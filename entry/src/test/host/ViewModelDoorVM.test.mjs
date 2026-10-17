/*
 * YaoCore T-15 DoorViewModel host tests.
 * Producer: agent:implementation-engineer | Task: T-15 / wp-060-vm
 * Contract: DES-B §10.1.7; D-016; ADR-004 §6.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { DoorViewModel } from '../../main/ets/viewmodel/DoorViewModel.ets';
import {
  DoorLinkConfig,
  DoorLinkMode,
  DoorLockState,
  DoorStage
} from '../../main/ets/viewmodel/core/DoorConfirmationTracker.ets';
import { DeviceChangeEvent, DeviceChangeEventType } from '../../main/ets/repository/DomainModels.ets';
import { DeviceAction } from '../../main/ets/common/constants/DeviceConstants.ets';
import { AppErrors } from '../../main/ets/common/types/AppError.ets';
import {
  FakeClock,
  FakeControlCoordinator,
  FakeDeviceQuery,
  FakeI18n,
  FakeLogger,
  FakeTimer,
  GATEWAY_ID,
  ROOM_A,
  executionOf,
  record,
  waitMicrotasks
} from './viewmodel-helpers.mjs';

function setup() {
  const clock = new FakeClock();
  const timer = new FakeTimer(clock);
  const door = record({
    deviceId: 'door-1',
    deviceType: 'door',
    deviceName: 'Door',
    openStatus: false
  });
  const sensor = record({
    deviceId: 'sensor-1',
    deviceType: 'sensor',
    isOnline: true,
    openStatus: false
  });
  const devices = new FakeDeviceQuery([door, sensor]);
  const control = new FakeControlCoordinator();
  const vm = new DoorViewModel(devices, control, new FakeI18n(), clock, timer,
    new FakeLogger());
  return { clock, timer, door, sensor, devices, control, vm, key: door.state.key };
}

test('T15_DoorView_lockWithGatewayMergedReachesSecuredAndCommitted', async () => {
  const h = setup();
  h.control.push(executionOf(record({ deviceId: 'door-1', deviceType: 'door',
    openStatus: false }), DeviceAction.CLOSE, { value: false }));
  await h.vm.load(h.key);
  await h.vm.configureLink(new DoorLinkConfig(DoorLinkMode.GATEWAY_MERGED));
  await h.vm.lock();
  const state = h.vm.getState();
  assert.equal(state.door.stage, DoorStage.SECURED);
  assert.equal(state.door.lockState, DoorLockState.SECURED);
  assert.equal(state.control.phase, 'COMMITTED');
  assert.equal(h.control.calls[0].command.action, DeviceAction.CLOSE);
});

test('T15_DoorView_contactSensorWaitsThenSecuresOnClosedOnlineContact', async () => {
  const h = setup();
  h.control.push(executionOf(record({ deviceId: 'door-1', deviceType: 'door',
    openStatus: false }), DeviceAction.CLOSE, { value: false }));
  await h.vm.load(h.key);
  await h.vm.configureLink(new DoorLinkConfig(DoorLinkMode.CONTACT_SENSOR, h.sensor.state.key));
  await h.vm.lock();
  assert.equal(h.vm.getState().door.stage, DoorStage.WAITING_CONTACT);
  h.vm.onDeviceChanged(new DeviceChangeEvent(DeviceChangeEventType.DEVICE_UPDATED,
    h.sensor.state.key));
  await waitMicrotasks();
  await h.clock.advance(0);
  assert.equal(h.vm.getState().door.stage, DoorStage.SECURED);
});

test('T15_DoorView_unlockReachesOpenWithoutWaitingForContact', async () => {
  const h = setup();
  h.control.push(executionOf(record({ deviceId: 'door-1', deviceType: 'door',
    openStatus: true }), DeviceAction.OPEN, { value: true }));
  await h.vm.load(h.key);
  await h.vm.unlock();
  assert.equal(h.vm.getState().door.stage, DoorStage.OPEN);
  assert.equal(h.vm.getState().control.phase, 'COMMITTED');
});

test('T15_DoorView_ackRejectedRevertsAndNeverClaimsSecured', async () => {
  const h = setup();
  h.control.push(executionOf(h.door, DeviceAction.CLOSE, {
    success: false,
    ackAccepted: false,
    error: AppErrors.of('ACK_PROTOCOL_VIOLATION', [])
  }));
  await h.vm.load(h.key);
  await h.vm.configureLink(new DoorLinkConfig(DoorLinkMode.GATEWAY_MERGED));
  await h.vm.lock();
  const state = h.vm.getState();
  assert.equal(state.door.stage, DoorStage.FAILED);
  assert.notEqual(state.door.stage, DoorStage.SECURED);
  assert.equal(state.control.phase, 'REVERT');
  h.timer.advance(320);
  assert.equal(h.vm.getState().control.phase, 'IDLE');
});
