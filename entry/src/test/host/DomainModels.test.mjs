/*
 * YaoCore C-02 domain model host tests.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Traceability: DES-A §5.1, §5.3; D-019 host layer.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { AppError, AppErrors } from '../../main/ets/common/types/AppError.ets';
import { StorageConstants } from '../../main/ets/common/constants/StorageConstants.ets';
import {
  DeviceAction,
  DeviceConstants,
  DeviceType,
} from '../../main/ets/common/constants/DeviceConstants.ets';
import { DeviceKey } from '../../main/ets/model/DeviceKey.ets';
import {
  DeviceSnapshot,
  DeviceSnapshotInit,
  DeviceState,
  DeviceStatePatch,
  DeviceStatePatchInit,
  RoomRef,
} from '../../main/ets/model/DeviceState.ets';
import {
  AcMode,
  StateSource,
  TransportProfile,
} from '../../main/ets/model/DeviceTypes.ets';
import {
  GatewayAddress,
  GatewayRoute,
  GatewayRouteInit,
  TlsMaterial,
} from '../../main/ets/model/GatewayRoute.ets';
import {
  ControlOutcome,
  ControlOutcomeInit,
  DeviceControlCommand,
  GatewayBoardState,
  StateVerification,
} from '../../main/ets/model/ControlModels.ets';
import {
  DiscoverySecurity,
  DiscoverySnapshot,
  DiscoverySnapshotInit,
} from '../../main/ets/model/DiscoveryModels.ets';
import {
  BleProvisioningIdentity,
  BleProvisioningResult,
  IdentityVersion,
  ProvisioningTlsMaterial,
} from '../../main/ets/model/ProvisioningModels.ets';
import {
  CloudConfig,
  Family,
  FamilyMember,
  InvitationRecord,
  InvitationStatus,
  InviteMode,
  MemberRole,
  MemberStatus,
  Room,
  Scene,
  SceneAction,
} from '../../main/ets/model/FamilyModels.ets';
import { GatewayResultClassifier } from '../../main/ets/common/types/GatewayResult.ets';

const UUID_A = '123e4567-e89b-12d3-a456-426614174000';
const UUID_B = '123e4567-e89b-12d3-a456-426614174001';
const PIN = 'a'.repeat(64);

const expectCode = (fn, code) => {
  assert.throws(fn, (error) => {
    assert.ok(error instanceof AppError, `expected AppError, got ${error}`);
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
};

const snapshot = (overrides = {}) => {
  const init = new DeviceSnapshotInit();
  init.deviceId = 'Light_01';
  init.deviceName = '客厅灯光';
  init.roomNameHint = '客厅';
  init.deviceTypeRaw = 'light';
  init.deviceType = DeviceType.LIGHT;
  init.isSupported = true;
  init.isOnline = true;
  init.updatedAt = '20261017T120000Z';
  init.brightness = 68;
  for (const key of Object.keys(overrides)) {
    init[key] = overrides[key];
  }
  return DeviceSnapshot.create(init);
};

test('C02_DeviceKey_derivesGlobalIdAndNeverParsesIt', () => {
  const key = new DeviceKey('gw_01', 'Light_01');
  assert.equal(key.globalId(), 'gw_01:Light_01');
  assert.equal(key.equals(new DeviceKey('gw_01', 'Light_01')), true);
  assert.equal(key.equals(new DeviceKey('gw_01', 'Light_02')), false);
  expectCode(() => new DeviceKey('gw:01', 'Light_01'), 'PROTOCOL_INVALID_IDENTIFIER');
  expectCode(() => new DeviceKey('gw_01', ''), 'PROTOCOL_INVALID_IDENTIFIER');
});

test('C02_DeviceSnapshot_derivesStateEpochAndValidatesRanges', () => {
  const item = snapshot();
  assert.equal(item.stateEpochMs, Date.UTC(2026, 9, 17, 12, 0, 0));
  assert.equal(item.isSupported, true);
  assert.equal(item.brightness, 68);
  expectCode(() => snapshot({ brightness: 101 }), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(() => snapshot({ temperature: 126 }), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(() => snapshot({ targetTemperature: 15 }), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(() => snapshot({ color: '#ffffff' }), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(() => snapshot({ updatedAt: 'not-a-time' }), 'PROTOCOL_INVALID_TIMESTAMP');
  expectCode(() => snapshot({ isSupported: false }), 'CONFIGURATION_ERROR');
  expectCode(() => snapshot({ mode: 'M'.repeat(33) }), 'PROTOCOL_VALUE_OUT_OF_RANGE');
});

test('C02_DeviceState_separatesLocalAndGatewayAuthority', () => {
  const item = snapshot();
  const key = new DeviceKey('gw_01', 'Light_01');
  const state = new DeviceState(key, 'family-1', item, '本地灯', '', true, true, false);
  assert.equal(state.isUnassigned, true);
  assert.equal(state.deviceName, '本地灯');
  assert.equal(state.snapshot.deviceName, '客厅灯光');

  const assigned = new DeviceState(key, 'family-1', item, '本地灯', UUID_A, true, false, false);
  assert.equal(assigned.roomId, UUID_A);
  expectCode(() => new DeviceState(key, 'family-1', item, '本地灯', '', false, false, false),
    'CONFIGURATION_ERROR');
  expectCode(() => new DeviceState(key, 'family-1', item, '本地灯', UUID_A, true, true, false),
    'CONFIGURATION_ERROR');
  expectCode(() => new DeviceState(key, 'family-1', item, '本地灯', 'room-1', true, false, false),
    'CONFIGURATION_ERROR');

  const ref = new RoomRef(UUID_A, '客厅');
  assert.equal(ref.roomName, '客厅');
  expectCode(() => new RoomRef('room-1', '客厅'), 'PROTOCOL_INVALID_IDENTIFIER');
});

test('C02_DeviceStatePatch_acceptsAckFieldsWithoutDeviceMetadata', () => {
  const init = new DeviceStatePatchInit();
  init.deviceId = 'Light_01';
  init.isOnline = true;
  init.powerStatus = true;
  init.brightness = 42;
  init.updatedAt = '20261017T120000Z';
  const patch = DeviceStatePatch.create(init);
  assert.equal(patch.stateEpochMs, Date.UTC(2026, 9, 17, 12, 0, 0));
  assert.equal(patch.brightness, 42);
  init.brightness = 101;
  expectCode(() => DeviceStatePatch.create(init), 'PROTOCOL_VALUE_OUT_OF_RANGE');
});

test('C02_GatewayRoute_enforcesHmacAndTlsProfiles', () => {
  const hmac = new GatewayRouteInit();
  hmac.gatewayId = 'gw_01';
  hmac.familyId = 'family-1';
  hmac.gatewayName = 'YaoCore Gateway';
  hmac.localIp = '192.168.1.10';
  hmac.port = 9200;
  hmac.profile = TransportProfile.P_HMAC;
  hmac.tlsEnabled = false;
  hmac.pins = [];
  hmac.pinAlg = '';
  hmac.keyId = 'app-key-v1';
  hmac.credentialAlias = StorageConstants.gatewayHmacAlias('gw_01');
  hmac.createdAt = '20261017T120000Z';
  hmac.updatedAt = '20261017T120000Z';
  const route = GatewayRoute.create(hmac);
  assert.equal(route.profile, TransportProfile.P_HMAC);
  assert.equal(route.pins.length, 0);

  const tls = new GatewayRouteInit();
  tls.gatewayId = 'gw_02';
  tls.familyId = 'family-1';
  tls.gatewayName = 'YaoCore Gateway';
  tls.localIp = '192.168.1.11';
  tls.port = 9443;
  tls.profile = TransportProfile.P_TLS_PIN;
  tls.tlsEnabled = true;
  tls.pins = [PIN];
  tls.pinAlg = 'sha256-spki-der';
  tls.keyId = 'app-key-v1';
  tls.credentialAlias = StorageConstants.gatewayHmacAlias('gw_02');
  tls.createdAt = '20261017T120000Z';
  tls.updatedAt = '20261017T120000Z';
  assert.equal(GatewayRoute.create(tls).pins[0], PIN);

  const bad = { ...tls, profile: TransportProfile.P_HMAC };
  expectCode(() => GatewayRoute.create(bad), 'TLS_PROFILE_INCONSISTENT');
  expectCode(() => GatewayRoute.create({ ...tls, profile: TransportProfile.P_BLOCKED }),
    'TLS_PROFILE_INCONSISTENT');
  expectCode(() => GatewayRoute.create({ ...tls, pins: ['A'.repeat(64)] }),
    'TLS_PIN_CONFIG_INVALID');
  expectCode(() => GatewayRoute.create({ ...tls, port: 0 }), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(() => GatewayRoute.create({ ...tls, gatewayId: 'gw:02' }),
    'PROTOCOL_INVALID_IDENTIFIER');

  assert.equal(new GatewayAddress('192.168.1.10', 9200).port, 9200);
  assert.equal(new TlsMaterial([PIN], 9443, 'sha256-spki-der').pins.length, 1);
  expectCode(() => new TlsMaterial([], 9443, 'sha256-spki-der'), 'TLS_PIN_CONFIG_INVALID');
});

test('C02_ControlOutcome_refusesOptimisticSuccess', () => {
  const patchInit = new DeviceStatePatchInit();
  patchInit.deviceId = 'Light_01';
  patchInit.isOnline = true;
  patchInit.brightness = 42;
  patchInit.updatedAt = '20261017T120000Z';
  const patch = DeviceStatePatch.create(patchInit);

  const init = new ControlOutcomeInit();
  init.requestId = 'req-1729000000000-1';
  init.seq = 1;
  init.resultCode = 0;
  init.serverTime = '20261017T120000Z';
  init.ackAccepted = true;
  init.reportedState = patch;
  init.stateVerification = StateVerification.MATCH;
  init.gatewayResult = GatewayResultClassifier.classify(0);
  init.shouldApplyState = true;
  const outcome = ControlOutcome.create(init);
  assert.equal(outcome.ackAccepted, true);
  assert.equal(outcome.stateVerification, StateVerification.MATCH);

  const noState = new ControlOutcomeInit();
  noState.requestId = 'req-1729000000000-1';
  noState.seq = 1;
  noState.resultCode = 0;
  noState.ackAccepted = true;
  noState.gatewayResult = GatewayResultClassifier.classify(0);
  expectCode(() => ControlOutcome.create(noState), 'CONFIGURATION_ERROR');

  const optimistic = new ControlOutcomeInit();
  optimistic.requestId = 'req-1729000000000-1';
  optimistic.seq = 1;
  optimistic.resultCode = 0;
  optimistic.ackAccepted = true;
  optimistic.reportedState = patch;
  optimistic.gatewayResult = GatewayResultClassifier.classify(1007);
  expectCode(() => ControlOutcome.create(optimistic), 'CONFIGURATION_ERROR');

  const command = new DeviceControlCommand('gw_01', 'Light_01', DeviceAction.SET_BRIGHTNESS,
    1729000000000, 42);
  assert.equal(command.value, 42);
  expectCode(() => new DeviceControlCommand('gw_01', 'gw:01', DeviceAction.TURN_ON,
    1729000000000), 'PROTOCOL_INVALID_IDENTIFIER');

  const board = new GatewayBoardState('gw_01', true, true, '20261017T120000Z');
  assert.equal(board.boardLed, true);
});

test('C02_DiscoverySnapshot_enforcesWireConstants', () => {
  const security = new DiscoverySecurity('HMAC-SHA256', 'app-key-v1', 120, 300);
  const init = new DiscoverySnapshotInit();
  init.gatewayId = 'gw_01';
  init.gatewayName = 'YaoCore Gateway';
  init.generatedAt = '20261017T120000Z';
  init.security = security;
  init.devices = [];
  init.isPartial = false;
  const discovery = DiscoverySnapshot.create(init);
  assert.equal(discovery.protocolVersion, '2.0');
  assert.equal(discovery.devices.length, 0);
  expectCode(() => new DiscoverySecurity('HMAC-SHA1', 'app-key-v1', 120, 300),
    'DISCOVERY_INVALID_RESPONSE');
  expectCode(() => DiscoverySnapshot.create({ ...init, protocolVersion: '2.1' }),
    'DISCOVERY_INVALID_RESPONSE');
});

test('C02_ProvisioningIdentity_andResultRespectTlsPorts', () => {
  const v20 = new BleProvisioningIdentity(IdentityVersion.V20, 'gw_01', 'Gateway');
  assert.equal(v20.tls, undefined);
  expectCode(() => new BleProvisioningIdentity(IdentityVersion.V20, 'gw_01', 'Gateway',
    new ProvisioningTlsMaterial([PIN], 9443, 'sha256-spki-der')), 'PROVISIONING_IDENTITY_INVALID');

  const v21 = new BleProvisioningIdentity(IdentityVersion.V21, 'gw_01', 'Gateway',
    new ProvisioningTlsMaterial([PIN], 9443, 'sha256-spki-der'));
  const result = new BleProvisioningResult(v21, '192.168.1.10', 9443, true, 'draft-1',
    '20261017T120000Z');
  assert.equal(result.port, 9443);
  expectCode(() => new BleProvisioningResult(v21, '192.168.1.10', 9200, true, 'draft-1',
    '20261017T120000Z'), 'CONFIGURATION_ERROR');
  assert.equal(new BleProvisioningResult(v20, '192.168.1.10', 9200, true, '',
    '20261017T120000Z').credentialDraftId, '');
});

test('C02_FamilyModels_enforceGuestAndInviteInvariants', () => {
  const family = new Family('f-1', 'Home', 'm-1', '20261017T120000Z', '20261017T120000Z',
    ['gw_01']);
  assert.equal(family.gatewayIds.length, 1);

  const admin = new FamilyMember('m-1', 'f-1', 'u-1', 'Admin', MemberRole.ADMIN,
    MemberStatus.ACTIVE, '20261017T120000Z', []);
  assert.equal(admin.expiresAt, undefined);
  expectCode(() => new FamilyMember('m-2', 'f-1', 'u-2', 'Guest', MemberRole.GUEST,
    MemberStatus.ACTIVE, '20261017T120000Z', [UUID_A]), 'CONFIGURATION_ERROR');
  const guest = new FamilyMember('m-2', 'f-1', 'u-2', 'Guest', MemberRole.GUEST,
    MemberStatus.ACTIVE, '20261017T120000Z', [UUID_A], '20271017T120000Z');
  assert.equal(guest.allowedRoomIds[0], UUID_A);

  const invite = new InvitationRecord('i-1', 'f-1', 'Home', 'm-1', MemberRole.GUEST, [UUID_A],
    InviteMode.CODE_KEK, InvitationStatus.PENDING, '20271017T120000Z', 3, 0, 'YCI1xxx',
    StorageConstants.inviteSeedAlias('i-1'));
  assert.equal(invite.maxUses, 3);
  expectCode(() => new InvitationRecord('i-2', 'f-1', 'Home', 'm-1', MemberRole.MEMBER, [],
    InviteMode.KEY_WRAP, InvitationStatus.PENDING, '20271017T120000Z', 2, 0, 'YCI1xxx',
    StorageConstants.inviteSeedAlias('i-2'), undefined, undefined, 'm-9'),
    'CONFIGURATION_ERROR');
  expectCode(() => new InvitationRecord('i-3', 'f-1', 'Home', 'm-1', MemberRole.MEMBER, [],
    InviteMode.CODE_KEK, InvitationStatus.PENDING, '20271017T120000Z', 1, 2, 'YCI1xxx',
    StorageConstants.inviteSeedAlias('i-3')), 'PROTOCOL_VALUE_OUT_OF_RANGE');
});

test('C02_RoomSceneCloudConfig_shapesAreUsable', () => {
  const room = new Room(UUID_A, 'f-1', '客厅', 0, '20261017T120000Z', '20261017T120000Z');
  assert.equal(room.roomId, UUID_A);
  expectCode(() => new Room('room-1', 'f-1', '客厅', 0, '20261017T120000Z',
    '20261017T120000Z'), 'PROTOCOL_INVALID_IDENTIFIER');

  const action = new SceneAction('gw_01', 'Light_01', DeviceAction.SET_BRIGHTNESS, 60, 100);
  const scene = new Scene(UUID_B, 'f-1', '回家', 'home', [action], true);
  assert.equal(scene.actions.length, 1);
  assert.equal(scene.actions[0].targetDeviceId, 'Light_01');

  const cloud = new CloudConfig('https://iotda.example.com', 'project-1', 'device-1',
    StorageConstants.ASSET_CLOUD_TOKEN);
  assert.equal(cloud.accessTokenAlias, 'yaocore.cloud.token.v2');
  expectCode(() => new CloudConfig('http://iotda.example.com', 'project-1', 'device-1',
    StorageConstants.ASSET_CLOUD_TOKEN), 'CLOUD_ENDPOINT_INVALID');
  expectCode(() => new CloudConfig('https://iotda.example.com/path', 'project-1', 'device-1',
    StorageConstants.ASSET_CLOUD_TOKEN), 'CLOUD_ENDPOINT_INVALID');
  expectCode(() => new CloudConfig('https://iotda.example.com', 'project-1', 'device-1',
    'literal-token'), 'CONFIGURATION_ERROR');

  assert.equal(DeviceConstants.actionToStateField(DeviceAction.TURN_ON), 'power');
  assert.equal(DeviceConstants.actionToStateField(DeviceAction.SET_TARGET_TEMPERATURE), 'targetTemp');
  assert.equal(DeviceConstants.actionToStateField(DeviceAction.SET_POSITION), undefined);
  assert.equal(DeviceConstants.actionToValueKind(DeviceAction.SET_COLOR), 'STRING_COLOR');
  assert.equal(DeviceConstants.isAcMode(AcMode.COOL), true);
  assert.equal(DeviceConstants.isStateSource(StateSource.APP_LAN), true);
  assert.equal(DeviceConstants.isSupported(DeviceType.SWITCH), false);
});
