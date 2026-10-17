/*
 * YaoCore C-01 base64url codec (no padding).
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §4.1.6, §4.3 invariant 6
 *
 * The tool itself throws SECRET_ENCODING_INVALID. C-13 wraps that error as
 * INVITE_INVALID when decoding invitation payloads.
 */
import { AppError, AppErrors } from '../types/AppError';

export class Base64Url {
  private static readonly ALPHABET: string =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

  static encode(bytes: Uint8Array): string {
    let result = '';
    let index = 0;
    while (index < bytes.length) {
      const remaining = bytes.length - index;
      const first = bytes[index];
      const second = remaining > 1 ? bytes[index + 1] : 0;
      const third = remaining > 2 ? bytes[index + 2] : 0;
      result += Base64Url.ALPHABET.charAt((first >> 2) & 0x3F);
      result += Base64Url.ALPHABET.charAt(((first & 0x03) << 4) | ((second >> 4) & 0x0F));
      if (remaining > 1) {
        result += Base64Url.ALPHABET.charAt(((second & 0x0F) << 2) | ((third >> 6) & 0x03));
      }
      if (remaining > 2) {
        result += Base64Url.ALPHABET.charAt(third & 0x3F);
      }
      index += 3;
    }
    return result;
  }

  static decode(text: string): Uint8Array {
    if (text.length === 0) {
      // DES-A §4.2: an empty encoded value is not a valid secret payload.
      throw Base64Url.invalid();
    }
    if (text.length % 4 === 1) {
      throw Base64Url.invalid();
    }
    const bytes: number[] = [];
    let index = 0;
    while (index < text.length) {
      const remaining = text.length - index;
      const first = Base64Url.digit(text.charCodeAt(index));
      const second = Base64Url.digit(text.charCodeAt(index + 1));
      if (first < 0 || second < 0) {
        throw Base64Url.invalid();
      }
      bytes.push((first << 2) | ((second >> 4) & 0x03));
      if (remaining === 2) {
        if ((second & 0x0F) !== 0) {
          throw Base64Url.invalid();
        }
        break;
      }
      const third = Base64Url.digit(text.charCodeAt(index + 2));
      if (third < 0) {
        throw Base64Url.invalid();
      }
      bytes.push(((second & 0x0F) << 4) | ((third >> 2) & 0x0F));
      if (remaining === 3) {
        if ((third & 0x03) !== 0) {
          throw Base64Url.invalid();
        }
        break;
      }
      const fourth = Base64Url.digit(text.charCodeAt(index + 3));
      if (fourth < 0) {
        throw Base64Url.invalid();
      }
      bytes.push(((third & 0x03) << 6) | fourth);
      index += 4;
    }
    const result = new Uint8Array(bytes.length);
    for (let i = 0; i < bytes.length; i++) {
      result[i] = bytes[i];
    }
    return result;
  }

  static isValid(text: string): boolean {
    try {
      Base64Url.decode(text);
      return true;
    } catch (error) {
      return false;
    }
  }

  private static digit(code: number): number {
    if (code >= 0x41 && code <= 0x5A) {
      return code - 0x41;
    }
    if (code >= 0x61 && code <= 0x7A) {
      return code - 0x61 + 26;
    }
    if (code >= 0x30 && code <= 0x39) {
      return code - 0x30 + 52;
    }
    if (code === 0x2D) {
      return 62;
    }
    if (code === 0x5F) {
      return 63;
    }
    return -1;
  }

  private static invalid(): AppError {
    return AppErrors.of('SECRET_ENCODING_INVALID', []);
  }
}
