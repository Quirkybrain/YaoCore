/*
 * YaoCore C-08 family use-case models and consumed ports.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §3.1.1, §3.1.3, §3.1.4, §23.1/§23.3
 *
 * LOCATION EXCEPTION: DES-B places view models in model/**. T-09's write scope
 * is service/** and repository/**, so the C-08 view models stay next to the
 * service that produces them. No platform import appears here.
 *
 * C-13 InviteService and C-12 AuthService are NOT implemented by T-09. The
 * ports below are the exact structural subset consumed by FamilyService; T-13
 * and T-12 adapt their concrete services to these interfaces.
 */
import type { AppError } from '../../common/types/AppError';
import type {
  Family,
  FamilyMember,
  InvitationRecord,
  InviteMode,
  MemberRole
} from '../../model/FamilyModels';

export enum FamilyContactSyncState {
  NEVER = 'NEVER',
  SYNCED = 'SYNCED',
  STALE = 'STALE'
}

export enum InvitationReceiptState {
  PENDING = 'PENDING',
  ACCEPTED = 'ACCEPTED',
  REVOKED = 'REVOKED',
  EXPIRED = 'EXPIRED'
}

export class FamilyMemberView {
  readonly member: FamilyMember;
  readonly syncState: FamilyContactSyncState;
  readonly lastSyncedAt?: string;
  readonly roleI18nKey: string;
  readonly statusI18nKey: string;
  readonly allowedRoomNames: ReadonlyArray<string>;

  constructor(member: FamilyMember, syncState: FamilyContactSyncState,
    roleI18nKey: string, statusI18nKey: string,
    allowedRoomNames: ReadonlyArray<string>, lastSyncedAt?: string) {
    this.member = member;
    this.syncState = syncState;
    this.roleI18nKey = roleI18nKey;
    this.statusI18nKey = statusI18nKey;
    this.allowedRoomNames = allowedRoomNames;
    this.lastSyncedAt = lastSyncedAt;
  }
}

export class InvitationView {
  readonly record: InvitationRecord;
  readonly receiptState: InvitationReceiptState;
  readonly remainingMs: number;
  readonly usesRemaining: number;
  readonly isWeakMode: boolean;
  readonly targetRoleI18nKey: string;
  readonly modeI18nKey: string;

  constructor(record: InvitationRecord, receiptState: InvitationReceiptState,
    remainingMs: number, usesRemaining: number, isWeakMode: boolean,
    targetRoleI18nKey: string, modeI18nKey: string) {
    this.record = record;
    this.receiptState = receiptState;
    this.remainingMs = remainingMs;
    this.usesRemaining = usesRemaining;
    this.isWeakMode = isWeakMode;
    this.targetRoleI18nKey = targetRoleI18nKey;
    this.modeI18nKey = modeI18nKey;
  }
}

export class FamilySwitchResult {
  readonly family: Family;
  readonly requiresUnlock: boolean;
  readonly activeProfileId?: string;

  constructor(family: Family, requiresUnlock: boolean,
    activeProfileId?: string) {
    this.family = family;
    this.requiresUnlock = requiresUnlock;
    this.activeProfileId = activeProfileId;
  }
}

export class RemoveMemberResult {
  readonly memberId: string;
  readonly removed: boolean;
  readonly rotationPlan?: RotationPlan;
  readonly requiresRotation: boolean;

  constructor(memberId: string, removed: boolean, requiresRotation: boolean,
    rotationPlan?: RotationPlan) {
    this.memberId = memberId;
    this.removed = removed;
    this.requiresRotation = requiresRotation;
    this.rotationPlan = rotationPlan;
  }
}

export class MemberChangeResult {
  readonly memberId: string;
  readonly changed: boolean;
  readonly rotationPlan?: RotationPlan;
  readonly requiresRotation: boolean;

  constructor(memberId: string, changed: boolean, requiresRotation: boolean,
    rotationPlan?: RotationPlan) {
    this.memberId = memberId;
    this.changed = changed;
    this.requiresRotation = requiresRotation;
    this.rotationPlan = rotationPlan;
  }
}

export class ExpireGuestsResult {
  readonly expiredCount: number;
  readonly expiredMemberIds: ReadonlyArray<string>;
  readonly rotationPlan?: RotationPlan;

  constructor(expiredCount: number, expiredMemberIds: ReadonlyArray<string>,
    rotationPlan?: RotationPlan) {
    this.expiredCount = expiredCount;
    this.expiredMemberIds = expiredMemberIds;
    this.rotationPlan = rotationPlan;
  }
}

export class FamilyDissolutionPlan {
  readonly familyId: string;
  readonly gatewayIds: ReadonlyArray<string>;
  readonly requiresRotation: boolean;
  readonly requiresGatewayUnbind: boolean;

  constructor(familyId: string, gatewayIds: ReadonlyArray<string>, requiresRotation: boolean,
    requiresGatewayUnbind: boolean) {
    this.familyId = familyId;
    this.gatewayIds = gatewayIds;
    this.requiresRotation = requiresRotation;
    this.requiresGatewayUnbind = requiresGatewayUnbind;
  }
}

export enum FamilyJoinPhase {
  IDLE = 'IDLE',
  JOIN_REQUEST_READY = 'JOIN_REQUEST_READY',
  WAITING_FOR_INVITATION = 'WAITING_FOR_INVITATION',
  CODE_REQUIRED = 'CODE_REQUIRED',
  VALIDATING = 'VALIDATING',
  APPLYING = 'APPLYING',
  /** T-15 ruling (F-06): C-08 finished (family row + ACTIVE member); C-22 owns profile. */
  MEMBER_BOUND = 'MEMBER_BOUND',
  COMPLETED = 'COMPLETED',
  FAILED = 'FAILED',
  CANCELLED = 'CANCELLED'
}

export class JoinSessionState {
  readonly phase: FamilyJoinPhase;
  readonly joinRequestText?: string;
  readonly mode?: InviteMode;
  readonly inviteId?: string;
  readonly accepted?: AcceptedInvitation;
  readonly error?: AppError;
  readonly revision: number;

  constructor(phase: FamilyJoinPhase, revision: number,
    joinRequestText?: string,
    mode?: InviteMode,
    inviteId?: string,
    accepted?: AcceptedInvitation,
    error?: AppError) {
    this.phase = phase;
    this.revision = revision;
    this.joinRequestText = joinRequestText;
    this.mode = mode;
    this.inviteId = inviteId;
    this.accepted = accepted;
    this.error = error;
  }
}

// ---- C-13 InviteService port (T-13 provides the implementation) ----------

export class RotationPlan {
  readonly gatewayId: string;
  readonly steps: ReadonlyArray<string>;

  constructor(gatewayId: string, steps: ReadonlyArray<string>) {
    this.gatewayId = gatewayId;
    this.steps = steps;
  }
}

export class InviteCreateRequest {
  readonly familyId: string;
  readonly familyName?: string;
  readonly targetRole: MemberRole;
  readonly allowedRoomIds: ReadonlyArray<string>;
  readonly maxUses: number;
  readonly ttlMs: number;
  readonly mode: InviteMode;
  readonly joinRequestText?: string;

  constructor(familyId: string, targetRole: MemberRole, allowedRoomIds: ReadonlyArray<string>,
    maxUses: number, ttlMs: number, mode: InviteMode,
    joinRequestText?: string, familyName?: string) {
    this.familyId = familyId;
    this.targetRole = targetRole;
    this.allowedRoomIds = allowedRoomIds;
    this.maxUses = maxUses;
    this.ttlMs = ttlMs;
    this.mode = mode;
    this.joinRequestText = joinRequestText;
    this.familyName = familyName;
  }
}

export class InviteCreation {
  readonly containerText: string;
  readonly record: InvitationRecord;
  readonly code?: string;

  constructor(containerText: string, record: InvitationRecord, code?: string) {
    this.containerText = containerText;
    this.record = record;
    this.code = code;
  }
}

/**
 * Caller-facing invitation input (DES-B §3.1.3 CreateInvitationInput). The
 * join-request text is a separate argument on FamilyService, so it is not
 * duplicated here.
 */
export class CreateInvitationInput {
  readonly familyId: string;
  readonly targetRole: MemberRole;
  readonly allowedRoomIds: ReadonlyArray<string>;
  readonly maxUses: number;
  readonly ttlMs: number;
  readonly mode: InviteMode;

  constructor(familyId: string, targetRole: MemberRole, allowedRoomIds: ReadonlyArray<string>,
    mode: InviteMode, maxUses: number = 1, ttlMs: number = 86400000) {
    this.familyId = familyId;
    this.targetRole = targetRole;
    this.allowedRoomIds = allowedRoomIds;
    this.mode = mode;
    this.maxUses = maxUses;
    this.ttlMs = ttlMs;
  }
}

export class JoinRequestHandle {
  readonly memberId: string;
  readonly text: string;

  constructor(memberId: string, text: string) {
    this.memberId = memberId;
    this.text = text;
  }
}

export class AcceptInviteOptions {
  readonly nowMs: number;
  readonly code?: string;

  constructor(nowMs: number, code?: string) {
    this.nowMs = nowMs;
    this.code = code;
  }
}

export class AcceptedInvitation {
  readonly familyId: string;
  readonly familyName: string;
  readonly memberId: string;
  readonly role: MemberRole;
  readonly allowedRoomIds: ReadonlyArray<string>;
  readonly appliedGatewayIds: ReadonlyArray<string>;
  readonly receipt: string;

  constructor(familyId: string, familyName: string, memberId: string, role: MemberRole,
    allowedRoomIds: ReadonlyArray<string>, appliedGatewayIds: ReadonlyArray<string>,
    receipt: string) {
    this.familyId = familyId;
    this.familyName = familyName;
    this.memberId = memberId;
    this.role = role;
    this.allowedRoomIds = allowedRoomIds;
    this.appliedGatewayIds = appliedGatewayIds;
    this.receipt = receipt;
  }
}

export class ReceiptVerification {
  readonly valid: boolean;
  readonly inviteId?: string;
  readonly memberId?: string;
  readonly acceptedAt?: string;

  constructor(valid: boolean, inviteId?: string, memberId?: string, acceptedAt?: string) {
    this.valid = valid;
    this.inviteId = inviteId;
    this.memberId = memberId;
    this.acceptedAt = acceptedAt;
  }
}

export interface InviteServicePort {
  createJoinRequest(displayName?: string): Promise<JoinRequestHandle>;
  createInvitation(input: InviteCreateRequest): Promise<InviteCreation>;
  acceptInvitation(containerText: string,
    options: AcceptInviteOptions): Promise<AcceptedInvitation>;
  /**
   * DES-A §13.2.1 / DES-B §23.6: receiptText must be a canonical
   * `YCP1.<b64url(canonical JSON)>` envelope; inviteId must equal the payload
   * value. Raw hex and non-canonical envelopes (key order, whitespace, extra
   * fields, duplicate keys, non-canonical b64url, unknown v) are rejected as
   * INVITE_RECEIPT_INVALID before any ledger write. On success the canonical
   * bytes are recorded once per (inviteId, receiptHash) in the single-process
   * ledger. F-05 compensation: C-08 calls releaseReceipt if its transaction
   * fails after this method returned.
   */
  verifyReceipt(receiptText: string, inviteId: string): Promise<ReceiptVerification>;
  /** F-05: remove the ledger entry written by verifyReceipt after a failed C-08 import. */
  releaseReceipt(receiptText: string, inviteId: string): Promise<void>;
  revokeInvitation(inviteId: string): Promise<void>;
  rotateGatewaySecret(gatewayId: string): Promise<RotationPlan>;
  discardJoinRequest(memberId: string): Promise<void>;
}

// ---- C-12 AuthService port (T-12 provides the implementation) ------------

export class FamilyProfileRef {
  readonly profileId: string;
  readonly familyId: string;
  /** EXT-DES-B-27 seam increment: needed by markProfileBound's exact-member check. */
  readonly memberId: string;

  constructor(profileId: string, familyId: string, memberId: string) {
    this.profileId = profileId;
    this.familyId = familyId;
    this.memberId = memberId;
  }
}

export interface FamilyAuthPort {
  lockAll(): Promise<void>;
  invalidateSessionsForMember(memberId: string): void;
  removeProfilesForFamily(familyId: string): Promise<void>;
  removeProfilesForMember(familyId: string, memberId: string): Promise<void>;
  listProfiles(familyId: string): Promise<ReadonlyArray<FamilyProfileRef>>;
}
