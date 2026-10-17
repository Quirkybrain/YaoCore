/*
 * YaoCore C-06 StorageService host tests.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Contract: DES-A §9.1-§9.4, §22.4; D-019 host layer.
 *
 * PUBLIC TEST DATA ONLY. Fake stores drive migration, drafts and secret
 * zeroization; the platform adapters are COMPILED_ONLY (no device).
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { AppError } from '../../main/ets/common/types/AppError.ets';
import { SecureBytes } from '../../main/ets/common/types/SecureBytes.ets';
import { MigrationRegistry } from '../../main/ets/service/storage/MigrationRegistry.ets';
import { SecretDraftStore } from '../../main/ets/service/storage/SecretDraftStore.ets';
import { StorageService } from '../../main/ets/service/storage/StorageService.ets';
import {
  FixedClock,
  InMemoryPreferencesStore,
  InMemoryRdbStore,
  InMemorySecretStore,
  SyncRandom,
} from '../storage/FakeStores.ets';

const FIXED_MS = Date.UTC(2026, 6, 17, 8, 0, 0);
const SECRET_HEX = '00112233445566778899aabbccddeeff';
const SECRET_HEX_2 = 'ffeeddccbbaa99887766554433221100';

const expectCode = async (fn, code) => {
  await assert.rejects(fn, (error) => {
    assert.ok(error instanceof AppError, `expected AppError, got ${error}`);
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
};
const expectSyncCode = (fn, code) => {
  assert.throws(fn, (error) => {
    assert.ok(error instanceof AppError, `expected AppError, got ${error}`);
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
};
const isZeroed = (bytes) => bytes.every((value) => value === 0);

const newDraftStore = (clock) => new SecretDraftStore(new SyncRandom(), clock);

const storageHarness = () => {
  const clock = new FixedClock(FIXED_MS);
  const preferences = new InMemoryPreferencesStore();
  const rdb = new InMemoryRdbStore();
  const secrets = new InMemorySecretStore();
  const registry = new MigrationRegistry();
  const service = new StorageService(preferences, rdb, secrets, registry);
  return { clock, preferences, rdb, secrets, registry, service };
};

test('C06_SecretDraftStore_putTakeIsOneShotAndSurvivesSourceDestroy', () => {
  const clock = new FixedClock(FIXED_MS);
  const drafts = newDraftStore(clock);
  const source = SecureBytes.fromHex(SECRET_HEX);
  const draftId = drafts.put(source);
  assert.equal(drafts.size(), 1);
  source.destroy();

  const taken = drafts.take(draftId);
  assert.equal(taken.toHex(), SECRET_HEX);
  assert.equal(drafts.size(), 0);
  taken.destroy();
  expectSyncCode(() => drafts.take(draftId), 'PROVISIONING_CREDENTIAL_MISSING');
});

test('C06_SecretDraftStore_ttlBoundaryAndExpiryZeroize', () => {
  const clock = new FixedClock(1000);
  const drafts = newDraftStore(clock);
  const first = drafts.put(SecureBytes.fromHex(SECRET_HEX), 1000);
  clock.value = 1999;
  const live = drafts.take(first);
  assert.equal(live.toHex(), SECRET_HEX);
  live.destroy();

  const second = drafts.put(SecureBytes.fromHex(SECRET_HEX_2), 1000);
  clock.value = 3000;
  expectSyncCode(() => drafts.take(second), 'PROVISIONING_SECRET_DRAFT_EXPIRED');
  assert.equal(drafts.size(), 0);
});

test('C06_SecretDraftStore_clearAllAndDestroyClearBuffers', () => {
  const clock = new FixedClock(FIXED_MS);
  const drafts = newDraftStore(clock);
  const first = drafts.put(SecureBytes.fromHex(SECRET_HEX));
  const second = drafts.put(SecureBytes.fromHex(SECRET_HEX_2));
  assert.equal(drafts.size(), 2);
  drafts.destroy(first);
  assert.equal(drafts.size(), 1);
  drafts.destroy(first);
  assert.equal(drafts.size(), 1);
  drafts.clearAll();
  assert.equal(drafts.size(), 0);
  expectSyncCode(() => drafts.take(second), 'PROVISIONING_CREDENTIAL_MISSING');
});

test('C06_SecretDraftStore_rejectsDestroyedSecretAndInvalidTtl', () => {
  const clock = new FixedClock(FIXED_MS);
  const drafts = newDraftStore(clock);
  const source = SecureBytes.fromHex(SECRET_HEX);
  source.destroy();
  expectSyncCode(() => drafts.put(source), 'SECRET_DESTROYED');
  const live = SecureBytes.fromHex(SECRET_HEX);
  expectSyncCode(() => drafts.put(live, 0), 'CONFIGURATION_ERROR');
  expectSyncCode(() => drafts.put(live, -1), 'CONFIGURATION_ERROR');
});

test('C06_MigrationRegistry_appliesContiguousVersionsAndIsIdempotent', async () => {
  const rdb = new InMemoryRdbStore();
  const registry = new MigrationRegistry();
  registry.register(1, ['CREATE TABLE IF NOT EXISTS first (id TEXT PRIMARY KEY NOT NULL)']);
  registry.register(2, ['CREATE TABLE IF NOT EXISTS second (id TEXT PRIMARY KEY NOT NULL)']);
  assert.equal(await registry.migrate(rdb), 2);
  assert.equal(await rdb.getVersion(), 2);
  assert.deepEqual(rdb.tableNamesForTest(), ['first', 'second']);
  assert.equal(await registry.migrate(rdb), 2);
  assert.equal(await rdb.getVersion(), 2);
});

test('C06_MigrationRegistry_rejectsDuplicateRegistrationAndVersionGap', async () => {
  const registry = new MigrationRegistry();
  registry.register(1, ['CREATE TABLE IF NOT EXISTS first (id TEXT PRIMARY KEY NOT NULL)']);
  expectSyncCode(() => registry.register(1, ['SELECT 1']), 'CONFIGURATION_ERROR');
  expectSyncCode(() => registry.register(0, ['SELECT 1']), 'CONFIGURATION_ERROR');

  const gap = new MigrationRegistry();
  gap.register(2, ['CREATE TABLE IF NOT EXISTS second (id TEXT PRIMARY KEY NOT NULL)']);
  const rdb = new InMemoryRdbStore();
  await expectCode(() => gap.migrate(rdb), 'STORAGE_MIGRATION_FAILED');
  assert.equal(await rdb.getVersion(), 0);
});

test('C06_MigrationRegistry_failedStatementRollsBackVersionAndTables', async () => {
  const rdb = new InMemoryRdbStore();
  const registry = new MigrationRegistry();
  registry.register(1, [
    'CREATE TABLE IF NOT EXISTS good (id TEXT PRIMARY KEY NOT NULL)',
    'INSERT INTO missing_table (id) VALUES (?)',
  ]);
  await expectCode(() => registry.migrate(rdb), 'STORAGE_MIGRATION_FAILED');
  assert.equal(await rdb.getVersion(), 0);
  assert.deepEqual(rdb.tableNamesForTest(), []);
});

test('C06_MigrationRegistry_refusesNewerSchemaWithoutDowngrade', async () => {
  const rdb = new InMemoryRdbStore();
  await rdb.setVersion(3);
  const registry = new MigrationRegistry();
  registry.register(1, ['CREATE TABLE IF NOT EXISTS first (id TEXT PRIMARY KEY NOT NULL)']);
  await expectCode(() => registry.migrate(rdb), 'STORAGE_MIGRATION_FAILED');
  assert.equal(await rdb.getVersion(), 3);
});

test('C06_StorageService_initializeRegistersV1AndIsIdempotent', async () => {
  const harness = storageHarness();
  await harness.service.initialize();
  assert.equal(harness.service.isInitialized(), true);
  assert.equal(await harness.rdb.getVersion(), 1);
  assert.deepEqual(harness.rdb.tableNamesForTest(),
    ['gw_dismissed_device', 'gw_route', 'gw_sequence']);
  await harness.service.initialize();
  assert.equal(await harness.rdb.getVersion(), 1);
});

test('C06_StorageService_getVersionFailureSurfacesStorageRdbError', async () => {
  const harness = storageHarness();
  harness.rdb.failGetVersion = true;
  await expectCode(() => harness.service.initialize(), 'STORAGE_RDB_ERROR');
  assert.equal(harness.service.isInitialized(), false);
});

test('C06_StorageService_closeDoesNotClearDataAndBlocksReinitialize', async () => {
  const harness = storageHarness();
  await harness.service.initialize();
  await harness.rdb.execute('INSERT OR REPLACE INTO gw_sequence (gateway_id, next_seq) VALUES (?, ?)',
    ['gw-a', 4]);
  await harness.service.close();
  assert.equal(harness.service.isInitialized(), false);
  const rows = await harness.rdb.query('SELECT next_seq FROM gw_sequence WHERE gateway_id = ?',
    ['gw-a']);
  assert.equal(rows[0].get('next_seq'), 4);
  await expectCode(() => harness.service.initialize(), 'STORAGE_NOT_INITIALIZED');
});

test('C06_InMemorySecretStore_withSecretZeroizesViewOnSuccessAndFailure', async () => {
  const secrets = new InMemorySecretStore();
  await secrets.put('yaocore.test.alias', SecureBytes.fromHex(SECRET_HEX));
  let captured;
  const value = await secrets.withSecret('yaocore.test.alias', async (secret) => {
    captured = secret;
    return secret.length;
  });
  assert.equal(value, 16);
  assert.equal(isZeroed(captured), true);
  assert.equal(secrets.zeroizedViews, 1);

  await assert.rejects(secrets.withSecret('yaocore.test.alias', async (secret) => {
    captured = secret;
    throw new Error('callback failed');
  }), /callback failed/);
  assert.equal(isZeroed(captured), true);
  assert.equal(secrets.zeroizedViews, 2);
});

test('C06_InMemorySecretStore_aliasGrammarAndListingHaveNoSecretValues', async () => {
  const secrets = new InMemorySecretStore();
  await secrets.put('yaocore.gateway.hmac.gw-a', SecureBytes.fromHex(SECRET_HEX));
  await secrets.put('yaocore.gateway.hmac.gw-b', SecureBytes.fromHex(SECRET_HEX_2));
  const aliases = await secrets.list('yaocore.gateway.hmac.');
  assert.deepEqual(aliases, ['yaocore.gateway.hmac.gw-a', 'yaocore.gateway.hmac.gw-b']);
  assert.equal(aliases.join('|').includes(SECRET_HEX), false);
  await expectCode(() => secrets.put('bad alias', SecureBytes.fromHex(SECRET_HEX)),
    'SECRET_ALIAS_INVALID');
  await expectCode(() => secrets.put('a'.repeat(128), SecureBytes.fromHex(SECRET_HEX)),
    'SECRET_ALIAS_INVALID');
  await expectCode(() => secrets.withSecret('missing.alias', async () => 1), 'ASSET_NOT_FOUND');
});

test('C06_SecretDraftStore_multipleDraftsAreIndependentAndUniqueIds', () => {
  const clock = new FixedClock(FIXED_MS);
  const drafts = newDraftStore(clock);
  const first = drafts.put(SecureBytes.fromHex(SECRET_HEX));
  const second = drafts.put(SecureBytes.fromHex(SECRET_HEX_2));
  assert.notEqual(first, second);
  const taken = drafts.take(second);
  assert.equal(taken.toHex(), SECRET_HEX_2);
  taken.destroy();
  const remaining = drafts.take(first);
  assert.equal(remaining.toHex(), SECRET_HEX);
  remaining.destroy();
  drafts.clearAll();
});
