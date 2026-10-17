/*
 * YaoCore C-02 family/member/invitation/room/scene/cloud base models.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §5.1.7, §5.3 invariants 9..10
 *
 * These are shared model shapes only. Repository, execution, UI and cloud
 * behavior belong to DES-001B (C-08/C-09/C-11/C-15).
 */
import { AppErrors } from '../common/types/AppError';
import { ProtocolConstants } from '../common/constants/ProtocolConstants';
import { StorageConstants } from '../common/constants/StorageConstants';
import { DeviceAction } from '../common/constants/DeviceConstants';
import type { CommandValue } from '../common/utils/JsonAtom';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import { UuidUtil } from '../common/utils/UuidUtil';

const ID_PATTERN: RegExp = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,62}$/;
const CLOUD_ID_PATTERN: RegExp = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$/;
const HTTPS_HOST_PATTERN: RegExp = /^https:\/\/[A-Za-z0-9.-]+(:[0-9]{1,5})?$/;
const HEX_PATTERN: RegExp = /^[0-9a-fA-F]+$/;

export enum MemberRole {
  ADMIN = 'ADMIN',
  MEMBER = 'MEMBER',
  GUEST = 'GUEST'
}

export enum MemberStatus {
  ACTIVE = 'ACTIVE',
  INVITED = 'INVITED',
  DISABLED = 'DISABLED',
  EXPIRED = 'EXPIRED'
}

export enum InviteMode {
  KEY_WRAP = 'KEY_WRAP',
  CODE_KEK = 'CODE_KEK'
}

export enum InvitationStatus {
  PENDING = 'PENDING',
  ACCEPTED = 'ACCEPTED',
  EXPIRED = 'EXPIRED',
  REVOKED = 'REVOKED'
}

export class Family {
  readonly familyId: string;
  readonly familyName: string;
  readonly ownerMemberId: string;
  readonly createdAt: string;
  readonly updatedAt: string;
  readonly gatewayIds: ReadonlyArray<string>;

  constructor(familyId: string, familyName: string, ownerMemberId: string, createdAt: string,
    updatedAt: string, gatewayIds: ReadonlyArray<string>) {
    ModelValidation.identifier(familyId, 'familyId');
    ModelValidation.text(familyName, 'familyName', 63);
    ModelValidation.identifier(ownerMemberId, 'ownerMemberId');
    DateTimeUtil.parseUtcCompact(createdAt);
    DateTimeUtil.parseUtcCompact(updatedAt);
    for (let index = 0; index < gatewayIds.length; index++) {
      ModelValidation.deviceIdentifier(gatewayIds[index], 'gatewayId');
    }
    this.familyId = familyId;
    this.familyName = familyName;
    this.ownerMemberId = ownerMemberId;
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
    this.gatewayIds = gatewayIds;
  }
}

export class FamilyMember {
  readonly memberId: string;
  readonly familyId: string;
  readonly userId: string;
  readonly displayName: string;
  readonly role: MemberRole;
  readonly status: MemberStatus;
  readonly joinedAt: string;
  readonly allowedRoomIds: ReadonlyArray<string>;
  readonly expiresAt?: string;
  readonly memberDeviceId?: string;
  readonly joinedVia?: string;
  readonly secretsVersion?: string;
  readonly lastSyncedAt?: string;

  constructor(memberId: string, familyId: string, userId: string, displayName: string,
    role: MemberRole, status: MemberStatus, joinedAt: string,
    allowedRoomIds: ReadonlyArray<string>, expiresAt?: string, memberDeviceId?: string,
    joinedVia?: string, secretsVersion?: string, lastSyncedAt?: string) {
    ModelValidation.identifier(memberId, 'memberId');
    ModelValidation.identifier(familyId, 'familyId');
    ModelValidation.identifier(userId, 'userId');
    ModelValidation.text(displayName, 'displayName', 63);
    DateTimeUtil.parseUtcCompact(joinedAt);
    for (let index = 0; index < allowedRoomIds.length; index++) {
      if (!UuidUtil.isValidUuid(allowedRoomIds[index])) {
        throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'allowedRoomIds');
      }
    }
    if (role === MemberRole.GUEST) {
      if (expiresAt === undefined || allowedRoomIds.length < 1) {
        throw AppErrors.of('CONFIGURATION_ERROR', []);
      }
    }
    if (expiresAt !== undefined) {
      DateTimeUtil.parseUtcCompact(expiresAt);
    }
    if (memberDeviceId !== undefined) {
      ModelValidation.deviceIdentifier(memberDeviceId, 'memberDeviceId');
    }
    if (lastSyncedAt !== undefined) {
      DateTimeUtil.parseUtcCompact(lastSyncedAt);
    }
    this.memberId = memberId;
    this.familyId = familyId;
    this.userId = userId;
    this.displayName = displayName;
    this.role = role;
    this.status = status;
    this.joinedAt = joinedAt;
    this.allowedRoomIds = allowedRoomIds;
    this.expiresAt = expiresAt;
    this.memberDeviceId = memberDeviceId;
    this.joinedVia = joinedVia;
    this.secretsVersion = secretsVersion;
    this.lastSyncedAt = lastSyncedAt;
  }
}

export class InvitationRecord {
  readonly inviteId: string;
  readonly familyId: string;
  readonly familyName: string;
  readonly inviterId: string;
  readonly targetRole: MemberRole;
  readonly allowedRoomIds: ReadonlyArray<string>;
  readonly mode: InviteMode;
  readonly status: InvitationStatus;
  readonly expireAt: string;
  readonly maxUses: number;
  readonly usedCount: number;
  readonly payloadString: string;
  readonly seedAlias: string;
  readonly codeSaltHex?: string;
  readonly kdfIterations?: number;
  readonly memberId?: string;
  readonly acceptedAt?: string;
  readonly acceptedByMemberId?: string;
  readonly receipt?: string;
  readonly revokedAt?: string;
  readonly revokedReason?: string;

  constructor(inviteId: string, familyId: string, familyName: string, inviterId: string,
    targetRole: MemberRole, allowedRoomIds: ReadonlyArray<string>, mode: InviteMode,
    status: InvitationStatus, expireAt: string, maxUses: number, usedCount: number,
    payloadString: string, seedAlias: string, codeSaltHex?: string, kdfIterations?: number,
    memberId?: string, acceptedAt?: string, acceptedByMemberId?: string, receipt?: string,
    revokedAt?: string, revokedReason?: string) {
    ModelValidation.identifier(inviteId, 'inviteId');
    ModelValidation.identifier(familyId, 'familyId');
    ModelValidation.text(familyName, 'familyName', 63);
    ModelValidation.identifier(inviterId, 'inviterId');
    if (targetRole !== MemberRole.MEMBER && targetRole !== MemberRole.GUEST) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    for (let index = 0; index < allowedRoomIds.length; index++) {
      if (!UuidUtil.isValidUuid(allowedRoomIds[index])) {
        throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'allowedRoomIds');
      }
    }
    if (targetRole === MemberRole.GUEST && allowedRoomIds.length < 1) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    DateTimeUtil.parseUtcCompact(expireAt);
    if (!Number.isInteger(maxUses) || maxUses < 1 || !Number.isInteger(usedCount) ||
      usedCount < 0 || usedCount > maxUses) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'maxUses');
    }
    if (mode === InviteMode.KEY_WRAP) {
      if (maxUses !== 1 || memberId === undefined || memberId.length === 0) {
        throw AppErrors.of('CONFIGURATION_ERROR', []);
      }
    }
    if (payloadString.length === 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (seedAlias.length === 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (codeSaltHex !== undefined && (codeSaltHex.length === 0 || !HEX_PATTERN.test(codeSaltHex))) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (kdfIterations !== undefined && (!Number.isInteger(kdfIterations) || kdfIterations < 1)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'kdfIterations');
    }
    if (memberId !== undefined) {
      ModelValidation.identifier(memberId, 'memberId');
    }
    if (acceptedAt !== undefined) {
      DateTimeUtil.parseUtcCompact(acceptedAt);
    }
    if (acceptedByMemberId !== undefined) {
      ModelValidation.identifier(acceptedByMemberId, 'acceptedByMemberId');
    }
    if (revokedAt !== undefined) {
      DateTimeUtil.parseUtcCompact(revokedAt);
    }
    this.inviteId = inviteId;
    this.familyId = familyId;
    this.familyName = familyName;
    this.inviterId = inviterId;
    this.targetRole = targetRole;
    this.allowedRoomIds = allowedRoomIds;
    this.mode = mode;
    this.status = status;
    this.expireAt = expireAt;
    this.maxUses = maxUses;
    this.usedCount = usedCount;
    this.payloadString = payloadString;
    this.seedAlias = seedAlias;
    this.codeSaltHex = codeSaltHex;
    this.kdfIterations = kdfIterations;
    this.memberId = memberId;
    this.acceptedAt = acceptedAt;
    this.acceptedByMemberId = acceptedByMemberId;
    this.receipt = receipt;
    this.revokedAt = revokedAt;
    this.revokedReason = revokedReason;
  }
}

export class Room {
  readonly roomId: string;
  readonly familyId: string;
  readonly roomName: string;
  readonly icon?: string;
  readonly orderIndex: number;
  readonly createdAt: string;
  readonly updatedAt: string;

  constructor(roomId: string, familyId: string, roomName: string, orderIndex: number,
    createdAt: string, updatedAt: string, icon?: string) {
    if (!UuidUtil.isValidUuid(roomId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'roomId');
    }
    ModelValidation.identifier(familyId, 'familyId');
    ModelValidation.text(roomName, 'roomName', ProtocolConstants.MAX_ROOM_NAME_LENGTH);
    if (!Number.isInteger(orderIndex) || orderIndex < 0) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'orderIndex');
    }
    DateTimeUtil.parseUtcCompact(createdAt);
    DateTimeUtil.parseUtcCompact(updatedAt);
    this.roomId = roomId;
    this.familyId = familyId;
    this.roomName = roomName;
    this.icon = icon;
    this.orderIndex = orderIndex;
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
  }
}

export class SceneAction {
  readonly gatewayId: string;
  readonly targetDeviceId: string;
  readonly action: DeviceAction;
  readonly value?: CommandValue;
  readonly delayMs?: number;

  constructor(gatewayId: string, targetDeviceId: string, action: DeviceAction, value?: CommandValue,
    delayMs?: number) {
    ModelValidation.deviceIdentifier(gatewayId, 'gatewayId');
    ModelValidation.deviceIdentifier(targetDeviceId, 'targetDeviceId');
    if (value !== undefined) {
      if (typeof value === 'number' && !Number.isFinite(value)) {
        throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'value');
      }
      if (typeof value === 'string' && value.length > 63) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'value');
      }
    }
    if (delayMs !== undefined && (!Number.isInteger(delayMs) || delayMs < 0)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'delayMs');
    }
    this.gatewayId = gatewayId;
    this.targetDeviceId = targetDeviceId;
    this.action = action;
    this.value = value;
    this.delayMs = delayMs;
  }
}

export class Scene {
  readonly sceneId: string;
  readonly familyId: string;
  readonly sceneName: string;
  readonly icon: string;
  readonly actions: ReadonlyArray<SceneAction>;
  readonly isEnabled: boolean;

  constructor(sceneId: string, familyId: string, sceneName: string, icon: string,
    actions: ReadonlyArray<SceneAction>, isEnabled: boolean) {
    if (!UuidUtil.isValidUuid(sceneId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'sceneId');
    }
    ModelValidation.identifier(familyId, 'familyId');
    ModelValidation.text(sceneName, 'sceneName', 63);
    this.sceneId = sceneId;
    this.familyId = familyId;
    this.sceneName = sceneName;
    this.icon = icon;
    this.actions = actions;
    this.isEnabled = isEnabled;
  }
}

export class CloudConfig {
  readonly endpoint: string;
  readonly projectId: string;
  readonly deviceId: string;
  readonly accessTokenAlias: string;
  readonly shadowEndpoint?: string;

  constructor(endpoint: string, projectId: string, deviceId: string, accessTokenAlias: string,
    shadowEndpoint?: string) {
    if (!HTTPS_HOST_PATTERN.test(endpoint)) {
      throw AppErrors.of('CLOUD_ENDPOINT_INVALID', []);
    }
    if (!CLOUD_ID_PATTERN.test(projectId) || !CLOUD_ID_PATTERN.test(deviceId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'cloudId');
    }
    if (accessTokenAlias !== StorageConstants.ASSET_CLOUD_TOKEN) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (shadowEndpoint !== undefined && !HTTPS_HOST_PATTERN.test(shadowEndpoint)) {
      throw AppErrors.of('CLOUD_ENDPOINT_INVALID', []);
    }
    this.endpoint = endpoint;
    this.projectId = projectId;
    this.deviceId = deviceId;
    this.accessTokenAlias = accessTokenAlias;
    this.shadowEndpoint = shadowEndpoint;
  }
}

class ModelValidation {
  static identifier(value: string, field: string): void {
    if (value.length === 0 || value.length > 63 || !ID_PATTERN.test(value)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', field);
    }
  }

  static deviceIdentifier(value: string, field: string): void {
    if (value.length === 0 || value.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      value.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(value)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', field);
    }
  }

  static text(value: string, field: string, maxLength: number): void {
    if (value.length === 0 || value.length > maxLength) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', field);
    }
  }
}
