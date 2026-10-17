/*
 * YaoCore C-03 local control request serializer.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §6.1.3, §18.1
 *
 * The serializer validates and serializes an already-signed request. It does
 * NOT compute HMAC. T-07 owns signing (HmacSignerPort).
 */
import { AppErrors } from '../../common/types/AppError';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';
import { ActionValueKind, DeviceAction, DeviceConstants } from '../../common/constants/DeviceConstants';
import { JsonNode, NameValueNode } from '../../common/types/JsonNode';
import { JsonAtom } from '../../common/utils/JsonAtom';
import type { CommandValue } from '../../common/utils/JsonAtom';
import { JsonCanonicalizer } from '../../common/utils/JsonCanonicalizer';
import { Utf8 } from '../../common/utils/Utf8';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import type { ControlPayloadDto, ControlRequestDto } from './dto/ControlRequestDto';

const COLOR_PATTERN: RegExp = /^#[0-9A-F]{6}$/;

export class ControlRequestSerializer {
  static toJsonNode(request: ControlRequestDto): JsonNode {
    ControlRequestSerializer.validate(request);
    const entries: NameValueNode[] = [];
    entries.push(new NameValueNode('request_id', JsonNode.string(request.request_id)));
    entries.push(new NameValueNode('cmd_id', JsonNode.number(request.cmd_id)));
    entries.push(new NameValueNode('seq', JsonNode.number(request.seq)));
    entries.push(new NameValueNode('target', JsonNode.string(request.target)));
    entries.push(new NameValueNode('payload', ControlRequestSerializer.payloadNode(request.payload)));
    entries.push(new NameValueNode('timestamp', JsonNode.string(request.timestamp)));
    entries.push(new NameValueNode('nonce', JsonNode.string(request.nonce)));
    entries.push(new NameValueNode('alg', JsonNode.string(request.alg)));
    entries.push(new NameValueNode('key_id', JsonNode.string(request.key_id)));
    entries.push(new NameValueNode('sign', JsonNode.string(request.sign)));
    return JsonNode.object(entries);
  }

  static serialize(request: ControlRequestDto): Uint8Array {
    return Utf8.encode(JsonCanonicalizer.stringify(ControlRequestSerializer.toJsonNode(request), false));
  }

  private static payloadNode(payload: ControlPayloadDto): JsonNode {
    const entries: NameValueNode[] = [];
    entries.push(new NameValueNode('action', JsonNode.string(payload.action)));
    if (payload.value !== undefined) {
      entries.push(new NameValueNode('value', ControlRequestSerializer.valueNode(payload.value)));
    }
    return JsonNode.object(entries);
  }

  private static valueNode(value: string | number | boolean): JsonNode {
    if (typeof value === 'string') {
      JsonAtom.normalizeString(value);
      return JsonNode.string(value);
    }
    if (typeof value === 'number') {
      if (!Number.isFinite(value)) {
        throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'value');
      }
      return JsonNode.number(value);
    }
    return JsonNode.boolean(value);
  }

  private static validate(request: ControlRequestDto): void {
    if (!ProtocolConstants.REQUEST_ID_PATTERN.test(request.request_id) ||
      request.request_id.length > ProtocolConstants.MAX_REQUEST_ID_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'request_id');
    }
    if (request.cmd_id !== ProtocolConstants.CMD_ID_CONTROL) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'cmd_id');
    }
    if (!Number.isInteger(request.seq) || request.seq < 0 ||
      request.seq > ProtocolConstants.MAX_SEQ) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'seq');
    }
    if (request.target.length === 0 || request.target.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      request.target.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(request.target)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'target');
    }
    if (!ProtocolConstants.ACTION_PATTERN.test(request.payload.action) ||
      request.payload.action.length > ProtocolConstants.MAX_ACTION_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'action');
    }
    ControlRequestSerializer.validateValue(request.payload.action, request.payload.value);
    DateTimeUtil.parseUtcCompact(request.timestamp);
    // DES-A §3.3/§18.5: App-generated outbound nonce is 16 random bytes as
    // 32 lowercase hex characters. The wire schema is looser; this serializer
    // is the last structural gate before signing.
    if (!ProtocolConstants.HEX_LOWER_32.test(request.nonce)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'nonce');
    }
    if (request.alg !== ProtocolConstants.ALG_HMAC_SHA256) {
      throw AppErrors.protocol('PROTOCOL_UNSUPPORTED_VERSION', 'alg');
    }
    if (request.key_id !== ProtocolConstants.KEY_ID_V1) {
      throw AppErrors.protocol('PROTOCOL_UNSUPPORTED_VERSION', 'key_id');
    }
    if (!ProtocolConstants.HEX_LOWER_64.test(request.sign)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'sign');
    }
  }

  private static validateValue(action: string, value: CommandValue | undefined): void {
    if (value === undefined) {
      return;
    }
    const kind = DeviceConstants.actionToValueKind(action as DeviceAction);
    if (kind === ActionValueKind.NONE) {
      throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'value');
    }
    if (kind === ActionValueKind.BOOLEAN) {
      if (typeof value !== 'boolean') {
        throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'value');
      }
      return;
    }
    if (kind === ActionValueKind.NUMBER) {
      if (typeof value !== 'number' || !Number.isFinite(value)) {
        throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'value');
      }
      if (action === DeviceAction.SET_BRIGHTNESS && (value < 0 || value > 100)) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'value');
      }
      if (action === DeviceAction.SET_TARGET_TEMPERATURE && (value < 16 || value > 30)) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'value');
      }
      if ((action === DeviceAction.SET_POSITION || action === DeviceAction.SET_SPEED ||
        action === DeviceAction.SET_VOLUME) && (value < 0 || value > 100)) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'value');
      }
      return;
    }
    if (typeof value !== 'string') {
      throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'value');
    }
    const maxLength = action === DeviceAction.SET_MODE ?
      ProtocolConstants.MAX_MODE_LENGTH_OUTBOUND : 63;
    if (value.length > maxLength) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'value');
    }
    if (kind === ActionValueKind.COLOR && !COLOR_PATTERN.test(value)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'value');
    }
    // Reject lone surrogates before they reach JSON encoding.
    JsonAtom.normalizeString(value);
  }
}
