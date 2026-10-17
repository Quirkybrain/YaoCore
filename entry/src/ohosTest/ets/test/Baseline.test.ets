/*
 * Minimal Hypium test probe for the T-01 build/test baseline.
 * This is a harness smoke test only; it does not test product behavior.
 * Public test code, no secrets.
 */
import { describe, expect, it } from '@ohos/hypium';

export default function baselineTest() {
  describe('YaoCoreBuildBaseline', () => {
    it('arkts_values_evaluate_correctly', 0, () => {
      const expected: string = 'YaoCore';
      expect(expected).assertEqual('YaoCore');
      expect(2 + 2).assertEqual(4);
    });

    it('assertion_failure_is_detected', 0, () => {
      const actual: number = 3;
      expect(actual).assertLarger(2);
      expect(actual).assertLess(4);
    });
  });
}
