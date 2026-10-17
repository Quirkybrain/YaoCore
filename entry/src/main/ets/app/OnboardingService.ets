/*
 * YaoCore C-28 NO_PROFILE onboarding (F-02).
 * Producer: agent:implementation-engineer | Task: wp-070-fix-t17
 * Contract: DES-B §17.1.5 (NO_PROFILE -> 创建家庭/加入家庭入口), §3.1.3, §3.3.4
 *
 * The T-17 shell must be usable on a fresh install before the full T-18
 * Family page exists. This service is the minimal C-22 orchestration:
 *   create: FamilyService.createFamily -> AuthService.createProfile -> switch
 *   join:   FamilyJoinSession.start (YCR1) -> submitInvitation (YCI1) ->
 *           profile -> switch -> markProfileBound
 * It never unlocks automatically: the resulting gate is LOCKED so the user
 * still proves the profile password through SessionGateView.
 */
import { AppError, AppErrors } from '../common/types/AppError';
import { NameValue } from '../common/types/NameValue';
import { MemberRole } from '../model/FamilyModels';
import { CreateProfileInput } from '../service/auth/AuthModels';
import type { AuthService } from '../service/auth/AuthService';
import type { FamilyService } from '../service/family/FamilyService';
import type { FamilyJoinSession } from '../service/family/FamilyJoinSession';
import type { AcceptedInvitation } from '../service/family/FamilyModels';
import type { OnboardingPort } from './AppContext';

export class OnboardingService implements OnboardingPort {
  private readonly families: FamilyService;
  private readonly auth: AuthService;
  private joinSession: FamilyJoinSession | undefined = undefined;

  constructor(families: FamilyService, auth: AuthService) {
    this.families = families;
    this.auth = auth;
  }

  async createFamily(familyName: string, ownerDisplayName: string,
    password: string): Promise<void> {
    const family = await this.families.createFamily(familyName, ownerDisplayName);
    const profile = new CreateProfileInput(OnboardingService.profileIdFor(family.ownerMemberId),
      family.familyId, family.ownerMemberId, ownerDisplayName, password, MemberRole.ADMIN);
    await this.auth.createProfile(profile);
    // switchFamily locks every session and makes the gate recompute LOCKED.
    await this.families.switchFamily(family.familyId);
  }

  async startJoin(displayName: string): Promise<string> {
    await this.cancelJoin();
    const session = this.families.createJoinSession();
    try {
      const handle = await session.start(displayName);
      this.joinSession = session;
      return handle.text;
    } catch (error) {
      session.dispose();
      throw error as Error;
    }
  }

  async completeJoin(invitationText: string, code: string, displayName: string,
    password: string): Promise<void> {
    const session = this.joinSession;
    if (session === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'joinSession')]);
    }
    const accepted = await session.submitInvitation(invitationText,
      code.length === 0 ? undefined : code);
    await this.createProfileIfMissing(accepted, displayName, password);
    await this.families.switchFamily(accepted.familyId);
    await session.markProfileBound();
    await this.cancelJoin();
  }

  async cancelJoin(): Promise<void> {
    const session = this.joinSession;
    this.joinSession = undefined;
    if (session !== undefined) {
      try {
        // Removes the YCR1 private key/alias unless the member is already
        // bound (C-08 cancel is a no-op in MEMBER_BOUND/COMPLETED).
        await session.cancel();
      } finally {
        session.dispose();
      }
    }
  }

  /**
   * Mirrors C-22's idempotency rule: AUTH_PROFILE_EXISTS is only success when
   * the exact member already has a profile in the accepted family. Any other
   * conflict is rethrown so the gate never binds a foreign profile.
   */
  private async createProfileIfMissing(accepted: AcceptedInvitation,
    displayName: string, password: string): Promise<void> {
    const profile = new CreateProfileInput(OnboardingService.profileIdFor(accepted.memberId),
      accepted.familyId, accepted.memberId, displayName, password, accepted.role);
    try {
      await this.auth.createProfile(profile);
    } catch (error) {
      const appError = error as AppError;
      if (appError instanceof AppError && appError.code === 'AUTH_PROFILE_EXISTS') {
        const profiles = await this.auth.listProfiles(accepted.familyId);
        for (let index = 0; index < profiles.length; index++) {
          if (profiles[index].memberId === accepted.memberId) {
            return;
          }
        }
        throw AppErrors.of('AUTH_PROFILE_EXISTS', []);
      }
      throw error as Error;
    }
  }

  private static profileIdFor(memberId: string): string {
    const sanitized = memberId.replace(/[^A-Za-z0-9_.-]/g, '_');
    return 'p-' + sanitized.substring(0, 61);
  }
}
