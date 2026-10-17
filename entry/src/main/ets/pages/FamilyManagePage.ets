/*
 * YaoCore T-17 FamilyManage NavDestination placeholder (C-26 body owned by T-18).
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §15.1.2, §17.1.5
 */
import type { NavigationService } from '../app/NavigationService';
import { PlaceholderPageBody } from './PlaceholderContent';

@Component
export struct FamilyManagePage {
  @Require navigation: NavigationService;

  build() {
    NavDestination() {
      PlaceholderPageBody({
        title: $r('app.string.page_family'),
        message: $r('app.string.placeholder_message'),
        navigation: this.navigation
      })
    }
    .title($r('app.string.page_family'))
  }
}
