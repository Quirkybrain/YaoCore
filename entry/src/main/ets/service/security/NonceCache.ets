/*
 * YaoCore C-05 nonce cache.
 * Producer: agent:implementation-engineer | Task: T-07 / wp-016-security
 * Contract: DES-A §8.1.4, §8.3-2/3, §18.5
 *
 * App-side outbound duplicate protection only. The gateway-side replay cache
 * (structure/time/signature verified before insertion) belongs to C-20; this
 * class never authorizes a control request by itself.
 */
import { AppErrors } from '../../common/types/AppError';
import type { ClockPort } from '../../common/types/Ports';

export enum NonceDecision {
  NEW = 'NEW',
  DUPLICATE = 'DUPLICATE',
  CAPACITY_EXCEEDED = 'CAPACITY_EXCEEDED'
}

export class NonceCache {
  private readonly clock: ClockPort;
  private readonly ttlMs: number;
  private readonly capacity: number;
  private readonly entries: Map<string, number> = new Map<string, number>();

  constructor(clock: ClockPort, ttlMs: number = 300000, capacity: number = 2048) {
    if (!Number.isInteger(ttlMs) || ttlMs <= 0) {
      throw AppErrors.of('CONFIGURATION_ERROR');
    }
    if (!Number.isInteger(capacity) || capacity <= 0) {
      throw AppErrors.of('CONFIGURATION_ERROR');
    }
    this.clock = clock;
    this.ttlMs = ttlMs;
    this.capacity = capacity;
  }

  checkAndRemember(keyId: string, nonce: string, nowMs: number): NonceDecision {
    this.purge(nowMs);
    const key = NonceCache.keyOf(keyId, nonce);
    if (this.entries.has(key)) {
      return NonceDecision.DUPLICATE;
    }
    let capacityExceeded = false;
    while (this.entries.size >= this.capacity) {
      const oldest = this.entries.keys().next();
      if (oldest.done === true || oldest.value === undefined) {
        break;
      }
      this.entries.delete(oldest.value);
      capacityExceeded = true;
    }
    this.entries.set(key, nowMs);
    return capacityExceeded ? NonceDecision.CAPACITY_EXCEEDED : NonceDecision.NEW;
  }

  contains(keyId: string, nonce: string, nowMs: number): boolean {
    const key = NonceCache.keyOf(keyId, nonce);
    const createdAt = this.entries.get(key);
    if (createdAt === undefined) {
      return false;
    }
    return nowMs - createdAt < this.ttlMs;
  }

  size(): number {
    this.purge(this.clock.nowMs());
    return this.entries.size;
  }

  clear(): void {
    this.entries.clear();
  }

  private purge(nowMs: number): void {
    const expired: string[] = [];
    this.entries.forEach((createdAt: number, key: string) => {
      if (nowMs - createdAt >= this.ttlMs) {
        expired.push(key);
      }
    });
    for (let index = 0; index < expired.length; index++) {
      this.entries.delete(expired[index]);
    }
  }

  private static keyOf(keyId: string, nonce: string): string {
    return keyId + '\u0000' + nonce;
  }
}
