/*
 * YaoCore C-17 OhosHttpTransport.
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §14.1.3, §19.3 path B, §19.4; ADR-002 §6.2/§7.1
 *
 * COMPILED_ONLY / DEVICE-VERIFIED-PENDING (PB-03).
 * - P-HMAC cleartext uses @ohos.net.http (system HTTP stack).
 * - P-TLS-PIN uses @ohos.net.socket TLSSocket with skipRemoteValidation=true,
 *   then verifies SHA-256(SPKI DER) against the route pins on the SAME
 *   connection BEFORE writing any HTTP byte. A mismatch closes the socket and
 *   throws TLS_PIN_MISMATCH; there is no cleartext fallback.
 *
 * The path-B HTTP/1.1 client is deliberately minimal: one request per
 * connection, `Connection: close`, Content-Length or chunked responses. This
 * matches the contract simulator (tools/simulator) and keeps the pin check
 * before the request bytes. Connection reuse/pooling is deferred to T-19.
 */
import { http, socket } from '@kit.NetworkKit';
import { AppError, AppErrors } from '../../../common/types/AppError';
import { ProtocolHeaders } from '../../../common/constants/ProtocolConstants';
import { NameValue } from '../../../common/types/NameValue';
import { HttpHeaders } from '../../../common/types/HttpHeaders';
import { JsonKind, JsonNode } from '../../../common/types/JsonNode';
import { JsonParser } from '../../../common/utils/JsonParser';
import { BytesUtil } from '../../../common/utils/BytesUtil';
import { Utf8 } from '../../../common/utils/Utf8';
import { IpAddressUtil } from '../../../common/utils/IpAddressUtil';
import type { ClockPort } from '../../../common/types/Ports';
import type { CryptoPort } from '../../crypto/CryptoPort';
import {
  HttpRequest,
  HttpResponse,
  HttpTransport,
  TlsPolicy,
  TlsVerification
} from '../GatewayTransportPorts';
import { TlsPinCheck } from './TlsPinCheck';

interface PlatformErrorLike {
  code?: number;
}

class UrlTarget {
  readonly host: string;
  readonly port: number;
  readonly path: string;

  constructor(host: string, port: number, path: string) {
    if (!IpAddressUtil.isValidIpv4(host) || !IpAddressUtil.isValidPort(port)) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.host = host;
    this.port = port;
    this.path = path;
  }
}

class RawHttpResponse {
  readonly statusCode: number;
  readonly headers: HttpHeaders;
  readonly body: Uint8Array;

  constructor(statusCode: number, headers: HttpHeaders, body: Uint8Array) {
    this.statusCode = statusCode;
    this.headers = headers;
    this.body = body;
  }
}

const CODE_TIMEOUT: number = 2300028;
const CODE_RESOLVE_PROXY: number = 2300005;
const CODE_RESOLVE_HOST: number = 2300006;
const CODE_CONNECT: number = 2300007;
const CODE_EMPTY_RESPONSE: number = 2300052;
const CODE_INVALID_RESPONSE: number = 2300008;
const CODE_INVALID_ENCODING: number = 2300061;
const CODE_SSL_CERT: number = 2300060;

const CODE_CONNECTION_TIMED_OUT: number = 2303210;
const CODE_SSL_NULL: number = 2303501;
const CODE_SSL_VERIFY: number = 2303504;
const CODE_SSL_SYSCALL: number = 2303505;
const CODE_SSL_CLOSE: number = 2303506;
const CODE_ADDRESS_IN_USE: number = 2303198;
const CODE_ADDRESS_UNASSIGNABLE: number = 2303199;
const CODE_NOT_SOCKET: number = 2303188;
const CODE_BAD_FD: number = 2303109;
const CODE_INTERRUPTED: number = 2303104;
const CODE_TRY_AGAIN: number = 2303111;
const CODE_PROTOCOL_TYPE: number = 2303191;

export class OhosHttpTransport implements HttpTransport {
  private readonly crypto: CryptoPort;
  private readonly clock: ClockPort;

  constructor(crypto: CryptoPort, clock: ClockPort) {
    this.crypto = crypto;
    this.clock = clock;
  }

  async send(request: HttpRequest, tls: TlsPolicy | undefined): Promise<HttpResponse> {
    if (tls === undefined) {
      return this.sendCleartext(request);
    }
    return this.sendPinnedTls(request, tls);
  }

  private async sendCleartext(request: HttpRequest): Promise<HttpResponse> {
    if (!request.url.startsWith('http://')) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    const client = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: request.method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: request.connectTimeoutMs,
        readTimeout: request.readTimeoutMs,
        // T-11 F-02: the SDK default is true. A cached /discover response would
        // carry a stale challenge and every HMAC/correlation check would fail.
        // Never serve a signed LAN request from the HTTP cache.
        usingCache: false
      };
      options.header = OhosHttpTransport.clearHeader(request);
      if (request.body !== undefined) {
        options.extraData = OhosHttpTransport.toArrayBuffer(request.body);
      }
      const response = await client.request(request.url, options);
      const body = OhosHttpTransport.responseBody(response.result);
      return new HttpResponse(response.responseCode,
        OhosHttpTransport.toHeaders(response.header), body, this.nowMs());
    } catch (error) {
      throw OhosHttpTransport.mapError(error, false);
    } finally {
      client.destroy();
    }
  }

  private async sendPinnedTls(request: HttpRequest, tls: TlsPolicy): Promise<HttpResponse> {
    if (!request.url.startsWith('https://')) {
      // A TLS policy on an http URL is a configuration defect, never a reason
      // to send cleartext (ADR-002 §6.2-4).
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    TlsPinCheck.validatePins(tls.pins);
    const target = OhosHttpTransport.parseUrl(request.url);
    let tlsSocket: socket.TLSSocket | undefined = undefined;
    try {
      tlsSocket = socket.constructTLSSocketInstance();
      await OhosHttpTransport.connectTls(tlsSocket, target.host, target.port,
        request.connectTimeoutMs);
      const raw = await tlsSocket.getRemoteCertificate();
      const digestHex = await TlsPinCheck.spkiSha256Hex(this.crypto, raw);
      const matched = await TlsPinCheck.matchPin(this.crypto, digestHex, tls.pins);
      if (matched === undefined) {
        throw AppErrors.of('TLS_PIN_MISMATCH', []);
      }
      let protocolVersion = 'unknown';
      try {
        protocolVersion = await tlsSocket.getProtocol();
      } catch (error) {
        protocolVersion = 'unknown';
      }
      const verification = new TlsVerification(matched, protocolVersion, digestHex);
      // Pin is verified: only now may request bytes leave the process.
      const wire = OhosHttpTransport.buildWireRequest(request, target);
      const rawResponse = await OhosHttpTransport.exchange(tlsSocket, wire, request.readTimeoutMs);
      return new HttpResponse(rawResponse.statusCode, rawResponse.headers, rawResponse.body,
        this.nowMs(), verification);
    } catch (error) {
      throw OhosHttpTransport.mapError(error, true);
    } finally {
      if (tlsSocket !== undefined) {
        try {
          await tlsSocket.close();
        } catch (error) {
          // Never mask the verification/transport classification on close.
        }
      }
    }
  }

  private static connectTls(tlsSocket: socket.TLSSocket, host: string, port: number,
    timeoutMs: number): Promise<void> {
    return new Promise<void>((resolve, reject): void => {
      let settled = false;
      const timer = setTimeout(() => {
        if (!settled) {
          settled = true;
          reject(AppErrors.of('GATEWAY_TIMEOUT', []));
        }
      }, timeoutMs);
      tlsSocket.connect({
        address: {
          address: host,
          port: port
        },
        secureOptions: {
          protocols: [socket.Protocol.TLSv12, socket.Protocol.TLSv13]
        },
        skipRemoteValidation: true
      }).then(() => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          resolve();
        }
      }).catch((error: Object) => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          reject(OhosHttpTransport.mapError(error, true));
        }
      });
    });
  }

  private static exchange(tlsSocket: socket.TLSSocket, wire: Uint8Array,
    readTimeoutMs: number): Promise<RawHttpResponse> {
    return new Promise<RawHttpResponse>((resolve, reject): void => {
      const chunks: Uint8Array[] = [];
      let settled = false;
      const timer = setTimeout(() => {
        if (!settled) {
          settled = true;
          reject(AppErrors.of('GATEWAY_TIMEOUT', []));
        }
      }, readTimeoutMs);
      const onMessage = (info: socket.SocketMessageInfo): void => {
        const chunk = new Uint8Array(info.message);
        chunks.push(chunk);
      };
      const onClose = (): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        try {
          resolve(OhosHttpTransport.parseResponse(BytesUtil.concat(chunks)));
        } catch (error) {
          reject(OhosHttpTransport.mapError(error, true));
        }
      };
      const onError = (error: Object): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        reject(OhosHttpTransport.mapError(error, true));
      };
      tlsSocket.on('message', onMessage);
      tlsSocket.on('close', onClose);
      tlsSocket.on('error', onError);
      tlsSocket.send(OhosHttpTransport.toArrayBuffer(wire)).catch((error: Object) => {
        onError(error);
      });
    });
  }

  private static buildWireRequest(request: HttpRequest, target: UrlTarget): Uint8Array {
    const lines: string[] = [];
    lines.push(request.method + ' ' + target.path + ' HTTP/1.1');
    lines.push('Host: ' + target.host + ':' + String(target.port));
    lines.push('Connection: close');
    const entries = request.headers.entries();
    let hasContentLength = false;
    for (let index = 0; index < entries.length; index++) {
      if (entries[index].name.toLowerCase() === 'content-length') {
        hasContentLength = true;
      }
      lines.push(entries[index].name + ': ' + entries[index].value);
    }
    if (request.body !== undefined && !hasContentLength) {
      lines.push('Content-Length: ' + String(request.body.length));
    }
    const head = Utf8.encode(lines.join('\r\n') + '\r\n\r\n');
    if (request.body === undefined) {
      return head;
    }
    return BytesUtil.concat([head, request.body]);
  }

  private static parseResponse(bytes: Uint8Array): RawHttpResponse {
    const headerEnd = OhosHttpTransport.findHeaderEnd(bytes);
    if (headerEnd < 0) {
      throw AppErrors.of('LOCAL_REQUEST_FAILED', []);
    }
    const headText = Utf8.decode(bytes.subarray(0, headerEnd));
    const lines = headText.split('\r\n');
    if (lines.length === 0) {
      throw AppErrors.of('LOCAL_REQUEST_FAILED', []);
    }
    const statusParts = lines[0].split(' ');
    if (statusParts.length < 2) {
      throw AppErrors.of('LOCAL_REQUEST_FAILED', []);
    }
    const statusCode = Number.parseInt(statusParts[1], 10);
    if (!Number.isInteger(statusCode) || statusCode < 100 || statusCode > 599) {
      throw AppErrors.of('LOCAL_REQUEST_FAILED', []);
    }
    const headerEntries: NameValue[] = [];
    let contentLength = -1;
    let chunked = false;
    for (let index = 1; index < lines.length; index++) {
      const line = lines[index];
      const colon = line.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      const name = line.substring(0, colon).trim();
      const value = line.substring(colon + 1).trim();
      if (name.length === 0) {
        continue;
      }
      headerEntries.push(new NameValue(name, value));
      if (name.toLowerCase() === 'content-length') {
        const parsed = Number.parseInt(value, 10);
        if (Number.isInteger(parsed) && parsed >= 0) {
          contentLength = parsed;
        }
      }
      if (name.toLowerCase() === 'transfer-encoding' &&
        value.toLowerCase().indexOf('chunked') >= 0) {
        chunked = true;
      }
    }
    const rawBody = bytes.subarray(headerEnd + 4);
    let body: Uint8Array = rawBody;
    if (chunked) {
      body = OhosHttpTransport.decodeChunked(rawBody);
    } else if (contentLength >= 0) {
      if (rawBody.length < contentLength) {
        throw AppErrors.of('LOCAL_REQUEST_FAILED', []);
      }
      body = rawBody.subarray(0, contentLength);
    }
    return new RawHttpResponse(statusCode, HttpHeaders.from(headerEntries), body);
  }

  private static decodeChunked(input: Uint8Array): Uint8Array {
    const output: Uint8Array[] = [];
    let offset = 0;
    while (offset < input.length) {
      const lineEnd = OhosHttpTransport.findCrlf(input, offset);
      if (lineEnd < 0) {
        throw AppErrors.of('LOCAL_REQUEST_FAILED', []);
      }
      const sizeText = Utf8.decode(input.subarray(offset, lineEnd)).trim();
      const semicolon = sizeText.indexOf(';');
      const hexText = semicolon >= 0 ? sizeText.substring(0, semicolon) : sizeText;
      const size = Number.parseInt(hexText, 16);
      if (!Number.isInteger(size) || size < 0) {
        throw AppErrors.of('LOCAL_REQUEST_FAILED', []);
      }
      offset = lineEnd + 2;
      if (size === 0) {
        break;
      }
      if (offset + size > input.length) {
        throw AppErrors.of('LOCAL_REQUEST_FAILED', []);
      }
      output.push(input.subarray(offset, offset + size));
      offset += size + 2;
    }
    return BytesUtil.concat(output);
  }

  private static findHeaderEnd(bytes: Uint8Array): number {
    for (let index = 0; index + 3 < bytes.length; index++) {
      if (bytes[index] === 0x0D && bytes[index + 1] === 0x0A &&
        bytes[index + 2] === 0x0D && bytes[index + 3] === 0x0A) {
        return index;
      }
    }
    return -1;
  }

  private static findCrlf(bytes: Uint8Array, start: number): number {
    for (let index = start; index + 1 < bytes.length; index++) {
      if (bytes[index] === 0x0D && bytes[index + 1] === 0x0A) {
        return index;
      }
    }
    return -1;
  }

  private static parseUrl(url: string): UrlTarget {
    const prefix = 'https://';
    if (!url.startsWith(prefix)) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    const rest = url.substring(prefix.length);
    const slash = rest.indexOf('/');
    const authority = slash < 0 ? rest : rest.substring(0, slash);
    const path = slash < 0 ? '/' : rest.substring(slash);
    const colon = authority.lastIndexOf(':');
    if (colon <= 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    const host = authority.substring(0, colon);
    const port = Number.parseInt(authority.substring(colon + 1), 10);
    return new UrlTarget(host, port, path);
  }

  private static clearHeader(request: HttpRequest): Record<string, string> {
    const accept = request.headers.get('Accept');
    const acceptValue = accept === undefined ? 'application/json' : accept;
    if (request.body !== undefined) {
      const post: Record<string, string> = {
        'Accept': acceptValue,
        'Content-Type': 'application/json'
      };
      return post;
    }
    const signed: Record<string, string> = {
      'Accept': acceptValue,
      'X-YaoCore-Challenge': OhosHttpTransport.requiredHeader(request,
        ProtocolHeaders.CHALLENGE),
      'X-YaoCore-Request-Nonce': OhosHttpTransport.requiredHeader(request,
        ProtocolHeaders.REQUEST_NONCE),
      'X-YaoCore-Request-Timestamp': OhosHttpTransport.requiredHeader(request,
        ProtocolHeaders.REQUEST_TIMESTAMP),
      'X-YaoCore-Request-Alg': OhosHttpTransport.requiredHeader(request,
        ProtocolHeaders.REQUEST_ALG),
      'X-YaoCore-Key-Id': OhosHttpTransport.requiredHeader(request,
        ProtocolHeaders.REQUEST_KEY_ID),
      'X-YaoCore-Request-Sign': OhosHttpTransport.requiredHeader(request,
        ProtocolHeaders.REQUEST_SIGN)
    };
    return signed;
  }

  private static requiredHeader(request: HttpRequest, name: string): string {
    const value = request.headers.get(name);
    if (value === undefined) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    return value;
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
      // Malformed platform headers are not protocol input; an empty header set
      // makes subsequent response verification fail closed.
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

  private static mapError(error: Object, tls: boolean): AppError {
    if (error instanceof AppError) {
      return error;
    }
    const code = (error as PlatformErrorLike).code;
    if (tls) {
      if (code === CODE_CONNECTION_TIMED_OUT) {
        return AppErrors.of('GATEWAY_TIMEOUT', []);
      }
      if (code === CODE_INTERRUPTED || code === CODE_BAD_FD || code === CODE_TRY_AGAIN ||
        code === CODE_NOT_SOCKET || code === CODE_PROTOCOL_TYPE || code === CODE_ADDRESS_IN_USE ||
        code === CODE_ADDRESS_UNASSIGNABLE) {
        return AppErrors.of('GATEWAY_UNREACHABLE', []);
      }
      if (code === CODE_SSL_NULL || code === CODE_SSL_VERIFY || code === CODE_SSL_SYSCALL ||
        code === CODE_SSL_CLOSE) {
        return AppErrors.of('TLS_HANDSHAKE_FAILED', []);
      }
      return AppErrors.of('TLS_HANDSHAKE_FAILED', []);
    }
    if (code === CODE_TIMEOUT) {
      return AppErrors.of('GATEWAY_TIMEOUT', []);
    }
    if (code === CODE_RESOLVE_PROXY || code === CODE_RESOLVE_HOST || code === CODE_CONNECT) {
      return AppErrors.of('GATEWAY_UNREACHABLE', []);
    }
    if (code === CODE_SSL_CERT) {
      return AppErrors.of('TLS_HANDSHAKE_FAILED', []);
    }
    if (code === CODE_EMPTY_RESPONSE || code === CODE_INVALID_RESPONSE ||
      code === CODE_INVALID_ENCODING) {
      return AppErrors.of('LOCAL_REQUEST_FAILED', []);
    }
    return AppErrors.of('LOCAL_REQUEST_FAILED', []);
  }
}
