/*
 * YaoCore C-11 SceneExecutor.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §6.1.4, §6.3.1-§6.3.3
 *
 * Strictly serial scene execution through DeviceControlPort. Preflight runs
 * before the first command; a step failure stops the rest (SKIPPED) and never
 * rolls back already executed steps. Cancellation is checked before every step
 * and during delayMs; an in-flight request is allowed to settle.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import type { CancellationToken, ClockPort, LoggerPort } from '../../common/types/Ports';
import { DeviceControlCommand, ControlOutcome, StateVerification } from '../../model/ControlModels';
import { Scene, SceneAction } from '../../model/FamilyModels';
import { DeviceRepository } from '../../repository/DeviceRepository';
import type { DeviceControlPort } from '../../repository/DomainPorts';
import type { GatewayRoutePort } from '../../repository/GatewayPorts';
import {
  ControlApplyContext,
  SceneExecutionPolicy,
  SceneExecutionProgress,
  SceneExecutionResult,
  SceneRunState,
  SceneStepResult,
  SceneStepState
} from '../../repository/DomainModels';
import type { SceneTimerPort } from './SceneTimerPort';
import { SceneValidation } from './SceneValidation';

export class RunCancellation implements CancellationToken {
  private flag: boolean = false;
  private readonly listeners: Array<() => void> = [];

  get cancelled(): boolean {
    return this.flag;
  }

  onCancel(listener: () => void): void {
    if (this.flag) {
      listener();
      return;
    }
    this.listeners.push(listener);
  }

  throwIfCancelled(): void {
    if (this.flag) {
      throw AppErrors.of('SCENE_CANCELLED', []);
    }
  }

  cancel(): void {
    if (this.flag) {
      return;
    }
    this.flag = true;
    const snapshot = this.listeners.slice(0);
    this.listeners.splice(0, this.listeners.length);
    for (let index = 0; index < snapshot.length; index++) {
      snapshot[index]();
    }
  }
}

export class SceneExecutor {
  private readonly control: DeviceControlPort;
  private readonly devices: DeviceRepository;
  private readonly routes: GatewayRoutePort;
  private readonly clock: ClockPort;
  private readonly timer: SceneTimerPort;
  private readonly logger: LoggerPort;

  constructor(control: DeviceControlPort, devices: DeviceRepository, routes: GatewayRoutePort,
    clock: ClockPort, timer: SceneTimerPort, logger: LoggerPort) {
    this.control = control;
    this.devices = devices;
    this.routes = routes;
    this.clock = clock;
    this.timer = timer;
    this.logger = logger;
  }

  async execute(scene: Scene, runId: string, policy: SceneExecutionPolicy,
    listener?: (progress: SceneExecutionProgress) => void,
    cancellation?: CancellationToken): Promise<SceneExecutionResult> {
    const startedAt = this.clock.nowMs();
    if (scene.actions.length === 0) {
      const error = AppErrors.of('SCENE_EMPTY', []);
      return new SceneExecutionResult(runId, scene.sceneId, scene.sceneName,
        SceneRunState.FAILED, [], startedAt, 0, 0, undefined, this.clock.nowMs(), error);
    }
    const steps: SceneStepResult[] = [];
    for (let index = 0; index < scene.actions.length; index++) {
      steps.push(new SceneStepResult(index, scene.actions[index], SceneStepState.PENDING));
    }
    this.emit(listener, runId, scene, SceneRunState.PREFLIGHT, -1, steps, 0, 0);

    const preflight = await SceneValidation.preflight(scene, this.devices, this.routes);
    if (!preflight.ok) {
      const cause = preflight.error === undefined ?
        AppErrors.of('SCENE_REFERENCE_INVALID', []) : preflight.error;
      const error = AppErrors.of('SCENE_PREFLIGHT_FAILED',
        [new NameValue('failedIndex', String(preflight.failedIndex)),
          new NameValue('cause', cause.code)]);
      for (let index = 0; index < steps.length; index++) {
        steps[index] = steps[index].withState(index === preflight.failedIndex ?
          SceneStepState.FAILED : SceneStepState.SKIPPED,
          undefined, this.clock.nowMs(), undefined, undefined,
          index === preflight.failedIndex ? cause : undefined);
      }
      this.emit(listener, runId, scene, SceneRunState.FAILED, preflight.failedIndex,
        steps, 0, 0);
      return new SceneExecutionResult(runId, scene.sceneId, scene.sceneName,
        SceneRunState.FAILED, steps, startedAt, 0, 0, preflight.failedIndex,
        this.clock.nowMs(), error);
    }

    this.emit(listener, runId, scene, SceneRunState.RUNNING, -1, steps, 0, 0);
    let executed = 0;
    let succeeded = 0;
    for (let index = 0; index < scene.actions.length; index++) {
      const action = scene.actions[index];
      if (this.isCancelled(cancellation)) {
        return this.cancelledResult(runId, scene, steps, index, startedAt, executed, succeeded,
          listener);
      }
      if (this.clock.nowMs() - startedAt > policy.totalTimeoutMs) {
        return this.failAt(runId, scene, steps, index, startedAt, executed, succeeded,
          AppErrors.of('SCENE_STEP_FAILED',
            [new NameValue('index', String(index)), new NameValue('cause', 'TOTAL_TIMEOUT')]),
          listener);
      }
      if (action.delayMs !== undefined && action.delayMs > 0) {
        const cancelled = await this.waitDelay(action.delayMs, cancellation);
        if (cancelled) {
          return this.cancelledResult(runId, scene, steps, index, startedAt, executed, succeeded,
            listener);
        }
      }
      steps[index] = steps[index].withState(SceneStepState.RUNNING, this.clock.nowMs());
      this.emit(listener, runId, scene, SceneRunState.RUNNING, index, steps, executed, succeeded);

      const command = new DeviceControlCommand(action.gatewayId, action.targetDeviceId,
        action.action, this.clock.nowMs(), action.value);
      let outcome: ControlOutcome | undefined = undefined;
      let failure: AppError | undefined = undefined;
      try {
        outcome = await this.sendWithTimeout(command, policy.stepTimeoutMs);
        executed++;
        if (outcome === undefined) {
          failure = AppErrors.of('SCENE_STEP_FAILED',
            [new NameValue('index', String(index)),
              new NameValue('cause', 'GATEWAY_TIMEOUT')]);
        }
      } catch (error) {
        executed++;
        failure = error instanceof AppError ? error : AppErrors.of('SCENE_STEP_FAILED',
          [new NameValue('index', String(index))]);
      }
      if (outcome !== undefined && failure === undefined) {
        if (!outcome.ackAccepted) {
          failure = AppErrors.of('SCENE_STEP_FAILED',
            [new NameValue('index', String(index)), new NameValue('cause', 'ACK_NOT_ACCEPTED')]);
        } else if (outcome.stateVerification === StateVerification.MISMATCH) {
          failure = AppErrors.of('SCENE_STEP_FAILED',
            [new NameValue('index', String(index)), new NameValue('cause', 'MISMATCH')]);
        }
      }
      if (failure !== undefined) {
        steps[index] = steps[index].withState(SceneStepState.FAILED,
          undefined, this.clock.nowMs(), outcome, outcome === undefined ? undefined :
            outcome.stateVerification, failure);
        return this.failAt(runId, scene, steps, index, startedAt, executed, succeeded,
          failure, listener);
      }
      if (outcome !== undefined) {
        steps[index] = steps[index].withState(SceneStepState.SUCCEEDED,
          undefined, this.clock.nowMs(), outcome, outcome.stateVerification);
        succeeded++;
        this.emit(listener, runId, scene, SceneRunState.RUNNING, index, steps, executed, succeeded);
        await this.applyAckBestEffort(scene, action, command, outcome);
      }
      if (this.isCancelled(cancellation)) {
        return this.cancelledResult(runId, scene, steps, index + 1, startedAt, executed, succeeded,
          listener);
      }
    }
    this.emit(listener, runId, scene, SceneRunState.SUCCEEDED, scene.actions.length - 1,
      steps, executed, succeeded);
    return new SceneExecutionResult(runId, scene.sceneId, scene.sceneName,
      SceneRunState.SUCCEEDED, steps, startedAt, executed, succeeded, undefined,
      this.clock.nowMs(), undefined);
  }

  private failAt(runId: string, scene: Scene, steps: SceneStepResult[], failedIndex: number,
    startedAt: number, executed: number, succeeded: number, error: AppError,
    listener?: (progress: SceneExecutionProgress) => void): SceneExecutionResult {
    for (let index = failedIndex + 1; index < steps.length; index++) {
      steps[index] = steps[index].withState(SceneStepState.SKIPPED);
    }
    const state = succeeded > 0 ? SceneRunState.PARTIAL_FAILED : SceneRunState.FAILED;
    this.emit(listener, runId, scene, state, failedIndex, steps, executed, succeeded);
    // Local failure never rolls back already executed steps (FR-SCN-001).
    return new SceneExecutionResult(runId, scene.sceneId, scene.sceneName, state,
      steps, startedAt, executed, succeeded, failedIndex, this.clock.nowMs(), error);
  }

  private cancelledResult(runId: string, scene: Scene, steps: SceneStepResult[],
    fromIndex: number, startedAt: number, executed: number, succeeded: number,
    listener?: (progress: SceneExecutionProgress) => void): SceneExecutionResult {
    for (let index = fromIndex; index < steps.length; index++) {
      if (steps[index].state === SceneStepState.PENDING) {
        steps[index] = steps[index].withState(SceneStepState.SKIPPED);
      }
    }
    const error = AppErrors.of('SCENE_CANCELLED', []);
    this.emit(listener, runId, scene, SceneRunState.CANCELLED, fromIndex, steps, executed,
      succeeded);
    return new SceneExecutionResult(runId, scene.sceneId, scene.sceneName,
      SceneRunState.CANCELLED, steps, startedAt, executed, succeeded, undefined,
      this.clock.nowMs(), error);
  }

  private async waitDelay(ms: number, cancellation?: CancellationToken): Promise<boolean> {
    if (cancellation === undefined) {
      await this.timer.delay(ms);
      return false;
    }
    if (cancellation.cancelled) {
      return true;
    }
    const delay = this.timer.delay(ms);
    const cancelled = new Promise<boolean>((resolve: (value: boolean) => void): void => {
      cancellation.onCancel((): void => {
        resolve(true);
      });
    });
    const finished = delay.then((): boolean => false);
    const result = await Promise.race([finished, cancelled]);
    return result;
  }

  private async sendWithTimeout(command: DeviceControlCommand,
    timeoutMs: number): Promise<ControlOutcome | undefined> {
    if (timeoutMs <= 0) {
      return this.control.send(command);
    }
    const send: Promise<ControlOutcome> = this.control.send(command);
    const timeout: Promise<ControlOutcome | undefined> = this.timer.delay(timeoutMs)
      .then((): ControlOutcome | undefined => undefined);
    return Promise.race([send, timeout]);
  }

  private async applyAckBestEffort(scene: Scene, action: SceneAction,
    command: DeviceControlCommand, outcome: ControlOutcome): Promise<void> {
    try {
      const context = new ControlApplyContext(scene.familyId, action.gatewayId,
        action.targetDeviceId, action.action, command.requestedAtMs, action.value);
      await this.devices.applyControlAck(context, outcome);
    } catch (error) {
      // The gateway ACK already succeeded; a local state-application failure is
      // diagnostic, not a reason to discard the executed step.
      this.logger.warn('SceneExecutor', 'ack_state_apply_failed',
        [new NameValue('gatewayId', action.gatewayId),
          new NameValue('deviceId', action.targetDeviceId)]);
    }
  }

  private isCancelled(cancellation?: CancellationToken): boolean {
    return cancellation !== undefined && cancellation.cancelled;
  }

  private emit(listener: ((progress: SceneExecutionProgress) => void) | undefined,
    runId: string, scene: Scene, state: SceneRunState, currentIndex: number,
    steps: ReadonlyArray<SceneStepResult>, executed: number, succeeded: number): void {
    if (listener === undefined) {
      return;
    }
    listener(new SceneExecutionProgress(runId, scene.sceneId, state, currentIndex,
      steps.slice(0), executed, succeeded));
  }
}
