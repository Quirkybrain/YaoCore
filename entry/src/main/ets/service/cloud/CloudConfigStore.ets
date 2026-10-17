/*
 * YaoCore C-15 production cloud configuration store.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §8.1.3, §8.5
 *
 * Single active cloud config row (`id='active'`). The token is never stored
 * here; only `accessTokenAlias` is persisted (CB §7.1).
 */
import { AppErrors } from '../../common/types/AppError';
import { CloudConfig } from '../../model/FamilyModels';
import type { RdbRow, RdbStore } from '../storage/RdbStore';
import type { CloudConfigStore } from './CloudPorts';

const TABLE: string = 'cloud_config';
const ACTIVE_ID: string = 'active';

export class RdbCloudConfigStore implements CloudConfigStore {
  private readonly rdb: RdbStore;

  constructor(rdb: RdbStore) {
    this.rdb = rdb;
  }

  async initialize(): Promise<void> {
    await this.rdb.execute('CREATE TABLE IF NOT EXISTS ' + TABLE + ' (' +
      'id TEXT PRIMARY KEY NOT NULL, ' +
      'endpoint TEXT NOT NULL, ' +
      'project_id TEXT NOT NULL, ' +
      'device_id TEXT NOT NULL, ' +
      'access_token_alias TEXT NOT NULL, ' +
      'shadow_endpoint TEXT)');
  }

  async load(): Promise<CloudConfig | undefined> {
    const rows = await this.rdb.query('SELECT endpoint, project_id, device_id, ' +
      'access_token_alias, shadow_endpoint FROM ' + TABLE + ' WHERE id = ?', [ACTIVE_ID]);
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
    await this.rdb.execute('INSERT OR REPLACE INTO ' + TABLE + ' (id, endpoint, project_id, ' +
      'device_id, access_token_alias, shadow_endpoint) VALUES (?, ?, ?, ?, ?, ?)', [
      ACTIVE_ID, config.endpoint, config.projectId, config.deviceId,
      config.accessTokenAlias, config.shadowEndpoint === undefined ? null : config.shadowEndpoint
    ]);
  }

  async clear(): Promise<void> {
    await this.rdb.execute('DELETE FROM ' + TABLE + ' WHERE id = ?', [ACTIVE_ID]);
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
