/*
 * YaoCore C-21..C-23 ViewModel-only ports.
 * Producer: agent:implementation-engineer | Task: T-15/T-16 / wp-060-vm
 * Contract: DES-B §10.4, §11.4, §12.4; DES-A §3.7; D-019
 *
 * Production services are injected as their concrete C-08..C-19 classes, as
 * specified by DES-B. Only the two seams that do not exist yet are declared
 * here: the control coordinator (implemented in core/) and the runtime
 * permission gate (assembled by C-28 / T-17).
 */
import type { DeviceControlCommand } from '../model/ControlModels';
import type { ControlExecution } from './core/ViewModelCore';

export interface DeviceControlCoordinatorPort {
  execute(command: DeviceControlCommand, familyId: string): Promise<ControlExecution>;
}

export enum PermissionKind {
  BLUETOOTH = 'BLUETOOTH'
}

export interface PermissionPort {
  /** Throws PROVISIONING_PERMISSION_DENIED / PROVISIONING_BLUETOOTH_OFF. */
  ensure(kind: PermissionKind): Promise<void>;
}

/** Discovery subset consumed by Home/Settings; C-18 satisfies it after the
 * compile blocker recorded in t15-16-vm.md is fixed. */
export interface ManualDiscoveryPort {
  probeLastKnown(gatewayId: string): Promise<import('../service/gateway/DiscoveryModels').DiscoveryCandidate | undefined>;
  probeManual(gatewayId: string, address: import('../model/GatewayRoute').GatewayAddress):
    Promise<import('../service/gateway/DiscoveryModels').DiscoveryCandidate>;
  resetManualFailures(gatewayId: string): void;
}
