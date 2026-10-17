/*
 * YaoCore C-03 control ACK mapper and decision chain.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §6.1.4, §18.7, SC-13
 *
 * Precondition: C-05/C-17 have already verified the response signature and
 * correlation header. This mapper re-checks body correlation, strict schema,
 * result classification, reported_state shape and action/state consistency.
 * `success` is never consulted.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';
import { DeviceAction, DeviceConstants } from '../../common/constants/DeviceConstants';
import { GatewayResultClass, GatewayResultClassifier } from '../../common/types/GatewayResult';
import { DeviationCode, ProtocolDeviation } from '../../common/types/ProtocolDeviation';
import { JsonKind, JsonNode } from '../../common/types/JsonNode';
import { JsonAtom } from '../../common/utils/JsonAtom';
import type { CommandValue } from '../../common/utils/JsonAtom';
import { JsonParser } from '../../common/utils/JsonParser';
import { Utf8 } from '../../common/utils/Utf8';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import { DeviceStatePatch, DeviceStatePatchInit } from '../../model/DeviceState';
import { GatewayBoardState } from '../../model/ControlModels';
import { ControlOutcome, ControlOutcomeInit, StateVerification } from '../../model/ControlModels';
import type { ProtocolDeviationSink } from './ProtocolDeviation';
import { ProtocolErrors } from './ProtocolErrors';

const ACK_FIELDS: ReadonlyArray<string> = [
  'request_id', 'seq', 'result_code', 'message', 'error_code', 'server_time',
  'idempotent_replay', 'reported_state', 'success'
];

const DEVICE_STATE_FIELDS: ReadonlyArray<string> = [
  'deviceId', 'online', 'power', 'open', 'brightness', 'color', 'temperature', 'humidity',
  'presence', 'targetTemp', 'mode', 'lastRequestId', 'lastSeq', 'stateSource',
  'triggerDeviceId', 'automationId', 'updatedAt', 'success'
];

const GATEWAY_STATE_FIELDS: ReadonlyArray<string> = [
  'gatewayId', 'online', 'boardLed', 'updatedAt', 'success'
];

const COLOR_PATTERN: RegExp = /^#[0-9A-Fa-f]{6}$/;

export class AckExpectation {
  readonly requestId: string;
  readonly seq: number;
  readonly target: string;
  readonly action: DeviceAction;
  readonly requestedValue?: CommandValue;
  alreadyApplied: boolean;

  constructor(requestId: string, seq: number, target: string, action: DeviceAction,
    requestedValue: CommandValue | undefined, alreadyApplied: boolean) {
    if (!ProtocolConstants.REQUEST_ID_PATTERN.test(requestId) ||
      requestId.length > ProtocolConstants.MAX_REQUEST_ID_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'request_id');
    }
    if (!Number.isInteger(seq) || seq < 0 || seq > ProtocolConstants.MAX_SEQ) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'seq');
    }
    if (target.length === 0 || target.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      target.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(target)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'target');
    }
    this.requestId = requestId;
    this.seq = seq;
    this.target = target;
    this.action = action;
    this.requestedValue = requestedValue;
    this.alreadyApplied = alreadyApplied;
  }
}

export class ControlAckMapper {
  static map(body: Uint8Array, expected: AckExpectation,
    deviations: ProtocolDeviationSink): ControlOutcome {
    const collected: ProtocolDeviation[] = [];
    const root = JsonParser.parse(Utf8.decode(body));
    if (root.kind !== JsonKind.OBJECT) {
      throw ProtocolErrors.ackProtocolViolation('envelope');
    }
    ControlAckMapper.rejectUnknownFields(root, ACK_FIELDS);
    if (root.has('success')) {
      ControlAckMapper.record(collected, deviations,
        new ProtocolDeviation(DeviationCode.SUCCESS_FIELD_IGNORED, undefined, undefined, 'success'));
    }
    const requestId = ControlAckMapper.requiredString(root, 'request_id');
    if (!ProtocolConstants.REQUEST_ID_PATTERN.test(requestId) ||
      requestId.length > ProtocolConstants.MAX_REQUEST_ID_LENGTH) {
      throw ProtocolErrors.ackProtocolViolation('request_id');
    }
    const seq = ControlAckMapper.requiredInteger(root, 'seq', 0, ProtocolConstants.MAX_SEQ);
    const resultCode = ControlAckMapper.requiredInteger(root, 'result_code', 0, 9999);
    const message = ControlAckMapper.requiredString(root, 'message');
    if (message.length === 0 || message.length > 127) {
      throw ProtocolErrors.ackProtocolViolation('message');
    }
    const serverTime = ControlAckMapper.requiredString(root, 'server_time');
    DateTimeUtil.parseUtcCompact(serverTime);
    let errorCode: string | undefined = undefined;
    if (root.has('error_code')) {
      errorCode = ControlAckMapper.requiredString(root, 'error_code');
      if (errorCode.length === 0 || errorCode.length > 47) {
        throw ProtocolErrors.ackProtocolViolation('error_code');
      }
    }
    let idempotentReplay = false;
    if (root.has('idempotent_replay')) {
      const replayNode = root.require('idempotent_replay');
      if (replayNode.kind !== JsonKind.BOOLEAN) {
        throw ProtocolErrors.ackProtocolViolation('idempotent_replay');
      }
      idempotentReplay = replayNode.booleanValue;
    }
    if (requestId !== expected.requestId || seq !== expected.seq) {
      throw ProtocolErrors.ackCorrelationMismatch(requestId, seq);
    }
    const gatewayResult = GatewayResultClassifier.classify(resultCode, errorCode);

    if (resultCode !== 0) {
      // DES-A §6.1.4 step 1/§18.7: schema validation precedes result
      // classification. A present but malformed reported_state on an error
      // ACK is still a protocol violation.
      if (root.has('reported_state')) {
        ControlAckMapper.validateReportedState(root.require('reported_state'), collected, deviations);
      }
      const init = ControlAckMapper.baseOutcome(requestId, seq, resultCode, errorCode, serverTime,
        idempotentReplay, gatewayResult);
      init.ackAccepted = false;
      init.stateVerification = StateVerification.UNVERIFIED;
      init.shouldApplyState = false;
      return ControlOutcome.create(init);
    }

    if (errorCode !== undefined) {
      ControlAckMapper.record(collected, deviations,
        new ProtocolDeviation(DeviationCode.ERROR_CODE_ON_SUCCESS, undefined, undefined, 'error_code'));
    }
    if (!root.has('reported_state')) {
      throw ProtocolErrors.ackProtocolViolation('reported_state');
    }
    const reportedNode = root.require('reported_state');
    if (reportedNode.kind !== JsonKind.OBJECT) {
      throw ProtocolErrors.ackProtocolViolation('reported_state');
    }
    const hasDeviceId = reportedNode.has('deviceId');
    const hasGatewayId = reportedNode.has('gatewayId');
    if (hasDeviceId === hasGatewayId) {
      throw ProtocolErrors.ackProtocolViolation('reported_state');
    }
    let deviceState: DeviceStatePatch | undefined = undefined;
    let gatewayState: GatewayBoardState | undefined = undefined;
    if (hasDeviceId) {
      deviceState = ControlAckMapper.mapDeviceState(reportedNode, collected, deviations);
      if (deviceState.deviceId !== expected.target) {
        throw ProtocolErrors.ackStateMismatch('deviceId');
      }
    } else {
      gatewayState = ControlAckMapper.mapGatewayState(reportedNode, collected, deviations);
      if (gatewayState.gatewayId !== expected.target) {
        throw ProtocolErrors.ackStateMismatch('gatewayId');
      }
    }
    const stateVerification = ControlAckMapper.compareAction(expected, deviceState, gatewayState);
    const init = ControlAckMapper.baseOutcome(requestId, seq, resultCode, errorCode, serverTime,
      idempotentReplay, gatewayResult);
    init.ackAccepted = true;
    init.reportedState = deviceState;
    init.gatewayBoardState = gatewayState;
    init.stateVerification = stateVerification;
    // DES-A §5.1.4: shouldApplyState only applies a device-side patch.
    init.shouldApplyState = init.ackAccepted && deviceState !== undefined &&
      !(idempotentReplay && expected.alreadyApplied);
    return ControlOutcome.create(init);
  }

  /**
   * R-04: strict schema validation for a reported_state that is present on a
   * non-zero result ACK. The value is diagnostic only and is not exposed on
   * ControlOutcome for the error path.
   */
  private static validateReportedState(node: JsonNode, collected: ProtocolDeviation[],
    deviations: ProtocolDeviationSink): void {
    if (node.kind !== JsonKind.OBJECT) {
      throw ProtocolErrors.ackProtocolViolation('reported_state');
    }
    const hasDeviceId = node.has('deviceId');
    const hasGatewayId = node.has('gatewayId');
    if (hasDeviceId === hasGatewayId) {
      throw ProtocolErrors.ackProtocolViolation('reported_state');
    }
    if (hasDeviceId) {
      ControlAckMapper.mapDeviceState(node, collected, deviations);
    } else {
      ControlAckMapper.mapGatewayState(node, collected, deviations);
    }
  }

  private static baseOutcome(requestId: string, seq: number, resultCode: number,
    errorCode: string | undefined, serverTime: string, idempotentReplay: boolean,
    gatewayResult: GatewayResultClass): ControlOutcomeInit {
    const init = new ControlOutcomeInit();
    init.requestId = requestId;
    init.seq = seq;
    init.resultCode = resultCode;
    init.errorCode = errorCode;
    init.serverTime = serverTime;
    init.idempotentReplay = idempotentReplay;
    init.gatewayResult = gatewayResult;
    return init;
  }

  private static mapDeviceState(node: JsonNode, collected: ProtocolDeviation[],
    deviations: ProtocolDeviationSink): DeviceStatePatch {
    ControlAckMapper.rejectUnknownFields(node, DEVICE_STATE_FIELDS);
    if (node.has('success')) {
      ControlAckMapper.record(collected, deviations,
        new ProtocolDeviation(DeviationCode.SUCCESS_FIELD_IGNORED, undefined,
          ControlAckMapper.optionalString(node, 'deviceId'), 'success'));
    }
    const deviceId = ControlAckMapper.requiredString(node, 'deviceId');
    if (deviceId.length === 0 || deviceId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      deviceId.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(deviceId)) {
      throw ProtocolErrors.ackProtocolViolation('deviceId');
    }
    const online = ControlAckMapper.requiredBoolean(node, 'online');
    const updatedAt = ControlAckMapper.requiredString(node, 'updatedAt');
    DateTimeUtil.parseUtcCompact(updatedAt);
    const init = new DeviceStatePatchInit();
    init.deviceId = deviceId;
    init.isOnline = online;
    init.updatedAt = updatedAt;
    if (node.has('power')) {
      init.powerStatus = ControlAckMapper.requiredBoolean(node, 'power');
    }
    if (node.has('open')) {
      init.openStatus = ControlAckMapper.requiredBoolean(node, 'open');
    }
    if (node.has('brightness')) {
      init.brightness = ControlAckMapper.requiredNumber(node, 'brightness', 0, 100);
    }
    if (node.has('temperature')) {
      init.temperature = ControlAckMapper.requiredNumber(node, 'temperature', -40, 125);
    }
    if (node.has('humidity')) {
      init.humidity = ControlAckMapper.requiredNumber(node, 'humidity', 0, 100);
    }
    if (node.has('presence')) {
      init.presence = ControlAckMapper.requiredBoolean(node, 'presence');
    }
    if (node.has('targetTemp')) {
      init.targetTemperature = ControlAckMapper.requiredNumber(node, 'targetTemp', 16, 30);
    }
    if (node.has('color')) {
      const rawColor = ControlAckMapper.requiredString(node, 'color');
      if (!COLOR_PATTERN.test(rawColor)) {
        throw ProtocolErrors.ackProtocolViolation('color');
      }
      init.color = rawColor.toUpperCase();
      if (rawColor !== init.color) {
        ControlAckMapper.record(collected, deviations,
          new ProtocolDeviation(DeviationCode.LOWERCASE_COLOR_NORMALIZED, undefined, deviceId, 'color'));
      }
    }
    if (node.has('mode')) {
      const mode = ControlAckMapper.requiredString(node, 'mode');
      if (mode.length > ProtocolConstants.MAX_MODE_LENGTH_INBOUND) {
        throw ProtocolErrors.ackProtocolViolation('mode');
      }
      init.mode = mode;
      init.modeStandard = DeviceConstants.isAcMode(mode);
      if (!init.modeStandard) {
        ControlAckMapper.record(collected, deviations,
          new ProtocolDeviation(DeviationCode.NON_STANDARD_AC_MODE, undefined, deviceId, 'mode'));
      }
    }
    if (node.has('stateSource')) {
      const stateSource = ControlAckMapper.requiredString(node, 'stateSource');
      if (stateSource.length === 0 || stateSource.length > ProtocolConstants.MAX_ROOM_NAME_LENGTH) {
        throw ProtocolErrors.ackProtocolViolation('stateSource');
      }
      init.stateSource = stateSource;
      init.stateSourceKnown = DeviceConstants.isStateSource(stateSource);
      if (!init.stateSourceKnown) {
        ControlAckMapper.record(collected, deviations,
          new ProtocolDeviation(DeviationCode.UNKNOWN_STATE_SOURCE, undefined, deviceId, 'stateSource'));
      }
    }
    if (node.has('lastRequestId')) {
      init.lastRequestId = ControlAckMapper.requiredString(node, 'lastRequestId');
      if (!ProtocolConstants.REQUEST_ID_PATTERN.test(init.lastRequestId) ||
        init.lastRequestId.length > ProtocolConstants.MAX_REQUEST_ID_LENGTH) {
        throw ProtocolErrors.ackProtocolViolation('lastRequestId');
      }
    }
    if (node.has('lastSeq')) {
      init.lastSeq = ControlAckMapper.requiredInteger(node, 'lastSeq', 0, ProtocolConstants.MAX_SEQ);
    }
    if (node.has('triggerDeviceId')) {
      init.triggerDeviceId = ControlAckMapper.requiredString(node, 'triggerDeviceId');
      if (init.triggerDeviceId.length === 0 ||
        init.triggerDeviceId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
        init.triggerDeviceId.indexOf(':') >= 0 ||
        !ProtocolConstants.DEVICE_ID_PATTERN.test(init.triggerDeviceId)) {
        throw ProtocolErrors.ackProtocolViolation('triggerDeviceId');
      }
    }
    if (node.has('automationId')) {
      init.automationId = ControlAckMapper.requiredString(node, 'automationId');
      if (init.automationId.length === 0 ||
        init.automationId.length > ProtocolConstants.MAX_AUTOMATION_ID_LENGTH) {
        throw ProtocolErrors.ackProtocolViolation('automationId');
      }
    }
    return DeviceStatePatch.create(init);
  }

  private static mapGatewayState(node: JsonNode, collected: ProtocolDeviation[],
    deviations: ProtocolDeviationSink): GatewayBoardState {
    ControlAckMapper.rejectUnknownFields(node, GATEWAY_STATE_FIELDS);
    if (node.has('success')) {
      ControlAckMapper.record(collected, deviations,
        new ProtocolDeviation(DeviationCode.SUCCESS_FIELD_IGNORED, undefined,
          ControlAckMapper.optionalString(node, 'gatewayId'), 'success'));
    }
    const gatewayId = ControlAckMapper.requiredString(node, 'gatewayId');
    if (gatewayId.length === 0 || gatewayId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      gatewayId.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(gatewayId)) {
      throw ProtocolErrors.ackProtocolViolation('gatewayId');
    }
    const online = ControlAckMapper.requiredBoolean(node, 'online');
    const boardLed = ControlAckMapper.requiredBoolean(node, 'boardLed');
    const updatedAt = ControlAckMapper.requiredString(node, 'updatedAt');
    return new GatewayBoardState(gatewayId, online, boardLed, updatedAt);
  }

  private static compareAction(expected: AckExpectation, deviceState: DeviceStatePatch | undefined,
    gatewayState: GatewayBoardState | undefined): StateVerification {
    const stateField = DeviceConstants.actionToStateField(expected.action);
    if (stateField === undefined) {
      return StateVerification.UNVERIFIED;
    }
    if (stateField === 'boardLed') {
      if (gatewayState === undefined) {
        return StateVerification.UNVERIFIED;
      }
      const expectedLed = expected.action === DeviceAction.BOARD_LED_ON;
      return gatewayState.boardLed === expectedLed ? StateVerification.MATCH : StateVerification.MISMATCH;
    }
    if (deviceState === undefined) {
      return StateVerification.UNVERIFIED;
    }
    if (expected.action === DeviceAction.OPEN || expected.action === DeviceAction.CLOSE) {
      if (deviceState.openStatus === undefined) {
        return StateVerification.UNVERIFIED;
      }
      const expectedOpen = expected.action === DeviceAction.OPEN;
      return deviceState.openStatus === expectedOpen ? StateVerification.MATCH :
        StateVerification.MISMATCH;
    }
    if (expected.action === DeviceAction.TURN_ON || expected.action === DeviceAction.TURN_OFF) {
      if (deviceState.powerStatus === undefined) {
        return StateVerification.UNVERIFIED;
      }
      const expectedPower = expected.action === DeviceAction.TURN_ON;
      return deviceState.powerStatus === expectedPower ? StateVerification.MATCH :
        StateVerification.MISMATCH;
    }
    if (expected.requestedValue === undefined) {
      return StateVerification.UNVERIFIED;
    }
    if (expected.action === DeviceAction.SET_BRIGHTNESS) {
      if (deviceState.brightness === undefined) {
        return StateVerification.UNVERIFIED;
      }
      return ControlAckMapper.numericMatch(expected.requestedValue, deviceState.brightness);
    }
    if (expected.action === DeviceAction.SET_TARGET_TEMPERATURE) {
      if (deviceState.targetTemperature === undefined) {
        return StateVerification.UNVERIFIED;
      }
      return ControlAckMapper.numericMatch(expected.requestedValue, deviceState.targetTemperature);
    }
    if (expected.action === DeviceAction.SET_MODE) {
      // DES-A §5.1.4/§6.1.4 step 8 compares the reported value with the
      // requested raw value. Non-standard vocabulary is C-11/C-16/CB §6.3
      // enforcement and DES-B §8.1.6 cloud policy, not this LAN mapper.
      if (deviceState.mode === undefined || typeof expected.requestedValue !== 'string') {
        return StateVerification.UNVERIFIED;
      }
      return expected.requestedValue === deviceState.mode ? StateVerification.MATCH :
        StateVerification.MISMATCH;
    }
    if (expected.action === DeviceAction.SET_COLOR) {
      if (deviceState.color === undefined || typeof expected.requestedValue !== 'string') {
        return StateVerification.UNVERIFIED;
      }
      const expectedColor = expected.requestedValue.toUpperCase();
      return expectedColor === deviceState.color ? StateVerification.MATCH : StateVerification.MISMATCH;
    }
    return StateVerification.UNVERIFIED;
  }

  private static numericMatch(expected: CommandValue, actual: number): StateVerification {
    if (typeof expected !== 'number' || !Number.isFinite(expected)) {
      return StateVerification.UNVERIFIED;
    }
    return expected === actual ? StateVerification.MATCH : StateVerification.MISMATCH;
  }

  private static requiredString(node: JsonNode, field: string): string {
    const value = node.require(field);
    if (value.kind !== JsonKind.STRING) {
      throw ProtocolErrors.ackProtocolViolation(field);
    }
    return value.stringValue;
  }

  private static optionalString(node: JsonNode, field: string): string | undefined {
    if (!node.has(field)) {
      return undefined;
    }
    const value = node.require(field);
    if (value.kind !== JsonKind.STRING) {
      return undefined;
    }
    return value.stringValue;
  }

  private static requiredBoolean(node: JsonNode, field: string): boolean {
    const value = node.require(field);
    if (value.kind !== JsonKind.BOOLEAN) {
      throw ProtocolErrors.ackProtocolViolation(field);
    }
    return value.booleanValue;
  }

  private static requiredNumber(node: JsonNode, field: string, min: number, max: number): number {
    const value = node.require(field);
    if (value.kind !== JsonKind.NUMBER || !Number.isFinite(value.numberValue) ||
      value.numberValue < min || value.numberValue > max) {
      throw ProtocolErrors.ackProtocolViolation(field);
    }
    return value.numberValue;
  }

  private static requiredInteger(node: JsonNode, field: string, min: number, max: number): number {
    const value = node.require(field);
    if (value.kind !== JsonKind.NUMBER || !Number.isInteger(value.numberValue) ||
      value.numberValue < min || value.numberValue > max) {
      throw ProtocolErrors.ackProtocolViolation(field);
    }
    return value.numberValue;
  }

  private static rejectUnknownFields(node: JsonNode, allowed: ReadonlyArray<string>): void {
    const keys = node.keys();
    for (let index = 0; index < keys.length; index++) {
      if (allowed.indexOf(keys[index]) < 0) {
        throw ProtocolErrors.ackProtocolViolation(keys[index]);
      }
    }
  }

  private static record(collected: ProtocolDeviation[], sink: ProtocolDeviationSink,
    deviation: ProtocolDeviation): void {
    collected.push(deviation);
    sink.record(deviation);
  }
}
