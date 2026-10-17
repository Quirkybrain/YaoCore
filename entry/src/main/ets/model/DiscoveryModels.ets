/*
 * YaoCore C-02 discovery snapshot.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §5.1.5, §6.1.2
 */
import { AppErrors } from '../common/types/AppError';
import { ProtocolConstants } from '../common/constants/ProtocolConstants';
import { ProtocolDeviation } from '../common/types/ProtocolDeviation';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import { DeviceSnapshot } from './DeviceState';

export class DiscoverySecurity {
  readonly alg: string;
  readonly keyId: string;
  readonly timeWindowSeconds: number;
  readonly nonceTtlSeconds: number;

  constructor(alg: string, keyId: string, timeWindowSeconds: number, nonceTtlSeconds: number) {
    if (alg !== ProtocolConstants.ALG_HMAC_SHA256 || keyId !== ProtocolConstants.KEY_ID_V1 ||
      timeWindowSeconds !== ProtocolConstants.TIME_WINDOW_SECONDS ||
      nonceTtlSeconds !== ProtocolConstants.NONCE_TTL_SECONDS) {
      throw AppErrors.of('DISCOVERY_INVALID_RESPONSE', []);
    }
    this.alg = alg;
    this.keyId = keyId;
    this.timeWindowSeconds = timeWindowSeconds;
    this.nonceTtlSeconds = nonceTtlSeconds;
  }
}

export class DiscoverySnapshotInit {
  gatewayId: string = '';
  gatewayName: string = '';
  serviceId: string = ProtocolConstants.SERVICE_ID_CLOUD;
  protocolVersion: string = ProtocolConstants.PROTOCOL_VERSION_20;
  generatedAt: string = '';
  security: DiscoverySecurity = new DiscoverySecurity(ProtocolConstants.ALG_HMAC_SHA256,
    ProtocolConstants.KEY_ID_V1, ProtocolConstants.TIME_WINDOW_SECONDS, ProtocolConstants.NONCE_TTL_SECONDS);
  devices: ReadonlyArray<DeviceSnapshot> = [];
  isPartial: boolean = false;
  aliasUsed: boolean = false;
  deviations: ReadonlyArray<ProtocolDeviation> = [];
}

export class DiscoverySnapshot {
  readonly gatewayId: string;
  readonly gatewayName: string;
  readonly serviceId: string;
  readonly protocolVersion: string;
  readonly generatedAt: string;
  readonly security: DiscoverySecurity;
  readonly devices: ReadonlyArray<DeviceSnapshot>;
  readonly isPartial: boolean;
  /** Diagnostic only: at least one device used an inbound alias wire field. */
  readonly aliasUsed: boolean;
  readonly deviations: ReadonlyArray<ProtocolDeviation>;

  private constructor(init: DiscoverySnapshotInit) {
    this.gatewayId = init.gatewayId;
    this.gatewayName = init.gatewayName;
    this.serviceId = init.serviceId;
    this.protocolVersion = init.protocolVersion;
    this.generatedAt = init.generatedAt;
    this.security = init.security;
    this.devices = init.devices;
    this.isPartial = init.isPartial;
    this.aliasUsed = init.aliasUsed;
    this.deviations = init.deviations;
  }

  static create(init: DiscoverySnapshotInit): DiscoverySnapshot {
    if (init.gatewayId.length === 0 || init.gatewayId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      init.gatewayId.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(init.gatewayId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'gatewayId');
    }
    if (init.gatewayName.length === 0 ||
      init.gatewayName.length > ProtocolConstants.MAX_GATEWAY_NAME_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'gatewayName');
    }
    if (init.serviceId !== ProtocolConstants.SERVICE_ID_CLOUD ||
      init.protocolVersion !== ProtocolConstants.PROTOCOL_VERSION_20) {
      throw AppErrors.of('DISCOVERY_INVALID_RESPONSE', []);
    }
    DateTimeUtil.parseUtcCompact(init.generatedAt);
    return new DiscoverySnapshot(init);
  }
}
