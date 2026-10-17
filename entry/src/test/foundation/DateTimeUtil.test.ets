/*
 * YaoCore Hypium host suite: C-01 DateTimeUtil.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Traceability: DES-A §4.1.5, §4.3 invariants 2..4.
 *
 * `hvigorw test` is BLOCKED in this Linux environment (Previewer limitation);
 * this suite is compile-checked and mirrors executable Node host assertions.
 */
import { describe, expect, it } from '@ohos/hypium';
import { DateTimeUtil } from '../../main/ets/common/utils/DateTimeUtil';

export function DateTimeUtilSuite(): void {
  describe('C01 DateTimeUtil', () => {
    it('C01_DateTimeUtil_roundTripsCompactUtc', 0, () => {
      expect(DateTimeUtil.formatUtcCompact(0)).assertEqual('19700101T000000Z');
      expect(DateTimeUtil.parseUtcCompact('19700101T000000Z')).assertEqual(0);
      expect(DateTimeUtil.formatUtcCompact(1234)).assertEqual('19700101T000001Z');
      expect(DateTimeUtil.parseUtcCompact('20240229T235959Z'))
        .assertEqual(Date.UTC(2024, 1, 29, 23, 59, 59));
    });

    it('C01_DateTimeUtil_rejectsInvalidCalendarDates', 0, () => {
      let code: string = '';
      try {
        DateTimeUtil.parseUtcCompact('20230229T000000Z');
      } catch (error) {
        code = (error as Error).message;
      }
      expect(code).assertEqual('PROTOCOL_INVALID_TIMESTAMP');
    });

    it('C01_DateTimeUtil_windowBoundaryIsInclusive', 0, () => {
      const now: number = 1700000000000;
      expect(DateTimeUtil.isWithinWindow(now, now + 120000, 120000)).assertTrue();
      expect(DateTimeUtil.isWithinWindow(now, now + 120001, 120000)).assertFalse();
    });

    it('C01_DateTimeUtil_requestIdMatchesPattern', 0, () => {
      expect(DateTimeUtil.formatRequestId(1729000000000, 7)).assertEqual('req-1729000000000-7');
    });
  });
}
