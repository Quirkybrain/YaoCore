/*
 * YaoCore C-19 Security1 session.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Contract: DES-A §16.4; BLE设计 §4-60-100; project-constraints SC-04/SC-05/SC-06
 *
 * X25519 -> SHA256(PoP) XOR shared secret -> AES-256-CTR/NoPadding. One
 * continuous CTR stream is used for client_verify_data, device_verify_data and
 * every subsequent request/response. A failed write/read/timeout/cancel
 * destroys the stream; a new connection starts again at step0. The PoP is held
 * in a zeroizable byte buffer, never as an immutable string.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { BytesUtil } from '../../common/utils/BytesUtil';
import type { RandomPort } from '../../contracts/Ports';
import type { AesCtrStream, CryptoPort, X25519KeyHandle, X25519KeyPair } from '../../contracts/CryptoPort';
import { AesCtrState } from '../../contracts/CryptoPort';
import { ProtocommCodec, SessionDataMessage } from './ProtocommCodec';

const X25519_BYTES: number = 32;
const SESSION_KEY_BYTES: number = 32;
const DEVICE_RANDOM_BYTES: number = 16;

export enum Security1State {
  NEW = 'NEW',
  STEP0_SENT = 'STEP0_SENT',
  STEP1_SENT = 'STEP1_SENT',
  ESTABLISHED = 'ESTABLISHED',
  BROKEN = 'BROKEN',
  DESTROYED = 'DESTROYED'
}

function handshakeFailure(field: string): never {
  throw AppErrors.of('PROVISIONING_SECURITY_HANDSHAKE_FAILED', [new NameValue('field', field)]);
}

export class Security1Session {
  private readonly crypto: CryptoPort;
  /** Retained for the DES-A §16.4 constructor seam; X25519 entropy comes from CryptoPort. */
  private readonly random: RandomPort;
  private readonly pop: Uint8Array;
  private stateValue: Security1State = Security1State.NEW;
  private clientPublicValue: Uint8Array = new Uint8Array(0);
  private privateKey: X25519KeyHandle | undefined = undefined;
  private stream: AesCtrStream | undefined = undefined;

  constructor(crypto: CryptoPort, random: RandomPort, pop: Uint8Array) {
    if (pop.length === 0 || pop.length > 64) {
      handshakeFailure('pop');
    }
    this.crypto = crypto;
    this.random = random;
    this.pop = BytesUtil.copyOf(pop);
  }

  get state(): Security1State {
    return this.stateValue;
  }

  get clientPublicRaw(): Uint8Array {
    return BytesUtil.copyOf(this.clientPublicValue);
  }

  /** SessionData(sec_ver=1, sec1.sc0.client_pubkey=raw32). */
  async createStep0(): Promise<Uint8Array> {
    if (this.stateValue !== Security1State.NEW) {
      handshakeFailure('createStep0State');
    }
    try {
      const pair: X25519KeyPair = await this.crypto.generateX25519KeyPair();
      if (pair.publicKeyRaw.length !== X25519_BYTES) {
        handshakeFailure('clientPublicKey');
      }
      this.privateKey = pair.privateKey;
      this.clientPublicValue = BytesUtil.copyOf(pair.publicKeyRaw);
      const payload = ProtocommCodec.encodeSessionDataStep0(this.clientPublicValue);
      this.stateValue = Security1State.STEP0_SENT;
      return payload;
    } catch (error) {
      this.stateValue = Security1State.BROKEN;
      this.destroy();
      this.rethrowHandshake(error as Error, 'step0');
      throw AppErrors.of('PROVISIONING_SECURITY_HANDSHAKE_FAILED', []);
    }
  }

  /** Derives the XOR session key, initializes the CTR stream, emits step1. */
  async handleStep0Response(payload: Uint8Array): Promise<Uint8Array> {
    this.requireState(Security1State.STEP0_SENT, 'handleStep0State');
    let shared: Uint8Array | undefined = undefined;
    let popDigest: Uint8Array | undefined = undefined;
    let sessionKey: Uint8Array | undefined = undefined;
    try {
      const message: SessionDataMessage = ProtocommCodec.decodeSessionDataStep0(payload);
      if (message.devicePubKey === undefined || message.deviceRandom === undefined ||
        this.privateKey === undefined) {
        handshakeFailure('step0Response');
      }
      shared = await this.crypto.computeX25519(this.privateKey, message.devicePubKey);
      if (shared.length !== SESSION_KEY_BYTES) {
        handshakeFailure('sharedSecret');
      }
      popDigest = await this.crypto.sha256(this.pop);
      if (popDigest.length !== SESSION_KEY_BYTES) {
        handshakeFailure('popDigest');
      }
      sessionKey = new Uint8Array(SESSION_KEY_BYTES);
      for (let index = 0; index < SESSION_KEY_BYTES; index++) {
        sessionKey[index] = shared[index] ^ popDigest[index];
      }
      this.stream = await this.crypto.createAesCtrStream(sessionKey, message.deviceRandom);
      const clientVerify = await this.stream.process(message.devicePubKey);
      const step1 = ProtocommCodec.encodeSessionDataStep1(clientVerify);
      BytesUtil.zeroize(clientVerify);
      this.stateValue = Security1State.STEP1_SENT;
      return step1;
    } catch (error) {
      this.stateValue = Security1State.BROKEN;
      this.destroy();
      this.rethrowHandshake(error as Error, 'step0Response');
      throw AppErrors.of('PROVISIONING_SECURITY_HANDSHAKE_FAILED', []);
    } finally {
      if (shared !== undefined) {
        BytesUtil.zeroize(shared);
      }
      if (popDigest !== undefined) {
        BytesUtil.zeroize(popDigest);
      }
      if (sessionKey !== undefined) {
        BytesUtil.zeroize(sessionKey);
      }
    }
  }

  /**
   * Verifies device_verify_data against client_public_raw in constant time.
   * A wrong PoP destroys the session; it can never fall through to Wi-Fi.
   */
  async handleStep1Response(payload: Uint8Array): Promise<void> {
    this.requireState(Security1State.STEP1_SENT, 'handleStep1State');
    let plain: Uint8Array | undefined = undefined;
    try {
      const message: SessionDataMessage = ProtocommCodec.decodeSessionDataStep1(payload);
      if (message.deviceVerifyData === undefined || this.stream === undefined) {
        handshakeFailure('step1Response');
      }
      plain = await this.stream.process(message.deviceVerifyData);
      if (plain.length !== X25519_BYTES || !this.crypto.constantTimeEqual(plain, this.clientPublicValue)) {
        this.stateValue = Security1State.BROKEN;
        this.destroy();
        throw AppErrors.of('PROVISIONING_POP_INVALID', []);
      }
      BytesUtil.zeroize(plain);
      plain = undefined;
      this.stateValue = Security1State.ESTABLISHED;
    } catch (error) {
      if (error instanceof AppError && error.code === 'PROVISIONING_POP_INVALID') {
        throw error;
      }
      this.stateValue = Security1State.BROKEN;
      this.destroy();
      this.rethrowHandshake(error as Error, 'step1Response');
      throw AppErrors.of('PROVISIONING_SECURITY_HANDSHAKE_FAILED', []);
    } finally {
      if (plain !== undefined) {
        BytesUtil.zeroize(plain);
      }
    }
  }

  /** Encrypts with the one continuous CTR stream. ESTABLISHED only. */
  async encrypt(payload: Uint8Array): Promise<Uint8Array> {
    return this.process(payload, 'encrypt');
  }

  /** Decrypts with the same continuous CTR stream. ESTABLISHED only. */
  async decrypt(payload: Uint8Array): Promise<Uint8Array> {
    return this.process(payload, 'decrypt');
  }

  /**
   * Destroys the CTR stream and zeroizes PoP/session-derived buffers. The
   * opaque private-key handle is dropped; platform crypto owns its lifetime.
   */
  destroy(): void {
    if (this.stateValue === Security1State.DESTROYED) {
      return;
    }
    if (this.stream !== undefined) {
      this.stream.destroy();
      this.stream = undefined;
    }
    this.privateKey = undefined;
    BytesUtil.zeroize(this.pop);
    BytesUtil.zeroize(this.clientPublicValue);
    this.clientPublicValue = new Uint8Array(0);
    this.stateValue = Security1State.DESTROYED;
  }

  private async process(payload: Uint8Array, field: string): Promise<Uint8Array> {
    if (this.stateValue !== Security1State.ESTABLISHED || this.stream === undefined ||
      this.stream.state !== AesCtrState.ACTIVE) {
      handshakeFailure(field);
    }
    try {
      return await this.stream.process(payload);
    } catch (error) {
      this.stateValue = Security1State.BROKEN;
      this.destroy();
      if (error instanceof AppError && error.code === 'CRYPTO_STREAM_BROKEN') {
        throw error;
      }
      this.rethrowHandshake(error as Error, field);
      throw AppErrors.of('PROVISIONING_SECURITY_HANDSHAKE_FAILED', []);
    }
  }

  private requireState(expected: Security1State, field: string): void {
    if (this.stateValue !== expected) {
      handshakeFailure(field);
    }
  }

  private rethrowHandshake(error: Error, field: string): never {
    if (error instanceof AppError) {
      const appError = error as AppError;
      if (appError.code === 'PROVISIONING_POP_INVALID' ||
        appError.code === 'PROVISIONING_SECURITY_HANDSHAKE_FAILED') {
        throw appError;
      }
    }
    throw AppErrors.of('PROVISIONING_SECURITY_HANDSHAKE_FAILED', [new NameValue('field', field)]);
  }
}
