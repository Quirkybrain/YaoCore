/*
 * YaoCore C-11 scene execution/read models.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-B §2.1/D-12 P2; moved out of
 * repository/DomainModels.ets so pages/components can import read-only DTOs
 * without a repository dependency.
 * Contract: DES-B §6.1.1 (EXT-DES-B-10..12)
 *
 * Pure values; no platform API.
 */
import type { AppError } from '../common/types/AppError';
import type { StateVerification } from './ControlModels';
import type { ControlOutcome } from './ControlModels';
import { SceneAction } from './FamilyModels';

export enum SceneRunState {
  IDLE = 'IDLE',
  PREFLIGHT = 'PREFLIGHT',
  RUNNING = 'RUNNING',
  SUCCEEDED = 'SUCCEEDED',
  PARTIAL_FAILED = 'PARTIAL_FAILED',
  FAILED = 'FAILED',
  CANCELLED = 'CANCELLED'
}

export enum SceneStepState {
  PENDING = 'PENDING',
  RUNNING = 'RUNNING',
  SUCCEEDED = 'SUCCEEDED',
  FAILED = 'FAILED',
  SKIPPED = 'SKIPPED',
  CANCELLED = 'CANCELLED'
}

export class SceneStepResult {
  readonly index: number;
  readonly action: SceneAction;
  readonly state: SceneStepState;
  readonly startedAtMs?: number;
  readonly endedAtMs?: number;
  readonly outcome?: ControlOutcome;
  readonly stateVerification?: StateVerification;
  readonly error?: AppError;

  constructor(index: number, action: SceneAction, state: SceneStepState,
    startedAtMs?: number, endedAtMs?: number, outcome?: ControlOutcome,
    stateVerification?: StateVerification, error?: AppError) {
    this.index = index;
    this.action = action;
    this.state = state;
    this.startedAtMs = startedAtMs;
    this.endedAtMs = endedAtMs;
    this.outcome = outcome;
    this.stateVerification = stateVerification;
    this.error = error;
  }

  withState(state: SceneStepState, startedAtMs?: number, endedAtMs?: number,
    outcome?: ControlOutcome, stateVerification?: StateVerification,
    error?: AppError): SceneStepResult {
    return new SceneStepResult(this.index, this.action, state,
      startedAtMs === undefined ? this.startedAtMs : startedAtMs,
      endedAtMs === undefined ? this.endedAtMs : endedAtMs,
      outcome === undefined ? this.outcome : outcome,
      stateVerification === undefined ? this.stateVerification : stateVerification,
      error === undefined ? this.error : error);
  }
}

export class SceneExecutionResult {
  readonly runId: string;
  readonly sceneId: string;
  readonly sceneName: string;
  readonly state: SceneRunState;
  readonly steps: ReadonlyArray<SceneStepResult>;
  readonly startedAtMs: number;
  readonly endedAtMs?: number;
  readonly executedCount: number;
  readonly succeededCount: number;
  readonly failedStepIndex?: number;
  readonly error?: AppError;
  readonly noRollbackNotice: boolean;

  constructor(runId: string, sceneId: string, sceneName: string, state: SceneRunState,
    steps: ReadonlyArray<SceneStepResult>, startedAtMs: number, executedCount: number,
    succeededCount: number, failedStepIndex?: number, endedAtMs?: number, error?: AppError) {
    this.runId = runId;
    this.sceneId = sceneId;
    this.sceneName = sceneName;
    this.state = state;
    this.steps = steps;
    this.startedAtMs = startedAtMs;
    this.endedAtMs = endedAtMs;
    this.executedCount = executedCount;
    this.succeededCount = succeededCount;
    this.failedStepIndex = failedStepIndex;
    this.error = error;
    // FR-SCN-001 / UIUX §4.6: executed steps are never automatically rolled back.
    this.noRollbackNotice = true;
  }
}

export class SceneExecutionProgress {
  readonly runId: string;
  readonly sceneId: string;
  readonly state: SceneRunState;
  readonly currentIndex: number;
  readonly steps: ReadonlyArray<SceneStepResult>;
  readonly executedCount: number;
  readonly succeededCount: number;

  constructor(runId: string, sceneId: string, state: SceneRunState, currentIndex: number,
    steps: ReadonlyArray<SceneStepResult>, executedCount: number, succeededCount: number) {
    this.runId = runId;
    this.sceneId = sceneId;
    this.state = state;
    this.currentIndex = currentIndex;
    this.steps = steps;
    this.executedCount = executedCount;
    this.succeededCount = succeededCount;
  }
}

export enum SceneExecutionEventType {
  STARTED = 'STARTED',
  STEP_STARTED = 'STEP_STARTED',
  STEP_SUCCEEDED = 'STEP_SUCCEEDED',
  STEP_FAILED = 'STEP_FAILED',
  FINISHED = 'FINISHED',
  CANCELLED = 'CANCELLED'
}

export class SceneExecutionEvent {
  readonly type: SceneExecutionEventType;
  readonly progress: SceneExecutionProgress;

  constructor(type: SceneExecutionEventType, progress: SceneExecutionProgress) {
    this.type = type;
    this.progress = progress;
  }
}

export class SceneExecutionPolicy {
  readonly stepTimeoutMs: number;
  readonly totalTimeoutMs: number;
  readonly allowCancelBetweenSteps: boolean;

  constructor(stepTimeoutMs: number = 8000, totalTimeoutMs: number = 60000,
    allowCancelBetweenSteps: boolean = true) {
    this.stepTimeoutMs = stepTimeoutMs;
    this.totalTimeoutMs = totalTimeoutMs;
    this.allowCancelBetweenSteps = allowCancelBetweenSteps;
  }

  static defaults(): SceneExecutionPolicy {
    return new SceneExecutionPolicy(8000, 60000, true);
  }
}
