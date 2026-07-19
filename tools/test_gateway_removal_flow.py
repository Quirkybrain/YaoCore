"""Static regression checks for safe gateway removal and cleanup."""

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


class GatewayRemovalFlowTests(unittest.TestCase):
    def test_app_has_no_direct_uno_r4_onboarding(self) -> None:
        app = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (ROOT / "entry/src/main/ets").rglob("*.ets")
        )
        self.assertNotIn("R4LightProvisioningService", app)
        self.assertNotIn("r4LightProvisioningCard", app)
        self.assertNotIn("UNO R4 灯", app)

    def test_gateway_removal_requires_expansion_and_warning_dialog(self) -> None:
        page = read("entry/src/main/ets/pages/DevicePage.ets")
        self.assertIn("gatewayDetailsExpanded = !this.gatewayDetailsExpanded", page)
        self.assertIn("确认删除网关", page)
        self.assertIn("bindSheet($$this.showGatewayRemovalDialog", page)
        self.assertIn("是否确认删除网关？", page)
        self.assertIn("仍要删除", page)
        self.assertIn("不会恢复出厂", page)

    def test_unbind_clears_route_key_devices_and_scenes(self) -> None:
        network = read("entry/src/main/ets/service/NetworkService.ets")
        repository = read("entry/src/main/ets/service/DeviceRepository.ets")
        scenes = read("entry/src/main/ets/service/SceneService.ets")
        view_model = read("entry/src/main/ets/viewmodel/DeviceViewModel.ets")
        self.assertIn("saveLocalRoute(createDefaultLocalRouteConfig())", network)
        self.assertIn("clearSessionSecret()", network)
        self.assertIn("clearGatewayBinding()", network)
        self.assertIn("this.devices = retained", repository)
        self.assertIn("removeGatewayActions", scenes)
        self.assertIn("scene.actions = nextActions", scenes)
        self.assertIn("repository.unbindGateway(gatewayId)", view_model)


if __name__ == "__main__":
    unittest.main()
