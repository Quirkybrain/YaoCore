/*
 * YaoCore ohosTest suite entry point.
 * Producer: agent:implementation-engineer | Task: wp-018-fix-t07 (R-04);
 *           wp-022-fix-t08 (R-03: register the C-06/C-07 storage skeleton)
 *
 * Registers every device-side suite so `onDeviceTest` actually executes them
 * once a device/emulator and signing config exist. Registration does not mean
 * PASS: each suite remains BLOCKED_ON_DEVICE_RUNNER in this environment.
 */
import baselineTest from './Baseline.test';
import bleProvisioningDeviceTest from './ble/BleProvisioningDevice.test';
import foundationDeviceTest from './foundation/FoundationDevice.test';
import gatewayTransportDeviceTest from './gateway/GatewayTransportDevice.test';
import i18nDeviceTest from './i18n/I18nDevice.test';
import securityDeviceTest from './security/SecurityDevice.test';
import storageDeviceTest from './storage/StorageDevice.test';

export default function testsuite() {
  baselineTest();
  foundationDeviceTest();
  securityDeviceTest();
  storageDeviceTest();
  i18nDeviceTest();
  gatewayTransportDeviceTest();
  bleProvisioningDeviceTest();
}
