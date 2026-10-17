/*
 * YaoCore C-19 Security1 / RFC7748 / identity negotiation host tests.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Traceability: DES-A §16.4/§16.6; BLE设计 §4/§5; ADR-002 §3.2;
 * TEST-001 V-10/V-11, SEC-N21.
 *
 * PUBLIC TEST DATA ONLY. Node crypto is the independent oracle; the fake
 * gateway speaks the real Security1 protobuf wire format.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { AppError } from '../../main/ets/common/types/AppError.ets';
import { ProtocommCodec } from '../../main/ets/service/ble/ProtocommCodec.ets';
import {
  Security1Session,
  Security1State,
} from '../../main/ets/service/ble/Security1Session.ets';
import { IdentityNegotiator } from '../../main/ets/service/ble/IdentityNegotiator.ets';
import { IdentityVersion } from '../../main/ets/model/ProvisioningModels.ets';
import { GattEndpointMap } from '../../main/ets/service/ble/GattEndpointMap.ets';
import {
  FakeGateway,
  NodeCryptoPort,
  PIN,
  encodeSessionResponse0,
  hex,
  rfc7748Vector,
  utf8,
} from './BleFakes.mjs';

const pop = utf8('correct-pop');
const randomPort = {
  async nextBytes(length) {
    return new Uint8Array(length).fill(5);
  },
};

const expectCode = async (fn, code) => {
  await assert.rejects(fn, (error) => {
    assert.ok(error instanceof AppError, 'expected AppError');
    assert.equal(error.code, code);
    return true;
  });
};

const expectCodeSync = (fn, code) => {
  assert.throws(fn, (error) => {
    assert.ok(error instanceof AppError, 'expected AppError');
    assert.equal(error.code, code);
    return true;
  });
};

async function handshake(gateway, popBytes = pop) {
  const crypto = new NodeCryptoPort();
  const session = new Security1Session(crypto, randomPort, popBytes);
  const step0 = await session.createStep0();
  const response0 = await gateway.handle('prov-session', step0);
  const step1 = await session.handleStep0Response(response0);
  const response1 = await gateway.handle('prov-session', step1);
  await session.handleStep1Response(response1);
  return { session, crypto, step0 };
}

test('C19_Security1_rfc7748Vector', () => {
  const vector = rfc7748Vector();
  assert.equal(vector.actual, vector.expected);
});

test('C19_Security1_handshakeAndContinuousCtrStream', async () => {
  const gateway = new FakeGateway({ pop: 'correct-pop' });
  const { session, crypto } = await handshake(gateway);
  assert.equal(session.state, Security1State.ESTABLISHED);
  assert.equal(session.clientPublicRaw.length, 32);
  assert.equal(crypto.keyPairCalls, 1);

  const firstPlain = ProtocommCodec.encodeGetStatus();
  const firstCipher = await session.encrypt(firstPlain);
  const firstResponse = await gateway.handle('prov-config', firstCipher);
  const firstDecrypted = await session.decrypt(firstResponse);
  assert.equal(ProtocommCodec.decodeWifiStatus(firstDecrypted).ip4, '192.168.1.50');

  const secondCipher = await session.encrypt(firstPlain);
  assert.notEqual(hex(secondCipher), hex(firstCipher),
    'CTR stream must advance; the same plaintext cannot repeat ciphertext');
  const secondResponse = await gateway.handle('prov-config', secondCipher);
  const secondDecrypted = await session.decrypt(secondResponse);
  assert.equal(ProtocommCodec.decodeWifiStatus(secondDecrypted).ip4, '192.168.1.50');
  session.destroy();
  assert.equal(session.state, Security1State.DESTROYED);
});

test('C19_Security1_wrongPopFailsClosedAndDestroysSession', async () => {
  const gateway = new FakeGateway({ pop: 'device-pop' });
  const session = new Security1Session(new NodeCryptoPort(), randomPort, utf8('wrong-pop'));
  const step0 = await session.createStep0();
  const response0 = await gateway.handle('prov-session', step0);
  const step1 = await session.handleStep0Response(response0);
  const response1 = await gateway.handle('prov-session', step1);
  await expectCode(() => session.handleStep1Response(response1), 'PROVISIONING_POP_INVALID');
  assert.equal(session.state, Security1State.DESTROYED);
  await expectCode(() => session.encrypt(utf8('x')), 'PROVISIONING_SECURITY_HANDSHAKE_FAILED');
});

test('C19_Security1_tamperedDeviceVerifyFailsClosed', async () => {
  const gateway = new FakeGateway({ pop: 'correct-pop', tamperDeviceVerify: true });
  const session = new Security1Session(new NodeCryptoPort(), randomPort, pop);
  const step0 = await session.createStep0();
  const response0 = await gateway.handle('prov-session', step0);
  const step1 = await session.handleStep0Response(response0);
  const response1 = await gateway.handle('prov-session', step1);
  await expectCode(() => session.handleStep1Response(response1), 'PROVISIONING_POP_INVALID');
  assert.equal(session.state, Security1State.DESTROYED);
});

test('C19_Security1_stateGuardsAndStep0Vector', async () => {
  const session = new Security1Session(new NodeCryptoPort(), randomPort, pop);
  await expectCode(() => session.encrypt(utf8('x')), 'PROVISIONING_SECURITY_HANDSHAKE_FAILED');
  const step0 = await session.createStep0();
  assert.equal(hex(step0).substring(0, 18), '10015a25a201220a20');
  await expectCode(() => session.createStep0(), 'PROVISIONING_SECURITY_HANDSHAKE_FAILED');
  await expectCode(() => session.handleStep0Response(
    encodeSessionResponse0(new Uint8Array(32), new Uint8Array(16), 6)),
  'PROVISIONING_SECURITY_HANDSHAKE_FAILED');
  assert.equal(session.state, Security1State.DESTROYED);
});

// ---- Identity negotiation -------------------------------------------------

const v21Body = () => JSON.stringify({
  protocolVersion: '2.1',
  serviceId: 'YaoCoreGateway',
  gatewayId: 'gateway_01',
  gatewayName: '客厅网关',
  security: {
    lan: { tls: true, port: 9200, pins: [PIN], pinAlg: 'sha256-spki-der' },
  },
});

const v20Body = () => JSON.stringify({
  protocolVersion: '2.0',
  serviceId: 'YaoCoreGateway',
  gatewayId: 'gateway_01',
  gatewayName: '客厅网关',
});

const established = { state: 'ESTABLISHED' };

function scriptedSend(responses) {
  const calls = [];
  return {
    calls,
    async send(endpoint, payload) {
      calls.push({
        endpoint,
        protocolVersion: JSON.parse(Buffer.from(payload).toString('utf8')).protocolVersion,
      });
      if (responses.length === 0) {
        throw AppErrorsFallback();
      }
      return utf8(responses.shift());
    },
  };
}

function AppErrorsFallback() {
  return new AppError('INTERNAL_ERROR', 'INTERNAL', 'errors.app.internal_error', false);
}

test('C19_IdentityNegotiator_v21TlsSuccess', async () => {
  const script = scriptedSend([v21Body()]);
  const identity = await new IdentityNegotiator().negotiate(established, script.send);
  assert.equal(identity.version, IdentityVersion.V21);
  assert.equal(identity.gatewayId, 'gateway_01');
  assert.equal(identity.tls.port, 9200);
  assert.equal(identity.tls.pins[0], PIN);
  assert.equal(script.calls.length, 1);
  assert.equal(script.calls[0].endpoint, GattEndpointMap.YAOCORE_ID);
  assert.equal(script.calls[0].protocolVersion, '2.1');
});

test('C19_IdentityNegotiator_v21WithoutSecurityIsHmacOnly', async () => {
  const body = JSON.stringify({
    protocolVersion: '2.1',
    serviceId: 'YaoCoreGateway',
    gatewayId: 'gateway_01',
    gatewayName: 'Gateway',
  });
  const identity = await new IdentityNegotiator().negotiate(established, scriptedSend([body]).send);
  assert.equal(identity.version, IdentityVersion.V21);
  assert.equal(identity.tls, undefined);
});

test('C19_IdentityNegotiator_v21TlsFalseIsHmacOnly', async () => {
  const body = JSON.stringify({
    protocolVersion: '2.1',
    serviceId: 'YaoCoreGateway',
    gatewayId: 'gateway_01',
    gatewayName: 'Gateway',
    security: { lan: { tls: false } },
  });
  const identity = await new IdentityNegotiator().negotiate(established, scriptedSend([body]).send);
  assert.equal(identity.version, IdentityVersion.V21);
  assert.equal(identity.tls, undefined);
});

test('C19_IdentityNegotiator_v21InvalidRetriesV20Once', async () => {
  const invalid = JSON.stringify({
    protocolVersion: '2.0',
    serviceId: 'YaoCoreGateway',
    gatewayId: 'gateway_01',
    gatewayName: 'Gateway',
  });
  const script = scriptedSend([invalid, v20Body()]);
  const identity = await new IdentityNegotiator().negotiate(established, script.send);
  assert.equal(identity.version, IdentityVersion.V20);
  assert.equal(identity.tls, undefined);
  assert.deepEqual(script.calls.map((call) => call.protocolVersion), ['2.1', '2.0']);
});

test('C19_IdentityNegotiator_v20OnlyFirmwareFallsBack', async () => {
  const script = scriptedSend([v20Body(), v20Body()]);
  const identity = await new IdentityNegotiator().negotiate(established, script.send);
  assert.equal(identity.version, IdentityVersion.V20);
  assert.deepEqual(script.calls.map((call) => call.protocolVersion), ['2.1', '2.0']);
});

test('C19_IdentityNegotiator_bothResponsesInvalidFailsClosed', async () => {
  const invalid = JSON.stringify({
    protocolVersion: '2.1',
    serviceId: 'YaoCoreGateway',
    gatewayId: 'gateway_01',
    gatewayName: 'Gateway',
    extra: true,
  });
  await expectCode(() => new IdentityNegotiator().negotiate(established,
    scriptedSend([invalid, invalid]).send), 'PROVISIONING_IDENTITY_INVALID');
});

test('C19_IdentityNegotiator_v20ExtraFieldFailsClosed', async () => {
  const withExtra = JSON.stringify({
    protocolVersion: '2.0',
    serviceId: 'YaoCoreGateway',
    gatewayId: 'gateway_01',
    gatewayName: 'Gateway',
    extra: true,
  });
  expectCodeSync(() => new IdentityNegotiator().parseV20(utf8(withExtra)),
    'PROVISIONING_IDENTITY_INVALID');
});

test('C19_IdentityNegotiator_v20ConstantsAndBoundsAreStrict', () => {
  const negotiator = new IdentityNegotiator();
  const base = {
    protocolVersion: '2.0',
    serviceId: 'YaoCoreGateway',
    gatewayId: 'gateway_01',
    gatewayName: 'Gateway',
  };
  const wrongService = JSON.stringify({ ...base, serviceId: 'Wrong' });
  expectCodeSync(() => negotiator.parseV20(utf8(wrongService)), 'PROVISIONING_IDENTITY_INVALID');
  const wrongVersion = JSON.stringify({ ...base, protocolVersion: '2.1' });
  expectCodeSync(() => negotiator.parseV20(utf8(wrongVersion)), 'PROVISIONING_IDENTITY_INVALID');
  const emptyName = JSON.stringify({ ...base, gatewayName: '' });
  expectCodeSync(() => negotiator.parseV20(utf8(emptyName)), 'PROVISIONING_IDENTITY_INVALID');
  const badGateway = JSON.stringify({ ...base, gatewayId: '-bad' });
  expectCodeSync(() => negotiator.parseV20(utf8(badGateway)), 'PROVISIONING_IDENTITY_INVALID');
  const notObject = JSON.stringify([]);
  expectCodeSync(() => negotiator.parseV20(utf8(notObject)), 'PROVISIONING_IDENTITY_INVALID');
});

test('C19_IdentityNegotiator_gatewayNameUsesCharacterLength', async () => {
  const negotiator = new IdentityNegotiator();
  const v20 = (name) => JSON.stringify({
    protocolVersion: '2.0',
    serviceId: 'YaoCoreGateway',
    gatewayId: 'gateway_01',
    gatewayName: name,
  });
  // 63 ASCII characters pass; 64 characters fail.
  assert.equal(negotiator.parseV20(utf8(v20('a'.repeat(63)))).gatewayName.length, 63);
  expectCodeSync(() => negotiator.parseV20(utf8(v20('a'.repeat(64)))),
    'PROVISIONING_IDENTITY_INVALID');
  // 22 Chinese characters are 66 UTF-8 bytes but only 22 characters; the
  // schema maxLength is in characters, so this must be accepted (F-01).
  const chinese22 = '网'.repeat(22);
  assert.equal(Buffer.byteLength(chinese22, 'utf8'), 66);
  assert.equal(negotiator.parseV20(utf8(v20(chinese22))).gatewayName, chinese22);
  assert.equal(negotiator.parseV20(utf8(v20('网'.repeat(63)))).gatewayName,
    '网'.repeat(63));
  expectCodeSync(() => negotiator.parseV20(utf8(v20('网'.repeat(64)))),
    'PROVISIONING_IDENTITY_INVALID');
  // v2.1 shares the same character-length check.
  const v21 = JSON.stringify({
    protocolVersion: '2.1',
    serviceId: 'YaoCoreGateway',
    gatewayId: 'gateway_01',
    gatewayName: chinese22,
  });
  const identity = await negotiator.negotiate(established, scriptedSend([v21]).send);
  assert.equal(identity.version, IdentityVersion.V21);
  assert.equal(identity.gatewayName, chinese22);
});

test('C19_IdentityNegotiator_pinValidationIsFailClosed', async () => {
  const uppercasePin = JSON.stringify({
    protocolVersion: '2.1',
    serviceId: 'YaoCoreGateway',
    gatewayId: 'gateway_01',
    gatewayName: 'Gateway',
    security: { lan: { tls: true, port: 9200, pins: [PIN.toUpperCase()], pinAlg: 'sha256-spki-der' } },
  });
  await expectCode(() => new IdentityNegotiator().negotiate(established,
    scriptedSend([uppercasePin, uppercasePin]).send), 'PROVISIONING_IDENTITY_INVALID');

  const wrongAlg = JSON.stringify({
    protocolVersion: '2.1',
    serviceId: 'YaoCoreGateway',
    gatewayId: 'gateway_01',
    gatewayName: 'Gateway',
    security: { lan: { tls: true, port: 9200, pins: [PIN], pinAlg: 'sha256' } },
  });
  await expectCode(() => new IdentityNegotiator().negotiate(established,
    scriptedSend([wrongAlg, wrongAlg]).send), 'PROVISIONING_IDENTITY_INVALID');

  const noPins = JSON.stringify({
    protocolVersion: '2.1',
    serviceId: 'YaoCoreGateway',
    gatewayId: 'gateway_01',
    gatewayName: 'Gateway',
    security: { lan: { tls: true, port: 9200, pinAlg: 'sha256-spki-der' } },
  });
  await expectCode(() => new IdentityNegotiator().negotiate(established,
    scriptedSend([noPins, noPins]).send), 'PROVISIONING_IDENTITY_INVALID');
});

test('C19_IdentityNegotiator_multiplePinsAreAccepted', async () => {
  const secondPin = 'b'.repeat(64);
  const body = JSON.stringify({
    protocolVersion: '2.1',
    serviceId: 'YaoCoreGateway',
    gatewayId: 'gateway_01',
    gatewayName: 'Gateway',
    security: {
      lan: { tls: true, port: 9443, pins: [PIN, secondPin], pinAlg: 'sha256-spki-der' },
    },
  });
  const identity = await new IdentityNegotiator().negotiate(established, scriptedSend([body]).send);
  assert.equal(identity.tls.pins.length, 2);
  assert.equal(identity.tls.pins[1], secondPin);
  assert.equal(identity.tls.port, 9443);
});

test('C19_IdentityNegotiator_expectedGatewayIdMismatchIsTerminal', async () => {
  await expectCode(() => new IdentityNegotiator().negotiate(established,
    scriptedSend([v21Body()]).send, 'gateway_other'),
  'PROVISIONING_BINDING_IDENTITY_MISMATCH');
  await expectCode(() => new IdentityNegotiator().negotiate(established,
    scriptedSend([v20Body(), v20Body()]).send, 'gateway_other'),
  'PROVISIONING_BINDING_IDENTITY_MISMATCH');
});

test('C19_IdentityNegotiator_requiresEstablishedSession', async () => {
  await expectCode(() => new IdentityNegotiator().negotiate({ state: 'NEW' },
    scriptedSend([v21Body()]).send), 'PROVISIONING_SECURITY_HANDSHAKE_FAILED');
});
