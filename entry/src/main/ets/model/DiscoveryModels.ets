/*
 * YaoCore C-02/C-18 discovery models.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Extended: T-23 / wp-090-ports (2026-10-18) — C-18 discovery control models
 * moved from service/gateway/DiscoveryModels.ets (DES-A §27.6.3 P2).
 * Contract: DES-A §5.1.5, §6.1.2, §15.1, §15.4, §21.2
 */
import { AppErrors } from '../common/types/AppError';
import { ProtocolConstants } from '../common/constants/ProtocolConstants';
import { ProtocolDeviation } from '../common/types/ProtocolDeviation';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import { DeviceSnapshot } from './DeviceState';
import type { AppError } from '../common/types/AppError';
import type { CancellationToken } from '../common/types/CancellationToken';
import { IpAddressUtil } from '../common/utils/IpAddressUtil';
import { TransportProfile } from './DeviceTypes';
import { GatewayAddress } from './GatewayRoute';

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

// ---- C-18 discovery control models (T-23 migration) -----------------------

export enum DiscoverySource {
  LAST_KNOWN = 'LAST_KNOWN',
  MDNS = 'MDNS',
  UDP = 'UDP',
  MANUAL = 'MANUAL'
}

export enum DiscoveryTransportKind {
  MDNS = 'MDNS',
  UDP = 'UDP'
}

export class DiscoveryCandidate {
  readonly address: GatewayAddress;
  readonly source: DiscoverySource;
  readonly gatewayIdHint?: string;
  readonly gatewayNameHint?: string;
  readonly verified: boolean;
  readonly gatewayId?: string;
  readonly profile?: TransportProfile;
  readonly latencyMs?: number;
  readonly lastSeenMs: number;
  readonly errorCode?: string;

  constructor(address: GatewayAddress, source: DiscoverySource, gatewayIdHint: string | undefined,
    gatewayNameHint: string | undefined, verified: boolean, gatewayId: string | undefined,
    profile: TransportProfile | undefined, latencyMs: number | undefined, lastSeenMs: number,
    errorCode?: string) {
    if (!Number.isFinite(lastSeenMs) || lastSeenMs < 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (latencyMs !== undefined && (!Number.isFinite(latencyMs) || latencyMs < 0)) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (verified) {
      // Only a signed discover whose identity equals the bound route may be
      // verified. A locator hint alone is never enough.
      if (gatewayId === undefined || gatewayId.length === 0 ||
        gatewayId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
        gatewayId.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(gatewayId)) {
        throw AppErrors.of('CONFIGURATION_ERROR', []);
      }
    }
    this.address = address;
    this.source = source;
    this.gatewayIdHint = gatewayIdHint;
    this.gatewayNameHint = gatewayNameHint;
    this.verified = verified;
    this.gatewayId = gatewayId;
    this.profile = profile;
    this.latencyMs = latencyMs;
    this.lastSeenMs = lastSeenMs;
    this.errorCode = errorCode;
  }
}

export class DiscoveryOptions {
  readonly familyId: string;
  readonly includeMdns: boolean;
  readonly includeUdp: boolean;
  readonly timeoutMs: number;
  readonly manualAddress?: GatewayAddress;
  readonly cancellation?: CancellationToken;

  constructor(familyId: string, includeMdns: boolean = true, includeUdp: boolean = false,
    timeoutMs: number = 3000, manualAddress?: GatewayAddress,
    cancellation?: CancellationToken) {
    if (familyId.length === 0 || familyId.length > 63) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'familyId');
    }
    if (!Number.isInteger(timeoutMs) || timeoutMs <= 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.familyId = familyId;
    this.includeMdns = includeMdns;
    this.includeUdp = includeUdp;
    this.timeoutMs = timeoutMs;
    this.manualAddress = manualAddress;
    this.cancellation = cancellation;
  }
}

export class DiscoveryReport {
  readonly candidates: ReadonlyArray<DiscoveryCandidate>;
  readonly verified: ReadonlyArray<DiscoveryCandidate>;
  readonly warnings: ReadonlyArray<AppError>;
  readonly elapsedMs: number;

  constructor(candidates: ReadonlyArray<DiscoveryCandidate>,
    warnings: ReadonlyArray<AppError>, elapsedMs: number) {
    const verified: DiscoveryCandidate[] = [];
    for (let index = 0; index < candidates.length; index++) {
      if (candidates[index].verified) {
        verified.push(candidates[index]);
      }
    }
    if (!Number.isFinite(elapsedMs) || elapsedMs < 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.candidates = candidates;
    this.verified = verified;
    this.warnings = warnings;
    this.elapsedMs = elapsedMs;
  }
}

/** One locator beacon (mDNS or, after PB-01, UDP). Never identity. */
export class DiscoveryBeacon {
  readonly address: GatewayAddress;
  readonly gatewayIdHint?: string;
  readonly gatewayNameHint?: string;
  /** Diagnostics only; never used for identity or binding. */
  readonly raw?: Uint8Array;
  readonly receivedAtMs: number;

  constructor(address: GatewayAddress, gatewayIdHint: string | undefined,
    gatewayNameHint: string | undefined, receivedAtMs: number, raw?: Uint8Array) {
    // F-10: locator sources must not point the app at loopback/link-local/
    // multicast/broadcast destinations even though they can never verify.
    if (!IpAddressUtil.isAllowedLanIpv4(address.ip) || !IpAddressUtil.isValidPort(address.port)) {
      throw AppErrors.of('DISCOVERY_INVALID_RESPONSE', []);
    }
    if (!Number.isFinite(receivedAtMs) || receivedAtMs < 0) {
      throw AppErrors.of('DISCOVERY_INVALID_RESPONSE', []);
    }
    this.address = address;
    this.gatewayIdHint = gatewayIdHint;
    this.gatewayNameHint = gatewayNameHint;
    this.receivedAtMs = receivedAtMs;
    this.raw = raw;
  }
}
