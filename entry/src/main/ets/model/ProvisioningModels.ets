/*
 * YaoCore C-02 provisioning identity/result models.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §5.1.6
 */
import { AppErrors } from '../common/types/AppError';
import { ProtocolConstants } from '../common/constants/ProtocolConstants';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import { IpAddressUtil } from '../common/utils/IpAddressUtil';

export enum IdentityVersion {
  V20 = '2.0',
  V21 = '2.1'
}

export class ProvisioningTlsMaterial {
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

export class BleProvisioningIdentity {
  readonly version: IdentityVersion;
  readonly gatewayId: string;
  readonly gatewayName: string;
  readonly tls?: ProvisioningTlsMaterial;

  constructor(version: IdentityVersion, gatewayId: string, gatewayName: string,
    tls?: ProvisioningTlsMaterial) {
    if (gatewayId.length === 0 || gatewayId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      gatewayId.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(gatewayId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'gatewayId');
    }
    if (gatewayName.length === 0 ||
      gatewayName.length > ProtocolConstants.MAX_GATEWAY_NAME_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'gatewayName');
    }
    if (version === IdentityVersion.V20 && tls !== undefined) {
      throw AppErrors.of('PROVISIONING_IDENTITY_INVALID', []);
    }
    this.version = version;
    this.gatewayId = gatewayId;
    this.gatewayName = gatewayName;
    this.tls = tls;
  }
}

export class BleProvisioningResult {
  readonly identity: BleProvisioningIdentity;
  readonly ip: string;
  readonly port: number;
  readonly boardLedConfirmed: boolean;
  readonly credentialDraftId: string;
  readonly completedAt: string;

  constructor(identity: BleProvisioningIdentity, ip: string, port: number, boardLedConfirmed: boolean,
    credentialDraftId: string, completedAt: string) {
    if (!IpAddressUtil.isValidIpv4(ip) || !IpAddressUtil.isValidPort(port)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'address');
    }
    const expectedPort = identity.tls === undefined ? ProtocolConstants.DEFAULT_GATEWAY_PORT :
      identity.tls.port;
    if (port !== expectedPort) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    DateTimeUtil.parseUtcCompact(completedAt);
    this.identity = identity;
    this.ip = ip;
    this.port = port;
    this.boardLedConfirmed = boardLedConfirmed;
    this.credentialDraftId = credentialDraftId;
    this.completedAt = completedAt;
  }
}
