/*
 * YaoCore C-01 gateway result namespace.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §3.2.4, CB §4.1
 *
 * This is deliberately separate from the App error namespace. Gateway result
 * codes never become AppError.code values.
 */
export enum GatewayResultCode {
  SUCCESS = 0,
  INVALID_REQUEST = 1001,
  UNSUPPORTED_SECURITY = 1002,
  TIMESTAMP_REJECTED = 1003,
  BAD_SIGNATURE = 1004,
  REPLAY = 1005,
  UNSUPPORTED_COMMAND = 1006,
  DEVICE_OFFLINE = 1007,
  HARDWARE_TIMEOUT = 1008
}

/** Immutable classification of one gateway result_code/error_code pair. */
export class GatewayResultClass {
  readonly known: boolean;
  readonly success: boolean;
  readonly stableName: string;
  readonly retryable: boolean;
  readonly i18nKey: string;

  constructor(known: boolean, success: boolean, stableName: string, retryable: boolean, i18nKey: string) {
    this.known = known;
    this.success = success;
    this.stableName = stableName;
    this.retryable = retryable;
    this.i18nKey = i18nKey;
  }
}

export class GatewayResultClassifier {
  static classify(resultCode: number, errorCode?: string): GatewayResultClass {
    if (!Number.isInteger(resultCode) || resultCode < 0 || resultCode > 9999) {
      return GatewayResultClassifier.unknown(resultCode);
    }
    if (resultCode === GatewayResultCode.SUCCESS) {
      return new GatewayResultClass(true, true, 'success', false, 'errors.gateway.success');
    }
    if (resultCode === GatewayResultCode.INVALID_REQUEST) {
      return new GatewayResultClass(true, false, 'invalid_request', false, 'errors.gateway.invalid_request');
    }
    if (resultCode === GatewayResultCode.UNSUPPORTED_SECURITY) {
      return new GatewayResultClass(true, false, 'unsupported_security', false,
        'errors.gateway.unsupported_security');
    }
    if (resultCode === GatewayResultCode.TIMESTAMP_REJECTED) {
      return new GatewayResultClass(true, false, 'timestamp_rejected', false,
        'errors.gateway.timestamp_rejected');
    }
    if (resultCode === GatewayResultCode.BAD_SIGNATURE) {
      return new GatewayResultClass(true, false, 'bad_signature', false, 'errors.gateway.bad_signature');
    }
    if (resultCode === GatewayResultCode.REPLAY) {
      return new GatewayResultClass(true, false, 'replay', false, 'errors.gateway.replay');
    }
    if (resultCode === GatewayResultCode.UNSUPPORTED_COMMAND) {
      return new GatewayResultClass(true, false, 'unsupported_command', false,
        'errors.gateway.unsupported_command');
    }
    if (resultCode === GatewayResultCode.DEVICE_OFFLINE) {
      return new GatewayResultClass(true, false, 'device_offline', true, 'errors.gateway.device_offline');
    }
    if (resultCode === GatewayResultCode.HARDWARE_TIMEOUT) {
      return new GatewayResultClass(true, false, 'hardware_timeout', true,
        'errors.gateway.hardware_timeout');
    }
    // Unknown or reserved code: fail closed. `errorCode` cannot promote an
    // unknown numeric code to success (ADR-001 §2.2-3).
    return GatewayResultClassifier.unknown(resultCode);
  }

  private static unknown(resultCode: number): GatewayResultClass {
    return new GatewayResultClass(false, false, 'unknown_' + String(resultCode), false,
      'errors.gateway.unknown');
  }
}
