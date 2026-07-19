/*
 * YaoCore - capability-driven device control page
 * Copyright (c) 2026 Zhang HaoXuan
 * SPDX-License-Identifier: Apache-2.0
 */

import { AppColors, AppMetrics, AppTypography } from '../common/constants/AppTheme';
import { ControlResult } from '../common/types/CommandTypes';
import { createDevicePlaceholder, DeviceState, DeviceType } from '../model/DeviceModel';
import { I18nService } from '../service/I18nService';
import { DeviceViewModel } from '../viewmodel/DeviceViewModel';

@Component
export struct DeviceControlPage {
  private viewModel: DeviceViewModel = new DeviceViewModel();
  private refreshTimer: number = -1;
  private refreshInFlight: boolean = false;
  private liveControlTimer: number = -1;
  private liveControlInFlight: boolean = false;
  private activeLiveControl: string = '';
  private pendingLiveControl: string = '';
  private pendingBrightness: number = 0;
  private pendingColor: string = '#FFFFFF';
  private lastLiveControlStartedAt: number = 0;
  @Prop deviceId: string = '';
  @Prop languageRevision: number = 0;
  onBack: () => void = () => {};

  @State private device: DeviceState = createDevicePlaceholder();
  @State private busy: boolean = false;
  @State private message: string = '';
  @State private brightnessValue: number = 0;
  @State private colorValue: string = '#FFFFFF';
  @State private hueValue: number = 0;
  @State private brightnessDragging: boolean = false;
  @State private colorDragging: boolean = false;
  @State private targetTemperature: number = 24;
  @State private positionValue: number = 0;
  @State private level: number = 0;
  @State private editingMetadata: boolean = false;
  @State private nameInput: string = '';
  @State private roomInput: string = '';

  aboutToAppear(): void {
    this.load();
    this.refreshLiveState();
    // Physical knob/module reports are committed by the gateway before this
    // authenticated snapshot is returned. 350 ms keeps the detail UI visibly
    // in step without overlapping requests on typical 2.4 GHz networks.
    this.refreshTimer = setInterval(() => this.refreshLiveState(), 350);
  }

  aboutToDisappear(): void {
    if (this.refreshTimer >= 0) clearInterval(this.refreshTimer);
    this.refreshTimer = -1;
    if (this.liveControlTimer >= 0) clearTimeout(this.liveControlTimer);
    this.liveControlTimer = -1;
  }

  build() {
    Column() {
      this.header()
      Scroll() {
        Column({ space: AppMetrics.SECTION_GAP }) {
          this.summary()
          this.metadataCard()
          if (this.device.deviceType === DeviceType.LIGHT) {
            this.lightControls()
          } else if (this.device.deviceType === DeviceType.AC) {
            this.acControls()
          } else if (this.device.deviceType === DeviceType.DOOR) {
            this.doorControls()
          } else if (this.device.deviceType === DeviceType.CURTAIN) {
            this.curtainControls()
          } else if (this.device.deviceType === DeviceType.FAN) {
            this.levelControls(this.zh('风速', 'Fan speed'), true)
          } else if (this.device.deviceType === DeviceType.SPEAKER) {
            this.levelControls(this.zh('音量', 'Volume'), false)
          } else if (this.device.deviceType === DeviceType.SENSOR || this.device.deviceType === DeviceType.CAMERA) {
            this.readOnlyControls()
          } else {
            this.switchControls()
          }
          this.feedback()
        }
        .width('100%')
        .padding({ left: AppMetrics.PAGE_PADDING, right: AppMetrics.PAGE_PADDING, bottom: 30 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .linearGradient({ angle: 145, colors: [[AppColors.BACKGROUND, 0.0], [AppColors.BACKGROUND_END, 1.0]] })
  }

  @Builder
  metadataCard() {
    Column({ space: 12 }) {
      Row() {
        Text(this.zh('设备信息', 'Device information'))
          .fontSize(AppTypography.SECTION_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
        Blank()
        if (!this.editingMetadata) {
          Button(this.zh('编辑', 'Edit'))
            .height(34)
            .padding({ left: 14, right: 14 })
            .enabled(!this.busy && this.device.deviceId.length > 0)
            .backgroundColor(AppColors.PRIMARY_SOFT)
            .fontColor(AppColors.PRIMARY_DARK)
            .borderRadius(AppMetrics.PILL_RADIUS)
            .onClick(() => {
              this.nameInput = this.device.deviceName;
              this.roomInput = this.device.roomName;
              this.editingMetadata = true;
            })
        }
      }
      .width('100%')

      if (this.editingMetadata) {
        TextInput({ placeholder: this.zh('设备名称', 'Device name'), text: this.nameInput })
          .height(42)
          .maxLength(20)
          .enabled(!this.busy)
          .backgroundColor(AppColors.SURFACE_SOFT)
          .borderRadius(AppMetrics.INNER_RADIUS)
          .onChange((value: string) => { this.nameInput = value; })
        TextInput({ placeholder: this.zh('房间', 'Room'), text: this.roomInput })
          .height(42)
          .maxLength(10)
          .enabled(!this.busy)
          .backgroundColor(AppColors.SURFACE_SOFT)
          .borderRadius(AppMetrics.INNER_RADIUS)
          .onChange((value: string) => { this.roomInput = value; })
        Row({ space: 10 }) {
          Button(this.zh('取消', 'Cancel'))
            .layoutWeight(1)
            .height(40)
            .enabled(!this.busy)
            .backgroundColor(AppColors.SURFACE_SOFT)
            .fontColor(AppColors.TEXT_SECONDARY)
            .onClick(() => { this.editingMetadata = false; })
          Button(this.zh('保存到网关', 'Save to gateway'))
            .layoutWeight(1)
            .height(40)
            .enabled(!this.busy && this.nameInput.trim().length > 0 && this.roomInput.trim().length > 0)
            .backgroundColor(AppColors.PRIMARY)
            .fontColor(AppColors.WHITE)
            .onClick(() => { this.saveMetadata(); })
        }
        .width('100%')
      } else {
        Row() {
          Text(this.zh('名称', 'Name')).fontSize(AppTypography.BODY).fontColor(AppColors.TEXT_MUTED)
          Blank()
          Text(this.device.deviceName).fontSize(AppTypography.BODY).fontColor(AppColors.TEXT_PRIMARY).maxLines(1)
        }.width('100%')
        Row() {
          Text(this.zh('房间', 'Room')).fontSize(AppTypography.BODY).fontColor(AppColors.TEXT_MUTED)
          Blank()
          Text(this.device.roomName).fontSize(AppTypography.BODY).fontColor(AppColors.TEXT_PRIMARY).maxLines(1)
        }.width('100%')
      }
    }
    .width('100%')
    .padding(AppMetrics.CARD_PADDING)
    .backgroundColor(AppColors.SURFACE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .border({ width: 1, color: AppColors.GLASS_BORDER })
    .borderRadius(AppMetrics.CARD_RADIUS)
  }

  @Builder
  header() {
    Row({ space: 12 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22)
          .fontColor([AppColors.TEXT_PRIMARY])
      }
      .width(42)
      .height(42)
      .backgroundColor(AppColors.SURFACE)
      .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
      .border({ width: 1, color: AppColors.GLASS_BORDER })
      .borderRadius(21)
      .onClick(() => this.onBack())
      Column({ space: 2 }) {
        Text(this.device.deviceName)
          .fontSize(AppTypography.PAGE_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .maxLines(1)
        Text(`${this.device.roomName} · ${this.typeLabel()}`)
          .fontSize(AppTypography.CAPTION)
          .fontColor(AppColors.TEXT_MUTED)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.busy) {
        LoadingProgress().width(24).height(24).color(AppColors.PRIMARY)
      }
    }
    .width('100%')
    .padding({ left: AppMetrics.PAGE_PADDING, right: AppMetrics.PAGE_PADDING, top: 14, bottom: 14 })
    .backgroundColor(AppColors.NAV_SURFACE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
  }

  @Builder
  summary() {
    Column({ space: 12 }) {
      Row() {
        Text(this.device.isOnline ? this.zh('在线', 'Online') : this.zh('离线', 'Offline'))
          .fontSize(AppTypography.CARD_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.device.isOnline ? AppColors.SUCCESS : AppColors.TEXT_MUTED)
        Blank()
        Text(this.device.protocol === undefined ? '--' : this.device.protocol)
          .fontSize(AppTypography.CAPTION)
          .fontColor(AppColors.TEXT_MUTED)
      }
      Text(this.stateText())
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_PRIMARY)
      Text(this.zh('所有操作由网关确认后才更新状态', 'State updates only after gateway acknowledgement'))
        .fontSize(AppTypography.CAPTION)
        .fontColor(AppColors.TEXT_SECONDARY)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(AppMetrics.CARD_PADDING)
    .margin({ top: AppMetrics.PAGE_PADDING })
    .backgroundColor(AppColors.SURFACE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .border({ width: 1, color: AppColors.GLASS_BORDER })
    .borderRadius(AppMetrics.CARD_RADIUS)
  }

  @Builder
  powerButton() {
    Button(this.isPowered(this.device) ? this.zh('关闭', 'Turn off') : this.zh('开启', 'Turn on'))
      .width('100%')
      .height(52)
      .enabled(this.canControl())
      .backgroundColor(this.isPowered(this.device) ? AppColors.TEXT_PRIMARY : AppColors.PRIMARY)
      .fontColor(AppColors.WHITE)
      .borderRadius(AppMetrics.CARD_RADIUS)
      .onClick(() => this.run(this.viewModel.togglePower(this.device)))
  }

  @Builder
  lightControls() {
    Column({ space: 18 }) {
      this.sectionTitle(this.zh('灯光控制', 'Light controls'))
      this.powerButton()
      this.sliderHeader(this.zh('亮度', 'Brightness'), `${Math.round(this.brightnessValue)}%`)
      Slider({ value: this.brightnessValue, min: 0, max: 100, step: 1, style: SliderStyle.OutSet })
        .selectedColor(AppColors.PRIMARY)
        .blockColor(AppColors.WHITE)
        .trackColor(AppColors.BORDER)
        .enabled(this.canControl())
        .onChange((value: number, mode: SliderChangeMode) => {
          this.brightnessValue = Math.round(value);
          const finalValue = mode === SliderChangeMode.End || mode === SliderChangeMode.Click;
          this.brightnessDragging = !finalValue;
          this.queueLiveControl('brightness', finalValue);
        })
      if (this.device.color !== undefined) {
        this.sliderHeader(this.zh('颜色', 'Color'), this.colorValue)
        Row({ space: 12 }) {
          Row()
            .width(42)
            .height(42)
            .borderRadius(21)
            .backgroundColor(this.colorValue)
            .border({ width: 2, color: AppColors.GLASS_BORDER })
          Slider({ value: this.hueValue, min: 0, max: 359, step: 1, style: SliderStyle.OutSet })
            .layoutWeight(1)
            .selectedColor(this.colorValue)
            .blockColor(this.colorValue)
            .trackColor(AppColors.BORDER)
            .enabled(this.canControl())
            .onChange((value: number, mode: SliderChangeMode) => {
              this.hueValue = value;
              this.colorValue = this.hueToColor(value);
              const finalValue = mode === SliderChangeMode.End || mode === SliderChangeMode.Click;
              this.colorDragging = !finalValue;
              this.queueLiveControl('color', finalValue);
            })
        }
        .width('100%')
        Row({ space: 8 }) {
          this.colorPreset('#FF0000')
          this.colorPreset('#FFB000')
          this.colorPreset('#00D060')
          this.colorPreset('#00A0FF')
          this.colorPreset('#6A5CFF')
          this.colorPreset('#FFFFFF')
        }
        .width('100%')
      }
    }
    .controlCard()
  }

  @Builder
  acControls() {
    Column({ space: 18 }) {
      this.sectionTitle(this.zh('空调遥控器', 'Air conditioner'))
      this.powerButton()
      Row() {
        Button('-').controlButton().onClick(() => this.adjustTemperature(-0.5))
        Column({ space: 2 }) {
          Text(this.targetTemperature.toFixed(1)).fontSize(38).fontWeight(FontWeight.Bold).fontColor(AppColors.TEXT_PRIMARY)
          Text('°C').fontSize(AppTypography.BODY).fontColor(AppColors.TEXT_MUTED)
        }.layoutWeight(1)
        Button('+').controlButton().onClick(() => this.adjustTemperature(0.5))
      }.width('100%')
      Row({ space: 8 }) {
        this.modeButton('COOL', this.zh('制冷', 'Cool'))
        this.modeButton('HEAT', this.zh('制热', 'Heat'))
        this.modeButton('FAN', this.zh('送风', 'Fan'))
        this.modeButton('AUTO', this.zh('自动', 'Auto'))
      }.width('100%')
    }
    .controlCard()
  }

  @Builder
  doorControls() {
    Column({ space: 18 }) {
      this.sectionTitle(this.zh('门窗控制', 'Door control'))
      Button(this.device.openStatus === true ? this.zh('关闭', 'Close') : this.zh('打开', 'Open'))
        .width('100%').height(52).enabled(this.canControl())
        .backgroundColor(this.device.openStatus === true ? AppColors.WARNING : AppColors.PRIMARY)
        .fontColor(AppColors.WHITE).borderRadius(AppMetrics.CARD_RADIUS)
        .onClick(() => this.run(this.viewModel.toggleDoor(this.device)))
    }.controlCard()
  }

  @Builder
  curtainControls() {
    Column({ space: 18 }) {
      this.sectionTitle(this.zh('窗帘开合', 'Curtain position'))
      this.sliderHeader(this.zh('打开程度', 'Open position'), `${Math.round(this.positionValue)}%`)
      Slider({ value: this.positionValue, min: 0, max: 100, step: 1, style: SliderStyle.OutSet })
        .selectedColor(AppColors.PRIMARY).trackColor(AppColors.BORDER).enabled(this.canControl())
        .onChange((value: number, mode: SliderChangeMode) => {
          this.positionValue = value;
          if (mode === SliderChangeMode.End) this.run(this.viewModel.setPosition(this.device, Math.round(value)));
        })
      Row({ space: 10 }) {
        Button(this.zh('全关', 'Close')).layoutWeight(1).onClick(() => this.run(this.viewModel.setPosition(this.device, 0)))
        Button(this.zh('停止', 'Stop')).layoutWeight(1).onClick(() => this.run(this.viewModel.stop(this.device)))
        Button(this.zh('全开', 'Open')).layoutWeight(1).onClick(() => this.run(this.viewModel.setPosition(this.device, 100)))
      }.width('100%')
    }.controlCard()
  }

  @Builder
  levelControls(title: string, speed: boolean) {
    Column({ space: 18 }) {
      this.sectionTitle(title)
      this.powerButton()
      this.sliderHeader(title, `${Math.round(this.level)}%`)
      Slider({ value: this.level, min: 0, max: 100, step: 1, style: SliderStyle.OutSet })
        .selectedColor(AppColors.PRIMARY).trackColor(AppColors.BORDER).enabled(this.canControl())
        .onChange((value: number, mode: SliderChangeMode) => {
          this.level = value;
          if (mode === SliderChangeMode.End) {
            this.run(speed ? this.viewModel.setSpeed(this.device, Math.round(value)) :
              this.viewModel.setVolume(this.device, Math.round(value)));
          }
        })
    }.controlCard()
  }

  @Builder
  switchControls() {
    Column({ space: 18 }) {
      this.sectionTitle(this.zh('开关控制', 'Switch control'))
      this.powerButton()
    }.controlCard()
  }

  @Builder
  readOnlyControls() {
    Column({ space: 10 }) {
      this.sectionTitle(this.zh('实时状态', 'Live status'))
      Text(this.zh('此设备当前只上报状态，没有可用的控制能力。', 'This device reports state and has no control capability.'))
        .fontSize(AppTypography.BODY).fontColor(AppColors.TEXT_SECONDARY)
    }.controlCard()
  }

  @Builder sectionTitle(value: string) { Text(value).fontSize(AppTypography.SECTION_TITLE).fontWeight(FontWeight.Bold).fontColor(AppColors.TEXT_PRIMARY).width('100%') }
  @Builder sliderHeader(label: string, value: string) { Row() { Text(label).fontColor(AppColors.TEXT_SECONDARY); Blank(); Text(value).fontWeight(FontWeight.Bold).fontColor(AppColors.PRIMARY_DARK) }.width('100%') }
  @Builder modeButton(mode: string, label: string) { Button(label).layoutWeight(1).height(38).enabled(this.canControl()).backgroundColor(this.modeSelected(mode) ? AppColors.PRIMARY : AppColors.SURFACE_SOFT).fontColor(this.modeSelected(mode) ? AppColors.WHITE : AppColors.TEXT_SECONDARY).onClick(() => this.run(this.viewModel.setMode(this.device, mode))) }
  @Builder colorPreset(color: string) { Button().layoutWeight(1).height(38).enabled(this.canControl()).backgroundColor(color).borderRadius(19).border({ width: this.colorValue === color ? 3 : 1, color: this.colorValue === color ? AppColors.TEXT_PRIMARY : AppColors.GLASS_BORDER }).onClick(() => { this.colorValue = color; this.hueValue = this.colorToHue(color); this.run(this.viewModel.setColor(this.device, color)); }) }

  @Builder
  feedback() {
    if (this.message.length > 0) {
      Row({ space: 10 }) {
        if (this.busy) { LoadingProgress().width(20).height(20).color(AppColors.PRIMARY) }
        Text(this.message).fontSize(AppTypography.BODY).fontColor(AppColors.TEXT_SECONDARY).layoutWeight(1).maxLines(3)
      }.width('100%').padding(14).backgroundColor(AppColors.PRIMARY_SOFT).borderRadius(AppMetrics.CARD_RADIUS)
    }
  }

  private async load(): Promise<void> { await this.viewModel.load(); this.reload(); }
  private reload(): void {
    const devices = this.viewModel.getAllDevices();
    for (let i = 0; i < devices.length; i++) if (devices[i].deviceId === this.deviceId) {
      this.device = devices[i];
      if (!this.busy) {
        if (!this.brightnessDragging && this.pendingLiveControl !== 'brightness' &&
          this.activeLiveControl !== 'brightness') {
          this.brightnessValue = this.device.brightness === undefined ? 0 : this.device.brightness;
        }
        if (!this.colorDragging && this.pendingLiveControl !== 'color' && this.activeLiveControl !== 'color') {
          this.colorValue = this.device.color === undefined ? '#FFFFFF' : this.device.color;
          this.hueValue = this.colorToHue(this.colorValue);
        }
        this.targetTemperature = this.device.targetTemperature === undefined ? 24 : this.device.targetTemperature;
        this.positionValue = this.device.position === undefined ? 0 : this.device.position;
        this.level = this.device.deviceType === DeviceType.SPEAKER ? (this.device.volume === undefined ? 0 : this.device.volume) :
          (this.device.speed === undefined ? 0 : this.device.speed);
        if (!this.editingMetadata) {
          this.nameInput = this.device.deviceName;
          this.roomInput = this.device.roomName;
        }
      }
      return;
    }
  }
  private async refreshLiveState(): Promise<void> {
    // 命令 ACK 已携带 R4 的真实状态。滑块命令执行期间暂停完整设备快照，
    // 避免高频 /discover 与连续控制争抢网关和手机网络资源。
    if (this.refreshInFlight || this.liveControlInFlight || this.pendingLiveControl.length > 0 ||
      this.brightnessDragging || this.colorDragging || this.busy) {
      return;
    }
    this.refreshInFlight = true;
    try {
      await this.viewModel.refreshLiveState();
      this.reload();
    } finally {
      this.refreshInFlight = false;
    }
  }
  private queueLiveControl(kind: string, finalValue: boolean): void {
    this.pendingLiveControl = kind;
    if (kind === 'brightness') this.pendingBrightness = Math.round(this.brightnessValue);
    else this.pendingColor = this.colorValue.toUpperCase();
    if (this.liveControlInFlight) return;
    if (finalValue && this.liveControlTimer >= 0) {
      clearTimeout(this.liveControlTimer);
      this.liveControlTimer = -1;
    }
    this.scheduleLiveControl(finalValue);
  }
  private scheduleLiveControl(finalValue: boolean): void {
    if (this.liveControlInFlight || this.pendingLiveControl.length === 0 || this.liveControlTimer >= 0) return;
    const elapsed = new Date().getTime() - this.lastLiveControlStartedAt;
    const delayMs = finalValue ? 0 : Math.max(0, 55 - elapsed);
    this.liveControlTimer = setTimeout(() => {
      this.liveControlTimer = -1;
      this.flushLiveControl();
    }, delayMs);
  }
  private async flushLiveControl(): Promise<void> {
    if (this.liveControlInFlight || this.pendingLiveControl.length === 0 || !this.canControl()) return;
    const kind = this.pendingLiveControl;
    const brightness = this.pendingBrightness;
    const color = this.pendingColor;
    this.pendingLiveControl = '';
    this.activeLiveControl = kind;
    this.liveControlInFlight = true;
    this.lastLiveControlStartedAt = new Date().getTime();
    try {
      const result = kind === 'brightness' ? await this.viewModel.setBrightness(this.device, brightness) :
        await this.viewModel.setColor(this.device, color);
      if (!result.success) this.message = result.message;
    } catch (_) {
      this.message = this.zh('控制失败，请检查网关连接', 'Control failed. Check the gateway connection.');
    } finally {
      this.liveControlInFlight = false;
      this.activeLiveControl = '';
      this.reload();
      if (this.pendingLiveControl.length > 0) this.scheduleLiveControl(true);
    }
  }
  private async run(operation: Promise<ControlResult>): Promise<void> {
    if (this.busy || !this.canControl()) return;
    this.busy = true; this.message = this.zh('正在等待网关确认…', 'Waiting for gateway acknowledgement…');
    try { const result = await operation; this.message = result.message; this.reload(); }
    catch (_) { this.message = this.zh('控制失败，请检查网关连接', 'Control failed. Check the gateway connection.'); }
    finally { this.busy = false; this.reload(); }
  }
  private async saveMetadata(): Promise<void> {
    if (this.busy || this.device.deviceId.length === 0) return;
    const name = this.nameInput.trim();
    const room = this.roomInput.trim();
    if (name.length < 1 || name.length > 20 || room.length < 1 || room.length > 10) {
      this.message = this.zh('名称需 1–20 个字符，房间需 1–10 个字符',
        'Name must be 1–20 characters and room must be 1–10 characters');
      return;
    }
    this.busy = true;
    this.message = this.zh('正在保存到网关…', 'Saving to gateway…');
    try {
      const result = await this.viewModel.updateMetadata(this.device, name, room);
      this.message = result.message;
      if (result.success) this.editingMetadata = false;
    } catch (_) {
      this.message = this.zh('保存失败，请检查网关连接', 'Save failed. Check the gateway connection.');
    } finally {
      this.busy = false;
      this.reload();
    }
  }
  private adjustTemperature(delta: number): void {
    const next = Math.max(16, Math.min(30, Math.round((this.targetTemperature + delta) * 2) / 2));
    if (next !== this.targetTemperature) { this.targetTemperature = next; this.run(this.viewModel.setTargetTemperature(this.device, next)); }
  }
  private canControl(): boolean { return this.device.isOnline && !this.busy && this.device.deviceId.length > 0; }
  private isPowered(device: DeviceState): boolean {
    return device.powerStatus === true &&
      !(device.deviceType === DeviceType.LIGHT && device.brightness !== undefined && device.brightness <= 0);
  }
  private modeSelected(mode: string): boolean {
    const current = this.device.mode === undefined ? '' : this.device.mode.toUpperCase();
    if (current === mode) return true;
    return (mode === 'COOL' && current === '制冷') || (mode === 'HEAT' && current === '制热') ||
      (mode === 'FAN' && current === '送风') || (mode === 'AUTO' && current === '自动');
  }
  private zh(chinese: string, english: string): string { return I18nService.isChinese() ? chinese : english; }
  private typeLabel(): string { return this.device.deviceType.toUpperCase(); }
  private hueToColor(hue: number): string {
    const normalized = ((Math.round(hue) % 360) + 360) % 360;
    const sector = Math.floor(normalized / 60);
    const fraction = normalized / 60 - sector;
    const rise = Math.round(255 * fraction);
    const fall = 255 - rise;
    if (sector === 0) return `#FF${this.toHex(rise)}00`;
    if (sector === 1) return `#${this.toHex(fall)}FF00`;
    if (sector === 2) return `#00FF${this.toHex(rise)}`;
    if (sector === 3) return `#00${this.toHex(fall)}FF`;
    if (sector === 4) return `#${this.toHex(rise)}00FF`;
    return `#FF00${this.toHex(fall)}`;
  }
  private colorToHue(color: string): number {
    if (color.length !== 7) return 0;
    const red = parseInt(color.substring(1, 3), 16) / 255;
    const green = parseInt(color.substring(3, 5), 16) / 255;
    const blue = parseInt(color.substring(5, 7), 16) / 255;
    const maximum = Math.max(red, green, blue);
    const minimum = Math.min(red, green, blue);
    const delta = maximum - minimum;
    if (delta === 0) return 0;
    let hue = 0;
    if (maximum === red) hue = 60 * (((green - blue) / delta) % 6);
    else if (maximum === green) hue = 60 * ((blue - red) / delta + 2);
    else hue = 60 * ((red - green) / delta + 4);
    return hue < 0 ? hue + 360 : hue;
  }
  private toHex(value: number): string {
    const hex = Math.max(0, Math.min(255, Math.round(value))).toString(16).toUpperCase();
    return hex.length === 1 ? `0${hex}` : hex;
  }
  private stateText(): string {
    if (!this.device.isOnline) return this.zh('设备离线', 'Device offline');
    if (this.device.deviceType === DeviceType.AC) return `${this.targetTemperature.toFixed(1)} °C`;
    if (this.device.deviceType === DeviceType.LIGHT) return this.device.color === undefined ?
      `${Math.round(this.brightnessValue)}%` : `${Math.round(this.brightnessValue)}%  ${this.colorValue}`;
    if (this.device.deviceType === DeviceType.CURTAIN) return `${Math.round(this.positionValue)}%`;
    if (this.device.deviceType === DeviceType.SENSOR) return `${this.device.temperature === undefined ? '--' : this.device.temperature} °C`;
    if (this.device.openStatus !== undefined) return this.device.openStatus ? this.zh('已打开', 'Open') : this.zh('已关闭', 'Closed');
    return this.isPowered(this.device) ? this.zh('已开启', 'On') : this.zh('已关闭', 'Off');
  }
}

@Extend(Column) function controlCard() { .width('100%').padding(AppMetrics.CARD_PADDING).backgroundColor(AppColors.SURFACE).backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR).border({ width: 1, color: AppColors.GLASS_BORDER }).borderRadius(AppMetrics.CARD_RADIUS).shadow({ radius: 12, color: AppColors.GLASS_SHADOW, offsetX: 0, offsetY: 4 }) }
@Extend(Button) function controlButton() { .width(56).height(48).fontSize(24).backgroundColor(AppColors.PRIMARY_SOFT).fontColor(AppColors.PRIMARY_DARK).borderRadius(24) }
