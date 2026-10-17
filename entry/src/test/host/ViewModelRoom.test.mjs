/*
 * YaoCore T-16 RoomViewModel host tests.
 * Producer: agent:implementation-engineer | Task: T-16 / wp-060-vm
 * Contract: DES-B §11.1.2, §11.3.3; FR-ROOM-001..006.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { RoomViewModel } from '../../main/ets/viewmodel/RoomViewModel.ets';
import { AppErrors } from '../../main/ets/common/types/AppError.ets';
import { Room } from '../../main/ets/model/FamilyModels.ets';
import {
  FakeClock,
  FakeDeviceQuery,
  FakeI18n,
  FakeLogger,
  ROOM_A,
  ROOM_B,
  record
} from './viewmodel-helpers.mjs';

function roomValue(roomId, name, order) {
  return new Room(roomId, 'family-1', name, order, '20261001T000000Z',
    '20261001T000000Z');
}

class FakeRoomAdmin {
  constructor() {
    this.rooms = [roomValue(ROOM_A, 'Living', 0), roomValue(ROOM_B, 'Bedroom', 1)];
    this.created = [];
    this.renamed = [];
    this.reordered = [];
    this.assigned = [];
    this.unassigned = [];
    this.deleted = [];
    this.confirmation = undefined;
  }

  async listRooms() { return this.rooms; }

  async createRoom(familyId, name, icon) {
    const created = roomValue('33333333-3333-4333-8333-333333333333', name, this.rooms.length);
    this.rooms.push(created);
    this.created.push({ familyId, name, icon });
    return created;
  }

  async renameRoom(roomId, name) {
    const target = this.rooms.find((room) => room.roomId === roomId);
    const renamed = roomValue(roomId, name, target.orderIndex);
    this.renamed.push({ roomId, name });
    this.rooms = this.rooms.map((room) => room.roomId === roomId ? renamed : room);
    return renamed;
  }

  async reorderRooms(familyId, orderedRoomIds) {
    this.reordered.push({ familyId, orderedRoomIds });
  }

  async previewDelete(roomId) {
    const room = this.rooms.find((entry) => entry.roomId === roomId);
    return { room, deviceCount: 2, deviceNames: ['Lamp', 'Switch'],
      requiresConfirmation: true };
  }

  async deleteRoom(roomId, confirmation) {
    this.confirmation = confirmation;
    if (confirmation.userAcknowledgedDeviceCount !== 2) {
      throw AppErrors.of('ROOM_DELETE_NOT_CONFIRMED', []);
    }
    this.deleted.push(roomId);
    this.rooms = this.rooms.filter((room) => room.roomId !== roomId);
    return { roomId, deleted: true, affectedDeviceCount: 2, affectedMemberCount: 1 };
  }

  async assignDevice(familyId, key, roomId) {
    this.assigned.push({ familyId, key, roomId });
    return { key };
  }

  async unassignDevice(familyId, key) {
    this.unassigned.push({ familyId, key });
    return { key };
  }
}

function setup() {
  const clock = new FakeClock();
  const admin = new FakeRoomAdmin();
  const pool = record({ deviceId: 'dev-pool', roomId: '', isUnassigned: true,
    isEnabled: false });
  const devices = new FakeDeviceQuery([pool]);
  const vm = new RoomViewModel(admin, devices, new FakeI18n(), clock, new FakeLogger());
  return { clock, admin, pool, devices, vm, key: pool.state.key };
}

test('T16_Room_initializeLoadsRoomsAndUnassignedPool', async () => {
  const h = setup();
  await h.vm.initialize('family-1');
  const state = h.vm.getState();
  assert.equal(state.phase, 'READY');
  assert.equal(state.rooms.length, 2);
  assert.equal(state.unassignedRecords.length, 1);
  assert.equal(state.unassignedRecords[0].state.isUnassigned, true);
});

test('T16_Room_createRenameAndReorder', async () => {
  const h = setup();
  await h.vm.initialize('family-1');
  const created = await h.vm.createRoom('Kitchen', 'kitchen');
  assert.equal(created.roomName, 'Kitchen');
  assert.equal(h.admin.created[0].familyId, 'family-1');
  await h.vm.renameRoom(ROOM_A, 'Lounge');
  assert.equal(h.admin.renamed[0].roomId, ROOM_A);
  await h.vm.reorderRooms([ROOM_B, ROOM_A]);
  assert.deepEqual(h.admin.reordered[0].orderedRoomIds, [ROOM_B, ROOM_A]);
});

test('T16_Room_previewDeleteShowsCountAndRequiresBlockingConfirmation', async () => {
  const h = setup();
  await h.vm.initialize('family-1');
  const preview = await h.vm.previewDelete(ROOM_A);
  assert.equal(preview.deviceCount, 2);
  assert.equal(preview.requiresConfirmation, true);
  assert.equal(h.vm.getState().deletionPreview.deviceCount, 2);
});

test('T16_Room_confirmDeleteCountMismatchKeepsPreviewAndFails', async () => {
  const h = setup();
  await h.vm.initialize('family-1');
  await h.vm.previewDelete(ROOM_A);
  await assert.rejects(h.vm.confirmDelete(ROOM_A, 1),
    (error) => error.code === 'ROOM_DELETE_NOT_CONFIRMED');
  assert.equal(h.vm.getState().error.error.code, 'ROOM_DELETE_NOT_CONFIRMED');
  assert.equal(h.vm.getState().deletionPreview.deviceCount, 2);
  assert.equal(h.admin.deleted.length, 0);
});

test('T16_Room_confirmDeleteSuccessClearsPreviewAndRefreshesPool', async () => {
  const h = setup();
  await h.vm.initialize('family-1');
  await h.vm.previewDelete(ROOM_A);
  const result = await h.vm.confirmDelete(ROOM_A, 2);
  assert.equal(result.deleted, true);
  assert.equal(h.vm.getState().deletionPreview, undefined);
  assert.equal(h.vm.getState().rooms.length, 1);
  assert.equal(h.admin.confirmation.userAcknowledgedDeviceCount, 2);
});

test('T16_Room_assignAndUnassignUseServicePorts', async () => {
  const h = setup();
  await h.vm.initialize('family-1');
  await h.vm.assignDevice(h.key, ROOM_A);
  assert.equal(h.admin.assigned[0].roomId, ROOM_A);
  await h.vm.unassignDevice(h.key);
  assert.equal(h.admin.unassigned[0].key.globalId(), h.key.globalId());
});

test('T16_Room_cancelDeleteClearsPreviewWithoutCallingService', async () => {
  const h = setup();
  await h.vm.initialize('family-1');
  await h.vm.previewDelete(ROOM_A);
  h.vm.cancelDelete();
  assert.equal(h.vm.getState().deletionPreview, undefined);
  assert.equal(h.admin.deleted.length, 0);
});
