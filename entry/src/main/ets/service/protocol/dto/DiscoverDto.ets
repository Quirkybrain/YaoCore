/*
 * YaoCore C-03 discover wire DTOs.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §6.1.1
 *
 * Wire field names only. Inbound aliases are read at the JsonNode layer by
 * DiscoverMapper and never appear in these DTOs.
 */
export interface DiscoverResponseDto {
  protocolVersion: string;
  gatewayId: string;
  gatewayName: string;
  serviceId: string;
  generatedAt: string;
  security: SecurityBlockDto;
  devices: DeviceDto[];
}

export interface SecurityBlockDto {
  alg: string;
  keyId: string;
  timeWindowSeconds: number;
  nonceTtlSeconds: number;
}

export interface DeviceDto {
  deviceId: string;
  deviceName: string;
  roomName: string;
  deviceType: string;
  brand?: string;
  online: boolean;
  power?: boolean;
  open?: boolean;
  brightness?: number;
  color?: string;
  temperature?: number;
  humidity?: number;
  presence?: boolean;
  targetTemp?: number;
  mode?: string;
  lastRequestId?: string;
  lastSeq?: number;
  stateSource?: string;
  triggerDeviceId?: string;
  automationId?: string;
  updatedAt: string;
}
