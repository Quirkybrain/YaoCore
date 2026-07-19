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
import { createDefaultGatewayState, GatewayState } from '../model/GatewayModel';

interface StatusOverview {
  onlineCount: number;
  totalCount: number;
  comfortLabel: string;
  securityLabel: string;
}

@Component
export struct StatusBanner {
  @Prop gateway: GatewayState = createDefaultGatewayState();
  @Prop overview: StatusOverview = {
    onlineCount: 0,
    totalCount: 0,
    comfortLabel: I18nService.t('未添加设备'),
    securityLabel: I18nService.t('未添加设备')
  };
  onRefresh: () => void = () => {};
  @Prop refreshing: boolean = false;

  build() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.house_fill'))
            .fontSize(24)
            .fontColor([AppColors.WHITE])
        }
        .width(46)
        .height(46)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(AppColors.PRIMARY)
        .borderRadius(AppMetrics.INNER_RADIUS)

        Column({ space: 3 }) {
          Text(I18nService.t('欢迎回家'))
            .fontSize(AppTypography.PAGE_TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text('YaoCore')
            .fontSize(AppTypography.CAPTION)
            .fontColor(AppColors.TEXT_SECONDARY)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button() {
          Row({ space: 7 }) {
            if (this.refreshing) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color(AppColors.PRIMARY_DARK)
            } else {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(17)
                .fontColor([AppColors.PRIMARY_DARK])
            }
            Text(this.refreshing ? I18nService.t('正在刷新…') : I18nService.t('刷新'))
              .fontSize(14)
              .fontColor(AppColors.PRIMARY_DARK)
          }
          .justifyContent(FlexAlign.Center)
        }
          .height(38)
          .padding({ left: 15, right: 15 })
          .backgroundColor('#BFFFFFFF')
          .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
          .border({ width: 1, color: '#8FFFFFFF' })
          .borderRadius(AppMetrics.PILL_RADIUS)
          .enabled(!this.refreshing)
          .onClick(() => {
            this.onRefresh();
          })
      }
      .width('100%')

      Row({ space: 10 }) {
        this.bannerMetric(`${this.overview.onlineCount}/${this.overview.totalCount}`, I18nService.t('在线设备'))
        this.bannerMetric(this.channelText(), I18nService.t('连接方式'))
        this.bannerMetric(`${this.gateway.latencyMs}ms`, I18nService.t('响应'))
      }
      .width('100%')

    }
    .width('100%')
    .padding(AppMetrics.CARD_PADDING)
    .linearGradient({
      angle: 135,
      colors: [[AppColors.PRIMARY_SOFT, 0.0], [AppColors.BACKGROUND_WARM, 1.0]]
    })
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .border({ width: 1, color: '#AFFFFFFF' })
    .borderRadius(AppMetrics.CARD_RADIUS)
    .shadow({ radius: 14, color: AppColors.SHADOW, offsetX: 0, offsetY: 5 })
  }

  @Builder
  bannerMetric(value: string, label: string) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.PRIMARY_DARK)
        .maxLines(1)
      Text(label)
        .fontSize(AppTypography.CAPTION)
        .fontColor(AppColors.TEXT_MUTED)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor('#BFFFFFFF')
    .borderRadius(AppMetrics.INNER_RADIUS)
  }

  private channelText(): string {
    if (this.gateway.localAvailable) {
      return I18nService.t('局域网');
    }
    if (this.gateway.cloudAvailable) {
      return I18nService.t('云端');
    }
    return I18nService.t('离线');
  }
}
