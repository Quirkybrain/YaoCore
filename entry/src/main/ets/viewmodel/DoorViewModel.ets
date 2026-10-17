/*
 * YaoCore C-21 DoorViewModel.
 * Producer: agent:implementation-engineer | Task: T-15 / wp-060-vm
 * Contract: DES-B §10.1.7, §10.3.3; ADR-004 §6; D-016
 *
 * The VM only composes control execution and the door confirmation tracker.
 * The tracker owns the four-stage confirmation and 10s contact timeout; the VM
 * never upgrades an unconfirmed lock to SECURED.
 */
import { AppErrors } from '../common/types/AppError';
import { NameValue } from '../common/types/NameValue';
import type { ClockPort, LoggerPort } from '../common/types/Ports';
import { DeviceAction } from '../common/constants/DeviceConstants';
import { DeviceKey } from '../model/DeviceKey';
import { DeviceControlCommand, StateVerification } from '../model/ControlModels';
import type { DeviceRecord, DeviceChangeEvent } from '../repository/DomainModels';
import {
  ControlExecution,
  ControlPhase,
  ControlUiState,
  LoadPhase,
  ViewModelError,
  ViewModelSupport
} from './core/ViewModelCore';
import type {
  ViewModelBase,
  VmTimerPort
} from './core/ViewModelCore';
import { I18nService } from '../service/i18n/I18nService';
import { DeviceRepository } from '../repository/DeviceRepository';
import { DeviceControlCoordinator } from './core/DeviceControlCoordinator';
import {
  DoorConfirmationPolicy,
  DoorConfirmationTracker,
  DoorLinkConfig,
  DoorStage,
  DoorUiState
} from './core/DoorConfirmationTracker';
import type { DeviceControlCoordinatorPort } from './ViewModelPorts';

const TAG: string = 'DoorViewModel';
const TIMEOUT_MS: number = 3000;
const SETTLE_MS: number = 320;

export class DoorViewState {
  readonly phase: LoadPhase;
  readonly record?: DeviceRecord;
  readonly door: DoorUiState;
  readonly control: ControlUiState;
  readonly error?: ViewModelError;
  readonly revision: number;

  constructor(phase: LoadPhase, door: DoorUiState, control: ControlUiState, revision: number,
    record?: DeviceRecord, error?: ViewModelError) {
    this.phase = phase;
    this.door = door;
    this.control = control;
    this.revision = revision;
    this.record = record;
    this.error = error;
  }
}

export class DoorViewModel implements ViewModelBase<DoorViewState> {
  private readonly devices: DeviceRepository;
  private readonly control: DeviceControlCoordinatorPort;
  private readonly i18n: I18nService;
  private readonly clock: ClockPort;
  private readonly timer: VmTimerPort;
  private readonly logger: LoggerPort;
  private readonly tracker: DoorConfirmationTracker;

  private state: DoorViewState;
  private listeners: Array<(state: DoorViewState) => void> = [];
  private key?: DeviceKey = undefined;
  private record?: DeviceRecord = undefined;
  private link: DoorLinkConfig = DoorLinkConfig.none();
  private revision: number = 0;
  private disposed: boolean = false;
  private token: number = 0;
  private timeoutId: number | undefined = undefined;
  private settleId: number | undefined = undefined;

  constructor(devices: DeviceRepository, control: DeviceControlCoordinatorPort,
    i18n: I18nService, clock: ClockPort, timer: VmTimerPort, logger: LoggerPort) {
    this.devices = devices;
    this.control = control;
    this.i18n = i18n;
    this.clock = clock;
    this.timer = timer;
    this.logger = logger;
    this.tracker = new DoorConfirmationTracker(clock, timer,
      DoorConfirmationPolicy.defaults());
    this.state = new DoorViewState(LoadPhase.IDLE, this.tracker.getState(),
      ControlUiState.idle(new DeviceKey('gateway', 'device'), 0), 0);
  }

  getState(): DoorViewState {
    return this.state;
  }

  subscribe(listener: (state: DoorViewState) => void): () => void {
    this.listeners.push(listener);
    return (): void => {
      const index = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    };
  }

  async load(key: DeviceKey): Promise<void> {
    this.key = key;
    this.publish(this.copy(LoadPhase.LOADING, this.controlIdle(key), this.tracker.getState(),
      undefined));
    try {
      const record = await this.devices.getRecord(key);
      if (record === undefined) {
        this.fail(AppErrors.of('DEVICE_NOT_FOUND', []));
        return;
      }
      this.record = record;
      this.publish(new DoorViewState(LoadPhase.READY, this.tracker.getState(),
        this.controlIdle(key), this.revision + 1, record, undefined));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async lock(): Promise<void> {
    await this.applyLock(DeviceAction.CLOSE, true);
  }

  async unlock(): Promise<void> {
    await this.applyLock(DeviceAction.OPEN, true);
  }

  async configureLink(link: DoorLinkConfig): Promise<void> {
    this.link = link;
    this.tracker.configure(link);
    this.publish(this.copy(this.state.phase, this.state.control, this.tracker.getState(),
      this.state.error));
  }

  onDeviceChanged(event: DeviceChangeEvent): void {
    if (this.disposed) {
      return;
    }
    if (this.key !== undefined && ViewModelSupport.isSameKey(event.key, this.key)) {
      this.devices.getRecord(event.key).then((record: DeviceRecord | undefined): void => {
        if (record !== undefined && !this.disposed) {
          this.record = record;
          this.publish(this.copy(this.state.phase, this.state.control, this.tracker.getState(),
            this.state.error));
        }
      }).catch((): void => undefined);
      return;
    }
    if (this.link.contactSensorKey !== undefined &&
      ViewModelSupport.isSameKey(event.key, this.link.contactSensorKey)) {
      this.devices.getRecord(event.key).then((record: DeviceRecord | undefined): void => {
        if (record === undefined || this.disposed) {
          return;
        }
        if (!record.state.snapshot.isOnline) {
          this.tracker.onContactOffline();
        } else if (record.state.snapshot.openStatus !== undefined) {
          this.tracker.onContactState(record.state.snapshot.openStatus === true, true);
        }
        this.publish(this.copy(this.state.phase, this.state.control, this.tracker.getState(),
          this.state.error));
      }).catch((): void => undefined);
    }
  }

  dismissAlert(): void {
    this.tracker.dismissAlert();
    this.publish(this.copy(this.state.phase, this.state.control, this.tracker.getState(),
      this.state.error));
  }

  settleRevert(): void {
    this.clearSettle();
    if (this.state.control.phase === ControlPhase.REVERT) {
      this.publish(this.copy(this.state.phase,
        this.controlIdle(this.state.control.key), this.tracker.getState(), this.state.error));
    }
    this.tracker.settleFailed();
  }

  translateError(error: ViewModelError | undefined): string {
    return error === undefined ? '' : this.i18n.t(error.i18nKey);
  }

  dispose(): void {
    this.disposed = true;
    this.clearTimer();
    this.clearSettle();
    this.tracker.dispose();
    this.listeners.splice(0, this.listeners.length);
  }

  private async applyLock(action: DeviceAction, value: boolean): Promise<void> {
    const record = this.requireRecord();
    if (record === undefined) {
      return;
    }
    const token = ++this.token;
    this.clearTimer();
    if (action === DeviceAction.CLOSE) {
      this.tracker.startLock(this.link);
      if (this.link.contactSensorKey !== undefined) {
        const contact = await this.devices.getRecord(this.link.contactSensorKey);
        if (contact !== undefined && !contact.state.snapshot.isOnline) {
          this.tracker.onContactOffline();
        }
      }
    }
    this.publish(this.copy(this.state.phase,
      new ControlUiState(record.state.key, action, ControlPhase.PENDING, this.revision + 1,
        this.state.control.confirmedValue, value), this.tracker.getState(), undefined));
    this.timeoutId = this.timer.setTimer(TIMEOUT_MS, (): void => {
      if (this.disposed || token !== this.token) {
        return;
      }
      this.token++;
      const error = ViewModelSupport.viewError(AppErrors.of('GATEWAY_TIMEOUT', []), this.clock);
      if (action === DeviceAction.CLOSE) {
        this.tracker.markUnlockFailed(error);
      }
      this.applyRevert(error);
    });
    const command = new DeviceControlCommand(record.state.key.gatewayId,
      record.state.key.deviceId, action, this.clock.nowMs(), value);
    try {
      const execution = await this.control.execute(command, record.state.familyId);
      if (this.disposed || token !== this.token) {
        return;
      }
      this.clearTimer();
      if (DeviceControlCoordinator.succeeded(execution)) {
        if (action === DeviceAction.CLOSE) {
          this.tracker.onResult(execution);
        } else {
          this.tracker.onUnlockResult(execution);
        }
        const door = this.tracker.getState();
        // F-02: the control ACK is not a door-state confirmation. A tracker
        // FAILED verdict (e.g. CLOSE reported open=true) must revert, never
        // publish COMMITTED; an UNVERIFIED verdict keeps COMMITTED only as
        // "executed, state not reported" and never as OPEN.
        if (door.stage === DoorStage.FAILED) {
          this.applyRevert(door.error === undefined ? this.errorOf(execution) : door.error);
          return;
        }
        // F-02: confirmedValue comes from the reported door state, never from
        // the requested value. UNVERIFIED keeps the previous confirmed state.
        const reported = DoorConfirmationTracker.reportedOpen(execution);
        const confirmed = reported === undefined ? this.state.control.confirmedValue : reported;
        this.publish(this.copy(LoadPhase.READY,
          new ControlUiState(record.state.key, action, ControlPhase.COMMITTED,
            this.revision + 1, confirmed, undefined, undefined,
            execution.lan === undefined ? undefined : execution.lan.outcome, execution),
          door, undefined));
        return;
      }
      const error = this.errorOf(execution);
      if (action === DeviceAction.CLOSE) {
        this.tracker.onResult(execution);
      } else {
        this.tracker.markUnlockFailed(error);
      }
      this.applyRevert(error);
    } catch (error) {
      if (this.disposed || token !== this.token) {
        return;
      }
      this.clearTimer();
      const viewError = ViewModelSupport.viewError(error as Object, this.clock);
      if (action === DeviceAction.CLOSE) {
        this.tracker.markUnlockFailed(viewError);
      } else {
        this.tracker.markUnlockFailed(viewError);
      }
      this.applyRevert(viewError);
    }
  }

  private applyRevert(error: ViewModelError): void {
    const current = this.state.control;
    this.publish(this.copy(this.state.phase,
      new ControlUiState(current.key, current.action, ControlPhase.REVERT,
        this.revision + 1, current.confirmedValue, undefined, undefined, current.lastOutcome,
        current.lastExecution, error), this.tracker.getState(), error));
    this.clearSettle();
    this.settleId = this.timer.setTimer(SETTLE_MS, (): void => {
      if (this.disposed) {
        return;
      }
      this.settleRevert();
    });
  }

  private errorOf(execution: ControlExecution): ViewModelError {
    if (execution.error !== undefined) {
      return ViewModelError.fromError(execution.error, this.clock.nowMs());
    }
    const mismatch = DeviceControlCoordinator.verificationFor(execution) ===
      StateVerification.MISMATCH;
    return ViewModelError.fromError(AppErrors.of(
      mismatch ? 'ACK_STATE_MISMATCH' : 'ACK_PROTOCOL_VIOLATION', []), this.clock.nowMs());
  }

  private requireRecord(): DeviceRecord | undefined {
    if (this.record === undefined) {
      this.fail(AppErrors.of('DEVICE_NOT_FOUND', []));
      return undefined;
    }
    return this.record;
  }

  private controlIdle(key: DeviceKey): ControlUiState {
    return new ControlUiState(key, DeviceAction.CLOSE, ControlPhase.IDLE, this.revision + 1);
  }

  private clearTimer(): void {
    if (this.timeoutId !== undefined) {
      this.timer.clearTimer(this.timeoutId);
      this.timeoutId = undefined;
    }
  }

  private clearSettle(): void {
    if (this.settleId !== undefined) {
      this.timer.clearTimer(this.settleId);
      this.settleId = undefined;
    }
  }

  private fail(error: Object): void {
    const viewError = ViewModelSupport.viewError(error, this.clock);
    this.logger.warn(TAG, 'view_model_error', [new NameValue('code', viewError.error.code)]);
    this.publish(this.copy(LoadPhase.ERROR, this.state.control, this.tracker.getState(),
      viewError));
  }

  private copy(phase: LoadPhase, control: ControlUiState, door: DoorUiState,
    error: ViewModelError | undefined): DoorViewState {
    return new DoorViewState(phase, door, control, this.revision + 1, this.record, error);
  }

  private publish(next: DoorViewState): void {
    this.revision = next.revision;
    this.state = next;
    for (let index = 0; index < this.listeners.length; index++) {
      try {
        this.listeners[index](next);
      } catch (error) {
        this.logger.warn(TAG, 'listener_failed',
          [new NameValue('code', ViewModelSupport.codeOf(error as Object))]);
      }
    }
  }
}
