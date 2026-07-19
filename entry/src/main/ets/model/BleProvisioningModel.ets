/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

export interface BleProvisioningDevice {
  deviceId: string;
  deviceName: string;
  serviceUuid: string;
  rssi: number;
}

export interface BleProvisioningRequest {
  device: BleProvisioningDevice;
  ssid: string;
  password: string;
  proofOfPossession: string;
}

export interface BleProvisioningResult {
  success: boolean;
  message: string;
  ipAddress: string;
  /** Security1 会话内由 yaocore-id 端点返回，供入网后 HTTP 身份关联。 */
  expectedGatewayId: string;
  expectedGatewayName: string;
  protocolVersion: string;
  /** Stable diagnostic code shown to the user without exposing credentials. */
  errorCode?: string;
  /** Last completed protocol stage, used to distinguish BLE from LAN binding failures. */
  failedStage?: string;
}

export interface BleWiFiNetwork {
  ssid: string;
  channel: number;
  rssi: number;
  authMode: number;
}

export interface BleProvisioningProgress {
  stage: string;
  message: string;
  percent: number;
}

export type BleProvisioningProgressListener = (progress: BleProvisioningProgress) => void;
