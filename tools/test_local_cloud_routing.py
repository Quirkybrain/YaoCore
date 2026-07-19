#!/usr/bin/env python3
# YaoCore (爻构) - Open-source smart home system
# Copyright (c) 2026 Zhang HaoXuan
# Author: Zhang HaoXuan
# Created: 2026-07-17
# Source: https://github.com/Quirkybrain/YaoCore
# SPDX-License-Identifier: Apache-2.0

"""Static safety checks for LAN/cloud routing and gateway isolation."""

from __future__ import annotations

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class LocalCloudRoutingTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_binding_authenticates_route_and_each_control_verifies_signed_ack(self) -> None:
        network = self.read("entry/src/main/ets/service/NetworkService.ets")
        bind = network[network.index("async bindGateway"):network.index("async unbindGateway")]
        control = network[network.index("async controlDevice"):network.index("getLastResult")]
        send_at = control.index("localGatewayService.send(wireCommand)")
        cloud_at = control.index("cloudService.send(wireCommand)")
        self.assertLess(send_at, cloud_at)
        self.assertIn("localGatewayService.testConnection", bind)
        self.assertIn("probe.success", bind)
        self.assertIn("probe.confirmed", bind)
        self.assertNotIn("probeConfiguredGateway", control)
        self.assertIn("confirmLocalResult", control)
        self.assertIn("if (!localReachable)", control)
        self.assertIn("this.setLocalReachability(false)", control)

    def test_only_a_potentially_sent_post_blocks_cloud_fallback(self) -> None:
        network = self.read("entry/src/main/ets/service/NetworkService.ets")
        local = self.read("entry/src/main/ets/service/LocalGatewayService.ets")
        control = network[network.index("async controlDevice"):network.index("getLastResult")]
        ambiguous = control[control.index("if (localResult.deliveryAttempted === true)"):
                            control.index("构包或本地传输前置条件失败")]
        self.assertIn("LOCAL_DELIVERY_AMBIGUOUS", ambiguous)
        self.assertIn("不自动改走云端", ambiguous)
        self.assertNotIn("cloudService.send", ambiguous)
        self.assertIn("deliveryAttempted: true", local)
        preflight = local[local.index("private async sendTo("):local.index("let lastResult")]
        self.assertNotIn("deliveryAttempted: true", preflight)

    def test_monitor_writes_reachability_back_to_route_decision(self) -> None:
        repository = self.read("entry/src/main/ets/service/DeviceRepository.ets")
        refresh = repository[repository.index("async refreshFromAvailableRoutes"):repository.index("startMonitoring")]
        self.assertIn("networkService.setLocalReachability", refresh)
        network = self.read("entry/src/main/ets/service/NetworkService.ets")
        setter = network[network.index("setLocalReachability"):network.index("private applyLocalRoute")]
        self.assertIn("this.isLocalAvailable = available", setter)
        self.assertIn("this.discoveryService.setLocalAvailable(available)", setter)

    def test_commands_cannot_cross_bound_gateway_identity(self) -> None:
        repository = self.read("entry/src/main/ets/service/DeviceRepository.ets")
        validate = repository[repository.index("private validateCommand"):repository.index("private normalizeCommand")]
        self.assertIn("target.gatewayId.trim() !== boundGatewayId", validate)
        self.assertIn("DEVICE_GATEWAY_MISMATCH", validate)
        bind = repository[repository.index("async bindGateway"):repository.index("async removeDevice")]
        self.assertIn("previousGatewayId !== gateway.gatewayId", bind)
        self.assertIn("markGatewayDevicesOffline(previousGatewayId)", bind)
        self.assertIn("await this.persistDevices()", bind)


if __name__ == "__main__":
    unittest.main()
