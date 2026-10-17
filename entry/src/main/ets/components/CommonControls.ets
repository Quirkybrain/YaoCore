/*
 * YaoCore C-24 shared UI controls.
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §13.1.3; UIUX §2/§4; I18N-07/08
 *
 * Explicit @Require i18n + @Prop localeRevision props only. No @Provide /
 * @Consume, no service/repository/VM import.
 */
import type { I18nService } from '../service/i18n/I18nService';
import { UiAction } from '../common/theme/AppEnums';
import {
  AppColors,
  AppRadius,
  AppSpacing,
  AppTypography
} from '../common/theme/AppTheme';

@Component
export struct GlassSurface {
  @Prop blurRadius: number = 35;
  @Prop surface: ResourceColor = AppColors.surface();
  @Prop radius: number = AppRadius.card;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .backgroundColor(this.surface)
    .borderRadius(this.radius)
    .border({ width: 1, color: AppColors.edge() })
    .backdropBlur(this.blurRadius)
  }
}

@Component
export struct SectionHeader {
  @Require i18n: I18nService;
  @Prop localeRevision: number = 0;
  @Prop titleKey: string = '';
  @Prop action: UiAction | undefined = undefined;
  onAction: (id: string) => void = (id: string): void => {};

  build() {
    Row() {
      Text(this.i18n.t(this.titleKey))
        .fontSize(AppTypography.section)
        .fontWeight(AppTypography.weightMedium)
        .fontColor(AppColors.ink())
        .layoutWeight(1)
      if (this.action !== undefined) {
        Button(this.i18n.t((this.action as UiAction).labelKey))
          .fontSize(AppTypography.label)
          .fontColor((this.action as UiAction).destructive ? AppColors.red() : AppColors.primary())
          .backgroundColor(Color.Transparent)
          .enabled((this.action as UiAction).enabled)
          .constraintSize({ minHeight: 44 })
          .accessibilityText(this.i18n.t((this.action as UiAction).labelKey))
          .onClick((): void => {
            this.onAction((this.action as UiAction).id);
          })
      }
    }
    .width('100%')
    .padding({ top: AppSpacing.sm, bottom: AppSpacing.xs })
  }
}

@Component
export struct PrimaryButton {
  @Require i18n: I18nService;
  @Prop localeRevision: number = 0;
  @Prop labelKey: string = '';
  @Prop isEnabled: boolean = true;
  @Prop loading: boolean = false;
  @Prop destructive: boolean = false;
  @Prop fullWidth: boolean = true;
  onTap: () => void = (): void => {};

  build() {
    Button(this.i18n.t(this.labelKey))
      // I18N-07: no fixed pixel width; long English labels may wrap instead of
      // being clipped. Full-width buttons still fill their parent.
      .width(this.fullWidth ? '100%' : 'auto')
      .constraintSize({ minWidth: this.fullWidth ? 0 : 168 })
      .height(48)
      .fontSize(AppTypography.body)
      .fontColor(Color.White)
      .backgroundColor(this.destructive ? AppColors.red() : AppColors.primary())
      .borderRadius(AppRadius.button)
      .enabled(this.isEnabled && !this.loading)
      .accessibilityText(this.i18n.t(this.labelKey))
      .onClick((): void => {
        if (this.isEnabled && !this.loading) {
          this.onTap();
        }
      })
  }
}

@Component
export struct IconButton {
  @Require i18n: I18nService;
  @Prop localeRevision: number = 0;
  @Prop icon: Resource | undefined = undefined;
  @Prop labelKey: string = '';
  @Prop isEnabled: boolean = true;
  onTap: () => void = (): void => {};

  build() {
    Button() {
      if (this.icon !== undefined) {
        Image(this.icon as Resource)
          .width(20)
          .height(20)
      } else {
        Text(this.i18n.t(this.labelKey))
          .fontSize(AppTypography.label)
          .fontColor(AppColors.inkSoft())
      }
    }
    .height(44)
    .constraintSize({ minWidth: 44 })
    .padding({ left: AppSpacing.sm, right: AppSpacing.sm })
    .backgroundColor(AppColors.surface())
    .borderRadius(AppRadius.button)
    .enabled(this.isEnabled)
    .accessibilityText(this.i18n.t(this.labelKey))
    .onClick((): void => {
      if (this.isEnabled) {
        this.onTap();
      }
    })
  }
}

@Component
export struct AppTextField {
  @Require i18n: I18nService;
  @Prop localeRevision: number = 0;
  @Prop labelKey: string = '';
  @Prop value: string = '';
  @Prop placeholderKey: string = '';
  @Prop password: boolean = false;
  @Prop errorKey: string = '';
  @Prop isEnabled: boolean = true;
  onChange: (value: string) => void = (value: string): void => {};

  build() {
    Column({ space: AppSpacing.xxs }) {
      if (this.labelKey.length > 0) {
        Text(this.i18n.t(this.labelKey))
          .fontSize(AppTypography.label)
          .fontColor(AppColors.muted())
      }
      TextInput({
        placeholder: this.i18n.t(this.placeholderKey),
        text: this.value
      })
        .type(this.password ? InputType.Password : InputType.Normal)
        .fontSize(AppTypography.body)
        .fontColor(AppColors.ink())
        .placeholderColor(AppColors.muted())
        .backgroundColor(AppColors.field())
        .borderRadius(AppRadius.field)
        .border({ width: 1, color: AppColors.line() })
        .height(48)
        .enabled(this.isEnabled)
        .onChange((next: string): void => {
          this.onChange(next);
        })
      if (this.errorKey.length > 0) {
        Text(this.i18n.t(this.errorKey))
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.red())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct SliderControl {
  @Prop value: number = 0;
  @Prop min: number = 0;
  @Prop max: number = 100;
  @Prop step: number = 1;
  @Prop isEnabled: boolean = true;
  onBegin: () => void = (): void => {};
  onChange: (value: number) => void = (value: number): void => {};
  onCommit: (value: number) => void = (value: number): void => {};

  build() {
    Slider({
      value: this.value,
      min: this.min,
      max: this.max,
      step: this.step,
      style: SliderStyle.OutSet
    })
      .width('100%')
      .blockColor(AppColors.surfaceStrong())
      .trackColor(AppColors.line())
      .selectedColor(AppColors.primary())
      .enabled(this.isEnabled)
      .onChange((next: number, mode: SliderChangeMode): void => {
        if (mode === SliderChangeMode.Begin) {
          this.onBegin();
        } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
          this.onCommit(next);
        } else {
          this.onChange(next);
        }
      })
  }
}

@Component
export struct EmptyState {
  @Require i18n: I18nService;
  @Prop localeRevision: number = 0;
  @Prop illustration: Resource | undefined = undefined;
  @Prop titleKey: string = '';
  @Prop messageKey: string = '';
  @Prop action: UiAction | undefined = undefined;
  onAction: (id: string) => void = (id: string): void => {};

  build() {
    Column({ space: AppSpacing.sm }) {
      if (this.illustration !== undefined) {
        Image(this.illustration as Resource)
          .width(72)
          .height(72)
      }
      Text(this.i18n.t(this.titleKey))
        .fontSize(AppTypography.title)
        .fontWeight(AppTypography.weightMedium)
        .fontColor(AppColors.ink())
        .textAlign(TextAlign.Center)
      if (this.messageKey.length > 0) {
        Text(this.i18n.t(this.messageKey))
          .fontSize(AppTypography.body)
          .fontColor(AppColors.inkSoft())
          .textAlign(TextAlign.Center)
      }
      if (this.action !== undefined) {
        PrimaryButton({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          labelKey: (this.action as UiAction).labelKey,
          isEnabled: (this.action as UiAction).enabled,
          fullWidth: false,
          onTap: (): void => {
            this.onAction((this.action as UiAction).id);
          }
        })
      }
    }
    .width('100%')
    .padding(AppSpacing.lg)
    .alignItems(HorizontalAlign.Center)
  }
}

@Component
export struct ErrorState {
  @Require i18n: I18nService;
  @Prop localeRevision: number = 0;
  @Prop titleKey: string = 'common.error';
  @Prop messageKey: string = '';
  @Prop retryKey: string = 'common.retry';
  onRetry: () => void = (): void => {};

  build() {
    Column({ space: AppSpacing.sm }) {
      Text(this.i18n.t(this.titleKey))
        .fontSize(AppTypography.title)
        .fontWeight(AppTypography.weightMedium)
        .fontColor(AppColors.red())
        .textAlign(TextAlign.Center)
      if (this.messageKey.length > 0) {
        Text(this.i18n.t(this.messageKey))
          .fontSize(AppTypography.body)
          .fontColor(AppColors.inkSoft())
          .textAlign(TextAlign.Center)
      }
      PrimaryButton({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        labelKey: this.retryKey,
        fullWidth: false,
        onTap: (): void => {
          this.onRetry();
        }
      })
    }
    .width('100%')
    .padding(AppSpacing.lg)
    .alignItems(HorizontalAlign.Center)
  }
}

@Component
export struct LoadingSkeleton {
  @Prop rows: number = 3;
  @Prop cardHeight: number = 72;

  build() {
    Column({ space: AppSpacing.sm }) {
      ForEach(this.skeletonRows(), (item: number, index: number): void => {
        Column()
          .width('100%')
          .height(this.cardHeight)
          .backgroundColor(AppColors.surface())
          .borderRadius(AppRadius.card)
      }, (item: number, index: number): string => 'skeleton-' + index)
    }
    .width('100%')
  }

  private skeletonRows(): number[] {
    const result: number[] = [];
    const count = this.rows < 1 ? 1 : this.rows;
    for (let index = 0; index < count; index++) {
      result.push(index);
    }
    return result;
  }
}

@Component
export struct AppDialog {
  @Require i18n: I18nService;
  @Prop localeRevision: number = 0;
  @Prop titleKey: string = '';
  @Prop messageKey: string = '';
  @Prop detail: string = '';
  @Prop confirmKey: string = 'common.confirm';
  @Prop cancelKey: string = 'common.cancel';
  @Prop destructive: boolean = false;
  @Prop busy: boolean = false;
  onConfirm: () => void = (): void => {};
  onCancel: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick((): void => {
          if (!this.busy) {
            this.onCancel();
          }
        })
      Column({ space: AppSpacing.sm }) {
        Text(this.i18n.t(this.titleKey))
          .fontSize(AppTypography.title)
          .fontWeight(AppTypography.weightMedium)
          .fontColor(AppColors.ink())
        if (this.messageKey.length > 0) {
          Text(this.i18n.t(this.messageKey))
            .fontSize(AppTypography.body)
            .fontColor(AppColors.inkSoft())
        }
        if (this.detail.length > 0) {
          Text(this.detail)
            .fontSize(AppTypography.label)
            .fontColor(AppColors.muted())
        }
        Row({ space: AppSpacing.sm }) {
          Button(this.i18n.t(this.cancelKey))
            .layoutWeight(1)
            .height(44)
            .fontSize(AppTypography.body)
            .fontColor(AppColors.ink())
            .backgroundColor(AppColors.field())
            .borderRadius(AppRadius.button)
            .enabled(!this.busy)
            .onClick((): void => {
              this.onCancel();
            })
          Button(this.i18n.t(this.confirmKey))
            .layoutWeight(1)
            .height(44)
            .fontSize(AppTypography.body)
            .fontColor(Color.White)
            .backgroundColor(this.destructive ? AppColors.red() : AppColors.primary())
            .borderRadius(AppRadius.button)
            .enabled(!this.busy)
            .onClick((): void => {
              this.onConfirm();
            })
        }
        .width('100%')
      }
      .width('86%')
      .padding(AppSpacing.lg)
      .backgroundColor(AppColors.surfaceStrong())
      .borderRadius(AppRadius.modal)
      .border({ width: 1, color: AppColors.edge() })
      .shadow({
        radius: 30,
        color: $r('app.color.shadow_base'),
        offsetX: 0,
        offsetY: 14
      })
    }
    .width('100%')
    .height('100%')
  }
}
