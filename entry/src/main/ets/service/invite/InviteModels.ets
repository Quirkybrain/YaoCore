/*
 * YaoCore C-13 InviteService value objects.
 * Producer: agent:implementation-engineer | Task: T-13 / wp-049-family
 * Contract: DES-A §13.1; ADR-003 §3-§5
 *
 * Pure value types. No plaintext commandSecret is retained beyond the
 * transient GatewaySecretEntry used to build the encrypted bundle.
 */
import { AppErrors } from '../../common/types/AppError';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import type { TlsMaterial } from '../../model/GatewayRoute';
import {
  InvitationRecord,
  InviteMode,
  MemberRole
} from '../../model/FamilyModels';

const IDENTIFIER_PATTERN: RegExp = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,62}$/;
const HEX_PATTERN: RegExp = /^[0-9a-f]+$/;

export class JoinRequest {
  readonly v: number;
  readonly memberId: string;
  readonly pub: string;
  readonly createdAt: string;
  readonly displayName?: string;

  constructor(v: number, memberId: string, pub: string, createdAt: string,
    displayName?: string) {
    this.v = v;
    this.memberId = memberId;
    this.pub = pub;
    this.createdAt = createdAt;
    this.displayName = displayName;
  }
}

export class JoinRequestContainer {
  readonly text: string;
  readonly joinRequest: JoinRequest;

  constructor(text: string, joinRequest: JoinRequest) {
    this.text = text;
    this.joinRequest = joinRequest;
  }
}

export class InviteKdf {
  readonly mode: InviteMode;
  readonly alg: string;
  readonly adminEphemeralPub?: string;
  readonly salt?: string;
  readonly iterations?: number;

  constructor(mode: InviteMode, alg: string, adminEphemeralPub?: string, salt?: string,
    iterations?: number) {
    this.mode = mode;
    this.alg = alg;
    this.adminEphemeralPub = adminEphemeralPub;
    this.salt = salt;
    this.iterations = iterations;
  }

  static keyWrap(adminEphemeralPub: string): InviteKdf {
    return new InviteKdf(InviteMode.KEY_WRAP, 'X25519-HKDF-SHA256', adminEphemeralPub);
  }

  static codeKek(salt: string, iterations: number): InviteKdf {
    return new InviteKdf(InviteMode.CODE_KEK, 'PBKDF2-SHA256-120000+HKDF-SHA256',
      undefined, salt, iterations);
  }
}

export class InviteHeader {
  readonly v: number;
  readonly inviteId: string;
  readonly familyId: string;
  readonly familyName: string;
  readonly targetRole: MemberRole;
  readonly allowedRoomIds: ReadonlyArray<string>;
  readonly expireAt: string;
  readonly maxUses: number;
  readonly kdf: InviteKdf;
  readonly keyId: string;

  constructor(v: number, inviteId: string, familyId: string, familyName: string,
    targetRole: MemberRole, allowedRoomIds: ReadonlyArray<string>, expireAt: string,
    maxUses: number, kdf: InviteKdf, keyId: string) {
    if (!Number.isInteger(v) || v < 1) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'v');
    }
    if (!IDENTIFIER_PATTERN.test(inviteId) || !IDENTIFIER_PATTERN.test(familyId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'inviteId');
    }
    if (familyName.length < 1 || familyName.length > 63) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'familyName');
    }
    if (targetRole !== MemberRole.MEMBER && targetRole !== MemberRole.GUEST) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'targetRole');
    }
    if (!Number.isInteger(maxUses) || maxUses < 1) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'maxUses');
    }
    DateTimeUtil.parseUtcCompact(expireAt);
    if (keyId.length < 1 || keyId.length > 32) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'keyId');
    }
    this.v = v;
    this.inviteId = inviteId;
    this.familyId = familyId;
    this.familyName = familyName;
    this.targetRole = targetRole;
    this.allowedRoomIds = allowedRoomIds;
    this.expireAt = expireAt;
    this.maxUses = maxUses;
    this.kdf = kdf;
    this.keyId = keyId;
  }
}

export class GatewaySecretEntry {
  readonly gatewayId: string;
  readonly name?: string;
  readonly commandSecretHex: string;
  readonly tls?: TlsMaterial;

  constructor(gatewayId: string, commandSecretHex: string, name?: string,
    tls?: TlsMaterial) {
    if (gatewayId.length === 0 ||
      gatewayId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      gatewayId.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(gatewayId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'gatewayId');
    }
    if (name !== undefined && (name.length < 1 || name.length > 63)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'gatewayName');
    }
    if (commandSecretHex.length < 32 || commandSecretHex.length > 128 ||
      commandSecretHex.length % 2 !== 0 || !HEX_PATTERN.test(commandSecretHex)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'commandSecret');
    }
    this.gatewayId = gatewayId;
    this.name = name;
    this.commandSecretHex = commandSecretHex;
    this.tls = tls;
  }
}

export class FamilySecretBundle {
  readonly v: number;
  readonly familyId: string;
  readonly issuedAt: string;
  readonly keyId: string;
  readonly seedHex: string;
  readonly gateways: ReadonlyArray<GatewaySecretEntry>;

  constructor(v: number, familyId: string, issuedAt: string, keyId: string, seedHex: string,
    gateways: ReadonlyArray<GatewaySecretEntry>) {
    if (!Number.isInteger(v) || v < 1) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'v');
    }
    if (!IDENTIFIER_PATTERN.test(familyId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'familyId');
    }
    DateTimeUtil.parseUtcCompact(issuedAt);
    if (keyId.length < 1 || keyId.length > 32) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'keyId');
    }
    if (seedHex.length !== 64 || !HEX_PATTERN.test(seedHex)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'seed');
    }
    this.v = v;
    this.familyId = familyId;
    this.issuedAt = issuedAt;
    this.keyId = keyId;
    this.seedHex = seedHex;
    this.gateways = gateways;
  }
}

export class InvitationContainer {
  readonly text: string;
  readonly header: InviteHeader;
  readonly inviteId: string;
  readonly mode: InviteMode;

  constructor(text: string, header: InviteHeader) {
    this.text = text;
    this.header = header;
    this.inviteId = header.inviteId;
    this.mode = header.kdf.mode;
  }
}

export class CreateInvitationInput {
  readonly familyId: string;
  readonly targetRole: MemberRole;
  readonly allowedRoomIds: ReadonlyArray<string>;
  readonly maxUses: number;
  readonly ttlMs: number;
  readonly mode: InviteMode;
  readonly joinRequest?: JoinRequestContainer;
  readonly familyName?: string;

  constructor(familyId: string, targetRole: MemberRole,
    allowedRoomIds: ReadonlyArray<string>, maxUses: number, ttlMs: number, mode: InviteMode,
    joinRequest?: JoinRequestContainer, familyName?: string) {
    this.familyId = familyId;
    this.targetRole = targetRole;
    this.allowedRoomIds = allowedRoomIds;
    this.maxUses = maxUses;
    this.ttlMs = ttlMs;
    this.mode = mode;
    this.joinRequest = joinRequest;
    this.familyName = familyName;
  }
}

export class InvitationCreationResult {
  readonly container: InvitationContainer;
  readonly code?: string;
  readonly record: InvitationRecord;

  constructor(container: InvitationContainer, record: InvitationRecord, code?: string) {
    this.container = container;
    this.record = record;
    this.code = code;
  }
}

export class AcceptInvitationOptions {
  readonly code?: string;
  readonly nowMs: number;

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

  constructor(valid: boolean, inviteId?: string, memberId?: string,
    acceptedAt?: string) {
    this.valid = valid;
    this.inviteId = inviteId;
    this.memberId = memberId;
    this.acceptedAt = acceptedAt;
  }
}

export class RotationPlan {
  readonly gatewayId: string;
  readonly steps: ReadonlyArray<string>;

  constructor(gatewayId: string, steps: ReadonlyArray<string>) {
    this.gatewayId = gatewayId;
    this.steps = steps;
  }
}

/**
 * Self-describing receipt envelope. DES-A §13.2 fixes the HMAC domain string;
 * the envelope only carries the memberId/acceptedAt inputs that the frozen
 * verifyReceipt(receiptText, inviteId) signature cannot otherwise recover.
 * The MAC itself remains exactly HMAC-SHA256(seed, domain || inviteId ||
 * memberId || acceptedAt) and the stored hash never contains this text.
 */
export class ReceiptPayload {
  readonly v: number;
  readonly inviteId: string;
  readonly memberId: string;
  readonly acceptedAt: string;
  readonly mac: string;

  constructor(v: number, inviteId: string, memberId: string, acceptedAt: string, mac: string) {
    this.v = v;
    this.inviteId = inviteId;
    this.memberId = memberId;
    this.acceptedAt = acceptedAt;
    this.mac = mac;
  }
}
