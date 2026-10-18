# Checkpoint CP-013 — release 准备完成，PAUSED_AT_STAGE

```text
Checkpoint ID: CP-013
时间: 2026-10-18
Repository revision / working-tree state: feat/yaocore-app @ e998cc6（干净；无活动交接）
Current Stage: release（准备完成）
Target Stage: release（准备范围；发布未授权）
Workflow and Execution Modes: STANDARD / GATED_AUTO
Active Task: 无
```

## 本轮完成（自 CP-012）

| 工作 | 结果 | 证据 |
|---|---|---|
| Release 目标扩展 | `config/project.md` Target Stage → release；登记发布未授权边界 | `6cd9a88` |
| RELEASE-001 发布计划 + 检查单 | 版本/构建/签名/远端/回滚/Gate 判据；release 模式 HAP 1,616,146 B / `1602110d…` | `560d08a`/`972f177`/`3501f5e` |
| 公开旧版本对照（F-01） | `origin/main` 1.0.0（`io.github.quirkybrain.yaocore`、Apache-2.0+NOTICE）A/B/C 选项，待用户决定 | `972f177` |
| CHANGELOG + Release Notes | v1.0.0 草案（`DRAFT/NOT_READY`，B-01..B-09） | `63d2235`/`19df893` |
| 独立评审 | 首次 CHANGES_REQUIRED（F-01 High）→ 修正 → **复评 PASS** | `f1fbe0d`/`1e955a8` |
| G-019 release 准备 Gate | **NOT_READY（publish）**；准备工作完成 | `state/gates/G-019-release-preparation-gate.md` |

集成提交：`40fe2a8`/`b716207`（计划）、`21c601d`/`e998cc6`（文档与修正）。

## 最终验证（代码基线 `e74a181`，未变）

host **697/697**；crosscheck **66/66**；layering **0 violation**；fixtures **27/27**；i18n **0 blocking**；triage 615 行；发布文档 4 份存在、B-01..B-09 一致、53 链接 0 broken、无越界表述。

## 发布阻塞（B-01..B-09）

B-01 许可证/身份 A/B/C｜B-02 签名｜B-03 设备/用户验收｜B-04 GAP-AC-01..03｜B-05 远端/通道授权｜B-06 身份/版本冻结｜B-07 CHANGELOG/Notes 签核｜B-08 残余风险签核｜B-09 API 14 兼容/混淆裁剪决策。

## 待用户决定

1. 身份/版本/许可证：A 沿用旧身份 + versionCode >1000000 + Apache-2.0/NOTICE；B 保留 `com.example.yaocore` 独立应用；C 混合/迁移。
2. B-09：API 14 运行时验证、混淆/裁剪/符号化。
3. P1/P2 回滚阈值批准。
4. 签名材料、设备矩阵、远端/发布授权。
5. GAP-AC-01..03 接受或修复。

## Next ready action

- **PAUSED_AT_STAGE**：不启动签名/推送/PR/MR/tag/发布。
- 恢复：`python3 scripts/swe_guard.py status` → 核对 HEAD `e998cc6` → 读 CP-013 / `state/project-state.md` / G-019。
