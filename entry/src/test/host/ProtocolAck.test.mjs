/*
 * YaoCore C-03 control ACK host tests.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Traceability: DES-A §6.1.4, §18.7; V-05/V-06; SEC-N09/N10/N11/N12/N14.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { AppError } from '../../main/ets/common/types/AppError.ets';
import { DeviceAction } from '../../main/ets/common/constants/DeviceConstants.ets';
import { DeviationCode } from '../../main/ets/common/types/ProtocolDeviation.ets';
import {
  AckExpectation,
  ControlAckMapper,
} from '../../main/ets/service/protocol/ControlAckMapper.ets';
import { DeviationCounter } from '../../main/ets/service/protocol/ProtocolDeviation.ets';
import { StateVerification } from '../../main/ets/model/ControlModels.ets';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(HERE, '../../../..');
const FIXTURES = path.join(
  REPO_ROOT,
  'entry/src/ohosTest/ets/test/contract/fixtures',
);

const encode = (value) => new TextEncoder().encode(JSON.stringify(value));
const golden = (name) => JSON.parse(readFileSync(path.join(FIXTURES, name), 'utf8'));

const expectation = (overrides = {}) => new AckExpectation(
  overrides.requestId ?? 'req-wp002-live-0001',
  overrides.seq ?? 1,
  overrides.target ?? 'Light_01',
  overrides.action ?? DeviceAction.SET_BRIGHTNESS,
  overrides.value ?? 42,
  overrides.alreadyApplied ?? false,
);

const map = (body, exp = expectation()) => {
  const counter = new DeviationCounter();
  const outcome = ControlAckMapper.map(
    typeof body === 'string' ? new TextEncoder().encode(body) : encode(body),
    exp,
    counter,
  );
  return { outcome, counter };
};

const mapError = (body, exp = expectation()) => {
  try {
    map(body, exp);
  } catch (error) {
    assert.ok(error instanceof AppError, `expected AppError, got ${error}`);
    return error;
  }
  assert.fail('expected ACK mapper to throw');
};

const ack = (overrides = {}) => ({
  request_id: 'req-wp002-live-0001',
  seq: 1,
  result_code: 0,
  message: 'command executed by DEV simulator',
  server_time: '20261016T155534Z',
  reported_state: {
    deviceId: 'Light_01',
    online: true,
    power: true,
    brightness: 42,
    updatedAt: '20261016T155534Z',
  },
  ...overrides,
});

test('C03_ControlAckMapper_goldenACKMatchesExpectedCommand', () => {
  const { outcome, counter } = map(golden('control-ack.json'));
  assert.equal(outcome.ackAccepted, true);
  assert.equal(outcome.resultCode, 0);
  assert.equal(outcome.errorCode, undefined);
  assert.equal(outcome.idempotentReplay, false);
  assert.equal(outcome.stateVerification, StateVerification.MATCH);
  assert.equal(outcome.shouldApplyState, true);
  assert.equal(outcome.reportedState.deviceId, 'Light_01');
  assert.equal(outcome.reportedState.brightness, 42);
  assert.equal(outcome.gatewayResult.known, true);
  assert.equal(outcome.gatewayResult.success, true);
  assert.equal(outcome.gatewayResult.stableName, 'success');
  assert.equal(counter.total(), 0);
  assert.equal(outcome.message, undefined);
});

test('C03_ControlAckMapper_replayDoesNotDuplicateAlreadyAppliedState', () => {
  const notApplied = map(golden('control-ack-replay.json'), expectation({ alreadyApplied: false }));
  assert.equal(notApplied.outcome.ackAccepted, true);
  assert.equal(notApplied.outcome.idempotentReplay, true);
  assert.equal(notApplied.outcome.shouldApplyState, true);

  const applied = map(golden('control-ack-replay.json'), expectation({ alreadyApplied: true }));
  assert.equal(applied.outcome.ackAccepted, true);
  assert.equal(applied.outcome.idempotentReplay, true);
  assert.equal(applied.outcome.shouldApplyState, false);
});

test('C03_ControlAckMapper_correlationMismatchFailsClosed', () => {
  assert.equal(mapError(ack({ request_id: 'req-other' })).code, 'ACK_CORRELATION_MISMATCH');
  assert.equal(mapError(ack({ seq: 2 })).code, 'ACK_CORRELATION_MISMATCH');
});

test('C03_ControlAckMapper_nonZeroResultNeverClaimsSuccess', () => {
  for (const resultCode of [1004, 1005, 1006, 1007, 1008, 9999]) {
    const { outcome } = map(ack({ result_code: resultCode, reported_state: undefined }));
    assert.equal(outcome.ackAccepted, false, `result ${resultCode}`);
    assert.equal(outcome.shouldApplyState, false, `result ${resultCode}`);
    assert.equal(outcome.stateVerification, StateVerification.UNVERIFIED, `result ${resultCode}`);
    assert.equal(outcome.gatewayResult.success, false, `result ${resultCode}`);
    assert.equal(outcome.resultCode, resultCode);
  }
  const unknown = map(ack({ result_code: 9999, reported_state: undefined })).outcome;
  assert.equal(unknown.gatewayResult.known, false);
  assert.equal(unknown.gatewayResult.stableName, 'unknown_9999');
  const offline = map(ack({ result_code: 1007, reported_state: undefined })).outcome;
  assert.equal(offline.gatewayResult.retryable, true);
});

test('C03_ControlAckMapper_zeroWithoutReportedStateIsProtocolViolation', () => {
  const error = mapError(ack({ reported_state: undefined }));
  assert.equal(error.code, 'ACK_PROTOCOL_VIOLATION');
});

test('C03_ControlAckMapper_reportedStateMustHaveExactlyOneShape', () => {
  const both = ack({
    reported_state: {
      deviceId: 'Light_01',
      gatewayId: 'gw_01',
      online: true,
      boardLed: true,
      updatedAt: '20261016T155534Z',
    },
  });
  assert.equal(mapError(both).code, 'ACK_PROTOCOL_VIOLATION');
  const neither = ack({
    reported_state: {
      online: true,
      updatedAt: '20261016T155534Z',
    },
  });
  assert.equal(mapError(neither).code, 'ACK_PROTOCOL_VIOLATION');
});

test('C03_ControlAckMapper_targetMismatchThrowsStateMismatch', () => {
  const body = ack({
    reported_state: {
      deviceId: 'Other_01',
      online: true,
      brightness: 42,
      updatedAt: '20261016T155534Z',
    },
  });
  assert.equal(mapError(body).code, 'ACK_STATE_MISMATCH');
});

test('C03_ControlAckMapper_stateVerificationDistinguishesMatchMismatchUnverified', () => {
  assert.equal(map(ack()).outcome.stateVerification, StateVerification.MATCH);
  const mismatch = map(ack({
    reported_state: {
      deviceId: 'Light_01',
      online: true,
      brightness: 50,
      updatedAt: '20261016T155534Z',
    },
  })).outcome;
  assert.equal(mismatch.ackAccepted, true);
  assert.equal(mismatch.stateVerification, StateVerification.MISMATCH);

  const unverified = map(ack({
    reported_state: {
      deviceId: 'Light_01',
      online: true,
      updatedAt: '20261016T155534Z',
    },
  })).outcome;
  assert.equal(unverified.ackAccepted, true);
  assert.equal(unverified.stateVerification, StateVerification.UNVERIFIED);
});

test('C03_ControlAckMapper_gatewayBoardStateIsComparedAndApplied', () => {
  const exp = new AckExpectation('req-led', 2, 'gw_01', DeviceAction.BOARD_LED_ON, undefined, false);
  const { outcome } = map(ack({
    request_id: 'req-led',
    seq: 2,
    reported_state: {
      gatewayId: 'gw_01',
      online: true,
      boardLed: true,
      updatedAt: '20261016T155534Z',
    },
  }), exp);
  assert.equal(outcome.ackAccepted, true);
  assert.equal(outcome.stateVerification, StateVerification.MATCH);
  assert.equal(outcome.gatewayBoardState.boardLed, true);
  assert.equal(outcome.shouldApplyState, true);
});

test('C03_ControlAckMapper_successFieldIsAlwaysIgnoredAndCounted', () => {
  const body = ack({
    success: true,
    reported_state: {
      deviceId: 'Light_01',
      online: true,
      brightness: 42,
      success: true,
      updatedAt: '20261016T155534Z',
    },
  });
  const { outcome, counter } = map(body);
  assert.equal(outcome.ackAccepted, true);
  assert.equal(outcome.stateVerification, StateVerification.MATCH);
  assert.equal(counter.counts().get(DeviationCode.SUCCESS_FIELD_IGNORED), 2);
});

test('C03_ControlAckMapper_errorCodeOnSuccessIsDiagnosticOnly', () => {
  const { outcome, counter } = map(ack({ error_code: 'legacy_warning' }));
  assert.equal(outcome.ackAccepted, true);
  assert.equal(outcome.gatewayResult.success, true);
  assert.equal(counter.counts().get(DeviationCode.ERROR_CODE_ON_SUCCESS), 1);
});

test('C03_ControlAckMapper_rejectsUnknownFieldsAndInvalidTypes', () => {
  assert.equal(mapError(ack({ unexpected: true })).code, 'PROTOCOL_UNKNOWN_FIELD');
  assert.equal(mapError(ack({ message: '' })).code, 'ACK_PROTOCOL_VIOLATION');
  assert.equal(mapError(ack({ server_time: '2026-10-16T15:55:34Z' })).code,
    'PROTOCOL_INVALID_TIMESTAMP');
  assert.equal(mapError(ack({ idempotent_replay: 'true' })).code, 'ACK_PROTOCOL_VIOLATION');
  assert.equal(mapError(ack({ reported_state: {
    deviceId: 'Light_01',
    online: true,
    brightness: '42',
    updatedAt: '20261016T155534Z',
  } })).code, 'ACK_PROTOCOL_VIOLATION');
});

test('C03_ControlAckMapper_nonStandardModeIsUnverifiedNotSuccess', () => {
  const exp = new AckExpectation('req-mode', 3, 'AC_01', DeviceAction.SET_MODE, 'COOL', false);
  const { outcome, counter } = map(ack({
    request_id: 'req-mode',
    seq: 3,
    reported_state: {
      deviceId: 'AC_01',
      online: true,
      mode: 'TURBO',
      updatedAt: '20261016T155534Z',
    },
  }), exp);
  assert.equal(outcome.ackAccepted, true);
  assert.equal(outcome.stateVerification, StateVerification.UNVERIFIED);
  assert.equal(counter.counts().get(DeviationCode.NON_STANDARD_AC_MODE), 1);
});

test('C03_ControlAckMapper_lowercaseColorIsNormalizedForComparison', () => {
  const exp = new AckExpectation('req-color', 4, 'Light_01', DeviceAction.SET_COLOR, '#AABBCC', false);
  const { outcome, counter } = map(ack({
    request_id: 'req-color',
    seq: 4,
    reported_state: {
      deviceId: 'Light_01',
      online: true,
      color: '#aabbcc',
      updatedAt: '20261016T155534Z',
    },
  }), exp);
  assert.equal(outcome.stateVerification, StateVerification.MATCH);
  assert.equal(outcome.reportedState.color, '#AABBCC');
  assert.equal(counter.counts().get(DeviationCode.LOWERCASE_COLOR_NORMALIZED), 1);
});
