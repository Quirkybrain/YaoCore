import { GattEndpointMap } from '../service/ble/GattEndpointMap';
import type { IBleProvisioningClient } from '../service/ble/BleProvisioningPorts';
export class VM { uuid(): string { return GattEndpointMap.SERVICE_UUID; } client?: IBleProvisioningClient; }
