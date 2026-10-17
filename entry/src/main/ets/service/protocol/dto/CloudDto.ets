/*
 * YaoCore C-03 cloud command/state-report wire DTOs.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-B §8.1.2/§8.1.4, input/api/protocol/cloud-command.schema.json,
 *           input/api/protocol/state-report.schema.json
 *
 * `Value` is a JSON string containing the compact JSON atom text, matching the
 * cloud-command schema. The canonical field is that atom text itself.
 */
export interface CloudCommandDto {
  service_id: string;
  command_name: string;
  paras: CloudCommandParasDto;
}

export interface CloudCommandParasDto {
  RequestId: string;
  CmdId: number;
  Seq: number;
  TargetDevice: string;
  Action: string;
  Value?: string;
  Timestamp: string;
  Nonce: string;
  Alg: string;
  KeyId: string;
  Sign: string;
}

export interface StateReportDto {
  services: StateReportServiceDto[];
}

export interface StateReportServiceDto {
  service_id: string;
  properties: Object;
  event_time: string;
}
