/*
 * YaoCore C-13 InviteService host tests.
 * Producer: agent:implementation-engineer | Task: T-13 / wp-049-family
 * Contract: DES-A §13.1-§13.6; DES-B §23.6; ADR-003; D-009/D-013/D-022; SEC-N22.
 *
 * PUBLIC TEST DATA ONLY. Node crypto is the independent host oracle; device
 * AES/X25519/PBKDF2 runtime evidence remains BLOCKED_ON_DEVICE_RUNNER.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { newDomainHarness } from '../domain/DomainHarness.ets';
import { FamilyService } from '../../main/ets/service/family/FamilyService.ets';
import { CreateInvitationInput as FamilyCreateInvitationInput,
  FamilyProfileRef } from '../../main/ets/service/family/FamilyModels.ets';
import {
  AcceptInvitationOptions,
  CreateInvitationInput as InviteCreateInvitationInput
} from '../../main/ets/service/invite/InviteModels.ets';
import { InviteCodec } from '../../main/ets/service/invite/InviteCodec.ets';
import { InviteService as InviteServiceImpl } from '../../main/ets/service/invite/InviteService.ets';
import { InviteServiceAdapter } from '../../main/ets/service/invite/InviteServiceAdapter.ets';
import { InvitationStatus, InviteMode, MemberRole } from '../../main/ets/model/FamilyModels.ets';
import { FamilyRepository } from '../../main/ets/repository/FamilyRepository.ets';
import { BytesUtil } from '../../main/ets/common/utils/BytesUtil.ets';
import { CreateProfileInput } from '../../main/ets/service/auth/AuthModels.ets';
import { HostCrypto } from './host-crypto.mjs';
import { expectRejectCode, expectThrowCode, inviteSetup, newMemberInvite,
  GATEWAY_ID, GATEWAY_SECRET_HEX, ROLE_MEMBER, newAuth, PASSWORD
} from './family-host-helpers.mjs';

const NOW = Date.UTC(2026, 9, 17, 8, 0, 0);

async function setup() {
  const harness = await newDomainHarness(NOW);
  const env = await inviteSetup(harness);
  return { harness, ...env };
}

function familyService(harness, adapter) {
  return new FamilyService(harness.families, adapter, harness.auth, harness.routes,
    harness.clock, harness.ids, harness.logger, harness.rdb, harness.rooms, harness.gate);
}

async function restartService(harness, credentials, applications) {
  return new InviteServiceImpl(new HostCrypto(), harness.secrets, harness.families,
    harness.routes, credentials, applications, harness.clock, harness.random, harness.ids);
}

/** Accept on a brand-new member device (separate migrations-only harness). */
async function memberAccept(containerText, acceptedAtMs, code, entropy = 0) {
  const memberHarness = await newDomainHarness(NOW);
  // SyncRandom is deterministic per harness; advance it so multiple simulated
  // member devices do not generate the same CODE_KEK memberId/receipt.
  if (entropy > 0) {
    memberHarness.random.nextBytesSync(entropy);
  }
  const env = newMemberInvite(memberHarness);
  const accepted = await env.service.acceptInvitation(containerText,
    new AcceptInvitationOptions(acceptedAtMs, code));
  return { accepted, harness: memberHarness, applications: env.applications };
}

function receiptPayload(receiptText) {
  const bytes = Buffer.from(receiptText.substring('YCP1.'.length), 'base64url');
  return JSON.parse(bytes.toString('utf8'));
}

function encodeReceiptObject(payload) {
  return 'YCP1.' + Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url');
}

test('C13_joinRequest_roundTripAndStrictParsing', async () => {
  const { harness, service } = await setup();
  const container = await service.createJoinRequest('Bob');
  assert.equal(container.text.startsWith('YCR1.'), true);
  const decoded = InviteCodec.decodeJoinRequest(container.text);
  assert.equal(decoded.memberId, container.joinRequest.memberId);
  assert.equal(decoded.memberId.length, 32);
  assert.equal(decoded.displayName, 'Bob');
  assert.equal(decoded.v, 1);
  const aliases = await harness.secrets.list('yaocore.invite.join.');
  assert.deepEqual(aliases, ['yaocore.invite.join.' + container.joinRequest.memberId]);

  expectThrowCode(() => InviteCodec.decodeJoinRequest('YCR2.invalid'),
    'INVITE_JOIN_REQUEST_INVALID');
  expectThrowCode(() => InviteCodec.decodeJoinRequest(container.text + '.extra'),
    'INVITE_JOIN_REQUEST_INVALID');
  expectThrowCode(() => InviteCodec.decodeJoinRequest('YCR1.++++'),
    'INVITE_JOIN_REQUEST_INVALID');
});

test('C13_keyWrap_roundTripAppliesGatewayAndCreatesMemberReceipt', async () => {
  const { harness, family, service, applications } = await setup();
  const join = await service.createJoinRequest('Bob');
  const created = await service.createInvitation(new InviteCreateInvitationInput(
    family.familyId, ROLE_MEMBER, [], 1, 3600000, InviteMode.KEY_WRAP, join));
  await harness.families.putInvitation(created.record);
  assert.equal(created.record.memberId, join.joinRequest.memberId);
  assert.equal(created.record.maxUses, 1);

  const accepted = await service.acceptInvitation(created.container.text,
    new AcceptInvitationOptions(harness.clock.nowMs()));
  assert.equal(accepted.memberId, join.joinRequest.memberId);
  assert.equal(accepted.familyId, family.familyId);
  assert.equal(accepted.role, MemberRole.MEMBER);
  assert.equal(accepted.receipt.startsWith('YCP1.'), true);
  assert.deepEqual(accepted.appliedGatewayIds, [GATEWAY_ID]);

  const member = await harness.families.getMember(family.familyId, accepted.memberId);
  assert.equal(member.displayName, 'Bob');
  assert.equal(member.joinedVia, 'INVITE_KEY_WRAP');
  assert.equal(applications.applied.length, 1);
  assert.equal(applications.applied[0].secretHex, GATEWAY_SECRET_HEX);
  assert.deepEqual((await harness.secrets.list('yaocore.invite.join.')), []);

  const payload = InviteCodec.decodeReceipt(accepted.receipt);
  assert.equal(payload.inviteId, created.record.inviteId);
  assert.equal(payload.memberId, accepted.memberId);
  const verification = await service.verifyReceipt(accepted.receipt, created.record.inviteId);
  assert.equal(verification.valid, true);
  assert.equal(verification.memberId, accepted.memberId);

  // C-12 consumes the accepted member: a fresh profile can unlock and control.
  const auth = await newAuth(harness);
  const profile = await auth.createProfile(new CreateProfileInput(
    harness.ids.newId(), family.familyId, accepted.memberId, 'Bob', PASSWORD,
    MemberRole.MEMBER));
  const session = await auth.unlock(profile.profileId, PASSWORD);
  assert.equal(session.role, MemberRole.MEMBER);
});

test('C13_codeKek_normalizesCodeAndWrongCodeFailsClosed', async () => {
  const { harness, family, service } = await setup();
  const created = await service.createInvitation(new InviteCreateInvitationInput(
    family.familyId, ROLE_MEMBER, [], 2, 3600000, InviteMode.CODE_KEK));
  assert.match(created.code, /^[0-9A-Z]{6}$/);
  assert.equal(created.record.codeSaltHex.length, 32);
  assert.equal(created.record.kdfIterations, 120000);

  await expectRejectCode(service.acceptInvitation(created.container.text,
    new AcceptInvitationOptions(harness.clock.nowMs())), 'INVITE_CODE_INVALID');
  await expectRejectCode(service.acceptInvitation(created.container.text,
    new AcceptInvitationOptions(harness.clock.nowMs(), '000000')), 'INVITE_INVALID');

  const variant = created.code.toLowerCase().replace(/0/g, 'O').replace(/1/g, 'I');
  const accepted = await service.acceptInvitation(created.container.text,
    new AcceptInvitationOptions(harness.clock.nowMs(), variant));
  assert.equal(accepted.role, MemberRole.MEMBER);
  assert.equal(accepted.memberId.length, 32);
});

test('C13_containerRejectsAadTamperCiphertextAndUnknownVersion', async () => {
  const { harness, family, service } = await setup();
  const join = await service.createJoinRequest('Bob');
  const created = await service.createInvitation(new InviteCreateInvitationInput(
    family.familyId, ROLE_MEMBER, [], 1, 3600000, InviteMode.KEY_WRAP, join));
  const parts = created.container.text.split('.');
  const headerJson = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));

  const aadTamperedJson = { ...headerJson, familyName: 'Evil Family' };
  const aadTampered = [parts[0],
    Buffer.from(JSON.stringify(aadTamperedJson), 'utf8').toString('base64url'),
    parts[2], parts[3]].join('.');
  await expectRejectCode(service.acceptInvitation(aadTampered,
    new AcceptInvitationOptions(harness.clock.nowMs())), 'INVITE_INVALID');

  const versionJson = { ...headerJson, v: 2 };
  const versionTampered = [parts[0],
    Buffer.from(JSON.stringify(versionJson), 'utf8').toString('base64url'),
    parts[2], parts[3]].join('.');
  await expectRejectCode(service.acceptInvitation(versionTampered,
    new AcceptInvitationOptions(harness.clock.nowMs())), 'INVITE_VERSION_UNSUPPORTED');

  const body = Buffer.from(parts[3], 'base64url');
  body[0] = body[0] ^ 0x01;
  const cipherTampered = [parts[0], parts[1], parts[2], body.toString('base64url')].join('.');
  await expectRejectCode(service.acceptInvitation(cipherTampered,
    new AcceptInvitationOptions(harness.clock.nowMs())), 'INVITE_INVALID');

  const prefixTampered = 'YCI2.' + parts.slice(1).join('.');
  await expectRejectCode(service.acceptInvitation(prefixTampered,
    new AcceptInvitationOptions(harness.clock.nowMs())), 'INVITE_VERSION_UNSUPPORTED');
});

test('C13_expiredAndRevokedInvitationsFailClosed', async () => {
  const { harness, family, service } = await setup();
  const expired = await service.createInvitation(new InviteCreateInvitationInput(
    family.familyId, ROLE_MEMBER, [], 1, 1000, InviteMode.CODE_KEK));
  await expectRejectCode(service.acceptInvitation(expired.container.text,
    new AcceptInvitationOptions(harness.clock.nowMs() + 5000, expired.code)),
    'INVITE_EXPIRED');

  const created = await service.createInvitation(new InviteCreateInvitationInput(
    family.familyId, ROLE_MEMBER, [], 2, 3600000, InviteMode.CODE_KEK));
  await harness.families.putInvitation(created.record);
  const accepted = await service.acceptInvitation(created.container.text,
    new AcceptInvitationOptions(harness.clock.nowMs(), created.code));
  await service.revokeInvitation(created.record.inviteId);
  await expectRejectCode(service.verifyReceipt(accepted.receipt, created.record.inviteId),
    'INVITE_REVOKED');
});

test('C13_familyJoinSession_drivesRealInviteServiceToCompleted', async () => {
  const { harness, family, adapter } = await setup();
  const familySvc = familyService(harness, adapter);
  await familySvc.initialize();
  const session = familySvc.createJoinSession();
  const handle = await session.start('Bob');
  assert.equal(session.getState().phase, 'JOIN_REQUEST_READY');
  const created = await familySvc.createInvitationForJoinRequest(handle.text,
    new FamilyCreateInvitationInput(family.familyId, ROLE_MEMBER, [], InviteMode.KEY_WRAP,
      1, 3600000));
  const accepted = await session.submitInvitation(created.containerText);
  assert.equal(session.getState().phase, 'MEMBER_BOUND');
  assert.equal(accepted.memberId, handle.memberId);
  assert.equal(session.getState().accepted.memberId, accepted.memberId);
  harness.auth.profiles.push(new FamilyProfileRef('p-' + accepted.memberId,
    accepted.familyId, accepted.memberId));
  await harness.families.setActiveFamily(accepted.familyId);
  await session.markProfileBound();
  assert.equal(session.getState().phase, 'COMPLETED');
});

test('C13_keyWrapMaxUsesMustBeOne', async () => {
  const { harness, family, service } = await setup();
  const join = await service.createJoinRequest('Bob');
  await expectRejectCode(service.createInvitation(new InviteCreateInvitationInput(
    family.familyId, ROLE_MEMBER, [], 2, 3600000, InviteMode.KEY_WRAP, join)),
    'PROTOCOL_VALUE_OUT_OF_RANGE');
});

test('C13_receiptLedger_replayAcrossRestart_d022', async () => {
  const { harness, family, service, adapter, credentials, applications } = await setup();
  const familySvc = familyService(harness, adapter);
  await familySvc.initialize();
  const created = await familySvc.createCodeInvitation(new FamilyCreateInvitationInput(
    family.familyId, ROLE_MEMBER, [], InviteMode.CODE_KEK, 3, 3600000));
  const inviteId = created.record.inviteId;
  const code = created.code;
  const text = created.containerText;

  const a = (await memberAccept(text, harness.clock.nowMs(), code, 0)).accepted;
  const b = (await memberAccept(text, harness.clock.nowMs(), code, 1)).accepted;
  const c = (await memberAccept(text, harness.clock.nowMs(), code, 2)).accepted;

  await familySvc.importReceipt(inviteId, a.receipt);
  let record = await harness.families.getInvitation(inviteId);
  assert.equal(record.status, InvitationStatus.ACCEPTED);
  assert.equal(record.usedCount, 1);
  assert.equal(record.acceptedByMemberId, a.memberId);

  await familySvc.importReceipt(inviteId, b.receipt);
  record = await harness.families.getInvitation(inviteId);
  assert.equal(record.usedCount, 2);

  await expectRejectCode(familySvc.importReceipt(inviteId, a.receipt),
    'INVITE_RECEIPT_INVALID');
  record = await harness.families.getInvitation(inviteId);
  assert.equal(record.usedCount, 2);

  // Process restart: a new service instance over the same Asset Store must
  // still recognize the historical receipt.
  const restartedService = new InviteServiceImpl(new HostCrypto(), harness.secrets,
    harness.families, harness.routes, credentials, applications, harness.clock,
    harness.random, harness.ids);
  const restartedAdapter = new InviteServiceAdapter(restartedService);
  const restartedFamily = familyService(harness, restartedAdapter);
  await restartedFamily.initialize();
  await expectRejectCode(restartedFamily.importReceipt(inviteId, a.receipt),
    'INVITE_RECEIPT_INVALID');
  record = await harness.families.getInvitation(inviteId);
  assert.equal(record.usedCount, 2);

  await restartedFamily.importReceipt(inviteId, c.receipt);
  record = await harness.families.getInvitation(inviteId);
  assert.equal(record.usedCount, 3);
  await expectRejectCode(restartedFamily.importReceipt(inviteId, c.receipt),
    'INVITE_MAX_USES');
});

test('C13_accept_newDevice_importsFamilyWithoutPreSeededRow', async () => {
  const adminHarness = await newDomainHarness(NOW);
  const adminEnv = await inviteSetup(adminHarness);
  const adminSvc = familyService(adminHarness, adminEnv.adapter);
  await adminSvc.initialize();
  const memberHarness = await newDomainHarness(NOW);
  const memberEnv = newMemberInvite(memberHarness);
  const join = await memberEnv.service.createJoinRequest('Bob');
  const created = await adminSvc.createInvitationForJoinRequest(join.text,
    new FamilyCreateInvitationInput(adminEnv.family.familyId, ROLE_MEMBER, [],
      InviteMode.KEY_WRAP, 1, 3600000));

  const accepted = await memberEnv.service.acceptInvitation(created.containerText,
    new AcceptInvitationOptions(memberHarness.clock.nowMs()));
  assert.equal(accepted.memberId, join.joinRequest.memberId);
  const imported = await memberHarness.families.getFamily(adminEnv.family.familyId);
  assert.notEqual(imported, undefined);
  assert.equal(imported.familyName, adminEnv.family.familyName);
  assert.equal(imported.ownerMemberId, FamilyRepository.IMPORTED_FAMILY_OWNER_PLACEHOLDER);
  assert.equal((await memberHarness.families.listFamilies()).length, 1);
  assert.equal(await memberHarness.families.getActiveFamily(), undefined);
  const members = await memberHarness.families.listMembers(adminEnv.family.familyId);
  assert.deepEqual(members.map((member) => member.memberId), [join.joinRequest.memberId]);
  assert.equal(members[0].role, ROLE_MEMBER);
  assert.equal(memberEnv.applications.applied.length, 1);
  // The one-time join key is gone; a new device never needed a pre-seeded family.
  await expectRejectCode(memberEnv.service.acceptInvitation(created.containerText,
    new AcceptInvitationOptions(memberHarness.clock.nowMs())), 'INVITE_KEY_MISSING');
});

test('C13_importFamily_idempotentAndKeepsNameOnSameIdOnly', async () => {
  const harness = await newDomainHarness(NOW);
  const familyId = harness.ids.newId();
  const first = await harness.families.importFamily(familyId, 'Home');
  assert.equal(first.familyId, familyId);
  assert.equal(first.familyName, 'Home');
  assert.equal(first.ownerMemberId, FamilyRepository.IMPORTED_FAMILY_OWNER_PLACEHOLDER);
  assert.deepEqual(first.gatewayIds, []);
  assert.equal((await harness.families.listMembers(familyId)).length, 0);

  const repeated = await harness.families.importFamily(familyId, 'Renamed');
  assert.equal(repeated.familyName, 'Home');
  assert.equal(repeated.ownerMemberId, FamilyRepository.IMPORTED_FAMILY_OWNER_PLACEHOLDER);
  assert.equal(repeated.createdAt, first.createdAt);
  assert.equal((await harness.families.listFamilies()).length, 1);

  const otherId = harness.ids.newId();
  await harness.families.importFamily(otherId, 'Home');
  assert.equal((await harness.families.listFamilies()).length, 2);
  assert.equal((await harness.families.listMembers(otherId)).length, 0);
});

test('C13_codeKek_sameDeviceAcceptsInviteOnlyOnceAcrossRestart', async () => {
  const { harness, family, service, adapter, credentials, applications } = await setup();
  const familySvc = familyService(harness, adapter);
  await familySvc.initialize();
  const created = await familySvc.createCodeInvitation(new FamilyCreateInvitationInput(
    family.familyId, ROLE_MEMBER, [], InviteMode.CODE_KEK, 3, 3600000));
  const options = new AcceptInvitationOptions(harness.clock.nowMs(), created.code);
  const accepted = await service.acceptInvitation(created.containerText, options);
  assert.equal(accepted.memberId.length, 32);
  const markers = await harness.secrets.list('yaocore.invite.accepted.');
  assert.deepEqual(markers, ['yaocore.invite.accepted.' + created.record.inviteId]);
  assert.equal((await harness.families.listMembers(family.familyId)).length, 2);

  await expectRejectCode(service.acceptInvitation(created.containerText,
    new AcceptInvitationOptions(harness.clock.nowMs(), created.code)), 'INVITE_INVALID');

  const restarted = await restartService(harness, credentials, applications);
  await expectRejectCode(restarted.acceptInvitation(created.containerText,
    new AcceptInvitationOptions(harness.clock.nowMs(), created.code)), 'INVITE_INVALID');
  // No duplicate member row was created by the rejected attempts.
  assert.equal((await harness.families.listMembers(family.familyId)).length, 2);
});

test('C13_keyWrap_joinKeyDeleteFailureStillCannotBeAcceptedTwice', async () => {
  const { harness, family, service, credentials, applications } = await setup();
  const join = await service.createJoinRequest('Bob');
  const created = await service.createInvitation(new InviteCreateInvitationInput(
    family.familyId, ROLE_MEMBER, [], 1, 3600000, InviteMode.KEY_WRAP, join));
  await harness.families.putInvitation(created.record);
  const joinAlias = 'yaocore.invite.join.' + join.joinRequest.memberId;
  const containerText = created.container.text;
  harness.secrets.failRemove = true;
  const accepted = await service.acceptInvitation(containerText,
    new AcceptInvitationOptions(harness.clock.nowMs()));
  assert.equal(accepted.memberId, join.joinRequest.memberId);
  assert.equal(harness.secrets.has(joinAlias), true);
  harness.secrets.failRemove = false;

  await expectRejectCode(service.acceptInvitation(containerText,
    new AcceptInvitationOptions(harness.clock.nowMs())), 'INVITE_INVALID');
  const restarted = await restartService(harness, credentials, applications);
  await expectRejectCode(restarted.acceptInvitation(containerText,
    new AcceptInvitationOptions(harness.clock.nowMs())), 'INVITE_INVALID');
});

test('C13_receipt_variantReplayIsRejectedWithoutConsumingUse', async () => {
  const { harness, family, service, adapter } = await setup();
  const familySvc = familyService(harness, adapter);
  await familySvc.initialize();
  const created = await familySvc.createCodeInvitation(new FamilyCreateInvitationInput(
    family.familyId, ROLE_MEMBER, [], InviteMode.CODE_KEK, 4, 3600000));
  const inviteId = created.record.inviteId;
  const a = (await memberAccept(created.containerText, harness.clock.nowMs(),
    created.code, 0)).accepted;
  const b = (await memberAccept(created.containerText, harness.clock.nowMs(),
    created.code, 1)).accepted;
  await familySvc.importReceipt(inviteId, a.receipt);
  await familySvc.importReceipt(inviteId, b.receipt);
  let record = await harness.families.getInvitation(inviteId);
  assert.equal(record.usedCount, 2);

  const payload = receiptPayload(a.receipt);
  // Same fields and MAC, different JSON key order: not a new receipt.
  const variant = encodeReceiptObject({
    v: payload.v,
    inviteId: payload.inviteId,
    mac: payload.mac,
    memberId: payload.memberId,
    acceptedAt: payload.acceptedAt
  });
  assert.notEqual(variant, a.receipt);
  await expectRejectCode(familySvc.importReceipt(inviteId, variant), 'INVITE_RECEIPT_INVALID');
  record = await harness.families.getInvitation(inviteId);
  assert.equal(record.usedCount, 2);
  assert.equal((await harness.secrets.list('yaocore.invite.receipt.')).length, 2);

  // The original historical receipt is still recognized as a replay.
  await expectRejectCode(familySvc.importReceipt(inviteId, a.receipt),
    'INVITE_RECEIPT_INVALID');
  record = await harness.families.getInvitation(inviteId);
  assert.equal(record.usedCount, 2);
  const c = (await memberAccept(created.containerText, harness.clock.nowMs(),
    created.code, 2)).accepted;
  await familySvc.importReceipt(inviteId, c.receipt);
  record = await harness.families.getInvitation(inviteId);
  assert.equal(record.usedCount, 3);
});

test('C13_receipt_negativeMatrixDoesNotWriteLedger', async () => {
  const { harness, family, service, adapter } = await setup();
  const familySvc = familyService(harness, adapter);
  await familySvc.initialize();
  const created = await familySvc.createCodeInvitation(new FamilyCreateInvitationInput(
    family.familyId, ROLE_MEMBER, [], InviteMode.CODE_KEK, 2, 3600000));
  const inviteId = created.record.inviteId;
  const accepted = (await memberAccept(created.containerText, harness.clock.nowMs(),
    created.code)).accepted;
  const canonical = accepted.receipt;
  assert.equal(InviteCodec.encodeReceipt(InviteCodec.decodeReceipt(canonical)), canonical);
  const payload = receiptPayload(canonical);
  const wrongInviteId = harness.ids.newId();

  const wrongMac = encodeReceiptObject({ ...payload, mac: '00'.repeat(32) });
  const unknownVersion = encodeReceiptObject({ ...payload, v: 2 });
  const extraField = encodeReceiptObject({ ...payload, extra: 'x' });
  const wrongInvite = encodeReceiptObject({ ...payload, inviteId: wrongInviteId });
  const whiteSpace = 'YCP1.' + Buffer.from(JSON.stringify(payload, null, 2), 'utf8')
    .toString('base64url');
  const payloadJson = JSON.stringify(payload);
  const duplicateKey = 'YCP1.' + Buffer.from(payloadJson.slice(0, -1) + ',"v":1}',
    'utf8').toString('base64url');

  const negatives = [
    wrongMac,
    unknownVersion,
    extraField,
    wrongInvite,
    whiteSpace,
    duplicateKey,
    canonical + '.extra',
    'YCP1.',
    'YCP2.' + canonical.substring('YCP1.'.length),
    payload.mac,
    'YCP1.' + Buffer.from('not-json', 'utf8').toString('base64url')
  ];
  for (let index = 0; index < negatives.length; index++) {
    await expectRejectCode(service.verifyReceipt(negatives[index], inviteId),
      'INVITE_RECEIPT_INVALID');
  }
  await expectRejectCode(service.verifyReceipt(canonical, wrongInviteId),
    'INVITE_RECEIPT_INVALID');
  assert.equal((await harness.secrets.list('yaocore.invite.receipt.')).length, 0);

  const verification = await service.verifyReceipt(canonical, inviteId);
  assert.equal(verification.valid, true);
  assert.equal((await harness.secrets.list('yaocore.invite.receipt.')).length, 1);
});

test('C13_receiptLedger_c08FailureCompensatesAndRetrySucceeds', async () => {
  const { harness, family, adapter } = await setup();
  const familySvc = familyService(harness, adapter);
  await familySvc.initialize();
  const created = await familySvc.createCodeInvitation(new FamilyCreateInvitationInput(
    family.familyId, ROLE_MEMBER, [], InviteMode.CODE_KEK, 2, 3600000));
  const inviteId = created.record.inviteId;
  const accepted = (await memberAccept(created.containerText, harness.clock.nowMs(),
    created.code)).accepted;

  harness.rdb.failNextExecuteContaining = 'UPDATE invitation SET status';
  await expectRejectCode(familySvc.importReceipt(inviteId, accepted.receipt),
    'STORAGE_RDB_ERROR');
  let record = await harness.families.getInvitation(inviteId);
  assert.equal(record.usedCount, 0);
  assert.equal((await harness.secrets.list('yaocore.invite.receipt.')).length, 0);
  assert.equal(await harness.families.getMember(family.familyId, accepted.memberId), undefined);

  // F-05 compensation released the reservation: the same receipt can retry.
  const imported = await familySvc.importReceipt(inviteId, accepted.receipt);
  assert.equal(imported.memberId, accepted.memberId);
  record = await harness.families.getInvitation(inviteId);
  assert.equal(record.usedCount, 1);
  assert.equal((await harness.secrets.list('yaocore.invite.receipt.')).length, 1);
  assert.notEqual(await harness.families.getMember(family.familyId, accepted.memberId),
    undefined);

  await expectRejectCode(familySvc.importReceipt(inviteId, accepted.receipt),
    'INVITE_RECEIPT_INVALID');
  record = await harness.families.getInvitation(inviteId);
  assert.equal(record.usedCount, 1);
});

test('C13_revoke_removesAdminSeedAlias', async () => {
  const { harness, family, adapter } = await setup();
  const familySvc = familyService(harness, adapter);
  await familySvc.initialize();
  const created = await familySvc.createCodeInvitation(new FamilyCreateInvitationInput(
    family.familyId, ROLE_MEMBER, [], InviteMode.CODE_KEK, 2, 3600000));
  const seedAlias = created.record.seedAlias;
  assert.equal(harness.secrets.has(seedAlias), true);
  await familySvc.revokeInvitation(created.record.inviteId);
  assert.equal(harness.secrets.has(seedAlias), false);
  await expectRejectCode(familySvc.importReceipt(created.record.inviteId,
    'YCP1.not-a-receipt'), 'INVITE_REVOKED');
});

test('C13_expireInvitations_marksAcceptedMultiUseAsExpired', async () => {
  const { harness, family, service, adapter } = await setup();
  const familySvc = familyService(harness, adapter);
  await familySvc.initialize();
  const created = await familySvc.createCodeInvitation(new FamilyCreateInvitationInput(
    family.familyId, ROLE_MEMBER, [], InviteMode.CODE_KEK, 2, 3000));
  const accepted = await service.acceptInvitation(created.containerText,
    new AcceptInvitationOptions(harness.clock.nowMs(), created.code));
  await familySvc.importReceipt(created.record.inviteId, accepted.receipt);
  let record = await harness.families.getInvitation(created.record.inviteId);
  assert.equal(record.status, InvitationStatus.ACCEPTED);
  assert.equal(record.usedCount, 1);

  harness.advance(5000);
  const expired = await familySvc.expireInvitations(family.familyId, harness.clock.nowMs());
  assert.equal(expired, 1);
  record = await harness.families.getInvitation(created.record.inviteId);
  assert.equal(record.status, InvitationStatus.EXPIRED);
  await expectRejectCode(service.verifyReceipt(accepted.receipt, created.record.inviteId),
    'INVITE_EXPIRED');
});

test('C13_rotationGuidanceAndDiscardAreLocalOnly', async () => {
  const { harness, service, applications } = await setup();
  const plan = await service.rotateGatewaySecret(GATEWAY_ID);
  assert.equal(plan.gatewayId, GATEWAY_ID);
  assert.deepEqual(plan.steps, ['invite.rotation.step.reprovision',
    'invite.rotation.step.verify']);
  assert.equal(applications.applied.length, 0);
  await expectRejectCode(service.rotateGatewaySecret('gw-unknown'), 'GATEWAY_NOT_BOUND');

  const join = await service.createJoinRequest();
  assert.equal((await harness.secrets.list('yaocore.invite.join.')).length, 1);
  await service.discardJoinRequest(join.joinRequest.memberId);
  assert.equal((await harness.secrets.list('yaocore.invite.join.')).length, 0);
});

test('C13_ledgerStoresOnlyDomainSeparatedHash', async () => {
  const { harness, family, service } = await setup();
  const created = await service.createInvitation(new InviteCreateInvitationInput(
    family.familyId, ROLE_MEMBER, [], 1, 3600000, InviteMode.CODE_KEK));
  await harness.families.putInvitation(created.record);
  const accepted = await service.acceptInvitation(created.container.text,
    new AcceptInvitationOptions(harness.clock.nowMs(), created.code));
  await service.verifyReceipt(accepted.receipt, created.record.inviteId);
  const aliases = await harness.secrets.list('yaocore.invite.receipt.');
  assert.equal(aliases.length, 1);
  const stored = await harness.secrets.withSecret(aliases[0],
    async (bytes) => BytesUtil.fromUtf8(bytes));
  assert.equal(stored.includes(accepted.receipt), false);
  assert.equal(stored.includes('YCP1.'), false);
  assert.equal(stored.includes('"receiptHash"'), true);
  assert.equal(stored.includes('"inviteId"'), true);
});
