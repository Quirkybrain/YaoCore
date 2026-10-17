/*
 * YaoCore C-01 strict JSON parser.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §3.4, §4.1.9
 *
 * Rejects duplicate keys, trailing content, non-finite numbers, invalid
 * escapes, lone surrogates, and input beyond JsonLimits. Protocol input must
 * never be parsed with a bare JSON.parse followed by a cast.
 */
import { AppErrors } from '../types/AppError';
import { JsonNode, JsonKind, NameValueNode } from '../types/JsonNode';
import { Utf8 } from './Utf8';

export class JsonLimits {
  readonly maxBytes: number;
  readonly maxDepth: number;
  readonly maxStringLength: number;

  constructor(maxBytes: number = 65536, maxDepth: number = 16, maxStringLength: number = 8192) {
    this.maxBytes = maxBytes;
    this.maxDepth = maxDepth;
    this.maxStringLength = maxStringLength;
  }

  static defaults(): JsonLimits {
    return new JsonLimits(65536, 16, 8192);
  }
}

class JsonReader {
  private readonly text: string;
  private readonly limits: JsonLimits;
  private index: number = 0;
  private depth: number = 0;

  constructor(text: string, limits: JsonLimits) {
    this.text = text;
    this.limits = limits;
  }

  parse(): JsonNode {
    this.skipWhitespace();
    const value = this.parseValue();
    this.skipWhitespace();
    if (this.index !== this.text.length) {
      throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
    }
    return value;
  }

  private parseValue(): JsonNode {
    if (this.index >= this.text.length) {
      throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
    }
    const code = this.text.charCodeAt(this.index);
    if (code === 0x7B) {
      return this.parseObject();
    }
    if (code === 0x5B) {
      return this.parseArray();
    }
    if (code === 0x22) {
      return JsonNode.string(this.parseString());
    }
    if (code === 0x74) {
      return this.parseLiteral('true', JsonNode.boolean(true));
    }
    if (code === 0x66) {
      return this.parseLiteral('false', JsonNode.boolean(false));
    }
    if (code === 0x6E) {
      return this.parseLiteral('null', JsonNode.nullNode());
    }
    if (code === 0x2D || (code >= 0x30 && code <= 0x39)) {
      return JsonNode.number(this.parseNumber());
    }
    throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
  }

  private parseObject(): JsonNode {
    this.depth += 1;
    if (this.depth > this.limits.maxDepth) {
      throw AppErrors.protocol('PROTOCOL_BODY_TOO_LARGE', 'json');
    }
    this.index += 1;
    this.skipWhitespace();
    const entries: NameValueNode[] = [];
    const seen = new Map<string, boolean>();
    if (this.index < this.text.length && this.text.charCodeAt(this.index) === 0x7D) {
      this.index += 1;
      this.depth -= 1;
      return JsonNode.object(entries);
    }
    while (true) {
      this.skipWhitespace();
      if (this.index >= this.text.length || this.text.charCodeAt(this.index) !== 0x22) {
        throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
      }
      const name = this.parseString();
      if (seen.has(name)) {
        throw AppErrors.protocol('PROTOCOL_DUPLICATE_KEY', name);
      }
      seen.set(name, true);
      this.skipWhitespace();
      if (this.index >= this.text.length || this.text.charCodeAt(this.index) !== 0x3A) {
        throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
      }
      this.index += 1;
      this.skipWhitespace();
      entries.push(new NameValueNode(name, this.parseValue()));
      this.skipWhitespace();
      if (this.index >= this.text.length) {
        throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
      }
      const next = this.text.charCodeAt(this.index);
      if (next === 0x2C) {
        this.index += 1;
        continue;
      }
      if (next === 0x7D) {
        this.index += 1;
        this.depth -= 1;
        return JsonNode.object(entries);
      }
      throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
    }
  }

  private parseArray(): JsonNode {
    this.depth += 1;
    if (this.depth > this.limits.maxDepth) {
      throw AppErrors.protocol('PROTOCOL_BODY_TOO_LARGE', 'json');
    }
    this.index += 1;
    this.skipWhitespace();
    const items: JsonNode[] = [];
    if (this.index < this.text.length && this.text.charCodeAt(this.index) === 0x5D) {
      this.index += 1;
      this.depth -= 1;
      return JsonNode.array(items);
    }
    while (true) {
      this.skipWhitespace();
      items.push(this.parseValue());
      this.skipWhitespace();
      if (this.index >= this.text.length) {
        throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
      }
      const next = this.text.charCodeAt(this.index);
      if (next === 0x2C) {
        this.index += 1;
        continue;
      }
      if (next === 0x5D) {
        this.index += 1;
        this.depth -= 1;
        return JsonNode.array(items);
      }
      throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
    }
  }

  private parseString(): string {
    this.index += 1;
    let result = '';
    let decodedLength = 0;
    while (this.index < this.text.length) {
      const code = this.text.charCodeAt(this.index);
      if (code === 0x22) {
        this.index += 1;
        if (decodedLength > this.limits.maxStringLength) {
          throw AppErrors.protocol('PROTOCOL_BODY_TOO_LARGE', 'json');
        }
        return result;
      }
      if (code === 0x5C) {
        this.index += 1;
        if (this.index >= this.text.length) {
          throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
        }
        const escape = this.text.charCodeAt(this.index);
        if (escape === 0x22) {
          result += '"';
        } else if (escape === 0x5C) {
          result += '\\';
        } else if (escape === 0x2F) {
          result += '/';
        } else if (escape === 0x62) {
          result += '\b';
        } else if (escape === 0x66) {
          result += '\f';
        } else if (escape === 0x6E) {
          result += '\n';
        } else if (escape === 0x72) {
          result += '\r';
        } else if (escape === 0x74) {
          result += '\t';
        } else if (escape === 0x75) {
          if (this.index + 4 >= this.text.length) {
            throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
          }
          const unit = this.parseHex4(this.index + 1);
          this.index += 4;
          if (unit >= 0xD800 && unit <= 0xDBFF) {
            if (this.index + 6 >= this.text.length ||
              this.text.charCodeAt(this.index + 1) !== 0x5C ||
              this.text.charCodeAt(this.index + 2) !== 0x75) {
              throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
            }
            const low = this.parseHex4(this.index + 3);
            if (low < 0xDC00 || low > 0xDFFF) {
              throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
            }
            this.index += 6;
            result += String.fromCharCode(unit);
            result += String.fromCharCode(low);
            decodedLength += 2;
          } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
            throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
          } else {
            result += String.fromCharCode(unit);
            decodedLength += 1;
          }
          this.index += 1;
          continue;
        } else {
          throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
        }
        decodedLength += 1;
        this.index += 1;
        continue;
      }
      if (code < 0x20) {
        throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
      }
      if (code >= 0xD800 && code <= 0xDBFF) {
        if (this.index + 1 >= this.text.length) {
          throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
        }
        const next = this.text.charCodeAt(this.index + 1);
        if (next < 0xDC00 || next > 0xDFFF) {
          throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
        }
        result += this.text.substring(this.index, this.index + 2);
        decodedLength += 2;
        this.index += 2;
        continue;
      }
      if (code >= 0xDC00 && code <= 0xDFFF) {
        throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
      }
      result += this.text.charAt(this.index);
      decodedLength += 1;
      this.index += 1;
    }
    throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
  }

  private parseNumber(): number {
    const start = this.index;
    if (this.text.charCodeAt(this.index) === 0x2D) {
      this.index += 1;
    }
    if (this.index >= this.text.length) {
      throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
    }
    const first = this.text.charCodeAt(this.index);
    if (first === 0x30) {
      this.index += 1;
    } else if (first >= 0x31 && first <= 0x39) {
      this.index += 1;
      while (this.index < this.text.length && this.isDigit(this.text.charCodeAt(this.index))) {
        this.index += 1;
      }
    } else {
      throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
    }
    if (this.index < this.text.length && this.text.charCodeAt(this.index) === 0x2E) {
      this.index += 1;
      if (this.index >= this.text.length || !this.isDigit(this.text.charCodeAt(this.index))) {
        throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
      }
      while (this.index < this.text.length && this.isDigit(this.text.charCodeAt(this.index))) {
        this.index += 1;
      }
    }
    if (this.index < this.text.length) {
      const exponent = this.text.charCodeAt(this.index);
      if (exponent === 0x65 || exponent === 0x45) {
        this.index += 1;
        if (this.index < this.text.length) {
          const sign = this.text.charCodeAt(this.index);
          if (sign === 0x2B || sign === 0x2D) {
            this.index += 1;
          }
        }
        if (this.index >= this.text.length || !this.isDigit(this.text.charCodeAt(this.index))) {
          throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
        }
        while (this.index < this.text.length && this.isDigit(this.text.charCodeAt(this.index))) {
          this.index += 1;
        }
      }
    }
    const value = Number(this.text.substring(start, this.index));
    if (!Number.isFinite(value)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
    }
    return value;
  }

  private parseLiteral(literal: string, node: JsonNode): JsonNode {
    if (this.text.substring(this.index, this.index + literal.length) !== literal) {
      throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
    }
    this.index += literal.length;
    if (this.index < this.text.length) {
      const next = this.text.charCodeAt(this.index);
      if (next !== 0x2C && next !== 0x7D && next !== 0x5D && next !== 0x20 && next !== 0x09 &&
        next !== 0x0A && next !== 0x0D) {
        throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
      }
    }
    return node;
  }

  private parseHex4(start: number): number {
    let value = 0;
    for (let offset = 0; offset < 4; offset++) {
      const digit = JsonReader.hexDigit(this.text.charCodeAt(start + offset));
      if (digit < 0) {
        throw AppErrors.protocol('PROTOCOL_INVALID_JSON', 'json');
      }
      value = (value << 4) | digit;
    }
    return value;
  }

  private skipWhitespace(): void {
    while (this.index < this.text.length) {
      const code = this.text.charCodeAt(this.index);
      if (code !== 0x20 && code !== 0x09 && code !== 0x0A && code !== 0x0D) {
        return;
      }
      this.index += 1;
    }
  }

  private isDigit(code: number): boolean {
    return code >= 0x30 && code <= 0x39;
  }

  private static hexDigit(code: number): number {
    if (code >= 0x30 && code <= 0x39) {
      return code - 0x30;
    }
    if (code >= 0x41 && code <= 0x46) {
      return code - 0x41 + 10;
    }
    if (code >= 0x61 && code <= 0x66) {
      return code - 0x61 + 10;
    }
    return -1;
  }
}

export class JsonParser {
  static parse(text: string, limits?: JsonLimits): JsonNode {
    const effective = limits === undefined ? JsonLimits.defaults() : limits;
    const byteLength = Utf8.encode(text).length;
    if (byteLength > effective.maxBytes) {
      throw AppErrors.protocol('PROTOCOL_BODY_TOO_LARGE', 'json');
    }
    return new JsonReader(text, effective).parse();
  }
}
