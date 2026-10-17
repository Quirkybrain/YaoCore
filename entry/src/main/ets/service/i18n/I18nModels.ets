/*
 * YaoCore C-14 i18n value objects.
 * Producer: agent:implementation-engineer | Task: T-10 / wp-031-i18n
 * Contract: DES-B §7.1.1; I18N-DESIGN §2-§4; DES-A §24.1
 *
 * Pure value objects only: no platform imports, no I/O. `I18nParams.count` is
 * used solely for the English `_one` / `_other` plural variants; Chinese uses
 * the base key.
 */
import { AppError } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';

export enum SupportedLocale {
  ZH_CN = 'zh-CN',
  EN_US = 'en-US'
}

export enum LocaleMode {
  AUTO = 'auto',
  ZH_CN = 'zh-CN',
  EN_US = 'en-US'
}

/** Key plus interpolation parameters, as produced by the error/state mappers. */
export class I18nKey {
  readonly key: string;
  readonly params: ReadonlyArray<NameValue>;

  constructor(key: string, params?: ReadonlyArray<NameValue>) {
    this.key = key;
    this.params = params === undefined ? [] : params;
  }
}

export class I18nParams {
  readonly entries: ReadonlyArray<NameValue>;
  readonly count: number | undefined;

  constructor(entries?: ReadonlyArray<NameValue>, count?: number) {
    this.entries = entries === undefined ? [] : entries;
    this.count = count;
  }

  static empty(): I18nParams {
    return new I18nParams();
  }

  static of(entries: ReadonlyArray<NameValue>): I18nParams {
    return new I18nParams(entries, undefined);
  }

  static countOf(count: number, entries?: ReadonlyArray<NameValue>): I18nParams {
    return new I18nParams(entries, count);
  }

  get(name: string): string | undefined {
    for (let index = 0; index < this.entries.length; index++) {
      if (this.entries[index].name === name) {
        return this.entries[index].value;
      }
    }
    if (name === 'count' && this.count !== undefined) {
      return String(this.count);
    }
    return undefined;
  }
}

/** One loaded locale bundle. `entries` are already flattened dot-separated keys. */
export class I18nResourceBundle {
  readonly locale: SupportedLocale;
  readonly entries: ReadonlyArray<NameValue>;
  readonly revision: string;

  constructor(locale: SupportedLocale, entries: ReadonlyArray<NameValue>, revision: string) {
    this.locale = locale;
    this.entries = entries;
    this.revision = revision;
  }
}

export class LocaleChangedEvent {
  readonly previous: SupportedLocale;
  readonly current: SupportedLocale;
  readonly mode: LocaleMode;
  readonly platformApplied: boolean;
  readonly revision: number;

  constructor(previous: SupportedLocale, current: SupportedLocale, mode: LocaleMode,
    platformApplied: boolean, revision: number) {
    this.previous = previous;
    this.current = current;
    this.mode = mode;
    this.platformApplied = platformApplied;
    this.revision = revision;
  }
}

export class I18nLoadResult {
  readonly locale: SupportedLocale;
  readonly loaded: boolean;
  readonly missingKeys: ReadonlyArray<string>;
  readonly error?: AppError;

  constructor(locale: SupportedLocale, loaded: boolean, missingKeys: ReadonlyArray<string>,
    error?: AppError) {
    this.locale = locale;
    this.loaded = loaded;
    this.missingKeys = missingKeys;
    this.error = error;
  }
}
