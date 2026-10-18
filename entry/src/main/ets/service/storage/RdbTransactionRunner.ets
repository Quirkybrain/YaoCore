/*
 * YaoCore C-06 serialized RDB transaction runner.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage; wp-022-fix-t08 (R-02)
 * Contract: DES-A §9.1.2, §9.2, §9.3 invariant 2
 *
 * Platform-neutral transaction coordinator used by RdbStoreAdapter. Keeping the
 * begin/commit/rollback state machine free of @kit.ArkData lets host tests
 * exercise the exact failure paths that the real platform can raise, including
 * `beginTransaction()` failing before the callback runs.
 *
 * Failure rules (DES-A §9.2):
 * - begin/commit/rollback/callback failures surface as STORAGE_RDB_ERROR with
 *   only the numeric platform code retained; callback AppErrors pass through.
 * - `active` is set only after begin() succeeds and is always reset by the
 *   finally block, so one failed begin can never poison later transactions.
 * - rollback is best effort; the primary failure is never masked.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import type { RdbTransaction } from '../../contracts/RdbStore';

interface PlatformErrorLike {
  code?: number;
}

/** Minimal platform transaction surface (relationalStore.RdbStore subset). */
export interface RdbTransactionDriver {
  begin(): void;
  commit(): void;
  rollBack(): void;
}

/** Maps platform/plain errors to the C-06 storage error namespace. */
export function mapRdbError(error: Error): AppError {
  if (error instanceof AppError) {
    return error;
  }
  const candidate = error as PlatformErrorLike;
  if (typeof candidate.code === 'number') {
    return AppErrors.of('STORAGE_RDB_ERROR',
      [new NameValue('platformCode', String(candidate.code))]);
  }
  return AppErrors.of('STORAGE_RDB_ERROR', []);
}

export class RdbTransactionRunner {
  private chain: Promise<void> = Promise.resolve();
  private active: boolean = false;

  /** True only between a successful begin() and commit()/rollBack(). */
  isActive(): boolean {
    return this.active;
  }

  async transaction<T>(driverFactory: () => Promise<RdbTransactionDriver>,
    tx: RdbTransaction, fn: (tx: RdbTransaction) => Promise<T>): Promise<T> {
    const run: Promise<T> = this.chain.then((): Promise<T> => {
      return this.runTransaction(driverFactory, tx, fn);
    });
    this.chain = run.then((): void => {
    }, (): void => {
    });
    return run;
  }

  private async runTransaction<T>(driverFactory: () => Promise<RdbTransactionDriver>,
    tx: RdbTransaction, fn: (tx: RdbTransaction) => Promise<T>): Promise<T> {
    if (this.active) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    let driver: RdbTransactionDriver;
    try {
      driver = await driverFactory();
    } catch (error) {
      throw mapRdbError(error as Error);
    }
    try {
      driver.begin();
    } catch (error) {
      // The platform may have opened a partial transaction before throwing.
      // Roll back best effort, then report the mapped begin failure. `active`
      // was never set, so the next transaction starts from a clean state.
      try {
        driver.rollBack();
      } catch (rollbackError) {
        // Keep the begin failure; rollback is best effort here.
      }
      throw mapRdbError(error as Error);
    }
    this.active = true;
    try {
      const result = await fn(tx);
      driver.commit();
      return result;
    } catch (error) {
      try {
        driver.rollBack();
      } catch (rollbackError) {
        // Keep the original failure; the platform rollback is best effort.
      }
      throw mapRdbError(error as Error);
    } finally {
      this.active = false;
    }
  }
}
