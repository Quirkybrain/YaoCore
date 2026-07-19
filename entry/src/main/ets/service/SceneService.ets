/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from './I18nService';
import { AppColors } from '../common/constants/AppTheme';
import { DeviceIds } from '../common/constants/DeviceConstants';
import { ControlResult, ControlRoute } from '../common/types/CommandTypes';
import { DeviceAction, DeviceState, DeviceType } from '../model/DeviceModel';
import { SceneAction, SceneCleanupResult, SceneDefinition, SceneDraft } from '../model/SceneModel';
import { AppStorageService } from './AppStorageService';
import { DeviceRepository } from './DeviceRepository';

export class SceneService {
  private static instance: SceneService | undefined;
  private repository: DeviceRepository = DeviceRepository.getInstance();
  private scenes: SceneDefinition[] = this.createDefaultScenes();
  private loaded: boolean = false;

  static getInstance(): SceneService {
    if (SceneService.instance === undefined) {
      SceneService.instance = new SceneService();
    }
    return SceneService.instance;
  }

  async load(): Promise<void> {
    if (this.loaded) {
      return;
    }
    await this.repository.load();
    const storedScenes = await AppStorageService.loadScenes();
    this.scenes = storedScenes.length > 0 ? storedScenes : this.createDefaultScenes();
    this.loaded = true;
  }

  getScenes(): SceneDefinition[] {
    return this.scenes.map((scene: SceneDefinition) => this.resolvePresetScene(scene));
  }

  async saveScene(draft: SceneDraft): Promise<SceneDefinition> {
    await this.load();
    const sceneId = draft.sceneId !== undefined && draft.sceneId.length > 0 ? draft.sceneId : `scene_${new Date().getTime()}`;
    const scene: SceneDefinition = {
      sceneId: sceneId,
      sceneName: draft.sceneName.trim().length === 0 ? I18nService.t('自定义场景') : draft.sceneName.trim(),
      description: draft.description.trim().length === 0 ? I18nService.t('用户配置的设备状态组合') : draft.description.trim(),
      accentColor: draft.accentColor,
      actions: this.bindDraftActions(draft.actions),
      isPreset: false
    };

    let updated = false;
    for (let index = 0; index < this.scenes.length; index++) {
      if (this.scenes[index].sceneId === scene.sceneId) {
        scene.isPreset = this.scenes[index].isPreset === true;
        this.scenes[index] = scene;
        updated = true;
        break;
      }
    }
    if (!updated) {
      this.scenes.push(scene);
    }
    await this.persistScenes();
    return this.copyScene(scene);
  }

  async deleteScene(sceneId: string): Promise<boolean> {
    await this.load();
    const next: SceneDefinition[] = [];
    let deleted = false;
    for (let index = 0; index < this.scenes.length; index++) {
      if (this.scenes[index].sceneId === sceneId) {
        deleted = true;
      } else {
        next.push(this.scenes[index]);
      }
    }
    if (deleted) {
      this.scenes = next;
      await this.persistScenes();
    }
    return deleted;
  }

  async removeDeviceActions(deviceId: string, gatewayId: string = ''): Promise<SceneCleanupResult> {
    await this.load();
    let removedActionCount = 0;
    const affectedSceneNames: string[] = [];
    for (let sceneIndex = 0; sceneIndex < this.scenes.length; sceneIndex++) {
      const scene = this.scenes[sceneIndex];
      const nextActions: SceneAction[] = [];
      let sceneRemovedCount = 0;
      for (let actionIndex = 0; actionIndex < scene.actions.length; actionIndex++) {
        const action = scene.actions[actionIndex];
        const actionGatewayId = action.gatewayId === undefined ? '' : action.gatewayId;
        if (action.targetDevice === deviceId &&
          (gatewayId.length === 0 || actionGatewayId.length === 0 || actionGatewayId === gatewayId)) {
          sceneRemovedCount += 1;
        } else {
          nextActions.push(action);
        }
      }
      if (sceneRemovedCount > 0) {
        scene.actions = nextActions;
        removedActionCount += sceneRemovedCount;
        affectedSceneNames.push(scene.sceneName);
      }
    }

    if (removedActionCount > 0) {
      await this.persistScenes();
    }
    return {
      removedActionCount: removedActionCount,
      affectedSceneNames: affectedSceneNames
    };
  }

  async removeGatewayActions(gatewayId: string, removedDeviceIds: string[]): Promise<SceneCleanupResult> {
    await this.load();
    const normalizedGatewayId = gatewayId.trim();
    let removedActionCount = 0;
    const affectedSceneNames: string[] = [];
    for (let sceneIndex = 0; sceneIndex < this.scenes.length; sceneIndex++) {
      const scene = this.scenes[sceneIndex];
      const nextActions: SceneAction[] = [];
      let sceneRemovedCount = 0;
      for (let actionIndex = 0; actionIndex < scene.actions.length; actionIndex++) {
        const action = scene.actions[actionIndex];
        const actionGatewayId = action.gatewayId === undefined ? '' : action.gatewayId.trim();
        const belongsToGateway = actionGatewayId === normalizedGatewayId ||
          (actionGatewayId.length === 0 && removedDeviceIds.indexOf(action.targetDevice) >= 0);
        if (belongsToGateway) sceneRemovedCount += 1;
        else nextActions.push(action);
      }
      if (sceneRemovedCount > 0) {
        scene.actions = nextActions;
        removedActionCount += sceneRemovedCount;
        affectedSceneNames.push(scene.sceneName);
      }
    }
    if (removedActionCount > 0) await this.persistScenes();
    return {
      removedActionCount: removedActionCount,
      affectedSceneNames: affectedSceneNames
    };
  }

  async runScene(sceneId: string): Promise<ControlResult> {
    await this.load();
    const storedScene = this.findScene(sceneId);
    let lastResult: ControlResult = {
      success: false,
      route: ControlRoute.OFFLINE,
      message: I18nService.t('未找到场景'),
      latencyMs: 0
    };
    if (storedScene === undefined) {
      return lastResult;
    }
    const scene = this.resolvePresetScene(storedScene);
    if (scene.actions.length === 0) {
      return {
        success: false,
        route: ControlRoute.OFFLINE,
        message: `${scene.sceneName} 暂无可执行的设备状态`,
        latencyMs: 0
      };
    }

    // 所有动作必须在第一条真实命令下发前通过同一套设备、绑定、在线、能力和值校验。
    for (let index = 0; index < scene.actions.length; index++) {
      const action = scene.actions[index];
      if (!this.isActionBoundToCurrentGateway(action)) {
        return {
          success: false,
          route: ControlRoute.OFFLINE,
          message: `${scene.sceneName} 的第 ${index + 1} 项绑定网关已变更，未下发任何命令；请编辑场景、重新选择设备并保存`,
          latencyMs: 0,
          confirmed: false,
          attempts: 0,
          errorCode: 'SCENE_GATEWAY_MISMATCH'
        };
      }
      const validation = this.repository.preflightControl({
        targetDevice: action.targetDevice,
        action: action.action,
        value: action.value,
        extra: {
          source: `scene-preflight:${scene.sceneId}`
        }
      });
      if (validation !== undefined) {
        return {
          success: false,
          route: ControlRoute.OFFLINE,
          message: `${scene.sceneName} 预检未通过，第 ${index + 1} 项未下发：${validation.message}`,
          latencyMs: 0,
          confirmed: false,
          attempts: 0,
          errorCode: validation.errorCode === undefined ? 'SCENE_PREFLIGHT_FAILED' : validation.errorCode
        };
      }
    }

    let totalLatencyMs = 0;
    let totalAttempts = 0;
    for (let index = 0; index < scene.actions.length; index++) {
      const action = scene.actions[index];
      if (action.delayMs !== undefined && action.delayMs > 0) {
        await this.delay(action.delayMs);
      }
      lastResult = await this.repository.control({
        targetDevice: action.targetDevice,
        action: action.action,
        value: action.value,
        extra: {
          source: `scene:${scene.sceneId}`
        }
      });
      totalLatencyMs += lastResult.latencyMs;
      totalAttempts += lastResult.attempts === undefined ? 0 : lastResult.attempts;
      if (!lastResult.success || lastResult.confirmed !== true) {
        return this.partialFailureResult(scene, index, lastResult, totalLatencyMs, totalAttempts);
      }
    }
    return {
      success: true,
      route: lastResult.route,
      message: `${scene.sceneName} 已执行，全部设备已确认`,
      latencyMs: totalLatencyMs,
      confirmed: true,
      requestId: lastResult.requestId,
      sequence: lastResult.sequence,
      commandId: lastResult.commandId,
      attempts: totalAttempts
    };
  }

  private findScene(sceneId: string): SceneDefinition | undefined {
    for (let index = 0; index < this.scenes.length; index++) {
      if (this.scenes[index].sceneId === sceneId) {
        return this.scenes[index];
      }
    }
    return undefined;
  }

  private copyScene(scene: SceneDefinition): SceneDefinition {
    return {
      sceneId: scene.sceneId,
      sceneName: scene.sceneName,
      description: scene.description,
      accentColor: scene.accentColor,
      actions: this.copyActions(scene.actions),
      isPreset: scene.isPreset
    };
  }

  private resolvePresetScene(scene: SceneDefinition): SceneDefinition {
    if (scene.isPreset !== true) {
      return this.copyScene(scene);
    }
    const actions: SceneAction[] = [];
    for (let index = 0; index < scene.actions.length; index++) {
      const template = scene.actions[index];
      const targetType = this.presetTargetType(template.targetDevice);
      if (targetType === undefined) {
        continue;
      }
      const devices = this.findBoundDevicesByType(targetType);
      if (devices.length === 0) {
        continue;
      }
      for (let deviceIndex = 0; deviceIndex < devices.length; deviceIndex++) {
        const device = devices[deviceIndex];
        actions.push({
          targetDevice: device.deviceId,
          gatewayId: device.gatewayId,
          action: template.action,
          value: template.value,
          // A template delay is a scene-step delay, not a per-device delay.
          delayMs: deviceIndex === 0 ? template.delayMs : 0
        });
      }
    }
    return {
      sceneId: scene.sceneId,
      sceneName: scene.sceneName,
      description: scene.description,
      accentColor: scene.accentColor,
      actions: actions,
      isPreset: true
    };
  }

  private presetTargetType(deviceId: string): DeviceType | undefined {
    if (deviceId === DeviceIds.DOOR) return DeviceType.DOOR;
    if (deviceId === DeviceIds.LIGHT) return DeviceType.LIGHT;
    if (deviceId === DeviceIds.SENSOR) return DeviceType.SENSOR;
    if (deviceId === DeviceIds.AC) return DeviceType.AC;
    const devices = this.repository.getDevices();
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].deviceId === deviceId) {
        return devices[index].deviceType;
      }
    }
    return undefined;
  }

  private findBoundDevicesByType(type: DeviceType): DeviceState[] {
    const devices = this.repository.getDevicesByType(type);
    const boundGatewayId = this.repository.getBoundGatewayId();
    const result: DeviceState[] = [];
    for (let index = 0; index < devices.length; index++) {
      const gatewayId = devices[index].gatewayId === undefined ? '' : devices[index].gatewayId as string;
      if (devices[index].protocol !== 'manual' && boundGatewayId.length > 0 &&
        gatewayId.trim() === boundGatewayId && devices[index].isOnline) {
        result.push(devices[index]);
      }
    }
    return result;
  }

  private copyActions(actions: SceneAction[]): SceneAction[] {
    const result: SceneAction[] = [];
    for (let index = 0; index < actions.length; index++) {
      const action = actions[index];
      result.push({
        targetDevice: action.targetDevice,
        gatewayId: action.gatewayId,
        action: action.action,
        value: action.value,
        delayMs: action.delayMs
      });
    }
    return result;
  }

  private bindDraftActions(actions: SceneAction[]): SceneAction[] {
    const result: SceneAction[] = [];
    const boundGatewayId = this.repository.getBoundGatewayId();
    for (let index = 0; index < actions.length; index++) {
      const action = actions[index];
      let gatewayId = action.gatewayId === undefined ? '' : action.gatewayId.trim();
      // 旧版本场景没有 gatewayId。用户主动重新保存时才根据当前真实绑定补齐；
      // 已经带有其他网关 ID 的动作必须保留，直到用户重新选择该设备。
      if (gatewayId.length === 0) {
        const device = this.repository.getDevice(action.targetDevice);
        const deviceGatewayId = device.gatewayId === undefined ? '' : device.gatewayId.trim();
        if (boundGatewayId.length > 0 && deviceGatewayId === boundGatewayId && device.protocol !== 'manual') {
          gatewayId = boundGatewayId;
        }
      }
      result.push({
        targetDevice: action.targetDevice,
        gatewayId: gatewayId.length === 0 ? undefined : gatewayId,
        action: action.action,
        value: action.value,
        delayMs: action.delayMs
      });
    }
    return result;
  }

  private isActionBoundToCurrentGateway(action: SceneAction): boolean {
    const boundGatewayId = this.repository.getBoundGatewayId();
    const actionGatewayId = action.gatewayId === undefined ? '' : action.gatewayId.trim();
    if (boundGatewayId.length === 0 || actionGatewayId.length === 0 || actionGatewayId !== boundGatewayId) {
      return false;
    }
    const device = this.repository.getDevice(action.targetDevice);
    const deviceGatewayId = device.gatewayId === undefined ? '' : device.gatewayId.trim();
    return device.protocol !== 'manual' && deviceGatewayId === boundGatewayId && deviceGatewayId === actionGatewayId;
  }

  private partialFailureResult(
    scene: SceneDefinition,
    failedIndex: number,
    failed: ControlResult,
    totalLatencyMs: number,
    totalAttempts: number
  ): ControlResult {
    const total = scene.actions.length;
    const completed = failedIndex;
    const remaining = total - failedIndex - 1;
    return {
      success: false,
      route: failed.route,
      message: `${scene.sceneName} 执行中止：已完成 ${completed}/${total} 项；第 ${failedIndex + 1} 项失败（${failed.message}）；后续 ${remaining} 项未执行；已执行动作未自动回滚`,
      latencyMs: totalLatencyMs,
      confirmed: false,
      requestId: failed.requestId,
      sequence: failed.sequence,
      commandId: failed.commandId,
      reportedState: failed.reportedState,
      acknowledged: failed.acknowledged,
      deliveryAttempted: failed.deliveryAttempted,
      notBeforeMs: failed.notBeforeMs,
      attempts: totalAttempts,
      errorCode: failed.errorCode === undefined && failed.success ?
        'SCENE_ACTION_UNCONFIRMED' : failed.errorCode
    };
  }

  private async persistScenes(): Promise<void> {
    await AppStorageService.saveScenes(this.scenes.map((scene: SceneDefinition) => this.copyScene(scene)));
  }

  private createDefaultScenes(): SceneDefinition[] {
    return [
      {
        sceneId: 'home',
        sceneName: I18nService.t('回家模式'),
        description: I18nService.t('开门、亮灯并打开空调'),
        accentColor: AppColors.PRIMARY,
        isPreset: true,
        actions: [
          { targetDevice: DeviceIds.DOOR, action: DeviceAction.OPEN },
          { targetDevice: DeviceIds.LIGHT, action: DeviceAction.TURN_ON, delayMs: 120 },
          { targetDevice: DeviceIds.AC, action: DeviceAction.TURN_ON, delayMs: 120 },
          { targetDevice: DeviceIds.AC, action: DeviceAction.SET_TARGET_TEMPERATURE, value: 24 }
        ]
      },
      {
        sceneId: 'away',
        sceneName: I18nService.t('离家模式'),
        description: I18nService.t('关闭灯光和空调，门禁复位'),
        accentColor: AppColors.WARNING,
        isPreset: true,
        actions: [
          { targetDevice: DeviceIds.LIGHT, action: DeviceAction.TURN_OFF },
          { targetDevice: DeviceIds.AC, action: DeviceAction.TURN_OFF },
          { targetDevice: DeviceIds.DOOR, action: DeviceAction.CLOSE }
        ]
      },
      {
        sceneId: 'sleep',
        sceneName: I18nService.t('睡眠模式'),
        description: I18nService.t('降低灯光亮度并设置舒适温度'),
        accentColor: '#7357C5',
        isPreset: true,
        actions: [
          { targetDevice: DeviceIds.LIGHT, action: DeviceAction.SET_BRIGHTNESS, value: 12 },
          { targetDevice: DeviceIds.AC, action: DeviceAction.SET_TARGET_TEMPERATURE, value: 26 },
          { targetDevice: DeviceIds.AC, action: DeviceAction.SET_MODE, value: 'SLEEP' }
        ]
      },
      {
        sceneId: 'energy',
        sceneName: I18nService.t('节能模式'),
        description: I18nService.t('关闭非必要设备并开启节能空调策略'),
        accentColor: AppColors.SUCCESS,
        isPreset: true,
        actions: [
          { targetDevice: DeviceIds.LIGHT, action: DeviceAction.SET_BRIGHTNESS, value: 35 },
          { targetDevice: DeviceIds.AC, action: DeviceAction.SET_TARGET_TEMPERATURE, value: 27 },
          { targetDevice: DeviceIds.AC, action: DeviceAction.SET_MODE, value: 'ECO' }
        ]
      }
    ];
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}
