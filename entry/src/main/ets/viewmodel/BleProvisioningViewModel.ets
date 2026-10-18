/*
 * YaoCore C-23 BleProvisioningViewModel.
 * Producer: agent:implementation-engineer | Task: T-16 / wp-060-vm
 * Contract: DES-B §12.1.1, §12.3.1; DES-A §16.9; BLE设计 §7; PR-13; SC-06
 *
 * The wizard maps the C-19 provisioning state machine onto six steps. BLE
 * success is never "bound": BOUND is only emitted after the result exists,
 * C-07 `commitBinding` consumed `result.credentialDraftId` (R-1) and the
 * gateway was added to the family. Cancel/fail destroys only this session's
 * drafts and clears PoP/Wi-Fi inputs.
 */
import { AppErrors } from '../common/types/AppError';
import type { AppError } from '../common/types/AppError';
import { NameValue } from '../common/types/NameValue';
import type { ClockPort } from '../common/types/Ports';
import type { LoggerPort } from '../contracts/Ports';
import { BytesUtil } from '../common/utils/BytesUtil';
import { Utf8 } from '../common/utils/Utf8';
import { SecureBytes } from '../common/types/SecureBytes';
import { BleProvisioningDevice, BleProvisioningRequest, BleProvisioningStage, BleScanFilter, BleWifiScanRequest, ProvisioningProgress, ProvisioningState, WifiAp } from '../model/ProvisioningModels';
import type { BleProvisioningProgressListener, BleScanListener, IBleProvisioningClient } from '../contracts/BleProvisioningPorts';
import { GattEndpointMap } from '../model/GattEndpointMap';
import type { BleProvisioningResult } from '../model/ProvisioningModels';
import type { CryptoPort } from '../contracts/CryptoPort';
import type { SecretDraftPort } from '../contracts/SecretDraftPort';
import {
  LoadPhase,
  ViewModelError,
  ViewModelSupport
} from './core/ViewModelCore';
import type { ViewModelBase, VmTimerPort } from './core/ViewModelCore';
import type { ProvisioningPermissionPort } from '../contracts/PermissionPort';
import { ProvisioningPermissionKind } from '../contracts/PermissionPort';
import { I18nService } from '../service/i18n/I18nService';
import { GatewayRepository } from '../repository/GatewayRepository';
import { FamilyRepository } from '../repository/FamilyRepository';

const TAG: string = 'BleProvisioningViewModel';
const DEFAULT_SCAN_TIMEOUT_MS: number = 10000;
const MIN_COMMAND_SECRET_BYTES: number = 16;
const COMMAND_SECRET_BYTES: number = 32;
const SERVICE_NAME_PREFIX: string = 'YaoCore-GW-';

export enum WizardStep {
  STEP_0_PERMISSION = 0,
  STEP_1_SCAN = 1,
  STEP_2_HANDSHAKE = 2,
  STEP_3_WIFI_SELECT = 3,
  STEP_4_APPLY = 4,
  STEP_5_BOUND = 5
}

export enum ProvisioningPermissionState {
  UNKNOWN = 'UNKNOWN',
  GRANTED = 'GRANTED',
  DENIED = 'DENIED',
  BLUETOOTH_OFF = 'BLUETOOTH_OFF'
}

export class BleProvisioningViewState {
  readonly phase: LoadPhase;
  readonly step: WizardStep;
  readonly provisioning: ProvisioningState;
  readonly permission: ProvisioningPermissionState;
  readonly scanResults: ReadonlyArray<BleProvisioningDevice>;
  readonly selectedDevice?: BleProvisioningDevice;
  readonly accessPoints: ReadonlyArray<WifiAp>;
  readonly selectedSsid?: string;
  readonly progress?: ProvisioningProgress;
  readonly result?: BleProvisioningResult;
  readonly error?: ViewModelError;
  readonly draftReady: boolean;
  readonly canCancel: boolean;
  readonly revision: number;

  constructor(phase: LoadPhase, step: WizardStep, provisioning: ProvisioningState,
    permission: ProvisioningPermissionState,
    scanResults: ReadonlyArray<BleProvisioningDevice>,
    selectedDevice: BleProvisioningDevice | undefined,
    accessPoints: ReadonlyArray<WifiAp>, selectedSsid: string | undefined,
    progress: ProvisioningProgress | undefined, result: BleProvisioningResult | undefined,
    error: ViewModelError | undefined, draftReady: boolean, canCancel: boolean,
    revision: number) {
    this.phase = phase;
    this.step = step;
    this.provisioning = provisioning;
    this.permission = permission;
    this.scanResults = scanResults;
    this.selectedDevice = selectedDevice;
    this.accessPoints = accessPoints;
    this.selectedSsid = selectedSsid;
    this.progress = progress;
    this.result = result;
    this.error = error;
    this.draftReady = draftReady;
    this.canCancel = canCancel;
    this.revision = revision;
  }

  static initial(): BleProvisioningViewState {
    return new BleProvisioningViewState(LoadPhase.IDLE, WizardStep.STEP_0_PERMISSION,
      ProvisioningState.IDLE, ProvisioningPermissionState.UNKNOWN, [], undefined, [],
      undefined, undefined, undefined, undefined, false, false, 0);
  }
}

export class BleProvisioningViewModel implements ViewModelBase<BleProvisioningViewState> {
  private readonly ble: IBleProvisioningClient;
  private readonly gateways: GatewayRepository;
  private readonly families: FamilyRepository;
  private readonly drafts: SecretDraftPort;
  private readonly crypto: CryptoPort;
  private readonly permissions: ProvisioningPermissionPort;
  private readonly i18n: I18nService;
  private readonly clock: ClockPort;
  private readonly timer: VmTimerPort;
  private readonly logger: LoggerPort;

  private state: BleProvisioningViewState = BleProvisioningViewState.initial();
  private listeners: Array<(state: BleProvisioningViewState) => void> = [];
  private familyId: string = '';
  private revision: number = 0;
  private disposed: boolean = false;
  private submitting: boolean = false;
  private preparing: boolean = false;
  private scanTimerId: number | undefined = undefined;
  /** F-03: invalidates a late startScan continuation after back/cancel/dispose. */
  private scanGeneration: number = 0;
  /**
   * R3-02: cancellation generation for prepareWifi/submit/commitResult.
   * cancel() and dispose() advance it synchronously, so every continuation that
   * resumes from an await can drop a late AP list, provisioning result or
   * listener event instead of publishing over CANCELLED or committing a binding.
   */
  private cancelGeneration: number = 0;
  private requestDraftId?: string = undefined;
  private resultDraftId?: string = undefined;
  private selectedDevice?: BleProvisioningDevice = undefined;
  private lastErrorCode: string = '';

  constructor(ble: IBleProvisioningClient, gateways: GatewayRepository,
    families: FamilyRepository, drafts: SecretDraftPort, crypto: CryptoPort,
    permissions: ProvisioningPermissionPort, i18n: I18nService, clock: ClockPort, timer: VmTimerPort,
    logger: LoggerPort) {
    this.ble = ble;
    this.gateways = gateways;
    this.families = families;
    this.drafts = drafts;
    this.crypto = crypto;
    this.permissions = permissions;
    this.i18n = i18n;
    this.clock = clock;
    this.timer = timer;
    this.logger = logger;
  }

  getState(): BleProvisioningViewState {
    return this.state;
  }

  subscribe(listener: (state: BleProvisioningViewState) => void): () => void {
    this.listeners.push(listener);
    return (): void => {
      const index = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    };
  }

  async initialize(familyId: string): Promise<void> {
    this.familyId = familyId;
    this.lastErrorCode = '';
    this.publish(new BleProvisioningViewState(LoadPhase.READY, WizardStep.STEP_0_PERMISSION,
      ProvisioningState.IDLE, ProvisioningPermissionState.UNKNOWN, [], undefined, [], undefined,
      undefined, undefined, undefined, false, false, this.revision + 1));
  }

  async requestPermission(): Promise<void> {
    const generation = this.cancelGeneration;
    try {
      await this.permissions.ensure(ProvisioningPermissionKind.BLUETOOTH);
      if (this.isStale(generation)) {
        return;
      }
      this.publish(this.copy(WizardStep.STEP_0_PERMISSION, ProvisioningState.PERMISSION,
        ProvisioningPermissionState.GRANTED, undefined, false, false));
    } catch (error) {
      if (this.isStale(generation)) {
        return;
      }
      const appError = ViewModelSupport.asAppError(error);
      const permission = appError.code === 'PROVISIONING_BLUETOOTH_OFF' ?
        ProvisioningPermissionState.BLUETOOTH_OFF : ProvisioningPermissionState.DENIED;
      this.publish(this.copy(WizardStep.STEP_0_PERMISSION, ProvisioningState.PERMISSION,
        permission, this.errorOf(error), false, false));
    }
  }

  async startScan(): Promise<void> {
    const generation = this.cancelGeneration;
    if (!this.permissionGranted()) {
      await this.requestPermission();
      if (this.isStale(generation) || !this.permissionGranted()) {
        return;
      }
    }
    let scanToken: number = 0;
    try {
      this.clearScanTimer();
      scanToken = ++this.scanGeneration;
      const filter = new BleScanFilter(GattEndpointMap.SERVICE_UUID, SERVICE_NAME_PREFIX,
        DEFAULT_SCAN_TIMEOUT_MS);
      this.publish(this.copy(WizardStep.STEP_1_SCAN, ProvisioningState.SCANNING,
        this.state.permission, undefined, false, true));
      await this.ble.startScan(filter, new WizardScanListener(this, scanToken));
      if (this.isStale(generation) || scanToken !== this.scanGeneration ||
        this.state.step !== WizardStep.STEP_1_SCAN) {
        // F-03/R3-02: back/cancel/dispose happened while startScan was in flight.
        this.clearScanTimer();
        await this.stopScan();
        return;
      }
      this.scanTimerId = this.timer.setTimer(DEFAULT_SCAN_TIMEOUT_MS, (): void => {
        this.scanTimerId = undefined;
        if (this.isStale(generation) || scanToken !== this.scanGeneration ||
          this.state.step !== WizardStep.STEP_1_SCAN ||
          this.state.scanResults.length > 0) {
          return;
        }
        this.failWith(AppErrors.of('PROVISIONING_DEVICE_NOT_FOUND', []), WizardStep.STEP_1_SCAN,
          ProvisioningState.SCANNING);
      });
    } catch (error) {
      if (this.isStale(generation) || scanToken !== this.scanGeneration ||
        this.state.step !== WizardStep.STEP_1_SCAN) {
        return;
      }
      this.failWith(ViewModelSupport.asAppError(error), WizardStep.STEP_1_SCAN,
        ProvisioningState.SCANNING);
    }
  }

  async stopScan(): Promise<void> {
    this.scanGeneration++;
    this.clearScanTimer();
    try {
      await this.ble.stopScan();
    } catch (error) {
      this.logger.warn(TAG, 'stop_scan_failed',
        [new NameValue('code', ViewModelSupport.codeOf(error as Object))]);
    }
  }

  selectDevice(device: BleProvisioningDevice): void {
    this.selectedDevice = device;
    this.stopScan().catch((): void => undefined);
    this.publish(this.copy(WizardStep.STEP_2_HANDSHAKE, ProvisioningState.IDLE,
      this.state.permission, undefined, this.state.draftReady, true, device));
  }

  /**
   * F-08: C-23 exposes the C-28 permission gate's "open settings" recovery.
   * The port is optional so older test harnesses keep their narrow shape.
   */
  async openSettings(): Promise<void> {
    if (this.permissions.openSettings === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'openSettings')]);
    }
    await this.permissions.openSettings();
  }

  /**
   * F-07: real handshake + AP scan for step 3. The aggregated submit() below
   * still performs the authoritative flow when credentials are applied.
   */
  async prepareWifi(pop: string, expectedGatewayId?: string): Promise<void> {
    if (this.preparing || this.submitting) {
      return;
    }
    if (this.selectedDevice === undefined) {
      this.failWith(AppErrors.of('PROVISIONING_DEVICE_NOT_FOUND', []), this.state.step,
        this.state.provisioning);
      return;
    }
    if (pop.length === 0) {
      this.failWith(AppErrors.of('PROVISIONING_POP_INVALID', []), this.state.step,
        this.state.provisioning);
      return;
    }
    const generation = this.cancelGeneration;
    let popBytes: Uint8Array = new Uint8Array(0);
    this.preparing = true;
    try {
      popBytes = Utf8.encode(pop);
      const request = new BleWifiScanRequest(popBytes, this.selectedDevice, expectedGatewayId);
      this.publish(new BleProvisioningViewState(LoadPhase.READY,
        WizardStep.STEP_2_HANDSHAKE, ProvisioningState.CONNECTING, this.state.permission,
        this.state.scanResults, this.selectedDevice, [], undefined, undefined, undefined,
        undefined, false, true, this.revision + 1));
      if (this.isStale(generation)) {
        return;
      }
      const accessPoints = await this.ble.scanWifiAccessPoints(request,
        new WizardProgressListener(this, generation));
      // R3-02: cancel() may have won the race while the handshake/AP scan was
      // pending; a late AP list must not replace the CANCELLED state.
      if (this.isStale(generation)) {
        return;
      }
      this.publish(new BleProvisioningViewState(LoadPhase.READY,
        WizardStep.STEP_3_WIFI_SELECT, ProvisioningState.AP_SCANNING, this.state.permission,
        this.state.scanResults, this.selectedDevice, accessPoints, this.state.selectedSsid,
        undefined, undefined, undefined, false, true, this.revision + 1));
    } catch (error) {
      if (!this.isStale(generation)) {
        this.handleProvisionFailure(error as Object);
      }
    } finally {
      BytesUtil.zeroize(popBytes);
      this.preparing = false;
    }
  }

  async submit(pop: string, ssid: string, wifiPassword: string,
    commandSecretHex?: string, expectedGatewayId?: string): Promise<void> {
    if (this.submitting) {
      return;
    }
    if (this.selectedDevice === undefined) {
      this.failWith(AppErrors.of('PROVISIONING_DEVICE_NOT_FOUND', []), this.state.step,
        this.state.provisioning);
      return;
    }
    if (pop.length === 0 || ssid.length === 0 || wifiPassword.length === 0) {
      this.failWith(AppErrors.of('PROVISIONING_CREDENTIAL_MISSING', []), this.state.step,
        this.state.provisioning);
      return;
    }
    const generation = this.cancelGeneration;
    let secret: Uint8Array = new Uint8Array(0);
    let popBytes: Uint8Array = new Uint8Array(0);
    let passwordBytes: Uint8Array = new Uint8Array(0);
    try {
      if (commandSecretHex === undefined || commandSecretHex.length === 0) {
        secret = await this.crypto.randomBytes(COMMAND_SECRET_BYTES);
        // R3-02: do not create a request draft after cancel() won this race.
        if (this.isStale(generation)) {
          return;
        }
      } else {
        try {
          secret = BytesUtil.hexToBytes(commandSecretHex);
        } catch (encodingError) {
          throw AppErrors.of('SECRET_ENCODING_INVALID', []);
        }
      }
      if (secret.length < MIN_COMMAND_SECRET_BYTES) {
        throw AppErrors.of('PROVISIONING_CREDENTIAL_MISSING', []);
      }
      const secure = SecureBytes.from(secret);
      try {
        this.requestDraftId = this.drafts.put(secure);
      } finally {
        secure.destroy();
      }
      popBytes = Utf8.encode(pop);
      passwordBytes = Utf8.encode(wifiPassword);
      const request = new BleProvisioningRequest(ssid, passwordBytes, popBytes,
        this.selectedDevice, this.requestDraftId, this.familyId, expectedGatewayId);
      this.submitting = true;
      this.publish(new BleProvisioningViewState(LoadPhase.READY,
        WizardStep.STEP_2_HANDSHAKE, ProvisioningState.CONNECTING,
        this.state.permission, this.state.scanResults, this.selectedDevice,
        this.state.accessPoints, ssid, undefined, undefined, undefined, true, true,
        this.revision + 1));
      if (this.isStale(generation)) {
        return;
      }
      const result = await this.ble.provision(request,
        new WizardProgressListener(this, generation));
      // R3-02: BLE success after cancel is not binding success. Drop the late
      // result and destroy the re-issued draft before commitResult can reach
      // commitBinding/addGatewayToFamily or republish BOUND.
      if (this.isStale(generation)) {
        this.destroyResultDraft(result);
        return;
      }
      this.resultDraftId = result.credentialDraftId;
      await this.commitResult(result, generation);
    } catch (error) {
      if (this.isStale(generation)) {
        // cancel()/dispose() own the cancelled state; never publish a failure
        // over it. Drafts are released here as well because a BLE cancel hook
        // may reject the pending provision before the owner resumes.
        this.destroyDrafts();
      } else {
        this.handleProvisionFailure(error as Object);
      }
    } finally {
      BytesUtil.zeroize(secret);
      BytesUtil.zeroize(popBytes);
      BytesUtil.zeroize(passwordBytes);
      this.submitting = false;
    }
  }

  async retry(): Promise<void> {
    if (this.state.provisioning !== ProvisioningState.FAILED) {
      return;
    }
    const wifiFailure = this.lastErrorCode === 'PROVISIONING_WIFI_AUTH_ERROR' ||
      this.lastErrorCode === 'PROVISIONING_WIFI_NETWORK_NOT_FOUND' ||
      this.lastErrorCode === 'PROVISIONING_WIFI_TIMEOUT';
    const step = wifiFailure ? WizardStep.STEP_3_WIFI_SELECT : WizardStep.STEP_2_HANDSHAKE;
    this.publish(this.copy(step, ProvisioningState.IDLE, this.state.permission, undefined,
      false, true));
  }

  async cancel(): Promise<void> {
    // R3-02: advance the cancellation generation synchronously, before the
    // first await, so a provision/AP-scan continuation or listener callback
    // that resumes later can never publish or enter commitResult after this
    // call. Repeated calls are safe: they only advance the generation again
    // and republish the same terminal CANCELLED state.
    this.cancelGeneration++;
    this.scanGeneration++;
    this.clearScanTimer();
    try {
      await this.ble.cancel();
    } catch (error) {
      this.logger.warn(TAG, 'ble_cancel_failed',
        [new NameValue('code', ViewModelSupport.codeOf(error as Object))]);
    }
    this.destroyDrafts();
    this.publish(new BleProvisioningViewState(LoadPhase.READY, this.state.step,
      ProvisioningState.CANCELLED, this.state.permission, this.state.scanResults,
      this.state.selectedDevice, [], undefined, undefined, undefined, undefined, false, false,
      this.revision + 1));
  }

  back(): void {
    if (this.state.step === WizardStep.STEP_0_PERMISSION) {
      this.publish(this.copy(WizardStep.STEP_0_PERMISSION, ProvisioningState.IDLE,
        this.state.permission, undefined, false, false, this.state.selectedDevice));
      return;
    }
    if (this.state.step === WizardStep.STEP_1_SCAN) {
      // F-03: stepping back from scan is a free back (DES-B §12.1.1) but must
      // stop the radio and drop the 10s timer so it cannot bounce the UI back
      // to STEP_1 with a late PROVISIONING_DEVICE_NOT_FOUND.
      this.scanGeneration++;
      this.clearScanTimer();
      this.stopScan().catch((): void => undefined);
      this.publish(this.copy(WizardStep.STEP_0_PERMISSION, ProvisioningState.IDLE,
        this.state.permission, undefined, false, false, this.state.selectedDevice));
      return;
    }
    // From step 2+ back means cancel and clean up; the page asks for
    // confirmation before invoking this method.
    this.cancel().catch((): void => undefined);
  }

  translateError(error: ViewModelError | undefined): string {
    return error === undefined ? '' : this.i18n.t(error.i18nKey);
  }

  dispose(): void {
    this.disposed = true;
    this.cancelGeneration++;
    this.scanGeneration++;
    this.clearScanTimer();
    this.destroyDrafts();
    this.ble.cancel().catch((): void => undefined);
    this.listeners.splice(0, this.listeners.length);
  }

  // ---- callbacks from listeners ------------------------------------------

  onScanDevice(device: BleProvisioningDevice, scanToken?: number): void {
    if (this.isStale() || (scanToken !== undefined && scanToken !== this.scanGeneration) ||
      this.state.step !== WizardStep.STEP_1_SCAN) {
      return;
    }
    for (let index = 0; index < this.state.scanResults.length; index++) {
      if (this.state.scanResults[index].deviceId === device.deviceId) {
        return;
      }
    }
    const results: BleProvisioningDevice[] = [];
    for (let index = 0; index < this.state.scanResults.length; index++) {
      results.push(this.state.scanResults[index]);
    }
    results.push(device);
    this.publish(new BleProvisioningViewState(this.state.phase, this.state.step,
      this.state.provisioning, this.state.permission, results, this.state.selectedDevice,
      this.state.accessPoints, this.state.selectedSsid, this.state.progress, this.state.result,
      this.state.error, this.state.draftReady, this.state.canCancel, this.revision + 1));
  }

  onScanFinished(scanToken?: number): void {
    if (scanToken !== undefined && scanToken !== this.scanGeneration) {
      return;
    }
    this.clearScanTimer();
  }

  onScanError(error: Object, scanToken?: number): void {
    if (scanToken !== undefined && scanToken !== this.scanGeneration) {
      return;
    }
    this.clearScanTimer();
    if (this.isStale() || this.state.step !== WizardStep.STEP_1_SCAN) {
      return;
    }
    this.failWith(ViewModelSupport.asAppError(error), WizardStep.STEP_1_SCAN,
      ProvisioningState.SCANNING);
  }

  onProvisionState(progress: ProvisioningProgress, generation?: number): void {
    // R3-02: a listener owned by an older generation is a late event after
    // cancel/dispose; it must not overwrite the CANCELLED snapshot.
    if (this.isStale(generation)) {
      return;
    }
    const step = this.mapStep(progress.state);
    const aps = progress.apList === undefined ? this.state.accessPoints : progress.apList;
    const error = progress.error === undefined ? undefined :
      ViewModelError.fromError(progress.error, this.clock.nowMs());
    if (progress.state === ProvisioningState.CANCELLED) {
      this.publish(new BleProvisioningViewState(LoadPhase.READY, step,
        ProvisioningState.CANCELLED, this.state.permission, this.state.scanResults,
        this.state.selectedDevice, aps, this.state.selectedSsid, progress, this.state.result,
        undefined, false, false, this.revision + 1));
      return;
    }
    if (progress.state === ProvisioningState.FAILED) {
      this.lastErrorCode = progress.error === undefined ? '' : progress.error.code;
      this.publish(new BleProvisioningViewState(LoadPhase.ERROR, step, ProvisioningState.FAILED,
        this.state.permission, this.state.scanResults, this.state.selectedDevice, aps,
        this.state.selectedSsid, progress, this.state.result, error, this.state.draftReady,
        true, this.revision + 1));
      return;
    }
    this.publish(new BleProvisioningViewState(LoadPhase.READY, step, progress.state,
      this.state.permission, this.state.scanResults, this.state.selectedDevice, aps,
      this.state.selectedSsid, progress, this.state.result, undefined, this.state.draftReady,
      this.canCancelFor(step), this.revision + 1));
  }

  onAccessPoints(aps: ReadonlyArray<WifiAp>, generation?: number): void {
    if (this.isStale(generation)) {
      return;
    }
    this.publish(new BleProvisioningViewState(this.state.phase, WizardStep.STEP_3_WIFI_SELECT,
      ProvisioningState.AP_SCANNING, this.state.permission, this.state.scanResults,
      this.state.selectedDevice, aps, this.state.selectedSsid, this.state.progress,
      this.state.result, this.state.error, this.state.draftReady, true, this.revision + 1));
  }

  onProvisionError(error: Object, generation?: number): void {
    if (this.isStale(generation)) {
      return;
    }
    this.lastErrorCode = ViewModelSupport.codeOf(error as Object);
    this.destroyDrafts();
    this.publish(new BleProvisioningViewState(LoadPhase.ERROR, this.state.step,
      ProvisioningState.FAILED, this.state.permission, this.state.scanResults,
      this.state.selectedDevice, this.state.accessPoints, this.state.selectedSsid,
      this.state.progress, this.state.result, this.errorOf(error), this.state.draftReady, true,
      this.revision + 1));
  }

  onCompleted(result: BleProvisioningResult, generation?: number): void {
    // C-19 has finished BLE; C-07 commitBinding is still required for BOUND.
    if (this.isStale(generation)) {
      // R3-02: a completion that lands after cancel/dispose owns a re-issued
      // draft the cancelled session will never commit; zeroize it immediately.
      this.destroyResultDraft(result);
      return;
    }
    this.resultDraftId = result.credentialDraftId;
  }

  private async commitResult(result: BleProvisioningResult,
    generation: number): Promise<void> {
    if (this.isStale(generation)) {
      this.destroyResultDraft(result);
      return;
    }
    try {
      // R-1 ruling: commitBinding must consume the draft id re-issued by the
      // binding probe, not the original request draft id.
      await this.gateways.commitBinding(result, result.credentialDraftId, this.familyId);
    } catch (error) {
      this.drafts.destroy(result.credentialDraftId);
      this.resultDraftId = undefined;
      if (this.isStale(generation)) {
        return;
      }
      this.failWith(ViewModelSupport.asAppError(error), this.state.step,
        ProvisioningState.DISCOVERING_ON_LAN);
      return;
    }
    this.requestDraftId = undefined;
    this.resultDraftId = undefined;
    // R3-02: if cancel() won while commitBinding was in flight, the durable
    // route commit cannot be unwound, but the cancelled session must not add
    // the gateway to the family or report BOUND.
    if (this.isStale(generation)) {
      return;
    }
    try {
      await this.families.addGatewayToFamily(this.familyId, result.identity.gatewayId);
    } catch (error) {
      // The route is already durable; surface a partial-success error without
      // pretending the wizard completed.
      if (this.isStale(generation)) {
        return;
      }
      this.failWith(ViewModelSupport.asAppError(error), WizardStep.STEP_4_APPLY,
        ProvisioningState.DISCOVERING_ON_LAN);
      return;
    }
    if (this.isStale(generation)) {
      return;
    }
    this.publish(new BleProvisioningViewState(LoadPhase.READY, WizardStep.STEP_5_BOUND,
      ProvisioningState.BOUND, this.state.permission, this.state.scanResults,
      this.state.selectedDevice, this.state.accessPoints, this.state.selectedSsid,
      this.state.progress, result, undefined, false, false, this.revision + 1));
  }

  private handleProvisionFailure(error: Object): void {
    const appError = ViewModelSupport.asAppError(error);
    this.lastErrorCode = appError.code;
    this.destroyDrafts();
    if (appError.code === 'PROVISIONING_CANCELLED') {
      this.publish(new BleProvisioningViewState(LoadPhase.READY, this.state.step,
        ProvisioningState.CANCELLED, this.state.permission, this.state.scanResults,
        this.state.selectedDevice, [], undefined, undefined, undefined, undefined, false, false,
        this.revision + 1));
      return;
    }
    this.publish(new BleProvisioningViewState(LoadPhase.ERROR, this.state.step,
      ProvisioningState.FAILED, this.state.permission, this.state.scanResults,
      this.state.selectedDevice, this.state.accessPoints, this.state.selectedSsid,
      this.state.progress, this.state.result, this.errorOf(error), false, true,
      this.revision + 1));
  }

  private failWith(error: AppError, step: WizardStep,
    provisioning: ProvisioningState): void {
    this.lastErrorCode = error.code;
    this.publish(new BleProvisioningViewState(LoadPhase.ERROR, step, provisioning,
      this.state.permission, this.state.scanResults, this.state.selectedDevice,
      this.state.accessPoints, this.state.selectedSsid, this.state.progress, this.state.result,
      this.errorOf(error), this.state.draftReady, this.state.step >= WizardStep.STEP_2_HANDSHAKE,
      this.revision + 1));
  }

  private errorOf(error: Object): ViewModelError {
    return ViewModelSupport.viewError(error, this.clock);
  }

  private mapStep(state: ProvisioningState): WizardStep {
    if (state === ProvisioningState.PERMISSION) {
      return WizardStep.STEP_0_PERMISSION;
    }
    if (state === ProvisioningState.SCANNING) {
      return WizardStep.STEP_1_SCAN;
    }
    if (state === ProvisioningState.CONNECTING || state === ProvisioningState.DISCOVERING ||
      state === ProvisioningState.CAPABILITY_CHECK ||
      state === ProvisioningState.SECURITY_HANDSHAKE ||
      state === ProvisioningState.SECURE_IDENTITY) {
      return WizardStep.STEP_2_HANDSHAKE;
    }
    if (state === ProvisioningState.AP_SCANNING) {
      return WizardStep.STEP_3_WIFI_SELECT;
    }
    if (state === ProvisioningState.SENDING_CREDENTIALS ||
      state === ProvisioningState.WAITING_FOR_WIFI) {
      return WizardStep.STEP_4_APPLY;
    }
    if (state === ProvisioningState.DISCOVERING_ON_LAN || state === ProvisioningState.BOUND) {
      return WizardStep.STEP_5_BOUND;
    }
    return this.state.step;
  }

  private permissionGranted(): boolean {
    return this.state.permission === ProvisioningPermissionState.GRANTED;
  }

  /**
   * R3-02: true when the VM was disposed or cancel() advanced the generation
   * captured by an in-flight operation. An omitted generation is only used by
   * direct (non-listener) callers and keeps the pre-R3-02 method shape working.
   */
  private isStale(generation?: number): boolean {
    return this.disposed ||
      (generation !== undefined && generation !== this.cancelGeneration);
  }

  /** Zeroize a re-issued result draft that the cancelled session won't commit. */
  private destroyResultDraft(result: BleProvisioningResult): void {
    if (this.resultDraftId === result.credentialDraftId) {
      this.resultDraftId = undefined;
    }
    if (result.credentialDraftId.length > 0) {
      this.drafts.destroy(result.credentialDraftId);
    }
  }

  private canCancelFor(step: WizardStep): boolean {
    return step >= WizardStep.STEP_1_SCAN && step < WizardStep.STEP_5_BOUND;
  }

  private copy(step: WizardStep, provisioning: ProvisioningState,
    permission: ProvisioningPermissionState, error: ViewModelError | undefined,
    draftReady: boolean, canCancel: boolean,
    selectedDevice?: BleProvisioningDevice): BleProvisioningViewState {
    return new BleProvisioningViewState(this.state.phase, step, provisioning, permission,
      this.state.scanResults, selectedDevice === undefined ? this.state.selectedDevice :
        selectedDevice, this.state.accessPoints, this.state.selectedSsid, this.state.progress,
      this.state.result, error, draftReady, canCancel, this.revision + 1);
  }

  private clearScanTimer(): void {
    if (this.scanTimerId !== undefined) {
      this.timer.clearTimer(this.scanTimerId);
      this.scanTimerId = undefined;
    }
  }

  private destroyDrafts(): void {
    if (this.requestDraftId !== undefined) {
      this.drafts.destroy(this.requestDraftId);
      this.requestDraftId = undefined;
    }
    if (this.resultDraftId !== undefined) {
      this.drafts.destroy(this.resultDraftId);
      this.resultDraftId = undefined;
    }
  }

  private publish(next: BleProvisioningViewState): void {
    this.revision = next.revision;
    this.state = next;
    for (let index = 0; index < this.listeners.length; index++) {
      try {
        this.listeners[index](next);
      } catch (error) {
        this.logger.warn(TAG, 'listener_failed',
          [new NameValue('code', ViewModelSupport.codeOf(error as Object))]);
      }
    }
  }
}

class WizardScanListener implements BleScanListener {
  private readonly vm: BleProvisioningViewModel;
  /** R3-02: scan generation captured when this listener's scan started. */
  private readonly scanToken: number;

  constructor(vm: BleProvisioningViewModel, scanToken: number) {
    this.vm = vm;
    this.scanToken = scanToken;
  }

  onDeviceFound(device: BleProvisioningDevice): void {
    this.vm.onScanDevice(device, this.scanToken);
  }

  onScanFinished(): void {
    this.vm.onScanFinished(this.scanToken);
  }

  onScanError(error: AppError): void {
    this.vm.onScanError(error, this.scanToken);
  }
}

class WizardProgressListener implements BleProvisioningProgressListener {
  private readonly vm: BleProvisioningViewModel;
  /** R3-02: cancel generation this handshake/provision operation started in. */
  private readonly generation: number;

  constructor(vm: BleProvisioningViewModel, generation: number) {
    this.vm = vm;
    this.generation = generation;
  }

  onStage(stage: BleProvisioningStage): void {
    // Coarse stage is intentionally ignored: onStateChanged carries the exact
    // ProvisioningState used for the 6-step mapping.
  }

  onStateChanged(progress: ProvisioningProgress): void {
    this.vm.onProvisionState(progress, this.generation);
  }

  onAccessPoints(aps: ReadonlyArray<WifiAp>): void {
    this.vm.onAccessPoints(aps, this.generation);
  }

  onError(error: AppError): void {
    this.vm.onProvisionError(error, this.generation);
  }

  onCompleted(result: BleProvisioningResult): void {
    this.vm.onCompleted(result, this.generation);
  }
}
