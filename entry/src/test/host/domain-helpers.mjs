/*
 * YaoCore T-09 host test helpers.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 *
 * PUBLIC TEST DATA ONLY. Builds DES-A/DES-B value objects without touching
 * platform code.
 */
import { DeviceSnapshot, DeviceSnapshotInit, DeviceStatePatch, DeviceStatePatchInit } from '../../main/ets/model/DeviceState';
import { DeviceType, DeviceAction, DeviceConstants } from '../../main/ets/common/constants/DeviceConstants';
import { DiscoverySnapshot, DiscoverySnapshotInit } from '../../main/ets/model/DiscoveryModels';
import { ControlOutcome, ControlOutcomeInit, DeviceControlCommand, GatewayBoardState, StateVerification } from '../../main/ets/model/ControlModels';
import { SceneAction } from '../../main/ets/model/FamilyModels';
import { GatewayResultClassifier } from '../../main/ets/common/types/GatewayResult';

export const FAMILY_ID = 'family-1';
export const GATEWAY_ID = 'gw-1';
export const T0 = '20261017T080000Z';
export const T1 = '20261017T080001Z';
export const T2 = '20261017T080002Z';
export const T3 = '20261017T080003Z';

export function snapshotDevice(deviceId, options = {}) {
  const init = new DeviceSnapshotInit();
  init.deviceId = deviceId;
  init.deviceName = options.deviceName === undefined ? deviceId : options.deviceName;
  init.roomNameHint = options.roomNameHint === undefined ? '' : options.roomNameHint;
  init.deviceTypeRaw = options.deviceTypeRaw === undefined ? 'light' : options.deviceTypeRaw;
  init.deviceType = options.deviceType === undefined ? DeviceType.LIGHT : options.deviceType;
  init.isSupported = init.deviceType !== undefined && DeviceConstants.isSupported(init.deviceType);
  if (options.isSupported !== undefined) {
    init.isSupported = options.isSupported;
  }
  init.brand = options.brand;
  init.isOnline = options.isOnline === undefined ? true : options.isOnline;
  init.powerStatus = options.powerStatus;
  init.openStatus = options.openStatus;
  init.brightness = options.brightness;
  init.color = options.color;
  init.temperature = options.temperature;
  init.humidity = options.humidity;
  init.presence = options.presence;
  init.targetTemperature = options.targetTemperature;
  init.mode = options.mode;
  init.modeStandard = options.modeStandard === undefined ? false : options.modeStandard;
  init.stateSource = options.stateSource;
  init.stateSourceKnown = options.stateSourceKnown === undefined ? false : options.stateSourceKnown;
  init.triggerDeviceId = options.triggerDeviceId;
  init.automationId = options.automationId;
  init.lastRequestId = options.lastRequestId;
  init.lastSeq = options.lastSeq;
  init.updatedAt = options.updatedAt === undefined ? T0 : options.updatedAt;
  return DeviceSnapshot.create(init);
}

export function unknownTypeSnapshot(deviceId, updatedAt = T0) {
  const init = new DeviceSnapshotInit();
  init.deviceId = deviceId;
  init.deviceName = deviceId;
  init.deviceTypeRaw = 'hologram';
  init.deviceType = undefined;
  init.isSupported = false;
  init.isOnline = true;
  init.updatedAt = updatedAt;
  return DeviceSnapshot.create(init);
}

export function discovery(devices, options = {}) {
  const init = new DiscoverySnapshotInit();
  init.gatewayId = options.gatewayId === undefined ? GATEWAY_ID : options.gatewayId;
  init.gatewayName = options.gatewayName === undefined ? 'Test Gateway' : options.gatewayName;
  init.devices = devices;
  init.isPartial = options.isPartial === undefined ? false : options.isPartial;
  init.aliasUsed = options.aliasUsed === undefined ? false : options.aliasUsed;
  init.generatedAt = options.generatedAt === undefined ? T0 : options.generatedAt;
  return DiscoverySnapshot.create(init);
}

export function patch(deviceId, updatedAt, fields = {}) {
  const init = new DeviceStatePatchInit();
  init.deviceId = deviceId;
  init.isOnline = fields.isOnline === undefined ? true : fields.isOnline;
  init.powerStatus = fields.powerStatus;
  init.openStatus = fields.openStatus;
  init.brightness = fields.brightness;
  init.color = fields.color;
  init.targetTemperature = fields.targetTemperature;
  init.mode = fields.mode;
  init.modeStandard = fields.modeStandard === undefined ? false : fields.modeStandard;
  init.stateSource = fields.stateSource;
  init.stateSourceKnown = fields.stateSourceKnown === undefined ? false : fields.stateSourceKnown;
  init.updatedAt = updatedAt;
  return DeviceStatePatch.create(init);
}

export function acceptedOutcome(target, gatewayId = GATEWAY_ID, options = {}) {
  const init = new ControlOutcomeInit();
  init.requestId = options.requestId === undefined ? 'req-1700000000000-1' :
    options.requestId;
  init.seq = options.seq === undefined ? 1 : options.seq;
  init.resultCode = 0;
  init.ackAccepted = true;
  init.idempotentReplay = options.idempotentReplay === undefined ? false :
    options.idempotentReplay;
  init.gatewayBoardState = new GatewayBoardState(gatewayId, true, false, T0);
  init.stateVerification = options.verification === undefined ? StateVerification.UNVERIFIED :
    options.verification;
  init.gatewayResult = GatewayResultClassifier.classify(0);
  init.shouldApplyState = false;
  return ControlOutcome.create(init);
}

export function rejectedOutcome(target, gatewayId = GATEWAY_ID) {
  const init = new ControlOutcomeInit();
  init.requestId = 'req-1700000000000-9';
  init.seq = 9;
  init.resultCode = 1007;
  init.ackAccepted = false;
  init.gatewayResult = GatewayResultClassifier.classify(1007);
  init.stateVerification = StateVerification.UNVERIFIED;
  init.shouldApplyState = false;
  return ControlOutcome.create(init);
}

export function stateOutcome(target, gatewayId = GATEWAY_ID, options = {}) {
  const init = new ControlOutcomeInit();
  init.requestId = options.requestId === undefined ? 'req-1700000000000-2' :
    options.requestId;
  init.seq = options.seq === undefined ? 2 : options.seq;
  init.resultCode = 0;
  init.ackAccepted = true;
  init.idempotentReplay = options.idempotentReplay === undefined ? false :
    options.idempotentReplay;
  init.reportedState = patch(options.deviceId === undefined ? target : options.deviceId,
    options.updatedAt === undefined ? T1 : options.updatedAt, options.fields);
  init.stateVerification = options.verification === undefined ? StateVerification.MATCH :
    options.verification;
  init.gatewayResult = GatewayResultClassifier.classify(0);
  init.shouldApplyState = true;
  return ControlOutcome.create(init);
}

export function command(gatewayId, target, action, requestedAtMs = 1700000000000, value) {
  return new DeviceControlCommand(gatewayId, target, action, requestedAtMs, value);
}

export function sceneAction(gatewayId, targetDeviceId, action, value, delayMs) {
  return new SceneAction(gatewayId, targetDeviceId, action, value, delayMs);
}

export function expectCode(error, code) {
  if (error === undefined || error === null) {
    throw new Error('expected AppError ' + code + ', got no error');
  }
  if (error.code !== code) {
    throw new Error('expected ' + code + ', got ' + String(error.code));
  }
  return true;
}
