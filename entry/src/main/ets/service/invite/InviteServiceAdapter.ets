/*
 * YaoCore C-13 InviteService adapter to the C-08 consumed port.
 * Producer: agent:implementation-engineer | Task: T-13 / wp-049-family
 * Contract: DES-B §3.1.3/§3.1.4 port shapes; DES-A §13.1 service types
 *
 * The DES-B port was written before DES-A types existed. This adapter performs
 * only value-shape conversion; all cryptography and state live in
 * InviteService. It never persists the invitation record (C-08 owns that).
 */
import {
  AcceptInviteOptions,
  AcceptedInvitation,
  InviteCreateRequest,
  InviteCreation,
  JoinRequestHandle,
  ReceiptVerification,
  RotationPlan
} from '../family/FamilyModels';
import type { InviteServicePort } from '../family/FamilyModels';
import {
  AcceptInvitationOptions,
  CreateInvitationInput,
  JoinRequestContainer
} from './InviteModels';
import { InviteCodec } from './InviteCodec';
import { InviteService } from './InviteService';

export class InviteServiceAdapter implements InviteServicePort {
  private readonly service: InviteService;

  constructor(service: InviteService) {
    this.service = service;
  }

  async createJoinRequest(displayName?: string): Promise<JoinRequestHandle> {
    const container = await this.service.createJoinRequest(displayName);
    return new JoinRequestHandle(container.joinRequest.memberId, container.text);
  }

  async createInvitation(input: InviteCreateRequest): Promise<InviteCreation> {
    let joinRequest: JoinRequestContainer | undefined = undefined;
    if (input.joinRequestText !== undefined) {
      joinRequest = new JoinRequestContainer(input.joinRequestText,
        InviteCodec.decodeJoinRequest(input.joinRequestText));
    }
    const request = new CreateInvitationInput(input.familyId, input.targetRole,
      input.allowedRoomIds, input.maxUses, input.ttlMs, input.mode, joinRequest,
      input.familyName);
    const result = await this.service.createInvitation(request);
    return new InviteCreation(result.container.text, result.record, result.code);
  }

  async acceptInvitation(containerText: string,
    options: AcceptInviteOptions): Promise<AcceptedInvitation> {
    const accepted = await this.service.acceptInvitation(containerText,
      new AcceptInvitationOptions(options.nowMs, options.code));
    return new AcceptedInvitation(accepted.familyId, accepted.familyName,
      accepted.memberId, accepted.role, accepted.allowedRoomIds,
      accepted.appliedGatewayIds, accepted.receipt);
  }

  async verifyReceipt(receiptText: string, inviteId: string): Promise<ReceiptVerification> {
    const verification = await this.service.verifyReceipt(receiptText, inviteId);
    return new ReceiptVerification(verification.valid, verification.inviteId,
      verification.memberId, verification.acceptedAt);
  }

  async revokeInvitation(inviteId: string): Promise<void> {
    await this.service.revokeInvitation(inviteId);
  }

  async rotateGatewaySecret(gatewayId: string): Promise<RotationPlan> {
    const plan = await this.service.rotateGatewaySecret(gatewayId);
    return new RotationPlan(plan.gatewayId, plan.steps);
  }

  async discardJoinRequest(memberId: string): Promise<void> {
    await this.service.discardJoinRequest(memberId);
  }
}
