import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, createHmac, X509Certificate } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  controlCanonical,
  discoveryCanonical,
  responseCanonical,
  valueAtom,
} from './protocol-oracle.ets';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(HERE, '../../../..');
const FIXTURES = path.join(
  REPO_ROOT,
  'entry/src/ohosTest/ets/test/contract/fixtures',
);
const PROTOCOL = path.join(REPO_ROOT, 'input/api/protocol');
const CERT = path.join(REPO_ROOT, 'tools/simulator/certs/dev-test-cert.pem');
const EXPECTED_SPKI =
  '63f928c4c645b242ffb2a90a624258035e2a5ffb515756e0fb2f88113afa3243';

const readJson = (file) => JSON.parse(readFileSync(file, 'utf8'));
const hmacHex = (secret, text) =>
  createHmac('sha256', secret).update(text, 'utf8').digest('hex');
const sha256Hex = (text) =>
  createHash('sha256').update(text, 'utf8').digest('hex');

test('host runner executes pure arithmetic and assertions', () => {
  assert.equal(2 + 2, 4);
  assert.equal('YaoCore'.length, 7);
});

test('valueAtom follows the protocol README', () => {
  assert.equal(valueAtom(undefined), '');
  assert.equal(valueAtom('制冷'), '"制冷"');
  assert.equal(valueAtom(true), 'true');
  assert.equal(valueAtom(false), 'false');
  assert.equal(valueAtom(24), '24');
  assert.equal(valueAtom(24.5), '24.5');
  assert.throws(() => valueAtom(null), /value must be/);
});

test('all 4 control HMAC vectors reproduce canonical and signature', () => {
  const document = readJson(path.join(FIXTURES, 'hmac-sha256-test-vectors.json'));
  assert.equal(document.vectors.length, 4);
  for (const vector of document.vectors) {
    assert.equal(
      controlCanonical(vector.request),
      vector.canonical,
      `canonical mismatch: ${vector.name}`,
    );
    assert.equal(
      hmacHex(vector.secret, vector.canonical),
      vector.expectedSign,
      `signature mismatch: ${vector.name}`,
    );
    assert.equal(
      vector.request.sign,
      vector.expectedSign,
      `request.sign mismatch: ${vector.name}`,
    );
  }
});

test('response-auth vector reproduces body hash, canonical and signature', () => {
  const document = readJson(path.join(FIXTURES, 'response-auth-test-vectors.json'));
  assert.equal(document.vectors.length, 1);
  for (const vector of document.vectors) {
    assert.equal(sha256Hex(vector.body), vector.bodySha256, vector.name);
    const canonical = responseCanonical(
      vector.kind,
      vector.correlation,
      vector.bodySha256,
    );
    assert.equal(canonical, vector.canonical.replaceAll('\\n', '\n'), vector.name);
    assert.equal(hmacHex(vector.secret, canonical), vector.signature, vector.name);
  }
});

test('discovery-request vector reproduces canonical and signature', () => {
  const document = readJson(
    path.join(FIXTURES, 'discovery-request-auth-test-vectors.json'),
  );
  assert.equal(document.vectors.length, 1);
  for (const vector of document.vectors) {
    const canonical = discoveryCanonical(
      vector.challenge,
      vector.timestamp,
      vector.nonce,
      vector.alg,
      vector.key_id,
    );
    assert.equal(canonical, vector.canonical.replaceAll('\\n', '\n'), vector.name);
    assert.equal(hmacHex(vector.secret, canonical), vector.signature, vector.name);
  }
});

test('golden discover response is schema-shaped and uses wire field names', () => {
  const schema = readJson(path.join(PROTOCOL, 'discover-response.schema.json'));
  const document = readJson(path.join(FIXTURES, 'discover-response.json'));

  assert.deepEqual(
    new Set(Object.keys(document)),
    new Set(schema.required),
    'top-level keys must equal schema required',
  );
  assert.deepEqual(
    Object.keys(document).filter((key) => !(key in schema.properties)),
    [],
    'no unknown top-level keys',
  );

  const deviceProperties = schema.$defs.device.properties;
  const allDeviceKeys = new Set();
  for (const device of document.devices) {
    for (const key of Object.keys(device)) {
      allDeviceKeys.add(key);
      assert.ok(key in deviceProperties, `unknown device key: ${key}`);
    }
  }
  assert.ok(allDeviceKeys.has('online'));
  assert.ok(!allDeviceKeys.has('isOnline'));
  assert.ok(!allDeviceKeys.has('powerStatus'));
  assert.ok(!allDeviceKeys.has('success'));
  assert.equal(document.security.keyId, 'app-key-v1');
  assert.equal(document.security.timeWindowSeconds, 120);
  assert.equal(document.security.nonceTtlSeconds, 300);
});

test('golden ACK satisfies execution-confirmation fields', () => {
  const schema = readJson(path.join(PROTOCOL, 'local-control-ack.schema.json'));
  const ack = readJson(path.join(FIXTURES, 'control-ack.json'));

  assert.equal(ack.result_code, 0);
  assert.equal(ack.request_id, 'req-wp002-live-0001');
  assert.equal(ack.seq, 1);
  assert.equal(`${ack.request_id}:${ack.seq}`, 'req-wp002-live-0001:1');
  assert.equal(ack.success, undefined);
  assert.equal(ack.reported_state.online, true);
  assert.equal(ack.reported_state.deviceId, 'Light_01');

  const allowed = new Set([
    ...Object.keys(schema.$defs.deviceState.properties),
    ...Object.keys(schema.$defs.gatewayState.properties),
  ]);
  for (const key of Object.keys(ack.reported_state)) {
    assert.ok(allowed.has(key), `unknown reported_state key: ${key}`);
  }
});

test('golden replay ACK only adds idempotent_replay', () => {
  const first = readJson(path.join(FIXTURES, 'control-ack.json'));
  const replay = readJson(path.join(FIXTURES, 'control-ack-replay.json'));
  assert.equal(replay.idempotent_replay, true);
  const core = { ...replay };
  delete core.idempotent_replay;
  assert.deepEqual(core, first);
});

test('test certificate SPKI matches the Python simulator pin', () => {
  const certificate = new X509Certificate(readFileSync(CERT));
  const spki = certificate.publicKey.export({ type: 'spki', format: 'der' });
  const digest = createHash('sha256').update(spki).digest('hex');
  assert.match(digest, /^[0-9a-f]{64}$/);
  assert.equal(digest, EXPECTED_SPKI);
});
