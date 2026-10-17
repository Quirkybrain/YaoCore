/*
 * YaoCore C-15 cloud value models.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §8.1.1, §8.1.2, §8.1.6, §8.1.7
 *
 * Pure value objects. `CloudConfig` itself is owned by C-02
 * (`model/FamilyModels.ets`) and is only referenced here. DES-B nominally
 * places these additions in `model/CloudModels.ets`; T-14's write scope keeps
 * them in service/cloud as a recorded location exception.
 */
import { AppErrors } from '../../common/types/AppError';
import type { AppError } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';
import type { DeviceAction } from '../../common/constants/DeviceConstants';
import type { CommandValue } from '../../common/utils/JsonAtom';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import type { CloudConfig } from '../../model/FamilyModels';
import type { DeviceStatePatch } from '../../model/DeviceState';
import { StateVerification } from '../../model/ControlModels';
import { ShadowShape } from '../../model/CloudModels';
import type { InventoryDeviceState, ShadowDeviceState } from '../../model/CloudModels';

export enum CloudTransportState {
  NOT_CONFIGURED = 'NOT_CONFIGURED',
  TOKEN_MISSING = 'TOKEN_MISSING',
  CONFIGURED = 'CONFIGURED',
  TOKEN_EXPIRED = 'TOKEN_EXPIRED',
  TOKEN_INVALID = 'TOKEN_INVALID',
  UNAVAILABLE = 'UNAVAILABLE'
}

export class CloudConfigView {
  readonly config?: CloudConfig;
  readonly state: CloudTransportState;
  readonly tokenPresent: boolean;
  readonly tokenUpdatedAt?: string;
  readonly lastError?: AppError;

  constructor(config: CloudConfig | undefined, state: CloudTransportState, tokenPresent: boolean,
    tokenUpdatedAt?: string, lastError?: AppError) {
    this.config = config;
    this.state = state;
    this.tokenPresent = tokenPresent;
    this.tokenUpdatedAt = tokenUpdatedAt;
    this.lastError = lastError;
  }
}

export class CloudConfigValidation {
  readonly valid: boolean;
  readonly errors: ReadonlyArray<AppError>;
  readonly commandEndpoint?: string;
  readonly shadowEndpoint?: string;

  constructor(valid: boolean, errors: ReadonlyArray<AppError>, commandEndpoint?: string,
    shadowEndpoint?: string) {
    this.valid = valid;
    this.errors = errors;
    this.commandEndpoint = commandEndpoint;
    this.shadowEndpoint = shadowEndpoint;
  }
}

export class CloudTokenStatus {
  readonly present: boolean;
  readonly updatedAt?: string;
  readonly lastAuthFailureAt?: string;
  readonly state: CloudTransportState;

  constructor(present: boolean, state: CloudTransportState, updatedAt?: string,
    lastAuthFailureAt?: string) {
    this.present = present;
    this.state = state;
    this.updatedAt = updatedAt;
    this.lastAuthFailureAt = lastAuthFailureAt;
  }
}

export class CloudCommandExpectation {
  readonly gatewayId: string;
  readonly targetDeviceId: string;
  readonly action: DeviceAction;
  readonly requestedValue?: CommandValue;
  readonly requestId: string;
  readonly seq: number;
  readonly notBeforeMs: number;

  constructor(gatewayId: string, targetDeviceId: string, action: DeviceAction,
    requestedValue: CommandValue | undefined, requestId: string, seq: number,
    notBeforeMs: number) {
    if (gatewayId.length === 0 || gatewayId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      gatewayId.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(gatewayId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'gatewayId');
    }
    if (targetDeviceId.length === 0 ||
      targetDeviceId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      targetDeviceId.indexOf(':') >= 0 ||
      !ProtocolConstants.DEVICE_ID_PATTERN.test(targetDeviceId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'targetDeviceId');
    }
    if (!ProtocolConstants.REQUEST_ID_PATTERN.test(requestId) ||
      requestId.length > ProtocolConstants.MAX_REQUEST_ID_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'requestId');
    }
    if (!Number.isInteger(seq) || seq < 0 || seq > ProtocolConstants.MAX_SEQ) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'seq');
    }
    if (!Number.isFinite(notBeforeMs) || notBeforeMs < 0) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'notBeforeMs');
    }
    this.gatewayId = gatewayId;
    this.targetDeviceId = targetDeviceId;
    this.action = action;
    this.requestedValue = requestedValue;
    this.requestId = requestId;
    this.seq = seq;
    this.notBeforeMs = notBeforeMs;
  }
}

export class CloudCommandReceipt {
  readonly gatewayId: string;
  readonly requestId: string;
  readonly seq: number;
  readonly httpStatus: number;
  readonly acceptedAtMs: number;
  readonly commandId?: string;
  readonly responseBodySha256?: string;

  constructor(gatewayId: string, requestId: string, seq: number, httpStatus: number,
    acceptedAtMs: number, commandId?: string, responseBodySha256?: string) {
    if (gatewayId.length === 0) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'gatewayId');
    }
    if (!ProtocolConstants.REQUEST_ID_PATTERN.test(requestId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'requestId');
    }
    if (!Number.isInteger(seq) || seq < 0 || seq > ProtocolConstants.MAX_SEQ) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'seq');
    }
    // 0 = synthesized receipt for direct awaitCompletion (no send receipt).
    if (!Number.isInteger(httpStatus) || httpStatus < 0 || httpStatus > 599) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'httpStatus');
    }
    if (!Number.isFinite(acceptedAtMs) || acceptedAtMs < 0) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'acceptedAtMs');
    }
    if (commandId !== undefined && commandId.length === 0) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'commandId');
    }
    this.gatewayId = gatewayId;
    this.requestId = requestId;
    this.seq = seq;
    this.httpStatus = httpStatus;
    this.acceptedAtMs = acceptedAtMs;
    this.commandId = commandId;
    this.responseBodySha256 = responseBodySha256;
  }
}

export class CloudCommandResponseDto {
  readonly commandId?: string;
  readonly errorCode?: string;
  readonly errorMessage?: string;
  readonly rawShape: string;

  constructor(rawShape: string, commandId?: string, errorCode?: string, errorMessage?: string) {
    this.rawShape = rawShape;
    this.commandId = commandId;
    this.errorCode = errorCode;
    this.errorMessage = errorMessage;
  }
}

export class ShadowSnapshot {
  readonly gatewayDeviceId: string;
  readonly eventTime: string;
  readonly eventEpochMs: number;
  readonly properties: ReadonlyArray<NameValue>;
  readonly fixedDevices: ReadonlyArray<ShadowDeviceState>;
  readonly deviceInventory: ReadonlyArray<InventoryDeviceState>;
  readonly receivedAtMs: number;
  readonly rawSha256: string;
  readonly shape: ShadowShape;
  /**
   * True when DeviceInventoryJson exists but cannot be trusted (PB-02). The
   * evaluator must return UNSUPPORTED for inventory targets; fixed built-in
   * properties remain usable.
   */
  readonly inventoryUnsupported: boolean;
  readonly inventoryError?: AppError;

  constructor(gatewayDeviceId: string, eventTime: string, properties: ReadonlyArray<NameValue>,
    fixedDevices: ReadonlyArray<ShadowDeviceState>,
    deviceInventory: ReadonlyArray<InventoryDeviceState>, receivedAtMs: number, rawSha256: string,
    shape: ShadowShape, inventoryUnsupported: boolean = false,
    inventoryError?: AppError) {
    if (gatewayDeviceId.length === 0 || gatewayDeviceId.length > 128) {
      throw AppErrors.of('CLOUD_SHADOW_INVALID', [new NameValue('field', 'gatewayDeviceId')]);
    }
    const eventEpochMs = DateTimeUtil.parseUtcCompact(eventTime);
    if (!Number.isFinite(receivedAtMs) || receivedAtMs < 0) {
      throw AppErrors.of('CLOUD_SHADOW_INVALID', [new NameValue('field', 'receivedAtMs')]);
    }
    if (rawSha256.length !== 64 || !ProtocolConstants.HEX_LOWER_64.test(rawSha256)) {
      throw AppErrors.of('CLOUD_SHADOW_INVALID', [new NameValue('field', 'rawSha256')]);
    }
    if (shape === ShadowShape.UNKNOWN) {
      throw AppErrors.of('CLOUD_SHADOW_INVALID', [new NameValue('field', 'shape')]);
    }
    this.gatewayDeviceId = gatewayDeviceId;
    this.eventTime = eventTime;
    this.eventEpochMs = eventEpochMs;
    this.properties = properties;
    this.fixedDevices = fixedDevices;
    this.deviceInventory = deviceInventory;
    this.receivedAtMs = receivedAtMs;
    this.rawSha256 = rawSha256;
    this.shape = shape;
    this.inventoryUnsupported = inventoryUnsupported;
    this.inventoryError = inventoryError;
  }
}

export enum CloudCompletion {
  PENDING = 'PENDING',
  CONFIRMED = 'CONFIRMED',
  STALE = 'STALE',
  UNSUPPORTED = 'UNSUPPORTED',
  INVALID = 'INVALID'
}

export class CloudCompletionVerdict {
  readonly completion: CloudCompletion;
  readonly stateVerification: StateVerification;
  readonly matchedRequestId?: string;
  readonly matchedSeq?: number;
  readonly eventTime?: string;
  readonly reportedState?: DeviceStatePatch;
  readonly reason: string;
  readonly error?: AppError;

  constructor(completion: CloudCompletion, stateVerification: StateVerification, reason: string,
    matchedRequestId?: string, matchedSeq?: number, eventTime?: string,
    reportedState?: DeviceStatePatch, error?: AppError) {
    this.completion = completion;
    this.stateVerification = stateVerification;
    this.reason = reason;
    this.matchedRequestId = matchedRequestId;
    this.matchedSeq = matchedSeq;
    this.eventTime = eventTime;
    this.reportedState = reportedState;
    this.error = error;
  }
}

export class CloudControlOutcome {
  readonly receipt: CloudCommandReceipt;
  readonly verdict: CloudCompletionVerdict;
  readonly executionAccepted: boolean;
  readonly elapsedMs: number;
  readonly error?: AppError;

  constructor(receipt: CloudCommandReceipt, verdict: CloudCompletionVerdict, elapsedMs: number,
    error?: AppError) {
    if (!Number.isFinite(elapsedMs) || elapsedMs < 0) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'elapsedMs');
    }
    this.receipt = receipt;
    this.verdict = verdict;
    this.executionAccepted = verdict.completion === CloudCompletion.CONFIRMED;
    this.elapsedMs = elapsedMs;
    this.error = error;
  }
}

export class CloudCompletionPolicy {
  readonly initialDelayMs: number;
  readonly intervalMs: number;
  readonly maxElapsedMs: number;
  readonly maxAttempts: number;
  readonly freshnessToleranceMs: number;
  readonly maxShadowAgeMs: number;

  constructor(initialDelayMs: number = 500, intervalMs: number = 1000,
    maxElapsedMs: number = 30000, maxAttempts: number = 30,
    freshnessToleranceMs: number = 2000, maxShadowAgeMs: number = 120000) {
    if (!Number.isFinite(initialDelayMs) || initialDelayMs < 0 ||
      !Number.isFinite(intervalMs) || intervalMs <= 0 ||
      !Number.isFinite(maxElapsedMs) || maxElapsedMs < 0 ||
      !Number.isInteger(maxAttempts) || maxAttempts < 1 ||
      !Number.isFinite(freshnessToleranceMs) || freshnessToleranceMs < 0 ||
      !Number.isFinite(maxShadowAgeMs) || maxShadowAgeMs < 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.initialDelayMs = initialDelayMs;
    this.intervalMs = intervalMs;
    this.maxElapsedMs = maxElapsedMs;
    this.maxAttempts = maxAttempts;
    this.freshnessToleranceMs = freshnessToleranceMs;
    this.maxShadowAgeMs = maxShadowAgeMs;
  }

  static defaults(): CloudCompletionPolicy {
    return new CloudCompletionPolicy();
  }
}

export class CloudStateChangedEvent {
  readonly view: CloudConfigView;
  readonly revision: number;

  constructor(view: CloudConfigView, revision: number) {
    this.view = view;
    this.revision = revision;
  }
}

export class DeviceInventoryLimits {
  readonly maxBytes: number;
  readonly maxEntries: number;
  readonly maxDeviceIdLength: number;

  constructor(maxBytes: number = 8192, maxEntries: number = 32, maxDeviceIdLength: number = 63) {
    if (!Number.isInteger(maxBytes) || maxBytes <= 0 ||
      !Number.isInteger(maxEntries) || maxEntries <= 0 ||
      !Number.isInteger(maxDeviceIdLength) || maxDeviceIdLength <= 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.maxBytes = maxBytes;
    this.maxEntries = maxEntries;
    this.maxDeviceIdLength = maxDeviceIdLength;
  }

  static defaults(): DeviceInventoryLimits {
    return new DeviceInventoryLimits();
  }
}
