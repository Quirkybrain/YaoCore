/*
 * YaoCore ohosTest suite entry point.
 * Producer: agent:implementation-engineer | Task: wp-018-fix-t07 (R-04)
 *
 * Registers every device-side suite so `onDeviceTest` actually executes them
 * once a device/emulator and signing config exist. Registration does not mean
 * PASS: each suite remains BLOCKED_ON_DEVICE_RUNNER in this environment.
 */
import baselineTest from './Baseline.test';
import foundationDeviceTest from './foundation/FoundationDevice.test';
import securityDeviceTest from './security/SecurityDevice.test';

export default function testsuite() {
  baselineTest();
  foundationDeviceTest();
  securityDeviceTest();
}
