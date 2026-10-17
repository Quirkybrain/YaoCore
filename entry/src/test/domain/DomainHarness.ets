/*
 * YaoCore T-09 domain host harness.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 *
 * Wires the DES-B v4 schema into the in-memory RDB fake with a shared O-1
 * DomainOperationGate. PUBLIC TEST DATA ONLY; no platform adapter is touched.
 */
import { FixedClock, InMemoryPreferencesStore, InMemoryRdbStore, InMemorySecretStore, SequenceIds, SyncRandom } from '../storage/FakeStores';
import { MigrationRegistry } from '../../main/ets/service/storage/MigrationRegistry';
import { DomainOperationGate } from '../../main/ets/repository/DomainOperationGate';
import { FamilyRepository } from '../../main/ets/repository/FamilyRepository';
import { RoomRepository } from '../../main/ets/repository/RoomRepository';
import { DeviceRepository } from '../../main/ets/repository/DeviceRepository';
import { SceneRepository } from '../../main/ets/repository/SceneRepository';
import { AuthService } from '../../main/ets/service/auth/AuthService';
import { FakeDeviceControlPort, FakeFamilyAuth, FakeInviteService, FakeLogger, FakeMetrics, FakeRoutePort, ManualSceneTimer } from './DomainFakes';

const V1_PROBE: ReadonlyArray<string> = [
  'CREATE TABLE IF NOT EXISTS gw_route (' +
    'gateway_id TEXT PRIMARY KEY NOT NULL, family_id TEXT NOT NULL, gateway_name TEXT NOT NULL, ' +
    'local_ip TEXT NOT NULL, port INTEGER NOT NULL, profile TEXT NOT NULL, ' +
    'tls_enabled INTEGER NOT NULL, pins_json TEXT NOT NULL, pin_alg TEXT NOT NULL, ' +
    'key_id TEXT NOT NULL, credential_alias TEXT NOT NULL, last_known_ip TEXT NOT NULL, ' +
    'last_seen_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)',
  'CREATE TABLE IF NOT EXISTS gw_sequence (' +
    'gateway_id TEXT PRIMARY KEY NOT NULL, next_seq INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS gw_dismissed_device (' +
    'gateway_id TEXT NOT NULL, device_id TEXT NOT NULL, dismissed_at TEXT NOT NULL, ' +
    'PRIMARY KEY (gateway_id, device_id))'
];

export class DomainHarness {
  readonly clock: FixedClock;
  readonly random: SyncRandom;
  readonly preferences: InMemoryPreferencesStore;
  readonly secrets: InMemorySecretStore;
  readonly rdb: InMemoryRdbStore;
  readonly ids: SequenceIds;
  readonly gate: DomainOperationGate;
  readonly registry: MigrationRegistry;
  readonly families: FamilyRepository;
  readonly rooms: RoomRepository;
  readonly devices: DeviceRepository;
  readonly scenes: SceneRepository;
  readonly routes: FakeRoutePort;
  readonly control: FakeDeviceControlPort;
  readonly logger: FakeLogger;
  readonly metrics: FakeMetrics;
  readonly timer: ManualSceneTimer;
  readonly invites: FakeInviteService;
  readonly auth: FakeFamilyAuth;
  private initialized: boolean = false;

  constructor(nowMs: number = Date.UTC(2026, 9, 17, 8, 0, 0)) {
    this.clock = new FixedClock(nowMs);
    this.random = new SyncRandom();
    this.preferences = new InMemoryPreferencesStore();
    this.secrets = new InMemorySecretStore();
    this.rdb = new InMemoryRdbStore();
    this.ids = new SequenceIds();
    this.gate = new DomainOperationGate();
    this.registry = new MigrationRegistry();
    this.routes = new FakeRoutePort();
    this.control = new FakeDeviceControlPort();
    this.logger = new FakeLogger();
    this.metrics = new FakeMetrics();
    this.timer = new ManualSceneTimer();
    this.invites = new FakeInviteService(this.clock);
    this.auth = new FakeFamilyAuth();
    this.registry.register(1, V1_PROBE);
    FamilyRepository.registerMigrations(this.registry);
    AuthService.registerMigrations(this.registry);
    // All three v4 components expose the DES-B static registration; the
    // shared v4 registration is idempotent (wp-026 R-06).
    RoomRepository.registerMigrations(this.registry);
    DeviceRepository.registerMigrations(this.registry);
    SceneRepository.registerMigrations(this.registry);
    this.families = new FamilyRepository(this.rdb, this.preferences, this.clock, this.ids,
      this.gate);
    this.rooms = new RoomRepository(this.rdb, this.clock, this.ids, this.gate);
    this.scenes = new SceneRepository(this.rdb, this.clock, this.ids, this.gate);
    this.devices = new DeviceRepository(this.rdb, this.rooms, this.scenes, this.clock,
      this.logger, this.gate, this.routes);
  }

  async setup(): Promise<void> {
    if (this.initialized) {
      return;
    }
    await this.registry.migrate(this.rdb);
    await this.families.initialize();
    await this.rooms.initialize();
    await this.scenes.initialize();
    await this.devices.initialize();
    this.initialized = true;
  }

  advance(ms: number): void {
    this.clock.value += ms;
    this.timer.advance(ms);
  }
}

export async function newDomainHarness(nowMs: number = Date.UTC(2026, 9, 17, 8, 0, 0)):
  Promise<DomainHarness> {
  const harness = new DomainHarness(nowMs);
  await harness.setup();
  return harness;
}
