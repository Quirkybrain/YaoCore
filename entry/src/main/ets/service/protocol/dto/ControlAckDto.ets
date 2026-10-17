/*
 * YaoCore C-03 control ACK wire DTOs.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §6.1.1/§6.1.4
 *
 * `success` is intentionally absent: it is never accepted as a success signal.
 */
export interface ControlAckDto {
  request_id: string;
  seq: number;
  result_code: number;
  message: string;
  error_code?: string;
  server_time: string;
  idempotent_replay?: boolean;
  reported_state?: DeviceStateDto | GatewayStateDto;
}

export interface DeviceStateDto {
  deviceId: string;
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

export interface GatewayStateDto {
  gatewayId: string;
  online: boolean;
  boardLed: boolean;
  updatedAt: string;
}
