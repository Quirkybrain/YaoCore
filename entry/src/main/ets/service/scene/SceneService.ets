/*
 * YaoCore C-11 SceneService.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §6.1.4, §6.2, §6.3
 *
 * Scene CRUD + serial execution orchestration. Execution itself lives in
 * SceneExecutor; this service owns run ids, cancellation handles, CRUD
 * validation and event fan-out. No platform import and no direct network.
 *
 * O-1: SceneRepository operations are gate-serialized. deleteScene uses one
 * top-level RDB transaction; run() does not hold a transaction across network
 * calls (each device ACK application is its own short transaction).
 */
import { AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { UuidUtil } from '../../common/utils/UuidUtil';
import type { CancellationToken, ClockPort, IdPort, LoggerPort, MetricsPort } from '../../common/types/Ports';
import { Scene, SceneAction } from '../../model/FamilyModels';
import type { RdbStore, RdbTransaction } from '../storage/RdbStore';
import { SceneRepository } from '../../repository/SceneRepository';
import { DeviceRepository } from '../../repository/DeviceRepository';
import { DomainOperationGate } from '../../repository/DomainOperationGate';
import type { DeviceControlPort } from '../../repository/DomainPorts';
import type { GatewayRoutePort } from '../../repository/GatewayPorts';
import {
  SceneExecutionEvent,
  SceneExecutionEventType,
  SceneExecutionPolicy,
  SceneExecutionProgress,
  SceneExecutionResult,
  SceneRunState,
  SceneStepResult,
  SceneStepState
} from '../../repository/DomainModels';
import { RunCancellation, SceneExecutor } from './SceneExecutor';
import type { SceneTimerPort } from './SceneTimerPort';
import { SceneValidation } from './SceneValidation';

export class SceneInput {
  readonly familyId: string;
  readonly sceneName: string;
  readonly icon: string;
  readonly actions: ReadonlyArray<SceneAction>;
  readonly isEnabled: boolean;

  constructor(familyId: string, sceneName: string, icon: string,
    actions: ReadonlyArray<SceneAction>, isEnabled: boolean = true) {
    this.familyId = familyId;
    this.sceneName = sceneName;
    this.icon = icon;
    this.actions = actions;
    this.isEnabled = isEnabled;
  }
}

export class SceneService {
  private readonly scenes: SceneRepository;
  private readonly routes: GatewayRoutePort;
  private readonly clock: ClockPort;
  private readonly ids: IdPort;
  private readonly logger: LoggerPort;
  private readonly metrics: MetricsPort;
  private readonly rdb?: RdbStore;
  private readonly gate?: DomainOperationGate;
  private readonly executor: SceneExecutor;
  private readonly listeners: Array<(event: SceneExecutionEvent) => void> = [];
  private readonly runs: Map<string, RunCancellation> = new Map<string, RunCancellation>();

  constructor(scenes: SceneRepository, devices: DeviceRepository, control: DeviceControlPort,
    routes: GatewayRoutePort, clock: ClockPort, timer: SceneTimerPort, ids: IdPort,
    logger: LoggerPort, metrics: MetricsPort, rdb?: RdbStore, gate?: DomainOperationGate) {
    this.scenes = scenes;
    this.routes = routes;
    this.clock = clock;
    this.ids = ids;
    this.logger = logger;
    this.metrics = metrics;
    this.rdb = rdb;
    this.gate = gate;
    this.executor = new SceneExecutor(control, devices, routes, clock, timer, logger);
  }

  async initialize(): Promise<void> {
    await this.scenes.initialize();
  }

  async listScenes(familyId: string): Promise<ReadonlyArray<Scene>> {
    return this.scenes.listScenes(familyId);
  }

  async getScene(sceneId: string): Promise<Scene | undefined> {
    return this.scenes.getScene(sceneId);
  }

  async createScene(input: SceneInput): Promise<Scene> {
    await this.validateInput(input);
    const scene = new Scene(UuidUtil.newUuid(this.ids), input.familyId,
      SceneService.sceneName(input.sceneName), SceneService.icon(input.icon),
      input.actions, input.isEnabled);
    await this.scenes.putScene(scene);
    return scene;
  }

  async updateScene(sceneId: string, input: SceneInput): Promise<Scene> {
    const existing = await this.scenes.getScene(sceneId);
    if (existing === undefined) {
      throw AppErrors.of('SCENE_NOT_FOUND', []);
    }
    await this.validateInput(input);
    if (existing.familyId !== input.familyId) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
    }
    const scene = new Scene(existing.sceneId, input.familyId,
      SceneService.sceneName(input.sceneName), SceneService.icon(input.icon),
      input.actions, input.isEnabled);
    await this.scenes.putScene(scene);
    return scene;
  }

  async deleteScene(sceneId: string): Promise<void> {
    const existing = await this.scenes.getScene(sceneId);
    if (existing === undefined) {
      throw AppErrors.of('SCENE_NOT_FOUND', []);
    }
    if (this.rdb === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'rdb')]);
    }
    const rdb = this.rdb;
    const operation = (): Promise<void> => rdb.transaction<void>(
      async (tx: RdbTransaction): Promise<void> => {
        await this.scenes.deleteScene(tx, sceneId);
      });
    if (this.gate === undefined) {
      await operation();
    } else {
      await this.gate.run(operation);
    }
  }

  async run(sceneId: string, listener?: (progress: SceneExecutionProgress) => void,
    cancellation?: CancellationToken): Promise<SceneExecutionResult> {
    const scene = await this.scenes.getScene(sceneId);
    if (scene === undefined) {
      throw AppErrors.of('SCENE_NOT_FOUND', []);
    }
    if (!scene.isEnabled) {
      throw AppErrors.of('SCENE_DISABLED', []);
    }
    if (scene.actions.length === 0) {
      throw AppErrors.of('SCENE_EMPTY', []);
    }
    const runId = this.ids.newId();
    const runCancellation = new RunCancellation();
    if (cancellation !== undefined) {
      cancellation.onCancel((): void => {
        runCancellation.cancel();
      });
      if (cancellation.cancelled) {
        runCancellation.cancel();
      }
    }
    this.runs.set(runId, runCancellation);
    this.logger.debug('SceneService', 'scene_run_started',
      [new NameValue('sceneId', scene.sceneId), new NameValue('runId', runId)]);
    const policy = SceneExecutionPolicy.defaults();
    const startedAt = this.clock.nowMs();
    const initialSteps: SceneStepResult[] = [];
    for (let index = 0; index < scene.actions.length; index++) {
      initialSteps.push(new SceneStepResult(index, scene.actions[index], SceneStepState.PENDING));
    }
    this.emit(new SceneExecutionEvent(SceneExecutionEventType.STARTED,
      new SceneExecutionProgress(runId, scene.sceneId, SceneRunState.PREFLIGHT, -1,
        initialSteps, 0, 0)));
    const stepStates: Map<number, SceneStepState> = new Map<number, SceneStepState>();
    const wrapped = (progress: SceneExecutionProgress): void => {
      if (listener !== undefined) {
        listener(progress);
      }
      this.emitProgressEvents(progress, stepStates);
    };
    try {
      const result = await this.executor.execute(scene, runId, policy, wrapped,
        runCancellation);
      this.metrics.record('scene_run_ms', this.clock.nowMs() - startedAt,
        [new NameValue('state', result.state)]);
      return result;
    } finally {
      this.runs.delete(runId);
    }
  }

  async cancel(runId: string): Promise<void> {
    const run = this.runs.get(runId);
    if (run !== undefined) {
      run.cancel();
    }
  }

  subscribe(listener: (event: SceneExecutionEvent) => void): () => void {
    this.listeners.push(listener);
    return (): void => {
      const index = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    };
  }

  dispose(): void {
    this.listeners.splice(0, this.listeners.length);
    this.runs.forEach((run: RunCancellation): void => {
      run.cancel();
    });
    this.runs.clear();
  }

  // ---- Internals ----------------------------------------------------------

  private async validateInput(input: SceneInput): Promise<void> {
    SceneService.sceneName(input.sceneName);
    SceneService.icon(input.icon);
    if (input.actions.length === 0) {
      throw AppErrors.of('SCENE_EMPTY', []);
    }
    for (let index = 0; index < input.actions.length; index++) {
      const action = input.actions[index];
      const shapeError = SceneValidation.actionShapeError(action);
      if (shapeError !== undefined) {
        throw shapeError;
      }
      const route = await this.routes.getRoute(action.gatewayId);
      if (route === undefined || route.familyId !== input.familyId) {
        throw AppErrors.of('SCENE_REFERENCE_INVALID',
          [new NameValue('index', String(index))]);
      }
    }
  }

  private emitProgressEvents(progress: SceneExecutionProgress,
    stepStates: Map<number, SceneStepState>): void {
    if (progress.currentIndex >= 0 && progress.currentIndex < progress.steps.length) {
      const step = progress.steps[progress.currentIndex];
      const previous = stepStates.get(progress.currentIndex);
      if (previous !== step.state) {
        stepStates.set(progress.currentIndex, step.state);
        if (step.state === SceneStepState.RUNNING) {
          this.emit(new SceneExecutionEvent(SceneExecutionEventType.STEP_STARTED, progress));
        } else if (step.state === SceneStepState.SUCCEEDED) {
          this.emit(new SceneExecutionEvent(SceneExecutionEventType.STEP_SUCCEEDED, progress));
        } else if (step.state === SceneStepState.FAILED) {
          this.emit(new SceneExecutionEvent(SceneExecutionEventType.STEP_FAILED, progress));
        }
      }
    }
    if (progress.state === SceneRunState.SUCCEEDED ||
      progress.state === SceneRunState.PARTIAL_FAILED ||
      progress.state === SceneRunState.FAILED) {
      this.emit(new SceneExecutionEvent(SceneExecutionEventType.FINISHED, progress));
    } else if (progress.state === SceneRunState.CANCELLED) {
      this.emit(new SceneExecutionEvent(SceneExecutionEventType.CANCELLED, progress));
    }
  }

  private emit(event: SceneExecutionEvent): void {
    for (let index = 0; index < this.listeners.length; index++) {
      this.listeners[index](event);
    }
  }

  private static sceneName(value: string): string {
    const trimmed = value.trim();
    if (trimmed.length < 1 || trimmed.length > 31) {
      throw AppErrors.of('SCENE_NAME_INVALID', []);
    }
    return trimmed;
  }

  private static icon(value: string): string {
    const trimmed = value.trim();
    if (trimmed.length < 1 || trimmed.length > 63) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'icon');
    }
    return trimmed;
  }
}
