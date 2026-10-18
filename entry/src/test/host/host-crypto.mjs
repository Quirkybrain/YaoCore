/*
 * YaoCore T-13 host CryptoPort adapter (test-only).
 * Producer: agent:implementation-engineer | Task: T-13 / wp-049-family
 *
 * PUBLIC TEST DATA ONLY. Node's crypto is an independent oracle for
 * SHA/HMAC/HKDF/PBKDF2/X25519/AES-256-GCM so the product InviteService and
 * AuthService can be exercised end-to-end on the host. The file is never
 * imported by entry/src/main/ets/**. Device-only evidence remains BLOCKED.
 */
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  createHmac,
  createPrivateKey,
  createPublicKey,
  diffieHellman,
  generateKeyPairSync,
  hkdfSync,
  pbkdf2Sync,
  randomBytes as nodeRandomBytes,
} from 'node:crypto';

import { AppErrors } from '../../main/ets/common/types/AppError.ets';
import { GcmCiphertext, X25519KeyPair } from '../../main/ets/contracts/CryptoPort.ets';
import { X25519KeyCodec } from '../../main/ets/service/crypto/X25519KeyCodec.ets';

class HostX25519Handle {
  algorithm = 'X25519';
  privateKey;
  publicKey;
  publicRaw;
}

const zero = (bytes) => {
  if (bytes !== undefined) {
    bytes.fill(0);
  }
};

export class HostCrypto {
  async sha256(data) {
    return new Uint8Array(createHash('sha256').update(Buffer.from(data)).digest());
  }

  async hmacSha256(key, data) {
    return new Uint8Array(createHmac('sha256', Buffer.from(key))
      .update(Buffer.from(data)).digest());
  }

  async hkdfSha256(ikm, salt, info, length) {
    const output = hkdfSync('sha256', Buffer.from(ikm), Buffer.from(salt),
      Buffer.from(info), length);
    return new Uint8Array(output);
  }

  async pbkdf2Sha256(password, salt, iterations, length) {
    return new Uint8Array(pbkdf2Sync(Buffer.from(password), Buffer.from(salt), iterations,
      length, 'sha256'));
  }

  async generateX25519KeyPair() {
    const pair = generateKeyPairSync('x25519');
    const handle = new HostX25519Handle();
    handle.privateKey = pair.privateKey;
    handle.publicKey = pair.publicKey;
    const publicDer = pair.publicKey.export({ format: 'der', type: 'spki' });
    handle.publicRaw = X25519KeyCodec.derToRawPublicKey(new Uint8Array(publicDer));
    return new X25519KeyPair(handle, handle.publicRaw);
  }

  async importX25519PrivateRaw(raw) {
    const der = X25519KeyCodec.rawToDerPrivateKey(raw);
    try {
      const privateKey = createPrivateKey({ key: Buffer.from(der), format: 'der',
        type: 'pkcs8' });
      const publicKey = createPublicKey(privateKey);
      const publicDer = publicKey.export({ format: 'der', type: 'spki' });
      const handle = new HostX25519Handle();
      handle.privateKey = privateKey;
      handle.publicKey = publicKey;
      handle.publicRaw = X25519KeyCodec.derToRawPublicKey(new Uint8Array(publicDer));
      return handle;
    } finally {
      zero(der);
    }
  }

  async importX25519PublicRaw(raw) {
    const der = X25519KeyCodec.rawToDerPublicKey(raw);
    try {
      const publicKey = createPublicKey({ key: Buffer.from(der), format: 'der',
        type: 'spki' });
      const handle = new HostX25519Handle();
      handle.publicKey = publicKey;
      handle.publicRaw = new Uint8Array(raw);
      return handle;
    } finally {
      zero(der);
    }
  }

  async exportX25519PublicRaw(key) {
    if (!(key instanceof HostX25519Handle)) {
      throw AppErrors.security('CRYPTO_INVALID_KEY', 'x25519Key');
    }
    if (key.publicRaw !== undefined) {
      return new Uint8Array(key.publicRaw);
    }
    if (key.publicKey === undefined) {
      throw AppErrors.security('CRYPTO_INVALID_KEY', 'x25519PublicKey');
    }
    const der = key.publicKey.export({ format: 'der', type: 'spki' });
    return X25519KeyCodec.derToRawPublicKey(new Uint8Array(der));
  }

  async computeX25519(privateKey, peerPublicRaw) {
    if (!(privateKey instanceof HostX25519Handle) || privateKey.privateKey === undefined) {
      throw AppErrors.security('CRYPTO_INVALID_KEY', 'x25519PrivateKey');
    }
    const der = X25519KeyCodec.rawToDerPublicKey(peerPublicRaw);
    try {
      const peer = createPublicKey({ key: Buffer.from(der), format: 'der', type: 'spki' });
      const shared = new Uint8Array(diffieHellman({
        privateKey: privateKey.privateKey,
        publicKey: peer,
      }));
      let accumulator = 0;
      for (let index = 0; index < shared.length; index++) {
        accumulator |= shared[index];
      }
      if (accumulator === 0) {
        zero(shared);
        throw AppErrors.security('CRYPTO_INVALID_KEY', 'x25519SharedSecret');
      }
      return shared;
    } finally {
      zero(der);
    }
  }

  async encryptAesGcm(key, iv, aad, plaintext) {
    const cipher = createCipheriv('aes-256-gcm', Buffer.from(key), Buffer.from(iv),
      { authTagLength: 16 });
    cipher.setAAD(Buffer.from(aad));
    const ciphertext = Buffer.concat([cipher.update(Buffer.from(plaintext)), cipher.final()]);
    return new GcmCiphertext(new Uint8Array(ciphertext), new Uint8Array(cipher.getAuthTag()));
  }

  async decryptAesGcm(key, iv, aad, ciphertext, tag) {
    try {
      const decipher = createDecipheriv('aes-256-gcm', Buffer.from(key), Buffer.from(iv),
        { authTagLength: 16 });
      decipher.setAAD(Buffer.from(aad));
      decipher.setAuthTag(Buffer.from(tag));
      const plaintext = Buffer.concat([decipher.update(Buffer.from(ciphertext)),
        decipher.final()]);
      return new Uint8Array(plaintext);
    } catch (error) {
      throw AppErrors.security('CRYPTO_TAG_MISMATCH');
    }
  }

  async randomBytes(length) {
    return new Uint8Array(nodeRandomBytes(length));
  }

  constantTimeEqual(a, b) {
    const max = a.length > b.length ? a.length : b.length;
    let accumulator = a.length === b.length ? 0 : 1;
    for (let index = 0; index < max; index++) {
      const left = index < a.length ? a[index] : 0;
      const right = index < b.length ? b[index] : 0;
      accumulator |= left ^ right;
    }
    return accumulator === 0;
  }
}
