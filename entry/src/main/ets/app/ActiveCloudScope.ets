/*
 * YaoCore C-28 single active cloud scope.
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §8.1.4, §8.3.1, §17.1.2; CQG-T14 F-06/R2-02
 *
 * CloudCommandClient requires CloudActiveScopePort before it allocates a
 * sequence, reads a command secret, signs or sends HTTP. `CloudConfig` has no
 * gatewayId (v1 single active scope), so C-28 supplies the binding:
 * - exactly one route in the active family is the active cloud scope;
 * - zero or more than one route fails closed (undefined);
 * - `isGatewayBound` delegates to the route repository's persisted binding and
 *   never reads the command secret.
 */
import type { CloudActiveScopePort } from '../service/cloud/CloudPorts';
import type { GatewayRoutePort } from '../repository/GatewayPorts';

export type ActiveFamilyIdProvider = () => string | undefined;

export class ActiveCloudScope implements CloudActiveScopePort {
  private readonly routes: GatewayRoutePort;
  private familyIdProvider: ActiveFamilyIdProvider | undefined = undefined;

  constructor(routes: GatewayRoutePort) {
    this.routes = routes;
  }

  setActiveFamilyIdProvider(provider: ActiveFamilyIdProvider): void {
    this.familyIdProvider = provider;
  }

  async activeGatewayId(): Promise<string | undefined> {
    const provider = this.familyIdProvider;
    if (provider === undefined) {
      return undefined;
    }
    const familyId = provider();
    if (familyId === undefined || familyId.length === 0) {
      return undefined;
    }
    const routes = await this.routes.listRoutesByFamily(familyId);
    if (routes.length !== 1) {
      return undefined;
    }
    return routes[0].gatewayId;
  }

  async isGatewayBound(gatewayId: string): Promise<boolean> {
    if (gatewayId.length === 0) {
      return false;
    }
    return this.routes.isBound(gatewayId);
  }
}
