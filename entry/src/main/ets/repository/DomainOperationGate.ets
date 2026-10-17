/*
 * YaoCore C-08..C-11 domain operation gate.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
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
 * The gate itself is dependency-injected (no global singleton). The composition
 * root must share one instance across C-08..C-11. If no gate is supplied, a
 * repository creates its own instance; that still serializes its own work, and
 * RdbStore.transaction remains globally serialized by RdbTransactionRunner.
 */
export class DomainOperationGate {
  private chain: Promise<void> = Promise.resolve();

  /** Runs one top-level operation after all previously scheduled operations. */
  run<T>(operation: () => Promise<T>): Promise<T> {
    const run: Promise<T> = this.chain.then((): Promise<T> => {
      return operation();
    });
    this.chain = run.then((): void => {
    }, (): void => {
    });
    return run;
  }
}
