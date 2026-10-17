/*
 * YaoCore C-02 gateway route and TLS material.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §5.1.3, §5.3 invariant 8
 */
import { AppErrors } from '../common/types/AppError';
import { ProtocolConstants } from '../common/constants/ProtocolConstants';
import { StorageConstants } from '../common/constants/StorageConstants';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import { IpAddressUtil } from '../common/utils/IpAddressUtil';
import { TransportProfile } from './DeviceTypes';

export class GatewayAddress {
  readonly ip: string;
  readonly port: number;

  constructor(ip: string, port: number) {
    if (!IpAddressUtil.isValidIpv4(ip) || !IpAddressUtil.isValidPort(port)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'address');
    }
    this.ip = ip;
    this.port = port;
  }
}

export class TlsMaterial {
  readonly pins: ReadonlyArray<string>;
  readonly port: number;
  readonly pinAlg: string;

  constructor(pins: ReadonlyArray<string>, port: number, pinAlg: string) {
    if (!IpAddressUtil.isValidPort(port)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'port');
    }
    if (pins.length < 1 || pins.length > ProtocolConstants.MAX_PIN_COUNT) {
      throw AppErrors.of('TLS_PIN_CONFIG_INVALID', []);
    }
    for (let index = 0; index < pins.length; index++) {
      if (!ProtocolConstants.PIN_PATTERN.test(pins[index])) {
        throw AppErrors.of('TLS_PIN_CONFIG_INVALID', []);
      }
    }
    if (pinAlg !== 'sha256-spki-der') {
      throw AppErrors.of('TLS_PIN_CONFIG_INVALID', []);
    }
    this.pins = pins;
    this.port = port;
    this.pinAlg = pinAlg;
  }
}

export class GatewayRouteInit {
  gatewayId: string = '';
  familyId: string = '';
  gatewayName: string = '';
  localIp: string = '';
  port: number = ProtocolConstants.DEFAULT_GATEWAY_PORT;
  profile: TransportProfile = TransportProfile.P_HMAC;
  tlsEnabled: boolean = false;
  pins: ReadonlyArray<string> = [];
  pinAlg: string = '';
  keyId: string = ProtocolConstants.KEY_ID_V1;
  credentialAlias: string = '';
  lastKnownIp: string = '';
  lastSeenAt: string | undefined = undefined;
  createdAt: string = '';
  updatedAt: string = '';
}

export class GatewayRoute {
  readonly gatewayId: string;
  readonly familyId: string;
  readonly gatewayName: string;
  readonly localIp: string;
  readonly port: number;
  readonly profile: TransportProfile;
  readonly tlsEnabled: boolean;
  readonly pins: ReadonlyArray<string>;
  readonly pinAlg: string;
  readonly keyId: string;
  readonly credentialAlias: string;
  readonly lastKnownIp: string;
  readonly lastSeenAt?: string;
  readonly createdAt: string;
  readonly updatedAt: string;

  private constructor(init: GatewayRouteInit) {
    this.gatewayId = init.gatewayId;
    this.familyId = init.familyId;
    this.gatewayName = init.gatewayName;
    this.localIp = init.localIp;
    this.port = init.port;
    this.profile = init.profile;
    this.tlsEnabled = init.tlsEnabled;
    this.pins = init.pins;
    this.pinAlg = init.pinAlg;
    this.keyId = init.keyId;
    this.credentialAlias = init.credentialAlias;
    this.lastKnownIp = init.lastKnownIp;
    this.lastSeenAt = init.lastSeenAt;
    this.createdAt = init.createdAt;
    this.updatedAt = init.updatedAt;
  }

  static create(init: GatewayRouteInit): GatewayRoute {
    if (init.gatewayId.length === 0 || init.gatewayId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      init.gatewayId.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(init.gatewayId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'gatewayId');
    }
    if (init.familyId.length === 0 || init.familyId.length > 63) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'familyId');
    }
    if (init.gatewayName.length === 0 ||
      init.gatewayName.length > ProtocolConstants.MAX_GATEWAY_NAME_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'gatewayName');
    }
    if (init.localIp.length > 0 && !IpAddressUtil.isValidIpv4(init.localIp)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'localIp');
    }
    if (init.lastKnownIp.length > 0 && !IpAddressUtil.isValidIpv4(init.lastKnownIp)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'lastKnownIp');
    }
    if (!IpAddressUtil.isValidPort(init.port)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'port');
    }
    if (init.profile === TransportProfile.P_BLOCKED) {
      throw AppErrors.of('TLS_PROFILE_INCONSISTENT', []);
    }
    if (!ProtocolConstants.KEY_ID_PATTERN.test(init.keyId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'keyId');
    }
    if (init.credentialAlias !== StorageConstants.gatewayHmacAlias(init.gatewayId)) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (init.profile === TransportProfile.P_HMAC) {
      if (init.tlsEnabled || init.pins.length !== 0 || init.pinAlg.length !== 0) {
        throw AppErrors.of('TLS_PROFILE_INCONSISTENT', []);
      }
    } else if (init.profile === TransportProfile.P_TLS_PIN) {
      if (!init.tlsEnabled || init.pins.length < 1 ||
        init.pins.length > ProtocolConstants.MAX_PIN_COUNT || init.pinAlg !== 'sha256-spki-der') {
        throw AppErrors.of('TLS_PROFILE_INCONSISTENT', []);
      }
      for (let index = 0; index < init.pins.length; index++) {
        if (!ProtocolConstants.PIN_PATTERN.test(init.pins[index])) {
          throw AppErrors.of('TLS_PIN_CONFIG_INVALID', []);
        }
      }
    } else {
      throw AppErrors.of('TLS_PROFILE_INCONSISTENT', []);
    }
    DateTimeUtil.parseUtcCompact(init.createdAt);
    DateTimeUtil.parseUtcCompact(init.updatedAt);
    if (init.lastSeenAt !== undefined) {
      DateTimeUtil.parseUtcCompact(init.lastSeenAt);
    }
    return new GatewayRoute(init);
  }
}
