/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import asset from '@ohos.security.asset';
import util from '@ohos.util';

/**
 * Stores tokens and command keys in Asset Store. Preferences only keeps
 * non-sensitive connection metadata.
 */
export class SecureStorageService {
  static readonly CLOUD_TOKEN_ALIAS: string = 'yaocore.cloud.token.v2';
  static readonly COMMAND_KEY_ALIAS: string = 'yaocore.gateway.hmac.v2';

  static async save(alias: string, value: string): Promise<boolean> {
    const query = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, SecureStorageService.encode(alias));
    try {
      await asset.remove(query);
    } catch (error) {
    }
    if (value.length === 0) {
      return true;
    }

    const attributes = new Map<asset.Tag, asset.Value>();
    attributes.set(asset.Tag.ALIAS, SecureStorageService.encode(alias));
    attributes.set(asset.Tag.SECRET, SecureStorageService.encode(value));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    try {
      await asset.add(attributes);
      return true;
    } catch (error) {
      return false;
    }
  }

  static async load(alias: string): Promise<string> {
    const query = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, SecureStorageService.encode(alias));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const results = await asset.query(query);
      if (results.length === 0) {
        return '';
      }
      const secret = results[0].get(asset.Tag.SECRET);
      if (secret instanceof Uint8Array) {
        return util.TextDecoder.create('utf-8').decodeToString(secret);
      }
    } catch (error) {
    }
    return '';
  }

  static async remove(alias: string): Promise<boolean> {
    const query = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, SecureStorageService.encode(alias));
    try {
      await asset.remove(query);
      return true;
    } catch (error) {
      return false;
    }
  }

  private static encode(value: string): Uint8Array {
    return util.TextEncoder.create('utf-8').encodeInto(value);
  }
}
