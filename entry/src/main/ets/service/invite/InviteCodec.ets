/*
 * YaoCore C-13 invitation container codec.
 * Producer: agent:implementation-engineer | Task: T-13 / wp-049-family
 * Contract: DES-A §13.2; ADR-003 §3
 *
 * Strict, fail-closed parsing for YCR1/YCI1/YCP1. Header bytes decoded from the
 * container are returned untouched so they can be used as AES-GCM AAD; a
 * re-serialization never replaces the received bytes. Decode failures map to
 * INVITE_INVALID (never distinguish version/code/tamper), except an explicit
 * unknown container version -> INVITE_VERSION_UNSUPPORTED.
 */
import { AppErrors } from '../../common/types/AppError';
import { JsonKind, JsonNode, NameValueNode } from '../../common/types/JsonNode';
import { JsonParser, JsonLimits } from '../../common/utils/JsonParser';
import { JsonCanonicalizer } from '../../common/utils/JsonCanonicalizer';
import { Base64Url } from '../../common/utils/Base64Url';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import { BytesUtil } from '../../common/utils/BytesUtil';
import { UuidUtil } from '../../common/utils/UuidUtil';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';
import { TlsMaterial } from '../../model/GatewayRoute';
import { InviteMode, MemberRole } from '../../model/FamilyModels';
import {
  FamilySecretBundle,
  GatewaySecretEntry,
  InviteHeader,
  InviteKdf,
  JoinRequest,
  ReceiptPayload
} from './InviteModels';

const JOIN_PREFIX: string = 'YCR1.';
const INVITE_PREFIX: string = 'YCI1.';
const RECEIPT_PREFIX: string = 'YCP1.';
const MAX_HEADER_BYTES: number = 4096;
const MAX_BUNDLE_BYTES: number = 32768;
const MAX_CONTAINER_BYTES: number = 65536;
const GCM_IV_BYTES: number = 12;
const GCM_TAG_BYTES: number = 16;
const SEED_BYTES: number = 32;
const MEMBER_ID_HEX_LENGTH: number = 32;
const LOWER_HEX_PATTERN: RegExp = /^[0-9a-f]+$/;
const CODE_ALG: string = 'PBKDF2-SHA256-120000+HKDF-SHA256';
const KEY_WRAP_ALG: string = 'X25519-HKDF-SHA256';
const INVITE_ITERATIONS: number = 120000;

export class ContainerEnvelope {
  readonly headerBytes: Uint8Array;
  readonly header: InviteHeader;
  readonly iv: Uint8Array;
  readonly ciphertext: Uint8Array;
  readonly tag: Uint8Array;

  constructor(headerBytes: Uint8Array, header: InviteHeader, iv: Uint8Array,
    ciphertext: Uint8Array, tag: Uint8Array) {
    this.headerBytes = headerBytes;
    this.header = header;
    this.iv = iv;
    this.ciphertext = ciphertext;
    this.tag = tag;
  }
}

export class InviteCodec {
  // ---- YCR1 ---------------------------------------------------------------

  static encodeJoinRequest(request: JoinRequest): string {
    if (request.v !== 1) {
      throw AppErrors.of('INVITE_JOIN_REQUEST_INVALID', []);
    }
    InviteCodec.requireMemberId(request.memberId, 'INVITE_JOIN_REQUEST_INVALID');
    const pub = InviteCodec.decodeBase64Url(request.pub, 'INVITE_JOIN_REQUEST_INVALID');
    if (pub.length !== 32) {
      throw AppErrors.of('INVITE_JOIN_REQUEST_INVALID', []);
    }
    DateTimeUtil.parseUtcCompact(request.createdAt);
    const entries: NameValueNode[] = [
      new NameValueNode('createdAt', JsonNode.string(request.createdAt)),
      new NameValueNode('memberId', JsonNode.string(request.memberId)),
      new NameValueNode('pub', JsonNode.string(request.pub)),
      new NameValueNode('v', JsonNode.number(1))
    ];
    if (request.displayName !== undefined) {
      InviteCodec.requireText(request.displayName, 63, 'INVITE_JOIN_REQUEST_INVALID');
      entries.push(new NameValueNode('displayName', JsonNode.string(request.displayName)));
    }
    const text = JsonCanonicalizer.stringifySorted(JsonNode.object(entries));
    return JOIN_PREFIX + Base64Url.encode(BytesUtil.utf8(text));
  }

  static decodeJoinRequest(text: string): JoinRequest {
    if (!text.startsWith(JOIN_PREFIX) || text.length <= JOIN_PREFIX.length ||
      text.indexOf('.', JOIN_PREFIX.length) >= 0) {
      throw AppErrors.of('INVITE_JOIN_REQUEST_INVALID', []);
    }
    const bytes = InviteCodec.decodeBase64Url(text.substring(JOIN_PREFIX.length),
      'INVITE_JOIN_REQUEST_INVALID');
    if (bytes.length > MAX_HEADER_BYTES) {
      throw AppErrors.of('INVITE_JOIN_REQUEST_INVALID', []);
    }
    const node = InviteCodec.parseObject(bytes, MAX_HEADER_BYTES,
      'INVITE_JOIN_REQUEST_INVALID');
    InviteCodec.requireKeys(node, ['createdAt', 'displayName', 'memberId', 'pub', 'v'],
      'INVITE_JOIN_REQUEST_INVALID');
    const version = InviteCodec.requireNumber(node, 'v', 'INVITE_JOIN_REQUEST_INVALID');
    if (version !== 1) {
      throw AppErrors.of('INVITE_JOIN_REQUEST_INVALID', []);
    }
    const memberId = InviteCodec.requireString(node, 'memberId',
      'INVITE_JOIN_REQUEST_INVALID');
    InviteCodec.requireMemberId(memberId, 'INVITE_JOIN_REQUEST_INVALID');
    const pub = InviteCodec.requireString(node, 'pub', 'INVITE_JOIN_REQUEST_INVALID');
    const pubBytes = InviteCodec.decodeBase64Url(pub, 'INVITE_JOIN_REQUEST_INVALID');
    if (pubBytes.length !== 32 || Base64Url.encode(pubBytes) !== pub) {
      throw AppErrors.of('INVITE_JOIN_REQUEST_INVALID', []);
    }
    const createdAt = InviteCodec.requireUtc(node, 'createdAt',
      'INVITE_JOIN_REQUEST_INVALID');
    const displayName = InviteCodec.optionalString(node, 'displayName',
      'INVITE_JOIN_REQUEST_INVALID');
    if (displayName !== undefined) {
      InviteCodec.requireText(displayName, 63, 'INVITE_JOIN_REQUEST_INVALID');
    }
    return new JoinRequest(1, memberId, pub, createdAt, displayName);
  }

  // ---- YCI1 header --------------------------------------------------------

  static encodeHeader(header: InviteHeader): Uint8Array {
    InviteCodec.validateHeader(header);
    const kdfEntries: NameValueNode[] = [
      new NameValueNode('alg', JsonNode.string(header.kdf.alg)),
      new NameValueNode('mode', JsonNode.string(header.kdf.mode))
    ];
    if (header.kdf.adminEphemeralPub !== undefined) {
      kdfEntries.push(new NameValueNode('adminEphemeralPub',
        JsonNode.string(header.kdf.adminEphemeralPub)));
    }
    if (header.kdf.salt !== undefined) {
      kdfEntries.push(new NameValueNode('salt', JsonNode.string(header.kdf.salt)));
    }
    if (header.kdf.iterations !== undefined) {
      kdfEntries.push(new NameValueNode('iterations',
        JsonNode.number(header.kdf.iterations)));
    }
    const roomNodes: JsonNode[] = [];
    for (let index = 0; index < header.allowedRoomIds.length; index++) {
      roomNodes.push(JsonNode.string(header.allowedRoomIds[index]));
    }
    const root = JsonNode.object([
      new NameValueNode('allowedRoomIds', JsonNode.array(roomNodes)),
      new NameValueNode('expireAt', JsonNode.string(header.expireAt)),
      new NameValueNode('familyId', JsonNode.string(header.familyId)),
      new NameValueNode('familyName', JsonNode.string(header.familyName)),
      new NameValueNode('inviteId', JsonNode.string(header.inviteId)),
      new NameValueNode('kdf', JsonNode.object(kdfEntries)),
      new NameValueNode('keyId', JsonNode.string(header.keyId)),
      new NameValueNode('maxUses', JsonNode.number(header.maxUses)),
      new NameValueNode('targetRole', JsonNode.string(header.targetRole)),
      new NameValueNode('v', JsonNode.number(header.v))
    ]);
    const bytes = BytesUtil.utf8(JsonCanonicalizer.stringifySorted(root));
    if (bytes.length > MAX_HEADER_BYTES) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    return bytes;
  }

  static decodeHeader(headerBytes: Uint8Array): InviteHeader {
    if (headerBytes.length < 2 || headerBytes.length > MAX_HEADER_BYTES) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const node = InviteCodec.parseObject(headerBytes, MAX_HEADER_BYTES, 'INVITE_INVALID');
    const versionNode = node.get('v');
    if (versionNode !== undefined && versionNode.kind === JsonKind.NUMBER &&
      versionNode.numberValue !== 1) {
      throw AppErrors.of('INVITE_VERSION_UNSUPPORTED', []);
    }
    InviteCodec.requireKeys(node, ['allowedRoomIds', 'expireAt', 'familyId', 'familyName',
      'inviteId', 'kdf', 'keyId', 'maxUses', 'targetRole', 'v'], 'INVITE_INVALID');
    const version = InviteCodec.requireNumber(node, 'v', 'INVITE_INVALID');
    if (version !== 1) {
      throw AppErrors.of('INVITE_VERSION_UNSUPPORTED', []);
    }
    const inviteId = InviteCodec.requireUuid(node, 'inviteId', 'INVITE_INVALID');
    const familyId = InviteCodec.requireUuid(node, 'familyId', 'INVITE_INVALID');
    const familyName = InviteCodec.requireTextValue(node, 'familyName', 63);
    const roleText = InviteCodec.requireString(node, 'targetRole', 'INVITE_INVALID');
    let targetRole: MemberRole;
    if (roleText === MemberRole.MEMBER) {
      targetRole = MemberRole.MEMBER;
    } else if (roleText === MemberRole.GUEST) {
      targetRole = MemberRole.GUEST;
    } else {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const allowedRoomIds = InviteCodec.requireUuidArray(node, 'allowedRoomIds');
    if (targetRole === MemberRole.GUEST && allowedRoomIds.length < 1) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const expireAt = InviteCodec.requireUtc(node, 'expireAt', 'INVITE_INVALID');
    const maxUses = InviteCodec.requireNumber(node, 'maxUses', 'INVITE_INVALID');
    if (!Number.isInteger(maxUses) || maxUses < 1) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const kdfNode = InviteCodec.requireObject(node, 'kdf', 'INVITE_INVALID');
    const kdf = InviteCodec.decodeKdf(kdfNode, maxUses);
    const keyId = InviteCodec.requireString(node, 'keyId', 'INVITE_INVALID');
    if (keyId !== ProtocolConstants.KEY_ID_V1) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    return new InviteHeader(1, inviteId, familyId, familyName, targetRole, allowedRoomIds,
      expireAt, maxUses, kdf, keyId);
  }

  static encodeBundle(bundle: FamilySecretBundle): string {
    if (bundle.v !== 1 || bundle.keyId !== ProtocolConstants.KEY_ID_V1) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const gatewayNodes: JsonNode[] = [];
    for (let index = 0; index < bundle.gateways.length; index++) {
      const gateway = bundle.gateways[index];
      const entries: NameValueNode[] = [
        new NameValueNode('commandSecret', JsonNode.string(gateway.commandSecretHex)),
        new NameValueNode('gatewayId', JsonNode.string(gateway.gatewayId))
      ];
      if (gateway.name !== undefined) {
        entries.push(new NameValueNode('name', JsonNode.string(gateway.name)));
      }
      if (gateway.tls !== undefined) {
        const pinNodes: JsonNode[] = [];
        for (let pinIndex = 0; pinIndex < gateway.tls.pins.length; pinIndex++) {
          pinNodes.push(JsonNode.string(gateway.tls.pins[pinIndex]));
        }
        entries.push(new NameValueNode('tls', JsonNode.object([
          new NameValueNode('pins', JsonNode.array(pinNodes)),
          new NameValueNode('port', JsonNode.number(gateway.tls.port))
        ])));
      }
      gatewayNodes.push(JsonNode.object(entries));
    }
    const root = JsonNode.object([
      new NameValueNode('familyId', JsonNode.string(bundle.familyId)),
      new NameValueNode('gateways', JsonNode.array(gatewayNodes)),
      new NameValueNode('issuedAt', JsonNode.string(bundle.issuedAt)),
      new NameValueNode('keyId', JsonNode.string(bundle.keyId)),
      new NameValueNode('seed', JsonNode.string(bundle.seedHex)),
      new NameValueNode('v', JsonNode.number(bundle.v))
    ]);
    const text = JsonCanonicalizer.stringifySorted(root);
    if (BytesUtil.utf8(text).length > MAX_BUNDLE_BYTES) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    return text;
  }

  static decodeBundle(text: string): FamilySecretBundle {
    if (BytesUtil.utf8(text).length > MAX_BUNDLE_BYTES) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const node = InviteCodec.parseObject(BytesUtil.utf8(text), MAX_BUNDLE_BYTES,
      'INVITE_INVALID');
    const versionNode = node.get('v');
    if (versionNode !== undefined && versionNode.kind === JsonKind.NUMBER &&
      versionNode.numberValue !== 1) {
      throw AppErrors.of('INVITE_VERSION_UNSUPPORTED', []);
    }
    InviteCodec.requireKeys(node, ['familyId', 'gateways', 'issuedAt', 'keyId', 'seed', 'v'],
      'INVITE_INVALID');
    const version = InviteCodec.requireNumber(node, 'v', 'INVITE_INVALID');
    if (version !== 1) {
      throw AppErrors.of('INVITE_VERSION_UNSUPPORTED', []);
    }
    const familyId = InviteCodec.requireUuid(node, 'familyId', 'INVITE_INVALID');
    const issuedAt = InviteCodec.requireUtc(node, 'issuedAt', 'INVITE_INVALID');
    const keyId = InviteCodec.requireString(node, 'keyId', 'INVITE_INVALID');
    if (keyId !== ProtocolConstants.KEY_ID_V1) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const seedHex = InviteCodec.requireString(node, 'seed', 'INVITE_INVALID');
    if (seedHex.length !== SEED_BYTES * 2 || !LOWER_HEX_PATTERN.test(seedHex)) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const gatewayNode = node.get('gateways');
    if (gatewayNode === undefined || gatewayNode.kind !== JsonKind.ARRAY) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const gateways: GatewaySecretEntry[] = [];
    for (let index = 0; index < gatewayNode.arrayValue.length; index++) {
      gateways.push(InviteCodec.decodeGateway(gatewayNode.arrayValue[index]));
    }
    return new FamilySecretBundle(1, familyId, issuedAt, keyId, seedHex, gateways);
  }

  // ---- Container ----------------------------------------------------------

  static encodeContainer(headerBytes: Uint8Array, iv: Uint8Array, ciphertext: Uint8Array,
    tag: Uint8Array): string {
    if (iv.length !== GCM_IV_BYTES || tag.length !== GCM_TAG_BYTES) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const body = BytesUtil.concat([ciphertext, tag]);
    const text = INVITE_PREFIX + Base64Url.encode(headerBytes) + '.' +
      Base64Url.encode(iv) + '.' + Base64Url.encode(body);
    if (text.length > MAX_CONTAINER_BYTES) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    return text;
  }

  static decodeContainer(text: string): ContainerEnvelope {
    if (text.length > MAX_CONTAINER_BYTES) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    if (/^YCI[0-9]+\./.test(text) && !text.startsWith(INVITE_PREFIX)) {
      throw AppErrors.of('INVITE_VERSION_UNSUPPORTED', []);
    }
    if (!text.startsWith(INVITE_PREFIX)) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const segments = text.split('.');
    if (segments.length !== 4 || segments[0] !== 'YCI1' ||
      segments[1].length === 0 || segments[2].length === 0 || segments[3].length === 0) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const headerBytes = InviteCodec.decodeBase64Url(segments[1], 'INVITE_INVALID');
    if (headerBytes.length < 2 || headerBytes.length > MAX_HEADER_BYTES) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const header = InviteCodec.decodeHeader(headerBytes);
    const iv = InviteCodec.decodeBase64Url(segments[2], 'INVITE_INVALID');
    if (iv.length !== GCM_IV_BYTES) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const body = InviteCodec.decodeBase64Url(segments[3], 'INVITE_INVALID');
    if (body.length < GCM_TAG_BYTES) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const ciphertext = new Uint8Array(body.length - GCM_TAG_BYTES);
    ciphertext.set(body.subarray(0, body.length - GCM_TAG_BYTES));
    const tag = new Uint8Array(GCM_TAG_BYTES);
    tag.set(body.subarray(body.length - GCM_TAG_BYTES));
    return new ContainerEnvelope(headerBytes, header, iv, ciphertext, tag);
  }

  // ---- Receipt envelope ---------------------------------------------------

  static encodeReceipt(payload: ReceiptPayload): string {
    if (payload.v !== 1) {
      throw AppErrors.of('INVITE_RECEIPT_INVALID', []);
    }
    InviteCodec.requireMemberId(payload.memberId, 'INVITE_RECEIPT_INVALID');
    InviteCodec.requireUuidValue(payload.inviteId, 'INVITE_RECEIPT_INVALID');
    DateTimeUtil.parseUtcCompact(payload.acceptedAt);
    if (payload.mac.length !== 64 || !LOWER_HEX_PATTERN.test(payload.mac)) {
      throw AppErrors.of('INVITE_RECEIPT_INVALID', []);
    }
    const root = JsonNode.object([
      new NameValueNode('acceptedAt', JsonNode.string(payload.acceptedAt)),
      new NameValueNode('inviteId', JsonNode.string(payload.inviteId)),
      new NameValueNode('mac', JsonNode.string(payload.mac)),
      new NameValueNode('memberId', JsonNode.string(payload.memberId)),
      new NameValueNode('v', JsonNode.number(1))
    ]);
    return RECEIPT_PREFIX + Base64Url.encode(
      BytesUtil.utf8(JsonCanonicalizer.stringifySorted(root)));
  }

  static decodeReceipt(text: string): ReceiptPayload {
    if (!text.startsWith(RECEIPT_PREFIX) || text.length <= RECEIPT_PREFIX.length ||
      text.indexOf('.', RECEIPT_PREFIX.length) >= 0) {
      throw AppErrors.of('INVITE_RECEIPT_INVALID', []);
    }
    const bytes = InviteCodec.decodeBase64Url(text.substring(RECEIPT_PREFIX.length),
      'INVITE_RECEIPT_INVALID');
    const node = InviteCodec.parseObject(bytes, MAX_HEADER_BYTES, 'INVITE_RECEIPT_INVALID');
    InviteCodec.requireKeys(node, ['acceptedAt', 'inviteId', 'mac', 'memberId', 'v'],
      'INVITE_RECEIPT_INVALID');
    const version = InviteCodec.requireNumber(node, 'v', 'INVITE_RECEIPT_INVALID');
    if (version !== 1) {
      throw AppErrors.of('INVITE_RECEIPT_INVALID', []);
    }
    const inviteId = InviteCodec.requireUuid(node, 'inviteId', 'INVITE_RECEIPT_INVALID');
    const memberId = InviteCodec.requireString(node, 'memberId', 'INVITE_RECEIPT_INVALID');
    InviteCodec.requireMemberId(memberId, 'INVITE_RECEIPT_INVALID');
    const acceptedAt = InviteCodec.requireUtc(node, 'acceptedAt', 'INVITE_RECEIPT_INVALID');
    const mac = InviteCodec.requireString(node, 'mac', 'INVITE_RECEIPT_INVALID');
    if (mac.length !== 64 || !LOWER_HEX_PATTERN.test(mac)) {
      throw AppErrors.of('INVITE_RECEIPT_INVALID', []);
    }
    return new ReceiptPayload(1, inviteId, memberId, acceptedAt, mac);
  }

  static receiptSigningText(inviteId: string, memberId: string, acceptedAt: string): string {
    return 'YAOCORE-INVITE-RECEIPT-V1\n' + inviteId + '\n' + memberId + '\n' + acceptedAt;
  }

  // ---- Internals ----------------------------------------------------------

  private static validateHeader(header: InviteHeader): void {
    InviteCodec.requireUuidValue(header.inviteId, 'INVITE_INVALID');
    InviteCodec.requireUuidValue(header.familyId, 'INVITE_INVALID');
    InviteCodec.requireText(header.familyName, 63, 'INVITE_INVALID');
    if (header.targetRole !== MemberRole.MEMBER && header.targetRole !== MemberRole.GUEST) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    for (let index = 0; index < header.allowedRoomIds.length; index++) {
      if (!UuidUtil.isValidUuid(header.allowedRoomIds[index])) {
        throw AppErrors.of('INVITE_INVALID', []);
      }
    }
    if (header.targetRole === MemberRole.GUEST && header.allowedRoomIds.length < 1) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    DateTimeUtil.parseUtcCompact(header.expireAt);
    if (header.maxUses < 1) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    if (header.keyId !== ProtocolConstants.KEY_ID_V1) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    if (header.kdf.mode === InviteMode.KEY_WRAP) {
      if (header.maxUses !== 1 || header.kdf.alg !== KEY_WRAP_ALG ||
        header.kdf.adminEphemeralPub === undefined || header.kdf.salt !== undefined ||
        header.kdf.iterations !== undefined) {
        throw AppErrors.of('INVITE_INVALID', []);
      }
      const pub = InviteCodec.decodeBase64Url(header.kdf.adminEphemeralPub, 'INVITE_INVALID');
      if (pub.length !== 32 ||
        Base64Url.encode(pub) !== header.kdf.adminEphemeralPub) {
        throw AppErrors.of('INVITE_INVALID', []);
      }
    } else if (header.kdf.mode === InviteMode.CODE_KEK) {
      if (header.kdf.alg !== CODE_ALG || header.kdf.adminEphemeralPub !== undefined ||
        header.kdf.salt === undefined || header.kdf.iterations !== INVITE_ITERATIONS) {
        throw AppErrors.of('INVITE_INVALID', []);
      }
      const salt = InviteCodec.decodeBase64Url(header.kdf.salt, 'INVITE_INVALID');
      if (salt.length !== 16 || Base64Url.encode(salt) !== header.kdf.salt) {
        throw AppErrors.of('INVITE_INVALID', []);
      }
    } else {
      throw AppErrors.of('INVITE_INVALID', []);
    }
  }

  private static decodeKdf(node: JsonNode, maxUses: number): InviteKdf {
    InviteCodec.requireKeys(node, ['adminEphemeralPub', 'alg', 'iterations', 'mode', 'salt'],
      'INVITE_INVALID');
    const modeText = InviteCodec.requireString(node, 'mode', 'INVITE_INVALID');
    const alg = InviteCodec.requireString(node, 'alg', 'INVITE_INVALID');
    if (modeText === InviteMode.KEY_WRAP) {
      if (maxUses !== 1 || alg !== KEY_WRAP_ALG) {
        throw AppErrors.of('INVITE_INVALID', []);
      }
      const pubText = InviteCodec.requireString(node, 'adminEphemeralPub', 'INVITE_INVALID');
      const pub = InviteCodec.decodeBase64Url(pubText, 'INVITE_INVALID');
      if (pub.length !== 32 || Base64Url.encode(pub) !== pubText) {
        throw AppErrors.of('INVITE_INVALID', []);
      }
      if (node.has('salt') || node.has('iterations')) {
        throw AppErrors.of('INVITE_INVALID', []);
      }
      return InviteKdf.keyWrap(pubText);
    }
    if (modeText !== InviteMode.CODE_KEK || alg !== CODE_ALG) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const saltText = InviteCodec.requireString(node, 'salt', 'INVITE_INVALID');
    const salt = InviteCodec.decodeBase64Url(saltText, 'INVITE_INVALID');
    if (salt.length !== 16 || Base64Url.encode(salt) !== saltText) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const iterations = InviteCodec.requireNumber(node, 'iterations', 'INVITE_INVALID');
    if (iterations !== INVITE_ITERATIONS || node.has('adminEphemeralPub')) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    return InviteKdf.codeKek(saltText, iterations);
  }

  private static decodeGateway(node: JsonNode): GatewaySecretEntry {
    if (node.kind !== JsonKind.OBJECT) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    InviteCodec.requireKeys(node, ['commandSecret', 'gatewayId', 'name', 'tls'],
      'INVITE_INVALID');
    const gatewayId = InviteCodec.requireString(node, 'gatewayId', 'INVITE_INVALID');
    const commandSecret = InviteCodec.requireString(node, 'commandSecret', 'INVITE_INVALID');
    if (commandSecret.length < 32 || commandSecret.length > 128 ||
      commandSecret.length % 2 !== 0 || !LOWER_HEX_PATTERN.test(commandSecret)) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const name = InviteCodec.optionalString(node, 'name', 'INVITE_INVALID');
    if (name !== undefined) {
      InviteCodec.requireText(name, 63, 'INVITE_INVALID');
    }
    let tls: TlsMaterial | undefined = undefined;
    if (node.has('tls')) {
      const tlsNode = InviteCodec.requireObject(node, 'tls', 'INVITE_INVALID');
      InviteCodec.requireKeys(tlsNode, ['pins', 'port'], 'INVITE_INVALID');
      const pins = InviteCodec.requireStringArray(tlsNode, 'pins', 'INVITE_INVALID');
      if (pins.length < 1 || pins.length > 4) {
        throw AppErrors.of('INVITE_INVALID', []);
      }
      for (let index = 0; index < pins.length; index++) {
        if (pins[index].length !== 64 || !LOWER_HEX_PATTERN.test(pins[index])) {
          throw AppErrors.of('INVITE_INVALID', []);
        }
      }
      const port = InviteCodec.requireNumber(tlsNode, 'port', 'INVITE_INVALID');
      if (!Number.isInteger(port) || port < 1 || port > 65535) {
        throw AppErrors.of('INVITE_INVALID', []);
      }
      tls = new TlsMaterial(pins, port, 'sha256-spki-der');
    }
    return new GatewaySecretEntry(gatewayId, commandSecret, name, tls);
  }

  private static parseObject(bytes: Uint8Array, maxBytes: number, code: string): JsonNode {
    try {
      const node = JsonParser.parse(BytesUtil.fromUtf8(bytes),
        new JsonLimits(maxBytes, 8, 1024));
      if (node.kind !== JsonKind.OBJECT) {
        throw AppErrors.of(code, []);
      }
      return node;
    } catch (error) {
      throw AppErrors.of(code, []);
    }
  }

  private static decodeBase64Url(text: string, code: string): Uint8Array {
    try {
      return Base64Url.decode(text);
    } catch (error) {
      throw AppErrors.of(code, []);
    }
  }

  private static requireKeys(node: JsonNode, allowed: ReadonlyArray<string>,
    code: string): void {
    const keys = node.keys();
    for (let index = 0; index < keys.length; index++) {
      let found = false;
      for (let allowedIndex = 0; allowedIndex < allowed.length; allowedIndex++) {
        if (allowed[allowedIndex] === keys[index]) {
          found = true;
          break;
        }
      }
      if (!found) {
        throw AppErrors.of(code, []);
      }
    }
  }

  private static requireString(node: JsonNode, key: string, code: string): string {
    const child = node.get(key);
    if (child === undefined || child.kind !== JsonKind.STRING) {
      throw AppErrors.of(code, []);
    }
    return child.stringValue;
  }

  private static optionalString(node: JsonNode, key: string,
    code: string): string | undefined {
    if (!node.has(key)) {
      return undefined;
    }
    return InviteCodec.requireString(node, key, code);
  }

  private static requireNumber(node: JsonNode, key: string, code: string): number {
    const child = node.get(key);
    if (child === undefined || child.kind !== JsonKind.NUMBER ||
      !Number.isInteger(child.numberValue)) {
      throw AppErrors.of(code, []);
    }
    return child.numberValue;
  }

  private static requireObject(node: JsonNode, key: string, code: string): JsonNode {
    const child = node.get(key);
    if (child === undefined || child.kind !== JsonKind.OBJECT) {
      throw AppErrors.of(code, []);
    }
    return child;
  }

  private static requireStringArray(node: JsonNode, key: string,
    code: string): ReadonlyArray<string> {
    const child = node.get(key);
    if (child === undefined || child.kind !== JsonKind.ARRAY) {
      throw AppErrors.of(code, []);
    }
    const values: string[] = [];
    for (let index = 0; index < child.arrayValue.length; index++) {
      if (child.arrayValue[index].kind !== JsonKind.STRING) {
        throw AppErrors.of(code, []);
      }
      values.push(child.arrayValue[index].stringValue);
    }
    return values;
  }

  private static requireUuidArray(node: JsonNode, key: string): ReadonlyArray<string> {
    const values = InviteCodec.requireStringArray(node, key, 'INVITE_INVALID');
    for (let index = 0; index < values.length; index++) {
      if (!UuidUtil.isValidUuid(values[index])) {
        throw AppErrors.of('INVITE_INVALID', []);
      }
    }
    return values;
  }

  private static requireUtc(node: JsonNode, key: string, code: string): string {
    const value = InviteCodec.requireString(node, key, code);
    try {
      DateTimeUtil.parseUtcCompact(value);
    } catch (error) {
      throw AppErrors.of(code, []);
    }
    return value;
  }

  private static requireUuid(node: JsonNode, key: string, code: string): string {
    const value = InviteCodec.requireString(node, key, code);
    InviteCodec.requireUuidValue(value, code);
    return value;
  }

  private static requireTextValue(node: JsonNode, key: string, max: number): string {
    const value = InviteCodec.requireString(node, key, 'INVITE_INVALID');
    InviteCodec.requireText(value, max, 'INVITE_INVALID');
    return value;
  }

  private static requireText(value: string, max: number, code: string): void {
    if (value.length < 1 || value.length > max) {
      throw AppErrors.of(code, []);
    }
  }

  private static requireUuidValue(value: string, code: string): void {
    if (!UuidUtil.isValidUuid(value)) {
      throw AppErrors.of(code, []);
    }
  }

  private static requireMemberId(value: string, code: string): void {
    if (value.length !== MEMBER_ID_HEX_LENGTH || !LOWER_HEX_PATTERN.test(value)) {
      throw AppErrors.of(code, []);
    }
  }
}
