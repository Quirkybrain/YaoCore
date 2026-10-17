/*
 * YaoCore C-28 production platform ports.
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-A §3.7, §23.3; DES-B §2.4 step 1; D-019
 *
 * ONLY composition-root-owned platform adapters: clock, UUID, hilog logger,
 * metrics and the two timer seams. No business logic. Secrets/family/user data
 * are never logged; callers pass English diagnostic fields only (SC-06).
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import type { ClockPort, IdPort, LoggerPort, MetricsPort } from '../common/types/Ports';
import type { NameValue } from '../common/types/NameValue';
import type { SceneTimerPort } from '../service/scene/SceneTimerPort';
import type { VmTimerPort } from '../viewmodel/core/ViewModelCore';

const DOMAIN: number = 0x0000;
const TAG: string = 'YaoCore';

export class SystemClock implements ClockPort {
  nowMs(): number {
    return Date.now();
  }
}

export class UuidGenerator implements IdPort {
  newId(): string {
    return util.generateRandomUUID(false);
  }
}

export class HilogLogger implements LoggerPort {
  debug(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
    hilog.debug(DOMAIN, TAG, '%{public}s', HilogLogger.line(tag, message, fields));
  }

  info(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
    hilog.info(DOMAIN, TAG, '%{public}s', HilogLogger.line(tag, message, fields));
  }

  warn(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
    hilog.warn(DOMAIN, TAG, '%{public}s', HilogLogger.line(tag, message, fields));
  }

  error(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
    hilog.error(DOMAIN, TAG, '%{public}s', HilogLogger.line(tag, message, fields));
  }

  private static line(tag: string, message: string,
    fields?: ReadonlyArray<NameValue>): string {
    let text = tag + ' ' + message;
    if (fields !== undefined) {
      for (let index = 0; index < fields.length; index++) {
        text = text + ' ' + fields[index].name + '=' + fields[index].value;
      }
    }
    return text;
  }
}

export class HilogMetrics implements MetricsPort {
  record(name: string, valueMs: number, tags?: ReadonlyArray<NameValue>): void {
    let text = name + '=' + String(valueMs) + 'ms';
    if (tags !== undefined) {
      for (let index = 0; index < tags.length; index++) {
        text = text + ' ' + tags[index].name + '=' + tags[index].value;
      }
    }
    hilog.debug(DOMAIN, TAG, 'metric %{public}s', text);
  }
}

export class SystemVmTimer implements VmTimerPort {
  setTimer(delayMs: number, callback: () => void): number {
    return setTimeout(callback, delayMs);
  }

  clearTimer(timerId: number): void {
    clearTimeout(timerId);
  }
}

export class SystemSceneTimer implements SceneTimerPort {
  delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, ms);
    });
  }
}
