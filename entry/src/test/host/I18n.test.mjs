/*
 * YaoCore C-14 I18nService host tests.
 * Producer: agent:implementation-engineer | Task: T-10 / wp-031-i18n
 * Contract: DES-B §7.1-§7.5, I18N-DESIGN §2-§7; D-019 host layer
 *
 * PUBLIC TEST DATA ONLY. The platform adapters (RawfileI18nLoader,
 * OhosLocaleApplier) are COMPILED_ONLY and are not imported here. These tests
 * exercise locale resolution, fallback, interpolation, plurals, observers,
 * rollback, key builders, production resource parity and the Python checker.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

import { ErrorCatalog } from '../../main/ets/common/types/AppError.ets';
import { NameValue } from '../../main/ets/common/types/NameValue.ets';
import { StorageConstants } from '../../main/ets/common/constants/StorageConstants.ets';
import { DeviceType } from '../../main/ets/common/constants/DeviceConstants.ets';
import { InvitationStatus, InviteMode, MemberRole, MemberStatus } from '../../main/ets/model/FamilyModels.ets';
import { TransportProfile } from '../../main/ets/model/DeviceTypes.ets';
import { I18nBundleCodec } from '../../main/ets/service/i18n/I18nBundleCodec.ets';
import {
  I18nKey,
  I18nParams,
  LocaleMode,
  SupportedLocale,
} from '../../main/ets/service/i18n/I18nModels.ets';
import { I18nService } from '../../main/ets/service/i18n/I18nService.ets';
import { I18nKeys } from '../../main/ets/service/i18n/I18nKeys.ets';
import { ErrorI18nMapper } from '../../main/ets/service/i18n/ErrorI18nMapper.ets';
import {
  FakeI18nLoader,
  FakeLocaleApplier,
  InMemoryI18nPreferences,
  RecordingLogger,
} from '../i18n/I18nFakes.ets';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(HERE, '../../../..');
const CHECKER = path.join(REPO_ROOT, 'entry/src/test/i18n/check_i18n.py');
const RAW_DIR = path.join(REPO_ROOT, 'entry/src/main/resources/rawfile/i18n');
const STRING_DIR = path.join(REPO_ROOT, 'entry/src/main/resources');

const ZH = Object.freeze({
  common: {
    ok: '确定',
    greet: '你好，{name}！',
    multi: '{first} + {last}',
    echo: '值 {value}',
  },
  only: { base: '仅基准' },
  device: {
    count: '{count} 个设备',
    onlyOne: '{count} 个仅一个',
  },
});
const EN = Object.freeze({
  common: {
    ok: 'OK',
    greet: 'Hello, {name}!',
    multi: '{first} + {last}',
    echo: 'Value {value}',
  },
  only: { current: 'Current only' },
  device: {
    count_one: '{count} device',
    count_other: '{count} devices',
    onlyOne_one: '{count} only-one',
  },
});

const bundle = (locale, data) => I18nBundleCodec.parse(locale, JSON.stringify(data));
const zhBundle = () => bundle(SupportedLocale.ZH_CN, ZH);
const enBundle = () => bundle(SupportedLocale.EN_US, EN);

function makeService(options = {}) {
  const loader = new FakeI18nLoader();
  loader.put(zhBundle());
  loader.put(enBundle());
  const applier = new FakeLocaleApplier();
  applier.systemLocale = options.systemLocale ?? 'zh-Hans-CN';
  applier.failSystemRead = options.failSystemRead ?? false;
  applier.failApply = options.failApply ?? false;
  const prefs = new InMemoryI18nPreferences();
  if (options.preferredMode !== undefined) {
    prefs.seed(StorageConstants.PREF_LOCALE_MODE, options.preferredMode);
  }
  prefs.failGet = options.failGet ?? false;
  prefs.failPut = options.failPut ?? false;
  const logger = new RecordingLogger();
  const service = new I18nService(loader, applier, prefs, logger);
  return { service, loader, applier, prefs, logger };
}

const counts = (count) => I18nParams.countOf(count, [new NameValue('count', String(count))]);

test('T10_C14_t_beforeInitialize_returnsKeyAndNeverThrows', () => {
  const { service } = makeService();
  assert.equal(service.t('common.ok'), 'common.ok');
  assert.equal(service.t('missing.deep.key'), 'missing.deep.key');
  assert.deepEqual(service.getMissingKeys(), []);
});

test('T10_C14_autoResolution_zh_en_other_and_readFailure', async () => {
  for (const [system, expected] of [
    ['zh-Hans-CN', SupportedLocale.ZH_CN],
    ['zh-CN', SupportedLocale.ZH_CN],
    ['en-GB', SupportedLocale.EN_US],
    ['en-US', SupportedLocale.EN_US],
    ['fr-FR', SupportedLocale.ZH_CN],
    ['', SupportedLocale.ZH_CN],
  ]) {
    const context = makeService({ systemLocale: system });
    const result = await context.service.initialize();
    assert.equal(result.loaded, true);
    assert.equal(context.service.getLocale(), expected, `system=${system}`);
    assert.equal(context.service.getLocaleMode(), LocaleMode.AUTO);
    assert.equal(context.service.getSystemLocale(), system);
  }

  const failed = makeService({ failSystemRead: true });
  await failed.service.initialize();
  assert.equal(failed.service.getLocale(), SupportedLocale.ZH_CN);
  assert.equal(failed.service.getSystemLocale(), '');
  assert.ok(failed.logger.warnMessages.includes('I18N_SYSTEM_LOCALE_READ_FAILED'));
});

test('T10_C14_explicitPreference_loadsWithoutSystemRead', async () => {
  const { service, applier } = makeService({ preferredMode: LocaleMode.EN_US, systemLocale: 'zh-CN' });
  const result = await service.initialize();
  assert.equal(result.loaded, true);
  assert.equal(service.getLocaleMode(), LocaleMode.EN_US);
  assert.equal(service.getLocale(), SupportedLocale.EN_US);
  assert.equal(service.t('common.ok'), 'OK');
  assert.equal(service.getSystemLocale(), '');
  assert.deepEqual(applier.applied, [SupportedLocale.EN_US]);
});

test('T10_C14_invalidPreference_fallsBackToAutoWithWarning', async () => {
  const { service, logger } = makeService({ preferredMode: 'fr-FR', systemLocale: 'en-GB' });
  await service.initialize();
  assert.equal(service.getLocaleMode(), LocaleMode.AUTO);
  assert.equal(service.getLocale(), SupportedLocale.EN_US);
  assert.ok(logger.warnMessages.includes('I18N_LOCALE_UNSUPPORTED'));
});

test('T10_C14_fallbackChain_current_base_key_and_missingDiagnostics', async () => {
  const { service, logger } = makeService({ systemLocale: 'en-GB' });
  await service.initialize();
  assert.equal(service.t('only.base'), '仅基准');
  assert.deepEqual(service.getMissingKeys(), ['only.base']);
  assert.equal(service.t('missing.key'), 'missing.key');
  assert.deepEqual(service.getMissingKeys(), ['only.base']);
  assert.ok(logger.debugMessages.includes('I18N_MISSING_KEY'));
});

test('T10_C14_interpolation_hit_missing_and_onePass', async () => {
  const { service, logger } = makeService({ systemLocale: 'en-GB' });
  await service.initialize();
  assert.equal(service.t('common.greet', I18nParams.of([new NameValue('name', 'Yao')])), 'Hello, Yao!');
  assert.equal(service.t('common.multi', I18nParams.of([
    new NameValue('first', 'A'),
    new NameValue('last', 'B'),
  ])), 'A + B');
  assert.equal(service.t('common.greet'), 'Hello, {name}!');
  assert.ok(logger.warnMessages.includes('I18N_MISSING_PARAM'));
  // Parameter values are inserted verbatim; braces inside a value are not re-expanded.
  assert.equal(service.t('common.echo', I18nParams.of([new NameValue('value', '{name}')])),
    'Value {name}');
});

test('T10_C14_pluralVariants_and_missingVariantFallback', async () => {
  const { service } = makeService({ systemLocale: 'en-GB' });
  await service.initialize();
  assert.equal(service.t('device.count', counts(1)), '1 device');
  assert.equal(service.t('device.count', I18nParams.countOf(2)), '2 devices');
  assert.equal(service.t('device.count', counts(0)), '0 devices');
  assert.equal(service.t('device.count', counts(2)), '2 devices');
  // English `onlyOne` has `_one` but no `_other`; count=2 falls back to zh base.
  assert.equal(service.t('device.onlyOne', counts(2)), '2 个仅一个');
  assert.ok(service.getMissingKeys().includes('device.onlyOne'));

  const zh = makeService({ systemLocale: 'zh-CN' });
  await zh.service.initialize();
  assert.equal(zh.service.t('device.count', counts(2)), '2 个设备');
  assert.deepEqual(zh.service.getMissingKeys(), []);
});

test('T10_C14_setLocaleMode_persistsReloadsAndNotifies', async () => {
  const { service, prefs, applier } = makeService({ systemLocale: 'zh-CN' });
  await service.initialize();
  const events = [];
  service.onLocaleChanged((event) => events.push(event));
  await service.setLocaleMode(LocaleMode.EN_US);
  assert.equal(service.getLocale(), SupportedLocale.EN_US);
  assert.equal(service.getLocaleMode(), LocaleMode.EN_US);
  assert.equal(service.t('common.ok'), 'OK');
  assert.equal(prefs.peek(StorageConstants.PREF_LOCALE_MODE), LocaleMode.EN_US);
  assert.equal(events.length, 1);
  assert.equal(events[0].previous, SupportedLocale.ZH_CN);
  assert.equal(events[0].current, SupportedLocale.EN_US);
  assert.equal(events[0].mode, LocaleMode.EN_US);
  assert.equal(events[0].platformApplied, true);
  assert.equal(events[0].revision, 1);
  assert.ok(applier.applied.includes(SupportedLocale.EN_US));
});

test('T10_C14_applyFailure_switchesRawfileButReportsPlatformFalse', async () => {
  const { service, logger } = makeService({ systemLocale: 'en-GB', failApply: true });
  await service.initialize();
  assert.equal(service.t('common.ok'), 'OK');
  const events = [];
  service.onLocaleChanged((event) => events.push(event));
  await service.setLocaleMode(LocaleMode.ZH_CN);
  assert.equal(service.getLocale(), SupportedLocale.ZH_CN);
  assert.equal(service.t('common.ok'), '确定');
  assert.equal(events.length, 1);
  assert.equal(events[0].platformApplied, false);
  assert.ok(logger.warnMessages.includes('I18N_PLATFORM_LOCALE_FAILED'));
});

test('T10_C14_setLocaleMode_loadFailure_rollsBackLocaleAndPreference', async () => {
  const { service, loader, prefs } = makeService({ systemLocale: 'zh-CN' });
  await service.initialize();
  loader.fail(SupportedLocale.EN_US);
  await assert.rejects(service.setLocaleMode(LocaleMode.EN_US), (error) => {
    assert.equal(error.code, 'I18N_RESOURCE_LOAD_FAILED');
    return true;
  });
  assert.equal(service.getLocale(), SupportedLocale.ZH_CN);
  assert.equal(service.getLocaleMode(), LocaleMode.AUTO);
  assert.equal(service.t('common.ok'), '确定');
  assert.equal(prefs.peek(StorageConstants.PREF_LOCALE_MODE), LocaleMode.AUTO);
});

test('T10_C14_setLocaleMode_preferencesFailure_propagatesStorageError', async () => {
  const { service, prefs } = makeService({ systemLocale: 'zh-CN' });
  await service.initialize();
  prefs.failPut = true;
  await assert.rejects(service.setLocaleMode(LocaleMode.EN_US), (error) => {
    assert.equal(error.code, 'STORAGE_PREFERENCES_ERROR');
    return true;
  });
  assert.equal(service.getLocale(), SupportedLocale.ZH_CN);
});

test('T10_C14_reload_autoReResolvesSystemLocale_andNotifies', async () => {
  const { service, applier } = makeService({ systemLocale: 'zh-CN' });
  await service.initialize();
  const events = [];
  service.onLocaleChanged((event) => events.push(event));
  applier.systemLocale = 'en-GB';
  const result = await service.reload();
  assert.equal(result.loaded, true);
  assert.equal(service.getLocale(), SupportedLocale.EN_US);
  assert.equal(service.t('common.ok'), 'OK');
  assert.equal(events.length, 1);
  assert.equal(events[0].current, SupportedLocale.EN_US);
});

test('T10_C14_listener_unsubscribe_and_isolation', async () => {
  const { service } = makeService({ systemLocale: 'zh-CN' });
  await service.initialize();
  let calls = 0;
  const unsubscribe = service.onLocaleChanged(() => {
    calls += 1;
  });
  service.onLocaleChanged(() => {
    throw new Error('listener boom');
  });
  await service.setLocaleMode(LocaleMode.EN_US);
  assert.equal(calls, 1, 'a throwing listener must not stop later listeners');
  unsubscribe();
  await service.setLocaleMode(LocaleMode.ZH_CN);
  assert.equal(calls, 1);
});

test('T10_C14_dispose_returnsKeysAndDropsListeners', async () => {
  const { service } = makeService({ systemLocale: 'zh-CN' });
  await service.initialize();
  let calls = 0;
  service.onLocaleChanged(() => {
    calls += 1;
  });
  service.dispose();
  assert.equal(service.t('common.ok'), 'common.ok');
  await service.setLocaleMode(LocaleMode.EN_US);
  assert.equal(calls, 0);
});

test('T10_C14_has_and_tKey', async () => {
  const { service } = makeService({ systemLocale: 'en-GB' });
  await service.initialize();
  assert.equal(service.has('only.base'), true);
  assert.equal(service.has('only.current'), true);
  assert.equal(service.has('device.count'), true);
  assert.equal(service.has('nope'), false);
  assert.equal(service.tKey(new I18nKey('common.greet', [new NameValue('name', 'Yao')])), 'Hello, Yao!');
});

test('T10_C14_bundleCodec_rejectsDuplicateEmptyAndMalformedBundles', () => {
  const parse = (text) => I18nBundleCodec.parse(SupportedLocale.ZH_CN, text);
  assert.throws(() => parse('{"common":{"ok":"x","ok":"y"}}'), (error) => error.code === 'I18N_BUNDLE_INVALID');
  assert.throws(() => parse('{"common":{"ok":""}}'), (error) => error.code === 'I18N_BUNDLE_INVALID');
  assert.throws(() => parse('{"common":{"ok":"TODO"}}'), (error) => error.code === 'I18N_BUNDLE_INVALID');
  assert.throws(() => parse('{"common":{"ok":"Hello {name"}}'), (error) => error.code === 'I18N_BUNDLE_INVALID');
  assert.throws(() => parse('{"a":{"b":{"c":{"d":{"e":"x"}}}}}'), (error) => error.code === 'I18N_BUNDLE_INVALID');
  assert.throws(() => parse('{"common":{"ok":1}}'), (error) => error.code === 'I18N_BUNDLE_INVALID');
  const parsed = parse('{"common":{"ok":"确定"}}');
  assert.equal(parsed.entries.length, 1);
  assert.equal(parsed.entries[0].name, 'common.ok');
  assert.match(parsed.revision, /^zh-CN-[0-9a-f]+-1$/);
  const second = parse('{"common":{"ok":"确定"}}');
  assert.equal(parsed.revision, second.revision);
  const changed = parse('{"common":{"ok":"好"}}');
  assert.notEqual(parsed.revision, changed.revision);
});

test('T10_C14_keyBuilders', () => {
  assert.equal(I18nKeys.appError('HTTP_404'), 'errors.app.http_error');
  assert.equal(I18nKeys.appError('INVITE_EXPIRED'), 'errors.app.invite_expired');
  assert.equal(I18nKeys.appError('SCENE_RUN_IN_PROGRESS'), 'errors.scene.run_in_progress');
  assert.equal(I18nKeys.gatewayError('bad_signature', 1004).key, 'errors.gateway.bad_signature');
  assert.deepEqual(I18nKeys.gatewayError('unknown_1009', 1009).params.map((item) => item.value), ['1009']);
  assert.equal(I18nKeys.stateSource('device.feedback', true).key, 'stateSource.device_feedback');
  assert.equal(I18nKeys.stateSource('vendor.custom', false).key, 'stateSource.unknown');
  assert.equal(I18nKeys.acMode('COOL', true).key, 'ac.mode.cool');
  assert.equal(I18nKeys.acMode('TURBO', false).key, 'ac.mode.unknown');
  assert.equal(I18nKeys.provisioningError('PROVISIONING_POP_INVALID'), 'provisioning.error.pop_invalid');
  assert.equal(I18nKeys.cloudError('CLOUD_TOKEN_EXPIRED'), 'errors.cloud.token_expired');
  assert.equal(I18nKeys.memberRole(MemberRole.ADMIN), 'member.role.admin');
  assert.equal(I18nKeys.memberStatus(MemberStatus.INVITED), 'member.status.invited');
  assert.equal(I18nKeys.inviteMode(InviteMode.CODE_KEK), 'invite.mode.code_kek');
  assert.equal(I18nKeys.invitationStatus(InvitationStatus.PENDING), 'invite.status.pending');
  assert.equal(I18nKeys.deviceType(DeviceType.AC), 'device.type.ac');
  assert.equal(I18nKeys.deviceType(undefined), 'device.type.unknown');
  assert.equal(I18nKeys.securityProfile(TransportProfile.P_HMAC).key, 'gateway.security.hmac_only');
  assert.equal(I18nKeys.securityProfile(TransportProfile.P_BLOCKED, 'pin_mismatch').key,
    'gateway.security.pin_mismatch');
});

test('T10_C14_errorMapper', () => {
  assert.equal(ErrorI18nMapper.gatewayKey(1004).key, 'errors.gateway.bad_signature');
  assert.equal(ErrorI18nMapper.gatewayKey(1006, 'unsupported_action').key,
    'errors.gateway.unsupported_action');
  assert.equal(ErrorI18nMapper.gatewayKey(1009).key, 'errors.gateway.unknown');
  assert.deepEqual(ErrorI18nMapper.gatewayKey(1009).params.map((item) => item.value), ['1009']);
  assert.equal(ErrorI18nMapper.stateSourceKey('sensor.physical', true).key, 'stateSource.sensor_physical');
  assert.equal(ErrorI18nMapper.acModeKey('ECO', true).key, 'ac.mode.eco');
  assert.equal(ErrorI18nMapper.securityProfileKey(TransportProfile.P_TLS_PIN).key,
    'gateway.security.tls_pinned');
});

const CATALOG_CODES = [
  'ACK_CORRELATION_MISMATCH', 'ACK_PROTOCOL_VIOLATION', 'ACK_STATE_MISMATCH', 'ASSET_NOT_FOUND',
  'AUTH_PROFILE_NOT_FOUND', 'AUTH_RBAC_DENIED', 'CLOUD_ENDPOINT_INVALID', 'CLOUD_INVENTORY_UNSUPPORTED',
  'CLOUD_SHADOW_INVALID', 'CONFIGURATION_ERROR', 'CRYPTO_INVALID_KEY', 'CRYPTO_OPERATION_FAILED',
  'CRYPTO_STREAM_BROKEN', 'CRYPTO_TAG_MISMATCH', 'CRYPTO_UNAVAILABLE', 'DEVICE_DISMISSED',
  'DEVICE_NAME_INVALID', 'DEVICE_NOT_FOUND', 'DISCOVERY_INVALID_RESPONSE', 'GATEWAY_ID_MISMATCH',
  'GATEWAY_NOT_BOUND', 'GATEWAY_PROFILE_BLOCKED', 'INTERNAL_ERROR', 'INVITE_EXPIRED', 'INVITE_INVALID',
  'INVITE_JOIN_REQUEST_INVALID', 'INVITE_MAX_USES', 'INVITE_RECEIPT_INVALID', 'INVITE_REVOKED',
  'PROTOCOL_BODY_TOO_LARGE', 'PROTOCOL_DUPLICATE_KEY', 'PROTOCOL_INVALID_IDENTIFIER',
  'PROTOCOL_INVALID_JSON', 'PROTOCOL_INVALID_TIMESTAMP', 'PROTOCOL_INVALID_TYPE',
  'PROTOCOL_MISSING_FIELD', 'PROTOCOL_UNSUPPORTED_VERSION', 'PROTOCOL_VALUE_OUT_OF_RANGE',
  'PROVISIONING_CREDENTIAL_MISSING', 'PROVISIONING_IDENTITY_INVALID', 'PROVISIONING_SECRET_DRAFT_EXPIRED',
  'RESPONSE_AUTH_FAILED', 'RESPONSE_CORRELATION_MISMATCH', 'ROOM_DELETE_NOT_CONFIRMED',
  'ROOM_NAME_INVALID', 'ROOM_NOT_FOUND', 'SCENE_CANCELLED', 'SCENE_DISABLED', 'SCENE_EMPTY',
  'SCENE_NAME_INVALID', 'SCENE_NOT_FOUND', 'SCENE_PREFLIGHT_FAILED', 'SCENE_REFERENCE_INVALID',
  'SCENE_RUN_IN_PROGRESS', 'SCENE_STEP_FAILED', 'SECRET_ALIAS_INVALID', 'SECRET_DESTROYED',
  'SECRET_ENCODING_INVALID', 'SIGNATURE_INVALID', 'STORAGE_MIGRATION_FAILED', 'STORAGE_NOT_INITIALIZED',
  'STORAGE_PREFERENCES_ERROR', 'STORAGE_RDB_ERROR', 'TLS_PIN_CONFIG_INVALID', 'TLS_PROFILE_INCONSISTENT',
  'CLOUD_COMPLETION_TIMEOUT', 'CLOUD_COMPLETION_UNSUPPORTED', 'CLOUD_TOKEN_EXPIRED', 'CLOUD_TOKEN_INVALID',
  'CLOUD_RATE_LIMITED', 'CLOUD_REQUEST_FAILED', 'CLOUD_RESPONSE_INVALID', 'CLOUD_SEQUENCE_UNAVAILABLE',
  'CLOUD_SERVICE_UNAVAILABLE', 'NONCE_REUSED', 'TIMESTAMP_OUT_OF_WINDOW', 'LOCAL_REQUEST_FAILED',
  'DEV_SIMULATOR_REJECTED', 'GATEWAY_UNREACHABLE', 'GATEWAY_TIMEOUT', 'DISCOVERY_NO_CANDIDATES',
  'DISCOVERY_TRANSPORT_UNAVAILABLE', 'PROVISIONING_AUTH_ERROR', 'PROVISIONING_BLUETOOTH_OFF',
  'PROVISIONING_BOARD_LED_UNCONFIRMED', 'PROVISIONING_BINDING_PROBE_FAILED', 'PROVISIONING_CANCELLED',
  'PROVISIONING_CONNECT_FAILED', 'PROVISIONING_DEVICE_NOT_FOUND', 'PROVISIONING_DONE_REJECTED',
  'PROVISIONING_GATT_BUSY', 'PROVISIONING_POP_INVALID', 'PROVISIONING_SECURITY_HANDSHAKE_FAILED',
  'PROVISIONING_WIFI_AUTH_ERROR', 'PROVISIONING_WIFI_NETWORK_NOT_FOUND', 'PROVISIONING_WIFI_SCAN_FAILED',
  'PROVISIONING_WIFI_TIMEOUT', 'I18N_LOCALE_UNSUPPORTED', 'I18N_PLATFORM_LOCALE_FAILED',
  'I18N_RESOURCE_LOAD_FAILED',
];

function flatten(node, prefix = '', out = {}) {
  for (const [key, value] of Object.entries(node)) {
    const next = prefix.length === 0 ? key : `${prefix}.${key}`;
    if (value !== null && typeof value === 'object') {
      flatten(value, next, out);
    } else {
      out[next] = value;
    }
  }
  return out;
}

const normalizePlural = (key) => key.replace(/_(one|other)$/, '');

test('T10_C14_productionResources_parityAndEveryCatalogKeyExists', () => {
  const zh = flatten(JSON.parse(fs.readFileSync(path.join(RAW_DIR, 'zh-CN.json'), 'utf8')));
  const en = flatten(JSON.parse(fs.readFileSync(path.join(RAW_DIR, 'en-US.json'), 'utf8')));
  const zhNorm = new Set(Object.keys(zh).map(normalizePlural));
  const enNorm = new Set(Object.keys(en).map(normalizePlural));
  assert.deepEqual([...zhNorm].filter((key) => !enNorm.has(key)), []);
  assert.deepEqual([...enNorm].filter((key) => !zhNorm.has(key)), []);
  assert.ok(zhNorm.size >= 180, `expected a substantive rawfile key set, got ${zhNorm.size}`);
  for (const code of CATALOG_CODES) {
    const key = ErrorCatalog.resolve(code).i18nKey;
    assert.ok(zhNorm.has(key), `missing rawfile key for ${code}: ${key}`);
    assert.ok(enNorm.has(key), `missing en-US rawfile key for ${code}: ${key}`);
  }
  assert.ok(zhNorm.has(I18nKeys.appError('SCENE_RUN_IN_PROGRESS')));
  assert.ok(zhNorm.has('errors.app.scene_run_in_progress'));

  const baseStrings = JSON.parse(fs.readFileSync(path.join(STRING_DIR, 'base/element/string.json'), 'utf8'));
  const enStrings = JSON.parse(fs.readFileSync(path.join(STRING_DIR, 'en_US/element/string.json'), 'utf8'));
  const baseKeys = baseStrings.string.map((entry) => entry.name).sort();
  const enKeys = enStrings.string.map((entry) => entry.name).sort();
  assert.deepEqual(baseKeys, enKeys);
  assert.ok(baseKeys.length >= 25);
});

test('T10_C14_checker_goodFixturePasses', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'yaocore-i18n-good-'));
  try {
    const report = path.join(tmp, 'report.json');
    const result = spawnSync('python3', [
      CHECKER,
      '--root', path.join(REPO_ROOT, 'entry/src/test/i18n/fixtures/good'),
      '--report', report,
      '--allowlist', path.join(tmp, 'allowlist.json'),
      '--strict-ui',
    ], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    const parsed = JSON.parse(fs.readFileSync(report, 'utf8'));
    assert.equal(parsed.summary.blockingFailures, 0);
    assert.ok(parsed.checks.every((check) => check.status === 'PASS'));
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test('T10_C14_checker_badFixtureBlocksEveryDesignedCheck', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'yaocore-i18n-bad-'));
  try {
    const report = path.join(tmp, 'report.json');
    const result = spawnSync('python3', [
      CHECKER,
      '--root', path.join(REPO_ROOT, 'entry/src/test/i18n/fixtures/bad'),
      '--report', report,
      '--allowlist', path.join(tmp, 'allowlist.json'),
      '--strict-ui',
    ], { encoding: 'utf8' });
    assert.equal(result.status, 1, result.stdout + result.stderr);
    const parsed = JSON.parse(fs.readFileSync(report, 'utf8'));
    const statuses = Object.fromEntries(parsed.checks.map((check) => [check.id, check.status]));
    for (const id of ['CHK-01', 'CHK-02', 'CHK-03', 'CHK-04', 'CHK-06', 'CHK-07', 'CHK-08', 'CHK-09']) {
      assert.equal(statuses[id], 'FAIL', `${id} should block the bad fixture`);
    }
    assert.equal(statuses['CHK-05'], 'PASS', 'CHK-05 is warning-only');
    assert.ok(parsed.summary.blockingFailures >= 8);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test('T10_C14_baseBundleFailure_stillServesCurrentLocaleAndReturnsKeyForBaseOnly', async () => {
  const { service, loader } = makeService({ systemLocale: 'en-GB' });
  loader.fail(SupportedLocale.ZH_CN);
  const result = await service.initialize();
  assert.equal(result.loaded, true);
  assert.ok(result.error);
  assert.equal(result.error.code, 'I18N_RESOURCE_LOAD_FAILED');
  assert.equal(service.t('common.ok'), 'OK');
  assert.equal(service.t('only.base'), 'only.base');
});

test('T10_C14_bothBundlesMissing_returnsLoadedFalseAndKeys', async () => {
  const { service, loader } = makeService({ systemLocale: 'en-GB' });
  loader.fail(SupportedLocale.ZH_CN);
  loader.fail(SupportedLocale.EN_US);
  const result = await service.initialize();
  assert.equal(result.loaded, false);
  assert.ok(result.error);
  assert.equal(service.t('common.ok'), 'common.ok');
});

test('T10_C14_preferencesReadFailure_stillInitializes', async () => {
  const { service, logger } = makeService({ systemLocale: 'en-GB', failGet: true });
  const result = await service.initialize();
  assert.equal(result.loaded, true);
  assert.equal(service.getLocale(), SupportedLocale.EN_US);
  assert.ok(logger.warnMessages.includes('STORAGE_PREFERENCES_ERROR'));
});
