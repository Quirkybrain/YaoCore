#!/usr/bin/env python3
# YaoCore (爻构) - Open-source smart home system
# Copyright (c) 2026 Zhang HaoXuan
# Author: Zhang HaoXuan
# Created: 2026-07-17
# Source: https://github.com/Quirkybrain/YaoCore
# SPDX-License-Identifier: Apache-2.0

"""Static contract and deterministic-vector checks for YaoCore BLE provisioning."""

from __future__ import annotations

import re
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GATEWAY = ROOT / "gateway" / "esp32s3m"
APP_ETS = ROOT / "entry" / "src" / "main" / "ets"
MANIFEST = ROOT / "entry" / "src" / "main" / "module.json5"
DESIGN = ROOT / "docs" / "BLE配网设计.md"

SERVICE_UUID = "7a6e0001-4d7b-4f67-9a21-6d13c52ae3b8"
DEVICE_PREFIX = "YaoCore-GW-"
ENDPOINTS = ("proto-ver", "prov-session", "prov-scan", "prov-config", "prov-ctrl", "yaocore-id", "yaocore-done")
FIXED_ENDPOINT_UUID_FRAGMENTS = (
    "7a6eff4f",
    "7a6eff50",
    "7a6eff51",
    "7a6eff52",
    "7a6eff53",
    "7a6eff54",
)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def aggregate(root: Path, suffixes: tuple[str, ...]) -> str:
    chunks: list[str] = []
    for path in sorted(root.rglob("*")):
        if path.is_file() and path.suffix.lower() in suffixes:
            chunks.append(read(path))
    return "\n".join(chunks)


def protobuf_varint(value: int) -> bytes:
    if value < 0:
        raise ValueError("this helper only encodes unsigned values")
    output = bytearray()
    while True:
        current = value & 0x7F
        value >>= 7
        output.append(current | (0x80 if value else 0))
        if not value:
            return bytes(output)


def protobuf_bytes(field_number: int, value: bytes) -> bytes:
    return protobuf_varint((field_number << 3) | 2) + protobuf_varint(len(value)) + value


def protobuf_uint(field_number: int, value: int) -> bytes:
    return protobuf_varint(field_number << 3) + protobuf_varint(value)


def protobuf_int32_value(value: int) -> bytes:
    encoded = value if value >= 0 else (1 << 64) + value
    return protobuf_varint(encoded)


def canonical_uuid_from_little_endian(raw: bytes) -> str:
    value = raw[::-1].hex()
    return f"{value[:8]}-{value[8:12]}-{value[12:16]}-{value[16:20]}-{value[20:]}"


class BleProvisioningVectorTests(unittest.TestCase):
    def test_security1_session_step0_protobuf_vector(self) -> None:
        client_public_key = bytes(range(32))
        session_cmd0 = protobuf_bytes(1, client_public_key)
        sec1_payload = protobuf_bytes(20, session_cmd0)
        session_data = bytes((0x10, 0x01)) + protobuf_bytes(11, sec1_payload)
        self.assertEqual(
            session_data.hex(),
            "10015a25a201220a20000102030405060708090a0b0c0d0e0f"
            "101112131415161718191a1b1c1d1e1f",
        )

    def test_minimal_wifi_config_vectors_are_documented(self) -> None:
        design = read(DESIGN).lower()
        self.assertIn("get_status   5200", design)
        self.assertIn("apply_config 08047200", design)

    def test_wifi_scan_request_vectors(self) -> None:
        scan_start_command = b"".join(
            (
                protobuf_uint(1, 1),
                protobuf_uint(2, 0),
                protobuf_uint(3, 0),
                protobuf_uint(4, 120),
            )
        )
        scan_start = protobuf_bytes(10, scan_start_command)
        scan_status = protobuf_uint(1, 2) + protobuf_bytes(12, b"")
        scan_result_command = protobuf_uint(1, 4) + protobuf_uint(2, 4)
        scan_result = protobuf_uint(1, 4) + protobuf_bytes(14, scan_result_command)
        self.assertEqual(scan_start.hex(), "52080801100018002078")
        self.assertEqual(scan_status.hex(), "08026200")
        self.assertEqual(scan_result.hex(), "0804720408041004")

    def test_negative_rssi_int32_uses_ten_byte_varint(self) -> None:
        self.assertEqual(protobuf_int32_value(-100).hex(), "9cffffffffffffffff01")
        self.assertIn("9cffffffffffffffff01", read(DESIGN).lower())

    def test_rfc7748_acceptance_vector_is_documented(self) -> None:
        design = read(DESIGN).lower()
        for value in (
            "a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4",
            "e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c",
            "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552",
        ):
            self.assertIn(value, design)


class BleGatewaySourceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.network_source = read(GATEWAY / "main" / "network_manager.c")
        cls.gateway_source = aggregate(GATEWAY, (".c", ".h", ".txt", ".defaults", ".projbuild"))
        cls.sdkconfig = read(GATEWAY / "sdkconfig.defaults")
        cls.kconfig = read(GATEWAY / "main" / "Kconfig.projbuild")
        cls.config_source = read(GATEWAY / "main" / "gateway_config.c")

    def test_displayed_uuid_matches_idf_little_endian_array(self) -> None:
        match = re.search(
            r"s_provisioning_service_uuid\s*\[\s*16\s*\]\s*=\s*\{(?P<body>.*?)\}",
            self.network_source,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(match, "missing 16-byte BLE provisioning service UUID")
        raw = bytes(int(token, 16) for token in re.findall(r"0x([0-9a-fA-F]{2})", match.group("body")))
        self.assertEqual(len(raw), 16)
        self.assertEqual(canonical_uuid_from_little_endian(raw), SERVICE_UUID)
        self.assertIn(SERVICE_UUID, self.network_source.lower())

    def test_gateway_uses_actual_name_prefix_and_dynamic_mac_suffix(self) -> None:
        self.assertIn(f'#define PROVISIONING_NAME_PREFIX "{DEVICE_PREFIX}"', self.network_source)
        self.assertIn("esp_wifi_get_mac(WIFI_IF_STA", self.network_source)
        self.assertRegex(self.network_source, r"mac\[3\].*mac\[4\].*mac\[5\]")

    def test_gateway_enforces_security1_with_pop(self) -> None:
        self.assertIn("WIFI_PROV_SECURITY_1", self.gateway_source)
        self.assertIn("wifi_prov_mgr_start_provisioning", self.gateway_source)
        self.assertIn("CONFIG_YAOCORE_PROV_POP", self.gateway_source)
        self.assertRegex(self.config_source, r"pop_len\s*<\s*[1-9]")
        self.assertIn("CONFIG_ESP_PROTOCOMM_SUPPORT_SECURITY_VERSION_1=y", self.sdkconfig)
        self.assertIn("CONFIG_ESP_PROTOCOMM_SUPPORT_SECURITY_VERSION_0=n", self.sdkconfig)
        self.assertIn("CONFIG_WIFI_PROV_BLE_FORCE_ENCRYPTION=n", self.sdkconfig)

    def test_ble_provisioning_lifecycle_is_complete(self) -> None:
        for token in (
            "wifi_prov_mgr_init",
            "wifi_prov_mgr_is_provisioned",
            "wifi_prov_mgr_set_app_info",
            "wifi_prov_scheme_ble_set_service_uuid",
            "wifi_prov_mgr_reset_sm_state_on_failure",
            "esp_wifi_restore",
            "WIFI_PROV_SCHEME_BLE_EVENT_HANDLER_FREE_BTDM",
        ):
            self.assertIn(token, self.gateway_source)
        self.assertIn("wifi_provisioning", read(GATEWAY / "main" / "CMakeLists.txt"))
        self.assertIn("CONFIG_BT_NIMBLE_ENABLED=y", self.sdkconfig)
        reset_block = self.network_source.split("esp_wifi_restore", 1)[1]
        self.assertRegex(reset_block, r"while\s*\(\s*gpio_get_level\(PROVISIONING_RESET_GPIO\)\s*==\s*0\s*\)")
        self.assertLess(reset_block.index("gpio_get_level"), reset_block.index("esp_restart"))

    def test_secure_identity_endpoint_is_registered_in_required_idf_order(self) -> None:
        create_at = self.network_source.index("wifi_prov_mgr_endpoint_create(PROVISIONING_IDENTITY_ENDPOINT)")
        start_at = self.network_source.index("wifi_prov_mgr_start_provisioning")
        register_at = self.network_source.index("wifi_prov_mgr_endpoint_register(PROVISIONING_IDENTITY_ENDPOINT")
        self.assertLess(create_at, start_at)
        self.assertLess(start_at, register_at)
        for token in ("get_identity", '"gatewayId"', '"gatewayName"', '"protocolVersion"'):
            self.assertIn(token, self.network_source)

    def test_app_acknowledges_final_status_before_ble_is_released(self) -> None:
        self.assertIn('PROVISIONING_FINISH_ENDPOINT "yaocore-done"', self.network_source)
        self.assertIn("wifi_prov_mgr_disable_auto_stop(1000)", self.network_source)
        self.assertIn("wifi_prov_mgr_stop_provisioning()", self.network_source)
        self.assertLess(
            self.network_source.index("wifi_prov_mgr_endpoint_create(PROVISIONING_FINISH_ENDPOINT)"),
            self.network_source.index("wifi_prov_mgr_start_provisioning"),
        )
        self.assertGreater(
            self.network_source.index("wifi_prov_mgr_endpoint_register(PROVISIONING_FINISH_ENDPOINT"),
            self.network_source.index("wifi_prov_mgr_start_provisioning"),
        )

    def test_identity_contract_is_machine_readable_and_fail_closed(self) -> None:
        request = json.loads(read(ROOT / "protocol" / "ble-enrollment-identity-request.schema.json"))
        response = json.loads(read(ROOT / "protocol" / "ble-enrollment-identity-response.schema.json"))
        self.assertFalse(request["additionalProperties"])
        self.assertFalse(response["additionalProperties"])
        self.assertEqual(request["properties"]["op"]["const"], "get_identity")
        self.assertEqual(response["properties"]["gatewayId"]["maxLength"], 63)
        self.assertEqual(
            response["properties"]["gatewayId"]["pattern"],
            "^[A-Za-z0-9][A-Za-z0-9_.:-]{0,62}$",
        )

    def test_compile_time_wifi_credentials_were_removed(self) -> None:
        for obsolete in ("YAOCORE_WIFI_SSID", "YAOCORE_WIFI_PASSWORD"):
            self.assertNotIn(obsolete, self.kconfig)
            self.assertNotIn(obsolete, self.config_source)


class HarmonyBleClientContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest = read(MANIFEST)
        cls.app_source = aggregate(APP_ETS, (".ets",))
        cls.app_lower = cls.app_source.lower()
        cls.ble_service = read(APP_ETS / "service" / "BleProvisioningService.ets")
        cls.ble_service_lower = cls.ble_service.lower()
        cls.device_page = read(APP_ETS / "pages" / "DevicePage.ets")
        cls.design_lower = read(DESIGN).lower()
        cls.sdkconfig = read(GATEWAY / "sdkconfig.defaults")

    def test_bluetooth_permission_is_declared_and_requested_at_runtime(self) -> None:
        self.assertIn("ohos.permission.ACCESS_BLUETOOTH", self.manifest)
        self.assertIn("ohos.permission.ACCESS_BLUETOOTH", self.app_source)
        self.assertIn("requestPermissionsFromUser", self.app_source)

    def test_client_scans_and_connects_using_the_repository_identity(self) -> None:
        self.assertIn(SERVICE_UUID, self.app_lower)
        self.assertIn(DEVICE_PREFIX.lower(), self.app_lower)
        for token in ("startBLEScan", "createGattClientDevice", "getServices"):
            self.assertIn(token, self.app_source)
        self.assertNotIn("0000ffff-0000-1000-8000-00805f9b34fb", self.ble_service_lower)

    def test_endpoints_are_mapped_from_0x2901_not_fixed_uuid_values(self) -> None:
        self.assertIn("readDescriptorValue", self.app_source)
        self.assertTrue(
            "00002901-0000-1000-8000-00805f9b34fb" in self.app_lower or "0x2901" in self.app_lower,
            "the client must identify endpoints through the 0x2901 descriptor",
        )
        for endpoint in ENDPOINTS:
            self.assertIn(endpoint, self.app_lower)
        for fragment in FIXED_ENDPOINT_UUID_FRAGMENTS:
            self.assertNotIn(
                fragment,
                self.app_lower,
                "the app must not depend on ESP-IDF's generated endpoint characteristic UUIDs",
            )

    def test_gatt_request_response_and_mtu_operations_exist(self) -> None:
        for token in (
            "writeCharacteristicValue",
            "readCharacteristicValue",
            "setBLEMtuSize",
        ):
            self.assertIn(token, self.app_source)
        self.assertRegex(self.app_source, r"setBLEMtuSize\s*\(\s*512\s*\)")
        self.assertIn("BLEMtuChange", self.ble_service)
        self.assertRegex(self.ble_service, r"MIN_PROVISIONING_MTU:\s*number\s*=\s*128")
        self.assertIn("negotiatedMtu", self.ble_service)
        self.assertIn("CONFIG_BT_NIMBLE_ATT_PREFERRED_MTU=256", self.sdkconfig)

    def test_protocol_capabilities_are_enforced_before_security_handshake(self) -> None:
        for token in ("v1.1", "wifi_scan", "no_sec", "no_pop", "yaocore", "2.0"):
            self.assertIn(token, self.ble_service_lower)
        self.assertRegex(self.ble_service, r"sec_ver\s*!==\s*1")

    def test_wifi_scan_is_implemented_paged_and_reachable_from_ui(self) -> None:
        for token in (
            "scanWiFiNetworks",
            "buildWiFiScanStart",
            "buildWiFiScanStatus",
            "buildWiFiScanResult",
        ):
            self.assertIn(token, self.ble_service)
        self.assertRegex(self.ble_service, r"pageSize\s*=\s*this\.negotiatedMtu")
        self.assertRegex(self.ble_service, r"start\s*\+=\s*pageSize")
        self.assertRegex(self.ble_service, r"Math\.min\s*\(\s*pageSize\s*,")
        self.assertRegex(self.device_page, r"private\s+async\s+handleBleWiFiScan\s*\(")
        self.assertRegex(self.device_page, r"bleViewModel\.scanWiFiNetworks\s*\(")
        self.assertRegex(self.device_page, r"wifiSsid\s*=\s*network\.ssid")
        self.assertNotIn("request.ssid.trim()", self.ble_service)

    def test_negative_rssi_decoder_preserves_low_32_bits(self) -> None:
        self.assertRegex(self.ble_service, r"let\s+low32\s*=\s*0")
        self.assertRegex(self.ble_service, r"shift\s*<\s*32")
        self.assertIn("0x100000000", self.ble_service_lower)

    def test_gatt_operations_have_timeouts_and_scans_are_cancellable(self) -> None:
        self.assertIn("withTimeout", self.ble_service)
        self.assertIn("OPERATION_TIMEOUT_MS", self.ble_service)
        self.assertIn("activeScanCancel", self.ble_service)
        self.assertRegex(self.ble_service, r"disconnect\s*\(\s*\)\s*:\s*void\s*\{\s*this\.cancelScan\s*\(")

    def test_successful_idf_ble_release_hands_off_to_lan_verification(self) -> None:
        self.assertIn("isExpectedProvisioningTransportRelease", self.ble_service)
        self.assertRegex(
            self.ble_service,
            r"stage\s*===\s*'wifi-status'.*verifiedIdentity\s*!==\s*undefined",
        )
        self.assertIn("BLE_LINK_LOST", self.ble_service)
        self.assertIn("GATT_READ_TIMEOUT:prov-config", self.ble_service)
        self.assertIn("this.progress(listener, 'lan-verify'", self.ble_service)
        self.assertIn("raw !== '[object Object]'", self.ble_service)
        self.assertIn("retryBleProvisioning", self.device_page)
        self.assertIn("this.bleProvisioning = false", self.device_page)
        self.assertIn("finishProvisioningIfSupported", self.ble_service)
        # A slow access point gets bounded exponential retries, but an offline
        # gateway must not leave the UI in an endless scanning loop.
        self.assertIn("PENDING_RETRY_MAX_MS", self.device_page)
        self.assertIn("pendingAutomaticRetryBlocked", self.device_page)
        self.assertIn("MAX_PENDING_AUTO_RETRIES", self.device_page)
        self.assertIn("局域网认证重试已停止", self.device_page)
        self.assertIn("retryPendingGatewayBinding(false)", self.device_page)

    def test_lan_fallback_scan_is_bounded_and_identity_specific(self) -> None:
        discovery = read(ROOT / "entry/src/main/ets/service/GatewayDiscoveryService.ets")
        repository = read(ROOT / "entry/src/main/ets/service/DeviceRepository.ets")
        self.assertIn("scanLanDevices(limit: number = 64)", discovery)
        self.assertIn("scanProvisionedGateway(expectedGatewayId", discovery)
        self.assertIn("probeCandidatesForGateway", discovery)
        self.assertIn("Math.min(batchSize, 8)", discovery)
        self.assertIn("probeCandidates(fallback, 8, true)", discovery)
        self.assertNotIn("scanLanDevices(limit: number = 254)", discovery)
        self.assertIn("gatewayDiscovery.scanProvisionedGateway(normalizedGatewayId)", repository)

    def test_client_contains_security1_primitives_and_no_security0_downgrade(self) -> None:
        for token in ("X25519", "SHA256", "CTR", "NoPadding"):
            self.assertIn(token.lower(), self.app_lower)
        self.assertNotIn("security0", self.app_lower)

    def test_ble_identity_is_correlated_with_authenticated_lan_gateway(self) -> None:
        self.assertRegex(self.ble_service, r"sendSecure\s*\(\s*'yaocore-id'")
        self.assertIn("expectedGatewayId", self.app_source)
        self.assertIn("gateway.gatewayId === normalizedGatewayId", self.app_source)
        self.assertIn("matched.gatewayId !== expectedGatewayId", self.device_page)
        self.assertIn("matched.secureTransport", self.device_page)
        self.assertRegex(self.device_page, r"Math\.min\s*\(\s*350\s*\*\s*Math\.pow\s*\(\s*2")
        self.assertNotRegex(self.device_page, r"delay\s*\(\s*1800\s*\)")

    def test_ble_flow_requires_command_key_before_network_enrollment(self) -> None:
        self.assertIn("ensureBleCommandKeyReady", self.device_page)
        self.assertIn("securityService.hasSessionSecret()", self.device_page)
        self.assertIn("saveInlineCommandKey", self.device_page)
        self.assertIn("securityService.setSessionSecret(secret)", self.device_page)
        self.assertIn("请先在当前配网卡片保存", self.device_page)

    def test_ui_separates_control_key_from_pop_as_two_required_steps(self) -> None:
        for label in (
            "步骤一：保存控制密钥",
            "步骤二：输入 PoP 完成 BLE 配网",
            "PoP · BLE 配网码",
            "更换控制密钥",
        ):
            self.assertIn(label, self.device_page)
        self.assertNotIn("网关配网 · 两步完成", self.device_page)
        self.assertIn("恢复已联网网关", self.device_page)
        self.assertIn("if (this.boundGatewayId.length === 0)", self.device_page)
        self.assertIn("editingCommandKey", self.device_page)
        self.assertRegex(
            self.device_page,
            r"if\s*\(\s*!this\.commandKeyReady\s*\|\|\s*this\.editingCommandKey\s*\)",
        )

    def test_design_requires_dynamic_mapping_and_fresh_session_after_transport_failure(self) -> None:
        for token in ("0x2901", "动态映射", "严格串行", "重新连接", "同一个连续密码流"):
            self.assertIn(token.lower(), self.design_lower)
        for endpoint in ENDPOINTS:
            self.assertIn(endpoint, self.design_lower)
        self.assertIn(SERVICE_UUID, self.design_lower)
        self.assertIn(DEVICE_PREFIX.lower(), self.design_lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
