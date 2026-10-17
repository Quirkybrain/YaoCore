/*
 * YaoCore T-17 shell gate / startup / route views.
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §17.1.3/§17.1.5, §17.2; DES-B-C28-STATE
 *
 * SessionGateView is a full-screen overlay, not a NavDestination: no business
 * page is rendered before UNLOCKED. It only shows profile display names and
 * the active family name (never old-family devices/members).
 */
import { AppError } from '../common/types/AppError';
import type { I18nService } from '../service/i18n/I18nService';
import {
  AppContext,
  SessionGateProfile,
  SessionGateState
} from '../app/AppContext';
import { NavigationService } from '../app/NavigationService';
import { ShellGateEntry, ShellGateRouting } from '../app/ShellGateRouting';
import { ShellTheme } from '../common/theme/ShellTheme';
import { OnboardingMode, OnboardingView } from './OnboardingView';

@Component
export struct SessionGateView {
  @Require appContext: AppContext;
  @Require i18n: I18nService;
  @Prop @Watch('onGateChanged') gate: SessionGateState = SessionGateState.NO_PROFILE;
  @Prop familyName: string = '';
  @Prop @Watch('onFamilyChanged') activeFamilyId: string = '';
  @Prop localeRevision: number = 0;
  @State profiles: SessionGateProfile[] = [];
  @State selectedProfileId: string = '';
  @State password: string = '';
  @State busy: boolean = false;
  @State errorKey: string = '';
  @State profilesError: boolean = false;
  @State onboardingMode: OnboardingMode = OnboardingMode.NONE;

  aboutToAppear(): void {
    if (this.gate === SessionGateState.LOCKED) {
      this.loadProfiles();
    }
  }

  /** F-04: NO_PROFILE -> LOCKED (onboarding/create/join) reloads profiles. */
  private onGateChanged(): void {
    this.resetEntryState();
    if (this.gate === SessionGateState.LOCKED) {
      this.loadProfiles();
    } else {
      this.profiles = [];
      this.profilesError = false;
    }
  }

  /** F-04: a family switch must not keep the previous family's profile list. */
  private onFamilyChanged(): void {
    this.resetEntryState();
    if (this.gate === SessionGateState.LOCKED) {
      this.loadProfiles();
    }
  }

  private resetEntryState(): void {
    this.selectedProfileId = '';
    this.password = '';
    this.errorKey = '';
    this.onboardingMode = OnboardingMode.NONE;
  }

  build() {
    Column({ space: ShellTheme.SPACING_MD }) {
      Text($r('app.string.shell_app_title'))
        .fontSize(ShellTheme.FONT_DISPLAY)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.shell_ink'))
      if (this.gate === SessionGateState.NO_PROFILE) {
        Text($r('app.string.session_no_profile_title'))
          .fontSize(ShellTheme.FONT_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.shell_ink'))
        Text($r('app.string.session_no_profile_message'))
          .fontSize(ShellTheme.FONT_BODY)
          .fontColor($r('app.color.shell_ink_soft'))
          .textAlign(TextAlign.Center)
        if (this.onboardingMode === OnboardingMode.NONE) {
          if (ShellGateRouting.hasEntry(this.gate, ShellGateEntry.CREATE_FAMILY)) {
            Button(this.i18n.t('family.create'))
              .width('100%')
              .fontSize(ShellTheme.FONT_BODY)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.shell_primary'))
              .borderRadius(ShellTheme.BUTTON_RADIUS)
              .onClick((): void => {
                this.onboardingMode = OnboardingMode.CREATE;
              })
          }
          if (ShellGateRouting.hasEntry(this.gate, ShellGateEntry.JOIN_FAMILY)) {
            Button(this.i18n.t('onboarding.join.title'))
              .width('100%')
              .fontSize(ShellTheme.FONT_BODY)
              .fontColor($r('app.color.shell_ink'))
              .backgroundColor($r('app.color.shell_surface'))
              .borderRadius(ShellTheme.BUTTON_RADIUS)
              .onClick((): void => {
                this.onboardingMode = OnboardingMode.JOIN;
              })
          }
        } else {
          OnboardingView({
            appContext: this.appContext,
            i18n: this.i18n,
            localeRevision: this.localeRevision,
            mode: this.onboardingMode,
            onCancel: (): void => {
              this.onboardingMode = OnboardingMode.NONE;
            }
          })
        }
      } else {
        Text($r('app.string.session_locked_title'))
          .fontSize(ShellTheme.FONT_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.shell_ink'))
        if (this.familyName.length > 0) {
          Text(this.familyName)
            .fontSize(ShellTheme.FONT_LABEL)
            .fontColor($r('app.color.shell_muted'))
        }
        Text($r('app.string.session_locked_message'))
          .fontSize(ShellTheme.FONT_BODY)
          .fontColor($r('app.color.shell_ink_soft'))
          .textAlign(TextAlign.Center)
        Text($r('app.string.session_profile_prompt'))
          .fontSize(ShellTheme.FONT_LABEL)
          .fontColor($r('app.color.shell_muted'))
        if (this.profilesError) {
          Text($r('app.string.common_refresh_failed'))
            .fontSize(ShellTheme.FONT_LABEL)
            .fontColor($r('app.color.shell_danger'))
            .textAlign(TextAlign.Center)
          Button($r('app.string.common_retry'))
            .fontSize(ShellTheme.FONT_BODY)
            .fontColor($r('app.color.shell_ink'))
            .backgroundColor($r('app.color.shell_surface'))
            .borderRadius(ShellTheme.BUTTON_RADIUS)
            .onClick((): void => {
              this.loadProfiles();
            })
        }
        ForEach(this.profiles, (profile: SessionGateProfile): void => {
          Button(profile.displayName)
            .width('100%')
            .fontSize(ShellTheme.FONT_BODY)
            .fontColor(this.selectedProfileId === profile.profileId
              ? Color.White : $r('app.color.shell_ink'))
            .backgroundColor(this.selectedProfileId === profile.profileId
              ? $r('app.color.shell_primary') : $r('app.color.shell_surface'))
            .borderRadius(ShellTheme.BUTTON_RADIUS)
            .onClick((): void => {
              this.selectedProfileId = profile.profileId;
            })
        }, (profile: SessionGateProfile): string => profile.profileId)
        TextInput({
          placeholder: $r('app.string.session_password_placeholder'),
          text: this.password
        })
          .type(InputType.Password)
          .fontSize(ShellTheme.FONT_BODY)
          .borderRadius(ShellTheme.BUTTON_RADIUS)
          .onChange((value: string): void => {
            this.password = value;
          })
        Button($r('app.string.session_unlock'))
          .width('100%')
          .fontSize(ShellTheme.FONT_BODY)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.shell_primary'))
          .borderRadius(ShellTheme.BUTTON_RADIUS)
          .enabled(!this.busy && this.selectedProfileId.length > 0 &&
            this.password.length > 0)
          .onClick((): void => {
            this.unlock();
          })
      }
      if (this.errorKey.length > 0) {
        Text(this.i18n.t(this.errorKey))
          .fontSize(ShellTheme.FONT_LABEL)
          .fontColor($r('app.color.shell_danger'))
          .textAlign(TextAlign.Center)
      }
      if (this.busy) {
        LoadingProgress()
          .width(ShellTheme.SPACING_XL)
          .height(ShellTheme.SPACING_XL)
          .color($r('app.color.shell_primary'))
      }
    }
    .width('100%')
    .height('100%')
    .padding(ShellTheme.SPACING_LG)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.shell_background'))
    .id('session-gate-locale-' + this.localeRevision)
  }

  private loadProfiles(): void {
    this.profilesError = false;
    this.appContext.listProfiles().then(
      (profiles: ReadonlyArray<SessionGateProfile>): void => {
        this.profiles = profiles.slice();
        let selectionStillValid = false;
        for (let index = 0; index < profiles.length; index++) {
          if (profiles[index].profileId === this.selectedProfileId) {
            selectionStillValid = true;
            break;
          }
        }
        if (!selectionStillValid) {
          this.selectedProfileId = profiles.length > 0 ? profiles[0].profileId : '';
        }
      },
      (error: Object): void => {
        this.profiles = [];
        this.selectedProfileId = '';
        this.profilesError = true;
      });
  }

  private unlock(): void {
    if (this.busy || this.selectedProfileId.length === 0) {
      return;
    }
    this.busy = true;
    this.errorKey = '';
    this.appContext.unlock(this.selectedProfileId, this.password).then(
      (): void => {
        this.password = '';
        this.busy = false;
      },
      (error: Object): void => {
        this.errorKey = error instanceof AppError
          ? (error as AppError).i18nKey : 'errors.app.internal_error';
        this.busy = false;
      });
  }
}

@Component
export struct StartupErrorView {
  @Require error: AppError;
  i18n: I18nService | undefined = undefined;
  onRetry: () => void = (): void => {};
  onExit: () => void = (): void => {};

  build() {
    Column({ space: ShellTheme.SPACING_MD }) {
      Text($r('app.string.startup_error_title'))
        .fontSize(ShellTheme.FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.shell_ink'))
      Text(this.i18n === undefined
        ? $r('app.string.startup_error_message') : this.i18n.t(this.error.i18nKey))
        .fontSize(ShellTheme.FONT_BODY)
        .fontColor($r('app.color.shell_ink_soft'))
        .textAlign(TextAlign.Center)
      Row({ space: ShellTheme.SPACING_SM }) {
        Button($r('app.string.common_retry'))
          .fontSize(ShellTheme.FONT_BODY)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.shell_primary'))
          .borderRadius(ShellTheme.BUTTON_RADIUS)
          .onClick((): void => {
            this.onRetry();
          })
        Button($r('app.string.common_close'))
          .fontSize(ShellTheme.FONT_BODY)
          .fontColor($r('app.color.shell_ink'))
          .backgroundColor($r('app.color.shell_surface'))
          .borderRadius(ShellTheme.BUTTON_RADIUS)
          .onClick((): void => {
            this.onExit();
          })
      }
    }
    .width('100%')
    .height('100%')
    .padding(ShellTheme.SPACING_LG)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.shell_background'))
  }
}

@Component
export struct UnknownRouteView {
  @Require i18n: I18nService;
  @Require navigation: NavigationService;
  @Prop localeRevision: number = 0;

  build() {
    Column({ space: ShellTheme.SPACING_MD }) {
      Text(this.i18n.t('route.unknown.title'))
        .fontSize(ShellTheme.FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.shell_ink'))
      Text(this.i18n.t('route.unknown.message'))
        .fontSize(ShellTheme.FONT_BODY)
        .fontColor($r('app.color.shell_ink_soft'))
        .textAlign(TextAlign.Center)
      Button(this.i18n.t('common.back'))
        .fontSize(ShellTheme.FONT_BODY)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.shell_primary'))
        .borderRadius(ShellTheme.BUTTON_RADIUS)
        .onClick((): void => {
          this.navigation.pop();
        })
    }
    .width('100%')
    .height('100%')
    .padding(ShellTheme.SPACING_LG)
    .justifyContent(FlexAlign.Center)
    .id('unknown-route-locale-' + this.localeRevision)
  }
}
