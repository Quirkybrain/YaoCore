#!/usr/bin/env python3
# YaoCore (爻构) - Open-source smart home system
# Copyright (c) 2026 Zhang HaoXuan
# Author: Zhang HaoXuan
# Created: 2026-07-17
# Source: https://github.com/Quirkybrain/YaoCore
# SPDX-License-Identifier: Apache-2.0

"""Standard-library tests for the YaoCore DEVELOPMENT contract simulator."""

from __future__ import annotations

import copy
import json
import threading
import unittest
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from tools.gateway_contract_server import (
    DEFAULT_KEY_ID,
    PUBLIC_TEST_SECRET,
    RESULT_BAD_SIGNATURE,
    RESULT_INVALID_REQUEST,
    RESULT_REPLAY,
    RESULT_TIMESTAMP_REJECTED,
    RESULT_UNSUPPORTED_COMMAND,
    RESULT_UNSUPPORTED_SECURITY,
    GatewayContractState,
    NonceReplayCache,
    canonicalize_control_request,
    compute_signature,
    create_server,
    format_timestamp,
    sign_packet,
)


ROOT = Path(__file__).resolve().parents[1]
PROTOCOL_DIR = ROOT / "protocol"
PROFILE_PATH = ROOT / "cloud" / "iotda" / "product-profile.json"
FIXED_NOW = datetime(2026, 7, 14, 8, 0, 0, tzinfo=timezone.utc)


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as source:
        return json.load(source)


class ProtocolAssetTests(unittest.TestCase):
    def test_all_json_assets_are_valid(self) -> None:
        expected_files = [
            "discover-response.schema.json",
            "local-control-request.schema.json",
            "local-control-ack.schema.json",
            "cloud-command.schema.json",
            "state-report.schema.json",
            "hmac-sha256-test-vectors.json",
        ]
        for filename in expected_files:
            with self.subTest(filename=filename):
                self.assertIsInstance(load_json(PROTOCOL_DIR / filename), dict)
        self.assertIsInstance(load_json(PROFILE_PATH), dict)

    def test_schemas_use_json_schema_2020_12(self) -> None:
        for path in sorted(PROTOCOL_DIR.glob("*.schema.json")):
            with self.subTest(path=path.name):
                document = load_json(path)
                self.assertEqual(
                    document.get("$schema"),
                    "https://json-schema.org/draft/2020-12/schema",
                )

        local_schema = load_json(PROTOCOL_DIR / "local-control-request.schema.json")
        self.assertEqual(local_schema["properties"]["key_id"]["const"], "app-key-v1")
        discover_schema = load_json(PROTOCOL_DIR / "discover-response.schema.json")
        self.assertEqual(
            discover_schema["properties"]["security"]["properties"]["keyId"]["const"],
            "app-key-v1",
        )
        ack_schema = load_json(PROTOCOL_DIR / "local-control-ack.schema.json")
        self.assertEqual(
            ack_schema["properties"]["idempotent_replay"]["type"],
            "boolean",
        )

    def test_hmac_vectors_match_canonical_contract(self) -> None:
        document = load_json(PROTOCOL_DIR / "hmac-sha256-test-vectors.json")
        self.assertGreaterEqual(len(document["vectors"]), 4)
        for vector in document["vectors"]:
            with self.subTest(vector=vector["name"]):
                request = vector["request"]
                self.assertEqual(
                    canonicalize_control_request(request),
                    vector["canonical"],
                )
                self.assertEqual(
                    compute_signature(request, vector["secret"]),
                    vector["expectedSign"],
                )
                self.assertEqual(request["sign"], vector["expectedSign"])

    def test_integer_and_integer_valued_float_canonicalize_identically(self) -> None:
        packet = {
            "request_id": "req-number-normalization",
            "cmd_id": 2001,
            "seq": 1,
            "target": "AC_01",
            "payload": {"action": "SET_TARGET_TEMPERATURE", "value": 24},
            "timestamp": format_timestamp(FIXED_NOW),
            "nonce": "numbernorm01",
            "alg": "HMAC-SHA256",
            "key_id": DEFAULT_KEY_ID,
        }
        floating = copy.deepcopy(packet)
        floating["payload"]["value"] = 24.0
        self.assertEqual(
            canonicalize_control_request(packet),
            canonicalize_control_request(floating),
        )

    def test_iotda_profile_contains_core_properties_and_commands(self) -> None:
        profile = load_json(PROFILE_PATH)
        services = profile["services"]
        self.assertEqual(len(services), 1)
        service = services[0]
        self.assertEqual(service["serviceId"], "SmartHomeService")
        properties = {item["propertyName"] for item in service["properties"]}
        self.assertTrue(
            {
                "Door_01_Status",
                "Light_01_Status",
                "Room_01_Temperature",
                "Room_01_Humidity",
                "AC_01_Status",
                "AC_01_TargetTemp",
            }.issubset(properties)
        )
        commands = {item["commandName"] for item in service["commands"]}
        self.assertEqual(commands, {"SetDeviceStatus"})

        command = service["commands"][0]
        command_paras = {item["paraName"]: item for item in command["paras"]}
        self.assertEqual(
            set(command_paras),
            {
                "RequestId",
                "CmdId",
                "Seq",
                "TargetDevice",
                "Action",
                "Value",
                "Timestamp",
                "Nonce",
                "Alg",
                "KeyId",
                "Sign",
            },
        )
        self.assertEqual(command_paras["Value"]["dataType"], "string")
        self.assertEqual(command_paras["KeyId"]["enumList"], ["app-key-v1"])

        cloud_schema = load_json(PROTOCOL_DIR / "cloud-command.schema.json")
        schema_paras = cloud_schema["properties"]["paras"]
        self.assertNotIn("object_device_id", schema_paras["properties"])
        self.assertEqual(cloud_schema["properties"]["command_name"]["const"], "SetDeviceStatus")
        self.assertEqual(schema_paras["properties"]["Value"]["type"], "string")

        state_schema = load_json(PROTOCOL_DIR / "state-report.schema.json")
        reported_properties = set(state_schema["$defs"]["properties"]["required"])
        self.assertTrue(reported_properties.issubset(properties))

    def test_nonce_cache_retains_entries_for_five_minutes(self) -> None:
        monotonic = [1000.0]
        cache = NonceReplayCache(300, lambda: monotonic[0])
        identity = (
            "app-key-v1",
            "ttl-nonce",
            "req-cache-ttl",
            1,
            "0" * 64,
            "canonical-request",
        )
        acknowledgement = {
            "request_id": "req-cache-ttl",
            "seq": 1,
            "result_code": 0,
            "message": "ok",
            "server_time": "20260714T080000Z",
        }
        self.assertEqual(
            cache.lookup("app-key-v1", "ttl-nonce", identity)[0],
            "miss",
        )
        cache.store("app-key-v1", "ttl-nonce", identity, 200, acknowledgement)
        monotonic[0] += 299
        replay_kind, http_status, cached_ack = cache.lookup(
            "app-key-v1",
            "ttl-nonce",
            identity,
        )
        self.assertEqual(replay_kind, "exact")
        self.assertEqual(http_status, 200)
        self.assertEqual(cached_ack, acknowledgement)
        conflicting_identity = identity[:-1] + ("different-canonical-request",)
        self.assertEqual(
            cache.lookup("app-key-v1", "ttl-nonce", conflicting_identity)[0],
            "conflict",
        )
        monotonic[0] += 2
        self.assertEqual(
            cache.lookup("app-key-v1", "ttl-nonce", identity)[0],
            "miss",
        )

    def test_cached_exact_retry_outlives_timestamp_freshness_window(self) -> None:
        wall_clock = [FIXED_NOW]
        monotonic = [1000.0]
        state = GatewayContractState(
            secret=PUBLIC_TEST_SECRET,
            key_id=DEFAULT_KEY_ID,
            clock=lambda: wall_clock[0],
            monotonic_clock=lambda: monotonic[0],
            log_requests=False,
        )
        packet = sign_packet(
            {
                "request_id": "req-lost-ack",
                "cmd_id": 2001,
                "seq": 17,
                "target": "gateway_01",
                "payload": {"action": "PING"},
                "timestamp": format_timestamp(FIXED_NOW),
                "nonce": "lost-ack-nonce",
                "alg": "HMAC-SHA256",
                "key_id": DEFAULT_KEY_ID,
            },
            PUBLIC_TEST_SECRET,
        )

        status, first_ack = state.process_control(packet)
        self.assertEqual(status, 200)
        wall_clock[0] += timedelta(seconds=121)
        monotonic[0] += 121

        status, replay_ack = state.process_control(packet)
        self.assertEqual(status, 200)
        self.assertIs(replay_ack["idempotent_replay"], True)
        del replay_ack["idempotent_replay"]
        self.assertEqual(replay_ack, first_ack)
        self.assertEqual(state.execution_count(packet["request_id"]), 1)


class GatewayContractHTTPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.state = GatewayContractState(
            secret=PUBLIC_TEST_SECRET,
            key_id=DEFAULT_KEY_ID,
            clock=lambda: FIXED_NOW,
            log_requests=False,
        )
        cls.server = create_server("127.0.0.1", 0, cls.state)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base_url = f"http://127.0.0.1:{cls.server.server_address[1]}"
        cls.sequence = 20000

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=2)

    @classmethod
    def next_packet(
        cls,
        target: str,
        action: str,
        *,
        value: Any = None,
        include_value: bool = False,
        nonce: str | None = None,
        timestamp: datetime = FIXED_NOW,
    ) -> dict[str, Any]:
        cls.sequence += 1
        payload: dict[str, Any] = {"action": action}
        if include_value:
            payload["value"] = value
        packet = {
            "request_id": f"req-http-{cls.sequence}",
            "cmd_id": 2001,
            "seq": cls.sequence,
            "target": target,
            "payload": payload,
            "timestamp": format_timestamp(timestamp),
            "nonce": nonce or f"nonce{cls.sequence}",
            "alg": "HMAC-SHA256",
            "key_id": DEFAULT_KEY_ID,
        }
        return sign_packet(packet, PUBLIC_TEST_SECRET)

    @classmethod
    def request_json(
        cls,
        method: str,
        path: str,
        document: Any | None = None,
    ) -> tuple[int, dict[str, Any], dict[str, str]]:
        body = None
        headers: dict[str, str] = {}
        if document is not None:
            body = json.dumps(
                document,
                ensure_ascii=False,
                separators=(",", ":"),
                allow_nan=False,
            ).encode("utf-8")
            headers["Content-Type"] = "application/json"
        return cls.request_raw(method, path, body, headers)

    @classmethod
    def request_raw(
        cls,
        method: str,
        path: str,
        body: bytes | None,
        headers: dict[str, str] | None = None,
    ) -> tuple[int, dict[str, Any], dict[str, str]]:
        request = urllib.request.Request(
            cls.base_url + path,
            data=body,
            headers=headers or {},
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=2) as response:
                response_body = response.read()
                return (
                    response.status,
                    json.loads(response_body.decode("utf-8")),
                    dict(response.headers.items()),
                )
        except urllib.error.HTTPError as error:
            try:
                response_body = error.read()
                return (
                    error.code,
                    json.loads(response_body.decode("utf-8")),
                    dict(error.headers.items()),
                )
            finally:
                error.close()

    def test_discover_and_health_are_explicitly_simulated(self) -> None:
        status, document, headers = self.request_json("GET", "/discover")
        self.assertEqual(status, 200)
        self.assertEqual(document["protocolVersion"], "2.0")
        self.assertEqual(document["serviceId"], "SmartHomeService")
        self.assertEqual(len(document["devices"]), 4)
        self.assertEqual(headers["X-YaoCore-Simulator"], "DEV-ONLY")

        status, health, _ = self.request_json("GET", "/health")
        self.assertEqual(status, 200)
        self.assertIs(health["simulator"], True)
        self.assertEqual(health["status"], "DEV_SIMULATOR_ONLY")

    def test_valid_control_echoes_request_and_returns_reported_state(self) -> None:
        packet = self.next_packet(
            "Light_01",
            "SET_BRIGHTNESS",
            value=37,
            include_value=True,
        )
        status, acknowledgement, _ = self.request_json("POST", "/control", packet)
        self.assertEqual(status, 200)
        self.assertEqual(acknowledgement["request_id"], packet["request_id"])
        self.assertEqual(acknowledgement["seq"], packet["seq"])
        self.assertEqual(acknowledgement["result_code"], 0)
        self.assertEqual(acknowledgement["reported_state"]["brightness"], 37)
        self.assertIs(acknowledgement["reported_state"]["power"], True)

        _, discovery, _ = self.request_json("GET", "/discover")
        light = next(item for item in discovery["devices"] if item["deviceId"] == "Light_01")
        self.assertEqual(light["brightness"], 37)

    def test_unicode_string_value_and_ping(self) -> None:
        mode_packet = self.next_packet(
            "AC_01",
            "SET_MODE",
            value="制冷",
            include_value=True,
        )
        status, acknowledgement, _ = self.request_json("POST", "/control", mode_packet)
        self.assertEqual(status, 200)
        self.assertEqual(acknowledgement["reported_state"]["mode"], "制冷")

        ping_packet = self.next_packet("gateway_01", "PING")
        status, acknowledgement, _ = self.request_json("POST", "/control", ping_packet)
        self.assertEqual(status, 200)
        self.assertEqual(acknowledgement["result_code"], 0)
        self.assertEqual(acknowledgement["reported_state"]["gatewayId"], "gateway_01")

    def test_bad_signature_does_not_consume_nonce(self) -> None:
        packet = self.next_packet("Door_01", "OPEN", nonce="bad-sign-nonce")
        bad_packet = copy.deepcopy(packet)
        bad_packet["sign"] = "0" * 64
        status, acknowledgement, _ = self.request_json("POST", "/control", bad_packet)
        self.assertEqual(status, 401)
        self.assertEqual(acknowledgement["result_code"], RESULT_BAD_SIGNATURE)

        status, acknowledgement, _ = self.request_json("POST", "/control", packet)
        self.assertEqual(status, 200)
        self.assertEqual(acknowledgement["result_code"], 0)

    def test_stale_timestamp_does_not_consume_nonce(self) -> None:
        stale = self.next_packet(
            "Door_01",
            "CLOSE",
            nonce="stale-time-nonce",
            timestamp=FIXED_NOW - timedelta(seconds=121),
        )
        status, acknowledgement, _ = self.request_json("POST", "/control", stale)
        self.assertEqual(status, 401)
        self.assertEqual(acknowledgement["result_code"], RESULT_TIMESTAMP_REJECTED)

        corrected = copy.deepcopy(stale)
        corrected["timestamp"] = format_timestamp(FIXED_NOW)
        corrected["sign"] = compute_signature(corrected, PUBLIC_TEST_SECRET)
        status, acknowledgement, _ = self.request_json("POST", "/control", corrected)
        self.assertEqual(status, 200)
        self.assertEqual(acknowledgement["result_code"], 0)

    def test_exact_authenticated_retransmission_returns_cached_ack(self) -> None:
        packet = self.next_packet("gateway_01", "PING", nonce="replay-nonce-01")
        status, first_ack, _ = self.request_json("POST", "/control", packet)
        self.assertEqual(status, 200)
        self.assertEqual(first_ack["result_code"], 0)
        self.assertNotIn("idempotent_replay", first_ack)
        self.assertEqual(self.state.execution_count(packet["request_id"]), 1)

        for retry_number in (1, 2):
            with self.subTest(retry_number=retry_number):
                status, replay_ack, _ = self.request_json("POST", "/control", packet)
                self.assertEqual(status, 200)
                self.assertEqual(replay_ack["result_code"], 0)
                self.assertIs(replay_ack["idempotent_replay"], True)
                replay_core = copy.deepcopy(replay_ack)
                del replay_core["idempotent_replay"]
                self.assertEqual(replay_core, first_ack)
                self.assertEqual(self.state.execution_count(packet["request_id"]), 1)

    def test_same_nonce_with_changed_bound_data_is_rejected(self) -> None:
        packet = self.next_packet("gateway_01", "PING", nonce="conflict-nonce-01")
        status, acknowledgement, _ = self.request_json("POST", "/control", packet)
        self.assertEqual(status, 200)
        self.assertEqual(acknowledgement["result_code"], 0)

        changed_field = copy.deepcopy(packet)
        changed_field["payload"] = {"action": "BOARD_LED_ON", "value": True}
        status, acknowledgement, _ = self.request_json(
            "POST",
            "/control",
            changed_field,
        )
        self.assertEqual(status, 409)
        self.assertEqual(acknowledgement["result_code"], RESULT_REPLAY)

        changed_sign = copy.deepcopy(packet)
        replacement = "0" if changed_sign["sign"][0] != "0" else "1"
        changed_sign["sign"] = replacement + changed_sign["sign"][1:]
        status, acknowledgement, _ = self.request_json(
            "POST",
            "/control",
            changed_sign,
        )
        self.assertEqual(status, 409)
        self.assertEqual(acknowledgement["result_code"], RESULT_REPLAY)
        self.assertEqual(self.state.execution_count(packet["request_id"]), 1)

    def test_unknown_key_is_rejected(self) -> None:
        packet = self.next_packet("gateway_01", "PING")
        packet["key_id"] = "unknown-key"
        packet["sign"] = compute_signature(packet, PUBLIC_TEST_SECRET)
        status, acknowledgement, _ = self.request_json("POST", "/control", packet)
        self.assertEqual(status, 401)
        self.assertEqual(acknowledgement["result_code"], RESULT_UNSUPPORTED_SECURITY)

    def test_authenticated_but_unsupported_command_is_not_confirmed(self) -> None:
        packet = self.next_packet(
            "Sensor_01",
            "ON",
            nonce="unsupported-nonce",
        )
        status, first_ack, _ = self.request_json("POST", "/control", packet)
        self.assertEqual(status, 422)
        self.assertEqual(first_ack["result_code"], RESULT_UNSUPPORTED_COMMAND)
        self.assertNotIn("reported_state", first_ack)
        self.assertEqual(self.state.execution_count(packet["request_id"]), 1)

        status, replay_ack, _ = self.request_json("POST", "/control", packet)
        self.assertEqual(status, 422)
        self.assertEqual(replay_ack["result_code"], RESULT_UNSUPPORTED_COMMAND)
        self.assertIs(replay_ack["idempotent_replay"], True)
        replay_core = copy.deepcopy(replay_ack)
        del replay_core["idempotent_replay"]
        self.assertEqual(replay_core, first_ack)
        self.assertEqual(self.state.execution_count(packet["request_id"]), 1)

    def test_duplicate_json_keys_are_rejected(self) -> None:
        raw = (
            b'{"request_id":"duplicate-key","request_id":"second",'
            b'"cmd_id":2001,"seq":1,"target":"gateway_01",'
            b'"payload":{"action":"PING"},"timestamp":"20260714T080000Z",'
            b'"nonce":"duplicate01","alg":"HMAC-SHA256",'
            b'"key_id":"app-key-v1","sign":"' + b"0" * 64 + b'"}'
        )
        status, acknowledgement, _ = self.request_raw(
            "POST",
            "/control",
            raw,
            {"Content-Type": "application/json"},
        )
        self.assertEqual(status, 400)
        self.assertEqual(acknowledgement["result_code"], RESULT_INVALID_REQUEST)


if __name__ == "__main__":
    unittest.main(verbosity=2)
