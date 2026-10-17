/*
 * YaoCore C-08 FamilyRepository.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-A §11.1-§11.6 (frozen base) + DES-B §3.1.2 (increments)
 *
 * Local authority only: no server, no network, no platform import. Family,
 * member, invitation and room-grant data live in RDB; `activeFamilyId` lives
 * in Preferences. Cross-device consistency is contact-based convergence
 * (D-010/DP-05), never an online-presence signal.
 *
 * O-1: public methods run through the injected DomainOperationGate; methods
 * that take an RdbTransaction are transaction-context only and never start a
 * nested transaction or acquire the gate.
 */
import { AppError, AppErrors } from '../common/types/AppError';
import { NameValue } from '../common/types/NameValue';
import { ProtocolConstants } from '../common/constants/ProtocolConstants';
import { StorageConstants } from '../common/constants/StorageConstants';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import { UuidUtil } from '../common/utils/UuidUtil';
import type { ClockPort, IdPort } from '../common/types/Ports';
import {
  Family,
  FamilyMember,
  InvitationRecord,
  InvitationStatus,
  MemberRole,
  MemberStatus,
  InviteMode
} from '../model/FamilyModels';
import type { PreferencesStore } from '../service/storage/PreferencesStore';
import type { RdbRow, RdbStore, RdbTransaction } from '../service/storage/RdbStore';
import type { MigrationSink } from '../service/storage/MigrationPort';
import { DomainOperationGate } from './DomainOperationGate';
import { SqlCells, SqlJson } from './SqlCells';
import type { MemberRoomGrantPort } from './DomainPorts';

export class InvitationPatch {
  readonly acceptedAt?: string;
  readonly acceptedByMemberId?: string;
  readonly receipt?: string;
  readonly revokedAt?: string;
  readonly revokedReason?: string;

  constructor(acceptedAt?: string, acceptedByMemberId?: string, receipt?: string,
    revokedAt?: string, revokedReason?: string) {
    this.acceptedAt = acceptedAt;
    this.acceptedByMemberId = acceptedByMemberId;
    this.receipt = receipt;
    this.revokedAt = revokedAt;
    this.revokedReason = revokedReason;
  }
}

const FAMILY_COLUMNS: string = 'family_id, family_name, owner_member_id, gateway_ids_json, ' +
  'created_at, updated_at';
const MEMBER_COLUMNS: string = 'member_id, family_id, user_id, display_name, role, status, ' +
  'joined_at, allowed_room_ids_json, expires_at, member_device_id, joined_via, ' +
  'secrets_version, last_synced_at';
const INVITATION_COLUMNS: string = 'invite_id, family_id, family_name, inviter_id, ' +
  'target_role, allowed_room_ids_json, mode, status, expire_at, max_uses, used_count, ' +
  'payload_string, seed_alias, code_salt_hex, kdf_iterations, member_id, accepted_at, ' +
  'accepted_by_member_id, receipt, revoked_at, revoked_reason';

const V2_STATEMENTS: ReadonlyArray<string> = [
  'CREATE TABLE IF NOT EXISTS family (' +
    'family_id TEXT PRIMARY KEY NOT NULL, ' +
    'family_name TEXT NOT NULL, ' +
    'owner_member_id TEXT NOT NULL, ' +
    'gateway_ids_json TEXT NOT NULL, ' +
    'created_at TEXT NOT NULL, ' +
    'updated_at TEXT NOT NULL)',
  'CREATE TABLE IF NOT EXISTS family_member (' +
    'member_id TEXT PRIMARY KEY NOT NULL, ' +
    'family_id TEXT NOT NULL, ' +
    'user_id TEXT NOT NULL, ' +
    'display_name TEXT NOT NULL, ' +
    'role TEXT NOT NULL, ' +
    'status TEXT NOT NULL, ' +
    'joined_at TEXT NOT NULL, ' +
    'allowed_room_ids_json TEXT NOT NULL, ' +
    'expires_at TEXT, ' +
    'member_device_id TEXT, ' +
    'joined_via TEXT, ' +
    'secrets_version TEXT, ' +
    'last_synced_at TEXT)',
  'CREATE INDEX IF NOT EXISTS idx_member_family ON family_member(family_id)',
  'CREATE TABLE IF NOT EXISTS invitation (' +
    'invite_id TEXT PRIMARY KEY NOT NULL, ' +
    'family_id TEXT NOT NULL, ' +
    'family_name TEXT NOT NULL, ' +
    'inviter_id TEXT NOT NULL, ' +
    'target_role TEXT NOT NULL, ' +
    'allowed_room_ids_json TEXT NOT NULL, ' +
    'mode TEXT NOT NULL, ' +
    'status TEXT NOT NULL, ' +
    'expire_at TEXT NOT NULL, ' +
    'max_uses INTEGER NOT NULL, ' +
    'used_count INTEGER NOT NULL, ' +
    'payload_string TEXT NOT NULL, ' +
    'seed_alias TEXT NOT NULL, ' +
    'code_salt_hex TEXT, ' +
    'kdf_iterations INTEGER, ' +
    'member_id TEXT, ' +
    'accepted_at TEXT, ' +
    'accepted_by_member_id TEXT, ' +
    'receipt TEXT, ' +
    'revoked_at TEXT, ' +
    'revoked_reason TEXT)',
  'CREATE INDEX IF NOT EXISTS idx_invitation_family ON invitation(family_id)'
];

export class FamilyRepository implements MemberRoomGrantPort {
  private readonly rdb: RdbStore;
  private readonly preferences: PreferencesStore;
  private readonly clock: ClockPort;
  private readonly ids: IdPort;
  private readonly gate: DomainOperationGate;
  private initialized: boolean = false;

  constructor(rdb: RdbStore, preferences: PreferencesStore, clock: ClockPort, ids: IdPort,
    gate?: DomainOperationGate) {
    this.rdb = rdb;
    this.preferences = preferences;
    this.clock = clock;
    this.ids = ids;
    this.gate = gate === undefined ? new DomainOperationGate() : gate;
  }

  static registerMigrations(registry: MigrationSink): void {
    registry.register(2, V2_STATEMENTS);
  }

  async initialize(): Promise<void> {
    try {
      await this.rdb.query('SELECT family_id FROM family LIMIT 0');
      await this.rdb.query('SELECT member_id FROM family_member LIMIT 0');
      await this.rdb.query('SELECT invite_id FROM invitation LIMIT 0');
    } catch (error) {
      throw FamilyRepository.storageError(error as Error);
    }
    this.initialized = true;
  }

  // ---- Family -------------------------------------------------------------

  async listFamilies(): Promise<ReadonlyArray<Family>> {
    this.ensureInitialized();
    return this.gate.run(async (): Promise<ReadonlyArray<Family>> => {
      const rows = await this.rdb.query('SELECT ' + FAMILY_COLUMNS +
        ' FROM family ORDER BY created_at ASC');
      return FamilyRepository.mapFamilies(rows);
    });
  }

  async getFamily(familyId: string): Promise<Family | undefined> {
    this.ensureInitialized();
    const checked = FamilyRepository.requireIdentifier(familyId, 'familyId');
    return this.gate.run(async (): Promise<Family | undefined> => {
      return this.readFamily(this.rdb, checked);
    });
  }

  async getActiveFamily(): Promise<Family | undefined> {
    this.ensureInitialized();
    return this.gate.run(async (): Promise<Family | undefined> => {
      let familyId: string | undefined;
      try {
        familyId = await this.preferences.getString(StorageConstants.PREF_ACTIVE_FAMILY_ID);
      } catch (error) {
        throw FamilyRepository.storageError(error as Error);
      }
      if (familyId === undefined || familyId.length === 0) {
        return undefined;
      }
      return this.readFamily(this.rdb, familyId);
    });
  }

  async setActiveFamily(familyId: string): Promise<void> {
    this.ensureInitialized();
    const checked = FamilyRepository.requireIdentifier(familyId, 'familyId');
    return this.gate.run(async (): Promise<void> => {
      await this.switchActiveFamilyInternal(checked);
    });
  }

  async switchActiveFamily(familyId: string): Promise<void> {
    this.ensureInitialized();
    const checked = FamilyRepository.requireIdentifier(familyId, 'familyId');
    return this.gate.run(async (): Promise<void> => {
      await this.switchActiveFamilyInternal(checked);
    });
  }

  /** Clears the active-family pointer after a local dissolution. */
  async clearActiveFamily(): Promise<void> {
    this.ensureInitialized();
    return this.gate.run(async (): Promise<void> => {
      try {
        await this.preferences.delete(StorageConstants.PREF_ACTIVE_FAMILY_ID);
        await this.preferences.flush();
      } catch (error) {
        throw FamilyRepository.storageError(error as Error);
      }
    });
  }

  async createFamily(familyName: string, ownerMemberId: string,
    ownerDisplayName?: string): Promise<Family> {
    this.ensureInitialized();
    const name = FamilyRepository.familyName(familyName);
    const owner = FamilyRepository.requireIdentifier(ownerMemberId, 'ownerMemberId');
    const displayName = ownerDisplayName === undefined ? owner :
      FamilyRepository.displayName(ownerDisplayName);
    return this.gate.run(async (): Promise<Family> => {
      const now = DateTimeUtil.nowUtcCompact(this.clock);
      const familyId = UuidUtil.newUuid(this.ids);
      const family = new Family(familyId, name, owner, now, now, []);
      const member = new FamilyMember(owner, familyId, owner, displayName, MemberRole.ADMIN,
        MemberStatus.ACTIVE, now, [], undefined, undefined, 'ADMIN_LOCAL');
      await this.rdb.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
        await tx.execute('INSERT OR REPLACE INTO family (' + FAMILY_COLUMNS + ') ' +
          'VALUES (?, ?, ?, ?, ?, ?)',
        [family.familyId, family.familyName, family.ownerMemberId,
          SqlJson.stringArray(family.gatewayIds), family.createdAt, family.updatedAt]);
        await FamilyRepository.insertMember(tx, member);
      });
      return family;
    });
  }

  async updateFamilyName(familyId: string, familyName: string): Promise<void> {
    this.ensureInitialized();
    const checked = FamilyRepository.requireIdentifier(familyId, 'familyId');
    const name = FamilyRepository.familyName(familyName);
    return this.gate.run(async (): Promise<void> => {
      const family = await this.readFamily(this.rdb, checked);
      if (family === undefined) {
        throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
      }
      const now = DateTimeUtil.nowUtcCompact(this.clock);
      await this.rdb.execute('UPDATE family SET family_name = ?, updated_at = ? ' +
        'WHERE family_id = ?', [name, now, checked]);
    });
  }

  async addGatewayToFamily(familyId: string, gatewayId: string): Promise<void> {
    this.ensureInitialized();
    const checkedFamily = FamilyRepository.requireIdentifier(familyId, 'familyId');
    const checkedGateway = FamilyRepository.requireGatewayId(gatewayId);
    return this.gate.run(async (): Promise<void> => {
      const family = await this.readFamily(this.rdb, checkedFamily);
      if (family === undefined) {
        throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
      }
      const ids: string[] = [];
      let found = false;
      for (let index = 0; index < family.gatewayIds.length; index++) {
        ids.push(family.gatewayIds[index]);
        if (family.gatewayIds[index] === checkedGateway) {
          found = true;
        }
      }
      if (found) {
        return;
      }
      ids.push(checkedGateway);
      await this.writeGatewayIds(checkedFamily, ids);
    });
  }

  async removeGatewayFromFamily(familyId: string, gatewayId: string): Promise<void> {
    this.ensureInitialized();
    const checkedFamily = FamilyRepository.requireIdentifier(familyId, 'familyId');
    const checkedGateway = FamilyRepository.requireGatewayId(gatewayId);
    return this.gate.run(async (): Promise<void> => {
      const family = await this.readFamily(this.rdb, checkedFamily);
      if (family === undefined) {
        throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
      }
      const ids: string[] = [];
      for (let index = 0; index < family.gatewayIds.length; index++) {
        if (family.gatewayIds[index] !== checkedGateway) {
          ids.push(family.gatewayIds[index]);
        }
      }
      if (ids.length !== family.gatewayIds.length) {
        await this.writeGatewayIds(checkedFamily, ids);
      }
    });
  }

  // ---- Members ------------------------------------------------------------

  async listMembers(familyId: string): Promise<ReadonlyArray<FamilyMember>> {
    this.ensureInitialized();
    const checked = FamilyRepository.requireIdentifier(familyId, 'familyId');
    return this.gate.run(async (): Promise<ReadonlyArray<FamilyMember>> => {
      return this.listMembersInTransaction(this.rdb, checked);
    });
  }

  async getMember(familyId: string, memberId: string): Promise<FamilyMember | undefined> {
    this.ensureInitialized();
    const checkedFamily = FamilyRepository.requireIdentifier(familyId, 'familyId');
    const checkedMember = FamilyRepository.requireIdentifier(memberId, 'memberId');
    return this.gate.run(async (): Promise<FamilyMember | undefined> => {
      return this.readMember(this.rdb, checkedFamily, checkedMember);
    });
  }

  async getMemberByDeviceId(familyId: string,
    memberDeviceId: string): Promise<FamilyMember | undefined> {
    this.ensureInitialized();
    const checkedFamily = FamilyRepository.requireIdentifier(familyId, 'familyId');
    const checkedDevice = FamilyRepository.requireGatewayId(memberDeviceId);
    return this.gate.run(async (): Promise<FamilyMember | undefined> => {
      const rows = await this.rdb.query('SELECT ' + MEMBER_COLUMNS +
        ' FROM family_member WHERE member_device_id = ?', [checkedDevice]);
      for (let index = 0; index < rows.length; index++) {
        const member = FamilyRepository.memberFromRow(rows[index]);
        if (member.familyId === checkedFamily) {
          return member;
        }
      }
      return undefined;
    });
  }

  async upsertMember(member: FamilyMember): Promise<void> {
    this.ensureInitialized();
    return this.gate.run(async (): Promise<void> => {
      await this.rdb.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
        await this.upsertMemberInTransaction(tx, member);
      });
    });
  }

  async removeMember(familyId: string, memberId: string): Promise<void> {
    this.ensureInitialized();
    const checkedFamily = FamilyRepository.requireIdentifier(familyId, 'familyId');
    const checkedMember = FamilyRepository.requireIdentifier(memberId, 'memberId');
    return this.gate.run(async (): Promise<void> => {
      await this.rdb.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
        await this.removeMemberInTransaction(tx, checkedFamily, checkedMember);
      });
    });
  }

  async updateMemberRole(familyId: string, memberId: string, role: MemberRole): Promise<void> {
    this.ensureInitialized();
    const checkedFamily = FamilyRepository.requireIdentifier(familyId, 'familyId');
    const checkedMember = FamilyRepository.requireIdentifier(memberId, 'memberId');
    return this.gate.run(async (): Promise<void> => {
      await this.rdb.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
        const family = await this.readFamily(tx, checkedFamily);
        if (family === undefined) {
          throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
        }
        const member = await this.readMember(tx, checkedFamily, checkedMember);
        if (member === undefined) {
          throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'memberId')]);
        }
        if (member.role === role) {
          return;
        }
        if (role === MemberRole.GUEST && member.expiresAt === undefined) {
          // A GUEST needs an expiry; role-only promotion is invalid (DES-A §5.1.7).
          throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'expiresAt');
        }
        if (family.ownerMemberId === checkedMember && role !== MemberRole.ADMIN) {
          // The owner pointer must never dangle. Transfer ownership explicitly
          // first (DES-B §3.3.1/§3.3.6; wp-026 R-09).
          throw AppErrors.of('AUTH_RBAC_DENIED', []);
        }
        if (member.role === MemberRole.ADMIN && role !== MemberRole.ADMIN) {
          await FamilyRepository.requireAnotherAdmin(tx, checkedFamily, checkedMember);
        }
        await tx.execute('UPDATE family_member SET role = ? WHERE member_id = ?',
          [role, checkedMember]);
      });
    });
  }

  async updateMemberStatus(familyId: string, memberId: string,
    status: MemberStatus): Promise<void> {
    this.ensureInitialized();
    const checkedFamily = FamilyRepository.requireIdentifier(familyId, 'familyId');
    const checkedMember = FamilyRepository.requireIdentifier(memberId, 'memberId');
    return this.gate.run(async (): Promise<void> => {
      await this.rdb.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
        const family = await this.readFamily(tx, checkedFamily);
        if (family === undefined) {
          throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
        }
        const member = await this.readMember(tx, checkedFamily, checkedMember);
        if (member === undefined) {
          throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'memberId')]);
        }
        if (family.ownerMemberId === checkedMember && status !== MemberStatus.ACTIVE) {
          // The owner must stay an ACTIVE ADMIN until transferAdmin runs.
          throw AppErrors.of('AUTH_RBAC_DENIED', []);
        }
        await tx.execute('UPDATE family_member SET status = ? WHERE member_id = ?',
          [status, checkedMember]);
      });
    });
  }

  async extendGuestExpiry(familyId: string, memberId: string, expiresAt: string): Promise<void> {
    this.ensureInitialized();
    const checkedFamily = FamilyRepository.requireIdentifier(familyId, 'familyId');
    const checkedMember = FamilyRepository.requireIdentifier(memberId, 'memberId');
    DateTimeUtil.parseUtcCompact(expiresAt);
    return this.gate.run(async (): Promise<void> => {
      await this.rdb.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
        const member = await this.readMember(tx, checkedFamily, checkedMember);
        if (member === undefined) {
          throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'memberId')]);
        }
        if (member.role !== MemberRole.GUEST) {
          throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'role');
        }
        // EXPIRED -> ACTIVE is the only legal automatic-looking transition and
        // it is still an explicit Admin action (DES-A §5.3 invariant 9).
        await tx.execute('UPDATE family_member SET expires_at = ?, status = ? ' +
          'WHERE member_id = ?', [expiresAt, MemberStatus.ACTIVE, checkedMember]);
      });
    });
  }

  async expireGuests(familyId: string, nowMs: number): Promise<number> {
    this.ensureInitialized();
    const checked = FamilyRepository.requireIdentifier(familyId, 'familyId');
    if (!Number.isFinite(nowMs) || nowMs < 0) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'nowMs');
    }
    return this.gate.run(async (): Promise<number> => {
      return this.rdb.transaction<number>(async (tx: RdbTransaction): Promise<number> => {
        const members = await this.listMembersInTransaction(tx, checked);
        let changed = 0;
        for (let index = 0; index < members.length; index++) {
          const member = members[index];
          if (member.role !== MemberRole.GUEST || member.status !== MemberStatus.ACTIVE ||
            member.expiresAt === undefined) {
            continue;
          }
          if (DateTimeUtil.parseUtcCompact(member.expiresAt) <= nowMs) {
            await tx.execute('UPDATE family_member SET status = ? WHERE member_id = ?',
              [MemberStatus.EXPIRED, member.memberId]);
            changed++;
          }
        }
        return changed;
      });
    });
  }

  // ---- Invitations --------------------------------------------------------

  async listInvitations(familyId: string): Promise<ReadonlyArray<InvitationRecord>> {
    this.ensureInitialized();
    const checked = FamilyRepository.requireIdentifier(familyId, 'familyId');
    return this.gate.run(async (): Promise<ReadonlyArray<InvitationRecord>> => {
      const rows = await this.rdb.query('SELECT ' + INVITATION_COLUMNS +
        ' FROM invitation WHERE family_id = ? ORDER BY invite_id ASC', [checked]);
      return FamilyRepository.mapInvitations(rows);
    });
  }

  async listInvitationsByFamily(familyId: string): Promise<ReadonlyArray<InvitationRecord>> {
    return this.listInvitations(familyId);
  }

  async getInvitation(inviteId: string): Promise<InvitationRecord | undefined> {
    this.ensureInitialized();
    const checked = FamilyRepository.requireIdentifier(inviteId, 'inviteId');
    return this.gate.run(async (): Promise<InvitationRecord | undefined> => {
      return this.readInvitation(this.rdb, checked);
    });
  }

  async putInvitation(record: InvitationRecord): Promise<void> {
    this.ensureInitialized();
    return this.gate.run(async (): Promise<void> => {
      await this.rdb.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
        await FamilyRepository.insertInvitation(tx, record);
      });
    });
  }

  async markInvitationStatus(inviteId: string, status: InvitationStatus,
    patch?: InvitationPatch): Promise<void> {
    this.ensureInitialized();
    const checked = FamilyRepository.requireIdentifier(inviteId, 'inviteId');
    return this.gate.run(async (): Promise<void> => {
      await this.rdb.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
        await this.markInvitationStatusInTransaction(tx, checked, status, patch);
      });
    });
  }

  async incrementUsedCount(inviteId: string): Promise<number> {
    this.ensureInitialized();
    const checked = FamilyRepository.requireIdentifier(inviteId, 'inviteId');
    return this.gate.run(async (): Promise<number> => {
      return this.rdb.transaction<number>(async (tx: RdbTransaction): Promise<number> => {
        const record = await this.readInvitation(tx, checked);
        if (record === undefined) {
          throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'inviteId')]);
        }
        if (record.usedCount >= record.maxUses) {
          throw AppErrors.of('INVITE_MAX_USES', []);
        }
        const next = record.usedCount + 1;
        await tx.execute('UPDATE invitation SET used_count = ? WHERE invite_id = ?',
          [next, checked]);
        return next;
      });
    });
  }

  async applyReceipt(inviteId: string, patch: InvitationPatch): Promise<void> {
    this.ensureInitialized();
    const checked = FamilyRepository.requireIdentifier(inviteId, 'inviteId');
    return this.gate.run(async (): Promise<void> => {
      await this.rdb.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
        await this.applyReceiptInTransaction(tx, checked, patch);
      });
    });
  }

  /**
   * Validates the invitation state and applies the receipt + member activation
   * in ONE transaction. A REVOKED/EXPIRED/exhausted invitation never leaves a
   * new ACTIVE member behind (wp-026 R-01).
   */
  async applyReceiptAndEnsureMember(inviteId: string, newMember: FamilyMember,
    patch: InvitationPatch): Promise<void> {
    this.ensureInitialized();
    const checked = FamilyRepository.requireIdentifier(inviteId, 'inviteId');
    return this.gate.run(async (): Promise<void> => {
      await this.rdb.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
        // Receipt validation runs first; a failure rolls back everything below.
        await this.applyReceiptInTransaction(tx, checked, patch);
        const existing = await this.readMember(tx, newMember.familyId, newMember.memberId);
        if (existing === undefined) {
          await this.upsertMemberInTransaction(tx, newMember);
        } else if (existing.status !== MemberStatus.ACTIVE) {
          await this.upsertMemberInTransaction(tx, new FamilyMember(existing.memberId,
            existing.familyId, existing.userId, existing.displayName, existing.role,
            MemberStatus.ACTIVE, existing.joinedAt, existing.allowedRoomIds,
            existing.expiresAt, existing.memberDeviceId, existing.joinedVia,
            existing.secretsVersion, existing.lastSyncedAt));
        }
      });
    });
  }

  async markSynced(memberId: string, atMs: number): Promise<void> {
    this.ensureInitialized();
    const checked = FamilyRepository.requireIdentifier(memberId, 'memberId');
    if (!Number.isFinite(atMs) || atMs < 0) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'atMs');
    }
    const text = DateTimeUtil.formatUtcCompact(atMs);
    return this.gate.run(async (): Promise<void> => {
      const rows = await this.rdb.query('SELECT member_id FROM family_member WHERE member_id = ?',
        [checked]);
      if (rows.length === 0) {
        throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'memberId')]);
      }
      // Contact-based convergence only. This is NOT an online/heartbeat signal.
      await this.rdb.execute('UPDATE family_member SET last_synced_at = ? WHERE member_id = ?',
        [text, checked]);
    });
  }

  // ---- Increment methods (DES-B §3.1.2) ----------------------------------

  async transferAdmin(familyId: string, currentAdminMemberId: string,
    newAdminMemberId: string): Promise<void> {
    this.ensureInitialized();
    const checkedFamily = FamilyRepository.requireIdentifier(familyId, 'familyId');
    const current = FamilyRepository.requireIdentifier(currentAdminMemberId, 'currentAdminMemberId');
    const next = FamilyRepository.requireIdentifier(newAdminMemberId, 'newAdminMemberId');
    return this.gate.run(async (): Promise<void> => {
      await this.rdb.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
        const family = await this.readFamily(tx, checkedFamily);
        if (family === undefined) {
          throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
        }
        const currentMember = await this.readMember(tx, checkedFamily, current);
        const newMember = await this.readMember(tx, checkedFamily, next);
        if (currentMember === undefined || newMember === undefined ||
          currentMember.role !== MemberRole.ADMIN ||
          currentMember.status !== MemberStatus.ACTIVE ||
          newMember.status !== MemberStatus.ACTIVE) {
          throw AppErrors.of('AUTH_RBAC_DENIED', []);
        }
        if (family.ownerMemberId !== current) {
          throw AppErrors.of('AUTH_RBAC_DENIED', []);
        }
        await tx.execute('UPDATE family_member SET role = ? WHERE member_id = ?',
          [MemberRole.MEMBER, current]);
        await tx.execute('UPDATE family_member SET role = ? WHERE member_id = ?',
          [MemberRole.ADMIN, next]);
        await tx.execute('UPDATE family SET owner_member_id = ?, updated_at = ? ' +
          'WHERE family_id = ?',
        [next, DateTimeUtil.nowUtcCompact(this.clock), checkedFamily]);
      });
    });
  }

  async listMemberRoomGrants(familyId: string, memberId: string): Promise<ReadonlyArray<string>> {
    const member = await this.getMember(familyId, memberId);
    if (member === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'memberId')]);
    }
    return member.allowedRoomIds;
  }

  // ---- Transaction-context port method (MemberRoomGrantPort) -------------

  async removeRoomGrant(tx: RdbTransaction, familyId: string, roomId: string): Promise<number> {
    const checkedFamily = FamilyRepository.requireIdentifier(familyId, 'familyId');
    const checkedRoom = FamilyRepository.requireRoomId(roomId);
    const members = await this.listMembersInTransaction(tx, checkedFamily);
    let affected = 0;
    for (let index = 0; index < members.length; index++) {
      const member = members[index];
      let found = false;
      const kept: string[] = [];
      for (let grantIndex = 0; grantIndex < member.allowedRoomIds.length; grantIndex++) {
        const grant = member.allowedRoomIds[grantIndex];
        if (grant === checkedRoom) {
          found = true;
        } else {
          kept.push(grant);
        }
      }
      if (found) {
        await tx.execute('UPDATE family_member SET allowed_room_ids_json = ? ' +
          'WHERE member_id = ?', [SqlJson.stringArray(kept), member.memberId]);
        affected++;
      }
    }
    return affected;
  }

  async removeFamilyLocal(tx: RdbTransaction, familyId: string): Promise<ReadonlyArray<string>> {
    const checked = FamilyRepository.requireIdentifier(familyId, 'familyId');
    const family = await this.readFamily(tx, checked);
    if (family === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
    }
    const gatewayIds: string[] = [];
    for (let index = 0; index < family.gatewayIds.length; index++) {
      gatewayIds.push(family.gatewayIds[index]);
    }
    await tx.execute('DELETE FROM invitation WHERE family_id = ?', [checked]);
    await tx.execute('DELETE FROM family_member WHERE family_id = ?', [checked]);
    await tx.execute('DELETE FROM family WHERE family_id = ?', [checked]);
    return gatewayIds;
  }

  async removeMemberLocal(tx: RdbTransaction, familyId: string,
    memberId: string): Promise<void> {
    const checkedFamily = FamilyRepository.requireIdentifier(familyId, 'familyId');
    const checkedMember = FamilyRepository.requireIdentifier(memberId, 'memberId');
    await this.removeMemberInTransaction(tx, checkedFamily, checkedMember);
  }

  // ---- Transaction-context helpers (no gate, no nested transaction) ------

  async readFamily(tx: RdbTransaction, familyId: string): Promise<Family | undefined> {
    const rows = await tx.query('SELECT ' + FAMILY_COLUMNS + ' FROM family WHERE family_id = ?',
      [familyId]);
    if (rows.length === 0) {
      return undefined;
    }
    return FamilyRepository.familyFromRow(rows[0]);
  }

  async readMember(tx: RdbTransaction, familyId: string,
    memberId: string): Promise<FamilyMember | undefined> {
    const rows = await tx.query('SELECT ' + MEMBER_COLUMNS +
      ' FROM family_member WHERE member_id = ?', [memberId]);
    if (rows.length === 0) {
      return undefined;
    }
    const member = FamilyRepository.memberFromRow(rows[0]);
    if (member.familyId !== familyId) {
      return undefined;
    }
    return member;
  }

  async readInvitation(tx: RdbTransaction, inviteId: string): Promise<InvitationRecord | undefined> {
    const rows = await tx.query('SELECT ' + INVITATION_COLUMNS +
      ' FROM invitation WHERE invite_id = ?', [inviteId]);
    if (rows.length === 0) {
      return undefined;
    }
    return FamilyRepository.invitationFromRow(rows[0]);
  }

  async listMembersInTransaction(tx: RdbTransaction,
    familyId: string): Promise<ReadonlyArray<FamilyMember>> {
    const rows = await tx.query('SELECT ' + MEMBER_COLUMNS +
      ' FROM family_member WHERE family_id = ? ORDER BY joined_at ASC', [familyId]);
    const members: FamilyMember[] = [];
    for (let index = 0; index < rows.length; index++) {
      members.push(FamilyRepository.memberFromRow(rows[index]));
    }
    return members;
  }

  async upsertMemberInTransaction(tx: RdbTransaction, member: FamilyMember): Promise<void> {
    const family = await this.readFamily(tx, member.familyId);
    if (family === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
    }
    const existingRows = await tx.query('SELECT ' + MEMBER_COLUMNS +
      ' FROM family_member WHERE member_id = ?', [member.memberId]);
    if (family.ownerMemberId === member.memberId &&
      (member.role !== MemberRole.ADMIN || member.status !== MemberStatus.ACTIVE)) {
      // Never let an upsert demote or deactivate the owner pointer target
      // until transferAdmin runs (wp-026 R-09).
      throw AppErrors.of('AUTH_RBAC_DENIED', []);
    }
    if (existingRows.length > 0) {
      const existing = FamilyRepository.memberFromRow(existingRows[0]);
      if (existing.familyId !== member.familyId) {
        throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
      }
      if (existing.role === MemberRole.ADMIN && member.role !== MemberRole.ADMIN) {
        await FamilyRepository.requireAnotherAdmin(tx, member.familyId, member.memberId);
      }
    }
    await FamilyRepository.insertMember(tx, member);
  }

  async applyReceiptInTransaction(tx: RdbTransaction, inviteId: string,
    patch: InvitationPatch, nowMs?: number): Promise<void> {
    const record = await this.readInvitation(tx, inviteId);
    if (record === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'inviteId')]);
    }
    if (record.status === InvitationStatus.REVOKED) {
      throw AppErrors.of('INVITE_REVOKED', []);
    }
    if (record.status === InvitationStatus.EXPIRED) {
      throw AppErrors.of('INVITE_EXPIRED', []);
    }
    const now = nowMs === undefined ? this.clock.nowMs() : nowMs;
    if (DateTimeUtil.parseUtcCompact(record.expireAt) <= now) {
      // ADR-003 §5.2 clock trust boundary: an Admin receipt import after expiry
      // is rejected before any member or invitation write (wp-026 R-01/R-10).
      throw AppErrors.of('INVITE_EXPIRED', []);
    }
    if (record.usedCount >= record.maxUses) {
      throw AppErrors.of('INVITE_MAX_USES', []);
    }
    if (patch.acceptedAt === undefined || patch.acceptedByMemberId === undefined ||
      patch.receipt === undefined || patch.receipt.length === 0) {
      throw AppErrors.of('INVITE_RECEIPT_INVALID', []);
    }
    DateTimeUtil.parseUtcCompact(patch.acceptedAt);
    // D-022: ACCEPTED records each receipt and is not a terminal state. The
    // invitation stays usable while usedCount < maxUses and not expired.
    await tx.execute('UPDATE invitation SET status = ?, accepted_at = ?, ' +
      'accepted_by_member_id = ?, receipt = ?, used_count = ? WHERE invite_id = ?',
    [InvitationStatus.ACCEPTED, patch.acceptedAt, patch.acceptedByMemberId, patch.receipt,
      record.usedCount + 1, inviteId]);
  }

  // ---- Internals ----------------------------------------------------------

  private async switchActiveFamilyInternal(familyId: string): Promise<void> {
    const family = await this.readFamily(this.rdb, familyId);
    if (family === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
    }
    try {
      await this.preferences.putString(StorageConstants.PREF_ACTIVE_FAMILY_ID, familyId);
      await this.preferences.flush();
    } catch (error) {
      throw FamilyRepository.storageError(error as Error);
    }
  }

  private async writeGatewayIds(familyId: string, gatewayIds: ReadonlyArray<string>): Promise<void> {
    const now = DateTimeUtil.nowUtcCompact(this.clock);
    await this.rdb.execute('UPDATE family SET gateway_ids_json = ?, updated_at = ? ' +
      'WHERE family_id = ?', [SqlJson.stringArray(gatewayIds), now, familyId]);
  }

  private async removeMemberInTransaction(tx: RdbTransaction, familyId: string,
    memberId: string): Promise<void> {
    const family = await this.readFamily(tx, familyId);
    if (family === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
    }
    const member = await this.readMember(tx, familyId, memberId);
    if (member === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'memberId')]);
    }
    if (family.ownerMemberId === memberId) {
      // The owner pointer must never dangle. transferAdmin must run first
      // (DES-B §3.3.1/§3.3.6; wp-026 R-09).
      throw AppErrors.of('AUTH_RBAC_DENIED', []);
    }
    if (member.role === MemberRole.ADMIN) {
      await FamilyRepository.requireAnotherAdmin(tx, familyId, memberId);
    }
    await tx.execute('DELETE FROM family_member WHERE member_id = ?', [memberId]);
  }

  private static async requireAnotherAdmin(tx: RdbTransaction, familyId: string,
    excludedMemberId: string): Promise<void> {
    const rows = await tx.query('SELECT member_id, role FROM family_member WHERE family_id = ?',
      [familyId]);
    let admins = 0;
    for (let index = 0; index < rows.length; index++) {
      const memberId = SqlCells.requiredString(rows[index], 'member_id');
      if (memberId !== excludedMemberId &&
        SqlCells.requiredString(rows[index], 'role') === MemberRole.ADMIN) {
        admins++;
      }
    }
    if (admins < 1) {
      // DES-A §11.2: never remove/demote the last local ADMIN.
      throw AppErrors.of('AUTH_RBAC_DENIED', []);
    }
  }

  private static async insertMember(tx: RdbTransaction, member: FamilyMember): Promise<void> {
    await tx.execute('INSERT OR REPLACE INTO family_member (' + MEMBER_COLUMNS + ') ' +
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [member.memberId, member.familyId, member.userId, member.displayName, member.role,
      member.status, member.joinedAt, SqlJson.stringArray(member.allowedRoomIds),
      member.expiresAt === undefined ? null : member.expiresAt,
      member.memberDeviceId === undefined ? null : member.memberDeviceId,
      member.joinedVia === undefined ? null : member.joinedVia,
      member.secretsVersion === undefined ? null : member.secretsVersion,
      member.lastSyncedAt === undefined ? null : member.lastSyncedAt]);
  }

  private static async insertInvitation(tx: RdbTransaction, record: InvitationRecord):
    Promise<void> {
    await tx.execute('INSERT OR REPLACE INTO invitation (' + INVITATION_COLUMNS + ') ' +
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [record.inviteId, record.familyId, record.familyName, record.inviterId, record.targetRole,
      SqlJson.stringArray(record.allowedRoomIds), record.mode, record.status, record.expireAt,
      record.maxUses, record.usedCount, record.payloadString, record.seedAlias,
      record.codeSaltHex === undefined ? null : record.codeSaltHex,
      record.kdfIterations === undefined ? null : record.kdfIterations,
      record.memberId === undefined ? null : record.memberId,
      record.acceptedAt === undefined ? null : record.acceptedAt,
      record.acceptedByMemberId === undefined ? null : record.acceptedByMemberId,
      record.receipt === undefined ? null : record.receipt,
      record.revokedAt === undefined ? null : record.revokedAt,
      record.revokedReason === undefined ? null : record.revokedReason]);
  }

  private async markInvitationStatusInTransaction(tx: RdbTransaction, inviteId: string,
    status: InvitationStatus, patch?: InvitationPatch): Promise<void> {
    const record = await this.readInvitation(tx, inviteId);
    if (record === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'inviteId')]);
    }
    if (record.status === status) {
      return;
    }
    if (record.status === InvitationStatus.REVOKED ||
      record.status === InvitationStatus.EXPIRED) {
      // REVOKED/EXPIRED are terminal; ACCEPTED is a receipt record, not a
      // terminal state (D-022), so an accepted invitation may still be revoked
      // or expired while uses remain.
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'status')]);
    }
    if (status === InvitationStatus.ACCEPTED) {
      if (patch === undefined || patch.acceptedAt === undefined ||
        patch.acceptedByMemberId === undefined || patch.receipt === undefined) {
        throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'acceptedAt')]);
      }
    }
    let sql = 'UPDATE invitation SET status = ?';
    const args: Array<string | number | null> = [status];
    if (patch !== undefined && patch.acceptedAt !== undefined) {
      sql += ', accepted_at = ?';
      args.push(patch.acceptedAt);
    }
    if (patch !== undefined && patch.acceptedByMemberId !== undefined) {
      sql += ', accepted_by_member_id = ?';
      args.push(patch.acceptedByMemberId);
    }
    if (patch !== undefined && patch.receipt !== undefined) {
      sql += ', receipt = ?';
      args.push(patch.receipt);
    }
    if (patch !== undefined && patch.revokedAt !== undefined) {
      sql += ', revoked_at = ?';
      args.push(patch.revokedAt);
    }
    if (patch !== undefined && patch.revokedReason !== undefined) {
      sql += ', revoked_reason = ?';
      args.push(patch.revokedReason);
    }
    sql += ' WHERE invite_id = ?';
    args.push(inviteId);
    await tx.execute(sql, args);
  }

  private static familyFromRow(row: RdbRow): Family {
    try {
      return new Family(SqlCells.requiredString(row, 'family_id'),
        SqlCells.requiredString(row, 'family_name'),
        SqlCells.requiredString(row, 'owner_member_id'),
        SqlCells.requiredString(row, 'created_at'),
        SqlCells.requiredString(row, 'updated_at'),
        SqlJson.parseStringArray(SqlCells.requiredString(row, 'gateway_ids_json')));
    } catch (error) {
      throw FamilyRepository.modelReadError(error as Error);
    }
  }

  private static memberFromRow(row: RdbRow): FamilyMember {
    try {
      return new FamilyMember(SqlCells.requiredString(row, 'member_id'),
        SqlCells.requiredString(row, 'family_id'),
        SqlCells.requiredString(row, 'user_id'),
        SqlCells.requiredString(row, 'display_name'),
        FamilyRepository.memberRole(SqlCells.requiredString(row, 'role')),
        FamilyRepository.memberStatus(SqlCells.requiredString(row, 'status')),
        SqlCells.requiredString(row, 'joined_at'),
        SqlJson.parseStringArray(SqlCells.requiredString(row, 'allowed_room_ids_json')),
        SqlCells.optionalString(row, 'expires_at'),
        SqlCells.optionalString(row, 'member_device_id'),
        SqlCells.optionalString(row, 'joined_via'),
        SqlCells.optionalString(row, 'secrets_version'),
        SqlCells.optionalString(row, 'last_synced_at'));
    } catch (error) {
      throw FamilyRepository.modelReadError(error as Error);
    }
  }

  private static invitationFromRow(row: RdbRow): InvitationRecord {
    try {
      return new InvitationRecord(SqlCells.requiredString(row, 'invite_id'),
        SqlCells.requiredString(row, 'family_id'),
        SqlCells.requiredString(row, 'family_name'),
        SqlCells.requiredString(row, 'inviter_id'),
        FamilyRepository.memberRole(SqlCells.requiredString(row, 'target_role')),
        SqlJson.parseStringArray(SqlCells.requiredString(row, 'allowed_room_ids_json')),
        FamilyRepository.inviteMode(SqlCells.requiredString(row, 'mode')),
        FamilyRepository.invitationStatus(SqlCells.requiredString(row, 'status')),
        SqlCells.requiredString(row, 'expire_at'),
        SqlCells.requiredNumber(row, 'max_uses'),
        SqlCells.requiredNumber(row, 'used_count'),
        SqlCells.requiredString(row, 'payload_string'),
        SqlCells.requiredString(row, 'seed_alias'),
        SqlCells.optionalString(row, 'code_salt_hex'),
        SqlCells.optionalNumber(row, 'kdf_iterations'),
        SqlCells.optionalString(row, 'member_id'),
        SqlCells.optionalString(row, 'accepted_at'),
        SqlCells.optionalString(row, 'accepted_by_member_id'),
        SqlCells.optionalString(row, 'receipt'),
        SqlCells.optionalString(row, 'revoked_at'),
        SqlCells.optionalString(row, 'revoked_reason'));
    } catch (error) {
      throw FamilyRepository.modelReadError(error as Error);
    }
  }

  private static mapFamilies(rows: ReadonlyArray<RdbRow>): ReadonlyArray<Family> {
    const families: Family[] = [];
    for (let index = 0; index < rows.length; index++) {
      families.push(FamilyRepository.familyFromRow(rows[index]));
    }
    return families;
  }

  private static mapInvitations(rows: ReadonlyArray<RdbRow>): ReadonlyArray<InvitationRecord> {
    const invitations: InvitationRecord[] = [];
    for (let index = 0; index < rows.length; index++) {
      invitations.push(FamilyRepository.invitationFromRow(rows[index]));
    }
    return invitations;
  }

  private static memberRole(value: string): MemberRole {
    if (value === MemberRole.ADMIN || value === MemberRole.MEMBER || value === MemberRole.GUEST) {
      return value as MemberRole;
    }
    throw AppErrors.of('STORAGE_RDB_ERROR', []);
  }

  private static memberStatus(value: string): MemberStatus {
    if (value === MemberStatus.ACTIVE || value === MemberStatus.INVITED ||
      value === MemberStatus.DISABLED || value === MemberStatus.EXPIRED) {
      return value as MemberStatus;
    }
    throw AppErrors.of('STORAGE_RDB_ERROR', []);
  }

  private static invitationStatus(value: string): InvitationStatus {
    if (value === InvitationStatus.PENDING || value === InvitationStatus.ACCEPTED ||
      value === InvitationStatus.EXPIRED || value === InvitationStatus.REVOKED) {
      return value as InvitationStatus;
    }
    throw AppErrors.of('STORAGE_RDB_ERROR', []);
  }

  private static inviteMode(value: string): InviteMode {
    if (value === InviteMode.KEY_WRAP) {
      return InviteMode.KEY_WRAP;
    }
    if (value === InviteMode.CODE_KEK) {
      return InviteMode.CODE_KEK;
    }
    throw AppErrors.of('STORAGE_RDB_ERROR', []);
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

  private static requireIdentifier(value: string, field: string): string {
    if (value.length === 0 || value.length > 63 || value.indexOf(':') >= 0 ||
      !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(value)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', field);
    }
    return value;
  }

  private static requireGatewayId(value: string): string {
    if (value.length === 0 || value.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      value.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(value)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'gatewayId');
    }
    return value;
  }

  private static requireRoomId(value: string): string {
    if (!UuidUtil.isValidUuid(value)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'roomId');
    }
    return value;
  }

  private static modelReadError(error: Error): Error {
    if (error instanceof AppError) {
      return AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    return AppErrors.of('STORAGE_RDB_ERROR', []);
  }

  private static storageError(error: Error): Error {
    if (error instanceof AppError) {
      return error;
    }
    return AppErrors.of('STORAGE_RDB_ERROR', []);
  }

  private ensureInitialized(): void {
    if (!this.initialized) {
      throw AppErrors.of('STORAGE_NOT_INITIALIZED', []);
    }
  }
}
