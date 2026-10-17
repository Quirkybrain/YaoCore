/*
 * YaoCore C-01 UUID helper.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §4.1.5
 */
import { AppErrors } from '../types/AppError';
import type { IdPort } from '../types/Ports';

export class UuidUtil {
  private static readonly UUID_PATTERN: RegExp =
    /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

  static newUuid(ids: IdPort): string {
    const value = ids.newId();
    if (!UuidUtil.isValidUuid(value)) {
      throw AppErrors.of('INTERNAL_ERROR', []);
    }
    return value;
  }

  static isValidUuid(value: string): boolean {
    return UuidUtil.UUID_PATTERN.test(value);
  }
}
