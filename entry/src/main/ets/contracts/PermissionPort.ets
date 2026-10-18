/*
 * YaoCore C-23 runtime permission port.
 * Producer: agent:implementation-engineer | Task: T-16 / wp-060-vm
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-A §27.6.3 P1 / DES-B §23.1
 * (EXT-DES-B-22 historical; EXT-DES-B-34 registers the renamed symbols).
 * Renamed: T-23 / wp-093-t23-fixes (2026-10-18) — C-23 VM-facing contract is
 * ProvisioningPermissionPort/ProvisioningPermissionKind; PermissionResult stays
 * an app-layer C-28 type and is not exported here.
 * Contract: DES-B §12.4
 */
export enum ProvisioningPermissionKind {
  BLUETOOTH = 'BLUETOOTH'
}

export interface ProvisioningPermissionPort {
  /** Throws PROVISIONING_PERMISSION_DENIED / PROVISIONING_BLUETOOTH_OFF. */
  ensure(kind: ProvisioningPermissionKind): Promise<void>;
  /** F-08: opens the app settings page after a terminal permission denial. */
  openSettings?(): Promise<void>;
}
