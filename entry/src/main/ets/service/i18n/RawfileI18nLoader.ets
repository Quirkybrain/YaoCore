/*
 * YaoCore C-14 rawfile resource loader adapter.
 * Producer: agent:implementation-engineer | Task: T-10 / wp-031-i18n
 * Contract: DES-B §7.1.2/§7.2; I18N-DESIGN §3.1
 *
 * COMPILED_ONLY platform adapter: reads `resources/rawfile/i18n/<locale>.json`
 * through the platform ResourceManager and delegates all parsing/validation to
 * the pure `I18nBundleCodec`. No device run exists in this environment.
 */
import { resourceManager } from '@kit.LocalizationKit';
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { Utf8 } from '../../common/utils/Utf8';
import { I18nBundleCodec } from './I18nBundleCodec';
import { I18nResourceBundle, SupportedLocale } from './I18nModels';
import type { I18nResourceLoaderPort } from './I18nPorts';

export class RawfileI18nLoader implements I18nResourceLoaderPort {
  private readonly resourceManager: resourceManager.ResourceManager;
  private readonly directory: string;

  constructor(manager: resourceManager.ResourceManager, directory: string = 'i18n') {
    this.resourceManager = manager;
    this.directory = directory;
  }

  async load(locale: SupportedLocale): Promise<I18nResourceBundle> {
    const path = this.directory + '/' + locale + '.json';
    let bytes: Uint8Array;
    try {
      bytes = await this.resourceManager.getRawFileContent(path);
    } catch (error) {
      throw AppErrors.of('I18N_RESOURCE_LOAD_FAILED', [new NameValue('locale', locale)]);
    }
    try {
      return I18nBundleCodec.parse(locale, Utf8.decode(bytes));
    } catch (error) {
      if (error instanceof AppError && error.code === 'I18N_BUNDLE_INVALID') {
        throw error;
      }
      throw AppErrors.of('I18N_BUNDLE_INVALID', [new NameValue('locale', locale)]);
    }
  }
}
