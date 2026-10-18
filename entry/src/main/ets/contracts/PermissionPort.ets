/*
 * YaoCore C-23 runtime permission port.
 * Producer: agent:implementation-engineer | Task: T-16 / wp-060-vm
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-A §27.6.3 P1 / DES-B §23.1
 * (EXT-DES-B-22).
 * Contract: DES-B §12.4
 */
export enum PermissionKind {
  BLUETOOTH = 'BLUETOOTH'
}

export interface PermissionPort {
  /** Throws PROVISIONING_PERMISSION_DENIED / PROVISIONING_BLUETOOTH_OFF. */
  ensure(kind: PermissionKind): Promise<void>;
  /** F-08: opens the app settings page after a terminal permission denial. */
  openSettings?(): Promise<void>;
}
