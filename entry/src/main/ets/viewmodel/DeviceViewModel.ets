/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from '../service/I18nService';
import { AcAdapterFactory } from '../adapter/ac/AcAdapterFactory';
import { ControlResult, ControlRoute } from '../common/types/CommandTypes';
import { CloudSyncResult } from '../model/CloudModel';
import { DeviceAction, DeviceDraft, DeviceState, DeviceType } from '../model/DeviceModel';
import { DiscoveredDevice, DiscoveredGateway, DiscoveryResult, GatewayState } from '../model/GatewayModel';
import { SceneCleanupResult } from '../model/SceneModel';
import { DeviceRepository } from '../service/DeviceRepository';
import { SceneService } from '../service/SceneService';

export interface DeviceRemoveResult {
  removed: boolean;
  deviceName: string;
  sceneCleanup: SceneCleanupResult;
  message: string;
}

export interface GatewayRemoveResult {
  removed: boolean;
  removedDeviceCount: number;
  sceneCleanup: SceneCleanupResult;
  message: string;
}

export class DeviceViewModel {
  private repository: DeviceRepository = DeviceRepository.getInstance();
  private sceneService: SceneService = SceneService.getInstance();

  async load(): Promise<void> {
    await this.repository.load();
  }

  getAllDevices(): DeviceState[] {
    return this.repository.getDevices();
  }

  getBoundGatewayId(): string {
    return this.repository.getBoundGatewayId();
  }

  getGateway(): GatewayState {
    return this.repository.getGateway();
  }

  getDevicesByType(type: DeviceType): DeviceState[] {
    return this.repository.getDevicesByType(type);
  }

  async refreshLiveState(): Promise<void> {
    await this.repository.refreshFromAvailableRoutes();
  }

  async togglePower(device: DeviceState): Promise<ControlResult> {
    const powered = device.powerStatus === true &&
      !(device.deviceType === DeviceType.LIGHT && device.brightness !== undefined && device.brightness <= 0);
    if (device.deviceType === DeviceType.AC) {
      const adapter = AcAdapterFactory.create(device.brand, device.deviceId);
      return powered ? await adapter.powerOff() : await adapter.powerOn();
    }
    return await this.repository.control({
      targetDevice: device.deviceId,
      action: powered ? DeviceAction.TURN_OFF : DeviceAction.TURN_ON,
      extra: {
        source: 'device-list'
      }
    });
  }

  async toggleDoor(device: DeviceState): Promise<ControlResult> {
    return await this.repository.control({
      targetDevice: device.deviceId,
      action: device.openStatus === true ? DeviceAction.CLOSE : DeviceAction.OPEN,
      extra: {
        source: 'device-list'
      }
    });
  }

  async setBrightness(device: DeviceState, brightness: number): Promise<ControlResult> {
    return await this.repository.control({
      targetDevice: device.deviceId,
      action: DeviceAction.SET_BRIGHTNESS,
      value: brightness,
      extra: {
        source: 'device-list',
        brightness: brightness
      }
    });
  }

  async setColor(device: DeviceState, color: string): Promise<ControlResult> {
    const normalized = color.toUpperCase();
    return await this.repository.control({
      targetDevice: device.deviceId,
      action: DeviceAction.SET_COLOR,
      value: normalized,
      extra: {
        source: 'device-detail',
        color: normalized
      }
    });
  }

  async setTargetTemperature(device: DeviceState, temperature: number): Promise<ControlResult> {
    return await AcAdapterFactory.create(device.brand, device.deviceId).setTargetTemperature(temperature);
  }

  async setMode(device: DeviceState, mode: string): Promise<ControlResult> {
    return await AcAdapterFactory.create(device.brand, device.deviceId).setMode(mode);
  }

  async setPosition(device: DeviceState, position: number): Promise<ControlResult> {
    return await this.repository.control({
      targetDevice: device.deviceId,
      action: DeviceAction.SET_POSITION,
      value: position,
      extra: { source: 'device-detail', position: position }
    });
  }

  async stop(device: DeviceState): Promise<ControlResult> {
    return await this.repository.control({
      targetDevice: device.deviceId,
      action: DeviceAction.STOP,
      extra: { source: 'device-detail' }
    });
  }

  async setSpeed(device: DeviceState, speed: number): Promise<ControlResult> {
    return await this.repository.control({
      targetDevice: device.deviceId,
      action: DeviceAction.SET_SPEED,
      value: speed,
      extra: { source: 'device-detail', speed: speed }
    });
  }

  async setVolume(device: DeviceState, volume: number): Promise<ControlResult> {
    return await this.repository.control({
      targetDevice: device.deviceId,
      action: DeviceAction.SET_VOLUME,
      value: volume,
      extra: { source: 'device-detail', volume: volume }
    });
  }

  async updateMetadata(device: DeviceState, name: string, room: string): Promise<ControlResult> {
    let result: ControlResult | undefined = undefined;
    const normalizedName = name.trim();
    const normalizedRoom = room.trim();
    if (normalizedName !== device.deviceName) {
      result = await this.repository.control({
        targetDevice: device.deviceId,
        action: DeviceAction.SET_DEVICE_NAME,
        value: normalizedName,
        extra: { source: 'device-detail' }
      });
      if (!result.success) return result;
    }
    if (normalizedRoom !== device.roomName) {
      result = await this.repository.control({
        targetDevice: device.deviceId,
        action: DeviceAction.SET_DEVICE_ROOM,
        value: normalizedRoom,
        extra: { source: 'device-detail' }
      });
      if (!result.success) return result;
    }
    if (result !== undefined) return result;
    return {
      success: true,
      route: ControlRoute.LOCAL,
      message: I18nService.isChinese() ? '设备信息没有变化' : 'Device information is unchanged',
      latencyMs: 0,
      confirmed: true,
      attempts: 0
    };
  }

  async addDevice(draft: DeviceDraft): Promise<DeviceState> {
    return await this.repository.addDevice(draft);
  }

  async removeDevice(deviceId: string): Promise<DeviceRemoveResult> {
    const removedDevice = await this.repository.removeDevice(deviceId);
    const emptyCleanup: SceneCleanupResult = {
      removedActionCount: 0,
      affectedSceneNames: []
    };
    if (removedDevice === undefined) {
      return {
        removed: false,
        deviceName: '',
        sceneCleanup: emptyCleanup,
        message: I18nService.t('未找到要删除的设备')
      };
    }

    const removedGatewayId = removedDevice.gatewayId === undefined ? '' : removedDevice.gatewayId;
    const cleanup = await this.sceneService.removeDeviceActions(deviceId, removedGatewayId);
    let message = `${removedDevice.deviceName} 已删除`;
    if (cleanup.removedActionCount > 0) {
      message = `${message}，并从 ${cleanup.affectedSceneNames.join('、')} 中移除了 ${cleanup.removedActionCount} 条设备状态`;
    }
    return {
      removed: true,
      deviceName: removedDevice.deviceName,
      sceneCleanup: cleanup,
      message: message
    };
  }

  async scanLanDevices(): Promise<DiscoveryResult> {
    return await this.repository.scanLanDevices();
  }

  async probeProvisionedGateway(ip: string, expectedGatewayId: string): Promise<DiscoveredGateway | undefined> {
    return await this.repository.probeProvisionedGateway(ip, expectedGatewayId);
  }

  async scanProvisionedGateway(expectedGatewayId: string): Promise<DiscoveredGateway | undefined> {
    return await this.repository.scanProvisionedGateway(expectedGatewayId);
  }

  async bindDiscoveredDevice(device: DiscoveredDevice): Promise<DeviceState> {
    return await this.repository.bindDiscoveredDevice(device);
  }

  async bindGateway(gateway: DiscoveredGateway): Promise<ControlResult> {
    return await this.repository.bindGateway(gateway);
  }

  async removeGateway(gatewayId: string): Promise<GatewayRemoveResult> {
    const removedDeviceIds = await this.repository.unbindGateway(gatewayId);
    const emptyCleanup: SceneCleanupResult = { removedActionCount: 0, affectedSceneNames: [] };
    if (removedDeviceIds === undefined) {
      return {
        removed: false,
        removedDeviceCount: 0,
        sceneCleanup: emptyCleanup,
        message: I18nService.t('网关删除失败，绑定信息未更改')
      };
    }
    const cleanup = await this.sceneService.removeGatewayActions(gatewayId, removedDeviceIds);
    return {
      removed: true,
      removedDeviceCount: removedDeviceIds.length,
      sceneCleanup: cleanup,
      message: I18nService.t('网关已从本机删除')
    };
  }

  async syncDevicesToCloud(): Promise<CloudSyncResult> {
    return await this.repository.syncDevicesToCloud();
  }

  getTypeLabel(type: DeviceType): string {
    if (type === DeviceType.DOOR) {
      return I18nService.t('门禁');
    }
    if (type === DeviceType.LIGHT) {
      return I18nService.t('灯光');
    }
    if (type === DeviceType.SENSOR) {
      return I18nService.t('传感器');
    }
    if (type === DeviceType.AC) {
      return I18nService.t('空调');
    }
    if (type === DeviceType.CAMERA) {
      return I18nService.t('摄像头');
    }
    if (type === DeviceType.CURTAIN) {
      return I18nService.isChinese() ? '窗帘' : 'Curtain';
    }
    if (type === DeviceType.FAN) {
      return I18nService.isChinese() ? '风扇' : 'Fan';
    }
    if (type === DeviceType.SPEAKER) {
      return I18nService.isChinese() ? '音箱' : 'Speaker';
    }
    return I18nService.t('开关');
  }
}
