/*
 * YaoCore T-11 host fakes for C-17/C-18/C-20.
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 *
 * PUBLIC TEST DATA ONLY. No platform import; every fake records calls so tests
 * can assert zero-request and exact-retransmission behaviour. Unconfigured
 * transport calls fail instead of silently succeeding.
 */
import { AppErrors } from '../../main/ets/common/types/AppError';
import { NameValue } from '../../main/ets/common/types/NameValue';
import type { ClockPort, LoggerPort, MetricsPort, RandomPort } from '../../main/ets/common/types/Ports';
import { GatewayAddress, GatewayRoute, TlsMaterial } from '../../main/ets/model/GatewayRoute';
import type {
  GatewayAddressPort,
  GatewayCredentialPort,
  GatewayRoutePort,
  GatewaySequencePort
} from '../../main/ets/repository/GatewayPorts';
import {
  HttpRequest,
  HttpResponse,
  TlsPolicy
} from '../../main/ets/service/gateway/GatewayTransportPorts';
import type { HttpTransport } from '../../main/ets/service/gateway/GatewayTransportPorts';

export class FakeTransportClock implements ClockPort {
  value: number;

  constructor(nowMs: number) {
    this.value = nowMs;
  }

  nowMs(): number {
    return this.value;
  }

  advance(ms: number): void {
    this.value += ms;
  }
}

export class SequenceRandom implements RandomPort {
  private readonly bytes: Uint8Array;
  private cursor: number = 0;

  constructor(bytes: Uint8Array) {
    this.bytes = bytes;
  }

  async nextBytes(length: number): Promise<Uint8Array> {
    const result = new Uint8Array(length);
    for (let index = 0; index < length; index++) {
      result[index] = this.bytes[this.cursor % this.bytes.length];
      this.cursor++;
    }
    return result;
  }
}

export class RecordingLogger implements LoggerPort {
  readonly entries: string[] = [];

  debug(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
    this.entries.push('D ' + tag + ' ' + message);
  }

  info(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
    this.entries.push('I ' + tag + ' ' + message);
  }

  warn(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
    this.entries.push('W ' + tag + ' ' + message);
  }

  error(tag: string, message: string, fields?: ReadonlyArray<NameValue>): void {
    this.entries.push('E ' + tag + ' ' + message);
  }
}

export class RecordingMetrics implements MetricsPort {
  readonly names: string[] = [];
  readonly values: number[] = [];

  record(name: string, valueMs: number, tags?: ReadonlyArray<NameValue>): void {
    this.names.push(name);
    this.values.push(valueMs);
  }

  count(name: string): number {
    let total = 0;
    for (let index = 0; index < this.names.length; index++) {
      if (this.names[index] === name) {
        total++;
      }
    }
    return total;
  }
}

export class InMemoryRoutePort implements GatewayRoutePort {
  readonly routes: GatewayRoute[] = [];

  add(route: GatewayRoute): void {
    this.routes.push(route);
  }

  async listRoutes(): Promise<ReadonlyArray<GatewayRoute>> {
    return this.routes;
  }

  async listRoutesByFamily(familyId: string): Promise<ReadonlyArray<GatewayRoute>> {
    const result: GatewayRoute[] = [];
    for (let index = 0; index < this.routes.length; index++) {
      if (this.routes[index].familyId === familyId) {
        result.push(this.routes[index]);
      }
    }
    return result;
  }

  async getRoute(gatewayId: string): Promise<GatewayRoute | undefined> {
    for (let index = 0; index < this.routes.length; index++) {
      if (this.routes[index].gatewayId === gatewayId) {
        return this.routes[index];
      }
    }
    return undefined;
  }

  async isBound(gatewayId: string): Promise<boolean> {
    return (await this.getRoute(gatewayId)) !== undefined;
  }
}

export class InMemoryCredentials implements GatewayCredentialPort {
  private readonly secrets: Map<string, Uint8Array> = new Map<string, Uint8Array>();

  set(gatewayId: string, secret: Uint8Array): void {
    this.secrets.set(gatewayId, secret);
  }

  async withCommandSecret<T>(gatewayId: string,
    fn: (secret: Uint8Array) => Promise<T>): Promise<T> {
    const secret = this.secrets.get(gatewayId);
    if (secret === undefined) {
      throw AppErrors.of('GATEWAY_NOT_BOUND', []);
    }
    const copy = new Uint8Array(secret.length);
    copy.set(secret);
    try {
      return await fn(copy);
    } finally {
      copy.fill(0);
    }
  }

  async tlsMaterial(gatewayId: string): Promise<TlsMaterial | undefined> {
    return undefined;
  }
}

export class InMemorySequences implements GatewaySequencePort {
  private readonly next: Map<string, number> = new Map<string, number>();

  async nextSequence(gatewayId: string): Promise<number> {
    const value = this.next.get(gatewayId);
    const assigned = value === undefined ? 0 : value;
    this.next.set(gatewayId, assigned + 1);
    return assigned;
  }

  async peekSequence(gatewayId: string): Promise<number> {
    const value = this.next.get(gatewayId);
    return value === undefined ? 0 : value;
  }

  async resetSequenceIfIdle(gatewayId: string): Promise<number> {
    this.next.set(gatewayId, 0);
    return 0;
  }
}

export class InMemoryAddressPort implements GatewayAddressPort {
  readonly updates: GatewayAddress[] = [];

  async updateLastKnownAddress(gatewayId: string, address: GatewayAddress): Promise<void> {
    this.updates.push(address);
  }
}

export type TransportHandler = (request: HttpRequest, tls: TlsPolicy | undefined,
  attempt: number) => Promise<HttpResponse>;

export class FakeHttpTransport implements HttpTransport {
  readonly requests: HttpRequest[] = [];
  readonly tlsPolicies: Array<TlsPolicy | undefined> = [];
  private handler: TransportHandler | undefined = undefined;

  setHandler(handler: TransportHandler): void {
    this.handler = handler;
  }

  async send(request: HttpRequest, tls: TlsPolicy | undefined): Promise<HttpResponse> {
    this.requests.push(request);
    this.tlsPolicies.push(tls);
    if (this.handler === undefined) {
      throw AppErrors.of('LOCAL_REQUEST_FAILED', []);
    }
    return this.handler(request, tls, this.requests.length);
  }
}
