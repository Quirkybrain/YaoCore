/*
 * YaoCore C-28 UI page VM factory seam (T-18 additive contract).
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §17.1.2 (T-18 incremental VM factory seam), §0.8, D-17
 *
 * The UI receives this port through Index/MainShell explicit props. Pages call
 * create*ViewModel() in aboutToAppear and dispose the instance in
 * aboutToDisappear; they never construct services, repositories or VMs.
 */
import type { BleProvisioningViewModel } from '../viewmodel/BleProvisioningViewModel';
import type { ClimateViewModel } from '../viewmodel/ClimateViewModel';
import type { DeviceViewModel } from '../viewmodel/DeviceViewModel';
import type { DoorViewModel } from '../viewmodel/DoorViewModel';
import type { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import type { HomeViewModel } from '../viewmodel/HomeViewModel';
import type { RoomViewModel } from '../viewmodel/RoomViewModel';
import type { SceneViewModel } from '../viewmodel/SceneViewModel';
import type { SettingsViewModel } from '../viewmodel/SettingsViewModel';

export interface PageVmFactoryPort {
  createHomeViewModel(): HomeViewModel;
  createDeviceViewModel(): DeviceViewModel;
  createClimateViewModel(): ClimateViewModel;
  createDoorViewModel(): DoorViewModel;
  createFamilyViewModel(): FamilyViewModel;
  createRoomViewModel(): RoomViewModel;
  createSceneViewModel(): SceneViewModel;
  createBleProvisioningViewModel(): BleProvisioningViewModel;
  createSettingsViewModel(): SettingsViewModel;
}
