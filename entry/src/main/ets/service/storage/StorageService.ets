/*
 * YaoCore C-06 StorageService and DES-A v1 migrations.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Contract: DES-A §9.1.4, §9.1.6, §9.3, §22.2
 *
 * Owns the RDB migration gate and exposes the three storage ports. v1 is the
 * DES-A schema (gw_route/gw_sequence/gw_dismissed_device) plus a family index
 * for listRoutesByFamily. Later components register their own versions before
 * this service is constructed; migrate() runs only missing versions.
 *
 * close() releases no data: adapters own platform handles, and the contract
 * explicitly forbids clearing user data here.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { StorageConstants } from '../../common/constants/StorageConstants';
import type { MigrationSink, MigrationRegistryPort } from './MigrationPort';
import type { PreferencesStore } from './PreferencesStore';
import type { RdbStore } from './RdbStore';
import type { SecretStore } from './SecretStore';

export class StorageService {
  readonly preferences: PreferencesStore;
  readonly rdb: RdbStore;
  readonly secrets: SecretStore;
  private readonly migrations: MigrationRegistryPort;
  private initialized: boolean = false;
  private closed: boolean = false;

  constructor(preferences: PreferencesStore, rdb: RdbStore, secrets: SecretStore,
    migrations: MigrationRegistryPort) {
    this.preferences = preferences;
    this.rdb = rdb;
    this.secrets = secrets;
    this.migrations = migrations;
    StorageService.registerMigrations(migrations);
  }

  /** DES-A v1 DDL. Idempotent: every statement uses IF NOT EXISTS. */
  static registerMigrations(sink: MigrationSink): void {
    sink.register(StorageConstants.RDB_BASE_VERSION, [
      'CREATE TABLE IF NOT EXISTS gw_route (' +
        'gateway_id TEXT PRIMARY KEY NOT NULL, ' +
        'family_id TEXT NOT NULL, ' +
        'gateway_name TEXT NOT NULL, ' +
        'local_ip TEXT NOT NULL, ' +
        'port INTEGER NOT NULL, ' +
        'profile TEXT NOT NULL, ' +
        'tls_enabled INTEGER NOT NULL, ' +
        'pins_json TEXT NOT NULL, ' +
        'pin_alg TEXT NOT NULL, ' +
        'key_id TEXT NOT NULL, ' +
        'credential_alias TEXT NOT NULL, ' +
        'last_known_ip TEXT NOT NULL, ' +
        'last_seen_at TEXT, ' +
        'created_at TEXT NOT NULL, ' +
        'updated_at TEXT NOT NULL)',
      'CREATE TABLE IF NOT EXISTS gw_sequence (' +
        'gateway_id TEXT PRIMARY KEY NOT NULL, ' +
        'next_seq INTEGER NOT NULL)',
      'CREATE TABLE IF NOT EXISTS gw_dismissed_device (' +
        'gateway_id TEXT NOT NULL, ' +
        'device_id TEXT NOT NULL, ' +
        'dismissed_at TEXT NOT NULL, ' +
        'PRIMARY KEY (gateway_id, device_id))',
      'CREATE INDEX IF NOT EXISTS gw_route_family_idx ON gw_route (family_id)'
    ]);
  }

  async initialize(): Promise<void> {
    if (this.closed) {
      throw AppErrors.of('STORAGE_NOT_INITIALIZED', []);
    }
    try {
      await this.migrations.migrate(this.rdb);
    } catch (error) {
      if (error instanceof AppError) {
        if (error.code === 'STORAGE_MIGRATION_FAILED' || error.code === 'STORAGE_RDB_ERROR') {
          throw error;
        }
      }
      throw AppErrors.of('STORAGE_MIGRATION_FAILED', []);
    }
    try {
      await this.rdb.query('SELECT gateway_id FROM gw_route LIMIT 0');
      await this.rdb.query('SELECT gateway_id FROM gw_sequence LIMIT 0');
    } catch (error) {
      throw AppErrors.of('STORAGE_MIGRATION_FAILED', []);
    }
    this.initialized = true;
  }

  isInitialized(): boolean {
    return this.initialized;
  }

  async close(): Promise<void> {
    // Only drops the logical lifecycle flag; platform adapters own handles and
    // no persisted data is cleared (DES-A §9.3 invariant 5).
    this.initialized = false;
    this.closed = true;
  }

}
