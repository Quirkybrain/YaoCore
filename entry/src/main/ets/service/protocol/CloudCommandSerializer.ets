/*
 * YaoCore C-03 IoTDA cloud command envelope serializer.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-B §8.1.4/§8.1.4 body table, PR-09, cloud-command.schema.json
 *
 * Envelope: service_id + command_name + paras (10 signed fields). No
 * object_device_id. `Value` is a JSON string carrying compact atom text.
 * HMAC and canonical construction are T-07/T-14 responsibilities.
 */
import { AppErrors } from '../../common/types/AppError';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';
import { JsonKind, JsonNode, NameValueNode } from '../../common/types/JsonNode';
import { JsonParser } from '../../common/utils/JsonParser';
import { JsonCanonicalizer } from '../../common/utils/JsonCanonicalizer';
import { Utf8 } from '../../common/utils/Utf8';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import type { CloudCommandDto, CloudCommandParasDto } from './dto/CloudDto';

export class CloudCommandSerializer {
  static toJsonNode(envelope: CloudCommandDto): JsonNode {
    CloudCommandSerializer.validate(envelope);
    const paras = CloudCommandSerializer.parasNode(envelope.paras);
    const entries: NameValueNode[] = [];
    entries.push(new NameValueNode('service_id', JsonNode.string(envelope.service_id)));
    entries.push(new NameValueNode('command_name', JsonNode.string(envelope.command_name)));
    entries.push(new NameValueNode('paras', paras));
    return JsonNode.object(entries);
  }

  static serialize(envelope: CloudCommandDto): Uint8Array {
    return Utf8.encode(JsonCanonicalizer.stringify(CloudCommandSerializer.toJsonNode(envelope), false));
  }

  private static parasNode(paras: CloudCommandParasDto): JsonNode {
    const entries: NameValueNode[] = [];
    entries.push(new NameValueNode('RequestId', JsonNode.string(paras.RequestId)));
    entries.push(new NameValueNode('CmdId', JsonNode.number(paras.CmdId)));
    entries.push(new NameValueNode('Seq', JsonNode.number(paras.Seq)));
    entries.push(new NameValueNode('TargetDevice', JsonNode.string(paras.TargetDevice)));
    entries.push(new NameValueNode('Action', JsonNode.string(paras.Action)));
    if (paras.Value !== undefined) {
      entries.push(new NameValueNode('Value', JsonNode.string(paras.Value)));
    }
    entries.push(new NameValueNode('Timestamp', JsonNode.string(paras.Timestamp)));
    entries.push(new NameValueNode('Nonce', JsonNode.string(paras.Nonce)));
    entries.push(new NameValueNode('Alg', JsonNode.string(paras.Alg)));
    entries.push(new NameValueNode('KeyId', JsonNode.string(paras.KeyId)));
    entries.push(new NameValueNode('Sign', JsonNode.string(paras.Sign)));
    return JsonNode.object(entries);
  }

  private static validate(envelope: CloudCommandDto): void {
    if (envelope.service_id !== ProtocolConstants.SERVICE_ID_CLOUD) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'service_id');
    }
    if (envelope.command_name !== 'SetDeviceStatus') {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'command_name');
    }
    const paras = envelope.paras;
    if (!ProtocolConstants.REQUEST_ID_PATTERN.test(paras.RequestId) ||
      paras.RequestId.length > ProtocolConstants.MAX_REQUEST_ID_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'RequestId');
    }
    if (paras.CmdId !== ProtocolConstants.CMD_ID_CLOUD) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'CmdId');
    }
    if (!Number.isInteger(paras.Seq) || paras.Seq < 0 || paras.Seq > ProtocolConstants.MAX_SEQ) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'Seq');
    }
    if (paras.TargetDevice.length === 0 ||
      paras.TargetDevice.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      paras.TargetDevice.indexOf(':') >= 0 ||
      !ProtocolConstants.DEVICE_ID_PATTERN.test(paras.TargetDevice)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'TargetDevice');
    }
    if (!ProtocolConstants.ACTION_PATTERN.test(paras.Action) ||
      paras.Action.length > ProtocolConstants.MAX_ACTION_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'Action');
    }
    if (paras.Value !== undefined) {
      if (paras.Value.length === 0 || paras.Value.length > 63) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'Value');
      }
      const valueNode = JsonParser.parse(paras.Value);
      if (valueNode.kind !== JsonKind.STRING && valueNode.kind !== JsonKind.NUMBER &&
        valueNode.kind !== JsonKind.BOOLEAN) {
        throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'Value');
      }
      const canonicalValue = JsonCanonicalizer.stringify(valueNode, false);
      if (canonicalValue !== paras.Value) {
        throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'Value');
      }
    }
    DateTimeUtil.parseUtcCompact(paras.Timestamp);
    if (!ProtocolConstants.NONCE_PATTERN.test(paras.Nonce)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'Nonce');
    }
    if (paras.Alg !== ProtocolConstants.ALG_HMAC_SHA256) {
      throw AppErrors.protocol('PROTOCOL_UNSUPPORTED_VERSION', 'Alg');
    }
    if (paras.KeyId !== ProtocolConstants.KEY_ID_V1) {
      throw AppErrors.protocol('PROTOCOL_UNSUPPORTED_VERSION', 'KeyId');
    }
    if (!ProtocolConstants.HEX_LOWER_64.test(paras.Sign)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'Sign');
    }
  }
}
