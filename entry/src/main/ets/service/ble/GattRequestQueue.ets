/*
 * YaoCore C-19 single-flight GATT request queue.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Contract: DES-A §16.2-3903-3911; BLE设计 §2-45; project-constraints PR-12
 *
 * Every Protocomm request is one write-with-response followed by one read on
 * the same characteristic. Requests must never interleave; a queue timeout is
 * reported as PROVISIONING_GATT_BUSY and the caller may retry once (50ms) only
 * when the operation never started.
 */
import { AppErrors } from '../../common/types/AppError';

export class GattRequestQueue {
  private readonly timeoutMs: number;
  private tail: Promise<void> = Promise.resolve();
  private epoch: number = 0;
  private released: boolean = false;

  constructor(timeoutMs: number) {
    if (!Number.isInteger(timeoutMs) || timeoutMs <= 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.timeoutMs = timeoutMs;
  }

  /**
   * Runs one serialized operation. The timeout covers both queue acquisition
   * and the operation itself. A timed-out operation still releases the lock so
   * later independent requests cannot deadlock; the caller must discard the
   * broken connection/session before reusing the link.
   */
  async run<T>(operation: () => Promise<T>): Promise<T> {
    if (this.released) {
      throw AppErrors.of('PROVISIONING_GATT_BUSY', []);
    }
    const epoch = this.epoch;
    const previous = this.tail;
    let release: () => void = () => {};
    this.tail = new Promise<void>((resolve: () => void) => {
      release = resolve;
    });
    try {
      return await this.execute<T>(async (): Promise<T> => {
        await previous;
        if (this.released || this.epoch !== epoch) {
          throw AppErrors.of('PROVISIONING_GATT_BUSY', []);
        }
        return await operation();
      });
    } finally {
      release();
    }
  }

  /** Drops queued work. Any waiter woken after reset fails with GATT_BUSY. */
  reset(): void {
    this.epoch++;
    this.tail = Promise.resolve();
  }

  /** Permanently releases the queue on provisioning teardown. */
  destroy(): void {
    this.released = true;
    this.epoch++;
    this.tail = Promise.resolve();
  }

  private async execute<T>(operation: () => Promise<T>): Promise<T> {
    let timer: number = 0;
    const timeout = new Promise<T>((_resolve: (value: T) => void, reject: (error: Error) => void) => {
      timer = setTimeout((): void => {
        reject(AppErrors.of('PROVISIONING_GATT_BUSY', []));
      }, this.timeoutMs);
    });
    try {
      return await Promise.race<T>([operation(), timeout]);
    } finally {
      if (timer !== 0) {
        clearTimeout(timer);
      }
    }
  }
}
