# YaoCore (爻构) - Open-source smart home system
# Copyright (c) 2026 Zhang HaoXuan
# Author: Zhang HaoXuan
# Created: 2026-07-17
# Source: https://github.com/Quirkybrain/YaoCore
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class SensorAutomationFlowTests(unittest.TestCase):
    def source(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_hardware_sensor_is_decoupled_from_actuator_and_uses_router(self) -> None:
        driver = self.source("gateway/esp32s3m/main/hardware_drivers.c")
        automation = self.source("gateway/esp32s3m/main/automation_engine.c")
        router = self.source("gateway/esp32s3m/main/device_router.c")
        self.assertIn("HARDWARE_EVENT_PRESENCE", driver)
        self.assertNotIn("set_light_locked((uint8_t)cfg->pir_light_brightness", driver)
        self.assertIn("s_executor(command, &ack)", automation)
        self.assertIn("ack.has_reported_state", automation)
        self.assertIn("automation_engine_on_sensor_state", router)

    def test_manual_priority_and_two_real_rule_paths_are_explicit(self) -> None:
        automation = self.source("gateway/esp32s3m/main/automation_engine.c")
        for marker in (
            'PRESENCE_LIGHT_RULE "presence-light-v1"',
            'TEMPERATURE_AC_RULE "temperature-ac-v1"',
            "s_presence_owns_light = false",
            "s_temperature_owns_ac = false",
            "automation_engine_note_external_command",
        ):
            self.assertIn(marker, automation)

    def test_app_reconciles_authenticated_inventory_and_displays_provenance(self) -> None:
        repository = self.source("entry/src/main/ets/service/DeviceRepository.ets")
        discovery = self.source("entry/src/main/ets/service/GatewayDiscoveryService.ets")
        page = self.source("entry/src/main/ets/pages/DevicePage.ets")
        self.assertIn("reconcileGatewayInventory", repository)
        self.assertIn("item.gatewayId !== gatewayId", repository)
        for marker in ("presence", "stateSource", "triggerDeviceId", "automationId"):
            self.assertIn(marker, discovery)
            self.assertIn(marker, page)
        # A physical knob/sensor change must become visible on list/home pages
        # promptly; the detail page has its own faster, drag-aware poller.
        self.assertIn("}, 1200);", repository)
        self.assertIn("now - this.lastCloudSyncMs >= 10000", repository)

    def test_home_cards_follow_live_repository_state_and_coalesce_slider_samples(self) -> None:
        home = self.source("entry/src/main/ets/pages/HomePage.ets")
        light = self.source("entry/src/main/ets/components/LightCard.ets")
        for component in ("LightCard.ets", "DoorCard.ets", "ClimateCard.ets", "StatusBanner.ets"):
            source = self.source(f"entry/src/main/ets/components/{component}")
            self.assertIn("@Prop", source)
        self.assertIn("step: 1", light)
        self.assertIn("this.onBrightnessChange(value, finalValue)", light)
        self.assertIn("pendingQuickBrightness", home)
        self.assertIn("quickBrightnessInFlight", home)
        self.assertIn("scheduleQuickBrightness", home)

    def test_cloud_model_contains_presence_and_automation_provenance(self) -> None:
        profile = json.loads(
            (ROOT / "cloud/iotda/product-profile.json").read_text(encoding="utf-8")
        )
        properties = {
            item["propertyName"] for item in profile["services"][0]["properties"]
        }
        self.assertTrue(
            {
                "Presence_01_Online",
                "Presence_01_Detected",
                "Light_01_StateSource",
                "Light_01_TriggerDeviceId",
                "Light_01_AutomationId",
                "AC_01_StateSource",
                "AC_01_TriggerDeviceId",
                "AC_01_AutomationId",
            }.issubset(properties)
        )


if __name__ == "__main__":
    unittest.main()
