/*
 * YaoCore T-08 host (local) compile/behaviour suite.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Contract: DES-A §9, §10, §22; TEST-001 host layer.
 *
 * Executable host evidence remains `entry/src/test/run-host-tests.sh` (Node).
 * This Hypium suite keeps C-06/C-07 and the device skeleton in the ArkTS
 * compile graph; the Linux Previewer execution path is BLOCKED (TEST-001 §3).
 */
import { describe, expect, it } from '@ohos/hypium';
import { StorageService } from '../../main/ets/service/storage/StorageService';
import { MigrationRegistry } from '../../main/ets/service/storage/MigrationRegistry';
import { SecretDraftStore } from '../../main/ets/service/storage/SecretDraftStore';
import { GatewayRepository } from '../../main/ets/repository/GatewayRepository';
import { GatewayAddress } from '../../main/ets/model/GatewayRoute';
import { TransportProfile } from '../../main/ets/model/DeviceTypes';
import {
  BleProvisioningIdentity,
  BleProvisioningResult,
  IdentityVersion
} from '../../main/ets/model/ProvisioningModels';
import { SecureBytes } from '../../main/ets/common/types/SecureBytes';
import { ProtocolConstants } from '../../main/ets/common/constants/ProtocolConstants';
import { StorageConstants } from '../../main/ets/common/constants/StorageConstants';
import {
  FixedClock,
  InMemoryPreferencesStore,
  InMemoryRdbStore,
  InMemorySecretStore,
  SequenceIds,
  SyncRandom
} from './FakeStores';
import storageDeviceTest from '../../ohosTest/ets/test/storage/StorageDevice.test';

const FIXED_MS: number = Date.UTC(2026, 6, 17, 8, 0, 0);
const FAMILY_ID: string = '123e4567-e89b-12d3-a456-426614174000';
const SECRET_HEX: string = '00112233445566778899aabbccddeeff';

// Imported only to pull the device-side adapter skeleton into the compile graph.
// It remains BLOCKED for execution until a device runner exists.
void storageDeviceTest;

class HostHarness {
  readonly clock: FixedClock;
  readonly preferences: InMemoryPreferencesStore;
  readonly rdb: InMemoryRdbStore;
  readonly secrets: InMemorySecretStore;
  readonly drafts: SecretDraftStore;
  readonly ids: SequenceIds;
  readonly storage: StorageService;
  readonly repo: GatewayRepository;

  constructor() {
    this.clock = new FixedClock(FIXED_MS);
    this.preferences = new InMemoryPreferencesStore();
    this.rdb = new InMemoryRdbStore();
    this.secrets = new InMemorySecretStore();
    this.drafts = new SecretDraftStore(new SyncRandom(), this.clock);
    this.ids = new SequenceIds();
    this.storage = new StorageService(this.preferences, this.rdb, this.secrets,
      new MigrationRegistry());
    this.repo = new GatewayRepository(this.rdb, this.preferences, this.secrets,
      this.drafts, this.clock, this.ids);
  }

  async start(): Promise<void> {
    await this.storage.initialize();
    await this.repo.initialize();
  }
}

export function StorageHostSuite() {
  describe('T08_C06_C07_host_compile_and_smoke', () => {
    it('C06_SecretDraftStore_isOneShot', 0, () => {
      const clock = new FixedClock(FIXED_MS);
      const drafts = new SecretDraftStore(new SyncRandom(), clock);
      const draftId = drafts.put(SecureBytes.fromHex(SECRET_HEX));
      const taken = drafts.take(draftId);
      expect(taken.toHex()).assertEqual(SECRET_HEX);
      taken.destroy();
      expect(drafts.size()).assertEqual(0);
    });

    it('C06_StorageService_initializesV1Schema', 0, async () => {
      const harness = new HostHarness();
      await harness.start();
      expect(harness.storage.isInitialized()).assertTrue();
      const rows = await harness.rdb.query('SELECT gateway_id FROM gw_route LIMIT 0');
      expect(rows.length).assertEqual(0);
    });

    it('C07_GatewayRepository_commitsHmacRouteAndSecret', 0, async () => {
      const harness = new HostHarness();
      await harness.start();
      const source = SecureBytes.fromHex(SECRET_HEX);
      const draftId = harness.drafts.put(source);
      source.destroy();
      const identity = new BleProvisioningIdentity(IdentityVersion.V20, 'gw-host', 'Host GW');
      const result = new BleProvisioningResult(identity, '192.168.1.20',
        ProtocolConstants.DEFAULT_GATEWAY_PORT, true, draftId, '20260717T080000Z');
      const route = await harness.repo.commitBinding(result, draftId, FAMILY_ID);
      expect(route.profile).assertEqual(TransportProfile.P_HMAC);
      expect(route.credentialAlias).assertEqual(StorageConstants.gatewayHmacAlias('gw-host'));
      expect(await harness.repo.isBound('gw-host')).assertTrue();
      expect(await harness.repo.peekSequence('gw-host')).assertEqual(0);
    });

    it('C07_GatewayRepository_rejectsBlockedProfile', 0, async () => {
      const harness = new HostHarness();
      await harness.start();
      const source = SecureBytes.fromHex(SECRET_HEX);
      const draftId = harness.drafts.put(source);
      source.destroy();
      const identity = new BleProvisioningIdentity(IdentityVersion.V20, 'gw-host', 'Host GW');
      const result = new BleProvisioningResult(identity, '192.168.1.20',
        ProtocolConstants.DEFAULT_GATEWAY_PORT, true, draftId, '20260717T080000Z');
      await harness.repo.commitBinding(result, draftId, FAMILY_ID);
      let blocked = false;
      try {
        await harness.repo.setPersistentProfile('gw-host', TransportProfile.P_BLOCKED);
      } catch (error) {
        blocked = true;
      }
      expect(blocked).assertTrue();
      await harness.repo.updateLastKnownAddress('gw-host',
        new GatewayAddress('192.168.1.21', ProtocolConstants.DEFAULT_GATEWAY_PORT));
      const route = await harness.repo.getRoute('gw-host');
      if (route === undefined) {
        expect(false).assertTrue();
        return;
      }
      expect(route.localIp).assertEqual('192.168.1.21');
    });
  });
}
