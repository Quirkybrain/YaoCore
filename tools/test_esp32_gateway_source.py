# YaoCore (爻构) - Open-source smart home system
# Copyright (c) 2026 Zhang HaoXuan
# Author: Zhang HaoXuan
# Created: 2026-07-17
# Source: https://github.com/Quirkybrain/YaoCore
# SPDX-License-Identifier: Apache-2.0

import hashlib
import hmac
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
GATEWAY = ROOT / "gateway" / "esp32s3m"


class Esp32GatewaySourceTests(unittest.TestCase):
    def read(self, name: str) -> str:
        return (GATEWAY / name).read_text(encoding="utf-8")

    def test_project_has_all_runtime_modules(self):
        required = {
            "main/app_main.c",
            "main/network_manager.c",
            "main/local_server.c",
            "main/gateway_security.c",
            "main/device_router.c",
            "main/cloud_iotda.c",
            "main/Kconfig.projbuild",
            "main/idf_component.yml",
        }
        self.assertTrue(required.issubset({p.relative_to(GATEWAY).as_posix() for p in GATEWAY.rglob("*") if p.is_file()}))

    def test_local_contract_matches_app_and_schema(self):
        local = self.read("main/local_server.c")
        security = self.read("main/gateway_security.c")
        for marker in ("/discover", "/control", "protocolVersion", "reported_state", "server_time", "idempotent_replay"):
            self.assertIn(marker, local)
        for marker in ("FRESHNESS_SECONDS 120", "NONCE_TTL_SECONDS 300", "MBEDTLS_MD_SHA256", "constant_time_equal"):
            self.assertIn(marker, security)

    def test_router_never_reports_unconfigured_driver_success(self):
        router = self.read("main/device_router.c")
        self.assertIn("DRIVER_NOT_CONFIGURED", router)
        self.assertIn("air-conditioner IR driver not configured", router)
        self.assertGreaterEqual(router.count("cfg->light_gpio < 0"), 2)

    def test_iotda_topics_and_tls_are_present(self):
        cloud = self.read("main/cloud_iotda.c")
        for marker in ("sys/commands/#", "sys/commands/response/request_id=", "sys/properties/report", "esp_crt_bundle_attach"):
            self.assertIn(marker, cloud)

    def test_udp_default_matches_app_gateway_port(self):
        kconfig = self.read("main/Kconfig.projbuild")
        udp_section = kconfig.split("config YAOCORE_DISCOVERY_UDP_PORT", 1)[1].split("config ", 1)[0]
        self.assertIn("default 9200", udp_section)

    def test_dnesp32s3m_n16r8_defaults(self):
        sdkconfig = self.read("sdkconfig.defaults")
        kconfig = self.read("main/Kconfig.projbuild")
        for marker in ("CONFIG_ESPTOOLPY_FLASHSIZE_16MB=y", "CONFIG_SPIRAM_MODE_OCT=y"):
            self.assertIn(marker, sdkconfig)
        led_section = kconfig.split("config YAOCORE_BOARD_LED_GPIO", 1)[1].split("config ", 1)[0]
        self.assertIn("default 1", led_section)
        self.assertIn("config YAOCORE_BOARD_LED_ACTIVE_LOW", kconfig)

    def test_huawei_documented_password_vector(self):
        # Huawei IoTDA documentation example: secret=12345678, UTC hour=2025041401.
        digest = hmac.new(b"2025041401", b"12345678", hashlib.sha256).hexdigest()
        self.assertEqual("c75150e6cb841417396819e4d2ee4358a416344a03a083e3a8567074ddec820a", digest)


if __name__ == "__main__":
    unittest.main()
