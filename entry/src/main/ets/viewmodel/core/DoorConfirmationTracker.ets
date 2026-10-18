/*
 * YaoCore C-21 DoorConfirmationTracker (four-stage lock confirmation).
 * Producer: agent:implementation-engineer | Task: T-15 / wp-060-vm
 * Contract: DES-B §10.1.7, §10.3.3; ADR-004 §6; D-016
 *
 * SECURED is only reported after gateway-merged contact or an online contact
 * sensor reports closed. A timeout with an online sensor is UNCONFIRMED, not
 * "unlocked"; with an offline sensor it is UNKNOWN. No link configured can
 * only ever reach UNVERIFIED.
 */
import { AppErrors } from '../../common/types/AppError';
import type { ClockPort } from '../../common/types/Ports';
import type { DeviceKey } from '../../model/DeviceKey';
import { StateVerification } from '../../model/ControlModels';
import { ViewModelError } from './ViewModelCore';
import { ControlExecution } from '../../model/ControlExecution';
import type { VmTimerPort } from './ViewModelCore';

export enum DoorLinkMode {
  NONE = 'NONE',
  CONTACT_SENSOR = 'CONTACT_SENSOR',
  GATEWAY_MERGED = 'GATEWAY_MERGED'
}

export class DoorConfirmationPolicy {
  readonly confirmTimeoutMs: number;
  readonly revertSettleMs: number;

  constructor(confirmTimeoutMs: number, revertSettleMs: number) {
    if (!Number.isFinite(confirmTimeoutMs) || confirmTimeoutMs <= 0 ||
      !Number.isFinite(revertSettleMs) || revertSettleMs < 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.confirmTimeoutMs = confirmTimeoutMs;
    this.revertSettleMs = revertSettleMs;
  }

  static defaults(): DoorConfirmationPolicy {
    return new DoorConfirmationPolicy(10000, 320);
  }
}

export class DoorLinkConfig {
  readonly mode: DoorLinkMode;
  readonly contactSensorKey?: DeviceKey;
  readonly configuredAt?: string;

  constructor(mode: DoorLinkMode, contactSensorKey?: DeviceKey, configuredAt?: string) {
    this.mode = mode;
    this.contactSensorKey = contactSensorKey;
    this.configuredAt = configuredAt;
  }

  static none(): DoorLinkConfig {
    return new DoorLinkConfig(DoorLinkMode.NONE);
  }
}

export enum DoorStage {
  IDLE = 'IDLE',
  PENDING = 'PENDING',
  GATEWAY_CONFIRMED = 'GATEWAY_CONFIRMED',
  WAITING_CONTACT = 'WAITING_CONTACT',
  SECURED = 'SECURED',
  OPEN = 'OPEN',
  UNCONFIRMED = 'UNCONFIRMED',
  UNKNOWN = 'UNKNOWN',
  UNVERIFIED = 'UNVERIFIED',
  FAILED = 'FAILED'
}

export enum DoorLockState {
  SECURED = 'SECURED',
  UNCONFIRMED = 'UNCONFIRMED',
  UNKNOWN = 'UNKNOWN',
  OPEN = 'OPEN',
  UNKNOWN_INITIAL = 'UNKNOWN_INITIAL'
}

export class DoorUiState {
  readonly stage: DoorStage;
  readonly lockState: DoorLockState;
  readonly link: DoorLinkConfig;
  readonly alertActive: boolean;
  readonly lastAckAtMs?: number;
  readonly lastContactAtMs?: number;
  readonly error?: ViewModelError;
  readonly revision: number;

  constructor(stage: DoorStage, lockState: DoorLockState, link: DoorLinkConfig,
    alertActive: boolean, revision: number, lastAckAtMs?: number, lastContactAtMs?: number,
    error?: ViewModelError) {
    this.stage = stage;
    this.lockState = lockState;
    this.link = link;
    this.alertActive = alertActive;
    this.lastAckAtMs = lastAckAtMs;
    this.lastContactAtMs = lastContactAtMs;
    this.error = error;
    this.revision = revision;
  }

  static initial(link: DoorLinkConfig): DoorUiState {
    return new DoorUiState(DoorStage.IDLE, DoorLockState.UNKNOWN_INITIAL, link, false, 0);
  }
}

export class DoorConfirmationTracker {
  private readonly clock: ClockPort;
  private readonly timer: VmTimerPort;
  private readonly policy: DoorConfirmationPolicy;
  private state: DoorUiState = DoorUiState.initial(DoorLinkConfig.none());
  private timeoutId: number | undefined = undefined;
  private lastContactOnline: boolean = true;
  private disposed: boolean = false;

  constructor(clock: ClockPort, timer: VmTimerPort, policy: DoorConfirmationPolicy) {
    this.clock = clock;
    this.timer = timer;
    this.policy = policy;
  }

  getState(): DoorUiState {
    return this.state;
  }

  configure(link: DoorLinkConfig): void {
    if (this.disposed) {
      return;
    }
    this.state = this.copy(DoorStage.IDLE, DoorLockState.UNKNOWN_INITIAL, link, false,
      this.state.lastAckAtMs, this.state.lastContactAtMs, undefined);
  }

  startLock(link: DoorLinkConfig): void {
    if (this.disposed) {
      return;
    }
    this.clearTimeout();
    this.lastContactOnline = true;
    this.state = this.copy(DoorStage.PENDING, DoorLockState.UNKNOWN_INITIAL, link, false,
      this.state.lastAckAtMs, this.state.lastContactAtMs, undefined);
  }

  onResult(execution: ControlExecution): void {
    if (this.disposed || this.state.stage !== DoorStage.PENDING) {
      return;
    }
    const now = this.clock.nowMs();
    if (execution.error !== undefined) {
      this.state = this.copy(DoorStage.FAILED, DoorLockState.UNCONFIRMED, this.state.link, false,
        this.state.lastAckAtMs, this.state.lastContactAtMs,
        ViewModelError.fromError(execution.error, now));
      return;
    }
    if (!execution.ackAccepted ||
      execution.stateVerification === StateVerification.MISMATCH) {
      const error = execution.stateVerification === StateVerification.MISMATCH ?
        AppErrors.of('ACK_STATE_MISMATCH', []) : AppErrors.of('ACK_PROTOCOL_VIOLATION', []);
      this.state = this.copy(DoorStage.FAILED, DoorLockState.UNCONFIRMED, this.state.link, false,
        this.state.lastAckAtMs, this.state.lastContactAtMs, ViewModelError.fromError(error, now));
      return;
    }
    const open = DoorConfirmationTracker.reportedOpen(execution);
    if (open === undefined) {
      this.state = this.copy(DoorStage.UNVERIFIED, DoorLockState.UNKNOWN, this.state.link, false,
        now, this.state.lastContactAtMs, undefined);
      return;
    }
    if (open) {
      this.state = this.copy(DoorStage.FAILED, DoorLockState.OPEN, this.state.link, false,
        now, this.state.lastContactAtMs, ViewModelError.fromError(
          AppErrors.of('ACK_STATE_MISMATCH', []), now));
      return;
    }
    if (this.state.link.mode === DoorLinkMode.GATEWAY_MERGED) {
      this.state = this.copy(DoorStage.SECURED, DoorLockState.SECURED, this.state.link, false,
        now, this.state.lastContactAtMs, undefined);
      return;
    }
    if (this.state.link.mode === DoorLinkMode.CONTACT_SENSOR) {
      this.state = this.copy(DoorStage.WAITING_CONTACT, DoorLockState.UNCONFIRMED,
        this.state.link, false, now, this.state.lastContactAtMs, undefined);
      this.armTimeout();
      return;
    }
    this.state = this.copy(DoorStage.UNVERIFIED, DoorLockState.UNKNOWN, this.state.link, false,
      now, this.state.lastContactAtMs, undefined);
  }

  onContactState(open: boolean, online: boolean): void {
    if (this.disposed) {
      return;
    }
    const now = this.clock.nowMs();
    this.lastContactOnline = online;
    if (this.state.stage === DoorStage.WAITING_CONTACT) {
      if (open) {
        this.clearTimeout();
        this.state = this.copy(DoorStage.UNCONFIRMED, DoorLockState.UNCONFIRMED, this.state.link,
          true, this.state.lastAckAtMs, now, ViewModelError.fromError(
            AppErrors.of('ACK_STATE_MISMATCH', []), now));
      } else if (online) {
        this.clearTimeout();
        this.state = this.copy(DoorStage.SECURED, DoorLockState.SECURED, this.state.link, false,
          this.state.lastAckAtMs, now, undefined);
      }
      return;
    }
    if (this.state.stage === DoorStage.SECURED && open) {
      this.state = this.copy(DoorStage.OPEN, DoorLockState.OPEN, this.state.link, true,
        this.state.lastAckAtMs, now, ViewModelError.fromError(
          AppErrors.of('ACK_STATE_MISMATCH', []), now));
    }
  }

  onContactOffline(): void {
    if (this.disposed) {
      return;
    }
    this.lastContactOnline = false;
  }

  onTimeout(): void {
    if (this.disposed || this.state.stage !== DoorStage.WAITING_CONTACT) {
      return;
    }
    this.timeoutId = undefined;
    const now = this.clock.nowMs();
    if (this.lastContactOnline) {
      this.state = this.copy(DoorStage.UNCONFIRMED, DoorLockState.UNCONFIRMED, this.state.link,
        true, this.state.lastAckAtMs, this.state.lastContactAtMs, ViewModelError.fromError(
          AppErrors.of('ACK_STATE_MISMATCH', []), now));
    } else {
      this.state = this.copy(DoorStage.UNKNOWN, DoorLockState.UNKNOWN, this.state.link, true,
        this.state.lastAckAtMs, this.state.lastContactAtMs, ViewModelError.fromError(
          AppErrors.of('GATEWAY_TIMEOUT', []), now));
    }
  }

  dismissAlert(): void {
    if (this.disposed) {
      return;
    }
    if (this.state.stage !== DoorStage.UNCONFIRMED && this.state.stage !== DoorStage.UNKNOWN &&
      this.state.stage !== DoorStage.UNVERIFIED && this.state.stage !== DoorStage.OPEN) {
      return;
    }
    this.state = this.copy(DoorStage.IDLE, this.state.lockState, this.state.link, false,
      this.state.lastAckAtMs, this.state.lastContactAtMs, this.state.error);
  }

  settleFailed(): void {
    if (this.disposed || this.state.stage !== DoorStage.FAILED) {
      return;
    }
    this.state = this.copy(DoorStage.IDLE, this.state.lockState, this.state.link, false,
      this.state.lastAckAtMs, this.state.lastContactAtMs, this.state.error);
  }

  /**
   * F-02: an unlock ACK is not door-state evidence. OPEN is published only when
   * the execution itself reports `openStatus === true`; a missing report stays
   * UNVERIFIED (previous confirmed lock state preserved) and a contradictory
   * `openStatus === false` is a failed attempt, never OPEN.
   */
  onUnlockResult(execution: ControlExecution): void {
    if (this.disposed) {
      return;
    }
    const now = this.clock.nowMs();
    if (execution.error !== undefined) {
      this.markUnlockFailed(ViewModelError.fromError(execution.error, now));
      return;
    }
    if (!execution.ackAccepted ||
      execution.stateVerification === StateVerification.MISMATCH) {
      const error = execution.stateVerification === StateVerification.MISMATCH ?
        AppErrors.of('ACK_STATE_MISMATCH', []) : AppErrors.of('ACK_PROTOCOL_VIOLATION', []);
      this.markUnlockFailed(ViewModelError.fromError(error, now));
      return;
    }
    const open = DoorConfirmationTracker.reportedOpen(execution);
    if (open === true) {
      this.clearTimeout();
      this.state = this.copy(DoorStage.OPEN, DoorLockState.OPEN, this.state.link, false,
        now, this.state.lastContactAtMs, undefined);
      return;
    }
    if (open === false) {
      this.clearTimeout();
      this.state = this.copy(DoorStage.FAILED, DoorLockState.UNCONFIRMED, this.state.link, false,
        now, this.state.lastContactAtMs, ViewModelError.fromError(
          AppErrors.of('ACK_STATE_MISMATCH', []), now));
      return;
    }
    // Executed, but the door did not report its state: keep the last confirmed
    // lock state and expose the honest UNVERIFIED stage.
    this.clearTimeout();
    this.state = this.copy(DoorStage.UNVERIFIED, this.state.lockState, this.state.link, false,
      now, this.state.lastContactAtMs, undefined);
  }

  markUnlockFailed(error: ViewModelError): void {
    if (this.disposed) {
      return;
    }
    this.state = this.copy(DoorStage.FAILED, DoorLockState.UNKNOWN, this.state.link, false,
      this.state.lastAckAtMs, this.state.lastContactAtMs, error);
  }

  reset(): void {
    this.clearTimeout();
    this.state = DoorUiState.initial(this.state.link);
  }

  dispose(): void {
    this.disposed = true;
    this.clearTimeout();
  }

  static reportedOpen(execution: ControlExecution): boolean | undefined {
    if (execution.apply !== undefined && execution.apply.record !== undefined) {
      return execution.apply.record.state.snapshot.openStatus;
    }
    if (execution.lan !== undefined) {
      if (execution.lan.apply !== undefined && execution.lan.apply.record !== undefined) {
        return execution.lan.apply.record.state.snapshot.openStatus;
      }
      if (execution.lan.outcome !== undefined &&
        execution.lan.outcome.reportedState !== undefined) {
        return execution.lan.outcome.reportedState.openStatus;
      }
    }
    if (execution.cloud !== undefined && execution.cloud.verdict.reportedState !== undefined) {
      return execution.cloud.verdict.reportedState.openStatus;
    }
    return undefined;
  }

  private armTimeout(): void {
    this.clearTimeout();
    this.timeoutId = this.timer.setTimer(this.policy.confirmTimeoutMs, (): void => {
      this.onTimeout();
    });
  }

  private clearTimeout(): void {
    if (this.timeoutId !== undefined) {
      this.timer.clearTimer(this.timeoutId);
      this.timeoutId = undefined;
    }
  }

  private copy(stage: DoorStage, lockState: DoorLockState, link: DoorLinkConfig,
    alertActive: boolean, lastAckAtMs: number | undefined, lastContactAtMs: number | undefined,
    error: ViewModelError | undefined): DoorUiState {
    return new DoorUiState(stage, lockState, link, alertActive, this.state.revision + 1,
      lastAckAtMs, lastContactAtMs, error);
  }
}
