/*
 * YaoCore C-05 request signer.
 * Producer: agent:implementation-engineer | Task: T-07 / wp-016-security
 * Contract: DES-A §8.1.2, §8.3, §18.1, §18.2, §18.5
 *
 * Generates App outbound nonces as 16 random bytes -> 32 lowercase hex and
 * signs the canonical UTF-8 bytes with HMAC-SHA256. Secrets stay caller-owned.
 */
import { AppErrors } from '../../common/types/AppError';
import { ProtocolConstants, ProtocolHeaders } from '../../common/constants/ProtocolConstants';
import { DeviceAction } from '../../common/constants/DeviceConstants';
import { HttpHeaders } from '../../common/types/HttpHeaders';
import { NameValue } from '../../common/types/NameValue';
import type { ClockPort, RandomPort } from '../../common/types/Ports';
import { BytesUtil } from '../../common/utils/BytesUtil';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import { JsonAtom } from '../../common/utils/JsonAtom';
import type { CommandValue } from '../../common/utils/JsonAtom';
import type { CryptoPort } from '../crypto/CryptoPort';
import {
  CanonicalBuilder,
  ControlCanonicalFields,
  DiscoverCanonicalFields
} from './CanonicalBuilder';
import { NonceCache, NonceDecision } from './NonceCache';

const MIN_SECRET_LENGTH: number = 16;
const NONCE_BYTES: number = 16;
const NONCE_RETRY_LIMIT: number = 3;

export class SigningInput {
  readonly gatewayId: string;
  readonly target: string;
  readonly action: DeviceAction;
  readonly value?: CommandValue;

  constructor(gatewayId: string, target: string, action: DeviceAction, value?: CommandValue) {
    this.gatewayId = gatewayId;
    this.target = target;
    this.action = action;
    this.value = value;
  }
}

export class DiscoverSigningInput {
  readonly gatewayId: string;

  constructor(gatewayId: string) {
    this.gatewayId = gatewayId;
  }
}

export class SignedControlRequest {
  readonly requestId: string;
  readonly seq: number;
  readonly target: string;
  readonly action: string;
  readonly valueText: string;
  readonly timestamp: string;
  readonly nonce: string;
  readonly canonical: string;
  readonly sign: string;

  constructor(requestId: string, seq: number, target: string, action: string, valueText: string,
    timestamp: string, nonce: string, canonical: string, sign: string) {
    this.requestId = requestId;
    this.seq = seq;
    this.target = target;
    this.action = action;
    this.valueText = valueText;
    this.timestamp = timestamp;
    this.nonce = nonce;
    this.canonical = canonical;
    this.sign = sign;
  }
}

export class SignedDiscoverRequest {
  readonly headers: HttpHeaders;
  readonly challenge: string;
  readonly timestamp: string;
  readonly nonce: string;
  readonly canonical: string;

  constructor(headers: HttpHeaders, challenge: string, timestamp: string, nonce: string,
    canonical: string) {
    this.headers = headers;
    this.challenge = challenge;
    this.timestamp = timestamp;
    this.nonce = nonce;
    this.canonical = canonical;
  }
}

export class RequestSigner {
  private readonly crypto: CryptoPort;
  private readonly clock: ClockPort;
  private readonly random: RandomPort;
  private readonly nonces: NonceCache;

  constructor(crypto: CryptoPort, clock: ClockPort, random: RandomPort, nonces: NonceCache) {
    this.crypto = crypto;
    this.clock = clock;
    this.random = random;
    this.nonces = nonces;
  }

  async signControl(input: SigningInput, secret: Uint8Array, seq: number): Promise<SignedControlRequest> {
    RequestSigner.requireSecret(secret);
    RequestSigner.validateGateway(input.gatewayId);
    RequestSigner.validateTarget(input.target);
    RequestSigner.validateAction(input.action);
    if (!Number.isInteger(seq) || seq < 0 || seq > ProtocolConstants.MAX_SEQ) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'seq');
    }
    const nowMs = this.nowMs();
    const timestamp = DateTimeUtil.formatUtcCompact(nowMs);
    const requestId = DateTimeUtil.formatRequestId(nowMs, seq);
    const nonce = await this.generateNonce(nowMs);
    const valueText = JsonAtom.encode(input.value);
    const fields = new ControlCanonicalFields(
      requestId,
      ProtocolConstants.CMD_ID_CONTROL,
      seq,
      input.target,
      String(input.action),
      valueText,
      timestamp,
      nonce,
      ProtocolConstants.ALG_HMAC_SHA256,
      ProtocolConstants.KEY_ID_V1
    );
    const canonical = CanonicalBuilder.control(fields);
    const sign = await this.hmacHex(secret, canonical);
    return new SignedControlRequest(requestId, seq, input.target, String(input.action), valueText,
      timestamp, nonce, canonical, sign);
  }

  async signDiscover(input: DiscoverSigningInput, secret: Uint8Array): Promise<SignedDiscoverRequest> {
    RequestSigner.requireSecret(secret);
    RequestSigner.validateGateway(input.gatewayId);
    const nowMs = this.nowMs();
    const timestamp = DateTimeUtil.formatUtcCompact(nowMs);
    const challenge = await this.generateRandomHex('challenge');
    const nonce = await this.generateNonce(nowMs);
    const fields = new DiscoverCanonicalFields(
      challenge,
      timestamp,
      nonce,
      ProtocolConstants.ALG_HMAC_SHA256,
      ProtocolConstants.KEY_ID_V1
    );
    const canonical = CanonicalBuilder.discover(fields);
    const sign = await this.hmacHex(secret, canonical);
    const headers = HttpHeaders.from([
      new NameValue(ProtocolHeaders.CHALLENGE, challenge),
      new NameValue(ProtocolHeaders.REQUEST_NONCE, nonce),
      new NameValue(ProtocolHeaders.REQUEST_TIMESTAMP, timestamp),
      new NameValue(ProtocolHeaders.REQUEST_ALG, ProtocolConstants.ALG_HMAC_SHA256),
      new NameValue(ProtocolHeaders.REQUEST_KEY_ID, ProtocolConstants.KEY_ID_V1),
      new NameValue(ProtocolHeaders.REQUEST_SIGN, sign)
    ]);
    return new SignedDiscoverRequest(headers, challenge, timestamp, nonce, canonical);
  }

  private nowMs(): number {
    const nowMs = this.clock.nowMs();
    if (!Number.isFinite(nowMs)) {
      throw AppErrors.internal('clock');
    }
    return Math.floor(nowMs);
  }

  private async generateNonce(nowMs: number): Promise<string> {
    for (let attempt = 0; attempt < NONCE_RETRY_LIMIT; attempt++) {
      const nonce = await this.generateRandomHex('nonce');
      const decision = this.nonces.checkAndRemember(ProtocolConstants.KEY_ID_V1, nonce, nowMs);
      if (decision !== NonceDecision.DUPLICATE) {
        return nonce;
      }
    }
    // DES-A §8.1.2: three duplicate nonces indicate a broken random source.
    throw AppErrors.internal('nonce');
  }

  private async generateRandomHex(field: string): Promise<string> {
    let bytes: Uint8Array;
    try {
      bytes = await this.random.nextBytes(NONCE_BYTES);
    } catch (error) {
      throw AppErrors.security('CRYPTO_OPERATION_FAILED', field);
    }
    if (bytes.length !== NONCE_BYTES) {
      throw AppErrors.security('CRYPTO_OPERATION_FAILED', field);
    }
    const hex = BytesUtil.hexLower(bytes);
    if (!ProtocolConstants.HEX_LOWER_32.test(hex)) {
      throw AppErrors.security('CRYPTO_OPERATION_FAILED', field);
    }
    return hex;
  }

  private async hmacHex(secret: Uint8Array, canonical: string): Promise<string> {
    const mac = await this.crypto.hmacSha256(secret, BytesUtil.utf8(canonical));
    if (mac.length !== 32) {
      throw AppErrors.security('CRYPTO_OPERATION_FAILED', 'sign');
    }
    return BytesUtil.hexLower(mac);
  }

  private static requireSecret(secret: Uint8Array): void {
    if (secret.length < MIN_SECRET_LENGTH) {
      throw AppErrors.security('CRYPTO_INVALID_KEY', 'secret');
    }
  }

  private static validateGateway(gatewayId: string): void {
    if (gatewayId.length === 0 || gatewayId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      gatewayId.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(gatewayId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'gatewayId');
    }
  }

  private static validateTarget(target: string): void {
    if (target.length === 0 || target.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      target.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(target)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'target');
    }
  }

  private static validateAction(action: DeviceAction): void {
    const text = String(action);
    if (text.length === 0 || text.length > ProtocolConstants.MAX_ACTION_LENGTH ||
      !ProtocolConstants.ACTION_PATTERN.test(text)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'action');
    }
  }
}
