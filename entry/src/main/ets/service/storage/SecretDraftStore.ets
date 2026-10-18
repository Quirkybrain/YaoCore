/*
 * YaoCore C-06 SecretDraftStore.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Contract: DES-A §9.1.5, §9.3 invariant 5, §22.3
 *
 * Memory-only one-shot drafts. put() copies the caller's SecureBytes, take()
 * returns a fresh SecureBytes and removes/zeroizes the table entry, clearAll()
 * zeroizes every draft (cancel/failure/background hook).
 *
 * Draft ids are opaque local handles, not credentials: the contract makes put()
 * synchronous while RandomPort is asynchronous. When the injected RandomPort
 * also exposes nextBytesSync() (test doubles may), it is mixed into the id;
 * otherwise the id is clock+counter based. The table itself is unreachable
 * outside this process and every entry expires after 10 minutes by default.
 */
import type { ClockPort } from '../../common/types/Ports';
import type { RandomPort } from '../../contracts/Ports';
import { SecureBytes } from '../../common/types/SecureBytes';
import { BytesUtil } from '../../common/utils/BytesUtil';
import { AppErrors } from '../../common/types/AppError';
import type { SecretDraftPort } from '../../contracts/SecretDraftPort';

interface SyncRandomLike extends RandomPort {
  nextBytesSync(length: number): Uint8Array;
}

class DraftEntry {
  readonly bytes: Uint8Array;
  readonly expiresAtMs: number;

  constructor(bytes: Uint8Array, expiresAtMs: number) {
    this.bytes = bytes;
    this.expiresAtMs = expiresAtMs;
  }
}

export class SecretDraftStore implements SecretDraftPort {
  static readonly DEFAULT_TTL_MS: number = 600000;

  private readonly random: RandomPort;
  private readonly clock: ClockPort;
  private readonly drafts: Map<string, DraftEntry> = new Map<string, DraftEntry>();
  private counter: number = 0;

  constructor(random: RandomPort, clock: ClockPort) {
    this.random = random;
    this.clock = clock;
  }

  put(secret: SecureBytes, ttlMs: number = SecretDraftStore.DEFAULT_TTL_MS): string {
    if (!Number.isFinite(ttlMs) || ttlMs <= 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    const copy = secret.withView((view: Uint8Array): Uint8Array => BytesUtil.copyOf(view));
    const draftId = this.newDraftId();
    this.drafts.set(draftId, new DraftEntry(copy, this.clock.nowMs() + ttlMs));
    return draftId;
  }

  take(draftId: string): SecureBytes {
    const entry = this.drafts.get(draftId);
    if (entry === undefined) {
      throw AppErrors.of('PROVISIONING_CREDENTIAL_MISSING', []);
    }
    this.drafts.delete(draftId);
    if (this.clock.nowMs() >= entry.expiresAtMs) {
      BytesUtil.zeroize(entry.bytes);
      throw AppErrors.of('PROVISIONING_SECRET_DRAFT_EXPIRED', []);
    }
    const result = SecureBytes.from(entry.bytes);
    BytesUtil.zeroize(entry.bytes);
    return result;
  }

  destroy(draftId: string): void {
    const entry = this.drafts.get(draftId);
    if (entry === undefined) {
      return;
    }
    BytesUtil.zeroize(entry.bytes);
    this.drafts.delete(draftId);
  }

  clearAll(): void {
    this.drafts.forEach((entry: DraftEntry): void => {
      BytesUtil.zeroize(entry.bytes);
    });
    this.drafts.clear();
  }

  size(): number {
    this.purgeExpired();
    return this.drafts.size;
  }

  private purgeExpired(): void {
    const nowMs = this.clock.nowMs();
    const expired: string[] = [];
    this.drafts.forEach((entry: DraftEntry, draftId: string): void => {
      if (nowMs >= entry.expiresAtMs) {
        expired.push(draftId);
      }
    });
    for (let index = 0; index < expired.length; index++) {
      this.destroy(expired[index]);
    }
  }

  private newDraftId(): string {
    this.counter++;
    let entropy = '';
    const candidate = this.random as SyncRandomLike;
    if (typeof candidate.nextBytesSync === 'function') {
      entropy = BytesUtil.hexLower(candidate.nextBytesSync(8));
    } else {
      entropy = String(this.counter) + String(this.clock.nowMs().toString(36));
    }
    return 'draft-' + String(this.clock.nowMs().toString(36)) + '-' + entropy +
      '-' + String(this.counter);
  }
}
