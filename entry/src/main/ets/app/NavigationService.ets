/*
 * YaoCore C-28 navigation service and route contract.
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §17.1.1, §17.1.5; DES-B-C28-API
 *
 * Index.ets is the only @Entry page. Home/Rooms/Scenes/Profile are TabContent
 * pages; DeviceControl/Family/RoomManage/Provisioning/Settings/About are
 * NavDestination entries. Pages never call router.pushUrl directly.
 *
 * NavigationService only operates on NavPathStack and the selected-tab index;
 * it holds no business service.
 */

export enum AppRoute {
  HOME_TAB = 'home',
  ROOMS_TAB = 'rooms',
  SCENES_TAB = 'scenes',
  PROFILE_TAB = 'profile',
  DEVICE_CONTROL = 'device-control',
  FAMILY = 'family',
  ROOM_MANAGE = 'room-manage',
  PROVISIONING = 'provisioning',
  SETTINGS = 'settings',
  ABOUT = 'about'
}

export interface AppRouteParamsInit {
  familyId?: string;
  gatewayId?: string;
  deviceId?: string;
  roomId?: string;
  sceneId?: string;
  section?: string;
  mode?: string;
  expectedGatewayId?: string;
  highlightRoomId?: string;
}

export class AppRouteParams {
  readonly familyId?: string;
  readonly gatewayId?: string;
  readonly deviceId?: string;
  readonly roomId?: string;
  readonly sceneId?: string;
  readonly section?: string;
  readonly mode?: string;
  readonly expectedGatewayId?: string;
  readonly highlightRoomId?: string;

  constructor(init?: AppRouteParamsInit) {
    if (init === undefined) {
      return;
    }
    this.familyId = init.familyId;
    this.gatewayId = init.gatewayId;
    this.deviceId = init.deviceId;
    this.roomId = init.roomId;
    this.sceneId = init.sceneId;
    this.section = init.section;
    this.mode = init.mode;
    this.expectedGatewayId = init.expectedGatewayId;
    this.highlightRoomId = init.highlightRoomId;
  }
}

export class AppRouteValidation {
  static fromName(name: string): AppRoute | undefined {
    switch (name) {
      case AppRoute.HOME_TAB:
        return AppRoute.HOME_TAB;
      case AppRoute.ROOMS_TAB:
        return AppRoute.ROOMS_TAB;
      case AppRoute.SCENES_TAB:
        return AppRoute.SCENES_TAB;
      case AppRoute.PROFILE_TAB:
        return AppRoute.PROFILE_TAB;
      case AppRoute.DEVICE_CONTROL:
        return AppRoute.DEVICE_CONTROL;
      case AppRoute.FAMILY:
        return AppRoute.FAMILY;
      case AppRoute.ROOM_MANAGE:
        return AppRoute.ROOM_MANAGE;
      case AppRoute.PROVISIONING:
        return AppRoute.PROVISIONING;
      case AppRoute.SETTINGS:
        return AppRoute.SETTINGS;
      case AppRoute.ABOUT:
        return AppRoute.ABOUT;
      default:
        return undefined;
    }
  }

  static isTab(route: AppRoute): boolean {
    return AppRouteValidation.tabIndex(route) >= 0;
  }

  static tabIndex(route: AppRoute): number {
    switch (route) {
      case AppRoute.HOME_TAB:
        return 0;
      case AppRoute.ROOMS_TAB:
        return 1;
      case AppRoute.SCENES_TAB:
        return 2;
      case AppRoute.PROFILE_TAB:
        return 3;
      default:
        return -1;
    }
  }

  static tabRoute(index: number): AppRoute | undefined {
    switch (index) {
      case 0:
        return AppRoute.HOME_TAB;
      case 1:
        return AppRoute.ROOMS_TAB;
      case 2:
        return AppRoute.SCENES_TAB;
      case 3:
        return AppRoute.PROFILE_TAB;
      default:
        return undefined;
    }
  }

  /**
   * Route-level argument validation. Missing required parameters render the
   * ErrorState/UnknownRouteView, never a crash (DES-B §17.2).
   */
  static accepts(route: AppRoute, params?: AppRouteParams): boolean {
    if (route === AppRoute.DEVICE_CONTROL) {
      if (params === undefined) {
        return false;
      }
      return AppRouteValidation.nonEmpty(params.gatewayId) &&
        AppRouteValidation.nonEmpty(params.deviceId);
    }
    if (route === AppRoute.PROVISIONING) {
      if (params === undefined || params.mode === undefined) {
        return true;
      }
      return params.mode === 'NEW_GATEWAY' || params.mode === 'RECONFIGURE' ||
        params.mode === 'ROTATE_SECRET';
    }
    return true;
  }

  private static nonEmpty(value?: string): boolean {
    return value !== undefined && value.length > 0;
  }
}

export type TabChangeListener = (index: number) => void;

export class NavigationService {
  private readonly stack: NavPathStack;
  private selectedTabIndex: number = 0;
  private tabListener: TabChangeListener | undefined = undefined;

  constructor(stack: NavPathStack) {
    this.stack = stack;
  }

  getStack(): NavPathStack {
    return this.stack;
  }

  push(route: AppRoute, params?: AppRouteParams): void {
    if (AppRouteValidation.isTab(route)) {
      this.switchTab(route);
      return;
    }
    this.stack.pushPathByName(route, params === undefined ? new AppRouteParams() : params, false);
  }

  pop(): void {
    if (this.stack.size() > 0) {
      this.stack.pop();
    }
  }

  replace(route: AppRoute, params?: AppRouteParams): void {
    if (AppRouteValidation.isTab(route)) {
      this.switchTab(route);
      return;
    }
    this.stack.replacePathByName(route, params === undefined ? new AppRouteParams() : params, false);
  }

  popTo(route: AppRoute): void {
    if (AppRouteValidation.isTab(route)) {
      return;
    }
    this.stack.popToName(route, false);
  }

  switchTab(route: AppRoute): void {
    const index = AppRouteValidation.tabIndex(route);
    if (index < 0) {
      return;
    }
    if (this.stack.size() > 0) {
      this.stack.clear(false);
    }
    this.selectedTabIndex = index;
    this.notifyTab();
  }

  /** Called by Tabs.onChange; does not clear the stack. */
  selectTabIndex(index: number): void {
    if (AppRouteValidation.tabRoute(index) === undefined) {
      return;
    }
    this.selectedTabIndex = index;
    this.notifyTab();
  }

  getSelectedTab(): AppRoute {
    const route = AppRouteValidation.tabRoute(this.selectedTabIndex);
    return route === undefined ? AppRoute.HOME_TAB : route;
  }

  getSelectedTabIndex(): number {
    return this.selectedTabIndex;
  }

  setTabChangeListener(listener: TabChangeListener | undefined): void {
    this.tabListener = listener;
  }

  /** Returns true when the event was consumed (a destination was popped). */
  onBack(): boolean {
    if (this.stack.size() > 0) {
      this.stack.pop();
      return true;
    }
    return false;
  }

  private notifyTab(): void {
    const listener = this.tabListener;
    if (listener !== undefined) {
      listener(this.selectedTabIndex);
    }
  }
}
