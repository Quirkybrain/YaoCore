/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from './I18nService';
import http from '@ohos.net.http';
import { GatewayDefaults } from '../common/constants/DeviceConstants';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import {
  ControlResult,
  ControlRoute,
  DeviceControlCommand,
  DeviceReportedState
} from '../common/types/CommandTypes';
import { CloudConfig, CloudSyncResult, createDefaultCloudConfig } from '../model/CloudModel';
import { DeviceState } from '../model/DeviceModel';
import { AppStorageService } from './AppStorageService';
import { SecurityService, SignedCommandMeta } from './SecurityService';

interface HuaweiCloudCommandPayload {
  object_device_id: string;
  command_name: string;
  service_id: string;
  paras: CloudCommandParas;
}

interface IoTDACommandPayload {
  command_name: string;
  service_id: string;
  paras: CloudCommandParas;
}

interface CloudCommandParas {
  TargetDevice: string;
  Action: string;
  Value?: string;
  Timestamp: string;
  Nonce: string;
  Sign: string;
  RequestId: string;
  CmdId: number;
  Seq: number;
  Alg: string;
  KeyId: string;
}

interface IoTDAResponsePayload {
  command_id?: string;
  error_code?: string;
  error_msg?: string;
  response?: IoTDACommandResponse;
  request_id?: string;
  success?: boolean;
  message?: string;
  reported_state?: CloudReportedPayload;
}

interface IoTDACommandResponse {
  result_code?: number;
  response_name?: string;
  paras?: IoTDACommandResponseParas;
}

interface IoTDACommandResponseParas {
  result?: string;
  message?: string;
  reported_state?: CloudReportedPayload;
  reportedState?: CloudReportedPayload;
}

interface CloudReportedPayload {
  device_id?: string;
  deviceId?: string;
  device_name?: string;
  deviceName?: string;
  room_name?: string;
  roomName?: string;
  device_type?: string;
  deviceType?: string;
  brand?: string;
  protocol?: string;
  module_id?: string;
  moduleId?: string;
  online?: boolean;
  power?: boolean;
  open?: boolean;
  brightness?: number;
  color?: string;
  position?: number;
  speed?: number;
  volume?: number;
  temperature?: number;
  humidity?: number;
  presence?: boolean;
  target_temperature?: number;
  targetTemperature?: number;
  mode?: string;
  event_time?: string;
  eventTime?: string;
  last_request_id?: string;
  lastRequestId?: string;
  last_seq?: number;
  lastSeq?: number;
  state_source?: string;
  stateSource?: string;
  trigger_device_id?: string;
  triggerDeviceId?: string;
  automation_id?: string;
  automationId?: string;
}

interface IoTDAShadowResponse {
  device_id?: string;
  shadow?: IoTDAServiceShadow[];
  devices?: CloudReportedPayload[];
}

interface IoTDAServiceShadow {
  service_id?: string;
  reported?: IoTDAPropertiesContainer;
  desired?: IoTDAPropertiesContainer;
  version?: number;
}

interface IoTDAPropertiesContainer {
  properties?: Record<string, string | number | boolean>;
  event_time?: string;
}

interface CloudRequestResult {
  code: number;
  body: string;
  attempts: number;
  errorCode?: string;
}

export class CloudService {
  private static instance: CloudService | undefined;
  private config: CloudConfig = createDefaultCloudConfig();
  private securityService: SecurityService = SecurityService.getInstance();
  private sequence: number = 30000;

  static getInstance(): CloudService {
    if (CloudService.instance === undefined) {
      CloudService.instance = new CloudService();
    }
    return CloudService.instance;
  }

  async loadConfig(): Promise<void> {
    this.config = await AppStorageService.loadCloudConfig();
  }

  getConfig(): CloudConfig {
    return {
      commandEndpoint: this.config.commandEndpoint,
      shadowEndpoint: this.config.shadowEndpoint,
      accessToken: this.config.accessToken,
      tenantId: this.config.tenantId,
      iotdaEndpoint: this.config.iotdaEndpoint,
      projectId: this.config.projectId,
      deviceId: this.config.deviceId,
      gatewayId: this.config.gatewayId,
      instanceId: this.config.instanceId,
      serviceId: this.config.serviceId
    };
  }

  async saveConfig(config: CloudConfig): Promise<void> {
    this.config = this.normalizeConfig(config);
    await AppStorageService.saveCloudConfig(this.config);
  }

  setEndpoint(endpoint: string): void {
    this.config.commandEndpoint = endpoint.trim();
  }

  async send(command: DeviceControlCommand): Promise<ControlResult> {
    const startedAt = new Date().getTime();
    const endpoint = this.resolveCommandEndpoint();
    const validation = this.validateEndpoint(endpoint, true);
    if (validation.length > 0) {
      return this.cloudFailure(validation, startedAt, 'CLOUD_CONFIG_INVALID');
    }

    let payload: HuaweiCloudCommandPayload;
    try {
      payload = this.buildPayload(command);
    } catch (error) {
      return this.cloudFailure(I18nService.t('请先配置至少 16 位命令密钥'), startedAt, 'COMMAND_KEY_NOT_CONFIGURED');
    }
    const directPayload: IoTDACommandPayload = {
      command_name: payload.command_name,
      service_id: payload.service_id,
      paras: payload.paras
    };
    const body = this.isDirectIoTDAEndpoint(endpoint) ? JSON.stringify(directPayload) : JSON.stringify(payload);
    const response = await this.requestWithRetry(endpoint, http.RequestMethod.POST, body, 22000);
    if (response.errorCode !== undefined) {
      return this.cloudFailure(I18nService.t('云端控制请求失败，请检查网络与 IoTDA 配置'), startedAt, response.errorCode, response.attempts,
        payload.paras.RequestId, payload.paras.Seq);
    }
    if (response.code < 200 || response.code >= 300) {
      const parsedError = this.readError(response.body);
      return this.cloudFailure(parsedError.length > 0 ? parsedError : `IoTDA 返回 ${response.code}`, startedAt,
        `HTTP_${response.code}`, response.attempts, payload.paras.RequestId, payload.paras.Seq);
    }
    return this.parseCommandResponse(response, payload, startedAt);
  }

  async testConnection(): Promise<ControlResult> {
    const startedAt = new Date().getTime();
    const syncResult = await this.fetchShadow();
    return {
      success: syncResult.success,
      route: ControlRoute.CLOUD,
      message: syncResult.success ? I18nService.t('华为云 IoTDA 鉴权与设备影子连接正常') : syncResult.message,
      latencyMs: new Date().getTime() - startedAt,
      confirmed: syncResult.success,
      attempts: 1,
      errorCode: syncResult.errorCode
    };
  }

  async syncDevices(devices: DeviceState[]): Promise<CloudSyncResult> {
    return await this.fetchShadow();
  }

  async fetchShadow(): Promise<CloudSyncResult> {
    const startedAt = new Date().getTime();
    const endpoint = this.resolveShadowEndpoint();
    const validation = this.validateEndpoint(endpoint, true);
    if (validation.length > 0) {
      return {
        success: false,
        message: validation,
        latencyMs: 0,
        confirmedCount: 0,
        errorCode: 'CLOUD_CONFIG_INVALID'
      };
    }
    const response = await this.requestWithRetry(endpoint, http.RequestMethod.GET, '', 5000);
    if (response.errorCode !== undefined) {
      return {
        success: false,
        message: I18nService.t('设备影子读取失败，请检查网络或鉴权'),
        latencyMs: new Date().getTime() - startedAt,
        confirmedCount: 0,
        errorCode: response.errorCode
      };
    }
    if (response.code < 200 || response.code >= 300) {
      const errorMessage = this.readError(response.body);
      return {
        success: false,
        message: errorMessage.length > 0 ? errorMessage : `设备影子返回 ${response.code}`,
        latencyMs: new Date().getTime() - startedAt,
        confirmedCount: 0,
        errorCode: `HTTP_${response.code}`
      };
    }
    try {
      const payload = JSON.parse(response.body) as IoTDAShadowResponse;
      const states = this.parseShadowStates(payload);
      return {
        success: true,
        message: states.length > 0 ? `已从 IoTDA 影子确认 ${states.length} 台设备状态` : I18nService.t('IoTDA 影子连接正常，暂无已上报属性'),
        latencyMs: new Date().getTime() - startedAt,
        confirmedCount: states.length,
        reportedStates: states,
        eventTime: this.latestEventTime(states)
      };
    } catch (error) {
      return {
        success: false,
        message: I18nService.t('IoTDA 影子响应格式无法解析'),
        latencyMs: new Date().getTime() - startedAt,
        confirmedCount: 0,
        errorCode: 'INVALID_SHADOW_RESPONSE'
      };
    }
  }

  buildPayload(command: DeviceControlCommand): HuaweiCloudCommandPayload {
    this.sequence += 1;
    const requestId = this.securityService.createRequestId();
    const signed: SignedCommandMeta = this.securityService.signCommand(command, {
      requestId: requestId,
      commandId: 3001,
      sequence: this.sequence
    });
    const gatewayId = this.config.deviceId.length > 0 ? this.config.deviceId : GatewayDefaults.ID;
    const paras: CloudCommandParas = {
      TargetDevice: command.targetDevice,
      Action: command.action,
      Timestamp: signed.timestamp,
      Nonce: signed.nonce,
      Sign: signed.sign,
      RequestId: requestId,
      CmdId: 3001,
      Seq: this.sequence,
      Alg: signed.algorithm,
      KeyId: signed.keyId
    };
    if (command.value !== undefined) {
      paras.Value = this.commandValueText(command.value);
    }
    return {
      object_device_id: gatewayId,
      command_name: 'SetDeviceStatus',
      service_id: this.config.serviceId.length > 0 ? this.config.serviceId : GatewayDefaults.SERVICE_ID,
      paras: paras
    };
  }

  private commandValueText(value: string | number | boolean): string {
    if (typeof value === 'string') {
      return JSON.stringify(value);
    }
    return `${value}`;
  }

  private async requestWithRetry(
    endpoint: string,
    method: http.RequestMethod,
    body: string,
    timeoutMs: number
  ): Promise<CloudRequestResult> {
    const maxAttempts = 2;
    let last: CloudRequestResult = {
      code: 0,
      body: '',
      attempts: 0,
      errorCode: 'CLOUD_REQUEST_FAILED'
    };
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      const request = http.createHttp();
      try {
        const options: http.HttpRequestOptions = {
          method: method,
          header: this.buildHeaders(endpoint),
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 3000,
          readTimeout: timeoutMs
        };
        if (method !== http.RequestMethod.GET && body.length > 0) {
          options.extraData = body;
        }
        const response = await request.request(endpoint, options);
        last = {
          code: response.responseCode,
          body: `${response.result}`,
          attempts: attempt
        };
        if (!this.retryableStatus(response.responseCode) || attempt === maxAttempts) {
          return last;
        }
      } catch (error) {
        last = {
          code: 0,
          body: '',
          attempts: attempt,
          errorCode: 'CLOUD_REQUEST_FAILED'
        };
        if (attempt === maxAttempts) {
          return last;
        }
      } finally {
        request.destroy();
      }
      await this.delay(120 * attempt);
    }
    return last;
  }

  private parseCommandResponse(
    response: CloudRequestResult,
    requestPayload: HuaweiCloudCommandPayload,
    startedAt: number
  ): ControlResult {
    if (response.body.trim().length === 0) {
      return {
        success: true,
        route: ControlRoute.CLOUD,
        message: I18nService.t('IoTDA 已接收命令，等待设备影子确认'),
        latencyMs: new Date().getTime() - startedAt,
        confirmed: false,
        requestId: requestPayload.paras.RequestId,
        sequence: requestPayload.paras.Seq,
        notBeforeMs: startedAt,
        attempts: response.attempts
      };
    }
    try {
      const payload = JSON.parse(response.body) as IoTDAResponsePayload;
      if (payload.error_code !== undefined && payload.error_code.length > 0) {
        return this.cloudFailure(payload.error_msg === undefined ? payload.error_code : payload.error_msg, startedAt,
          payload.error_code, response.attempts, requestPayload.paras.RequestId, requestPayload.paras.Seq);
      }
      const responseParas = payload.response === undefined ? undefined : payload.response.paras;
      const statePayload = payload.reported_state === undefined ?
        (responseParas === undefined ? undefined :
          (responseParas.reported_state === undefined ? responseParas.reportedState : responseParas.reported_state)) :
        payload.reported_state;
      const reportedState = statePayload === undefined ? undefined : this.toReportedState(statePayload,
        requestPayload.paras.TargetDevice);
      const resultCode = payload.response === undefined ? undefined : payload.response.result_code;
      const resultText = responseParas === undefined ? '' : (responseParas.result === undefined ? '' : responseParas.result.toLowerCase());
      const responseAcceptedExecution = resultCode === 0 || resultText === 'success';
      const explicitExecutionFailure = payload.response !== undefined &&
        ((resultCode !== undefined && resultCode !== 0) ||
          (resultCode === undefined && resultText.length > 0 && resultText !== 'success'));
      if (explicitExecutionFailure || (payload.response === undefined && payload.success === false)) {
        return this.cloudFailure(responseParas !== undefined && responseParas.message !== undefined ?
          responseParas.message : I18nService.t('设备返回执行失败'), startedAt, 'DEVICE_EXECUTION_FAILED', response.attempts,
        requestPayload.paras.RequestId, requestPayload.paras.Seq);
      }
      return {
        success: true,
        route: ControlRoute.CLOUD,
        message: responseAcceptedExecution && reportedState !== undefined ?
          I18nService.t('IoTDA 已返回状态，正在校验状态时间与命令结果') : I18nService.t('IoTDA 已接收命令，等待设备影子确认'),
        latencyMs: new Date().getTime() - startedAt,
        confirmed: false,
        requestId: requestPayload.paras.RequestId,
        sequence: requestPayload.paras.Seq,
        commandId: payload.command_id,
        reportedState: reportedState,
        notBeforeMs: startedAt,
        attempts: response.attempts
      };
    } catch (error) {
      return {
        success: true,
        route: ControlRoute.CLOUD,
        message: I18nService.t('云端已接收命令，等待设备影子确认'),
        latencyMs: new Date().getTime() - startedAt,
        confirmed: false,
        requestId: requestPayload.paras.RequestId,
        sequence: requestPayload.paras.Seq,
        notBeforeMs: startedAt,
        attempts: response.attempts
      };
    }
  }

  private parseShadowStates(payload: IoTDAShadowResponse): DeviceReportedState[] {
    const states: DeviceReportedState[] = [];
    if (payload.devices !== undefined) {
      for (let index = 0; index < payload.devices.length; index++) {
        states.push(this.toReportedState(payload.devices[index],
          payload.devices[index].device_id === undefined ? '' : payload.devices[index].device_id as string));
      }
    }
    if (payload.shadow !== undefined) {
      for (let index = 0; index < payload.shadow.length; index++) {
        const service = payload.shadow[index];
        if (service.reported === undefined || service.reported.properties === undefined) {
          continue;
        }
        this.appendPropertyStates(states, service.reported.properties,
          service.reported.event_time === undefined ? '' : service.reported.event_time);
      }
    }
    const merged = this.mergeReportedStates(states);
    for (let index = 0; index < merged.length; index++) {
      merged[index].gatewayId = this.config.gatewayId;
    }
    return this.expireStaleStates(merged);
  }

  private expireStaleStates(states: DeviceReportedState[]): DeviceReportedState[] {
    const now = new Date().getTime();
    const maxShadowAgeMs = 120000; // 网关正常每30秒全量上报，四个周期无更新即不可再称在线。
    for (let index = 0; index < states.length; index++) {
      const eventMs = states[index].eventTime === undefined ? Number.NaN :
        DateTimeUtil.parseUtcToMillis(states[index].eventTime as string);
      if (Number.isNaN(eventMs) || eventMs > now + 300000 || now - eventMs > maxShadowAgeMs) {
        states[index].online = false;
      }
    }
    return states;
  }

  private appendPropertyStates(
    states: DeviceReportedState[],
    properties: Record<string, string | number | boolean>,
    eventTime: string
  ): void {
    const inventoryNames: string[] = ['DeviceInventoryJson', 'DeviceInventoryJson2',
      'DeviceInventoryJson3', 'DeviceInventoryJson4'];
    for (let page = 0; page < inventoryNames.length; page++) {
      const inventoryJson = this.firstProperty(properties, [inventoryNames[page]]);
      if (typeof inventoryJson !== 'string' || inventoryJson.length === 0 || inventoryJson.length > 8192) continue;
      try {
        const inventory = JSON.parse(inventoryJson) as CloudReportedPayload[];
        if (!Array.isArray(inventory) || inventory.length > 32) continue;
        for (let index = 0; index < inventory.length; index++) {
          const deviceId = inventory[index].device_id === undefined ?
            (inventory[index].deviceId === undefined ? '' : inventory[index].deviceId as string) :
            inventory[index].device_id as string;
          if (deviceId.trim().length > 0 && deviceId.length <= 96) {
            const state = this.toReportedState(inventory[index], deviceId);
            if (state.eventTime === undefined || state.eventTime.length === 0) state.eventTime = eventTime;
            states.push(state);
          }
        }
      } catch (error) {
        // Keep parsing other pages and the fixed compatibility properties.
      }
    }
    const doorStatus = this.firstProperty(properties, ['Door_01_Status', 'doorStatus', 'door_status']);
    const doorOnline = this.firstProperty(properties, ['Door_01_Online', 'doorOnline', 'door_online']);
    const doorRequest = this.firstProperty(properties, ['Door_01_LastRequestId']);
    const doorSequence = this.firstProperty(properties, ['Door_01_LastSeq']);
    const doorSource = this.firstProperty(properties, ['Door_01_StateSource']);
    if (doorStatus !== undefined || doorOnline !== undefined || doorRequest !== undefined) {
      states.push({
        deviceId: 'Door_01',
        online: doorOnline === undefined ? undefined : this.toBoolean(doorOnline),
        open: doorStatus === undefined ? undefined : this.toOpen(doorStatus),
        eventTime: eventTime,
        lastRequestId: doorRequest === undefined ? undefined : `${doorRequest}`,
        lastSequence: doorSequence === undefined ? undefined : this.toNumber(doorSequence),
        stateSource: doorSource === undefined ? undefined : `${doorSource}`
      });
    }
    const lightStatus = this.firstProperty(properties, ['Light_01_Status', 'lightStatus', 'light_power']);
    const lightBrightness = this.firstProperty(properties, ['Light_01_Brightness', 'lightBrightness', 'brightness']);
    const lightColor = this.firstProperty(properties, ['Light_01_Color', 'lightColor', 'color']);
    const lightOnline = this.firstProperty(properties, ['Light_01_Online', 'lightOnline', 'light_online']);
    const lightRequest = this.firstProperty(properties, ['Light_01_LastRequestId']);
    const lightSequence = this.firstProperty(properties, ['Light_01_LastSeq']);
    const lightSource = this.firstProperty(properties, ['Light_01_StateSource']);
    const lightTrigger = this.firstProperty(properties, ['Light_01_TriggerDeviceId']);
    const lightAutomation = this.firstProperty(properties, ['Light_01_AutomationId']);
    if (lightStatus !== undefined || lightBrightness !== undefined || lightColor !== undefined ||
      lightOnline !== undefined || lightRequest !== undefined) {
      states.push({
        deviceId: 'Light_01',
        online: lightOnline === undefined ? undefined : this.toBoolean(lightOnline),
        power: lightStatus === undefined ? undefined : this.toBoolean(lightStatus),
        brightness: lightBrightness === undefined ? undefined : this.toNumber(lightBrightness),
        color: lightColor === undefined ? undefined : `${lightColor}`,
        eventTime: eventTime,
        lastRequestId: lightRequest === undefined ? undefined : `${lightRequest}`,
        lastSequence: lightSequence === undefined ? undefined : this.toNumber(lightSequence),
        stateSource: lightSource === undefined ? undefined : `${lightSource}`,
        triggerDeviceId: lightTrigger === undefined ? undefined : `${lightTrigger}`,
        automationId: lightAutomation === undefined ? undefined : `${lightAutomation}`
      });
    }
    const temperature = this.firstProperty(properties,
      ['Room_01_Temperature', 'temperature', 'roomTemperature']);
    const humidity = this.firstProperty(properties, ['Room_01_Humidity', 'humidity', 'roomHumidity']);
    const sensorOnline = this.firstProperty(properties, ['Sensor_01_Online', 'sensorOnline', 'sensor_online']);
    if (temperature !== undefined || humidity !== undefined || sensorOnline !== undefined) {
      states.push({
        deviceId: 'Sensor_01',
        online: sensorOnline === undefined ? undefined : this.toBoolean(sensorOnline),
        temperature: temperature === undefined ? undefined : this.toNumber(temperature),
        humidity: humidity === undefined ? undefined : this.toNumber(humidity),
        eventTime: eventTime
      });
    }
    const presence = this.firstProperty(properties, ['Presence_01_Detected', 'presence', 'occupied']);
    const presenceOnline = this.firstProperty(properties, ['Presence_01_Online', 'presenceOnline']);
    if (presence !== undefined || presenceOnline !== undefined) {
      states.push({
        deviceId: 'Presence_01',
        online: presenceOnline === undefined ? undefined : this.toBoolean(presenceOnline),
        presence: presence === undefined ? undefined : this.toBoolean(presence),
        eventTime: eventTime,
        stateSource: 'sensor.physical'
      });
    }
    const acPower = this.firstProperty(properties, ['AC_01_Status', 'acPower', 'ac_power']);
    const targetTemperature = this.firstProperty(properties,
      ['AC_01_TargetTemp', 'targetTemperature', 'target_temperature']);
    const mode = this.firstProperty(properties, ['AC_01_Mode', 'acMode', 'mode']);
    const acOnline = this.firstProperty(properties, ['AC_01_Online', 'acOnline', 'ac_online']);
    const acRequest = this.firstProperty(properties, ['AC_01_LastRequestId']);
    const acSequence = this.firstProperty(properties, ['AC_01_LastSeq']);
    const acSource = this.firstProperty(properties, ['AC_01_StateSource']);
    const acTrigger = this.firstProperty(properties, ['AC_01_TriggerDeviceId']);
    const acAutomation = this.firstProperty(properties, ['AC_01_AutomationId']);
    if (acPower !== undefined || targetTemperature !== undefined || mode !== undefined || acOnline !== undefined ||
      acRequest !== undefined) {
      states.push({
        deviceId: 'AC_01',
        online: acOnline === undefined ? undefined : this.toBoolean(acOnline),
        power: acPower === undefined ? undefined : this.toBoolean(acPower),
        targetTemperature: targetTemperature === undefined ? undefined : this.toNumber(targetTemperature),
        mode: mode === undefined ? undefined : `${mode}`,
        eventTime: eventTime,
        lastRequestId: acRequest === undefined ? undefined : `${acRequest}`,
        lastSequence: acSequence === undefined ? undefined : this.toNumber(acSequence),
        stateSource: acSource === undefined ? undefined : `${acSource}`,
        triggerDeviceId: acTrigger === undefined ? undefined : `${acTrigger}`,
        automationId: acAutomation === undefined ? undefined : `${acAutomation}`
      });
    }
    const gatewayOnline = this.firstProperty(properties, ['Gateway_Online', 'gatewayOnline', 'gateway_online']);
    if (gatewayOnline !== undefined) {
      states.push({
        deviceId: this.config.deviceId.length > 0 ? this.config.deviceId : GatewayDefaults.ID,
        online: this.toBoolean(gatewayOnline),
        eventTime: eventTime
      });
    }
  }

  private mergeReportedStates(states: DeviceReportedState[]): DeviceReportedState[] {
    const merged: DeviceReportedState[] = [];
    for (let index = 0; index < states.length; index++) {
      let targetIndex: number = -1;
      for (let mergedIndex = 0; mergedIndex < merged.length; mergedIndex++) {
        if (merged[mergedIndex].deviceId === states[index].deviceId) {
          targetIndex = mergedIndex;
          break;
        }
      }
      if (targetIndex < 0) {
        merged.push(states[index]);
      } else {
        const targetTime = merged[targetIndex].eventTime === undefined ? Number.NaN :
          DateTimeUtil.parseUtcToMillis(merged[targetIndex].eventTime as string);
        const sourceTime = states[index].eventTime === undefined ? Number.NaN :
          DateTimeUtil.parseUtcToMillis(states[index].eventTime as string);
        if (!Number.isNaN(targetTime) && (Number.isNaN(sourceTime) || sourceTime < targetTime)) {
          continue;
        }
        if (!Number.isNaN(sourceTime) && (Number.isNaN(targetTime) || sourceTime > targetTime)) {
          // 不混合两个不同时刻的局部属性，否则旧值会被伪装成新时间戳。
          merged[targetIndex] = states[index];
          continue;
        }
        this.mergeState(merged[targetIndex], states[index]);
      }
    }
    return merged;
  }

  private mergeState(target: DeviceReportedState, source: DeviceReportedState): void {
    if (source.gatewayId !== undefined) target.gatewayId = source.gatewayId;
    if (source.deviceName !== undefined) target.deviceName = source.deviceName;
    if (source.roomName !== undefined) target.roomName = source.roomName;
    if (source.deviceType !== undefined) target.deviceType = source.deviceType;
    if (source.brand !== undefined) target.brand = source.brand;
    if (source.protocol !== undefined) target.protocol = source.protocol;
    if (source.moduleId !== undefined) target.moduleId = source.moduleId;
    if (source.online !== undefined) target.online = source.online;
    if (source.power !== undefined) target.power = source.power;
    if (source.open !== undefined) target.open = source.open;
    if (source.brightness !== undefined) target.brightness = source.brightness;
    if (source.color !== undefined) target.color = source.color;
    if (source.position !== undefined) target.position = source.position;
    if (source.speed !== undefined) target.speed = source.speed;
    if (source.volume !== undefined) target.volume = source.volume;
    if (source.temperature !== undefined) target.temperature = source.temperature;
    if (source.humidity !== undefined) target.humidity = source.humidity;
    if (source.presence !== undefined) target.presence = source.presence;
    if (source.targetTemperature !== undefined) target.targetTemperature = source.targetTemperature;
    if (source.mode !== undefined) target.mode = source.mode;
    if (source.eventTime !== undefined) target.eventTime = source.eventTime;
    if (source.lastRequestId !== undefined) target.lastRequestId = source.lastRequestId;
    if (source.lastSequence !== undefined) target.lastSequence = source.lastSequence;
    if (source.stateSource !== undefined) target.stateSource = source.stateSource;
    if (source.triggerDeviceId !== undefined) target.triggerDeviceId = source.triggerDeviceId;
    if (source.automationId !== undefined) target.automationId = source.automationId;
  }

  private toReportedState(payload: CloudReportedPayload, fallbackId: string): DeviceReportedState {
    return {
      deviceId: payload.device_id === undefined ?
        (payload.deviceId === undefined ? fallbackId : payload.deviceId) : payload.device_id,
      gatewayId: this.config.gatewayId,
      deviceName: payload.device_name === undefined ? payload.deviceName : payload.device_name,
      roomName: payload.room_name === undefined ? payload.roomName : payload.room_name,
      deviceType: payload.device_type === undefined ? payload.deviceType : payload.device_type,
      brand: payload.brand,
      protocol: payload.protocol,
      moduleId: payload.module_id === undefined ? payload.moduleId : payload.module_id,
      online: payload.online,
      power: payload.power,
      open: payload.open,
      brightness: payload.brightness,
      color: payload.color,
      position: payload.position,
      speed: payload.speed,
      volume: payload.volume,
      temperature: payload.temperature,
      humidity: payload.humidity,
      presence: payload.presence,
      targetTemperature: payload.target_temperature === undefined ? payload.targetTemperature : payload.target_temperature,
      mode: payload.mode,
      stateSource: payload.state_source === undefined ? payload.stateSource : payload.state_source,
      triggerDeviceId: payload.trigger_device_id === undefined ? payload.triggerDeviceId : payload.trigger_device_id,
      automationId: payload.automation_id === undefined ? payload.automationId : payload.automation_id,
      eventTime: payload.event_time === undefined ? payload.eventTime : payload.event_time,
      lastRequestId: payload.last_request_id === undefined ? payload.lastRequestId : payload.last_request_id,
      lastSequence: payload.last_seq === undefined ? payload.lastSeq : payload.last_seq
    };
  }

  private resolveCommandEndpoint(): string {
    if (this.config.commandEndpoint.length > 0) {
      return this.config.commandEndpoint;
    }
    if (this.config.iotdaEndpoint.length === 0 || this.config.projectId.length === 0 || this.config.deviceId.length === 0) {
      return '';
    }
    return `${this.trimSlash(this.config.iotdaEndpoint)}/v5/iot/${this.config.projectId}/devices/${this.config.deviceId}/commands`;
  }

  private resolveShadowEndpoint(): string {
    if (this.config.shadowEndpoint.length > 0) {
      return this.config.shadowEndpoint;
    }
    if (this.config.iotdaEndpoint.length === 0 || this.config.projectId.length === 0 || this.config.deviceId.length === 0) {
      return '';
    }
    return `${this.trimSlash(this.config.iotdaEndpoint)}/v5/iot/${this.config.projectId}/devices/${this.config.deviceId}/shadow`;
  }

  private validateEndpoint(endpoint: string, requiresAuth: boolean): string {
    if (endpoint.length === 0) {
      return I18nService.t('请填写 IoTDA Endpoint、Project ID 和 Device ID');
    }
    if (!endpoint.startsWith('https://')) {
      return I18nService.t('云端 Endpoint 必须使用 HTTPS');
    }
    if (requiresAuth && this.config.accessToken.length === 0) {
      return I18nService.t('请填写有效的 IAM X-Auth-Token');
    }
    return '';
  }

  private buildHeaders(endpoint: string): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
    if (this.config.accessToken.length > 0) {
      if (this.isDirectIoTDAEndpoint(endpoint)) {
        headers['X-Auth-Token'] = this.config.accessToken;
      } else {
        headers['Authorization'] = `Bearer ${this.config.accessToken}`;
      }
    }
    const instanceId = this.config.instanceId.length > 0 ? this.config.instanceId : this.config.tenantId;
    if (instanceId.length > 0) {
      headers['Instance-Id'] = instanceId;
    }
    return headers;
  }

  private normalizeConfig(config: CloudConfig): CloudConfig {
    return {
      commandEndpoint: config.commandEndpoint.trim(),
      shadowEndpoint: config.shadowEndpoint.trim(),
      accessToken: config.accessToken.trim(),
      tenantId: config.tenantId.trim(),
      iotdaEndpoint: config.iotdaEndpoint.trim(),
      projectId: config.projectId.trim(),
      deviceId: config.deviceId.trim(),
      gatewayId: config.gatewayId.trim(),
      instanceId: config.instanceId.trim(),
      serviceId: config.serviceId.trim().length === 0 ? GatewayDefaults.SERVICE_ID : config.serviceId.trim()
    };
  }

  private cloudFailure(
    message: string,
    startedAt: number,
    errorCode: string,
    attempts: number = 0,
    requestId?: string,
    sequence?: number
  ): ControlResult {
    return {
      success: false,
      route: ControlRoute.CLOUD,
      message: message,
      latencyMs: new Date().getTime() - startedAt,
      confirmed: false,
      requestId: requestId,
      sequence: sequence,
      notBeforeMs: startedAt,
      attempts: attempts,
      errorCode: errorCode
    };
  }

  private readError(raw: string): string {
    try {
      const payload = JSON.parse(raw) as IoTDAResponsePayload;
      if (payload.error_msg !== undefined && payload.error_msg.length > 0) {
        return payload.error_msg;
      }
      if (payload.message !== undefined && payload.message.length > 0) {
        return payload.message;
      }
      if (payload.error_code !== undefined) {
        return payload.error_code;
      }
    } catch (error) {
    }
    return '';
  }

  private firstProperty(
    properties: Record<string, string | number | boolean>,
    keys: string[]
  ): string | number | boolean | undefined {
    for (let index = 0; index < keys.length; index++) {
      if (properties[keys[index]] !== undefined) {
        return properties[keys[index]];
      }
    }
    return undefined;
  }

  private toBoolean(value: string | number | boolean): boolean | undefined {
    if (typeof value === 'boolean') return value;
    if (typeof value === 'number') {
      if (value === 1) return true;
      if (value === 0) return false;
      return undefined;
    }
    const lower = value.toLowerCase();
    if (lower === 'on' || lower === 'open' || lower === 'true' || lower === '1' || lower === 'running') {
      return true;
    }
    if (lower === 'off' || lower === 'closed' || lower === 'false' || lower === '0' || lower === 'stopped') {
      return false;
    }
    return undefined;
  }

  private toOpen(value: string | number | boolean): boolean | undefined {
    if (typeof value === 'string') {
      const lower = value.toLowerCase();
      if (lower === 'open' || lower === 'opened' || lower === 'true' || lower === '1') return true;
      if (lower === 'closed' || lower === 'close' || lower === 'false' || lower === '0') return false;
      return undefined;
    }
    return this.toBoolean(value);
  }

  private toNumber(value: string | number | boolean): number {
    if (typeof value === 'number') return value;
    if (typeof value === 'boolean') return value ? 1 : 0;
    const parsed = Number(value);
    return Number.isNaN(parsed) ? 0 : parsed;
  }

  private retryableStatus(code: number): boolean {
    return code === 408 || code === 429 || code >= 500;
  }

  private isDirectIoTDAEndpoint(endpoint: string): boolean {
    return endpoint.indexOf('/v5/iot/') >= 0;
  }

  private trimSlash(value: string): string {
    let result = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  private latestEventTime(states: DeviceReportedState[]): string {
    let latest = '';
    for (let index = 0; index < states.length; index++) {
      if (states[index].eventTime !== undefined && (states[index].eventTime as string) > latest) {
        latest = states[index].eventTime as string;
      }
    }
    return latest;
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}
