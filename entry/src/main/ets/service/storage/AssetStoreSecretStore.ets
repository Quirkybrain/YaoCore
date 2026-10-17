/*
 * YaoCore C-06 AssetStoreSecretStore.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Contract: DES-A §9.1.3, §9.2, §9.4, §22.3
 *
 * The ONLY storage file importing @ohos.security.asset (through
 * AssetStoreKit). Accessibility is DEVICE_FIRST_UNLOCKED. There is no
 * plaintext fallback anywhere in this adapter: any unavailable/denied/IO
 * failure is surfaced as ASSET_* and callers must block provisioning/control.
 *
 * Device verification is BLOCKED in this environment (no device/signing);
 * the adapter is COMPILED_ONLY. The exact ALIAS value encoding (BYTES tag) is
 * exercised by the blocked device suite, not claimed as runtime-verified.
 */
import { asset } from '@kit.AssetStoreKit';
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import type { SecureBytes } from '../../common/types/SecureBytes';
import { BytesUtil } from '../../common/utils/BytesUtil';
import { SecretAlias } from './SecretStore';
import type { SecretStore } from './SecretStore';

interface PlatformErrorLike {
  code?: number;
}

const CODE_UNAVAILABLE: number = 24000001;
const CODE_NOT_FOUND: number = 24000002;
const CODE_ALREADY_EXISTS: number = 24000003;
const CODE_ACCESS_DENIED: number = 24000004;
const CODE_SCREEN_LOCK_MISMATCH: number = 24000005;
const CODE_DATABASE_FAILED: number = 24000008;
const CODE_CRYPTO_FAILED: number = 24000009;
const CODE_IPC_FAILED: number = 24000010;
const CODE_PERMISSION_DENIED: number = 201;
const LIST_PAGE_SIZE: number = 256;
const LIST_MAX_PAGES: number = 16;

export class AssetStoreSecretStore implements SecretStore {
  private initialized: boolean = false;

  /**
   * Probes Asset Store availability. An empty store reports NOT_FOUND, which
   * is a healthy state; every other failure is fail-closed ASSET_*.
   */
  async initialize(): Promise<void> {
    this.initialized = false;
    try {
      const query = AssetStoreSecretStore.attributeQuery();
      query.set(asset.Tag.RETURN_LIMIT, 1);
      await asset.query(query);
    } catch (error) {
      const code = AssetStoreSecretStore.platformCode(error as Error);
      if (code !== CODE_NOT_FOUND) {
        throw AssetStoreSecretStore.mapError(error as Error);
      }
    }
    this.initialized = true;
  }

  isInitialized(): boolean {
    return this.initialized;
  }

  async put(alias: string, secret: SecureBytes): Promise<void> {
    const checked = SecretAlias.require(alias);
    const bytes = secret.withView((view: Uint8Array): Uint8Array => BytesUtil.copyOf(view));
    try {
      const query = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, BytesUtil.utf8(checked));
      const update = new Map<asset.Tag, asset.Value>();
      update.set(asset.Tag.SECRET, bytes);
      try {
        await asset.update(query, update);
        return;
      } catch (error) {
        const code = AssetStoreSecretStore.platformCode(error as Error);
        if (code !== CODE_NOT_FOUND) {
          throw AssetStoreSecretStore.mapError(error as Error);
        }
      }
      const created = new Map<asset.Tag, asset.Value>();
      created.set(asset.Tag.ALIAS, BytesUtil.utf8(checked));
      created.set(asset.Tag.SECRET, bytes);
      created.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
      try {
        await asset.add(created);
      } catch (error) {
        const code = AssetStoreSecretStore.platformCode(error as Error);
        if (code === CODE_ALREADY_EXISTS) {
          await asset.update(query, update);
          return;
        }
        throw AssetStoreSecretStore.mapError(error as Error);
      }
    } catch (error) {
      throw AssetStoreSecretStore.mapError(error as Error);
    } finally {
      BytesUtil.zeroize(bytes);
    }
  }

  async withSecret<T>(alias: string, fn: (secret: Uint8Array) => Promise<T>): Promise<T> {
    const checked = SecretAlias.require(alias);
    const query = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, BytesUtil.utf8(checked));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    let results: Array<asset.AssetMap> = [];
    try {
      results = await asset.query(query);
    } catch (error) {
      throw AssetStoreSecretStore.mapError(error as Error);
    }
    if (results.length === 0) {
      throw AppErrors.of('ASSET_NOT_FOUND', []);
    }
    const value = results[0].get(asset.Tag.SECRET);
    if (!(value instanceof Uint8Array)) {
      throw AppErrors.of('SECRET_ENCODING_INVALID', []);
    }
    const copy = BytesUtil.copyOf(value);
    BytesUtil.zeroize(value);
    try {
      return await fn(copy);
    } finally {
      BytesUtil.zeroize(copy);
    }
  }

  async remove(alias: string): Promise<void> {
    const checked = SecretAlias.require(alias);
    const query = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, BytesUtil.utf8(checked));
    try {
      await asset.remove(query);
    } catch (error) {
      throw AssetStoreSecretStore.mapError(error as Error);
    }
  }

  async list(prefix: string): Promise<ReadonlyArray<string>> {
    const aliases: string[] = [];
    for (let page = 0; page < LIST_MAX_PAGES; page++) {
      const query = AssetStoreSecretStore.attributeQuery();
      query.set(asset.Tag.RETURN_LIMIT, LIST_PAGE_SIZE);
      query.set(asset.Tag.RETURN_OFFSET, page * LIST_PAGE_SIZE);
      let results: Array<asset.AssetMap> = [];
      try {
        results = await asset.query(query);
      } catch (error) {
        const code = AssetStoreSecretStore.platformCode(error as Error);
        if (code === CODE_NOT_FOUND) {
          break;
        }
        throw AssetStoreSecretStore.mapError(error as Error);
      }
      for (let index = 0; index < results.length; index++) {
        const aliasValue = results[index].get(asset.Tag.ALIAS);
        if (!(aliasValue instanceof Uint8Array)) {
          continue;
        }
        const alias = BytesUtil.fromUtf8(aliasValue);
        if (prefix.length === 0 || alias.startsWith(prefix)) {
          aliases.push(alias);
        }
      }
      if (results.length < LIST_PAGE_SIZE) {
        break;
      }
    }
    aliases.sort();
    return aliases;
  }

  private static attributeQuery(): Map<asset.Tag, asset.Value> {
    const query = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ATTRIBUTES);
    return query;
  }

  private static platformCode(error: Error): number {
    const candidate = error as PlatformErrorLike;
    if (typeof candidate.code === 'number') {
      return candidate.code;
    }
    return -1;
  }

  private static mapError(error: Error): AppError {
    if (error instanceof AppError) {
      return error;
    }
    const code = AssetStoreSecretStore.platformCode(error);
    let appCode = 'ASSET_IO_FAILED';
    if (code === CODE_UNAVAILABLE) {
      appCode = 'ASSET_UNAVAILABLE';
    } else if (code === CODE_NOT_FOUND) {
      appCode = 'ASSET_NOT_FOUND';
    } else if (code === CODE_ACCESS_DENIED || code === CODE_SCREEN_LOCK_MISMATCH ||
      code === CODE_PERMISSION_DENIED) {
      appCode = 'ASSET_ACCESS_DENIED';
    } else if (code === CODE_DATABASE_FAILED || code === CODE_CRYPTO_FAILED ||
      code === CODE_IPC_FAILED) {
      appCode = 'ASSET_IO_FAILED';
    }
    return AppErrors.of(appCode, [new NameValue('platformCode', String(code))]);
  }
}
