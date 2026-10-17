/*
 * YaoCore T-15/T-16 ViewModel host fixtures.
 * Producer: agent:implementation-engineer | Task: T-15/T-16 / wp-060-vm
 *
 * PUBLIC TEST DATA ONLY. No real device, credential, or network access.
 */
import { DeviceSnapshot, DeviceSnapshotInit, DeviceState } from '../../main/ets/model/DeviceState.ets';
import { DeviceKey } from '../../main/ets/model/DeviceKey.ets';
import {
  DeviceMergeResult,
  DeviceMergeState,
  DeviceRecord
} from '../../main/ets/repository/DomainModels.ets';

export const GATEWAY_ID = 'gw-1';
export const FAMILY_ID = 'family-1';
export const ROOM_A = '11111111-1111-4111-8111-111111111111';
export const ROOM_B = '22222222-2222-4222-8222-222222222222';
export const T0 = 1760691600000; // 2026-10-17T09:00:00Z
export const UPDATED = '20261017T090000Z';

export class FakeClock {
  constructor(now = T0) {
    this.now = now;
  }

  nowMs() {
    return this.now;
  }

  advance(ms) {
    this.now += ms;
    return this.now;
  }
}

export class FakeTimer {
  constructor(clock) {
    this.clock = clock;
    this.nextId = 1;
    this.entries = [];
  }

  setTimer(delayMs, callback) {
    const id = this.nextId++;
    this.entries.push({ id, at: this.clock.nowMs() + delayMs, callback });
    return id;
  }

  clearTimer(id) {
    this.entries = this.entries.filter((entry) => entry.id !== id);
  }

  pending() {
    return this.entries.length;
  }

  advance(ms) {
    this.clock.advance(ms);
    let progressed = true;
    while (progressed) {
      progressed = false;
      const due = this.entries
        .filter((entry) => entry.at <= this.clock.nowMs())
        .sort((left, right) => left.at - right.at);
      if (due.length > 0) {
        const entry = due[0];
        this.clearTimer(entry.id);
        entry.callback();
        progressed = true;
      }
    }
  }
}

export class FakeLogger {
  constructor() {
    this.entries = [];
  }

  debug(tag, message, fields) { this.entries.push({ level: 'debug', tag, message, fields }); }
  info(tag, message, fields) { this.entries.push({ level: 'info', tag, message, fields }); }
  warn(tag, message, fields) { this.entries.push({ level: 'warn', tag, message, fields }); }
  error(tag, message, fields) { this.entries.push({ level: 'error', tag, message, fields }); }
}

export class FakeI18n {
  t(key) {
    return 't:' + key;
  }
}

export class FakeAppContext {
  constructor() {
    this.refreshCount = 0;
    this.lockCount = 0;
  }

  refreshSessionGate() { this.refreshCount++; }
  lock() { this.lockCount++; }
}

export function snapshot(options = {}) {
  const init = new DeviceSnapshotInit();
  init.deviceId = options.deviceId === undefined ? 'dev-1' : options.deviceId;
  init.deviceName = options.deviceName === undefined ? 'Lamp' : options.deviceName;
  init.roomNameHint = '';
  init.deviceTypeRaw = options.deviceType === undefined ? 'light' : options.deviceType;
  init.deviceType = options.deviceType === undefined ? 'light' : options.deviceType;
  init.isSupported = options.isSupported === undefined ? true : options.isSupported;
  init.brand = options.brand;
  init.isOnline = options.isOnline === undefined ? true : options.isOnline;
  init.powerStatus = options.powerStatus;
  init.openStatus = options.openStatus;
  init.brightness = options.brightness;
  init.color = options.color;
  init.temperature = options.temperature;
  init.humidity = options.humidity;
  init.presence = options.presence;
  init.targetTemperature = options.targetTemperature;
  init.mode = options.mode;
  init.modeStandard = options.modeStandard === undefined ? false : options.modeStandard;
  init.stateSource = options.stateSource;
  init.stateSourceKnown = options.stateSourceKnown === undefined ? false : options.stateSourceKnown;
  init.triggerDeviceId = options.triggerDeviceId;
  init.automationId = options.automationId;
  init.lastRequestId = options.lastRequestId;
  init.lastSeq = options.lastSeq;
  init.updatedAt = options.updatedAt === undefined ? UPDATED : options.updatedAt;
  return DeviceSnapshot.create(init);
}

export function record(options = {}) {
  const state = new DeviceState(
    new DeviceKey(options.gatewayId === undefined ? GATEWAY_ID : options.gatewayId,
      options.deviceId === undefined ? 'dev-1' : options.deviceId),
    options.familyId === undefined ? FAMILY_ID : options.familyId,
    snapshot(options),
    options.deviceName === undefined ? 'Lamp' : options.deviceName,
    options.roomId === undefined ? ROOM_A : options.roomId,
    options.isEnabled === undefined ? true : options.isEnabled,
    options.isUnassigned === undefined ? false : options.isUnassigned,
    options.isDismissed === undefined ? false : options.isDismissed);
  return new DeviceRecord(state,
    new DeviceMergeState(options.atMs === undefined ? T0 : options.atMs,
      state.snapshot.stateEpochMs, DeviceMergeResult.UPDATED),
    options.gatewayRemoved === undefined ? false : options.gatewayRemoved,
    options.hasPartialState === undefined ? false : options.hasPartialState);
}

export function commandFor(key, action, value) {
  return {
    gatewayId: key.gatewayId,
    target: key.deviceId,
    action,
    value,
    requestedAtMs: T0
  };
}

export function executionOf(recordValue, action, options = {}) {
  const success = options.success === undefined ? true : options.success;
  const error = options.error;
  const command = commandFor(recordValue.state.key, action, options.value);
  if (!success) {
    return {
      command,
      transport: 'LAN',
      elapsedMs: 5,
      ackAccepted: options.ackAccepted === undefined ? false : options.ackAccepted,
      stateVerification: options.verification === undefined ? 'UNVERIFIED' : options.verification,
      apply: undefined,
      lan: options.lan,
      cloud: options.cloud,
      error
    };
  }
  const apply = {
    ackAccepted: true,
    stateApplied: true,
    stateVerification: options.verification === undefined ? 'MATCH' : options.verification,
    reason: 'APPLIED',
    record: recordValue
  };
  return {
    command,
    transport: 'LAN',
    elapsedMs: 5,
    ackAccepted: true,
    stateVerification: apply.stateVerification,
    apply,
    lan: options.lan,
    cloud: options.cloud,
    error
  };
}

export class FakeControlCoordinator {
  constructor() {
    this.calls = [];
    this.next = [];
  }

  push(execution) {
    this.next.push(execution);
  }

  async execute(command, familyId) {
    this.calls.push({ command, familyId });
    if (this.next.length === 0) {
      throw new Error('no queued execution');
    }
    return this.next.shift();
  }
}

export class FakeFamilies {
  constructor(families = []) {
    this.families = families;
    this.active = families.length > 0 ? families[0] : undefined;
    this.switchCalls = [];
    this.switchResult = undefined;
  }

  async listFamilies() { return this.families; }
  async getActiveFamily() { return this.active; }

  async switchFamily(familyId) {
    this.switchCalls.push(familyId);
    const family = this.families.find((item) => item.familyId === familyId);
    this.active = family;
    if (this.switchResult !== undefined) {
      return this.switchResult;
    }
    return {
      family,
      requiresUnlock: true,
      activeProfileId: 'profile-1'
    };
  }
}

export class FakeRoutes {
  constructor(routes = []) {
    this.routes = routes;
  }

  async listRoutes() { return this.routes; }

  async listRoutesByFamily(familyId) {
    return this.routes.filter((route) => route.familyId === familyId);
  }

  async getRoute(gatewayId) {
    return this.routes.find((route) => route.gatewayId === gatewayId);
  }

  async isBound(gatewayId) {
    return this.routes.some((route) => route.gatewayId === gatewayId);
  }

  add(route) { this.routes.push(route); }
}

export function route(options = {}) {
  return {
    gatewayId: options.gatewayId === undefined ? GATEWAY_ID : options.gatewayId,
    familyId: options.familyId === undefined ? FAMILY_ID : options.familyId,
    gatewayName: options.gatewayName === undefined ? 'Gateway' : options.gatewayName,
    localIp: options.localIp === undefined ? '192.168.1.10' : options.localIp,
    port: options.port === undefined ? 8443 : options.port,
    profile: options.profile === undefined ? 'P-HMAC' : options.profile,
    tlsEnabled: options.tlsEnabled === undefined ? false : options.tlsEnabled,
    pins: options.pins === undefined ? [] : options.pins,
    pinAlg: options.pinAlg === undefined ? '' : options.pinAlg,
    keyId: 'v1',
    credentialAlias: 'yaocore.gateway.hmac.' +
      (options.gatewayId === undefined ? GATEWAY_ID : options.gatewayId),
    lastKnownIp: options.lastKnownIp === undefined ? '' : options.lastKnownIp,
    lastSeenAt: options.lastSeenAt,
    createdAt: '20261001T000000Z',
    updatedAt: '20261001T000000Z'
  };
}

export class FakeRoomQuery {
  constructor(rooms = []) { this.rooms = rooms; }
  async listRooms(familyId) { return this.rooms.filter((room) => room.familyId === familyId); }
}

export class FakeDeviceQuery {
  constructor(records = []) {
    this.records = records;
    this.applied = [];
  }

  async getRecord(key) {
    return this.records.find((item) => item.state.key.globalId() === key.globalId());
  }

  async listRecords(familyId) {
    return this.records.filter((item) => item.state.familyId === familyId);
  }

  async listRecordsByRoom(familyId, roomId) {
    return this.records.filter((item) => item.state.familyId === familyId &&
      item.state.roomId === roomId);
  }

  async listUnassigned(familyId) {
    return this.records.filter((item) => item.state.familyId === familyId &&
      item.state.isUnassigned);
  }

  async applyDiscoverSnapshot(snapshotValue, options) {
    this.applied.push({ snapshot: snapshotValue, options });
    return {
      added: 0, updated: 0, unchanged: snapshotValue.devices.length, staleDropped: 0,
      tombstonedSkipped: 0, invalidDropped: 0, gatewayRemovedMarked: 0,
      partial: snapshotValue.isPartial, deviations: [], affectedKeys: []
    };
  }
}

export function waitMicrotasks() {
  return new Promise((resolve) => setImmediate(resolve));
}
