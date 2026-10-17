/*
 * YaoCore C-04 OhosCryptoProvider.
 * Producer: agent:implementation-engineer | Task: T-07 / wp-016-security
 * Fix: wp-018-fix-t07 (R-01 error stages, R-02 secret cleanup)
 * Contract: DES-A §7.1.2, §7.2, §7.4
 *
 * The ONLY production file importing @ohos.security.cryptoFramework. Platform
 * messages/codes are intentionally discarded: callers see sanitized
 * CryptoProviderError kinds only. Each platform call is wrapped with an explicit
 * CryptoFailureStage so creation, key-conversion and operation failures map to
 * the DES-A §7.2 error table instead of one blanket kind. X25519 keys stay
 * inside opaque handles; temporary private DER buffers are zeroized.
 */
import cryptoFramework from '@ohos.security.cryptoFramework';
import { classifyCryptoFailure, CryptoFailureStage } from './CryptoErrorClassifier';
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
      // R-02: a failed CTR operation is terminal; release the platform key
      // immediately. destroy() is idempotent, so the service-level BROKEN
      // transition remains valid.
      this.destroy();
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
    let stage: CryptoFailureStage = CryptoFailureStage.CREATE;
    try {
      digest = cryptoFramework.createMd('SHA256');
      stage = CryptoFailureStage.OPERATION;
      digest.updateSync({ data: data });
      return digest.digestSync().data;
    } catch (error) {
      throw new CryptoProviderError(classifyCryptoFailure(stage, error as Error));
    }
  }

  async hmacSha256(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
    let mac: cryptoFramework.Mac;
    let symKey: cryptoFramework.SymKey | undefined = undefined;
    let stage: CryptoFailureStage = CryptoFailureStage.CREATE;
    try {
      mac = cryptoFramework.createMac('SHA256');
      const generator = cryptoFramework.createSymKeyGenerator('HMAC');
      stage = CryptoFailureStage.KEY_CONVERSION;
      symKey = generator.convertKeySync({ data: key });
      stage = CryptoFailureStage.OPERATION;
      mac.initSync(symKey);
      mac.updateSync({ data: data });
      return mac.doFinalSync().data;
    } catch (error) {
      throw new CryptoProviderError(classifyCryptoFailure(stage, error as Error));
    } finally {
      if (symKey !== undefined) {
        symKey.clearMem();
      }
    }
  }

  async hkdfSha256(ikm: Uint8Array, salt: Uint8Array, info: Uint8Array,
    length: number): Promise<Uint8Array> {
    let stage: CryptoFailureStage = CryptoFailureStage.CREATE;
    try {
      const kdf = cryptoFramework.createKdf('HKDF|SHA256');
      stage = CryptoFailureStage.OPERATION;
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
      throw new CryptoProviderError(classifyCryptoFailure(stage, error as Error));
    }
  }

  async pbkdf2Sha256(password: Uint8Array, salt: Uint8Array, iterations: number,
    length: number): Promise<Uint8Array> {
    let stage: CryptoFailureStage = CryptoFailureStage.CREATE;
    try {
      const kdf = cryptoFramework.createKdf('PBKDF2|SHA256');
      stage = CryptoFailureStage.OPERATION;
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
      throw new CryptoProviderError(classifyCryptoFailure(stage, error as Error));
    }
  }

  async generateX25519KeyPair(): Promise<X25519KeyPair> {
    let stage: CryptoFailureStage = CryptoFailureStage.CREATE;
    try {
      const generator = cryptoFramework.createAsyKeyGenerator('X25519');
      stage = CryptoFailureStage.OPERATION;
      const pair = generator.generateKeyPairSync();
      stage = CryptoFailureStage.KEY_CONVERSION;
      const encoded = pair.pubKey.getEncoded().data;
      const raw = OhosCryptoProvider.publicDerToRaw(encoded);
      const handle = new OhosX25519KeyHandle(pair.priKey, pair.pubKey);
      return new X25519KeyPair(handle, raw);
    } catch (error) {
      throw new CryptoProviderError(classifyCryptoFailure(stage, error as Error));
    }
  }

  async importX25519PrivateRaw(raw: Uint8Array): Promise<X25519KeyHandle> {
    let stage: CryptoFailureStage = CryptoFailureStage.CREATE;
    let der: Uint8Array | undefined = undefined;
    try {
      const generator = cryptoFramework.createAsyKeyGenerator('X25519');
      stage = CryptoFailureStage.KEY_CONVERSION;
      der = X25519KeyCodec.rawToDerPrivateKey(raw);
      const pair = generator.convertKeySync(null, { data: der });
      return new OhosX25519KeyHandle(pair.priKey, pair.pubKey);
    } catch (error) {
      throw new CryptoProviderError(classifyCryptoFailure(stage, error as Error));
    } finally {
      // R-02: the PKCS#8 wrapper contains the 32B private key. Zeroize the
      // temporary copy on every path after the platform has imported it.
      if (der !== undefined) {
        der.fill(0);
      }
    }
  }

  async importX25519PublicRaw(raw: Uint8Array): Promise<X25519KeyHandle> {
    let stage: CryptoFailureStage = CryptoFailureStage.CREATE;
    try {
      const generator = cryptoFramework.createAsyKeyGenerator('X25519');
      stage = CryptoFailureStage.KEY_CONVERSION;
      const der = X25519KeyCodec.rawToDerPublicKey(raw);
      const pair = generator.convertKeySync({ data: der }, null);
      return new OhosX25519KeyHandle(undefined, pair.pubKey);
    } catch (error) {
      throw new CryptoProviderError(classifyCryptoFailure(stage, error as Error));
    }
  }

  async exportX25519PublicRaw(key: X25519KeyHandle): Promise<Uint8Array> {
    if (!(key instanceof OhosX25519KeyHandle) || key.pubKey === undefined) {
      throw new CryptoProviderError(CryptoErrorKind.INVALID_KEY);
    }
    const stage: CryptoFailureStage = CryptoFailureStage.KEY_CONVERSION;
    try {
      return OhosCryptoProvider.publicDerToRaw(key.pubKey.getEncoded().data);
    } catch (error) {
      throw new CryptoProviderError(classifyCryptoFailure(stage, error as Error));
    }
  }

  async computeX25519(privateKey: X25519KeyHandle, peerPublicRaw: Uint8Array): Promise<Uint8Array> {
    if (!(privateKey instanceof OhosX25519KeyHandle) || privateKey.priKey === undefined) {
      throw new CryptoProviderError(CryptoErrorKind.INVALID_KEY);
    }
    let stage: CryptoFailureStage = CryptoFailureStage.CREATE;
    try {
      const generator = cryptoFramework.createAsyKeyGenerator('X25519');
      stage = CryptoFailureStage.KEY_CONVERSION;
      const peerDer = X25519KeyCodec.rawToDerPublicKey(peerPublicRaw);
      const peerPair = generator.convertKeySync({ data: peerDer }, null);
      stage = CryptoFailureStage.CREATE;
      const agreement = cryptoFramework.createKeyAgreement('X25519');
      stage = CryptoFailureStage.OPERATION;
      const shared = await agreement.generateSecret(privateKey.priKey, peerPair.pubKey);
      return shared.data;
    } catch (error) {
      throw new CryptoProviderError(classifyCryptoFailure(stage, error as Error));
    }
  }

  async createAesCtrStream(key: Uint8Array, iv: Uint8Array): Promise<CryptoProviderAesCtrStream> {
    let symKey: cryptoFramework.SymKey | undefined = undefined;
    let stage: CryptoFailureStage = CryptoFailureStage.CREATE;
    try {
      const generator = cryptoFramework.createSymKeyGenerator('AES256');
      stage = CryptoFailureStage.KEY_CONVERSION;
      symKey = generator.convertKeySync({ data: key });
      stage = CryptoFailureStage.CREATE;
      const cipher = cryptoFramework.createCipher('AES256|CTR|NoPadding');
      const params: cryptoFramework.IvParamsSpec = {
        algName: 'IvParamsSpec',
        iv: { data: iv }
      };
      stage = CryptoFailureStage.OPERATION;
      cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params);
      const stream = new OhosAesCtrStream(cipher, symKey);
      symKey = undefined; // ownership moves to the stream (destroy clears it)
      return stream;
    } catch (error) {
      throw new CryptoProviderError(classifyCryptoFailure(stage, error as Error));
    } finally {
      if (symKey !== undefined) {
        symKey.clearMem();
      }
    }
  }

  async encryptAesGcm(key: Uint8Array, iv: Uint8Array, aad: Uint8Array,
    plaintext: Uint8Array): Promise<GcmCiphertext> {
    let symKey: cryptoFramework.SymKey | undefined = undefined;
    let cipher: cryptoFramework.Cipher;
    let stage: CryptoFailureStage = CryptoFailureStage.CREATE;
    try {
      const generator = cryptoFramework.createSymKeyGenerator('AES256');
      stage = CryptoFailureStage.KEY_CONVERSION;
      symKey = generator.convertKeySync({ data: key });
      stage = CryptoFailureStage.CREATE;
      cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
      const params: cryptoFramework.GcmParamsSpec = {
        algName: 'GcmParamsSpec',
        iv: { data: iv },
        aad: { data: aad },
        authTag: { data: new Uint8Array(16) }
      };
      stage = CryptoFailureStage.OPERATION;
      cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params);
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
      throw new CryptoProviderError(classifyCryptoFailure(stage, error as Error));
    } finally {
      // R-02: clear the platform key on success and on every failure path,
      // including createCipher/initSync failures.
      if (symKey !== undefined) {
        symKey.clearMem();
      }
    }
  }

  async decryptAesGcm(key: Uint8Array, iv: Uint8Array, aad: Uint8Array,
    ciphertext: Uint8Array, tag: Uint8Array): Promise<Uint8Array> {
    let symKey: cryptoFramework.SymKey | undefined = undefined;
    let cipher: cryptoFramework.Cipher;
    let stage: CryptoFailureStage = CryptoFailureStage.CREATE;
    try {
      const generator = cryptoFramework.createSymKeyGenerator('AES256');
      stage = CryptoFailureStage.KEY_CONVERSION;
      symKey = generator.convertKeySync({ data: key });
      stage = CryptoFailureStage.CREATE;
      cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
      const params: cryptoFramework.GcmParamsSpec = {
        algName: 'GcmParamsSpec',
        iv: { data: iv },
        aad: { data: aad },
        authTag: { data: tag }
      };
      stage = CryptoFailureStage.OPERATION;
      cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
      stage = CryptoFailureStage.GCM_DECRYPT_FINAL;
      // Only an authenticated-decryption failure (platform crypto operation
      // code) maps to CRYPTO_TAG_MISMATCH; never return partial plaintext
      // (DES-A §7.2/§7.3-5).
      return cipher.doFinalSync({ data: ciphertext }).data;
    } catch (error) {
      throw new CryptoProviderError(classifyCryptoFailure(stage, error as Error));
    } finally {
      if (symKey !== undefined) {
        symKey.clearMem();
      }
    }
  }

  async randomBytes(length: number): Promise<Uint8Array> {
    let random: cryptoFramework.Random;
    let stage: CryptoFailureStage = CryptoFailureStage.CREATE;
    try {
      random = cryptoFramework.createRandom();
      stage = CryptoFailureStage.OPERATION;
      return random.generateRandomSync(length).data;
    } catch (error) {
      throw new CryptoProviderError(classifyCryptoFailure(stage, error as Error));
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
}
