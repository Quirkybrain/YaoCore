/*
 * YaoCore T-15 DeviceControlCoordinator host tests.
 * Producer: agent:implementation-engineer | Task: T-15 / wp-060-vm
 * Contract: DES-B §10.1.5; CB §2.3; ADR-001 §2.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { DeviceControlCoordinator } from '../../main/ets/viewmodel/core/DeviceControlCoordinator.ets';
import { DeviceControlCommand } from '../../main/ets/model/ControlModels.ets';
import { AppErrors } from '../../main/ets/common/types/AppError.ets';
import { DeviceAction } from '../../main/ets/common/constants/DeviceConstants.ets';
import {
  FakeClock,
  FakeLogger,
  GATEWAY_ID,
  T0,
  record
} from './viewmodel-helpers.mjs';

class FakeLan {
  constructor(execution) { this.execution = execution; this.calls = 0; }
  async run() { this.calls++; return this.execution; }
}

class FakeCloud {
  constructor(state, outcome) {
    this.state = state;
    this.outcome = outcome;
    this.sendCalls = 0;
  }
  async getState() { return { state: this.state, config: undefined, tokenPresent: true }; }
  async sendAndConfirm() { this.sendCalls++; return this.outcome; }
}

class FakeApply {
  constructor(recordValue) { this.record = recordValue; this.calls = []; }
  async applyCloudState(context, reported, verification, requestId, seq, accepted) {
    this.calls.push({ context, reported, verification, requestId, seq, accepted });
    return {
      ackAccepted: accepted,
      stateApplied: reported !== undefined,
      stateVerification: verification,
      reason: 'APPLIED',
      record: this.record
    };
  }
}

function command() {
  return new DeviceControlCommand(GATEWAY_ID, 'dev-1', DeviceAction.TURN_ON, T0, true);
}

function lanFailure(code) {
  return { ackAccepted: false, apply: undefined, error: AppErrors.of(code, []) };
}

function setup(lanExecution, cloudState = 'CONFIGURED', cloudOutcome = undefined) {
  const clock = new FakeClock();
  const light = record({ powerStatus: false });
  const lan = new FakeLan(lanExecution);
  const cloud = new FakeCloud(cloudState, cloudOutcome);
  const apply = new FakeApply(record({ powerStatus: true }));
  const coordinator = new DeviceControlCoordinator(lan, cloud, apply, clock, new FakeLogger());
  return { clock, light, lan, cloud, apply, coordinator };
}

const confirmedOutcome = {
  executionAccepted: true,
  receipt: { requestId: 'req-1', seq: 7 },
  verdict: { stateVerification: 'MATCH', reportedState: { powerStatus: true } },
  error: undefined
};

test('T15_Coordinator_lanSuccessNeverFallsBackToCloud', async () => {
  const h = setup({ ackAccepted: true, apply: { stateVerification: 'MATCH' }, error: undefined });
  const execution = await h.coordinator.execute(command(), 'family-1');
  assert.equal(execution.transport, 'LAN');
  assert.equal(execution.ackAccepted, true);
  assert.equal(h.cloud.sendCalls, 0);
  assert.equal(h.apply.calls.length, 0);
});

test('T15_Coordinator_lanUnreachableWithConfiguredCloudFallsBackAndApplies', async () => {
  const h = setup(lanFailure('GATEWAY_UNREACHABLE'), 'CONFIGURED', confirmedOutcome);
  const execution = await h.coordinator.execute(command(), 'family-1');
  assert.equal(execution.transport, 'CLOUD');
  assert.equal(execution.ackAccepted, true);
  assert.equal(h.cloud.sendCalls, 1);
  assert.equal(h.apply.calls.length, 1);
  assert.equal(h.apply.calls[0].requestId, 'req-1');
  assert.equal(h.apply.calls[0].seq, 7);
});

test('T15_Coordinator_deviceOfflineDoesNotFallBack', async () => {
  const h = setup(lanFailure('DEVICE_OFFLINE'), 'CONFIGURED', confirmedOutcome);
  const execution = await h.coordinator.execute(command(), 'family-1');
  assert.equal(execution.transport, 'LAN');
  assert.equal(h.cloud.sendCalls, 0);
});

test('T15_Coordinator_tlsOrProfileErrorsDoNotFallBack', async () => {
  const h = setup(lanFailure('TLS_PIN_MISMATCH'), 'CONFIGURED', confirmedOutcome);
  const execution = await h.coordinator.execute(command(), 'family-1');
  assert.equal(execution.transport, 'LAN');
  assert.equal(h.cloud.sendCalls, 0);
});

test('T15_Coordinator_cloudNotConfiguredKeepsLanError', async () => {
  const h = setup(lanFailure('GATEWAY_TIMEOUT'), 'NOT_CONFIGURED', confirmedOutcome);
  const execution = await h.coordinator.execute(command(), 'family-1');
  assert.equal(execution.transport, 'LAN');
  assert.equal(execution.error.code, 'GATEWAY_TIMEOUT');
  assert.equal(h.cloud.sendCalls, 0);
});

test('T15_Coordinator_cloudTokenExpiredDoesNotFallBack', async () => {
  const h = setup(lanFailure('GATEWAY_TIMEOUT'), 'TOKEN_EXPIRED', confirmedOutcome);
  const execution = await h.coordinator.execute(command(), 'family-1');
  assert.equal(execution.transport, 'LAN');
  assert.equal(h.cloud.sendCalls, 0);
});

test('T15_Coordinator_cloudUnsupportedDoesNotApplyStateOrClaimSuccess', async () => {
  const unsupported = {
    executionAccepted: false,
    receipt: { requestId: 'req-1', seq: 7 },
    verdict: { stateVerification: 'UNVERIFIED', reportedState: undefined },
    error: AppErrors.of('CLOUD_COMPLETION_UNSUPPORTED', [])
  };
  const h = setup(lanFailure('LOCAL_REQUEST_FAILED'), 'CONFIGURED', unsupported);
  const execution = await h.coordinator.execute(command(), 'family-1');
  assert.equal(execution.transport, 'CLOUD');
  assert.equal(execution.ackAccepted, false);
  assert.equal(h.apply.calls.length, 0);
  assert.equal(DeviceControlCoordinator.succeeded(execution), false);
});
