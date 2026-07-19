/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { AppColors, AppMetrics, AppTypography } from '../common/constants/AppTheme';
import { I18nService } from '../service/I18nService';

@Component
export struct OnboardingPage {
  onStart: () => void = () => {};
  @Prop languageRevision: number = 0;
  @Link currentPage: number;
  @State private isStarting: boolean = false;

  build() {
    Column() {
      Row() {
        Text(I18nService.isChinese() ? '爻构' : 'YaoCore')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
        Blank()
        if (this.currentPage < 3) {
          Button(I18nService.t('跳过'))
            .height(36)
            .backgroundColor(Color.Transparent)
            .fontColor(AppColors.TEXT_SECONDARY)
            .onClick(() => {
              this.currentPage = 3;
            })
        }
      }
      .width('100%')
      .height(58)

      Swiper() {
        this.guidePage(
          $r('sys.symbol.house_fill'),
          I18nService.t('欢迎使用爻构'),
          '爻联万物，构筑智慧。',
          'Connecting Things, Building Intelligence.',
          I18nService.t('本地控制、自动化与远程连接'),
          AppColors.PRIMARY,
          AppColors.PRIMARY_SOFT
        )
        this.guidePage(
          $r('sys.symbol.key_horizontal'),
          I18nService.t('准备网关'),
          I18nService.t('保存控制密钥'),
          I18nService.t('打开设备页，先保存网关固件对应的控制密钥。'),
          I18nService.t('控制密钥用于配网后的网关认证'),
          AppColors.ACCENT,
          AppColors.ACCENT_SOFT
        )
        this.guidePage(
          $r('sys.symbol.wifi'),
          I18nService.t('连接家庭网络'),
          I18nService.t('输入 PoP 完成 BLE 配网'),
          I18nService.t('搜索网关，选择 2.4 GHz Wi-Fi，并输入开发板屏幕上的 PoP。'),
          I18nService.t('成功后自动认证并绑定，无需再次查找'),
          AppColors.SUCCESS,
          AppColors.SUCCESS_SOFT
        )
        this.guidePage(
          $r('sys.symbol.bolt'),
          I18nService.t('设备与自动化'),
          I18nService.t('添加设备并同步真实状态'),
          I18nService.t('扫描设备并创建本地自动化；配置云端后可在家庭网络外控制。'),
          I18nService.t('传感器触发后，设备最终状态会同步到手机'),
          AppColors.PRIMARY_DARK,
          AppColors.PRIMARY_SOFT
        )
      }
      .index(this.currentPage)
      .indicator(false)
      .loop(false)
      .layoutWeight(1)
      .width('100%')
      .onChange((index: number) => {
        this.currentPage = index;
      })

      Row({ space: 7 }) {
        ForEach([0, 1, 2, 3], (item: number) => {
          Column()
            .width(this.currentPage === item ? 24 : 7)
            .height(7)
            .backgroundColor(this.currentPage === item ? AppColors.PRIMARY : AppColors.BORDER)
            .borderRadius(4)
        })
      }
      .height(28)
      .justifyContent(FlexAlign.Center)

      Row({ space: 12 }) {
        if (this.currentPage > 0) {
          Button(I18nService.t('上一步'))
            .layoutWeight(1)
            .height(50)
            .backgroundColor(AppColors.SURFACE_SOFT)
            .fontColor(AppColors.TEXT_SECONDARY)
            .borderRadius(AppMetrics.PILL_RADIUS)
            .onClick(() => {
              this.currentPage -= 1;
            })
        }
        Button(this.currentPage === 3 ?
          (this.isStarting ? I18nService.t('正在进入…') : I18nService.t('开始使用')) : I18nService.t('下一步'))
          .layoutWeight(1)
          .height(50)
          .backgroundColor(AppColors.PRIMARY)
          .fontColor(AppColors.WHITE)
          .borderRadius(AppMetrics.PILL_RADIUS)
          .enabled(!this.isStarting)
          .onClick(() => {
            if (this.currentPage < 3) {
              this.currentPage += 1;
              return;
            }
            if (!this.isStarting) {
              this.isStarting = true;
              this.onStart();
            }
          })
      }
      .width('100%')
      .padding({ bottom: 18 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppMetrics.PAGE_PADDING, right: AppMetrics.PAGE_PADDING })
    .linearGradient({
      angle: 145,
      colors: [[AppColors.BACKGROUND, 0.0], [AppColors.BACKGROUND_END, 1.0]]
    })
  }

  @Builder
  guidePage(
    icon: Resource,
    title: string,
    headline: string,
    description: string,
    hint: string,
    accent: string,
    softColor: string
  ) {
    Column({ space: 20 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(176)
          .height(176)
          .backgroundColor(softColor)
          .borderRadius(88)
        Column()
          .width(116)
          .height(116)
          .backgroundColor(AppColors.GLASS_STRONG)
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .border({ width: 1, color: AppColors.GLASS_BORDER })
          .borderRadius(58)
          .shadow({ radius: 18, color: AppColors.GLASS_SHADOW, offsetX: 0, offsetY: 8 })
        SymbolGlyph(icon)
          .fontSize(55)
          .fontColor([accent])
      }
      .width(190)
      .height(190)

      Text(title)
        .fontSize(AppTypography.PAGE_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_PRIMARY)
        .textAlign(TextAlign.Center)

      Text(headline)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(accent)
        .textAlign(TextAlign.Center)

      Text(description)
        .fontSize(AppTypography.BODY)
        .fontColor(AppColors.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .lineHeight(24)
        .maxLines(4)

      Text(hint)
        .fontSize(AppTypography.CAPTION)
        .fontColor(AppColors.TEXT_MUTED)
        .textAlign(TextAlign.Center)
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .backgroundColor(AppColors.GLASS)
        .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
        .border({ width: 1, color: AppColors.GLASS_BORDER })
        .borderRadius(AppMetrics.PILL_RADIUS)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 8, right: 8, bottom: 20 })
  }
}
