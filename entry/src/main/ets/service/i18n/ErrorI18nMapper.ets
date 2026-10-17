/*
 * YaoCore C-14 error -> i18n key mapper.
 * Producer: agent:implementation-engineer | Task: T-10 / wp-031-i18n
 * Contract: DES-A §24.1/§24.2; CB §4.1/§4.4; DES-B §7.1.4
 *
 * `ErrorI18nMapper` is the single error-to-key entry point for UI and
 * view-models. `I18nKeys` remains the thin convenience wrapper. Raw gateway
 * `message` text is never used.
 */
import { AppError } from '../../common/types/AppError';
import { GatewayResultClassifier } from '../../common/types/GatewayResult';
import { NameValue } from '../../common/types/NameValue';
import { TransportProfile } from '../../model/DeviceTypes';
import { I18nKeys } from './I18nKeys';
import { I18nKey } from './I18nModels';

export class ErrorI18nMapper {
  static gatewayKey(resultCode: number, errorCode?: string): I18nKey {
    const classification = GatewayResultClassifier.classify(resultCode, errorCode);
    if (!classification.known) {
      return new I18nKey('errors.gateway.unknown', [new NameValue('code', String(resultCode))]);
    }
    if (resultCode === 1006 && ErrorI18nMapper.isKnownSubcode(errorCode)) {
      return new I18nKey('errors.gateway.' + (errorCode as string));
    }
    return new I18nKey(classification.i18nKey);
  }

  static appKey(error: AppError): I18nKey {
    const key = I18nKeys.appError(error.code);
    if (error.code.startsWith('HTTP_')) {
      const status = error.code.substring('HTTP_'.length);
      return new I18nKey(key, [new NameValue('status', status)]);
    }
    return new I18nKey(key);
  }

  static stateSourceKey(value: string, known: boolean): I18nKey {
    return I18nKeys.stateSource(value, known);
  }

  static acModeKey(value: string, standard: boolean): I18nKey {
    return I18nKeys.acMode(value, standard);
  }

  static securityProfileKey(profile: TransportProfile, cause?: string): I18nKey {
    return I18nKeys.securityProfile(profile, cause);
  }

  static provisioningKey(error: AppError): I18nKey {
    return new I18nKey(error.i18nKey);
  }

  private static isKnownSubcode(errorCode?: string): boolean {
    return errorCode === 'unknown_device' || errorCode === 'unsupported_action' ||
      errorCode === 'unsupported_gateway_action';
  }
}
