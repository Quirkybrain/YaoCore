"""Static contracts that prevent same-brand devices from sharing state."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class MultiDeviceContractTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_app_uses_gateway_and_device_as_physical_identity(self) -> None:
        repository = self.read("entry/src/main/ets/service/DeviceRepository.ets")
        storage = self.read("entry/src/main/ets/service/AppStorageService.ets")
        self.assertIn("`${gatewayId}::${device.deviceId.trim()}`", storage)
        self.assertIn("`${this.getBoundGatewayId().trim()}::${deviceId.trim()}`", repository)
        self.assertIn("this.findMutable(deviceId, gatewayId)", repository)

    def test_preset_scene_expands_to_all_matching_bound_devices(self) -> None:
        scene = self.read("entry/src/main/ets/service/SceneService.ets")
        self.assertIn("findBoundDevicesByType", scene)
        self.assertRegex(scene, r"for \(let deviceIndex = 0; deviceIndex < devices\.length;")
        self.assertNotIn("findBoundDeviceByType", scene)

    def test_quick_control_target_is_stable_when_connectivity_changes(self) -> None:
        home = self.read("entry/src/main/ets/viewmodel/HomeViewModel.ets")
        method = home[home.index("private getFirstDevice"):]
        self.assertIn("devices[index].deviceId < selected.deviceId", method)
        self.assertNotIn("devices[index].isOnline", method.split("private resolveSecurityLabel", 1)[0])

    def test_cloud_shadow_has_dynamic_device_inventory(self) -> None:
        cloud = self.read("entry/src/main/ets/service/CloudService.ets")
        firmware = self.read("gateway/esp32s3m/main/cloud_iotda.c")
        profile = self.read("cloud/iotda/product-profile.json")
        for source in (cloud, firmware, profile):
            self.assertIn("DeviceInventoryJson", source)
        self.assertIn('cJSON_AddStringToObject(item, "device_id", d->device_id)', firmware)
        self.assertIn("this.toReportedState(inventory[index], deviceId)", cloud)

    def test_background_monitor_never_scans_an_unbound_subnet(self) -> None:
        repository = self.read("entry/src/main/ets/service/DeviceRepository.ets")
        self.assertIn("boundGatewayId.length === 0", repository)
        self.assertIn("never sweep the whole subnet", repository)


if __name__ == "__main__":
    unittest.main(verbosity=2)
