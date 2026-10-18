/*
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-A §27.6.3 P1.
 * YaoCore C-06 SecretDraftPort.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Contract: DES-A §9.1.5
 *
 * One-shot, memory-only command-secret drafts used between BLE provisioning
 * and commitBinding. Drafts are never written to Preferences/RDB/Asset Store.
 */
import type { SecureBytes } from '../common/types/SecureBytes';

export interface SecretDraftPort {
  put(secret: SecureBytes, ttlMs?: number): string;
  take(draftId: string): SecureBytes;
  destroy(draftId: string): void;
  clearAll(): void;
  size(): number;
}
