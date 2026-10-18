/*
 * YaoCore C-11 scene preflight validation.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §6.3.2 (preflight checklist), §6.1.4 (create/update checks)
 *
 * The same validation is used by create/update (reference sanity) and by
 * run()'s preflight. No command is sent before every action passes.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { DeviceAction, DeviceConstants, DeviceType } from '../../common/constants/DeviceConstants';
import { DeviceKey } from '../../model/DeviceKey';
import { Scene, SceneAction } from '../../model/FamilyModels';
import { DeviceRepository } from '../../repository/DeviceRepository';
import type { GatewayRoutePort } from '../../contracts/GatewayPorts';

const COLOR_PATTERN: RegExp = /^#[0-9A-F]{6}$/;

export class ScenePreflightResult {
  readonly ok: boolean;
  readonly failedIndex: number;
  readonly error?: AppError;

  constructor(ok: boolean, failedIndex: number, error?: AppError) {
    this.ok = ok;
    this.failedIndex = failedIndex;
    this.error = error;
  }
}

export class SceneValidation {
  static async preflight(scene: Scene, devices: DeviceRepository,
    routes: GatewayRoutePort): Promise<ScenePreflightResult> {
    for (let index = 0; index < scene.actions.length; index++) {
      const action = scene.actions[index];
      const shapeError = SceneValidation.actionShapeError(action);
      if (shapeError !== undefined) {
        return new ScenePreflightResult(false, index, shapeError);
      }
      const route = await routes.getRoute(action.gatewayId);
      if (route === undefined || route.familyId !== scene.familyId) {
        return new ScenePreflightResult(false, index,
          AppErrors.of('SCENE_REFERENCE_INVALID', [new NameValue('index', String(index))]));
      }
      const key = new DeviceKey(action.gatewayId, action.targetDeviceId);
      const record = await devices.getRecord(key);
      if (record === undefined || record.gatewayRemoved) {
        return new ScenePreflightResult(false, index,
          AppErrors.of('SCENE_REFERENCE_INVALID', [new NameValue('index', String(index))]));
      }
      if (!record.state.isEnabled || record.state.isUnassigned) {
        // Unassigned/disabled pool and read-only degraded devices are not
        // executable (DES-B §6.3.2).
        return new ScenePreflightResult(false, index,
          AppErrors.of('SCENE_REFERENCE_INVALID', [new NameValue('index', String(index))]));
      }
      if (!record.isSupported || !SceneValidation.actionMatchesType(
        record.state.snapshot.deviceType, action.action)) {
        return new ScenePreflightResult(false, index,
          AppErrors.of('SCENE_REFERENCE_INVALID', [new NameValue('index', String(index))]));
      }
    }
    return new ScenePreflightResult(true, -1);
  }

  /** Validates one action independent of current device state. */
  static actionShapeError(action: SceneAction): AppError | undefined {
    if (action.gatewayId.length === 0 || action.targetDeviceId.length === 0) {
      return AppErrors.of('SCENE_REFERENCE_INVALID', []);
    }
    if (action.delayMs !== undefined && (!Number.isInteger(action.delayMs) || action.delayMs < 0)) {
      return AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'delayMs');
    }
    if (action.action === DeviceAction.SET_POSITION || action.action === DeviceAction.SET_SPEED ||
      action.action === DeviceAction.SET_VOLUME || action.action === DeviceAction.SET_DEVICE_NAME ||
      action.action === DeviceAction.SET_DEVICE_ROOM || action.action === DeviceAction.BOARD_LED_ON ||
      action.action === DeviceAction.BOARD_LED_OFF || action.action === DeviceAction.PING ||
      action.action === DeviceAction.STOP) {
      return AppErrors.of('SCENE_REFERENCE_INVALID', []);
    }
    if (action.action === DeviceAction.OPEN || action.action === DeviceAction.CLOSE ||
      action.action === DeviceAction.TURN_ON || action.action === DeviceAction.TURN_OFF) {
      if (action.value !== undefined && typeof action.value !== 'boolean') {
        return AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'value');
      }
      return undefined;
    }
    if (action.action === DeviceAction.SET_BRIGHTNESS) {
      if (typeof action.value !== 'number' || !Number.isInteger(action.value) ||
        action.value < DeviceConstants.BRIGHTNESS_MIN ||
        action.value > DeviceConstants.BRIGHTNESS_MAX) {
        return AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'brightness');
      }
      return undefined;
    }
    if (action.action === DeviceAction.SET_COLOR) {
      if (typeof action.value !== 'string' || !COLOR_PATTERN.test(action.value)) {
        return AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'color');
      }
      return undefined;
    }
    if (action.action === DeviceAction.SET_TARGET_TEMPERATURE) {
      if (typeof action.value !== 'number' ||
        action.value < DeviceConstants.DEFAULT_TARGET_TEMP_MIN ||
        action.value > DeviceConstants.DEFAULT_TARGET_TEMP_MAX) {
        return AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'targetTemperature');
      }
      return undefined;
    }
    if (action.action === DeviceAction.SET_MODE) {
      if (typeof action.value !== 'string' || !DeviceConstants.isAcMode(action.value)) {
        return AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'mode');
      }
      return undefined;
    }
    return AppErrors.of('SCENE_REFERENCE_INVALID', []);
  }

  static actionMatchesType(type: DeviceType | undefined, action: DeviceAction): boolean {
    if (type === DeviceType.DOOR) {
      return action === DeviceAction.OPEN || action === DeviceAction.CLOSE;
    }
    if (type === DeviceType.LIGHT) {
      return action === DeviceAction.TURN_ON || action === DeviceAction.TURN_OFF ||
        action === DeviceAction.SET_BRIGHTNESS || action === DeviceAction.SET_COLOR;
    }
    if (type === DeviceType.AC) {
      return action === DeviceAction.TURN_ON || action === DeviceAction.TURN_OFF ||
        action === DeviceAction.SET_TARGET_TEMPERATURE || action === DeviceAction.SET_MODE;
    }
    // Sensors and unsupported types have no control actions.
    return false;
  }
}
