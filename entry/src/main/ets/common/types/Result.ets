/*
 * YaoCore C-01 Result<T>.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §3.2.2
 */
import { AppError } from './AppError';

export class Result<T> {
  readonly ok: boolean;
  readonly value: T | undefined;
  readonly error: AppError | undefined;

  private constructor(ok: boolean, value: T | undefined, error: AppError | undefined) {
    this.ok = ok;
    this.value = value;
    this.error = error;
  }

  static ok<T>(value: T): Result<T> {
    return new Result<T>(true, value, undefined);
  }

  static fail<T>(error: AppError): Result<T> {
    return new Result<T>(false, undefined, error);
  }
}
