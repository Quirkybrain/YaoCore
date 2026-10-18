/*
 * YaoCore C-11 device control/state ports.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-A §27.6.3 P1 / DES-B §23.1.
 * Contract: DES-B §5.1.2 (EXT-DES-B-07..08)
 *
 * Port-only declarations; no platform import and no implementation.
 */
import type { DeviceControlCommand, ControlOutcome } from '../model/ControlModels';
import type { DiscoverySnapshot } from '../model/DiscoveryModels';
import type { DeviceKey } from '../model/DeviceKey';
import type {
  ControlApplyContext,
  ControlApplyResult,
  DeviceRecord,
  DiscoverApplyOptions,
  DiscoverApplyResult
} from '../model/DeviceRecord';

export interface DeviceControlPort {
  send(command: DeviceControlCommand): Promise<ControlOutcome>;
}

export interface DeviceStatePort {
  applyDiscoverSnapshot(snapshot: DiscoverySnapshot,
    options?: DiscoverApplyOptions): Promise<DiscoverApplyResult>;
  applyControlAck(context: ControlApplyContext,
    outcome: ControlOutcome): Promise<ControlApplyResult>;
}

/** Read-only record lookup used by C-11 preflight. */
export interface DeviceRecordQueryPort {
  getRecord(key: DeviceKey): Promise<DeviceRecord | undefined>;
  listRecords(familyId: string): Promise<ReadonlyArray<DeviceRecord>>;
  listRecordsByRoom(familyId: string, roomId: string): Promise<ReadonlyArray<DeviceRecord>>;
  listUnassigned(familyId: string): Promise<ReadonlyArray<DeviceRecord>>;
}
