/*
 * YaoCore C-01 strict JSON node model.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §3.4
 */
import { AppErrors } from './AppError';

export enum JsonKind {
  NULL = 'NULL',
  BOOLEAN = 'BOOLEAN',
  NUMBER = 'NUMBER',
  STRING = 'STRING',
  OBJECT = 'OBJECT',
  ARRAY = 'ARRAY'
}

export class NameValueNode {
  readonly name: string;
  readonly value: JsonNode;

  constructor(name: string, value: JsonNode) {
    this.name = name;
    this.value = value;
  }
}

export class JsonNode {
  readonly kind: JsonKind;
  readonly booleanValue: boolean;
  readonly numberValue: number;
  readonly stringValue: string;
  readonly objectValue: Map<string, JsonNode>;
  readonly arrayValue: ReadonlyArray<JsonNode>;

  private constructor(kind: JsonKind, booleanValue: boolean, numberValue: number, stringValue: string,
    objectValue: Map<string, JsonNode>, arrayValue: ReadonlyArray<JsonNode>) {
    this.kind = kind;
    this.booleanValue = booleanValue;
    this.numberValue = numberValue;
    this.stringValue = stringValue;
    this.objectValue = objectValue;
    this.arrayValue = arrayValue;
  }

  static object(entries: ReadonlyArray<NameValueNode>): JsonNode {
    const map = new Map<string, JsonNode>();
    for (let index = 0; index < entries.length; index++) {
      map.set(entries[index].name, entries[index].value);
    }
    return new JsonNode(JsonKind.OBJECT, false, 0, '', map, []);
  }

  static array(items: ReadonlyArray<JsonNode>): JsonNode {
    return new JsonNode(JsonKind.ARRAY, false, 0, '', new Map<string, JsonNode>(), items);
  }

  static string(value: string): JsonNode {
    return new JsonNode(JsonKind.STRING, false, 0, value, new Map<string, JsonNode>(), []);
  }

  static number(value: number): JsonNode {
    return new JsonNode(JsonKind.NUMBER, false, value, '', new Map<string, JsonNode>(), []);
  }

  static boolean(value: boolean): JsonNode {
    return new JsonNode(JsonKind.BOOLEAN, value, 0, '', new Map<string, JsonNode>(), []);
  }

  static nullNode(): JsonNode {
    return new JsonNode(JsonKind.NULL, false, 0, '', new Map<string, JsonNode>(), []);
  }

  has(key: string): boolean {
    return this.kind === JsonKind.OBJECT && this.objectValue.has(key);
  }

  get(key: string): JsonNode | undefined {
    if (this.kind !== JsonKind.OBJECT) {
      return undefined;
    }
    return this.objectValue.get(key);
  }

  require(key: string): JsonNode {
    if (this.kind !== JsonKind.OBJECT) {
      throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'object');
    }
    const value = this.objectValue.get(key);
    if (value === undefined) {
      throw AppErrors.protocol('PROTOCOL_MISSING_FIELD', key);
    }
    return value;
  }

  keys(): ReadonlyArray<string> {
    const result: string[] = [];
    this.objectValue.forEach((_value: JsonNode, key: string) => {
      result.push(key);
    });
    return result;
  }
}
