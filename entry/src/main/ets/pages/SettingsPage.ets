/*
 * YaoCore C-27 SettingsPage.
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §16.1.3, §16.2/§16.3; FR-SET-001..003; D-012/D-015
 *
 * Language switches immediately (platformRestartRequired is shown, never
 * hidden). Cloud configuration is manual-token only, single-gateway v1, and
 * never writes the token to preferences/logs/UI state. Manual IP is collapsed
 * by default, only for bound gateways, and never creates a binding.
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
import { StorageConstants } from '../common/constants/StorageConstants';
import { CloudConfig } from '../model/FamilyModels';
import { MemberRole } from '../model/FamilyModels';
import { CloudTransportState } from '../service/cloud/CloudModels';
import type { CloudConfigView } from '../service/cloud/CloudModels';
import { LocaleMode, I18nParams, SupportedLocale } from '../model/I18nModels';
import { NameValue } from '../common/types/NameValue';
import { TransportProfile } from '../model/DeviceTypes';
import {
  GatewaySecurityView,
  ManualAddressResult,
  SettingsSection,
  SettingsViewState,
  SettingsViewModel
} from '../viewmodel/SettingsViewModel';
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
export struct SettingsPage {
  @Require params: AppRouteParams;
  @Require appContext: AppContext;
  @Require i18n: I18nService;
  @Require navigation: NavigationService;
  @Require vmFactory: PageVmFactoryPort;
  @Prop localeRevision: number = 0;
  @Prop motionEnabled: boolean = true;
  @State settings: SettingsViewState = SettingsViewState.initial(SupportedLocale.ZH_CN);
  @State section: SettingsSection = SettingsSection.LANGUAGE;
  @State endpoint: string = '';
  @State projectId: string = '';
  @State cloudDeviceId: string = '';
  @State token: string = '';
  @State manualIp: string = '';
  @State manualPort: string = '';
  @State selectedGatewayId: string = '';
  @State localErrorKey: string = '';
  @State cloudTested: boolean = false;
  @State cloudTestOk: boolean = false;

  private settingsVm: SettingsViewModel | undefined = undefined;
  private unsubscribeSettings: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    const vm = this.vmFactory.createSettingsViewModel();
    this.settingsVm = vm;
    this.unsubscribeSettings = vm.subscribe((state: SettingsViewState): void => {
      this.settings = state;
      this.section = state.section;
      this.fillCloudInputs(state.cloud);
      if (state.security.length > 0 && this.selectedGatewayId.length === 0) {
        this.selectedGatewayId = state.security[0].gatewayId;
      }
    });
    const requested = this.params.section;
    if (requested === 'CLOUD') {
      this.section = SettingsSection.CLOUD;
      vm.setSection(SettingsSection.CLOUD);
    } else if (requested === 'SECURITY') {
      this.section = SettingsSection.SECURITY;
      vm.setSection(SettingsSection.SECURITY);
    } else if (requested === 'ADVANCED') {
      this.section = SettingsSection.ADVANCED;
      vm.setSection(SettingsSection.ADVANCED);
    }
    vm.initialize().catch((): void => undefined);
  }

  aboutToDisappear(): void {
    if (this.unsubscribeSettings !== undefined) {
      this.unsubscribeSettings();
      this.unsubscribeSettings = undefined;
    }
    if (this.settingsVm !== undefined) {
      this.settingsVm.dispose();
      this.settingsVm = undefined;
    }
  }

  private fillCloudInputs(view: CloudConfigView | undefined): void {
    if (view === undefined || view.config === undefined) {
      return;
    }
    if (this.endpoint.length === 0) {
      this.endpoint = view.config.endpoint;
    }
    if (this.projectId.length === 0) {
      this.projectId = view.config.projectId;
    }
    if (this.cloudDeviceId.length === 0) {
      this.cloudDeviceId = view.config.deviceId;
    }
  }

  private isAdmin(): boolean {
    const session = this.appContext.session;
    return session !== undefined && session.role === MemberRole.ADMIN;
  }

  private selectSection(section: SettingsSection): void {
    this.section = section;
    const vm = this.settingsVm;
    if (vm !== undefined) {
      vm.setSection(section);
    }
  }

  private saveCloud(): void {
    const vm = this.settingsVm;
    if (vm === undefined) {
      return;
    }
    this.localErrorKey = '';
    try {
      const config = new CloudConfig(this.endpoint.trim(), this.projectId.trim(),
        this.cloudDeviceId.trim(), StorageConstants.ASSET_CLOUD_TOKEN, undefined);
      const tokenInput = this.token;
      this.token = '';
      vm.saveCloudConfig(config,
        tokenInput.length > 0 ? tokenInput : undefined).catch((): void => undefined);
    } catch (error) {
      this.localErrorKey = 'errors.cloud.endpoint_invalid';
    }
  }

  private testCloud(): void {
    const vm = this.settingsVm;
    if (vm === undefined) {
      return;
    }
    this.cloudTested = true;
    this.cloudTestOk = false;
    vm.testCloudConnection().then((ok: boolean): void => {
      this.cloudTestOk = ok;
    }).catch((): void => {
      this.cloudTestOk = false;
    });
  }

  private clearToken(): void {
    const vm = this.settingsVm;
    if (vm !== undefined) {
      vm.clearCloudToken().catch((): void => undefined);
    }
  }

  private probeAddress(): void {
    const vm = this.settingsVm;
    if (vm === undefined || this.selectedGatewayId.length === 0) {
      return;
    }
    const port = Number.parseInt(this.manualPort.length === 0 ? '8443' : this.manualPort, 10);
    vm.probeManualAddress(this.selectedGatewayId, this.manualIp,
      Number.isNaN(port) ? 8443 : port).catch((): void => undefined);
  }

  private manualAddressText(): string {
    const result = this.settings.manualAddressResult;
    if (result === undefined) {
      return '';
    }
    if (result.accepted) {
      return this.i18n.t('settings.advanced.accepted');
    }
    if (result.error === undefined) {
      return this.i18n.t('errors.app.manual_address_rejected');
    }
    return this.i18n.t(result.error.i18nKey);
  }

  private securityProfile(view: GatewaySecurityView): string {
    return UiMapping.securityProfileKey(view.profile, view.pinCount);
  }

  @Builder
  languageButton(mode: LocaleMode, label: Resource) {
    Button(label)
      .layoutWeight(1)
      .height(44)
      .fontSize(AppTypography.label)
      .fontColor(this.settings.localeMode === mode ? Color.White : AppColors.inkSoft())
      .backgroundColor(this.settings.localeMode === mode
        ? AppColors.primary() : AppColors.field())
      .borderRadius(AppRadius.button)
      .onClick((): void => {
        const vm = this.settingsVm;
        if (vm !== undefined) {
          vm.setLocaleMode(mode).catch((): void => undefined);
        }
      })
  }

  @Builder
  sectionButton(section: SettingsSection, labelKey: string) {
    Button(this.i18n.t(labelKey))
      .height(44)
      .fontSize(AppTypography.caption)
      .fontColor(this.section === section ? Color.White : AppColors.inkSoft())
      .backgroundColor(this.section === section
        ? AppColors.primary() : AppColors.surface())
      .borderRadius(AppRadius.chip)
      .onClick((): void => {
        this.selectSection(section);
      })
  }

  @Builder
  languageSection() {
    Column({ space: AppSpacing.sm }) {
      SectionHeader({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        titleKey: 'settings.section.language'
      })
      Row({ space: AppSpacing.xs }) {
        this.languageButton(LocaleMode.AUTO, $r('app.string.settings_language_auto'))
        this.languageButton(LocaleMode.ZH_CN, $r('app.string.settings_language_zh_cn'))
        this.languageButton(LocaleMode.EN_US, $r('app.string.settings_language_en_us'))
      }
      .width('100%')
      if (this.settings.platformRestartRequired) {
        Text(this.i18n.t('settings.language.restart_required'))
          .fontSize(AppTypography.label)
          .fontColor(AppColors.amber())
      }
      Text(this.i18n.t('settings.language.current') + ' ' +
        this.i18n.t(UiMapping.localeModeKey(this.settings.localeMode)))
        .fontSize(AppTypography.caption)
        .fontColor(AppColors.muted())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  cloudSection() {
    Column({ space: AppSpacing.sm }) {
      SectionHeader({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        titleKey: 'settings.section.cloud'
      })
      Row({ space: AppSpacing.xs }) {
        Text(this.i18n.t('settings.cloud.state'))
          .fontSize(AppTypography.label)
          .fontColor(AppColors.muted())
        Text(this.i18n.t(UiMapping.cloudStateKey(
          this.settings.cloud === undefined ? undefined : this.settings.cloud.state)))
          .fontSize(AppTypography.label)
          .fontColor(AppColors.inkSoft())
      }
      if (this.settings.cloud !== undefined &&
        (this.settings.cloud.state === CloudTransportState.TOKEN_EXPIRED ||
          this.settings.cloud.state === CloudTransportState.TOKEN_INVALID)) {
        Text(this.i18n.t('cloud.token.expired'))
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.amber())
      }
      if (this.settings.cloudRestricted) {
        Text(this.i18n.t(this.settings.cloudRestrictionKey === undefined
          ? 'settings.cloud.single_gateway_required'
          : this.settings.cloudRestrictionKey))
          .fontSize(AppTypography.label)
          .fontColor(AppColors.amber())
      }
      AppTextField({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        labelKey: 'settings.cloud.endpoint',
        placeholderKey: 'settings.cloud.endpoint_placeholder',
        value: this.endpoint,
        isEnabled: !this.settings.cloudRestricted && this.isAdmin(),
        onChange: (value: string): void => {
          this.endpoint = value;
        }
      })
      AppTextField({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        labelKey: 'settings.cloud.project',
        placeholderKey: 'settings.cloud.project_placeholder',
        value: this.projectId,
        isEnabled: !this.settings.cloudRestricted && this.isAdmin(),
        onChange: (value: string): void => {
          this.projectId = value;
        }
      })
      AppTextField({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        labelKey: 'settings.cloud.device',
        placeholderKey: 'settings.cloud.device_placeholder',
        value: this.cloudDeviceId,
        isEnabled: !this.settings.cloudRestricted && this.isAdmin(),
        onChange: (value: string): void => {
          this.cloudDeviceId = value;
        }
      })
      AppTextField({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        labelKey: 'settings.cloud.token',
        placeholderKey: 'settings.cloud.token_placeholder',
        value: this.token,
        password: true,
        isEnabled: !this.settings.cloudRestricted && this.isAdmin(),
        onChange: (value: string): void => {
          this.token = value;
        }
      })
      Text(this.i18n.t('settings.cloud.token_manual_hint'))
        .fontSize(AppTypography.caption)
        .fontColor(AppColors.muted())
      Row({ space: AppSpacing.xs }) {
        PrimaryButton({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          labelKey: 'common.save',
          fullWidth: false,
          isEnabled: !this.settings.cloudRestricted && this.isAdmin(),
          onTap: (): void => {
            this.saveCloud();
          }
        })
        Button(this.i18n.t('settings.cloud.test'))
          .height(48)
          .fontSize(AppTypography.body)
          .fontColor(AppColors.primary())
          .backgroundColor(AppColors.field())
          .borderRadius(AppRadius.button)
          .enabled(!this.settings.cloudRestricted && this.isAdmin())
          .onClick((): void => {
            this.testCloud();
          })
        Button(this.i18n.t('settings.cloud.clear_token'))
          .height(48)
          .fontSize(AppTypography.body)
          .fontColor(AppColors.red())
          .backgroundColor(Color.Transparent)
          .enabled(this.isAdmin())
          .onClick((): void => {
            this.clearToken();
          })
      }
      .width('100%')
      if (this.cloudTested && this.cloudTestOk) {
        // F-17: success is explicit; a state refresh alone was ambiguous.
        Text(this.i18n.t('errors.gateway.success'))
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.green())
      } else if (this.cloudTested && this.settings.cloud !== undefined &&
        this.settings.cloud.lastError !== undefined) {
        Text(this.i18n.t(this.settings.cloud.lastError.i18nKey))
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.red())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  securitySection() {
    Column({ space: AppSpacing.sm }) {
      SectionHeader({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        titleKey: 'settings.section.security'
      })
      if (this.settings.security.length === 0) {
        EmptyState({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          titleKey: 'settings.security.empty.title',
          messageKey: 'settings.security.empty.message'
        })
      }
      ForEach(this.settings.security.slice(), (view: GatewaySecurityView): void => {
        Column({ space: AppSpacing.xxs }) {
          Row() {
            Text(view.gatewayName.length > 0 ? view.gatewayName : view.gatewayId)
              .fontSize(AppTypography.body)
              .fontColor(AppColors.ink())
              .layoutWeight(1)
            Text(this.i18n.t(this.securityProfile(view)))
              .fontSize(AppTypography.caption)
              .fontColor(AppColors.primary())
          }
          .width('100%')
          if (view.pinCount > 0) {
            Text(this.i18n.t('settings.security.pin_count',
              new I18nParams([new NameValue('count', String(view.pinCount))])))
              .fontSize(AppTypography.caption)
              .fontColor(AppColors.muted())
          }
          if (view.lastErrorKey !== undefined) {
            Text(this.i18n.t(view.lastErrorKey))
              .fontSize(AppTypography.caption)
              .fontColor(AppColors.red())
          }
          if (view.rotationRecommended) {
            Text(this.i18n.t('settings.security.rotation_recommended'))
              .fontSize(AppTypography.caption)
              .fontColor(AppColors.amber())
          }
          Row({ space: AppSpacing.xs }) {
            Button(this.i18n.t('settings.security.rotate'))
              .height(44)
              .fontSize(AppTypography.caption)
              .fontColor(Color.White)
              .backgroundColor(AppColors.primary())
              .borderRadius(AppRadius.button)
              .enabled(this.isAdmin())
              .onClick((): void => {
                this.navigation.push(AppRoute.PROVISIONING, new AppRouteParams({
                  mode: 'ROTATE_SECRET', expectedGatewayId: view.gatewayId
                }));
              })
            if (view.profile === TransportProfile.P_BLOCKED) {
              Button(this.i18n.t('settings.security.reprovision'))
                .height(44)
                .fontSize(AppTypography.caption)
                .fontColor(AppColors.inkSoft())
                .backgroundColor(AppColors.field())
                .borderRadius(AppRadius.button)
                // R2-01: gateway reconfiguration is an ADMIN capability, just
                // like ROTATE_SECRET; non-admins get a disabled control and
                // the service layer remains the authoritative check.
                .enabled(this.isAdmin())
                .onClick((): void => {
                  this.navigation.push(AppRoute.PROVISIONING, new AppRouteParams({
                    mode: 'RECONFIGURE', expectedGatewayId: view.gatewayId
                  }));
                })
            }
          }
        }
        .width('100%')
        .padding(AppSpacing.sm)
        .backgroundColor(AppColors.surface())
        .borderRadius(AppRadius.card)
        .border({ width: 1, color: AppColors.edge() })
        .alignItems(HorizontalAlign.Start)
      }, (view: GatewaySecurityView): string => view.gatewayId)
      Text(this.i18n.t('settings.security.no_manual_pins'))
        .fontSize(AppTypography.caption)
        .fontColor(AppColors.muted())
      Button(this.i18n.t('profile.lock'))
        .width('100%')
        .height(44)
        .fontSize(AppTypography.body)
        .fontColor(Color.White)
        .backgroundColor(AppColors.red())
        .borderRadius(AppRadius.button)
        .onClick((): void => {
          this.appContext.lock().catch((): void => undefined);
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  advancedSection() {
    Column({ space: AppSpacing.sm }) {
      Row() {
        Text(this.i18n.t('settings.section.advanced'))
          .fontSize(AppTypography.section)
          .fontColor(AppColors.ink())
          .layoutWeight(1)
        Button(this.i18n.t(this.settings.advancedExpanded
          ? 'common.collapse' : 'common.expand'))
          .height(44)
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.primary())
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            const vm = this.settingsVm;
            if (vm !== undefined) {
              vm.setAdvancedExpanded(!this.settings.advancedExpanded);
            }
          })
      }
      .width('100%')
      if (this.settings.advancedExpanded) {
        Text(this.i18n.t('settings.advanced.hint'))
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.muted())
        if (this.settings.security.length === 0) {
          Text(this.i18n.t('settings.advanced.no_gateway'))
            .fontSize(AppTypography.body)
            .fontColor(AppColors.muted())
        } else {
          Scroll() {
            Row({ space: AppSpacing.xs }) {
              ForEach(this.settings.security.slice(), (view: GatewaySecurityView): void => {
                Button(view.gatewayName.length > 0 ? view.gatewayName : view.gatewayId)
                  .height(44)
                  .fontSize(AppTypography.caption)
                  .fontColor(this.selectedGatewayId === view.gatewayId
                    ? Color.White : AppColors.inkSoft())
                  .backgroundColor(this.selectedGatewayId === view.gatewayId
                    ? AppColors.primary() : AppColors.field())
                  .borderRadius(AppRadius.chip)
                  .onClick((): void => {
                    this.selectedGatewayId = view.gatewayId;
                  })
              }, (view: GatewaySecurityView): string => view.gatewayId)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          AppTextField({
            i18n: this.i18n,
            localeRevision: this.localeRevision,
            labelKey: 'settings.advanced.ip',
            placeholderKey: 'settings.advanced.ip_placeholder',
            value: this.manualIp,
            onChange: (value: string): void => {
              this.manualIp = value;
            }
          })
          AppTextField({
            i18n: this.i18n,
            localeRevision: this.localeRevision,
            labelKey: 'settings.advanced.port',
            placeholderKey: 'settings.advanced.port_placeholder',
            value: this.manualPort,
            onChange: (value: string): void => {
              this.manualPort = value;
            }
          })
          PrimaryButton({
            i18n: this.i18n,
            localeRevision: this.localeRevision,
            labelKey: 'settings.advanced.probe',
            isEnabled: this.manualIp.trim().length > 0 &&
              this.selectedGatewayId.length > 0,
            fullWidth: false,
            onTap: (): void => {
              this.probeAddress();
            }
          })
          if (this.settings.manualAddressResult !== undefined) {
            Text(this.manualAddressText())
              .fontSize(AppTypography.label)
              .fontColor((this.settings.manualAddressResult as ManualAddressResult).accepted
                ? AppColors.green() : AppColors.red())
          }
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  behaviourSection() {
    Column({ space: AppSpacing.sm }) {
      SectionHeader({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        titleKey: 'settings.section.behaviour'
      })
      Row() {
        Text(this.i18n.t('settings.motion'))
          .fontSize(AppTypography.body)
          .fontColor(AppColors.ink())
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.settings.motionEnabled })
          .onChange((value: boolean): void => {
            const vm = this.settingsVm;
            if (vm !== undefined) {
              vm.setMotionEnabled(value).catch((): void => undefined);
            }
          })
      }
      .width('100%')
      Row() {
        Text(this.i18n.t('settings.notifications'))
          .fontSize(AppTypography.body)
          .fontColor(AppColors.ink())
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.settings.notificationsEnabled })
          .onChange((value: boolean): void => {
            const vm = this.settingsVm;
            if (vm !== undefined) {
              vm.setNotificationsEnabled(value).catch((): void => undefined);
            }
          })
      }
      .width('100%')
      Text(this.i18n.t('settings.appearance.system'))
        .fontSize(AppTypography.caption)
        .fontColor(AppColors.muted())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: AppSpacing.md }) {
          Scroll() {
            Row({ space: AppSpacing.xs }) {
              this.sectionButton(SettingsSection.LANGUAGE, 'settings.section.language')
              this.sectionButton(SettingsSection.CLOUD, 'settings.section.cloud')
              this.sectionButton(SettingsSection.SECURITY, 'settings.section.security')
              if (this.isAdmin()) {
                this.sectionButton(SettingsSection.ADVANCED, 'settings.section.advanced')
              }
              this.sectionButton(SettingsSection.NOTIFICATIONS,
                'settings.section.behaviour')
              this.sectionButton(SettingsSection.ABOUT, 'settings.section.about')
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')

          if (this.settings.phase === 'LOADING' && this.settings.appVersion.length === 0) {
            LoadingSkeleton({ rows: 3, cardHeight: 72 })
          } else if (this.settings.phase === 'ERROR') {
            ErrorState({
              i18n: this.i18n,
              localeRevision: this.localeRevision,
              messageKey: this.settings.error === undefined
                ? 'common.refresh_failed' : this.settings.error.i18nKey,
              onRetry: (): void => {
                const vm = this.settingsVm;
                if (vm !== undefined) {
                  vm.initialize().catch((): void => undefined);
                }
              }
            })
          } else {
            if (this.section === SettingsSection.LANGUAGE) {
              this.languageSection()
            } else if (this.section === SettingsSection.CLOUD) {
              this.cloudSection()
            } else if (this.section === SettingsSection.SECURITY) {
              this.securitySection()
            } else if (this.section === SettingsSection.ADVANCED && this.isAdmin()) {
              this.advancedSection()
            } else if (this.section === SettingsSection.NOTIFICATIONS) {
              this.behaviourSection()
            } else {
              Row({ space: AppSpacing.sm }) {
                PrimaryButton({
                  i18n: this.i18n,
                  localeRevision: this.localeRevision,
                  labelKey: 'profile.about',
                  fullWidth: true,
                  onTap: (): void => {
                    this.navigation.push(AppRoute.ABOUT);
                  }
                })
              }
              .width('100%')
              Text(this.i18n.t('settings.version') + ' ' + this.settings.appVersion)
                .fontSize(AppTypography.caption)
                .fontColor(AppColors.muted())
            }
            if (this.settings.error !== undefined) {
              Text(this.i18n.t(this.settings.error.i18nKey))
                .fontSize(AppTypography.caption)
                .fontColor(AppColors.red())
            }
            if (this.localErrorKey.length > 0) {
              Text(this.i18n.t(this.localErrorKey))
                .fontSize(AppTypography.caption)
                .fontColor(AppColors.red())
            }
          }
        }
        .width('100%')
        .padding(AppSpacing.md)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .id('settings-locale-' + this.localeRevision)
    }
    .title(this.i18n.t('page.settings.title'))
    .backgroundColor(AppColors.background())
  }
}
