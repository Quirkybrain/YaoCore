/*
 * YaoCore C-19 production BLE transport adapter.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Contract: DES-A §16.1.3, §16.2; BLE设计 §2-§4; TEST-001 CP-03
 *
 * COMPILED_ONLY (no device/radio in this environment). This is the only
 * production file that imports @ohos.bluetooth.*. It maps platform types to
 * the pure BleTransport port, maps BusinessError codes to AppError, and never
 * interprets provisioning semantics. Write errors are special: only
 * 2900011/2901004 are confirmed busy and safe to resend; every other write
 * failure maps to a non-GATT_BUSY code (REV-T12-002 R2-01).
 *
 * Runtime permission: ohos.permission.ACCESS_BLUETOOTH is requested through
 * the injected UIAbility context. module.json5 declaration is owned by T-17
 * (this task must not edit module.json5); until then the runtime request will
 * be rejected by the platform and must be reported as a T-17 dependency.
 */
import { access, ble, constant } from '@kit.ConnectivityKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppError, AppErrors } from '../../../common/types/AppError';
import { NameValue } from '../../../common/types/NameValue';
import type { CancellationToken } from '../../../common/types/Ports';
import { confirmedWriteBusy } from '../BleSupport';
import {
  BleCharacteristicRef,
  BleConnection,
  BleDescriptorRef,
  BlePermissionGate,
  BleProvisioningDevice,
  BleScanFilter,
  BleScanListener,
  BleServiceRef,
  BleTransport
} from '../BleProvisioningPorts';

const ACCESS_BLUETOOTH: Permissions = 'ohos.permission.ACCESS_BLUETOOTH';
const CONNECT_TIMEOUT_MS: number = 12000;
const MTU_TIMEOUT_MS: number = 12000;
const CODE_PERMISSION_DENIED: number = 201;
const CODE_BLUETOOTH_DISABLED: number = 2900003;
const CODE_GATT_BUSY: number = 2900011;
const CODE_CONNECTION_CONGESTED: number = 2901004;
const CODE_CONNECTION_NOT_ESTABLISHED: number = 2901003;
const CODE_READ_FORBIDDEN: number = 2901000;

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const buffer = new ArrayBuffer(bytes.length);
  const view = new Uint8Array(buffer);
  for (let index = 0; index < bytes.length; index++) {
    view[index] = bytes[index];
  }
  return buffer;
}

function businessCode(error: Error): number {
  const business = error as BusinessError;
  return typeof business.code === 'number' ? business.code : -1;
}

function mapBleError(error: Error, fallbackCode: string): AppError {
  const business = error as BusinessError;
  if (typeof business.code !== 'number') {
    return AppErrors.of(fallbackCode, []);
  }
  const code = business.code;
  if (code === CODE_PERMISSION_DENIED) {
    return AppErrors.of('PROVISIONING_PERMISSION_DENIED', []);
  }
  if (code === CODE_BLUETOOTH_DISABLED) {
    return AppErrors.of('PROVISIONING_BLUETOOTH_OFF', []);
  }
  if (code === CODE_GATT_BUSY || code === CODE_CONNECTION_CONGESTED) {
    return AppErrors.of('PROVISIONING_GATT_BUSY', []);
  }
  if (code === CODE_CONNECTION_NOT_ESTABLISHED) {
    return AppErrors.of('PROVISIONING_CONNECT_FAILED', []);
  }
  if (code === CODE_READ_FORBIDDEN) {
    return AppErrors.of('PROVISIONING_GATT_INCOMPLETE', []);
  }
  return AppErrors.of(fallbackCode, [new NameValue('field', 'ble:' + String(code))]);
}

/**
 * Maps a write failure. Only an explicit GATT busy / connection-congested
 * rejection confirms that the write was not accepted and may be resent.
 * 2900099 Operation failed, 2900001, 2901005..2901007 and missing/unknown
 * codes are ambiguous and map to a non-GATT_BUSY code so the channel never
 * resends the same frame (REV-T12-002 R2-01).
 */
function mapWriteError(error: Error): AppError {
  const business = error as BusinessError;
  if (typeof business.code === 'number' &&
    (business.code === CODE_GATT_BUSY || business.code === CODE_CONNECTION_CONGESTED)) {
    return confirmedWriteBusy();
  }
  return mapBleError(error, 'PROVISIONING_GATT_INCOMPLETE');
}

/** Runtime permission gate; module.json5 declaration is T-17. */
export class OhosBlePermissionGate implements BlePermissionGate {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async ensurePermission(): Promise<void> {
    try {
      const manager = abilityAccessCtrl.createAtManager();
      const result = await manager.requestPermissionsFromUser(this.context, [ACCESS_BLUETOOTH]);
      if (result.authResults.length === 0 || result.authResults[0] !== 0) {
        throw AppErrors.of('PROVISIONING_PERMISSION_DENIED', []);
      }
    } catch (error) {
      if (error instanceof Object && typeof (error as BusinessError).code === 'number') {
        throw mapBleError(error as Error, 'PROVISIONING_PERMISSION_DENIED');
      }
      throw AppErrors.of('PROVISIONING_PERMISSION_DENIED', []);
    }
  }
}

export class OhosBleTransport implements BleTransport {
  private readonly permissionGate: BlePermissionGate;
  private scanCallback: ((results: Array<ble.ScanResult>) => void) | undefined = undefined;

  constructor(permissionGate: BlePermissionGate) {
    this.permissionGate = permissionGate;
  }

  async ensurePermission(): Promise<void> {
    await this.permissionGate.ensurePermission();
  }

  async isBluetoothEnabled(): Promise<boolean> {
    try {
      return access.getState() === access.BluetoothState.STATE_ON;
    } catch (error) {
      throw mapBleError(error as Error, 'PROVISIONING_BLUETOOTH_OFF');
    }
  }

  async startScan(filter: BleScanFilter, listener: BleScanListener): Promise<void> {
    this.stopScanCallback();
    const scanFilter: ble.ScanFilter = {
      serviceUuid: filter.serviceUuid
    };
    const callback = (results: Array<ble.ScanResult>): void => {
      for (let index = 0; index < results.length; index++) {
        const result = results[index];
        if (!this.matchesService(result, filter.serviceUuid)) {
          continue;
        }
        listener.onDeviceFound(new BleProvisioningDevice(result.deviceId, result.deviceName,
          result.rssi, [filter.serviceUuid]));
      }
    };
    this.scanCallback = callback;
    try {
      ble.on('BLEDeviceFind', callback);
      ble.startBLEScan([scanFilter], {
        dutyMode: ble.ScanDuty.SCAN_MODE_LOW_LATENCY,
        matchMode: ble.MatchMode.MATCH_MODE_AGGRESSIVE
      });
    } catch (error) {
      this.stopScanCallback();
      throw mapBleError(error as Error, 'PROVISIONING_CONNECT_FAILED');
    }
  }

  async stopScan(): Promise<void> {
    this.stopScanCallback();
    try {
      ble.stopBLEScan();
    } catch (error) {
      // A stopped/absent scan is not an error for cleanup.
    }
  }

  async connect(deviceId: string, cancellation?: CancellationToken): Promise<BleConnection> {
    let client: ble.GattClientDevice;
    try {
      client = ble.createGattClientDevice(deviceId);
    } catch (error) {
      throw mapBleError(error as Error, 'PROVISIONING_CONNECT_FAILED');
    }
    await new Promise<void>((resolve, reject) => {
      let settled = false;
      let timer: number = 0;
      const cleanup = (): void => {
        if (timer !== 0) {
          clearTimeout(timer);
          timer = 0;
        }
        try {
          client.off('BLEConnectionStateChange', onConnection);
        } catch (error) {
          // Listener may not have been registered.
        }
      };
      const settle = (error: AppError | undefined): void => {
        if (settled) {
          return;
        }
        settled = true;
        cleanup();
        if (error === undefined) {
          resolve();
        } else {
          try {
            client.close();
          } catch (closeError) {
            // Best-effort cleanup after a failed connection.
          }
          reject(error);
        }
      };
      const onConnection = (change: ble.BLEConnectionChangeState): void => {
        if (change.deviceId !== deviceId) {
          return;
        }
        if (change.state === constant.ProfileConnectionState.STATE_CONNECTED) {
          settle(undefined);
        } else if (change.state === constant.ProfileConnectionState.STATE_DISCONNECTED) {
          settle(AppErrors.of('PROVISIONING_CONNECT_FAILED', []));
        }
      };
      try {
        client.on('BLEConnectionStateChange', onConnection);
        if (cancellation !== undefined) {
          cancellation.onCancel((): void => {
            settle(AppErrors.of('PROVISIONING_CANCELLED', []));
          });
        }
        timer = setTimeout((): void => {
          settle(AppErrors.of('PROVISIONING_CONNECT_FAILED', []));
        }, CONNECT_TIMEOUT_MS);
        client.connect();
      } catch (error) {
        settle(mapBleError(error as Error, 'PROVISIONING_CONNECT_FAILED'));
      }
    });
    return new OhosBleConnection(client);
  }

  private matchesService(result: ble.ScanResult, serviceUuid: string): boolean {
    if (result.serviceUuids === undefined) {
      return true;
    }
    const expected = serviceUuid.toLowerCase();
    for (let index = 0; index < result.serviceUuids.length; index++) {
      if (result.serviceUuids[index].toLowerCase() === expected) {
        return true;
      }
    }
    return false;
  }

  private stopScanCallback(): void {
    if (this.scanCallback !== undefined) {
      try {
        ble.off('BLEDeviceFind', this.scanCallback);
      } catch (error) {
        // Idempotent unsubscribe.
      }
      this.scanCallback = undefined;
    }
  }
}

class OhosBleConnection implements BleConnection {
  private readonly client: ble.GattClientDevice;
  private readonly characteristics: Map<string, ble.BLECharacteristic> =
    new Map<string, ble.BLECharacteristic>();
  private disconnected: boolean = false;

  constructor(client: ble.GattClientDevice) {
    this.client = client;
  }

  async requestMtu(target: number): Promise<number> {
    return await new Promise<number>((resolve, reject) => {
      let settled = false;
      let timer: number = 0;
      const cleanup = (): void => {
        if (timer !== 0) {
          clearTimeout(timer);
          timer = 0;
        }
        try {
          this.client.off('BLEMtuChange', onMtu);
        } catch (error) {
          // Listener may not have been registered.
        }
      };
      const settle = (mtu: number, error: AppError | undefined): void => {
        if (settled) {
          return;
        }
        settled = true;
        cleanup();
        if (error === undefined) {
          resolve(mtu);
        } else {
          reject(error);
        }
      };
      const onMtu = (mtu: number): void => {
        settle(mtu, undefined);
      };
      try {
        this.client.on('BLEMtuChange', onMtu);
        timer = setTimeout((): void => {
          settle(0, AppErrors.of('PROVISIONING_CONNECT_FAILED',
            [new NameValue('field', 'mtu')]));
        }, MTU_TIMEOUT_MS);
        this.client.setBLEMtuSize(target);
      } catch (error) {
        settle(0, mapBleError(error as Error, 'PROVISIONING_CONNECT_FAILED'));
      }
    });
  }

  async discoverServices(serviceUuid: string): Promise<ReadonlyArray<BleServiceRef>> {
    try {
      const services = await this.client.getServices();
      const result: BleServiceRef[] = [];
      const expected = serviceUuid.toLowerCase();
      for (let index = 0; index < services.length; index++) {
        if (services[index].serviceUuid.toLowerCase() === expected) {
          result.push(new BleServiceRef(services[index].serviceUuid));
        }
      }
      return result;
    } catch (error) {
      throw mapBleError(error as Error, 'PROVISIONING_GATT_INCOMPLETE');
    }
  }

  async discoverCharacteristics(serviceUuid: string): Promise<ReadonlyArray<BleCharacteristicRef>> {
    try {
      const services = await this.client.getServices();
      const expected = serviceUuid.toLowerCase();
      for (let index = 0; index < services.length; index++) {
        const service = services[index];
        if (service.serviceUuid.toLowerCase() !== expected) {
          continue;
        }
        const result: BleCharacteristicRef[] = [];
        for (let charIndex = 0; charIndex < service.characteristics.length; charIndex++) {
          const characteristic = service.characteristics[charIndex];
          this.characteristics.set(
            service.serviceUuid + '|' + characteristic.characteristicUuid, characteristic);
          const properties = characteristic.properties;
          const canRead = properties !== undefined && properties.read === true;
          const canWrite = properties !== undefined && properties.write === true;
          const canWriteNoResponse = properties !== undefined &&
            properties.writeNoResponse === true;
          result.push(new BleCharacteristicRef(service.serviceUuid,
            characteristic.characteristicUuid, canRead, canWrite, canWriteNoResponse));
        }
        return result;
      }
      throw AppErrors.of('PROVISIONING_GATT_INCOMPLETE', [new NameValue('field', 'service')]);
    } catch (error) {
      const business = error as BusinessError;
      if (typeof business.code === 'number') {
        throw mapBleError(error as Error, 'PROVISIONING_GATT_INCOMPLETE');
      }
      if (error instanceof AppError) {
        throw error;
      }
      throw AppErrors.of('PROVISIONING_GATT_INCOMPLETE', []);
    }
  }

  async readDescriptor(descriptor: BleDescriptorRef): Promise<Uint8Array> {
    const characteristic = this.findCharacteristic(descriptor);
    let target: ble.BLEDescriptor | undefined = undefined;
    if (characteristic !== undefined && characteristic.descriptors !== undefined) {
      for (let index = 0; index < characteristic.descriptors.length; index++) {
        if (characteristic.descriptors[index].descriptorUuid.toLowerCase() ===
          descriptor.descriptorUuid.toLowerCase()) {
          target = characteristic.descriptors[index];
          break;
        }
      }
    }
    if (target === undefined) {
      target = {
        serviceUuid: descriptor.serviceUuid,
        characteristicUuid: descriptor.characteristicUuid,
        descriptorUuid: descriptor.descriptorUuid,
        descriptorValue: new ArrayBuffer(0)
      };
    }
    try {
      const result = await this.client.readDescriptorValue(target);
      return new Uint8Array(result.descriptorValue);
    } catch (error) {
      throw mapBleError(error as Error, 'PROVISIONING_GATT_INCOMPLETE');
    }
  }

  async writeCharacteristic(characteristic: BleCharacteristicRef,
    value: Uint8Array): Promise<void> {
    const target = this.buildCharacteristic(characteristic, value);
    try {
      await this.client.writeCharacteristicValue(target, ble.GattWriteType.WRITE);
    } catch (error) {
      throw mapWriteError(error as Error);
    }
  }

  async readCharacteristic(characteristic: BleCharacteristicRef): Promise<Uint8Array> {
    const target = this.buildCharacteristic(characteristic, new Uint8Array(0));
    try {
      const result = await this.client.readCharacteristicValue(target);
      return new Uint8Array(result.characteristicValue);
    } catch (error) {
      throw mapBleError(error as Error, 'PROVISIONING_GATT_BUSY');
    }
  }

  async disconnect(): Promise<void> {
    if (this.disconnected) {
      return;
    }
    this.disconnected = true;
    this.characteristics.clear();
    try {
      this.client.disconnect();
    } catch (error) {
      // Link may already be gone.
    }
    try {
      this.client.close();
    } catch (error) {
      // Closing twice is harmless.
    }
  }

  private findCharacteristic(reference: BleDescriptorRef | BleCharacteristicRef):
    ble.BLECharacteristic | undefined {
    const key = reference.serviceUuid + '|' + reference.characteristicUuid;
    return this.characteristics.get(key);
  }

  private buildCharacteristic(reference: BleCharacteristicRef,
    value: Uint8Array): ble.BLECharacteristic {
    const discovered = this.characteristics.get(
      reference.serviceUuid + '|' + reference.characteristicUuid);
    const descriptors: Array<ble.BLEDescriptor> = discovered === undefined ||
      discovered.descriptors === undefined ? [] : discovered.descriptors;
    const properties: ble.GattProperties | undefined = discovered === undefined ?
      undefined : discovered.properties;
    return {
      serviceUuid: reference.serviceUuid,
      characteristicUuid: reference.characteristicUuid,
      characteristicValue: toArrayBuffer(value),
      descriptors: descriptors,
      properties: properties
    };
  }
}
