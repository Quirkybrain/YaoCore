/*
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-A §27.6.3 P1.
 * YaoCore C-14 i18n ports.
 * Producer: agent:implementation-engineer | Task: T-10 / wp-031-i18n
 * Contract: DES-B §7.1.2, §7.5 (DES-B-C14-SEAM)
 *
 * I18nService depends only on these ports. Platform APIs live in adapters:
 * `RawfileI18nLoader` and `OhosLocaleApplier`.
 */
import { I18nResourceBundle, SupportedLocale } from '../model/I18nModels';

export interface I18nResourceLoaderPort {
  load(locale: SupportedLocale): Promise<I18nResourceBundle>;
}

export interface LocaleApplierPort {
  /** Reads the system locale (BCP-47). Failure returns an empty string (fallback zh-CN). */
  getSystemLocale(): Promise<string>;
  /** Applies the app resource locale to the platform (affects `$r` text). Failure rejects AppError. */
  apply(locale: SupportedLocale): Promise<void>;
}
