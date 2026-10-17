/*
 * YaoCore C-27 AboutPage.
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §16.1.4, §16.3(6); FR-SET-003
 *
 * Static privacy/security boundary text; version comes from bundleInfo via
 * SettingsViewModel. No endpoint, token, secret or internal path is shown.
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
import { SettingsViewState, SettingsViewModel } from '../viewmodel/SettingsViewModel';
import { SectionHeader } from '../components/CommonControls';

@Component
export struct AboutPage {
  @Require appContext: AppContext;
  @Require i18n: I18nService;
  @Require navigation: NavigationService;
  @Require vmFactory: PageVmFactoryPort;
  @Prop localeRevision: number = 0;
  @Prop motionEnabled: boolean = true;
  @State version: string = '';

  private settingsVm: SettingsViewModel | undefined = undefined;
  private unsubscribeSettings: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    const vm = this.vmFactory.createSettingsViewModel();
    this.settingsVm = vm;
    this.unsubscribeSettings = vm.subscribe((state: SettingsViewState): void => {
      this.version = state.appVersion;
    });
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

  @Builder
  section(titleKey: string, bodyKey: string) {
    Column({ space: AppSpacing.xs }) {
      Text(this.i18n.t(titleKey))
        .fontSize(AppTypography.section)
        .fontWeight(AppTypography.weightMedium)
        .fontColor(AppColors.ink())
      Text(this.i18n.t(bodyKey))
        .fontSize(AppTypography.body)
        .fontColor(AppColors.inkSoft())
        .lineHeight(21)
    }
    .width('100%')
    .padding(AppSpacing.md)
    .backgroundColor(AppColors.surface())
    .borderRadius(AppRadius.card)
    .border({ width: 1, color: AppColors.edge() })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: AppSpacing.md }) {
          Column({ space: AppSpacing.xxs }) {
            Text($r('app.string.shell_app_title'))
              .fontSize(AppTypography.display)
              .fontWeight(AppTypography.weightBold)
              .fontColor(AppColors.ink())
            Text(this.i18n.t('about.version') + ' ' +
              (this.version.length > 0 ? this.version : this.i18n.t('common.unknown')))
              .fontSize(AppTypography.label)
              .fontColor(AppColors.muted())
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          SectionHeader({
            i18n: this.i18n,
            localeRevision: this.localeRevision,
            titleKey: 'about.privacy.title'
          })
          this.section('about.privacy.heading', 'about.privacy.body')
          this.section('about.security.heading', 'about.security.body')
          this.section('about.guest.heading', 'about.guest.body')
          this.section('about.open_source.heading', 'about.open_source.body')
          this.section('about.license.heading', 'about.license.body')
        }
        .width('100%')
        .padding(AppSpacing.md)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .id('about-locale-' + this.localeRevision)
    }
    .title(this.i18n.t('page.about.title'))
    .backgroundColor(AppColors.background())
  }
}
