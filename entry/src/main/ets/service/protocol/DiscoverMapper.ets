/*
 * YaoCore C-03 discover response mapper.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §6.1.2, §6.3, §18.8
 *
 * Top-level envelope failures are fail-closed. Device-level failures skip the
 * device and set isPartial=true. Alias fields are read only when the canonical
 * wire field is absent; `success` is always ignored.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';
import { DeviceConstants, DeviceType } from '../../common/constants/DeviceConstants';
import { DeviationCode, ProtocolDeviation } from '../../common/types/ProtocolDeviation';
import { JsonKind, JsonNode } from '../../common/types/JsonNode';
import { JsonParser } from '../../common/utils/JsonParser';
import { Utf8 } from '../../common/utils/Utf8';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import { DeviceSnapshot, DeviceSnapshotInit } from '../../model/DeviceState';
import { DiscoverySecurity, DiscoverySnapshot, DiscoverySnapshotInit } from '../../model/DiscoveryModels';
import type { ProtocolDeviationSink } from './ProtocolDeviation';
import { ProtocolErrors } from './ProtocolErrors';

const TOP_LEVEL_FIELDS: ReadonlyArray<string> = [
  'protocolVersion', 'gatewayId', 'gatewayName', 'serviceId', 'generatedAt', 'security', 'devices'
];

const SECURITY_FIELDS: ReadonlyArray<string> = [
  'alg', 'keyId', 'timeWindowSeconds', 'nonceTtlSeconds'
];

const DEVICE_FIELDS: ReadonlyArray<string> = [
  'deviceId', 'deviceName', 'roomName', 'deviceType', 'brand', 'online', 'power', 'open',
  'brightness', 'color', 'temperature', 'humidity', 'presence', 'targetTemp', 'mode',
  'lastRequestId', 'lastSeq', 'stateSource', 'triggerDeviceId', 'automationId', 'updatedAt',
  // Known inbound aliases and the ignored success field are consumed with deviations.
  'isOnline', 'powerStatus', 'openStatus', 'targetTemperature', 'success'
];

const INBOUND_DEVICE_ID_PATTERN: RegExp = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/;
const COLOR_PATTERN: RegExp = /^#[0-9A-Fa-f]{6}$/;

export class DiscoverMapContext {
  readonly expectedGatewayId?: string;
  readonly nowMs: number;

  constructor(expectedGatewayId: string | undefined, nowMs: number) {
    this.expectedGatewayId = expectedGatewayId;
    this.nowMs = nowMs;
  }
}

export class DiscoverMapper {
  static map(body: Uint8Array, context: DiscoverMapContext,
    deviations: ProtocolDeviationSink): DiscoverySnapshot {
    const root = JsonParser.parse(Utf8.decode(body));
    if (root.kind !== JsonKind.OBJECT) {
      throw ProtocolErrors.discoveryInvalid('envelope');
    }
    DiscoverMapper.rejectUnknownFields(root, TOP_LEVEL_FIELDS, 'DISCOVERY_INVALID_RESPONSE');
    const collected: ProtocolDeviation[] = [];
    const protocolVersion = DiscoverMapper.requiredString(root, 'protocolVersion');
    if (protocolVersion !== ProtocolConstants.PROTOCOL_VERSION_20) {
      throw ProtocolErrors.unsupportedVersion(protocolVersion);
    }
    const gatewayId = DiscoverMapper.requiredString(root, 'gatewayId');
    DiscoverMapper.validateGatewayId(gatewayId);
    if (context.expectedGatewayId !== undefined && context.expectedGatewayId !== gatewayId) {
      throw ProtocolErrors.gatewayIdMismatch(context.expectedGatewayId, gatewayId);
    }
    const gatewayName = DiscoverMapper.requiredString(root, 'gatewayName');
    if (gatewayName.length === 0 || gatewayName.length > ProtocolConstants.MAX_GATEWAY_NAME_LENGTH) {
      throw ProtocolErrors.discoveryInvalid('gatewayName');
    }
    const serviceId = DiscoverMapper.requiredString(root, 'serviceId');
    if (serviceId !== ProtocolConstants.SERVICE_ID_CLOUD) {
      throw ProtocolErrors.discoveryInvalid('serviceId');
    }
    const generatedAt = DiscoverMapper.requiredString(root, 'generatedAt');
    DateTimeUtil.parseUtcCompact(generatedAt);

    const securityNode = root.require('security');
    if (securityNode.kind !== JsonKind.OBJECT) {
      throw ProtocolErrors.discoveryInvalid('security');
    }
    DiscoverMapper.rejectUnknownFields(securityNode, SECURITY_FIELDS, 'DISCOVERY_INVALID_RESPONSE');
    const security = new DiscoverySecurity(
      DiscoverMapper.requiredString(securityNode, 'alg'),
      DiscoverMapper.requiredString(securityNode, 'keyId'),
      DiscoverMapper.requiredInteger(securityNode, 'timeWindowSeconds'),
      DiscoverMapper.requiredInteger(securityNode, 'nonceTtlSeconds')
    );

    const devicesNode = root.require('devices');
    if (devicesNode.kind !== JsonKind.ARRAY) {
      throw ProtocolErrors.discoveryInvalid('devices');
    }
    const devices: DeviceSnapshot[] = [];
    let isPartial = false;
    for (let index = 0; index < devicesNode.arrayValue.length; index++) {
      try {
        const mapped = DiscoverMapper.mapDevice(devicesNode.arrayValue[index], gatewayId, collected, deviations);
        devices.push(mapped.snapshot);
        if (mapped.partial) {
          isPartial = true;
        }
      } catch (error) {
        isPartial = true;
        const deviceId = DiscoverMapper.optionalDeviceIdForDiagnostics(devicesNode.arrayValue[index]);
        DiscoverMapper.record(collected, deviations, new ProtocolDeviation(DeviationCode.DEVICE_SKIPPED,
          gatewayId, deviceId, 'devices', DiscoverMapper.errorReason(error)));
      }
    }

    const init = new DiscoverySnapshotInit();
    init.gatewayId = gatewayId;
    init.gatewayName = gatewayName;
    init.serviceId = serviceId;
    init.protocolVersion = protocolVersion;
    init.generatedAt = generatedAt;
    init.security = security;
    init.devices = devices;
    init.isPartial = isPartial;
    init.deviations = collected;
    return DiscoverySnapshot.create(init);
  }

  private static mapDevice(node: JsonNode, gatewayId: string, collected: ProtocolDeviation[],
    sink: ProtocolDeviationSink): MappedDevice {
    if (node.kind !== JsonKind.OBJECT) {
      throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'device');
    }
    DiscoverMapper.rejectUnknownFields(node, DEVICE_FIELDS, 'PROTOCOL_UNKNOWN_FIELD');
    if (node.has('success')) {
      DiscoverMapper.record(collected, sink, new ProtocolDeviation(DeviationCode.SUCCESS_FIELD_IGNORED,
        gatewayId, DiscoverMapper.optionalString(node, 'deviceId'), 'success'));
    }
    const deviceId = DiscoverMapper.requiredString(node, 'deviceId');
    if (deviceId.length === 0 || deviceId.length > ProtocolConstants.MAX_IDENTIFIER_LENGTH_INBOUND ||
      deviceId.indexOf(':') >= 0 || !INBOUND_DEVICE_ID_PATTERN.test(deviceId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'deviceId');
    }
    let partial = false;
    if (deviceId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH) {
      DiscoverMapper.record(collected, sink, new ProtocolDeviation(DeviationCode.OVERSIZE_INBOUND_IDENTIFIER,
        gatewayId, deviceId, 'deviceId'));
    }
    const deviceName = DiscoverMapper.requiredString(node, 'deviceName');
    if (deviceName.length === 0 || deviceName.length > ProtocolConstants.MAX_GATEWAY_NAME_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'deviceName');
    }
    let roomNameHint = '';
    if (!node.has('roomName')) {
      partial = true;
      DiscoverMapper.record(collected, sink, new ProtocolDeviation(DeviationCode.ROOM_NAME_MISSING,
        gatewayId, deviceId, 'roomName'));
    } else {
      const roomNameNode = node.require('roomName');
      if (roomNameNode.kind !== JsonKind.STRING) {
        throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'roomName');
      }
      if (roomNameNode.stringValue.length === 0) {
        partial = true;
        DiscoverMapper.record(collected, sink, new ProtocolDeviation(DeviationCode.ROOM_NAME_MISSING,
          gatewayId, deviceId, 'roomName'));
      } else if (roomNameNode.stringValue.length > ProtocolConstants.MAX_ROOM_NAME_LENGTH) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'roomName');
      } else {
        roomNameHint = roomNameNode.stringValue;
      }
    }
    const deviceTypeRaw = DiscoverMapper.requiredString(node, 'deviceType');
    const deviceType = DiscoverMapper.parseDeviceType(deviceTypeRaw);
    if (deviceType === undefined) {
      partial = true;
      DiscoverMapper.record(collected, sink, new ProtocolDeviation(DeviationCode.UNKNOWN_DEVICE_TYPE,
        gatewayId, deviceId, 'deviceType', deviceTypeRaw));
    }
    let brand: string | undefined = undefined;
    if (node.has('brand')) {
      brand = DiscoverMapper.requiredString(node, 'brand');
      if (brand.length > ProtocolConstants.MAX_BRAND_LENGTH) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'brand');
      }
    }

    const onlineNode = DiscoverMapper.readAliased(node, 'online', 'isOnline', gatewayId, deviceId,
      collected, sink);
    if (onlineNode === undefined) {
      throw AppErrors.protocol('PROTOCOL_MISSING_FIELD', 'online');
    }
    if (onlineNode.kind !== JsonKind.BOOLEAN) {
      throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'online');
    }
    const online = onlineNode.booleanValue;

    const powerNode = DiscoverMapper.readAliased(node, 'power', 'powerStatus', gatewayId, deviceId,
      collected, sink);
    const powerStatus = DiscoverMapper.optionalBooleanNode(powerNode, 'power');
    const openNode = DiscoverMapper.readAliased(node, 'open', 'openStatus', gatewayId, deviceId,
      collected, sink);
    const openStatus = DiscoverMapper.optionalBooleanNode(openNode, 'open');
    const presence = DiscoverMapper.optionalBoolean(node, 'presence');
    const brightness = DiscoverMapper.optionalNumber(node, 'brightness', 0, 100);
    const temperature = DiscoverMapper.optionalNumber(node, 'temperature', -40, 125);
    const humidity = DiscoverMapper.optionalNumber(node, 'humidity', 0, 100);
    const targetNode = DiscoverMapper.readAliased(node, 'targetTemp', 'targetTemperature',
      gatewayId, deviceId, collected, sink);
    const targetTemperature = DiscoverMapper.optionalNumberNode(targetNode, 'targetTemp', 16, 30);

    let color: string | undefined = undefined;
    if (node.has('color')) {
      const colorNode = node.require('color');
      if (colorNode.kind !== JsonKind.STRING) {
        throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'color');
      }
      const rawColor = colorNode.stringValue;
      if (!COLOR_PATTERN.test(rawColor)) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'color');
      }
      color = rawColor.toUpperCase();
      if (rawColor !== color) {
        DiscoverMapper.record(collected, sink, new ProtocolDeviation(DeviationCode.LOWERCASE_COLOR_NORMALIZED,
          gatewayId, deviceId, 'color'));
      }
    }

    let mode: string | undefined = undefined;
    let modeStandard = false;
    if (node.has('mode')) {
      const modeNode = node.require('mode');
      if (modeNode.kind !== JsonKind.STRING) {
        throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'mode');
      }
      mode = modeNode.stringValue;
      if (mode.length > ProtocolConstants.MAX_MODE_LENGTH_INBOUND) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'mode');
      }
      modeStandard = DeviceConstants.isAcMode(mode);
      if (!modeStandard) {
        DiscoverMapper.record(collected, sink, new ProtocolDeviation(DeviationCode.NON_STANDARD_AC_MODE,
          gatewayId, deviceId, 'mode'));
      }
    }

    let stateSource: string | undefined = undefined;
    let stateSourceKnown = false;
    if (node.has('stateSource')) {
      const stateSourceNode = node.require('stateSource');
      if (stateSourceNode.kind !== JsonKind.STRING) {
        throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'stateSource');
      }
      stateSource = stateSourceNode.stringValue;
      if (stateSource.length === 0 || stateSource.length > ProtocolConstants.MAX_ROOM_NAME_LENGTH) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'stateSource');
      }
      stateSourceKnown = DeviceConstants.isStateSource(stateSource);
      if (!stateSourceKnown) {
        DiscoverMapper.record(collected, sink, new ProtocolDeviation(DeviationCode.UNKNOWN_STATE_SOURCE,
          gatewayId, deviceId, 'stateSource'));
      }
    }

    let lastRequestId: string | undefined = undefined;
    if (node.has('lastRequestId')) {
      lastRequestId = DiscoverMapper.requiredString(node, 'lastRequestId');
      if (!ProtocolConstants.REQUEST_ID_PATTERN.test(lastRequestId) ||
        lastRequestId.length > ProtocolConstants.MAX_REQUEST_ID_LENGTH) {
        throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'lastRequestId');
      }
    }
    const lastSeq = DiscoverMapper.optionalInteger(node, 'lastSeq', 0, ProtocolConstants.MAX_SEQ);
    let triggerDeviceId: string | undefined = undefined;
    if (node.has('triggerDeviceId')) {
      triggerDeviceId = DiscoverMapper.requiredString(node, 'triggerDeviceId');
      if (triggerDeviceId.length === 0 ||
        triggerDeviceId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
        triggerDeviceId.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(triggerDeviceId)) {
        throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'triggerDeviceId');
      }
    }
    let automationId: string | undefined = undefined;
    if (node.has('automationId')) {
      automationId = DiscoverMapper.requiredString(node, 'automationId');
      if (automationId.length === 0 ||
        automationId.length > ProtocolConstants.MAX_AUTOMATION_ID_LENGTH) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'automationId');
      }
    }
    const updatedAt = DiscoverMapper.requiredString(node, 'updatedAt');
    DateTimeUtil.parseUtcCompact(updatedAt);

    const init = new DeviceSnapshotInit();
    init.deviceId = deviceId;
    init.deviceName = deviceName;
    init.roomNameHint = roomNameHint;
    init.deviceTypeRaw = deviceTypeRaw;
    init.deviceType = deviceType;
    init.isSupported = deviceType !== undefined && DeviceConstants.isSupported(deviceType);
    init.brand = brand;
    init.isOnline = online;
    init.powerStatus = powerStatus;
    init.openStatus = openStatus;
    init.brightness = brightness;
    init.color = color;
    init.temperature = temperature;
    init.humidity = humidity;
    init.presence = presence;
    init.targetTemperature = targetTemperature;
    init.mode = mode;
    init.modeStandard = modeStandard;
    init.stateSource = stateSource;
    init.stateSourceKnown = stateSourceKnown;
    init.triggerDeviceId = triggerDeviceId;
    init.automationId = automationId;
    init.lastRequestId = lastRequestId;
    init.lastSeq = lastSeq;
    init.updatedAt = updatedAt;
    if (DiscoverMapper.hasDeviation(collected, deviceId, DeviationCode.ALIAS_FIELD_USED)) {
      partial = true;
    }
    const snapshot = DeviceSnapshot.create(init);
    return new MappedDevice(snapshot, partial);
  }

  private static readAliased(node: JsonNode, canonical: string, alias: string, gatewayId: string,
    deviceId: string, collected: ProtocolDeviation[], sink: ProtocolDeviationSink): JsonNode | undefined {
    if (node.has(canonical)) {
      const canonicalNode = node.require(canonical);
      if (node.has(alias)) {
        const aliasNode = node.require(alias);
        if (!DiscoverMapper.samePrimitive(canonicalNode, aliasNode)) {
          DiscoverMapper.record(collected, sink, new ProtocolDeviation(DeviationCode.ALIAS_CONFLICT,
            gatewayId, deviceId, canonical, alias));
        }
      }
      return canonicalNode;
    }
    if (node.has(alias)) {
      DiscoverMapper.record(collected, sink, new ProtocolDeviation(DeviationCode.ALIAS_FIELD_USED,
        gatewayId, deviceId, canonical, alias));
      return node.require(alias);
    }
    return undefined;
  }

  private static optionalBooleanNode(node: JsonNode | undefined, field: string): boolean | undefined {
    if (node === undefined) {
      return undefined;
    }
    if (node.kind !== JsonKind.BOOLEAN) {
      throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', field);
    }
    return node.booleanValue;
  }

  private static optionalNumberNode(node: JsonNode | undefined, field: string, min: number,
    max: number): number | undefined {
    if (node === undefined) {
      return undefined;
    }
    if (node.kind !== JsonKind.NUMBER || !Number.isFinite(node.numberValue) ||
      node.numberValue < min || node.numberValue > max) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', field);
    }
    return node.numberValue;
  }

  private static optionalBoolean(node: JsonNode, field: string): boolean | undefined {
    if (!node.has(field)) {
      return undefined;
    }
    const value = node.require(field);
    if (value.kind !== JsonKind.BOOLEAN) {
      throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', field);
    }
    return value.booleanValue;
  }

  private static optionalNumber(node: JsonNode, field: string, min: number, max: number): number | undefined {
    if (!node.has(field)) {
      return undefined;
    }
    const value = node.require(field);
    if (value.kind !== JsonKind.NUMBER || !Number.isFinite(value.numberValue) ||
      value.numberValue < min || value.numberValue > max) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', field);
    }
    return value.numberValue;
  }

  private static optionalInteger(node: JsonNode, field: string, min: number, max: number): number | undefined {
    if (!node.has(field)) {
      return undefined;
    }
    const value = node.require(field);
    if (value.kind !== JsonKind.NUMBER || !Number.isInteger(value.numberValue) ||
      value.numberValue < min || value.numberValue > max) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', field);
    }
    return value.numberValue;
  }

  private static requiredString(node: JsonNode, field: string): string {
    const value = node.require(field);
    if (value.kind !== JsonKind.STRING) {
      throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', field);
    }
    return value.stringValue;
  }

  private static requiredInteger(node: JsonNode, field: string): number {
    const value = node.require(field);
    if (value.kind !== JsonKind.NUMBER || !Number.isInteger(value.numberValue)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', field);
    }
    return value.numberValue;
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

  private static rejectUnknownFields(node: JsonNode, allowed: ReadonlyArray<string>, code: string): void {
    const keys = node.keys();
    for (let index = 0; index < keys.length; index++) {
      if (allowed.indexOf(keys[index]) < 0) {
        throw AppErrors.protocol(code, keys[index]);
      }
    }
  }

  private static parseDeviceType(value: string): DeviceType | undefined {
    for (let index = 0; index < DeviceConstants.SUPPORTED_TYPES.length; index++) {
      if (DeviceConstants.SUPPORTED_TYPES[index] === value) {
        return DeviceConstants.SUPPORTED_TYPES[index];
      }
    }
    for (let index = 0; index < DeviceConstants.READ_ONLY_TYPES.length; index++) {
      if (DeviceConstants.READ_ONLY_TYPES[index] === value) {
        return DeviceConstants.READ_ONLY_TYPES[index];
      }
    }
    return undefined;
  }

  private static validateGatewayId(value: string): void {
    if (value.length === 0 || value.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      value.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(value)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'gatewayId');
    }
  }

  private static optionalDeviceIdForDiagnostics(node: JsonNode): string | undefined {
    if (node.kind !== JsonKind.OBJECT) {
      return undefined;
    }
    return DiscoverMapper.optionalString(node, 'deviceId');
  }

  private static hasDeviation(collected: ProtocolDeviation[], deviceId: string,
    code: DeviationCode): boolean {
    for (let index = 0; index < collected.length; index++) {
      const deviation = collected[index];
      if (deviation.code === code && deviation.deviceId === deviceId) {
        return true;
      }
    }
    return false;
  }

  private static samePrimitive(first: JsonNode, second: JsonNode): boolean {
    if (first.kind !== second.kind) {
      return false;
    }
    if (first.kind === JsonKind.BOOLEAN) {
      return first.booleanValue === second.booleanValue;
    }
    if (first.kind === JsonKind.NUMBER) {
      return first.numberValue === second.numberValue;
    }
    if (first.kind === JsonKind.STRING) {
      return first.stringValue === second.stringValue;
    }
    return true;
  }

  private static record(collected: ProtocolDeviation[], sink: ProtocolDeviationSink,
    deviation: ProtocolDeviation): void {
    collected.push(deviation);
    sink.record(deviation);
  }

  private static errorReason(error: Object): string {
    if (error instanceof AppError) {
      return error.code;
    }
    return 'DEVICE_INVALID';
  }
}

class MappedDevice {
  readonly snapshot: DeviceSnapshot;
  readonly partial: boolean;

  constructor(snapshot: DeviceSnapshot, partial: boolean) {
    this.snapshot = snapshot;
    this.partial = partial;
  }
}
