/*
 * YaoCore C-24 design tokens.
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §13.1.1; UIUX §2, §5; I18N-07/08
 *
 * Single source of colour, spacing, radius, typography, shadow and motion
 * tokens. Colours are resource references only (I18N-08); both base and dark
 * resource folders define every name.
 */
import { CardVisualState } from './AppEnums';

export class AppColors {
  static background(): ResourceColor {
    return $r('app.color.background');
  }

  static ink(): ResourceColor {
    return $r('app.color.ink');
  }

  static inkSoft(): ResourceColor {
    return $r('app.color.ink_soft');
  }

  static muted(): ResourceColor {
    return $r('app.color.muted');
  }

  static mutedLight(): ResourceColor {
    return $r('app.color.muted_light');
  }

  static surface(): ResourceColor {
    return $r('app.color.surface');
  }

  static surfaceStrong(): ResourceColor {
    return $r('app.color.surface_strong');
  }

  static field(): ResourceColor {
    return $r('app.color.field');
  }

  static edge(): ResourceColor {
    return $r('app.color.edge');
  }

  static line(): ResourceColor {
    return $r('app.color.line');
  }

  static primary(): ResourceColor {
    return $r('app.color.primary');
  }

  static primaryDark(): ResourceColor {
    return $r('app.color.primary_dark');
  }

  static green(): ResourceColor {
    return $r('app.color.green');
  }

  static amber(): ResourceColor {
    return $r('app.color.amber');
  }

  static red(): ResourceColor {
    return $r('app.color.red');
  }

  static tabBackground(): ResourceColor {
    return $r('app.color.tab_background');
  }

  static orbApricot(): ResourceColor {
    return $r('app.color.orb_apricot');
  }

  static orbMint(): ResourceColor {
    return $r('app.color.orb_mint');
  }

  static orbAqua(): ResourceColor {
    return $r('app.color.orb_aqua');
  }

  static orbLilac(): ResourceColor {
    return $r('app.color.orb_lilac');
  }

  static cardFor(state: CardVisualState): ResourceColor {
    if (state === CardVisualState.PENDING) {
      return $r('app.color.surface_pending');
    }
    if (state === CardVisualState.REVERT) {
      return $r('app.color.surface_revert');
    }
    if (state === CardVisualState.DISABLED || state === CardVisualState.OFFLINE) {
      return $r('app.color.surface_muted');
    }
    return AppColors.surface();
  }

  static accentFor(state: CardVisualState): ResourceColor {
    if (state === CardVisualState.COMMITTED) {
      return $r('app.color.accent_committed');
    }
    if (state === CardVisualState.REVERT) {
      return $r('app.color.accent_revert');
    }
    if (state === CardVisualState.PENDING) {
      return $r('app.color.accent_pending');
    }
    return $r('app.color.edge');
  }
}

export class AppMotionTokens {
  static readonly SPRING_TOUCH: string = 'springMotion(0.35, 0.75)';
  static readonly SPRING_MODAL: string = 'springMotion(0.45, 0.82)';
  static readonly SPRING_REVERT: string = 'springMotion(0.50, 0.65)';

  static readonly SPRING_TOUCH_RESPONSE: number = 0.35;
  static readonly SPRING_TOUCH_DAMPING: number = 0.75;
  static readonly SPRING_MODAL_RESPONSE: number = 0.45;
  static readonly SPRING_MODAL_DAMPING: number = 0.82;
  static readonly SPRING_REVERT_RESPONSE: number = 0.50;
  static readonly SPRING_REVERT_DAMPING: number = 0.65;

  static readonly THROTTLE_CONTINUOUS_MS: number = 55;
  static readonly TIMEOUT_CONTROL_ACK_MS: number = 3000;
  static readonly TIMEOUT_BLE_CONNECT_MS: number = 30000;
  static readonly TIMEOUT_DOOR_CONFIRM_MS: number = 10000;
  static readonly REVERT_SETTLE_MS: number = 320;
  static readonly FADE_MS: number = 220;
  static readonly REDUCED_MOTION_MS: number = 150;

  static readonly BASE_SHADOW: string =
    '0 18vp 60vp rgba(72,112,143,0.085), 0 2vp 9vp rgba(87,119,142,0.035)';
  static readonly ACCENT_SHADOW: string = '0 10vp 40vp rgba(105,159,192,0.13)';
  static readonly GLOW_AMBER: string = '0 13vp 37vp rgba(251,195,117,0.23)';
  static readonly GLOW_AQUA: string = '0 13vp 37vp rgba(127,202,239,0.21)';
  static readonly GLOW_MINT: string = '0 13vp 37vp rgba(115,202,168,0.17)';
  static readonly GLOW_LILAC: string = '0 13vp 37vp rgba(186,168,232,0.17)';

  static readonly ORB_APRICOT_PERIOD_MS: number = 32000;
  static readonly ORB_MINT_PERIOD_MS: number = 29000;
  static readonly ORB_AQUA_PERIOD_MS: number = 37000;
  static readonly ORB_LILAC_PERIOD_MS: number = 35000;

  static motionMs(enabled: boolean): number {
    return enabled ? AppMotionTokens.FADE_MS : AppMotionTokens.REDUCED_MOTION_MS;
  }
}

export class AppSpacing {
  static readonly xxs: number = 4;
  static readonly xs: number = 8;
  static readonly sm: number = 12;
  static readonly md: number = 16;
  static readonly lg: number = 24;
  static readonly xl: number = 32;
  static readonly xxl: number = 48;
}

export class AppRadius {
  static readonly card: number = 22;
  static readonly button: number = 13;
  static readonly chip: number = 999;
  static readonly modal: number = 28;
  static readonly field: number = 14;
  static readonly tabBar: number = 24;
}

export class AppTypography {
  static readonly display: number = 28;
  static readonly title: number = 22;
  static readonly section: number = 18;
  static readonly body: number = 15;
  static readonly label: number = 13;
  static readonly caption: number = 11;
  static readonly weightBold: FontWeight = FontWeight.Bold;
  static readonly weightMedium: FontWeight = FontWeight.Medium;
  static readonly weightRegular: FontWeight = FontWeight.Regular;
}

export class AppShadows {
  static readonly base: string = AppMotionTokens.BASE_SHADOW;
  static readonly accent: string = AppMotionTokens.ACCENT_SHADOW;
  static readonly glowAmber: string = AppMotionTokens.GLOW_AMBER;
  static readonly glowAqua: string = AppMotionTokens.GLOW_AQUA;
  static readonly glowMint: string = AppMotionTokens.GLOW_MINT;
  static readonly glowLilac: string = AppMotionTokens.GLOW_LILAC;
}

export class AppLayout {
  static readonly HEADER_HEIGHT: number = 56;
  static readonly TAB_BAR_HEIGHT: number = 68;
  static readonly ORB_BLUR: number = 62;
  static readonly TOUCH_TARGET: number = 44;
}
