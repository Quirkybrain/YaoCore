/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from '../service/I18nService';
import { DeviceState } from './DeviceModel';

export interface ClimateSnapshot {
  sensor: DeviceState;
  ac: DeviceState;
  comfortLabel: string;
  humidityLabel: string;
}

export class ClimateModel {
  static toSnapshot(sensor: DeviceState, ac: DeviceState): ClimateSnapshot {
    const temperature = sensor.temperature === undefined ? 0 : sensor.temperature;
    const humidity = sensor.humidity === undefined ? 0 : sensor.humidity;
    let comfortLabel = I18nService.t('舒适');
    if (temperature >= 29) {
      comfortLabel = I18nService.t('偏热');
    } else if (temperature <= 18) {
      comfortLabel = I18nService.t('偏冷');
    }
    let humidityLabel = I18nService.t('湿度适中');
    if (humidity >= 70) {
      humidityLabel = I18nService.t('湿度偏高');
    } else if (humidity <= 35) {
      humidityLabel = I18nService.t('湿度偏低');
    }
    return {
      sensor: sensor,
      ac: ac,
      comfortLabel: comfortLabel,
      humidityLabel: humidityLabel
    };
  }
}
