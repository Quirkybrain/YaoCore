/*
 * YaoCore C-28 composition/assembly plan.
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §2.4, §17.1.2, §17.4; DES-B-C28-SEAM; D-019
 *
 * The plan is the executable order contract for AppCompositionRoot. The root
 * records every construction and initialization step through AssemblyTrace;
 * an out-of-order or repeated step fails closed with CONFIGURATION_ERROR.
 *
 * Deviations from DES-B §2.4 (recorded in the T-17 implementation and fix
 * reports):
 * - SceneService depends on the BACKGROUND IGatewayClient/DeviceControlPort, so
 *   it is constructed after the two LocalGatewayService instances instead of at
 *   step 13. RoomService/FamilyService remain at the step-13 position.
 * - CryptoService is constructed in PLATFORM (step 1) instead of the §2.4
 *   security stack (step 5). It only depends on OhosCryptoProvider and
 *   CryptoRandomSource; no storage edge exists. SECURITY is still recorded as
 *   the §2.4 security-stack step.
 * Every other dependency edge follows §2.4.
 */

import { AppErrors } from '../common/types/AppError';

export enum ConstructionStep {
  PLATFORM = 'PLATFORM',
  STORAGE_ADAPTERS = 'STORAGE_ADAPTERS',
  MIGRATIONS = 'MIGRATIONS',
  STORAGE_SERVICE = 'STORAGE_SERVICE',
  SECURITY = 'SECURITY',
  REPOSITORIES = 'REPOSITORIES',
  AUTH_SERVICE = 'AUTH_SERVICE',
  INVITE_SERVICE = 'INVITE_SERVICE',
  DOMAIN_SERVICES = 'DOMAIN_SERVICES',
  GATEWAY_TRANSPORT = 'GATEWAY_TRANSPORT',
  GATEWAY_CLIENTS = 'GATEWAY_CLIENTS',
  SCENE_SERVICE = 'SCENE_SERVICE',
  DISCOVERY = 'DISCOVERY',
  BLE = 'BLE',
  CLOUD = 'CLOUD',
  DEVICE_COMMAND_RUNNER = 'DEVICE_COMMAND_RUNNER',
  CONTROL_COORDINATOR = 'CONTROL_COORDINATOR',
  I18N_SERVICE = 'I18N_SERVICE',
  APP_CONTEXT = 'APP_CONTEXT'
}

export enum InitializationStep {
  STORAGE = 'STORAGE',
  AUTH = 'AUTH',
  GATEWAY = 'GATEWAY',
  FAMILY = 'FAMILY',
  ROOM = 'ROOM',
  SCENE = 'SCENE',
  DEVICE = 'DEVICE',
  CLOUD = 'CLOUD',
  I18N = 'I18N'
}

export const ASSEMBLY_CONSTRUCTION_ORDER: ReadonlyArray<ConstructionStep> = [
  ConstructionStep.PLATFORM,
  ConstructionStep.STORAGE_ADAPTERS,
  ConstructionStep.MIGRATIONS,
  ConstructionStep.STORAGE_SERVICE,
  ConstructionStep.SECURITY,
  ConstructionStep.REPOSITORIES,
  ConstructionStep.AUTH_SERVICE,
  ConstructionStep.INVITE_SERVICE,
  ConstructionStep.DOMAIN_SERVICES,
  ConstructionStep.GATEWAY_TRANSPORT,
  ConstructionStep.GATEWAY_CLIENTS,
  ConstructionStep.SCENE_SERVICE,
  ConstructionStep.DISCOVERY,
  ConstructionStep.BLE,
  ConstructionStep.CLOUD,
  ConstructionStep.DEVICE_COMMAND_RUNNER,
  ConstructionStep.CONTROL_COORDINATOR,
  ConstructionStep.I18N_SERVICE,
  ConstructionStep.APP_CONTEXT
];

export const ASSEMBLY_INITIALIZATION_ORDER: ReadonlyArray<InitializationStep> = [
  InitializationStep.STORAGE,
  InitializationStep.AUTH,
  InitializationStep.GATEWAY,
  InitializationStep.FAMILY,
  InitializationStep.ROOM,
  InitializationStep.SCENE,
  InitializationStep.DEVICE,
  InitializationStep.CLOUD,
  InitializationStep.I18N
];

/**
 * Monotonic recorder. The root constructs/initializes services in plan order;
 * any drift is a coding/configuration error, not a recoverable runtime state.
 */
export class AssemblyTrace {
  private readonly plan: ReadonlyArray<string>;
  private readonly recorded: string[] = [];
  private nextIndex: number = 0;

  constructor(plan: ReadonlyArray<string>) {
    this.plan = plan;
  }

  record(step: string): void {
    if (this.nextIndex >= this.plan.length || this.plan[this.nextIndex] !== step) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.recorded.push(step);
    this.nextIndex = this.nextIndex + 1;
  }

  isComplete(): boolean {
    return this.nextIndex === this.plan.length;
  }

  getRecorded(): ReadonlyArray<string> {
    return this.recorded;
  }
}
