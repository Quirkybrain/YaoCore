#!/usr/bin/env python3
# YaoCore (爻构) - Open-source smart home system
# Copyright (c) 2026 Zhang HaoXuan
# Author: Zhang HaoXuan
# Created: 2026-07-17
# Source: https://github.com/Quirkybrain/YaoCore
# SPDX-License-Identifier: Apache-2.0

"""Static checks for YaoCore branding, onboarding, and language selection."""

from __future__ import annotations

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class BrandLocalizationTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_launch_slogan_and_swipe_tutorial_are_reachable(self) -> None:
        index = self.read("entry/src/main/ets/pages/Index.ets")
        onboarding = self.read("entry/src/main/ets/pages/OnboardingPage.ets")
        self.assertIn("爻联万物，构筑智慧。", index)
        self.assertIn("Connecting Things, Building Intelligence.", index)
        self.assertIn("Swiper()", onboarding)
        self.assertIn(".loop(false)", onboarding)
        self.assertIn("this.currentPage = index", onboarding)
        self.assertIn("开始使用", onboarding)

    def test_onboarding_matches_real_gateway_enrollment_flow(self) -> None:
        onboarding = self.read("entry/src/main/ets/pages/OnboardingPage.ets")
        for label in (
            "保存控制密钥",
            "输入 PoP 完成 BLE 配网",
            "成功后自动认证并绑定，无需再次查找",
            "添加设备并同步真实状态",
        ):
            self.assertIn(label, onboarding)

    def test_language_specific_ui_does_not_hardcode_english_option_copy(self) -> None:
        settings = self.read("entry/src/main/ets/pages/SettingsPage.ets")
        self.assertIn("I18nService.t('始终使用英文')", settings)
        self.assertNotIn("'Always use English'", settings)

    def test_region_policy_and_manual_override_are_implemented(self) -> None:
        service = self.read("entry/src/main/ets/service/I18nService.ets")
        settings = self.read("entry/src/main/ets/pages/SettingsPage.ets")
        for region in ("'CN'", "'TW'", "'HK'", "'MO'"):
            self.assertIn(region, service)
        self.assertIn("setAppPreferredLanguage", service)
        self.assertIn("setPreference", service)
        for preference in ("'auto'", "'zh-Hans'", "'en'"):
            self.assertIn(preference, settings)
        self.assertIn("onLanguageChanged", settings)

    def test_app_and_gateway_use_yaocore_brand(self) -> None:
        app_strings = self.read("AppScope/resources/base/element/string.json")
        app_strings_en = self.read("AppScope/resources/en_US/element/string.json")
        ble = self.read("entry/src/main/ets/service/BleProvisioningService.ets")
        network = self.read("gateway/esp32s3m/main/network_manager.c")
        local_server = self.read("gateway/esp32s3m/main/local_server.c")
        self.assertIn("爻构", app_strings)
        self.assertIn("YaoCore", app_strings_en)
        self.assertIn("YaoCore-GW-", ble)
        self.assertIn("YaoCore-GW-", network)
        self.assertIn("X-YaoCore-", local_server)

    def test_legacy_brand_is_absent_from_app_gateway_and_protocol(self) -> None:
        legacy = "aura" + "nest"
        roots = ("AppScope", "entry", "gateway/esp32s3m/main", "protocol", "cloud")
        suffixes = {".ets", ".ts", ".c", ".h", ".json", ".json5", ".md", ".yml"}
        for root in roots:
            for path in (ROOT / root).rglob("*"):
                if path.is_file() and path.suffix.lower() in suffixes and "build" not in path.parts:
                    self.assertNotIn(legacy, path.read_text(encoding="utf-8").lower(), str(path))
        app = self.read("AppScope/app.json5")
        self.assertIn('"bundleName": "io.github.quirkybrain.yaocore"', app)

    def test_legal_and_public_names_are_separated(self) -> None:
        notice = self.read("NOTICE")
        authors = self.read("AUTHORS.md")
        settings = self.read("entry/src/main/ets/pages/SettingsPage.ets")
        handle = "Quirky" + "brain"
        self.assertIn("Copyright 2026 Zhang HaoXuan", notice)
        self.assertNotIn(f"Copyright 2026 {handle}", notice)
        self.assertIn("legal copyright holder", authors)
        self.assertIn("'Quirkybrain'", settings)

    def test_refresh_and_scan_actions_expose_busy_feedback(self) -> None:
        banner = self.read("entry/src/main/ets/components/StatusBanner.ets")
        home = self.read("entry/src/main/ets/pages/HomePage.ets")
        devices = self.read("entry/src/main/ets/pages/DevicePage.ets")
        settings = self.read("entry/src/main/ets/pages/SettingsPage.ets")
        self.assertIn("@Prop refreshing", banner)
        self.assertIn("sys.symbol.arrow_clockwise", banner)
        self.assertIn("LoadingProgress()", banner)
        self.assertIn("650 - (Date.now() - startedAt)", home)
        self.assertIn("refreshingGateway", home)
        for state in ("bleScanning", "scanningWiFiNetworks", "scanningGateways", "scanningDevices", "syncingDevices"):
            self.assertIn(state, devices)
        self.assertIn("busyOperation", settings)
        self.assertIn("rowBusyButton", settings)
        self.assertIn("fullBusyButton", settings)

    def test_icon_combines_hexagram_and_circuit_motifs(self) -> None:
        icon = self.read("AppScope/resources/base/media/app_icon.svg")
        self.assertIn('id="bronze"', icon)
        self.assertIn('id="jade"', icon)
        self.assertIn("M54 12L87 31V77L54 96", icon)
        self.assertIn("M34 43H49M59 43H74", icon)

    def test_system_back_uses_real_navigation_stack(self) -> None:
        index = self.read("entry/src/main/ets/pages/Index.ets")
        settings = self.read("entry/src/main/ets/pages/SettingsPage.ets")
        onboarding = self.read("entry/src/main/ets/pages/OnboardingPage.ets")
        self.assertIn("new NavPathStack()", index)
        self.assertIn("Navigation(this.pathStack)", index)
        self.assertIn(".navDestination(this.destinationBuilder)", index)
        self.assertIn("pushPathByName('deviceControl'", index)
        self.assertIn(".onBackPressed(() =>", index)
        self.assertGreaterEqual(index.count("this.pathStack.pop(true)"), 3)
        self.assertIn("if (this.settingsPage !== 'main')", index)
        self.assertIn("@Link currentPage", settings)
        self.assertIn("@Link currentPage", onboarding)

    def test_glass_material_and_live_capsule_are_not_decorative_stubs(self) -> None:
        index = self.read("entry/src/main/ets/pages/Index.ets")
        theme = self.read("entry/src/main/ets/common/constants/AppTheme.ets")
        pages = "\n".join(self.read(path) for path in (
            "entry/src/main/ets/pages/HomePage.ets",
            "entry/src/main/ets/pages/DevicePage.ets",
            "entry/src/main/ets/pages/ScenePage.ets",
            "entry/src/main/ets/pages/SettingsPage.ets",
            "entry/src/main/ets/pages/DeviceControlPage.ets",
        ))
        self.assertIn("liveStatusCapsule", index)
        self.assertIn("this.repository.getGateway()", index)
        self.assertIn("this.repository.getBoundGatewayId()", index)
        self.assertIn("this.repository.getDevices()", index)
        self.assertIn("this.gatewayState.gatewayName", index)
        self.assertIn("this.gatewayState.localIp", index)
        self.assertNotIn("this.tabTitle()", index)
        self.assertIn("connectedGatewayCard", pages)
        self.assertIn("COMPONENT_THICK", index)
        self.assertIn("GLASS_BORDER", theme)
        self.assertGreaterEqual(pages.count("backgroundBlurStyle"), 15)
        self.assertGreaterEqual(pages.count("linearGradient"), 5)


if __name__ == "__main__":
    unittest.main()
