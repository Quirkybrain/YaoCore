/*
 * YaoCore C-22 SceneViewModel.
 * Producer: agent:implementation-engineer | Task: T-16 / wp-060-vm
 * Contract: DES-B §11.1.3, §11.3.4; FR-SCN-001; UIUX §4.6
 *
 * Progress is passed through step by step. A PARTIAL_FAILED result keeps its
 * explicit `noRollbackNotice`; SKIPPED steps are never rendered as success. The
 * VM does not retry automatically.
 */
import { AppErrors } from '../common/types/AppError';
import { NameValue } from '../common/types/NameValue';
import type { LoggerPort } from '../common/types/Ports';
import type { Scene } from '../model/FamilyModels';
import {
  SceneExecutionProgress,
  SceneExecutionResult
} from '../repository/DomainModels';
import type { SceneInput } from '../service/scene/SceneService';
import {
  LoadPhase,
  ViewModelError,
  ViewModelSupport
} from './core/ViewModelCore';
import type { ViewModelBase } from './core/ViewModelCore';
import { I18nService } from '../service/i18n/I18nService';
import { SceneService } from '../service/scene/SceneService';
import { DeviceRepository } from '../repository/DeviceRepository';

const TAG: string = 'SceneViewModel';

export class SceneViewState {
  readonly phase: LoadPhase;
  readonly scenes: ReadonlyArray<Scene>;
  readonly execution?: SceneExecutionProgress;
  readonly lastResult?: SceneExecutionResult;
  readonly runningSceneId?: string;
  readonly error?: ViewModelError;
  readonly revision: number;

  constructor(phase: LoadPhase, scenes: ReadonlyArray<Scene>, revision: number,
    execution?: SceneExecutionProgress, lastResult?: SceneExecutionResult,
    runningSceneId?: string, error?: ViewModelError) {
    this.phase = phase;
    this.scenes = scenes;
    this.execution = execution;
    this.lastResult = lastResult;
    this.runningSceneId = runningSceneId;
    this.error = error;
    this.revision = revision;
  }
}

export class SceneViewModel implements ViewModelBase<SceneViewState> {
  private readonly scenes: SceneService;
  private readonly devices: DeviceRepository;
  private readonly i18n: I18nService;
  private readonly logger: LoggerPort;

  private state: SceneViewState;
  private listeners: Array<(state: SceneViewState) => void> = [];
  private familyId: string = '';
  private revision: number = 0;
  private disposed: boolean = false;
  private activeRunId?: string = undefined;

  constructor(scenes: SceneService, devices: DeviceRepository, i18n: I18nService,
    logger: LoggerPort) {
    this.scenes = scenes;
    this.devices = devices;
    this.i18n = i18n;
    this.logger = logger;
    this.state = new SceneViewState(LoadPhase.IDLE, [], 0);
  }

  getState(): SceneViewState {
    return this.state;
  }

  subscribe(listener: (state: SceneViewState) => void): () => void {
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
    this.publish(new SceneViewState(LoadPhase.LOADING, this.state.scenes,
      this.revision + 1));
    await this.refresh();
  }

  async refresh(): Promise<void> {
    if (this.disposed) {
      return;
    }
    try {
      const scenes = await this.scenes.listScenes(this.familyId);
      this.publish(new SceneViewState(LoadPhase.READY, scenes, this.revision + 1,
        this.state.execution, this.state.lastResult, this.state.runningSceneId,
        this.state.error));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async run(sceneId: string): Promise<SceneExecutionResult> {
    if (this.state.runningSceneId !== undefined) {
      const error = AppErrors.of('SCENE_RUN_IN_PROGRESS', [
        new NameValue('sceneId', this.state.runningSceneId)]);
      this.fail(error);
      throw error;
    }
    this.activeRunId = undefined;
    this.publish(new SceneViewState(LoadPhase.READY, this.state.scenes, this.revision + 1,
      this.state.execution, this.state.lastResult, sceneId, undefined));
    try {
      const result = await this.scenes.run(sceneId,
        (progress: SceneExecutionProgress): void => {
          if (this.disposed) {
            return;
          }
          this.activeRunId = progress.runId;
          this.publish(new SceneViewState(this.state.phase, this.state.scenes,
            this.revision + 1, progress, this.state.lastResult, progress.sceneId,
            this.state.error));
        });
      this.activeRunId = undefined;
      this.publish(new SceneViewState(LoadPhase.READY, this.state.scenes,
        this.revision + 1, this.state.execution, result, undefined, undefined));
      return result;
    } catch (error) {
      this.activeRunId = undefined;
      const appError = ViewModelSupport.asAppError(error as Object);
      const mapped = ViewModelError.fromError(appError, 0);
      this.logger.warn(TAG, 'view_model_error', [new NameValue('code', appError.code)]);
      this.publish(new SceneViewState(this.state.phase, this.state.scenes,
        this.revision + 1, this.state.execution, this.state.lastResult, undefined, mapped));
      throw appError;
    }
  }

  async cancel(): Promise<void> {
    const runId = this.activeRunId === undefined ? this.state.runningSceneId : this.activeRunId;
    if (runId === undefined) {
      return;
    }
    try {
      await this.scenes.cancel(runId);
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async createScene(input: SceneInput): Promise<Scene> {
    try {
      const scene = await this.scenes.createScene(input);
      await this.refresh();
      return scene;
    } catch (error) {
      this.fail(error as Object);
      throw error as Error;
    }
  }

  async updateScene(sceneId: string, input: SceneInput): Promise<Scene> {
    try {
      const scene = await this.scenes.updateScene(sceneId, input);
      await this.refresh();
      return scene;
    } catch (error) {
      this.fail(error as Object);
      throw error as Error;
    }
  }

  async deleteScene(sceneId: string): Promise<void> {
    try {
      await this.scenes.deleteScene(sceneId);
      await this.refresh();
    } catch (error) {
      this.fail(error as Object);
    }
  }

  clearResult(): void {
    this.publish(new SceneViewState(this.state.phase, this.state.scenes,
      this.revision + 1, undefined, undefined, this.state.runningSceneId,
      this.state.error));
  }

  translateError(error: ViewModelError | undefined): string {
    return error === undefined ? '' : this.i18n.t(error.i18nKey);
  }

  dispose(): void {
    this.disposed = true;
    this.listeners.splice(0, this.listeners.length);
  }

  private fail(error: Object): void {
    const mapped = ViewModelError.fromError(ViewModelSupport.asAppError(error), 0);
    this.logger.warn(TAG, 'view_model_error', [new NameValue('code', mapped.error.code)]);
    this.publish(new SceneViewState(this.state.phase, this.state.scenes,
      this.revision + 1, this.state.execution, this.state.lastResult,
      this.state.runningSceneId, mapped));
  }

  private publish(next: SceneViewState): void {
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
