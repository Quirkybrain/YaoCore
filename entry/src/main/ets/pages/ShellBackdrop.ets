/*
 * YaoCore T-17 shell backdrop (static ambient orbs).
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §13.1.1 (C-24), UIUX §2.2; T-18 owns full AmbientBackground
 *
 * The orbs are deliberately static in the T-17 shell. The long-running orb
 * animation is a C-24/T-18 deliverable; keeping it off here guarantees the
 * reduced-motion/settings-off degradation without shipping a divergent
 * animation implementation.
 */
import { ShellTheme } from '../app/ShellTheme';

@Component
export struct ShellBackdrop {
  @Prop motionEnabled: boolean = true;

  build() {
    Stack() {
      Circle()
        .width(520)
        .height(520)
        .fill($r('app.color.orb_apricot'))
        .opacity(this.motionEnabled ? 0.55 : 0.40)
        .blur(ShellTheme.ORB_BLUR)
        .position({ x: -160, y: -120 })
      Circle()
        .width(540)
        .height(540)
        .fill($r('app.color.orb_mint'))
        .opacity(this.motionEnabled ? 0.45 : 0.32)
        .blur(ShellTheme.ORB_BLUR)
        .position({ x: 190, y: 80 })
      Circle()
        .width(500)
        .height(500)
        .fill($r('app.color.orb_aqua'))
        .opacity(this.motionEnabled ? 0.40 : 0.30)
        .blur(ShellTheme.ORB_BLUR)
        .position({ x: -120, y: 430 })
      Circle()
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
  }
}
