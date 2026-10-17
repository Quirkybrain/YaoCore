/*
 * YaoCore T-17 shell backdrop (static ambient orbs).
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §13.1.1 (C-24), UIUX §2.2; T-18 owns full AmbientBackground
 *
 * The orbs are deliberately static in the T-17 shell. The long-running orb
 * animation is a C-24/T-18 deliverable; keeping it off here guarantees the
 * reduced-motion/settings-off degradation without shipping a divergent
 * animation implementation.
 *
 * F-10: `Ellipse` uses the API 10/11 CommonShapeMethod.fill(ResourceColor)
 * overload; `Circle.fill` resolves to the API 26 ColorMetrics overload and
 * warns on the API 14 compatibility floor. Equal width/height renders a circle.
 * The backdrop (not interactive content) expands into the system safe area so
 * the immersive window layout from EntryAbility is painted edge-to-edge.
 */
import { ShellTheme } from '../app/ShellTheme';

@Component
export struct ShellBackdrop {
  @Prop motionEnabled: boolean = true;

  build() {
    Stack() {
      Ellipse()
        .width(520)
        .height(520)
        .fill($r('app.color.orb_apricot'))
        .opacity(this.motionEnabled ? 0.55 : 0.40)
        .blur(ShellTheme.ORB_BLUR)
        .position({ x: -160, y: -120 })
      Ellipse()
        .width(540)
        .height(540)
        .fill($r('app.color.orb_mint'))
        .opacity(this.motionEnabled ? 0.45 : 0.32)
        .blur(ShellTheme.ORB_BLUR)
        .position({ x: 190, y: 80 })
      Ellipse()
        .width(500)
        .height(500)
        .fill($r('app.color.orb_aqua'))
        .opacity(this.motionEnabled ? 0.40 : 0.30)
        .blur(ShellTheme.ORB_BLUR)
        .position({ x: -120, y: 430 })
      Ellipse()
        .width(380)
        .height(380)
        .fill($r('app.color.orb_lilac'))
        .opacity(this.motionEnabled ? 0.45 : 0.34)
        .blur(ShellTheme.ORB_BLUR)
        .position({ x: 210, y: 540 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.shell_background'))
    .clip(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
