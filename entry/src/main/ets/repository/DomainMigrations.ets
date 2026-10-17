/*
 * YaoCore DES-B v4 domain storage migrations.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §2.4, §2.7 (v4 DDL)
 *
 * Registered before StorageService construction by the composition root.
 * Versions stay contiguous: v1 C-06, v2 C-08 (FamilyRepository), v3 C-12,
 * v4 this file. T-09 does not register a v3 placeholder; C-12 owns it.
 */
import type { MigrationSink } from '../service/storage/MigrationPort';

const V4_STATEMENTS: ReadonlyArray<string> = [
  'CREATE TABLE IF NOT EXISTS room (' +
    'room_id TEXT PRIMARY KEY NOT NULL, ' +
    'family_id TEXT NOT NULL, ' +
    'room_name TEXT NOT NULL, ' +
    'icon TEXT, ' +
    'order_index INTEGER NOT NULL, ' +
    'created_at TEXT NOT NULL, ' +
    'updated_at TEXT NOT NULL)',
  'CREATE INDEX IF NOT EXISTS idx_room_family_order ON room(family_id, order_index)',
  'CREATE TABLE IF NOT EXISTS device_state (' +
    'gateway_id TEXT NOT NULL, ' +
    'device_id TEXT NOT NULL, ' +
    'family_id TEXT NOT NULL, ' +
    'device_name TEXT NOT NULL, ' +
    'room_id TEXT NOT NULL DEFAULT \'\', ' +
    'is_enabled INTEGER NOT NULL, ' +
    'is_unassigned INTEGER NOT NULL, ' +
    'snapshot_json TEXT NOT NULL, ' +
    'state_epoch_ms INTEGER NOT NULL, ' +
    'last_merge_at TEXT, ' +
    'gateway_removed INTEGER NOT NULL DEFAULT 0, ' +
    'last_applied_request_id TEXT, ' +
    'last_applied_seq INTEGER, ' +
    'PRIMARY KEY (gateway_id, device_id))',
  'CREATE INDEX IF NOT EXISTS idx_device_family_room ON device_state(family_id, room_id)',
  'CREATE INDEX IF NOT EXISTS idx_device_family_unassigned ON device_state(family_id, is_unassigned)',
  'CREATE TABLE IF NOT EXISTS scene (' +
    'scene_id TEXT PRIMARY KEY NOT NULL, ' +
    'family_id TEXT NOT NULL, ' +
    'scene_name TEXT NOT NULL, ' +
    'icon TEXT NOT NULL, ' +
    'actions_json TEXT NOT NULL, ' +
    'is_enabled INTEGER NOT NULL, ' +
    'updated_at TEXT NOT NULL)',
  'CREATE INDEX IF NOT EXISTS idx_scene_family ON scene(family_id)',
  'CREATE TABLE IF NOT EXISTS cloud_config (' +
    'singleton_id INTEGER PRIMARY KEY NOT NULL, ' +
    'endpoint TEXT NOT NULL, ' +
    'project_id TEXT NOT NULL, ' +
    'device_id TEXT NOT NULL, ' +
    'access_token_alias TEXT NOT NULL, ' +
    'shadow_endpoint TEXT, ' +
    'updated_at TEXT NOT NULL, ' +
    'CHECK (singleton_id = 1))'
];

export class DomainMigrations {
  /**
   * v4 is one schema version shared by C-09/C-10/C-11. Each component exposes
   * its own static `registerMigrations` (DES-B §2.5/§4.1.2/§5.1.3/§6.1.3) and
   * delegates here; registration is idempotent per sink so a composition root
   * may call any or all of them without a duplicate-version failure.
   */
  static register(registry: MigrationSink): void {
    if (DomainMigrations.registeredSinks.has(registry)) {
      return;
    }
    registry.register(4, V4_STATEMENTS);
    DomainMigrations.registeredSinks.set(registry, true);
  }

  private static registeredSinks: Map<MigrationSink, boolean> =
    new Map<MigrationSink, boolean>();
}
