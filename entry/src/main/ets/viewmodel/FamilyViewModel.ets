/*
 * YaoCore C-22 FamilyViewModel.
 * Producer: agent:implementation-engineer | Task: T-16 / wp-060-vm
 * Contract: DES-B §11.1.1, §11.3.1, §11.3.2; ADR-003; D-009/D-010/D-013
 *
 * UI visibility is derived from `FamilyCapabilities`, but the service layer is
 * still authoritative. GUEST scene execution is fail-closed (F-08). Member
 * presence is never shown: only local contact-sync metadata (D-010).
 */
import { AppErrors } from '../common/types/AppError';
import { NameValue } from '../common/types/NameValue';
import type { ClockPort, LoggerPort } from '../common/types/Ports';
import type { Family, MemberRole } from '../model/FamilyModels';
import { MemberRole as MemberRoleValue } from '../model/FamilyModels';
import type {
  FamilyMemberView,
  InvitationView,
  JoinSessionState
} from '../service/family/FamilyModels';
import {
  AcceptedInvitation,
  CreateInvitationInput,
  InviteCreation
} from '../service/family/FamilyModels';
import { FamilyJoinSession } from '../service/family/FamilyJoinSession';
import { CreateProfileInput } from '../service/auth/AuthModels';
import type { SessionInfo } from '../service/auth/AuthModels';
import { AuthService } from '../service/auth/AuthService';
import { FamilyService } from '../service/family/FamilyService';
import { I18nService } from '../service/i18n/I18nService';
import {
  LoadPhase,
  ViewModelError,
  ViewModelSupport
} from './core/ViewModelCore';
import type {
  AppContextPort,
  ViewModelBase
} from './core/ViewModelCore';

const TAG: string = 'FamilyViewModel';

export enum FamilySection {
  MEMBERS = 'MEMBERS',
  INVITES = 'INVITES',
  JOIN = 'JOIN',
  FAMILY = 'FAMILY'
}

export class FamilyCapabilities {
  readonly canManageFamily: boolean;
  readonly canManageRooms: boolean;
  readonly canInvite: boolean;
  readonly canControlAll: boolean;
  readonly canExecuteScene: boolean;
  readonly allowedRoomIds: ReadonlyArray<string>;
  readonly role: MemberRole;

  constructor(role: MemberRole, canManageFamily: boolean, canManageRooms: boolean,
    canInvite: boolean, canControlAll: boolean, canExecuteScene: boolean,
    allowedRoomIds: ReadonlyArray<string>) {
    this.role = role;
    this.canManageFamily = canManageFamily;
    this.canManageRooms = canManageRooms;
    this.canInvite = canInvite;
    this.canControlAll = canControlAll;
    this.canExecuteScene = canExecuteScene;
    this.allowedRoomIds = allowedRoomIds;
  }
}

export class FamilyViewState {
  readonly phase: LoadPhase;
  readonly families: ReadonlyArray<Family>;
  readonly activeFamily?: Family;
  readonly members: ReadonlyArray<FamilyMemberView>;
  readonly invitations: ReadonlyArray<InvitationView>;
  readonly capabilities?: FamilyCapabilities;
  readonly section: FamilySection;
  readonly join?: JoinSessionState;
  readonly pendingAction: boolean;
  readonly error?: ViewModelError;
  readonly needsUnlock: boolean;
  /** D-010: family state converges on contact; there is no online presence. */
  readonly contactSyncOnly: boolean;
  readonly inviteSecurityKey?: string;
  readonly revision: number;

  constructor(phase: LoadPhase, families: ReadonlyArray<Family>, activeFamily: Family | undefined,
    members: ReadonlyArray<FamilyMemberView>, invitations: ReadonlyArray<InvitationView>,
    section: FamilySection, pendingAction: boolean, revision: number,
    capabilities?: FamilyCapabilities, join?: JoinSessionState, error?: ViewModelError,
    needsUnlock: boolean = false, inviteSecurityKey?: string) {
    this.phase = phase;
    this.families = families;
    this.activeFamily = activeFamily;
    this.members = members;
    this.invitations = invitations;
    this.capabilities = capabilities;
    this.section = section;
    this.join = join;
    this.pendingAction = pendingAction;
    this.error = error;
    this.needsUnlock = needsUnlock;
    this.contactSyncOnly = true;
    this.inviteSecurityKey = inviteSecurityKey;
    this.revision = revision;
  }

  static initial(): FamilyViewState {
    return new FamilyViewState(LoadPhase.IDLE, [], undefined, [], [], FamilySection.MEMBERS,
      false, 0);
  }
}

export class FamilyViewModel implements ViewModelBase<FamilyViewState> {
  private readonly families: FamilyService;
  private readonly auth: AuthService;
  private readonly appContext: AppContextPort;
  private readonly i18n: I18nService;
  private readonly clock: ClockPort;
  private readonly logger: LoggerPort;

  private state: FamilyViewState = FamilyViewState.initial();
  private listeners: Array<(state: FamilyViewState) => void> = [];
  private joinSession?: FamilyJoinSession = undefined;
  private unsubscribeJoin?: (() => void) = undefined;
  private revision: number = 0;
  private disposed: boolean = false;

  constructor(families: FamilyService, auth: AuthService, appContext: AppContextPort,
    i18n: I18nService, clock: ClockPort, logger: LoggerPort) {
    this.families = families;
    this.auth = auth;
    this.appContext = appContext;
    this.i18n = i18n;
    this.clock = clock;
    this.logger = logger;
  }

  getState(): FamilyViewState {
    return this.state;
  }

  subscribe(listener: (state: FamilyViewState) => void): () => void {
    this.listeners.push(listener);
    return (): void => {
      const index = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    };
  }

  async initialize(): Promise<void> {
    this.publish(this.copy(LoadPhase.LOADING, false, undefined));
    try {
      const families = await this.families.listFamilies();
      const active = await this.families.getActiveFamily();
      await this.loadActive(families, active);
    } catch (error) {
      this.fail(error as Object);
    }
  }

  setSection(section: FamilySection): void {
    this.publish(new FamilyViewState(this.state.phase, this.state.families,
      this.state.activeFamily, this.state.members, this.state.invitations, section,
      this.state.pendingAction, this.revision + 1, this.state.capabilities, this.state.join,
      this.state.error, this.state.needsUnlock, this.state.inviteSecurityKey));
  }

  async refresh(): Promise<void> {
    try {
      const families = await this.families.listFamilies();
      const active = await this.families.getActiveFamily();
      await this.loadActive(families, active);
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async createFamily(familyName: string, displayName: string, password: string): Promise<Family> {
    this.publish(this.copy(this.state.phase, true, undefined));
    try {
      const family = await this.families.createFamily(familyName, displayName);
      const profile = new CreateProfileInput(FamilyViewModel.profileIdFor(family.ownerMemberId),
        family.familyId, family.ownerMemberId, displayName, password, MemberRoleValue.ADMIN);
      await this.auth.createProfile(profile);
      const switched = await this.families.switchFamily(family.familyId);
      this.appContext.refreshSessionGate();
      this.publish(this.copy(this.state.phase, false, undefined, switched.requiresUnlock));
      await this.refresh();
      return family;
    } catch (error) {
      this.fail(error as Object);
      throw error as Error;
    }
  }

  async switchFamily(familyId: string): Promise<void> {
    this.publish(this.copy(this.state.phase, true, undefined));
    try {
      const switched = await this.families.switchFamily(familyId);
      this.appContext.refreshSessionGate();
      this.publish(this.copy(this.state.phase, false, undefined, switched.requiresUnlock));
      await this.refresh();
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async leaveFamily(familyId: string): Promise<void> {
    const session = this.requireSession();
    if (session === undefined) {
      return;
    }
    this.publish(this.copy(this.state.phase, true, undefined));
    try {
      await this.families.leaveFamily(familyId, session.memberId, session.memberId);
      this.appContext.refreshSessionGate();
      this.publish(FamilyViewState.initial());
      await this.refresh();
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async transferAdmin(newAdminMemberId: string): Promise<void> {
    const session = this.requireSession();
    if (session === undefined || this.state.activeFamily === undefined) {
      return;
    }
    this.publish(this.copy(this.state.phase, true, undefined));
    try {
      await this.families.transferAdmin(this.state.activeFamily.familyId, session.memberId,
        newAdminMemberId, session.memberId);
      await this.refresh();
      this.publish(this.copy(this.state.phase, false, undefined));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async dissolveFamily(familyId: string): Promise<void> {
    const session = this.requireSession();
    if (session === undefined) {
      return;
    }
    this.publish(this.copy(this.state.phase, true, undefined));
    try {
      await this.families.dissolveFamily(familyId, session.memberId);
      this.appContext.refreshSessionGate();
      this.publish(FamilyViewState.initial());
      await this.refresh();
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async removeMember(memberId: string): Promise<void> {
    const session = this.requireSession();
    if (session === undefined || this.state.activeFamily === undefined) {
      return;
    }
    this.publish(this.copy(this.state.phase, true, undefined));
    try {
      await this.families.removeMember(this.state.activeFamily.familyId, memberId,
        session.memberId);
      await this.refreshMembers();
      this.publish(this.copy(this.state.phase, false, undefined));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async changeMemberRole(memberId: string, role: MemberRole): Promise<void> {
    const session = this.requireSession();
    if (session === undefined || this.state.activeFamily === undefined) {
      return;
    }
    this.publish(this.copy(this.state.phase, true, undefined));
    try {
      await this.families.changeMemberRole(this.state.activeFamily.familyId, memberId, role,
        session.memberId);
      await this.refreshMembers();
      this.publish(this.copy(this.state.phase, false, undefined));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async extendGuest(memberId: string, expiresAt: string): Promise<void> {
    const session = this.requireSession();
    if (session === undefined || this.state.activeFamily === undefined) {
      return;
    }
    this.publish(this.copy(this.state.phase, true, undefined));
    try {
      await this.families.extendGuest(this.state.activeFamily.familyId, memberId, expiresAt,
        session.memberId);
      await this.refreshMembers();
      this.publish(this.copy(this.state.phase, false, undefined));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async importReceipt(inviteId: string, receiptText: string): Promise<void> {
    const session = this.requireSession();
    if (session === undefined || this.state.activeFamily === undefined) {
      return;
    }
    this.publish(this.copy(this.state.phase, true, undefined));
    try {
      await this.families.importReceipt(inviteId, receiptText, session.memberId);
      await this.refresh();
      this.publish(this.copy(this.state.phase, false, undefined));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async startJoin(displayName?: string): Promise<void> {
    try {
      this.disposeJoin();
      const session = this.families.createJoinSession();
      this.joinSession = session;
      this.unsubscribeJoin = session.subscribe((state: JoinSessionState): void => {
        this.syncJoin(state);
      });
      await session.start(displayName);
      this.publish(new FamilyViewState(this.state.phase, this.state.families,
        this.state.activeFamily, this.state.members, this.state.invitations,
        this.state.section, false, this.revision + 1, this.state.capabilities,
        session.getState(), this.state.error, this.state.needsUnlock,
        this.state.inviteSecurityKey));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async submitJoinInvitation(text: string, code?: string): Promise<void> {
    const session = this.joinSession;
    if (session === undefined) {
      this.fail(AppErrors.of('INVITE_INVALID', []));
      return;
    }
    try {
      await session.submitInvitation(text, code);
    } catch (error) {
      // FamilyJoinSession already exposes a typed FAILED/CODE_REQUIRED state.
      this.syncJoin(session.getState());
    }
  }

  async completeJoinWithProfile(displayName: string, password: string): Promise<void> {
    const join = this.state.join;
    if (join === undefined || join.accepted === undefined) {
      this.fail(AppErrors.of('INVITE_INVALID', []));
      return;
    }
    const accepted: AcceptedInvitation = join.accepted;
    try {
      const profile = new CreateProfileInput(FamilyViewModel.profileIdFor(accepted.memberId),
        accepted.familyId, accepted.memberId, displayName, password, accepted.role);
      await this.auth.createProfile(profile);
      await this.families.switchFamily(accepted.familyId);
      this.appContext.refreshSessionGate();
      await this.refresh();
    } catch (error) {
      // Keep AcceptedInvitation so the user can retry without re-consuming the
      // invitation container; the profile creation is idempotent-guarded by C-12.
      this.fail(error as Object);
    }
  }

  async startInviteFromJoinRequest(text: string,
    input: CreateInvitationInput): Promise<InviteCreation> {
    const session = this.requireSession();
    if (session === undefined) {
      throw AppErrors.of('AUTH_SESSION_INVALID', []);
    }
    this.publish(this.copy(this.state.phase, true, undefined));
    try {
      const creation = await this.families.createInvitationForJoinRequest(text, input,
        session.memberId);
      this.publish(this.copy(this.state.phase, false, undefined));
      return creation;
    } catch (error) {
      this.fail(error as Object);
      throw error as Error;
    }
  }

  async createCodeInvitation(input: CreateInvitationInput): Promise<InviteCreation> {
    const session = this.requireSession();
    if (session === undefined) {
      throw AppErrors.of('AUTH_SESSION_INVALID', []);
    }
    this.publish(this.copy(this.state.phase, true, undefined));
    try {
      const creation = await this.families.createCodeInvitation(input, session.memberId);
      this.publish(new FamilyViewState(this.state.phase, this.state.families,
        this.state.activeFamily, this.state.members, this.state.invitations,
        this.state.section, false, this.revision + 1, this.state.capabilities,
        this.state.join, undefined, this.state.needsUnlock,
        'invite.security.weak_mode_warning'));
      return creation;
    } catch (error) {
      this.fail(error as Object);
      throw error as Error;
    }
  }

  async revokeInvitation(inviteId: string): Promise<void> {
    const session = this.requireSession();
    if (session === undefined) {
      return;
    }
    this.publish(this.copy(this.state.phase, true, undefined));
    try {
      await this.families.revokeInvitation(inviteId, session.memberId);
      await this.refresh();
      this.publish(this.copy(this.state.phase, false, undefined));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async cancelJoin(): Promise<void> {
    try {
      if (this.joinSession !== undefined) {
        await this.joinSession.cancel();
      }
      this.publish(new FamilyViewState(this.state.phase, this.state.families,
        this.state.activeFamily, this.state.members, this.state.invitations,
        this.state.section, false, this.revision + 1, this.state.capabilities,
        this.joinSession === undefined ? undefined : this.joinSession.getState(),
        this.state.error, this.state.needsUnlock, this.state.inviteSecurityKey));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  clearError(): void {
    this.publish(this.copy(this.state.phase, this.state.pendingAction, undefined));
  }

  translateError(error: ViewModelError | undefined): string {
    return error === undefined ? '' : this.i18n.t(error.i18nKey);
  }

  dispose(): void {
    this.disposed = true;
    this.disposeJoin();
    this.listeners.splice(0, this.listeners.length);
  }

  private async loadActive(families: ReadonlyArray<Family>,
    active: Family | undefined): Promise<void> {
    if (active === undefined) {
      this.publish(new FamilyViewState(LoadPhase.READY, families, undefined, [], [],
        this.state.section, false, this.revision + 1, undefined, this.state.join, undefined,
        this.state.needsUnlock, this.state.inviteSecurityKey));
      return;
    }
    const session = this.auth.getActiveSession();
    let members: ReadonlyArray<FamilyMemberView> = [];
    let invitations: ReadonlyArray<InvitationView> = [];
    const capabilities = this.capabilitiesFor(session, members);
    try {
      members = await this.families.listMemberViews(active.familyId);
      const effective = this.capabilitiesFor(session, members);
      if (effective !== undefined && effective.canInvite) {
        invitations = await this.families.listInvitationViews(active.familyId,
          session === undefined ? undefined : session.memberId);
      }
      this.publish(new FamilyViewState(LoadPhase.READY, families, active, members, invitations,
        this.state.section, false, this.revision + 1, effective, this.state.join, undefined,
        this.state.needsUnlock, this.state.inviteSecurityKey));
    } catch (error) {
      this.publish(new FamilyViewState(LoadPhase.READY, families, active, members, [],
        this.state.section, false, this.revision + 1, capabilities, this.state.join, undefined,
        this.state.needsUnlock, this.state.inviteSecurityKey));
      this.fail(error as Object);
    }
  }

  private async refreshMembers(): Promise<void> {
    if (this.state.activeFamily === undefined) {
      return;
    }
    const session = this.auth.getActiveSession();
    const members = await this.families.listMemberViews(this.state.activeFamily.familyId);
    const capabilities = this.capabilitiesFor(session, members);
    let invitations: ReadonlyArray<InvitationView> = this.state.invitations;
    if (capabilities !== undefined && capabilities.canInvite) {
      invitations = await this.families.listInvitationViews(this.state.activeFamily.familyId,
        session === undefined ? undefined : session.memberId);
    } else {
      invitations = [];
    }
    this.publish(new FamilyViewState(this.state.phase, this.state.families,
      this.state.activeFamily, members, invitations, this.state.section,
      this.state.pendingAction, this.revision + 1, capabilities, this.state.join,
      this.state.error, this.state.needsUnlock, this.state.inviteSecurityKey));
  }

  private capabilitiesFor(session: SessionInfo | undefined,
    members: ReadonlyArray<FamilyMemberView>): FamilyCapabilities | undefined {
    if (session === undefined) {
      return undefined;
    }
    const role = session.role;
    const canManageFamily = this.auth.canManageFamily(session).allowed;
    const canManageRooms = this.auth.canManageRooms(session).allowed;
    const canInvite = this.auth.canInvite(session).allowed;
    const canExecuteScene = this.auth.canExecuteScene(session).allowed;
    const allowedRoomIds: string[] = [];
    if (role === MemberRoleValue.GUEST) {
      for (let index = 0; index < members.length; index++) {
        if (members[index].member.memberId === session.memberId) {
          for (let roomIndex = 0; roomIndex < members[index].member.allowedRoomIds.length;
            roomIndex++) {
            allowedRoomIds.push(members[index].member.allowedRoomIds[roomIndex]);
          }
          break;
        }
      }
    }
    return new FamilyCapabilities(role, canManageFamily, canManageRooms, canInvite,
      role === MemberRoleValue.ADMIN || role === MemberRoleValue.MEMBER, canExecuteScene,
      allowedRoomIds);
  }

  private syncJoin(join: JoinSessionState): void {
    this.publish(new FamilyViewState(this.state.phase, this.state.families,
      this.state.activeFamily, this.state.members, this.state.invitations, this.state.section,
      this.state.pendingAction, this.revision + 1, this.state.capabilities, join,
      this.state.error, this.state.needsUnlock, this.state.inviteSecurityKey));
  }

  private requireSession(): SessionInfo | undefined {
    const session = this.auth.getActiveSession();
    if (session === undefined) {
      this.fail(AppErrors.of('AUTH_SESSION_INVALID', []));
      return undefined;
    }
    return session;
  }

  private copy(phase: LoadPhase, pendingAction: boolean, error: ViewModelError | undefined,
    needsUnlock: boolean = this.state.needsUnlock): FamilyViewState {
    return new FamilyViewState(phase, this.state.families, this.state.activeFamily,
      this.state.members, this.state.invitations, this.state.section, pendingAction,
      this.revision + 1, this.state.capabilities, this.state.join, error, needsUnlock,
      this.state.inviteSecurityKey);
  }

  private fail(error: Object): void {
    const viewError = ViewModelSupport.viewError(error, this.clock);
    this.logger.warn(TAG, 'view_model_error', [new NameValue('code', viewError.error.code)]);
    this.publish(new FamilyViewState(this.state.phase, this.state.families,
      this.state.activeFamily, this.state.members, this.state.invitations, this.state.section,
      false, this.revision + 1, this.state.capabilities, this.state.join, viewError,
      this.state.needsUnlock, this.state.inviteSecurityKey));
  }

  private publish(next: FamilyViewState): void {
    this.revision = next.revision;
    this.state = next;
    for (let index = 0; index < this.listeners.length; index++) {
      try {
        this.listeners[index](next);
      } catch (error) {
        this.logger.warn(TAG, 'listener_failed',
          [new NameValue('code', ViewModelSupport.codeOf(error as Object))]);
      }
    }
  }

  private disposeJoin(): void {
    if (this.unsubscribeJoin !== undefined) {
      this.unsubscribeJoin();
      this.unsubscribeJoin = undefined;
    }
    if (this.joinSession !== undefined) {
      this.joinSession.dispose();
      this.joinSession = undefined;
    }
  }

  private static profileIdFor(memberId: string): string {
    const sanitized = memberId.replace(/[^A-Za-z0-9_.-]/g, '_');
    return 'p-' + sanitized.substring(0, 61);
  }
}
