/*
 * YaoCore C-17 request policy and LAN control policy.
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §14.1.1, §14.2.3, §14.3, §18.1
 *
 * Pure logic only: no @ohos import, no timers, no platform state.
 */
import { AppErrors } from '../../common/types/AppError';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';
import { ActionValueKind, DeviceAction, DeviceConstants, DeviceType } from '../../common/constants/DeviceConstants';
import { JsonAtom } from '../../common/utils/JsonAtom';
import type { CommandValue } from '../../common/utils/JsonAtom';

const COLOR_PATTERN: RegExp = /^#[0-9A-F]{6}$/;

export class GatewayRequestPolicy {
  readonly connectTimeoutMs: number;
  readonly readTimeoutMs: number;
  readonly maxAttempts: number;
  readonly retryBaseDelayMs: number;
  readonly retryMaxDelayMs: number;
  readonly discoverTimeoutMs: number;
  readonly allowCleartext: boolean;

  constructor(connectTimeoutMs: number, readTimeoutMs: number, maxAttempts: number,
    retryBaseDelayMs: number, retryMaxDelayMs: number, discoverTimeoutMs: number,
    allowCleartext: boolean) {
    if (!Number.isInteger(connectTimeoutMs) || connectTimeoutMs <= 0 ||
      !Number.isInteger(readTimeoutMs) || readTimeoutMs <= 0 ||
      !Number.isInteger(discoverTimeoutMs) || discoverTimeoutMs <= 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (!Number.isInteger(maxAttempts) || maxAttempts < 1 || maxAttempts > 5) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (!Number.isInteger(retryBaseDelayMs) || retryBaseDelayMs < 0 ||
      !Number.isInteger(retryMaxDelayMs) || retryMaxDelayMs < retryBaseDelayMs) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.connectTimeoutMs = connectTimeoutMs;
    this.readTimeoutMs = readTimeoutMs;
    this.maxAttempts = maxAttempts;
    this.retryBaseDelayMs = retryBaseDelayMs;
    this.retryMaxDelayMs = retryMaxDelayMs;
    this.discoverTimeoutMs = discoverTimeoutMs;
    this.allowCleartext = allowCleartext;
  }

  static defaults(): GatewayRequestPolicy {
    return new GatewayRequestPolicy(3000, 5000, 3, 300, 900, 5000, true);
  }

  /** DES-A §14.3 fixed retry sequence: 300ms, then 900ms, capped. */
  retryDelayMs(attempt: number): number {
    if (!Number.isInteger(attempt) || attempt < 1) {
      return this.retryBaseDelayMs;
    }
    let delay = this.retryBaseDelayMs;
    for (let index = 1; index < attempt; index++) {
      delay = delay * 3;
      if (delay >= this.retryMaxDelayMs) {
        return this.retryMaxDelayMs;
      }
    }
    return Math.min(delay, this.retryMaxDelayMs);
  }
}

/**
 * DES-A §14.2.3 control policy. C-17 cannot see the device repository, so
 * `deviceType`/`isSupported` are optional prechecks supplied by C-10/C-11 when
 * available; without them the action/value-only rules still apply.
 *
 * T-11 F-04: C-10 DeviceCommandRunner now calls this policy with the persisted
 * device type before `port.send`, so the action x deviceType matrix is enforced
 * on direct device commands as well. C-17 direct `control()` callers that cannot
 * supply a type only get the action/value rules.
 */
export class ControlPolicy {
  static validate(deviceType: DeviceType | undefined, isSupported: boolean,
    action: DeviceAction, value?: CommandValue): void {
    if (!isSupported) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (deviceType !== undefined) {
      ControlPolicy.validateDeviceType(deviceType);
    }
    if (DeviceConstants.LOCAL_ONLY_ACTIONS.indexOf(action) >= 0) {
      // ADR-004 §2.1: rename/move are local-only and must never reach a gateway.
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (action === DeviceAction.SET_POSITION || action === DeviceAction.SET_SPEED ||
      action === DeviceAction.SET_VOLUME || action === DeviceAction.STOP) {
      // v1 LAN schema has no such fields (CB §6.2).
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (deviceType !== undefined) {
      ControlPolicy.validateMatrix(deviceType, action);
    }
    ControlPolicy.validateValue(action, value);
  }

  /**
   * App normalizes color and AC mode to uppercase before signing (DES-A
   * §14.2.3). Other values are returned unchanged. The caller uses this value
   * both in the canonical signing input and in the ACK expectation.
   */
  static normalizeValue(action: DeviceAction, value?: CommandValue): CommandValue | undefined {
    if ((action === DeviceAction.SET_COLOR || action === DeviceAction.SET_MODE) &&
      typeof value === 'string') {
      return value.toUpperCase();
    }
    return value;
  }

  /** F-11: these actions are meaningless without a value (DES-A §14.2.3). */
  private static requiresValue(action: DeviceAction): boolean {
    return action === DeviceAction.SET_BRIGHTNESS || action === DeviceAction.SET_COLOR ||
      action === DeviceAction.SET_TARGET_TEMPERATURE || action === DeviceAction.SET_MODE;
  }

  private static validateDeviceType(deviceType: DeviceType): void {
    const supported = DeviceConstants.SUPPORTED_TYPES.indexOf(deviceType) >= 0;
    const readOnly = DeviceConstants.READ_ONLY_TYPES.indexOf(deviceType) >= 0;
    if (!supported && !readOnly) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (deviceType === DeviceType.SENSOR) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
  }

  private static validateMatrix(deviceType: DeviceType, action: DeviceAction): void {
    if (deviceType === DeviceType.DOOR) {
      if (action !== DeviceAction.OPEN && action !== DeviceAction.CLOSE) {
        throw AppErrors.of('CONFIGURATION_ERROR', []);
      }
      return;
    }
    if (deviceType === DeviceType.LIGHT) {
      if (action !== DeviceAction.TURN_ON && action !== DeviceAction.TURN_OFF &&
        action !== DeviceAction.SET_BRIGHTNESS && action !== DeviceAction.SET_COLOR) {
        throw AppErrors.of('CONFIGURATION_ERROR', []);
      }
      return;
    }
    if (deviceType === DeviceType.AC) {
      if (action !== DeviceAction.TURN_ON && action !== DeviceAction.TURN_OFF &&
        action !== DeviceAction.SET_TARGET_TEMPERATURE && action !== DeviceAction.SET_MODE) {
        throw AppErrors.of('CONFIGURATION_ERROR', []);
      }
      return;
    }
    // Read-only types (switch/camera/curtain/fan/speaker) never receive control.
    throw AppErrors.of('CONFIGURATION_ERROR', []);
  }

  private static validateValue(action: DeviceAction, value?: CommandValue): void {
    if (action === DeviceAction.PING) {
      if (value !== undefined) {
        throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'value');
      }
      return;
    }
    const kind = DeviceConstants.actionToValueKind(action);
    if (value === undefined) {
      if (ControlPolicy.requiresValue(action)) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'value');
      }
      return;
    }
    if (kind === ActionValueKind.BOOLEAN) {
      if (typeof value !== 'boolean') {
        throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'value');
      }
      const expected = action === DeviceAction.TURN_ON || action === DeviceAction.OPEN ||
        action === DeviceAction.BOARD_LED_ON;
      if (value !== expected) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'value');
      }
      return;
    }
    if (kind === ActionValueKind.NUMBER) {
      if (typeof value !== 'number' || !Number.isFinite(value)) {
        throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'value');
      }
      if (action === DeviceAction.SET_BRIGHTNESS && (value < 0 || value > 100)) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'value');
      }
      if (action === DeviceAction.SET_TARGET_TEMPERATURE && (value < 16 || value > 30)) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'value');
      }
      return;
    }
    if (kind === ActionValueKind.NONE) {
      throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'value');
    }
    if (typeof value !== 'string') {
      throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'value');
    }
    if (action === DeviceAction.SET_MODE) {
      const normalized = value.toUpperCase();
      if (!DeviceConstants.isAcMode(normalized)) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'value');
      }
      return;
    }
    if (value.length === 0 || value.length > 63) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'value');
    }
    if (kind === ActionValueKind.COLOR) {
      if (!COLOR_PATTERN.test(value.toUpperCase())) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'value');
      }
    }
    // Reject lone surrogates before the string reaches the JSON encoder.
    JsonAtom.normalizeString(value);
  }
}
