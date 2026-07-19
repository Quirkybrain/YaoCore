/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from './I18nService';
import { DeviceIds, GatewayDefaults } from '../common/constants/DeviceConstants';
import { ControlResult, ControlRoute, DeviceControlCommand, DeviceReportedState } from '../common/types/CommandTypes';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import { NumberUtil } from '../common/utils/NumberUtil';
import { copyDeviceState, createDevicePlaceholder, DeviceAction, DeviceDraft, DeviceState, DeviceType } from '../model/DeviceModel';
import { CloudSyncResult } from '../model/CloudModel';
import { DiscoveredDevice, DiscoveredGateway, DiscoveryResult, GatewayState } from '../model/GatewayModel';
import { AppStorageService } from './AppStorageService';
import { GatewayDiscoveryService } from './GatewayDiscoveryService';
import { NetworkService } from './NetworkService';

export class DeviceRepository {
  private static instance: DeviceRepository | undefined;
  private networkService: NetworkService = NetworkService.getInstance();
  private gatewayDiscovery: GatewayDiscoveryService = GatewayDiscoveryService.getInstance();
  private devices: DeviceState[] = [];
  private loaded: boolean = false;
  private refreshInProgress: boolean = false;
  private monitorTimer: number = -1;
  private lastCloudSyncMs: number = 0;
  private lastBackgroundPersistMs: number = 0;
  private inventoryChangedSincePersist: boolean = false;
  /** Composite gateway/device keys currently executing a command. */
  private controllingDeviceIds: string[] = [];

  static getInstance(): DeviceRepository {
    if (DeviceRepository.instance === undefined) {
      DeviceRepository.instance = new DeviceRepository();
    }
    return DeviceRepository.instance;
  }

  async load(): Promise<void> {
    if (this.loaded) {
      return;
    }
    const hasStoredDevices = await AppStorageService.hasStoredDevices();
    const storedDevices = await AppStorageService.loadDevices();
    if (hasStoredDevices) {
      this.devices = storedDevices;
    }
    await this.networkService.loadCloudConfig();
    this.loaded = true;
  }

  getGateway(): GatewayState {
    return this.gatewayDiscovery.getGateway();
  }

  getBoundGatewayId(): string {
    const value = this.networkService.getLocalRouteConfig().gatewayId;
    return value === undefined ? '' : value;
  }

  async refreshGateway(): Promise<GatewayState> {
    return await this.networkService.refreshGateway();
  }

  getDevices(): DeviceState[] {
    const result: DeviceState[] = [];
    for (let index = 0; index < this.devices.length; index++) {
      if (this.belongsToActiveHome(this.devices[index])) {
        result.push(copyDeviceState(this.devices[index]));
      }
    }
    return result;
  }

  getDevice(deviceId: string): DeviceState {
    const device = this.findActiveMutable(deviceId);
    if (device !== undefined) {
      return copyDeviceState(device);
    }
    return createDevicePlaceholder(deviceId, I18nService.t('未绑定设备'));
  }

  hasDevice(deviceId: string): boolean {
    return this.findActiveMutable(deviceId) !== undefined;
  }

  getDevicesByType(type: DeviceType): DeviceState[] {
    const result: DeviceState[] = [];
    for (let index = 0; index < this.devices.length; index++) {
      if (this.devices[index].deviceType === type && this.belongsToActiveHome(this.devices[index])) {
        result.push(copyDeviceState(this.devices[index]));
      }
    }
    return result;
  }

  async control(command: DeviceControlCommand): Promise<ControlResult> {
    const validation = this.validateCommand(command);
    if (validation !== undefined) {
      return validation;
    }
    const busyKey = this.deviceOperationKey(command.targetDevice);
    if (this.isDeviceBusy(busyKey)) {
      return this.rejectedControl(I18nService.t('设备正在执行上一条指令，请稍候'), 'DEVICE_BUSY');
    }
    const normalized = this.normalizeCommand(command);
    this.controllingDeviceIds.push(busyKey);
    try {
      const result = await this.networkService.controlDevice(normalized);
      if (result.acknowledged === true && result.reportedState !== undefined) {
        // 失败ACK仍可能携带可信的离线/未知状态，必须回写但不能把命令标成成功。
        this.applyReportedState(result.reportedState);
        await this.persistDevices();
      }
      if (result.success && result.confirmed === true) {
        if (result.reportedState !== undefined && result.acknowledged !== true) {
          this.applyReportedState(result.reportedState);
        } else {
          if (result.reportedState === undefined) {
            this.applyCommand(normalized);
          }
        }
        await this.persistDevices();
      }
      return result;
    } finally {
      this.removeBusyDevice(busyKey);
    }
  }

  /** 场景在下发第一条命令前使用同一套规则验证全部动作。 */
  preflightControl(command: DeviceControlCommand): ControlResult | undefined {
    return this.validateCommand(command);
  }

  private validateCommand(command: DeviceControlCommand): ControlResult | undefined {
    if (command.targetDevice.trim().length === 0) {
      return this.rejectedControl(I18nService.t('请先发现并绑定设备'), 'DEVICE_NOT_BOUND');
    }
    const target = this.findActiveMutable(command.targetDevice);
    if (target === undefined) {
      return this.rejectedControl(I18nService.t('目标设备不存在或已被删除'), 'DEVICE_NOT_FOUND');
    }
    if (target.protocol === 'manual' || target.gatewayId === undefined || target.gatewayId.trim().length === 0) {
      return this.rejectedControl(I18nService.t('该设备是待绑定离线占位，请先通过网关发现并绑定真实设备'), 'DEVICE_PENDING_BINDING');
    }
    const route = this.networkService.getLocalRouteConfig();
    const boundGatewayId = route.gatewayId === undefined ? '' : route.gatewayId.trim();
    if (boundGatewayId.length === 0) {
      return this.rejectedControl(I18nService.t('尚未绑定控制网关，未下发控制指令'), 'GATEWAY_NOT_BOUND');
    }
    if (target.gatewayId.trim() !== boundGatewayId) {
      return this.rejectedControl(I18nService.t('该设备属于另一网关，请重新发现并绑定后再控制'), 'DEVICE_GATEWAY_MISMATCH');
    }
    const action = command.action;
    const metadataAction = action === DeviceAction.SET_DEVICE_NAME || action === DeviceAction.SET_DEVICE_ROOM;
    if (metadataAction) {
      const value = typeof command.value === 'string' ? command.value.trim() : '';
      const maximum = action === DeviceAction.SET_DEVICE_NAME ? 20 : 10;
      if (value.length === 0 || value.length > maximum) {
        return this.rejectedControl(I18nService.isChinese() ?
          (action === DeviceAction.SET_DEVICE_NAME ? '设备名称需要 1 到 20 个字符' : '房间名称需要 1 到 10 个字符') :
          (action === DeviceAction.SET_DEVICE_NAME ? 'Device name must contain 1 to 20 characters' :
            'Room name must contain 1 to 10 characters'), 'INVALID_METADATA');
      }
      return undefined;
    }
    if (!target.isOnline) {
      return this.rejectedControl(I18nService.t('设备当前离线，未下发控制指令'), 'DEVICE_OFFLINE');
    }
    if (target.deviceType === DeviceType.SENSOR || target.deviceType === DeviceType.CAMERA) {
      return this.rejectedControl(I18nService.t('该设备当前只支持状态读取'), 'DEVICE_READ_ONLY');
    }
    if (target.deviceType === DeviceType.DOOR && action !== DeviceAction.OPEN && action !== DeviceAction.CLOSE) {
      return this.rejectedControl(I18nService.t('门禁不支持该控制动作'), 'ACTION_NOT_SUPPORTED');
    }
    if (target.deviceType === DeviceType.LIGHT && action !== DeviceAction.TURN_ON &&
      action !== DeviceAction.TURN_OFF && action !== DeviceAction.SET_BRIGHTNESS &&
      action !== DeviceAction.SET_COLOR) {
      return this.rejectedControl(I18nService.t('灯光不支持该控制动作'), 'ACTION_NOT_SUPPORTED');
    }
    if (action === DeviceAction.SET_COLOR && target.color === undefined) {
      return this.rejectedControl(I18nService.t('该灯不支持颜色控制'), 'ACTION_NOT_SUPPORTED');
    }
    if (target.deviceType === DeviceType.AC && action !== DeviceAction.TURN_ON && action !== DeviceAction.TURN_OFF &&
      action !== DeviceAction.SET_TARGET_TEMPERATURE && action !== DeviceAction.SET_MODE) {
      return this.rejectedControl(I18nService.t('空调不支持该控制动作'), 'ACTION_NOT_SUPPORTED');
    }
    if (target.deviceType === DeviceType.CURTAIN && action !== DeviceAction.SET_POSITION && action !== DeviceAction.STOP) {
      return this.rejectedControl(I18nService.t('设备不支持该控制动作'), 'ACTION_NOT_SUPPORTED');
    }
    if (target.deviceType === DeviceType.FAN && action !== DeviceAction.TURN_ON && action !== DeviceAction.TURN_OFF &&
      action !== DeviceAction.SET_SPEED) {
      return this.rejectedControl(I18nService.t('设备不支持该控制动作'), 'ACTION_NOT_SUPPORTED');
    }
    if (target.deviceType === DeviceType.SPEAKER && action !== DeviceAction.TURN_ON && action !== DeviceAction.TURN_OFF &&
      action !== DeviceAction.SET_VOLUME) {
      return this.rejectedControl(I18nService.t('设备不支持该控制动作'), 'ACTION_NOT_SUPPORTED');
    }
    const valueMustBeAbsent = action === DeviceAction.OPEN || action === DeviceAction.CLOSE ||
      action === DeviceAction.TURN_ON || action === DeviceAction.TURN_OFF || action === DeviceAction.STOP;
    if (valueMustBeAbsent && command.value !== undefined) {
      return this.rejectedControl(I18nService.t('该开关动作不接受额外参数'), 'INVALID_COMMAND_VALUE');
    }
    if (action === DeviceAction.SET_BRIGHTNESS && (typeof command.value !== 'number' ||
      !Number.isFinite(command.value) || command.value < 0 || command.value > 100)) {
      return this.rejectedControl(I18nService.t('亮度必须是 0 到 100 的数字'), 'INVALID_COMMAND_VALUE');
    }
    if (action === DeviceAction.SET_COLOR && (typeof command.value !== 'string' ||
      !this.isColorHex(command.value))) {
      return this.rejectedControl(I18nService.t('颜色必须是 #RRGGBB 格式'), 'INVALID_COMMAND_VALUE');
    }
    if ((action === DeviceAction.SET_POSITION || action === DeviceAction.SET_SPEED ||
      action === DeviceAction.SET_VOLUME) && (typeof command.value !== 'number' ||
      !Number.isFinite(command.value) || command.value < 0 || command.value > 100)) {
      return this.rejectedControl(I18nService.t('控制值必须是 0 到 100 的数字'), 'INVALID_COMMAND_VALUE');
    }
    if (action === DeviceAction.SET_TARGET_TEMPERATURE && (typeof command.value !== 'number' ||
      !Number.isFinite(command.value) || command.value < 16 || command.value > 30)) {
      return this.rejectedControl(I18nService.t('目标温度必须是 16 到 30 的数字'), 'INVALID_COMMAND_VALUE');
    }
    if (action === DeviceAction.SET_MODE && (typeof command.value !== 'string' ||
      this.toWireMode(command.value) === undefined)) {
      return this.rejectedControl(I18nService.t('空调模式仅支持自动、制冷、制热、除湿、送风、节能或睡眠'),
        'INVALID_COMMAND_VALUE');
    }
    return undefined;
  }

  private normalizeCommand(command: DeviceControlCommand): DeviceControlCommand {
    let value = command.value;
    if (command.action === DeviceAction.SET_BRIGHTNESS && typeof value === 'number') {
      value = NumberUtil.clamp(value, 0, 100);
    } else if (command.action === DeviceAction.SET_COLOR && typeof value === 'string') {
      value = value.toUpperCase();
    } else if (command.action === DeviceAction.SET_TARGET_TEMPERATURE && typeof value === 'number') {
      value = NumberUtil.clamp(value, 16, 30);
    } else if (command.action === DeviceAction.SET_MODE && typeof value === 'string') {
      const mode = this.toWireMode(value);
      value = mode === undefined ? value.trim() : mode;
    } else if ((command.action === DeviceAction.SET_DEVICE_NAME ||
      command.action === DeviceAction.SET_DEVICE_ROOM) && typeof value === 'string') {
      value = value.trim();
    }
    return {
      targetDevice: command.targetDevice.trim(),
      action: command.action,
      value: value,
      extra: command.extra
    };
  }

  private rejectedControl(message: string, errorCode: string): ControlResult {
    return {
      success: false,
      route: ControlRoute.OFFLINE,
      message: message,
      latencyMs: 0,
      confirmed: false,
      attempts: 0,
      errorCode: errorCode
    };
  }

  private isDeviceBusy(deviceId: string): boolean {
    return this.controllingDeviceIds.indexOf(deviceId) >= 0;
  }

  private removeBusyDevice(deviceId: string): void {
    const next: string[] = [];
    for (let index = 0; index < this.controllingDeviceIds.length; index++) {
      if (this.controllingDeviceIds[index] !== deviceId) {
        next.push(this.controllingDeviceIds[index]);
      }
    }
    this.controllingDeviceIds = next;
  }

  async addDevice(draft: DeviceDraft): Promise<DeviceState> {
    const device = this.createDeviceFromDraft(draft);
    this.devices.push(device);
    await this.persistDevices();
    return copyDeviceState(device);
  }

  async bindDiscoveredDevice(discovered: DiscoveredDevice): Promise<DeviceState> {
    let existing = this.findMutable(discovered.deviceId, discovered.gatewayId);
    if (existing === undefined) {
      existing = this.findUniquePendingPlaceholder(discovered);
    }
    if (existing !== undefined) {
      existing.deviceId = discovered.deviceId;
      existing.deviceName = discovered.deviceName;
      existing.roomName = discovered.roomName;
      existing.deviceType = discovered.deviceType;
      existing.brand = discovered.brand;
      existing.gatewayId = discovered.gatewayId;
      existing.localIp = discovered.localIp;
      existing.protocol = discovered.protocol;
      existing.isOnline = discovered.isOnline === undefined ? true : discovered.isOnline;
      this.applyDiscoveredStatus(existing, discovered);
      await this.persistDevices();
      return copyDeviceState(existing);
    }

    const device = this.createDeviceFromDraft({
      deviceName: discovered.deviceName,
      roomName: discovered.roomName,
      deviceType: discovered.deviceType,
      brand: discovered.brand,
      gatewayId: discovered.gatewayId,
      localIp: discovered.localIp,
      protocol: discovered.protocol
    }, discovered.deviceId);
    device.isOnline = discovered.isOnline === undefined ? true : discovered.isOnline;
    this.applyDiscoveredStatus(device, discovered);
    this.devices.push(device);
    await this.persistDevices();
    return copyDeviceState(device);
  }

  async bindGateway(gateway: DiscoveredGateway): Promise<ControlResult> {
    const route = this.networkService.getLocalRouteConfig();
    const previousGatewayId = route.gatewayId === undefined ? '' : route.gatewayId;
    const result = await this.networkService.bindGateway(gateway);
    if (result.success && result.confirmed === true && previousGatewayId.length > 0 &&
      previousGatewayId !== gateway.gatewayId) {
      // 同一 deviceId 在不同厂商/家庭网关下并不代表同一物理设备。切换后保留记录但隔离为离线，
      // 直到用户从新网关重新发现并绑定，避免把 A 的 Door_01 缓存动作发给 B 的 Door_01。
      this.markGatewayDevicesOffline(previousGatewayId);
      await this.persistDevices();
    }
    if (result.success && result.confirmed === true) {
      // 绑定的是经过 BLE 身份和 HTTP HMAC 双重确认的网关；其设备清单是该家庭的
      // 权威库存。自动纳管后，后续新增传感器无需用户逐台点击“添加”才能追踪状态。
      const discovery = await this.gatewayDiscovery.checkConfiguredGateway(gateway.localIp, gateway.port);
      if (discovery.gateway.localAvailable && discovery.gateway.gatewayId === gateway.gatewayId) {
        const reconciled = this.reconcileGatewayInventory(discovery.devices, gateway.gatewayId);
        if (reconciled > 0) await this.persistDevices();
      }
    }
    return result;
  }

  async unbindGateway(gatewayId: string): Promise<string[] | undefined> {
    const expected = gatewayId.trim();
    if (expected.length === 0 || this.getBoundGatewayId().trim() !== expected) {
      return undefined;
    }
    const removedDeviceIds: string[] = [];
    const retained: DeviceState[] = [];
    for (let index = 0; index < this.devices.length; index++) {
      const deviceGatewayId = this.devices[index].gatewayId === undefined ? '' : this.devices[index].gatewayId as string;
      if (deviceGatewayId.trim() === expected && this.devices[index].protocol !== 'manual') {
        removedDeviceIds.push(this.devices[index].deviceId);
      } else {
        retained.push(this.devices[index]);
      }
    }
    const routeCleared = await this.networkService.unbindGateway(expected);
    if (!routeCleared) {
      return undefined;
    }
    this.devices = retained;
    this.controllingDeviceIds = [];
    await this.persistDevices();
    return removedDeviceIds;
  }

  async removeDevice(deviceId: string): Promise<DeviceState | undefined> {
    const next: DeviceState[] = [];
    let removed: DeviceState | undefined = undefined;
    for (let index = 0; index < this.devices.length; index++) {
      if (this.devices[index].deviceId !== deviceId || !this.belongsToActiveHome(this.devices[index])) {
        next.push(this.devices[index]);
      } else {
        removed = copyDeviceState(this.devices[index]);
      }
    }
    if (removed !== undefined) {
      this.devices = next;
      await this.persistDevices();
    }
    return removed;
  }

  async scanLanDevices(): Promise<DiscoveryResult> {
    const result = await this.gatewayDiscovery.scanLanDevices();
    const current = this.networkService.getLocalRouteConfig();
    if (result.gateway.localAvailable && current.gatewayId !== undefined && current.gatewayId.length > 0 &&
      result.gateway.gatewayId === current.gatewayId) {
      await this.networkService.saveLocalRoute({
        localEnabled: true,
        gatewayIp: result.gateway.localIp,
        gatewayPort: result.gateway.port === undefined ? current.gatewayPort : result.gateway.port,
        realTransportEnabled: true,
        gatewayId: result.gateway.gatewayId,
        gatewayName: result.gateway.gatewayName
      });
    } else if (!result.gateway.localAvailable && current.gatewayId !== undefined && current.gatewayId.length > 0) {
      this.networkService.setLocalRoute(false, result.gateway.localIp);
      if (result.gateway.failureCount !== undefined && result.gateway.failureCount >= 2) {
        this.markGatewayDevicesOffline(result.gateway.gatewayId);
      }
    }
    const boundGatewayId = current.gatewayId === undefined ? '' : current.gatewayId;
    const boundDevices = this.devicesForGateway(result.devices, boundGatewayId);
    const canApplyBoundState = boundGatewayId.length > 0 && result.gateway.localAvailable &&
      result.gateway.gatewayId === boundGatewayId;
    const updatedCount = canApplyBoundState ? this.reconcileGatewayInventory(boundDevices, boundGatewayId) : 0;
    const offlineCount = canApplyBoundState ?
      this.markMissingGatewayDevicesOffline(boundGatewayId, boundDevices) : 0;
    if (updatedCount > 0 || offlineCount > 0) {
      await this.persistDevices();
      result.message = `${result.message}，已回写 ${updatedCount} 台设备状态`;
      if (offlineCount > 0) {
        result.message = `${result.message}，${offlineCount} 台设备已离线`;
      }
    }
    return result;
  }

  /**
   * BLE Security1 已确认 gatewayId 后，只接受指定 IP 上通过 HTTP HMAC 校验且
   * gatewayId 完全一致的网关。此方法不保存路由，也不会绑定相邻的其他网关。
   */
  async probeProvisionedGateway(ip: string, expectedGatewayId: string): Promise<DiscoveredGateway | undefined> {
    const normalizedIp = ip.trim();
    const normalizedGatewayId = expectedGatewayId.trim();
    if (normalizedIp.length === 0 || normalizedGatewayId.length === 0) {
      return undefined;
    }
    const outcome = await this.gatewayDiscovery.probeConfiguredGatewayDetailed(normalizedIp, GatewayDefaults.LOCAL_PORT);
    if (outcome.result === undefined) {
      if (outcome.errorCode === 'COMMAND_KEY_MISMATCH' ||
        outcome.errorCode === 'RESPONSE_SIGNATURE_INVALID' ||
        outcome.errorCode === 'GATEWAY_PAYLOAD_INVALID') {
        throw new Error(outcome.errorCode);
      }
      return undefined;
    }
    const result = outcome.result as DiscoveryResult;
    if (result.gateways === undefined) return undefined;
    for (let index = 0; index < result.gateways.length; index++) {
      const gateway = result.gateways[index];
      if (gateway.gatewayId === normalizedGatewayId && gateway.localIp === normalizedIp && gateway.secureTransport) {
        return gateway;
      }
    }
    if (result.gateway.gatewayId !== normalizedGatewayId) {
      throw new Error('GATEWAY_ID_MISMATCH');
    }
    return undefined;
  }

  /** IP 缺失或 DHCP 地址尚未可达时的安全兜底；有限候选仍须精确匹配 BLE 身份。 */
  async scanProvisionedGateway(expectedGatewayId: string): Promise<DiscoveredGateway | undefined> {
    const normalizedGatewayId = expectedGatewayId.trim();
    if (normalizedGatewayId.length === 0) {
      return undefined;
    }
    return await this.gatewayDiscovery.scanProvisionedGateway(normalizedGatewayId);
  }

  async syncGatewayStatus(): Promise<DiscoveryResult> {
    return await this.scanLanDevices();
  }

  async syncDevicesToCloud(): Promise<CloudSyncResult> {
    const result = await this.networkService.syncDevices(this.getDevices());
    if (result.success && result.reportedStates !== undefined) {
      for (let index = 0; index < result.reportedStates.length; index++) {
        this.applyReportedState(result.reportedStates[index]);
      }
      if (result.reportedStates.length > 0) {
        await this.persistDevices();
      }
    }
    return result;
  }

  private applyCommand(command: DeviceControlCommand): void {
    const target = this.findActiveMutable(command.targetDevice);
    if (target === undefined) {
      return;
    }

    if (command.action === DeviceAction.OPEN) {
      target.openStatus = true;
    } else if (command.action === DeviceAction.CLOSE) {
      target.openStatus = false;
    } else if (command.action === DeviceAction.TURN_ON) {
      target.powerStatus = true;
    } else if (command.action === DeviceAction.TURN_OFF) {
      target.powerStatus = false;
    } else if (command.action === DeviceAction.SET_BRIGHTNESS && typeof command.value === 'number') {
      target.brightness = NumberUtil.clamp(command.value, 0, 100);
      target.powerStatus = target.brightness > 0;
    } else if (command.action === DeviceAction.SET_COLOR && typeof command.value === 'string') {
      target.color = command.value.toUpperCase();
    } else if (command.action === DeviceAction.SET_TARGET_TEMPERATURE && typeof command.value === 'number') {
      target.targetTemperature = NumberUtil.clamp(command.value, 16, 30);
      target.powerStatus = true;
    } else if (command.action === DeviceAction.SET_MODE && typeof command.value === 'string') {
      target.mode = this.displayMode(command.value);
    } else if (command.action === DeviceAction.SET_DEVICE_NAME && typeof command.value === 'string') {
      target.deviceName = command.value.trim();
    } else if (command.action === DeviceAction.SET_DEVICE_ROOM && typeof command.value === 'string') {
      target.roomName = command.value.trim();
    }

    target.updatedAt = DateTimeUtil.nowDisplay();
    target.stateEpochMs = new Date().getTime();
  }

  private applyDiscoveredStatuses(discovered: DiscoveredDevice[], gatewayId: string = ''): number {
    let updatedCount = 0;
    for (let index = 0; index < discovered.length; index++) {
      if (gatewayId.length > 0 && discovered[index].gatewayId !== gatewayId) {
        continue;
      }
      const target = this.findMutable(discovered[index].deviceId, discovered[index].gatewayId);
      if (target !== undefined) {
        this.applyDiscoveredStatus(target, discovered[index]);
        updatedCount += 1;
      }
    }
    return updatedCount;
  }

  private applyDiscoveredStatus(target: DeviceState, discovered: DiscoveredDevice): void {
    const incomingEpoch = DateTimeUtil.parseUtcToMillis(discovered.lastSeenAt);
    if (!Number.isNaN(incomingEpoch) && target.stateEpochMs !== undefined && incomingEpoch < target.stateEpochMs) {
      return;
    }
    if (discovered.isOnline !== undefined) {
      target.isOnline = discovered.isOnline;
    }
    if (discovered.powerStatus !== undefined) {
      target.powerStatus = discovered.powerStatus;
    }
    if (discovered.openStatus !== undefined) {
      target.openStatus = discovered.openStatus;
    }
    if (discovered.brightness !== undefined) {
      target.brightness = NumberUtil.clamp(discovered.brightness, 0, 100);
    }
    if (discovered.color !== undefined && this.isColorHex(discovered.color)) {
      target.color = discovered.color.toUpperCase();
    }
    if (discovered.position !== undefined) {
      target.position = NumberUtil.clamp(discovered.position, 0, 100);
    }
    if (discovered.speed !== undefined) {
      target.speed = NumberUtil.clamp(discovered.speed, 0, 100);
    }
    if (discovered.volume !== undefined) {
      target.volume = NumberUtil.clamp(discovered.volume, 0, 100);
    }
    if (discovered.temperature !== undefined) {
      target.temperature = discovered.temperature;
    }
    if (discovered.humidity !== undefined) {
      target.humidity = discovered.humidity;
    }
    if (discovered.presence !== undefined) {
      target.presence = discovered.presence;
    }
    if (discovered.targetTemperature !== undefined) {
      target.targetTemperature = NumberUtil.clamp(discovered.targetTemperature, 16, 30);
    }
    if (discovered.mode !== undefined && discovered.mode.length > 0) {
      target.mode = this.displayMode(discovered.mode);
    }
    this.normalizeLightPowerState(target);
    if (discovered.stateSource !== undefined) target.stateSource = discovered.stateSource;
    if (discovered.triggerDeviceId !== undefined) target.triggerDeviceId = discovered.triggerDeviceId;
    if (discovered.automationId !== undefined) target.automationId = discovered.automationId;
    target.updatedAt = discovered.lastSeenAt;
    target.stateEpochMs = Number.isNaN(incomingEpoch) ? new Date().getTime() : incomingEpoch;
  }

  private applyReportedState(state: DeviceReportedState): void {
    const gatewayId = this.getBoundGatewayId();
    if (state.gatewayId !== undefined && state.gatewayId.trim().length > 0 &&
      state.gatewayId.trim() !== gatewayId) {
      return;
    }
    let target = gatewayId.length === 0 ? undefined : this.findMutable(state.deviceId, gatewayId);
    if (target === undefined) target = this.createKnownCloudDevice(state);
    if (target === undefined) {
      return;
    }
    const incomingEpoch = state.eventTime === undefined ? Number.NaN : DateTimeUtil.parseUtcToMillis(state.eventTime);
    if (!Number.isNaN(incomingEpoch) && target.stateEpochMs !== undefined && incomingEpoch < target.stateEpochMs) {
      return;
    }
    if (state.online !== undefined) target.isOnline = state.online;
    if (state.power !== undefined) target.powerStatus = state.power;
    if (state.open !== undefined) target.openStatus = state.open;
    if (state.brightness !== undefined) target.brightness = NumberUtil.clamp(state.brightness, 0, 100);
    if (state.color !== undefined && this.isColorHex(state.color)) target.color = state.color.toUpperCase();
    if (state.position !== undefined) target.position = NumberUtil.clamp(state.position, 0, 100);
    if (state.speed !== undefined) target.speed = NumberUtil.clamp(state.speed, 0, 100);
    if (state.volume !== undefined) target.volume = NumberUtil.clamp(state.volume, 0, 100);
    if (state.temperature !== undefined) target.temperature = state.temperature;
    if (state.humidity !== undefined) target.humidity = state.humidity;
    if (state.presence !== undefined) target.presence = state.presence;
    if (state.targetTemperature !== undefined) {
      target.targetTemperature = NumberUtil.clamp(state.targetTemperature, 16, 30);
    }
    if (state.mode !== undefined && state.mode.length > 0) target.mode = this.displayMode(state.mode);
    this.normalizeLightPowerState(target);
    if (state.deviceName !== undefined && state.deviceName.trim().length > 0) {
      target.deviceName = state.deviceName.trim();
    }
    if (state.roomName !== undefined && state.roomName.trim().length > 0) {
      target.roomName = state.roomName.trim();
    }
    if (state.brand !== undefined && state.brand.trim().length > 0) target.brand = state.brand.trim();
    if (state.protocol !== undefined && state.protocol.trim().length > 0) target.protocol = state.protocol.trim();
    if (state.stateSource !== undefined) target.stateSource = state.stateSource;
    if (state.triggerDeviceId !== undefined) target.triggerDeviceId = state.triggerDeviceId;
    if (state.automationId !== undefined) target.automationId = state.automationId;
    target.updatedAt = state.eventTime === undefined || state.eventTime.length === 0 ? DateTimeUtil.nowDisplay() : state.eventTime;
    target.stateEpochMs = Number.isNaN(incomingEpoch) ? new Date().getTime() : incomingEpoch;
  }

  private normalizeLightPowerState(target: DeviceState): void {
    // A dimmable light at 0% is physically off. Keep list buttons, detail UI,
    // automation and cloud state on the same invariant even if a module sends
    // an inconsistent power flag in a discovery or ACK payload.
    if (target.deviceType === DeviceType.LIGHT && target.brightness !== undefined && target.brightness <= 0) {
      target.powerStatus = false;
    }
  }

  private createKnownCloudDevice(state: DeviceReportedState): DeviceState | undefined {
    const gatewayId = this.getBoundGatewayId();
    if (gatewayId.length === 0) return undefined;
    const deviceId = state.deviceId;
    let type: DeviceType;
    let name: string;
    let room = I18nService.t('客厅');
    if (deviceId === 'Door_01') {
      type = DeviceType.DOOR; name = I18nService.t('智能门禁'); room = I18nService.t('玄关');
    } else if (deviceId === 'Light_01') {
      type = DeviceType.LIGHT; name = I18nService.t('客厅灯光');
    } else if (deviceId === 'Sensor_01') {
      type = DeviceType.SENSOR; name = I18nService.t('温湿度传感器');
    } else if (deviceId === 'Presence_01') {
      type = DeviceType.SENSOR; name = I18nService.t('人体存在传感器');
    } else if (deviceId === 'AC_01') {
      type = DeviceType.AC; name = I18nService.t('智能空调');
    } else if (state.deviceType !== undefined) {
      const cloudType = state.deviceType.toLowerCase();
      if (cloudType === DeviceType.DOOR) type = DeviceType.DOOR;
      else if (cloudType === DeviceType.LIGHT) type = DeviceType.LIGHT;
      else if (cloudType === DeviceType.SENSOR) type = DeviceType.SENSOR;
      else if (cloudType === DeviceType.AC) type = DeviceType.AC;
      else if (cloudType === DeviceType.SWITCH) type = DeviceType.SWITCH;
      else if (cloudType === DeviceType.CAMERA) type = DeviceType.CAMERA;
      else if (cloudType === DeviceType.CURTAIN) type = DeviceType.CURTAIN;
      else if (cloudType === DeviceType.FAN) type = DeviceType.FAN;
      else if (cloudType === DeviceType.SPEAKER) type = DeviceType.SPEAKER;
      else return undefined;
      name = state.deviceName === undefined || state.deviceName.trim().length === 0 ?
        this.getTypeLabel(type) : state.deviceName.trim();
      if (state.roomName !== undefined && state.roomName.trim().length > 0) {
        room = state.roomName.trim();
      }
    } else {
      return undefined;
    }
    const device = this.createDeviceFromDraft({
      deviceName: name,
      roomName: room,
      deviceType: type,
      brand: state.brand,
      gatewayId: gatewayId,
      protocol: state.protocol === undefined || state.protocol.trim().length === 0 ?
        'YaoCore-IoTDA-v2' : state.protocol
    }, deviceId);
    device.isOnline = false;
    this.devices.push(device);
    return device;
  }

  private markGatewayDevicesOffline(gatewayId: string): void {
    for (let index = 0; index < this.devices.length; index++) {
      if (gatewayId.length === 0 || this.devices[index].gatewayId === gatewayId) {
        this.devices[index].isOnline = false;
        this.devices[index].updatedAt = DateTimeUtil.nowDisplay();
      }
    }
  }

  private markMissingGatewayDevicesOffline(gatewayId: string, discovered: DiscoveredDevice[]): number {
    let count = 0;
    for (let index = 0; index < this.devices.length; index++) {
      const device = this.devices[index];
      if (gatewayId.length > 0 && device.gatewayId !== gatewayId) {
        continue;
      }
      let found = false;
      for (let itemIndex = 0; itemIndex < discovered.length; itemIndex++) {
        if (discovered[itemIndex].deviceId === device.deviceId) {
          found = true;
          break;
        }
      }
      if (!found && device.isOnline) {
        device.isOnline = false;
        device.updatedAt = DateTimeUtil.nowDisplay();
        count += 1;
      }
    }
    return count;
  }

  private devicesForGateway(discovered: DiscoveredDevice[], gatewayId: string): DiscoveredDevice[] {
    const matched: DiscoveredDevice[] = [];
    if (gatewayId.length === 0) {
      return matched;
    }
    for (let index = 0; index < discovered.length; index++) {
      if (discovered[index].gatewayId === gatewayId) {
        matched.push(discovered[index]);
      }
    }
    return matched;
  }

  /**
   * Authenticated discovery is both state reconciliation and inventory sync.
   * A bound gateway may gain a physical sensor after initial setup; silently
   * ignoring it would make the App display an incomplete home.
   */
  private reconcileGatewayInventory(discovered: DiscoveredDevice[], gatewayId: string): number {
    let changedCount = 0;
    for (let index = 0; index < discovered.length; index++) {
      const item = discovered[index];
      if (gatewayId.length === 0 || item.gatewayId !== gatewayId) continue;
      let target = this.findMutable(item.deviceId, gatewayId);
      if (target === undefined) target = this.findUniquePendingPlaceholder(item);
      if (target === undefined) {
        target = this.createDeviceFromDraft({
          deviceName: item.deviceName,
          roomName: item.roomName,
          deviceType: item.deviceType,
          brand: item.brand,
          gatewayId: item.gatewayId,
          localIp: item.localIp,
          protocol: item.protocol
        }, item.deviceId);
        this.devices.push(target);
        this.inventoryChangedSincePersist = true;
      } else {
        target.deviceId = item.deviceId;
        target.deviceName = item.deviceName;
        target.roomName = item.roomName;
        target.deviceType = item.deviceType;
        target.brand = item.brand;
        target.gatewayId = item.gatewayId;
        target.localIp = item.localIp;
        target.protocol = item.protocol;
      }
      this.applyDiscoveredStatus(target, item);
      changedCount += 1;
    }
    return changedCount;
  }

  private findMutable(deviceId: string, gatewayId: string = ''): DeviceState | undefined {
    for (let index = 0; index < this.devices.length; index++) {
      if (this.devices[index].deviceId === deviceId &&
        (gatewayId.length === 0 || this.devices[index].gatewayId === gatewayId)) {
        return this.devices[index];
      }
    }
    return undefined;
  }

  /**
   * A physical device is identified by (gatewayId, deviceId), never by a
   * vendor-generated deviceId alone. Manual placeholders are local drafts and
   * remain visible until the active gateway discovers their physical peer.
   */
  private belongsToActiveHome(device: DeviceState): boolean {
    if (device.protocol === 'manual' || device.gatewayId === undefined || device.gatewayId.trim().length === 0) {
      return true;
    }
    const gatewayId = this.getBoundGatewayId().trim();
    return gatewayId.length > 0 && device.gatewayId.trim() === gatewayId;
  }

  private findActiveMutable(deviceId: string): DeviceState | undefined {
    const gatewayId = this.getBoundGatewayId().trim();
    if (gatewayId.length > 0) {
      const physical = this.findMutable(deviceId, gatewayId);
      if (physical !== undefined) {
        return physical;
      }
    }
    for (let index = 0; index < this.devices.length; index++) {
      const candidate = this.devices[index];
      if (candidate.deviceId === deviceId &&
        (candidate.protocol === 'manual' || candidate.gatewayId === undefined || candidate.gatewayId.trim().length === 0)) {
        return candidate;
      }
    }
    return undefined;
  }

  private deviceOperationKey(deviceId: string): string {
    return `${this.getBoundGatewayId().trim()}::${deviceId.trim()}`;
  }

  private findUniquePendingPlaceholder(discovered: DiscoveredDevice): DeviceState | undefined {
    let match: DeviceState | undefined = undefined;
    const discoveredName = discovered.deviceName.trim().toLowerCase();
    for (let index = 0; index < this.devices.length; index++) {
      const candidate = this.devices[index];
      if (candidate.protocol !== 'manual' || candidate.deviceType !== discovered.deviceType ||
        candidate.deviceName.trim().toLowerCase() !== discoveredName) {
        continue;
      }
      if (match !== undefined) {
        // 同名占位不做猜测，避免把真实设备绑定到错误的家庭条目。
        return undefined;
      }
      match = candidate;
    }
    return match;
  }

  private findFirstMutableByType(type: DeviceType): DeviceState | undefined {
    for (let index = 0; index < this.devices.length; index++) {
      if (this.devices[index].deviceType === type && this.belongsToActiveHome(this.devices[index])) {
        return this.devices[index];
      }
    }
    return undefined;
  }

  private createDeviceFromDraft(draft: DeviceDraft, fixedId: string = ''): DeviceState {
    const id = fixedId.length > 0 ? fixedId : this.createUniqueManualDeviceId();
    const device: DeviceState = {
      deviceId: id,
      deviceName: draft.deviceName.trim().length === 0 ? this.getTypeLabel(draft.deviceType) : draft.deviceName.trim(),
      roomName: draft.roomName.trim().length === 0 ? I18nService.t('未分区') : draft.roomName.trim(),
      deviceType: draft.deviceType,
      brand: draft.brand,
      gatewayId: draft.gatewayId,
      localIp: draft.localIp,
      protocol: draft.protocol === undefined ? 'manual' : draft.protocol,
      isOnline: draft.localIp !== undefined && draft.localIp.length > 0,
      updatedAt: DateTimeUtil.nowDisplay(),
      stateEpochMs: 0
    };
    this.applyInitialCapability(device);
    return device;
  }

  private createUniqueManualDeviceId(): string {
    const epoch = new Date().getTime();
    for (let attempt = 0; attempt < 16; attempt++) {
      const candidate = `Device_${epoch}_${Math.floor(Math.random() * 1000000)}`;
      let exists = false;
      for (let index = 0; index < this.devices.length; index++) {
        if (this.devices[index].deviceId === candidate) {
          exists = true;
          break;
        }
      }
      if (!exists) return candidate;
    }
    return `Device_${epoch}_${this.devices.length}`;
  }

  private applyInitialCapability(device: DeviceState): void {
    // 无论手动占位还是刚发现的实体，能力字段都必须等待网关/影子真实上报。
    // 这里不再填充门锁、亮度、温湿度、空调温度或电源的演示默认值。
  }

  private getTypeLabel(type: DeviceType): string {
    if (type === DeviceType.DOOR) {
      return I18nService.t('智能门禁');
    }
    if (type === DeviceType.LIGHT) {
      return I18nService.t('智能灯光');
    }
    if (type === DeviceType.SENSOR) {
      return I18nService.t('环境传感器');
    }
    if (type === DeviceType.AC) {
      return I18nService.t('智能空调');
    }
    if (type === DeviceType.CAMERA) {
      return I18nService.t('安防摄像头');
    }
    if (type === DeviceType.CURTAIN) return I18nService.isChinese() ? '智能窗帘' : 'Smart curtain';
    if (type === DeviceType.FAN) return I18nService.isChinese() ? '智能风扇' : 'Smart fan';
    if (type === DeviceType.SPEAKER) return I18nService.isChinese() ? '智能音箱' : 'Smart speaker';
    return I18nService.t('智能开关');
  }

  private displayMode(mode: string): string {
    const normalized = mode.trim().toUpperCase();
    if (normalized === 'AUTO') return I18nService.t('自动');
    if (normalized === 'COOL') return I18nService.t('制冷');
    if (normalized === 'HEAT') return I18nService.t('制热');
    if (normalized === 'DRY') return I18nService.t('除湿');
    if (normalized === 'FAN') return I18nService.t('送风');
    if (normalized === 'ECO') return I18nService.t('节能');
    if (normalized === 'SLEEP') return I18nService.t('睡眠');
    return mode;
  }

  /** 品牌适配器和场景最终都落到同一组稳定 wire 值，禁止把 UI 文案发给固件。 */
  private toWireMode(mode: string): string | undefined {
    const normalized = mode.trim().toUpperCase();
    // Accept canonical wire values plus both-language legacy values so scenes
    // created before this migration keep working after a language switch.
    if (normalized === 'AUTO' || normalized === '自动') return 'AUTO';
    if (normalized === 'COOL' || normalized === '制冷') return 'COOL';
    if (normalized === 'HEAT' || normalized === '制热') return 'HEAT';
    if (normalized === 'DRY' || normalized === '除湿') return 'DRY';
    if (normalized === 'FAN' || normalized === '送风') return 'FAN';
    if (normalized === 'ECO' || normalized === '节能') return 'ECO';
    if (normalized === 'SLEEP' || normalized === '睡眠') return 'SLEEP';
    return undefined;
  }

  private isColorHex(value: string): boolean {
    if (value.length !== 7 || value.charAt(0) !== '#') {
      return false;
    }
    for (let index = 1; index < value.length; index++) {
      const code = value.charCodeAt(index);
      const digit = code >= 48 && code <= 57;
      const upper = code >= 65 && code <= 70;
      const lower = code >= 97 && code <= 102;
      if (!digit && !upper && !lower) {
        return false;
      }
    }
    return true;
  }

  private async persistDevices(): Promise<void> {
    await AppStorageService.saveDevices(this.devices);
    this.inventoryChangedSincePersist = false;
    this.lastBackgroundPersistMs = new Date().getTime();
  }

  private async persistBackgroundState(): Promise<void> {
    const now = new Date().getTime();
    // 轮询状态保存在内存供界面即时读取；新增设备立即落盘，普通遥测最多每分钟落盘一次，
    // 避免 5 秒同步周期持续写 Preferences/闪存。
    if (this.inventoryChangedSincePersist || now - this.lastBackgroundPersistMs >= 60000) {
      await this.persistDevices();
    }
  }

  async refreshFromAvailableRoutes(): Promise<void> {
    if (this.refreshInProgress) {
      return;
    }
    this.refreshInProgress = true;
    try {
      const route = this.networkService.getLocalRouteConfig();
      const boundGatewayId = route.gatewayId === undefined ? '' : route.gatewayId.trim();
      // Discovery is a user-initiated onboarding action. Background monitoring must
      // never sweep the whole subnet before a gateway has been explicitly bound.
      if (!route.realTransportEnabled || boundGatewayId.length === 0) {
        return;
      }
      let localResult: DiscoveryResult;
      if (route.realTransportEnabled && route.gatewayId !== undefined && route.gatewayId.length > 0) {
        localResult = await this.gatewayDiscovery.checkConfiguredGateway(route.gatewayIp, route.gatewayPort);
        this.networkService.setLocalReachability(localResult.gateway.localAvailable &&
          localResult.gateway.gatewayId === route.gatewayId);
        const updatedCount = localResult.gateway.localAvailable &&
          localResult.gateway.gatewayId === route.gatewayId ?
          this.reconcileGatewayInventory(localResult.devices, route.gatewayId) : 0;
        const offlineCount = localResult.gateway.localAvailable ?
          this.markMissingGatewayDevicesOffline(route.gatewayId, localResult.devices) : 0;
        if (updatedCount > 0 || offlineCount > 0) {
          await this.persistBackgroundState();
        }
        if (!localResult.gateway.localAvailable && localResult.gateway.failureCount !== undefined &&
          localResult.gateway.failureCount >= 2) {
          this.markGatewayDevicesOffline(route.gatewayId);
          await this.persistDevices();
        }
      } else return;
      if (!localResult.gateway.localAvailable) {
        const now = new Date().getTime();
        if (now - this.lastCloudSyncMs >= 10000) {
          this.lastCloudSyncMs = now;
          await this.syncDevicesToCloud();
        }
      }
    } finally {
      this.refreshInProgress = false;
    }
  }

  startMonitoring(): void {
    if (this.monitorTimer >= 0) {
      return;
    }
    this.refreshFromAvailableRoutes();
    this.monitorTimer = setInterval(() => {
      this.refreshFromAvailableRoutes();
    }, 1200);
  }

  stopMonitoring(): void {
    if (this.monitorTimer < 0) {
      return;
    }
    clearInterval(this.monitorTimer);
    this.monitorTimer = -1;
  }
}
