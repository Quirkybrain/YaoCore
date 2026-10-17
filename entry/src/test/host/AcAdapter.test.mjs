/*
 * YaoCore C-16 AC brand adapter host tests.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §9.1-§9.4; CB §6.3; PL-08
 *
 * PUBLIC TEST DATA ONLY. Pure mapping; no device or network.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';

import { AppError } from '../../main/ets/common/types/AppError.ets';
import { DeviceAction } from '../../main/ets/common/constants/DeviceConstants.ets';
import { AcMode } from '../../main/ets/model/DeviceTypes.ets';
import { DeviceStatePatch, DeviceStatePatchInit } from '../../main/ets/model/DeviceState.ets';
import { AcAdapterFactory } from '../../main/ets/service/ac/AcAdapterFactory.ets';
import { AcVocabulary, AcBrand, AcModeViewKind } from '../../main/ets/service/ac/AcModels.ets';

const expectCode = (fn, code) => {
  assert.throws(fn, (error) => {
    assert.ok(error instanceof AppError, `expected AppError, got ${error}`);
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
};

const patch = (options = {}) => {
  const init = new DeviceStatePatchInit();
  init.deviceId = options.deviceId ?? 'AC_01';
  init.isOnline = options.isOnline ?? true;
  init.powerStatus = options.powerStatus ?? true;
  init.targetTemperature = options.targetTemperature ?? 24;
  init.mode = options.mode;
  init.modeStandard = options.mode !== undefined && AcVocabulary.isStandard(options.mode);
  init.updatedAt = '20261017T080000Z';
  return DeviceStatePatch.create(init);
};

test('C16_factoryNormalizesAsciiChineseAliasesAndUnknown', () => {
  const cases = [
    [undefined, AcBrand.GENERIC],
    ['', AcBrand.GENERIC],
    ['   ', AcBrand.GENERIC],
    ['generic', AcBrand.GENERIC],
    ['通用', AcBrand.GENERIC],
    ['GREE', AcBrand.GREE],
    [' 格力 ', AcBrand.GREE],
    ['gree/格力', AcBrand.GREE],
    ['haier', AcBrand.HAIER],
    ['海尔', AcBrand.HAIER],
    ['haier/海尔', AcBrand.HAIER],
    ['Midea', AcBrand.MIDEA],
    ['美的', AcBrand.MIDEA],
    ['midea/美的', AcBrand.MIDEA],
    ['unknown-brand', AcBrand.GENERIC],
  ];
  for (const [input, expected] of cases) {
    assert.equal(AcAdapterFactory.normalizeBrand(input), expected, String(input));
    assert.equal(AcAdapterFactory.create(input).brand, expected, String(input));
  }
  assert.deepEqual(AcAdapterFactory.supportedBrands(),
    [AcBrand.GENERIC, AcBrand.GREE, AcBrand.HAIER, AcBrand.MIDEA]);
});

test('C16_allBrandsShareSevenModesAndTemperatureRange', () => {
  for (const brand of AcAdapterFactory.supportedBrands()) {
    const adapter = AcAdapterFactory.create(brand);
    assert.equal(adapter.brand, brand);
    assert.deepEqual(adapter.capabilities.supportedModes,
      [AcMode.AUTO, AcMode.COOL, AcMode.HEAT, AcMode.DRY, AcMode.FAN, AcMode.ECO, AcMode.SLEEP]);
    assert.equal(adapter.capabilities.minTargetTemperature, 16);
    assert.equal(adapter.capabilities.maxTargetTemperature, 30);
    assert.equal(adapter.capabilities.supportsColor, false);
    assert.equal(adapter.capabilities.supportsFanSpeed, false);
  }
});

test('C16_outboundModeVocabularyIsExactlySevenCanonicalValues', () => {
  const modes = [AcMode.AUTO, AcMode.COOL, AcMode.HEAT, AcMode.DRY,
    AcMode.FAN, AcMode.ECO, AcMode.SLEEP];
  for (const brand of AcAdapterFactory.supportedBrands()) {
    const adapter = AcAdapterFactory.create(brand);
    for (const mode of modes) {
      const command = adapter.setMode(mode);
      assert.equal(command.action, DeviceAction.SET_MODE);
      assert.equal(command.value, mode);
      assert.ok(!(command instanceof Promise));
    }
  }
});

test('C16_nonStandardModeCannotBeSentBack', () => {
  for (const brand of AcAdapterFactory.supportedBrands()) {
    const adapter = AcAdapterFactory.create(brand);
    expectCode(() => adapter.setMode('TURBO'), 'PROTOCOL_VALUE_OUT_OF_RANGE');
    expectCode(() => adapter.setMode('cool'), 'PROTOCOL_VALUE_OUT_OF_RANGE');
    expectCode(() => adapter.setMode(''), 'PROTOCOL_VALUE_OUT_OF_RANGE');
    expectCode(() => adapter.setMode('制冷'), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  }
});

test('C16_powerAndTargetTemperatureMappingAndBoundaries', () => {
  const adapter = AcAdapterFactory.create('gree');
  assert.equal(adapter.power(true).action, DeviceAction.TURN_ON);
  assert.equal(adapter.power(true).value, undefined);
  assert.equal(adapter.power(false).action, DeviceAction.TURN_OFF);
  assert.equal(adapter.power(false).value, undefined);

  for (const value of [16, 24, 24.5, 30]) {
    const command = adapter.setTargetTemperature(value);
    assert.equal(command.action, DeviceAction.SET_TARGET_TEMPERATURE);
    assert.equal(command.value, value);
  }
  for (const value of [15.9, 30.1, -1, 100]) {
    expectCode(() => adapter.setTargetTemperature(value), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  }
  for (const value of [NaN, Infinity, -Infinity, '24', undefined]) {
    expectCode(() => adapter.setTargetTemperature(value), 'PROTOCOL_INVALID_TYPE');
  }
  assert.equal(adapter.normalizeInboundTemperature(16), 16);
  assert.equal(adapter.normalizeInboundTemperature(30), 30);
  expectCode(() => adapter.normalizeInboundTemperature(15.9),
    'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(() => adapter.normalizeInboundTemperature(30.1),
    'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(() => adapter.normalizeInboundTemperature(NaN), 'PROTOCOL_INVALID_TYPE');
});

test('C16_inboundModeStandardNonStandardAndBrandAliases', () => {
  const generic = AcAdapterFactory.create(undefined);
  for (const mode of AcVocabulary.MODES) {
    const view = generic.normalizeInboundMode(mode);
    assert.equal(view.kind, AcModeViewKind.STANDARD);
    assert.equal(view.mode, mode);
    assert.equal(view.i18nKey, 'ac.mode.' + mode.toLowerCase());
  }
  const lower = generic.normalizeInboundMode('cool');
  assert.equal(lower.kind, AcModeViewKind.STANDARD);
  assert.equal(lower.mode, AcMode.COOL);
  assert.equal(lower.raw, 'cool');

  const unknown = generic.normalizeInboundMode('TURBO');
  assert.equal(unknown.kind, AcModeViewKind.NON_STANDARD);
  assert.equal(unknown.mode, undefined);
  assert.equal(unknown.raw, 'TURBO');
  assert.equal(unknown.i18nKey, 'ac.mode.unknown');

  const empty = generic.normalizeInboundMode('   ');
  assert.equal(empty.kind, AcModeViewKind.UNKNOWN);
  assert.equal(empty.raw, '');
  assert.equal(empty.i18nKey, 'ac.mode.unknown');

  const greeAlias = AcAdapterFactory.create('gree').normalizeInboundMode('节能');
  assert.equal(greeAlias.kind, AcModeViewKind.STANDARD);
  assert.equal(greeAlias.mode, AcMode.ECO);
  const haierAlias = AcAdapterFactory.create('haier').normalizeInboundMode('制冷');
  assert.equal(haierAlias.mode, AcMode.COOL);
  const mideaAlias = AcAdapterFactory.create('midea').normalizeInboundMode('睡眠');
  assert.equal(mideaAlias.mode, AcMode.SLEEP);

  // Aliases are brand-scoped: Generic keeps the raw non-standard value.
  assert.equal(generic.normalizeInboundMode('节能').kind, AcModeViewKind.NON_STANDARD);
});

test('C16_toViewStateKeepsUnknownAndOfflineReadOnly', () => {
  const gree = AcAdapterFactory.create('gree');
  const standard = gree.toViewState(patch({ mode: 'COOL' }));
  assert.equal(standard.power, true);
  assert.equal(standard.targetTemperature, 24);
  assert.equal(standard.mode.kind, AcModeViewKind.STANDARD);
  assert.equal(standard.mode.mode, AcMode.COOL);
  assert.equal(standard.brand, AcBrand.GREE);
  assert.equal(standard.brandI18nKey, 'brand.gree');
  assert.equal(standard.isReadOnly, false);

  const nonStandard = gree.toViewState(patch({ mode: 'TURBO' }));
  assert.equal(nonStandard.mode.kind, AcModeViewKind.NON_STANDARD);
  assert.equal(nonStandard.mode.raw, 'TURBO');
  assert.equal(nonStandard.mode.mode, undefined);

  const missing = gree.toViewState(patch({ mode: undefined }));
  assert.equal(missing.mode.kind, AcModeViewKind.UNKNOWN);

  const offline = gree.toViewState(patch({ mode: 'COOL', isOnline: false }));
  assert.equal(offline.isReadOnly, true);
});

test('C16_adaptersHaveNoNetworkRepositoryOrI18nDependency', () => {
  const directory = path.resolve('entry/src/main/ets/service/ac');
  const files = readdirSync(directory).filter((name) => name.endsWith('.ets'));
  assert.ok(files.length >= 7);
  const forbidden = [
    '@ohos', '@kit', 'repository/', 'service/i18n', 'HttpTransport', 'fetch(',
    'setTimeout', 'require(',
  ];
  for (const file of files) {
    const source = readFileSync(path.join(directory, file), 'utf8');
    for (const token of forbidden) {
      assert.equal(source.includes(token), false, `${file} contains ${token}`);
    }
  }
});
