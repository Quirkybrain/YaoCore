/*
 * YaoCore C-26 ScenePage.
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §15.1.4, §15.2/§15.3; FR-SCN-001; UIUX §4.6
 *
 * The step overlay renders only C-11 SceneExecutionProgress/lastResult. A
 * PARTIAL_FAILED/FAILED/CANCELLED run with executed steps always shows the
 * no-rollback notice and never reports success.
 */
import type { I18nService } from '../service/i18n/I18nService';
import { AppContext } from '../app/AppContext';
import type { NavigationService } from '../app/NavigationService';
import type { PageVmFactoryPort } from '../app/PageVmFactory';
import {
  AppColors,
  AppRadius,
  AppSpacing,
  AppTypography
} from '../common/theme/AppTheme';
import type { Scene } from '../model/FamilyModels';
import { NameValue } from '../common/types/NameValue';
import { I18nParams } from '../service/i18n/I18nModels';
import type {
  SceneExecutionProgress,
  SceneExecutionResult,
  SceneStepResult
} from '../repository/DomainModels';
import type { SceneRunState } from '../repository/DomainModels';
import { LoadPhase } from '../viewmodel/core/ViewModelCore';
import { SceneViewState, SceneViewModel } from '../viewmodel/SceneViewModel';
import {
  AppDialog,
  EmptyState,
  ErrorState,
  LoadingSkeleton,
  PrimaryButton,
  SectionHeader
} from '../components/CommonControls';
import { SceneCard } from '../components/DeviceCards';
import { UiMapping } from '../components/support/UiMapping';

@Component
export struct ScenePage {
  @Require appContext: AppContext;
  @Require i18n: I18nService;
  @Require navigation: NavigationService;
  @Require vmFactory: PageVmFactoryPort;
  @Prop localeRevision: number = 0;
  @Prop motionEnabled: boolean = true;
  @State scenes: SceneViewState = new SceneViewState(LoadPhase.IDLE, [], 0);
  @State showOverlay: boolean = false;
  @State editNotice: boolean = false;
  @State busy: boolean = false;
  @State canExecuteScene: boolean = false;

  private sceneVm: SceneViewModel | undefined = undefined;
  private lastShownRunId: string = '';
  private unsubscribeScenes: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    const vm = this.vmFactory.createSceneViewModel();
    this.sceneVm = vm;
    // F-02: capability comes from the same C-12 policy port used by the
    // service; GUEST/unlocked-without-policy renders a disabled entry.
    this.canExecuteScene = vm.canExecuteScene();
    this.unsubscribeScenes = vm.subscribe((state: SceneViewState): void => {
      this.scenes = state;
      let runId = '';
      if (state.execution !== undefined) {
        runId = state.execution.runId;
      } else if (state.lastResult !== undefined) {
        runId = state.lastResult.runId;
      }
      if (runId.length > 0 && runId !== this.lastShownRunId) {
        this.lastShownRunId = runId;
        this.showOverlay = true;
      }
    });
    const familyId = this.appContext.activeFamilyId;
    if (familyId !== undefined) {
      vm.initialize(familyId).catch((): void => undefined);
    }
  }

  aboutToDisappear(): void {
    if (this.unsubscribeScenes !== undefined) {
      this.unsubscribeScenes();
      this.unsubscribeScenes = undefined;
    }
    if (this.sceneVm !== undefined) {
      this.sceneVm.dispose();
      this.sceneVm = undefined;
    }
  }

  private runScene(scene: Scene): void {
    const vm = this.sceneVm;
    if (vm === undefined || this.busy || !this.canExecuteScene) {
      return;
    }
    this.busy = true;
    this.showOverlay = true;
    vm.run(scene.sceneId).then((): void => {
      this.busy = false;
    }).catch((): void => {
      this.busy = false;
    });
  }

  private cancelRun(): void {
    const vm = this.sceneVm;
    if (vm === undefined) {
      return;
    }
    vm.cancel().catch((): void => undefined);
  }

  private progress(): SceneExecutionProgress | undefined {
    return this.scenes.execution;
  }

  private result(): SceneExecutionResult | undefined {
    return this.scenes.lastResult;
  }

  private steps(): ReadonlyArray<SceneStepResult> {
    if (this.progress() !== undefined) {
      return (this.progress() as SceneExecutionProgress).steps;
    }
    if (this.result() !== undefined) {
      return (this.result() as SceneExecutionResult).steps;
    }
    return [];
  }

  private runState(): SceneRunState | undefined {
    if (this.progress() !== undefined) {
      return (this.progress() as SceneExecutionProgress).state;
    }
    if (this.result() !== undefined) {
      return (this.result() as SceneExecutionResult).state;
    }
    return undefined;
  }

  private noRollback(): boolean {
    return UiMapping.sceneNoRollback(this.progress(), this.result());
  }

  private closeOverlay(): void {
    this.showOverlay = false;
  }

  @Builder
  runOverlay() {
    Column({ space: AppSpacing.sm }) {
      Row() {
        Text(this.i18n.t(UiMapping.sceneRunKey(this.runState())))
          .fontSize(AppTypography.title)
          .fontWeight(AppTypography.weightMedium)
          .fontColor(AppColors.ink())
          .layoutWeight(1)
        if (UiMapping.sceneIsRunning(this.runState())) {
          Text(UiMapping.progressPercent(this.progress()).toFixed(0) + '%')
            .fontSize(AppTypography.label)
            .fontColor(AppColors.primary())
        }
      }
      .width('100%')
      if (this.progress() !== undefined) {
        Progress({
          value: (this.progress() as SceneExecutionProgress).executedCount,
          total: Math.max(1, (this.progress() as SceneExecutionProgress).steps.length),
          type: ProgressType.Linear
        })
          .width('100%')
          .color(AppColors.primary())
      }
      ForEach(this.steps().slice(), (step: SceneStepResult): void => {
        Row({ space: AppSpacing.xs }) {
          Text(UiMapping.sceneStepMarker(step.state))
            .fontSize(AppTypography.body)
            .fontColor(step.state === 'FAILED' ? AppColors.red() :
              step.state === 'SUCCEEDED' ? AppColors.green() : AppColors.muted())
          Column({ space: AppSpacing.xxs }) {
            Text(this.i18n.t('scene.step.line',
              new I18nParams([new NameValue('index', String(step.index + 1)),
                new NameValue('device', step.action.targetDeviceId)])))
              .fontSize(AppTypography.body)
              .fontColor(AppColors.ink())
            Text(this.i18n.t(UiMapping.sceneStepKey(step.state)))
              .fontSize(AppTypography.caption)
              .fontColor(step.state === 'FAILED'
                ? AppColors.red() : AppColors.muted())
            if (step.error !== undefined) {
              Text(this.i18n.t(step.error.i18nKey))
                .fontSize(AppTypography.caption)
                .fontColor(AppColors.red())
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding(AppSpacing.xs)
        .backgroundColor(AppColors.field())
        .borderRadius(AppRadius.button)
      }, (step: SceneStepResult): string => 'step-' + step.index)
      if (this.noRollback()) {
        Text(this.i18n.t('scene.no_rollback'))
          .fontSize(AppTypography.label)
          .fontColor(AppColors.amber())
          .width('100%')
          .padding(AppSpacing.sm)
          .backgroundColor(AppColors.surface())
          .borderRadius(AppRadius.button)
      }
      if (this.scenes.error !== undefined) {
        Text(this.i18n.t(this.scenes.error.i18nKey))
          .fontSize(AppTypography.label)
          .fontColor(AppColors.red())
      }
      Row({ space: AppSpacing.sm }) {
        if (UiMapping.sceneIsRunning(this.runState())) {
          Button(this.i18n.t('scene.cancel'))
            .layoutWeight(1)
            .height(44)
            .fontSize(AppTypography.body)
            .fontColor(AppColors.red())
            .backgroundColor(AppColors.field())
            .borderRadius(AppRadius.button)
            .onClick((): void => {
              this.cancelRun();
            })
        } else {
          PrimaryButton({
            i18n: this.i18n,
            localeRevision: this.localeRevision,
            labelKey: 'common.close',
            onTap: (): void => {
              this.closeOverlay();
            }
          })
        }
      }
      .width('100%')
    }
    .width('88%')
    .padding(AppSpacing.lg)
    .backgroundColor(AppColors.surfaceStrong())
    .borderRadius(AppRadius.modal)
    .border({ width: 1, color: AppColors.edge() })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Scroll() {
        Column({ space: AppSpacing.md }) {
          SectionHeader({
            i18n: this.i18n,
            localeRevision: this.localeRevision,
            titleKey: 'scene.title'
          })
          if (this.scenes.phase === 'LOADING' && this.scenes.scenes.length === 0) {
            LoadingSkeleton({ rows: 3, cardHeight: 96 })
          } else if (this.scenes.phase === 'ERROR') {
            ErrorState({
              i18n: this.i18n,
              localeRevision: this.localeRevision,
              messageKey: this.scenes.error === undefined
                ? 'common.refresh_failed' : this.scenes.error.i18nKey,
              onRetry: (): void => {
                const vm = this.sceneVm;
                if (vm !== undefined) {
                  vm.refresh().catch((): void => undefined);
                }
              }
            })
          } else if (this.scenes.scenes.length === 0) {
            EmptyState({
              i18n: this.i18n,
              localeRevision: this.localeRevision,
              titleKey: 'scene.empty.title',
              messageKey: 'scene.empty.message'
            })
          } else {
            ForEach(this.scenes.scenes.slice(), (scene: Scene): void => {
              SceneCard({
                i18n: this.i18n,
                localeRevision: this.localeRevision,
                scene: scene,
                isRunning: this.scenes.runningSceneId === scene.sceneId,
                canRun: this.canExecuteScene,
                lastResult: this.scenes.lastResult !== undefined &&
                  this.scenes.lastResult.sceneId === scene.sceneId
                  ? this.scenes.lastResult : undefined,
                onRun: (): void => {
                  this.runScene(scene);
                },
                onEdit: (): void => {
                  this.editNotice = true;
                }
              })
            }, (scene: Scene): string => scene.sceneId)
            Text(this.i18n.t('scene.no_rollback_hint'))
              .fontSize(AppTypography.caption)
              .fontColor(AppColors.muted())
          }
        }
        .width('100%')
        .padding(AppSpacing.md)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)

      if (this.showOverlay && (this.progress() !== undefined || this.result() !== undefined)) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.scrim'))
        this.runOverlay()
      }

      if (this.editNotice) {
        AppDialog({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          titleKey: 'scene.edit.title',
          messageKey: 'scene.edit.unavailable',
          confirmKey: 'common.close',
          cancelKey: 'common.close',
          onConfirm: (): void => {
            this.editNotice = false;
          },
          onCancel: (): void => {
            this.editNotice = false;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .id('scene-locale-' + this.localeRevision)
  }
}
