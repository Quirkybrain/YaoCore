/*
 * YaoCore C-15 cloud completion evaluator.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §8.1.6, §8.3.3, §8.4; PR-10; D-014
 *
 * IoTDA acceptance is never completion. Only a fresh shadow whose
 * LastRequestId AND LastSeq both match the expectation (fixed built-in path)
 * or the same pair in DeviceInventoryJson (PB-02 candidate path) may produce
 * CONFIRMED. Missing/unknown inventory structure is UNSUPPORTED, never
 * CONFIRMED. Reserved fixed names never use inventory: `Gateway` and the
 * read-only sensors are always UNSUPPORTED (F-04 ruling).
 */
import { AppErrors } from '../../common/types/AppError';
import type { ClockPort } from '../../common/types/Ports';
import { DeviceAction, DeviceConstants } from '../../common/constants/DeviceConstants';
import type { CommandValue } from '../../common/utils/JsonAtom';
import { DeviceStatePatch, DeviceStatePatchInit } from '../../model/DeviceState';
import { StateVerification } from '../../model/ControlModels';
import type { InventoryDeviceState, ShadowDeviceState } from '../../model/CloudModels';
import {
  CloudCommandExpectation,
  CloudCompletion,
  CloudCompletionPolicy,
  CloudCompletionVerdict,
  ShadowSnapshot
} from './CloudModels';
import { CloudErrors } from './CloudErrors';

const FIXED_PREFIXES: ReadonlyArray<string> = ['Door_01', 'Light_01', 'AC_01'];
const READ_ONLY_FIXED: ReadonlyArray<string> = ['Sensor_01', 'Presence_01'];
/** v1 reserved fixed-name registry (DES-B §8.1.6; F-04 ruling). */
const NON_INVENTORY_FIXED: ReadonlyArray<string> = [
  'Gateway', 'Door_01', 'Light_01', 'AC_01', 'Sensor_01', 'Presence_01'
];
const FUTURE_TOLERANCE_MS: number = 300000;

export class CloudCompletionEvaluator {
  private readonly clock: ClockPort;
  private readonly policy: CloudCompletionPolicy;

  constructor(clock: ClockPort, policy: CloudCompletionPolicy = CloudCompletionPolicy.defaults()) {
    this.clock = clock;
    this.policy = policy;
  }

  evaluate(expectation: CloudCommandExpectation,
    shadow: ShadowSnapshot): CloudCompletionVerdict {
    const nowMs = this.clock.nowMs();
    if (shadow.eventEpochMs > nowMs + FUTURE_TOLERANCE_MS) {
      return new CloudCompletionVerdict(CloudCompletion.INVALID, StateVerification.UNVERIFIED,
        'SHADOW_CLOCK_SKEW', undefined, undefined, shadow.eventTime, undefined,
        CloudErrors.shadowInvalid('event_time'));
    }
    if (shadow.eventEpochMs + this.policy.freshnessToleranceMs < expectation.notBeforeMs) {
      return new CloudCompletionVerdict(CloudCompletion.STALE, StateVerification.UNVERIFIED,
        'STALE_SHADOW', undefined, undefined, shadow.eventTime);
    }
    const target = expectation.targetDeviceId;
    const prefix = CloudCompletionEvaluator.fixedPrefix(target);
    if (prefix !== undefined) {
      return this.evaluateFixed(expectation, shadow, prefix);
    }
    if (READ_ONLY_FIXED.indexOf(target) >= 0) {
      return new CloudCompletionVerdict(CloudCompletion.UNSUPPORTED,
        StateVerification.UNVERIFIED, 'READ_ONLY_SENSOR', undefined, undefined,
        shadow.eventTime, undefined,
        AppErrors.of('CLOUD_COMPLETION_UNSUPPORTED', []));
    }
    if (target === 'Gateway') {
      // Gateway_Online/Gateway_RSSI are gateway status, not a command receipt.
      // Even a matching DeviceInventoryJson entry must never confirm it.
      return new CloudCompletionVerdict(CloudCompletion.UNSUPPORTED,
        StateVerification.UNVERIFIED, 'GATEWAY_NOT_SUPPORTED', undefined, undefined,
        shadow.eventTime, undefined,
        AppErrors.of('CLOUD_COMPLETION_UNSUPPORTED', []));
    }
    if (NON_INVENTORY_FIXED.indexOf(target) >= 0) {
      // Reserved fixed names never route through inventory (F-04). Any future
      // registry entry without an explicit carrier therefore fails closed.
      return new CloudCompletionVerdict(CloudCompletion.UNSUPPORTED,
        StateVerification.UNVERIFIED, 'FIXED_DEVICE_UNSUPPORTED', undefined, undefined,
        shadow.eventTime, undefined,
        AppErrors.of('CLOUD_COMPLETION_UNSUPPORTED', []));
    }
    return this.evaluateInventory(expectation, shadow);
  }

  private evaluateFixed(expectation: CloudCommandExpectation, shadow: ShadowSnapshot,
    prefix: string): CloudCompletionVerdict {
    let state: ShadowDeviceState | undefined = undefined;
    for (let index = 0; index < shadow.fixedDevices.length; index++) {
      if (shadow.fixedDevices[index].deviceId === expectation.targetDeviceId) {
        state = shadow.fixedDevices[index];
        break;
      }
    }
    if (state === undefined) {
      return new CloudCompletionVerdict(CloudCompletion.PENDING, StateVerification.UNVERIFIED,
        'AWAITING_STATE', undefined, undefined, shadow.eventTime);
    }
    const requestMatched = state.lastRequestId === expectation.requestId;
    const seqMatched = state.lastSeq === expectation.seq;
    const fresh = state.eventEpochMs + this.policy.freshnessToleranceMs >=
      expectation.notBeforeMs;
    const patch = CloudCompletionEvaluator.fixedPatch(state);
    if (requestMatched && seqMatched && fresh) {
      return new CloudCompletionVerdict(CloudCompletion.CONFIRMED,
        CloudCompletionEvaluator.verify(expectation.action, expectation.requestedValue, patch),
        'CONFIRMED_FIXED', expectation.requestId, expectation.seq, state.eventTime, patch);
    }
    let reason = 'AWAITING_COMMAND_ACK';
    if (requestMatched && !seqMatched) {
      reason = 'REQUEST_ID_MATCHED';
    } else if (!requestMatched && seqMatched) {
      reason = 'SEQ_MATCHED';
    } else if (requestMatched && seqMatched && !fresh) {
      reason = 'AWAITING_FRESH_STATE';
    }
    return new CloudCompletionVerdict(CloudCompletion.PENDING, StateVerification.UNVERIFIED,
      reason + ':' + prefix, undefined, undefined, state.eventTime, patch);
  }

  private evaluateInventory(expectation: CloudCommandExpectation,
    shadow: ShadowSnapshot): CloudCompletionVerdict {
    if (shadow.inventoryUnsupported) {
      const error = shadow.inventoryError === undefined ?
        CloudErrors.inventoryUnsupported('DeviceInventoryJson') : shadow.inventoryError;
      return new CloudCompletionVerdict(CloudCompletion.UNSUPPORTED,
        StateVerification.UNVERIFIED, 'PB02_INVENTORY_UNSUPPORTED', undefined, undefined,
        shadow.eventTime, undefined, error);
    }
    let entry: InventoryDeviceState | undefined = undefined;
    for (let index = 0; index < shadow.deviceInventory.length; index++) {
      if (shadow.deviceInventory[index].deviceId === expectation.targetDeviceId) {
        entry = shadow.deviceInventory[index];
        break;
      }
    }
    if (entry === undefined) {
      return new CloudCompletionVerdict(CloudCompletion.UNSUPPORTED,
        StateVerification.UNVERIFIED, 'INVENTORY_ENTRY_MISSING', undefined, undefined,
        shadow.eventTime, undefined,
        CloudErrors.inventoryUnsupported('device_id'));
    }
    if (entry.lastRequestId === undefined || entry.lastSeq === undefined ||
      entry.eventTime === undefined) {
      return new CloudCompletionVerdict(CloudCompletion.UNSUPPORTED,
        StateVerification.UNVERIFIED, 'INVENTORY_CARRIER_MISSING', undefined, undefined,
        shadow.eventTime, undefined,
        CloudErrors.inventoryUnsupported('last_request_id'));
    }
    const entryEpochMs = CloudCompletionEvaluator.parseQuietly(entry.eventTime);
    if (entryEpochMs > this.clock.nowMs() + FUTURE_TOLERANCE_MS) {
      return new CloudCompletionVerdict(CloudCompletion.INVALID,
        StateVerification.UNVERIFIED, 'INVENTORY_CLOCK_SKEW', undefined, undefined,
        entry.eventTime, undefined, CloudErrors.shadowInvalid('inventory.event_time'));
    }
    const fresh = entryEpochMs + this.policy.freshnessToleranceMs >= expectation.notBeforeMs;
    const patch = CloudCompletionEvaluator.inventoryPatch(entry);
    if (entry.lastRequestId === expectation.requestId && entry.lastSeq === expectation.seq &&
      fresh) {
      return new CloudCompletionVerdict(CloudCompletion.CONFIRMED,
        CloudCompletionEvaluator.verify(expectation.action, expectation.requestedValue, patch),
        'CONFIRMED_INVENTORY', expectation.requestId, expectation.seq, entry.eventTime, patch);
    }
    return new CloudCompletionVerdict(CloudCompletion.PENDING, StateVerification.UNVERIFIED,
      'AWAITING_INVENTORY_ACK', undefined, undefined, entry.eventTime, patch);
  }

  private static fixedPrefix(deviceId: string): string | undefined {
    for (let index = 0; index < FIXED_PREFIXES.length; index++) {
      if (FIXED_PREFIXES[index] === deviceId) {
        return FIXED_PREFIXES[index];
      }
    }
    return undefined;
  }

  private static fixedPatch(state: ShadowDeviceState): DeviceStatePatch {
    const init = new DeviceStatePatchInit();
    init.deviceId = state.deviceId;
    init.isOnline = state.online === true;
    init.powerStatus = state.power;
    init.openStatus = state.open;
    init.brightness = state.brightness;
    init.color = state.color;
    init.temperature = state.temperature;
    init.humidity = state.humidity;
    init.presence = state.presence;
    init.targetTemperature = state.targetTemperature;
    init.mode = state.mode;
    init.modeStandard = state.modeStandard;
    init.stateSource = state.stateSource;
    init.stateSourceKnown = state.stateSourceKnown;
    init.triggerDeviceId = state.triggerDeviceId;
    init.automationId = state.automationId;
    init.lastRequestId = state.lastRequestId;
    init.lastSeq = state.lastSeq;
    init.updatedAt = state.eventTime;
    return DeviceStatePatch.create(init);
  }

  private static inventoryPatch(entry: InventoryDeviceState): DeviceStatePatch {
    const init = new DeviceStatePatchInit();
    init.deviceId = entry.deviceId;
    init.isOnline = entry.online === true;
    init.powerStatus = entry.power;
    init.openStatus = entry.open;
    init.brightness = entry.brightness;
    init.color = entry.color;
    init.temperature = entry.temperature;
    init.humidity = entry.humidity;
    init.presence = entry.presence;
    init.targetTemperature = entry.targetTemperature;
    init.mode = entry.mode;
    init.modeStandard = entry.mode !== undefined && DeviceConstants.isAcMode(entry.mode);
    init.stateSource = entry.stateSource;
    init.stateSourceKnown = entry.stateSource !== undefined &&
      DeviceConstants.isStateSource(entry.stateSource);
    init.triggerDeviceId = entry.triggerDeviceId;
    init.automationId = entry.automationId;
    init.lastRequestId = entry.lastRequestId;
    init.lastSeq = entry.lastSeq;
    init.updatedAt = entry.eventTime === undefined ? '19700101T000000Z' : entry.eventTime;
    return DeviceStatePatch.create(init);
  }

  private static verify(action: DeviceAction, value: CommandValue | undefined,
    patch: DeviceStatePatch): StateVerification {
    if (action === DeviceAction.OPEN || action === DeviceAction.CLOSE) {
      const expected = action === DeviceAction.OPEN;
      if (patch.openStatus === undefined) {
        return StateVerification.UNVERIFIED;
      }
      return patch.openStatus === expected ? StateVerification.MATCH :
        StateVerification.MISMATCH;
    }
    if (action === DeviceAction.TURN_ON || action === DeviceAction.TURN_OFF) {
      const expected = action === DeviceAction.TURN_ON;
      if (patch.powerStatus === undefined) {
        return StateVerification.UNVERIFIED;
      }
      return patch.powerStatus === expected ? StateVerification.MATCH :
        StateVerification.MISMATCH;
    }
    if (action === DeviceAction.SET_BRIGHTNESS) {
      if (typeof value !== 'number' || !Number.isFinite(value) ||
        patch.brightness === undefined) {
        return StateVerification.UNVERIFIED;
      }
      return patch.brightness === value ? StateVerification.MATCH :
        StateVerification.MISMATCH;
    }
    if (action === DeviceAction.SET_TARGET_TEMPERATURE) {
      if (typeof value !== 'number' || !Number.isFinite(value) ||
        patch.targetTemperature === undefined) {
        return StateVerification.UNVERIFIED;
      }
      return patch.targetTemperature === value ? StateVerification.MATCH :
        StateVerification.MISMATCH;
    }
    if (action === DeviceAction.SET_MODE) {
      if (typeof value !== 'string' || !DeviceConstants.isAcMode(value) ||
        patch.mode === undefined) {
        return StateVerification.UNVERIFIED;
      }
      return patch.mode === value ? StateVerification.MATCH :
        StateVerification.MISMATCH;
    }
    // Cloud SR has no color property and no other v1 completion field.
    return StateVerification.UNVERIFIED;
  }

  private static parseQuietly(compact: string): number {
    try {
      // Date parsing is delegated to the shared strict UTC helper elsewhere;
      // the inventory parser already accepted this value.
      const year = Number.parseInt(compact.substring(0, 4), 10);
      const month = Number.parseInt(compact.substring(4, 6), 10);
      const day = Number.parseInt(compact.substring(6, 8), 10);
      const hour = Number.parseInt(compact.substring(9, 11), 10);
      const minute = Number.parseInt(compact.substring(11, 13), 10);
      const second = Number.parseInt(compact.substring(13, 15), 10);
      return Date.UTC(year, month - 1, day, hour, minute, second);
    } catch (error) {
      return 0;
    }
  }
}
