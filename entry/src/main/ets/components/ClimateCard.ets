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
export struct ClimateCard {
  @Prop sensor: DeviceState = createDevicePlaceholder('', I18nService.t('温湿度'), DeviceType.SENSOR);
  @Prop ac: DeviceState = createDevicePlaceholder('', I18nService.t('空调'), DeviceType.AC);
  onAcToggle: () => void = () => {};
  onTemperatureChange: (value: number) => void = (value: number) => {};
  onModeChange: (mode: string) => void = (mode: string) => {};

  build() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.sun_max'))
            .fontSize(25)
            .fontColor([this.ac.powerStatus === true ? AppColors.ACCENT : AppColors.PRIMARY])
        }
        .width(48)
        .height(48)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.ac.powerStatus === true ? AppColors.ACCENT_SOFT : AppColors.PRIMARY_SOFT)
        .borderRadius(AppMetrics.INNER_RADIUS)

        Column({ space: 4 }) {
          Text(this.ac.deviceName)
            .fontSize(AppTypography.CARD_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text(`${this.sensor.deviceName} · ${this.sensor.roomName} · ${!this.ac.isOnline ? I18nService.t('空调离线，状态未知') :
            (this.ac.powerStatus === undefined ? I18nService.t('空调状态未知') : (this.ac.powerStatus ? this.ac.mode : I18nService.t('空调已关闭')))}`)
            .fontSize(AppTypography.CAPTION)
            .fontColor(AppColors.TEXT_MUTED)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button(!this.ac.isOnline ? I18nService.t('设备离线') :
          (this.ac.powerStatus === undefined ? I18nService.t('状态未知') : (this.ac.powerStatus ? I18nService.t('关闭') : I18nService.t('开启'))))
          .height(AppMetrics.CONTROL_HEIGHT)
          .padding({ left: 18, right: 18 })
          .enabled(this.ac.isOnline && this.ac.powerStatus !== undefined)
          .backgroundColor(this.ac.isOnline && this.ac.powerStatus !== undefined ?
            (this.ac.powerStatus ? AppColors.ACCENT : AppColors.PRIMARY) : AppColors.TEXT_MUTED)
          .fontColor(AppColors.WHITE)
          .borderRadius(AppMetrics.PILL_RADIUS)
          .onClick(() => {
            this.onAcToggle();
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        this.metric(this.sensor.temperature === undefined ? '--' : `${this.sensor.temperature}℃`, I18nService.t('室温'), AppColors.PRIMARY)
        this.metric(this.sensor.humidity === undefined ? '--' : `${this.sensor.humidity}%`, I18nService.t('湿度'), AppColors.SUCCESS)
        this.metric(this.ac.targetTemperature === undefined ? '--' : `${this.ac.targetTemperature}℃`, I18nService.t('目标'), AppColors.ACCENT)
      }
      .width('100%')

      Column({ space: 8 }) {
        Row() {
          Text(I18nService.t('目标温度'))
            .fontSize(AppTypography.BODY)
            .fontColor(AppColors.TEXT_SECONDARY)
          Blank()
          Text(this.ac.targetTemperature === undefined ? '--' : `${this.ac.targetTemperature}℃`)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.ACCENT)
        }
        .width('100%')
        Slider({
          value: this.ac.targetTemperature === undefined ? 24 : this.ac.targetTemperature,
          min: 16,
          max: 30,
          step: 0.5
        })
          .blockColor(AppColors.ACCENT)
          .selectedColor(AppColors.ACCENT)
          .trackColor(AppColors.BORDER)
          .enabled(this.ac.isOnline && this.ac.targetTemperature !== undefined)
          .onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.onTemperatureChange(value);
            }
          })
      }
      .width('100%')
      .padding(14)
      .backgroundColor(AppColors.ACCENT_SOFT)
      .borderRadius(AppMetrics.INNER_RADIUS)

      Row({ space: 8 }) {
        this.modeButton('COOL', I18nService.t('制冷'))
        this.modeButton('SLEEP', I18nService.t('睡眠'))
        this.modeButton('ECO', I18nService.t('节能'))
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppMetrics.CARD_PADDING)
    .backgroundColor('#EFFFFFFF')
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .border({ width: 1, color: '#AFFFFFFF' })
    .borderRadius(AppMetrics.CARD_RADIUS)
    .shadow({ radius: 11, color: AppColors.SHADOW, offsetX: 0, offsetY: 4 })
  }

  @Builder
  metric(value: string, label: string, accent: string) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(accent)
        .maxLines(1)
      Text(label)
        .fontSize(AppTypography.CAPTION)
        .fontColor(AppColors.TEXT_MUTED)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor(AppColors.SURFACE_SOFT)
    .borderRadius(AppMetrics.INNER_RADIUS)
  }

  @Builder
  modeButton(wireMode: string, label: string) {
    Button(label)
      .layoutWeight(1)
      .height(38)
      .backgroundColor(this.ac.mode === label ? AppColors.PRIMARY : AppColors.SURFACE_SOFT)
      .fontColor(this.ac.mode === label ? AppColors.WHITE : AppColors.TEXT_SECONDARY)
      .borderRadius(AppMetrics.PILL_RADIUS)
      .enabled(this.ac.isOnline && this.ac.powerStatus !== undefined)
      .onClick(() => {
        this.onModeChange(wireMode);
      })
  }
}
