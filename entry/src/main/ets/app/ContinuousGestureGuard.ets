/*
 * YaoCore C-28 continuous-gesture guard (R3-02).
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §10.1.3/§10.1.4, §10.3.2; CQG-T15/T16 R3-02
 *
 * T-15/T-16 review R3-02 observed that DeviceViewModel.endContinuous() keeps a
 * fallback that sends one final command even after cancelContinuous() removed
 * the session. The UI must therefore never call endContinuous() after a
 * pointer-cancel/page-leave; it cancels and suppresses the later TouchUp.
 * T-18 slider wiring MUST use this guard (or an equivalent explicit flag):
 *
 *   onPointerCancel: guard.cancel(); vm.cancelContinuous(key);
 *   onTouchUp:       if (!guard.end()) return; else vm.endContinuous(key, value);
 *
 * Host test: entry/src/test/host/AppShell.test.mjs.
 */
export class ContinuousGestureGuard {
  private active: boolean = false;
  private cancelled: boolean = false;

  begin(): void {
    this.active = true;
    this.cancelled = false;
  }

  cancel(): void {
    if (this.active) {
      this.cancelled = true;
    }
  }

  /** Returns true only when the TouchUp may be forwarded to endContinuous. */
  end(): boolean {
    if (!this.active) {
      return false;
    }
    const allowed = !this.cancelled;
    this.active = false;
    this.cancelled = false;
    return allowed;
  }

  isActive(): boolean {
    return this.active;
  }

  isCancelled(): boolean {
    return this.cancelled;
  }
}
