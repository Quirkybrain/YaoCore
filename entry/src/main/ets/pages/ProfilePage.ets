/*
 * YaoCore T-17 Profile tab placeholder (C-27 body owned by T-18).
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §16.1.4, §17.1.5
 *
 * The lock control is real: it calls AppContext.lock() so the shell gate can
 * be exercised before T-18 supplies the full profile page.
 */
import { AppContext } from '../app/AppContext';
import { AppRoute, NavigationService } from '../app/NavigationService';
import { ShellTheme } from '../app/ShellTheme';
import { PlaceholderText } from './PlaceholderContent';

@Component
export struct ProfilePage {
  @Require appContext: AppContext;
  @Require navigation: NavigationService;

  build() {
    Column({ space: ShellTheme.SPACING_MD }) {
      PlaceholderText({
        title: $r('app.string.tab_profile'),
        message: $r('app.string.placeholder_message')
      })
      Column({ space: ShellTheme.SPACING_XS }) {
        Button($r('app.string.page_family'))
          .width('100%')
          .fontSize(ShellTheme.FONT_BODY)
          .fontColor($r('app.color.shell_ink'))
          .backgroundColor($r('app.color.shell_surface'))
          .borderRadius(ShellTheme.BUTTON_RADIUS)
          .onClick((): void => {
            this.navigation.push(AppRoute.FAMILY);
          })
        Button($r('app.string.page_settings'))
          .width('100%')
          .fontSize(ShellTheme.FONT_BODY)
          .fontColor($r('app.color.shell_ink'))
          .backgroundColor($r('app.color.shell_surface'))
          .borderRadius(ShellTheme.BUTTON_RADIUS)
          .onClick((): void => {
            this.navigation.push(AppRoute.SETTINGS);
          })
        Button($r('app.string.page_about'))
          .width('100%')
          .fontSize(ShellTheme.FONT_BODY)
          .fontColor($r('app.color.shell_ink'))
          .backgroundColor($r('app.color.shell_surface'))
          .borderRadius(ShellTheme.BUTTON_RADIUS)
          .onClick((): void => {
            this.navigation.push(AppRoute.ABOUT);
          })
        Button($r('app.string.session_lock'))
          .width('100%')
          .fontSize(ShellTheme.FONT_BODY)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.shell_danger'))
          .borderRadius(ShellTheme.BUTTON_RADIUS)
          .onClick((): void => {
            this.appContext.lock().catch((error: Object): void => {
              // Session remains unlocked; the gate is recomputed on next event.
            });
          })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(ShellTheme.SPACING_LG)
    .justifyContent(FlexAlign.Center)
  }
}
