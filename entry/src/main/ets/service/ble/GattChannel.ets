/*
 * YaoCore C-19 serialized secure GATT channel.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Contract: DES-A §16.2-§16.4; BLE设计 §2-45, §4.2-86-88
 *
 * One channel owns the write->read pair and the Security1 CTR order. Plain
 * requests (proto-ver) and secure requests share the same single-flight queue;
 * no notification subscription is used. Encryption and decryption happen
 * inside the queue slot so concurrent callers cannot interleave stream bytes.
 *
 * GATT busy policy (DES-A §16.2-3911; REV-T12-002 R2-01/R2-03): only a write
 * rejection explicitly confirmed as busy by the platform (2900011/2901004)
 * retries once after 50ms with the same bytes. Ambiguous write failures
 * (2900099, unknown or missing code) are terminal because the write may have
 * been accepted. A secure retry reuses the already encrypted frame so the
 * client CTR stream is not advanced twice. A busy on the read is never
 * retried (the write may have been delivered); the caller tears down the
 * session/connection and restarts from Security1 step0. A queue-acquisition
 * timeout marks the queue broken, so it is terminal as well.
 */
import { AppErrors } from '../../common/types/AppError';
import { defaultBleDelay, isConfirmedWriteBusy, mapProvisioningError } from './BleSupport';
import type { BleDelay } from './BleSupport';
import type { BleConnection } from '../../contracts/BleProvisioningPorts';
import type { BleCharacteristicRef } from '../../model/ProvisioningModels';

import { GattEndpointMap } from '../../model/GattEndpointMap';
import { GattRequestQueue } from './GattRequestQueue';
import type { Security1Session } from './Security1Session';

export interface SecureGattChannel {
  request(endpoint: string, payload: Uint8Array): Promise<Uint8Array>;
  requestPlain(endpoint: string, payload: Uint8Array): Promise<Uint8Array>;
}

export class GattChannel implements SecureGattChannel {
  private readonly connection: BleConnection;
  private readonly endpoints: GattEndpointMap;
  private readonly queue: GattRequestQueue;
  private readonly delay: BleDelay;
  private session: Security1Session | undefined = undefined;

  constructor(connection: BleConnection, endpoints: GattEndpointMap,
    queue: GattRequestQueue, delay: BleDelay = defaultBleDelay) {
    this.connection = connection;
    this.endpoints = endpoints;
    this.queue = queue;
    this.delay = delay;
  }

  setSession(session: Security1Session): void {
    this.session = session;
  }

  clearSession(): void {
    this.session = undefined;
  }

  async requestPlain(endpoint: string, payload: Uint8Array): Promise<Uint8Array> {
    return this.runSerialized(endpoint, async (): Promise<Uint8Array> => {
      return await this.writeRead(endpoint, payload);
    });
  }

  async request(endpoint: string, payload: Uint8Array): Promise<Uint8Array> {
    if (this.session === undefined) {
      throw AppErrors.of('PROVISIONING_SECURITY_HANDSHAKE_FAILED', []);
    }
    const session = this.session;
    return this.runSerialized(endpoint, async (): Promise<Uint8Array> => {
      const encrypted = await session.encrypt(payload);
      let response: Uint8Array;
      try {
        response = await this.writeRead(endpoint, encrypted);
      } finally {
        // The ciphertext copy is not secret, but it is transient protocol state.
        encrypted.fill(0);
      }
      return await session.decrypt(response);
    });
  }

  /**
   * One serialized attempt. There is deliberately no queue-acquisition retry:
   * a queue timeout permanently breaks the queue (the timed-out operation may
   * still be in flight), so a second run would fail immediately; retrying only
   * added 50ms and misreported the semantics (REV-T12-002 R2-03). Write-busy
   * handling lives in `writeRead`, where the same encrypted frame is reused.
   */
  private async runSerialized(endpoint: string,
    operation: () => Promise<Uint8Array>): Promise<Uint8Array> {
    try {
      return await this.queue.run<Uint8Array>(operation);
    } catch (error) {
      throw mapProvisioningError(error as Error, 'PROVISIONING_GATT_BUSY', endpoint);
    }
  }

  /**
   * One write-with-response followed by one read. Only a platform-confirmed
   * write busy is retryable: the write was rejected before acceptance, and
   * retrying the exact same bytes cannot advance the Security1 CTR stream
   * twice. Any other write failure (2900099, unknown/missing code) may have
   * been accepted and is terminal. A busy on the read is ambiguous (the write
   * may have been delivered), so it is terminal too.
   */
  private async writeRead(endpoint: string, value: Uint8Array): Promise<Uint8Array> {
    const characteristic: BleCharacteristicRef = this.endpoints.get(endpoint);
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        await this.connection.writeCharacteristic(characteristic, value);
      } catch (error) {
        const typed = error as Error;
        if (attempt === 0 && isConfirmedWriteBusy(typed)) {
          await Promise.resolve(this.delay(50));
          continue;
        }
        throw typed;
      }
      return await this.connection.readCharacteristic(characteristic);
    }
    throw AppErrors.of('PROVISIONING_GATT_BUSY', []);
  }
}
