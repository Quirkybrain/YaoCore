/*
 * YaoCore C-19 BleProvisioningService.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Contract: DES-A §16.1-§16.11; BLE设计 §2-§7; ADR-002 §3.2;
 *           project-constraints PR-06/PR-07/PR-12/PR-13/SC-04/SC-05/SC-06
 *
 * Pure orchestration: BLE transport, crypto, clock, random, gateway client,
 * credential store and one-shot drafts are injected ports. No @ohos import.
 *
 * Hard invariants:
 * - Permission -> scan -> connect -> MTU/0x2901 discovery -> proto-ver ->
 *   Security1 -> identity (2.1 then one 2.0 retry) -> Wi-Fi scan -> set/apply
 *   -> 30s status -> yaocore-done -> LAN probe + board LED -> result.
 * - Every write succeeds before the next request (response-driven state).
 * - Any exit path stops the scan, disconnects GATT, destroys the Security1
 *   stream, destroys the queue, and zeroizes Wi-Fi password/PoP copies.
 * - BLE success is not binding success; only the verified LAN probe + LED
 *   acknowledgement produces BleProvisioningResult.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { BytesUtil } from '../../common/utils/BytesUtil';
import { Utf8 } from '../../common/utils/Utf8';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';
import type { ClockPort } from '../../common/types/Ports';
import type { LoggerPort, RandomPort } from '../../contracts/Ports';
import type { CancellationToken } from '../../common/types/CancellationToken';
import type { CryptoPort } from '../../contracts/CryptoPort';
import type { GatewayCredentialPort } from '../../contracts/GatewayPorts';
import type { SecretDraftPort } from '../../contracts/SecretDraftPort';
import {
  BleProvisioningIdentity,
  BleProvisioningResult
} from '../../model/ProvisioningModels';
import type { IGatewayClient } from '../../contracts/GatewayTransportPorts';
import { BleCharacteristicRef, BleDescriptorRef, BleProvisioningDevice, BleProvisioningRequest, BleProvisioningStage, BleScanFilter, BleWifiScanRequest, ProvisioningProgress, ProvisioningState } from '../../model/ProvisioningModels';
import type { BleConnection, BleProvisioningProgressListener, BleScanListener, BleTransport, IBleProvisioningClient } from '../../contracts/BleProvisioningPorts';
import type { WifiAp } from '../../model/ProvisioningModels';
import {
  defaultBleDelay,
  isCode,
  mapProvisioningError,
  throwIfCancelled
} from './BleSupport';
import type { BleDelay } from './BleSupport';
import { GattEndpointMap } from '../../model/GattEndpointMap';
import { GattRequestQueue } from './GattRequestQueue';
import { GattChannel } from './GattChannel';
import { Security1Session } from './Security1Session';
import { ProtoVerParser } from './ProtoVerParser';
import { IdentityNegotiator } from './IdentityNegotiator';
import { WifiConfig, WifiStatus } from './ProtocommCodec';
import { WifiProvisioningFlow } from './WifiProvisioningFlow';
import { BindingProber, BindingProbeOutcome } from './BindingProbe';
import {
  ProvisioningEvent,
  ProvisioningStateMachine
} from './ProvisioningStateMachine';

const MTU_TARGET: number = 512;
const MTU_MINIMUM: number = 247;
const GATT_REQUEST_TIMEOUT_MS: number = 15000;
const PROTO_VER_PROBE: string = 'ESP';
const DEFAULT_SCAN_TIMEOUT_MS: number = 10000;
const DEFAULT_NAME_PREFIX: string = 'YaoCore-GW-';

class DelegatingScanListener implements BleScanListener {
  private readonly found: (device: BleProvisioningDevice) => void;
  private readonly finished: () => void;
  private readonly failed: (error: AppError) => void;

  constructor(found: (device: BleProvisioningDevice) => void, finished: () => void,
    failed: (error: AppError) => void) {
    this.found = found;
    this.finished = finished;
    this.failed = failed;
  }

  onDeviceFound(device: BleProvisioningDevice): void {
    this.found(device);
  }

  onScanFinished(): void {
    this.finished();
  }

  onScanError(error: AppError): void {
    this.failed(error);
  }
}

export class BleProvisioningService implements IBleProvisioningClient {
  private readonly transport: BleTransport;
  private readonly crypto: CryptoPort;
  private readonly clock: ClockPort;
  private readonly random: RandomPort;
  private readonly gatewayClient: IGatewayClient;
  private readonly credentials: GatewayCredentialPort;
  private readonly drafts: SecretDraftPort;
  private readonly logger: LoggerPort;
  private readonly delay: BleDelay;
  private readonly scanTimeoutMs: number;

  private readonly stateMachine: ProvisioningStateMachine = new ProvisioningStateMachine();
  private connection: BleConnection | undefined = undefined;
  private endpoints: GattEndpointMap | undefined = undefined;
  private queue: GattRequestQueue | undefined = undefined;
  private channel: GattChannel | undefined = undefined;
  private session: Security1Session | undefined = undefined;
  private running: boolean = false;
  private cancelled: boolean = false;
  private activeListener: BleProvisioningProgressListener | undefined = undefined;
  private publicScanListener: BleScanListener | undefined = undefined;
  private publicScanTimer: number = 0;
  private publicScanActive: boolean = false;
  private readonly scannedDevices: Map<string, BleProvisioningDevice> =
    new Map<string, BleProvisioningDevice>();
  private lastDevice: BleProvisioningDevice | undefined = undefined;

  constructor(transport: BleTransport, crypto: CryptoPort, clock: ClockPort,
    random: RandomPort, gatewayClient: IGatewayClient, credentials: GatewayCredentialPort,
    drafts: SecretDraftPort, logger: LoggerPort, delay: BleDelay = defaultBleDelay,
    scanTimeoutMs: number = DEFAULT_SCAN_TIMEOUT_MS) {
    if (!Number.isInteger(scanTimeoutMs) || scanTimeoutMs <= 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.transport = transport;
    this.crypto = crypto;
    this.clock = clock;
    this.random = random;
    this.gatewayClient = gatewayClient;
    this.credentials = credentials;
    this.drafts = drafts;
    this.logger = logger;
    this.delay = delay;
    this.scanTimeoutMs = scanTimeoutMs;
  }

  get state(): ProvisioningState {
    return this.stateMachine.state;
  }

  // ---- Scan ---------------------------------------------------------------

  async startScan(filter: BleScanFilter, listener: BleScanListener): Promise<void> {
    if (this.running) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'provisioningActive')]);
    }
    await this.ensureReady();
    this.stopPublicScan(false);
    // A new public scan replaces the previous selection: only the latest scan
    // may satisfy an omitted request.device (F-02).
    this.scannedDevices.clear();
    this.lastDevice = undefined;
    this.publicScanListener = listener;
    this.publicScanActive = true;
    const seen: Map<string, boolean> = new Map<string, boolean>();
    const wrapped = new DelegatingScanListener(
      (device: BleProvisioningDevice): void => {
        if (!this.publicScanActive) {
          return;
        }
        if (seen.has(device.deviceId)) {
          return;
        }
        seen.set(device.deviceId, true);
        this.scannedDevices.set(device.deviceId, device);
        // Keep the latest unique candidate; resolveDevice still rejects when
        // more than one device was seen in this scan.
        this.lastDevice = device;
        listener.onDeviceFound(device);
      },
      (): void => {
        this.finishPublicScan(listener);
      },
      (error: AppError): void => {
        this.stopPublicScan(false);
        listener.onScanError(error);
      });
    try {
      await this.transport.startScan(filter, wrapped);
    } catch (error) {
      this.publicScanActive = false;
      this.publicScanListener = undefined;
      try {
        await this.transport.stopScan();
      } catch (stopError) {
        // Best-effort cleanup after a failed scan start.
      }
      throw mapProvisioningError(error as Error, 'PROVISIONING_CONNECT_FAILED', 'startScan');
    }
    if (this.publicScanActive) {
      this.publicScanTimer = setTimeout((): void => {
        this.publicScanTimer = 0;
        this.stopPublicScan(true);
      }, filter.timeoutMs);
    }
  }

  async stopScan(): Promise<void> {
    this.stopPublicScan(true);
    try {
      await this.transport.stopScan();
    } catch (error) {
      // Idempotent public stop.
    }
  }

  // ---- Provision ----------------------------------------------------------

  async provision(request: BleProvisioningRequest,
    listener: BleProvisioningProgressListener,
    cancellation?: CancellationToken): Promise<BleProvisioningResult> {
    if (this.running) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'provisioningActive')]);
    }
    // DES-A §16.8-4118: an empty draft means "re-provision an already-bound
    // gateway using its stored command secret", which is only valid when the
    // caller names the expected gateway. A new binding must pass a draft.
    if ((request.credentialDraftId === undefined || request.credentialDraftId.length === 0) &&
      request.expectedGatewayId === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'expectedGatewayId')]);
    }
    this.running = true;
    this.cancelled = false;
    this.activeListener = listener;
    let popCopy: Uint8Array = new Uint8Array(0);
    let passwordCopy: Uint8Array = new Uint8Array(0);
    let identity: BleProvisioningIdentity | undefined = undefined;
    let resultIp: string = '';
    let issuedDraftId: string | undefined = undefined;
    let completed = false;
    try {
      this.stopPublicScan(false);
      this.stateMachine.reset();
      popCopy = BytesUtil.copyOf(request.pop);
      passwordCopy = BytesUtil.copyOf(request.wifiPassword);
      // Listener callbacks run inside the guarded flow so a throwing callback
      // cannot leave `running`/`activeListener` locked (F-10).
      this.emitStage(listener, BleProvisioningStage.CONNECTING);
      this.transition(ProvisioningEvent.START);
      this.emitState(listener, ProvisioningState.PERMISSION);
      this.checkCancelled(cancellation);
      await this.ensureReady();
      this.transition(ProvisioningEvent.PERMISSION_GRANTED);

      this.emitState(listener, ProvisioningState.SCANNING);
      const device = await this.resolveDevice(request.device, cancellation);
      this.transition(ProvisioningEvent.DEVICE_FOUND);
      this.emitState(listener, ProvisioningState.CONNECTING);
      await this.connect(device.deviceId, cancellation);
      this.transition(ProvisioningEvent.CONNECTED);

      this.emitState(listener, ProvisioningState.DISCOVERING);
      await this.discover();
      this.transition(ProvisioningEvent.DISCOVERED);

      this.emitState(listener, ProvisioningState.CAPABILITY_CHECK);
      await this.checkCapability();
      this.transition(ProvisioningEvent.CAPABILITY_OK);

      this.emitStage(listener, BleProvisioningStage.SECURITY);
      this.emitState(listener, ProvisioningState.SECURITY_HANDSHAKE);
      await this.handshake(popCopy);
      this.transition(ProvisioningEvent.SECURITY_OK);

      this.emitStage(listener, BleProvisioningStage.IDENTITY);
      this.emitState(listener, ProvisioningState.SECURE_IDENTITY);
      identity = await this.negotiateIdentity(request.expectedGatewayId, listener);
      this.transition(ProvisioningEvent.IDENTITY_OK);

      this.emitStage(listener, BleProvisioningStage.WIFI_SCAN);
      this.emitState(listener, ProvisioningState.AP_SCANNING);
      await this.scanAccessPoints(listener, cancellation);
      this.transition(ProvisioningEvent.AP_SELECTED);

      this.emitStage(listener, BleProvisioningStage.WIFI_APPLY);
      this.emitState(listener, ProvisioningState.SENDING_CREDENTIALS);
      await this.applyCredentials(request.ssid, passwordCopy, cancellation);
      this.transition(ProvisioningEvent.CREDENTIALS_SENT);

      this.emitStage(listener, BleProvisioningStage.WIFI_STATUS);
      this.emitState(listener, ProvisioningState.WAITING_FOR_WIFI);
      const status = await this.waitForWifi(cancellation);
      resultIp = status.ip4 === undefined ? '' : status.ip4;
      this.transition(ProvisioningEvent.WIFI_CONNECTED);

      this.emitStage(listener, BleProvisioningStage.DONE);
      this.emitState(listener, ProvisioningState.DISCOVERING_ON_LAN);
      await this.finishProvisioning();

      // BLE is no longer needed: release the radio and the CTR session before
      // opening any LAN connection (BLE设计 §5-143).
      await this.teardownBle();
      this.checkCancelled(cancellation);

      this.emitStage(listener, BleProvisioningStage.BINDING_PROBE);
      if (identity === undefined || resultIp.length === 0) {
        throw AppErrors.internal('bleIdentity');
      }
      const outcome = await this.probeBinding(identity, resultIp, request, cancellation);
      // The probe consumed the original one-shot draft and re-issued a fresh
      // id. From here until the result is delivered, this new id is owned by
      // the failed path and must be destroyed on any error (SC-06 / F-07).
      if (outcome.credentialDraftId.length > 0) {
        issuedDraftId = outcome.credentialDraftId;
      }
      this.transition(ProvisioningEvent.BINDING_OK);

      const port = identity.tls === undefined ? ProtocolConstants.DEFAULT_GATEWAY_PORT :
        identity.tls.port;
      const completedAt = DateTimeUtil.formatUtcCompact(Math.floor(this.clock.nowMs()));
      const result = new BleProvisioningResult(identity, resultIp, port, outcome.boardLedConfirmed,
        outcome.credentialDraftId, completedAt);
      completed = true;
      this.emitState(listener, ProvisioningState.BOUND);
      if (listener.onCompleted !== undefined) {
        listener.onCompleted(result);
      }
      return result;
    } catch (error) {
      const typed = error as Error;
      this.destroyDraft(issuedDraftId);
      if (this.cancelled || isCode(typed, 'PROVISIONING_CANCELLED')) {
        this.safeTransition(ProvisioningEvent.CANCEL);
        this.emitState(listener, ProvisioningState.CANCELLED);
        this.destroyDraft(request.credentialDraftId);
        throw AppErrors.of('PROVISIONING_CANCELLED', []);
      }
      this.safeTransition(ProvisioningEvent.FAIL);
      const mapped = this.mapFailure(typed);
      this.emitState(listener, ProvisioningState.FAILED, mapped);
      if (listener.onError !== undefined) {
        listener.onError(mapped);
      }
      this.destroyDraft(request.credentialDraftId);
      throw mapped;
    } finally {
      // Even if teardown or draft cleanup throws, the service must not stay
      // locked: `running` and `activeListener` are reset in an inner finally
      // (F-10).
      try {
        BytesUtil.zeroize(popCopy);
        BytesUtil.zeroize(passwordCopy);
        await this.teardownBle();
        if (!completed) {
          this.destroyDraft(request.credentialDraftId);
          this.destroyDraft(issuedDraftId);
        }
      } finally {
        this.running = false;
        this.activeListener = undefined;
      }
    }
  }

  /**
   * F-07: step 2/3 seam. Performs the real Security1 handshake and identity
   * negotiation, then returns the gateway AP list so the wizard can render
   * step 3 before credentials are sent. The link is torn down afterwards; the
   * authoritative aggregated provision() repeats the handshake when applying
   * credentials. No SSID/password is sent here.
   */
  async scanWifiAccessPoints(request: BleWifiScanRequest,
    listener: BleProvisioningProgressListener,
    cancellation?: CancellationToken): Promise<ReadonlyArray<WifiAp>> {
    if (this.running) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'provisioningActive')]);
    }
    this.running = true;
    this.cancelled = false;
    this.activeListener = listener;
    let popCopy: Uint8Array = new Uint8Array(0);
    try {
      this.stopPublicScan(false);
      this.stateMachine.reset();
      popCopy = BytesUtil.copyOf(request.pop);
      this.emitStage(listener, BleProvisioningStage.CONNECTING);
      this.transition(ProvisioningEvent.START);
      this.emitState(listener, ProvisioningState.PERMISSION);
      this.checkCancelled(cancellation);
      await this.ensureReady();
      this.transition(ProvisioningEvent.PERMISSION_GRANTED);

      this.emitState(listener, ProvisioningState.SCANNING);
      const device = await this.resolveDevice(request.device, cancellation);
      this.transition(ProvisioningEvent.DEVICE_FOUND);
      this.emitState(listener, ProvisioningState.CONNECTING);
      await this.connect(device.deviceId, cancellation);
      this.transition(ProvisioningEvent.CONNECTED);

      this.emitState(listener, ProvisioningState.DISCOVERING);
      await this.discover();
      this.transition(ProvisioningEvent.DISCOVERED);

      this.emitState(listener, ProvisioningState.CAPABILITY_CHECK);
      await this.checkCapability();
      this.transition(ProvisioningEvent.CAPABILITY_OK);

      this.emitStage(listener, BleProvisioningStage.SECURITY);
      this.emitState(listener, ProvisioningState.SECURITY_HANDSHAKE);
      await this.handshake(popCopy);
      this.transition(ProvisioningEvent.SECURITY_OK);

      this.emitStage(listener, BleProvisioningStage.IDENTITY);
      this.emitState(listener, ProvisioningState.SECURE_IDENTITY);
      await this.negotiateIdentity(request.expectedGatewayId, listener);
      this.transition(ProvisioningEvent.IDENTITY_OK);

      this.emitStage(listener, BleProvisioningStage.WIFI_SCAN);
      this.emitState(listener, ProvisioningState.AP_SCANNING);
      const accessPoints = await this.scanAccessPoints(listener, cancellation);
      this.transition(ProvisioningEvent.AP_SELECTED);
      return accessPoints;
    } catch (error) {
      const typed = error as Error;
      if (this.cancelled || isCode(typed, 'PROVISIONING_CANCELLED')) {
        this.safeTransition(ProvisioningEvent.CANCEL);
        this.emitState(listener, ProvisioningState.CANCELLED);
        throw AppErrors.of('PROVISIONING_CANCELLED', []);
      }
      this.safeTransition(ProvisioningEvent.FAIL);
      const mapped = this.mapFailure(typed);
      this.emitState(listener, ProvisioningState.FAILED, mapped);
      if (listener.onError !== undefined) {
        listener.onError(mapped);
      }
      throw mapped;
    } finally {
      try {
        BytesUtil.zeroize(popCopy);
        await this.teardownBle();
      } finally {
        this.running = false;
        this.activeListener = undefined;
      }
    }
  }

  async cancel(): Promise<void> {
    this.cancelled = true;
    const listener = this.activeListener;
    await this.teardownBle();
    if (listener !== undefined) {
      this.safeTransition(ProvisioningEvent.CANCEL);
      this.emitState(listener, ProvisioningState.CANCELLED);
    }
  }

  // ---- Step helpers -------------------------------------------------------

  private async ensureReady(): Promise<void> {
    try {
      await this.transport.ensurePermission();
    } catch (error) {
      throw AppErrors.of('PROVISIONING_PERMISSION_DENIED', []);
    }
    let enabled = false;
    try {
      enabled = await this.transport.isBluetoothEnabled();
    } catch (error) {
      throw AppErrors.of('PROVISIONING_BLUETOOTH_OFF', []);
    }
    if (!enabled) {
      throw AppErrors.of('PROVISIONING_BLUETOOTH_OFF', []);
    }
  }

  private async resolveDevice(selected: BleProvisioningDevice | undefined,
    cancellation?: CancellationToken): Promise<BleProvisioningDevice> {
    this.checkCancelled(cancellation);
    if (selected !== undefined) {
      this.lastDevice = selected;
      return selected;
    }
    if (this.lastDevice !== undefined && this.scannedDevices.size <= 1) {
      return this.lastDevice;
    }
    if (this.scannedDevices.size > 1) {
      throw AppErrors.of('PROVISIONING_MULTIPLE_DEVICES', []);
    }
    const filter = new BleScanFilter(GattEndpointMap.SERVICE_UUID, DEFAULT_NAME_PREFIX,
      this.scanTimeoutMs);
    const found: Map<string, BleProvisioningDevice> = new Map<string, BleProvisioningDevice>();
    let scanError: AppError | undefined = undefined;
    let settle: (() => void) | undefined = undefined;
    const firstFound = new Promise<void>((resolve: () => void) => {
      settle = resolve;
    });
    const listener = new DelegatingScanListener(
      (device: BleProvisioningDevice): void => {
        found.set(device.deviceId, device);
        if (settle !== undefined) {
          settle();
        }
      },
      (): void => {
        if (settle !== undefined) {
          settle();
        }
      },
      (error: AppError): void => {
        scanError = error;
        if (settle !== undefined) {
          settle();
        }
      });
    try {
      await this.transport.startScan(filter, listener);
    } catch (error) {
      throw mapProvisioningError(error as Error, 'PROVISIONING_CONNECT_FAILED', 'scan');
    }
    let timer: number = 0;
    const timeout = new Promise<void>((resolve: () => void) => {
      timer = setTimeout(resolve, this.scanTimeoutMs);
    });
    try {
      await Promise.race<void>([firstFound, timeout]);
    } finally {
      if (timer !== 0) {
        clearTimeout(timer);
      }
    }
    await this.transport.stopScan();
    this.checkCancelled(cancellation);
    if (scanError !== undefined) {
      throw mapProvisioningError(scanError, 'PROVISIONING_DEVICE_NOT_FOUND', 'scan');
    }
    if (found.size === 0) {
      throw AppErrors.of('PROVISIONING_DEVICE_NOT_FOUND', []);
    }
    if (found.size > 1) {
      throw AppErrors.of('PROVISIONING_MULTIPLE_DEVICES', []);
    }
    let device: BleProvisioningDevice | undefined = undefined;
    found.forEach((value: BleProvisioningDevice) => {
      device = value;
    });
    if (device === undefined) {
      throw AppErrors.of('PROVISIONING_DEVICE_NOT_FOUND', []);
    }
    this.lastDevice = device;
    return device;
  }

  private async connect(deviceId: string, cancellation?: CancellationToken): Promise<void> {
    this.checkCancelled(cancellation);
    try {
      this.connection = await this.transport.connect(deviceId, cancellation);
    } catch (error) {
      if (isCode(error as Error, 'PROVISIONING_CANCELLED')) {
        throw error as Error;
      }
      throw mapProvisioningError(error as Error, 'PROVISIONING_CONNECT_FAILED', 'connect');
    }
  }

  private async discover(): Promise<void> {
    const connection = this.requireConnection();
    let mtu = 0;
    try {
      mtu = await connection.requestMtu(MTU_TARGET);
    } catch (error) {
      throw mapProvisioningError(error as Error, 'PROVISIONING_CONNECT_FAILED', 'mtu');
    }
    if (!Number.isInteger(mtu) || mtu < MTU_MINIMUM) {
      throw AppErrors.of('PROVISIONING_MTU_TOO_SMALL', []);
    }
    let characteristics: ReadonlyArray<BleCharacteristicRef>;
    try {
      const services = await connection.discoverServices(GattEndpointMap.SERVICE_UUID);
      let foundService = false;
      for (let index = 0; index < services.length; index++) {
        if (services[index].uuid.toLowerCase() === GattEndpointMap.SERVICE_UUID) {
          foundService = true;
          break;
        }
      }
      if (!foundService) {
        throw AppErrors.of('PROVISIONING_GATT_INCOMPLETE',
          [new NameValue('field', 'service')]);
      }
      characteristics = await connection.discoverCharacteristics(GattEndpointMap.SERVICE_UUID);
    } catch (error) {
      throw mapProvisioningError(error as Error, 'PROVISIONING_GATT_INCOMPLETE', 'discovery');
    }
    const descriptors: Map<string, Uint8Array> = new Map<string, Uint8Array>();
    for (let index = 0; index < characteristics.length; index++) {
      const characteristic = characteristics[index];
      const descriptor = new BleDescriptorRef(characteristic.serviceUuid,
        characteristic.characteristicUuid, GattEndpointMap.USER_DESCRIPTION_UUID);
      try {
        const raw = await connection.readDescriptor(descriptor);
        descriptors.set(characteristic.serviceUuid + '|' + characteristic.characteristicUuid, raw);
      } catch (error) {
        throw AppErrors.of('PROVISIONING_GATT_INCOMPLETE',
          [new NameValue('field', 'userDescription')]);
      }
    }
    try {
      this.endpoints = GattEndpointMap.build(characteristics, descriptors);
    } catch (error) {
      throw mapProvisioningError(error as Error, 'PROVISIONING_GATT_INCOMPLETE', 'endpoints');
    }
    this.queue = new GattRequestQueue(GATT_REQUEST_TIMEOUT_MS);
    this.channel = new GattChannel(connection, this.endpoints, this.queue, this.delay);
  }

  private async checkCapability(): Promise<void> {
    const channel = this.requireChannel();
    try {
      const response = await channel.requestPlain(GattEndpointMap.PROTO_VER,
        Utf8.encode(PROTO_VER_PROBE));
      ProtoVerParser.parse(response);
    } catch (error) {
      throw mapProvisioningError(error as Error, 'PROVISIONING_CAPABILITY_UNSUPPORTED',
        'protoVer');
    }
  }

  private async handshake(pop: Uint8Array): Promise<void> {
    const channel = this.requireChannel();
    this.session = new Security1Session(this.crypto, this.random, pop);
    try {
      const step0 = await this.session.createStep0();
      const response0 = await channel.requestPlain(GattEndpointMap.PROV_SESSION, step0);
      const step1 = await this.session.handleStep0Response(response0);
      const response1 = await channel.requestPlain(GattEndpointMap.PROV_SESSION, step1);
      await this.session.handleStep1Response(response1);
      channel.setSession(this.session);
    } catch (error) {
      const typed = error as Error;
      if (isCode(typed, 'PROVISIONING_POP_INVALID')) {
        throw typed;
      }
      throw mapProvisioningError(typed, 'PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'security');
    }
  }

  private async negotiateIdentity(expectedGatewayId: string | undefined,
    listener: BleProvisioningProgressListener): Promise<BleProvisioningIdentity> {
    const channel = this.requireChannel();
    const session = this.session;
    if (session === undefined) {
      throw AppErrors.of('PROVISIONING_SECURITY_HANDSHAKE_FAILED', []);
    }
    const negotiator = new IdentityNegotiator();
    const identity = await negotiator.negotiate(session,
      async (endpoint: string, payload: Uint8Array): Promise<Uint8Array> => {
        return await channel.request(endpoint, payload);
      }, expectedGatewayId);
    if (listener.onStateChanged !== undefined) {
      listener.onStateChanged(new ProvisioningProgress(ProvisioningState.SECURE_IDENTITY,
        undefined, undefined, identity));
    }
    return identity;
  }

  private async scanAccessPoints(listener: BleProvisioningProgressListener,
    cancellation?: CancellationToken): Promise<ReadonlyArray<WifiAp>> {
    const channel = this.requireChannel();
    const flow = new WifiProvisioningFlow(this.clock, this.delay);
    const accessPoints = await flow.scan(channel, cancellation);
    if (listener.onAccessPoints !== undefined) {
      listener.onAccessPoints(accessPoints);
    }
    return accessPoints;
  }

  private async applyCredentials(ssid: string, password: Uint8Array,
    cancellation?: CancellationToken): Promise<void> {
    throwIfCancelled(cancellation);
    this.checkCancelled(cancellation);
    const channel = this.requireChannel();
    const flow = new WifiProvisioningFlow(this.clock, this.delay);
    const config = new WifiConfig(ssid, password);
    await flow.apply(channel, config);
  }

  private async waitForWifi(cancellation?: CancellationToken): Promise<WifiStatus> {
    this.checkCancelled(cancellation);
    const channel = this.requireChannel();
    const flow = new WifiProvisioningFlow(this.clock, this.delay);
    return await flow.waitForConnection(channel, cancellation);
  }

  private async finishProvisioning(): Promise<void> {
    const channel = this.requireChannel();
    const endpoints = this.requireEndpoints();
    const flow = new WifiProvisioningFlow(this.clock, this.delay);
    await flow.finish(channel, endpoints.requiresDoneEndpoint());
  }

  private async probeBinding(identity: BleProvisioningIdentity, ip: string,
    request: BleProvisioningRequest,
    cancellation?: CancellationToken): Promise<BindingProbeOutcome> {
    const prober = new BindingProber(this.gatewayClient, this.credentials, this.clock,
      this.logger, this.delay);
    return await prober.probe(identity, ip, request.familyId, request.credentialDraftId,
      this.drafts, cancellation);
  }

  // ---- Cleanup ------------------------------------------------------------

  /** Destroys a one-shot draft if the flow still owns it; idempotent. */
  private destroyDraft(draftId: string | undefined): void {
    if (draftId !== undefined) {
      this.drafts.destroy(draftId);
    }
  }

  private async teardownBle(): Promise<void> {
    const connection = this.connection;
    this.connection = undefined;
    if (this.session !== undefined) {
      this.session.destroy();
      this.session = undefined;
    }
    if (this.channel !== undefined) {
      this.channel.clearSession();
      this.channel = undefined;
    }
    if (this.queue !== undefined) {
      this.queue.destroy();
      this.queue = undefined;
    }
    this.endpoints = undefined;
    try {
      await this.transport.stopScan();
    } catch (error) {
      // Idempotent teardown: a stopped/absent scan is not a failure.
    }
    if (connection !== undefined) {
      try {
        await connection.disconnect();
      } catch (error) {
        // The link may already be gone; cleanup remains complete.
      }
    }
  }

  private stopPublicScan(notify: boolean): void {
    if (this.publicScanTimer !== 0) {
      clearTimeout(this.publicScanTimer);
      this.publicScanTimer = 0;
    }
    const wasActive = this.publicScanActive;
    this.publicScanActive = false;
    const listener = this.publicScanListener;
    this.publicScanListener = undefined;
    try {
      this.transport.stopScan().then((): void => {}, (): void => {});
    } catch (error) {
      // Idempotent stop.
    }
    if (notify && wasActive && listener !== undefined) {
      listener.onScanFinished();
    }
  }

  private finishPublicScan(listener: BleScanListener): void {
    if (this.publicScanTimer !== 0) {
      clearTimeout(this.publicScanTimer);
      this.publicScanTimer = 0;
    }
    if (!this.publicScanActive) {
      return;
    }
    this.publicScanActive = false;
    this.publicScanListener = undefined;
    listener.onScanFinished();
  }

  private requireConnection(): BleConnection {
    if (this.connection === undefined) {
      throw AppErrors.of('PROVISIONING_CONNECT_FAILED', []);
    }
    return this.connection;
  }

  private requireChannel(): GattChannel {
    if (this.channel === undefined) {
      throw AppErrors.of('PROVISIONING_GATT_INCOMPLETE', []);
    }
    return this.channel;
  }

  private requireEndpoints(): GattEndpointMap {
    if (this.endpoints === undefined) {
      throw AppErrors.of('PROVISIONING_GATT_INCOMPLETE', []);
    }
    return this.endpoints;
  }

  // ---- State/progress -----------------------------------------------------

  private transition(event: ProvisioningEvent): void {
    this.stateMachine.transition(event);
  }

  private safeTransition(event: ProvisioningEvent): void {
    try {
      this.stateMachine.transition(event);
    } catch (error) {
      // The flow may already be terminal (e.g. cancel raced a failure); the
      // terminal state is preserved and the original error is reported.
    }
  }

  private checkCancelled(cancellation?: CancellationToken): void {
    if (this.cancelled) {
      throw AppErrors.of('PROVISIONING_CANCELLED', []);
    }
    throwIfCancelled(cancellation);
  }

  private emitStage(listener: BleProvisioningProgressListener, stage: BleProvisioningStage): void {
    listener.onStage(stage);
  }

  private emitState(listener: BleProvisioningProgressListener, state: ProvisioningState,
    error?: AppError): void {
    if (listener.onStateChanged !== undefined) {
      listener.onStateChanged(new ProvisioningProgress(state, undefined, undefined, undefined,
        error));
    }
  }

  private mapFailure(error: Error): AppError {
    if (error instanceof AppError) {
      return error;
    }
    return AppErrors.internal('bleProvisioning');
  }
}
