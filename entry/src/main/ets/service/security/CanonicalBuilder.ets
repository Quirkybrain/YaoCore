/*
 * YaoCore C-05 canonical string builders.
 * Producer: agent:implementation-engineer | Task: T-07 / wp-016-security
 * Contract: DES-A §8.1.1, §18.1, §18.2, §18.3
 *
 * Builders concatenate only: field semantics are validated by C-03/callers.
 * Line-safety (empty required field, unescaped LF/CR) is enforced here because
 * an injected line break would change the signed byte stream (DES-A §8.3-1).
 */
import { AppErrors } from '../../common/types/AppError';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';

export enum ResponseKind {
  DISCOVER = 'discover',
  CONTROL = 'control'
}

export class ControlCanonicalFields {
  readonly requestId: string;
  readonly cmdId: number;
  readonly seq: number;
  readonly target: string;
  readonly action: string;
  readonly valueText: string; // JsonAtom.encode(value); absent -> ''
  readonly timestamp: string;
  readonly nonce: string;
  readonly alg: string;
  readonly keyId: string;

  constructor(requestId: string, cmdId: number, seq: number, target: string, action: string,
    valueText: string, timestamp: string, nonce: string, alg: string, keyId: string) {
    this.requestId = requestId;
    this.cmdId = cmdId;
    this.seq = seq;
    this.target = target;
    this.action = action;
    this.valueText = valueText;
    this.timestamp = timestamp;
    this.nonce = nonce;
    this.alg = alg;
    this.keyId = keyId;
  }
}

export class DiscoverCanonicalFields {
  readonly challenge: string;
  readonly timestamp: string;
  readonly nonce: string;
  readonly alg: string;
  readonly keyId: string;

  constructor(challenge: string, timestamp: string, nonce: string, alg: string, keyId: string) {
    this.challenge = challenge;
    this.timestamp = timestamp;
    this.nonce = nonce;
    this.alg = alg;
    this.keyId = keyId;
  }
}

export class CloudCanonicalFields {
  readonly requestId: string;
  readonly cmdId: number;
  readonly seq: number;
  readonly targetDevice: string;
  readonly action: string;
  readonly valueText: string;
  readonly timestamp: string;
  readonly nonce: string;
  readonly alg: string;
  readonly keyId: string;

  constructor(requestId: string, cmdId: number, seq: number, targetDevice: string, action: string,
    valueText: string, timestamp: string, nonce: string, alg: string, keyId: string) {
    this.requestId = requestId;
    this.cmdId = cmdId;
    this.seq = seq;
    this.targetDevice = targetDevice;
    this.action = action;
    this.valueText = valueText;
    this.timestamp = timestamp;
    this.nonce = nonce;
    this.alg = alg;
    this.keyId = keyId;
  }
}

export class CanonicalBuilder {
  /** 10 lines, LF separated, no trailing newline (DES-A §18.1). */
  static control(fields: ControlCanonicalFields): string {
    const lines: string[] = [
      CanonicalBuilder.required(fields.requestId, 'request_id'),
      CanonicalBuilder.integer(fields.cmdId, 'cmd_id'),
      CanonicalBuilder.integer(fields.seq, 'seq'),
      CanonicalBuilder.required(fields.target, 'target'),
      CanonicalBuilder.required(fields.action, 'action'),
      CanonicalBuilder.line(fields.valueText, 'value'),
      CanonicalBuilder.required(fields.timestamp, 'timestamp'),
      CanonicalBuilder.required(fields.nonce, 'nonce'),
      CanonicalBuilder.required(fields.alg, 'alg'),
      CanonicalBuilder.required(fields.keyId, 'key_id')
    ];
    return lines.join('\n');
  }

  /** 6 lines, first line YAOCORE-DISCOVER-V2 (DES-A §18.2). */
  static discover(fields: DiscoverCanonicalFields): string {
    const lines: string[] = [
      ProtocolConstants.CANONICAL_DISCOVER_TAG,
      CanonicalBuilder.required(fields.challenge, 'challenge'),
      CanonicalBuilder.required(fields.timestamp, 'timestamp'),
      CanonicalBuilder.required(fields.nonce, 'nonce'),
      CanonicalBuilder.required(fields.alg, 'alg'),
      CanonicalBuilder.required(fields.keyId, 'key_id')
    ];
    return lines.join('\n');
  }

  /** 4 lines, first line YAOCORE-RESPONSE-V1 (DES-A §18.3). */
  static response(kind: ResponseKind, correlation: string, bodySha256Hex: string): string {
    if (kind !== ResponseKind.DISCOVER && kind !== ResponseKind.CONTROL) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'kind');
    }
    if (!ProtocolConstants.HEX_LOWER_64.test(bodySha256Hex)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'bodySha256');
    }
    const lines: string[] = [
      ProtocolConstants.CANONICAL_RESPONSE_TAG,
      kind,
      CanonicalBuilder.required(correlation, 'correlation'),
      bodySha256Hex
    ];
    return lines.join('\n');
  }

  /** 10 lines using cloud field names; C-15 consumes (CB §2.4). */
  static cloudCommand(fields: CloudCanonicalFields): string {
    const lines: string[] = [
      CanonicalBuilder.required(fields.requestId, 'RequestId'),
      CanonicalBuilder.integer(fields.cmdId, 'CmdId'),
      CanonicalBuilder.integer(fields.seq, 'Seq'),
      CanonicalBuilder.required(fields.targetDevice, 'TargetDevice'),
      CanonicalBuilder.required(fields.action, 'Action'),
      CanonicalBuilder.line(fields.valueText, 'Value'),
      CanonicalBuilder.required(fields.timestamp, 'Timestamp'),
      CanonicalBuilder.required(fields.nonce, 'Nonce'),
      CanonicalBuilder.required(fields.alg, 'Alg'),
      CanonicalBuilder.required(fields.keyId, 'KeyId')
    ];
    return lines.join('\n');
  }

  private static required(value: string, field: string): string {
    if (value.length === 0) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', field);
    }
    return CanonicalBuilder.line(value, field);
  }

  private static line(value: string, field: string): string {
    if (value.indexOf('\n') >= 0 || value.indexOf('\r') >= 0) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', field);
    }
    return value;
  }

  private static integer(value: number, field: string): string {
    if (!Number.isInteger(value) || value < 0 || value > ProtocolConstants.MAX_SEQ) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', field);
    }
    return String(value);
  }
}
