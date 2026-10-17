/*
 * YaoCore T-09 host fakes for C-08..C-11 ports.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 *
 * PUBLIC TEST DATA ONLY. These fakes never default to a hiding behaviour:
 * configured failures throw the production AppError code, and every command /
 * invite / auth call is recorded for zero-network and ordering assertions.
 */
import { AppError, AppErrors } from '../../main/ets/common/types/AppError';
import { NameValue } from '../../main/ets/common/types/NameValue';
import { ProtocolConstants } from '../../main/ets/common/constants/ProtocolConstants';
import { StorageConstants } from '../../main/ets/common/constants/StorageConstants';
import type { ClockPort, LoggerPort, MetricsPort } from '../../main/ets/common/types/Ports';
import { DateTimeUtil } from '../../main/ets/common/utils/DateTimeUtil';
import { TransportProfile } from '../../main/ets/model/DeviceTypes';
import { GatewayRoute, GatewayRouteInit } from '../../main/ets/model/GatewayRoute';
import type { GatewayRoutePort } from '../../main/ets/repository/GatewayPorts';
import {
  InvitationRecord,
  InvitationStatus,
  InviteMode,
  MemberRole
} from '../../main/ets/model/FamilyModels';
import {
  DeviceControlCommand,
  ControlOutcome,
  ControlOutcomeInit,
  GatewayBoardState,
  StateVerification
} from '../../main/ets/model/ControlModels';
import { DeviceStatePatch, DeviceStatePatchInit } from '../../main/ets/model/DeviceState';
import { GatewayResultClassifier } from '../../main/ets/common/types/GatewayResult';
import type { DeviceControlPort } from '../../main/ets/repository/DomainPorts';
import {
  AcceptInviteOptions,
  AcceptedInvitation,
  FamilyProfileRef,
  InviteCreateRequest,
  InviteCreation,
  JoinRequestHandle,
  ReceiptVerification,
  RotationPlan
} from '../../main/ets/service/family/FamilyModels';
import type { FamilyAuthPort, InviteServicePort } from '../../main/ets/service/family/FamilyModels';
import type { SceneTimerPort } from '../../main/ets/service/scene/SceneTimerPort';

const FIXED_UTC: string = '20261017T080000Z';

export class FakeLogger implements LoggerPort {
  readonly entries: string[] = [];

  debug(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
    this.entries.push('D ' + tag + ' ' + message);
  }

  info(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
    this.entries.push('I ' + tag + ' ' + message);
  }

  warn(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
    this.entries.push('W ' + tag + ' ' + message);
  }

  error(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
    this.entries.push('E ' + tag + ' ' + message);
  }
}

export class FakeMetrics implements MetricsPort {
  readonly names: string[] = [];
  readonly values: number[] = [];

  record(name: string, valueMs: number, tags?: ReadonlyArray<NameValue>): void {
    this.names.push(name);
    this.values.push(valueMs);
  }
}

export class FakeRoutePort implements GatewayRoutePort {
  private readonly routes: Map<string, GatewayRoute> = new Map<string, GatewayRoute>();

  add(gatewayId: string, familyId: string, gatewayName: string = 'Test Gateway'): void {
    const init = new GatewayRouteInit();
    init.gatewayId = gatewayId;
    init.familyId = familyId;
    init.gatewayName = gatewayName;
    init.localIp = '127.0.0.1';
    init.port = ProtocolConstants.DEFAULT_GATEWAY_PORT;
    init.profile = TransportProfile.P_HMAC;
    init.tlsEnabled = false;
    init.pins = [];
    init.pinAlg = '';
    init.keyId = ProtocolConstants.KEY_ID_V1;
    init.credentialAlias = StorageConstants.gatewayHmacAlias(gatewayId);
    init.lastKnownIp = '';
    init.createdAt = FIXED_UTC;
    init.updatedAt = FIXED_UTC;
    this.routes.set(gatewayId, GatewayRoute.create(init));
  }

  async listRoutes(): Promise<ReadonlyArray<GatewayRoute>> {
    const result: GatewayRoute[] = [];
    this.routes.forEach((route: GatewayRoute): void => {
      result.push(route);
    });
    return result;
  }

  async listRoutesByFamily(familyId: string): Promise<ReadonlyArray<GatewayRoute>> {
    const result: GatewayRoute[] = [];
    this.routes.forEach((route: GatewayRoute): void => {
      if (route.familyId === familyId) {
        result.push(route);
      }
    });
    return result;
  }

  async getRoute(gatewayId: string): Promise<GatewayRoute | undefined> {
    return this.routes.get(gatewayId);
  }

  async isBound(gatewayId: string): Promise<boolean> {
    return this.routes.has(gatewayId);
  }
}

export class FakeDeviceControlPort implements DeviceControlPort {
  readonly commands: DeviceControlCommand[] = [];
  readonly outcomes: ControlOutcome[] = [];
  failNext?: AppError = undefined;
  defaultAccepted: boolean = true;

  async send(command: DeviceControlCommand): Promise<ControlOutcome> {
    this.commands.push(command);
    if (this.failNext !== undefined) {
      const error = this.failNext;
      this.failNext = undefined;
      throw error;
    }
    if (this.outcomes.length > 0) {
      const outcome = this.outcomes.shift();
      if (outcome !== undefined) {
        return outcome;
      }
    }
    return FakeDeviceControlPort.defaultOutcome(command, this.defaultAccepted);
  }

  static defaultOutcome(command: DeviceControlCommand, accepted: boolean): ControlOutcome {
    const init = new ControlOutcomeInit();
    init.requestId = 'req-1-' + String(FakeDeviceControlPort.sequence);
    init.seq = FakeDeviceControlPort.sequence;
    FakeDeviceControlPort.sequence++;
    init.resultCode = accepted ? 0 : 1001;
    init.ackAccepted = accepted;
    init.gatewayResult = GatewayResultClassifier.classify(init.resultCode);
    init.stateVerification = StateVerification.UNVERIFIED;
    init.gatewayBoardState = new GatewayBoardState(command.gatewayId, true, false, FIXED_UTC);
    init.shouldApplyState = false;
    return ControlOutcome.create(init);
  }

  static acceptedWithState(command: DeviceControlCommand, deviceId: string, epoch: string,
    match: boolean): ControlOutcome {
    const patchInit = new DeviceStatePatchInit();
    patchInit.deviceId = deviceId;
    patchInit.isOnline = true;
    patchInit.updatedAt = epoch;
    const init = new ControlOutcomeInit();
    init.requestId = 'req-2-' + String(FakeDeviceControlPort.sequence);
    init.seq = FakeDeviceControlPort.sequence + 10;
    FakeDeviceControlPort.sequence++;
    init.resultCode = 0;
    init.ackAccepted = true;
    init.reportedState = DeviceStatePatch.create(patchInit);
    init.stateVerification = match ? StateVerification.MATCH : StateVerification.MISMATCH;
    init.gatewayResult = GatewayResultClassifier.classify(0);
    init.shouldApplyState = true;
    return ControlOutcome.create(init);
  }

  private static sequence: number = 1;
}

export class FakeInviteService implements InviteServicePort {
  readonly createRequests: InviteCreateRequest[] = [];
  readonly revoked: string[] = [];
  readonly discarded: string[] = [];
  readonly releasedReceipts: string[] = [];
  createJoinCalls: number = 0;
  acceptCalls: number = 0;
  verifyCalls: number = 0;
  failCreate?: AppError = undefined;
  failAccept?: AppError = undefined;
  failVerify?: AppError = undefined;
  failRevoke?: AppError = undefined;
  failRelease: boolean = false;
  receiptValid: boolean = true;
  receiptMemberId: string = 'member-1';
  receiptAcceptedAt: string = FIXED_UTC;
  receiptInviteId?: string = undefined;
  acceptedFamilyId: string = 'family-1';
  acceptedFamilyName: string = 'Test Family';
  acceptedMemberId: string = 'member-1';
  acceptedRole: MemberRole = MemberRole.MEMBER;
  acceptedAllowedRoomIds: ReadonlyArray<string> = [];
  acceptedGatewayIds: ReadonlyArray<string> = [];
  acceptedReceipt: string = 'receipt-1';
  private counter: number = 0;
  private readonly clock: ClockPort;

  constructor(clock: ClockPort) {
    this.clock = clock;
  }

  async createJoinRequest(displayName?: string): Promise<JoinRequestHandle> {
    this.createJoinCalls++;
    const id = 'member-' + String(this.createJoinCalls);
    return new JoinRequestHandle(id, 'YCR1.fake.' + id);
  }

  async createInvitation(input: InviteCreateRequest): Promise<InviteCreation> {
    this.createRequests.push(input);
    if (this.failCreate !== undefined) {
      throw this.failCreate;
    }
    this.counter++;
    const inviteId = 'invite-' + String(this.counter);
    const memberId = input.mode === InviteMode.KEY_WRAP ? 'member-' + String(this.counter) :
      undefined;
    const record = new InvitationRecord(inviteId, input.familyId,
      input.familyName === undefined ? 'Test Family' : input.familyName, 'admin-1',
      input.targetRole, input.allowedRoomIds, input.mode, InvitationStatus.PENDING,
      DateTimeUtil.formatUtcCompact(this.clock.nowMs() + input.ttlMs), input.maxUses, 0,
      'YCI1.fake.' + inviteId, StorageConstants.inviteSeedAlias(inviteId), undefined,
      undefined, memberId);
    return new InviteCreation('YCI1.fake.' + inviteId, record,
      input.mode === InviteMode.CODE_KEK ? 'ABC123' : undefined);
  }

  async acceptInvitation(containerText: string,
    options: AcceptInviteOptions): Promise<AcceptedInvitation> {
    this.acceptCalls++;
    if (this.failAccept !== undefined) {
      throw this.failAccept;
    }
    if (options.code === undefined && containerText.indexOf('CODE') >= 0) {
      throw AppErrors.of('INVITE_CODE_INVALID', []);
    }
    return new AcceptedInvitation(this.acceptedFamilyId, this.acceptedFamilyName,
      this.acceptedMemberId, this.acceptedRole, this.acceptedAllowedRoomIds,
      this.acceptedGatewayIds, this.acceptedReceipt);
  }

  async verifyReceipt(receiptText: string, inviteId: string): Promise<ReceiptVerification> {
    this.verifyCalls++;
    if (this.failVerify !== undefined) {
      throw this.failVerify;
    }
    const verifiedInviteId = this.receiptInviteId === undefined ? inviteId : this.receiptInviteId;
    return new ReceiptVerification(this.receiptValid, verifiedInviteId, this.receiptMemberId,
      this.receiptAcceptedAt);
  }

  async releaseReceipt(receiptText: string, inviteId: string): Promise<void> {
    if (this.failRelease) {
      throw AppErrors.of('ASSET_IO_FAILED', []);
    }
    this.releasedReceipts.push(inviteId + ':' + receiptText);
  }

  async revokeInvitation(inviteId: string): Promise<void> {
    if (this.failRevoke !== undefined) {
      throw this.failRevoke;
    }
    this.revoked.push(inviteId);
  }

  async rotateGatewaySecret(gatewayId: string): Promise<RotationPlan> {
    return new RotationPlan(gatewayId, ['invite.rotation.step.reprovision']);
  }

  async discardJoinRequest(memberId: string): Promise<void> {
    this.discarded.push(memberId);
  }
}

export class FakeFamilyAuth implements FamilyAuthPort {
  readonly profiles: FamilyProfileRef[] = [];
  readonly invalidated: string[] = [];
  readonly removedFamilyProfiles: string[] = [];
  readonly removedMemberProfiles: string[] = [];
  lockAllCalls: number = 0;
  failRemoveFamily: boolean = false;
  failRemoveMember: boolean = false;

  async lockAll(): Promise<void> {
    this.lockAllCalls++;
  }

  invalidateSessionsForMember(memberId: string): void {
    this.invalidated.push(memberId);
  }

  async removeProfilesForFamily(familyId: string): Promise<void> {
    if (this.failRemoveFamily) {
      throw AppErrors.of('ASSET_IO_FAILED', []);
    }
    this.removedFamilyProfiles.push(familyId);
  }

  async removeProfilesForMember(familyId: string, memberId: string): Promise<void> {
    if (this.failRemoveMember) {
      throw AppErrors.of('ASSET_IO_FAILED', []);
    }
    this.removedMemberProfiles.push(familyId + ':' + memberId);
  }

  async listProfiles(familyId: string): Promise<ReadonlyArray<FamilyProfileRef>> {
    const result: FamilyProfileRef[] = [];
    for (let index = 0; index < this.profiles.length; index++) {
      if (this.profiles[index].familyId === familyId) {
        result.push(this.profiles[index]);
      }
    }
    return result;
  }
}

class ScheduledDelay {
  readonly dueMs: number;
  readonly resolve: () => void;

  constructor(dueMs: number, resolve: () => void) {
    this.dueMs = dueMs;
    this.resolve = resolve;
  }
}

/** Deterministic timer: advance(ms) resolves all delays whose deadline passed. */
export class ManualSceneTimer implements SceneTimerPort {
  nowMs: number = 0;
  private scheduled: ScheduledDelay[] = [];

  delay(ms: number): Promise<void> {
    if (ms <= 0) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void): void => {
      this.scheduled.push(new ScheduledDelay(this.nowMs + ms, resolve));
    });
  }

  advance(ms: number): void {
    this.nowMs += ms;
    const due: ScheduledDelay[] = [];
    const remaining: ScheduledDelay[] = [];
    for (let index = 0; index < this.scheduled.length; index++) {
      if (this.scheduled[index].dueMs <= this.nowMs) {
        due.push(this.scheduled[index]);
      } else {
        remaining.push(this.scheduled[index]);
      }
    }
    this.scheduled = remaining;
    for (let index = 0; index < due.length; index++) {
      due[index].resolve();
    }
  }
}
