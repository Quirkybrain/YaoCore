/*
 * YaoCore C-05 response verifier.
 * Producer: agent:implementation-engineer | Task: T-07 / wp-016-security
 * Contract: DES-A §8.1.3, §8.2, §8.3-5/6, §18.3, §18.7
 *
 * Fixed verification order: alg -> key id -> correlation -> sign shape ->
 * body SHA-256 -> response canonical -> HMAC -> constant-time compare.
 * Responses carry no time window; `server_time` never affects acceptance.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { ProtocolConstants, ProtocolHeaders } from '../../common/constants/ProtocolConstants';
import { HttpHeaders } from '../../common/types/HttpHeaders';
import type { CryptoPort } from '../crypto/CryptoPort';
import { BytesUtil } from '../../common/utils/BytesUtil';
import { CanonicalBuilder, ResponseKind } from './CanonicalBuilder';

const MIN_SECRET_LENGTH: number = 16;

export class ExpectedResponse {
  readonly kind: ResponseKind;
  readonly correlation: string;

  private constructor(kind: ResponseKind, correlation: string) {
    this.kind = kind;
    this.correlation = correlation;
  }

  static forDiscover(challenge: string): ExpectedResponse {
    if (!ProtocolConstants.HEX_LOWER_32.test(challenge)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'challenge');
    }
    return new ExpectedResponse(ResponseKind.DISCOVER, challenge);
  }

  static forControl(requestId: string, seq: number): ExpectedResponse {
    if (!ProtocolConstants.REQUEST_ID_PATTERN.test(requestId) ||
      requestId.length > ProtocolConstants.MAX_REQUEST_ID_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'request_id');
    }
    if (!Number.isInteger(seq) || seq < 0 || seq > ProtocolConstants.MAX_SEQ) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'seq');
    }
    return new ExpectedResponse(ResponseKind.CONTROL, requestId + ':' + String(seq));
  }
}

export class VerifiedResponse {
  readonly kind: ResponseKind;
  readonly correlation: string;
  readonly bodySha256Hex: string;

  constructor(kind: ResponseKind, correlation: string, bodySha256Hex: string) {
    this.kind = kind;
    this.correlation = correlation;
    this.bodySha256Hex = bodySha256Hex;
  }
}

export class ResponseVerifier {
  private readonly crypto: CryptoPort;

  constructor(crypto: CryptoPort) {
    this.crypto = crypto;
  }

  async verify(headers: HttpHeaders, body: Uint8Array, expected: ExpectedResponse,
    secret: Uint8Array): Promise<VerifiedResponse> {
    if (secret.length < MIN_SECRET_LENGTH) {
      throw AppErrors.security('CRYPTO_INVALID_KEY', 'secret');
    }
    const alg = headers.get(ProtocolHeaders.RESPONSE_ALG);
    if (alg !== ProtocolConstants.ALG_HMAC_SHA256) {
      throw AppErrors.security('RESPONSE_AUTH_FAILED', 'alg');
    }
    const keyId = headers.get(ProtocolHeaders.RESPONSE_KEY_ID);
    if (keyId !== ProtocolConstants.KEY_ID_V1) {
      throw AppErrors.security('RESPONSE_AUTH_FAILED', 'key_id');
    }
    const correlation = headers.get(ProtocolHeaders.RESPONSE_CORRELATION);
    if (correlation === undefined) {
      throw AppErrors.security('RESPONSE_AUTH_FAILED', 'correlation');
    }
    if (correlation !== expected.correlation) {
      throw AppErrors.security('RESPONSE_CORRELATION_MISMATCH', 'correlation');
    }
    const sign = headers.get(ProtocolHeaders.RESPONSE_SIGN);
    if (sign === undefined || !ProtocolConstants.HEX_LOWER_64.test(sign)) {
      throw AppErrors.security('RESPONSE_AUTH_FAILED', 'sign');
    }
    try {
      const digest = await this.crypto.sha256(body);
      if (digest.length !== 32) {
        throw AppErrors.security('CRYPTO_OPERATION_FAILED', 'bodySha256');
      }
      const bodySha256Hex = BytesUtil.hexLower(digest);
      const canonical = CanonicalBuilder.response(expected.kind, expected.correlation, bodySha256Hex);
      const expectedMac = await this.crypto.hmacSha256(secret, BytesUtil.utf8(canonical));
      if (expectedMac.length !== 32) {
        throw AppErrors.security('CRYPTO_OPERATION_FAILED', 'sign');
      }
      const expectedSign = BytesUtil.hexLower(expectedMac);
      const matches = this.crypto.constantTimeEqual(
        BytesUtil.utf8(expectedSign),
        BytesUtil.utf8(sign)
      );
      if (!matches) {
        throw AppErrors.security('RESPONSE_AUTH_FAILED', 'sign');
      }
      return new VerifiedResponse(expected.kind, expected.correlation, bodySha256Hex);
    } catch (error) {
      if (error instanceof AppError) {
        throw error;
      }
      throw AppErrors.security('CRYPTO_OPERATION_FAILED', 'responseAuth');
    }
  }
}
