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
import { CreateInvitationInput as FamilyCreateInvitationInput } from '../../main/ets/service/family/FamilyModels.ets';
import {
  AcceptInvitationOptions,
  CreateInvitationInput as InviteCreateInvitationInput
} from '../../main/ets/service/invite/InviteModels.ets';
import { InviteCodec } from '../../main/ets/service/invite/InviteCodec.ets';
import { InviteService as InviteServiceImpl } from '../../main/ets/service/invite/InviteService.ets';
import { InviteServiceAdapter } from '../../main/ets/service/invite/InviteServiceAdapter.ets';
import { InvitationStatus, InviteMode, MemberRole } from '../../main/ets/model/FamilyModels.ets';
import { BytesUtil } from '../../main/ets/common/utils/BytesUtil.ets';
import { CreateProfileInput } from '../../main/ets/service/auth/AuthModels.ets';
import { HostCrypto } from './host-crypto.mjs';
import { expectRejectCode, expectThrowCode, inviteSetup,
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
    new AcceptInvitationOptions(harness.clock.nowMs())), 'INVITE_INVALID');
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
  assert.equal(session.getState().phase, 'COMPLETED');
  assert.equal(accepted.memberId, handle.memberId);
  assert.equal(session.getState().accepted.memberId, accepted.memberId);
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

  const a = await service.acceptInvitation(text,
    new AcceptInvitationOptions(harness.clock.nowMs(), code));
  const b = await service.acceptInvitation(text,
    new AcceptInvitationOptions(harness.clock.nowMs(), code));
  const c = await service.acceptInvitation(text,
    new AcceptInvitationOptions(harness.clock.nowMs(), code));

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
