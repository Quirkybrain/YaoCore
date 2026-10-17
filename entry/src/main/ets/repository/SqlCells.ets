/*
 * YaoCore C-08..C-11 typed RDB cell helpers.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §2.7, §3.1.2, §4.1.2, §5.1.3, §6.1.3
 *
 * All persisted scalar decoding is strict: a missing/wrong-typed cell is a
 * storage failure (STORAGE_RDB_ERROR), never a silent default. JSON string
 * arrays are the DES-B storage form for room grants/gateway ids.
 */
import { AppErrors } from '../common/types/AppError';
import { JsonKind } from '../common/types/JsonNode';
import type { JsonNode } from '../common/types/JsonNode';
import { JsonParser, JsonLimits } from '../common/utils/JsonParser';
import { JsonAtom } from '../common/utils/JsonAtom';
import type { RdbRow } from '../service/storage/RdbStore';

export class SqlCells {
  static requiredString(row: RdbRow, column: string): string {
    const value = row.get(column);
    if (typeof value !== 'string') {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    return value;
  }

  static optionalString(row: RdbRow, column: string): string | undefined {
    const value = row.get(column);
    if (value === null || value === undefined) {
      return undefined;
    }
    if (typeof value !== 'string') {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    return value;
  }

  static requiredNumber(row: RdbRow, column: string): number {
    const value = row.get(column);
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    return value;
  }

  static optionalNumber(row: RdbRow, column: string): number | undefined {
    const value = row.get(column);
    if (value === null || value === undefined) {
      return undefined;
    }
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    return value;
  }

  static requiredBoolean(row: RdbRow, column: string): boolean {
    return SqlCells.requiredNumber(row, column) !== 0;
  }

  static columnExists(row: RdbRow, column: string): boolean {
    return row.has(column);
  }
}

export class SqlJson {
  static stringArray(values: ReadonlyArray<string>): string {
    let text = '[';
    for (let index = 0; index < values.length; index++) {
      if (index > 0) {
        text += ',';
      }
      text += JsonAtom.normalizeString(values[index]);
    }
    return text + ']';
  }

  static parseStringArray(text: string): ReadonlyArray<string> {
    let node: JsonNode;
    try {
      node = JsonParser.parse(text, new JsonLimits(8192, 4, 512));
    } catch (error) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    if (node.kind !== JsonKind.ARRAY) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    const values: string[] = [];
    for (let index = 0; index < node.arrayValue.length; index++) {
      const item = node.arrayValue[index];
      if (item.kind !== JsonKind.STRING) {
        throw AppErrors.of('STORAGE_RDB_ERROR', []);
      }
      values.push(item.stringValue);
    }
    return values;
  }
}
