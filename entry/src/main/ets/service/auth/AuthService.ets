/*
 * YaoCore C-12 AuthService.
 * Producer: agent:implementation-engineer | Task: T-13 / wp-049-family
 * Contract: DES-A §12.1-§12.6; FR-FAM-003/004; NFR-4.2; DP-04/DP-06
 *
 * Local profile + PBKDF2|SHA256(120000) + in-memory sessions + App-policy RBAC.
 * The password hash lives only in the platform SecretStore (Asset Store); the
 * RDB keeps public salt/iteration metadata. Sessions are memory-only and are
 * invalidated when members change; RBAC is explicitly NOT a cryptographic
 * boundary (ADR-003 §6.3).
 *
 * O-1: no nested RDB transactions. The only transaction is inside createProfile
 * and it never calls another repository/service.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { StorageConstants } from '../../common/constants/StorageConstants';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import { BytesUtil } from '../../common/utils/BytesUtil';
import { SecureBytes } from '../../common/types/SecureBytes';
import type {
  ClockPort,
  IdPort,
  RandomPort
} from '../../common/types/Ports';
import {
  MemberRole,
  MemberStatus
} from '../../model/FamilyModels';
import { DeviceState, RoomRef } from '../../model/DeviceState';
import type { MigrationSink } from '../storage/MigrationPort';
import type { RdbRow, RdbTransaction } from '../storage/RdbStore';
import { StorageService } from '../storage/StorageService';
import { SqlCells } from '../../repository/SqlCells';
import { FamilyRepository } from '../../repository/FamilyRepository';
import type { FamilyAuthPort } from '../family/FamilyModels';
import type { CryptoPort } from '../crypto/CryptoPort';
import {
  AuthPolicy,
  CreateProfileInput,
  LocalProfile,
  PolicyDecision,
  SessionInfo
} from './AuthModels';

const AUTH_ITERATIONS: number = 120000;
const SALT_BYTES: number = 16;
const HASH_BYTES: number = 32;
const SESSION_ID_BYTES: number = 16;
const PASSWORD_MIN_LENGTH: number = 8;
const BACKOFF_THRESHOLD: number = 5;
const BACKOFF_BASE_MS: number = 30000;
const BACKOFF_MAX_EXPONENT: number = 4;

const PROFILE_ID_PATTERN: RegExp = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$/;

const V3_STATEMENTS: ReadonlyArray<string> = [
  'CREATE TABLE IF NOT EXISTS auth_profile (' +
    'profile_id TEXT PRIMARY KEY NOT NULL, ' +
    'family_id TEXT NOT NULL, ' +
    'member_id TEXT NOT NULL, ' +
    'display_name TEXT NOT NULL, ' +
    'hash_alias TEXT NOT NULL, ' +
    'salt_hex TEXT NOT NULL, ' +
    'iterations INTEGER NOT NULL, ' +
    'created_at TEXT NOT NULL, ' +
    'updated_at TEXT NOT NULL)',
  'CREATE INDEX IF NOT EXISTS idx_auth_profile_family ON auth_profile(family_id)'
];

class SessionRecord {
  readonly info: SessionInfo;
  readonly memberStatus: MemberStatus;
  readonly memberExpiresAtMs: number;
  readonly allowedRoomIds: ReadonlyArray<string>;

  constructor(info: SessionInfo, memberStatus: MemberStatus, memberExpiresAtMs: number,
    allowedRoomIds: ReadonlyArray<string>) {
    this.info = info;
    this.memberStatus = memberStatus;
    this.memberExpiresAtMs = memberExpiresAtMs;
    this.allowedRoomIds = allowedRoomIds;
  }
}

class FailureState {
  count: number = 0;
  nextAttemptMs: number = 0;
}

export class AuthService implements FamilyAuthPort {
  private readonly crypto: CryptoPort;
  private readonly storage: StorageService;
  private readonly families: FamilyRepository;
  private readonly clock: ClockPort;
  private readonly random: RandomPort;
  private readonly ids: IdPort;
  private readonly policy: AuthPolicy;
  private readonly sessions: Map<string, SessionRecord> = new Map<string, SessionRecord>();
  private readonly failures: Map<string, FailureState> = new Map<string, FailureState>();
  private activeSessionId?: string = undefined;
  private initialized: boolean = false;

  constructor(crypto: CryptoPort, storage: StorageService, families: FamilyRepository,
    clock: ClockPort, random: RandomPort, ids: IdPort, policy: AuthPolicy) {
    this.crypto = crypto;
    this.storage = storage;
    this.families = families;
    this.clock = clock;
    this.random = random;
    this.ids = ids;
    this.policy = policy;
  }

  /** DES-A §12.3/§12.4: v3 auth_profile. Registered before StorageService. */
  static registerMigrations(registry: MigrationSink): void {
    registry.register(3, V3_STATEMENTS);
  }

  async initialize(): Promise<void> {
    try {
      await this.storage.rdb.query('SELECT profile_id FROM auth_profile LIMIT 0');
    } catch (error) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    this.initialized = true;
  }

  // ---- Profiles -----------------------------------------------------------

  async createProfile(input: CreateProfileInput): Promise<LocalProfile> {
    this.ensureInitialized();
    AuthService.validatePassword(input.password);
    const familyId = AuthService.requireIdentifier(input.familyId, 'familyId');
    const memberId = AuthService.requireIdentifier(input.memberId, 'memberId');
    const profileId = AuthService.requireProfileId(input.profileId);
    const displayName = AuthService.requireDisplayName(input.displayName);
    const member = await this.families.getMember(familyId, memberId);
    if (member === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'memberId')]);
    }
    if (member.familyId !== familyId) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
    }
    const existing = await this.readProfile(profileId);
    if (existing !== undefined) {
      throw AppErrors.of('AUTH_PROFILE_EXISTS', []);
    }
    const familyProfiles = await this.listProfiles(familyId);
    for (let index = 0; index < familyProfiles.length; index++) {
      if (familyProfiles[index].memberId === memberId) {
        throw AppErrors.of('AUTH_PROFILE_EXISTS', []);
      }
    }
    const salt = await this.random.nextBytes(SALT_BYTES);
    const saltHex = BytesUtil.hexLower(salt);
    const hashAlias = StorageConstants.authHashAlias(profileId);
    const hash = await this.deriveHash(input.password, salt, AUTH_ITERATIONS);
    let stored = false;
    try {
      const secret = SecureBytes.from(hash);
      try {
        await this.storage.secrets.put(hashAlias, secret);
        stored = true;
      } finally {
        secret.destroy();
      }
    } finally {
      BytesUtil.zeroize(hash);
      BytesUtil.zeroize(salt);
    }
    const now = DateTimeUtil.nowUtcCompact(this.clock);
    try {
      await this.storage.rdb.transaction<void>(
        async (tx: RdbTransaction): Promise<void> => {
          const rows = await tx.query('SELECT profile_id FROM auth_profile WHERE profile_id = ?',
            [profileId]);
          if (rows.length > 0) {
            throw AppErrors.of('AUTH_PROFILE_EXISTS', []);
          }
          await tx.execute('INSERT INTO auth_profile (profile_id, family_id, member_id, ' +
            'display_name, hash_alias, salt_hex, iterations, created_at, updated_at) ' +
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [profileId, familyId, memberId, displayName, hashAlias, saltHex, AUTH_ITERATIONS,
            now, now]);
        });
    } catch (error) {
      if (stored) {
        await this.removeSecretQuietly(hashAlias);
      }
      throw error as Error;
    }
    return new LocalProfile(profileId, familyId, memberId, displayName, hashAlias, saltHex,
      AUTH_ITERATIONS, now, now);
  }

  async getProfile(profileId: string): Promise<LocalProfile | undefined> {
    this.ensureInitialized();
    return this.readProfile(AuthService.requireProfileId(profileId));
  }

  async listProfiles(familyId: string): Promise<ReadonlyArray<LocalProfile>> {
    this.ensureInitialized();
    const checked = AuthService.requireIdentifier(familyId, 'familyId');
    const rows = await this.storage.rdb.query('SELECT profile_id, family_id, member_id, ' +
      'display_name, hash_alias, salt_hex, iterations, created_at, updated_at ' +
      'FROM auth_profile WHERE family_id = ? ORDER BY created_at ASC', [checked]);
    const profiles: LocalProfile[] = [];
    for (let index = 0; index < rows.length; index++) {
      profiles.push(AuthService.profileFromRow(rows[index]));
    }
    return profiles;
  }

  async changePassword(profileId: string, oldPassword: string,
    newPassword: string): Promise<void> {
    this.ensureInitialized();
    AuthService.validatePassword(newPassword);
    const profile = await this.readProfile(AuthService.requireProfileId(profileId));
    if (profile === undefined) {
      throw AppErrors.of('AUTH_PROFILE_NOT_FOUND', []);
    }
    const oldSalt = BytesUtil.hexToBytesStrictLower(profile.saltHex);
    const oldOk = await this.verifyAgainst(profile.hashAlias, oldPassword, oldSalt,
      profile.iterations);
    if (!oldOk) {
      throw AppErrors.of('AUTH_PASSWORD_INVALID', []);
    }
    const newSalt = await this.random.nextBytes(SALT_BYTES);
    const newSaltHex = BytesUtil.hexLower(newSalt);
    const newHash = await this.deriveHash(newPassword, newSalt, AUTH_ITERATIONS);
    let replaced = false;
    try {
      const secret = SecureBytes.from(newHash);
      try {
        await this.storage.secrets.put(profile.hashAlias, secret);
        replaced = true;
      } finally {
        secret.destroy();
      }
      await this.storage.rdb.execute('UPDATE auth_profile SET salt_hex = ?, iterations = ?, ' +
        'updated_at = ? WHERE profile_id = ?',
      [newSaltHex, AUTH_ITERATIONS, DateTimeUtil.nowUtcCompact(this.clock), profile.profileId]);
    } catch (error) {
      if (replaced) {
        // Contract §12.3 invariant 8: a failed password change must not destroy
        // the old credential. Re-derive the old hash from the verified old
        // password and restore it.
        try {
          const restored = await this.deriveHash(oldPassword, oldSalt, profile.iterations);
          const secret = SecureBytes.from(restored);
          try {
            await this.storage.secrets.put(profile.hashAlias, secret);
          } finally {
            secret.destroy();
            BytesUtil.zeroize(restored);
          }
        } catch (restoreError) {
          // The original failure is the actionable error; a failed restore is
          // surfaced by the next unlock as AUTH_PASSWORD_INVALID/ASSET_*.
        }
      }
      throw error as Error;
    } finally {
      BytesUtil.zeroize(oldSalt);
      BytesUtil.zeroize(newSalt);
      BytesUtil.zeroize(newHash);
    }
    await this.lockAll();
  }

  // ---- Sessions -----------------------------------------------------------

  async unlock(profileId: string, password: string): Promise<SessionInfo> {
    this.ensureInitialized();
    const checked = AuthService.requireProfileId(profileId);
    const now = this.clock.nowMs();
    const failure = this.failureState(checked);
    if (now < failure.nextAttemptMs) {
      // v1 exponential backoff is a local, in-memory refusal window. It is not
      // persisted (DoS resistance) and uses AUTH_PASSWORD_INVALID so the
      // reserved AUTH_LOCKED_OUT code is not emitted before it is catalogued.
      throw AppErrors.of('AUTH_PASSWORD_INVALID', []);
    }
    const profile = await this.readProfile(checked);
    if (profile === undefined) {
      this.recordFailure(checked, now);
      throw AppErrors.of('AUTH_PASSWORD_INVALID', []);
    }
    const salt = BytesUtil.hexToBytesStrictLower(profile.saltHex);
    let ok = false;
    try {
      ok = await this.verifyAgainst(profile.hashAlias, password, salt, profile.iterations);
    } finally {
      BytesUtil.zeroize(salt);
    }
    if (!ok) {
      this.recordFailure(checked, now);
      throw AppErrors.of('AUTH_PASSWORD_INVALID', []);
    }
    this.resetFailures(checked);
    const member = await this.families.getMember(profile.familyId, profile.memberId);
    if (member === undefined || member.familyId !== profile.familyId) {
      throw AppErrors.of('AUTH_PROFILE_NOT_FOUND', []);
    }
    const sessionId = BytesUtil.hexLower(await this.random.nextBytes(SESSION_ID_BYTES));
    const absoluteDeadline = now + this.policy.absoluteTimeoutMs;
    const idleDeadline = now + this.policy.idleTimeoutMs;
    const expiresAt = idleDeadline < absoluteDeadline ? idleDeadline : absoluteDeadline;
    const info = new SessionInfo(sessionId, profile.profileId, profile.familyId,
      profile.memberId, member.role, now, now, expiresAt);
    const memberExpiresAtMs = member.expiresAt === undefined ? -1 :
      DateTimeUtil.parseUtcCompact(member.expiresAt);
    this.sessions.set(sessionId,
      new SessionRecord(info, member.status, memberExpiresAtMs, member.allowedRoomIds));
    this.activeSessionId = sessionId;
    return info;
  }

  async lock(sessionId: string): Promise<void> {
    this.sessions.delete(sessionId);
    if (this.activeSessionId === sessionId) {
      this.activeSessionId = undefined;
    }
  }

  async lockAll(): Promise<void> {
    this.sessions.clear();
    this.activeSessionId = undefined;
  }

  invalidateSessionsForMember(memberId: string): void {
    const ids: string[] = [];
    this.sessions.forEach((record: SessionRecord, sessionId: string): void => {
      if (record.info.memberId === memberId) {
        ids.push(sessionId);
      }
    });
    for (let index = 0; index < ids.length; index++) {
      this.sessions.delete(ids[index]);
      if (this.activeSessionId === ids[index]) {
        this.activeSessionId = undefined;
      }
    }
  }

  getSession(sessionId: string): SessionInfo | undefined {
    const record = this.resolveRecord(sessionId);
    return record === undefined ? undefined : record.info;
  }

  getActiveSession(): SessionInfo | undefined {
    const active = this.activeSessionId;
    if (active === undefined) {
      return undefined;
    }
    const record = this.resolveRecord(active);
    if (record === undefined) {
      this.activeSessionId = undefined;
      return undefined;
    }
    return record.info;
  }

  touch(sessionId: string): void {
    const record = this.resolveRecord(sessionId);
    if (record === undefined) {
      return;
    }
    const now = this.clock.nowMs();
    const absoluteDeadline = record.info.createdAtMs + this.policy.absoluteTimeoutMs;
    if (now >= absoluteDeadline) {
      this.sessions.delete(sessionId);
      if (this.activeSessionId === sessionId) {
        this.activeSessionId = undefined;
      }
      return;
    }
    const idleDeadline = now + this.policy.idleTimeoutMs;
    const expiresAt = idleDeadline < absoluteDeadline ? idleDeadline : absoluteDeadline;
    const info = new SessionInfo(record.info.sessionId, record.info.profileId,
      record.info.familyId, record.info.memberId, record.info.role, record.info.createdAtMs,
      now, expiresAt);
    this.sessions.set(sessionId,
      new SessionRecord(info, record.memberStatus, record.memberExpiresAtMs,
        record.allowedRoomIds));
  }

  async verifyPassword(profileId: string, password: string): Promise<boolean> {
    this.ensureInitialized();
    const profile = await this.readProfile(AuthService.requireProfileId(profileId));
    if (profile === undefined) {
      return false;
    }
    const salt = BytesUtil.hexToBytesStrictLower(profile.saltHex);
    try {
      return await this.verifyAgainst(profile.hashAlias, password, salt, profile.iterations);
    } finally {
      BytesUtil.zeroize(salt);
    }
  }

  // ---- RBAC ---------------------------------------------------------------

  isAdmin(session: SessionInfo): boolean {
    const record = this.resolveRecord(session.sessionId);
    return record !== undefined && record.info.role === MemberRole.ADMIN;
  }

  canControl(session: SessionInfo, device: DeviceState,
    room: RoomRef | undefined): PolicyDecision {
    const record = this.resolveRecord(session.sessionId);
    if (record === undefined) {
      return PolicyDecision.deny('SESSION_EXPIRED');
    }
    if (!AuthService.memberUsable(record, this.clock.nowMs())) {
      return PolicyDecision.deny('MEMBER_INACTIVE');
    }
    if (!device.isEnabled) {
      return PolicyDecision.deny('DEVICE_DISABLED');
    }
    if (device.isUnassigned) {
      return PolicyDecision.deny('DEVICE_UNASSIGNED');
    }
    const role = record.info.role;
    if (role === MemberRole.ADMIN || role === MemberRole.MEMBER) {
      if (!device.snapshot.isSupported) {
        return PolicyDecision.deny('UNSUPPORTED_DEVICE_TYPE');
      }
      return PolicyDecision.allow();
    }
    if (device.roomId.length === 0) {
      return PolicyDecision.deny('ROOM_NOT_ALLOWED');
    }
    if (room !== undefined && room.roomId !== device.roomId) {
      return PolicyDecision.deny('ROOM_NOT_ALLOWED');
    }
    let allowed = false;
    for (let index = 0; index < record.allowedRoomIds.length; index++) {
      if (record.allowedRoomIds[index] === device.roomId) {
        allowed = true;
        break;
      }
    }
    if (!allowed) {
      return PolicyDecision.deny('ROOM_NOT_ALLOWED');
    }
    if (!device.snapshot.isSupported) {
      return PolicyDecision.deny('UNSUPPORTED_DEVICE_TYPE');
    }
    return PolicyDecision.allow();
  }

  canManageFamily(session: SessionInfo): PolicyDecision {
    return this.adminDecision(session);
  }

  canManageRooms(session: SessionInfo): PolicyDecision {
    return this.adminDecision(session);
  }

  canInvite(session: SessionInfo): PolicyDecision {
    return this.adminDecision(session);
  }

  canExecuteScene(session: SessionInfo): PolicyDecision {
    const record = this.resolveRecord(session.sessionId);
    if (record === undefined) {
      return PolicyDecision.deny('SESSION_EXPIRED');
    }
    if (!AuthService.memberUsable(record, this.clock.nowMs())) {
      return PolicyDecision.deny('MEMBER_INACTIVE');
    }
    if (record.info.role === MemberRole.ADMIN || record.info.role === MemberRole.MEMBER) {
      return PolicyDecision.allow();
    }
    return PolicyDecision.deny('RBAC_DENIED');
  }

  // ---- Profile cleanup (EXT-DES-B-20) ------------------------------------

  async removeProfilesForFamily(familyId: string): Promise<void> {
    this.ensureInitialized();
    const profiles = await this.listProfiles(familyId);
    await this.removeProfiles(profiles);
  }

  async removeProfilesForMember(familyId: string, memberId: string): Promise<void> {
    this.ensureInitialized();
    const profiles = await this.listProfiles(familyId);
    const matching: LocalProfile[] = [];
    for (let index = 0; index < profiles.length; index++) {
      if (profiles[index].memberId === memberId) {
        matching.push(profiles[index]);
      }
    }
    await this.removeProfiles(matching);
  }

  // ---- Internals ----------------------------------------------------------

  private async removeProfiles(profiles: ReadonlyArray<LocalProfile>): Promise<void> {
    let firstError: AppError | undefined = undefined;
    for (let index = 0; index < profiles.length; index++) {
      const profile = profiles[index];
      try {
        await this.storage.secrets.remove(profile.hashAlias);
      } catch (error) {
        if (!(error instanceof AppError) || error.code !== 'ASSET_NOT_FOUND') {
          if (firstError === undefined) {
            firstError = error instanceof AppError ? error :
              AppErrors.of('ASSET_IO_FAILED', []);
          }
        }
      }
      try {
        await this.storage.rdb.execute('DELETE FROM auth_profile WHERE profile_id = ?',
          [profile.profileId]);
      } catch (error) {
        if (firstError === undefined) {
          firstError = error instanceof AppError ? error : AppErrors.of('STORAGE_RDB_ERROR', []);
        }
      }
      this.invalidateSessionsForMember(profile.memberId);
    }
    if (firstError !== undefined) {
      throw firstError;
    }
  }

  private adminDecision(session: SessionInfo): PolicyDecision {
    const record = this.resolveRecord(session.sessionId);
    if (record === undefined) {
      return PolicyDecision.deny('SESSION_EXPIRED');
    }
    if (!AuthService.memberUsable(record, this.clock.nowMs())) {
      return PolicyDecision.deny('MEMBER_INACTIVE');
    }
    return record.info.role === MemberRole.ADMIN ? PolicyDecision.allow() :
      PolicyDecision.deny('RBAC_DENIED');
  }

  private resolveRecord(sessionId: string): SessionRecord | undefined {
    const record = this.sessions.get(sessionId);
    if (record === undefined) {
      return undefined;
    }
    if (this.clock.nowMs() >= record.info.expiresAtMs) {
      this.sessions.delete(sessionId);
      if (this.activeSessionId === sessionId) {
        this.activeSessionId = undefined;
      }
      return undefined;
    }
    return record;
  }

  private static memberUsable(record: SessionRecord, nowMs: number): boolean {
    if (record.memberStatus !== MemberStatus.ACTIVE) {
      return false;
    }
    if (record.info.role === MemberRole.GUEST && record.memberExpiresAtMs >= 0 &&
      nowMs >= record.memberExpiresAtMs) {
      return false;
    }
    return true;
  }

  private failureState(profileId: string): FailureState {
    let state = this.failures.get(profileId);
    if (state === undefined) {
      state = new FailureState();
      this.failures.set(profileId, state);
    }
    return state;
  }

  private recordFailure(profileId: string, nowMs: number): void {
    const state = this.failureState(profileId);
    state.count++;
    if (state.count >= BACKOFF_THRESHOLD) {
      let exponent = state.count - BACKOFF_THRESHOLD;
      if (exponent > BACKOFF_MAX_EXPONENT) {
        exponent = BACKOFF_MAX_EXPONENT;
      }
      let delay = BACKOFF_BASE_MS;
      for (let index = 0; index < exponent; index++) {
        delay *= 2;
      }
      state.nextAttemptMs = nowMs + delay;
    }
  }

  private resetFailures(profileId: string): void {
    const state = this.failures.get(profileId);
    if (state !== undefined) {
      state.count = 0;
      state.nextAttemptMs = 0;
    }
  }

  private async readProfile(profileId: string): Promise<LocalProfile | undefined> {
    const rows = await this.storage.rdb.query('SELECT profile_id, family_id, member_id, ' +
      'display_name, hash_alias, salt_hex, iterations, created_at, updated_at ' +
      'FROM auth_profile WHERE profile_id = ?', [profileId]);
    if (rows.length === 0) {
      return undefined;
    }
    return AuthService.profileFromRow(rows[0]);
  }

  private static profileFromRow(row: RdbRow): LocalProfile {
    try {
      return new LocalProfile(SqlCells.requiredString(row, 'profile_id'),
        SqlCells.requiredString(row, 'family_id'),
        SqlCells.requiredString(row, 'member_id'),
        SqlCells.requiredString(row, 'display_name'),
        SqlCells.requiredString(row, 'hash_alias'),
        SqlCells.requiredString(row, 'salt_hex'),
        SqlCells.requiredNumber(row, 'iterations'),
        SqlCells.requiredString(row, 'created_at'),
        SqlCells.requiredString(row, 'updated_at'));
    } catch (error) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
  }

  private async deriveHash(password: string, salt: Uint8Array,
    iterations: number): Promise<Uint8Array> {
    const passwordBytes = BytesUtil.utf8(password);
    try {
      return await this.crypto.pbkdf2Sha256(passwordBytes, salt, iterations, HASH_BYTES);
    } catch (error) {
      throw AppErrors.of('AUTH_KDF_FAILED', []);
    } finally {
      BytesUtil.zeroize(passwordBytes);
    }
  }

  private async verifyAgainst(hashAlias: string, password: string, salt: Uint8Array,
    iterations: number): Promise<boolean> {
    let stored: Uint8Array;
    try {
      stored = await this.storage.secrets.withSecret(hashAlias,
        async (secret: Uint8Array): Promise<Uint8Array> => BytesUtil.copyOf(secret));
    } catch (error) {
      if (error instanceof AppError && error.code === 'ASSET_NOT_FOUND') {
        return false;
      }
      throw error as Error;
    }
    try {
      const derived = await this.deriveHash(password, salt, iterations);
      try {
        return this.crypto.constantTimeEqual(derived, stored);
      } finally {
        BytesUtil.zeroize(derived);
      }
    } finally {
      BytesUtil.zeroize(stored);
    }
  }

  private async removeSecretQuietly(alias: string): Promise<void> {
    try {
      await this.storage.secrets.remove(alias);
    } catch (error) {
      // Best-effort compensation after a failed profile insert. The asset is
      // unreachable without a profile row; no plaintext is exposed.
    }
  }

  private ensureInitialized(): void {
    if (!this.initialized) {
      throw AppErrors.of('STORAGE_NOT_INITIALIZED', []);
    }
  }

  private static validatePassword(password: string): void {
    if (password.length < PASSWORD_MIN_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'password');
    }
  }

  private static requireIdentifier(value: string, field: string): string {
    if (value.length < 1 || value.length > 63) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', field);
    }
    return value;
  }

  private static requireProfileId(value: string): string {
    if (!PROFILE_ID_PATTERN.test(value)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'profileId');
    }
    return value;
  }

  private static requireDisplayName(value: string): string {
    const trimmed = value.trim();
    if (trimmed.length < 1 || trimmed.length > 63) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'displayName');
    }
    return trimmed;
  }
}
