/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from './I18nService';
import { GatewayDefaults } from '../common/constants/DeviceConstants';
import {
  ControlResult,
  ControlRoute,
  DeviceControlCommand,
  DeviceReportedState,
  INetworkControlService
} from '../common/types/CommandTypes';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import { CloudConfig, CloudSyncResult } from '../model/CloudModel';
import { LocalRouteConfig, createDefaultLocalRouteConfig } from '../model/CommunicationModel';
import { DeviceState } from '../model/DeviceModel';
import { DiscoveredDevice, DiscoveredGateway, GatewayState } from '../model/GatewayModel';
import { AppStorageService } from './AppStorageService';
import { CloudService } from './CloudService';
import { GatewayDiscoveryService } from './GatewayDiscoveryService';
import { LocalGatewayService } from './LocalGatewayService';
import { SecurityService } from './SecurityService';

export class NetworkService implements INetworkControlService {
  private static instance: NetworkService | undefined;
  private cloudService: CloudService = CloudService.getInstance();
  private localGatewayService: LocalGatewayService = new LocalGatewayService();
  private discoveryService: GatewayDiscoveryService = GatewayDiscoveryService.getInstance();
  private securityService: SecurityService = SecurityService.getInstance();
  private isLocalAvailable: boolean = false;
  private localGatewayIp: string = GatewayDefaults.LOCAL_IP;
  private routeConfig: LocalRouteConfig = createDefaultLocalRouteConfig();
  private lastResult: ControlResult = {
    success: false,
    route: ControlRoute.LOCAL,
    message: I18nService.t('尚未建立真实控制链路'),
    latencyMs: 0,
    confirmed: false,
    attempts: 0
  };

  static getInstance(): NetworkService {
    if (NetworkService.instance === undefined) {
      NetworkService.instance = new NetworkService();
    }
    return NetworkService.instance;
  }

  async loadCloudConfig(): Promise<void> {
    await this.cloudService.loadConfig();
    await this.securityService.load();
    const route = await AppStorageService.loadLocalRouteConfig();
    this.applyLocalRoute(route);
    this.discoveryService.setSecureTransport(this.securityService.hasSessionSecret());
  }

  setLocalRoute(available: boolean, ip: string): void {
    const next: LocalRouteConfig = {
      localEnabled: available,
      gatewayIp: ip.trim(),
      gatewayPort: this.routeConfig.gatewayPort,
      realTransportEnabled: this.routeConfig.realTransportEnabled,
      gatewayId: this.routeConfig.gatewayId,
      gatewayName: this.routeConfig.gatewayName
    };
    this.applyLocalRoute(next);
  }

  async saveLocalRoute(config: LocalRouteConfig): Promise<boolean> {
    const next: LocalRouteConfig = this.normalizeLocalRoute(config);
    const saved = await AppStorageService.saveLocalRouteConfig(next);
    if (!saved) {
      return false;
    }
    this.applyLocalRoute(next);
    return true;
  }

  getLocalRouteConfig(): LocalRouteConfig {
    return {
      localEnabled: this.routeConfig.localEnabled,
      gatewayIp: this.routeConfig.gatewayIp,
      gatewayPort: this.routeConfig.gatewayPort,
      realTransportEnabled: this.routeConfig.realTransportEnabled,
      gatewayId: this.routeConfig.gatewayId,
      gatewayName: this.routeConfig.gatewayName
    };
  }

  setCloudEndpoint(endpoint: string): void {
    this.cloudService.setEndpoint(endpoint);
  }

  getCloudConfig(): CloudConfig {
    return this.cloudService.getConfig();
  }

  async saveCloudConfig(config: CloudConfig): Promise<void> {
    await this.cloudService.saveConfig(config);
  }

  async syncDevices(devices: DeviceState[]): Promise<CloudSyncResult> {
    const routeError = this.cloudGatewayRouteError();
    if (routeError !== undefined) {
      return {
        success: false,
        message: routeError.message,
        latencyMs: 0,
        errorCode: routeError.errorCode
      };
    }
    const result = await this.cloudService.syncDevices(devices);
    this.discoveryService.setCloudAvailable(result.success);
    return result;
  }

  setRealLocalTransportEnabled(enabled: boolean): void {
    this.routeConfig.realTransportEnabled = enabled;
    this.localGatewayService.setRealTransportEnabled(enabled);
  }

  async saveCommandSecret(secret: string): Promise<boolean> {
    const saved = await this.securityService.setSessionSecret(secret);
    this.discoveryService.setSecureTransport(saved && this.securityService.hasSessionSecret());
    return saved;
  }

  hasCommandSecret(): boolean {
    return this.securityService.hasSessionSecret();
  }

  async refreshGateway(): Promise<GatewayState> {
    const gateway = await this.discoveryService.scan();
    const boundGatewayId = this.routeConfig.gatewayId === undefined ? '' : this.routeConfig.gatewayId;
    if (gateway.localAvailable && boundGatewayId.length > 0 && gateway.gatewayId === boundGatewayId) {
      await this.saveLocalRoute({
        localEnabled: true,
        gatewayIp: gateway.localIp,
        gatewayPort: gateway.port === undefined ? this.routeConfig.gatewayPort : gateway.port,
        realTransportEnabled: true,
        gatewayId: gateway.gatewayId,
        gatewayName: gateway.gatewayName
      });
    } else if (boundGatewayId.length > 0) {
      this.setLocalRoute(false, this.routeConfig.gatewayIp);
    }
    return gateway;
  }

  async testLocalGateway(ip: string, port: number): Promise<ControlResult> {
    const result = await this.localGatewayService.testConnection(ip.trim(), port);
    this.discoveryService.setLocalRoute(result.success, ip.trim(), port, this.routeConfig.gatewayId);
    this.lastResult = result;
    return result;
  }

  async bindGateway(gateway: DiscoveredGateway): Promise<ControlResult> {
    if (!this.securityService.hasSessionSecret()) {
      const missingSecret: ControlResult = {
        success: false,
        route: ControlRoute.LOCAL,
        message: I18nService.t('请先在“我的 > 安全配置”保存与网关一致的至少 16 位命令密钥'),
        latencyMs: 0,
        confirmed: false,
        attempts: 0,
        errorCode: 'COMMAND_KEY_NOT_CONFIGURED'
      };
      this.lastResult = missingSecret;
      return missingSecret;
    }
    const probe = await this.localGatewayService.testConnection(gateway.localIp, gateway.port);
    if (!probe.success || probe.confirmed !== true) {
      this.lastResult = probe;
      return probe;
    }
    const ledResult = await this.localGatewayService.sendToGateway(gateway.localIp, gateway.port, {
      targetDevice: gateway.gatewayId,
      action: 'BOARD_LED_ON',
      value: true,
      extra: {
        source: 'gateway-bind-verification'
      }
    });
    if (!ledResult.success || ledResult.confirmed !== true) {
      ledResult.success = false;
      ledResult.confirmed = false;
      ledResult.errorCode = ledResult.errorCode === undefined ? 'GATEWAY_LED_UNCONFIRMED' : ledResult.errorCode;
      ledResult.message = I18nService.isChinese() ?
        `网关探测通过，但板载 LED 未获得真实执行回传，未绑定：${ledResult.message}` :
        `Gateway discovery passed, but no physical onboard LED feedback was received; not bound: ${ledResult.message}`;
      this.lastResult = ledResult;
      return ledResult;
    }
    const saved = await this.saveLocalRoute({
      localEnabled: true,
      gatewayIp: gateway.localIp,
      gatewayPort: gateway.port,
      realTransportEnabled: true,
      gatewayId: gateway.gatewayId,
      gatewayName: gateway.gatewayName
    });
    if (!saved) {
      const persistFailure: ControlResult = {
        success: false,
        route: ControlRoute.LOCAL,
        message: I18nService.t('网关验证通过，但本地路由安全保存失败，未绑定'),
        latencyMs: probe.latencyMs + ledResult.latencyMs,
        confirmed: false,
        attempts: probe.attempts === undefined ? ledResult.attempts :
          probe.attempts + (ledResult.attempts === undefined ? 0 : ledResult.attempts),
        errorCode: 'GATEWAY_ROUTE_PERSIST_FAILED'
      };
      this.lastResult = persistFailure;
      return persistFailure;
    }
    const boundResult: ControlResult = {
      success: true,
      route: ControlRoute.LOCAL,
      message: I18nService.isChinese() ?
        `${gateway.gatewayName} 已绑定，身份、协议及板载 LED 执行回传均已确认` :
        `${gateway.gatewayName} is bound; identity, protocol, and onboard LED feedback are verified`,
      latencyMs: probe.latencyMs + ledResult.latencyMs,
      confirmed: true,
      requestId: ledResult.requestId,
      sequence: ledResult.sequence,
      reportedState: ledResult.reportedState,
      attempts: (probe.attempts === undefined ? 0 : probe.attempts) +
        (ledResult.attempts === undefined ? 0 : ledResult.attempts)
    };
    this.lastResult = boundResult;
    return boundResult;
  }

  async unbindGateway(expectedGatewayId: string): Promise<boolean> {
    const boundGatewayId = this.routeConfig.gatewayId === undefined ? '' : this.routeConfig.gatewayId.trim();
    if (expectedGatewayId.trim().length === 0 || boundGatewayId !== expectedGatewayId.trim()) {
      return false;
    }
    const routeCleared = await this.saveLocalRoute(createDefaultLocalRouteConfig());
    if (!routeCleared) {
      return false;
    }
    // A command key belongs to the removed household trust relationship. It
    // must not silently authorize a later gateway selected by the user.
    await this.securityService.clearSessionSecret();
    this.discoveryService.clearGatewayBinding();
    return true;
  }

  async testCloudConnection(): Promise<ControlResult> {
    const routeError = this.cloudGatewayRouteError();
    if (routeError !== undefined) {
      this.lastResult = routeError;
      return routeError;
    }
    const result = await this.cloudService.testConnection();
    this.discoveryService.setCloudAvailable(result.success);
    this.lastResult = result;
    return result;
  }

  async sendDiagnosticCommand(): Promise<ControlResult> {
    const cloudDeviceId = this.cloudService.getConfig().deviceId;
    const targetGateway = this.routeConfig.gatewayId !== undefined && this.routeConfig.gatewayId.length > 0 ?
      this.routeConfig.gatewayId : (cloudDeviceId.length > 0 ? cloudDeviceId : GatewayDefaults.ID);
    const result = await this.controlDevice({
      targetDevice: targetGateway,
      action: 'PING',
      extra: {
        source: 'settings-diagnostic'
      }
    });
    this.lastResult = result;
    return result;
  }

  async turnGatewayLedOn(): Promise<ControlResult> {
    const targetGateway = this.routeConfig.gatewayId !== undefined && this.routeConfig.gatewayId.length > 0 ?
      this.routeConfig.gatewayId : GatewayDefaults.ID;
    const result = await this.localGatewayService.send({
      targetDevice: targetGateway,
      action: 'BOARD_LED_ON',
      value: true,
      extra: {
        source: 'gateway-connect'
      }
    });
    this.lastResult = result;
    return result;
  }

  async controlDevice(command: DeviceControlCommand): Promise<ControlResult> {
    const wireCommand = this.toWireCommand(command);
    if (this.isLocalAvailable && this.routeConfig.realTransportEnabled && this.localGatewayIp.length > 0) {
      // 路由在绑定时已经完成身份认证，每条 /control 响应也会再次验签。
      // 连续调光前额外请求完整 /discover 只会增加一个往返和 JSON 解析开销，
      // 不会增加信任强度；地址若被其他主机占用，也无法伪造家庭控制密钥签名。
      const expectedGatewayId = this.routeConfig.gatewayId === undefined ? '' : this.routeConfig.gatewayId;
      const localReachable = expectedGatewayId.length > 0;
      if (!localReachable) {
        this.setLocalReachability(false);
      } else {
        this.setLocalReachability(true);
        const localResult = await this.localGatewayService.send(wireCommand);
        if (localResult.success) {
          const confirmedLocal = await this.confirmLocalResult(wireCommand, localResult);
          this.setLocalReachability(true);
          if (confirmedLocal.confirmed === true) {
            this.lastResult = confirmedLocal;
            return confirmedLocal;
          }
          confirmedLocal.success = false;
          confirmedLocal.errorCode = 'LOCAL_STATE_UNCONFIRMED';
          confirmedLocal.message = `${confirmedLocal.message}；为避免重复执行，本次不自动改走云端`;
          this.lastResult = confirmedLocal;
          return confirmedLocal;
        } else {
          if (localResult.acknowledged === true) {
            // 已验签的失败ACK是网关/驱动的最终结论；走云端仍会到同一网关，不能盲目重发。
            this.setLocalReachability(true);
            this.lastResult = localResult;
            return localResult;
          }
          if (localResult.deliveryAttempted === true) {
            const reconciled = await this.confirmLocalResult(wireCommand, localResult);
            if (reconciled.confirmed === true) {
              reconciled.success = true;
              reconciled.errorCode = undefined;
              this.setLocalReachability(true);
              this.lastResult = reconciled;
              return reconciled;
            }
            this.setLocalReachability(false);
            reconciled.errorCode = reconciled.errorCode === undefined ?
              'LOCAL_DELIVERY_AMBIGUOUS' : reconciled.errorCode;
            reconciled.message = `${reconciled.message}；无法证明命令未执行，为避免重复动作，本次不自动改走云端`;
            this.lastResult = reconciled;
            return reconciled;
          }
          // 构包或本地传输前置条件失败，尚未调用控制 POST，可安全改走云端。
          this.setLocalReachability(false);
        }
      }
    }

    const routeError = this.cloudGatewayRouteError();
    if (routeError !== undefined) {
      this.lastResult = routeError;
      return routeError;
    }
    let cloudResult = await this.cloudService.send(wireCommand);
    this.discoveryService.setCloudAvailable(cloudResult.success);
    if (cloudResult.success) {
      cloudResult = await this.confirmCloudResult(wireCommand, cloudResult);
    }
    this.lastResult = cloudResult;
    return cloudResult;
  }

  getLastResult(): ControlResult {
    return {
      success: this.lastResult.success,
      route: this.lastResult.route,
      message: this.lastResult.message,
      latencyMs: this.lastResult.latencyMs,
      confirmed: this.lastResult.confirmed,
      requestId: this.lastResult.requestId,
      sequence: this.lastResult.sequence,
      commandId: this.lastResult.commandId,
      reportedState: this.lastResult.reportedState,
      acknowledged: this.lastResult.acknowledged,
      deliveryAttempted: this.lastResult.deliveryAttempted,
      notBeforeMs: this.lastResult.notBeforeMs,
      attempts: this.lastResult.attempts,
      errorCode: this.lastResult.errorCode
    };
  }

  /** 同步路由决策与网关展示状态；后台巡检不得只更新发现服务。 */
  setLocalReachability(available: boolean): void {
    this.isLocalAvailable = available;
    this.routeConfig.localEnabled = available;
    this.discoveryService.setLocalAvailable(available);
  }

  private applyLocalRoute(config: LocalRouteConfig): void {
    const normalized = this.normalizeLocalRoute(config);
    this.routeConfig = normalized;
    this.isLocalAvailable = normalized.localEnabled;
    this.localGatewayIp = normalized.gatewayIp;
    this.discoveryService.setLocalRoute(normalized.localEnabled, normalized.gatewayIp, normalized.gatewayPort,
      normalized.gatewayId === undefined ? '' : normalized.gatewayId);
    this.localGatewayService.setGateway(normalized.gatewayIp, normalized.gatewayPort);
    this.localGatewayService.setRealTransportEnabled(normalized.realTransportEnabled);
  }

  private cloudGatewayRouteError(): ControlResult | undefined {
    const boundGatewayId = this.routeConfig.gatewayId === undefined ? '' : this.routeConfig.gatewayId.trim();
    const cloudGatewayId = this.cloudService.getConfig().gatewayId.trim();
    let message = '';
    let code = '';
    if (boundGatewayId.length === 0) {
      message = I18nService.t('请先安全绑定家庭网关，再启用远程控制');
      code = 'GATEWAY_NOT_BOUND';
    } else if (cloudGatewayId.length === 0) {
      message = I18nService.t('云端配置尚未关联当前网关，请在远程连接页重新保存');
      code = 'CLOUD_GATEWAY_UNBOUND';
    } else if (cloudGatewayId !== boundGatewayId) {
      message = I18nService.t('云端配置属于另一网关，已阻止跨家庭控制');
      code = 'CLOUD_GATEWAY_MISMATCH';
    }
    if (code.length === 0) return undefined;
    return {
      success: false,
      route: ControlRoute.CLOUD,
      message: message,
      latencyMs: 0,
      confirmed: false,
      attempts: 0,
      errorCode: code
    };
  }

  private normalizeLocalRoute(config: LocalRouteConfig): LocalRouteConfig {
    const fallback = createDefaultLocalRouteConfig();
    const port = config.gatewayPort > 0 && config.gatewayPort < 65536 ? config.gatewayPort : fallback.gatewayPort;
    const ip = config.gatewayIp.trim().length > 0 ? config.gatewayIp.trim() : fallback.gatewayIp;
    return {
      localEnabled: config.localEnabled,
      gatewayIp: ip,
      gatewayPort: port,
      realTransportEnabled: config.realTransportEnabled,
      gatewayId: config.gatewayId === undefined ? '' : config.gatewayId,
      gatewayName: config.gatewayName === undefined ? '' : config.gatewayName
    };
  }

  private async confirmLocalResult(command: DeviceControlCommand, result: ControlResult): Promise<ControlResult> {
    const notBeforeMs = result.notBeforeMs === undefined ? new Date().getTime() : result.notBeforeMs;
    const signedAckIsSufficient = command.action === 'PING' || command.action === 'BOARD_LED_ON';
    if (result.confirmed === true) {
      if (signedAckIsSufficient) {
        return result;
      }
      if (result.reportedState !== undefined && result.reportedState.deviceId === command.targetDevice &&
        this.stateMatchesCommand(result.reportedState, command) &&
        this.stateIsFresh(result.reportedState, notBeforeMs) &&
        (result.acknowledged === true || this.stateCorrelatesResult(result.reportedState, result))) {
        return result;
      }
      result.confirmed = false;
      result.reportedState = undefined;
      result.message = I18nService.t('网关 ACK 与期望设备状态不一致，正在回读');
    }
    for (let attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await this.delay(180 * attempt);
      }
      const snapshot = await this.discoveryService.probeConfiguredGateway(this.routeConfig.gatewayIp,
        this.routeConfig.gatewayPort);
      if (snapshot === undefined) {
        continue;
      }
      const state = this.findReportedState(snapshot.devices, command.targetDevice);
      if (state !== undefined && this.stateMatchesCommand(state, command) && this.stateIsFresh(state, notBeforeMs) &&
        this.stateCorrelatesResult(state, result)) {
        result.confirmed = true;
        result.reportedState = state;
        result.message = I18nService.t('局域网指令与设备回传状态已确认');
        return result;
      }
    }
    result.message = I18nService.t('网关已接收命令，但设备状态未在时限内确认');
    return result;
  }

  private async confirmCloudResult(command: DeviceControlCommand, result: ControlResult): Promise<ControlResult> {
    const notBeforeMs = result.notBeforeMs === undefined ? new Date().getTime() : result.notBeforeMs;
    if (result.reportedState !== undefined && result.reportedState.deviceId === command.targetDevice &&
      this.stateMatchesCommand(result.reportedState, command) && this.stateIsFresh(result.reportedState, notBeforeMs) &&
      this.stateCorrelatesResult(result.reportedState, result)) {
      result.confirmed = true;
      result.message = I18nService.t('IoTDA 命令与本次设备状态回传已确认');
      return result;
    }
    result.confirmed = false;
    result.reportedState = undefined;
    for (let attempt = 0; attempt < 9; attempt++) {
      if (attempt > 0) {
        await this.delay(Math.min(300 * Math.pow(1.6, attempt - 1), 2500));
      }
      const shadow = await this.cloudService.fetchShadow();
      if (!shadow.success || shadow.reportedStates === undefined) {
        continue;
      }
      for (let index = 0; index < shadow.reportedStates.length; index++) {
        const state = shadow.reportedStates[index];
        if (state.deviceId === command.targetDevice && this.stateMatchesCommand(state, command) &&
          this.stateIsFresh(state, notBeforeMs) && this.stateCorrelatesResult(state, result)) {
          result.confirmed = true;
          result.reportedState = state;
          result.message = I18nService.t('IoTDA 命令与设备影子状态已确认');
          return result;
        }
      }
    }
    result.success = false;
    result.confirmed = false;
    result.errorCode = 'CLOUD_STATE_UNCONFIRMED';
    result.message = I18nService.t('IoTDA 已接收命令，但未取得不早于本次下发时间的设备影子确认');
    return result;
  }

  private stateIsFresh(state: DeviceReportedState, notBeforeMs: number): boolean {
    if (state.eventTime === undefined || state.eventTime.trim().length === 0) {
      return false;
    }
    const eventMs = DateTimeUtil.parseUtcToMillis(state.eventTime);
    return !Number.isNaN(eventMs) && eventMs + 2000 >= notBeforeMs;
  }

  private stateCorrelatesResult(state: DeviceReportedState, result: ControlResult): boolean {
    return result.requestId !== undefined && result.sequence !== undefined &&
      state.lastRequestId === result.requestId && state.lastSequence === result.sequence;
  }

  private findReportedState(devices: DiscoveredDevice[], deviceId: string): DeviceReportedState | undefined {
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].deviceId === deviceId) {
        return {
          deviceId: devices[index].deviceId,
          gatewayId: devices[index].gatewayId,
          online: devices[index].isOnline,
          power: devices[index].powerStatus,
          open: devices[index].openStatus,
          brightness: devices[index].brightness,
          color: devices[index].color,
          temperature: devices[index].temperature,
          humidity: devices[index].humidity,
          targetTemperature: devices[index].targetTemperature,
          mode: devices[index].mode,
          eventTime: devices[index].lastSeenAt,
          lastRequestId: devices[index].lastRequestId,
          lastSequence: devices[index].lastSequence
        };
      }
    }
    return undefined;
  }

  private stateMatchesCommand(state: DeviceReportedState, command: DeviceControlCommand): boolean {
    if (command.action === 'OPEN') return state.open === true;
    if (command.action === 'CLOSE') return state.open === false;
    if (command.action === 'ON') return state.power === true;
    if (command.action === 'OFF') return state.power === false;
    if (command.action === 'SET_BRIGHTNESS' && typeof command.value === 'number') {
      return state.brightness !== undefined && Math.abs(state.brightness - command.value) < 1;
    }
    if (command.action === 'SET_COLOR' && typeof command.value === 'string') {
      return state.color !== undefined && state.color.toUpperCase() === command.value.toUpperCase();
    }
    if (command.action === 'SET_TARGET_TEMPERATURE' && typeof command.value === 'number') {
      return state.targetTemperature !== undefined && Math.abs(state.targetTemperature - command.value) < 0.5;
    }
    if (command.action === 'SET_MODE' && typeof command.value === 'string') {
      return state.mode !== undefined && this.protocolMode(state.mode) === this.protocolMode(command.value);
    }
    if (command.action === 'PING' || command.action === 'BOARD_LED_ON') {
      return true;
    }
    return false;
  }

  private toWireCommand(command: DeviceControlCommand): DeviceControlCommand {
    if (command.action !== 'SET_MODE' || typeof command.value !== 'string') {
      return command;
    }
    return {
      targetDevice: command.targetDevice,
      action: command.action,
      value: this.protocolMode(command.value),
      extra: command.extra
    };
  }

  private protocolMode(mode: string): string {
    const normalized = mode.trim().toUpperCase();
    if (mode === I18nService.t('自动') || normalized === 'AUTO') return 'AUTO';
    if (mode === I18nService.t('制冷') || normalized === 'COOL') return 'COOL';
    if (mode === I18nService.t('制热') || normalized === 'HEAT') return 'HEAT';
    if (mode === I18nService.t('除湿') || normalized === 'DRY') return 'DRY';
    if (mode === I18nService.t('送风') || normalized === 'FAN') return 'FAN';
    if (mode === I18nService.t('节能') || normalized === 'ECO') return 'ECO';
    if (mode === I18nService.t('睡眠') || normalized === 'SLEEP') return 'SLEEP';
    return normalized;
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}
