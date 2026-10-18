/*
 * YaoCore C-07 invitation entry value.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-A §27.6.3 P2; split out of
 * repository/GatewayPorts.ets so the contract file stays port-only.
 * Contract: DES-A §10.1, §10.3
 */
import { AppErrors } from '../common/types/AppError';
import { ProtocolConstants } from '../common/constants/ProtocolConstants';
import type { SecureBytes } from '../common/types/SecureBytes';
import type { ProvisioningTlsMaterial } from './ProvisioningModels';

/**
 * Invite bundle entry. The caller owns `commandSecret` and must destroy it
 * after the repository call returns (DES-A §10.1/§10.3).
 */
export class InvitedGateway {
  readonly gatewayId: string;
  readonly familyId: string;
  readonly gatewayName: string;
  readonly commandSecret: SecureBytes;
  readonly tls?: ProvisioningTlsMaterial;

  constructor(gatewayId: string, familyId: string, gatewayName: string,
    commandSecret: SecureBytes, tls?: ProvisioningTlsMaterial) {
    if (gatewayId.length === 0 || gatewayId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      gatewayId.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(gatewayId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'gatewayId');
    }
    if (familyId.length === 0 || familyId.length > 63) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'familyId');
    }
    if (gatewayName.length === 0 ||
      gatewayName.length > ProtocolConstants.MAX_GATEWAY_NAME_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'gatewayName');
    }
    if (commandSecret.length < 16) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    // ProvisioningTlsMaterial constructor already validates pins/port/pinAlg.
    this.gatewayId = gatewayId;
    this.familyId = familyId;
    this.gatewayName = gatewayName;
    this.commandSecret = commandSecret;
    this.tls = tls;
  }
}
