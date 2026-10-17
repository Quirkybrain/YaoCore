/*
 * YaoCore C-14 I18nService.
 * Producer: agent:implementation-engineer | Task: T-10 / wp-031-i18n
 * Contract: DES-B §7.1.3/§7.2/§7.3 (DES-B-C14-API/ERR/STATE); I18N-DESIGN §2-§4
 * Constraints: I18N-01..06; DES-B D-16; project-constraints §5
 *
 * Pure service: no @ohos imports. Locale resolution, rawfile bundle loading,
 * synchronous lookup, plural selection, interpolation, fallback and observer
 * notification are all injectable and host-testable.
 *
 * Fallback chain (DES-B §7.3.3):
 *   current[key+suffix] -> current[key] -> base[key+suffix] -> base[key] -> key
 * `t()` never throws and never returns a blank string for a non-empty key.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { StorageConstants } from '../../common/constants/StorageConstants';
import type { LoggerPort } from '../../common/types/Ports';
import type { PreferencesStore } from '../storage/PreferencesStore';
import {
  I18nLoadResult,
  I18nParams,
  I18nKey,
  I18nResourceBundle,
  LocaleChangedEvent,
  LocaleMode,
  SupportedLocale
} from './I18nModels';
import type { I18nResourceLoaderPort, LocaleApplierPort } from './I18nPorts';

const TAG = 'I18nService';
const ZH_CN = SupportedLocale.ZH_CN;
const EN_US = SupportedLocale.EN_US;
const AUTO = LocaleMode.AUTO;

class LoadedBundles {
  readonly locale: SupportedLocale;
  readonly current: I18nResourceBundle | undefined;
  readonly base: I18nResourceBundle | undefined;
  readonly missingKeys: ReadonlyArray<string>;
  readonly error: AppError | undefined;

  constructor(locale: SupportedLocale, current: I18nResourceBundle | undefined,
    base: I18nResourceBundle | undefined, missingKeys: ReadonlyArray<string>,
    error: AppError | undefined) {
    this.locale = locale;
    this.current = current;
    this.base = base;
    this.missingKeys = missingKeys;
    this.error = error;
  }
}

export class I18nService {
  private readonly loader: I18nResourceLoaderPort;
  private readonly localeApplier: LocaleApplierPort;
  private readonly preferences: PreferencesStore;
  private readonly logger: LoggerPort;

  private currentLocale: SupportedLocale = ZH_CN;
  private currentMode: LocaleMode = AUTO;
  private systemLocale: string = '';

  private currentEntries: Map<string, string> = new Map<string, string>();
  private baseEntries: Map<string, string> = new Map<string, string>();

  private readonly missingInLocale: Set<string> = new Set<string>();
  private readonly loggedMissingKeys: Set<string> = new Set<string>();
  private readonly loggedMissingParams: Set<string> = new Set<string>();
  private listeners: Array<(event: LocaleChangedEvent) => void> = [];
  private revisionCounter: number = 0;

  constructor(loader: I18nResourceLoaderPort, localeApplier: LocaleApplierPort,
    preferences: PreferencesStore, logger: LoggerPort) {
    this.loader = loader;
    this.localeApplier = localeApplier;
    this.preferences = preferences;
    this.logger = logger;
  }

  async initialize(): Promise<I18nLoadResult> {
    let stored: string | undefined = undefined;
    try {
      stored = await this.preferences.getString(StorageConstants.PREF_LOCALE_MODE);
    } catch (error) {
      const storageError = I18nService.toStorageError(error);
      this.logger.warn(TAG, storageError.code, [new NameValue('locale', this.currentLocale)]);
    }

    const mode = this.parseMode(stored);
    const locale = mode === AUTO ? await this.resolveAutoLocale() : I18nService.modeLocale(mode);
    const loaded = await this.loadBundles(locale);

    // F-08: when the current bundle fails but the zh-CN base loaded, serve the
    // base bundle and apply zh-CN. Keeping the failed locale here would make
    // `$r` (platform) and `t()` (rawfile) show different languages.
    const effectiveLocale = loaded.current !== undefined ? locale : ZH_CN;
    const effectiveCurrent = loaded.current !== undefined ? loaded.current : loaded.base;

    this.currentMode = mode;
    this.currentLocale = effectiveLocale;
    this.assignBundles(effectiveCurrent, loaded.base);
    await this.applyPlatform(effectiveLocale);
    this.warnBaseFailure(loaded);
    this.warnCurrentFailure(loaded, locale);

    return new I18nLoadResult(effectiveLocale, loaded.current !== undefined, loaded.missingKeys, loaded.error);
  }

  getLocale(): SupportedLocale {
    return this.currentLocale;
  }

  getLocaleMode(): LocaleMode {
    return this.currentMode;
  }

  /** Latest system locale read; empty when auto resolution failed or was not attempted. */
  getSystemLocale(): string {
    return this.systemLocale;
  }

  async setLocaleMode(mode: LocaleMode): Promise<void> {
    if (mode !== AUTO && mode !== LocaleMode.ZH_CN && mode !== LocaleMode.EN_US) {
      throw AppErrors.of('I18N_LOCALE_UNSUPPORTED', [new NameValue('locale', String(mode))]);
    }

    const previousMode = this.currentMode;
    try {
      await this.preferences.putString(StorageConstants.PREF_LOCALE_MODE, mode);
    } catch (error) {
      throw I18nService.toStorageError(error);
    }

    const locale = mode === AUTO ? await this.resolveAutoLocale() : I18nService.modeLocale(mode);
    const loaded = await this.loadBundles(locale);
    if (loaded.current === undefined) {
      await this.restorePreviousMode(previousMode);
      if (loaded.error !== undefined) {
        throw loaded.error;
      }
      throw AppErrors.of('I18N_RESOURCE_LOAD_FAILED', [new NameValue('locale', locale)]);
    }

    const previousLocale = this.currentLocale;
    this.currentMode = mode;
    this.currentLocale = locale;
    this.assignBundles(loaded.current, loaded.base);
    const applied = await this.applyPlatform(locale);
    this.notify(previousLocale, locale, mode, applied);
    this.warnBaseFailure(loaded);
  }

  async reload(): Promise<I18nLoadResult> {
    const previousLocale = this.currentLocale;
    const mode = this.currentMode;
    const locale = mode === AUTO ? await this.resolveAutoLocale() : I18nService.modeLocale(mode);
    const loaded = await this.loadBundles(locale);
    if (loaded.current === undefined) {
      if (loaded.error !== undefined) {
        this.logger.warn(TAG, loaded.error.code, [new NameValue('locale', locale)]);
      }
      return new I18nLoadResult(locale, false, loaded.missingKeys, loaded.error);
    }

    this.currentLocale = locale;
    this.assignBundles(loaded.current, loaded.base);
    const applied = await this.applyPlatform(locale);
    this.notify(previousLocale, locale, mode, applied);
    this.warnBaseFailure(loaded);
    return new I18nLoadResult(locale, true, loaded.missingKeys, loaded.error);
  }

  /** Synchronous lookup used from ArkUI build(); never throws, never blank for non-empty keys. */
  t(key: string, params?: I18nParams): string {
    if (key.length === 0) {
      return key;
    }
    const actual = params === undefined ? I18nParams.empty() : params;
    const suffix = this.pluralSuffix(actual);

    let text = this.lookupCurrent(key, suffix);
    if (text === undefined) {
      text = this.lookupBase(key, suffix);
    }
    if (text === undefined) {
      this.recordMissingKey(key);
      return key;
    }
    return this.interpolate(text, key, actual);
  }

  tKey(key: I18nKey): string {
    return this.t(key.key, I18nParams.of(key.params));
  }

  has(key: string): boolean {
    return this.currentEntries.has(key) || this.baseEntries.has(key) ||
      this.currentEntries.has(key + '_one') || this.currentEntries.has(key + '_other') ||
      this.baseEntries.has(key + '_one') || this.baseEntries.has(key + '_other');
  }

  onLocaleChanged(listener: (event: LocaleChangedEvent) => void): () => void {
    this.listeners.push(listener);
    let active = true;
    return (): void => {
      if (!active) {
        return;
      }
      active = false;
      const index = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    };
  }

  /** Current-locale keys that fell back to the zh-CN bundle; excludes keys missing from both. */
  getMissingKeys(): ReadonlyArray<string> {
    const result: string[] = [];
    this.missingInLocale.forEach((key: string): void => {
      result.push(key);
    });
    result.sort();
    return result;
  }

  dispose(): void {
    this.listeners = [];
    this.currentEntries.clear();
    this.baseEntries.clear();
    this.missingInLocale.clear();
    this.loggedMissingKeys.clear();
    this.loggedMissingParams.clear();
  }

  private parseMode(stored: string | undefined): LocaleMode {
    if (stored === undefined || stored.length === 0) {
      return AUTO;
    }
    if (stored === LocaleMode.ZH_CN) {
      return LocaleMode.ZH_CN;
    }
    if (stored === LocaleMode.EN_US) {
      return LocaleMode.EN_US;
    }
    if (stored === LocaleMode.AUTO) {
      return AUTO;
    }
    this.logger.warn(TAG, 'I18N_LOCALE_UNSUPPORTED', [new NameValue('mode', stored)]);
    return AUTO;
  }

  private static modeLocale(mode: LocaleMode): SupportedLocale {
    return mode === LocaleMode.EN_US ? EN_US : ZH_CN;
  }

  private async resolveAutoLocale(): Promise<SupportedLocale> {
    try {
      const raw = await this.localeApplier.getSystemLocale();
      this.systemLocale = raw;
      return I18nService.resolveLocale(raw);
    } catch (error) {
      this.systemLocale = '';
      this.logger.warn(TAG, 'I18N_SYSTEM_LOCALE_READ_FAILED', []);
      return ZH_CN;
    }
  }

  /** `zh*` -> zh-CN, `en*` -> en-US, everything else/empty -> zh-CN. */
  static resolveLocale(raw: string): SupportedLocale {
    const normalized = raw.trim().toLowerCase();
    if (normalized.startsWith('zh')) {
      return ZH_CN;
    }
    if (normalized.startsWith('en')) {
      return EN_US;
    }
    return ZH_CN;
  }

  private async loadBundles(locale: SupportedLocale): Promise<LoadedBundles> {
    let base: I18nResourceBundle | undefined = undefined;
    let baseError: AppError | undefined = undefined;
    try {
      base = await this.loader.load(ZH_CN);
    } catch (error) {
      baseError = I18nService.toLoadError(error, ZH_CN);
    }

    let current: I18nResourceBundle | undefined = base;
    let currentError: AppError | undefined = baseError;
    if (locale !== ZH_CN) {
      try {
        current = await this.loader.load(locale);
        currentError = undefined;
      } catch (error) {
        current = undefined;
        currentError = I18nService.toLoadError(error, locale);
      }
    }

    const missing = I18nService.missingInCurrent(current, base);
    const error = currentError !== undefined ? currentError : baseError;
    return new LoadedBundles(locale, current, base, missing, error);
  }

  private assignBundles(current: I18nResourceBundle | undefined, base: I18nResourceBundle | undefined): void {
    this.currentEntries = I18nService.toMap(current);
    this.baseEntries = I18nService.toMap(base);
    this.missingInLocale.clear();
    this.loggedMissingKeys.clear();
    this.loggedMissingParams.clear();
  }

  private static toMap(bundle: I18nResourceBundle | undefined): Map<string, string> {
    const map = new Map<string, string>();
    if (bundle === undefined) {
      return map;
    }
    for (let index = 0; index < bundle.entries.length; index++) {
      const entry = bundle.entries[index];
      map.set(entry.name, entry.value);
    }
    return map;
  }

  private static missingInCurrent(current: I18nResourceBundle | undefined,
    base: I18nResourceBundle | undefined): ReadonlyArray<string> {
    if (current === undefined || base === undefined) {
      return [];
    }
    const present = new Set<string>();
    for (let index = 0; index < current.entries.length; index++) {
      present.add(I18nService.baseKey(current.entries[index].name));
    }
    const missing = new Set<string>();
    for (let index = 0; index < base.entries.length; index++) {
      const key = I18nService.baseKey(base.entries[index].name);
      if (!present.has(key)) {
        missing.add(key);
      }
    }
    const result: string[] = [];
    missing.forEach((key: string): void => {
      result.push(key);
    });
    result.sort();
    return result;
  }

  private static baseKey(key: string): string {
    if (key.endsWith('_one')) {
      return key.substring(0, key.length - '_one'.length);
    }
    if (key.endsWith('_other')) {
      return key.substring(0, key.length - '_other'.length);
    }
    return key;
  }

  private lookupCurrent(key: string, suffix: string): string | undefined {
    if (suffix.length > 0) {
      const variant = this.currentEntries.get(key + suffix);
      if (variant !== undefined && variant.length > 0) {
        return variant;
      }
    }
    const value = this.currentEntries.get(key);
    if (value !== undefined && value.length > 0) {
      return value;
    }
    return undefined;
  }

  private lookupBase(key: string, suffix: string): string | undefined {
    if (this.currentLocale === ZH_CN) {
      return undefined;
    }
    if (suffix.length > 0) {
      const variant = this.baseEntries.get(key + suffix);
      if (variant !== undefined && variant.length > 0) {
        this.missingInLocale.add(key);
        return variant;
      }
    }
    const value = this.baseEntries.get(key);
    if (value !== undefined && value.length > 0) {
      this.missingInLocale.add(key);
      return value;
    }
    return undefined;
  }

  private pluralSuffix(params: I18nParams): string {
    if (this.currentLocale !== EN_US || params.count === undefined) {
      return '';
    }
    return params.count === 1 ? '_one' : '_other';
  }

  private interpolate(text: string, key: string, params: I18nParams): string {
    let result = '';
    let index = 0;
    while (index < text.length) {
      const open = text.indexOf('{', index);
      if (open < 0) {
        result += text.substring(index);
        break;
      }
      const close = text.indexOf('}', open + 1);
      if (close < 0) {
        result += text.substring(index);
        break;
      }
      const name = text.substring(open + 1, close);
      if (!I18nService.isValidParamName(name)) {
        result += text.substring(index, open + 1);
        index = open + 1;
        continue;
      }
      result += text.substring(index, open);
      const value = params.get(name);
      if (value === undefined) {
        result += text.substring(open, close + 1);
        this.recordMissingParam(key, name);
      } else {
        result += value;
      }
      index = close + 1;
    }
    return result;
  }

  private static isValidParamName(name: string): boolean {
    if (name.length === 0 || !I18nService.isAsciiLetter(name.charCodeAt(0))) {
      return false;
    }
    for (let index = 1; index < name.length; index++) {
      const code = name.charCodeAt(index);
      if (!I18nService.isAsciiLetter(code) && (code < 0x30 || code > 0x39) && code !== 0x5F) {
        return false;
      }
    }
    return true;
  }

  private static isAsciiLetter(code: number): boolean {
    return (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
  }

  private recordMissingKey(key: string): void {
    if (this.loggedMissingKeys.has(key)) {
      return;
    }
    this.loggedMissingKeys.add(key);
    this.logger.debug(TAG, 'I18N_MISSING_KEY', [
      new NameValue('key', key),
      new NameValue('locale', this.currentLocale)
    ]);
  }

  private recordMissingParam(key: string, name: string): void {
    const identity = key + '|' + name;
    if (this.loggedMissingParams.has(identity)) {
      return;
    }
    this.loggedMissingParams.add(identity);
    this.logger.warn(TAG, 'I18N_MISSING_PARAM', [
      new NameValue('key', key),
      new NameValue('param', name)
    ]);
  }

  private async applyPlatform(locale: SupportedLocale): Promise<boolean> {
    try {
      await this.localeApplier.apply(locale);
      return true;
    } catch (error) {
      const mapped = error instanceof AppError ? error : AppErrors.of('I18N_PLATFORM_LOCALE_FAILED',
        [new NameValue('locale', locale)]);
      this.logger.warn(TAG, mapped.code, [new NameValue('locale', locale)]);
      return false;
    }
  }

  private notify(previous: SupportedLocale, current: SupportedLocale, mode: LocaleMode,
    applied: boolean): void {
    this.revisionCounter += 1;
    const event = new LocaleChangedEvent(previous, current, mode, applied, this.revisionCounter);
    const snapshot = this.listeners.slice();
    for (let index = 0; index < snapshot.length; index++) {
      try {
        snapshot[index](event);
      } catch (error) {
        this.logger.warn(TAG, 'I18N_LISTENER_FAILED', []);
      }
    }
  }

  private async restorePreviousMode(previousMode: LocaleMode): Promise<void> {
    try {
      await this.preferences.putString(StorageConstants.PREF_LOCALE_MODE, previousMode);
    } catch (error) {
      const storageError = I18nService.toStorageError(error);
      this.logger.warn(TAG, storageError.code, [new NameValue('mode', previousMode)]);
    }
  }

  private warnBaseFailure(loaded: LoadedBundles): void {
    if (loaded.current !== undefined && loaded.base === undefined && loaded.error !== undefined) {
      this.logger.warn(TAG, loaded.error.code, [new NameValue('locale', ZH_CN)]);
    }
  }

  /** Current-locale load failure after a successful base fallback; logs locale names only. */
  private warnCurrentFailure(loaded: LoadedBundles, requested: SupportedLocale): void {
    if (loaded.current === undefined && loaded.error !== undefined) {
      const fields: NameValue[] = [new NameValue('locale', requested)];
      if (requested !== ZH_CN) {
        fields.push(new NameValue('fallback', ZH_CN));
      }
      this.logger.warn(TAG, loaded.error.code, fields);
    }
  }

  private static toLoadError(error: Object, locale: SupportedLocale): AppError {
    if (error instanceof AppError) {
      return error;
    }
    return AppErrors.of('I18N_RESOURCE_LOAD_FAILED', [new NameValue('locale', locale)]);
  }

  private static toStorageError(error: Object): AppError {
    if (error instanceof AppError) {
      return error;
    }
    return AppErrors.of('STORAGE_PREFERENCES_ERROR', []);
  }
}
