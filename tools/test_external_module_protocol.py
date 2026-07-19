# YaoCore (爻构) - external module contract tests
# Copyright (c) 2026 Zhang HaoXuan
# SPDX-License-Identifier: Apache-2.0

import hashlib
import hmac
import json
import pathlib
import unittest

from derive_module_key import derive


ROOT = pathlib.Path(__file__).resolve().parents[1]
MAIN = ROOT / "gateway" / "esp32s3m" / "main"
PROTOCOL = ROOT / "protocol"


class ExternalModuleProtocolTests(unittest.TestCase):
    def read_main(self, name: str) -> str:
        return (MAIN / name).read_text(encoding="utf-8")

    def test_all_module_contract_files_are_valid_json(self):
        names = (
            "module-register.schema.json",
            "module-state.schema.json",
            "module-heartbeat.schema.json",
            "module-command.schema.json",
            "module-command-ack.schema.json",
            "module-hmac-test-vector.json",
        )
        for name in names:
            with self.subTest(name=name):
                self.assertIsInstance(json.loads((PROTOCOL / name).read_text(encoding="utf-8")), dict)

    def test_per_module_hmac_vector(self):
        vector = json.loads((PROTOCOL / "module-hmac-test-vector.json").read_text(encoding="utf-8"))
        context = f"YAOCORE-MODULE-KEY-V1\n{vector['moduleId']}".encode()
        module_key = hmac.new(vector["masterSecret"].encode(), context, hashlib.sha256).digest()
        self.assertEqual(vector["derivedModuleKeyHex"], module_key.hex())
        self.assertEqual(vector["derivedModuleKeyHex"], derive(vector["masterSecret"], vector["moduleId"]))
        self.assertEqual(vector["bodySha256"], hashlib.sha256(vector["body"].encode()).hexdigest())
        signature = hmac.new(module_key, vector["canonical"].encode(), hashlib.sha256).hexdigest()
        self.assertEqual(vector["signature"], signature)

    def test_gateway_exposes_authenticated_southbound_endpoints(self):
        local = self.read_main("local_server.c")
        security = self.read_main("gateway_security.c")
        for endpoint in ("/module/v1/register", "/module/v1/state", "/module/v1/heartbeat"):
            self.assertIn(endpoint, local)
        for kind in ("register", "state", "heartbeat", "command", "command_ack", "gateway_ack"):
            self.assertIn(f'"{kind}"', security)
        self.assertIn("YAOCORE-MODULE-KEY-V1", security)
        self.assertIn("constant_time_equal", security)

    def test_registration_is_peer_bound_and_identity_safe(self):
        local = self.read_main("local_server.c")
        transport = self.read_main("external_module.c")
        router = self.read_main("device_router.c")
        self.assertIn("peer_ipv4(req, peer)", local)
        self.assertIn("module_identifier(registration.module_id)", local)
        self.assertIn("module_last_sequence_locked", transport)
        self.assertIn("external_module_unregister", local)
        self.assertIn("!device->external", router)

    def test_command_requires_authenticated_final_state_before_router_update(self):
        transport = self.read_main("external_module.c")
        router = self.read_main("device_router.c")
        self.assertIn('verify_module_message("command_ack"', transport)
        self.assertIn("parse_reported_state", transport)
        execute_at = router.index("external_module_execute(command")
        update_at = router.index("apply_external_patch(device, &reported)", execute_at)
        self.assertLess(execute_at, update_at)
        self.assertIn("MODULE_COMMAND_UNCONFIRMED", router)

    def test_sensor_rules_are_capability_based_and_asynchronous(self):
        automation = self.read_main("automation_engine.c")
        self.assertIn("xQueueCreate", automation)
        self.assertIn("xQueueSend", automation)
        self.assertIn("sensor.has_presence", automation)
        self.assertIn("sensor.has_environment", automation)
        self.assertNotIn('!strcmp(sensor_state->device_id, "Presence_01")', automation)

    def test_dynamic_cloud_inventory_preserves_unique_devices_and_metadata(self):
        cloud = self.read_main("cloud_iotda.c")
        for marker in ("device_id", "device_name", "room_name", "device_type", "protocol", "module_id"):
            self.assertIn(f'"{marker}"', cloud)
        self.assertIn('!strcmp(d->device_id, "Light_01")', cloud)
        self.assertIn("DeviceInventoryJson", cloud)

    def test_module_telemetry_is_authenticated_and_does_not_block_command_tcp(self):
        """Heartbeat/state telemetry uses signed UDP; physical command ACK stays on TCP."""
        local = self.read_main("local_server.c")
        r4 = (ROOT / "devices" / "arduino_rgb_light" /
              "YaoCoreRgbLightUnoR4WiFi" /
              "YaoCoreRgbLightUnoR4WiFi.ino").read_text(encoding="utf-8")
        for marker in (
            '"YAOCORE_MODULE_EVENT"',
            '"YAOCORE_MODULE_ACK"',
            "gateway_security_verify_module_message(kind",
            "send_module_udp_ack",
            'xTaskCreate(udp_task, "yaocore_udp", 8192',
        ):
            self.assertIn(marker, local)
        for marker in (
            "sendStateDatagram",
            "sendHeartbeatDatagram",
            "pollGatewayDatagram",
            "udpAckAccepted",
            "sendHttp(client, 200, response, true)",
        ):
            self.assertIn(marker, r4)
        self.assertNotIn("sendStateReport();", r4)
        self.assertNotIn("sendHeartbeat();", r4)


if __name__ == "__main__":
    unittest.main()
