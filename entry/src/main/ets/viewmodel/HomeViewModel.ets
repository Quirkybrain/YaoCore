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
import { DeviceIds } from '../common/constants/DeviceConstants';
import { ControlResult } from '../common/types/CommandTypes';
import { createDevicePlaceholder, DeviceAction, DeviceState, DeviceType } from '../model/DeviceModel';
import { GatewayState } from '../model/GatewayModel';
import { DeviceRepository } from '../service/DeviceRepository';

export interface HomeOverview {
  onlineCount: number;
  totalCount: number;
  comfortLabel: string;
  securityLabel: string;
}

export class HomeViewModel {
  private repository: DeviceRepository = DeviceRepository.getInstance();

  async load(): Promise<void> {
    await this.repository.load();
  }

  getGateway(): GatewayState {
    return this.repository.getGateway();
  }

  getOverview(): HomeOverview {
    const devices = this.repository.getDevices();
    let onlineCount = 0;
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].isOnline) {
        onlineCount += 1;
      }
    }
    const sensors = this.repository.getDevicesByType(DeviceType.SENSOR);
    const doors = this.repository.getDevicesByType(DeviceType.DOOR);
    const sensor = this.getSensor();
    const temp = sensor.temperature === undefined ? 0 : sensor.temperature;
    const comfortLabel = sensors.length === 0 ? I18nService.t('未添加设备') : sensor.temperature === undefined ? I18nService.t('暂无环境数据') :
      temp >= 29 ? I18nService.t('环境偏热') : temp <= 18 ? I18nService.t('环境偏冷') : I18nService.t('环境舒适');
    const securityLabel = this.resolveSecurityLabel(doors);
    return {
      onlineCount: onlineCount,
      totalCount: devices.length,
      comfortLabel: comfortLabel,
      securityLabel: securityLabel
    };
  }

  getDevices(): DeviceState[] {
    return this.repository.getDevices();
  }

  getDoor(): DeviceState {
    return this.getFirstDevice(DeviceType.DOOR, DeviceIds.DOOR, I18nService.t('门禁'));
  }

  getLight(): DeviceState {
    return this.getFirstDevice(DeviceType.LIGHT, DeviceIds.LIGHT, I18nService.t('灯光'));
  }

  getSensor(): DeviceState {
    return this.getFirstDevice(DeviceType.SENSOR, DeviceIds.SENSOR, I18nService.t('温湿度'));
  }

  getAc(): DeviceState {
    return this.getFirstDevice(DeviceType.AC, DeviceIds.AC, I18nService.t('空调'));
  }

  async refreshGateway(): Promise<GatewayState> {
    return await this.repository.refreshGateway();
  }

  async toggleDoor(): Promise<ControlResult> {
    const door = this.getDoor();
    return await this.repository.control({
      targetDevice: door.deviceId,
      action: door.openStatus === true ? DeviceAction.CLOSE : DeviceAction.OPEN,
      extra: {
        source: 'home'
      }
    });
  }

  async toggleLight(): Promise<ControlResult> {
    const light = this.getLight();
    return await this.repository.control({
      targetDevice: light.deviceId,
      action: light.powerStatus === true ? DeviceAction.TURN_OFF : DeviceAction.TURN_ON,
      extra: {
        source: 'home'
      }
    });
  }

  async toggleAc(): Promise<ControlResult> {
    const ac = this.getAc();
    const adapter = AcAdapterFactory.create(ac.brand, ac.deviceId);
    return ac.powerStatus === true ? await adapter.powerOff() : await adapter.powerOn();
  }

  async setLightBrightness(value: number): Promise<ControlResult> {
    const light = this.getLight();
    return await this.repository.control({
      targetDevice: light.deviceId,
      action: DeviceAction.SET_BRIGHTNESS,
      value: value,
      extra: {
        source: 'home-slider',
        brightness: value
      }
    });
  }

  async setAcTemperature(value: number): Promise<ControlResult> {
    const ac = this.getAc();
    return await AcAdapterFactory.create(ac.brand, ac.deviceId).setTargetTemperature(value);
  }

  async setAcMode(mode: string): Promise<ControlResult> {
    const ac = this.getAc();
    return await AcAdapterFactory.create(ac.brand, ac.deviceId).setMode(mode);
  }

  async toggleDevice(device: DeviceState): Promise<ControlResult> {
    if (device.deviceType === DeviceType.DOOR) {
      return await this.repository.control({
        targetDevice: device.deviceId,
        action: device.openStatus === true ? DeviceAction.CLOSE : DeviceAction.OPEN,
        extra: {
          source: 'home-list'
        }
      });
    }
    if (device.deviceType === DeviceType.AC) {
      const adapter = AcAdapterFactory.create(device.brand, device.deviceId);
      return device.powerStatus === true ? await adapter.powerOff() : await adapter.powerOn();
    }
    return await this.repository.control({
      targetDevice: device.deviceId,
      action: device.powerStatus === true ? DeviceAction.TURN_OFF : DeviceAction.TURN_ON,
      extra: {
        source: 'home-list'
      }
    });
  }

  private getFirstDevice(type: DeviceType, fallbackId: string, fallbackName: string): DeviceState {
    const devices = this.repository.getDevicesByType(type);
    if (devices.length > 0) {
      // Keep a deterministic quick-control target. Choosing "the first online"
      // makes a card silently jump to another same-type/same-brand device when
      // connectivity changes, which is unsafe for physical actuators.
      let selected = devices[0];
      for (let index = 1; index < devices.length; index++) {
        if (devices[index].deviceId < selected.deviceId) selected = devices[index];
      }
      return selected;
    }
    return createDevicePlaceholder(fallbackId, fallbackName, type);
  }

  private resolveSecurityLabel(doors: DeviceState[]): string {
    if (doors.length === 0) return I18nService.t('未添加设备');
    let hasUnknown = false;
    for (let index = 0; index < doors.length; index++) {
      if (!doors[index].isOnline || doors[index].openStatus === undefined) {
        hasUnknown = true;
      } else if (doors[index].openStatus === true) {
        return I18nService.t('有门禁已开启');
      }
    }
    return hasUnknown ? I18nService.t('部分门禁离线或状态未知') : I18nService.t('全部门禁已上锁');
  }
}
