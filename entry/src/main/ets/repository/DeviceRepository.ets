/*
 * YaoCore C-10 DeviceRepository.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-A §5.1.2/§5.3 + DES-B §5.1-§5.5
 *
 * Single source of truth for device state. Discovery snapshots are arbitrated
 * by stateEpochMs, local fields (name/room/enabled/unassigned/dismissed) are
 * never overwritten by discovery, and no network request is issued here.
 * Cloud completion evaluation (PB-02) is deliberately out of scope: this
 * repository only applies a state patch after the caller supplies an accepted
 * verdict.
 *
 * O-1: public methods run through the injected DomainOperationGate and all
 * writes are inside one top-level RDB transaction. `tx`-taking port methods
 * are transaction-context only; they never start another transaction or take
 * the gate.
 */
import { AppError, AppErrors } from '../common/types/AppError';
import { NameValue } from '../common/types/NameValue';
import { ProtocolConstants } from '../common/constants/ProtocolConstants';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import { UuidUtil } from '../common/utils/UuidUtil';
import type { ClockPort, LoggerPort } from '../common/types/Ports';
import { DeviceKey } from '../model/DeviceKey';
import { DeviceState, DeviceSnapshot, DeviceSnapshotInit, DeviceStatePatch } from '../model/DeviceState';
import { ControlOutcome, StateVerification } from '../model/ControlModels';
import type { DiscoverySnapshot } from '../model/DiscoveryModels';
import type { GatewayRoutePort } from './GatewayPorts';
import type { RdbRow, RdbStore, RdbTransaction } from '../service/storage/RdbStore';
import type { MigrationSink } from '../service/storage/MigrationPort';
import { DomainMigrations } from './DomainMigrations';
import { DomainOperationGate } from './DomainOperationGate';
import { DeviceSnapshotCodec } from './DeviceSnapshotCodec';
import { SqlCells } from './SqlCells';
import {
  ControlApplyContext,
  ControlApplyReason,
  ControlApplyResult,
  DeviceChangeEvent,
  DeviceChangeEventType,
  DeviceMergeResult,
  DeviceMergeState,
  DeviceRecord,
  DeviceRemovalOptions,
  DeviceRemovalResult,
  DiscoverApplyOptions,
  DiscoverApplyResult,
  SceneCleanupSummary
} from './DomainModels';
import type {
  DeviceAssignmentPort,
  DeviceStatePort,
  RoomDeviceNamePort,
  RoomLookupPort,
  SceneReferencePort
} from './DomainPorts';

const DEVICE_COLUMNS: string = 'gateway_id, device_id, family_id, device_name, room_id, ' +
  'is_enabled, is_unassigned, snapshot_json, state_epoch_ms, last_merge_at, ' +
  'gateway_removed, last_applied_request_id, last_applied_seq';

export class DeviceRepository implements DeviceStatePort, DeviceAssignmentPort, RoomDeviceNamePort {
  private readonly rdb: RdbStore;
  private readonly rooms: RoomLookupPort;
  private readonly scenes: SceneReferencePort;
  private readonly clock: ClockPort;
  private readonly logger: LoggerPort;
  private readonly gate: DomainOperationGate;
  private readonly routes?: GatewayRoutePort;
  private readonly mergeStates: Map<string, DeviceMergeState> = new Map<string, DeviceMergeState>();
  private readonly partialKeys: Map<string, boolean> = new Map<string, boolean>();
  private readonly listeners: Array<(event: DeviceChangeEvent) => void> = [];
  private initialized: boolean = false;

  constructor(rdb: RdbStore, rooms: RoomLookupPort, scenes: SceneReferencePort,
    clock: ClockPort, logger: LoggerPort, gate?: DomainOperationGate,
    routes?: GatewayRoutePort) {
    this.rdb = rdb;
    this.rooms = rooms;
    this.scenes = scenes;
    this.clock = clock;
    this.logger = logger;
    this.gate = gate === undefined ? new DomainOperationGate() : gate;
    this.routes = routes;
  }

  /** DES-B §5.1.3: v4 device_state table (shared v4 registration is idempotent). */
  static registerMigrations(registry: MigrationSink): void {
    DomainMigrations.register(registry);
  }

  async initialize(): Promise<void> {
    try {
      await this.rdb.query('SELECT gateway_id FROM device_state LIMIT 0');
      await this.rdb.query('SELECT gateway_id FROM gw_dismissed_device LIMIT 0');
    } catch (error) {
      throw DeviceRepository.storageError(error as Error);
    }
    this.initialized = true;
  }

  // ---- Discovery merge / arbitration -------------------------------------

  async applyDiscoverSnapshot(snapshot: DiscoverySnapshot,
    options?: DiscoverApplyOptions): Promise<DiscoverApplyResult> {
    this.ensureInitialized();
    if (options === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'options')]);
    }
    const familyId = DeviceRepository.requireIdentifier(options.familyId, 'familyId');
    return this.gate.run(async (): Promise<DiscoverApplyResult> => {
      if (this.routes !== undefined) {
        const route = await this.routes.getRoute(snapshot.gatewayId);
        if (route === undefined) {
          return DeviceRepository.emptyResult(false, ['GATEWAY_NOT_BOUND']);
        }
        if (route.familyId !== familyId) {
          return DeviceRepository.emptyResult(false, ['GATEWAY_FAMILY_MISMATCH']);
        }
      }
      const events: DeviceChangeEvent[] = [];
      const result = await this.rdb.transaction<DiscoverApplyResult>(
        async (tx: RdbTransaction): Promise<DiscoverApplyResult> => {
          return this.applyDiscoverInTransaction(tx, snapshot, familyId, options, events);
        });
      // Events are notifications, never a fact source: dispatch only after the
      // transaction committed (wp-026 R-12).
      this.dispatchEvents(events);
      return result;
    });
  }

  private async applyDiscoverInTransaction(tx: RdbTransaction, snapshot: DiscoverySnapshot,
    familyId: string, options: DiscoverApplyOptions,
    events: DeviceChangeEvent[]): Promise<DiscoverApplyResult> {
    const existingRows = await tx.query('SELECT ' + DEVICE_COLUMNS +
      ' FROM device_state WHERE gateway_id = ?', [snapshot.gatewayId]);
    const existing: Map<string, RdbRow> = new Map<string, RdbRow>();
    for (let index = 0; index < existingRows.length; index++) {
      existing.set(SqlCells.requiredString(existingRows[index], 'device_id'), existingRows[index]);
    }
    const dismissedRows = await tx.query('SELECT device_id FROM gw_dismissed_device ' +
      'WHERE gateway_id = ?', [snapshot.gatewayId]);
    const dismissed: Map<string, boolean> = new Map<string, boolean>();
    for (let index = 0; index < dismissedRows.length; index++) {
      dismissed.set(SqlCells.requiredString(dismissedRows[index], 'device_id'), true);
    }

    let added = 0;
    let updated = 0;
    let unchanged = 0;
    let staleDropped = 0;
    let tombstonedSkipped = 0;
    let invalidDropped = 0;
    const deviations: string[] = [];
    const affectedKeys: DeviceKey[] = [];
    const present: Map<string, boolean> = new Map<string, boolean>();

    if (snapshot.aliasUsed) {
      // Alias fallback is a diagnostic only. It must never be treated as a
      // partial snapshot (DES-B §0.2-2 / RISK-PARTIAL-DISCOVER).
      deviations.push('ALIAS_FIELD_USED');
    }
    if (snapshot.isPartial) {
      deviations.push('PARTIAL_DISCOVER');
    }

    for (let index = 0; index < snapshot.devices.length; index++) {
      const incoming = snapshot.devices[index];
      const key = new DeviceKey(snapshot.gatewayId, incoming.deviceId);
      if (present.has(key.globalId())) {
        invalidDropped++;
        deviations.push('DUPLICATE_DEVICE');
        continue;
      }
      present.set(key.globalId(), true);
      affectedKeys.push(key);
      const familyMismatch = existing.get(key.deviceId);
      if (dismissed.has(key.deviceId)) {
        tombstonedSkipped++;
        this.rememberMerge(key, DeviceMergeResult.TOMBSTONED_SKIPPED,
          this.clock.nowMs(), incoming.stateEpochMs, 'TOMBSTONED_SKIPPED');
        continue;
      }
      if (familyMismatch !== undefined &&
        SqlCells.requiredString(familyMismatch, 'family_id') !== familyId) {
        invalidDropped++;
        deviations.push('FAMILY_MISMATCH');
        continue;
      }
      try {
        if (familyMismatch === undefined) {
          const now = DateTimeUtil.formatUtcCompact(this.clock.nowMs());
          await tx.execute('INSERT OR REPLACE INTO device_state (' + DEVICE_COLUMNS + ') ' +
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [key.gatewayId, key.deviceId, familyId, incoming.deviceName, '', 0, 1,
            DeviceSnapshotCodec.encode(incoming), incoming.stateEpochMs, now, 0, null, null]);
          added++;
          this.rememberMerge(key, DeviceMergeResult.ADDED, this.clock.nowMs(),
            incoming.stateEpochMs, undefined);
          if (snapshot.isPartial) {
            this.partialKeys.set(key.globalId(), true);
          }
          events.push(new DeviceChangeEvent(DeviceChangeEventType.DEVICE_ADDED, key));
          continue;
        }

        const priorEpoch = SqlCells.requiredNumber(familyMismatch, 'state_epoch_ms');
        const oldSnapshot = DeviceSnapshotCodec.decode(
          SqlCells.requiredString(familyMismatch, 'snapshot_json'));
        const incomingEpoch = incoming.stateEpochMs;
        if (incomingEpoch < priorEpoch) {
          staleDropped++;
          deviations.push('STALE_SNAPSHOT');
          this.rememberMerge(key, DeviceMergeResult.STALE_DROPPED, this.clock.nowMs(),
            priorEpoch, 'STALE_SNAPSHOT');
          this.logger.debug('DeviceRepository', 'stale_snapshot_dropped',
            [new NameValue('gatewayId', key.gatewayId), new NameValue('deviceId', key.deviceId)]);
          continue;
        }
        const merged = DeviceRepository.mergeSnapshots(oldSnapshot, incoming);
        const oldText = DeviceSnapshotCodec.encode(oldSnapshot);
        const newText = DeviceSnapshotCodec.encode(merged);
        const wasGatewayRemoved = SqlCells.requiredNumber(familyMismatch, 'gateway_removed') !== 0;
        if (oldText === newText && !wasGatewayRemoved) {
          unchanged++;
          this.rememberMerge(key, DeviceMergeResult.UNCHANGED, this.clock.nowMs(),
            priorEpoch, undefined);
          if (snapshot.isPartial) {
            this.partialKeys.set(key.globalId(), true);
          } else {
            this.partialKeys.delete(key.globalId());
          }
          continue;
        }
        const epochEqual = incomingEpoch === priorEpoch;
        let result = DeviceMergeResult.UPDATED;
        let deviation: string | undefined = undefined;
        if (oldText === newText) {
          // Only the local gateway_removed hint changed (device reappeared).
          result = DeviceMergeResult.UPDATED;
        } else if (epochEqual) {
          result = DeviceMergeResult.SAME_EPOCH_OVERWRITE;
          deviation = 'SAME_EPOCH_OVERWRITE';
          deviations.push('SAME_EPOCH_OVERWRITE');
        } else if (snapshot.isPartial) {
          result = DeviceMergeResult.PARTIAL_MERGED;
          deviation = 'PARTIAL_DISCOVER';
        }
        await tx.execute('UPDATE device_state SET family_id = ?, ' +
          'snapshot_json = ?, state_epoch_ms = ?, last_merge_at = ?, gateway_removed = ? ' +
          'WHERE gateway_id = ? AND device_id = ?',
        [familyId, newText, priorEpoch > incomingEpoch ? priorEpoch : incomingEpoch,
          DateTimeUtil.formatUtcCompact(this.clock.nowMs()), 0, key.gatewayId, key.deviceId]);
        updated++;
        this.rememberMerge(key, result, this.clock.nowMs(),
          priorEpoch > incomingEpoch ? priorEpoch : incomingEpoch, deviation);
        if (snapshot.isPartial) {
          this.partialKeys.set(key.globalId(), true);
        } else {
          this.partialKeys.delete(key.globalId());
        }
        events.push(new DeviceChangeEvent(wasGatewayRemoved ?
          DeviceChangeEventType.DEVICE_RESTORED : DeviceChangeEventType.DEVICE_UPDATED, key));
      } catch (error) {
        if (error instanceof AppError && error.code.startsWith('STORAGE_')) {
          throw error;
        }
        invalidDropped++;
        deviations.push('INVALID_DEVICE');
        this.logger.warn('DeviceRepository', 'discover_device_invalid',
          [new NameValue('gatewayId', key.gatewayId), new NameValue('deviceId', key.deviceId)]);
      }
    }

    let gatewayRemovedMarked = 0;
    if (!snapshot.isPartial && invalidDropped === 0 && options.markMissingAsGatewayRemoved) {
      const missing: DeviceKey[] = [];
      existing.forEach((row: RdbRow, deviceId: string): void => {
        if (present.has(snapshot.gatewayId + ':' + deviceId)) {
          return;
        }
        if (SqlCells.requiredString(row, 'family_id') !== familyId) {
          return;
        }
        if (SqlCells.requiredNumber(row, 'gateway_removed') !== 0) {
          return;
        }
        missing.push(new DeviceKey(snapshot.gatewayId, deviceId));
      });
      for (let index = 0; index < missing.length; index++) {
        const key = missing[index];
        // Full discover did not list this device: a local hint only. It is not
        // a deletion, disablement or room change (DES-B §5.3.3).
        await tx.execute('UPDATE device_state SET gateway_removed = ? ' +
          'WHERE gateway_id = ? AND device_id = ?', [1, key.gatewayId, key.deviceId]);
        gatewayRemovedMarked++;
        events.push(new DeviceChangeEvent(DeviceChangeEventType.GATEWAY_REMOVED, key));
      }
    }

    return new DiscoverApplyResult(added, updated, unchanged, staleDropped, tombstonedSkipped,
      invalidDropped, gatewayRemovedMarked, snapshot.isPartial || invalidDropped > 0,
      deviations, affectedKeys);
  }

  // ---- Control / cloud state application ---------------------------------

  async applyControlAck(context: ControlApplyContext,
    outcome: ControlOutcome): Promise<ControlApplyResult> {
    this.ensureInitialized();
    return this.gate.run(async (): Promise<ControlApplyResult> => {
      const events: DeviceChangeEvent[] = [];
      const result = await this.rdb.transaction<ControlApplyResult>(
        async (tx: RdbTransaction): Promise<ControlApplyResult> => {
          return this.applyStateInTransaction(tx, context, outcome.reportedState,
            outcome.stateVerification, outcome.ackAccepted, outcome.shouldApplyState,
            outcome.idempotentReplay, outcome.requestId, outcome.seq, events);
        });
      this.dispatchEvents(events);
      return result;
    });
  }

  async applyCloudState(context: ControlApplyContext,
    reportedState: DeviceStatePatch | undefined, verification: StateVerification,
    requestId: string, seq: number, accepted: boolean): Promise<ControlApplyResult> {
    this.ensureInitialized();
    return this.gate.run(async (): Promise<ControlApplyResult> => {
      const events: DeviceChangeEvent[] = [];
      const result = await this.rdb.transaction<ControlApplyResult>(
        async (tx: RdbTransaction): Promise<ControlApplyResult> => {
          return this.applyStateInTransaction(tx, context, reportedState, verification, accepted,
            accepted, false, requestId, seq, events);
        });
      this.dispatchEvents(events);
      return result;
    });
  }

  private async applyStateInTransaction(tx: RdbTransaction, context: ControlApplyContext,
    patch: DeviceStatePatch | undefined,
    verification: StateVerification,
    ackAccepted: boolean, shouldApply: boolean, idempotentReplay: boolean,
    requestId: string, seq: number,
    events: DeviceChangeEvent[]): Promise<ControlApplyResult> {
    const key = new DeviceKey(context.gatewayId, context.deviceId);
    const row = await this.readRow(tx, key);
    if (row === undefined) {
      return new ControlApplyResult(ackAccepted, false, verification,
        ControlApplyReason.DEVICE_NOT_FOUND);
    }
    if (patch !== undefined && patch.deviceId !== context.deviceId) {
      return new ControlApplyResult(ackAccepted, false, verification,
        ControlApplyReason.DEVICE_MISMATCH, this.recordFromRow(row));
    }
    if (!ackAccepted) {
      return new ControlApplyResult(false, false, verification,
        ControlApplyReason.ACK_NOT_ACCEPTED, this.recordFromRow(row));
    }
    if (!shouldApply || patch === undefined) {
      return new ControlApplyResult(ackAccepted, false, verification,
        idempotentReplay ? ControlApplyReason.IDEMPOTENT_REPLAY :
          ControlApplyReason.NO_REPORTED_STATE, this.recordFromRow(row));
    }
    const lastRequestId = SqlCells.optionalString(row, 'last_applied_request_id');
    const lastSeq = SqlCells.optionalNumber(row, 'last_applied_seq');
    if (idempotentReplay && lastRequestId === requestId && lastSeq === seq) {
      return new ControlApplyResult(true, false, verification,
        ControlApplyReason.IDEMPOTENT_REPLAY, this.recordFromRow(row));
    }
    const priorEpoch = SqlCells.requiredNumber(row, 'state_epoch_ms');
    if (patch.stateEpochMs < priorEpoch) {
      // Execution is confirmed by ackAccepted; the state is simply older.
      return new ControlApplyResult(ackAccepted, false, verification,
        ControlApplyReason.STALE_STATE_DROPPED, this.recordFromRow(row));
    }
    const oldSnapshot = DeviceSnapshotCodec.decode(
      SqlCells.requiredString(row, 'snapshot_json'));
    const merged = DeviceRepository.applyPatch(oldSnapshot, patch);
    const nextEpoch = priorEpoch > patch.stateEpochMs ? priorEpoch : patch.stateEpochMs;
    await tx.execute('UPDATE device_state SET snapshot_json = ?, state_epoch_ms = ?, ' +
      'last_merge_at = ?, last_applied_request_id = ?, last_applied_seq = ? ' +
      'WHERE gateway_id = ? AND device_id = ?',
    [DeviceSnapshotCodec.encode(merged), nextEpoch,
      DateTimeUtil.formatUtcCompact(this.clock.nowMs()), requestId, seq,
      key.gatewayId, key.deviceId]);
    const refreshed = await this.readRow(tx, key);
    const record = refreshed === undefined ? undefined : this.recordFromRow(refreshed);
    events.push(new DeviceChangeEvent(DeviceChangeEventType.STATE_APPLIED, key));
    return new ControlApplyResult(true, true, verification, ControlApplyReason.APPLIED, record);
  }

  // ---- Queries ------------------------------------------------------------

  async getRecord(key: DeviceKey): Promise<DeviceRecord | undefined> {
    this.ensureInitialized();
    return this.gate.run(async (): Promise<DeviceRecord | undefined> => {
      const row = await this.readRow(this.rdb, key);
      if (row === undefined) {
        return undefined;
      }
      if (await this.isDismissedIn(this.rdb, key)) {
        return undefined;
      }
      return this.recordFromRow(row);
    });
  }

  async isDismissed(key: DeviceKey): Promise<boolean> {
    this.ensureInitialized();
    return this.gate.run(async (): Promise<boolean> => {
      return this.isDismissedIn(this.rdb, key);
    });
  }

  async listRecords(familyId: string): Promise<ReadonlyArray<DeviceRecord>> {
    this.ensureInitialized();
    const checked = DeviceRepository.requireIdentifier(familyId, 'familyId');
    return this.gate.run(async (): Promise<ReadonlyArray<DeviceRecord>> => {
      const rows = await this.rdb.query('SELECT ' + DEVICE_COLUMNS +
        ' FROM device_state WHERE family_id = ?', [checked]);
      return this.mapVisibleRecords(this.rdb, rows);
    });
  }

  async listRecordsByRoom(familyId: string, roomId: string): Promise<ReadonlyArray<DeviceRecord>> {
    this.ensureInitialized();
    const checkedFamily = DeviceRepository.requireIdentifier(familyId, 'familyId');
    const checkedRoom = DeviceRepository.requireRoomId(roomId);
    return this.gate.run(async (): Promise<ReadonlyArray<DeviceRecord>> => {
      const rows = await this.rdb.query('SELECT ' + DEVICE_COLUMNS +
        ' FROM device_state WHERE family_id = ?', [checkedFamily]);
      const filtered: RdbRow[] = [];
      for (let index = 0; index < rows.length; index++) {
        if (SqlCells.requiredString(rows[index], 'room_id') === checkedRoom) {
          filtered.push(rows[index]);
        }
      }
      return this.mapVisibleRecords(this.rdb, filtered);
    });
  }

  async listUnassigned(familyId: string): Promise<ReadonlyArray<DeviceRecord>> {
    this.ensureInitialized();
    const checked = DeviceRepository.requireIdentifier(familyId, 'familyId');
    return this.gate.run(async (): Promise<ReadonlyArray<DeviceRecord>> => {
      const rows = await this.rdb.query('SELECT ' + DEVICE_COLUMNS +
        ' FROM device_state WHERE family_id = ?', [checked]);
      const filtered: RdbRow[] = [];
      for (let index = 0; index < rows.length; index++) {
        if (SqlCells.requiredNumber(rows[index], 'is_unassigned') !== 0) {
          filtered.push(rows[index]);
        }
      }
      return this.mapVisibleRecords(this.rdb, filtered);
    });
  }

  async listByRoom(familyId: string, roomId: string): Promise<ReadonlyArray<DeviceState>> {
    const records = await this.listRecordsByRoom(familyId, roomId);
    const states: DeviceState[] = [];
    for (let index = 0; index < records.length; index++) {
      states.push(records[index].state);
    }
    return states;
  }

  async listDismissed(gatewayId: string): Promise<ReadonlyArray<DeviceKey>> {
    this.ensureInitialized();
    const checked = DeviceRepository.requireGatewayId(gatewayId);
    return this.gate.run(async (): Promise<ReadonlyArray<DeviceKey>> => {
      const rows = await this.rdb.query('SELECT device_id FROM gw_dismissed_device ' +
        'WHERE gateway_id = ?', [checked]);
      const keys: DeviceKey[] = [];
      for (let index = 0; index < rows.length; index++) {
        keys.push(new DeviceKey(checked, SqlCells.requiredString(rows[index], 'device_id')));
      }
      return keys;
    });
  }

  async listDeviceNamesByRoom(familyId: string, roomId: string): Promise<ReadonlyArray<string>> {
    const records = await this.listRecordsByRoom(familyId, roomId);
    const names: string[] = [];
    for (let index = 0; index < records.length; index++) {
      names.push(records[index].state.deviceName);
    }
    return names;
  }

  // ---- Local lifecycle ----------------------------------------------------

  async onRoomDeleted(tx: RdbTransaction, familyId: string, roomId: string): Promise<number> {
    const checkedFamily = DeviceRepository.requireIdentifier(familyId, 'familyId');
    const checkedRoom = DeviceRepository.requireRoomId(roomId);
    const rows = await tx.query('SELECT ' + DEVICE_COLUMNS +
      ' FROM device_state WHERE family_id = ?', [checkedFamily]);
    let affected = 0;
    for (let index = 0; index < rows.length; index++) {
      if (SqlCells.requiredString(rows[index], 'room_id') !== checkedRoom) {
        continue;
      }
      const key = new DeviceKey(SqlCells.requiredString(rows[index], 'gateway_id'),
        SqlCells.requiredString(rows[index], 'device_id'));
      // Protective disable, no physical deletion (FR-ROOM-004/DP-02).
      await tx.execute('UPDATE device_state SET room_id = ?, is_unassigned = ?, ' +
        'is_enabled = ? WHERE gateway_id = ? AND device_id = ?',
      ['', 1, 0, key.gatewayId, key.deviceId]);
      affected++;
    }
    return affected;
  }

  async countByRoom(familyId: string, roomId: string): Promise<number> {
    this.ensureInitialized();
    return this.gate.run(async (): Promise<number> => {
      return this.countByRoomInTransaction(this.rdb, familyId, roomId);
    });
  }

  async countByRoomInTransaction(tx: RdbTransaction, familyId: string,
    roomId: string): Promise<number> {
    const checkedFamily = DeviceRepository.requireIdentifier(familyId, 'familyId');
    const checkedRoom = DeviceRepository.requireRoomId(roomId);
    const rows = await tx.query('SELECT room_id FROM device_state WHERE family_id = ?',
      [checkedFamily]);
    let count = 0;
    for (let index = 0; index < rows.length; index++) {
      if (SqlCells.requiredString(rows[index], 'room_id') === checkedRoom) {
        count++;
      }
    }
    return count;
  }

  async assignRoom(familyId: string, key: DeviceKey,
    targetRoomId: string): Promise<DeviceState> {
    this.ensureInitialized();
    const checkedFamily = DeviceRepository.requireIdentifier(familyId, 'familyId');
    const checkedRoom = DeviceRepository.requireRoomId(targetRoomId);
    return this.gate.run(async (): Promise<DeviceState> => {
      return this.rdb.transaction<DeviceState>(async (tx: RdbTransaction): Promise<DeviceState> => {
        const room = await this.rooms.readRoomInTransaction(tx, checkedRoom);
        if (room === undefined || room.familyId !== checkedFamily) {
          // The port itself enforces the family boundary; RoomService's
          // pre-check alone cannot protect other callers (wp-026 R-07).
          throw AppErrors.of('ROOM_NOT_FOUND', []);
        }
        await this.requireWritableDevice(tx, checkedFamily, key);
        await tx.execute('UPDATE device_state SET room_id = ?, is_unassigned = ?, ' +
          'is_enabled = ? WHERE gateway_id = ? AND device_id = ?',
        [checkedRoom, 0, 1, key.gatewayId, key.deviceId]);
        return this.requireState(tx, key);
      });
    });
  }

  async unassignDevice(familyId: string, key: DeviceKey): Promise<DeviceState> {
    this.ensureInitialized();
    const checkedFamily = DeviceRepository.requireIdentifier(familyId, 'familyId');
    return this.gate.run(async (): Promise<DeviceState> => {
      return this.rdb.transaction<DeviceState>(async (tx: RdbTransaction): Promise<DeviceState> => {
        await this.requireWritableDevice(tx, checkedFamily, key);
        await tx.execute('UPDATE device_state SET room_id = ?, is_unassigned = ?, ' +
          'is_enabled = ? WHERE gateway_id = ? AND device_id = ?',
        ['', 1, 0, key.gatewayId, key.deviceId]);
        return this.requireState(tx, key);
      });
    });
  }

  async renameDevice(familyId: string, key: DeviceKey, deviceName: string): Promise<void> {
    this.ensureInitialized();
    const checkedFamily = DeviceRepository.requireIdentifier(familyId, 'familyId');
    const name = DeviceRepository.deviceName(deviceName);
    return this.gate.run(async (): Promise<void> => {
      await this.rdb.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
        await this.requireWritableDevice(tx, checkedFamily, key);
        // Local rename only: never sends SET_DEVICE_NAME and never touches IDs.
        await tx.execute('UPDATE device_state SET device_name = ? ' +
          'WHERE gateway_id = ? AND device_id = ?', [name, key.gatewayId, key.deviceId]);
      });
    });
  }

  async removeDevice(familyId: string, key: DeviceKey,
    options?: DeviceRemovalOptions): Promise<DeviceRemovalResult> {
    this.ensureInitialized();
    const checkedFamily = DeviceRepository.requireIdentifier(familyId, 'familyId');
    const nowMs = options === undefined ? this.clock.nowMs() : options.nowMs;
    const removeSceneReferences = options === undefined ? true : options.removeSceneReferences;
    return this.gate.run(async (): Promise<DeviceRemovalResult> => {
      const events: DeviceChangeEvent[] = [];
      const result = await this.rdb.transaction<DeviceRemovalResult>(
        async (tx: RdbTransaction): Promise<DeviceRemovalResult> => {
          const row = await this.readRow(tx, key);
          if (row === undefined ||
            SqlCells.requiredString(row, 'family_id') !== checkedFamily) {
            throw AppErrors.of('DEVICE_NOT_FOUND', []);
          }
          let cleanup: SceneCleanupSummary | undefined = undefined;
          if (removeSceneReferences) {
            cleanup = await this.scenes.removeDeviceReferences(tx, checkedFamily, key);
          }
          await tx.execute('DELETE FROM device_state WHERE gateway_id = ? AND device_id = ?',
            [key.gatewayId, key.deviceId]);
          await tx.execute('INSERT OR IGNORE INTO gw_dismissed_device ' +
            '(gateway_id, device_id, dismissed_at) VALUES (?, ?, ?)',
          [key.gatewayId, key.deviceId, DateTimeUtil.formatUtcCompact(nowMs)]);
          this.mergeStates.delete(key.globalId());
          this.partialKeys.delete(key.globalId());
          events.push(new DeviceChangeEvent(DeviceChangeEventType.DEVICE_DISMISSED, key));
          return new DeviceRemovalResult(true, key, true, cleanup);
        });
      this.dispatchEvents(events);
      return result;
    });
  }

  async restoreDevice(gatewayId: string, deviceId: string): Promise<boolean> {
    this.ensureInitialized();
    const key = new DeviceKey(DeviceRepository.requireGatewayId(gatewayId), deviceId);
    return this.gate.run(async (): Promise<boolean> => {
      const events: DeviceChangeEvent[] = [];
      const restored = await this.rdb.transaction<boolean>(
        async (tx: RdbTransaction): Promise<boolean> => {
          const rows = await tx.query('SELECT device_id FROM gw_dismissed_device ' +
            'WHERE gateway_id = ? AND device_id = ?', [key.gatewayId, key.deviceId]);
          if (rows.length === 0) {
            return false;
          }
          await tx.execute('DELETE FROM gw_dismissed_device ' +
            'WHERE gateway_id = ? AND device_id = ?', [key.gatewayId, key.deviceId]);
          // Old snapshot is deliberately not restored: the next discover re-adds
          // the device in the unassigned/disabled pool (DES-B §5.3.4).
          await tx.execute('DELETE FROM device_state WHERE gateway_id = ? AND device_id = ?',
            [key.gatewayId, key.deviceId]);
          this.mergeStates.delete(key.globalId());
          this.partialKeys.delete(key.globalId());
          events.push(new DeviceChangeEvent(DeviceChangeEventType.DEVICE_RESTORED, key));
          return true;
        });
      this.dispatchEvents(events);
      return restored;
    });
  }

  async removeDevicesForGateway(gatewayId: string): Promise<number> {
    this.ensureInitialized();
    const checked = DeviceRepository.requireGatewayId(gatewayId);
    return this.gate.run(async (): Promise<number> => {
      // GatewayRoutePort is not transaction-context; read the route before the
      // transaction opens so the tx callback only touches `tx` (wp-026 R-13).
      let routeFamilyId: string | undefined = undefined;
      if (this.routes !== undefined) {
        const route = await this.routes.getRoute(checked);
        if (route !== undefined) {
          routeFamilyId = route.familyId;
        }
      }
      return this.rdb.transaction<number>(async (tx: RdbTransaction): Promise<number> => {
        const rows = await tx.query('SELECT ' + DEVICE_COLUMNS +
          ' FROM device_state WHERE gateway_id = ?', [checked]);
        const families: string[] = [];
        const seenFamilies: Map<string, boolean> = new Map<string, boolean>();
        if (routeFamilyId !== undefined) {
          seenFamilies.set(routeFamilyId, true);
          families.push(routeFamilyId);
        }
        let removed = 0;
        for (let index = 0; index < rows.length; index++) {
          const familyId = SqlCells.requiredString(rows[index], 'family_id');
          if (!seenFamilies.has(familyId)) {
            seenFamilies.set(familyId, true);
            families.push(familyId);
          }
          const deviceId = SqlCells.requiredString(rows[index], 'device_id');
          await tx.execute('DELETE FROM device_state WHERE gateway_id = ? AND device_id = ?',
            [checked, deviceId]);
          this.mergeStates.delete(checked + ':' + deviceId);
          this.partialKeys.delete(checked + ':' + deviceId);
          removed++;
        }
        for (let index = 0; index < families.length; index++) {
          await this.scenes.removeGatewayReferences(tx, families[index], checked);
        }
        return removed;
      });
    });
  }

  async markGatewayRemoved(gatewayId: string): Promise<number> {
    this.ensureInitialized();
    const checked = DeviceRepository.requireGatewayId(gatewayId);
    return this.gate.run(async (): Promise<number> => {
      return this.rdb.transaction<number>(async (tx: RdbTransaction): Promise<number> => {
        const rows = await tx.query('SELECT device_id, gateway_removed FROM device_state ' +
          'WHERE gateway_id = ?', [checked]);
        let changed = 0;
        for (let index = 0; index < rows.length; index++) {
          if (SqlCells.requiredNumber(rows[index], 'gateway_removed') !== 0) {
            continue;
          }
          await tx.execute('UPDATE device_state SET gateway_removed = ? ' +
            'WHERE gateway_id = ? AND device_id = ?',
          [1, checked, SqlCells.requiredString(rows[index], 'device_id')]);
          changed++;
        }
        return changed;
      });
    });
  }

  // ---- Events -------------------------------------------------------------

  subscribe(listener: (event: DeviceChangeEvent) => void): () => void {
    this.listeners.push(listener);
    return (): void => {
      const index = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    };
  }

  dispose(): void {
    this.listeners.splice(0, this.listeners.length);
    this.mergeStates.clear();
    this.partialKeys.clear();
  }

  // ---- Internals ----------------------------------------------------------

  private static mergeSnapshots(oldSnapshot: DeviceSnapshot,
    incoming: DeviceSnapshot): DeviceSnapshot {
    const init = new DeviceSnapshotInit();
    init.deviceId = oldSnapshot.deviceId;
    init.deviceName = incoming.deviceName;
    init.roomNameHint = incoming.roomNameHint;
    init.deviceTypeRaw = incoming.deviceTypeRaw;
    if (incoming.deviceType !== undefined) {
      init.deviceType = incoming.deviceType;
    } else if (incoming.deviceTypeRaw === oldSnapshot.deviceTypeRaw) {
      init.deviceType = oldSnapshot.deviceType;
    } else {
      init.deviceType = undefined;
    }
    init.isSupported = incoming.isSupported;
    init.brand = incoming.brand === undefined ? oldSnapshot.brand : incoming.brand;
    // Offline is not an erase: only the online flag changes; last known values
    // survive (ADR-004 §2.5).
    init.isOnline = incoming.isOnline;
    init.powerStatus = incoming.powerStatus === undefined ? oldSnapshot.powerStatus :
      incoming.powerStatus;
    init.openStatus = incoming.openStatus === undefined ? oldSnapshot.openStatus :
      incoming.openStatus;
    init.brightness = incoming.brightness === undefined ? oldSnapshot.brightness :
      incoming.brightness;
    init.color = incoming.color === undefined ? oldSnapshot.color : incoming.color;
    init.temperature = incoming.temperature === undefined ? oldSnapshot.temperature :
      incoming.temperature;
    init.humidity = incoming.humidity === undefined ? oldSnapshot.humidity : incoming.humidity;
    init.presence = incoming.presence === undefined ? oldSnapshot.presence : incoming.presence;
    init.targetTemperature = incoming.targetTemperature === undefined ?
      oldSnapshot.targetTemperature : incoming.targetTemperature;
    if (incoming.mode === undefined) {
      init.mode = oldSnapshot.mode;
      init.modeStandard = oldSnapshot.modeStandard;
    } else {
      init.mode = incoming.mode;
      init.modeStandard = incoming.modeStandard;
    }
    if (incoming.stateSource === undefined) {
      init.stateSource = oldSnapshot.stateSource;
      init.stateSourceKnown = oldSnapshot.stateSourceKnown;
    } else {
      init.stateSource = incoming.stateSource;
      init.stateSourceKnown = incoming.stateSourceKnown;
    }
    init.triggerDeviceId = incoming.triggerDeviceId === undefined ?
      oldSnapshot.triggerDeviceId : incoming.triggerDeviceId;
    init.automationId = incoming.automationId === undefined ?
      oldSnapshot.automationId : incoming.automationId;
    init.lastRequestId = incoming.lastRequestId === undefined ? oldSnapshot.lastRequestId :
      incoming.lastRequestId;
    init.lastSeq = incoming.lastSeq === undefined ? oldSnapshot.lastSeq : incoming.lastSeq;
    init.updatedAt = incoming.updatedAt;
    return DeviceSnapshot.create(init);
  }

  private static applyPatch(oldSnapshot: DeviceSnapshot, patch: DeviceStatePatch): DeviceSnapshot {
    const init = new DeviceSnapshotInit();
    init.deviceId = oldSnapshot.deviceId;
    init.deviceName = oldSnapshot.deviceName;
    init.roomNameHint = oldSnapshot.roomNameHint;
    init.deviceTypeRaw = oldSnapshot.deviceTypeRaw;
    init.deviceType = oldSnapshot.deviceType;
    init.isSupported = oldSnapshot.isSupported;
    init.brand = oldSnapshot.brand;
    init.isOnline = patch.isOnline;
    init.powerStatus = patch.powerStatus === undefined ? oldSnapshot.powerStatus :
      patch.powerStatus;
    init.openStatus = patch.openStatus === undefined ? oldSnapshot.openStatus : patch.openStatus;
    init.brightness = patch.brightness === undefined ? oldSnapshot.brightness : patch.brightness;
    init.color = patch.color === undefined ? oldSnapshot.color : patch.color;
    init.temperature = patch.temperature === undefined ? oldSnapshot.temperature :
      patch.temperature;
    init.humidity = patch.humidity === undefined ? oldSnapshot.humidity : patch.humidity;
    init.presence = patch.presence === undefined ? oldSnapshot.presence : patch.presence;
    init.targetTemperature = patch.targetTemperature === undefined ?
      oldSnapshot.targetTemperature : patch.targetTemperature;
    if (patch.mode === undefined) {
      init.mode = oldSnapshot.mode;
      init.modeStandard = oldSnapshot.modeStandard;
    } else {
      init.mode = patch.mode;
      init.modeStandard = patch.modeStandard;
    }
    if (patch.stateSource === undefined) {
      init.stateSource = oldSnapshot.stateSource;
      init.stateSourceKnown = oldSnapshot.stateSourceKnown;
    } else {
      init.stateSource = patch.stateSource;
      init.stateSourceKnown = patch.stateSourceKnown;
    }
    init.triggerDeviceId = patch.triggerDeviceId === undefined ? oldSnapshot.triggerDeviceId :
      patch.triggerDeviceId;
    init.automationId = patch.automationId === undefined ? oldSnapshot.automationId :
      patch.automationId;
    init.lastRequestId = patch.lastRequestId === undefined ? oldSnapshot.lastRequestId :
      patch.lastRequestId;
    init.lastSeq = patch.lastSeq === undefined ? oldSnapshot.lastSeq : patch.lastSeq;
    init.updatedAt = patch.updatedAt;
    return DeviceSnapshot.create(init);
  }

  private async readRow(tx: RdbTransaction, key: DeviceKey): Promise<RdbRow | undefined> {
    const rows = await tx.query('SELECT ' + DEVICE_COLUMNS + ' FROM device_state ' +
      'WHERE gateway_id = ? AND device_id = ?', [key.gatewayId, key.deviceId]);
    if (rows.length === 0) {
      return undefined;
    }
    return rows[0];
  }

  private async isDismissedIn(tx: RdbTransaction, key: DeviceKey): Promise<boolean> {
    const rows = await tx.query('SELECT device_id FROM gw_dismissed_device ' +
      'WHERE gateway_id = ? AND device_id = ?', [key.gatewayId, key.deviceId]);
    return rows.length > 0;
  }

  private async requireWritableDevice(tx: RdbTransaction, familyId: string,
    key: DeviceKey): Promise<void> {
    const row = await this.readRow(tx, key);
    if (row === undefined) {
      if (await this.isDismissedIn(tx, key)) {
        throw AppErrors.of('DEVICE_DISMISSED', []);
      }
      throw AppErrors.of('DEVICE_NOT_FOUND', []);
    }
    if (SqlCells.requiredString(row, 'family_id') !== familyId) {
      throw AppErrors.of('DEVICE_NOT_FOUND', []);
    }
  }

  private async requireState(tx: RdbTransaction, key: DeviceKey): Promise<DeviceState> {
    const row = await this.readRow(tx, key);
    if (row === undefined) {
      throw AppErrors.of('DEVICE_NOT_FOUND', []);
    }
    return this.stateFromRow(row);
  }

  private async mapVisibleRecords(tx: RdbTransaction,
    rows: ReadonlyArray<RdbRow>): Promise<ReadonlyArray<DeviceRecord>> {
    const records: DeviceRecord[] = [];
    for (let index = 0; index < rows.length; index++) {
      const key = new DeviceKey(SqlCells.requiredString(rows[index], 'gateway_id'),
        SqlCells.requiredString(rows[index], 'device_id'));
      if (await this.isDismissedIn(tx, key)) {
        continue;
      }
      records.push(this.recordFromRow(rows[index]));
    }
    return records;
  }

  private recordFromRow(row: RdbRow): DeviceRecord {
    const key = new DeviceKey(SqlCells.requiredString(row, 'gateway_id'),
      SqlCells.requiredString(row, 'device_id'));
    const state = this.stateFromRow(row);
    const merge = this.mergeStateFor(key, row);
    return new DeviceRecord(state, merge,
      SqlCells.requiredNumber(row, 'gateway_removed') !== 0,
      this.partialKeys.has(key.globalId()));
  }

  private stateFromRow(row: RdbRow): DeviceState {
    try {
      const key = new DeviceKey(SqlCells.requiredString(row, 'gateway_id'),
        SqlCells.requiredString(row, 'device_id'));
      const snapshot = DeviceSnapshotCodec.decode(SqlCells.requiredString(row, 'snapshot_json'));
      return new DeviceState(key, SqlCells.requiredString(row, 'family_id'), snapshot,
        SqlCells.requiredString(row, 'device_name'), SqlCells.requiredString(row, 'room_id'),
        SqlCells.requiredNumber(row, 'is_enabled') !== 0,
        SqlCells.requiredNumber(row, 'is_unassigned') !== 0, false);
    } catch (error) {
      if (error instanceof AppError && error.code.startsWith('STORAGE_')) {
        throw error;
      }
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
  }

  private mergeStateFor(key: DeviceKey, row: RdbRow): DeviceMergeState {
    const cached = this.mergeStates.get(key.globalId());
    if (cached !== undefined) {
      return cached;
    }
    let atMs = 0;
    const lastMergeAt = SqlCells.optionalString(row, 'last_merge_at');
    if (lastMergeAt !== undefined) {
      try {
        atMs = DateTimeUtil.parseUtcCompact(lastMergeAt);
      } catch (error) {
        atMs = 0;
      }
    }
    // Merge diagnostics are process-local; after a restart the durable facts
    // remain state_epoch_ms and last_merge_at.
    return new DeviceMergeState(atMs, SqlCells.requiredNumber(row, 'state_epoch_ms'),
      DeviceMergeResult.UNCHANGED);
  }

  private rememberMerge(key: DeviceKey, result: DeviceMergeResult, atMs: number, epochMs: number,
    deviation?: string): void {
    this.mergeStates.set(key.globalId(),
      new DeviceMergeState(atMs, epochMs, result, deviation));
  }

  private dispatchEvents(events: ReadonlyArray<DeviceChangeEvent>): void {
    for (let index = 0; index < events.length; index++) {
      this.emit(events[index]);
    }
  }

  private emit(event: DeviceChangeEvent): void {
    // A subscriber is a notification consumer, never a participant in the
    // committed fact. A throwing listener is isolated and diagnosed.
    const snapshot = this.listeners.slice(0);
    for (let index = 0; index < snapshot.length; index++) {
      try {
        snapshot[index](event);
      } catch (error) {
        this.logger.warn('DeviceRepository', 'device_listener_failed',
          [new NameValue('event', event.type)]);
      }
    }
  }

  private static emptyResult(partial: boolean,
    deviations: ReadonlyArray<string>): DiscoverApplyResult {
    return new DiscoverApplyResult(0, 0, 0, 0, 0, 0, 0, partial, deviations, []);
  }

  private static deviceName(value: string): string {
    const trimmed = value.trim();
    if (trimmed.length < 1 || trimmed.length > 31) {
      throw AppErrors.of('DEVICE_NAME_INVALID', []);
    }
    return trimmed;
  }

  private static requireIdentifier(value: string, field: string): string {
    if (value.length === 0 || value.length > 63 || value.indexOf(':') >= 0 ||
      !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(value)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', field);
    }
    return value;
  }

  private static requireGatewayId(value: string): string {
    if (value.length === 0 || value.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      value.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(value)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'gatewayId');
    }
    return value;
  }

  private static requireRoomId(value: string): string {
    if (!UuidUtil.isValidUuid(value)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'roomId');
    }
    return value;
  }

  private static storageError(error: Error): Error {
    if (error instanceof AppError) {
      return error;
    }
    return AppErrors.of('STORAGE_RDB_ERROR', []);
  }

  private ensureInitialized(): void {
    if (!this.initialized) {
      throw AppErrors.of('STORAGE_NOT_INITIALIZED', []);
    }
  }
}
