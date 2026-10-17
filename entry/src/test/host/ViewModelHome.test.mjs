/*
 * YaoCore T-15 HomeViewModel host tests.
 * Producer: agent:implementation-engineer | Task: T-15 / wp-060-vm
 * Contract: DES-B §10.1.2; FR-HOME-001..004; D-019.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { HomeViewModel } from '../../main/ets/viewmodel/HomeViewModel.ets';
import { DeviceFilter } from '../../main/ets/viewmodel/core/ViewModelCore.ets';
import { Family } from '../../main/ets/model/FamilyModels.ets';
import { Room } from '../../main/ets/model/FamilyModels.ets';
import { DiscoverySnapshot, DiscoverySnapshotInit } from '../../main/ets/model/DiscoveryModels.ets';
import { AppErrors } from '../../main/ets/common/types/AppError.ets';
import {
  FakeAppContext,
  FakeClock,
  FakeDeviceQuery,
  FakeFamilies,
  FakeI18n,
  FakeLogger,
  FakeRoomQuery,
  FakeRoutes,
  FakeTimer,
  FAMILY_ID,
  GATEWAY_ID,
  ROOM_A,
  ROOM_B,
  T0,
  record,
  route,
  snapshot
} from './viewmodel-helpers.mjs';

const FAMILY = new Family(FAMILY_ID, 'Home', 'member-1', '20261001T000000Z',
  '20261001T000000Z', [GATEWAY_ID]);
const OTHER = new Family('family-2', 'Office', 'member-2', '20261001T000000Z',
  '20261001T000000Z', []);
const ROOM = new Room(ROOM_A, FAMILY_ID, 'Living', 0, '20261001T000000Z',
  '20261001T000000Z');

function discovery(devices) {
  const init = new DiscoverySnapshotInit();
  init.gatewayId = GATEWAY_ID;
  init.gatewayName = 'Gateway';
  init.generatedAt = '20261017T090000Z';
  init.devices = devices;
  return DiscoverySnapshot.create(init);
}

class FakeClient {
  constructor(options = {}) {
    this.failure = options.failure;
    this.snapshot = options.snapshot;
    this.calls = [];
  }
  async discover(target) {
    this.calls.push(target);
    if (this.failure !== undefined) {
      throw this.failure;
    }
    return this.snapshot;
  }
}

class FakeCloudState {
  constructor(state) { this.state = state; }
  async getState() { return { state: this.state, config: undefined, tokenPresent: true }; }
}

function setup(options = {}) {
  const clock = new FakeClock();
  const timer = new FakeTimer(clock);
  const lamp = record({ deviceId: 'dev-1', roomId: ROOM_A });
  const pool = record({ deviceId: 'dev-2', roomId: '', isUnassigned: true, isEnabled: false });
  const sensor = record({
    deviceId: 'sensor-1',
    deviceType: 'sensor',
    roomId: ROOM_A,
    temperature: 23.5,
    humidity: 41,
    presence: true,
    stateSource: 'sensor.physical',
    stateSourceKnown: true,
    updatedAt: '20261017T090001Z'
  });
  const devices = new FakeDeviceQuery(options.records === undefined ?
    [lamp, pool, sensor] : options.records);
  const families = new FakeFamilies([FAMILY, OTHER]);
  const rooms = new FakeRoomQuery([ROOM]);
  const routes = new FakeRoutes(options.routes === undefined ? [route()] : options.routes);
  const client = new FakeClient(options.client === undefined ?
    { snapshot: discovery([lamp.state.snapshot, pool.state.snapshot]) } : options.client);
  const appContext = new FakeAppContext();
  const vm = new HomeViewModel(families, rooms, devices, routes, client, {},
    new FakeCloudState(options.cloud === undefined ? 'CONFIGURED' : options.cloud),
    appContext, new FakeI18n(), clock, timer, new FakeLogger());
  return { clock, timer, lamp, pool, sensor, devices, families, rooms, routes, client,
    appContext, vm };
}

test('T15_Home_initializeLoadsFamilyRoomsRecordsAndGatewayStatus', async () => {
  const h = setup();
  await h.vm.initialize();
  const state = h.vm.getState();
  assert.equal(state.phase, 'READY');
  assert.equal(state.families.length, 2);
  assert.equal(state.activeFamily.familyId, FAMILY_ID);
  assert.equal(state.rooms.length, 1);
  assert.equal(state.records.length, 3);
  assert.equal(state.unassignedCount, 1);
  assert.equal(state.gatewayStatuses[0].lan, 'ONLINE');
  assert.equal(state.gatewayStatuses[0].cloud, 'CONFIGURED');
  assert.ok(state.gatewayStatuses[0].latencyMs >= 0);
  assert.equal(h.client.calls.length, 1);
  assert.equal(h.client.calls[0].profile, 'P-HMAC');
  assert.equal(h.devices.applied.length, 1);
});

test('T15_Home_environmentAggregatesLatestSensorValuesOnly', async () => {
  const h = setup();
  await h.vm.initialize();
  const environment = h.vm.getState().environment;
  assert.equal(environment.known, true);
  assert.equal(environment.temperature, 23.5);
  assert.equal(environment.humidity, 41);
  assert.equal(environment.presence, true);
  assert.equal(environment.stateSource, 'sensor.physical');
});

test('T15_Home_roomFilterAndUnassignedPoolSelectors', async () => {
  const h = setup();
  await h.vm.initialize();
  h.vm.setRoomFilter(DeviceFilter.room(ROOM_A));
  assert.equal(h.vm.getState().records.length, 2);
  h.vm.setRoomFilter(DeviceFilter.unassigned());
  assert.equal(h.vm.getState().records.length, 1);
  assert.equal(h.vm.getState().records[0].state.isUnassigned, true);
  h.vm.setRoomFilter(DeviceFilter.room(ROOM_B));
  assert.equal(h.vm.getState().records.length, 0);
});

test('T15_Home_selectFamilyRequiresUnlockAndRefreshes', async () => {
  const h = setup();
  await h.vm.initialize();
  await h.vm.selectFamily('family-2');
  assert.equal(h.vm.getState().activeFamily.familyId, 'family-2');
  assert.equal(h.vm.getState().needsUnlock, true);
  assert.equal(h.appContext.refreshCount, 1);
  assert.deepEqual(h.families.switchCalls, ['family-2']);
  // family-2 has no routes; refresh must not invent gateways or records.
  assert.equal(h.vm.getState().records.length, 0);
});

test('T15_Home_gatewayFailurePreservesRecordsAndReportsOffline', async () => {
  const h = setup({
    client: { failure: AppErrors.of('GATEWAY_TIMEOUT', []) }
  });
  await h.vm.initialize();
  const state = h.vm.getState();
  assert.equal(state.phase, 'READY');
  assert.equal(state.records.length, 3);
  assert.equal(state.gatewayStatuses[0].lan, 'OFFLINE');
  assert.equal(h.devices.applied.length, 0);
});

test('T15_Home_tlsFailureReportsBlocked', async () => {
  const h = setup({
    client: { failure: AppErrors.of('TLS_PIN_MISMATCH', []) }
  });
  await h.vm.initialize();
  assert.equal(h.vm.getState().gatewayStatuses[0].lan, 'BLOCKED');
  assert.equal(h.vm.getState().gatewayStatuses[0].warningKey,
    'gateway.security.unavailable');
});

test('T15_Home_cloudTokenStateMapping', async () => {
  const h = setup({ cloud: 'TOKEN_EXPIRED' });
  await h.vm.initialize();
  assert.equal(h.vm.getState().gatewayStatuses[0].cloud, 'TOKEN_EXPIRED');
});
