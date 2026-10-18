/*
 * YaoCore T-16 BleProvisioningViewModel host tests.
 * Producer: agent:implementation-engineer | Task: T-16 / wp-060-vm
 * Contract: DES-B §12.1.1, §12.3.1; R-1 credentialDraftId; SC-06.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { BleProvisioningViewModel } from '../../main/ets/viewmodel/BleProvisioningViewModel.ets';
import { ProvisioningPermissionKind } from '../../main/ets/contracts/PermissionPort.ets';
import { AppErrors } from '../../main/ets/common/types/AppError.ets';
import {
  FakeClock,
  FakeI18n,
  FakeLogger,
  FakeTimer,
  GATEWAY_ID,
  waitMicrotasks
} from './viewmodel-helpers.mjs';

const RESULT = {
  identity: { gatewayId: GATEWAY_ID, gatewayName: 'Gateway' },
  ip: '192.168.1.10',
  port: 8443,
  boardLedConfirmed: true,
  credentialDraftId: 'draft-result',
  completedAt: '20261017T090000Z'
};

class FakeBle {
  constructor(options = {}) {
    this.scanListener = undefined;
    this.request = undefined;
    this.listener = undefined;
    this.provisionCalls = 0;
    this.cancelCalls = 0;
    this.pendingReject = undefined;
    this.result = options.result === undefined ? RESULT : options.result;
  }

  async startScan(filter, listener) {
    this.filter = filter;
    this.scanListener = listener;
  }

  async stopScan() { this.stopCalls = (this.stopCalls || 0) + 1; }

  async provision(request, listener) {
    this.provisionCalls++;
    this.request = request;
    this.listener = listener;
    listener.onStateChanged({ state: 'SECURITY_HANDSHAKE' });
    listener.onStateChanged({ state: 'AP_SCANNING', apList: [
      { ssid: 'HomeWifi', bssid: 'aa', channel: 1, rssi: -40, auth: 3 }
    ] });
    listener.onStateChanged({ state: 'SENDING_CREDENTIALS' });
    listener.onStateChanged({ state: 'WAITING_FOR_WIFI' });
    listener.onStateChanged({ state: 'DISCOVERING_ON_LAN' });
    if (this.result instanceof Error) {
      throw this.result;
    }
    listener.onCompleted(this.result);
    return this.result;
  }

  async cancel() {
    this.cancelCalls++;
    if (this.pendingReject !== undefined) {
      const reject = this.pendingReject;
      this.pendingReject = undefined;
      reject(AppErrors.of('PROVISIONING_CANCELLED', []));
    }
  }
}

class HangingBle extends FakeBle {
  async provision(request, listener) {
    this.provisionCalls++;
    this.request = request;
    this.listener = listener;
    return new Promise((resolve, reject) => {
      this.pendingReject = reject;
    });
  }
}

class HangingWifiBle extends FakeBle {
  async scanWifiAccessPoints(request, listener) {
    this.wifiRequest = request;
    this.wifiListener = listener;
    return new Promise((resolve, reject) => {
      this.pendingWifiReject = reject;
    });
  }

  async cancel() {
    this.cancelCalls++;
    if (this.pendingWifiReject !== undefined) {
      const reject = this.pendingWifiReject;
      this.pendingWifiReject = undefined;
      reject(AppErrors.of('PROVISIONING_CANCELLED', []));
    }
  }
}

/**
 * R3-02: simulates a BLE implementation whose cancel() does not reject the
 * pending provision/AP scan. Its late success must still be dropped by the VM
 * cancellation generation.
 */
class DeferredBle extends FakeBle {
  async provision(request, listener) {
    this.provisionCalls++;
    this.request = request;
    this.listener = listener;
    return new Promise((resolve) => {
      this.pendingResolve = resolve;
    });
  }

  async cancel() { this.cancelCalls++; }
}

class DeferredWifiBle extends FakeBle {
  async scanWifiAccessPoints(request, listener) {
    this.wifiRequest = request;
    this.wifiListener = listener;
    return new Promise((resolve) => {
      this.pendingWifiResolve = resolve;
    });
  }

  async cancel() { this.cancelCalls++; }
}

class FakePermissions {
  constructor(options = {}) {
    this.failure = options.failure;
    this.calls = [];
  }

  async ensure(kind) {
    this.calls.push(kind);
    if (this.failure !== undefined) {
      throw this.failure;
    }
  }
}

class FakeDrafts {
  constructor() {
    this.next = 1;
    this.values = new Map();
    this.destroyed = [];
    this.clearAllCalls = 0;
  }

  put() {
    const id = 'draft-' + this.next++;
    this.values.set(id, true);
    return id;
  }

  take(id) {
    const value = this.values.get(id);
    if (value === undefined) {
      throw AppErrors.of('PROVISIONING_CREDENTIAL_MISSING', []);
    }
    this.values.delete(id);
    return { id };
  }

  destroy(id) {
    this.destroyed.push(id);
    this.values.delete(id);
  }

  clearAll() { this.clearAllCalls++; this.values.clear(); }
  size() { return this.values.size; }
}

class FakeCrypto {
  constructor() { this.calls = 0; }
  async randomBytes(length) {
    this.calls++;
    return new Uint8Array(length).fill(7);
  }
}

class FakeBindings {
  constructor(options = {}) {
    this.failure = options.failure;
    this.calls = [];
  }
  async commitBinding(result, draftId, familyId) {
    this.calls.push({ result, draftId, familyId });
    if (this.failure !== undefined) {
      throw this.failure;
    }
    return { gatewayId: result.identity.gatewayId };
  }
}

class FakeFamilyGateways {
  constructor(options = {}) {
    this.failure = options.failure;
    this.calls = [];
  }
  async addGatewayToFamily(familyId, gatewayId) {
    this.calls.push({ familyId, gatewayId });
    if (this.failure !== undefined) {
      throw this.failure;
    }
  }
}

/** R3-02: holds commitBinding open so cancel can race the commit await. */
class DeferredBindings {
  constructor() {
    this.calls = [];
    this.pendingResolve = undefined;
  }
  async commitBinding(result, draftId, familyId) {
    this.calls.push({ result, draftId, familyId });
    return new Promise((resolve) => {
      this.pendingResolve = resolve;
    });
  }
}

function setup(options = {}) {
  const clock = new FakeClock();
  const timer = new FakeTimer(clock);
  const ble = options.deferredWifi ? new DeferredWifiBle(options) :
    options.deferred ? new DeferredBle(options) :
    options.hangingWifi ? new HangingWifiBle(options) :
    options.hanging ? new HangingBle(options) : new FakeBle(options);
  const drafts = new FakeDrafts();
  const crypto = new FakeCrypto();
  const permissions = new FakePermissions(options.permission);
  const bindings = options.deferredBinding ? new DeferredBindings() :
    new FakeBindings(options.binding);
  const families = new FakeFamilyGateways(options.family);
  const vm = new BleProvisioningViewModel(ble, bindings, families, drafts, crypto, permissions,
    new FakeI18n(), clock, timer, new FakeLogger());
  return { clock, timer, ble, drafts, crypto, permissions, bindings, families, vm };
}

async function readyDevice(h) {
  await h.vm.initialize('family-1');
  await h.vm.requestPermission();
  await h.vm.startScan();
  h.ble.scanListener.onDeviceFound({ deviceId: 'dev-ble', name: 'YaoCore-GW-1', rssi: -50,
    serviceUuids: [] });
  const device = h.vm.getState().scanResults[0];
  h.vm.selectDevice(device);
  return device;
}

test('T16_Ble_initializeStartsAtPermissionStep', async () => {
  const h = setup();
  await h.vm.initialize('family-1');
  const state = h.vm.getState();
  assert.equal(state.step, 0);
  assert.equal(state.permission, 'UNKNOWN');
  assert.equal(state.provisioning, 'IDLE');
  assert.equal(state.canCancel, false);
});

test('T16_Ble_permissionDeniedAndBluetoothOffAreDistinct', async () => {
  const denied = setup({ permission: { failure: AppErrors.of('PROVISIONING_PERMISSION_DENIED',
    []) } });
  await denied.vm.initialize('family-1');
  await denied.vm.requestPermission();
  assert.equal(denied.vm.getState().permission, 'DENIED');
  assert.equal(denied.vm.getState().error.error.code, 'PROVISIONING_PERMISSION_DENIED');

  const off = setup({ permission: { failure: AppErrors.of('PROVISIONING_BLUETOOTH_OFF', []) } });
  await off.vm.initialize('family-1');
  await off.vm.requestPermission();
  assert.equal(off.vm.getState().permission, 'BLUETOOTH_OFF');
  assert.equal(off.vm.getState().error.error.code, 'PROVISIONING_BLUETOOTH_OFF');
});

test('T16_Ble_scanDeduplicatesAndSelectMovesToHandshake', async () => {
  const h = setup();
  const device = await readyDevice(h);
  assert.equal(h.vm.getState().step, 2);
  assert.equal(h.vm.getState().scanResults.length, 1);
  assert.equal(device.deviceId, 'dev-ble');
  h.ble.scanListener.onDeviceFound({ deviceId: 'dev-ble', name: 'YaoCore-GW-1', rssi: -40,
    serviceUuids: [] });
  assert.equal(h.vm.getState().scanResults.length, 1);
});

test('T16_Ble_submitMapsStatesAndCommitsWithReissuedResultDraft', async () => {
  const h = setup();
  await readyDevice(h);
  await h.vm.submit('12345678', 'HomeWifi', 'wifi-password');
  const state = h.vm.getState();
  assert.equal(h.ble.provisionCalls, 1);
  assert.equal(state.step, 5);
  assert.equal(state.provisioning, 'BOUND');
  assert.equal(state.draftReady, false);
  assert.equal(state.canCancel, false);
  assert.equal(state.result.identity.gatewayId, GATEWAY_ID);
  assert.equal(h.bindings.calls.length, 1);
  assert.equal(h.bindings.calls[0].draftId, 'draft-result');
  assert.notEqual(h.bindings.calls[0].draftId, h.ble.request.credentialDraftId);
  assert.equal(h.bindings.calls[0].familyId, 'family-1');
  assert.equal(h.families.calls[0].gatewayId, GATEWAY_ID);
});

test('T16_Ble_shortCommandSecretIsRejectedBeforeNetwork', async () => {
  const h = setup();
  await readyDevice(h);
  await h.vm.submit('12345678', 'HomeWifi', 'wifi-password', '00112233');
  assert.equal(h.ble.provisionCalls, 0);
  assert.equal(h.vm.getState().error.error.code, 'PROVISIONING_CREDENTIAL_MISSING');
});

test('T16_Ble_commitFailureNeverReportsBoundAndDestroysResultDraft', async () => {
  const h = setup({ binding: { failure: AppErrors.of('CONFIGURATION_ERROR', []) } });
  await readyDevice(h);
  await h.vm.submit('12345678', 'HomeWifi', 'wifi-password');
  const state = h.vm.getState();
  assert.notEqual(state.provisioning, 'BOUND');
  assert.equal(state.result, undefined);
  assert.equal(state.error.error.code, 'CONFIGURATION_ERROR');
  assert.equal(h.drafts.destroyed.indexOf('draft-result') >= 0, true);
  assert.equal(h.families.calls.length, 0);
});

test('T16_Ble_addGatewayFailureIsPartialSuccessNotBound', async () => {
  const h = setup({ family: { failure: AppErrors.of('STORAGE_RDB_ERROR', []) } });
  await readyDevice(h);
  await h.vm.submit('12345678', 'HomeWifi', 'wifi-password');
  const state = h.vm.getState();
  assert.notEqual(state.step, 5);
  assert.equal(state.error.error.code, 'STORAGE_RDB_ERROR');
  assert.equal(h.bindings.calls.length, 1);
});

test('T16_Ble_cancelCallsBleCancelsAndDestroysSessionDraft', async () => {
  const h = setup({ hanging: true });
  await readyDevice(h);
  const submitting = h.vm.submit('12345678', 'HomeWifi', 'wifi-password');
  await waitMicrotasks();
  assert.equal(h.ble.provisionCalls, 1);
  const draftId = h.ble.request.credentialDraftId;
  await h.vm.cancel();
  await submitting;
  const state = h.vm.getState();
  assert.equal(h.ble.cancelCalls >= 1, true);
  assert.equal(h.drafts.destroyed.indexOf(draftId) >= 0, true);
  assert.equal(state.provisioning, 'CANCELLED');
  assert.equal(state.result, undefined);
});

test('T18_R2_cancelDuringPrepareWifiCancelsBleAndClearsTimer', async () => {
  const h = setup({ hangingWifi: true });
  await readyDevice(h);
  const preparing = h.vm.prepareWifi('12345678');
  await waitMicrotasks();
  assert.equal(h.vm.getState().step, 2);
  assert.equal(h.vm.getState().provisioning, 'CONNECTING');
  assert.equal(h.vm.getState().canCancel, true,
    'R2-02: the wizard stays cancellable while the AP scan is in flight');
  await h.vm.cancel();
  await preparing;
  const state = h.vm.getState();
  assert.equal(h.ble.cancelCalls >= 1, true);
  assert.equal(state.provisioning, 'CANCELLED');
  assert.equal(state.canCancel, false);
  assert.equal(h.timer.pending(), 0);
});

test('T18_R3_cancelDuringPrepareWifiDropsLateAccessPoints', async () => {
  const h = setup({ deferredWifi: true });
  await readyDevice(h);
  const preparing = h.vm.prepareWifi('12345678');
  await waitMicrotasks();
  assert.equal(h.vm.getState().provisioning, 'CONNECTING');

  await h.vm.cancel();
  const cancelled = h.vm.getState();
  assert.equal(cancelled.provisioning, 'CANCELLED');
  const revisionAtCancel = cancelled.revision;

  // The pending handshake still emits events and resolves with a real AP list.
  // None of that may republish over the cancelled snapshot.
  h.ble.wifiListener.onAccessPoints([
    { ssid: 'LateWifi', bssid: 'bb', channel: 6, rssi: -50, auth: 3 }
  ]);
  h.ble.wifiListener.onStateChanged({ state: 'AP_SCANNING' });
  h.ble.pendingWifiResolve([
    { ssid: 'LateWifi', bssid: 'bb', channel: 6, rssi: -50, auth: 3 }
  ]);
  await preparing;

  const state = h.vm.getState();
  assert.equal(state.provisioning, 'CANCELLED');
  assert.equal(state.step, 2);
  assert.equal(state.accessPoints.length, 0);
  assert.equal(state.revision, revisionAtCancel,
    'R3-02: a late AP list must not publish after cancel');
  assert.equal(h.timer.pending(), 0);
});

test('T18_R3_cancelDuringSubmitDropsLateBindingSuccess', async () => {
  const h = setup({ deferred: true });
  await readyDevice(h);
  const published = [];
  h.vm.subscribe((state) => published.push(state.provisioning));
  const submitting = h.vm.submit('12345678', 'HomeWifi', 'wifi-password');
  await waitMicrotasks();
  assert.equal(h.ble.provisionCalls, 1);

  await h.vm.cancel();
  const revisionAtCancel = h.vm.getState().revision;

  // A provision that ignores the cancel and reports success late must not
  // reach commitBinding/addGatewayToFamily or re-enter BOUND.
  h.ble.listener.onStateChanged({ state: 'BOUND' });
  h.ble.listener.onCompleted(RESULT);
  h.ble.pendingResolve(RESULT);
  await submitting;

  const state = h.vm.getState();
  assert.equal(state.provisioning, 'CANCELLED');
  assert.equal(state.step, 2);
  assert.equal(state.result, undefined);
  assert.equal(state.revision, revisionAtCancel,
    'R3-02: late progress/completion must not publish after cancel');
  assert.equal(h.bindings.calls.length, 0,
    'R3-02: cancelled submit must not call commitBinding');
  assert.equal(h.families.calls.length, 0,
    'R3-02: cancelled submit must not call addGatewayToFamily');
  assert.equal(published.indexOf('BOUND'), -1);
  assert.equal(h.drafts.destroyed.indexOf('draft-result') >= 0, true,
    'the late re-issued result draft must be zeroized');
});

test('T18_R3_cancelDuringCommitBindingSkipsFamilyAddAndBound', async () => {
  const h = setup({ deferredBinding: true });
  await readyDevice(h);
  const submitting = h.vm.submit('12345678', 'HomeWifi', 'wifi-password');
  await waitMicrotasks();
  assert.equal(h.bindings.calls.length, 1);
  assert.equal(h.bindings.calls[0].draftId, 'draft-result');

  await h.vm.cancel();
  const revisionAtCancel = h.vm.getState().revision;
  h.bindings.pendingResolve({ gatewayId: GATEWAY_ID });
  await submitting;

  const state = h.vm.getState();
  assert.equal(state.provisioning, 'CANCELLED');
  assert.equal(state.result, undefined);
  assert.equal(state.revision, revisionAtCancel);
  assert.equal(h.families.calls.length, 0,
    'cancel while commitBinding is in flight skips addGatewayToFamily');
});

test('T18_R3_repeatedCancelIsIdempotentAndDropsLateSuccess', async () => {
  const h = setup({ deferred: true });
  await readyDevice(h);
  const submitting = h.vm.submit('12345678', 'HomeWifi', 'wifi-password');
  await waitMicrotasks();

  await Promise.all([h.vm.cancel(), h.vm.cancel()]);
  const cancelled = h.vm.getState();
  assert.equal(cancelled.provisioning, 'CANCELLED');
  assert.equal(cancelled.canCancel, false);
  assert.equal(cancelled.result, undefined);

  h.ble.pendingResolve(RESULT);
  await submitting;
  const state = h.vm.getState();
  assert.equal(state.provisioning, 'CANCELLED');
  assert.equal(state.result, undefined);
  assert.equal(h.bindings.calls.length, 0);
  assert.equal(h.families.calls.length, 0);
});

test('T16_Ble_backFromScanStopsScanAndDropsTheTenSecondTimer', async () => {
  const h = setup();
  await h.vm.initialize('family-1');
  await h.vm.requestPermission();
  await h.vm.startScan();
  assert.equal(h.timer.pending(), 1);
  h.vm.back();
  await waitMicrotasks();
  assert.equal(h.vm.getState().step, 0);
  assert.equal(h.vm.getState().error, undefined);
  assert.equal(h.ble.stopCalls, 1);
  assert.equal(h.timer.pending(), 0);
  h.timer.advance(10000);
  assert.equal(h.vm.getState().step, 0);
  assert.equal(h.vm.getState().error, undefined);
});

test('T16_Ble_backDuringStartScanCannotInstallLateTimer', async () => {
  const h = setup();
  await h.vm.initialize('family-1');
  await h.vm.requestPermission();
  let releaseStart;
  h.ble.startScan = async () => new Promise((resolve) => {
    releaseStart = resolve;
  });
  const scanning = h.vm.startScan();
  await waitMicrotasks();
  assert.equal(h.vm.getState().step, 1);
  h.vm.back();
  releaseStart();
  await scanning;
  await waitMicrotasks();
  assert.equal(h.vm.getState().step, 0);
  assert.equal(h.timer.pending(), 0);
  h.timer.advance(10000);
  assert.equal(h.vm.getState().step, 0);
  assert.equal(h.vm.getState().error, undefined);
});

test('T16_Ble_scanTimeoutWithoutResultsShowsRetryableError', async () => {
  const h = setup();
  await h.vm.initialize('family-1');
  await h.vm.requestPermission();
  await h.vm.startScan();
  h.timer.advance(10000);
  assert.equal(h.vm.getState().error.error.code, 'PROVISIONING_DEVICE_NOT_FOUND');
  assert.equal(h.vm.getState().step, 1);
});

test('T16_Ble_stateMapCoversAllSixSteps', () => {
  const h = setup();
  const cases = [
    ['PERMISSION', 0], ['SCANNING', 1], ['CONNECTING', 2], ['SECURITY_HANDSHAKE', 2],
    ['AP_SCANNING', 3], ['SENDING_CREDENTIALS', 4], ['WAITING_FOR_WIFI', 4],
    ['DISCOVERING_ON_LAN', 5], ['BOUND', 5]
  ];
  for (const [state, step] of cases) {
    h.vm.onProvisionState({ state });
    assert.equal(h.vm.getState().step, step, state);
  }
});

test('T16_Ble_wifiFailureRetryReturnsToStepThree', async () => {
  const h = setup({ result: AppErrors.of('PROVISIONING_WIFI_AUTH_ERROR', []) });
  await readyDevice(h);
  await h.vm.submit('12345678', 'HomeWifi', 'wifi-password');
  assert.equal(h.vm.getState().provisioning, 'FAILED');
  await h.vm.retry();
  assert.equal(h.vm.getState().step, 3);
});
