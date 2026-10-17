/*
 * YaoCore C-06 MigrationRegistry.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Contract: DES-A §9.1.4, §9.3 invariants 1/7
 *
 * Versions must be a contiguous sequence starting at 1. Registration may
 * happen out of order (other components register before StorageService's
 * constructor registers v1), so contiguity is verified at migrate() time.
 * Every version runs in one RDB transaction; the version bump participates in
 * the same transaction, so a failure leaves both data and user_version at the
 * previous revision. No downgrade and no data deletion on failure.
 */
import { AppErrors } from '../../common/types/AppError';
import type { MigrationRegistryPort } from './MigrationPort';
import type { RdbStore, RdbTransaction } from './RdbStore';

export class MigrationRegistry implements MigrationRegistryPort {
  private readonly statementsByVersion: Map<number, ReadonlyArray<string>> =
    new Map<number, ReadonlyArray<string>>();

  register(version: number, statements: ReadonlyArray<string>): void {
    if (!Number.isInteger(version) || version < 1) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (statements.length === 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (this.statementsByVersion.has(version)) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    const copy: string[] = [];
    for (let index = 0; index < statements.length; index++) {
      if (statements[index].length === 0) {
        throw AppErrors.of('CONFIGURATION_ERROR', []);
      }
      copy.push(statements[index]);
    }
    this.statementsByVersion.set(version, copy);
  }

  async migrate(rdb: RdbStore): Promise<number> {
    const versions = this.sortedVersions();
    for (let index = 0; index < versions.length; index++) {
      if (versions[index] !== index + 1) {
        throw AppErrors.of('STORAGE_MIGRATION_FAILED', []);
      }
    }
    const targetVersion = versions.length;
    let currentVersion = 0;
    try {
      currentVersion = await rdb.getVersion();
    } catch (error) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    if (!Number.isInteger(currentVersion) || currentVersion < 0 ||
      currentVersion > targetVersion) {
      // A newer schema than this build understands must never be downgraded.
      throw AppErrors.of('STORAGE_MIGRATION_FAILED', []);
    }

    for (let version = currentVersion + 1; version <= targetVersion; version++) {
      const statements = this.statementsByVersion.get(version);
      if (statements === undefined) {
        throw AppErrors.of('STORAGE_MIGRATION_FAILED', []);
      }
      try {
        await rdb.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
          await MigrationRegistry.applyStatements(tx, statements);
          await rdb.setVersion(version);
        });
      } catch (error) {
        throw AppErrors.of('STORAGE_MIGRATION_FAILED', []);
      }
    }
    return targetVersion;
  }

  private static async applyStatements(tx: RdbTransaction,
    statements: ReadonlyArray<string>): Promise<void> {
    for (let index = 0; index < statements.length; index++) {
      await tx.execute(statements[index]);
    }
  }

  private sortedVersions(): number[] {
    const versions: number[] = [];
    this.statementsByVersion.forEach((statements: ReadonlyArray<string>,
      version: number): void => {
      versions.push(version);
    });
    versions.sort((left: number, right: number): number => left - right);
    return versions;
  }
}
