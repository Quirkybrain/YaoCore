/*
 * YaoCore C-01 storage constants.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §4.1.4
 */
export class StorageConstants {
  static readonly PREFERENCES_NAME: string = 'yaocore_prefs';
  static readonly RDB_NAME: string = 'yaocore.db';
  static readonly RDB_BASE_VERSION: number = 1;
  static readonly PREF_LOCALE_MODE: string = 'app.locale.mode';
  static readonly PREF_ACTIVE_FAMILY_ID: string = 'app.activeFamilyId';
  static readonly PREF_LAST_PROFILE_ID: string = 'app.lastProfileId';
  static readonly PREF_LAST_KNOWN_WIFI_SSID: string = 'ble.lastSsid';
  static readonly ASSET_PREFIX_GATEWAY_HMAC: string = 'yaocore.gateway.hmac.';
  static readonly ASSET_PREFIX_GATEWAY_HMAC_PENDING: string = 'yaocore.gateway.hmac.pending.';
  static readonly ASSET_CLOUD_TOKEN: string = 'yaocore.cloud.token.v2';
  static readonly ASSET_PREFIX_AUTH_HASH: string = 'yaocore.auth.profile.';
  static readonly ASSET_PREFIX_INVITE_JOIN: string = 'yaocore.invite.join.';
  static readonly ASSET_PREFIX_INVITE_SEED: string = 'yaocore.invite.seed.';

  static gatewayHmacAlias(gatewayId: string): string {
    return StorageConstants.ASSET_PREFIX_GATEWAY_HMAC + gatewayId;
  }

  static gatewayHmacPendingAlias(gatewayId: string, rotationId: string): string {
    return StorageConstants.ASSET_PREFIX_GATEWAY_HMAC_PENDING + gatewayId + '.' + rotationId;
  }

  static authHashAlias(profileId: string): string {
    return StorageConstants.ASSET_PREFIX_AUTH_HASH + profileId;
  }

  static inviteJoinAlias(memberId: string): string {
    return StorageConstants.ASSET_PREFIX_INVITE_JOIN + memberId;
  }

  static inviteSeedAlias(inviteId: string): string {
    return StorageConstants.ASSET_PREFIX_INVITE_SEED + inviteId;
  }
}
