/*
 * YaoCore C-20 MockGatewayService.
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §17.1-§17.5, §19.3; ADR-002 §7.3
 *
 * TEST ONLY — SC-11 boundary. Never import this file from entryability,
 * viewmodel, pages, components, service (other than mock/**), or repository.
 * The composition root (C-28) must bind only real adapters. Host test
 * TransportBoundary.test.mjs scans the production tree for this path.
 *
 * The mock uses the production CanonicalBuilder + ResponseVerifier +
 * ControlAckMapper so that a mock pass cannot hide a real ACK-chain regression.
 * Secrets are PUBLIC TEST DATA ONLY; no payload is logged.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { ProtocolConstants, ProtocolHeaders } from '../../common/constants/ProtocolConstants';
import { DeviceAction, DeviceConstants, DeviceType } from '../../common/constants/DeviceConstants';
import { HttpHeaders } from '../../common/types/HttpHeaders';
import { NameValue } from '../../common/types/NameValue';
import { JsonNode, NameValueNode } from '../../common/types/JsonNode';
import { BytesUtil } from '../../common/utils/BytesUtil';
import { Utf8 } from '../../common/utils/Utf8';
import { JsonCanonicalizer } from '../../common/utils/JsonCanonicalizer';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import type { ClockPort, RandomPort } from '../../common/types/Ports';
import { ControlOutcome } from '../../model/ControlModels';
import { DeviceControlCommand } from '../../model/ControlModels';
import { DeviceSnapshot, DeviceSnapshotInit } from '../../model/DeviceState';
import { DiscoverySnapshot, DiscoverySnapshotInit } from '../../model/DiscoveryModels';
import { GatewayAddress } from '../../model/GatewayRoute';
import { TransportProfile } from '../../model/DeviceTypes';
import type { CryptoPort } from '../crypto/CryptoPort';
import { CanonicalBuilder, ResponseKind } from '../security/CanonicalBuilder';
import { ExpectedResponse, ResponseVerifier } from '../security/ResponseVerifier';
import { AckExpectation, ControlAckMapper } from '../protocol/ControlAckMapper';
import { DeviationCounter } from '../protocol/ProtocolDeviation';
import type { DeviceControlPort } from '../../repository/DomainPorts';
import type { GatewayCredentialPort } from '../../repository/GatewayPorts';
import { GatewayTarget, ProbeResult } from '../gateway/GatewayTransportPorts';
import type { IGatewayClient } from '../gateway/GatewayTransportPorts';
import { MockMode, MockScenario, MockTlsMode } from './MockScenario';

const MOCK_FAMILY_ID: string = 'mock-family';
const MOCK_IP: string = '192.168.1.10';
const MOCK_PORT: number = 9200;

export type MockDelay = (delayMs: number) => Promise<void>;

function defaultMockDelay(delayMs: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, delayMs);
  });
}

class MockRecord {
  readonly key: string;
  readonly applied: boolean;
  /** ack-lost: the exact ACK produced by the lost first attempt (T-11 F-12). */
  readonly outcome?: ControlOutcome;

  constructor(key: string, applied: boolean, outcome?: ControlOutcome) {
    this.key = key;
    this.applied = applied;
    this.outcome = outcome;
  }
}

export class MockGatewayService implements IGatewayClient, DeviceControlPort {
  private readonly scenario: MockScenario;
  private readonly clock: ClockPort;
  private readonly crypto: CryptoPort;
  private readonly secret: Uint8Array;
  private readonly gatewayId: string;
  private readonly gatewayName: string;
  private readonly delay: (delayMs: number) => Promise<void>;
  private readonly verifier: ResponseVerifier;
  private readonly records: Map<string, MockRecord> = new Map<string, MockRecord>();
  private readonly lastCommandByTarget: Map<string, string> = new Map<string, string>();
  private requestCount: number = 0;
  private sequence: number = 0;
  private boardLed: boolean = false;

  constructor(scenario: MockScenario, clock: ClockPort, random: RandomPort, crypto: CryptoPort,
    secret: Uint8Array, gatewayId: string, gatewayName: string, delay?: MockDelay) {
    if (secret.length < 16) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (gatewayId.length === 0 || gatewayId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      gatewayId.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(gatewayId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'gatewayId');
    }
    if (gatewayName.length === 0 ||
      gatewayName.length > ProtocolConstants.MAX_GATEWAY_NAME_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'gatewayName');
    }
    this.scenario = scenario;
    this.clock = clock;
    this.crypto = crypto;
    this.secret = BytesUtil.copyOf(secret);
    this.gatewayId = gatewayId;
    this.gatewayName = gatewayName;
    this.delay = delay === undefined ? defaultMockDelay : delay;
    this.verifier = new ResponseVerifier(crypto);
    this.sequence = Math.abs(Math.floor(scenario.seed)) % 1000;
  }

  async discover(target: GatewayTarget): Promise<DiscoverySnapshot> {
    await this.beforeRequest(target);
    return this.snapshot();
  }

  async control(target: GatewayTarget, command: DeviceControlCommand): Promise<ControlOutcome> {
    if (command.gatewayId !== target.gatewayId) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    await this.beforeRequest(target);
    const key = MockGatewayService.commandKey(command);
    if (this.scenario.mode === MockMode.ACK_LOST) {
      const existing = this.records.get(key);
      if (existing === undefined) {
        const outcome = await this.ackOutcome(command, false, false);
        this.records.set(key, new MockRecord(key, true, outcome));
        throw AppErrors.of('GATEWAY_TIMEOUT', []);
      }
      if (existing.outcome === undefined) {
        throw AppErrors.of('GATEWAY_TIMEOUT', []);
      }
      // F-12: exact retransmission returns the original ACK (same
      // request_id/seq); no new identity is invented for the retry.
      return existing.outcome;
    }
    if (this.scenario.mode === MockMode.REPLAY) {
      const existing = this.records.get(key);
      if (existing !== undefined) {
        return this.ackOutcome(command, true, true);
      }
      const previousKey = this.lastCommandByTarget.get(command.target);
      if (previousKey !== undefined && previousKey !== key) {
        // Same target, different authenticated content within the replay
        // window: gateway returns a signed 1005, which is not an ACK.
        this.records.set(key, new MockRecord(key, false));
        return this.ackOutcome(command, false, false, 1005);
      }
      const outcome = await this.ackOutcome(command, false, false);
      this.records.set(key, new MockRecord(key, true));
      this.lastCommandByTarget.set(command.target, key);
      return outcome;
    }
    const resultCode = this.scenario.resultCode === undefined ? 0 : this.scenario.resultCode;
    const replay = this.scenario.idempotentReplay === true;
    return this.ackOutcome(command, replay, replay, resultCode);
  }

  async probe(target: GatewayTarget, credentials?: GatewayCredentialPort): Promise<ProbeResult> {
    await this.beforeRequest(target);
    const startedAtMs = this.nowMs();
    const snapshot = this.snapshot();
    const latencyMs = Math.max(0, this.nowMs() - startedAtMs) + this.scenario.latencyMs;
    const matched = target.profile === TransportProfile.P_TLS_PIN &&
      this.scenario.tlsMode === MockTlsMode.PIN_MATCH && target.pins.length > 0 ?
      target.pins[0] : undefined;
    return new ProbeResult(true, this.gatewayId, this.gatewayName, target.profile, matched,
      latencyMs, snapshot);
  }

  /** DeviceControlPort adapter for VM/SceneService integration on host tests. */
  async send(command: DeviceControlCommand): Promise<ControlOutcome> {
    const target = new GatewayTarget(this.gatewayId, MOCK_FAMILY_ID,
      new GatewayAddress(MOCK_IP, MOCK_PORT), TransportProfile.P_HMAC, [], MOCK_PORT,
      'yaocore.gateway.hmac.' + this.gatewayId);
    return this.control(target, command);
  }

  private async beforeRequest(target: GatewayTarget): Promise<void> {
    this.requestCount += 1;
    if (target.profile === TransportProfile.P_BLOCKED) {
      throw AppErrors.gateway('GATEWAY_PROFILE_BLOCKED', target.gatewayId);
    }
    if (target.gatewayId !== this.gatewayId) {
      throw AppErrors.gateway('GATEWAY_ID_MISMATCH', target.gatewayId);
    }
    if (this.scenario.failAtAttempt > 0 &&
      this.requestCount === this.scenario.failAtAttempt) {
      throw AppErrors.of('GATEWAY_UNREACHABLE', []);
    }
    if (this.scenario.mode === MockMode.OFFLINE) {
      throw AppErrors.of('GATEWAY_UNREACHABLE', []);
    }
    if (this.scenario.mode === MockMode.TIMEOUT) {
      await this.delay(this.scenario.latencyMs);
      throw AppErrors.of('GATEWAY_TIMEOUT', []);
    }
    if (this.scenario.mode === MockMode.DEV_ONLY) {
      // The mock surfaces the production rejection result, not a usable ACK.
      throw AppErrors.of('DEV_SIMULATOR_REJECTED', []);
    }
    if (target.profile === TransportProfile.P_TLS_PIN) {
      if (target.pins.length < 1 || target.pins.length > ProtocolConstants.MAX_PIN_COUNT) {
        throw AppErrors.of('TLS_PROFILE_INCONSISTENT', []);
      }
      if (this.scenario.tlsMode === MockTlsMode.PIN_MISMATCH) {
        throw AppErrors.of('TLS_PIN_MISMATCH', []);
      }
      if (this.scenario.tlsMode === MockTlsMode.HANDSHAKE_FAIL ||
        this.scenario.tlsMode === MockTlsMode.DISABLED) {
        throw AppErrors.of('TLS_HANDSHAKE_FAILED', []);
      }
    }
    if (this.scenario.latencyMs > 0) {
      await this.delay(this.scenario.latencyMs);
    }
  }

  private snapshot(): DiscoverySnapshot {
    const updatedAt = this.nowCompact();
    const init = new DiscoverySnapshotInit();
    init.gatewayId = this.gatewayId;
    init.gatewayName = this.gatewayName;
    init.generatedAt = updatedAt;
    init.devices = [
      this.device('Door_01', 'Mock Door', 'door', DeviceType.DOOR, updatedAt, false),
      this.device('Light_01', 'Mock Light', 'light', DeviceType.LIGHT, updatedAt, true),
      this.device('Sensor_01', 'Mock Sensor', 'sensor', DeviceType.SENSOR, updatedAt, true),
      this.device('AC_01', 'Mock AC', 'ac', DeviceType.AC, updatedAt, true)
    ];
    init.deviations = [];
    init.isPartial = false;
    init.aliasUsed = false;
    return DiscoverySnapshot.create(init);
  }

  private device(deviceId: string, name: string, rawType: string, type: DeviceType,
    updatedAt: string, powered: boolean): DeviceSnapshot {
    const init = new DeviceSnapshotInit();
    init.deviceId = deviceId;
    init.deviceName = name;
    init.roomNameHint = 'Mock Room';
    init.deviceTypeRaw = rawType;
    init.deviceType = type;
    init.isSupported = DeviceConstants.isSupported(type);
    init.isOnline = true;
    init.updatedAt = updatedAt;
    init.stateSource = 'app.lan';
    init.stateSourceKnown = true;
    if (type === DeviceType.DOOR) {
      init.openStatus = false;
    } else if (type === DeviceType.LIGHT) {
      init.powerStatus = powered;
      init.brightness = 60 + Math.abs(Math.floor(this.scenario.seed)) % 10;
    } else if (type === DeviceType.SENSOR) {
      init.temperature = 25 + Math.abs(Math.floor(this.scenario.seed)) % 3;
      init.humidity = 50 + Math.abs(Math.floor(this.scenario.seed)) % 5;
    } else if (type === DeviceType.AC) {
      init.powerStatus = powered;
      init.targetTemperature = 24;
      init.mode = 'COOL';
      init.modeStandard = true;
    }
    return DeviceSnapshot.create(init);
  }

  /**
   * Builds a real signed ACK, verifies it with C-05, then maps it with C-03.
   * This is the same acceptance chain a real gateway response must pass.
   */
  private async ackOutcome(command: DeviceControlCommand, replay: boolean,
    alreadyApplied: boolean, overrideResultCode?: number): Promise<ControlOutcome> {
    const seq = this.sequence;
    this.sequence = (this.sequence + 1) % (ProtocolConstants.MAX_SEQ + 1);
    const requestId = DateTimeUtil.formatRequestId(this.nowMs(), seq);
    const resultCode = overrideResultCode === undefined ?
      (this.scenario.resultCode === undefined ? 0 : this.scenario.resultCode) : overrideResultCode;
    const reported = resultCode === 0 && this.scenario.omitReportedState !== true ?
      this.reportedState(command) : undefined;
    const entries: NameValueNode[] = [];
    entries.push(new NameValueNode('request_id', JsonNode.string(requestId)));
    entries.push(new NameValueNode('seq', JsonNode.number(seq)));
    entries.push(new NameValueNode('result_code', JsonNode.number(resultCode)));
    entries.push(new NameValueNode('message', JsonNode.string(resultCode === 0 ?
      'mock executed' : 'mock gateway result ' + String(resultCode))));
    entries.push(new NameValueNode('server_time', JsonNode.string(this.nowCompact())));
    if (resultCode !== 0) {
      entries.push(new NameValueNode('error_code', JsonNode.string(
        this.scenario.errorCode === undefined ? 'mock_error' : this.scenario.errorCode)));
    }
    if (replay) {
      entries.push(new NameValueNode('idempotent_replay', JsonNode.boolean(true)));
    }
    if (reported !== undefined) {
      entries.push(new NameValueNode('reported_state', reported));
    }
    const body = Utf8.encode(JsonCanonicalizer.stringify(JsonNode.object(entries), false));
    const headers = await this.signedHeaders(requestId, seq, body);
    const expectation = new AckExpectation(requestId, seq, command.target, command.action,
      command.value, alreadyApplied);
    try {
      await this.verifier.verify(headers, body,
        ExpectedResponse.forControl(requestId, seq), this.secret);
      return ControlAckMapper.map(body, expectation, new DeviationCounter());
    } catch (error) {
      if (error instanceof AppError) {
        if (error.code === 'RESPONSE_AUTH_FAILED') {
          throw AppErrors.of('CONTROL_RESPONSE_AUTH_FAILED', []);
        }
        if (error.code === 'RESPONSE_CORRELATION_MISMATCH') {
          throw AppErrors.of('ACK_CORRELATION_MISMATCH', []);
        }
      }
      throw error;
    }
  }

  private async signedHeaders(requestId: string, seq: number,
    body: Uint8Array): Promise<HttpHeaders> {
    const digest = await this.crypto.sha256(body);
    const correlation = requestId + ':' + String(seq);
    const canonical = CanonicalBuilder.response(ResponseKind.CONTROL,
      this.scenario.badCorrelation === true ? 'mock-wrong-correlation' : correlation,
      BytesUtil.hexLower(digest));
    const mac = await this.crypto.hmacSha256(this.secret, Utf8.encode(canonical));
    let sign = BytesUtil.hexLower(mac);
    if (this.scenario.badSignature === true) {
      sign = (sign.charAt(0) === '0' ? '1' : '0') + sign.substring(1);
    }
    return HttpHeaders.from([
      new NameValue(ProtocolHeaders.RESPONSE_ALG, ProtocolConstants.ALG_HMAC_SHA256),
      new NameValue(ProtocolHeaders.RESPONSE_KEY_ID, ProtocolConstants.KEY_ID_V1),
      new NameValue(ProtocolHeaders.RESPONSE_CORRELATION,
        this.scenario.badCorrelation === true ? 'mock-wrong-correlation' : correlation),
      new NameValue(ProtocolHeaders.RESPONSE_SIGN, sign)
    ]);
  }

  private reportedState(command: DeviceControlCommand): JsonNode | undefined {
    const updatedAt = this.nowCompact();
    if (command.target === this.gatewayId) {
      if (command.action === DeviceAction.BOARD_LED_ON) {
        this.boardLed = true;
      } else if (command.action === DeviceAction.BOARD_LED_OFF) {
        this.boardLed = false;
      } else if (command.action !== DeviceAction.PING) {
        return undefined;
      }
      return JsonNode.object([
        new NameValueNode('gatewayId', JsonNode.string(this.gatewayId)),
        new NameValueNode('online', JsonNode.boolean(true)),
        new NameValueNode('boardLed', JsonNode.boolean(this.boardLed)),
        new NameValueNode('updatedAt', JsonNode.string(updatedAt))
      ]);
    }
    const entries: NameValueNode[] = [];
    entries.push(new NameValueNode('deviceId', JsonNode.string(command.target)));
    entries.push(new NameValueNode('online', JsonNode.boolean(true)));
    const value = command.value;
    if (command.action === DeviceAction.OPEN || command.action === DeviceAction.CLOSE) {
      entries.push(new NameValueNode('open', JsonNode.boolean(command.action === DeviceAction.OPEN)));
    } else if (command.action === DeviceAction.TURN_ON || command.action === DeviceAction.TURN_OFF) {
      entries.push(new NameValueNode('power', JsonNode.boolean(command.action === DeviceAction.TURN_ON)));
    } else if (command.action === DeviceAction.SET_BRIGHTNESS && typeof value === 'number') {
      entries.push(new NameValueNode('brightness', JsonNode.number(value)));
      entries.push(new NameValueNode('power', JsonNode.boolean(value > 0)));
    } else if (command.action === DeviceAction.SET_COLOR && typeof value === 'string') {
      entries.push(new NameValueNode('color', JsonNode.string(value.toUpperCase())));
    } else if (command.action === DeviceAction.SET_TARGET_TEMPERATURE && typeof value === 'number') {
      entries.push(new NameValueNode('targetTemp', JsonNode.number(value)));
      entries.push(new NameValueNode('power', JsonNode.boolean(true)));
    } else if (command.action === DeviceAction.SET_MODE && typeof value === 'string') {
      entries.push(new NameValueNode('mode', JsonNode.string(value)));
    } else {
      return undefined;
    }
    entries.push(new NameValueNode('updatedAt', JsonNode.string(updatedAt)));
    return JsonNode.object(entries);
  }

  private nowMs(): number {
    const value = this.clock.nowMs();
    if (!Number.isFinite(value)) {
      throw AppErrors.internal('clock');
    }
    return Math.floor(value);
  }

  private nowCompact(): string {
    return DateTimeUtil.formatUtcCompact(this.nowMs());
  }

  private static commandKey(command: DeviceControlCommand): string {
    const value = command.value === undefined ? '' : String(command.value);
    return command.gatewayId + '|' + command.target + '|' + String(command.action) + '|' + value;
  }
}
