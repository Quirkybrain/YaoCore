/*
 * YaoCore T-17 DeviceControl NavDestination placeholder (C-25 body owned by T-18).
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §14.1.1, §17.1.5
 */
import { AppRouteParams } from '../app/NavigationService';
import type { NavigationService } from '../app/NavigationService';
import { ShellTheme } from '../app/ShellTheme';
import { PlaceholderText } from './PlaceholderContent';

@Component
export struct DeviceControlPage {
  @Require params: AppRouteParams;
  @Require navigation: NavigationService;

  build() {
    NavDestination() {
      Column({ space: ShellTheme.SPACING_MD }) {
        PlaceholderText({
          title: $r('app.string.page_device_control'),
          message: $r('app.string.placeholder_message')
        })
        if (this.params.gatewayId !== undefined && this.params.deviceId !== undefined) {
          Text(this.params.gatewayId + ' / ' + this.params.deviceId)
            .fontSize(ShellTheme.FONT_CAPTION)
            .fontColor($r('app.color.shell_muted'))
        }
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
    .title($r('app.string.page_device_control'))
  }
}
