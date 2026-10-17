/*
 * YaoCore C-08 FamilyService (use-case orchestration).
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §3.1.3, §3.2, §3.3
 *
 * Local semantics only. Family/member/role state converges when devices meet
 * (D-010/DP-05); there is no server and no cross-device online presence. C-13
 * InviteService is consumed through a port; T-13 provides the real container
 * cryptography. C-12 AuthService is consumed through a port; T-12 provides
 * session/profile implementation.
 *
 * O-1: all persistence cross-cuts go through FamilyRepository transactions and
 * ports. FamilyService opens exactly one top-level RDB transaction for
 * dissolve/leave; it never nests transactions.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import { UuidUtil } from '../../common/utils/UuidUtil';
import type { ClockPort, IdPort, LoggerPort } from '../../common/types/Ports';
import {
  Family,
  FamilyMember,
  InvitationRecord,
  InvitationStatus,
  InviteMode,
  MemberRole,
  MemberStatus
} from '../../model/FamilyModels';
import type { RdbStore, RdbTransaction } from '../storage/RdbStore';
import { FamilyRepository, InvitationPatch } from '../../repository/FamilyRepository';
import type { GatewayRoutePort } from '../../repository/GatewayPorts';
import type { RoomLookupPort } from '../../repository/DomainPorts';
import { DomainOperationGate } from '../../repository/DomainOperationGate';
import {
  AcceptedInvitation,
  CreateInvitationInput,
  ExpireGuestsResult,
  FamilyContactSyncState,
  FamilyDissolutionPlan,
  FamilyMemberView,
  FamilySwitchResult,
  InvitationReceiptState,
  InvitationView,
  InviteCreation,
  InviteCreateRequest,
  MemberChangeResult,
  RemoveMemberResult,
  RotationPlan
} from './FamilyModels';
import type { FamilyAuthPort, InviteServicePort } from './FamilyModels';
import { FamilyRbac } from './FamilyRbac';
import { FamilyJoinSession } from './FamilyJoinSession';

const ROTATION_STEP: string = 'invite.rotation.step.reprovision';

export class FamilyService {
  private readonly families: FamilyRepository;
  private readonly invites: InviteServicePort;
  private readonly auth: FamilyAuthPort;
  private readonly routes: GatewayRoutePort;
  private readonly clock: ClockPort;
  private readonly ids: IdPort;
  private readonly logger: LoggerPort;
  private readonly rdb?: RdbStore;
  private readonly rooms?: RoomLookupPort;
  private readonly gate?: DomainOperationGate;

  constructor(families: FamilyRepository, invites: InviteServicePort, auth: FamilyAuthPort,
    routes: GatewayRoutePort, clock: ClockPort, ids: IdPort, logger: LoggerPort,
    rdb?: RdbStore, rooms?: RoomLookupPort, gate?: DomainOperationGate) {
    this.families = families;
    this.invites = invites;
    this.auth = auth;
    this.routes = routes;
    this.clock = clock;
    this.ids = ids;
    this.logger = logger;
    this.rdb = rdb;
    this.rooms = rooms;
    this.gate = gate;
  }

  async initialize(): Promise<void> {
    await this.families.initialize();
  }

  // ---- Family -------------------------------------------------------------

  async listFamilies(): Promise<ReadonlyArray<Family>> {
    return this.families.listFamilies();
  }

  async getActiveFamily(): Promise<Family | undefined> {
    return this.families.getActiveFamily();
  }

  async createFamily(familyName: string, ownerDisplayName: string): Promise<Family> {
    const name = FamilyService.familyName(familyName);
    const displayName = FamilyService.displayName(ownerDisplayName);
    const ownerMemberId = UuidUtil.newUuid(this.ids);
    const family = await this.families.createFamily(name, ownerMemberId, displayName);
    const active = await this.families.getActiveFamily();
    if (active === undefined) {
      await this.families.setActiveFamily(family.familyId);
    }
    return family;
  }

  async switchFamily(familyId: string): Promise<FamilySwitchResult> {
    const family = await this.families.getFamily(familyId);
    if (family === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
    }
    await this.families.switchActiveFamily(familyId);
    await this.auth.lockAll();
    // v1: one LocalProfile per family; switching requires unlocking the
    // target family's profile (RISK-MULTIFAMILY-PROFILE).
    const profiles = await this.auth.listProfiles(familyId);
    if (profiles.length === 0) {
      throw AppErrors.of('AUTH_PROFILE_NOT_FOUND', []);
    }
    let profileId = profiles[0].profileId;
    for (let index = 0; index < profiles.length; index++) {
      if (profiles[index].familyId === familyId) {
        profileId = profiles[index].profileId;
        break;
      }
    }
    return new FamilySwitchResult(family, true, profileId);
  }

  async updateFamilyName(familyId: string, familyName: string,
    actorMemberId?: string): Promise<void> {
    await this.requireAdmin(familyId, actorMemberId);
    await this.families.updateFamilyName(familyId, familyName);
  }

  async dissolveFamily(familyId: string,
    actorMemberId?: string): Promise<FamilyDissolutionPlan> {
    await this.requireAdmin(familyId, actorMemberId);
    if (this.rdb === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'rdb')]);
    }
    const active = await this.families.getActiveFamily();
    let gatewayIds: ReadonlyArray<string> = [];
    await this.runTopLevelTransaction<void>(async (tx: RdbTransaction): Promise<void> => {
      gatewayIds = await this.families.removeFamilyLocal(tx, familyId);
    });
    let cleanupError: AppError | undefined = undefined;
    try {
      await this.auth.removeProfilesForFamily(familyId);
    } catch (error) {
      // Family data is already gone; the profile cleanup is recoverable.
      this.logger.error('FamilyService', 'dissolve_profile_cleanup_failed',
        [new NameValue('familyId', familyId)]);
      cleanupError = AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'profiles')]);
    }
    if (active !== undefined && active.familyId === familyId) {
      await this.families.clearActiveFamily();
    }
    if (cleanupError !== undefined) {
      throw cleanupError;
    }
    return new FamilyDissolutionPlan(familyId, gatewayIds, true, true);
  }

  async leaveFamily(familyId: string, memberId: string,
    actorMemberId?: string): Promise<FamilyDissolutionPlan> {
    if (actorMemberId !== undefined && actorMemberId !== memberId) {
      throw AppErrors.of('AUTH_RBAC_DENIED', []);
    }
    if (this.rdb === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'rdb')]);
    }
    const member = await this.families.getMember(familyId, memberId);
    if (member === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'memberId')]);
    }
    await this.runTopLevelTransaction<void>(async (tx: RdbTransaction): Promise<void> => {
      await this.families.removeMemberLocal(tx, familyId, memberId);
    });
    await this.auth.removeProfilesForMember(familyId, memberId);
    const plan = await this.rotationPlanForFamily(familyId);
    const gatewayIds: string[] = [];
    if (plan !== undefined) {
      gatewayIds.push(plan.gatewayId);
    }
    return new FamilyDissolutionPlan(familyId, gatewayIds, plan !== undefined, false);
  }

  // ---- Members ------------------------------------------------------------

  async listMemberViews(familyId: string): Promise<ReadonlyArray<FamilyMemberView>> {
    const members = await this.families.listMembers(familyId);
    const roomNames: Map<string, string> = new Map<string, string>();
    if (this.rooms !== undefined) {
      const rooms = await this.rooms.listRooms(familyId);
      for (let index = 0; index < rooms.length; index++) {
        roomNames.set(rooms[index].roomId, rooms[index].roomName);
      }
    }
    const views: FamilyMemberView[] = [];
    for (let index = 0; index < members.length; index++) {
      const member = members[index];
      const names: string[] = [];
      for (let grantIndex = 0; grantIndex < member.allowedRoomIds.length; grantIndex++) {
        const name = roomNames.get(member.allowedRoomIds[grantIndex]);
        if (name !== undefined) {
          names.push(name);
        }
      }
      views.push(new FamilyMemberView(member,
        member.lastSyncedAt === undefined ? FamilyContactSyncState.NEVER :
          FamilyContactSyncState.SYNCED,
        FamilyService.roleKey(member.role), FamilyService.statusKey(member.status), names,
        member.lastSyncedAt));
    }
    return views;
  }

  async removeMember(familyId: string, memberId: string,
    actorMemberId?: string): Promise<RemoveMemberResult> {
    await this.requireAdmin(familyId, actorMemberId);
    const member = await this.families.getMember(familyId, memberId);
    if (member === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'memberId')]);
    }
    await this.families.removeMember(familyId, memberId);
    this.auth.invalidateSessionsForMember(memberId);
    const plan = await this.rotationPlanForFamily(familyId);
    // The removed member may still hold command secrets: guide, never auto-run
    // BLE rotation here (DES-B §3.1.3; ADR-003 §6).
    return new RemoveMemberResult(memberId, true, true, plan);
  }

  async changeMemberRole(familyId: string, memberId: string, role: MemberRole,
    actorMemberId?: string): Promise<MemberChangeResult> {
    await this.requireAdmin(familyId, actorMemberId);
    const member = await this.families.getMember(familyId, memberId);
    if (member === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'memberId')]);
    }
    if (member.role === role) {
      return new MemberChangeResult(memberId, false, false);
    }
    await this.families.updateMemberRole(familyId, memberId, role);
    this.auth.invalidateSessionsForMember(memberId);
    // Role change does not change key material; high-risk prompts may still
    // guide a rotation, but nothing is forced here.
    return new MemberChangeResult(memberId, true, false);
  }

  async extendGuest(familyId: string, memberId: string, expiresAt: string,
    actorMemberId?: string): Promise<MemberChangeResult> {
    await this.requireAdmin(familyId, actorMemberId);
    const member = await this.families.getMember(familyId, memberId);
    if (member === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'memberId')]);
    }
    if (member.role !== MemberRole.GUEST) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'role');
    }
    const expiryMs = DateTimeUtil.parseUtcCompact(expiresAt);
    if (expiryMs <= this.clock.nowMs()) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'expiresAt');
    }
    await this.families.extendGuestExpiry(familyId, memberId, expiresAt);
    this.auth.invalidateSessionsForMember(memberId);
    return new MemberChangeResult(memberId, true, false);
  }

  async expireGuests(familyId: string, nowMs: number,
    actorMemberId?: string): Promise<ExpireGuestsResult> {
    await this.requireAdmin(familyId, actorMemberId);
    const before = await this.families.listMembers(familyId);
    const expiring: string[] = [];
    for (let index = 0; index < before.length; index++) {
      const member = before[index];
      if (member.role === MemberRole.GUEST && member.status === MemberStatus.ACTIVE &&
        member.expiresAt !== undefined && DateTimeUtil.parseUtcCompact(member.expiresAt) <= nowMs) {
        expiring.push(member.memberId);
      }
    }
    const changed = await this.families.expireGuests(familyId, nowMs);
    for (let index = 0; index < expiring.length; index++) {
      this.auth.invalidateSessionsForMember(expiring[index]);
    }
    // D-013: expiry prompts a rotation but never forces it automatically.
    const plan = await this.rotationPlanForFamily(familyId);
    return new ExpireGuestsResult(changed, expiring, plan);
  }

  async transferAdmin(familyId: string, currentAdminMemberId: string,
    newAdminMemberId: string, actorMemberId?: string): Promise<void> {
    if (actorMemberId !== undefined && actorMemberId !== currentAdminMemberId) {
      throw AppErrors.of('AUTH_RBAC_DENIED', []);
    }
    await this.requireAdmin(familyId, currentAdminMemberId);
    await this.families.transferAdmin(familyId, currentAdminMemberId, newAdminMemberId);
    this.auth.invalidateSessionsForMember(currentAdminMemberId);
    this.auth.invalidateSessionsForMember(newAdminMemberId);
  }

  async markContactSync(familyId: string, memberId: string, atMs: number): Promise<void> {
    const member = await this.families.getMember(familyId, memberId);
    if (member === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'memberId')]);
    }
    // Local contact-sync timestamp only; never an online/heartbeat signal.
    await this.families.markSynced(memberId, atMs);
  }

  // ---- Invitations (Admin side) ------------------------------------------

  async createInvitationForJoinRequest(joinRequestText: string, input: CreateInvitationInput,
    actorMemberId?: string): Promise<InviteCreation> {
    if (!joinRequestText.startsWith('YCR1.') || joinRequestText.length <= 5) {
      throw AppErrors.of('INVITE_JOIN_REQUEST_INVALID', []);
    }
    await this.requireAdmin(input.familyId, actorMemberId);
    if (input.mode !== InviteMode.KEY_WRAP) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'mode');
    }
    const family = await this.requireFamily(input.familyId);
    const request = new InviteCreateRequest(input.familyId, input.targetRole,
      input.allowedRoomIds, 1, input.ttlMs, InviteMode.KEY_WRAP, joinRequestText,
      family.familyName);
    const creation = await this.invites.createInvitation(request);
    await this.families.putInvitation(creation.record);
    return creation;
  }

  async createCodeInvitation(input: CreateInvitationInput,
    actorMemberId?: string): Promise<InviteCreation> {
    await this.requireAdmin(input.familyId, actorMemberId);
    const family = await this.requireFamily(input.familyId);
    const maxUses = input.maxUses < 1 ? 1 : input.maxUses;
    const request = new InviteCreateRequest(input.familyId, input.targetRole,
      input.allowedRoomIds, maxUses, input.ttlMs, InviteMode.CODE_KEK, undefined,
      family.familyName);
    const creation = await this.invites.createInvitation(request);
    await this.families.putInvitation(creation.record);
    return creation;
  }

  async listInvitationViews(familyId: string,
    actorMemberId?: string): Promise<ReadonlyArray<InvitationView>> {
    await this.requireAdmin(familyId, actorMemberId);
    const records = await this.families.listInvitations(familyId);
    const now = this.clock.nowMs();
    const views: InvitationView[] = [];
    for (let index = 0; index < records.length; index++) {
      const record = records[index];
      const remaining = DateTimeUtil.parseUtcCompact(record.expireAt) - now;
      const usesRemaining = record.maxUses - record.usedCount;
      views.push(new InvitationView(record,
        FamilyService.receiptState(record.status), remaining > 0 ? remaining : 0,
        usesRemaining > 0 ? usesRemaining : 0, record.mode === InviteMode.CODE_KEK,
        FamilyService.roleKey(record.targetRole), FamilyService.modeKey(record.mode)));
    }
    return views;
  }

  async revokeInvitation(inviteId: string, actorMemberId?: string): Promise<void> {
    const record = await this.requireInvitation(inviteId);
    await this.requireAdmin(record.familyId, actorMemberId);
    if (record.status === InvitationStatus.REVOKED) {
      return;
    }
    if (record.status !== InvitationStatus.PENDING) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'status')]);
    }
    await this.invites.revokeInvitation(inviteId);
    await this.families.markInvitationStatus(inviteId, InvitationStatus.REVOKED,
      new InvitationPatch(undefined, undefined, undefined,
        DateTimeUtil.nowUtcCompact(this.clock), 'USER_REVOKED'));
  }

  async importReceipt(inviteId: string, receiptText: string,
    actorMemberId?: string): Promise<AcceptedInvitation> {
    const record = await this.requireInvitation(inviteId);
    await this.requireAdmin(record.familyId, actorMemberId);
    const verification = await this.invites.verifyReceipt(receiptText, inviteId);
    if (!verification.valid || verification.memberId === undefined) {
      throw AppErrors.of('INVITE_RECEIPT_INVALID', []);
    }
    const memberId = verification.memberId;
    const existing = await this.families.getMember(record.familyId, memberId);
    if (existing === undefined) {
      const expiresAt = record.targetRole === MemberRole.GUEST ? record.expireAt : undefined;
      const member = new FamilyMember(memberId, record.familyId, memberId, memberId,
        record.targetRole, MemberStatus.ACTIVE, DateTimeUtil.nowUtcCompact(this.clock),
        record.allowedRoomIds, expiresAt, undefined,
        record.mode === InviteMode.KEY_WRAP ? 'INVITE_KEY_WRAP' : 'INVITE_CODE_KEK');
      await this.families.upsertMember(member);
    } else if (existing.status !== MemberStatus.ACTIVE) {
      await this.families.updateMemberStatus(record.familyId, memberId, MemberStatus.ACTIVE);
    }
    const acceptedAt = verification.acceptedAt === undefined ?
      DateTimeUtil.nowUtcCompact(this.clock) : verification.acceptedAt;
    await this.families.applyReceipt(inviteId,
      new InvitationPatch(acceptedAt, memberId, receiptText));
    const family = await this.requireFamily(record.familyId);
    return new AcceptedInvitation(record.familyId, record.familyName, memberId,
      record.targetRole, record.allowedRoomIds, family.gatewayIds, receiptText);
  }

  async expireInvitations(familyId: string, nowMs: number,
    actorMemberId?: string): Promise<number> {
    await this.requireAdmin(familyId, actorMemberId);
    const records = await this.families.listInvitations(familyId);
    let expired = 0;
    for (let index = 0; index < records.length; index++) {
      const record = records[index];
      if (record.status === InvitationStatus.PENDING &&
        DateTimeUtil.parseUtcCompact(record.expireAt) <= nowMs) {
        await this.families.markInvitationStatus(record.inviteId, InvitationStatus.EXPIRED);
        expired++;
      }
    }
    return expired;
  }

  createJoinSession(): FamilyJoinSession {
    return new FamilyJoinSession(this.invites, this.families, this.auth, this.clock, this.logger);
  }

  // ---- Internals ----------------------------------------------------------

  private async runTopLevelTransaction<T>(
    fn: (tx: RdbTransaction) => Promise<T>): Promise<T> {
    if (this.rdb === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'rdb')]);
    }
    const rdb = this.rdb;
    const operation = (): Promise<T> => rdb.transaction<T>(fn);
    return this.gate === undefined ? operation() : this.gate.run(operation);
  }

  private async requireAdmin(familyId: string, actorMemberId?: string): Promise<void> {
    const family = await this.families.getFamily(familyId);
    if (family === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
    }
    if (actorMemberId === undefined) {
      // v1 local-admin trust: C-12 enforces session RBAC at the call site. The
      // service still guarantees data invariants (last ADMIN) unconditionally.
      return;
    }
    const actor = await this.families.getMember(familyId, actorMemberId);
    if (actor === undefined || actor.status !== MemberStatus.ACTIVE) {
      throw AppErrors.of('AUTH_RBAC_DENIED', []);
    }
    FamilyRbac.requireAdmin(actor.role);
  }

  private async requireFamily(familyId: string): Promise<Family> {
    const family = await this.families.getFamily(familyId);
    if (family === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
    }
    return family;
  }

  private async requireInvitation(inviteId: string): Promise<InvitationRecord> {
    const record = await this.families.getInvitation(inviteId);
    if (record === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'inviteId')]);
    }
    return record;
  }

  private async rotationPlanForFamily(familyId: string): Promise<RotationPlan | undefined> {
    try {
      const routes = await this.routes.listRoutesByFamily(familyId);
      if (routes.length === 0) {
        return undefined;
      }
      return new RotationPlan(routes[0].gatewayId, [ROTATION_STEP]);
    } catch (error) {
      // Rotation guidance is advisory; never turn a successful local change
      // into a failure just because route listing failed.
      this.logger.warn('FamilyService', 'rotation_plan_unavailable',
        [new NameValue('familyId', familyId)]);
      return undefined;
    }
  }

  private static familyName(value: string): string {
    const trimmed = value.trim();
    if (trimmed.length < 1 || trimmed.length > 31) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'familyName');
    }
    return trimmed;
  }

  private static displayName(value: string): string {
    const trimmed = value.trim();
    if (trimmed.length < 1 || trimmed.length > 63) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'displayName');
    }
    return trimmed;
  }

  private static roleKey(role: MemberRole): string {
    if (role === MemberRole.ADMIN) {
      return 'member.role.admin';
    }
    if (role === MemberRole.MEMBER) {
      return 'member.role.member';
    }
    return 'member.role.guest';
  }

  private static statusKey(status: MemberStatus): string {
    if (status === MemberStatus.ACTIVE) {
      return 'member.status.active';
    }
    if (status === MemberStatus.INVITED) {
      return 'member.status.invited';
    }
    if (status === MemberStatus.DISABLED) {
      return 'member.status.disabled';
    }
    return 'member.status.expired';
  }

  private static modeKey(mode: InviteMode): string {
    return mode === InviteMode.KEY_WRAP ? 'invite.mode.key_wrap' : 'invite.mode.code_kek';
  }

  private static receiptState(status: InvitationStatus): InvitationReceiptState {
    if (status === InvitationStatus.ACCEPTED) {
      return InvitationReceiptState.ACCEPTED;
    }
    if (status === InvitationStatus.REVOKED) {
      return InvitationReceiptState.REVOKED;
    }
    if (status === InvitationStatus.EXPIRED) {
      return InvitationReceiptState.EXPIRED;
    }
    return InvitationReceiptState.PENDING;
  }
}
