/*
 * YaoCore C-05 SecurityService host tests.
 * Producer: agent:implementation-engineer | Task: T-07 / wp-016-security
 * Traceability: DES-A §8.1-§8.5, §18; CB §2.5/§3/§4; V-01/V-02/V-03.
 *
 * PUBLIC TEST DATA ONLY. Product C-05 runs over the independent pure-TS
 * TestCryptoProvider; Node crypto recomputes every HMAC/SHA vector.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { AppError } from '../../main/ets/common/types/AppError.ets';
import { HttpHeaders } from '../../main/ets/common/types/HttpHeaders.ets';
import { NameValue } from '../../main/ets/common/types/NameValue.ets';
import { ProtocolConstants } from '../../main/ets/common/constants/ProtocolConstants.ets';
import { DeviceAction } from '../../main/ets/common/constants/DeviceConstants.ets';
import { DateTimeUtil } from '../../main/ets/common/utils/DateTimeUtil.ets';
import { CryptoService } from '../../main/ets/service/crypto/CryptoService.ets';
import {
  CanonicalBuilder,
  CloudCanonicalFields,
  ControlCanonicalFields,
  DiscoverCanonicalFields,
  ResponseKind,
} from '../../main/ets/service/security/CanonicalBuilder.ets';
import {
  DiscoverSigningInput,
  RequestSigner,
  SigningInput,
} from '../../main/ets/service/security/RequestSigner.ets';
import {
  ExpectedResponse,
  ResponseVerifier,
} from '../../main/ets/service/security/ResponseVerifier.ets';
import { NonceCache, NonceDecision } from '../../main/ets/service/security/NonceCache.ets';
import { ClockSkewTracker } from '../../main/ets/service/security/ClockSkewTracker.ets';
import { TestCryptoProvider } from './TestCryptoProvider.ets';
import { valueAtom } from './protocol-oracle.ets';
import {
  AckExpectation,
  ControlAckMapper,
} from '../../main/ets/service/protocol/ControlAckMapper.ets';
import { DeviationCounter } from '../../main/ets/service/protocol/ProtocolDeviation.ets';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(HERE, '../../../..');
const FIXTURES = path.join(REPO_ROOT, 'entry/src/ohosTest/ets/test/contract/fixtures');

const readJson = (name) => JSON.parse(readFileSync(path.join(FIXTURES, name), 'utf8'));
const utf8 = (text) => new TextEncoder().encode(text);
const hex = (bytes) => Buffer.from(bytes).toString('hex');
const hmacHex = (secret, text) =>
  createHmac('sha256', secret).update(text, 'utf8').digest('hex');
const sha256Hex = (data) => createHash('sha256').update(data).digest('hex');

const expectCode = async (fn, code) => {
  await assert.rejects(fn, (error) => {
    assert.ok(error instanceof AppError, `expected AppError, got ${error}`);
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
};
const expectSyncCode = (fn, code) => {
  assert.throws(fn, (error) => {
    assert.ok(error instanceof AppError, `expected AppError, got ${error}`);
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
};

class FakeClock {
  constructor(nowMs) {
    this.value = nowMs;
  }

  nowMs() {
    return this.value;
  }
}

class FakeRandom {
  constructor(byteFactory) {
    this.byteFactory = byteFactory;
    this.calls = 0;
  }

  async nextBytes(length) {
    this.calls += 1;
    return this.byteFactory(length, this.calls);
  }
}

const cryptoService = new CryptoService(new TestCryptoProvider());
const verifier = new ResponseVerifier(cryptoService);

const FIXED_MS = Date.UTC(2026, 6, 14, 8, 0, 0); // 20260714T080000Z
const SECRET = utf8('0123456789abcdef'); // public test data

// V-01 vectors: fixture nonce is 12 lowercase hex (legacy fixture). The
// canonical/HMAC oracle below uses the fixture value verbatim; RequestSigner
// generation is separately asserted to be 32 lowercase hex (DES-A §3.3).
test('C05_CanonicalBuilder_reproducesAllFourV01CanonicalAndHmacVectors', async () => {
  const document = readJson('hmac-sha256-test-vectors.json');
  assert.equal(document.vectors.length, 4);
  for (const vector of document.vectors) {
    const request = vector.request;
    const fields = new ControlCanonicalFields(
      request.request_id,
      request.cmd_id,
      request.seq,
      request.target,
      request.payload.action,
      valueAtom(request.payload.value),
      request.timestamp,
      request.nonce,
      request.alg,
      request.key_id,
    );
    const canonical = CanonicalBuilder.control(fields);
    assert.equal(canonical, vector.canonical, vector.name);
    assert.equal(canonical.split('\n').length, 10, vector.name);
    assert.ok(!canonical.endsWith('\n'), vector.name);
    const mac = await cryptoService.hmacSha256(utf8(vector.secret), utf8(canonical));
    assert.equal(hex(mac), vector.expectedSign, vector.name);
    assert.equal(hmacHex(vector.secret, canonical), vector.expectedSign, vector.name);
    assert.equal(request.sign, vector.expectedSign, vector.name);
  }
  assert.equal(document.vectors[0].request.nonce.length, 12);
});

test('C05_CanonicalBuilder_reproducesDiscoveryRequestVector', async () => {
  const document = readJson('discovery-request-auth-test-vectors.json');
  assert.equal(document.vectors.length, 1);
  for (const vector of document.vectors) {
    const fields = new DiscoverCanonicalFields(
      vector.challenge,
      vector.timestamp,
      vector.nonce,
      vector.alg,
      vector.key_id,
    );
    const canonical = CanonicalBuilder.discover(fields);
    assert.equal(canonical, vector.canonical.replaceAll('\\n', '\n'), vector.name);
    assert.equal(canonical.split('\n').length, 6, vector.name);
    assert.equal(canonical.split('\n')[0], 'YAOCORE-DISCOVER-V2');
    assert.equal(hex(await cryptoService.hmacSha256(utf8(vector.secret), utf8(canonical))),
      vector.signature, vector.name);
    assert.equal(hmacHex(vector.secret, canonical), vector.signature, vector.name);
  }
});

test('C05_ResponseVerifier_acceptsResponseAuthVectorAndComputesBodySha', async () => {
  const document = readJson('response-auth-test-vectors.json');
  assert.equal(document.vectors.length, 1);
  for (const vector of document.vectors) {
    const headers = HttpHeaders.from([
      new NameValue('X-YaoCore-Response-Alg', 'HMAC-SHA256'),
      new NameValue('X-YaoCore-Key-Id', 'app-key-v1'),
      new NameValue('X-YaoCore-Response-Correlation', vector.correlation),
      new NameValue('X-YaoCore-Response-Sign', vector.signature),
    ]);
    const verified = await verifier.verify(
      headers,
      utf8(vector.body),
      ExpectedResponse.forDiscover(vector.correlation),
      utf8(vector.secret),
    );
    assert.equal(verified.kind, ResponseKind.DISCOVER);
    assert.equal(verified.correlation, vector.correlation);
    assert.equal(verified.bodySha256Hex, vector.bodySha256);
    assert.equal(sha256Hex(Buffer.from(vector.body, 'utf8')), vector.bodySha256);
    assert.equal(verified.bodySha256Hex, vector.bodySha256);
  }
});

test('C05_ResponseVerifier_headerLookupIsCaseInsensitiveAndTimeAgnostic', async () => {
  const vector = readJson('response-auth-test-vectors.json').vectors[0];
  const headers = HttpHeaders.from([
    new NameValue('x-yaocore-response-alg', 'HMAC-SHA256'),
    new NameValue('X-YAOCORE-KEY-ID', 'app-key-v1'),
    new NameValue('x-YaoCore-Response-Correlation', vector.correlation),
    new NameValue('X-YaoCore-Response-Sign', vector.signature),
    // Response authentication never consults a timestamp; server_time is
    // informational (CB §2.5).
    new NameValue('X-YaoCore-Response-Timestamp', '19990101T000000Z'),
  ]);
  const verified = await verifier.verify(headers, utf8(vector.body),
    ExpectedResponse.forDiscover(vector.correlation), utf8(vector.secret));
  assert.equal(verified.bodySha256Hex, vector.bodySha256);
});

test('C05_ResponseVerifier_negativePathsUseContractErrorCodes', async () => {
  const vector = readJson('response-auth-test-vectors.json').vectors[0];
  const body = utf8(vector.body);
  const expected = ExpectedResponse.forDiscover(vector.correlation);
  const secret = utf8(vector.secret);
  const makeHeaders = (overrides = {}) => HttpHeaders.from([
    new NameValue('X-YaoCore-Response-Alg', overrides.alg ?? 'HMAC-SHA256'),
    new NameValue('X-YaoCore-Key-Id', overrides.keyId ?? 'app-key-v1'),
    ...(overrides.correlation === null ? [] : [
      new NameValue('X-YaoCore-Response-Correlation',
        overrides.correlation ?? vector.correlation),
    ]),
    ...(overrides.sign === null ? [] : [
      new NameValue('X-YaoCore-Response-Sign', overrides.sign ?? vector.signature),
    ]),
  ]);

  await expectCode(() => verifier.verify(makeHeaders({ alg: 'HMAC-SHA1' }), body, expected, secret),
    'RESPONSE_AUTH_FAILED');
  await expectCode(() => verifier.verify(makeHeaders({ keyId: 'app-key-v2' }), body, expected, secret),
    'RESPONSE_AUTH_FAILED');
  await expectCode(() => verifier.verify(makeHeaders({ correlation: null }), body, expected, secret),
    'RESPONSE_AUTH_FAILED');
  await expectCode(() => verifier.verify(makeHeaders({
    correlation: 'ffeeddccbbaa99887766554433221100',
  }), body, expected, secret), 'RESPONSE_CORRELATION_MISMATCH');
  await expectCode(() => verifier.verify(makeHeaders({ sign: null }), body, expected, secret),
    'RESPONSE_AUTH_FAILED');
  await expectCode(() => verifier.verify(makeHeaders({ sign: vector.signature.toUpperCase() }),
    body, expected, secret), 'RESPONSE_AUTH_FAILED');
  await expectCode(() => verifier.verify(makeHeaders({ sign: vector.signature.slice(0, 63) }),
    body, expected, secret), 'RESPONSE_AUTH_FAILED');
  const flipped = `${vector.signature.slice(0, 63)}` +
    `${vector.signature[63] === '0' ? '1' : '0'}`;
  await expectCode(() => verifier.verify(makeHeaders({ sign: flipped }), body, expected, secret),
    'RESPONSE_AUTH_FAILED');
  await expectCode(() => verifier.verify(makeHeaders(), body, expected, utf8('short')),
    'CRYPTO_INVALID_KEY');
  // Body tampering changes the SHA-256 canonical input.
  await expectCode(() => verifier.verify(makeHeaders(), utf8(`${vector.body} `), expected, secret),
    'RESPONSE_AUTH_FAILED');
});

test('C05_ExpectedResponse_controlCorrelationIsRequestIdColonSeq', () => {
  assert.equal(ExpectedResponse.forControl('req-1729000000123-7', 7).correlation,
    'req-1729000000123-7:7');
  assert.equal(ExpectedResponse.forControl('req-1729000000123-0', 0).correlation,
    'req-1729000000123-0:0');
  expectSyncCode(() => ExpectedResponse.forControl('bad id', 1), 'PROTOCOL_INVALID_IDENTIFIER');
  expectSyncCode(() => ExpectedResponse.forControl('req-1729000000123-7', -1),
    'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectSyncCode(() => ExpectedResponse.forControl('req-1729000000123-7', 1.5),
    'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectSyncCode(() => ExpectedResponse.forDiscover('ABCDEF0123456789ABCDEF0123456789'),
    'PROTOCOL_INVALID_IDENTIFIER');
});

test('C05_RequestSigner_signControlUsesOneClockSnapshotAndContractNonce', async () => {
  const clock = new FakeClock(FIXED_MS);
  const random = new FakeRandom((length) => new Uint8Array(length).fill(0xab));
  const nonces = new NonceCache(clock);
  const signer = new RequestSigner(cryptoService, clock, random, nonces);
  const signed = await signer.signControl(
    new SigningInput('gateway_01', 'Light_01', DeviceAction.SET_BRIGHTNESS, 68),
    SECRET,
    10086,
  );
  assert.equal(signed.timestamp, '20260714T080000Z');
  assert.equal(signed.requestId, `req-${FIXED_MS}-10086`);
  assert.match(signed.nonce, /^[0-9a-f]{32}$/);
  assert.equal(signed.nonce, 'ab'.repeat(16));
  assert.equal(signed.canonical,
    `req-${FIXED_MS}-10086\n2001\n10086\nLight_01\nSET_BRIGHTNESS\n68\n` +
    '20260714T080000Z\n' + 'ab'.repeat(16) + '\nHMAC-SHA256\napp-key-v1');
  assert.equal(signed.canonical.split('\n').length, 10);
  assert.equal(signed.sign, hmacHex('0123456789abcdef', signed.canonical));
  assert.equal(signed.sign.length, 64);
  assert.equal(nonces.contains('app-key-v1', signed.nonce, FIXED_MS), true);
});

test('C05_RequestSigner_encodesEveryValueKindAndAbsentValue', async () => {
  const cases = [
    [68, '68', DeviceAction.SET_BRIGHTNESS, true],
    ['制冷', '"制冷"', DeviceAction.SET_MODE, true],
    [true, 'true', DeviceAction.BOARD_LED_ON, true],
    [undefined, '', DeviceAction.PING, false],
  ];
  for (const [value, expectedLine, action, hasValue] of cases) {
    const clock = new FakeClock(FIXED_MS);
    const signer = new RequestSigner(cryptoService, clock,
      new FakeRandom((length) => new Uint8Array(length).fill(0x11)),
      new NonceCache(clock));
    const input = hasValue ?
      new SigningInput('gateway_01', 'AC_01', action, value) :
      new SigningInput('gateway_01', 'gateway_01', action);
    const signed = await signer.signControl(input, SECRET, 3);
    const lines = signed.canonical.split('\n');
    assert.equal(lines.length, 10);
    assert.equal(lines[5], expectedLine);
    assert.equal(signed.valueText, expectedLine);
  }
});

test('C05_RequestSigner_signDiscoverUsesIndependent32HexChallengeAndNonce', async () => {
  const clock = new FakeClock(FIXED_MS);
  let counter = 0;
  const random = new FakeRandom((length) => new Uint8Array(length).fill(counter++));
  const nonces = new NonceCache(clock);
  const signer = new RequestSigner(cryptoService, clock, random, nonces);
  const signed = await signer.signDiscover(new DiscoverSigningInput('gateway_01'), SECRET);
  assert.match(signed.challenge, /^[0-9a-f]{32}$/);
  assert.match(signed.nonce, /^[0-9a-f]{32}$/);
  assert.notEqual(signed.challenge, signed.nonce);
  assert.equal(signed.canonical.split('\n').length, 6);
  assert.equal(signed.canonical.split('\n')[0], 'YAOCORE-DISCOVER-V2');
  const headers = signed.headers;
  assert.equal(headers.get('X-YaoCore-Challenge'), signed.challenge);
  assert.equal(headers.get('x-yaocore-request-nonce'), signed.nonce);
  assert.equal(headers.get('X-YaoCore-Request-Timestamp'), '20260714T080000Z');
  assert.equal(headers.get('X-YaoCore-Request-Alg'), 'HMAC-SHA256');
  assert.equal(headers.get('X-YaoCore-Key-Id'), 'app-key-v1');
  assert.equal(headers.get('X-YaoCore-Request-Sign'),
    hmacHex('0123456789abcdef', signed.canonical));
  assert.equal(nonces.contains('app-key-v1', signed.nonce, FIXED_MS), true);
});

test('C05_RequestSigner_rejectsRepeatedNonceAndBadSecrets', async () => {
  const clock = new FakeClock(FIXED_MS);
  const duplicateNonce = '07'.repeat(16);
  const nonces = new NonceCache(clock);
  assert.equal(nonces.checkAndRemember('app-key-v1', duplicateNonce, FIXED_MS),
    NonceDecision.NEW);
  const signer = new RequestSigner(cryptoService, clock,
    new FakeRandom((length) => new Uint8Array(length).fill(7)), nonces);
  await expectCode(() => signer.signControl(
    new SigningInput('gateway_01', 'Light_01', DeviceAction.SET_BRIGHTNESS, 10),
    SECRET, 1), 'INTERNAL_ERROR');

  const badRandom = new RequestSigner(cryptoService, clock, {
    nextBytes: async () => {
      throw new Error('entropy failed');
    },
  }, new NonceCache(clock));
  await expectCode(() => badRandom.signControl(
    new SigningInput('gateway_01', 'Light_01', DeviceAction.SET_BRIGHTNESS, 10),
    SECRET, 1), 'CRYPTO_OPERATION_FAILED');

  const fresh = new RequestSigner(cryptoService, clock,
    new FakeRandom((length) => new Uint8Array(length).fill(2)), new NonceCache(clock));
  await expectCode(() => fresh.signControl(
    new SigningInput('gateway_01', 'Light_01', DeviceAction.SET_BRIGHTNESS, 10),
    utf8('short'), 1), 'CRYPTO_INVALID_KEY');
  await expectCode(() => fresh.signDiscover(new DiscoverSigningInput('bad id'), SECRET),
    'PROTOCOL_INVALID_IDENTIFIER');
  await expectCode(() => fresh.signControl(
    new SigningInput('gateway_01', 'bad:id', DeviceAction.SET_BRIGHTNESS, 10), SECRET, 1),
    'PROTOCOL_INVALID_IDENTIFIER');
  await expectCode(() => fresh.signControl(
    new SigningInput('gateway_01', 'Light_01', DeviceAction.SET_BRIGHTNESS, 10), SECRET, -1),
    'PROTOCOL_VALUE_OUT_OF_RANGE');
});

test('C05_NonceCache_ttlBoundaryAndCapacityEviction', () => {
  const clock = new FakeClock(1000);
  const cache = new NonceCache(clock, 300000, 2);
  assert.equal(cache.checkAndRemember('app-key-v1', 'a', 1000), NonceDecision.NEW);
  assert.equal(cache.contains('app-key-v1', 'a', 300999), true);
  assert.equal(cache.contains('app-key-v1', 'a', 301000), false);
  assert.equal(cache.checkAndRemember('app-key-v1', 'a', 300999), NonceDecision.DUPLICATE);
  assert.equal(cache.checkAndRemember('app-key-v1', 'a', 301000), NonceDecision.NEW);

  const evictionClock = new FakeClock(2000);
  const eviction = new NonceCache(evictionClock, 300000, 2);
  assert.equal(eviction.checkAndRemember('app-key-v1', 'b', 2000), NonceDecision.NEW);
  assert.equal(eviction.checkAndRemember('app-key-v1', 'c', 2000), NonceDecision.NEW);
  assert.equal(eviction.checkAndRemember('app-key-v1', 'd', 2000), NonceDecision.CAPACITY_EXCEEDED);
  assert.equal(eviction.contains('app-key-v1', 'b', 2000), false);
  assert.equal(eviction.contains('app-key-v1', 'c', 2000), true);
  assert.equal(eviction.contains('app-key-v1', 'd', 2000), true);
  evictionClock.value = 302000;
  assert.equal(eviction.size(), 0);
  eviction.clear();
  assert.equal(eviction.size(), 0);
});

test('C05_CanonicalBuilder_rejectsLineInjectionAndBadAtoms', () => {
  const base = new ControlCanonicalFields('req-1', 2001, 1, 'Light_01', 'ON', '',
    '20260714T080000Z', 'ab'.repeat(16), 'HMAC-SHA256', 'app-key-v1');
  assert.equal(CanonicalBuilder.control(base).split('\n').length, 10);

  const newlineTarget = new ControlCanonicalFields('req-1', 2001, 1, 'Light\n01', 'ON', '',
    '20260714T080000Z', 'ab'.repeat(16), 'HMAC-SHA256', 'app-key-v1');
  expectSyncCode(() => CanonicalBuilder.control(newlineTarget), 'PROTOCOL_VALUE_OUT_OF_RANGE');

  const carriageValue = new ControlCanonicalFields('req-1', 2001, 1, 'Light_01', 'ON', 'x\rY',
    '20260714T080000Z', 'ab'.repeat(16), 'HMAC-SHA256', 'app-key-v1');
  expectSyncCode(() => CanonicalBuilder.control(carriageValue), 'PROTOCOL_VALUE_OUT_OF_RANGE');

  const emptyId = new ControlCanonicalFields('', 2001, 1, 'Light_01', 'ON', '',
    '20260714T080000Z', 'ab'.repeat(16), 'HMAC-SHA256', 'app-key-v1');
  expectSyncCode(() => CanonicalBuilder.control(emptyId), 'PROTOCOL_VALUE_OUT_OF_RANGE');

  const badSeq = new ControlCanonicalFields('req-1', 2001, 1.5, 'Light_01', 'ON', '',
    '20260714T080000Z', 'ab'.repeat(16), 'HMAC-SHA256', 'app-key-v1');
  expectSyncCode(() => CanonicalBuilder.control(badSeq), 'PROTOCOL_VALUE_OUT_OF_RANGE');

  const newlineChallenge = new DiscoverCanonicalFields('0123456789abcdef0123456789abcdef\n',
    '20260714T080000Z', 'ab'.repeat(16), 'HMAC-SHA256', 'app-key-v1');
  expectSyncCode(() => CanonicalBuilder.discover(newlineChallenge),
    'PROTOCOL_VALUE_OUT_OF_RANGE');

  expectSyncCode(() => CanonicalBuilder.response(ResponseKind.CONTROL, 'req-1:1', 'abc'),
    'PROTOCOL_VALUE_OUT_OF_RANGE');
  assert.equal(CanonicalBuilder.response(ResponseKind.CONTROL, 'req-1:1', 'a'.repeat(64))
    .split('\n').length, 4);

  const cloud = new CloudCanonicalFields('req-1', 3001, 1, 'Light_01', 'ON', '',
    '20260714T080000Z', 'ab'.repeat(16), 'HMAC-SHA256', 'app-key-v1');
  const cloudCanonical = CanonicalBuilder.cloudCommand(cloud);
  assert.equal(cloudCanonical.split('\n').length, 10);
  assert.equal(cloudCanonical.split('\n')[1], '3001');
  assert.equal(cloudCanonical.split('\n')[3], 'Light_01');
});

test('C05_timeWindowBoundaryIsInclusiveAt120Seconds', () => {
  const now = Date.UTC(2026, 6, 14, 8, 0, 0);
  assert.equal(DateTimeUtil.isWithinWindow(now, now + 120000, 120000), true);
  assert.equal(DateTimeUtil.isWithinWindow(now, now + 120001, 120000), false);
  assert.equal(DateTimeUtil.isWithinWindow(now, now - 120000, 120000), true);
  assert.equal(DateTimeUtil.isWithinWindow(now, now - 120001, 120000), false);
  // Expired request timestamp (3 minutes old) fails the gateway-side window.
  const expired = DateTimeUtil.parseUtcCompact('20260714T075700Z');
  assert.equal(DateTimeUtil.isWithinWindow(now, expired, 120000), false);
});

test('C05_ClockSkewTracker_hintsWithoutChangingAcceptance', () => {
  const tracker = new ClockSkewTracker(120000);
  const local = Date.UTC(2026, 6, 14, 8, 0, 0);
  const edge = tracker.observe('20260714T080200Z', local);
  assert.equal(edge.skewMs, 120000);
  assert.equal(edge.exceedsWindow, false);
  assert.equal(tracker.lastSkewMs(), 120000);
  const over = tracker.observe('20260714T080201Z', local + 999);
  assert.equal(over.skewMs, 120001);
  assert.equal(over.exceedsWindow, true);
  expectSyncCode(() => tracker.observe('2026-07-14T08:02:01Z', local),
    'PROTOCOL_INVALID_TIMESTAMP');
});

test('C05_ACKChain_verifiedResponseFeedsC03MapperWithoutReinterpretation', async () => {
  const body = new Uint8Array(readFileSync(path.join(FIXTURES, 'control-ack.json')));
  const secret = utf8('0123456789abcdef0123456789abcdef');
  const correlation = 'req-wp002-live-0001:1';
  const digest = sha256Hex(body);
  const canonical = CanonicalBuilder.response(ResponseKind.CONTROL, correlation, digest);
  const sign = hmacHex('0123456789abcdef0123456789abcdef', canonical);
  const headers = HttpHeaders.from([
    new NameValue('X-YaoCore-Response-Alg', 'HMAC-SHA256'),
    new NameValue('X-YaoCore-Key-Id', 'app-key-v1'),
    new NameValue('X-YaoCore-Response-Correlation', correlation),
    new NameValue('X-YaoCore-Response-Sign', sign),
  ]);
  const verified = await verifier.verify(headers, body,
    ExpectedResponse.forControl('req-wp002-live-0001', 1), secret);
  assert.equal(verified.kind, ResponseKind.CONTROL);
  assert.equal(verified.correlation, correlation);

  const outcome = ControlAckMapper.map(body,
    new AckExpectation('req-wp002-live-0001', 1, 'Light_01', DeviceAction.SET_BRIGHTNESS, 42, false),
    new DeviationCounter());
  assert.equal(outcome.ackAccepted, true);
  assert.equal(outcome.resultCode, 0);
  assert.equal(outcome.stateVerification, 'MATCH');
  assert.equal(outcome.shouldApplyState, true);

  const badSign = `${sign.slice(0, 63)}${sign[63] === '0' ? '1' : '0'}`;
  const badHeaders = HttpHeaders.from([
    new NameValue('X-YaoCore-Response-Alg', 'HMAC-SHA256'),
    new NameValue('X-YaoCore-Key-Id', 'app-key-v1'),
    new NameValue('X-YaoCore-Response-Correlation', correlation),
    new NameValue('X-YaoCore-Response-Sign', badSign),
  ]);
  await expectCode(() => verifier.verify(badHeaders, body,
    ExpectedResponse.forControl('req-wp002-live-0001', 1), secret), 'RESPONSE_AUTH_FAILED');
});

test('C05_CorrelationIsExactAndNonceGenerationIs32LowerHex', async () => {
  const clock = new FakeClock(FIXED_MS);
  const signer = new RequestSigner(cryptoService, clock,
    new FakeRandom((length) => new Uint8Array(length).fill(0x5a)), new NonceCache(clock));
  const signed = await signer.signControl(
    new SigningInput('gateway_01', 'Light_01', DeviceAction.SET_BRIGHTNESS, 68), SECRET, 0);
  const correlation = ExpectedResponse.forControl(signed.requestId, signed.seq).correlation;
  assert.equal(correlation, `${signed.requestId}:0`);
  assert.doesNotMatch(correlation, /:00$/);
  assert.match(signed.nonce, new RegExp(ProtocolConstants.HEX_LOWER_32.source));
});
