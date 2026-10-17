/*
 * YaoCore T-17 Rooms tab placeholder (C-25 body owned by T-18).
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §14.1.1, §17.1.5
 */
import { AppRoute, NavigationService } from '../app/NavigationService';
import { ShellTheme } from '../app/ShellTheme';
import { PlaceholderText } from './PlaceholderContent';

@Component
export struct RoomsPage {
  @Require navigation: NavigationService;

  build() {
    Column({ space: ShellTheme.SPACING_LG }) {
      PlaceholderText({
        title: $r('app.string.tab_rooms'),
        message: $r('app.string.placeholder_message')
      })
      Button($r('app.string.rooms_manage'))
        .fontSize(ShellTheme.FONT_BODY)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.shell_primary'))
        .borderRadius(ShellTheme.BUTTON_RADIUS)
        .onClick((): void => {
          this.navigation.push(AppRoute.ROOM_MANAGE);
        })
    }
    .width('100%')
    .height('100%')
    .padding(ShellTheme.SPACING_LG)
    .justifyContent(FlexAlign.Center)
  }
}
