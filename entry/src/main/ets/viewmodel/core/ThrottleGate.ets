/*
 * YaoCore C-21 ThrottleGate (55ms coalescing + TouchUp strong sync).
 * Producer: agent:implementation-engineer | Task: T-15 / wp-060-vm
 * Contract: DES-B §10.1.4, §10.3.2; UIUX §4.4; PF-02
 *
 * At most one dispatch is in flight. While a dispatch is in flight new inputs
 * only replace `latest`; the completion immediately dispatches the newest
 * value. `onCommit` (TouchUp) never drops the final value and waits until the
 * final dispatch completed. `cancel` invalidates any late completion so a
 * disposed page cannot mutate state.
 */
import type { ClockPort } from '../../common/types/Ports';
import { AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import type { VmTimerPort } from './ViewModelCore';

export enum ThrottlePhase {
  IDLE = 'IDLE',
  COALESCING = 'COALESCING',
  IN_FLIGHT = 'IN_FLIGHT'
}

type DispatchComplete = (failed: boolean) => void;

export class ThrottleGate {
  private readonly timer: VmTimerPort;
  private readonly clock: ClockPort;
  private readonly throttleMs: number;
  private readonly dispatch: (value: number) => Promise<void>;

  private phase: ThrottlePhase = ThrottlePhase.IDLE;
  private latest: number | undefined = undefined;
  private lastDispatched: number | undefined = undefined;
  private timerId: number | undefined = undefined;
  private commitTarget: number | undefined = undefined;
  private generation: number = 0;
  private waiters: Array<DispatchComplete> = [];
  private disposed: boolean = false;
  private lastFailed: boolean = false;
  private lastDispatchAtMs: number | undefined = undefined;

  constructor(timer: VmTimerPort, clock: ClockPort, throttleMs: number,
    dispatch: (value: number) => Promise<void>) {
    if (!Number.isFinite(throttleMs) || throttleMs <= 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'throttleMs')]);
    }
    this.timer = timer;
    this.clock = clock;
    this.throttleMs = throttleMs;
    this.dispatch = dispatch;
  }

  onInput(value: number): void {
    if (this.disposed || !Number.isFinite(value)) {
      return;
    }
    this.latest = value;
    if (this.phase === ThrottlePhase.IN_FLIGHT) {
      return;
    }
    this.phase = ThrottlePhase.COALESCING;
    this.schedule();
  }

  async onCommit(value: number): Promise<void> {
    if (this.disposed || !Number.isFinite(value)) {
      return;
    }
    this.latest = value;
    this.commitTarget = value;
    this.clearTimer();
    if (this.phase === ThrottlePhase.IDLE && !this.lastFailed &&
      this.lastDispatched === value) {
      // The coalesced dispatch already sent exactly this final value.
      this.commitTarget = undefined;
      return;
    }
    if (this.phase === ThrottlePhase.IN_FLIGHT) {
      return new Promise<void>((resolve: () => void): void => {
        this.waiters.push((failed: boolean): void => {
          resolve();
        });
      });
    }
    await this.dispatchLatest();
  }

  async onInFlightFinished(): Promise<void> {
    if (this.phase !== ThrottlePhase.IN_FLIGHT) {
      return;
    }
    await this.finishInFlight(this.generation);
  }

  cancel(): void {
    this.generation++;
    this.clearTimer();
    this.phase = ThrottlePhase.IDLE;
    this.latest = undefined;
    this.commitTarget = undefined;
    this.settleWaiters(false);
  }

  getPhase(): ThrottlePhase {
    return this.phase;
  }

  getLatest(): number | undefined {
    return this.latest;
  }

  getLastDispatched(): number | undefined {
    return this.lastDispatched;
  }

  getLastFailed(): boolean {
    return this.lastFailed;
  }

  getLastDispatchAtMs(): number | undefined {
    return this.lastDispatchAtMs;
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.cancel();
  }

  private schedule(): void {
    this.clearTimer();
    this.timerId = this.timer.setTimer(this.throttleMs, (): void => {
      this.timerId = undefined;
      if (this.phase === ThrottlePhase.COALESCING) {
        // The dispatch closure belongs to the view model and catches its own
        // failures; the returned promise is intentionally not awaited here.
        this.dispatchLatest().catch((): void => undefined);
      }
    });
  }

  private clearTimer(): void {
    if (this.timerId !== undefined) {
      this.timer.clearTimer(this.timerId);
      this.timerId = undefined;
    }
  }

  private async dispatchLatest(): Promise<void> {
    if (this.disposed) {
      this.phase = ThrottlePhase.IDLE;
      this.settleWaiters(false);
      return;
    }
    const value = this.latest;
    if (value === undefined) {
      this.phase = ThrottlePhase.IDLE;
      this.settleWaiters(false);
      return;
    }
    const generation = this.generation;
    this.phase = ThrottlePhase.IN_FLIGHT;
    this.lastDispatched = value;
    this.lastFailed = false;
    this.lastDispatchAtMs = this.clock.nowMs();
    try {
      await this.dispatch(value);
    } catch (error) {
      this.lastFailed = true;
    }
    if (generation !== this.generation || this.disposed) {
      // cancel() already reset the gate; a late network result must not cause
      // another dispatch or mutate confirmed state.
      this.phase = ThrottlePhase.IDLE;
      this.settleWaiters(this.lastFailed);
      return;
    }
    await this.finishInFlight(generation);
  }

  private async finishInFlight(generation: number): Promise<void> {
    if (generation !== this.generation) {
      this.phase = ThrottlePhase.IDLE;
      this.settleWaiters(this.lastFailed);
      return;
    }
    if (this.lastFailed) {
      this.phase = ThrottlePhase.IDLE;
      this.commitTarget = undefined;
      this.settleWaiters(true);
      return;
    }
    const target = this.commitTarget;
    const latest = this.latest;
    if (target !== undefined && target === latest && target === this.lastDispatched) {
      // TouchUp final value has been dispatched.
      this.commitTarget = undefined;
      this.phase = ThrottlePhase.IDLE;
      this.settleWaiters(false);
      return;
    }
    if (target !== undefined && target === latest) {
      // TouchUp arrived while a different value was in flight: send the final
      // value now, even if an earlier coalesced value existed.
      await this.dispatchLatest();
      return;
    }
    if (latest !== undefined && latest !== this.lastDispatched) {
      await this.dispatchLatest();
      return;
    }
    this.phase = ThrottlePhase.IDLE;
    this.settleWaiters(false);
  }

  private settleWaiters(failed: boolean): void {
    const waiters = this.waiters;
    this.waiters = [];
    for (let index = 0; index < waiters.length; index++) {
      waiters[index](failed);
    }
  }
}
