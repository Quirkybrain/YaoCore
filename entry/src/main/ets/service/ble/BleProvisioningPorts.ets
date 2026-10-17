/*
 * YaoCore C-19 BLE provisioning ports (minimal T-11 surface for C-20 Mock).
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §16.1 (interface shape), §17.1; C-19/T-12 extends
 *
 * Port-only declarations. T-12 owns the real C-19 implementation and may extend
 * these types without changing the Mock contract. No @ohos import.
 */
import { AppErrors } from '../../common/types/AppError';
import { BleProvisioningResult } from '../../model/ProvisioningModels';
import type { CancellationToken } from '../../common/types/Ports';

export class BleScanDevice {
  readonly deviceId: string;
  readonly name: string;
  readonly rssi: number;

  constructor(deviceId: string, name: string, rssi: number) {
    if (deviceId.length === 0 || name.length === 0 || !Number.isFinite(rssi)) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.deviceId = deviceId;
    this.name = name;
    this.rssi = rssi;
  }
}

export class BleScanFilter {
  readonly namePrefix?: string;

  constructor(namePrefix?: string) {
    this.namePrefix = namePrefix;
  }
}

export interface BleScanListener {
  onDeviceFound(device: BleScanDevice): void;
  onScanFinished(): void;
}

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

export interface BleProvisioningProgressListener {
  onStage(stage: BleProvisioningStage): void;
}

/**
 * Provisioning request. Wi-Fi password and PoP are byte buffers only; callers
 * must clear them after the call (SC-06). This port never logs them.
 */
export class BleProvisioningRequest {
  readonly ssid: string;
  readonly wifiPassword: Uint8Array;
  readonly pop: Uint8Array;

  constructor(ssid: string, wifiPassword: Uint8Array, pop: Uint8Array) {
    if (ssid.length === 0 || ssid.length > 32) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'ssid');
    }
    if (wifiPassword.length === 0 || pop.length === 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.ssid = ssid;
    this.wifiPassword = wifiPassword;
    this.pop = pop;
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
