/*
 * YaoCore C-17/C-18 transport ports and client contracts.
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §14.1.1/§14.1.3, §15.1, §15.4, §19.3, §3.7
 *
 * Port-only declarations: no @ohos import, no platform behaviour. Production
 * adapters live under service/gateway/adapters/** and are assembled only by the
 * composition root (C-28) or ohosTest.
 *
 * DES-A §3.7 nominally places ports under contracts/**. T-11's delegated write
 * scope covers service/**, so - following the recorded T-06/T-07/T-08 location
 * exception - the gateway ports stay next to their pure-logic consumers. They
 * contain no implementation and can still be imported by host tests.
 */
import { AppErrors } from '../../common/types/AppError';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';
import { HttpHeaders } from '../../common/types/HttpHeaders';
import { IpAddressUtil } from '../../common/utils/IpAddressUtil';
import { TransportProfile } from '../../model/DeviceTypes';
import { GatewayAddress } from '../../model/GatewayRoute';
import { DeviceControlCommand, ControlOutcome } from '../../model/ControlModels';
import { DiscoverySnapshot } from '../../model/DiscoveryModels';
import type { GatewayCredentialPort } from '../../repository/GatewayPorts';

const PIN_ALG_SHA256_SPKI: string = 'sha256-spki-der';

export class HttpRequest {
  readonly method: string;
  readonly url: string;
  readonly headers: HttpHeaders;
  readonly body?: Uint8Array;
  readonly connectTimeoutMs: number;
  readonly readTimeoutMs: number;

  constructor(method: string, url: string, headers: HttpHeaders, body: Uint8Array | undefined,
    connectTimeoutMs: number, readTimeoutMs: number) {
    if (method !== 'GET' && method !== 'POST') {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (url.length === 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (!Number.isInteger(connectTimeoutMs) || connectTimeoutMs <= 0 ||
      !Number.isInteger(readTimeoutMs) || readTimeoutMs <= 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.method = method;
    this.url = url;
    this.headers = headers;
    this.body = body;
    this.connectTimeoutMs = connectTimeoutMs;
    this.readTimeoutMs = readTimeoutMs;
  }
}

/** TLS verification evidence produced before any HTTP byte is written. */
export class TlsVerification {
  readonly matchedPin: string;
  readonly protocolVersion: string;
  readonly peerSpkiSha256Hex: string;

  constructor(matchedPin: string, protocolVersion: string, peerSpkiSha256Hex: string) {
    if (!ProtocolConstants.PIN_PATTERN.test(matchedPin) ||
      !ProtocolConstants.PIN_PATTERN.test(peerSpkiSha256Hex)) {
      throw AppErrors.of('TLS_PIN_CONFIG_INVALID', []);
    }
    this.matchedPin = matchedPin;
    this.protocolVersion = protocolVersion;
    this.peerSpkiSha256Hex = peerSpkiSha256Hex;
  }
}

export class HttpResponse {
  readonly statusCode: number;
  readonly headers: HttpHeaders;
  readonly body: Uint8Array;
  readonly receivedAtMs: number;
  /**
   * DES-A §14.2.4 returns `tlsPinMatched` from probe(). The transport is the
   * only layer that knows which pin matched, so the verification evidence is
   * carried on the response instead of re-opening a second TLS connection.
   */
  readonly tlsVerification?: TlsVerification;

  constructor(statusCode: number, headers: HttpHeaders, body: Uint8Array, receivedAtMs: number,
    tlsVerification?: TlsVerification) {
    if (!Number.isInteger(statusCode) || statusCode < 100 || statusCode > 599) {
      throw AppErrors.of('LOCAL_REQUEST_FAILED', []);
    }
    this.statusCode = statusCode;
    this.headers = headers;
    this.body = body;
    this.receivedAtMs = receivedAtMs;
    this.tlsVerification = tlsVerification;
  }
}

export class TlsPolicy {
  readonly enabled: boolean;
  readonly pins: ReadonlyArray<string>;
  readonly port: number;
  readonly pinAlg: string;

  constructor(enabled: boolean, pins: ReadonlyArray<string>, port: number, pinAlg: string) {
    if (!enabled) {
      throw AppErrors.of('TLS_PROFILE_INCONSISTENT', []);
    }
    if (pins.length < 1 || pins.length > ProtocolConstants.MAX_PIN_COUNT) {
      throw AppErrors.of('TLS_PIN_CONFIG_INVALID', []);
    }
    for (let index = 0; index < pins.length; index++) {
      if (!ProtocolConstants.PIN_PATTERN.test(pins[index])) {
        throw AppErrors.of('TLS_PIN_CONFIG_INVALID', []);
      }
    }
    if (!IpAddressUtil.isValidPort(port) || pinAlg !== PIN_ALG_SHA256_SPKI) {
      throw AppErrors.of('TLS_PIN_CONFIG_INVALID', []);
    }
    this.enabled = enabled;
    this.pins = pins;
    this.port = port;
    this.pinAlg = pinAlg;
  }
}

/**
 * HTTP transport seam (DES-A §14.1.3). Implementations MUST complete the TLS
 * pin verification before returning any response and MUST NOT fall back to
 * cleartext after a TLS failure (ADR-002 §6.2-4).
 */
export interface HttpTransport {
  send(request: HttpRequest, tls: TlsPolicy | undefined): Promise<HttpResponse>;
}

export interface TlsPinVerifier {
  verify(host: string, port: number, pins: ReadonlyArray<string>,
    timeoutMs: number): Promise<TlsVerification>;
}

/** One signed-discover target. Address/profile/pins come from a bound route. */
export class GatewayTarget {
  readonly gatewayId: string;
  readonly familyId: string;
  readonly address: GatewayAddress;
  readonly profile: TransportProfile;
  readonly pins: ReadonlyArray<string>;
  readonly port: number;
  readonly credentialAlias: string;

  constructor(gatewayId: string, familyId: string, address: GatewayAddress,
    profile: TransportProfile, pins: ReadonlyArray<string>, port: number,
    credentialAlias: string) {
    if (gatewayId.length === 0 || gatewayId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      gatewayId.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(gatewayId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'gatewayId');
    }
    if (familyId.length === 0 || familyId.length > 63) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'familyId');
    }
    if (!IpAddressUtil.isValidPort(port) || port !== address.port) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'port');
    }
    if (profile !== TransportProfile.P_HMAC && profile !== TransportProfile.P_TLS_PIN &&
      profile !== TransportProfile.P_BLOCKED) {
      throw AppErrors.of('TLS_PROFILE_INCONSISTENT', []);
    }
    if (credentialAlias.length === 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.gatewayId = gatewayId;
    this.familyId = familyId;
    this.address = address;
    this.profile = profile;
    this.pins = pins;
    this.port = port;
    this.credentialAlias = credentialAlias;
  }
}

export class ProbeResult {
  readonly reachable: boolean;
  readonly gatewayId: string;
  readonly gatewayName: string;
  readonly profile: TransportProfile;
  readonly tlsPinMatched?: string;
  readonly latencyMs: number;
  readonly snapshot?: DiscoverySnapshot;

  constructor(reachable: boolean, gatewayId: string, gatewayName: string,
    profile: TransportProfile, tlsPinMatched: string | undefined, latencyMs: number,
    snapshot?: DiscoverySnapshot) {
    if (reachable && (gatewayId.length === 0 || gatewayName.length === 0)) {
      throw AppErrors.of('DISCOVERY_INVALID_RESPONSE', []);
    }
    if (!Number.isFinite(latencyMs) || latencyMs < 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.reachable = reachable;
    this.gatewayId = gatewayId;
    this.gatewayName = gatewayName;
    this.profile = profile;
    this.tlsPinMatched = tlsPinMatched;
    this.latencyMs = latencyMs;
    this.snapshot = snapshot;
  }
}

export interface IGatewayClient {
  discover(target: GatewayTarget): Promise<DiscoverySnapshot>;
  control(target: GatewayTarget, command: DeviceControlCommand): Promise<ControlOutcome>;
  probe(target: GatewayTarget, credentials?: GatewayCredentialPort): Promise<ProbeResult>;
}
