/*
 * YaoCore C-04 independent host crypto provider.
 * Producer: agent:implementation-engineer | Task: T-07 / wp-016-security
 * Contract: DES-A §7.4 (TestCryptoProvider seam)
 *
 * PUBLIC TEST DATA ONLY. This is a test-only pure-TS implementation of
 * SHA-256/HMAC/HKDF/PBKDF2 used to exercise product C-05 logic on the host.
 * It is never imported by entry/src/main/ets/**. X25519/CTR/GCM deliberately
 * throw CRYPTO_UNAVAILABLE; those primitives are device-only evidence.
 */
import {
  CryptoErrorKind,
  CryptoProviderError
} from '../../main/ets/service/crypto/CryptoProvider';
import type {
  CryptoProvider,
  CryptoProviderAesCtrStream
} from '../../main/ets/service/crypto/CryptoProvider';
import { GcmCiphertext, X25519KeyPair } from '../../main/ets/service/crypto/CryptoPort';
import type { X25519KeyHandle } from '../../main/ets/service/crypto/CryptoPort';

const SHA256_BLOCK: number = 64;

class Sha256 {
  private static readonly K: ReadonlyArray<number> = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ];

  static digest(data: Uint8Array): Uint8Array {
    const bitLength = data.length * 8;
    const paddedLength = (Math.floor((data.length + 8) / SHA256_BLOCK) + 1) * SHA256_BLOCK;
    const padded = new Uint8Array(paddedLength);
    padded.set(data);
    padded[data.length] = 0x80;
    const high = Math.floor(bitLength / 4294967296);
    const low = bitLength % 4294967296;
    padded[paddedLength - 8] = (high >>> 24) & 0xff;
    padded[paddedLength - 7] = (high >>> 16) & 0xff;
    padded[paddedLength - 6] = (high >>> 8) & 0xff;
    padded[paddedLength - 5] = high & 0xff;
    padded[paddedLength - 4] = (low >>> 24) & 0xff;
    padded[paddedLength - 3] = (low >>> 16) & 0xff;
    padded[paddedLength - 2] = (low >>> 8) & 0xff;
    padded[paddedLength - 1] = low & 0xff;

    let h0 = 0x6a09e667;
    let h1 = 0xbb67ae85;
    let h2 = 0x3c6ef372;
    let h3 = 0xa54ff53a;
    let h4 = 0x510e527f;
    let h5 = 0x9b05688c;
    let h6 = 0x1f83d9ab;
    let h7 = 0x5be0cd19;
    const w = new Int32Array(64);

    for (let offset = 0; offset < padded.length; offset += SHA256_BLOCK) {
      for (let i = 0; i < 16; i++) {
        const base = offset + i * 4;
        w[i] = (padded[base] << 24) | (padded[base + 1] << 16) |
          (padded[base + 2] << 8) | padded[base + 3];
      }
      for (let i = 16; i < 64; i++) {
        const s0 = Sha256.rotr(w[i - 15], 7) ^ Sha256.rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        const s1 = Sha256.rotr(w[i - 2], 17) ^ Sha256.rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0;
      }
      let a = h0;
      let b = h1;
      let c = h2;
      let d = h3;
      let e = h4;
      let f = h5;
      let g = h6;
      let h = h7;
      for (let i = 0; i < 64; i++) {
        const sigma1 = Sha256.rotr(e, 6) ^ Sha256.rotr(e, 11) ^ Sha256.rotr(e, 25);
        const choose = (e & f) ^ (~e & g);
        const temp1 = (h + sigma1 + choose + Sha256.K[i] + w[i]) | 0;
        const sigma0 = Sha256.rotr(a, 2) ^ Sha256.rotr(a, 13) ^ Sha256.rotr(a, 22);
        const majority = (a & b) ^ (a & c) ^ (b & c);
        const temp2 = (sigma0 + majority) | 0;
        h = g;
        g = f;
        f = e;
        e = (d + temp1) | 0;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) | 0;
      }
      h0 = (h0 + a) | 0;
      h1 = (h1 + b) | 0;
      h2 = (h2 + c) | 0;
      h3 = (h3 + d) | 0;
      h4 = (h4 + e) | 0;
      h5 = (h5 + f) | 0;
      h6 = (h6 + g) | 0;
      h7 = (h7 + h) | 0;
    }

    const output = new Uint8Array(32);
    Sha256.writeWord(output, 0, h0);
    Sha256.writeWord(output, 4, h1);
    Sha256.writeWord(output, 8, h2);
    Sha256.writeWord(output, 12, h3);
    Sha256.writeWord(output, 16, h4);
    Sha256.writeWord(output, 20, h5);
    Sha256.writeWord(output, 24, h6);
    Sha256.writeWord(output, 28, h7);
    return output;
  }

  private static rotr(value: number, bits: number): number {
    return (value >>> bits) | (value << (32 - bits));
  }

  private static writeWord(target: Uint8Array, offset: number, value: number): void {
    target[offset] = (value >>> 24) & 0xff;
    target[offset + 1] = (value >>> 16) & 0xff;
    target[offset + 2] = (value >>> 8) & 0xff;
    target[offset + 3] = value & 0xff;
  }
}

function concatBytes(parts: ReadonlyArray<Uint8Array>): Uint8Array {
  let total = 0;
  for (let index = 0; index < parts.length; index++) {
    total += parts[index].length;
  }
  const result = new Uint8Array(total);
  let offset = 0;
  for (let index = 0; index < parts.length; index++) {
    result.set(parts[index], offset);
    offset += parts[index].length;
  }
  return result;
}

function hmacSha256(key: Uint8Array, data: Uint8Array): Uint8Array {
  const keyBytes = key.length > SHA256_BLOCK ? Sha256.digest(key) : key;
  const innerPad = new Uint8Array(SHA256_BLOCK);
  const outerPad = new Uint8Array(SHA256_BLOCK);
  for (let index = 0; index < SHA256_BLOCK; index++) {
    const value = index < keyBytes.length ? keyBytes[index] : 0;
    innerPad[index] = value ^ 0x36;
    outerPad[index] = value ^ 0x5c;
  }
  const inner = Sha256.digest(concatBytes([innerPad, data]));
  return Sha256.digest(concatBytes([outerPad, inner]));
}

function hkdfSha256(ikm: Uint8Array, salt: Uint8Array, info: Uint8Array,
  length: number): Uint8Array {
  const effectiveSalt = salt.length === 0 ? new Uint8Array(32) : salt;
  const prk = hmacSha256(effectiveSalt, ikm);
  const blocks = Math.ceil(length / 32);
  const output = new Uint8Array(length);
  let previous = new Uint8Array(0);
  let offset = 0;
  for (let counter = 1; counter <= blocks; counter++) {
    const input = concatBytes([previous, info, new Uint8Array([counter & 0xff])]);
    previous = hmacSha256(prk, input);
    const copyLength = Math.min(32, length - offset);
    output.set(previous.subarray(0, copyLength), offset);
    offset += copyLength;
  }
  return output;
}

function pbkdf2Sha256(password: Uint8Array, salt: Uint8Array, iterations: number,
  length: number): Uint8Array {
  const blocks = Math.ceil(length / 32);
  const output = new Uint8Array(length);
  let offset = 0;
  for (let block = 1; block <= blocks; block++) {
    const counter = new Uint8Array([
      (block >>> 24) & 0xff, (block >>> 16) & 0xff, (block >>> 8) & 0xff, block & 0xff
    ]);
    let u = hmacSha256(password, concatBytes([salt, counter]));
    const t = new Uint8Array(u.length);
    t.set(u);
    for (let round = 1; round < iterations; round++) {
      u = hmacSha256(password, u);
      for (let index = 0; index < t.length; index++) {
        t[index] ^= u[index];
      }
    }
    const copyLength = Math.min(32, length - offset);
    output.set(t.subarray(0, copyLength), offset);
    offset += copyLength;
  }
  return output;
}

export class TestCryptoProvider implements CryptoProvider {
  async sha256(data: Uint8Array): Promise<Uint8Array> {
    return Sha256.digest(data);
  }

  async hmacSha256(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
    return hmacSha256(key, data);
  }

  async hkdfSha256(ikm: Uint8Array, salt: Uint8Array, info: Uint8Array,
    length: number): Promise<Uint8Array> {
    return hkdfSha256(ikm, salt, info, length);
  }

  async pbkdf2Sha256(password: Uint8Array, salt: Uint8Array, iterations: number,
    length: number): Promise<Uint8Array> {
    return pbkdf2Sha256(password, salt, iterations, length);
  }

  async generateX25519KeyPair(): Promise<X25519KeyPair> {
    throw new CryptoProviderError(CryptoErrorKind.UNAVAILABLE);
  }

  async importX25519PrivateRaw(raw: Uint8Array): Promise<X25519KeyHandle> {
    throw new CryptoProviderError(CryptoErrorKind.UNAVAILABLE);
  }

  async importX25519PublicRaw(raw: Uint8Array): Promise<X25519KeyHandle> {
    throw new CryptoProviderError(CryptoErrorKind.UNAVAILABLE);
  }

  async exportX25519PublicRaw(key: X25519KeyHandle): Promise<Uint8Array> {
    throw new CryptoProviderError(CryptoErrorKind.UNAVAILABLE);
  }

  async computeX25519(privateKey: X25519KeyHandle, peerPublicRaw: Uint8Array): Promise<Uint8Array> {
    throw new CryptoProviderError(CryptoErrorKind.UNAVAILABLE);
  }

  async createAesCtrStream(key: Uint8Array, iv: Uint8Array): Promise<CryptoProviderAesCtrStream> {
    throw new CryptoProviderError(CryptoErrorKind.UNAVAILABLE);
  }

  async encryptAesGcm(key: Uint8Array, iv: Uint8Array, aad: Uint8Array,
    plaintext: Uint8Array): Promise<GcmCiphertext> {
    throw new CryptoProviderError(CryptoErrorKind.UNAVAILABLE);
  }

  async decryptAesGcm(key: Uint8Array, iv: Uint8Array, aad: Uint8Array,
    ciphertext: Uint8Array, tag: Uint8Array): Promise<Uint8Array> {
    throw new CryptoProviderError(CryptoErrorKind.UNAVAILABLE);
  }

  async randomBytes(length: number): Promise<Uint8Array> {
    throw new CryptoProviderError(CryptoErrorKind.UNAVAILABLE);
  }
}
