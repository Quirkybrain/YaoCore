/*
 * YaoCore C-04 OhosCryptoProvider.
 * Producer: agent:implementation-engineer | Task: T-07 / wp-016-security
 * Contract: DES-A §7.1.2, §7.2, §7.4
 *
 * The ONLY production file importing @ohos.security.cryptoFramework. Platform
 * messages/codes are intentionally discarded: callers see sanitized
 * CryptoProviderError kinds only. X25519 keys stay inside opaque handles.
 */
import cryptoFramework from '@ohos.security.cryptoFramework';
import { X25519KeyCodec } from './X25519KeyCodec';
import { X25519KeyPair } from './CryptoPort';
import type { X25519KeyHandle } from './CryptoPort';
import {
  CryptoErrorKind,
  CryptoProviderAesCtrStream,
  CryptoProviderError
} from './CryptoProvider';
import type { CryptoProvider } from './CryptoProvider';
import { GcmCiphertext } from './CryptoPort';

class OhosX25519KeyHandle implements X25519KeyHandle {
  readonly algorithm: string = 'X25519';
  readonly priKey: cryptoFramework.PriKey | undefined;
  readonly pubKey: cryptoFramework.PubKey | undefined;

  constructor(priKey: cryptoFramework.PriKey | undefined, pubKey: cryptoFramework.PubKey | undefined) {
    this.priKey = priKey;
    this.pubKey = pubKey;
  }
}

class OhosAesCtrStream implements CryptoProviderAesCtrStream {
  private cipher: cryptoFramework.Cipher | undefined;
  private key: cryptoFramework.SymKey | undefined;
  private destroyed: boolean = false;

  constructor(cipher: cryptoFramework.Cipher, key: cryptoFramework.SymKey) {
    this.cipher = cipher;
    this.key = key;
  }

  async process(data: Uint8Array): Promise<Uint8Array> {
    if (this.destroyed || this.cipher === undefined) {
      throw new CryptoProviderError(CryptoErrorKind.OPERATION_FAILED);
    }
    try {
      const output = this.cipher.updateSync({ data: data });
      return output.data;
    } catch (error) {
      throw new CryptoProviderError(CryptoErrorKind.OPERATION_FAILED);
    }
  }

  destroy(): void {
    if (this.destroyed) {
      return;
    }
    this.destroyed = true;
    if (this.key !== undefined) {
      this.key.clearMem();
    }
    this.cipher = undefined;
    this.key = undefined;
  }
}

export class OhosCryptoProvider implements CryptoProvider {
  async sha256(data: Uint8Array): Promise<Uint8Array> {
    let digest: cryptoFramework.Md;
    try {
      digest = cryptoFramework.createMd('SHA256');
    } catch (error) {
      throw new CryptoProviderError(CryptoErrorKind.UNAVAILABLE);
    }
    try {
      digest.updateSync({ data: data });
      return digest.digestSync().data;
    } catch (error) {
      throw new CryptoProviderError(CryptoErrorKind.OPERATION_FAILED);
    }
  }

  async hmacSha256(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
    let mac: cryptoFramework.Mac;
    try {
      mac = cryptoFramework.createMac('SHA256');
    } catch (error) {
      throw new CryptoProviderError(CryptoErrorKind.UNAVAILABLE);
    }
    let symKey: cryptoFramework.SymKey | undefined = undefined;
    try {
      symKey = cryptoFramework.createSymKeyGenerator('HMAC').convertKeySync({ data: key });
      mac.initSync(symKey);
      mac.updateSync({ data: data });
      return mac.doFinalSync().data;
    } catch (error) {
      throw new CryptoProviderError(CryptoErrorKind.OPERATION_FAILED);
    } finally {
      if (symKey !== undefined) {
        symKey.clearMem();
      }
    }
  }

  async hkdfSha256(ikm: Uint8Array, salt: Uint8Array, info: Uint8Array,
    length: number): Promise<Uint8Array> {
    try {
      const kdf = cryptoFramework.createKdf('HKDF|SHA256');
      const spec: cryptoFramework.HKDFSpec = {
        algName: 'HKDF',
        key: ikm,
        salt: salt,
        info: info,
        keySize: length
      };
      const derived = await kdf.generateSecret(spec);
      return derived.data;
    } catch (error) {
      throw new CryptoProviderError(CryptoErrorKind.OPERATION_FAILED);
    }
  }

  async pbkdf2Sha256(password: Uint8Array, salt: Uint8Array, iterations: number,
    length: number): Promise<Uint8Array> {
    try {
      const kdf = cryptoFramework.createKdf('PBKDF2|SHA256');
      const spec: cryptoFramework.PBKDF2Spec = {
        algName: 'PBKDF2',
        password: password,
        salt: salt,
        iterations: iterations,
        keySize: length
      };
      const derived = await kdf.generateSecret(spec);
      return derived.data;
    } catch (error) {
      throw new CryptoProviderError(CryptoErrorKind.OPERATION_FAILED);
    }
  }

  async generateX25519KeyPair(): Promise<X25519KeyPair> {
    try {
      const generator = cryptoFramework.createAsyKeyGenerator('X25519');
      const pair = generator.generateKeyPairSync();
      const encoded = pair.pubKey.getEncoded().data;
      const raw = OhosCryptoProvider.publicDerToRaw(encoded);
      const handle = new OhosX25519KeyHandle(pair.priKey, pair.pubKey);
      return new X25519KeyPair(handle, raw);
    } catch (error) {
      throw OhosCryptoProvider.map(error as Error, CryptoErrorKind.INVALID_KEY);
    }
  }

  async importX25519PrivateRaw(raw: Uint8Array): Promise<X25519KeyHandle> {
    try {
      const generator = cryptoFramework.createAsyKeyGenerator('X25519');
      const der = X25519KeyCodec.rawToDerPrivateKey(raw);
      const pair = generator.convertKeySync(null, { data: der });
      return new OhosX25519KeyHandle(pair.priKey, pair.pubKey);
    } catch (error) {
      throw OhosCryptoProvider.map(error as Error, CryptoErrorKind.INVALID_KEY);
    }
  }

  async importX25519PublicRaw(raw: Uint8Array): Promise<X25519KeyHandle> {
    try {
      const generator = cryptoFramework.createAsyKeyGenerator('X25519');
      const der = X25519KeyCodec.rawToDerPublicKey(raw);
      const pair = generator.convertKeySync({ data: der }, null);
      return new OhosX25519KeyHandle(undefined, pair.pubKey);
    } catch (error) {
      throw OhosCryptoProvider.map(error as Error, CryptoErrorKind.INVALID_KEY);
    }
  }

  async exportX25519PublicRaw(key: X25519KeyHandle): Promise<Uint8Array> {
    if (!(key instanceof OhosX25519KeyHandle) || key.pubKey === undefined) {
      throw new CryptoProviderError(CryptoErrorKind.INVALID_KEY);
    }
    try {
      return OhosCryptoProvider.publicDerToRaw(key.pubKey.getEncoded().data);
    } catch (error) {
      throw OhosCryptoProvider.map(error as Error, CryptoErrorKind.INVALID_KEY);
    }
  }

  async computeX25519(privateKey: X25519KeyHandle, peerPublicRaw: Uint8Array): Promise<Uint8Array> {
    if (!(privateKey instanceof OhosX25519KeyHandle) || privateKey.priKey === undefined) {
      throw new CryptoProviderError(CryptoErrorKind.INVALID_KEY);
    }
    try {
      const generator = cryptoFramework.createAsyKeyGenerator('X25519');
      const peerDer = X25519KeyCodec.rawToDerPublicKey(peerPublicRaw);
      const peerPair = generator.convertKeySync({ data: peerDer }, null);
      const agreement = cryptoFramework.createKeyAgreement('X25519');
      const shared = await agreement.generateSecret(privateKey.priKey, peerPair.pubKey);
      return shared.data;
    } catch (error) {
      throw OhosCryptoProvider.map(error as Error, CryptoErrorKind.INVALID_KEY);
    }
  }

  async createAesCtrStream(key: Uint8Array, iv: Uint8Array): Promise<CryptoProviderAesCtrStream> {
    let symKey: cryptoFramework.SymKey | undefined = undefined;
    try {
      symKey = cryptoFramework.createSymKeyGenerator('AES256').convertKeySync({ data: key });
      const cipher = cryptoFramework.createCipher('AES256|CTR|NoPadding');
      const params: cryptoFramework.IvParamsSpec = {
        algName: 'IvParamsSpec',
        iv: { data: iv }
      };
      cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params);
      return new OhosAesCtrStream(cipher, symKey);
    } catch (error) {
      if (symKey !== undefined) {
        symKey.clearMem();
      }
      throw OhosCryptoProvider.map(error as Error, CryptoErrorKind.INVALID_KEY);
    }
  }

  async encryptAesGcm(key: Uint8Array, iv: Uint8Array, aad: Uint8Array,
    plaintext: Uint8Array): Promise<GcmCiphertext> {
    let symKey: cryptoFramework.SymKey | undefined = undefined;
    let cipher: cryptoFramework.Cipher;
    try {
      symKey = cryptoFramework.createSymKeyGenerator('AES256').convertKeySync({ data: key });
      cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
      const params: cryptoFramework.GcmParamsSpec = {
        algName: 'GcmParamsSpec',
        iv: { data: iv },
        aad: { data: aad },
        authTag: { data: new Uint8Array(16) }
      };
      cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params);
    } catch (error) {
      throw OhosCryptoProvider.map(error as Error, CryptoErrorKind.INVALID_KEY);
    }
    try {
      const output = cipher.doFinalSync({ data: plaintext }).data;
      if (output.length < 16) {
        throw new CryptoProviderError(CryptoErrorKind.OPERATION_FAILED);
      }
      const ciphertext = new Uint8Array(output.length - 16);
      ciphertext.set(output.subarray(0, output.length - 16));
      const tag = new Uint8Array(16);
      tag.set(output.subarray(output.length - 16));
      return new GcmCiphertext(ciphertext, tag);
    } catch (error) {
      throw OhosCryptoProvider.map(error as Error, CryptoErrorKind.OPERATION_FAILED);
    } finally {
      if (symKey !== undefined) {
        symKey.clearMem();
      }
    }
  }

  async decryptAesGcm(key: Uint8Array, iv: Uint8Array, aad: Uint8Array,
    ciphertext: Uint8Array, tag: Uint8Array): Promise<Uint8Array> {
    let symKey: cryptoFramework.SymKey | undefined = undefined;
    let cipher: cryptoFramework.Cipher;
    try {
      symKey = cryptoFramework.createSymKeyGenerator('AES256').convertKeySync({ data: key });
      cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
      const params: cryptoFramework.GcmParamsSpec = {
        algName: 'GcmParamsSpec',
        iv: { data: iv },
        aad: { data: aad },
        authTag: { data: tag }
      };
      cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
    } catch (error) {
      throw OhosCryptoProvider.map(error as Error, CryptoErrorKind.INVALID_KEY);
    }
    try {
      return cipher.doFinalSync({ data: ciphertext }).data;
    } catch (error) {
      // A GCM decrypt failure is an authentication failure; never return
      // partial plaintext (DES-A §7.2/§7.3-5).
      throw new CryptoProviderError(CryptoErrorKind.AUTH_TAG);
    } finally {
      if (symKey !== undefined) {
        symKey.clearMem();
      }
    }
  }

  async randomBytes(length: number): Promise<Uint8Array> {
    let random: cryptoFramework.Random;
    try {
      random = cryptoFramework.createRandom();
    } catch (error) {
      throw new CryptoProviderError(CryptoErrorKind.UNAVAILABLE);
    }
    try {
      return random.generateRandomSync(length).data;
    } catch (error) {
      throw new CryptoProviderError(CryptoErrorKind.OPERATION_FAILED);
    }
  }

  private static publicDerToRaw(encoded: Uint8Array): Uint8Array {
    if (encoded.length === 32) {
      const raw = new Uint8Array(32);
      raw.set(encoded);
      return raw;
    }
    return X25519KeyCodec.derToRawPublicKey(encoded);
  }

  private static map(error: Error, kind: CryptoErrorKind): CryptoProviderError {
    if (error instanceof CryptoProviderError) {
      return error;
    }
    return new CryptoProviderError(kind);
  }
}
