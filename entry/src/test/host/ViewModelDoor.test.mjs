/*
 * YaoCore T-15 DoorConfirmationTracker host tests.
 * Producer: agent:implementation-engineer | Task: T-15 / wp-060-vm
 * Contract: DES-B §10.1.7, §10.3.3; ADR-004 §6; D-016.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DoorConfirmationPolicy,
  DoorConfirmationTracker,
  DoorLinkConfig,
  DoorLinkMode,
  DoorLockState,
  DoorStage
} from '../../main/ets/viewmodel/core/DoorConfirmationTracker.ets';
import { DeviceKey } from '../../main/ets/model/DeviceKey.ets';
import {
  FakeClock,
  FakeTimer,
  GATEWAY_ID,
  record
} from './viewmodel-helpers.mjs';

const SENSOR = new DeviceKey(GATEWAY_ID, 'sensor-1');
const CONTACT = new DoorLinkConfig(DoorLinkMode.CONTACT_SENSOR, SENSOR);
const MERGED = new DoorLinkConfig(DoorLinkMode.GATEWAY_MERGED);
const NONE = DoorLinkConfig.none();

function tracker() {
  const clock = new FakeClock();
  const timer = new FakeTimer(clock);
  const value = new DoorConfirmationTracker(clock, timer,
    DoorConfirmationPolicy.defaults());
  return { clock, timer, tracker: value };
}

function execution(open, options = {}) {
  if (options.ackAccepted === false) {
    return {
      ackAccepted: false,
      stateVerification: 'UNVERIFIED',
      apply: undefined,
      error: options.error
    };
  }
  return {
    ackAccepted: true,
    stateVerification: options.verification === undefined ? 'MATCH' : options.verification,
    apply: { stateVerification: 'MATCH', record: record({ openStatus: open }) },
    error: options.error
  };
}

test('T15_Door_gatewayMergedReachesSecured', () => {
  const h = tracker();
  h.tracker.startLock(MERGED);
  assert.equal(h.tracker.getState().stage, DoorStage.PENDING);
  h.tracker.onResult(execution(false));
  assert.equal(h.tracker.getState().stage, DoorStage.SECURED);
  assert.equal(h.tracker.getState().lockState, DoorLockState.SECURED);
  assert.equal(h.tracker.getState().alertActive, false);
});

test('T15_Door_contactSensorClosedOnlineReachesSecured', () => {
  const h = tracker();
  h.tracker.startLock(CONTACT);
  h.tracker.onResult(execution(false));
  assert.equal(h.tracker.getState().stage, DoorStage.WAITING_CONTACT);
  h.tracker.onContactState(false, true);
  assert.equal(h.tracker.getState().stage, DoorStage.SECURED);
  assert.equal(h.timer.pending(), 0);
});

test('T15_Door_contactTimeoutOnlineIsUnconfirmedNotUnlocked', () => {
  const h = tracker();
  h.tracker.startLock(CONTACT);
  h.tracker.onResult(execution(false));
  h.timer.advance(9999);
  assert.equal(h.tracker.getState().stage, DoorStage.WAITING_CONTACT);
  h.timer.advance(1);
  assert.equal(h.tracker.getState().stage, DoorStage.UNCONFIRMED);
  assert.equal(h.tracker.getState().alertActive, true);
  assert.equal(h.tracker.getState().lockState, DoorLockState.UNCONFIRMED);
});

test('T15_Door_contactTimeoutOfflineIsUnknown', () => {
  const h = tracker();
  h.tracker.startLock(CONTACT);
  h.tracker.onResult(execution(false));
  h.tracker.onContactOffline();
  h.timer.advance(10000);
  assert.equal(h.tracker.getState().stage, DoorStage.UNKNOWN);
  assert.equal(h.tracker.getState().alertActive, true);
});

test('T15_Door_noLinkIsAlwaysUnverified', () => {
  const h = tracker();
  h.tracker.startLock(NONE);
  h.tracker.onResult(execution(false));
  assert.equal(h.tracker.getState().stage, DoorStage.UNVERIFIED);
  assert.equal(h.tracker.getState().lockState, DoorLockState.UNKNOWN);
});

test('T15_Door_contactOpenDuringWaitRaisesAlertAndNeverSecures', () => {
  const h = tracker();
  h.tracker.startLock(CONTACT);
  h.tracker.onResult(execution(false));
  h.tracker.onContactState(true, true);
  assert.equal(h.tracker.getState().stage, DoorStage.UNCONFIRMED);
  assert.equal(h.tracker.getState().alertActive, true);
  h.tracker.onContactState(false, true);
  assert.equal(h.tracker.getState().stage, DoorStage.UNCONFIRMED);
});

test('T15_Door_openAfterSecuredDropsToOpenWithAlert', () => {
  const h = tracker();
  h.tracker.startLock(MERGED);
  h.tracker.onResult(execution(false));
  assert.equal(h.tracker.getState().stage, DoorStage.SECURED);
  h.tracker.onContactState(true, true);
  assert.equal(h.tracker.getState().stage, DoorStage.OPEN);
  assert.equal(h.tracker.getState().alertActive, true);
});

test('T15_Door_ackRejectedOrMissingReportedStateNeverSecures', () => {
  const rejected = tracker();
  rejected.tracker.startLock(MERGED);
  rejected.tracker.onResult(execution(false, { ackAccepted: false }));
  assert.equal(rejected.tracker.getState().stage, DoorStage.FAILED);

  const unverified = tracker();
  unverified.tracker.startLock(MERGED);
  unverified.tracker.onResult(execution(undefined));
  assert.equal(unverified.tracker.getState().stage, DoorStage.UNVERIFIED);
});

test('T15_Door_dismissAlertReturnsToIdleKeepingEvidence', () => {
  const h = tracker();
  h.tracker.startLock(CONTACT);
  h.tracker.onResult(execution(false));
  h.timer.advance(10000);
  assert.equal(h.tracker.getState().stage, DoorStage.UNCONFIRMED);
  h.tracker.dismissAlert();
  assert.equal(h.tracker.getState().stage, DoorStage.IDLE);
  assert.equal(h.tracker.getState().alertActive, false);
  assert.equal(h.tracker.getState().lockState, DoorLockState.UNCONFIRMED);
});
