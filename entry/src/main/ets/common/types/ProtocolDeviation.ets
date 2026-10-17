/*
 * YaoCore C-01 protocol deviation value object.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §4.1.10, §18.8
 *
 * Deviations are diagnostic only. `detail` must contain a field name or reason
 * code, never a device name, secret, or complete payload.
 */
export enum DeviationCode {
  ALIAS_FIELD_USED = 'ALIAS_FIELD_USED',
  ALIAS_CONFLICT = 'ALIAS_CONFLICT',
  SUCCESS_FIELD_IGNORED = 'SUCCESS_FIELD_IGNORED',
  ROOM_NAME_MISSING = 'ROOM_NAME_MISSING',
  UNKNOWN_DEVICE_TYPE = 'UNKNOWN_DEVICE_TYPE',
  UNKNOWN_STATE_SOURCE = 'UNKNOWN_STATE_SOURCE',
  NON_STANDARD_AC_MODE = 'NON_STANDARD_AC_MODE',
  LOWERCASE_COLOR_NORMALIZED = 'LOWERCASE_COLOR_NORMALIZED',
  OVERSIZE_INBOUND_IDENTIFIER = 'OVERSIZE_INBOUND_IDENTIFIER',
  ERROR_CODE_ON_SUCCESS = 'ERROR_CODE_ON_SUCCESS',
  DEVICE_SKIPPED = 'DEVICE_SKIPPED'
}

export class ProtocolDeviation {
  readonly code: DeviationCode;
  readonly gatewayId?: string;
  readonly deviceId?: string;
  readonly field?: string;
  readonly detail?: string;

  constructor(code: DeviationCode, gatewayId?: string, deviceId?: string, field?: string, detail?: string) {
    this.code = code;
    this.gatewayId = gatewayId;
    this.deviceId = deviceId;
    this.field = field;
    this.detail = detail;
  }
}
