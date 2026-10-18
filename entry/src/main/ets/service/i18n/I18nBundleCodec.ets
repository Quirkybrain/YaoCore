/*
 * YaoCore C-14 resource bundle codec.
 * Producer: agent:implementation-engineer | Task: T-10 / wp-031-i18n
 * Contract: DES-B §7.3.3/§7.4; I18N-DESIGN §4/§6.3 (CHK-01/03/04)
 *
 * Pure parser for `rawfile/i18n/<locale>.json`. The platform adapter
 * (`RawfileI18nLoader`) only reads bytes; all structure validation and
 * flattening lives here so host tests can exercise it without @ohos.
 *
 * Rejects: non-object roots, non-string leaves, empty/placeholder values,
 * unbalanced or malformed `{param}` placeholders, invalid key paths, duplicate
 * flattened keys, and keys deeper than four dot-separated segments.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { JsonKind, JsonNode } from '../../common/types/JsonNode';
import { NameValue } from '../../common/types/NameValue';
import { JsonLimits, JsonParser } from '../../common/utils/JsonParser';
import { I18nResourceBundle, SupportedLocale } from '../../model/I18nModels';

const MAX_BYTES = 2097152;
const MAX_DEPTH = 8;
const MAX_STRING_LENGTH = 32768;

export class I18nBundleCodec {
  static parse(locale: SupportedLocale, text: string): I18nResourceBundle {
    try {
      const root = JsonParser.parse(text, new JsonLimits(MAX_BYTES, MAX_DEPTH, MAX_STRING_LENGTH));
      if (root.kind !== JsonKind.OBJECT) {
        throw I18nBundleCodec.invalid(locale);
      }
      const entries: NameValue[] = [];
      const seen = new Set<string>();
      I18nBundleCodec.flatten(locale, root, '', entries, seen);
      entries.sort((left: NameValue, right: NameValue): number => {
        if (left.name < right.name) {
          return -1;
        }
        if (left.name > right.name) {
          return 1;
        }
        return 0;
      });
      return new I18nResourceBundle(locale, entries, I18nBundleCodec.revision(locale, entries));
    } catch (error) {
      if (error instanceof AppError && error.code === 'I18N_BUNDLE_INVALID') {
        throw error;
      }
      throw I18nBundleCodec.invalid(locale);
    }
  }

  private static flatten(locale: SupportedLocale, node: JsonNode, prefix: string,
    entries: NameValue[], seen: Set<string>): void {
    if (node.kind === JsonKind.STRING) {
      I18nBundleCodec.addLeaf(locale, prefix, node.stringValue, entries, seen);
      return;
    }
    if (node.kind !== JsonKind.OBJECT) {
      throw I18nBundleCodec.invalid(locale);
    }
    const names = node.keys();
    if (names.length === 0) {
      throw I18nBundleCodec.invalid(locale);
    }
    for (let index = 0; index < names.length; index++) {
      const name = names[index];
      if (name.length === 0) {
        throw I18nBundleCodec.invalid(locale);
      }
      const child = node.get(name);
      if (child === undefined) {
        throw I18nBundleCodec.invalid(locale);
      }
      const key = prefix.length === 0 ? name : prefix + '.' + name;
      I18nBundleCodec.flatten(locale, child, key, entries, seen);
    }
  }

  private static addLeaf(locale: SupportedLocale, key: string, value: string,
    entries: NameValue[], seen: Set<string>): void {
    if (!I18nBundleCodec.isValidKey(key)) {
      throw I18nBundleCodec.invalid(locale);
    }
    if (seen.has(key)) {
      throw I18nBundleCodec.invalid(locale);
    }
    if (value.trim().length === 0 || value.indexOf('TODO') >= 0 || value.indexOf('??') >= 0) {
      throw I18nBundleCodec.invalid(locale);
    }
    I18nBundleCodec.validatePlaceholders(locale, value);
    seen.add(key);
    entries.push(new NameValue(key, value));
  }

  private static isValidKey(key: string): boolean {
    const parts = key.split('.');
    if (parts.length === 0 || parts.length > 4) {
      return false;
    }
    for (let index = 0; index < parts.length; index++) {
      if (!I18nBundleCodec.isValidSegment(parts[index])) {
        return false;
      }
    }
    return true;
  }

  private static isValidSegment(segment: string): boolean {
    if (segment.length === 0 || !I18nBundleCodec.isAsciiLetter(segment.charCodeAt(0))) {
      return false;
    }
    for (let index = 1; index < segment.length; index++) {
      const code = segment.charCodeAt(index);
      if (!I18nBundleCodec.isAsciiLetter(code) && (code < 0x30 || code > 0x39) && code !== 0x5F) {
        return false;
      }
    }
    return true;
  }

  private static isAsciiLetter(code: number): boolean {
    return (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
  }

  private static validatePlaceholders(locale: SupportedLocale, value: string): void {
    let index = 0;
    while (index < value.length) {
      const open = value.indexOf('{', index);
      const close = value.indexOf('}', index);
      if (open < 0 && close < 0) {
        return;
      }
      if (open < 0 || close < 0 || close < open) {
        throw I18nBundleCodec.invalid(locale);
      }
      const name = value.substring(open + 1, close);
      if (!I18nBundleCodec.isValidParamName(name)) {
        throw I18nBundleCodec.invalid(locale);
      }
      index = close + 1;
    }
  }

  private static isValidParamName(name: string): boolean {
    if (name.length === 0 || !I18nBundleCodec.isAsciiLetter(name.charCodeAt(0))) {
      return false;
    }
    for (let index = 1; index < name.length; index++) {
      const code = name.charCodeAt(index);
      if (!I18nBundleCodec.isAsciiLetter(code) && (code < 0x30 || code > 0x39) && code !== 0x5F) {
        return false;
      }
    }
    return true;
  }

  private static revision(locale: SupportedLocale, entries: ReadonlyArray<NameValue>): string {
    let hash = 2166136261;
    for (let index = 0; index < entries.length; index++) {
      const entry = entries[index];
      hash = I18nBundleCodec.hashText(hash, entry.name);
      hash = I18nBundleCodec.hashText(hash, '\u0000');
      hash = I18nBundleCodec.hashText(hash, entry.value);
      hash = I18nBundleCodec.hashText(hash, '\u0001');
    }
    return locale + '-' + (hash >>> 0).toString(16) + '-' + String(entries.length);
  }

  private static hashText(seed: number, text: string): number {
    let hash = seed;
    for (let index = 0; index < text.length; index++) {
      hash = hash ^ text.charCodeAt(index);
      hash = Math.imul(hash, 16777619) >>> 0;
    }
    return hash;
  }

  private static invalid(locale: SupportedLocale): AppError {
    return AppErrors.of('I18N_BUNDLE_INVALID', [new NameValue('locale', locale)]);
  }
}
