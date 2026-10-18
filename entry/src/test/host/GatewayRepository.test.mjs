/*
 * YaoCore C-07 GatewayRepository host tests.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Contract: DES-A §10.1-§10.5, §22; ADR-002 §4/§6/§8.3/§8.4; D-019 host layer.
 *
 * PUBLIC TEST DATA ONLY. Everything runs on in-memory fakes. Device-only
 * behaviour (real Asset Store/RDB) remains COMPILED_ONLY/BLOCKED.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { AppError, AppErrors } from '../../main/ets/common/types/AppError.ets';
import { SecureBytes } from '../../main/ets/common/types/SecureBytes.ets';
import { ProtocolConstants } from '../../main/ets/common/constants/ProtocolConstants.ets';
import { StorageConstants } from '../../main/ets/common/constants/StorageConstants.ets';
import { GatewayAddress } from '../../main/ets/model/GatewayRoute.ets';
import { TransportProfile } from '../../main/ets/model/DeviceTypes.ets';
import {
  BleProvisioningIdentity,
  BleProvisioningResult,
  IdentityVersion,
  ProvisioningTlsMaterial,
} from '../../main/ets/model/ProvisioningModels.ets';
import { GatewayRepository } from '../../main/ets/repository/GatewayRepository.ets';

import { InvitedGateway } from '../../main/ets/model/InvitedGateway.ets';
import { MigrationRegistry } from '../../main/ets/service/storage/MigrationRegistry.ets';
import { StorageService } from '../../main/ets/service/storage/StorageService.ets';
import { SecretDraftStore } from '../../main/ets/service/storage/SecretDraftStore.ets';
import {
  FixedClock,
  InMemoryPreferencesStore,
  InMemoryRdbStore,
  InMemorySecretStore,
  SequenceIds,
  SyncRandom,
} from '../storage/FakeStores.ets';

const FIXED_MS = Date.UTC(2026, 6, 17, 8, 0, 0);
const FIXED_TS = '20260717T080000Z';
const FAMILY_A = '123e4567-e89b-12d3-a456-426614174000';
const FAMILY_B = '123e4567-e89b-12d3-a456-426614174001';
const PIN_A = 'a'.repeat(64);
const PIN_B = 'b'.repeat(64);
const SECRET_OLD = '00112233445566778899aabbccddeeff';
const SECRET_NEW = '102132435465768798a9bacbdcedfe0f';

const expectCode = async (fn, code) => {
  await assert.rejects(fn, (error) => {
    assert.ok(error instanceof AppError, `expected AppError, got ${error}`);
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
};

const setup = async () => {
  const clock = new FixedClock(FIXED_MS);
  const preferences = new InMemoryPreferencesStore();
  const rdb = new InMemoryRdbStore();
  const secrets = new InMemorySecretStore();
  const drafts = new SecretDraftStore(new SyncRandom(), clock);
  const storage = new StorageService(preferences, rdb, secrets, new MigrationRegistry());
  await storage.initialize();
  const ids = new SequenceIds();
  const repo = new GatewayRepository(rdb, preferences, secrets, drafts, clock, ids);
  await repo.initialize();
  return { clock, preferences, rdb, secrets, drafts, storage, ids, repo };
};

const draftFor = (drafts, hex) => {
  const source = SecureBytes.fromHex(hex);
  const draftId = drafts.put(source);
  source.destroy();
  return draftId;
};

const makeTls = (pins = [PIN_A, PIN_B], port = 9443) =>
  new ProvisioningTlsMaterial(pins, port, 'sha256-spki-der');

const makeResult = ({
  gatewayId = 'gw-a',
  gatewayName = 'Gateway A',
  version = IdentityVersion.V20,
  tls = undefined,
  ip = '192.168.1.20',
  draftId = '',
  completedAt = FIXED_TS,
} = {}) => {
  const identity = new BleProvisioningIdentity(version, gatewayId, gatewayName, tls);
  const port = tls === undefined ? ProtocolConstants.DEFAULT_GATEWAY_PORT : tls.port;
  return new BleProvisioningResult(identity, ip, port, true, draftId, completedAt);
};

const bindDraft = async (h, hex, options = {}) => {
  const draftId = draftFor(h.drafts, hex);
  const result = makeResult({ ...options, draftId });
  const route = await h.repo.commitBinding(result, draftId, options.familyId ?? FAMILY_A);
  return route;
};

const secretHexViaRepo = async (repo, gatewayId) => {
  let hex = '';
  await repo.withCommandSecret(gatewayId, async (secret) => {
    hex = Buffer.from(secret).toString('hex');
  });
  return hex;
};

class RecordingVerifier {
  constructor(result = true, throwCode = undefined) {
    this.result = result;
    this.throwCode = throwCode;
    this.calls = 0;
    this.gatewayId = '';
    this.secretHex = '';
  }

  async verify(gatewayId, secret) {
    this.calls += 1;
    this.gatewayId = gatewayId;
    this.secretHex = Buffer.from(secret).toString('hex');
    if (this.throwCode !== undefined) {
      throw AppErrors.of(this.throwCode, []);
    }
    return this.result;
  }
}

test('C07_commitBinding_hmacPersistsRouteAndOneShotSecret', async () => {
  const h = await setup();
  const draftId = draftFor(h.drafts, SECRET_OLD);
  const result = makeResult({ draftId });
  const route = await h.repo.commitBinding(result, draftId, FAMILY_A);

  assert.equal(route.gatewayId, 'gw-a');
  assert.equal(route.familyId, FAMILY_A);
  assert.equal(route.profile, TransportProfile.P_HMAC);
  assert.equal(route.tlsEnabled, false);
  assert.deepEqual(route.pins, []);
  assert.equal(route.pinAlg, '');
  assert.equal(route.port, ProtocolConstants.DEFAULT_GATEWAY_PORT);
  assert.equal(route.keyId, 'app-key-v1');
  assert.equal(route.credentialAlias, StorageConstants.gatewayHmacAlias('gw-a'));
  assert.equal(route.lastKnownIp, '192.168.1.20');
  assert.equal(route.lastSeenAt, FIXED_TS);
  assert.equal(route.createdAt, FIXED_TS);
  assert.equal(await h.secrets.peekHexForTest(route.credentialAlias), SECRET_OLD);
  assert.equal(h.drafts.size(), 0);
  assert.equal(await secretHexViaRepo(h.repo, 'gw-a'), SECRET_OLD);

  // One-shot: replaying the same draft must not rebind.
  await expectCode(() => h.repo.commitBinding(result, draftId, FAMILY_A),
    'PROVISIONING_SECRET_DRAFT_EXPIRED');
});

test('C07_commitBinding_tlsPersistsPinsPortAndMaterial', async () => {
  const h = await setup();
  const tls = makeTls([PIN_A, PIN_B], 9443);
  const draftId = draftFor(h.drafts, SECRET_OLD);
  const route = await h.repo.commitBinding(
    makeResult({ version: IdentityVersion.V21, tls, draftId, gatewayName: 'TLS Gateway' }),
    draftId, FAMILY_A);

  assert.equal(route.profile, TransportProfile.P_TLS_PIN);
  assert.equal(route.tlsEnabled, true);
  assert.deepEqual(route.pins, [PIN_A, PIN_B]);
  assert.equal(route.port, 9443);
  assert.equal(route.pinAlg, 'sha256-spki-der');
  const material = await h.repo.tlsMaterial('gw-a');
  assert.ok(material !== undefined);
  assert.deepEqual(material.pins, [PIN_A, PIN_B]);
  assert.equal(material.port, 9443);
});

test('C07_commitBinding_rejectsDraftMismatchBeforeConsumingDraft', async () => {
  const h = await setup();
  const draftId = draftFor(h.drafts, SECRET_OLD);
  const result = makeResult({ draftId: 'different-draft' });
  await expectCode(() => h.repo.commitBinding(result, draftId, FAMILY_A),
    'CONFIGURATION_ERROR');
  const taken = h.drafts.take(draftId);
  assert.equal(taken.toHex(), SECRET_OLD);
  taken.destroy();
  assert.equal(await h.repo.isBound('gw-a'), false);
});

test('C07_commitBinding_rejectsSilentFamilyMigration', async () => {
  const h = await setup();
  await bindDraft(h, SECRET_OLD);
  const draftId = draftFor(h.drafts, SECRET_NEW);
  await expectCode(() => h.repo.commitBinding(makeResult({ draftId }), draftId, FAMILY_B),
    'CONFIGURATION_ERROR');
  const route = await h.repo.getRoute('gw-a');
  assert.equal(route.familyId, FAMILY_A);
  const taken = h.drafts.take(draftId);
  assert.equal(taken.toHex(), SECRET_NEW);
  taken.destroy();
});

test('C07_commitBinding_routeWriteFails_restoresPreviousSecret', async () => {
  const h = await setup();
  await bindDraft(h, SECRET_OLD);
  const draftId = draftFor(h.drafts, SECRET_NEW);
  h.rdb.failNextExecuteContaining = 'INSERT OR REPLACE INTO gw_route';
  await expectCode(() => h.repo.commitBinding(
    makeResult({ draftId, gatewayName: 'Renamed' }), draftId, FAMILY_A),
  'STORAGE_RDB_ERROR');
  assert.equal(await secretHexViaRepo(h.repo, 'gw-a'), SECRET_OLD);
  const route = await h.repo.getRoute('gw-a');
  assert.equal(route.gatewayName, 'Gateway A');
  // The draft is single-use even when the binding failed.
  await expectCode(async () => h.drafts.take(draftId), 'PROVISIONING_CREDENTIAL_MISSING');
});

test('C07_commitBinding_rollbackRestoreFailureDeletesUnverifiedSecret', async () => {
  const h = await setup();
  await bindDraft(h, SECRET_OLD);
  const draftId = draftFor(h.drafts, SECRET_NEW);
  const originalPut = h.secrets.put.bind(h.secrets);
  let putCalls = 0;
  h.secrets.put = async (alias, secret) => {
    putCalls += 1;
    if (putCalls === 2) {
      throw AppErrors.of('ASSET_IO_FAILED', []);
    }
    return originalPut(alias, secret);
  };
  h.rdb.failNextExecuteContaining = 'INSERT OR REPLACE INTO gw_route';
  await expectCode(() => h.repo.commitBinding(makeResult({ draftId }), draftId, FAMILY_A),
    'STORAGE_RDB_ERROR');
  assert.equal(putCalls, 2);
  // Fail closed: an unverified replacement secret must not remain usable.
  assert.equal(h.secrets.has(StorageConstants.gatewayHmacAlias('gw-a')), false);
});

test('C07_commitBinding_freshRouteWriteFails_removesNewSecret', async () => {
  const h = await setup();
  const draftId = draftFor(h.drafts, SECRET_NEW);
  h.rdb.failNextExecuteContaining = 'INSERT OR REPLACE INTO gw_route';
  await expectCode(() => h.repo.commitBinding(makeResult({ draftId }), draftId, FAMILY_A),
    'STORAGE_RDB_ERROR');
  assert.equal(h.secrets.has(StorageConstants.gatewayHmacAlias('gw-a')), false);
  assert.equal(await h.repo.isBound('gw-a'), false);
});

test('C07_commitBinding_secretWriteFails_writesNoRoute', async () => {
  const h = await setup();
  const draftId = draftFor(h.drafts, SECRET_OLD);
  h.secrets.failPut = true;
  await expectCode(() => h.repo.commitBinding(makeResult({ draftId }), draftId, FAMILY_A),
    'ASSET_IO_FAILED');
  assert.equal(await h.repo.isBound('gw-a'), false);
  assert.equal(h.secrets.size(), 0);
});

test('C07_commitBinding_rejectsShortAndOversizedDraftSecretsBeforePersisting', async () => {
  const h = await setup();
  // SC-04 Must: 1-byte secret (review probe R-01) and an oversized draft must
  // both be rejected without writing a secret or route; the draft is consumed.
  const invalidHex = ['00', '00'.repeat(4097)];
  for (const hex of invalidHex) {
    const draftId = draftFor(h.drafts, hex);
    await assert.rejects(
      () => h.repo.commitBinding(makeResult({ draftId }), draftId, FAMILY_A),
      (error) => {
        assert.ok(error instanceof AppError);
        assert.equal(error.code, 'CONFIGURATION_ERROR');
        assert.deepEqual(error.details.map((detail) => detail.value), ['secret']);
        return true;
      });
    assert.equal(await h.repo.isBound('gw-a'), false);
    assert.equal(h.secrets.size(), 0);
    assert.equal(h.drafts.size(), 0);
  }
});

test('C07_commitBinding_withoutDraftReusesSecretAndRequiresExistingBinding', async () => {
  const h = await setup();
  await bindDraft(h, SECRET_OLD);
  const route = await h.repo.commitBinding(
    makeResult({ gatewayName: 'Renamed', ip: '192.168.1.44' }), '', FAMILY_A);
  assert.equal(route.gatewayName, 'Renamed');
  assert.equal(route.localIp, '192.168.1.44');
  assert.equal(route.lastKnownIp, '192.168.1.44');
  assert.equal(await secretHexViaRepo(h.repo, 'gw-a'), SECRET_OLD);

  await expectCode(() => h.repo.commitBinding(makeResult({ gatewayId: 'gw-missing' }), '',
    FAMILY_A), 'PROVISIONING_CREDENTIAL_MISSING');
});

test('C07_commitBinding_markSeenFailureStillReportsCommittedBinding', async () => {
  const h = await setup();
  const draftId = draftFor(h.drafts, SECRET_OLD);
  h.repo.markSeen = async () => {
    throw AppErrors.of('STORAGE_RDB_ERROR', []);
  };
  const route = await h.repo.commitBinding(makeResult({ draftId }), draftId, FAMILY_A);
  // R-05: route + secret are durable before markSeen; a failure must not be
  // reported as a failed binding. last_seen_at may lag.
  assert.equal(route.gatewayId, 'gw-a');
  assert.equal(route.lastSeenAt, undefined);
  assert.equal(await h.repo.isBound('gw-a'), true);
  assert.equal(await secretHexViaRepo(h.repo, 'gw-a'), SECRET_OLD);
  assert.equal(h.drafts.size(), 0);
});

test('C07_commitBinding_reusePath_markSeenFailureStillReportsCommittedBinding', async () => {
  const h = await setup();
  await bindDraft(h, SECRET_OLD);
  h.clock.value = FIXED_MS + 60000;
  h.repo.markSeen = async () => {
    throw AppErrors.of('STORAGE_RDB_ERROR', []);
  };
  const route = await h.repo.commitBinding(
    makeResult({ gatewayName: 'Renamed after reuse', ip: '192.168.1.55' }), '', FAMILY_A);
  assert.equal(route.gatewayName, 'Renamed after reuse');
  assert.equal(route.localIp, '192.168.1.55');
  assert.equal(route.lastSeenAt, FIXED_TS);
  assert.equal(await secretHexViaRepo(h.repo, 'gw-a'), SECRET_OLD);
});

test('C07_commitBinding_readBackFailureReturnsCommittedSnapshot', async () => {
  const h = await setup();
  const draftId = draftFor(h.drafts, SECRET_OLD);
  const originalReadRoute = h.repo.readRoute.bind(h.repo);
  let readCalls = 0;
  h.repo.readRoute = async (gatewayId) => {
    readCalls += 1;
    // Fresh binding read order: existing check, markSeen guard, final read-back.
    if (readCalls === 3) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    return originalReadRoute(gatewayId);
  };
  const route = await h.repo.commitBinding(makeResult({ draftId }), draftId, FAMILY_A);
  // The write already committed, so return the committed snapshot rather than
  // a false failure; the persisted row still contains markSeen's timestamp.
  assert.equal(route.gatewayId, 'gw-a');
  assert.equal(route.lastSeenAt, undefined);
  assert.equal(await h.repo.isBound('gw-a'), true);
  assert.equal((await h.repo.getRoute('gw-a')).lastSeenAt, FIXED_TS);
  assert.equal(await secretHexViaRepo(h.repo, 'gw-a'), SECRET_OLD);
});

test('C07_commitBinding_missingDraftMeansExpired', async () => {
  const h = await setup();
  await expectCode(() => h.repo.commitBinding(
    makeResult({ draftId: 'draft-never-issued' }), 'draft-never-issued', FAMILY_A),
  'PROVISIONING_SECRET_DRAFT_EXPIRED');
});

test('C07_applyInvitedGateway_isIdempotentAndPreservesCreatedAt', async () => {
  const h = await setup();
  const tls = makeTls([PIN_A], 9443);
  const entry = new InvitedGateway('gw-inv', FAMILY_A, 'Invite Gateway',
    SecureBytes.fromHex(SECRET_OLD), tls);
  await h.repo.applyInvitedGateway(entry);
  const first = await h.repo.getRoute('gw-inv');
  await h.repo.applyInvitedGateway(entry);
  const routes = await h.repo.listRoutes();
  assert.equal(routes.length, 1);
  assert.equal(routes[0].createdAt, first.createdAt);
  assert.equal(routes[0].profile, TransportProfile.P_TLS_PIN);
  assert.equal(await h.secrets.peekHexForTest(StorageConstants.gatewayHmacAlias('gw-inv')),
    SECRET_OLD);
  entry.commandSecret.destroy();

  const wrongFamily = new InvitedGateway('gw-inv', FAMILY_B, 'Invite Gateway',
    SecureBytes.fromHex(SECRET_NEW));
  await expectCode(() => h.repo.applyInvitedGateway(wrongFamily), 'CONFIGURATION_ERROR');
  wrongFamily.commandSecret.destroy();
});

test('C07_applyInvitedGateway_secretWriteFailureWritesNoRoute', async () => {
  const h = await setup();
  const entry = new InvitedGateway('gw-inv', FAMILY_A, 'Invite Gateway',
    SecureBytes.fromHex(SECRET_OLD));
  h.secrets.failPut = true;
  await expectCode(() => h.repo.applyInvitedGateway(entry), 'ASSET_IO_FAILED');
  assert.equal(await h.repo.isBound('gw-inv'), false);
  entry.commandSecret.destroy();
});

test('C07_setPersistentProfile_rejectsBlockedAndMigratesHmacTls', async () => {
  const h = await setup();
  await bindDraft(h, SECRET_OLD, { version: IdentityVersion.V21, tls: makeTls([PIN_A], 9443) });
  await expectCode(() => h.repo.setPersistentProfile('gw-a', TransportProfile.P_BLOCKED),
    'GATEWAY_PROFILE_BLOCKED');
  assert.equal((await h.repo.getRoute('gw-a')).profile, TransportProfile.P_TLS_PIN);

  await h.repo.setPersistentProfile('gw-a', TransportProfile.P_HMAC);
  const hmac = await h.repo.getRoute('gw-a');
  assert.equal(hmac.profile, TransportProfile.P_HMAC);
  assert.equal(hmac.tlsEnabled, false);
  assert.deepEqual(hmac.pins, []);
  assert.equal(hmac.pinAlg, '');
  assert.equal(hmac.port, ProtocolConstants.DEFAULT_GATEWAY_PORT);
  assert.equal(await h.repo.tlsMaterial('gw-a'), undefined);

  await expectCode(() => h.repo.setPersistentProfile('gw-a', TransportProfile.P_TLS_PIN),
    'TLS_PROFILE_INCONSISTENT');
  await expectCode(() => h.repo.setPersistentProfile('gw-missing', TransportProfile.P_HMAC),
    'GATEWAY_NOT_BOUND');
});

test('C07_pinVerified_shrinksMultiPinSetAndFailsClosedOnUnknownPin', async () => {
  const h = await setup();
  await bindDraft(h, SECRET_OLD, { version: IdentityVersion.V21, tls: makeTls([PIN_A, PIN_B]) });
  await expectCode(() => h.repo.pinVerified('gw-a', 'c'.repeat(64)), 'TLS_PIN_CONFIG_INVALID');
  assert.deepEqual((await h.repo.getRoute('gw-a')).pins, [PIN_A, PIN_B]);

  await h.repo.pinVerified('gw-a', PIN_B);
  assert.deepEqual((await h.repo.getRoute('gw-a')).pins, [PIN_B]);
  await h.repo.pinVerified('gw-a', PIN_B);
  assert.deepEqual((await h.repo.getRoute('gw-a')).pins, [PIN_B]);
  await expectCode(() => h.repo.pinVerified('gw-a', 'not-a-pin'), 'TLS_PIN_CONFIG_INVALID');

  await bindDraft(h, SECRET_OLD, { gatewayId: 'gw-hmac' });
  await expectCode(() => h.repo.pinVerified('gw-hmac', PIN_A), 'TLS_PROFILE_INCONSISTENT');
});

test('C07_rotateSecret_successPromotesActiveAndRemovesPending', async () => {
  const h = await setup();
  await bindDraft(h, SECRET_OLD);
  const verifier = new RecordingVerifier(true);
  const next = SecureBytes.fromHex(SECRET_NEW);
  await h.repo.rotateSecret('gw-a', next, verifier);
  next.destroy();

  assert.equal(verifier.calls, 1);
  assert.equal(verifier.gatewayId, 'gw-a');
  assert.equal(verifier.secretHex, SECRET_NEW);
  assert.equal(await secretHexViaRepo(h.repo, 'gw-a'), SECRET_NEW);
  assert.deepEqual(await h.secrets.list(
    StorageConstants.ASSET_PREFIX_GATEWAY_HMAC_PENDING), []);
});

test('C07_rotateSecret_verificationFailureKeepsActiveAndRemovesPending', async () => {
  const h = await setup();
  await bindDraft(h, SECRET_OLD);
  const next = SecureBytes.fromHex(SECRET_NEW);
  await expectCode(() => h.repo.rotateSecret('gw-a', next, new RecordingVerifier(false)),
    'SIGNATURE_INVALID');
  next.destroy();
  assert.equal(await secretHexViaRepo(h.repo, 'gw-a'), SECRET_OLD);
  assert.deepEqual(await h.secrets.list(
    StorageConstants.ASSET_PREFIX_GATEWAY_HMAC_PENDING), []);
});

test('C07_rotateSecret_verifierThrowKeepsActiveAndRemovesPending', async () => {
  const h = await setup();
  await bindDraft(h, SECRET_OLD);
  const next = SecureBytes.fromHex(SECRET_NEW);
  await expectCode(() => h.repo.rotateSecret('gw-a', next,
    new RecordingVerifier(true, 'GATEWAY_UNREACHABLE')), 'GATEWAY_UNREACHABLE');
  next.destroy();
  assert.equal(await secretHexViaRepo(h.repo, 'gw-a'), SECRET_OLD);
  assert.deepEqual(await h.secrets.list(
    StorageConstants.ASSET_PREFIX_GATEWAY_HMAC_PENDING), []);
});

test('C07_initialize_cleansLeftoverPendingRotationAliases', async () => {
  const h = await setup();
  const pendingAlias = StorageConstants.gatewayHmacPendingAlias('gw-a', 'rot1');
  await h.secrets.put(pendingAlias, SecureBytes.fromHex(SECRET_NEW));
  assert.equal(h.secrets.has(pendingAlias), true);
  await h.repo.initialize();
  assert.equal(h.secrets.has(pendingAlias), false);
});

test('C07_removeLocalBinding_deletesRouteSecretsAndSequenceWithoutNetwork', async () => {
  const h = await setup();
  await bindDraft(h, SECRET_OLD);
  await h.repo.nextSequence('gw-a');
  await h.repo.nextSequence('gw-a');
  const transport = { calls: 0 };
  await h.repo.removeLocalBinding('gw-a');
  assert.equal(await h.repo.isBound('gw-a'), false);
  assert.equal(h.secrets.has(StorageConstants.gatewayHmacAlias('gw-a')), false);
  const sequence = await h.rdb.query('SELECT next_seq FROM gw_sequence WHERE gateway_id = ?',
    ['gw-a']);
  assert.equal(sequence.length, 0);
  assert.equal(transport.calls, 0);
  await expectCode(() => h.repo.removeLocalBinding('gw-a'), 'GATEWAY_NOT_BOUND');
});

test('C07_sequence_nextPeekResetAndSaturation', async () => {
  const h = await setup();
  await bindDraft(h, SECRET_OLD);
  assert.equal(await h.repo.peekSequence('gw-a'), 0);
  assert.equal(await h.repo.nextSequence('gw-a'), 0);
  assert.equal(await h.repo.nextSequence('gw-a'), 1);
  assert.equal(await h.repo.peekSequence('gw-a'), 2);
  assert.equal(await h.repo.resetSequenceIfIdle('gw-a'), 0);
  assert.equal(await h.repo.peekSequence('gw-a'), 0);

  await h.rdb.execute('UPDATE gw_sequence SET next_seq = ? WHERE gateway_id = ?',
    [ProtocolConstants.MAX_SEQ, 'gw-a']);
  await expectCode(() => h.repo.nextSequence('gw-a'), 'CONFIGURATION_ERROR');
  assert.equal(await h.repo.resetSequenceIfIdle('gw-a'), 0);
  assert.equal(await h.repo.peekSequence('gw-a'), 0);
  await expectCode(() => h.repo.nextSequence('gw-missing'), 'GATEWAY_NOT_BOUND');
});

test('C07_sequence_concurrentNextCallsAreSerialized', async () => {
  const h = await setup();
  await bindDraft(h, SECRET_OLD);
  const values = await Promise.all(Array.from({ length: 40 }, () => h.repo.nextSequence('gw-a')));
  values.sort((left, right) => left - right);
  assert.deepEqual(values, Array.from({ length: 40 }, (_, index) => index));
  assert.equal(await h.repo.peekSequence('gw-a'), 40);
});

test('C07_routes_listByFamilyIsBoundAndAddressUpdates', async () => {
  const h = await setup();
  await bindDraft(h, SECRET_OLD, { gatewayId: 'gw-a', gatewayName: 'A' });
  await bindDraft(h, SECRET_OLD, {
    gatewayId: 'gw-b', gatewayName: 'B', familyId: FAMILY_B,
  });
  assert.equal((await h.repo.listRoutes()).length, 2);
  const familyA = await h.repo.listRoutesByFamily(FAMILY_A);
  assert.equal(familyA.length, 1);
  assert.equal(familyA[0].gatewayId, 'gw-a');
  assert.equal(await h.repo.isBound('gw-b'), true);
  await expectCode(() => h.repo.listRoutesByFamily(''), 'PROTOCOL_INVALID_IDENTIFIER');

  await h.repo.updateLastKnownAddress('gw-a', new GatewayAddress('192.168.1.77', 9201));
  const updated = await h.repo.getRoute('gw-a');
  assert.equal(updated.localIp, '192.168.1.77');
  assert.equal(updated.lastKnownIp, '192.168.1.77');
  assert.equal(updated.port, 9201);
  await expectCode(() => h.repo.updateLastKnownAddress('gw-missing',
    new GatewayAddress('192.168.1.77', 9200)), 'GATEWAY_NOT_BOUND');
});

test('C07_credentials_unboundAndTlsOnlySemantics', async () => {
  const h = await setup();
  await expectCode(() => h.repo.withCommandSecret('gw-missing', async () => 1),
    'GATEWAY_NOT_BOUND');
  await expectCode(() => h.repo.tlsMaterial('gw-missing'), 'GATEWAY_NOT_BOUND');
});

test('C07_initialize_requiresTablesAndInitializeState', async () => {
  const h = await setup();
  const fresh = new GatewayRepository(h.rdb, h.preferences, h.secrets, h.drafts,
    h.clock, h.ids);
  await expectCode(() => fresh.listRoutes(), 'STORAGE_NOT_INITIALIZED');
});

test('C07_secretDiscipline_noPlaintextInPreferencesRdbOrErrors', async () => {
  const h = await setup();
  await bindDraft(h, SECRET_OLD, {
    version: IdentityVersion.V21,
    tls: makeTls([PIN_A], 9443),
  });

  let view;
  await h.repo.withCommandSecret('gw-a', async (secret) => {
    view = secret;
    assert.equal(Buffer.from(secret).toString('hex'), SECRET_OLD);
  });
  assert.equal(view.every((byte) => byte === 0), true);
  assert.ok(h.secrets.zeroizedViews >= 1);

  const persisted = h.preferences.dumpValuesForTest().concat(h.rdb.dumpAllValuesForTest());
  const base64 = Buffer.from(SECRET_OLD, 'hex').toString('base64');
  for (const value of persisted) {
    assert.equal(value.includes(SECRET_OLD), false, `secret hex leaked: ${value}`);
    assert.equal(value.includes(base64), false, `secret base64 leaked: ${value}`);
  }
  const route = await h.repo.getRoute('gw-a');
  assert.equal(JSON.stringify(route).includes(SECRET_OLD), false);

  let error;
  try {
    await h.repo.rotateSecret('gw-a', SecureBytes.fromHex(SECRET_NEW),
      new RecordingVerifier(false));
  } catch (caught) {
    error = caught;
  }
  assert.ok(error instanceof AppError);
  assert.equal(error.code, 'SIGNATURE_INVALID');
  assert.equal(JSON.stringify(error.details).includes(SECRET_NEW), false);
  assert.equal(String(error.message).includes(SECRET_NEW), false);
});
