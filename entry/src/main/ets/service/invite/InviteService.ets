/*
 * YaoCore C-13 InviteService.
 * Producer: agent:implementation-engineer | Task: T-13 / wp-049-family
 * Contract: DES-A §13.1-§13.6; DES-B §23.6; ADR-003 §3-§6; D-009/D-013/D-022
 *
 * Offline credential distribution only: no server, no LAN GCM, no BLE. The
 * member side opens YCI1 locally, applies gateway credentials through
 * InvitationApplicationPort, writes the local member row, and returns a
 * receipt. The admin side persists the seed in SecretStore and verifies
 * receipts with the persistent (inviteId, receiptHash) ledger.
 *
 * Ledger storage: Asset Store alias yaocore.invite.receipt.<receiptHash>.
 * `receiptHash` is SHA-256 over the domain string plus inviteId and the
 * canonical YCP1 text (encodeReceipt(decodeReceipt(text))), so plaintext
 * receipts never reach storage and a semantically equal re-encoding cannot
 * create a second entry. Alias uniqueness is only a final-row uniqueness
 * property of the upsert-based store. The ledger is single-process: the static
 * DomainOperationGate serializes check-then-put and the (inviteId, receiptHash)
 * key design keeps one entry per receipt. This is NOT a cross-process CAS
 * (DES-B §23.6; F-04); multi-process use requires an RDB unique constraint or
 * an inter-process mutex.
 *
 * Device-level acceptance: a persistent Asset Store marker
 * yaocore.invite.accepted.<inviteId> records that this member device already
 * accepted the invitation (DES-A §13.4.7; F-03). The marker survives service
 * restarts. If a later side effect fails, the marker is removed so a valid
 * retry is possible; a crash between the marker write and completion leaves a
 * marker that blocks retry (documented residual).
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { StorageConstants } from '../../common/constants/StorageConstants';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import { BytesUtil } from '../../common/utils/BytesUtil';
import { Base64Url } from '../../common/utils/Base64Url';
import { UuidUtil } from '../../common/utils/UuidUtil';
import { SecureBytes } from '../../common/types/SecureBytes';
import type { ClockPort, IdPort } from '../../common/types/Ports';
import type { RandomPort } from '../../contracts/Ports';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';
import {
  FamilyMember,
  InvitationRecord,
  InvitationStatus,
  InviteMode,
  MemberRole,
  MemberStatus
} from '../../model/FamilyModels';
import { TlsMaterial } from '../../model/GatewayRoute';
import { ProvisioningTlsMaterial } from '../../model/ProvisioningModels';
import { FamilyRepository, InvitationPatch } from '../../repository/FamilyRepository';
import { DomainOperationGate } from '../../repository/DomainOperationGate';
import type { GatewayCredentialPort, GatewayRoutePort, InvitationApplicationPort } from '../../contracts/GatewayPorts';

import { InvitedGateway } from '../../model/InvitedGateway';
import type { SecretStore } from '../../contracts/SecretStore';
import type { CryptoPort, X25519KeyHandle } from '../../contracts/CryptoPort';
import {
  AcceptInvitationOptions,
  AcceptedInvitation,
  CreateInvitationInput,
  FamilySecretBundle,
  GatewaySecretEntry,
  InvitationContainer,
  InvitationCreationResult,
  InviteHeader,
  InviteKdf,
  JoinRequest,
  JoinRequestContainer,
  ReceiptPayload,
  ReceiptVerification,
  RotationPlan
} from './InviteModels';
import { ContainerEnvelope, InviteCodec } from './InviteCodec';

const HKDF_INFO: string = 'yaocore-family-invite-v1';
const RECEIPT_HASH_DOMAIN: string = 'YAOCORE-INVITE-RECEIPT-HASH-V1';
const LEDGER_PREFIX: string = 'yaocore.invite.receipt.';
const ACCEPTED_PREFIX: string = 'yaocore.invite.accepted.';
const CODE_ALPHABET: string = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const CODE_LENGTH: number = 6;
const MAX_BUNDLE_PLAINTEXT: number = 32768;
const ROTATION_STEP_REPROVISION: string = 'invite.rotation.step.reprovision';
const ROTATION_STEP_VERIFY: string = 'invite.rotation.step.verify';

class OpenedKeyWrap {
  readonly memberId: string;
  readonly plaintext: Uint8Array;
  readonly joinAlias: string;

  constructor(memberId: string, plaintext: Uint8Array, joinAlias: string) {
    this.memberId = memberId;
    this.plaintext = plaintext;
    this.joinAlias = joinAlias;
  }
}

class InviteMaterial {
  readonly header: InviteHeader;
  readonly headerBytes: Uint8Array;
  readonly kek: Uint8Array;
  readonly code?: string;
  readonly codeSaltHex?: string;
  readonly iterations?: number;
  readonly memberId?: string;

  constructor(header: InviteHeader, headerBytes: Uint8Array, kek: Uint8Array,
    code?: string, codeSaltHex?: string, iterations?: number, memberId?: string) {
    this.header = header;
    this.headerBytes = headerBytes;
    this.kek = kek;
    this.code = code;
    this.codeSaltHex = codeSaltHex;
    this.iterations = iterations;
    this.memberId = memberId;
  }
}

export class InviteService {
  private readonly crypto: CryptoPort;
  private readonly secrets: SecretStore;
  private readonly families: FamilyRepository;
  private readonly routes: GatewayRoutePort;
  private readonly credentials: GatewayCredentialPort;
  private readonly applications: InvitationApplicationPort;
  private readonly clock: ClockPort;
  private readonly random: RandomPort;
  private readonly ids: IdPort;
  private static readonly LEDGER_GATE: DomainOperationGate = new DomainOperationGate();
  private static readonly ACCEPT_GATE: DomainOperationGate = new DomainOperationGate();
  private readonly joinDisplayNames: Map<string, string> = new Map<string, string>();

  constructor(crypto: CryptoPort, secrets: SecretStore, families: FamilyRepository,
    routes: GatewayRoutePort, credentials: GatewayCredentialPort,
    applications: InvitationApplicationPort, clock: ClockPort, random: RandomPort,
    ids: IdPort) {
    this.crypto = crypto;
    this.secrets = secrets;
    this.families = families;
    this.routes = routes;
    this.credentials = credentials;
    this.applications = applications;
    this.clock = clock;
    this.random = random;
    this.ids = ids;
  }

  // ---- Join request / invitation creation ---------------------------------

  async createJoinRequest(displayName?: string): Promise<JoinRequestContainer> {
    const memberIdBytes = await this.random.nextBytes(16);
    const memberId = BytesUtil.hexLower(memberIdBytes);
    const privateRaw = await this.random.nextBytes(32);
    let publicRaw: Uint8Array;
    try {
      const handle = await this.crypto.importX25519PrivateRaw(privateRaw);
      publicRaw = await this.crypto.exportX25519PublicRaw(handle);
    } catch (error) {
      BytesUtil.zeroize(privateRaw);
      throw error as Error;
    }
    const alias = StorageConstants.inviteJoinAlias(memberId);
    try {
      const secret = SecureBytes.from(privateRaw);
      try {
        await this.secrets.put(alias, secret);
      } finally {
        secret.destroy();
      }
    } finally {
      BytesUtil.zeroize(privateRaw);
    }
    const createdAt = DateTimeUtil.nowUtcCompact(this.clock);
    const checkedName = displayName === undefined ? undefined :
      InviteService.optionalDisplayName(displayName);
    const request = new JoinRequest(1, memberId, Base64Url.encode(publicRaw), createdAt,
      checkedName);
    if (checkedName !== undefined) {
      this.joinDisplayNames.set(memberId, checkedName);
    }
    return new JoinRequestContainer(InviteCodec.encodeJoinRequest(request), request);
  }

  async createInvitation(input: CreateInvitationInput): Promise<InvitationCreationResult> {
    InviteService.validateCreateInput(input);
    const family = await this.families.getFamily(input.familyId);
    if (family === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
    }
    const familyName = input.familyName === undefined ? family.familyName :
      InviteService.familyName(input.familyName);
    const now = this.clock.nowMs();
    const expireAt = DateTimeUtil.formatUtcCompact(now + input.ttlMs);
    const inviteId = UuidUtil.newUuid(this.ids);
    const seed = await this.random.nextBytes(32);
    let seedStored = false;
    const seedHex = BytesUtil.hexLower(seed);
    const seedAlias = StorageConstants.inviteSeedAlias(inviteId);
    let material: InviteMaterial | undefined = undefined;
    try {
      material = await this.buildInviteMaterial(input, family.familyId, familyName, inviteId,
        expireAt);
      const bundle = await this.buildBundle(family.familyId, now, seedHex);
      const plaintext = BytesUtil.utf8(InviteCodec.encodeBundle(bundle));
      let text: string;
      try {
        if (plaintext.length > MAX_BUNDLE_PLAINTEXT) {
          throw AppErrors.of('INVITE_INVALID', []);
        }
        const iv = await this.random.nextBytes(12);
        const gcm = await this.crypto.encryptAesGcm(material.kek, iv,
          material.headerBytes, plaintext);
        text = InviteCodec.encodeContainer(material.headerBytes, iv, gcm.ciphertext, gcm.tag);
      } finally {
        BytesUtil.zeroize(plaintext);
      }
      // Admin keeps the receipt key; the record stores only the Asset alias.
      const seedSecret = SecureBytes.from(seed);
      try {
        await this.secrets.put(seedAlias, seedSecret);
        seedStored = true;
      } finally {
        seedSecret.destroy();
      }
      const record = new InvitationRecord(inviteId, family.familyId, familyName,
        family.ownerMemberId, input.targetRole, input.allowedRoomIds, input.mode,
        InvitationStatus.PENDING, expireAt,
        input.mode === InviteMode.KEY_WRAP ? 1 : input.maxUses, 0, text, seedAlias,
        material.codeSaltHex, material.iterations, material.memberId);
      return new InvitationCreationResult(
        new InvitationContainer(text, material.header), record, material.code);
    } catch (error) {
      if (seedStored) {
        await InviteService.removeQuietly(this.secrets, seedAlias);
      }
      throw error as Error;
    } finally {
      BytesUtil.zeroize(seed);
      if (material !== undefined) {
        BytesUtil.zeroize(material.kek);
      }
    }
  }

  // ---- Acceptance ---------------------------------------------------------

  async acceptInvitation(containerText: string,
    options: AcceptInvitationOptions): Promise<AcceptedInvitation> {
    if (!Number.isFinite(options.nowMs) || options.nowMs < 0) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'nowMs');
    }
    const envelope = InviteCodec.decodeContainer(containerText);
    const header = envelope.header;
    if (DateTimeUtil.parseUtcCompact(header.expireAt) <= options.nowMs) {
      throw AppErrors.of('INVITE_EXPIRED', []);
    }
    let plaintext: Uint8Array | undefined = undefined;
    let memberId: string = '';
    let displayName: string = '';
    let joinAlias: string = '';
    let kek: Uint8Array | undefined = undefined;
    try {
      if (header.kdf.mode === InviteMode.KEY_WRAP) {
        const opened = await this.openKeyWrap(envelope);
        if (opened === undefined) {
          throw AppErrors.of('INVITE_INVALID', []);
        }
        plaintext = opened.plaintext;
        memberId = opened.memberId;
        joinAlias = opened.joinAlias;
        const cached = this.joinDisplayNames.get(memberId);
        displayName = cached === undefined ? memberId : cached;
      } else {
        if (options.code === undefined || options.code.length === 0) {
          throw AppErrors.of('INVITE_CODE_INVALID', []);
        }
        const normalized = InviteService.normalizeCode(options.code);
        if (normalized === undefined) {
          throw AppErrors.of('INVITE_CODE_INVALID', []);
        }
        kek = await this.openCodeKek(envelope, normalized);
        plaintext = await this.decryptInvite(envelope, kek);
        memberId = BytesUtil.hexLower(await this.random.nextBytes(16));
        displayName = memberId;
      }
      if (plaintext === undefined) {
        throw AppErrors.of('INVITE_INVALID', []);
      }
      if (plaintext.length > MAX_BUNDLE_PLAINTEXT) {
        throw AppErrors.of('INVITE_INVALID', []);
      }
      const bundle = InviteCodec.decodeBundle(BytesUtil.fromUtf8(plaintext));
      if (bundle.familyId !== header.familyId || bundle.keyId !== header.keyId ||
        bundle.v !== 1) {
        throw AppErrors.of('INVITE_INVALID', []);
      }
      const nowText = DateTimeUtil.formatUtcCompact(options.nowMs);
      // DES-A §13.4.7: one acceptance per member device and inviteId. The
      // marker is written only after the container is authenticated and is
      // removed if any later step fails, so a legitimate retry can succeed.
      let claimed = false;
      try {
        await this.claimAcceptance(header.inviteId, memberId, nowText);
        claimed = true;
        // F-02 / DES-A §13.4.10: an authenticated container creates/ensures
        // the local family row with the invitation's fixed familyId. A brand
        // new member device must not require a pre-seeded family row.
        await this.families.importFamily(header.familyId, header.familyName);
        const appliedGatewayIds: string[] = [];
        for (let index = 0; index < bundle.gateways.length; index++) {
          const entry = bundle.gateways[index];
          await this.applyGateway(header.familyId, entry);
          appliedGatewayIds.push(entry.gatewayId);
        }
        const expiresAt = header.targetRole === MemberRole.GUEST ? header.expireAt : undefined;
        const member = new FamilyMember(memberId, header.familyId, memberId, displayName,
          header.targetRole, MemberStatus.ACTIVE, nowText, header.allowedRoomIds, expiresAt,
          memberId, header.kdf.mode === InviteMode.KEY_WRAP ? 'INVITE_KEY_WRAP' :
            'INVITE_CODE_KEK');
        await this.families.upsertMember(member);
        const receipt = await this.buildReceipt(header.inviteId, memberId, nowText,
          bundle.seedHex);
        if (joinAlias.length > 0) {
          // One-time member key. A failure to delete is non-fatal after the
          // join succeeded; the accepted marker still prevents reuse on this
          // device (F-10 best-effort deletion; residual in the fix report).
          await InviteService.removeQuietly(this.secrets, joinAlias);
          this.joinDisplayNames.delete(memberId);
        }
        return new AcceptedInvitation(header.familyId, header.familyName, memberId,
          header.targetRole, header.allowedRoomIds, appliedGatewayIds, receipt);
      } catch (error) {
        if (claimed) {
          await InviteService.removeQuietly(this.secrets,
            ACCEPTED_PREFIX + header.inviteId);
        }
        throw error as Error;
      }
    } finally {
      if (plaintext !== undefined) {
        BytesUtil.zeroize(plaintext);
      }
      if (kek !== undefined) {
        BytesUtil.zeroize(kek);
      }
    }
  }

  // ---- Receipts -----------------------------------------------------------

  async verifyReceipt(receiptText: string, inviteId: string): Promise<ReceiptVerification> {
    const payload = InviteCodec.decodeReceipt(receiptText);
    if (payload.inviteId !== inviteId) {
      throw AppErrors.of('INVITE_RECEIPT_INVALID', []);
    }
    const record = await this.families.getInvitation(inviteId);
    if (record === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'inviteId')]);
    }
    if (record.status === InvitationStatus.REVOKED) {
      throw AppErrors.of('INVITE_REVOKED', []);
    }
    if (record.status === InvitationStatus.EXPIRED) {
      throw AppErrors.of('INVITE_EXPIRED', []);
    }
    if (record.usedCount >= record.maxUses) {
      throw AppErrors.of('INVITE_MAX_USES', []);
    }
    if (DateTimeUtil.parseUtcCompact(record.expireAt) <= this.clock.nowMs()) {
      throw AppErrors.of('INVITE_EXPIRED', []);
    }
    const seed = await this.readSeed(record.seedAlias);
    let expected: Uint8Array;
    try {
      const signing = BytesUtil.utf8(InviteCodec.receiptSigningText(inviteId,
        payload.memberId, payload.acceptedAt));
      try {
        expected = await this.crypto.hmacSha256(seed, signing);
      } finally {
        BytesUtil.zeroize(signing);
      }
    } finally {
      BytesUtil.zeroize(seed);
    }
    let actual: Uint8Array;
    try {
      actual = BytesUtil.hexToBytesStrictLower(payload.mac);
    } catch (error) {
      BytesUtil.zeroize(expected);
      throw AppErrors.of('INVITE_RECEIPT_INVALID', []);
    }
    let matches = false;
    try {
      matches = this.crypto.constantTimeEqual(actual, expected);
    } finally {
      BytesUtil.zeroize(actual);
      BytesUtil.zeroize(expected);
    }
    if (!matches) {
      throw AppErrors.of('INVITE_RECEIPT_INVALID', []);
    }
    // F-01 / DES-A §13.2.1: hash the canonical bytes produced by re-encoding
    // the decoded payload, never the raw input text. decodeReceipt already
    // rejects non-canonical text, so equal-semantics variants cannot mint a
    // second receiptHash.
    const canonicalReceipt = InviteCodec.encodeReceipt(payload);
    const receiptHash = await this.receiptHash(inviteId, canonicalReceipt);
    const recorded = await InviteService.LEDGER_GATE.run(async (): Promise<boolean> => {
      return this.recordLedger(receiptHash, inviteId, payload.memberId, payload.acceptedAt);
    });
    if (!recorded) {
      throw AppErrors.of('INVITE_RECEIPT_INVALID', []);
    }
    return new ReceiptVerification(true, inviteId, payload.memberId, payload.acceptedAt);
  }

  /**
   * F-05 compensation for the non-atomic Asset-ledger + RDB write. C-08 calls
   * this only when its receipt transaction fails after verifyReceipt returned
   * success. It removes the canonical ledger entry so the same valid receipt
   * can be retried. Missing entries are a no-op.
   */
  async releaseReceipt(receiptText: string, inviteId: string): Promise<void> {
    const payload = InviteCodec.decodeReceipt(receiptText);
    if (payload.inviteId !== inviteId) {
      throw AppErrors.of('INVITE_RECEIPT_INVALID', []);
    }
    const canonicalReceipt = InviteCodec.encodeReceipt(payload);
    const receiptHash = await this.receiptHash(inviteId, canonicalReceipt);
    try {
      await this.secrets.remove(LEDGER_PREFIX + receiptHash);
    } catch (error) {
      if (error instanceof AppError && error.code === 'ASSET_NOT_FOUND') {
        return;
      }
      throw error as Error;
    }
  }

  // ---- Lifecycle ----------------------------------------------------------

  async revokeInvitation(inviteId: string): Promise<void> {
    const record = await this.families.getInvitation(inviteId);
    if (record === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'inviteId')]);
    }
    if (record.status === InvitationStatus.REVOKED) {
      return;
    }
    if (record.status === InvitationStatus.EXPIRED) {
      throw AppErrors.of('INVITE_EXPIRED', []);
    }
    if (record.usedCount >= record.maxUses) {
      throw AppErrors.of('INVITE_MAX_USES', []);
    }
    const now = DateTimeUtil.nowUtcCompact(this.clock);
    await this.families.markInvitationStatus(inviteId, InvitationStatus.REVOKED,
      new InvitationPatch(undefined, undefined, undefined, now, 'USER_REVOKED'));
    // F-13: a revoked invitation is terminal. Drop the Admin seed from Asset
    // Store instead of retaining it until app-data wipe. Best effort: the
    // status is already terminal and receipt verification rejects REVOKED
    // before reading the seed.
    await InviteService.removeQuietly(this.secrets, record.seedAlias);
  }

  async rotateGatewaySecret(gatewayId: string): Promise<RotationPlan> {
    const route = await this.routes.getRoute(gatewayId);
    if (route === undefined) {
      throw AppErrors.of('GATEWAY_NOT_BOUND', []);
    }
    return new RotationPlan(gatewayId, [ROTATION_STEP_REPROVISION, ROTATION_STEP_VERIFY]);
  }

  async discardJoinRequest(memberId: string): Promise<void> {
    if (memberId.length < 1 || memberId.length > 63) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'memberId');
    }
    await InviteService.removeQuietly(this.secrets,
      StorageConstants.inviteJoinAlias(memberId));
    this.joinDisplayNames.delete(memberId);
  }

  // ---- Internals ----------------------------------------------------------

  private async buildInviteMaterial(input: CreateInvitationInput, familyId: string,
    familyName: string, inviteId: string, expireAt: string): Promise<InviteMaterial> {
    const header = input.mode === InviteMode.KEY_WRAP ?
      await this.buildKeyWrapMaterial(input, familyId, familyName, inviteId, expireAt) :
      await this.buildCodeKekMaterial(input, familyId, familyName, inviteId, expireAt);
    return header;
  }

  private async buildKeyWrapMaterial(input: CreateInvitationInput, familyId: string,
    familyName: string, inviteId: string, expireAt: string): Promise<InviteMaterial> {
    const joinContainer = input.joinRequest;
    if (joinContainer === undefined) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'joinRequest');
    }
    const join = InviteCodec.decodeJoinRequest(joinContainer.text);
    const adminPair = await this.crypto.generateX25519KeyPair();
    const kdf = InviteKdf.keyWrap(Base64Url.encode(adminPair.publicKeyRaw));
    const header = new InviteHeader(1, inviteId, familyId, familyName, input.targetRole,
      input.allowedRoomIds, expireAt, 1, kdf, ProtocolConstants.KEY_ID_V1);
    const headerBytes = InviteCodec.encodeHeader(header);
    const shared = await this.crypto.computeX25519(adminPair.privateKey,
      Base64Url.decode(join.pub));
    let kek: Uint8Array;
    try {
      kek = await this.crypto.hkdfSha256(shared, headerBytes,
        BytesUtil.utf8(HKDF_INFO), 32);
    } finally {
      BytesUtil.zeroize(shared);
    }
    return new InviteMaterial(header, headerBytes, kek, undefined, undefined, undefined,
      join.memberId);
  }

  private async buildCodeKekMaterial(input: CreateInvitationInput, familyId: string,
    familyName: string, inviteId: string, expireAt: string): Promise<InviteMaterial> {
    const code = InviteService.generateCode(await this.random.nextBytes(CODE_LENGTH));
    const salt = await this.random.nextBytes(16);
    let normalized: string | undefined = undefined;
    let pass: Uint8Array | undefined = undefined;
    let kek: Uint8Array;
    try {
      normalized = InviteService.normalizeCode(code);
      if (normalized === undefined) {
        throw AppErrors.of('INVITE_CODE_INVALID', []);
      }
      const kdf = InviteKdf.codeKek(Base64Url.encode(salt), 120000);
      const header = new InviteHeader(1, inviteId, familyId, familyName, input.targetRole,
        input.allowedRoomIds, expireAt, input.maxUses, kdf, ProtocolConstants.KEY_ID_V1);
      const headerBytes = InviteCodec.encodeHeader(header);
      const passwordBytes = BytesUtil.utf8(normalized);
      try {
        pass = await this.crypto.pbkdf2Sha256(passwordBytes, salt, 120000, 32);
      } finally {
        BytesUtil.zeroize(passwordBytes);
      }
      kek = await this.crypto.hkdfSha256(pass, headerBytes, BytesUtil.utf8(HKDF_INFO), 32);
      return new InviteMaterial(header, headerBytes, kek, code, BytesUtil.hexLower(salt),
        120000, undefined);
    } catch (error) {
      if (error instanceof AppError && error.code === 'CRYPTO_UNAVAILABLE') {
        throw error;
      }
      throw error as Error;
    } finally {
      BytesUtil.zeroize(salt);
      if (pass !== undefined) {
        BytesUtil.zeroize(pass);
      }
    }
  }

  private async buildBundle(familyId: string, issuedAtMs: number,
    seedHex: string): Promise<FamilySecretBundle> {
    const routeList = await this.routes.listRoutesByFamily(familyId);
    const gateways: GatewaySecretEntry[] = [];
    for (let index = 0; index < routeList.length; index++) {
      const route = routeList[index];
      const commandSecretHex = await this.credentials.withCommandSecret(route.gatewayId,
        async (secret: Uint8Array): Promise<string> => {
          if (secret.length < 16) {
            throw AppErrors.of('CONFIGURATION_ERROR', []);
          }
          return BytesUtil.hexLower(secret);
        });
      let tls: TlsMaterial | undefined = undefined;
      if (route.tlsEnabled) {
        const material = await this.credentials.tlsMaterial(route.gatewayId);
        if (material === undefined) {
          throw AppErrors.of('TLS_PROFILE_INCONSISTENT', []);
        }
        tls = material;
      }
      gateways.push(new GatewaySecretEntry(route.gatewayId, commandSecretHex,
        route.gatewayName, tls));
    }
    return new FamilySecretBundle(1, familyId, DateTimeUtil.formatUtcCompact(issuedAtMs),
      ProtocolConstants.KEY_ID_V1, seedHex, gateways);
  }

  private async openKeyWrap(envelope: ContainerEnvelope): Promise<OpenedKeyWrap | undefined> {
    const aliases = await this.secrets.list(StorageConstants.ASSET_PREFIX_INVITE_JOIN);
    const prefix = StorageConstants.ASSET_PREFIX_INVITE_JOIN;
    const candidates: string[] = [];
    for (let index = 0; index < aliases.length; index++) {
      if (aliases[index].startsWith(prefix)) {
        candidates.push(aliases[index]);
      }
    }
    if (candidates.length === 0) {
      throw AppErrors.of('INVITE_KEY_MISSING', []);
    }
    const adminPubText = envelope.header.kdf.adminEphemeralPub;
    if (adminPubText === undefined) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const adminPub = Base64Url.decode(adminPubText);
    for (let index = 0; index < candidates.length; index++) {
      const alias = candidates[index];
      const memberId = alias.substring(prefix.length);
      if (!InviteService.isMemberId(memberId)) {
        continue;
      }
      let plaintext: Uint8Array | undefined = undefined;
      try {
        plaintext = await this.secrets.withSecret(alias,
          async (privateRaw: Uint8Array): Promise<Uint8Array | undefined> => {
            let handle: X25519KeyHandle;
            try {
              handle = await this.crypto.importX25519PrivateRaw(privateRaw);
            } catch (error) {
              InviteService.rethrowUnavailable(error as Error);
              return undefined;
            }
            const shared = await this.crypto.computeX25519(handle, adminPub);
            let candidateKek: Uint8Array | undefined = undefined;
            try {
              candidateKek = await this.crypto.hkdfSha256(shared, envelope.headerBytes,
                BytesUtil.utf8(HKDF_INFO), 32);
              try {
                return await this.decrypt(envelope, candidateKek);
              } catch (error) {
                InviteService.rethrowUnavailable(error as Error);
                return undefined;
              }
            } finally {
              BytesUtil.zeroize(shared);
              if (candidateKek !== undefined) {
                BytesUtil.zeroize(candidateKek);
              }
            }
          });
      } catch (error) {
        InviteService.rethrowUnavailable(error as Error);
      }
      if (plaintext !== undefined) {
        return new OpenedKeyWrap(memberId, plaintext, alias);
      }
    }
    return undefined;
  }

  private async openCodeKek(envelope: ContainerEnvelope, normalizedCode: string): Promise<Uint8Array> {
    const saltText = envelope.header.kdf.salt;
    if (saltText === undefined) {
      throw AppErrors.of('INVITE_INVALID', []);
    }
    const salt = Base64Url.decode(saltText);
    const iterations = envelope.header.kdf.iterations === undefined ? 120000 :
      envelope.header.kdf.iterations;
    const passwordBytes = BytesUtil.utf8(normalizedCode);
    let pass: Uint8Array;
    try {
      pass = await this.crypto.pbkdf2Sha256(passwordBytes, salt, iterations, 32);
    } catch (error) {
      if (error instanceof AppError && error.code === 'CRYPTO_UNAVAILABLE') {
        throw error;
      }
      throw AppErrors.of('INVITE_INVALID', []);
    } finally {
      BytesUtil.zeroize(passwordBytes);
      BytesUtil.zeroize(salt);
    }
    try {
      return await this.crypto.hkdfSha256(pass, envelope.headerBytes,
        BytesUtil.utf8(HKDF_INFO), 32);
    } catch (error) {
      if (error instanceof AppError && error.code === 'CRYPTO_UNAVAILABLE') {
        throw error;
      }
      throw AppErrors.of('INVITE_INVALID', []);
    } finally {
      BytesUtil.zeroize(pass);
    }
  }

  private async decrypt(envelope: ContainerEnvelope, kek: Uint8Array): Promise<Uint8Array> {
    return this.crypto.decryptAesGcm(kek, envelope.iv, envelope.headerBytes,
      envelope.ciphertext, envelope.tag);
  }

  private async decryptInvite(envelope: ContainerEnvelope,
    kek: Uint8Array): Promise<Uint8Array> {
    try {
      return await this.decrypt(envelope, kek);
    } catch (error) {
      if (error instanceof AppError && error.code === 'CRYPTO_UNAVAILABLE') {
        throw error;
      }
      throw AppErrors.of('INVITE_INVALID', []);
    }
  }

  private async applyGateway(familyId: string, entry: GatewaySecretEntry): Promise<void> {
    let tls: ProvisioningTlsMaterial | undefined = undefined;
    if (entry.tls !== undefined) {
      tls = new ProvisioningTlsMaterial(entry.tls.pins, entry.tls.port, entry.tls.pinAlg);
    }
    const secret = SecureBytes.fromHex(entry.commandSecretHex);
    try {
      await this.applications.applyInvitedGateway(new InvitedGateway(entry.gatewayId,
        familyId, entry.name === undefined ? entry.gatewayId : entry.name, secret, tls));
    } finally {
      secret.destroy();
    }
  }

  private async buildReceipt(inviteId: string, memberId: string, acceptedAt: string,
    seedHex: string): Promise<string> {
    const seed = BytesUtil.hexToBytesStrictLower(seedHex);
    try {
      const signing = BytesUtil.utf8(InviteCodec.receiptSigningText(inviteId, memberId,
        acceptedAt));
      let mac: Uint8Array;
      try {
        mac = await this.crypto.hmacSha256(seed, signing);
      } finally {
        BytesUtil.zeroize(signing);
      }
      try {
        return InviteCodec.encodeReceipt(new ReceiptPayload(1, inviteId, memberId,
          acceptedAt, BytesUtil.hexLower(mac)));
      } finally {
        BytesUtil.zeroize(mac);
      }
    } finally {
      BytesUtil.zeroize(seed);
    }
  }

  private async readSeed(alias: string): Promise<Uint8Array> {
    try {
      return await this.secrets.withSecret(alias,
        async (seed: Uint8Array): Promise<Uint8Array> => BytesUtil.copyOf(seed));
    } catch (error) {
      if (error instanceof AppError && error.code === 'ASSET_NOT_FOUND') {
        throw AppErrors.of('INVITE_KEY_MISSING', []);
      }
      throw error as Error;
    }
  }

  private async receiptHash(inviteId: string, canonicalReceipt: string): Promise<string> {
    const receiptHashBytes = await this.crypto.sha256(BytesUtil.utf8(RECEIPT_HASH_DOMAIN +
      '\n' + inviteId + '\n' + canonicalReceipt));
    const receiptHash = BytesUtil.hexLower(receiptHashBytes);
    BytesUtil.zeroize(receiptHashBytes);
    return receiptHash;
  }

  private async claimAcceptance(inviteId: string, memberId: string,
    acceptedAt: string): Promise<void> {
    const alias = ACCEPTED_PREFIX + inviteId;
    await InviteService.ACCEPT_GATE.run(async (): Promise<void> => {
      let exists = true;
      try {
        await this.secrets.withSecret(alias,
          async (stored: Uint8Array): Promise<boolean> => true);
      } catch (error) {
        if (error instanceof AppError && error.code === 'ASSET_NOT_FOUND') {
          exists = false;
        } else {
          throw error as Error;
        }
      }
      if (exists) {
        // DES-A §13.4.7: this member device already accepted this inviteId.
        throw AppErrors.of('INVITE_INVALID', []);
      }
      const metadata = '{"acceptedAt":' + JSON.stringify(acceptedAt) +
        ',"inviteId":' + JSON.stringify(inviteId) +
        ',"memberId":' + JSON.stringify(memberId) +
        ',"v":1}';
      const bytes = BytesUtil.utf8(metadata);
      const secret = SecureBytes.from(bytes);
      try {
        await this.secrets.put(alias, secret);
      } finally {
        secret.destroy();
        BytesUtil.zeroize(bytes);
      }
    });
  }

  private async recordLedger(receiptHash: string, inviteId: string, memberId: string,
    acceptedAt: string): Promise<boolean> {
    const alias = LEDGER_PREFIX + receiptHash;
    let exists = true;
    try {
      await this.secrets.withSecret(alias,
        async (stored: Uint8Array): Promise<boolean> => true);
    } catch (error) {
      if (error instanceof AppError && error.code === 'ASSET_NOT_FOUND') {
        exists = false;
      } else {
        throw error as Error;
      }
    }
    if (exists) {
      return false;
    }
    const metadata = '{"acceptedAt":' + JSON.stringify(acceptedAt) +
      ',"inviteId":' + JSON.stringify(inviteId) +
      ',"memberId":' + JSON.stringify(memberId) +
      ',"receiptHash":' + JSON.stringify(receiptHash) +
      ',"recordedAt":' + JSON.stringify(DateTimeUtil.nowUtcCompact(this.clock)) +
      ',"v":1}';
    const bytes = BytesUtil.utf8(metadata);
    const secret = SecureBytes.from(bytes);
    try {
      await this.secrets.put(alias, secret);
    } finally {
      secret.destroy();
      BytesUtil.zeroize(bytes);
    }
    return true;
  }

  private static rethrowUnavailable(error: Error): void {
    if (error instanceof AppError && error.code === 'CRYPTO_UNAVAILABLE') {
      throw error;
    }
  }

  private static validateCreateInput(input: CreateInvitationInput): void {
    if (input.familyId.length < 1 || input.familyId.length > 63) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'familyId');
    }
    if (input.targetRole !== MemberRole.MEMBER && input.targetRole !== MemberRole.GUEST) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'targetRole');
    }
    for (let index = 0; index < input.allowedRoomIds.length; index++) {
      if (!UuidUtil.isValidUuid(input.allowedRoomIds[index])) {
        throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'allowedRoomIds');
      }
    }
    if (input.targetRole === MemberRole.GUEST && input.allowedRoomIds.length < 1) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'allowedRoomIds');
    }
    if (!Number.isInteger(input.maxUses) || input.maxUses < 1) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'maxUses');
    }
    if (!Number.isInteger(input.ttlMs) || input.ttlMs < 1) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'ttlMs');
    }
    if (input.mode === InviteMode.KEY_WRAP) {
      if (input.maxUses !== 1 || input.joinRequest === undefined) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'maxUses');
      }
    } else if (input.mode !== InviteMode.CODE_KEK) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'mode');
    }
  }

  private static normalizeCode(code: string): string | undefined {
    if (typeof code !== 'string') {
      return undefined;
    }
    let text = code.trim().toUpperCase();
    text = text.split('-').join('');
    text = text.split(' ').join('');
    text = text.split('O').join('0');
    text = text.split('I').join('1');
    text = text.split('L').join('1');
    if (text.length !== CODE_LENGTH) {
      return undefined;
    }
    let normalized = '';
    for (let index = 0; index < text.length; index++) {
      const character = text.charAt(index);
      if (CODE_ALPHABET.indexOf(character) < 0) {
        return undefined;
      }
      normalized += character;
    }
    return normalized;
  }

  private static generateCode(bytes: Uint8Array): string {
    let code = '';
    for (let index = 0; index < CODE_LENGTH; index++) {
      code += CODE_ALPHABET.charAt(bytes[index] % CODE_ALPHABET.length);
    }
    return code;
  }

  private static optionalDisplayName(value: string): string {
    const trimmed = value.trim();
    if (trimmed.length < 1 || trimmed.length > 63) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'displayName');
    }
    return trimmed;
  }

  private static familyName(value: string): string {
    const trimmed = value.trim();
    if (trimmed.length < 1 || trimmed.length > 63) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'familyName');
    }
    return trimmed;
  }

  private static isMemberId(value: string): boolean {
    if (value.length !== 32) {
      return false;
    }
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      if (!((code >= 0x30 && code <= 0x39) || (code >= 0x61 && code <= 0x66))) {
        return false;
      }
    }
    return true;
  }

  private static async removeQuietly(secrets: SecretStore, alias: string): Promise<void> {
    try {
      await secrets.remove(alias);
    } catch (error) {
      // ASSET_NOT_FOUND is expected for an already-consumed join key. Other
      // failures are not fatal to an otherwise completed local operation.
    }
  }
}
