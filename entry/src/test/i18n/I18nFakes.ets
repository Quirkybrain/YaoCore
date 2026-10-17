/*
 * YaoCore C-14 host fakes.
 * Producer: agent:implementation-engineer | Task: T-10 / wp-031-i18n
 * Contract: DES-B §7.5 (DES-B-C14-SEAM); D-019 host layer
 *
 * PUBLIC TEST DATA ONLY. No platform APIs. Failures are injectable so the
 * service rollback and `platformApplied=false` branches are host-observable.
 */
import { NameValue } from '../../main/ets/common/types/NameValue';
import type { LoggerPort } from '../../main/ets/common/types/Ports';
import type { PreferencesStore } from '../../main/ets/service/storage/PreferencesStore';
import { I18nResourceBundle, SupportedLocale } from '../../main/ets/service/i18n/I18nModels';
import type { I18nResourceLoaderPort, LocaleApplierPort } from '../../main/ets/service/i18n/I18nPorts';

export class FakeI18nLoader implements I18nResourceLoaderPort {
  private readonly bundles: Map<string, I18nResourceBundle> = new Map<string, I18nResourceBundle>();
  private readonly failures: Set<string> = new Set<string>();
  loadCalls: string[] = [];

  put(bundle: I18nResourceBundle): void {
    this.bundles.set(bundle.locale, bundle);
  }

  fail(locale: SupportedLocale): void {
    this.failures.add(locale);
  }

  clearFailure(locale: SupportedLocale): void {
    this.failures.delete(locale);
  }

  async load(locale: SupportedLocale): Promise<I18nResourceBundle> {
    this.loadCalls.push(locale);
    if (this.failures.has(locale)) {
      throw new Error('injected load failure: ' + locale);
    }
    const bundle = this.bundles.get(locale);
    if (bundle === undefined) {
      throw new Error('missing fake bundle: ' + locale);
    }
    return bundle;
  }
}

export class FakeLocaleApplier implements LocaleApplierPort {
  systemLocale: string = 'zh-Hans-CN';
  failSystemRead: boolean = false;
  failApply: boolean = false;
  applied: string[] = [];

  async getSystemLocale(): Promise<string> {
    if (this.failSystemRead) {
      throw new Error('injected system locale failure');
    }
    return this.systemLocale;
  }

  async apply(locale: SupportedLocale): Promise<void> {
    if (this.failApply) {
      throw new Error('injected apply failure');
    }
    this.applied.push(locale);
  }
}

export class InMemoryI18nPreferences implements PreferencesStore {
  private readonly values: Map<string, string> = new Map<string, string>();
  failGet: boolean = false;
  failPut: boolean = false;
  puts: string[] = [];

  async getString(key: string): Promise<string | undefined> {
    if (this.failGet) {
      throw new Error('injected preferences read failure');
    }
    return this.values.get(key);
  }

  async putString(key: string, value: string): Promise<void> {
    if (this.failPut) {
      throw new Error('injected preferences write failure');
    }
    this.values.set(key, value);
    this.puts.push(value);
  }

  async delete(key: string): Promise<void> {
    this.values.delete(key);
  }

  async flush(): Promise<void> {
  }

  seed(key: string, value: string): void {
    this.values.set(key, value);
  }

  peek(key: string): string | undefined {
    return this.values.get(key);
  }
}

export class RecordingLogger implements LoggerPort {
  debugMessages: string[] = [];
  infoMessages: string[] = [];
  warnMessages: string[] = [];
  errorMessages: string[] = [];

  debug(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
    this.debugMessages.push(message);
  }

  info(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
    this.infoMessages.push(message);
  }

  warn(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
    this.warnMessages.push(message);
  }

  error(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
    this.errorMessages.push(message);
  }
}
