/*
 * YaoCore C-03 deviation sink and counter.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §6.1.6, §18.8
 *
 * DeviationCode/ProtocolDeviation live in common/types/ProtocolDeviation.ets so
 * model/** never depends on service/protocol/**.
 */
import { DeviationCode, ProtocolDeviation } from '../../common/types/ProtocolDeviation';

export interface ProtocolDeviationSink {
  record(deviation: ProtocolDeviation): void;
}

export class DeviationCounter implements ProtocolDeviationSink {
  private readonly countsByCode: Map<DeviationCode, number> = new Map<DeviationCode, number>();

  record(deviation: ProtocolDeviation): void {
    const current = this.countsByCode.get(deviation.code);
    this.countsByCode.set(deviation.code, current === undefined ? 1 : current + 1);
  }

  counts(): Map<DeviationCode, number> {
    const copy = new Map<DeviationCode, number>();
    this.countsByCode.forEach((value: number, key: DeviationCode) => {
      copy.set(key, value);
    });
    return copy;
  }

  total(): number {
    let total = 0;
    this.countsByCode.forEach((value: number) => {
      total += value;
    });
    return total;
  }

  reset(): void {
    this.countsByCode.clear();
  }
}

export class NoopDeviationSink implements ProtocolDeviationSink {
  record(_deviation: ProtocolDeviation): void {
  }
}
