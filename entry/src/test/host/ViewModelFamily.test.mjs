/*
 * YaoCore T-16 FamilyViewModel host tests.
 * Producer: agent:implementation-engineer | Task: T-16 / wp-060-vm
 * Contract: DES-B §11.1.1, §11.3.1, §11.3.2; F-08; D-009/D-010.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { FamilyViewModel } from '../../main/ets/viewmodel/FamilyViewModel.ets';
import { MemberRole } from '../../main/ets/model/FamilyModels.ets';
import { AppErrors } from '../../main/ets/common/types/AppError.ets';
import {
  FakeAppContext,
  FakeClock,
  FakeI18n,
  FakeLogger
} from './viewmodel-helpers.mjs';
import {
  FAMILY_ID,
  MEMBER_ADMIN,
  MEMBER_GUEST,
  MEMBER_USER,
  FakeFamilyAuth,
  FakeFamilyWorkflow,
  FakeJoinSession,
  family,
  member,
  memberView
} from './viewmodel-admin-helpers.mjs';

const ADMIN_SESSION = { memberId: MEMBER_ADMIN, role: MemberRole.ADMIN, familyId: FAMILY_ID };
const MEMBER_SESSION = { memberId: MEMBER_USER, role: MemberRole.MEMBER, familyId: FAMILY_ID };
const GUEST_SESSION = { memberId: MEMBER_GUEST, role: MemberRole.GUEST, familyId: FAMILY_ID };

function setup(options = {}) {
  const members = options.members === undefined ? [
    memberView(member(MEMBER_ADMIN, MemberRole.ADMIN, { displayName: 'Alice' })),
    memberView(member(MEMBER_USER, MemberRole.MEMBER, { displayName: 'Bob' })),
    memberView(member(MEMBER_GUEST, MemberRole.GUEST, {
      displayName: 'Guest',
      allowedRoomIds: ['11111111-1111-4111-8111-111111111111'],
      expiresAt: '20261117T090000Z'
    }))
  ] : options.members;
  const workflow = new FakeFamilyWorkflow({
    families: [family(), family('family-2', 'Office')],
    members,
    invitations: options.invitations === undefined ? [] : options.invitations,
    joinSession: new FakeJoinSession()
  });
  const auth = new FakeFamilyAuth({
    session: options.session,
    manageFamily: options.manageFamily,
    manageRooms: options.manageRooms,
    invite: options.invite,
    executeScene: options.executeScene
  });
  const appContext = new FakeAppContext();
  const clock = new FakeClock();
  const vm = new FamilyViewModel(workflow, auth, appContext, new FakeI18n(), clock,
    new FakeLogger());
  return { workflow, auth, appContext, clock, vm };
}

test('T16_Family_adminCapabilitiesExposeAllEntries', async () => {
  const h = setup({ session: ADMIN_SESSION });
  await h.vm.initialize();
  const state = h.vm.getState();
  assert.equal(state.phase, 'READY');
  assert.equal(state.capabilities.role, MemberRole.ADMIN);
  assert.equal(state.capabilities.canManageFamily, true);
  assert.equal(state.capabilities.canManageRooms, true);
  assert.equal(state.capabilities.canInvite, true);
  assert.equal(state.capabilities.canControlAll, true);
  assert.equal(state.capabilities.canExecuteScene, true);
  assert.equal(state.contactSyncOnly, true);
});

test('T16_Family_memberCapabilitiesHideAdminEntriesButAllowScene', async () => {
  const h = setup({ session: MEMBER_SESSION, manageFamily: false, manageRooms: false,
    invite: false, executeScene: true });
  await h.vm.initialize();
  const capabilities = h.vm.getState().capabilities;
  assert.equal(capabilities.role, MemberRole.MEMBER);
  assert.equal(capabilities.canManageFamily, false);
  assert.equal(capabilities.canInvite, false);
  assert.equal(capabilities.canControlAll, true);
  assert.equal(capabilities.canExecuteScene, true);
});

test('T16_Family_guestSceneExecutionIsFailClosedAndRoomScoped', async () => {
  const h = setup({ session: GUEST_SESSION, manageFamily: false, manageRooms: false,
    invite: false, executeScene: false });
  await h.vm.initialize();
  const capabilities = h.vm.getState().capabilities;
  assert.equal(capabilities.role, MemberRole.GUEST);
  assert.equal(capabilities.canManageFamily, false);
  assert.equal(capabilities.canInvite, false);
  assert.equal(capabilities.canControlAll, false);
  assert.equal(capabilities.canExecuteScene, false);
  assert.deepEqual(capabilities.allowedRoomIds, ['11111111-1111-4111-8111-111111111111']);
});

test('T16_Family_switchFamilyRequiresUnlockAndRefreshesGate', async () => {
  const h = setup({ session: ADMIN_SESSION });
  await h.vm.initialize();
  await h.vm.switchFamily('family-2');
  assert.deepEqual(h.workflow.switched, ['family-2']);
  assert.equal(h.vm.getState().activeFamily.familyId, 'family-2');
  assert.equal(h.vm.getState().needsUnlock, true);
  assert.equal(h.appContext.refreshCount, 1);
});

test('T16_Family_createFamilyCreatesProfileAndActivates', async () => {
  const h = setup({ session: ADMIN_SESSION });
  await h.vm.initialize();
  const created = await h.vm.createFamily('New Home', 'Alice', 'correct-horse-1');
  assert.equal(created.familyName, 'New Home');
  assert.equal(h.auth.profiles.length, 1);
  assert.equal(h.auth.profiles[0].familyId, created.familyId);
  assert.equal(h.auth.profiles[0].role, MemberRole.ADMIN);
  assert.equal(h.workflow.switched.indexOf(created.familyId) >= 0, true);
  assert.equal(h.appContext.refreshCount, 1);
  assert.equal(JSON.stringify(h.vm.getState()).indexOf('correct-horse-1'), -1);
});

test('T16_Family_joinStateMachineAndProfileCompletion', async () => {
  const h = setup({ session: undefined });
  await h.vm.initialize();
  await h.vm.startJoin('New Member');
  assert.equal(h.vm.getState().join.phase, 'JOIN_REQUEST_READY');
  await h.vm.submitJoinInvitation('YCI1.test');
  // T-15 ruling F-06: submitInvitation stops at MEMBER_BOUND, not COMPLETED.
  assert.equal(h.vm.getState().join.phase, 'MEMBER_BOUND');
  assert.equal(h.vm.getState().join.accepted.memberId, 'member-new');
  assert.equal(h.auth.profiles.length, 0);
  await h.vm.completeJoinWithProfile('New Member', 'correct-horse-1');
  assert.equal(h.vm.getState().join.phase, 'COMPLETED');
  assert.equal(h.auth.profiles.length, 1);
  assert.equal(h.auth.profiles[0].memberId, 'member-new');
  assert.equal(h.workflow.switched[0], FAMILY_ID);
  assert.equal(h.workflow.joinSession.markCalls, 1);
  assert.equal(h.appContext.lockCount, 1);
  assert.equal(h.appContext.refreshCount, 1);
  assert.equal(h.vm.getState().needsUnlock, true);
  assert.equal(JSON.stringify(h.vm.getState()).indexOf('correct-horse-1'), -1);
});

test('T16_Family_joinPartialFailureKeepsMemberBoundAndRetriesViaProfileExists', async () => {
  const h = setup({ session: undefined });
  await h.vm.initialize();
  await h.vm.startJoin('New Member');
  await h.vm.submitJoinInvitation('YCI1.test');
  h.workflow.switchFailure = AppErrors.of('STORAGE_RDB_ERROR', []);
  h.workflow.switchFailuresRemaining = 1;
  await h.vm.completeJoinWithProfile('New Member', 'correct-horse-1');
  assert.equal(h.vm.getState().join.phase, 'MEMBER_BOUND');
  assert.equal(h.vm.getState().join.accepted.memberId, 'member-new');
  assert.equal(h.vm.getState().error.error.code, 'STORAGE_RDB_ERROR');
  assert.equal(h.vm.getState().needsUnlock, true);
  assert.equal(h.auth.profiles.length, 1);
  assert.equal(h.workflow.joinSession.markCalls, 0);

  // Retry: C-12 reports AUTH_PROFILE_EXISTS for the same member; this is
  // idempotent and must continue through switchFamily -> markProfileBound.
  await h.vm.completeJoinWithProfile('New Member', 'correct-horse-1');
  assert.equal(h.vm.getState().join.phase, 'COMPLETED');
  assert.equal(h.auth.profiles.length, 1);
  assert.equal(h.workflow.switched.length, 2);
  assert.equal(h.workflow.joinSession.markCalls, 1);
  assert.equal(h.vm.getState().needsUnlock, true);
});

test('T16_Family_joinTerminalPhasesRejectStartCancelAndOtherContainers', async () => {
  const h = setup({ session: undefined });
  await h.vm.initialize();
  await h.vm.startJoin('New Member');
  await h.vm.submitJoinInvitation('YCI1.test');
  assert.equal(h.vm.getState().join.phase, 'MEMBER_BOUND');
  await h.vm.startJoin('Again');
  assert.equal(h.vm.getState().error.error.code, 'CONFIGURATION_ERROR');
  assert.equal(h.vm.getState().join.phase, 'MEMBER_BOUND');
  assert.equal(h.vm.getState().join.accepted.memberId, 'member-new');
  await h.vm.cancelJoin();
  assert.equal(h.vm.getState().join.phase, 'MEMBER_BOUND');
  assert.equal(h.vm.getState().join.accepted.memberId, 'member-new');
  await h.vm.submitJoinInvitation('YCI1.other');
  assert.equal(h.vm.getState().error.error.code, 'INVITE_INVALID');
  assert.equal(h.vm.getState().join.phase, 'MEMBER_BOUND');
});

test('T16_Family_codeRequiredJoinKeepsAcceptedAndClearErrorWorks', async () => {
  const h = setup({ session: undefined });
  await h.vm.initialize();
  await h.vm.startJoin();
  await h.vm.submitJoinInvitation('CODE_REQUIRED');
  assert.equal(h.vm.getState().join.phase, 'CODE_REQUIRED');
  assert.equal(h.vm.getState().join.error.code, 'INVITE_CODE_INVALID');
  await h.vm.cancelJoin();
  assert.equal(h.vm.getState().join.phase, 'CANCELLED');
  await h.vm.removeMember('member-2');
  assert.equal(h.vm.getState().error.error.code, 'AUTH_SESSION_INVALID');
  h.vm.clearError();
  assert.equal(h.vm.getState().error, undefined);
});

test('T16_Family_codeInvitationExposesWeakModeKey', async () => {
  const h = setup({ session: ADMIN_SESSION });
  await h.vm.initialize();
  const input = {
    familyId: FAMILY_ID,
    targetRole: MemberRole.MEMBER,
    allowedRoomIds: [],
    maxUses: 5,
    ttlMs: 3600000,
    mode: 'CODE_KEK'
  };
  const creation = await h.vm.createCodeInvitation(input);
  assert.equal(creation.code, '123456');
  assert.equal(h.vm.getState().inviteSecurityKey, 'invite.security.weak_mode_warning');
  assert.equal(h.workflow.codeInviteCalls[0].actor, MEMBER_ADMIN);
});

test('T16_Family_inviteFromJoinRequestRequiresAdminSession', async () => {
  const h = setup({ session: ADMIN_SESSION });
  await h.vm.initialize();
  const input = {
    familyId: FAMILY_ID,
    targetRole: MemberRole.MEMBER,
    allowedRoomIds: [],
    maxUses: 1,
    ttlMs: 3600000,
    mode: 'KEY_WRAP'
  };
  const creation = await h.vm.startInviteFromJoinRequest('YCR1.member', input);
  assert.equal(creation.containerText, 'YCR1.test');
  assert.equal(h.workflow.inviteCalls[0].actor, MEMBER_ADMIN);
});

test('T16_Family_memberManagementPassesActorAndRefreshMembers', async () => {
  const h = setup({ session: ADMIN_SESSION });
  await h.vm.initialize();
  await h.vm.removeMember(MEMBER_USER);
  assert.equal(h.workflow.removed[0].actor, MEMBER_ADMIN);
  await h.vm.changeMemberRole(MEMBER_USER, MemberRole.GUEST);
  assert.equal(h.workflow.roleChanges[0].role, MemberRole.GUEST);
});
