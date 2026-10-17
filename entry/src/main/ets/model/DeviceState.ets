/*
 * YaoCore C-02 device snapshot, patch and local state.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §5.1.2, §5.3 invariants 2..7
 *
 * Local/gateway field ownership:
 *   snapshot.*        gateway authoritative
 *   deviceName/roomId/isEnabled/isUnassigned/isDismissed  local authoritative
 */
import { AppErrors } from '../common/types/AppError';
import { ProtocolConstants } from '../common/constants/ProtocolConstants';
import { DeviceConstants, DeviceType } from '../common/constants/DeviceConstants';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import { UuidUtil } from '../common/utils/UuidUtil';
import { DeviceKey } from './DeviceKey';

const INBOUND_DEVICE_ID_PATTERN: RegExp = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/;
const COLOR_PATTERN: RegExp = /^#[0-9A-F]{6}$/;

export class DeviceSnapshotInit {
  deviceId: string = '';
  deviceName: string = '';
  roomNameHint: string = '';
  deviceTypeRaw: string = '';
  deviceType: DeviceType | undefined = undefined;
  isSupported: boolean = false;
  brand: string | undefined = undefined;
  isOnline: boolean = false;
  powerStatus: boolean | undefined = undefined;
  openStatus: boolean | undefined = undefined;
  brightness: number | undefined = undefined;
  color: string | undefined = undefined;
  temperature: number | undefined = undefined;
  humidity: number | undefined = undefined;
  presence: boolean | undefined = undefined;
  targetTemperature: number | undefined = undefined;
  mode: string | undefined = undefined;
  modeStandard: boolean = false;
  stateSource: string | undefined = undefined;
  stateSourceKnown: boolean = false;
  triggerDeviceId: string | undefined = undefined;
  automationId: string | undefined = undefined;
  lastRequestId: string | undefined = undefined;
  lastSeq: number | undefined = undefined;
  updatedAt: string = '';
}

export class DeviceSnapshot {
  readonly deviceId: string;
  readonly deviceName: string;
  readonly roomNameHint: string;
  readonly deviceTypeRaw: string;
  readonly deviceType: DeviceType | undefined;
  readonly isSupported: boolean;
  readonly brand?: string;
  readonly isOnline: boolean;
  readonly powerStatus?: boolean;
  readonly openStatus?: boolean;
  readonly brightness?: number;
  readonly color?: string;
  readonly temperature?: number;
  readonly humidity?: number;
  readonly presence?: boolean;
  readonly targetTemperature?: number;
  readonly mode?: string;
  readonly modeStandard: boolean;
  readonly stateSource?: string;
  readonly stateSourceKnown: boolean;
  readonly triggerDeviceId?: string;
  readonly automationId?: string;
  readonly lastRequestId?: string;
  readonly lastSeq?: number;
  readonly updatedAt: string;
  readonly stateEpochMs: number;

  private constructor(init: DeviceSnapshotInit, stateEpochMs: number) {
    this.deviceId = init.deviceId;
    this.deviceName = init.deviceName;
    this.roomNameHint = init.roomNameHint;
    this.deviceTypeRaw = init.deviceTypeRaw;
    this.deviceType = init.deviceType;
    this.isSupported = init.isSupported;
    this.brand = init.brand;
    this.isOnline = init.isOnline;
    this.powerStatus = init.powerStatus;
    this.openStatus = init.openStatus;
    this.brightness = init.brightness;
    this.color = init.color;
    this.temperature = init.temperature;
    this.humidity = init.humidity;
    this.presence = init.presence;
    this.targetTemperature = init.targetTemperature;
    this.mode = init.mode;
    this.modeStandard = init.modeStandard;
    this.stateSource = init.stateSource;
    this.stateSourceKnown = init.stateSourceKnown;
    this.triggerDeviceId = init.triggerDeviceId;
    this.automationId = init.automationId;
    this.lastRequestId = init.lastRequestId;
    this.lastSeq = init.lastSeq;
    this.updatedAt = init.updatedAt;
    this.stateEpochMs = stateEpochMs;
  }

  static create(init: DeviceSnapshotInit): DeviceSnapshot {
    DeviceStateValidation.deviceIdInbound(init.deviceId);
    DeviceStateValidation.text(init.deviceName, 'deviceName', ProtocolConstants.MAX_GATEWAY_NAME_LENGTH);
    if (init.roomNameHint.length > ProtocolConstants.MAX_ROOM_NAME_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'roomName');
    }
    if (init.deviceTypeRaw.length === 0 || init.deviceTypeRaw.length > 63) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'deviceType');
    }
    const expectedSupported = init.deviceType !== undefined && DeviceConstants.isSupported(init.deviceType);
    if (init.isSupported !== expectedSupported) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (init.brand !== undefined && init.brand.length > ProtocolConstants.MAX_BRAND_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'brand');
    }
    DeviceStateValidation.rangeOptional(init.brightness, 0, 100, 'brightness');
    DeviceStateValidation.rangeOptional(init.temperature, -40, 125, 'temperature');
    DeviceStateValidation.rangeOptional(init.humidity, 0, 100, 'humidity');
    DeviceStateValidation.rangeOptional(init.targetTemperature, 16, 30, 'targetTemp');
    if (init.color !== undefined && !COLOR_PATTERN.test(init.color)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'color');
    }
    if (init.mode !== undefined && init.mode.length > ProtocolConstants.MAX_MODE_LENGTH_INBOUND) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'mode');
    }
    if (init.mode === undefined && init.modeStandard) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (init.mode !== undefined && init.modeStandard !== DeviceConstants.isAcMode(init.mode)) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (init.stateSource !== undefined && init.stateSource.length > ProtocolConstants.MAX_ROOM_NAME_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'stateSource');
    }
    if (init.stateSource === undefined && init.stateSourceKnown) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (init.stateSource !== undefined &&
      init.stateSourceKnown !== DeviceConstants.isStateSource(init.stateSource)) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (init.triggerDeviceId !== undefined) {
      DeviceStateValidation.deviceIdInbound(init.triggerDeviceId);
    }
    if (init.automationId !== undefined) {
      DeviceStateValidation.text(init.automationId, 'automationId',
        ProtocolConstants.MAX_AUTOMATION_ID_LENGTH);
    }
    if (init.lastRequestId !== undefined) {
      DeviceStateValidation.requestId(init.lastRequestId);
    }
    DeviceStateValidation.rangeOptional(init.lastSeq, 0, ProtocolConstants.MAX_SEQ, 'lastSeq');
    const stateEpochMs = DateTimeUtil.parseUtcCompact(init.updatedAt);
    return new DeviceSnapshot(init, stateEpochMs);
  }
}

export class DeviceStatePatchInit {
  deviceId: string = '';
  isOnline: boolean = false;
  powerStatus: boolean | undefined = undefined;
  openStatus: boolean | undefined = undefined;
  brightness: number | undefined = undefined;
  color: string | undefined = undefined;
  temperature: number | undefined = undefined;
  humidity: number | undefined = undefined;
  presence: boolean | undefined = undefined;
  targetTemperature: number | undefined = undefined;
  mode: string | undefined = undefined;
  modeStandard: boolean = false;
  stateSource: string | undefined = undefined;
  stateSourceKnown: boolean = false;
  triggerDeviceId: string | undefined = undefined;
  automationId: string | undefined = undefined;
  lastRequestId: string | undefined = undefined;
  lastSeq: number | undefined = undefined;
  updatedAt: string = '';
}

export class DeviceStatePatch {
  readonly deviceId: string;
  readonly isOnline: boolean;
  readonly powerStatus?: boolean;
  readonly openStatus?: boolean;
  readonly brightness?: number;
  readonly color?: string;
  readonly temperature?: number;
  readonly humidity?: number;
  readonly presence?: boolean;
  readonly targetTemperature?: number;
  readonly mode?: string;
  readonly modeStandard: boolean;
  readonly stateSource?: string;
  readonly stateSourceKnown: boolean;
  readonly triggerDeviceId?: string;
  readonly automationId?: string;
  readonly lastRequestId?: string;
  readonly lastSeq?: number;
  readonly updatedAt: string;
  readonly stateEpochMs: number;

  private constructor(init: DeviceStatePatchInit, stateEpochMs: number) {
    this.deviceId = init.deviceId;
    this.isOnline = init.isOnline;
    this.powerStatus = init.powerStatus;
    this.openStatus = init.openStatus;
    this.brightness = init.brightness;
    this.color = init.color;
    this.temperature = init.temperature;
    this.humidity = init.humidity;
    this.presence = init.presence;
    this.targetTemperature = init.targetTemperature;
    this.mode = init.mode;
    this.modeStandard = init.modeStandard;
    this.stateSource = init.stateSource;
    this.stateSourceKnown = init.stateSourceKnown;
    this.triggerDeviceId = init.triggerDeviceId;
    this.automationId = init.automationId;
    this.lastRequestId = init.lastRequestId;
    this.lastSeq = init.lastSeq;
    this.updatedAt = init.updatedAt;
    this.stateEpochMs = stateEpochMs;
  }

  static create(init: DeviceStatePatchInit): DeviceStatePatch {
    DeviceStateValidation.deviceIdInbound(init.deviceId);
    DeviceStateValidation.rangeOptional(init.brightness, 0, 100, 'brightness');
    DeviceStateValidation.rangeOptional(init.temperature, -40, 125, 'temperature');
    DeviceStateValidation.rangeOptional(init.humidity, 0, 100, 'humidity');
    DeviceStateValidation.rangeOptional(init.targetTemperature, 16, 30, 'targetTemp');
    if (init.color !== undefined && !COLOR_PATTERN.test(init.color)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'color');
    }
    if (init.mode !== undefined && init.mode.length > ProtocolConstants.MAX_MODE_LENGTH_INBOUND) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'mode');
    }
    if (init.mode === undefined && init.modeStandard) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (init.mode !== undefined && init.modeStandard !== DeviceConstants.isAcMode(init.mode)) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (init.stateSource !== undefined && init.stateSource.length > ProtocolConstants.MAX_ROOM_NAME_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'stateSource');
    }
    if (init.stateSource === undefined && init.stateSourceKnown) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (init.stateSource !== undefined &&
      init.stateSourceKnown !== DeviceConstants.isStateSource(init.stateSource)) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (init.triggerDeviceId !== undefined) {
      DeviceStateValidation.deviceIdInbound(init.triggerDeviceId);
    }
    if (init.automationId !== undefined) {
      DeviceStateValidation.text(init.automationId, 'automationId',
        ProtocolConstants.MAX_AUTOMATION_ID_LENGTH);
    }
    if (init.lastRequestId !== undefined) {
      DeviceStateValidation.requestId(init.lastRequestId);
    }
    DeviceStateValidation.rangeOptional(init.lastSeq, 0, ProtocolConstants.MAX_SEQ, 'lastSeq');
    const stateEpochMs = DateTimeUtil.parseUtcCompact(init.updatedAt);
    return new DeviceStatePatch(init, stateEpochMs);
  }
}

export class DeviceState {
  readonly key: DeviceKey;
  readonly familyId: string;
  readonly snapshot: DeviceSnapshot;
  readonly deviceName: string;
  readonly roomId: string;
  readonly isEnabled: boolean;
  readonly isUnassigned: boolean;
  readonly isDismissed: boolean;

  constructor(key: DeviceKey, familyId: string, snapshot: DeviceSnapshot, deviceName: string,
    roomId: string, isEnabled: boolean, isUnassigned: boolean, isDismissed: boolean) {
    if (familyId.length === 0 || familyId.length > 63) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'familyId');
    }
    if (snapshot.deviceId !== key.deviceId) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    DeviceStateValidation.text(deviceName, 'deviceName', ProtocolConstants.MAX_GATEWAY_NAME_LENGTH);
    if (roomId.length === 0) {
      if (!isUnassigned) {
        throw AppErrors.of('CONFIGURATION_ERROR', []);
      }
    } else {
      if (!UuidUtil.isValidUuid(roomId) || isUnassigned) {
        throw AppErrors.of('CONFIGURATION_ERROR', []);
      }
    }
    this.key = key;
    this.familyId = familyId;
    this.snapshot = snapshot;
    this.deviceName = deviceName;
    this.roomId = roomId;
    this.isEnabled = isEnabled;
    this.isUnassigned = isUnassigned;
    this.isDismissed = isDismissed;
  }
}

export class RoomRef {
  readonly roomId: string;
  readonly roomName: string;

  constructor(roomId: string, roomName: string) {
    if (!UuidUtil.isValidUuid(roomId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'roomId');
    }
    DeviceStateValidation.text(roomName, 'roomName', ProtocolConstants.MAX_ROOM_NAME_LENGTH);
    this.roomId = roomId;
    this.roomName = roomName;
  }
}

class DeviceStateValidation {
  static deviceIdInbound(value: string): void {
    if (value.length === 0 || value.length > ProtocolConstants.MAX_IDENTIFIER_LENGTH_INBOUND ||
      value.indexOf(':') >= 0 || !INBOUND_DEVICE_ID_PATTERN.test(value)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'deviceId');
    }
  }

  static text(value: string, field: string, maxLength: number): void {
    if (value.length === 0 || value.length > maxLength) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', field);
    }
  }

  static requestId(value: string): void {
    if (!ProtocolConstants.REQUEST_ID_PATTERN.test(value) ||
      value.length > ProtocolConstants.MAX_REQUEST_ID_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'requestId');
    }
  }

  static rangeOptional(value: number | undefined, min: number, max: number, field: string): void {
    if (value === undefined) {
      return;
    }
    if (!Number.isFinite(value) || value < min || value > max) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', field);
    }
  }
}
