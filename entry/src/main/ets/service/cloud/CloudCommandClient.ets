/*
 * YaoCore C-15 IoTDA CreateCommand client.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §8.1.4, §8.2, §8.3.2; CB §2.4/§7.1; PR-09
 *
 * The body carries the 10 signed CamelCase fields (plus Sign) and never
 * `object_device_id`. A 2xx response is an IoTDA acceptance receipt only; it
 * is never execution confirmation.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { HttpHeaders } from '../../common/types/HttpHeaders';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';
import { JsonKind, JsonNode } from '../../common/types/JsonNode';
import { JsonParser, JsonLimits } from '../../common/utils/JsonParser';
import { JsonAtom } from '../../common/utils/JsonAtom';
import { Utf8 } from '../../common/utils/Utf8';
import { BytesUtil } from '../../common/utils/BytesUtil';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import type { ClockPort, LoggerPort, RandomPort, CancellationToken } from '../../common/types/Ports';
import type { DeviceControlCommand } from '../../model/ControlModels';
import type { CryptoPort } from '../crypto/CryptoPort';
import type {
  GatewayCredentialPort,
  GatewaySequencePort
} from '../../repository/GatewayPorts';
import {
  HttpRequest,
  HttpResponse
} from '../gateway/GatewayTransportPorts';
import type { HttpTransport } from '../gateway/GatewayTransportPorts';
import { CanonicalBuilder, CloudCanonicalFields } from '../security/CanonicalBuilder';
import { CloudCommandSerializer } from '../protocol/CloudCommandSerializer';
import type { CloudCommandDto } from '../protocol/dto/CloudDto';
import type { CloudConfigStore, CloudCredentialPort } from './CloudPorts';
import {
  CloudCommandReceipt,
  CloudCommandResponseDto
} from './CloudModels';
import { CloudConfigValidator } from './CloudConfigValidator';
import { CloudErrors } from './CloudErrors';

const CONNECT_TIMEOUT_MS: number = 10000;
const READ_TIMEOUT_MS: number = 15000;
const RESPONSE_BODY_LIMIT: number = 65536;

export class CloudSendRetryPolicy {
  readonly maxRetries: number;
  readonly backoffMs: number;

  constructor(maxRetries: number = 1, backoffMs: number = 500) {
    if (!Number.isInteger(maxRetries) || maxRetries < 0 || maxRetries > 3 ||
      !Number.isFinite(backoffMs) || backoffMs < 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.maxRetries = maxRetries;
    this.backoffMs = backoffMs;
  }

  static defaults(): CloudSendRetryPolicy {
    return new CloudSendRetryPolicy();
  }
}

export class CloudCommandClient {
  private readonly transport: HttpTransport;
  private readonly configs: CloudConfigStore;
  private readonly credentials: CloudCredentialPort;
  private readonly gatewayCredentials: GatewayCredentialPort;
  private readonly sequences: GatewaySequencePort;
  private readonly crypto: CryptoPort;
  private readonly clock: ClockPort;
  private readonly random: RandomPort;
  private readonly logger: LoggerPort;
  private readonly retryPolicy: CloudSendRetryPolicy;

  constructor(transport: HttpTransport, configs: CloudConfigStore,
    credentials: CloudCredentialPort, gatewayCredentials: GatewayCredentialPort,
    sequences: GatewaySequencePort, crypto: CryptoPort, clock: ClockPort, random: RandomPort,
    logger: LoggerPort, retryPolicy: CloudSendRetryPolicy = CloudSendRetryPolicy.defaults()) {
    this.transport = transport;
    this.configs = configs;
    this.credentials = credentials;
    this.gatewayCredentials = gatewayCredentials;
    this.sequences = sequences;
    this.crypto = crypto;
    this.clock = clock;
    this.random = random;
    this.logger = logger;
    this.retryPolicy = retryPolicy;
  }

  async send(command: DeviceControlCommand,
    cancellation?: CancellationToken): Promise<CloudCommandReceipt> {
    if (cancellation !== undefined && cancellation.cancelled) {
      throw AppErrors.of('PROVISIONING_CANCELLED', []);
    }
    const config = await this.configs.load();
    if (config === undefined) {
      throw AppErrors.of('CLOUD_NOT_CONFIGURED', []);
    }
    const validation = CloudConfigValidator.validate(config);
    if (!validation.valid) {
      throw validation.errors[0];
    }
    const commandEndpoint = validation.commandEndpoint;
    if (commandEndpoint === undefined) {
      throw AppErrors.of('CLOUD_ENDPOINT_INVALID', []);
    }
    if (!(await this.credentials.hasToken())) {
      throw AppErrors.of('CLOUD_TOKEN_MISSING', []);
    }
    let seq = 0;
    try {
      seq = await this.sequences.nextSequence(command.gatewayId);
      if (!Number.isInteger(seq) || seq < 0 || seq > ProtocolConstants.MAX_SEQ) {
        throw AppErrors.of('CLOUD_SEQUENCE_UNAVAILABLE', []);
      }
    } catch (error) {
      throw AppErrors.of('CLOUD_SEQUENCE_UNAVAILABLE', []);
    }
    const nowMs = this.clock.nowMs();
    const timestamp = DateTimeUtil.formatUtcCompact(nowMs);
    const requestId = DateTimeUtil.formatRequestId(nowMs, seq);
    const nonceBytes = await this.random.nextBytes(16);
    if (nonceBytes.length !== 16) {
      throw AppErrors.of('INTERNAL_ERROR', [new NameValue('field', 'nonce')]);
    }
    const nonce = BytesUtil.hexLower(nonceBytes);
    if (!ProtocolConstants.HEX_LOWER_32.test(nonce)) {
      throw AppErrors.of('INTERNAL_ERROR', [new NameValue('field', 'nonce')]);
    }
    const valueText = JsonAtom.encode(command.value);
    const canonical = CanonicalBuilder.cloudCommand(new CloudCanonicalFields(requestId,
      ProtocolConstants.CMD_ID_CLOUD, seq, command.target, command.action, valueText, timestamp,
      nonce, ProtocolConstants.ALG_HMAC_SHA256, ProtocolConstants.KEY_ID_V1));
    return this.credentials.withToken(async (token: string): Promise<CloudCommandReceipt> => {
      return this.gatewayCredentials.withCommandSecret(command.gatewayId,
        async (secret: Uint8Array): Promise<CloudCommandReceipt> => {
          const signBytes = await this.crypto.hmacSha256(secret, Utf8.encode(canonical));
          const sign = BytesUtil.hexLower(signBytes);
          BytesUtil.zeroize(signBytes);
          const dto: CloudCommandDto = {
            service_id: ProtocolConstants.SERVICE_ID_CLOUD,
            command_name: 'SetDeviceStatus',
            paras: {
              RequestId: requestId,
              CmdId: ProtocolConstants.CMD_ID_CLOUD,
              Seq: seq,
              TargetDevice: command.target,
              Action: command.action,
              Value: valueText,
              Timestamp: timestamp,
              Nonce: nonce,
              Alg: ProtocolConstants.ALG_HMAC_SHA256,
              KeyId: ProtocolConstants.KEY_ID_V1,
              Sign: sign
            }
          };
          const body = CloudCommandSerializer.serialize(dto);
          const headers = HttpHeaders.from([
            new NameValue('X-Auth-Token', token),
            new NameValue('Content-Type', 'application/json'),
            new NameValue('Accept', 'application/json')
          ]);
          const request = new HttpRequest('POST', commandEndpoint, headers, body,
            CONNECT_TIMEOUT_MS, READ_TIMEOUT_MS);
          return this.sendWithRetry(request, requestId, seq, command.gatewayId, command.target);
        });
    });
  }

  private async sendWithRetry(request: HttpRequest, requestId: string, seq: number,
    gatewayId: string, targetDevice: string): Promise<CloudCommandReceipt> {
    let attempt = 0;
    while (true) {
      try {
        const response = await this.transport.send(request, undefined);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return await this.accept(response, requestId, seq, gatewayId, targetDevice);
        }
        if (CloudErrors.retryableStatus(response.statusCode) &&
          attempt < this.retryPolicy.maxRetries) {
          attempt++;
          await this.delay(this.retryPolicy.backoffMs);
          continue;
        }
        throw CloudErrors.http(response.statusCode, requestId, seq, targetDevice);
      } catch (error) {
        throw this.mapTransportError(error, requestId, seq, targetDevice);
      }
    }
  }

  private async accept(response: HttpResponse, requestId: string, seq: number,
    gatewayId: string, targetDevice: string): Promise<CloudCommandReceipt> {
    const bodySha = BytesUtil.hexLower(await this.crypto.sha256(response.body));
    const dto = this.parseResponse(response, requestId, seq, targetDevice);
    if (dto.errorCode !== undefined) {
      // 2xx with an error field is still an IoTDA acceptance fact, but the
      // anomaly is recorded and never promotes execution confirmation.
      this.logger.warn('cloud.command', 'CLOUD_RESPONSE_INVALID', [
        new NameValue('requestId', requestId),
        new NameValue('seq', String(seq)),
        new NameValue('shape', dto.rawShape)
      ]);
    }
    return new CloudCommandReceipt(gatewayId, requestId, seq, response.statusCode,
      this.clock.nowMs(), dto.commandId, bodySha);
  }

  private parseResponse(response: HttpResponse, requestId: string, seq: number,
    targetDevice: string): CloudCommandResponseDto {
    if (response.body.length === 0) {
      return new CloudCommandResponseDto('UNKNOWN');
    }
    if (response.body.length > RESPONSE_BODY_LIMIT) {
      this.logger.warn('cloud.command', 'CLOUD_RESPONSE_INVALID', [
        new NameValue('requestId', requestId),
        new NameValue('field', 'body')
      ]);
      return new CloudCommandResponseDto('UNKNOWN');
    }
    try {
      const root = JsonParser.parse(Utf8.decode(response.body), JsonLimits.defaults());
      if (root.kind !== JsonKind.OBJECT) {
        this.logger.warn('cloud.command', 'CLOUD_RESPONSE_INVALID', [
          new NameValue('requestId', requestId),
          new NameValue('field', 'root')
        ]);
        return new CloudCommandResponseDto('UNKNOWN');
      }
      const commandId = this.firstString(root, 'command_id', 'commandId');
      const errorCode = this.firstString(root, 'error_code', 'errorCode');
      const errorMessage = this.firstString(root, 'error_msg', 'errorMessage');
      let shape = 'UNKNOWN';
      if (commandId !== undefined) {
        shape = 'COMMAND_ID';
      } else if (errorCode !== undefined) {
        shape = 'ERROR';
      }
      return new CloudCommandResponseDto(shape, commandId, errorCode, errorMessage);
    } catch (error) {
      this.logger.warn('cloud.command', 'CLOUD_RESPONSE_INVALID', [
        new NameValue('requestId', requestId),
        new NameValue('seq', String(seq)),
        new NameValue('deviceId', targetDevice)
      ]);
      return new CloudCommandResponseDto('UNKNOWN');
    }
  }

  private firstString(node: JsonNode, first: string, second: string): string | undefined {
    if (node.has(first)) {
      const value = node.require(first);
      if (value.kind === JsonKind.STRING) {
        return value.stringValue;
      }
      return undefined;
    }
    if (node.has(second)) {
      const value = node.require(second);
      if (value.kind === JsonKind.STRING) {
        return value.stringValue;
      }
    }
    return undefined;
  }

  private mapTransportError(error: Object, requestId: string, seq: number,
    targetDevice: string): AppError {
    return CloudErrors.transport(error, requestId, seq, targetDevice);
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, ms);
    });
  }
}
