/*
 * YaoCore C-01 error namespace.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §3.2.1/§3.2.3 (App namespace) and §3.2.4 (gateway namespace)
 *
 * AppError is the only error type thrown by product code. Gateway result codes
 * are classified separately by GatewayResultClassifier (common/types/GatewayResult.ets).
 */
import { NameValue } from './NameValue';

export enum ErrorCategory {
  PROTOCOL = 'PROTOCOL',
  SECURITY = 'SECURITY',
  TRANSPORT = 'TRANSPORT',
  GATEWAY = 'GATEWAY',
  STORAGE = 'STORAGE',
  AUTH = 'AUTH',
  INVITE = 'INVITE',
  PROVISIONING = 'PROVISIONING',
  CONFIG = 'CONFIG',
  INTERNAL = 'INTERNAL'
}

/** Stable catalog entry for one App error code. */
export class ErrorDefinition {
  readonly category: ErrorCategory;
  readonly retryable: boolean;
  readonly i18nKey: string;

  constructor(category: ErrorCategory, retryable: boolean, i18nKey: string) {
    this.category = category;
    this.retryable = retryable;
    this.i18nKey = i18nKey;
  }
}

/**
 * Central mapping from stable App error code to category/retryability/i18n key.
 * DES-A §3.2.3 is the authoritative table. Keys for codes not yet consumed by
 * a later component are still resolved here so callers never invent a key.
 */
export class ErrorCatalog {
  static resolve(code: string): ErrorDefinition {
    return new ErrorDefinition(
      ErrorCatalog.categoryOf(code),
      ErrorCatalog.isRetryable(code),
      ErrorCatalog.i18nKeyOf(code)
    );
  }

  private static i18nKeyOf(code: string): string {
    if (code === 'PROTOCOL_INVALID_TIMESTAMP') {
      return 'errors.app.protocol_invalid_timestamp';
    }
    if (code === 'PROTOCOL_INVALID_IDENTIFIER') {
      return 'errors.app.protocol_invalid_identifier';
    }
    if (code === 'PROTOCOL_UNSUPPORTED_VERSION') {
      return 'errors.app.protocol_unsupported_version';
    }
    if (code.startsWith('PROTOCOL_')) {
      return 'errors.app.protocol_invalid_json';
    }
    if (code === 'CRYPTO_UNAVAILABLE') {
      return 'errors.app.crypto_unavailable';
    }
    if (code === 'CRYPTO_INVALID_KEY') {
      return 'errors.app.crypto_invalid_key';
    }
    if (code === 'CRYPTO_TAG_MISMATCH') {
      return 'errors.app.crypto_tag_mismatch';
    }
    if (code === 'SIGNATURE_INVALID') {
      return 'errors.app.signature_invalid';
    }
    if (code === 'NONCE_REUSED') {
      return 'errors.app.nonce_reused';
    }
    if (code === 'TIMESTAMP_OUT_OF_WINDOW') {
      return 'errors.app.timestamp_out_of_window';
    }
    if (code === 'RESPONSE_AUTH_FAILED') {
      return 'errors.app.control_response_auth_failed';
    }
    if (code === 'RESPONSE_CORRELATION_MISMATCH') {
      return 'errors.app.ack_correlation_mismatch';
    }
    if (code.startsWith('HTTP_')) {
      return 'errors.app.http_error';
    }
    if (code === 'STORAGE_RDB_ERROR' || code === 'STORAGE_PREFERENCES_ERROR') {
      return 'errors.app.storage_error';
    }
    if (code === 'INVITE_AEAD_FAILED' || code === 'INVITE_JOIN_REQUEST_INVALID' ||
      code === 'INVITE_VERSION_UNSUPPORTED') {
      return 'errors.app.invite_invalid';
    }
    if (code === 'PROVISIONING_CREDENTIAL_MISSING' || code === 'PROVISIONING_SECRET_DRAFT_EXPIRED') {
      return 'provisioning.error.credential_missing';
    }
    if (code === 'PROVISIONING_WIFI_AUTH_ERROR') {
      return 'provisioning.error.auth_error';
    }
    if (code === 'PROVISIONING_WIFI_NETWORK_NOT_FOUND') {
      return 'provisioning.error.network_not_found';
    }
    if (code.startsWith('PROVISIONING_')) {
      return 'provisioning.error.' + code.substring('PROVISIONING_'.length).toLowerCase();
    }
    if (code === 'CLOUD_COMPLETION_TIMEOUT') {
      return 'cloud.command.accepted_not_confirmed';
    }
    if (code === 'CLOUD_COMPLETION_UNSUPPORTED' || code === 'CLOUD_INVENTORY_UNSUPPORTED') {
      return 'cloud.completion.unsupported';
    }
    if (code.startsWith('CLOUD_')) {
      return 'errors.cloud.' + code.substring('CLOUD_'.length).toLowerCase();
    }
    if (code === 'INTERNAL_ERROR') {
      return 'errors.app.internal_error';
    }
    if (code === 'CONFIGURATION_ERROR') {
      return 'errors.app.configuration_error';
    }
    if (code.startsWith('CRYPTO_')) {
      return 'errors.app.crypto_operation_failed';
    }
    if (code.startsWith('TLS_')) {
      return 'errors.app.' + code.toLowerCase();
    }
    if (code.startsWith('ROOM_') || code.startsWith('DEVICE_') || code.startsWith('SCENE_') ||
      code.startsWith('I18N_')) {
      return 'errors.app.' + code.toLowerCase();
    }
    if (code.startsWith('AUTH_') || code.startsWith('INVITE_') || code.startsWith('STORAGE_') ||
      code.startsWith('ASSET_') || code.startsWith('SECRET_') || code.startsWith('GATEWAY_') ||
      code.startsWith('ACK_') || code.startsWith('CONTROL_') || code.startsWith('MANUAL_') ||
      code.startsWith('DISCOVERY_') || code.startsWith('LOCAL_') || code.startsWith('DEV_')) {
      return 'errors.app.' + code.toLowerCase();
    }
    return 'errors.app.internal_error';
  }

  private static categoryOf(code: string): ErrorCategory {
    if (code.startsWith('PROTOCOL_')) {
      return ErrorCategory.PROTOCOL;
    }
    if (code.startsWith('CRYPTO_') || code === 'SIGNATURE_INVALID' || code === 'NONCE_REUSED' ||
      code === 'TIMESTAMP_OUT_OF_WINDOW' || code.startsWith('RESPONSE_') || code.startsWith('TLS_')) {
      return ErrorCategory.SECURITY;
    }
    if (code === 'LOCAL_REQUEST_FAILED' || code.startsWith('HTTP_') || code === 'GATEWAY_UNREACHABLE' ||
      code === 'GATEWAY_TIMEOUT' || code === 'DEV_SIMULATOR_REJECTED') {
      return ErrorCategory.TRANSPORT;
    }
    if (code.startsWith('CONTROL_') || code.startsWith('ACK_') || code.startsWith('GATEWAY_') ||
      code.startsWith('MANUAL_') || code.startsWith('DISCOVERY_')) {
      return ErrorCategory.GATEWAY;
    }
    if (code.startsWith('STORAGE_') || code.startsWith('ASSET_') || code.startsWith('SECRET_')) {
      return ErrorCategory.STORAGE;
    }
    if (code.startsWith('AUTH_')) {
      return ErrorCategory.AUTH;
    }
    if (code.startsWith('INVITE_')) {
      return ErrorCategory.INVITE;
    }
    if (code.startsWith('PROVISIONING_')) {
      return ErrorCategory.PROVISIONING;
    }
    if (code === 'CLOUD_TOKEN_EXPIRED' || code === 'CLOUD_TOKEN_INVALID') {
      return ErrorCategory.AUTH;
    }
    if (code === 'CLOUD_RATE_LIMITED' || code === 'CLOUD_REQUEST_FAILED' ||
      code === 'CLOUD_SERVICE_UNAVAILABLE' || code === 'CLOUD_SEQUENCE_UNAVAILABLE') {
      return ErrorCategory.TRANSPORT;
    }
    if (code === 'CLOUD_RESPONSE_INVALID' || code === 'CLOUD_SHADOW_INVALID') {
      return ErrorCategory.PROTOCOL;
    }
    if (code.startsWith('CLOUD_') || code.startsWith('ROOM_') || code.startsWith('DEVICE_') ||
      code.startsWith('SCENE_') || code.startsWith('I18N_') || code === 'CONFIGURATION_ERROR') {
      return ErrorCategory.CONFIG;
    }
    return ErrorCategory.INTERNAL;
  }

  private static isRetryable(code: string): boolean {
    if (code === 'NONCE_REUSED' || code === 'TIMESTAMP_OUT_OF_WINDOW') {
      return true;
    }
    if (code === 'LOCAL_REQUEST_FAILED' || code === 'GATEWAY_UNREACHABLE' || code === 'GATEWAY_TIMEOUT') {
      return true;
    }
    if (code.startsWith('HTTP_')) {
      const status = Number.parseInt(code.substring('HTTP_'.length), 10);
      return status === 408 || status === 425 || status === 429 || status >= 500;
    }
    if (code === 'STORAGE_RDB_ERROR' || code === 'STORAGE_PREFERENCES_ERROR' || code === 'ASSET_IO_FAILED') {
      return true;
    }
    if (code === 'AUTH_PASSWORD_INVALID' || code === 'INVITE_CODE_INVALID') {
      return true;
    }
    if (code === 'DISCOVERY_NO_CANDIDATES' || code === 'DISCOVERY_TRANSPORT_UNAVAILABLE') {
      return true;
    }
    if (code === 'CLOUD_RATE_LIMITED' || code === 'CLOUD_REQUEST_FAILED' ||
      code === 'CLOUD_SERVICE_UNAVAILABLE' || code === 'CLOUD_SHADOW_INVALID' ||
      code === 'CLOUD_COMPLETION_TIMEOUT' || code === 'CLOUD_SEQUENCE_UNAVAILABLE') {
      return true;
    }
    if (code === 'SCENE_STEP_FAILED' || code === 'SCENE_CANCELLED') {
      return true;
    }
    if (code === 'I18N_RESOURCE_LOAD_FAILED' || code === 'I18N_PLATFORM_LOCALE_FAILED') {
      return true;
    }
    if (code.startsWith('PROVISIONING_')) {
      return code === 'PROVISIONING_BLUETOOTH_OFF' || code === 'PROVISIONING_DEVICE_NOT_FOUND' ||
        code === 'PROVISIONING_CONNECT_FAILED' || code === 'PROVISIONING_GATT_BUSY' ||
        code === 'PROVISIONING_POP_INVALID' || code === 'PROVISIONING_SECURITY_HANDSHAKE_FAILED' ||
        code === 'PROVISIONING_WIFI_SCAN_FAILED' || code === 'PROVISIONING_WIFI_AUTH_ERROR' ||
        code === 'PROVISIONING_WIFI_NETWORK_NOT_FOUND' || code === 'PROVISIONING_WIFI_TIMEOUT' ||
        code === 'PROVISIONING_DONE_REJECTED' || code === 'PROVISIONING_BINDING_PROBE_FAILED' ||
        code === 'PROVISIONING_BOARD_LED_UNCONFIRMED' || code === 'PROVISIONING_CANCELLED';
    }
    return false;
  }
}

/** Thrown App error. `message` is English diagnostic text only. */
export class AppError extends Error {
  readonly code: string;
  readonly category: ErrorCategory;
  readonly retryable: boolean;
  readonly i18nKey: string;
  readonly details: ReadonlyArray<NameValue>;

  constructor(code: string, category: ErrorCategory, i18nKey: string, retryable: boolean,
    details?: ReadonlyArray<NameValue>) {
    super(code);
    this.name = 'AppError';
    this.code = code;
    this.category = category;
    this.i18nKey = i18nKey;
    this.retryable = retryable;
    this.details = details === undefined ? [] : details;
  }
}

/** Small factory surface so callers do not hand-copy ErrorCatalog fields. */
export class AppErrors {
  static of(code: string, details?: ReadonlyArray<NameValue>): AppError {
    const definition = ErrorCatalog.resolve(code);
    return new AppError(code, definition.category, definition.i18nKey, definition.retryable, details);
  }

  static protocol(code: string, field?: string): AppError {
    return AppErrors.of(code, AppErrors.fieldDetails(field));
  }

  static security(code: string, field?: string): AppError {
    return AppErrors.of(code, AppErrors.fieldDetails(field));
  }

  static gateway(code: string, gatewayId?: string, requestId?: string, seq?: number): AppError {
    const details: NameValue[] = [];
    if (gatewayId !== undefined && gatewayId.length > 0) {
      details.push(new NameValue('gatewayId', gatewayId));
    }
    if (requestId !== undefined && requestId.length > 0) {
      details.push(new NameValue('requestId', requestId));
    }
    if (seq !== undefined) {
      details.push(new NameValue('seq', String(seq)));
    }
    return AppErrors.of(code, details);
  }

  static transport(code: string, httpStatus?: number): AppError {
    const details: NameValue[] = [];
    if (httpStatus !== undefined) {
      details.push(new NameValue('httpStatus', String(httpStatus)));
    }
    return AppErrors.of(code, details);
  }

  static internal(field?: string): AppError {
    return AppErrors.of('INTERNAL_ERROR', AppErrors.fieldDetails(field));
  }

  private static fieldDetails(field?: string): ReadonlyArray<NameValue> {
    if (field === undefined || field.length === 0) {
      return [];
    }
    return [new NameValue('field', field)];
  }
}
