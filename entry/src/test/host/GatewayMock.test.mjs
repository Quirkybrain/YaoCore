/*
 * YaoCore C-20 MockGatewayService / MockBleProvisioningClient host tests.
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §17.1-§17.5, §19.3; ADR-002 §7.3; SC-11; D-019.
 *
 * PUBLIC TEST DATA ONLY. Deterministic fake clock/random; no sleeps, no radio.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { AppError, AppErrors } from '../../main/ets/common/types/AppError.ets';
import { DeviceAction } from '../../main/ets/common/constants/DeviceConstants.ets';
import { GatewayAddress } from '../../main/ets/model/GatewayRoute.ets';
import { TransportProfile } from '../../main/ets/model/DeviceTypes.ets';
import { DeviceControlCommand, StateVerification } from '../../main/ets/model/ControlModels.ets';
import { IdentityVersion } from '../../main/ets/model/ProvisioningModels.ets';
import { CryptoService } from '../../main/ets/service/crypto/CryptoService.ets';
import {
  GatewayTarget,
} from '../../main/ets/service/gateway/GatewayTransportPorts.ets';
import { MockGatewayService } from '../../main/ets/service/mock/MockGatewayService.ets';
import { MockBleProvisioningClient } from '../../main/ets/service/mock/MockBleProvisioningClient.ets';
import {
  MockMode,
  MockScenario,
  MockTlsMode,
} from '../../main/ets/service/mock/MockScenario.ets';
import {
  BleProvisioningRequest,
  BleProvisioningStage,
  BleScanFilter,
} from '../../main/ets/service/ble/BleProvisioningPorts.ets';
import { FakeTransportClock, SequenceRandom } from './TransportFakes.ets';
import { TestCryptoProvider } from './TestCryptoProvider.ets';

const FIXED_MS = Date.UTC(2026, 9, 17, 8, 0, 0);
const FAMILY = '123e4567-e89b-12d3-a456-426614174000';
const GATEWAY = 'gateway_01';
const PIN_A = 'a'.repeat(64);
const SECRET = Buffer.from('0123456789abcdef', 'utf8');

const expectCode = async (fn, code) => {
  await assert.rejects(fn, (error) => {
    assert.ok(error instanceof AppError, `expected AppError, got ${error}`);
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
};

const target = (profile = TransportProfile.P_HMAC, pins = []) => new GatewayTarget(
  GATEWAY, FAMILY, new GatewayAddress('192.168.1.10', 9200), profile, pins, 9200,
  'yaocore.gateway.hmac.' + GATEWAY);

const command = (action = DeviceAction.SET_BRIGHTNESS, value = 42) => new DeviceControlCommand(
  GATEWAY, 'Light_01', action, FIXED_MS, value);

const setup = (scenario = MockScenario.normal()) => {
  const clock = new FakeTransportClock(FIXED_MS);
  const delays = [];
  const service = new MockGatewayService(scenario, clock,
    new SequenceRandom(new Uint8Array(16).fill(7)),
    new CryptoService(new TestCryptoProvider()), SECRET, GATEWAY, 'Mock Gateway',
    async (delayMs) => {
      delays.push(delayMs);
    });
  return { clock, delays, service };
};

test('C20_normal_discoverIsDeterministic', async () => {
  const first = setup(MockScenario.normal());
  const second = setup(MockScenario.normal());
  const one = await first.service.discover(target());
  const two = await second.service.discover(target());
  assert.equal(one.gatewayId, GATEWAY);
  assert.equal(one.devices.length, 4);
  assert.equal(one.gatewayName, two.gatewayName);
  assert.equal(one.generatedAt, two.generatedAt);
  assert.equal(one.devices[1].brightness, two.devices[1].brightness);
  assert.equal(one.devices[2].temperature, two.devices[2].temperature);
});

test('C20_offline_throwsUnreachable', async () => {
  const ctx = setup(MockScenario.offline());
  await expectCode(() => ctx.service.discover(target()), 'GATEWAY_UNREACHABLE');
  await expectCode(() => ctx.service.control(target(), command()), 'GATEWAY_UNREACHABLE');
});

test('C20_timeout_usesInjectedDelayAndClassifiesTimeout', async () => {
  const ctx = setup(MockScenario.timeout());
  await expectCode(() => ctx.service.control(target(), command()), 'GATEWAY_TIMEOUT');
  assert.deepEqual(ctx.delays, [6000]);
});

test('C20_devOnly_isRejected', async () => {
  const ctx = setup(MockScenario.devOnly());
  await expectCode(() => ctx.service.discover(target()), 'DEV_SIMULATOR_REJECTED');
  await expectCode(() => ctx.service.control(target(), command()), 'DEV_SIMULATOR_REJECTED');
});

test('C20_tlsPinMatch_probeReturnsMatchedPin', async () => {
  const ctx = setup(MockScenario.tlsPinMatch());
  const result = await ctx.service.probe(target(TransportProfile.P_TLS_PIN, [PIN_A]));
  assert.equal(result.profile, TransportProfile.P_TLS_PIN);
  assert.equal(result.tlsPinMatched, PIN_A);
  assert.equal(result.reachable, true);
});

test('C20_tlsPinMismatchAndHandshakeFail_areHardFailures', async () => {
  const mismatch = setup(MockScenario.tlsPinMismatch());
  await expectCode(() => mismatch.service.control(target(TransportProfile.P_TLS_PIN, [PIN_A]),
    command()), 'TLS_PIN_MISMATCH');
  const handshake = setup(MockScenario.tlsHandshakeFail());
  await expectCode(() => handshake.service.control(target(TransportProfile.P_TLS_PIN, [PIN_A]),
    command()), 'TLS_HANDSHAKE_FAILED');
  const noTls = setup(MockScenario.normal());
  await expectCode(() => noTls.service.control(target(TransportProfile.P_TLS_PIN, [PIN_A]),
    command()), 'TLS_HANDSHAKE_FAILED');
});

test('C20_normal_controlRunsProductionAckChain', async () => {
  const ctx = setup(MockScenario.normal());
  const outcome = await ctx.service.control(target(), command());
  assert.equal(outcome.ackAccepted, true);
  assert.equal(outcome.resultCode, 0);
  assert.equal(outcome.stateVerification, StateVerification.MATCH);
  assert.equal(outcome.shouldApplyState, true);
  assert.match(outcome.requestId, /^req-/);
});

test('C20_ackLost_firstAttemptTimesOutThenExactReplayDoesNotReapply', async () => {
  const ctx = setup(MockScenario.ackLost());
  await expectCode(() => ctx.service.control(target(), command()), 'GATEWAY_TIMEOUT');
  const replay = await ctx.service.control(target(), command());
  assert.equal(replay.ackAccepted, true);
  assert.equal(replay.idempotentReplay, true);
  assert.equal(replay.shouldApplyState, false);
});

test('C20_replay_sameCommandReplaysAndDifferentCommandReturns1005', async () => {
  const ctx = setup(MockScenario.replay());
  const first = await ctx.service.control(target(), command(DeviceAction.TURN_ON, undefined));
  assert.equal(first.ackAccepted, true);
  const replay = await ctx.service.control(target(), command(DeviceAction.TURN_ON, undefined));
  assert.equal(replay.idempotentReplay, true);
  assert.equal(replay.shouldApplyState, false);
  const conflict = await ctx.service.control(target(), command(DeviceAction.TURN_OFF, undefined));
  assert.equal(conflict.resultCode, 1005);
  assert.equal(conflict.ackAccepted, false);
  assert.equal(conflict.gatewayResult.known, true);
});

test('C20_resultCodeOverride_returnsSignedGatewayErrorWithoutThrowing', async () => {
  const scenario = new MockScenario(MockMode.NORMAL, MockTlsMode.DISABLED, 1, 0, 0, 1004,
    'bad_signature');
  const ctx = setup(scenario);
  const outcome = await ctx.service.control(target(), command());
  assert.equal(outcome.ackAccepted, false);
  assert.equal(outcome.resultCode, 1004);
  assert.equal(outcome.gatewayResult.stableName, 'bad_signature');
});

test('C20_omitReportedState_isProtocolViolation', async () => {
  const scenario = new MockScenario(MockMode.NORMAL, MockTlsMode.DISABLED, 1, 0, 0, 0,
    undefined, false, true);
  const ctx = setup(scenario);
  await expectCode(() => ctx.service.control(target(), command()), 'ACK_PROTOCOL_VIOLATION');
});

test('C20_badSignatureAndCorrelation_failClosed', async () => {
  const badSignature = new MockScenario(MockMode.NORMAL, MockTlsMode.DISABLED, 1, 0, 0,
    undefined, undefined, false, false, true);
  await expectCode(() => setup(badSignature).service.control(target(), command()),
    'CONTROL_RESPONSE_AUTH_FAILED');
  const badCorrelation = new MockScenario(MockMode.NORMAL, MockTlsMode.DISABLED, 1, 0, 0,
    undefined, undefined, false, false, false, true);
  await expectCode(() => setup(badCorrelation).service.control(target(), command()),
    'ACK_CORRELATION_MISMATCH');
});

test('C20_failAtAttempt_onlyThatRequestFails', async () => {
  const scenario = new MockScenario(MockMode.NORMAL, MockTlsMode.DISABLED, 1, 0, 1);
  const ctx = setup(scenario);
  await expectCode(() => ctx.service.discover(target()), 'GATEWAY_UNREACHABLE');
  const snapshot = await ctx.service.discover(target());
  assert.equal(snapshot.gatewayId, GATEWAY);
});

test('C20_deviceControlPortSendUsesMockGateway', async () => {
  const ctx = setup(MockScenario.normal());
  const outcome = await ctx.service.send(command());
  assert.equal(outcome.ackAccepted, true);
});

test('C20_mockBle_normalScanAndProvisionV20', async () => {
  const clock = new FakeTransportClock(FIXED_MS);
  const client = new MockBleProvisioningClient(MockScenario.normal(), clock,
    new SequenceRandom(new Uint8Array(4).fill(3)));
  const devices = [];
  let finished = false;
  await client.startScan(new BleScanFilter('YaoCore-GW-'), {
    onDeviceFound: (device) => devices.push(device),
    onScanFinished: () => { finished = true; },
  });
  assert.equal(devices.length, 1);
  assert.equal(devices[0].deviceId, 'Mock_Gateway_01');
  assert.equal(finished, true);
  const stages = [];
  const result = await client.provision(
    new BleProvisioningRequest('home-wifi', Buffer.from('password'), Buffer.from('pop')),
    { onStage: (stage) => stages.push(stage) });
  assert.equal(result.identity.version, IdentityVersion.V20);
  assert.equal(result.identity.tls, undefined);
  assert.equal(result.ip, '192.168.1.10');
  assert.ok(stages.includes(BleProvisioningStage.DONE));
  assert.ok(stages.includes(BleProvisioningStage.BINDING_PROBE));
});

test('C20_mockBle_tlsModeReturnsV21PinsAndOfflineFails', async () => {
  const clock = new FakeTransportClock(FIXED_MS);
  const tlsClient = new MockBleProvisioningClient(MockScenario.tlsPinMatch(), clock,
    new SequenceRandom(new Uint8Array(4).fill(3)));
  const result = await tlsClient.provision(
    new BleProvisioningRequest('home-wifi', Buffer.from('password'), Buffer.from('pop')),
    { onStage: () => {} });
  assert.equal(result.identity.version, IdentityVersion.V21);
  assert.equal(result.identity.tls.pins[0], PIN_A);
  assert.equal(result.port, 9200);
  const offline = new MockBleProvisioningClient(MockScenario.offline(), clock,
    new SequenceRandom(new Uint8Array(4).fill(3)));
  await expectCode(() => offline.startScan(new BleScanFilter(), {
    onDeviceFound: () => {},
    onScanFinished: () => {},
  }), 'PROVISIONING_DEVICE_NOT_FOUND');
  const timeout = new MockBleProvisioningClient(MockScenario.timeout(), clock,
    new SequenceRandom(new Uint8Array(4).fill(3)));
  await expectCode(() => timeout.provision(
    new BleProvisioningRequest('home-wifi', Buffer.from('password'), Buffer.from('pop')),
    { onStage: () => {} }), 'PROVISIONING_WIFI_TIMEOUT');
});

test('C20_mockBle_cancelIsObservedBetweenStages', async () => {
  const clock = new FakeTransportClock(FIXED_MS);
  const client = new MockBleProvisioningClient(MockScenario.normal(), clock,
    new SequenceRandom(new Uint8Array(4).fill(3)));
  const cancellation = {
    cancelled: true,
    onCancel: () => {},
    throwIfCancelled: () => {
      throw AppErrors.of('PROVISIONING_CANCELLED', []);
    },
  };
  await expectCode(() => client.provision(
    new BleProvisioningRequest('home-wifi', Buffer.from('password'), Buffer.from('pop')),
    { onStage: () => {} }, cancellation), 'PROVISIONING_CANCELLED');
});
