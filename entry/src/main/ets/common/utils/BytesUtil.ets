/*
 * YaoCore C-01 byte/hex helpers.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §4.1.6, §4.3 invariants 5/8
 */
import { AppErrors } from '../types/AppError';
import { Utf8 } from './Utf8';

export class BytesUtil {
  static hexLower(bytes: Uint8Array): string {
    const digits = '0123456789abcdef';
    let result = '';
    for (let index = 0; index < bytes.length; index++) {
      const value = bytes[index];
      result += digits.charAt((value >> 4) & 0x0F);
      result += digits.charAt(value & 0x0F);
    }
    return result;
  }

  static hexToBytes(hex: string): Uint8Array {
    return BytesUtil.decodeHex(hex, false);
  }

  static hexToBytesStrictLower(hex: string): Uint8Array {
    return BytesUtil.decodeHex(hex, true);
  }

  static concat(parts: ReadonlyArray<Uint8Array>): Uint8Array {
    let total = 0;
    for (let index = 0; index < parts.length; index++) {
      total += parts[index].length;
    }
    const result = new Uint8Array(total);
    let offset = 0;
    for (let index = 0; index < parts.length; index++) {
      const part = parts[index];
      for (let i = 0; i < part.length; i++) {
        result[offset + i] = part[i];
      }
      offset += part.length;
    }
    return result;
  }

  static utf8(text: string): Uint8Array {
    return Utf8.encode(text);
  }

  static fromUtf8(bytes: Uint8Array): string {
    return Utf8.decode(bytes);
  }

  static zeroize(bytes: Uint8Array): void {
    bytes.fill(0);
  }

  static copyOf(bytes: Uint8Array): Uint8Array {
    const copy = new Uint8Array(bytes.length);
    for (let index = 0; index < bytes.length; index++) {
      copy[index] = bytes[index];
    }
    return copy;
  }

  private static decodeHex(hex: string, strictLower: boolean): Uint8Array {
    if (hex.length % 2 !== 0) {
      throw AppErrors.of('SECRET_ENCODING_INVALID', []);
    }
    const result = new Uint8Array(hex.length / 2);
    for (let index = 0; index < hex.length; index += 2) {
      const high = BytesUtil.hexDigit(hex.charCodeAt(index), strictLower);
      const low = BytesUtil.hexDigit(hex.charCodeAt(index + 1), strictLower);
      if (high < 0 || low < 0) {
        throw AppErrors.of('SECRET_ENCODING_INVALID', []);
      }
      result[index / 2] = (high << 4) | low;
    }
    return result;
  }

  private static hexDigit(code: number, strictLower: boolean): number {
    if (code >= 0x30 && code <= 0x39) {
      return code - 0x30;
    }
    if (!strictLower && code >= 0x41 && code <= 0x46) {
      return code - 0x41 + 10;
    }
    if (code >= 0x61 && code <= 0x66) {
      return code - 0x61 + 10;
    }
    return -1;
  }
}
