/*
 * YaoCore C-10/C-11 scene reference port.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-A §27.6.3 P1 / DES-B §23.1.
 * Contract: DES-B §6.1.2 (EXT-DES-B-06)
 *
 * Port-only declaration; no platform import and no implementation.
 */
import type { RdbTransaction } from './RdbStore';
import type { DeviceKey } from '../model/DeviceKey';
import type { SceneCleanupSummary } from '../model/DeviceRecord';

export interface SceneReferencePort {
  removeDeviceReferences(tx: RdbTransaction, familyId: string,
    key: DeviceKey): Promise<SceneCleanupSummary>;
  removeGatewayReferences(tx: RdbTransaction, familyId: string,
    gatewayId: string): Promise<SceneCleanupSummary>;
  listSceneIdsReferencing(tx: RdbTransaction, familyId: string,
    key: DeviceKey): Promise<ReadonlyArray<string>>;
}
