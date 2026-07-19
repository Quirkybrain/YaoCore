/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { DeviceIds } from '../../common/constants/DeviceConstants';
import { ControlResult } from '../../common/types/CommandTypes';
import { DeviceAction } from '../../model/DeviceModel';
import { DeviceRepository } from '../../service/DeviceRepository';
import { AcAdapter } from './AcAdapter';

export class GenericAcAdapter implements AcAdapter {
  protected brand: string = 'Generic';
  protected targetDevice: string = DeviceIds.AC;
  protected repository: DeviceRepository = DeviceRepository.getInstance();

  constructor(brand: string = 'Generic', targetDevice: string = DeviceIds.AC) {
    this.brand = brand;
    this.targetDevice = targetDevice;
  }

  getBrand(): string {
    return this.brand;
  }

  async powerOn(): Promise<ControlResult> {
    return await this.repository.control({
      targetDevice: this.targetDevice,
      action: DeviceAction.TURN_ON,
      extra: {
        source: `adapter:${this.brand}`
      }
    });
  }

  async powerOff(): Promise<ControlResult> {
    return await this.repository.control({
      targetDevice: this.targetDevice,
      action: DeviceAction.TURN_OFF,
      extra: {
        source: `adapter:${this.brand}`
      }
    });
  }

  async setTargetTemperature(temp: number): Promise<ControlResult> {
    return await this.repository.control({
      targetDevice: this.targetDevice,
      action: DeviceAction.SET_TARGET_TEMPERATURE,
      value: temp,
      extra: {
        source: `adapter:${this.brand}`
      }
    });
  }

  async setMode(mode: string): Promise<ControlResult> {
    return await this.repository.control({
      targetDevice: this.targetDevice,
      action: DeviceAction.SET_MODE,
      value: mode,
      extra: {
        source: `adapter:${this.brand}`
      }
    });
  }
}
