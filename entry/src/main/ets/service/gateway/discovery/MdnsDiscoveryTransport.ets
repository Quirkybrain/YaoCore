/*
 * YaoCore C-18 mDNS discovery adapter (PB-01 seam).
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §15.4, §21.2; ADR-004 §5
 *
 * COMPILED_ONLY / DEVICE-VERIFIED-PENDING.
 *
 * PB-01 leaves the mDNS service type and TXT schema UNRESOLVED. Therefore this
 * adapter has NO default service type and NO default TXT field: both are
 * injected by the composition root when (and only if) the architecture closes
 * PB-01. Beacons are locators only; the C-18 service still requires a signed
 * discover whose identity equals the bound route before a candidate can be
 * verified. Service names, hostnames and TXT values never create a binding.
 */
import { mdns } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { AppErrors } from '../../../common/types/AppError';
import { Utf8 } from '../../../common/utils/Utf8';
import { IpAddressUtil } from '../../../common/utils/IpAddressUtil';
import { GatewayAddress } from '../../../model/GatewayRoute';
import type { CancellationToken } from '../../../common/types/CancellationToken';
import { DiscoveryBeacon, DiscoveryTransportKind } from '../../../model/DiscoveryModels';
import type { DiscoveryTransport } from '../../../contracts/DiscoveryTransport';

export class MdnsDiscoveryTransport implements DiscoveryTransport {
  readonly kind: DiscoveryTransportKind = DiscoveryTransportKind.MDNS;
  private readonly context: common.Context;
  private readonly serviceType: string;
  private readonly hintAttribute: string | undefined;
  private readonly clockNowMs: () => number;

  constructor(context: common.Context, serviceType: string, hintAttribute?: string,
    clockNowMs?: () => number) {
    if (serviceType.length === 0) {
      // PB-01: the service type is configuration, never a guess.
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.context = context;
    this.serviceType = serviceType;
    this.hintAttribute = hintAttribute;
    this.clockNowMs = clockNowMs === undefined ? (): number => Date.now() : clockNowMs;
  }

  async scan(timeoutMs: number,
    cancellation?: CancellationToken): Promise<ReadonlyArray<DiscoveryBeacon>> {
    if (!Number.isInteger(timeoutMs) || timeoutMs <= 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    const found: mdns.LocalServiceInfo[] = [];
    const service = mdns.createDiscoveryService(this.context, this.serviceType);
    const onFound = (info: mdns.LocalServiceInfo): void => {
      found.push(info);
    };
    try {
      service.on('serviceFound', onFound);
      service.startSearchingMDNS();
      await MdnsDiscoveryTransport.wait(timeoutMs, cancellation);
    } catch (error) {
      throw AppErrors.of('DISCOVERY_TRANSPORT_UNAVAILABLE', []);
    } finally {
      try {
        service.stopSearchingMDNS();
      } catch (error) {
        // Best-effort stop; the scan result/exception is already classified.
      }
      try {
        service.off('serviceFound', onFound);
      } catch (error) {
        // Listener removal failure must not mask the scan result.
      }
    }
    const beacons: DiscoveryBeacon[] = [];
    for (let index = 0; index < found.length; index++) {
      const beacon = await this.toBeacon(found[index]);
      if (beacon !== undefined) {
        beacons.push(beacon);
      }
    }
    return beacons;
  }

  private async toBeacon(info: mdns.LocalServiceInfo): Promise<DiscoveryBeacon | undefined> {
    let resolved = info;
    if (resolved.host === undefined && resolved.port === undefined) {
      try {
        resolved = await mdns.resolveLocalService(this.context, info);
      } catch (error) {
        return undefined;
      }
    }
    if (resolved.host === undefined || resolved.port === undefined) {
      return undefined;
    }
    const ip = resolved.host.address;
    const port = resolved.port;
    // C-02 GatewayAddress is IPv4-only in v1. F-10: mDNS is an untrusted
    // locator source, so loopback/link-local/multicast directions are dropped.
    if (!IpAddressUtil.isAllowedLanIpv4(ip) || !IpAddressUtil.isValidPort(port)) {
      return undefined;
    }
    const hint = this.readHint(resolved.serviceAttribute);
    return new DiscoveryBeacon(new GatewayAddress(ip, port), hint, resolved.serviceName,
      this.clockNowMs());
  }

  /**
   * Reads only the explicitly configured TXT attribute. No default key is
   * assumed (PB-01); without configuration the beacon carries no gateway hint.
   */
  private readHint(attributes: Array<mdns.ServiceAttribute> | undefined): string | undefined {
    if (this.hintAttribute === undefined || attributes === undefined) {
      return undefined;
    }
    for (let index = 0; index < attributes.length; index++) {
      if (attributes[index].key === this.hintAttribute) {
        const bytes = new Uint8Array(attributes[index].value.length);
        for (let offset = 0; offset < attributes[index].value.length; offset++) {
          bytes[offset] = attributes[index].value[offset];
        }
        try {
          return Utf8.decode(bytes);
        } catch (error) {
          return undefined;
        }
      }
    }
    return undefined;
  }

  private static wait(timeoutMs: number, cancellation?: CancellationToken): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      let settled = false;
      const timer = setTimeout(() => {
        if (!settled) {
          settled = true;
          resolve();
        }
      }, timeoutMs);
      if (cancellation !== undefined) {
        cancellation.onCancel(() => {
          if (!settled) {
            settled = true;
            clearTimeout(timer);
            resolve();
          }
        });
      }
    });
  }
}
