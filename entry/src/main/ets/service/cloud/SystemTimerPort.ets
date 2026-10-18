/*
 * YaoCore C-15 production timer adapter.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §8.1.7, §8.5
 *
 * The platform timer stays out of the cloud logic. CloudService only sees the
 * TimerPort seam; host tests inject a deterministic fake.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import type { CancellationToken } from '../../common/types/CancellationToken';
import type { TimerPort } from '../../contracts/TimerPort';

export class SystemTimerPort implements TimerPort {
  private timer: number | undefined = undefined;
  private rejecter: ((error: AppError) => void) | undefined = undefined;

  sleep(ms: number, cancellation?: CancellationToken): Promise<void> {
    if (!Number.isFinite(ms) || ms < 0) {
      return Promise.reject(AppErrors.of('CONFIGURATION_ERROR', []));
    }
    if (cancellation !== undefined && cancellation.cancelled) {
      return Promise.reject(AppErrors.of('PROVISIONING_CANCELLED', []));
    }
    return new Promise<void>((resolve: () => void, reject: (error: Error) => void): void => {
      this.rejecter = reject;
      if (cancellation !== undefined) {
        cancellation.onCancel((): void => {
          this.cancel();
        });
      }
      this.timer = setTimeout((): void => {
        this.timer = undefined;
        this.rejecter = undefined;
        resolve();
      }, ms);
    });
  }

  cancel(): void {
    if (this.timer !== undefined) {
      clearTimeout(this.timer);
      this.timer = undefined;
    }
    const reject = this.rejecter;
    this.rejecter = undefined;
    if (reject !== undefined) {
      reject(AppErrors.of('PROVISIONING_CANCELLED', []));
    }
  }
}
