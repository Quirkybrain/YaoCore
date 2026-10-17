/*
 * YaoCore C-01 base ports.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §3.7, §4.1.11
 *
 * Port-only declarations. No implementation and no platform import. The
 * contracts/** location is reserved for the later port-expansion task; T-06's
 * delegated write scope places these pure interfaces under common/types/.
 */
import type { NameValue } from './NameValue';

export interface ClockPort {
  nowMs(): number;
}

export interface RandomPort {
  nextBytes(length: number): Promise<Uint8Array>;
}

export interface IdPort {
  newId(): string;
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

export interface CancellationToken {
  readonly cancelled: boolean;
  onCancel(listener: () => void): void;
  throwIfCancelled(): void;
}

/**
 * HMAC-SHA256 signing seam for T-07 (C-05).
 * Implementations return 64 lowercase hex characters. T-06 deliberately does
 * not implement HMAC; it only validates and serializes already-signed DTOs.
 */
export interface HmacSignerPort {
  signHmacSha256(secret: Uint8Array, canonicalUtf8: string): Promise<string>;
}
