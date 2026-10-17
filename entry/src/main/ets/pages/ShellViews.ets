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
import { ShellTheme } from '../app/ShellTheme';

@Component
export struct SessionGateView {
  @Require appContext: AppContext;
  @Require i18n: I18nService;
  @Prop gate: SessionGateState = SessionGateState.NO_PROFILE;
  @Prop familyName: string = '';
  @State profiles: SessionGateProfile[] = [];
  @State selectedProfileId: string = '';
  @State password: string = '';
  @State busy: boolean = false;
  @State errorKey: string = '';

  aboutToAppear(): void {
    if (this.gate === SessionGateState.LOCKED) {
      this.loadProfiles();
    }
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
  }

  private loadProfiles(): void {
    this.appContext.listProfiles().then(
      (profiles: ReadonlyArray<SessionGateProfile>): void => {
        this.profiles = profiles.slice();
        if (this.selectedProfileId.length === 0 && profiles.length > 0) {
          this.selectedProfileId = profiles[0].profileId;
        }
      },
      (error: Object): void => {
        this.profiles = [];
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
  @Require navigation: NavigationService;

  build() {
    Column({ space: ShellTheme.SPACING_MD }) {
      Text($r('app.string.route_unknown_title'))
        .fontSize(ShellTheme.FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.shell_ink'))
      Text($r('app.string.route_unknown_message'))
        .fontSize(ShellTheme.FONT_BODY)
        .fontColor($r('app.color.shell_ink_soft'))
        .textAlign(TextAlign.Center)
      Button($r('app.string.common_back'))
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
  }
}
