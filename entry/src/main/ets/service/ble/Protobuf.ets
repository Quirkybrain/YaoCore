/*
 * YaoCore C-19 strict protobuf wire codec.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Contract: DES-A §16.5; BLE设计 §5-118-147
 *
 * Minimal protobuf (proto3) writer/reader for the ESP-IDF 5.2 protocomm and
 * Wi-Fi provisioning messages. No generated code, no reflection, no @ohos
 * import. Negative int32 values are encoded as 10-byte two's-complement
 * varints without accumulating a 64-bit value into a JS Number (>2^53 loses
 * low bits); the reader keeps the low 32 bits and applies two's-complement.
 */
import { AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { Utf8 } from '../../common/utils/Utf8';

const VARINT_MAX_BYTES: number = 10;
const WIRE_VARINT: number = 0;
const WIRE_FIXED64: number = 1;
const WIRE_LENGTH: number = 2;
const WIRE_FIXED32: number = 5;

export class ProtobufTag {
  readonly fieldNumber: number;
  readonly wireType: number;

  constructor(fieldNumber: number, wireType: number) {
    this.fieldNumber = fieldNumber;
    this.wireType = wireType;
  }
}

function fail(field: string): never {
  throw AppErrors.of('PROTOCOL_INVALID_JSON', [new NameValue('field', 'protobuf:' + field)]);
}

/** Append-only proto3 writer. */
export class ProtobufWriter {
  private readonly data: number[] = [];

  varint(fieldNumber: number, value: number): void {
    if (!Number.isInteger(fieldNumber) || fieldNumber < 1 || fieldNumber > 536870911) {
      fail('field');
    }
    if (!Number.isInteger(value) || value < 0) {
      fail('varint');
    }
    this.writeTag(fieldNumber, WIRE_VARINT);
    this.writeUnsigned(value);
  }

  int32(fieldNumber: number, value: number): void {
    if (!Number.isInteger(fieldNumber) || fieldNumber < 1 || fieldNumber > 536870911) {
      fail('field');
    }
    if (!Number.isInteger(value) || value < -2147483648 || value > 2147483647) {
      fail('int32');
    }
    this.writeTag(fieldNumber, WIRE_VARINT);
    if (value >= 0) {
      this.writeUnsigned(value);
      return;
    }
    // Two's-complement 64-bit varint; the low 32 bits are the signed value.
    let low = value >>> 0;
    let high = 0xFFFFFFFF;
    for (let index = 0; index < 10; index++) {
      const byte = low & 0x7F;
      low = ((low >>> 7) | ((high & 0x7F) << 25)) >>> 0;
      high = high >>> 7;
      if (low === 0 && high === 0) {
        this.data.push(byte);
        return;
      }
      this.data.push(byte | 0x80);
    }
    fail('int32');
  }

  bool(fieldNumber: number, value: boolean): void {
    this.varint(fieldNumber, value ? 1 : 0);
  }

  bytes(fieldNumber: number, value: Uint8Array): void {
    if (!Number.isInteger(fieldNumber) || fieldNumber < 1 || fieldNumber > 536870911) {
      fail('field');
    }
    this.writeTag(fieldNumber, WIRE_LENGTH);
    this.writeUnsigned(value.length);
    for (let index = 0; index < value.length; index++) {
      this.data.push(value[index]);
    }
  }

  string(fieldNumber: number, value: string): void {
    this.bytes(fieldNumber, Utf8.encode(value));
  }

  message(fieldNumber: number, value: ProtobufWriter): void {
    this.bytes(fieldNumber, value.toBytes());
  }

  /** Raw length-delimited body (used for oneof payload fields). */
  rawVarint(value: number): void {
    if (!Number.isInteger(value) || value < 0) {
      fail('varint');
    }
    this.writeUnsigned(value);
  }

  toBytes(): Uint8Array {
    const result = new Uint8Array(this.data.length);
    for (let index = 0; index < this.data.length; index++) {
      result[index] = this.data[index];
    }
    return result;
  }

  /** Zeroizes the scratch buffer after the caller owns the returned bytes. */
  destroy(): void {
    for (let index = 0; index < this.data.length; index++) {
      this.data[index] = 0;
    }
    this.data.length = 0;
  }

  private writeTag(fieldNumber: number, wireType: number): void {
    this.writeUnsigned(fieldNumber * 8 + wireType);
  }

  private writeUnsigned(value: number): void {
    let remaining = value;
    while (remaining > 0x7F) {
      this.data.push((remaining & 0x7F) | 0x80);
      remaining = Math.floor(remaining / 128);
    }
    this.data.push(remaining & 0x7F);
  }
}

/** Bounds-checked proto3 reader. Unknown but well-formed fields can be skipped. */
export class ProtobufReader {
  private readonly data: Uint8Array;
  private offset: number = 0;

  constructor(data: Uint8Array) {
    this.data = data;
  }

  hasMore(): boolean {
    return this.offset < this.data.length;
  }

  position(): number {
    return this.offset;
  }

  readTag(): ProtobufTag {
    const raw = this.readUnsigned();
    if (raw === 0) {
      fail('tag');
    }
    const fieldNumber = Math.floor(raw / 8);
    const wireType = raw % 8;
    if (fieldNumber < 1 || fieldNumber > 536870911) {
      fail('field');
    }
    if (wireType !== WIRE_VARINT && wireType !== WIRE_FIXED64 &&
      wireType !== WIRE_LENGTH && wireType !== WIRE_FIXED32) {
      fail('wireType');
    }
    return new ProtobufTag(fieldNumber, wireType);
  }

  /** Reads a varint and returns the low 32 unsigned bits. */
  readUnsigned(): number {
    let low = 0;
    let shift = 0;
    for (let index = 0; index < VARINT_MAX_BYTES; index++) {
      if (this.offset >= this.data.length) {
        fail('truncated');
      }
      const byte = this.data[this.offset];
      this.offset += 1;
      if (shift < 32) {
        low = (low | ((byte & 0x7F) << shift)) >>> 0;
      }
      const continuation = (byte & 0x80) !== 0;
      if (!continuation) {
        if (index === 9 && (byte & 0x7E) !== 0) {
          fail('varint64');
        }
        return low >>> 0;
      }
      if (index === 9) {
        fail('varint');
      }
      shift += 7;
    }
    fail('varint');
  }

  readInt32(): number {
    const low = this.readUnsigned();
    return low >= 0x80000000 ? low - 0x100000000 : low;
  }

  readUint32(): number {
    return this.readUnsigned();
  }

  readBool(): boolean {
    const value = this.readUnsigned();
    if (value !== 0 && value !== 1) {
      fail('bool');
    }
    return value === 1;
  }

  /**
   * Reads a length prefix. Unlike `readUnsigned` (which keeps the low 32 bits
   * for int32 two's complement), a wire length must fit in 32 bits; a varint
   * whose value exceeds 0xFFFFFFFF is a malformed frame (F-11).
   */
  readLength(): number {
    let low = 0;
    let shift = 0;
    for (let index = 0; index < VARINT_MAX_BYTES; index++) {
      if (this.offset >= this.data.length) {
        fail('truncated');
      }
      const byte = this.data[this.offset];
      this.offset += 1;
      const payload = byte & 0x7F;
      if (shift < 28) {
        low = (low | (payload << shift)) >>> 0;
      } else if (shift === 28) {
        if ((payload & 0x70) !== 0) {
          fail('length');
        }
        low = (low | (payload << 28)) >>> 0;
      } else if (payload !== 0) {
        // Continuation bytes above bit 31 can only be zero; otherwise the
        // length cannot be represented as an unsigned 32-bit value.
        fail('length');
      }
      if ((byte & 0x80) === 0) {
        return low >>> 0;
      }
      shift += 7;
    }
    fail('length');
  }

  readBytes(): Uint8Array {
    const length = this.readLength();
    if (length > this.data.length - this.offset) {
      fail('length');
    }
    const result = new Uint8Array(length);
    for (let index = 0; index < length; index++) {
      result[index] = this.data[this.offset + index];
    }
    this.offset += length;
    return result;
  }

  readString(): string {
    return Utf8.decode(this.readBytes());
  }

  skip(tag: ProtobufTag): void {
    if (tag.wireType === WIRE_VARINT) {
      this.readUnsigned();
      return;
    }
    if (tag.wireType === WIRE_FIXED64) {
      this.skipFixed(8);
      return;
    }
    if (tag.wireType === WIRE_LENGTH) {
      this.readBytes();
      return;
    }
    if (tag.wireType === WIRE_FIXED32) {
      this.skipFixed(4);
      return;
    }
    fail('wireType');
  }

  assertEnd(): void {
    if (this.offset !== this.data.length) {
      fail('trailing');
    }
  }

  private skipFixed(length: number): void {
    if (length > this.data.length - this.offset) {
      fail('truncated');
    }
    this.offset += length;
  }
}
