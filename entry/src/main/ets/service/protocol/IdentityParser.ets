/*
 * YaoCore C-03 BLE enrollment identity parser.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §6.1.5, PR-07, ADR-002 §3.2
 *
 * v2.0 is strictly closed: exactly four fields. v2.1 accepts only the optional
 * security/lan extension; every other extra field fails closed. v2.1
 * negotiation itself belongs to T-12.
 */
import { AppError } from '../../common/types/AppError';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';
import { JsonKind, JsonNode } from '../../common/types/JsonNode';
import { JsonParser } from '../../common/utils/JsonParser';
import { Utf8 } from '../../common/utils/Utf8';
import { IdentityVersion } from '../../model/ProvisioningModels';
import type {
  IdentityLanDto,
  IdentitySecurityDto,
  IdentityV20Dto,
  IdentityV21Dto
} from './dto/IdentityDto';
import { ProtocolErrors } from './ProtocolErrors';

const IDENTITY_FIELDS: ReadonlyArray<string> = [
  'protocolVersion', 'serviceId', 'gatewayId', 'gatewayName'
];

const V21_FIELDS: ReadonlyArray<string> = [
  'protocolVersion', 'serviceId', 'gatewayId', 'gatewayName', 'security'
];

export class IdentityParser {
  static parseV20(body: Uint8Array): IdentityV20Dto {
    try {
      const root = IdentityParser.parseRoot(body);
      IdentityParser.rejectUnknown(root, IDENTITY_FIELDS);
      const protocolVersion = IdentityParser.requiredString(root, 'protocolVersion');
      const serviceId = IdentityParser.requiredString(root, 'serviceId');
      const gatewayId = IdentityParser.requiredString(root, 'gatewayId');
      const gatewayName = IdentityParser.requiredString(root, 'gatewayName');
      if (protocolVersion !== ProtocolConstants.PROTOCOL_VERSION_20 ||
        serviceId !== ProtocolConstants.SERVICE_ID_IDENTITY) {
        throw ProtocolErrors.identityInvalid('constants');
      }
      IdentityParser.validateGatewayId(gatewayId);
      IdentityParser.validateGatewayName(gatewayName);
      const dto: IdentityV20Dto = {
        protocolVersion: protocolVersion,
        serviceId: serviceId,
        gatewayId: gatewayId,
        gatewayName: gatewayName
      };
      return dto;
    } catch (error) {
      throw IdentityParser.asIdentityError(error);
    }
  }

  static parseV21(body: Uint8Array): IdentityV21Dto {
    try {
      const root = IdentityParser.parseRoot(body);
      IdentityParser.rejectUnknown(root, V21_FIELDS);
      const protocolVersion = IdentityParser.requiredString(root, 'protocolVersion');
      const serviceId = IdentityParser.requiredString(root, 'serviceId');
      const gatewayId = IdentityParser.requiredString(root, 'gatewayId');
      const gatewayName = IdentityParser.requiredString(root, 'gatewayName');
      if (protocolVersion !== ProtocolConstants.PROTOCOL_VERSION_21 ||
        serviceId !== ProtocolConstants.SERVICE_ID_IDENTITY) {
        throw ProtocolErrors.identityInvalid('constants');
      }
      IdentityParser.validateGatewayId(gatewayId);
      IdentityParser.validateGatewayName(gatewayName);
      let security: IdentitySecurityDto | undefined = undefined;
      if (root.has('security')) {
        security = IdentityParser.parseSecurity(root.require('security'));
      }
      const dto: IdentityV21Dto = {
        protocolVersion: protocolVersion,
        serviceId: serviceId,
        gatewayId: gatewayId,
        gatewayName: gatewayName,
        security: security
      };
      return dto;
    } catch (error) {
      throw IdentityParser.asIdentityError(error);
    }
  }

  static serializeRequest(version: IdentityVersion): Uint8Array {
    return Utf8.encode('{"op":"get_identity","protocolVersion":"' + version + '"}');
  }

  private static parseSecurity(node: JsonNode): IdentitySecurityDto {
    if (node.kind !== JsonKind.OBJECT) {
      throw ProtocolErrors.identityInvalid('security');
    }
    IdentityParser.rejectUnknown(node, ['lan']);
    if (!node.has('lan')) {
      const empty: IdentitySecurityDto = {};
      return empty;
    }
    const lanNode = node.require('lan');
    if (lanNode.kind !== JsonKind.OBJECT) {
      throw ProtocolErrors.identityInvalid('security.lan');
    }
    IdentityParser.rejectUnknown(lanNode, ['tls', 'port', 'pins', 'pinAlg']);
    const tlsNode = lanNode.require('tls');
    if (tlsNode.kind !== JsonKind.BOOLEAN) {
      throw ProtocolErrors.identityInvalid('security.lan.tls');
    }
    const tls = tlsNode.booleanValue;
    if (!tls) {
      if (lanNode.has('port') || lanNode.has('pins') || lanNode.has('pinAlg')) {
        throw ProtocolErrors.identityInvalid('security.lan');
      }
      const lanOff: IdentityLanDto = { tls: false };
      const securityOff: IdentitySecurityDto = { lan: lanOff };
      return securityOff;
    }
    const port = IdentityParser.requiredInteger(lanNode, 'port');
    if (port < 1 || port > 65535) {
      throw ProtocolErrors.identityInvalid('security.lan.port');
    }
    const pinsNode = lanNode.require('pins');
    if (pinsNode.kind !== JsonKind.ARRAY || pinsNode.arrayValue.length < 1 ||
      pinsNode.arrayValue.length > ProtocolConstants.MAX_PIN_COUNT) {
      throw ProtocolErrors.identityInvalid('security.lan.pins');
    }
    const pins: string[] = [];
    for (let index = 0; index < pinsNode.arrayValue.length; index++) {
      const pinNode = pinsNode.arrayValue[index];
      if (pinNode.kind !== JsonKind.STRING || !ProtocolConstants.PIN_PATTERN.test(pinNode.stringValue)) {
        throw ProtocolErrors.identityInvalid('security.lan.pins');
      }
      pins.push(pinNode.stringValue);
    }
    const pinAlg = IdentityParser.requiredString(lanNode, 'pinAlg');
    if (pinAlg !== 'sha256-spki-der') {
      throw ProtocolErrors.identityInvalid('security.lan.pinAlg');
    }
    const lanOn: IdentityLanDto = { tls: true, port: port, pins: pins, pinAlg: pinAlg };
    const securityOn: IdentitySecurityDto = { lan: lanOn };
    return securityOn;
  }

  private static parseRoot(body: Uint8Array): JsonNode {
    const root = JsonParser.parse(Utf8.decode(body));
    if (root.kind !== JsonKind.OBJECT) {
      throw ProtocolErrors.identityInvalid('envelope');
    }
    return root;
  }

  private static rejectUnknown(node: JsonNode, allowed: ReadonlyArray<string>): void {
    const keys = node.keys();
    for (let index = 0; index < keys.length; index++) {
      if (allowed.indexOf(keys[index]) < 0) {
        throw ProtocolErrors.identityInvalid(keys[index]);
      }
    }
  }

  private static requiredString(node: JsonNode, field: string): string {
    const value = node.require(field);
    if (value.kind !== JsonKind.STRING) {
      throw ProtocolErrors.identityInvalid(field);
    }
    return value.stringValue;
  }

  private static requiredInteger(node: JsonNode, field: string): number {
    const value = node.require(field);
    if (value.kind !== JsonKind.NUMBER || !Number.isInteger(value.numberValue)) {
      throw ProtocolErrors.identityInvalid(field);
    }
    return value.numberValue;
  }

  private static validateGatewayId(value: string): void {
    if (value.length === 0 || value.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      value.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(value)) {
      throw ProtocolErrors.identityInvalid('gatewayId');
    }
  }

  private static validateGatewayName(value: string): void {
    if (value.length === 0 || value.length > ProtocolConstants.MAX_GATEWAY_NAME_LENGTH) {
      throw ProtocolErrors.identityInvalid('gatewayName');
    }
  }

  private static asIdentityError(error: Object): AppError {
    if (error instanceof AppError && error.code === 'PROVISIONING_IDENTITY_INVALID') {
      return error;
    }
    return ProtocolErrors.identityInvalid('body');
  }
}
