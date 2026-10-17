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
import { INVALID_ROUTE_NAME } from '../../main/ets/app/NavigationService.ets';
import {
  ShellGateEntry,
  ShellGateRouting
} from '../../main/ets/app/ShellGateRouting.ets';
import { OnboardingService } from '../../main/ets/app/OnboardingService.ets';
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

class FakeOnboarding {
  constructor(root) {
    this.root = root;
    this.calls = root.calls;
  }

  async createFamily(familyName, displayName, password) {
    this.calls.push('onboarding.createFamily');
    this.lastCreate = { familyName, displayName, password };
    this.root.family.family = { familyId: 'family-new', familyName };
    this.root.auth.profiles = [{ profileId: 'p-new', displayName }];
    this.root.auth.session = undefined;
  }

  async startJoin(displayName) {
    this.calls.push('onboarding.startJoin');
    this.lastStartJoin = { displayName };
    return 'YCR1.join-request-' + displayName;
  }

  async completeJoin(invitationText, code, displayName, password) {
    this.calls.push('onboarding.completeJoin');
    this.lastJoin = { invitationText, code, displayName, password };
    this.root.family.family = { familyId: 'family-joined', familyName: 'Joined' };
    this.root.auth.profiles = [{ profileId: 'p-joined', displayName }];
    this.root.auth.session = undefined;
  }

  async cancelJoin() {
    this.calls.push('onboarding.cancelJoin');
  }
}

class FakeJoinSession {
  constructor(calls) {
    this.calls = calls;
    this.accepted = {
      familyId: 'family-joined',
      familyName: 'Joined',
      memberId: 'member-joined',
      role: 'MEMBER'
    };
  }

  async start(displayName) {
    this.calls.push('join.start');
    this.displayName = displayName;
    return { text: 'YCR1.fake-request' };
  }

  async submitInvitation(text, code) {
    this.calls.push('join.submitInvitation');
    this.text = text;
    this.code = code;
    return this.accepted;
  }

  async markProfileBound() {
    this.calls.push('join.markProfileBound');
  }

  async cancel() {
    this.calls.push('join.cancel');
  }

  dispose() {
    this.calls.push('join.dispose');
  }
}

class FakeOnboardingFamilyService {
  constructor(calls) {
    this.calls = calls;
    this.joinSession = new FakeJoinSession(calls);
  }

  async createFamily(familyName, ownerDisplayName) {
    this.calls.push('families.createFamily');
    this.familyName = familyName;
    this.ownerDisplayName = ownerDisplayName;
    return {
      familyId: 'family-created',
      familyName,
      ownerMemberId: 'member-owner'
    };
  }

  async switchFamily(familyId) {
    this.calls.push('families.switchFamily');
    this.switchedTo = familyId;
    return { requiresUnlock: true };
  }

  createJoinSession() {
    this.calls.push('families.createJoinSession');
    return this.joinSession;
  }
}

class FakeOnboardingAuthService {
  constructor(calls) {
    this.calls = calls;
    this.profiles = [];
    this.failProfileCreate = undefined;
  }

  async createProfile(input) {
    this.calls.push('auth.createProfile');
    if (this.failProfileCreate !== undefined) {
      throw this.failProfileCreate;
    }
    this.profiles.push(input);
    this.created = input;
  }

  async listProfiles() {
    return this.profiles;
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
    this.onboardingValue = new FakeOnboarding(this);
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

  get onboarding() {
    return this.onboardingValue;
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

function walkEtsFiles(root) {
  const result = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const full = path.join(root, entry.name);
    if (entry.isDirectory()) {
      result.push(...walkEtsFiles(full));
    } else if (entry.name.endsWith('.ets')) {
      result.push(full);
    }
  }
  return result;
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
  root.auth.session = { sessionId: 's-1', profileId: 'p-1', familyId: FAMILY.familyId };
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
  root.auth.session = { sessionId: 's-1', profileId: 'p-1', familyId: FAMILY.familyId };
  const context = new AppContext(root);
  await context.initialize();
  assert.equal(context.sessionGate, SessionGateState.UNLOCKED);
  await context.lock();
  assert.equal(context.sessionGate, SessionGateState.LOCKED);
});

test('T17_backgroundCleanupOrderMatchesContract', async () => {
  const calls = [];
  const root = new FakeRoot({ calls, profiles: [{ profileId: 'p-1', displayName: 'Owner' }] });
  root.auth.session = { sessionId: 's-1', profileId: 'p-1', familyId: FAMILY.familyId };
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

test('T17_gateEntryMappingCoversFreshInstallAndLock', () => {
  assert.deepEqual(ShellGateRouting.entriesFor(SessionGateState.NO_PROFILE),
    [ShellGateEntry.CREATE_FAMILY, ShellGateEntry.JOIN_FAMILY]);
  assert.deepEqual(ShellGateRouting.entriesFor(SessionGateState.LOCKED),
    [ShellGateEntry.UNLOCK]);
  assert.deepEqual(ShellGateRouting.entriesFor(SessionGateState.UNLOCKED), []);
  assert.equal(ShellGateRouting.hasEntry(SessionGateState.NO_PROFILE,
    ShellGateEntry.CREATE_FAMILY), true);
  assert.equal(ShellGateRouting.hasEntry(SessionGateState.LOCKED,
    ShellGateEntry.JOIN_FAMILY), false);
});

test('T17_sessionGateViewWiresOnboardingAndReloadsOnGateOrFamilyChange', () => {
  const shell = source('entry/src/main/ets/pages/ShellViews.ets');
  assert.ok(shell.includes("@Watch('onGateChanged')"));
  assert.ok(shell.includes("@Watch('onFamilyChanged')"));
  assert.ok(shell.includes('OnboardingView('));
  assert.ok(shell.includes('ShellGateRouting.hasEntry'));
  assert.ok(shell.includes('this.loadProfiles();'));
  assert.ok(shell.includes('profilesError'));
  const onboarding = source('entry/src/main/ets/pages/OnboardingView.ets');
  assert.ok(onboarding.includes('this.appContext.createFamily('));
  assert.ok(onboarding.includes('this.appContext.startJoin('));
  assert.ok(onboarding.includes('this.appContext.completeJoin('));
  assert.ok(onboarding.includes('PASSWORD_MIN_LENGTH'));
});

test('T17_entryUsesSharedStorageAndAbilityWritesBootstrap', () => {
  const index = source('entry/src/main/ets/pages/Index.ets');
  assert.ok(index.includes('@Entry({ useSharedStorage: true })'));
  assert.ok(index.includes("@LocalStorageProp('bootstrap')"));
  const ability = source('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.ok(ability.includes('new LocalStorage()'));
  assert.ok(ability.includes("storage.setOrCreate('bootstrap'"));
  assert.ok(ability.includes("windowStage.loadContent('pages/Index', storage"));
});

test('T17_onboardingCreateAndJoinLandLocked', async () => {
  const createRoot = new FakeRoot({ family: undefined });
  const createContext = new AppContext(createRoot);
  await createContext.createFamily('Home', 'Owner', 'password1');
  assert.equal(createContext.sessionGate, SessionGateState.LOCKED);
  assert.equal(createContext.activeFamilyId, 'family-new');
  assert.equal(createRoot.auth.session, undefined);
  assert.equal(createRoot.onboardingValue.lastCreate.familyName, 'Home');

  const joinRoot = new FakeRoot({ family: undefined });
  const joinContext = new AppContext(joinRoot);
  const requestText = await joinContext.startJoin('Member');
  assert.equal(requestText, 'YCR1.join-request-Member');
  await joinContext.completeJoin('YCI1.container', '123456', 'Member', 'password1');
  assert.equal(joinContext.sessionGate, SessionGateState.LOCKED);
  assert.equal(joinContext.activeFamilyId, 'family-joined');
  assert.equal(joinRoot.auth.session, undefined);
  assert.equal(joinRoot.onboardingValue.lastJoin.invitationText, 'YCI1.container');
  await joinContext.cancelJoin();
  assert.ok(joinRoot.calls.includes('onboarding.cancelJoin'));
});

test('T17_setActiveFamilyLocksPreviousSession', async () => {
  const root = new FakeRoot({ profiles: [{ profileId: 'p-1', displayName: 'Owner' }] });
  root.auth.session = {
    sessionId: 's-1', profileId: 'p-1', familyId: FAMILY.familyId
  };
  const context = new AppContext(root);
  await context.initialize();
  assert.equal(context.sessionGate, SessionGateState.UNLOCKED);
  await context.setActiveFamily('family-2');
  assert.equal(root.auth.session, undefined);
  assert.equal(context.sessionGate, SessionGateState.LOCKED);
});

test('T17_sessionFromAnotherFamilyCannotUnlock', async () => {
  const root = new FakeRoot({ profiles: [{ profileId: 'p-1', displayName: 'Owner' }] });
  root.auth.session = {
    sessionId: 's-1', profileId: 'p-1', familyId: 'family-2'
  };
  const context = new AppContext(root);
  await context.initialize();
  assert.equal(context.sessionGate, SessionGateState.LOCKED);
});

test('T17_routeValidationWiredIntoPushAndReplace', () => {
  const stack = new FakeNavStack();
  const navigation = new NavigationService(stack);
  navigation.push(AppRoute.DEVICE_CONTROL);
  assert.equal(stack.entries[0].name, INVALID_ROUTE_NAME);
  navigation.push(AppRoute.DEVICE_CONTROL,
    new AppRouteParams({ gatewayId: 'gw-1', deviceId: 'dev-1' }));
  assert.equal(stack.entries[1].name, AppRoute.DEVICE_CONTROL);
  navigation.replace(AppRoute.PROVISIONING, new AppRouteParams({ mode: 'UNKNOWN' }));
  assert.equal(stack.entries[1].name, INVALID_ROUTE_NAME);
  navigation.replace(AppRoute.PROVISIONING, new AppRouteParams({ mode: 'ROTATE_SECRET' }));
  assert.equal(stack.entries[1].name, AppRoute.PROVISIONING);
});

test('T17_routeBuilderValidatesParametersBeforeConstructingPage', () => {
  const shell = source('entry/src/main/ets/pages/MainShell.ets');
  assert.ok(shell.includes('routeIsValid'));
  assert.ok(shell.includes('AppRouteValidation.accepts'));
  assert.ok(shell.indexOf('!this.routeIsValid(name, param)') <
    shell.indexOf('name === AppRoute.DEVICE_CONTROL'));
  assert.ok(shell.includes('UnknownRouteView'));
});

test('T17_permissionApi14FallbackIsRequestableOnce', () => {
  assert.equal(PermissionPolicy.stateFromTokenCheck(false, 14),
    PermissionState.NOT_DETERMINED);
  assert.equal(PermissionPolicy.stateFromTokenCheck(false, 20), PermissionState.DENIED);
  assert.equal(PermissionPolicy.stateFromTokenCheck(true, 14), PermissionState.GRANTED);
  assert.equal(PermissionPolicy.shouldRequestPermission(PermissionState.NOT_DETERMINED,
    false), true);
  assert.equal(PermissionPolicy.shouldRequestPermission(PermissionState.NOT_DETERMINED,
    true), false);
  assert.equal(PermissionPolicy.shouldRequestPermission(PermissionState.DENIED, false), false);
  assert.equal(PermissionPolicy.stateAfterSuppressedRequest(), PermissionState.DENIED);
  const gate = source('entry/src/main/ets/app/PermissionGate.ets');
  assert.ok(gate.includes('deviceInfo.sdkApiVersion'));
  assert.ok(gate.includes('SELF_PERMISSION_STATUS_MIN_API'));
  assert.ok(gate.includes('shouldRequestPermission'));
  assert.ok(gate.includes('requestPermissionsFromUser'));
});

test('T17_disposeLocksSessionBeforeClosingStorage', () => {
  const text = source('entry/src/main/ets/app/AppCompositionRoot.ets');
  const disposeStart = text.indexOf('async dispose()');
  const lock = text.indexOf('await this.appContextValue.lock();', disposeStart);
  const close = text.indexOf('await this.storage.close();', disposeStart);
  assert.ok(disposeStart >= 0);
  assert.ok(lock > disposeStart, 'dispose must lock the session and gate');
  assert.ok(close > lock, 'storage must close after the session lock');
});

test('T17_productionMockExclusionCoversAllMainSources', () => {
  const mainRoot = path.join(REPO_ROOT, 'entry/src/main/ets');
  const files = walkEtsFiles(mainRoot);
  assert.ok(files.length > 50);
  for (const file of files) {
    const relative = path.relative(mainRoot, file).split(path.sep).join('/');
    if (relative.startsWith('service/mock/')) {
      continue;
    }
    const text = fs.readFileSync(file, 'utf8');
    assert.ok(!/from\s+['"][^'"]*(?:Mock|ohosTest|service\/mock)/.test(text),
      relative + ' imports a Mock/ohosTest module');
  }
  for (const directory of ['app', 'pages', 'entryability']) {
    const root = path.join(mainRoot, directory);
    for (const file of walkEtsFiles(root)) {
      const text = fs.readFileSync(file, 'utf8');
      assert.ok(!/DEV-ONLY|DEV_ONLY/.test(text),
        path.relative(mainRoot, file) + ' contains a development-only branch');
    }
  }
});

test('T17_shellUsesApi14CompatibleEllipseFill', () => {
  for (const relative of ['entry/src/main/ets/pages/MainShell.ets',
    'entry/src/main/ets/pages/ShellBackdrop.ets']) {
    const text = source(relative);
    assert.ok(!text.includes('Circle()'), relative + ' must not use Circle.fill');
    assert.ok(text.includes('Ellipse()'), relative + ' must use Ellipse.fill');
  }
});

test('T17_entryAbilityAppliesImmersiveWindowLayout', () => {
  const ability = source('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.ok(ability.includes('applyImmersiveWindow'));
  assert.ok(ability.includes('setWindowLayoutFullScreen(true)'));
  assert.ok(ability.includes('setWindowSystemBarProperties'));
  const backdrop = source('entry/src/main/ets/pages/ShellBackdrop.ets');
  assert.ok(backdrop.includes('expandSafeArea([SafeAreaType.SYSTEM]'));
});

test('T17_indexExitUsesNonDeprecatedHostContext', () => {
  const index = source('entry/src/main/ets/pages/Index.ets');
  assert.ok(index.includes('this.getUIContext().getHostContext()'));
  assert.ok(!index.includes('getContext(this)'));
});

test('T17_onboardingServiceCreatesFamilyProfileThenSwitches', async () => {
  const calls = [];
  const families = new FakeOnboardingFamilyService(calls);
  const auth = new FakeOnboardingAuthService(calls);
  const service = new OnboardingService(families, auth);
  await service.createFamily('Home', 'Owner', 'password1');
  assert.deepEqual(calls, [
    'families.createFamily',
    'auth.createProfile',
    'families.switchFamily'
  ]);
  assert.equal(families.switchedTo, 'family-created');
  assert.equal(auth.created.memberId, 'member-owner');
  assert.equal(auth.created.displayName, 'Owner');
  assert.equal(auth.created.familyId, 'family-created');
});

test('T17_onboardingServiceJoinIsTwoStepAndDisposesSession', async () => {
  const calls = [];
  const families = new FakeOnboardingFamilyService(calls);
  const auth = new FakeOnboardingAuthService(calls);
  const service = new OnboardingService(families, auth);
  const requestText = await service.startJoin('Member');
  assert.equal(requestText, 'YCR1.fake-request');
  assert.deepEqual(calls, ['families.createJoinSession', 'join.start']);
  await service.completeJoin('YCI1.container', '123456', 'Member', 'password1');
  assert.deepEqual(calls, [
    'families.createJoinSession',
    'join.start',
    'join.submitInvitation',
    'auth.createProfile',
    'families.switchFamily',
    'join.markProfileBound',
    'join.cancel',
    'join.dispose'
  ]);
  assert.equal(auth.created.familyId, 'family-joined');
  assert.equal(auth.created.memberId, 'member-joined');
});

test('T17_onboardingServiceProfileConflictOnlyIdempotentForSameMember', async () => {
  const calls = [];
  const families = new FakeOnboardingFamilyService(calls);
  const auth = new FakeOnboardingAuthService(calls);
  const service = new OnboardingService(families, auth);

  auth.failProfileCreate = AppErrors.of('AUTH_PROFILE_EXISTS', []);
  auth.profiles = [{ memberId: 'member-joined' }];
  await service.startJoin('Member');
  await service.completeJoin('YCI1.container', '', 'Member', 'password1');
  assert.equal(families.switchedTo, 'family-joined');

  auth.profiles = [{ memberId: 'member-other' }];
  await service.startJoin('Member');
  await assert.rejects(service.completeJoin('YCI1.container', '', 'Member', 'password1'),
    (error) => error.code === 'AUTH_PROFILE_EXISTS');
});
