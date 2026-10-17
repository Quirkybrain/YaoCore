/*
 * YaoCore C-18 manual address policy.
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §15.3; ADR-004 §5.2; PR-06
 *
 * Manual addresses are a locator for an already-bound gateway. They never
 * create a binding and are never used to infer a gatewayId.
 */
import { AppErrors } from '../../common/types/AppError';
import { IpAddressUtil } from '../../common/utils/IpAddressUtil';
import { GatewayAddress, GatewayRoute } from '../../model/GatewayRoute';

export class ManualAddressPolicy {
  static validate(input: string, port: number): GatewayAddress {
    const text = input.trim();
    if (!IpAddressUtil.isAllowedLanIpv4(text) || !IpAddressUtil.isValidPort(port)) {
      throw AppErrors.of('MANUAL_ADDRESS_REJECTED', []);
    }
    return new GatewayAddress(text, port);
  }

  static requireBound(route: GatewayRoute | undefined): GatewayRoute {
    if (route === undefined) {
      throw AppErrors.of('MANUAL_ADDRESS_NOT_BOUND', []);
    }
    return route;
  }
}
