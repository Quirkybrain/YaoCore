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

export interface DoorSnapshot {
  device: DeviceState;
  isLocked: boolean;
  actionLabel: string;
}

export class DoorModel {
  static toSnapshot(device: DeviceState): DoorSnapshot {
    const locked = device.openStatus !== true;
    return {
      device: device,
      isLocked: locked,
      actionLabel: locked ? I18nService.t('开门') : I18nService.t('上锁')
    };
  }

  static nextAction(device: DeviceState): DeviceAction {
    return device.openStatus === true ? DeviceAction.CLOSE : DeviceAction.OPEN;
  }
}
