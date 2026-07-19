/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import {
  BleProvisioningDevice,
  BleProvisioningProgressListener,
  BleProvisioningRequest,
  BleProvisioningResult,
  BleWiFiNetwork
} from '../model/BleProvisioningModel';
import { BleProvisioningService } from '../service/BleProvisioningService';

export class BleProvisioningViewModel {
  private service: BleProvisioningService = BleProvisioningService.getInstance();

  async scan(): Promise<BleProvisioningDevice[]> {
    return await this.service.scanGateways();
  }

  async provision(
    device: BleProvisioningDevice,
    ssid: string,
    password: string,
    proofOfPossession: string,
    listener?: BleProvisioningProgressListener
  ): Promise<BleProvisioningResult> {
    const request: BleProvisioningRequest = {
      device: device,
      ssid: ssid,
      password: password,
      proofOfPossession: proofOfPossession
    };
    return await this.service.provision(request, listener);
  }

  async scanWiFiNetworks(
    device: BleProvisioningDevice,
    proofOfPossession: string,
    listener?: BleProvisioningProgressListener
  ): Promise<BleWiFiNetwork[]> {
    return await this.service.scanWiFiNetworks(device, proofOfPossession, listener);
  }

  disconnect(): void {
    this.service.disconnect();
  }
}
