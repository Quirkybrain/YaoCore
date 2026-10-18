/*
 * YaoCore C-04 low-level crypto provider seam.
 * Producer: agent:implementation-engineer | Task: T-07 / wp-016-security
 * Contract: DES-A §7.1.2, §7.2, §7.4
 *
 * `OhosCryptoProvider` is the only production file allowed to import
 * @ohos.security.cryptoFramework (DES-A §7.4). Host tests inject an
 * independent pure-TS provider through this seam.
 */
import type { GcmCiphertext, X25519KeyHandle, X25519KeyPair } from '../../contracts/CryptoPort';

export enum CryptoErrorKind {
  UNAVAILABLE = 'UNAVAILABLE',
  INVALID_KEY = 'INVALID_KEY',
  OPERATION_FAILED = 'OPERATION_FAILED',
  AUTH_TAG = 'AUTH_TAG'
}

/** Sanitized provider failure. Platform messages never leave the adapter. */
export class CryptoProviderError extends Error {
  readonly kind: CryptoErrorKind;

  constructor(kind: CryptoErrorKind) {
    super('crypto provider operation failed');
    this.name = 'CryptoProviderError';
    this.kind = kind;
  }
}

/** Provider-owned continuous CTR stream. State/accounting live in CryptoService. */
export interface CryptoProviderAesCtrStream {
  process(data: Uint8Array): Promise<Uint8Array>;
  destroy(): void;
}

/**
 * Raw platform primitive seam. Parameter validation/error mapping belong to
 * CryptoService, so every provider implementation stays replaceable.
 */
export interface CryptoProvider {
  sha256(data: Uint8Array): Promise<Uint8Array>;
  hmacSha256(key: Uint8Array, data: Uint8Array): Promise<Uint8Array>;
  hkdfSha256(ikm: Uint8Array, salt: Uint8Array, info: Uint8Array, length: number): Promise<Uint8Array>;
  pbkdf2Sha256(password: Uint8Array, salt: Uint8Array, iterations: number,
    length: number): Promise<Uint8Array>;

  generateX25519KeyPair(): Promise<X25519KeyPair>;
  importX25519PrivateRaw(raw: Uint8Array): Promise<X25519KeyHandle>;
  importX25519PublicRaw(raw: Uint8Array): Promise<X25519KeyHandle>;
  exportX25519PublicRaw(key: X25519KeyHandle): Promise<Uint8Array>;
  computeX25519(privateKey: X25519KeyHandle, peerPublicRaw: Uint8Array): Promise<Uint8Array>;

  createAesCtrStream(key: Uint8Array, iv: Uint8Array): Promise<CryptoProviderAesCtrStream>;
  encryptAesGcm(key: Uint8Array, iv: Uint8Array, aad: Uint8Array,
    plaintext: Uint8Array): Promise<GcmCiphertext>;
  decryptAesGcm(key: Uint8Array, iv: Uint8Array, aad: Uint8Array,
    ciphertext: Uint8Array, tag: Uint8Array): Promise<Uint8Array>;

  randomBytes(length: number): Promise<Uint8Array>;
}
