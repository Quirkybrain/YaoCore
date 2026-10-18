/*
 * YaoCore C-06 SecretStore port.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-A §27.6.3 P1/P2.
 * Contract: DES-A §9.1.3, §22.3
 *
 * Secrets live only in the platform Asset Store. The port deliberately never
 * returns raw bytes: callers receive a temporary view through withSecret and
 * the implementation zeroizes it on success, failure, or cancellation.
 */
import type { SecureBytes } from '../common/types/SecureBytes';

export interface SecretStore {
  put(alias: string, secret: SecureBytes): Promise<void>;
  withSecret<T>(alias: string, fn: (secret: Uint8Array) => Promise<T>): Promise<T>;
  remove(alias: string): Promise<void>;
  list(prefix: string): Promise<ReadonlyArray<string>>;
}
