/*
 * YaoCore C-19 shared runtime helpers (host-testable, no platform import).
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import type { CancellationToken } from '../../common/types/Ports';

/** Delay seam: production uses setTimeout, host tests advance a fake clock. */
export type BleDelay = (delayMs: number) => Promise<void>;

export function defaultBleDelay(delayMs: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, delayMs);
  });
}

export function throwIfCancelled(cancellation?: CancellationToken): void {
  if (cancellation === undefined) {
    return;
  }
  try {
    cancellation.throwIfCancelled();
  } catch (error) {
    throw AppErrors.of('PROVISIONING_CANCELLED', []);
  }
}

export function isAppError(error: Error): boolean {
  return error instanceof AppError;
}

export function errorCode(error: Error): string {
  if (error instanceof AppError) {
    return (error as AppError).code;
  }
  return '';
}

export function isCode(error: Error, code: string): boolean {
  return errorCode(error) === code;
}

/**
 * Detail marker carried only by a write failure where the platform explicitly
 * rejected the write as busy (GATT busy 2900011 / connection congested
 * 2901004). Only this marker authorizes resending the same frame: any other
 * write failure, including 2900099 and a missing/unknown code, may have been
 * accepted and therefore must not be retried (REV-T12-002 R2-01).
 */
const WRITE_BUSY_DETAIL_NAME: string = 'retryable';
const WRITE_BUSY_DETAIL_VALUE: string = 'write-busy';

/** Builds the only GATT_BUSY that is safe to resend. */
export function confirmedWriteBusy(): AppError {
  return AppErrors.of('PROVISIONING_GATT_BUSY',
    [new NameValue(WRITE_BUSY_DETAIL_NAME, WRITE_BUSY_DETAIL_VALUE)]);
}

/**
 * True only for a GATT_BUSY explicitly marked as a rejected write. An
 * unmarked GATT_BUSY (e.g. queue timeout) or any other code is not safe to
 * resend.
 */
export function isConfirmedWriteBusy(error: Error): boolean {
  if (!(error instanceof AppError)) {
    return false;
  }
  const appError = error as AppError;
  if (appError.code !== 'PROVISIONING_GATT_BUSY') {
    return false;
  }
  for (let index = 0; index < appError.details.length; index++) {
    const detail = appError.details[index];
    if (detail.name === WRITE_BUSY_DETAIL_NAME && detail.value === WRITE_BUSY_DETAIL_VALUE) {
      return true;
    }
  }
  return false;
}

/**
 * Preserve an existing PROVISIONING_* classification; otherwise map to the
 * caller-supplied stage error. Never leaks secret material in details.
 */
export function mapProvisioningError(error: Error, fallbackCode: string, field: string): AppError {
  if (error instanceof AppError) {
    const appError = error as AppError;
    if (appError.code.startsWith('PROVISIONING_')) {
      return appError;
    }
  }
  return AppErrors.of(fallbackCode, [new NameValue('field', field)]);
}
