/*
 * YaoCore C-21 control coordinator port.
 * Producer: agent:implementation-engineer | Task: T-15/T-16 / wp-060-vm
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-A §27.6.3 P1 / DES-B §23.1
 * (EXT-DES-B-23).
 * Contract: DES-B §10.4
 */
import type { DeviceControlCommand } from '../model/ControlModels';
import type { ControlExecution } from '../model/ControlExecution';

export interface DeviceControlCoordinatorPort {
  execute(command: DeviceControlCommand, familyId: string): Promise<ControlExecution>;
}
