/*
 * YaoCore C-28 explicit adapters for ArkTS nominal typing.
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §17.1.2/§17.1.3; D-019
 *
 * ArkTS forbids structural typing (arkts-no-structural-typing). Where a C-08/
 * C-12/C-18 concrete class already implements the same shape but not the exact
 * port name, the composition root wraps it in one of these thin, explicit
 * adapters instead of forcing a service-layer change.
 */
import type { Family } from '../model/FamilyModels';
import type { GatewayAddress } from '../model/GatewayRoute';
import type { LocalProfile, SessionInfo } from '../service/auth/AuthModels';
import { PolicyDecision } from '../service/auth/AuthModels';
import type { AuthService } from '../service/auth/AuthService';
import type { FamilyRepository } from '../repository/FamilyRepository';
import type { FamilyMember } from '../model/FamilyModels';
import type { DiscoveryCandidate } from '../service/gateway/DiscoveryModels';
import type { GatewayDiscoveryService } from '../service/gateway/GatewayDiscoveryService';
import type { ManualDiscoveryPort } from '../viewmodel/ViewModelPorts';
import type { RoomActorLookupPort } from '../service/room/RoomService';
import type { RoomSessionPort } from '../viewmodel/RoomViewModel';
import type { SceneExecutionAuthorizationPort } from '../service/scene/SceneService';
import type {
  ActiveFamilyPort,
  SessionGateAuthPort
} from './AppContext';

export class SessionGateAuthAdapter implements SessionGateAuthPort {
  private readonly auth: AuthService;

  constructor(auth: AuthService) {
    this.auth = auth;
  }

  listProfiles(familyId: string): Promise<ReadonlyArray<LocalProfile>> {
    return this.auth.listProfiles(familyId);
  }

  getActiveSession(): SessionInfo | undefined {
    return this.auth.getActiveSession();
  }

  unlock(profileId: string, password: string): Promise<SessionInfo> {
    return this.auth.unlock(profileId, password);
  }

  lockAll(): Promise<void> {
    return this.auth.lockAll();
  }
}

export class ActiveFamilyAdapter implements ActiveFamilyPort {
  private readonly families: FamilyRepository;

  constructor(families: FamilyRepository) {
    this.families = families;
  }

  getActiveFamily(): Promise<Family | undefined> {
    return this.families.getActiveFamily();
  }

  setActiveFamily(familyId: string): Promise<void> {
    return this.families.setActiveFamily(familyId);
  }
}

/**
 * F-02: C-12 session policy adapted to the C-11 scene guard. No session means
 * SESSION_EXPIRED and therefore a denial; a GUEST gets RBAC_DENIED from the
 * existing AuthService matrix.
 */
export class SceneExecutionAuthAdapter implements SceneExecutionAuthorizationPort {
  private readonly auth: AuthService;

  constructor(auth: AuthService) {
    this.auth = auth;
  }

  canExecuteScene(): PolicyDecision {
    const session = this.auth.getActiveSession();
    if (session === undefined) {
      return PolicyDecision.deny('SESSION_EXPIRED');
    }
    return this.auth.canExecuteScene(session);
  }
}

/** F-03: active session member id for RoomService actor checks. */
export class RoomSessionAdapter implements RoomSessionPort {
  private readonly auth: AuthService;

  constructor(auth: AuthService) {
    this.auth = auth;
  }

  getMemberId(): string | undefined {
    const session = this.auth.getActiveSession();
    return session === undefined ? undefined : session.memberId;
  }
}

/** F-03: C-08 member lookup used by RoomService to verify an actor role. */
export class RoomActorLookupAdapter implements RoomActorLookupPort {
  private readonly families: FamilyRepository;

  constructor(families: FamilyRepository) {
    this.families = families;
  }

  getMember(familyId: string, memberId: string): Promise<FamilyMember | undefined> {
    return this.families.getMember(familyId, memberId);
  }
}

export class ManualDiscoveryAdapter implements ManualDiscoveryPort {
  private readonly discovery: GatewayDiscoveryService;

  constructor(discovery: GatewayDiscoveryService) {
    this.discovery = discovery;
  }

  probeLastKnown(gatewayId: string): Promise<DiscoveryCandidate | undefined> {
    return this.discovery.probeLastKnown(gatewayId);
  }

  probeManual(gatewayId: string, address: GatewayAddress): Promise<DiscoveryCandidate> {
    return this.discovery.probeManual(gatewayId, address);
  }

  resetManualFailures(gatewayId: string): void {
    this.discovery.resetManualFailures(gatewayId);
  }
}
