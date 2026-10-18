# G-017 — Stage Gate（acceptance）

```text
Gate ID and type: G-017, Stage Gate（acceptance readiness）
Purpose and scope: 判定验收就绪（代码级）与用户侧验收边界；不授予产品/设备验收。
Input revisions: feat/yaocore-app @ 4faf3e3；ACCEPT-001 @ d649ac7（合并 06265fd）；TEST-002 @ 7200543；G-015/G-016。
Workflow Level: STANDARD
```

## Checks

| 检查 | 结论 | 依据 |
|---|---|---|
| FR 清点与追溯 | ✅ 26 FR 编号连续唯一；Requirement→设计→Component→Task→代码→测试链完整；24 COVERED / 2 PARTIAL / 0 GAP | ACCEPT-001 §2/§3 |
| NFR | ⚠️ 4.1/4.2/4.3 均 PARTIAL；4.3.3 60/120fps 无实测 | ACCEPT-001 §3 |
| 代码级验收 | ✅ build/lint/host/契约/仿真/layering/i18n 均 PASS（最终候选复验） | TEST-002、ACCEPT-001 §5 |
| 用户侧验收 | ⏳ 未执行：签名/设备/BLE/LAN/云/TLS/视觉/A11y/fps（BLK-01..08） | ACCEPT-001 §4 |
| UI 子句偏离 | ⚠️ `GAP-AC-01..03`（LAN IP 展示、首页家庭切换形态、房间图标）→ **用户决定：接受为 v1 简化或 bounded fix** | ACCEPT-001 §4.1 |
| 文档漂移 | ⚠️ `D-AC-01..08` + RR-03 → documentation 阶段 | ACCEPT-001 §4.2 |
| 安全与风险 | ✅ 无未关闭 High/Critical；D-030/R4-01/P-HMAC/PB-01/02 均登记 | RA-01..RA-10、ACCEPT-001 §6 |
| 范围边界 | ✅ 未启动 release；未 push；未合并 main | 本轮记录 |

## Verdict

**PASS_WITH_ACCEPTED_RISKS（acceptance readiness）** — 代码级验收就绪；**用户验收未完成**。

## 待用户决定 / 执行

1. **GAP-AC-01..03**：接受为 v1 简化，或派发 bounded fix（新增 UI 行为需 Change Impact）。
2. **签名与设备矩阵**：BLK-01..08（建议顺序：签名/设备 smoke → BLE → LAN/HMAC → TLS/固件 → 云/硬件 → 视觉/性能）。
3. **release/远端策略**：推送、PR/MR、`main` 合并与发布需显式授权。
4. 风险确认：D-030、R4-01、P-HMAC、PB-01/02、PORT-LOC-01、i18n 残余。

## Next action

进入 **G-018 documentation**：同步 D-AC-01..08 + RR-03（README/维护计划/测试报告/集成报告），随后 PAUSED_AT_STAGE。

```text
Evaluator: Orchestrator (main session)
Date / repository revision: 2026-10-18 / 4faf3e3
```
