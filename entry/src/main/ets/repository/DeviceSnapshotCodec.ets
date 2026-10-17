/*
 * YaoCore C-10 DeviceSnapshot canonical persistence codec.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §2.7 (`device_state.snapshot_json`), §5.3.2/§5.3.3
 *
 * Fixed field order, no whitespace, no undefined members. The encoded text is
 * also the identity comparison used by the same-epoch arbitration rule.
 */
import { AppError, AppErrors } from '../common/types/AppError';
import { DeviceType } from '../common/constants/DeviceConstants';
import { JsonKind } from '../common/types/JsonNode';
import type { JsonNode } from '../common/types/JsonNode';
import { JsonParser, JsonLimits } from '../common/utils/JsonParser';
import { JsonAtom } from '../common/utils/JsonAtom';
import { DeviceSnapshot } from '../model/DeviceState';
import { DeviceSnapshotInit } from '../model/DeviceState';

export class DeviceSnapshotCodec {
  static encode(snapshot: DeviceSnapshot): string {
    let text = '{';
    text += '"deviceId":' + JsonAtom.normalizeString(snapshot.deviceId);
    text += ',"deviceName":' + JsonAtom.normalizeString(snapshot.deviceName);
    text += ',"roomNameHint":' + JsonAtom.normalizeString(snapshot.roomNameHint);
    text += ',"deviceTypeRaw":' + JsonAtom.normalizeString(snapshot.deviceTypeRaw);
    if (snapshot.deviceType !== undefined) {
      text += ',"deviceType":' + JsonAtom.normalizeString(snapshot.deviceType);
    }
    text += ',"isSupported":' + (snapshot.isSupported ? 'true' : 'false');
    if (snapshot.brand !== undefined) {
      text += ',"brand":' + JsonAtom.normalizeString(snapshot.brand);
    }
    text += ',"isOnline":' + (snapshot.isOnline ? 'true' : 'false');
    if (snapshot.powerStatus !== undefined) {
      text += ',"powerStatus":' + (snapshot.powerStatus ? 'true' : 'false');
    }
    if (snapshot.openStatus !== undefined) {
      text += ',"openStatus":' + (snapshot.openStatus ? 'true' : 'false');
    }
    if (snapshot.brightness !== undefined) {
      text += ',"brightness":' + String(snapshot.brightness);
    }
    if (snapshot.color !== undefined) {
      text += ',"color":' + JsonAtom.normalizeString(snapshot.color);
    }
    if (snapshot.temperature !== undefined) {
      text += ',"temperature":' + String(snapshot.temperature);
    }
    if (snapshot.humidity !== undefined) {
      text += ',"humidity":' + String(snapshot.humidity);
    }
    if (snapshot.presence !== undefined) {
      text += ',"presence":' + (snapshot.presence ? 'true' : 'false');
    }
    if (snapshot.targetTemperature !== undefined) {
      text += ',"targetTemperature":' + String(snapshot.targetTemperature);
    }
    if (snapshot.mode !== undefined) {
      text += ',"mode":' + JsonAtom.normalizeString(snapshot.mode);
    }
    text += ',"modeStandard":' + (snapshot.modeStandard ? 'true' : 'false');
    if (snapshot.stateSource !== undefined) {
      text += ',"stateSource":' + JsonAtom.normalizeString(snapshot.stateSource);
    }
    text += ',"stateSourceKnown":' + (snapshot.stateSourceKnown ? 'true' : 'false');
    if (snapshot.triggerDeviceId !== undefined) {
      text += ',"triggerDeviceId":' + JsonAtom.normalizeString(snapshot.triggerDeviceId);
    }
    if (snapshot.automationId !== undefined) {
      text += ',"automationId":' + JsonAtom.normalizeString(snapshot.automationId);
    }
    if (snapshot.lastRequestId !== undefined) {
      text += ',"lastRequestId":' + JsonAtom.normalizeString(snapshot.lastRequestId);
    }
    if (snapshot.lastSeq !== undefined) {
      text += ',"lastSeq":' + String(snapshot.lastSeq);
    }
    text += ',"updatedAt":' + JsonAtom.normalizeString(snapshot.updatedAt);
    return text + '}';
  }

  static decode(text: string): DeviceSnapshot {
    let root: JsonNode;
    try {
      root = JsonParser.parse(text, new JsonLimits(65536, 8, 8192));
    } catch (error) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    if (root.kind !== JsonKind.OBJECT) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    try {
      const init = new DeviceSnapshotInit();
      init.deviceId = DeviceSnapshotCodec.requiredString(root, 'deviceId');
      init.deviceName = DeviceSnapshotCodec.requiredString(root, 'deviceName');
      init.roomNameHint = DeviceSnapshotCodec.requiredString(root, 'roomNameHint');
      init.deviceTypeRaw = DeviceSnapshotCodec.requiredString(root, 'deviceTypeRaw');
      init.deviceType = DeviceSnapshotCodec.parseDeviceType(
        DeviceSnapshotCodec.optionalString(root, 'deviceType'));
      init.isSupported = DeviceSnapshotCodec.requiredBoolean(root, 'isSupported');
      init.brand = DeviceSnapshotCodec.optionalString(root, 'brand');
      init.isOnline = DeviceSnapshotCodec.requiredBoolean(root, 'isOnline');
      init.powerStatus = DeviceSnapshotCodec.optionalBoolean(root, 'powerStatus');
      init.openStatus = DeviceSnapshotCodec.optionalBoolean(root, 'openStatus');
      init.brightness = DeviceSnapshotCodec.optionalNumber(root, 'brightness');
      init.color = DeviceSnapshotCodec.optionalString(root, 'color');
      init.temperature = DeviceSnapshotCodec.optionalNumber(root, 'temperature');
      init.humidity = DeviceSnapshotCodec.optionalNumber(root, 'humidity');
      init.presence = DeviceSnapshotCodec.optionalBoolean(root, 'presence');
      init.targetTemperature = DeviceSnapshotCodec.optionalNumber(root, 'targetTemperature');
      init.mode = DeviceSnapshotCodec.optionalString(root, 'mode');
      init.modeStandard = DeviceSnapshotCodec.requiredBoolean(root, 'modeStandard');
      init.stateSource = DeviceSnapshotCodec.optionalString(root, 'stateSource');
      init.stateSourceKnown = DeviceSnapshotCodec.requiredBoolean(root, 'stateSourceKnown');
      init.triggerDeviceId = DeviceSnapshotCodec.optionalString(root, 'triggerDeviceId');
      init.automationId = DeviceSnapshotCodec.optionalString(root, 'automationId');
      init.lastRequestId = DeviceSnapshotCodec.optionalString(root, 'lastRequestId');
      init.lastSeq = DeviceSnapshotCodec.optionalNumber(root, 'lastSeq');
      init.updatedAt = DeviceSnapshotCodec.requiredString(root, 'updatedAt');
      return DeviceSnapshot.create(init);
    } catch (error) {
      if (error instanceof AppError && error.code.startsWith('STORAGE_')) {
        throw error;
      }
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
  }

  private static requiredString(root: JsonNode, key: string): string {
    const node = root.get(key);
    if (node === undefined || node.kind !== JsonKind.STRING) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    return node.stringValue;
  }

  private static optionalString(root: JsonNode, key: string): string | undefined {
    const node = root.get(key);
    if (node === undefined || node.kind === JsonKind.NULL) {
      return undefined;
    }
    if (node.kind !== JsonKind.STRING) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    return node.stringValue;
  }

  private static requiredBoolean(root: JsonNode, key: string): boolean {
    const node = root.get(key);
    if (node === undefined || node.kind !== JsonKind.BOOLEAN) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    return node.booleanValue;
  }

  private static optionalBoolean(root: JsonNode, key: string): boolean | undefined {
    const node = root.get(key);
    if (node === undefined || node.kind === JsonKind.NULL) {
      return undefined;
    }
    if (node.kind !== JsonKind.BOOLEAN) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    return node.booleanValue;
  }

  private static optionalNumber(root: JsonNode, key: string): number | undefined {
    const node = root.get(key);
    if (node === undefined || node.kind === JsonKind.NULL) {
      return undefined;
    }
    if (node.kind !== JsonKind.NUMBER) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    return node.numberValue;
  }

  private static parseDeviceType(value: string | undefined): DeviceType | undefined {
    if (value === undefined) {
      return undefined;
    }
    if (value === DeviceType.DOOR) {
      return DeviceType.DOOR;
    }
    if (value === DeviceType.LIGHT) {
      return DeviceType.LIGHT;
    }
    if (value === DeviceType.SENSOR) {
      return DeviceType.SENSOR;
    }
    if (value === DeviceType.AC) {
      return DeviceType.AC;
    }
    if (value === DeviceType.SWITCH) {
      return DeviceType.SWITCH;
    }
    if (value === DeviceType.CAMERA) {
      return DeviceType.CAMERA;
    }
    if (value === DeviceType.CURTAIN) {
      return DeviceType.CURTAIN;
    }
    if (value === DeviceType.FAN) {
      return DeviceType.FAN;
    }
    if (value === DeviceType.SPEAKER) {
      return DeviceType.SPEAKER;
    }
    return undefined;
  }
}
