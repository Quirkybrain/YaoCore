/*
 * YaoCore C-21 ClimateViewModel.
 * Producer: agent:implementation-engineer | Task: T-15 / wp-060-vm
 * Contract: DES-B §10.1.6, §10.3; CB §6.2/§6.3; DES-B §9.3
 *
 * The adapter is the only inbound/outbound AC vocabulary boundary. The view
 * model never forwards non-standard raw modes and clamps the temperature slider
 * to the adapter capability range (v1 16..30).
 */
import { AppErrors } from '../common/types/AppError';
import { NameValue } from '../common/types/NameValue';
import type { ClockPort, LoggerPort } from '../common/types/Ports';
import { DeviceAction, DeviceConstants } from '../common/constants/DeviceConstants';
import type { CommandValue } from '../common/utils/JsonAtom';
import { AcMode } from '../model/DeviceTypes';
import { DeviceControlCommand, StateVerification } from '../model/ControlModels';
import { DeviceStatePatch, DeviceStatePatchInit } from '../model/DeviceState';
import type { DeviceSnapshot } from '../model/DeviceState';
import { DeviceKey } from '../model/DeviceKey';
import type { DeviceRecord } from '../repository/DomainModels';
import { AcAdapterFactory } from '../service/ac/AcAdapterFactory';
import type { AcAdapter } from '../service/ac/AcAdapter';
import type { AcViewState } from '../service/ac/AcModels';
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
import { ThrottleGate } from './core/ThrottleGate';
import type { DeviceControlCoordinatorPort } from './ViewModelPorts';

const TAG: string = 'ClimateViewModel';
const THROTTLE_MS: number = 55;
const TIMEOUT_MS: number = 3000;
const SETTLE_MS: number = 320;

export class ClimateViewState {
  readonly phase: LoadPhase;
  readonly record?: DeviceRecord;
  readonly ac?: AcViewState;
  readonly control: ControlUiState;
  readonly modeOptions: ReadonlyArray<AcMode>;
  readonly error?: ViewModelError;
  readonly revision: number;

  constructor(phase: LoadPhase, control: ControlUiState, modeOptions: ReadonlyArray<AcMode>,
    revision: number, record?: DeviceRecord, ac?: AcViewState, error?: ViewModelError) {
    this.phase = phase;
    this.control = control;
    this.modeOptions = modeOptions;
    this.revision = revision;
    this.record = record;
    this.ac = ac;
    this.error = error;
  }
}

export class ClimateViewModel implements ViewModelBase<ClimateViewState> {
  private readonly devices: DeviceRepository;
  private readonly control: DeviceControlCoordinatorPort;
  private readonly i18n: I18nService;
  private readonly clock: ClockPort;
  private readonly timer: VmTimerPort;
  private readonly logger: LoggerPort;

  private state: ClimateViewState;
  private listeners: Array<(state: ClimateViewState) => void> = [];
  private key?: DeviceKey = undefined;
  private record?: DeviceRecord = undefined;
  private adapter?: AcAdapter = undefined;
  private revision: number = 0;
  private disposed: boolean = false;
  private token: number = 0;
  private timerId: number | undefined = undefined;
  private gate?: ThrottleGate = undefined;
  private gateOk: boolean = true;
  private gateExecution?: ControlExecution = undefined;
  private gateError?: ViewModelError = undefined;

  constructor(devices: DeviceRepository, control: DeviceControlCoordinatorPort,
    i18n: I18nService, clock: ClockPort, timer: VmTimerPort, logger: LoggerPort) {
    this.devices = devices;
    this.control = control;
    this.i18n = i18n;
    this.clock = clock;
    this.timer = timer;
    this.logger = logger;
    this.state = new ClimateViewState(LoadPhase.IDLE,
      ControlUiState.idle(new DeviceKey('gateway', 'device'), 0), [], 0);
  }

  getState(): ClimateViewState {
    return this.state;
  }

  subscribe(listener: (state: ClimateViewState) => void): () => void {
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
    this.publish(new ClimateViewState(LoadPhase.LOADING, this.controlState(), [],
      this.revision + 1));
    try {
      const record = await this.devices.getRecord(key);
      if (record === undefined) {
        this.fail(AppErrors.of('DEVICE_NOT_FOUND', []));
        return;
      }
      this.record = record;
      this.adapter = AcAdapterFactory.create(record.state.snapshot.brand);
      const ac = this.adapter.toViewState(ClimateViewModel.patchOf(record.state.snapshot));
      const confirmed = record.state.snapshot.targetTemperature;
      const control = new ControlUiState(key, DeviceAction.SET_TARGET_TEMPERATURE,
        ControlPhase.IDLE, this.revision + 1, confirmed);
      this.publish(new ClimateViewState(LoadPhase.READY, control,
        this.adapter.capabilities.supportedModes, this.revision + 1, record, ac));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async togglePower(): Promise<void> {
    const record = this.requireRecord();
    if (record === undefined) {
      return;
    }
    const on = record.state.snapshot.powerStatus !== true;
    await this.send(on ? DeviceAction.TURN_ON : DeviceAction.TURN_OFF, on);
  }

  async setMode(mode: AcMode): Promise<void> {
    if (this.state.modeOptions.indexOf(mode) < 0) {
      this.fail(AppErrors.of('CONFIGURATION_ERROR', [
        new NameValue('field', 'mode')]));
      return;
    }
    await this.send(DeviceAction.SET_MODE, mode);
  }

  beginTemperature(value: number): void {
    const record = this.requireRecord();
    if (record === undefined) {
      return;
    }
    this.disposeGate();
    this.gateOk = true;
    this.gateExecution = undefined;
    this.gateError = undefined;
    const clamped = this.clamp(value);
    this.token++;
    const confirmed = record.state.snapshot.targetTemperature;
    this.publish(new ClimateViewState(LoadPhase.READY,
      new ControlUiState(record.state.key, DeviceAction.SET_TARGET_TEMPERATURE,
        ControlPhase.PENDING, this.revision + 1, confirmed, clamped, this.clock.nowMs()),
      this.state.modeOptions, this.revision + 1, record, this.state.ac));
    this.gate = new ThrottleGate(this.timer, this.clock, THROTTLE_MS,
      (next: number): Promise<void> => this.dispatchTemperature(next));
  }

  updateTemperature(value: number): void {
    if (this.gate === undefined) {
      return;
    }
    const clamped = this.clamp(value);
    this.gate.onInput(clamped);
    const current = this.state.control;
    this.publish(new ClimateViewState(this.state.phase,
      new ControlUiState(this.key as DeviceKey, DeviceAction.SET_TARGET_TEMPERATURE,
        ControlPhase.PENDING, this.revision + 1, current.confirmedValue, clamped,
        current.pendingSinceMs), this.state.modeOptions, this.revision + 1, this.record,
      this.state.ac));
  }

  async endTemperature(value: number): Promise<void> {
    if (this.gate === undefined) {
      await this.send(DeviceAction.SET_TARGET_TEMPERATURE, this.clamp(value));
      return;
    }
    const gate = this.gate;
    const clamped = this.clamp(value);
    await gate.onCommit(clamped);
    if (this.disposed) {
      return;
    }
    this.gate = undefined;
    if (!this.gateOk) {
      this.applyRevert(this.gateError === undefined ?
        ViewModelSupport.viewError(AppErrors.of('GATEWAY_TIMEOUT', []), this.clock) :
        this.gateError);
      return;
    }
    const execution = this.gateExecution;
    const confirmed = execution === undefined ? clamped :
      ClimateViewModel.reportedTemperature(execution);
    this.publish(new ClimateViewState(LoadPhase.READY,
      new ControlUiState(this.key as DeviceKey, DeviceAction.SET_TARGET_TEMPERATURE,
        ControlPhase.COMMITTED, this.revision + 1,
        confirmed === undefined ? clamped : confirmed, undefined, undefined,
        execution === undefined ? undefined : execution.lan === undefined ? undefined :
          execution.lan.outcome, execution),
      this.state.modeOptions, this.revision + 1, this.record, this.state.ac));
  }

  settleRevert(): void {
    if (this.state.control.phase !== ControlPhase.REVERT) {
      return;
    }
    const current = this.state.control;
    this.publish(new ClimateViewState(this.state.phase,
      new ControlUiState(current.key, current.action, ControlPhase.IDLE, this.revision + 1,
        current.confirmedValue, undefined, undefined, current.lastOutcome, current.lastExecution,
        current.lastError), this.state.modeOptions, this.revision + 1, this.record,
      this.state.ac));
  }

  translateError(error: ViewModelError | undefined): string {
    return error === undefined ? '' : this.i18n.t(error.i18nKey);
  }

  dispose(): void {
    this.disposed = true;
    this.disposeGate();
    if (this.timerId !== undefined) {
      this.timer.clearTimer(this.timerId);
      this.timerId = undefined;
    }
    this.listeners.splice(0, this.listeners.length);
  }

  private async send(action: DeviceAction, value?: CommandValue): Promise<void> {
    const record = this.requireRecord();
    if (record === undefined) {
      return;
    }
    const token = ++this.token;
    this.clearTimer();
    this.publish(new ClimateViewState(this.state.phase,
      new ControlUiState(record.state.key, action, ControlPhase.PENDING, this.revision + 1,
        this.state.control.confirmedValue, value, this.clock.nowMs()), this.state.modeOptions,
      this.revision + 1, record, this.state.ac));
    this.timerId = this.timer.setTimer(TIMEOUT_MS, (): void => {
      if (this.disposed || token !== this.token) {
        return;
      }
      this.token++;
      this.applyRevert(ViewModelSupport.viewError(AppErrors.of('GATEWAY_TIMEOUT', []),
        this.clock));
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
        this.publish(new ClimateViewState(LoadPhase.READY,
          new ControlUiState(record.state.key, action, ControlPhase.COMMITTED,
            this.revision + 1, this.state.control.confirmedValue, undefined, undefined,
            execution.lan === undefined ? undefined : execution.lan.outcome, execution),
          this.state.modeOptions, this.revision + 1, this.record, this.state.ac));
        return;
      }
      this.applyRevert(this.errorOf(execution));
    } catch (error) {
      if (this.disposed || token !== this.token) {
        return;
      }
      this.clearTimer();
      this.applyRevert(ViewModelSupport.viewError(error as Object, this.clock));
    }
  }

  private async dispatchTemperature(value: number): Promise<void> {
    const record = this.record;
    if (record === undefined) {
      this.gateOk = false;
      this.gateError = ViewModelSupport.viewError(AppErrors.of('DEVICE_NOT_FOUND', []),
        this.clock);
      return;
    }
    try {
      const command = new DeviceControlCommand(record.state.key.gatewayId,
        record.state.key.deviceId, DeviceAction.SET_TARGET_TEMPERATURE, this.clock.nowMs(),
        value);
      const execution = await this.control.execute(command, record.state.familyId);
      this.gateExecution = execution;
      this.gateOk = DeviceControlCoordinator.succeeded(execution);
      this.gateError = this.gateOk ? undefined : this.errorOf(execution);
    } catch (error) {
      this.gateOk = false;
      this.gateError = ViewModelSupport.viewError(error as Object, this.clock);
    }
  }

  private applyRevert(error: ViewModelError): void {
    const current = this.state.control;
    this.publish(new ClimateViewState(this.state.phase,
      new ControlUiState(current.key, current.action, ControlPhase.REVERT,
        this.revision + 1, current.confirmedValue, undefined, undefined, current.lastOutcome,
        current.lastExecution, error), this.state.modeOptions, this.revision + 1, this.record,
      this.state.ac));
    this.clearTimer();
    this.timerId = this.timer.setTimer(SETTLE_MS, (): void => {
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

  private controlState(): ControlUiState {
    const key = this.key === undefined ? new DeviceKey('gateway', 'device') : this.key;
    return new ControlUiState(key, DeviceAction.SET_TARGET_TEMPERATURE, ControlPhase.IDLE,
      this.revision + 1);
  }

  private clamp(value: number): number {
    const adapter = this.adapter;
    const min = adapter === undefined ? DeviceConstants.DEFAULT_TARGET_TEMP_MIN :
      adapter.capabilities.minTargetTemperature;
    const max = adapter === undefined ? DeviceConstants.DEFAULT_TARGET_TEMP_MAX :
      adapter.capabilities.maxTargetTemperature;
    const rounded = Math.round(value);
    if (!Number.isFinite(rounded)) {
      return min;
    }
    return rounded < min ? min : rounded > max ? max : rounded;
  }

  private clearTimer(): void {
    if (this.timerId !== undefined) {
      this.timer.clearTimer(this.timerId);
      this.timerId = undefined;
    }
  }

  private disposeGate(): void {
    if (this.gate !== undefined) {
      this.gate.dispose();
      this.gate = undefined;
    }
  }

  private fail(error: Object): void {
    const viewError = ViewModelSupport.viewError(error, this.clock);
    this.logger.warn(TAG, 'view_model_error', [new NameValue('code', viewError.error.code)]);
    this.publish(new ClimateViewState(LoadPhase.ERROR, this.state.control,
      this.state.modeOptions, this.revision + 1, this.record, this.state.ac, viewError));
  }

  private publish(next: ClimateViewState): void {
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

  private static patchOf(snapshot: DeviceSnapshot): DeviceStatePatch {
    const init = new DeviceStatePatchInit();
    init.deviceId = snapshot.deviceId;
    init.isOnline = snapshot.isOnline;
    init.powerStatus = snapshot.powerStatus;
    init.openStatus = snapshot.openStatus;
    init.brightness = snapshot.brightness;
    init.color = snapshot.color;
    init.temperature = snapshot.temperature;
    init.humidity = snapshot.humidity;
    init.presence = snapshot.presence;
    init.targetTemperature = snapshot.targetTemperature;
    init.mode = snapshot.mode;
    init.modeStandard = snapshot.modeStandard;
    init.stateSource = snapshot.stateSource;
    init.stateSourceKnown = snapshot.stateSourceKnown;
    init.triggerDeviceId = snapshot.triggerDeviceId;
    init.automationId = snapshot.automationId;
    init.lastRequestId = snapshot.lastRequestId;
    init.lastSeq = snapshot.lastSeq;
    init.updatedAt = snapshot.updatedAt;
    return DeviceStatePatch.create(init);
  }

  private static reportedTemperature(execution: ControlExecution): number | undefined {
    if (execution.apply !== undefined && execution.apply.record !== undefined) {
      return execution.apply.record.state.snapshot.targetTemperature;
    }
    if (execution.lan !== undefined && execution.lan.outcome !== undefined &&
      execution.lan.outcome.reportedState !== undefined) {
      return execution.lan.outcome.reportedState.targetTemperature;
    }
    if (execution.cloud !== undefined && execution.cloud.verdict.reportedState !== undefined) {
      return execution.cloud.verdict.reportedState.targetTemperature;
    }
    return undefined;
  }
}
