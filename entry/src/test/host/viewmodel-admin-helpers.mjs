/*
 * YaoCore T-16 Room/Scene/Family ViewModel host fixtures.
 * Producer: agent:implementation-engineer | Task: T-16 / wp-060-vm
 * PUBLIC TEST DATA ONLY.
 */
import { Family, FamilyMember, MemberRole, MemberStatus } from '../../main/ets/model/FamilyModels.ets';
import { FamilyMemberView, FamilyContactSyncState } from '../../main/ets/service/family/FamilyModels.ets';

export const FAMILY_ID = 'family-1';
export const MEMBER_ADMIN = 'member-admin';
export const MEMBER_USER = 'member-user';
export const MEMBER_GUEST = 'member-guest';
export const ROOM_A = '11111111-1111-4111-8111-111111111111';
export const ROOM_B = '22222222-2222-4222-8222-222222222222';
export const T0 = '20261017T090000Z';

export function family(familyId = FAMILY_ID, name = 'Home') {
  return new Family(familyId, name, MEMBER_ADMIN, '20261001T000000Z',
    '20261001T000000Z', []);
}

export function member(memberId, role, options = {}) {
  return new FamilyMember(memberId, FAMILY_ID, memberId, options.displayName === undefined ?
    memberId : options.displayName, role, MemberStatus.ACTIVE, T0,
    options.allowedRoomIds === undefined ? [] : options.allowedRoomIds,
    options.expiresAt);
}

export function memberView(memberValue) {
  return new FamilyMemberView(memberValue, FamilyContactSyncState.NEVER,
    'member.role.' + memberValue.role.toLowerCase(),
    'member.status.' + memberValue.status.toLowerCase(), [], undefined);
}

export class FakeFamilyWorkflow {
  constructor(options = {}) {
    this.families = options.families === undefined ? [family()] : options.families;
    this.active = options.active === undefined ? this.families[0] : options.active;
    this.members = options.members === undefined ? [] : options.members;
    this.invitations = options.invitations === undefined ? [] : options.invitations;
    this.created = [];
    this.switched = [];
    this.removed = [];
    this.roleChanges = [];
    this.inviteCalls = [];
    this.codeInviteCalls = [];
    this.joinSession = options.joinSession;
  }

  async listFamilies() { return this.families; }
  async getActiveFamily() { return this.active; }

  async createFamily(name, owner) {
    const created = family('family-created', name);
    this.families.push(created);
    this.created.push({ name, owner });
    return created;
  }

  async switchFamily(familyId) {
    this.switched.push(familyId);
    const target = this.families.find((entry) => entry.familyId === familyId);
    this.active = target;
    return { family: target, requiresUnlock: true, activeProfileId: 'p-1' };
  }

  async leaveFamily(familyId, memberId, actor) { this.leave = { familyId, memberId, actor }; }
  async transferAdmin() { this.transferred = true; }
  async dissolveFamily(familyId) { this.dissolved = familyId; }
  async listMemberViews() { return this.members; }
  async listInvitationViews() { return this.invitations; }

  async removeMember(familyId, memberId, actor) {
    this.removed.push({ familyId, memberId, actor });
    return { memberId, removed: true, requiresRotation: false };
  }

  async changeMemberRole(familyId, memberId, role, actor) {
    this.roleChanges.push({ familyId, memberId, role, actor });
    return { memberId, changed: true, requiresRotation: false };
  }

  async extendGuest() { return { memberId: MEMBER_GUEST, changed: true, requiresRotation: false }; }
  async importReceipt(inviteId) { this.imported = inviteId; return { familyId: FAMILY_ID }; }
  async revokeInvitation(inviteId) { this.revoked = inviteId; }

  async createInvitationForJoinRequest(text, input, actor) {
    this.inviteCalls.push({ text, input, actor });
    return { containerText: 'YCR1.test', record: {}, code: undefined };
  }

  async createCodeInvitation(input, actor) {
    this.codeInviteCalls.push({ input, actor });
    return { containerText: 'YCI1.test', record: {}, code: '123456' };
  }

  createJoinSession() { return this.joinSession; }
}

export class FakeFamilyAuth {
  constructor(options = {}) {
    this.session = options.session;
    this.manageFamily = options.manageFamily === undefined ? true : options.manageFamily;
    this.manageRooms = options.manageRooms === undefined ? true : options.manageRooms;
    this.invite = options.invite === undefined ? true : options.invite;
    this.executeScene = options.executeScene === undefined ? true : options.executeScene;
    this.profiles = [];
    this.lockCalls = 0;
  }

  getActiveSession() { return this.session; }
  async createProfile(input) { this.profiles.push(input); return { profileId: input.profileId }; }
  canManageFamily() { return { allowed: this.manageFamily, reason: '' }; }
  canManageRooms() { return { allowed: this.manageRooms, reason: '' }; }
  canInvite() { return { allowed: this.invite, reason: '' }; }
  canExecuteScene() { return { allowed: this.executeScene, reason: '' }; }
  async lockAll() { this.lockCalls++; }
}

export class FakeJoinSession {
  constructor() {
    this.phase = 'IDLE';
    this.listeners = [];
    this.started = 0;
    this.cancelled = false;
    this.accepted = undefined;
    this.error = undefined;
    this.revision = 0;
  }

  getState() {
    return {
      phase: this.phase,
      revision: this.revision,
      joinRequestText: this.phase === 'IDLE' ? undefined : 'YCR1.test',
      accepted: this.accepted,
      error: this.error
    };
  }

  subscribe(listener) {
    this.listeners.push(listener);
    return () => {
      this.listeners = this.listeners.filter((entry) => entry !== listener);
    };
  }

  emit() {
    this.revision++;
    for (const listener of this.listeners) {
      listener(this.getState());
    }
  }

  async start() {
    this.started++;
    this.phase = 'JOIN_REQUEST_READY';
    this.emit();
    return { memberId: 'member-new', text: 'YCR1.test' };
  }

  async submitInvitation(text) {
    if (text === 'CODE_REQUIRED') {
      this.phase = 'CODE_REQUIRED';
      this.error = { code: 'INVITE_CODE_INVALID' };
      this.emit();
      throw this.error;
    }
    if (text === 'INVALID') {
      this.phase = 'FAILED';
      this.error = { code: 'INVITE_INVALID' };
      this.emit();
      throw this.error;
    }
    this.phase = 'COMPLETED';
    this.accepted = {
      familyId: FAMILY_ID,
      familyName: 'Home',
      memberId: 'member-new',
      role: MemberRole.MEMBER,
      allowedRoomIds: [],
      appliedGatewayIds: [],
      receipt: 'YCP1.test'
    };
    this.emit();
    return this.accepted;
  }

  async cancel() {
    this.cancelled = true;
    this.phase = 'CANCELLED';
    this.emit();
  }

  dispose() {
    this.listeners = [];
  }
}
