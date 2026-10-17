/*
 * YaoCore C-21..C-23 ViewModel device-side compile skeleton.
 * Producer: agent:implementation-engineer | Task: T-15/T-16 / wp-060-vm
 * Contract: DES-B §10.4/§11.4/§12.4; D-019 device layer
 *
 * STATUS: BLOCKED_ON_DEVICE_RUNNER — no device/emulator and no signing config
 * in this environment. This suite is COMPILED_ONLY and must never be reported
 * as PASS from the host Node runner. It exists so the ohosTest target
 * type-checks every view model against the production services/ports.
 *
 * PUBLIC TEST DATA ONLY.
 */
import { describe, expect, it } from '@ohos/hypium';

import { HomeViewModel, HomeViewState } from '../../../../main/ets/viewmodel/HomeViewModel';
import { DeviceViewModel, DeviceViewState } from '../../../../main/ets/viewmodel/DeviceViewModel';
import { ClimateViewModel, ClimateViewState } from '../../../../main/ets/viewmodel/ClimateViewModel';
import { DoorViewModel, DoorViewState } from '../../../../main/ets/viewmodel/DoorViewModel';
import { FamilyViewModel, FamilyViewState } from '../../../../main/ets/viewmodel/FamilyViewModel';
import { RoomViewModel, RoomViewState } from '../../../../main/ets/viewmodel/RoomViewModel';
import { SceneViewModel, SceneViewState } from '../../../../main/ets/viewmodel/SceneViewModel';
import {
  BleProvisioningViewModel,
  BleProvisioningViewState
} from '../../../../main/ets/viewmodel/BleProvisioningViewModel';
import {
  SettingsViewModel,
  SettingsViewState
} from '../../../../main/ets/viewmodel/SettingsViewModel';
import { SupportedLocale } from '../../../../main/ets/service/i18n/I18nModels';
import { DeviceControlCoordinator } from '../../../../main/ets/viewmodel/core/DeviceControlCoordinator';
import { DoorConfirmationTracker } from '../../../../main/ets/viewmodel/core/DoorConfirmationTracker';
import { ThrottleGate } from '../../../../main/ets/viewmodel/core/ThrottleGate';

export default function viewModelsDeviceTest(): void {
  describe('BLOCKED_ON_DEVICE_RUNNER C21-C23 view models', () => {
    it('C21_C23_viewModelExportsAreWired', 0, () => {
      expect(HomeViewModel !== undefined).assertTrue();
      expect(DeviceViewModel !== undefined).assertTrue();
      expect(ClimateViewModel !== undefined).assertTrue();
      expect(DoorViewModel !== undefined).assertTrue();
      expect(FamilyViewModel !== undefined).assertTrue();
      expect(RoomViewModel !== undefined).assertTrue();
      expect(SceneViewModel !== undefined).assertTrue();
      expect(BleProvisioningViewModel !== undefined).assertTrue();
      expect(SettingsViewModel !== undefined).assertTrue();
      expect(DeviceControlCoordinator !== undefined).assertTrue();
      expect(DoorConfirmationTracker !== undefined).assertTrue();
      expect(ThrottleGate !== undefined).assertTrue();
      expect(HomeViewState.initial() !== undefined).assertTrue();
      expect(DeviceViewState.initial() !== undefined).assertTrue();
      expect(FamilyViewState.initial() !== undefined).assertTrue();
      expect(RoomViewState.initial() !== undefined).assertTrue();
      expect(BleProvisioningViewState.initial() !== undefined).assertTrue();
      expect(SettingsViewState.initial(SupportedLocale.ZH_CN) !== undefined).assertTrue();
      expect(ClimateViewState !== undefined).assertTrue();
      expect(DoorViewState !== undefined).assertTrue();
      expect(SceneViewState !== undefined).assertTrue();
    });
  });
}
