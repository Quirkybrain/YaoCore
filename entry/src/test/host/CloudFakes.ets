/*
 * YaoCore T-14 host fakes for C-15.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 *
 * PUBLIC TEST DATA ONLY. Every fake records calls so tests can prove that
 * an IoTDA 2xx is not completion and that no request is sent when config or
 * token is missing. No platform import.
 */
import { AppError, AppErrors } from '../../main/ets/common/types/AppError';
import { HttpHeaders } from '../../main/ets/common/types/HttpHeaders';
import type {
  CancellationToken,
  ClockPort,
  RandomPort
} from '../../main/ets/common/types/Ports';
import { CloudConfig } from '../../main/ets/model/FamilyModels';
import type {
  HttpRequest,
  HttpResponse,
  HttpTransport,
  TlsPolicy
} from '../../main/ets/service/gateway/GatewayTransportPorts';
import type {
  CloudConfigStore,
  CloudCredentialPort,
  TimerPort
} from '../../main/ets/service/cloud/CloudPorts';

export class FakeCloudClock implements ClockPort {
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

export class FixedRandom implements RandomPort {
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

export class InMemoryCloudConfigStore implements CloudConfigStore {
  config: CloudConfig | undefined = undefined;
  saves: number = 0;
  clears: number = 0;

  constructor(config?: CloudConfig) {
    this.config = config;
  }

  async load(): Promise<CloudConfig | undefined> {
    return this.config;
  }

  async save(config: CloudConfig): Promise<void> {
    this.config = config;
    this.saves++;
  }

  async clear(): Promise<void> {
    this.config = undefined;
    this.clears++;
  }
}

export class InMemoryCloudCredentials implements CloudCredentialPort {
  token: string | undefined = undefined;
  updatedAtValue: string | undefined = undefined;
  puts: number = 0;
  removals: number = 0;
  failHasToken: AppError | undefined = undefined;

  constructor(token?: string, updatedAt?: string) {
    this.token = token;
    this.updatedAtValue = updatedAt;
  }

  async hasToken(): Promise<boolean> {
    if (this.failHasToken !== undefined) {
      throw this.failHasToken;
    }
    return this.token !== undefined && this.token.length > 0;
  }

  async withToken<T>(fn: (token: string) => Promise<T>): Promise<T> {
    if (this.token === undefined || this.token.length === 0) {
      throw AppErrors.of('CLOUD_TOKEN_MISSING', []);
    }
    return fn(this.token);
  }

  async putToken(token: string): Promise<void> {
    this.token = token;
    this.puts++;
  }

  async removeToken(): Promise<void> {
    this.token = undefined;
    this.removals++;
  }

  async updatedAt(): Promise<string | undefined> {
    return this.updatedAtValue;
  }
}

export class ImmediateCloudTimer implements TimerPort {
  readonly sleeps: number[] = [];
  cancelled: number = 0;
  onSleep: (() => void) | undefined = undefined;

  async sleep(ms: number, cancellation?: CancellationToken): Promise<void> {
    if (cancellation !== undefined && cancellation.cancelled) {
      throw AppErrors.of('PROVISIONING_CANCELLED', []);
    }
    this.sleeps.push(ms);
    if (this.onSleep !== undefined) {
      const hook = this.onSleep;
      this.onSleep = undefined;
      hook();
    }
    return Promise.resolve();
  }

  cancel(): void {
    this.cancelled++;
  }
}

export class ScriptedCloudTransport implements HttpTransport {
  readonly requests: HttpRequest[] = [];
  private readonly responses: HttpResponse[] = [];
  private readonly errors: Array<AppError | undefined> = [];

  enqueue(response: HttpResponse): void {
    this.responses.push(response);
    this.errors.push(undefined);
  }

  enqueueError(error: AppError): void {
    this.responses.push(new HttpResponse(500, HttpHeaders.from([]), new Uint8Array(0), 0));
    this.errors.push(error);
  }

  async send(request: HttpRequest, tls: TlsPolicy | undefined): Promise<HttpResponse> {
    this.requests.push(request);
    const index = this.requests.length - 1;
    const error = this.errors[index];
    if (error !== undefined) {
      throw error;
    }
    const response = this.responses[index];
    if (response === undefined) {
      throw AppErrors.of('LOCAL_REQUEST_FAILED', []);
    }
    return response;
  }
}
