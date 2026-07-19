/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { DeviceIds } from '../common/constants/DeviceConstants';
import { ControlResult } from '../common/types/CommandTypes';
import { DeviceAction, DeviceState } from '../model/DeviceModel';
import { DeviceRepository } from '../service/DeviceRepository';

export class DoorViewModel {
  private repository: DeviceRepository = DeviceRepository.getInstance();

  getDoor(): DeviceState {
    return this.repository.getDevice(DeviceIds.DOOR);
  }

  async open(): Promise<ControlResult> {
    return await this.repository.control({
      targetDevice: DeviceIds.DOOR,
      action: DeviceAction.OPEN,
      extra: {
        source: 'door'
      }
    });
  }

  async close(): Promise<ControlResult> {
    return await this.repository.control({
      targetDevice: DeviceIds.DOOR,
      action: DeviceAction.CLOSE,
      extra: {
        source: 'door'
      }
    });
  }
}
