#!/usr/bin/env python3
# YaoCore (爻构) - Open-source smart home system
# Copyright (c) 2026 Zhang HaoXuan
# Author: Zhang HaoXuan
# Created: 2026-07-17
# Source: https://github.com/Quirkybrain/YaoCore
# SPDX-License-Identifier: Apache-2.0

"""Static and interoperability checks for App-side authenticated LAN responses."""

from __future__ import annotations

import hashlib
import hmac
import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class AppResponseAuthenticationTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_public_response_vector_matches_protocol(self) -> None:
        document = json.loads(self.read("protocol/response-auth-test-vectors.json"))
        for vector in document["vectors"]:
            body_hash = hashlib.sha256(vector["body"].encode("utf-8")).hexdigest()
            canonical = (
                "YAOCORE-RESPONSE-V1\n"
                f"{vector['kind']}\n{vector['correlation']}\n{body_hash}"
            )
            signature = hmac.new(
                vector["secret"].encode("utf-8"),
                canonical.encode("utf-8"),
                hashlib.sha256,
            ).hexdigest()
            self.assertEqual(body_hash, vector["bodySha256"])
            # This fixture keeps the four separators visibly escaped; the
            # signed wire canonical form contains actual LF bytes.
            self.assertEqual(canonical, vector["canonical"].replace("\\n", "\n"))
            self.assertEqual(signature, vector["signature"])

    def test_security_service_implements_full_response_canonicalization(self) -> None:
        security = self.read("entry/src/main/ets/service/SecurityService.ets")
        for marker in (
            "createResponseChallenge",
            "randomHex(16)",
            "YAOCORE-RESPONSE-V1\\n${kind}\\n${expectedCorrelation}\\n${bodyHash}",
            "createMd('SHA256')",
            "constantTimeEqual",
            "left.length ^ right.length",
            "isLowerHex(signature, 64)",
        ):
            self.assertIn(marker, security)

    def test_discovery_request_vector_is_fresh_and_replay_resistant(self) -> None:
        document = json.loads(self.read("protocol/discovery-request-auth-test-vectors.json"))
        for vector in document["vectors"]:
            canonical = (
                "YAOCORE-DISCOVER-V2\n"
                f"{vector['challenge']}\n{vector['timestamp']}\n{vector['nonce']}\n"
                f"{vector['alg']}\n{vector['key_id']}"
            )
            signature = hmac.new(
                vector["secret"].encode("utf-8"),
                canonical.encode("utf-8"),
                hashlib.sha256,
            ).hexdigest()
            self.assertEqual(canonical, vector["canonical"].replace("\\n", "\n"))
            self.assertEqual(signature, vector["signature"])

        security = self.read("entry/src/main/ets/service/SecurityService.ets")
        self.assertIn("signDiscoveryRequest", security)
        self.assertIn("YAOCORE-DISCOVER-V2\\n${challenge}\\n${timestamp}\\n${nonce}", security)

    def test_discovery_is_challenged_and_authenticated_before_parsing(self) -> None:
        discovery = self.read("entry/src/main/ets/service/GatewayDiscoveryService.ets")
        probe = discovery[discovery.index("private async probeHost"):discovery.index("private mergeResults")]
        self.assertIn("'X-YaoCore-Challenge': challenge", probe)
        self.assertIn("'X-YaoCore-Request-Timestamp': requestAuthentication.timestamp", probe)
        self.assertIn("'X-YaoCore-Request-Nonce': requestAuthentication.nonce", probe)
        verify_at = probe.index("isAuthenticatedResponse(response.header, challenge, raw)")
        parse_at = probe.index("JSON.parse(raw)")
        self.assertLess(verify_at, parse_at)
        for header in (
            "X-YaoCore-Response-Alg",
            "X-YaoCore-Key-Id",
            "X-YaoCore-Response-Correlation",
            "X-YaoCore-Response-Sign",
        ):
            self.assertIn(header, discovery)

    def test_control_ack_is_authenticated_and_strictly_correlated(self) -> None:
        local = self.read("entry/src/main/ets/service/LocalGatewayService.ets")
        send_once = local[local.index("private async sendOnce"):local.index("private parseAck")]
        self.assertIn("`${packet.request_id}:${packet.seq}`", send_once)
        self.assertLess(
            send_once.index("isAuthenticatedResponse(response.header, 'control', correlation, raw)"),
            send_once.index("parseAck(raw"),
        )
        self.assertIn("if (ackRequestId !== packet.request_id)", local)
        self.assertIn("if (ack.seq !== packet.seq)", local)
        self.assertIn("const executed = resultCode === 0;", local)
        self.assertNotIn("resultCode === undefined && ack.success === true", local)

    def test_freshness_and_online_contracts_are_wired(self) -> None:
        date_time = self.read("entry/src/main/ets/common/utils/DateTimeUtil.ets")
        network = self.read("entry/src/main/ets/service/NetworkService.ets")
        cloud = self.read("entry/src/main/ets/service/CloudService.ets")
        self.assertIn("parseUtcToMillis", date_time)
        self.assertIn("DateTimeUtil.parseUtcToMillis", network)
        self.assertIn("eventMs + 2000 >= notBeforeMs", network)
        for online_property in (
            "Door_01_Online",
            "Light_01_Online",
            "Sensor_01_Online",
            "AC_01_Online",
        ):
            self.assertIn(online_property, cloud)


if __name__ == "__main__":
    unittest.main()
