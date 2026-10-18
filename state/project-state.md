# YaoCore Project State（最终：PAUSED_AT_STAGE）

- **Project**: YaoCore (爻构) — HarmonyOS NEXT 原生智能家居应用 (ArkTS)
- **Project Status**: ACTIVE（设备验收包就绪，等待用户执行）
- **Current Stage**: implementation（Target Stage 已达成并通过 G-014 Stage Gate）
- **Target Stage**: release（用户 2026-10-18 选择「Release 准备（不发布）」；push/PR/MR/发布仍需显式授权）
- **Project Workflow Level**: STANDARD
- **Execution Mode**: GATED_AUTO
- **Final integration revision**: `feat/yaocore-app @ 1d4b202`（main 仍为 `a6f6558`；未 push）
- **Runtime**: OpenCode V2 + swe-guards 插件（串行主 worktree，task/ → feat/ 分层，全部门禁留痕）

## 交付摘要

- **代码**：HarmonyOS NEXT ArkTS App 全量实现（C-01..C-29）：公共层/领域模型/协议 DTO/加密安全/存储路由/领域仓储/传输发现/Mock/BLE 配网/邀请认证/云与 AC 适配/i18n/壳层组合根/38 个页面与组件/工具链。
- **测试（代码级）**：host **697/697 PASS**；契约 crosscheck **66/66**；仿真器 **20/20**（HTTP+TLS）；layering **0 violation/0 pending**（含 30 条版本化例外）；i18n **0 blocking/0 missing**；构建 **BUILD SUCCESSFUL**（生产图，unsigned HAP）；lint **0 error**。
- **文档**：README（已实现状态 + 已验证命令 + 已知限制）、维护计划（MAINTENANCE-PLAN-001）、契约基线/ADRs/DES-A/DES-B/TEST-001/REPORT/独立评审/集成报告。
- **FR 覆盖**：26 FR：24 covered（host）/2 partial（真实传感器、真实 TLS）；0 gap；NFR 4.1/4.2/4.3 partial。

## Gate 结论链

- G-001..G-009B：Intake/协议夹具/一致性/契约基线/交付计划/测试/构建基线 → 均 PASS。
- CQG-T06..CQG-T18：C-01..C-28 → STABLE（代码级，条件式）；C-29 工具证据（T-19..T-22）。
- **G-013（IG-4）：PASS（代码级）**。
- **G-014（Stage Gate）：PASS_WITH_ACCEPTED_RISKS → PAUSED_AT_STAGE**（`state/gates/G-014-stage-gate.md`）。

## 已接受风险（RA-01..RA-10，详见 G-014）

D-030/GAP-T18-01 服务层 RBAC 缺口（v1 接受）｜R4-01 durable 取消边界｜端口/D-12 例外迁移未完成｜i18n 596 条待 triage｜设备/真实环境未验证（用户执行 BLK-01..08）｜ACK p95 仅 MOCK_ONLY｜NFR partial｜测试 lint/覆盖率缺口｜IG-1/2/3 无独立 Gate｜未签名产物。

## 开放项（用户决策/后续阶段）

1. **设备矩阵**：按维护计划 §4 执行真实 BLE/LAN/TLS/云/视觉测试并回填证据。
2. **发布/远端策略**：本地 `main` 与 `origin/main`（原项目）历史不相关；推送、PR/MR 或新仓库策略需显式授权；守卫禁止本地直并 main（`review_request_when_remote`）。
3. **后续 Stage**：review/testing/acceptance/documentation/release 均为独立阶段，未自动启动。
4. **维护轮**：端口迁移 P1-P3、i18n 596、`tools/build/README.md` 刷新、固件 v2.1 协同（TLS/Pinning 实际启用）、D-030 服务层 RBAC 补齐。

## 运行记录

- 专业任务 40+（含评审/修复/复审循环）；四次 handoff 范围误判均 `--failed` 归档并沉淀规则（D-021/D-024/D-027/D-029/D-031）；一次集成回归（DES-A 表格机读格式）被合并后回归捕获并修复（D-028）。
- 全部任务主 worktree 串行执行；证据链见 `state/handoffs/`、`.git/swe/history/`、`state/gates/`、`state/reports/`、`artifacts/`。

## 恢复后续目标（2026-10-18）
用户指令「继续完成开发」→ 目标从 implementation 扩展至 **documentation**，按以下顺序执行：
1. **开发债务收尾**：端口迁移 P1-P3（contracts/**）、D-030 服务层 RBAC 补齐、R4-01 文档边界、i18n 596 条 triage；
2. **review 阶段**：变更后增量独立评审 + review Stage Gate；
3. **testing 阶段**：全量矩阵重跑 + 验收标准映射 + testing Stage Gate；
4. **acceptance 阶段**：system-verifier 验收分析 + 最终 traceability + acceptance Stage Gate；
5. **documentation 阶段**：README/开发者文档/维护计划最终同步 + documentation Stage Gate → PAUSED_AT_STAGE；
6. **release 不自动启动**：需用户授权推送/PR/远端策略。

## G-015 review Stage Gate（2026-10-18）

- **Verdict: PASS_WITH_ACCEPTED_RISKS** @ `09e1b46`（`state/gates/G-015-review-gate.md`）。
- 本轮变更（端口迁移/裁定修复、i18n triage、检查器 RR、DES 同步）均有独立评审批次；阻断项全部闭环。
- 转 documentation：RR-03（T-23 报告旧口径）；接受：V-01..V-06/O-01（Info）、PORT-LOC-01 OPEN、D-030 RA-01、设备 BLOCKED。
- 下一阶段：G-016 testing（最终 revision 全量矩阵 + FR/NFR 映射）。

## G-016 testing Stage Gate（2026-10-18）

- **Verdict: PASS_WITH_ACCEPTED_RISKS** @ `1cccec5`（`state/gates/G-016-testing-gate.md`）。
- TEST-002：11/11 矩阵 exit 0；host 697、crosscheck 66、simulator 20、layering 0、fixtures 27、i18n 0 blocking、build SUCCESS。
- FR 26 → 24 covered / 2 partial / 0 gap；NFR 4.1/4.2/4.3 partial；ACK p95 MOCK_ONLY；设备 BLOCKED。
- 下一阶段：G-017 acceptance（system-verifier 验收就绪与最终追溯）。

## G-017 acceptance Stage Gate（2026-10-18）

- **Verdict: PASS_WITH_ACCEPTED_RISKS（acceptance readiness）** @ `4faf3e3`（`state/gates/G-017-acceptance-gate.md`）。
- FR 26：24 COVERED / 2 PARTIAL / 0 GAP；NFR 4.1/4.2/4.3 PARTIAL；用户验收未执行（BLK-01..08）。
- 待用户决定：GAP-AC-01..03（LAN IP/家庭切换形态/房间图标）；文档 D-AC-01..08 + RR-03 转 documentation。
- 下一阶段：G-018 documentation；release 不启动（需授权）。

## G-018 documentation Stage Gate（2026-10-18）

- **Verdict: PASS** @ `13de4d7`（`state/gates/G-018-documentation-gate.md`）：D-AC-01..08 + RR-03 全部闭环；文档与代码/测试/门禁口径一致。
- **Target Stage `documentation` 达到 → PAUSED_AT_STAGE**；release 未启动。
- 最终 revision：`feat/yaocore-app @ 13de4d7`；工作树干净；无活动交接。
- 待用户：GAP-AC-01..03、设备矩阵 BLK-01..08、release/远端授权、D-009..D-012 确认/覆盖。

## Release 准备（2026-10-18，用户选择）

- 目标：release **仅准备**（版本/CHANGELOG/release notes/签名与远端清单/发布检查单/未签名产物校验）。
- **明确不授权**：push、PR/MR、`main` 合并、签名证书使用、应用市场/远端发布。
- 现有基线：versionName `1.0.0` / versionCode `1000000`；`signingConfigs: []`；无 HAP 产物；无 CHANGELOG/LICENSE。
- 待用户决定：许可证、签名证书与远端策略、GAP-AC-01..03、设备矩阵。

## G-019 release 准备 Stage Gate（2026-10-18）

- **Verdict: NOT_READY（publish）** @ `e998cc6`（`state/gates/G-019-release-preparation-gate.md`）；**release 准备工作完成**。
- 发布资产：RELEASE-001/检查单/CHANGELOG/Release Notes；独立复评 PASS（F-01..F-06 闭环）。
- 产物：release 模式未签名 HAP 1,616,146 B / SHA-256 `1602110d…`（非字节可复现）。
- 阻塞 B-01..B-09：许可证/身份、签名、设备验收、GAP-AC、远端授权、版本冻结、文档签核、风险签核、构建硬化。
- **未执行**任何 push/PR/MR/tag/签名/市场发布。

## 设备验收阶段（2026-10-19，用户指令）

- **优先事项**：设备验收（用户执行硬件；Agent 提供可执行的验收包与结果分析）。
- **不使用原仓库**：`origin`（Quirkybrain/YaoCore）不作为基线、不 fetch/push/PR/MR；设备包使用本地构建与本地身份 `com.example.yaocore`（B-01 最终身份 A/B/C 仍待定，设备结果可能需按最终身份复验安装/升级）。
- release 准备保持完成状态；发布/签名/远端仍**未授权**。
- 计划：验收包（BLK-01..08 用例/步骤/证据模板/校验脚本）→ 用户执行 → 回填证据 → Agent 分析并产出设备验收报告 → 更新 B-03 与风险。

## 设备验收包就绪（2026-10-19）

- 31 用例 `DA-001..DA-031`，覆盖 BLK-01..08、U-01..U-12、26 FR/NFR；校验工具 self-test 18/18、模板 31/31 NOT_RUN、secret clean。
- 合并 `51ac14c` / 证据 `3c4fb11`；host 697/697、layering 0 violation。
- **设备执行未发生**；不使用原仓库；本地身份 `com.example.yaocore`；发布/签名仍未授权。
- 下一步：用户签名构建 → 安装 → 执行用例 → 回填 CSV/证据 → Agent 分析 → 更新 B-03。
