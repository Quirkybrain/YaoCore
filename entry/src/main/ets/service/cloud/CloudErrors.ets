/*
 * YaoCore C-15 cloud error mapping.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §8.2; CB §4.2, §7.1; ADR-001 §2.2-6
 *
 * Cloud failures use their own App namespace. Gateway result_code values are
 * never reused and no token/body/certificate material enters `details`.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';

export class CloudErrors {
  static http(statusCode: number, requestId: string, seq: number, deviceId: string): AppError {
    return CloudErrors.withContext(CloudErrors.codeForStatus(statusCode), statusCode, requestId,
      seq, deviceId);
  }

  static codeForStatus(statusCode: number): string {
    if (statusCode === 401) {
      return 'CLOUD_TOKEN_EXPIRED';
    }
    if (statusCode === 403) {
      return 'CLOUD_TOKEN_INVALID';
    }
    if (statusCode === 404) {
      return 'CLOUD_DEVICE_NOT_FOUND';
    }
    if (statusCode === 408) {
      return 'CLOUD_REQUEST_FAILED';
    }
    if (statusCode === 429) {
      return 'CLOUD_RATE_LIMITED';
    }
    if (statusCode >= 500) {
      return 'CLOUD_SERVICE_UNAVAILABLE';
    }
    if (statusCode >= 400) {
      return 'CLOUD_RESPONSE_INVALID';
    }
    return 'CLOUD_REQUEST_FAILED';
  }

  static withContext(code: string, httpStatus: number | undefined, requestId: string | undefined,
    seq: number | undefined, deviceId: string | undefined): AppError {
    const details: NameValue[] = [];
    if (httpStatus !== undefined) {
      details.push(new NameValue('httpStatus', String(httpStatus)));
    }
    if (requestId !== undefined && requestId.length > 0) {
      details.push(new NameValue('requestId', requestId));
    }
    if (seq !== undefined) {
      details.push(new NameValue('seq', String(seq)));
    }
    if (deviceId !== undefined && deviceId.length > 0) {
      details.push(new NameValue('deviceId', deviceId));
    }
    return AppErrors.of(code, details);
  }

  static shadowInvalid(field: string): AppError {
    return AppErrors.of('CLOUD_SHADOW_INVALID', [new NameValue('field', field)]);
  }

  static inventoryUnsupported(field: string): AppError {
    return AppErrors.of('CLOUD_INVENTORY_UNSUPPORTED', [new NameValue('field', field)]);
  }

  static tokenState(code: string): boolean {
    return code === 'CLOUD_TOKEN_EXPIRED' || code === 'CLOUD_TOKEN_INVALID';
  }

  static retryableStatus(statusCode: number): boolean {
    return statusCode === 429 || statusCode >= 500;
  }

  static transport(error: Object, requestId: string | undefined, seq: number | undefined,
    deviceId: string | undefined): AppError {
    if (error instanceof AppError) {
      if (error.code.startsWith('CLOUD_')) {
        return error;
      }
      if (error.code.startsWith('HTTP_')) {
        const status = Number.parseInt(error.code.substring('HTTP_'.length), 10);
        if (Number.isInteger(status)) {
          return CloudErrors.http(status, requestId === undefined ? '' : requestId,
            seq === undefined ? 0 : seq, deviceId === undefined ? '' : deviceId);
        }
      }
    }
    return CloudErrors.withContext('CLOUD_REQUEST_FAILED', undefined, requestId, seq, deviceId);
  }
}
