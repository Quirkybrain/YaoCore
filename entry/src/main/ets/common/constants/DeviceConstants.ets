/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from '../../service/I18nService';

export class DeviceIds {
  static readonly DOOR: string = 'Door_01';
  static readonly LIGHT: string = 'Light_01';
  static readonly SENSOR: string = 'Sensor_01';
  static readonly AC: string = 'AC_01';
}

export class GatewayDefaults {
  static readonly ID: string = 'gateway_01';
  static readonly NAME: string = I18nService.t('YaoCore ESP32-S3M 网关');
  static readonly LOCAL_IP: string = '192.168.1.88';
  static readonly LOCAL_PORT: number = 9200;
  static readonly SERVICE_ID: string = 'SmartHomeService';
}
