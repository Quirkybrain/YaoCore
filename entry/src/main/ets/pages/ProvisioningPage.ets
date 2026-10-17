/*
 * YaoCore C-27 ProvisioningPage (six-step BLE wizard).
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §16.1.2, §16.2/§16.3; FR-GW-001..003; BLE §7; PR-13
 *
 * Steps are user-facing; the C-23 ViewModel enforces the real provisioning
 * state machine, Security1, binding probe, commitBinding + family add, and
 * cancellation/secret cleanup. The page only renders view state and forwards
 * explicit user input. No Wi-Fi password/PoP is logged or copied.
 */
import type { I18nService } from '../service/i18n/I18nService';
import { AppContext } from '../app/AppContext';
import { AppRoute, AppRouteParams, NavigationService } from '../app/NavigationService';
import type { PageVmFactoryPort } from '../app/PageVmFactory';
import {
  AppColors,
  AppRadius,
  AppSpacing,
  AppTypography
} from '../common/theme/AppTheme';
import {
  BleProvisioningDevice,
  ProvisioningState,
  WifiAp
} from '../service/ble/BleProvisioningPorts';
import {
  BleProvisioningViewState,
  BleProvisioningViewModel,
  ProvisioningPermissionState,
  WizardStep
} from '../viewmodel/BleProvisioningViewModel';
import type { ProvisioningProgress } from '../service/ble/BleProvisioningPorts';
import type { BleProvisioningResult } from '../model/ProvisioningModels';
import {
  AppTextField,
  EmptyState,
  ErrorState,
  LoadingSkeleton,
  PrimaryButton,
  SectionHeader
} from '../components/CommonControls';
import { UiMapping } from '../components/support/UiMapping';

@Component
export struct ProvisioningPage {
  @Require params: AppRouteParams;
  @Require appContext: AppContext;
  @Require i18n: I18nService;
  @Require navigation: NavigationService;
  @Require vmFactory: PageVmFactoryPort;
  @Prop localeRevision: number = 0;
  @Prop motionEnabled: boolean = true;
  @State view: BleProvisioningViewState = BleProvisioningViewState.initial();
  @State localStep: number = 0;
  @State pop: string = '';
  @State ssid: string = '';
  @State wifiPassword: string = '';
  @State busy: boolean = false;
  @State errorKey: string = '';

  private provisioningVm: BleProvisioningViewModel | undefined = undefined;
  private unsubscribeProvisioning: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    const vm = this.vmFactory.createBleProvisioningViewModel();
    this.provisioningVm = vm;
    this.unsubscribeProvisioning = vm.subscribe((state: BleProvisioningViewState): void => {
      this.view = state;
      if (state.step === WizardStep.STEP_5_BOUND && state.result !== undefined) {
        this.localStep = 5;
        this.busy = false;
      }
      if (state.error !== undefined) {
        this.errorKey = state.error.i18nKey;
        this.localStep = UiMapping.provisioningErrorStep(state.error.error.code);
        this.busy = false;
      }
    });
    const familyId = this.appContext.activeFamilyId;
    if (familyId === undefined) {
      this.errorKey = 'family.none_message';
      return;
    }
    vm.initialize(familyId).catch((): void => undefined);
  }

  aboutToDisappear(): void {
    if (this.unsubscribeProvisioning !== undefined) {
      this.unsubscribeProvisioning();
      this.unsubscribeProvisioning = undefined;
    }
    if (this.provisioningVm !== undefined) {
      this.provisioningVm.dispose();
      this.provisioningVm = undefined;
    }
  }

  private requestPermissionAndScan(): void {
    const vm = this.provisioningVm;
    if (vm === undefined || this.busy) {
      return;
    }
    this.busy = true;
    this.errorKey = '';
    vm.requestPermission().then((): void => {
      if (this.view.permission !== ProvisioningPermissionState.GRANTED) {
        this.busy = false;
        this.localStep = 0;
        return;
      }
      this.localStep = 1;
      vm.startScan().then((): void => {
        this.busy = false;
      }).catch((): void => {
        this.busy = false;
      });
    }).catch((): void => {
      this.busy = false;
    });
  }

  private rescan(): void {
    const vm = this.provisioningVm;
    if (vm === undefined) {
      return;
    }
    vm.startScan().catch((): void => undefined);
  }

  private selectDevice(device: BleProvisioningDevice): void {
    const vm = this.provisioningVm;
    if (vm === undefined) {
      return;
    }
    vm.selectDevice(device);
    this.localStep = 2;
  }

  private nextFromHandshake(): void {
    if (this.pop.trim().length === 0) {
      this.errorKey = 'provisioning.error.pop_invalid';
      return;
    }
    this.errorKey = '';
    this.localStep = 3;
  }

  private nextFromWifi(): void {
    if (this.ssid.trim().length === 0) {
      this.errorKey = 'provisioning.error.network_not_found';
      return;
    }
    this.errorKey = '';
    this.localStep = 4;
  }

  private applyCredentials(): void {
    const vm = this.provisioningVm;
    if (vm === undefined || this.busy) {
      return;
    }
    if (this.pop.trim().length === 0 || this.ssid.trim().length === 0 ||
      this.wifiPassword.length === 0) {
      this.errorKey = 'provisioning.error.credential_missing';
      return;
    }
    this.busy = true;
    this.errorKey = '';
    vm.submit(this.pop, this.ssid.trim(), this.wifiPassword).then((): void => {
      this.busy = false;
    }).catch((): void => {
      this.busy = false;
    });
  }

  private cancel(): void {
    const vm = this.provisioningVm;
    if (vm !== undefined) {
      vm.cancel().then((): void => {
        this.navigation.pop();
      }).catch((): void => {
        this.navigation.pop();
      });
    } else {
      this.navigation.pop();
    }
  }

  private progressLabel(): string {
    if (this.view.progress === undefined) {
      return this.i18n.t(UiMapping.provisioningProgressKey(this.view.provisioning));
    }
    return this.i18n.t(UiMapping.provisioningProgressKey(
      (this.view.progress as ProvisioningProgress).state));
  }

  private result(): BleProvisioningResult | undefined {
    return this.view.result;
  }

  @Builder
  stepIndicator() {
    Scroll() {
      Row({ space: AppSpacing.xxs }) {
        ForEach([0, 1, 2, 3, 4, 5], (step: number): void => {
          Column({ space: AppSpacing.xxs }) {
            Text(String(step + 1))
              .fontSize(AppTypography.caption)
              .fontColor(step <= this.localStep ? Color.White : AppColors.muted())
              .width(26)
              .height(26)
              .textAlign(TextAlign.Center)
              .backgroundColor(step <= this.localStep
                ? AppColors.primary() : AppColors.field())
              .borderRadius(13)
            Text(this.i18n.t(UiMapping.provisioningStepKey(step)))
              .fontSize(AppTypography.caption)
              .fontColor(step === this.localStep ? AppColors.ink() : AppColors.muted())
              .maxLines(1)
          }
          .width(64)
        }, (step: number): string => 'prov-step-' + step)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  stepPermission() {
    Column({ space: AppSpacing.sm }) {
      Text(this.i18n.t('provisioning.permission.title'))
        .fontSize(AppTypography.section)
        .fontColor(AppColors.ink())
      Text(this.i18n.t('provisioning.permission.message'))
        .fontSize(AppTypography.body)
        .fontColor(AppColors.inkSoft())
      if (this.view.permission === ProvisioningPermissionState.DENIED) {
        Text(this.i18n.t('provisioning.error.permission_denied'))
          .fontSize(AppTypography.label)
          .fontColor(AppColors.red())
      }
      if (this.view.permission === ProvisioningPermissionState.BLUETOOTH_OFF) {
        Text(this.i18n.t('provisioning.error.bluetooth_off'))
          .fontSize(AppTypography.label)
          .fontColor(AppColors.amber())
      }
      PrimaryButton({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        labelKey: 'provisioning.permission.request',
        loading: this.busy,
        onTap: (): void => {
          this.requestPermissionAndScan();
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  stepScan() {
    Column({ space: AppSpacing.sm }) {
      Text(this.i18n.t('provisioning.scan.title'))
        .fontSize(AppTypography.section)
        .fontColor(AppColors.ink())
      Text(this.i18n.t('provisioning.scan.hint'))
        .fontSize(AppTypography.caption)
        .fontColor(AppColors.muted())
      if (this.view.scanResults.length === 0) {
        if (this.view.provisioning === ProvisioningState.SCANNING) {
          Row({ space: AppSpacing.xs }) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(AppColors.primary())
            Text(this.i18n.t('provisioning.scan.scanning'))
              .fontSize(AppTypography.body)
              .fontColor(AppColors.inkSoft())
          }
        } else {
          EmptyState({
            i18n: this.i18n,
            localeRevision: this.localeRevision,
            titleKey: 'provisioning.scan.empty.title',
            messageKey: 'provisioning.scan.empty.message'
          })
        }
      }
      ForEach(this.view.scanResults.slice(), (device: BleProvisioningDevice): void => {
        Row() {
          Column({ space: AppSpacing.xxs }) {
            Text(device.name)
              .fontSize(AppTypography.body)
              .fontColor(AppColors.ink())
            Text(device.deviceId)
              .fontSize(AppTypography.caption)
              .fontColor(AppColors.muted())
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text(String(device.rssi) + ' dBm')
            .fontSize(AppTypography.caption)
            .fontColor(AppColors.muted())
          Button(this.i18n.t('provisioning.scan.connect'))
            .height(44)
            .fontSize(AppTypography.caption)
            .fontColor(Color.White)
            .backgroundColor(AppColors.primary())
            .borderRadius(AppRadius.button)
            .onClick((): void => {
              this.selectDevice(device);
            })
        }
        .width('100%')
        .padding(AppSpacing.sm)
        .backgroundColor(AppColors.surface())
        .borderRadius(AppRadius.card)
      }, (device: BleProvisioningDevice): string => device.deviceId)
      Button(this.i18n.t('provisioning.scan.rescan'))
        .height(44)
        .fontSize(AppTypography.label)
        .fontColor(AppColors.primary())
        .backgroundColor(AppColors.field())
        .borderRadius(AppRadius.button)
        .onClick((): void => {
          this.rescan();
        })
      if (this.view.selectedDevice !== undefined) {
        Text(this.i18n.t('provisioning.scan.selected') + ' ' +
          this.view.selectedDevice.name)
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.green())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  stepHandshake() {
    Column({ space: AppSpacing.sm }) {
      Text(this.i18n.t('provisioning.handshake.title'))
        .fontSize(AppTypography.section)
        .fontColor(AppColors.ink())
      Text(this.i18n.t('provisioning.handshake.message'))
        .fontSize(AppTypography.body)
        .fontColor(AppColors.inkSoft())
      AppTextField({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        labelKey: 'provisioning.handshake.pop',
        placeholderKey: 'provisioning.handshake.pop_placeholder',
        value: this.pop,
        password: true,
        onChange: (value: string): void => {
          this.pop = value;
        }
      })
      PrimaryButton({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        labelKey: 'common.next',
        isEnabled: this.pop.trim().length > 0,
        onTap: (): void => {
          this.nextFromHandshake();
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  stepWifi() {
    Column({ space: AppSpacing.sm }) {
      Text(this.i18n.t('provisioning.wifi.title'))
        .fontSize(AppTypography.section)
        .fontColor(AppColors.ink())
      if (this.view.accessPoints.length > 0) {
        ForEach(this.view.accessPoints.slice(), (ap: WifiAp): void => {
          Button(ap.ssid)
            .width('100%')
            .height(44)
            .fontSize(AppTypography.body)
            .fontColor(this.ssid === ap.ssid ? Color.White : AppColors.ink())
            .backgroundColor(this.ssid === ap.ssid
              ? AppColors.primary() : AppColors.surface())
            .borderRadius(AppRadius.button)
            .onClick((): void => {
              this.ssid = ap.ssid;
            })
        }, (ap: WifiAp): string => ap.bssid)
      }
      AppTextField({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        labelKey: 'provisioning.wifi.ssid',
        placeholderKey: 'provisioning.wifi.ssid_placeholder',
        value: this.ssid,
        onChange: (value: string): void => {
          this.ssid = value;
        }
      })
      PrimaryButton({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        labelKey: 'common.next',
        isEnabled: this.ssid.trim().length > 0,
        onTap: (): void => {
          this.nextFromWifi();
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  stepApply() {
    Column({ space: AppSpacing.sm }) {
      Text(this.i18n.t('provisioning.apply.title'))
        .fontSize(AppTypography.section)
        .fontColor(AppColors.ink())
      Text(this.i18n.t('provisioning.apply.message'))
        .fontSize(AppTypography.body)
        .fontColor(AppColors.inkSoft())
      Text(this.ssid + ' · ' + this.progressLabel())
        .fontSize(AppTypography.label)
        .fontColor(AppColors.muted())
      AppTextField({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        labelKey: 'provisioning.apply.password',
        placeholderKey: 'provisioning.apply.password_placeholder',
        value: this.wifiPassword,
        password: true,
        onChange: (value: string): void => {
          this.wifiPassword = value;
        }
      })
      Text(this.i18n.t('provisioning.apply.secret_hint'))
        .fontSize(AppTypography.caption)
        .fontColor(AppColors.muted())
      PrimaryButton({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        labelKey: 'provisioning.apply.apply',
        loading: this.busy,
        isEnabled: this.wifiPassword.length > 0 && !this.busy,
        onTap: (): void => {
          this.applyCredentials();
        }
      })
      if (this.view.provisioning !== ProvisioningState.IDLE) {
        LoadingSkeleton({ rows: 1, cardHeight: 40 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  stepBound() {
    Column({ space: AppSpacing.sm }) {
      Text(this.i18n.t('provisioning.bound.title'))
        .fontSize(AppTypography.title)
        .fontWeight(AppTypography.weightBold)
        .fontColor(AppColors.green())
      if (this.result() !== undefined) {
        Text((this.result() as BleProvisioningResult).identity.gatewayName)
          .fontSize(AppTypography.section)
          .fontColor(AppColors.ink())
        Text((this.result() as BleProvisioningResult).identity.gatewayId)
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.muted())
        Text((this.result() as BleProvisioningResult).boardLedConfirmed
          ? this.i18n.t('provisioning.bound.led_confirmed')
          : this.i18n.t('provisioning.error.board_led_unconfirmed'))
          .fontSize(AppTypography.label)
          .fontColor((this.result() as BleProvisioningResult).boardLedConfirmed
            ? AppColors.green() : AppColors.amber())
      }
      Text(this.i18n.t('provisioning.bound.unassigned_hint'))
        .fontSize(AppTypography.body)
        .fontColor(AppColors.inkSoft())
      Row({ space: AppSpacing.sm }) {
        PrimaryButton({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          labelKey: 'provisioning.bound.assign_room',
          fullWidth: false,
          onTap: (): void => {
            this.navigation.pop();
            this.navigation.switchTab(AppRoute.ROOMS_TAB);
          }
        })
        Button(this.i18n.t('provisioning.bound.done'))
          .height(48)
          .fontSize(AppTypography.body)
          .fontColor(AppColors.inkSoft())
          .backgroundColor(AppColors.field())
          .borderRadius(AppRadius.button)
          .onClick((): void => {
            this.navigation.pop();
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: AppSpacing.md }) {
          Row() {
            Text(this.i18n.t('provisioning.title'))
              .fontSize(AppTypography.title)
              .fontWeight(AppTypography.weightBold)
              .fontColor(AppColors.ink())
              .layoutWeight(1)
            Button(this.i18n.t('provisioning.cancel'))
              .height(44)
              .fontSize(AppTypography.label)
              .fontColor(AppColors.red())
              .backgroundColor(Color.Transparent)
              .enabled(this.view.canCancel || this.localStep < 5)
              .onClick((): void => {
                this.cancel();
              })
          }
          .width('100%')
          this.stepIndicator()
          if (this.localStep < 5 && this.params.mode === 'ROTATE_SECRET') {
            Text(this.i18n.t('provisioning.rotate.hint'))
              .fontSize(AppTypography.caption)
              .fontColor(AppColors.amber())
          }
          if (this.errorKey.length > 0) {
            Text(this.i18n.t(this.errorKey))
              .fontSize(AppTypography.label)
              .fontColor(AppColors.red())
              .width('100%')
              .padding(AppSpacing.sm)
              .backgroundColor(AppColors.surface())
              .borderRadius(AppRadius.button)
          }
          if (this.localStep === 0) {
            this.stepPermission()
          } else if (this.localStep === 1) {
            this.stepScan()
          } else if (this.localStep === 2) {
            this.stepHandshake()
          } else if (this.localStep === 3) {
            this.stepWifi()
          } else if (this.localStep === 4) {
            this.stepApply()
          } else {
            this.stepBound()
          }
          if (this.localStep > 1 && this.localStep < 5) {
            Button(this.i18n.t('common.previous'))
              .height(44)
              .fontSize(AppTypography.label)
              .fontColor(AppColors.inkSoft())
              .backgroundColor(AppColors.field())
              .borderRadius(AppRadius.button)
              .enabled(!this.busy)
              .onClick((): void => {
                if (this.localStep === 4) {
                  this.localStep = 3;
                } else if (this.localStep === 3) {
                  this.localStep = 2;
                } else {
                  this.localStep = 1;
                }
              })
          }
        }
        .width('100%')
        .padding(AppSpacing.md)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .id('provisioning-locale-' + this.localeRevision)
    }
    .title(this.i18n.t('provisioning.title'))
    .backgroundColor(AppColors.background())
  }
}
