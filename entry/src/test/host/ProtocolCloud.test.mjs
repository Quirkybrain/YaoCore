/*
 * YaoCore C-03 cloud envelope / state-report mapping host tests.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Traceability: DES-B §8.1.4/§8.1.5/§8.3.3; PR-09; D-014 fixed paths.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { AppError } from '../../main/ets/common/types/AppError.ets';
import { CloudCommandSerializer } from '../../main/ets/service/protocol/CloudCommandSerializer.ets';
import {
  ShadowMapContext,
  StateReportMapper,
} from '../../main/ets/service/protocol/StateReportMapper.ets';

const encode = (value) => new TextEncoder().encode(JSON.stringify(value));
const decode = (bytes) => new TextDecoder().decode(bytes);
const receivedAtMs = Date.UTC(2026, 9, 17, 12, 0, 1);

const envelope = (overrides = {}) => {
  const result = {
    service_id: overrides.service_id ?? 'SmartHomeService',
    command_name: overrides.command_name ?? 'SetDeviceStatus',
    paras: {
      RequestId: 'req-1790000000000-7',
      CmdId: 3001,
      Seq: 7,
      TargetDevice: 'Light_01',
      Action: 'SET_BRIGHTNESS',
      Value: '68',
      Timestamp: '20261017T120000Z',
      Nonce: '0123456789abcdef0123456789abcdef',
      Alg: 'HMAC-SHA256',
      KeyId: 'app-key-v1',
      Sign: 'a'.repeat(64),
      ...overrides.paras,
    },
  };
  if (overrides.object_device_id !== undefined) {
    result.object_device_id = overrides.object_device_id;
  }
  return result;
};

const expectCode = (fn, code) => {
  assert.throws(fn, (error) => {
    assert.ok(error instanceof AppError, `expected AppError, got ${error}`);
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
};

const stateReport = (properties, eventTime = '20261017T120000Z') => ({
  services: [{
    service_id: 'SmartHomeService',
    properties,
    event_time: eventTime,
  }],
});

const fixedProperties = () => ({
  Door_01_Online: true,
  Door_01_Status: 'OPEN',
  Door_01_LastRequestId: 'req-door',
  Door_01_LastSeq: 1,
  Door_01_StateSource: 'device.feedback',
  Light_01_Online: true,
  Light_01_Status: 'ON',
  Light_01_Brightness: 68,
  Light_01_LastRequestId: 'req-light',
  Light_01_LastSeq: 2,
  Light_01_StateSource: 'app.lan',
  Light_01_TriggerDeviceId: 'Presence_01',
  Light_01_AutomationId: 'auto-1',
  Sensor_01_Online: true,
  Room_01_Temperature: 26.8,
  Room_01_Humidity: 58,
  Presence_01_Online: true,
  Presence_01_Detected: false,
  AC_01_Online: true,
  AC_01_Status: 'ON',
  AC_01_TargetTemp: 24,
  AC_01_Mode: 'COOL',
  AC_01_LastRequestId: 'req-ac',
  AC_01_LastSeq: 3,
  AC_01_StateSource: 'device.feedback',
  AC_01_TriggerDeviceId: 'Presence_01',
  AC_01_AutomationId: 'auto-2',
  Gateway_Online: true,
  Gateway_RSSI: -55,
});

test('C03_CloudCommandSerializer_emitsExactEnvelopeOrder', () => {
  const text = decode(CloudCommandSerializer.serialize(envelope({ object_device_id: 'ignored' })));
  const parsed = JSON.parse(text);
  assert.deepEqual(Object.keys(parsed), ['service_id', 'command_name', 'paras']);
  assert.deepEqual(Object.keys(parsed.paras), [
    'RequestId', 'CmdId', 'Seq', 'TargetDevice', 'Action', 'Value',
    'Timestamp', 'Nonce', 'Alg', 'KeyId', 'Sign',
  ]);
  assert.equal(parsed.service_id, 'SmartHomeService');
  assert.equal(parsed.command_name, 'SetDeviceStatus');
  assert.equal(parsed.object_device_id, undefined);
  assert.equal(parsed.paras.CmdId, 3001);
  assert.equal(parsed.paras.Value, '68');
  assert.ok(!text.endsWith('\n'));
});

test('C03_CloudCommandSerializer_valueIsCompactAtomText', () => {
  const numeric = JSON.parse(decode(CloudCommandSerializer.serialize(envelope())));
  assert.equal(numeric.paras.Value, '68');
  assert.equal(typeof numeric.paras.Value, 'string');

  const textValue = JSON.parse(decode(CloudCommandSerializer.serialize(
    envelope({ paras: { Action: 'SET_MODE', Value: '"制冷"' } }),
  )));
  assert.equal(textValue.paras.Value, '"制冷"');

  const absent = JSON.parse(decode(CloudCommandSerializer.serialize(
    envelope({ paras: { Action: 'PING', Value: undefined } }),
  )));
  assert.equal(absent.paras.Value, undefined);
  assert.deepEqual(Object.keys(absent.paras).includes('Value'), false);
});

test('C03_CloudCommandSerializer_rejectsNonCanonicalValueAndFields', () => {
  expectCode(() => CloudCommandSerializer.serialize(
    envelope({ paras: { Value: '24.0' } })), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(() => CloudCommandSerializer.serialize(
    envelope({ paras: { Value: '{"a":1}' } })), 'PROTOCOL_INVALID_TYPE');
  expectCode(() => CloudCommandSerializer.serialize(
    envelope({ paras: { Value: 'NaN' } })), 'PROTOCOL_INVALID_JSON');
  expectCode(() => CloudCommandSerializer.serialize(
    envelope({ paras: { Value: 'x'.repeat(64) } })), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(() => CloudCommandSerializer.serialize(
    envelope({ service_id: 'Other' })), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(() => CloudCommandSerializer.serialize(
    envelope({ command_name: 'Other' })), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(() => CloudCommandSerializer.serialize(
    envelope({ paras: { CmdId: 2001 } })), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(() => CloudCommandSerializer.serialize(
    envelope({ paras: { Seq: -1 } })), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(() => CloudCommandSerializer.serialize(
    envelope({ paras: { TargetDevice: 'gw:01' } })), 'PROTOCOL_INVALID_IDENTIFIER');
  expectCode(() => CloudCommandSerializer.serialize(
    envelope({ paras: { Action: 'lowercase' } })), 'PROTOCOL_INVALID_IDENTIFIER');
  expectCode(() => CloudCommandSerializer.serialize(
    envelope({ paras: { Timestamp: '2026-10-17T12:00:00Z' } })), 'PROTOCOL_INVALID_TIMESTAMP');
  expectCode(() => CloudCommandSerializer.serialize(
    envelope({ paras: { Nonce: 'short' } })), 'PROTOCOL_INVALID_IDENTIFIER');
  expectCode(() => CloudCommandSerializer.serialize(
    envelope({ paras: { Nonce: '9f2a7c001122' } })), 'PROTOCOL_INVALID_IDENTIFIER');
  expectCode(() => CloudCommandSerializer.serialize(
    envelope({ paras: { Nonce: '0123456789ABCDEF0123456789ABCDEF' } })),
  'PROTOCOL_INVALID_IDENTIFIER');
  expectCode(() => CloudCommandSerializer.serialize(
    envelope({ paras: { Nonce: '0123456789abcdef-123456789abcdef' } })),
  'PROTOCOL_INVALID_IDENTIFIER');
  expectCode(() => CloudCommandSerializer.serialize(
    envelope({ paras: { Alg: 'HMAC-SHA1' } })), 'PROTOCOL_UNSUPPORTED_VERSION');
  expectCode(() => CloudCommandSerializer.serialize(
    envelope({ paras: { KeyId: 'other' } })), 'PROTOCOL_UNSUPPORTED_VERSION');
  expectCode(() => CloudCommandSerializer.serialize(
    envelope({ paras: { Sign: 'A'.repeat(64) } })), 'PROTOCOL_INVALID_IDENTIFIER');
});

test('C03_StateReportMapper_servicesShapeMapsFixedPropertyPaths', () => {
  const snapshot = StateReportMapper.map(
    encode(stateReport(fixedProperties())),
    new ShadowMapContext('gw-device-1', receivedAtMs, 'b'.repeat(64)),
  );
  assert.equal(snapshot.shape, 'SERVICES');
  assert.equal(snapshot.gatewayDeviceId, 'gw-device-1');
  assert.equal(snapshot.eventTime, '20261017T120000Z');
  assert.equal(snapshot.eventEpochMs, Date.UTC(2026, 9, 17, 12, 0, 0));
  assert.equal(snapshot.gatewayOnline, true);
  assert.equal(snapshot.rawSha256, 'b'.repeat(64));
  assert.equal(snapshot.properties.length, Object.keys(fixedProperties()).length);
  assert.equal(snapshot.devices.length, 5);

  const byId = new Map(snapshot.devices.map((item) => [item.deviceId, item]));
  assert.equal(byId.get('Door_01').open, true);
  assert.equal(byId.get('Door_01').lastRequestId, 'req-door');
  assert.equal(byId.get('Door_01').lastSeq, 1);
  assert.equal(byId.get('Door_01').stateSourceKnown, true);
  assert.equal(byId.get('Light_01').power, true);
  assert.equal(byId.get('Light_01').brightness, 68);
  assert.equal(byId.get('Light_01').triggerDeviceId, 'Presence_01');
  assert.equal(byId.get('Light_01').automationId, 'auto-1');
  assert.equal(byId.get('Sensor_01').temperature, 26.8);
  assert.equal(byId.get('Sensor_01').humidity, 58);
  assert.equal(byId.get('Presence_01').presence, false);
  assert.equal(byId.get('AC_01').targetTemperature, 24);
  assert.equal(byId.get('AC_01').mode, 'COOL');
  assert.equal(byId.get('AC_01').modeStandard, true);
});

test('C03_StateReportMapper_shadowShapeAndDevicesShapeAreAccepted', () => {
  const shadow = StateReportMapper.map(encode({
    shadow: [{
      service_id: 'SmartHomeService',
      reported: {
        properties: {
          Light_01_Online: true,
          Light_01_Status: 'OFF',
          Light_01_Brightness: 40,
        },
        event_time: '20261017T120000Z',
      },
    }],
  }), new ShadowMapContext('gw-device-1', receivedAtMs));
  assert.equal(shadow.shape, 'SHADOW');
  assert.equal(shadow.devices.length, 1);
  assert.equal(shadow.devices[0].power, false);
  assert.equal(shadow.devices[0].brightness, 40);

  const devices = StateReportMapper.map(encode({
    devices: [
      {
        device_id: 'Light_01',
        online: true,
        power: true,
        brightness: 40,
        event_time: '20261017T120000Z',
        last_request_id: 'req-device',
        last_seq: 5,
      },
      {
        device_id: 'Gateway',
        online: true,
        event_time: '20261017T120000Z',
      },
    ],
  }), new ShadowMapContext('gw-device-1', receivedAtMs));
  assert.equal(devices.shape, 'DEVICES');
  assert.equal(devices.devices.length, 2);
  assert.equal(devices.devices[0].brightness, 40);
  assert.equal(devices.devices[0].lastRequestId, 'req-device');
  assert.equal(devices.devices[0].lastSeq, 5);
  assert.equal(devices.gatewayOnline, true);
});

test('C03_StateReportMapper_servicesShapeIsStrictPerSchema', () => {
  const context = new ShadowMapContext('gw-device-1', receivedAtMs);
  const full = fixedProperties();

  const missingRequired = stateReport((() => {
    const copy = { ...full };
    delete copy.Gateway_RSSI;
    return copy;
  })());
  expectCode(() => StateReportMapper.map(encode(missingRequired), context), 'CLOUD_SHADOW_INVALID');

  expectCode(() => StateReportMapper.map(encode(stateReport({ ...full, Unknown_Property: 1 })),
    context), 'CLOUD_SHADOW_INVALID');

  const topLevelUnknown = { ...stateReport(full), extra: true };
  expectCode(() => StateReportMapper.map(encode(topLevelUnknown), context), 'CLOUD_SHADOW_INVALID');

  expectCode(() => StateReportMapper.map(encode(stateReport({ ...full, Door_01_Online: 'true' })),
    context), 'CLOUD_SHADOW_INVALID');

  expectCode(() => StateReportMapper.map(encode(stateReport({ ...full, Gateway_RSSI: -55.5 })),
    context), 'CLOUD_SHADOW_INVALID');

  // SHADOW/DEVICES shapes remain partial-tolerant in T-06; T-14 owns the full
  // strict cloud adapter and DeviceInventoryJson.
  const partialShadow = StateReportMapper.map(encode({
    shadow: [{
      service_id: 'SmartHomeService',
      reported: {
        properties: { Light_01_Online: true },
        event_time: '20261017T120000Z',
      },
    }],
  }), context);
  assert.equal(partialShadow.devices.length, 1);
});

test('C03_StateReportMapper_rejectsUnknownShapesAndInvalidProperties', () => {
  const context = new ShadowMapContext('gw-device-1', receivedAtMs);
  expectCode(() => StateReportMapper.map(encode({ foo: 1 }), context), 'CLOUD_SHADOW_INVALID');
  expectCode(() => StateReportMapper.map(encode(stateReport({ Light_01_Brightness: 101 })),
    context), 'CLOUD_SHADOW_INVALID');
  expectCode(() => StateReportMapper.map(encode(stateReport({ Light_01_Status: 'BROKEN' })),
    context), 'CLOUD_SHADOW_INVALID');
  expectCode(() => StateReportMapper.map(encode(stateReport({ Light_01_Color: '#abc' })),
    context), 'CLOUD_SHADOW_INVALID');
  expectCode(() => StateReportMapper.map(encode(stateReport({ Light_01_Online: { value: true } })),
    context), 'CLOUD_SHADOW_INVALID');
  expectCode(() => StateReportMapper.map(encode({
    services: [{ service_id: 'SmartHomeService', properties: { Light_01_Online: true } }],
  }), context), 'CLOUD_SHADOW_INVALID');
  expectCode(() => StateReportMapper.map(encode(stateReport({ Light_01_Online: true },
    '20261017T120601Z')), context), 'CLOUD_SHADOW_INVALID');
  expectCode(() => StateReportMapper.map(encode(stateReport({ Light_01_Online: true })),
    new ShadowMapContext('gw-device-1', receivedAtMs, 'not-a-hash')), 'CLOUD_SHADOW_INVALID');
});

test('C03_StateReportMapper_DeviceInventoryJsonIsPreservedButNotParsedYet', () => {
  const snapshot = StateReportMapper.map(encode(stateReport({
    Door_01_Online: true,
    Light_01_Online: true,
    Sensor_01_Online: true,
    Presence_01_Online: true,
    AC_01_Online: true,
    Gateway_Online: true,
    Gateway_RSSI: -55,
    DeviceInventoryJson: '[{"device_id":"MODULE_01","last_request_id":"req-1","last_seq":1}]',
  })), new ShadowMapContext('gw-device-1', receivedAtMs));
  assert.equal(snapshot.devices.length, 5);
  assert.ok(snapshot.properties.some((item) => item.name === 'DeviceInventoryJson'));
  assert.equal(snapshot.devices.some((item) => item.deviceId === 'MODULE_01'), false);
});
