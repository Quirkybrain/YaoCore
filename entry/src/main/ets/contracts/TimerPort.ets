/*
 * YaoCore C-15 cancellable delay seam.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Migrated: T-23 / wp-090-ports (2026-10-18) — split out of CloudPorts
 * per DES-A §27.6.3 P1 / DES-B §23.1 (EXT-DES-B-01).
 * Contract: DES-B §8.1.7
 */
import type { CancellationToken } from '../common/types/CancellationToken';

/**
 * Cancellable delay seam. CloudService must be able to stop the active poll
 * timer without waiting for the interval to elapse (DES-B §8.1.7).
 */
export interface TimerPort {
  sleep(ms: number, cancellation?: CancellationToken): Promise<void>;
  cancel(): void;
}
