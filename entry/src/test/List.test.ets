/*
 * YaoCore host (local) unit-test entry point.
 * Producer: agent:test-engineer (baseline) / agent:implementation-engineer (T-06/T-07 suites)
 * Task: T-05 / wp-010-test-plan; T-06 / wp-012-foundation; T-07 / wp-016-security
 *
 * `hvigorw test` generates a local TestAbility that imports this exact module
 * (`entry/src/test/List.test.ets`). Keep this file as the single suite
 * aggregator and import each host test module here.
 *
 * The executable host path in this Linux environment is
 * `entry/src/test/run-host-tests.sh` (Node); `hvigorw test` remains
 * COMPILED_ONLY + BLOCKED by the Previewer limitation (TEST-001 §2.3).
 */
import hostBaselineTest from './HostBaseline.test';
import { DateTimeUtilSuite } from './foundation/DateTimeUtil.test';
import { JsonAtomSuite } from './foundation/JsonAtom.test';
import { DiscoverMapperSuite } from './protocol/DiscoverMapper.test';
import { ControlAckMapperSuite } from './protocol/ControlAckMapper.test';
import { ControlRequestSerializerSuite } from './protocol/ControlRequestSerializer.test';
import { IdentityParserSuite } from './protocol/IdentityParser.test';
import { StateReportMapperSuite } from './protocol/StateReportMapper.test';
import { SecurityHostSuite } from './security/SecurityHost.test';
import { StorageHostSuite } from './storage/StorageHost.test';
import { DomainHostSuite } from './domain/DomainHost.test';

export default function testsuite() {
  hostBaselineTest();
  DateTimeUtilSuite();
  JsonAtomSuite();
  DiscoverMapperSuite();
  ControlAckMapperSuite();
  ControlRequestSerializerSuite();
  IdentityParserSuite();
  StateReportMapperSuite();
  SecurityHostSuite();
  StorageHostSuite();
  DomainHostSuite();
}
