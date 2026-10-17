/*
 * YaoCore C-15 IoTDA HTTPS transport adapter.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §8.5; CB §7.1; A-CB-1
 *
 * COMPILED_ONLY (no device/network verification in this environment). Uses
 * the system HTTP stack over HTTPS only. Cloud v1 has no pinned TLS profile;
 * a non-undefined TlsPolicy is rejected rather than silently ignored. No
 * platform API leaks above the HttpTransport port.
 */
import { http } from '@kit.NetworkKit';
import { AppError, AppErrors } from '../../../common/types/AppError';
import { NameValue } from '../../../common/types/NameValue';
import { HttpHeaders } from '../../../common/types/HttpHeaders';
import { JsonKind } from '../../../common/types/JsonNode';
import { JsonParser } from '../../../common/utils/JsonParser';
import { Utf8 } from '../../../common/utils/Utf8';
import type { ClockPort } from '../../../common/types/Ports';
import {
  HttpRequest,
  HttpResponse,
  TlsPolicy
} from '../../gateway/GatewayTransportPorts';
import type { HttpTransport } from '../../gateway/GatewayTransportPorts';

interface PlatformErrorLike {
  code?: number;
}

export class OhosCloudHttpTransport implements HttpTransport {
  private readonly clock: ClockPort;

  constructor(clock: ClockPort) {
    this.clock = clock;
  }

  async send(request: HttpRequest, tls: TlsPolicy | undefined): Promise<HttpResponse> {
    if (tls !== undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'cloudTlsPolicy')]);
    }
    if (!request.url.startsWith('https://')) {
      throw AppErrors.of('CLOUD_ENDPOINT_INVALID', []);
    }
    const client = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: request.method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: request.connectTimeoutMs,
        readTimeout: request.readTimeoutMs,
        usingCache: false
      };
      options.header = OhosCloudHttpTransport.toHeaderRecord(request);
      if (request.body !== undefined) {
        options.extraData = OhosCloudHttpTransport.toArrayBuffer(request.body);
      }
      const response = await client.request(request.url, options);
      const body = OhosCloudHttpTransport.responseBody(response.result);
      return new HttpResponse(response.responseCode,
        OhosCloudHttpTransport.toHeaders(response.header), body, this.nowMs());
    } catch (error) {
      throw OhosCloudHttpTransport.mapError(error);
    } finally {
      client.destroy();
    }
  }

  private static toHeaderRecord(request: HttpRequest): Record<string, string> {
    const record: Record<string, string> = {};
    const entries = request.headers.entries();
    for (let index = 0; index < entries.length; index++) {
      record[entries[index].name] = entries[index].value;
    }
    return record;
  }

  private static toHeaders(header: Object): HttpHeaders {
    const text = JSON.stringify(header);
    if (text === undefined || text.length === 0 || text === 'null') {
      return HttpHeaders.from([]);
    }
    try {
      const root = JsonParser.parse(text);
      if (root.kind !== JsonKind.OBJECT) {
        return HttpHeaders.from([]);
      }
      const entries: NameValue[] = [];
      const names = root.keys();
      for (let index = 0; index < names.length; index++) {
        const value = root.require(names[index]);
        if (value.kind === JsonKind.STRING) {
          entries.push(new NameValue(names[index], value.stringValue));
        } else if (value.kind === JsonKind.NUMBER) {
          entries.push(new NameValue(names[index], String(value.numberValue)));
        } else if (value.kind === JsonKind.BOOLEAN) {
          entries.push(new NameValue(names[index], String(value.booleanValue)));
        }
      }
      return HttpHeaders.from(entries);
    } catch (error) {
      return HttpHeaders.from([]);
    }
  }

  private static responseBody(result: string | Object | ArrayBuffer): Uint8Array {
    if (result instanceof ArrayBuffer) {
      return new Uint8Array(result);
    }
    if (typeof result === 'string') {
      return Utf8.encode(result);
    }
    return new Uint8Array(0);
  }

  private static toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
    const copy = new Uint8Array(bytes.length);
    copy.set(bytes);
    return copy.buffer;
  }

  private nowMs(): number {
    const value = this.clock.nowMs();
    return Number.isFinite(value) ? Math.floor(value) : Date.now();
  }

  private static mapError(error: Object): AppError {
    if (error instanceof AppError) {
      return error;
    }
    const code = (error as PlatformErrorLike).code;
    if (code === 2300028 || code === 2303210) {
      return AppErrors.of('CLOUD_REQUEST_FAILED', [new NameValue('reason', 'timeout')]);
    }
    return AppErrors.of('CLOUD_REQUEST_FAILED', []);
  }
}
