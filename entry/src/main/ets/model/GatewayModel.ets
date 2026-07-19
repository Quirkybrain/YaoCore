/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from '../service/I18nService';
import { GatewayDefaults } from '../common/constants/DeviceConstants';
import { DeviceType } from './DeviceModel';

export interface GatewayState {
  gatewayId: string;
  gatewayName: string;
  localIp: string;
  localAvailable: boolean;
  cloudAvailable: boolean;
  secureTransport: boolean;
  lastSyncAt: string;
  latencyMs: number;
  port?: number;
  discoveryMethod?: string;
  failureCount?: number;
}

export interface DiscoveredGateway {
  gatewayId: string;
  gatewayName: string;
  localIp: string;
  port: number;
  serviceId: string;
  protocolVersion: number;
  discoveryMethod: string;
  secureTransport: boolean;
  latencyMs: number;
  deviceCount: number;
  lastSeenAt: string;
}

/**
 * Non-secret identity returned by BLE provisioning and retained until the
 * authenticated LAN binding has completed. Keeping this small record allows
 * the App to resume after a page change or process restart without asking the
 * user to provision Wi-Fi again.
 */
export interface PendingGatewayBindingState {
  gatewayId: string;
  gatewayName: string;
  ipAddress: string;
  protocolVersion: string;
}

export interface DiscoveredDevice {
  deviceId: string;
  deviceName: string;
  roomName: string;
  deviceType: DeviceType;
  brand?: string;
  gatewayId: string;
  localIp: string;
  protocol: string;
  isOnline?: boolean;
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
  stateSource?: string;
  triggerDeviceId?: string;
  automationId?: string;
  lastRequestId?: string;
  lastSequence?: number;
  lastSeenAt: string;
}

export interface DiscoveryResult {
  gateway: GatewayState;
  gateways?: DiscoveredGateway[];
  devices: DiscoveredDevice[];
  scannedHosts: number;
  message: string;
}

export function createDefaultGatewayState(): GatewayState {
  return {
    gatewayId: GatewayDefaults.ID,
    gatewayName: GatewayDefaults.NAME,
    localIp: GatewayDefaults.LOCAL_IP,
    localAvailable: false,
    cloudAvailable: false,
    secureTransport: false,
    lastSyncAt: I18nService.t('尚未连接'),
    latencyMs: 0,
    port: GatewayDefaults.LOCAL_PORT,
    discoveryMethod: I18nService.t('未发现'),
    failureCount: 0
  };
}
