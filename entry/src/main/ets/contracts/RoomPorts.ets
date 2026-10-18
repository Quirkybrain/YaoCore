/*
 * YaoCore C-08/C-09 cross-repository room ports.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-A §27.6.3 P1 / DES-B §23.1.
 * Contract: DES-B §3.1.5, §4.1.1 (EXT-DES-B-04..05)
 *
 * Port-only declarations; no platform import and no implementation.
 */
import type { RdbTransaction } from './RdbStore';
import type { Room } from '../model/FamilyModels';
import type { DeviceKey } from '../model/DeviceKey';
import type { DeviceState } from '../model/DeviceState';

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
