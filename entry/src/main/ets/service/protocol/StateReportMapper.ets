/*
 * YaoCore C-03 IoTDA state-report / shadow mapper.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-B §8.1.5/§8.3.3, D-014 fixed property paths
 *
 * Accepted shapes: SERVICES (state-report.schema.json), SHADOW (reported
 * service list) and DEVICES (device-keyed payload list). Unknown shapes,
 * non-object properties, invalid event_time and values outside fixed ranges
 * fail closed. DeviceInventoryJson is intentionally deferred to T-14/PB-02.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';
import { DeviceConstants } from '../../common/constants/DeviceConstants';
import { JsonKind, JsonNode } from '../../common/types/JsonNode';
import { JsonAtom } from '../../common/utils/JsonAtom';
import { JsonParser } from '../../common/utils/JsonParser';
import { Utf8 } from '../../common/utils/Utf8';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import {
  ShadowDeviceState,
  ShadowDeviceStateInit,
  ShadowShape,
  StateReportSnapshot
} from '../../model/CloudModels';

const SERVICE_FIELDS: ReadonlyArray<string> = ['service_id', 'properties', 'event_time'];
const SERVICES_ROOT_FIELDS: ReadonlyArray<string> = ['services'];
const SHADOW_SERVICE_FIELDS: ReadonlyArray<string> = ['service_id', 'reported', 'desired', 'version'];
const SHADOW_REPORTED_FIELDS: ReadonlyArray<string> = ['properties', 'event_time'];

/** Required fixed properties from input/api/protocol/state-report.schema.json. */
const REQUIRED_SERVICE_PROPERTIES: ReadonlyArray<string> = [
  'Door_01_Online', 'Light_01_Online', 'Sensor_01_Online', 'Presence_01_Online',
  'AC_01_Online', 'Gateway_Online', 'Gateway_RSSI'
];

const REQUIRED_BOOLEAN_PROPERTIES: ReadonlyArray<string> = [
  'Door_01_Online', 'Light_01_Online', 'Sensor_01_Online', 'Presence_01_Online',
  'AC_01_Online', 'Gateway_Online'
];

/** Full property allowlist (schema additionalProperties:false). */
const SERVICE_PROPERTY_FIELDS: ReadonlyArray<string> = [
  'DeviceInventoryJson',
  'Door_01_Online', 'Door_01_Status', 'Door_01_LastRequestId', 'Door_01_LastSeq',
  'Door_01_StateSource',
  'Light_01_Online', 'Light_01_Status', 'Light_01_Brightness', 'Light_01_LastRequestId',
  'Light_01_LastSeq', 'Light_01_StateSource', 'Light_01_TriggerDeviceId', 'Light_01_AutomationId',
  'Sensor_01_Online',
  'Presence_01_Online', 'Presence_01_Detected',
  'AC_01_Online', 'AC_01_Status', 'AC_01_TargetTemp', 'AC_01_Mode', 'AC_01_LastRequestId',
  'AC_01_LastSeq', 'AC_01_StateSource', 'AC_01_TriggerDeviceId', 'AC_01_AutomationId',
  'Room_01_Temperature', 'Room_01_Humidity',
  'Gateway_Online', 'Gateway_RSSI'
];

export class ShadowMapContext {
  readonly gatewayDeviceId: string;
  readonly receivedAtMs: number;
  readonly rawSha256: string;

  constructor(gatewayDeviceId: string, receivedAtMs: number, rawSha256: string = '') {
    this.gatewayDeviceId = gatewayDeviceId;
    this.receivedAtMs = receivedAtMs;
    this.rawSha256 = rawSha256;
  }
}

export class StateReportMapper {
  static map(body: Uint8Array, context: ShadowMapContext): StateReportSnapshot {
    try {
      const root = JsonParser.parse(Utf8.decode(body));
      if (root.kind !== JsonKind.OBJECT) {
        throw StateReportMapper.invalid('envelope');
      }
      if (root.has('services')) {
        return StateReportMapper.mapServices(root, context);
      }
      if (root.has('shadow')) {
        return StateReportMapper.mapShadow(root, context);
      }
      if (root.has('devices')) {
        return StateReportMapper.mapDevices(root, context);
      }
      throw StateReportMapper.invalid('shape');
    } catch (error) {
      if (error instanceof AppError) {
        if (error.code === 'CLOUD_SHADOW_INVALID' || error.code === 'PROTOCOL_INVALID_JSON' ||
          error.code === 'PROTOCOL_DUPLICATE_KEY' || error.code === 'PROTOCOL_BODY_TOO_LARGE') {
          throw error;
        }
      }
      throw StateReportMapper.invalid('shadow');
    }
  }

  private static mapServices(root: JsonNode, context: ShadowMapContext): StateReportSnapshot {
    // R-09: state-report.schema.json is authoritative for the SERVICES shape.
    // Top-level and service-level objects are closed; the seven fixed
    // properties are required. SHADOW/DEVICES shapes remain tolerant in T-06;
    // T-14 owns the full strict cloud adapter and DeviceInventoryJson.
    StateReportMapper.rejectUnknown(root, SERVICES_ROOT_FIELDS);
    const servicesNode = root.require('services');
    if (servicesNode.kind !== JsonKind.ARRAY || servicesNode.arrayValue.length !== 1) {
      throw StateReportMapper.invalid('services');
    }
    const serviceNode = servicesNode.arrayValue[0];
    if (serviceNode.kind !== JsonKind.OBJECT) {
      throw StateReportMapper.invalid('services');
    }
    StateReportMapper.rejectUnknown(serviceNode, SERVICE_FIELDS);
    const serviceId = StateReportMapper.requiredString(serviceNode, 'service_id');
    if (serviceId !== ProtocolConstants.SERVICE_ID_CLOUD) {
      throw StateReportMapper.invalid('service_id');
    }
    const propertiesNode = serviceNode.require('properties');
    if (propertiesNode.kind !== JsonKind.OBJECT) {
      throw StateReportMapper.invalid('properties');
    }
    StateReportMapper.validateServiceProperties(propertiesNode);
    const properties = StateReportMapper.flattenProperties(propertiesNode);
    const eventTime = StateReportMapper.requiredString(serviceNode, 'event_time');
    const eventEpochMs = DateTimeUtil.parseUtcCompact(eventTime);
    StateReportMapper.ensureFreshEnough(eventEpochMs, context.receivedAtMs);
    const bag = new PropertyBag(properties);
    const devices = StateReportMapper.mapFixedDevices(bag, eventTime);
    return new StateReportSnapshot(context.gatewayDeviceId, eventTime, properties, devices,
      bag.boolean('Gateway_Online'), context.receivedAtMs, context.rawSha256, ShadowShape.SERVICES);
  }

  private static mapShadow(root: JsonNode, context: ShadowMapContext): StateReportSnapshot {
    const shadowNode = root.require('shadow');
    if (shadowNode.kind !== JsonKind.ARRAY || shadowNode.arrayValue.length === 0) {
      throw StateReportMapper.invalid('shadow');
    }
    const properties: NameValue[] = [];
    let latestEventTime: string | undefined = undefined;
    let latestEpochMs = 0;
    for (let index = 0; index < shadowNode.arrayValue.length; index++) {
      const serviceNode = shadowNode.arrayValue[index];
      if (serviceNode.kind !== JsonKind.OBJECT) {
        throw StateReportMapper.invalid('shadow');
      }
      StateReportMapper.rejectUnknown(serviceNode, SHADOW_SERVICE_FIELDS);
      if (serviceNode.has('service_id')) {
        const serviceId = StateReportMapper.requiredString(serviceNode, 'service_id');
        if (serviceId !== ProtocolConstants.SERVICE_ID_CLOUD) {
          throw StateReportMapper.invalid('service_id');
        }
      }
      if (!serviceNode.has('reported')) {
        continue;
      }
      const reportedNode = serviceNode.require('reported');
      if (reportedNode.kind !== JsonKind.OBJECT) {
        throw StateReportMapper.invalid('reported');
      }
      StateReportMapper.rejectUnknown(reportedNode, SHADOW_REPORTED_FIELDS);
      const reportedProperties = StateReportMapper.flattenProperties(reportedNode.require('properties'));
      for (let p = 0; p < reportedProperties.length; p++) {
        properties.push(reportedProperties[p]);
      }
      const eventTime = StateReportMapper.requiredString(reportedNode, 'event_time');
      const eventEpochMs = DateTimeUtil.parseUtcCompact(eventTime);
      StateReportMapper.ensureFreshEnough(eventEpochMs, context.receivedAtMs);
      if (latestEventTime === undefined || eventEpochMs > latestEpochMs) {
        latestEventTime = eventTime;
        latestEpochMs = eventEpochMs;
      }
    }
    if (latestEventTime === undefined || properties.length === 0) {
      throw StateReportMapper.invalid('shadow');
    }
    const bag = new PropertyBag(properties);
    const devices = StateReportMapper.mapFixedDevices(bag, latestEventTime);
    return new StateReportSnapshot(context.gatewayDeviceId, latestEventTime, properties, devices,
      bag.boolean('Gateway_Online'), context.receivedAtMs, context.rawSha256, ShadowShape.SHADOW);
  }

  private static mapDevices(root: JsonNode, context: ShadowMapContext): StateReportSnapshot {
    const devicesNode = root.require('devices');
    if (devicesNode.kind !== JsonKind.ARRAY || devicesNode.arrayValue.length === 0) {
      throw StateReportMapper.invalid('devices');
    }
    const devices: ShadowDeviceState[] = [];
    let latestEventTime: string | undefined = undefined;
    let latestEpochMs = 0;
    let gatewayOnline: boolean | undefined = undefined;
    for (let index = 0; index < devicesNode.arrayValue.length; index++) {
      const entry = devicesNode.arrayValue[index];
      if (entry.kind !== JsonKind.OBJECT) {
        throw StateReportMapper.invalid('devices');
      }
      const deviceId = StateReportMapper.firstString(entry, 'device_id', 'deviceId');
      if (deviceId === undefined) {
        throw StateReportMapper.invalid('device_id');
      }
      const eventTime = StateReportMapper.firstString(entry, 'event_time', 'eventTime');
      if (eventTime === undefined) {
        throw StateReportMapper.invalid('event_time');
      }
      const eventEpochMs = DateTimeUtil.parseUtcCompact(eventTime);
      StateReportMapper.ensureFreshEnough(eventEpochMs, context.receivedAtMs);
      if (latestEventTime === undefined || eventEpochMs > latestEpochMs) {
        latestEventTime = eventTime;
        latestEpochMs = eventEpochMs;
      }
      const init = new ShadowDeviceStateInit();
      init.deviceId = deviceId;
      init.eventTime = eventTime;
      init.online = StateReportMapper.optionalBoolean(entry, 'online');
      init.power = StateReportMapper.optionalBoolean(entry, 'power');
      init.open = StateReportMapper.optionalBoolean(entry, 'open');
      init.brightness = StateReportMapper.optionalNumber(entry, 'brightness', 0, 100);
      init.temperature = StateReportMapper.optionalNumber(entry, 'temperature', -40, 125);
      init.humidity = StateReportMapper.optionalNumber(entry, 'humidity', 0, 100);
      init.presence = StateReportMapper.optionalBoolean(entry, 'presence');
      init.targetTemperature = StateReportMapper.optionalNumber(entry, 'target_temperature', 16, 30);
      if (init.targetTemperature === undefined) {
        init.targetTemperature = StateReportMapper.optionalNumber(entry, 'targetTemperature', 16, 30);
      }
      const color = StateReportMapper.optionalString(entry, 'color');
      if (color !== undefined) {
        if (!/^#[0-9A-F]{6}$/.test(color.toUpperCase())) {
          throw StateReportMapper.invalid('color');
        }
        init.color = color.toUpperCase();
      }
      const mode = StateReportMapper.optionalString(entry, 'mode');
      if (mode !== undefined) {
        init.mode = mode;
        init.modeStandard = DeviceConstants.isAcMode(mode);
      }
      const stateSource = StateReportMapper.optionalString(entry, 'state_source');
      if (stateSource !== undefined) {
        init.stateSource = stateSource;
        init.stateSourceKnown = DeviceConstants.isStateSource(stateSource);
      } else {
        const stateSourceCamel = StateReportMapper.optionalString(entry, 'stateSource');
        if (stateSourceCamel !== undefined) {
          init.stateSource = stateSourceCamel;
          init.stateSourceKnown = DeviceConstants.isStateSource(stateSourceCamel);
        }
      }
      init.triggerDeviceId = StateReportMapper.firstString(entry, 'trigger_device_id', 'triggerDeviceId');
      init.automationId = StateReportMapper.firstString(entry, 'automation_id', 'automationId');
      init.lastRequestId = StateReportMapper.firstString(entry, 'last_request_id', 'lastRequestId');
      const lastSeqSnake = StateReportMapper.optionalInteger(entry, 'last_seq', 0, ProtocolConstants.MAX_SEQ);
      init.lastSeq = lastSeqSnake === undefined ?
        StateReportMapper.optionalInteger(entry, 'lastSeq', 0, ProtocolConstants.MAX_SEQ) : lastSeqSnake;
      const state = ShadowDeviceState.create(init);
      devices.push(state);
      if (deviceId === 'Gateway' || deviceId === context.gatewayDeviceId) {
        gatewayOnline = state.online;
      }
    }
    if (latestEventTime === undefined) {
      throw StateReportMapper.invalid('event_time');
    }
    return new StateReportSnapshot(context.gatewayDeviceId, latestEventTime, [], devices, gatewayOnline,
      context.receivedAtMs, context.rawSha256, ShadowShape.DEVICES);
  }

  private static mapFixedDevices(bag: PropertyBag, eventTime: string): ShadowDeviceState[] {
    const devices: ShadowDeviceState[] = [];
    if (bag.hasAny(['Door_01_Online', 'Door_01_Status', 'Door_01_LastRequestId', 'Door_01_LastSeq',
      'Door_01_StateSource'])) {
      const init = new ShadowDeviceStateInit();
      init.deviceId = 'Door_01';
      init.eventTime = eventTime;
      init.online = bag.boolean('Door_01_Online');
      init.open = bag.statusOpen('Door_01_Status');
      init.lastRequestId = bag.requestId('Door_01_LastRequestId');
      init.lastSeq = bag.integer('Door_01_LastSeq', 0, ProtocolConstants.MAX_SEQ);
      init.stateSource = bag.stateSource('Door_01_StateSource');
      init.stateSourceKnown = init.stateSource !== undefined && DeviceConstants.isStateSource(init.stateSource);
      devices.push(ShadowDeviceState.create(init));
    }
    if (bag.hasAny(['Light_01_Online', 'Light_01_Status', 'Light_01_Brightness', 'Light_01_Color',
      'Light_01_LastRequestId', 'Light_01_LastSeq', 'Light_01_StateSource',
      'Light_01_TriggerDeviceId', 'Light_01_AutomationId'])) {
      const init = new ShadowDeviceStateInit();
      init.deviceId = 'Light_01';
      init.eventTime = eventTime;
      init.online = bag.boolean('Light_01_Online');
      init.power = bag.statusPower('Light_01_Status');
      init.brightness = bag.number('Light_01_Brightness', 0, 100);
      init.color = bag.color('Light_01_Color');
      init.lastRequestId = bag.requestId('Light_01_LastRequestId');
      init.lastSeq = bag.integer('Light_01_LastSeq', 0, ProtocolConstants.MAX_SEQ);
      init.stateSource = bag.stateSource('Light_01_StateSource');
      init.stateSourceKnown = init.stateSource !== undefined && DeviceConstants.isStateSource(init.stateSource);
      init.triggerDeviceId = bag.string('Light_01_TriggerDeviceId');
      init.automationId = bag.string('Light_01_AutomationId');
      devices.push(ShadowDeviceState.create(init));
    }
    if (bag.hasAny(['Sensor_01_Online', 'Room_01_Temperature', 'Room_01_Humidity'])) {
      const init = new ShadowDeviceStateInit();
      init.deviceId = 'Sensor_01';
      init.eventTime = eventTime;
      init.online = bag.boolean('Sensor_01_Online');
      init.temperature = bag.number('Room_01_Temperature', -40, 125);
      init.humidity = bag.number('Room_01_Humidity', 0, 100);
      devices.push(ShadowDeviceState.create(init));
    }
    if (bag.hasAny(['Presence_01_Online', 'Presence_01_Detected'])) {
      const init = new ShadowDeviceStateInit();
      init.deviceId = 'Presence_01';
      init.eventTime = eventTime;
      init.online = bag.boolean('Presence_01_Online');
      init.presence = bag.boolean('Presence_01_Detected');
      devices.push(ShadowDeviceState.create(init));
    }
    if (bag.hasAny(['AC_01_Online', 'AC_01_Status', 'AC_01_TargetTemp', 'AC_01_Mode',
      'AC_01_LastRequestId', 'AC_01_LastSeq', 'AC_01_StateSource', 'AC_01_TriggerDeviceId',
      'AC_01_AutomationId'])) {
      const init = new ShadowDeviceStateInit();
      init.deviceId = 'AC_01';
      init.eventTime = eventTime;
      init.online = bag.boolean('AC_01_Online');
      init.power = bag.statusPower('AC_01_Status');
      init.targetTemperature = bag.number('AC_01_TargetTemp', 16, 30);
      init.mode = bag.string('AC_01_Mode');
      init.modeStandard = init.mode !== undefined && DeviceConstants.isAcMode(init.mode);
      init.lastRequestId = bag.requestId('AC_01_LastRequestId');
      init.lastSeq = bag.integer('AC_01_LastSeq', 0, ProtocolConstants.MAX_SEQ);
      init.stateSource = bag.stateSource('AC_01_StateSource');
      init.stateSourceKnown = init.stateSource !== undefined && DeviceConstants.isStateSource(init.stateSource);
      init.triggerDeviceId = bag.string('AC_01_TriggerDeviceId');
      init.automationId = bag.string('AC_01_AutomationId');
      devices.push(ShadowDeviceState.create(init));
    }
    return devices;
  }

  private static validateServiceProperties(node: JsonNode): void {
    for (let index = 0; index < REQUIRED_SERVICE_PROPERTIES.length; index++) {
      if (!node.has(REQUIRED_SERVICE_PROPERTIES[index])) {
        throw StateReportMapper.invalid(REQUIRED_SERVICE_PROPERTIES[index]);
      }
    }
    const keys = node.keys();
    for (let index = 0; index < keys.length; index++) {
      if (SERVICE_PROPERTY_FIELDS.indexOf(keys[index]) < 0) {
        throw StateReportMapper.invalid(keys[index]);
      }
    }
    for (let index = 0; index < REQUIRED_BOOLEAN_PROPERTIES.length; index++) {
      if (node.require(REQUIRED_BOOLEAN_PROPERTIES[index]).kind !== JsonKind.BOOLEAN) {
        throw StateReportMapper.invalid(REQUIRED_BOOLEAN_PROPERTIES[index]);
      }
    }
    const rssi = node.require('Gateway_RSSI');
    if (rssi.kind !== JsonKind.NUMBER || !Number.isInteger(rssi.numberValue) ||
      rssi.numberValue < -127 || rssi.numberValue > 0) {
      throw StateReportMapper.invalid('Gateway_RSSI');
    }
  }

  private static flattenProperties(node: JsonNode): NameValue[] {
    if (node.kind !== JsonKind.OBJECT) {
      throw StateReportMapper.invalid('properties');
    }
    const result: NameValue[] = [];
    const keys = node.keys();
    for (let index = 0; index < keys.length; index++) {
      const key = keys[index];
      const value = node.require(key);
      if (value.kind === JsonKind.STRING) {
        result.push(new NameValue(key, value.stringValue));
      } else if (value.kind === JsonKind.NUMBER) {
        result.push(new NameValue(key, JsonAtom.normalizeNumber(value.numberValue)));
      } else if (value.kind === JsonKind.BOOLEAN) {
        result.push(new NameValue(key, value.booleanValue ? 'true' : 'false'));
      } else {
        throw StateReportMapper.invalid(key);
      }
    }
    return result;
  }

  private static requiredString(node: JsonNode, field: string): string {
    const value = node.require(field);
    if (value.kind !== JsonKind.STRING) {
      throw StateReportMapper.invalid(field);
    }
    return value.stringValue;
  }

  private static optionalString(node: JsonNode, field: string): string | undefined {
    if (!node.has(field)) {
      return undefined;
    }
    const value = node.require(field);
    if (value.kind !== JsonKind.STRING) {
      throw StateReportMapper.invalid(field);
    }
    return value.stringValue;
  }

  private static firstString(node: JsonNode, first: string, second: string): string | undefined {
    if (node.has(first)) {
      return StateReportMapper.requiredString(node, first);
    }
    if (node.has(second)) {
      return StateReportMapper.requiredString(node, second);
    }
    return undefined;
  }

  private static optionalBoolean(node: JsonNode, field: string): boolean | undefined {
    if (!node.has(field)) {
      return undefined;
    }
    const value = node.require(field);
    if (value.kind !== JsonKind.BOOLEAN) {
      throw StateReportMapper.invalid(field);
    }
    return value.booleanValue;
  }

  private static optionalNumber(node: JsonNode, field: string, min: number,
    max: number): number | undefined {
    if (!node.has(field)) {
      return undefined;
    }
    const value = node.require(field);
    if (value.kind !== JsonKind.NUMBER || !Number.isFinite(value.numberValue) ||
      value.numberValue < min || value.numberValue > max) {
      throw StateReportMapper.invalid(field);
    }
    return value.numberValue;
  }

  private static optionalInteger(node: JsonNode, field: string, min: number,
    max: number): number | undefined {
    if (!node.has(field)) {
      return undefined;
    }
    const value = node.require(field);
    if (value.kind !== JsonKind.NUMBER || !Number.isInteger(value.numberValue) ||
      value.numberValue < min || value.numberValue > max) {
      throw StateReportMapper.invalid(field);
    }
    return value.numberValue;
  }

  private static rejectUnknown(node: JsonNode, allowed: ReadonlyArray<string>): void {
    const keys = node.keys();
    for (let index = 0; index < keys.length; index++) {
      if (allowed.indexOf(keys[index]) < 0) {
        throw StateReportMapper.invalid(keys[index]);
      }
    }
  }

  private static ensureFreshEnough(eventEpochMs: number, receivedAtMs: number): void {
    if (!Number.isFinite(receivedAtMs) || eventEpochMs > receivedAtMs + 300000) {
      throw StateReportMapper.invalid('event_time');
    }
  }

  static invalid(field: string): AppError {
    return AppErrors.of('CLOUD_SHADOW_INVALID', [new NameValue('field', field)]);
  }
}

class PropertyBag {
  private readonly values: Map<string, string>;

  constructor(entries: ReadonlyArray<NameValue>) {
    this.values = new Map<string, string>();
    for (let index = 0; index < entries.length; index++) {
      this.values.set(entries[index].name, entries[index].value);
    }
  }

  hasAny(names: ReadonlyArray<string>): boolean {
    for (let index = 0; index < names.length; index++) {
      if (this.values.has(names[index])) {
        return true;
      }
    }
    return false;
  }

  string(name: string): string | undefined {
    return this.values.get(name);
  }

  boolean(name: string): boolean | undefined {
    const value = this.values.get(name);
    if (value === undefined) {
      return undefined;
    }
    if (value === 'true') {
      return true;
    }
    if (value === 'false') {
      return false;
    }
    throw StateReportMapper.invalid(name);
  }

  number(name: string, min: number, max: number): number | undefined {
    const value = this.values.get(name);
    if (value === undefined) {
      return undefined;
    }
    if (value.length === 0) {
      throw StateReportMapper.invalid(name);
    }
    const parsed = Number(value);
    if (!Number.isFinite(parsed) || parsed < min || parsed > max) {
      throw StateReportMapper.invalid(name);
    }
    return parsed;
  }

  integer(name: string, min: number, max: number): number | undefined {
    const parsed = this.number(name, min, max);
    if (parsed === undefined) {
      return undefined;
    }
    if (!Number.isInteger(parsed)) {
      throw StateReportMapper.invalid(name);
    }
    return parsed;
  }

  color(name: string): string | undefined {
    const value = this.values.get(name);
    if (value === undefined) {
      return undefined;
    }
    const normalized = value.toUpperCase();
    if (!/^#[0-9A-F]{6}$/.test(normalized)) {
      throw StateReportMapper.invalid(name);
    }
    return normalized;
  }

  statusPower(name: string): boolean | undefined {
    const value = this.values.get(name);
    if (value === undefined || value === 'UNKNOWN') {
      return undefined;
    }
    if (value === 'ON') {
      return true;
    }
    if (value === 'OFF') {
      return false;
    }
    throw StateReportMapper.invalid(name);
  }

  statusOpen(name: string): boolean | undefined {
    const value = this.values.get(name);
    if (value === undefined || value === 'UNKNOWN') {
      return undefined;
    }
    if (value === 'OPEN') {
      return true;
    }
    if (value === 'CLOSED') {
      return false;
    }
    throw StateReportMapper.invalid(name);
  }

  requestId(name: string): string | undefined {
    const value = this.values.get(name);
    if (value === undefined) {
      return undefined;
    }
    if (!ProtocolConstants.REQUEST_ID_PATTERN.test(value) ||
      value.length > ProtocolConstants.MAX_REQUEST_ID_LENGTH) {
      throw StateReportMapper.invalid(name);
    }
    return value;
  }

  stateSource(name: string): string | undefined {
    const value = this.values.get(name);
    if (value === undefined) {
      return undefined;
    }
    if (value.length === 0 || value.length > ProtocolConstants.MAX_ROOM_NAME_LENGTH) {
      throw StateReportMapper.invalid(name);
    }
    return value;
  }
}
