import test from 'node:test';
import assert from 'node:assert/strict';

import {
  buildPerfReport,
  measureOperation,
  percentile,
  summarizeSamples,
} from './perf-harness.mjs';

test('percentile uses nearest-rank and handles p50/p95', () => {
  const values = Array.from({ length: 100 }, (_, index) => index + 1);
  assert.equal(percentile(values, 50), 50);
  assert.equal(percentile(values, 95), 95);
  assert.equal(percentile(values, 0), 1);
  assert.equal(percentile(values, 100), 100);
});

test('summarizeSamples reports count/min/p50/p95/max', () => {
  const summary = summarizeSamples([1, 2, 3, 4, 5]);
  assert.deepEqual(summary, {
    count: 5,
    minMs: 1,
    p50Ms: 3,
    p95Ms: 5,
    maxMs: 5,
  });
});

test('measureOperation discards warmup and collects N samples', async () => {
  const calls = [];
  const summary = await measureOperation(
    async (index, isWarmup) => {
      calls.push({ index, isWarmup });
      return index + 1;
    },
    { samples: 10, warmup: 2 },
  );
  assert.equal(calls.length, 12);
  assert.equal(calls.filter((call) => call.isWarmup).length, 2);
  assert.equal(summary.count, 10);
  assert.equal(summary.minMs, 1);
  assert.equal(summary.maxMs, 10);
});

test('buildPerfReport rejects invented result classes', () => {
  const summary = summarizeSamples([1, 2, 3]);
  assert.throws(
    () =>
      buildPerfReport(summary, {
        metric: 'ack.p95',
        resultClass: 'PASS',
        environment: 'localhost',
      }),
    /invalid resultClass/,
  );
  const report = buildPerfReport(summary, {
    metric: 'ack.p95',
    resultClass: 'MOCK_ONLY',
    environment: 'linux localhost simulator',
    profile: 'light/SET_BRIGHTNESS',
    warmup: 2,
    limitation: 'not a real LAN/device measurement',
  });
  assert.equal(report.samples, 3);
  assert.equal(report.p95Ms, 3);
  assert.equal(report.resultClass, 'MOCK_ONLY');
});
