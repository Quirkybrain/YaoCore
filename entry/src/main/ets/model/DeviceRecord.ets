/*
 * YaoCore C-10/C-11 device view and execution models.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-B §2.1/D-12 P2; moved out of
 * repository/DomainModels.ets so contracts/** and pages/components can import
 * read-only DTOs without a repository dependency.
 * Contract: DES-B §5.1.1, §5.1.3 (EXT-DES-B-10..12)
 *
 * Pure values; no platform API.
 */
import type { DeviceKey } from './DeviceKey';
import type { DeviceState } from './DeviceState';
import type { DeviceAction } from '../common/constants/DeviceConstants';
import type { CommandValue } from '../common/utils/JsonAtom';
import type { AppError } from '../common/types/AppError';
import { StateVerification } from './ControlModels';
import { DeviceControlCommand } from './ControlModels';
import type { ControlOutcome } from './ControlModels';

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
