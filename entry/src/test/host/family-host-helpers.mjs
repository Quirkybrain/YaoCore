/*
 * YaoCore T-13 host test helpers (C-12/C-13).
 * Producer: agent:implementation-engineer | Task: T-13 / wp-049-family
 *
 * PUBLIC TEST DATA ONLY. No real family data, secrets, or platform calls.
 */
import { AppErrors } from '../../main/ets/common/types/AppError.ets';
import { BytesUtil } from '../../main/ets/common/utils/BytesUtil.ets';
import { DateTimeUtil } from '../../main/ets/common/utils/DateTimeUtil.ets';
import { MigrationRegistry } from '../../main/ets/service/storage/MigrationRegistry.ets';
import { StorageService } from '../../main/ets/service/storage/StorageService.ets';
import { AuthPolicy } from '../../main/ets/service/auth/AuthModels.ets';
import { AuthService } from '../../main/ets/service/auth/AuthService.ets';
import { InviteService } from '../../main/ets/service/invite/InviteService.ets';
import { InviteServiceAdapter } from '../../main/ets/service/invite/InviteServiceAdapter.ets';
import { FamilyMember, MemberRole, MemberStatus } from '../../main/ets/model/FamilyModels.ets';
import { HostCrypto } from './host-crypto.mjs';
import { T0 } from './domain-helpers.mjs';

export const GATEWAY_ID = 'gw-1';
export const ROOM_A = '22222222-2222-4222-8222-222222222222';
export const ROOM_B = '33333333-3333-4333-8333-333333333333';
export const GATEWAY_SECRET_HEX = '00112233445566778899aabbccddeeff';
export const PASSWORD = 'correct-horse-1';

export async function newAuth(harness) {
  const storage = new StorageService(harness.preferences, harness.rdb, harness.secrets,
    new MigrationRegistry());
  const auth = new AuthService(new HostCrypto(), storage, harness.families, harness.clock,
    harness.random, harness.ids, AuthPolicy.defaults());
  await auth.initialize();
  return auth;
}

export async function seedFamily(harness, name = 'Home', ownerName = 'Alice') {
  return harness.families.createFamily(name, harness.ids.newId(), ownerName);
}

export async function addMember(harness, familyId, role, options = {}) {
  const memberId = options.memberId === undefined ? harness.ids.newId() : options.memberId;
  const expiresAt = options.expiresAt === undefined ? undefined : options.expiresAt;
  const rooms = options.allowedRoomIds === undefined ? [] : options.allowedRoomIds;
  const member = new FamilyMember(memberId, familyId, memberId,
    options.displayName === undefined ? 'Member' : options.displayName,
    role, options.status === undefined ? MemberStatus.ACTIVE : options.status,
    T0, rooms, expiresAt);
  await harness.families.upsertMember(member);
  return member;
}

export class FakeGatewayCredentials {
  constructor() {
    this.secrets = new Map();
    this.tls = new Map();
  }

  setSecret(gatewayId, hex) {
    this.secrets.set(gatewayId, BytesUtil.hexToBytes(hex));
  }

  setTls(gatewayId, material) {
    this.tls.set(gatewayId, material);
  }

  async withCommandSecret(gatewayId, fn) {
    const stored = this.secrets.get(gatewayId);
    if (stored === undefined) {
      throw AppErrors.of('GATEWAY_NOT_BOUND', []);
    }
    const copy = BytesUtil.copyOf(stored);
    try {
      return await fn(copy);
    } finally {
      BytesUtil.zeroize(copy);
    }
  }

  async tlsMaterial(gatewayId) {
    return this.tls.get(gatewayId);
  }
}

export class FakeInvitationApplications {
  constructor() {
    this.applied = [];
  }

  async applyInvitedGateway(entry) {
    this.applied.push({
      gatewayId: entry.gatewayId,
      familyId: entry.familyId,
      gatewayName: entry.gatewayName,
      secretHex: entry.commandSecret.toHex(),
      pins: entry.tls === undefined ? undefined : entry.tls.pins,
      port: entry.tls === undefined ? undefined : entry.tls.port,
    });
  }
}

export async function inviteSetup(harness, options = {}) {
  const family = await seedFamily(harness, options.familyName, options.ownerName);
  harness.routes.add(GATEWAY_ID, family.familyId, 'Test Gateway');
  const credentials = new FakeGatewayCredentials();
  credentials.setSecret(GATEWAY_ID, GATEWAY_SECRET_HEX);
  const applications = new FakeInvitationApplications();
  const service = new InviteService(new HostCrypto(), harness.secrets, harness.families,
    harness.routes, credentials, applications, harness.clock, harness.random, harness.ids);
  const adapter = new InviteServiceAdapter(service);
  return { family, credentials, applications, service, adapter };
}

/**
 * Member-device service on its own harness. The harness has migrations only;
 * no family/member rows are pre-seeded (F-02 new-device path).
 */
export function newMemberInvite(harness) {
  const credentials = new FakeGatewayCredentials();
  const applications = new FakeInvitationApplications();
  const service = new InviteService(new HostCrypto(), harness.secrets, harness.families,
    harness.routes, credentials, applications, harness.clock, harness.random, harness.ids);
  return { service, adapter: new InviteServiceAdapter(service), credentials, applications };
}

export function nowCompact(harness) {
  return DateTimeUtil.formatUtcCompact(harness.clock.nowMs());
}

export async function expectRejectCode(promise, code) {
  let captured;
  try {
    await promise;
  } catch (error) {
    captured = error;
  }
  if (captured === undefined) {
    throw new Error('expected ' + code + ', promise resolved');
  }
  if (captured.code !== code) {
    throw new Error('expected ' + code + ', got ' + String(captured.code));
  }
  return captured;
}

export function expectThrowCode(fn, code) {
  try {
    fn();
  } catch (error) {
    if (error.code !== code) {
      throw new Error('expected ' + code + ', got ' + String(error.code));
    }
    return error;
  }
  throw new Error('expected ' + code + ', function did not throw');
}

export const ROLE_ADMIN = MemberRole.ADMIN;
export const ROLE_MEMBER = MemberRole.MEMBER;
export const ROLE_GUEST = MemberRole.GUEST;
