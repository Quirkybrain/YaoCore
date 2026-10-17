/*
 * YaoCore C-19 GATT/state-machine/Wi-Fi-flow/binding-probe host tests.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Traceability: DES-A §16.2/§16.3/§16.7/§16.8/§16.9; BLE设计 §2/§3/§5/§7.
 *
 * PUBLIC TEST DATA ONLY. No platform BLE/crypto, no real gateway.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { AppError } from '../../main/ets/common/types/AppError.ets';
import { BleDescriptorRef } from '../../main/ets/service/ble/BleProvisioningPorts.ets';
import { GattEndpointMap } from '../../main/ets/service/ble/GattEndpointMap.ets';
import { GattRequestQueue } from '../../main/ets/service/ble/GattRequestQueue.ets';
import { GattChannel } from '../../main/ets/service/ble/GattChannel.ets';
import { ProtoVerParser } from '../../main/ets/service/ble/ProtoVerParser.ets';
import {
  Security1Session,
} from '../../main/ets/service/ble/Security1Session.ets';
import {
  ProvisioningEvent,
  ProvisioningStateMachine,
} from '../../main/ets/service/ble/ProvisioningStateMachine.ets';
import { ProvisioningState } from '../../main/ets/service/ble/BleProvisioningPorts.ets';
import { WifiProvisioningFlow } from '../../main/ets/service/ble/WifiProvisioningFlow.ets';
import {
  ProtocommCodec,
  WifiConfig,
} from '../../main/ets/service/ble/ProtocommCodec.ets';
import { BindingProber } from '../../main/ets/service/ble/BindingProbe.ets';
import {
  BleProvisioningIdentity,
  IdentityVersion,
  ProvisioningTlsMaterial,
} from '../../main/ets/model/ProvisioningModels.ets';
import { ProtobufWriter } from '../../main/ets/service/ble/Protobuf.ets';
import {
  FakeBleConnection,
  FakeClock,
  FakeCredentials,
  FakeGateway,
  FakeGatewayClient,
  GATEWAY_ID,
  GATEWAY_NAME,
  NodeCryptoPort,
  PIN,
  SECRET_HEX,
  fakeDelay,
  makeDraftStore,
  putDraft,
  readFields,
  fieldBytes,
  fieldVarint,
  utf8,
} from './BleFakes.mjs';

const GATEWAY_UID = GattEndpointMap.SERVICE_UUID;

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

async function validMap(connection) {
  const characteristics = await connection.discoverCharacteristics(GATEWAY_UID);
  const descriptors = new Map();
  for (const characteristic of characteristics) {
    try {
      const raw = await connection.readDescriptor(new BleDescriptorRef(
        characteristic.serviceUuid, characteristic.characteristicUuid,
        GattEndpointMap.USER_DESCRIPTION_UUID));
      descriptors.set(characteristic.serviceUuid + '|' + characteristic.characteristicUuid, raw);
    } catch (error) {
      // The service maps an unreadable 0x2901 to GATT_INCOMPLETE; the map
      // builder sees the missing descriptor entry and fails closed.
    }
  }
  return { characteristics, descriptors };
}

// ---- GattEndpointMap ------------------------------------------------------

test('C19_GattEndpointMap_buildsEndpointMapFrom2901Descriptions', async () => {
  const connection = new FakeBleConnection(new FakeGateway());
  const { characteristics, descriptors } = await validMap(connection);
  const map = GattEndpointMap.build(characteristics, descriptors);
  assert.equal(map.get('proto-ver').characteristicUuid, 'char-proto-ver');
  assert.equal(map.get('yaocore-id').characteristicUuid, 'char-yaocore-id');
  assert.equal(map.requiresDoneEndpoint(), true);
  assert.equal(map.endpoints().length, 7);
});

test('C19_GattEndpointMap_missingRequiredEndpointFailsClosed', async () => {
  const connection = new FakeBleConnection(new FakeGateway());
  const { characteristics, descriptors } = await validMap(connection);
  const filtered = characteristics.filter((entry) => entry.characteristicUuid !== 'char-prov-scan');
  expectCodeSync(() => GattEndpointMap.build(filtered, descriptors),
    'PROVISIONING_GATT_INCOMPLETE');
});

test('C19_GattEndpointMap_duplicateEndpointFailsClosed', async () => {
  const connection = new FakeBleConnection(new FakeGateway(), { duplicateEndpoint: true });
  const { characteristics, descriptors } = await validMap(connection);
  expectCodeSync(() => GattEndpointMap.build(characteristics, descriptors),
    'PROVISIONING_GATT_INCOMPLETE');
});

test('C19_GattEndpointMap_unreadableDescriptorFailsClosed', async () => {
  const connection = new FakeBleConnection(new FakeGateway(), { missingDescriptor: true });
  const { characteristics, descriptors } = await validMap(connection);
  expectCodeSync(() => GattEndpointMap.build(characteristics, descriptors),
    'PROVISIONING_GATT_INCOMPLETE');
});

test('C19_GattEndpointMap_characteristicWithoutWriteFailsClosed', async () => {
  const connection = new FakeBleConnection(new FakeGateway(), { readOnlyCharacteristic: true });
  const { characteristics, descriptors } = await validMap(connection);
  expectCodeSync(() => GattEndpointMap.build(characteristics, descriptors),
    'PROVISIONING_GATT_INCOMPLETE');
});

test('C19_GattEndpointMap_unknownEndpointIsIgnoredAndDoneIsOptional', async () => {
  const connection = new FakeBleConnection(new FakeGateway());
  const { characteristics, descriptors } = await validMap(connection);
  descriptors.set(GATEWAY_UID + '|char-yaocore-done', utf8('future-endpoint'));
  const map = GattEndpointMap.build(characteristics, descriptors);
  assert.equal(map.requiresDoneEndpoint(), false);
  assert.equal(map.has('future-endpoint'), true);
  expectCodeSync(() => map.get('yaocore-done'), 'PROVISIONING_GATT_INCOMPLETE');
});

// ---- ProtoVerParser -------------------------------------------------------

const validProtoVer = () => JSON.stringify({
  prov: { ver: 'v1.1', sec_ver: 1, cap: ['wifi_scan'] },
  yaocore: { ver: '2.0' },
});

test('C19_ProtoVerParser_validCapabilityGate', () => {
  const info = ProtoVerParser.parse(utf8(validProtoVer()));
  assert.equal(info.provVersion, 'v1.1');
  assert.equal(info.secVer, 1);
  assert.equal(info.supportsWifiScan, true);
  assert.equal(info.yaoCoreVersion, '2.0');
});

test('C19_ProtoVerParser_acceptsTopLevelSecVerAndStringYaoCore', () => {
  const payload = JSON.stringify({
    prov: { ver: 'v1.1.3', cap: ['wifi_scan'] },
    sec_ver: 1,
    yaocore: '2.0',
  });
  assert.equal(ProtoVerParser.parse(utf8(payload)).yaoCoreVersion, '2.0');
});

test('C19_ProtoVerParser_missingProvVerAndShapeFailCapabilityGate', () => {
  const cases = [
    // missing prov.ver
    JSON.stringify({ prov: { sec_ver: 1, cap: ['wifi_scan'] }, yaocore: '2.0' }),
    // prov is an array, not an object
    JSON.stringify({ prov: [], sec_ver: 1, yaocore: '2.0' }),
    // missing sec_ver
    JSON.stringify({ prov: { ver: 'v1.1', cap: ['wifi_scan'] }, yaocore: '2.0' }),
  ];
  for (const payload of cases) {
    expectCodeSync(() => ProtoVerParser.parse(utf8(payload)),
      'PROVISIONING_CAPABILITY_UNSUPPORTED');
  }
});

test('C19_ProtoVerParser_downgradeAndMissingCapabilitiesFailClosed', () => {
  const cases = [
    JSON.stringify({ prov: { ver: 'v1.1', cap: ['wifi_scan'], no_sec: true }, sec_ver: 1, yaocore: '2.0' }),
    JSON.stringify({ prov: { ver: 'v1.1', cap: ['wifi_scan'], no_pop: true }, sec_ver: 1, yaocore: '2.0' }),
    JSON.stringify({ prov: { ver: 'v1.1', cap: [] }, sec_ver: 1, yaocore: '2.0' }),
    JSON.stringify({ prov: { ver: 'v1.1', cap: ['wifi_scan', 'no_sec'] }, sec_ver: 1, yaocore: '2.0' }),
    JSON.stringify({ prov: { ver: 'v1.1', cap: ['wifi_scan'] }, sec_ver: 0, yaocore: '2.0' }),
    JSON.stringify({ prov: { ver: 'v1.1', cap: ['wifi_scan'] }, yaocore: '2.0' }),
    JSON.stringify({ prov: { ver: 'v1.1', cap: ['wifi_scan'] }, sec_ver: 1, yaocore: '1.0' }),
    'not-json',
  ];
  for (const payload of cases) {
    expectCodeSync(() => ProtoVerParser.parse(utf8(payload)),
      'PROVISIONING_CAPABILITY_UNSUPPORTED');
  }
});

// ---- GattRequestQueue -----------------------------------------------------

test('C19_GattRequestQueue_serializesWriteReadPairs', async () => {
  const queue = new GattRequestQueue(1000);
  const events = [];
  const first = queue.run(async () => {
    events.push('a-start');
    await new Promise((resolve) => setTimeout(resolve, 5));
    events.push('a-end');
    return 1;
  });
  const second = queue.run(async () => {
    events.push('b-start');
    return 2;
  });
  assert.deepEqual(await Promise.all([first, second]), [1, 2]);
  assert.deepEqual(events, ['a-start', 'a-end', 'b-start']);
  queue.destroy();
});

test('C19_GattRequestQueue_timeoutAndDestroyFailClosed', async () => {
  const queue = new GattRequestQueue(10);
  await expectCode(() => queue.run(() => new Promise(() => {})), 'PROVISIONING_GATT_BUSY');
  const destroyed = new GattRequestQueue(100);
  destroyed.destroy();
  await expectCode(() => destroyed.run(async () => 1), 'PROVISIONING_GATT_BUSY');
});

test('C19_GattRequestQueue_timeoutNeverStartsConcurrentOperation', async () => {
  const queue = new GattRequestQueue(10);
  const events = [];
  const first = queue.run(async () => {
    events.push('a-start');
    await new Promise((resolve) => setTimeout(resolve, 50));
    events.push('a-end');
    return 'a';
  });
  const second = queue.run(async () => {
    events.push('b-start');
    return 'b';
  });
  await expectCode(() => first, 'PROVISIONING_GATT_BUSY');
  await expectCode(() => second, 'PROVISIONING_GATT_BUSY');
  assert.deepEqual(events, ['a-start'],
    'a queued request must not start while the timed-out operation is still running');
  await expectCode(() => queue.run(async () => 1), 'PROVISIONING_GATT_BUSY');
  await new Promise((resolve) => setTimeout(resolve, 60));
  assert.deepEqual(events, ['a-start', 'a-end']);
  queue.destroy();
});

// ---- GattChannel GATT busy policy (F-04) ----------------------------------

test('C19_GattChannel_writeBusyRetriesOnceWithSameBytes', async () => {
  const gateway = new FakeGateway();
  const connection = new FakeBleConnection(gateway, { writeBusyOnce: true });
  const { characteristics, descriptors } = await validMap(connection);
  const map = GattEndpointMap.build(characteristics, descriptors);
  const clock = new FakeClock();
  const channel = new GattChannel(connection, map, new GattRequestQueue(1000),
    fakeDelay(clock));
  const response = await channel.requestPlain('proto-ver', utf8('ESP'));
  assert.equal(Buffer.from(response).toString('utf8').includes('"prov"'), true);
  assert.equal(connection.writeAttempts.length, 2);
  assert.equal(connection.writes.length, 1);
  assert.deepEqual(connection.writeAttempts[0].value, connection.writeAttempts[1].value);
  assert.equal(clock.nowMs() - FakeClockBase(), 50);
});

test('C19_GattChannel_readBusyIsTerminalWithoutResend', async () => {
  const gateway = new FakeGateway();
  const connection = new FakeBleConnection(gateway, { readBusyOnce: true });
  const { characteristics, descriptors } = await validMap(connection);
  const map = GattEndpointMap.build(characteristics, descriptors);
  const clock = new FakeClock();
  const channel = new GattChannel(connection, map, new GattRequestQueue(1000),
    fakeDelay(clock));
  await expectCode(() => channel.requestPlain('proto-ver', utf8('ESP')),
    'PROVISIONING_GATT_BUSY');
  assert.equal(connection.writeAttempts.length, 1,
    'a read busy must not resend the already delivered write');
  assert.equal(connection.readAttempts, 1);
});

test('C19_GattChannel_writeBusyRetryPreservesCtrStream', async () => {
  const gateway = new FakeGateway();
  const session = new Security1Session(new NodeCryptoPort(), {
    async nextBytes(length) {
      return new Uint8Array(length).fill(5);
    },
  }, utf8('pop'));
  const step0 = await session.createStep0();
  const response0 = await gateway.handle('prov-session', step0);
  const step1 = await session.handleStep0Response(response0);
  const response1 = await gateway.handle('prov-session', step1);
  await session.handleStep1Response(response1);

  const connection = new FakeBleConnection(gateway, { writeBusyOnce: true });
  const { characteristics, descriptors } = await validMap(connection);
  const map = GattEndpointMap.build(characteristics, descriptors);
  const clock = new FakeClock();
  const channel = new GattChannel(connection, map, new GattRequestQueue(1000),
    fakeDelay(clock));
  channel.setSession(session);
  const response = await channel.request('prov-config', ProtocommCodec.encodeGetStatus());
  assert.equal(ProtocommCodec.decodeWifiStatus(response).ip4, '192.168.1.50');
  assert.equal(connection.writeAttempts.length, 2);
  assert.deepEqual(connection.writeAttempts[0].value, connection.writeAttempts[1].value,
    'the retry must reuse the single encrypted frame; re-encrypting would desync CTR');
  session.destroy();
});

// ---- ProvisioningStateMachine --------------------------------------------

const forwardPath = [
  ProvisioningEvent.START,
  ProvisioningEvent.PERMISSION_GRANTED,
  ProvisioningEvent.DEVICE_FOUND,
  ProvisioningEvent.CONNECTED,
  ProvisioningEvent.DISCOVERED,
  ProvisioningEvent.CAPABILITY_OK,
  ProvisioningEvent.SECURITY_OK,
  ProvisioningEvent.IDENTITY_OK,
  ProvisioningEvent.AP_SELECTED,
  ProvisioningEvent.CREDENTIALS_SENT,
  ProvisioningEvent.WIFI_CONNECTED,
  ProvisioningEvent.BINDING_OK,
];

test('C19_ProvisioningStateMachine_forwardPathAndReset', () => {
  const machine = new ProvisioningStateMachine();
  assert.equal(machine.state, ProvisioningState.IDLE);
  for (const event of forwardPath) {
    machine.transition(event);
  }
  assert.equal(machine.state, ProvisioningState.BOUND);
  machine.reset();
  assert.equal(machine.state, ProvisioningState.IDLE);
  expectCodeSync(() => machine.transition(ProvisioningEvent.CONNECTED),
    'CONFIGURATION_ERROR');
});

test('C19_ProvisioningStateMachine_cancelAndFailFromNonTerminalStates', () => {
  for (let index = 0; index < forwardPath.length; index++) {
    const machine = new ProvisioningStateMachine();
    for (let step = 0; step < index; step++) {
      machine.transition(forwardPath[step]);
    }
    machine.transition(ProvisioningEvent.CANCEL);
    assert.equal(machine.state, ProvisioningState.CANCELLED);
    machine.reset();
  }
  for (let index = 0; index < forwardPath.length; index++) {
    const machine = new ProvisioningStateMachine();
    for (let step = 0; step < index; step++) {
      machine.transition(forwardPath[step]);
    }
    machine.transition(ProvisioningEvent.FAIL);
    assert.equal(machine.state, ProvisioningState.FAILED);
  }
});

test('C19_ProvisioningStateMachine_terminalStatesRejectCancel', () => {
  const machine = new ProvisioningStateMachine();
  for (const event of forwardPath) {
    machine.transition(event);
  }
  expectCodeSync(() => machine.transition(ProvisioningEvent.CANCEL), 'CONFIGURATION_ERROR');
  expectCodeSync(() => machine.transition(ProvisioningEvent.FAIL), 'CONFIGURATION_ERROR');
});

// ---- WifiProvisioningFlow -------------------------------------------------

class FakeSecureChannel {
  constructor(handler) {
    this.handler = handler;
    this.requests = [];
  }

  async request(endpoint, payload) {
    this.requests.push({ endpoint, payload: new Uint8Array(payload) });
    return this.handler(endpoint, payload);
  }

  async requestPlain(endpoint, payload) {
    return this.request(endpoint, payload);
  }
}

function scanStartResponse() {
  const response = new ProtobufWriter();
  response.varint(1, 1);
  response.message(11, new ProtobufWriter());
  return response.toBytes();
}

function scanStatusResponse(finished, resultCount) {
  const response = new ProtobufWriter();
  response.varint(1, 3);
  const status = new ProtobufWriter();
  status.bool(1, finished);
  status.varint(2, resultCount);
  response.message(13, status);
  return response.toBytes();
}

function scanResultResponse(start, count, aps) {
  const response = new ProtobufWriter();
  response.varint(1, 5);
  const results = new ProtobufWriter();
  for (let index = start; index < start + count && index < aps.length; index++) {
    const ap = aps[index];
    const entry = new ProtobufWriter();
    entry.bytes(1, utf8(ap.ssid));
    entry.varint(2, ap.channel);
    entry.int32(3, ap.rssi);
    entry.bytes(4, new Uint8Array(ap.bssid));
    entry.varint(5, ap.auth);
    results.message(1, entry);
  }
  response.message(15, results);
  return response.toBytes();
}

function wifiStatusResponse(status) {
  const response = new ProtobufWriter();
  response.varint(1, 1);
  const body = new ProtobufWriter();
  body.varint(1, 0);
  if (status.state === 'connected') {
    body.varint(2, 0);
    const connected = new ProtobufWriter();
    connected.string(1, status.ip);
    body.message(11, connected);
  } else if (status.state === 'connecting') {
    body.varint(2, 1);
  } else {
    body.varint(2, 3);
    body.varint(10, status.reason === 'auth' ? 0 : 1);
  }
  response.message(11, body);
  return response.toBytes();
}

const aps = [
  { ssid: 'a1', bssid: [1, 1, 1, 1, 1, 1], channel: 1, rssi: -40, auth: 3 },
  { ssid: 'a2', bssid: [2, 2, 2, 2, 2, 2], channel: 6, rssi: -50, auth: 3 },
  { ssid: 'a3', bssid: [3, 3, 3, 3, 3, 3], channel: 11, rssi: -60, auth: 3 },
  { ssid: 'a4', bssid: [4, 4, 4, 4, 4, 4], channel: 3, rssi: -70, auth: 3 },
  { ssid: 'a5', bssid: [5, 5, 5, 5, 5, 5], channel: 8, rssi: -80, auth: 3 },
  { ssid: 'a6', bssid: [6, 6, 6, 6, 6, 6], channel: 13, rssi: -90, auth: 3 },
];

test('C19_WifiProvisioningFlow_scanPaginatesFourPerPage', async () => {
  let polls = 0;
  const channel = new FakeSecureChannel(async (_endpoint, payload) => {
    const fields = readFields(payload);
    const message = fieldVarint(fields, 1, 0);
    if (message === 0) {
      return scanStartResponse();
    }
    if (message === 2) {
      polls++;
      return scanStatusResponse(polls > 1, aps.length);
    }
    const command = readFields(fieldBytes(fields, 14));
    const start = fieldVarint(command, 1, 0);
    const count = fieldVarint(command, 2, 0);
    return scanResultResponse(start, count, aps);
  });
  const clock = new FakeClock();
  const flow = new WifiProvisioningFlow(clock, fakeDelay(clock));
  const result = await flow.scan(channel);
  assert.equal(result.length, 6);
  assert.equal(result[0].ssid, 'a1');
  assert.equal(result[0].bssid, '010101010101');
  assert.equal(channel.requests.length, 5);
});

test('C19_WifiProvisioningFlow_scanTimeoutAndInvalidStartFailClosed', async () => {
  const neverFinished = new FakeSecureChannel(async (_endpoint, payload) => {
    const fields = readFields(payload);
    const message = fieldVarint(fields, 1, 0);
    if (message === 0) {
      return scanStartResponse();
    }
    return scanStatusResponse(false, 0);
  });
  const clock = new FakeClock();
  const flow = new WifiProvisioningFlow(clock, fakeDelay(clock));
  await expectCode(() => flow.scan(neverFinished), 'PROVISIONING_WIFI_SCAN_FAILED');
  const badStart = new FakeSecureChannel(async () => new Uint8Array([0x08, 0x09]));
  await expectCode(() => flow.scan(badStart), 'PROVISIONING_WIFI_SCAN_FAILED');
});

test('C19_WifiProvisioningFlow_scanPagesShareFifteenSecondDeadline', async () => {
  const many = [];
  for (let index = 0; index < 8; index++) {
    many.push({
      ssid: 'ap-' + String(index),
      bssid: [index + 1, index + 1, index + 1, index + 1, index + 1, index + 1],
      channel: 1 + index,
      rssi: -40 - index,
      auth: 3,
    });
  }
  const clock = new FakeClock();
  let pages = 0;
  const channel = new FakeSecureChannel(async (_endpoint, payload) => {
    const fields = readFields(payload);
    const message = fieldVarint(fields, 1, 0);
    if (message === 0) {
      return scanStartResponse();
    }
    if (message === 2) {
      return scanStatusResponse(true, many.length);
    }
    pages++;
    clock.advance(16000);
    const command = readFields(fieldBytes(fields, 14));
    const start = fieldVarint(command, 1, 0);
    const count = fieldVarint(command, 2, 0);
    return scanResultResponse(start, count, many);
  });
  const flow = new WifiProvisioningFlow(clock, fakeDelay(clock));
  await expectCode(() => flow.scan(channel), 'PROVISIONING_WIFI_SCAN_FAILED');
  assert.equal(pages, 1,
    'the page loop must stop at the same 15s deadline as status polling');
});

test('C19_WifiProvisioningFlow_applySendsSetThenApply', async () => {
  const channel = new FakeSecureChannel(async (_endpoint, payload) => {
    const fields = readFields(payload);
    const message = fieldVarint(fields, 1, 0);
    const response = new ProtobufWriter();
    if (message === 2) {
      response.varint(1, 3);
      const ack = new ProtobufWriter();
      ack.varint(1, 0);
      response.message(13, ack);
      return response.toBytes();
    }
    response.varint(1, 5);
    const ack = new ProtobufWriter();
    ack.varint(1, 0);
    response.message(15, ack);
    return response.toBytes();
  });
  const clock = new FakeClock();
  const flow = new WifiProvisioningFlow(clock, fakeDelay(clock));
  await flow.apply(channel, new WifiConfig('home-wifi', utf8('password')));
  assert.equal(channel.requests.length, 2);
  const set = readFields(channel.requests[0].payload);
  assert.equal(fieldVarint(set, 1), 2);
  const apply = readFields(channel.requests[1].payload);
  assert.equal(fieldVarint(apply, 1), 4);
});

test('C19_WifiProvisioningFlow_waitForConnectionAndTerminalClassification', async () => {
  let polls = 0;
  const channel = new FakeSecureChannel(async () => {
    polls++;
    if (polls === 1) {
      return wifiStatusResponse({ state: 'connecting' });
    }
    return wifiStatusResponse({ state: 'connected', ip: '192.168.1.50' });
  });
  const clock = new FakeClock();
  const flow = new WifiProvisioningFlow(clock, fakeDelay(clock));
  const status = await flow.waitForConnection(channel);
  assert.equal(status.ip4, '192.168.1.50');
  assert.equal(polls, 2);

  const auth = new FakeSecureChannel(async () =>
    wifiStatusResponse({ state: 'failed', reason: 'auth' }));
  await expectCode(() => flow.waitForConnection(auth), 'PROVISIONING_WIFI_AUTH_ERROR');
  const missing = new FakeSecureChannel(async () =>
    wifiStatusResponse({ state: 'failed', reason: 'network' }));
  await expectCode(() => flow.waitForConnection(missing),
    'PROVISIONING_WIFI_NETWORK_NOT_FOUND');
});

test('C19_WifiProvisioningFlow_waitForConnectionTimesOutAtThirtySeconds', async () => {
  const channel = new FakeSecureChannel(async () =>
    wifiStatusResponse({ state: 'connecting' }));
  const clock = new FakeClock();
  const flow = new WifiProvisioningFlow(clock, fakeDelay(clock));
  await expectCode(() => flow.waitForConnection(channel), 'PROVISIONING_WIFI_TIMEOUT');
  assert.equal(clock.nowMs() >= FakeClockBase() + 30000, true);
});

function FakeClockBase() {
  return Date.UTC(2026, 9, 17, 8, 0, 0);
}

test('C19_WifiProvisioningFlow_finishAckSemantics', async () => {
  const clock = new FakeClock();
  const flow = new WifiProvisioningFlow(clock, fakeDelay(clock));
  const absent = new FakeSecureChannel(async () => utf8('{}'));
  assert.equal(await flow.finish(absent, false), false);
  assert.equal(absent.requests.length, 0);
  for (const body of ['', 'not-json', '{"status":"accepted","protocolVersion":"2.0"}']) {
    const channel = new FakeSecureChannel(async () => utf8(body));
    assert.equal(await flow.finish(channel, true), true, body);
  }
  for (const body of ['{"ok":false}', '{"status":"failed"}', '{"status":false}']) {
    const channel = new FakeSecureChannel(async () => utf8(body));
    await expectCode(() => flow.finish(channel, true), 'PROVISIONING_DONE_REJECTED');
  }
  const failing = new FakeSecureChannel(async () => {
    throw new AppError('PROVISIONING_GATT_BUSY', 'PROVISIONING', 'x', true);
  });
  await expectCode(() => flow.finish(failing, true), 'PROVISIONING_DONE_REJECTED');
});

// ---- BindingProber --------------------------------------------------------

function v21Identity() {
  return new BleProvisioningIdentity(IdentityVersion.V21, GATEWAY_ID, GATEWAY_NAME,
    new ProvisioningTlsMaterial([PIN], 9200, 'sha256-spki-der'));
}

function v20Identity() {
  return new BleProvisioningIdentity(IdentityVersion.V20, GATEWAY_ID, GATEWAY_NAME);
}

test('C19_BindingProber_hmacProbeAndBoardLedConfirmation', async () => {
  const clock = new FakeClock();
  const client = new FakeGatewayClient();
  const drafts = makeDraftStore(clock);
  const prober = new BindingProber(client, new FakeCredentials(), clock, undefined,
    fakeDelay(clock));
  const outcome = await prober.probe(v20Identity(), '192.168.1.50', 'family-01',
    undefined, drafts);
  assert.equal(outcome.boardLedConfirmed, true);
  assert.equal(outcome.credentialDraftId, '');
  assert.equal(client.probeCalls, 1);
  assert.equal(client.controlCalls, 2);
  assert.equal(client.probeTargets[0].profile, 'P-HMAC');
  assert.equal(client.secrets[0], SECRET_HEX);
});

test('C19_BindingProber_tlsProfileCarriesPins', async () => {
  const clock = new FakeClock();
  const client = new FakeGatewayClient();
  const drafts = makeDraftStore(clock);
  const prober = new BindingProber(client, new FakeCredentials(), clock, undefined,
    fakeDelay(clock));
  const outcome = await prober.probe(v21Identity(), '192.168.1.50', 'family-01',
    undefined, drafts);
  assert.equal(outcome.boardLedConfirmed, true);
  assert.equal(client.probeTargets[0].profile, 'P-TLS-PIN');
  assert.deepEqual([...client.probeTargets[0].pins], [PIN]);
});

test('C19_BindingProber_identityMismatchIsTerminal', async () => {
  const clock = new FakeClock();
  const client = new FakeGatewayClient({ probeGatewayId: 'gateway_02' });
  const prober = new BindingProber(client, new FakeCredentials(), clock, undefined,
    fakeDelay(clock));
  await expectCode(() => prober.probe(v20Identity(), '192.168.1.50', 'family-01',
    undefined, makeDraftStore(clock)), 'PROVISIONING_BINDING_IDENTITY_MISMATCH');
  assert.equal(client.probeCalls, 1);
});

test('C19_BindingProber_snapshotMismatchAndProfileMismatchAreTerminal', async () => {
  const clock = new FakeClock();
  const snapshotMismatch = new FakeGatewayClient({ snapshotGatewayId: 'gateway_02' });
  const prober = new BindingProber(snapshotMismatch, new FakeCredentials(), clock,
    undefined, fakeDelay(clock));
  await expectCode(() => prober.probe(v20Identity(), '192.168.1.50', 'family-01',
    undefined, makeDraftStore(clock)), 'PROVISIONING_BINDING_IDENTITY_MISMATCH');

  const profileMismatch = new FakeGatewayClient({ profileOverride: 'P-TLS-PIN' });
  const prober2 = new BindingProber(profileMismatch, new FakeCredentials(), clock,
    undefined, fakeDelay(clock));
  await expectCode(() => prober2.probe(v20Identity(), '192.168.1.50', 'family-01',
    undefined, makeDraftStore(clock)), 'PROVISIONING_BINDING_IDENTITY_MISMATCH');
});

test('C19_BindingProber_tlsPinMismatchExhaustsFiniteRetries', async () => {
  const clock = new FakeClock();
  const client = new FakeGatewayClient({ tlsPinMatchedOverride: 'b'.repeat(64) });
  const prober = new BindingProber(client, new FakeCredentials(), clock, undefined,
    fakeDelay(clock));
  await expectCode(() => prober.probe(v21Identity(), '192.168.1.50', 'family-01',
    undefined, makeDraftStore(clock)), 'PROVISIONING_BINDING_PROBE_FAILED');
  assert.equal(client.probeCalls, 5);
});

test('C19_BindingProber_transientProbeFailuresRetryThenSucceed', async () => {
  const clock = new FakeClock();
  const client = new FakeGatewayClient({ failProbes: 2 });
  const prober = new BindingProber(client, new FakeCredentials(), clock, undefined,
    fakeDelay(clock));
  const outcome = await prober.probe(v20Identity(), '192.168.1.50', 'family-01',
    undefined, makeDraftStore(clock));
  assert.equal(outcome.boardLedConfirmed, true);
  assert.equal(client.probeCalls, 3);
});

test('C19_BindingProber_firstRetryWaits500msAndExhausts7500ms', async () => {
  const transientClock = new FakeClock();
  const transient = new FakeGatewayClient({ failProbes: 1 });
  const transientProber = new BindingProber(transient, new FakeCredentials(), transientClock,
    undefined, fakeDelay(transientClock));
  const transientStart = transientClock.nowMs();
  const outcome = await transientProber.probe(v20Identity(), '192.168.1.50', 'family-01',
    undefined, makeDraftStore(transientClock));
  assert.equal(outcome.boardLedConfirmed, true);
  assert.equal(transientClock.nowMs() - transientStart, 500,
    'the first retry is 500ms (ProbeBackoff is 1-based)');

  const exhaustClock = new FakeClock();
  const failing = new FakeGatewayClient({ failProbes: 5 });
  const failingProber = new BindingProber(failing, new FakeCredentials(), exhaustClock,
    undefined, fakeDelay(exhaustClock));
  const exhaustStart = exhaustClock.nowMs();
  await expectCode(() => failingProber.probe(v20Identity(), '192.168.1.50', 'family-01',
    undefined, makeDraftStore(exhaustClock)), 'PROVISIONING_BINDING_PROBE_FAILED');
  assert.equal(failing.probeCalls, 5);
  assert.equal(exhaustClock.nowMs() - exhaustStart, 7500,
    'retry delays are 500 + 1000 + 2000 + 4000 ms');
});

test('C19_BindingProber_enforcesThirtySecondTotalBudget', async () => {
  const clock = new FakeClock();
  class SlowFailingClient extends FakeGatewayClient {
    constructor() {
      super({ failProbes: 99 });
    }

    async probe(target, credentials) {
      clock.advance(7000);
      return await super.probe(target, credentials);
    }
  }
  const client = new SlowFailingClient();
  const prober = new BindingProber(client, new FakeCredentials(), clock, undefined,
    fakeDelay(clock));
  const start = clock.nowMs();
  await expectCode(() => prober.probe(v20Identity(), '192.168.1.50', 'family-01',
    undefined, makeDraftStore(clock)), 'PROVISIONING_BINDING_PROBE_FAILED');
  assert.equal(client.probeCalls, 4,
    'the fifth attempt must not start after the 30s budget is spent');
  assert.equal(clock.nowMs() - start >= 30000, true);
});

test('C19_BindingProber_boardLedFailuresNeverBind', async () => {
  const cases = [
    { ledAck: false },
    { boardLed: false },
    { stateVerification: 'UNVERIFIED' },
    { boardStateGatewayId: 'gateway_02' },
  ];
  for (const options of cases) {
    const clock = new FakeClock();
    const client = new FakeGatewayClient(options);
    const prober = new BindingProber(client, new FakeCredentials(), clock, undefined,
      fakeDelay(clock));
    await expectCode(() => prober.probe(v20Identity(), '192.168.1.50', 'family-01',
      undefined, makeDraftStore(clock)), 'PROVISIONING_BOARD_LED_UNCONFIRMED');
  }
});

test('C19_BindingProber_ledResetFailureDoesNotInvalidateBinding', async () => {
  const clock = new FakeClock();
  const client = new FakeGatewayClient({ failReset: true });
  const prober = new BindingProber(client, new FakeCredentials(), clock, undefined,
    fakeDelay(clock));
  const outcome = await prober.probe(v20Identity(), '192.168.1.50', 'family-01',
    undefined, makeDraftStore(clock));
  assert.equal(outcome.boardLedConfirmed, true);
});

test('C19_BindingProber_draftIsReissuedOnlyOnSuccess', async () => {
  const clock = new FakeClock();
  const drafts = makeDraftStore(clock);
  const originalId = putDraft(drafts, SECRET_HEX);
  const client = new FakeGatewayClient();
  const prober = new BindingProber(client, new FakeCredentials(''), clock, undefined,
    fakeDelay(clock));
  const outcome = await prober.probe(v20Identity(), '192.168.1.50', 'family-01',
    originalId, drafts);
  assert.notEqual(outcome.credentialDraftId, '');
  assert.notEqual(outcome.credentialDraftId, originalId);
  assert.equal(client.secrets[0], SECRET_HEX);
  expectCodeSync(() => drafts.take(originalId), 'PROVISIONING_CREDENTIAL_MISSING');
  const issued = drafts.take(outcome.credentialDraftId);
  assert.equal(issued.toHex(), SECRET_HEX);
  issued.destroy();
});

test('C19_BindingProber_draftIsDestroyedOnFailure', async () => {
  const clock = new FakeClock();
  const drafts = makeDraftStore(clock);
  const originalId = putDraft(drafts, SECRET_HEX);
  const client = new FakeGatewayClient({ probeGatewayId: 'gateway_02' });
  const prober = new BindingProber(client, new FakeCredentials(''), clock, undefined,
    fakeDelay(clock));
  await expectCode(() => prober.probe(v20Identity(), '192.168.1.50', 'family-01',
    originalId, drafts), 'PROVISIONING_BINDING_IDENTITY_MISMATCH');
  expectCodeSync(() => drafts.take(originalId), 'PROVISIONING_CREDENTIAL_MISSING');
});

test('C19_BindingProber_missingDraftAndFamilyFailClosed', async () => {
  const clock = new FakeClock();
  const drafts = makeDraftStore(clock);
  const client = new FakeGatewayClient();
  const prober = new BindingProber(client, new FakeCredentials(''), clock, undefined,
    fakeDelay(clock));
  await expectCode(() => prober.probe(v20Identity(), '192.168.1.50', 'family-01',
    'missing-draft', drafts), 'PROVISIONING_CREDENTIAL_MISSING');
  await expectCode(() => prober.probe(v20Identity(), '192.168.1.50', '',
    undefined, drafts), 'CONFIGURATION_ERROR');
});
