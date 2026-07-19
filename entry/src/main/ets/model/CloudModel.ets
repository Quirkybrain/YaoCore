/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { DeviceReportedState } from '../common/types/CommandTypes';

export interface CloudConfig {
  commandEndpoint: string;
  shadowEndpoint: string;
  accessToken: string;
  tenantId: string;
  iotdaEndpoint: string;
  projectId: string;
  deviceId: string;
  /** Logical YaoCore gateway represented by this IoTDA device. */
  gatewayId: string;
  instanceId: string;
  serviceId: string;
}

export interface CloudSyncResult {
  success: boolean;
  message: string;
  latencyMs: number;
  confirmedCount?: number;
  reportedStates?: DeviceReportedState[];
  eventTime?: string;
  errorCode?: string;
}

export function createDefaultCloudConfig(): CloudConfig {
  return {
    commandEndpoint: '',
    shadowEndpoint: '',
    accessToken: '',
    tenantId: '',
    iotdaEndpoint: '',
    projectId: '',
    deviceId: '',
    gatewayId: '',
    instanceId: '',
    serviceId: 'SmartHomeService'
  };
}
