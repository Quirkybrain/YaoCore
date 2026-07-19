/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from '../service/I18nService';
import { DeviceAction, DeviceState } from './DeviceModel';

export interface LightSnapshot {
  device: DeviceState;
  brightness: number;
  actionLabel: string;
}

export class LightModel {
  static toSnapshot(device: DeviceState): LightSnapshot {
    const brightness = device.brightness === undefined ? 0 : device.brightness;
    return {
      device: device,
      brightness: brightness,
      actionLabel: device.powerStatus === true ? I18nService.t('关灯') : I18nService.t('开灯')
    };
  }

  static nextAction(device: DeviceState): DeviceAction {
    return device.powerStatus === true ? DeviceAction.TURN_OFF : DeviceAction.TURN_ON;
  }
}
