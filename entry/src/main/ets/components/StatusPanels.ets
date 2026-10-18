/*
 * YaoCore C-24 status banner and environment panel.
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §13.1.3, §14.1.2; FR-HOME-001..004
 */
import type { I18nService } from '../service/i18n/I18nService';
import { NameValue } from '../common/types/NameValue';
import {
  CloudLinkState,
  EnvironmentSummary,
  GatewayLinkState,
  GatewayStatus
} from '../viewmodel/core/ViewModelCore';
import { I18nKeys } from '../service/i18n/I18nKeys';
import { I18nParams, I18nKey } from '../model/I18nModels';
import {
  AppColors,
  AppRadius,
  AppSpacing,
  AppTypography
} from '../common/theme/AppTheme';

@Component
export struct StatusBanner {
  @Require i18n: I18nService;
  @Prop localeRevision: number = 0;
  @Prop familyName: string = '';
  @Prop gateway: GatewayStatus | undefined = undefined;
  @Prop cloud: CloudLinkState = CloudLinkState.UNKNOWN;
  @Prop showGateway: boolean = true;
  @Prop isRefreshing: boolean = false;
  onFamilyClick: () => void = (): void => {};
  onGatewayClick: () => void = (): void => {};
  onRefresh: () => void = (): void => {};

  private lanKey(): string {
    if (this.gateway === undefined) {
      return 'home.gateway.none';
    }
    if (this.gateway.lan === GatewayLinkState.ONLINE) {
      return 'home.gateway.online';
    }
    if (this.gateway.lan === GatewayLinkState.BLOCKED) {
      return 'gateway.security.unavailable';
    }
    return 'home.gateway.offline';
  }

  private lanColor(): ResourceColor {
    if (this.gateway !== undefined && this.gateway.lan === GatewayLinkState.ONLINE) {
      return AppColors.green();
    }
    return AppColors.amber();
  }

  private cloudKey(): string {
    if (this.cloud === CloudLinkState.CONFIGURED) {
      return 'home.cloud.configured';
    }
    if (this.cloud === CloudLinkState.TOKEN_EXPIRED) {
      return 'cloud.token.expired';
    }
    if (this.cloud === CloudLinkState.TOKEN_INVALID) {
      return 'cloud.token.invalid';
    }
    if (this.cloud === CloudLinkState.UNAVAILABLE) {
      return 'cloud.state.unavailable';
    }
    return 'home.cloud.not_configured';
  }

  build() {
    Column({ space: AppSpacing.xs }) {
      Row({ space: AppSpacing.xs }) {
        Button(this.familyName.length > 0 ? this.familyName : this.i18n.t('family.none'))
          .fontSize(AppTypography.title)
          .fontWeight(AppTypography.weightBold)
          .fontColor(AppColors.ink())
          .backgroundColor(Color.Transparent)
          .padding(0)
          .constraintSize({ minHeight: 44 })
          .accessibilityText(this.i18n.t('family.switch'))
          .onClick((): void => {
            this.onFamilyClick();
          })
        Text('▾')
          .fontSize(AppTypography.label)
          .fontColor(AppColors.muted())
        Blank()
        Button(this.i18n.t(this.isRefreshing ? 'common.loading' : 'common.refresh'))
          .fontSize(AppTypography.label)
          .fontColor(AppColors.primary())
          .backgroundColor(Color.Transparent)
          .constraintSize({ minHeight: 44 })
          .enabled(!this.isRefreshing)
          .accessibilityText(this.i18n.t('common.refresh'))
          .onClick((): void => {
            this.onRefresh();
          })
      }
      .width('100%')

      if (this.showGateway) {
        Row({ space: AppSpacing.xs }) {
          Row({ space: AppSpacing.xxs }) {
            Ellipse()
              .width(8)
              .height(8)
              .fill(this.lanColor())
            Text(this.i18n.t(this.lanKey()))
              .fontSize(AppTypography.label)
              .fontColor(AppColors.inkSoft())
            if (this.gateway !== undefined && this.gateway.latencyMs !== undefined) {
              Text(this.i18n.t('home.metric.rtt_ms',
                new I18nParams([new NameValue('value', String(this.gateway.latencyMs))])))
                .fontSize(AppTypography.caption)
                .fontColor(AppColors.muted())
            }
          }
          .height(44)
          .onClick((): void => {
            this.onGatewayClick();
          })
          Text('·')
            .fontSize(AppTypography.caption)
            .fontColor(AppColors.mutedLight())
          Text(this.i18n.t(this.cloudKey()))
            .fontSize(AppTypography.label)
            .fontColor(AppColors.muted())
          Blank()
          if (this.gateway !== undefined && this.gateway.gatewayName.length > 0) {
            Text(this.gateway.gatewayName)
              .fontSize(AppTypography.caption)
              .fontColor(AppColors.muted())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .padding({ top: AppSpacing.xs, bottom: AppSpacing.xs })
        if (this.gateway !== undefined && this.gateway.warningKey !== undefined) {
          Text(this.i18n.t(this.gateway.warningKey))
            .fontSize(AppTypography.caption)
            .fontColor(AppColors.amber())
        }
      }
    }
    .width('100%')
    .padding(AppSpacing.md)
    .backgroundColor(AppColors.surface())
    .borderRadius(AppRadius.card)
    .border({ width: 1, color: AppColors.edge() })
  }
}

@Component
export struct EnvironmentPanel {
  @Require i18n: I18nService;
  @Prop localeRevision: number = 0;
  @Prop environment: EnvironmentSummary = EnvironmentSummary.empty();

  private sourceKey(): string {
    const key: I18nKey = this.environment.stateSource === undefined
      ? new I18nKey('stateSource.unknown') :
      I18nKeys.stateSource(this.environment.stateSource, true);
    return this.i18n.t(key.key, I18nParams.of(key.params));
  }

  build() {
    Column({ space: AppSpacing.xs }) {
      Row() {
        Text(this.i18n.t('home.environment.title'))
          .fontSize(AppTypography.section)
          .fontWeight(AppTypography.weightMedium)
          .fontColor(AppColors.ink())
        Blank()
        if (this.environment.updatedAt !== undefined) {
          Text(this.environment.updatedAt)
            .fontSize(AppTypography.caption)
            .fontColor(AppColors.muted())
        }
      }
      .width('100%')
      if (!this.environment.known) {
        Text(this.i18n.t('home.environment.empty'))
          .fontSize(AppTypography.body)
          .fontColor(AppColors.muted())
      } else {
        Row({ space: AppSpacing.lg }) {
          if (this.environment.temperature !== undefined) {
            Column({ space: AppSpacing.xxs }) {
              Text(this.environment.temperature.toFixed(1) + ' °C')
                .fontSize(AppTypography.display)
                .fontColor(AppColors.ink())
              Text(this.i18n.t('home.environment.temperature'))
                .fontSize(AppTypography.caption)
                .fontColor(AppColors.muted())
            }
            .alignItems(HorizontalAlign.Start)
          }
          if (this.environment.humidity !== undefined) {
            Column({ space: AppSpacing.xxs }) {
              Text(this.environment.humidity.toFixed(0) + ' %')
                .fontSize(AppTypography.title)
                .fontColor(AppColors.inkSoft())
              Text(this.i18n.t('home.environment.humidity'))
                .fontSize(AppTypography.caption)
                .fontColor(AppColors.muted())
            }
            .alignItems(HorizontalAlign.Start)
          }
          if (this.environment.presence !== undefined) {
            Column({ space: AppSpacing.xxs }) {
              Text(this.i18n.t(this.environment.presence
                ? 'home.environment.presence_detected' : 'home.environment.presence_clear'))
                .fontSize(AppTypography.section)
                .fontColor(AppColors.inkSoft())
              Text(this.i18n.t('home.environment.presence'))
                .fontSize(AppTypography.caption)
                .fontColor(AppColors.muted())
            }
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        Text(this.i18n.t('home.environment.source') + ' ' + this.sourceKey())
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.muted())
      }
    }
    .width('100%')
    .padding(AppSpacing.md)
    .backgroundColor(AppColors.surface())
    .borderRadius(AppRadius.card)
    .border({ width: 1, color: AppColors.edge() })
    .alignItems(HorizontalAlign.Start)
  }
}
