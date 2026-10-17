/*
 * YaoCore C-02 control command and control outcome.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §5.1.4, §5.3
 */
import { AppErrors } from '../common/types/AppError';
import { ProtocolConstants } from '../common/constants/ProtocolConstants';
import { DeviceAction } from '../common/constants/DeviceConstants';
import type { CommandValue } from '../common/utils/JsonAtom';
import { GatewayResultClass, GatewayResultClassifier } from '../common/types/GatewayResult';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import { DeviceStatePatch } from './DeviceState';

export class DeviceControlCommand {
  readonly gatewayId: string;
  readonly target: string;
  readonly action: DeviceAction;
  readonly value?: CommandValue;
  readonly requestedAtMs: number;

  constructor(gatewayId: string, target: string, action: DeviceAction, requestedAtMs: number,
    value?: CommandValue) {
    if (gatewayId.length === 0 || gatewayId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      gatewayId.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(gatewayId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'gatewayId');
    }
    if (target.length === 0 || target.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      target.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(target)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'target');
    }
    if (!Number.isFinite(requestedAtMs) || requestedAtMs < 0) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'requestedAtMs');
    }
    if (value !== undefined) {
      if (typeof value === 'number' && !Number.isFinite(value)) {
        throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'value');
      }
      if (typeof value === 'string' && value.length > 63) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'value');
      }
    }
    this.gatewayId = gatewayId;
    this.target = target;
    this.action = action;
    this.value = value;
    this.requestedAtMs = requestedAtMs;
  }
}

export enum StateVerification {
  MATCH = 'MATCH',
  UNVERIFIED = 'UNVERIFIED',
  MISMATCH = 'MISMATCH'
}

export class GatewayBoardState {
  readonly gatewayId: string;
  readonly isOnline: boolean;
  readonly boardLed: boolean;
  readonly updatedAt: string;

  constructor(gatewayId: string, isOnline: boolean, boardLed: boolean, updatedAt: string) {
    if (gatewayId.length === 0 || gatewayId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      gatewayId.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(gatewayId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'gatewayId');
    }
    DateTimeUtil.parseUtcCompact(updatedAt);
    this.gatewayId = gatewayId;
    this.isOnline = isOnline;
    this.boardLed = boardLed;
    this.updatedAt = updatedAt;
  }
}

export class ControlOutcomeInit {
  requestId: string = '';
  seq: number = 0;
  resultCode: number = 0;
  errorCode: string | undefined = undefined;
  serverTime: string | undefined = undefined;
  idempotentReplay: boolean = false;
  ackAccepted: boolean = false;
  reportedState: DeviceStatePatch | undefined = undefined;
  gatewayBoardState: GatewayBoardState | undefined = undefined;
  stateVerification: StateVerification = StateVerification.UNVERIFIED;
  gatewayResult: GatewayResultClass = GatewayResultClassifier.classify(1001);
  shouldApplyState: boolean = false;
}

export class ControlOutcome {
  readonly requestId: string;
  readonly seq: number;
  readonly resultCode: number;
  readonly errorCode?: string;
  readonly serverTime?: string;
  readonly idempotentReplay: boolean;
  readonly ackAccepted: boolean;
  readonly reportedState?: DeviceStatePatch;
  readonly gatewayBoardState?: GatewayBoardState;
  readonly stateVerification: StateVerification;
  readonly gatewayResult: GatewayResultClass;
  readonly shouldApplyState: boolean;

  private constructor(init: ControlOutcomeInit) {
    this.requestId = init.requestId;
    this.seq = init.seq;
    this.resultCode = init.resultCode;
    this.errorCode = init.errorCode;
    this.serverTime = init.serverTime;
    this.idempotentReplay = init.idempotentReplay;
    this.ackAccepted = init.ackAccepted;
    this.reportedState = init.reportedState;
    this.gatewayBoardState = init.gatewayBoardState;
    this.stateVerification = init.stateVerification;
    this.gatewayResult = init.gatewayResult;
    this.shouldApplyState = init.shouldApplyState;
  }

  static create(init: ControlOutcomeInit): ControlOutcome {
    if (!ProtocolConstants.REQUEST_ID_PATTERN.test(init.requestId) ||
      init.requestId.length > ProtocolConstants.MAX_REQUEST_ID_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'request_id');
    }
    if (!Number.isInteger(init.seq) || init.seq < 0 || init.seq > ProtocolConstants.MAX_SEQ) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'seq');
    }
    if (!Number.isInteger(init.resultCode) || init.resultCode < 0 || init.resultCode > 9999) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'result_code');
    }
    if (init.serverTime !== undefined) {
      DateTimeUtil.parseUtcCompact(init.serverTime);
    }
    if (init.ackAccepted && (init.resultCode !== 0 ||
      (init.reportedState === undefined && init.gatewayBoardState === undefined))) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (init.shouldApplyState && !init.ackAccepted) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (init.gatewayResult.success !== (init.resultCode === 0)) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    return new ControlOutcome(init);
  }
}
