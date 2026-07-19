/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from '../service/I18nService';

export enum DeviceType {
  DOOR = 'door',
  LIGHT = 'light',
  SENSOR = 'sensor',
  AC = 'ac',
  SWITCH = 'switch',
  CAMERA = 'camera',
  CURTAIN = 'curtain',
  FAN = 'fan',
  SPEAKER = 'speaker'
}

export enum DeviceAction {
  OPEN = 'OPEN',
  CLOSE = 'CLOSE',
  TURN_ON = 'ON',
  TURN_OFF = 'OFF',
  SET_BRIGHTNESS = 'SET_BRIGHTNESS',
  SET_COLOR = 'SET_COLOR',
  SET_TARGET_TEMPERATURE = 'SET_TARGET_TEMPERATURE',
  SET_MODE = 'SET_MODE',
  SET_POSITION = 'SET_POSITION',
  SET_SPEED = 'SET_SPEED',
  SET_VOLUME = 'SET_VOLUME',
  SET_DEVICE_NAME = 'SET_DEVICE_NAME',
  SET_DEVICE_ROOM = 'SET_DEVICE_ROOM',
  STOP = 'STOP'
}

export interface DeviceState {
  deviceId: string;
  deviceName: string;
  roomName: string;
  deviceType: DeviceType;
  brand?: string;
  gatewayId?: string;
  localIp?: string;
  protocol?: string;
  isOnline: boolean;
  powerStatus?: boolean;
  openStatus?: boolean;
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
  /** 网关确认的最近状态来源，例如 sensor.physical、automation.local、app.lan。 */
  stateSource?: string;
  triggerDeviceId?: string;
  automationId?: string;
  updatedAt: string;
  /** 仅用于拒绝旧影子/旧发现覆盖新状态，不作为界面文案。 */
  stateEpochMs?: number;
}

export interface DeviceDraft {
  deviceName: string;
  roomName: string;
  deviceType: DeviceType;
  brand?: string;
  gatewayId?: string;
  localIp?: string;
  protocol?: string;
}

export function copyDeviceState(device: DeviceState): DeviceState {
  return {
    deviceId: device.deviceId,
    deviceName: device.deviceName,
    roomName: device.roomName,
    deviceType: device.deviceType,
    brand: device.brand,
    gatewayId: device.gatewayId,
    localIp: device.localIp,
    protocol: device.protocol,
    isOnline: device.isOnline,
    powerStatus: device.powerStatus,
    openStatus: device.openStatus,
    brightness: device.brightness,
    color: device.color,
    temperature: device.temperature,
    humidity: device.humidity,
    presence: device.presence,
    targetTemperature: device.targetTemperature,
    mode: device.mode,
    position: device.position,
    speed: device.speed,
    volume: device.volume,
    stateSource: device.stateSource,
    triggerDeviceId: device.triggerDeviceId,
    automationId: device.automationId,
    updatedAt: device.updatedAt,
    stateEpochMs: device.stateEpochMs
  };
}

export function createDevicePlaceholder(
  deviceId: string = '',
  deviceName: string = I18nService.t('设备'),
  deviceType: DeviceType = DeviceType.LIGHT
): DeviceState {
  return {
    deviceId: deviceId,
    deviceName: deviceName,
    roomName: '--',
    deviceType: deviceType,
    gatewayId: '',
    localIp: '',
    protocol: 'manual',
    isOnline: false,
    updatedAt: '--',
    stateEpochMs: 0
  };
}
