/*
 * YaoCore T-16 SceneViewModel host tests.
 * Producer: agent:implementation-engineer | Task: T-16 / wp-060-vm
 * Contract: DES-B §11.1.3, §11.3.4; FR-SCN-001.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { SceneViewModel } from '../../main/ets/viewmodel/SceneViewModel.ets';
import { Scene } from '../../main/ets/model/FamilyModels.ets';
import { PolicyDecision } from '../../main/ets/service/auth/AuthModels.ets';
import { FakeI18n, FakeLogger } from './viewmodel-helpers.mjs';

const SCENE_ID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

function scene() {
  return new Scene(SCENE_ID, 'family-1', 'Movie', 'film', [], true);
}

function progress(runId, state, currentIndex, steps = []) {
  return {
    runId,
    sceneId: SCENE_ID,
    state,
    currentIndex,
    steps,
    executedCount: steps.length,
    succeededCount: steps.filter((step) => step.state === 'SUCCEEDED').length
  };
}

function result(state, steps = [], options = {}) {
  return {
    runId: options.runId === undefined ? 'run-1' : options.runId,
    sceneId: SCENE_ID,
    sceneName: 'Movie',
    state,
    steps,
    startedAtMs: 1,
    endedAtMs: 2,
    executedCount: steps.length,
    succeededCount: steps.filter((step) => step.state === 'SUCCEEDED').length,
    failedStepIndex: options.failedStepIndex,
    error: options.error,
    noRollbackNotice: true
  };
}

class FakeSceneService {
  constructor() {
    this.scenes = [scene()];
    this.progress = undefined;
    this.result = undefined;
    this.cancelRunId = undefined;
    this.resolveRun = undefined;
    this.created = [];
    this.updated = [];
    this.deleted = [];
  }

  async listScenes() { return this.scenes; }

  async run(sceneId, listener) {
    this.progress = listener;
    if (this.result !== undefined && this.resolveRun === undefined) {
      if (listener !== undefined) {
        listener(progress('run-1', 'RUNNING', 0, []));
      }
      return this.result;
    }
    return new Promise((resolve) => {
      this.resolveRun = resolve;
    });
  }

  emit(value) {
    this.progress(value);
  }

  finish(value) {
    const resolve = this.resolveRun;
    this.resolveRun = undefined;
    resolve(value);
  }

  async cancel(runId) {
    this.cancelRunId = runId;
  }

  async createScene(input) {
    this.created.push(input);
    return scene();
  }

  async updateScene(sceneId, input) {
    this.updated.push({ sceneId, input });
    return scene();
  }

  async deleteScene(sceneId) {
    this.deleted.push(sceneId);
    this.scenes = [];
  }
}

function allowAll() {
  return { canExecuteScene: () => PolicyDecision.allow() };
}

function setup(authorization = allowAll()) {
  const service = new FakeSceneService();
  const vm = new SceneViewModel(service, {}, new FakeI18n(), new FakeLogger(),
    authorization);
  return { service, vm };
}

test('T16_Scene_initializeListsScenes', async () => {
  const h = setup();
  await h.vm.initialize('family-1');
  assert.equal(h.vm.getState().phase, 'READY');
  assert.equal(h.vm.getState().scenes.length, 1);
});

test('T16_Scene_runPassesProgressAndStoresSucceededResult', async () => {
  const h = setup();
  const steps = [
    { index: 0, state: 'SUCCEEDED' },
    { index: 1, state: 'SUCCEEDED' }
  ];
  h.service.result = result('SUCCEEDED', steps);
  await h.vm.initialize('family-1');
  const final = await h.vm.run(SCENE_ID);
  const state = h.vm.getState();
  assert.equal(state.runningSceneId, undefined);
  assert.equal(state.lastResult.state, 'SUCCEEDED');
  assert.equal(final.noRollbackNotice, true);
});

test('T16_Scene_partialFailurePreservesStepsAndNoRollbackNotice', async () => {
  const h = setup();
  const steps = [
    { index: 0, state: 'SUCCEEDED' },
    { index: 1, state: 'FAILED' },
    { index: 2, state: 'SKIPPED' }
  ];
  h.service.result = result('PARTIAL_FAILED', steps, { failedStepIndex: 1 });
  await h.vm.initialize('family-1');
  await h.vm.run(SCENE_ID);
  const last = h.vm.getState().lastResult;
  assert.equal(last.state, 'PARTIAL_FAILED');
  assert.equal(last.noRollbackNotice, true);
  assert.equal(last.steps[1].state, 'FAILED');
  assert.equal(last.steps[2].state, 'SKIPPED');
  assert.equal(last.steps[2].state === 'SUCCEEDED', false);
});

test('T16_Scene_cancelCallsServiceWithRunIdAndKeepsCancelledResult', async () => {
  const h = setup();
  await h.vm.initialize('family-1');
  const running = h.vm.run(SCENE_ID);
  h.service.emit(progress('run-9', 'CANCELLED', 0, []));
  await h.vm.cancel();
  assert.equal(h.service.cancelRunId, 'run-9');
  h.service.finish(result('CANCELLED', [], { runId: 'run-9' }));
  const final = await running;
  assert.equal(final.state, 'CANCELLED');
  assert.equal(h.vm.getState().lastResult.state, 'CANCELLED');
});

test('T16_Scene_secondRunWhileRunningIsRejected', async () => {
  const h = setup();
  await h.vm.initialize('family-1');
  const running = h.vm.run(SCENE_ID);
  assert.equal(h.vm.getState().runningSceneId, SCENE_ID);
  await assert.rejects(h.vm.run(SCENE_ID),
    (error) => error.code === 'SCENE_RUN_IN_PROGRESS');
  h.service.emit(progress('run-9', 'RUNNING', 0, []));
  h.service.finish(result('CANCELLED', [], { runId: 'run-9' }));
  await running;
});

test('T16_Scene_crudDelegatesAndRefreshes', async () => {
  const h = setup();
  await h.vm.initialize('family-1');
  await h.vm.createScene({ familyId: 'family-1', sceneName: 'Night', icon: 'moon',
    actions: [], isEnabled: true });
  assert.equal(h.service.created.length, 1);
  await h.vm.updateScene(SCENE_ID, { familyId: 'family-1', sceneName: 'Night 2',
    icon: 'moon', actions: [], isEnabled: true });
  assert.equal(h.service.updated.length, 1);
  await h.vm.deleteScene(SCENE_ID);
  assert.equal(h.service.deleted[0], SCENE_ID);
  assert.equal(h.vm.getState().scenes.length, 0);
});

test('T16_Scene_clearResultKeepsScenes', async () => {
  const h = setup();
  h.service.result = result('SUCCEEDED', []);
  await h.vm.initialize('family-1');
  await h.vm.run(SCENE_ID);
  h.vm.clearResult();
  assert.equal(h.vm.getState().lastResult, undefined);
  assert.equal(h.vm.getState().scenes.length, 1);
});

test('T18_SceneViewModel_capabilityAndRunRbacMatrix', async () => {
  const matrix = [
    { role: 'ADMIN', allowed: true },
    { role: 'MEMBER', allowed: true },
    { role: 'GUEST', allowed: false }
  ];
  for (const entry of matrix) {
    const authorization = {
      canExecuteScene: () => entry.allowed
        ? PolicyDecision.allow() : PolicyDecision.deny('RBAC_DENIED')
    };
    const h = setup(authorization);
    await h.vm.initialize('family-1');
    assert.equal(h.vm.canExecuteScene(), entry.allowed, entry.role);
    if (entry.allowed) {
      h.service.result = result('SUCCEEDED', []);
      const final = await h.vm.run(SCENE_ID);
      assert.equal(final.state, 'SUCCEEDED', entry.role);
    } else {
      await assert.rejects(h.vm.run(SCENE_ID),
        (error) => error.code === 'AUTH_RBAC_DENIED', entry.role);
      assert.equal(h.service.progress, undefined, entry.role);
      assert.equal(h.vm.getState().error.error.code, 'AUTH_RBAC_DENIED', entry.role);
    }
  }
  // Missing policy is fail-closed even before a service call.
  const noPolicy = new SceneViewModel(new FakeSceneService(), {}, new FakeI18n(),
    new FakeLogger());
  assert.equal(noPolicy.canExecuteScene(), false);
  await assert.rejects(noPolicy.run(SCENE_ID),
    (error) => error.code === 'AUTH_RBAC_DENIED');
});
