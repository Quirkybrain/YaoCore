# YaoCore Project State（最终：PAUSED_AT_STAGE）

- **Project**: YaoCore (爻构) — HarmonyOS NEXT 原生智能家居应用 (ArkTS)
- **Project Status**: ACTIVE（review Stage Gate PASS，进入 testing）
- **Current Stage**: implementation（Target Stage 已达成并通过 G-014 Stage Gate）
- **Target Stage**: documentation（用户 2026-10-18 指令「继续完成开发」扩展；release/发布另需授权）
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
