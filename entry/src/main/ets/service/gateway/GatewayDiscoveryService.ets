/*
 * YaoCore C-18 GatewayDiscoveryService.
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §15.1-§15.6, §21; ADR-004 §5.2; PR-06/PR-13; PB-01
 *
 * Discovery only locates. A candidate becomes `verified` exclusively through a
 * signed discover probe whose response identity equals the bound route's
 * gatewayId and whose runtime profile equals the route profile. mDNS/UDP hints,
 * broadcast names, MAC addresses and neighbour ordering never create a binding.
 *
 * PB-01 remains UNRESOLVED: no raw UDP adapter exists; callers may inject only
 * fake/test transports. mDNS is optional and its service type is configured by
 * the adapter constructor, never guessed here.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import type { CancellationToken, ClockPort, LoggerPort } from '../../common/types/Ports';
import { GatewayAddress, GatewayRoute } from '../../model/GatewayRoute';
import { TransportProfile } from '../../model/DeviceTypes';
import type { GatewayAddressPort, GatewayRoutePort } from '../../repository/GatewayPorts';
import type { IGatewayClient, GatewayTarget, ProbeResult } from './GatewayTransportPorts';
import { GatewayTarget as GatewayTargetValue } from './GatewayTransportPorts';
import {
  DiscoveryBeacon,
  DiscoveryCandidate,
  DiscoveryOptions,
  DiscoveryReport,
  DiscoverySource
} from './DiscoveryModels';
import type { DiscoveryTransport } from './DiscoveryModels';
import { ManualAddressPolicy } from './ManualAddressPolicy';

const DEFAULT_PROBE_TIMEOUT_MS: number = 1500;
const MANUAL_MIN_INTERVAL_MS: number = 2000;
const MANUAL_FAILURE_LIMIT: number = 5;

class OrderedCandidates {
  readonly candidates: ReadonlyArray<DiscoveryCandidate>;
  readonly verified: ReadonlyArray<DiscoveryCandidate>;

  constructor(candidates: ReadonlyArray<DiscoveryCandidate>,
    verified: ReadonlyArray<DiscoveryCandidate>) {
    this.candidates = candidates;
    this.verified = verified;
  }
}

export class GatewayDiscoveryService {
  private readonly client: IGatewayClient;
  private readonly routes: GatewayRoutePort;
  private readonly mdns: DiscoveryTransport | undefined;
  private readonly udp: DiscoveryTransport | undefined;
  private readonly addresses: GatewayAddressPort;
  private readonly clock: ClockPort;
  private readonly logger: LoggerPort;
  private readonly probeTimeoutMs: number;
  private readonly lastManualProbeMs: Map<string, number> = new Map<string, number>();
  private readonly manualFailures: Map<string, number> = new Map<string, number>();

  constructor(client: IGatewayClient, routes: GatewayRoutePort,
    mdns: DiscoveryTransport | undefined, udp: DiscoveryTransport | undefined,
    addresses: GatewayAddressPort, clock: ClockPort, logger: LoggerPort,
    probeTimeoutMs: number = DEFAULT_PROBE_TIMEOUT_MS) {
    if (!Number.isInteger(probeTimeoutMs) || probeTimeoutMs <= 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.client = client;
    this.routes = routes;
    this.mdns = mdns;
    this.udp = udp;
    this.addresses = addresses;
    this.clock = clock;
    this.logger = logger;
    this.probeTimeoutMs = probeTimeoutMs;
  }

  async discoverBound(options: DiscoveryOptions): Promise<DiscoveryReport> {
    this.throwIfCancelled(options.cancellation);
    const startedAtMs = this.nowMs();
    const routes = await this.routes.listRoutesByFamily(options.familyId);
    const candidates: DiscoveryCandidate[] = [];
    const warnings: AppError[] = [];

    // 1. LAST_KNOWN: each route is probed independently; one failure never
    // blocks another route.
    for (let index = 0; index < routes.length; index++) {
      this.throwIfCancelled(options.cancellation);
      const route = routes[index];
      const ip = route.lastKnownIp.length > 0 ? route.lastKnownIp : route.localIp;
      if (ip.length === 0) {
        continue;
      }
      const address = new GatewayAddress(ip, route.port);
      try {
        candidates.push(await this.probeRoute(route, DiscoverySource.LAST_KNOWN, address));
      } catch (error) {
        const appError = GatewayDiscoveryService.asAppError(error);
        warnings.push(appError);
        candidates.push(this.unverified(route, DiscoverySource.LAST_KNOWN, address, appError.code));
      }
    }

    // 2. mDNS: optional locator source. A hint that exactly matches a bound
    // route may trigger a signed probe; any other beacon stays unverified.
    if (options.includeMdns && this.mdns !== undefined) {
      try {
        const beacons = await this.mdns.scan(options.timeoutMs, options.cancellation);
        for (let index = 0; index < beacons.length; index++) {
          this.throwIfCancelled(options.cancellation);
          await this.consumeBeacon(beacons[index], routes, candidates, warnings);
        }
      } catch (error) {
        warnings.push(AppErrors.of('DISCOVERY_TRANSPORT_UNAVAILABLE', []));
        this.logger.warn('GatewayDiscovery', 'mdns_scan_failed',
          [new NameValue('code', GatewayDiscoveryService.asAppError(error).code)]);
      }
      this.throwIfCancelled(options.cancellation);
    }

    // 3. MANUAL: only already-bound gateways may be probed at a manual address.
    // No unbound address ever becomes a candidate.
    if (options.manualAddress !== undefined) {
      for (let index = 0; index < routes.length; index++) {
        this.throwIfCancelled(options.cancellation);
        try {
          candidates.push(await this.probeManual(routes[index].gatewayId, options.manualAddress));
        } catch (error) {
          warnings.push(GatewayDiscoveryService.asAppError(error));
        }
      }
      this.throwIfCancelled(options.cancellation);
    }

    // 4. UDP: PB-01 unresolved. A missing adapter is a warning; an injected
    // (test) adapter yields locators only and can never verify.
    if (options.includeUdp) {
      if (this.udp === undefined) {
        warnings.push(AppErrors.of('DISCOVERY_TRANSPORT_UNAVAILABLE', []));
      } else {
        try {
          const beacons = await this.udp.scan(options.timeoutMs, options.cancellation);
          for (let index = 0; index < beacons.length; index++) {
            candidates.push(this.unverifiedBeacon(beacons[index], DiscoverySource.UDP));
          }
        } catch (error) {
          warnings.push(AppErrors.of('DISCOVERY_TRANSPORT_UNAVAILABLE', []));
          this.logger.warn('GatewayDiscovery', 'udp_scan_failed',
            [new NameValue('code', GatewayDiscoveryService.asAppError(error).code)]);
        }
      }
      this.throwIfCancelled(options.cancellation);
    }

    const ordered = GatewayDiscoveryService.order(candidates);
    if (ordered.candidates.length === 0) {
      warnings.push(AppErrors.of('DISCOVERY_NO_CANDIDATES', []));
    }
    const elapsedMs = Math.max(0, this.nowMs() - startedAtMs);
    this.logger.info('GatewayDiscovery', 'discovery_complete',
      [new NameValue('familyId', options.familyId),
        new NameValue('candidates', String(ordered.candidates.length)),
        new NameValue('verified', String(ordered.verified.length))]);
    return new DiscoveryReport(ordered.candidates, warnings, elapsedMs);
  }

  async probeManual(gatewayId: string, address: GatewayAddress): Promise<DiscoveryCandidate> {
    const validated = ManualAddressPolicy.validate(address.ip, address.port);
    const route = ManualAddressPolicy.requireBound(await this.routes.getRoute(gatewayId));
    if (!(await this.routes.isBound(gatewayId))) {
      throw AppErrors.of('MANUAL_ADDRESS_NOT_BOUND', []);
    }
    const nowMs = this.nowMs();
    const lastMs = this.lastManualProbeMs.get(gatewayId);
    if (lastMs !== undefined && nowMs - lastMs < MANUAL_MIN_INTERVAL_MS) {
      throw AppErrors.of('MANUAL_ADDRESS_REJECTED', []);
    }
    const failures = this.manualFailures.get(gatewayId);
    if (failures !== undefined && failures >= MANUAL_FAILURE_LIMIT) {
      throw AppErrors.of('MANUAL_ADDRESS_REJECTED', []);
    }
    this.lastManualProbeMs.set(gatewayId, nowMs);
    try {
      const candidate = await this.probeRoute(route, DiscoverySource.MANUAL, validated);
      this.manualFailures.delete(gatewayId);
      await this.addresses.updateLastKnownAddress(gatewayId, validated);
      return candidate;
    } catch (error) {
      const next = (failures === undefined ? 0 : failures) + 1;
      this.manualFailures.set(gatewayId, next);
      throw GatewayDiscoveryService.asAppError(error);
    }
  }

  async probeLastKnown(gatewayId: string): Promise<DiscoveryCandidate | undefined> {
    const route = await this.routes.getRoute(gatewayId);
    if (route === undefined) {
      return undefined;
    }
    const ip = route.lastKnownIp.length > 0 ? route.lastKnownIp : route.localIp;
    if (ip.length === 0) {
      return undefined;
    }
    const address = new GatewayAddress(ip, route.port);
    try {
      return await this.probeRoute(route, DiscoverySource.LAST_KNOWN, address);
    } catch (error) {
      const appError = GatewayDiscoveryService.asAppError(error);
      if (appError.code === 'GATEWAY_ID_MISMATCH') {
        throw appError;
      }
      return this.unverified(route, DiscoverySource.LAST_KNOWN, address, appError.code);
    }
  }

  /**
   * F-10: explicit user action (retry / address change) clears the manual
   * failure budget and the >=2s interval gate. Automatic discovery never calls
   * this, so the rate limit cannot be bypassed opportunistically.
   */
  resetManualFailures(gatewayId: string): void {
    this.manualFailures.delete(gatewayId);
    this.lastManualProbeMs.delete(gatewayId);
  }

  /**
   * Probes one bound route and returns a verified candidate only when the
   * signed discover identity, runtime profile and (for P-TLS-PIN) pin evidence
   * match the route. This is an independent service-layer fail-closed check in
   * addition to the C-17 probe check (T-11 F-03).
   */
  private async probeRoute(route: GatewayRoute, source: DiscoverySource,
    address: GatewayAddress): Promise<DiscoveryCandidate> {
    const target = GatewayDiscoveryService.targetOf(route, address);
    const probe = await this.withProbeTimeout(this.client.probe(target));
    if (!probe.reachable) {
      throw AppErrors.transport('GATEWAY_UNREACHABLE');
    }
    if (probe.gatewayId !== route.gatewayId) {
      throw AppErrors.gateway('GATEWAY_ID_MISMATCH', route.gatewayId);
    }
    this.requireRouteTlsEvidence(route, probe);
    return new DiscoveryCandidate(address, source, undefined, probe.gatewayName, true,
      probe.gatewayId, probe.profile, probe.latencyMs, this.nowMs());
  }

  private async consumeBeacon(beacon: DiscoveryBeacon, routes: ReadonlyArray<GatewayRoute>,
    candidates: DiscoveryCandidate[], warnings: AppError[]): Promise<void> {
    const route = GatewayDiscoveryService.matchBound(beacon.gatewayIdHint, routes);
    if (route === undefined) {
      candidates.push(this.unverifiedBeacon(beacon, DiscoverySource.MDNS));
      return;
    }
    try {
      const target = GatewayDiscoveryService.targetOf(route, beacon.address);
      const probe = await this.withProbeTimeout(this.client.probe(target));
      if (!probe.reachable) {
        warnings.push(AppErrors.gateway('GATEWAY_UNREACHABLE', route.gatewayId));
        candidates.push(this.unverifiedBeacon(beacon, DiscoverySource.MDNS, 'GATEWAY_UNREACHABLE'));
        return;
      }
      if (probe.gatewayId !== route.gatewayId) {
        warnings.push(AppErrors.gateway('GATEWAY_ID_MISMATCH', route.gatewayId));
        candidates.push(this.unverifiedBeacon(beacon, DiscoverySource.MDNS, 'GATEWAY_ID_MISMATCH'));
        return;
      }
      // F-09: profile incompatibility is TLS_PROFILE_INCONSISTENT, not an
      // identity mismatch. requireRouteTlsEvidence also checks pin evidence.
      this.requireRouteTlsEvidence(route, probe);
      candidates.push(new DiscoveryCandidate(beacon.address, DiscoverySource.MDNS,
        beacon.gatewayIdHint, probe.gatewayName, true, probe.gatewayId, probe.profile,
        probe.latencyMs, this.nowMs()));
    } catch (error) {
      const appError = GatewayDiscoveryService.asAppError(error);
      warnings.push(appError);
      candidates.push(this.unverifiedBeacon(beacon, DiscoverySource.MDNS, appError.code));
    }
  }

  /**
   * F-03/F-09: verified P-TLS-PIN candidates need a matched pin that belongs to
   * the bound route. A probe without evidence is never promoted to verified.
   */
  private requireRouteTlsEvidence(route: GatewayRoute, probe: ProbeResult): void {
    if (probe.profile !== route.profile) {
      this.logTlsEvent(route, 'TLS_PROFILE_INCONSISTENT');
      throw AppErrors.of('TLS_PROFILE_INCONSISTENT', []);
    }
    if (route.profile !== TransportProfile.P_TLS_PIN) {
      return;
    }
    if (probe.tlsPinMatched === undefined) {
      this.logTlsEvent(route, 'TLS_VERIFIER_UNAVAILABLE');
      throw AppErrors.of('TLS_VERIFIER_UNAVAILABLE', []);
    }
    if (route.pins.indexOf(probe.tlsPinMatched) < 0) {
      this.logTlsEvent(route, 'TLS_PIN_MISMATCH');
      throw AppErrors.of('TLS_PIN_MISMATCH', []);
    }
  }

  /** F-05: gatewayId/profile/errorCode/time only; no secret or certificate. */
  private logTlsEvent(route: GatewayRoute, errorCode: string): void {
    this.logger.warn('GatewayDiscovery', 'tls_security_event', [
      new NameValue('gatewayId', route.gatewayId),
      new NameValue('profile', String(route.profile)),
      new NameValue('errorCode', errorCode),
      new NameValue('atMs', String(this.nowMs()))
    ]);
  }

  private unverified(route: GatewayRoute, source: DiscoverySource, address: GatewayAddress,
    errorCode: string): DiscoveryCandidate {
    return new DiscoveryCandidate(address, source, route.gatewayId, route.gatewayName, false,
      undefined, undefined, undefined, this.nowMs(), errorCode);
  }

  private unverifiedBeacon(beacon: DiscoveryBeacon, source: DiscoverySource,
    errorCode?: string): DiscoveryCandidate {
    return new DiscoveryCandidate(beacon.address, source, beacon.gatewayIdHint,
      beacon.gatewayNameHint, false, undefined, undefined, undefined, this.nowMs(),
      errorCode);
  }

  /**
   * U-01 / T-15 fix: the executor reject parameter is typed as AppError. ArkTS
   * rejects passing an AppError to a callback declared as `(reason: Error)`
   * (arkts-no-structural-typing); callers still receive the exact AppError code
   * instead of a generic Error wrapper.
   */
  private withProbeTimeout(promise: Promise<ProbeResult>): Promise<ProbeResult> {
    return new Promise<ProbeResult>((resolve: (value: ProbeResult) => void,
      reject: (reason: AppError) => void): void => {
      let settled = false;
      const timer = setTimeout(() => {
        if (!settled) {
          settled = true;
          reject(AppErrors.transport('GATEWAY_TIMEOUT'));
        }
      }, this.probeTimeoutMs);
      promise.then((value: ProbeResult) => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          resolve(value);
        }
      }).catch((error: Object) => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          reject(GatewayDiscoveryService.asAppError(error));
        }
      });
    });
  }

  private nowMs(): number {
    const value = this.clock.nowMs();
    if (!Number.isFinite(value)) {
      throw AppErrors.internal('clock');
    }
    return Math.floor(value);
  }

  private throwIfCancelled(cancellation?: CancellationToken): void {
    if (cancellation !== undefined) {
      cancellation.throwIfCancelled();
    }
  }

  private static targetOf(route: GatewayRoute, address: GatewayAddress): GatewayTarget {
    return new GatewayTargetValue(route.gatewayId, route.familyId, address, route.profile,
      route.pins, address.port, route.credentialAlias);
  }

  private static matchBound(hint: string | undefined,
    routes: ReadonlyArray<GatewayRoute>): GatewayRoute | undefined {
    if (hint === undefined) {
      return undefined;
    }
    for (let index = 0; index < routes.length; index++) {
      if (routes[index].gatewayId === hint) {
        return routes[index];
      }
    }
    return undefined;
  }

  private static order(candidates: ReadonlyArray<DiscoveryCandidate>): OrderedCandidates {
    const byKey: Map<string, DiscoveryCandidate> = new Map<string, DiscoveryCandidate>();
    for (let index = 0; index < candidates.length; index++) {
      const candidate = candidates[index];
      const identity = candidate.gatewayId === undefined ?
        (candidate.gatewayIdHint === undefined ? '' : candidate.gatewayIdHint) :
        candidate.gatewayId;
      const key = identity + '|' + candidate.address.ip + ':' + String(candidate.address.port);
      const existing = byKey.get(key);
      if (existing === undefined || GatewayDiscoveryService.better(candidate, existing)) {
        byKey.set(key, candidate);
      }
    }
    const deduped: DiscoveryCandidate[] = [];
    byKey.forEach((candidate: DiscoveryCandidate) => {
      deduped.push(candidate);
    });
    deduped.sort((left: DiscoveryCandidate, right: DiscoveryCandidate): number => {
      if (left.verified !== right.verified) {
        return left.verified ? -1 : 1;
      }
      const leftLatency = left.latencyMs === undefined ? Number.POSITIVE_INFINITY : left.latencyMs;
      const rightLatency = right.latencyMs === undefined ? Number.POSITIVE_INFINITY : right.latencyMs;
      if (leftLatency !== rightLatency) {
        return leftLatency < rightLatency ? -1 : 1;
      }
      const leftId = left.gatewayId === undefined ? '' : left.gatewayId;
      const rightId = right.gatewayId === undefined ? '' : right.gatewayId;
      if (leftId !== rightId) {
        return leftId < rightId ? -1 : 1;
      }
      if (left.address.ip !== right.address.ip) {
        return left.address.ip < right.address.ip ? -1 : 1;
      }
      return left.address.port - right.address.port;
    });
    const verified: DiscoveryCandidate[] = [];
    for (let index = 0; index < deduped.length; index++) {
      if (deduped[index].verified) {
        verified.push(deduped[index]);
      }
    }
    return new OrderedCandidates(deduped, verified);
  }

  private static better(candidate: DiscoveryCandidate, existing: DiscoveryCandidate): boolean {
    if (candidate.verified !== existing.verified) {
      return candidate.verified;
    }
    const candidateLatency = candidate.latencyMs === undefined ?
      Number.POSITIVE_INFINITY : candidate.latencyMs;
    const existingLatency = existing.latencyMs === undefined ?
      Number.POSITIVE_INFINITY : existing.latencyMs;
    return candidateLatency < existingLatency;
  }

  private static asAppError(error: Object): AppError {
    if (error instanceof AppError) {
      return error;
    }
    return AppErrors.of('INTERNAL_ERROR', []);
  }
}
