/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { AcAdapterFactory } from '../adapter/ac/AcAdapterFactory';
import { DeviceIds } from '../common/constants/DeviceConstants';
import { ClimateModel, ClimateSnapshot } from '../model/ClimateModel';
import { DeviceState } from '../model/DeviceModel';
import { DeviceRepository } from '../service/DeviceRepository';

export class ClimateViewModel {
  private repository: DeviceRepository = DeviceRepository.getInstance();

  getSnapshot(): ClimateSnapshot {
    return ClimateModel.toSnapshot(
      this.repository.getDevice(DeviceIds.SENSOR),
      this.repository.getDevice(DeviceIds.AC)
    );
  }

  getSensor(): DeviceState {
    return this.repository.getDevice(DeviceIds.SENSOR);
  }

  getAc(): DeviceState {
    return this.repository.getDevice(DeviceIds.AC);
  }

  refreshSensor(): void {
    this.repository.startMonitoring();
  }

  async toggleAc(): Promise<boolean> {
    const ac = this.getAc();
    const acAdapter = AcAdapterFactory.create(ac.brand, ac.deviceId);
    if (ac.powerStatus === true) {
      const result = await acAdapter.powerOff();
      return result.success && result.confirmed === true;
    }
    const result = await acAdapter.powerOn();
    return result.success && result.confirmed === true;
  }

  async setTemperature(temp: number): Promise<boolean> {
    const ac = this.getAc();
    const result = await AcAdapterFactory.create(ac.brand, ac.deviceId).setTargetTemperature(temp);
    return result.success && result.confirmed === true;
  }

  async setMode(mode: string): Promise<boolean> {
    const ac = this.getAc();
    const result = await AcAdapterFactory.create(ac.brand, ac.deviceId).setMode(mode);
    return result.success && result.confirmed === true;
  }
}
