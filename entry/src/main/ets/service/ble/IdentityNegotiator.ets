/*
 * YaoCore C-19 identity negotiation (v2.1 -> v2.0 fail-closed fallback).
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Contract: DES-A §16.6; ADR-002 §3.2; identity schemas (v2.0 closed);
 *           project-constraints PR-07
 *
 * Request 2.1 once. If the response is not a valid v2.1 identity, retry 2.0
 * exactly once in the same Security1 session. v2.0 is parsed with the frozen
 * four-field closed schema; any extra key, wrong constant, bad pin or pinAlg
 * fails closed. No command secret/PoP/Wi-Fi password ever crosses this
 * endpoint.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { JsonKind, JsonNode } from '../../common/types/JsonNode';
import { JsonParser } from '../../common/utils/JsonParser';
import { Utf8 } from '../../common/utils/Utf8';
import {
  BleProvisioningIdentity,
  IdentityVersion,
  ProvisioningTlsMaterial
} from '../../model/ProvisioningModels';
import { GattEndpointMap } from './GattEndpointMap';
import { Security1State } from './Security1Session';
import type { Security1Session } from './Security1Session';

const GATEWAY_ID_PATTERN: RegExp = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,62}$/;
const PIN_PATTERN: RegExp = /^[0-9a-f]{64}$/;
const PIN_ALG: string = 'sha256-spki-der';
const MAX_PINS: number = 4;
const SERVICE_ID: string = 'YaoCoreGateway';

const V21_REQUEST: string = '{"op":"get_identity","protocolVersion":"2.1"}';
const V20_REQUEST: string = '{"op":"get_identity","protocolVersion":"2.0"}';

const V20_KEYS: ReadonlyArray<string> = [
  'protocolVersion', 'serviceId', 'gatewayId', 'gatewayName'
];
const V21_KEYS: ReadonlyArray<string> = [
  'protocolVersion', 'serviceId', 'gatewayId', 'gatewayName', 'security'
];
const SECURITY_KEYS: ReadonlyArray<string> = ['lan'];
const LAN_KEYS: ReadonlyArray<string> = ['tls', 'port', 'pins', 'pinAlg'];

export type IdentitySend = (endpoint: string, payload: Uint8Array) => Promise<Uint8Array>;

function identityInvalid(field: string): never {
  throw AppErrors.of('PROVISIONING_IDENTITY_INVALID', [new NameValue('field', field)]);
}

export class IdentityNegotiator {
  /**
   * Encryption/decryption is performed by the supplied `send` closure so the
   * continuous CTR order is owned by the GATT channel; `session` is checked
   * only for ESTABLISHED state before any identity bytes are sent.
   */
  constructor() {
  }

  async negotiate(session: Security1Session, send: IdentitySend,
    expectedGatewayId?: string): Promise<BleProvisioningIdentity> {
    if (session.state !== Security1State.ESTABLISHED) {
      throw AppErrors.of('PROVISIONING_SECURITY_HANDSHAKE_FAILED',
        [new NameValue('field', 'identitySession')]);
    }
    const first = await Promise.resolve(
      send(GattEndpointMap.YAOCORE_ID, Utf8.encode(V21_REQUEST)));
    const v21 = this.tryParseV21(first);
    if (v21 !== undefined) {
      this.checkExpected(v21, expectedGatewayId);
      return v21;
    }
    const second = await Promise.resolve(
      send(GattEndpointMap.YAOCORE_ID, Utf8.encode(V20_REQUEST)));
    let v20: BleProvisioningIdentity;
    try {
      v20 = this.parseV20(second);
    } catch (error) {
      this.rethrowIdentity(error as Error, 'v20Response');
    }
    this.checkExpected(v20, expectedGatewayId);
    return v20;
  }

  /** Strict frozen v2.0 response: exactly four keys, exact constants. */
  parseV20(payload: Uint8Array): BleProvisioningIdentity {
    try {
      let root: JsonNode;
      try {
        root = JsonParser.parse(Utf8.decode(payload));
      } catch (error) {
        identityInvalid('v20Json');
      }
      this.requireExactObject(root, V20_KEYS, 'v20Root');
      this.requireConstant(root, 'protocolVersion', '2.0');
      this.requireConstant(root, 'serviceId', SERVICE_ID);
      const gatewayId = this.readGatewayId(root);
      const gatewayName = this.readGatewayName(root);
      return this.buildIdentity(IdentityVersion.V20, gatewayId, gatewayName, undefined);
    } catch (error) {
      if (error instanceof AppError &&
        (error as AppError).code === 'PROVISIONING_IDENTITY_INVALID') {
        throw error;
      }
      identityInvalid('v20');
    }
  }

  /** Strict v2.1 response: v2.0 four fields plus optional closed security.lan. */
  parseV21(payload: Uint8Array): BleProvisioningIdentity {
    const parsed = this.tryParseV21(payload);
    if (parsed === undefined) {
      identityInvalid('v21Response');
    }
    return parsed as BleProvisioningIdentity;
  }

  private tryParseV21(payload: Uint8Array): BleProvisioningIdentity | undefined {
    try {
      let root: JsonNode;
      try {
        root = JsonParser.parse(Utf8.decode(payload));
      } catch (error) {
        return undefined;
      }
      if (root.kind !== JsonKind.OBJECT) {
        return undefined;
      }
      if (!this.hasExactKeys(root, V21_KEYS, V20_KEYS)) {
        return undefined;
      }
      if (!this.isConstant(root, 'protocolVersion', '2.1') ||
        !this.isConstant(root, 'serviceId', SERVICE_ID)) {
        return undefined;
      }
      const gatewayId = this.readGatewayIdOptional(root);
      const gatewayName = this.readGatewayNameOptional(root);
      if (gatewayId === undefined || gatewayName === undefined) {
        return undefined;
      }
      const tls = this.parseSecurityOptional(root);
      if (tls === undefined) {
        // A security block that exists but is malformed is fail-closed; only
        // a completely absent security block means HMAC-only v2.1.
        if (root.get('security') === undefined) {
          return this.buildIdentityOptional(IdentityVersion.V21, gatewayId, gatewayName, undefined);
        }
        return undefined;
      }
      if (tls.present) {
        return this.buildIdentityOptional(IdentityVersion.V21, gatewayId, gatewayName, tls.material);
      }
      return this.buildIdentityOptional(IdentityVersion.V21, gatewayId, gatewayName, undefined);
    } catch (error) {
      return undefined;
    }
  }

  /**
   * Returns undefined when the security block is absent or invalid. A present
   * block with `lan` omitted means "v2.1 identity, HMAC-only profile".
   */
  private parseSecurityOptional(root: JsonNode): SecurityParse | undefined {
    const security = root.get('security');
    if (security === undefined) {
      return new SecurityParse(false, undefined);
    }
    if (security.kind !== JsonKind.OBJECT) {
      return undefined;
    }
    const keys = security.keys();
    for (let index = 0; index < keys.length; index++) {
      if (SECURITY_KEYS.indexOf(keys[index]) < 0) {
        return undefined;
      }
    }
    const lan = security.get('lan');
    if (lan === undefined) {
      return new SecurityParse(false, undefined);
    }
    if (lan.kind !== JsonKind.OBJECT) {
      return undefined;
    }
    const lanKeys = lan.keys();
    for (let index = 0; index < lanKeys.length; index++) {
      if (LAN_KEYS.indexOf(lanKeys[index]) < 0) {
        return undefined;
      }
    }
    const tlsNode = lan.get('tls');
    if (tlsNode === undefined || tlsNode.kind !== JsonKind.BOOLEAN) {
      return undefined;
    }
    if (!tlsNode.booleanValue) {
      if (lan.get('port') !== undefined || lan.get('pins') !== undefined ||
        lan.get('pinAlg') !== undefined) {
        return undefined;
      }
      return new SecurityParse(false, undefined);
    }
    const portNode = lan.get('port');
    const pinsNode = lan.get('pins');
    const pinAlgNode = lan.get('pinAlg');
    if (portNode === undefined || portNode.kind !== JsonKind.NUMBER ||
      !Number.isInteger(portNode.numberValue) ||
      portNode.numberValue < 1 || portNode.numberValue > 65535) {
      return undefined;
    }
    if (pinsNode === undefined || pinsNode.kind !== JsonKind.ARRAY ||
      pinsNode.arrayValue.length < 1 || pinsNode.arrayValue.length > MAX_PINS) {
      return undefined;
    }
    const pins: string[] = [];
    for (let index = 0; index < pinsNode.arrayValue.length; index++) {
      const pin = pinsNode.arrayValue[index];
      if (pin.kind !== JsonKind.STRING || !PIN_PATTERN.test(pin.stringValue)) {
        return undefined;
      }
      pins.push(pin.stringValue);
    }
    if (pinAlgNode === undefined || pinAlgNode.kind !== JsonKind.STRING ||
      pinAlgNode.stringValue !== PIN_ALG) {
      return undefined;
    }
    try {
      return new SecurityParse(true,
        new ProvisioningTlsMaterial(pins, portNode.numberValue, PIN_ALG));
    } catch (error) {
      return undefined;
    }
  }

  private requireExactObject(node: JsonNode, allowed: ReadonlyArray<string>, field: string): void {
    if (node.kind !== JsonKind.OBJECT) {
      identityInvalid(field);
    }
    if (!this.hasExactKeys(node, allowed, allowed)) {
      identityInvalid(field);
    }
  }

  private hasExactKeys(node: JsonNode, allowed: ReadonlyArray<string>,
    required: ReadonlyArray<string>): boolean {
    if (node.kind !== JsonKind.OBJECT) {
      return false;
    }
    const keys = node.keys();
    for (let index = 0; index < keys.length; index++) {
      if (allowed.indexOf(keys[index]) < 0) {
        return false;
      }
    }
    for (let index = 0; index < required.length; index++) {
      if (!node.has(required[index])) {
        return false;
      }
    }
    return true;
  }

  private requireConstant(node: JsonNode, key: string, expected: string): void {
    if (!this.isConstant(node, key, expected)) {
      identityInvalid(key);
    }
  }

  private isConstant(node: JsonNode, key: string, expected: string): boolean {
    const value = node.get(key);
    return value !== undefined && value.kind === JsonKind.STRING &&
      value.stringValue === expected;
  }

  private readGatewayId(node: JsonNode): string {
    const value = this.readGatewayIdOptional(node);
    if (value === undefined) {
      identityInvalid('gatewayId');
    }
    return value;
  }

  private readGatewayIdOptional(node: JsonNode): string | undefined {
    const value = node.get('gatewayId');
    if (value === undefined || value.kind !== JsonKind.STRING) {
      return undefined;
    }
    return GATEWAY_ID_PATTERN.test(value.stringValue) ? value.stringValue : undefined;
  }

  private readGatewayName(node: JsonNode): string {
    const value = this.readGatewayNameOptional(node);
    if (value === undefined) {
      identityInvalid('gatewayName');
    }
    return value;
  }

  private readGatewayNameOptional(node: JsonNode): string | undefined {
    const value = node.get('gatewayName');
    if (value === undefined || value.kind !== JsonKind.STRING) {
      return undefined;
    }
    // identity schema maxLength counts characters, not UTF-8 bytes: a legal
    // 22-character Chinese name is 66 bytes and must be accepted (F-01).
    if (value.stringValue.length < 1 || value.stringValue.length > 63) {
      return undefined;
    }
    return value.stringValue;
  }

  private buildIdentity(version: IdentityVersion, gatewayId: string, gatewayName: string,
    tls: ProvisioningTlsMaterial | undefined): BleProvisioningIdentity {
    try {
      return new BleProvisioningIdentity(version, gatewayId, gatewayName, tls);
    } catch (error) {
      identityInvalid('identity');
    }
  }

  private buildIdentityOptional(version: IdentityVersion, gatewayId: string,
    gatewayName: string, tls: ProvisioningTlsMaterial | undefined):
    BleProvisioningIdentity | undefined {
    try {
      return new BleProvisioningIdentity(version, gatewayId, gatewayName, tls);
    } catch (error) {
      return undefined;
    }
  }

  private checkExpected(identity: BleProvisioningIdentity, expectedGatewayId?: string): void {
    if (expectedGatewayId !== undefined && identity.gatewayId !== expectedGatewayId) {
      throw AppErrors.of('PROVISIONING_BINDING_IDENTITY_MISMATCH',
        [new NameValue('gatewayId', identity.gatewayId)]);
    }
  }

  private rethrowIdentity(error: Error, field: string): never {
    if (error instanceof AppError) {
      const appError = error as AppError;
      if (appError.code === 'PROVISIONING_BINDING_IDENTITY_MISMATCH') {
        throw appError;
      }
    }
    identityInvalid(field);
  }
}

class SecurityParse {
  readonly present: boolean;
  readonly material?: ProvisioningTlsMaterial;

  constructor(present: boolean, material?: ProvisioningTlsMaterial) {
    this.present = present;
    this.material = material;
  }
}
