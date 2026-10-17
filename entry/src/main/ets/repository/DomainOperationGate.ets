/*
 * YaoCore C-08..C-11 domain operation gate.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain; wp-026-fix-t09
 * Contract: O-1 constraint carried from CQG-T08 (DES-B §2.8)
 *
 * O-1 rule enforced here:
 * - Ordinary execute/query work and top-level transactions are single-flight
 *   per injected gate instance. Repositories and services that share a gate
 *   never interleave an ordinary statement with an open transaction.
 * - Transactions are NEVER nested. Methods that accept an RdbTransaction are
 *   transaction-context methods: they must be called only from inside the one
 *   top-level `RdbStore.transaction` callback and must not call `run()`.
 * - Cross-repository writes (room deletion, device removal + scene cleanup)
 *   are serialized by this gate and executed in a single top-level transaction
 *   through injected ports.
 *
 * Reentrancy (wp-026 R-04):
 * - A `run()` invoked synchronously from inside an executing operation would
 *   chain behind itself and deadlock. Such calls are rejected immediately with
 *   CONFIGURATION_ERROR (field=nestedGateOperation).
 * - A reentrant call that yields first cannot be told apart from an ordinary
 *   concurrent caller without async-context support. The gate therefore also
 *   guards every queued operation with a bounded wait (default 2000 ms,
 *   constructor-injectable; D-023). If the queue cannot start an operation in
 *   that window, the caller receives CONFIGURATION_ERROR
 *   (field=nestedOperationOrQueueTimeout) and the queued body is never
 *   executed. This converts an O-1 deadlock into a deterministic failure
 *   instead of an unbounded hang.
 *
 * Bounded-wait semantics (D-023):
 * - The budget is a GLOBAL queue-wait bound, not a nested-call detector: it
 *   also applies to legitimate independent callers that queue behind a slow
 *   operation.
 * - Valid domain operations are expected to complete well below the default
 *   2000 ms. A caller that knows its operation may run longer must serialize
 *   at the call site (await the previous operation) instead of relying on the
 *   gate queue; the composition root may inject a larger budget through
 *   `new DomainOperationGate(ms)`.
 * - A positive value is the budget; a value <= 0 disables the bounded wait.
 *   Disabling it is not recommended because an asynchronous reentrant call
 *   would then hang until the outer operation settles.
 *
 * The gate itself is dependency-injected (no global singleton). The composition
 * root must share one instance across C-08..C-11. If no gate is supplied, a
 * repository creates its own instance; that still serializes its own work, and
 * RdbStore.transaction remains globally serialized by RdbTransactionRunner.
 */
import { AppErrors } from '../common/types/AppError';
import { NameValue } from '../common/types/NameValue';

export class DomainOperationGate {
  private chain: Promise<void> = Promise.resolve();
  private dispatching: boolean = false;
  private readonly waitTimeoutMs: number;

  constructor(waitTimeoutMs: number = 2000) {
    this.waitTimeoutMs = waitTimeoutMs > 0 ? waitTimeoutMs : 0;
  }

  /** Runs one top-level operation after all previously scheduled operations. */
  run<T>(operation: () => Promise<T>): Promise<T> {
    if (this.dispatching) {
      return Promise.reject(DomainOperationGate.nestedError('nestedGateOperation'));
    }
    let cancelled: boolean = false;
    let started: boolean = false;
    let settled: boolean = false;
    let timer: number | undefined = undefined;
    const start: Promise<T> = this.chain.then((): Promise<T> => {
      if (cancelled) {
        return Promise.reject(DomainOperationGate.nestedError(
          'nestedOperationOrQueueTimeout'));
      }
      started = true;
      return this.dispatch(operation);
    });
    this.chain = start.then((): void => {
    }, (): void => {
    });
    if (this.waitTimeoutMs <= 0) {
      return start;
    }
    return new Promise<T>((resolve: (value: T) => void, reject: (reason: Error) => void): void => {
      timer = setTimeout((): void => {
        if (started || settled) {
          return;
        }
        cancelled = true;
        settled = true;
        reject(DomainOperationGate.nestedError('nestedOperationOrQueueTimeout'));
      }, this.waitTimeoutMs);
      start.then((value: T): void => {
        settled = true;
        if (timer !== undefined) {
          clearTimeout(timer);
        }
        resolve(value);
      }, (error: Error): void => {
        settled = true;
        if (timer !== undefined) {
          clearTimeout(timer);
        }
        reject(error);
      });
    });
  }

  private dispatch<T>(operation: () => Promise<T>): Promise<T> {
    this.dispatching = true;
    try {
      return operation();
    } finally {
      this.dispatching = false;
    }
  }

  private static nestedError(field: string): Error {
    return AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', field)]);
  }
}
