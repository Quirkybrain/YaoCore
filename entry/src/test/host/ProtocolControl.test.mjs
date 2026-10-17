/*
 * YaoCore C-03 control request serializer host tests.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Traceability: DES-A §6.1.3, §18.1; V-01.
 *
 * HMAC is deliberately NOT implemented by T-06. These tests use the public
 * vector signatures supplied by input/api/protocol/hmac-sha256-test-vectors.json
 * and check the serializer/canonical field set only.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { AppError } from '../../main/ets/common/types/AppError.ets';
import { ControlRequestSerializer } from '../../main/ets/service/protocol/ControlRequestSerializer.ets';
import { Utf8 } from '../../main/ets/common/utils/Utf8.ets';
import { controlCanonical } from './protocol-oracle.ets';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(HERE, '../../../..');
const FIXTURES = path.join(
  REPO_ROOT,
  'entry/src/ohosTest/ets/test/contract/fixtures',
);

const vectorDoc = JSON.parse(
  readFileSync(path.join(FIXTURES, 'hmac-sha256-test-vectors.json'), 'utf8'),
);

const validRequest = (overrides = {}) => ({
  request_id: 'req-1729000000000-7',
  cmd_id: 2001,
  seq: 7,
  target: 'Light_01',
  payload: {
    action: 'SET_BRIGHTNESS',
    value: 42,
  },
  timestamp: '20261017T120000Z',
  nonce: '0123456789abcdef0123456789abcdef',
  alg: 'HMAC-SHA256',
  key_id: 'app-key-v1',
  sign: 'a'.repeat(64),
  ...overrides,
});

const expectCode = (request, code) => {
  assert.throws(() => ControlRequestSerializer.serialize(request), (error) => {
    assert.ok(error instanceof AppError, `expected AppError, got ${error}`);
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
};

test('C03_ControlRequestSerializer_allPublicVectorsMatchSchemaOrder', () => {
  assert.equal(vectorDoc.vectors.length, 4);
  for (const vector of vectorDoc.vectors) {
    const bytes = ControlRequestSerializer.serialize(vector.request);
    const text = Utf8.decode(bytes);
    assert.ok(!text.endsWith('\n'), `${vector.name}: trailing newline`);
    assert.ok(!text.includes(' '), `${vector.name}: compact JSON contains whitespace`);
    const parsed = JSON.parse(text);
    assert.deepEqual(Object.keys(parsed), [
      'request_id', 'cmd_id', 'seq', 'target', 'payload',
      'timestamp', 'nonce', 'alg', 'key_id', 'sign',
    ], vector.name);
    assert.deepEqual(Object.keys(parsed.payload),
      vector.request.payload.value === undefined ? ['action'] : ['action', 'value'],
      vector.name);
    assert.equal(parsed.request_id, vector.request.request_id);
    assert.equal(parsed.cmd_id, 2001);
    assert.equal(parsed.seq, vector.request.seq);
    assert.equal(parsed.target, vector.request.target);
    assert.equal(parsed.payload.action, vector.request.payload.action);
    assert.equal(parsed.sign, vector.expectedSign);
    assert.equal(controlCanonical(vector.request), vector.canonical, vector.name);
  }
});

test('C03_ControlRequestSerializer_roundTripsValueTypes', () => {
  const cases = [
    ['SET_BRIGHTNESS', 68],
    ['SET_MODE', '制冷'],
    ['BOARD_LED_ON', true],
    ['PING', undefined],
  ];
  for (const [action, value] of cases) {
    const request = validRequest({ payload: { action, value } });
    const parsed = JSON.parse(Utf8.decode(ControlRequestSerializer.serialize(request)));
    if (value === undefined) {
      assert.deepEqual(Object.keys(parsed.payload), ['action']);
    } else {
      assert.deepEqual(parsed.payload.value, value);
    }
  }
});

test('C03_ControlRequestSerializer_rejectsFieldViolations', () => {
  expectCode(validRequest({ request_id: 'bad id' }), 'PROTOCOL_INVALID_IDENTIFIER');
  expectCode(validRequest({ request_id: 'r'.repeat(128) }), 'PROTOCOL_INVALID_IDENTIFIER');
  expectCode(validRequest({ cmd_id: 2002 }), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(validRequest({ seq: -1 }), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(validRequest({ seq: 2147483648 }), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(validRequest({ seq: 1.5 }), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(validRequest({ target: 'gw:01' }), 'PROTOCOL_INVALID_IDENTIFIER');
  expectCode(validRequest({ target: 'L'.repeat(64) }), 'PROTOCOL_INVALID_IDENTIFIER');
  expectCode(validRequest({ payload: { action: 'lowercase' } }), 'PROTOCOL_INVALID_IDENTIFIER');
  expectCode(validRequest({ payload: { action: 'A'.repeat(48) } }), 'PROTOCOL_INVALID_IDENTIFIER');
  expectCode(validRequest({ timestamp: '2026-10-17T12:00:00Z' }), 'PROTOCOL_INVALID_TIMESTAMP');
  expectCode(validRequest({ nonce: 'short' }), 'PROTOCOL_INVALID_IDENTIFIER');
  expectCode(validRequest({ nonce: 'bad nonce value' }), 'PROTOCOL_INVALID_IDENTIFIER');
  expectCode(validRequest({ alg: 'HMAC-SHA1' }), 'PROTOCOL_UNSUPPORTED_VERSION');
  expectCode(validRequest({ key_id: 'other-key' }), 'PROTOCOL_UNSUPPORTED_VERSION');
  expectCode(validRequest({ sign: 'A'.repeat(64) }), 'PROTOCOL_INVALID_IDENTIFIER');
  expectCode(validRequest({ sign: 'a'.repeat(63) }), 'PROTOCOL_INVALID_IDENTIFIER');
});

test('C03_ControlRequestSerializer_enforcesOutboundValueBounds', () => {
  expectCode(validRequest({ payload: { action: 'SET_BRIGHTNESS', value: 101 } }),
    'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(validRequest({ payload: { action: 'SET_BRIGHTNESS', value: -1 } }),
    'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(validRequest({ payload: { action: 'SET_TARGET_TEMPERATURE', value: 15 } }),
    'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(validRequest({ payload: { action: 'SET_TARGET_TEMPERATURE', value: 31 } }),
    'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(validRequest({ payload: { action: 'SET_MODE', value: 'M'.repeat(16) } }),
    'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(validRequest({ payload: { action: 'SET_MODE', value: 'X'.repeat(63) } }),
    'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(validRequest({ payload: { action: 'SET_COLOR', value: '#ffffff' } }),
    'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(validRequest({ payload: { action: 'SET_BRIGHTNESS', value: Number.NaN } }),
    'PROTOCOL_INVALID_TYPE');
});

test('C03_ControlRequestSerializer_producesNoTrailingNewlineAndUtf8', () => {
  const request = validRequest({ payload: { action: 'SET_MODE', value: '制冷' } });
  const bytes = ControlRequestSerializer.serialize(request);
  const text = Utf8.decode(bytes);
  assert.ok(text.includes('"制冷"'));
  assert.ok(!text.endsWith('\n'));
  assert.equal(bytes[bytes.length - 1], 0x7d);
});
