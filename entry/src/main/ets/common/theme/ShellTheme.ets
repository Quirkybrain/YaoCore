/*
 * YaoCore C-24 shell design tokens (migrated from app/ShellTheme.ets).
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §13.1.1; UIUX §2/§5; C-24
 *
 * Migrated to the canonical `common/theme/**` path owned by C-24. Values are
 * aliases of AppMotionTokens / AppSpacing / AppTypography so there is exactly
 * one token source. Kept as a thin compatibility facade for the T-17 shell.
 */
import {
  AppLayout,
  AppMotionTokens,
  AppRadius,
  AppSpacing,
  AppTypography
} from './AppTheme';

export class ShellTheme {
  // Layout (UIUX §2.1)
  static readonly HEADER_HEIGHT: number = AppLayout.HEADER_HEIGHT;
  static readonly TAB_BAR_HEIGHT: number = AppLayout.TAB_BAR_HEIGHT;
  static readonly TAB_BAR_RADIUS: number = AppRadius.tabBar;
  static readonly CARD_RADIUS: number = AppRadius.card;
  static readonly BUTTON_RADIUS: number = AppRadius.button;
  static readonly ORB_BLUR: number = AppLayout.ORB_BLUR;

  // Spacing
  static readonly SPACING_XXS: number = AppSpacing.xxs;
  static readonly SPACING_XS: number = AppSpacing.xs;
  static readonly SPACING_SM: number = AppSpacing.sm;
  static readonly SPACING_MD: number = AppSpacing.md;
  static readonly SPACING_LG: number = AppSpacing.lg;
  static readonly SPACING_XL: number = AppSpacing.xl;

  // Typography
  static readonly FONT_DISPLAY: number = AppTypography.display;
  static readonly FONT_TITLE: number = AppTypography.title;
  static readonly FONT_SECTION: number = AppTypography.section;
  static readonly FONT_BODY: number = AppTypography.body;
  static readonly FONT_LABEL: number = AppTypography.label;
  static readonly FONT_CAPTION: number = AppTypography.caption;

  // Motion
  static readonly SPRING_TOUCH_RESPONSE: number = AppMotionTokens.SPRING_TOUCH_RESPONSE;
  static readonly SPRING_TOUCH_DAMPING: number = AppMotionTokens.SPRING_TOUCH_DAMPING;
  static readonly SPRING_MODAL_RESPONSE: number = AppMotionTokens.SPRING_MODAL_RESPONSE;
  static readonly SPRING_MODAL_DAMPING: number = AppMotionTokens.SPRING_MODAL_DAMPING;
  static readonly SPRING_REVERT_RESPONSE: number = AppMotionTokens.SPRING_REVERT_RESPONSE;
  static readonly SPRING_REVERT_DAMPING: number = AppMotionTokens.SPRING_REVERT_DAMPING;
  static readonly FADE_MS: number = AppMotionTokens.FADE_MS;
  static readonly REDUCED_MOTION_MS: number = AppMotionTokens.REDUCED_MOTION_MS;

  // Ambient orb periods
  static readonly ORB_APRICOT_PERIOD_MS: number = AppMotionTokens.ORB_APRICOT_PERIOD_MS;
  static readonly ORB_MINT_PERIOD_MS: number = AppMotionTokens.ORB_MINT_PERIOD_MS;
  static readonly ORB_AQUA_PERIOD_MS: number = AppMotionTokens.ORB_AQUA_PERIOD_MS;
  static readonly ORB_LILAC_PERIOD_MS: number = AppMotionTokens.ORB_LILAC_PERIOD_MS;

  static motionMs(enabled: boolean): number {
    return AppMotionTokens.motionMs(enabled);
  }
}
