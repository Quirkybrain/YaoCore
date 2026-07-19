/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import UIAbility from '@ohos.app.ability.UIAbility';
import window from '@ohos.window';
import { BusinessError } from '@ohos.base';
import { AppStorageService } from '../service/AppStorageService';
import { BleProvisioningService } from '../service/BleProvisioningService';
import { DeviceRepository } from '../service/DeviceRepository';
import { GatewayDiscoveryService } from '../service/GatewayDiscoveryService';
import { LiveActivityService } from '../service/LiveActivityService';

export default class EntryAbility extends UIAbility {
  private isForeground: boolean = false;

  onCreate(): void {
    AppStorageService.initialize(this.context);
    BleProvisioningService.getInstance().initialize(this.context);
    LiveActivityService.initialize(this.context);
    GatewayDiscoveryService.getInstance().initialize(this.context);
    const repository = DeviceRepository.getInstance();
    repository.load();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        console.error(`YaoCore load content failed: ${err.code}, ${err.message}`);
      }
    });
  }

  onBackground(): void {
    this.isForeground = false;
    const repository = DeviceRepository.getInstance();
    repository.stopMonitoring();
    LiveActivityService.publishSnapshot(repository.getDevices(), repository.getGateway());
  }

  onForeground(): void {
    this.isForeground = true;
    this.startRepositoryMonitoring();
  }

  private async startRepositoryMonitoring(): Promise<void> {
    const repository = DeviceRepository.getInstance();
    await repository.load();
    if (this.isForeground) {
      repository.startMonitoring();
    }
  }
}
