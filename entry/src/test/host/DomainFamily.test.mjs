/*
 * YaoCore T-09 C-08 FamilyRepository / FamilyService host tests.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §3.1-§3.4; ADR-003; D-010/D-013; D-019 host layer.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { newDomainHarness } from '../domain/DomainHarness.ets';
import { FamilyService } from '../../main/ets/service/family/FamilyService.ets';
import {
  CreateInvitationInput,
  FamilyContactSyncState,
  FamilyJoinPhase,
  FamilyProfileRef,
  InvitationReceiptState
} from '../../main/ets/service/family/FamilyModels.ets';
import { FamilyRbac, FamilyCapability } from '../../main/ets/service/family/FamilyRbac.ets';
import {
  FamilyMember,
  InvitationStatus,
  InviteMode,
  MemberRole,
  MemberStatus
} from '../../main/ets/model/FamilyModels.ets';
import { GATEWAY_ID, T0 } from './domain-helpers.mjs';

const NOW = Date.UTC(2026, 9, 17, 8, 0, 0);
const LATER = '20261017T090000Z';

async function setup() {
  const h = await newDomainHarness(NOW);
  h.routes.add(GATEWAY_ID, 'unused-family');
  const service = new FamilyService(h.families, h.invites, h.auth, h.routes, h.clock, h.ids,
    h.logger, h.rdb, h.rooms, h.gate);
  await service.initialize();
  return { h, service };
}

async function createFamily(service) {
  return service.createFamily('Home', 'Alice');
}

async function addMember(h, familyId, memberId, role, name, options = {}) {
  const member = new FamilyMember(memberId, familyId, memberId, name, role,
    options.status === undefined ? MemberStatus.ACTIVE : options.status,
    options.joinedAt === undefined ? T0 : options.joinedAt,
    options.allowedRoomIds === undefined ? [] : options.allowedRoomIds,
    options.expiresAt);
  await h.families.upsertMember(member);
  return member;
}

test('T09_C08_createFamilyCreatesAdminAndActivatesFirstFamily', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const members = await h.families.listMembers(family.familyId);
  assert.equal(members.length, 1);
  assert.equal(members[0].memberId, family.ownerMemberId);
  assert.equal(members[0].role, MemberRole.ADMIN);
  assert.equal(members[0].status, MemberStatus.ACTIVE);
  assert.equal(members[0].displayName, 'Alice');
  const active = await service.getActiveFamily();
  assert.equal(active.familyId, family.familyId);
  const views = await service.listMemberViews(family.familyId);
  assert.equal(views[0].syncState, FamilyContactSyncState.NEVER);
  assert.equal(views[0].roleI18nKey, 'member.role.admin');
  assert.equal((await service.listFamilies()).length, 1);
});

test('T09_C08_switchFamilyLocksSessionAndRequiresTargetProfile', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  await assert.rejects(service.switchFamily(family.familyId),
    (error) => error.code === 'AUTH_PROFILE_NOT_FOUND');
  h.auth.profiles.push(new FamilyProfileRef('profile-1', family.familyId));
  const result = await service.switchFamily(family.familyId);
  assert.equal(result.requiresUnlock, true);
  assert.equal(result.activeProfileId, 'profile-1');
  assert.equal(h.auth.lockAllCalls, 2);
  assert.equal(h.preferences.values.get('app.activeFamilyId'), family.familyId);
});

test('T09_C08_rbacMatrixAndActorEnforcement', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const member = await addMember(h, family.familyId, 'member-2', MemberRole.MEMBER, 'Bob');
  const guest = await addMember(h, family.familyId, 'guest-2', MemberRole.GUEST, 'Guest',
    { allowedRoomIds: ['123e4567-e89b-12d3-a456-000000000001'], expiresAt: LATER });

  assert.equal(FamilyRbac.allows(MemberRole.ADMIN, FamilyCapability.MANAGE_FAMILY), true);
  assert.equal(FamilyRbac.allows(MemberRole.MEMBER, FamilyCapability.MANAGE_FAMILY), false);
  assert.equal(FamilyRbac.allows(MemberRole.GUEST, FamilyCapability.INVITE_MEMBERS), false);
  assert.equal(FamilyRbac.allows(MemberRole.MEMBER, FamilyCapability.CONTROL_DEVICE), true);
  assert.equal(FamilyRbac.allows(MemberRole.GUEST, FamilyCapability.CONTROL_DEVICE), true);
  assert.equal(FamilyRbac.canControlRoom(MemberRole.GUEST, 'room-a',
    ['123e4567-e89b-12d3-a456-000000000001']), false);
  assert.equal(FamilyRbac.canControlRoom(MemberRole.GUEST,
    '123e4567-e89b-12d3-a456-000000000001',
    ['123e4567-e89b-12d3-a456-000000000001']), true);

  await assert.rejects(service.removeMember(family.familyId, member.memberId, member.memberId),
    (error) => error.code === 'AUTH_RBAC_DENIED');
  await assert.rejects(service.updateFamilyName(family.familyId, 'Nope', member.memberId),
    (error) => error.code === 'AUTH_RBAC_DENIED');
  await assert.rejects(service.createCodeInvitation(new CreateInvitationInput(
    family.familyId, MemberRole.MEMBER, [], InviteMode.CODE_KEK), guest.memberId),
  (error) => error.code === 'AUTH_RBAC_DENIED');
});

test('T09_C08_lastAdminCannotBeRemovedDemotedOrLeave', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  await assert.rejects(service.removeMember(family.familyId, family.ownerMemberId),
    (error) => error.code === 'AUTH_RBAC_DENIED');
  await assert.rejects(service.changeMemberRole(family.familyId, family.ownerMemberId,
    MemberRole.MEMBER), (error) => error.code === 'AUTH_RBAC_DENIED');
  await assert.rejects(service.leaveFamily(family.familyId, family.ownerMemberId),
    (error) => error.code === 'AUTH_RBAC_DENIED');
  const admin = await h.families.getMember(family.familyId, family.ownerMemberId);
  assert.equal(admin.role, MemberRole.ADMIN);
});

test('T09_C08_transferAdminUpdatesOwnerAndInvalidatesBothSessions', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const second = await addMember(h, family.familyId, 'member-2', MemberRole.MEMBER, 'Bob');
  await service.transferAdmin(family.familyId, family.ownerMemberId, second.memberId);
  const owner = await h.families.getMember(family.familyId, family.ownerMemberId);
  const promoted = await h.families.getMember(family.familyId, second.memberId);
  const stored = await h.families.getFamily(family.familyId);
  assert.equal(owner.role, MemberRole.MEMBER);
  assert.equal(promoted.role, MemberRole.ADMIN);
  assert.equal(stored.ownerMemberId, second.memberId);
  assert.ok(h.auth.invalidated.includes(family.ownerMemberId));
  assert.ok(h.auth.invalidated.includes(second.memberId));
  assert.equal(h.control.commands.length, 0);
});

test('T09_C08_guestExpiryFreezesAndExplicitExtendReactivates', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const guest = await addMember(h, family.familyId, 'guest-2', MemberRole.GUEST, 'Guest',
    { allowedRoomIds: ['123e4567-e89b-12d3-a456-000000000001'],
      expiresAt: '20261017T080100Z' });
  const expired = await service.expireGuests(family.familyId, NOW + 120000);
  assert.equal(expired.expiredCount, 1);
  assert.deepEqual(expired.expiredMemberIds, ['guest-2']);
  assert.ok(h.auth.invalidated.includes('guest-2'));
  let stored = await h.families.getMember(family.familyId, guest.memberId);
  assert.equal(stored.status, MemberStatus.EXPIRED);
  // Expiry does not auto-reactivate.
  await service.expireGuests(family.familyId, NOW + 120000);
  stored = await h.families.getMember(family.familyId, guest.memberId);
  assert.equal(stored.status, MemberStatus.EXPIRED);
  const extended = await service.extendGuest(family.familyId, guest.memberId, LATER);
  assert.equal(extended.changed, true);
  stored = await h.families.getMember(family.familyId, guest.memberId);
  assert.equal(stored.status, MemberStatus.ACTIVE);
  assert.equal(stored.expiresAt, LATER);
  await assert.rejects(service.extendGuest(family.familyId, guest.memberId,
    '20200101T000000Z'), (error) => error.code === 'PROTOCOL_VALUE_OUT_OF_RANGE');
});

test('T09_C08_invitationReceiptStateMachineAndWeakModeView', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const input = new CreateInvitationInput(family.familyId, MemberRole.MEMBER, [],
    InviteMode.KEY_WRAP, 1, 86400000);
  const created = await service.createInvitationForJoinRequest('YCR1.fake.join', input);
  assert.equal(created.record.status, InvitationStatus.PENDING);
  assert.equal(h.invites.createRequests[0].joinRequestText, 'YCR1.fake.join');
  h.invites.receiptMemberId = 'member-9';
  const accepted = await service.importReceipt(created.record.inviteId, 'receipt-ok');
  assert.equal(accepted.memberId, 'member-9');
  const stored = await h.families.getInvitation(created.record.inviteId);
  assert.equal(stored.status, InvitationStatus.ACCEPTED);
  assert.equal(stored.usedCount, 1);
  assert.equal(stored.acceptedByMemberId, 'member-9');
  assert.equal(stored.receipt, 'receipt-ok');
  const member = await h.families.getMember(family.familyId, 'member-9');
  assert.equal(member.status, MemberStatus.ACTIVE);
  await assert.rejects(service.importReceipt(created.record.inviteId, 'receipt-again'),
    (error) => error.code === 'INVITE_MAX_USES');
  assert.equal((await h.families.listMembers(family.familyId)).length, 2);

  const weak = await service.createCodeInvitation(new CreateInvitationInput(
    family.familyId, MemberRole.MEMBER, [], InviteMode.CODE_KEK, 2, 86400000));
  assert.equal(weak.code, 'ABC123');
  const views = await service.listInvitationViews(family.familyId);
  const weakView = views.find((view) => view.record.inviteId === weak.record.inviteId);
  assert.equal(weakView.isWeakMode, true);
  assert.equal(weakView.receiptState, InvitationReceiptState.PENDING);
  assert.equal(weakView.modeI18nKey, 'invite.mode.code_kek');
});

test('T09_C08_revokeAndExpireInvitations', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const created = await service.createCodeInvitation(new CreateInvitationInput(
    family.familyId, MemberRole.MEMBER, [], InviteMode.CODE_KEK));
  await service.revokeInvitation(created.record.inviteId);
  assert.deepEqual(h.invites.revoked, [created.record.inviteId]);
  let stored = await h.families.getInvitation(created.record.inviteId);
  assert.equal(stored.status, InvitationStatus.REVOKED);
  await service.revokeInvitation(created.record.inviteId);
  stored = await h.families.getInvitation(created.record.inviteId);
  assert.equal(stored.status, InvitationStatus.REVOKED);

  const expiring = await service.createCodeInvitation(new CreateInvitationInput(
    family.familyId, MemberRole.MEMBER, [], InviteMode.CODE_KEK, 1, 1000));
  const count = await service.expireInvitations(family.familyId, NOW + 2000);
  assert.equal(count, 1);
  stored = await h.families.getInvitation(expiring.record.inviteId);
  assert.equal(stored.status, InvitationStatus.EXPIRED);
});

test('T09_C08_invitationValidationNegativeCases', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const before = h.invites.createRequests.length;
  await assert.rejects(service.createInvitationForJoinRequest('not-ycr1',
    new CreateInvitationInput(family.familyId, MemberRole.MEMBER, [], InviteMode.KEY_WRAP)),
  (error) => error.code === 'INVITE_JOIN_REQUEST_INVALID');
  await assert.rejects(service.createInvitationForJoinRequest('YCR1.fake',
    new CreateInvitationInput(family.familyId, MemberRole.ADMIN, [], InviteMode.KEY_WRAP)),
  (error) => error.code === 'PROTOCOL_VALUE_OUT_OF_RANGE');
  await assert.rejects(service.createCodeInvitation(new CreateInvitationInput(
    family.familyId, MemberRole.GUEST, [], InviteMode.CODE_KEK)),
  (error) => error.code === 'PROTOCOL_VALUE_OUT_OF_RANGE');
  await assert.rejects(service.createInvitationForJoinRequest('YCR1.fake',
    new CreateInvitationInput(family.familyId, MemberRole.MEMBER, [], InviteMode.CODE_KEK)),
  (error) => error.code === 'PROTOCOL_VALUE_OUT_OF_RANGE');
  await assert.rejects(service.createCodeInvitation(new CreateInvitationInput(
    family.familyId, MemberRole.MEMBER, [], InviteMode.CODE_KEK, 0)),
  (error) => error.code === 'PROTOCOL_VALUE_OUT_OF_RANGE');
  await assert.rejects(service.createCodeInvitation(new CreateInvitationInput(
    family.familyId, MemberRole.MEMBER, [], InviteMode.CODE_KEK, 1, 0)),
  (error) => error.code === 'PROTOCOL_VALUE_OUT_OF_RANGE');
  await assert.rejects(service.createCodeInvitation(new CreateInvitationInput(
    family.familyId, MemberRole.GUEST, ['not-a-uuid'], InviteMode.CODE_KEK, 1, 1000)),
  (error) => error.code === 'PROTOCOL_INVALID_IDENTIFIER');
  // No C-13 side effect (seed alias/creation) may happen before validation.
  assert.equal(h.invites.createRequests.length, before);
});

test('T09_C08_revokedReceiptLeavesNoActiveMember', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const created = await service.createInvitationForJoinRequest('YCR1.fake.join',
    new CreateInvitationInput(family.familyId, MemberRole.MEMBER, [], InviteMode.KEY_WRAP));
  await service.revokeInvitation(created.record.inviteId);
  h.invites.receiptMemberId = 'member-revoked';
  await assert.rejects(service.importReceipt(created.record.inviteId, 'receipt-revoked'),
    (error) => error.code === 'INVITE_REVOKED');
  assert.equal(await h.families.getMember(family.familyId, 'member-revoked'), undefined);
  const stored = await h.families.getInvitation(created.record.inviteId);
  assert.equal(stored.status, InvitationStatus.REVOKED);
  assert.equal(stored.usedCount, 0);
});

test('T09_C08_expiredReceiptLeavesNoActiveMember', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const created = await service.createCodeInvitation(new CreateInvitationInput(
    family.familyId, MemberRole.MEMBER, [], InviteMode.CODE_KEK, 1, 1000));
  h.clock.value += 2000;
  h.invites.receiptMemberId = 'member-expired';
  await assert.rejects(service.importReceipt(created.record.inviteId, 'receipt-expired'),
    (error) => error.code === 'INVITE_EXPIRED');
  assert.equal(await h.families.getMember(family.familyId, 'member-expired'), undefined);
  assert.equal(h.invites.verifyCalls, 0);
  const stored = await h.families.getInvitation(created.record.inviteId);
  assert.equal(stored.usedCount, 0);
});

test('T09_C08_receiptInviteMismatchIsRejectedBeforeMemberWrite', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const created = await service.createCodeInvitation(new CreateInvitationInput(
    family.familyId, MemberRole.MEMBER, [], InviteMode.CODE_KEK, 1, 10000));
  h.invites.receiptMemberId = 'member-mismatch';
  h.invites.receiptInviteId = 'other-invite';
  await assert.rejects(service.importReceipt(created.record.inviteId, 'receipt-mismatch'),
    (error) => error.code === 'INVITE_RECEIPT_INVALID');
  assert.equal(await h.families.getMember(family.familyId, 'member-mismatch'), undefined);
});

test('T09_C08_codeKekMultipleReceiptsFollowD022', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const created = await service.createCodeInvitation(new CreateInvitationInput(
    family.familyId, MemberRole.MEMBER, [], InviteMode.CODE_KEK, 2, 86400000));
  h.invites.receiptMemberId = 'member-a';
  const first = await service.importReceipt(created.record.inviteId, 'receipt-a');
  assert.equal(first.memberId, 'member-a');
  let stored = await h.families.getInvitation(created.record.inviteId);
  assert.equal(stored.status, InvitationStatus.ACCEPTED);
  assert.equal(stored.usedCount, 1);
  // D-022: ACCEPTED is a receipt record, not a terminal state.
  h.invites.receiptMemberId = 'member-b';
  const second = await service.importReceipt(created.record.inviteId, 'receipt-b');
  assert.equal(second.memberId, 'member-b');
  stored = await h.families.getInvitation(created.record.inviteId);
  assert.equal(stored.usedCount, 2);
  assert.equal(stored.acceptedByMemberId, 'member-b');
  const memberA = await h.families.getMember(family.familyId, 'member-a');
  const memberB = await h.families.getMember(family.familyId, 'member-b');
  assert.equal(memberA.status, MemberStatus.ACTIVE);
  assert.equal(memberB.status, MemberStatus.ACTIVE);
  h.invites.receiptMemberId = 'member-c';
  await assert.rejects(service.importReceipt(created.record.inviteId, 'receipt-c'),
    (error) => error.code === 'INVITE_MAX_USES');
  assert.equal(await h.families.getMember(family.familyId, 'member-c'), undefined);
});

test('T09_C08_sameReceiptReplayDoesNotConsumeUse', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const created = await service.createCodeInvitation(new CreateInvitationInput(
    family.familyId, MemberRole.MEMBER, [], InviteMode.CODE_KEK, 2, 86400000));
  h.invites.receiptMemberId = 'member-a';
  const first = await service.importReceipt(created.record.inviteId, 'receipt-a');
  assert.equal(first.memberId, 'member-a');
  let stored = await h.families.getInvitation(created.record.inviteId);
  assert.equal(stored.usedCount, 1);
  assert.equal((await h.families.listMembers(family.familyId)).length, 2);

  // DES-B §3.4: the same receipt is accepted once. Replaying it (even on a
  // multi-use CODE_KEK invitation) must not consume another use or add a row.
  await assert.rejects(service.importReceipt(created.record.inviteId, 'receipt-a'),
    (error) => error.code === 'INVITE_RECEIPT_INVALID');
  stored = await h.families.getInvitation(created.record.inviteId);
  assert.equal(stored.usedCount, 1);
  assert.equal((await h.families.listMembers(family.familyId)).length, 2);

  // A second receipt for the same member is the same acceptance, not a new use.
  await assert.rejects(service.importReceipt(created.record.inviteId, 'receipt-a-retry'),
    (error) => error.code === 'INVITE_RECEIPT_INVALID');
  stored = await h.families.getInvitation(created.record.inviteId);
  assert.equal(stored.usedCount, 1);
  assert.equal((await h.families.listMembers(family.familyId)).length, 2);

  // A different receipt for a different member still consumes a use (D-022).
  h.invites.receiptMemberId = 'member-b';
  const second = await service.importReceipt(created.record.inviteId, 'receipt-b');
  assert.equal(second.memberId, 'member-b');
  stored = await h.families.getInvitation(created.record.inviteId);
  assert.equal(stored.usedCount, 2);
  assert.equal(stored.acceptedByMemberId, 'member-b');
  assert.equal((await h.families.listMembers(family.familyId)).length, 3);
  assert.equal((await h.families.getMember(family.familyId, 'member-a')).status,
    MemberStatus.ACTIVE);
  assert.equal((await h.families.getMember(family.familyId, 'member-b')).status,
    MemberStatus.ACTIVE);
});

test('T09_C08_keyWrapReceiptReplayIsRejectedWithoutExtraConsumption', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const created = await service.createInvitationForJoinRequest('YCR1.fake.join',
    new CreateInvitationInput(family.familyId, MemberRole.MEMBER, [], InviteMode.KEY_WRAP));
  h.invites.receiptMemberId = 'member-a';
  await service.importReceipt(created.record.inviteId, 'receipt-a');
  // KEY_WRAP maxUses=1, so the exhausted-invitation check keeps the closed
  // R-01/D-022 INVITE_MAX_USES precedence; either way no extra use is consumed.
  await assert.rejects(service.importReceipt(created.record.inviteId, 'receipt-a'),
    (error) => error.code === 'INVITE_MAX_USES');
  const stored = await h.families.getInvitation(created.record.inviteId);
  assert.equal(stored.usedCount, 1);
  assert.equal((await h.families.listMembers(family.familyId)).length, 2);
  assert.equal((await h.families.getMember(family.familyId, 'member-b')), undefined);
});

test('T09_C08_acceptedCodeKekCanStillBeRevokedWhileUsesRemain', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const created = await service.createCodeInvitation(new CreateInvitationInput(
    family.familyId, MemberRole.MEMBER, [], InviteMode.CODE_KEK, 2, 86400000));
  h.invites.receiptMemberId = 'member-a';
  await service.importReceipt(created.record.inviteId, 'receipt-a');
  await service.revokeInvitation(created.record.inviteId);
  const stored = await h.families.getInvitation(created.record.inviteId);
  assert.equal(stored.status, InvitationStatus.REVOKED);
  h.invites.receiptMemberId = 'member-b';
  await assert.rejects(service.importReceipt(created.record.inviteId, 'receipt-b'),
    (error) => error.code === 'INVITE_REVOKED');
  assert.equal(await h.families.getMember(family.familyId, 'member-b'), undefined);
});

test('T09_C08_joinSessionKeyWrapCompletesAndWritesMember', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  h.invites.acceptedFamilyId = family.familyId;
  h.invites.acceptedMemberId = 'member-join';
  h.invites.acceptedRole = MemberRole.MEMBER;
  const session = service.createJoinSession();
  const handle = await session.start('Joiner');
  assert.equal(session.getState().phase, FamilyJoinPhase.JOIN_REQUEST_READY);
  session.waitForInvitation();
  assert.equal(session.getState().phase, FamilyJoinPhase.WAITING_FOR_INVITATION);
  const accepted = await session.submitInvitation('YCI1.fake.key_wrap');
  assert.equal(accepted.memberId, 'member-join');
  assert.equal(session.getState().phase, FamilyJoinPhase.COMPLETED);
  const member = await h.families.getMember(family.familyId, 'member-join');
  assert.equal(member.status, MemberStatus.ACTIVE);
  assert.equal(handle.text.startsWith('YCR1.'), true);
});

test('T09_C08_joinSessionCodeKekWithoutCodeRequiresCodeAndCancelCleansUp', async () => {
  const { h, service } = await setup();
  await createFamily(service);
  const session = service.createJoinSession();
  const handle = await session.start('Joiner');
  await assert.rejects(session.submitInvitation('YCI1.CODE.container'),
    (error) => error.code === 'INVITE_CODE_INVALID');
  assert.equal(session.getState().phase, FamilyJoinPhase.CODE_REQUIRED);
  await session.cancel();
  assert.equal(session.getState().phase, FamilyJoinPhase.CANCELLED);
  assert.deepEqual(h.invites.discarded, [handle.memberId]);
});

test('T09_C08_markContactSyncIsConvergenceOnly', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  await service.markContactSync(family.familyId, family.ownerMemberId, NOW + 5000);
  const member = await h.families.getMember(family.familyId, family.ownerMemberId);
  assert.equal(member.lastSyncedAt, '20261017T080005Z');
  const view = (await service.listMemberViews(family.familyId))[0];
  assert.equal(view.syncState, FamilyContactSyncState.SYNCED);
  assert.equal(view.lastSyncedAt, '20261017T080005Z');
  assert.equal(typeof view.isOnline, 'undefined');
});

test('T09_C08_leaveFamilyRemovesMemberAndProfileOnly', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const member = await addMember(h, family.familyId, 'member-2', MemberRole.MEMBER, 'Bob');
  const plan = await service.leaveFamily(family.familyId, member.memberId, member.memberId);
  assert.equal(plan.familyId, family.familyId);
  assert.equal(await h.families.getMember(family.familyId, member.memberId), undefined);
  assert.equal((await h.families.getFamily(family.familyId)).familyId, family.familyId);
  assert.equal(h.control.commands.length, 0);
});

test('T09_C08_dissolveFamilyRemovesLocalDataProfilesAndClearsActive', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  await h.families.addGatewayToFamily(family.familyId, GATEWAY_ID);
  await addMember(h, family.familyId, 'member-2', MemberRole.MEMBER, 'Bob');
  const plan = await service.dissolveFamily(family.familyId, family.ownerMemberId);
  assert.deepEqual(plan.gatewayIds, [GATEWAY_ID]);
  assert.equal(plan.requiresRotation, true);
  assert.equal(plan.requiresGatewayUnbind, true);
  assert.equal(await h.families.getFamily(family.familyId), undefined);
  assert.equal((await h.families.listMembers(family.familyId)).length, 0);
  assert.equal(await service.getActiveFamily(), undefined);
  assert.equal(h.control.commands.length, 0);
});

test('T09_C08_dissolveReportsProfileCleanupFailureButKeepsLocalDeletion', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  h.auth.failRemoveFamily = true;
  await assert.rejects(service.dissolveFamily(family.familyId, family.ownerMemberId),
    (error) => error.code === 'CONFIGURATION_ERROR');
  assert.equal(await h.families.getFamily(family.familyId), undefined);
});

test('T09_C08_dissolveUsesRouteAuthorityAndReturnsEveryGateway', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const secondGateway = 'gw-2';
  h.routes.add(GATEWAY_ID, family.familyId);
  h.routes.add(secondGateway, family.familyId);
  // Family row deliberately lists only one gateway (stale local projection).
  await h.families.addGatewayToFamily(family.familyId, GATEWAY_ID);
  const plan = await service.dissolveFamily(family.familyId, family.ownerMemberId);
  assert.deepEqual(plan.gatewayIds.slice(0).sort(), [GATEWAY_ID, secondGateway].sort());
  assert.equal(plan.requiresRotation, true);
  assert.equal(plan.requiresGatewayUnbind, true);
  assert.ok(h.auth.removedFamilyProfiles.includes(family.familyId));
  assert.equal(await h.families.getFamily(family.familyId), undefined);
});

test('T09_C08_leaveFamilyReturnsEveryBoundGatewayAndRemovesProfile', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const member = await addMember(h, family.familyId, 'member-2', MemberRole.MEMBER, 'Bob');
  h.routes.add(GATEWAY_ID, family.familyId);
  h.routes.add('gw-2', family.familyId);
  const plan = await service.leaveFamily(family.familyId, member.memberId, member.memberId);
  assert.deepEqual(plan.gatewayIds.slice(0).sort(), [GATEWAY_ID, 'gw-2'].sort());
  assert.equal(plan.requiresRotation, true);
  assert.ok(h.auth.removedMemberProfiles.includes(family.familyId + ':' + member.memberId));
});

test('T09_C08_removeMemberSuccessInvalidatesSessionsAndGuidesRotation', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const member = await addMember(h, family.familyId, 'member-2', MemberRole.MEMBER, 'Bob');
  h.routes.add(GATEWAY_ID, family.familyId);
  const result = await service.removeMember(family.familyId, member.memberId,
    family.ownerMemberId);
  assert.equal(result.removed, true);
  assert.equal(result.requiresRotation, true);
  assert.equal(result.rotationPlan.gatewayId, GATEWAY_ID);
  assert.ok(h.auth.invalidated.includes(member.memberId));
  assert.equal(await h.families.getMember(family.familyId, member.memberId), undefined);
});

test('T09_C08_changeMemberRoleSuccessInvalidatesSessions', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const member = await addMember(h, family.familyId, 'member-2', MemberRole.MEMBER, 'Bob');
  const promoted = await service.changeMemberRole(family.familyId, member.memberId,
    MemberRole.ADMIN, family.ownerMemberId);
  assert.equal(promoted.changed, true);
  assert.equal((await h.families.getMember(family.familyId, member.memberId)).role,
    MemberRole.ADMIN);
  assert.ok(h.auth.invalidated.includes(member.memberId));
  await service.changeMemberRole(family.familyId, member.memberId, MemberRole.MEMBER,
    family.ownerMemberId);
  assert.equal((await h.families.getMember(family.familyId, member.memberId)).role,
    MemberRole.MEMBER);
});

test('T09_C08_ownerCannotBeDemotedOrRemovedAndTransferRemainsPossible', async () => {
  const { h, service } = await setup();
  const family = await createFamily(service);
  const second = await addMember(h, family.familyId, 'member-2', MemberRole.ADMIN, 'Bob');
  await assert.rejects(service.changeMemberRole(family.familyId, family.ownerMemberId,
    MemberRole.MEMBER, second.memberId), (error) => error.code === 'AUTH_RBAC_DENIED');
  await assert.rejects(service.removeMember(family.familyId, family.ownerMemberId,
    second.memberId), (error) => error.code === 'AUTH_RBAC_DENIED');
  await assert.rejects(h.families.updateMemberStatus(family.familyId, family.ownerMemberId,
    MemberStatus.DISABLED), (error) => error.code === 'AUTH_RBAC_DENIED');
  let storedFamily = await h.families.getFamily(family.familyId);
  let owner = await h.families.getMember(family.familyId, family.ownerMemberId);
  assert.equal(storedFamily.ownerMemberId, family.ownerMemberId);
  assert.equal(owner.role, MemberRole.ADMIN);
  // The family is not wedged: an explicit transfer still works and the old
  // owner can then be demoted/removed normally.
  await service.transferAdmin(family.familyId, family.ownerMemberId, second.memberId,
    family.ownerMemberId);
  storedFamily = await h.families.getFamily(family.familyId);
  owner = await h.families.getMember(family.familyId, family.ownerMemberId);
  assert.equal(storedFamily.ownerMemberId, second.memberId);
  assert.equal(owner.role, MemberRole.MEMBER);
  await service.removeMember(family.familyId, family.ownerMemberId, second.memberId);
  assert.equal(await h.families.getMember(family.familyId, family.ownerMemberId), undefined);
});
