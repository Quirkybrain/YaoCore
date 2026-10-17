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
 * GATT busy policy (DES-A §16.2-3911): a platform busy on the write retries
 * once after 50ms with the same bytes; a secure retry reuses the already
 * encrypted frame so the client CTR stream is not advanced twice. A busy on
 * the read is never retried (the write may have been delivered); the caller
 * tears down the session/connection and restarts from Security1 step0.
 */
import { AppErrors } from '../../common/types/AppError';
import { defaultBleDelay, isCode, mapProvisioningError } from './BleSupport';
import type { BleDelay } from './BleSupport';
import type { BleCharacteristicRef, BleConnection } from './BleProvisioningPorts';

import { GattEndpointMap } from './GattEndpointMap';
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
    return this.runWithBusyRetry(endpoint, async (): Promise<Uint8Array> => {
      return await this.writeRead(endpoint, payload);
    });
  }

  async request(endpoint: string, payload: Uint8Array): Promise<Uint8Array> {
    if (this.session === undefined) {
      throw AppErrors.of('PROVISIONING_SECURITY_HANDSHAKE_FAILED', []);
    }
    const session = this.session;
    return this.runWithBusyRetry(endpoint, async (): Promise<Uint8Array> => {
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

  private async runWithBusyRetry(endpoint: string,
    operation: () => Promise<Uint8Array>): Promise<Uint8Array> {
    for (let attempt = 0; attempt < 2; attempt++) {
      let started = false;
      try {
        return await this.queue.run<Uint8Array>(async (): Promise<Uint8Array> => {
          started = true;
          return await operation();
        });
      } catch (error) {
        const typed = error as Error;
        // Retry only when the operation never started (queue acquisition
        // timeout); a started operation already owns the CTR/command state.
        if (isCode(typed, 'PROVISIONING_GATT_BUSY') && !started && attempt === 0) {
          await Promise.resolve(this.delay(50));
          continue;
        }
        throw mapProvisioningError(typed, 'PROVISIONING_GATT_BUSY', endpoint);
      }
    }
    throw AppErrors.of('PROVISIONING_GATT_BUSY', []);
  }

  /**
   * One write-with-response followed by one read. A busy on the write is the
   * only retryable failure: the value was rejected, and retrying the exact
   * same bytes cannot advance the Security1 CTR stream twice. A busy on the
   * read is ambiguous (the write may have been delivered), so it is terminal.
   */
  private async writeRead(endpoint: string, value: Uint8Array): Promise<Uint8Array> {
    const characteristic: BleCharacteristicRef = this.endpoints.get(endpoint);
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        await this.connection.writeCharacteristic(characteristic, value);
      } catch (error) {
        const typed = error as Error;
        if (attempt === 0 && isCode(typed, 'PROVISIONING_GATT_BUSY')) {
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
