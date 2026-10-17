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
