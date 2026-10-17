/*
 * YaoCore C-03 BLE enrollment identity DTOs.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §6.1.1/§6.1.5
 */
export interface IdentityV20Dto {
  protocolVersion: string;
  serviceId: string;
  gatewayId: string;
  gatewayName: string;
}

export interface IdentityV21Dto {
  protocolVersion: string;
  serviceId: string;
  gatewayId: string;
  gatewayName: string;
  security?: IdentitySecurityDto;
}

export interface IdentitySecurityDto {
  lan?: IdentityLanDto;
}

export interface IdentityLanDto {
  tls: boolean;
  port?: number;
  pins?: string[];
  pinAlg?: string;
}
