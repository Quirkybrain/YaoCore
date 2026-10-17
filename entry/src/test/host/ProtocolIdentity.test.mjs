/*
 * YaoCore C-03 BLE enrollment identity host tests.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Traceability: DES-A §6.1.5; PR-07; V-11; SEC-N21.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { AppError } from '../../main/ets/common/types/AppError.ets';
import { IdentityParser } from '../../main/ets/service/protocol/IdentityParser.ets';
import { IdentityVersion } from '../../main/ets/model/ProvisioningModels.ets';

const PIN = 'a'.repeat(64);
const encode = (value) => new TextEncoder().encode(JSON.stringify(value));

const v20 = (overrides = {}) => ({
  protocolVersion: '2.0',
  serviceId: 'YaoCoreGateway',
  gatewayId: 'gateway_01',
  gatewayName: 'YaoCore Gateway',
  ...overrides,
});

const v21 = (overrides = {}) => ({
  protocolVersion: '2.1',
  serviceId: 'YaoCoreGateway',
  gatewayId: 'gateway_01',
  gatewayName: 'YaoCore Gateway',
  ...overrides,
});

const lan = (overrides = {}) => ({
  tls: true,
  port: 9443,
  pins: [PIN],
  pinAlg: 'sha256-spki-der',
  ...overrides,
});

const expectIdentityInvalid = (fn) => {
  assert.throws(fn, (error) => {
    assert.ok(error instanceof AppError, `expected AppError, got ${error}`);
    assert.equal(error.code, 'PROVISIONING_IDENTITY_INVALID', error.code);
    return true;
  });
};

test('C03_IdentityParser_v20StrictFourFieldEnvelope', () => {
  const dto = IdentityParser.parseV20(encode(v20()));
  assert.equal(dto.protocolVersion, '2.0');
  assert.equal(dto.serviceId, 'YaoCoreGateway');
  assert.equal(dto.gatewayId, 'gateway_01');
  assert.equal(dto.gatewayName, 'YaoCore Gateway');

  expectIdentityInvalid(() => IdentityParser.parseV20(encode(v20({ extra: true }))));
  expectIdentityInvalid(() => IdentityParser.parseV20(encode(v20({ serviceId: 'Other' }))));
  expectIdentityInvalid(() => IdentityParser.parseV20(encode(v20({ protocolVersion: '2.1' }))));
  expectIdentityInvalid(() => IdentityParser.parseV20(encode(v20({ gatewayId: 'gw:01' }))));
  expectIdentityInvalid(() => IdentityParser.parseV20(encode(v20({ gatewayId: 'g'.repeat(64) }))));
  expectIdentityInvalid(() => IdentityParser.parseV20(encode(v20({ gatewayName: '' }))));
  expectIdentityInvalid(() => IdentityParser.parseV20('{'));
  expectIdentityInvalid(() => IdentityParser.parseV20('{"protocolVersion":"2.0","protocolVersion":"2.0"}'));
});

test('C03_IdentityParser_v21AcceptsKnownSecurityLanOnly', () => {
  const dto = IdentityParser.parseV21(encode(v21({ security: { lan: lan() } })));
  assert.equal(dto.security.lan.tls, true);
  assert.equal(dto.security.lan.port, 9443);
  assert.deepEqual(dto.security.lan.pins, [PIN]);
  assert.equal(dto.security.lan.pinAlg, 'sha256-spki-der');

  assert.equal(IdentityParser.parseV21(encode(v21({ security: {} }))).security.lan, undefined);
  const tlsOff = IdentityParser.parseV21(encode(v21({ security: { lan: { tls: false } } })));
  assert.equal(tlsOff.security.lan.tls, false);
  assert.equal(tlsOff.security.lan.port, undefined);
});

test('C03_IdentityParser_v21FailsClosedOnUnknownOrInconsistentFields', () => {
  expectIdentityInvalid(() => IdentityParser.parseV21(encode(v21({ extra: true }))));
  expectIdentityInvalid(() => IdentityParser.parseV21(encode(v21({
    security: { lan: lan(), extra: true },
  }))));
  expectIdentityInvalid(() => IdentityParser.parseV21(encode(v21({
    security: { lan: lan({ extra: true }) },
  }))));
  expectIdentityInvalid(() => IdentityParser.parseV21(encode(v21({
    security: { lan: { tls: false, port: 9443 } },
  }))));
  expectIdentityInvalid(() => IdentityParser.parseV21(encode(v21({
    security: { lan: { tls: false, pins: [PIN] } },
  }))));
  expectIdentityInvalid(() => IdentityParser.parseV21(encode(v21({
    security: { lan: { tls: false, pinAlg: 'sha256-spki-der' } },
  }))));
  expectIdentityInvalid(() => IdentityParser.parseV21(encode(v21({
    protocolVersion: '2.0', security: { lan: lan() },
  }))));
});

test('C03_IdentityParser_v21ValidatesPortPinsAndPinAlg', () => {
  expectIdentityInvalid(() => IdentityParser.parseV21(encode(v21({
    security: { lan: lan({ port: 0 }) },
  }))));
  expectIdentityInvalid(() => IdentityParser.parseV21(encode(v21({
    security: { lan: lan({ port: 65536 }) },
  }))));
  expectIdentityInvalid(() => IdentityParser.parseV21(encode(v21({
    security: { lan: lan({ port: 9443.5 }) },
  }))));
  expectIdentityInvalid(() => IdentityParser.parseV21(encode(v21({
    security: { lan: lan({ pins: [] }) },
  }))));
  expectIdentityInvalid(() => IdentityParser.parseV21(encode(v21({
    security: { lan: lan({ pins: [PIN, PIN, PIN, PIN, PIN] }) },
  }))));
  expectIdentityInvalid(() => IdentityParser.parseV21(encode(v21({
    security: { lan: lan({ pins: ['A'.repeat(64)] }) },
  }))));
  expectIdentityInvalid(() => IdentityParser.parseV21(encode(v21({
    security: { lan: lan({ pins: ['a'.repeat(63)] }) },
  }))));
  expectIdentityInvalid(() => IdentityParser.parseV21(encode(v21({
    security: { lan: lan({ pinAlg: 'sha1' }) },
  }))));
  expectIdentityInvalid(() => IdentityParser.parseV21(encode(v21({
    security: { lan: { tls: true, pins: [PIN], pinAlg: 'sha256-spki-der' } },
  }))));
});

test('C03_IdentityParser_serializesGetIdentityRequest', () => {
  assert.equal(
    new TextDecoder().decode(IdentityParser.serializeRequest(IdentityVersion.V20)),
    '{"op":"get_identity","protocolVersion":"2.0"}',
  );
  assert.equal(
    new TextDecoder().decode(IdentityParser.serializeRequest(IdentityVersion.V21)),
    '{"op":"get_identity","protocolVersion":"2.1"}',
  );
});
