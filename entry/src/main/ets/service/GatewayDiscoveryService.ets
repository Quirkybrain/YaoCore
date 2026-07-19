/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from './I18nService';
import common from '@ohos.app.ability.common';
import connection from '@ohos.net.connection';
import http from '@ohos.net.http';
import mdns from '@ohos.net.mdns';
import socket from '@ohos.net.socket';
import util from '@ohos.util';
import { GatewayDefaults } from '../common/constants/DeviceConstants';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import { HttpHeaderUtil } from '../common/utils/HttpHeaderUtil';
import { DeviceType } from '../model/DeviceModel';
import {
  createDefaultGatewayState,
  DiscoveredDevice,
  DiscoveredGateway,
  DiscoveryResult,
  GatewayState
} from '../model/GatewayModel';
import { SecurityService } from './SecurityService';

interface GatewayDevicePayload {
  deviceId?: string;
  device_id?: string;
  id?: string;
  deviceName?: string;
  device_name?: string;
  name?: string;
  roomName?: string;
  room_name?: string;
  room?: string;
  deviceType?: string;
  device_type?: string;
  type?: string;
  brand?: string;
  protocol?: string;
  moduleId?: string;
  module_id?: string;
  isOnline?: boolean;
  online?: boolean;
  powerStatus?: boolean;
  power?: boolean | number | string;
  openStatus?: boolean;
  open?: boolean | number | string;
  brightness?: number;
  bright?: number;
  color?: string;
  temperature?: number;
  humidity?: number;
  presence?: boolean;
  occupied?: boolean;
  targetTemperature?: number;
  target_temperature?: number;
  targetTemp?: number;
  mode?: string;
  position?: number;
  speed?: number;
  volume?: number;
  updatedAt?: string;
  updated_at?: string;
  eventTime?: string;
  event_time?: string;
  lastRequestId?: string;
  last_request_id?: string;
  lastSeq?: number;
  last_seq?: number;
  stateSource?: string;
  state_source?: string;
  triggerDeviceId?: string;
  trigger_device_id?: string;
  automationId?: string;
  automation_id?: string;
}

interface GatewayDiscoveryPayload {
  gatewayId?: string;
  gateway_id?: string;
  gatewayName?: string;
  gateway_name?: string;
  name?: string;
  serviceId?: string;
  service_id?: string;
  protocolVersion?: number | string;
  protocol_version?: number | string;
  secureTransport?: boolean;
  secure_transport?: boolean;
  security?: GatewaySecurityPayload;
  generatedAt?: string;
  generated_at?: string;
  port?: number;
  devices?: GatewayDevicePayload[];
}

interface GatewaySecurityPayload {
  alg?: string;
  keyId?: string;
  key_id?: string;
}

interface DiscoveryCandidate {
  ip: string;
  port: number;
  method: string;
}

interface NetworkInfo {
  address: string;
  prefixLength: number;
  neighbors: string[];
}

export interface GatewayProbeOutcome {
  result?: DiscoveryResult;
  errorCode: string;
  message: string;
}

export class GatewayDiscoveryService {
  private static instance: GatewayDiscoveryService | undefined;
  private context: common.Context | undefined;
  private gateway: GatewayState = createDefaultGatewayState();
  private lastDevices: DiscoveredDevice[] = [];
  private lastGateways: DiscoveredGateway[] = [];
  private configuredPort: number = GatewayDefaults.LOCAL_PORT;
  private boundGatewayId: string = '';
  private failureCount: number = 0;
  private securityService: SecurityService = SecurityService.getInstance();

  static getInstance(): GatewayDiscoveryService {
    if (GatewayDiscoveryService.instance === undefined) {
      GatewayDiscoveryService.instance = new GatewayDiscoveryService();
    }
    return GatewayDiscoveryService.instance;
  }

  initialize(context: common.Context): void {
    this.context = context;
  }

  async scan(): Promise<GatewayState> {
    const result = await this.scanLanDevices();
    return this.copyGateway(result.gateway);
  }

  async scanLanDevices(limit: number = 64): Promise<DiscoveryResult> {
    const startedAt = new Date().getTime();
    if (!this.securityService.hasSessionSecret()) {
      this.gateway.localAvailable = false;
      this.gateway.discoveryMethod = I18nService.t('未配置控制密钥');
      this.gateway.lastSyncAt = DateTimeUtil.nowDisplay();
      this.gateway.latencyMs = 0;
      this.lastDevices = [];
      this.lastGateways = [];
      return {
        gateway: this.copyGateway(this.gateway),
        gateways: [],
        devices: [],
        scannedHosts: 0,
        message: I18nService.t('尚未配置网关控制密钥，请先到“我的 > 安全配置”保存与网关一致的密钥')
      };
    }
    const candidates: DiscoveryCandidate[] = [];
    this.addCandidate(candidates, this.gateway.localIp, this.configuredPort, I18nService.t('已绑定地址'));

    const mdnsTask = this.discoverByMdns(700);
    const udpTask = this.discoverByUdp(700);
    const networkTask = this.resolveNetworkInfo();
    const mdnsCandidates = await mdnsTask;
    const udpCandidates = await udpTask;
    const network = await networkTask;
    this.mergeCandidates(candidates, mdnsCandidates);
    this.mergeCandidates(candidates, udpCandidates);
    for (let index = 0; index < network.neighbors.length; index++) {
      this.addCandidate(candidates, network.neighbors[index], this.configuredPort, I18nService.t('邻居表'));
    }

    let scannedHosts = 0;
    let results = await this.probeCandidates(candidates, 6);
    scannedHosts += candidates.length;
    if (results.length === 0) {
      const fallback = this.createFallbackCandidates(network, limit);
      // A subnet sweep is recovery only. Probe a small bounded batch and stop
      // as soon as one authenticated gateway answers; creating hundreds of
      // simultaneous Harmony HTTP tasks can starve the real gateway request.
      results = await this.probeCandidates(fallback, 8, true);
      scannedHosts += fallback.length;
    }
    return this.mergeResults(results, scannedHosts, startedAt);
  }

  async probeConfiguredGateway(ip: string, port: number): Promise<DiscoveryResult | undefined> {
    const outcome = await this.probeConfiguredGatewayDetailed(ip, port);
    return outcome.result;
  }

  async probeConfiguredGatewayDetailed(ip: string, port: number): Promise<GatewayProbeOutcome> {
    return await this.probeHostDetailed({
      ip: ip,
      port: port,
      method: I18nService.t('已绑定地址')
    });
  }

  async checkConfiguredGateway(ip: string, port: number): Promise<DiscoveryResult> {
    const startedAt = new Date().getTime();
    const result = await this.probeConfiguredGateway(ip, port);
    return this.mergeResults(result === undefined ? [] : [result], 1, startedAt);
  }

  /**
   * BLE has already authenticated a logical gatewayId. Prefer mDNS/UDP
   * candidates and only then use a bounded subnet fallback. Every HTTP result
   * still needs the control-key HMAC and must match that exact BLE identity.
   */
  async scanProvisionedGateway(expectedGatewayId: string, limit: number = 64): Promise<DiscoveredGateway | undefined> {
    const normalizedGatewayId = expectedGatewayId.trim();
    if (normalizedGatewayId.length === 0) return undefined;
    if (!this.securityService.hasSessionSecret()) throw new Error('COMMAND_KEY_NOT_CONFIGURED');

    const candidates: DiscoveryCandidate[] = [];
    this.addCandidate(candidates, this.gateway.localIp, this.configuredPort, I18nService.t('已绑定地址'));
    const mdnsTask = this.discoverByMdns(700);
    const udpTask = this.discoverByUdp(700);
    const networkTask = this.resolveNetworkInfo();
    this.mergeCandidates(candidates, await mdnsTask);
    this.mergeCandidates(candidates, await udpTask);
    const network = await networkTask;
    for (let index = 0; index < network.neighbors.length; index++) {
      this.addCandidate(candidates, network.neighbors[index], this.configuredPort, I18nService.t('邻居表'));
    }

    let matched = await this.probeCandidatesForGateway(candidates, 6, normalizedGatewayId);
    if (matched !== undefined) return matched;
    const fallback = this.createFallbackCandidates(network, limit);
    matched = await this.probeCandidatesForGateway(fallback, 8, normalizedGatewayId);
    return matched;
  }

  getGateway(): GatewayState {
    return this.copyGateway(this.gateway);
  }

  getLastDevices(): DiscoveredDevice[] {
    return this.copyDiscoveredDevices(this.lastDevices);
  }

  getLastGateways(): DiscoveredGateway[] {
    const result: DiscoveredGateway[] = [];
    for (let index = 0; index < this.lastGateways.length; index++) {
      result.push(this.copyDiscoveredGateway(this.lastGateways[index]));
    }
    return result;
  }

  setLocalAvailable(available: boolean): void {
    this.gateway.localAvailable = available;
    this.gateway.lastSyncAt = DateTimeUtil.nowDisplay();
  }

  setCloudAvailable(available: boolean): void {
    this.gateway.cloudAvailable = available;
    this.gateway.lastSyncAt = DateTimeUtil.nowDisplay();
  }

  setSecureTransport(secure: boolean): void {
    this.gateway.secureTransport = secure;
  }

  clearGatewayBinding(): void {
    this.gateway = createDefaultGatewayState();
    this.lastDevices = [];
    this.lastGateways = [];
    this.boundGatewayId = '';
    this.failureCount = 0;
    this.configuredPort = GatewayDefaults.LOCAL_PORT;
  }

  setLocalRoute(available: boolean, ip: string, port: number = GatewayDefaults.LOCAL_PORT, gatewayId: string = ''): void {
    this.gateway.localAvailable = available;
    if (ip.length > 0) {
      this.gateway.localIp = ip;
    }
    this.gateway.port = port;
    this.configuredPort = port;
    if (gatewayId.length > 0) {
      this.gateway.gatewayId = gatewayId;
      this.boundGatewayId = gatewayId;
    }
    this.gateway.lastSyncAt = DateTimeUtil.nowDisplay();
  }

  private async discoverByMdns(waitMs: number): Promise<DiscoveryCandidate[]> {
    const candidates: DiscoveryCandidate[] = [];
    const context = this.context;
    if (context === undefined) {
      return candidates;
    }
    let discovery: mdns.DiscoveryService | undefined = undefined;
    try {
      discovery = mdns.createDiscoveryService(context, '_yaocore._tcp');
      const onFound = (serviceInfo: mdns.LocalServiceInfo): void => {
        if (serviceInfo.host !== undefined && serviceInfo.host.address.length > 0) {
          this.addCandidate(candidates, serviceInfo.host.address,
            serviceInfo.port === undefined ? this.configuredPort : serviceInfo.port, 'mDNS');
        }
        mdns.resolveLocalService(context, serviceInfo).then((resolved: mdns.LocalServiceInfo) => {
          if (resolved.host !== undefined && resolved.host.address.length > 0) {
            this.addCandidate(candidates, resolved.host.address,
              resolved.port === undefined ? this.configuredPort : resolved.port, 'mDNS');
          }
        }).catch(() => {
        });
      };
      discovery.on('serviceFound', onFound);
      discovery.startSearchingMDNS();
      await this.delay(waitMs);
      discovery.stopSearchingMDNS();
      discovery.off('serviceFound', onFound);
    } catch (error) {
      if (discovery !== undefined) {
        try {
          discovery.stopSearchingMDNS();
        } catch (stopError) {
        }
      }
    }
    return candidates;
  }

  private async discoverByUdp(waitMs: number): Promise<DiscoveryCandidate[]> {
    const candidates: DiscoveryCandidate[] = [];
    const udp = socket.constructUDPSocketInstance();
    const decoder = util.TextDecoder.create('utf-8');
    const onMessage = (info: socket.SocketMessageInfo): void => {
      let valid = false;
      let port = this.configuredPort;
      try {
        const raw = decoder.decodeToString(new Uint8Array(info.message));
        const payload = JSON.parse(raw) as GatewayDiscoveryPayload;
        const gatewayId = payload.gatewayId === undefined ? payload.gateway_id : payload.gatewayId;
        valid = gatewayId !== undefined && gatewayId.length > 0;
        if (payload.port !== undefined && payload.port > 0 && payload.port < 65536) {
          port = payload.port;
        }
      } catch (error) {
      }
      if (valid && this.isUsableIpv4(info.remoteInfo.address)) {
        this.addCandidate(candidates, info.remoteInfo.address, port, I18nService.t('UDP 广播'));
      }
    };
    try {
      udp.on('message', onMessage);
      await udp.bind({
        address: '0.0.0.0',
        family: 1,
        port: 0
      });
      await udp.setExtraOptions({
        broadcast: true,
        reuseAddress: true
      });
      await udp.send({
        data: JSON.stringify({
          type: 'YAOCORE_DISCOVER',
          protocol_version: 2,
          service_id: GatewayDefaults.SERVICE_ID,
          reply_port: 0
        }),
        address: {
          address: '255.255.255.255',
          family: 1,
          port: this.configuredPort
        }
      });
      await this.delay(waitMs);
    } catch (error) {
    } finally {
      udp.off('message', onMessage);
      try {
        await udp.close();
      } catch (error) {
      }
    }
    return candidates;
  }

  private async resolveNetworkInfo(): Promise<NetworkInfo> {
    let address = '';
    let prefixLength = 24;
    const neighbors: string[] = [];
    try {
      const netHandle = await connection.getDefaultNet();
      const properties = await connection.getConnectionProperties(netHandle);
      for (let index = 0; index < properties.linkAddresses.length; index++) {
        const linkAddress = properties.linkAddresses[index];
        if (this.isUsableIpv4(linkAddress.address.address)) {
          address = linkAddress.address.address;
          prefixLength = linkAddress.prefixLength;
          break;
        }
      }
      for (let index = 0; index < properties.routes.length; index++) {
        const route = properties.routes[index];
        if (route.hasGateway && this.isUsableIpv4(route.gateway.address)) {
          this.addUniqueIp(neighbors, route.gateway.address);
        }
      }
    } catch (error) {
    }
    return {
      address: address,
      prefixLength: prefixLength,
      neighbors: neighbors
    };
  }

  private createFallbackCandidates(network: NetworkInfo, limit: number): DiscoveryCandidate[] {
    const candidates: DiscoveryCandidate[] = [];
    if (!this.isUsableIpv4(network.address)) {
      return candidates;
    }
    const parts = network.address.split('.');
    const max = limit < 1 ? 1 : limit > 254 ? 254 : limit;
    if (network.prefixLength >= 24 && network.prefixLength <= 30) {
      const hostBits = 32 - network.prefixLength;
      const hostCount = Math.min((1 << hostBits) - 2, max);
      const currentHost = Number(parts[3]);
      const blockSize = 1 << hostBits;
      const blockStart = Math.floor(currentHost / blockSize) * blockSize;
      for (let host = 1; host <= hostCount; host++) {
        this.addCandidate(candidates, `${parts[0]}.${parts[1]}.${parts[2]}.${blockStart + host}`,
          this.configuredPort, I18nService.t('受限网段扫描'));
      }
      return candidates;
    }
    for (let host = 1; host <= max; host++) {
      this.addCandidate(candidates, `${parts[0]}.${parts[1]}.${parts[2]}.${host}`,
        this.configuredPort, I18nService.t('受限网段扫描'));
    }
    return candidates;
  }

  private async probeCandidates(
    candidates: DiscoveryCandidate[],
    batchSize: number,
    stopAfterFirst: boolean = false
  ): Promise<DiscoveryResult[]> {
    const found: DiscoveryResult[] = [];
    for (let start = 0; start < candidates.length; start += batchSize) {
      const batch = candidates.slice(start, start + batchSize);
      const tasks: Promise<DiscoveryResult | undefined>[] = [];
      for (let index = 0; index < batch.length; index++) {
        tasks.push(this.probeHost(batch[index]));
      }
      const results = await Promise.all(tasks);
      for (let index = 0; index < results.length; index++) {
        if (results[index] !== undefined) {
          found.push(results[index] as DiscoveryResult);
        }
      }
      if (stopAfterFirst && found.length > 0) return found;
    }
    return found;
  }

  private async probeCandidatesForGateway(
    candidates: DiscoveryCandidate[],
    batchSize: number,
    expectedGatewayId: string
  ): Promise<DiscoveredGateway | undefined> {
    const safeBatchSize = Math.max(1, Math.min(batchSize, 8));
    for (let start = 0; start < candidates.length; start += safeBatchSize) {
      const batch = candidates.slice(start, start + safeBatchSize);
      const tasks: Promise<GatewayProbeOutcome>[] = [];
      for (let index = 0; index < batch.length; index++) {
        tasks.push(this.probeHostDetailed(batch[index]));
      }
      const outcomes = await Promise.all(tasks);
      for (let index = 0; index < outcomes.length; index++) {
        const outcome = outcomes[index];
        if (outcome.result !== undefined) {
          const gateways = outcome.result.gateways === undefined ? [] : outcome.result.gateways;
          for (let gatewayIndex = 0; gatewayIndex < gateways.length; gatewayIndex++) {
            const gateway = gateways[gatewayIndex];
            if (gateway.gatewayId === expectedGatewayId && gateway.secureTransport) return gateway;
          }
          if (outcome.result.gateway.gatewayId !== expectedGatewayId) continue;
        }
        if (outcome.errorCode === 'COMMAND_KEY_MISMATCH' ||
          outcome.errorCode === 'RESPONSE_SIGNATURE_INVALID' ||
          outcome.errorCode === 'GATEWAY_PAYLOAD_INVALID') {
          throw new Error(outcome.errorCode);
        }
      }
    }
    return undefined;
  }

  private async probeHost(candidate: DiscoveryCandidate): Promise<DiscoveryResult | undefined> {
    const outcome = await this.probeHostDetailed(candidate);
    return outcome.result;
  }

  private async probeHostDetailed(candidate: DiscoveryCandidate): Promise<GatewayProbeOutcome> {
    if (!this.isUsableIpv4(candidate.ip) || candidate.port <= 0 || candidate.port >= 65536) {
      return this.probeFailure('GATEWAY_ADDRESS_INVALID', I18nService.t('网关地址无效'));
    }
    if (!this.securityService.hasSessionSecret()) {
      return this.probeFailure('COMMAND_KEY_NOT_CONFIGURED', I18nService.t('尚未配置网关控制密钥'));
    }
    const request = http.createHttp();
    const startedAt = new Date().getTime();
    try {
      const challenge = this.securityService.createResponseChallenge();
      const requestAuthentication = this.securityService.signDiscoveryRequest(challenge);
      const response = await request.request(`http://${candidate.ip}:${candidate.port}/discover`, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/json',
          'X-YaoCore-Protocol': '2',
          'X-YaoCore-Challenge': challenge,
          'X-YaoCore-Request-Timestamp': requestAuthentication.timestamp,
          'X-YaoCore-Request-Nonce': requestAuthentication.nonce,
          'X-YaoCore-Request-Alg': requestAuthentication.algorithm,
          'X-YaoCore-Key-Id': requestAuthentication.keyId,
          'X-YaoCore-Request-Sign': requestAuthentication.sign
        },
        expectDataType: http.HttpDataType.STRING,
        // Real 2.4 GHz networks can exceed one DTIM interval while the ESP32
        // wakes or the access point forwards between wireless clients.  The
        // previous sub-second limits caused a reachable gateway to be rejected
        // repeatedly at the final LAN verification step.
        connectTimeout: 2500,
        readTimeout: 4000
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        if (response.responseCode === 401 || response.responseCode === 403) {
          return this.probeFailure('COMMAND_KEY_MISMATCH',
            I18nService.t('控制密钥与网关不一致，或网关认证时钟异常'));
        }
        return this.probeFailure(`GATEWAY_HTTP_${response.responseCode}`,
          I18nService.t('网关拒绝了局域网身份认证'));
      }
      if (this.isSimulatorResponse(response.header)) {
        return this.probeFailure('SIMULATOR_RESPONSE_REJECTED', I18nService.t('已拒绝模拟网关响应'));
      }
      const raw = `${response.result}`;
      if (!this.isAuthenticatedResponse(response.header, challenge, raw)) {
        return this.probeFailure('RESPONSE_SIGNATURE_INVALID',
          I18nService.t('网关响应签名无效，已停止绑定'));
      }
      const payload = JSON.parse(raw) as GatewayDiscoveryPayload;
      if (!this.isValidPayload(payload)) {
        return this.probeFailure('GATEWAY_PAYLOAD_INVALID', I18nService.t('网关身份或协议响应无效'));
      }
      const latency = new Date().getTime() - startedAt;
      const gateway = this.buildGateway(candidate, payload, latency);
      const payloadDevices = payload.devices === undefined ? [] : payload.devices;
      const devices = this.buildDevices(candidate.ip, gateway.gatewayId, payloadDevices);
      const discoveredGateway = this.buildDiscoveredGateway(gateway, payload, candidate, devices.length);
      return {
        result: {
          gateway: gateway,
          gateways: [discoveredGateway],
          devices: devices,
          scannedHosts: 1,
          message: devices.length > 0 ? I18nService.t('发现并校验网关') : I18nService.t('发现空网关，可继续绑定')
        },
        errorCode: '',
        message: ''
      };
    } catch (error) {
      return this.probeFailure('GATEWAY_UNREACHABLE', I18nService.t('手机暂时无法访问网关局域网地址'));
    } finally {
      request.destroy();
    }
  }

  private probeFailure(errorCode: string, message: string): GatewayProbeOutcome {
    return {
      errorCode: errorCode,
      message: message
    };
  }

  private mergeResults(results: DiscoveryResult[], scannedHosts: number, startedAt: number): DiscoveryResult {
    if (results.length === 0) {
      this.failureCount += 1;
      this.gateway.localAvailable = false;
      this.gateway.failureCount = this.failureCount;
      this.gateway.lastSyncAt = DateTimeUtil.nowDisplay();
      this.gateway.latencyMs = new Date().getTime() - startedAt;
      this.gateway.discoveryMethod = I18nService.t('未发现');
      this.lastDevices = [];
      this.lastGateways = [];
      return {
        gateway: this.copyGateway(this.gateway),
        gateways: [],
        devices: [],
        scannedHosts: scannedHosts,
        message: I18nService.t('未发现 YaoCore 网关，请确认网关与手机在同一局域网')
      };
    }

    const gateways: DiscoveredGateway[] = [];
    const allDevices: DiscoveredDevice[] = [];
    for (let index = 0; index < results.length; index++) {
      const resultGateways = results[index].gateways === undefined ? [] : results[index].gateways as DiscoveredGateway[];
      for (let gatewayIndex = 0; gatewayIndex < resultGateways.length; gatewayIndex++) {
        this.addDiscoveredGateway(gateways, resultGateways[gatewayIndex]);
      }
      for (let deviceIndex = 0; deviceIndex < results[index].devices.length; deviceIndex++) {
        this.addDiscoveredDevice(allDevices, results[index].devices[deviceIndex]);
      }
    }
    let selectedResult: DiscoveryResult | undefined = undefined;
    if (this.boundGatewayId.length > 0) {
      for (let index = 0; index < results.length; index++) {
        if (results[index].gateway.gatewayId === this.boundGatewayId) {
          selectedResult = results[index];
          break;
        }
      }
      if (selectedResult === undefined) {
        this.failureCount += 1;
        this.gateway.localAvailable = false;
        this.gateway.failureCount = this.failureCount;
        this.gateway.lastSyncAt = DateTimeUtil.nowDisplay();
        this.gateway.latencyMs = new Date().getTime() - startedAt;
        this.gateway.discoveryMethod = I18nService.t('已绑定网关未发现');
        this.lastDevices = [];
        this.lastGateways = gateways;
        return {
          gateway: this.copyGateway(this.gateway),
          gateways: this.getLastGateways(),
          devices: [],
          scannedHosts: scannedHosts,
          message: `发现 ${gateways.length} 个其他网关，但未发现已绑定网关 ${this.boundGatewayId}`
        };
      }
    } else {
      selectedResult = results[0];
    }
    const selected = (selectedResult as DiscoveryResult).gateway;
    const devices = this.boundGatewayId.length > 0 ?
      (selectedResult as DiscoveryResult).devices : allDevices;
    this.failureCount = 0;
    selected.localAvailable = true;
    selected.failureCount = 0;
    selected.lastSyncAt = DateTimeUtil.nowDisplay();
    this.gateway = selected;
    this.lastDevices = devices;
    this.lastGateways = gateways;
    return {
      gateway: this.copyGateway(selected),
      gateways: this.getLastGateways(),
      devices: this.copyDiscoveredDevices(devices),
      scannedHosts: scannedHosts,
      message: this.boundGatewayId.length > 0 ?
        `发现已绑定网关及 ${devices.length} 个子设备` :
        `发现 ${gateways.length} 个网关，绑定后才会同步其子设备`
    };
  }

  private buildGateway(candidate: DiscoveryCandidate, payload: GatewayDiscoveryPayload, latencyMs: number): GatewayState {
    const gatewayId = payload.gatewayId === undefined ? payload.gateway_id as string : payload.gatewayId;
    const gatewayName = payload.gatewayName === undefined ?
      (payload.gateway_name === undefined ? (payload.name === undefined ? GatewayDefaults.NAME : payload.name) : payload.gateway_name) :
      payload.gatewayName;
    const advertisedSecure = payload.secureTransport === true || payload.secure_transport === true ||
      (payload.security !== undefined && payload.security.alg === 'HMAC-SHA256');
    // Reaching this point already means isAuthenticatedResponse verified the
    // response HMAC with the locally stored control key.  Requiring the old
    // gateway state to be secure as well created a circular dependency: a new
    // gateway had to be bound before it could be marked secure, but binding
    // rejected every gateway not yet marked secure.
    const secure = advertisedSecure;
    return {
      gatewayId: gatewayId,
      gatewayName: gatewayName,
      localIp: candidate.ip,
      localAvailable: true,
      cloudAvailable: this.gateway.cloudAvailable,
      secureTransport: secure,
      lastSyncAt: DateTimeUtil.nowDisplay(),
      latencyMs: latencyMs,
      port: candidate.port,
      discoveryMethod: candidate.method,
      failureCount: 0
    };
  }

  private buildDiscoveredGateway(
    gateway: GatewayState,
    payload: GatewayDiscoveryPayload,
    candidate: DiscoveryCandidate,
    deviceCount: number
  ): DiscoveredGateway {
    const serviceId = payload.serviceId === undefined ?
      (payload.service_id === undefined ? GatewayDefaults.SERVICE_ID : payload.service_id) : payload.serviceId;
    const rawVersion = payload.protocolVersion === undefined ? payload.protocol_version : payload.protocolVersion;
    const parsedVersion = rawVersion === undefined ? 1 : Number(rawVersion);
    const version = Number.isNaN(parsedVersion) ? 1 : parsedVersion;
    return {
      gatewayId: gateway.gatewayId,
      gatewayName: gateway.gatewayName,
      localIp: candidate.ip,
      port: candidate.port,
      serviceId: serviceId,
      protocolVersion: version,
      discoveryMethod: candidate.method,
      secureTransport: gateway.secureTransport,
      latencyMs: gateway.latencyMs,
      deviceCount: deviceCount,
      lastSeenAt: DateTimeUtil.nowDisplay()
    };
  }

  private buildDevices(ip: string, gatewayId: string, payloadDevices: GatewayDevicePayload[]): DiscoveredDevice[] {
    const devices: DiscoveredDevice[] = [];
    for (let index = 0; index < payloadDevices.length; index++) {
      const item = payloadDevices[index];
      const id = item.deviceId === undefined ?
        (item.device_id === undefined ? (item.id === undefined ? '' : item.id) : item.device_id) : item.deviceId;
      const typeText = item.deviceType === undefined ?
        (item.device_type === undefined ? (item.type === undefined ? '' : item.type) : item.device_type) : item.deviceType;
      const normalizedType = this.normalizeType(typeText);
      if (normalizedType === undefined) {
        continue;
      }
      const deviceName = item.deviceName === undefined ?
        (item.device_name === undefined ? (item.name === undefined ? I18nService.t('局域网设备') : item.name) : item.device_name) : item.deviceName;
      const roomName = item.roomName === undefined ?
        (item.room_name === undefined ? (item.room === undefined ? I18nService.t('未分区') : item.room) : item.room_name) : item.roomName;
      devices.push({
        deviceId: id,
        deviceName: deviceName,
        roomName: roomName,
        deviceType: normalizedType,
        brand: item.brand,
        gatewayId: gatewayId,
        localIp: ip,
        protocol: item.protocol === undefined || item.protocol.trim().length === 0 ?
          'YaoCore-LAN-v2' : item.protocol,
        isOnline: item.isOnline === undefined ? item.online : item.isOnline,
        powerStatus: this.normalizeBoolean(item.powerStatus === undefined ? item.power : item.powerStatus),
        openStatus: this.normalizeBoolean(item.openStatus === undefined ? item.open : item.openStatus),
        brightness: item.brightness === undefined ? item.bright : item.brightness,
        color: item.color,
        temperature: item.temperature,
        humidity: item.humidity,
        presence: item.presence === undefined ? item.occupied : item.presence,
        targetTemperature: item.targetTemperature === undefined ?
          (item.target_temperature === undefined ? item.targetTemp : item.target_temperature) : item.targetTemperature,
        mode: item.mode,
        position: item.position,
        speed: item.speed,
        volume: item.volume,
        stateSource: item.stateSource === undefined ? item.state_source : item.stateSource,
        triggerDeviceId: item.triggerDeviceId === undefined ? item.trigger_device_id : item.triggerDeviceId,
        automationId: item.automationId === undefined ? item.automation_id : item.automationId,
        lastRequestId: item.lastRequestId === undefined ? item.last_request_id : item.lastRequestId,
        lastSequence: item.lastSeq === undefined ? item.last_seq : item.lastSeq,
        lastSeenAt: this.deviceEventTime(item)
      });
    }
    return devices;
  }

  private isValidPayload(payload: GatewayDiscoveryPayload): boolean {
    const gatewayId = payload.gatewayId === undefined ? payload.gateway_id : payload.gatewayId;
    const gatewayName = payload.gatewayName === undefined ?
      (payload.gateway_name === undefined ? payload.name : payload.gateway_name) : payload.gatewayName;
    const serviceId = payload.serviceId === undefined ? payload.service_id : payload.serviceId;
    const version = payload.protocolVersion === undefined ? payload.protocol_version : payload.protocolVersion;
    const algorithm = payload.security === undefined ? '' : payload.security.alg;
    const keyId = payload.security === undefined ? undefined :
      (payload.security.keyId === undefined ? payload.security.key_id : payload.security.keyId);
    return gatewayId !== undefined && this.isGatewayIdentifier(gatewayId) &&
      gatewayName !== undefined && gatewayName.trim().length > 0 && gatewayName.trim().length <= 63 &&
      serviceId === GatewayDefaults.SERVICE_ID && `${version}` === '2.0' &&
      algorithm === 'HMAC-SHA256' && keyId === 'app-key-v1' &&
      payload.devices !== undefined && this.isValidDeviceInventory(payload.devices);
  }

  private isValidDeviceInventory(devices: GatewayDevicePayload[]): boolean {
    if (devices.length > 128) return false;
    const ids: string[] = [];
    for (let index = 0; index < devices.length; index++) {
      const item = devices[index];
      const id = item.deviceId === undefined ?
        (item.device_id === undefined ? item.id : item.device_id) : item.deviceId;
      if (id === undefined || !this.isGatewayIdentifier(id)) return false;
      for (let previous = 0; previous < ids.length; previous++) {
        if (ids[previous] === id) return false;
      }
      ids.push(id);
    }
    return true;
  }

  private isGatewayIdentifier(value: string): boolean {
    if (value.length < 1 || value.length > 63) {
      return false;
    }
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      const alphaNumeric = (code >= 48 && code <= 57) || (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122);
      const separator = value.charAt(index) === '_' || value.charAt(index) === '-' ||
        value.charAt(index) === '.' || value.charAt(index) === ':';
      if ((!alphaNumeric && !separator) || (index === 0 && !alphaNumeric)) {
        return false;
      }
    }
    return true;
  }

  private deviceEventTime(payload: GatewayDevicePayload): string {
    if (payload.updatedAt !== undefined) return payload.updatedAt;
    if (payload.updated_at !== undefined) return payload.updated_at;
    if (payload.eventTime !== undefined) return payload.eventTime;
    if (payload.event_time !== undefined) return payload.event_time;
    return '';
  }

  private isSimulatorResponse(header: Object): boolean {
    const marker = HttpHeaderUtil.getValue(header, 'X-YaoCore-Simulator').toUpperCase();
    if (marker.indexOf('DEV-ONLY') >= 0) {
      return true;
    }
    try {
      const text = JSON.stringify(header).toUpperCase();
      return text.indexOf('X-YAOCORE-SIMULATOR') >= 0 || text.indexOf('DEV-ONLY') >= 0;
    } catch (error) {
      return false;
    }
  }

  private isAuthenticatedResponse(header: Object, challenge: string, body: string): boolean {
    return this.securityService.verifyResponseAuthentication(
      'discover',
      challenge,
      body,
      HttpHeaderUtil.getValue(header, 'X-YaoCore-Response-Alg'),
      HttpHeaderUtil.getValue(header, 'X-YaoCore-Key-Id'),
      HttpHeaderUtil.getValue(header, 'X-YaoCore-Response-Correlation'),
      HttpHeaderUtil.getValue(header, 'X-YaoCore-Response-Sign')
    );
  }

  private addCandidate(candidates: DiscoveryCandidate[], ip: string, port: number, method: string): void {
    if (!this.isUsableIpv4(ip) || port <= 0 || port >= 65536) {
      return;
    }
    for (let index = 0; index < candidates.length; index++) {
      if (candidates[index].ip === ip && candidates[index].port === port) {
        if (candidates[index].method === I18nService.t('受限网段扫描')) {
          candidates[index].method = method;
        }
        return;
      }
    }
    candidates.push({
      ip: ip,
      port: port,
      method: method
    });
  }

  private mergeCandidates(target: DiscoveryCandidate[], source: DiscoveryCandidate[]): void {
    for (let index = 0; index < source.length; index++) {
      this.addCandidate(target, source[index].ip, source[index].port, source[index].method);
    }
  }

  private addUniqueIp(values: string[], ip: string): void {
    for (let index = 0; index < values.length; index++) {
      if (values[index] === ip) {
        return;
      }
    }
    values.push(ip);
  }

  private addDiscoveredGateway(values: DiscoveredGateway[], gateway: DiscoveredGateway): void {
    for (let index = 0; index < values.length; index++) {
      if (values[index].gatewayId === gateway.gatewayId && values[index].localIp === gateway.localIp) {
        return;
      }
    }
    values.push(this.copyDiscoveredGateway(gateway));
  }

  private addDiscoveredDevice(values: DiscoveredDevice[], device: DiscoveredDevice): void {
    for (let index = 0; index < values.length; index++) {
      if (values[index].gatewayId === device.gatewayId && values[index].deviceId === device.deviceId) {
        values[index] = device;
        return;
      }
    }
    values.push(device);
  }

  private copyGateway(value: GatewayState): GatewayState {
    return {
      gatewayId: value.gatewayId,
      gatewayName: value.gatewayName,
      localIp: value.localIp,
      localAvailable: value.localAvailable,
      cloudAvailable: value.cloudAvailable,
      secureTransport: value.secureTransport,
      lastSyncAt: value.lastSyncAt,
      latencyMs: value.latencyMs,
      port: value.port,
      discoveryMethod: value.discoveryMethod,
      failureCount: value.failureCount
    };
  }

  private copyDiscoveredGateway(value: DiscoveredGateway): DiscoveredGateway {
    return {
      gatewayId: value.gatewayId,
      gatewayName: value.gatewayName,
      localIp: value.localIp,
      port: value.port,
      serviceId: value.serviceId,
      protocolVersion: value.protocolVersion,
      discoveryMethod: value.discoveryMethod,
      secureTransport: value.secureTransport,
      latencyMs: value.latencyMs,
      deviceCount: value.deviceCount,
      lastSeenAt: value.lastSeenAt
    };
  }

  private copyDiscoveredDevices(devices: DiscoveredDevice[]): DiscoveredDevice[] {
    const result: DiscoveredDevice[] = [];
    for (let index = 0; index < devices.length; index++) {
      result.push({
        deviceId: devices[index].deviceId,
        deviceName: devices[index].deviceName,
        roomName: devices[index].roomName,
        deviceType: devices[index].deviceType,
        brand: devices[index].brand,
        gatewayId: devices[index].gatewayId,
        localIp: devices[index].localIp,
        protocol: devices[index].protocol,
        isOnline: devices[index].isOnline,
        powerStatus: devices[index].powerStatus,
        openStatus: devices[index].openStatus,
        brightness: devices[index].brightness,
        color: devices[index].color,
        temperature: devices[index].temperature,
        humidity: devices[index].humidity,
        presence: devices[index].presence,
        targetTemperature: devices[index].targetTemperature,
        mode: devices[index].mode,
        stateSource: devices[index].stateSource,
        triggerDeviceId: devices[index].triggerDeviceId,
        automationId: devices[index].automationId,
        lastRequestId: devices[index].lastRequestId,
        lastSequence: devices[index].lastSequence,
        lastSeenAt: devices[index].lastSeenAt
      });
    }
    return result;
  }

  private normalizeBoolean(value?: boolean | number | string): boolean | undefined {
    if (value === undefined) {
      return undefined;
    }
    if (typeof value === 'boolean') {
      return value;
    }
    if (typeof value === 'number') {
      return value > 0;
    }
    const lower = value.toLowerCase();
    if (lower === 'true' || lower === 'on' || lower === 'open' || lower === '1') {
      return true;
    }
    if (lower === 'false' || lower === 'off' || lower === 'closed' || lower === 'close' || lower === '0') {
      return false;
    }
    return undefined;
  }

  private normalizeType(typeText: string): DeviceType | undefined {
    const lower = typeText.toLowerCase();
    if (lower === 'door' || lower === 'lock') {
      return DeviceType.DOOR;
    }
    if (lower === 'light' || lower === 'lamp') {
      return DeviceType.LIGHT;
    }
    if (lower === 'sensor' || lower === 'climate_sensor' || lower === 'temperature_humidity') {
      return DeviceType.SENSOR;
    }
    if (lower === 'ac' || lower === 'air_conditioner') {
      return DeviceType.AC;
    }
    if (lower === 'camera') {
      return DeviceType.CAMERA;
    }
    if (lower === 'curtain' || lower === 'blind' || lower === 'shade') return DeviceType.CURTAIN;
    if (lower === 'fan') return DeviceType.FAN;
    if (lower === 'speaker' || lower === 'audio') return DeviceType.SPEAKER;
    if (lower === 'switch') return DeviceType.SWITCH;
    return undefined;
  }

  private isUsableIpv4(address: string): boolean {
    if (address.length === 0 || address.indexOf('.') < 0 || address.startsWith('127.') || address.startsWith('0.')) {
      return false;
    }
    const segments = address.split('.');
    if (segments.length !== 4) {
      return false;
    }
    for (let index = 0; index < segments.length; index++) {
      const value = Number(segments[index]);
      if (value < 0 || value > 255 || Number.isNaN(value)) {
        return false;
      }
    }
    return true;
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}
