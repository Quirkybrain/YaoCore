/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import common from '@ohos.app.ability.common';
import preferences from '@ohos.data.preferences';
import { CloudConfig, createDefaultCloudConfig } from '../model/CloudModel';
import { LocalRouteConfig, createDefaultLocalRouteConfig } from '../model/CommunicationModel';
import { DeviceState, DeviceType } from '../model/DeviceModel';
import { SceneDefinition } from '../model/SceneModel';
import { PendingGatewayBindingState } from '../model/GatewayModel';
import { AuthSession, createAnonymousSession, LocalCredential } from '../model/UserModel';
import { SecureStorageService } from './SecureStorageService';

export class AppStorageService {
  private static readonly STORE_NAME: string = 'yaocore_store';
  private static readonly KEY_DEVICES: string = 'devices';
  private static readonly KEY_USERS: string = 'users';
  private static readonly KEY_LOCAL_CREDENTIAL: string = 'local_credential';
  private static readonly KEY_SESSION: string = 'session';
  private static readonly KEY_CLOUD: string = 'cloud';
  private static readonly KEY_LOCAL_ROUTE: string = 'local_route';
  private static readonly KEY_SCENES: string = 'scenes';
  private static readonly KEY_ONBOARDING_COMPLETED: string = 'onboarding_completed_v2';
  private static readonly KEY_LANGUAGE_PREFERENCE: string = 'language_preference_v1';
  private static readonly KEY_PENDING_GATEWAY_BINDING: string = 'pending_gateway_binding_v1';
  private static localProfileResetNotice: boolean = false;
  private static context: common.Context | undefined;
  private static store: preferences.Preferences | undefined;

  static initialize(context: common.Context): void {
    AppStorageService.context = context;
  }

  static async loadDevices(): Promise<DeviceState[]> {
    const raw = await AppStorageService.readString(AppStorageService.KEY_DEVICES, '');
    if (raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as DeviceState[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      const devices: DeviceState[] = [];
      const compositeKeys: string[] = [];
      for (let index = 0; index < parsed.length; index++) {
        const device = parsed[index];
        if (!AppStorageService.isStoredDevice(device)) {
          continue;
        }
        const gatewayId = device.gatewayId === undefined ? '' : device.gatewayId.trim();
        const key = `${gatewayId}::${device.deviceId.trim()}`;
        const duplicateIndex = compositeKeys.indexOf(key);
        if (duplicateIndex < 0) {
          compositeKeys.push(key);
          devices.push(device);
          continue;
        }
        const previousEpoch = devices[duplicateIndex].stateEpochMs === undefined ? 0 :
          devices[duplicateIndex].stateEpochMs as number;
        const currentEpoch = device.stateEpochMs === undefined ? 0 : device.stateEpochMs as number;
        if (currentEpoch >= previousEpoch) {
          devices[duplicateIndex] = device;
        }
      }
      return devices;
    } catch (error) {
      return [];
    }
  }

  static async saveDevices(devices: DeviceState[]): Promise<void> {
    await AppStorageService.writeString(AppStorageService.KEY_DEVICES, JSON.stringify(devices));
  }

  static async hasStoredDevices(): Promise<boolean> {
    const raw = await AppStorageService.readString(AppStorageService.KEY_DEVICES, '');
    return raw.length > 0;
  }

  static async loadLocalCredential(): Promise<LocalCredential | undefined> {
    const raw = await AppStorageService.readString(AppStorageService.KEY_LOCAL_CREDENTIAL, '');
    if (raw.length === 0) {
      const legacyUsers = await AppStorageService.readString(AppStorageService.KEY_USERS, '');
      if (legacyUsers.length > 0) {
        await AppStorageService.invalidateLegacyLocalProfile();
      }
      return undefined;
    }
    try {
      const credential = JSON.parse(raw) as LocalCredential;
      if (!AppStorageService.isModernLocalCredential(credential)) {
        await AppStorageService.invalidateLegacyLocalProfile();
        return undefined;
      }
      return {
        username: credential.username,
        salt: credential.salt,
        passwordHash: credential.passwordHash,
        iterations: credential.iterations
      };
    } catch (error) {
      await AppStorageService.invalidateLegacyLocalProfile();
      return undefined;
    }
  }

  static async saveLocalCredential(credential: LocalCredential): Promise<boolean> {
    const legacyCleared = await AppStorageService.writeStringChecked(AppStorageService.KEY_USERS, '');
    if (!legacyCleared) {
      return false;
    }
    return await AppStorageService.writeStringChecked(
      AppStorageService.KEY_LOCAL_CREDENTIAL,
      JSON.stringify(credential)
    );
  }

  static consumeLocalProfileResetNotice(): boolean {
    const shouldNotify = AppStorageService.localProfileResetNotice;
    AppStorageService.localProfileResetNotice = false;
    return shouldNotify;
  }

  static async loadSession(): Promise<AuthSession> {
    const raw = await AppStorageService.readString(AppStorageService.KEY_SESSION, '');
    if (raw.length === 0) {
      return createAnonymousSession();
    }
    try {
      return JSON.parse(raw) as AuthSession;
    } catch (error) {
      return createAnonymousSession();
    }
  }

  static async saveSession(session: AuthSession): Promise<boolean> {
    return await AppStorageService.writeStringChecked(AppStorageService.KEY_SESSION, JSON.stringify(session));
  }

  static async loadCloudConfig(): Promise<CloudConfig> {
    const raw = await AppStorageService.readString(AppStorageService.KEY_CLOUD, '');
    const fallback = createDefaultCloudConfig();
    let parsed = fallback;
    if (raw.length === 0) {
      parsed = fallback;
    } else {
      try {
        const stored = JSON.parse(raw) as CloudConfig;
        parsed = {
          commandEndpoint: stored.commandEndpoint === undefined ? '' : stored.commandEndpoint,
          shadowEndpoint: stored.shadowEndpoint === undefined ? '' : stored.shadowEndpoint,
          accessToken: '',
          tenantId: stored.tenantId === undefined ? '' : stored.tenantId,
          iotdaEndpoint: stored.iotdaEndpoint === undefined ? '' : stored.iotdaEndpoint,
          projectId: stored.projectId === undefined ? (stored.tenantId === undefined ? '' : stored.tenantId) : stored.projectId,
          deviceId: stored.deviceId === undefined ? '' : stored.deviceId,
          gatewayId: stored.gatewayId === undefined ? '' : stored.gatewayId,
          instanceId: stored.instanceId === undefined ? '' : stored.instanceId,
          serviceId: stored.serviceId === undefined || stored.serviceId.length === 0 ? fallback.serviceId : stored.serviceId
        };
      } catch (error) {
        parsed = fallback;
      }
    }
    parsed.accessToken = await SecureStorageService.load(SecureStorageService.CLOUD_TOKEN_ALIAS);
    return parsed;
  }

  static async saveCloudConfig(config: CloudConfig): Promise<void> {
    const safeConfig: CloudConfig = {
      commandEndpoint: config.commandEndpoint,
      shadowEndpoint: config.shadowEndpoint,
      accessToken: '',
      tenantId: config.tenantId,
      iotdaEndpoint: config.iotdaEndpoint,
      projectId: config.projectId,
      deviceId: config.deviceId,
      gatewayId: config.gatewayId,
      instanceId: config.instanceId,
      serviceId: config.serviceId
    };
    await SecureStorageService.save(SecureStorageService.CLOUD_TOKEN_ALIAS, config.accessToken);
    await AppStorageService.writeString(AppStorageService.KEY_CLOUD, JSON.stringify(safeConfig));
  }

  static async loadCommandSecret(): Promise<string> {
    return await SecureStorageService.load(SecureStorageService.COMMAND_KEY_ALIAS);
  }

  static async saveCommandSecret(secret: string): Promise<boolean> {
    return await SecureStorageService.save(SecureStorageService.COMMAND_KEY_ALIAS, secret.trim());
  }

  static async loadLocalRouteConfig(): Promise<LocalRouteConfig> {
    const raw = await AppStorageService.readString(AppStorageService.KEY_LOCAL_ROUTE, '');
    if (raw.length === 0) {
      return createDefaultLocalRouteConfig();
    }
    try {
      const parsed = JSON.parse(raw) as LocalRouteConfig;
      const fallback = createDefaultLocalRouteConfig();
      return {
        localEnabled: parsed.localEnabled === undefined ? fallback.localEnabled : parsed.localEnabled,
        gatewayIp: parsed.gatewayIp === undefined || parsed.gatewayIp.length === 0 ? fallback.gatewayIp : parsed.gatewayIp,
        gatewayPort: parsed.gatewayPort === undefined || parsed.gatewayPort <= 0 ? fallback.gatewayPort : parsed.gatewayPort,
        realTransportEnabled: parsed.realTransportEnabled === undefined ? fallback.realTransportEnabled : parsed.realTransportEnabled,
        gatewayId: parsed.gatewayId === undefined ? '' : parsed.gatewayId,
        gatewayName: parsed.gatewayName === undefined ? '' : parsed.gatewayName
      };
    } catch (error) {
      return createDefaultLocalRouteConfig();
    }
  }

  static async saveLocalRouteConfig(config: LocalRouteConfig): Promise<boolean> {
    return await AppStorageService.writeStringChecked(AppStorageService.KEY_LOCAL_ROUTE, JSON.stringify(config));
  }

  static async loadPendingGatewayBinding(): Promise<PendingGatewayBindingState | undefined> {
    const raw = await AppStorageService.readString(AppStorageService.KEY_PENDING_GATEWAY_BINDING, '');
    if (raw.length === 0) {
      return undefined;
    }
    try {
      const parsed = JSON.parse(raw) as PendingGatewayBindingState;
      if (!AppStorageService.isPendingGatewayBinding(parsed)) {
        await AppStorageService.clearPendingGatewayBinding();
        return undefined;
      }
      return {
        gatewayId: parsed.gatewayId.trim(),
        gatewayName: parsed.gatewayName.trim(),
        ipAddress: parsed.ipAddress.trim(),
        protocolVersion: parsed.protocolVersion.trim()
      };
    } catch (error) {
      await AppStorageService.clearPendingGatewayBinding();
      return undefined;
    }
  }

  static async savePendingGatewayBinding(binding: PendingGatewayBindingState): Promise<boolean> {
    if (!AppStorageService.isPendingGatewayBinding(binding)) {
      return false;
    }
    return await AppStorageService.writeStringChecked(
      AppStorageService.KEY_PENDING_GATEWAY_BINDING,
      JSON.stringify(binding)
    );
  }

  static async clearPendingGatewayBinding(): Promise<void> {
    await AppStorageService.writeString(AppStorageService.KEY_PENDING_GATEWAY_BINDING, '');
  }

  static async loadScenes(): Promise<SceneDefinition[]> {
    const raw = await AppStorageService.readString(AppStorageService.KEY_SCENES, '');
    if (raw.length === 0) {
      return [];
    }
    try {
      return JSON.parse(raw) as SceneDefinition[];
    } catch (error) {
      return [];
    }
  }

  static async saveScenes(scenes: SceneDefinition[]): Promise<void> {
    await AppStorageService.writeString(AppStorageService.KEY_SCENES, JSON.stringify(scenes));
  }

  static async hasCompletedOnboarding(): Promise<boolean> {
    const value = await AppStorageService.readString(AppStorageService.KEY_ONBOARDING_COMPLETED, 'false');
    return value === 'true';
  }

  static async completeOnboarding(): Promise<void> {
    await AppStorageService.writeString(AppStorageService.KEY_ONBOARDING_COMPLETED, 'true');
  }

  // 供开发、测试或未来设置页调用；不在普通用户首页暴露入口。
  static async resetOnboarding(): Promise<void> {
    await AppStorageService.writeString(AppStorageService.KEY_ONBOARDING_COMPLETED, 'false');
  }

  static async loadLanguagePreference(): Promise<string> {
    return await AppStorageService.readString(AppStorageService.KEY_LANGUAGE_PREFERENCE, 'auto');
  }

  static async saveLanguagePreference(language: string): Promise<void> {
    await AppStorageService.writeString(AppStorageService.KEY_LANGUAGE_PREFERENCE, language);
  }

  private static async getStore(): Promise<preferences.Preferences | undefined> {
    if (AppStorageService.store !== undefined) {
      return AppStorageService.store;
    }
    if (AppStorageService.context === undefined) {
      return undefined;
    }
    try {
      AppStorageService.store = await preferences.getPreferences(AppStorageService.context, AppStorageService.STORE_NAME);
      return AppStorageService.store;
    } catch (error) {
      return undefined;
    }
  }

  private static async readString(key: string, fallback: string): Promise<string> {
    const store = await AppStorageService.getStore();
    if (store === undefined) {
      return fallback;
    }
    try {
      const value = await store.get(key, fallback);
      return typeof value === 'string' ? value : fallback;
    } catch (error) {
      return fallback;
    }
  }

  private static async writeString(key: string, value: string): Promise<void> {
    const store = await AppStorageService.getStore();
    if (store === undefined) {
      return;
    }
    try {
      await store.put(key, value);
      await store.flush();
    } catch (error) {
    }
  }

  private static async writeStringChecked(key: string, value: string): Promise<boolean> {
    const store = await AppStorageService.getStore();
    if (store === undefined) {
      return false;
    }
    try {
      await store.put(key, value);
      await store.flush();
      return true;
    } catch (error) {
      return false;
    }
  }

  private static isModernLocalCredential(credential: LocalCredential): boolean {
    return typeof credential.username === 'string' && credential.username.trim().length >= 2 &&
      typeof credential.salt === 'string' && AppStorageService.isLowerHex(credential.salt, 32) &&
      typeof credential.passwordHash === 'string' &&
      AppStorageService.isLowerHex(credential.passwordHash, 64) &&
      typeof credential.iterations === 'number' && credential.iterations >= 120000 &&
      Math.floor(credential.iterations) === credential.iterations;
  }

  private static isPendingGatewayBinding(binding: PendingGatewayBindingState): boolean {
    return binding !== undefined && binding !== null &&
      typeof binding.gatewayId === 'string' && binding.gatewayId.trim().length > 0 &&
      binding.gatewayId.length <= 96 &&
      typeof binding.gatewayName === 'string' && binding.gatewayName.length <= 96 &&
      typeof binding.ipAddress === 'string' && binding.ipAddress.length <= 64 &&
      typeof binding.protocolVersion === 'string' && binding.protocolVersion.trim() === '2.0';
  }

  private static isStoredDevice(device: DeviceState): boolean {
    if (device === undefined || device === null ||
      typeof device.deviceId !== 'string' || device.deviceId.trim().length === 0 ||
      device.deviceId.length > 96 ||
      typeof device.deviceName !== 'string' || device.deviceName.trim().length === 0 ||
      device.deviceName.length > 80 ||
      typeof device.roomName !== 'string' || device.roomName.length > 80 ||
      typeof device.isOnline !== 'boolean' ||
      typeof device.updatedAt !== 'string') {
      return false;
    }
    return AppStorageService.isSupportedDeviceType(device.deviceType);
  }

  private static isSupportedDeviceType(type: DeviceType): boolean {
    return type === DeviceType.DOOR || type === DeviceType.LIGHT || type === DeviceType.SENSOR ||
      type === DeviceType.AC || type === DeviceType.SWITCH || type === DeviceType.CAMERA ||
      type === DeviceType.CURTAIN || type === DeviceType.FAN || type === DeviceType.SPEAKER;
  }

  private static isLowerHex(value: string, expectedLength: number): boolean {
    if (value.length !== expectedLength) {
      return false;
    }
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      const digit = code >= 48 && code <= 57;
      const lowerHex = code >= 97 && code <= 102;
      if (!digit && !lowerHex) {
        return false;
      }
    }
    return true;
  }

  private static async invalidateLegacyLocalProfile(): Promise<void> {
    AppStorageService.localProfileResetNotice = true;
    await AppStorageService.writeStringChecked(AppStorageService.KEY_LOCAL_CREDENTIAL, '');
    await AppStorageService.writeStringChecked(AppStorageService.KEY_USERS, '');
    await AppStorageService.writeStringChecked(AppStorageService.KEY_SESSION, '');
  }
}
