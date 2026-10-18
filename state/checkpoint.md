# Checkpoint CP-014 — 设备验收包就绪，等待用户执行

```text
Checkpoint ID: CP-014
时间: 2026-10-19
Repository revision / working-tree state: feat/yaocore-app @ 3c4fb11（干净；无活动交接）
Current Stage: acceptance（设备验收，用户执行）
Target Stage: release（准备完成；发布未授权）
Workflow and Execution Modes: STANDARD / GATED_AUTO
Active Task: 无
```

## 本轮完成

| 工作 | 结果 | 证据 |
|---|---|---|
| 决策登记 | 设备验收优先；**不使用原仓库**（不 fetch/push/PR/MR）；本地身份 `com.example.yaocore` | `938867e` |
| 设备验收包 | 31 用例 `DA-001..DA-031`（BLK-01..08 + U-01..U-12 + 26 FR/NFR）；计划/CSV/缺陷模板/证据目录 | `7b0ab0c` |
| 校验工具 | `tools/acceptance/validate_device_evidence.py`：模板/结果/秘密扫描/self-test 18/18 | `7b0ab0c` |
| 合并 | `51ac14c` + 证据 `3c4fb11`；host 697/697、layering 0、模板 31/31 NOT_RUN | wp-122 |

## 设备验收边界

- 设备测试**未执行**（当前环境 `hdc` 无目标）；不得宣称设备 PASS。
- 需要用户：签名证书/Profile、真机、网关/固件、网络、云 token、硬件。
- `DA-002`（覆盖升级）仅在身份 A 下执行；B/C 记 `BLOCKED`（不适用）。
- 证据必须脱敏（Wi-Fi 密码/PoP/HMAC key/IAM token/私钥/完整邀请凭据）。

## 待用户决定

1. 身份/版本/许可证 A/B/C（影响 DA-002 与安装/升级）。
2. GAP-AC-01..03（视觉/交互断言）。
3. P-HMAC/TLS 范围、B-09（API 14/混淆裁剪）、残余风险签核。
4. 签名与设备执行；发布/远端仍不授权。

## Next ready action

1. 用户按 `artifacts/75-device-acceptance/device-acceptance-plan.md` 准备签名 HAP 与设备。
2. 执行 DA-001..DA-031，回填 `device-evidence-template.csv`，证据放 `evidence/<case_id>/`。
3. 运行 `python3 tools/acceptance/validate_device_evidence.py <csv>`；将结果/证据交回 Agent 分析。
4. 结果分析后更新 B-03、设备验收报告与 Gate；发布仍需授权。
