/*
 * YaoCore C-15 cloud configuration validator.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §8.1.7 (validateConfig), DES-A §5.1.7 (CloudConfig)
 *
 * Endpoint grammar is intentionally strict: HTTPS only, host (optional port),
 * no path/query/user-info. Tokens are never part of CloudConfig.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';
import { StorageConstants } from '../../common/constants/StorageConstants';
import type { CloudConfig } from '../../model/FamilyModels';
import { CloudConfigValidation } from './CloudModels';

const HTTPS_HOST_PATTERN: RegExp =
  /^https:\/\/([A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)(?::([0-9]{1,5}))?$/;
const CLOUD_ID_PATTERN: RegExp = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$/;

export class CloudConfigValidator {
  static validate(config: CloudConfig): CloudConfigValidation {
    const errors: AppError[] = [];
    CloudConfigValidator.validateEndpoint(config.endpoint, errors);
    if (!CLOUD_ID_PATTERN.test(config.projectId)) {
      errors.push(AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'projectId'));
    }
    if (!CLOUD_ID_PATTERN.test(config.deviceId)) {
      errors.push(AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'deviceId'));
    }
    if (config.accessTokenAlias !== StorageConstants.ASSET_CLOUD_TOKEN) {
      errors.push(AppErrors.of('CONFIGURATION_ERROR',
        [new NameValue('field', 'accessTokenAlias')]));
    }
    if (config.shadowEndpoint !== undefined) {
      CloudConfigValidator.validateEndpoint(config.shadowEndpoint, errors);
    }
    if (errors.length > 0) {
      return new CloudConfigValidation(false, errors);
    }
    const base = config.endpoint;
    const shadowBase = config.shadowEndpoint === undefined ? base : config.shadowEndpoint;
    const commandEndpoint = base + '/v5/iot/' + config.projectId + '/devices/' +
      config.deviceId + '/commands';
    const shadowEndpoint = shadowBase + '/v5/iot/' + config.projectId + '/devices/' +
      config.deviceId + '/shadow';
    return new CloudConfigValidation(true, [], commandEndpoint, shadowEndpoint);
  }

  static isId(value: string): boolean {
    return CLOUD_ID_PATTERN.test(value) && value.length <= ProtocolConstants.MAX_IDENTIFIER_LENGTH_INBOUND;
  }

  private static validateEndpoint(endpoint: string, errors: AppError[]): boolean {
    const match = HTTPS_HOST_PATTERN.exec(endpoint);
    if (match === null) {
      errors.push(AppErrors.of('CLOUD_ENDPOINT_INVALID', []));
      return false;
    }
    if (match[2] !== undefined) {
      const port = Number.parseInt(match[2], 10);
      if (!Number.isInteger(port) || port < 1 || port > 65535) {
        errors.push(AppErrors.of('CLOUD_ENDPOINT_INVALID', []));
        return false;
      }
    }
    return true;
  }
}
