/*
 * YaoCore C-19 protobuf/protocomm codec host tests.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Traceability: DES-A §16.5; BLE设计 §4.3/§5; TEST-001 V-10.
 *
 * PUBLIC TEST DATA ONLY. Vectors are copied from the frozen BLE design
 * document (input/existing/docs/BLE配网设计.md L118-129, L145-147).
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { AppError } from '../../main/ets/common/types/AppError.ets';
import { ProtobufReader, ProtobufWriter } from '../../main/ets/service/ble/Protobuf.ets';
import {
  ProtocommCodec,
  WifiConfig,
  WifiConnectFailedReason,
  WifiStationState,
  WifiStatus,
} from '../../main/ets/service/ble/ProtocommCodec.ets';
import {
  encodeSessionResponse0,
  encodeSessionResponse1,
  encodeWifiStatus,
  fieldBytes,
  fieldVarint,
  hex,
  readFields,
  utf8,
} from './BleFakes.mjs';

const expectCode = (fn, code) => {
  assert.throws(fn, (error) => {
    assert.ok(error instanceof AppError, 'expected AppError');
    assert.equal(error.code, code);
    return true;
  });
};

test('C19_ProtocommCodec_step0MatchesFrozenVector', () => {
  const publicKey = new Uint8Array(32);
  for (let index = 0; index < 32; index++) {
    publicKey[index] = index;
  }
  assert.equal(hex(ProtocommCodec.encodeSessionDataStep0(publicKey)),
    '10015a25a201220a20000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f');
});

test('C19_ProtocommCodec_wifiConfigAndScanFramesMatchFrozenVectors', () => {
  assert.equal(hex(ProtocommCodec.encodeGetStatus()), '5200');
  assert.equal(hex(ProtocommCodec.encodeApplyConfig()), '08047200');
  assert.equal(hex(ProtocommCodec.encodeScanStart()), '52080801100018002078');
  assert.equal(hex(ProtocommCodec.encodeScanStatus()), '08026200');
  assert.equal(hex(ProtocommCodec.encodeScanResult(0, 4)), '0804720408001004');
});

test('C19_ProtocommCodec_negativeRssiUsesTenByteTwosComplement', () => {
  const writer = new ProtobufWriter();
  writer.int32(3, -100);
  assert.equal(hex(writer.toBytes()), '189cffffffffffffffff01');
  const reader = new ProtobufReader(writer.toBytes());
  const tag = reader.readTag();
  assert.equal(tag.fieldNumber, 3);
  assert.equal(reader.readInt32(), -100);
});

test('C19_ProtocommCodec_scanResultDecodesNegativeRssiAndBssid', () => {
  const entry = new ProtobufWriter();
  entry.bytes(1, utf8('home-wifi'));
  entry.varint(2, 6);
  entry.int32(3, -100);
  entry.bytes(4, new Uint8Array([0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0x01]));
  entry.varint(5, 3);
  const response = new ProtobufWriter();
  response.varint(1, 5);
  const entries = new ProtobufWriter();
  entries.message(1, entry);
  response.message(15, entries);
  const decoded = ProtocommCodec.decodeScanResult(response.toBytes());
  assert.equal(decoded.length, 1);
  assert.equal(Buffer.from(decoded[0].ssid).toString('utf8'), 'home-wifi');
  assert.equal(decoded[0].rssi, -100);
  assert.equal(decoded[0].channel, 6);
  assert.equal(decoded[0].auth, 3);
});

test('C19_ProtocommCodec_setConfigRoundTripsSsidAndPassphrase', () => {
  const encoded = ProtocommCodec.encodeSetConfig(
    new WifiConfig('home-wifi', utf8('password')));
  const envelope = readFields(encoded);
  assert.equal(fieldVarint(envelope, 1), 2);
  const command = readFields(fieldBytes(envelope, 12));
  assert.equal(Buffer.from(fieldBytes(command, 1)).toString('utf8'), 'home-wifi');
  assert.equal(Buffer.from(fieldBytes(command, 2)).toString('utf8'), 'password');
});

test('C19_ProtocommCodec_sessionStep0ResponseDecodesRawKeys', () => {
  const devicePublic = new Uint8Array(32).fill(9);
  const deviceRandom = new Uint8Array(16).fill(4);
  const decoded = ProtocommCodec.decodeSessionDataStep0(
    encodeSessionResponse0(devicePublic, deviceRandom));
  assert.equal(decoded.secVer, 1);
  assert.equal(hex(decoded.devicePubKey), hex(devicePublic));
  assert.equal(hex(decoded.deviceRandom), hex(deviceRandom));
});

test('C19_ProtocommCodec_sessionStep1ResponseDecodesVerifyData', () => {
  const verify = new Uint8Array(32).fill(0x5a);
  const decoded = ProtocommCodec.decodeSessionDataStep1(encodeSessionResponse1(verify));
  assert.equal(hex(decoded.deviceVerifyData), hex(verify));
});

test('C19_ProtocommCodec_sessionRejectsWrongStatusAndLengths', () => {
  expectCode(() => ProtocommCodec.decodeSessionDataStep0(
    encodeSessionResponse0(new Uint8Array(31), new Uint8Array(16))),
  'PROVISIONING_SECURITY_HANDSHAKE_FAILED');
  expectCode(() => ProtocommCodec.decodeSessionDataStep0(
    encodeSessionResponse0(new Uint8Array(32), new Uint8Array(15))),
  'PROVISIONING_SECURITY_HANDSHAKE_FAILED');
  expectCode(() => ProtocommCodec.decodeSessionDataStep0(
    encodeSessionResponse0(new Uint8Array(32), new Uint8Array(16), 6)),
  'PROVISIONING_SECURITY_HANDSHAKE_FAILED');
  expectCode(() => ProtocommCodec.decodeSessionDataStep1(
    encodeSessionResponse1(new Uint8Array(31))),
  'PROVISIONING_SECURITY_HANDSHAKE_FAILED');
});

test('C19_ProtocommCodec_scanStatusAndResultsAreStrict', () => {
  const status = new ProtobufWriter();
  status.varint(1, 3);
  const body = new ProtobufWriter();
  body.bool(1, true);
  body.varint(2, 7);
  status.message(13, body);
  const decoded = ProtocommCodec.decodeScanStatus(status.toBytes());
  assert.equal(decoded.scanFinished, true);
  assert.equal(decoded.resultCount, 7);

  const wrongMessage = new ProtobufWriter();
  wrongMessage.varint(1, 2);
  wrongMessage.message(13, body);
  expectCode(() => ProtocommCodec.decodeScanStatus(wrongMessage.toBytes()),
    'PROVISIONING_WIFI_SCAN_FAILED');

  const truncatedEntry = new ProtobufWriter();
  truncatedEntry.bytes(1, utf8('home-wifi'));
  truncatedEntry.varint(2, 6);
  truncatedEntry.varint(3, 0);
  truncatedEntry.bytes(4, new Uint8Array([1, 2]));
  const response = new ProtobufWriter();
  response.varint(1, 5);
  const entries = new ProtobufWriter();
  entries.message(1, truncatedEntry);
  response.message(15, entries);
  expectCode(() => ProtocommCodec.decodeScanResult(response.toBytes()),
    'PROVISIONING_WIFI_SCAN_FAILED');
});

test('C19_ProtocommCodec_wifiStatusClassifiesEveryTerminalState', () => {
  assert.equal(ProtocommCodec.decodeWifiStatus(encodeWifiStatus(
    { state: 'connected', ip: '192.168.1.50' })).state, WifiStationState.CONNECTED);
  assert.equal(ProtocommCodec.decodeWifiStatus(encodeWifiStatus(
    { state: 'connecting' })).state, WifiStationState.CONNECTING);
  const auth = ProtocommCodec.decodeWifiStatus(encodeWifiStatus(
    { state: 'failed', reason: 'auth' }));
  assert.equal(auth.state, WifiStationState.CONNECTION_FAILED);
  assert.equal(auth.failReason, WifiConnectFailedReason.AUTH_ERROR);
  const missing = ProtocommCodec.decodeWifiStatus(encodeWifiStatus(
    { state: 'failed', reason: 'network' }));
  assert.equal(missing.failReason, WifiConnectFailedReason.NETWORK_NOT_FOUND);
});

test('C19_ProtocommCodec_wifiStatusRejectsInvalidAddressAndState', () => {
  expectCode(() => new WifiStatus(WifiStationState.CONNECTED, undefined, '999.1.1.1'),
    'PROVISIONING_SECURITY_HANDSHAKE_FAILED');
  expectCode(() => new WifiStatus(WifiStationState.CONNECTED, undefined, ''),
    'PROVISIONING_SECURITY_HANDSHAKE_FAILED');
  const payload = new ProtobufWriter();
  payload.varint(1, 1);
  const body = new ProtobufWriter();
  body.varint(1, 0);
  body.varint(2, 9);
  payload.message(11, body);
  expectCode(() => ProtocommCodec.decodeWifiStatus(payload.toBytes()),
    'PROVISIONING_SECURITY_HANDSHAKE_FAILED');
});

test('C19_ProtobufReader_rejectsTruncationOverlongAndBadWireTypes', () => {
  expectCode(() => {
    const reader = new ProtobufReader(new Uint8Array([0x0a, 0x05, 0x01]));
    reader.readTag();
    reader.readBytes();
  }, 'PROTOCOL_INVALID_JSON');
  expectCode(() => {
    const reader = new ProtobufReader(new Uint8Array(11).fill(0x80));
    reader.readUnsigned();
  }, 'PROTOCOL_INVALID_JSON');
  expectCode(() => {
    const reader = new ProtobufReader(new Uint8Array([0x0b]));
    reader.readTag();
  }, 'PROTOCOL_INVALID_JSON');
  expectCode(() => {
    const reader = new ProtobufReader(new Uint8Array([0x0a, 0xff, 0x01, 0x00]));
    reader.readTag();
    reader.readBytes();
  }, 'PROTOCOL_INVALID_JSON');
  expectCode(() => new ProtobufWriter().varint(0, 1), 'PROTOCOL_INVALID_JSON');
  expectCode(() => new ProtobufWriter().varint(1, -1), 'PROTOCOL_INVALID_JSON');
});

test('C19_ProtobufReader_rejectsLengthVarintAbove32Bits', () => {
  // Field 1, wire type 2, length varint = 2^32: the low 32 bits are zero, so
  // a low-bits-only reader would silently accept an empty field (F-11).
  expectCode(() => {
    const reader = new ProtobufReader(
      new Uint8Array([0x0a, 0x80, 0x80, 0x80, 0x80, 0x10]));
    reader.readTag();
    reader.readBytes();
  }, 'PROTOCOL_INVALID_JSON');
  // A full 10-byte length varint is likewise rejected, not truncated to 32 bits.
  expectCode(() => {
    const reader = new ProtobufReader(new Uint8Array([
      0x0a, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01,
    ]));
    reader.readTag();
    reader.readBytes();
  }, 'PROTOCOL_INVALID_JSON');
  // A legitimate small length still round-trips.
  const writer = new ProtobufWriter();
  writer.bytes(1, utf8('ok'));
  const reader = new ProtobufReader(writer.toBytes());
  reader.readTag();
  assert.equal(Buffer.from(reader.readBytes()).toString('utf8'), 'ok');
});

test('C19_ProtobufReader_rejectsNonCanonicalLengthVarint', () => {
  // A 10-byte zero length is overlong and must not be accepted as 0 (R2-04).
  expectCode(() => {
    const reader = new ProtobufReader(new Uint8Array([
      0x0a, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x00,
    ]));
    reader.readTag();
    reader.readBytes();
  }, 'PROTOCOL_INVALID_JSON');
  // The same non-minimal rule applies to a short overlong encoding.
  expectCode(() => {
    const reader = new ProtobufReader(new Uint8Array([0x0a, 0x80, 0x00]));
    reader.readTag();
    reader.readBytes();
  }, 'PROTOCOL_INVALID_JSON');
});

test('C19_ProtocommCodec_customJsonHasNoFrameHeader', () => {
  const json = '{"op":"finish","protocolVersion":"2.0"}';
  assert.equal(hex(ProtocommCodec.encodeCustomJson(json)), hex(utf8(json)));
  assert.equal(ProtocommCodec.decodeCustomJson(utf8(json)), json);
});
