/*
 * YaoCore C-14 device-side i18n adapter tests.
 * Producer: agent:implementation-engineer | Task: T-10 / wp-031-i18n
 * Contract: DES-B §7.1-§7.5; D-019 device layer.
 *
 * STATUS: BLOCKED_ON_DEVICE_RUNNER — no device/emulator and no signing config
 * exists in this environment. This file is COMPILED_ONLY (pulled into the
 * ArkTS compile graph by the host suite); it must never be reported as PASS
 * from the Node host runner.
 *
 * The suite exercises the real rawfile loader, ApplicationContext language
 * apply and Preferences persistence once a device runner exists. Runtime
 * `$r` re-render is a UI assertion owned by T-17/T-18 and is not claimed here.
 *
 * PUBLIC TEST DATA ONLY.
 */
import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { NameValue } from '../../../../main/ets/common/types/NameValue';
import type { LoggerPort } from '../../../../main/ets/common/types/Ports';
import { PreferencesStoreAdapter } from '../../../../main/ets/service/storage/PreferencesStoreAdapter';
import { I18nParams, LocaleMode, SupportedLocale } from '../../../../main/ets/service/i18n/I18nModels';
import { I18nService } from '../../../../main/ets/service/i18n/I18nService';
import { I18nKeys } from '../../../../main/ets/service/i18n/I18nKeys';
import { OhosLocaleApplier } from '../../../../main/ets/service/i18n/OhosLocaleApplier';
import { RawfileI18nLoader } from '../../../../main/ets/service/i18n/RawfileI18nLoader';

const PREF_NAME: string = 'yaocore_t10_device_prefs';

class DeviceLogger implements LoggerPort {
  debug(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
  }

  info(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
  }

  warn(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
  }

  error(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
  }
}

export default function i18nDeviceTest() {
  describe('BLOCKED_ON_DEVICE_RUNNER C14 i18n adapters', () => {
    it('C14_rawfileLocaleSwitchAndFallback', 0, async () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const preferences = new PreferencesStoreAdapter(context, PREF_NAME);
      const service = new I18nService(new RawfileI18nLoader(context.resourceManager),
        new OhosLocaleApplier(context.getApplicationContext()), preferences, new DeviceLogger());
      const initialized = await service.initialize();
      expect(initialized.loaded).assertTrue();
      const locale = service.getLocale();
      expect(locale === SupportedLocale.ZH_CN || locale === SupportedLocale.EN_US).assertTrue();
      // `common_*` lives in string.json ($r); rawfile lookups use rawfile keys.
      expect(service.t('errors.gateway.success') === 'errors.gateway.success').assertFalse();

      await service.setLocaleMode(LocaleMode.EN_US);
      expect(service.getLocale()).assertEqual(SupportedLocale.EN_US);
      const english = service.t('errors.gateway.success');
      expect(english).assertEqual('Success');

      await service.setLocaleMode(LocaleMode.ZH_CN);
      expect(service.getLocale()).assertEqual(SupportedLocale.ZH_CN);
      const chinese = service.t('errors.gateway.success');
      expect(chinese).assertEqual('成功');

      expect(service.t('missing.key.for.device.probe')).assertEqual('missing.key.for.device.probe');
      const count = I18nParams.countOf(2, [new NameValue('count', '2')]);
      expect(service.t('device.count', count).length > 0).assertTrue();
      expect(I18nKeys.appError('SCENE_RUN_IN_PROGRESS')).assertEqual('errors.scene.run_in_progress');
      await preferences.delete('app.locale.mode');
      service.dispose();
      await preferences.close();
    });
  });
}
