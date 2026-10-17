/*
 * YaoCore C-01 protocol constants.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §4.1.1/§4.1.2
 */
export class ProtocolConstants {
  static readonly PROTOCOL_VERSION_20: string = '2.0';
  static readonly PROTOCOL_VERSION_21: string = '2.1';
  static readonly SERVICE_ID_CLOUD: string = 'SmartHomeService';
  static readonly SERVICE_ID_IDENTITY: string = 'YaoCoreGateway';
  static readonly ALG_HMAC_SHA256: string = 'HMAC-SHA256';
  static readonly KEY_ID_V1: string = 'app-key-v1';
  static readonly CMD_ID_CONTROL: number = 2001;
  static readonly CMD_ID_CLOUD: number = 3001;
  static readonly TIME_WINDOW_SECONDS: number = 120;
  static readonly NONCE_TTL_SECONDS: number = 300;
  static readonly DEFAULT_GATEWAY_PORT: number = 9200;
  static readonly DISCOVER_PATH: string = '/discover';
  static readonly CONTROL_PATH: string = '/control';
  static readonly HEALTH_PATH: string = '/health';
  static readonly CANONICAL_DISCOVER_TAG: string = 'YAOCORE-DISCOVER-V2';
  static readonly CANONICAL_RESPONSE_TAG: string = 'YAOCORE-RESPONSE-V1';
  static readonly RESPONSE_KIND_DISCOVER: string = 'discover';
  static readonly RESPONSE_KIND_CONTROL: string = 'control';
  static readonly KEY_ID_PATTERN: RegExp = /^[a-z0-9][a-z0-9._-]{0,31}$/;
  static readonly HEX_LOWER_32: RegExp = /^[0-9a-f]{32}$/;
  static readonly HEX_LOWER_64: RegExp = /^[0-9a-f]{64}$/;
  static readonly PIN_PATTERN: RegExp = /^[0-9a-f]{64}$/;
  static readonly REQUEST_ID_PATTERN: RegExp = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,126}$/;
  static readonly DEVICE_ID_PATTERN: RegExp = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$/;
  static readonly DISCOVER_REQUEST_ID_PATTERN: RegExp = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/;
  static readonly UTC_COMPACT_PATTERN: RegExp = /^[0-9]{8}T[0-9]{6}Z$/;
  static readonly ACTION_PATTERN: RegExp = /^[A-Z][A-Z0-9_]{0,46}$/;
  static readonly NONCE_PATTERN: RegExp = /^[A-Za-z0-9_-]{8,64}$/;
  static readonly MAX_SEQ: number = 2147483647;
  static readonly MAX_PIN_COUNT: number = 4;
  static readonly MAX_REQUEST_ID_LENGTH: number = 127;
  static readonly MAX_DEVICE_ID_LENGTH: number = 63;
  static readonly MAX_ACTION_LENGTH: number = 47;
  static readonly MAX_MODE_LENGTH_OUTBOUND: number = 15;
  static readonly MAX_MODE_LENGTH_INBOUND: number = 32;
  static readonly MAX_IDENTIFIER_LENGTH_INBOUND: number = 128;
  static readonly MAX_GATEWAY_NAME_LENGTH: number = 63;
  static readonly MAX_ROOM_NAME_LENGTH: number = 31;
  static readonly MAX_BRAND_LENGTH: number = 31;
  static readonly MAX_AUTOMATION_ID_LENGTH: number = 63;
}

export class ProtocolHeaders {
  static readonly CHALLENGE: string = 'X-YaoCore-Challenge';
  static readonly REQUEST_NONCE: string = 'X-YaoCore-Request-Nonce';
  static readonly REQUEST_TIMESTAMP: string = 'X-YaoCore-Request-Timestamp';
  static readonly REQUEST_ALG: string = 'X-YaoCore-Request-Alg';
  static readonly REQUEST_KEY_ID: string = 'X-YaoCore-Key-Id';
  static readonly REQUEST_SIGN: string = 'X-YaoCore-Request-Sign';
  static readonly RESPONSE_ALG: string = 'X-YaoCore-Response-Alg';
  static readonly RESPONSE_KEY_ID: string = 'X-YaoCore-Key-Id';
  static readonly RESPONSE_CORRELATION: string = 'X-YaoCore-Response-Correlation';
  static readonly RESPONSE_SIGN: string = 'X-YaoCore-Response-Sign';
  static readonly SIMULATOR: string = 'X-YaoCore-Simulator';
  static readonly CONTENT_TYPE: string = 'Content-Type';
  static readonly CONTENT_LENGTH: string = 'Content-Length';
  static readonly DEV_ONLY_VALUE: string = 'DEV-ONLY';
  static readonly DEV_SIMULATOR_ONLY: string = 'DEV_SIMULATOR_ONLY';
}
