/*
 * YaoCore C-19 single-flight GATT request queue.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Contract: DES-A §16.2-3903-3911; BLE设计 §2-45; project-constraints PR-12
 *
 * Every Protocomm request is one write-with-response followed by one read on
 * the same characteristic. Requests must never interleave; a queue timeout is
 * reported as PROVISIONING_GATT_BUSY. A timed-out operation may still be in
 * flight below this layer, so a timeout permanently breaks the queue: queued
 * and later runs fail with GATT_BUSY instead of starting concurrently. The
 * caller tears the link/session down and reconnects from Security1 step0.
 */
import { AppError, AppErrors } from '../../common/types/AppError';

export class GattRequestQueue {
  private readonly timeoutMs: number;
  private tail: Promise<void> = Promise.resolve();
  private epoch: number = 0;
  private released: boolean = false;
  private broken: boolean = false;

  constructor(timeoutMs: number) {
    if (!Number.isInteger(timeoutMs) || timeoutMs <= 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.timeoutMs = timeoutMs;
  }

  /**
   * Runs one serialized operation. The timeout covers both queue acquisition
   * and the operation itself. A timeout marks the queue broken: the timed-out
   * operation may still be running below, so every queued/later request fails
   * with GATT_BUSY rather than starting a second concurrent operation.
   */
  async run<T>(operation: () => Promise<T>): Promise<T> {
    if (this.released || this.broken) {
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
        if (this.released || this.broken || this.epoch !== epoch) {
          throw AppErrors.of('PROVISIONING_GATT_BUSY', []);
        }
        return await operation();
      });
    } finally {
      // Always release the gate so waiters observe `broken` and fail fast
      // instead of hanging forever on a dead link.
      release();
    }
  }

  /**
   * Drops queued work. Any waiter woken after reset fails with GATT_BUSY.
   * A broken queue stays broken: reset only starts a new epoch, it does not
   * resurrect a link whose last operation timed out; use a new queue after
   * reconnecting.
   */
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
    const timeout = new Promise<T>((_resolve: (value: T) => void, reject: (error: AppError) => void) => {
      timer = setTimeout((): void => {
        this.broken = true;
        reject(AppErrors.of('PROVISIONING_GATT_BUSY', []));
      }, this.timeoutMs);
    });
    const running = operation();
    try {
      return await Promise.race<T>([running, timeout]);
    } finally {
      if (timer !== 0) {
        clearTimeout(timer);
      }
      // The race already handles the late result; keep an explicit sink so a
      // late rejection cannot escape as unhandled after the caller failed.
      running.then((): void => {}, (): void => {});
    }
  }
}
