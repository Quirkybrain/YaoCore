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
import { createDevicePlaceholder, DeviceState, DeviceType } from '../model/DeviceModel';

@Component
export struct LightCard {
  @Prop device: DeviceState = createDevicePlaceholder('', I18nService.t('灯光'), DeviceType.LIGHT);
  onToggle: () => void = () => {};
  onBrightnessChange: (value: number, finalValue: boolean) => void =
    (value: number, finalValue: boolean) => {};

  build() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        Row() {
          SymbolGlyph(this.device.powerStatus === true ? $r('sys.symbol.lightbulb') : $r('sys.symbol.lightbulb_slash'))
            .fontSize(25)
            .fontColor([this.device.powerStatus === true ? AppColors.ACCENT : AppColors.TEXT_MUTED])
        }
        .width(48)
        .height(48)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.device.powerStatus === true ? AppColors.ACCENT_SOFT : AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.INNER_RADIUS)

        Column({ space: 4 }) {
          Text(this.device.deviceName)
            .fontSize(AppTypography.CARD_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text(`${this.device.roomName} · ${!this.device.isOnline ? I18nService.t('离线，状态未知') :
            (this.device.powerStatus === undefined ? I18nService.t('状态未知') : (this.device.powerStatus ? I18nService.t('已开启') : I18nService.t('已关闭')))}`)
            .fontSize(AppTypography.CAPTION)
            .fontColor(AppColors.TEXT_MUTED)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button(!this.device.isOnline ? I18nService.t('设备离线') :
          (this.device.powerStatus === undefined ? I18nService.t('状态未知') : (this.device.powerStatus ? I18nService.t('关闭') : I18nService.t('开启'))))
          .height(AppMetrics.CONTROL_HEIGHT)
          .padding({ left: 18, right: 18 })
          .enabled(this.device.isOnline && this.device.powerStatus !== undefined)
          .backgroundColor(this.device.isOnline && this.device.powerStatus !== undefined ?
            (this.device.powerStatus ? AppColors.ACCENT : AppColors.PRIMARY) : AppColors.TEXT_MUTED)
          .fontColor(AppColors.WHITE)
          .borderRadius(AppMetrics.PILL_RADIUS)
          .onClick(() => {
            this.onToggle();
          })
      }
      .width('100%')

      Column({ space: 9 }) {
        Row() {
          Text(I18nService.t('亮度'))
            .fontSize(AppTypography.BODY)
            .fontColor(AppColors.TEXT_SECONDARY)
          Blank()
          Text(this.device.brightness === undefined ? '--' : `${this.device.brightness}%`)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.device.powerStatus === true ? AppColors.ACCENT : AppColors.TEXT_MUTED)
        }
        .width('100%')

        Slider({
          value: this.device.brightness === undefined ? 0 : this.device.brightness,
          min: 0,
          max: 100,
          step: 1
        })
          .blockColor(this.device.powerStatus === true ? AppColors.ACCENT : AppColors.PRIMARY)
          .selectedColor(this.device.powerStatus === true ? AppColors.ACCENT : AppColors.PRIMARY)
          .trackColor(AppColors.BORDER)
          .enabled(this.device.isOnline && this.device.brightness !== undefined)
          .onChange((value: number, mode: SliderChangeMode) => {
            const finalValue = mode === SliderChangeMode.End || mode === SliderChangeMode.Click;
            this.onBrightnessChange(value, finalValue);
          })
      }
      .width('100%')
      .padding(14)
      .backgroundColor(this.device.powerStatus === true ? AppColors.ACCENT_SOFT : AppColors.SURFACE_SOFT)
      .borderRadius(AppMetrics.INNER_RADIUS)
    }
    .width('100%')
    .padding(AppMetrics.CARD_PADDING)
    .backgroundColor('#EFFFFFFF')
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .border({ width: 1, color: '#AFFFFFFF' })
    .borderRadius(AppMetrics.CARD_RADIUS)
    .shadow({ radius: 11, color: AppColors.SHADOW, offsetX: 0, offsetY: 4 })
  }
}
