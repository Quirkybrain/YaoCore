/*
 * YaoCore C-06 PreferencesStoreAdapter.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Contract: DES-A §9.4, §22.1, §23.3
 *
 * The ONLY storage file importing @ohos.data.preferences (through ArkData).
 * Adapter rules: platform type mapping and error mapping only; no business
 * decisions. Platform messages are discarded, only the numeric code is kept.
 * Secrets are rejected by policy at the call sites; this adapter stores
 * whatever non-secret strings the port receives.
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { StorageConstants } from '../../common/constants/StorageConstants';
import type { PreferencesStore } from '../../contracts/PreferencesStore';

interface PlatformErrorLike {
  code?: number;
}

export class PreferencesStoreAdapter implements PreferencesStore {
  private readonly context: common.Context;
  private readonly name: string;
  private store: preferences.Preferences | undefined = undefined;
  private opening: Promise<preferences.Preferences> | undefined = undefined;

  constructor(context: common.Context, name: string = StorageConstants.PREFERENCES_NAME) {
    this.context = context;
    this.name = name;
  }

  async getString(key: string): Promise<string | undefined> {
    try {
      const store = await this.open();
      const value = await store.get(key, '');
      if (typeof value !== 'string' || value.length === 0) {
        return undefined;
      }
      return value;
    } catch (error) {
      throw PreferencesStoreAdapter.mapError(error as Error);
    }
  }

  async putString(key: string, value: string): Promise<void> {
    try {
      const store = await this.open();
      await store.put(key, value);
      await store.flush();
    } catch (error) {
      throw PreferencesStoreAdapter.mapError(error as Error);
    }
  }

  async delete(key: string): Promise<void> {
    try {
      const store = await this.open();
      await store.delete(key);
      await store.flush();
    } catch (error) {
      throw PreferencesStoreAdapter.mapError(error as Error);
    }
  }

  async flush(): Promise<void> {
    try {
      const store = await this.open();
      await store.flush();
    } catch (error) {
      throw PreferencesStoreAdapter.mapError(error as Error);
    }
  }

  async close(): Promise<void> {
    this.store = undefined;
    this.opening = undefined;
  }

  private open(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return Promise.resolve(this.store);
    }
    if (this.opening === undefined) {
      this.opening = preferences.getPreferences(this.context, this.name)
        .then((opened: preferences.Preferences): preferences.Preferences => {
          this.store = opened;
          return opened;
        })
        .catch((error: Error): never => {
          this.opening = undefined;
          throw PreferencesStoreAdapter.mapError(error);
        });
    }
    return this.opening;
  }

  private static mapError(error: Error): AppError {
    if (error instanceof AppError) {
      return error;
    }
    const candidate = error as PlatformErrorLike;
    if (typeof candidate.code === 'number') {
      return AppErrors.of('STORAGE_PREFERENCES_ERROR',
        [new NameValue('platformCode', String(candidate.code))]);
    }
    return AppErrors.of('STORAGE_PREFERENCES_ERROR', []);
  }
}
