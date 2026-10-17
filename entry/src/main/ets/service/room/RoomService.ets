/*
 * YaoCore C-09 RoomService.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §4.1.3, §4.3.2, §4.3.3
 *
 * Room deletion is a single local RDB transaction: delete room, move its
 * devices to the unassigned/disabled pool, and remove member room grants.
 * Devices are never physically deleted and no LAN/cloud request is issued
 * (FR-ROOM-004; DP-01/DP-02).
 *
 * O-1: the whole deletion is one top-level transaction executed under the
 * shared DomainOperationGate; every collaborator called inside it is a
 * transaction-context port method. No nested transaction is possible.
 */
import { AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import type { ClockPort, LoggerPort } from '../../common/types/Ports';
import type { RdbStore, RdbTransaction } from '../storage/RdbStore';
import { MemberStatus, Room } from '../../model/FamilyModels';
import type { FamilyMember } from '../../model/FamilyModels';
import { DeviceKey } from '../../model/DeviceKey';
import { DeviceState } from '../../model/DeviceState';
import { DomainOperationGate } from '../../repository/DomainOperationGate';
import { RoomRepository } from '../../repository/RoomRepository';
import { FamilyRbac } from '../family/FamilyRbac';
import type {
  DeviceAssignmentPort,
  MemberRoomGrantPort,
  RoomDeviceNamePort
} from '../../repository/DomainPorts';

/**
 * F-03 / CQG-T18: narrow actor lookup used by RoomService to enforce ADMIN for
 * every room/pool mutation. C-12 still owns session policy at the call site;
 * the service refuses a supplied non-admin actor instead of trusting the UI.
 */
export interface RoomActorLookupPort {
  getMember(familyId: string, memberId: string): Promise<FamilyMember | undefined>;
}

export enum RoomChangeEventType {
  ROOM_CREATED = 'ROOM_CREATED',
  ROOM_RENAMED = 'ROOM_RENAMED',
  ROOM_REORDERED = 'ROOM_REORDERED',
  ROOM_DELETED = 'ROOM_DELETED',
  DEVICE_ASSIGNED = 'DEVICE_ASSIGNED'
}

export class RoomChangeEvent {
  readonly type: RoomChangeEventType;
  readonly roomId: string;
  readonly deviceKey?: DeviceKey;

  constructor(type: RoomChangeEventType, roomId: string, deviceKey?: DeviceKey) {
    this.type = type;
    this.roomId = roomId;
    this.deviceKey = deviceKey;
  }
}

export class RoomDeletionPreview {
  readonly room: Room;
  readonly deviceCount: number;
  readonly deviceNames: ReadonlyArray<string>;
  readonly requiresConfirmation: boolean;

  constructor(room: Room, deviceCount: number, deviceNames: ReadonlyArray<string>) {
    this.room = room;
    this.deviceCount = deviceCount;
    this.deviceNames = deviceNames;
    // Blocking confirmation is mandatory (DES-B §4.1.3).
    this.requiresConfirmation = true;
  }
}

export class RoomDeletionConfirmation {
  readonly confirmed: boolean;
  readonly userAcknowledgedDeviceCount: number;

  constructor(confirmed: boolean, userAcknowledgedDeviceCount: number) {
    this.confirmed = confirmed;
    this.userAcknowledgedDeviceCount = userAcknowledgedDeviceCount;
  }
}

export class RoomDeletionResult {
  readonly roomId: string;
  readonly deleted: boolean;
  readonly affectedDeviceCount: number;
  readonly affectedMemberCount: number;

  constructor(roomId: string, deleted: boolean, affectedDeviceCount: number,
    affectedMemberCount: number) {
    this.roomId = roomId;
    this.deleted = deleted;
    this.affectedDeviceCount = affectedDeviceCount;
    this.affectedMemberCount = affectedMemberCount;
  }
}

export class RoomService {
  private readonly rooms: RoomRepository;
  private readonly devices: DeviceAssignmentPort;
  private readonly grants: MemberRoomGrantPort;
  private readonly rdb: RdbStore;
  private readonly clock: ClockPort;
  private readonly logger: LoggerPort;
  private readonly gate: DomainOperationGate;
  private readonly deviceNames?: RoomDeviceNamePort;
  private readonly actors?: RoomActorLookupPort;
  private readonly listeners: Array<(event: RoomChangeEvent) => void> = [];

  constructor(rooms: RoomRepository, devices: DeviceAssignmentPort, grants: MemberRoomGrantPort,
    rdb: RdbStore, clock: ClockPort, logger: LoggerPort, gate?: DomainOperationGate,
    deviceNames?: RoomDeviceNamePort, actors?: RoomActorLookupPort) {
    this.rooms = rooms;
    this.devices = devices;
    this.grants = grants;
    this.rdb = rdb;
    this.clock = clock;
    this.logger = logger;
    this.gate = gate === undefined ? new DomainOperationGate() : gate;
    this.deviceNames = deviceNames;
    this.actors = actors;
  }

  async listRooms(familyId: string): Promise<ReadonlyArray<Room>> {
    return this.rooms.listRoomsOrdered(familyId);
  }

  async createRoom(familyId: string, roomName: string, icon?: string,
    actorMemberId?: string): Promise<Room> {
    await this.requireAdmin(familyId, actorMemberId);
    const room = await this.rooms.createRoom(familyId, roomName, icon);
    this.emit(new RoomChangeEvent(RoomChangeEventType.ROOM_CREATED, room.roomId));
    return room;
  }

  async renameRoom(roomId: string, roomName: string, actorMemberId?: string): Promise<Room> {
    const existing = await this.rooms.getRoom(roomId);
    if (existing === undefined) {
      throw AppErrors.of('ROOM_NOT_FOUND', []);
    }
    await this.requireAdmin(existing.familyId, actorMemberId);
    await this.rooms.updateRoomName(roomId, roomName);
    const room = await this.rooms.getRoom(roomId);
    if (room === undefined) {
      throw AppErrors.of('ROOM_NOT_FOUND', []);
    }
    this.emit(new RoomChangeEvent(RoomChangeEventType.ROOM_RENAMED, room.roomId));
    return room;
  }

  async setIcon(roomId: string, icon: string | undefined,
    actorMemberId?: string): Promise<void> {
    const existing = await this.rooms.getRoom(roomId);
    if (existing === undefined) {
      throw AppErrors.of('ROOM_NOT_FOUND', []);
    }
    await this.requireAdmin(existing.familyId, actorMemberId);
    await this.rooms.updateRoomIcon(roomId, icon);
  }

  async reorderRooms(familyId: string, orderedRoomIds: ReadonlyArray<string>,
    actorMemberId?: string): Promise<void> {
    await this.requireAdmin(familyId, actorMemberId);
    await this.rooms.updateOrder(familyId, orderedRoomIds);
    this.emit(new RoomChangeEvent(RoomChangeEventType.ROOM_REORDERED, ''));
  }

  async previewDelete(roomId: string): Promise<RoomDeletionPreview> {
    const room = await this.rooms.getRoom(roomId);
    if (room === undefined) {
      throw AppErrors.of('ROOM_NOT_FOUND', []);
    }
    const count = await this.devices.countByRoom(room.familyId, room.roomId);
    let names: ReadonlyArray<string> = [];
    if (this.deviceNames !== undefined) {
      names = await this.deviceNames.listDeviceNamesByRoom(room.familyId, room.roomId);
    }
    const limited: string[] = [];
    for (let index = 0; index < names.length && index < 20; index++) {
      limited.push(names[index]);
    }
    return new RoomDeletionPreview(room, count, limited);
  }

  async deleteRoom(roomId: string, confirmation: RoomDeletionConfirmation,
    actorMemberId?: string): Promise<RoomDeletionResult> {
    const initial = await this.rooms.getRoom(roomId);
    if (initial === undefined) {
      throw AppErrors.of('ROOM_NOT_FOUND', []);
    }
    await this.requireAdmin(initial.familyId, actorMemberId);
    if (!confirmation.confirmed) {
      throw AppErrors.of('ROOM_DELETE_NOT_CONFIRMED', []);
    }
    const initialCount = await this.devices.countByRoom(initial.familyId, initial.roomId);
    if (initialCount !== confirmation.userAcknowledgedDeviceCount) {
      // The user confirmed a different device count than the current one.
      throw AppErrors.of('ROOM_DELETE_NOT_CONFIRMED', []);
    }
    return this.gate.run((): Promise<RoomDeletionResult> => {
      return this.rdb.transaction<RoomDeletionResult>(
        async (tx: RdbTransaction): Promise<RoomDeletionResult> => {
          const fresh = await this.rooms.readRoom(tx, roomId);
          if (fresh === undefined) {
            throw AppErrors.of('ROOM_NOT_FOUND', []);
          }
          // Re-check inside the transaction to close the preview/delete race.
          const current = await this.devices.countByRoomInTransaction(tx, fresh.familyId,
            fresh.roomId);
          if (current !== confirmation.userAcknowledgedDeviceCount) {
            throw AppErrors.of('ROOM_DELETE_NOT_CONFIRMED', []);
          }
          await this.rooms.deleteRoom(tx, roomId);
          const affectedDevices = await this.devices.onRoomDeleted(tx, fresh.familyId,
            fresh.roomId);
          const affectedMembers = await this.grants.removeRoomGrant(tx, fresh.familyId,
            fresh.roomId);
          return new RoomDeletionResult(roomId, true, affectedDevices, affectedMembers);
        }).then((result: RoomDeletionResult): RoomDeletionResult => {
        this.emit(new RoomChangeEvent(RoomChangeEventType.ROOM_DELETED, roomId));
        this.logger.info('RoomService', 'room_deleted',
          [new NameValue('roomId', roomId),
            new NameValue('atMs', String(this.clock.nowMs()))]);
        return result;
      });
    });
  }

  async assignDevice(familyId: string, key: DeviceKey, roomId: string,
    actorMemberId?: string): Promise<DeviceState> {
    await this.requireAdmin(familyId, actorMemberId);
    if (roomId.length === 0) {
      return this.unassignDevice(familyId, key, actorMemberId);
    }
    const room = await this.rooms.getRoom(roomId);
    if (room === undefined) {
      throw AppErrors.of('ROOM_NOT_FOUND', []);
    }
    if (room.familyId !== familyId) {
      throw AppErrors.of('ROOM_NOT_FOUND', []);
    }
    const state = await this.devices.assignRoom(familyId, key, roomId);
    this.emit(new RoomChangeEvent(RoomChangeEventType.DEVICE_ASSIGNED, roomId, key));
    return state;
  }

  async unassignDevice(familyId: string, key: DeviceKey,
    actorMemberId?: string): Promise<DeviceState> {
    await this.requireAdmin(familyId, actorMemberId);
    const state = await this.devices.unassignDevice(familyId, key);
    this.emit(new RoomChangeEvent(RoomChangeEventType.DEVICE_ASSIGNED, '', key));
    return state;
  }

  async moveDevice(familyId: string, key: DeviceKey, targetRoomId: string,
    actorMemberId?: string): Promise<DeviceState> {
    return this.assignDevice(familyId, key, targetRoomId, actorMemberId);
  }

  subscribe(listener: (event: RoomChangeEvent) => void): () => void {
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
  }

  /**
   * F-03: a supplied actor must exist, be ACTIVE and be ADMIN. Omitting the
   * actor is the v1 local-admin composition path (same convention as
   * FamilyService.requireAdmin); C-12 still applies session policy at the
   * call site, while the VM always supplies the active member id.
   */
  private async requireAdmin(familyId: string, actorMemberId?: string): Promise<void> {
    if (actorMemberId === undefined) {
      return;
    }
    if (this.actors === undefined) {
      throw AppErrors.of('AUTH_RBAC_DENIED', []);
    }
    const actor = await this.actors.getMember(familyId, actorMemberId);
    if (actor === undefined || actor.status !== MemberStatus.ACTIVE) {
      throw AppErrors.of('AUTH_RBAC_DENIED', []);
    }
    FamilyRbac.requireAdmin(actor.role);
  }

  private emit(event: RoomChangeEvent): void {
    // Listeners are notification consumers; a throwing subscriber must not
    // turn a committed room change into a caller-visible failure (wp-026 R-12).
    const snapshot = this.listeners.slice(0);
    for (let index = 0; index < snapshot.length; index++) {
      try {
        snapshot[index](event);
      } catch (error) {
        this.logger.warn('RoomService', 'room_listener_failed',
          [new NameValue('event', event.type)]);
      }
    }
  }
}
