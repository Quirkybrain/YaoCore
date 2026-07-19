/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from './I18nService';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import common from '@ohos.app.ability.common';
import access from '@ohos.bluetooth.access';
import ble from '@ohos.bluetooth.ble';
import constant from '@ohos.bluetooth.constant';
import cryptoFramework from '@ohos.security.cryptoFramework';
import util from '@ohos.util';
import { BusinessError } from '@ohos.base';
import {
  BleProvisioningDevice,
  BleProvisioningProgressListener,
  BleProvisioningRequest,
  BleProvisioningResult,
  BleWiFiNetwork
} from '../model/BleProvisioningModel';

interface ProvisionVersion {
  ver?: string;
  sec_ver?: number;
  sec_patch_ver?: number;
  cap?: string[];
}

interface ProvisionVersionEnvelope {
  prov?: ProvisionVersion;
  yaocore?: ProvisionVersion;
}

interface ProvisionedGatewayIdentity {
  protocolVersion?: string | number;
  gatewayId?: string;
  gatewayName?: string;
  serviceId?: string;
}

interface VerifiedGatewayIdentity {
  gatewayId: string;
  gatewayName: string;
  protocolVersion: string;
}

interface ProvisioningFinishAck {
  status?: string;
  protocolVersion?: string | number;
}

class ProtoField {
  fieldNumber: number;
  wireType: number;
  varintValue: number;
  bytesValue: Uint8Array;

  constructor(fieldNumber: number, wireType: number, varintValue: number, bytesValue: Uint8Array) {
    this.fieldNumber = fieldNumber;
    this.wireType = wireType;
    this.varintValue = varintValue;
    this.bytesValue = bytesValue;
  }
}

class VarintValue {
  value: number;
  nextOffset: number;

  constructor(value: number, nextOffset: number) {
    this.value = value;
    this.nextOffset = nextOffset;
  }
}

class SecurityResponse0 {
  devicePublicKey: Uint8Array;
  deviceRandom: Uint8Array;

  constructor(devicePublicKey: Uint8Array, deviceRandom: Uint8Array) {
    this.devicePublicKey = devicePublicKey;
    this.deviceRandom = deviceRandom;
  }
}

class WiFiConnectionStatus {
  state: number;
  failureReason: number;
  ipAddress: string;

  constructor(state: number, failureReason: number, ipAddress: string) {
    this.state = state;
    this.failureReason = failureReason;
    this.ipAddress = ipAddress;
  }
}

/**
 * ESP-IDF Unified Provisioning BLE client for wifi_prov_mgr Security1.
 *
 * The transport deliberately discovers endpoint names from each characteristic's
 * 0x2901 User Description descriptor. ESP-IDF assigns characteristic UUIDs at
 * runtime, so hard-coding FF51/FF52 would not be interoperable.
 */
export class BleProvisioningService {
  private static readonly ACCESS_BLUETOOTH: Permissions = 'ohos.permission.ACCESS_BLUETOOTH';
  private static readonly YAOCORE_SERVICE_UUID: string = '7a6e0001-4d7b-4f67-9a21-6d13c52ae3b8';
  private static readonly USER_DESCRIPTION_UUID: string = '00002901-0000-1000-8000-00805f9b34fb';
  private static readonly DEVICE_NAME_PREFIX: string = 'YaoCore-GW-';
  private static readonly SCAN_DURATION_MS: number = 8000;
  private static readonly OPERATION_TIMEOUT_MS: number = 12000;
  // Identity and one worst-case Wi-Fi result fit at this MTU. Larger MTUs are
  // used to page more scan entries per request.
  private static readonly MIN_PROVISIONING_MTU: number = 128;
  private static instance: BleProvisioningService | undefined;
  private context: common.UIAbilityContext | undefined;
  private client: ble.GattClientDevice | undefined;
  private endpoints: Map<string, ble.BLECharacteristic> = new Map<string, ble.BLECharacteristic>();
  private cipher: cryptoFramework.Cipher | undefined;
  private clientPublicKey: Uint8Array = new Uint8Array(0);
  private activeScanCancel: (() => void) | undefined;
  private activeConnectCancel: (() => void) | undefined;
  private negotiatedMtu: number = 23;
  private sessionConnectionListener: ((change: ble.BLEConnectionChangeState) => void) | undefined;
  private operationAbortListeners: Array<() => void> = [];

  static getInstance(): BleProvisioningService {
    if (BleProvisioningService.instance === undefined) {
      BleProvisioningService.instance = new BleProvisioningService();
    }
    return BleProvisioningService.instance;
  }

  initialize(context: common.UIAbilityContext): void {
    this.context = context;
  }

  async scanGateways(): Promise<BleProvisioningDevice[]> {
    this.cancelScan();
    await this.ensureBluetoothReady();
    const found = new Map<string, BleProvisioningDevice>();
    return await new Promise<BleProvisioningDevice[]>((resolve, reject) => {
      let completed = false;
      let scanTimer = -1;
      const cleanup = (): void => {
        if (scanTimer >= 0) {
          clearTimeout(scanTimer);
          scanTimer = -1;
        }
        try {
          ble.stopBLEScan();
        } catch (error) {
        }
        try {
          ble.off('BLEDeviceFind', onDeviceFind);
        } catch (error) {
        }
        this.activeScanCancel = undefined;
      };
      const finish = (): void => {
        if (completed) {
          return;
        }
        completed = true;
        cleanup();
        const devices: BleProvisioningDevice[] = [];
        found.forEach((device: BleProvisioningDevice) => {
          devices.push(device);
        });
        devices.sort((left: BleProvisioningDevice, right: BleProvisioningDevice) => right.rssi - left.rssi);
        resolve(devices);
      };
      const onDeviceFind = (results: Array<ble.ScanResult>): void => {
        for (let index = 0; index < results.length; index++) {
          const result = results[index];
          const serviceUuid = this.findProvisioningServiceUuid(result);
          const name = result.deviceName === undefined ? '' : result.deviceName;
          if (serviceUuid.length === 0) {
            continue;
          }
          const device: BleProvisioningDevice = {
            deviceId: result.deviceId,
            deviceName: name.length > 0 ? name : `YaoCore-GW-${result.deviceId.slice(-5).replace(':', '')}`,
            serviceUuid: serviceUuid,
            rssi: result.rssi
          };
          const previous = found.get(device.deviceId);
          if (previous === undefined || device.rssi > previous.rssi) {
            found.set(device.deviceId, device);
          }
        }
      };
      this.activeScanCancel = (): void => {
        if (completed) {
          return;
        }
        completed = true;
        cleanup();
        reject(new Error('BLE_SCAN_CANCELLED'));
      };
      try {
        ble.on('BLEDeviceFind', onDeviceFind);
        /* Default scan options have the widest device compatibility. Some
         * HarmonyOS builds reject LOW_LATENCY even though it exists in the
         * SDK declaration, returning the generic 2900099 operation failure. */
        const filters: Array<ble.ScanFilter> = [{
          serviceUuid: BleProvisioningService.YAOCORE_SERVICE_UUID
        }];
        ble.startBLEScan(filters);
        scanTimer = setTimeout(finish, BleProvisioningService.SCAN_DURATION_MS);
      } catch (error) {
        completed = true;
        cleanup();
        const businessError = error as BusinessError;
        reject(new Error(`BLE_SCAN_FAILED:${businessError.code}`));
      }
    });
  }

  async provision(
    request: BleProvisioningRequest,
    listener?: BleProvisioningProgressListener
  ): Promise<BleProvisioningResult> {
    const ssid = request.ssid;
    const ssidBytes = this.encodeText(ssid);
    const passwordBytes = this.encodeText(request.password);
    const popBytes = this.encodeText(request.proofOfPossession);
    if (ssidBytes.length === 0 || ssidBytes.length > 32) {
      return this.failure(I18nService.t('Wi-Fi 名称必须为 1 至 32 个 UTF-8 字节'),
        'WIFI_SSID_INVALID', 'validation');
    }
    if (passwordBytes.length > 64) {
      return this.failure(I18nService.t('Wi-Fi 密码不能超过 64 个 UTF-8 字节'),
        'WIFI_PASSWORD_INVALID', 'validation');
    }
    if (popBytes.length < 8 || popBytes.length > 64) {
      return this.failure(I18nService.t('网关配网码必须为 8 至 64 个 UTF-8 字节'),
        'PROVISIONING_POP_INVALID', 'validation');
    }

    let stage = 'bluetooth-ready';
    let verifiedIdentity: VerifiedGatewayIdentity | undefined = undefined;
    try {
      await this.ensureBluetoothReady();
      stage = 'connect';
      this.progress(listener, 'connect', I18nService.t('正在连接网关'), 10);
      await this.connect(request.device);

      stage = 'discover';
      this.progress(listener, 'discover', I18nService.t('正在识别安全配网服务'), 25);
      // Some HarmonyOS Bluetooth stacks report a transient 2900099 business
      // error when service discovery starts immediately after MTU negotiation.
      // Let the connection settle; discoverEndpoints also retries transient
      // GATT discovery/descriptor reads on the same authenticated link.
      await this.delay(350);
      await this.discoverEndpoints(request.device.serviceUuid);
      await this.validateProtocolVersion();

      stage = 'handshake';
      this.progress(listener, 'handshake', I18nService.t('正在建立 Security1 加密会话'), 42);
      await this.establishSecurity1(request.proofOfPossession);

      // 自定义端点经过已建立的 Security1 会话加密与 PoP 认证。先读取不可猜测的
      // 逻辑身份，配网后再用相同 gatewayId 关联 HTTP HMAC 认证结果。
      stage = 'identity';
      this.progress(listener, 'identity', I18nService.t('正在读取网关安全身份'), 52);
      verifiedIdentity = await this.readProvisionedGatewayIdentity();

      stage = 'credentials';
      this.progress(listener, 'credentials', I18nService.t('正在加密发送 Wi-Fi 凭据'), 62);
      const setResponse = await this.sendSecure('prov-config', this.buildSetConfig(ssid, request.password));
      this.validateConfigResponse(setResponse, 3, 13);

      stage = 'apply';
      this.progress(listener, 'apply', I18nService.t('网关正在连接家庭 Wi-Fi'), 76);
      const applyResponse = await this.sendSecure('prov-config', this.buildApplyConfig());
      this.validateConfigResponse(applyResponse, 5, 15);

      stage = 'wifi-status';
      const status = await this.waitForWiFiStatus(listener);
      if (status.state === 0) {
        await this.finishProvisioningIfSupported();
        this.progress(listener, 'lan-verify', I18nService.t('网关已连接家庭 Wi-Fi，准备进行局域网身份认证'), 88);
        return {
          success: true,
          message: I18nService.t('BLE 配网成功，正在通过局域网认证并关联同一网关'),
          ipAddress: status.ipAddress,
          expectedGatewayId: verifiedIdentity.gatewayId,
          expectedGatewayName: verifiedIdentity.gatewayName,
          protocolVersion: verifiedIdentity.protocolVersion
        };
      }
      if (status.state === 3 && status.failureReason === 0) {
        return this.failure(I18nService.t('Wi-Fi 认证失败，请检查密码'), 'WIFI_AUTH_FAILED', stage);
      }
      if (status.state === 3 && status.failureReason === 1) {
        return this.failure(I18nService.t('网关未找到该 Wi-Fi，请确认使用 2.4 GHz 网络'),
          'WIFI_NETWORK_NOT_FOUND', stage);
      }
      // The ESP-IDF station can remain in Connecting while the AP retries an
      // association or its DHCP server is slow. The credentials have already
      // been accepted and persisted at this point, so reporting a terminal
      // provisioning failure is incorrect. Preserve the Security1 identity
      // and hand over to authenticated LAN discovery, whose retries provide
      // the authoritative end-to-end result.
      this.progress(listener, 'lan-verify', I18nService.isChinese() ?
        'Wi-Fi 配置已提交，网关仍在连接，正在转入局域网确认' :
        'Wi-Fi settings were submitted. The gateway is still connecting; verifying it over the LAN.', 88);
      return {
        success: true,
        message: I18nService.isChinese() ?
          '网关正在连接家庭 Wi-Fi，YaoCore 将继续通过局域网认证并绑定' :
          'The gateway is joining the home Wi-Fi. YaoCore will continue LAN authentication and binding.',
        ipAddress: '',
        expectedGatewayId: verifiedIdentity.gatewayId,
        expectedGatewayName: verifiedIdentity.gatewayName,
        protocolVersion: verifiedIdentity.protocolVersion
      };
    } catch (error) {
      // ESP-IDF releases the provisioning BLE transport as soon as the
      // station obtains an IP address. That disconnect can race get-status.
      // Security1, identity verification, SetConfig and ApplyConfig have all
      // succeeded here, so only a transport loss is accepted as the expected
      // hand-off to authenticated LAN discovery.
      if (stage === 'wifi-status' && verifiedIdentity !== undefined &&
        this.isExpectedProvisioningTransportRelease(error)) {
        this.progress(listener, 'lan-verify', I18nService.isChinese() ?
          '网关已接收 Wi-Fi 配置，BLE 已释放，正在通过局域网确认网关' :
          'The gateway accepted the Wi-Fi configuration. Verifying it over the LAN.', 88);
        return {
          success: true,
          message: I18nService.isChinese() ?
            '网关已完成安全配网，正在通过局域网认证并绑定同一网关' :
            'Secure provisioning completed. Authenticating and binding the same gateway over the LAN.',
          ipAddress: '',
          expectedGatewayId: verifiedIdentity.gatewayId,
          expectedGatewayName: verifiedIdentity.gatewayName,
          protocolVersion: verifiedIdentity.protocolVersion
        };
      }
      const errorCode = this.diagnosticCode(error);
      const message = stage === 'handshake' ?
        I18nService.t('Security1 握手失败，请核对 PoP 并保持手机靠近网关') : this.mapFailure(error);
      return this.failure(message, errorCode, stage);
    } finally {
      this.disconnect();
    }
  }

  async scanWiFiNetworks(
    device: BleProvisioningDevice,
    proofOfPossession: string,
    listener?: BleProvisioningProgressListener
  ): Promise<BleWiFiNetwork[]> {
    const popLength = this.encodeText(proofOfPossession).length;
    if (popLength < 8 || popLength > 64) {
      throw new Error('PROVISIONING_POP_INVALID');
    }
    try {
      await this.ensureBluetoothReady();
      this.progress(listener, 'connect', I18nService.t('正在连接网关'), 10);
      await this.connect(device);
      this.progress(listener, 'discover', I18nService.t('正在识别安全配网服务'), 24);
      await this.delay(350);
      await this.discoverEndpoints(device.serviceUuid);
      await this.validateProtocolVersion();
      this.progress(listener, 'handshake', I18nService.t('正在建立 Security1 加密会话'), 38);
      await this.establishSecurity1(proofOfPossession);

      this.progress(listener, 'wifi-scan', I18nService.t('网关正在扫描周边 2.4 GHz Wi-Fi'), 52);
      const startResponse = await this.sendSecure('prov-scan', this.buildWiFiScanStart());
      this.validateScanResponse(startResponse, 1, 11);
      const resultCount = await this.waitForWiFiScan(listener);
      const networks = await this.fetchWiFiScanResults(resultCount, listener);
      this.progress(listener, 'wifi-scan-complete', `发现 ${networks.length} 个 Wi-Fi`, 100);
      return networks;
    } finally {
      this.disconnect();
    }
  }

  disconnect(): void {
    this.cancelScan();
    const cancelConnect = this.activeConnectCancel;
    this.activeConnectCancel = undefined;
    if (cancelConnect !== undefined) {
      cancelConnect();
    }
    const active = this.client;
    if (active !== undefined && this.sessionConnectionListener !== undefined) {
      try {
        active.off('BLEConnectionStateChange', this.sessionConnectionListener);
      } catch (error) {
      }
    }
    this.sessionConnectionListener = undefined;
    this.abortActiveOperations();
    this.client = undefined;
    this.endpoints.clear();
    this.cipher = undefined;
    this.clientPublicKey = new Uint8Array(0);
    this.negotiatedMtu = 23;
    if (active === undefined) {
      return;
    }
    try {
      active.disconnect();
    } catch (error) {
    }
    try {
      active.close();
    } catch (error) {
    }
  }

  private cancelScan(): void {
    const cancel = this.activeScanCancel;
    this.activeScanCancel = undefined;
    if (cancel !== undefined) {
      cancel();
    }
  }

  private async ensureBluetoothReady(): Promise<void> {
    if (this.context === undefined) {
      throw new Error('BLE_CONTEXT_NOT_READY');
    }
    const manager = abilityAccessCtrl.createAtManager();
    const permissionResult = await manager.requestPermissionsFromUser(
      this.context,
      [BleProvisioningService.ACCESS_BLUETOOTH]
    );
    if (permissionResult.authResults.length === 0 || permissionResult.authResults[0] !== 0) {
      throw new Error('BLE_PERMISSION_DENIED');
    }
    if (access.getState() !== access.BluetoothState.STATE_ON) {
      throw new Error('BLUETOOTH_DISABLED');
    }
  }

  private findProvisioningServiceUuid(result: ble.ScanResult): string {
    if (result.serviceUuids === undefined) {
      return '';
    }
    for (let index = 0; index < result.serviceUuids.length; index++) {
      const normalized = result.serviceUuids[index].toLowerCase();
      if (normalized === BleProvisioningService.YAOCORE_SERVICE_UUID) {
        return normalized;
      }
    }
    return '';
  }

  private async connect(device: BleProvisioningDevice): Promise<void> {
    this.disconnect();
    const client = ble.createGattClientDevice(device.deviceId);
    this.client = client;
    await new Promise<void>((resolve, reject) => {
      let settled = false;
      let connectionTimer = -1;
      const cleanup = (): void => {
        if (connectionTimer >= 0) {
          clearTimeout(connectionTimer);
          connectionTimer = -1;
        }
        try {
          client.off('BLEConnectionStateChange', onConnection);
        } catch (error) {
        }
        this.activeConnectCancel = undefined;
      };
      const settle = (error: Error | undefined): void => {
        if (settled) {
          return;
        }
        settled = true;
        cleanup();
        if (error === undefined) {
          resolve();
        } else {
          reject(error);
        }
      };
      const onConnection = (change: ble.BLEConnectionChangeState): void => {
        if (change.deviceId !== device.deviceId || settled) {
          return;
        }
        if (change.state === constant.ProfileConnectionState.STATE_CONNECTED) {
          settle(undefined);
        } else if (change.state === constant.ProfileConnectionState.STATE_DISCONNECTED) {
          settle(new Error('BLE_CONNECTION_FAILED'));
        }
      };
      this.activeConnectCancel = (): void => {
        settle(new Error('BLE_CONNECTION_CANCELLED'));
      };
      try {
        client.on('BLEConnectionStateChange', onConnection);
        connectionTimer = setTimeout(() => {
          settle(new Error('BLE_CONNECTION_TIMEOUT'));
        }, BleProvisioningService.OPERATION_TIMEOUT_MS);
        client.connect();
      } catch (error) {
        settle(new Error('BLE_CONNECTION_FAILED'));
      }
    });
    this.installSessionConnectionListener(client, device.deviceId);
    await this.negotiateMtu(client);
  }

  private installSessionConnectionListener(client: ble.GattClientDevice, deviceId: string): void {
    const listener = (change: ble.BLEConnectionChangeState): void => {
      if (change.deviceId !== deviceId ||
        change.state !== constant.ProfileConnectionState.STATE_DISCONNECTED) {
        return;
      }
      const cancelConnect = this.activeConnectCancel;
      if (cancelConnect !== undefined) cancelConnect();
      this.abortActiveOperations();
    };
    this.sessionConnectionListener = listener;
    client.on('BLEConnectionStateChange', listener);
  }

  private async negotiateMtu(client: ble.GattClientDevice): Promise<void> {
    await new Promise<void>((resolve, reject) => {
      let settled = false;
      let mtuTimer = -1;
      const cleanup = (): void => {
        if (mtuTimer >= 0) {
          clearTimeout(mtuTimer);
          mtuTimer = -1;
        }
        try {
          client.off('BLEMtuChange', onMtuChange);
        } catch (error) {
        }
        this.activeConnectCancel = undefined;
      };
      const settle = (error: Error | undefined): void => {
        if (settled) {
          return;
        }
        settled = true;
        cleanup();
        if (error === undefined) {
          resolve();
        } else {
          reject(error);
        }
      };
      const onMtuChange = (mtu: number): void => {
        if (mtu < BleProvisioningService.MIN_PROVISIONING_MTU) {
          settle(new Error(`BLE_MTU_TOO_SMALL:${mtu}`));
          return;
        }
        this.negotiatedMtu = mtu;
        settle(undefined);
      };
      this.activeConnectCancel = (): void => {
        settle(new Error('BLE_MTU_CANCELLED'));
      };
      try {
        client.on('BLEMtuChange', onMtuChange);
        mtuTimer = setTimeout(() => {
          settle(new Error('BLE_MTU_TIMEOUT'));
        }, BleProvisioningService.OPERATION_TIMEOUT_MS);
        client.setBLEMtuSize(512);
      } catch (error) {
        settle(new Error('BLE_MTU_REQUEST_FAILED'));
      }
    });
  }

  private async discoverEndpoints(serviceUuid: string): Promise<void> {
    let lastError: Error = new Error('GATT_DISCOVERY_FAILED');
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        await this.discoverEndpointsOnce(serviceUuid);
        return;
      } catch (error) {
        lastError = new Error(this.errorDescription(error));
        this.endpoints.clear();
        if (attempt < 2) {
          await this.delay(400 * (attempt + 1));
        }
      }
    }
    throw lastError;
  }

  private async discoverEndpointsOnce(serviceUuid: string): Promise<void> {
    const client = this.requireClient();
    const services = await this.withTimeout(client.getServices(), 'GATT_SERVICES_TIMEOUT');
    let provisioningService: ble.GattService | undefined;
    const expectedUuid = serviceUuid.toLowerCase();
    for (let index = 0; index < services.length; index++) {
      const current = services[index];
      if (current.serviceUuid.toLowerCase() === expectedUuid &&
        expectedUuid === BleProvisioningService.YAOCORE_SERVICE_UUID) {
        provisioningService = current;
        break;
      }
    }
    if (provisioningService === undefined) {
      throw new Error('PROVISIONING_SERVICE_NOT_FOUND');
    }

    this.endpoints.clear();
    for (let charIndex = 0; charIndex < provisioningService.characteristics.length; charIndex++) {
      const characteristic = provisioningService.characteristics[charIndex];
      for (let descriptorIndex = 0; descriptorIndex < characteristic.descriptors.length; descriptorIndex++) {
        const descriptor = characteristic.descriptors[descriptorIndex];
        const descriptorUuid = descriptor.descriptorUuid.toLowerCase();
        if (descriptorUuid !== BleProvisioningService.USER_DESCRIPTION_UUID && descriptorUuid.indexOf('2901') < 0) {
          continue;
        }
        const readDescriptor = await this.withTimeout(
          client.readDescriptorValue(descriptor),
          'GATT_DESCRIPTOR_TIMEOUT'
        );
        const endpointName = this.decodeText(new Uint8Array(readDescriptor.descriptorValue)).replace('\u0000', '').trim();
        if (endpointName.length > 0) {
          this.endpoints.set(endpointName, characteristic);
        }
      }
    }
    if (!this.endpoints.has('proto-ver') || !this.endpoints.has('prov-session') ||
      !this.endpoints.has('prov-config') || !this.endpoints.has('prov-scan') ||
      !this.endpoints.has('prov-ctrl') || !this.endpoints.has('yaocore-id')) {
      throw new Error('PROVISIONING_ENDPOINTS_INCOMPLETE');
    }
  }

  private async readProvisionedGatewayIdentity(): Promise<VerifiedGatewayIdentity> {
    const request = this.encodeText(JSON.stringify({
      op: 'get_identity',
      protocolVersion: '2.0'
    }));
    const response = await this.sendSecure('yaocore-id', request);
    let identity: ProvisionedGatewayIdentity;
    try {
      identity = JSON.parse(this.decodeText(response)) as ProvisionedGatewayIdentity;
    } catch (error) {
      throw new Error('PROVISIONING_IDENTITY_INVALID');
    }
    const gatewayId = identity.gatewayId === undefined ? '' : identity.gatewayId.trim();
    const gatewayName = identity.gatewayName === undefined ? '' : identity.gatewayName.trim();
    const protocolVersion = identity.protocolVersion === undefined ? '' : `${identity.protocolVersion}`;
    if (!this.isGatewayIdentifier(gatewayId) || gatewayName.length === 0 || gatewayName.length > 63 ||
      protocolVersion !== '2.0' || identity.serviceId !== 'YaoCoreGateway') {
      throw new Error('PROVISIONING_IDENTITY_INVALID');
    }
    return {
      gatewayId: gatewayId,
      gatewayName: gatewayName,
      protocolVersion: protocolVersion
    };
  }

  private async finishProvisioningIfSupported(): Promise<void> {
    if (!this.endpoints.has('yaocore-done')) {
      return;
    }
    const request = this.encodeText(JSON.stringify({
      op: 'finish',
      protocolVersion: '2.0'
    }));
    try {
      const response = await this.sendSecure('yaocore-done', request);
      const acknowledgement = JSON.parse(this.decodeText(response)) as ProvisioningFinishAck;
      const version = acknowledgement.protocolVersion === undefined ? '' :
        `${acknowledgement.protocolVersion}`;
      if (acknowledgement.status !== 'accepted' || version !== '2.0') {
        return;
      }
    } catch (error) {
      // The finish handler schedules BLE teardown, so its acknowledgement can
      // race the disconnect. Finalization is best-effort because connected
      // status and the authenticated IPv4 address are already available; LAN
      // identity verification remains the authoritative binding gate.
      return;
    }
  }

  private isGatewayIdentifier(value: string): boolean {
    if (value.length < 1 || value.length > 63) {
      return false;
    }
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      const alphaNumeric = (code >= 48 && code <= 57) || (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122);
      const separator = value.charAt(index) === '_' || value.charAt(index) === '-' ||
        value.charAt(index) === '.' || value.charAt(index) === ':';
      if ((!alphaNumeric && !separator) || (index === 0 && !alphaNumeric)) {
        return false;
      }
    }
    return true;
  }

  private async validateProtocolVersion(): Promise<void> {
    const response = await this.writeRead('proto-ver', this.encodeText('ESP'));
    const raw = this.decodeText(response);
    let envelope: ProvisionVersionEnvelope;
    try {
      envelope = JSON.parse(raw) as ProvisionVersionEnvelope;
    } catch (error) {
      throw new Error('PROVISIONING_VERSION_INVALID');
    }
    if (envelope.prov === undefined || envelope.prov.sec_ver !== 1 || envelope.prov.ver !== 'v1.1' ||
      envelope.yaocore === undefined || envelope.yaocore.ver !== '2.0') {
      throw new Error('SECURITY_VERSION_UNSUPPORTED');
    }
    const capabilities = envelope.prov.cap === undefined ? [] : envelope.prov.cap;
    if (capabilities.indexOf('wifi_scan') < 0 || capabilities.indexOf('no_sec') >= 0 ||
      capabilities.indexOf('no_pop') >= 0) {
      throw new Error('PROVISIONING_CAPABILITIES_UNSAFE');
    }
  }

  private async establishSecurity1(proofOfPossession: string): Promise<void> {
    const keyGenerator = cryptoFramework.createAsyKeyGenerator('X25519');
    const keyPair = keyGenerator.generateKeyPairSync();
    const encodedPublicKey = keyPair.pubKey.getEncoded().data;
    if (encodedPublicKey.length < 32) {
      throw new Error('X25519_PUBLIC_KEY_INVALID');
    }
    this.clientPublicKey = this.copyRange(encodedPublicKey, encodedPublicKey.length - 32, encodedPublicKey.length);

    const response0Raw = await this.writeRead('prov-session', this.buildSecurityCommand0(this.clientPublicKey));
    const response0 = this.parseSecurityResponse0(response0Raw);
    const remoteDer = this.x25519RawPublicKeyToDer(response0.devicePublicKey);
    const remoteKeyPair = keyGenerator.convertKeySync({ data: remoteDer }, null);
    const agreement = cryptoFramework.createKeyAgreement('X25519');
    const sharedSecret = agreement.generateSecretSync(keyPair.priKey, remoteKeyPair.pubKey).data;
    const sessionKey = new Uint8Array(sharedSecret.length);
    sessionKey.set(sharedSecret);

    const popBytes = this.encodeText(proofOfPossession);
    if (popBytes.length > 0) {
      const digest = cryptoFramework.createMd('SHA256');
      digest.updateSync({ data: popBytes });
      const popDigest = digest.digestSync().data;
      if (popDigest.length !== sessionKey.length) {
        throw new Error('SECURITY_KEY_LENGTH_INVALID');
      }
      for (let index = 0; index < sessionKey.length; index++) {
        sessionKey[index] = sessionKey[index] ^ popDigest[index];
      }
    }

    const symmetricKey = cryptoFramework.createSymKeyGenerator('AES256').convertKeySync({ data: sessionKey });
    const cipher = cryptoFramework.createCipher('AES256|CTR|NoPadding');
    const params: cryptoFramework.IvParamsSpec = {
      algName: 'IvParamsSpec',
      iv: {
        data: response0.deviceRandom
      }
    };
    cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, symmetricKey, params);
    this.cipher = cipher;

    const clientVerify = this.crypt(response0.devicePublicKey);
    const response1Raw = await this.writeRead('prov-session', this.buildSecurityCommand1(clientVerify));
    const encryptedDeviceVerify = this.parseSecurityResponse1(response1Raw);
    const deviceVerify = this.crypt(encryptedDeviceVerify);
    if (!this.bytesEqual(deviceVerify, this.clientPublicKey)) {
      throw new Error('PROOF_OF_POSSESSION_REJECTED');
    }
  }

  private async sendSecure(endpoint: string, payload: Uint8Array): Promise<Uint8Array> {
    const encrypted = this.crypt(payload);
    const response = await this.writeRead(endpoint, encrypted);
    return this.crypt(response);
  }

  private async writeRead(endpoint: string, data: Uint8Array): Promise<Uint8Array> {
    const client = this.requireClient();
    const discovered = this.endpoints.get(endpoint);
    if (discovered === undefined) {
      throw new Error(`ENDPOINT_NOT_FOUND:${endpoint}`);
    }
    const characteristic: ble.BLECharacteristic = {
      serviceUuid: discovered.serviceUuid,
      characteristicUuid: discovered.characteristicUuid,
      characteristicValue: this.toArrayBuffer(data),
      descriptors: discovered.descriptors
    };
    await this.withTimeout(
      client.writeCharacteristicValue(characteristic, ble.GattWriteType.WRITE),
      `GATT_WRITE_TIMEOUT:${endpoint}`
    );
    const response = await this.withTimeout(
      client.readCharacteristicValue(discovered),
      `GATT_READ_TIMEOUT:${endpoint}`
    );
    return new Uint8Array(response.characteristicValue);
  }

  private async waitForWiFiStatus(listener?: BleProvisioningProgressListener): Promise<WiFiConnectionStatus> {
    for (let attempt = 0; attempt < 25; attempt++) {
      await this.delay(attempt === 0 ? 700 : 1000);
      this.progress(listener, 'verify', I18nService.isChinese() ?
        `正在确认连接状态 ${attempt + 1}/25` : `Confirming connection ${attempt + 1}/25`,
        80 + Math.floor(attempt / 2));
      const response = await this.sendSecure('prov-config', this.buildGetStatus());
      const status = this.parseWiFiStatus(response);
      if (status.state === 0 || status.state === 3) {
        return status;
      }
    }
    return new WiFiConnectionStatus(2, -1, '');
  }

  private async waitForWiFiScan(listener?: BleProvisioningProgressListener): Promise<number> {
    for (let attempt = 0; attempt < 16; attempt++) {
      await this.delay(500);
      this.progress(listener, 'wifi-scan', I18nService.isChinese() ?
        `正在等待网关扫描 ${attempt + 1}/16` : `Waiting for gateway scan ${attempt + 1}/16`, 55 + attempt);
      const response = await this.sendSecure('prov-scan', this.buildWiFiScanStatus());
      const payload = this.parseFields(response);
      if (this.getVarint(payload, 1, -1) !== 3 || this.getVarint(payload, 2, 0) !== 0) {
        throw new Error('WIFI_SCAN_STATUS_INVALID');
      }
      const status = this.parseFields(this.requireBytes(payload, 13));
      if (this.getVarint(status, 1, 0) === 1) {
        return this.getVarint(status, 2, 0);
      }
    }
    throw new Error('WIFI_SCAN_TIMEOUT');
  }

  private async fetchWiFiScanResults(
    resultCount: number,
    listener?: BleProvisioningProgressListener
  ): Promise<BleWiFiNetwork[]> {
    const networks = new Map<string, BleWiFiNetwork>();
    const pageSize = this.negotiatedMtu >= 247 ? 4 : (this.negotiatedMtu >= 176 ? 2 : 1);
    for (let start = 0; start < resultCount; start += pageSize) {
      const count = Math.min(pageSize, resultCount - start);
      this.progress(listener, 'wifi-scan-results', `正在读取 Wi-Fi ${start + 1}-${start + count}`, 74);
      const response = await this.sendSecure('prov-scan', this.buildWiFiScanResult(start, count));
      const payload = this.parseFields(response);
      if (this.getVarint(payload, 1, -1) !== 5 || this.getVarint(payload, 2, 0) !== 0) {
        throw new Error('WIFI_SCAN_RESULT_INVALID');
      }
      const result = this.parseFields(this.requireBytes(payload, 15));
      const entries = this.repeatedBytes(result, 1);
      for (let index = 0; index < entries.length; index++) {
        const fields = this.parseFields(entries[index]);
        const ssidBytes = this.optionalBytes(fields, 1);
        if (ssidBytes === undefined) {
          continue;
        }
        const ssid = this.decodeText(ssidBytes);
        if (ssidBytes.length === 0) {
          continue;
        }
        const rawRssi = this.getVarint(fields, 3, 0xFFFFFF9C);
        const network: BleWiFiNetwork = {
          ssid: ssid,
          channel: this.getVarint(fields, 2, 0),
          rssi: rawRssi >= 0x80000000 ? rawRssi - 0x100000000 : rawRssi,
          authMode: this.getVarint(fields, 5, 0)
        };
        const previous = networks.get(ssid);
        if (previous === undefined || network.rssi > previous.rssi) {
          networks.set(ssid, network);
        }
      }
    }
    const values: BleWiFiNetwork[] = [];
    networks.forEach((network: BleWiFiNetwork) => {
      values.push(network);
    });
    values.sort((left: BleWiFiNetwork, right: BleWiFiNetwork) => right.rssi - left.rssi);
    return values;
  }

  private buildWiFiScanStart(): Uint8Array {
    const command = this.concat([
      this.varintField(1, 1),
      this.varintField(2, 0),
      this.varintField(3, 0),
      this.varintField(4, 120)
    ]);
    return this.messageField(10, command);
  }

  private buildWiFiScanStatus(): Uint8Array {
    return this.concat([
      this.varintField(1, 2),
      this.messageField(12, new Uint8Array(0))
    ]);
  }

  private buildWiFiScanResult(start: number, count: number): Uint8Array {
    const command = this.concat([
      this.varintField(1, start),
      this.varintField(2, count)
    ]);
    return this.concat([
      this.varintField(1, 4),
      this.messageField(14, command)
    ]);
  }

  private validateScanResponse(data: Uint8Array, expectedMessage: number, responseField: number): void {
    const payload = this.parseFields(data);
    if (this.getVarint(payload, 1, -1) !== expectedMessage || this.getVarint(payload, 2, 0) !== 0) {
      throw new Error('WIFI_SCAN_REJECTED');
    }
    this.requireBytes(payload, responseField);
  }

  private buildSecurityCommand0(publicKey: Uint8Array): Uint8Array {
    const command = this.bytesField(1, publicKey);
    const securityPayload = this.messageField(20, command);
    return this.concat([
      this.varintField(2, 1),
      this.messageField(11, securityPayload)
    ]);
  }

  private buildSecurityCommand1(clientVerify: Uint8Array): Uint8Array {
    const command = this.bytesField(2, clientVerify);
    const securityPayload = this.concat([
      this.varintField(1, 2),
      this.messageField(22, command)
    ]);
    return this.concat([
      this.varintField(2, 1),
      this.messageField(11, securityPayload)
    ]);
  }

  private parseSecurityResponse0(data: Uint8Array): SecurityResponse0 {
    const session = this.parseFields(data);
    if (this.getVarint(session, 2, -1) !== 1) {
      throw new Error('SECURITY_VERSION_MISMATCH');
    }
    const securityPayload = this.parseFields(this.requireBytes(session, 11));
    if (this.getVarint(securityPayload, 1, -1) !== 1) {
      throw new Error('SECURITY_RESPONSE_MESSAGE_INVALID');
    }
    const response = this.parseFields(this.requireBytes(securityPayload, 21));
    if (this.getVarint(response, 1, 0) !== 0) {
      throw new Error('SECURITY_HANDSHAKE_REJECTED');
    }
    const publicKey = this.requireBytes(response, 2);
    const random = this.requireBytes(response, 3);
    if (publicKey.length !== 32 || random.length !== 16) {
      throw new Error('SECURITY_RESPONSE_INVALID');
    }
    return new SecurityResponse0(publicKey, random);
  }

  private parseSecurityResponse1(data: Uint8Array): Uint8Array {
    const session = this.parseFields(data);
    if (this.getVarint(session, 2, -1) !== 1) {
      throw new Error('SECURITY_VERSION_MISMATCH');
    }
    const securityPayload = this.parseFields(this.requireBytes(session, 11));
    if (this.getVarint(securityPayload, 1, -1) !== 3) {
      throw new Error('SECURITY_RESPONSE_MESSAGE_INVALID');
    }
    const response = this.parseFields(this.requireBytes(securityPayload, 23));
    if (this.getVarint(response, 1, 0) !== 0) {
      throw new Error('PROOF_OF_POSSESSION_REJECTED');
    }
    const verify = this.requireBytes(response, 3);
    if (verify.length !== 32) {
      throw new Error('SECURITY_RESPONSE_INVALID');
    }
    return verify;
  }

  private buildSetConfig(ssid: string, password: string): Uint8Array {
    const fields: Uint8Array[] = [this.bytesField(1, this.encodeText(ssid))];
    if (password.length > 0) {
      fields.push(this.bytesField(2, this.encodeText(password)));
    }
    const command = this.concat(fields);
    return this.concat([
      this.varintField(1, 2),
      this.messageField(12, command)
    ]);
  }

  private buildApplyConfig(): Uint8Array {
    return this.concat([
      this.varintField(1, 4),
      this.messageField(14, new Uint8Array(0))
    ]);
  }

  private buildGetStatus(): Uint8Array {
    return this.messageField(10, new Uint8Array(0));
  }

  private validateConfigResponse(data: Uint8Array, expectedMessage: number, responseField: number): void {
    const payload = this.parseFields(data);
    if (this.getVarint(payload, 1, -1) !== expectedMessage) {
      throw new Error('WIFI_CONFIG_RESPONSE_INVALID');
    }
    const response = this.parseFields(this.requireBytes(payload, responseField));
    if (this.getVarint(response, 1, 0) !== 0) {
      throw new Error('WIFI_CONFIG_REJECTED');
    }
  }

  private parseWiFiStatus(data: Uint8Array): WiFiConnectionStatus {
    const payload = this.parseFields(data);
    if (this.getVarint(payload, 1, -1) !== 1) {
      throw new Error('WIFI_STATUS_RESPONSE_INVALID');
    }
    const response = this.parseFields(this.requireBytes(payload, 11));
    if (this.getVarint(response, 1, 0) !== 0) {
      throw new Error('WIFI_STATUS_REJECTED');
    }
    const state = this.getVarint(response, 2, 0);
    const failureReason = this.getVarint(response, 10, 0);
    let ipAddress = '';
    const connected = this.optionalBytes(response, 11);
    if (connected !== undefined) {
      const connectedFields = this.parseFields(connected);
      const ipBytes = this.optionalBytes(connectedFields, 1);
      if (ipBytes !== undefined) {
        ipAddress = this.decodeText(ipBytes);
      }
    }
    return new WiFiConnectionStatus(state, failureReason, ipAddress);
  }

  private crypt(data: Uint8Array): Uint8Array {
    if (this.cipher === undefined) {
      throw new Error('SECURE_SESSION_NOT_READY');
    }
    return this.cipher.updateSync({ data: data }).data;
  }

  private x25519RawPublicKeyToDer(raw: Uint8Array): Uint8Array {
    if (raw.length !== 32) {
      throw new Error('X25519_PUBLIC_KEY_INVALID');
    }
    const header = new Uint8Array([0x30, 0x2A, 0x30, 0x05, 0x06, 0x03, 0x2B, 0x65, 0x6E, 0x03, 0x21, 0x00]);
    return this.concat([header, raw]);
  }

  private parseFields(data: Uint8Array): ProtoField[] {
    const fields: ProtoField[] = [];
    let offset = 0;
    while (offset < data.length) {
      const key = this.readVarint(data, offset);
      offset = key.nextOffset;
      const fieldNumber = Math.floor(key.value / 8);
      const wireType = key.value % 8;
      if (fieldNumber <= 0) {
        throw new Error('PROTOBUF_INVALID_FIELD');
      }
      if (wireType === 0) {
        const value = this.readVarint(data, offset);
        offset = value.nextOffset;
        fields.push(new ProtoField(fieldNumber, wireType, value.value, new Uint8Array(0)));
      } else if (wireType === 2) {
        const length = this.readVarint(data, offset);
        offset = length.nextOffset;
        const end = offset + length.value;
        if (length.value < 0 || end > data.length) {
          throw new Error('PROTOBUF_LENGTH_INVALID');
        }
        fields.push(new ProtoField(fieldNumber, wireType, 0, this.copyRange(data, offset, end)));
        offset = end;
      } else if (wireType === 1) {
        offset += 8;
      } else if (wireType === 5) {
        offset += 4;
      } else {
        throw new Error('PROTOBUF_WIRE_TYPE_UNSUPPORTED');
      }
      if (offset > data.length) {
        throw new Error('PROTOBUF_TRUNCATED');
      }
    }
    return fields;
  }

  private readVarint(data: Uint8Array, start: number): VarintValue {
    // Keep the low 32 bits explicitly. Negative protobuf int32 values (for
    // example RSSI -100) are sign-extended to a 10-byte uint64 varint; adding
    // all 64 bits to a JavaScript Number would lose integer precision.
    let low32 = 0;
    let shift = 0;
    let offset = start;
    for (let index = 0; index < 10 && offset < data.length; index++) {
      const current = data[offset];
      offset += 1;
      if (shift < 32) {
        const bitCount = Math.min(7, 32 - shift);
        const modulus = Math.pow(2, bitCount);
        low32 += ((current & 0x7F) % modulus) * Math.pow(2, shift);
      }
      if ((current & 0x80) === 0) {
        return new VarintValue(low32, offset);
      }
      shift += 7;
    }
    throw new Error('PROTOBUF_VARINT_INVALID');
  }

  private getVarint(fields: ProtoField[], fieldNumber: number, fallback: number): number {
    for (let index = 0; index < fields.length; index++) {
      if (fields[index].fieldNumber === fieldNumber && fields[index].wireType === 0) {
        return fields[index].varintValue;
      }
    }
    return fallback;
  }

  private requireBytes(fields: ProtoField[], fieldNumber: number): Uint8Array {
    const value = this.optionalBytes(fields, fieldNumber);
    if (value === undefined) {
      throw new Error(`PROTOBUF_FIELD_MISSING:${fieldNumber}`);
    }
    return value;
  }

  private optionalBytes(fields: ProtoField[], fieldNumber: number): Uint8Array | undefined {
    for (let index = 0; index < fields.length; index++) {
      if (fields[index].fieldNumber === fieldNumber && fields[index].wireType === 2) {
        return fields[index].bytesValue;
      }
    }
    return undefined;
  }

  private repeatedBytes(fields: ProtoField[], fieldNumber: number): Uint8Array[] {
    const values: Uint8Array[] = [];
    for (let index = 0; index < fields.length; index++) {
      if (fields[index].fieldNumber === fieldNumber && fields[index].wireType === 2) {
        values.push(fields[index].bytesValue);
      }
    }
    return values;
  }

  private varintField(fieldNumber: number, value: number): Uint8Array {
    return this.concat([
      this.encodeVarint(fieldNumber * 8),
      this.encodeVarint(value)
    ]);
  }

  private bytesField(fieldNumber: number, value: Uint8Array): Uint8Array {
    return this.concat([
      this.encodeVarint(fieldNumber * 8 + 2),
      this.encodeVarint(value.length),
      value
    ]);
  }

  private messageField(fieldNumber: number, value: Uint8Array): Uint8Array {
    return this.bytesField(fieldNumber, value);
  }

  private encodeVarint(input: number): Uint8Array {
    const values: number[] = [];
    let value = input;
    do {
      let current = value % 128;
      value = Math.floor(value / 128);
      if (value > 0) {
        current += 128;
      }
      values.push(current);
    } while (value > 0);
    return new Uint8Array(values);
  }

  private concat(parts: Uint8Array[]): Uint8Array {
    let length = 0;
    for (let index = 0; index < parts.length; index++) {
      length += parts[index].length;
    }
    const result = new Uint8Array(length);
    let offset = 0;
    for (let index = 0; index < parts.length; index++) {
      result.set(parts[index], offset);
      offset += parts[index].length;
    }
    return result;
  }

  private copyRange(data: Uint8Array, start: number, end: number): Uint8Array {
    const result = new Uint8Array(end - start);
    for (let index = start; index < end; index++) {
      result[index - start] = data[index];
    }
    return result;
  }

  private bytesEqual(left: Uint8Array, right: Uint8Array): boolean {
    if (left.length !== right.length) {
      return false;
    }
    let difference = 0;
    for (let index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference === 0;
  }

  private encodeText(value: string): Uint8Array {
    return util.TextEncoder.create('utf-8').encodeInto(value);
  }

  private decodeText(value: Uint8Array): string {
    return util.TextDecoder.create('utf-8').decodeToString(value);
  }

  private toArrayBuffer(value: Uint8Array): ArrayBuffer {
    const copy = new Uint8Array(value.length);
    copy.set(value);
    return copy.buffer;
  }

  private requireClient(): ble.GattClientDevice {
    if (this.client === undefined) {
      throw new Error('BLE_NOT_CONNECTED');
    }
    return this.client;
  }

  private withTimeout<T>(operation: Promise<T>, errorCode: string): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      let completed = false;
      let timer: number = -1;
      const abort = (): void => {
        if (completed) return;
        completed = true;
        if (timer >= 0) clearTimeout(timer);
        this.removeOperationAbortListener(abort);
        reject(new Error(`BLE_LINK_LOST:${errorCode}`));
      };
      this.operationAbortListeners.push(abort);
      timer = setTimeout(() => {
        if (completed) {
          return;
        }
        completed = true;
        this.removeOperationAbortListener(abort);
        reject(new Error(errorCode));
      }, BleProvisioningService.OPERATION_TIMEOUT_MS);
      operation.then((value: T) => {
        if (completed) {
          return;
        }
        completed = true;
        clearTimeout(timer);
        this.removeOperationAbortListener(abort);
        resolve(value);
      }).catch((error: Object) => {
        if (completed) {
          return;
        }
        completed = true;
        clearTimeout(timer);
        this.removeOperationAbortListener(abort);
        reject(error);
      });
    });
  }

  private removeOperationAbortListener(listener: () => void): void {
    const next: Array<() => void> = [];
    for (let index = 0; index < this.operationAbortListeners.length; index++) {
      if (this.operationAbortListeners[index] !== listener) next.push(this.operationAbortListeners[index]);
    }
    this.operationAbortListeners = next;
  }

  private abortActiveOperations(): void {
    const listeners = this.operationAbortListeners;
    this.operationAbortListeners = [];
    for (let index = 0; index < listeners.length; index++) listeners[index]();
  }

  private progress(
    listener: BleProvisioningProgressListener | undefined,
    stage: string,
    message: string,
    percent: number
  ): void {
    if (listener !== undefined) {
      listener({
        stage: stage,
        message: message,
        percent: Math.max(0, Math.min(100, percent))
      });
    }
  }

  private failure(message: string, errorCode: string = '', failedStage: string = ''): BleProvisioningResult {
    return {
      success: false,
      message: message,
      ipAddress: '',
      expectedGatewayId: '',
      expectedGatewayName: '',
      protocolVersion: '',
      errorCode: errorCode.length === 0 ? undefined : errorCode,
      failedStage: failedStage.length === 0 ? undefined : failedStage
    };
  }

  private diagnosticCode(error: Object): string {
    const raw = this.errorDescription(error).replace('Error:', '').trim();
    if (raw.indexOf('BLE_BUSINESS_ERROR:') === 0) {
      const fields = raw.split(':');
      return fields.length > 1 ? `BLE_BUSINESS_ERROR_${fields[1]}` : 'BLE_BUSINESS_ERROR';
    }
    const separator = raw.indexOf(':');
    const code = separator < 0 ? raw : raw.substring(0, separator);
    return code.length === 0 ? 'BLE_UNKNOWN' : code;
  }

  private mapFailure(error: Object): string {
    const message = this.errorDescription(error);
    if (message.indexOf('BLE_PERMISSION_DENIED') >= 0) {
      return I18nService.t('需要授予蓝牙访问权限才能配置网关');
    }
    if (message.indexOf('BLUETOOTH_DISABLED') >= 0) {
      return I18nService.t('请先打开手机蓝牙');
    }
    if (message.indexOf('PROOF_OF_POSSESSION_REJECTED') >= 0) {
      return I18nService.t('配网码校验失败，请检查网关 PoP');
    }
    if (message.indexOf('SECURITY_VERSION_UNSUPPORTED') >= 0) {
      return I18nService.t('网关未启用 ESP-IDF Security1，无法安全配网');
    }
    if (message.indexOf('PROVISIONING_ENDPOINTS_INCOMPLETE') >= 0) {
      return I18nService.t('该设备不是兼容的 YaoCore 配网网关');
    }
    if (message.indexOf('PROVISIONING_IDENTITY_INVALID') >= 0) {
      return I18nService.t('未能在安全会话内确认网关身份，已停止配网');
    }
    if (message.indexOf('BLE_CONNECTION_TIMEOUT') >= 0) {
      return I18nService.t('连接网关超时，请靠近开发板后重试');
    }
    if (message.indexOf('BLE_MTU_') >= 0) {
      return I18nService.t('蓝牙数据长度协商失败，当前连接无法完整传输配网数据');
    }
    if (message.indexOf('GATT_') >= 0 && message.indexOf('_TIMEOUT') >= 0) {
      return I18nService.t('蓝牙通信超时，请靠近网关后重试');
    }
    if (message.indexOf('WIFI_CONFIG_REJECTED') >= 0) {
      return I18nService.t('网关拒绝了 Wi-Fi 配置');
    }
    return I18nService.t('BLE 配网失败，请让网关重新进入配网模式后重试');
  }

  private errorDescription(error: Object): string {
    const businessError = error as BusinessError;
    const raw = `${error}`;
    // Harmony Bluetooth APIs can reject with a plain BusinessError object.
    // String interpolation then produces only "[object Object]", so preserve
    // its numeric code and optional message for diagnosis and classification.
    if (raw === '[object Object]' && businessError.code !== undefined) {
      const detail = businessError.message !== undefined ? businessError.message : '';
      return `BLE_BUSINESS_ERROR:${businessError.code}:${detail}`;
    }
    if (businessError.message !== undefined && businessError.message.length > 0) {
      return businessError.message;
    }
    if (raw.length > 0 && raw !== '[object Object]') {
      return raw;
    }
    if (businessError.code !== undefined) {
      return `BLE_BUSINESS_ERROR:${businessError.code}`;
    }
    return 'BLE_UNKNOWN';
  }

  private isExpectedProvisioningTransportRelease(error: Object): boolean {
    const message = this.errorDescription(error);
    return message.indexOf('BLE_LINK_LOST') >= 0 ||
      message.indexOf('BLE_NOT_CONNECTED') >= 0 ||
      message.indexOf('BLE_CONNECTION_FAILED') >= 0 ||
      message.indexOf('GATT_READ_TIMEOUT:prov-config') >= 0 ||
      message.indexOf('GATT_WRITE_TIMEOUT:prov-config') >= 0 ||
      message.indexOf('GATT_READ_TIMEOUT:yaocore-done') >= 0 ||
      message.indexOf('GATT_WRITE_TIMEOUT:yaocore-done') >= 0 ||
      message.indexOf('BLE_BUSINESS_ERROR:') >= 0;
  }

  private delay(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, milliseconds);
    });
  }
}
