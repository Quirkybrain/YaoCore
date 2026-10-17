/*
 * YaoCore C-03 discover mapper host tests.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Traceability: DES-A §6.1.2, §6.3, §18.8; V-04; SEC-N18.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { AppError } from '../../main/ets/common/types/AppError.ets';
import {
  DeviationCode,
  ProtocolDeviation,
} from '../../main/ets/common/types/ProtocolDeviation.ets';
import {
  DiscoverMapContext,
  DiscoverMapper,
} from '../../main/ets/service/protocol/DiscoverMapper.ets';
import { DeviationCounter } from '../../main/ets/service/protocol/ProtocolDeviation.ets';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(HERE, '../../../..');
const GOLDEN = path.join(
  REPO_ROOT,
  'entry/src/ohosTest/ets/test/contract/fixtures/discover-response.json',
);

const encode = (value) => new TextEncoder().encode(JSON.stringify(value));

const baseEnvelope = (devices) => ({
  protocolVersion: '2.0',
  gatewayId: 'gw_01',
  gatewayName: 'YaoCore Gateway',
  serviceId: 'SmartHomeService',
  generatedAt: '20261017T120000Z',
  security: {
    alg: 'HMAC-SHA256',
    keyId: 'app-key-v1',
    timeWindowSeconds: 120,
    nonceTtlSeconds: 300,
  },
  devices,
});

const device = (overrides = {}) => ({
  deviceId: 'Light_01',
  deviceName: 'Light',
  roomName: 'Living',
  deviceType: 'light',
  online: true,
  updatedAt: '20261017T120000Z',
  ...overrides,
});

const map = (body, expectedGatewayId = undefined) => {
  const counter = new DeviationCounter();
  const snapshot = DiscoverMapper.map(
    typeof body === 'string' ? new TextEncoder().encode(body) : encode(body),
    new DiscoverMapContext(expectedGatewayId, Date.now()),
    counter,
  );
  return { snapshot, counter };
};

const mapError = (body, expectedGatewayId = undefined) => {
  try {
    map(body, expectedGatewayId);
  } catch (error) {
    assert.ok(error instanceof AppError, `expected AppError, got ${error}`);
    return error;
  }
  assert.fail('expected discover mapper to throw');
};

test('C03_DiscoverMapper_goldenMapsAllFourDevicesWithoutDeviations', () => {
  const golden = JSON.parse(readFileSync(GOLDEN, 'utf8'));
  const { snapshot, counter } = map(golden);
  assert.equal(snapshot.gatewayId, 'gateway_01');
  assert.equal(snapshot.gatewayName, 'YaoCore DEV Contract Simulator');
  assert.equal(snapshot.protocolVersion, '2.0');
  assert.equal(snapshot.serviceId, 'SmartHomeService');
  assert.equal(snapshot.devices.length, 4);
  assert.equal(snapshot.isPartial, false);
  assert.equal(counter.total(), 0);

  const byId = new Map(snapshot.devices.map((item) => [item.deviceId, item]));
  assert.equal(byId.get('Door_01').deviceType, 'door');
  assert.equal(byId.get('Door_01').openStatus, false);
  assert.equal(byId.get('Door_01').roomNameHint, '玄关');
  assert.equal(byId.get('Light_01').powerStatus, true);
  assert.equal(byId.get('Light_01').brightness, 68);
  assert.equal(byId.get('Sensor_01').temperature, 26.8);
  assert.equal(byId.get('Sensor_01').humidity, 58);
  assert.equal(byId.get('AC_01').targetTemperature, 24);
  assert.equal(byId.get('AC_01').mode, 'COOL');
  assert.equal(byId.get('AC_01').modeStandard, true);
  assert.equal(byId.get('AC_01').stateEpochMs, Date.UTC(2026, 9, 16, 15, 55, 33));
});

test('C03_DiscoverMapper_readsKnownAliasesOnlyWhenCanonicalIsAbsent', () => {
  const { snapshot, counter } = map(baseEnvelope([
    device({
      online: undefined,
      isOnline: true,
      powerStatus: true,
      openStatus: false,
      targetTemperature: 24,
      success: true,
    }),
  ]));
  const item = snapshot.devices[0];
  assert.equal(item.isOnline, true);
  assert.equal(item.powerStatus, true);
  assert.equal(item.openStatus, false);
  assert.equal(item.targetTemperature, 24);
  assert.equal(snapshot.isPartial, false);
  assert.equal(snapshot.aliasUsed, true);
  const counts = counter.counts();
  assert.equal(counts.get(DeviationCode.ALIAS_FIELD_USED), 4);
  assert.equal(counts.get(DeviationCode.SUCCESS_FIELD_IGNORED), 1);
});

test('C03_DiscoverMapper_aliasAndPartialAreIndependentDiagnostics', () => {
  const { snapshot } = map(baseEnvelope([
    device({ deviceId: 'Light_02', online: undefined, isOnline: true }),
    device({ deviceId: 'Bad:01' }),
  ]));
  assert.equal(snapshot.devices.length, 1);
  assert.equal(snapshot.isPartial, true);
  assert.equal(snapshot.aliasUsed, true);

  const skippedAlias = map(baseEnvelope([
    device({ online: undefined, isOnline: true, updatedAt: 'not-a-time' }),
  ])).snapshot;
  assert.equal(skippedAlias.devices.length, 0);
  assert.equal(skippedAlias.isPartial, true);
  assert.equal(skippedAlias.aliasUsed, true);

  const clean = map(baseEnvelope([device()])).snapshot;
  assert.equal(clean.isPartial, false);
  assert.equal(clean.aliasUsed, false);
});

test('C03_DiscoverMapper_canonicalWinsAliasConflict', () => {
  const { snapshot, counter } = map(baseEnvelope([
    device({ online: true, isOnline: false, power: true, powerStatus: false }),
  ]));
  assert.equal(snapshot.devices[0].isOnline, true);
  assert.equal(snapshot.devices[0].powerStatus, true);
  assert.equal(counter.counts().get(DeviationCode.ALIAS_CONFLICT), 2);
  assert.equal(counter.counts().get(DeviationCode.ALIAS_FIELD_USED), undefined);
});

test('C03_DiscoverMapper_unknownTypeRoomModeColorAndStateSourceAreTolerated', () => {
  const { snapshot, counter } = map(baseEnvelope([
    {
      deviceId: 'Weird_01',
      deviceName: 'Weird',
      deviceType: 'weird',
      online: true,
      updatedAt: '20261017T120000Z',
    },
    device({
      deviceId: 'AC_02',
      deviceType: 'ac',
      color: '#aabbcc',
      mode: 'TURBO',
      stateSource: 'custom.source',
    }),
  ]));
  const weird = snapshot.devices[0];
  assert.equal(weird.deviceTypeRaw, 'weird');
  assert.equal(weird.deviceType, undefined);
  assert.equal(weird.isSupported, false);
  assert.equal(weird.roomNameHint, '');
  const counts = counter.counts();
  assert.equal(counts.get(DeviationCode.UNKNOWN_DEVICE_TYPE), 1);
  assert.equal(counts.get(DeviationCode.ROOM_NAME_MISSING), 1);
  const unknownTypeDeviation = snapshot.deviations.find(
    (item) => item.code === DeviationCode.UNKNOWN_DEVICE_TYPE,
  );
  assert.equal(unknownTypeDeviation.detail, 'unrecognized_type');
  assert.equal(snapshot.deviations.some((item) => item.detail === 'weird'), false);

  const ac = snapshot.devices[1];
  assert.equal(ac.color, '#AABBCC');
  assert.equal(ac.mode, 'TURBO');
  assert.equal(ac.modeStandard, false);
  assert.equal(ac.stateSourceKnown, false);
  assert.equal(counts.get(DeviationCode.LOWERCASE_COLOR_NORMALIZED), 1);
  assert.equal(counts.get(DeviationCode.NON_STANDARD_AC_MODE), 1);
  assert.equal(counts.get(DeviationCode.UNKNOWN_STATE_SOURCE), 1);
});

test('C03_DiscoverMapper_acceptsOversizeInboundIdAndSkipsInvalidDevices', () => {
  const oversized = 'D'.repeat(64);
  const { snapshot, counter } = map(baseEnvelope([
    device({ deviceId: oversized }),
    device({ deviceId: 'Bad:01' }),
    device({ deviceId: 'Bad_02', updatedAt: 'not-a-time' }),
    device({ deviceId: 'Unknown_01', unexpected: true }),
  ]));
  assert.equal(snapshot.devices.length, 1);
  assert.equal(snapshot.devices[0].deviceId, oversized);
  assert.equal(snapshot.isPartial, true);
  const counts = counter.counts();
  assert.equal(counts.get(DeviationCode.OVERSIZE_INBOUND_IDENTIFIER), 1);
  assert.equal(counts.get(DeviationCode.DEVICE_SKIPPED), 3);
});

test('C03_DiscoverMapper_readOnlyTypeIsKeptButNotSupported', () => {
  const { snapshot, counter } = map(baseEnvelope([
    device({ deviceId: 'Switch_01', deviceType: 'switch' }),
  ]));
  assert.equal(snapshot.devices.length, 1);
  assert.equal(snapshot.devices[0].deviceType, 'switch');
  assert.equal(snapshot.devices[0].isSupported, false);
  assert.equal(counter.total(), 0);
});

test('C03_DiscoverMapper_topLevelFailuresAreFailClosed', () => {
  assert.equal(mapError({ ...baseEnvelope([]), serviceId: 'Other' }).code,
    'DISCOVERY_INVALID_RESPONSE');
  assert.equal(mapError({ ...baseEnvelope([]), security: {
    alg: 'HMAC-SHA1', keyId: 'app-key-v1', timeWindowSeconds: 120, nonceTtlSeconds: 300,
  } }).code, 'DISCOVERY_INVALID_RESPONSE');
  assert.equal(mapError({ ...baseEnvelope([]), protocolVersion: '2.1' }).code,
    'PROTOCOL_UNSUPPORTED_VERSION');
  assert.equal(mapError({ ...baseEnvelope([]), extra: true }).code,
    'DISCOVERY_INVALID_RESPONSE');
  assert.equal(mapError({ ...baseEnvelope([]), gatewayName: undefined }).code,
    'PROTOCOL_MISSING_FIELD');
  assert.equal(mapError({ ...baseEnvelope([]), security: {
    alg: 'HMAC-SHA256', keyId: 'app-key-v1', timeWindowSeconds: 120,
  } }).code, 'PROTOCOL_MISSING_FIELD');
  assert.equal(mapError('{"a":1,"a":2}').code, 'PROTOCOL_DUPLICATE_KEY');
  assert.equal(mapError('{').code, 'PROTOCOL_INVALID_JSON');
  assert.equal(mapError(baseEnvelope([]), 'gw_02').code, 'GATEWAY_ID_MISMATCH');
});

test('C03_DiscoverMapper_emptyDeviceListIsAValidEnvelope', () => {
  const { snapshot, counter } = map(baseEnvelope([]));
  assert.equal(snapshot.devices.length, 0);
  assert.equal(snapshot.isPartial, false);
  assert.equal(counter.total(), 0);
});

test('C03_DeviationCounter_resetsAndCopiesCounts', () => {
  const counter = new DeviationCounter();
  counter.record(new ProtocolDeviation(DeviationCode.ALIAS_FIELD_USED, 'gw', 'dev', 'online', 'isOnline'));
  counter.record(new ProtocolDeviation(DeviationCode.ALIAS_FIELD_USED, 'gw', 'dev', 'power', 'powerStatus'));
  assert.equal(counter.total(), 2);
  assert.equal(counter.counts().get(DeviationCode.ALIAS_FIELD_USED), 2);
  const copy = counter.counts();
  copy.set(DeviationCode.ALIAS_FIELD_USED, 99);
  assert.equal(counter.counts().get(DeviationCode.ALIAS_FIELD_USED), 2);
  counter.reset();
  assert.equal(counter.total(), 0);
});
