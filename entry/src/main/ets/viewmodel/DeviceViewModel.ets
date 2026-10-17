/*
 * YaoCore C-21 DeviceViewModel.
 * Producer: agent:implementation-engineer | Task: T-15 / wp-060-vm
 * Contract: DES-B §10.1.3, §10.3.1, §10.3.2; FR-DEV-001/002; D-019
 *
 * Three-phase anti-optimistic control:
 *   IDLE -> PENDING (UI only) -> COMMITTED only after ACK accepted and the
 *   reported state is not MISMATCH; otherwise REVERT to the last confirmed
 *   value. A 3s VM timeout reverts without retrying. Continuous controls use
 *   the 55ms ThrottleGate and TouchUp final-value guarantee.
 */
import { AppErrors } from '../common/types/AppError';
import { NameValue } from '../common/types/NameValue';
import type { ClockPort, LoggerPort } from '../common/types/Ports';
import { DeviceAction } from '../common/constants/DeviceConstants';
import type { CommandValue } from '../common/utils/JsonAtom';
import { DeviceKey } from '../model/DeviceKey';
import { DeviceControlCommand, StateVerification } from '../model/ControlModels';
import type { DeviceSnapshot, DeviceStatePatch } from '../model/DeviceState';
import type { Room } from '../model/FamilyModels';
import type { DeviceRecord } from '../repository/DomainModels';
import {
  ControlExecution,
  ControlPhase,
  ControlUiState,
  DeviceFilter,
  DeviceFilterKind,
  LoadPhase,
  ViewModelError,
  ViewModelSupport
} from './core/ViewModelCore';
import type {
  ViewModelBase,
  VmTimerPort
} from './core/ViewModelCore';
import { I18nService } from '../service/i18n/I18nService';
import { RoomService } from '../service/room/RoomService';
import { DeviceRepository } from '../repository/DeviceRepository';
import {
  DeviceControlCoordinator
} from './core/DeviceControlCoordinator';
import { ThrottleGate } from './core/ThrottleGate';
import type { DeviceControlCoordinatorPort } from './ViewModelPorts';

const TAG: string = 'DeviceViewModel';
const THROTTLE_MS: number = 55;
const CONTROL_TIMEOUT_MS: number = 3000;
const REVERT_SETTLE_MS: number = 320;

export class DeviceViewState {
  readonly phase: LoadPhase;
  readonly filter: DeviceFilter;
  readonly records: ReadonlyArray<DeviceRecord>;
  readonly rooms: ReadonlyArray<Room>;
  readonly controls: ReadonlyArray<ControlUiState>;
  readonly lastRefreshAtMs?: number;
  readonly error?: ViewModelError;
  readonly revision: number;

  constructor(phase: LoadPhase, filter: DeviceFilter, records: ReadonlyArray<DeviceRecord>,
    rooms: ReadonlyArray<Room>, controls: ReadonlyArray<ControlUiState>, revision: number,
    lastRefreshAtMs?: number, error?: ViewModelError) {
    this.phase = phase;
    this.filter = filter;
    this.records = records;
    this.rooms = rooms;
    this.controls = controls;
    this.lastRefreshAtMs = lastRefreshAtMs;
    this.error = error;
    this.revision = revision;
  }

  static initial(): DeviceViewState {
    return new DeviceViewState(LoadPhase.IDLE, DeviceFilter.all(), [], [], [], 0);
  }
}

export class DeviceViewModel implements ViewModelBase<DeviceViewState> {
  private readonly devices: DeviceRepository;
  private readonly rooms: RoomService;
  private readonly control: DeviceControlCoordinatorPort;
  private readonly i18n: I18nService;
  private readonly clock: ClockPort;
  private readonly timer: VmTimerPort;
  private readonly logger: LoggerPort;

  private state: DeviceViewState = DeviceViewState.initial();
  private listeners: Array<(state: DeviceViewState) => void> = [];
  private allRecords: ReadonlyArray<DeviceRecord> = [];
  private controls: Map<string, ControlUiState> = new Map<string, ControlUiState>();
  private tokens: Map<string, number> = new Map<string, number>();
  private revertTimers: Map<string, number> = new Map<string, number>();
  private familyId: string = '';
  private revision: number = 0;
  private disposed: boolean = false;

  private gate?: ThrottleGate = undefined;
  private gateKey?: DeviceKey = undefined;
  /** F-01: one generation per beginContinuous session; late results are dropped. */
  private gateToken: number = 0;
  private gateAction: DeviceAction = DeviceAction.PING;
  private gateMin: number = 0;
  private gateMax: number = 100;
  private gateLastOk: boolean = true;
  private gateLastExecution?: ControlExecution = undefined;
  private gateLastError?: ViewModelError = undefined;

  constructor(devices: DeviceRepository, rooms: RoomService,
    control: DeviceControlCoordinatorPort, i18n: I18nService, clock: ClockPort,
    timer: VmTimerPort, logger: LoggerPort) {
    this.devices = devices;
    this.rooms = rooms;
    this.control = control;
    this.i18n = i18n;
    this.clock = clock;
    this.timer = timer;
    this.logger = logger;
  }

  getState(): DeviceViewState {
    return this.state;
  }

  subscribe(listener: (state: DeviceViewState) => void): () => void {
    this.listeners.push(listener);
    return (): void => {
      const index = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    };
  }

  async initialize(familyId: string): Promise<void> {
    this.familyId = familyId;
    this.publish(this.copy(LoadPhase.LOADING, undefined));
    await this.refresh();
  }

  async refresh(): Promise<void> {
    if (this.disposed) {
      return;
    }
    try {
      if (this.state.phase !== LoadPhase.LOADING) {
        this.publish(this.copy(LoadPhase.LOADING, undefined));
      }
      this.allRecords = await this.devices.listRecords(this.familyId);
      const rooms = await this.rooms.listRooms(this.familyId);
      this.ensureControls(this.allRecords);
      const records = this.filterRecords(this.allRecords, this.state.filter);
      this.publish(new DeviceViewState(LoadPhase.READY, this.state.filter, records, rooms,
        this.controlList(records), this.revision + 1, this.clock.nowMs(), undefined));
    } catch (error) {
      this.fail(error);
    }
  }

  setFilter(filter: DeviceFilter): void {
    if (this.disposed) {
      return;
    }
    const records = this.filterRecords(this.allRecords, filter);
    this.publish(new DeviceViewState(this.state.phase, filter, records, this.state.rooms,
      this.controlList(records), this.revision + 1, this.state.lastRefreshAtMs,
      this.state.error));
  }

  async togglePower(key: DeviceKey): Promise<void> {
    const record = this.recordFor(key);
    if (record === undefined) {
      this.fail(AppErrors.of('DEVICE_NOT_FOUND', []));
      return;
    }
    const current = record.state.snapshot.powerStatus === true;
    await this.runSingle(key, current ? DeviceAction.TURN_OFF : DeviceAction.TURN_ON, !current);
  }

  async openDoor(key: DeviceKey): Promise<void> {
    await this.runSingle(key, DeviceAction.OPEN, true);
  }

  async closeDoor(key: DeviceKey): Promise<void> {
    await this.runSingle(key, DeviceAction.CLOSE, false);
  }

  async setColor(key: DeviceKey, color: string): Promise<void> {
    await this.runSingle(key, DeviceAction.SET_COLOR, color);
  }

  beginContinuous(key: DeviceKey, action: DeviceAction, min: number, max: number): void {
    if (this.disposed) {
      return;
    }
    const record = this.recordFor(key);
    if (record === undefined) {
      this.fail(AppErrors.of('DEVICE_NOT_FOUND', []));
      return;
    }
    this.cancelContinuous(key);
    this.gateKey = key;
    this.gateAction = action;
    this.gateMin = min;
    this.gateMax = max;
    this.gateLastOk = true;
    this.gateLastExecution = undefined;
    this.gateLastError = undefined;
    // Arm the per-key settle token (the control-timeout generation) and capture
    // the F-01 gate generation that owns this session's in-flight dispatches.
    this.nextToken(key);
    const token = this.gateToken;
    const current = this.controls.get(key.globalId());
    const start = current !== undefined && current.confirmedValue !== undefined ?
      DeviceViewModel.numeric(current.confirmedValue) : min;
    this.setControl(new ControlUiState(key, action, ControlPhase.PENDING, this.revision + 1,
      current === undefined ? undefined : current.confirmedValue, start, this.clock.nowMs(),
      current === undefined ? undefined : current.lastOutcome,
      current === undefined ? undefined : current.lastExecution,
      current === undefined ? undefined : current.lastError));
    this.gate = new ThrottleGate(this.timer, this.clock, THROTTLE_MS,
      (value: number): Promise<void> => this.dispatchContinuous(value, token));
    this.publishControls();
  }

  updateContinuous(key: DeviceKey, value: number): void {
    if (this.gate === undefined || this.gateKey === undefined ||
      !ViewModelSupport.isSameKey(this.gateKey, key)) {
      return;
    }
    const clamped = DeviceViewModel.clamp(value, this.gateMin, this.gateMax);
    this.gate.onInput(clamped);
    const current = this.controls.get(key.globalId());
    if (current !== undefined) {
      this.setControl(new ControlUiState(key, this.gateAction, ControlPhase.PENDING,
        this.revision + 1, current.confirmedValue, clamped, current.pendingSinceMs,
        current.lastOutcome, current.lastExecution, current.lastError));
      this.publishControls();
    }
  }

  async endContinuous(key: DeviceKey, value: number): Promise<void> {
    if (this.gate === undefined || this.gateKey === undefined ||
      !ViewModelSupport.isSameKey(this.gateKey, key)) {
      const action = this.gateAction === DeviceAction.PING ?
        DeviceAction.SET_TARGET_TEMPERATURE : this.gateAction;
      await this.runSingle(key, action, value);
      return;
    }
    const gate = this.gate;
    const sessionToken = this.gateToken;
    const action = this.gateAction;
    const clamped = DeviceViewModel.clamp(value, this.gateMin, this.gateMax);
    await gate.onCommit(clamped);
    // F-01: a concurrent cancel/dispose/new session invalidates this commit.
    // Only the session that still owns the gate may publish COMMITTED/REVERT.
    if (this.disposed || this.gate !== gate || this.gateToken !== sessionToken) {
      return;
    }
    const failed = !this.gateLastOk;
    const execution = this.gateLastExecution;
    const error = this.gateLastError;
    this.gate = undefined;
    this.gateKey = undefined;
    this.gateToken++;
    if (failed) {
      this.applyRevert(key, action, error === undefined ?
        ViewModelSupport.viewError(AppErrors.of('GATEWAY_TIMEOUT', []), this.clock) : error);
      return;
    }
    const confirmed = execution === undefined ? clamped :
      DeviceViewModel.reportedValue(execution, action);
    this.setControl(new ControlUiState(key, action, ControlPhase.COMMITTED,
      this.revision + 1, confirmed === undefined ? clamped : confirmed, undefined, undefined,
      execution === undefined ? undefined : execution.lan === undefined ? undefined :
        execution.lan.outcome, execution, undefined));
    this.clearRevertTimer(key);
    this.publishControls();
  }

  cancelContinuous(key: DeviceKey): void {
    if (this.gate !== undefined) {
      this.gate.dispose();
    }
    this.gate = undefined;
    this.gateKey = undefined;
    // F-01: invalidate every in-flight dispatch of the cancelled session.
    this.gateToken++;
    const current = this.controls.get(key.globalId());
    if (current === undefined) {
      return;
    }
    this.setControl(new ControlUiState(key, current.action, ControlPhase.IDLE,
      this.revision + 1, current.confirmedValue, undefined, undefined, current.lastOutcome,
      current.lastExecution, current.lastError));
    this.publishControls();
  }

  settleRevert(key: DeviceKey): void {
    const current = this.controls.get(key.globalId());
    if (current === undefined || current.phase !== ControlPhase.REVERT) {
      return;
    }
    this.clearRevertTimer(key);
    this.setControl(new ControlUiState(key, current.action, ControlPhase.IDLE,
      this.revision + 1, current.confirmedValue, undefined, undefined, current.lastOutcome,
      current.lastExecution, current.lastError));
    this.publishControls();
  }

  getControl(key: DeviceKey): ControlUiState | undefined {
    return this.controls.get(key.globalId());
  }

  translateError(error: ViewModelError | undefined): string {
    return error === undefined ? '' : this.i18n.t(error.i18nKey);
  }

  dispose(): void {
    this.disposed = true;
    this.gateToken++;
    if (this.gate !== undefined) {
      this.gate.dispose();
      this.gate = undefined;
    }
    this.revertTimers.forEach((timerId: number): void => {
      this.timer.clearTimer(timerId);
    });
    this.revertTimers.clear();
    this.listeners.splice(0, this.listeners.length);
  }

  private async runSingle(key: DeviceKey, action: DeviceAction,
    value?: CommandValue): Promise<void> {
    if (this.disposed) {
      return;
    }
    const record = this.recordFor(key);
    if (record === undefined) {
      this.fail(AppErrors.of('DEVICE_NOT_FOUND', []));
      return;
    }
    const existing = this.controls.get(key.globalId());
    if (existing !== undefined && existing.phase === ControlPhase.PENDING &&
      existing.action === action) {
      // Single action: at most one in-flight command per device/action.
      return;
    }
    const token = this.nextToken(key);
    this.clearRevertTimer(key);
    this.setControl(new ControlUiState(key, action, ControlPhase.PENDING, this.revision + 1,
      existing === undefined ? undefined : existing.confirmedValue, value, this.clock.nowMs(),
      existing === undefined ? undefined : existing.lastOutcome,
      existing === undefined ? undefined : existing.lastExecution, undefined));
    this.publishControls();
    this.armControlTimeout(key, token);
    const command = new DeviceControlCommand(key.gatewayId, key.deviceId, action,
      this.clock.nowMs(), value);
    let execution: ControlExecution | undefined = undefined;
    try {
      execution = await this.control.execute(command, record.state.familyId);
    } catch (error) {
      execution = undefined;
      if (this.isCurrent(key, token)) {
        this.applyRevert(key, action, ViewModelSupport.viewError(error as Object, this.clock));
      }
      return;
    }
    if (!this.isCurrent(key, token) || this.disposed) {
      return;
    }
    if (execution !== undefined && DeviceControlCoordinator.succeeded(execution)) {
      this.clearControlTimeout(key, token);
      const confirmed = DeviceViewModel.reportedValue(execution, action);
      this.setControl(new ControlUiState(key, action, ControlPhase.COMMITTED,
        this.revision + 1, confirmed === undefined ? value : confirmed, undefined, undefined,
        execution.lan === undefined ? undefined : execution.lan.outcome, execution, undefined));
      this.publishControls();
      return;
    }
    this.applyRevert(key, action, this.errorOf(execution));
  }

  private async dispatchContinuous(value: number, token: number): Promise<void> {
    if (!this.isGateCurrent(token)) {
      return;
    }
    const gate = this.gate as ThrottleGate;
    const key = this.gateKey as DeviceKey;
    const action = this.gateAction;
    const record = this.recordFor(key);
    if (record === undefined) {
      if (this.isGateCurrent(token)) {
        this.gateLastOk = false;
        this.gateLastError = ViewModelSupport.viewError(AppErrors.of('DEVICE_NOT_FOUND', []),
          this.clock);
      }
      return;
    }
    try {
      const command = new DeviceControlCommand(key.gatewayId, key.deviceId, action,
        this.clock.nowMs(), value);
      const execution = await this.control.execute(command, record.state.familyId);
      // F-01: cancel/dispose/new begin increments the generation. A late
      // result must not resurrect PENDING or mutate the new session.
      if (this.disposed || this.gate !== gate || this.gateToken !== token) {
        return;
      }
      this.gateLastExecution = execution;
      this.gateLastOk = DeviceControlCoordinator.succeeded(execution);
      this.gateLastError = this.gateLastOk ? undefined : this.errorOf(execution);
      if (this.gateLastOk) {
        const current = this.controls.get(key.globalId());
        if (current !== undefined) {
          this.setControl(new ControlUiState(key, action, ControlPhase.PENDING,
            this.revision + 1, current.confirmedValue, value, current.pendingSinceMs,
            execution.lan === undefined ? undefined : execution.lan.outcome, execution,
            undefined));
          this.publishControls();
        }
      }
    } catch (error) {
      if (this.disposed || this.gate !== gate || this.gateToken !== token) {
        return;
      }
      this.gateLastOk = false;
      this.gateLastError = ViewModelSupport.viewError(error as Object, this.clock);
    }
  }

  private isGateCurrent(token: number): boolean {
    return !this.disposed && this.gate !== undefined && this.gateKey !== undefined &&
      this.gateToken === token;
  }

  private applyRevert(key: DeviceKey, action: DeviceAction, error: ViewModelError): void {
    const current = this.controls.get(key.globalId());
    const revision = this.revision + 1;
    this.setControl(new ControlUiState(key, action, ControlPhase.REVERT, revision,
      current === undefined ? undefined : current.confirmedValue, undefined, undefined,
      current === undefined ? undefined : current.lastOutcome,
      current === undefined ? undefined : current.lastExecution, error));
    this.publishControls();
    const token = this.tokens.get(key.globalId());
    if (token !== undefined) {
      this.armRevertSettle(key, token);
    }
  }

  private errorOf(execution: ControlExecution | undefined): ViewModelError {
    if (execution !== undefined && execution.error !== undefined) {
      return ViewModelError.fromError(execution.error, this.clock.nowMs());
    }
    const mismatch = execution !== undefined &&
      DeviceControlCoordinator.verificationFor(execution) === StateVerification.MISMATCH;
    const code = mismatch ? 'ACK_STATE_MISMATCH' : 'ACK_PROTOCOL_VIOLATION';
    return ViewModelError.fromError(AppErrors.of(code, []), this.clock.nowMs());
  }

  private armControlTimeout(key: DeviceKey, token: number): void {
    const timerId = this.timer.setTimer(CONTROL_TIMEOUT_MS, (): void => {
      if (this.disposed || !this.isCurrent(key, token)) {
        return;
      }
      const current = this.controls.get(key.globalId());
      if (current === undefined || current.phase !== ControlPhase.PENDING) {
        return;
      }
      // Invalidate the late result: timeout is the final outcome of this try.
      this.tokens.set(key.globalId(), token + 1);
      this.applyRevert(key, current.action,
        ViewModelError.fromError(AppErrors.of('GATEWAY_TIMEOUT', []), this.clock.nowMs()));
    });
    this.revertTimers.set(this.timeoutKey(key), timerId);
  }

  private clearControlTimeout(key: DeviceKey, token: number): void {
    if (!this.isCurrent(key, token)) {
      return;
    }
    this.clearRevertTimer(key);
  }

  private armRevertSettle(key: DeviceKey, token: number): void {
    this.clearRevertTimer(key);
    const timerId = this.timer.setTimer(REVERT_SETTLE_MS, (): void => {
      if (this.disposed || !this.isCurrent(key, token)) {
        return;
      }
      const current = this.controls.get(key.globalId());
      if (current === undefined || current.phase !== ControlPhase.REVERT) {
        return;
      }
      this.setControl(new ControlUiState(key, current.action, ControlPhase.IDLE,
        this.revision + 1, current.confirmedValue, undefined, undefined, current.lastOutcome,
        current.lastExecution, current.lastError));
      this.publishControls();
    });
    this.revertTimers.set(this.timeoutKey(key), timerId);
  }

  private clearRevertTimer(key: DeviceKey): void {
    const existing = this.revertTimers.get(this.timeoutKey(key));
    if (existing !== undefined) {
      this.timer.clearTimer(existing);
      this.revertTimers.delete(this.timeoutKey(key));
    }
  }

  private timeoutKey(key: DeviceKey): string {
    return 'control|' + key.globalId();
  }

  private nextToken(key: DeviceKey): number {
    const next = (this.tokens.get(key.globalId()) === undefined ? 0 :
      (this.tokens.get(key.globalId()) as number)) + 1;
    this.tokens.set(key.globalId(), next);
    return next;
  }

  private isCurrent(key: DeviceKey, token: number): boolean {
    return this.tokens.get(key.globalId()) === token;
  }

  private recordFor(key: DeviceKey): DeviceRecord | undefined {
    for (let index = 0; index < this.allRecords.length; index++) {
      if (ViewModelSupport.isSameKey(this.allRecords[index].state.key, key)) {
        return this.allRecords[index];
      }
    }
    return undefined;
  }

  private ensureControls(records: ReadonlyArray<DeviceRecord>): void {
    for (let index = 0; index < records.length; index++) {
      const id = records[index].state.key.globalId();
      if (!this.controls.has(id)) {
        this.controls.set(id, ControlUiState.idle(records[index].state.key, this.revision + 1));
      }
    }
  }

  private controlList(records: ReadonlyArray<DeviceRecord>): ReadonlyArray<ControlUiState> {
    const result: ControlUiState[] = [];
    for (let index = 0; index < records.length; index++) {
      const control = this.controls.get(records[index].state.key.globalId());
      if (control !== undefined) {
        result.push(control);
      }
    }
    return result;
  }

  private filterRecords(records: ReadonlyArray<DeviceRecord>,
    filter: DeviceFilter): ReadonlyArray<DeviceRecord> {
    const result: DeviceRecord[] = [];
    for (let index = 0; index < records.length; index++) {
      const record = records[index];
      if (filter.kind === DeviceFilterKind.ALL) {
        result.push(record);
      } else if (filter.kind === DeviceFilterKind.ROOM &&
        record.state.roomId === filter.roomId) {
        result.push(record);
      } else if (filter.kind === DeviceFilterKind.UNASSIGNED && record.state.isUnassigned) {
        result.push(record);
      }
    }
    return result;
  }

  private setControl(control: ControlUiState): void {
    this.controls.set(control.key.globalId(), control);
  }

  private publishControls(): void {
    const records = this.filterRecords(this.allRecords, this.state.filter);
    this.publish(new DeviceViewState(this.state.phase, this.state.filter, records,
      this.state.rooms, this.controlList(records), this.revision + 1,
      this.state.lastRefreshAtMs, this.state.error));
  }

  private copy(phase: LoadPhase, error: ViewModelError | undefined): DeviceViewState {
    return new DeviceViewState(phase, this.state.filter, this.state.records, this.state.rooms,
      this.state.controls, this.revision + 1, this.state.lastRefreshAtMs, error);
  }

  private fail(error: Object): void {
    const viewError = ViewModelSupport.viewError(error, this.clock);
    this.logger.warn(TAG, 'view_model_error', [new NameValue('code', viewError.error.code)]);
    this.publish(new DeviceViewState(LoadPhase.ERROR, this.state.filter, this.state.records,
      this.state.rooms, this.state.controls, this.revision + 1, this.state.lastRefreshAtMs,
      viewError));
  }

  private publish(next: DeviceViewState): void {
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

  private static clamp(value: number, min: number, max: number): number {
    if (!Number.isFinite(value)) {
      return min;
    }
    return value < min ? min : value > max ? max : value;
  }

  private static numeric(value: CommandValue): number {
    return typeof value === 'number' ? value as number : 0;
  }

  private static reportedValue(execution: ControlExecution,
    action: DeviceAction): CommandValue | undefined {
    const snapshot = DeviceViewModel.snapshotOf(execution);
    if (snapshot !== undefined) {
      return DeviceViewModel.snapshotValue(snapshot, action);
    }
    if (execution.cloud !== undefined && execution.cloud.verdict.reportedState !== undefined) {
      return DeviceViewModel.patchValue(execution.cloud.verdict.reportedState, action);
    }
    if (execution.lan !== undefined && execution.lan.outcome !== undefined &&
      execution.lan.outcome.reportedState !== undefined) {
      return DeviceViewModel.patchValue(execution.lan.outcome.reportedState, action);
    }
    return undefined;
  }

  private static snapshotOf(execution: ControlExecution): DeviceSnapshot | undefined {
    if (execution.apply !== undefined && execution.apply.record !== undefined) {
      return execution.apply.record.state.snapshot;
    }
    if (execution.lan !== undefined && execution.lan.apply !== undefined &&
      execution.lan.apply.record !== undefined) {
      return execution.lan.apply.record.state.snapshot;
    }
    return undefined;
  }

  private static snapshotValue(snapshot: DeviceSnapshot, action: DeviceAction):
    CommandValue | undefined {
    if (action === DeviceAction.OPEN || action === DeviceAction.CLOSE) {
      return snapshot.openStatus;
    }
    if (action === DeviceAction.TURN_ON || action === DeviceAction.TURN_OFF) {
      return snapshot.powerStatus;
    }
    if (action === DeviceAction.SET_BRIGHTNESS) {
      return snapshot.brightness;
    }
    if (action === DeviceAction.SET_COLOR) {
      return snapshot.color;
    }
    if (action === DeviceAction.SET_TARGET_TEMPERATURE) {
      return snapshot.targetTemperature;
    }
    if (action === DeviceAction.SET_MODE) {
      return snapshot.mode;
    }
    return undefined;
  }

  private static patchValue(patch: DeviceStatePatch, action: DeviceAction):
    CommandValue | undefined {
    if (action === DeviceAction.OPEN || action === DeviceAction.CLOSE) {
      return patch.openStatus;
    }
    if (action === DeviceAction.TURN_ON || action === DeviceAction.TURN_OFF) {
      return patch.powerStatus;
    }
    if (action === DeviceAction.SET_BRIGHTNESS) {
      return patch.brightness;
    }
    if (action === DeviceAction.SET_COLOR) {
      return patch.color;
    }
    if (action === DeviceAction.SET_TARGET_TEMPERATURE) {
      return patch.targetTemperature;
    }
    if (action === DeviceAction.SET_MODE) {
      return patch.mode;
    }
    return undefined;
  }
}
