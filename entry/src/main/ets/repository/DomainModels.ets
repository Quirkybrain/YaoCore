/*
 * YaoCore C-10/C-11 domain view and execution models.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §5.1.1, §5.1.3, §6.1.1 (EXT-DES-B-10..12)
 *
 * LOCATION EXCEPTION: DES-B places these in model/**. T-09's delegated write
 * scope is repository/**, service/**; they are kept here so no out-of-scope
 * file is touched. They are pure values and do not import platform APIs.
 */
import type { DeviceKey } from '../model/DeviceKey';
import type { DeviceState } from '../model/DeviceState';
import type { DeviceAction } from '../common/constants/DeviceConstants';
import type { CommandValue } from '../common/utils/JsonAtom';
import type { AppError } from '../common/types/AppError';
import { StateVerification } from '../model/ControlModels';
import { DeviceControlCommand } from '../model/ControlModels';
import type { ControlOutcome } from '../model/ControlModels';
import { SceneAction } from '../model/FamilyModels';

export enum DeviceMergeResult {
  ADDED = 'ADDED',
  UPDATED = 'UPDATED',
  UNCHANGED = 'UNCHANGED',
  STALE_DROPPED = 'STALE_DROPPED',
  SAME_EPOCH_OVERWRITE = 'SAME_EPOCH_OVERWRITE',
  TOMBSTONED_SKIPPED = 'TOMBSTONED_SKIPPED',
  PARTIAL_MERGED = 'PARTIAL_MERGED',
  INVALID_DROPPED = 'INVALID_DROPPED'
}

export class DeviceMergeState {
  readonly lastSnapshotAtMs: number;
  readonly lastEpochMs: number;
  readonly lastResult: DeviceMergeResult;
  readonly lastDeviationCode?: string;

  constructor(lastSnapshotAtMs: number, lastEpochMs: number, lastResult: DeviceMergeResult,
    lastDeviationCode?: string) {
    this.lastSnapshotAtMs = lastSnapshotAtMs;
    this.lastEpochMs = lastEpochMs;
    this.lastResult = lastResult;
    this.lastDeviationCode = lastDeviationCode;
  }
}

export class DeviceRecord {
  readonly state: DeviceState;
  readonly merge: DeviceMergeState;
  readonly gatewayRemoved: boolean;
  readonly hasPartialState: boolean;
  readonly isSupported: boolean;
  readonly isControlAllowed: boolean;

  constructor(state: DeviceState, merge: DeviceMergeState, gatewayRemoved: boolean,
    hasPartialState: boolean) {
    this.state = state;
    this.merge = merge;
    this.gatewayRemoved = gatewayRemoved;
    this.hasPartialState = hasPartialState;
    this.isSupported = state.snapshot.isSupported;
    // ADR-004 §2.1-4: read-only degraded, unassigned/disabled and dismissed
    // devices are never controllable.
    this.isControlAllowed = state.isEnabled && !state.isUnassigned && this.isSupported &&
      !state.isDismissed;
  }
}

export class DiscoverApplyOptions {
  readonly familyId: string;
  readonly markMissingAsGatewayRemoved: boolean;
  readonly nowMs: number;

  constructor(familyId: string, nowMs: number, markMissingAsGatewayRemoved: boolean = true) {
    this.familyId = familyId;
    this.nowMs = nowMs;
    this.markMissingAsGatewayRemoved = markMissingAsGatewayRemoved;
  }
}

export class DiscoverApplyResult {
  readonly added: number;
  readonly updated: number;
  readonly unchanged: number;
  readonly staleDropped: number;
  readonly tombstonedSkipped: number;
  readonly invalidDropped: number;
  readonly gatewayRemovedMarked: number;
  readonly partial: boolean;
  readonly deviations: ReadonlyArray<string>;
  readonly affectedKeys: ReadonlyArray<DeviceKey>;

  constructor(added: number, updated: number, unchanged: number, staleDropped: number,
    tombstonedSkipped: number, invalidDropped: number, gatewayRemovedMarked: number,
    partial: boolean, deviations: ReadonlyArray<string>,
    affectedKeys: ReadonlyArray<DeviceKey>) {
    this.added = added;
    this.updated = updated;
    this.unchanged = unchanged;
    this.staleDropped = staleDropped;
    this.tombstonedSkipped = tombstonedSkipped;
    this.invalidDropped = invalidDropped;
    this.gatewayRemovedMarked = gatewayRemovedMarked;
    this.partial = partial;
    this.deviations = deviations;
    this.affectedKeys = affectedKeys;
  }
}

export class ControlApplyContext {
  readonly familyId: string;
  readonly gatewayId: string;
  readonly deviceId: string;
  readonly action: DeviceAction;
  readonly requestedValue?: CommandValue;
  readonly notBeforeMs: number;

  constructor(familyId: string, gatewayId: string, deviceId: string, action: DeviceAction,
    notBeforeMs: number, requestedValue?: CommandValue) {
    this.familyId = familyId;
    this.gatewayId = gatewayId;
    this.deviceId = deviceId;
    this.action = action;
    this.notBeforeMs = notBeforeMs;
    this.requestedValue = requestedValue;
  }
}

export enum ControlApplyReason {
  APPLIED = 'APPLIED',
  IDEMPOTENT_REPLAY = 'IDEMPOTENT_REPLAY',
  NO_REPORTED_STATE = 'NO_REPORTED_STATE',
  STALE_STATE_DROPPED = 'STALE_STATE_DROPPED',
  DEVICE_MISMATCH = 'DEVICE_MISMATCH',
  DEVICE_NOT_FOUND = 'DEVICE_NOT_FOUND',
  ACK_NOT_ACCEPTED = 'ACK_NOT_ACCEPTED',
  APPLY_FAILED = 'APPLY_FAILED'
}

export class ControlApplyResult {
  readonly ackAccepted: boolean;
  readonly stateApplied: boolean;
  readonly stateVerification: StateVerification;
  readonly reason: ControlApplyReason;
  readonly record?: DeviceRecord;

  constructor(ackAccepted: boolean, stateApplied: boolean,
    stateVerification: StateVerification, reason: ControlApplyReason, record?: DeviceRecord) {
    this.ackAccepted = ackAccepted;
    this.stateApplied = stateApplied;
    this.stateVerification = stateVerification;
    this.reason = reason;
    this.record = record;
  }
}

export class DeviceRemovalOptions {
  readonly removeSceneReferences: boolean;
  readonly nowMs: number;

  constructor(nowMs: number, removeSceneReferences: boolean = true) {
    this.nowMs = nowMs;
    this.removeSceneReferences = removeSceneReferences;
  }
}

export class SceneCleanupSummary {
  readonly removedActionCount: number;
  readonly affectedSceneIds: ReadonlyArray<string>;
  readonly affectedSceneNames: ReadonlyArray<string>;

  constructor(removedActionCount: number, affectedSceneIds: ReadonlyArray<string>,
    affectedSceneNames: ReadonlyArray<string>) {
    this.removedActionCount = removedActionCount;
    this.affectedSceneIds = affectedSceneIds;
    this.affectedSceneNames = affectedSceneNames;
  }
}

export class DeviceRemovalResult {
  readonly removed: boolean;
  readonly key: DeviceKey;
  readonly sceneCleanup?: SceneCleanupSummary;
  readonly tombstoneCreated: boolean;

  constructor(removed: boolean, key: DeviceKey, tombstoneCreated: boolean,
    sceneCleanup?: SceneCleanupSummary) {
    this.removed = removed;
    this.key = key;
    this.tombstoneCreated = tombstoneCreated;
    this.sceneCleanup = sceneCleanup;
  }
}

export enum DeviceChangeEventType {
  DEVICE_ADDED = 'DEVICE_ADDED',
  DEVICE_UPDATED = 'DEVICE_UPDATED',
  DEVICE_REMOVED = 'DEVICE_REMOVED',
  DEVICE_DISMISSED = 'DEVICE_DISMISSED',
  DEVICE_RESTORED = 'DEVICE_RESTORED',
  GATEWAY_REMOVED = 'GATEWAY_REMOVED',
  STATE_APPLIED = 'STATE_APPLIED'
}

export class DeviceChangeEvent {
  readonly type: DeviceChangeEventType;
  readonly key: DeviceKey;

  constructor(type: DeviceChangeEventType, key: DeviceKey) {
    this.type = type;
    this.key = key;
  }
}

export enum SceneRunState {
  IDLE = 'IDLE',
  PREFLIGHT = 'PREFLIGHT',
  RUNNING = 'RUNNING',
  SUCCEEDED = 'SUCCEEDED',
  PARTIAL_FAILED = 'PARTIAL_FAILED',
  FAILED = 'FAILED',
  CANCELLED = 'CANCELLED'
}

export enum SceneStepState {
  PENDING = 'PENDING',
  RUNNING = 'RUNNING',
  SUCCEEDED = 'SUCCEEDED',
  FAILED = 'FAILED',
  SKIPPED = 'SKIPPED',
  CANCELLED = 'CANCELLED'
}

export class SceneStepResult {
  readonly index: number;
  readonly action: SceneAction;
  readonly state: SceneStepState;
  readonly startedAtMs?: number;
  readonly endedAtMs?: number;
  readonly outcome?: ControlOutcome;
  readonly stateVerification?: StateVerification;
  readonly error?: AppError;

  constructor(index: number, action: SceneAction, state: SceneStepState,
    startedAtMs?: number, endedAtMs?: number, outcome?: ControlOutcome,
    stateVerification?: StateVerification, error?: AppError) {
    this.index = index;
    this.action = action;
    this.state = state;
    this.startedAtMs = startedAtMs;
    this.endedAtMs = endedAtMs;
    this.outcome = outcome;
    this.stateVerification = stateVerification;
    this.error = error;
  }

  withState(state: SceneStepState, startedAtMs?: number, endedAtMs?: number,
    outcome?: ControlOutcome, stateVerification?: StateVerification,
    error?: AppError): SceneStepResult {
    return new SceneStepResult(this.index, this.action, state,
      startedAtMs === undefined ? this.startedAtMs : startedAtMs,
      endedAtMs === undefined ? this.endedAtMs : endedAtMs,
      outcome === undefined ? this.outcome : outcome,
      stateVerification === undefined ? this.stateVerification : stateVerification,
      error === undefined ? this.error : error);
  }
}

export class SceneExecutionResult {
  readonly runId: string;
  readonly sceneId: string;
  readonly sceneName: string;
  readonly state: SceneRunState;
  readonly steps: ReadonlyArray<SceneStepResult>;
  readonly startedAtMs: number;
  readonly endedAtMs?: number;
  readonly executedCount: number;
  readonly succeededCount: number;
  readonly failedStepIndex?: number;
  readonly error?: AppError;
  readonly noRollbackNotice: boolean;

  constructor(runId: string, sceneId: string, sceneName: string, state: SceneRunState,
    steps: ReadonlyArray<SceneStepResult>, startedAtMs: number, executedCount: number,
    succeededCount: number, failedStepIndex?: number, endedAtMs?: number, error?: AppError) {
    this.runId = runId;
    this.sceneId = sceneId;
    this.sceneName = sceneName;
    this.state = state;
    this.steps = steps;
    this.startedAtMs = startedAtMs;
    this.endedAtMs = endedAtMs;
    this.executedCount = executedCount;
    this.succeededCount = succeededCount;
    this.failedStepIndex = failedStepIndex;
    this.error = error;
    // FR-SCN-001 / UIUX §4.6: executed steps are never automatically rolled back.
    this.noRollbackNotice = true;
  }
}

export class SceneExecutionProgress {
  readonly runId: string;
  readonly sceneId: string;
  readonly state: SceneRunState;
  readonly currentIndex: number;
  readonly steps: ReadonlyArray<SceneStepResult>;
  readonly executedCount: number;
  readonly succeededCount: number;

  constructor(runId: string, sceneId: string, state: SceneRunState, currentIndex: number,
    steps: ReadonlyArray<SceneStepResult>, executedCount: number, succeededCount: number) {
    this.runId = runId;
    this.sceneId = sceneId;
    this.state = state;
    this.currentIndex = currentIndex;
    this.steps = steps;
    this.executedCount = executedCount;
    this.succeededCount = succeededCount;
  }
}

export enum SceneExecutionEventType {
  STARTED = 'STARTED',
  STEP_STARTED = 'STEP_STARTED',
  STEP_SUCCEEDED = 'STEP_SUCCEEDED',
  STEP_FAILED = 'STEP_FAILED',
  FINISHED = 'FINISHED',
  CANCELLED = 'CANCELLED'
}

export class SceneExecutionEvent {
  readonly type: SceneExecutionEventType;
  readonly progress: SceneExecutionProgress;

  constructor(type: SceneExecutionEventType, progress: SceneExecutionProgress) {
    this.type = type;
    this.progress = progress;
  }
}

export class SceneExecutionPolicy {
  readonly stepTimeoutMs: number;
  readonly totalTimeoutMs: number;
  readonly allowCancelBetweenSteps: boolean;

  constructor(stepTimeoutMs: number = 8000, totalTimeoutMs: number = 60000,
    allowCancelBetweenSteps: boolean = true) {
    this.stepTimeoutMs = stepTimeoutMs;
    this.totalTimeoutMs = totalTimeoutMs;
    this.allowCancelBetweenSteps = allowCancelBetweenSteps;
  }

  static defaults(): SceneExecutionPolicy {
    return new SceneExecutionPolicy(8000, 60000, true);
  }
}

export class DeviceCommandOptions {
  readonly familyId: string;
  readonly precheck: boolean;
  readonly timeoutMs?: number;

  constructor(familyId: string, precheck: boolean = true, timeoutMs?: number) {
    this.familyId = familyId;
    this.precheck = precheck;
    this.timeoutMs = timeoutMs;
  }
}

export class DeviceCommandExecution {
  readonly command: DeviceControlCommand;
  readonly outcome?: ControlOutcome;
  readonly apply?: ControlApplyResult;
  readonly error?: AppError;
  readonly elapsedMs: number;
  readonly ackAccepted: boolean;

  constructor(command: DeviceControlCommand,
    elapsedMs: number, ackAccepted: boolean, outcome?: ControlOutcome,
    apply?: ControlApplyResult, error?: AppError) {
    this.command = command;
    this.outcome = outcome;
    this.apply = apply;
    this.error = error;
    this.elapsedMs = elapsedMs;
    this.ackAccepted = ackAccepted;
  }
}
