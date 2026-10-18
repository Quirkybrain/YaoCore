/*
 * YaoCore C-04 CryptoService.
 * Producer: agent:implementation-engineer | Task: T-07 / wp-016-security
 * Contract: DES-A §7.1, §7.2, §7.3
 *
 * Parameter validation + platform delegation + AppError mapping + CTR stream
 * state. No protocol or business semantics live here. AES-256-GCM is reserved
 * for the ADR-003 invitation container and MUST NOT be used for LAN control
 * payloads (ADR-002 §5, EXT-GCM-001).
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { AesCtrState, GcmCiphertext, X25519KeyPair } from '../../contracts/CryptoPort';
import type { AesCtrStream, CryptoPort, X25519KeyHandle } from '../../contracts/CryptoPort';
import {
  CryptoErrorKind,
  CryptoProviderError
} from './CryptoProvider';
import type {
  CryptoProvider,
  CryptoProviderAesCtrStream
} from './CryptoProvider';

const X25519_RAW_LENGTH: number = 32;
const AES_KEY_LENGTH: number = 32;
const AES_CTR_IV_LENGTH: number = 16;
const AES_GCM_IV_LENGTH: number = 12;
const AES_GCM_TAG_LENGTH: number = 16;
const PBKDF2_MIN_ITERATIONS: number = 120000;
const PBKDF2_SALT_LENGTH: number = 16;
const PBKDF2_OUTPUT_LENGTH: number = 32;
const HKDF_MAX_LENGTH: number = 8160;
const MAX_RANDOM_BYTES: number = 1048576;

export class CryptoService implements CryptoPort {
  private readonly provider: CryptoProvider;

  constructor(provider: CryptoProvider) {
    this.provider = provider;
  }

  async sha256(data: Uint8Array): Promise<Uint8Array> {
    try {
      const digest = await this.provider.sha256(data);
      return CryptoService.requireLength(digest, 32, 'sha256');
    } catch (error) {
      throw mapCryptoError(error as Error);
    }
  }

  async hmacSha256(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
    try {
      const mac = await this.provider.hmacSha256(key, data);
      return CryptoService.requireLength(mac, 32, 'hmacSha256');
    } catch (error) {
      throw mapCryptoError(error as Error);
    }
  }

  async hkdfSha256(ikm: Uint8Array, salt: Uint8Array, info: Uint8Array,
    length: number): Promise<Uint8Array> {
    if (!Number.isInteger(length) || length < 1 || length > HKDF_MAX_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'hkdfLength');
    }
    try {
      const derived = await this.provider.hkdfSha256(ikm, salt, info, length);
      return CryptoService.requireLength(derived, length, 'hkdfSha256');
    } catch (error) {
      throw mapCryptoError(error as Error);
    }
  }

  async pbkdf2Sha256(password: Uint8Array, salt: Uint8Array, iterations: number,
    length: number): Promise<Uint8Array> {
    if (!Number.isInteger(iterations) || iterations < PBKDF2_MIN_ITERATIONS) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'iterations');
    }
    if (!Number.isInteger(length) || length !== PBKDF2_OUTPUT_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'pbkdf2Length');
    }
    if (salt.length !== PBKDF2_SALT_LENGTH) {
      throw AppErrors.security('CRYPTO_INVALID_KEY', 'pbkdf2Salt');
    }
    try {
      const derived = await this.provider.pbkdf2Sha256(password, salt, iterations, length);
      return CryptoService.requireLength(derived, length, 'pbkdf2Sha256');
    } catch (error) {
      throw mapCryptoError(error as Error);
    }
  }

  async generateX25519KeyPair(): Promise<X25519KeyPair> {
    try {
      const pair = await this.provider.generateX25519KeyPair();
      if (pair.publicKeyRaw.length !== X25519_RAW_LENGTH) {
        throw new CryptoProviderError(CryptoErrorKind.OPERATION_FAILED);
      }
      return pair;
    } catch (error) {
      throw mapCryptoError(error as Error);
    }
  }

  async importX25519PrivateRaw(raw: Uint8Array): Promise<X25519KeyHandle> {
    CryptoService.requireRawKey(raw, 'x25519PrivateKey');
    try {
      return await this.provider.importX25519PrivateRaw(raw);
    } catch (error) {
      throw mapCryptoError(error as Error);
    }
  }

  async importX25519PublicRaw(raw: Uint8Array): Promise<X25519KeyHandle> {
    CryptoService.requireRawKey(raw, 'x25519PublicKey');
    try {
      return await this.provider.importX25519PublicRaw(raw);
    } catch (error) {
      throw mapCryptoError(error as Error);
    }
  }

  async exportX25519PublicRaw(key: X25519KeyHandle): Promise<Uint8Array> {
    if (key.algorithm !== 'X25519') {
      throw AppErrors.security('CRYPTO_INVALID_KEY', 'x25519Key');
    }
    try {
      const raw = await this.provider.exportX25519PublicRaw(key);
      return CryptoService.requireLength(raw, X25519_RAW_LENGTH, 'x25519PublicKey');
    } catch (error) {
      throw mapCryptoError(error as Error);
    }
  }

  async computeX25519(privateKey: X25519KeyHandle, peerPublicRaw: Uint8Array): Promise<Uint8Array> {
    if (privateKey.algorithm !== 'X25519') {
      throw AppErrors.security('CRYPTO_INVALID_KEY', 'x25519Key');
    }
    CryptoService.requireRawKey(peerPublicRaw, 'x25519PeerPublicKey');
    try {
      const shared = await this.provider.computeX25519(privateKey, peerPublicRaw);
      if (shared.length !== X25519_RAW_LENGTH) {
        throw new CryptoProviderError(CryptoErrorKind.OPERATION_FAILED);
      }
      if (CryptoService.isAllZero(shared)) {
        shared.fill(0);
        throw AppErrors.security('CRYPTO_INVALID_KEY', 'x25519SharedSecret');
      }
      return shared;
    } catch (error) {
      throw mapCryptoError(error as Error);
    }
  }

  async createAesCtrStream(key: Uint8Array, iv: Uint8Array): Promise<AesCtrStream> {
    if (key.length !== AES_KEY_LENGTH) {
      throw AppErrors.security('CRYPTO_INVALID_KEY', 'aesKey');
    }
    if (iv.length !== AES_CTR_IV_LENGTH) {
      throw AppErrors.security('CRYPTO_INVALID_KEY', 'aesIv');
    }
    try {
      const rawStream = await this.provider.createAesCtrStream(key, iv);
      return new AesCtrStreamImpl(rawStream);
    } catch (error) {
      throw mapCryptoError(error as Error);
    }
  }

  async encryptAesGcm(key: Uint8Array, iv: Uint8Array, aad: Uint8Array,
    plaintext: Uint8Array): Promise<GcmCiphertext> {
    CryptoService.validateGcmInputs(key, iv);
    try {
      const result = await this.provider.encryptAesGcm(key, iv, aad, plaintext);
      if (result.ciphertext.length !== plaintext.length || result.tag.length !== AES_GCM_TAG_LENGTH) {
        throw new CryptoProviderError(CryptoErrorKind.OPERATION_FAILED);
      }
      return result;
    } catch (error) {
      throw mapCryptoError(error as Error);
    }
  }

  async decryptAesGcm(key: Uint8Array, iv: Uint8Array, aad: Uint8Array,
    ciphertext: Uint8Array, tag: Uint8Array): Promise<Uint8Array> {
    CryptoService.validateGcmInputs(key, iv);
    if (tag.length !== AES_GCM_TAG_LENGTH) {
      throw AppErrors.security('CRYPTO_INVALID_KEY', 'gcmTag');
    }
    try {
      const plaintext = await this.provider.decryptAesGcm(key, iv, aad, ciphertext, tag);
      if (plaintext.length !== ciphertext.length) {
        throw new CryptoProviderError(CryptoErrorKind.OPERATION_FAILED);
      }
      return plaintext;
    } catch (error) {
      throw mapCryptoError(error as Error);
    }
  }

  async randomBytes(length: number): Promise<Uint8Array> {
    if (!Number.isInteger(length) || length < 1 || length > MAX_RANDOM_BYTES) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'randomLength');
    }
    try {
      const bytes = await this.provider.randomBytes(length);
      if (bytes.length !== length || CryptoService.isAllZero(bytes)) {
        throw new CryptoProviderError(CryptoErrorKind.OPERATION_FAILED);
      }
      return bytes;
    } catch (error) {
      throw mapCryptoError(error as Error);
    }
  }

  /**
   * Constant-time comparison (SC-15). Always scans max(a.length, b.length);
   * length mismatch is folded into the accumulator and never short-circuits.
   */
  constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
    const maxLength = a.length > b.length ? a.length : b.length;
    let difference = a.length ^ b.length;
    for (let index = 0; index < maxLength; index++) {
      const left = index < a.length ? a[index] : 0;
      const right = index < b.length ? b[index] : 0;
      difference |= left ^ right;
    }
    return difference === 0;
  }

  private static validateGcmInputs(key: Uint8Array, iv: Uint8Array): void {
    if (key.length !== AES_KEY_LENGTH) {
      throw AppErrors.security('CRYPTO_INVALID_KEY', 'aesKey');
    }
    if (iv.length !== AES_GCM_IV_LENGTH) {
      throw AppErrors.security('CRYPTO_INVALID_KEY', 'aesIv');
    }
  }

  private static requireRawKey(raw: Uint8Array, field: string): void {
    if (raw.length !== X25519_RAW_LENGTH) {
      throw AppErrors.security('CRYPTO_INVALID_KEY', field);
    }
  }

  private static requireLength(bytes: Uint8Array, expected: number, field: string): Uint8Array {
    if (bytes.length !== expected) {
      throw AppErrors.security('CRYPTO_OPERATION_FAILED', field);
    }
    return bytes;
  }

  private static isAllZero(bytes: Uint8Array): boolean {
    let accumulator = 0;
    for (let index = 0; index < bytes.length; index++) {
      accumulator |= bytes[index];
    }
    return accumulator === 0;
  }

}

function mapCryptoError(error: Error): AppError {
  if (error instanceof AppError) {
    return error;
  }
  if (error instanceof CryptoProviderError) {
    if (error.kind === CryptoErrorKind.UNAVAILABLE) {
      return AppErrors.security('CRYPTO_UNAVAILABLE');
    }
    if (error.kind === CryptoErrorKind.INVALID_KEY) {
      return AppErrors.security('CRYPTO_INVALID_KEY');
    }
    if (error.kind === CryptoErrorKind.AUTH_TAG) {
      return AppErrors.security('CRYPTO_TAG_MISMATCH');
    }
    return AppErrors.security('CRYPTO_OPERATION_FAILED');
  }
  return AppErrors.security('CRYPTO_OPERATION_FAILED');
}

/**
 * Stateful CTR wrapper. Any provider failure is terminal (BROKEN) and the
 * underlying stream is destroyed; callers must rebuild the session.
 */
class AesCtrStreamImpl implements AesCtrStream {
  private readonly raw: CryptoProviderAesCtrStream;
  private stateValue: AesCtrState = AesCtrState.ACTIVE;
  private processed: number = 0;

  constructor(raw: CryptoProviderAesCtrStream) {
    this.raw = raw;
  }

  get state(): AesCtrState {
    return this.stateValue;
  }

  get bytesProcessed(): number {
    return this.processed;
  }

  async process(data: Uint8Array): Promise<Uint8Array> {
    if (this.stateValue !== AesCtrState.ACTIVE) {
      throw AppErrors.security('CRYPTO_STREAM_BROKEN', 'aesCtr');
    }
    try {
      const output = await this.raw.process(data);
      if (output.length !== data.length) {
        throw new CryptoProviderError(CryptoErrorKind.OPERATION_FAILED);
      }
      this.processed += data.length;
      return output;
    } catch (error) {
      this.stateValue = AesCtrState.BROKEN;
      this.raw.destroy();
      throw mapCryptoError(error as Error);
    }
  }

  destroy(): void {
    this.raw.destroy();
    if (this.stateValue === AesCtrState.ACTIVE) {
      this.stateValue = AesCtrState.DESTROYED;
    }
  }
}
