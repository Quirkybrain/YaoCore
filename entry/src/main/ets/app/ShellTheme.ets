/*
 * YaoCore C-24/T-17 shell design tokens.
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §13.1.1, §13.1; UIUX §2/§5; C-24
 *
 * Location note: C-24's canonical path is `common/theme/**`, which is outside
 * T-17's delegated write scope. The shell therefore keeps the single T-17
 * definition here, using the UIUX §2/§5 values verbatim. T-18 owns the full
 * C-24 token module and components; it must move/expand these values rather
 * than define a second, diverging set. No page may use magic numbers for
 * radius/spacing/motion.
 */
export class ShellTheme {
  // Layout (UIUX §2.1)
  static readonly HEADER_HEIGHT: number = 56;
  static readonly TAB_BAR_HEIGHT: number = 68;
  static readonly TAB_BAR_RADIUS: number = 24;
  static readonly CARD_RADIUS: number = 22;
  static readonly BUTTON_RADIUS: number = 13;
  static readonly ORB_BLUR: number = 62;

  // Spacing
  static readonly SPACING_XXS: number = 4;
  static readonly SPACING_XS: number = 8;
  static readonly SPACING_SM: number = 12;
  static readonly SPACING_MD: number = 16;
  static readonly SPACING_LG: number = 24;
  static readonly SPACING_XL: number = 32;

  // Typography (UIUX §2.3, DES-B AppTypography)
  static readonly FONT_DISPLAY: number = 28;
  static readonly FONT_TITLE: number = 22;
  static readonly FONT_SECTION: number = 18;
  static readonly FONT_BODY: number = 15;
  static readonly FONT_LABEL: number = 13;
  static readonly FONT_CAPTION: number = 11;

  // Motion (UIUX §5; DES-B AppMotionTokens)
  static readonly SPRING_TOUCH_RESPONSE: number = 0.35;
  static readonly SPRING_TOUCH_DAMPING: number = 0.75;
  static readonly SPRING_MODAL_RESPONSE: number = 0.45;
  static readonly SPRING_MODAL_DAMPING: number = 0.82;
  static readonly SPRING_REVERT_RESPONSE: number = 0.50;
  static readonly SPRING_REVERT_DAMPING: number = 0.65;
  static readonly FADE_MS: number = 220;
  static readonly REDUCED_MOTION_MS: number = 150;

  // Ambient orb periods (UIUX §2.2). Long orb animation is intentionally not
  // started by the T-17 shell; T-18 owns the full AmbientBackground.
  static readonly ORB_APRICOT_PERIOD_MS: number = 32000;
  static readonly ORB_MINT_PERIOD_MS: number = 29000;
  static readonly ORB_AQUA_PERIOD_MS: number = 37000;
  static readonly ORB_LILAC_PERIOD_MS: number = 35000;

  static motionMs(enabled: boolean): number {
    return enabled ? ShellTheme.FADE_MS : ShellTheme.REDUCED_MOTION_MS;
  }
}
