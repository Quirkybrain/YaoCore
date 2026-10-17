/*
 * YaoCore C-28/C-25/C-26/C-27 MainShell: Tabs + Navigation/NavDestination.
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §17.1.5, §14.1.1, §15.1.1, §16.1.1; UIUX §3
 *
 * Home/Rooms/Scenes/Profile are TabContent pages. Secondary pages are
 * NavDestination entries built from AppRoute. Unknown routes render
 * UnknownRouteView instead of crashing. Tab state survives secondary pages.
 *
 * DI: AppContext/i18n/navigation/vmFactory/localeRevision are explicit props.
 * No @Provide/@Consume; pages create VMs only through vmFactory.
 */
import type { I18nService } from '../service/i18n/I18nService';
import { AppContext } from '../app/AppContext';
import {
  AppRoute,
  AppRouteParams,
  AppRouteValidation,
  NavigationService
} from '../app/NavigationService';
import type { PageVmFactoryPort } from '../app/PageVmFactory';
import { AppColors, AppRadius, AppSpacing, AppTypography } from '../common/theme/AppTheme';
import { ShellTheme } from '../common/theme/ShellTheme';
import { AboutPage } from './AboutPage';
import { DeviceControlPage } from './DeviceControlPage';
import { FamilyManagePage } from './FamilyManagePage';
import { HomePage } from './HomePage';
import { ProfilePage } from './ProfilePage';
import { ProvisioningPage } from './ProvisioningPage';
import { RoomManagePage } from './RoomManagePage';
import { RoomsPage } from './RoomsPage';
import { ScenePage } from './ScenePage';
import { SettingsPage } from './SettingsPage';
import { UnknownRouteView } from './ShellViews';

@Component
export struct MainShell {
  @Require appContext: AppContext;
  @Require i18n: I18nService;
  @Require navigation: NavigationService;
  @Require vmFactory: PageVmFactoryPort;
  @Prop localeRevision: number = 0;
  @Prop motionEnabled: boolean = true;
  @State selectedTab: number = 0;
  @State roomsHighlight: string = '';

  aboutToAppear(): void {
    this.selectedTab = this.navigation.getSelectedTabIndex();
    this.navigation.setTabChangeListener((index: number): void => {
      this.selectedTab = index;
      if (index === 1) {
        const highlight = this.navigation.consumeRoomsHighlight();
        if (highlight !== undefined) {
          this.roomsHighlight = highlight;
        }
      }
    });
  }

  aboutToDisappear(): void {
    this.navigation.setTabChangeListener(undefined);
  }

  @Builder
  tabBar(index: number, title: Resource) {
    Column({ space: ShellTheme.SPACING_XXS }) {
      // F-10: Ellipse.fill(ResourceColor) is API 10/11; Circle.fill(Resource)
      // resolves to the API 26 ColorMetrics overload on this SDK.
      Ellipse()
        .width(6)
        .height(6)
        .fill(this.selectedTab === index
          ? AppColors.primary() : AppColors.mutedLight())
      Text(title)
        .fontSize(AppTypography.caption)
        .fontColor(this.selectedTab === index
          ? AppColors.primary() : AppColors.muted())
        .fontWeight(this.selectedTab === index
          ? AppTypography.weightMedium : AppTypography.weightRegular)
    }
    .width('25%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  /**
   * F-05: validate the route name and its required parameters at the
   * NavDestination boundary too, so a direct NavPathStack push cannot bypass
   * `NavigationService.push/replace`. Invalid input renders the ErrorState.
   */
  private routeIsValid(name: string, param: Object): boolean {
    const route = AppRouteValidation.fromName(name);
    if (route === undefined) {
      return false;
    }
    return AppRouteValidation.accepts(route,
      param instanceof AppRouteParams ? param as AppRouteParams : undefined);
  }

  @Builder
  routeBuilder(name: string, param: Object) {
    if (!this.routeIsValid(name, param)) {
      UnknownRouteView({ i18n: this.i18n, navigation: this.navigation,
        localeRevision: this.localeRevision })
    } else if (name === AppRoute.DEVICE_CONTROL) {
      DeviceControlPage({
        params: param instanceof AppRouteParams ? param as AppRouteParams : new AppRouteParams(),
        appContext: this.appContext,
        i18n: this.i18n,
        navigation: this.navigation,
        vmFactory: this.vmFactory,
        localeRevision: this.localeRevision,
        motionEnabled: this.motionEnabled
      })
    } else if (name === AppRoute.FAMILY) {
      FamilyManagePage({
        params: param instanceof AppRouteParams ? param as AppRouteParams : new AppRouteParams(),
        appContext: this.appContext,
        i18n: this.i18n,
        navigation: this.navigation,
        vmFactory: this.vmFactory,
        localeRevision: this.localeRevision,
        motionEnabled: this.motionEnabled
      })
    } else if (name === AppRoute.ROOM_MANAGE) {
      RoomManagePage({
        params: param instanceof AppRouteParams ? param as AppRouteParams : new AppRouteParams(),
        appContext: this.appContext,
        i18n: this.i18n,
        navigation: this.navigation,
        vmFactory: this.vmFactory,
        localeRevision: this.localeRevision,
        motionEnabled: this.motionEnabled
      })
    } else if (name === AppRoute.PROVISIONING) {
      ProvisioningPage({
        params: param instanceof AppRouteParams ? param as AppRouteParams : new AppRouteParams(),
        appContext: this.appContext,
        i18n: this.i18n,
        navigation: this.navigation,
        vmFactory: this.vmFactory,
        localeRevision: this.localeRevision,
        motionEnabled: this.motionEnabled
      })
    } else if (name === AppRoute.SETTINGS) {
      SettingsPage({
        params: param instanceof AppRouteParams ? param as AppRouteParams : new AppRouteParams(),
        appContext: this.appContext,
        i18n: this.i18n,
        navigation: this.navigation,
        vmFactory: this.vmFactory,
        localeRevision: this.localeRevision,
        motionEnabled: this.motionEnabled
      })
    } else if (name === AppRoute.ABOUT) {
      AboutPage({
        appContext: this.appContext,
        i18n: this.i18n,
        navigation: this.navigation,
        vmFactory: this.vmFactory,
        localeRevision: this.localeRevision,
        motionEnabled: this.motionEnabled
      })
    } else {
      UnknownRouteView({ i18n: this.i18n, navigation: this.navigation,
        localeRevision: this.localeRevision })
    }
  }

  build() {
    Navigation(this.navigation.getStack()) {
      Column() {
        Row() {
          Text($r('app.string.shell_app_title'))
            .fontSize(AppTypography.title)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.ink())
          Blank()
          Text(this.appContext.activeFamilyName.length > 0
            ? this.appContext.activeFamilyName : $r('app.string.shell_no_family'))
            .fontSize(AppTypography.label)
            .fontColor(AppColors.muted())
        }
        .width('100%')
        .height(ShellTheme.HEADER_HEIGHT)
        .padding({
          left: AppSpacing.lg,
          right: AppSpacing.lg
        })

        Tabs({ barPosition: BarPosition.End, index: this.selectedTab }) {
          TabContent() {
            HomePage({
              appContext: this.appContext,
              i18n: this.i18n,
              navigation: this.navigation,
              vmFactory: this.vmFactory,
              localeRevision: this.localeRevision,
              motionEnabled: this.motionEnabled
            })
          }
          .tabBar(this.tabBar(0, $r('app.string.tab_home')))

          TabContent() {
            RoomsPage({
              appContext: this.appContext,
              i18n: this.i18n,
              navigation: this.navigation,
              vmFactory: this.vmFactory,
              localeRevision: this.localeRevision,
              motionEnabled: this.motionEnabled,
              highlightRoomId: this.roomsHighlight
            })
          }
          .tabBar(this.tabBar(1, $r('app.string.tab_rooms')))

          TabContent() {
            ScenePage({
              appContext: this.appContext,
              i18n: this.i18n,
              navigation: this.navigation,
              vmFactory: this.vmFactory,
              localeRevision: this.localeRevision,
              motionEnabled: this.motionEnabled
            })
          }
          .tabBar(this.tabBar(2, $r('app.string.tab_scenes')))

          TabContent() {
            ProfilePage({
              appContext: this.appContext,
              i18n: this.i18n,
              navigation: this.navigation,
              vmFactory: this.vmFactory,
              localeRevision: this.localeRevision,
              motionEnabled: this.motionEnabled
            })
          }
          .tabBar(this.tabBar(3, $r('app.string.tab_profile')))
        }
        .barHeight(ShellTheme.TAB_BAR_HEIGHT)
        .barBackgroundColor(AppColors.tabBackground())
        .layoutWeight(1)
        .onChange((index: number): void => {
          this.selectedTab = index;
          this.navigation.selectTabIndex(index);
        })
      }
      .width('100%')
      .height('100%')
      .id('shell-locale-' + this.localeRevision)
    }
    .navDestination(this.routeBuilder)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .width('100%')
    .height('100%')
  }
}
