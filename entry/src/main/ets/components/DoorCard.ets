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
export struct DoorCard {
  @Prop device: DeviceState = createDevicePlaceholder('', I18nService.t('门禁'), DeviceType.DOOR);
  onToggle: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        Row() {
          SymbolGlyph(this.device.isOnline && this.device.openStatus === true ?
            $r('sys.symbol.lock_open') : $r('sys.symbol.lock_fill'))
            .fontSize(24)
            .fontColor([this.doorStateColor()])
        }
        .width(48)
        .height(48)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.device.isOnline && this.device.openStatus !== undefined ?
          (this.device.openStatus ? AppColors.WARNING_SOFT : AppColors.SUCCESS_SOFT) : AppColors.SURFACE_SOFT)
        .borderRadius(AppMetrics.INNER_RADIUS)

        Column({ space: 4 }) {
          Text(this.device.deviceName)
            .fontSize(AppTypography.CARD_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text(this.device.roomName)
            .fontSize(AppTypography.CAPTION)
            .fontColor(AppColors.TEXT_MUTED)
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(this.doorStateLabel())
          .fontSize(AppTypography.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.doorStateColor())
          .padding({ left: 11, right: 11, top: 6, bottom: 6 })
          .backgroundColor(this.device.isOnline && this.device.openStatus !== undefined ?
            (this.device.openStatus ? AppColors.WARNING_SOFT : AppColors.SUCCESS_SOFT) : AppColors.SURFACE_SOFT)
          .borderRadius(AppMetrics.PILL_RADIUS)
      }
      .width('100%')

      Button(!this.device.isOnline ? I18nService.t('设备离线') :
        (this.device.openStatus === undefined ? I18nService.t('状态未知') : (this.device.openStatus ? I18nService.t('上锁') : I18nService.t('开门'))))
      .width('100%')
        .height(AppMetrics.CONTROL_HEIGHT)
        .enabled(this.device.isOnline && this.device.openStatus !== undefined)
        .backgroundColor(this.device.isOnline && this.device.openStatus !== undefined ?
          (this.device.openStatus ? AppColors.WARNING : AppColors.PRIMARY) : AppColors.TEXT_MUTED)
        .fontColor(AppColors.WHITE)
        .borderRadius(AppMetrics.PILL_RADIUS)
        .onClick(() => {
          this.onToggle();
        })
    }
    .width('100%')
    .padding(AppMetrics.CARD_PADDING)
    .backgroundColor('#EFFFFFFF')
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .border({ width: 1, color: '#AFFFFFFF' })
    .borderRadius(AppMetrics.CARD_RADIUS)
    .shadow({ radius: 11, color: AppColors.SHADOW, offsetX: 0, offsetY: 4 })
  }

  private doorStateLabel(): string {
    if (!this.device.isOnline) return I18nService.t('离线 · 状态未知');
    if (this.device.openStatus === undefined) return I18nService.t('状态未知');
    return this.device.openStatus ? I18nService.t('已开启') : I18nService.t('已上锁');
  }

  private doorStateColor(): string {
    if (!this.device.isOnline || this.device.openStatus === undefined) return AppColors.TEXT_MUTED;
    return this.device.openStatus ? AppColors.WARNING : AppColors.SUCCESS;
  }
}
