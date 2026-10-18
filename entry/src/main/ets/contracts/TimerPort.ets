/*
 * YaoCore C-15 cloud cancellable delay seam.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Migrated: T-23 / wp-090-ports (2026-10-18) — split out of CloudPorts
 * per DES-A §27.6.3 P1.
 * Contract: DES-B §8.1.7.
 *
 * This is the C-15 cloud poll sleep/cancel seam only. The VM callback timer is
 * VmTimerPort (DES-B §23.1 EXT-DES-B-33), not this port. T-23 retired the
 * never-implemented DES-B EXT-DES-B-01 callback scheduler shape; do not
 * reintroduce it here. C-11 SceneTimerPort remains a separate scene delay seam.
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
