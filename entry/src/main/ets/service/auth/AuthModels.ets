/*
 * YaoCore C-12 AuthService value objects.
 * Producer: agent:implementation-engineer | Task: T-13 / wp-049-family
 * Contract: DES-A §12.1, §12.3
 *
 * Pure value types. No platform import and no secret material: a LocalProfile
 * carries only the Asset Store alias plus the public salt/iteration metadata.
 */
import { AppErrors } from '../../common/types/AppError';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import { MemberRole } from '../../model/FamilyModels';

const AUTH_ITERATIONS: number = 120000;
const SALT_HEX_PATTERN: RegExp = /^[0-9a-f]{32}$/;
const ID_PATTERN: RegExp = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,62}$/;
const PROFILE_ID_PATTERN: RegExp = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$/;

export class LocalProfile {
  readonly profileId: string;
  readonly familyId: string;
  readonly memberId: string;
  readonly displayName: string;
  readonly hashAlias: string;
  readonly saltHex: string;
  readonly iterations: number;
  readonly createdAt: string;
  readonly updatedAt: string;

  constructor(profileId: string, familyId: string, memberId: string, displayName: string,
    hashAlias: string, saltHex: string, iterations: number, createdAt: string,
    updatedAt: string) {
    if (!PROFILE_ID_PATTERN.test(profileId) || !ID_PATTERN.test(familyId) ||
      !ID_PATTERN.test(memberId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'profile');
    }
    if (displayName.length < 1 || displayName.length > 63) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'displayName');
    }
    if (hashAlias.length < 1 || hashAlias.length > 127) {
      throw AppErrors.of('SECRET_ALIAS_INVALID', []);
    }
    if (!SALT_HEX_PATTERN.test(saltHex)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'saltHex');
    }
    if (iterations !== AUTH_ITERATIONS) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'iterations');
    }
    DateTimeUtil.parseUtcCompact(createdAt);
    DateTimeUtil.parseUtcCompact(updatedAt);
    this.profileId = profileId;
    this.familyId = familyId;
    this.memberId = memberId;
    this.displayName = displayName;
    this.hashAlias = hashAlias;
    this.saltHex = saltHex;
    this.iterations = iterations;
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
  }
}

export class SessionInfo {
  readonly sessionId: string;
  readonly profileId: string;
  readonly familyId: string;
  readonly memberId: string;
  readonly role: MemberRole;
  readonly createdAtMs: number;
  readonly lastActivityMs: number;
  readonly expiresAtMs: number;

  constructor(sessionId: string, profileId: string, familyId: string, memberId: string,
    role: MemberRole, createdAtMs: number, lastActivityMs: number, expiresAtMs: number) {
    if (sessionId.length !== 32) {
      throw AppErrors.of('AUTH_SESSION_INVALID', []);
    }
    if (!PROFILE_ID_PATTERN.test(profileId) || !ID_PATTERN.test(familyId) ||
      !ID_PATTERN.test(memberId)) {
      throw AppErrors.of('AUTH_SESSION_INVALID', []);
    }
    if (role !== MemberRole.ADMIN && role !== MemberRole.MEMBER &&
      role !== MemberRole.GUEST) {
      throw AppErrors.of('AUTH_SESSION_INVALID', []);
    }
    if (!Number.isFinite(createdAtMs) || !Number.isFinite(lastActivityMs) ||
      !Number.isFinite(expiresAtMs) || createdAtMs < 0 || lastActivityMs < createdAtMs ||
      expiresAtMs < lastActivityMs) {
      throw AppErrors.of('AUTH_SESSION_INVALID', []);
    }
    this.sessionId = sessionId;
    this.profileId = profileId;
    this.familyId = familyId;
    this.memberId = memberId;
    this.role = role;
    this.createdAtMs = createdAtMs;
    this.lastActivityMs = lastActivityMs;
    this.expiresAtMs = expiresAtMs;
  }
}

export class PolicyDecision {
  readonly allowed: boolean;
  readonly reason: string;

  private constructor(allowed: boolean, reason: string) {
    this.allowed = allowed;
    this.reason = reason;
  }

  static allow(): PolicyDecision {
    return new PolicyDecision(true, 'ALLOWED');
  }

  static deny(reason: string): PolicyDecision {
    return new PolicyDecision(false, reason);
  }
}

export class AuthPolicy {
  readonly idleTimeoutMs: number;
  readonly absoluteTimeoutMs: number;

  constructor(idleTimeoutMs: number, absoluteTimeoutMs: number) {
    if (!Number.isInteger(idleTimeoutMs) || idleTimeoutMs <= 0 ||
      !Number.isInteger(absoluteTimeoutMs) || absoluteTimeoutMs <= 0 ||
      absoluteTimeoutMs < idleTimeoutMs) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'authPolicy');
    }
    this.idleTimeoutMs = idleTimeoutMs;
    this.absoluteTimeoutMs = absoluteTimeoutMs;
  }

  static defaults(): AuthPolicy {
    return new AuthPolicy(15 * 60 * 1000, 24 * 60 * 60 * 1000);
  }
}

export class CreateProfileInput {
  readonly profileId: string;
  readonly familyId: string;
  readonly memberId: string;
  readonly displayName: string;
  readonly password: string;
  readonly role: MemberRole;

  constructor(profileId: string, familyId: string, memberId: string, displayName: string,
    password: string, role: MemberRole) {
    this.profileId = profileId;
    this.familyId = familyId;
    this.memberId = memberId;
    this.displayName = displayName;
    this.password = password;
    this.role = role;
  }
}
