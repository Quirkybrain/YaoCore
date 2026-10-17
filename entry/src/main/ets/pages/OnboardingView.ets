/*
 * YaoCore T-17 shell onboarding (F-02).
 * Producer: agent:implementation-engineer | Task: wp-070-fix-t17
 * Contract: DES-B §17.1.5, §3.1.3, §3.3.4
 *
 * Minimal create/join flows reachable before UNLOCKED. The full C-26 family
 * page remains T-18; this view only supplies what a fresh install needs:
 * create a family + owner profile, or accept an invitation container and
 * create the local profile. It never unlocks automatically.
 *
 * Labels reuse existing app.string / rawfile keys because resources/** is
 * outside this task's write scope; T-18 should add dedicated family.join and
 * field-label keys when it owns the full page.
 */
import { AppError } from '../common/types/AppError';
import type { I18nService } from '../service/i18n/I18nService';
import { AppContext } from '../app/AppContext';
import { ShellTheme } from '../app/ShellTheme';

export enum OnboardingMode {
  NONE,
  CREATE,
  JOIN
}

const PASSWORD_MIN_LENGTH: number = 8;

@Component
export struct OnboardingView {
  @Require appContext: AppContext;
  @Require i18n: I18nService;
  @Prop mode: OnboardingMode = OnboardingMode.NONE;
  onCancel: () => void = (): void => {};
  @State familyName: string = '';
  @State displayName: string = '';
  @State invitationText: string = '';
  @State invitationCode: string = '';
  @State joinRequestText: string = '';
  @State password: string = '';
  @State busy: boolean = false;
  @State errorKey: string = '';

  build() {
    Column({ space: ShellTheme.SPACING_SM }) {
      Text(this.mode === OnboardingMode.JOIN
        ? this.i18n.t('family.switch') : this.i18n.t('family.create'))
        .fontSize(ShellTheme.FONT_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.shell_ink'))
      if (this.mode === OnboardingMode.CREATE) {
        TextInput({
          placeholder: $r('app.string.page_family'),
          text: this.familyName
        })
          .fontSize(ShellTheme.FONT_BODY)
          .borderRadius(ShellTheme.BUTTON_RADIUS)
          .onChange((value: string): void => {
            this.familyName = value;
          })
      }
      TextInput({
        placeholder: $r('app.string.tab_profile'),
        text: this.displayName
      })
        .fontSize(ShellTheme.FONT_BODY)
        .borderRadius(ShellTheme.BUTTON_RADIUS)
        .enabled(this.mode === OnboardingMode.CREATE || this.joinRequestText.length === 0)
        .onChange((value: string): void => {
          this.displayName = value;
        })
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
      if (this.mode === OnboardingMode.JOIN) {
        if (this.joinRequestText.length === 0) {
          Button($r('app.string.common_confirm'))
            .width('100%')
            .fontSize(ShellTheme.FONT_BODY)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.shell_primary'))
            .borderRadius(ShellTheme.BUTTON_RADIUS)
            .enabled(!this.busy && this.displayName.trim().length > 0)
            .onClick((): void => {
              this.startJoin();
            })
        } else {
          Text(this.joinRequestText)
            .fontSize(ShellTheme.FONT_LABEL)
            .fontColor($r('app.color.shell_ink_soft'))
            .textAlign(TextAlign.Center)
            .wordBreak(WordBreak.BREAK_ALL)
            .copyOption(CopyOptions.LocalDevice)
          TextInput({
            placeholder: $r('app.string.session_no_profile_message'),
            text: this.invitationText
          })
            .fontSize(ShellTheme.FONT_BODY)
            .borderRadius(ShellTheme.BUTTON_RADIUS)
            .onChange((value: string): void => {
              this.invitationText = value;
            })
          TextInput({
            placeholder: this.i18n.t('invite.mode.code_kek'),
            text: this.invitationCode
          })
            .fontSize(ShellTheme.FONT_BODY)
            .borderRadius(ShellTheme.BUTTON_RADIUS)
            .onChange((value: string): void => {
              this.invitationCode = value;
            })
        }
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
      Row({ space: ShellTheme.SPACING_SM }) {
        Button($r('app.string.common_confirm'))
          .fontSize(ShellTheme.FONT_BODY)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.shell_primary'))
          .borderRadius(ShellTheme.BUTTON_RADIUS)
          .enabled(!this.busy && this.canSubmit())
          .onClick((): void => {
            this.submit();
          })
        Button($r('app.string.common_cancel'))
          .fontSize(ShellTheme.FONT_BODY)
          .fontColor($r('app.color.shell_ink'))
          .backgroundColor($r('app.color.shell_surface'))
          .borderRadius(ShellTheme.BUTTON_RADIUS)
          .enabled(!this.busy)
          .onClick((): void => {
            this.appContext.cancelJoin().catch((error: Object): void => {
              // Best-effort join-request cleanup; the view closes regardless.
            });
            this.onCancel();
          })
      }
    }
    .width('100%')
    .padding(ShellTheme.SPACING_MD)
    .backgroundColor($r('app.color.shell_surface'))
    .borderRadius(ShellTheme.BUTTON_RADIUS)
  }

  private canSubmit(): boolean {
    if (this.displayName.trim().length === 0 || this.password.length < PASSWORD_MIN_LENGTH) {
      return false;
    }
    if (this.mode === OnboardingMode.CREATE) {
      return this.familyName.trim().length > 0;
    }
    if (this.mode === OnboardingMode.JOIN) {
      return this.joinRequestText.length > 0 && this.invitationText.trim().length > 0;
    }
    return false;
  }

  private startJoin(): void {
    if (this.busy || this.displayName.trim().length === 0) {
      return;
    }
    this.busy = true;
    this.errorKey = '';
    this.appContext.startJoin(this.displayName.trim()).then((text: string): void => {
      this.joinRequestText = text;
      this.busy = false;
    }, (error: Object): void => {
      this.fail(error);
    });
  }

  private submit(): void {
    if (this.busy || !this.canSubmit()) {
      return;
    }
    this.busy = true;
    this.errorKey = '';
    if (this.mode === OnboardingMode.CREATE) {
      this.appContext.createFamily(this.familyName.trim(), this.displayName.trim(),
        this.password).then((): void => {
        this.busy = false;
      }, (error: Object): void => {
        this.fail(error);
      });
      return;
    }
    this.appContext.completeJoin(this.invitationText.trim(), this.invitationCode.trim(),
      this.displayName.trim(), this.password).then((): void => {
      this.busy = false;
    }, (error: Object): void => {
      this.fail(error);
    });
  }

  private fail(error: Object): void {
    this.errorKey = error instanceof AppError
      ? (error as AppError).i18nKey : 'errors.app.internal_error';
    this.busy = false;
  }
}
