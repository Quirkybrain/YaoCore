/*
 * YaoCore C-15 cloud ports.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §8.1.3, §8.5; DES-A §3.7
 *
 * Port-only declarations. No platform import and no token getter: callers can
 * only touch the cloud token inside `withToken` so a raw credential never
 * becomes long-lived application state.
 *
 * DES-B nominally places these ports under `contracts/CloudPorts.ets`. T-14's
 * delegated write scope is `entry/src/main/ets/service/**`, so the file stays
 * next to the cloud implementation (recorded location exception, consistent
 * with T-06/T-07/T-08/T-11).
 */
import type { CloudConfig } from '../../model/FamilyModels';
import type { CancellationToken } from '../../common/types/Ports';

export interface CloudConfigStore {
  load(): Promise<CloudConfig | undefined>;
  save(config: CloudConfig): Promise<void>;
  clear(): Promise<void>;
}

export interface CloudCredentialPort {
  hasToken(): Promise<boolean>;
  /** Provides the token only for the duration of the HTTP call; no retention. */
  withToken<T>(fn: (token: string) => Promise<T>): Promise<T>;
  putToken(token: string): Promise<void>;
  removeToken(): Promise<void>;
  updatedAt(): Promise<string | undefined>;
}

/**
 * Cancellable delay seam. CloudService must be able to stop the active poll
 * timer without waiting for the interval to elapse (DES-B §8.1.7).
 */
export interface TimerPort {
  sleep(ms: number, cancellation?: CancellationToken): Promise<void>;
  cancel(): void;
}

/**
 * v1 active cloud scope assertion (DES-B §8.1.4, §8.3.1; F-06 ruling).
 *
 * C-28 assembles the single C-15 instance for the current active gateway and
 * supplies this seam. `CloudCommandClient` uses it to reject a command whose
 * `gatewayId` is outside the active cloud scope or has no bound gateway
 * credential BEFORE allocating a sequence, reading a secret, signing or
 * sending HTTP. `CloudConfig` has no `gatewayId`, so C-15 cannot rebuild this
 * binding from persistence alone.
 */
export interface CloudActiveScopePort {
  /** Current active gateway, or undefined when no active scope is selected. */
  activeGatewayId(): Promise<string | undefined>;
  /** Whether the gateway has a persisted route/command-credential binding. */
  isGatewayBound(gatewayId: string): Promise<boolean>;
}
