/*
 * YaoCore C-06/C-07 device-side adapter tests.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Contract: DES-A §9.4, §10.5, §23.1-§23.3; D-019 device layer.
 *
 * STATUS: BLOCKED_ON_DEVICE_RUNNER — no device/emulator and no signing config
 * exists in this environment. This file is COMPILED_ONLY (pulled into the
 * ArkTS compile graph by the host suite); it must never be reported as PASS
 * from the Node host runner.
 *
 * The suite is registered in `entry/src/ohosTest/ets/test/List.test.ets`
 * (wp-022 R-03) but remains BLOCKED_ON_DEVICE_RUNNER. It exercises real
 * Preferences/RDB/Asset Store persistence once a device runner exists,
 * including restart persistence, transaction-internal version rollback, and
 * lock-screen access semantics (ASSET_ACCESS_DENIED). The lock-screen case
 * requires the runner to establish a locked-device precondition; it is not
 * claimed as executed in this environment.
 *
 * PUBLIC TEST DATA ONLY.
 */
import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { PreferencesStoreAdapter } from '../../../../main/ets/service/storage/PreferencesStoreAdapter';
import { RdbStoreAdapter } from '../../../../main/ets/service/storage/RdbStoreAdapter';
import { AssetStoreSecretStore } from '../../../../main/ets/service/storage/AssetStoreSecretStore';
import { SecretAlias } from '../../../../main/ets/common/types/SecretAlias';
import { RdbTransaction } from '../../../../main/ets/contracts/RdbStore';
import { AppError } from '../../../../main/ets/common/types/AppError';
import { SecureBytes } from '../../../../main/ets/common/types/SecureBytes';

const PREF_NAME: string = 'yaocore_t08_device_prefs';
const RDB_NAME: string = 'yaocore_t08_device.db';
const SECRET_ALIAS: string = 'yaocore.t08.device.secret';
const LOCK_ALIAS: string = 'yaocore.t08.device.lockprobe';
const SECRET_HEX: string = '00112233445566778899aabbccddeeff';

export default function storageDeviceTest() {
  describe('BLOCKED_ON_DEVICE_RUNNER C06 storage adapters', () => {
    it('C06_PreferencesAdapter_persistsFlushesDeletesNonSecretValue', 0, async () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const store = new PreferencesStoreAdapter(context, PREF_NAME);
      await store.putString('app.locale.mode', 'zh-CN');
      await store.flush();
      expect(await store.getString('app.locale.mode')).assertEqual('zh-CN');
      await store.delete('app.locale.mode');
      expect(await store.getString('app.locale.mode') === undefined).assertTrue();
      await store.close();
    });

    it('C06_RdbAdapter_createsMigratesTransactionsAndReadsRows', 0, async () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const store = new RdbStoreAdapter(context, RDB_NAME);
      await store.execute('CREATE TABLE IF NOT EXISTS t08_probe (' +
        'id TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)');
      await store.execute('INSERT OR REPLACE INTO t08_probe (id, value) VALUES (?, ?)',
        ['a', 'one']);
      const rows = await store.query('SELECT id, value FROM t08_probe WHERE id = ?', ['a']);
      expect(rows.length).assertEqual(1);
      expect(rows[0].get('value')).assertEqual('one');

      let rolledBack = false;
      try {
        await store.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
          await tx.execute('INSERT OR REPLACE INTO t08_probe (id, value) VALUES (?, ?)',
            ['b', 'two']);
          throw new Error('rollback probe');
        });
      } catch (error) {
        rolledBack = true;
      }
      expect(rolledBack).assertTrue();
      const after = await store.query('SELECT id FROM t08_probe WHERE id = ?', ['b']);
      expect(after.length).assertEqual(0);

      const version = await store.getVersion();
      await store.setVersion(version + 1);
      expect(await store.getVersion()).assertEqual(version + 1);
      await store.close();
    });

    it('C06_RdbAdapter_setVersionInsideTransactionRollsBack', 0, async () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const store = new RdbStoreAdapter(context, RDB_NAME);
      await store.execute('CREATE TABLE IF NOT EXISTS t08_version_probe (' +
        'id TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)');
      const before = await store.getVersion();
      let failed = false;
      try {
        await store.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
          await tx.execute('INSERT OR REPLACE INTO t08_version_probe (id, value) VALUES (?, ?)',
            ['v', 'pending']);
          // R-T08-03 / R-03: prove store.version joins the transaction and is
          // rolled back with the table write when the callback fails.
          await store.setVersion(before + 1);
          throw new Error('version rollback probe');
        });
      } catch (error) {
        failed = true;
      }
      expect(failed).assertTrue();
      expect(await store.getVersion()).assertEqual(before);
      const rows = await store.query('SELECT id FROM t08_version_probe WHERE id = ?', ['v']);
      expect(rows.length).assertEqual(0);
      await store.close();
    });

    it('C06_AssetStoreSecretStore_addQueryRemoveAndList', 0, async () => {
      const store = new AssetStoreSecretStore();
      await store.initialize();
      const secret = SecureBytes.fromHex(SECRET_HEX);
      await store.put(SECRET_ALIAS, secret);
      secret.destroy();
      const value = await store.withSecret(SECRET_ALIAS, async (bytes: Uint8Array): Promise<number> => {
        let total = 0;
        for (let index = 0; index < bytes.length; index++) {
          total += bytes[index];
        }
        return total;
      });
      expect(value > 0).assertTrue();
      const aliases = await store.list('yaocore.t08.device.');
      expect(aliases.includes(SECRET_ALIAS)).assertTrue();
      await store.remove(SECRET_ALIAS);
      let missing = false;
      try {
        await store.withSecret(SECRET_ALIAS, async (): Promise<number> => 0);
      } catch (error) {
        missing = true;
      }
      expect(missing).assertTrue();
      expect(SecretAlias.PATTERN.test(SECRET_ALIAS)).assertTrue();
    });

    it('C06_AssetStore_lockScreenPreconditionMapsDenialToAccessDenied', 0, async () => {
      // Device skeleton for R-T08-04 / R-03. The runner must establish a
      // locked-device precondition before this case; when unlocked, access is
      // expected to succeed and only the success branch is exercised. Any
      // failure must be ASSET_ACCESS_DENIED (never a generic error or a
      // plaintext fallback).
      const store = new AssetStoreSecretStore();
      let failureCode = '';
      try {
        await store.initialize();
        const secret = SecureBytes.fromHex(SECRET_HEX);
        await store.put(LOCK_ALIAS, secret);
        secret.destroy();
        await store.withSecret(LOCK_ALIAS, async (): Promise<number> => 1);
      } catch (error) {
        failureCode = (error as AppError).code;
      }
      try {
        await store.remove(LOCK_ALIAS);
      } catch (error) {
        // Cleanup is best effort: a locked device may deny it as well.
      }
      expect(failureCode === '' || failureCode === 'ASSET_ACCESS_DENIED').assertTrue();
    });
  });
}
