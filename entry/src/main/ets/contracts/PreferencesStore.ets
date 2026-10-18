/*
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-A §27.6.3 P1.
 * YaoCore C-06 PreferencesStore port.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Contract: DES-A §9.1.1, §22.1-§22.2
 *
 * Non-secret, small configuration only (locale, active family, last profile,
 * optional last SSID). Large objects belong in RDB. Secrets/tokens/passwords/
 * private keys are forbidden here (SC-09).
 *
 * DES-A nominally places ports under contracts/**. T-08's write scope is
 * service/storage/** and repository/**, so this port remains next to its
 * implementation as a recorded location exception (same pattern as T-06 R-13
 * and T-07 R-08).
 */
export interface PreferencesStore {
  getString(key: string): Promise<string | undefined>;
  putString(key: string, value: string): Promise<void>;
  delete(key: string): Promise<void>;
  flush(): Promise<void>;
}
