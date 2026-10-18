/*
 * YaoCore T-09 C-10 DeviceRepository / DeviceCommandRunner host tests.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §5.1-§5.4; D-019 host layer.
 *
 * PUBLIC TEST DATA ONLY. Fake RDB/ports; no platform adapter and no network.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { newDomainHarness } from '../domain/DomainHarness.ets';
import { DomainOperationGate } from '../../main/ets/repository/DomainOperationGate.ets';
import { ControlApplyContext, ControlApplyReason, DeviceMergeResult, DiscoverApplyOptions } from '../../main/ets/model/DeviceRecord.ets';
import { DeviceRepository } from '../../main/ets/repository/DeviceRepository.ets';
import { DeviceKey } from '../../main/ets/model/DeviceKey.ets';
import { DeviceAction, DeviceType } from '../../main/ets/common/constants/DeviceConstants.ets';
import { StateVerification } from '../../main/ets/model/ControlModels.ets';
import { DeviceCommandRunner } from '../../main/ets/service/device/DeviceCommandRunner.ets';
import { Scene, SceneAction } from '../../main/ets/model/FamilyModels.ets';
import { MigrationRegistry } from '../../main/ets/service/storage/MigrationRegistry.ets';
import { DomainMigrations } from '../../main/ets/repository/DomainMigrations.ets';
import { RoomRepository } from '../../main/ets/repository/RoomRepository.ets';
import { SceneRepository } from '../../main/ets/repository/SceneRepository.ets';
import {
  FAMILY_ID,
  GATEWAY_ID,
  T0,
  T1,
  T2,
  T3,
  discovery,
  snapshotDevice,
  unknownTypeSnapshot,
  acceptedOutcome,
  rejectedOutcome,
  stateOutcome,
  command,
  expectCode
} from './domain-helpers.mjs';

async function setup() {
  const h = await newDomainHarness();
  const family = await h.families.createFamily('Home', 'Alice');
  h.routes.add(GATEWAY_ID, family.familyId);
  return { h, familyId: family.familyId };
}

function options(h, familyId) {
  return new DiscoverApplyOptions(familyId, h.clock.nowMs());
}

async function withTimeout(promise, ms) {
  let timer;
  const timeout = new Promise((resolve, reject) => {
    timer = setTimeout(() => reject(new Error('operation hung')), ms);
  });
  try {
    return await Promise.race([promise, timeout]);
  } finally {
    clearTimeout(timer);
  }
}

test('T09_C10_newDiscoverAddsUnassignedProtectivelyDisabledDevice', async () => {
  const { h, familyId } = await setup();
  const result = await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01', { powerStatus: true })]), options(h, familyId));
  assert.equal(result.added, 1);
  assert.equal(result.updated, 0);
  const record = await h.devices.getRecord(new DeviceKey(GATEWAY_ID, 'Light_01'));
  assert.ok(record);
  assert.equal(record.state.roomId, '');
  assert.equal(record.state.isUnassigned, true);
  assert.equal(record.state.isEnabled, false);
  assert.equal(record.isControlAllowed, false);
  assert.equal(record.merge.lastResult, DeviceMergeResult.ADDED);
  assert.equal((await h.devices.listUnassigned(familyId)).length, 1);
  assert.equal((await h.devices.listRecords(familyId)).length, 1);
});

test('T09_C10_staleSnapshotIsDroppedWhole', async () => {
  const { h, familyId } = await setup();
  const opt = options(h, familyId);
  await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01', { updatedAt: T2, powerStatus: true, brightness: 80 })]),
    opt);
  const stale = await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01', { updatedAt: T1, powerStatus: false, brightness: 5 })]),
    opt);
  assert.equal(stale.staleDropped, 1);
  assert.ok(stale.deviations.includes('STALE_SNAPSHOT'));
  const record = await h.devices.getRecord(new DeviceKey(GATEWAY_ID, 'Light_01'));
  assert.equal(record.state.snapshot.updatedAt, T2);
  assert.equal(record.state.snapshot.powerStatus, true);
  assert.equal(record.state.snapshot.brightness, 80);
  assert.equal(record.merge.lastResult, DeviceMergeResult.STALE_DROPPED);
});

test('T09_C10_sameEpochOverwriteIsAppliedAndDiagnosed', async () => {
  const { h, familyId } = await setup();
  const opt = options(h, familyId);
  await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01', { updatedAt: T1, powerStatus: true })]), opt);
  const same = await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01', { updatedAt: T1, powerStatus: false })]), opt);
  assert.equal(same.updated, 1);
  assert.ok(same.deviations.includes('SAME_EPOCH_OVERWRITE'));
  const record = await h.devices.getRecord(new DeviceKey(GATEWAY_ID, 'Light_01'));
  assert.equal(record.state.snapshot.powerStatus, false);
  assert.equal(record.merge.lastResult, DeviceMergeResult.SAME_EPOCH_OVERWRITE);
});

test('T09_C10_missingFieldsPreserveOldAndOfflineDoesNotErase', async () => {
  const { h, familyId } = await setup();
  const opt = options(h, familyId);
  await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01', {
      updatedAt: T1, isOnline: true, powerStatus: true, brightness: 70
    })]), opt);
  await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01', { updatedAt: T2, isOnline: false })]), opt);
  const record = await h.devices.getRecord(new DeviceKey(GATEWAY_ID, 'Light_01'));
  assert.equal(record.state.snapshot.isOnline, false);
  assert.equal(record.state.snapshot.powerStatus, true);
  assert.equal(record.state.snapshot.brightness, 70);
});

test('T09_C10_partialSnapshotNeverMarksGatewayRemoved', async () => {
  const { h, familyId } = await setup();
  const opt = options(h, familyId);
  await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01'), snapshotDevice('Light_02')]), opt);
  const partial = await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01', { updatedAt: T1 })], { isPartial: true }), opt);
  assert.equal(partial.partial, true);
  assert.ok(partial.deviations.includes('PARTIAL_DISCOVER'));
  const second = await h.devices.getRecord(new DeviceKey(GATEWAY_ID, 'Light_02'));
  assert.equal(second.gatewayRemoved, false);
});

test('T09_C10_fullSnapshotMarksMissingAndReappearanceClearsHint', async () => {
  const { h, familyId } = await setup();
  const opt = options(h, familyId);
  await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01'), snapshotDevice('Light_02')]), opt);
  const full = await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01', { updatedAt: T1 })]), opt);
  assert.equal(full.gatewayRemovedMarked, 1);
  const second = await h.devices.getRecord(new DeviceKey(GATEWAY_ID, 'Light_02'));
  assert.equal(second.gatewayRemoved, true);
  // Not a deletion and not a disablement.
  assert.equal(second.state.isEnabled, false);
  assert.equal(second.state.isUnassigned, true);
  await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01', { updatedAt: T1 }),
      snapshotDevice('Light_02', { updatedAt: T1 })]), opt);
  const restored = await h.devices.getRecord(new DeviceKey(GATEWAY_ID, 'Light_02'));
  assert.equal(restored.gatewayRemoved, false);
});

test('T09_C10_aliasUsedIsDiagnosticAndNotPartial', async () => {
  const { h, familyId } = await setup();
  const opt = options(h, familyId);
  await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01'), snapshotDevice('Light_02')]), opt);
  const result = await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01', { updatedAt: T1 })],
      { aliasUsed: true, isPartial: false }), opt);
  assert.equal(result.partial, false);
  assert.ok(result.deviations.includes('ALIAS_FIELD_USED'));
  // Alias fallback does not suppress the full-snapshot missing hint.
  assert.equal(result.gatewayRemovedMarked, 1);
  const second = await h.devices.getRecord(new DeviceKey(GATEWAY_ID, 'Light_02'));
  assert.equal(second.gatewayRemoved, true);
});

test('T09_C10_unknownTypeIsReadOnlyAndRunnerRejectsWithZeroCommands', async () => {
  const { h, familyId } = await setup();
  const room = await h.rooms.createRoom(familyId, 'Living');
  await h.devices.applyDiscoverSnapshot(discovery([unknownTypeSnapshot('Mystery_01')]),
    options(h, familyId));
  const record = await h.devices.getRecord(new DeviceKey(GATEWAY_ID, 'Mystery_01'));
  assert.equal(record.isSupported, false);
  assert.equal(record.isControlAllowed, false);
  await h.devices.assignRoom(familyId, new DeviceKey(GATEWAY_ID, 'Mystery_01'), room.roomId);
  const runner = new DeviceCommandRunner(h.control, h.devices, h.clock, h.logger, h.metrics);
  const execution = await runner.run(command(GATEWAY_ID, 'Mystery_01', DeviceAction.TURN_ON, 1700000000000, true),
    { familyId, precheck: true });
  assert.equal(execution.ackAccepted, false);
  expectCode(execution.error, 'CONFIGURATION_ERROR');
  assert.equal(h.control.commands.length, 0);
  assert.equal(room.roomId.length > 0, true);
});

test('T09_C10_tombstoneSurvivesRediscoverAndRestoreReaddsFresh', async () => {
  const { h, familyId } = await setup();
  const room = await h.rooms.createRoom(familyId, 'Living');
  await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01')]), options(h, familyId));
  const key = new DeviceKey(GATEWAY_ID, 'Light_01');
  await h.devices.assignRoom(familyId, key, room.roomId);
  const removed = await h.devices.removeDevice(familyId, key);
  assert.equal(removed.removed, true);
  assert.equal(removed.tombstoneCreated, true);
  assert.equal(await h.devices.getRecord(key), undefined);
  const dismissed = await h.devices.listDismissed(GATEWAY_ID);
  assert.equal(dismissed.length, 1);

  const again = await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01', { updatedAt: T1 })]), options(h, familyId));
  assert.equal(again.tombstonedSkipped, 1);
  assert.equal(await h.devices.getRecord(key), undefined);

  assert.equal(await h.devices.restoreDevice(GATEWAY_ID, 'Light_01'), true);
  const readd = await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01', { updatedAt: T2 })]), options(h, familyId));
  assert.equal(readd.added, 1);
  const record = await h.devices.getRecord(key);
  assert.equal(record.state.isUnassigned, true);
  assert.equal(record.state.isEnabled, false);
});

test('T09_C10_removeDeviceCleansSceneReferences', async () => {
  const { h, familyId } = await setup();
  const room = await h.rooms.createRoom(familyId, 'Living');
  await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01')]), options(h, familyId));
  const key = new DeviceKey(GATEWAY_ID, 'Light_01');
  await h.devices.assignRoom(familyId, key, room.roomId);
  await h.scenes.putScene(new Scene(
    '123e4567-e89b-12d3-a456-000000000099', familyId, 'Movie', 'scene.movie',
    [new SceneAction(GATEWAY_ID, 'Light_01', DeviceAction.TURN_ON, true)], true));
  const removed = await h.devices.removeDevice(familyId, key);
  assert.equal(removed.sceneCleanup.removedActionCount, 1);
  const stored = await h.scenes.getScene('123e4567-e89b-12d3-a456-000000000099');
  assert.equal(stored.actions.length, 0);
});

test('T09_C10_removeDeviceRollsBackWhenSceneCleanupFails', async () => {
  const { h, familyId } = await setup();
  const room = await h.rooms.createRoom(familyId, 'Living');
  await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01')]), options(h, familyId));
  const key = new DeviceKey(GATEWAY_ID, 'Light_01');
  await h.devices.assignRoom(familyId, key, room.roomId);
  await h.scenes.putScene(new Scene(
    '123e4567-e89b-12d3-a456-000000000099', familyId, 'Movie', 'scene.movie',
    [new SceneAction(GATEWAY_ID, 'Light_01', DeviceAction.TURN_ON, true)], true));
  h.rdb.failNextExecuteContaining = 'INSERT OR REPLACE INTO scene';
  await assert.rejects(h.devices.removeDevice(familyId, key), (error) => error.code === 'STORAGE_RDB_ERROR');
  const record = await h.devices.getRecord(key);
  assert.ok(record);
  assert.equal(record.state.roomId, room.roomId);
  const stored = await h.scenes.getScene('123e4567-e89b-12d3-a456-000000000099');
  assert.equal(stored.actions.length, 1);
  assert.equal((await h.devices.listDismissed(GATEWAY_ID)).length, 0);
});

test('T09_C10_ackAppliesStateAndPreservesExecutionOnStaleState', async () => {
  const { h, familyId } = await setup();
  await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01', { updatedAt: T0, powerStatus: false })]),
    options(h, familyId));
  const context = new ControlApplyContext(familyId, GATEWAY_ID, 'Light_01',
    DeviceAction.TURN_ON, 1700000000000, true);
  const applied = await h.devices.applyControlAck(context,
    stateOutcome('Light_01', GATEWAY_ID, { updatedAt: T1, fields: { powerStatus: true } }));
  assert.equal(applied.reason, ControlApplyReason.APPLIED);
  assert.equal(applied.stateApplied, true);
  assert.equal(applied.ackAccepted, true);
  let record = await h.devices.getRecord(new DeviceKey(GATEWAY_ID, 'Light_01'));
  assert.equal(record.state.snapshot.powerStatus, true);

  const stale = await h.devices.applyControlAck(context,
    stateOutcome('Light_01', GATEWAY_ID, { updatedAt: T0, fields: { powerStatus: false } }));
  assert.equal(stale.reason, ControlApplyReason.STALE_STATE_DROPPED);
  assert.equal(stale.ackAccepted, true);
  assert.equal(stale.stateApplied, false);
  record = await h.devices.getRecord(new DeviceKey(GATEWAY_ID, 'Light_01'));
  assert.equal(record.state.snapshot.powerStatus, true);
});

test('T09_C10_ackMismatchReplayAndNoReportedState', async () => {
  const { h, familyId } = await setup();
  await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01', { updatedAt: T0 })]), options(h, familyId));
  const context = new ControlApplyContext(familyId, GATEWAY_ID, 'Light_01',
    DeviceAction.TURN_ON, 1700000000000, true);

  const noState = await h.devices.applyControlAck(context, acceptedOutcome('Light_01'));
  assert.equal(noState.reason, ControlApplyReason.NO_REPORTED_STATE);
  assert.equal(noState.stateApplied, false);

  const mismatch = await h.devices.applyControlAck(context,
    stateOutcome('Light_01', GATEWAY_ID, { deviceId: 'Other_01' }));
  assert.equal(mismatch.reason, ControlApplyReason.DEVICE_MISMATCH);
  assert.equal(mismatch.stateApplied, false);

  const first = stateOutcome('Light_01', GATEWAY_ID, {
    updatedAt: T1, requestId: 'req-1700000000000-77', seq: 77,
    fields: { powerStatus: true }
  });
  const applied = await h.devices.applyControlAck(context, first);
  assert.equal(applied.reason, ControlApplyReason.APPLIED);
  const replayOutcome = stateOutcome('Light_01', GATEWAY_ID, {
    updatedAt: T1, requestId: 'req-1700000000000-77', seq: 77, idempotentReplay: true,
    fields: { powerStatus: false }
  });
  const replay = await h.devices.applyControlAck(context, replayOutcome);
  assert.equal(replay.reason, ControlApplyReason.IDEMPOTENT_REPLAY);
  assert.equal(replay.stateApplied, false);

  const mismatchState = await h.devices.applyControlAck(context,
    stateOutcome('Light_01', GATEWAY_ID, {
      updatedAt: T2, verification: StateVerification.MISMATCH, fields: { powerStatus: false }
    }));
  assert.equal(mismatchState.reason, ControlApplyReason.APPLIED);
  assert.equal(mismatchState.stateVerification, StateVerification.MISMATCH);
});

test('T09_C10_applyCloudStateRespectsAcceptedBoundary', async () => {
  const { h, familyId } = await setup();
  await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01', { updatedAt: T0 })]), options(h, familyId));
  const context = new ControlApplyContext(familyId, GATEWAY_ID, 'Light_01',
    DeviceAction.TURN_ON, 1700000000000, true);
  const notAccepted = await h.devices.applyCloudState(context,
    stateOutcome('Light_01', GATEWAY_ID, { updatedAt: T1, fields: { powerStatus: true } }).reportedState,
    StateVerification.MATCH, 'req-1700000000000-88', 88, false);
  assert.equal(notAccepted.reason, ControlApplyReason.ACK_NOT_ACCEPTED);
  const accepted = await h.devices.applyCloudState(context,
    stateOutcome('Light_01', GATEWAY_ID, { updatedAt: T1, fields: { powerStatus: true } }).reportedState,
    StateVerification.MATCH, 'req-1700000000000-88', 88, true);
  assert.equal(accepted.reason, ControlApplyReason.APPLIED);
  assert.equal(accepted.stateApplied, true);
});

test('T09_C10_commandRunnerPrechecksAndControlFlow', async () => {
  const { h, familyId } = await setup();
  const room = await h.rooms.createRoom(familyId, 'Living');
  await h.devices.applyDiscoverSnapshot(discovery([snapshotDevice('Light_01')]),
    options(h, familyId));
  const runner = new DeviceCommandRunner(h.control, h.devices, h.clock, h.logger, h.metrics);
  const key = new DeviceKey(GATEWAY_ID, 'Light_01');

  const disabled = await runner.run(command(GATEWAY_ID, 'Light_01', DeviceAction.TURN_ON, 1700000000000, true),
    { familyId, precheck: true });
  expectCode(disabled.error, 'DEVICE_DISABLED');
  assert.equal(h.control.commands.length, 0);

  await h.devices.assignRoom(familyId, key, room.roomId);
  const ok = await runner.run(command(GATEWAY_ID, 'Light_01', DeviceAction.TURN_ON, 1700000000000, true),
    { familyId, precheck: true });
  assert.equal(ok.ackAccepted, true);
  assert.equal(h.control.commands.length, 1);

  await h.devices.removeDevice(familyId, key);
  const before = h.control.commands.length;
  const dismissed = await runner.run(command(GATEWAY_ID, 'Light_01', DeviceAction.TURN_ON, 1700000000000, true),
    { familyId, precheck: true });
  expectCode(dismissed.error, 'DEVICE_DISMISSED');
  assert.equal(h.control.commands.length, before);
});

// T-11 F-04: C-10 enforces the DES-A §14.2.3 action x deviceType matrix locally
// before port.send; unsupported combinations never reach the gateway.
test('T09_C10_commandRunnerEnforcesActionDeviceTypeMatrix', async () => {
  const { h, familyId } = await setup();
  const room = await h.rooms.createRoom(familyId, 'Living');
  await h.devices.applyDiscoverSnapshot(discovery([
    snapshotDevice('Door_01', { deviceType: DeviceType.DOOR, deviceTypeRaw: 'door' }),
    snapshotDevice('Light_01', { deviceType: DeviceType.LIGHT, deviceTypeRaw: 'light' }),
    snapshotDevice('AC_01', { deviceType: DeviceType.AC, deviceTypeRaw: 'ac' }),
    snapshotDevice('Sensor_01', { deviceType: DeviceType.SENSOR, deviceTypeRaw: 'sensor' }),
  ]), options(h, familyId));
  for (const deviceId of ['Door_01', 'Light_01', 'AC_01', 'Sensor_01']) {
    await h.devices.assignRoom(familyId, new DeviceKey(GATEWAY_ID, deviceId), room.roomId);
  }
  const runner = new DeviceCommandRunner(h.control, h.devices, h.clock, h.logger, h.metrics);
  const run = (deviceId, action, value) => runner.run(
    command(GATEWAY_ID, deviceId, action, 1700000000000, value), { familyId, precheck: true });

  const doorOpen = await run('Door_01', DeviceAction.OPEN, undefined);
  assert.equal(doorOpen.ackAccepted, true);
  assert.equal(h.control.commands.length, 1);

  const doorBrightness = await run('Door_01', DeviceAction.SET_BRIGHTNESS, 42);
  expectCode(doorBrightness.error, 'CONFIGURATION_ERROR');
  assert.equal(h.control.commands.length, 1, 'door + SET_BRIGHTNESS must not reach the port');

  const lightBrightness = await run('Light_01', DeviceAction.SET_BRIGHTNESS, 42);
  assert.equal(lightBrightness.ackAccepted, true);
  assert.equal(h.control.commands.length, 2);

  const lightMode = await run('Light_01', DeviceAction.SET_MODE, 'COOL');
  expectCode(lightMode.error, 'CONFIGURATION_ERROR');
  assert.equal(h.control.commands.length, 2, 'light + SET_MODE must not reach the port');

  const acMode = await run('AC_01', DeviceAction.SET_MODE, 'cool');
  assert.equal(acMode.ackAccepted, true);
  assert.equal(h.control.commands.length, 3);

  const acTemp = await run('AC_01', DeviceAction.SET_TARGET_TEMPERATURE, 24);
  assert.equal(acTemp.ackAccepted, true);
  assert.equal(h.control.commands.length, 4);

  const acTempOutOfRange = await run('AC_01', DeviceAction.SET_TARGET_TEMPERATURE, 31);
  expectCode(acTempOutOfRange.error, 'PROTOCOL_VALUE_OUT_OF_RANGE');
  assert.equal(h.control.commands.length, 4);

  const sensorOn = await run('Sensor_01', DeviceAction.TURN_ON, true);
  expectCode(sensorOn.error, 'CONFIGURATION_ERROR');
  assert.equal(h.control.commands.length, 4, 'sensor control must not reach the port');

  const lightMissingValue = await run('Light_01', DeviceAction.SET_BRIGHTNESS, undefined);
  expectCode(lightMissingValue.error, 'PROTOCOL_VALUE_OUT_OF_RANGE');
  assert.equal(h.control.commands.length, 4, 'missing required value must not reach the port');
});

test('T09_C10_renameAndAssignNeverTouchTheNetwork', async () => {
  const { h, familyId } = await setup();
  const room = await h.rooms.createRoom(familyId, 'Living');
  await h.devices.applyDiscoverSnapshot(discovery([snapshotDevice('Light_01')]),
    options(h, familyId));
  const key = new DeviceKey(GATEWAY_ID, 'Light_01');
  await h.devices.renameDevice(familyId, key, 'Desk Lamp');
  await h.devices.assignRoom(familyId, key, room.roomId);
  await h.devices.unassignDevice(familyId, key);
  await h.devices.assignRoom(familyId, key, room.roomId);
  const record = await h.devices.getRecord(key);
  assert.equal(record.state.deviceName, 'Desk Lamp');
  assert.equal(h.control.commands.length, 0);
});

test('T09_O1_gateSerializesOperations', async () => {
  const gate = new DomainOperationGate();
  const order = [];
  let release;
  const blocked = new Promise((resolve) => {
    release = resolve;
  });
  const first = gate.run(async () => {
    order.push('first-start');
    await blocked;
    order.push('first-end');
  });
  const second = gate.run(async () => {
    order.push('second');
  });
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(order, ['first-start']);
  release();
  await first;
  await second;
  assert.deepEqual(order, ['first-start', 'first-end', 'second']);
});

test('T09_O1_gateAllowsLegitQueueWithinTimeout', async () => {
  // D-023: the bounded wait is a global queue budget. Two legitimate serial
  // operations that each finish inside the budget must both succeed.
  const gate = new DomainOperationGate(200);
  const order = [];
  const first = gate.run(async () => {
    order.push('first-start');
    await new Promise((resolve) => setTimeout(resolve, 20));
    order.push('first-end');
    return 'first';
  });
  const second = gate.run(async () => {
    order.push('second');
    return 'second';
  });
  assert.equal(await withTimeout(first, 1000), 'first');
  assert.equal(await withTimeout(second, 1000), 'second');
  assert.deepEqual(order, ['first-start', 'first-end', 'second']);
});

test('T09_C10_assignRoomRejectsRoomFromAnotherFamily', async () => {
  const { h, familyId } = await setup();
  const otherFamily = await h.families.createFamily('Other', 'Bob');
  const foreignRoom = await h.rooms.createRoom(otherFamily.familyId, 'Foreign');
  await h.devices.applyDiscoverSnapshot(discovery([snapshotDevice('Light_01')]),
    options(h, familyId));
  const key = new DeviceKey(GATEWAY_ID, 'Light_01');
  await assert.rejects(h.devices.assignRoom(familyId, key, foreignRoom.roomId),
    (error) => error.code === 'ROOM_NOT_FOUND');
  const record = await h.devices.getRecord(key);
  assert.equal(record.state.roomId, '');
  assert.equal(record.state.isUnassigned, true);
});

test('T09_C10_unboundGatewayAndFamilyMismatchIgnoreWholeDiscover', async () => {
  const { h, familyId } = await setup();
  const unbound = await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Ghost_01')], { gatewayId: 'gw-unbound' }),
    options(h, familyId));
  assert.equal(unbound.added, 0);
  assert.deepEqual(unbound.deviations, ['GATEWAY_NOT_BOUND']);
  assert.equal((await h.devices.listRecords(familyId)).length, 0);

  const otherFamily = await h.families.createFamily('Other', 'Bob');
  h.routes.add(GATEWAY_ID, otherFamily.familyId);
  const mismatch = await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01')]), options(h, familyId));
  assert.equal(mismatch.added, 0);
  assert.deepEqual(mismatch.deviations, ['GATEWAY_FAMILY_MISMATCH']);
  assert.equal((await h.devices.listRecords(familyId)).length, 0);
});

test('T09_C10_duplicateAndFamilyMismatchDevicesSetPartial', async () => {
  const { h, familyId } = await setup();
  await h.devices.applyDiscoverSnapshot(discovery([snapshotDevice('Light_02')]),
    options(h, familyId));
  const duplicate = await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01'), snapshotDevice('Light_01')]),
    options(h, familyId));
  assert.equal(duplicate.added, 1);
  assert.equal(duplicate.invalidDropped, 1);
  assert.equal(duplicate.partial, true);
  assert.ok(duplicate.deviations.includes('DUPLICATE_DEVICE'));
  // A partially invalid snapshot must not infer gateway removal for others.
  assert.equal(duplicate.gatewayRemovedMarked, 0);
  assert.equal((await h.devices.getRecord(new DeviceKey(GATEWAY_ID, 'Light_02'))).gatewayRemoved,
    false);

  const otherFamily = await h.families.createFamily('Other', 'Bob');
  h.routes.add(GATEWAY_ID, otherFamily.familyId);
  const mismatch = await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01', { updatedAt: T1, powerStatus: true })]),
    options(h, otherFamily.familyId));
  assert.equal(mismatch.invalidDropped, 1);
  assert.equal(mismatch.partial, true);
  assert.ok(mismatch.deviations.includes('FAMILY_MISMATCH'));
  const record = await h.devices.getRecord(new DeviceKey(GATEWAY_ID, 'Light_01'));
  assert.equal(record.state.familyId, familyId);
});

test('T09_C10_throwingListenerDoesNotAbortDiscover', async () => {
  const { h, familyId } = await setup();
  let calls = 0;
  h.devices.subscribe(() => {
    calls++;
    throw new Error('listener boom');
  });
  const result = await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01')]), options(h, familyId));
  assert.equal(result.added, 1);
  assert.equal(calls, 1);
  assert.ok(await h.devices.getRecord(new DeviceKey(GATEWAY_ID, 'Light_01')));
  assert.ok(h.logger.entries.includes('W DeviceRepository device_listener_failed'));
});

test('T09_C10_commitFailureEmitsNoDeviceEvent', async () => {
  const { h, familyId } = await setup();
  let events = 0;
  h.devices.subscribe(() => {
    events++;
  });
  h.rdb.failCommit = true;
  await assert.rejects(h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01')]), options(h, familyId)),
  (error) => error.code === 'STORAGE_RDB_ERROR');
  assert.equal(events, 0);
  assert.equal(await h.devices.getRecord(new DeviceKey(GATEWAY_ID, 'Light_01')), undefined);
});

test('T09_C10_commitFailureRollsBackDiagnostics', async () => {
  const { h, familyId } = await setup();
  const opt = options(h, familyId);
  await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01', { updatedAt: T1 })], { isPartial: true }), opt);
  let record = await h.devices.getRecord(new DeviceKey(GATEWAY_ID, 'Light_01'));
  assert.equal(record.merge.lastResult, DeviceMergeResult.ADDED);
  assert.equal(record.hasPartialState, true);

  h.rdb.failCommit = true;
  // The full snapshot would clear the partial flag and rewrite the merge
  // diagnostics, but its commit fails; both caches must roll back (R2-05).
  await assert.rejects(h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01', { updatedAt: T1 })]), opt),
  (error) => error.code === 'STORAGE_RDB_ERROR');
  record = await h.devices.getRecord(new DeviceKey(GATEWAY_ID, 'Light_01'));
  assert.equal(record.merge.lastResult, DeviceMergeResult.ADDED);
  assert.equal(record.hasPartialState, true);
  assert.equal(record.state.snapshot.updatedAt, T1);
  assert.equal(h.rdb.failCommit, false);
});

test('T09_C10_removeDevicesForGatewayReadsRouteOutsideTransaction', async () => {
  const { h, familyId } = await setup();
  await h.devices.applyDiscoverSnapshot(
    discovery([snapshotDevice('Light_01'), snapshotDevice('Light_02')]),
    options(h, familyId));
  const sceneId = '123e4567-e89b-12d3-a456-000000000099';
  await h.scenes.putScene(new Scene(sceneId, familyId, 'Movie', 'scene.movie',
    [new SceneAction(GATEWAY_ID, 'Light_01', DeviceAction.TURN_ON, true)], true));
  let readInsideTransaction = false;
  const wrappedRoutes = {
    listRoutes: () => h.routes.listRoutes(),
    listRoutesByFamily: (id) => h.routes.listRoutesByFamily(id),
    getRoute: async (gatewayId) => {
      if (h.rdb.isInTransactionForTest()) {
        readInsideTransaction = true;
      }
      return h.routes.getRoute(gatewayId);
    },
    isBound: (gatewayId) => h.routes.isBound(gatewayId)
  };
  const devices = new DeviceRepository(h.rdb, h.rooms, h.scenes, h.clock, h.logger, h.gate,
    wrappedRoutes);
  await devices.initialize();
  const removed = await devices.removeDevicesForGateway(GATEWAY_ID);
  assert.equal(removed, 2);
  assert.equal(readInsideTransaction, false);
  assert.equal((await h.scenes.getScene(sceneId)).actions.length, 0);
});

test('T09_C10_commandRunnerRejectsUnassignedDeviceWithZeroCommands', async () => {
  const { h, familyId } = await setup();
  await h.devices.applyDiscoverSnapshot(discovery([snapshotDevice('Light_01')]),
    options(h, familyId));
  await h.rdb.execute('UPDATE device_state SET is_enabled = ?, is_unassigned = ? ' +
    'WHERE gateway_id = ? AND device_id = ?', [1, 1, GATEWAY_ID, 'Light_01']);
  const runner = new DeviceCommandRunner(h.control, h.devices, h.clock, h.logger, h.metrics);
  const execution = await runner.run(
    command(GATEWAY_ID, 'Light_01', DeviceAction.TURN_ON, 1700000000000, true),
    { familyId, precheck: true });
  expectCode(execution.error, 'DEVICE_UNASSIGNED');
  assert.equal(h.control.commands.length, 0);
});

test('T09_O1_gateRejectsSynchronousNestedRun', async () => {
  const gate = new DomainOperationGate();
  let innerRan = false;
  await assert.rejects(withTimeout(gate.run(async () => {
    await gate.run(async () => {
      innerRan = true;
    });
  }), 500), (error) => error.code === 'CONFIGURATION_ERROR');
  assert.equal(innerRan, false);
  // The gate remains usable after the rejected reentrant call.
  await gate.run(async () => {
  });
});

test('T09_O1_gateRejectsAsyncReentrantCallInsteadOfHanging', async () => {
  const gate = new DomainOperationGate(50);
  let innerRan = false;
  await assert.rejects(withTimeout(gate.run(async () => {
    await Promise.resolve();
    await gate.run(async () => {
      innerRan = true;
    });
  }), 500), (error) => error.code === 'CONFIGURATION_ERROR' &&
    error.details.some((detail) => detail.name === 'field' &&
      detail.value === 'nestedOperationOrQueueTimeout'));
  assert.equal(innerRan, false);
});

test('T09_O1_nestedFakeTransactionFailsFast', async () => {
  const h = await newDomainHarness();
  await assert.rejects(withTimeout(h.rdb.transaction(async () => {
    await h.rdb.transaction(async () => {
    });
  }), 500), (error) => error.code === 'STORAGE_RDB_ERROR');
});

test('T09_C09_v4StaticRegistrationIsDelegatedAndIdempotent', async () => {
  const { h } = await setup();
  // The harness already registered v4 through the three component statics.
  RoomRepository.registerMigrations(h.registry);
  DeviceRepository.registerMigrations(h.registry);
  SceneRepository.registerMigrations(h.registry);
  DomainMigrations.register(h.registry);
  assert.ok(h.rdb.tableNamesForTest().includes('room'));
  assert.ok(h.rdb.tableNamesForTest().includes('device_state'));
  assert.ok(h.rdb.tableNamesForTest().includes('scene'));
  assert.ok(h.rdb.tableNamesForTest().includes('cloud_config'));
  // A genuinely different duplicate version registration is still rejected.
  assert.throws(() => h.registry.register(4, ['SELECT 1']),
    (error) => error.code === 'CONFIGURATION_ERROR');
});
