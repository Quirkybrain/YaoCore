/*
 * YaoCore PB-03 SPKI pin helper (path B).
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §19.1/§19.3; ADR-002 §4.1
 *
 * Shared by SocketTlsPinVerifier (standalone probe) and OhosHttpTransport
 * (same-connection verification before the first HTTP byte is written).
 * COMPILED_ONLY: imports @ohos.security.cert.
 */
import { socket } from '@kit.NetworkKit';
import { cert } from '@kit.DeviceCertificateKit';
import { AppErrors } from '../../../common/types/AppError';
import { ProtocolConstants } from '../../../common/constants/ProtocolConstants';
import { BytesUtil } from '../../../common/utils/BytesUtil';
import type { CryptoPort } from '../../../contracts/CryptoPort';

export class TlsPinCheck {
  static validatePins(pins: ReadonlyArray<string>): void {
    if (pins.length < 1 || pins.length > ProtocolConstants.MAX_PIN_COUNT) {
      throw AppErrors.of('TLS_PIN_CONFIG_INVALID', []);
    }
    for (let index = 0; index < pins.length; index++) {
      if (!ProtocolConstants.PIN_PATTERN.test(pins[index])) {
        throw AppErrors.of('TLS_PIN_CONFIG_INVALID', []);
      }
    }
  }

  /** SHA-256 over X.509 SubjectPublicKeyInfo DER, 64 lowercase hex. */
  static async spkiSha256Hex(crypto: CryptoPort,
    raw: socket.X509CertRawData): Promise<string> {
    const x509 = await cert.createX509Cert({
      data: raw.data,
      encodingFormat: raw.encodingFormat
    });
    const publicKey = x509.getPublicKey();
    const spki = publicKey.getEncoded();
    if (spki.data.length === 0) {
      throw AppErrors.of('TLS_HANDSHAKE_FAILED', []);
    }
    const digest = await crypto.sha256(spki.data);
    if (digest.length !== 32) {
      throw AppErrors.of('TLS_HANDSHAKE_FAILED', []);
    }
    return BytesUtil.hexLower(digest);
  }

  /** Constant-time comparison; returns the matched pin or undefined. */
  static async matchPin(crypto: CryptoPort, digestHex: string,
    pins: ReadonlyArray<string>): Promise<string | undefined> {
    const digestBytes = BytesUtil.hexToBytes(digestHex);
    for (let index = 0; index < pins.length; index++) {
      const pinBytes = BytesUtil.hexToBytesStrictLower(pins[index]);
      if (crypto.constantTimeEqual(digestBytes, pinBytes)) {
        return pins[index];
      }
    }
    return undefined;
  }
}
