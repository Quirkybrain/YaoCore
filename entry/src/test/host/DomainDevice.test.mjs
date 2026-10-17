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
import {
  ControlApplyContext,
  ControlApplyReason,
  DeviceMergeResult,
  DiscoverApplyOptions
} from '../../main/ets/repository/DomainModels.ets';
import { DeviceRepository } from '../../main/ets/repository/DeviceRepository.ets';
import { DeviceKey } from '../../main/ets/model/DeviceKey.ets';
import { DeviceAction, DeviceType } from '../../main/ets/common/constants/DeviceConstants.ets';
import { StateVerification } from '../../main/ets/model/ControlModels.ets';
import { DeviceCommandRunner } from '../../main/ets/service/device/DeviceCommandRunner.ets';
import { Scene, SceneAction } from '../../main/ets/model/FamilyModels.ets';
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
