/*
 * YaoCore C-07 GatewayRepository ports and invite entry.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Contract: DES-A §10.1, §10.5, §3.7
 *
 * Port-only declarations consumed by C-17/C-18/C-23. C-07 owns the
 * implementations; no platform import appears here.
 *
 * DES-A nominally places ports under contracts/**. T-08's write scope is
 * repository/**, so this file keeps the ports next to the implementation as a
 * recorded location exception.
 */
import { AppErrors } from '../common/types/AppError';
import { ProtocolConstants } from '../common/constants/ProtocolConstants';
import type { SecureBytes } from '../common/types/SecureBytes';
import type { GatewayAddress, GatewayRoute, TlsMaterial } from '../model/GatewayRoute';
import type { ProvisioningTlsMaterial } from '../model/ProvisioningModels';

export interface GatewayRoutePort {
  listRoutes(): Promise<ReadonlyArray<GatewayRoute>>;
  listRoutesByFamily(familyId: string): Promise<ReadonlyArray<GatewayRoute>>;
  getRoute(gatewayId: string): Promise<GatewayRoute | undefined>;
  isBound(gatewayId: string): Promise<boolean>;
}

export interface GatewayCredentialPort {
  withCommandSecret<T>(gatewayId: string, fn: (secret: Uint8Array) => Promise<T>): Promise<T>;
  tlsMaterial(gatewayId: string): Promise<TlsMaterial | undefined>;
}

export interface GatewayAddressPort {
  updateLastKnownAddress(gatewayId: string, address: GatewayAddress): Promise<void>;
}

export interface GatewaySequencePort {
  nextSequence(gatewayId: string): Promise<number>;
  peekSequence(gatewayId: string): Promise<number>;
  resetSequenceIfIdle(gatewayId: string): Promise<number>;
}

export interface SecretVerifier {
  verify(gatewayId: string, secret: Uint8Array): Promise<boolean>;
}

export interface InvitationApplicationPort {
  applyInvitedGateway(entry: InvitedGateway): Promise<void>;
}

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
