/*
 * YaoCore C-21..C-23 ViewModel shared contract types.
 * Producer: agent:implementation-engineer | Task: T-15/T-16 / wp-060-vm
 * Contract: DES-B §10.1.1, §11.1, §12.1; D-018; DES-B §10.4/§11.4/§12.4
 *
 * Pure presentation logic only: no @ohos import, no ArkUI decorator and no
 * direct repository/transport instantiation. View models expose immutable
 * state snapshots and `subscribe()` so host tests can drive them with fake
 * clocks, timers, services and ports.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { DeviceAction } from '../../common/constants/DeviceConstants';
import type { CommandValue } from '../../common/utils/JsonAtom';
import type { ClockPort } from '../../common/types/Ports';
import type { LoggerPort } from '../../contracts/Ports';
import { DeviceKey } from '../../model/DeviceKey';
import { TransportProfile } from '../../model/DeviceTypes';
import type { ControlOutcome, DeviceControlCommand } from '../../model/ControlModels';
import { StateVerification } from '../../model/ControlModels';
import type { DeviceCommandExecution } from '../../model/DeviceRecord';
import type { ControlApplyResult } from '../../model/DeviceRecord';
import type { ControlExecution } from '../../model/ControlExecution';

import type { CloudControlOutcome } from '../../model/CloudControlModels';
import { ErrorI18nMapper } from '../../service/i18n/ErrorI18nMapper';
import { LocaleChangedEvent, LocaleMode, SupportedLocale } from '../../model/I18nModels';

export enum LoadPhase {
  IDLE = 'IDLE',
  LOADING = 'LOADING',
  READY = 'READY',
  ERROR = 'ERROR'
}

export class ViewModelError {
  readonly error: AppError;
  readonly i18nKey: string;
  readonly atMs: number;

  constructor(error: AppError, i18nKey: string, atMs: number) {
    this.error = error;
    this.i18nKey = i18nKey;
    this.atMs = atMs;
  }

  static fromError(error: AppError, atMs: number): ViewModelError {
    return new ViewModelError(error, ErrorI18nMapper.appKey(error).key, atMs);
  }
}

export enum DeviceFilterKind {
  ALL = 'ALL',
  ROOM = 'ROOM',
  UNASSIGNED = 'UNASSIGNED'
}

export class DeviceFilter {
  readonly kind: DeviceFilterKind;
  readonly roomId?: string;

  private constructor(kind: DeviceFilterKind, roomId?: string) {
    this.kind = kind;
    this.roomId = roomId;
  }

  static all(): DeviceFilter {
    return new DeviceFilter(DeviceFilterKind.ALL);
  }

  static room(roomId: string): DeviceFilter {
    if (roomId.length === 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'roomId')]);
    }
    return new DeviceFilter(DeviceFilterKind.ROOM, roomId);
  }

  static unassigned(): DeviceFilter {
    return new DeviceFilter(DeviceFilterKind.UNASSIGNED);
  }
}

export enum GatewayLinkState {
  ONLINE = 'ONLINE',
  OFFLINE = 'OFFLINE',
  BLOCKED = 'BLOCKED',
  UNKNOWN = 'UNKNOWN'
}

export enum CloudLinkState {
  NOT_CONFIGURED = 'NOT_CONFIGURED',
  CONFIGURED = 'CONFIGURED',
  TOKEN_EXPIRED = 'TOKEN_EXPIRED',
  TOKEN_INVALID = 'TOKEN_INVALID',
  UNAVAILABLE = 'UNAVAILABLE',
  UNKNOWN = 'UNKNOWN'
}

export class GatewayStatus {
  readonly gatewayId: string;
  readonly gatewayName: string;
  readonly lan: GatewayLinkState;
  readonly cloud: CloudLinkState;
  readonly profile: TransportProfile;
  readonly latencyMs?: number;
  readonly lastSeenAt?: string;
  readonly warningKey?: string;

  constructor(gatewayId: string, gatewayName: string, lan: GatewayLinkState,
    cloud: CloudLinkState, profile: TransportProfile, latencyMs?: number,
    lastSeenAt?: string, warningKey?: string) {
    this.gatewayId = gatewayId;
    this.gatewayName = gatewayName;
    this.lan = lan;
    this.cloud = cloud;
    this.profile = profile;
    this.latencyMs = latencyMs;
    this.lastSeenAt = lastSeenAt;
    this.warningKey = warningKey;
  }
}

export class EnvironmentSummary {
  readonly temperature?: number;
  readonly humidity?: number;
  readonly presence?: boolean;
  readonly updatedAt?: string;
  readonly stateSource?: string;
  readonly known: boolean;

  constructor(temperature: number | undefined, humidity: number | undefined,
    presence: boolean | undefined, updatedAt: string | undefined,
    stateSource: string | undefined) {
    this.temperature = temperature;
    this.humidity = humidity;
    this.presence = presence;
    this.updatedAt = updatedAt;
    this.stateSource = stateSource;
    this.known = temperature !== undefined || humidity !== undefined || presence !== undefined;
  }

  static empty(): EnvironmentSummary {
    return new EnvironmentSummary(undefined, undefined, undefined, undefined, undefined);
  }
}

export enum ControlPhase {
  IDLE = 'IDLE',
  PENDING = 'PENDING',
  COMMITTED = 'COMMITTED',
  REVERT = 'REVERT'
}

export class ControlUiState {
  readonly key: DeviceKey;
  readonly action: DeviceAction;
  readonly phase: ControlPhase;
  readonly confirmedValue?: CommandValue;
  readonly optimisticValue?: CommandValue;
  readonly pendingSinceMs?: number;
  readonly lastOutcome?: ControlOutcome;
  readonly lastExecution?: ControlExecution;
  readonly lastError?: ViewModelError;
  readonly revision: number;

  constructor(key: DeviceKey, action: DeviceAction, phase: ControlPhase, revision: number,
    confirmedValue?: CommandValue, optimisticValue?: CommandValue,
    pendingSinceMs?: number, lastOutcome?: ControlOutcome, lastExecution?: ControlExecution,
    lastError?: ViewModelError) {
    this.key = key;
    this.action = action;
    this.phase = phase;
    this.confirmedValue = confirmedValue;
    this.optimisticValue = optimisticValue;
    this.pendingSinceMs = pendingSinceMs;
    this.lastOutcome = lastOutcome;
    this.lastExecution = lastExecution;
    this.lastError = lastError;
    this.revision = revision;
  }

  static idle(key: DeviceKey, revision: number, confirmedValue?: CommandValue): ControlUiState {
    return new ControlUiState(key, DeviceAction.PING, ControlPhase.IDLE, revision,
      confirmedValue);
  }
}

/**
 * Callback timer seam (DES-B §23.1 EXT-DES-B-33). Production wires
 * setTimeout/clearTimeout in C-28; host tests use a deterministic fake timer.
 * It is a VM-local seam, not a contracts port, and intentionally separate from
 * the C-15 cloud TimerPort (sleep/cancel) and the C-11 SceneTimerPort (delay),
 * neither of which can schedule a reentrant callback.
 */
export interface VmTimerPort {
  setTimer(delayMs: number, callback: () => void): number;
  clearTimer(timerId: number): void;
}

/** Session-gate seam owned by C-28 (Index/SessionGateView). */
export interface AppContextPort {
  refreshSessionGate(): void;
  lock(): void;
}

export interface I18nTextPort {
  t(key: string): string;
}

/** Minimal i18n surface consumed by SettingsViewModel; C-14 satisfies it. */
export interface I18nSettingsPort extends I18nTextPort {
  getLocale(): SupportedLocale;
  getLocaleMode(): LocaleMode;
  setLocaleMode(mode: LocaleMode): Promise<void>;
  onLocaleChanged(listener: (event: LocaleChangedEvent) => void): () => void;
}

export interface ViewModelBase<T> {
  getState(): T;
  subscribe(listener: (state: T) => void): () => void;
  dispose(): void;
}

/** Bounded helper surface shared by view models. */
export class ViewModelSupport {
  static asAppError(error: Object): AppError {
    if (error instanceof AppError) {
      return error as AppError;
    }
    return AppErrors.of('INTERNAL_ERROR', []);
  }

  static codeOf(error: Object): string {
    if (error instanceof AppError) {
      return (error as AppError).code;
    }
    return 'INTERNAL_ERROR';
  }

  static viewError(error: Object, clock: ClockPort): ViewModelError {
    return ViewModelError.fromError(ViewModelSupport.asAppError(error), clock.nowMs());
  }

  static keyId(key: DeviceKey): string {
    return key.globalId();
  }

  static isSameKey(left: DeviceKey, right: DeviceKey): boolean {
    return left.gatewayId === right.gatewayId && left.deviceId === right.deviceId;
  }

  static errorCodeForControl(errorCode: string): string {
    if (errorCode.length === 0) {
      return 'ACK_PROTOCOL_VIOLATION';
    }
    return errorCode;
  }
}

export class ViewModelLogger {
  private readonly inner: LoggerPort;

  constructor(inner: LoggerPort) {
    this.inner = inner;
  }

  debug(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
    this.inner.debug(tag, message, fields);
  }

  warn(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
    this.inner.warn(tag, message, fields);
  }

  error(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
    this.inner.error(tag, message, fields);
  }
}
