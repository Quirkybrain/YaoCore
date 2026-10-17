/*
 * YaoCore T-18 UI/pages host tests (D-019).
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §13.4, §14.4, §15.4, §16.4; CQG-T17 R2-02/R2-03/R2-06
 *
 * The host runner cannot render ArkUI. These tests cover the pure selectors
 * used by cards/pages, route/parameter guards, AppContext active-family
 * observability and the onboarding create-family cleanup/idempotency seam.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { UiMapping, LIGHT_COLOR_PRESETS } from '../../main/ets/components/support/UiMapping.ets';
import { CardVisualState } from '../../main/ets/common/theme/AppEnums.ets';
import {
  ControlPhase,
  ControlUiState,
  DeviceFilter,
  LoadPhase
} from '../../main/ets/viewmodel/core/ViewModelCore.ets';
import { DoorLinkConfig, DoorLinkMode, DoorStage, DoorLockState } from '../../main/ets/viewmodel/core/DoorConfirmationTracker.ets';
import { SceneRunState, SceneStepState } from '../../main/ets/repository/DomainModels.ets';
import { FamilyJoinPhase } from '../../main/ets/service/family/FamilyModels.ets';
import { InviteMode, MemberRole, Room } from '../../main/ets/model/FamilyModels.ets';
import { DeviceKey } from '../../main/ets/model/DeviceKey.ets';
import { AppRoute, AppRouteParams, AppRouteValidation } from '../../main/ets/app/NavigationService.ets';
import { AppContext, SessionGateState } from '../../main/ets/app/AppContext.ets';
import { OnboardingService } from '../../main/ets/app/OnboardingService.ets';
import { AppErrors } from '../../main/ets/common/types/AppError.ets';
import {
  GATEWAY_ID,
  ROOM_A,
  ROOM_B,
  UPDATED,
  record
} from './viewmodel-helpers.mjs';

function control(key, phase, confirmed, optimistic) {
  return new ControlUiState(key, 'SET_BRIGHTNESS', phase, 1, confirmed, optimistic);
}

test('T18_cardVisualState_mapsControlPhaseAndOverrides', () => {
  const light = record({ brightness: 10 });
  const key = light.state.key;
  assert.equal(UiMapping.visualState(light, control(key, ControlPhase.IDLE, 10)),
    CardVisualState.IDLE);
  assert.equal(UiMapping.visualState(light, control(key, ControlPhase.PENDING, 10, 20)),
    CardVisualState.PENDING);
  assert.equal(UiMapping.visualState(light, control(key, ControlPhase.COMMITTED, 20)),
    CardVisualState.COMMITTED);
  assert.equal(UiMapping.visualState(light, control(key, ControlPhase.REVERT, 10)),
    CardVisualState.REVERT);
  const offline = record({ isOnline: false });
  assert.equal(UiMapping.visualState(offline, control(offline.state.key, ControlPhase.PENDING, 0)),
    CardVisualState.OFFLINE);
  const disabled = record({ isEnabled: false });
  assert.equal(UiMapping.visualState(disabled, undefined), CardVisualState.DISABLED);
  assert.equal(UiMapping.visualState(undefined, undefined), CardVisualState.DISABLED);
});

test('T18_cardVisualState_readOnlyWhenUnsupportedOrUnassigned', () => {
  const unsupported = record({ isSupported: false, deviceType: 'switch' });
  assert.equal(UiMapping.visualState(unsupported, undefined), CardVisualState.READ_ONLY);
  const unassigned = record({ isUnassigned: true, roomId: '' });
  assert.equal(UiMapping.visualState(unassigned, undefined), CardVisualState.DISABLED);
});

test('T18_brightnessAndTemperatureFollowPendingValueThenConfirmed', () => {
  const light = record({ brightness: 30 });
  const key = light.state.key;
  assert.equal(UiMapping.brightnessValue(light,
    control(key, ControlPhase.PENDING, 30, 75)), 75);
  assert.equal(UiMapping.brightnessValue(light,
    control(key, ControlPhase.COMMITTED, 75)), 75);
  assert.equal(UiMapping.brightnessValue(light, undefined), 30);
  assert.equal(UiMapping.brightnessValue(light,
    control(key, ControlPhase.PENDING, 0, 250)), 100);
  const ac = record({ deviceType: 'ac', targetTemperature: 22 });
  assert.equal(UiMapping.temperatureValue(ac,
    control(ac.state.key, ControlPhase.PENDING, 22, 26)), 26);
  assert.equal(UiMapping.temperatureValue(ac, undefined), 22);
});

test('T18_roomJoinAndCountsUseRoomEntitiesNotHints', () => {
  const rooms = [
    new Room(ROOM_A, 'family-1', 'Living', 0, UPDATED, UPDATED),
    new Room(ROOM_B, 'family-1', 'Bedroom', 1, UPDATED, UPDATED)
  ];
  const lamp = record({ deviceId: 'lamp-1', roomId: ROOM_A, roomNameHint: 'stale-hint' });
  assert.equal(UiMapping.roomNameFor(lamp, rooms), 'Living');
  assert.equal(UiMapping.roomNameById(ROOM_B, rooms), 'Bedroom');
  assert.equal(UiMapping.roomNameById('missing', rooms), '');
  assert.equal(UiMapping.roomDeviceCount([lamp], ROOM_A), 1);
  assert.equal(UiMapping.roomDeviceCount([lamp], ROOM_B), 0);
  assert.equal(UiMapping.unassignedCount([lamp, record({ isUnassigned: true, roomId: '' })]), 1);
});

test('T18_filtersMatchAllRoomAndUnassigned', () => {
  const lamp = record({ roomId: ROOM_A });
  assert.equal(UiMapping.filterMatches(DeviceFilter.all(), lamp), true);
  assert.equal(UiMapping.filterMatches(DeviceFilter.room(ROOM_A), lamp), true);
  assert.equal(UiMapping.filterMatches(DeviceFilter.room(ROOM_B), lamp), false);
  assert.equal(UiMapping.filterMatches(DeviceFilter.unassigned(), lamp), false);
  assert.equal(UiMapping.filterKey(DeviceFilter.room(ROOM_A)), 'room:' + ROOM_A);
});

test('T18_sceneProgressMarkersAndNoRollback', () => {
  assert.equal(UiMapping.sceneStepMarker(SceneStepState.SUCCEEDED), '✓');
  assert.equal(UiMapping.sceneStepMarker(SceneStepState.FAILED), '✗');
  assert.equal(UiMapping.sceneStepMarker(SceneStepState.SKIPPED), '–');
  assert.equal(UiMapping.sceneStepKey(SceneStepState.RUNNING), 'scene.step.running');
  assert.equal(UiMapping.sceneRunKey(SceneRunState.PARTIAL_FAILED), 'scene.partial_failed');
  const progress = {
    runId: 'run-1', sceneId: 'scene-1', state: SceneRunState.PARTIAL_FAILED,
    currentIndex: 1, steps: [1, 2, 3], executedCount: 2, succeededCount: 1
  };
  assert.equal(UiMapping.sceneNoRollback(progress, undefined), true);
  assert.equal(UiMapping.progressPercent(progress), 67);
  assert.equal(UiMapping.sceneIsRunning(SceneRunState.RUNNING), true);
  assert.equal(UiMapping.sceneNoRollback(undefined, {
    state: SceneRunState.CANCELLED, executedCount: 0, noRollbackNotice: true
  }), false);
});

test('T18_familyJoinAndInviteGuards', () => {
  assert.equal(UiMapping.joinPhaseKey(FamilyJoinPhase.MEMBER_BOUND),
    'family.join.phase.member_bound');
  assert.equal(UiMapping.joinNeedsProfile(FamilyJoinPhase.MEMBER_BOUND), true);
  assert.equal(UiMapping.joinCanSubmit(FamilyJoinPhase.JOIN_REQUEST_READY), true);
  assert.equal(UiMapping.inviteInputValid(MemberRole.MEMBER, []), true);
  assert.equal(UiMapping.inviteInputValid(MemberRole.GUEST, []), false);
  assert.equal(UiMapping.inviteInputValid(MemberRole.GUEST, [ROOM_A]), true);
  assert.equal(UiMapping.inviteInputValid(MemberRole.ADMIN, [ROOM_A]), false);
  assert.equal(UiMapping.weakInviteMode(InviteMode.CODE_KEK), true);
  assert.equal(UiMapping.inviteModeKey(InviteMode.KEY_WRAP), 'invite.mode.key_wrap');
});

test('T18_doorStagesNeverUpgradeWithoutEvidence', () => {
  assert.equal(UiMapping.doorStageKey(DoorStage.SECURED), 'door.state.secured');
  assert.equal(UiMapping.doorStageKey(DoorStage.UNVERIFIED), 'door.link.unverified');
  const door = {
    stage: DoorStage.IDLE, lockState: DoorLockState.UNKNOWN_INITIAL,
    link: DoorLinkConfig.none(), alertActive: false, revision: 0
  };
  assert.equal(UiMapping.doorNeedsLinkGuide(door), true);
  assert.equal(UiMapping.doorNeedsLinkGuide({
    stage: DoorStage.SECURED, lockState: DoorLockState.SECURED,
    link: new DoorLinkConfig(DoorLinkMode.GATEWAY_MERGED), alertActive: false, revision: 1
  }), false);
  assert.equal(UiMapping.doorAlarmKey({ alertActive: true }), 'door.alert.unconfirmed');
});

test('T18_provisioningStepAndErrorMapping', () => {
  assert.equal(UiMapping.provisioningStepKey(0), 'provisioning.step0');
  assert.equal(UiMapping.provisioningStepKey(9), 'provisioning.step5');
  assert.equal(UiMapping.provisioningStepIndex(-1), 0);
  assert.equal(UiMapping.provisioningProgressKey('SENDING_CREDENTIALS'),
    'provisioning.progress.sending_credentials');
  assert.equal(UiMapping.provisioningErrorStep('PROVISIONING_PERMISSION_DENIED'), 0);
  assert.equal(UiMapping.provisioningErrorStep('PROVISIONING_DEVICE_NOT_FOUND'), 1);
  assert.equal(UiMapping.provisioningErrorStep('PROVISIONING_POP_INVALID'), 2);
  assert.equal(UiMapping.provisioningErrorStep('PROVISIONING_WIFI_AUTH_ERROR'), 3);
  assert.equal(UiMapping.provisioningErrorStep('PROVISIONING_WIFI_TIMEOUT'), 4);
  assert.equal(UiMapping.provisioningErrorStep('PROVISIONING_CREDENTIAL_MISSING'), 4);
});

test('T18_settingsStateLocaleCloudAndSecurityKeys', () => {
  assert.equal(UiMapping.localeModeKey('AUTO'), 'settings.language.auto');
  assert.equal(UiMapping.localeModeKey('EN_US'), 'settings.language.en_us');
  assert.equal(UiMapping.cloudStateKey('TOKEN_EXPIRED'), 'cloud.state.token_expired');
  assert.equal(UiMapping.cloudStateKey(undefined), 'cloud.state.not_configured');
  assert.equal(UiMapping.cloudNeedsToken('TOKEN_INVALID'), true);
  assert.equal(UiMapping.securityProfileKey('P-HMAC', 0), 'gateway.security.hmac_only');
  assert.equal(UiMapping.securityProfileKey('P-TLS-PIN', 2), 'gateway.security.tls_pinned');
  assert.equal(UiMapping.securityProfileKey('P-BLOCKED', 0), 'gateway.security.unavailable');
  assert.equal(UiMapping.isManualAddressRejected('MANUAL_ADDRESS_NOT_BOUND'), true);
  assert.equal(UiMapping.isManualAddressRejected('STORAGE_ERROR'), false);
});

test('T18_loadStateAndColorPresets', () => {
  assert.equal(UiMapping.loadState('ERROR', true), 'ERROR');
  assert.equal(UiMapping.loadState('READY', false), 'EMPTY');
  assert.equal(UiMapping.loadState(LoadPhase.READY, true), 'READY');
  assert.ok(LIGHT_COLOR_PRESETS.length > 0);
  for (const value of LIGHT_COLOR_PRESETS) {
    assert.equal(UiMapping.isKnownColor(value), true);
  }
  assert.equal(UiMapping.isKnownColor('red'), false);
  assert.equal(UiMapping.clampNumber(Number.NaN, 0, 100), 0);
});

test('T18_routeParametersRequireDeviceIdentity', () => {
  assert.equal(AppRouteValidation.accepts(AppRoute.DEVICE_CONTROL), false);
  assert.equal(AppRouteValidation.accepts(AppRoute.DEVICE_CONTROL,
    new AppRouteParams({ gatewayId: GATEWAY_ID })), false);
  assert.equal(AppRouteValidation.accepts(AppRoute.DEVICE_CONTROL,
    new AppRouteParams({ gatewayId: GATEWAY_ID, deviceId: 'lamp-1' })), true);
  assert.equal(AppRouteValidation.accepts(AppRoute.PROVISIONING,
    new AppRouteParams({ mode: 'ROTATE_SECRET' })), true);
  assert.equal(AppRouteValidation.accepts(AppRoute.PROVISIONING,
    new AppRouteParams({ mode: 'INVALID' })), false);
});

class FakeActiveFamily {
  constructor(family) {
    this.family = family;
    this.setCalls = [];
  }
  async getActiveFamily() { return this.family; }
  async setActiveFamily(familyId) {
    this.setCalls.push(familyId);
    this.family = { familyId, familyName: 'Next' };
  }
}

class FakeAuthGate {
  constructor() { this.session = undefined; this.profiles = [{ profileId: 'p-1', displayName: 'Owner' }]; }
  async listProfiles() { return this.profiles; }
  getActiveSession() { return this.session; }
  async unlock() { this.session = {}; return this.session; }
  async lockAll() { this.session = undefined; }
}

class FakeRoot {
  constructor() {
    this.family = new FakeActiveFamily({ familyId: 'family-1', familyName: 'Home' });
    this.auth = new FakeAuthGate();
    this.i18nValue = { async reload() {}, onLocaleChanged() { return () => {}; }, t(key) { return key; } };
    this.preferences = { async getString() { return undefined; }, async flush() {} };
    this.secretDrafts = { clearAll() {} };
    this.ble = { async cancel() {} };
    this.cloud = { stopPolling() {} };
    this.onboarding = {};
    this.logger = { warn() {} };
    this.pageVms = {};
    this.initialized = false;
  }
  get i18n() { return this.i18nValue; }
  get sessionAuth() { return this.auth; }
  get activeFamily() { return this.family; }
  async initialize() { this.initialized = true; }
  isInitialized() { return this.initialized; }
  getInitializationError() { return undefined; }
}

test('T18_activeFamilyIsObservable', async () => {
  const root = new FakeRoot();
  const context = new AppContext(root);
  const seen = [];
  const unsubscribe = context.subscribeActiveFamily((familyId) => seen.push(familyId));
  await context.initialize();
  assert.equal(context.sessionGate, SessionGateState.LOCKED);
  assert.equal(context.activeFamilyId, 'family-1');
  root.family.family = { familyId: 'family-2', familyName: 'Next' };
  await context.refreshSessionGate();
  assert.equal(seen[seen.length - 1], 'family-2');
  unsubscribe();
  root.family.family = { familyId: 'family-3', familyName: 'Third' };
  await context.refreshSessionGate();
  assert.notEqual(seen[seen.length - 1], 'family-3');
});

class OnboardingFamilyService {
  constructor(failDissolve) {
    this.calls = [];
    this.failDissolve = failDissolve;
    this.family = { familyId: 'family-new', familyName: 'Home', ownerMemberId: 'member-owner' };
  }
  async createFamily() { this.calls.push('createFamily'); return this.family; }
  async switchFamily(familyId) { this.calls.push('switch:' + familyId); return { requiresUnlock: true }; }
  async dissolveFamily(familyId, memberId) {
    this.calls.push('dissolve:' + familyId + ':' + memberId);
    if (this.failDissolve) { throw AppErrors.of('INTERNAL_ERROR', []); }
  }
}

class OnboardingAuthService {
  constructor(options = {}) {
    this.calls = [];
    this.error = options.error;
    this.profiles = options.profiles === undefined ? [] : options.profiles;
  }
  async createProfile() {
    this.calls.push('createProfile');
    if (this.error !== undefined) { throw this.error; }
  }
  async listProfiles() { return this.profiles; }
}

test('T18_onboardingCreateFamilyCleansUpFailedProfile', async () => {
  const families = new OnboardingFamilyService(true);
  const auth = new OnboardingAuthService({ error: AppErrors.of('STORAGE_ERROR', []) });
  const service = new OnboardingService(families, auth);
  await assert.rejects(() => service.createFamily('Home', 'Owner', 'password1'),
    (error) => error.code === 'STORAGE_ERROR');
  assert.ok(families.calls.includes('dissolve:family-new:member-owner'));
  assert.ok(!families.calls.some((entry) => entry.startsWith('switch:')));
});

test('T18_onboardingCreateFamilyIsIdempotentForSameMember', async () => {
  const families = new OnboardingFamilyService(false);
  const auth = new OnboardingAuthService({
    error: AppErrors.of('AUTH_PROFILE_EXISTS', []),
    profiles: [{ memberId: 'member-owner' }]
  });
  const service = new OnboardingService(families, auth);
  await service.createFamily('Home', 'Owner', 'password1');
  assert.ok(!families.calls.some((entry) => entry.startsWith('dissolve:')));
  assert.ok(families.calls.includes('switch:family-new'));
});

test('T18_pagesUseExplicitPropsAndNoProvideConsume', () => {
  // Source-level guard: UI dependencies are explicit props, no global DI.
  // (Read with fs in the host runner; ArkTS pages are not importable.)
  return import('node:fs').then(({ readFileSync, readdirSync }) => {
    const root = new URL('../../main/ets/', import.meta.url);
    const files = [];
    const walk = (directory) => {
      for (const entry of readdirSync(directory, { withFileTypes: true })) {
        const child = new URL(entry.name + (entry.isDirectory() ? '/' : ''), directory);
        if (entry.isDirectory()) {
          walk(child);
        } else if (entry.name.endsWith('.ets')) {
          files.push(child);
        }
      }
    };
    walk(new URL('pages/', root));
    walk(new URL('components/', root));
    for (const file of files) {
      const text = readFileSync(file, 'utf8');
      assert.ok(!/^\s*@Provide\b/m.test(text), file.pathname);
      assert.ok(!/^\s*@Consume\b/m.test(text), file.pathname);
    }
  });
});
