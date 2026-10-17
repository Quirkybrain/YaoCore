/*
 * YaoCore host (local) unit-test entry point.
 * Producer: agent:test-engineer | Task: T-05 / wp-010-test-plan
 *
 * `hvigorw test` generates a local TestAbility that imports this exact module
 * (`entry/src/test/List.test.ets`). Keep this file as the single suite
 * aggregator and import each host test module here.
 */
import hostBaselineTest from './HostBaseline.test';

export default function testsuite() {
  hostBaselineTest();
}
