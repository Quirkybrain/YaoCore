/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

export class HttpHeaderUtil {
  static getValue(header: Object, expectedName: string): string {
    try {
      const serialized = JSON.stringify(header);
      if (serialized.length === 0) {
        return '';
      }
      const headers = JSON.parse(serialized) as Record<string, string | string[]>;
      const names = Object.keys(headers);
      const normalizedName = expectedName.toLowerCase();
      for (let index = 0; index < names.length; index++) {
        if (names[index].toLowerCase() !== normalizedName) {
          continue;
        }
        const value = headers[names[index]];
        if (Array.isArray(value)) {
          return value.length === 1 ? `${value[0]}`.trim() : '';
        }
        return `${value}`.trim();
      }
    } catch (error) {
    }
    return '';
  }
}
