/*
 * YaoCore T-17 MainShell: Tabs + Navigation/NavDestination.
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §17.1.5; UIUX §3
 *
 * Home/Rooms/Scenes/Profile are TabContent pages. Secondary pages are
 * NavDestination entries built from AppRoute. Unknown routes render
 * UnknownRouteView instead of crashing. Tab state survives secondary pages.
 */
import type { I18nService } from '../service/i18n/I18nService';
import { AppContext } from '../app/AppContext';
import {
  AppRoute,
  AppRouteParams,
  AppRouteValidation,
  NavigationService
} from '../app/NavigationService';
import { ShellTheme } from '../app/ShellTheme';
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
  @Prop localeRevision: number = 0;
  @State selectedTab: number = 0;

  aboutToAppear(): void {
    this.navigation.setTabChangeListener((index: number): void => {
      this.selectedTab = index;
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
          ? $r('app.color.shell_primary') : $r('app.color.shell_muted_light'))
      Text(title)
        .fontSize(ShellTheme.FONT_CAPTION)
        .fontColor(this.selectedTab === index
          ? $r('app.color.shell_primary') : $r('app.color.shell_muted'))
        .fontWeight(this.selectedTab === index ? FontWeight.Medium : FontWeight.Regular)
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
      UnknownRouteView({ navigation: this.navigation })
    } else if (name === AppRoute.DEVICE_CONTROL) {
      DeviceControlPage({
        params: param instanceof AppRouteParams ? param as AppRouteParams : new AppRouteParams(),
        navigation: this.navigation
      })
    } else if (name === AppRoute.FAMILY) {
      FamilyManagePage({ navigation: this.navigation })
    } else if (name === AppRoute.ROOM_MANAGE) {
      RoomManagePage({ navigation: this.navigation })
    } else if (name === AppRoute.PROVISIONING) {
      ProvisioningPage({ navigation: this.navigation })
    } else if (name === AppRoute.SETTINGS) {
      SettingsPage({ i18n: this.i18n, navigation: this.navigation })
    } else if (name === AppRoute.ABOUT) {
      AboutPage({ navigation: this.navigation })
    } else {
      UnknownRouteView({ navigation: this.navigation })
    }
  }

  build() {
    Navigation(this.navigation.getStack()) {
      Column() {
        Row() {
          Text($r('app.string.shell_app_title'))
            .fontSize(ShellTheme.FONT_TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.shell_ink'))
          Blank()
          Text(this.appContext.activeFamilyName.length > 0
            ? this.appContext.activeFamilyName : $r('app.string.shell_no_family'))
            .fontSize(ShellTheme.FONT_LABEL)
            .fontColor($r('app.color.shell_muted'))
        }
        .width('100%')
        .height(ShellTheme.HEADER_HEIGHT)
        .padding({
          left: ShellTheme.SPACING_LG,
          right: ShellTheme.SPACING_LG
        })

        Tabs({ barPosition: BarPosition.End, index: this.selectedTab }) {
          TabContent() {
            HomePage({ navigation: this.navigation })
          }
          .tabBar(this.tabBar(0, $r('app.string.tab_home')))

          TabContent() {
            RoomsPage({ navigation: this.navigation })
          }
          .tabBar(this.tabBar(1, $r('app.string.tab_rooms')))

          TabContent() {
            ScenePage()
          }
          .tabBar(this.tabBar(2, $r('app.string.tab_scenes')))

          TabContent() {
            ProfilePage({ appContext: this.appContext, navigation: this.navigation })
          }
          .tabBar(this.tabBar(3, $r('app.string.tab_profile')))
        }
        .barHeight(ShellTheme.TAB_BAR_HEIGHT)
        .barBackgroundColor($r('app.color.shell_tab_background'))
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
