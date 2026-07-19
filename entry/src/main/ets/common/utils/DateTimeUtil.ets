/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

export class DateTimeUtil {
  static pad(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  static nowIsoCompact(): string {
    const now = new Date();
    const year = now.getUTCFullYear();
    const month = DateTimeUtil.pad(now.getUTCMonth() + 1);
    const day = DateTimeUtil.pad(now.getUTCDate());
    const hour = DateTimeUtil.pad(now.getUTCHours());
    const minute = DateTimeUtil.pad(now.getUTCMinutes());
    const second = DateTimeUtil.pad(now.getUTCSeconds());
    return `${year}${month}${day}T${hour}${minute}${second}Z`;
  }

  static parseUtcToMillis(value: string): number {
    const text = value.trim();
    const compact = /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/.exec(text);
    if (compact !== null) {
      return DateTimeUtil.validatedUtcMillis(
        Number(compact[1]), Number(compact[2]), Number(compact[3]),
        Number(compact[4]), Number(compact[5]), Number(compact[6]), 0
      );
    }
    const standard = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?Z$/.exec(text);
    if (standard === null) {
      return Number.NaN;
    }
    let millisecond = 0;
    if (standard[7] !== undefined) {
      const fraction = standard[7];
      millisecond = Number(fraction) * (fraction.length === 1 ? 100 : (fraction.length === 2 ? 10 : 1));
    }
    return DateTimeUtil.validatedUtcMillis(
      Number(standard[1]), Number(standard[2]), Number(standard[3]),
      Number(standard[4]), Number(standard[5]), Number(standard[6]), millisecond
    );
  }

  private static validatedUtcMillis(
    year: number,
    month: number,
    day: number,
    hour: number,
    minute: number,
    second: number,
    millisecond: number
  ): number {
    if (year < 1970 || year > 9999 || month < 1 || month > 12 || day < 1 || day > 31 ||
      hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59 ||
      millisecond < 0 || millisecond > 999) {
      return Number.NaN;
    }
    const timestamp = Date.UTC(year, month - 1, day, hour, minute, second, millisecond);
    const parsed = new Date(timestamp);
    if (parsed.getUTCFullYear() !== year || parsed.getUTCMonth() !== month - 1 || parsed.getUTCDate() !== day ||
      parsed.getUTCHours() !== hour || parsed.getUTCMinutes() !== minute || parsed.getUTCSeconds() !== second ||
      parsed.getUTCMilliseconds() !== millisecond) {
      return Number.NaN;
    }
    return timestamp;
  }

  static nowDisplay(): string {
    const now = new Date();
    return `${DateTimeUtil.pad(now.getHours())}:${DateTimeUtil.pad(now.getMinutes())}`;
  }

  static nowReadable(): string {
    const now = new Date();
    return `${DateTimeUtil.pad(now.getMonth() + 1)}-${DateTimeUtil.pad(now.getDate())} ${DateTimeUtil.nowDisplay()}`;
  }
}
