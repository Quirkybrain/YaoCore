/*
 * YaoCore C-18 probe backoff.
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §15.2, §15.3-6; PR-13
 *
 * Finite exponential backoff. There is no unbounded refresh path.
 */
import { AppErrors } from '../../common/types/AppError';

const BINDING_PROBE_ATTEMPTS: number = 5;
const BINDING_PROBE_INITIAL_DELAY_MS: number = 500;
const BINDING_PROBE_MULTIPLIER: number = 2;
const BINDING_PROBE_MAX_DELAY_MS: number = 8000;
const BINDING_PROBE_TOTAL_BUDGET_MS: number = 30000;

export class ProbeBackoff {
  readonly attempts: number;
  readonly initialDelayMs: number;
  readonly multiplier: number;
  readonly maxDelayMs: number;

  constructor(attempts: number = 5, initialDelayMs: number = 500, multiplier: number = 2,
    maxDelayMs: number = 8000) {
    if (!Number.isInteger(attempts) || attempts < 1 || attempts > 16) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (!Number.isInteger(initialDelayMs) || initialDelayMs < 0 ||
      !Number.isInteger(maxDelayMs) || maxDelayMs < initialDelayMs) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (!Number.isFinite(multiplier) || multiplier < 1) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.attempts = attempts;
    this.initialDelayMs = initialDelayMs;
    this.multiplier = multiplier;
    this.maxDelayMs = maxDelayMs;
  }

  /** 1-based attempt number: 1 -> 500ms, 2 -> 1000ms, ... capped. */
  nextDelayMs(attempt: number): number {
    if (!Number.isInteger(attempt) || attempt <= 1) {
      return this.initialDelayMs;
    }
    let delay = this.initialDelayMs;
    for (let index = 1; index < attempt; index++) {
      delay = delay * this.multiplier;
      if (delay >= this.maxDelayMs) {
        return this.maxDelayMs;
      }
    }
    return Math.min(delay, this.maxDelayMs);
  }

  totalBudgetMs(): number {
    let total = 0;
    for (let attempt = 1; attempt <= this.attempts; attempt++) {
      total += this.nextDelayMs(attempt);
    }
    return total;
  }

  static forBindingProbe(): ProbeBackoff {
    return new ProbeBackoff(BINDING_PROBE_ATTEMPTS, BINDING_PROBE_INITIAL_DELAY_MS,
      BINDING_PROBE_MULTIPLIER, BINDING_PROBE_MAX_DELAY_MS);
  }

  static bindingProbeTotalBudgetMs(): number {
    return BINDING_PROBE_TOTAL_BUDGET_MS;
  }
}
