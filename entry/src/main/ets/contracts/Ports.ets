/*
 * YaoCore C-01 base ports.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-A §27.6.3 P1.
 * Contract: DES-A §3.7, §4.1.11
 *
 * Port-only declarations. No implementation and no platform import.
 * ClockPort/IdPort remain in common/types/Ports.ets (PORT-LOC-01) because the
 * frozen DateTimeUtil/UuidUtil signatures consume them from common/** (D-01).
 */
import type { NameValue } from '../common/types/NameValue';

export interface RandomPort {
  nextBytes(length: number): Promise<Uint8Array>;
}

export interface LoggerPort {
  debug(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void;
  info(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void;
  warn(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void;
  error(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void;
}

export interface MetricsPort {
  record(name: string, valueMs: number, tags?: ReadonlyArray<NameValue>): void;
}

/**
 * HMAC-SHA256 signing seam for T-07 (C-05).
 * Implementations return 64 lowercase hex characters. T-06 deliberately does
 * not implement HMAC; it only validates and serializes already-signed DTOs.
 */
export interface HmacSignerPort {
  signHmacSha256(secret: Uint8Array, canonicalUtf8: string): Promise<string>;
}
