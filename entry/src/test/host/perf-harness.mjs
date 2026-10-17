/**
 * NFR 4.3 measurement harness (host-side, no device required).
 * Producer: agent:test-engineer | Task: T-05 / wp-010-test-plan
 *
 * This module defines the *measurement contract* for ACK latency and other
 * timed UI/transport paths. It does not itself measure a real gateway.
 *
 * Correct use for ACK p95 (see TEST-001 §7):
 *   const summary = await measureAckLatency(async () => {
 *     const t0 = performance.now();
 *     await gateway.sendControl(...);       // includes write
 *     await applyAckAndState(...);          // auth + correlation + result_code + reported_state
 *     return performance.now() - t0;        // caller may instead return t1 - t0
 *   }, { samples: 100, warmup: 5 });
 *
 * The measured function MUST include the full t0->t1 chain; measuring only
 * HTTP write time is not ACK p95 evidence.
 */

/** Return a monotonic millisecond timestamp. */
export function monotonicNowMs() {
  return performance.now();
}

/** Nearest-rank percentile for a non-empty array of finite numbers. */
export function percentile(values, p) {
  if (!Array.isArray(values) || values.length === 0) {
    throw new Error('percentile requires a non-empty array');
  }
  if (!(p >= 0 && p <= 100)) {
    throw new Error('percentile must be within 0..100');
  }
  const sorted = [...values].sort((a, b) => a - b);
  if (p === 0) {
    return sorted[0];
  }
  const rank = Math.ceil((p / 100) * sorted.length);
  return sorted[Math.min(sorted.length - 1, Math.max(0, rank - 1))];
}

/** Summarize raw samples with the fields required by TEST-001. */
export function summarizeSamples(values) {
  if (!Array.isArray(values) || values.length === 0) {
    throw new Error('summarizeSamples requires at least one sample');
  }
  for (const value of values) {
    if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
      throw new Error(`invalid sample: ${String(value)}`);
    }
  }
  return {
    count: values.length,
    minMs: Math.min(...values),
    p50Ms: percentile(values, 50),
    p95Ms: percentile(values, 95),
    maxMs: Math.max(...values),
  };
}

/**
 * Run `operation` `warmup + samples` times and return the summary.
 * The caller owns the t0/t1 definition inside `operation`.
 */
export async function measureOperation(operation, options = {}) {
  const samples = options.samples ?? 100;
  const warmup = options.warmup ?? 5;
  if (typeof operation !== 'function') {
    throw new Error('operation must be a function');
  }
  if (!Number.isInteger(samples) || samples < 1) {
    throw new Error('samples must be a positive integer');
  }
  if (!Number.isInteger(warmup) || warmup < 0) {
    throw new Error('warmup must be a non-negative integer');
  }
  for (let index = 0; index < warmup; index += 1) {
    await operation(index, true);
  }
  const measured = [];
  for (let index = 0; index < samples; index += 1) {
    measured.push(await operation(index, false));
  }
  return summarizeSamples(measured);
}

/**
 * Build the report envelope required by TEST-001. `resultClass` must be one
 * of MOCK_ONLY / ESTIMATE / EMULATOR_ONLY / DEVICE_ONLY / UNAVAILABLE.
 */
export function buildPerfReport(summary, metadata) {
  const allowed = new Set([
    'MOCK_ONLY',
    'ESTIMATE',
    'EMULATOR_ONLY',
    'DEVICE_ONLY',
    'UNAVAILABLE',
  ]);
  if (!allowed.has(metadata.resultClass)) {
    throw new Error(`invalid resultClass: ${metadata.resultClass}`);
  }
  return {
    metric: metadata.metric,
    resultClass: metadata.resultClass,
    environment: metadata.environment,
    profile: metadata.profile,
    samples: summary.count,
    warmup: metadata.warmup ?? 0,
    p50Ms: summary.p50Ms,
    p95Ms: summary.p95Ms,
    maxMs: summary.maxMs,
    measuredAt: metadata.measuredAt ?? new Date().toISOString(),
    limitation: metadata.limitation ?? '',
  };
}
