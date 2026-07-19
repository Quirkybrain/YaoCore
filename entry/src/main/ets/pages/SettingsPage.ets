/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { AppLanguage, I18nService } from '../service/I18nService';
import { AppColors, AppMetrics } from '../common/constants/AppTheme';
import { GatewayDefaults } from '../common/constants/DeviceConstants';
import { ControlResult, ControlRoute } from '../common/types/CommandTypes';
import { CloudConfig } from '../model/CloudModel';
import { LocalRouteConfig } from '../model/CommunicationModel';
import { createDefaultGatewayState, GatewayState } from '../model/GatewayModel';
import { AuthSession, createAnonymousSession } from '../model/UserModel';
import { SettingsViewModel } from '../viewmodel/SettingsViewModel';

@Component
export struct SettingsPage {
  private viewModel: SettingsViewModel = new SettingsViewModel();
  onOpenDevices: () => void = () => {};
  onLanguageChanged: () => void = () => {};
  onCommandKeyChanged: (ready: boolean) => void = () => {};
  @Prop languageRevision: number = 0;
  @Prop commandKeyReady: boolean = false;
  @State private gateway: GatewayState = createDefaultGatewayState();
  @State private session: AuthSession = createAnonymousSession();
  @State private localEnabled: boolean = false;
  @State private realLocalTransport: boolean = false;
  @State private gatewayIp: string = GatewayDefaults.LOCAL_IP;
  @State private gatewayPort: string = `${GatewayDefaults.LOCAL_PORT}`;
  @State private commandEndpoint: string = '';
  @State private shadowEndpoint: string = '';
  @State private accessToken: string = '';
  @State private tenantId: string = '';
  @State private iotdaEndpoint: string = '';
  @State private projectId: string = '';
  @State private cloudDeviceId: string = '';
  @State private boundGatewayId: string = '';
  @State private instanceId: string = '';
  @State private serviceId: string = GatewayDefaults.SERVICE_ID;
  @State private email: string = '';
  @State private password: string = '';
  @State private sessionSecret: string = '';
  @Link currentPage: string;
  @State private activeSection: string = '';
  @State private authMode: string = 'login';
  @State private hasLocalAccount: boolean = false;
  @State private showGatewayAdvanced: boolean = false;
  @State private showCloudAdvanced: boolean = false;
  @State private message: string = '';
  @State private localProbeMessage: string = I18nService.t('未检查');
  @State private gatewayLedMessage: string = I18nService.t('未检查');
  @State private cloudProbeMessage: string = I18nService.t('未检查');
  @State private cloudSyncMessage: string = I18nService.t('未同步');
  @State private statusSyncMessage: string = I18nService.t('未刷新');
  @State private diagnosticMessage: string = I18nService.t('未测试');
  @State private lastRouteText: string = I18nService.t('未连接');
  @State private lastLatencyText: string = '0ms';
  @State private languagePreference: AppLanguage = 'auto';
  @State private busyOperation: string = '';
  @State private deviceCount: number = 0;
  @State private onlineCount: number = 0;

  aboutToAppear(): void {
    this.reloadAsync();
  }

  build() {
    if (this.currentPage === 'account') {
      this.accountSubPage()
    } else if (this.currentPage === 'detail') {
      this.detailSubPage()
    } else {
      this.mainPage()
    }
  }

  @Builder
  mainPage() {
    Scroll() {
      Column({ space: 18 }) {
        Text(I18nService.t('我的'))
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .width('100%')

        this.profileHeader()
        this.menuGroups()
      }
      .padding({
        left: AppMetrics.PAGE_PADDING,
        right: AppMetrics.PAGE_PADDING,
        top: AppMetrics.PAGE_PADDING,
        bottom: 28
      })
    }
    .width('100%')
    .height('100%')
    .linearGradient({ angle: 145, colors: [[AppColors.BACKGROUND, 0.0], [AppColors.BACKGROUND_END, 1.0]] })
  }

  @Builder
  profileHeader() {
    Row({ space: 14 }) {
      Column() {
        Text(this.avatarText())
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.WHITE)
      }
      .width(62)
      .height(62)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.session.signedIn ? AppColors.PRIMARY : AppColors.TEXT_PRIMARY)
      .borderRadius(31)

      Column({ space: 5 }) {
        Text(this.session.signedIn ? this.session.displayName :
          (this.hasLocalAccount ? I18nService.t('解锁本机使用档案') : I18nService.t('创建本机使用档案')))
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .maxLines(1)
        Text(this.session.signedIn ? I18nService.t('本机档案已解锁') :
          (this.hasLocalAccount ? I18nService.t('点击本机解锁') : I18nService.t('仅用于本机名称显示')))
          .fontSize(13)
          .fontColor(AppColors.TEXT_SECONDARY)
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('>')
        .fontSize(18)
        .fontColor(AppColors.TEXT_MUTED)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(AppColors.SURFACE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .border({ width: 1, color: AppColors.GLASS_BORDER })
    .borderRadius(AppMetrics.CARD_RADIUS)
    .shadow({ radius: 14, color: AppColors.GLASS_SHADOW, offsetX: 0, offsetY: 5 })
    .onClick(() => {
      this.openAccountPage();
    })
  }

  @Builder
  menuGroups() {
    Column({ space: 16 }) {
      Column({ space: 8 }) {
        this.groupTitle(I18nService.t('家庭连接'))
        Column() {
          this.menuRow('gateway', I18nService.t('家'), I18nService.t('家庭网关'), this.gatewayMenuText(),
            this.gateway.localAvailable ? I18nService.t('已连接') : I18nService.t('未连接'), AppColors.PRIMARY)
          Divider().color(AppColors.BORDER).margin({ left: 58 })
          this.menuRow('cloud', I18nService.t('云'), I18nService.t('远程连接'), this.cloudMenuText(), this.cloudStatusText(), AppColors.ACCENT)
        }
        .width('100%')
        .backgroundColor(AppColors.SURFACE)
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .border({ width: 1, color: AppColors.GLASS_BORDER })
        .borderRadius(AppMetrics.CARD_RADIUS)
        .shadow({ radius: 8, color: AppColors.SHADOW, offsetX: 0, offsetY: 2 })
      }
      .width('100%')

      Column({ space: 8 }) {
        this.groupTitle(I18nService.t('隐私与安全'))
        Column() {
          this.menuRow('security', I18nService.t('盾'), I18nService.t('控制保护'),
            this.commandKeyReady ? I18nService.t('控制密钥已保存') : I18nService.t('设置控制密钥'),
            this.commandKeyReady ? I18nService.t('已保存') : I18nService.t('未设置'), AppColors.SUCCESS)
        }
        .width('100%')
        .backgroundColor(AppColors.SURFACE)
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .border({ width: 1, color: AppColors.GLASS_BORDER })
        .borderRadius(AppMetrics.CARD_RADIUS)
        .shadow({ radius: 8, color: AppColors.SHADOW, offsetX: 0, offsetY: 2 })
      }
      .width('100%')

      Column({ space: 8 }) {
        this.groupTitle(I18nService.t('应用'))
        Column() {
          this.menuRow('live', I18nService.t('态'), I18nService.t('设备状态通知'), I18nService.t('在通知栏查看设备状态'), '', AppColors.PRIMARY_DARK)
          Divider().color(AppColors.BORDER).margin({ left: 58 })
          this.menuRow('language', '文', I18nService.t('语言'), this.languagePreferenceText(), '', AppColors.ACCENT)
          Divider().color(AppColors.BORDER).margin({ left: 58 })
          this.menuRow('about', 'i', I18nService.t('关于 YaoCore'), I18nService.t('版本 1.1.0'), '', AppColors.TEXT_SECONDARY)
        }
        .width('100%')
        .backgroundColor(AppColors.SURFACE)
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .border({ width: 1, color: AppColors.GLASS_BORDER })
        .borderRadius(AppMetrics.CARD_RADIUS)
        .shadow({ radius: 8, color: AppColors.SHADOW, offsetX: 0, offsetY: 2 })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  groupTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppColors.TEXT_SECONDARY)
      .padding({ left: 4 })
      .width('100%')
  }

  @Builder
  menuRow(id: string, icon: string, title: string, subtitle: string, badge: string, color: string) {
    Row({ space: 12 }) {
      Column() {
        Text(icon)
          .fontSize(icon === 'i' ? 17 : 14)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.WHITE)
      }
      .width(34)
      .height(34)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(color)
      .borderRadius(10)

      Column({ space: 3 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .maxLines(1)
        Text(subtitle)
          .fontSize(12)
          .fontColor(AppColors.TEXT_MUTED)
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (badge.length > 0) {
        Text(badge)
          .fontSize(11)
          .fontColor(badge === I18nService.t('已连接') || badge === I18nService.t('已开启') ? AppColors.SUCCESS : AppColors.TEXT_MUTED)
          .maxLines(1)
      }
      Text('>')
        .fontSize(16)
        .fontColor(AppColors.TEXT_MUTED)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .onClick(() => {
      this.handleMenuClick(id, title);
    })
  }

  @Builder
  accountSubPage() {
    Scroll() {
      Column({ space: 22 }) {
        this.pageHeader(I18nService.t('本机使用档案'))

        Column({ space: 18 }) {
          Column() {
            Text(this.avatarText())
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.WHITE)
          }
          .width(76)
          .height(76)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(this.session.signedIn ? AppColors.PRIMARY : AppColors.TEXT_PRIMARY)
          .borderRadius(38)

          if (this.session.signedIn) {
            this.signedInAccountContent()
          } else {
            this.authFormContent()
          }
        }
        .width('100%')
        .padding({ left: 22, right: 22, top: 26, bottom: 22 })
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(AppColors.SURFACE)
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .border({ width: 1, color: AppColors.GLASS_BORDER })
        .borderRadius(AppMetrics.CARD_RADIUS)
        .shadow({ radius: 16, color: AppColors.GLASS_SHADOW, offsetX: 0, offsetY: 6 })

        if (!this.session.signedIn) {
          Button(I18nService.t('暂不解锁'))
            .height(42)
            .backgroundColor(Color.Transparent)
            .fontColor(AppColors.TEXT_SECONDARY)
            .onClick(() => {
              this.currentPage = 'main';
              this.message = '';
            })
        }
      }
      .padding({
        left: AppMetrics.PAGE_PADDING,
        right: AppMetrics.PAGE_PADDING,
        top: AppMetrics.PAGE_PADDING,
        bottom: 28
      })
    }
    .width('100%')
    .height('100%')
    .linearGradient({ angle: 145, colors: [[AppColors.BACKGROUND, 0.0], [AppColors.BACKGROUND_END, 1.0]] })
  }

  @Builder
  signedInAccountContent() {
    Column({ space: 14 }) {
      Column({ space: 5 }) {
        Text(this.session.displayName)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .maxLines(1)
        Text(this.session.email)
          .fontSize(13)
          .fontColor(AppColors.TEXT_SECONDARY)
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Center)

      if (this.message.length > 0) {
        this.feedbackBar()
      }

      Text(I18nService.t('该档案仅保存在本机，不是云端账号，不提供家庭成员身份或设备控制授权。'))
        .fontSize(12)
        .fontColor(AppColors.TEXT_MUTED)
        .width('100%')

      Button(I18nService.t('锁定本机档案'))
        .width('100%')
        .height(AppMetrics.CONTROL_HEIGHT)
        .backgroundColor(AppColors.DANGER_SOFT)
        .fontColor(AppColors.DANGER)
        .borderRadius(AppMetrics.INNER_RADIUS)
        .onClick(() => {
          this.handleLogout();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  authFormContent() {
    Column({ space: 14 }) {
      Column({ space: 5 }) {
        Text(this.authMode === 'register' ? I18nService.t('创建本机档案') : I18nService.t('解锁本机档案'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
        Text(I18nService.t('仅用于在本机显示使用者名称；不是云端账号，不提供家庭成员授权，也不限制设备控制。'))
          .fontSize(13)
          .fontColor(AppColors.TEXT_SECONDARY)
      }
      .alignItems(HorizontalAlign.Center)

      TextInput({ placeholder: I18nService.t('用户名'), text: this.email })
        .width('100%')
        .height(48)
        .padding({ left: 14, right: 14 })
        .backgroundColor(AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.INNER_RADIUS)
        .onChange((value: string) => {
          this.email = value;
        })
      TextInput({ placeholder: I18nService.t('密码（至少 8 位）'), text: this.password })
        .width('100%')
        .height(48)
        .padding({ left: 14, right: 14 })
        .type(InputType.Password)
        .backgroundColor(AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.INNER_RADIUS)
        .onChange((value: string) => {
          this.password = value;
        })

      if (this.message.length > 0) {
        this.feedbackBar()
      }

      Button(this.authMode === 'register' ? I18nService.t('创建并解锁') : I18nService.t('解锁本机档案'))
        .width('100%')
        .height(48)
        .backgroundColor(AppColors.PRIMARY)
        .fontColor(AppColors.WHITE)
        .fontSize(16)
        .borderRadius(AppMetrics.INNER_RADIUS)
        .onClick(() => {
          if (this.authMode === 'register') {
            this.handleRegister();
          } else {
            this.handleLogin();
          }
        })

    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  detailSubPage() {
    Scroll() {
      Column({ space: 16 }) {
        this.pageHeader(this.detailPageTitle())
        if (this.activeSection === 'gateway') {
          this.gatewayPanel()
        } else if (this.activeSection === 'cloud') {
          this.cloudPanel()
        } else if (this.activeSection === 'security') {
          this.securityPanel()
        } else if (this.activeSection === 'live') {
          this.livePanel()
        } else if (this.activeSection === 'language') {
          this.languagePanel()
        } else if (this.activeSection === 'about') {
          this.aboutPanel()
        }
        if (this.message.length > 0) {
          this.feedbackBar()
        }
      }
      .padding({
        left: AppMetrics.PAGE_PADDING,
        right: AppMetrics.PAGE_PADDING,
        top: AppMetrics.PAGE_PADDING,
        bottom: 28
      })
    }
    .width('100%')
    .height('100%')
    .linearGradient({ angle: 145, colors: [[AppColors.BACKGROUND, 0.0], [AppColors.BACKGROUND_END, 1.0]] })
  }

  @Builder
  pageHeader(title: string) {
    Row({ space: 12 }) {
      Button('<')
        .width(42)
        .height(42)
        .fontSize(20)
        .backgroundColor(AppColors.SURFACE)
        .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
        .border({ width: 1, color: AppColors.GLASS_BORDER })
        .fontColor(AppColors.TEXT_PRIMARY)
        .borderRadius(21)
        .onClick(() => {
          this.currentPage = 'main';
          this.activeSection = '';
          this.message = '';
          this.reload();
        })
      Text(title)
        .fontSize(23)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_PRIMARY)
        .layoutWeight(1)
        .maxLines(1)
    }
    .width('100%')
  }

  @Builder
  gatewayPanel() {
    Column({ space: 14 }) {
      this.statusCard(I18nService.t('家'),
        this.gateway.localAvailable ? I18nService.t('网关已连接') : I18nService.t('网关未连接'),
        this.gateway.localAvailable ? this.gateway.gatewayName : I18nService.t('前往设备页查找并连接网关'),
        this.gateway.localAvailable ? AppColors.SUCCESS : AppColors.TEXT_SECONDARY)

      if (!this.gateway.localAvailable) {
        Button(I18nService.t('前往设备页'))
          .width('100%')
          .height(AppMetrics.CONTROL_HEIGHT)
          .backgroundColor(AppColors.PRIMARY)
          .fontColor(AppColors.WHITE)
          .borderRadius(AppMetrics.INNER_RADIUS)
          .onClick(() => {
            this.currentPage = 'main';
            this.activeSection = '';
            this.onOpenDevices();
          })
      } else {
        this.simpleInfoRow(I18nService.t('网关地址'), this.gateway.localIp)
        Row({ space: 10 }) {
          this.rowBusyButton(I18nService.t('检查连接'), 'local-probe', true, () => {
            this.handleLocalProbe();
          })
          this.rowBusyButton(I18nService.t('刷新状态'), 'gateway-sync', false, () => {
            this.handleGatewayStatusSync();
          })
        }
      }

      Button(this.showGatewayAdvanced ? I18nService.t('收起网络设置') : I18nService.t('网络设置'))
        .width('100%')
        .height(42)
        .backgroundColor(Color.Transparent)
        .fontColor(AppColors.TEXT_SECONDARY)
        .onClick(() => {
          this.showGatewayAdvanced = !this.showGatewayAdvanced;
          this.message = '';
        })

      if (this.showGatewayAdvanced) {
        this.gatewayAdvancedPanel()
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor(AppColors.SURFACE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .border({ width: 1, color: AppColors.GLASS_BORDER })
    .borderRadius(AppMetrics.CARD_RADIUS)
    .shadow({ radius: 12, color: AppColors.GLASS_SHADOW, offsetX: 0, offsetY: 4 })
  }

  @Builder
  gatewayAdvancedPanel() {
    Column({ space: 12 }) {
      Divider().color(AppColors.BORDER)
      this.panelTitle(I18nService.t('网络设置'), I18nService.t('仅在自动连接失败时修改'))
      this.fieldLabel(I18nService.t('网关地址'))
      TextInput({ placeholder: I18nService.t('例如 192.168.1.10'), text: this.gatewayIp })
        .height(44)
        .padding({ left: 12, right: 12 })
        .backgroundColor(AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.INNER_RADIUS)
        .onChange((value: string) => {
          this.gatewayIp = value;
        })
      this.fieldLabel(I18nService.t('端口'))
      TextInput({ placeholder: '9200', text: this.gatewayPort })
        .height(44)
        .padding({ left: 12, right: 12 })
        .backgroundColor(AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.INNER_RADIUS)
        .onChange((value: string) => {
          this.gatewayPort = value;
        })

      this.optionRow(I18nService.t('优先使用家庭网络'), this.localEnabled, () => {
        this.localEnabled = !this.localEnabled;
      })
      this.optionRow(I18nService.t('允许直接连接网关'), this.realLocalTransport, () => {
        this.realLocalTransport = !this.realLocalTransport;
      })

      Button(I18nService.t('保存网络设置'))
        .width('100%')
        .height(AppMetrics.CONTROL_HEIGHT)
        .backgroundColor(AppColors.PRIMARY)
        .fontColor(AppColors.WHITE)
        .borderRadius(AppMetrics.INNER_RADIUS)
        .onClick(() => {
          this.saveLocalRoute();
        })

      Row({ space: 10 }) {
        this.rowBusyButton(I18nService.t('重新查找网关'), 'gateway-refresh', false, () => {
          this.handleRefresh();
        })
        this.rowBusyButton(I18nService.t('测试设备控制'), 'diagnostic', false, () => {
          this.handleDiagnosticCommand();
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  cloudPanel() {
    Column({ space: 14 }) {
      this.statusCard(I18nService.t('云'),
        this.cloudStatusText() === I18nService.t('已配置') ? I18nService.t('远程连接已设置') : I18nService.t('远程连接未设置'),
        this.cloudStatusText() === I18nService.t('已配置') ? I18nService.t('可在外出时查看和控制设备') : I18nService.t('设置后可在外出时控制设备'),
        this.cloudStatusText() === I18nService.t('已配置') ? AppColors.SUCCESS : AppColors.TEXT_SECONDARY)

      if (this.cloudStatusText() === I18nService.t('已配置')) {
        Row({ space: 10 }) {
          this.rowBusyButton(I18nService.t('检查连接'), 'cloud-probe', true, () => {
            this.handleCloudProbe();
          })
          this.rowBusyButton(I18nService.t('同步设备'), 'cloud-sync', false, () => {
            this.handleCloudSync();
          })
        }
      }

      Button(this.showCloudAdvanced ? I18nService.t('收起连接设置') :
        (this.cloudStatusText() === I18nService.t('已配置') ? I18nService.t('修改连接设置') : I18nService.t('开始设置')))
        .width('100%')
        .height(AppMetrics.CONTROL_HEIGHT)
        .backgroundColor(this.showCloudAdvanced ? AppColors.SURFACE_SOFT : AppColors.PRIMARY)
        .fontColor(this.showCloudAdvanced ? AppColors.TEXT_SECONDARY : AppColors.WHITE)
        .borderRadius(AppMetrics.INNER_RADIUS)
        .onClick(() => {
          this.showCloudAdvanced = !this.showCloudAdvanced;
          this.message = '';
        })

      if (this.showCloudAdvanced) {
        this.cloudAdvancedPanel()
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor(AppColors.SURFACE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .border({ width: 1, color: AppColors.GLASS_BORDER })
    .borderRadius(AppMetrics.CARD_RADIUS)
    .shadow({ radius: 12, color: AppColors.GLASS_SHADOW, offsetX: 0, offsetY: 4 })
  }

  @Builder
  cloudAdvancedPanel() {
    Column({ space: 10 }) {
      Divider().color(AppColors.BORDER)
      this.panelTitle(I18nService.t('连接信息'), I18nService.t('请填写服务提供方给出的信息'))
      this.fieldLabel(I18nService.t('服务地址'))
      TextInput({ placeholder: I18nService.t('HTTPS 地址'), text: this.iotdaEndpoint })
        .height(44)
        .padding({ left: 12, right: 12 })
        .backgroundColor(AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.INNER_RADIUS)
        .onChange((value: string) => {
          this.iotdaEndpoint = value;
        })
      this.fieldLabel(I18nService.t('项目 ID'))
      TextInput({ placeholder: 'Project ID', text: this.projectId })
        .height(44)
        .padding({ left: 12, right: 12 })
        .backgroundColor(AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.INNER_RADIUS)
        .onChange((value: string) => {
          this.projectId = value;
        })
      this.fieldLabel(I18nService.t('网关设备 ID'))
      TextInput({ placeholder: 'Device ID', text: this.cloudDeviceId })
        .height(44)
        .padding({ left: 12, right: 12 })
        .backgroundColor(AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.INNER_RADIUS)
        .onChange((value: string) => {
          this.cloudDeviceId = value;
        })
      this.fieldLabel(I18nService.t('实例 ID'))
      TextInput({ placeholder: I18nService.t('没有可留空'), text: this.instanceId })
        .height(44)
        .padding({ left: 12, right: 12 })
        .backgroundColor(AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.INNER_RADIUS)
        .onChange((value: string) => {
          this.instanceId = value;
        })
      this.fieldLabel(I18nService.t('服务 ID'))
      TextInput({ placeholder: 'Service ID', text: this.serviceId })
        .height(44)
        .padding({ left: 12, right: 12 })
        .backgroundColor(AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.INNER_RADIUS)
        .onChange((value: string) => {
          this.serviceId = value;
        })
      this.fieldLabel(I18nService.t('访问令牌'))
      TextInput({ placeholder: I18nService.t('请输入访问令牌'), text: this.accessToken })
        .height(44)
        .padding({ left: 12, right: 12 })
        .type(InputType.Password)
        .backgroundColor(AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.INNER_RADIUS)
        .onChange((value: string) => {
          this.accessToken = value;
        })

      this.fullBusyButton(I18nService.t('保存并检查连接'), 'cloud-save-check', () => {
        this.saveAndCheckCloud();
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  securityPanel() {
    Column({ space: 16 }) {
      this.statusCard(I18nService.t('盾'),
        this.commandKeyReady ? I18nService.t('控制密钥已保存') : I18nService.t('控制保护未开启'),
        I18nService.t('防止他人未经允许控制你的设备'),
        this.commandKeyReady ? AppColors.SUCCESS : AppColors.TEXT_SECONDARY)

      Column({ space: 8 }) {
        this.fieldLabel(I18nService.t('控制密钥'))
        TextInput({ placeholder: I18nService.t('至少输入 16 位'), text: this.sessionSecret })
          .width('100%')
          .height(46)
          .padding({ left: 12, right: 12 })
          .type(InputType.Password)
          .backgroundColor(AppColors.SURFACE_SOFT)
          .borderRadius(AppMetrics.INNER_RADIUS)
          .onChange((value: string) => {
            this.sessionSecret = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Button(I18nService.t('保存密钥'))
        .width('100%')
        .height(AppMetrics.CONTROL_HEIGHT)
        .backgroundColor(AppColors.PRIMARY)
        .fontColor(AppColors.WHITE)
        .borderRadius(AppMetrics.INNER_RADIUS)
        .onClick(() => {
          this.saveSecuritySecret();
        })
    }
    .width('100%')
    .padding(18)
    .backgroundColor(AppColors.SURFACE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .border({ width: 1, color: AppColors.GLASS_BORDER })
    .borderRadius(AppMetrics.CARD_RADIUS)
    .shadow({ radius: 12, color: AppColors.GLASS_SHADOW, offsetX: 0, offsetY: 4 })
  }

  @Builder
  livePanel() {
    Column({ space: 16 }) {
      this.statusCard(I18nService.t('态'), I18nService.t('设备状态通知'), I18nService.t('在通知栏快速查看家中设备'), AppColors.PRIMARY)
      Button(I18nService.t('开启通知'))
        .width('100%')
        .height(AppMetrics.CONTROL_HEIGHT)
        .backgroundColor(AppColors.PRIMARY)
        .fontColor(AppColors.WHITE)
        .borderRadius(AppMetrics.INNER_RADIUS)
        .onClick(() => {
          this.handleNotificationPermission();
        })
      Button(I18nService.t('查看通知效果'))
        .width('100%')
        .height(AppMetrics.CONTROL_HEIGHT)
        .backgroundColor(AppColors.SURFACE_SOFT)
        .fontColor(AppColors.PRIMARY_DARK)
        .borderRadius(AppMetrics.INNER_RADIUS)
        .onClick(() => {
          this.handleLivePreview();
        })
    }
    .width('100%')
    .padding(18)
    .backgroundColor(AppColors.SURFACE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .border({ width: 1, color: AppColors.GLASS_BORDER })
    .borderRadius(AppMetrics.CARD_RADIUS)
    .shadow({ radius: 12, color: AppColors.GLASS_SHADOW, offsetX: 0, offsetY: 4 })
  }

  @Builder
  aboutPanel() {
    Column({ space: 18 }) {
      Column() {
        Text('A')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.WHITE)
      }
      .width(72)
      .height(72)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(AppColors.PRIMARY)
      .borderRadius(20)

      Column({ space: 5 }) {
        Text('YaoCore')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
        Text(I18nService.t('让家庭控制更简单'))
          .fontSize(13)
          .fontColor(AppColors.TEXT_SECONDARY)
      }
      .alignItems(HorizontalAlign.Center)

      Divider().color(AppColors.BORDER)
      this.simpleInfoRow(I18nService.t('版本'), '1.1.0')
      this.simpleInfoRow(I18nService.t('适用系统'), 'HarmonyOS')
      this.simpleInfoRow(I18nService.t('开发者'), 'Quirkybrain')
    }
    .width('100%')
    .padding(22)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(AppColors.SURFACE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .border({ width: 1, color: AppColors.GLASS_BORDER })
    .borderRadius(AppMetrics.CARD_RADIUS)
    .shadow({ radius: 12, color: AppColors.GLASS_SHADOW, offsetX: 0, offsetY: 4 })
  }

  @Builder
  languagePanel() {
    Column({ space: 14 }) {
      this.panelTitle(I18nService.t('选择应用语言'),
        I18nService.t('中国大陆、台湾、香港和澳门默认使用简体中文，其他地区默认使用英文。'))
      this.languageOption('auto', I18nService.t('跟随系统地区'),
        I18nService.t('根据系统地区自动选择'))
      this.languageOption('zh-Hans', I18nService.t('简体中文'),
        I18nService.t('始终使用简体中文'))
      this.languageOption('en', I18nService.t('英文'), I18nService.t('始终使用英文'))
    }
    .width('100%')
    .padding(18)
    .backgroundColor(AppColors.SURFACE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .border({ width: 1, color: AppColors.GLASS_BORDER })
    .borderRadius(AppMetrics.CARD_RADIUS)
    .shadow({ radius: 12, color: AppColors.GLASS_SHADOW, offsetX: 0, offsetY: 4 })
  }

  @Builder
  languageOption(value: AppLanguage, title: string, subtitle: string) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
        Text(subtitle)
          .fontSize(12)
          .fontColor(AppColors.TEXT_MUTED)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.languagePreference === value) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(24)
          .fontColor([AppColors.SUCCESS])
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.languagePreference === value ? AppColors.PRIMARY_SOFT : AppColors.SURFACE_SOFT)
    .borderRadius(AppMetrics.INNER_RADIUS)
    .onClick(() => {
      this.changeLanguage(value);
    })
  }

  @Builder
  statusCard(icon: string, title: string, subtitle: string, color: string) {
    Row({ space: 13 }) {
      Column() {
        Text(icon)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.WHITE)
      }
      .width(42)
      .height(42)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(color)
      .borderRadius(13)

      Column({ space: 4 }) {
        Text(title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .maxLines(1)
        Text(subtitle)
          .fontSize(12)
          .fontColor(AppColors.TEXT_SECONDARY)
          .maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(AppColors.SURFACE_SOFT)
    .borderRadius(AppMetrics.INNER_RADIUS)
  }

  @Builder
  optionRow(title: string, enabled: boolean, onClick: () => void) {
    Row({ space: 12 }) {
      Text(title)
        .fontSize(14)
        .fontColor(AppColors.TEXT_PRIMARY)
        .layoutWeight(1)
      Button(enabled ? I18nService.t('已开启') : I18nService.t('已关闭'))
        .width(76)
        .height(34)
        .fontSize(12)
        .backgroundColor(enabled ? AppColors.SUCCESS_SOFT : AppColors.SURFACE_SOFT)
        .fontColor(enabled ? AppColors.SUCCESS : AppColors.TEXT_MUTED)
        .borderRadius(17)
        .onClick(onClick)
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  rowBusyButton(label: string, operation: string, primary: boolean, onClick: () => void) {
    Button() {
      Row({ space: 7 }) {
        if (this.busyOperation === operation) {
          LoadingProgress()
            .width(17)
            .height(17)
            .color(primary ? AppColors.WHITE : AppColors.PRIMARY_DARK)
        }
        Text(this.busyOperation === operation ? I18nService.t('处理中…') : label)
          .fontSize(13)
          .fontColor(primary ? AppColors.WHITE : AppColors.PRIMARY_DARK)
          .maxLines(1)
      }
      .justifyContent(FlexAlign.Center)
    }
    .layoutWeight(1)
    .height(AppMetrics.CONTROL_HEIGHT)
    .backgroundColor(primary ? AppColors.PRIMARY : AppColors.SURFACE_SOFT)
    .borderRadius(AppMetrics.INNER_RADIUS)
    .enabled(this.busyOperation.length === 0)
    .onClick(onClick)
  }

  @Builder
  fullBusyButton(label: string, operation: string, onClick: () => void) {
    Button() {
      Row({ space: 8 }) {
        if (this.busyOperation === operation) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(AppColors.WHITE)
        }
        Text(this.busyOperation === operation ? I18nService.t('处理中…') : label)
          .fontSize(14)
          .fontColor(AppColors.WHITE)
      }
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(AppMetrics.CONTROL_HEIGHT)
    .backgroundColor(AppColors.PRIMARY)
    .borderRadius(AppMetrics.INNER_RADIUS)
    .enabled(this.busyOperation.length === 0)
    .onClick(onClick)
  }

  @Builder
  panelTitle(title: string, subtitle: string) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.TEXT_PRIMARY)
        .width('100%')
      Text(subtitle)
        .fontSize(12)
        .fontColor(AppColors.TEXT_MUTED)
        .width('100%')
        .maxLines(2)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  fieldLabel(label: string) {
    Text(label)
      .fontSize(12)
      .fontColor(AppColors.TEXT_SECONDARY)
      .width('100%')
  }

  @Builder
  simpleInfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(AppColors.TEXT_SECONDARY)
      Blank()
      Text(value.length > 0 ? value : '--')
        .fontSize(14)
        .fontColor(AppColors.TEXT_PRIMARY)
        .maxLines(1)
    }
    .width('100%')
  }

  @Builder
  feedbackBar() {
    Row({ space: 8 }) {
      Text('·')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.PRIMARY)
      Text(this.message)
        .fontSize(13)
        .fontColor(AppColors.TEXT_SECONDARY)
        .layoutWeight(1)
        .maxLines(2)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 9, bottom: 9 })
    .backgroundColor(AppColors.SURFACE_SOFT)
    .borderRadius(AppMetrics.INNER_RADIUS)
  }

  private async reloadAsync(): Promise<void> {
    await this.viewModel.load();
    this.languagePreference = I18nService.getPreference();
    this.reload();
  }

  private reload(): void {
    this.gateway = this.viewModel.getGateway();
    this.session = this.viewModel.getSession();
    this.hasLocalAccount = this.viewModel.hasLocalAccount();
    this.deviceCount = this.viewModel.getDeviceCount();
    this.onlineCount = this.viewModel.getOnlineDeviceCount();
    const route = this.viewModel.getLocalRouteConfig();
    this.localEnabled = route.localEnabled;
    this.realLocalTransport = route.realTransportEnabled;
    this.gatewayIp = route.gatewayIp;
    this.gatewayPort = `${route.gatewayPort}`;
    this.boundGatewayId = route.gatewayId === undefined ? '' : route.gatewayId;
    const cloud = this.viewModel.getCloudConfig();
    this.commandEndpoint = cloud.commandEndpoint;
    this.shadowEndpoint = cloud.shadowEndpoint;
    this.accessToken = cloud.accessToken;
    this.tenantId = cloud.tenantId;
    this.iotdaEndpoint = cloud.iotdaEndpoint;
    this.projectId = cloud.projectId;
    this.cloudDeviceId = cloud.deviceId;
    this.instanceId = cloud.instanceId;
    this.serviceId = cloud.serviceId;
    this.applyLastResult(this.viewModel.getLastControlResult());
  }

  private avatarText(): string {
    if (!this.session.signedIn) {
      return I18nService.t('我');
    }
    const name = this.session.displayName.length > 0 ? this.session.displayName : this.session.email;
    return name.length > 0 ? name.substring(0, 1).toUpperCase() : I18nService.t('我');
  }

  private gatewayMenuText(): string {
    if (this.gateway.localAvailable) {
      return this.gateway.gatewayName.length > 0 ? this.gateway.gatewayName : I18nService.t('家庭网关');
    }
    return I18nService.t('前往设备页连接');
  }

  private cloudMenuText(): string {
    return this.cloudStatusText() === I18nService.t('已配置') ? I18nService.t('外出时也能控制设备') : I18nService.t('设置远程控制');
  }

  private detailPageTitle(): string {
    if (this.activeSection === 'gateway') {
      return I18nService.t('家庭网关');
    }
    if (this.activeSection === 'cloud') {
      return I18nService.t('远程连接');
    }
    if (this.activeSection === 'security') {
      return I18nService.t('控制保护');
    }
    if (this.activeSection === 'live') {
      return I18nService.t('设备状态通知');
    }
    if (this.activeSection === 'language') {
      return I18nService.t('语言');
    }
    return I18nService.t('关于 YaoCore');
  }

  private languagePreferenceText(): string {
    if (this.languagePreference === 'zh-Hans') {
      return I18nService.t('简体中文');
    }
    if (this.languagePreference === 'en') {
      return 'English';
    }
    return I18nService.t('跟随系统地区');
  }

  private async changeLanguage(preference: AppLanguage): Promise<void> {
    await I18nService.setPreference(preference);
    this.languagePreference = preference;
    this.onLanguageChanged();
  }

  private openAccountPage(): void {
    this.currentPage = 'account';
    this.authMode = this.hasLocalAccount ? 'login' : 'register';
    this.message = this.viewModel.consumeLocalProfileNotice();
  }

  private handleMenuClick(id: string, title: string): void {
    this.activeSection = id;
    this.currentPage = 'detail';
    this.message = '';
  }

  private cloudStatusText(): string {
    return (this.iotdaEndpoint.length > 0 || this.commandEndpoint.length > 0) && this.accessToken.length > 0 ? I18nService.t('已配置') : I18nService.t('未连接');
  }

  private routePreferenceText(): string {
    if (!this.localEnabled) {
      return this.cloudStatusText() === I18nService.t('已配置') ? I18nService.t('云端') : I18nService.t('离线');
    }
    return this.realLocalTransport ? I18nService.t('局域网') : I18nService.t('待连接');
  }

  private routeName(route: ControlRoute): string {
    if (route === ControlRoute.LOCAL) {
      return I18nService.t('局域网');
    }
    if (route === ControlRoute.CLOUD) {
      return I18nService.t('云端');
    }
    return I18nService.t('离线');
  }

  private readPort(): number {
    const value = Number(this.gatewayPort);
    if (value > 0 && value < 65536) {
      return value;
    }
    return GatewayDefaults.LOCAL_PORT;
  }

  private buildLocalRouteConfig(): LocalRouteConfig {
    return {
      localEnabled: this.localEnabled,
      gatewayIp: this.gatewayIp,
      gatewayPort: this.readPort(),
      realTransportEnabled: this.realLocalTransport,
      gatewayId: this.gateway.gatewayId,
      gatewayName: this.gateway.gatewayName
    };
  }

  private buildCloudConfig(): CloudConfig {
    return {
      commandEndpoint: this.commandEndpoint,
      shadowEndpoint: this.shadowEndpoint,
      accessToken: this.accessToken,
      tenantId: this.tenantId,
      iotdaEndpoint: this.iotdaEndpoint,
      projectId: this.projectId,
      deviceId: this.cloudDeviceId,
      gatewayId: this.boundGatewayId,
      instanceId: this.instanceId,
      serviceId: this.serviceId
    };
  }

  private applyLastResult(result: ControlResult): void {
    this.lastRouteText = this.routeName(result.route);
    this.lastLatencyText = `${result.latencyMs}ms`;
    this.diagnosticMessage = result.success ? I18nService.t('成功') : I18nService.t('失败');
  }

  private async handleRegister(): Promise<void> {
    const result = await this.viewModel.register(this.email, this.password);
    this.message = result.message;
    this.session = result.session;
    this.hasLocalAccount = this.viewModel.hasLocalAccount();
    if (result.success) {
      this.password = '';
    }
  }

  private async handleLogin(): Promise<void> {
    const result = await this.viewModel.login(this.email, this.password);
    this.message = result.message;
    this.session = result.session;
    if (result.success) {
      this.password = '';
    }
  }

  private async handleLogout(): Promise<void> {
    const result = await this.viewModel.logout();
    this.message = result.message;
    this.session = result.session;
    if (result.success) {
      this.authMode = 'login';
    }
  }

  private async handleRefresh(): Promise<void> {
    if (this.busyOperation.length > 0) return;
    this.busyOperation = 'gateway-refresh';
    this.message = I18nService.t('正在查找网关…');
    try {
      this.gateway = await this.viewModel.refreshGateway();
      if (this.gateway.localAvailable) {
        this.localEnabled = true;
        this.realLocalTransport = true;
        this.gatewayIp = this.gateway.localIp;
        await this.viewModel.saveLocalRoute(this.buildLocalRouteConfig());
        const ledResult = await this.viewModel.turnGatewayLedOn();
        this.gatewayLedMessage = ledResult.success ? I18nService.t('已点亮') : I18nService.t('点亮失败');
        this.applyLastResult(ledResult);
      }
      this.reload();
      this.message = this.gateway.localAvailable ? I18nService.t('网关已连接') : I18nService.t('没有找到网关，请检查家庭网络');
    } catch (error) {
      this.message = I18nService.t('扫描失败，请重试');
    } finally {
      this.busyOperation = '';
    }
  }

  private async handleLocalProbe(): Promise<void> {
    if (this.busyOperation.length > 0) return;
    this.busyOperation = 'local-probe';
    this.message = I18nService.t('正在检查连接…');
    try {
      const result = await this.viewModel.testLocalGateway(this.gatewayIp, this.readPort());
      this.localProbeMessage = result.success ? I18nService.t('已连接') : I18nService.t('连接失败');
      this.applyLastResult(result);
      if (result.success) {
        this.localEnabled = true;
        this.realLocalTransport = true;
        await this.viewModel.saveLocalRoute(this.buildLocalRouteConfig());
        const ledResult = await this.viewModel.turnGatewayLedOn();
        this.gatewayLedMessage = ledResult.success ? I18nService.t('已点亮') : I18nService.t('点亮失败');
        this.applyLastResult(ledResult);
        this.reload();
      }
      this.message = result.success ? I18nService.t('网关连接正常') : I18nService.t('连接失败，请检查网关和家庭网络');
    } catch (error) {
      this.message = I18nService.t('连接失败，请检查网关和家庭网络');
    } finally {
      this.busyOperation = '';
    }
  }

  private async handleGatewayStatusSync(): Promise<void> {
    if (this.busyOperation.length > 0) return;
    this.busyOperation = 'gateway-sync';
    this.message = I18nService.t('正在刷新…');
    try {
      const result = await this.viewModel.syncGatewayStatus();
      this.gateway = result.gateway;
      this.reload();
      this.statusSyncMessage = result.gateway.localAvailable ? I18nService.t('已刷新') : I18nService.t('网关未连接');
      this.message = result.gateway.localAvailable ? I18nService.t('设备状态已刷新') : I18nService.t('网关未连接');
    } catch (error) {
      this.message = I18nService.t('刷新失败，请重试');
    } finally {
      this.busyOperation = '';
    }
  }

  private async saveLocalRoute(): Promise<void> {
    await this.viewModel.saveLocalRoute(this.buildLocalRouteConfig());
    this.reload();
    this.message = I18nService.t('网络设置已保存');
  }

  private async handleDiagnosticCommand(): Promise<void> {
    if (this.busyOperation.length > 0) return;
    this.busyOperation = 'diagnostic';
    this.message = I18nService.t('正在测试…');
    try {
      await this.viewModel.saveLocalRoute(this.buildLocalRouteConfig());
      const result = await this.viewModel.sendDiagnosticCommand();
      this.applyLastResult(result);
      this.message = result.success ? I18nService.t('设备控制正常') : I18nService.t('控制失败，请检查设备连接');
    } catch (error) {
      this.message = I18nService.t('控制失败，请检查设备连接');
    } finally {
      this.busyOperation = '';
    }
  }

  private async saveCloudConfig(): Promise<void> {
    const config: CloudConfig = this.buildCloudConfig();
    await this.viewModel.saveCloudConfig(config);
    this.reload();
    this.message = this.cloudStatusText() === I18nService.t('已配置') ? I18nService.t('远程连接设置已保存') : I18nService.t('请补全连接信息');
  }

  private async saveAndCheckCloud(): Promise<void> {
    if (this.busyOperation.length > 0) return;
    this.busyOperation = 'cloud-save-check';
    this.message = I18nService.t('正在检查连接…');
    try {
      const config: CloudConfig = this.buildCloudConfig();
      await this.viewModel.saveCloudConfig(config);
      this.reload();
      if (this.cloudStatusText() !== I18nService.t('已配置')) {
        this.message = I18nService.t('请补全连接信息');
        return;
      }
      const result = await this.viewModel.testCloudConnection();
      this.applyLastResult(result);
      this.cloudProbeMessage = result.success ? I18nService.t('已连接') : I18nService.t('连接失败');
      this.message = result.success ? I18nService.t('远程连接正常') : I18nService.t('连接失败，请检查填写的信息');
    } catch (error) {
      this.message = I18nService.t('连接失败，请检查填写的信息');
    } finally {
      this.busyOperation = '';
    }
  }

  private async handleCloudSync(): Promise<void> {
    if (this.busyOperation.length > 0) return;
    this.busyOperation = 'cloud-sync';
    this.message = I18nService.t('同步中…');
    try {
      const config: CloudConfig = this.buildCloudConfig();
      await this.viewModel.saveCloudConfig(config);
      const result = await this.viewModel.syncDevicesToCloud();
      this.reload();
      this.cloudSyncMessage = result.success ? I18nService.t('同步成功') : I18nService.t('同步失败');
      this.message = result.success ? I18nService.t('设备已同步') : I18nService.t('同步失败，请检查远程连接');
    } catch (error) {
      this.message = I18nService.t('同步失败，请检查远程连接');
    } finally {
      this.busyOperation = '';
    }
  }

  private async handleCloudProbe(): Promise<void> {
    if (this.busyOperation.length > 0) return;
    this.busyOperation = 'cloud-probe';
    this.message = I18nService.t('正在检查连接…');
    try {
      const config: CloudConfig = this.buildCloudConfig();
      await this.viewModel.saveCloudConfig(config);
      const result = await this.viewModel.testCloudConnection();
      this.applyLastResult(result);
      this.reload();
      this.cloudProbeMessage = result.success ? I18nService.t('已连接') : I18nService.t('连接失败');
      this.message = result.success ? I18nService.t('远程连接正常') : I18nService.t('连接失败，请检查填写的信息');
    } catch (error) {
      this.message = I18nService.t('连接失败，请检查填写的信息');
    } finally {
      this.busyOperation = '';
    }
  }

  private async saveSecuritySecret(): Promise<void> {
    if (this.sessionSecret.trim().length < 16) {
      this.message = I18nService.t('控制密钥至少需要 16 位');
      return;
    }
    const saved = await this.viewModel.setSessionSecret(this.sessionSecret);
    this.sessionSecret = '';
    this.onCommandKeyChanged(saved && this.viewModel.hasSessionSecret());
    this.reload();
    this.message = saved ? I18nService.t('控制保护已开启') : I18nService.t('保存失败，请重试');
  }

  private async handleNotificationPermission(): Promise<void> {
    const enabled = await this.viewModel.enableLiveActivity();
    this.message = enabled ? I18nService.t('设备状态通知已开启') : I18nService.t('请在系统设置中允许通知');
  }

  private async handleLivePreview(): Promise<void> {
    const ok = await this.viewModel.publishLiveActivity();
    this.message = ok ? I18nService.t('通知已发送') : I18nService.t('请先允许应用发送通知');
  }
}
