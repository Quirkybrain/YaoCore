/*
 * YaoCore T-17 app shell host tests (D-019).
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §17.4 (C28-SEAM), §2.4, §2.8; CQG-T14 F-06; CQG-T15/T16 R3-02
 *
 * The Node host runner imports pure ArkTS only. Platform PermissionGate /
 * AppCompositionRoot are covered by source-boundary assertions; device/UI
 * execution remains BLOCKED.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { AppContext, SessionGateState } from '../../main/ets/app/AppContext.ets';
import {
  AppRoute,
  AppRouteParams,
  AppRouteValidation,
  NavigationService
} from '../../main/ets/app/NavigationService.ets';
import {
  ASSEMBLY_CONSTRUCTION_ORDER,
  ASSEMBLY_INITIALIZATION_ORDER,
  AssemblyTrace,
  ConstructionStep,
  InitializationStep
} from '../../main/ets/app/CompositionPlan.ets';
import { ActiveCloudScope } from '../../main/ets/app/ActiveCloudScope.ets';
import { ContinuousGestureGuard } from '../../main/ets/app/ContinuousGestureGuard.ets';
import {
  PermissionKind,
  PermissionPolicy,
  PermissionState
} from '../../main/ets/app/PermissionPolicy.ets';
import { AppErrors } from '../../main/ets/common/types/AppError.ets';

const TEST_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(TEST_DIR, '../../../..');

const FAMILY = { familyId: 'family-1', familyName: 'Home' };

class FakeAuth {
  constructor(calls, profileList) {
    this.calls = calls;
    this.profiles = profileList === undefined ? [] : profileList;
    this.session = undefined;
    this.unlockError = undefined;
  }

  async listProfiles(familyId) {
    this.calls.push('listProfiles');
    this.lastFamilyId = familyId;
    return this.profiles;
  }

  getActiveSession() {
    return this.session;
  }

  async unlock(profileId, password) {
    this.calls.push('unlock');
    if (this.unlockError !== undefined) {
      throw this.unlockError;
    }
    this.session = {
      sessionId: 's-1',
      profileId,
      familyId: FAMILY.familyId,
      memberId: 'member-1'
    };
    return this.session;
  }

  async lockAll() {
    this.calls.push('lockAll');
    this.session = undefined;
  }
}

class FakeFamilyRepository {
  constructor(calls, family) {
    this.calls = calls;
    this.family = family;
  }

  async getActiveFamily() {
    this.calls.push('getActiveFamily');
    return this.family;
  }

  async setActiveFamily(familyId) {
    this.calls.push('setActiveFamily');
    this.family = { familyId, familyName: 'Home' };
  }
}

class FakePreferences {
  constructor(calls) {
    this.calls = calls;
    this.values = new Map();
  }

  async getString(key) {
    return this.values.get(key);
  }

  async putString(key, value) {
    this.values.set(key, value);
  }

  async delete(key) {
    this.values.delete(key);
  }

  async flush() {
    this.calls.push('preferences.flush');
  }
}

class FakeDrafts {
  constructor(calls) {
    this.calls = calls;
  }

  clearAll() {
    this.calls.push('drafts.clearAll');
  }
}

class FakeBle {
  constructor(calls) {
    this.calls = calls;
  }

  async cancel() {
    this.calls.push('ble.cancel');
  }
}

class FakeCloud {
  constructor(calls) {
    this.calls = calls;
  }

  stopPolling() {
    this.calls.push('cloud.stopPolling');
  }
}

class FakeLogger {
  constructor() {
    this.messages = [];
  }

  warn(tag, message) {
    this.messages.push(message);
  }
}

class FakeI18n {
  constructor() {
    this.reloads = 0;
  }

  async reload() {
    this.reloads++;
  }

  onLocaleChanged() {
    return () => {};
  }

  t(key) {
    return 't:' + key;
  }
}

class FakeRoot {
  constructor(options = {}) {
    this.calls = options.calls === undefined ? [] : options.calls;
    this.auth = new FakeAuth(this.calls, options.profiles);
    this.family = new FakeFamilyRepository(this.calls,
      Object.prototype.hasOwnProperty.call(options, 'family') ? options.family : FAMILY);
    this.preferences = new FakePreferences(this.calls);
    this.secretDrafts = new FakeDrafts(this.calls);
    this.ble = new FakeBle(this.calls);
    this.cloud = new FakeCloud(this.calls);
    this.logger = new FakeLogger();
    this.i18nValue = new FakeI18n();
    this.fail = options.fail;
    this.initialized = false;
    this.error = undefined;
  }

  get i18n() {
    return this.i18nValue;
  }

  get sessionAuth() {
    return this.auth;
  }

  get activeFamily() {
    return this.family;
  }

  async initialize() {
    this.calls.push('root.initialize');
    if (this.fail !== undefined) {
      this.error = this.fail;
      throw this.fail;
    }
    this.initialized = true;
    this.error = undefined;
  }

  isInitialized() {
    return this.initialized;
  }

  getInitializationError() {
    return this.error;
  }
}

class FakeNavStack {
  constructor() {
    this.entries = [];
    this.clears = 0;
    this.popToCalls = [];
  }

  pushPathByName(name, param, animated) {
    this.entries.push({ name, param, animated });
  }

  replacePathByName(name, param, animated) {
    this.entries[this.entries.length - 1] = { name, param, animated };
  }

  pop() {
    return this.entries.pop();
  }

  popToName(name, animated) {
    this.popToCalls.push({ name, animated });
    let index = -1;
    for (let position = 0; position < this.entries.length; position++) {
      if (this.entries[position].name === name) {
        index = position;
        break;
      }
    }
    if (index < 0) {
      return -1;
    }
    this.entries.splice(index + 1);
    return this.entries.length;
  }

  getAllPathName() {
    return this.entries.map((entry) => entry.name);
  }

  size() {
    return this.entries.length;
  }

  clear() {
    this.clears++;
    this.entries = [];
  }
}

function source(relative) {
  return fs.readFileSync(path.join(REPO_ROOT, relative), 'utf8');
}

test('T17_sessionGateNoFamilyIsNoProfile', async () => {
  const root = new FakeRoot({ family: undefined });
  const context = new AppContext(root);
  await context.initialize();
  assert.equal(context.sessionGate, SessionGateState.NO_PROFILE);
  assert.equal(context.activeFamilyId, undefined);
});

test('T17_sessionGateFamilyWithoutProfileIsNoProfile', async () => {
  const root = new FakeRoot({ profiles: [] });
  const context = new AppContext(root);
  await context.initialize();
  assert.equal(context.sessionGate, SessionGateState.NO_PROFILE);
  assert.equal(context.activeFamilyId, FAMILY.familyId);
});

test('T17_sessionGateProfileWithoutSessionIsLocked', async () => {
  const root = new FakeRoot({ profiles: [{ profileId: 'p-1', displayName: 'Owner' }] });
  const context = new AppContext(root);
  await context.initialize();
  assert.equal(context.sessionGate, SessionGateState.LOCKED);
});

test('T17_sessionGateProfileWithSessionIsUnlocked', async () => {
  const root = new FakeRoot({ profiles: [{ profileId: 'p-1', displayName: 'Owner' }] });
  root.auth.session = { sessionId: 's-1', profileId: 'p-1' };
  const context = new AppContext(root);
  await context.initialize();
  assert.equal(context.sessionGate, SessionGateState.UNLOCKED);
});

test('T17_unlockRefreshesGateAndMapsProfiles', async () => {
  const root = new FakeRoot({ profiles: [{ profileId: 'p-1', displayName: 'Owner' }] });
  const context = new AppContext(root);
  await context.initialize();
  assert.equal(context.sessionGate, SessionGateState.LOCKED);
  const profiles = await context.listProfiles();
  assert.deepEqual(profiles.map((entry) => entry.profileId), ['p-1']);
  assert.deepEqual(profiles.map((entry) => entry.displayName), ['Owner']);
  await context.unlock('p-1', 'secret');
  assert.equal(context.sessionGate, SessionGateState.UNLOCKED);
  assert.equal((await context.listProfiles()).length, 1);
});

test('T17_lockReturnsToLocked', async () => {
  const root = new FakeRoot({ profiles: [{ profileId: 'p-1', displayName: 'Owner' }] });
  root.auth.session = { sessionId: 's-1', profileId: 'p-1' };
  const context = new AppContext(root);
  await context.initialize();
  assert.equal(context.sessionGate, SessionGateState.UNLOCKED);
  await context.lock();
  assert.equal(context.sessionGate, SessionGateState.LOCKED);
});

test('T17_backgroundCleanupOrderMatchesContract', async () => {
  const calls = [];
  const root = new FakeRoot({ calls, profiles: [{ profileId: 'p-1', displayName: 'Owner' }] });
  root.auth.session = { sessionId: 's-1', profileId: 'p-1' };
  const context = new AppContext(root);
  await context.initialize();
  context.subscribeLifecycle({
    onForeground: async () => { calls.push('observer.foreground'); },
    onBackground: async () => { calls.push('observer.background'); }
  });
  calls.length = 0;
  await context.onBackground();
  assert.deepEqual(calls.slice(0, 5), [
    'lockAll',
    'getActiveFamily',
    'listProfiles',
    'drafts.clearAll',
    'ble.cancel'
  ]);
  assert.ok(calls.indexOf('cloud.stopPolling') > calls.indexOf('ble.cancel'));
  assert.ok(calls.indexOf('observer.background') > calls.indexOf('cloud.stopPolling'));
  assert.equal(calls[calls.length - 1], 'preferences.flush');
});

test('T17_foregroundNotifiesObserversAndReloadsLocale', async () => {
  const calls = [];
  const root = new FakeRoot({ calls, profiles: [] });
  const context = new AppContext(root);
  await context.initialize();
  context.subscribeLifecycle({
    onForeground: async () => { calls.push('observer.foreground'); },
    onBackground: async () => { calls.push('observer.background'); }
  });
  calls.length = 0;
  await context.onForeground();
  assert.equal(context.isForeground, true);
  assert.equal(calls[0], 'observer.foreground');
  assert.equal(calls[1], 'getActiveFamily');
  assert.equal(root.i18nValue.reloads, 1);
});

test('T17_initializationFailureCanRetry', async () => {
  const root = new FakeRoot({
    profiles: [{ profileId: 'p-1', displayName: 'Owner' }],
    fail: AppErrors.of('STORAGE_MIGRATION_FAILED', [])
  });
  const context = new AppContext(root);
  await context.initialize();
  assert.equal(context.initializationError.code, 'STORAGE_MIGRATION_FAILED');
  root.fail = undefined;
  await context.retryInitialization();
  assert.equal(context.initializationError, undefined);
  assert.equal(context.sessionGate, SessionGateState.LOCKED);
});

test('T17_motionPreferenceDefaultsToEnabled', async () => {
  const root = new FakeRoot({ profiles: [] });
  const context = new AppContext(root);
  await context.initialize();
  assert.equal(await context.isMotionEnabled(), true);
  root.preferences.values.set('app.motion.enabled', 'false');
  assert.equal(await context.isMotionEnabled(), false);
});

test('T17_navigationPushPopAndBack', () => {
  const stack = new FakeNavStack();
  const navigation = new NavigationService(stack);
  navigation.push(AppRoute.FAMILY);
  assert.equal(stack.size(), 1);
  assert.equal(stack.entries[0].name, AppRoute.FAMILY);
  assert.equal(navigation.onBack(), true);
  assert.equal(stack.size(), 0);
  assert.equal(navigation.onBack(), false);
});

test('T17_navigationTabSwitchClearsStack', () => {
  const stack = new FakeNavStack();
  const navigation = new NavigationService(stack);
  let selected = -1;
  navigation.setTabChangeListener((index) => { selected = index; });
  navigation.push(AppRoute.SETTINGS);
  navigation.switchTab(AppRoute.SCENES_TAB);
  assert.equal(stack.size(), 0);
  assert.equal(stack.clears, 1);
  assert.equal(selected, 2);
  assert.equal(navigation.getSelectedTab(), AppRoute.SCENES_TAB);
});

test('T17_navigationPushTabRouteSwitchesInsteadOfPushing', () => {
  const stack = new FakeNavStack();
  const navigation = new NavigationService(stack);
  navigation.push(AppRoute.ROOMS_TAB);
  assert.equal(stack.size(), 0);
  assert.equal(navigation.getSelectedTabIndex(), 1);
});

test('T17_navigationReplaceAndPopTo', () => {
  const stack = new FakeNavStack();
  const navigation = new NavigationService(stack);
  navigation.push(AppRoute.FAMILY);
  navigation.push(AppRoute.SETTINGS);
  navigation.replace(AppRoute.ABOUT);
  assert.equal(stack.entries[1].name, AppRoute.ABOUT);
  navigation.popTo(AppRoute.FAMILY);
  assert.deepEqual(stack.popToCalls, [{ name: AppRoute.FAMILY, animated: false }]);
});

test('T17_routeValidationRequiresDeviceIdentity', () => {
  assert.equal(AppRouteValidation.accepts(AppRoute.DEVICE_CONTROL), false);
  assert.equal(AppRouteValidation.accepts(AppRoute.DEVICE_CONTROL,
    new AppRouteParams({ gatewayId: 'gw-1' })), false);
  assert.equal(AppRouteValidation.accepts(AppRoute.DEVICE_CONTROL,
    new AppRouteParams({ gatewayId: 'gw-1', deviceId: 'dev-1' })), true);
  assert.equal(AppRouteValidation.accepts(AppRoute.PROVISIONING,
    new AppRouteParams({ mode: 'UNKNOWN' })), false);
  assert.equal(AppRouteValidation.accepts(AppRoute.PROVISIONING,
    new AppRouteParams({ mode: 'ROTATE_SECRET' })), true);
  assert.equal(AppRouteValidation.fromName('not-a-route'), undefined);
});

test('T17_compositionPlanOrderAndDependencies', () => {
  assert.equal(ASSEMBLY_CONSTRUCTION_ORDER[0], ConstructionStep.PLATFORM);
  assert.equal(ASSEMBLY_CONSTRUCTION_ORDER[ASSEMBLY_CONSTRUCTION_ORDER.length - 1],
    ConstructionStep.APP_CONTEXT);
  assert.equal(new Set(ASSEMBLY_CONSTRUCTION_ORDER).size,
    ASSEMBLY_CONSTRUCTION_ORDER.length);
  assert.ok(ASSEMBLY_CONSTRUCTION_ORDER.indexOf(ConstructionStep.GATEWAY_CLIENTS) <
    ASSEMBLY_CONSTRUCTION_ORDER.indexOf(ConstructionStep.SCENE_SERVICE));
  assert.ok(ASSEMBLY_CONSTRUCTION_ORDER.indexOf(ConstructionStep.STORAGE_SERVICE) <
    ASSEMBLY_CONSTRUCTION_ORDER.indexOf(ConstructionStep.AUTH_SERVICE));
  assert.ok(ASSEMBLY_INITIALIZATION_ORDER.indexOf(InitializationStep.STORAGE) <
    ASSEMBLY_INITIALIZATION_ORDER.indexOf(InitializationStep.AUTH));
  assert.ok(ASSEMBLY_INITIALIZATION_ORDER.indexOf(InitializationStep.DEVICE) <
    ASSEMBLY_INITIALIZATION_ORDER.indexOf(InitializationStep.CLOUD));
  assert.ok(ASSEMBLY_INITIALIZATION_ORDER.indexOf(InitializationStep.CLOUD) <
    ASSEMBLY_INITIALIZATION_ORDER.indexOf(InitializationStep.I18N));
});

test('T17_assemblyTraceFailsClosedOnOutOfOrderStep', () => {
  const trace = new AssemblyTrace(ASSEMBLY_CONSTRUCTION_ORDER);
  trace.record(ConstructionStep.PLATFORM);
  assert.equal(trace.isComplete(), false);
  assert.throws(() => trace.record(ConstructionStep.SECURITY), (error) => {
    assert.equal(error.code, 'CONFIGURATION_ERROR');
    return true;
  });
  const ordered = new AssemblyTrace(ASSEMBLY_CONSTRUCTION_ORDER);
  for (const step of ASSEMBLY_CONSTRUCTION_ORDER) {
    ordered.record(step);
  }
  assert.equal(ordered.isComplete(), true);
});

test('T17_activeCloudScopeFailsClosedOutsideSingleGateway', async () => {
  let routes = [];
  const fakeRoutes = {
    async listRoutesByFamily() { return routes; },
    async isBound(gatewayId) { return gatewayId === 'gw-1'; }
  };
  const scope = new ActiveCloudScope(fakeRoutes);
  assert.equal(await scope.activeGatewayId(), undefined);
  scope.setActiveFamilyIdProvider(() => FAMILY.familyId);
  assert.equal(await scope.activeGatewayId(), undefined);
  routes = [{ gatewayId: 'gw-1' }];
  assert.equal(await scope.activeGatewayId(), 'gw-1');
  routes = [{ gatewayId: 'gw-1' }, { gatewayId: 'gw-2' }];
  assert.equal(await scope.activeGatewayId(), undefined);
  assert.equal(await scope.isGatewayBound('gw-1'), true);
  assert.equal(await scope.isGatewayBound('gw-2'), false);
});

test('T17_permissionPolicyManifestIsMinimal', () => {
  assert.deepEqual(PermissionPolicy.manifestPermissions(), [
    'ohos.permission.INTERNET',
    'ohos.permission.ACCESS_BLUETOOTH'
  ]);
  assert.deepEqual(PermissionPolicy.requiredForProvisioning(), [PermissionKind.BLUETOOTH]);
  assert.equal(PermissionPolicy.isSystemGrant(PermissionKind.INTERNET), true);
  assert.equal(PermissionPolicy.isRuntimeRequestable(PermissionKind.INTERNET), false);
  assert.equal(PermissionPolicy.isRuntimeRequestable(PermissionKind.BLUETOOTH), true);
  assert.equal(PermissionPolicy.isDeclared(PermissionKind.CAMERA), false);
  assert.equal(PermissionPolicy.isDeclared(PermissionKind.LOCATION_OPTIONAL), false);
});

test('T17_permissionStateMapping', () => {
  assert.equal(PermissionPolicy.stateFromSelfStatus(0), PermissionState.GRANTED);
  assert.equal(PermissionPolicy.stateFromSelfStatus(-1), PermissionState.DENIED);
  assert.equal(PermissionPolicy.stateFromSelfStatus(1), PermissionState.NOT_DETERMINED);
  assert.equal(PermissionPolicy.stateFromSelfStatus(2), PermissionState.UNAVAILABLE);
  assert.equal(PermissionPolicy.stateFromRequestResult(0), PermissionState.GRANTED);
  assert.equal(PermissionPolicy.stateFromRequestResult(-1), PermissionState.DENIED);
  assert.equal(PermissionPolicy.canOpenSettings(PermissionState.DENIED), true);
  assert.equal(PermissionPolicy.canOpenSettings(PermissionState.GRANTED), false);
  assert.equal(PermissionPolicy.errorFor(PermissionKind.BLUETOOTH,
    PermissionState.GRANTED), undefined);
  assert.equal(PermissionPolicy.errorFor(PermissionKind.BLUETOOTH,
    PermissionState.DENIED).code, 'PROVISIONING_PERMISSION_DENIED');
});

test('T17_continuousGestureGuardSuppressesTouchUpAfterCancel', () => {
  const guard = new ContinuousGestureGuard();
  guard.begin();
  assert.equal(guard.end(), true);
  guard.begin();
  guard.cancel();
  assert.equal(guard.isCancelled(), true);
  assert.equal(guard.end(), false);
  assert.equal(guard.end(), false);
});

test('T17_moduleJsonDeclaresOnlyRequiredPermissions', () => {
  const text = source('entry/src/main/module.json5');
  assert.ok(text.includes('ohos.permission.INTERNET'));
  assert.ok(text.includes('ohos.permission.ACCESS_BLUETOOTH'));
  assert.ok(!text.includes('ohos.permission.CAMERA'));
  assert.ok(!text.includes('LOCATION'));
  assert.ok(text.includes('$string:permission_bluetooth_reason'));
});

test('T17_compositionRootHasNoProductionMockOrDevOnlyBranch', () => {
  const appRoot = path.join(REPO_ROOT, 'entry/src/main/ets/app');
  const files = fs.readdirSync(appRoot).filter((name) => name.endsWith('.ets'));
  for (const name of files) {
    const text = fs.readFileSync(path.join(appRoot, name), 'utf8');
    assert.ok(!/from\s+['"][^'"]*Mock/.test(text), name + ' imports a Mock module');
    assert.ok(!/from\s+['"][^'"]*ohosTest/.test(text), name + ' imports ohosTest');
    assert.ok(!/DEV-ONLY/.test(text), name + ' contains DEV-ONLY');
  }
});

test('T17_compositionRootInjectsCloudScopeAndClock', () => {
  const text = source('entry/src/main/ets/app/AppCompositionRoot.ets');
  assert.ok(text.includes('new ActiveCloudScope(this.gatewayRepository)'));
  assert.ok(text.includes('new RdbCloudConfigStore(this.rdbAdapter, this.clock)'));
  assert.ok(text.includes('CloudSendRetryPolicy.defaults(), this.activeCloudScope'));
  assert.ok(text.includes('new SystemTimerPort()'));
  assert.ok(text.includes('setActiveFamilyIdProvider'));
});

test('T17_pagesDoNotWireCancelAndEndTogether', () => {
  const pagesRoot = path.join(REPO_ROOT, 'entry/src/main/ets/pages');
  for (const name of fs.readdirSync(pagesRoot)) {
    if (!name.endsWith('.ets')) {
      continue;
    }
    const text = fs.readFileSync(path.join(pagesRoot, name), 'utf8');
    assert.ok(!(text.includes('cancelContinuous') && text.includes('endContinuous')),
      name + ' must use ContinuousGestureGuard for cancel/TouchUp wiring');
  }
});

test('T17_brandAndSingleGatewayResourcesExist', () => {
  for (const locale of ['zh-CN', 'en-US']) {
    const bundle = JSON.parse(source('entry/src/main/resources/rawfile/i18n/' + locale + '.json'));
    for (const brand of ['gree', 'haier', 'midea', 'generic']) {
      assert.equal(typeof bundle.brand[brand], 'string');
      assert.ok(bundle.brand[brand].length > 0);
    }
    assert.equal(typeof bundle.settings.cloud.single_gateway_required, 'string');
    assert.ok(bundle.settings.cloud.single_gateway_required.length > 0);
  }
});
