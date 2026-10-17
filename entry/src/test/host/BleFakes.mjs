/*
 * YaoCore T-12 BLE provisioning host fakes and protocol oracles.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 *
 * PUBLIC TEST DATA ONLY. This file uses Node crypto as an independent oracle
 * for X25519/SHA-256/AES-CTR and implements a deterministic ESP-IDF-style
 * gateway over the product protobuf codec. It is never imported by
 * entry/src/main/ets/**. No real PoP, Wi-Fi password or gateway identity is
 * present.
 */
import {
  createCipheriv,
  createHash,
  createPrivateKey,
  createPublicKey,
  diffieHellman,
  timingSafeEqual,
} from 'node:crypto';

import { AppErrors } from '../../main/ets/common/types/AppError.ets';
import { SecureBytes } from '../../main/ets/common/types/SecureBytes.ets';
import {
  BleProvisioningDevice,
  BleProvisioningRequest,
} from '../../main/ets/service/ble/BleProvisioningPorts.ets';
import { GattEndpointMap } from '../../main/ets/service/ble/GattEndpointMap.ets';
import { ProtobufReader, ProtobufWriter } from '../../main/ets/service/ble/Protobuf.ets';
import { X25519KeyPair } from '../../main/ets/service/crypto/CryptoPort.ets';
import {
  DiscoverySnapshot,
  DiscoverySnapshotInit,
} from '../../main/ets/model/DiscoveryModels.ets';
import {
  ControlOutcome,
  GatewayBoardState,
  StateVerification,
} from '../../main/ets/model/ControlModels.ets';
import { GatewayResultClassifier } from '../../main/ets/common/types/GatewayResult.ets';
import { ProbeResult } from '../../main/ets/service/gateway/GatewayTransportPorts.ets';
import { SecretDraftStore } from '../../main/ets/service/storage/SecretDraftStore.ets';
import { BleProvisioningService } from '../../main/ets/service/ble/BleProvisioningService.ets';

export const FIXED_MS = Date.UTC(2026, 9, 17, 8, 0, 0);
export const GATEWAY_ID = 'gateway_01';
export const GATEWAY_NAME = '客厅网关';
export const PIN = 'a'.repeat(64);
export const FAMILY_ID = 'family-01';
export const SECRET_HEX = '0123456789abcdef0123456789abcdef';

const PKCS8_PREFIX = Buffer.from('302e020100300506032b656e04220420', 'hex');
const SPKI_PREFIX = Buffer.from('302a300506032b656e032100', 'hex');

export const utf8 = (text) => new TextEncoder().encode(text);
export const hex = (bytes) => Buffer.from(bytes).toString('hex');
export const bytes = (value) => new Uint8Array(value);

function x25519PrivateFromRaw(raw) {
  return createPrivateKey({
    key: Buffer.concat([PKCS8_PREFIX, Buffer.from(raw)]),
    format: 'der',
    type: 'pkcs8',
  });
}

function x25519PublicFromRaw(raw) {
  return createPublicKey({
    key: Buffer.concat([SPKI_PREFIX, Buffer.from(raw)]),
    format: 'der',
    type: 'spki',
  });
}

function x25519PublicRaw(privateKey) {
  const jwk = createPublicKey(privateKey).export({ format: 'jwk' });
  return new Uint8Array(Buffer.from(jwk.x, 'base64url'));
}

export function x25519(privateKey, peerRaw) {
  return new Uint8Array(diffieHellman({
    privateKey,
    publicKey: x25519PublicFromRaw(peerRaw),
  }));
}

export function sha256(data) {
  return new Uint8Array(createHash('sha256').update(Buffer.from(data)).digest());
}

/** RFC 7748 §6.1 test vector, run through Node's independent X25519. */
export function rfc7748Vector() {
  const scalar = new Uint8Array(Buffer.from(
    'a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4', 'hex'));
  const u = new Uint8Array(Buffer.from(
    'e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c', 'hex'));
  const expected = 'c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552';
  return { actual: hex(x25519(x25519PrivateFromRaw(scalar), u)), expected };
}

/** CryptoPort implementation backed by Node crypto (independent oracle). */
export class NodeCryptoPort {
  constructor(privateRaw = new Uint8Array(32).fill(7)) {
    this.privateRaw = new Uint8Array(privateRaw);
    this.privateKey = x25519PrivateFromRaw(this.privateRaw);
    this.publicRaw = x25519PublicRaw(this.privateKey);
    this.keyPairCalls = 0;
  }

  async generateX25519KeyPair() {
    this.keyPairCalls++;
    // A fresh keypair per call: never reuse the previous Security1 identity.
    const raw = new Uint8Array(this.privateRaw);
    // X25519 clamps the low 3 bits of byte 0; use surviving bits and a high
    // byte so every generated keypair is distinct.
    raw[0] = (this.keyPairCalls * 8) & 0xff;
    raw[20] = this.keyPairCalls & 0xff;
    const privateKey = x25519PrivateFromRaw(raw);
    return new X25519KeyPair({ algorithm: 'X25519', keyObject: privateKey },
      x25519PublicRaw(privateKey));
  }

  async computeX25519(privateKey, peerPublicRaw) {
    return x25519(privateKey.keyObject, peerPublicRaw);
  }

  async sha256(data) {
    return sha256(data);
  }

  async hmacSha256() {
    throw AppErrors.of('CRYPTO_UNAVAILABLE', []);
  }

  async hkdfSha256() {
    throw AppErrors.of('CRYPTO_UNAVAILABLE', []);
  }

  async pbkdf2Sha256() {
    throw AppErrors.of('CRYPTO_UNAVAILABLE', []);
  }

  async importX25519PrivateRaw() {
    throw AppErrors.of('CRYPTO_UNAVAILABLE', []);
  }

  async importX25519PublicRaw() {
    throw AppErrors.of('CRYPTO_UNAVAILABLE', []);
  }

  async exportX25519PublicRaw() {
    throw AppErrors.of('CRYPTO_UNAVAILABLE', []);
  }

  async createAesCtrStream(key, iv) {
    const cipher = createCipheriv('aes-256-ctr', Buffer.from(key), Buffer.from(iv));
    let destroyed = false;
    let processed = 0;
    return {
      get state() {
        return destroyed ? 'DESTROYED' : 'ACTIVE';
      },
      get bytesProcessed() {
        return processed;
      },
      async process(data) {
        if (destroyed) {
          throw AppErrors.of('CRYPTO_STREAM_BROKEN', []);
        }
        const output = cipher.update(Buffer.from(data));
        processed += data.length;
        return new Uint8Array(output);
      },
      destroy() {
        destroyed = true;
      },
    };
  }

  async encryptAesGcm() {
    throw AppErrors.of('CRYPTO_UNAVAILABLE', []);
  }

  async decryptAesGcm() {
    throw AppErrors.of('CRYPTO_UNAVAILABLE', []);
  }

  async randomBytes(length) {
    return new Uint8Array(length).fill(9);
  }

  constantTimeEqual(left, right) {
    if (left.length !== right.length) {
      return false;
    }
    return timingSafeEqual(Buffer.from(left), Buffer.from(right));
  }
}

export function xorBytes(left, right) {
  const result = new Uint8Array(left.length);
  for (let index = 0; index < left.length; index++) {
    result[index] = left[index] ^ right[index];
  }
  return result;
}

export function readFields(payload) {
  const reader = new ProtobufReader(payload);
  const fields = [];
  while (reader.hasMore()) {
    const tag = reader.readTag();
    if (tag.wireType === 0) {
      fields.push({ field: tag.fieldNumber, wire: 0, value: reader.readUnsigned() });
    } else if (tag.wireType === 2) {
      fields.push({ field: tag.fieldNumber, wire: 2, value: reader.readBytes() });
    } else {
      reader.skip(tag);
    }
  }
  return fields;
}

export function fieldBytes(fields, number) {
  const found = fields.find((entry) => entry.field === number && entry.wire === 2);
  return found === undefined ? undefined : found.value;
}

export function fieldVarint(fields, number, fallback = 0) {
  const found = fields.find((entry) => entry.field === number && entry.wire === 0);
  return found === undefined ? fallback : found.value;
}

export function encodeSessionResponse0(devicePublicRaw, deviceRandom, status = 0) {
  const response = new ProtobufWriter();
  response.varint(1, status);
  response.bytes(2, devicePublicRaw);
  response.bytes(3, deviceRandom);
  const sec1 = new ProtobufWriter();
  sec1.varint(1, 1);
  sec1.message(21, response);
  const session = new ProtobufWriter();
  session.varint(2, 1);
  session.message(11, sec1);
  return session.toBytes();
}

export function encodeSessionResponse1(deviceVerifyData, status = 0) {
  const response = new ProtobufWriter();
  response.varint(1, status);
  response.bytes(3, deviceVerifyData);
  const sec1 = new ProtobufWriter();
  sec1.varint(1, 3);
  sec1.message(23, response);
  const session = new ProtobufWriter();
  session.varint(2, 1);
  session.message(11, sec1);
  return session.toBytes();
}

export function parseClientStep0(payload) {
  const session = readFields(payload);
  const sec1 = readFields(fieldBytes(session, 11));
  const command = readFields(fieldBytes(sec1, 20));
  return fieldBytes(command, 1);
}

export function parseClientStep1(payload) {
  const session = readFields(payload);
  const sec1 = readFields(fieldBytes(session, 11));
  const command = readFields(fieldBytes(sec1, 22));
  return fieldBytes(command, 2);
}

export function encodeWifiStatus(status) {
  const response = new ProtobufWriter();
  response.varint(1, 0);
  if (status.state === 'connected') {
    response.varint(2, 0);
    const connected = new ProtobufWriter();
    connected.string(1, status.ip);
    response.message(11, connected);
  } else if (status.state === 'connecting') {
    response.varint(2, 1);
  } else if (status.state === 'failed') {
    response.varint(2, 3);
    response.varint(10, status.reason === 'auth' ? 0 : 1);
  } else {
    response.varint(2, 2);
  }
  const payload = new ProtobufWriter();
  payload.varint(1, 1);
  payload.message(11, response);
  return payload.toBytes();
}

/**
 * Deterministic ESP-IDF-style gateway. It implements the device side of
 * Security1 with Node crypto and the product protobuf wire format.
 */
export class FakeGateway {
  constructor(options = {}) {
    this.identityMode = options.identityMode ?? 'v21';
    this.pop = options.pop ?? 'pop';
    this.privateKey = x25519PrivateFromRaw(new Uint8Array(32).fill(options.keySeed ?? 11));
    this.publicRaw = x25519PublicRaw(this.privateKey);
    this.deviceRandom = new Uint8Array(16).fill(3);
    this.cipher = undefined;
    this.clientPublic = undefined;
    this.expectedClientVerify = undefined;
    this.established = false;
    this.requests = [];
    this.identityRequests = [];
    this.scanPolls = options.scanPolls ?? 1;
    this.aps = options.aps ?? [
      { ssid: 'home-wifi', bssid: [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0x01], channel: 6, rssi: -45, auth: 3 },
      { ssid: 'neighbour', bssid: [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0x02], channel: 11, rssi: -80, auth: 3 },
    ];
    this.statusSequence = options.statusSequence ?? [{ state: 'connected', ip: '192.168.1.50' }];
    this.statusIndex = 0;
    this.config = undefined;
    this.applied = false;
    this.doneBody = options.doneBody ?? utf8('{"status":"accepted","protocolVersion":"2.0"}');
    this.tamperDeviceVerify = options.tamperDeviceVerify ?? false;
    this.protoVerBody = options.protoVerBody ?? utf8(JSON.stringify({
      prov: { ver: 'v1.1', sec_ver: 1, cap: ['wifi_scan'] },
      yaocore: { ver: '2.0' },
    }));
  }

  async handle(endpoint, value) {
    this.requests.push({ endpoint, value: new Uint8Array(value) });
    if (endpoint === 'proto-ver') {
      return this.protoVerBody;
    }
    if (endpoint === 'prov-session') {
      return this.handleSession(value);
    }
    if (!this.established || this.cipher === undefined) {
      throw new Error('secure session not established');
    }
    const plain = this.crypt(value);
    let response;
    if (endpoint === 'yaocore-id') {
      response = this.handleIdentity(plain);
    } else if (endpoint === 'prov-scan') {
      response = this.handleScan(plain);
    } else if (endpoint === 'prov-config') {
      response = this.handleConfig(plain);
    } else if (endpoint === 'yaocore-done') {
      response = this.doneBody;
    } else {
      throw new Error('unknown endpoint ' + endpoint);
    }
    return this.crypt(response);
  }

  handleSession(value) {
    const envelope = readFields(value);
    const sec1Envelope = readFields(fieldBytes(envelope, 11));
    const messageType = fieldVarint(sec1Envelope, 1, 0);
    if (messageType === 0) {
      // New connection/session always starts at step0; no CTR reuse.
      this.cipher = undefined;
      this.established = false;
      this.clientPublic = undefined;
      this.expectedClientVerify = undefined;
    }
    if (this.cipher === undefined) {
      const clientPublic = parseClientStep0(value);
      const shared = x25519(this.privateKey, clientPublic);
      const popDigest = sha256(utf8(this.pop));
      const sessionKey = xorBytes(shared, popDigest);
      this.cipher = createCipheriv('aes-256-ctr', Buffer.from(sessionKey),
        Buffer.from(this.deviceRandom));
      this.clientPublic = clientPublic;
      this.expectedClientVerify = new Uint8Array(this.cipher.update(Buffer.from(this.publicRaw)));
      return encodeSessionResponse0(this.publicRaw, this.deviceRandom);
    }
    const verify = parseClientStep1(value);
    if (!timingSafeEqual(Buffer.from(verify), Buffer.from(this.expectedClientVerify))) {
      return encodeSessionResponse1(new Uint8Array(32).fill(0xaa));
    }
    const deviceVerify = this.tamperDeviceVerify ?
      new Uint8Array(32).fill(0x55) :
      new Uint8Array(this.cipher.update(Buffer.from(this.clientPublic)));
    this.established = true;
    return encodeSessionResponse1(deviceVerify);
  }

  crypt(data) {
    return new Uint8Array(this.cipher.update(Buffer.from(data)));
  }

  handleIdentity(plain) {
    const request = JSON.parse(Buffer.from(plain).toString('utf8'));
    this.identityRequests.push(request.protocolVersion);
    if (this.identityMode === 'v20') {
      return utf8(JSON.stringify({
        protocolVersion: '2.0',
        serviceId: 'YaoCoreGateway',
        gatewayId: GATEWAY_ID,
        gatewayName: GATEWAY_NAME,
      }));
    }
    if (this.identityMode === 'invalid') {
      return utf8(JSON.stringify({
        protocolVersion: '2.1',
        serviceId: 'YaoCoreGateway',
        gatewayId: GATEWAY_ID,
        gatewayName: GATEWAY_NAME,
        extra: true,
      }));
    }
    if (this.identityMode === 'v21-no-tls') {
      return utf8(JSON.stringify({
        protocolVersion: '2.1',
        serviceId: 'YaoCoreGateway',
        gatewayId: GATEWAY_ID,
        gatewayName: GATEWAY_NAME,
      }));
    }
    return utf8(JSON.stringify({
      protocolVersion: '2.1',
      serviceId: 'YaoCoreGateway',
      gatewayId: GATEWAY_ID,
      gatewayName: GATEWAY_NAME,
      security: {
        lan: { tls: true, port: 9200, pins: [PIN], pinAlg: 'sha256-spki-der' },
      },
    }));
  }

  handleScan(plain) {
    const payload = readFields(plain);
    const messageType = fieldVarint(payload, 1, 0);
    if (messageType === 0) {
      const response = new ProtobufWriter();
      response.varint(1, 1);
      response.message(11, new ProtobufWriter());
      return response.toBytes();
    }
    if (messageType === 2) {
      const response = new ProtobufWriter();
      response.varint(1, 3);
      response.bytes(13, this.scanStatus());
      return response.toBytes();
    }
    if (messageType === 4) {
      const command = readFields(fieldBytes(payload, 14));
      const start = fieldVarint(command, 1, 0);
      const count = fieldVarint(command, 2, 0);
      const response = new ProtobufWriter();
      response.varint(1, 5);
      const results = new ProtobufWriter();
      for (let index = start; index < start + count && index < this.aps.length; index++) {
        const ap = this.aps[index];
        const entry = new ProtobufWriter();
        entry.bytes(1, utf8(ap.ssid));
        entry.varint(2, ap.channel);
        entry.int32(3, ap.rssi);
        entry.bytes(4, new Uint8Array(ap.bssid));
        entry.varint(5, ap.auth);
        results.message(1, entry);
      }
      response.message(15, results);
      return response.toBytes();
    }
    throw new Error('unexpected scan message');
  }

  scanStatus() {
    const response = new ProtobufWriter();
    if (this.scanPolls > 0) {
      this.scanPolls--;
      response.bool(1, false);
      response.varint(2, this.aps.length);
    } else {
      response.bool(1, true);
      response.varint(2, this.aps.length);
    }
    return response.toBytes();
  }

  handleConfig(plain) {
    const payload = readFields(plain);
    const messageType = fieldVarint(payload, 1, 0);
    if (messageType === 0) {
      const status = this.statusSequence[Math.min(this.statusIndex,
        this.statusSequence.length - 1)];
      this.statusIndex++;
      return encodeWifiStatus(status);
    }
    if (messageType === 2) {
      const command = readFields(fieldBytes(payload, 12));
      const ssid = fieldBytes(command, 1);
      const password = fieldBytes(command, 2);
      this.config = {
        ssid: ssid === undefined ? '' : Buffer.from(ssid).toString('utf8'),
        password: password === undefined ? '' : Buffer.from(password).toString('utf8'),
      };
      const response = new ProtobufWriter();
      response.varint(1, 3);
      const ack = new ProtobufWriter();
      ack.varint(1, 0);
      response.message(13, ack);
      return response.toBytes();
    }
    if (messageType === 4) {
      this.applied = true;
      const response = new ProtobufWriter();
      response.varint(1, 5);
      const ack = new ProtobufWriter();
      ack.varint(1, 0);
      response.message(15, ack);
      return response.toBytes();
    }
    throw new Error('unexpected config message');
  }
}

export class FakeClock {
  constructor(nowMs = FIXED_MS) {
    this.value = nowMs;
  }

  nowMs() {
    return this.value;
  }

  advance(ms) {
    this.value += ms;
  }
}

export function fakeDelay(clock) {
  return async (ms) => {
    clock.advance(ms);
  };
}

export class SilentLogger {
  constructor() {
    this.entries = [];
  }

  debug(tag, message) {
    this.entries.push('D ' + tag + ' ' + message);
  }

  info(tag, message) {
    this.entries.push('I ' + tag + ' ' + message);
  }

  warn(tag, message) {
    this.entries.push('W ' + tag + ' ' + message);
  }

  error(tag, message) {
    this.entries.push('E ' + tag + ' ' + message);
  }
}

export function makeDevice(overrides = {}) {
  return new BleProvisioningDevice(
    overrides.deviceId ?? 'AA:BB:CC:DD:EE:FF',
    overrides.name ?? 'YaoCore-GW-EEFF',
    overrides.rssi ?? -42,
    overrides.serviceUuids ?? [GattEndpointMap.SERVICE_UUID]);
}

export class FakeBleConnection {
  constructor(gateway, options = {}) {
    this.gateway = gateway;
    this.mtu = options.mtu ?? 512;
    this.mtuRequests = [];
    this.writes = [];
    this.writeAttempts = [];
    this.readAttempts = 0;
    this.writeBusyRemaining = options.writeBusyOnce === true ? 1 : 0;
    this.readBusyRemaining = options.readBusyOnce === true ? 1 : 0;
    this.disconnectCalls = 0;
    this.pending = undefined;
    this.serviceUuid = GattEndpointMap.SERVICE_UUID;
    this.endpoints = options.endpoints ?? [
      'proto-ver', 'prov-session', 'prov-scan', 'prov-config', 'prov-ctrl',
      'yaocore-id', 'yaocore-done',
    ];
    this.characteristics = [];
    this.descriptors = new Map();
    this.duplicate = options.duplicateEndpoint ?? false;
    this.missingDescriptor = options.missingDescriptor ?? false;
    this.readOnlyCharacteristic = options.readOnlyCharacteristic ?? false;
    const seen = new Set();
    for (let index = 0; index < this.endpoints.length; index++) {
      const endpoint = this.endpoints[index];
      const characteristicUuid = 'char-' + endpoint;
      const canWrite = !(this.readOnlyCharacteristic && endpoint === 'prov-config');
      this.characteristics.push({
        serviceUuid: this.serviceUuid,
        characteristicUuid,
        canRead: true,
        canWrite,
        canWriteNoResponse: false,
      });
      if (this.missingDescriptor && endpoint === 'prov-config') {
        continue;
      }
      let text = endpoint;
      if (this.duplicate && endpoint === 'prov-config') {
        text = seen.has('prov-scan') ? 'prov-scan' : endpoint;
      }
      seen.add(text);
      this.descriptors.set(this.serviceUuid + '|' + characteristicUuid, utf8(text + '\u0000'));
    }
  }

  async requestMtu(target) {
    this.mtuRequests.push(target);
    return this.mtu;
  }

  async discoverServices() {
    return [{ uuid: this.serviceUuid }];
  }

  async discoverCharacteristics() {
    return this.characteristics;
  }

  async readDescriptor(reference) {
    const value = this.descriptors.get(reference.serviceUuid + '|' +
      reference.characteristicUuid);
    if (value === undefined) {
      throw AppErrors.of('PROVISIONING_GATT_BUSY', []);
    }
    return value;
  }

  async writeCharacteristic(reference, value) {
    const endpoint = reference.characteristicUuid.substring('char-'.length);
    this.writeAttempts.push({ endpoint, value: new Uint8Array(value) });
    if (this.writeBusyRemaining > 0) {
      this.writeBusyRemaining--;
      throw AppErrors.of('PROVISIONING_GATT_BUSY', []);
    }
    this.writes.push({ endpoint, value: new Uint8Array(value) });
    this.pending = await this.gateway.handle(endpoint, value);
  }

  async readCharacteristic() {
    this.readAttempts++;
    if (this.readBusyRemaining > 0) {
      this.readBusyRemaining--;
      throw AppErrors.of('PROVISIONING_GATT_BUSY', []);
    }
    if (this.pending === undefined) {
      throw AppErrors.of('PROVISIONING_GATT_BUSY', []);
    }
    return this.pending;
  }

  async disconnect() {
    this.disconnectCalls++;
  }
}

export class FakeBleTransport {
  constructor(connection, options = {}) {
    this.connection = connection;
    this.permissionError = options.permissionError;
    this.bluetoothEnabled = options.bluetoothEnabled ?? true;
    this.devices = options.devices ?? [makeDevice()];
    this.scanFinishes = options.scanFinishes ?? true;
    this.connectError = options.connectError;
    this.startScanCalls = 0;
    this.stopScanCalls = 0;
    this.connectCalls = 0;
    this.scanFilter = undefined;
  }

  async ensurePermission() {
    if (this.permissionError !== undefined) {
      throw this.permissionError;
    }
  }

  async isBluetoothEnabled() {
    return this.bluetoothEnabled;
  }

  async startScan(filter, listener) {
    this.startScanCalls++;
    this.scanFilter = filter;
    for (let index = 0; index < this.devices.length; index++) {
      listener.onDeviceFound(this.devices[index]);
    }
    if (this.scanFinishes) {
      listener.onScanFinished();
    }
  }

  async stopScan() {
    this.stopScanCalls++;
  }

  async connect(deviceId, cancellation) {
    this.connectCalls++;
    this.connectedDeviceId = deviceId;
    if (this.connectError !== undefined) {
      throw this.connectError;
    }
    return this.connection;
  }
}

export class FakeCredentials {
  constructor(secretHex = SECRET_HEX) {
    this.secretHex = secretHex;
    this.calls = 0;
  }

  async withCommandSecret(gatewayId, fn) {
    this.calls++;
    if (this.secretHex.length === 0) {
      throw AppErrors.of('GATEWAY_NOT_BOUND', []);
    }
    const secret = new Uint8Array(Buffer.from(this.secretHex, 'hex'));
    try {
      return await fn(secret);
    } finally {
      secret.fill(0);
    }
  }

  async tlsMaterial() {
    return undefined;
  }
}

export class FakeGatewayClient {
  constructor(options = {}) {
    this.gatewayId = options.gatewayId ?? GATEWAY_ID;
    this.probeGatewayId = options.probeGatewayId ?? this.gatewayId;
    this.snapshotGatewayId = options.snapshotGatewayId ?? this.gatewayId;
    this.failProbes = options.failProbes ?? 0;
    this.probeCalls = 0;
    this.controlCalls = 0;
    this.probeTargets = [];
    this.controlTargets = [];
    this.secrets = [];
    this.ledAck = options.ledAck ?? true;
    this.boardLed = options.boardLed ?? true;
    this.stateVerification = options.stateVerification ?? StateVerification.MATCH;
    this.profileOverride = options.profileOverride;
    this.tlsPinMatchedOverride = options.tlsPinMatchedOverride;
    this.boardStateGatewayId = options.boardStateGatewayId ?? this.gatewayId;
    this.failReset = options.failReset ?? false;
  }

  async probe(target, credentials) {
    this.probeCalls++;
    this.probeTargets.push(target);
    await credentials.withCommandSecret(target.gatewayId, async (secret) => {
      this.secrets.push(Buffer.from(secret).toString('hex'));
    });
    if (this.failProbes > 0) {
      this.failProbes--;
      throw AppErrors.of('GATEWAY_UNREACHABLE', []);
    }
    const init = new DiscoverySnapshotInit();
    init.gatewayId = this.snapshotGatewayId;
    init.gatewayName = GATEWAY_NAME;
    init.generatedAt = '20261017T080000Z';
    const snapshot = DiscoverySnapshot.create(init);
    const tlsPinMatched = this.tlsPinMatchedOverride !== undefined ?
      this.tlsPinMatchedOverride :
      (target.profile === 'P-TLS-PIN' ? target.pins[0] : undefined);
    return new ProbeResult(true, this.probeGatewayId, GATEWAY_NAME,
      this.profileOverride ?? target.profile, tlsPinMatched, 12, snapshot);
  }

  async control(target, command) {
    this.controlCalls++;
    this.controlTargets.push(target);
    if (command.action === 'BOARD_LED_OFF' && this.failReset) {
      throw AppErrors.of('GATEWAY_UNREACHABLE', []);
    }
    if (!this.ledAck && command.action === 'BOARD_LED_ON') {
      throw AppErrors.of('GATEWAY_UNREACHABLE', []);
    }
    const boardState = new GatewayBoardState(this.boardStateGatewayId, true, this.boardLed,
      '20261017T080000Z');
    return ControlOutcome.create({
      requestId: 'req-' + String(this.controlCalls),
      seq: this.controlCalls,
      resultCode: 0,
      idempotentReplay: false,
      ackAccepted: true,
      gatewayBoardState: boardState,
      stateVerification: this.stateVerification,
      gatewayResult: GatewayResultClassifier.classify(0),
      shouldApplyState: false,
    });
  }
}

export function makeDraftStore(clock) {
  const random = {
    async nextBytes(length) {
      return new Uint8Array(length).fill(7);
    },
    nextBytesSync(length) {
      return new Uint8Array(length).fill(7);
    },
  };
  return new SecretDraftStore(random, clock);
}

export function putDraft(drafts, secretHex = SECRET_HEX) {
  return drafts.put(SecureBytes.fromHex(secretHex));
}

export function createRequest(options = {}) {
  return new BleProvisioningRequest(
    options.ssid ?? 'home-wifi',
    options.password ?? utf8('password'),
    options.pop ?? utf8('pop'),
    options.device,
    options.draftId,
    options.familyId ?? FAMILY_ID,
    options.expectedGatewayId);
}

export function makeService(options = {}) {
  const clock = options.clock ?? new FakeClock();
  const gateway = options.gateway ?? new FakeGateway();
  const connection = options.connection ?? new FakeBleConnection(gateway, options.connectionOptions);
  const transport = options.transport ?? new FakeBleTransport(connection, {
    devices: options.devices ?? [makeDevice()],
    ...options.transportOptions,
  });
  const gatewayClient = options.gatewayClient ?? new FakeGatewayClient(options.gatewayClientOptions);
  const credentials = options.credentials ?? new FakeCredentials(
    options.credentialsSecretHex ?? SECRET_HEX);
  const drafts = options.drafts ?? makeDraftStore(clock);
  const crypto = options.crypto ?? new NodeCryptoPort();
  const service = new BleProvisioningService(transport, crypto, clock,
    { async nextBytes(length) { return new Uint8Array(length).fill(5); } },
    gatewayClient, credentials, drafts, new SilentLogger(), fakeDelay(clock), 10);
  return { service, clock, gateway, connection, transport, gatewayClient, credentials, drafts, crypto };
}
