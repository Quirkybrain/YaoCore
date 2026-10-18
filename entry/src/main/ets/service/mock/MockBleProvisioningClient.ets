/*
 * YaoCore C-20 MockBleProvisioningClient.
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §17.1, §17.2, §17.4; T-12 extends the real C-19
 *
 * TEST ONLY — SC-11 boundary. Never import this file from production code.
 * Deterministic: no real sleep, no radio, no secret logging. Identity v2.1 is
 * emitted only when the scenario declares a TLS mode, matching ADR-002 §3.
 */
import { AppErrors } from '../../common/types/AppError';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import type { ClockPort } from '../../common/types/Ports';
import type { RandomPort } from '../../contracts/Ports';
import type { CancellationToken } from '../../common/types/CancellationToken';
import {
  BleProvisioningIdentity,
  BleProvisioningResult,
  IdentityVersion,
  ProvisioningTlsMaterial
} from '../../model/ProvisioningModels';
import { BleProvisioningRequest, BleProvisioningStage, BleScanDevice, BleScanFilter, BleWifiScanRequest, ProvisioningProgress, ProvisioningState, WifiAp } from '../../model/ProvisioningModels';
import type { BleProvisioningProgressListener, BleScanListener, IBleProvisioningClient } from '../../contracts/BleProvisioningPorts';
import { MockMode, MockScenario, MockTlsMode } from './MockScenario';

const MOCK_GATEWAY_ID: string = 'Mock_Gateway_01';
const MOCK_GATEWAY_NAME: string = 'YaoCore-GW-Mock';
const MOCK_IP: string = '192.168.1.10';
const MOCK_PORT: number = 9200;
const MOCK_PIN: string = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const MOCK_DRAFT_ID: string = 'mock-credential-draft-01';

export class MockBleProvisioningClient implements IBleProvisioningClient {
  private readonly scenario: MockScenario;
  private readonly clock: ClockPort;
  private readonly random: RandomPort;
  private cancelled: boolean = false;

  constructor(scenario: MockScenario, clock: ClockPort, random: RandomPort) {
    this.scenario = scenario;
    this.clock = clock;
    this.random = random;
  }

  async startScan(filter: BleScanFilter, listener: BleScanListener): Promise<void> {
    if (this.scenario.mode === MockMode.OFFLINE) {
      throw AppErrors.of('PROVISIONING_DEVICE_NOT_FOUND', []);
    }
    if (this.scenario.mode !== MockMode.TIMEOUT) {
      const name = MOCK_GATEWAY_NAME;
      const prefix = filter.namePrefix;
      if (prefix === undefined || name.startsWith(prefix)) {
        const jitter = await this.random.nextBytes(1);
        const rssi = -40 - (jitter[0] % 5);
        listener.onDeviceFound(new BleScanDevice(MOCK_GATEWAY_ID, name, rssi));
      }
    }
    listener.onScanFinished();
  }

  async stopScan(): Promise<void> {
    // The mock scan is synchronous; no radio state survives startScan.
  }

  async provision(request: BleProvisioningRequest,
    listener: BleProvisioningProgressListener,
    cancellation?: CancellationToken): Promise<BleProvisioningResult> {
    this.cancelled = false;
    if (this.scenario.mode === MockMode.OFFLINE) {
      throw AppErrors.of('PROVISIONING_CONNECT_FAILED', []);
    }
    if (this.scenario.mode === MockMode.TIMEOUT) {
      this.stage(listener, BleProvisioningStage.CONNECTING, cancellation);
      this.stage(listener, BleProvisioningStage.SECURITY, cancellation);
      this.stage(listener, BleProvisioningStage.WIFI_APPLY, cancellation);
      throw AppErrors.of('PROVISIONING_WIFI_TIMEOUT', []);
    }
    if (this.scenario.mode === MockMode.ACK_LOST) {
      this.stage(listener, BleProvisioningStage.CONNECTING, cancellation);
      throw AppErrors.of('PROVISIONING_DONE_REJECTED', []);
    }
    this.stage(listener, BleProvisioningStage.CONNECTING, cancellation);
    this.stage(listener, BleProvisioningStage.SECURITY, cancellation);
    this.stage(listener, BleProvisioningStage.IDENTITY, cancellation);
    this.stage(listener, BleProvisioningStage.WIFI_SCAN, cancellation);
    this.stage(listener, BleProvisioningStage.WIFI_APPLY, cancellation);
    this.stage(listener, BleProvisioningStage.WIFI_STATUS, cancellation);
    this.stage(listener, BleProvisioningStage.DONE, cancellation);
    this.stage(listener, BleProvisioningStage.BINDING_PROBE, cancellation);
    const identity = this.identity();
    return new BleProvisioningResult(identity, MOCK_IP, identity.tls === undefined ?
      MOCK_PORT : identity.tls.port, true, MOCK_DRAFT_ID, this.nowCompact());
  }

  async scanWifiAccessPoints(request: BleWifiScanRequest,
    listener: BleProvisioningProgressListener,
    cancellation?: CancellationToken): Promise<ReadonlyArray<WifiAp>> {
    this.cancelled = false;
    if (this.scenario.mode === MockMode.OFFLINE) {
      throw AppErrors.of('PROVISIONING_CONNECT_FAILED', []);
    }
    this.stage(listener, BleProvisioningStage.CONNECTING, cancellation);
    this.stage(listener, BleProvisioningStage.SECURITY, cancellation);
    this.stage(listener, BleProvisioningStage.IDENTITY, cancellation);
    this.stage(listener, BleProvisioningStage.WIFI_SCAN, cancellation);
    if (listener.onStateChanged !== undefined) {
      listener.onStateChanged(new ProvisioningProgress(ProvisioningState.AP_SCANNING));
    }
    const accessPoints: ReadonlyArray<WifiAp> = [
      new WifiAp('Mock-Home', 'aa:bb:cc:dd:ee:01', 6, -42, 3),
      new WifiAp('Mock-Office', 'aa:bb:cc:dd:ee:02', 11, -58, 3)
    ];
    if (listener.onAccessPoints !== undefined) {
      listener.onAccessPoints(accessPoints);
    }
    return accessPoints;
  }

  async cancel(): Promise<void> {
    this.cancelled = true;
  }

  private stage(listener: BleProvisioningProgressListener, stage: BleProvisioningStage,
    cancellation?: CancellationToken): void {
    if (this.cancelled) {
      throw AppErrors.of('PROVISIONING_CANCELLED', []);
    }
    if (cancellation !== undefined) {
      try {
        cancellation.throwIfCancelled();
      } catch (error) {
        throw AppErrors.of('PROVISIONING_CANCELLED', []);
      }
    }
    listener.onStage(stage);
  }

  private identity(): BleProvisioningIdentity {
    if (this.scenario.tlsMode === MockTlsMode.DISABLED) {
      return new BleProvisioningIdentity(IdentityVersion.V20, MOCK_GATEWAY_ID,
        MOCK_GATEWAY_NAME);
    }
    const tls = new ProvisioningTlsMaterial([MOCK_PIN], MOCK_PORT, 'sha256-spki-der');
    return new BleProvisioningIdentity(IdentityVersion.V21, MOCK_GATEWAY_ID,
      MOCK_GATEWAY_NAME, tls);
  }

  private nowCompact(): string {
    const value = this.clock.nowMs();
    if (!Number.isFinite(value)) {
      throw AppErrors.internal('clock');
    }
    return DateTimeUtil.formatUtcCompact(Math.floor(value));
  }
}
