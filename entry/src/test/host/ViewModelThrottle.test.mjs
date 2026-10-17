/*
 * YaoCore T-15 ThrottleGate host tests.
 * Producer: agent:implementation-engineer | Task: T-15 / wp-060-vm
 * Contract: DES-B §10.1.4, §10.3.2; PF-02.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { ThrottleGate, ThrottlePhase } from '../../main/ets/viewmodel/core/ThrottleGate.ets';
import { FakeClock, FakeTimer, waitMicrotasks } from './viewmodel-helpers.mjs';

function gateWithQueue(options = {}) {
  const clock = new FakeClock();
  const timer = new FakeTimer(clock);
  const dispatched = [];
  const resolvers = [];
  const rejecters = [];
  const gate = new ThrottleGate(timer, clock, 55, async (value) => {
    dispatched.push(value);
    await new Promise((resolve, reject) => {
      resolvers.push(resolve);
      rejecters.push(reject);
    });
  });
  return { clock, timer, dispatched, resolvers, rejecters, gate };
}

test('T15_Throttle_coalescesWithin55msAndKeepsLatest', async () => {
  const h = gateWithQueue();
  h.gate.onInput(10);
  h.gate.onInput(20);
  h.timer.advance(54);
  assert.deepEqual(h.dispatched, []);
  assert.equal(h.gate.getPhase(), ThrottlePhase.COALESCING);
  h.timer.advance(1);
  assert.deepEqual(h.dispatched, [20]);
  assert.equal(h.gate.getPhase(), ThrottlePhase.IN_FLIGHT);
  h.resolvers[0]();
  await waitMicrotasks();
  assert.equal(h.gate.getPhase(), ThrottlePhase.IDLE);
});

test('T15_Throttle_oneInFlightAndLatestDispatchedAfterFinish', async () => {
  const h = gateWithQueue();
  h.gate.onInput(10);
  h.timer.advance(55);
  assert.deepEqual(h.dispatched, [10]);
  h.gate.onInput(20);
  h.gate.onInput(30);
  assert.deepEqual(h.dispatched, [10]);
  h.resolvers[0]();
  await waitMicrotasks();
  assert.deepEqual(h.dispatched, [10, 30]);
  h.resolvers[1]();
  await waitMicrotasks();
  assert.equal(h.gate.getPhase(), ThrottlePhase.IDLE);
});

test('T15_Throttle_touchUpWaitsForInFlightThenSendsFinalValue', async () => {
  const h = gateWithQueue();
  h.gate.onInput(10);
  h.timer.advance(55);
  const committed = h.gate.onCommit(40);
  assert.deepEqual(h.dispatched, [10]);
  h.resolvers[0]();
  await waitMicrotasks();
  assert.deepEqual(h.dispatched, [10, 40]);
  h.resolvers[1]();
  await committed;
  assert.equal(h.gate.getPhase(), ThrottlePhase.IDLE);
  assert.equal(h.gate.getLastDispatched(), 40);
});

test('T15_Throttle_cancelInvalidatesTimerAndLateResult', async () => {
  const h = gateWithQueue();
  h.gate.onInput(10);
  h.gate.cancel();
  h.timer.advance(1000);
  assert.deepEqual(h.dispatched, []);
  assert.equal(h.gate.getPhase(), ThrottlePhase.IDLE);
  h.gate.onInput(20);
  h.timer.advance(55);
  h.gate.cancel();
  h.resolvers[0]();
  await waitMicrotasks();
  assert.deepEqual(h.dispatched, [20]);
  assert.equal(h.gate.getPhase(), ThrottlePhase.IDLE);
});

test('T15_Throttle_commitBefore55msSendsFinalValueImmediately', async () => {
  const h = gateWithQueue();
  h.gate.onInput(10);
  const committed = h.gate.onCommit(20);
  await waitMicrotasks();
  assert.deepEqual(h.dispatched, [20]);
  h.resolvers[0]();
  await committed;
  assert.equal(h.gate.getPhase(), ThrottlePhase.IDLE);
  assert.equal(h.gate.getLastDispatched(), 20);
});

test('T15_Throttle_cancelWithWaiterResolvesWithoutExtraDispatch', async () => {
  const h = gateWithQueue();
  h.gate.onInput(10);
  h.timer.advance(55);
  assert.deepEqual(h.dispatched, [10]);
  const committed = h.gate.onCommit(30);
  h.gate.cancel();
  await committed;
  assert.equal(h.gate.getPhase(), ThrottlePhase.IDLE);
  h.timer.advance(500);
  await waitMicrotasks();
  assert.deepEqual(h.dispatched, [10]);
  h.resolvers[0]();
  await waitMicrotasks();
  assert.deepEqual(h.dispatched, [10]);
  assert.equal(h.gate.getPhase(), ThrottlePhase.IDLE);
});

test('T15_Throttle_dispatchFailureReturnsToIdleWithoutRetry', async () => {
  const clock = new FakeClock();
  const timer = new FakeTimer(clock);
  let calls = 0;
  const gate = new ThrottleGate(timer, clock, 55, async () => {
    calls++;
    throw new Error('dispatch failed');
  });
  gate.onInput(10);
  timer.advance(55);
  await waitMicrotasks();
  assert.equal(calls, 1);
  assert.equal(gate.getPhase(), ThrottlePhase.IDLE);
  assert.equal(gate.getLastFailed(), true);
  timer.advance(1000);
  assert.equal(calls, 1);
});
