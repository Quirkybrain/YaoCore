/*
 * YaoCore C-15 CloudService.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §8.1.7, §8.2, §8.3; D-012; PR-10
 *
 * Manual IoTDA token only (no refresh), signed CreateCommand, shadow polling
 * and completion confirmation. Cloud availability never blocks LAN control.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import type { ClockPort } from '../../common/types/Ports';
import type { LoggerPort, MetricsPort } from '../../contracts/Ports';
import type { CancellationToken } from '../../common/types/CancellationToken';
import type { DeviceControlCommand } from '../../model/ControlModels';
import { StateVerification } from '../../model/ControlModels';
import type { CloudConfig } from '../../model/FamilyModels';
import type { CloudConfigStore, CloudCredentialPort } from '../../contracts/CloudPorts';
import type { TimerPort } from '../../contracts/TimerPort';
import { CloudCommandExpectation, CloudCompletionPolicy, CloudConfigValidation, CloudConfigView, CloudStateChangedEvent, CloudTokenStatus, CloudTransportState } from './CloudModels';
import { CloudCommandReceipt, CloudCompletion, CloudCompletionVerdict, CloudControlOutcome } from '../../model/CloudControlModels';
import { CloudCommandClient } from './CloudCommandClient';
import { CloudCompletionEvaluator } from './CloudCompletionEvaluator';
import { CloudConfigValidator } from './CloudConfigValidator';
import { CloudCancellation } from './CloudCancellation';
import { CloudErrors } from './CloudErrors';
import { ShadowReader } from './ShadowReader';

const NETWORK_FAILURE_THRESHOLD: number = 2;

export class CloudService {
  private readonly configs: CloudConfigStore;
  private readonly credentials: CloudCredentialPort;
  private readonly commands: CloudCommandClient;
  private readonly shadows: ShadowReader;
  private readonly evaluator: CloudCompletionEvaluator;
  private readonly clock: ClockPort;
  private readonly timer: TimerPort;
  private readonly logger: LoggerPort;
  private readonly metrics: MetricsPort;
  private readonly listeners: Array<(event: CloudStateChangedEvent) => void> = [];
  private revision: number = 0;
  private disposed: boolean = false;
  private tokenFailure: string = '';
  private authFailureAt: string | undefined = undefined;
  private lastError: AppError | undefined = undefined;
  private networkFailures: number = 0;
  private unavailable: boolean = false;
  private pollCancellation: CloudCancellation | undefined = undefined;

  constructor(configs: CloudConfigStore, credentials: CloudCredentialPort,
    commands: CloudCommandClient, shadows: ShadowReader, evaluator: CloudCompletionEvaluator,
    clock: ClockPort, timer: TimerPort, logger: LoggerPort, metrics: MetricsPort) {
    this.configs = configs;
    this.credentials = credentials;
    this.commands = commands;
    this.shadows = shadows;
    this.evaluator = evaluator;
    this.clock = clock;
    this.timer = timer;
    this.logger = logger;
    this.metrics = metrics;
  }

  async initialize(): Promise<void> {
    await this.getState();
  }

  async getState(): Promise<CloudConfigView> {
    let config: CloudConfig | undefined = undefined;
    try {
      config = await this.configs.load();
    } catch (error) {
      const appError = CloudService.asAppError(error);
      return new CloudConfigView(undefined, CloudTransportState.UNAVAILABLE, false, undefined,
        appError);
    }
    if (config === undefined) {
      return new CloudConfigView(undefined, CloudTransportState.NOT_CONFIGURED, false);
    }
    const validation = CloudConfigValidator.validate(config);
    if (!validation.valid) {
      return new CloudConfigView(config, CloudTransportState.UNAVAILABLE, false, undefined,
        validation.errors[0]);
    }
    let present = false;
    let updatedAt: string | undefined = undefined;
    try {
      present = await this.credentials.hasToken();
      updatedAt = await this.credentials.updatedAt();
    } catch (error) {
      const appError = CloudService.asAppError(error);
      return new CloudConfigView(config, CloudTransportState.UNAVAILABLE, false, undefined,
        appError);
    }
    if (!present) {
      return new CloudConfigView(config, CloudTransportState.TOKEN_MISSING, false);
    }
    if (this.tokenFailure === 'CLOUD_TOKEN_INVALID') {
      return new CloudConfigView(config, CloudTransportState.TOKEN_INVALID, true, updatedAt,
        this.lastError);
    }
    if (this.tokenFailure === 'CLOUD_TOKEN_EXPIRED') {
      return new CloudConfigView(config, CloudTransportState.TOKEN_EXPIRED, true, updatedAt,
        this.lastError);
    }
    if (this.unavailable) {
      return new CloudConfigView(config, CloudTransportState.UNAVAILABLE, true, updatedAt,
        this.lastError);
    }
    return new CloudConfigView(config, CloudTransportState.CONFIGURED, true, updatedAt);
  }

  async getTokenStatus(): Promise<CloudTokenStatus> {
    const view = await this.getState();
    return new CloudTokenStatus(view.tokenPresent, view.state, view.tokenUpdatedAt,
      this.authFailureAt);
  }

  async saveConfig(config: CloudConfig, token?: string): Promise<CloudConfigView> {
    this.ensureActive();
    const validation = this.validateConfig(config);
    if (!validation.valid) {
      throw validation.errors[0];
    }
    await this.configs.save(config);
    if (token !== undefined) {
      if (token.length > 0) {
        await this.credentials.putToken(token);
      } else {
        await this.credentials.removeToken();
      }
      // F-02: only a new non-empty token (or an explicit clear) resets the
      // transient token-failure state. A bare saveConfig(config) keeps
      // TOKEN_EXPIRED/TOKEN_INVALID so the UI still asks for a new token.
      this.resetFailureState();
    }
    return this.notify();
  }

  async clearConfig(): Promise<void> {
    this.ensureActive();
    await this.configs.clear();
    try {
      await this.credentials.removeToken();
    } catch (error) {
      if (!(error instanceof AppError) || error.code !== 'ASSET_NOT_FOUND') {
        throw CloudService.asAppError(error);
      }
    }
    this.resetFailureState();
    await this.notify();
  }

  async clearToken(): Promise<void> {
    this.ensureActive();
    try {
      await this.credentials.removeToken();
    } catch (error) {
      if (!(error instanceof AppError) || error.code !== 'ASSET_NOT_FOUND') {
        throw CloudService.asAppError(error);
      }
    }
    this.resetFailureState();
    await this.notify();
  }

  validateConfig(config: CloudConfig): CloudConfigValidation {
    return CloudConfigValidator.validate(config);
  }

  async testConnection(cancellation?: CancellationToken): Promise<CloudConfigValidation> {
    // F-03 two-layer semantics (DES-B §8.1.7/§8.3.1): the persistent layer
    // (cloud_config + token) is never written here; only the in-process
    // transient health layer is updated from the probe result.
    let config: CloudConfig | undefined = undefined;
    try {
      config = await this.configs.load();
    } catch (error) {
      return new CloudConfigValidation(false, [CloudService.asAppError(error)]);
    }
    if (config === undefined) {
      return new CloudConfigValidation(false, [AppErrors.of('CLOUD_NOT_CONFIGURED', [])]);
    }
    const validation = this.validateConfig(config);
    if (!validation.valid) {
      return validation;
    }
    let tokenPresent = false;
    try {
      tokenPresent = await this.credentials.hasToken();
    } catch (error) {
      return new CloudConfigValidation(false, [CloudService.asAppError(error)]);
    }
    if (!tokenPresent) {
      return new CloudConfigValidation(false, [AppErrors.of('CLOUD_TOKEN_MISSING', [])]);
    }
    let previousState: CloudTransportState;
    try {
      previousState = (await this.getState()).state;
    } catch (error) {
      previousState = CloudTransportState.UNAVAILABLE;
    }
    try {
      await this.shadows.read(config.deviceId, cancellation);
      this.recordNetworkSuccess();
      if ((await this.getState()).state !== previousState) {
        await this.notify();
      }
      return validation;
    } catch (error) {
      const appError = CloudService.asAppError(error);
      if (CloudErrors.tokenState(appError.code)) {
        // 401/403: record the transient token failure (no token rewrite, no
        // automatic retry) and notify subscribers.
        this.recordFailure(appError);
        await this.notify();
      } else {
        // A manual probe failure is not a persistent network failure: keep
        // the failure counter/UNAVAILABLE flag untouched (F-03).
        this.lastError = appError;
      }
      return new CloudConfigValidation(false, [appError], validation.commandEndpoint,
        validation.shadowEndpoint);
    }
  }

  async send(command: DeviceControlCommand,
    cancellation?: CancellationToken): Promise<CloudCommandReceipt> {
    this.ensureActive();
    if (cancellation !== undefined && cancellation.cancelled) {
      throw AppErrors.of('PROVISIONING_CANCELLED', []);
    }
    try {
      const receipt = await this.commands.send(command, cancellation);
      this.recordNetworkSuccess();
      return receipt;
    } catch (error) {
      const appError = CloudService.asAppError(error);
      this.recordFailure(appError);
      throw appError;
    }
  }

  async awaitCompletion(expectation: CloudCommandExpectation,
    cancellation?: CancellationToken,
    policy: CloudCompletionPolicy = CloudCompletionPolicy.defaults()): Promise<CloudControlOutcome> {
    this.ensureActive();
    const startedAtMs = this.clock.nowMs();
    const pollCancellation = new CloudCancellation(cancellation);
    this.pollCancellation = pollCancellation;
    const receipt = new CloudCommandReceipt(expectation.gatewayId, expectation.requestId,
      expectation.seq, 0, expectation.notBeforeMs);
    try {
      if (policy.initialDelayMs > 0) {
        await this.timer.sleep(policy.initialDelayMs, pollCancellation);
      }
      let attempts = 0;
      while (attempts < policy.maxAttempts) {
        pollCancellation.throwIfCancelled();
        if (this.clock.nowMs() - startedAtMs > policy.maxElapsedMs) {
          break;
        }
        attempts++;
        let verdict: CloudCompletionVerdict;
        try {
          const shadow = await this.shadows.read(expectation.gatewayId, pollCancellation);
          verdict = this.evaluator.evaluate(expectation, shadow);
        } catch (error) {
          const appError = CloudService.asAppError(error);
          if (appError.code === 'PROVISIONING_CANCELLED') {
            throw appError;
          }
          if (CloudErrors.tokenState(appError.code)) {
            this.recordFailure(appError);
            throw appError;
          }
          if (appError.code === 'CLOUD_SHADOW_INVALID') {
            const invalid = new CloudCompletionVerdict(CloudCompletion.INVALID,
              StateVerification.UNVERIFIED, 'SHADOW_INVALID', undefined, undefined, undefined,
              undefined, appError);
            return new CloudControlOutcome(receipt, invalid,
              this.clock.nowMs() - startedAtMs, appError);
          }
          this.recordFailure(appError);
          throw appError;
        }
        if (verdict.completion === CloudCompletion.CONFIRMED ||
          verdict.completion === CloudCompletion.UNSUPPORTED ||
          verdict.completion === CloudCompletion.INVALID) {
          const elapsed = this.clock.nowMs() - startedAtMs;
          this.metrics.record('cloud.command.completion.ms', elapsed);
          this.recordNetworkSuccess();
          return new CloudControlOutcome(receipt, verdict, elapsed, verdict.error);
        }
        await this.timer.sleep(policy.intervalMs, pollCancellation);
      }
      pollCancellation.throwIfCancelled();
      const timeout = AppErrors.of('CLOUD_COMPLETION_TIMEOUT', [
        new NameValue('requestId', expectation.requestId),
        new NameValue('seq', String(expectation.seq)),
        new NameValue('deviceId', expectation.targetDeviceId)
      ]);
      const timedOut = new CloudCompletionVerdict(CloudCompletion.PENDING,
        StateVerification.UNVERIFIED, 'COMPLETION_TIMEOUT', undefined, undefined, undefined,
        undefined, timeout);
      return new CloudControlOutcome(receipt, timedOut, this.clock.nowMs() - startedAtMs,
        timeout);
    } finally {
      if (this.pollCancellation === pollCancellation) {
        this.pollCancellation = undefined;
      }
    }
  }

  async sendAndConfirm(command: DeviceControlCommand,
    policy: CloudCompletionPolicy = CloudCompletionPolicy.defaults(),
    cancellation?: CancellationToken): Promise<CloudControlOutcome> {
    this.ensureActive();
    const notBeforeMs = this.clock.nowMs();
    const receipt = await this.send(command, cancellation);
    const expectation = new CloudCommandExpectation(command.gatewayId, command.target,
      command.action, command.value, receipt.requestId, receipt.seq, notBeforeMs);
    const outcome = await this.awaitCompletion(expectation, cancellation, policy);
    const elapsed = this.clock.nowMs() - notBeforeMs;
    const result = new CloudControlOutcome(receipt, outcome.verdict, elapsed, outcome.error);
    this.logger.info('cloud.command', 'completion', [
      new NameValue('requestId', receipt.requestId),
      new NameValue('seq', String(receipt.seq)),
      new NameValue('completion', outcome.verdict.completion),
      new NameValue('verification', outcome.verdict.stateVerification)
    ]);
    return result;
  }

  stopPolling(): void {
    const current = this.pollCancellation;
    if (current !== undefined) {
      current.cancel();
    }
    this.timer.cancel();
  }

  subscribe(listener: (event: CloudStateChangedEvent) => void): () => void {
    this.listeners.push(listener);
    return (): void => {
      const index = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    };
  }

  dispose(): void {
    this.disposed = true;
    this.stopPolling();
    this.listeners.length = 0;
  }

  private async notify(): Promise<CloudConfigView> {
    const view = await this.getState();
    this.revision++;
    const event = new CloudStateChangedEvent(view, this.revision);
    const pending = this.listeners.slice();
    for (let index = 0; index < pending.length; index++) {
      try {
        pending[index](event);
      } catch (error) {
        this.logger.warn('cloud.state', 'listener failed', []);
      }
    }
    return view;
  }

  private recordFailure(error: AppError): void {
    this.lastError = error;
    if (CloudErrors.tokenState(error.code)) {
      this.tokenFailure = error.code;
      this.authFailureAt = DateTimeUtil.formatUtcCompact(this.clock.nowMs());
      return;
    }
    if (error.code === 'CLOUD_REQUEST_FAILED' || error.code === 'CLOUD_SERVICE_UNAVAILABLE' ||
      error.code === 'CLOUD_RATE_LIMITED') {
      this.networkFailures++;
      if (this.networkFailures >= NETWORK_FAILURE_THRESHOLD) {
        this.unavailable = true;
      }
    }
  }

  private recordNetworkSuccess(): void {
    this.networkFailures = 0;
    this.unavailable = false;
    this.lastError = undefined;
  }

  private resetFailureState(): void {
    this.tokenFailure = '';
    this.authFailureAt = undefined;
    this.lastError = undefined;
    this.networkFailures = 0;
    this.unavailable = false;
  }

  private ensureActive(): void {
    if (this.disposed) {
      throw AppErrors.of('INTERNAL_ERROR', [new NameValue('field', 'disposed')]);
    }
  }

  private static asAppError(error: Object): AppError {
    if (error instanceof AppError) {
      return error;
    }
    return AppErrors.of('INTERNAL_ERROR', []);
  }
}
