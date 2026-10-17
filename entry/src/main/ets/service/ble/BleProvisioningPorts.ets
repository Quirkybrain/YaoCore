/*
 * YaoCore C-19 BLE provisioning ports and public contract types.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Contract: DES-A §16.1 (API), §16.1.3 (transport), §16.9 (state/cleanup);
 *           BLE设计 §2-§7; project-constraints PR-12/PR-13/SC-06.
 *
 * Port-only declarations plus immutable value objects. No @ohos/@kit import:
 * this file is consumed by host tests and by the pure C-19 service. The
 * platform BLE adapter lives under adapters/OhosBleTransport.ets and is the
 * only production file that may import @ohos.bluetooth.*.
 *
 * T-11 shipped a deliberately minimal surface (`BleScanDevice`,
 * `BleProvisioningStage`, byte-buffer request). T-12 extends it to the full
 * DES-A §16.1 shape. The byte-buffer Wi-Fi password/PoP is retained instead of
 * the DES-A sketch's `string` so callers can zeroize the secret in place
 * (SC-06); `BleProvisioningRequest` never turns them into an immutable string.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';
import { Utf8 } from '../../common/utils/Utf8';
import type { BleProvisioningIdentity, BleProvisioningResult } from '../../model/ProvisioningModels';
import type { CancellationToken } from '../../common/types/Ports';

/** Main provisioning state machine (DES-A §16.9; BLE设计 §7-161-165). */
export enum ProvisioningState {
  IDLE = 'IDLE',
  PERMISSION = 'PERMISSION',
  SCANNING = 'SCANNING',
  CONNECTING = 'CONNECTING',
  DISCOVERING = 'DISCOVERING',
  CAPABILITY_CHECK = 'CAPABILITY_CHECK',
  SECURITY_HANDSHAKE = 'SECURITY_HANDSHAKE',
  SECURE_IDENTITY = 'SECURE_IDENTITY',
  AP_SCANNING = 'AP_SCANNING',
  SENDING_CREDENTIALS = 'SENDING_CREDENTIALS',
  WAITING_FOR_WIFI = 'WAITING_FOR_WIFI',
  DISCOVERING_ON_LAN = 'DISCOVERING_ON_LAN',
  BOUND = 'BOUND',
  FAILED = 'FAILED',
  CANCELLED = 'CANCELLED'
}

/** Coarse progress stages retained for the T-11 listener surface. */
export enum BleProvisioningStage {
  CONNECTING = 'CONNECTING',
  SECURITY = 'SECURITY',
  IDENTITY = 'IDENTITY',
  WIFI_SCAN = 'WIFI_SCAN',
  WIFI_APPLY = 'WIFI_APPLY',
  WIFI_STATUS = 'WIFI_STATUS',
  DONE = 'DONE',
  BINDING_PROBE = 'BINDING_PROBE'
}

export class BleProvisioningDevice {
  readonly deviceId: string;
  readonly name: string;
  readonly rssi: number;
  readonly serviceUuids: ReadonlyArray<string>;

  constructor(deviceId: string, name: string, rssi: number,
    serviceUuids: ReadonlyArray<string> = []) {
    if (deviceId.length === 0 || !Number.isFinite(rssi) ||
      rssi < -127 || rssi > 20) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.deviceId = deviceId;
    this.name = name;
    this.rssi = rssi;
    this.serviceUuids = serviceUuids;
  }
}

/** Backwards-compatible T-11 name; same value object. */
export class BleScanDevice extends BleProvisioningDevice {
}

export class BleScanFilter {
  readonly serviceUuid: string;
  readonly namePrefix?: string;
  readonly timeoutMs: number;

  constructor(serviceUuid: string, namePrefix?: string, timeoutMs: number = 10000) {
    if (serviceUuid.length === 0 || !Number.isInteger(timeoutMs) || timeoutMs <= 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.serviceUuid = serviceUuid;
    this.namePrefix = namePrefix;
    this.timeoutMs = timeoutMs;
  }
}

export interface BleScanListener {
  onDeviceFound(device: BleProvisioningDevice): void;
  onScanFinished(): void;
  onScanError(error: AppError): void;
}

export class WifiAp {
  readonly ssid: string;
  readonly bssid: string;
  readonly channel: number;
  readonly rssi: number;
  readonly auth: number;

  constructor(ssid: string, bssid: string, channel: number, rssi: number, auth: number) {
    if (ssid.length === 0 || !Number.isInteger(channel) || channel < 0 || channel > 196 ||
      !Number.isFinite(rssi) || !Number.isInteger(auth) || auth < 0 || auth > 7) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'wifiAp');
    }
    this.ssid = ssid;
    this.bssid = bssid;
    this.channel = channel;
    this.rssi = rssi;
    this.auth = auth;
  }
}

/** Progress event (DES-A §16.1.1). messageKey is an i18n key, never text. */
export class ProvisioningProgress {
  readonly state: ProvisioningState;
  readonly messageKey?: string;
  readonly apList?: ReadonlyArray<WifiAp>;
  readonly identity?: BleProvisioningIdentity;
  readonly error?: AppError;

  constructor(state: ProvisioningState, messageKey?: string, apList?: ReadonlyArray<WifiAp>,
    identity?: BleProvisioningIdentity, error?: AppError) {
    this.state = state;
    this.messageKey = messageKey;
    this.apList = apList;
    this.identity = identity;
    this.error = error;
  }
}

/**
 * Listener contract. `onStage` is the T-11-compatible coarse progress hook;
 * the DES-A §16.1 callbacks are optional so small consumers (and the mock)
 * only opt into what they render. The service never logs secrets here.
 */
export interface BleProvisioningProgressListener {
  onStage(stage: BleProvisioningStage): void;
  onStateChanged?(progress: ProvisioningProgress): void;
  onAccessPoints?(aps: ReadonlyArray<WifiAp>): void;
  onError?(error: AppError): void;
  onCompleted?(result: BleProvisioningResult): void;
}

/**
 * Provisioning request. Wi-Fi password and PoP are byte buffers only; the
 * caller owns them and must clear them after the call (SC-06). The service
 * copies them for the active flow and zeroizes its copies in every exit path.
 * `device` selects the already-discovered gateway; when omitted, provision()
 * falls back to the unique device discovered by the last scan.
 */
export class BleProvisioningRequest {
  readonly ssid: string;
  readonly wifiPassword: Uint8Array;
  readonly pop: Uint8Array;
  readonly device?: BleProvisioningDevice;
  readonly credentialDraftId?: string;
  readonly familyId: string;
  readonly expectedGatewayId?: string;

  constructor(ssid: string, wifiPassword: Uint8Array, pop: Uint8Array,
    device?: BleProvisioningDevice, credentialDraftId?: string,
    familyId: string = '', expectedGatewayId?: string) {
    let ssidBytes: Uint8Array;
    try {
      ssidBytes = Utf8.encode(ssid);
    } catch (error) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'ssid');
    }
    if (ssidBytes.length === 0 || ssidBytes.length > 32) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'ssid');
    }
    if (wifiPassword.length > 64) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'wifiPassword');
    }
    if (pop.length === 0 || pop.length > 64) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'pop');
    }
    if (familyId.length > 63) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'familyId');
    }
    if (credentialDraftId !== undefined &&
      (credentialDraftId.length === 0 || credentialDraftId.length > 128)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'credentialDraftId');
    }
    if (expectedGatewayId !== undefined) {
      if (expectedGatewayId.length === 0 ||
        expectedGatewayId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
        expectedGatewayId.indexOf(':') >= 0 ||
        !ProtocolConstants.DEVICE_ID_PATTERN.test(expectedGatewayId)) {
        throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'expectedGatewayId');
      }
    }
    this.ssid = ssid;
    this.wifiPassword = wifiPassword;
    this.pop = pop;
    this.device = device;
    this.credentialDraftId = credentialDraftId;
    this.familyId = familyId;
    this.expectedGatewayId = expectedGatewayId;
  }
}

export interface IBleProvisioningClient {
  startScan(filter: BleScanFilter, listener: BleScanListener): Promise<void>;
  stopScan(): Promise<void>;
  provision(request: BleProvisioningRequest,
    listener: BleProvisioningProgressListener,
    cancellation?: CancellationToken): Promise<BleProvisioningResult>;
  cancel(): Promise<void>;
}

// ---- BLE transport port (DES-A §16.1.3, BLE设计 §2) -----------------------

export class BleServiceRef {
  readonly uuid: string;

  constructor(uuid: string) {
    if (uuid.length === 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.uuid = uuid;
  }
}

export class BleCharacteristicRef {
  readonly serviceUuid: string;
  readonly characteristicUuid: string;
  readonly canRead: boolean;
  readonly canWrite: boolean;
  readonly canWriteNoResponse: boolean;

  constructor(serviceUuid: string, characteristicUuid: string, canRead: boolean,
    canWrite: boolean, canWriteNoResponse: boolean) {
    if (serviceUuid.length === 0 || characteristicUuid.length === 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.serviceUuid = serviceUuid;
    this.characteristicUuid = characteristicUuid;
    this.canRead = canRead;
    this.canWrite = canWrite;
    this.canWriteNoResponse = canWriteNoResponse;
  }
}

export class BleDescriptorRef {
  readonly serviceUuid: string;
  readonly characteristicUuid: string;
  readonly descriptorUuid: string;

  constructor(serviceUuid: string, characteristicUuid: string, descriptorUuid: string) {
    if (serviceUuid.length === 0 || characteristicUuid.length === 0 ||
      descriptorUuid.length === 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.serviceUuid = serviceUuid;
    this.characteristicUuid = characteristicUuid;
    this.descriptorUuid = descriptorUuid;
  }
}

/**
 * One GATT link. Implementations serialize writes/reads internally; the
 * service additionally serializes each write->read pair through
 * GattRequestQueue (PR-12). All methods reject with AppError.
 */
export interface BleConnection {
  requestMtu(target: number): Promise<number>;
  discoverServices(serviceUuid: string): Promise<ReadonlyArray<BleServiceRef>>;
  discoverCharacteristics(serviceUuid: string): Promise<ReadonlyArray<BleCharacteristicRef>>;
  readDescriptor(descriptor: BleDescriptorRef): Promise<Uint8Array>;
  writeCharacteristic(characteristic: BleCharacteristicRef, value: Uint8Array): Promise<void>;
  readCharacteristic(characteristic: BleCharacteristicRef): Promise<Uint8Array>;
  disconnect(): Promise<void>;
}

export interface BleTransport {
  ensurePermission(): Promise<void>;
  isBluetoothEnabled(): Promise<boolean>;
  startScan(filter: BleScanFilter, listener: BleScanListener): Promise<void>;
  stopScan(): Promise<void>;
  connect(deviceId: string, cancellation?: CancellationToken): Promise<BleConnection>;
}

/**
 * Permission seam used by the production adapter. T-17 owns module.json5;
 * this interface only reserves the runtime check the SDK requires.
 */
export interface BlePermissionGate {
  ensurePermission(): Promise<void>;
}
