/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

export type CommandValue = string | number | boolean;

export interface CommandExtra {
  mode?: string;
  brightness?: number;
  color?: string;
  position?: number;
  speed?: number;
  volume?: number;
  source?: string;
}

export interface DeviceControlCommand {
  targetDevice: string;
  action: string;
  value?: CommandValue;
  extra?: CommandExtra;
}

export interface DeviceReportedState {
  deviceId: string;
  gatewayId?: string;
  deviceName?: string;
  roomName?: string;
  deviceType?: string;
  brand?: string;
  protocol?: string;
  moduleId?: string;
  online?: boolean;
  power?: boolean;
  open?: boolean;
  brightness?: number;
  color?: string;
  temperature?: number;
  humidity?: number;
  presence?: boolean;
  targetTemperature?: number;
  mode?: string;
  position?: number;
  speed?: number;
  volume?: number;
  stateSource?: string;
  triggerDeviceId?: string;
  automationId?: string;
  eventTime?: string;
  lastRequestId?: string;
  lastSequence?: number;
}

export enum ControlRoute {
  LOCAL = 'local',
  CLOUD = 'cloud',
  OFFLINE = 'offline'
}

export interface ControlResult {
  success: boolean;
  route: ControlRoute;
  message: string;
  latencyMs: number;
  confirmed?: boolean;
  requestId?: string;
  sequence?: number;
  commandId?: string;
  reportedState?: DeviceReportedState;
  /** 已收到并通过响应HMAC、request_id与seq校验的网关ACK。 */
  acknowledged?: boolean;
  /** 已调用局域网控制 POST；失败时必须按“可能已送达”处理，禁止换路重发同一动作。 */
  deliveryAttempted?: boolean;
  /** 命令开始下发的本机时间；云影子确认不得早于该时刻。 */
  notBeforeMs?: number;
  attempts?: number;
  errorCode?: string;
}

export interface INetworkControlService {
  setLocalRoute(available: boolean, ip: string): void;
  controlDevice(command: DeviceControlCommand): Promise<ControlResult>;
}
