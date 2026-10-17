/*
 * YaoCore C-18 GatewayDiscoveryService host tests.
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §15.1-§15.6, §21; ADR-004 §5; PR-06/PR-13; PB-01; D-019.
 *
 * PUBLIC TEST DATA ONLY. Locator fakes never create bindings; only a probe
 * whose identity equals the bound route may verify.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { AppError, AppErrors } from '../../main/ets/common/types/AppError.ets';
import { GatewayAddress, GatewayRoute, GatewayRouteInit } from '../../main/ets/model/GatewayRoute.ets';
import { TransportProfile } from '../../main/ets/model/DeviceTypes.ets';
import {
  ProbeResult,
} from '../../main/ets/service/gateway/GatewayTransportPorts.ets';
import { GatewayDiscoveryService } from '../../main/ets/service/gateway/GatewayDiscoveryService.ets';
import {
  DiscoveryBeacon,
  DiscoveryOptions,
  DiscoverySource,
  DiscoveryTransportKind,
} from '../../main/ets/service/gateway/DiscoveryModels.ets';
import { ManualAddressPolicy } from '../../main/ets/service/gateway/ManualAddressPolicy.ets';
import { ProbeBackoff } from '../../main/ets/service/gateway/ProbeBackoff.ets';
import {
  FakeTransportClock,
  InMemoryAddressPort,
  InMemoryRoutePort,
  RecordingLogger,
} from './TransportFakes.ets';

const FIXED_MS = Date.UTC(2026, 9, 17, 8, 0, 0);
const FIXED_TS = '20261017T080000Z';
const FAMILY = '123e4567-e89b-12d3-a456-426614174000';
const GW_A = 'gateway_01';
const GW_B = 'gateway_02';
const PIN_A = 'a'.repeat(64);

const alias = (gatewayId) => 'yaocore.gateway.hmac.' + gatewayId;

const route = (gatewayId, ip, profile = TransportProfile.P_HMAC, pins = []) => {
  const init = new GatewayRouteInit();
  init.gatewayId = gatewayId;
  init.familyId = FAMILY;
  init.gatewayName = 'Gateway ' + gatewayId;
  init.localIp = ip;
  init.port = 9200;
  init.profile = profile;
  init.tlsEnabled = profile === TransportProfile.P_TLS_PIN;
  init.pins = pins;
  init.pinAlg = profile === TransportProfile.P_TLS_PIN ? 'sha256-spki-der' : '';
  init.credentialAlias = alias(gatewayId);
  init.lastKnownIp = ip;
  init.createdAt = FIXED_TS;
  init.updatedAt = FIXED_TS;
  return GatewayRoute.create(init);
};

class FakeGatewayClient {
  constructor() {
    this.calls = [];
    this.handler = undefined;
  }

  setHandler(handler) {
    this.handler = handler;
  }

  async probe(target) {
    this.calls.push(target);
    if (this.handler === undefined) {
      throw AppErrors.of('GATEWAY_UNREACHABLE', []);
    }
    return this.handler(target, this.calls.length);
  }

  async discover() {
    throw AppErrors.of('INTERNAL_ERROR', []);
  }

  async control() {
    throw AppErrors.of('INTERNAL_ERROR', []);
  }
}

class FakeDiscoveryTransport {
  constructor(kind, beacons) {
    this.kind = kind;
    this.beacons = beacons;
    this.scans = 0;
    this.failure = undefined;
  }

  async scan(timeoutMs, cancellation) {
    this.scans += 1;
    if (this.failure !== undefined) {
      throw this.failure;
    }
    return this.beacons;
  }
}

class FakeCancellation {
  constructor() {
    this.cancelled = false;
    this.listeners = [];
  }

  onCancel(listener) {
    this.listeners.push(listener);
  }

  throwIfCancelled() {
    if (this.cancelled) {
      throw AppErrors.of('PROVISIONING_CANCELLED', []);
    }
  }

  cancel() {
    this.cancelled = true;
    for (const listener of this.listeners) {
      listener();
    }
  }
}

const setup = (routes = [], beacons = [], probeTimeoutMs = 50) => {
  const clock = new FakeTransportClock(FIXED_MS);
  const routePort = new InMemoryRoutePort();
  for (const item of routes) {
    routePort.add(item);
  }
  const client = new FakeGatewayClient();
  const mdns = new FakeDiscoveryTransport(DiscoveryTransportKind.MDNS, beacons);
  const addresses = new InMemoryAddressPort();
  const logger = new RecordingLogger();
  const service = new GatewayDiscoveryService(client, routePort, mdns, undefined, addresses,
    clock, logger, probeTimeoutMs);
  return { clock, routePort, client, mdns, addresses, logger, service };
};

const probeOk = (target, latencyMs = 5) => new ProbeResult(true, target.gatewayId,
  'Gateway ' + target.gatewayId, target.profile,
  target.profile === TransportProfile.P_TLS_PIN ? target.pins[0] : undefined, latencyMs);

test('C18_lastKnown_probeVerifiesBoundRoute', async () => {
  const ctx = setup([route(GW_A, '192.168.1.20')]);
  ctx.client.setHandler(async (target) => probeOk(target, 7));
  const report = await ctx.service.discoverBound(new DiscoveryOptions(FAMILY, false, false, 200));
  assert.equal(report.verified.length, 1);
  assert.equal(report.candidates.length, 1);
  assert.equal(report.candidates[0].source, DiscoverySource.LAST_KNOWN);
  assert.equal(report.candidates[0].gatewayId, GW_A);
  assert.equal(report.candidates[0].latencyMs, 7);
  assert.equal(report.warnings.length, 0);
});

test('C18_lastKnown_failureDoesNotBlockOtherRoutes', async () => {
  const ctx = setup([route(GW_A, '192.168.1.20'), route(GW_B, '192.168.1.21')]);
  ctx.client.setHandler(async (target) => {
    if (target.gatewayId === GW_A) {
      throw AppErrors.of('GATEWAY_UNREACHABLE', []);
    }
    return probeOk(target, 9);
  });
  const report = await ctx.service.discoverBound(new DiscoveryOptions(FAMILY, false, false, 200));
  assert.equal(report.verified.length, 1);
  assert.equal(report.verified[0].gatewayId, GW_B);
  assert.equal(report.candidates.length, 2);
  assert.equal(report.warnings.length, 1);
  assert.equal(report.warnings[0].code, 'GATEWAY_UNREACHABLE');
});

test('C18_lastKnown_identityMismatchNeverVerifies', async () => {
  const ctx = setup([route(GW_A, '192.168.1.20')]);
  ctx.client.setHandler(async (target) => new ProbeResult(true, 'other_gateway',
    'Impostor', target.profile, undefined, 3));
  const report = await ctx.service.discoverBound(new DiscoveryOptions(FAMILY, false, false, 200));
  assert.equal(report.verified.length, 0);
  assert.equal(report.candidates[0].verified, false);
  assert.equal(report.candidates[0].errorCode, 'GATEWAY_ID_MISMATCH');
  assert.equal(report.warnings[0].code, 'GATEWAY_ID_MISMATCH');
});

test('C18_lastKnown_profileMismatchIsPBlockedEvidence', async () => {
  const ctx = setup([route(GW_A, '192.168.1.20', TransportProfile.P_TLS_PIN, [PIN_A])]);
  ctx.client.setHandler(async (target) => new ProbeResult(true, target.gatewayId,
    'Gateway', TransportProfile.P_HMAC, undefined, 3));
  const report = await ctx.service.discoverBound(new DiscoveryOptions(FAMILY, false, false, 200));
  assert.equal(report.verified.length, 0);
  assert.equal(report.candidates[0].errorCode, 'TLS_PROFILE_INCONSISTENT');
});

test('C18_candidates_areDedupedAndLatencyOrdered', async () => {
  const ctx = setup([route(GW_A, '192.168.1.20')]);
  ctx.client.setHandler(async (target) => probeOk(target, 30));
  const mdnsBeacon = new DiscoveryBeacon(new GatewayAddress('192.168.1.20', 9200), GW_A,
    'Gateway ' + GW_A, FIXED_MS);
  ctx.mdns.beacons = [mdnsBeacon];
  const report = await ctx.service.discoverBound(new DiscoveryOptions(FAMILY, true, false, 200));
  assert.equal(report.candidates.length, 1, 'same gateway/ip/port is deduped');
  assert.equal(report.candidates[0].verified, true);
});

test('C18_mdns_withoutHintIsLocatorOnly', async () => {
  const ctx = setup([route(GW_A, '192.168.1.20')]);
  const beacon = new DiscoveryBeacon(new GatewayAddress('192.168.1.50', 9200), undefined,
    'Some Other Device', FIXED_MS);
  ctx.mdns.beacons = [beacon];
  ctx.client.setHandler(async (target) => probeOk(target, 1));
  const report = await ctx.service.discoverBound(new DiscoveryOptions(FAMILY, true, false, 200));
  const locator = report.candidates.find((item) => item.address.ip === '192.168.1.50');
  assert.ok(locator);
  assert.equal(locator.verified, false);
  assert.equal(locator.gatewayId, undefined);
  assert.equal(ctx.routePort.routes.length, 1, 'no binding created from a beacon');
});

test('C18_mdns_hintMatchingBoundRouteUsesSignedProbe', async () => {
  const ctx = setup([route(GW_A, '192.168.1.20')]);
  const beacon = new DiscoveryBeacon(new GatewayAddress('192.168.1.55', 9200), GW_A,
    'Gateway ' + GW_A, FIXED_MS);
  ctx.mdns.beacons = [beacon];
  ctx.client.setHandler(async (target) => {
    assert.equal(target.address.ip, '192.168.1.55');
    return probeOk(target, 4);
  });
  const report = await ctx.service.discoverBound(new DiscoveryOptions(FAMILY, true, false, 200));
  const verified = report.verified.find((item) => item.source === DiscoverySource.MDNS);
  assert.ok(verified);
  assert.equal(verified.gatewayId, GW_A);
});

test('C18_mdns_scanFailureIsWarningOnly', async () => {
  const ctx = setup([]);
  ctx.mdns.failure = AppErrors.of('DISCOVERY_TRANSPORT_UNAVAILABLE', []);
  const report = await ctx.service.discoverBound(new DiscoveryOptions(FAMILY, true, false, 200));
  assert.equal(report.candidates.length, 0);
  assert.ok(report.warnings.some((item) => item.code === 'DISCOVERY_TRANSPORT_UNAVAILABLE'));
  assert.ok(report.warnings.some((item) => item.code === 'DISCOVERY_NO_CANDIDATES'));
});

test('C18_udp_unresolvedPB01_isWarningWhenRequested', async () => {
  const ctx = setup([]);
  const report = await ctx.service.discoverBound(new DiscoveryOptions(FAMILY, false, true, 200));
  assert.ok(report.warnings.some((item) => item.code === 'DISCOVERY_TRANSPORT_UNAVAILABLE'));
});

test('C18_udp_injectedBeaconsRemainUnverifiedLocators', async () => {
  const clock = new FakeTransportClock(FIXED_MS);
  const routes = new InMemoryRoutePort();
  routes.add(route(GW_A, '192.168.1.20'));
  const client = new FakeGatewayClient();
  const udp = new FakeDiscoveryTransport(DiscoveryTransportKind.UDP, [
    new DiscoveryBeacon(new GatewayAddress('192.168.1.77', 9200), GW_A, 'Gateway ' + GW_A, FIXED_MS),
  ]);
  const service = new GatewayDiscoveryService(client, routes, undefined, udp,
    new InMemoryAddressPort(), clock, new RecordingLogger(), 50);
  const report = await service.discoverBound(new DiscoveryOptions(FAMILY, false, true, 200));
  const locator = report.candidates.find((item) => item.address.ip === '192.168.1.77');
  assert.ok(locator);
  assert.equal(locator.verified, false);
  assert.equal(report.verified.length, 0);
});

test('C18_manual_requiresBoundGatewayAndUpdatesAddressOnSuccess', async () => {
  const ctx = setup([route(GW_A, '192.168.1.20')]);
  ctx.client.setHandler(async (target) => probeOk(target, 2));
  const address = new GatewayAddress('192.168.1.30', 9200);
  const candidate = await ctx.service.probeManual(GW_A, address);
  assert.equal(candidate.verified, true);
  assert.equal(candidate.source, DiscoverySource.MANUAL);
  assert.equal(ctx.addresses.updates.length, 1);
  assert.equal(ctx.addresses.updates[0].ip, '192.168.1.30');
});

test('C18_manual_rejectsUnboundAndInvalidAddresses', async () => {
  const ctx = setup([]);
  await assert.rejects(() => ctx.service.probeManual(GW_A,
    new GatewayAddress('192.168.1.30', 9200)),
  (error) => error instanceof AppError && error.code === 'MANUAL_ADDRESS_NOT_BOUND');
  assert.throws(() => ManualAddressPolicy.validate('127.0.0.1', 9200),
    (error) => error instanceof AppError && error.code === 'MANUAL_ADDRESS_REJECTED');
  assert.throws(() => ManualAddressPolicy.validate('169.254.1.1', 9200),
    (error) => error instanceof AppError && error.code === 'MANUAL_ADDRESS_REJECTED');
});

test('C18_manual_identityMismatchDoesNotUpdateAddress', async () => {
  const ctx = setup([route(GW_A, '192.168.1.20')]);
  ctx.client.setHandler(async (target) => new ProbeResult(true, 'other_gateway', 'Impostor',
    target.profile, undefined, 2));
  await assert.rejects(() => ctx.service.probeManual(GW_A,
    new GatewayAddress('192.168.1.30', 9200)),
  (error) => error instanceof AppError && error.code === 'GATEWAY_ID_MISMATCH');
  assert.equal(ctx.addresses.updates.length, 0);
});

test('C18_manual_rateLimitAndFailureBudget', async () => {
  const ctx = setup([route(GW_A, '192.168.1.20')]);
  ctx.client.setHandler(async () => {
    throw AppErrors.of('GATEWAY_UNREACHABLE', []);
  });
  await assert.rejects(() => ctx.service.probeManual(GW_A,
    new GatewayAddress('192.168.1.30', 9200)), (error) => error.code === 'GATEWAY_UNREACHABLE');
  await assert.rejects(() => ctx.service.probeManual(GW_A,
    new GatewayAddress('192.168.1.30', 9200)), (error) => error.code === 'MANUAL_ADDRESS_REJECTED');
  for (let index = 0; index < 4; index++) {
    ctx.clock.advance(2000);
    await assert.rejects(() => ctx.service.probeManual(GW_A,
      new GatewayAddress('192.168.1.30', 9200)),
    (error) => error.code === 'GATEWAY_UNREACHABLE');
  }
  ctx.clock.advance(2000);
  await assert.rejects(() => ctx.service.probeManual(GW_A,
    new GatewayAddress('192.168.1.30', 9200)),
  (error) => error.code === 'MANUAL_ADDRESS_REJECTED');
});

test('C18_probeLastKnown_returnsUndefinedWithoutAddress', async () => {
  const init = new GatewayRouteInit();
  init.gatewayId = GW_A;
  init.familyId = FAMILY;
  init.gatewayName = 'Gateway';
  init.port = 9200;
  init.profile = TransportProfile.P_HMAC;
  init.credentialAlias = alias(GW_A);
  init.createdAt = FIXED_TS;
  init.updatedAt = FIXED_TS;
  const ctx = setup([GatewayRoute.create(init)]);
  assert.equal(await ctx.service.probeLastKnown(GW_A), undefined);
  assert.equal(await ctx.service.probeLastKnown('missing_gateway'), undefined);
});

test('C18_probeLastKnown_transportFailureReturnsUnverifiedCandidate', async () => {
  const ctx = setup([route(GW_A, '192.168.1.20')]);
  ctx.client.setHandler(async () => {
    throw AppErrors.of('GATEWAY_TIMEOUT', []);
  });
  const candidate = await ctx.service.probeLastKnown(GW_A);
  assert.ok(candidate);
  assert.equal(candidate.verified, false);
  assert.equal(candidate.errorCode, 'GATEWAY_TIMEOUT');
});

test('C18_probeTimeoutIsClassifiedAndDoesNotHang', async () => {
  const ctx = setup([route(GW_A, '192.168.1.20')], [], 20);
  ctx.client.setHandler(() => new Promise(() => {}));
  const report = await ctx.service.discoverBound(new DiscoveryOptions(FAMILY, false, false, 100));
  assert.equal(report.verified.length, 0);
  assert.equal(report.candidates[0].errorCode, 'GATEWAY_TIMEOUT');
});

test('C18_cancellationStopsDiscovery', async () => {
  const ctx = setup([route(GW_A, '192.168.1.20')]);
  const cancellation = new FakeCancellation();
  cancellation.cancel();
  await assert.rejects(() => ctx.service.discoverBound(
    new DiscoveryOptions(FAMILY, false, false, 100, undefined, cancellation)),
  (error) => error instanceof AppError && error.code === 'PROVISIONING_CANCELLED');
});

test('C18_probeBackoffSequenceMatchesBindingProbeBudget', () => {
  const backoff = ProbeBackoff.forBindingProbe();
  assert.deepEqual([1, 2, 3, 4, 5].map((attempt) => backoff.nextDelayMs(attempt)),
    [500, 1000, 2000, 4000, 8000]);
  assert.equal(backoff.totalBudgetMs(), 15500);
  assert.equal(ProbeBackoff.bindingProbeTotalBudgetMs(), 30000);
});
