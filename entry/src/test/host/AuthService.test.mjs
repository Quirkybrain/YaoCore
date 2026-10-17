/*
 * YaoCore C-12 AuthService host tests.
 * Producer: agent:implementation-engineer | Task: T-13 / wp-049-family
 * Contract: DES-A §12.1-§12.6; NFR-4.2; DP-04/DP-06; SEC-N23.
 *
 * PUBLIC TEST DATA ONLY. PBKDF2 always uses the real 120000-iteration product
 * path over the Node host oracle.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { newDomainHarness } from '../domain/DomainHarness.ets';
import { CreateProfileInput } from '../../main/ets/service/auth/AuthModels.ets';
import { DeviceKey } from '../../main/ets/model/DeviceKey.ets';
import { DeviceState, RoomRef } from '../../main/ets/model/DeviceState.ets';
import { DateTimeUtil } from '../../main/ets/common/utils/DateTimeUtil.ets';
import { MemberRole } from '../../main/ets/model/FamilyModels.ets';
import { snapshotDevice, unknownTypeSnapshot } from './domain-helpers.mjs';
import {
  addMember,
  expectRejectCode,
  newAuth,
  PASSWORD,
  ROLE_ADMIN,
  ROLE_GUEST,
  ROLE_MEMBER,
  ROOM_A,
  ROOM_B,
  seedFamily
} from './family-host-helpers.mjs';

const NOW = Date.UTC(2026, 9, 17, 8, 0, 0);

async function setup() {
  const harness = await newDomainHarness(NOW);
  const auth = await newAuth(harness);
  const family = await seedFamily(harness);
  return { harness, auth, family };
}

async function profileFor(auth, harness, familyId, memberId, role,
  password = PASSWORD) {
  return auth.createProfile(new CreateProfileInput(harness.ids.newId(), familyId, memberId,
    'User ' + role, password, role));
}

function device(familyId, roomId, options = {}) {
  const deviceId = options.deviceId === undefined ? 'dev-1' : options.deviceId;
  const snapshot = options.unsupported === true ? unknownTypeSnapshot(deviceId) :
    snapshotDevice(deviceId);
  return new DeviceState(new DeviceKey('gw-1', deviceId), familyId, snapshot, 'Lamp',
    roomId, options.enabled === undefined ? true : options.enabled,
    options.unassigned === undefined ? roomId.length === 0 : options.unassigned, false);
}

test('C12_profile_pbkdf2ParamsAndUnifiedPasswordErrors', async () => {
  const { harness, auth, family } = await setup();
  const profile = await profileFor(auth, harness, family.familyId, family.ownerMemberId,
    MemberRole.ADMIN);
  assert.equal(profile.iterations, 120000);
  assert.match(profile.saltHex, /^[0-9a-f]{32}$/);
  const rows = await harness.rdb.query('SELECT salt_hex, iterations FROM auth_profile ' +
    'WHERE profile_id = ?', [profile.profileId]);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].get('iterations'), 120000);
  assert.equal(rows[0].get('salt_hex'), profile.saltHex);

  const hashBytes = await harness.secrets.withSecret(profile.hashAlias,
    async (secret) => secret.length);
  assert.equal(hashBytes, 32);

  assert.equal(await auth.verifyPassword(profile.profileId, PASSWORD), true);
  assert.equal(await auth.verifyPassword(profile.profileId, 'wrong-password-1'), false);
  await expectRejectCode(auth.unlock(profile.profileId, 'wrong-password-1'),
    'AUTH_PASSWORD_INVALID');
  await expectRejectCode(auth.unlock('11111111-1111-4111-8111-111111111111', PASSWORD),
    'AUTH_PASSWORD_INVALID');
  await expectRejectCode(profileFor(auth, harness, family.familyId, family.ownerMemberId,
    MemberRole.ADMIN), 'AUTH_PROFILE_EXISTS');
});

test('C12_changePassword_restoresOnWrongOldAndLocksAll', async () => {
  const { harness, auth, family } = await setup();
  const profile = await profileFor(auth, harness, family.familyId, family.ownerMemberId,
    MemberRole.ADMIN);
  const session = await auth.unlock(profile.profileId, PASSWORD);
  assert.equal(auth.getActiveSession().sessionId, session.sessionId);

  await expectRejectCode(auth.changePassword(profile.profileId, 'wrong-old-1',
    'brand-new-pass-2'), 'AUTH_PASSWORD_INVALID');
  assert.equal(await auth.verifyPassword(profile.profileId, PASSWORD), true);

  await auth.changePassword(profile.profileId, PASSWORD, 'brand-new-pass-2');
  assert.equal(await auth.verifyPassword(profile.profileId, PASSWORD), false);
  assert.equal(await auth.verifyPassword(profile.profileId, 'brand-new-pass-2'), true);
  assert.equal(auth.getSession(session.sessionId), undefined);
  assert.equal(auth.getActiveSession(), undefined);
  const next = await auth.unlock(profile.profileId, 'brand-new-pass-2');
  assert.equal(next.role, MemberRole.ADMIN);
});

test('C12_sessions_idleAndAbsoluteTimeout', async () => {
  const { harness, auth, family } = await setup();
  const profile = await profileFor(auth, harness, family.familyId, family.ownerMemberId,
    MemberRole.ADMIN);
  const session = await auth.unlock(profile.profileId, PASSWORD);
  harness.advance(15 * 60 * 1000 - 1000);
  assert.equal(auth.getSession(session.sessionId).sessionId, session.sessionId);
  harness.advance(2000);
  assert.equal(auth.getSession(session.sessionId), undefined);
  assert.equal(auth.getActiveSession(), undefined);

  const absolute = await auth.unlock(profile.profileId, PASSWORD);
  for (let index = 0; index < 144; index++) {
    harness.advance(10 * 60 * 1000);
    auth.touch(absolute.sessionId);
  }
  harness.advance(1000);
  assert.equal(auth.getSession(absolute.sessionId), undefined);
});

test('C12_lockAllAndMemberInvalidation', async () => {
  const { harness, auth, family } = await setup();
  const profile = await profileFor(auth, harness, family.familyId, family.ownerMemberId,
    MemberRole.ADMIN);
  const first = await auth.unlock(profile.profileId, PASSWORD);
  await auth.lockAll();
  assert.equal(auth.getSession(first.sessionId), undefined);
  assert.equal(auth.getActiveSession(), undefined);

  const second = await auth.unlock(profile.profileId, PASSWORD);
  auth.invalidateSessionsForMember(profile.memberId);
  assert.equal(auth.getSession(second.sessionId), undefined);
  assert.equal(auth.getActiveSession(), undefined);
});

test('C12_rbacMatrix_adminMemberGuestAndDeviceStates', async () => {
  const { harness, auth, family } = await setup();
  const member = await addMember(harness, family.familyId, MemberRole.MEMBER,
    { displayName: 'Bob' });
  const guestExpiresAt = DateTimeUtil.formatUtcCompact(harness.clock.nowMs() + 10 * 60 * 1000);
  const guest = await addMember(harness, family.familyId, MemberRole.GUEST,
    { displayName: 'Guest', allowedRoomIds: [ROOM_A], expiresAt: guestExpiresAt });

  const adminProfile = await profileFor(auth, harness, family.familyId,
    family.ownerMemberId, MemberRole.ADMIN);
  const memberProfile = await profileFor(auth, harness, family.familyId, member.memberId,
    MemberRole.MEMBER);
  const guestProfile = await profileFor(auth, harness, family.familyId, guest.memberId,
    MemberRole.GUEST);
  const admin = await auth.unlock(adminProfile.profileId, PASSWORD);
  const memberSession = await auth.unlock(memberProfile.profileId, PASSWORD);
  const guestSession = await auth.unlock(guestProfile.profileId, PASSWORD);
  const roomA = new RoomRef(ROOM_A, 'Living');
  const roomB = new RoomRef(ROOM_B, 'Kitchen');

  assert.equal(auth.canControl(admin, device(family.familyId, ROOM_A), roomA).allowed, true);
  assert.equal(auth.canControl(memberSession, device(family.familyId, ROOM_B),
    roomB).allowed, true);
  assert.equal(auth.canControl(guestSession, device(family.familyId, ROOM_A),
    roomA).allowed, true);
  const wrongRoom = auth.canControl(guestSession, device(family.familyId, ROOM_B), roomB);
  assert.equal(wrongRoom.allowed, false);
  assert.equal(wrongRoom.reason, 'ROOM_NOT_ALLOWED');

  assert.equal(auth.canControl(admin, device(family.familyId, ROOM_A, { enabled: false }),
    roomA).reason, 'DEVICE_DISABLED');
  assert.equal(auth.canControl(admin, device(family.familyId, '', { unassigned: true }),
    undefined).reason, 'DEVICE_UNASSIGNED');
  assert.equal(auth.canControl(memberSession,
    device(family.familyId, ROOM_A, { unsupported: true, deviceId: 'dev-u' }),
    roomA).reason, 'UNSUPPORTED_DEVICE_TYPE');

  assert.equal(auth.canManageFamily(admin).allowed, true);
  assert.equal(auth.canManageFamily(memberSession).allowed, false);
  assert.equal(auth.canManageRooms(admin).allowed, true);
  assert.equal(auth.canInvite(admin).allowed, true);
  assert.equal(auth.canInvite(guestSession).allowed, false);
  assert.equal(auth.canExecuteScene(memberSession).allowed, true);
  assert.equal(auth.canExecuteScene(guestSession).allowed, false);
  assert.equal(auth.isAdmin(admin), true);
  assert.equal(auth.isAdmin(memberSession), false);

  harness.advance(4 * 60 * 1000);
  auth.touch(guestSession.sessionId);
  harness.advance(4 * 60 * 1000);
  auth.touch(guestSession.sessionId);
  harness.advance(3 * 60 * 1000);
  auth.touch(guestSession.sessionId);
  const expired = auth.canControl(guestSession, device(family.familyId, ROOM_A), roomA);
  assert.equal(expired.allowed, false);
  assert.equal(expired.reason, 'MEMBER_INACTIVE');
});

test('C12_backoffAfterFiveFailuresAndProfileCleanup', async () => {
  const { harness, auth, family } = await setup();
  const profile = await profileFor(auth, harness, family.familyId, family.ownerMemberId,
    MemberRole.ADMIN);
  for (let index = 0; index < 5; index++) {
    await expectRejectCode(auth.unlock(profile.profileId, 'wrong-password-1'),
      'AUTH_PASSWORD_INVALID');
  }
  await expectRejectCode(auth.unlock(profile.profileId, PASSWORD), 'AUTH_PASSWORD_INVALID');
  harness.advance(30000);
  const session = await auth.unlock(profile.profileId, PASSWORD);
  assert.equal(auth.getSession(session.sessionId).sessionId, session.sessionId);

  await auth.removeProfilesForMember(family.familyId, family.ownerMemberId);
  assert.equal(await auth.getProfile(profile.profileId), undefined);
  assert.equal(harness.secrets.has(profile.hashAlias), false);
  assert.equal(auth.getSession(session.sessionId), undefined);
});

test('C12_multiFamilyProfilesStayScoped', async () => {
  const { harness, auth, family } = await setup();
  const other = await seedFamily(harness, 'Cabin', 'Carol');
  const first = await profileFor(auth, harness, family.familyId, family.ownerMemberId,
    MemberRole.ADMIN);
  const second = await profileFor(auth, harness, other.familyId, other.ownerMemberId,
    MemberRole.ADMIN);
  const firstList = await auth.listProfiles(family.familyId);
  const secondList = await auth.listProfiles(other.familyId);
  assert.deepEqual(firstList.map((item) => item.profileId), [first.profileId]);
  assert.deepEqual(secondList.map((item) => item.profileId), [second.profileId]);
  assert.equal(first.familyId, family.familyId);
  assert.equal(second.familyId, other.familyId);
});
