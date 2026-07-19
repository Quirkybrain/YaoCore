#!/usr/bin/env python3
# YaoCore (爻构) - Open-source smart home system
# Copyright (c) 2026 Zhang HaoXuan
# Author: Zhang HaoXuan
# Created: 2026-07-17
# Source: https://github.com/Quirkybrain/YaoCore
# SPDX-License-Identifier: Apache-2.0

"""Static safety contracts for gateway-bound scene execution."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ETS = ROOT / "entry" / "src" / "main" / "ets"


def read(relative: str) -> str:
    return (ETS / relative).read_text(encoding="utf-8", errors="replace")


class SceneGatewayClosureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.model = read("model/SceneModel.ets")
        cls.service = read("service/SceneService.ets")
        cls.view_model = read("viewmodel/SceneViewModel.ets")
        cls.page = read("pages/ScenePage.ets")

    def test_actions_persist_gateway_identity_and_legacy_actions_fail_closed(self) -> None:
        self.assertIn("gatewayId?: string", self.model)
        self.assertIn("bindDraftActions", self.service)
        self.assertIn("actionGatewayId.length === 0", self.service)
        self.assertIn("SCENE_GATEWAY_MISMATCH", self.service)
        self.assertLess(
            self.service.index("isActionBoundToCurrentGateway(action)"),
            self.service.index("repository.preflightControl"),
        )

    def test_editor_and_presets_only_use_current_gateway(self) -> None:
        self.assertIn("gatewayId.trim() === boundGatewayId", self.view_model)
        self.assertIn("gatewayId.trim() === boundGatewayId", self.service)
        self.assertIn("gatewayId: device.gatewayId", self.page)
        self.assertIn("current.gatewayId === action.gatewayId", self.page)
        self.assertIn("属于旧网关，请删除该动作并从当前网关重新选择设备", self.page)
        self.assertIn("旧场景，需编辑后重新保存", self.page)

    def test_partial_failure_summary_is_explicit_and_preserves_result_metadata(self) -> None:
        for token in (
            "已完成 ${completed}/${total} 项",
            "第 ${failedIndex + 1} 项失败",
            "后续 ${remaining} 项未执行",
            "已执行动作未自动回滚",
            "route: failed.route",
            "errorCode: failed.errorCode",
            "requestId: failed.requestId",
            "reportedState: failed.reportedState",
        ):
            self.assertIn(token, self.service)


if __name__ == "__main__":
    unittest.main(verbosity=2)
