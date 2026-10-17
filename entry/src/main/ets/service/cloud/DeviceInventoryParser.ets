/*
 * YaoCore C-15 DeviceInventoryJson parser (PB-02, fail-closed).
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §8.1.6, §8.4; CB §7.1; SR L47-51
 *
 * DeviceInventoryJson's internal schema is not frozen. This parser accepts
 * only the documented candidate fields with strict types/limits. Missing
 * completion carriers, duplicate IDs, unknown root structure, oversize input
 * or invalid values raise CLOUD_INVENTORY_UNSUPPORTED. It never invents a
 * completion signal.
 *
 * PUBLIC TEST DATA ONLY for all fixtures; no real firmware interoperability is
 * claimed (PB-02 remains a firmware coordination item).
 */
import { AppError } from '../../common/types/AppError';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';
import { JsonKind, JsonNode } from '../../common/types/JsonNode';
import { JsonParser, JsonLimits } from '../../common/utils/JsonParser';
import { Utf8 } from '../../common/utils/Utf8';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import {
  DeviceInventoryLimits
} from './CloudModels';
import { CloudErrors } from './CloudErrors';
import { InventoryDeviceState } from '../../model/CloudModels';

const ALLOWED_FIELDS: ReadonlyArray<string> = [
  'device_id', 'online', 'power', 'open', 'brightness', 'color', 'temperature',
  'humidity', 'presence', 'target_temperature', 'mode', 'state_source',
  'trigger_device_id', 'automation_id', 'event_time', 'last_request_id', 'last_seq'
];
const COLOR_PATTERN: RegExp = /^#[0-9A-F]{6}$/;

export class DeviceInventoryParser {
  /**
   * Strict parse of the candidate PB-02 array. `deviations` optionally
   * receives ignored unknown field names for diagnostics (not fatal).
   */
  static parse(jsonText: string, limits: DeviceInventoryLimits = DeviceInventoryLimits.defaults(),
    deviations?: string[]): ReadonlyArray<InventoryDeviceState> {
    if (jsonText.length > limits.maxBytes) {
      throw CloudErrors.inventoryUnsupported('DeviceInventoryJson.length');
    }
    try {
      if (Utf8.encode(jsonText).length > limits.maxBytes) {
        throw CloudErrors.inventoryUnsupported('DeviceInventoryJson.bytes');
      }
    } catch (error) {
      if (error instanceof AppError) {
        throw CloudErrors.inventoryUnsupported('DeviceInventoryJson.encoding');
      }
      throw CloudErrors.inventoryUnsupported('DeviceInventoryJson.encoding');
    }
    let root: JsonNode = JsonNode.nullNode();
    try {
      root = JsonParser.parse(jsonText, new JsonLimits(limits.maxBytes, 16, 8192));
    } catch (error) {
      throw CloudErrors.inventoryUnsupported('DeviceInventoryJson.json');
    }
    if (root.kind !== JsonKind.ARRAY) {
      throw CloudErrors.inventoryUnsupported('DeviceInventoryJson.root');
    }
    if (root.arrayValue.length > limits.maxEntries) {
      throw CloudErrors.inventoryUnsupported('DeviceInventoryJson.entries');
    }
    const entries: InventoryDeviceState[] = [];
    const seen: Map<string, boolean> = new Map<string, boolean>();
    for (let index = 0; index < root.arrayValue.length; index++) {
      const entry = root.arrayValue[index];
      if (entry.kind !== JsonKind.OBJECT) {
        throw CloudErrors.inventoryUnsupported('entry');
      }
      DeviceInventoryParser.recordUnknownFields(entry, deviations);
      const deviceId = DeviceInventoryParser.requiredString(entry, 'device_id');
      if (deviceId.length === 0 || deviceId.length > limits.maxDeviceIdLength ||
        deviceId.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(deviceId)) {
        throw CloudErrors.inventoryUnsupported('device_id');
      }
      if (seen.has(deviceId)) {
        throw CloudErrors.inventoryUnsupported('device_id.duplicate');
      }
      seen.set(deviceId, true);
      const lastRequestId = DeviceInventoryParser.requiredString(entry, 'last_request_id');
      if (!ProtocolConstants.REQUEST_ID_PATTERN.test(lastRequestId) ||
        lastRequestId.length > ProtocolConstants.MAX_REQUEST_ID_LENGTH) {
        throw CloudErrors.inventoryUnsupported('last_request_id');
      }
      const lastSeq = DeviceInventoryParser.requiredInteger(entry, 'last_seq',
        0, ProtocolConstants.MAX_SEQ);
      const eventTime = DeviceInventoryParser.requiredString(entry, 'event_time');
      try {
        DateTimeUtil.parseUtcCompact(eventTime);
      } catch (error) {
        throw CloudErrors.inventoryUnsupported('event_time');
      }
      const online = DeviceInventoryParser.optionalBoolean(entry, 'online');
      const power = DeviceInventoryParser.optionalBoolean(entry, 'power');
      const open = DeviceInventoryParser.optionalBoolean(entry, 'open');
      const presence = DeviceInventoryParser.optionalBoolean(entry, 'presence');
      const brightness = DeviceInventoryParser.optionalNumber(entry, 'brightness', 0, 100);
      const temperature = DeviceInventoryParser.optionalNumber(entry, 'temperature', -40, 125);
      const humidity = DeviceInventoryParser.optionalNumber(entry, 'humidity', 0, 100);
      const targetTemperature = DeviceInventoryParser.optionalNumber(entry,
        'target_temperature', 16, 30);
      let color: string | undefined = undefined;
      const rawColor = DeviceInventoryParser.optionalString(entry, 'color');
      if (rawColor !== undefined) {
        color = rawColor.toUpperCase();
        if (!COLOR_PATTERN.test(color)) {
          throw CloudErrors.inventoryUnsupported('color');
        }
      }
      const mode = DeviceInventoryParser.optionalString(entry, 'mode');
      if (mode !== undefined && (mode.length === 0 ||
        mode.length > ProtocolConstants.MAX_MODE_LENGTH_INBOUND)) {
        throw CloudErrors.inventoryUnsupported('mode');
      }
      const stateSource = DeviceInventoryParser.optionalString(entry, 'state_source');
      if (stateSource !== undefined && (stateSource.length === 0 ||
        stateSource.length > ProtocolConstants.MAX_ROOM_NAME_LENGTH)) {
        throw CloudErrors.inventoryUnsupported('state_source');
      }
      const triggerDeviceId = DeviceInventoryParser.optionalString(entry, 'trigger_device_id');
      if (triggerDeviceId !== undefined) {
        if (triggerDeviceId.length === 0 ||
          triggerDeviceId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
          triggerDeviceId.indexOf(':') >= 0 ||
          !ProtocolConstants.DEVICE_ID_PATTERN.test(triggerDeviceId)) {
          throw CloudErrors.inventoryUnsupported('trigger_device_id');
        }
      }
      const automationId = DeviceInventoryParser.optionalString(entry, 'automation_id');
      if (automationId !== undefined && (automationId.length === 0 ||
        automationId.length > ProtocolConstants.MAX_AUTOMATION_ID_LENGTH)) {
        throw CloudErrors.inventoryUnsupported('automation_id');
      }
      entries.push(new InventoryDeviceState(deviceId, online, power, open, brightness, color,
        temperature, humidity, presence, targetTemperature, mode, stateSource, triggerDeviceId,
        automationId, eventTime, lastRequestId, lastSeq));
    }
    return entries;
  }

  private static recordUnknownFields(entry: JsonNode, deviations?: string[]): void {
    if (deviations === undefined) {
      return;
    }
    const keys = entry.keys();
    for (let index = 0; index < keys.length; index++) {
      if (ALLOWED_FIELDS.indexOf(keys[index]) < 0) {
        deviations.push(keys[index]);
      }
    }
  }

  private static requiredString(entry: JsonNode, field: string): string {
    if (!entry.has(field)) {
      throw CloudErrors.inventoryUnsupported(field);
    }
    const value = entry.require(field);
    if (value.kind !== JsonKind.STRING) {
      throw CloudErrors.inventoryUnsupported(field);
    }
    return value.stringValue;
  }

  private static optionalString(entry: JsonNode, field: string): string | undefined {
    if (!entry.has(field)) {
      return undefined;
    }
    const value = entry.require(field);
    if (value.kind !== JsonKind.STRING) {
      throw CloudErrors.inventoryUnsupported(field);
    }
    return value.stringValue;
  }

  private static optionalBoolean(entry: JsonNode, field: string): boolean | undefined {
    if (!entry.has(field)) {
      return undefined;
    }
    const value = entry.require(field);
    if (value.kind !== JsonKind.BOOLEAN) {
      throw CloudErrors.inventoryUnsupported(field);
    }
    return value.booleanValue;
  }

  private static optionalNumber(entry: JsonNode, field: string, min: number,
    max: number): number | undefined {
    if (!entry.has(field)) {
      return undefined;
    }
    const value = entry.require(field);
    if (value.kind !== JsonKind.NUMBER || !Number.isFinite(value.numberValue) ||
      value.numberValue < min || value.numberValue > max) {
      throw CloudErrors.inventoryUnsupported(field);
    }
    return value.numberValue;
  }

  private static requiredInteger(entry: JsonNode, field: string, min: number,
    max: number): number {
    if (!entry.has(field)) {
      throw CloudErrors.inventoryUnsupported(field);
    }
    const value = entry.require(field);
    if (value.kind !== JsonKind.NUMBER || !Number.isInteger(value.numberValue) ||
      value.numberValue < min || value.numberValue > max) {
      throw CloudErrors.inventoryUnsupported(field);
    }
    return value.numberValue;
  }
}
