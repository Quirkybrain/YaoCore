/*
 * YaoCore C-01 compact JSON canonicalizer.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §3.4, §4.1.9
 *
 * Compact, no whitespace. sortKeys=true emits lexicographic key order; array
 * order is always preserved.
 */
import { JsonNode, JsonKind } from '../types/JsonNode';
import { JsonAtom } from './JsonAtom';

export class JsonCanonicalizer {
  static stringify(node: JsonNode, sortKeys: boolean): string {
    if (node.kind === JsonKind.NULL) {
      return 'null';
    }
    if (node.kind === JsonKind.BOOLEAN) {
      return node.booleanValue ? 'true' : 'false';
    }
    if (node.kind === JsonKind.NUMBER) {
      return JsonAtom.normalizeNumber(node.numberValue);
    }
    if (node.kind === JsonKind.STRING) {
      return JsonAtom.normalizeString(node.stringValue);
    }
    if (node.kind === JsonKind.ARRAY) {
      const items: string[] = [];
      for (let index = 0; index < node.arrayValue.length; index++) {
        items.push(JsonCanonicalizer.stringify(node.arrayValue[index], sortKeys));
      }
      return '[' + items.join(',') + ']';
    }
    const keys: string[] = [];
    const sourceKeys = node.keys();
    for (let index = 0; index < sourceKeys.length; index++) {
      keys.push(sourceKeys[index]);
    }
    if (sortKeys) {
      keys.sort();
    }
    const parts: string[] = [];
    for (let index = 0; index < keys.length; index++) {
      const key = keys[index];
      const child = node.get(key);
      if (child === undefined) {
        continue;
      }
      parts.push(JsonAtom.normalizeString(key) + ':' + JsonCanonicalizer.stringify(child, sortKeys));
    }
    return '{' + parts.join(',') + '}';
  }

  static stringifySorted(node: JsonNode): string {
    return JsonCanonicalizer.stringify(node, true);
  }
}
