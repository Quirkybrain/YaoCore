/*
 * YaoCore C-19 BleProvisioningService end-to-end host tests.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Traceability: DES-A §16.1-§16.11; BLE设计 §2-§7; TEST-001 CQG-T12.
 *
 * PUBLIC TEST DATA ONLY. A deterministic fake ESP-IDF gateway and Node crypto
 * oracle exercise the full flow without platform BLE or a real gateway.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { AppError } from '../../main/ets/common/types/AppError.ets';
import { BleScanFilter, BleWifiScanRequest, ProvisioningState } from '../../main/ets/model/ProvisioningModels.ets';
import { GattEndpointMap } from '../../main/ets/model/GattEndpointMap.ets';
import { IdentityVersion } from '../../main/ets/model/ProvisioningModels.ets';
import {
  FakeClock,
  FakeGateway,
  GATEWAY_ID,
  SECRET_HEX,
  createRequest,
  hex,
  makeDevice,
  makeService,
  putDraft,
  utf8,
} from './BleFakes.mjs';

const serviceUuid = GattEndpointMap.SERVICE_UUID;

const expectCode = async (fn, code) => {
  await assert.rejects(fn, (error) => {
    assert.ok(error instanceof AppError, 'expected AppError');
    assert.equal(error.code, code);
    return true;
  });
};

const listener = () => {
  const events = { stages: [], states: [], aps: [], errors: [], completed: [] };
  events.listener = {
    onStage: (stage) => events.stages.push(stage),
    onStateChanged: (progress) => events.states.push(progress.state),
    onAccessPoints: (aps) => events.aps.push(...aps),
    onError: (error) => events.errors.push(error),
    onCompleted: (result) => events.completed.push(result),
  };
  return events;
};

test('C19_BleProvisioningService_happyPathV21', async () => {
  const ctx = makeService();
  const events = listener();
  const request = createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID });
  const result = await ctx.service.provision(request, events.listener);
  assert.equal(result.identity.version, IdentityVersion.V21);
  assert.equal(result.identity.gatewayId, GATEWAY_ID);
  assert.equal(result.ip, '192.168.1.50');
  assert.equal(result.port, 9200);
  assert.equal(result.boardLedConfirmed, true);
  assert.equal(result.credentialDraftId, '');
  assert.match(result.completedAt, /^[0-9]{8}T[0-9]{6}Z$/);
  assert.equal(ctx.gateway.config.ssid, 'home-wifi');
  assert.equal(ctx.gateway.config.password, 'password');
  assert.equal(ctx.gateway.applied, true);
  assert.deepEqual(ctx.gateway.identityRequests, ['2.1']);
  assert.equal(ctx.connection.disconnectCalls >= 1, true);
  assert.equal(ctx.service.state, ProvisioningState.BOUND);
  assert.equal(events.completed.length, 1);
  assert.equal(events.errors.length, 0);
  assert.deepEqual(events.stages, [
    'CONNECTING', 'SECURITY', 'IDENTITY', 'WIFI_SCAN', 'WIFI_APPLY', 'WIFI_STATUS',
    'DONE', 'BINDING_PROBE',
  ]);
  assert.equal(events.states.includes(ProvisioningState.BOUND), true);
  assert.equal(events.aps.length, 2);
  assert.equal(ctx.gatewayClient.probeTargets[0].profile, 'P-TLS-PIN');
  assert.equal(ctx.gatewayClient.secrets[0], SECRET_HEX);
  assert.equal(ctx.gatewayClient.controlTargets.length, 2);
});

test('C19_BleProvisioningService_v20FallbackUsesHmacProfile', async () => {
  const ctx = makeService({ gateway: new FakeGateway({ identityMode: 'v20' }) });
  const request = createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID });
  const result = await ctx.service.provision(request, listener().listener);
  assert.equal(result.identity.version, IdentityVersion.V20);
  assert.equal(result.identity.tls, undefined);
  assert.equal(result.port, 9200);
  assert.deepEqual(ctx.gateway.identityRequests, ['2.1', '2.0']);
  assert.equal(ctx.gatewayClient.probeTargets[0].profile, 'P-HMAC');
});

test('C19_BleProvisioningService_publicScanDedupesAndStops', async () => {
  const device = makeDevice();
  const ctx = makeService({
    devices: [device, device],
    transportOptions: { scanFinishes: false },
  });
  const devices = [];
  let finished = 0;
  await ctx.service.startScan(new BleScanFilter(serviceUuid, 'YaoCore-GW-', 20), {
    onDeviceFound: (found) => devices.push(found),
    onScanFinished: () => { finished++; },
    onScanError: () => {},
  });
  assert.equal(devices.length, 1);
  await ctx.service.stopScan();
  assert.equal(finished, 1);
  assert.equal(ctx.transport.scanFilter.serviceUuid, serviceUuid);
});

test('C19_BleProvisioningService_scanPermissionAndBluetoothFailClosed', async () => {
  const denied = makeService({
    transportOptions: {
      permissionError: new AppError('PROVISIONING_PERMISSION_DENIED',
        'PROVISIONING', 'x', false),
    },
  });
  await expectCode(() => denied.service.startScan(
    new BleScanFilter(serviceUuid), {
      onDeviceFound: () => {}, onScanFinished: () => {}, onScanError: () => {},
    }), 'PROVISIONING_PERMISSION_DENIED');
  const off = makeService({ transportOptions: { bluetoothEnabled: false } });
  await expectCode(() => off.service.startScan(
    new BleScanFilter(serviceUuid), {
      onDeviceFound: () => {}, onScanFinished: () => {}, onScanError: () => {},
    }), 'PROVISIONING_BLUETOOTH_OFF');
});

test('C19_BleProvisioningService_deviceSelection', async () => {
  const single = makeService({ devices: [makeDevice()] });
  const result = await single.service.provision(
    createRequest({ expectedGatewayId: GATEWAY_ID }), listener().listener);
  assert.equal(result.identity.gatewayId, GATEWAY_ID);
  assert.equal(single.transport.connectCalls, 1);

  const multiple = makeService({
    devices: [makeDevice({ deviceId: 'AA:00:00:00:00:01' }),
      makeDevice({ deviceId: 'AA:00:00:00:00:02' })],
    transportOptions: { scanFinishes: false },
  });
  await expectCode(() => multiple.service.provision(
    createRequest({ expectedGatewayId: GATEWAY_ID }), listener().listener),
  'PROVISIONING_MULTIPLE_DEVICES');

  const none = makeService({ devices: [] });
  await expectCode(() => none.service.provision(
    createRequest({ expectedGatewayId: GATEWAY_ID }), listener().listener),
  'PROVISIONING_DEVICE_NOT_FOUND');
});

test('C19_BleProvisioningService_permissionAndBluetoothProvisionFailClosed', async () => {
  const denied = makeService({
    transportOptions: { permissionError: new AppError('PROVISIONING_PERMISSION_DENIED',
      'PROVISIONING', 'x', false) },
  });
  await expectCode(() => denied.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener), 'PROVISIONING_PERMISSION_DENIED');
  assert.equal(denied.service.state, ProvisioningState.FAILED);

  const off = makeService({ transportOptions: { bluetoothEnabled: false } });
  await expectCode(() => off.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener), 'PROVISIONING_BLUETOOTH_OFF');
});

test('C19_BleProvisioningService_connectAndMtuFailuresCleanUp', async () => {
  const connect = makeService({
    transportOptions: { connectError: new AppError('PROVISIONING_CONNECT_FAILED',
      'PROVISIONING', 'x', true) },
  });
  await expectCode(() => connect.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener), 'PROVISIONING_CONNECT_FAILED');

  const mtu = makeService({ connectionOptions: { mtu: 246 } });
  const events = listener();
  await expectCode(() => mtu.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    events.listener), 'PROVISIONING_MTU_TOO_SMALL');
  assert.equal(mtu.service.state, ProvisioningState.FAILED);
  assert.equal(mtu.connection.disconnectCalls >= 1, true);
  assert.equal(events.errors.length, 1);
});

test('C19_BleProvisioningService_gattIncompleteFailures', async () => {
  const missing = makeService({ connectionOptions: { endpoints: [
    'proto-ver', 'prov-session', 'prov-config', 'prov-ctrl', 'yaocore-id',
  ] } });
  await expectCode(() => missing.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener), 'PROVISIONING_GATT_INCOMPLETE');
  const readOnly = makeService({ connectionOptions: { readOnlyCharacteristic: true } });
  await expectCode(() => readOnly.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener), 'PROVISIONING_GATT_INCOMPLETE');
});

test('C19_BleProvisioningService_capabilityAndPopFailures', async () => {
  const capability = makeService({
    gateway: new FakeGateway({
      protoVerBody: utf8(JSON.stringify({
        prov: { ver: 'v1.1', sec_ver: 1, cap: [] }, yaocore: { ver: '2.0' },
      })),
    }),
  });
  await expectCode(() => capability.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener), 'PROVISIONING_CAPABILITY_UNSUPPORTED');

  const pop = makeService({ gateway: new FakeGateway({ pop: 'device-pop' }) });
  const events = listener();
  await expectCode(() => pop.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    events.listener), 'PROVISIONING_POP_INVALID');
  assert.equal(pop.service.state, ProvisioningState.FAILED);
  assert.equal(pop.connection.disconnectCalls >= 1, true);
  assert.equal(events.errors[0].code, 'PROVISIONING_POP_INVALID');
});

test('C19_BleProvisioningService_identityAndExpectedIdFailures', async () => {
  const invalid = makeService({ gateway: new FakeGateway({ identityMode: 'invalid' }) });
  await expectCode(() => invalid.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener), 'PROVISIONING_IDENTITY_INVALID');
  assert.deepEqual(invalid.gateway.identityRequests, ['2.1', '2.0']);

  const expected = makeService();
  await expectCode(() => expected.service.provision(createRequest({
    device: makeDevice(), expectedGatewayId: 'gateway_other',
  }), listener().listener), 'PROVISIONING_BINDING_IDENTITY_MISMATCH');
});

test('C19_BleProvisioningService_wifiAuthNetworkAndTimeoutClassification', async () => {
  const auth = makeService({ gateway: new FakeGateway({
    statusSequence: [{ state: 'failed', reason: 'auth' }],
  }) });
  await expectCode(() => auth.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener), 'PROVISIONING_WIFI_AUTH_ERROR');
  const network = makeService({ gateway: new FakeGateway({
    statusSequence: [{ state: 'failed', reason: 'network' }],
  }) });
  await expectCode(() => network.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener), 'PROVISIONING_WIFI_NETWORK_NOT_FOUND');
  const timeout = makeService({ gateway: new FakeGateway({
    statusSequence: [{ state: 'connecting' }],
  }) });
  await expectCode(() => timeout.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener), 'PROVISIONING_WIFI_TIMEOUT');
});

test('C19_BleProvisioningService_scanAndDoneFailures', async () => {
  const scan = makeService({ gateway: new FakeGateway({ scanPolls: 100000 }) });
  await expectCode(() => scan.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener), 'PROVISIONING_WIFI_SCAN_FAILED');
  const done = makeService({ gateway: new FakeGateway({ doneBody: utf8('{"ok":false}') }) });
  await expectCode(() => done.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener), 'PROVISIONING_DONE_REJECTED');
});

test('C19_BleProvisioningService_cancelIsTerminalAndCleansUp', async () => {
  const ctx = makeService();
  const events = listener();
  const promise = ctx.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }), events.listener);
  await ctx.service.cancel();
  await expectCode(() => promise, 'PROVISIONING_CANCELLED');
  assert.equal(ctx.service.state, ProvisioningState.CANCELLED);
  assert.equal(events.states.includes(ProvisioningState.CANCELLED), true);
});

test('C19_BleProvisioningService_preCancelledTokenRejectsBeforeConnect', async () => {
  const ctx = makeService();
  const cancellation = {
    cancelled: true,
    onCancel: () => {},
    throwIfCancelled: () => {
      throw new AppError('PROVISIONING_CANCELLED', 'PROVISIONING', 'x', true);
    },
  };
  await expectCode(() => ctx.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener, cancellation), 'PROVISIONING_CANCELLED');
  assert.equal(ctx.transport.connectCalls, 0);
});

test('C19_BleProvisioningService_probeFailuresNeverBind', async () => {
  const mismatch = makeService({ gatewayClientOptions: { probeGatewayId: 'gateway_02' } });
  await expectCode(() => mismatch.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener), 'PROVISIONING_BINDING_IDENTITY_MISMATCH');
  assert.equal(mismatch.gatewayClient.probeCalls, 1);

  const unreachable = makeService({ gatewayClientOptions: { failProbes: 5 } });
  await expectCode(() => unreachable.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener), 'PROVISIONING_BINDING_PROBE_FAILED');
  assert.equal(unreachable.gatewayClient.probeCalls, 5);

  const led = makeService({ gatewayClientOptions: { boardLed: false } });
  await expectCode(() => led.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener), 'PROVISIONING_BOARD_LED_UNCONFIRMED');
  assert.equal(led.gatewayClient.probeCalls, 1);
});

test('C19_BleProvisioningService_tlsPinMismatchNeverBinds', async () => {
  const ctx = makeService({
    gatewayClientOptions: { tlsPinMatchedOverride: 'b'.repeat(64) },
  });
  await expectCode(() => ctx.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener), 'PROVISIONING_BINDING_PROBE_FAILED');
  assert.equal(ctx.gatewayClient.probeCalls, 5);
});

test('C19_BleProvisioningService_draftLifecycleOnSuccessAndFailure', async () => {
  const success = makeService();
  const originalId = putDraft(success.drafts, SECRET_HEX);
  const result = await success.service.provision(createRequest({
    device: makeDevice(), draftId: originalId,
  }), listener().listener);
  assert.notEqual(result.credentialDraftId, originalId);
  assert.equal(success.gatewayClient.secrets[0], SECRET_HEX);
  const issued = success.drafts.take(result.credentialDraftId);
  assert.equal(issued.toHex(), SECRET_HEX);
  issued.destroy();

  const failure = makeService({ gateway: new FakeGateway({ identityMode: 'invalid' }) });
  const failedId = putDraft(failure.drafts, SECRET_HEX);
  await expectCode(() => failure.service.provision(createRequest({
    device: makeDevice(), draftId: failedId,
  }), listener().listener), 'PROVISIONING_IDENTITY_INVALID');
  assert.throws(() => failure.drafts.take(failedId), (error) =>
    error.code === 'PROVISIONING_CREDENTIAL_MISSING');
});

test('C19_BleProvisioningService_missingExistingCredentialFailsClosed', async () => {
  const ctx = makeService({ credentialsSecretHex: '' });
  await expectCode(() => ctx.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener), 'PROVISIONING_CREDENTIAL_MISSING');
});

test('C19_BleProvisioningService_latestScanWinsWhenDeviceOmitted', async () => {
  const deviceA = makeDevice({ deviceId: 'AA:00:00:00:00:01' });
  const deviceB = makeDevice({ deviceId: 'AA:00:00:00:00:02' });
  const ctx = makeService({ devices: [deviceA], transportOptions: { scanFinishes: false } });
  const filter = new BleScanFilter(serviceUuid, 'YaoCore-GW-', 20);
  const noopScan = {
    onDeviceFound: () => {},
    onScanFinished: () => {},
    onScanError: () => {},
  };
  await ctx.service.startScan(filter, noopScan);
  await ctx.service.stopScan();
  ctx.transport.devices = [deviceB];
  await ctx.service.startScan(filter, noopScan);
  await ctx.service.stopScan();

  const result = await ctx.service.provision(
    createRequest({ expectedGatewayId: GATEWAY_ID }), listener().listener);
  assert.equal(ctx.transport.connectCalls, 1);
  assert.equal(ctx.transport.connectedDeviceId, 'AA:00:00:00:00:02',
    'omitting request.device must connect the most recent scan, not the first');
  assert.equal(result.identity.gatewayId, GATEWAY_ID);
});

test('C19_BleProvisioningService_emptyDraftRequiresExpectedGatewayId', async () => {
  const missing = makeService();
  await expectCode(() => missing.service.provision(
    createRequest({ device: makeDevice() }), listener().listener), 'CONFIGURATION_ERROR');
  assert.equal(missing.transport.connectCalls, 0);
  assert.equal(missing.credentials.calls, 0);

  // A draft identifies a new binding and does not require expectedGatewayId.
  const draft = makeService();
  const draftId = putDraft(draft.drafts, SECRET_HEX);
  const result = await draft.service.provision(
    createRequest({ device: makeDevice(), draftId }), listener().listener);
  assert.equal(result.identity.gatewayId, GATEWAY_ID);
});

test('C19_BleProvisioningService_postProbeListenerFailureDestroysReissuedDraft', async () => {
  const ctx = makeService();
  const originalId = putDraft(ctx.drafts, SECRET_HEX);
  const throwing = {
    onStage: () => {},
    onStateChanged: () => {},
    onCompleted: () => {
      throw new Error('listener boom');
    },
  };
  await expectCode(() => ctx.service.provision(
    createRequest({ device: makeDevice(), draftId: originalId }), throwing), 'INTERNAL_ERROR');
  assert.equal(ctx.gatewayClient.probeCalls, 1);
  assert.equal(ctx.drafts.size(), 0,
    'the re-issued draft must not survive a post-probe listener failure (SC-06)');
});

test('C19_BleProvisioningService_listenerExceptionsDoNotLockRunning', async () => {
  const ctx = makeService();
  let stageThrew = false;
  const stageListener = {
    onStage: () => {
      if (!stageThrew) {
        stageThrew = true;
        throw new Error('stage boom');
      }
    },
    onStateChanged: () => {},
    onError: () => {},
  };
  await expectCode(() => ctx.service.provision(
    createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    stageListener), 'INTERNAL_ERROR');

  let stateCalls = 0;
  const stateListener = {
    onStage: () => {},
    onStateChanged: () => {
      stateCalls++;
      if (stateCalls === 1) {
        throw new Error('state boom');
      }
    },
    onError: () => {},
  };
  await expectCode(() => ctx.service.provision(
    createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    stateListener), 'INTERNAL_ERROR');

  const result = await ctx.service.provision(
    createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener);
  assert.equal(result.identity.gatewayId, GATEWAY_ID,
    'a throwing listener must not leave the service locked in running state');
});

test('C19_BleProvisioningService_retryUsesNewSessionAndKeypair', async () => {
  const gateway = new FakeGateway({ pop: 'wrong-pop' });
  const ctx = makeService({ gateway });
  await expectCode(() => ctx.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener), 'PROVISIONING_POP_INVALID');
  assert.equal(ctx.crypto.keyPairCalls, 1);
  gateway.pop = 'pop';
  const result = await ctx.service.provision(createRequest({ device: makeDevice(), expectedGatewayId: GATEWAY_ID }),
    listener().listener);
  assert.equal(result.identity.gatewayId, GATEWAY_ID);
  assert.equal(ctx.crypto.keyPairCalls, 2);
  const step0Writes = ctx.gateway.requests
    .filter((entry) => entry.endpoint === 'prov-session')
    .map((entry) => hex(entry.value));
  assert.equal(step0Writes.length, 4);
  assert.notEqual(step0Writes[0], step0Writes[2],
    'a retry must not reuse the previous Security1 keypair/state');
});

test('T18_C19_scanWifiAccessPointsHandshakesWithoutApplyingCredentials', async () => {
  const ctx = makeService();
  const events = listener();
  const aps = await ctx.service.scanWifiAccessPoints(
    new BleWifiScanRequest(utf8('pop'), makeDevice(), GATEWAY_ID), events.listener);
  assert.equal(aps.length, 2);
  assert.equal(events.aps.length, 2);
  assert.deepEqual(events.stages, ['CONNECTING', 'SECURITY', 'IDENTITY', 'WIFI_SCAN']);
  assert.equal(events.states.includes(ProvisioningState.AP_SCANNING), true);
  assert.equal(ctx.gateway.applied, false);
  assert.equal(ctx.gateway.config, undefined);
  assert.equal(ctx.connection.disconnectCalls >= 1, true);
  // The BLE link is torn down after the preview scan.
  assert.equal(ctx.service.running, false);
});
