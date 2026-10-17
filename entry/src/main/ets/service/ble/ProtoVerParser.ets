/*
 * YaoCore C-19 `proto-ver` capability gate.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Contract: DES-A §16.3; BLE设计 §3-49-58; project-constraints PR-12
 *
 * Plaintext JSON is parsed with the C-01 strict parser. Any malformed or
 * security-downgrading response fails closed; there is no Security0 fallback
 * and no cleartext Wi-Fi credential path.
 */
import { AppErrors } from '../../common/types/AppError';
import { JsonKind, JsonNode } from '../../common/types/JsonNode';
import { JsonParser } from '../../common/utils/JsonParser';
import { Utf8 } from '../../common/utils/Utf8';

const V11_PATTERN: RegExp = /^v1\.1(\.[0-9]+)?$/;
const YAOCORE_VERSION: string = '2.0';

export class ProtoVerInfo {
  readonly provVersion: string;
  readonly secVer: number;
  readonly noSec: boolean;
  readonly noPop: boolean;
  readonly supportsWifiScan: boolean;
  readonly yaoCoreVersion: string;

  constructor(provVersion: string, secVer: number, noSec: boolean, noPop: boolean,
    supportsWifiScan: boolean, yaoCoreVersion: string) {
    this.provVersion = provVersion;
    this.secVer = secVer;
    this.noSec = noSec;
    this.noPop = noPop;
    this.supportsWifiScan = supportsWifiScan;
    this.yaoCoreVersion = yaoCoreVersion;
  }
}

function unsupported(field: string): never {
  throw AppErrors.protocol('PROVISIONING_CAPABILITY_UNSUPPORTED', field);
}

export class ProtoVerParser {
  static parse(payload: Uint8Array): ProtoVerInfo {
    let root: JsonNode;
    try {
      root = JsonParser.parse(Utf8.decode(payload));
    } catch (error) {
      unsupported('json');
    }
    if (root.kind !== JsonKind.OBJECT) {
      unsupported('root');
    }
    const prov = root.get('prov');
    if (prov === undefined || prov.kind !== JsonKind.OBJECT) {
      unsupported('prov');
    }
    // A missing `prov.ver` is a capability failure, not a generic protocol
    // missing-field error (DES-A §16.3-3926; F-06).
    const provVersionNode = prov.get('ver');
    if (provVersionNode === undefined || provVersionNode.kind !== JsonKind.STRING ||
      !V11_PATTERN.test(provVersionNode.stringValue)) {
      unsupported('prov.ver');
    }
    const secVer = ProtoVerParser.readSecVer(root, prov);
    if (secVer !== 1) {
      unsupported('sec_ver');
    }
    const noSec = ProtoVerParser.readBooleanFlag(root, prov, 'no_sec');
    const noPop = ProtoVerParser.readBooleanFlag(root, prov, 'no_pop');
    if (noSec || noPop) {
      unsupported(noSec ? 'no_sec' : 'no_pop');
    }
    const capabilities = ProtoVerParser.readCapabilities(prov);
    let supportsWifiScan = false;
    for (let index = 0; index < capabilities.length; index++) {
      const capability = capabilities[index];
      if (capability === 'wifi_scan') {
        supportsWifiScan = true;
      }
      if (capability === 'no_sec' || capability === 'no_pop') {
        unsupported(capability);
      }
    }
    if (!supportsWifiScan) {
      unsupported('prov.cap.wifi_scan');
    }
    const yaoCoreVersion = ProtoVerParser.readYaoCoreVersion(root, prov);
    return new ProtoVerInfo(provVersionNode.stringValue, secVer, noSec, noPop,
      supportsWifiScan, yaoCoreVersion);
  }

  private static readSecVer(root: JsonNode, prov: JsonNode): number {
    let value = -1;
    const top = root.get('sec_ver');
    if (top !== undefined) {
      if (top.kind !== JsonKind.NUMBER || !Number.isInteger(top.numberValue)) {
        unsupported('sec_ver');
      }
      value = top.numberValue;
    }
    const nested = prov.get('sec_ver');
    if (nested !== undefined) {
      if (nested.kind !== JsonKind.NUMBER || !Number.isInteger(nested.numberValue)) {
        unsupported('prov.sec_ver');
      }
      if (value !== -1 && value !== nested.numberValue) {
        unsupported('sec_ver');
      }
      value = nested.numberValue;
    }
    return value;
  }

  private static readBooleanFlag(root: JsonNode, prov: JsonNode, name: string): boolean {
    let result = false;
    const top = root.get(name);
    if (top !== undefined) {
      if (top.kind !== JsonKind.BOOLEAN) {
        unsupported(name);
      }
      result = result || top.booleanValue;
    }
    const nested = prov.get(name);
    if (nested !== undefined) {
      if (nested.kind !== JsonKind.BOOLEAN) {
        unsupported('prov.' + name);
      }
      result = result || nested.booleanValue;
    }
    return result;
  }

  private static readCapabilities(prov: JsonNode): ReadonlyArray<string> {
    const capability = prov.get('cap');
    if (capability === undefined || capability.kind !== JsonKind.ARRAY) {
      unsupported('prov.cap');
    }
    const result: string[] = [];
    const items = capability.arrayValue;
    for (let index = 0; index < items.length; index++) {
      if (items[index].kind !== JsonKind.STRING) {
        unsupported('prov.cap');
      }
      result.push(items[index].stringValue);
    }
    return result;
  }

  private static readYaoCoreVersion(root: JsonNode, prov: JsonNode): string {
    let found = false;
    let version = '';
    const top = root.get('yaocore');
    if (top !== undefined) {
      found = true;
      version = ProtoVerParser.readVersionNode(top);
    }
    const nested = prov.get('yaocore');
    if (nested !== undefined) {
      const nestedVersion = ProtoVerParser.readVersionNode(nested);
      if (found && version !== nestedVersion) {
        unsupported('yaocore');
      }
      found = true;
      version = nestedVersion;
    }
    if (!found || version !== YAOCORE_VERSION) {
      unsupported('yaocore.version');
    }
    return version;
  }

  private static readVersionNode(node: JsonNode): string {
    if (node.kind === JsonKind.STRING) {
      return node.stringValue;
    }
    if (node.kind === JsonKind.OBJECT) {
      const version = node.get('version');
      if (version !== undefined && version.kind === JsonKind.STRING) {
        return version.stringValue;
      }
      const ver = node.get('ver');
      if (ver !== undefined && ver.kind === JsonKind.STRING) {
        return ver.stringValue;
      }
    }
    unsupported('yaocore.version');
  }
}
