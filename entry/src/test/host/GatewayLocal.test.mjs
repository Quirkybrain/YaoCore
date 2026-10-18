/*
 * YaoCore C-17 LocalGatewayService host tests.
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §14.1-§14.6, §18.1-§18.7, §19.4; ADR-002 §6; D-019.
 *
 * PUBLIC TEST DATA ONLY. All transport/TLS behaviour is injected; no device,
 * no real HTTP stack. Node crypto is an independent oracle for the HMAC and
 * response canonical.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, createHmac } from 'node:crypto';

import { AppError, AppErrors } from '../../main/ets/common/types/AppError.ets';
import { NameValue } from '../../main/ets/common/types/NameValue.ets';
import { HttpHeaders } from '../../main/ets/common/types/HttpHeaders.ets';
import { ProtocolConstants, ProtocolHeaders } from '../../main/ets/common/constants/ProtocolConstants.ets';
import { DeviceAction, DeviceType } from '../../main/ets/common/constants/DeviceConstants.ets';
import { GatewayAddress, GatewayRoute, GatewayRouteInit } from '../../main/ets/model/GatewayRoute.ets';
import { TransportProfile } from '../../main/ets/model/DeviceTypes.ets';
import { DeviceControlCommand } from '../../main/ets/model/ControlModels.ets';
import { StateVerification } from '../../main/ets/model/ControlModels.ets';
import { CryptoService } from '../../main/ets/service/crypto/CryptoService.ets';
import { NonceCache } from '../../main/ets/service/security/NonceCache.ets';
import { RequestSigner } from '../../main/ets/service/security/RequestSigner.ets';
import { ClockSkewTracker } from '../../main/ets/service/security/ClockSkewTracker.ets';
import { ResponseVerifier } from '../../main/ets/service/security/ResponseVerifier.ets';
import { CanonicalBuilder, ResponseKind } from '../../main/ets/service/security/CanonicalBuilder.ets';
import {
  GatewayRequestPolicy,
  ControlPolicy,
} from '../../main/ets/service/gateway/GatewayRequestPolicy.ets';
import { LocalGatewayService } from '../../main/ets/service/gateway/LocalGatewayService.ets';
import { GatewayTarget, HttpResponse, TlsVerification } from '../../main/ets/model/GatewayTransportModels.ets';
import {
  FakeHttpTransport,
  FakeTransportClock,
  InMemoryAddressPort,
  InMemoryCredentials,
  InMemoryRoutePort,
  InMemorySequences,
  RecordingLogger,
  RecordingMetrics,
  SequenceRandom,
} from './TransportFakes.ets';
import { TestCryptoProvider } from './TestCryptoProvider.ets';

const FIXED_MS = Date.UTC(2026, 9, 17, 8, 0, 0); // 20261017T080000Z
const FIXED_TS = '20261017T080000Z';
const FAMILY = '123e4567-e89b-12d3-a456-426614174000';
const GATEWAY = 'gateway_01';
const PIN_A = 'a'.repeat(64);
const PIN_B = 'b'.repeat(64);
const SECRET = Buffer.from('0123456789abcdef', 'utf8'); // PUBLIC TEST DATA ONLY
const ALIAS = 'yaocore.gateway.hmac.' + GATEWAY;

const sha256Hex = (bytes) => createHash('sha256').update(bytes).digest('hex');
const hmacHex = (secret, text) => createHmac('sha256', secret).update(text, 'utf8').digest('hex');
const utf8 = (text) => Buffer.from(text, 'utf8');

const expectCode = async (fn, code) => {
  await assert.rejects(fn, (error) => {
    assert.ok(error instanceof AppError, `expected AppError, got ${error}`);
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
};

const signedResponseHeaders = (kind, correlation, bodyBytes, secret) => {
  const canonical = `YAOCORE-RESPONSE-V1\n${kind}\n${correlation}\n${sha256Hex(bodyBytes)}`;
  return HttpHeaders.from([
    new NameValue(ProtocolHeaders.RESPONSE_ALG, 'HMAC-SHA256'),
    new NameValue(ProtocolHeaders.RESPONSE_KEY_ID, 'app-key-v1'),
    new NameValue(ProtocolHeaders.RESPONSE_CORRELATION, correlation),
    new NameValue(ProtocolHeaders.RESPONSE_SIGN, hmacHex(secret, canonical)),
  ]);
};

const discoverBody = (gatewayId = GATEWAY) => Buffer.from(JSON.stringify({
  protocolVersion: '2.0',
  gatewayId,
  gatewayName: 'Mock Gateway',
  serviceId: 'SmartHomeService',
  generatedAt: FIXED_TS,
  security: {
    alg: 'HMAC-SHA256',
    keyId: 'app-key-v1',
    timeWindowSeconds: 120,
    nonceTtlSeconds: 300,
  },
  devices: [],
}), 'utf8');

const ackBody = (request, options = {}) => {
  const resultCode = options.resultCode === undefined ? 0 : options.resultCode;
  const document = {
    request_id: request.request_id,
    seq: request.seq,
    result_code: resultCode,
    message: resultCode === 0 ? 'ok' : 'gateway error',
    server_time: FIXED_TS,
  };
  if (resultCode !== 0) {
    document.error_code = options.errorCode === undefined ? 'mock_error' : options.errorCode;
  }
  if (options.idempotentReplay === true) {
    document.idempotent_replay = true;
  }
  if (resultCode === 0 && options.omitReportedState !== true) {
    document.reported_state = options.reportedState === undefined ? {
      deviceId: request.target,
      online: true,
      power: true,
      updatedAt: FIXED_TS,
    } : options.reportedState;
  }
  return Buffer.from(JSON.stringify(document), 'utf8');
};

const setup = (policy = GatewayRequestPolicy.defaults()) => {
  const clock = new FakeTransportClock(FIXED_MS);
  const crypto = new CryptoService(new TestCryptoProvider());
  const transport = new FakeHttpTransport();
  const credentials = new InMemoryCredentials();
  credentials.set(GATEWAY, SECRET);
  const sequences = new InMemorySequences();
  const routes = new InMemoryRoutePort();
  const addresses = new InMemoryAddressPort();
  const logger = new RecordingLogger();
  const metrics = new RecordingMetrics();
  const delays = [];
  const service = new LocalGatewayService(
    transport,
    new RequestSigner(crypto, clock, new SequenceRandom(new Uint8Array(64).fill(7)),
      new NonceCache(clock)),
    new ResponseVerifier(crypto),
    credentials,
    sequences,
    routes,
    addresses,
    clock,
    new ClockSkewTracker(),
    logger,
    metrics,
    policy,
    async (delayMs) => {
      delays.push(delayMs);
      clock.advance(delayMs);
    },
  );
  return { clock, crypto, transport, credentials, sequences, routes, addresses, logger,
    metrics, delays, service };
};

const target = (profile = TransportProfile.P_HMAC, pins = []) => new GatewayTarget(
  GATEWAY, FAMILY, new GatewayAddress('192.168.1.20', 9200), profile, pins, 9200, ALIAS);

const command = (action = DeviceAction.SET_BRIGHTNESS, value = 42) => new DeviceControlCommand(
  GATEWAY, 'Light_01', action, FIXED_MS, value);

const parseRequest = (httpRequest) => JSON.parse(Buffer.from(httpRequest.body).toString('utf8'));

const discoverChallenge = (httpRequest) => httpRequest.headers.get(ProtocolHeaders.CHALLENGE);

test('C17_discover_pipeline_signsAndVerifiesResponse', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request) => {
    const body = discoverBody();
    const challenge = discoverChallenge(request);
    return new HttpResponse(200, signedResponseHeaders('discover', challenge, body, SECRET), body,
      ctx.clock.nowMs());
  });
  const snapshot = await ctx.service.discover(target());
  assert.equal(snapshot.gatewayId, GATEWAY);
  assert.equal(ctx.transport.requests.length, 1);
  assert.equal(ctx.transport.requests[0].url, 'http://192.168.1.20:9200/discover');
  assert.match(discoverChallenge(ctx.transport.requests[0]), /^[0-9a-f]{32}$/);
  assert.equal(ctx.transport.requests[0].headers.get('Accept'), 'application/json');
  assert.equal(ctx.metrics.count('lan.discover.ms'), 1);
});

test('C17_discover_gatewayIdMismatchRejected', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request) => {
    const body = discoverBody('other_gateway');
    return new HttpResponse(200,
      signedResponseHeaders('discover', discoverChallenge(request), body, SECRET), body,
      ctx.clock.nowMs());
  });
  await expectCode(() => ctx.service.discover(target()), 'GATEWAY_ID_MISMATCH');
});

test('C17_control_success_appliesAckChain', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request) => {
    const parsed = parseRequest(request);
    const body = ackBody(parsed, {
      reportedState: {
        deviceId: 'Light_01',
        online: true,
        brightness: 42,
        power: true,
        updatedAt: FIXED_TS,
      },
    });
    const correlation = `${parsed.request_id}:${parsed.seq}`;
    return new HttpResponse(200, signedResponseHeaders('control', correlation, body, SECRET), body,
      ctx.clock.nowMs());
  });
  const outcome = await ctx.service.control(target(), command());
  assert.equal(outcome.ackAccepted, true);
  assert.equal(outcome.resultCode, 0);
  assert.equal(outcome.stateVerification, StateVerification.MATCH);
  assert.equal(outcome.shouldApplyState, true);
  assert.equal(outcome.idempotentReplay, false);
  assert.equal(ctx.transport.requests.length, 1);
  const sent = parseRequest(ctx.transport.requests[0]);
  assert.equal(sent.cmd_id, 2001);
  assert.equal(sent.payload.action, 'SET_BRIGHTNESS');
  assert.equal(sent.payload.value, 42);
  assert.match(sent.nonce, /^[0-9a-f]{32}$/);
  assert.equal(ctx.metrics.count('lan.control.transport.ms'), 1);
  assert.equal(ctx.metrics.count('lan.control.commit.ms'), 1);
});

test('C17_control_retriesExactBytesOnTimeout', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request, tls, attempt) => {
    if (attempt === 1) {
      throw AppErrors.of('GATEWAY_TIMEOUT', []);
    }
    const parsed = parseRequest(request);
    const body = ackBody(parsed, { idempotentReplay: true });
    return new HttpResponse(200,
      signedResponseHeaders('control', `${parsed.request_id}:${parsed.seq}`, body, SECRET), body,
      ctx.clock.nowMs());
  });
  const outcome = await ctx.service.control(target(), command());
  assert.equal(outcome.ackAccepted, true);
  assert.equal(outcome.idempotentReplay, true);
  assert.equal(ctx.transport.requests.length, 2);
  assert.equal(Buffer.compare(ctx.transport.requests[0].body, ctx.transport.requests[1].body), 0);
  assert.deepEqual(ctx.delays, [300]);
  assert.equal(parseRequest(ctx.transport.requests[0]).nonce,
    parseRequest(ctx.transport.requests[1]).nonce);
});

test('C17_control_retriesHttp500WithoutSignedAck', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request, tls, attempt) => {
    if (attempt === 1) {
      return new HttpResponse(500, HttpHeaders.from([]), utf8('upstream failure'), ctx.clock.nowMs());
    }
    const parsed = parseRequest(request);
    const body = ackBody(parsed);
    return new HttpResponse(200,
      signedResponseHeaders('control', `${parsed.request_id}:${parsed.seq}`, body, SECRET), body,
      ctx.clock.nowMs());
  });
  const outcome = await ctx.service.control(target(), command());
  assert.equal(outcome.ackAccepted, true);
  assert.equal(ctx.transport.requests.length, 2);
  assert.equal(ctx.delays.length, 1);
  assert.equal(ctx.metrics.count('lan.control.transport.ms'), 2);
});

test('C17_control_exhaustsThreeAttemptsOnUnsignedHttp500', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async () => new HttpResponse(500, HttpHeaders.from([]),
    utf8('upstream failure'), ctx.clock.nowMs()));
  await expectCode(() => ctx.service.control(target(), command()), 'HTTP_500');
  assert.equal(ctx.transport.requests.length, 3);
  assert.deepEqual(ctx.delays, [300, 900]);
});

// T-11 F-01: non-2xx responses that DO carry ACK material must fail closed and
// must never be retried. Only a response with no authentication material is a
// plain HTTP failure.
test('C17_control_http500WithBadSignatureFailsClosedWithoutRetry', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request) => {
    const parsed = parseRequest(request);
    const body = ackBody(parsed);
    return new HttpResponse(500,
      signedResponseHeaders('control', `${parsed.request_id}:${parsed.seq}`, body,
        Buffer.from('ffffffffffffffff', 'utf8')), body, ctx.clock.nowMs());
  });
  await expectCode(() => ctx.service.control(target(), command()), 'RESPONSE_AUTH_FAILED');
  assert.equal(ctx.transport.requests.length, 1);
  assert.deepEqual(ctx.delays, []);
});

test('C17_control_http500WithBadCorrelationFailsClosedWithoutRetry', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request) => {
    const parsed = parseRequest(request);
    const body = ackBody(parsed);
    return new HttpResponse(500,
      signedResponseHeaders('control', 'wrong:correlation', body, SECRET), body,
      ctx.clock.nowMs());
  });
  await expectCode(() => ctx.service.control(target(), command()),
    'RESPONSE_CORRELATION_MISMATCH');
  assert.equal(ctx.transport.requests.length, 1);
  assert.deepEqual(ctx.delays, []);
});

test('C17_control_http500WithSignedMalformedAckIsProtocolViolation', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request) => {
    const parsed = parseRequest(request);
    const malformed = ackBody(parsed, { omitReportedState: true });
    return new HttpResponse(500,
      signedResponseHeaders('control', `${parsed.request_id}:${parsed.seq}`, malformed, SECRET),
      malformed, ctx.clock.nowMs());
  });
  await expectCode(() => ctx.service.control(target(), command()), 'ACK_PROTOCOL_VIOLATION');
  assert.equal(ctx.transport.requests.length, 1);
  assert.deepEqual(ctx.delays, []);
});

test('C17_control_http422WithBadSignatureFailsClosedWithoutRetry', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request) => {
    const parsed = parseRequest(request);
    const body = ackBody(parsed);
    return new HttpResponse(422,
      signedResponseHeaders('control', `${parsed.request_id}:${parsed.seq}`, body,
        Buffer.from('ffffffffffffffff', 'utf8')), body, ctx.clock.nowMs());
  });
  await expectCode(() => ctx.service.control(target(), command()), 'RESPONSE_AUTH_FAILED');
  assert.equal(ctx.transport.requests.length, 1);
});

test('C17_control_http4xxWithoutAckMaterialDoesNotRetry', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async () => new HttpResponse(404, HttpHeaders.from([]),
    utf8('not found'), ctx.clock.nowMs()));
  await expectCode(() => ctx.service.control(target(), command()), 'HTTP_404');
  assert.equal(ctx.transport.requests.length, 1);
});

test('C17_control_doesNotRetrySignedGatewayError', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request) => {
    const parsed = parseRequest(request);
    const body = ackBody(parsed, { resultCode: 1004, errorCode: 'bad_signature' });
    return new HttpResponse(401,
      signedResponseHeaders('control', `${parsed.request_id}:${parsed.seq}`, body, SECRET), body,
      ctx.clock.nowMs());
  });
  const outcome = await ctx.service.control(target(), command());
  assert.equal(outcome.ackAccepted, false);
  assert.equal(outcome.resultCode, 1004);
  assert.equal(outcome.gatewayResult.known, true);
  assert.equal(outcome.gatewayResult.success, false);
  assert.equal(ctx.transport.requests.length, 1);
});

test('C17_control_exhaustsThreeAttemptsOnTransportFailure', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async () => {
    throw AppErrors.of('GATEWAY_UNREACHABLE', []);
  });
  await expectCode(() => ctx.service.control(target(), command()), 'GATEWAY_UNREACHABLE');
  assert.equal(ctx.transport.requests.length, 3);
  assert.deepEqual(ctx.delays, [300, 900]);
});

test('C17_controlNormalizesAcModeBeforeSigning', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request) => {
    const parsed = parseRequest(request);
    const body = ackBody(parsed);
    return new HttpResponse(200,
      signedResponseHeaders('control', `${parsed.request_id}:${parsed.seq}`, body, SECRET), body,
      ctx.clock.nowMs());
  });
  const acCommand = new DeviceControlCommand(GATEWAY, 'AC_01', DeviceAction.SET_MODE,
    FIXED_MS, 'cool');
  const outcome = await ctx.service.control(target(), acCommand);
  assert.equal(outcome.ackAccepted, true);
  assert.equal(parseRequest(ctx.transport.requests[0]).payload.value, 'COOL');
});

test('C17_control_badSignatureFailsClosedWithoutRetry', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request) => {
    const parsed = parseRequest(request);
    const body = ackBody(parsed);
    return new HttpResponse(200,
      signedResponseHeaders('control', `${parsed.request_id}:${parsed.seq}`, body,
        Buffer.from('ffffffffffffffff', 'utf8')), body, ctx.clock.nowMs());
  });
  await expectCode(() => ctx.service.control(target(), command()), 'RESPONSE_AUTH_FAILED');
  assert.equal(ctx.transport.requests.length, 1);
});

test('C17_control_badCorrelationFailsClosedWithoutRetry', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request) => {
    const parsed = parseRequest(request);
    const body = ackBody(parsed);
    return new HttpResponse(200,
      signedResponseHeaders('control', 'wrong:correlation', body, SECRET), body, ctx.clock.nowMs());
  });
  await expectCode(() => ctx.service.control(target(), command()),
    'RESPONSE_CORRELATION_MISMATCH');
  assert.equal(ctx.transport.requests.length, 1);
});

test('C17_control_successWithoutReportedStateIsProtocolViolation', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request) => {
    const parsed = parseRequest(request);
    const body = ackBody(parsed, { omitReportedState: true });
    return new HttpResponse(200,
      signedResponseHeaders('control', `${parsed.request_id}:${parsed.seq}`, body, SECRET), body,
      ctx.clock.nowMs());
  });
  await expectCode(() => ctx.service.control(target(), command()), 'ACK_PROTOCOL_VIOLATION');
});

test('C17_control_stateTargetMismatchIsRejected', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request) => {
    const parsed = parseRequest(request);
    const body = ackBody(parsed, {
      reportedState: { deviceId: 'Other_01', online: true, power: true, updatedAt: FIXED_TS },
    });
    return new HttpResponse(200,
      signedResponseHeaders('control', `${parsed.request_id}:${parsed.seq}`, body, SECRET), body,
      ctx.clock.nowMs());
  });
  await expectCode(() => ctx.service.control(target(), command()), 'ACK_STATE_MISMATCH');
});

test('C17_devOnlyResponseRejectedBeforeVerification', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async () => new HttpResponse(200,
    HttpHeaders.from([new NameValue(ProtocolHeaders.SIMULATOR, 'dev-only')]),
    utf8('not even json'), ctx.clock.nowMs()));
  await expectCode(() => ctx.service.discover(target()), 'DEV_SIMULATOR_REJECTED');
  assert.equal(ctx.transport.requests.length, 1);
  assert.equal(ctx.metrics.count('lan.discover.ms'), 0);
});

test('C17_pBlockedSendsNoRequest', async () => {
  const ctx = setup();
  await expectCode(() => ctx.service.control(target(TransportProfile.P_BLOCKED), command()),
    'GATEWAY_PROFILE_BLOCKED');
  assert.equal(ctx.transport.requests.length, 0);
  const event = ctx.logger.records.find((entry) => entry.message === 'tls_security_event');
  assert.ok(event, 'P-BLOCKED must produce a TLS security event');
  assert.equal(event.field('gatewayId'), GATEWAY);
  assert.equal(event.field('profile'), String(TransportProfile.P_BLOCKED));
  assert.equal(event.field('errorCode'), 'GATEWAY_PROFILE_BLOCKED');
});

test('C17_tlsProfileWithMissingPinsSendsNoRequest', async () => {
  const ctx = setup();
  await expectCode(() => ctx.service.control(target(TransportProfile.P_TLS_PIN, []), command()),
    'TLS_PROFILE_INCONSISTENT');
  assert.equal(ctx.transport.requests.length, 0);
});

test('C17_tlsPinMismatchNeverFallsBackToCleartext', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async () => {
    throw AppErrors.of('TLS_PIN_MISMATCH', []);
  });
  await expectCode(() => ctx.service.control(target(TransportProfile.P_TLS_PIN, [PIN_A]), command()),
    'TLS_PIN_MISMATCH');
  assert.equal(ctx.transport.requests.length, 1);
  assert.equal(ctx.transport.requests[0].url.startsWith('https://'), true);
  assert.equal(ctx.transport.tlsPolicies[0].pins[0], PIN_A);
  assert.equal(ctx.transport.tlsPolicies[0].pinAlg, 'sha256-spki-der');
  const event = ctx.logger.records.find((entry) => entry.message === 'tls_security_event');
  assert.ok(event, 'pin mismatch must produce a TLS security event');
  assert.equal(event.field('errorCode'), 'TLS_PIN_MISMATCH');
  assert.equal(event.field('profile'), String(TransportProfile.P_TLS_PIN));
  assert.equal(event.field('atMs'), String(FIXED_MS));
});

test('C17_tlsHandshakeFailureIsLoggedWithoutSecret', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async () => {
    throw AppErrors.of('TLS_HANDSHAKE_FAILED', []);
  });
  await expectCode(() => ctx.service.control(target(TransportProfile.P_TLS_PIN, [PIN_A]), command()),
    'TLS_HANDSHAKE_FAILED');
  const events = ctx.logger.records.filter((entry) => entry.message === 'tls_security_event');
  assert.equal(events.length, 1);
  assert.equal(events[0].field('errorCode'), 'TLS_HANDSHAKE_FAILED');
  assert.equal(JSON.stringify(events[0].fields).includes('0123456789abcdef'), false,
    'security events must not contain secrets');
});

test('C17_tlsProbeReturnsMatchedPinAndRuntimeProfile', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request) => {
    const body = discoverBody();
    const challenge = discoverChallenge(request);
    return new HttpResponse(200, signedResponseHeaders('discover', challenge, body, SECRET), body,
      ctx.clock.nowMs(), new TlsVerification(PIN_A, 'TLSv1.3', PIN_A));
  });
  const result = await ctx.service.probe(target(TransportProfile.P_TLS_PIN, [PIN_A, PIN_B]));
  assert.equal(result.reachable, true);
  assert.equal(result.profile, TransportProfile.P_TLS_PIN);
  assert.equal(result.tlsPinMatched, PIN_A);
  assert.equal(result.snapshot.gatewayId, GATEWAY);
});

// T-11 F-03: the service layer must independently fail closed when a transport
// returns a P-TLS-PIN response without (or with inconsistent) pin evidence.
test('C17_tlsProbeWithoutVerificationEvidenceFailsClosed', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request) => {
    const body = discoverBody();
    return new HttpResponse(200,
      signedResponseHeaders('discover', discoverChallenge(request), body, SECRET), body,
      ctx.clock.nowMs());
  });
  await expectCode(() => ctx.service.probe(target(TransportProfile.P_TLS_PIN, [PIN_A])),
    'TLS_VERIFIER_UNAVAILABLE');
  assert.equal(ctx.transport.requests.length, 1);
  const event = ctx.logger.records.find((entry) => entry.message === 'tls_security_event');
  assert.ok(event);
  assert.equal(event.field('errorCode'), 'TLS_VERIFIER_UNAVAILABLE');
});

test('C17_tlsProbeWithPinOutsideRouteFailsClosed', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request) => {
    const body = discoverBody();
    return new HttpResponse(200,
      signedResponseHeaders('discover', discoverChallenge(request), body, SECRET), body,
      ctx.clock.nowMs(), new TlsVerification(PIN_B, 'TLSv1.3', PIN_B));
  });
  await expectCode(() => ctx.service.probe(target(TransportProfile.P_TLS_PIN, [PIN_A])),
    'TLS_PIN_MISMATCH');
  assert.equal(ctx.transport.requests.length, 1);
});

test('C17_tlsProbeWithInconsistentPeerSpkiFailsClosed', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request) => {
    const body = discoverBody();
    return new HttpResponse(200,
      signedResponseHeaders('discover', discoverChallenge(request), body, SECRET), body,
      ctx.clock.nowMs(), new TlsVerification(PIN_A, 'TLSv1.3', PIN_B));
  });
  await expectCode(() => ctx.service.probe(target(TransportProfile.P_TLS_PIN, [PIN_A])),
    'TLS_HANDSHAKE_FAILED');
  assert.equal(ctx.transport.requests.length, 1);
});

test('C17_tlsControlWithMatchingEvidenceSucceeds', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request) => {
    const parsed = parseRequest(request);
    const body = ackBody(parsed);
    return new HttpResponse(200,
      signedResponseHeaders('control', `${parsed.request_id}:${parsed.seq}`, body, SECRET), body,
      ctx.clock.nowMs(), new TlsVerification(PIN_A, 'TLSv1.3', PIN_A));
  });
  const outcome = await ctx.service.control(target(TransportProfile.P_TLS_PIN, [PIN_A]), command());
  assert.equal(outcome.ackAccepted, true);
  assert.equal(ctx.transport.requests.length, 1);
});

test('C17_cleartextDisabledRefusesHmacWithoutFallback', async () => {
  const ctx = setup(new GatewayRequestPolicy(3000, 5000, 3, 300, 900, 5000, false));
  await expectCode(() => ctx.service.discover(target()), 'CONFIGURATION_ERROR');
  assert.equal(ctx.transport.requests.length, 0);
});

test('C17_sendUsesBoundRouteAndRejectsUnboundGateway', async () => {
  const ctx = setup();
  ctx.transport.setHandler(async (request) => {
    const parsed = parseRequest(request);
    const body = ackBody(parsed);
    return new HttpResponse(200,
      signedResponseHeaders('control', `${parsed.request_id}:${parsed.seq}`, body, SECRET), body,
      ctx.clock.nowMs());
  });
  await expectCode(() => ctx.service.send(command()), 'GATEWAY_NOT_BOUND');
  const init = new GatewayRouteInit();
  init.gatewayId = GATEWAY;
  init.familyId = FAMILY;
  init.gatewayName = 'Mock Gateway';
  init.localIp = '192.168.1.20';
  init.lastKnownIp = '192.168.1.20';
  init.port = 9200;
  init.profile = TransportProfile.P_HMAC;
  init.credentialAlias = ALIAS;
  init.createdAt = FIXED_TS;
  init.updatedAt = FIXED_TS;
  ctx.routes.add(GatewayRoute.create(init));
  const outcome = await ctx.service.send(command());
  assert.equal(outcome.ackAccepted, true);
  assert.equal(ctx.transport.requests.length, 1);
});

test('C17_commandGatewayIdentityMustMatchTarget', async () => {
  const ctx = setup();
  const other = new DeviceControlCommand('gateway_02', 'Light_01', DeviceAction.SET_BRIGHTNESS,
    FIXED_MS, 10);
  await expectCode(() => ctx.service.control(target(), other), 'CONFIGURATION_ERROR');
  assert.equal(ctx.transport.requests.length, 0);
});

test('C17_controlPolicyRejectsLocalUnsupportedAndOutOfRangeActions', () => {
  assert.throws(() => ControlPolicy.validate(undefined, true, DeviceAction.SET_DEVICE_NAME, 'x'),
    (error) => error instanceof AppError && error.code === 'CONFIGURATION_ERROR');
  assert.throws(() => ControlPolicy.validate(undefined, true, DeviceAction.SET_POSITION, 10),
    (error) => error instanceof AppError && error.code === 'CONFIGURATION_ERROR');
  assert.throws(() => ControlPolicy.validate(DeviceType.SENSOR, true, DeviceAction.TURN_ON),
    (error) => error instanceof AppError && error.code === 'CONFIGURATION_ERROR');
  assert.throws(() => ControlPolicy.validate(DeviceType.LIGHT, true, DeviceAction.SET_BRIGHTNESS, 101),
    (error) => error instanceof AppError && error.code === 'PROTOCOL_VALUE_OUT_OF_RANGE');
  assert.throws(() => ControlPolicy.validate(DeviceType.AC, true, DeviceAction.SET_MODE, 'TURBO'),
    (error) => error instanceof AppError && error.code === 'PROTOCOL_VALUE_OUT_OF_RANGE');
  assert.throws(() => ControlPolicy.validate(DeviceType.DOOR, true, DeviceAction.PING),
    (error) => error instanceof AppError && error.code === 'CONFIGURATION_ERROR');
});

test('C17_controlPolicyNormalizesColorAndAcceptsMatrix', () => {
  assert.equal(ControlPolicy.normalizeValue(DeviceAction.SET_COLOR, '#abcdef'), '#ABCDEF');
  assert.doesNotThrow(() => ControlPolicy.validate(DeviceType.LIGHT, true,
    DeviceAction.SET_COLOR, '#ABCDEF'));
  assert.doesNotThrow(() => ControlPolicy.validate(DeviceType.AC, true,
    DeviceAction.SET_TARGET_TEMPERATURE, 24));
  assert.doesNotThrow(() => ControlPolicy.validate(DeviceType.DOOR, true, DeviceAction.OPEN));
  assert.doesNotThrow(() => ControlPolicy.validate(undefined, true, DeviceAction.PING));
});

// T-11 F-11: set-* actions require a value; AC mode is normalized to the
// uppercase AC_MODES vocabulary before signing.
test('C17_controlPolicyRequiresValueForSetActions', () => {
  const required = [
    DeviceAction.SET_BRIGHTNESS,
    DeviceAction.SET_COLOR,
    DeviceAction.SET_TARGET_TEMPERATURE,
    DeviceAction.SET_MODE,
  ];
  for (const action of required) {
    assert.throws(() => ControlPolicy.validate(undefined, true, action),
      (error) => error instanceof AppError && error.code === 'PROTOCOL_VALUE_OUT_OF_RANGE',
      `${action} must require a value`);
  }
  assert.throws(() => ControlPolicy.validate(DeviceType.LIGHT, true,
    DeviceAction.SET_BRIGHTNESS, undefined),
  (error) => error instanceof AppError && error.code === 'PROTOCOL_VALUE_OUT_OF_RANGE');
  assert.throws(() => ControlPolicy.validate(DeviceType.AC, true,
    DeviceAction.SET_MODE, undefined),
  (error) => error instanceof AppError && error.code === 'PROTOCOL_VALUE_OUT_OF_RANGE');
  // Value-less boolean actions stay valid.
  assert.doesNotThrow(() => ControlPolicy.validate(DeviceType.LIGHT, true,
    DeviceAction.TURN_ON, undefined));
});

test('C17_controlPolicyNormalizesAcModeCase', () => {
  assert.equal(ControlPolicy.normalizeValue(DeviceAction.SET_MODE, 'cool'), 'COOL');
  assert.doesNotThrow(() => ControlPolicy.validate(DeviceType.AC, true,
    DeviceAction.SET_MODE, 'cool'));
  assert.throws(() => ControlPolicy.validate(DeviceType.AC, true,
    DeviceAction.SET_MODE, 'TURBO'),
  (error) => error instanceof AppError && error.code === 'PROTOCOL_VALUE_OUT_OF_RANGE');
});
