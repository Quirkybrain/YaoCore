/*
 * YaoCore C-04 secure RandomPort adapter.
 * Producer: agent:implementation-engineer | Task: T-07 / wp-016-security
 * Contract: DES-A §3.3, §3.7, §7.1.2
 */
import type { RandomPort } from '../../common/types/Ports';
import type { CryptoPort } from './CryptoPort';

/** RandomPort backed by CryptoPort.randomBytes (cryptoFramework Random). */
export class CryptoRandomSource implements RandomPort {
  private readonly crypto: CryptoPort;

  constructor(crypto: CryptoPort) {
    this.crypto = crypto;
  }

  nextBytes(length: number): Promise<Uint8Array> {
    return this.crypto.randomBytes(length);
  }
}
