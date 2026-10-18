/*
 * YaoCore C-07 GatewayRepository ports.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-A §27.6.3 P1/P2.
 * Contract: DES-A §10.1, §10.5, §3.7
 *
 * Port-only declarations consumed by C-17/C-18/C-23. C-07 owns the
 * implementations; no platform import appears here. `InvitedGateway` lives in
 * model/InvitedGateway.ets (pure value object).
 */
import type { GatewayAddress, GatewayRoute, TlsMaterial } from '../model/GatewayRoute';
import type { InvitedGateway } from '../model/InvitedGateway';

export interface GatewayRoutePort {
  listRoutes(): Promise<ReadonlyArray<GatewayRoute>>;
  listRoutesByFamily(familyId: string): Promise<ReadonlyArray<GatewayRoute>>;
  getRoute(gatewayId: string): Promise<GatewayRoute | undefined>;
  isBound(gatewayId: string): Promise<boolean>;
}

export interface GatewayCredentialPort {
  withCommandSecret<T>(gatewayId: string, fn: (secret: Uint8Array) => Promise<T>): Promise<T>;
  tlsMaterial(gatewayId: string): Promise<TlsMaterial | undefined>;
}

export interface GatewayAddressPort {
  updateLastKnownAddress(gatewayId: string, address: GatewayAddress): Promise<void>;
}

export interface GatewaySequencePort {
  nextSequence(gatewayId: string): Promise<number>;
  peekSequence(gatewayId: string): Promise<number>;
  resetSequenceIfIdle(gatewayId: string): Promise<number>;
}

export interface SecretVerifier {
  verify(gatewayId: string, secret: Uint8Array): Promise<boolean>;
}

export interface InvitationApplicationPort {
  applyInvitedGateway(entry: InvitedGateway): Promise<void>;
}
