/*
 * Pure protocol canonicalization oracle for host tests.
 * Producer: agent:test-engineer | Task: T-05 / wp-010-test-plan
 *
 * This file is deliberately free of @ohos.* and ArkUI syntax so it can be
 * imported by:
 *   1) the Node host runner via entry/src/test/host/ets-hooks.mjs; and
 *   2) ArkTS host tests as a pure logic reference.
 *
 * It is a TEST ORACLE, not product code. T-06/T-07 must compare the product
 * implementation against these vectors, not call this file in production.
 */

export interface ControlPayload {
  action: string;
  value?: string | number | boolean;
}

export interface ControlPacket {
  request_id: string;
  cmd_id: number;
  seq: number;
  target: string;
  payload: ControlPayload;
  timestamp: string;
  nonce: string;
  alg: string;
  key_id: string;
  sign?: string;
}

/** Encode a command value as one compact JSON atom (protocol README). */
export function valueAtom(value: string | number | boolean | undefined): string {
  if (value === undefined) {
    return '';
  }
  if (typeof value === 'string') {
    return JSON.stringify(value);
  }
  if (typeof value === 'boolean') {
    return value ? 'true' : 'false';
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return JSON.stringify(value);
  }
  throw new Error('value must be a string, finite number, or boolean');
}

/** Build the 10-line UTF-8 control canonical string (no trailing newline). */
export function controlCanonical(packet: ControlPacket): string {
  const lines: string[] = [
    String(packet.request_id),
    String(packet.cmd_id),
    String(packet.seq),
    String(packet.target),
    String(packet.payload.action),
    valueAtom(packet.payload.value),
    String(packet.timestamp),
    String(packet.nonce),
    String(packet.alg),
    String(packet.key_id),
  ];
  return lines.join('\n');
}

/** Build the discovery request canonical string (no trailing newline). */
export function discoveryCanonical(
  challenge: string,
  timestamp: string,
  nonce: string,
  alg: string,
  keyId: string,
): string {
  return [
    'YAOCORE-DISCOVER-V2',
    challenge,
    timestamp,
    nonce,
    alg,
    keyId,
  ].join('\n');
}

/** Build the response authentication canonical string (no trailing newline). */
export function responseCanonical(
  kind: string,
  correlation: string,
  bodySha256: string,
): string {
  return [
    'YAOCORE-RESPONSE-V1',
    kind,
    correlation,
    bodySha256,
  ].join('\n');
}
