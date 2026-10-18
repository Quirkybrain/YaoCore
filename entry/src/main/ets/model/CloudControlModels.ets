/*
 * YaoCore C-15 cloud command/completion DTOs.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-B §2.1 model/** split so
 * viewmodel/contracts ControlExecution does not depend on service/cloud.
 * Contract: DES-B §8.1.2, §8.1.6, §8.1.7
 *
 * Pure value objects; no platform API.
 */
import { AppErrors } from '../common/types/AppError';
import type { AppError } from '../common/types/AppError';
import { ProtocolConstants } from '../common/constants/ProtocolConstants';
import { StateVerification } from './ControlModels';
import type { DeviceStatePatch } from './DeviceState';

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
