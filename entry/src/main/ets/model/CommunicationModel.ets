/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { GatewayDefaults } from '../common/constants/DeviceConstants';

export interface LocalRouteConfig {
  localEnabled: boolean;
  gatewayIp: string;
  gatewayPort: number;
  realTransportEnabled: boolean;
  gatewayId?: string;
  gatewayName?: string;
}

export function createDefaultLocalRouteConfig(): LocalRouteConfig {
  return {
    localEnabled: false,
    gatewayIp: GatewayDefaults.LOCAL_IP,
    gatewayPort: GatewayDefaults.LOCAL_PORT,
    realTransportEnabled: false,
    gatewayId: '',
    gatewayName: ''
  };
}
