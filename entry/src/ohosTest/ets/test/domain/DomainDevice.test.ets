/*
 * YaoCore C-08..C-11 device-side domain tests.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §3-§6; D-019 device layer.
 *
 * STATUS: BLOCKED_ON_DEVICE_RUNNER — no device/emulator and no signing config
 * exists in this environment. This file is COMPILED_ONLY. It must never be
 * reported as PASS from the Node host runner.
 *
 * The suite exercises the real RDB adapter: v2/v4 migrations, discovery
 * arbitration persistence, tombstone persistence, and the room-deletion
 * transaction. PUBLIC TEST DATA ONLY.
 */
import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { RdbStoreAdapter } from '../../../../main/ets/service/storage/RdbStoreAdapter';
import { PreferencesStoreAdapter } from '../../../../main/ets/service/storage/PreferencesStoreAdapter';
import { MigrationRegistry } from '../../../../main/ets/service/storage/MigrationRegistry';
import { DomainMigrations } from '../../../../main/ets/repository/DomainMigrations';
import { FamilyRepository } from '../../../../main/ets/repository/FamilyRepository';
import { RoomRepository } from '../../../../main/ets/repository/RoomRepository';
import { SceneRepository } from '../../../../main/ets/repository/SceneRepository';
import { DeviceRepository } from '../../../../main/ets/repository/DeviceRepository';
import { DiscoverApplyOptions } from '../../../../main/ets/repository/DomainModels';
import { RoomService, RoomDeletionConfirmation } from '../../../../main/ets/service/room/RoomService';
import { DeviceKey } from '../../../../main/ets/model/DeviceKey';
import { DeviceSnapshot, DeviceSnapshotInit } from '../../../../main/ets/model/DeviceState';
import { DiscoverySnapshot, DiscoverySnapshotInit } from '../../../../main/ets/model/DiscoveryModels';
import { DeviceType } from '../../../../main/ets/common/constants/DeviceConstants';
import { NameValue } from '../../../../main/ets/common/types/NameValue';
import type { ClockPort, IdPort, LoggerPort } from '../../../../main/ets/common/types/Ports';

const NOW: number = Date.UTC(2026, 9, 17, 8, 0, 0);
const GATEWAY: string = 'gw-device-1';

class DeviceClock implements ClockPort {
  nowMs(): number {
    return NOW;
  }
}

class DeviceIds implements IdPort {
  private counter: number = 0;

  newId(): string {
    this.counter++;
    return '123e4567-e89b-12d3-a456-' + String(this.counter).padStart(12, '0');
  }
}

class DeviceLogger implements LoggerPort {
  debug(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
  }

  info(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
  }

  warn(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
  }

  error(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
  }
}

function lightSnapshot(deviceId: string, updatedAt: string): DeviceSnapshot {
  const init = new DeviceSnapshotInit();
  init.deviceId = deviceId;
  init.deviceName = deviceId;
  init.deviceTypeRaw = 'light';
  init.deviceType = DeviceType.LIGHT;
  init.isSupported = true;
  init.isOnline = true;
  init.updatedAt = updatedAt;
  return DeviceSnapshot.create(init);
}

function discovery(devices: ReadonlyArray<DeviceSnapshot>): DiscoverySnapshot {
  const init = new DiscoverySnapshotInit();
  init.gatewayId = GATEWAY;
  init.gatewayName = 'Device Gateway';
  init.devices = devices;
  init.generatedAt = '20261017T080000Z';
  return DiscoverySnapshot.create(init);
}

const V1: ReadonlyArray<string> = [
  'CREATE TABLE IF NOT EXISTS gw_dismissed_device (' +
    'gateway_id TEXT NOT NULL, device_id TEXT NOT NULL, dismissed_at TEXT NOT NULL, ' +
    'PRIMARY KEY (gateway_id, device_id))'
];
const V3: ReadonlyArray<string> = [
  'CREATE TABLE IF NOT EXISTS auth_profile (' +
    'profile_id TEXT PRIMARY KEY NOT NULL, family_id TEXT NOT NULL, member_id TEXT NOT NULL, ' +
    'display_name TEXT NOT NULL, hash_alias TEXT NOT NULL, salt_hex TEXT NOT NULL, ' +
    'iterations INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)'
];

export default function domainDeviceTest() {
  describe('BLOCKED_ON_DEVICE_RUNNER C08_C11 domain persistence', () => {
    it('C10_discoverTombstoneAndRestorePersistInRealRdb', 0, async () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const name = 'yaocore_t09_domain_' + String(Date.now()) + '.db';
      const store = new RdbStoreAdapter(context, name);
      const clock = new DeviceClock();
      const ids = new DeviceIds();
      const registry = new MigrationRegistry();
      registry.register(1, V1);
      FamilyRepository.registerMigrations(registry);
      registry.register(3, V3);
      DomainMigrations.register(registry);
      await registry.migrate(store);
      const preferences = new PreferencesStoreAdapter(context,
        'yaocore_t09_domain_prefs_' + String(Date.now()));
      const families = new FamilyRepository(store, preferences, clock, ids);
      const rooms = new RoomRepository(store, clock, ids);
      const scenes = new SceneRepository(store, clock, ids);
      const devices = new DeviceRepository(store, rooms, scenes, clock, new DeviceLogger());
      await families.initialize();
      await rooms.initialize();
      await scenes.initialize();
      await devices.initialize();
      const family = await families.createFamily('Device Home', 'owner-1');
      const room = await rooms.createRoom(family.familyId, 'Living');
      await devices.applyDiscoverSnapshot(discovery([lightSnapshot('Light_01', '20261017T080000Z')]),
        new DiscoverApplyOptions(family.familyId, NOW));
      const key = new DeviceKey(GATEWAY, 'Light_01');
      await devices.assignRoom(family.familyId, key, room.roomId);
      const removed = await devices.removeDevice(family.familyId, key);
      expect(removed.tombstoneCreated).assertTrue();
      expect(await devices.getRecord(key) === undefined).assertTrue();
      expect((await devices.listDismissed(GATEWAY)).length).assertEqual(1);
      expect(await devices.restoreDevice(GATEWAY, 'Light_01')).assertTrue();
      await store.close();
    });

    it('C09_roomDeletionMovesDeviceToUnassignedPoolInRealRdb', 0, async () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const name = 'yaocore_t09_room_' + String(Date.now()) + '.db';
      const store = new RdbStoreAdapter(context, name);
      const clock = new DeviceClock();
      const ids = new DeviceIds();
      const registry = new MigrationRegistry();
      registry.register(1, V1);
      FamilyRepository.registerMigrations(registry);
      registry.register(3, V3);
      DomainMigrations.register(registry);
      await registry.migrate(store);
      const preferences = new PreferencesStoreAdapter(context,
        'yaocore_t09_room_prefs_' + String(Date.now()));
      const families = new FamilyRepository(store, preferences, clock, ids);
      const rooms = new RoomRepository(store, clock, ids);
      const scenes = new SceneRepository(store, clock, ids);
      const devices = new DeviceRepository(store, rooms, scenes, clock, new DeviceLogger());
      await families.initialize();
      await rooms.initialize();
      await scenes.initialize();
      await devices.initialize();
      const family = await families.createFamily('Device Home', 'owner-1');
      const room = await rooms.createRoom(family.familyId, 'Living');
      await devices.applyDiscoverSnapshot(discovery([lightSnapshot('Light_01', '20261017T080000Z')]),
        new DiscoverApplyOptions(family.familyId, NOW));
      const key = new DeviceKey(GATEWAY, 'Light_01');
      await devices.assignRoom(family.familyId, key, room.roomId);
      const service = new RoomService(rooms, devices, families, store, clock, new DeviceLogger());
      await service.deleteRoom(room.roomId, new RoomDeletionConfirmation(true, 1));
      expect(await rooms.exists(room.roomId)).assertFalse();
      const record = await devices.getRecord(key);
      expect(record !== undefined).assertTrue();
      if (record !== undefined) {
        expect(record.state.isUnassigned).assertTrue();
        expect(record.state.isEnabled).assertFalse();
      }
      await store.close();
    });
  });
}
