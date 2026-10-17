/*
 * YaoCore C-01 device/action vocabulary.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §4.1.3
 */
export enum DeviceType {
  DOOR = 'door',
  LIGHT = 'light',
  SENSOR = 'sensor',
  AC = 'ac',
  SWITCH = 'switch',
  CAMERA = 'camera',
  CURTAIN = 'curtain',
  FAN = 'fan',
  SPEAKER = 'speaker'
}

export enum DeviceAction {
  OPEN = 'OPEN',
  CLOSE = 'CLOSE',
  TURN_ON = 'ON',
  TURN_OFF = 'OFF',
  SET_BRIGHTNESS = 'SET_BRIGHTNESS',
  SET_COLOR = 'SET_COLOR',
  SET_TARGET_TEMPERATURE = 'SET_TARGET_TEMPERATURE',
  SET_MODE = 'SET_MODE',
  SET_POSITION = 'SET_POSITION',
  SET_SPEED = 'SET_SPEED',
  SET_VOLUME = 'SET_VOLUME',
  SET_DEVICE_NAME = 'SET_DEVICE_NAME',
  SET_DEVICE_ROOM = 'SET_DEVICE_ROOM',
  STOP = 'STOP',
  BOARD_LED_ON = 'BOARD_LED_ON',
  BOARD_LED_OFF = 'BOARD_LED_OFF',
  PING = 'PING'
}

export enum ActionValueKind {
  NONE = 'NONE',
  BOOLEAN = 'BOOLEAN',
  NUMBER = 'NUMBER',
  STRING = 'STRING',
  COLOR = 'STRING_COLOR'
}

export class DeviceConstants {
  static readonly SUPPORTED_TYPES: ReadonlyArray<DeviceType> = [
    DeviceType.DOOR, DeviceType.LIGHT, DeviceType.SENSOR, DeviceType.AC
  ];
  static readonly READ_ONLY_TYPES: ReadonlyArray<DeviceType> = [
    DeviceType.SWITCH, DeviceType.CAMERA, DeviceType.CURTAIN, DeviceType.FAN, DeviceType.SPEAKER
  ];
  static readonly AC_MODES: ReadonlyArray<string> = ['AUTO', 'COOL', 'HEAT', 'DRY', 'FAN', 'ECO', 'SLEEP'];
  static readonly STATE_SOURCES: ReadonlyArray<string> = [
    'sensor.physical', 'device.feedback', 'automation.local', 'app.lan', 'app.cloud'
  ];
  static readonly LOCAL_ONLY_ACTIONS: ReadonlyArray<DeviceAction> = [
    DeviceAction.SET_DEVICE_NAME, DeviceAction.SET_DEVICE_ROOM
  ];
  static readonly GATEWAY_ACTIONS: ReadonlyArray<DeviceAction> = [
    DeviceAction.BOARD_LED_ON, DeviceAction.BOARD_LED_OFF, DeviceAction.PING
  ];
  static readonly DEFAULT_TARGET_TEMP_MIN: number = 16;
  static readonly DEFAULT_TARGET_TEMP_MAX: number = 30;
  static readonly BRIGHTNESS_MIN: number = 0;
  static readonly BRIGHTNESS_MAX: number = 100;
  static readonly DOOR_CONFIRM_TIMEOUT_MS: number = 10000;

  static isSupported(type: DeviceType): boolean {
    return DeviceConstants.SUPPORTED_TYPES.indexOf(type) >= 0;
  }

  static isAcMode(value: string): boolean {
    return DeviceConstants.AC_MODES.indexOf(value) >= 0;
  }

  static isStateSource(value: string): boolean {
    return DeviceConstants.STATE_SOURCES.indexOf(value) >= 0;
  }

  /** Returns the internal state field name, or undefined when v1 LAN has no such field. */
  static actionToStateField(action: DeviceAction): string | undefined {
    if (action === DeviceAction.OPEN || action === DeviceAction.CLOSE) {
      return 'open';
    }
    if (action === DeviceAction.TURN_ON || action === DeviceAction.TURN_OFF) {
      return 'power';
    }
    if (action === DeviceAction.SET_BRIGHTNESS) {
      return 'brightness';
    }
    if (action === DeviceAction.SET_COLOR) {
      return 'color';
    }
    if (action === DeviceAction.SET_TARGET_TEMPERATURE) {
      return 'targetTemp';
    }
    if (action === DeviceAction.SET_MODE) {
      return 'mode';
    }
    if (action === DeviceAction.BOARD_LED_ON || action === DeviceAction.BOARD_LED_OFF) {
      return 'boardLed';
    }
    return undefined;
  }

  static actionToValueKind(action: DeviceAction): ActionValueKind {
    if (action === DeviceAction.OPEN || action === DeviceAction.CLOSE ||
      action === DeviceAction.TURN_ON || action === DeviceAction.TURN_OFF ||
      action === DeviceAction.BOARD_LED_ON || action === DeviceAction.BOARD_LED_OFF) {
      return ActionValueKind.BOOLEAN;
    }
    if (action === DeviceAction.SET_BRIGHTNESS || action === DeviceAction.SET_TARGET_TEMPERATURE ||
      action === DeviceAction.SET_POSITION || action === DeviceAction.SET_SPEED ||
      action === DeviceAction.SET_VOLUME) {
      return ActionValueKind.NUMBER;
    }
    if (action === DeviceAction.SET_MODE || action === DeviceAction.SET_DEVICE_NAME ||
      action === DeviceAction.SET_DEVICE_ROOM) {
      return ActionValueKind.STRING;
    }
    if (action === DeviceAction.SET_COLOR) {
      return ActionValueKind.COLOR;
    }
    return ActionValueKind.NONE;
  }
}
