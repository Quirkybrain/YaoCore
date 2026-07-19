/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from '../service/I18nService';
import { ControlResult } from '../common/types/CommandTypes';
import { DeviceAction, DeviceState, DeviceType } from '../model/DeviceModel';
import { SceneDefinition, SceneDraft } from '../model/SceneModel';
import { DeviceRepository } from '../service/DeviceRepository';
import { SceneService } from '../service/SceneService';

export class SceneViewModel {
  private sceneService: SceneService = SceneService.getInstance();
  private repository: DeviceRepository = DeviceRepository.getInstance();

  async load(): Promise<void> {
    await this.repository.load();
    await this.sceneService.load();
  }

  getScenes(): SceneDefinition[] {
    return this.sceneService.getScenes();
  }

  getDevices(): DeviceState[] {
    const devices = this.repository.getDevices();
    const boundDevices: DeviceState[] = [];
    const boundGatewayId = this.repository.getBoundGatewayId();
    for (let index = 0; index < devices.length; index++) {
      const gatewayId = devices[index].gatewayId === undefined ? '' : devices[index].gatewayId as string;
      if (devices[index].protocol !== 'manual' && boundGatewayId.length > 0 &&
        gatewayId.trim() === boundGatewayId) {
        boundDevices.push(devices[index]);
      }
    }
    return boundDevices;
  }

  async saveScene(draft: SceneDraft): Promise<SceneDefinition> {
    return await this.sceneService.saveScene(draft);
  }

  async deleteScene(sceneId: string): Promise<boolean> {
    return await this.sceneService.deleteScene(sceneId);
  }

  async runScene(sceneId: string): Promise<ControlResult> {
    return await this.sceneService.runScene(sceneId);
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
    return I18nService.t('开关');
  }

  getActionLabel(action: string): string {
    if (action === DeviceAction.OPEN) {
      return I18nService.t('开启');
    }
    if (action === DeviceAction.CLOSE) {
      return I18nService.t('关闭/上锁');
    }
    if (action === DeviceAction.TURN_ON) {
      return I18nService.t('开机/打开');
    }
    if (action === DeviceAction.TURN_OFF) {
      return I18nService.t('关机/关闭');
    }
    if (action === DeviceAction.SET_BRIGHTNESS) {
      return I18nService.t('设置亮度');
    }
    if (action === DeviceAction.SET_COLOR) {
      return I18nService.isChinese() ? '设置颜色' : 'Set color';
    }
    if (action === DeviceAction.SET_TARGET_TEMPERATURE) {
      return I18nService.t('设置温度');
    }
    if (action === DeviceAction.SET_MODE) {
      return I18nService.t('设置模式');
    }
    return action;
  }
}
