/*
 * YaoCore C-06 RdbStore port.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Contract: DES-A §9.1.2, §22.1-§22.2
 *
 * Minimal RelationalStore seam used by C-06/C-07 and later repositories.
 * `Uint8Array` is reserved for BLOB values; DES-A stores no secret BLOB.
 * Production errors are mapped to STORAGE_RDB_ERROR by the adapter; callers
 * receive AppError only.
 */
export type RdbValue = string | number | boolean | Uint8Array | null;

export type RdbRow = Map<string, RdbValue>;

export interface RdbTransaction {
  execute(sql: string, args?: ReadonlyArray<RdbValue>): Promise<void>;
  query(sql: string, args?: ReadonlyArray<RdbValue>): Promise<ReadonlyArray<RdbRow>>;
}

export interface RdbStore extends RdbTransaction {
  transaction<T>(fn: (tx: RdbTransaction) => Promise<T>): Promise<T>;
  getVersion(): Promise<number>;
  setVersion(version: number): Promise<void>;
}
