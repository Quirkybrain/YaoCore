/*
 * YaoCore C-28 Index: unique @Entry navigation shell.
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §17.1.5, §17.3; DES-B-C28-STATE
 *
 * Boot sequence:
 *   1. read the ShellBootstrap written by EntryAbility's ability LocalStorage;
 *   2. subscribe session-gate + locale changes;
 *   3. await AppContext.initialize();
 *   4. render StartupErrorView, SessionGateView, or MainShell.
 * No business page is constructed before the session gate is UNLOCKED.
 *
 * `useSharedStorage: true` is required (API 12+): without it the framework
 * creates a page-local LocalStorage and `bootstrap` never resolves to the
 * instance passed to `windowStage.loadContent('pages/Index', storage)`.
 */
import { common } from '@kit.AbilityKit';
import { AppError, AppErrors } from '../common/types/AppError';
import { AppContext, SessionGateState } from '../app/AppContext';
import { NavigationService } from '../app/NavigationService';
import { ShellBootstrap } from '../app/ShellBootstrap';
import { ShellTheme } from '../common/theme/ShellTheme';
import { MainShell } from './MainShell';
import { ShellBackdrop } from './ShellBackdrop';
import { SessionGateView, StartupErrorView } from './ShellViews';

@Entry({ useSharedStorage: true })
@Component
struct Index {
  @LocalStorageProp('bootstrap') bootstrap: ShellBootstrap = new ShellBootstrap();
  @State ready: boolean = false;
  @State startupError: AppError | undefined = undefined;
  @State sessionGate: SessionGateState = SessionGateState.NO_PROFILE;
  @State localeRevision: number = 0;
  @State motionEnabled: boolean = true;

  private appContext: AppContext | undefined = undefined;
  private navigation: NavigationService | undefined = undefined;
  private unsubscribeGate: (() => void) | undefined = undefined;
  private unsubscribeLocale: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.appContext = this.bootstrap.appContext;
    this.startupError = this.bootstrap.startupError;
    const context = this.appContext;
    if (context === undefined) {
      if (this.startupError === undefined) {
        this.startupError = AppErrors.of('INTERNAL_ERROR', []);
      }
      this.ready = true;
      return;
    }

    this.navigation = new NavigationService(new NavPathStack());
    this.unsubscribeGate = context.subscribeSessionGate((state: SessionGateState): void => {
      this.sessionGate = state;
    });
    this.unsubscribeLocale = context.i18n.onLocaleChanged((): void => {
      this.localeRevision = this.localeRevision + 1;
    });
    context.isMotionEnabled().then((enabled: boolean): void => {
      this.motionEnabled = enabled;
    }, (error: Object): void => {
      this.motionEnabled = true;
    });

    context.initialize().then((): void => {
      const current = this.appContext;
      if (current === undefined) {
        return;
      }
      this.startupError = current.initializationError;
      this.sessionGate = current.sessionGate;
      this.ready = true;
    }, (error: Object): void => {
      this.startupError = error instanceof AppError
        ? error as AppError : AppErrors.of('INTERNAL_ERROR', []);
      this.ready = true;
    });
  }

  aboutToDisappear(): void {
    if (this.unsubscribeGate !== undefined) {
      this.unsubscribeGate();
      this.unsubscribeGate = undefined;
    }
    if (this.unsubscribeLocale !== undefined) {
      this.unsubscribeLocale();
      this.unsubscribeLocale = undefined;
    }
  }

  onBackPress(): boolean {
    if (this.navigation !== undefined) {
      return this.navigation.onBack();
    }
    return false;
  }

  build() {
    Stack() {
      ShellBackdrop({ motionEnabled: this.motionEnabled })
      if (!this.ready) {
        Column({ space: ShellTheme.SPACING_SM }) {
          LoadingProgress()
            .width(ShellTheme.SPACING_XL)
            .height(ShellTheme.SPACING_XL)
            .color($r('app.color.shell_primary'))
          Text($r('app.string.common_loading'))
            .fontSize(ShellTheme.FONT_BODY)
            .fontColor($r('app.color.shell_ink_soft'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.startupError !== undefined) {
        StartupErrorView({
          error: this.startupError,
          i18n: this.appContext === undefined ? undefined : this.appContext.i18n,
          onRetry: (): void => {
            this.retry();
          },
          onExit: (): void => {
            this.exit();
          }
        })
      } else if (this.appContext === undefined || this.navigation === undefined) {
        StartupErrorView({
          error: AppErrors.of('INTERNAL_ERROR', []),
          i18n: undefined,
          onRetry: (): void => {
            this.retry();
          },
          onExit: (): void => {
            this.exit();
          }
        })
      } else if (this.sessionGate !== SessionGateState.UNLOCKED) {
        SessionGateView({
          appContext: this.appContext,
          i18n: this.appContext.i18n,
          gate: this.sessionGate,
          localeRevision: this.localeRevision,
          familyName: this.appContext.activeFamilyName,
          activeFamilyId: this.appContext.activeFamilyId === undefined
            ? '' : this.appContext.activeFamilyId
        })
      } else {
        MainShell({
          appContext: this.appContext,
          i18n: this.appContext.i18n,
          navigation: this.navigation,
          vmFactory: this.appContext.pageVms,
          localeRevision: this.localeRevision,
          motionEnabled: this.motionEnabled
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  private retry(): void {
    const context = this.appContext;
    if (context === undefined) {
      return;
    }
    this.ready = false;
    this.startupError = undefined;
    context.retryInitialization().then((): void => {
      const current = this.appContext;
      if (current === undefined) {
        return;
      }
      this.startupError = current.initializationError;
      this.sessionGate = current.sessionGate;
      this.ready = true;
    }, (error: Object): void => {
      this.startupError = error instanceof AppError
        ? error as AppError : AppErrors.of('INTERNAL_ERROR', []);
      this.ready = true;
    });
  }

  private exit(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.terminateSelf();
    } catch (error) {
      // Nothing else can be safely done from a startup error state.
    }
  }
}
