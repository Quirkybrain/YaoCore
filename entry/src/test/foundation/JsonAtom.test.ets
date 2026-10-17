/*
 * YaoCore Hypium host suite: C-01 JsonAtom.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Traceability: DES-A §4.1.9, §18.1.
 */
import { describe, expect, it } from '@ohos/hypium';
import { JsonAtom } from '../../main/ets/common/utils/JsonAtom';

export function JsonAtomSuite(): void {
  describe('C01 JsonAtom', () => {
    it('C01_JsonAtom_encodesCommandValueKinds', 0, () => {
      expect(JsonAtom.encode(undefined)).assertEqual('');
      expect(JsonAtom.encode('制冷')).assertEqual('"制冷"');
      expect(JsonAtom.encode(true)).assertEqual('true');
      expect(JsonAtom.encode(false)).assertEqual('false');
      expect(JsonAtom.encode(24)).assertEqual('24');
      expect(JsonAtom.encode(24.5)).assertEqual('24.5');
    });

    it('C01_JsonAtom_rejectsNonFiniteNumbers', 0, () => {
      let code: string = '';
      try {
        JsonAtom.encode(Number.NaN);
      } catch (error) {
        code = (error as Error).message;
      }
      expect(code).assertEqual('PROTOCOL_INVALID_TYPE');
    });

    it('C01_JsonAtom_escapesControlCharacters', 0, () => {
      expect(JsonAtom.encode('a"b\\c\n')).assertEqual('"a\\"b\\\\c\\n"');
    });
  });
}
