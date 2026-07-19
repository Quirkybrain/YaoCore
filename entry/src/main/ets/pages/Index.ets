/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from '../service/I18nService';
import { AppColors, AppMetrics } from '../common/constants/AppTheme';
import { DevicePage } from './DevicePage';
import { HomePage } from './HomePage';
import { ScenePage } from './ScenePage';
import { SettingsPage } from './SettingsPage';
import { OnboardingPage } from './OnboardingPage';
import { AppStorageService } from '../service/AppStorageService';
import { DeviceControlPage } from './DeviceControlPage';
import { DeviceRepository } from '../service/DeviceRepository';
import { createDefaultGatewayState, GatewayState } from '../model/GatewayModel';
import { DeviceState } from '../model/DeviceModel';
import { SecurityService } from '../service/SecurityService';

class DeviceRouteParam {
  deviceId: string = '';

  constructor(deviceId: string) {
    this.deviceId = deviceId;
  }
}

@Entry
@Component
struct Index {
  private pathStack: NavPathStack = new NavPathStack();
  private repository: DeviceRepository = DeviceRepository.getInstance();
  private securityService: SecurityService = SecurityService.getInstance();
  private statusTimer: number = -1;
  private lastGatewayVisualKey: string = '';
  @State private currentTab: number = 0;
  @State private launchState: number = 0;
  @State private languageRevision: number = 0;
  @State private splashOpacity: number = 1;
  @State private splashScale: number = 0.96;
  @State private sloganOffset: number = 8;
  @State private onboardingPage: number = 0;
  @State private settingsPage: string = 'main';
  @State private gatewayState: GatewayState = createDefaultGatewayState();
  @State private boundGatewayId: string = '';
  @State private onlineDeviceCount: number = 0;
  @State private totalDeviceCount: number = 0;
  @State private capsuleScale: number = 1;
  @State private commandKeyReady: boolean = false;

  aboutToAppear(): void {
    this.startLaunch();
    this.startGatewayStatus();
    this.reloadCommandKeyState();
  }

  aboutToDisappear(): void {
    if (this.statusTimer >= 0) {
      clearInterval(this.statusTimer);
      this.statusTimer = -1;
    }
  }

  build() {
    if (this.launchState === 0) {
      this.loadingView()
    } else if (this.launchState === 1) {
      OnboardingPage({
        languageRevision: this.languageRevision,
        currentPage: $onboardingPage,
        onStart: () => {
          this.finishOnboarding();
        }
      })
    } else {
      this.appNavigation()
    }
  }

  onBackPress(): boolean {
    if (this.pathStack.size() > 0) {
      this.pathStack.pop(true);
      return true;
    }
    if (this.launchState === 1 && this.onboardingPage > 0) {
      this.onboardingPage -= 1;
      return true;
    }
    if (this.settingsPage !== 'main') {
      this.settingsPage = 'main';
      return true;
    }
    return false;
  }

  @Builder
  appNavigation() {
    Navigation(this.pathStack) {
      this.mainTabs()
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.destinationBuilder)
    .backgroundColor(AppColors.BACKGROUND)
  }

  @Builder
  destinationBuilder(name: string, param: Object) {
    NavDestination() {
      if (name === 'deviceControl') {
        DeviceControlPage({
          deviceId: (param as DeviceRouteParam).deviceId,
          languageRevision: this.languageRevision,
          onBack: () => {
            if (this.pathStack.size() > 0) this.pathStack.pop(true);
          }
        })
      }
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      if (this.pathStack.size() > 0) {
        this.pathStack.pop(true);
        return true;
      }
      return false;
    })
    .backgroundColor(AppColors.BACKGROUND)
  }

  @Builder
  mainTabs() {
    Column() {
      this.liveStatusCapsule()
      Tabs({ barPosition: BarPosition.End, index: this.currentTab }) {
        TabContent() {
          HomePage({
            languageRevision: this.languageRevision,
            onOpenDevices: () => {
              this.currentTab = 1;
            }
          })
        }
        .tabBar(this.tabBarItem(0, I18nService.t('首页'), $r('sys.symbol.house'), $r('sys.symbol.house_fill')))

        TabContent() {
          DevicePage({
            languageRevision: this.languageRevision,
            onCommandKeyChanged: (ready: boolean) => {
              this.commandKeyReady = ready;
            },
            onOpenDevice: (deviceId: string) => {
              this.pathStack.pushPathByName('deviceControl', new DeviceRouteParam(deviceId), true);
            }
          })
        }
        .tabBar(this.tabBarItem(1, I18nService.t('设备'), $r('sys.symbol.square_grid_2x2'), $r('sys.symbol.square_fill_grid_2x2')))

        TabContent() {
          ScenePage({ languageRevision: this.languageRevision })
        }
        .tabBar(this.tabBarItem(2, I18nService.t('场景'), $r('sys.symbol.bolt'), $r('sys.symbol.bolt_filled_on_circle')))

        TabContent() {
          SettingsPage({
            languageRevision: this.languageRevision,
            commandKeyReady: this.commandKeyReady,
            currentPage: $settingsPage,
            onCommandKeyChanged: (ready: boolean) => {
              this.commandKeyReady = ready;
            },
            onLanguageChanged: () => {
              this.languageRevision += 1;
            },
            onOpenDevices: () => {
              this.currentTab = 1;
            }
          })
        }
        .tabBar(this.tabBarItem(3, I18nService.t('我的'), $r('sys.symbol.person'), $r('sys.symbol.person_square_fill')))
      }
      .barMode(BarMode.Fixed)
      .barHeight(AppMetrics.TAB_BAR_HEIGHT)
      .barBackgroundColor('#D9FCFEFE')
      .barBackgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
      .layoutWeight(1)
      .onChange((index: number) => {
        this.currentTab = index;
      })
      .backgroundColor(AppColors.BACKGROUND)
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 145,
      colors: [[AppColors.BACKGROUND, 0.0], [AppColors.BACKGROUND_END, 1.0]]
    })
  }

  private async reloadCommandKeyState(): Promise<void> {
    await this.securityService.load();
    this.commandKeyReady = this.securityService.hasSessionSecret();
  }

  @Builder
  liveStatusCapsule() {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(40)
          .height(40)
          .backgroundColor(this.routeColor())
          .opacity(0.16)
          .borderRadius(20)
        Column()
          .width(30)
          .height(30)
          .backgroundColor('#16FFFFFF')
          .borderRadius(15)
        SymbolGlyph(this.boundGatewayId.length === 0 ? $r('sys.symbol.exclamationmark_triangle') :
          (this.gatewayState.localAvailable ? $r('sys.symbol.wifi') :
            (this.gatewayState.cloudAvailable ? $r('sys.symbol.cloud') : $r('sys.symbol.exclamationmark_triangle'))))
          .fontSize(18)
          .fontColor([this.routeColor()])
        Column()
          .width(7)
          .height(7)
          .backgroundColor(this.routeColor())
          .borderRadius(4)
          .position({ x: 31, y: 31 })
      }
      .width(42)
      .height(42)

      Column({ space: 3 }) {
        Text(this.gatewayDisplayName())
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.WHITE)
          .maxLines(1)
        Text(this.gatewayConnectionDetail())
          .fontSize(11)
          .fontColor('#B8FFFFFF')
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 1 }) {
        Text(this.capsuleValue())
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.routeColor())
          .maxLines(1)
        Text(this.capsuleLabel())
          .fontSize(9)
          .fontColor('#A8FFFFFF')
          .maxLines(1)
      }
      .height(38)
      .padding({ left: 12, right: 12 })
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#18FFFFFF')
      .border({ width: 1, color: '#24FFFFFF' })
      .borderRadius(19)
    }
    .width('92%')
    .height(64)
    .padding({ left: 12, right: 10 })
    .margin({ top: 8, bottom: 6 })
    .linearGradient({
      angle: 105,
      colors: [['#F21A2B33', 0.0], ['#E51D3D46', 0.58], ['#E5125B63', 1.0]]
    })
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 1, color: '#3DFFFFFF' })
    .borderRadius(32)
    .shadow({ radius: 20, color: '#33075E68', offsetX: 0, offsetY: 8 })
    .scale({ x: this.capsuleScale, y: this.capsuleScale })
    .onClick(() => {
      this.currentTab = 1;
      this.pulseCapsule();
    })
  }

  @Builder
  loadingView() {
    Column({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(110)
          .height(110)
          .backgroundColor(AppColors.PRIMARY_SOFT)
          .borderRadius(55)
        SymbolGlyph($r('sys.symbol.house_fill'))
          .fontSize(50)
          .fontColor([AppColors.PRIMARY])
      }
      .width(120)
      .height(120)

      Text(I18nService.isChinese() ? '爻构' : 'YaoCore')
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_PRIMARY)

      Text('爻联万物，构筑智慧。')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.PRIMARY_DARK)
        .textAlign(TextAlign.Center)
        .translate({ y: this.sloganOffset })

      Text('Connecting Things, Building Intelligence.')
        .fontSize(13)
        .fontColor(AppColors.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .translate({ y: this.sloganOffset })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppColors.BACKGROUND)
    .opacity(this.splashOpacity)
    .scale({ x: this.splashScale, y: this.splashScale })
  }

  @Builder
  tabBarItem(index: number, label: string, icon: Resource, selectedIcon: Resource) {
    Column({ space: 3 }) {
      Row() {
        SymbolGlyph(this.currentTab === index ? selectedIcon : icon)
          .fontSize(22)
          .fontColor([this.currentTab === index ? AppColors.PRIMARY : AppColors.TEXT_MUTED])
      }
      .width(42)
      .height(29)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.currentTab === index ? AppColors.PRIMARY_SOFT : '#00FFFFFF')
      .borderRadius(AppMetrics.PILL_RADIUS)

      Text(label)
        .fontSize(11)
        .fontWeight(this.currentTab === index ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.currentTab === index ? AppColors.PRIMARY_DARK : AppColors.TEXT_MUTED)
    }
    .width('100%')
    .height(AppMetrics.TAB_BAR_HEIGHT)
    .justifyContent(FlexAlign.Center)
  }

  private async startLaunch(): Promise<void> {
    this.getUIContext().animateTo({ duration: 420, curve: Curve.EaseOut }, () => {
      this.splashScale = 1;
      this.sloganOffset = 0;
    });
    await I18nService.initialize();
    this.languageRevision += 1;
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseIn }, () => {
        this.splashOpacity = 0;
        this.splashScale = 1.04;
      });
      setTimeout(() => this.resolveLaunchState(), 300);
    }, 1450);
  }

  private async resolveLaunchState(): Promise<void> {
    const completed = await AppStorageService.hasCompletedOnboarding();
    this.launchState = completed ? 2 : 1;
  }

  private async finishOnboarding(): Promise<void> {
    await AppStorageService.completeOnboarding();
    this.currentTab = 1;
    this.launchState = 2;
  }

  private async startGatewayStatus(): Promise<void> {
    await this.repository.load();
    this.updateGatewayStatus();
    this.statusTimer = setInterval(() => this.updateGatewayStatus(), 2000);
  }

  private updateGatewayStatus(): void {
    const nextGateway = this.repository.getGateway();
    const nextBoundGatewayId = this.repository.getBoundGatewayId();
    const devices: DeviceState[] = this.repository.getDevices();
    let onlineCount = 0;
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].isOnline) onlineCount += 1;
    }
    const visualKey = `${nextBoundGatewayId}|${nextGateway.localAvailable}|${nextGateway.cloudAvailable}|${onlineCount}|${devices.length}`;
    if (this.lastGatewayVisualKey.length > 0 && this.lastGatewayVisualKey !== visualKey) {
      this.pulseCapsule();
    }
    this.lastGatewayVisualKey = visualKey;
    this.gatewayState = nextGateway;
    this.boundGatewayId = nextBoundGatewayId;
    this.onlineDeviceCount = onlineCount;
    this.totalDeviceCount = devices.length;
  }

  private gatewayDisplayName(): string {
    if (this.boundGatewayId.length === 0) return I18nService.t('未添加网关');
    return this.gatewayState.gatewayName.length > 0 ? this.gatewayState.gatewayName : I18nService.t('家庭网关');
  }

  private gatewayConnectionDetail(): string {
    if (this.boundGatewayId.length === 0) return I18nService.t('点击添加或恢复网关');
    if (this.gatewayState.localAvailable) {
      const latency = this.gatewayState.latencyMs > 0 ? ` · ${this.gatewayState.latencyMs} ms` : '';
      return `${I18nService.t('局域网')} · ${this.gatewayState.localIp}${latency}`;
    }
    if (this.gatewayState.cloudAvailable) return I18nService.t('云端安全连接');
    return `${I18nService.t('离线')} · ${this.gatewayState.localIp}`;
  }

  private capsuleValue(): string {
    return this.boundGatewayId.length === 0 ? '+' : `${this.onlineDeviceCount}/${this.totalDeviceCount}`;
  }

  private capsuleLabel(): string {
    return this.boundGatewayId.length === 0 ? I18nService.t('添加') : I18nService.t('设备在线');
  }

  private routeColor(): string {
    if (this.gatewayState.localAvailable) return '#66F0C2';
    if (this.gatewayState.cloudAvailable) return '#77C7FF';
    return '#FFCA72';
  }

  private pulseCapsule(): void {
    this.getUIContext().animateTo({ duration: 110, curve: Curve.EaseOut }, () => {
      this.capsuleScale = 0.96;
    });
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 220, curve: Curve.Friction }, () => {
        this.capsuleScale = 1;
      });
    }, 115);
  }
}
