/*
 * YaoCore C-17/C-18 transport ports and client contracts.
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-A §27.6.3 P1/P2.
 * Contract: DES-A §14.1.1/§14.1.3, §15.1, §15.4, §19.3, §3.7
 *
 * Port-only declarations: no @ohos import, no platform behaviour. Production
 * adapters live under service/gateway/adapters/** and are assembled only by the
 * composition root (C-28) or ohosTest. DTOs live in
 * model/GatewayTransportModels.ets.
 */
import type { DeviceControlCommand, ControlOutcome } from '../model/ControlModels';
import type { DiscoverySnapshot } from '../model/DiscoveryModels';
import type {
  GatewayTarget,
  HttpRequest,
  HttpResponse,
  ProbeResult,
  TlsPolicy,
  TlsVerification
} from '../model/GatewayTransportModels';
import type { GatewayCredentialPort } from './GatewayPorts';

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

export interface IGatewayClient {
  discover(target: GatewayTarget): Promise<DiscoverySnapshot>;
  control(target: GatewayTarget, command: DeviceControlCommand): Promise<ControlOutcome>;
  probe(target: GatewayTarget, credentials?: GatewayCredentialPort): Promise<ProbeResult>;
}
