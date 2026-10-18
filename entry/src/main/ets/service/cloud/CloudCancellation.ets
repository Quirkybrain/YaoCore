/*
 * YaoCore C-15 internal/external cancellation bridge.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §8.1.7 (stopPolling/cancellation)
 */
import { AppErrors } from '../../common/types/AppError';
import type { CancellationToken } from '../../common/types/CancellationToken';

export class CloudCancellation implements CancellationToken {
  private cancelledFlag: boolean = false;
  private readonly listeners: Array<() => void> = [];

  constructor(parent?: CancellationToken) {
    if (parent !== undefined) {
      if (parent.cancelled) {
        this.cancelledFlag = true;
      } else {
        parent.onCancel((): void => {
          this.cancel();
        });
      }
    }
  }

  get cancelled(): boolean {
    return this.cancelledFlag;
  }

  onCancel(listener: () => void): void {
    if (this.cancelledFlag) {
      listener();
      return;
    }
    this.listeners.push(listener);
  }

  throwIfCancelled(): void {
    if (this.cancelledFlag) {
      throw AppErrors.of('PROVISIONING_CANCELLED', []);
    }
  }

  cancel(): void {
    if (this.cancelledFlag) {
      return;
    }
    this.cancelledFlag = true;
    const pending = this.listeners.slice();
    this.listeners.length = 0;
    for (let index = 0; index < pending.length; index++) {
      try {
        pending[index]();
      } catch (error) {
        // Cancellation listeners must not break other listeners.
      }
    }
  }
}
