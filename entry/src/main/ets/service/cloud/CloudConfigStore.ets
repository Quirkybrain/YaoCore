/*
 * YaoCore C-15 production cloud configuration store.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §2.7, §8.1.3, §8.5
 *
 * Single active cloud config row. The v4 `cloud_config` schema is owned by
 * T-09 `DomainMigrations` (singleton_id INTEGER PRIMARY KEY CHECK=1,
 * updated_at TEXT NOT NULL); this store never creates or alters the table.
 * The token is never stored here; only `accessTokenAlias` is persisted
 * (CB §7.1).
 */
import { AppErrors } from '../../common/types/AppError';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import type { ClockPort } from '../../common/types/Ports';
import { CloudConfig } from '../../model/FamilyModels';
import type { RdbRow, RdbStore } from '../storage/RdbStore';
import type { CloudConfigStore } from './CloudPorts';

const TABLE: string = 'cloud_config';
const SINGLETON_ID: number = 1;
const COLUMNS: string = 'singleton_id, endpoint, project_id, device_id, ' +
  'access_token_alias, shadow_endpoint, updated_at';

export class RdbCloudConfigStore implements CloudConfigStore {
  private readonly rdb: RdbStore;
  private readonly clock: ClockPort | undefined;

  /**
   * `clock` should be injected by the composition root so `updated_at` is
   * deterministic and shares the application time source. It is optional only
   * to keep the pre-existing device skeleton construction compiling.
   */
  constructor(rdb: RdbStore, clock?: ClockPort) {
    this.rdb = rdb;
    this.clock = clock;
  }

  /**
   * Verify that the v4 migration created `cloud_config` with the frozen
   * columns. This method never creates or mutates the table (F-01): the schema
   * belongs to `DomainMigrations` v4 and must run before this store opens.
   */
  async initialize(): Promise<void> {
    try {
      await this.rdb.query('SELECT ' + COLUMNS + ' FROM ' + TABLE + ' LIMIT 0');
    } catch (error) {
      throw AppErrors.of('STORAGE_MIGRATION_FAILED', []);
    }
  }

  async load(): Promise<CloudConfig | undefined> {
    const rows = await this.rdb.query('SELECT endpoint, project_id, device_id, ' +
      'access_token_alias, shadow_endpoint FROM ' + TABLE + ' WHERE singleton_id = ?',
      [SINGLETON_ID]);
    if (rows.length === 0) {
      return undefined;
    }
    const row = rows[0];
    const endpoint = RdbCloudConfigStore.required(row, 'endpoint');
    const projectId = RdbCloudConfigStore.required(row, 'project_id');
    const deviceId = RdbCloudConfigStore.required(row, 'device_id');
    const accessTokenAlias = RdbCloudConfigStore.required(row, 'access_token_alias');
    const shadowEndpoint = RdbCloudConfigStore.optional(row, 'shadow_endpoint');
    // CloudConfig performs endpoint/ID/alias invariant checks.
    return new CloudConfig(endpoint, projectId, deviceId, accessTokenAlias, shadowEndpoint);
  }

  async save(config: CloudConfig): Promise<void> {
    const updatedAt = DateTimeUtil.formatUtcCompact(this.nowMs());
    await this.rdb.execute('INSERT OR REPLACE INTO ' + TABLE + ' (' + COLUMNS + ') ' +
      'VALUES (?, ?, ?, ?, ?, ?, ?)', [
      SINGLETON_ID, config.endpoint, config.projectId, config.deviceId,
      config.accessTokenAlias, config.shadowEndpoint === undefined ? null : config.shadowEndpoint,
      updatedAt
    ]);
  }

  async clear(): Promise<void> {
    await this.rdb.execute('DELETE FROM ' + TABLE + ' WHERE singleton_id = ?', [SINGLETON_ID]);
  }

  private nowMs(): number {
    return this.clock === undefined ? Date.now() : this.clock.nowMs();
  }

  private static required(row: RdbRow, field: string): string {
    const value = row.get(field);
    if (typeof value !== 'string' || value.length === 0) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    return value;
  }

  private static optional(row: RdbRow, field: string): string | undefined {
    const value = row.get(field);
    if (value === null || value === undefined) {
      return undefined;
    }
    if (typeof value !== 'string') {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    return value;
  }
}
