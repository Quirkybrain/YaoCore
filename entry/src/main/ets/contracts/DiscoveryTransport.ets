/*
 * YaoCore C-18 discovery transport seam.
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Migrated: T-23 / wp-090-ports (2026-10-18) — split out of
 * service/gateway/DiscoveryModels.ets (DES-A §27.6.3 P2); ManualDiscoveryPort
 * converges with C-18 as required by §27.6.2 PORT-LOC-17.
 * Contract: DES-A §15.1, §15.4, §21.2; DES-B §2.1/§23.1
 *
 * PB-01 seam. Implementations return locators only. The raw UDP packet format
 * and the mDNS service type/TXT schema are UNRESOLVED; production code must not
 * install a raw UDP adapter before the architecture decision closes PB-01.
 */
import type { GatewayAddress } from '../model/GatewayRoute';
import type {
  DiscoveryBeacon,
  DiscoveryCandidate,
  DiscoveryTransportKind
} from '../model/DiscoveryModels';
import type { CancellationToken } from '../common/types/CancellationToken';

export interface DiscoveryTransport {
  readonly kind: DiscoveryTransportKind;
  scan(timeoutMs: number, cancellation?: CancellationToken): Promise<ReadonlyArray<DiscoveryBeacon>>;
}

/** Discovery subset consumed by Home/Settings; C-18 satisfies it. */
export interface ManualDiscoveryPort {
  probeLastKnown(gatewayId: string): Promise<DiscoveryCandidate | undefined>;
  probeManual(gatewayId: string, address: GatewayAddress): Promise<DiscoveryCandidate>;
  resetManualFailures(gatewayId: string): void;
}
