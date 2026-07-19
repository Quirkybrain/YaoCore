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
import { CommandValue } from '../common/types/CommandTypes';
import { DeviceAction, DeviceState, DeviceType } from '../model/DeviceModel';
import { SceneAction, SceneDefinition, SceneDraft } from '../model/SceneModel';
import { SceneViewModel } from '../viewmodel/SceneViewModel';

@Component
export struct ScenePage {
  private viewModel: SceneViewModel = new SceneViewModel();
  @Prop languageRevision: number = 0;
  @State private scenes: SceneDefinition[] = [];
  @State private devices: DeviceState[] = [];
  @State private runningSceneId: string = '';
  @State private message: string = I18nService.t('一键开启常用场景');
  @State private editorExpanded: boolean = false;
  @State private draftSceneId: string = '';
  @State private draftName: string = '';
  @State private draftDescription: string = '';
  @State private draftAccent: string = AppColors.PRIMARY;
  @State private selectedDeviceId: string = '';
  @State private selectedAction: string = DeviceAction.TURN_ON;
  @State private numericValue: number = 50;
  @State private colorValue: string = '#FFFFFF';
  @State private modeValue: string = 'AUTO';
  @State private draftActions: SceneAction[] = [];

  aboutToAppear(): void {
    this.reloadAsync();
  }

  build() {
    Scroll() {
      Column({ space: AppMetrics.SECTION_GAP }) {
        this.pageHeader()
        if (this.editorExpanded) {
          this.editorPanel()
        }
        this.sceneList()
      }
      .padding(AppMetrics.PAGE_PADDING)
    }
    .width('100%')
    .height('100%')
    .linearGradient({ angle: 145, colors: [[AppColors.BACKGROUND, 0.0], [AppColors.BACKGROUND_END, 1.0]] })
  }

  @Builder
  pageHeader() {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 4 }) {
          Text(I18nService.t('场景'))
            .fontSize(AppTypography.PAGE_TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text(this.message)
            .fontSize(AppTypography.CAPTION)
            .fontColor(AppColors.TEXT_SECONDARY)
            .maxLines(2)
        }
        .layoutWeight(1)
        Button(this.editorExpanded ? I18nService.t('收起') : I18nService.t('新建'))
          .height(36)
          .padding({ left: 14, right: 14 })
          .backgroundColor(this.editorExpanded ? AppColors.SURFACE_SOFT : AppColors.PRIMARY)
          .fontColor(this.editorExpanded ? AppColors.TEXT_SECONDARY : AppColors.SURFACE)
          .borderRadius(AppMetrics.CARD_RADIUS)
          .onClick(() => {
            if (this.editorExpanded) {
              this.cancelEditor();
            } else {
              this.beginCreateScene();
            }
          })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  editorPanel() {
    Column({ space: 12 }) {
      Row() {
        Text(this.draftSceneId.length > 0 ? I18nService.t('编辑场景') : I18nService.t('新建场景'))
          .fontSize(AppTypography.SECTION_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
      }
      .width('100%')

      TextInput({ placeholder: I18nService.t('场景名称'), text: this.draftName })
        .height(42)
        .backgroundColor(AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onChange((value: string) => {
          this.draftName = value;
        })

      TextInput({ placeholder: I18nService.t('一句话说明（可选）'), text: this.draftDescription })
        .height(42)
        .backgroundColor(AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onChange((value: string) => {
          this.draftDescription = value;
        })

      this.colorPicker()
      this.devicePicker()
      this.actionPicker()
      this.actionValueEditor()

      Row({ space: 10 }) {
        Button(I18nService.t('添加动作'))
          .layoutWeight(1)
          .height(AppMetrics.CONTROL_HEIGHT)
          .backgroundColor(AppColors.PRIMARY)
          .fontColor(AppColors.SURFACE)
          .borderRadius(AppMetrics.CARD_RADIUS)
          .onClick(() => {
            this.addDraftAction();
          })
        Button(I18nService.t('清空'))
          .layoutWeight(1)
          .height(AppMetrics.CONTROL_HEIGHT)
          .backgroundColor(AppColors.SURFACE_SOFT)
          .fontColor(AppColors.TEXT_SECONDARY)
          .borderRadius(AppMetrics.CARD_RADIUS)
          .onClick(() => {
            this.draftActions = [];
          })
      }
      .width('100%')

      this.draftActionList()

      Button(this.draftSceneId.length > 0 ? I18nService.t('保存修改') : I18nService.t('保存场景'))
        .width('100%')
        .height(AppMetrics.CONTROL_HEIGHT)
        .backgroundColor(AppColors.TEXT_PRIMARY)
        .fontColor(AppColors.SURFACE)
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onClick(() => {
          this.saveDraftScene();
        })
    }
    .width('100%')
    .padding(AppMetrics.CARD_PADDING)
    .backgroundColor(AppColors.SURFACE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .borderRadius(AppMetrics.CARD_RADIUS)
    .border({ width: 1, color: AppColors.GLASS_BORDER })
    .shadow({ radius: 14, color: AppColors.GLASS_SHADOW, offsetX: 0, offsetY: 5 })
  }

  @Builder
  sceneCountPill(text: string, color: string) {
    Text(text)
      .fontSize(AppTypography.CAPTION)
      .fontColor(color)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(AppColors.SURFACE_SOFT)
      .borderRadius(AppMetrics.CARD_RADIUS)
  }

  @Builder
  colorPicker() {
    Column({ space: 8 }) {
      Text(I18nService.t('颜色'))
        .fontSize(AppTypography.CAPTION)
        .fontColor(AppColors.TEXT_SECONDARY)
      Row({ space: 10 }) {
        this.colorDot(AppColors.PRIMARY)
        this.colorDot(AppColors.ACCENT)
        this.colorDot(AppColors.SUCCESS)
        this.colorDot(AppColors.WARNING)
        this.colorDot(AppColors.PRIMARY_DARK)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  colorDot(color: string) {
    Column()
      .width(28)
      .height(28)
      .backgroundColor(color)
      .borderRadius(14)
      .border({ width: this.draftAccent === color ? 3 : 0, color: AppColors.TEXT_PRIMARY })
      .onClick(() => {
        this.draftAccent = color;
      })
  }

  @Builder
  devicePicker() {
    Column({ space: 8 }) {
      Text(I18nService.t('设备'))
        .fontSize(AppTypography.CAPTION)
        .fontColor(AppColors.TEXT_SECONDARY)
      if (this.devices.length === 0) {
        Text(I18nService.t('请先添加设备。'))
          .fontSize(AppTypography.CAPTION)
          .fontColor(AppColors.TEXT_MUTED)
          .width('100%')
          .padding(12)
          .backgroundColor(AppColors.SURFACE_SOFT)
          .borderRadius(AppMetrics.CARD_RADIUS)
      } else {
        ForEach(this.devices, (device: DeviceState) => {
          this.deviceChoice(device)
        }, (device: DeviceState) => device.deviceId)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  deviceChoice(device: DeviceState) {
    Row() {
      Column({ space: 3 }) {
        Text(device.deviceName)
          .fontSize(AppTypography.BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.selectedDeviceId === device.deviceId ? AppColors.PRIMARY : AppColors.TEXT_PRIMARY)
          .maxLines(1)
        Text(`${device.roomName} · ${this.viewModel.getTypeLabel(device.deviceType)}`)
          .fontSize(AppTypography.CAPTION)
          .fontColor(AppColors.TEXT_MUTED)
          .maxLines(1)
      }
      .layoutWeight(1)
      Text(this.selectedDeviceId === device.deviceId ? I18nService.t('已选') : I18nService.t('选择'))
        .fontSize(AppTypography.CAPTION)
        .fontColor(this.selectedDeviceId === device.deviceId ? AppColors.PRIMARY : AppColors.TEXT_MUTED)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(AppColors.SURFACE_SOFT)
    .border({ width: this.selectedDeviceId === device.deviceId ? 1 : 0, color: AppColors.PRIMARY })
    .borderRadius(AppMetrics.CARD_RADIUS)
    .onClick(() => {
      this.selectDevice(device);
    })
  }

  @Builder
  actionPicker() {
    Column({ space: 8 }) {
      Text(I18nService.t('动作'))
        .fontSize(AppTypography.CAPTION)
        .fontColor(AppColors.TEXT_SECONDARY)
      if (this.getActionOptions().length === 0) {
        Text(I18nService.t('暂无可用动作'))
          .fontSize(AppTypography.CAPTION)
          .fontColor(AppColors.TEXT_MUTED)
      } else {
        Row({ space: 8 }) {
          ForEach(this.getActionOptions(), (action: string) => {
            this.actionButton(action)
          }, (action: string) => action)
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  actionButton(action: string) {
    Button(this.viewModel.getActionLabel(action))
      .layoutWeight(1)
      .height(36)
      .backgroundColor(this.selectedAction === action ? AppColors.PRIMARY : AppColors.SURFACE_SOFT)
      .fontColor(this.selectedAction === action ? AppColors.SURFACE : AppColors.TEXT_SECONDARY)
      .borderRadius(AppMetrics.CARD_RADIUS)
      .onClick(() => {
        this.selectedAction = action;
        this.applyDefaultValueForAction();
      })
  }

  @Builder
  actionValueEditor() {
    if (this.requiresNumericValue()) {
      Column({ space: 8 }) {
        Row() {
          Text(this.selectedAction === DeviceAction.SET_BRIGHTNESS ? I18nService.t('亮度') : I18nService.t('目标温度'))
            .fontSize(13)
            .fontColor(AppColors.TEXT_SECONDARY)
          Blank()
          Text(`${this.numericValue}${this.selectedAction === DeviceAction.SET_BRIGHTNESS ? '%' : '℃'}`)
            .fontSize(13)
            .fontColor(AppColors.PRIMARY)
        }
        .width('100%')
        Slider({
          value: this.numericValue,
          min: this.selectedAction === DeviceAction.SET_BRIGHTNESS ? 0 : 16,
          max: this.selectedAction === DeviceAction.SET_BRIGHTNESS ? 100 : 30,
          step: 1
        })
          .blockColor(AppColors.PRIMARY)
          .selectedColor(AppColors.PRIMARY)
          .trackColor(AppColors.BORDER)
          .onChange((value: number) => {
            this.numericValue = value;
          })
      }
      .width('100%')
    } else if (this.selectedAction === DeviceAction.SET_MODE) {
      Column({ space: 8 }) {
        Text(I18nService.t('空调模式'))
          .fontSize(13)
          .fontColor(AppColors.TEXT_SECONDARY)
        Row({ space: 8 }) {
          this.modeButton('AUTO', I18nService.t('自动'))
          this.modeButton('COOL', I18nService.t('制冷'))
          this.modeButton('SLEEP', I18nService.t('睡眠'))
          this.modeButton('ECO', I18nService.t('节能'))
        }
        .width('100%')
      }
      .width('100%')
    } else if (this.selectedAction === DeviceAction.SET_COLOR) {
      Column({ space: 8 }) {
        Row() {
          Text(I18nService.isChinese() ? '颜色' : 'Color')
            .fontSize(13)
            .fontColor(AppColors.TEXT_SECONDARY)
          Blank()
          Text(this.colorValue).fontSize(13).fontColor(AppColors.PRIMARY)
        }
        .width('100%')
        Row({ space: 8 }) {
          this.sceneColorPreset('#FF0000')
          this.sceneColorPreset('#FFB000')
          this.sceneColorPreset('#00D060')
          this.sceneColorPreset('#00A0FF')
          this.sceneColorPreset('#6A5CFF')
          this.sceneColorPreset('#FFFFFF')
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  sceneColorPreset(color: string) {
    Button()
      .layoutWeight(1)
      .height(36)
      .backgroundColor(color)
      .borderRadius(18)
      .border({ width: this.colorValue === color ? 3 : 1,
        color: this.colorValue === color ? AppColors.TEXT_PRIMARY : AppColors.GLASS_BORDER })
      .onClick(() => this.colorValue = color)
  }

  @Builder
  modeButton(mode: string, label: string) {
    Button(label)
      .layoutWeight(1)
      .height(36)
      .backgroundColor(this.modeValue === mode ? AppColors.PRIMARY : AppColors.SURFACE_SOFT)
      .fontColor(this.modeValue === mode ? AppColors.SURFACE : AppColors.TEXT_SECONDARY)
      .borderRadius(AppMetrics.CARD_RADIUS)
      .onClick(() => {
        this.modeValue = mode;
      })
  }

  @Builder
  draftActionList() {
    Column({ space: 8 }) {
      Row() {
        Text(I18nService.t('已添加'))
          .fontSize(AppTypography.CAPTION)
          .fontColor(AppColors.TEXT_SECONDARY)
        Blank()
        Text(this.actionCountText(this.draftActions.length))
          .fontSize(AppTypography.CAPTION)
          .fontColor(AppColors.TEXT_MUTED)
      }
      .width('100%')

      if (this.draftActions.length === 0) {
        Text(I18nService.t('还没有动作。'))
          .fontSize(AppTypography.CAPTION)
          .fontColor(AppColors.TEXT_MUTED)
          .width('100%')
          .padding(12)
          .backgroundColor(AppColors.SURFACE_SOFT)
          .borderRadius(AppMetrics.CARD_RADIUS)
      } else {
        ForEach(this.draftActions, (action: SceneAction) => {
          this.draftActionRow(action)
        }, (action: SceneAction) => `${action.gatewayId === undefined ? 'legacy' : action.gatewayId}-${action.targetDevice}-${action.action}`)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  draftActionRow(action: SceneAction) {
    Row() {
      Text(this.sceneActionText(action))
        .fontSize(AppTypography.CAPTION)
        .fontColor(AppColors.TEXT_SECONDARY)
        .maxLines(2)
        .layoutWeight(1)
      Button(I18nService.t('移除'))
        .height(32)
        .padding({ left: 10, right: 10 })
        .backgroundColor(AppColors.SURFACE)
        .fontColor(AppColors.DANGER)
        .borderRadius(AppMetrics.CARD_RADIUS)
        .onClick(() => {
          this.removeDraftAction(action);
        })
    }
    .width('100%')
    .padding(10)
    .backgroundColor(AppColors.SURFACE_SOFT)
    .borderRadius(AppMetrics.CARD_RADIUS)
  }

  @Builder
  sceneList() {
    Column({ space: 14 }) {
      Row() {
        Text(I18nService.t('我的场景'))
          .fontSize(AppTypography.SECTION_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
        Blank()
        Text(this.sceneCountText(this.scenes.length))
          .fontSize(AppTypography.CAPTION)
          .fontColor(AppColors.TEXT_MUTED)
      }
      .width('100%')

      if (this.scenes.length === 0) {
        Column({ space: 8 }) {
          Text(I18nService.t('暂无可执行场景'))
            .fontSize(AppTypography.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text(I18nService.t('创建后即可一键开启。'))
            .fontSize(AppTypography.CAPTION)
            .fontColor(AppColors.TEXT_MUTED)
            .textAlign(TextAlign.Center)
          Button(I18nService.t('新建场景'))
            .height(36)
            .padding({ left: 16, right: 16 })
            .backgroundColor(AppColors.PRIMARY)
            .fontColor(AppColors.SURFACE)
            .borderRadius(AppMetrics.CARD_RADIUS)
            .onClick(() => {
              this.beginCreateScene();
            })
        }
        .width('100%')
        .padding(AppMetrics.CARD_PADDING)
        .backgroundColor(AppColors.SURFACE)
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .border({ width: 1, color: AppColors.GLASS_BORDER })
        .borderRadius(AppMetrics.CARD_RADIUS)
      } else {
        this.sceneGroup(I18nService.t('推荐'), true)
        this.sceneGroup(I18nService.t('自定义'), false)
      }
    }
    .width('100%')
  }

  @Builder
  sceneGroup(title: string, preset: boolean) {
    Column({ space: 10 }) {
      Row() {
        Text(title)
          .fontSize(AppTypography.CARD_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .layoutWeight(1)
        this.sceneCountPill(this.sceneCountText(this.countScenes(preset)), preset ? AppColors.ACCENT : AppColors.PRIMARY)
      }
      .width('100%')

      if (this.countScenes(preset) === 0) {
        Text(preset ? I18nService.t('暂无推荐场景') : I18nService.t('点击新建添加场景'))
          .fontSize(AppTypography.CAPTION)
          .fontColor(AppColors.TEXT_MUTED)
          .width('100%')
          .padding(14)
          .backgroundColor(AppColors.SURFACE_SOFT)
          .borderRadius(AppMetrics.CARD_RADIUS)
      } else {
        ForEach(this.getScenesByPreset(preset), (scene: SceneDefinition) => {
          this.sceneCard(scene)
        }, (scene: SceneDefinition) => scene.sceneId)
      }
    }
    .width('100%')
  }

  @Builder
  sceneCard(scene: SceneDefinition) {
    Column({ space: 12 }) {
      Row({ space: 14 }) {
        Column()
          .width(6)
          .height(68)
          .backgroundColor(scene.accentColor)
          .borderRadius(3)
        Column({ space: 5 }) {
          Text(scene.sceneName)
            .fontSize(AppTypography.CARD_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
            .maxLines(1)
          if (scene.description.length > 0) {
            Text(scene.description)
              .fontSize(AppTypography.BODY)
              .fontColor(AppColors.TEXT_SECONDARY)
              .maxLines(1)
          }
          Text(this.actionCountText(scene.actions.length))
            .fontSize(AppTypography.CAPTION)
            .fontColor(AppColors.TEXT_MUTED)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      Row({ space: 8 }) {
        Button(scene.actions.length === 0 ? I18nService.t('无可用设备') :
          (this.runningSceneId === scene.sceneId ? I18nService.t('执行中') : I18nService.t('执行')))
          .layoutWeight(1)
          .height(38)
          .enabled(scene.actions.length > 0 && this.runningSceneId !== scene.sceneId)
          .backgroundColor(scene.actions.length === 0 || this.runningSceneId === scene.sceneId ?
            AppColors.TEXT_MUTED : scene.accentColor)
          .fontColor(AppColors.SURFACE)
          .borderRadius(AppMetrics.CARD_RADIUS)
          .onClick(() => {
            this.handleRun(scene.sceneId);
          })
        if (scene.isPreset !== true) {
          Button(I18nService.t('编辑'))
            .width(70)
            .height(38)
            .backgroundColor(AppColors.SURFACE_SOFT)
            .fontColor(AppColors.TEXT_SECONDARY)
            .borderRadius(AppMetrics.CARD_RADIUS)
            .onClick(() => {
              this.editScene(scene);
            })
          Button(I18nService.t('删除'))
            .width(70)
            .height(38)
            .backgroundColor(AppColors.SURFACE_SOFT)
            .fontColor(AppColors.DANGER)
            .borderRadius(AppMetrics.CARD_RADIUS)
            .onClick(() => {
              this.deleteScene(scene.sceneId);
            })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppMetrics.CARD_PADDING)
    .backgroundColor(AppColors.SURFACE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .borderRadius(AppMetrics.CARD_RADIUS)
    .border({ width: 1, color: AppColors.GLASS_BORDER })
    .shadow({ radius: 12, color: AppColors.GLASS_SHADOW, offsetX: 0, offsetY: 4 })
  }

  private async reloadAsync(): Promise<void> {
    await this.viewModel.load();
    this.reload();
  }

  private reload(): void {
    this.scenes = this.viewModel.getScenes();
    this.devices = this.viewModel.getDevices();
    if (!this.hasSelectedDevice() && this.devices.length > 0) {
      this.selectDevice(this.devices[0]);
    }
  }

  private countScenes(preset: boolean): number {
    let count = 0;
    for (let index = 0; index < this.scenes.length; index++) {
      if ((this.scenes[index].isPreset === true) === preset) {
        count += 1;
      }
    }
    return count;
  }

  private getScenesByPreset(preset: boolean): SceneDefinition[] {
    const result: SceneDefinition[] = [];
    for (let index = 0; index < this.scenes.length; index++) {
      const scene = this.scenes[index];
      if ((scene.isPreset === true) === preset) {
        result.push(scene);
      }
    }
    return result;
  }

  private beginCreateScene(): void {
    this.resetDraft();
    this.editorExpanded = true;
    this.message = I18nService.t('新建场景');
  }

  private cancelEditor(): void {
    this.resetDraft();
    this.message = I18nService.t('一键开启常用场景');
  }

  private async handleRun(sceneId: string): Promise<void> {
    this.runningSceneId = sceneId;
    const result = await this.viewModel.runScene(sceneId);
    this.message = result.message;
    this.runningSceneId = '';
    this.reload();
  }

  private async saveDraftScene(): Promise<void> {
    if (this.draftName.trim().length === 0) {
      this.message = I18nService.t('请输入场景名称');
      return;
    }
    if (this.draftActions.length === 0) {
      this.message = I18nService.t('请添加一个动作');
      return;
    }
    for (let index = 0; index < this.draftActions.length; index++) {
      const action = this.draftActions[index];
      const device = this.findCurrentSceneDevice(action.targetDevice);
      const actionGatewayId = action.gatewayId === undefined ? '' : action.gatewayId;
      const deviceGatewayId = device === undefined || device.gatewayId === undefined ? '' : device.gatewayId;
      if (device === undefined || deviceGatewayId.length === 0 ||
        (actionGatewayId.length > 0 && actionGatewayId !== deviceGatewayId)) {
        this.message = I18nService.isChinese() ?
          `第 ${index + 1} 项属于旧网关，请删除该动作并从当前网关重新选择设备` :
          `Item ${index + 1} belongs to an old gateway. Remove it and select the device again from the current gateway.`;
        return;
      }
    }

    const draft: SceneDraft = {
      sceneName: this.draftName,
      description: this.draftDescription,
      accentColor: this.draftAccent,
      actions: this.copyActions(this.draftActions)
    };
    if (this.draftSceneId.length > 0) {
      draft.sceneId = this.draftSceneId;
    }
    const scene = await this.viewModel.saveScene(draft);
    this.message = I18nService.isChinese() ? `${scene.sceneName} 已保存` : `${scene.sceneName} saved`;
    this.resetDraft();
    this.reload();
  }

  private async deleteScene(sceneId: string): Promise<void> {
    const deleted = await this.viewModel.deleteScene(sceneId);
    this.message = deleted ? I18nService.t('场景已删除') : I18nService.t('删除失败');
    if (this.draftSceneId === sceneId) {
      this.resetDraft();
    }
    this.reload();
  }

  private editScene(scene: SceneDefinition): void {
    this.draftSceneId = scene.sceneId;
    this.draftName = scene.sceneName;
    this.draftDescription = scene.description;
    this.draftAccent = scene.accentColor;
    this.draftActions = this.copyActions(scene.actions);
    this.editorExpanded = true;
    this.message = I18nService.isChinese() ? `编辑 ${scene.sceneName}` : `Editing ${scene.sceneName}`;
  }

  private resetDraft(): void {
    this.draftSceneId = '';
    this.draftName = '';
    this.draftDescription = '';
    this.draftAccent = AppColors.PRIMARY;
    this.draftActions = [];
    this.editorExpanded = false;
  }

  private selectDevice(device: DeviceState): void {
    this.selectedDeviceId = device.deviceId;
    const options = this.getActionOptions();
    if (options.length > 0) {
      this.selectedAction = options[0];
      this.applyDefaultValueForAction();
    } else {
      this.selectedAction = '';
    }
  }

  private addDraftAction(): void {
    const device = this.getSelectedDevice();
    if (device === undefined) {
      this.message = I18nService.t('请选择设备');
      return;
    }
    if (this.getActionOptions().length === 0) {
      this.message = I18nService.t('暂无可用动作');
      return;
    }
    const action: SceneAction = {
      targetDevice: device.deviceId,
      gatewayId: device.gatewayId,
      action: this.selectedAction
    };
    if (this.requiresNumericValue()) {
      action.value = this.numericValue;
    } else if (this.selectedAction === DeviceAction.SET_MODE) {
      action.value = this.modeValue;
    } else if (this.selectedAction === DeviceAction.SET_COLOR) {
      action.value = this.colorValue;
    }
    const next: SceneAction[] = [];
    let replaced = false;
    for (let index = 0; index < this.draftActions.length; index++) {
      const current = this.draftActions[index];
      if (current.gatewayId === action.gatewayId && current.targetDevice === action.targetDevice &&
        current.action === action.action) {
        next.push(action);
        replaced = true;
      } else {
        next.push(current);
      }
    }
    if (!replaced) {
      next.push(action);
    }
    this.draftActions = next;
    this.message = I18nService.isChinese() ?
      (replaced ? `已更新 ${device.deviceName}` : `已添加 ${device.deviceName}`) :
      (replaced ? `Updated ${device.deviceName}` : `Added ${device.deviceName}`);
  }

  private removeDraftAction(target: SceneAction): void {
    const next: SceneAction[] = [];
    let removed = false;
    for (let index = 0; index < this.draftActions.length; index++) {
      const action = this.draftActions[index];
      const same = action.gatewayId === target.gatewayId && action.targetDevice === target.targetDevice &&
        action.action === target.action &&
        this.valueText(action.value) === this.valueText(target.value);
      if (!removed && same) {
        removed = true;
      } else {
        next.push(action);
      }
    }
    this.draftActions = next;
  }

  private getActionOptions(): string[] {
    const device = this.getSelectedDevice();
    if (device === undefined) {
      return [];
    }
    if (device.deviceType === DeviceType.DOOR) {
      return [DeviceAction.OPEN, DeviceAction.CLOSE];
    }
    if (device.deviceType === DeviceType.LIGHT) {
      const options = [DeviceAction.TURN_ON, DeviceAction.TURN_OFF, DeviceAction.SET_BRIGHTNESS];
      if (device.color !== undefined) options.push(DeviceAction.SET_COLOR);
      return options;
    }
    if (device.deviceType === DeviceType.AC) {
      return [DeviceAction.TURN_ON, DeviceAction.TURN_OFF, DeviceAction.SET_TARGET_TEMPERATURE, DeviceAction.SET_MODE];
    }
    if (device.deviceType === DeviceType.SENSOR) {
      return [];
    }
    return [DeviceAction.TURN_ON, DeviceAction.TURN_OFF];
  }

  private getSelectedDevice(): DeviceState | undefined {
    for (let index = 0; index < this.devices.length; index++) {
      if (this.devices[index].deviceId === this.selectedDeviceId) {
        return this.devices[index];
      }
    }
    return undefined;
  }

  private hasSelectedDevice(): boolean {
    return this.getSelectedDevice() !== undefined;
  }

  private requiresNumericValue(): boolean {
    return this.selectedAction === DeviceAction.SET_BRIGHTNESS || this.selectedAction === DeviceAction.SET_TARGET_TEMPERATURE;
  }

  private applyDefaultValueForAction(): void {
    if (this.selectedAction === DeviceAction.SET_BRIGHTNESS) {
      this.numericValue = 50;
    } else if (this.selectedAction === DeviceAction.SET_TARGET_TEMPERATURE) {
      this.numericValue = 24;
    } else if (this.selectedAction === DeviceAction.SET_MODE) {
      this.modeValue = 'AUTO';
    } else if (this.selectedAction === DeviceAction.SET_COLOR) {
      this.colorValue = '#FFFFFF';
    }
  }

  private sceneSummary(scene: SceneDefinition): string {
    if (scene.actions.length === 0) {
      return I18nService.t('当前没有设备状态；执行时不会下发命令。');
    }
    const lines: string[] = [];
    for (let index = 0; index < scene.actions.length; index++) {
      lines.push(this.sceneActionText(scene.actions[index]));
    }
    return lines.join('；');
  }

  private actionCountText(count: number): string {
    return I18nService.isChinese() ? `${count} 个动作` : `${count} actions`;
  }

  private sceneCountText(count: number): string {
    return I18nService.isChinese() ? `${count} 个场景` : `${count} scenes`;
  }

  private sceneActionText(action: SceneAction): string {
    const device = this.findCurrentSceneDevice(action.targetDevice);
    const actionGatewayId = action.gatewayId === undefined ? '' : action.gatewayId;
    const deviceGatewayId = device === undefined || device.gatewayId === undefined ? '' : device.gatewayId;
    let notice = '';
    if (actionGatewayId.length === 0) {
      notice = I18nService.t('（旧场景，需编辑后重新保存）');
    } else if (device === undefined || deviceGatewayId !== actionGatewayId) {
      notice = I18nService.t('（网关已变更，需重新选择）');
    }
    return `${this.deviceName(action.targetDevice)}${notice}：${this.viewModel.getActionLabel(action.action)}${this.valueTextWithPrefix(action.value)}`;
  }

  private findCurrentSceneDevice(deviceId: string): DeviceState | undefined {
    for (let index = 0; index < this.devices.length; index++) {
      if (this.devices[index].deviceId === deviceId) {
        return this.devices[index];
      }
    }
    return undefined;
  }

  private valueTextWithPrefix(value?: CommandValue): string {
    const text = this.valueText(value);
    return text.length === 0 ? '' : ` ${text}`;
  }

  private valueText(value?: CommandValue): string {
    if (value === undefined) {
      return '';
    }
    return `${value}`;
  }

  private deviceName(deviceId: string): string {
    for (let index = 0; index < this.devices.length; index++) {
      if (this.devices[index].deviceId === deviceId) {
        return this.devices[index].deviceName;
      }
    }
    return I18nService.t('已删除设备');
  }

  private copyActions(actions: SceneAction[]): SceneAction[] {
    const result: SceneAction[] = [];
    for (let index = 0; index < actions.length; index++) {
      const action = actions[index];
      result.push({
        targetDevice: action.targetDevice,
        gatewayId: action.gatewayId,
        action: action.action,
        value: action.value,
        delayMs: action.delayMs
      });
    }
    return result;
  }
}
