/*
 * YaoCore T-15 DeviceViewModel host tests.
 * Producer: agent:implementation-engineer | Task: T-15 / wp-060-vm
 * Contract: DES-B §10.1.3, §10.3.1, §10.3.2; FR-DEV-001; D-019.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { DeviceViewModel } from '../../main/ets/viewmodel/DeviceViewModel.ets';
import {
  ControlPhase
} from '../../main/ets/viewmodel/core/ViewModelCore.ets';
import { DeviceAction } from '../../main/ets/common/constants/DeviceConstants.ets';
import { AppErrors } from '../../main/ets/common/types/AppError.ets';
import {
  FakeClock,
  FakeControlCoordinator,
  FakeDeviceQuery,
  FakeI18n,
  FakeLogger,
  FakeRoomQuery,
  FakeTimer,
  ROOM_A,
  executionOf,
  record,
  waitMicrotasks
} from './viewmodel-helpers.mjs';

function setup(options = {}) {
  const clock = new FakeClock();
  const timer = new FakeTimer(clock);
  const light = options.record === undefined ? record({ powerStatus: false }) : options.record;
  const devices = new FakeDeviceQuery([light]);
  const control = new FakeControlCoordinator();
  const vm = new DeviceViewModel(devices, new FakeRoomQuery([]), control, new FakeI18n(), clock,
    timer, new FakeLogger());
  return { clock, timer, light, devices, control, vm, key: light.state.key };
}

test('T15_Device_threePhasePendingThenCommitted', async () => {
  const h = setup();
  const powered = record({ powerStatus: true });
  h.control.push(executionOf(powered, DeviceAction.TURN_ON, { value: true }));
  await h.vm.initialize('family-1');
  const pending = h.vm.togglePower(h.key);
  assert.equal(h.vm.getControl(h.key).phase, ControlPhase.PENDING);
  await pending;
  const control = h.vm.getControl(h.key);
  assert.equal(control.phase, ControlPhase.COMMITTED);
  assert.equal(control.confirmedValue, true);
  assert.equal(h.control.calls[0].command.action, DeviceAction.TURN_ON);
});

test('T15_Device_mismatchRevertsAndAutoSettlesWithoutConfirmedValue', async () => {
  const h = setup();
  h.control.push(executionOf(h.light, DeviceAction.TURN_ON, {
    value: true,
    success: true,
    verification: 'MISMATCH'
  }));
  await h.vm.initialize('family-1');
  await h.vm.togglePower(h.key);
  let control = h.vm.getControl(h.key);
  assert.equal(control.phase, ControlPhase.REVERT);
  assert.equal(control.lastError.i18nKey, 'errors.app.ack_state_mismatch');
  h.timer.advance(320);
  control = h.vm.getControl(h.key);
  assert.equal(control.phase, ControlPhase.IDLE);
  assert.equal(control.confirmedValue, undefined);
});

test('T15_Device_errorRevertsToConfirmedValue', async () => {
  const h = setup();
  h.control.push(executionOf(h.light, DeviceAction.TURN_ON, {
    success: false,
    error: AppErrors.of('GATEWAY_UNREACHABLE', [])
  }));
  await h.vm.initialize('family-1');
  await h.vm.togglePower(h.key);
  const control = h.vm.getControl(h.key);
  assert.equal(control.phase, ControlPhase.REVERT);
  assert.equal(control.lastError.error.code, 'GATEWAY_UNREACHABLE');
  assert.equal(control.confirmedValue, undefined);
});

test('T15_Device_threeSecondTimeoutRevertsAndIgnoresLateResult', async () => {
  const h = setup();
  let resolveExecution;
  h.control.execute = async () => new Promise((resolve) => { resolveExecution = resolve; });
  await h.vm.initialize('family-1');
  const pending = h.vm.togglePower(h.key);
  assert.equal(h.vm.getControl(h.key).phase, ControlPhase.PENDING);
  h.timer.advance(3000);
  assert.equal(h.vm.getControl(h.key).phase, ControlPhase.REVERT);
  assert.equal(h.vm.getControl(h.key).lastError.error.code, 'GATEWAY_TIMEOUT');
  h.timer.advance(320);
  assert.equal(h.vm.getControl(h.key).phase, ControlPhase.IDLE);
  resolveExecution(executionOf(record({ powerStatus: true }), DeviceAction.TURN_ON,
    { value: true }));
  await pending;
  await waitMicrotasks();
  assert.equal(h.vm.getControl(h.key).phase, ControlPhase.IDLE);
});

test('T15_Device_continuous55msCoalescesAndTouchUpSendsFinalValue', async () => {
  const h = setup();
  const brightness20 = record({ brightness: 20 });
  const brightness80 = record({ brightness: 80 });
  h.control.push(executionOf(brightness20, DeviceAction.SET_BRIGHTNESS, { value: 20 }));
  h.control.push(executionOf(brightness80, DeviceAction.SET_BRIGHTNESS, { value: 80 }));
  await h.vm.initialize('family-1');
  h.vm.beginContinuous(h.key, DeviceAction.SET_BRIGHTNESS, 0, 100);
  h.vm.updateContinuous(h.key, 10);
  h.vm.updateContinuous(h.key, 20);
  h.timer.advance(54);
  assert.equal(h.control.calls.length, 0);
  h.timer.advance(1);
  await waitMicrotasks();
  assert.equal(h.control.calls.length, 1);
  assert.equal(h.control.calls[0].command.value, 20);
  h.vm.updateContinuous(h.key, 50);
  await h.vm.endContinuous(h.key, 80);
  await waitMicrotasks();
  assert.equal(h.control.calls.length, 2);
  assert.equal(h.control.calls[1].command.value, 80);
  const control = h.vm.getControl(h.key);
  assert.equal(control.phase, ControlPhase.COMMITTED);
  assert.equal(control.confirmedValue, 80);
});

test('T15_Device_cancelContinuousSendsNothingAndRebounds', async () => {
  const h = setup();
  h.control.push(executionOf(h.light, DeviceAction.SET_BRIGHTNESS, { value: 10 }));
  await h.vm.initialize('family-1');
  h.vm.beginContinuous(h.key, DeviceAction.SET_BRIGHTNESS, 0, 100);
  h.vm.updateContinuous(h.key, 10);
  h.vm.cancelContinuous(h.key);
  h.timer.advance(500);
  await waitMicrotasks();
  assert.equal(h.control.calls.length, 0);
  const control = h.vm.getControl(h.key);
  assert.equal(control.phase, ControlPhase.IDLE);
  assert.equal(control.optimisticValue, undefined);
});

test('T15_Device_cancelWhileDispatchInFlightDropsLateSuccess', async () => {
  const h = setup();
  let release;
  h.control.execute = async (command, familyId) => {
    h.control.calls.push({ command, familyId });
    return new Promise((resolve) => {
      release = resolve;
    });
  };
  await h.vm.initialize('family-1');
  h.vm.beginContinuous(h.key, DeviceAction.SET_BRIGHTNESS, 0, 100);
  h.vm.updateContinuous(h.key, 80);
  h.timer.advance(55);
  await waitMicrotasks();
  assert.equal(h.control.calls.length, 1);
  assert.equal(h.vm.getControl(h.key).phase, ControlPhase.PENDING);
  h.vm.cancelContinuous(h.key);
  assert.equal(h.vm.getControl(h.key).phase, ControlPhase.IDLE);
  release(executionOf(record({ brightness: 80 }), DeviceAction.SET_BRIGHTNESS, { value: 80 }));
  await waitMicrotasks();
  const control = h.vm.getControl(h.key);
  assert.equal(control.phase, ControlPhase.IDLE);
  assert.equal(control.optimisticValue, undefined);
  assert.equal(control.confirmedValue, undefined);
});

test('T15_Device_newBeginInvalidatesAnOlderDispatchResult', async () => {
  const h = setup();
  const releases = [];
  h.control.execute = async () => new Promise((resolve) => {
    releases.push(resolve);
  });
  await h.vm.initialize('family-1');
  h.vm.beginContinuous(h.key, DeviceAction.SET_BRIGHTNESS, 0, 100);
  h.vm.updateContinuous(h.key, 10);
  h.timer.advance(55);
  await waitMicrotasks();
  assert.equal(releases.length, 1);
  h.vm.beginContinuous(h.key, DeviceAction.SET_BRIGHTNESS, 0, 100);
  h.vm.updateContinuous(h.key, 30);
  h.timer.advance(55);
  await waitMicrotasks();
  assert.equal(releases.length, 2);
  releases[0](executionOf(record({ brightness: 10 }), DeviceAction.SET_BRIGHTNESS,
    { value: 10 }));
  await waitMicrotasks();
  const control = h.vm.getControl(h.key);
  assert.equal(control.phase, ControlPhase.PENDING);
  assert.equal(control.optimisticValue, 30);
  assert.equal(control.lastExecution, undefined);
  releases[1](executionOf(record({ brightness: 30 }), DeviceAction.SET_BRIGHTNESS,
    { value: 30 }));
  await waitMicrotasks();
  h.vm.cancelContinuous(h.key);
});

test('T15_Device_cancelRacingEndCommitNeverPublishesCommitted', async () => {
  const h = setup();
  let release;
  h.control.execute = async () => new Promise((resolve) => {
    release = resolve;
  });
  await h.vm.initialize('family-1');
  h.vm.beginContinuous(h.key, DeviceAction.SET_BRIGHTNESS, 0, 100);
  h.vm.updateContinuous(h.key, 20);
  h.timer.advance(55);
  await waitMicrotasks();
  const ending = h.vm.endContinuous(h.key, 40);
  await waitMicrotasks();
  h.vm.cancelContinuous(h.key);
  release(executionOf(record({ brightness: 20 }), DeviceAction.SET_BRIGHTNESS, { value: 20 }));
  await ending;
  await waitMicrotasks();
  const control = h.vm.getControl(h.key);
  assert.equal(control.phase, ControlPhase.IDLE);
  assert.equal(control.confirmedValue, undefined);
});

test('T15_Device_crossDeviceContinuousSessionsAreIndependent', async () => {
  const clock = new FakeClock();
  const timer = new FakeTimer(clock);
  const lightA = record({ deviceId: 'dev-a', brightness: 10 });
  const lightB = record({ deviceId: 'dev-b', brightness: 20 });
  const devices = new FakeDeviceQuery([lightA, lightB]);
  const control = new FakeControlCoordinator();
  const vm = new DeviceViewModel(devices, new FakeRoomQuery([]), control, new FakeI18n(), clock,
    timer, new FakeLogger());
  await vm.initialize('family-1');
  const keyA = lightA.state.key;
  const keyB = lightB.state.key;

  vm.beginContinuous(keyA, DeviceAction.SET_BRIGHTNESS, 0, 100);
  vm.beginContinuous(keyB, DeviceAction.SET_BRIGHTNESS, 0, 100);
  // R2-02: starting B must not cancel/invalidate A's session.
  assert.equal(vm.getControl(keyA).phase, ControlPhase.PENDING);
  assert.equal(vm.getControl(keyB).phase, ControlPhase.PENDING);

  control.push(executionOf(record({ deviceId: 'dev-a', brightness: 60 }),
    DeviceAction.SET_BRIGHTNESS, { value: 60 }));
  vm.updateContinuous(keyA, 60);
  timer.advance(55);
  await waitMicrotasks();
  assert.equal(control.calls.length, 1);
  assert.equal(control.calls[0].command.target, 'dev-a');
  assert.equal(control.calls[0].command.value, 60);
  await vm.endContinuous(keyA, 60);
  assert.equal(vm.getControl(keyA).phase, ControlPhase.COMMITTED);
  assert.equal(vm.getControl(keyA).confirmedValue, 60);
  // B's session is still active after A commits.
  assert.equal(vm.getControl(keyB).phase, ControlPhase.PENDING);

  control.push(executionOf(record({ deviceId: 'dev-b', brightness: 75 }),
    DeviceAction.SET_BRIGHTNESS, { value: 75 }));
  vm.updateContinuous(keyB, 75);
  timer.advance(55);
  await waitMicrotasks();
  assert.equal(control.calls.length, 2);
  assert.equal(control.calls[1].command.target, 'dev-b');
  assert.equal(control.calls[1].command.value, 75);
  await vm.endContinuous(keyB, 75);
  assert.equal(vm.getControl(keyB).phase, ControlPhase.COMMITTED);
  assert.equal(vm.getControl(keyB).confirmedValue, 75);
});

test('T15_Device_cancelOnOneDeviceKeepsAnotherSessionAlive', async () => {
  const clock = new FakeClock();
  const timer = new FakeTimer(clock);
  const lightA = record({ deviceId: 'dev-a', brightness: 10 });
  const lightB = record({ deviceId: 'dev-b', brightness: 20 });
  const devices = new FakeDeviceQuery([lightA, lightB]);
  const control = new FakeControlCoordinator();
  const vm = new DeviceViewModel(devices, new FakeRoomQuery([]), control, new FakeI18n(), clock,
    timer, new FakeLogger());
  await vm.initialize('family-1');
  const keyA = lightA.state.key;
  const keyB = lightB.state.key;

  vm.beginContinuous(keyA, DeviceAction.SET_BRIGHTNESS, 0, 100);
  vm.beginContinuous(keyB, DeviceAction.SET_BRIGHTNESS, 0, 100);
  vm.cancelContinuous(keyB);
  assert.equal(vm.getControl(keyA).phase, ControlPhase.PENDING);
  assert.equal(vm.getControl(keyB).phase, ControlPhase.IDLE);

  control.push(executionOf(record({ deviceId: 'dev-a', brightness: 40 }),
    DeviceAction.SET_BRIGHTNESS, { value: 40 }));
  vm.updateContinuous(keyA, 40);
  timer.advance(55);
  await waitMicrotasks();
  await vm.endContinuous(keyA, 40);
  assert.equal(control.calls.length, 1);
  assert.equal(control.calls[0].command.target, 'dev-a');
  assert.equal(vm.getControl(keyA).phase, ControlPhase.COMMITTED);
  assert.equal(vm.getControl(keyA).confirmedValue, 40);
});

test('T15_Device_roomFilterAndUnassignedPool', async () => {
  const clock = new FakeClock();
  const timer = new FakeTimer(clock);
  const assigned = record({ deviceId: 'dev-1', roomId: ROOM_A });
  const pool = record({ deviceId: 'dev-2', roomId: '', isUnassigned: true, isEnabled: false });
  const devices = new FakeDeviceQuery([assigned, pool]);
  const control = new FakeControlCoordinator();
  const vm = new DeviceViewModel(devices, new FakeRoomQuery([]), control, new FakeI18n(), clock,
    timer, new FakeLogger());
  await vm.initialize('family-1');
  assert.equal(vm.getState().records.length, 2);
  vm.setFilter({
    kind: 'UNASSIGNED',
    roomId: undefined
  });
  assert.equal(vm.getState().records.length, 1);
  assert.equal(vm.getState().records[0].state.isUnassigned, true);
});
