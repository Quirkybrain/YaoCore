/*
 * YaoCore C-28 shell-gate entry mapping (F-02).
 * Producer: agent:implementation-engineer | Task: wp-070-fix-t17
 * Contract: DES-B §17.1.5 (NO_PROFILE -> 创建家庭/加入家庭入口; LOCKED -> 解锁)
 *
 * Pure, host-testable mapping from SessionGateState to the entries the gate
 * must render. SessionGateView consumes this instead of duplicating the state
 * checks, so a fresh install always exposes onboarding.
 */
import { SessionGateState } from './AppContext';

export enum ShellGateEntry {
  CREATE_FAMILY = 'CREATE_FAMILY',
  JOIN_FAMILY = 'JOIN_FAMILY',
  UNLOCK = 'UNLOCK'
}

export class ShellGateRouting {
  static entriesFor(state: SessionGateState): ReadonlyArray<ShellGateEntry> {
    if (state === SessionGateState.NO_PROFILE) {
      return [ShellGateEntry.CREATE_FAMILY, ShellGateEntry.JOIN_FAMILY];
    }
    if (state === SessionGateState.LOCKED) {
      return [ShellGateEntry.UNLOCK];
    }
    return [];
  }

  static hasEntry(state: SessionGateState, entry: ShellGateEntry): boolean {
    return ShellGateRouting.entriesFor(state).indexOf(entry) >= 0;
  }
}
