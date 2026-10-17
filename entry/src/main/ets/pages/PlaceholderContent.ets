/*
 * YaoCore T-17 shared placeholder content (shell-only).
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §14/§16, §17.1.5; T-18 replaces page bodies
 *
 * Every user-visible string is a $r() resource; no CJK/English literals.
 */
import { ShellTheme } from '../app/ShellTheme';
import { NavigationService } from '../app/NavigationService';

@Component
export struct PlaceholderText {
  @Require title: Resource;
  @Require message: Resource;

  build() {
    Column({ space: ShellTheme.SPACING_SM }) {
      Text(this.title)
        .fontSize(ShellTheme.FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.shell_ink'))
        .textAlign(TextAlign.Center)
      Text(this.message)
        .fontSize(ShellTheme.FONT_BODY)
        .fontColor($r('app.color.shell_ink_soft'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }
}

@Component
export struct PlaceholderPageBody {
  @Require title: Resource;
  @Require message: Resource;
  @Require navigation: NavigationService;

  build() {
    Column({ space: ShellTheme.SPACING_LG }) {
      PlaceholderText({ title: this.title, message: this.message })
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
