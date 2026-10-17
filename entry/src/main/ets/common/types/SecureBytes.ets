/*
 * YaoCore C-01 secure byte buffer.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §3.5
 *
 * Secrets are held as bytes and zeroized on destroy. toHex is for protocol and
 * tests only; callers must keep the resulting string for the shortest period.
 */
import { AppErrors } from './AppError';
import { BytesUtil } from '../utils/BytesUtil';

export class SecureBytes {
  private readonly bytes: Uint8Array;
  private destroyed: boolean = false;

  private constructor(bytes: Uint8Array) {
    this.bytes = bytes;
  }

  static from(source: Uint8Array): SecureBytes {
    return new SecureBytes(BytesUtil.copyOf(source));
  }

  static fromHex(hex: string): SecureBytes {
    return new SecureBytes(BytesUtil.hexToBytes(hex));
  }

  get length(): number {
    return this.bytes.length;
  }

  withView<T>(fn: (view: Uint8Array) => T): T {
    if (this.destroyed) {
      throw AppErrors.of('SECRET_DESTROYED', []);
    }
    return fn(this.bytes);
  }

  toHex(): string {
    if (this.destroyed) {
      throw AppErrors.of('SECRET_DESTROYED', []);
    }
    return BytesUtil.hexLower(this.bytes);
  }

  destroy(): void {
    if (!this.destroyed) {
      BytesUtil.zeroize(this.bytes);
      this.destroyed = true;
    }
  }
}
