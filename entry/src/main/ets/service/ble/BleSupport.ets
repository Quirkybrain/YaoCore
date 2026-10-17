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
