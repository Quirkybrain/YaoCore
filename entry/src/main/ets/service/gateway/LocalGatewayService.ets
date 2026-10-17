/*
 * YaoCore C-17 LocalGatewayService.
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §14.1-§14.6, §18.1-§18.7, §19.4; ADR-002 §6
 *
 * Pure orchestration: HMAC signing (C-05), canonical serialization and ACK
 * mapping (C-03), persistent routes/sequences (C-07), HTTP/TLS transport and
 * pin verification behind ports. No @ohos import in this file.
 *
 * Security invariants:
 * - P-TLS-PIN failures never fall back to cleartext (P-BLOCKED).
 * - Automatic retries are exact byte-for-byte replays; no re-signing.
 * - A response that carries ACK authentication material is only trusted after
 *   full verification. Non-2xx responses with material are never downgraded to
 *   HTTP_<status> and are never retried (T-11 F-01).
 * - A response is never parsed or applied before DEV-ONLY rejection + HMAC
 *   verification + correlation + ACK schema/state checks.
 * - P-TLS-PIN responses must carry successful pin evidence from the transport;
 *   the service re-checks it fail-closed (T-11 F-03).
 * - Secrets stay inside GatewayCredentialPort.withCommandSecret callbacks.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { ProtocolConstants, ProtocolHeaders } from '../../common/constants/ProtocolConstants';
import { HttpHeaders } from '../../common/types/HttpHeaders';
import { JsonKind } from '../../common/types/JsonNode';
import { JsonParser } from '../../common/utils/JsonParser';
import { Utf8 } from '../../common/utils/Utf8';
import type { ClockPort, LoggerPort, MetricsPort } from '../../common/types/Ports';
import { TransportProfile } from '../../model/DeviceTypes';
import { GatewayAddress, GatewayRoute } from '../../model/GatewayRoute';
import { DeviceControlCommand, ControlOutcome } from '../../model/ControlModels';
import { DiscoverySnapshot } from '../../model/DiscoveryModels';
import type {
  GatewayAddressPort,
  GatewayCredentialPort,
  GatewayRoutePort,
  GatewaySequencePort
} from '../../repository/GatewayPorts';
import type { DeviceControlPort } from '../../repository/DomainPorts';
import { DiscoverMapper, DiscoverMapContext } from '../protocol/DiscoverMapper';
import { ControlAckMapper, AckExpectation } from '../protocol/ControlAckMapper';
import { ControlRequestSerializer } from '../protocol/ControlRequestSerializer';
import { DeviationCounter } from '../protocol/ProtocolDeviation';
import type { ControlRequestDto } from '../protocol/dto/ControlRequestDto';
import { ClockSkewTracker } from '../security/ClockSkewTracker';
import { RequestSigner, DiscoverSigningInput, SigningInput } from '../security/RequestSigner';
import { ExpectedResponse, ResponseVerifier } from '../security/ResponseVerifier';
import { GatewayRequestPolicy, ControlPolicy } from './GatewayRequestPolicy';
import {
  GatewayTarget,
  HttpRequest,
  HttpResponse,
  ProbeResult,
  TlsPolicy,
  TlsVerification
} from './GatewayTransportPorts';
import type { HttpTransport, IGatewayClient } from './GatewayTransportPorts';

const PENDING_TTL_MS: number = 300000;
const HTTP_STATUS_CODE_PREFIX: string = 'HTTP' + '_';

export type GatewayDelay = (delayMs: number) => Promise<void>;

/** Cancellation-free delay used for retry backoff; injectable for host tests. */
function defaultDelay(delayMs: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, delayMs);
  });
}

/** Exact retransmission record (DES-A §14.3). */
export class PendingCommand {
  readonly gatewayId: string;
  readonly requestId: string;
  readonly seq: number;
  readonly body: Uint8Array;
  readonly expectation: AckExpectation;
  readonly firstSentAtMs: number;
  readonly expiresAtMs: number;
  attempts: number;
  ackApplied: boolean;

  constructor(gatewayId: string, requestId: string, seq: number, body: Uint8Array,
    expectation: AckExpectation, firstSentAtMs: number) {
    this.gatewayId = gatewayId;
    this.requestId = requestId;
    this.seq = seq;
    this.body = body;
    this.expectation = expectation;
    this.firstSentAtMs = firstSentAtMs;
    this.expiresAtMs = firstSentAtMs + PENDING_TTL_MS;
    this.attempts = 0;
    this.ackApplied = false;
  }
}

class GatewayMutex {
  private tail: Promise<void> = Promise.resolve();

  async run<T>(task: () => Promise<T>): Promise<T> {
    const previous = this.tail;
    let release: () => void = () => {};
    this.tail = new Promise<void>((resolve: () => void) => {
      release = resolve;
    });
    await previous;
    try {
      return await task();
    } finally {
      release();
    }
  }
}

class RuntimeProfile {
  readonly profile: TransportProfile;
  readonly tlsPolicy?: TlsPolicy;

  constructor(profile: TransportProfile, tlsPolicy?: TlsPolicy) {
    this.profile = profile;
    this.tlsPolicy = tlsPolicy;
  }
}

class DiscoverExecution {
  readonly snapshot: DiscoverySnapshot;
  readonly tlsVerification?: TlsVerification;
  readonly latencyMs: number;

  constructor(snapshot: DiscoverySnapshot, tlsVerification: TlsVerification | undefined,
    latencyMs: number) {
    this.snapshot = snapshot;
    this.tlsVerification = tlsVerification;
    this.latencyMs = latencyMs;
  }
}

export class LocalGatewayService implements IGatewayClient, DeviceControlPort {
  private readonly transport: HttpTransport;
  private readonly signer: RequestSigner;
  private readonly verifier: ResponseVerifier;
  private readonly credentials: GatewayCredentialPort;
  private readonly sequences: GatewaySequencePort;
  private readonly routes: GatewayRoutePort;
  private readonly addresses: GatewayAddressPort;
  private readonly clock: ClockPort;
  private readonly clockSkew: ClockSkewTracker;
  private readonly logger: LoggerPort;
  private readonly metrics: MetricsPort;
  private readonly policy: GatewayRequestPolicy;
  private readonly delay: (delayMs: number) => Promise<void>;
  private readonly mutexes: Map<string, GatewayMutex> = new Map<string, GatewayMutex>();
  private readonly pending: Map<string, PendingCommand> = new Map<string, PendingCommand>();

  constructor(transport: HttpTransport, signer: RequestSigner, verifier: ResponseVerifier,
    credentials: GatewayCredentialPort, sequences: GatewaySequencePort, routes: GatewayRoutePort,
    addresses: GatewayAddressPort, clock: ClockPort, clockSkew: ClockSkewTracker,
    logger: LoggerPort, metrics: MetricsPort, policy: GatewayRequestPolicy,
    delay?: GatewayDelay) {
    this.transport = transport;
    this.signer = signer;
    this.verifier = verifier;
    this.credentials = credentials;
    this.sequences = sequences;
    this.routes = routes;
    this.addresses = addresses;
    this.clock = clock;
    this.clockSkew = clockSkew;
    this.logger = logger;
    this.metrics = metrics;
    this.policy = policy;
    this.delay = delay === undefined ? defaultDelay : delay;
  }

  async discover(target: GatewayTarget): Promise<DiscoverySnapshot> {
    const execution = await this.performDiscover(target, this.credentials);
    return execution.snapshot;
  }

  async probe(target: GatewayTarget, credentials?: GatewayCredentialPort): Promise<ProbeResult> {
    const execution = await this.performDiscover(target,
      credentials === undefined ? this.credentials : credentials);
    const runtime = this.resolveRuntimeProfile(target);
    // Defense in depth: performDiscover already checked the evidence, but probe
    // is the binding-probe contract and must never report a P-TLS-PIN target as
    // reachable without a pin that belongs to the route (T-11 F-03).
    const tlsPinMatched = this.requireTlsEvidence(target, runtime,
      execution.tlsVerification);
    return new ProbeResult(true, execution.snapshot.gatewayId, execution.snapshot.gatewayName,
      runtime.profile, tlsPinMatched, execution.latencyMs, execution.snapshot);
  }

  async control(target: GatewayTarget, command: DeviceControlCommand): Promise<ControlOutcome> {
    if (command.gatewayId !== target.gatewayId) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    ControlPolicy.validate(undefined, true, command.action, command.value);
    const runtime = this.resolveRuntimeProfile(target);
    const normalizedValue = ControlPolicy.normalizeValue(command.action, command.value);
    const mutex = this.mutexFor(target.gatewayId);
    return mutex.run<ControlOutcome>(async (): Promise<ControlOutcome> => {
      this.prunePending();
      const startedAtMs = this.requireClock();
      const seq = await this.sequences.nextSequence(target.gatewayId);
      return this.credentials.withCommandSecret(target.gatewayId,
        async (secret: Uint8Array): Promise<ControlOutcome> => {
          const signed = await this.signer.signControl(
            new SigningInput(target.gatewayId, command.target, command.action, normalizedValue),
            secret, seq);
          const dto: ControlRequestDto = {
            request_id: signed.requestId,
            cmd_id: ProtocolConstants.CMD_ID_CONTROL,
            seq: signed.seq,
            target: signed.target,
            payload: {
              action: String(command.action),
              value: normalizedValue
            },
            timestamp: signed.timestamp,
            nonce: signed.nonce,
            alg: ProtocolConstants.ALG_HMAC_SHA256,
            key_id: ProtocolConstants.KEY_ID_V1,
            sign: signed.sign
          };
          const body = ControlRequestSerializer.serialize(dto);
          const expectation = new AckExpectation(signed.requestId, signed.seq, command.target,
            command.action, normalizedValue, false);
          const pending = new PendingCommand(target.gatewayId, signed.requestId, signed.seq,
            body, expectation, startedAtMs);
          this.pending.set(target.gatewayId, pending);
          const request = this.buildRequest('POST', target, ProtocolConstants.CONTROL_PATH,
            this.mergeHeaders(HttpHeaders.from([]), true), body);
          return this.sendWithRetry(target, request, runtime, expectation, secret, pending, startedAtMs);
        });
    });
  }

  /**
   * DeviceControlPort adapter (C-11/SceneService). Builds the target from the
   * bound route and delegates to control(). An unbound or address-less route is
   * a hard GATEWAY_NOT_BOUND, never a guess.
   */
  async send(command: DeviceControlCommand): Promise<ControlOutcome> {
    const route = await this.routes.getRoute(command.gatewayId);
    if (route === undefined || !(await this.routes.isBound(command.gatewayId))) {
      throw AppErrors.gateway('GATEWAY_NOT_BOUND', command.gatewayId);
    }
    const target = this.targetFromRoute(route);
    return this.control(target, command);
  }

  private async performDiscover(target: GatewayTarget,
    credentials: GatewayCredentialPort): Promise<DiscoverExecution> {
    const runtime = this.resolveRuntimeProfile(target);
    const startedAtMs = this.requireClock();
    return credentials.withCommandSecret(target.gatewayId,
      async (secret: Uint8Array): Promise<DiscoverExecution> => {
        const signed = await this.signer.signDiscover(
          new DiscoverSigningInput(target.gatewayId), secret);
        const request = this.buildRequest('GET', target, ProtocolConstants.DISCOVER_PATH,
          this.mergeHeaders(signed.headers, false), undefined);
        const response = await this.sendTransport(target, request, runtime);
        this.requireTlsEvidence(target, runtime, response.tlsVerification);
        this.rejectDevOnly(response);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw AppErrors.transport(HTTP_STATUS_CODE_PREFIX + String(response.statusCode),
            response.statusCode);
        }
        await this.verifier.verify(response.headers, response.body,
          ExpectedResponse.forDiscover(signed.challenge), secret);
        const deviations = new DeviationCounter();
        const snapshot = DiscoverMapper.map(response.body,
          new DiscoverMapContext(target.gatewayId, this.requireClock()), deviations);
        const elapsedMs = Math.max(0, this.requireClock() - startedAtMs);
        this.metrics.record('lan.discover.ms', elapsedMs,
          [new NameValue('profile', String(runtime.profile))]);
        this.clockSkew.observe(snapshot.generatedAt, this.requireClock());
        return new DiscoverExecution(snapshot, response.tlsVerification, elapsedMs);
      });
  }

  private async sendWithRetry(target: GatewayTarget, request: HttpRequest,
    runtime: RuntimeProfile, expectation: AckExpectation, secret: Uint8Array,
    pending: PendingCommand, startedAtMs: number): Promise<ControlOutcome> {
    let lastError: AppError = AppErrors.transport('LOCAL_REQUEST_FAILED');
    for (let attempt = 1; attempt <= this.policy.maxAttempts; attempt++) {
      if (this.requireClock() >= pending.expiresAtMs) {
        throw AppErrors.transport('GATEWAY_TIMEOUT');
      }
      pending.attempts = attempt;
      try {
        const transportStartedAtMs = this.requireClock();
        const response = await this.sendTransport(target, request, runtime);
        const transportMs = Math.max(0, this.requireClock() - transportStartedAtMs);
        this.metrics.record('lan.control.transport.ms', transportMs,
          [new NameValue('attempt', String(attempt))]);
        this.requireTlsEvidence(target, runtime, response.tlsVerification);
        this.rejectDevOnly(response);
        const attemptOutcome = await this.classifyControlResponse(response, expectation, secret);
        if (attemptOutcome !== undefined) {
          pending.ackApplied = attemptOutcome.ackAccepted;
          const totalMs = Math.max(0, this.requireClock() - startedAtMs);
          this.metrics.record('lan.control.commit.ms', totalMs,
            [new NameValue('attempt', String(attempt))]);
          return attemptOutcome;
        }
        lastError = AppErrors.transport(HTTP_STATUS_CODE_PREFIX + String(response.statusCode),
          response.statusCode);
        if (!LocalGatewayService.isRetryable(lastError)) {
          throw lastError;
        }
      } catch (error) {
        lastError = error instanceof AppError ? error : AppErrors.transport('LOCAL_REQUEST_FAILED');
        if (!LocalGatewayService.isRetryable(lastError)) {
          throw lastError;
        }
      }
      if (attempt >= this.policy.maxAttempts) {
        break;
      }
      const delayMs = this.policy.retryDelayMs(attempt);
      if (this.requireClock() + delayMs >= pending.expiresAtMs) {
        break;
      }
      await this.delay(delayMs);
    }
    this.logger.warn('LocalGatewayService', 'control_exhausted',
      [new NameValue('gatewayId', target.gatewayId),
        new NameValue('requestId', pending.requestId),
        new NameValue('code', lastError.code)]);
    throw lastError;
  }

  /**
   * Returns an outcome when the response carries a trusted ACK; undefined when
   * a 4xx/5xx response has no ACK authentication material at all and must be
   * classified as HTTP_<status>.
   *
   * T-11 F-01 / DES-A §14.3/§18.9: a response that DOES carry ACK material
   * (any X-YaoCore-Response-* header or an ACK-shaped body) is authoritative
   * only after full verification. Verification/protocol failures are thrown
   * unchanged and are never retried, including on 5xx.
   */
  private async classifyControlResponse(response: HttpResponse, expectation: AckExpectation,
    secret: Uint8Array): Promise<ControlOutcome | undefined> {
    const httpFailure = response.statusCode < 200 || response.statusCode >= 300;
    if (!httpFailure) {
      return this.mapControlAck(response, expectation, secret);
    }
    if (!LocalGatewayService.hasAckAuthenticationMaterial(response)) {
      return undefined;
    }
    return this.mapControlAck(response, expectation, secret);
  }

  /**
   * F-01: distinguishes "no authentication material" (plain HTTP error) from
   * "material present but possibly bad" (must fail closed). Reading the body
   * here is classification only; it is never trusted without verification.
   */
  private static hasAckAuthenticationMaterial(response: HttpResponse): boolean {
    const headers = response.headers;
    if (headers.has(ProtocolHeaders.RESPONSE_ALG) ||
      headers.has(ProtocolHeaders.RESPONSE_KEY_ID) ||
      headers.has(ProtocolHeaders.RESPONSE_CORRELATION) ||
      headers.has(ProtocolHeaders.RESPONSE_SIGN)) {
      return true;
    }
    if (response.body.length === 0) {
      return false;
    }
    try {
      const root = JsonParser.parse(Utf8.decode(response.body));
      return root.kind === JsonKind.OBJECT && root.has('request_id') && root.has('seq');
    } catch (error) {
      return false;
    }
  }

  /**
   * F-03: the service layer independently requires P-TLS-PIN responses to carry
   * verification evidence whose matched pin belongs to the bound route and
   * whose peer SPKI equals that pin. A transport that skips the check cannot
   * turn this into a reachable P-TLS-PIN result.
   */
  private requireTlsEvidence(target: GatewayTarget, runtime: RuntimeProfile,
    verification: TlsVerification | undefined): string | undefined {
    if (runtime.profile !== TransportProfile.P_TLS_PIN) {
      return undefined;
    }
    if (verification === undefined) {
      this.logSecurityEvent(target.gatewayId, runtime.profile, 'TLS_VERIFIER_UNAVAILABLE');
      throw AppErrors.of('TLS_VERIFIER_UNAVAILABLE', []);
    }
    if (target.pins.indexOf(verification.matchedPin) < 0) {
      this.logSecurityEvent(target.gatewayId, runtime.profile, 'TLS_PIN_MISMATCH');
      throw AppErrors.of('TLS_PIN_MISMATCH', []);
    }
    if (verification.matchedPin !== verification.peerSpkiSha256Hex) {
      this.logSecurityEvent(target.gatewayId, runtime.profile, 'TLS_HANDSHAKE_FAILED');
      throw AppErrors.of('TLS_HANDSHAKE_FAILED', []);
    }
    return verification.matchedPin;
  }

  /**
   * F-05 / DES-A §14.5: pin/handshake/profile security events record only
   * gatewayId, profile, errorCode and time. No certificate, secret or body.
   */
  private logSecurityEvent(gatewayId: string, profile: TransportProfile, errorCode: string): void {
    this.logger.warn('LocalGatewayService', 'tls_security_event', [
      new NameValue('gatewayId', gatewayId),
      new NameValue('profile', String(profile)),
      new NameValue('errorCode', errorCode),
      new NameValue('atMs', String(this.safeNowMs()))
    ]);
  }

  /** Transport seam with TLS-failure security logging (F-05). */
  private async sendTransport(target: GatewayTarget, request: HttpRequest,
    runtime: RuntimeProfile): Promise<HttpResponse> {
    try {
      return await this.transport.send(request, runtime.tlsPolicy);
    } catch (error) {
      const appError = error instanceof AppError ? error : AppErrors.transport('LOCAL_REQUEST_FAILED');
      if (LocalGatewayService.isTlsFailure(appError.code)) {
        this.logSecurityEvent(target.gatewayId, runtime.profile, appError.code);
      }
      throw appError;
    }
  }

  private safeNowMs(): number {
    const value = this.clock.nowMs();
    return Number.isFinite(value) ? Math.floor(value) : 0;
  }

  private async mapControlAck(response: HttpResponse, expectation: AckExpectation,
    secret: Uint8Array): Promise<ControlOutcome> {
    await this.verifier.verify(response.headers, response.body,
      ExpectedResponse.forControl(expectation.requestId, expectation.seq), secret);
    const deviations = new DeviationCounter();
    return ControlAckMapper.map(response.body, expectation, deviations);
  }

  private buildRequest(method: string, target: GatewayTarget, path: string,
    headers: HttpHeaders, body: Uint8Array | undefined): HttpRequest {
    const secure = target.profile === TransportProfile.P_TLS_PIN;
    const scheme = secure ? 'https' : 'http';
    const url = scheme + '://' + target.address.ip + ':' + String(target.address.port) + path;
    const timeoutMs = path === ProtocolConstants.DISCOVER_PATH ?
      this.policy.discoverTimeoutMs : this.policy.readTimeoutMs;
    return new HttpRequest(method, url, headers, body, this.policy.connectTimeoutMs, timeoutMs);
  }

  private mergeHeaders(signed: HttpHeaders, jsonBody: boolean): HttpHeaders {
    const entries: NameValue[] = [];
    const signedEntries = signed.entries();
    for (let index = 0; index < signedEntries.length; index++) {
      entries.push(signedEntries[index]);
    }
    entries.push(new NameValue('Accept', 'application/json'));
    if (jsonBody) {
      entries.push(new NameValue(ProtocolHeaders.CONTENT_TYPE, 'application/json'));
    }
    return HttpHeaders.from(entries);
  }

  private resolveRuntimeProfile(target: GatewayTarget): RuntimeProfile {
    if (target.profile === TransportProfile.P_BLOCKED) {
      this.logSecurityEvent(target.gatewayId, target.profile, 'GATEWAY_PROFILE_BLOCKED');
      throw AppErrors.gateway('GATEWAY_PROFILE_BLOCKED', target.gatewayId);
    }
    if (target.profile === TransportProfile.P_HMAC) {
      if (!this.policy.allowCleartext) {
        // Test/high-security mode only; never a TLS downgrade path.
        throw AppErrors.of('CONFIGURATION_ERROR', []);
      }
      if (target.pins.length !== 0) {
        this.logSecurityEvent(target.gatewayId, target.profile, 'TLS_PROFILE_INCONSISTENT');
        throw AppErrors.of('TLS_PROFILE_INCONSISTENT', []);
      }
      return new RuntimeProfile(TransportProfile.P_HMAC);
    }
    if (target.pins.length < 1 || target.pins.length > ProtocolConstants.MAX_PIN_COUNT) {
      this.logSecurityEvent(target.gatewayId, target.profile, 'TLS_PROFILE_INCONSISTENT');
      throw AppErrors.of('TLS_PROFILE_INCONSISTENT', []);
    }
    for (let index = 0; index < target.pins.length; index++) {
      if (!ProtocolConstants.PIN_PATTERN.test(target.pins[index])) {
        this.logSecurityEvent(target.gatewayId, target.profile, 'TLS_PROFILE_INCONSISTENT');
        throw AppErrors.of('TLS_PROFILE_INCONSISTENT', []);
      }
    }
    const tlsPolicy = new TlsPolicy(true, target.pins, target.port, 'sha256-spki-der');
    return new RuntimeProfile(TransportProfile.P_TLS_PIN, tlsPolicy);
  }

  private rejectDevOnly(response: HttpResponse): void {
    const marker = response.headers.get(ProtocolHeaders.SIMULATOR);
    if (marker === undefined) {
      return;
    }
    const normalized = marker.trim().toUpperCase();
    if (normalized === ProtocolHeaders.DEV_ONLY_VALUE ||
      normalized === ProtocolHeaders.DEV_SIMULATOR_ONLY) {
      throw AppErrors.of('DEV_SIMULATOR_REJECTED', []);
    }
  }

  private targetFromRoute(route: GatewayRoute): GatewayTarget {
    const ip = route.lastKnownIp.length > 0 ? route.lastKnownIp : route.localIp;
    if (ip.length === 0) {
      throw AppErrors.gateway('GATEWAY_NOT_BOUND', route.gatewayId);
    }
    if (route.profile === TransportProfile.P_TLS_PIN && !route.tlsEnabled) {
      this.logSecurityEvent(route.gatewayId, route.profile, 'TLS_PROFILE_INCONSISTENT');
      throw AppErrors.of('TLS_PROFILE_INCONSISTENT', []);
    }
    return new GatewayTarget(route.gatewayId, route.familyId,
      new GatewayAddress(ip, route.port), route.profile, route.pins, route.port,
      route.credentialAlias);
  }

  private mutexFor(gatewayId: string): GatewayMutex {
    const existing = this.mutexes.get(gatewayId);
    if (existing !== undefined) {
      return existing;
    }
    const created = new GatewayMutex();
    this.mutexes.set(gatewayId, created);
    return created;
  }

  private prunePending(): void {
    const nowMs = this.requireClock();
    const expired: string[] = [];
    this.pending.forEach((entry: PendingCommand, key: string) => {
      if (nowMs >= entry.expiresAtMs) {
        expired.push(key);
      }
    });
    for (let index = 0; index < expired.length; index++) {
      this.pending.delete(expired[index]);
    }
  }

  private requireClock(): number {
    const nowMs = this.clock.nowMs();
    if (!Number.isFinite(nowMs)) {
      throw AppErrors.internal('clock');
    }
    return Math.floor(nowMs);
  }

  private static isRetryable(error: AppError): boolean {
    if (error.code === 'GATEWAY_UNREACHABLE' || error.code === 'GATEWAY_TIMEOUT' ||
      error.code === 'LOCAL_REQUEST_FAILED') {
      return true;
    }
    if (error.code.startsWith('HTTP_')) {
      const status = Number.parseInt(error.code.substring('HTTP_'.length), 10);
      return status >= 500;
    }
    return false;
  }

  private static isTlsFailure(code: string): boolean {
    return code === 'GATEWAY_PROFILE_BLOCKED' || code.startsWith('TLS_');
  }
}
