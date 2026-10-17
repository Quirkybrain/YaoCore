/*
 * YaoCore T-09 C-11 SceneRepository / SceneService host tests.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §6.1-§6.4; FR-SCN-001; D-019 host layer.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { newDomainHarness } from '../domain/DomainHarness.ets';
import { DiscoverApplyOptions } from '../../main/ets/repository/DomainModels.ets';
import { SceneService, SceneInput } from '../../main/ets/service/scene/SceneService.ets';
import { RoomService, RoomDeletionConfirmation } from '../../main/ets/service/room/RoomService.ets';
import { DeviceKey } from '../../main/ets/model/DeviceKey.ets';
import { DeviceAction, DeviceType } from '../../main/ets/common/constants/DeviceConstants.ets';
import { StateVerification } from '../../main/ets/model/ControlModels.ets';
import {
  GATEWAY_ID,
  discovery,
  snapshotDevice,
  sceneAction,
  acceptedOutcome,
  rejectedOutcome
} from './domain-helpers.mjs';

const tick = () => new Promise((resolve) => setImmediate(resolve));

async function setup() {
  const h = await newDomainHarness();
  const family = await h.families.createFamily('Home', 'Alice');
  const familyId = family.familyId;
  h.routes.add(GATEWAY_ID, familyId);
  const room = await h.rooms.createRoom(familyId, 'Living');
  await h.devices.applyDiscoverSnapshot(discovery([
    snapshotDevice('Light_01', { powerStatus: false }),
    snapshotDevice('AC_01', { deviceType: DeviceType.AC, deviceTypeRaw: 'ac' }),
    snapshotDevice('Door_01', { deviceType: DeviceType.DOOR, deviceTypeRaw: 'door' })
  ]), new DiscoverApplyOptions(familyId, h.clock.nowMs()));
  for (const id of ['Light_01', 'AC_01', 'Door_01']) {
    await h.devices.assignRoom(familyId, new DeviceKey(GATEWAY_ID, id), room.roomId);
  }
  const service = new SceneService(h.scenes, h.devices, h.control, h.routes, h.clock,
    h.timer, h.ids, h.logger, h.metrics, h.rdb, h.gate);
  await service.initialize();
  return { h, familyId, room, service };
}

async function createLightScene(service, familyId, options = {}) {
  const actions = options.actions === undefined ?
    [sceneAction(GATEWAY_ID, 'Light_01', DeviceAction.TURN_ON, true)] : options.actions;
  return service.createScene(new SceneInput(familyId, options.name === undefined ? 'Movie' :
    options.name, 'scene.icons.movie', actions,
  options.isEnabled === undefined ? true : options.isEnabled));
}

test('T09_C11_sceneCrudAndValidation', async () => {
  const { h, familyId, service } = await setup();
  const scene = await createLightScene(service, familyId);
  assert.equal((await service.listScenes(familyId)).length, 1);
  const updated = await service.updateScene(scene.sceneId, new SceneInput(familyId, 'Cinema',
    'scene.icons.cinema', [sceneAction(GATEWAY_ID, 'Light_01', DeviceAction.TURN_OFF, false)], true));
  assert.equal(updated.sceneId, scene.sceneId);
  assert.equal(updated.sceneName, 'Cinema');
  await service.deleteScene(scene.sceneId);
  assert.equal(await service.getScene(scene.sceneId), undefined);
  await assert.rejects(service.deleteScene(scene.sceneId), (error) => error.code === 'SCENE_NOT_FOUND');
  await assert.rejects(service.createScene(new SceneInput(familyId, '', 'x', [], true)),
    (error) => error.code === 'SCENE_NAME_INVALID');
  await assert.rejects(service.createScene(new SceneInput(familyId, 'Empty', 'x', [], true)),
    (error) => error.code === 'SCENE_EMPTY');
  await assert.rejects(service.createScene(new SceneInput(familyId, 'Bad', 'x',
    [sceneAction('gw-missing', 'Light_01', DeviceAction.TURN_ON, true)], true)),
  (error) => error.code === 'SCENE_REFERENCE_INVALID');
  assert.equal(h.control.commands.length, 0);
});

test('T09_C11_runSucceedsSeriallyAndEmitsEvents', async () => {
  const { h, familyId, service } = await setup();
  const scene = await createLightScene(service, familyId, {
    actions: [
      sceneAction(GATEWAY_ID, 'Light_01', DeviceAction.TURN_ON, true),
      sceneAction(GATEWAY_ID, 'AC_01', DeviceAction.SET_TARGET_TEMPERATURE, 24)
    ]
  });
  const events = [];
  const unsubscribe = service.subscribe((event) => events.push(event.type));
  const result = await service.run(scene.sceneId);
  unsubscribe();
  assert.equal(result.state, 'SUCCEEDED');
  assert.equal(result.executedCount, 2);
  assert.equal(result.succeededCount, 2);
  assert.equal(result.noRollbackNotice, true);
  assert.equal(h.control.commands.length, 2);
  assert.equal(h.control.commands[0].target, 'Light_01');
  assert.equal(h.control.commands[1].target, 'AC_01');
  assert.ok(events.includes('STARTED'));
  assert.ok(events.includes('STEP_SUCCEEDED'));
  assert.ok(events.includes('FINISHED'));
  assert.ok(h.metrics.names.includes('scene_run_ms'));
});

test('T09_C11_preflightFailureSendsZeroCommands', async () => {
  const { h, familyId, service } = await setup();
  const missing = await service.createScene(new SceneInput(familyId, 'Missing',
    'scene.icons.x', [sceneAction(GATEWAY_ID, 'Light_99', DeviceAction.TURN_ON, true)], true));
  const result = await service.run(missing.sceneId);
  assert.equal(result.state, 'FAILED');
  assert.equal(result.executedCount, 0);
  assert.equal(result.failedStepIndex, 0);
  assert.equal(result.error.code, 'SCENE_PREFLIGHT_FAILED');
  assert.equal(h.control.commands.length, 0);

  const mismatchType = await service.createScene(new SceneInput(familyId, 'TypeMismatch',
    'scene.icons.x', [sceneAction(GATEWAY_ID, 'Light_01', DeviceAction.OPEN, true)], true));
  const second = await service.run(mismatchType.sceneId);
  assert.equal(second.state, 'FAILED');
  assert.equal(h.control.commands.length, 0);
});

test('T09_C11_firstStepFailureMarksRestSkipped', async () => {
  const { h, familyId, service } = await setup();
  h.control.defaultAccepted = false;
  const scene = await createLightScene(service, familyId, {
    actions: [
      sceneAction(GATEWAY_ID, 'Light_01', DeviceAction.TURN_ON, true),
      sceneAction(GATEWAY_ID, 'AC_01', DeviceAction.TURN_ON, true)
    ]
  });
  const result = await service.run(scene.sceneId);
  assert.equal(result.state, 'FAILED');
  assert.equal(result.executedCount, 1);
  assert.equal(result.succeededCount, 0);
  assert.equal(result.steps[0].state, 'FAILED');
  assert.equal(result.steps[1].state, 'SKIPPED');
  assert.equal(result.noRollbackNotice, true);
  assert.equal(h.control.commands.length, 1);
});

test('T09_C11_secondStepFailureIsPartialFailedWithoutRollback', async () => {
  const { h, familyId, service } = await setup();
  h.control.outcomes.push(acceptedOutcome('Light_01'));
  h.control.outcomes.push(rejectedOutcome('AC_01'));
  const scene = await createLightScene(service, familyId, {
    actions: [
      sceneAction(GATEWAY_ID, 'Light_01', DeviceAction.TURN_ON, true),
      sceneAction(GATEWAY_ID, 'AC_01', DeviceAction.TURN_ON, true),
      sceneAction(GATEWAY_ID, 'Door_01', DeviceAction.OPEN, true)
    ]
  });
  const result = await service.run(scene.sceneId);
  assert.equal(result.state, 'PARTIAL_FAILED');
  assert.equal(result.executedCount, 2);
  assert.equal(result.succeededCount, 1);
  assert.equal(result.failedStepIndex, 1);
  assert.equal(result.steps[0].state, 'SUCCEEDED');
  assert.equal(result.steps[1].state, 'FAILED');
  assert.equal(result.steps[2].state, 'SKIPPED');
  assert.equal(result.noRollbackNotice, true);
  assert.equal(h.control.commands.length, 2);
});

test('T09_C11_mismatchFailsUnverifiedSucceeds', async () => {
  const { h, familyId, service } = await setup();
  h.control.outcomes.push(acceptedOutcome('Light_01', GATEWAY_ID,
    { verification: StateVerification.MISMATCH }));
  const mismatchScene = await createLightScene(service, familyId);
  const mismatch = await service.run(mismatchScene.sceneId);
  assert.equal(mismatch.state, 'FAILED');
  assert.equal(mismatch.steps[0].stateVerification, StateVerification.MISMATCH);

  const unverifiedScene = await createLightScene(service, familyId, {
    name: 'Unverified', actions: [sceneAction(GATEWAY_ID, 'AC_01', DeviceAction.TURN_ON, true)]
  });
  const unverified = await service.run(unverifiedScene.sceneId);
  assert.equal(unverified.state, 'SUCCEEDED');
  assert.equal(unverified.steps[0].stateVerification, StateVerification.UNVERIFIED);
});

test('T09_C11_delayMsWaitsForTimerBeforeCommand', async () => {
  const { h, familyId, service } = await setup();
  const scene = await createLightScene(service, familyId, {
    actions: [sceneAction(GATEWAY_ID, 'Light_01', DeviceAction.TURN_ON, true, 500)]
  });
  const running = service.run(scene.sceneId);
  for (let index = 0; index < 5; index++) {
    await tick();
  }
  assert.equal(h.control.commands.length, 0);
  h.timer.advance(500);
  const result = await running;
  assert.equal(result.state, 'SUCCEEDED');
  assert.equal(h.control.commands.length, 1);
});

test('T09_C11_cancelDuringDelayLeavesExecutedStepsAndSkipsRest', async () => {
  const { h, familyId, service } = await setup();
  const scene = await createLightScene(service, familyId, {
    actions: [
      sceneAction(GATEWAY_ID, 'Light_01', DeviceAction.TURN_ON, true, 1000),
      sceneAction(GATEWAY_ID, 'AC_01', DeviceAction.TURN_ON, true)
    ]
  });
  let runId = '';
  const running = service.run(scene.sceneId, (progress) => {
    runId = progress.runId;
  });
  for (let index = 0; index < 5; index++) {
    await tick();
  }
  await service.cancel(runId);
  const result = await running;
  assert.equal(result.state, 'CANCELLED');
  assert.equal(result.executedCount, 0);
  assert.equal(result.steps[0].state, 'SKIPPED');
  assert.equal(result.steps[1].state, 'SKIPPED');
  assert.equal(result.error.code, 'SCENE_CANCELLED');
  assert.equal(h.control.commands.length, 0);
});

test('T09_C11_roomDeletionMakesScenePreflightUnassigned', async () => {
  const { h, familyId, room, service } = await setup();
  const scene = await createLightScene(service, familyId);
  const rooms = new RoomService(h.rooms, h.devices, h.families, h.rdb, h.clock,
    h.logger, h.gate, h.devices);
  await rooms.deleteRoom(room.roomId, new RoomDeletionConfirmation(true, 3));
  const result = await service.run(scene.sceneId);
  assert.equal(result.state, 'FAILED');
  assert.equal(result.error.code, 'SCENE_PREFLIGHT_FAILED');
  assert.equal(h.control.commands.length, 0);
});

test('T09_C11_disabledAndEmptyScenesAreRejected', async () => {
  const { familyId, service } = await setup();
  const disabled = await createLightScene(service, familyId, {
    name: 'Disabled', isEnabled: false
  });
  await assert.rejects(service.run(disabled.sceneId), (error) => error.code === 'SCENE_DISABLED');
  await assert.rejects(service.run('123e4567-e89b-12d3-a456-000000000099'),
    (error) => error.code === 'SCENE_NOT_FOUND');
});
