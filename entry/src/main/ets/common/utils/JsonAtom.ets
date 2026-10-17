/*
 * YaoCore C-01 JSON atom encoding.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §4.1.9, §18.1
 */
import { AppErrors } from '../types/AppError';

export type CommandValue = string | number | boolean;

export class JsonAtom {
  /** Encode one command value as a compact JSON atom; undefined -> empty line. */
  static encode(value: CommandValue | undefined): string {
    if (value === undefined) {
      return '';
    }
    if (typeof value === 'string') {
      return JsonAtom.normalizeString(value);
    }
    if (typeof value === 'number') {
      return JsonAtom.normalizeNumber(value);
    }
    if (typeof value === 'boolean') {
      return value ? 'true' : 'false';
    }
    throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'value');
  }

  static isCommandValue(value: Object): boolean {
    if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
      return true;
    }
    return false;
  }

  static normalizeNumber(value: number): string {
    if (!Number.isFinite(value)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'value');
    }
    return String(value);
  }

  /** Validate UTF-16 and return a quoted JSON string, preserving non-ASCII text. */
  static normalizeString(value: string): string {
    let result = '"';
    let index = 0;
    while (index < value.length) {
      const code = value.charCodeAt(index);
      if (code >= 0xD800 && code <= 0xDBFF) {
        if (index + 1 >= value.length) {
          throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'value');
        }
        const next = value.charCodeAt(index + 1);
        if (next < 0xDC00 || next > 0xDFFF) {
          throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'value');
        }
        result += value.substring(index, index + 2);
        index += 2;
        continue;
      }
      if (code >= 0xDC00 && code <= 0xDFFF) {
        throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'value');
      }
      if (code === 0x22) {
        result += '\\"';
      } else if (code === 0x5C) {
        result += '\\\\';
      } else if (code === 0x08) {
        result += '\\b';
      } else if (code === 0x0C) {
        result += '\\f';
      } else if (code === 0x0A) {
        result += '\\n';
      } else if (code === 0x0D) {
        result += '\\r';
      } else if (code === 0x09) {
        result += '\\t';
      } else if (code < 0x20) {
        result += '\\u' + JsonAtom.hex4(code);
      } else {
        result += value.charAt(index);
      }
      index += 1;
    }
    return result + '"';
  }

  private static hex4(value: number): string {
    const digits = '0123456789abcdef';
    return digits.charAt((value >> 12) & 0x0F) + digits.charAt((value >> 8) & 0x0F) +
      digits.charAt((value >> 4) & 0x0F) + digits.charAt(value & 0x0F);
  }
}
