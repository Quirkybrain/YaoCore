/*
 * YaoCore C-14 semantic key builders.
 * Producer: agent:implementation-engineer | Task: T-10 / wp-031-i18n
 * Contract: DES-B §7.1.4; DES-A §24.2; I18N-DESIGN §3.3/§7; CB §4.4/§6
 *
 * These builders never copy the App error mapping: `appError` delegates to
 * `ErrorCatalog` (the single mapping table) and only overrides the T-10
 * scene-concurrency key agreed in DES-B §6.2. Unknown enum values map to the
 * explicit `*.unknown` key plus the original value as an interpolation
 * parameter, never to concatenated prose.
 */
import { ErrorCatalog } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { DeviceType } from '../../common/constants/DeviceConstants';
import { InvitationStatus, InviteMode, MemberRole, MemberStatus } from '../../model/FamilyModels';
import { TransportProfile } from '../../model/DeviceTypes';
import { I18nKey } from './I18nModels';

export class I18nKeys {
  /** `errors.app.<code>` except `SCENE_RUN_IN_PROGRESS` -> `errors.scene.run_in_progress`. */
  static appError(code: string): string {
    if (code === 'SCENE_RUN_IN_PROGRESS') {
      return 'errors.scene.run_in_progress';
    }
    return ErrorCatalog.resolve(code).i18nKey;
  }

  static gatewayError(stableName: string, resultCode?: number): I18nKey {
    if (stableName === 'success') {
      return new I18nKey('errors.gateway.success');
    }
    if (I18nKeys.isKnownGatewayName(stableName)) {
      return new I18nKey('errors.gateway.' + stableName);
    }
    const code = resultCode === undefined ? '0' : String(resultCode);
    return new I18nKey('errors.gateway.unknown', [new NameValue('code', code)]);
  }

  static stateSource(value: string, known: boolean): I18nKey {
    if (known && value.length > 0) {
      return new I18nKey('stateSource.' + value.split('.').join('_'));
    }
    return new I18nKey('stateSource.unknown', [new NameValue('value', value)]);
  }

  static acMode(value: string, standard: boolean): I18nKey {
    if (standard && value.length > 0) {
      return new I18nKey('ac.mode.' + value.toLowerCase());
    }
    return new I18nKey('ac.mode.unknown', [new NameValue('mode', value)]);
  }

  /** Delegates to `ErrorCatalog`; the special provisioning/cloud mappings live only there. */
  static provisioningError(code: string): string {
    return ErrorCatalog.resolve(code).i18nKey;
  }

  /** Delegates to `ErrorCatalog`; the special provisioning/cloud mappings live only there. */
  static cloudError(code: string): string {
    return ErrorCatalog.resolve(code).i18nKey;
  }

  static memberRole(role: MemberRole): string {
    return 'member.role.' + role.toLowerCase();
  }

  static memberStatus(status: MemberStatus): string {
    return 'member.status.' + status.toLowerCase();
  }

  static inviteMode(mode: InviteMode): string {
    return 'invite.mode.' + mode.toLowerCase();
  }

  static invitationStatus(status: InvitationStatus): string {
    return 'invite.status.' + status.toLowerCase();
  }

  static deviceType(type: DeviceType | undefined): string {
    if (type === undefined) {
      return 'device.type.unknown';
    }
    return 'device.type.' + type.toLowerCase();
  }

  static securityProfile(profile: TransportProfile, cause?: string): I18nKey {
    if (profile === TransportProfile.P_HMAC) {
      return new I18nKey('gateway.security.hmac_only');
    }
    if (profile === TransportProfile.P_TLS_PIN) {
      return new I18nKey('gateway.security.tls_pinned');
    }
    if (cause === 'pin_mismatch') {
      return new I18nKey('gateway.security.pin_mismatch');
    }
    if (cause === 'state_inconsistent') {
      return new I18nKey('gateway.security.state_inconsistent');
    }
    return new I18nKey('gateway.security.handshake_failed');
  }

  private static isKnownGatewayName(stableName: string): boolean {
    return stableName === 'invalid_request' || stableName === 'unsupported_security' ||
      stableName === 'timestamp_rejected' || stableName === 'bad_signature' ||
      stableName === 'replay' || stableName === 'unsupported_command' ||
      stableName === 'unknown_device' || stableName === 'unsupported_action' ||
      stableName === 'unsupported_gateway_action' || stableName === 'device_offline' ||
      stableName === 'hardware_timeout';
  }
}
