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
import { SceneDefinition } from '../model/SceneModel';

@Component
export struct SceneCard {
  scene: SceneDefinition = {
    sceneId: '',
    sceneName: I18nService.t('场景'),
    description: '',
    accentColor: AppColors.PRIMARY,
    actions: []
  };
  running: boolean = false;
  onRun: () => void = () => {};

  build() {
    Row({ space: 14 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.bolt'))
          .fontSize(24)
          .fontColor([this.scene.accentColor])
      }
      .width(48)
      .height(48)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(AppColors.SURFACE_SOFT)
      .borderRadius(AppMetrics.INNER_RADIUS)

      Column({ space: 5 }) {
        Text(this.scene.sceneName)
          .fontSize(AppTypography.CARD_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
        Text(this.scene.description)
          .fontSize(AppTypography.CAPTION)
          .fontColor(AppColors.TEXT_SECONDARY)
          .maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button(this.running ? I18nService.t('执行中') : I18nService.t('执行'))
        .height(38)
        .padding({ left: 17, right: 17 })
        .enabled(!this.running)
        .backgroundColor(this.running ? AppColors.TEXT_MUTED : this.scene.accentColor)
        .fontColor(AppColors.WHITE)
        .borderRadius(AppMetrics.PILL_RADIUS)
        .onClick(() => {
          this.onRun();
        })
    }
    .width('100%')
    .padding(AppMetrics.CARD_PADDING)
    .backgroundColor(AppColors.SURFACE)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .border({ width: 1, color: AppColors.GLASS_BORDER })
    .borderRadius(AppMetrics.CARD_RADIUS)
    .shadow({ radius: 12, color: AppColors.GLASS_SHADOW, offsetX: 0, offsetY: 4 })
  }
}
