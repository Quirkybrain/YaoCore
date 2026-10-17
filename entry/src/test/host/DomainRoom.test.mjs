/*
 * YaoCore T-09 C-09 RoomRepository / RoomService host tests.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §4.1-§4.4; DP-01/DP-02; D-019 host layer.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { newDomainHarness } from '../domain/DomainHarness.ets';
import { DiscoverApplyOptions } from '../../main/ets/repository/DomainModels.ets';
import { RoomService, RoomDeletionConfirmation } from '../../main/ets/service/room/RoomService.ets';
import { DeviceKey } from '../../main/ets/model/DeviceKey.ets';
import { FamilyMember, MemberRole, MemberStatus } from '../../main/ets/model/FamilyModels.ets';
import { snapshotDevice, discovery, GATEWAY_ID } from './domain-helpers.mjs';

async function setup() {
  const h = await newDomainHarness();
  const family = await h.families.createFamily('Home', 'Alice');
  h.routes.add(GATEWAY_ID, family.familyId);
  const service = new RoomService(h.rooms, h.devices, h.families, h.rdb, h.clock, h.logger,
    h.gate, h.devices);
  return { h, familyId: family.familyId, service };
}

async function addDevice(h, familyId, deviceId = 'Light_01') {
  await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice(deviceId)]),
    new DiscoverApplyOptions(familyId, h.clock.nowMs()));
  return new DeviceKey(GATEWAY_ID, deviceId);
}

test('T09_C09_roomCreateRenameKeepsIdAndDefaultOrder', async () => {
  const { h, familyId, service } = await setup();
  const first = await service.createRoom(familyId, 'Living');
  const second = await service.createRoom(familyId, 'Bedroom');
  assert.equal(first.orderIndex, 0);
  assert.equal(second.orderIndex, 1);
  const renamed = await service.renameRoom(first.roomId, '  Lounge  ');
  assert.equal(renamed.roomId, first.roomId);
  assert.equal(renamed.roomName, 'Lounge');
  const rooms = await service.listRooms(familyId);
  assert.equal(rooms.length, 2);
  assert.equal(rooms[0].roomId, first.roomId);
  assert.equal(h.control.commands.length, 0);
});

test('T09_C09_roomNameValidationAndNotFound', async () => {
  const { service, familyId } = await setup();
  await assert.rejects(service.createRoom(familyId, '   '), (error) => error.code === 'ROOM_NAME_INVALID');
  await assert.rejects(service.renameRoom('123e4567-e89b-12d3-a456-000000000099', 'X'),
    (error) => error.code === 'ROOM_NOT_FOUND');
});

test('T09_C09_reorderRequiresExactSet', async () => {
  const { service, familyId } = await setup();
  const first = await service.createRoom(familyId, 'Living');
  const second = await service.createRoom(familyId, 'Bedroom');
  await service.reorderRooms(familyId, [second.roomId, first.roomId]);
  const rooms = await service.listRooms(familyId);
  assert.equal(rooms[0].roomId, second.roomId);
  assert.equal(rooms[1].roomId, first.roomId);
  await assert.rejects(service.reorderRooms(familyId, [first.roomId]),
    (error) => error.code === 'CONFIGURATION_ERROR');
  await assert.rejects(service.reorderRooms(familyId, [first.roomId, first.roomId]),
    (error) => error.code === 'CONFIGURATION_ERROR');
  await assert.rejects(service.reorderRooms(familyId,
    [first.roomId, '123e4567-e89b-12d3-a456-000000000099']),
  (error) => error.code === 'CONFIGURATION_ERROR');
});

test('T09_C09_assignMoveAndUnassignFollowPoolSemantics', async () => {
  const { h, familyId, service } = await setup();
  const room = await service.createRoom(familyId, 'Living');
  const other = await service.createRoom(familyId, 'Bedroom');
  const key = await addDevice(h, familyId);
  let state = await service.assignDevice(familyId, key, room.roomId);
  assert.equal(state.roomId, room.roomId);
  assert.equal(state.isUnassigned, false);
  assert.equal(state.isEnabled, true);
  state = await service.moveDevice(familyId, key, other.roomId);
  assert.equal(state.roomId, other.roomId);
  state = await service.unassignDevice(familyId, key);
  assert.equal(state.roomId, '');
  assert.equal(state.isUnassigned, true);
  assert.equal(state.isEnabled, false);
  await assert.rejects(service.assignDevice(familyId, key,
    '123e4567-e89b-12d3-a456-000000000099'), (error) => error.code === 'ROOM_NOT_FOUND');
  assert.equal(h.control.commands.length, 0);
});

test('T09_C09_previewDeleteReportsDevicesAndRejectsStaleConfirmation', async () => {
  const { h, familyId, service } = await setup();
  const room = await service.createRoom(familyId, 'Living');
  const key = await addDevice(h, familyId);
  await service.assignDevice(familyId, key, room.roomId);
  const preview = await service.previewDelete(room.roomId);
  assert.equal(preview.deviceCount, 1);
  assert.equal(preview.deviceNames[0], 'Light_01');
  assert.equal(preview.requiresConfirmation, true);
  await assert.rejects(service.deleteRoom(room.roomId, new RoomDeletionConfirmation(false, 1)),
    (error) => error.code === 'ROOM_DELETE_NOT_CONFIRMED');
  await assert.rejects(service.deleteRoom(room.roomId, new RoomDeletionConfirmation(true, 0)),
    (error) => error.code === 'ROOM_DELETE_NOT_CONFIRMED');
  await assert.rejects(service.previewDelete('123e4567-e89b-12d3-a456-000000000099'),
    (error) => error.code === 'ROOM_NOT_FOUND');
});

test('T09_C09_deleteRoomIsOneTransactionDevicesUnassignedGrantsRemoved', async () => {
  const { h, familyId, service } = await setup();
  const room = await service.createRoom(familyId, 'Living');
  const key = await addDevice(h, familyId);
  await service.assignDevice(familyId, key, room.roomId);
  const member = new FamilyMember('member-2', familyId, 'member-2', 'Bob', MemberRole.MEMBER,
    MemberStatus.ACTIVE, '20261017T080000Z', [room.roomId]);
  await h.families.upsertMember(member);

  const result = await service.deleteRoom(room.roomId,
    new RoomDeletionConfirmation(true, 1));
  assert.equal(result.deleted, true);
  assert.equal(result.affectedDeviceCount, 1);
  assert.equal(result.affectedMemberCount, 1);
  assert.equal(await h.rooms.exists(room.roomId), false);
  const record = await h.devices.getRecord(key);
  assert.equal(record.state.roomId, '');
  assert.equal(record.state.isUnassigned, true);
  assert.equal(record.state.isEnabled, false);
  assert.deepEqual(await h.families.listMemberRoomGrants(familyId, 'member-2'), []);
  assert.equal(h.control.commands.length, 0);
});

test('T09_C09_deleteRoomRollsBackRoomDeviceAndGrantOnFailure', async () => {
  const { h, familyId, service } = await setup();
  const room = await service.createRoom(familyId, 'Living');
  const key = await addDevice(h, familyId);
  await service.assignDevice(familyId, key, room.roomId);
  const member = new FamilyMember('member-2', familyId, 'member-2', 'Bob', MemberRole.MEMBER,
    MemberStatus.ACTIVE, '20261017T080000Z', [room.roomId]);
  await h.families.upsertMember(member);
  h.rdb.failNextExecuteContaining = 'UPDATE device_state';
  await assert.rejects(service.deleteRoom(room.roomId, new RoomDeletionConfirmation(true, 1)),
    (error) => error.code === 'STORAGE_RDB_ERROR');
  assert.equal(await h.rooms.exists(room.roomId), true);
  const record = await h.devices.getRecord(key);
  assert.equal(record.state.roomId, room.roomId);
  assert.equal(record.state.isUnassigned, false);
  assert.equal(record.state.isEnabled, true);
  assert.deepEqual(await h.families.listMemberRoomGrants(familyId, 'member-2'),
    [room.roomId]);
});

test('T09_C09_deleteEmptyAndLastRoomSucceeds', async () => {
  const { h, familyId, service } = await setup();
  const empty = await service.createRoom(familyId, 'Empty');
  const result = await service.deleteRoom(empty.roomId, new RoomDeletionConfirmation(true, 0));
  assert.equal(result.affectedDeviceCount, 0);
  const last = await service.createRoom(familyId, 'Last');
  const key = await addDevice(h, familyId);
  await service.assignDevice(familyId, key, last.roomId);
  await service.deleteRoom(last.roomId, new RoomDeletionConfirmation(true, 1));
  assert.equal((await service.listRooms(familyId)).length, 0);
  assert.equal(h.control.commands.length, 0);
});

test('T09_C09_throwingListenerDoesNotFailRoomDeletion', async () => {
  const { h, familyId, service } = await setup();
  const room = await service.createRoom(familyId, 'Living');
  service.subscribe(() => {
    throw new Error('listener boom');
  });
  const result = await service.deleteRoom(room.roomId, new RoomDeletionConfirmation(true, 0));
  assert.equal(result.deleted, true);
  assert.equal(await h.rooms.exists(room.roomId), false);
  assert.ok(h.logger.entries.includes('W RoomService room_listener_failed'));
});

test('T18_C09_roomMutationsRequireAdminActorMatrix', async () => {
  const { h, familyId } = await setup();
  const room = await h.rooms.createRoom(familyId, 'Living');
  const admin = new FamilyMember('member-admin', familyId, 'member-admin', 'Owner',
    MemberRole.ADMIN, MemberStatus.ACTIVE, '20261017T080000Z', []);
  const member = new FamilyMember('member-user', familyId, 'member-user', 'Bob',
    MemberRole.MEMBER, MemberStatus.ACTIVE, '20261017T080000Z', []);
  const guest = new FamilyMember('member-guest', familyId, 'member-guest', 'Eve',
    MemberRole.GUEST, MemberStatus.ACTIVE, '20261017T080000Z', [room.roomId],
    '20271017T080000Z');
  await h.families.upsertMember(admin);
  await h.families.upsertMember(member);
  await h.families.upsertMember(guest);
  const actors = {
    async getMember(targetFamilyId, memberId) {
      if (targetFamilyId !== familyId) { return undefined; }
      if (memberId === admin.memberId) { return admin; }
      if (memberId === member.memberId) { return member; }
      if (memberId === guest.memberId) { return guest; }
      return undefined;
    }
  };
  const service = new RoomService(h.rooms, h.devices, h.families, h.rdb, h.clock,
    h.logger, h.gate, h.devices, actors);
  const key = await addDevice(h, familyId);
  // ADMIN can assign; MEMBER/GUEST are refused by the service, not just UI.
  await service.assignDevice(familyId, key, room.roomId, admin.memberId);
  await assert.rejects(service.assignDevice(familyId, key, room.roomId, member.memberId),
    (error) => error.code === 'AUTH_RBAC_DENIED');
  await assert.rejects(service.assignDevice(familyId, key, room.roomId, guest.memberId),
    (error) => error.code === 'AUTH_RBAC_DENIED');
  await assert.rejects(service.deleteRoom(room.roomId,
    new RoomDeletionConfirmation(true, 1), member.memberId),
  (error) => error.code === 'AUTH_RBAC_DENIED');
  await assert.rejects(service.createRoom(familyId, 'Denied', undefined, guest.memberId),
    (error) => error.code === 'AUTH_RBAC_DENIED');
  // The admin deletion still works and moves the device to the pool.
  const result = await service.deleteRoom(room.roomId,
    new RoomDeletionConfirmation(true, 1), admin.memberId);
  assert.equal(result.deleted, true);
  const record = await h.devices.getRecord(key);
  assert.equal(record.state.isUnassigned, true);
});
