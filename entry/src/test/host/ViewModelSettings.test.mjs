/*
 * YaoCore T-16 SettingsViewModel host tests.
 * Producer: agent:implementation-engineer | Task: T-16 / wp-060-vm
 * Contract: DES-B §12.1.2, §12.3.2; F-03/F-06; D-012/D-015.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { SettingsViewModel } from '../../main/ets/viewmodel/SettingsViewModel.ets';
import { CloudConfig } from '../../main/ets/model/FamilyModels.ets';
import { StorageConstants } from '../../main/ets/common/constants/StorageConstants.ets';
import { AppErrors } from '../../main/ets/common/types/AppError.ets';
import { LocaleMode, SupportedLocale } from '../../main/ets/model/I18nModels.ets';
import {
  FakeClock,
  FakeLogger,
  FAMILY_ID,
  FakeRoutes,
  route
} from './viewmodel-helpers.mjs';

class FakeI18nSettings {
  constructor(options = {}) {
    this.locale = options.locale === undefined ? SupportedLocale.ZH_CN : options.locale;
    this.mode = options.mode === undefined ? LocaleMode.AUTO : options.mode;
    this.failApply = options.failApply === undefined ? false : options.failApply;
    this.listeners = [];
    this.calls = [];
  }

  t(key) { return 't:' + key; }
  getLocale() { return this.locale; }
  getLocaleMode() { return this.mode; }

  async setLocaleMode(mode) {
    this.calls.push(mode);
    this.mode = mode;
    this.locale = mode === LocaleMode.EN_US ? SupportedLocale.EN_US : SupportedLocale.ZH_CN;
    const event = {
      previous: SupportedLocale.ZH_CN,
      current: this.locale,
      mode,
      platformApplied: !this.failApply,
      revision: this.calls.length
    };
    for (const listener of this.listeners) {
      listener(event);
    }
  }

  onLocaleChanged(listener) {
    this.listeners.push(listener);
    return () => {
      this.listeners = this.listeners.filter((entry) => entry !== listener);
    };
  }
}

class FakeCloud {
  constructor(options = {}) {
    this.view = options.view === undefined ? { state: 'CONFIGURED', tokenPresent: true } :
      options.view;
    this.testResult = options.testResult === undefined ? { valid: true, errors: [] } :
      options.testResult;
    this.saved = [];
    this.cleared = 0;
  }
  async getState() { return this.view; }
  async saveConfig(config, token) {
    this.saved.push({ config, token });
    this.view = { state: 'CONFIGURED', tokenPresent: token !== undefined, config };
    return this.view;
  }
  async clearToken() {
    this.cleared++;
    this.view = { state: 'TOKEN_MISSING', tokenPresent: false };
  }
  async testConnection() {
    // Mirror C-15 T-14 F-03 ruling: 401/403 are a transient TOKEN_* view,
    // network failures do not change the persistent state.
    if (!this.testResult.valid) {
      const tokenError = this.testResult.errors.find((entry) =>
        entry.code === 'CLOUD_TOKEN_EXPIRED' || entry.code === 'CLOUD_TOKEN_INVALID');
      if (tokenError !== undefined) {
        this.view = { state: tokenError.code === 'CLOUD_TOKEN_EXPIRED' ?
          'TOKEN_EXPIRED' : 'TOKEN_INVALID', tokenPresent: true };
      }
    }
    return this.testResult;
  }
}

class FakeDiscovery {
  constructor(options = {}) {
    this.probe = options.probe;
    this.manual = options.manual;
    this.manualCalls = [];
    this.reset = [];
  }
  async probeLastKnown() {
    if (this.probe instanceof Error) {
      throw this.probe;
    }
    return this.probe;
  }
  async probeManual(gatewayId, address) {
    this.manualCalls.push({ gatewayId, address });
    if (this.manual instanceof Error) {
      throw this.manual;
    }
    return this.manual;
  }
  resetManualFailures(gatewayId) { this.reset.push(gatewayId); }
}

class FakePrefs {
  constructor() { this.values = new Map(); this.flushes = 0; }
  async getString(key) { return this.values.get(key); }
  async putString(key, value) { this.values.set(key, value); }
  async delete(key) { this.values.delete(key); }
  async flush() { this.flushes++; }
}

class FakeAuth {
  constructor(familyId = FAMILY_ID) { this.familyId = familyId; }
  getActiveSession() { return { familyId: this.familyId, memberId: 'member-admin' }; }
  canManageFamily() { return { allowed: true, reason: 'ALLOWED' }; }
}

function setup(options = {}) {
  const i18n = new FakeI18nSettings(options);
  const cloud = new FakeCloud(options);
  const routes = new FakeRoutes(options.routes === undefined ? [route()] : options.routes);
  const discovery = new FakeDiscovery({
    probe: options.probe === undefined ? { profile: 'P-TLS-PIN', latencyMs: 2 } : options.probe,
    manual: options.manual === undefined ? { latencyMs: 4, verified: true } : options.manual
  });
  const prefs = new FakePrefs();
  const vm = new SettingsViewModel(i18n, cloud, routes, discovery, new FakeAuth(),
    prefs, new FakeClock(), new FakeLogger(), '1.2.3');
  return { i18n, cloud, routes, discovery, prefs, vm };
}

test('T16_Settings_initializeLoadsLocaleCloudSecurityAndPreferences', async () => {
  const h = setup();
  await h.vm.initialize();
  const state = h.vm.getState();
  assert.equal(state.phase, 'READY');
  assert.equal(state.currentLocale, 'zh-CN');
  assert.equal(state.localeMode, 'auto');
  assert.equal(state.cloud.state, 'CONFIGURED');
  assert.equal(state.security.length, 1);
  assert.equal(state.security[0].effectiveProfile, 'P-TLS-PIN');
  assert.equal(state.security[0].tlsEnabled, true);
  assert.equal(state.motionEnabled, true);
  assert.equal(state.notificationsEnabled, false);
  assert.equal(state.appVersion, '1.2.3');
});

test('T16_Settings_localeSwitchUpdatesStateAndPlatformRestartFlag', async () => {
  const h = setup({ failApply: true });
  await h.vm.initialize();
  await h.vm.setLocaleMode(LocaleMode.EN_US);
  const state = h.vm.getState();
  assert.equal(state.currentLocale, 'en-US');
  assert.equal(state.localeMode, 'en-US');
  assert.equal(state.platformRestartRequired, true);
  assert.deepEqual(h.i18n.calls, ['en-US']);
});

test('T16_Settings_multiGatewayFamilyRestrictsCloudAndRejectsSave', async () => {
  const h = setup({ routes: [route(), route({ gatewayId: 'gw-2' })] });
  await h.vm.initialize();
  assert.equal(h.vm.getState().cloudRestricted, true);
  assert.equal(h.vm.getState().cloudRestrictionKey,
    'settings.cloud.single_gateway_required');
  const config = new CloudConfig('https://iotda.example.com', 'project-1', 'device-1',
    StorageConstants.ASSET_CLOUD_TOKEN);
  await h.vm.saveCloudConfig(config, 'PUBLIC-TEST-TOKEN');
  assert.equal(h.cloud.saved.length, 0);
  assert.equal(h.vm.getState().error.error.code, 'CONFIGURATION_ERROR');
  assert.equal(await h.vm.testCloudConnection(), false);
});

test('T16_Settings_saveCloudConfigPreservesTokenWhenEmpty', async () => {
  const h = setup();
  await h.vm.initialize();
  const config = new CloudConfig('https://iotda.example.com', 'project-1', 'device-1',
    StorageConstants.ASSET_CLOUD_TOKEN);
  await h.vm.saveCloudConfig(config, '');
  assert.equal(h.cloud.saved[0].token, undefined);
  assert.equal(h.vm.getState().pendingAction, false);

  await h.vm.saveCloudConfig(config, 'PUBLIC-TEST-TOKEN');
  assert.equal(h.cloud.saved[1].token, 'PUBLIC-TEST-TOKEN');
});

test('T16_Settings_testConnectionSuccessRefreshesAndFailureMapsTokenError', async () => {
  const ok = setup();
  await ok.vm.initialize();
  assert.equal(await ok.vm.testCloudConnection(), true);
  assert.equal(ok.vm.getState().error, undefined);

  const bad = setup({ testResult: { valid: false, errors: [
    AppErrors.of('CLOUD_TOKEN_EXPIRED', [])
  ] } });
  await bad.vm.initialize();
  assert.equal(bad.vm.getState().cloud.state, 'CONFIGURED');
  assert.equal(await bad.vm.testCloudConnection(), false);
  assert.equal(bad.vm.getState().error.error.code, 'CLOUD_TOKEN_EXPIRED');
  // F-04: the persistent layer must no longer look CONFIGURED after expiry.
  assert.equal(bad.vm.getState().cloud.state, 'TOKEN_EXPIRED');
});

test('T16_Settings_networkTestFailureDoesNotDowngradeCloudState', async () => {
  const h = setup({ testResult: { valid: false, errors: [
    AppErrors.of('CLOUD_REQUEST_FAILED', [])
  ] } });
  await h.vm.initialize();
  assert.equal(h.vm.getState().cloud.state, 'CONFIGURED');
  assert.equal(await h.vm.testCloudConnection(), false);
  assert.equal(h.vm.getState().error.error.code, 'CLOUD_REQUEST_FAILED');
  assert.equal(h.vm.getState().cloud.state, 'CONFIGURED');
});

test('T16_Settings_clearTokenKeepsConfigAndShowsTokenMissing', async () => {
  const h = setup();
  await h.vm.initialize();
  await h.vm.clearCloudToken();
  assert.equal(h.cloud.cleared, 1);
  assert.equal(h.vm.getState().cloud.state, 'TOKEN_MISSING');
});

test('T16_Settings_securityProbeFailureShowsMappedKeyWithoutDowngradingProfile', async () => {
  const h = setup({ probe: AppErrors.of('TLS_HANDSHAKE_FAILED', []) });
  await h.vm.initialize();
  const security = h.vm.getState().security[0];
  assert.equal(security.effectiveProfile, 'P-HMAC');
  assert.equal(security.lastErrorKey, 'errors.app.tls_handshake_failed');
});

test('T16_Settings_manualAddressProbeAcceptsBoundAndRejectsLoopback', async () => {
  const h = setup();
  await h.vm.initialize();
  const accepted = await h.vm.probeManualAddress('gw-1', ' 192.168.1.20 ', 8443);
  assert.equal(accepted.accepted, true);
  assert.equal(accepted.latencyMs, 4);
  assert.equal(h.discovery.manualCalls[0].address.ip, '192.168.1.20');
  assert.deepEqual(h.discovery.reset, ['gw-1']);

  const rejected = await h.vm.probeManualAddress('gw-1', '127.0.0.1', 8443);
  assert.equal(rejected.accepted, false);
  assert.equal(rejected.error.error.code, 'MANUAL_ADDRESS_REJECTED');
  assert.equal(h.discovery.manualCalls.length, 1);
});

test('T16_Settings_motionAndNotificationPreferencesPersist', async () => {
  const h = setup();
  await h.vm.initialize();
  await h.vm.setMotionEnabled(false);
  await h.vm.setNotificationsEnabled(true);
  assert.equal(h.prefs.values.get('app.motion.enabled'), 'false');
  assert.equal(h.prefs.values.get('app.notifications.enabled'), 'true');
  assert.equal(h.vm.getState().motionEnabled, false);
  assert.equal(h.vm.getState().notificationsEnabled, true);
  assert.equal(h.prefs.flushes, 2);
});

test('T16_Settings_sectionAndAdvancedExpansionAreLocalOnly', async () => {
  const h = setup();
  await h.vm.initialize();
  h.vm.setSection('ADVANCED');
  h.vm.setAdvancedExpanded(true);
  assert.equal(h.vm.getState().section, 'ADVANCED');
  assert.equal(h.vm.getState().advancedExpanded, true);
  assert.equal(h.cloud.saved.length, 0);
});
