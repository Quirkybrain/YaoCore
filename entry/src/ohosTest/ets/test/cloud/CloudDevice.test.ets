/*
 * YaoCore C-15 cloud device-side skeleton.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §8.5; D-019 device layer; TEST-001 §2.5
 *
 * STATUS: BLOCKED_ON_DEVICE_RUNNER — no device/emulator and no signing
 * config in this environment. This file is COMPILED_ONLY and must never be
 * reported as PASS from the host Node runner.
 *
 * Once a runner exists it proves:
 * - RdbCloudConfigStore creates/reads/clears the single active config row;
 * - the token is stored only in Asset Store and never readable except inside
 *   withToken;
 * - the platform HTTPS adapter rejects cleartext and pinned-TLS misuse.
 *
 * PUBLIC TEST DATA ONLY.
 */
import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import type { ClockPort } from '../../../../main/ets/common/types/Ports';
import { CloudConfig } from '../../../../main/ets/model/FamilyModels';
import { StorageConstants } from '../../../../main/ets/common/constants/StorageConstants';
import { RdbStoreAdapter } from '../../../../main/ets/service/storage/RdbStoreAdapter';
import { PreferencesStoreAdapter } from '../../../../main/ets/service/storage/PreferencesStoreAdapter';
import { AssetStoreSecretStore } from '../../../../main/ets/service/storage/AssetStoreSecretStore';
import { RdbCloudConfigStore } from '../../../../main/ets/service/cloud/CloudConfigStore';
import { AssetCloudCredentialStore } from '../../../../main/ets/service/cloud/CloudCredentialStore';
import { OhosCloudHttpTransport } from '../../../../main/ets/service/cloud/adapters/OhosCloudHttpTransport';
import { HttpHeaders } from '../../../../main/ets/common/types/HttpHeaders';
import { HttpRequest, TlsPolicy } from '../../../../main/ets/model/GatewayTransportModels';
import { AppError } from '../../../../main/ets/common/types/AppError';

const RDB_NAME: string = 'yaocore_t14_device.db';
const PREF_NAME: string = 'yaocore_t14_device_prefs';
const TOKEN: string = 'PUBLIC-TEST-TOKEN-ONLY';
const PIN: string = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class DeviceClock implements ClockPort {
  nowMs(): number {
    return Date.now();
  }
}

export default function cloudDeviceTest() {
  describe('BLOCKED_ON_DEVICE_RUNNER C15 cloud stores', () => {
    it('C15_RdbCloudConfigStore_roundTripsSingleActiveConfig', 0, async () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const rdb = new RdbStoreAdapter(context, RDB_NAME);
      const store = new RdbCloudConfigStore(rdb);
      await store.initialize();
      await store.clear();
      expect(await store.load() === undefined).assertTrue();

      const config = new CloudConfig('https://iotda.example.com', 'project-1',
        'gw-device-1', StorageConstants.ASSET_CLOUD_TOKEN);
      await store.save(config);
      const loaded = await store.load();
      expect(loaded === undefined).assertFalse();
      if (loaded !== undefined) {
        expect(loaded.endpoint).assertEqual('https://iotda.example.com');
        expect(loaded.projectId).assertEqual('project-1');
        expect(loaded.deviceId).assertEqual('gw-device-1');
      }
      await store.clear();
      expect(await store.load() === undefined).assertTrue();
      await rdb.close();
    });

    it('C15_AssetCloudCredentialStore_tokenOnlyInsideWithToken', 0, async () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const prefs = new PreferencesStoreAdapter(context, PREF_NAME);
      const secrets = new AssetStoreSecretStore();
      await secrets.initialize();
      const store = new AssetCloudCredentialStore(secrets, new DeviceClock(), prefs);
      await store.removeToken();
      expect(await store.hasToken()).assertFalse();
      await store.putToken(TOKEN);
      expect(await store.hasToken()).assertTrue();
      const length = await store.withToken(async (token: string): Promise<number> => token.length);
      expect(length).assertEqual(TOKEN.length);
      await store.removeToken();
      expect(await store.hasToken()).assertFalse();
      await prefs.close();
    });
  });

  describe('BLOCKED_ON_DEVICE_RUNNER C15 platform HTTPS boundary', () => {
    it('C15_OhosCloudTransport_rejectsCleartextAndPinnedPolicy', 0, async () => {
      const transport = new OhosCloudHttpTransport(new DeviceClock());
      const cleartext = new HttpRequest('GET', 'http://iotda.example.com/shadow',
        HttpHeaders.from([]), undefined, 1000, 1000);
      let cleartextCode = '';
      try {
        await transport.send(cleartext, undefined);
      } catch (error) {
        cleartextCode = (error as AppError).code;
      }
      expect(cleartextCode).assertEqual('CLOUD_ENDPOINT_INVALID');

      const https = new HttpRequest('GET', 'https://127.0.0.1:1/shadow',
        HttpHeaders.from([]), undefined, 100, 100);
      const pinned = new TlsPolicy(true, [PIN], 1, 'sha256-spki-der');
      let pinnedCode = '';
      try {
        await transport.send(https, pinned);
      } catch (error) {
        pinnedCode = (error as AppError).code;
      }
      expect(pinnedCode).assertEqual('CONFIGURATION_ERROR');
    });
  });
}
