/*
 * YaoCore T-17 Scenes tab placeholder (C-26 body owned by T-18).
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §15.1.2, §17.1.5
 */
import { ShellTheme } from '../app/ShellTheme';
import { PlaceholderText } from './PlaceholderContent';

@Component
export struct ScenePage {
  build() {
    Column({ space: ShellTheme.SPACING_LG }) {
      PlaceholderText({
        title: $r('app.string.tab_scenes'),
        message: $r('app.string.placeholder_message')
      })
    }
    .width('100%')
    .height('100%')
    .padding(ShellTheme.SPACING_LG)
    .justifyContent(FlexAlign.Center)
  }
}
