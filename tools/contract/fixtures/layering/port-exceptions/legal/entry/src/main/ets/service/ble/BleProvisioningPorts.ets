export interface IBleProvisioningClient { provision(): Promise<void>; }
export enum ProvisioningState { IDLE = 'IDLE', RUNNING = 'RUNNING' }
