/*
 * YaoCore C-04 X25519 DER <-> raw codec.
 * Producer: agent:implementation-engineer | Task: T-07 / wp-016-security
 * Contract: DES-A §7.1.3, §7.3-4; BLE §4.3
 *
 * X25519 raw keys are 32 bytes, RFC 7748 little-endian. Platform APIs consume
 * SubjectPublicKeyInfo / PKCS#8 DER, so the fixed wrappers below are applied
 * without accepting trailing data or alternate lengths.
 */
import { AppErrors } from '../../common/types/AppError';
import { BytesUtil } from '../../common/utils/BytesUtil';

export class X25519KeyCodec {
  // 30 2a 30 05 06 03 2b 65 6e 03 21 00
  static readonly SPKI_PREFIX: Uint8Array = new Uint8Array([
    0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65,
    0x6e, 0x03, 0x21, 0x00
  ]);

  // 30 2e 02 01 00 30 05 06 03 2b 65 6e 04 22 04 20
  static readonly PKCS8_PREFIX: Uint8Array = new Uint8Array([
    0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06,
    0x03, 0x2b, 0x65, 0x6e, 0x04, 0x22, 0x04, 0x20
  ]);

  static derToRawPublicKey(der: Uint8Array): Uint8Array {
    return X25519KeyCodec.stripPrefix(der, X25519KeyCodec.SPKI_PREFIX, 'x25519PublicKey');
  }

  static rawToDerPublicKey(raw: Uint8Array): Uint8Array {
    return X25519KeyCodec.wrapRaw(raw, X25519KeyCodec.SPKI_PREFIX, 'x25519PublicKey');
  }

  static derToRawPrivateKey(der: Uint8Array): Uint8Array {
    return X25519KeyCodec.stripPrefix(der, X25519KeyCodec.PKCS8_PREFIX, 'x25519PrivateKey');
  }

  static rawToDerPrivateKey(raw: Uint8Array): Uint8Array {
    return X25519KeyCodec.wrapRaw(raw, X25519KeyCodec.PKCS8_PREFIX, 'x25519PrivateKey');
  }

  private static stripPrefix(der: Uint8Array, prefix: Uint8Array, field: string): Uint8Array {
    if (der.length !== prefix.length + 32) {
      throw AppErrors.security('CRYPTO_INVALID_KEY', field);
    }
    for (let index = 0; index < prefix.length; index++) {
      if (der[index] !== prefix[index]) {
        throw AppErrors.security('CRYPTO_INVALID_KEY', field);
      }
    }
    const raw = new Uint8Array(32);
    raw.set(der.subarray(prefix.length));
    return raw;
  }

  private static wrapRaw(raw: Uint8Array, prefix: Uint8Array, field: string): Uint8Array {
    if (raw.length !== 32) {
      throw AppErrors.security('CRYPTO_INVALID_KEY', field);
    }
    return BytesUtil.concat([prefix, raw]);
  }
}
