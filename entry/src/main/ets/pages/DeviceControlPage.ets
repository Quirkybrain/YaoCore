/*
 * YaoCore C-25 DeviceControlPage.
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §14.1.1/§14.1.4, §14.2/§14.3; FR-DEV-001..005; D-016
 *
 * One device only; batch control belongs to scenes. Light brightness uses the
 * C-21 55ms ThrottleGate + TouchUp final-value guarantee. Climate uses the
 * adapter range (16..30). Door stages are rendered from DoorUiState and never
 * upgraded to "secured" without evidence.
 */
import type { I18nService } from '../service/i18n/I18nService';
import { AppContext } from '../app/AppContext';
import type { AppRouteParams, NavigationService } from '../app/NavigationService';
import type { PageVmFactoryPort } from '../app/PageVmFactory';
import { DeviceAction, DeviceType } from '../common/constants/DeviceConstants';
import {
  AppColors,
  AppRadius,
  AppSpacing,
  AppTypography
} from '../common/theme/AppTheme';
import { DeviceKey } from '../model/DeviceKey';
import { AcMode } from '../model/DeviceTypes';
import { ControlPhase, ControlUiState } from '../viewmodel/core/ViewModelCore';
import { DeviceViewState, DeviceViewModel } from '../viewmodel/DeviceViewModel';
import { ClimateViewState, ClimateViewModel } from '../viewmodel/ClimateViewModel';
import { DoorViewState, DoorViewModel } from '../viewmodel/DoorViewModel';
import {
  DoorLinkConfig,
  DoorLinkMode,
  DoorStage
} from '../viewmodel/core/DoorConfirmationTracker';
import { I18nKeys } from '../service/i18n/I18nKeys';
import { I18nParams, I18nKey } from '../service/i18n/I18nModels';
import { NameValue } from '../common/types/NameValue';
import type { DeviceRecord } from '../repository/DomainModels';
import {
  EmptyState,
  ErrorState,
  LoadingSkeleton,
  PrimaryButton,
  SectionHeader
} from '../components/CommonControls';
import { ClimateCard, DoorCard, LightCard } from '../components/DeviceCards';
import { UiMapping, LIGHT_COLOR_PRESETS } from '../components/support/UiMapping';

@Component
export struct DeviceControlPage {
  @Require params: AppRouteParams;
  @Require appContext: AppContext;
  @Require i18n: I18nService;
  @Require navigation: NavigationService;
  @Require vmFactory: PageVmFactoryPort;
  @Prop localeRevision: number = 0;
  @Prop motionEnabled: boolean = true;
  @State devices: DeviceViewState = DeviceViewState.initial();
  @State climate: ClimateViewState | undefined = undefined;
  @State door: DoorViewState | undefined = undefined;
  @State loading: boolean = true;
  @State doorGuideVisible: boolean = false;
  @State selectedBrightness: number = 0;
  @State brightnessTouched: boolean = false;

  private deviceVm: DeviceViewModel | undefined = undefined;
  private climateVm: ClimateViewModel | undefined = undefined;
  private doorVm: DoorViewModel | undefined = undefined;
  private unsubscribeDevices: (() => void) | undefined = undefined;
  private unsubscribeClimate: (() => void) | undefined = undefined;
  private unsubscribeDoor: (() => void) | undefined = undefined;
  private loadedDetail: boolean = false;
  private doorGuideDismissed: boolean = false;

  aboutToAppear(): void {
    const key = this.deviceKey();
    if (key === undefined || this.appContext.activeFamilyId === undefined) {
      this.loading = false;
      return;
    }
    const deviceVm = this.vmFactory.createDeviceViewModel();
    this.deviceVm = deviceVm;
    this.unsubscribeDevices = deviceVm.subscribe((state: DeviceViewState): void => {
      this.devices = state;
      this.loading = state.phase === 'LOADING';
      this.ensureDetail(key);
    });
    deviceVm.initialize(this.appContext.activeFamilyId as string).then((): void => {
      this.loading = false;
      this.ensureDetail(key);
    }).catch((): void => {
      this.loading = false;
    });
  }

  aboutToDisappear(): void {
    if (this.unsubscribeDevices !== undefined) {
      this.unsubscribeDevices();
      this.unsubscribeDevices = undefined;
    }
    if (this.unsubscribeClimate !== undefined) {
      this.unsubscribeClimate();
      this.unsubscribeClimate = undefined;
    }
    if (this.unsubscribeDoor !== undefined) {
      this.unsubscribeDoor();
      this.unsubscribeDoor = undefined;
    }
    if (this.deviceVm !== undefined) {
      this.deviceVm.dispose();
      this.deviceVm = undefined;
    }
    if (this.climateVm !== undefined) {
      this.climateVm.dispose();
      this.climateVm = undefined;
    }
    if (this.doorVm !== undefined) {
      this.doorVm.dispose();
      this.doorVm = undefined;
    }
  }

  private deviceKey(): DeviceKey | undefined {
    const gatewayId = this.params.gatewayId;
    const deviceId = this.params.deviceId;
    if (gatewayId === undefined || deviceId === undefined ||
      gatewayId.length === 0 || deviceId.length === 0) {
      return undefined;
    }
    try {
      return new DeviceKey(gatewayId, deviceId);
    } catch (error) {
      return undefined;
    }
  }

  private record(): DeviceRecord | undefined {
    const key = this.deviceKey();
    if (key === undefined) {
      return undefined;
    }
    return UiMapping.findRecord(this.devices.records, key);
  }

  private control(): ControlUiState | undefined {
    const key = this.deviceKey();
    if (key === undefined) {
      return undefined;
    }
    return UiMapping.findControl(this.devices.controls, key);
  }

  private ensureDetail(key: DeviceKey): void {
    if (this.loadedDetail) {
      return;
    }
    const record = this.record();
    if (record === undefined) {
      return;
    }
    this.loadedDetail = true;
    this.selectedBrightness = UiMapping.brightnessValue(record, this.control());
    if (record.state.snapshot.deviceType === DeviceType.AC) {
      const vm = this.vmFactory.createClimateViewModel();
      this.climateVm = vm;
      this.unsubscribeClimate = vm.subscribe((state: ClimateViewState): void => {
        this.climate = state;
      });
      vm.load(key).catch((): void => undefined);
    } else if (record.state.snapshot.deviceType === DeviceType.DOOR) {
      const vm = this.vmFactory.createDoorViewModel();
      this.doorVm = vm;
      this.unsubscribeDoor = vm.subscribe((state: DoorViewState): void => {
        this.door = state;
        // F-19: the link guide is one-shot; a later VM publish must not
        // resurrect it after the user configured or skipped it.
        if (!this.doorGuideDismissed) {
          this.doorGuideVisible = UiMapping.doorNeedsLinkGuide(state.door);
        }
      });
      vm.load(key).catch((): void => undefined);
    }
  }

  private sourceText(): string {
    const record = this.record();
    if (record === undefined || record.state.snapshot.stateSource === undefined) {
      return this.i18n.t('stateSource.unknown',
        new I18nParams([new NameValue('value', '')]));
    }
    const key: I18nKey = I18nKeys.stateSource(record.state.snapshot.stateSource,
      record.state.snapshot.stateSourceKnown);
    return this.i18n.t(key.key, I18nParams.of(key.params));
  }

  private stageIndex(): number {
    if (this.door === undefined) {
      return 0;
    }
    // F-10: UNVERIFIED/FAILED/UNKNOWN never light the fourth (secured) stage.
    return UiMapping.doorStageProgress(this.door.door.stage);
  }

  private configureDoorLink(): void {
    const record = this.record();
    const vm = this.doorVm;
    if (record === undefined || vm === undefined) {
      return;
    }
    for (let index = 0; index < this.devices.records.length; index++) {
      const candidate = this.devices.records[index];
      if (candidate.state.snapshot.deviceType === DeviceType.SENSOR) {
        vm.configureLink(new DoorLinkConfig(DoorLinkMode.CONTACT_SENSOR,
          candidate.state.key, record.state.snapshot.updatedAt)).then((): void => {
          this.doorGuideVisible = false;
          this.doorGuideDismissed = true;
        }).catch((): void => {
          // Keep the guide visible so the user can retry.
        });
        return;
      }
    }
  }

  @Builder
  deviceHeader(record: DeviceRecord) {
    Column({ space: AppSpacing.xxs }) {
      Text(record.state.deviceName)
        .fontSize(AppTypography.title)
        .fontWeight(AppTypography.weightBold)
        .fontColor(AppColors.ink())
      Row({ space: AppSpacing.xs }) {
        Text(this.i18n.t(UiMapping.deviceTypeKey(record.state.snapshot.deviceType)))
          .fontSize(AppTypography.label)
          .fontColor(AppColors.muted())
        if (record.state.roomId.length > 0) {
          Text('·')
            .fontSize(AppTypography.caption)
            .fontColor(AppColors.mutedLight())
          Text(UiMapping.roomNameById(record.state.roomId, this.devices.rooms))
            .fontSize(AppTypography.label)
            .fontColor(AppColors.muted())
        }
        Text('·')
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.mutedLight())
        Text(this.i18n.t(record.state.snapshot.isOnline
          ? 'device.state.online' : 'device.state.offline'))
          .fontSize(AppTypography.label)
          .fontColor(record.state.snapshot.isOnline
            ? AppColors.green() : AppColors.amber())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  lightControl(record: DeviceRecord) {
    Column({ space: AppSpacing.md }) {
      LightCard({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        record: record,
        control: this.control() === undefined
          ? ControlUiState.idle(record.state.key, 0) : this.control() as ControlUiState,
        roomName: UiMapping.roomNameById(record.state.roomId, this.devices.rooms),
        compact: false,
        motionEnabled: this.motionEnabled,
        onToggle: (): void => {
          const vm = this.deviceVm;
          if (vm !== undefined) {
            vm.togglePower(record.state.key).catch((): void => undefined);
          }
        },
        onBrightnessChange: (value: number): void => {
          const vm = this.deviceVm;
          this.selectedBrightness = value;
          if (vm !== undefined) {
            if (!this.brightnessTouched) {
              this.brightnessTouched = true;
              vm.beginContinuous(record.state.key, DeviceAction.SET_BRIGHTNESS, 0, 100);
            }
            vm.updateContinuous(record.state.key, value);
          }
        },
        onBrightnessCommit: (value: number): void => {
          const vm = this.deviceVm;
          this.selectedBrightness = value;
          this.brightnessTouched = false;
          if (vm !== undefined) {
            vm.endContinuous(record.state.key, value).catch((): void => undefined);
          }
        },
        onColor: (color: string): void => {
          const vm = this.deviceVm;
          if (vm !== undefined) {
            vm.setColor(record.state.key, color).catch((): void => undefined);
          }
        },
        onOpenDetail: (): void => {
          // Already on the detail page.
        }
      })
    }
    .width('100%')
  }

  @Builder
  climateControl(record: DeviceRecord) {
    Column({ space: AppSpacing.md }) {
      if (this.climate !== undefined && this.climate.ac !== undefined) {
        ClimateCard({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          record: record,
          ac: this.climate.ac,
          control: this.climate.control,
          roomName: UiMapping.roomNameById(record.state.roomId, this.devices.rooms),
          compact: false,
          motionEnabled: this.motionEnabled,
          onPower: (): void => {
            const vm = this.climateVm;
            if (vm !== undefined) {
              vm.togglePower().catch((): void => undefined);
            }
          },
          onMode: (mode: AcMode): void => {
            const vm = this.climateVm;
            if (vm !== undefined) {
              vm.setMode(mode).catch((): void => undefined);
            }
          },
          onTemperatureChange: (value: number): void => {
            const vm = this.climateVm;
            if (vm !== undefined) {
              if (!this.brightnessTouched) {
                this.brightnessTouched = true;
                vm.beginTemperature(value);
              }
              vm.updateTemperature(value);
            }
          },
          onTemperatureCommit: (value: number): void => {
            const vm = this.climateVm;
            this.brightnessTouched = false;
            if (vm !== undefined) {
              vm.endTemperature(value).catch((): void => undefined);
            }
          },
          onOpenDetail: (): void => {
            // Already on the detail page.
          }
        })
        Text(this.i18n.t('device.climate.nonstandard_hint'))
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.muted())
      } else {
        LoadingSkeleton({ rows: 1, cardHeight: 160 })
      }
    }
    .width('100%')
  }

  @Builder
  doorControl(record: DeviceRecord) {
    Column({ space: AppSpacing.sm }) {
      if (this.door !== undefined) {
        DoorCard({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          record: record,
          door: this.door.door,
          control: this.door.control,
          roomName: UiMapping.roomNameById(record.state.roomId, this.devices.rooms),
          compact: false,
          motionEnabled: this.motionEnabled,
          onOpen: (): void => {
            const vm = this.doorVm;
            if (vm !== undefined) {
              vm.unlock().catch((): void => undefined);
            }
          },
          onClose: (): void => {
            const vm = this.doorVm;
            if (vm !== undefined) {
              vm.lock().catch((): void => undefined);
            }
          },
          onConfigureLink: (): void => {
            // R2-04: the one-shot rule only suppresses the automatic prompt.
            // The explicit "link sensor" button must always reopen the guide.
            this.doorGuideDismissed = false;
            this.doorGuideVisible = true;
          },
          onDismissAlert: (): void => {
            const vm = this.doorVm;
            if (vm !== undefined) {
              vm.dismissAlert();
            }
          },
          onOpenDetail: (): void => {
            // Already on the detail page.
          }
        })

        Column({ space: AppSpacing.xs }) {
          Text(this.i18n.t('device.door.stages'))
            .fontSize(AppTypography.label)
            .fontColor(AppColors.muted())
          Row({ space: AppSpacing.xxs }) {
            ForEach([1, 2, 3, 4], (index: number): void => {
              Column({ space: AppSpacing.xxs }) {
                Ellipse()
                  .width(14)
                  .height(14)
                  .fill(index <= this.stageIndex() ? AppColors.primary() : AppColors.line())
                Text(this.i18n.t('device.door.stage.marker'))
                  .fontSize(AppTypography.caption)
                  .fontColor(index <= this.stageIndex()
                    ? AppColors.inkSoft() : AppColors.mutedLight())
              }
              .layoutWeight(1)
            }, (index: number): string => 'door-stage-' + index)
          }
          .width('100%')
          Text(this.i18n.t(UiMapping.doorStageKey(this.door.door.stage)))
            .fontSize(AppTypography.body)
            .fontColor(AppColors.inkSoft())
          if (this.door.door.stage === DoorStage.UNVERIFIED) {
            Text(this.i18n.t('door.link.unverified'))
              .fontSize(AppTypography.label)
              .fontColor(AppColors.amber())
          }
        }
        .width('100%')
        .padding(AppSpacing.md)
        .backgroundColor(AppColors.surface())
        .borderRadius(AppRadius.card)
        .border({ width: 1, color: AppColors.edge() })
        .alignItems(HorizontalAlign.Start)

        if (this.doorGuideVisible) {
          Column({ space: AppSpacing.xs }) {
            Text(this.i18n.t('device.door.link_guide.title'))
              .fontSize(AppTypography.body)
              .fontWeight(AppTypography.weightMedium)
              .fontColor(AppColors.ink())
            Text(this.i18n.t('device.door.link_guide.message'))
              .fontSize(AppTypography.caption)
              .fontColor(AppColors.muted())
            Row({ space: AppSpacing.sm }) {
              PrimaryButton({
                i18n: this.i18n,
                localeRevision: this.localeRevision,
                labelKey: 'device.door.link_guide.confirm',
                fullWidth: false,
                onTap: (): void => {
                  this.configureDoorLink();
                }
              })
              Button(this.i18n.t('device.door.link_guide.skip'))
                .height(48)
                .fontSize(AppTypography.body)
                .fontColor(AppColors.inkSoft())
                .backgroundColor(AppColors.field())
                .borderRadius(AppRadius.button)
                .onClick((): void => {
                  this.doorGuideDismissed = true;
                  this.doorGuideVisible = false;
                })
            }
          }
          .width('100%')
          .padding(AppSpacing.md)
          .backgroundColor(AppColors.surfaceStrong())
          .borderRadius(AppRadius.card)
          .alignItems(HorizontalAlign.Start)
        }
      } else {
        LoadingSkeleton({ rows: 1, cardHeight: 160 })
      }
    }
    .width('100%')
  }

  @Builder
  sensorControl(record: DeviceRecord) {
    Column({ space: AppSpacing.sm }) {
      if (record.state.snapshot.temperature !== undefined) {
        Text(record.state.snapshot.temperature.toFixed(1) + ' °C')
          .fontSize(AppTypography.display)
          .fontColor(AppColors.ink())
      }
      if (record.state.snapshot.humidity !== undefined) {
        Text(record.state.snapshot.humidity.toFixed(0) + ' %')
          .fontSize(AppTypography.title)
          .fontColor(AppColors.inkSoft())
      }
      if (record.state.snapshot.presence !== undefined) {
        Text(this.i18n.t(record.state.snapshot.presence
          ? 'home.environment.presence_detected' : 'home.environment.presence_clear'))
          .fontSize(AppTypography.body)
          .fontColor(AppColors.inkSoft())
      }
      Text(this.i18n.t('device.sensor.read_only'))
        .fontSize(AppTypography.caption)
        .fontColor(AppColors.muted())
    }
    .width('100%')
    .padding(AppSpacing.lg)
    .backgroundColor(AppColors.surface())
    .borderRadius(AppRadius.card)
    .border({ width: 1, color: AppColors.edge() })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  deviceInfo(record: DeviceRecord) {
    Column({ space: AppSpacing.xxs }) {
      Text(this.i18n.t('device.info.title'))
        .fontSize(AppTypography.label)
        .fontColor(AppColors.muted())
      Text(this.i18n.t('device.info.gateway') + ' ' + record.state.key.gatewayId)
        .fontSize(AppTypography.caption)
        .fontColor(AppColors.muted())
      Text(this.i18n.t('device.info.device') + ' ' + record.state.key.deviceId)
        .fontSize(AppTypography.caption)
        .fontColor(AppColors.muted())
      if (record.state.snapshot.updatedAt.length > 0) {
        Text(this.i18n.t('device.info.updated') + ' ' + record.state.snapshot.updatedAt)
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.muted())
      }
      Text(this.i18n.t('device.info.source') + ' ' + this.sourceText())
        .fontSize(AppTypography.caption)
        .fontColor(AppColors.muted())
    }
    .width('100%')
    .padding(AppSpacing.md)
    .backgroundColor(AppColors.surface())
    .borderRadius(AppRadius.card)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: AppSpacing.md }) {
          if (this.deviceKey() === undefined) {
            ErrorState({
              i18n: this.i18n,
              localeRevision: this.localeRevision,
              messageKey: 'route.unknown.message',
              onRetry: (): void => {
                this.navigation.pop();
              }
            })
          } else if (this.loading) {
            LoadingSkeleton({ rows: 3, cardHeight: 88 })
          } else if (this.record() === undefined) {
            EmptyState({
              i18n: this.i18n,
              localeRevision: this.localeRevision,
              titleKey: 'device.not_found.title',
              messageKey: 'device.not_found.message'
            })
          } else {
            this.deviceHeader(this.record() as DeviceRecord)
            if (!(this.record() as DeviceRecord).isSupported) {
              Text(this.i18n.t('device.unsupported.read_only'))
                .fontSize(AppTypography.label)
                .fontColor(AppColors.amber())
                .padding(AppSpacing.sm)
                .backgroundColor(AppColors.surface())
                .borderRadius(AppRadius.button)
            }
            if (UiMapping.isDisabled(this.record() as DeviceRecord)) {
              Text(this.i18n.t('device.disabled.banner'))
                .fontSize(AppTypography.label)
                .fontColor(AppColors.amber())
                .padding(AppSpacing.sm)
                .backgroundColor(AppColors.surface())
                .borderRadius(AppRadius.button)
            }
            if (!(this.record() as DeviceRecord).state.snapshot.isOnline) {
              Text(this.i18n.t('device.offline.banner'))
                .fontSize(AppTypography.label)
                .fontColor(AppColors.amber())
            }
            if ((this.record() as DeviceRecord).gatewayRemoved ||
              (this.record() as DeviceRecord).state.isDismissed) {
              ErrorState({
                i18n: this.i18n,
                localeRevision: this.localeRevision,
                messageKey: 'device.removed.message',
                onRetry: (): void => {
                  this.navigation.pop();
                }
              })
            } else if ((this.record() as DeviceRecord).state.snapshot.deviceType ===
              DeviceType.LIGHT) {
              this.lightControl(this.record() as DeviceRecord)
            } else if ((this.record() as DeviceRecord).state.snapshot.deviceType ===
              DeviceType.AC) {
              this.climateControl(this.record() as DeviceRecord)
            } else if ((this.record() as DeviceRecord).state.snapshot.deviceType ===
              DeviceType.DOOR) {
              this.doorControl(this.record() as DeviceRecord)
            } else {
              this.sensorControl(this.record() as DeviceRecord)
            }
            this.deviceInfo(this.record() as DeviceRecord)
            Button(this.i18n.t('common.back'))
              .width('100%')
              .height(44)
              .fontSize(AppTypography.body)
              .fontColor(AppColors.ink())
              .backgroundColor(AppColors.field())
              .borderRadius(AppRadius.button)
              .onClick((): void => {
                this.navigation.pop();
              })
          }
        }
        .width('100%')
        .padding(AppSpacing.md)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .id('device-control-locale-' + this.localeRevision)
    }
    .title(this.i18n.t('device.control.title'))
    .backgroundColor(AppColors.background())
  }
}
