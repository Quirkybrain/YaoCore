/*
 * YaoCore C-01 clock/id ports.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Migrated: T-23 / wp-090-ports (2026-10-18) — partial migration.
 * Contract: DES-A §3.7, §4.1.5, §4.1.11
 *
 * LOCATION EXCEPTION (PORT-LOC-01, retained): ClockPort/IdPort stay in
 * common/types because the frozen C-01 signatures
 * `DateTimeUtil.nowUtcCompact(clock: ClockPort)` and
 * `UuidUtil.newUuid(ids: IdPort)` live in common/** and D-01 forbids
 * common/** -> contracts/**. Moving these two ports without an approved
 * D-01/signature change would require a duplicate port definition, which
 * DES-A §27.6.3 forbids. All other C-01 ports now live in contracts/Ports.ets.
 *
 * Port-only declarations. No implementation and no platform import.
 */

export interface ClockPort {
  nowMs(): number;
}

export interface IdPort {
  newId(): string;
}
