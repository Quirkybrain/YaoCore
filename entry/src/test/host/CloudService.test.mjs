/*
 * YaoCore C-15 CloudService host tests.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §8.1-§8.5; CB §2.4/§4.2/§7.1; PR-09/PR-10; D-012/D-014; D-019
 *
 * PUBLIC TEST DATA ONLY. All HTTP is a scripted fake; host crypto is an
 * independent Node oracle for HMAC/SHA-256. No device or real IoTDA call.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, createHmac } from 'node:crypto';

import { AppError } from '../../main/ets/common/types/AppError.ets';
import { HttpHeaders } from '../../main/ets/common/types/HttpHeaders.ets';
import { DeviceAction } from '../../main/ets/common/constants/DeviceConstants.ets';
import { StorageConstants } from '../../main/ets/common/constants/StorageConstants.ets';
import { DeviceControlCommand } from '../../main/ets/model/ControlModels.ets';
import { StateVerification } from '../../main/ets/model/ControlModels.ets';
import { CloudConfig } from '../../main/ets/model/FamilyModels.ets';
import {
  ShadowDeviceState,
  ShadowDeviceStateInit,
  ShadowShape,
} from '../../main/ets/model/CloudModels.ets';
import { HostCrypto } from './host-crypto.mjs';
import { HttpResponse } from '../../main/ets/service/gateway/GatewayTransportPorts.ets';
import {
  InMemoryCredentials,
  InMemorySequences,
  RecordingLogger,
  RecordingMetrics,
} from './TransportFakes.ets';
import {
  FakeCloudClock,
  FixedRandom,
  ImmediateCloudTimer,
  InMemoryCloudConfigStore,
  InMemoryCloudCredentials,
  ScriptedCloudTransport,
} from './CloudFakes.ets';
import {
  CloudCommandClient,
  CloudSendRetryPolicy,
} from '../../main/ets/service/cloud/CloudCommandClient.ets';
import {
  CloudCommandExpectation,
  CloudCompletion,
  CloudCompletionPolicy,
  ShadowSnapshot,
  CloudTransportState,
} from '../../main/ets/service/cloud/CloudModels.ets';
import { CloudCompletionEvaluator } from '../../main/ets/service/cloud/CloudCompletionEvaluator.ets';
import { CloudConfigValidator } from '../../main/ets/service/cloud/CloudConfigValidator.ets';
import { CloudService } from '../../main/ets/service/cloud/CloudService.ets';
import { DeviceInventoryParser } from '../../main/ets/service/cloud/DeviceInventoryParser.ets';
import { ShadowReader } from '../../main/ets/service/cloud/ShadowReader.ets';

const NOW = Date.UTC(2026, 9, 17, 8, 0, 0); // 20261017T080000Z
const NOW_TEXT = '20261017T080000Z';
const GATEWAY = 'gateway_01';
const IOTDA_DEVICE = 'gw-device-1';
const PROJECT = 'project-1';
const TOKEN = 'PUBLIC-TEST-TOKEN-ONLY';
const SECRET = Buffer.from('0123456789abcdef', 'utf8'); // PUBLIC TEST DATA ONLY
const NONCE = Uint8Array.from([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]);
const REQUEST_ID = 'req-1790000000000-7';
const FULL_FIXED = () => ({
  Door_01_Online: true,
  Light_01_Online: true,
  Sensor_01_Online: true,
  Presence_01_Online: true,
  AC_01_Online: true,
  Gateway_Online: true,
  Gateway_RSSI: -55,
});

const sha256Hex = (bytes) => createHash('sha256').update(bytes).digest('hex');
const hmacHex = (secret, text) => createHmac('sha256', secret).update(text, 'utf8').digest('hex');
const utf8 = (s) => Buffer.from(s, 'utf8');
const bytes = (s) => new Uint8Array(utf8(s));

const jsonResponse = (status, body) => new HttpResponse(status, HttpHeaders.from([]),
  typeof body === 'string' ? bytes(body) : bytes(JSON.stringify(body)), NOW);

const config = (endpoint = 'https://iotda.example.com') =>
  new CloudConfig(endpoint, PROJECT, IOTDA_DEVICE, StorageConstants.ASSET_CLOUD_TOKEN);

const command = (value = 68) => new DeviceControlCommand(GATEWAY, 'Light_01',
  DeviceAction.SET_BRIGHTNESS, NOW, value);

const stateReport = (properties, eventTime = NOW_TEXT) => ({
  services: [{
    service_id: 'SmartHomeService',
    properties,
    event_time: eventTime,
  }],
});

const lightProperties = (requestId = REQUEST_ID, seq = 7, brightness = 68) => ({
  ...FULL_FIXED(),
  Light_01_Status: 'ON',
  Light_01_Brightness: brightness,
  Light_01_LastRequestId: requestId,
  Light_01_LastSeq: seq,
  Light_01_StateSource: 'app.cloud',
});

const inventoryEntry = (overrides = {}) => ({
  device_id: 'MODULE_01',
  online: true,
  power: true,
  brightness: 68,
  event_time: NOW_TEXT,
  last_request_id: REQUEST_ID,
  last_seq: 7,
  ...overrides,
});

const expectCode = async (fn, code) => {
  await assert.rejects(fn, (error) => {
    assert.ok(error instanceof AppError, `expected AppError, got ${error}`);
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
};

const expectThrowsCode = (fn, code) => {
  assert.throws(fn, (error) => {
    assert.ok(error instanceof AppError, `expected AppError, got ${error}`);
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
};

async function harness(options = {}) {
  const clock = new FakeCloudClock(options.now === undefined ? NOW : options.now);
  const configs = new InMemoryCloudConfigStore(options.config === null ? undefined :
    (options.config === undefined ? config() : options.config));
  const credentials = new InMemoryCloudCredentials(options.token === null ? undefined :
    (options.token === undefined ? TOKEN : options.token), '20261017T075000Z');
  const transport = new ScriptedCloudTransport();
  const gatewayCredentials = new InMemoryCredentials();
  gatewayCredentials.set(GATEWAY, new Uint8Array(SECRET));
  const sequences = new InMemorySequences();
  const logger = new RecordingLogger();
  const metrics = new RecordingMetrics();
  const crypto = new HostCrypto();
  const retryPolicy = options.retryPolicy === undefined ? new CloudSendRetryPolicy(0, 0) :
    options.retryPolicy;
  const client = new CloudCommandClient(transport, configs, credentials, gatewayCredentials,
    sequences, crypto, clock, new FixedRandom(NONCE), logger, retryPolicy);
  const shadowReader = new ShadowReader(transport, configs, credentials, crypto, clock, logger);
  const policy = options.policy === undefined ? CloudCompletionPolicy.defaults() :
    options.policy;
  const evaluator = new CloudCompletionEvaluator(clock, policy);
  const timer = new ImmediateCloudTimer();
  const service = new CloudService(configs, credentials, client, shadowReader, evaluator,
    clock, timer, logger, metrics);
  return { clock, configs, credentials, transport, gatewayCredentials, sequences, logger,
    metrics, crypto, client, shadowReader, evaluator, timer, service, policy };
}

async function readShadow(env, properties, eventTime = NOW_TEXT) {
  env.transport.enqueue(jsonResponse(200, stateReport(properties, eventTime)));
  return env.shadowReader.read(GATEWAY);
}

test('C15_cloudCommand_exactEnvelopeCanonicalAndHmac', async () => {
  const env = await harness();
  env.transport.enqueue(jsonResponse(200, { command_id: 'cmd-1' }));
  const receipt = await env.client.send(command());

  assert.equal(env.transport.requests.length, 1);
  const request = env.transport.requests[0];
  assert.equal(request.method, 'POST');
  assert.equal(request.url, 'https://iotda.example.com/v5/iot/' + PROJECT + '/devices/' +
    IOTDA_DEVICE + '/commands');
  assert.equal(request.headers.get('X-Auth-Token'), TOKEN);
  assert.equal(request.headers.get('Accept'), 'application/json');
  assert.equal(request.headers.get('Content-Type'), 'application/json');

  const body = JSON.parse(new TextDecoder().decode(request.body));
  assert.deepEqual(Object.keys(body), ['service_id', 'command_name', 'paras']);
  assert.equal(body.object_device_id, undefined);
  assert.equal(body.service_id, 'SmartHomeService');
  assert.equal(body.command_name, 'SetDeviceStatus');
  assert.deepEqual(Object.keys(body.paras), [
    'RequestId', 'CmdId', 'Seq', 'TargetDevice', 'Action', 'Value',
    'Timestamp', 'Nonce', 'Alg', 'KeyId', 'Sign',
  ]);
  assert.equal(body.paras.CmdId, 3001);
  assert.equal(body.paras.Seq, 0);
  assert.equal(body.paras.TargetDevice, 'Light_01');
  assert.equal(body.paras.Action, 'SET_BRIGHTNESS');
  assert.equal(body.paras.Value, '68');
  assert.equal(body.paras.Timestamp, NOW_TEXT);
  assert.equal(body.paras.Nonce, '000102030405060708090a0b0c0d0e0f');
  assert.equal(body.paras.Alg, 'HMAC-SHA256');
  assert.equal(body.paras.KeyId, 'app-key-v1');
  assert.ok(!new TextDecoder().decode(request.body).includes('object_device_id'));

  const canonical = [
    body.paras.RequestId,
    String(body.paras.CmdId),
    String(body.paras.Seq),
    body.paras.TargetDevice,
    body.paras.Action,
    body.paras.Value,
    body.paras.Timestamp,
    body.paras.Nonce,
    body.paras.Alg,
    body.paras.KeyId,
  ].join('\n');
  assert.equal(body.paras.Sign, hmacHex(SECRET, canonical));

  assert.equal(receipt.gatewayId, GATEWAY);
  assert.equal(receipt.requestId, body.paras.RequestId);
  assert.equal(receipt.seq, 0);
  assert.equal(receipt.httpStatus, 200);
  assert.equal(receipt.acceptedAtMs, NOW);
  assert.equal(receipt.commandId, 'cmd-1');
  assert.match(receipt.responseBodySha256, /^[0-9a-f]{64}$/);
});

test('C15_cloudCommand_missingConfigTokenAndValidation', async () => {
  const noConfig = await harness({ config: null });
  await expectCode(() => noConfig.client.send(command()), 'CLOUD_NOT_CONFIGURED');
  assert.equal(noConfig.transport.requests.length, 0);

  const noToken = await harness({ token: null });
  await expectCode(() => noToken.client.send(command()), 'CLOUD_TOKEN_MISSING');
  assert.equal(noToken.transport.requests.length, 0);

  const emptyToken = await harness({ token: '' });
  await expectCode(() => emptyToken.client.send(command()), 'CLOUD_TOKEN_MISSING');
  assert.equal(emptyToken.transport.requests.length, 0);

  const valid = CloudConfigValidator.validate(config());
  assert.equal(valid.valid, true);
  assert.equal(valid.commandEndpoint, 'https://iotda.example.com/v5/iot/' + PROJECT +
    '/devices/' + IOTDA_DEVICE + '/commands');
  assert.equal(valid.shadowEndpoint, 'https://iotda.example.com/v5/iot/' + PROJECT +
    '/devices/' + IOTDA_DEVICE + '/shadow');

  const base = {
    endpoint: 'https://iotda.example.com',
    projectId: PROJECT,
    deviceId: IOTDA_DEVICE,
    accessTokenAlias: StorageConstants.ASSET_CLOUD_TOKEN,
  };
  for (const endpoint of ['http://iotda.example.com', 'https://iotda.example.com/path',
    'https://iotda.example.com?x=1', 'https://iotda.example.com:70000',
    'https://user@iotda.example.com', '']) {
    const result = CloudConfigValidator.validate({ ...base, endpoint });
    assert.equal(result.valid, false, endpoint);
    assert.equal(result.errors[0].code, 'CLOUD_ENDPOINT_INVALID');
  }
  const badId = CloudConfigValidator.validate({ ...base, projectId: 'bad id' });
  assert.equal(badId.valid, false);
  assert.equal(badId.errors[0].code, 'PROTOCOL_INVALID_IDENTIFIER');
  const badAlias = CloudConfigValidator.validate({ ...base, accessTokenAlias: 'other' });
  assert.equal(badAlias.valid, false);
  assert.equal(badAlias.errors[0].code, 'CONFIGURATION_ERROR');
  const badShadow = CloudConfigValidator.validate({ ...base,
    shadowEndpoint: 'http://shadow.example.com' });
  assert.equal(badShadow.valid, false);
  assert.equal(badShadow.errors[0].code, 'CLOUD_ENDPOINT_INVALID');
});

test('C15_responseMapping_2xxReceiptOnlyAndHttpErrors', async () => {
  const cases = [
    [401, 'CLOUD_TOKEN_EXPIRED'],
    [403, 'CLOUD_TOKEN_INVALID'],
    [404, 'CLOUD_DEVICE_NOT_FOUND'],
    [429, 'CLOUD_RATE_LIMITED'],
    [500, 'CLOUD_SERVICE_UNAVAILABLE'],
    [503, 'CLOUD_SERVICE_UNAVAILABLE'],
    [400, 'CLOUD_RESPONSE_INVALID'],
    [408, 'CLOUD_REQUEST_FAILED'],
  ];
  for (const [status, code] of cases) {
    const env = await harness();
    env.transport.enqueue(jsonResponse(status, { error_code: 'E' + status,
      error_msg: 'diagnostic only' }));
    const error = await env.client.send(command()).catch((value) => value);
    assert.ok(error instanceof AppError, `status ${status}`);
    assert.equal(error.code, code, `status ${status}`);
    assert.equal(env.transport.requests.length, 1, 'no retry for ' + status);
    for (const detail of error.details) {
      assert.notEqual(detail.value, TOKEN);
    }
  }

  const env = await harness();
  env.transport.enqueue(jsonResponse(200, 'not-json'));
  const receipt = await env.client.send(command());
  assert.equal(receipt.httpStatus, 200);
  assert.equal(receipt.commandId, undefined);
  assert.ok(env.logger.records.some((record) => record.message === 'CLOUD_RESPONSE_INVALID'));

  const retry = await harness({ retryPolicy: new CloudSendRetryPolicy(1, 0) });
  retry.transport.enqueue(jsonResponse(500, {}));
  retry.transport.enqueue(jsonResponse(200, { command_id: 'cmd-after-retry' }));
  const retried = await retry.client.send(command());
  assert.equal(retry.transport.requests.length, 2);
  assert.equal(retried.commandId, 'cmd-after-retry');
  assert.deepEqual(retry.transport.requests[0].body, retry.transport.requests[1].body);
  assert.deepEqual(retry.transport.requests[0].headers.entries(),
    retry.transport.requests[1].headers.entries());

  const noRetry401 = await harness({ retryPolicy: new CloudSendRetryPolicy(1, 0) });
  noRetry401.transport.enqueue(jsonResponse(401, {}));
  await expectCode(() => noRetry401.client.send(command()), 'CLOUD_TOKEN_EXPIRED');
  assert.equal(noRetry401.transport.requests.length, 1);
});

test('C15_shadow_threeShapesAndStrictInvalidCases', async () => {
  const env = await harness();

  const services = await readShadow(env, {
    ...FULL_FIXED(),
    Light_01_Status: 'ON',
    Light_01_Brightness: 68,
    Light_01_LastRequestId: REQUEST_ID,
    Light_01_LastSeq: 7,
    DeviceInventoryJson: JSON.stringify([inventoryEntry()]),
  });
  assert.equal(services.shape, ShadowShape.SERVICES);
  assert.equal(services.eventTime, NOW_TEXT);
  assert.equal(services.eventEpochMs, NOW);
  assert.equal(services.fixedDevices.some((item) => item.deviceId === 'Light_01'), true);
  assert.equal(services.deviceInventory.length, 1);
  assert.equal(services.deviceInventory[0].deviceId, 'MODULE_01');
  assert.equal(services.inventoryUnsupported, false);
  assert.match(services.rawSha256, /^[0-9a-f]{64}$/);

  env.transport.enqueue(jsonResponse(200, {
    shadow: [{
      service_id: 'SmartHomeService',
      reported: {
        properties: { Light_01_Online: true, Light_01_Status: 'ON' },
        event_time: NOW_TEXT,
      },
    }],
  }));
  const shadow = await env.shadowReader.read(GATEWAY);
  assert.equal(shadow.shape, ShadowShape.SHADOW);
  assert.equal(shadow.fixedDevices[0].power, true);

  env.transport.enqueue(jsonResponse(200, {
    devices: [{
      device_id: 'Light_01',
      online: true,
      power: true,
      brightness: 68,
      event_time: NOW_TEXT,
      last_request_id: REQUEST_ID,
      last_seq: 7,
    }],
  }));
  const devices = await env.shadowReader.read(GATEWAY);
  assert.equal(devices.shape, ShadowShape.DEVICES);
  assert.equal(devices.fixedDevices[0].brightness, 68);

  for (const body of [
    { foo: 1 },
    { services: [{ service_id: 'SmartHomeService', properties: { Light_01_Online: true } }] },
    { services: [{ service_id: 'SmartHomeService', properties: FULL_FIXED(),
      event_time: '2026-10-17T08:00:00Z' }] },
    { services: [{ service_id: 'SmartHomeService', properties: [], event_time: NOW_TEXT }] },
  ]) {
    env.transport.enqueue(jsonResponse(200, body));
    await expectCode(() => env.shadowReader.read(GATEWAY), 'CLOUD_SHADOW_INVALID');
  }

  env.transport.enqueue(jsonResponse(200, stateReport(FULL_FIXED(), '20261017T081000Z')));
  await expectCode(() => env.shadowReader.read(GATEWAY), 'CLOUD_SHADOW_INVALID');

  const oversized = 'x'.repeat(65537);
  env.transport.enqueue(jsonResponse(200, oversized));
  await expectCode(() => env.shadowReader.read(GATEWAY), 'CLOUD_SHADOW_INVALID');

  const malformed = await readShadow(env, {
    ...FULL_FIXED(),
    Light_01_LastRequestId: REQUEST_ID,
    Light_01_LastSeq: 7,
    DeviceInventoryJson: '[{"device_id":',
  });
  assert.equal(malformed.inventoryUnsupported, true);
  assert.equal(malformed.deviceInventory.length, 0);
  assert.ok(env.logger.records.some((record) =>
    record.message === 'CLOUD_INVENTORY_UNSUPPORTED'));

  env.transport.enqueue(jsonResponse(401, {}));
  await expectCode(() => env.shadowReader.read(GATEWAY), 'CLOUD_TOKEN_EXPIRED');
});

test('C15_completion_builtInDoubleMatchStaleAndVerification', async () => {
  const env = await harness();
  const expectation = new CloudCommandExpectation(GATEWAY, 'Light_01',
    DeviceAction.SET_BRIGHTNESS, 68, REQUEST_ID, 7, NOW);

  const fresh = await readShadow(env, lightProperties());
  const confirmed = env.evaluator.evaluate(expectation, fresh);
  assert.equal(confirmed.completion, CloudCompletion.CONFIRMED);
  assert.equal(confirmed.stateVerification, StateVerification.MATCH);
  assert.equal(confirmed.matchedRequestId, REQUEST_ID);
  assert.equal(confirmed.matchedSeq, 7);
  assert.equal(confirmed.reportedState.brightness, 68);

  const seqOnly = await readShadow(env, lightProperties(REQUEST_ID, 8));
  const pendingSeq = env.evaluator.evaluate(expectation, seqOnly);
  assert.equal(pendingSeq.completion, CloudCompletion.PENDING);
  assert.equal(pendingSeq.reason.startsWith('REQUEST_ID_MATCHED'), true);

  const requestOnly = await readShadow(env, lightProperties('req-other-1', 7));
  const pendingRequest = env.evaluator.evaluate(expectation, requestOnly);
  assert.equal(pendingRequest.completion, CloudCompletion.PENDING);
  assert.equal(pendingRequest.reason.startsWith('SEQ_MATCHED'), true);

  const neither = await readShadow(env, lightProperties('req-other-1', 8));
  assert.equal(env.evaluator.evaluate(expectation, neither).completion,
    CloudCompletion.PENDING);

  const stale = await readShadow(env, lightProperties(REQUEST_ID, 7, 68),
    '20261017T075957Z'); // 3s before notBefore, outside 2s tolerance
  assert.equal(env.evaluator.evaluate(expectation, stale).completion,
    CloudCompletion.STALE);

  const boundary = await readShadow(env, lightProperties(REQUEST_ID, 7, 68),
    '20261017T075958Z'); // exactly 2s before notBefore => fresh
  assert.equal(env.evaluator.evaluate(expectation, boundary).completion,
    CloudCompletion.CONFIRMED);

  const mismatch = await readShadow(env, lightProperties(REQUEST_ID, 7, 40));
  const mismatchVerdict = env.evaluator.evaluate(expectation, mismatch);
  assert.equal(mismatchVerdict.completion, CloudCompletion.CONFIRMED);
  assert.equal(mismatchVerdict.stateVerification, StateVerification.MISMATCH);

  const sensor = new CloudCommandExpectation(GATEWAY, 'Sensor_01',
    DeviceAction.SET_TARGET_TEMPERATURE, 24, REQUEST_ID, 7, NOW);
  assert.equal(env.evaluator.evaluate(sensor, fresh).completion,
    CloudCompletion.UNSUPPORTED);

  const gateway = new CloudCommandExpectation(GATEWAY, 'Gateway',
    DeviceAction.TURN_ON, undefined, REQUEST_ID, 7, NOW);
  const gatewayVerdict = env.evaluator.evaluate(gateway, fresh);
  assert.equal(gatewayVerdict.completion, CloudCompletion.UNSUPPORTED);
  assert.equal(gatewayVerdict.error.code, 'CLOUD_INVENTORY_UNSUPPORTED');

  const futureInit = new ShadowDeviceStateInit();
  futureInit.deviceId = 'Light_01';
  futureInit.eventTime = '20261017T080600Z';
  futureInit.online = true;
  const futureState = ShadowDeviceState.create(futureInit);
  const futureShadow = new ShadowSnapshot(IOTDA_DEVICE, '20261017T080600Z', [],
    [futureState], [], NOW, 'a'.repeat(64), ShadowShape.SERVICES);
  const futureVerdict = env.evaluator.evaluate(expectation, futureShadow);
  assert.equal(futureVerdict.completion, CloudCompletion.INVALID);
  assert.equal(futureVerdict.error.code, 'CLOUD_SHADOW_INVALID');

  const color = new CloudCommandExpectation(GATEWAY, 'Light_01',
    DeviceAction.SET_COLOR, '#FF0000', REQUEST_ID, 7, NOW);
  assert.equal(env.evaluator.evaluate(color, fresh).stateVerification,
    StateVerification.UNVERIFIED);
  const nonStandardMode = new CloudCommandExpectation(GATEWAY, 'AC_01',
    DeviceAction.SET_MODE, 'TURBO', REQUEST_ID, 7, NOW);
  assert.equal(env.evaluator.evaluate(nonStandardMode, fresh).completion,
    CloudCompletion.PENDING);
});

test('C15_inventory_candidateMatchAndFailClosed', async () => {
  const env = await harness();
  const expectation = new CloudCommandExpectation(GATEWAY, 'MODULE_01',
    DeviceAction.SET_BRIGHTNESS, 68, REQUEST_ID, 7, NOW);

  const candidate = await readShadow(env, {
    ...FULL_FIXED(),
    DeviceInventoryJson: JSON.stringify([inventoryEntry()]),
  });
  const confirmed = env.evaluator.evaluate(expectation, candidate);
  assert.equal(confirmed.completion, CloudCompletion.CONFIRMED);
  assert.equal(confirmed.reason, 'CONFIRMED_INVENTORY');
  assert.equal(confirmed.stateVerification, StateVerification.MATCH);
  assert.equal(confirmed.reportedState.deviceId, 'MODULE_01');

  const missingSeq = await readShadow(env, {
    ...FULL_FIXED(),
    DeviceInventoryJson: JSON.stringify([inventoryEntry({ last_seq: undefined })]),
  });
  assert.equal(missingSeq.inventoryUnsupported, true);
  const unsupported = env.evaluator.evaluate(expectation, missingSeq);
  assert.equal(unsupported.completion, CloudCompletion.UNSUPPORTED);
  assert.equal(unsupported.error.code, 'CLOUD_INVENTORY_UNSUPPORTED');

  const absent = await readShadow(env, FULL_FIXED());
  const missingEntry = env.evaluator.evaluate(expectation, absent);
  assert.equal(missingEntry.completion, CloudCompletion.UNSUPPORTED);
  assert.equal(missingEntry.reason, 'INVENTORY_ENTRY_MISSING');

  const unknownField = await readShadow(env, {
    ...FULL_FIXED(),
    DeviceInventoryJson: JSON.stringify([inventoryEntry({ future_field: true })]),
  });
  assert.equal(unknownField.inventoryUnsupported, false);
  assert.equal(env.evaluator.evaluate(expectation, unknownField).completion,
    CloudCompletion.CONFIRMED);
  assert.ok(env.logger.records.some((record) =>
    record.message === 'CLOUD_INVENTORY_FIELD_IGNORED'));

  const staleEntry = await readShadow(env, {
    ...FULL_FIXED(),
    DeviceInventoryJson: JSON.stringify([inventoryEntry({
      event_time: '20261017T075957Z',
    })]),
  });
  assert.equal(env.evaluator.evaluate(expectation, staleEntry).completion,
    CloudCompletion.PENDING);

  expectThrowsCode(() => DeviceInventoryParser.parse('[]1'), 'CLOUD_INVENTORY_UNSUPPORTED');
  expectThrowsCode(() => DeviceInventoryParser.parse(JSON.stringify([inventoryEntry({
    last_request_id: undefined,
  })])), 'CLOUD_INVENTORY_UNSUPPORTED');
  expectThrowsCode(() => DeviceInventoryParser.parse(JSON.stringify([inventoryEntry({
    last_seq: 1.5,
  })])), 'CLOUD_INVENTORY_UNSUPPORTED');
  expectThrowsCode(() => DeviceInventoryParser.parse(JSON.stringify([
    inventoryEntry(), inventoryEntry(),
  ])), 'CLOUD_INVENTORY_UNSUPPORTED');
  expectThrowsCode(() => DeviceInventoryParser.parse(JSON.stringify(
    Array.from({ length: 33 }, (_, index) => inventoryEntry({ device_id: 'M_' + index })))),
  'CLOUD_INVENTORY_UNSUPPORTED');
  expectThrowsCode(() => DeviceInventoryParser.parse('x'.repeat(8193)),
    'CLOUD_INVENTORY_UNSUPPORTED');
});

test('C15_service_configTokenStateAndTestConnection', async () => {
  const env = await harness({ config: null, token: '' });
  assert.equal((await env.service.getState()).state, CloudTransportState.NOT_CONFIGURED);

  await env.service.saveConfig(config());
  assert.equal((await env.service.getState()).state, CloudTransportState.TOKEN_MISSING);

  await env.service.saveConfig(config(), TOKEN);
  assert.equal((await env.service.getState()).state, CloudTransportState.CONFIGURED);
  assert.equal(env.credentials.puts, 1);
  assert.equal(env.configs.saves, 2);

  await env.service.clearToken();
  assert.equal((await env.service.getState()).state, CloudTransportState.TOKEN_MISSING);
  await env.service.saveConfig(config(), TOKEN);

  env.transport.enqueue(jsonResponse(200, stateReport(FULL_FIXED())));
  const tested = await env.service.testConnection();
  assert.equal(tested.valid, true);
  assert.equal((await env.service.getState()).state, CloudTransportState.CONFIGURED);

  env.transport.enqueue(jsonResponse(401, {}));
  const failed = await env.service.testConnection();
  assert.equal(failed.valid, false);
  assert.equal(failed.errors[0].code, 'CLOUD_TOKEN_EXPIRED');
  assert.equal((await env.service.getState()).state, CloudTransportState.CONFIGURED);

  env.transport.enqueue(jsonResponse(401, {}));
  await expectCode(() => env.service.send(command()), 'CLOUD_TOKEN_EXPIRED');
  assert.equal((await env.service.getState()).state, CloudTransportState.TOKEN_EXPIRED);

  await env.service.saveConfig(config(), 'NEW-PUBLIC-TEST-TOKEN');
  assert.equal((await env.service.getState()).state, CloudTransportState.CONFIGURED);

  await env.service.clearConfig();
  assert.equal((await env.service.getState()).state, CloudTransportState.NOT_CONFIGURED);
  assert.equal(env.credentials.token, undefined);

  await expectCode(() => env.service.saveConfig({ ...config(), endpoint: 'http://x' }),
    'CLOUD_ENDPOINT_INVALID');
});

test('C15_sendAndConfirm_acceptanceIsNotCompletion', async () => {
  const env = await harness({ policy: new CloudCompletionPolicy(0, 1, 30000, 3, 2000) });
  const expectedRequestId = 'req-' + NOW + '-0';
  env.transport.enqueue(jsonResponse(200, { command_id: 'cmd-1' }));
  env.transport.enqueue(jsonResponse(200, stateReport(lightProperties(expectedRequestId, 1))));
  env.transport.enqueue(jsonResponse(200, stateReport(lightProperties(expectedRequestId, 0))));

  const outcome = await env.service.sendAndConfirm(command());
  assert.equal(outcome.receipt.httpStatus, 200);
  assert.equal(outcome.receipt.commandId, 'cmd-1');
  assert.equal(outcome.verdict.completion, CloudCompletion.CONFIRMED);
  assert.equal(outcome.executionAccepted, true);
  assert.equal(outcome.elapsedMs >= 0, true);
  assert.equal(env.transport.requests.length, 3);

  const timeoutEnv = await harness({
    policy: new CloudCompletionPolicy(0, 1, 30000, 2, 2000),
  });
  timeoutEnv.transport.enqueue(jsonResponse(202, {}));
  timeoutEnv.transport.enqueue(jsonResponse(200, stateReport(lightProperties('req-other', 9))));
  timeoutEnv.transport.enqueue(jsonResponse(200, stateReport(lightProperties('req-other', 9))));
  const timedOut = await timeoutEnv.service.sendAndConfirm(command(), timeoutEnv.policy);
  assert.equal(timedOut.executionAccepted, false);
  assert.equal(timedOut.verdict.completion, CloudCompletion.PENDING);
  assert.equal(timedOut.error.code, 'CLOUD_COMPLETION_TIMEOUT');

  const tokenEnv = await harness({ policy: new CloudCompletionPolicy(0, 1, 30000, 3, 2000) });
  tokenEnv.transport.enqueue(jsonResponse(200, {}));
  tokenEnv.transport.enqueue(jsonResponse(401, {}));
  await expectCode(() => tokenEnv.service.sendAndConfirm(command(), tokenEnv.policy),
    'CLOUD_TOKEN_EXPIRED');
  assert.equal((await tokenEnv.service.getState()).state, CloudTransportState.TOKEN_EXPIRED);
});

test('C15_stopPollingCancelDisposeAndSubscription', async () => {
  const env = await harness({ policy: new CloudCompletionPolicy(1, 1, 30000, 3, 2000) });
  env.transport.enqueue(jsonResponse(200, {}));
  env.transport.enqueue(jsonResponse(200, stateReport(lightProperties('req-other', 9))));
  env.transport.enqueue(jsonResponse(200, stateReport(lightProperties(REQUEST_ID, 7))));

  const events = [];
  const unsubscribe = env.service.subscribe((event) => events.push(event));
  await env.service.saveConfig(config(), TOKEN);
  assert.equal(events.length, 1);
  assert.equal(events[0].revision, 1);
  unsubscribe();
  await env.service.saveConfig(config(), TOKEN);
  assert.equal(events.length, 1);

  env.timer.onSleep = () => env.service.stopPolling();
  await expectCode(() => env.service.sendAndConfirm(command()), 'PROVISIONING_CANCELLED');
  assert.ok(env.timer.cancelled >= 1);

  env.service.dispose();
  await expectCode(() => env.service.send(command()), 'INTERNAL_ERROR');
});

test('C15_receiptSyntheticAndNoTokenLeakInDetails', async () => {
  const env = await harness();
  const expectation = new CloudCommandExpectation(GATEWAY, 'Light_01',
    DeviceAction.SET_BRIGHTNESS, 68, REQUEST_ID, 7, NOW);
  env.transport.enqueue(jsonResponse(200, stateReport(lightProperties())));
  const outcome = await env.service.awaitCompletion(expectation);
  assert.equal(outcome.receipt.httpStatus, 0);
  assert.equal(outcome.receipt.requestId, REQUEST_ID);
  assert.equal(outcome.verdict.completion, CloudCompletion.CONFIRMED);
  for (const record of env.logger.records) {
    for (const field of record.fields) {
      assert.notEqual(field.value, TOKEN);
    }
  }
});
