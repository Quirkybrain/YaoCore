/*
 * YaoCore C-24/C-25/C-26 reusable cards.
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §13.1.3/§13.1.4, §14.1.2..4, §15.1.4; FR-DEV/FR-SCN
 *
 * Cards render only the values passed by pages/view models. They never call a
 * repository, transport or VM and never decide ACK/RBAC outcomes.
 */
import type { I18nService } from '../service/i18n/I18nService';
import type { DeviceRecord } from '../repository/DomainModels';
import type { SceneExecutionResult } from '../repository/DomainModels';
import type { Scene } from '../model/FamilyModels';
import type { Room } from '../model/FamilyModels';
import type { AcViewState } from '../service/ac/AcModels';
import { AcMode } from '../model/DeviceTypes';
import { ControlPhase } from '../viewmodel/core/ViewModelCore';
import type { ControlUiState } from '../viewmodel/core/ViewModelCore';
import { DoorLockState } from '../viewmodel/core/DoorConfirmationTracker';
import type { DoorUiState } from '../viewmodel/core/DoorConfirmationTracker';
import { DeviceKey } from '../model/DeviceKey';
import { CardVisualState } from '../common/theme/AppEnums';
import { I18nParams } from '../service/i18n/I18nModels';
import { NameValue } from '../common/types/NameValue';
import {
  AppColors,
  AppMotionTokens,
  AppRadius,
  AppSpacing,
  AppTypography
} from '../common/theme/AppTheme';
import { UiMapping, LIGHT_COLOR_PRESETS } from './support/UiMapping';

@Component
export struct LightCard {
  @Require i18n: I18nService;
  @Prop localeRevision: number = 0;
  @Require record: DeviceRecord;
  @Require control: ControlUiState;
  @Prop roomName: string = '';
  @Prop compact: boolean = false;
  @Prop motionEnabled: boolean = true;
  onToggle: () => void = (): void => {};
  onBrightnessChange: (value: number) => void = (value: number): void => {};
  onBrightnessCommit: (value: number) => void = (value: number): void => {};
  onColor: (color: string) => void = (color: string): void => {};
  onOpenDetail: () => void = (): void => {};

  private visual(): CardVisualState {
    return UiMapping.visualState(this.record, this.control);
  }

  private controlsEnabled(): boolean {
    return UiMapping.controlsEnabled(this.record);
  }

  build() {
    Column({ space: AppSpacing.xs }) {
      Row() {
        Text(this.record.state.deviceName)
          .fontSize(AppTypography.body)
          .fontWeight(AppTypography.weightMedium)
          .fontColor(AppColors.ink())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.visual() !== CardVisualState.IDLE) {
          Text(this.i18n.t(UiMapping.cardStateKey(this.visual())))
            .fontSize(AppTypography.caption)
            .fontColor(this.visual() === CardVisualState.REVERT
              ? AppColors.amber() : AppColors.muted())
        }
      }
      .width('100%')
      if (this.roomName.length > 0) {
        Text(this.roomName)
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.muted())
      }
      Row({ space: AppSpacing.xs }) {
        Button(this.i18n.t(UiMapping.powerValue(this.record, this.control)
          ? 'common.off' : 'common.on'))
          .height(44)
          .fontSize(AppTypography.label)
          .fontColor(Color.White)
          .backgroundColor(UiMapping.powerValue(this.record, this.control)
            ? AppColors.primary() : AppColors.muted())
          .borderRadius(AppRadius.chip)
          .enabled(this.controlsEnabled())
          .accessibilityText(this.i18n.t(UiMapping.powerValue(this.record, this.control)
            ? 'common.off' : 'common.on'))
          .onClick((): void => {
            this.onToggle();
          })
        Blank()
        Button(this.i18n.t('common.view'))
          .height(44)
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.primary())
          .backgroundColor(Color.Transparent)
          .enabled(this.record.isControlAllowed || this.record.isSupported)
          .accessibilityText(this.i18n.t('common.view'))
          .onClick((): void => {
            this.onOpenDetail();
          })
      }
      .width('100%')
      if (!this.compact) {
        Row({ space: AppSpacing.xs }) {
          Text(String(UiMapping.brightnessValue(this.record, this.control)) + '%')
            .fontSize(AppTypography.caption)
            .fontColor(AppColors.inkSoft())
          Slider({
            value: UiMapping.brightnessValue(this.record, this.control),
            min: 0,
            max: 100,
            step: 1,
            style: SliderStyle.OutSet
          })
            .layoutWeight(1)
            .selectedColor(AppColors.primary())
            .trackColor(AppColors.line())
            // F-04: PENDING must keep receiving drag input. The VM's
            // ThrottleGate/TouchUp and same-action de-duplication own
            // idempotency; disabling the slider here breaks 55ms tracking.
            .enabled(this.controlsEnabled())
            .onChange((value: number, mode: SliderChangeMode): void => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.onBrightnessCommit(value);
              } else {
                this.onBrightnessChange(value);
              }
            })
        }
        .width('100%')
        Row({ space: AppSpacing.xs }) {
          ForEach(LIGHT_COLOR_PRESETS.slice(),
            (color: string): void => {
              Button()
                .width(44)
                .height(44)
                .backgroundColor(color)
                .borderRadius(22)
                .border({ width: 1, color: AppColors.edge() })
                .enabled(this.controlsEnabled())
                .accessibilityText(color)
                .onClick((): void => {
                  this.onColor(color);
                })
            }, (color: string): string => color)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(AppSpacing.md)
    .backgroundColor(AppColors.cardFor(this.visual()))
    .borderRadius(AppRadius.card)
    .border({
      width: this.visual() === CardVisualState.REVERT ? 2 : 1,
      color: AppColors.accentFor(this.visual())
    })
    .shadow({
      radius: this.visual() === CardVisualState.COMMITTED ? 24 : 18,
      color: $r('app.color.shadow_base'),
      offsetX: 0,
      offsetY: 8
    })
    .animation({
      duration: this.motionEnabled ? AppMotionTokens.FADE_MS : 0,
      curve: Curve.EaseInOut
    })
  }
}

@Component
export struct ClimateCard {
  @Require i18n: I18nService;
  @Prop localeRevision: number = 0;
  @Require record: DeviceRecord;
  @Require ac: AcViewState;
  @Require control: ControlUiState;
  @Prop roomName: string = '';
  @Prop compact: boolean = false;
  @Prop motionEnabled: boolean = true;
  onPower: () => void = (): void => {};
  onMode: (mode: AcMode) => void = (mode: AcMode): void => {};
  onTemperatureChange: (value: number) => void = (value: number): void => {};
  onTemperatureCommit: (value: number) => void = (value: number): void => {};
  onOpenDetail: () => void = (): void => {};

  private visual(): CardVisualState {
    return UiMapping.visualState(this.record, this.control);
  }

  private controlsEnabled(): boolean {
    return UiMapping.controlsEnabled(this.record);
  }

  build() {
    Column({ space: AppSpacing.xs }) {
      Row() {
        Text(this.record.state.deviceName)
          .fontSize(AppTypography.body)
          .fontWeight(AppTypography.weightMedium)
          .fontColor(AppColors.ink())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.i18n.t(this.ac.brandI18nKey))
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.muted())
      }
      .width('100%')
      Text(UiMapping.temperatureValue(this.record, this.control).toFixed(0) + ' °C')
        .fontSize(this.compact ? AppTypography.title : AppTypography.display)
        .fontColor(AppColors.ink())
      Text(this.i18n.t(UiMapping.acModeKey(this.ac)))
        .fontSize(AppTypography.label)
        .fontColor(AppColors.inkSoft())
      Row({ space: AppSpacing.xs }) {
        Button(this.i18n.t(UiMapping.powerValue(this.record, this.control)
          ? 'common.on' : 'common.off'))
          .height(44)
          .fontSize(AppTypography.caption)
          .fontColor(Color.White)
          .backgroundColor(UiMapping.powerValue(this.record, this.control)
            ? AppColors.primary() : AppColors.muted())
          .borderRadius(AppRadius.chip)
          .enabled(this.controlsEnabled())
          .accessibilityText(this.i18n.t(UiMapping.powerValue(this.record, this.control)
            ? 'common.on' : 'common.off'))
          .onClick((): void => {
            this.onPower();
          })
        Blank()
        Button(this.i18n.t('common.view'))
          .height(44)
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.primary())
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.i18n.t('common.view'))
          .onClick((): void => {
            this.onOpenDetail();
          })
      }
      .width('100%')
      if (!this.compact && UiMapping.acEditable(this.ac)) {
        Slider({
          value: UiMapping.temperatureValue(this.record, this.control),
          min: 16,
          max: 30,
          step: 1,
          style: SliderStyle.OutSet
        })
          .width('100%')
          .selectedColor(AppColors.primary())
          .trackColor(AppColors.line())
          .enabled(this.controlsEnabled())
          .onChange((value: number, mode: SliderChangeMode): void => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.onTemperatureCommit(value);
            } else {
              this.onTemperatureChange(value);
            }
          })
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach([AcMode.AUTO, AcMode.COOL, AcMode.HEAT, AcMode.DRY, AcMode.FAN,
            AcMode.ECO, AcMode.SLEEP], (mode: AcMode): void => {
            Button(this.i18n.t('ac.mode.' + mode.toLowerCase()))
              .height(44)
              .margin({ right: AppSpacing.xs, bottom: AppSpacing.xxs })
              .fontSize(AppTypography.caption)
              .fontColor(this.ac.mode.mode === mode ? Color.White : AppColors.inkSoft())
              .backgroundColor(this.ac.mode.mode === mode
                ? AppColors.primary() : AppColors.field())
              .borderRadius(AppRadius.chip)
              .enabled(this.controlsEnabled())
              .onClick((): void => {
                this.onMode(mode);
              })
          }, (mode: AcMode): string => mode)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(AppSpacing.md)
    .backgroundColor(AppColors.cardFor(this.visual()))
    .borderRadius(AppRadius.card)
    .border({
      width: this.visual() === CardVisualState.REVERT ? 2 : 1,
      color: AppColors.accentFor(this.visual())
    })
    .shadow({
      radius: 18,
      color: $r('app.color.shadow_base'),
      offsetX: 0,
      offsetY: 8
    })
    .animation({
      duration: this.motionEnabled ? AppMotionTokens.FADE_MS : 0,
      curve: Curve.EaseInOut
    })
  }
}

@Component
export struct DoorCard {
  @Require i18n: I18nService;
  @Prop localeRevision: number = 0;
  @Require record: DeviceRecord;
  @Require door: DoorUiState;
  @Require control: ControlUiState;
  @Prop roomName: string = '';
  @Prop compact: boolean = false;
  @Prop motionEnabled: boolean = true;
  @Prop linkGuideOpen: boolean = false;
  onOpen: () => void = (): void => {};
  onClose: () => void = (): void => {};
  onConfigureLink: () => void = (): void => {};
  onDismissAlert: () => void = (): void => {};
  onOpenDetail: () => void = (): void => {};

  private visual(): CardVisualState {
    return UiMapping.visualState(this.record, this.control);
  }

  private controlsEnabled(): boolean {
    return UiMapping.controlsEnabled(this.record);
  }

  private lockKey(): string {
    return UiMapping.lockKeyFor(this.door.lockState);
  }

  build() {
    Column({ space: AppSpacing.xs }) {
      Row() {
        Text(this.record.state.deviceName)
          .fontSize(AppTypography.body)
          .fontWeight(AppTypography.weightMedium)
          .fontColor(AppColors.ink())
          .layoutWeight(1)
        Text(this.i18n.t(this.lockKey()))
          .fontSize(AppTypography.label)
          .fontColor(this.door.lockState === DoorLockState.SECURED
            ? AppColors.green() : AppColors.amber())
      }
      .width('100%')
      Text(this.i18n.t(UiMapping.doorStageKey(this.door.stage)))
        .fontSize(AppTypography.caption)
        .fontColor(AppColors.muted())
      if (this.door.link.mode === 'NONE') {
        Text(this.i18n.t('door.link.unverified'))
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.amber())
      }
      if (this.door.alertActive) {
        Row({ space: AppSpacing.xs }) {
          Text(this.i18n.t(UiMapping.doorAlarmKey(this.door)))
            .fontSize(AppTypography.caption)
            .fontColor(AppColors.red())
            .layoutWeight(1)
          Button(this.i18n.t('common.close'))
            .height(28)
            .fontSize(AppTypography.caption)
            .backgroundColor(AppColors.field())
            .fontColor(AppColors.inkSoft())
            .borderRadius(AppRadius.chip)
            .onClick((): void => {
              this.onDismissAlert();
            })
        }
        .width('100%')
      }
      if (!this.compact) {
        Row({ space: AppSpacing.xs }) {
          Button(this.i18n.t('device.door.lock'))
            .layoutWeight(1)
            .height(44)
            .fontSize(AppTypography.label)
            .fontColor(Color.White)
            .backgroundColor(AppColors.primary())
            .borderRadius(AppRadius.button)
            .enabled(this.controlsEnabled() &&
              this.control.phase !== ControlPhase.PENDING)
            .onClick((): void => {
              this.onClose();
            })
          Button(this.i18n.t('device.door.open'))
            .layoutWeight(1)
            .height(44)
            .fontSize(AppTypography.label)
            .fontColor(AppColors.ink())
            .backgroundColor(AppColors.field())
            .borderRadius(AppRadius.button)
            .enabled(this.controlsEnabled() &&
              this.control.phase !== ControlPhase.PENDING)
            .onClick((): void => {
              this.onOpen();
            })
        }
        .width('100%')
        if (this.door.link.mode === 'NONE' && !this.linkGuideOpen) {
          Button(this.i18n.t('device.door.configure_link'))
            .height(44)
            .fontSize(AppTypography.caption)
            .fontColor(AppColors.primary())
            .backgroundColor(Color.Transparent)
            .onClick((): void => {
              this.onConfigureLink();
            })
        }
      }
      Row() {
        if (this.door.error !== undefined) {
          Text(this.i18n.t(this.door.error.i18nKey))
            .fontSize(AppTypography.caption)
            .fontColor(AppColors.red())
            .layoutWeight(1)
        }
        Button(this.i18n.t('common.view'))
          .height(44)
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.primary())
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.onOpenDetail();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppSpacing.md)
    .backgroundColor(AppColors.cardFor(this.visual()))
    .borderRadius(AppRadius.card)
    .border({
      width: this.visual() === CardVisualState.REVERT ? 2 : 1,
      color: AppColors.accentFor(this.visual())
    })
    .shadow({
      radius: 18,
      color: $r('app.color.shadow_base'),
      offsetX: 0,
      offsetY: 8
    })
    .animation({
      duration: this.motionEnabled ? AppMotionTokens.FADE_MS : 0,
      curve: Curve.EaseInOut
    })
  }
}

@Component
export struct SensorTile {
  @Require i18n: I18nService;
  @Prop localeRevision: number = 0;
  @Require record: DeviceRecord;
  @Prop roomName: string = '';
  onOpen: (key: DeviceKey) => void = (key: DeviceKey): void => {};

  build() {
    Column({ space: AppSpacing.xxs }) {
      Row() {
        Text(this.record.state.deviceName)
          .fontSize(AppTypography.body)
          .fontColor(AppColors.ink())
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.i18n.t('card.state.read_only'))
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.muted())
      }
      .width('100%')
      if (this.record.state.snapshot.temperature !== undefined) {
        Text(this.record.state.snapshot.temperature.toFixed(1) + ' °C')
          .fontSize(AppTypography.title)
          .fontColor(AppColors.inkSoft())
      }
      if (this.record.state.snapshot.humidity !== undefined) {
        Text(this.record.state.snapshot.humidity.toFixed(0) + ' %')
          .fontSize(AppTypography.label)
          .fontColor(AppColors.muted())
      }
      if (this.record.state.snapshot.presence !== undefined) {
        Text(this.i18n.t(this.record.state.snapshot.presence
          ? 'home.environment.presence_detected' : 'home.environment.presence_clear'))
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.muted())
      }
      Button(this.i18n.t('common.view'))
        .height(44)
        .fontSize(AppTypography.caption)
        .fontColor(AppColors.primary())
        .backgroundColor(Color.Transparent)
        .onClick((): void => {
          this.onOpen(this.record.state.key);
        })
    }
    .width('100%')
    .padding(AppSpacing.md)
    .backgroundColor(AppColors.surface())
    .borderRadius(AppRadius.card)
    .border({ width: 1, color: AppColors.edge() })
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct SceneCard {
  @Require i18n: I18nService;
  @Prop localeRevision: number = 0;
  @Require scene: Scene;
  @Prop isRunning: boolean = false;
  @Prop canRun: boolean = false;
  @Prop lastResult: SceneExecutionResult | undefined = undefined;
  onRun: () => void = (): void => {};
  onEdit: () => void = (): void => {};

  build() {
    Column({ space: AppSpacing.xs }) {
      Row() {
        Text(this.scene.sceneName)
          .fontSize(AppTypography.body)
          .fontWeight(AppTypography.weightMedium)
          .fontColor(AppColors.ink())
          .layoutWeight(1)
        Text(this.i18n.t('scene.actions',
            new I18nParams([new NameValue('count', String(this.scene.actions.length))])))
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.muted())
      }
      .width('100%')
      if (!this.scene.isEnabled) {
        Text(this.i18n.t('scene.disabled_hint'))
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.amber())
      }
      if (!this.canRun) {
        Text(this.i18n.t('errors.app.auth_rbac_denied'))
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.amber())
      }
      if (this.lastResult !== undefined) {
        Text(this.i18n.t(UiMapping.sceneRunKey(this.lastResult.state)))
          .fontSize(AppTypography.label)
          .fontColor(UiMapping.sceneFailed(this.lastResult.state) ? AppColors.red() : AppColors.green())
      }
      Row({ space: AppSpacing.xs }) {
        Button(this.i18n.t(this.isRunning ? 'scene.running' : 'scene.run'))
          .layoutWeight(1)
          .height(44)
          .fontSize(AppTypography.label)
          .fontColor(Color.White)
          .backgroundColor(AppColors.primary())
          .borderRadius(AppRadius.button)
          .enabled(!this.isRunning && this.scene.isEnabled &&
            this.scene.actions.length > 0 && this.canRun)
          .onClick((): void => {
            this.onRun();
          })
        Button(this.i18n.t('common.edit'))
          .height(44)
          .fontSize(AppTypography.label)
          .fontColor(AppColors.inkSoft())
          .backgroundColor(AppColors.field())
          .borderRadius(AppRadius.button)
          .enabled(!this.isRunning)
          .onClick((): void => {
            this.onEdit();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppSpacing.md)
    .backgroundColor(AppColors.surface())
    .borderRadius(AppRadius.card)
    .border({ width: 1, color: AppColors.edge() })
    .shadow({
      radius: 18,
      color: $r('app.color.shadow_base'),
      offsetX: 0,
      offsetY: 8
    })
  }
}

@Component
export struct RoomCard {
  @Require i18n: I18nService;
  @Prop localeRevision: number = 0;
  @Require room: Room;
  @Prop deviceCount: number = 0;
  @Prop unassignedCount: number = 0;
  @Prop canManage: boolean = false;
  onOpen: () => void = (): void => {};
  onRename: () => void = (): void => {};
  onDelete: () => void = (): void => {};

  build() {
    Column({ space: AppSpacing.xs }) {
      Text(this.room.roomName)
        .fontSize(AppTypography.body)
        .fontWeight(AppTypography.weightMedium)
        .fontColor(AppColors.ink())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.i18n.t('device.count',
          new I18nParams([new NameValue('count', String(this.deviceCount))])))
        .fontSize(AppTypography.caption)
        .fontColor(AppColors.muted())
      if (this.unassignedCount > 0) {
        Text(this.i18n.t('rooms.unassigned_count',
          new I18nParams([new NameValue('count', String(this.unassignedCount))])))
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.amber())
      }
      Row({ space: AppSpacing.xs }) {
        Button(this.i18n.t('common.view'))
          .layoutWeight(1)
          .height(44)
          .fontSize(AppTypography.caption)
          .fontColor(Color.White)
          .backgroundColor(AppColors.primary())
          .borderRadius(AppRadius.button)
          .onClick((): void => {
            this.onOpen();
          })
        if (this.canManage) {
          Button(this.i18n.t('common.edit'))
            .height(44)
            .fontSize(AppTypography.caption)
            .fontColor(AppColors.inkSoft())
            .backgroundColor(AppColors.field())
            .borderRadius(AppRadius.button)
            .onClick((): void => {
              this.onRename();
            })
          Button(this.i18n.t('common.delete'))
            .height(44)
            .fontSize(AppTypography.caption)
            .fontColor(AppColors.red())
            .backgroundColor(Color.Transparent)
            .onClick((): void => {
              this.onDelete();
            })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppSpacing.md)
    .backgroundColor(AppColors.surface())
    .borderRadius(AppRadius.card)
    .border({ width: 1, color: AppColors.edge() })
  }
}
