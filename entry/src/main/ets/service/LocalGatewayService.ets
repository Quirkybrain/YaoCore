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
import { ControlResult, ControlRoute, DeviceControlCommand, DeviceReportedState } from '../common/types/CommandTypes';
import { HttpHeaderUtil } from '../common/utils/HttpHeaderUtil';
import { SecurityService, SignedCommandMeta } from './SecurityService';

interface LocalGatewayPacket {
  request_id: string;
  cmd_id: number;
  seq: number;
  target: string;
  payload: LocalGatewayPayload;
  timestamp: string;
  nonce: string;
  alg: string;
  key_id: string;
  sign: string;
}

interface LocalGatewayPayload {
  action: string;
  value?: string | number | boolean;
}

interface LocalReportedPayload {
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
  isOnline?: boolean;
  power?: boolean;
  powerStatus?: boolean;
  open?: boolean;
  openStatus?: boolean;
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
  targetTemp?: number;
  mode?: string;
  event_time?: string;
  eventTime?: string;
  updated_at?: string;
  updatedAt?: string;
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

interface LocalGatewayAck {
  request_id?: string;
  requestId?: string;
  seq?: number;
  result_code?: number;
  resultCode?: number;
  success?: boolean;
  message?: string;
  error_code?: string;
  errorCode?: string;
  reported_state?: LocalReportedPayload;
  reportedState?: LocalReportedPayload;
  state?: LocalReportedPayload;
}

export class LocalGatewayService {
  private gatewayIp: string = GatewayDefaults.LOCAL_IP;
  private gatewayPort: number = GatewayDefaults.LOCAL_PORT;
  private realTransportEnabled: boolean = false;
  private sequence: number = 10000;
  private securityService: SecurityService = SecurityService.getInstance();

  setGateway(ip: string, port: number = GatewayDefaults.LOCAL_PORT): void {
    this.gatewayIp = ip.trim();
    this.gatewayPort = port;
  }

  setRealTransportEnabled(enabled: boolean): void {
    this.realTransportEnabled = enabled;
  }

  async send(command: DeviceControlCommand): Promise<ControlResult> {
    return await this.sendTo(this.gatewayIp, this.gatewayPort, command, this.realTransportEnabled);
  }

  /**
   * 在尚未绑定时直接验证候选网关。该方法不修改当前路由，避免验证失败污染已保存配置。
   */
  async sendToGateway(ip: string, port: number, command: DeviceControlCommand): Promise<ControlResult> {
    return await this.sendTo(ip.trim(), port, command, true);
  }

  private async sendTo(
    gatewayIp: string,
    gatewayPort: number,
    command: DeviceControlCommand,
    transportEnabled: boolean
  ): Promise<ControlResult> {
    const startedAt = new Date().getTime();
    if (!transportEnabled) {
      return {
        success: false,
        route: ControlRoute.LOCAL,
        message: I18nService.t('真实局域网传输未启用'),
        latencyMs: 0,
        confirmed: false,
        attempts: 0,
        errorCode: 'LOCAL_TRANSPORT_DISABLED'
      };
    }
    if (gatewayIp.length === 0) {
      return {
        success: false,
        route: ControlRoute.LOCAL,
        message: I18nService.t('尚未绑定局域网网关'),
        latencyMs: 0,
        confirmed: false,
        attempts: 0,
        errorCode: 'GATEWAY_NOT_BOUND'
      };
    }

    let packet: LocalGatewayPacket;
    try {
      packet = this.buildPacket(command);
    } catch (error) {
      return {
        success: false,
        route: ControlRoute.LOCAL,
        message: I18nService.t('请先在“我的 > 安全配置”保存至少 16 位命令密钥'),
        latencyMs: new Date().getTime() - startedAt,
        confirmed: false,
        attempts: 0,
        errorCode: 'COMMAND_KEY_NOT_CONFIGURED'
      };
    }

    let lastResult: ControlResult | undefined = undefined;
    const maxAttempts = 2;
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      lastResult = await this.sendOnce(packet, startedAt, attempt, gatewayIp, gatewayPort);
      if (lastResult.success || !this.shouldRetry(lastResult)) {
        return lastResult;
      }
      if (attempt < maxAttempts) {
        await this.delay(70 * attempt);
      }
    }
    return lastResult === undefined ? this.unexpectedFailure(startedAt, packet) : lastResult;
  }

  async testConnection(ip: string, port: number): Promise<ControlResult> {
    const startedAt = new Date().getTime();
    const targetIp = ip.trim().length > 0 ? ip.trim() : this.gatewayIp;
    if (!this.securityService.hasSessionSecret()) {
      return {
        success: false,
        route: ControlRoute.LOCAL,
        message: I18nService.t('请先配置与网关一致的命令密钥，再验证网关身份'),
        latencyMs: 0,
        confirmed: false,
        attempts: 0,
        errorCode: 'COMMAND_KEY_NOT_CONFIGURED'
      };
    }
    const request = http.createHttp();
    try {
      const challenge = this.securityService.createResponseChallenge();
      const requestAuthentication = this.securityService.signDiscoveryRequest(challenge);
      const response = await request.request(`http://${targetIp}:${port}/discover`, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/json',
          'X-YaoCore-Protocol': '2',
          'X-YaoCore-Challenge': challenge,
          'X-YaoCore-Request-Timestamp': requestAuthentication.timestamp,
          'X-YaoCore-Request-Nonce': requestAuthentication.nonce,
          'X-YaoCore-Request-Alg': requestAuthentication.algorithm,
          'X-YaoCore-Key-Id': requestAuthentication.keyId,
          'X-YaoCore-Request-Sign': requestAuthentication.sign
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 1000,
        readTimeout: 1000
      });
      const ok = response.responseCode >= 200 && response.responseCode < 300;
      if (!ok) {
        return {
          success: false,
          route: ControlRoute.LOCAL,
          message: `局域网探测返回 ${response.responseCode}`,
          latencyMs: new Date().getTime() - startedAt,
          confirmed: false,
          attempts: 1,
          errorCode: `HTTP_${response.responseCode}`
        };
      }
      if (this.isSimulatorResponse(response.header)) {
        return {
          success: false,
          route: ControlRoute.LOCAL,
          message: I18nService.t('检测到开发协议模拟器，正式版禁止将其绑定为真实网关'),
          latencyMs: new Date().getTime() - startedAt,
          confirmed: false,
          attempts: 1,
          errorCode: 'DEV_SIMULATOR_REJECTED'
        };
      }
      const raw = `${response.result}`;
      if (!this.isAuthenticatedResponse(response.header, 'discover', challenge, raw)) {
        return {
          success: false,
          route: ControlRoute.LOCAL,
          message: I18nService.t('网关发现响应身份校验失败，未绑定该地址'),
          latencyMs: new Date().getTime() - startedAt,
          confirmed: false,
          attempts: 1,
          errorCode: 'DISCOVERY_RESPONSE_AUTH_FAILED'
        };
      }
      const valid = this.isDiscoveryPayload(raw);
      return {
        success: valid,
        route: ControlRoute.LOCAL,
        message: valid ? `已校验 YaoCore 网关 ${targetIp}:${port}` : I18nService.t('目标响应了 HTTP，但不是有效的 YaoCore 网关'),
        latencyMs: new Date().getTime() - startedAt,
        confirmed: valid,
        attempts: 1,
        errorCode: valid ? undefined : 'INVALID_DISCOVERY_PAYLOAD'
      };
    } catch (error) {
      return {
        success: false,
        route: ControlRoute.LOCAL,
        message: `未连通 ${targetIp}:${port}，请检查网关服务或同网段连接`,
        latencyMs: new Date().getTime() - startedAt,
        confirmed: false,
        attempts: 1,
        errorCode: 'LOCAL_CONNECT_FAILED'
      };
    } finally {
      request.destroy();
    }
  }

  buildPacket(command: DeviceControlCommand): LocalGatewayPacket {
    this.sequence += 1;
    const requestId = this.securityService.createRequestId();
    const signed: SignedCommandMeta = this.securityService.signCommand(command, {
      requestId: requestId,
      commandId: 2001,
      sequence: this.sequence
    });
    const payload: LocalGatewayPayload = {
      action: command.action
    };
    if (command.value !== undefined) {
      payload.value = command.value;
    }
    return {
      request_id: requestId,
      cmd_id: 2001,
      seq: this.sequence,
      target: command.targetDevice,
      payload: payload,
      timestamp: signed.timestamp,
      nonce: signed.nonce,
      alg: signed.algorithm,
      key_id: signed.keyId,
      sign: signed.sign
    };
  }

  private async sendOnce(
    packet: LocalGatewayPacket,
    startedAt: number,
    attempt: number,
    gatewayIp: string,
    gatewayPort: number
  ): Promise<ControlResult> {
    const request = http.createHttp();
    try {
      const response = await request.request(`http://${gatewayIp}:${gatewayPort}/control`, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-YaoCore-Protocol': '2'
        },
        extraData: JSON.stringify(packet),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 900,
        // 门磁和空调下位机的可配置执行超时最高为10秒，预留传输余量。
        readTimeout: 12000
      });
      const raw = `${response.result}`;
      if (this.isSimulatorResponse(response.header)) {
        return this.invalidAck(I18nService.t('检测到开发协议模拟器，拒绝其控制响应'), 'DEV_SIMULATOR_REJECTED', packet,
          startedAt, attempt);
      }
      const correlation = `${packet.request_id}:${packet.seq}`;
      if (!this.isAuthenticatedResponse(response.header, 'control', correlation, raw)) {
        return this.invalidAck(I18nService.t('网关控制响应身份校验失败'), 'CONTROL_RESPONSE_AUTH_FAILED', packet,
          startedAt, attempt);
      }
      const parsed = this.parseAck(raw, packet, startedAt, attempt);
      if ((response.responseCode < 200 || response.responseCode >= 300) && parsed.success) {
        return this.invalidAck(`HTTP ${response.responseCode} 与成功 ACK 冲突`, 'ACK_HTTP_STATUS_MISMATCH', packet,
          startedAt, attempt);
      }
      return parsed;
    } catch (error) {
      return {
        success: false,
        route: ControlRoute.LOCAL,
        message: I18nService.t('局域网控制请求失败'),
        latencyMs: new Date().getTime() - startedAt,
        confirmed: false,
        requestId: packet.request_id,
        sequence: packet.seq,
        deliveryAttempted: true,
        notBeforeMs: startedAt,
        attempts: attempt,
        errorCode: 'LOCAL_REQUEST_FAILED'
      };
    } finally {
      request.destroy();
    }
  }

  private parseAck(raw: string, packet: LocalGatewayPacket, startedAt: number, attempt: number): ControlResult {
    if (raw.trim().length === 0) {
      return this.invalidAck(I18nService.t('网关返回了空 ACK'), 'INVALID_ACK_PAYLOAD', packet, startedAt, attempt);
    }
    try {
      const ack = JSON.parse(raw) as LocalGatewayAck;
      const ackRequestId = ack.request_id === undefined ? ack.requestId : ack.request_id;
      if (ackRequestId !== packet.request_id) {
        return this.invalidAck(I18nService.t('ACK request_id 不匹配'), 'ACK_REQUEST_MISMATCH', packet, startedAt, attempt);
      }
      if (ack.seq !== packet.seq) {
        return this.invalidAck(I18nService.t('ACK seq 不匹配'), 'ACK_SEQUENCE_MISMATCH', packet, startedAt, attempt);
      }
      const resultCode = ack.result_code === undefined ? ack.resultCode : ack.result_code;
      const executed = resultCode === 0;
      const statePayload = ack.reported_state === undefined ?
        (ack.reportedState === undefined ? ack.state : ack.reportedState) : ack.reported_state;
      const reportedState = statePayload === undefined ? undefined : this.toReportedState(statePayload, packet.target);
      const correlated = ackRequestId === packet.request_id && ack.seq === packet.seq;
      const signedAckIsSufficient = packet.payload.action === 'PING' || packet.payload.action === 'BOARD_LED_ON';
      const confirmed = executed && correlated && (reportedState !== undefined || signedAckIsSufficient);
      const errorCode = ack.error_code === undefined ? ack.errorCode : ack.error_code;
      if (!executed) {
        return {
          success: false,
          route: ControlRoute.LOCAL,
          message: ack.message === undefined ? I18nService.t('网关拒绝或执行指令失败') : ack.message,
          latencyMs: new Date().getTime() - startedAt,
          confirmed: false,
          requestId: packet.request_id,
          sequence: packet.seq,
          reportedState: reportedState,
          acknowledged: true,
          deliveryAttempted: true,
          notBeforeMs: startedAt,
          attempts: attempt,
          errorCode: errorCode === undefined ? 'GATEWAY_EXECUTION_FAILED' : errorCode
        };
      }
      return {
        success: true,
        route: ControlRoute.LOCAL,
        message: confirmed ? I18nService.t('网关已确认设备执行') : I18nService.t('网关已接收，正在读取设备状态'),
        latencyMs: new Date().getTime() - startedAt,
        confirmed: confirmed,
        requestId: packet.request_id,
        sequence: packet.seq,
        reportedState: reportedState,
        acknowledged: true,
        deliveryAttempted: true,
        notBeforeMs: startedAt,
        attempts: attempt
      };
    } catch (error) {
      return this.invalidAck(I18nService.t('网关 ACK 不是有效 JSON'), 'INVALID_ACK_PAYLOAD', packet, startedAt, attempt);
    }
  }

  private toReportedState(payload: LocalReportedPayload, fallbackId: string): DeviceReportedState {
    return {
      deviceId: payload.device_id === undefined ? (payload.deviceId === undefined ? fallbackId : payload.deviceId) : payload.device_id,
      deviceName: payload.device_name === undefined ? payload.deviceName : payload.device_name,
      roomName: payload.room_name === undefined ? payload.roomName : payload.room_name,
      deviceType: payload.device_type === undefined ? payload.deviceType : payload.device_type,
      brand: payload.brand,
      protocol: payload.protocol,
      moduleId: payload.module_id === undefined ? payload.moduleId : payload.module_id,
      online: payload.online === undefined ? payload.isOnline : payload.online,
      power: payload.power === undefined ? payload.powerStatus : payload.power,
      open: payload.open === undefined ? payload.openStatus : payload.open,
      brightness: payload.brightness,
      color: payload.color,
      position: payload.position,
      speed: payload.speed,
      volume: payload.volume,
      temperature: payload.temperature,
      humidity: payload.humidity,
      presence: payload.presence,
      targetTemperature: payload.target_temperature === undefined ?
        (payload.targetTemperature === undefined ? payload.targetTemp : payload.targetTemperature) : payload.target_temperature,
      mode: payload.mode,
      stateSource: payload.state_source === undefined ? payload.stateSource : payload.state_source,
      triggerDeviceId: payload.trigger_device_id === undefined ? payload.triggerDeviceId : payload.trigger_device_id,
      automationId: payload.automation_id === undefined ? payload.automationId : payload.automation_id,
      eventTime: payload.event_time === undefined ?
        (payload.eventTime === undefined ?
          (payload.updated_at === undefined ? payload.updatedAt : payload.updated_at) : payload.eventTime) : payload.event_time,
      lastRequestId: payload.last_request_id === undefined ? payload.lastRequestId : payload.last_request_id,
      lastSequence: payload.last_seq === undefined ? payload.lastSeq : payload.last_seq
    };
  }

  private invalidAck(
    message: string,
    code: string,
    packet: LocalGatewayPacket,
    startedAt: number,
    attempt: number
  ): ControlResult {
    return {
      success: false,
      route: ControlRoute.LOCAL,
      message: message,
      latencyMs: new Date().getTime() - startedAt,
      confirmed: false,
      requestId: packet.request_id,
      sequence: packet.seq,
      deliveryAttempted: true,
      notBeforeMs: startedAt,
      attempts: attempt,
      errorCode: code
    };
  }

  private shouldRetry(result: ControlResult): boolean {
    return result.errorCode === 'LOCAL_REQUEST_FAILED' ||
      result.errorCode === 'HTTP_408' ||
      result.errorCode === 'HTTP_429' ||
      (result.errorCode !== undefined && result.errorCode.startsWith('HTTP_5'));
  }

  private isDiscoveryPayload(raw: string): boolean {
    try {
      const payload = JSON.parse(raw) as Record<string, Object>;
      const gatewayId = payload['gatewayId'] === undefined ? payload['gateway_id'] : payload['gatewayId'];
      const serviceId = payload['serviceId'] === undefined ? payload['service_id'] : payload['serviceId'];
      const protocolVersion = payload['protocolVersion'] === undefined ? payload['protocol_version'] : payload['protocolVersion'];
      const security = payload['security'];
      const securityText = security === undefined ? '' : JSON.stringify(security);
      return gatewayId !== undefined &&
        `${serviceId}` === GatewayDefaults.SERVICE_ID && `${protocolVersion}` === '2.0' &&
        securityText.indexOf('HMAC-SHA256') >= 0 && securityText.indexOf('app-key-v1') >= 0 &&
        payload['devices'] !== undefined;
    } catch (error) {
      return false;
    }
  }

  private isSimulatorResponse(header: Object): boolean {
    const marker = HttpHeaderUtil.getValue(header, 'X-YaoCore-Simulator').toUpperCase();
    if (marker.indexOf('DEV-ONLY') >= 0) {
      return true;
    }
    try {
      const text = JSON.stringify(header).toUpperCase();
      return text.indexOf('X-YAOCORE-SIMULATOR') >= 0 || text.indexOf('DEV-ONLY') >= 0;
    } catch (error) {
      return false;
    }
  }

  private isAuthenticatedResponse(header: Object, kind: string, correlation: string, body: string): boolean {
    return this.securityService.verifyResponseAuthentication(
      kind,
      correlation,
      body,
      HttpHeaderUtil.getValue(header, 'X-YaoCore-Response-Alg'),
      HttpHeaderUtil.getValue(header, 'X-YaoCore-Key-Id'),
      HttpHeaderUtil.getValue(header, 'X-YaoCore-Response-Correlation'),
      HttpHeaderUtil.getValue(header, 'X-YaoCore-Response-Sign')
    );
  }

  private unexpectedFailure(startedAt: number, packet: LocalGatewayPacket): ControlResult {
    return {
      success: false,
      route: ControlRoute.LOCAL,
      message: I18nService.t('局域网控制出现未知错误'),
      latencyMs: new Date().getTime() - startedAt,
      confirmed: false,
      requestId: packet.request_id,
      sequence: packet.seq,
      notBeforeMs: startedAt,
      attempts: 0,
      errorCode: 'LOCAL_UNKNOWN_ERROR'
    };
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}
