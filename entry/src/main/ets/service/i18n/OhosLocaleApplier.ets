/*
 * YaoCore C-14 platform locale applier.
 * Producer: agent:implementation-engineer | Task: T-10 / wp-031-i18n
 * Contract: DES-B §7.1.2/§7.2/§7.3.1
 *
 * COMPILED_ONLY adapter. `ApplicationContext.setLanguage` reloads `$r` string
 * resources for the running app; `i18n.System.getSystemLocale` supplies the
 * auto-mode preference. Failures are normalized to AppError / empty string and
 * never carry user data.
 */
import { common } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';
import { AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { SupportedLocale } from '../../model/I18nModels';
import type { LocaleApplierPort } from '../../contracts/I18nPorts';

export class OhosLocaleApplier implements LocaleApplierPort {
  private readonly context: common.ApplicationContext;

  constructor(context: common.ApplicationContext) {
    this.context = context;
  }

  async getSystemLocale(): Promise<string> {
    try {
      return i18n.System.getSystemLocaleInstance().toString();
    } catch (error) {
      return '';
    }
  }

  async apply(locale: SupportedLocale): Promise<void> {
    try {
      this.context.setLanguage(locale);
    } catch (error) {
      throw AppErrors.of('I18N_PLATFORM_LOCALE_FAILED', [new NameValue('locale', locale)]);
    }
  }
}
