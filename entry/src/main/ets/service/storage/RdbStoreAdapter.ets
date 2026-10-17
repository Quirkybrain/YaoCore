/*
 * YaoCore C-06 RdbStoreAdapter.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Contract: DES-A §9.1.2, §9.4, §23.3
 *
 * The ONLY storage file importing @ohos.data.relationalStore (through
 * ArkData). Transactions are serialized per store; the same connection object
 * is handed to the callback so platform PRAGMA user_version updates join the
 * transaction. The begin/commit/rollback state machine lives in the
 * platform-neutral RdbTransactionRunner, so host tests can prove that a failed
 * beginTransaction() resets state and maps to STORAGE_RDB_ERROR (wp-022 R-02).
 * Failures map to STORAGE_RDB_ERROR with only a numeric platform code retained.
 */
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppErrors } from '../../common/types/AppError';
import { StorageConstants } from '../../common/constants/StorageConstants';
import type { RdbRow, RdbStore, RdbTransaction, RdbValue } from './RdbStore';
import type { RdbTransactionDriver } from './RdbTransactionRunner';
import { RdbTransactionRunner, mapRdbError } from './RdbTransactionRunner';

class PlatformTransactionDriver implements RdbTransactionDriver {
  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  begin(): void {
    this.store.beginTransaction();
  }

  commit(): void {
    this.store.commit();
  }

  rollBack(): void {
    this.store.rollBack();
  }
}

export class RdbStoreAdapter implements RdbStore {
  private readonly context: common.Context;
  private readonly name: string;
  private store: relationalStore.RdbStore | undefined = undefined;
  private opening: Promise<relationalStore.RdbStore> | undefined = undefined;
  private readonly transactions: RdbTransactionRunner = new RdbTransactionRunner();

  constructor(context: common.Context, name: string = StorageConstants.RDB_NAME) {
    this.context = context;
    this.name = name;
  }

  async execute(sql: string, args?: ReadonlyArray<RdbValue>): Promise<void> {
    try {
      const store = await this.open();
      await store.executeSql(sql, RdbStoreAdapter.bindArgs(args));
    } catch (error) {
      throw mapRdbError(error as Error);
    }
  }

  async query(sql: string, args?: ReadonlyArray<RdbValue>):
    Promise<ReadonlyArray<RdbRow>> {
    try {
      const store = await this.open();
      const resultSet = await store.querySql(sql, RdbStoreAdapter.bindArgs(args));
      const rows: RdbRow[] = [];
      try {
        while (resultSet.goToNextRow()) {
          rows.push(RdbStoreAdapter.readRow(resultSet));
        }
      } finally {
        resultSet.close();
      }
      return rows;
    } catch (error) {
      throw mapRdbError(error as Error);
    }
  }

  async transaction<T>(fn: (tx: RdbTransaction) => Promise<T>): Promise<T> {
    return this.transactions.transaction(
      (): Promise<RdbTransactionDriver> => this.openDriver(), this, fn);
  }

  async getVersion(): Promise<number> {
    try {
      const store = await this.open();
      return store.version;
    } catch (error) {
      throw mapRdbError(error as Error);
    }
  }

  async setVersion(version: number): Promise<void> {
    if (!Number.isInteger(version) || version < 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    try {
      const store = await this.open();
      store.version = version;
    } catch (error) {
      throw mapRdbError(error as Error);
    }
  }

  async close(): Promise<void> {
    if (this.store !== undefined) {
      try {
        await this.store.close();
      } catch (error) {
        throw mapRdbError(error as Error);
      }
    }
    this.store = undefined;
    this.opening = undefined;
  }

  private async openDriver(): Promise<RdbTransactionDriver> {
    const store = await this.open();
    return new PlatformTransactionDriver(store);
  }

  private open(): Promise<relationalStore.RdbStore> {
    if (this.store !== undefined) {
      return Promise.resolve(this.store);
    }
    if (this.opening === undefined) {
      const config: relationalStore.StoreConfig = {
        name: this.name,
        securityLevel: relationalStore.SecurityLevel.S1
      };
      this.opening = relationalStore.getRdbStore(this.context, config)
        .then((opened: relationalStore.RdbStore): relationalStore.RdbStore => {
          this.store = opened;
          return opened;
        })
        .catch((error: Error): never => {
          this.opening = undefined;
          throw mapRdbError(error);
        });
    }
    return this.opening;
  }

  private static bindArgs(args?: ReadonlyArray<RdbValue>):
    Array<relationalStore.ValueType> {
    const bound: Array<relationalStore.ValueType> = [];
    if (args !== undefined) {
      for (let index = 0; index < args.length; index++) {
        bound.push(args[index]);
      }
    }
    return bound;
  }

  private static readRow(resultSet: relationalStore.ResultSet): RdbRow {
    const row: RdbRow = new Map<string, RdbValue>();
    const count = resultSet.columnCount;
    for (let index = 0; index < count; index++) {
      const name = resultSet.getColumnName(index);
      row.set(name, RdbStoreAdapter.readCell(resultSet, index));
    }
    return row;
  }

  private static readCell(resultSet: relationalStore.ResultSet, index: number): RdbValue {
    if (resultSet.isColumnNull(index)) {
      return null;
    }
    const columnType = resultSet.getColumnTypeSync(index);
    if (columnType === relationalStore.ColumnType.INTEGER) {
      return resultSet.getLong(index);
    }
    if (columnType === relationalStore.ColumnType.REAL) {
      return resultSet.getDouble(index);
    }
    if (columnType === relationalStore.ColumnType.TEXT) {
      return resultSet.getString(index);
    }
    if (columnType === relationalStore.ColumnType.BLOB) {
      return resultSet.getBlob(index);
    }
    return resultSet.getString(index);
  }
}
