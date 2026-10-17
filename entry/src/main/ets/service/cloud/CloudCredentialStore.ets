/*
 * YaoCore C-15 production cloud credential store.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §8.1.3, §8.5; DES-A §9.1.3; CB §7.1 (D-012)
 *
 * The IAM token lives only in the platform SecretStore under
 * `yaocore.cloud.token.v2`. A non-secret update timestamp is kept in
 * Preferences for diagnostics; failures there never invalidate the token.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { StorageConstants } from '../../common/constants/StorageConstants';
import { SecureBytes } from '../../common/types/SecureBytes';
import { Utf8 } from '../../common/utils/Utf8';
import { DateTimeUtil } from '../../common/utils/DateTimeUtil';
import type { ClockPort } from '../../common/types/Ports';
import type { SecretStore } from '../storage/SecretStore';
import type { PreferencesStore } from '../storage/PreferencesStore';
import type { CloudCredentialPort } from './CloudPorts';

const TOKEN_UPDATED_AT_KEY: string = 'app.cloud.tokenUpdatedAt';

export class AssetCloudCredentialStore implements CloudCredentialPort {
  private readonly secrets: SecretStore;
  private readonly preferences: PreferencesStore | undefined;
  private readonly clock: ClockPort;

  constructor(secrets: SecretStore, clock: ClockPort, preferences?: PreferencesStore) {
    this.secrets = secrets;
    this.clock = clock;
    this.preferences = preferences;
  }

  async hasToken(): Promise<boolean> {
    try {
      await this.secrets.withSecret(StorageConstants.ASSET_CLOUD_TOKEN,
        async (): Promise<boolean> => true);
      return true;
    } catch (error) {
      if (error instanceof AppError && error.code === 'ASSET_NOT_FOUND') {
        return false;
      }
      throw AssetCloudCredentialStore.asAppError(error);
    }
  }

  async withToken<T>(fn: (token: string) => Promise<T>): Promise<T> {
    return this.secrets.withSecret(StorageConstants.ASSET_CLOUD_TOKEN,
      async (bytes: Uint8Array): Promise<T> => {
        const token = Utf8.decode(bytes);
        return fn(token);
      });
  }

  async putToken(token: string): Promise<void> {
    if (token.length === 0) {
      throw AppErrors.of('CLOUD_TOKEN_MISSING', []);
    }
    const secret = SecureBytes.from(Utf8.encode(token));
    try {
      await this.secrets.put(StorageConstants.ASSET_CLOUD_TOKEN, secret);
    } finally {
      secret.destroy();
    }
    if (this.preferences !== undefined) {
      try {
        await this.preferences.putString(TOKEN_UPDATED_AT_KEY,
          DateTimeUtil.formatUtcCompact(this.clock.nowMs()));
        await this.preferences.flush();
      } catch (error) {
        // Timestamp is diagnostic only; the token itself was stored.
      }
    }
  }

  async removeToken(): Promise<void> {
    try {
      await this.secrets.remove(StorageConstants.ASSET_CLOUD_TOKEN);
    } catch (error) {
      if (!(error instanceof AppError) || error.code !== 'ASSET_NOT_FOUND') {
        throw AssetCloudCredentialStore.asAppError(error);
      }
    }
    if (this.preferences !== undefined) {
      try {
        await this.preferences.delete(TOKEN_UPDATED_AT_KEY);
        await this.preferences.flush();
      } catch (error) {
        // Diagnostic metadata only.
      }
    }
  }

  async updatedAt(): Promise<string | undefined> {
    if (this.preferences === undefined) {
      return undefined;
    }
    try {
      return await this.preferences.getString(TOKEN_UPDATED_AT_KEY);
    } catch (error) {
      return undefined;
    }
  }

  private static asAppError(error: Object): AppError {
    if (error instanceof AppError) {
      return error;
    }
    return AppErrors.of('ASSET_IO_FAILED', []);
  }
}
