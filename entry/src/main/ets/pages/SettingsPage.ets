/*
 * YaoCore T-17 Settings NavDestination placeholder (C-27 body owned by T-18).
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §16.1.3, §17.1.5; F-06 single-gateway cloud restriction
 *
 * This placeholder already consumes the mandatory v1 cloud restriction key so
 * the resource is wired and CI-checked before T-18 builds the full section.
 */
import type { I18nService } from '../service/i18n/I18nService';
import type { NavigationService } from '../app/NavigationService';
import { ShellTheme } from '../app/ShellTheme';
import { PlaceholderText } from './PlaceholderContent';

@Component
export struct SettingsPage {
  @Require i18n: I18nService;
  @Require navigation: NavigationService;

  build() {
    NavDestination() {
      Column({ space: ShellTheme.SPACING_LG }) {
        PlaceholderText({
          title: $r('app.string.page_settings'),
          message: $r('app.string.placeholder_message')
        })
        Text(this.i18n.t('settings.cloud.single_gateway_required'))
          .fontSize(ShellTheme.FONT_LABEL)
          .fontColor($r('app.color.shell_warning'))
          .textAlign(TextAlign.Center)
          .padding(ShellTheme.SPACING_SM)
          .backgroundColor($r('app.color.shell_surface'))
          .borderRadius(ShellTheme.CARD_RADIUS)
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
    .title($r('app.string.page_settings'))
  }
}
