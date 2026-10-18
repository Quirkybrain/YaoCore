/*
 * YaoCore C-01 cancellation token.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Migrated: T-23 / wp-090-ports (2026-10-18) — split out of common/types/Ports.ets
 * per DES-A §2.1 target layout (common/types/CancellationToken.ets).
 * Contract: DES-A §3.7, §4.1.11
 */
export interface CancellationToken {
  readonly cancelled: boolean;
  onCancel(listener: () => void): void;
  throwIfCancelled(): void;
}
