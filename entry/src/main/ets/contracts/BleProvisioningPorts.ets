/*
 * YaoCore C-19 BLE provisioning ports.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-A §27.6.3 P1/P2.
 * Contract: DES-A §16.1 (API), §16.1.3 (transport), §16.9 (state/cleanup);
 *           BLE设计 §2-§7; project-constraints PR-12/PR-13/SC-06.
 *
 * Port-only declarations. DTO/enums live in model/ProvisioningModels.ets; the
 * platform BLE adapter lives under adapters/OhosBleTransport.ets and is the
 * only production file that may import @ohos.bluetooth.*.
 */
import { AppError } from '../common/types/AppError';
import type {
  BleCharacteristicRef,
  BleDescriptorRef,
  BleProvisioningDevice,
  BleProvisioningRequest,
  BleProvisioningStage,
  BleProvisioningResult,
  BleScanFilter,
  BleServiceRef,
  BleWifiScanRequest,
  ProvisioningProgress,
  ProvisioningState,
  WifiAp
} from '../model/ProvisioningModels';
import type { CancellationToken } from '../common/types/CancellationToken';

export interface BleScanListener {
  onDeviceFound(device: BleProvisioningDevice): void;
  onScanFinished(): void;
  onScanError(error: AppError): void;
}

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

export interface IBleProvisioningClient {
  startScan(filter: BleScanFilter, listener: BleScanListener): Promise<void>;
  stopScan(): Promise<void>;
  provision(request: BleProvisioningRequest,
    listener: BleProvisioningProgressListener,
    cancellation?: CancellationToken): Promise<BleProvisioningResult>;
  /**
   * F-07 additive seam: connect, Security1 handshake and identity negotiation,
   * then return the Wi-Fi AP list for the wizard's step 3. The call tears the
   * BLE link down; provision() still owns the authoritative aggregated flow.
   */
  scanWifiAccessPoints(request: BleWifiScanRequest,
    listener: BleProvisioningProgressListener,
    cancellation?: CancellationToken): Promise<ReadonlyArray<WifiAp>>;
  cancel(): Promise<void>;
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
