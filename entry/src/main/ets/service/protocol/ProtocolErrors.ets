/*
 * YaoCore C-03 protocol error factories.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §6.2
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';

export class ProtocolErrors {
  static protocol(code: string, field?: string): AppError {
    return AppErrors.protocol(code, field);
  }

  static discoveryInvalid(field?: string): AppError {
    return AppErrors.protocol('DISCOVERY_INVALID_RESPONSE', field);
  }

  static unsupportedVersion(version: string): AppError {
    return AppErrors.of('PROTOCOL_UNSUPPORTED_VERSION', [new NameValue('field', 'protocolVersion')]);
  }

  static gatewayIdMismatch(expected: string, actual: string): AppError {
    return AppErrors.of('GATEWAY_ID_MISMATCH', [
      new NameValue('field', 'gatewayId')
    ]);
  }

  static ackCorrelationMismatch(requestId: string, seq: number): AppError {
    return AppErrors.of('ACK_CORRELATION_MISMATCH', [
      new NameValue('requestId', requestId),
      new NameValue('seq', String(seq))
    ]);
  }

  static ackProtocolViolation(field?: string): AppError {
    return AppErrors.protocol('ACK_PROTOCOL_VIOLATION', field);
  }

  static ackStateMismatch(field?: string): AppError {
    return AppErrors.protocol('ACK_STATE_MISMATCH', field);
  }

  static identityInvalid(field?: string): AppError {
    return AppErrors.protocol('PROVISIONING_IDENTITY_INVALID', field);
  }

  static cloudCommandInvalid(field?: string): AppError {
    return AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', field);
  }

  static cloudShadowInvalid(field?: string): AppError {
    return AppErrors.of('CLOUD_SHADOW_INVALID', [new NameValue('field', field === undefined ? 'shadow' : field)]);
  }
}
