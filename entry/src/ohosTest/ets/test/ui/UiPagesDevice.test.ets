/*
 * YaoCore C-24..C-27 UI device-side compile skeleton.
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §13.4/§14.4/§15.4/§16.4; D-019 device layer
 *
 * STATUS: BLOCKED_ON_DEVICE_RUNNER — no device/emulator and no signing config
 * in this environment. This suite is COMPILED_ONLY and must never be reported
 * as a device PASS from the host Node runner. Its value is keeping every new
 * page/component in the ohosTest ArkTS compile graph, so a decorator/props
 * regression fails the build before Review.
 *
 * This is a presence/wiring smoke only; real launch, navigation, visual and
 * accessibility checks remain in T-19.
 */
import { describe, expect, it } from '@ohos/hypium';

import { HomePage } from '../../../../main/ets/pages/HomePage';
import { RoomsPage } from '../../../../main/ets/pages/RoomsPage';
import { DeviceControlPage } from '../../../../main/ets/pages/DeviceControlPage';
import { FamilyManagePage } from '../../../../main/ets/pages/FamilyManagePage';
import { RoomManagePage } from '../../../../main/ets/pages/RoomManagePage';
import { ScenePage } from '../../../../main/ets/pages/ScenePage';
import { ProvisioningPage } from '../../../../main/ets/pages/ProvisioningPage';
import { SettingsPage } from '../../../../main/ets/pages/SettingsPage';
import { AboutPage } from '../../../../main/ets/pages/AboutPage';
import { ProfilePage } from '../../../../main/ets/pages/ProfilePage';
import {
  AppDialog,
  AppTextField,
  EmptyState,
  ErrorState,
  GlassSurface,
  LoadingSkeleton,
  PrimaryButton,
  SectionHeader,
  SliderControl
} from '../../../../main/ets/components/CommonControls';
import {
  ClimateCard,
  DoorCard,
  LightCard,
  RoomCard,
  SceneCard,
  SensorTile
} from '../../../../main/ets/components/DeviceCards';
import { DeviceGrid, UnassignedPool } from '../../../../main/ets/components/DeviceGrid';
import { RoomChipBar } from '../../../../main/ets/components/RoomChipBar';
import { EnvironmentPanel, StatusBanner } from '../../../../main/ets/components/StatusPanels';
import { AppColors, AppMotionTokens } from '../../../../main/ets/common/theme/AppTheme';
import { CardVisualState } from '../../../../main/ets/common/theme/AppEnums';

export default function uiPagesDeviceTest(): void {
  describe('BLOCKED_ON_DEVICE_RUNNER C24-C27 UI', () => {
    it('C24_C27_pagesAndComponentsAreWired', 0, () => {
      expect(HomePage !== undefined).assertTrue();
      expect(RoomsPage !== undefined).assertTrue();
      expect(DeviceControlPage !== undefined).assertTrue();
      expect(FamilyManagePage !== undefined).assertTrue();
      expect(RoomManagePage !== undefined).assertTrue();
      expect(ScenePage !== undefined).assertTrue();
      expect(ProvisioningPage !== undefined).assertTrue();
      expect(SettingsPage !== undefined).assertTrue();
      expect(AboutPage !== undefined).assertTrue();
      expect(ProfilePage !== undefined).assertTrue();
      expect(StatusBanner !== undefined).assertTrue();
      expect(EnvironmentPanel !== undefined).assertTrue();
      expect(RoomChipBar !== undefined).assertTrue();
      expect(LightCard !== undefined).assertTrue();
      expect(ClimateCard !== undefined).assertTrue();
      expect(DoorCard !== undefined).assertTrue();
      expect(SensorTile !== undefined).assertTrue();
      expect(SceneCard !== undefined).assertTrue();
      expect(RoomCard !== undefined).assertTrue();
      expect(DeviceGrid !== undefined).assertTrue();
      expect(UnassignedPool !== undefined).assertTrue();
      expect(GlassSurface !== undefined).assertTrue();
      expect(SectionHeader !== undefined).assertTrue();
      expect(PrimaryButton !== undefined).assertTrue();
      expect(AppTextField !== undefined).assertTrue();
      expect(SliderControl !== undefined).assertTrue();
      expect(EmptyState !== undefined).assertTrue();
      expect(ErrorState !== undefined).assertTrue();
      expect(LoadingSkeleton !== undefined).assertTrue();
      expect(AppDialog !== undefined).assertTrue();
      expect(CardVisualState.PENDING).assertEqual('PENDING');
      expect(AppMotionTokens.THROTTLE_CONTINUOUS_MS).assertEqual(55);
      expect(AppColors.primary() !== undefined).assertTrue();
    });
  });
}
