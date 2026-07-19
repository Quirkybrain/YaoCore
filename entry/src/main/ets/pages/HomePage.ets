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
import { ClimateCard } from '../components/ClimateCard';
import { DoorCard } from '../components/DoorCard';
import { LightCard } from '../components/LightCard';
import { StatusBanner } from '../components/StatusBanner';
import { copyDeviceState, createDevicePlaceholder, DeviceState, DeviceType } from '../model/DeviceModel';
import { createDefaultGatewayState, GatewayState } from '../model/GatewayModel';
import { HomeOverview, HomeViewModel } from '../viewmodel/HomeViewModel';

@Component
export struct HomePage {
  private viewModel: HomeViewModel = new HomeViewModel();
  private stateRefreshTimer: number = -1;
  private quickBrightnessTimer: number = -1;
  private quickBrightnessInFlight: boolean = false;
  private pendingQuickBrightness: number | undefined = undefined;
  private lastQuickBrightnessStartedAt: number = 0;
  onOpenDevices: () => void = () => {};
  @Prop languageRevision: number = 0;

  @State private gateway: GatewayState = createDefaultGatewayState();
  @State private overview: HomeOverview = {
    onlineCount: 0,
    totalCount: 0,
    comfortLabel: I18nService.t('未添加设备'),
    securityLabel: I18nService.t('未添加设备')
  };
  @State private door: DeviceState = createDevicePlaceholder('', I18nService.t('门禁'), DeviceType.DOOR);
  @State private light: DeviceState = createDevicePlaceholder('', I18nService.t('灯光'), DeviceType.LIGHT);
  @State private sensor: DeviceState = createDevicePlaceholder('', I18nService.t('温湿度'), DeviceType.SENSOR);
  @State private ac: DeviceState = createDevicePlaceholder('', I18nService.t('空调'), DeviceType.AC);
  @State private devices: DeviceState[] = [];
  @State private lastMessage: string = I18nService.t('暂未添加设备');
  @State private refreshingGateway: boolean = false;

  aboutToAppear(): void {
    this.reloadAsync();
    this.startStateRefresh();
  }

  aboutToDisappear(): void {
    this.stopStateRefresh();
    if (this.quickBrightnessTimer >= 0) clearTimeout(this.quickBrightnessTimer);
    this.quickBrightnessTimer = -1;
  }

  build() {
    Scroll() {
      Column({ space: AppMetrics.SECTION_GAP }) {
        StatusBanner({
          gateway: this.gateway,
          overview: this.overview,
          refreshing: this.refreshingGateway,
          onRefresh: () => {
            this.handleRefreshGateway();
          }
        })

        this.overviewCards()

        if (this.devices.length === 0) {
          this.emptyHome()
        } else if (this.hasQuickControls()) {
          this.quickControls()
        } else {
          this.noQuickControls()
        }
      }
      .width('100%')
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
  overviewCards() {
    Column({ space: AppMetrics.CARD_GAP }) {
      this.sectionHeader(I18nService.t('家庭状态'), '')
      Row({ space: AppMetrics.CARD_GAP }) {
        this.summaryTile(
          this.environmentValue(),
          I18nService.t('室内环境'),
          this.overview.comfortLabel,
          AppColors.PRIMARY,
          AppColors.PRIMARY_SOFT
        )
        this.summaryTile(
          this.lastMessage,
          I18nService.t('最近反馈'),
          '',
          AppColors.ACCENT,
          AppColors.ACCENT_SOFT
        )
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  quickControls() {
    Column({ space: AppMetrics.CARD_GAP }) {
      this.sectionHeader(I18nService.t('常用控制'), `${this.devices.length} 台`)

      if (this.hasDeviceType(DeviceType.DOOR)) {
        DoorCard({
          device: this.door,
          onToggle: () => {
            this.handleToggleDoor();
          }
        })
      }

      if (this.hasDeviceType(DeviceType.LIGHT)) {
        LightCard({
          device: this.light,
          onToggle: () => {
            this.handleToggleLight();
          },
          onBrightnessChange: (value: number, finalValue: boolean) => {
            this.handleBrightness(value, finalValue);
          }
        })
      }

      if (this.hasDeviceType(DeviceType.SENSOR) && this.hasDeviceType(DeviceType.AC)) {
        ClimateCard({
          sensor: this.sensor,
          ac: this.ac,
          onAcToggle: () => {
            this.handleToggleAc();
          },
          onTemperatureChange: (value: number) => {
            this.handleTemperature(value);
          },
          onModeChange: (mode: string) => {
            this.handleMode(mode);
          }
        })
      }
    }
    .width('100%')
  }

  @Builder
  emptyHome() {
    Column({ space: 12 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.square_grid_2x2'))
          .fontSize(28)
          .fontColor([AppColors.PRIMARY])
      }
      .width(52)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(AppColors.PRIMARY_SOFT)
      .borderRadius(AppMetrics.INNER_RADIUS)

      Text(I18nService.t('把第一台设备带回家'))
        .fontSize(AppTypography.CARD_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.TEXT_PRIMARY)
      Text(I18nService.t('前往设备页添加设备。'))
        .fontSize(AppTypography.BODY)
        .fontColor(AppColors.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .maxLines(2)

      Button(I18nService.t('前往设备页'))
        .height(AppMetrics.CONTROL_HEIGHT)
        .padding({ left: 22, right: 22 })
        .backgroundColor(AppColors.PRIMARY)
        .fontColor(AppColors.WHITE)
        .borderRadius(AppMetrics.PILL_RADIUS)
        .onClick(() => {
          this.onOpenDevices();
        })
    }
    .width('100%')
    .padding({ top: 26, bottom: 26, left: AppMetrics.CARD_PADDING, right: AppMetrics.CARD_PADDING })
    .backgroundColor(AppColors.SURFACE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .border({ width: 1, color: AppColors.GLASS_BORDER })
    .borderRadius(AppMetrics.CARD_RADIUS)
    .shadow({ radius: 14, color: AppColors.GLASS_SHADOW, offsetX: 0, offsetY: 5 })
  }

  @Builder
  noQuickControls() {
    Column({ space: 10 }) {
      this.sectionHeader(I18nService.t('常用控制'), `${this.devices.length} 台`)
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.slider_horizontal_2'))
          .fontSize(24)
          .fontColor([AppColors.PRIMARY])
        Column({ space: 4 }) {
          Text(I18nService.t('前往设备页控制'))
            .fontSize(AppTypography.CARD_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Button(I18nService.t('查看'))
          .height(38)
          .padding({ left: 16, right: 16 })
          .backgroundColor(AppColors.PRIMARY_SOFT)
          .fontColor(AppColors.PRIMARY_DARK)
          .borderRadius(AppMetrics.PILL_RADIUS)
          .onClick(() => {
            this.onOpenDevices();
          })
      }
      .width('100%')
      .padding(AppMetrics.CARD_PADDING)
      .backgroundColor(AppColors.SURFACE)
      .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
      .border({ width: 1, color: AppColors.GLASS_BORDER })
      .borderRadius(AppMetrics.CARD_RADIUS)
      .shadow({ radius: 10, color: AppColors.SHADOW, offsetX: 0, offsetY: 3 })
    }
    .width('100%')
  }

  @Builder
  sectionHeader(title: string, subtitle: string) {
    Row() {
      Text(title)
        .fontSize(AppTypography.SECTION_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.TEXT_PRIMARY)
      Blank()
      if (subtitle.length > 0) {
        Text(subtitle)
          .fontSize(AppTypography.CAPTION)
          .fontColor(AppColors.TEXT_MUTED)
          .maxLines(1)
      }
    }
    .width('100%')
  }

  @Builder
  summaryTile(value: string, label: string, helper: string, accent: string, softColor: string) {
    Column({ space: 7 }) {
      Row() {
        Text(label)
          .fontSize(AppTypography.CAPTION)
          .fontColor(AppColors.TEXT_MUTED)
        Blank()
        Column()
          .width(8)
          .height(8)
          .backgroundColor(accent)
          .borderRadius(4)
      }
      .width('100%')

      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.TEXT_PRIMARY)
        .maxLines(2)
      if (helper.length > 0) {
        Text(helper)
          .fontSize(11)
          .fontColor(accent)
          .maxLines(1)
      }
    }
    .layoutWeight(1)
    .height(112)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(softColor)
    .borderRadius(AppMetrics.CARD_RADIUS)
  }

  private reload(): void {
    this.gateway = this.viewModel.getGateway();
    this.overview = this.viewModel.getOverview();
    this.devices = this.viewModel.getDevices();
    this.door = this.viewModel.getDoor();
    this.light = this.viewModel.getLight();
    this.sensor = this.viewModel.getSensor();
    this.ac = this.viewModel.getAc();
    if (this.devices.length === 0) {
      this.lastMessage = I18nService.t('暂未添加设备');
    }
  }

  private async reloadAsync(): Promise<void> {
    await this.viewModel.load();
    this.reload();
  }

  private async handleRefreshGateway(): Promise<void> {
    if (this.refreshingGateway) {
      return;
    }
    this.refreshingGateway = true;
    const startedAt = Date.now();
    this.lastMessage = I18nService.t('正在刷新…');
    try {
      this.gateway = await this.viewModel.refreshGateway();
      this.reload();
      if (this.devices.length > 0) {
        this.lastMessage = this.gateway.localAvailable ? I18nService.t('网关在线') : I18nService.t('云端可用');
      } else {
        this.lastMessage = I18nService.t('暂未添加设备');
      }
    } catch (error) {
      this.lastMessage = I18nService.t('刷新失败，请重试');
    } finally {
      const remaining = 650 - (Date.now() - startedAt);
      if (remaining > 0) await new Promise<void>((resolve: () => void) => setTimeout(resolve, remaining));
      this.refreshingGateway = false;
    }
  }

  private async handleToggleDoor(): Promise<void> {
    const result = await this.viewModel.toggleDoor();
    this.lastMessage = result.message;
    this.reload();
  }

  private async handleToggleLight(): Promise<void> {
    const result = await this.viewModel.toggleLight();
    this.lastMessage = result.message;
    this.reload();
  }

  private async handleToggleAc(): Promise<void> {
    const result = await this.viewModel.toggleAc();
    this.lastMessage = result.message;
    this.reload();
  }

  private handleBrightness(value: number, finalValue: boolean): void {
    const normalized = Math.max(0, Math.min(100, Math.round(value)));
    const preview = copyDeviceState(this.light);
    preview.brightness = normalized;
    preview.powerStatus = normalized > 0;
    this.light = preview;
    this.pendingQuickBrightness = normalized;
    if (this.quickBrightnessInFlight) return;
    if (finalValue && this.quickBrightnessTimer >= 0) {
      clearTimeout(this.quickBrightnessTimer);
      this.quickBrightnessTimer = -1;
    }
    this.scheduleQuickBrightness(finalValue);
  }

  private scheduleQuickBrightness(finalValue: boolean): void {
    if (this.quickBrightnessInFlight || this.pendingQuickBrightness === undefined ||
      this.quickBrightnessTimer >= 0) return;
    const elapsed = new Date().getTime() - this.lastQuickBrightnessStartedAt;
    const delayMs = finalValue ? 0 : Math.max(0, 55 - elapsed);
    this.quickBrightnessTimer = setTimeout(() => {
      this.quickBrightnessTimer = -1;
      this.flushQuickBrightness();
    }, delayMs);
  }

  private async flushQuickBrightness(): Promise<void> {
    if (this.quickBrightnessInFlight || this.pendingQuickBrightness === undefined) return;
    const value = this.pendingQuickBrightness;
    this.pendingQuickBrightness = undefined;
    this.quickBrightnessInFlight = true;
    this.lastQuickBrightnessStartedAt = new Date().getTime();
    try {
      const result = await this.viewModel.setLightBrightness(value);
      this.lastMessage = result.message;
    } catch (_) {
      this.lastMessage = I18nService.t('控制失败，请检查网关连接');
    } finally {
      this.quickBrightnessInFlight = false;
      this.reload();
      if (this.pendingQuickBrightness !== undefined) {
        const preview = copyDeviceState(this.light);
        preview.brightness = this.pendingQuickBrightness;
        preview.powerStatus = this.pendingQuickBrightness > 0;
        this.light = preview;
        this.scheduleQuickBrightness(true);
      }
    }
  }

  private async handleTemperature(value: number): Promise<void> {
    const result = await this.viewModel.setAcTemperature(value);
    this.lastMessage = result.message;
    this.reload();
  }

  private async handleMode(mode: string): Promise<void> {
    const result = await this.viewModel.setAcMode(mode);
    this.lastMessage = result.message;
    this.reload();
  }

  private hasDeviceType(type: DeviceType): boolean {
    for (let index = 0; index < this.devices.length; index++) {
      if (this.devices[index].deviceType === type) {
        return true;
      }
    }
    return false;
  }

  private hasQuickControls(): boolean {
    return this.hasDeviceType(DeviceType.DOOR) ||
      this.hasDeviceType(DeviceType.LIGHT) ||
      (this.hasDeviceType(DeviceType.SENSOR) && this.hasDeviceType(DeviceType.AC));
  }

  private environmentValue(): string {
    if (!this.hasDeviceType(DeviceType.SENSOR)) {
      return this.overview.comfortLabel;
    }
    const temperature = this.sensor.temperature === undefined ? '--' : `${this.sensor.temperature}℃`;
    const humidity = this.sensor.humidity === undefined ? '--' : `${this.sensor.humidity}%`;
    let presenceText = '';
    for (let index = 0; index < this.devices.length; index++) {
      if (this.devices[index].deviceType === DeviceType.SENSOR &&
        this.devices[index].presence !== undefined && this.devices[index].isOnline) {
        presenceText = this.devices[index].presence ? I18nService.t(' · 有人') : I18nService.t(' · 无人');
        break;
      }
    }
    return `${temperature} · ${humidity}${presenceText}`;
  }

  private startStateRefresh(): void {
    if (this.stateRefreshTimer >= 0) {
      return;
    }
    this.stateRefreshTimer = setInterval(() => {
      this.reload();
    }, 600);
  }

  private stopStateRefresh(): void {
    if (this.stateRefreshTimer < 0) {
      return;
    }
    clearInterval(this.stateRefreshTimer);
    this.stateRefreshTimer = -1;
  }
}
