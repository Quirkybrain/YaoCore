/*
 * YaoCore T-17 RoomManage NavDestination placeholder (C-26 body owned by T-18).
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §15.1.3, §17.1.5
 */
import type { NavigationService } from '../app/NavigationService';
import { PlaceholderPageBody } from './PlaceholderContent';

@Component
export struct RoomManagePage {
  @Require navigation: NavigationService;

  build() {
    NavDestination() {
      PlaceholderPageBody({
        title: $r('app.string.page_room_manage'),
        message: $r('app.string.placeholder_message'),
        navigation: this.navigation
      })
    }
    .title($r('app.string.page_room_manage'))
  }
}
