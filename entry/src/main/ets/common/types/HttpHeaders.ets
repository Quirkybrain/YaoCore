/*
 * YaoCore C-01 HTTP header container.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §4.1.8
 *
 * Header names are looked up case-insensitively. `from` keeps every entry in
 * input order; `get` returns the last matching value.
 */
import { NameValue } from './NameValue';
import { AppErrors } from './AppError';

export class HttpHeaders {
  private readonly entriesList: ReadonlyArray<NameValue>;
  private readonly lookup: Map<string, string>;

  private constructor(entries: ReadonlyArray<NameValue>, lookup: Map<string, string>) {
    this.entriesList = entries;
    this.lookup = lookup;
  }

  static from(entries: ReadonlyArray<NameValue>): HttpHeaders {
    const lookup = new Map<string, string>();
    for (let index = 0; index < entries.length; index++) {
      lookup.set(entries[index].name.toLowerCase(), entries[index].value);
    }
    return new HttpHeaders(entries, lookup);
  }

  static fromMap(map: Map<string, string>): HttpHeaders {
    const entries: NameValue[] = [];
    map.forEach((value: string, key: string) => {
      entries.push(new NameValue(key, value));
    });
    return HttpHeaders.from(entries);
  }

  get(name: string): string | undefined {
    return this.lookup.get(name.toLowerCase());
  }

  require(name: string): string {
    const value = this.get(name);
    if (value === undefined) {
      throw AppErrors.protocol('PROTOCOL_MISSING_FIELD', name);
    }
    return value;
  }

  has(name: string): boolean {
    return this.lookup.has(name.toLowerCase());
  }

  entries(): ReadonlyArray<NameValue> {
    return this.entriesList;
  }
}
