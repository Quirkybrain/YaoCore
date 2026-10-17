/*
 * YaoCore C-01 strict UTF-8 codec.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §4.1.6, §4.3 invariant 8
 *
 * Invalid sequences are rejected. No replacement character is ever produced.
 */
import { AppErrors } from '../types/AppError';

export class Utf8 {
  static encode(text: string): Uint8Array {
    const bytes: number[] = [];
    let index = 0;
    while (index < text.length) {
      const first = text.charCodeAt(index);
      let codePoint = first;
      if (first >= 0xD800 && first <= 0xDBFF) {
        if (index + 1 >= text.length) {
          throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'utf8');
        }
        const second = text.charCodeAt(index + 1);
        if (second < 0xDC00 || second > 0xDFFF) {
          throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'utf8');
        }
        codePoint = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00);
        index += 2;
      } else if (first >= 0xDC00 && first <= 0xDFFF) {
        throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'utf8');
      } else {
        index += 1;
      }
      Utf8.pushCodePoint(bytes, codePoint);
    }
    const result = new Uint8Array(bytes.length);
    for (let i = 0; i < bytes.length; i++) {
      result[i] = bytes[i];
    }
    return result;
  }

  static decode(bytes: Uint8Array): string {
    let result = '';
    let index = 0;
    while (index < bytes.length) {
      const first = bytes[index];
      if (first <= 0x7F) {
        result += String.fromCharCode(first);
        index += 1;
        continue;
      }
      let codePoint = 0;
      let extra = 0;
      if (first >= 0xC2 && first <= 0xDF) {
        codePoint = first & 0x1F;
        extra = 1;
      } else if (first >= 0xE0 && first <= 0xEF) {
        codePoint = first & 0x0F;
        extra = 2;
      } else if (first >= 0xF0 && first <= 0xF4) {
        codePoint = first & 0x07;
        extra = 3;
      } else {
        throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'utf8');
      }
      if (index + extra >= bytes.length) {
        throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'utf8');
      }
      for (let offset = 1; offset <= extra; offset++) {
        const next = bytes[index + offset];
        if (next < 0x80 || next > 0xBF) {
          throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'utf8');
        }
        codePoint = (codePoint << 6) | (next & 0x3F);
      }
      if (extra === 2) {
        if (codePoint < 0x800 || (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
          throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'utf8');
        }
      } else if (extra === 3) {
        if (codePoint < 0x10000 || codePoint > 0x10FFFF) {
          throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'utf8');
        }
      }
      if (codePoint <= 0xFFFF) {
        result += String.fromCharCode(codePoint);
      } else {
        const value = codePoint - 0x10000;
        result += String.fromCharCode(0xD800 + (value >> 10));
        result += String.fromCharCode(0xDC00 + (value & 0x3FF));
      }
      index += extra + 1;
    }
    return result;
  }

  private static pushCodePoint(bytes: number[], codePoint: number): void {
    if (codePoint <= 0x7F) {
      bytes.push(codePoint);
    } else if (codePoint <= 0x7FF) {
      bytes.push(0xC0 | (codePoint >> 6));
      bytes.push(0x80 | (codePoint & 0x3F));
    } else if (codePoint <= 0xFFFF) {
      bytes.push(0xE0 | (codePoint >> 12));
      bytes.push(0x80 | ((codePoint >> 6) & 0x3F));
      bytes.push(0x80 | (codePoint & 0x3F));
    } else {
      bytes.push(0xF0 | (codePoint >> 18));
      bytes.push(0x80 | ((codePoint >> 12) & 0x3F));
      bytes.push(0x80 | ((codePoint >> 6) & 0x3F));
      bytes.push(0x80 | (codePoint & 0x3F));
    }
  }
}
