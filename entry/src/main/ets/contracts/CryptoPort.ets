/*
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-A §27.6.3 P1/P2.
 * YaoCore C-04 crypto port contract.
 * Producer: agent:implementation-engineer | Task: T-07 / wp-016-security
 * Contract: DES-A §7.1.1, §7.1.3, §7.3
 *
 * Port-only surface consumed by C-05/C-13/C-19. No @ohos import here.
 *
 * Location exception (T-07 R-08 / T-06 R-13): DES-A §7 nominally places this
 * port under contracts/**. T-07/T-19 write scopes do not include contracts/,
 * so it stays in service/crypto/ with no duplicate implementation; migrate the
 * file once C-17 assembles the composition root.
 */
import { AppErrors } from '../common/types/AppError';

export interface X25519KeyHandle {
  readonly algorithm: string; // 'X25519'
}

export class X25519KeyPair {
  readonly privateKey: X25519KeyHandle;
  readonly publicKeyRaw: Uint8Array; // 32 bytes, RFC 7748 little-endian

  constructor(privateKey: X25519KeyHandle, publicKeyRaw: Uint8Array) {
    if (publicKeyRaw.length !== 32) {
      throw AppErrors.security('CRYPTO_INVALID_KEY', 'x25519PublicKey');
    }
    const copy = new Uint8Array(32);
    copy.set(publicKeyRaw);
    this.privateKey = privateKey;
    this.publicKeyRaw = copy;
  }
}

export enum AesCtrState {
  ACTIVE = 'ACTIVE',
  BROKEN = 'BROKEN',
  DESTROYED = 'DESTROYED'
}

export interface AesCtrStream {
  readonly state: AesCtrState;
  readonly bytesProcessed: number;
  process(data: Uint8Array): Promise<Uint8Array>; // output length == input length
  destroy(): void;
}

export class GcmCiphertext {
  readonly ciphertext: Uint8Array;
  readonly tag: Uint8Array; // 16 bytes

  constructor(ciphertext: Uint8Array, tag: Uint8Array) {
    if (tag.length !== 16) {
      throw AppErrors.security('CRYPTO_INVALID_KEY', 'gcmTag');
    }
    const cipherCopy = new Uint8Array(ciphertext.length);
    cipherCopy.set(ciphertext);
    const tagCopy = new Uint8Array(16);
    tagCopy.set(tag);
    this.ciphertext = cipherCopy;
    this.tag = tagCopy;
  }
}

/**
 * Public crypto port (DES-A §7.1.1). Implementations must throw AppError,
 * never bare Error, and must never log key material or plaintext.
 */
export interface CryptoPort {
  sha256(data: Uint8Array): Promise<Uint8Array>;
  hmacSha256(key: Uint8Array, data: Uint8Array): Promise<Uint8Array>;
  hkdfSha256(ikm: Uint8Array, salt: Uint8Array, info: Uint8Array, length: number): Promise<Uint8Array>;
  pbkdf2Sha256(password: Uint8Array, salt: Uint8Array, iterations: number, length: number): Promise<Uint8Array>;

  generateX25519KeyPair(): Promise<X25519KeyPair>;
  importX25519PrivateRaw(raw: Uint8Array): Promise<X25519KeyHandle>;
  importX25519PublicRaw(raw: Uint8Array): Promise<X25519KeyHandle>;
  exportX25519PublicRaw(key: X25519KeyHandle): Promise<Uint8Array>;
  computeX25519(privateKey: X25519KeyHandle, peerPublicRaw: Uint8Array): Promise<Uint8Array>;

  createAesCtrStream(key: Uint8Array, iv: Uint8Array): Promise<AesCtrStream>;
  encryptAesGcm(key: Uint8Array, iv: Uint8Array, aad: Uint8Array,
    plaintext: Uint8Array): Promise<GcmCiphertext>;
  decryptAesGcm(key: Uint8Array, iv: Uint8Array, aad: Uint8Array,
    ciphertext: Uint8Array, tag: Uint8Array): Promise<Uint8Array>;

  randomBytes(length: number): Promise<Uint8Array>;
  constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean;
}
