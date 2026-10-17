/*
 * YaoCore C-05 clock skew hint tracker.
 * Producer: agent:implementation-engineer | Task: T-07 / wp-016-security
 * Contract: DES-A §8.1.5, §3.3
 *
 * Responses are never rejected because of clock skew; this tracker only feeds
 * a local "calibrate time" hint (CB §2.5).
 */
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';

export class ClockSkewObservation {
  readonly skewMs: number;
  readonly exceedsWindow: boolean;

  constructor(skewMs: number, exceedsWindow: boolean) {
    this.skewMs = skewMs;
    this.exceedsWindow = exceedsWindow;
  }
}

export class ClockSkewTracker {
  private readonly windowMs: number;
  private lastObservedSkew: number | undefined = undefined;

  constructor(windowMs: number = 120000) {
    this.windowMs = windowMs;
  }

  observe(serverTime: string, localNowMs: number): ClockSkewObservation {
    const serverMs = DateTimeUtil.parseUtcCompact(serverTime);
    const skew = serverMs - localNowMs;
    this.lastObservedSkew = skew;
    const exceeds = Math.abs(skew) > this.windowMs;
    return new ClockSkewObservation(skew, exceeds);
  }

  lastSkewMs(): number | undefined {
    return this.lastObservedSkew;
  }
}
