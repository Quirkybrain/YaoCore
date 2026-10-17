/*
 * YaoCore T-15 ClimateViewModel host tests.
 * Producer: agent:implementation-engineer | Task: T-15 / wp-060-vm
 * Contract: DES-B §10.1.6; CB §6.2/§6.3.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { ClimateViewModel } from '../../main/ets/viewmodel/ClimateViewModel.ets';
import { DeviceAction } from '../../main/ets/common/constants/DeviceConstants.ets';
import { AcMode } from '../../main/ets/model/DeviceTypes.ets';
import {
  FakeClock,
  FakeControlCoordinator,
  FakeDeviceQuery,
  FakeI18n,
  FakeLogger,
  FakeTimer,
  executionOf,
  record,
  waitMicrotasks
} from './viewmodel-helpers.mjs';

function acRecord(options = {}) {
  return record({
    deviceId: options.deviceId === undefined ? 'ac-1' : options.deviceId,
    deviceType: 'ac',
    deviceName: 'AC',
    brand: 'gree',
    powerStatus: options.powerStatus === undefined ? true : options.powerStatus,
    targetTemperature: options.targetTemperature === undefined ? 24 : options.targetTemperature,
    mode: options.mode === undefined ? 'COOL' : options.mode,
    modeStandard: true
  });
}

function setup() {
  const clock = new FakeClock();
  const timer = new FakeTimer(clock);
  const ac = acRecord();
  const devices = new FakeDeviceQuery([ac]);
  const control = new FakeControlCoordinator();
  const vm = new ClimateViewModel(devices, control, new FakeI18n(), clock, timer,
    new FakeLogger());
  return { clock, timer, ac, devices, control, vm, key: ac.state.key };
}

test('T15_Climate_loadMapsAdapterModeOptionsAndCapabilities', async () => {
  const h = setup();
  await h.vm.load(h.key);
  const state = h.vm.getState();
  assert.equal(state.phase, 'READY');
  assert.equal(state.modeOptions.length, 7);
  assert.equal(state.ac.brandI18nKey, 'brand.gree');
  assert.equal(state.ac.targetTemperature, 24);
  assert.equal(state.ac.mode.mode, AcMode.COOL);
});

test('T15_Climate_togglePowerUsesAdapterStandardAction', async () => {
  const h = setup();
  const off = acRecord({ powerStatus: false });
  h.control.push(executionOf(off, DeviceAction.TURN_OFF, { value: false }));
  await h.vm.load(h.key);
  await h.vm.togglePower();
  assert.equal(h.control.calls[0].command.action, DeviceAction.TURN_OFF);
  assert.equal(h.vm.getState().control.phase, 'COMMITTED');
});

test('T15_Climate_setModeRejectsNonStandardModeBeforeAnyCall', async () => {
  const h = setup();
  await h.vm.load(h.key);
  await h.vm.setMode('TURBO');
  assert.equal(h.control.calls.length, 0);
  assert.equal(h.vm.getState().error.error.code, 'CONFIGURATION_ERROR');
});

test('T15_Climate_newBeginDropsAnOlderInFlightTemperatureResult', async () => {
  const h = setup();
  const releases = [];
  h.control.execute = async () => new Promise((resolve) => {
    releases.push(resolve);
  });
  await h.vm.load(h.key);
  h.vm.beginTemperature(24);
  h.vm.updateTemperature(25);
  h.timer.advance(55);
  await waitMicrotasks();
  assert.equal(releases.length, 1);
  h.vm.beginTemperature(24);
  h.vm.updateTemperature(26);
  h.timer.advance(55);
  await waitMicrotasks();
  assert.equal(releases.length, 2);
  releases[0](executionOf(acRecord({ targetTemperature: 25 }),
    DeviceAction.SET_TARGET_TEMPERATURE, { value: 25 }));
  await waitMicrotasks();
  let control = h.vm.getState().control;
  assert.equal(control.phase, 'PENDING');
  assert.equal(control.optimisticValue, 26);
  const ending = h.vm.endTemperature(26);
  await waitMicrotasks();
  releases[1](executionOf(acRecord({ targetTemperature: 26 }),
    DeviceAction.SET_TARGET_TEMPERATURE, { value: 26 }));
  await ending;
  control = h.vm.getState().control;
  assert.equal(control.phase, 'COMMITTED');
  assert.equal(control.confirmedValue, 26);
});

test('T15_Climate_temperatureContinuousCoalescesAndTouchUpCommits', async () => {
  const h = setup();
  const warmed = acRecord({ targetTemperature: 26 });
  h.control.push(executionOf(warmed, DeviceAction.SET_TARGET_TEMPERATURE, { value: 26 }));
  await h.vm.load(h.key);
  h.vm.beginTemperature(24);
  h.vm.updateTemperature(25);
  h.vm.updateTemperature(26);
  h.timer.advance(55);
  await waitMicrotasks();
  assert.equal(h.control.calls.length, 1);
  assert.equal(h.control.calls[0].command.value, 26);
  await h.vm.endTemperature(26);
  const control = h.vm.getState().control;
  assert.equal(control.phase, 'COMMITTED');
  assert.equal(control.confirmedValue, 26);
});
