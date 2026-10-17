/*
 * YaoCore C-01 compact UTC time helpers.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §3.3, §4.1.5, §18.6
 *
 * All protocol time is UTC `yyyyMMddTHHmmssZ`, second precision. Local time
 * zones are never used.
 */
import { AppErrors } from '../types/AppError';
import type { ClockPort } from '../types/Ports';
import { ProtocolConstants } from '../constants/ProtocolConstants';

export class DateTimeUtil {
  static formatUtcCompact(epochMs: number): string {
    if (!Number.isFinite(epochMs)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_TIMESTAMP', 'timestamp');
    }
    const truncated = Math.floor(epochMs / 1000) * 1000;
    const date = new Date(truncated);
    const year = date.getUTCFullYear();
    if (year < 0 || year > 9999) {
      throw AppErrors.protocol('PROTOCOL_INVALID_TIMESTAMP', 'timestamp');
    }
    return DateTimeUtil.pad4(year) + DateTimeUtil.pad2(date.getUTCMonth() + 1) +
      DateTimeUtil.pad2(date.getUTCDate()) + 'T' + DateTimeUtil.pad2(date.getUTCHours()) +
      DateTimeUtil.pad2(date.getUTCMinutes()) + DateTimeUtil.pad2(date.getUTCSeconds()) + 'Z';
  }

  static parseUtcCompact(text: string): number {
    if (!ProtocolConstants.UTC_COMPACT_PATTERN.test(text)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_TIMESTAMP', 'timestamp');
    }
    const year = Number.parseInt(text.substring(0, 4), 10);
    const month = Number.parseInt(text.substring(4, 6), 10);
    const day = Number.parseInt(text.substring(6, 8), 10);
    const hour = Number.parseInt(text.substring(9, 11), 10);
    const minute = Number.parseInt(text.substring(11, 13), 10);
    const second = Number.parseInt(text.substring(13, 15), 10);
    if (month < 1 || month > 12 || day < 1 || day > DateTimeUtil.daysInMonth(year, month) ||
      hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59) {
      throw AppErrors.protocol('PROTOCOL_INVALID_TIMESTAMP', 'timestamp');
    }
    const date = new Date(0);
    date.setUTCFullYear(year, month - 1, day);
    date.setUTCHours(hour, minute, second, 0);
    const epochMs = date.getTime();
    if (!Number.isFinite(epochMs)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_TIMESTAMP', 'timestamp');
    }
    if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 ||
      date.getUTCDate() !== day || date.getUTCHours() !== hour ||
      date.getUTCMinutes() !== minute || date.getUTCSeconds() !== second) {
      throw AppErrors.protocol('PROTOCOL_INVALID_TIMESTAMP', 'timestamp');
    }
    return epochMs;
  }

  static isWithinWindow(nowMs: number, timestampMs: number, windowMs: number = 120000): boolean {
    if (!Number.isFinite(nowMs) || !Number.isFinite(timestampMs) || !Number.isFinite(windowMs)) {
      return false;
    }
    return Math.abs(nowMs - timestampMs) <= windowMs;
  }

  static nowUtcCompact(clock: ClockPort): string {
    return DateTimeUtil.formatUtcCompact(clock.nowMs());
  }

  static formatRequestId(epochMs: number, seq: number): string {
    if (!Number.isInteger(epochMs) || epochMs < 0 || epochMs > 9999999999999) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'request_id');
    }
    if (!Number.isInteger(seq) || seq < 0 || seq > ProtocolConstants.MAX_SEQ) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'seq');
    }
    const requestId = 'req-' + String(epochMs) + '-' + String(seq);
    if (!ProtocolConstants.REQUEST_ID_PATTERN.test(requestId) ||
      requestId.length > ProtocolConstants.MAX_REQUEST_ID_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'request_id');
    }
    return requestId;
  }

  private static daysInMonth(year: number, month: number): number {
    if (month === 2) {
      const leap = (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
      return leap ? 29 : 28;
    }
    if (month === 4 || month === 6 || month === 9 || month === 11) {
      return 30;
    }
    return 31;
  }

  private static pad2(value: number): string {
    return value < 10 ? '0' + String(value) : String(value);
  }

  private static pad4(value: number): string {
    if (value < 10) {
      return '000' + String(value);
    }
    if (value < 100) {
      return '00' + String(value);
    }
    if (value < 1000) {
      return '0' + String(value);
    }
    return String(value);
  }
}
