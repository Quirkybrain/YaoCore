/*
 * YaoCore C-08 FamilyJoinSession (member side).
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §3.1.4, §3.3.4 (D-009 main path)
 *
 * The session only orchestrates UI phases and idempotent member persistence.
 * Container cryptography (YCR1/YCI1, KEY_WRAP/CODE_KEK, receipt) belongs to
 * C-13 InviteService and is consumed through InviteServicePort.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import type { ClockPort } from '../../common/types/Ports';
import type { LoggerPort } from '../../contracts/Ports';
import { FamilyMember, MemberRole, MemberStatus } from '../../model/FamilyModels';
import { FamilyRepository } from '../../repository/FamilyRepository';
import {
  AcceptInviteOptions,
  AcceptedInvitation,
  FamilyJoinPhase,
  JoinRequestHandle,
  JoinSessionState
} from './FamilyModels';
import type { FamilyAuthPort, InviteServicePort } from './FamilyModels';

export class FamilyJoinSession {
  private readonly invites: InviteServicePort;
  private readonly families: FamilyRepository;
  private readonly auth: FamilyAuthPort;
  private readonly clock: ClockPort;
  private readonly logger: LoggerPort;
  private readonly listeners: Array<(state: JoinSessionState) => void> = [];
  private state: JoinSessionState = new JoinSessionState(FamilyJoinPhase.IDLE, 0);
  private handle?: JoinRequestHandle;
  private accepted?: AcceptedInvitation = undefined;
  private acceptedText?: string = undefined;
  private disposed: boolean = false;

  constructor(invites: InviteServicePort, families: FamilyRepository, auth: FamilyAuthPort,
    clock: ClockPort, logger: LoggerPort) {
    this.invites = invites;
    this.families = families;
    this.auth = auth;
    this.clock = clock;
    this.logger = logger;
  }

  getState(): JoinSessionState {
    return this.state;
  }

  subscribe(listener: (state: JoinSessionState) => void): () => void {
    this.listeners.push(listener);
    return (): void => {
      const index = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    };
  }

  async start(displayName?: string): Promise<JoinRequestHandle> {
    this.ensureActive();
    if (this.state.phase === FamilyJoinPhase.MEMBER_BOUND ||
      this.state.phase === FamilyJoinPhase.COMPLETED) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'phase')]);
    }
    try {
      const handle = await this.invites.createJoinRequest(displayName);
      this.handle = handle;
      this.setState(new JoinSessionState(FamilyJoinPhase.JOIN_REQUEST_READY,
        this.state.revision + 1, handle.text));
      return handle;
    } catch (error) {
      this.fail(error as Error);
      throw error as Error;
    }
  }

  waitForInvitation(): void {
    this.ensureActive();
    this.setState(new JoinSessionState(FamilyJoinPhase.WAITING_FOR_INVITATION,
      this.state.revision + 1, this.state.joinRequestText));
  }

  async submitInvitation(text: string, code?: string): Promise<AcceptedInvitation> {
    this.ensureActive();
    // T-15 ruling (F-06): MEMBER_BOUND/COMPLETED is terminal for accepting a
    // container. The same text is idempotent (return the saved accepted
    // invitation); a different container is rejected without leaving the phase.
    if (this.state.phase === FamilyJoinPhase.MEMBER_BOUND ||
      this.state.phase === FamilyJoinPhase.COMPLETED) {
      if (this.accepted !== undefined && this.acceptedText === text) {
        return this.accepted;
      }
      throw AppErrors.of('INVITE_INVALID', []);
    }
    if (!text.startsWith('YCI1.') || text.length <= 5) {
      const error = AppErrors.of('INVITE_INVALID', []);
      this.fail(error as Error);
      throw error as Error;
    }
    this.setState(new JoinSessionState(FamilyJoinPhase.VALIDATING,
      this.state.revision + 1, this.state.joinRequestText));
    let accepted: AcceptedInvitation;
    try {
      accepted = await this.invites.acceptInvitation(text,
        new AcceptInviteOptions(this.clock.nowMs(), code));
    } catch (error) {
      const appError = error as AppError;
      if (appError instanceof AppError && appError.code === 'INVITE_CODE_INVALID') {
        // CODE_KEK mode without a code: expose the code-entry phase.
        this.setState(new JoinSessionState(FamilyJoinPhase.CODE_REQUIRED,
          this.state.revision + 1, this.state.joinRequestText, undefined, undefined, undefined,
          appError));
      } else {
        this.fail(error as Error);
      }
      throw error as Error;
    }
    this.setState(new JoinSessionState(FamilyJoinPhase.APPLYING,
      this.state.revision + 1, this.state.joinRequestText));
    try {
      const existing = await this.families.getMember(accepted.familyId, accepted.memberId);
      if (existing === undefined) {
        // Defensive idempotent upsert. C-13 normally writes the member already;
        // a GUEST fallback uses one local day when the container carries no
        // separate membership expiry.
        const expiresAt = accepted.role === MemberRole.GUEST ?
          DateTimeUtil.formatUtcCompact(this.clock.nowMs() + 86400000) : undefined;
        const member = new FamilyMember(accepted.memberId, accepted.familyId,
          accepted.memberId, accepted.memberId, accepted.role, MemberStatus.ACTIVE,
          DateTimeUtil.nowUtcCompact(this.clock), accepted.allowedRoomIds, expiresAt,
          undefined, undefined);
        await this.families.upsertMember(member);
      }
      this.auth.invalidateSessionsForMember(accepted.memberId);
    } catch (error) {
      this.fail(error as Error);
      throw error as Error;
    }
    this.accepted = accepted;
    this.acceptedText = text;
    // C-08's own terminal phase. COMPLETED is reserved for markProfileBound().
    this.setState(new JoinSessionState(FamilyJoinPhase.MEMBER_BOUND,
      this.state.revision + 1, this.state.joinRequestText, undefined, undefined, accepted));
    return accepted;
  }

  /**
   * T-15 ruling (F-06 / EXT-DES-B-27): the only COMPLETED writer. Requires the
   * exact member profile plus the accepted family as active family; otherwise
   * throws CONFIGURATION_ERROR and keeps MEMBER_BOUND + accepted for retry.
   */
  async markProfileBound(): Promise<void> {
    this.ensureActive();
    if (this.state.phase === FamilyJoinPhase.COMPLETED) {
      return;
    }
    if (this.state.phase !== FamilyJoinPhase.MEMBER_BOUND || this.accepted === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'phase')]);
    }
    const accepted = this.accepted;
    const member = await this.families.getMember(accepted.familyId, accepted.memberId);
    if (member === undefined || member.status !== MemberStatus.ACTIVE) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'memberId')]);
    }
    const profiles = await this.auth.listProfiles(accepted.familyId);
    let profileFound = false;
    for (let index = 0; index < profiles.length; index++) {
      if (profiles[index].memberId === accepted.memberId) {
        profileFound = true;
        break;
      }
    }
    if (!profileFound) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'profileId')]);
    }
    const active = await this.families.getActiveFamily();
    if (active === undefined || active.familyId !== accepted.familyId) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'activeFamilyId')]);
    }
    this.setState(new JoinSessionState(FamilyJoinPhase.COMPLETED,
      this.state.revision + 1, this.state.joinRequestText, undefined, undefined, accepted));
  }

  async cancel(): Promise<void> {
    if (this.disposed) {
      return;
    }
    // T-15 ruling: members are already persisted in MEMBER_BOUND/COMPLETED;
    // cancellation is a no-op there and must not discard the join request.
    if (this.state.phase === FamilyJoinPhase.MEMBER_BOUND ||
      this.state.phase === FamilyJoinPhase.COMPLETED) {
      return;
    }
    const handle = this.handle;
    this.handle = undefined;
    if (handle !== undefined) {
      try {
        await this.invites.discardJoinRequest(handle.memberId);
      } catch (error) {
        // Cleanup is best effort; never retain join-request text in state.
        this.logger.warn('FamilyJoinSession', 'join_request_cleanup_failed',
          [new NameValue('memberId', handle.memberId)]);
      }
    }
    this.setState(new JoinSessionState(FamilyJoinPhase.CANCELLED,
      this.state.revision + 1));
  }

  dispose(): void {
    this.disposed = true;
    this.listeners.splice(0, this.listeners.length);
    this.accepted = undefined;
    this.acceptedText = undefined;
    this.handle = undefined;
  }

  private fail(error: Error): void {
    const appError = error instanceof AppError ? error : AppErrors.of('INTERNAL_ERROR', []);
    this.setState(new JoinSessionState(FamilyJoinPhase.FAILED,
      this.state.revision + 1, this.state.joinRequestText, undefined, undefined, undefined,
      appError));
  }

  private setState(next: JoinSessionState): void {
    this.state = next;
    for (let index = 0; index < this.listeners.length; index++) {
      this.listeners[index](next);
    }
  }

  private ensureActive(): void {
    if (this.disposed) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'session')]);
    }
  }
}
