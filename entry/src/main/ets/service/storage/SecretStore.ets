/*
 * YaoCore C-06 SecretStore port.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Contract: DES-A §9.1.3, §22.3
 *
 * Secrets live only in the platform Asset Store. The port deliberately never
 * returns raw bytes: callers receive a temporary view through withSecret and
 * the implementation zeroizes it on success, failure, or cancellation.
 */
import { AppErrors } from '../../common/types/AppError';
import type { SecureBytes } from '../../common/types/SecureBytes';

export interface SecretStore {
  put(alias: string, secret: SecureBytes): Promise<void>;
  withSecret<T>(alias: string, fn: (secret: Uint8Array) => Promise<T>): Promise<T>;
  remove(alias: string): Promise<void>;
  list(prefix: string): Promise<ReadonlyArray<string>>;
}

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
