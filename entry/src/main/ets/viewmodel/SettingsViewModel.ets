/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { CloudConfig, CloudSyncResult } from '../model/CloudModel';
import { ControlResult } from '../common/types/CommandTypes';
import { LocalRouteConfig } from '../model/CommunicationModel';
import { DeviceState } from '../model/DeviceModel';
import { DiscoveryResult, GatewayState } from '../model/GatewayModel';
import { AuthSession } from '../model/UserModel';
import { AuthResult, AuthService } from '../service/AuthService';
import { DeviceRepository } from '../service/DeviceRepository';
import { LiveActivityService } from '../service/LiveActivityService';
import { NetworkService } from '../service/NetworkService';
import { SecurityService } from '../service/SecurityService';

export class SettingsViewModel {
  private repository: DeviceRepository = DeviceRepository.getInstance();
  private networkService: NetworkService = NetworkService.getInstance();
  private securityService: SecurityService = SecurityService.getInstance();
  private authService: AuthService = AuthService.getInstance();

  async load(): Promise<void> {
    await this.repository.load();
    await this.authService.load();
    await this.networkService.loadCloudConfig();
  }

  getGateway(): GatewayState {
    return this.repository.getGateway();
  }

  getSession(): AuthSession {
    return this.authService.getSession();
  }

  hasLocalAccount(): boolean {
    return this.authService.hasLocalAccount();
  }

  getDeviceCount(): number {
    return this.repository.getDevices().length;
  }

  getOnlineDeviceCount(): number {
    const devices: DeviceState[] = this.repository.getDevices();
    let count = 0;
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].isOnline) {
        count += 1;
      }
    }
    return count;
  }

  async register(email: string, password: string): Promise<AuthResult> {
    return await this.authService.register(email, password);
  }

  async login(email: string, password: string): Promise<AuthResult> {
    return await this.authService.login(email, password);
  }

  async logout(): Promise<AuthResult> {
    return await this.authService.logout();
  }

  consumeLocalProfileNotice(): string {
    return this.authService.consumeProfileNotice();
  }

  async refreshGateway(): Promise<GatewayState> {
    return await this.repository.refreshGateway();
  }

  async syncGatewayStatus(): Promise<DiscoveryResult> {
    return await this.repository.syncGatewayStatus();
  }

  async syncDevicesToCloud(): Promise<CloudSyncResult> {
    return await this.repository.syncDevicesToCloud();
  }

  setLocalRoute(enabled: boolean, ip: string): void {
    this.networkService.setLocalRoute(enabled, ip);
    this.networkService.setRealLocalTransportEnabled(enabled && ip.length > 0);
  }

  async saveLocalRoute(config: LocalRouteConfig): Promise<void> {
    await this.networkService.saveLocalRoute(config);
  }

  getLocalRouteConfig(): LocalRouteConfig {
    return this.networkService.getLocalRouteConfig();
  }

  setCloudEndpoint(endpoint: string): void {
    this.networkService.setCloudEndpoint(endpoint);
  }

  getCloudConfig(): CloudConfig {
    return this.networkService.getCloudConfig();
  }

  async saveCloudConfig(config: CloudConfig): Promise<void> {
    await this.networkService.saveCloudConfig(config);
  }

  async testLocalGateway(ip: string, port: number): Promise<ControlResult> {
    return await this.networkService.testLocalGateway(ip, port);
  }

  async testCloudConnection(): Promise<ControlResult> {
    return await this.networkService.testCloudConnection();
  }

  async sendDiagnosticCommand(): Promise<ControlResult> {
    return await this.networkService.sendDiagnosticCommand();
  }

  async turnGatewayLedOn(): Promise<ControlResult> {
    return await this.networkService.turnGatewayLedOn();
  }

  getLastControlResult(): ControlResult {
    return this.networkService.getLastResult();
  }

  async setSessionSecret(secret: string): Promise<boolean> {
    return await this.networkService.saveCommandSecret(secret);
  }

  hasSessionSecret(): boolean {
    return this.networkService.hasCommandSecret();
  }

  async enableLiveActivity(): Promise<boolean> {
    return await LiveActivityService.requestNotificationEnabled();
  }

  async publishLiveActivity(): Promise<boolean> {
    return await LiveActivityService.publishSnapshot(this.repository.getDevices(), this.repository.getGateway());
  }

  getLiveActivityDesignNote(): string {
    return LiveActivityService.getDesignNote();
  }
}
