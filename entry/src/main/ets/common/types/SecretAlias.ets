/*
 * YaoCore C-06 secret alias grammar.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Migrated: T-23 / wp-090-ports (2026-10-18) — moved out of the port file so
 * repository/** no longer imports service/storage (DES-A §27.6.2 PORT-LOC-05).
 * Contract: DES-A §9.1.3
 */
import { AppErrors } from './AppError';

/**
 * DES-A §9.1.3 alias grammar. Rejecting invalid aliases before touching the
 * platform prevents path/alias injection and keeps migration cleanup bounded.
 */
export class SecretAlias {
  static readonly PATTERN: RegExp = /^[a-zA-Z0-9._-]{1,127}$/;

  static require(alias: string): string {
    if (!SecretAlias.PATTERN.test(alias)) {
      throw AppErrors.of('SECRET_ALIAS_INVALID', []);
    }
    return alias;
  }
}
