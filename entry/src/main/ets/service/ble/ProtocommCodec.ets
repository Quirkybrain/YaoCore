/*
 * YaoCore C-19 protocomm / Wi-Fi provisioning protobuf codec.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Contract: DES-A §16.5; BLE设计 §5; ESP-IDF 5.2 proto files pinned below.
 *
 * Field numbers (verified against ESP-IDF v5.2.3):
 * - protocomm/proto/session.proto: SessionData.sec_ver=2, sec1=11
 * - protocomm/proto/sec1.proto: Sec1Payload.msg=1, sc0=20, sr0=21, sc1=22,
 *   sr1=23; SessionCmd0.client_pubkey=1; SessionResp0.status=1,
 *   device_pubkey=2, device_random=3; SessionCmd1.client_verify_data=2;
 *   SessionResp1.status=1, device_verify_data=3
 * - wifi_provisioning/proto/wifi_config.proto: WiFiConfigPayload.msg=1,
 *   cmd_get_status=10, resp_get_status=11, cmd_set_config=12,
 *   resp_set_config=13, cmd_apply_config=14, resp_apply_config=15
 * - wifi_provisioning/proto/wifi_scan.proto: cmd_scan_start=10,
 *   resp_scan_start=11, cmd_scan_status=12, resp_scan_status=13,
 *   cmd_scan_result=14, resp_scan_result=15
 * - wifi_provisioning/proto/wifi_constants.proto: WifiStationState,
 *   WifiConnectFailedReason, WifiAuthMode
 *
 * No custom frame header is ever added (BLE设计 §5-116). Decode failures are
 * mapped to the caller-facing C-19 error code; protobuf detail is not leaked.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { Utf8 } from '../../common/utils/Utf8';
import { IpAddressUtil } from '../../common/utils/IpAddressUtil';
import { ProtobufReader, ProtobufWriter } from './Protobuf';

const SEC1_SEC_VER: number = 1;
const SEC1_MSG_COMMAND0: number = 0;
const SEC1_MSG_RESPONSE0: number = 1;
const SEC1_MSG_COMMAND1: number = 2;
const SEC1_MSG_RESPONSE1: number = 3;
const SEC1_PUBLIC_KEY_BYTES: number = 32;
const SEC1_DEVICE_RANDOM_BYTES: number = 16;
const SEC1_VERIFY_BYTES: number = 32;

const WIFI_MSG_RESP_GET_STATUS: number = 1;
const WIFI_MSG_CMD_SET_CONFIG: number = 2;
const WIFI_MSG_RESP_SET_CONFIG: number = 3;
const WIFI_MSG_CMD_APPLY_CONFIG: number = 4;
const WIFI_MSG_RESP_APPLY_CONFIG: number = 5;
const WIFI_MSG_CMD_GET_STATUS: number = 0;

const SCAN_MSG_CMD_START: number = 0;
const SCAN_MSG_RESP_START: number = 1;
const SCAN_MSG_CMD_STATUS: number = 2;
const SCAN_MSG_RESP_STATUS: number = 3;
const SCAN_MSG_CMD_RESULT: number = 4;
const SCAN_MSG_RESP_RESULT: number = 5;

const PROTO_SUCCESS: number = 0;
const WIFI_STATE_CONNECTED: number = 0;
const WIFI_STATE_CONNECTING: number = 1;
const WIFI_STATE_DISCONNECTED: number = 2;
const WIFI_STATE_CONNECTION_FAILED: number = 3;
const WIFI_FAIL_AUTH: number = 0;
const WIFI_FAIL_NETWORK_NOT_FOUND: number = 1;

export class SessionDataMessage {
  readonly secVer: number;
  readonly clientPubKey?: Uint8Array;
  readonly devicePubKey?: Uint8Array;
  readonly deviceRandom?: Uint8Array;
  readonly clientVerifyData?: Uint8Array;
  readonly deviceVerifyData?: Uint8Array;

  constructor(secVer: number, clientPubKey?: Uint8Array, devicePubKey?: Uint8Array,
    deviceRandom?: Uint8Array, clientVerifyData?: Uint8Array,
    deviceVerifyData?: Uint8Array) {
    this.secVer = secVer;
    this.clientPubKey = clientPubKey;
    this.devicePubKey = devicePubKey;
    this.deviceRandom = deviceRandom;
    this.clientVerifyData = clientVerifyData;
    this.deviceVerifyData = deviceVerifyData;
  }
}

export class WifiScanStatus {
  readonly scanFinished: boolean;
  readonly resultCount: number;

  constructor(scanFinished: boolean, resultCount: number) {
    if (!Number.isInteger(resultCount) || resultCount < 0) {
      throw AppErrors.of('PROVISIONING_WIFI_SCAN_FAILED', []);
    }
    this.scanFinished = scanFinished;
    this.resultCount = resultCount;
  }
}

export class WifiScanResult {
  readonly ssid: Uint8Array;
  readonly bssid: Uint8Array;
  readonly channel: number;
  readonly rssi: number;
  readonly auth: number;

  constructor(ssid: Uint8Array, bssid: Uint8Array, channel: number, rssi: number, auth: number) {
    this.ssid = ssid;
    this.bssid = bssid;
    this.channel = channel;
    this.rssi = rssi;
    this.auth = auth;
  }
}

export class WifiConfig {
  readonly ssid: string;
  readonly password: Uint8Array;
  readonly bssid?: Uint8Array;
  readonly channel?: number;

  constructor(ssid: string, password: Uint8Array, bssid?: Uint8Array, channel?: number) {
    const ssidBytes = Utf8.encode(ssid);
    if (ssidBytes.length === 0 || ssidBytes.length > 32 || password.length > 64) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'wifiConfig');
    }
    this.ssid = ssid;
    this.password = password;
    this.bssid = bssid;
    this.channel = channel;
  }
}

export enum WifiStationState {
  CONNECTED = 'CONNECTED',
  CONNECTING = 'CONNECTING',
  DISCONNECTED = 'DISCONNECTED',
  CONNECTION_FAILED = 'CONNECTION_FAILED'
}

export enum WifiConnectFailedReason {
  AUTH_ERROR = 'AUTH_ERROR',
  NETWORK_NOT_FOUND = 'NETWORK_NOT_FOUND'
}

export class WifiStatus {
  readonly state: WifiStationState;
  readonly failReason?: WifiConnectFailedReason;
  readonly ip4?: string;

  constructor(state: WifiStationState, failReason?: WifiConnectFailedReason, ip4?: string) {
    if (ip4 !== undefined && ip4.length > 0 && !IpAddressUtil.isValidIpv4(ip4)) {
      throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'wifiIp4');
    }
    if (state === WifiStationState.CONNECTED && (ip4 === undefined || ip4.length === 0)) {
      throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'wifiIp4');
    }
    this.state = state;
    this.failReason = failReason;
    this.ip4 = ip4;
  }
}

class ScanStatusMessage {
  readonly scanFinished: boolean;
  readonly resultCount: number;

  constructor(scanFinished: boolean, resultCount: number) {
    this.scanFinished = scanFinished;
    this.resultCount = resultCount;
  }
}

function decodeFailure(code: string, field: string): AppError {
  return AppErrors.of(code, [new NameValue('field', field)]);
}

function rethrowDecode(error: Error, code: string, field: string): never {
  if (error instanceof AppError) {
    const appError = error as AppError;
    if (appError.code.startsWith('PROVISIONING_')) {
      throw appError;
    }
  }
  throw decodeFailure(code, field);
}

function requireLength(bytes: Uint8Array, expected: number, field: string,
  code: string): Uint8Array {
  if (bytes.length !== expected) {
    throw decodeFailure(code, field);
  }
  return bytes;
}

export class ProtocommCodec {
  // ---- Security1 SessionData ---------------------------------------------

  static encodeSessionDataStep0(clientPubRaw: Uint8Array): Uint8Array {
    requireLength(clientPubRaw, SEC1_PUBLIC_KEY_BYTES, 'clientPublicKey',
      'PROVISIONING_SECURITY_HANDSHAKE_FAILED');
    const command = new ProtobufWriter();
    command.bytes(1, clientPubRaw);
    const sec1 = new ProtobufWriter();
    sec1.message(20, command);
    const session = new ProtobufWriter();
    session.varint(2, SEC1_SEC_VER);
    session.message(11, sec1);
    return session.toBytes();
  }

  static encodeSessionDataStep1(clientVerifyData: Uint8Array): Uint8Array {
    requireLength(clientVerifyData, SEC1_VERIFY_BYTES, 'clientVerifyData',
      'PROVISIONING_SECURITY_HANDSHAKE_FAILED');
    const command = new ProtobufWriter();
    command.bytes(2, clientVerifyData);
    const sec1 = new ProtobufWriter();
    sec1.varint(1, SEC1_MSG_COMMAND1);
    sec1.message(22, command);
    const session = new ProtobufWriter();
    session.varint(2, SEC1_SEC_VER);
    session.message(11, sec1);
    return session.toBytes();
  }

  static decodeSessionDataStep0(payload: Uint8Array): SessionDataMessage {
    try {
      const session = ProtocommCodec.readSessionEnvelope(payload, SEC1_MSG_RESPONSE0, 21);
      let status = PROTO_SUCCESS;
      let publicKey: Uint8Array | undefined = undefined;
      let random: Uint8Array | undefined = undefined;
      const reader = session.responseReader;
      while (reader.hasMore()) {
        const tag = reader.readTag();
        if (tag.fieldNumber === 1 && tag.wireType === 0) {
          status = reader.readUnsigned();
        } else if (tag.fieldNumber === 2 && tag.wireType === 2) {
          if (publicKey !== undefined) {
            throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'devicePublicKey');
          }
          publicKey = reader.readBytes();
        } else if (tag.fieldNumber === 3 && tag.wireType === 2) {
          if (random !== undefined) {
            throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'deviceRandom');
          }
          random = reader.readBytes();
        } else {
          reader.skip(tag);
        }
      }
      if (status !== PROTO_SUCCESS || publicKey === undefined || random === undefined) {
        throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'step0Response');
      }
      requireLength(publicKey, SEC1_PUBLIC_KEY_BYTES, 'devicePublicKey',
        'PROVISIONING_SECURITY_HANDSHAKE_FAILED');
      requireLength(random, SEC1_DEVICE_RANDOM_BYTES, 'deviceRandom',
        'PROVISIONING_SECURITY_HANDSHAKE_FAILED');
      return new SessionDataMessage(SEC1_SEC_VER, undefined, publicKey, random);
    } catch (error) {
      rethrowDecode(error as Error, 'PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'step0Response');
    }
  }

  static decodeSessionDataStep1(payload: Uint8Array): SessionDataMessage {
    try {
      const session = ProtocommCodec.readSessionEnvelope(payload, SEC1_MSG_RESPONSE1, 23);
      let status = PROTO_SUCCESS;
      let verifyData: Uint8Array | undefined = undefined;
      const reader = session.responseReader;
      while (reader.hasMore()) {
        const tag = reader.readTag();
        if (tag.fieldNumber === 1 && tag.wireType === 0) {
          status = reader.readUnsigned();
        } else if (tag.fieldNumber === 3 && tag.wireType === 2) {
          if (verifyData !== undefined) {
            throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'deviceVerifyData');
          }
          verifyData = reader.readBytes();
        } else {
          reader.skip(tag);
        }
      }
      if (status !== PROTO_SUCCESS || verifyData === undefined) {
        throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'step1Response');
      }
      requireLength(verifyData, SEC1_VERIFY_BYTES, 'deviceVerifyData',
        'PROVISIONING_SECURITY_HANDSHAKE_FAILED');
      return new SessionDataMessage(SEC1_SEC_VER, undefined, undefined, undefined,
        undefined, verifyData);
    } catch (error) {
      rethrowDecode(error as Error, 'PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'step1Response');
    }
  }

  private static readSessionEnvelope(payload: Uint8Array, expectedMessage: number,
    responseField: number): SessionEnvelope {
    const session = new ProtobufReader(payload);
    let secVer = 0;
    let sec1Body: Uint8Array | undefined = undefined;
    while (session.hasMore()) {
      const tag = session.readTag();
      if (tag.fieldNumber === 2 && tag.wireType === 0) {
        secVer = session.readUnsigned();
      } else if (tag.fieldNumber === 11 && tag.wireType === 2) {
        if (sec1Body !== undefined) {
          throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'sec1');
        }
        sec1Body = session.readBytes();
      } else {
        session.skip(tag);
      }
    }
    if (secVer !== SEC1_SEC_VER || sec1Body === undefined) {
      throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'session');
    }
    const sec1 = new ProtobufReader(sec1Body);
    let messageType = SEC1_MSG_COMMAND0;
    let responseBody: Uint8Array | undefined = undefined;
    while (sec1.hasMore()) {
      const tag = sec1.readTag();
      if (tag.fieldNumber === 1 && tag.wireType === 0) {
        messageType = sec1.readUnsigned();
      } else if (tag.fieldNumber === responseField && tag.wireType === 2) {
        if (responseBody !== undefined) {
          throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'sec1Response');
        }
        responseBody = sec1.readBytes();
      } else {
        sec1.skip(tag);
      }
    }
    if (messageType !== expectedMessage || responseBody === undefined) {
      throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'sec1Message');
    }
    return new SessionEnvelope(new ProtobufReader(responseBody));
  }

  // ---- Wi-Fi scan ---------------------------------------------------------

  static encodeScanStart(): Uint8Array {
    const command = new ProtobufWriter();
    command.bool(1, true);
    command.bool(2, false);
    command.varint(3, 0);
    command.varint(4, 120);
    const payload = new ProtobufWriter();
    payload.message(10, command);
    return payload.toBytes();
  }

  static encodeScanStatus(): Uint8Array {
    const payload = new ProtobufWriter();
    payload.varint(1, SCAN_MSG_CMD_STATUS);
    payload.message(12, new ProtobufWriter());
    return payload.toBytes();
  }

  static validateScanStartResponse(payload: Uint8Array): void {
    try {
      ProtocommCodec.readWifiScanEnvelope(payload, SCAN_MSG_RESP_START, 11);
    } catch (error) {
      rethrowDecode(error as Error, 'PROVISIONING_WIFI_SCAN_FAILED', 'scanStartResponse');
    }
  }

  static decodeScanStatus(payload: Uint8Array): WifiScanStatus {
    try {
      const parsed = ProtocommCodec.readWifiScanEnvelope(payload, SCAN_MSG_RESP_STATUS, 13);
      let scanFinished = false;
      let resultCount = 0;
      const reader = parsed;
      while (reader.hasMore()) {
        const tag = reader.readTag();
        if (tag.fieldNumber === 1 && tag.wireType === 0) {
          scanFinished = reader.readBool();
        } else if (tag.fieldNumber === 2 && tag.wireType === 0) {
          resultCount = reader.readUnsigned();
        } else {
          reader.skip(tag);
        }
      }
      return new WifiScanStatus(scanFinished, resultCount);
    } catch (error) {
      rethrowDecode(error as Error, 'PROVISIONING_WIFI_SCAN_FAILED', 'scanStatus');
    }
  }

  static encodeScanResult(startIndex: number, count: number): Uint8Array {
    if (!Number.isInteger(startIndex) || startIndex < 0 || !Number.isInteger(count) ||
      count < 1 || count > 4) {
      throw AppErrors.of('PROVISIONING_WIFI_SCAN_FAILED', []);
    }
    const command = new ProtobufWriter();
    command.varint(1, startIndex);
    command.varint(2, count);
    const payload = new ProtobufWriter();
    payload.varint(1, SCAN_MSG_CMD_RESULT);
    payload.message(14, command);
    return payload.toBytes();
  }

  static decodeScanResult(payload: Uint8Array): ReadonlyArray<WifiScanResult> {
    try {
      const reader = ProtocommCodec.readWifiScanEnvelope(payload, SCAN_MSG_RESP_RESULT, 15);
      const results: WifiScanResult[] = [];
      while (reader.hasMore()) {
        const tag = reader.readTag();
        if (tag.fieldNumber === 1 && tag.wireType === 2) {
          results.push(ProtocommCodec.decodeSingleScanResult(reader.readBytes()));
        } else {
          reader.skip(tag);
        }
      }
      return results;
    } catch (error) {
      rethrowDecode(error as Error, 'PROVISIONING_WIFI_SCAN_FAILED', 'scanResult');
    }
  }

  private static decodeSingleScanResult(payload: Uint8Array): WifiScanResult {
    const reader = new ProtobufReader(payload);
    let ssid: Uint8Array | undefined = undefined;
    let channel = 0;
    let rssi = 0;
    let bssid: Uint8Array | undefined = undefined;
    let auth = 0;
    while (reader.hasMore()) {
      const tag = reader.readTag();
      if (tag.fieldNumber === 1 && tag.wireType === 2) {
        ssid = reader.readBytes();
      } else if (tag.fieldNumber === 2 && tag.wireType === 0) {
        channel = reader.readUnsigned();
      } else if (tag.fieldNumber === 3 && tag.wireType === 0) {
        rssi = reader.readInt32();
      } else if (tag.fieldNumber === 4 && tag.wireType === 2) {
        bssid = reader.readBytes();
      } else if (tag.fieldNumber === 5 && tag.wireType === 0) {
        auth = reader.readUnsigned();
      } else {
        reader.skip(tag);
      }
    }
    if (ssid === undefined || bssid === undefined || ssid.length === 0 || bssid.length !== 6 ||
      channel < 0 || channel > 196 || auth > 7) {
      throw decodeFailure('PROVISIONING_WIFI_SCAN_FAILED', 'scanEntry');
    }
    return new WifiScanResult(ssid, bssid, channel, rssi, auth);
  }

  private static readWifiScanEnvelope(payload: Uint8Array, expectedMessage: number,
    responseField: number): ProtobufReader {
    const envelope = new ProtobufReader(payload);
    let messageType = SCAN_MSG_CMD_START;
    let status = PROTO_SUCCESS;
    let body: Uint8Array | undefined = undefined;
    while (envelope.hasMore()) {
      const tag = envelope.readTag();
      if (tag.fieldNumber === 1 && tag.wireType === 0) {
        messageType = envelope.readUnsigned();
      } else if (tag.fieldNumber === 2 && tag.wireType === 0) {
        status = envelope.readUnsigned();
      } else if (tag.fieldNumber === responseField && tag.wireType === 2) {
        if (body !== undefined) {
          throw decodeFailure('PROVISIONING_WIFI_SCAN_FAILED', 'scanResponse');
        }
        body = envelope.readBytes();
      } else {
        envelope.skip(tag);
      }
    }
    if (messageType !== expectedMessage || status !== PROTO_SUCCESS || body === undefined) {
      throw decodeFailure('PROVISIONING_WIFI_SCAN_FAILED', 'scanMessage');
    }
    return new ProtobufReader(body);
  }

  // ---- Wi-Fi configuration / status ---------------------------------------

  static encodeSetConfig(config: WifiConfig): Uint8Array {
    const command = new ProtobufWriter();
    command.bytes(1, Utf8.encode(config.ssid));
    if (config.password.length > 0) {
      command.bytes(2, config.password);
    }
    if (config.bssid !== undefined && config.bssid.length > 0) {
      command.bytes(3, config.bssid);
    }
    if (config.channel !== undefined) {
      command.int32(4, config.channel);
    }
    const payload = new ProtobufWriter();
    payload.varint(1, WIFI_MSG_CMD_SET_CONFIG);
    payload.message(12, command);
    const result = payload.toBytes();
    // The scratch writers held the plaintext Wi-Fi passphrase; zeroize them.
    command.destroy();
    payload.destroy();
    return result;
  }

  static encodeApplyConfig(): Uint8Array {
    const payload = new ProtobufWriter();
    payload.varint(1, WIFI_MSG_CMD_APPLY_CONFIG);
    payload.message(14, new ProtobufWriter());
    return payload.toBytes();
  }

  static encodeGetStatus(): Uint8Array {
    const payload = new ProtobufWriter();
    payload.message(10, new ProtobufWriter());
    return payload.toBytes();
  }

  static decodeSetConfigResponse(payload: Uint8Array): void {
    ProtocommCodec.decodeConfigAck(payload, WIFI_MSG_RESP_SET_CONFIG, 13);
  }

  static decodeApplyConfigResponse(payload: Uint8Array): void {
    ProtocommCodec.decodeConfigAck(payload, WIFI_MSG_RESP_APPLY_CONFIG, 15);
  }

  private static decodeConfigAck(payload: Uint8Array, expectedMessage: number,
    responseField: number): void {
    try {
      const envelope = new ProtobufReader(payload);
      let messageType = WIFI_MSG_CMD_GET_STATUS;
      let status = PROTO_SUCCESS;
      let body: Uint8Array | undefined = undefined;
      while (envelope.hasMore()) {
        const tag = envelope.readTag();
        if (tag.fieldNumber === 1 && tag.wireType === 0) {
          messageType = envelope.readUnsigned();
        } else if (tag.fieldNumber === 2 && tag.wireType === 0) {
          status = envelope.readUnsigned();
        } else if (tag.fieldNumber === responseField && tag.wireType === 2) {
          if (body !== undefined) {
            throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'configResponse');
          }
          body = envelope.readBytes();
        } else {
          envelope.skip(tag);
        }
      }
      if (messageType !== expectedMessage || status !== PROTO_SUCCESS || body === undefined) {
        throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'configMessage');
      }
      const response = new ProtobufReader(body);
      let responseStatus = PROTO_SUCCESS;
      while (response.hasMore()) {
        const tag = response.readTag();
        if (tag.fieldNumber === 1 && tag.wireType === 0) {
          responseStatus = response.readUnsigned();
        } else {
          response.skip(tag);
        }
      }
      if (responseStatus !== PROTO_SUCCESS) {
        throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'configStatus');
      }
    } catch (error) {
      rethrowDecode(error as Error, 'PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'configResponse');
    }
  }

  static decodeWifiStatus(payload: Uint8Array): WifiStatus {
    try {
      const envelope = new ProtobufReader(payload);
      let messageType = WIFI_MSG_CMD_GET_STATUS;
      let status = PROTO_SUCCESS;
      let body: Uint8Array | undefined = undefined;
      while (envelope.hasMore()) {
        const tag = envelope.readTag();
        if (tag.fieldNumber === 1 && tag.wireType === 0) {
          messageType = envelope.readUnsigned();
        } else if (tag.fieldNumber === 2 && tag.wireType === 0) {
          status = envelope.readUnsigned();
        } else if (tag.fieldNumber === 11 && tag.wireType === 2) {
          if (body !== undefined) {
            throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'wifiStatus');
          }
          body = envelope.readBytes();
        } else {
          envelope.skip(tag);
        }
      }
      if (messageType !== WIFI_MSG_RESP_GET_STATUS || status !== PROTO_SUCCESS ||
        body === undefined) {
        throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'wifiStatusMessage');
      }
      const response = new ProtobufReader(body);
      let responseStatus = PROTO_SUCCESS;
      let rawState = WIFI_STATE_CONNECTING;
      let rawFailReason = -1;
      let ip4: string | undefined = undefined;
      while (response.hasMore()) {
        const tag = response.readTag();
        if (tag.fieldNumber === 1 && tag.wireType === 0) {
          responseStatus = response.readUnsigned();
        } else if (tag.fieldNumber === 2 && tag.wireType === 0) {
          rawState = response.readUnsigned();
        } else if (tag.fieldNumber === 10 && tag.wireType === 0) {
          rawFailReason = response.readUnsigned();
        } else if (tag.fieldNumber === 11 && tag.wireType === 2) {
          ip4 = ProtocommCodec.readConnectedState(response.readBytes());
        } else {
          response.skip(tag);
        }
      }
      if (responseStatus !== PROTO_SUCCESS) {
        throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'wifiStatusResponse');
      }
      let state = WifiStationState.DISCONNECTED;
      if (rawState === WIFI_STATE_CONNECTED) {
        state = WifiStationState.CONNECTED;
      } else if (rawState === WIFI_STATE_CONNECTING) {
        state = WifiStationState.CONNECTING;
      } else if (rawState === WIFI_STATE_DISCONNECTED) {
        state = WifiStationState.DISCONNECTED;
      } else if (rawState === WIFI_STATE_CONNECTION_FAILED) {
        state = WifiStationState.CONNECTION_FAILED;
      } else {
        throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'wifiState');
      }
      let failReason: WifiConnectFailedReason | undefined = undefined;
      if (rawFailReason >= 0) {
        if (rawFailReason === WIFI_FAIL_AUTH) {
          failReason = WifiConnectFailedReason.AUTH_ERROR;
        } else if (rawFailReason === WIFI_FAIL_NETWORK_NOT_FOUND) {
          failReason = WifiConnectFailedReason.NETWORK_NOT_FOUND;
        } else {
          throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'wifiFailReason');
        }
      }
      if (state === WifiStationState.CONNECTED && (ip4 === undefined || ip4.length === 0)) {
        throw decodeFailure('PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'wifiIp4');
      }
      return new WifiStatus(state, failReason, ip4);
    } catch (error) {
      rethrowDecode(error as Error, 'PROVISIONING_SECURITY_HANDSHAKE_FAILED', 'wifiStatus');
    }
  }

  private static readConnectedState(payload: Uint8Array): string {
    const reader = new ProtobufReader(payload);
    let ip4 = '';
    while (reader.hasMore()) {
      const tag = reader.readTag();
      if (tag.fieldNumber === 1 && tag.wireType === 2) {
        ip4 = reader.readString();
      } else {
        reader.skip(tag);
      }
    }
    return ip4;
  }

  // ---- YaoCore custom endpoints -------------------------------------------

  static encodeCustomJson(json: string): Uint8Array {
    return Utf8.encode(json);
  }

  static decodeCustomJson(payload: Uint8Array): string {
    return Utf8.decode(payload);
  }

  /**
   * UNRESOLVED-BLE-CTRL-PROTO: wifi_ctrl.proto defines CmdCtrlReset (field 11)
   * and CmdCtrlReprov (field 13), but no "stop" message. reset is encoded from
   * the pinned ESP-IDF 5.2 proto; C-19 does not call it on the happy path.
   */
  static encodeCtrlReset(): Uint8Array {
    const payload = new ProtobufWriter();
    payload.varint(1, 1);
    payload.message(11, new ProtobufWriter());
    return payload.toBytes();
  }

  static encodeCtrlStop(): Uint8Array {
    throw AppErrors.of('PROVISIONING_CAPABILITY_UNSUPPORTED',
      [new NameValue('field', 'prov-ctrl-stop')]);
  }
}

class SessionEnvelope {
  readonly responseReader: ProtobufReader;

  constructor(responseReader: ProtobufReader) {
    this.responseReader = responseReader;
  }
}
