/*
 * YaoCore C-09 RoomRepository.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §4.1.2, §4.3
 *
 * Rooms are local-only. `roomId` is immutable; name/icon/order may change.
 * No LAN/cloud request is ever issued here (DP-01).
 *
 * O-1: public methods run through the injected DomainOperationGate. The
 * `tx`-taking methods are transaction-context only and never nest.
 */
import { AppError, AppErrors } from '../common/types/AppError';
import { NameValue } from '../common/types/NameValue';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import { UuidUtil } from '../common/utils/UuidUtil';
import type { ClockPort, IdPort } from '../common/types/Ports';
import { Room } from '../model/FamilyModels';
import type { RdbRow, RdbStore, RdbTransaction } from '../service/storage/RdbStore';
import type { MigrationSink } from '../service/storage/MigrationPort';
import { DomainMigrations } from './DomainMigrations';
import { DomainOperationGate } from './DomainOperationGate';
import type { RoomLookupPort } from './DomainPorts';
import { SqlCells } from './SqlCells';

const ROOM_COLUMNS: string = 'room_id, family_id, room_name, icon, order_index, ' +
  'created_at, updated_at';

export class RoomRepository implements RoomLookupPort {
  private readonly rdb: RdbStore;
  private readonly clock: ClockPort;
  private readonly ids: IdPort;
  private readonly gate: DomainOperationGate;
  private initialized: boolean = false;

  constructor(rdb: RdbStore, clock: ClockPort, ids: IdPort, gate?: DomainOperationGate) {
    this.rdb = rdb;
    this.clock = clock;
    this.ids = ids;
    this.gate = gate === undefined ? new DomainOperationGate() : gate;
  }

  /** DES-B §4.1.2: v4 room table (shared v4 registration is idempotent). */
  static registerMigrations(registry: MigrationSink): void {
    DomainMigrations.register(registry);
  }

  async initialize(): Promise<void> {
    try {
      await this.rdb.query('SELECT room_id FROM room LIMIT 0');
    } catch (error) {
      throw RoomRepository.storageError(error as Error);
    }
    this.initialized = true;
  }

  async createRoom(familyId: string, roomName: string, icon?: string,
    orderIndex?: number): Promise<Room> {
    this.ensureInitialized();
    const checkedFamily = RoomRepository.requireIdentifier(familyId, 'familyId');
    const name = RoomRepository.roomName(roomName);
    const checkedIcon = RoomRepository.roomIcon(icon);
    return this.gate.run(async (): Promise<Room> => {
      const index = orderIndex === undefined ? await this.nextOrderIndexInternal(checkedFamily) :
        RoomRepository.orderIndex(orderIndex);
      const now = DateTimeUtil.nowUtcCompact(this.clock);
      const room = new Room(UuidUtil.newUuid(this.ids), checkedFamily, name, index, now, now,
        checkedIcon);
      await this.rdb.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
        await RoomRepository.insertRoom(tx, room);
      });
      return room;
    });
  }

  async getRoom(roomId: string): Promise<Room | undefined> {
    this.ensureInitialized();
    const checked = RoomRepository.requireRoomId(roomId);
    return this.gate.run(async (): Promise<Room | undefined> => {
      return this.readRoom(this.rdb, checked);
    });
  }

  async exists(roomId: string): Promise<boolean> {
    return (await this.getRoom(roomId)) !== undefined;
  }

  async listRooms(familyId: string): Promise<ReadonlyArray<Room>> {
    return this.listRoomsOrdered(familyId);
  }

  async listRoomsOrdered(familyId: string): Promise<ReadonlyArray<Room>> {
    this.ensureInitialized();
    const checked = RoomRepository.requireIdentifier(familyId, 'familyId');
    return this.gate.run(async (): Promise<ReadonlyArray<Room>> => {
      const rows = await this.rdb.query('SELECT ' + ROOM_COLUMNS +
        ' FROM room WHERE family_id = ? ORDER BY order_index ASC', [checked]);
      return RoomRepository.mapRooms(rows);
    });
  }

  async updateRoomName(roomId: string, roomName: string): Promise<void> {
    this.ensureInitialized();
    const checked = RoomRepository.requireRoomId(roomId);
    const name = RoomRepository.roomName(roomName);
    return this.gate.run(async (): Promise<void> => {
      const room = await this.readRoom(this.rdb, checked);
      if (room === undefined) {
        throw AppErrors.of('ROOM_NOT_FOUND', []);
      }
      await this.rdb.execute('UPDATE room SET room_name = ?, updated_at = ? WHERE room_id = ?',
        [name, DateTimeUtil.nowUtcCompact(this.clock), checked]);
    });
  }

  async updateRoomIcon(roomId: string, icon: string | undefined): Promise<void> {
    this.ensureInitialized();
    const checked = RoomRepository.requireRoomId(roomId);
    const checkedIcon = RoomRepository.roomIcon(icon);
    return this.gate.run(async (): Promise<void> => {
      const room = await this.readRoom(this.rdb, checked);
      if (room === undefined) {
        throw AppErrors.of('ROOM_NOT_FOUND', []);
      }
      await this.rdb.execute('UPDATE room SET icon = ?, updated_at = ? WHERE room_id = ?',
        [checkedIcon === undefined ? null : checkedIcon,
          DateTimeUtil.nowUtcCompact(this.clock), checked]);
    });
  }

  async updateOrder(familyId: string, orderedRoomIds: ReadonlyArray<string>): Promise<void> {
    this.ensureInitialized();
    const checked = RoomRepository.requireIdentifier(familyId, 'familyId');
    return this.gate.run(async (): Promise<void> => {
      await this.rdb.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
        await this.updateOrderInTransaction(tx, checked, orderedRoomIds);
      });
    });
  }

  async updateOrderInTransaction(tx: RdbTransaction, familyId: string,
    orderedRoomIds: ReadonlyArray<string>): Promise<void> {
    const existing = await this.listRoomsInTransaction(tx, familyId);
    if (existing.length !== orderedRoomIds.length) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'orderedRoomIds')]);
    }
    const seen = new Map<string, boolean>();
    for (let index = 0; index < orderedRoomIds.length; index++) {
      const id = RoomRepository.requireRoomId(orderedRoomIds[index]);
      if (seen.has(id)) {
        throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'orderedRoomIds')]);
      }
      seen.set(id, true);
      let known = false;
      for (let roomIndex = 0; roomIndex < existing.length; roomIndex++) {
        if (existing[roomIndex].roomId === id) {
          known = true;
          break;
        }
      }
      if (!known) {
        throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'orderedRoomIds')]);
      }
    }
    for (let index = 0; index < orderedRoomIds.length; index++) {
      await tx.execute('UPDATE room SET order_index = ?, updated_at = ? WHERE room_id = ?',
        [index, DateTimeUtil.nowUtcCompact(this.clock), orderedRoomIds[index]]);
    }
  }

  async deleteRoom(tx: RdbTransaction, roomId: string): Promise<void> {
    const checked = RoomRepository.requireRoomId(roomId);
    const room = await this.readRoom(tx, checked);
    if (room === undefined) {
      throw AppErrors.of('ROOM_NOT_FOUND', []);
    }
    await tx.execute('DELETE FROM room WHERE room_id = ?', [checked]);
  }

  async nextOrderIndex(familyId: string): Promise<number> {
    this.ensureInitialized();
    const checked = RoomRepository.requireIdentifier(familyId, 'familyId');
    return this.gate.run(async (): Promise<number> => {
      return this.nextOrderIndexInternal(checked);
    });
  }

  // ---- Transaction-context helpers ---------------------------------------

  async readRoom(tx: RdbTransaction, roomId: string): Promise<Room | undefined> {
    const rows = await tx.query('SELECT ' + ROOM_COLUMNS + ' FROM room WHERE room_id = ?',
      [roomId]);
    if (rows.length === 0) {
      return undefined;
    }
    return RoomRepository.roomFromRow(rows[0]);
  }

  async readRoomInTransaction(tx: RdbTransaction, roomId: string): Promise<Room | undefined> {
    return this.readRoom(tx, RoomRepository.requireRoomId(roomId));
  }

  async listRoomsInTransaction(tx: RdbTransaction,
    familyId: string): Promise<ReadonlyArray<Room>> {
    const rows = await tx.query('SELECT ' + ROOM_COLUMNS +
      ' FROM room WHERE family_id = ? ORDER BY order_index ASC', [familyId]);
    return RoomRepository.mapRooms(rows);
  }

  private async nextOrderIndexInternal(familyId: string): Promise<number> {
    const rows = await this.rdb.query('SELECT room_id, order_index FROM room ' +
      'WHERE family_id = ?', [familyId]);
    let max = -1;
    for (let index = 0; index < rows.length; index++) {
      const value = SqlCells.requiredNumber(rows[index], 'order_index');
      if (value > max) {
        max = value;
      }
    }
    return max + 1;
  }

  private static async insertRoom(tx: RdbTransaction, room: Room): Promise<void> {
    await tx.execute('INSERT OR REPLACE INTO room (' + ROOM_COLUMNS + ') ' +
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
    [room.roomId, room.familyId, room.roomName,
      room.icon === undefined ? null : room.icon, room.orderIndex, room.createdAt,
      room.updatedAt]);
  }

  private static roomFromRow(row: RdbRow): Room {
    try {
      return new Room(SqlCells.requiredString(row, 'room_id'),
        SqlCells.requiredString(row, 'family_id'),
        SqlCells.requiredString(row, 'room_name'),
        SqlCells.requiredNumber(row, 'order_index'),
        SqlCells.requiredString(row, 'created_at'),
        SqlCells.requiredString(row, 'updated_at'),
        SqlCells.optionalString(row, 'icon'));
    } catch (error) {
      throw RoomRepository.modelReadError(error as Error);
    }
  }

  private static mapRooms(rows: ReadonlyArray<RdbRow>): ReadonlyArray<Room> {
    const rooms: Room[] = [];
    for (let index = 0; index < rows.length; index++) {
      rooms.push(RoomRepository.roomFromRow(rows[index]));
    }
    return rooms;
  }

  private static roomName(value: string): string {
    const trimmed = value.trim();
    if (trimmed.length < 1 || trimmed.length > 31) {
      throw AppErrors.of('ROOM_NAME_INVALID', []);
    }
    return trimmed;
  }

  private static roomIcon(value: string | undefined): string | undefined {
    if (value === undefined) {
      return undefined;
    }
    const trimmed = value.trim();
    if (trimmed.length === 0 || trimmed.length > 63) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'icon');
    }
    return trimmed;
  }

  private static orderIndex(value: number): number {
    if (!Number.isInteger(value) || value < 0) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'orderIndex');
    }
    return value;
  }

  private static requireRoomId(value: string): string {
    if (!UuidUtil.isValidUuid(value)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'roomId');
    }
    return value;
  }

  private static requireIdentifier(value: string, field: string): string {
    if (value.length === 0 || value.length > 63 || value.indexOf(':') >= 0 ||
      !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(value)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', field);
    }
    return value;
  }

  private static modelReadError(_error: Error): Error {
    return AppErrors.of('STORAGE_RDB_ERROR', []);
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
