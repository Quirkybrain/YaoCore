/*
 * YaoCore C-06 migration ports.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Contract: DES-A §9.1.4
 *
 * C-08 and later repositories depend on MigrationSink only, avoiding a
 * repository -> service reverse dependency. StorageService owns the registry.
 */
import type { RdbStore } from './RdbStore';

export interface MigrationSink {
  register(version: number, statements: ReadonlyArray<string>): void;
}

export interface MigrationRegistryPort extends MigrationSink {
  migrate(rdb: RdbStore): Promise<number>;
}
