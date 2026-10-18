/*
 * YaoCore C-19 Wi-Fi scan / apply / status / finish flow.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Contract: DES-A §16.7; BLE设计 §5-131-147, §7-177-182
 *
 * Paged scan (max 4 APs per page, 15s budget), set_config -> apply_config,
 * 1s get_status polling with a 30s budget, explicit AuthError vs
 * NetworkNotFound classification, and yaocore-done ACK handling. The flow only
 * sees a SecureGattChannel; it never touches platform BLE or persists secrets.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { BytesUtil } from '../../common/utils/BytesUtil';
import { Utf8 } from '../../common/utils/Utf8';
import { JsonKind } from '../../common/types/JsonNode';
import { JsonParser } from '../../common/utils/JsonParser';
import type { ClockPort } from '../../common/types/Ports';
import type { CancellationToken } from '../../common/types/CancellationToken';
import { WifiAp } from '../../model/ProvisioningModels';
import {
  defaultBleDelay,
  isCode,
  mapProvisioningError,
  throwIfCancelled
} from './BleSupport';
import type { BleDelay } from './BleSupport';
import { GattEndpointMap } from '../../model/GattEndpointMap';
import type { SecureGattChannel } from './GattChannel';
import {
  ProtocommCodec,
  WifiConfig,
  WifiConnectFailedReason,
  WifiScanResult,
  WifiStationState,
  WifiStatus
} from './ProtocommCodec';

const SCAN_TOTAL_TIMEOUT_MS: number = 15000;
const SCAN_STATUS_DELAY_MS: number = 300;
const MAX_SCAN_RESULTS: number = 80;
const SCAN_PAGE_SIZE: number = 4;
const WIFI_TOTAL_TIMEOUT_MS: number = 30000;
const WIFI_POLL_DELAY_MS: number = 1000;

const FINISH_REQUEST: string = '{"op":"finish","protocolVersion":"2.0"}';

export class WifiProvisioningFlow {
  private readonly clock: ClockPort;
  private readonly delay: BleDelay;

  constructor(clock: ClockPort, delay: BleDelay = defaultBleDelay) {
    this.clock = clock;
    this.delay = delay;
  }

  /** Blocking scan start + status polling + 4-AP pages (raw, best-RSSI kept). */
  async scan(channel: SecureGattChannel,
    cancellation?: CancellationToken): Promise<ReadonlyArray<WifiAp>> {
    const deadline = this.clock.nowMs() + SCAN_TOTAL_TIMEOUT_MS;
    try {
      throwIfCancelled(cancellation);
      const startResponse = await channel.request(GattEndpointMap.PROV_SCAN,
        ProtocommCodec.encodeScanStart());
      ProtocommCodec.validateScanStartResponse(startResponse);
      let resultCount = 0;
      while (true) {
        throwIfCancelled(cancellation);
        const statusPayload = await channel.request(GattEndpointMap.PROV_SCAN,
          ProtocommCodec.encodeScanStatus());
        const status = ProtocommCodec.decodeScanStatus(statusPayload);
        if (status.scanFinished) {
          resultCount = status.resultCount;
          break;
        }
        if (this.clock.nowMs() >= deadline) {
          throw AppErrors.of('PROVISIONING_WIFI_SCAN_FAILED', []);
        }
        await Promise.resolve(this.delay(SCAN_STATUS_DELAY_MS));
      }
      const total = Math.min(resultCount, MAX_SCAN_RESULTS);
      const collected: WifiScanResult[] = [];
      for (let startIndex = 0; startIndex < total; startIndex += SCAN_PAGE_SIZE) {
        throwIfCancelled(cancellation);
        // Page requests share the same 15s scan budget as status polling
        // (DES-A §16.7-4078); a slow finished-scan read cannot extend it.
        if (this.clock.nowMs() >= deadline) {
          throw AppErrors.of('PROVISIONING_WIFI_SCAN_FAILED', []);
        }
        const count = Math.min(SCAN_PAGE_SIZE, total - startIndex);
        const pagePayload = await channel.request(GattEndpointMap.PROV_SCAN,
          ProtocommCodec.encodeScanResult(startIndex, count));
        const page = ProtocommCodec.decodeScanResult(pagePayload);
        for (let index = 0; index < page.length; index++) {
          collected.push(page[index]);
        }
      }
      return WifiProvisioningFlow.toAccessPoints(collected);
    } catch (error) {
      const typed = error as Error;
      if (isCode(typed, 'PROVISIONING_CANCELLED')) {
        throw typed;
      }
      throw mapProvisioningError(typed, 'PROVISIONING_WIFI_SCAN_FAILED', 'scan');
    }
  }

  /** set_config followed by apply_config; both ACKs must be Success. */
  async apply(channel: SecureGattChannel, config: WifiConfig): Promise<void> {
    const setPayload = ProtocommCodec.encodeSetConfig(config);
    try {
      const setResponse = await channel.request(GattEndpointMap.PROV_CONFIG, setPayload);
      ProtocommCodec.decodeSetConfigResponse(setResponse);
    } finally {
      BytesUtil.zeroize(setPayload);
    }
    const applyResponse = await channel.request(GattEndpointMap.PROV_CONFIG,
      ProtocommCodec.encodeApplyConfig());
    ProtocommCodec.decodeApplyConfigResponse(applyResponse);
  }

  /**
   * Polls get_status until CONNECTED + valid IPv4, a terminal AuthError /
   * NetworkNotFound, or the 30s budget expires.
   */
  async waitForConnection(channel: SecureGattChannel,
    cancellation?: CancellationToken): Promise<WifiStatus> {
    const deadline = this.clock.nowMs() + WIFI_TOTAL_TIMEOUT_MS;
    let waitFirst = true;
    while (true) {
      throwIfCancelled(cancellation);
      if (!waitFirst) {
        if (this.clock.nowMs() >= deadline) {
          throw AppErrors.of('PROVISIONING_WIFI_TIMEOUT', []);
        }
        await Promise.resolve(this.delay(WIFI_POLL_DELAY_MS));
      }
      waitFirst = false;
      if (this.clock.nowMs() >= deadline) {
        throw AppErrors.of('PROVISIONING_WIFI_TIMEOUT', []);
      }
      const payload = await channel.request(GattEndpointMap.PROV_CONFIG,
        ProtocommCodec.encodeGetStatus());
      const status = ProtocommCodec.decodeWifiStatus(payload);
      if (status.state === WifiStationState.CONNECTED) {
        return status;
      }
      if (status.failReason === WifiConnectFailedReason.AUTH_ERROR) {
        throw AppErrors.of('PROVISIONING_WIFI_AUTH_ERROR', []);
      }
      if (status.failReason === WifiConnectFailedReason.NETWORK_NOT_FOUND) {
        throw AppErrors.of('PROVISIONING_WIFI_NETWORK_NOT_FOUND', []);
      }
    }
  }

  /**
   * `yaocore-done` ACK. Returns false when old firmware has no endpoint.
   * RISK-BLE-DONE-ACK: an empty/non-JSON body is accepted as ACK; only an
   * explicit `ok:false` or failure status string rejects.
   */
  async finish(channel: SecureGattChannel, doneAvailable: boolean): Promise<boolean> {
    if (!doneAvailable) {
      return false;
    }
    let response: Uint8Array;
    try {
      response = await channel.request(GattEndpointMap.YAOCORE_DONE,
        ProtocommCodec.encodeCustomJson(FINISH_REQUEST));
    } catch (error) {
      throw AppErrors.of('PROVISIONING_DONE_REJECTED', []);
    }
    if (response.length === 0) {
      return true;
    }
    try {
      const text = Utf8.decode(response);
      const node = JsonParser.parse(text);
      if (node.kind === JsonKind.OBJECT) {
        const ok = node.get('ok');
        if (ok !== undefined && ok.kind === JsonKind.BOOLEAN && !ok.booleanValue) {
          throw AppErrors.of('PROVISIONING_DONE_REJECTED', []);
        }
        const status = node.get('status');
        if (status !== undefined) {
          if (status.kind === JsonKind.BOOLEAN && !status.booleanValue) {
            throw AppErrors.of('PROVISIONING_DONE_REJECTED', []);
          }
          if (status.kind === JsonKind.STRING &&
            WifiProvisioningFlow.isFailureStatus(status.stringValue)) {
            throw AppErrors.of('PROVISIONING_DONE_REJECTED', []);
          }
        }
      }
      return true;
    } catch (error) {
      if (error instanceof AppError &&
        (error as AppError).code === 'PROVISIONING_DONE_REJECTED') {
        throw error;
      }
      // Non-JSON or unrelated parse failures are accepted as an ACK; only an
      // explicit rejection body is terminal (RISK-BLE-DONE-ACK).
      return true;
    }
  }

  private static isFailureStatus(status: string): boolean {
    const normalized = status.toLowerCase();
    return normalized === 'error' || normalized === 'failed' || normalized === 'failure' ||
      normalized === 'rejected' || normalized === 'denied';
  }

  /** Raw AP list: SSID+BSSID are preserved; UI owns SSID aggregation. */
  private static toAccessPoints(results: ReadonlyArray<WifiScanResult>): ReadonlyArray<WifiAp> {
    const accessPoints: WifiAp[] = [];
    for (let index = 0; index < results.length; index++) {
      const result = results[index];
      if (result.ssid.length === 0) {
        continue;
      }
      let ssid: string;
      try {
        ssid = Utf8.decode(result.ssid);
      } catch (error) {
        throw AppErrors.of('PROVISIONING_WIFI_SCAN_FAILED', []);
      }
      if (ssid.length === 0) {
        continue;
      }
      try {
        accessPoints.push(new WifiAp(ssid, BytesUtil.hexLower(result.bssid),
          result.channel, result.rssi, result.auth));
      } catch (error) {
        // A single malformed entry must not abort the whole scan page.
        continue;
      }
    }
    accessPoints.sort((left: WifiAp, right: WifiAp): number => right.rssi - left.rssi);
    return accessPoints;
  }
}
