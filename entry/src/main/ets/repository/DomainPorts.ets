/*
 * YaoCore C-08..C-11 cross-component ports.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §3.1.5, §4.1.1, §5.1.2, §6.1.2 (EXT-DES-B-04..08)
 *
 * LOCATION EXCEPTION: DES-B nominally places ports under contracts/**. T-09's
 * delegated write scope is repository/**, so they stay next to the
 * implementations (same recorded pattern as C-07 GatewayPorts.ets). These are
 * pure interfaces; no platform import and no implementation.
 */
import type { RdbTransaction } from '../service/storage/RdbStore';
import type { Room } from '../model/FamilyModels';
import type { DeviceKey } from '../model/DeviceKey';
import type { DeviceState } from '../model/DeviceState';
import type { DiscoverySnapshot } from '../model/DiscoveryModels';
import type { ControlOutcome, DeviceControlCommand } from '../model/ControlModels';
import type {
  ControlApplyContext,
  ControlApplyResult,
  DeviceRecord,
  DiscoverApplyOptions,
  DiscoverApplyResult,
  SceneCleanupSummary
} from './DomainModels';

export interface RoomLookupPort {
  getRoom(roomId: string): Promise<Room | undefined>;
  exists(roomId: string): Promise<boolean>;
  listRooms(familyId: string): Promise<ReadonlyArray<Room>>;
  /** Transaction-context existence/read for C-10 assignment (O-1). */
  readRoomInTransaction(tx: RdbTransaction, roomId: string): Promise<Room | undefined>;
}

export interface DeviceAssignmentPort {
  /** Transaction-context: mark this room's devices unassigned/disabled. */
  onRoomDeleted(tx: RdbTransaction, familyId: string, roomId: string): Promise<number>;

  /** Assign/move to an existing room; validates the room through RoomLookupPort. */
  assignRoom(familyId: string, key: DeviceKey, targetRoomId: string): Promise<DeviceState>;

  /** Manual move to the unassigned pool (protective disable). */
  unassignDevice(familyId: string, key: DeviceKey): Promise<DeviceState>;

  /** Read-only count used by room deletion confirmation. */
  countByRoom(familyId: string, roomId: string): Promise<number>;

  /** Transaction-context re-check for room deletion race protection. */
  countByRoomInTransaction(tx: RdbTransaction, familyId: string,
    roomId: string): Promise<number>;
}

/** Optional companion port used by RoomService.previewDelete for device names. */
export interface RoomDeviceNamePort {
  listDeviceNamesByRoom(familyId: string, roomId: string): Promise<ReadonlyArray<string>>;
}

export interface MemberRoomGrantPort {
  /** Transaction-context: remove a room id from every member grant. */
  removeRoomGrant(tx: RdbTransaction, familyId: string, roomId: string): Promise<number>;
}

export interface SceneReferencePort {
  removeDeviceReferences(tx: RdbTransaction, familyId: string,
    key: DeviceKey): Promise<SceneCleanupSummary>;
  removeGatewayReferences(tx: RdbTransaction, familyId: string,
    gatewayId: string): Promise<SceneCleanupSummary>;
  listSceneIdsReferencing(tx: RdbTransaction, familyId: string,
    key: DeviceKey): Promise<ReadonlyArray<string>>;
}

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
