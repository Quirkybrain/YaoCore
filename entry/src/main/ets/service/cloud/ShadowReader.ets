/*
 * YaoCore C-15 IoTDA shadow reader.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §8.1.5, §8.2, §8.3.3; A-CB-1
 *
 * Reads the gateway shadow on demand; never caches and never treats a previous
 * shadow as fresh. Response bodies above 64 KiB are rejected before parsing.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { HttpHeaders } from '../../common/types/HttpHeaders';
import type { ClockPort } from '../../common/types/Ports';
import type { LoggerPort } from '../../contracts/Ports';
import type { CancellationToken } from '../../common/types/CancellationToken';
import type { CryptoPort } from '../../contracts/CryptoPort';
import { HttpRequest, HttpResponse } from '../../model/GatewayTransportModels';
import type { HttpTransport } from '../../contracts/GatewayTransportPorts';
import type { CloudConfigStore, CloudCredentialPort } from '../../contracts/CloudPorts';
import type { ShadowSnapshot } from './CloudModels';
import { CloudConfigValidator } from './CloudConfigValidator';
import { CloudErrors } from './CloudErrors';
import { ShadowDtoAdapter } from './ShadowDtoAdapter';

const CONNECT_TIMEOUT_MS: number = 10000;
const READ_TIMEOUT_MS: number = 15000;

export class ShadowReader {
  private readonly transport: HttpTransport;
  private readonly configs: CloudConfigStore;
  private readonly credentials: CloudCredentialPort;
  private readonly crypto: CryptoPort;
  private readonly clock: ClockPort;
  private readonly logger: LoggerPort;

  constructor(transport: HttpTransport, configs: CloudConfigStore,
    credentials: CloudCredentialPort, crypto: CryptoPort, clock: ClockPort,
    logger: LoggerPort) {
    this.transport = transport;
    this.configs = configs;
    this.credentials = credentials;
    this.crypto = crypto;
    this.clock = clock;
    this.logger = logger;
  }

  async read(gatewayId: string, cancellation?: CancellationToken): Promise<ShadowSnapshot> {
    if (gatewayId.length === 0) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'gatewayId');
    }
    if (cancellation !== undefined && cancellation.cancelled) {
      throw AppErrors.of('PROVISIONING_CANCELLED', []);
    }
    this.logger.debug('cloud.shadow', 'read', [new NameValue('gatewayId', gatewayId)]);
    const config = await this.configs.load();
    if (config === undefined) {
      throw AppErrors.of('CLOUD_NOT_CONFIGURED', []);
    }
    const validation = CloudConfigValidator.validate(config);
    if (!validation.valid) {
      throw validation.errors[0];
    }
    const shadowEndpoint = validation.shadowEndpoint;
    if (shadowEndpoint === undefined) {
      throw AppErrors.of('CLOUD_ENDPOINT_INVALID', []);
    }
    if (!(await this.credentials.hasToken())) {
      throw AppErrors.of('CLOUD_TOKEN_MISSING', []);
    }
    return this.credentials.withToken(async (token: string): Promise<ShadowSnapshot> => {
      const headers = HttpHeaders.from([
        new NameValue('X-Auth-Token', token),
        new NameValue('Accept', 'application/json')
      ]);
      const request = new HttpRequest('GET', shadowEndpoint, headers, undefined,
        CONNECT_TIMEOUT_MS, READ_TIMEOUT_MS);
      let response: HttpResponse;
      try {
        response = await this.transport.send(request, undefined);
      } catch (error) {
        throw CloudErrors.transport(error, undefined, undefined, config.deviceId);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CloudErrors.withContext(CloudErrors.codeForStatus(response.statusCode),
          response.statusCode, undefined, undefined, config.deviceId);
      }
      try {
        return await ShadowDtoAdapter.map(response.body, config.deviceId,
          this.clock.nowMs(), this.crypto, this.logger);
      } catch (error) {
        if (error instanceof AppError) {
          if (error.code === 'CLOUD_SHADOW_INVALID' || error.code === 'CLOUD_INVENTORY_UNSUPPORTED' ||
            error.code === 'CLOUD_ENDPOINT_INVALID') {
            throw error;
          }
        }
        throw CloudErrors.shadowInvalid('shadow');
      }
    });
  }
}
