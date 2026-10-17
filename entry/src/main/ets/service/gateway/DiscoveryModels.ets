/*
 * YaoCore C-18 discovery control models and PB-01 seam.
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §15.1, §15.4, §21.2
 *
 * These are pure value objects/interfaces. A `gatewayIdHint` is a locator hint
 * only; it can never create or verify a binding (PR-06). UDP/mDNS wire formats
 * remain UNRESOLVED (PB-01), so the seam exposes locators only.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';
import type { CancellationToken } from '../../common/types/Ports';
import { IpAddressUtil } from '../../common/utils/IpAddressUtil';
import { TransportProfile } from '../../model/DeviceTypes';
import { GatewayAddress } from '../../model/GatewayRoute';

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

/**
 * PB-01 seam. Implementations return locators only. The raw UDP packet format
 * and the mDNS service type/TXT schema are UNRESOLVED; production code must not
 * install a raw UDP adapter before the architecture decision closes PB-01.
 */
export interface DiscoveryTransport {
  readonly kind: DiscoveryTransportKind;
  scan(timeoutMs: number, cancellation?: CancellationToken): Promise<ReadonlyArray<DiscoveryBeacon>>;
}
