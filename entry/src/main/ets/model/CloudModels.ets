/*
 * YaoCore C-02 cloud mapping value models (shared subset).
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §5.1.7 (CloudConfig), DES-B §8.1.2/§8.3.3
 *
 * T-06 maps IoTDA state reports/shadows into StateReportSnapshot. Full
 * CloudService/ShadowReader/CompletionEvaluator behavior belongs to T-14.
 */
import { AppErrors } from '../common/types/AppError';
import { NameValue } from '../common/types/NameValue';
import { ProtocolConstants } from '../common/constants/ProtocolConstants';
import { DeviceConstants } from '../common/constants/DeviceConstants';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';

const COLOR_PATTERN: RegExp = /^#[0-9A-F]{6}$/;
const HEX_LOWER_64: RegExp = /^[0-9a-f]{64}$/;

export enum ShadowShape {
  SERVICES = 'SERVICES',
  SHADOW = 'SHADOW',
  DEVICES = 'DEVICES',
  UNKNOWN = 'UNKNOWN'
}

export class ShadowDeviceStateInit {
  deviceId: string = '';
  online: boolean | undefined = undefined;
  power: boolean | undefined = undefined;
  open: boolean | undefined = undefined;
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
  eventTime: string = '';
}

/** One device state derived from built-in fixed cloud property prefixes. */
export class ShadowDeviceState {
  readonly deviceId: string;
  readonly online?: boolean;
  readonly power?: boolean;
  readonly open?: boolean;
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
  readonly eventTime: string;
  readonly eventEpochMs: number;

  private constructor(init: ShadowDeviceStateInit, eventEpochMs: number) {
    this.deviceId = init.deviceId;
    this.online = init.online;
    this.power = init.power;
    this.open = init.open;
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
    this.eventTime = init.eventTime;
    this.eventEpochMs = eventEpochMs;
  }

  static create(init: ShadowDeviceStateInit): ShadowDeviceState {
    if (init.deviceId.length === 0 || init.deviceId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      init.deviceId.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(init.deviceId)) {
      throw AppErrors.of('CLOUD_SHADOW_INVALID', []);
    }
    ShadowStateValidation.range(init.brightness, 0, 100);
    ShadowStateValidation.range(init.temperature, -40, 125);
    ShadowStateValidation.range(init.humidity, 0, 100);
    ShadowStateValidation.range(init.targetTemperature, 16, 30);
    if (init.color !== undefined && !COLOR_PATTERN.test(init.color)) {
      throw AppErrors.of('CLOUD_SHADOW_INVALID', []);
    }
    if (init.mode !== undefined) {
      if (init.mode.length > ProtocolConstants.MAX_MODE_LENGTH_INBOUND) {
        throw AppErrors.of('CLOUD_SHADOW_INVALID', []);
      }
      if (init.modeStandard !== DeviceConstants.isAcMode(init.mode)) {
        throw AppErrors.of('CLOUD_SHADOW_INVALID', []);
      }
    } else if (init.modeStandard) {
      throw AppErrors.of('CLOUD_SHADOW_INVALID', []);
    }
    if (init.stateSource !== undefined && init.stateSource.length > ProtocolConstants.MAX_ROOM_NAME_LENGTH) {
      throw AppErrors.of('CLOUD_SHADOW_INVALID', []);
    }
    if (init.stateSource === undefined && init.stateSourceKnown) {
      throw AppErrors.of('CLOUD_SHADOW_INVALID', []);
    }
    if (init.stateSource !== undefined &&
      init.stateSourceKnown !== DeviceConstants.isStateSource(init.stateSource)) {
      throw AppErrors.of('CLOUD_SHADOW_INVALID', []);
    }
    if (init.triggerDeviceId !== undefined) {
      if (init.triggerDeviceId.length === 0 ||
        init.triggerDeviceId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
        init.triggerDeviceId.indexOf(':') >= 0 ||
        !ProtocolConstants.DEVICE_ID_PATTERN.test(init.triggerDeviceId)) {
        throw AppErrors.of('CLOUD_SHADOW_INVALID', []);
      }
    }
    if (init.automationId !== undefined) {
      if (init.automationId.length === 0 ||
        init.automationId.length > ProtocolConstants.MAX_AUTOMATION_ID_LENGTH) {
        throw AppErrors.of('CLOUD_SHADOW_INVALID', []);
      }
    }
    if (init.lastRequestId !== undefined) {
      if (!ProtocolConstants.REQUEST_ID_PATTERN.test(init.lastRequestId) ||
        init.lastRequestId.length > ProtocolConstants.MAX_REQUEST_ID_LENGTH) {
        throw AppErrors.of('CLOUD_SHADOW_INVALID', []);
      }
    }
    if (init.lastSeq !== undefined &&
      (!Number.isInteger(init.lastSeq) || init.lastSeq < 0 || init.lastSeq > ProtocolConstants.MAX_SEQ)) {
      throw AppErrors.of('CLOUD_SHADOW_INVALID', []);
    }
    const eventEpochMs = DateTimeUtil.parseUtcCompact(init.eventTime);
    return new ShadowDeviceState(init, eventEpochMs);
  }
}

/** External inventory candidate (PB-02); structure is not frozen. */
export class InventoryDeviceState {
  readonly deviceId: string;
  readonly online?: boolean;
  readonly power?: boolean;
  readonly open?: boolean;
  readonly brightness?: number;
  readonly color?: string;
  readonly temperature?: number;
  readonly humidity?: number;
  readonly presence?: boolean;
  readonly targetTemperature?: number;
  readonly mode?: string;
  readonly stateSource?: string;
  readonly triggerDeviceId?: string;
  readonly automationId?: string;
  readonly eventTime?: string;
  readonly lastRequestId?: string;
  readonly lastSeq?: number;

  constructor(deviceId: string, online?: boolean, power?: boolean, open?: boolean,
    brightness?: number, color?: string, temperature?: number, humidity?: number,
    presence?: boolean, targetTemperature?: number, mode?: string, stateSource?: string,
    triggerDeviceId?: string, automationId?: string, eventTime?: string,
    lastRequestId?: string, lastSeq?: number) {
    if (deviceId.length === 0 || deviceId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH) {
      throw AppErrors.of('CLOUD_INVENTORY_UNSUPPORTED', []);
    }
    this.deviceId = deviceId;
    this.online = online;
    this.power = power;
    this.open = open;
    this.brightness = brightness;
    this.color = color;
    this.temperature = temperature;
    this.humidity = humidity;
    this.presence = presence;
    this.targetTemperature = targetTemperature;
    this.mode = mode;
    this.stateSource = stateSource;
    this.triggerDeviceId = triggerDeviceId;
    this.automationId = automationId;
    this.eventTime = eventTime;
    this.lastRequestId = lastRequestId;
    this.lastSeq = lastSeq;
  }
}

export class StateReportSnapshot {
  readonly gatewayDeviceId: string;
  readonly eventTime: string;
  readonly eventEpochMs: number;
  readonly properties: ReadonlyArray<NameValue>;
  readonly devices: ReadonlyArray<ShadowDeviceState>;
  readonly gatewayOnline?: boolean;
  readonly receivedAtMs: number;
  readonly rawSha256: string;
  readonly shape: ShadowShape;

  constructor(gatewayDeviceId: string, eventTime: string, properties: ReadonlyArray<NameValue>,
    devices: ReadonlyArray<ShadowDeviceState>, gatewayOnline: boolean | undefined,
    receivedAtMs: number, rawSha256: string, shape: ShadowShape) {
    if (gatewayDeviceId.length === 0 || gatewayDeviceId.length > 128) {
      throw AppErrors.of('CLOUD_SHADOW_INVALID', []);
    }
    const eventEpochMs = DateTimeUtil.parseUtcCompact(eventTime);
    if (!Number.isFinite(receivedAtMs) || receivedAtMs < 0) {
      throw AppErrors.of('CLOUD_SHADOW_INVALID', []);
    }
    if (rawSha256.length !== 0 && !HEX_LOWER_64.test(rawSha256)) {
      throw AppErrors.of('CLOUD_SHADOW_INVALID', []);
    }
    this.gatewayDeviceId = gatewayDeviceId;
    this.eventTime = eventTime;
    this.eventEpochMs = eventEpochMs;
    this.properties = properties;
    this.devices = devices;
    this.gatewayOnline = gatewayOnline;
    this.receivedAtMs = receivedAtMs;
    this.rawSha256 = rawSha256;
    this.shape = shape;
  }
}

class ShadowStateValidation {
  static range(value: number | undefined, min: number, max: number): void {
    if (value === undefined) {
      return;
    }
    if (!Number.isFinite(value) || value < min || value > max) {
      throw AppErrors.of('CLOUD_SHADOW_INVALID', []);
    }
  }
}
