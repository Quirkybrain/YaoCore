/*
 * YaoCore C-03 local control request wire DTOs.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §6.1.1/§6.1.3
 */
export interface ControlRequestDto {
  request_id: string;
  cmd_id: number;
  seq: number;
  target: string;
  payload: ControlPayloadDto;
  timestamp: string;
  nonce: string;
  alg: string;
  key_id: string;
  sign: string;
}

export interface ControlPayloadDto {
  action: string;
  value?: string | number | boolean;
}
