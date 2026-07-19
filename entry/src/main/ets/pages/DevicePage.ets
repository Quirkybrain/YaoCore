/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from '../service/I18nService';
import { AppColors, AppMetrics, AppTypography } from '../common/constants/AppTheme';
import { DeviceDraft, DeviceState, DeviceType } from '../model/DeviceModel';
import {
  BleProvisioningDevice,
  BleProvisioningProgress,
  BleProvisioningResult,
  BleWiFiNetwork
} from '../model/BleProvisioningModel';
import {
  createDefaultGatewayState,
  DiscoveredDevice,
  DiscoveredGateway,
  GatewayState,
  PendingGatewayBindingState
} from '../model/GatewayModel';
import { AppStorageService } from '../service/AppStorageService';
import { SecurityService } from '../service/SecurityService';
import { BleProvisioningViewModel } from '../viewmodel/BleProvisioningViewModel';
import { DeviceViewModel } from '../viewmodel/DeviceViewModel';

@Component
export struct DevicePage {
  private viewModel: DeviceViewModel = new DeviceViewModel();
  private bleViewModel: BleProvisioningViewModel = new BleProvisioningViewModel();
  private securityService: SecurityService = SecurityService.getInstance();
  private stateRefreshTimer: number = -1;
  private bleOperationId: number = 0;
  private pageActive: boolean = false;
  @Prop languageRevision: number = 0;
  onCommandKeyChanged: (ready: boolean) => void = () => {};
  onOpenDevice: (deviceId: string) => void = () => {};
  @State private devices: DeviceState[] = [];
  @State private discovered: DiscoveredDevice[] = [];
  @State private discoveredGateways: DiscoveredGateway[] = [];
  @State private boundGatewayId: string = '';
  @State private gateway: GatewayState = createDefaultGatewayState();
  @State private message: string = I18nService.t('设备一目了然');
  @State private sceneCleanupNotice: string = '';
  @State private keyword: string = '';
  @State private manualExpanded: boolean = false;
  @State private hasScannedGateways: boolean = false;
  @State private hasScannedDevices: boolean = false;
  @State private scanningGateways: boolean = false;
  @State private scanningDevices: boolean = false;
  @State private bleExpanded: boolean = false;
  @State private bleScanning: boolean = false;
  @State private bleProvisioning: boolean = false;
  @State private scanningWiFiNetworks: boolean = false;
  @State private syncingDevices: boolean = false;
  @State private gatewayDetailsExpanded: boolean = false;
  @State private deletingGateway: boolean = false;
  @State private showGatewayRemovalDialog: boolean = false;
  @State private pendingGatewayRemovalId: string = '';
  @State private pendingGatewayRemovalName: string = '';
  @State private bleDevices: BleProvisioningDevice[] = [];
  @State private wifiNetworks: BleWiFiNetwork[] = [];
  @State private selectedBleDeviceId: string = '';
  @State private wifiSsid: string = '';
  @State private wifiPassword: string = '';
  @State private provisioningCode: string = '';
  @State private bleMessage: string = I18nService.t('首次使用时，通过蓝牙把 2.4 GHz Wi-Fi 安全发送给网关');
  @State private bleProgress: number = 0;
  @State private bleFailed: boolean = false;
  @State private pendingGatewayBinding: boolean = false;
  @State private commandKeyReady: boolean = false;
  @State private editingCommandKey: boolean = false;
  @State private commandSecretInput: string = '';
  @State private draftName: string = '';
  @State private draftRoom: string = '';
  @State private draftBrand: string = '';
  @State private draftType: DeviceType = DeviceType.LIGHT;
  private pendingGatewayId: string = '';
  private pendingGatewayName: string = '';
  private pendingGatewayIp: string = '';
  private pendingGatewayProtocol: string = '';
  private pendingRetryAfter: number = 0;
  private pendingAutoRetryCount: number = 0;
  private pendingAutomaticRetryBlocked: boolean = false;
  private static readonly PENDING_RETRY_BASE_MS: number = 8000;
  private static readonly PENDING_RETRY_MAX_MS: number = 60000;
  private static readonly PENDING_RETRY_MAX_EXPONENT: number = 3;
  private static readonly MAX_PENDING_AUTO_RETRIES: number = 3;

  aboutToAppear(): void {
    this.pageActive = true;
    this.reloadAsync();
    this.startStateRefresh();
  }

  aboutToDisappear(): void {
    this.pageActive = false;
    this.bleOperationId += 1;
    this.stopStateRefresh();
    this.bleViewModel.disconnect();
    this.wifiPassword = '';
    this.provisioningCode = '';
    this.bleScanning = false;
    this.bleProvisioning = false;
    this.scanningWiFiNetworks = false;
  }

  build() {
    Scroll() {
      Column({ space: AppMetrics.SECTION_GAP }) {
        this.pageHeader()
        if (this.sceneCleanupNotice.length > 0) {
          this.cleanupNotice()
        }
        this.deviceManager()
        this.deviceRegistry()
      }
      .padding(AppMetrics.PAGE_PADDING)
    }
    .width('100%')
    .height('100%')
    .linearGradient({ angle: 145, colors: [[AppColors.BACKGROUND, 0.0], [AppColors.BACKGROUND_END, 1.0]] })
    .bindSheet($$this.showGatewayRemovalDialog, this.gatewayRemovalSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: false,
      showClose: false,
      blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
      maskColor: '#66000000',
      onDisappear: () => {
        if (!this.deletingGateway) {
          this.pendingGatewayRemovalId = '';
          this.pendingGatewayRemovalName = '';
        }
      }
    })
  }

  @Builder
  pageHeader() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text(I18nService.t('设备'))
            .fontSize(AppTypography.PAGE_TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text(this.message)
            .fontSize(AppTypography.CAPTION)
            .fontColor(AppColors.TEXT_SECONDARY)
            .maxLines(2)
        }
        Blank()
        this.statusPill(this.onlineSummary(), AppColors.SUCCESS)
      }
      .width('100%')

      Search({ value: this.keyword, placeholder: I18nService.t('搜索设备或房间') })
        .height(42)
        .backgroundColor(AppColors.GLASS_STRONG)
        .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
        .border({ width: 1, color: AppColors.GLASS_BORDER })
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onChange((value: string) => {
          this.keyword = value;
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  deviceManager() {
    Column({ space: AppMetrics.CARD_GAP }) {
      if (this.boundGatewayId.length === 0) {
        this.bleProvisioningCard()
        this.gatewayDiscoveryCard()
      } else {
        this.connectedGatewayCard()
      }
      this.deviceDiscoveryCard()
    }
    .width('100%')
  }

  @Builder
  connectedGatewayCard() {
    Column({ space: 12 }) {
      Row({ space: 13 }) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(46)
            .height(46)
            .backgroundColor(this.gatewayStatusColor())
            .opacity(0.14)
            .borderRadius(23)
          SymbolGlyph(this.gateway.localAvailable ? $r('sys.symbol.wifi') :
            (this.gateway.cloudAvailable ? $r('sys.symbol.cloud') : $r('sys.symbol.exclamationmark_triangle')))
            .fontSize(22)
            .fontColor([this.gatewayStatusColor()])
        }
        .width(46)
        .height(46)

        Column({ space: 4 }) {
          Text(I18nService.t('当前网关'))
            .fontSize(AppTypography.CAPTION)
            .fontColor(AppColors.TEXT_MUTED)
          Text(this.gateway.gatewayName)
            .fontSize(AppTypography.CARD_TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT_PRIMARY)
            .maxLines(1)
          Text(this.connectedGatewayDetail())
            .fontSize(AppTypography.CAPTION)
            .fontColor(AppColors.TEXT_SECONDARY)
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 5 }) {
          Text(this.gatewayConnectionLabel())
            .fontSize(AppTypography.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.gatewayStatusColor())
            .padding({ left: 11, right: 11, top: 7, bottom: 7 })
            .backgroundColor(this.gateway.localAvailable || this.gateway.cloudAvailable ?
              AppColors.SUCCESS_SOFT : AppColors.WARNING_SOFT)
            .borderRadius(AppMetrics.PILL_RADIUS)
          Text(this.gatewayDetailsExpanded ? I18nService.t('收起管理') : I18nService.t('点击管理'))
            .fontSize(AppTypography.CAPTION)
            .fontColor(AppColors.TEXT_MUTED)
        }
      }
      .width('100%')
      .onClick(() => {
        this.gatewayDetailsExpanded = !this.gatewayDetailsExpanded;
      })

      if (this.gatewayDetailsExpanded) {
        Divider().color(AppColors.GLASS_BORDER)
        Column({ space: 8 }) {
          this.gatewayManagementRow(I18nService.t('网关标识'), this.boundGatewayId)
          this.gatewayManagementRow(I18nService.t('网关地址'), `${this.gateway.localIp}:${this.gateway.port}`)
          Text(I18nService.t('删除入口仅解除本机绑定，不会恢复开发板出厂设置'))
            .width('100%')
            .fontSize(AppTypography.CAPTION)
            .fontColor(AppColors.TEXT_MUTED)
          Button(this.deletingGateway ? I18nService.t('处理中…') : I18nService.t('确认删除网关'))
            .width('100%')
            .height(42)
            .enabled(!this.deletingGateway)
            .backgroundColor(AppColors.SURFACE_SOFT)
            .fontColor(AppColors.DANGER)
            .borderRadius(AppMetrics.CARD_RADIUS)
            .onClick(() => {
              this.showGatewayRemovalWarning();
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(AppMetrics.CARD_PADDING)
    .backgroundColor(AppColors.GLASS_STRONG)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .border({ width: 1, color: AppColors.GLASS_BORDER })
    .borderRadius(AppMetrics.CARD_RADIUS)
    .shadow({ radius: 12, color: AppColors.GLASS_SHADOW, offsetX: 0, offsetY: 4 })
  }

  @Builder
  gatewayManagementRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(AppTypography.CAPTION).fontColor(AppColors.TEXT_MUTED)
      Blank()
      Text(value).fontSize(AppTypography.CAPTION).fontColor(AppColors.TEXT_SECONDARY).maxLines(1)
    }
    .width('100%')
  }

  @Builder
  gatewayRemovalSheet() {
    Column({ space: 14 }) {
      Text(I18nService.t('是否确认删除网关？'))
        .width('100%')
        .fontSize(AppTypography.SECTION_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_PRIMARY)
      Text(I18nService.isChinese() ? `即将从本机删除“${this.pendingGatewayRemovalName}”` :
        `“${this.pendingGatewayRemovalName}” will be removed from this phone`)
        .width('100%')
        .fontSize(AppTypography.BODY)
        .fontColor(AppColors.TEXT_SECONDARY)
      Column({ space: 9 }) {
        this.gatewayRemovalRisk(I18nService.t('设备将从 App 移除，无法继续控制或查看状态'))
        this.gatewayRemovalRisk(I18nService.t('相关场景动作会被清理，远程控制将停止'))
        this.gatewayRemovalRisk(I18nService.t('本机保存的网关控制密钥会被清除'))
        this.gatewayRemovalRisk(I18nService.t('网关 Wi-Fi、板载配置和实体设备不会恢复出厂'))
      }
      .width('100%')
      .padding(14)
      .backgroundColor(AppColors.WARNING_SOFT)
      .borderRadius(AppMetrics.CARD_RADIUS)
      Text(I18nService.t('重新使用时，需要再次保存控制密钥并绑定网关'))
        .width('100%')
        .fontSize(AppTypography.CAPTION)
        .fontColor(AppColors.TEXT_MUTED)
      Row({ space: 10 }) {
        Button(I18nService.t('取消'))
          .layoutWeight(1)
          .height(44)
          .enabled(!this.deletingGateway)
          .backgroundColor(AppColors.SURFACE_SOFT)
          .fontColor(AppColors.TEXT_SECONDARY)
          .borderRadius(AppMetrics.CARD_RADIUS)
          .onClick(() => {
            this.showGatewayRemovalDialog = false;
          })
        Button(this.deletingGateway ? I18nService.t('处理中…') : I18nService.t('仍要删除'))
          .layoutWeight(1)
          .height(44)
          .enabled(!this.deletingGateway)
          .backgroundColor(AppColors.DANGER)
          .fontColor(AppColors.SURFACE)
          .borderRadius(AppMetrics.CARD_RADIUS)
          .onClick(() => {
            this.handleRemoveGateway(this.pendingGatewayRemovalId);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 24, bottom: 28 })
  }

  @Builder
  gatewayRemovalRisk(text: string) {
    Row({ space: 9 }) {
      Text('•').fontSize(AppTypography.BODY).fontColor(AppColors.WARNING)
      Text(text).layoutWeight(1).fontSize(AppTypography.CAPTION).fontColor(AppColors.TEXT_SECONDARY)
    }
    .width('100%')
  }

  @Builder
  bleProvisioningCard() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text(I18nService.t('网关配网'))
            .fontSize(AppTypography.CARD_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text(this.bleMessage)
            .fontSize(AppTypography.CAPTION)
            .fontColor(this.bleProvisioning ? AppColors.PRIMARY : AppColors.TEXT_MUTED)
            .maxLines(2)
        }
        .layoutWeight(1)
        Button(this.bleExpanded ? I18nService.t('收起') : I18nService.t('开始配网'))
          .height(38)
          .padding({ left: 14, right: 14 })
          .backgroundColor(this.bleExpanded ? AppColors.SURFACE_SOFT : AppColors.PRIMARY)
          .fontColor(this.bleExpanded ? AppColors.PRIMARY : AppColors.SURFACE)
          .borderRadius(AppMetrics.CARD_RADIUS)
          .onClick(() => {
            if (this.bleExpanded) {
              this.cancelBleSession();
              this.bleExpanded = false;
              this.bleMessage = I18nService.t('已取消蓝牙配网，可随时重新开始');
            } else {
              this.bleExpanded = true;
              this.bleMessage = this.commandKeyReady ?
                I18nService.t('请搜索正在配网的 YaoCore 网关') : I18nService.t('请先保存开发板屏幕对应的控制密钥');
            }
          })
      }
      .width('100%')

      if (this.bleExpanded) {
        this.provisioningGuideStep(
          '1',
          I18nService.t('步骤一：保存控制密钥'),
          this.commandKeyReady,
          !this.commandKeyReady || this.editingCommandKey
        )

        if (!this.commandKeyReady || this.editingCommandKey) {
          this.commandKeySetup()
        } else {
          this.savedCommandKeyCard()
        }

        this.provisioningGuideStep(
          '2',
          I18nService.t('步骤二：输入 PoP 完成 BLE 配网'),
          this.boundGatewayId.length > 0,
          this.commandKeyReady && !this.editingCommandKey
        )

        if (!this.commandKeyReady || this.editingCommandKey) {
          Text(I18nService.t('请先保存控制密钥'))
            .fontSize(AppTypography.CAPTION)
            .fontColor(AppColors.WARNING)
            .width('100%')
            .padding(10)
            .backgroundColor(AppColors.WARNING_SOFT)
            .borderRadius(AppMetrics.INNER_RADIUS)
        } else {
          Button(this.bleScanning ? I18nService.t('正在搜索…') : I18nService.t('搜索附近网关'))
            .width('100%')
            .height(40)
            .enabled(!this.bleScanning && !this.bleProvisioning && !this.scanningWiFiNetworks)
            .backgroundColor(!this.bleScanning ? AppColors.TEXT_PRIMARY : AppColors.BORDER)
            .fontColor(AppColors.SURFACE)
            .borderRadius(AppMetrics.CARD_RADIUS)
            .onClick(() => {
              this.handleBleScan();
            })

          if (this.bleScanning) {
            this.scanLoading(I18nService.t('正在搜索 YaoCore-GW 网关（约 8 秒）'))
          } else if (this.bleDevices.length > 0) {
            ForEach(this.bleDevices, (device: BleProvisioningDevice) => {
              this.bleGatewayRow(device)
            }, (device: BleProvisioningDevice) => device.deviceId)
          }

          if (this.selectedBleDeviceId.length > 0) {
            this.bleCredentialForm()
          }
          if (!this.bleScanning && !this.scanningWiFiNetworks && !this.bleProvisioning && this.bleMessage.length > 0) {
            this.bleOutcomeBanner()
          }
          if (this.pendingGatewayBinding && !this.bleProvisioning) {
            Button(I18nService.t('继续完成网关绑定'))
              .width('100%')
              .height(42)
              .backgroundColor(AppColors.PRIMARY)
              .fontColor(AppColors.SURFACE)
              .borderRadius(AppMetrics.CARD_RADIUS)
              .onClick(() => { this.retryPendingGatewayBinding(); })
          }
        }
      }
    }
    .width('100%')
    .padding(AppMetrics.CARD_PADDING)
    .backgroundColor(AppColors.SURFACE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .borderRadius(AppMetrics.CARD_RADIUS)
    .border({ width: 1, color: AppColors.GLASS_BORDER })
    .shadow({ radius: 12, color: AppColors.GLASS_SHADOW, offsetX: 0, offsetY: 4 })
  }

  @Builder
  provisioningGuideStep(
    stepNumber: string,
    title: string,
    completed: boolean,
    active: boolean
  ) {
    Row({ space: 12 }) {
      Text(completed ? '✓' : stepNumber)
        .width(34)
        .height(34)
        .fontSize(AppTypography.BODY)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.SURFACE)
        .textAlign(TextAlign.Center)
        .backgroundColor(completed ? AppColors.SUCCESS : (active ? AppColors.PRIMARY : AppColors.TEXT_MUTED))
        .borderRadius(17)
      Text(title)
        .fontSize(AppTypography.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.TEXT_PRIMARY)
        .layoutWeight(1)
      Text(I18nService.t(completed ? '已完成' : '待完成'))
        .fontSize(AppTypography.CAPTION)
        .fontColor(completed ? AppColors.SUCCESS : (active ? AppColors.PRIMARY : AppColors.TEXT_MUTED))
    }
    .width('100%')
    .padding(10)
    .backgroundColor(completed ? AppColors.SUCCESS_SOFT : (active ? AppColors.PRIMARY_SOFT : AppColors.SURFACE_SOFT))
    .border({ width: 1, color: completed ? AppColors.SUCCESS : (active ? AppColors.PRIMARY : AppColors.BORDER) })
    .borderRadius(AppMetrics.INNER_RADIUS)
  }

  @Builder
  savedCommandKeyCard() {
    Row({ space: 10 }) {
      Text(I18nService.t('控制密钥已保存'))
        .fontSize(AppTypography.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.SUCCESS)
      .layoutWeight(1)
      Button(I18nService.t('更换控制密钥'))
        .height(34)
        .padding({ left: 12, right: 12 })
        .enabled(!this.bleScanning && !this.bleProvisioning && !this.scanningWiFiNetworks)
        .backgroundColor(AppColors.SURFACE)
        .fontColor(AppColors.PRIMARY)
        .border({ width: 1, color: AppColors.PRIMARY })
        .borderRadius(AppMetrics.PILL_RADIUS)
        .onClick(() => {
          this.editingCommandKey = true;
          this.commandSecretInput = '';
          this.bleMessage = I18nService.t('输入新的控制密钥并保存，或取消更换');
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(AppColors.SUCCESS_SOFT)
    .borderRadius(AppMetrics.INNER_RADIUS)
  }

  @Builder
  commandKeySetup() {
    Column({ space: 10 }) {
      Text(I18nService.t('安全控制密钥'))
        .fontSize(AppTypography.CARD_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.TEXT_PRIMARY)
        .width('100%')
      TextInput({ placeholder: I18nService.t('至少 16 位控制密钥'), text: this.commandSecretInput })
        .height(42)
        .type(InputType.Password)
        .backgroundColor(AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onChange((value: string) => {
          this.commandSecretInput = value;
        })
      Row({ space: 8 }) {
        if (this.editingCommandKey && this.commandKeyReady) {
          Button(I18nService.t('取消更换'))
            .layoutWeight(1)
            .height(40)
            .backgroundColor(AppColors.SURFACE)
            .fontColor(AppColors.TEXT_SECONDARY)
            .border({ width: 1, color: AppColors.BORDER })
            .borderRadius(AppMetrics.CARD_RADIUS)
            .onClick(() => {
              this.editingCommandKey = false;
              this.commandSecretInput = '';
              this.bleMessage = I18nService.t('控制密钥保持不变，可继续步骤二');
            })
        }
        Button(I18nService.t(this.editingCommandKey ? '保存新的控制密钥' : '保存密钥并继续'))
          .layoutWeight(1)
          .height(40)
          .enabled(this.commandSecretInput.trim().length >= 16)
          .backgroundColor(this.commandSecretInput.trim().length >= 16 ? AppColors.PRIMARY : AppColors.BORDER)
          .fontColor(this.commandSecretInput.trim().length >= 16 ? AppColors.SURFACE : AppColors.TEXT_MUTED)
          .borderRadius(AppMetrics.CARD_RADIUS)
          .onClick(() => {
            this.saveInlineCommandKey();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(AppColors.PRIMARY_SOFT)
    .borderRadius(AppMetrics.CARD_RADIUS)
  }

  @Builder
  bleOutcomeBanner() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        if (this.bleFailed) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(22)
            .fontColor([AppColors.DANGER])
        } else {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(22)
            .fontColor([AppColors.PRIMARY])
        }
        Text(this.bleMessage)
          .fontSize(AppTypography.BODY)
          .fontColor(this.bleFailed ? AppColors.DANGER : AppColors.TEXT_PRIMARY)
          .layoutWeight(1)
          .maxLines(5)
      }
      .width('100%')

      if (this.bleFailed && !this.pendingGatewayBinding && this.selectedBleDeviceId.length > 0) {
        Button(I18nService.t('重新尝试 BLE 配网'))
          .width('100%')
          .height(40)
          .enabled(!this.bleProvisioning && !this.scanningWiFiNetworks && !this.bleScanning)
          .backgroundColor(AppColors.DANGER)
          .fontColor(AppColors.SURFACE)
          .borderRadius(AppMetrics.CARD_RADIUS)
          .onClick(() => {
            this.retryBleProvisioning();
          })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.bleFailed ? AppColors.DANGER_SOFT : AppColors.PRIMARY_SOFT)
    .borderRadius(AppMetrics.CARD_RADIUS)
    .border({ width: 1, color: this.bleFailed ? AppColors.DANGER : AppColors.BORDER })
  }

  @Builder
  bleGatewayRow(device: BleProvisioningDevice) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(device.deviceName)
          .fontSize(AppTypography.CARD_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .maxLines(1)
        Text(this.signalText(device.rssi))
          .fontSize(AppTypography.CAPTION)
          .fontColor(AppColors.TEXT_MUTED)
      }
      .layoutWeight(1)
      Button(this.selectedBleDeviceId === device.deviceId ? I18nService.t('已选择') : I18nService.t('选择'))
        .width(82)
        .height(36)
        .enabled(!this.bleProvisioning && !this.scanningWiFiNetworks)
        .backgroundColor(this.selectedBleDeviceId === device.deviceId ? AppColors.SUCCESS : AppColors.PRIMARY)
        .fontColor(AppColors.SURFACE)
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onClick(() => {
          this.selectedBleDeviceId = device.deviceId;
          this.wifiNetworks = [];
          this.bleMessage = I18nService.isChinese() ? `已选择 ${device.deviceName}` : `Selected ${device.deviceName}`;
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(AppColors.SURFACE_SOFT)
    .borderRadius(AppMetrics.CARD_RADIUS)
  }

  @Builder
  bleCredentialForm() {
    Column({ space: 10 }) {
      Divider().color(AppColors.BORDER)
      Text(I18nService.t('家庭 Wi-Fi（ESP32-S3 仅支持 2.4 GHz）'))
        .fontSize(AppTypography.CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.TEXT_SECONDARY)
        .width('100%')

      TextInput({ placeholder: I18nService.t('2.4 GHz Wi-Fi 名称（SSID）'), text: this.wifiSsid })
        .height(42)
        .enabled(!this.bleProvisioning && !this.scanningWiFiNetworks)
        .backgroundColor(AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onChange((value: string) => {
          this.wifiSsid = value;
        })

      TextInput({ placeholder: I18nService.t('Wi-Fi 密码（开放网络可留空）'), text: this.wifiPassword })
        .height(42)
        .type(InputType.Password)
        .enabled(!this.bleProvisioning && !this.scanningWiFiNetworks)
        .backgroundColor(AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onChange((value: string) => {
          this.wifiPassword = value;
        })

      Text(I18nService.t('PoP · BLE 配网码'))
        .fontSize(AppTypography.CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.PRIMARY_DARK)
        .width('100%')
      TextInput({ placeholder: I18nService.t('输入屏幕上的 PoP（区分大小写）'), text: this.provisioningCode })
        .height(42)
        .type(InputType.Password)
        .enabled(!this.bleProvisioning && !this.scanningWiFiNetworks)
        .backgroundColor(AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onChange((value: string) => {
          this.provisioningCode = value;
        })

      Button(this.scanningWiFiNetworks ? I18nService.t('网关正在扫描 Wi-Fi…') : I18nService.t('扫描家庭 Wi-Fi'))
        .width('100%')
        .height(40)
        .enabled(!this.bleProvisioning && !this.scanningWiFiNetworks)
        .backgroundColor(this.scanningWiFiNetworks ? AppColors.TEXT_MUTED : AppColors.TEXT_PRIMARY)
        .fontColor(AppColors.SURFACE)
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onClick(() => {
          this.handleBleWiFiScan();
        })

      if (this.wifiNetworks.length > 0) {
        Text(I18nService.t('选择网关扫描到的 2.4 GHz Wi-Fi（也可继续手动输入隐藏 SSID）'))
          .fontSize(AppTypography.CAPTION)
          .fontColor(AppColors.TEXT_SECONDARY)
          .width('100%')
        ForEach(this.wifiNetworks, (network: BleWiFiNetwork) => {
          this.bleWiFiRow(network)
        }, (network: BleWiFiNetwork) => network.ssid)
      }

      if (this.bleProvisioning || this.scanningWiFiNetworks) {
        Row({ space: 10 }) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(AppColors.PRIMARY)
          Column({ space: 3 }) {
            Text(this.bleMessage)
              .fontSize(AppTypography.BODY)
              .fontColor(AppColors.TEXT_PRIMARY)
              .maxLines(2)
            Text(`${this.bleProgress}%`)
              .fontSize(AppTypography.CAPTION)
              .fontColor(AppColors.PRIMARY)
          }
          .layoutWeight(1)
        }
        .width('100%')
        .padding(12)
        .backgroundColor(AppColors.PRIMARY_SOFT)
        .borderRadius(AppMetrics.CARD_RADIUS)
      }

      Button(this.bleProvisioning ? I18nService.t('正在安全配网') : I18nService.t('发送配置并连接'))
        .width('100%')
        .height(AppMetrics.CONTROL_HEIGHT)
        .enabled(!this.bleProvisioning && !this.scanningWiFiNetworks)
        .backgroundColor(this.bleProvisioning ? AppColors.TEXT_MUTED : AppColors.PRIMARY)
        .fontColor(AppColors.SURFACE)
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onClick(() => {
          this.handleBleProvision();
        })
    }
    .width('100%')
  }

  @Builder
  bleWiFiRow(network: BleWiFiNetwork) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(network.ssid)
          .fontSize(AppTypography.BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .maxLines(1)
        Text(this.wifiNetworkSummary(network))
          .fontSize(AppTypography.CAPTION)
          .fontColor(AppColors.TEXT_MUTED)
          .maxLines(1)
      }
      .layoutWeight(1)
      Button(this.wifiSsid === network.ssid ? I18nService.t('已选择') : I18nService.t('选择'))
        .width(76)
        .height(34)
        .enabled(!this.bleProvisioning && !this.scanningWiFiNetworks)
        .backgroundColor(this.wifiSsid === network.ssid ? AppColors.SUCCESS : AppColors.PRIMARY)
        .fontColor(AppColors.SURFACE)
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onClick(() => {
          this.wifiSsid = network.ssid;
          this.bleMessage = I18nService.isChinese() ?
            `已选择家庭 Wi-Fi：${network.ssid}` : `Selected home Wi-Fi: ${network.ssid}`;
        })
    }
    .width('100%')
    .padding(10)
    .backgroundColor(AppColors.SURFACE_SOFT)
    .borderRadius(AppMetrics.CARD_RADIUS)
  }

  @Builder
  cleanupNotice() {
    Row({ space: 10 }) {
      Text(this.sceneCleanupNotice)
        .fontSize(AppTypography.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.TEXT_PRIMARY)
        .maxLines(2)
      .layoutWeight(1)
      Button(I18nService.t('知道了'))
        .height(34)
        .padding({ left: 12, right: 12 })
        .backgroundColor(AppColors.SURFACE)
        .fontColor(AppColors.PRIMARY)
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onClick(() => {
          this.sceneCleanupNotice = '';
        })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(AppColors.SURFACE_SOFT)
    .border({ width: 1, color: AppColors.WARNING })
    .borderRadius(AppMetrics.CARD_RADIUS)
  }

  @Builder
  gatewayDiscoveryCard() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 3 }) {
          Text(I18nService.t('恢复已联网网关'))
            .fontSize(AppTypography.CARD_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text(I18nService.t('换手机或自动绑定失败时使用'))
            .fontSize(AppTypography.CAPTION)
            .fontColor(AppColors.TEXT_MUTED)
        }
        .layoutWeight(1)
        Blank()
        Button(this.scanningGateways ? I18nService.t('扫描中') : I18nService.t('手动查找'))
          .height(38)
          .padding({ left: 14, right: 14 })
          .enabled(!this.scanningGateways && !this.scanningDevices)
          .backgroundColor(this.scanningGateways ? AppColors.TEXT_MUTED : AppColors.PRIMARY)
          .fontColor(AppColors.SURFACE)
          .borderRadius(AppMetrics.CARD_RADIUS)
          .onClick(() => {
            this.handleGatewayScan();
          })
      }
      .width('100%')

      if (this.scanningGateways) {
        this.scanLoading(I18nService.t('正在查找网关'))
      } else if (this.hasScannedGateways) {
        if (this.discoveredGateways.length === 0) {
          this.emptyDiscoveryResult(I18nService.t('未发现网关'))
        } else {
          ForEach(this.discoveredGateways, (gateway: DiscoveredGateway) => {
            this.discoveredGatewayRow(gateway)
          }, (gateway: DiscoveredGateway) => `${gateway.gatewayId}_${gateway.localIp}`)
        }
      }
    }
    .width('100%')
    .padding(AppMetrics.CARD_PADDING)
    .backgroundColor(AppColors.SURFACE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .borderRadius(AppMetrics.CARD_RADIUS)
    .border({ width: 1, color: AppColors.GLASS_BORDER })
    .shadow({ radius: 12, color: AppColors.GLASS_SHADOW, offsetX: 0, offsetY: 4 })
  }

  @Builder
  discoveredGatewayRow(gateway: DiscoveredGateway) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(gateway.gatewayName)
          .fontSize(AppTypography.CARD_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .maxLines(1)
        Text(this.deviceCountText(gateway.deviceCount))
          .fontSize(AppTypography.CAPTION)
          .fontColor(AppColors.TEXT_MUTED)
          .maxLines(1)
      }
      .layoutWeight(1)
      Button(this.isGatewayBound(gateway.gatewayId) ? I18nService.t('已添加') : I18nService.t('添加网关'))
        .height(36)
        .padding({ left: 13, right: 13 })
        .enabled(!this.isGatewayBound(gateway.gatewayId))
        .backgroundColor(this.isGatewayBound(gateway.gatewayId) ? AppColors.BORDER : AppColors.PRIMARY)
        .fontColor(this.isGatewayBound(gateway.gatewayId) ? AppColors.TEXT_MUTED : AppColors.SURFACE)
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onClick(() => {
          this.handleBindGateway(gateway);
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(AppColors.SURFACE_SOFT)
    .borderRadius(AppMetrics.CARD_RADIUS)
  }

  @Builder
  deviceDiscoveryCard() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 3 }) {
          Text(I18nService.t('扫描设备'))
            .fontSize(AppTypography.CARD_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text(this.boundGatewayId.length > 0 ? I18nService.t('通过网关发现设备') : I18nService.t('请先完成网关配网'))
            .fontSize(AppTypography.CAPTION)
            .fontColor(this.boundGatewayId.length > 0 ? AppColors.PRIMARY : AppColors.WARNING)
        }
        .layoutWeight(1)
        Blank()
        Button(this.scanningDevices ? I18nService.t('扫描中') :
          (this.boundGatewayId.length > 0 ? I18nService.t('扫描设备') : I18nService.t('先添加网关')))
          .height(38)
          .padding({ left: 14, right: 14 })
          .enabled(this.boundGatewayId.length > 0 && !this.scanningGateways && !this.scanningDevices)
          .backgroundColor(this.boundGatewayId.length > 0 && !this.scanningDevices ? AppColors.PRIMARY : AppColors.BORDER)
          .fontColor(this.boundGatewayId.length > 0 && !this.scanningDevices ? AppColors.SURFACE : AppColors.TEXT_MUTED)
          .borderRadius(AppMetrics.CARD_RADIUS)
          .onClick(() => {
            this.handleDeviceScan();
          })
      }
      .width('100%')

      if (this.boundGatewayId.length === 0) {
        this.emptyDiscoveryResult(I18nService.t('添加网关后即可扫描'))
      } else if (this.scanningDevices) {
        this.scanLoading(I18nService.t('正在查找设备'))
      } else if (this.hasScannedDevices) {
        if (this.discovered.length === 0) {
          this.emptyDiscoveryResult(I18nService.t('未发现设备'))
        } else {
          ForEach(this.discovered, (item: DiscoveredDevice) => {
            this.discoveredRow(item)
          }, (item: DiscoveredDevice) => item.deviceId)
        }
        this.manualFallback()
      }
    }
    .width('100%')
    .padding(AppMetrics.CARD_PADDING)
    .backgroundColor(AppColors.SURFACE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .borderRadius(AppMetrics.CARD_RADIUS)
    .border({ width: 1, color: AppColors.GLASS_BORDER })
    .shadow({ radius: 12, color: AppColors.GLASS_SHADOW, offsetX: 0, offsetY: 4 })
  }

  @Builder
  emptyDiscoveryResult(text: string) {
    Text(text)
      .fontSize(AppTypography.BODY)
      .fontColor(AppColors.TEXT_SECONDARY)
      .width('100%')
      .textAlign(TextAlign.Center)
      .padding(12)
      .backgroundColor(AppColors.SURFACE_SOFT)
      .borderRadius(AppMetrics.CARD_RADIUS)
  }

  @Builder
  scanLoading(label: string) {
    Column({ space: 9 }) {
      LoadingProgress()
        .width(42)
        .height(42)
        .color(AppColors.PRIMARY)
      Text(label)
        .fontSize(AppTypography.CAPTION)
        .fontColor(AppColors.TEXT_SECONDARY)
    }
    .width('100%')
    .padding({ top: 18, bottom: 18 })
    .backgroundColor(AppColors.PRIMARY_SOFT)
    .borderRadius(AppMetrics.CARD_RADIUS)
  }

  @Builder
  manualFallback() {
    if (this.manualExpanded) {
      Divider()
        .color(AppColors.BORDER)
      Row() {
        Text(I18nService.t('创建待绑定占位'))
          .fontSize(AppTypography.CARD_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
        Blank()
        Button(I18nService.t('收起'))
          .height(32)
          .padding({ left: 12, right: 12 })
          .backgroundColor(AppColors.SURFACE_SOFT)
          .fontColor(AppColors.TEXT_SECONDARY)
          .borderRadius(AppMetrics.CARD_RADIUS)
          .onClick(() => {
            this.manualExpanded = false;
          })
      }
      .width('100%')
      Text(I18nService.t('手动录入不会让设备立即可控；保存后保持离线，需由已绑定网关发现同一真实设备后再绑定。'))
        .fontSize(AppTypography.CAPTION)
        .fontColor(AppColors.WARNING)
        .width('100%')
      this.addPanel()
    } else {
      Button(this.discovered.length > 0 ? I18nService.t('没有找到？创建离线占位') : I18nService.t('创建离线占位'))
        .width('100%')
        .height(38)
        .backgroundColor(AppColors.SURFACE)
        .fontColor(AppColors.TEXT_SECONDARY)
        .border({ width: 1, color: AppColors.BORDER })
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onClick(() => {
          this.manualExpanded = true;
        })
    }
  }

  @Builder
  addPanel() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        this.typeButton(DeviceType.DOOR)
        this.typeButton(DeviceType.LIGHT)
        this.typeButton(DeviceType.SENSOR)
        this.typeButton(DeviceType.AC)
      }
      .width('100%')

      Row({ space: 8 }) {
        this.typeButton(DeviceType.SWITCH)
        this.typeButton(DeviceType.CAMERA)
      }
      .width('100%')

      Row({ space: 8 }) {
        this.typeButton(DeviceType.CURTAIN)
        this.typeButton(DeviceType.FAN)
        this.typeButton(DeviceType.SPEAKER)
      }
      .width('100%')

      TextInput({ placeholder: I18nService.t('设备名称'), text: this.draftName })
        .height(42)
        .backgroundColor(AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onChange((value: string) => {
          this.draftName = value;
        })

      TextInput({ placeholder: I18nService.t('房间'), text: this.draftRoom })
        .height(42)
        .backgroundColor(AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onChange((value: string) => {
          this.draftRoom = value;
        })

      TextInput({ placeholder: I18nService.t('品牌（可选）'), text: this.draftBrand })
        .height(42)
        .backgroundColor(AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onChange((value: string) => {
          this.draftBrand = value;
        })

      Button(I18nService.t('保存待绑定离线占位'))
        .width('100%')
        .height(AppMetrics.CONTROL_HEIGHT)
        .backgroundColor(AppColors.PRIMARY)
        .fontColor(AppColors.SURFACE)
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onClick(() => {
          this.handleAddDevice();
        })
    }
  }

  @Builder
  deviceRegistry() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(I18nService.t('全部设备'))
          .fontSize(AppTypography.SECTION_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
        Blank()
        Text(this.deviceCountText(this.getFilteredDevices().length))
          .fontSize(AppTypography.CAPTION)
          .fontColor(AppColors.TEXT_MUTED)
        Button() {
          Row({ space: 6 }) {
            if (this.syncingDevices) {
              LoadingProgress()
                .width(15)
                .height(15)
                .color(AppColors.SURFACE)
            }
            Text(this.syncingDevices ? I18nService.t('同步中…') : I18nService.t('同步'))
              .fontSize(AppTypography.CAPTION)
              .fontColor(AppColors.SURFACE)
          }
        }
          .height(34)
          .padding({ left: 12, right: 12 })
          .backgroundColor(AppColors.TEXT_PRIMARY)
          .borderRadius(AppMetrics.CARD_RADIUS)
          .enabled(!this.syncingDevices)
          .onClick(() => {
            this.handleCloudSync();
          })
      }
      .width('100%')

      if (this.getFilteredDevices().length === 0) {
        this.emptyDeviceState()
      } else {
        ForEach(this.getFilteredDevices(), (device: DeviceState) => {
          this.deviceRow(device)
        }, (device: DeviceState) => this.deviceRenderKey(device))
      }
    }
    .width('100%')
  }

  @Builder
  emptyDeviceState() {
    Column({ space: 8 }) {
      Text(this.devices.length === 0 ? I18nService.t('还没有家庭设备') : I18nService.t('没有匹配的设备'))
        .fontSize(AppTypography.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.TEXT_PRIMARY)
      Text(this.devices.length === 0 ? I18nService.t('先添加网关，再扫描设备。') : I18nService.t('换个关键词试试。'))
        .fontSize(AppTypography.CAPTION)
        .fontColor(AppColors.TEXT_MUTED)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding(AppMetrics.CARD_PADDING)
    .backgroundColor(AppColors.SURFACE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .border({ width: 1, color: AppColors.GLASS_BORDER })
    .borderRadius(AppMetrics.CARD_RADIUS)
    .shadow({ radius: 12, color: AppColors.GLASS_SHADOW, offsetX: 0, offsetY: 4 })
  }

  @Builder
  deviceRow(device: DeviceState) {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 4 }) {
          Row({ space: 8 }) {
            Text(device.deviceName)
              .fontSize(AppTypography.CARD_TITLE)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
              .maxLines(1)
            this.statusPill(this.viewModel.getTypeLabel(device.deviceType), this.deviceAccent(device.deviceType))
          }
          Text(device.roomName)
            .fontSize(AppTypography.CAPTION)
            .fontColor(AppColors.TEXT_MUTED)
            .maxLines(1)
        }
        Blank()
        Text(this.isPendingPlaceholder(device) ? I18nService.t('待绑定 · 离线占位') : (device.isOnline ? I18nService.t('在线') : I18nService.t('离线')))
          .fontSize(AppTypography.CAPTION)
          .fontColor(device.isOnline && !this.isPendingPlaceholder(device) ? AppColors.SUCCESS : AppColors.TEXT_MUTED)
      }
      .width('100%')
      .onClick(() => {
        if (!this.isPendingPlaceholder(device)) this.onOpenDevice(device.deviceId);
      })

      Text(this.deviceStateText(device))
        .fontSize(AppTypography.BODY)
        .fontColor(AppColors.TEXT_SECONDARY)
        .maxLines(2)
        .width('100%')
      if (device.stateSource !== undefined && device.stateSource.length > 0) {
        Text(`${this.stateSourceText(device)} · ${device.updatedAt}`)
          .fontSize(AppTypography.CAPTION)
          .fontColor(device.automationId !== undefined && device.automationId.length > 0 ?
            AppColors.ACCENT : AppColors.TEXT_MUTED)
          .maxLines(2)
          .width('100%')
      }

      Row({ space: 8 }) {
        Button(this.actionLabel(device))
          .layoutWeight(1)
          .height(38)
          .enabled(this.canQuickControl(device))
          .backgroundColor(this.canQuickControl(device) ? AppColors.PRIMARY : AppColors.BORDER)
          .fontColor(AppColors.SURFACE)
          .borderRadius(AppMetrics.CARD_RADIUS)
          .onClick(() => {
            this.handleQuickAction(device);
          })
        Button(I18nService.t('删除'))
          .width(76)
          .height(38)
          .backgroundColor(AppColors.SURFACE_SOFT)
          .fontColor(AppColors.DANGER)
          .borderRadius(AppMetrics.CARD_RADIUS)
          .onClick(() => {
            this.handleRemoveDevice(device.deviceId);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(AppColors.SURFACE)
    .borderRadius(AppMetrics.CARD_RADIUS)
    .border({ width: 1, color: AppColors.BORDER })
  }

  @Builder
  discoveredRow(item: DiscoveredDevice) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(item.deviceName)
          .fontSize(AppTypography.CARD_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .maxLines(1)
        Text(`${item.roomName} · ${this.viewModel.getTypeLabel(item.deviceType)}`)
          .fontSize(AppTypography.CAPTION)
          .fontColor(AppColors.TEXT_MUTED)
          .maxLines(1)
      }
      .layoutWeight(1)
      Button(this.isDeviceBound(item.deviceId) ? I18nService.t('已添加') :
        (this.isGatewayBound(item.gatewayId) ? I18nService.t('添加') : I18nService.t('先添加网关')))
        .width(100)
        .height(36)
        .enabled(this.isGatewayBound(item.gatewayId) && !this.isDeviceBound(item.deviceId))
        .backgroundColor(this.isGatewayBound(item.gatewayId) && !this.isDeviceBound(item.deviceId) ?
          AppColors.PRIMARY : AppColors.BORDER)
        .fontColor(this.isGatewayBound(item.gatewayId) && !this.isDeviceBound(item.deviceId) ?
          AppColors.SURFACE : AppColors.TEXT_MUTED)
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onClick(() => {
          this.handleBind(item);
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(AppColors.SURFACE_SOFT)
    .borderRadius(AppMetrics.CARD_RADIUS)
  }

  @Builder
  typeButton(type: DeviceType) {
    Button(this.viewModel.getTypeLabel(type))
      .height(36)
      .layoutWeight(1)
      .backgroundColor(this.draftType === type ? AppColors.PRIMARY : AppColors.SURFACE_SOFT)
      .fontColor(this.draftType === type ? AppColors.SURFACE : AppColors.TEXT_SECONDARY)
      .borderRadius(AppMetrics.CARD_RADIUS)
      .onClick(() => {
        this.draftType = type;
      })
  }

  @Builder
  statusPill(text: string, color: string) {
    Text(text)
      .fontSize(AppTypography.CAPTION)
      .fontColor(color)
      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
      .backgroundColor(AppColors.SURFACE_SOFT)
      .borderRadius(AppMetrics.CARD_RADIUS)
      .maxLines(1)
  }

  private async handleBleScan(): Promise<void> {
    if (this.bleScanning || this.bleProvisioning || this.scanningWiFiNetworks) {
      return;
    }
    if (!await this.ensureBleCommandKeyReady()) {
      return;
    }
    // Starting a new enrollment explicitly supersedes any pending identity
    // from an earlier gateway; its background retry must never win a race.
    await this.clearPendingGateway();
    const operationId = ++this.bleOperationId;
    this.bleFailed = false;
    this.bleScanning = true;
    this.bleDevices = [];
    this.wifiNetworks = [];
    this.selectedBleDeviceId = '';
    this.bleMessage = I18nService.t('正在请求蓝牙权限并搜索网关');
    try {
      const devices = await this.bleViewModel.scan();
      if (!this.isBleOperationCurrent(operationId)) {
        return;
      }
      this.bleDevices = devices;
      this.bleMessage = this.bleDevices.length > 0 ?
        `发现 ${this.bleDevices.length} 个可配网网关` : I18nService.t('未发现网关，请确认开发板处于配网模式');
    } catch (error) {
      if (this.isBleOperationCurrent(operationId)) {
        this.bleFailed = true;
        this.wifiPassword = '';
        this.provisioningCode = '';
        const reason = error instanceof Error ? error.message : `${error}`;
        if (reason.indexOf('BLE_PERMISSION_DENIED') >= 0) {
          this.bleMessage = I18nService.t('蓝牙权限未授予，请在系统设置中允许 YaoCore 使用附近设备');
        } else if (reason.indexOf('BLUETOOTH_DISABLED') >= 0) {
          this.bleMessage = I18nService.t('手机蓝牙未开启，请打开蓝牙后重试');
        } else if (reason.indexOf('BLE_SCAN_FAILED') >= 0) {
          this.bleMessage = I18nService.t('系统未能启动蓝牙扫描，请确认蓝牙已开启且附近设备权限已允许');
        } else {
          this.bleMessage = I18nService.isChinese() ? `蓝牙搜索失败：${reason}` : `Bluetooth search failed: ${reason}`;
        }
      }
    } finally {
      if (this.isBleOperationCurrent(operationId)) {
        this.bleScanning = false;
      }
    }
  }

  private async handleBleWiFiScan(): Promise<void> {
    if (this.bleProvisioning || this.scanningWiFiNetworks || this.bleScanning) {
      return;
    }
    if (!await this.ensureBleCommandKeyReady()) {
      return;
    }
    const device = this.findSelectedBleDevice();
    if (device === undefined) {
      this.bleMessage = I18nService.t('请先选择一个网关');
      return;
    }
    if (this.provisioningCode.length === 0) {
      this.bleMessage = I18nService.t('请先输入网关配网码（PoP），再扫描家庭 Wi-Fi');
      return;
    }

    const operationId = ++this.bleOperationId;
    this.bleFailed = false;
    this.scanningWiFiNetworks = true;
    this.wifiNetworks = [];
    this.bleProgress = 1;
    this.bleMessage = I18nService.t('准备让网关扫描家庭 Wi-Fi');
    try {
      const networks = await this.bleViewModel.scanWiFiNetworks(
        device,
        this.provisioningCode,
        (progress: BleProvisioningProgress) => {
          if (this.isBleOperationCurrent(operationId)) {
            this.bleMessage = progress.message;
            this.bleProgress = progress.percent;
          }
        }
      );
      if (!this.isBleOperationCurrent(operationId)) {
        return;
      }
      this.wifiNetworks = networks;
      this.bleProgress = 100;
      this.bleMessage = networks.length > 0 ?
        `发现 ${networks.length} 个家庭 Wi-Fi，请选择或手动输入隐藏 SSID` :
        I18nService.t('未扫描到 Wi-Fi，可继续手动输入隐藏 SSID');
    } catch (error) {
      if (this.isBleOperationCurrent(operationId)) {
        const message = `${error}`;
        this.wifiPassword = '';
        this.bleFailed = true;
        if (message.indexOf('PROVISIONING_POP_INVALID') >= 0) {
          this.bleMessage = I18nService.t('网关配网码必须为 8 至 64 个 UTF-8 字节');
        } else if (message.indexOf('BLE_PERMISSION_DENIED') >= 0) {
          this.bleMessage = I18nService.t('需要授予蓝牙访问权限才能扫描家庭 Wi-Fi');
        } else if (message.indexOf('BLUETOOTH_DISABLED') >= 0) {
          this.bleMessage = I18nService.t('请先打开手机蓝牙');
        } else if (message.indexOf('BLE_MTU_') >= 0) {
          this.bleMessage = I18nService.t('蓝牙数据长度协商失败，当前连接无法完整传输扫描结果');
        } else if (message.indexOf('PROOF_OF_POSSESSION_REJECTED') >= 0) {
          this.bleMessage = I18nService.t('配网码校验失败，请检查网关 PoP');
        } else if (message.indexOf('BLE_CONNECTION_TIMEOUT') >= 0) {
          this.bleMessage = I18nService.t('连接网关超时，请靠近开发板并确认屏幕仍显示 BLE SETUP');
        } else if (message.indexOf('WIFI_SCAN_TIMEOUT') >= 0) {
          this.bleMessage = I18nService.t('网关扫描家庭 Wi-Fi 超时，请重试或直接手动输入 Wi-Fi 名称');
        } else if (message.indexOf('GATT_') >= 0) {
          this.bleMessage = I18nService.t('蓝牙通信中断，请保持手机靠近网关后重试');
        } else {
          this.bleMessage = I18nService.isChinese() ?
            `网关扫描 Wi-Fi 失败（${this.errorCode(message)}），可直接手动输入 Wi-Fi 名称后继续` :
            `Gateway Wi-Fi scan failed (${this.errorCode(message)}). You can enter the SSID manually and continue.`;
        }
      }
    } finally {
      if (this.isBleOperationCurrent(operationId)) {
        this.scanningWiFiNetworks = false;
      }
    }
  }

  private async handleBleProvision(): Promise<void> {
    if (this.bleProvisioning || this.scanningWiFiNetworks || this.bleScanning) {
      return;
    }
    if (!await this.ensureBleCommandKeyReady()) {
      return;
    }
    const device = this.findSelectedBleDevice();
    if (device === undefined) {
      this.bleMessage = I18nService.t('请先选择一个网关');
      return;
    }
    if (this.wifiSsid.length === 0) {
      this.bleMessage = I18nService.t('请输入 2.4 GHz Wi-Fi 名称');
      return;
    }
    if (this.provisioningCode.length === 0) {
      this.bleMessage = I18nService.t('请输入网关配网码（PoP）');
      return;
    }

    const operationId = ++this.bleOperationId;
    this.bleFailed = false;
    this.bleProvisioning = true;
    this.bleProgress = 1;
    this.bleMessage = I18nService.t('准备安全配网');
    let result: BleProvisioningResult | undefined = undefined;
    try {
      result = await this.bleViewModel.provision(
        device,
        this.wifiSsid,
        this.wifiPassword,
        this.provisioningCode,
        (progress: BleProvisioningProgress) => {
          if (this.isBleOperationCurrent(operationId)) {
            this.bleMessage = progress.message;
            this.bleProgress = progress.percent;
          }
        }
      );
      if (!this.isBleOperationCurrent(operationId)) {
        return;
      }
      this.bleMessage = result.message;
      if (!result.success) {
        this.bleFailed = true;
        if (result.errorCode !== undefined && result.errorCode.length > 0) {
          const stage = result.failedStage === undefined ? 'ble' : result.failedStage;
          this.bleMessage = `${result.message} [${stage}/${result.errorCode}]`;
        }
        // A failed transport attempt must never leave the form locked in its
        // loading state. Keep the entered SSID/password/PoP so the explicit
        // retry button can establish a fresh GATT/Security1 session.
        this.bleProvisioning = false;
        this.bleViewModel.disconnect();
        return;
      }
    } catch (error) {
      if (this.isBleOperationCurrent(operationId)) {
        this.bleFailed = true;
        this.bleMessage = I18nService.isChinese() ?
          `BLE 配网异常中断（${this.errorCode(`${error}`)}），请按提示重试` :
          `BLE provisioning stopped (${this.errorCode(`${error}`)}). Please retry.`;
        this.bleProvisioning = false;
        this.bleViewModel.disconnect();
      }
      return;
    }

    if (result === undefined || !this.isBleOperationCurrent(operationId)) {
      if (this.isBleOperationCurrent(operationId)) this.bleProvisioning = false;
      return;
    }
    this.provisioningCode = '';
    await this.rememberPendingGateway(result);
    try {
      await this.verifyAndBindProvisionedGateway(result, operationId);
    } catch (error) {
      if (this.isBleOperationCurrent(operationId)) {
        const code = this.errorCode(`${error}`);
        this.bleFailed = false;
        this.pendingGatewayBinding = true;
        this.pendingRetryAfter = Date.now() + 5000;
        if (code === 'COMMAND_KEY_MISMATCH' || code === 'RESPONSE_SIGNATURE_INVALID') {
          await this.securityService.clearSessionSecret();
          this.commandKeyReady = false;
          this.onCommandKeyChanged(false);
          this.bleFailed = true;
          this.bleMessage = I18nService.isChinese() ?
            `Wi-Fi 已配好，但控制密钥与网关不一致（${code}）。请在下方重新输入固件中的控制密钥，再继续绑定。` :
            `Wi-Fi is configured, but the command key does not match (${code}). Enter the firmware command key below, then continue binding.`;
        } else if (code === 'GATEWAY_ID_MISMATCH') {
          this.bleFailed = true;
          this.bleMessage = I18nService.isChinese() ?
            'Wi-Fi 已配好，但该地址返回了另一台网关，已阻止错误绑定。' :
            'Wi-Fi is configured, but another gateway answered at that address; incorrect binding was blocked.';
        } else {
          this.bleMessage = I18nService.isChinese() ?
            `Wi-Fi 配网已完成，局域网绑定暂未完成（${code}）。请让手机连接同一 Wi-Fi，YaoCore 会自动重试。` :
            `Wi-Fi setup completed, but LAN binding is pending (${code}). Connect the phone to the same Wi-Fi; YaoCore will retry automatically.`;
        }
      }
    } finally {
      if (this.isBleOperationCurrent(operationId)) this.bleProvisioning = false;
    }
  }

  private cancelBleSession(): void {
    this.bleOperationId += 1;
    this.bleViewModel.disconnect();
    this.bleScanning = false;
    this.bleProvisioning = false;
    this.scanningWiFiNetworks = false;
    this.wifiPassword = '';
    this.provisioningCode = '';
    this.wifiNetworks = [];
  }

  private retryBleProvisioning(): void {
    if (this.bleProvisioning || this.scanningWiFiNetworks || this.bleScanning) return;
    this.bleViewModel.disconnect();
    this.bleFailed = false;
    this.bleProgress = 0;
    this.bleMessage = I18nService.t('正在创建新的 BLE 安全会话');
    this.handleBleProvision();
  }

  private isBleOperationCurrent(operationId: number): boolean {
    return this.pageActive && operationId === this.bleOperationId;
  }

  private async ensureBleCommandKeyReady(): Promise<boolean> {
    await this.securityService.load();
    this.commandKeyReady = this.securityService.hasSessionSecret();
    if (!this.commandKeyReady) {
      this.bleExpanded = true;
      this.bleMessage = I18nService.t('请先在当前配网卡片保存与开发板一致的控制密钥');
      return false;
    }
    return true;
  }

  private async saveInlineCommandKey(): Promise<void> {
    const secret = this.commandSecretInput.trim();
    if (secret.length < 16) {
      this.bleMessage = I18nService.t('控制密钥至少需要 16 位');
      return;
    }
    const saved = await this.securityService.setSessionSecret(secret);
    this.commandSecretInput = '';
    this.commandKeyReady = saved && this.securityService.hasSessionSecret();
    this.onCommandKeyChanged(this.commandKeyReady);
    if (this.commandKeyReady) {
      this.editingCommandKey = false;
      this.pendingAutoRetryCount = 0;
      this.pendingAutomaticRetryBlocked = false;
    }
    this.bleMessage = this.commandKeyReady ?
      I18nService.t('控制密钥已安全保存，请继续搜索附近网关') : I18nService.t('控制密钥保存失败，请重试');
    this.bleFailed = !this.commandKeyReady;
    if (this.commandKeyReady && this.pendingGatewayBinding) this.pendingRetryAfter = Date.now();
  }

  private async verifyAndBindProvisionedGateway(
    result: BleProvisioningResult,
    operationId: number
  ): Promise<void> {
    const expectedGatewayId = result.expectedGatewayId.trim();
    if (expectedGatewayId.length === 0 || result.protocolVersion !== '2.0') {
      this.bleFailed = true;
      this.bleMessage = I18nService.t('BLE 入网完成，但安全身份无效，已拒绝扫描与绑定');
      return;
    }

    let matched: DiscoveredGateway | undefined = undefined;
    const preferredIp = result.ipAddress.trim();
    if (preferredIp.length > 0) {
      for (let attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) {
          const backoffMs = Math.min(350 * Math.pow(2, attempt - 1), 4000);
          await this.delay(backoffMs);
        }
        if (!this.isBleOperationCurrent(operationId)) {
          return;
        }
        this.bleProgress = 90 + attempt;
        this.bleMessage = I18nService.isChinese() ?
          `正在认证 ${preferredIp} 上的同一网关（${attempt + 1}/3）` :
          `Authenticating the same gateway at ${preferredIp} (${attempt + 1}/3)`;
        matched = await this.viewModel.probeProvisionedGateway(preferredIp, expectedGatewayId);
        if (matched !== undefined) {
          break;
        }
      }
    }

    if (matched === undefined && this.isBleOperationCurrent(operationId)) {
      this.bleProgress = 96;
      this.bleMessage = preferredIp.length > 0 ?
        I18nService.t('指定地址暂不可达，正在安全扫描并仅匹配 BLE 已确认身份') :
        (I18nService.isChinese() ?
          '网关已联网，正在局域网中发现并认证同一网关' :
          'The gateway is online. Discovering and authenticating it on the LAN.');
      matched = await this.viewModel.scanProvisionedGateway(expectedGatewayId);
    }
    if (!this.isBleOperationCurrent(operationId)) {
      return;
    }
    if (matched === undefined || matched.gatewayId !== expectedGatewayId || !matched.secureTransport) {
      this.bleProgress = 88;
      this.pendingGatewayBinding = true;
      this.pendingRetryAfter = Date.now() + 8000;
      this.bleFailed = true;
      this.bleMessage = I18nService.isChinese() ?
        `Wi-Fi 配网已完成，但尚未通过局域网身份认证。请确认手机连接 ${this.wifiSsid}，并检查控制密钥是否与网关一致。` :
        `Wi-Fi setup is complete, but LAN identity verification is pending. Connect to ${this.wifiSsid} and verify the gateway control key.`;
      this.message = I18nService.t('未绑定：没有发现与 BLE 安全身份完全一致的已认证网关');
      return;
    }

    this.discoveredGateways = [matched];
    this.hasScannedGateways = true;
    this.bleProgress = 98;
    this.bleMessage = I18nService.t('双重身份校验通过，正在验证板载 LED 并保存绑定');
    const bindResult = await this.viewModel.bindGateway(matched);
    if (!this.isBleOperationCurrent(operationId)) {
      return;
    }
    if (!bindResult.success || bindResult.confirmed !== true) {
      this.bleFailed = true;
      this.bleMessage = I18nService.isChinese() ?
        `同一网关身份已确认，但未完成绑定：${bindResult.message}` :
        `Gateway identity confirmed, but binding did not finish: ${bindResult.message}`;
      this.message = bindResult.message;
      return;
    }
    this.boundGatewayId = matched.gatewayId;
    await this.clearPendingGateway();
    this.bleFailed = false;
    this.discovered = [];
    this.hasScannedDevices = false;
    this.manualExpanded = false;
    this.bleProgress = 100;
    this.bleMessage = I18nService.isChinese() ?
      `${matched.gatewayName} 已安全配网并绑定` : `${matched.gatewayName} was securely provisioned and bound`;
    this.message = bindResult.message;
    this.bleExpanded = false;
    this.reload();
  }

  private wifiSecurityLabel(authMode: number): string {
    switch (authMode) {
      case 0:
        return I18nService.t('开放网络');
      case 1:
        return 'WEP';
      case 2:
        return 'WPA';
      case 3:
        return 'WPA2';
      case 4:
        return 'WPA/WPA2';
      case 5:
        return I18nService.t('企业网络');
      case 6:
        return 'WPA3';
      case 7:
        return 'WPA2/WPA3';
      case 8:
        return 'WAPI';
      default:
        return I18nService.t('加密网络');
    }
  }

  private findSelectedBleDevice(): BleProvisioningDevice | undefined {
    for (let index = 0; index < this.bleDevices.length; index++) {
      if (this.bleDevices[index].deviceId === this.selectedBleDeviceId) {
        return this.bleDevices[index];
      }
    }
    return undefined;
  }

  private async rememberPendingGateway(result: BleProvisioningResult): Promise<void> {
    this.pendingGatewayId = result.expectedGatewayId;
    this.pendingGatewayName = result.expectedGatewayName;
    this.pendingGatewayIp = result.ipAddress;
    this.pendingGatewayProtocol = result.protocolVersion;
    this.pendingGatewayBinding = true;
    this.pendingRetryAfter = Date.now() + 5000;
    this.pendingAutoRetryCount = 0;
    this.pendingAutomaticRetryBlocked = false;
    const binding: PendingGatewayBindingState = {
      gatewayId: this.pendingGatewayId,
      gatewayName: this.pendingGatewayName,
      ipAddress: this.pendingGatewayIp,
      protocolVersion: this.pendingGatewayProtocol
    };
    await AppStorageService.savePendingGatewayBinding(binding);
  }

  private async clearPendingGateway(): Promise<void> {
    this.pendingGatewayId = '';
    this.pendingGatewayName = '';
    this.pendingGatewayIp = '';
    this.pendingGatewayProtocol = '';
    this.pendingGatewayBinding = false;
    this.pendingRetryAfter = 0;
    this.pendingAutoRetryCount = 0;
    this.pendingAutomaticRetryBlocked = false;
    await AppStorageService.clearPendingGatewayBinding();
  }

  private async retryPendingGatewayBinding(manual: boolean = true): Promise<void> {
    if (!this.pageActive || this.bleProvisioning || !this.commandKeyReady || !this.pendingGatewayBinding ||
      this.pendingGatewayId.length === 0) return;
    if (!manual && this.pendingAutomaticRetryBlocked) return;
    if (manual) {
      this.pendingAutoRetryCount = 0;
      this.pendingAutomaticRetryBlocked = false;
    } else {
      this.pendingAutoRetryCount = Math.min(this.pendingAutoRetryCount + 1,
        DevicePage.MAX_PENDING_AUTO_RETRIES);
    }
    const operationId = ++this.bleOperationId;
    this.bleProvisioning = true;
    this.bleFailed = false;
    this.bleProgress = 90;
    this.bleMessage = I18nService.t('正在自动认证并绑定刚刚配网的网关');
    const result: BleProvisioningResult = {
      success: true,
      message: this.bleMessage,
      ipAddress: this.pendingGatewayIp,
      expectedGatewayId: this.pendingGatewayId,
      expectedGatewayName: this.pendingGatewayName,
      protocolVersion: this.pendingGatewayProtocol
    };
    try {
      await this.verifyAndBindProvisionedGateway(result, operationId);
    } catch (error) {
      if (this.isBleOperationCurrent(operationId)) {
        const code = this.errorCode(`${error}`);
        if (code === 'COMMAND_KEY_MISMATCH' || code === 'RESPONSE_SIGNATURE_INVALID') {
          await this.securityService.clearSessionSecret();
          this.commandKeyReady = false;
          this.onCommandKeyChanged(false);
          this.pendingRetryAfter = Number.MAX_SAFE_INTEGER;
          this.pendingAutomaticRetryBlocked = true;
          this.bleFailed = true;
          this.bleMessage = I18nService.isChinese() ?
            `网关可达，但控制密钥不一致（${code}）。自动重试已暂停，请重新输入开发板对应的控制密钥。` :
            `The gateway is reachable, but the control key does not match (${code}). Automatic retries are paused; enter the correct key.`;
        } else if (code === 'GATEWAY_ID_MISMATCH') {
          this.pendingRetryAfter = Number.MAX_SAFE_INTEGER;
          this.pendingAutomaticRetryBlocked = true;
          this.bleFailed = true;
          this.bleMessage = I18nService.isChinese() ?
            '该地址是另一台网关，已停止自动绑定以避免绑定错误设备。' :
            'Another gateway answered at that address. Automatic binding was stopped to prevent an incorrect association.';
        } else {
          // BLE/Wi-Fi provisioning has already completed at this point.  A
          // failed LAN identity probe must be shown as a recoverable binding
          // failure, not as an endless provisioning spinner.  Background
          // retries remain enabled and the dedicated binding button below can
          // also retry immediately without sending the Wi-Fi credentials again.
          this.bleFailed = true;
          this.bleMessage = I18nService.isChinese() ?
            `局域网认证暂未完成（${code}），请确认手机与网关连接同一 Wi-Fi。` :
            `LAN verification is still pending (${code}). Confirm that the phone and gateway use the same Wi-Fi.`;
        }
      }
    } finally {
      if (this.isBleOperationCurrent(operationId)) {
        this.bleProvisioning = false;
        if (this.pendingGatewayBinding && this.commandKeyReady && !this.pendingAutomaticRetryBlocked) {
          if (!manual && this.pendingAutoRetryCount >= DevicePage.MAX_PENDING_AUTO_RETRIES) {
            this.pendingAutomaticRetryBlocked = true;
            this.pendingRetryAfter = Number.MAX_SAFE_INTEGER;
            this.bleFailed = true;
            this.bleMessage = I18nService.isChinese() ?
              '局域网认证重试已停止。网关当前不可达，请确认开发板显示 ONLINE 后点击“继续完成网关绑定”。' :
              'LAN verification retries stopped. Confirm the gateway shows ONLINE, then tap Continue gateway binding.';
          } else {
            this.pendingRetryAfter = Date.now() + this.pendingRetryDelayMs();
          }
          if (!this.bleFailed) {
            this.bleMessage = I18nService.isChinese() ?
              '网关正在启动或暂时不可达，YaoCore 将在后台继续尝试绑定；也可以点击“继续完成网关绑定”立即重试。' :
              'The gateway is starting or temporarily unreachable. YaoCore will keep retrying in the background; tap Continue gateway binding to retry now.';
          }
        }
      }
    }
  }

  private pendingRetryDelayMs(): number {
    const exponent = Math.min(this.pendingAutoRetryCount, DevicePage.PENDING_RETRY_MAX_EXPONENT);
    return Math.min(
      DevicePage.PENDING_RETRY_BASE_MS * Math.pow(2, exponent),
      DevicePage.PENDING_RETRY_MAX_MS
    );
  }

  private errorCode(message: string): string {
    const normalized = message.replace('Error:', '').trim();
    const separator = normalized.indexOf(':');
    const code = separator < 0 ? normalized : normalized.substring(0, separator);
    return code.length === 0 ? 'UNKNOWN' : code;
  }

  private delay(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, milliseconds);
    });
  }

  private async reloadAsync(): Promise<void> {
    await this.viewModel.load();
    await this.securityService.load();
    this.commandKeyReady = this.securityService.hasSessionSecret();
    this.reload();
    if (this.boundGatewayId.length === 0) {
      await this.restorePendingGatewayBinding();
      this.bleExpanded = true;
      if (!this.commandKeyReady) {
        this.bleMessage = I18nService.t('请先保存开发板屏幕对应的控制密钥');
      }
    } else {
      await AppStorageService.clearPendingGatewayBinding();
    }
  }

  private async restorePendingGatewayBinding(): Promise<void> {
    if (this.pendingGatewayBinding) {
      return;
    }
    const binding = await AppStorageService.loadPendingGatewayBinding();
    if (binding === undefined) {
      return;
    }
    this.pendingGatewayId = binding.gatewayId;
    this.pendingGatewayName = binding.gatewayName;
    this.pendingGatewayIp = binding.ipAddress;
    this.pendingGatewayProtocol = binding.protocolVersion;
    this.pendingGatewayBinding = true;
    this.pendingRetryAfter = Date.now();
    this.pendingAutoRetryCount = 0;
    this.pendingAutomaticRetryBlocked = false;
    this.bleMessage = I18nService.isChinese() ?
      '正在恢复尚未完成的网关绑定。' : 'Resuming the pending gateway binding.';
  }

  private reload(): void {
    this.devices = this.viewModel.getAllDevices();
    this.boundGatewayId = this.viewModel.getBoundGatewayId();
    this.gateway = this.viewModel.getGateway();
  }

  private startStateRefresh(): void {
    if (this.stateRefreshTimer >= 0) {
      return;
    }
    this.stateRefreshTimer = setInterval(() => {
      this.reload();
      if (this.pendingGatewayBinding && this.commandKeyReady && !this.pendingAutomaticRetryBlocked &&
        !this.bleProvisioning &&
        Date.now() >= this.pendingRetryAfter) {
        this.retryPendingGatewayBinding(false);
      }
    }, 1000);
  }

  private stopStateRefresh(): void {
    if (this.stateRefreshTimer < 0) {
      return;
    }
    clearInterval(this.stateRefreshTimer);
    this.stateRefreshTimer = -1;
  }

  private async handleGatewayScan(): Promise<void> {
    if (this.scanningGateways || this.scanningDevices || this.bleScanning || this.bleProvisioning ||
      this.scanningWiFiNetworks) {
      return;
    }
    this.hasScannedGateways = false;
    this.discoveredGateways = [];
    this.scanningGateways = true;
    this.message = I18nService.t('正在扫描网关');
    try {
      const result = await this.viewModel.scanLanDevices();
      this.discoveredGateways = result.gateways === undefined ? [] : result.gateways;
      this.message = this.discoveredGateways.length > 0 ?
        `发现 ${this.discoveredGateways.length} 个网关` : result.message;
    } catch (error) {
      this.discoveredGateways = [];
      this.message = I18nService.t('扫描失败，请重试');
    } finally {
      this.scanningGateways = false;
      this.hasScannedGateways = true;
    }
  }

  private async handleDeviceScan(): Promise<void> {
    if (this.boundGatewayId.length === 0) {
      this.message = I18nService.t('请先添加网关');
      return;
    }
    if (this.scanningGateways || this.scanningDevices || this.bleScanning || this.bleProvisioning ||
      this.scanningWiFiNetworks) {
      return;
    }
    this.manualExpanded = false;
    this.hasScannedDevices = false;
    this.discovered = [];
    this.scanningDevices = true;
    this.message = I18nService.t('正在扫描设备');
    try {
      const result = await this.viewModel.scanLanDevices();
      const matched: DiscoveredDevice[] = [];
      for (let index = 0; index < result.devices.length; index++) {
        if (result.devices[index].gatewayId === this.boundGatewayId) {
          matched.push(result.devices[index]);
        }
      }
      this.discovered = matched;
      this.message = matched.length > 0 ? `发现 ${matched.length} 台设备` : I18nService.t('未发现设备');
    } catch (error) {
      this.discovered = [];
      this.message = I18nService.t('扫描失败，可尝试手动添加');
    } finally {
      this.scanningDevices = false;
      this.hasScannedDevices = true;
    }
  }

  private async handleAddDevice(): Promise<void> {
    if (this.draftName.trim().length === 0) {
      this.message = I18nService.t('请输入设备名称');
      return;
    }
    const draft: DeviceDraft = {
      deviceName: this.draftName,
      roomName: this.draftRoom,
      deviceType: this.draftType,
      brand: this.draftBrand,
      protocol: 'manual'
    };
    await this.viewModel.addDevice(draft);
    this.draftName = '';
    this.draftRoom = '';
    this.draftBrand = '';
    this.message = I18nService.t('已保存待绑定离线占位；通过网关发现并绑定真实设备后才可使用');
    this.manualExpanded = false;
    this.reload();
  }

  private async handleBind(item: DiscoveredDevice): Promise<void> {
    if (!this.isGatewayBound(item.gatewayId)) {
      this.message = I18nService.t('请先添加网关');
      return;
    }
    await this.viewModel.bindDiscoveredDevice(item);
    this.message = I18nService.isChinese() ?
      `${item.deviceName} 已与网关真实设备绑定` : `${item.deviceName} is bound to the physical gateway device`;
    this.reload();
  }

  private async handleBindGateway(gateway: DiscoveredGateway): Promise<void> {
    const result = await this.viewModel.bindGateway(gateway);
    if (result.success) {
      this.boundGatewayId = gateway.gatewayId;
      await this.clearPendingGateway();
      this.discovered = [];
      this.hasScannedDevices = false;
      this.manualExpanded = false;
    }
    this.message = result.message;
    this.reload();
  }

  private showGatewayRemovalWarning(): void {
    if (this.deletingGateway || this.boundGatewayId.length === 0) return;
    this.pendingGatewayRemovalId = this.boundGatewayId;
    this.pendingGatewayRemovalName = this.gateway.gatewayName;
    this.showGatewayRemovalDialog = true;
  }

  private async handleRemoveGateway(gatewayId: string): Promise<void> {
    if (this.deletingGateway) return;
    this.deletingGateway = true;
    this.message = I18nService.t('正在删除网关绑定…');
    try {
      const result = await this.viewModel.removeGateway(gatewayId);
      this.message = result.message;
      if (result.removed) {
        this.showGatewayRemovalDialog = false;
        this.gatewayDetailsExpanded = false;
        this.discovered = [];
        this.discoveredGateways = [];
        this.hasScannedDevices = false;
        this.hasScannedGateways = false;
        this.commandKeyReady = false;
        this.commandSecretInput = '';
        this.editingCommandKey = false;
        await this.clearPendingGateway();
        this.onCommandKeyChanged(false);
        this.sceneCleanupNotice = result.sceneCleanup.removedActionCount > 0 ?
          I18nService.t('网关已删除，相关场景已自动更新') : I18nService.t('网关已删除');
      }
    } catch (_) {
      this.message = I18nService.t('网关删除失败，绑定信息未更改');
    } finally {
      this.deletingGateway = false;
      this.reload();
    }
  }

  private async handleRemoveDevice(deviceId: string): Promise<void> {
    const result = await this.viewModel.removeDevice(deviceId);
    this.message = result.removed ? I18nService.t('设备已删除') : I18nService.t('删除失败');
    this.sceneCleanupNotice = result.sceneCleanup.removedActionCount > 0 ? I18nService.t('相关场景已自动更新') : '';
    this.reload();
  }

  private async handleCloudSync(): Promise<void> {
    if (this.syncingDevices) {
      return;
    }
    this.syncingDevices = true;
    this.message = I18nService.t('同步中…');
    try {
      const result = await this.viewModel.syncDevicesToCloud();
      this.message = result.success ? I18nService.t('状态已同步') : I18nService.t('同步失败，请重试');
    } catch (error) {
      this.message = I18nService.t('同步失败，请重试');
    } finally {
      this.syncingDevices = false;
    }
  }

  private async handleQuickAction(device: DeviceState): Promise<void> {
    if (this.isPendingPlaceholder(device)) {
      this.message = I18nService.t('这是待绑定离线占位，请先通过网关发现并绑定真实设备');
      return;
    }
    if (device.deviceType === DeviceType.DOOR) {
      const result = await this.viewModel.toggleDoor(device);
      this.message = result.success ?
        (I18nService.isChinese() ? `${device.deviceName} 已更新` : `${device.deviceName} updated`) :
        I18nService.t('操作失败，请重试');
    } else if (device.deviceType === DeviceType.SENSOR) {
      this.message = I18nService.t('传感器仅显示状态');
    } else {
      const result = await this.viewModel.togglePower(device);
      this.message = result.success ?
        (I18nService.isChinese() ? `${device.deviceName} 已更新` : `${device.deviceName} updated`) :
        I18nService.t('操作失败，请重试');
    }
    this.reload();
  }

  private getFilteredDevices(): DeviceState[] {
    const text = this.keyword.trim().toLowerCase();
    if (text.length === 0) {
      return this.devices;
    }
    const result: DeviceState[] = [];
    for (let index = 0; index < this.devices.length; index++) {
      const device = this.devices[index];
      const brand = device.brand === undefined ? '' : device.brand;
      const haystack = `${device.deviceName}|${device.roomName}|${brand}|${this.viewModel.getTypeLabel(device.deviceType)}`.toLowerCase();
      if (haystack.indexOf(text) >= 0) {
        result.push(device);
      }
    }
    return result;
  }

  private onlineCount(): number {
    let count = 0;
    for (let index = 0; index < this.devices.length; index++) {
      if (this.devices[index].isOnline) {
        count += 1;
      }
    }
    return count;
  }

  private onlineSummary(): string {
    return I18nService.isChinese() ? `${this.onlineCount()}/${this.devices.length} 在线` :
      `${this.onlineCount()}/${this.devices.length} online`;
  }

  private connectedGatewayDetail(): string {
    if (this.gateway.localAvailable) {
      const latency = this.gateway.latencyMs > 0 ? ` · ${this.gateway.latencyMs} ms` : '';
      return `${this.gateway.localIp}${latency}`;
    }
    if (this.gateway.cloudAvailable) return I18nService.t('通过云端连接');
    return this.gateway.localIp;
  }

  private gatewayConnectionLabel(): string {
    if (this.gateway.localAvailable) return I18nService.t('局域网');
    if (this.gateway.cloudAvailable) return I18nService.t('云端');
    return I18nService.t('离线');
  }

  private gatewayStatusColor(): string {
    if (this.gateway.localAvailable || this.gateway.cloudAvailable) return AppColors.SUCCESS;
    return AppColors.WARNING;
  }

  private signalText(rssi: number): string {
    return I18nService.isChinese() ? `信号 ${rssi} dBm` : `Signal ${rssi} dBm`;
  }

  private wifiNetworkSummary(network: BleWiFiNetwork): string {
    return I18nService.isChinese() ?
      `信号 ${network.rssi} dBm · 信道 ${network.channel} · ${this.wifiSecurityLabel(network.authMode)}` :
      `Signal ${network.rssi} dBm · Channel ${network.channel} · ${this.wifiSecurityLabel(network.authMode)}`;
  }

  private deviceCountText(count: number): string {
    return I18nService.isChinese() ? `${count} 台设备` : `${count} devices`;
  }

  private hasDeviceType(type: DeviceType): boolean {
    for (let index = 0; index < this.devices.length; index++) {
      if (this.devices[index].deviceType === type) {
        return true;
      }
    }
    return false;
  }

  private isDeviceBound(deviceId: string): boolean {
    for (let index = 0; index < this.devices.length; index++) {
      if (this.devices[index].deviceId === deviceId) {
        return true;
      }
    }
    return false;
  }

  private isGatewayBound(gatewayId: string): boolean {
    return this.boundGatewayId.length > 0 && this.boundGatewayId === gatewayId;
  }

  private actionLabel(device: DeviceState): string {
    if (this.isPendingPlaceholder(device)) {
      return I18nService.t('等待绑定');
    }
    if (!device.isOnline) {
      return I18nService.t('设备离线');
    }
    if (device.deviceType === DeviceType.DOOR) {
      if (device.openStatus === undefined) return I18nService.t('状态未知');
      return device.openStatus === true ? I18nService.t('上锁') : I18nService.t('开门');
    }
    if (device.deviceType === DeviceType.SENSOR) {
      return I18nService.t('查看');
    }
    if (device.deviceType === DeviceType.CAMERA) {
      return I18nService.t('只读设备');
    }
    if (device.powerStatus === undefined) {
      return I18nService.t('状态未知');
    }
    return this.isPowered(device) ? I18nService.t('关闭') : I18nService.t('开启');
  }

  private isPowered(device: DeviceState): boolean {
    return device.powerStatus === true &&
      !(device.deviceType === DeviceType.LIGHT && device.brightness !== undefined && device.brightness <= 0);
  }

  private deviceRenderKey(device: DeviceState): string {
    // ForEach 会缓存相同 key 的卡片。把真实 ACK 状态加入 key，确保开灯后
    // “开启”立即变成“关闭”，再次点击则发送 OFF，而不是保留旧卡片文字。
    const power = device.powerStatus === undefined ? 'unknown' : (device.powerStatus ? 'on' : 'off');
    const brightness = device.brightness === undefined ? 'na' : `${device.brightness}`;
    const color = device.color === undefined ? 'na' : device.color;
    return `${device.deviceId}:${device.isOnline}:${power}:${brightness}:${color}:${device.updatedAt}`;
  }

  private deviceStateText(device: DeviceState): string {
    if (!device.isOnline) return I18nService.t('设备离线，状态未知');
    if (device.deviceType === DeviceType.SENSOR) {
      if (device.presence !== undefined) return device.presence ? I18nService.t('检测到有人') : I18nService.t('当前无人');
      const temperature = device.temperature === undefined ? '--' : `${device.temperature}℃`;
      const humidity = device.humidity === undefined ? '--' : `${device.humidity}%RH`;
      return I18nService.isChinese() ? `温度 ${temperature} · 湿度 ${humidity}` :
        `Temperature ${temperature} · Humidity ${humidity}`;
    }
    if (device.deviceType === DeviceType.DOOR) {
      return device.openStatus === undefined ? I18nService.t('门状态未知') : (device.openStatus ? I18nService.t('门已打开') : I18nService.t('门已关闭'));
    }
    if (device.deviceType === DeviceType.LIGHT) {
      if (device.powerStatus === undefined) return I18nService.t('灯光状态未知');
      const color = device.color === undefined ? '' :
        (I18nService.isChinese() ? ` · 颜色 ${device.color}` : ` · Color ${device.color}`);
      return device.powerStatus ?
        (I18nService.isChinese() ? `灯已开启 · 亮度 ${device.brightness === undefined ? '--' : device.brightness}%${color}` :
          `Light on · Brightness ${device.brightness === undefined ? '--' : device.brightness}%${color}`) :
        I18nService.t('灯已关闭');
    }
    if (device.deviceType === DeviceType.AC) {
      if (device.powerStatus === undefined) return I18nService.t('空调状态未知');
      return device.powerStatus ?
        (I18nService.isChinese() ?
          `空调已开启 · ${device.mode === undefined ? I18nService.t('模式未知') : device.mode} · ${device.targetTemperature === undefined ? '--' : device.targetTemperature}℃` :
          `AC on · ${device.mode === undefined ? I18nService.t('模式未知') : device.mode} · ${device.targetTemperature === undefined ? '--' : device.targetTemperature}℃`) :
        I18nService.t('空调已关闭');
    }
    if (device.powerStatus !== undefined) return device.powerStatus ? I18nService.t('已开启') : I18nService.t('已关闭');
    return I18nService.t('状态已同步');
  }

  private stateSourceText(device: DeviceState): string {
    if (device.automationId !== undefined && device.automationId.length > 0) {
      const trigger = device.triggerDeviceId === undefined || device.triggerDeviceId.length === 0 ?
        I18nService.t('传感器') : device.triggerDeviceId;
      return I18nService.isChinese() ? `本地自动化 ${device.automationId}（由 ${trigger} 触发）` :
        `Local automation ${device.automationId} (triggered by ${trigger})`;
    }
    if (device.stateSource === 'sensor.physical') return I18nService.t('物理传感器上报');
    if (device.stateSource === 'device.feedback') return I18nService.t('设备主动反馈');
    if (device.stateSource === 'app.lan') return I18nService.t('手机局域网控制确认');
    if (device.stateSource === 'app.cloud') return I18nService.t('手机云端控制确认');
    return I18nService.isChinese() ? `状态来源 ${device.stateSource}` : `State source ${device.stateSource}`;
  }

  private canQuickControl(device: DeviceState): boolean {
    if (this.isPendingPlaceholder(device) || !device.isOnline || device.deviceType === DeviceType.CAMERA) return false;
    if (device.deviceType === DeviceType.SENSOR) return true;
    if (device.deviceType === DeviceType.DOOR) return device.openStatus !== undefined;
    return device.powerStatus !== undefined;
  }

  private isPendingPlaceholder(device: DeviceState): boolean {
    return device.protocol === 'manual' || device.gatewayId === undefined || device.gatewayId.trim().length === 0;
  }

  private deviceAccent(type: DeviceType): string {
    if (type === DeviceType.DOOR) {
      return AppColors.WARNING;
    }
    if (type === DeviceType.SENSOR) {
      return AppColors.SUCCESS;
    }
    if (type === DeviceType.AC) {
      return AppColors.ACCENT;
    }
    return AppColors.PRIMARY;
  }
}
