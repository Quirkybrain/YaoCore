/*
 * YaoCore C-14 host (local) compile/behaviour suite.
 * Producer: agent:implementation-engineer | Task: T-10 / wp-031-i18n
 * Contract: DES-B §7.1-§7.5; TEST-001 host layer; D-019
 *
 * Executable host evidence remains `entry/src/test/run-host-tests.sh` (Node).
 * This Hypium suite keeps C-14 and the device skeleton in the ArkTS compile
 * graph; the Linux Previewer execution path is BLOCKED (TEST-001 §3).
 */
import { describe, expect, it } from '@ohos/hypium';
import { NameValue } from '../../main/ets/common/types/NameValue';
import { I18nBundleCodec } from '../../main/ets/service/i18n/I18nBundleCodec';
import {
  I18nParams,
  LocaleMode,
  SupportedLocale
} from '../../main/ets/service/i18n/I18nModels';
import { I18nService } from '../../main/ets/service/i18n/I18nService';
import { I18nKeys } from '../../main/ets/service/i18n/I18nKeys';
import {
  FakeI18nLoader,
  FakeLocaleApplier,
  InMemoryI18nPreferences,
  RecordingLogger
} from './I18nFakes';
import i18nDeviceTest from '../../ohosTest/ets/test/i18n/I18nDevice.test';

// Imported only to pull the device-side skeleton into the compile graph.
// It remains BLOCKED for execution until a device runner exists.
void i18nDeviceTest;

const ZH_JSON: string = '{"common":{"ok":"确定","greet":"你好，{name}！"},"device":{"count":"{count} 个设备"}}';
const EN_JSON: string = '{"common":{"ok":"OK","greet":"Hello, {name}!"},' +
  '"device":{"count_one":"{count} device","count_other":"{count} devices"}}';

class I18nHostHarness {
  readonly loader: FakeI18nLoader;
  readonly applier: FakeLocaleApplier;
  readonly preferences: InMemoryI18nPreferences;
  readonly logger: RecordingLogger;
  readonly service: I18nService;

  constructor() {
    this.loader = new FakeI18nLoader();
    this.loader.put(I18nBundleCodec.parse(SupportedLocale.ZH_CN, ZH_JSON));
    this.loader.put(I18nBundleCodec.parse(SupportedLocale.EN_US, EN_JSON));
    this.applier = new FakeLocaleApplier();
    this.applier.systemLocale = 'en-GB';
    this.preferences = new InMemoryI18nPreferences();
    this.logger = new RecordingLogger();
    this.service = new I18nService(this.loader, this.applier, this.preferences, this.logger);
  }
}

export function I18nHostSuite() {
  describe('T10_C14_host_compile_and_smoke', () => {
    it('C14_initialize_autoEnglish_and_lookup', 0, async () => {
      const harness = new I18nHostHarness();
      const result = await harness.service.initialize();
      expect(result.loaded).assertTrue();
      expect(harness.service.getLocale()).assertEqual(SupportedLocale.EN_US);
      expect(harness.service.t('common.ok')).assertEqual('OK');
    });

    it('C14_interpolation_and_missingParam', 0, async () => {
      const harness = new I18nHostHarness();
      await harness.service.initialize();
      const params = I18nParams.of([new NameValue('name', 'Yao')]);
      expect(harness.service.t('common.greet', params)).assertEqual('Hello, Yao!');
      expect(harness.service.t('common.greet')).assertEqual('Hello, {name}!');
    });

    it('C14_plural_one_other_and_zhBaseOnly', 0, async () => {
      const harness = new I18nHostHarness();
      await harness.service.initialize();
      const one = I18nParams.countOf(1, [new NameValue('count', '1')]);
      const two = I18nParams.countOf(2, [new NameValue('count', '2')]);
      expect(harness.service.t('device.count', one)).assertEqual('1 device');
      expect(harness.service.t('device.count', two)).assertEqual('2 devices');
      await harness.service.setLocaleMode(LocaleMode.ZH_CN);
      expect(harness.service.t('device.count', two)).assertEqual('2 个设备');
    });

    it('C14_setLocaleMode_persistsAndNotifies', 0, async () => {
      const harness = new I18nHostHarness();
      await harness.service.initialize();
      let events: number = 0;
      harness.service.onLocaleChanged((): void => {
        events += 1;
      });
      await harness.service.setLocaleMode(LocaleMode.ZH_CN);
      expect(events).assertEqual(1);
      expect(harness.service.t('common.ok')).assertEqual('确定');
      expect(harness.preferences.peek('app.locale.mode')).assertEqual(LocaleMode.ZH_CN);
    });

    it('C14_keysAndFallbackKeyText', 0, () => {
      expect(I18nKeys.appError('SCENE_RUN_IN_PROGRESS')).assertEqual('errors.scene.run_in_progress');
      expect(I18nKeys.stateSource('device.feedback', true).key).assertEqual('stateSource.device_feedback');
      expect(I18nKeys.acMode('COOL', true).key).assertEqual('ac.mode.cool');
    });
  });
}
