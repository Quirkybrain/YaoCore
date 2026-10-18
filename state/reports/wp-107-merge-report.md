# wp-107 TEST-002 测试阶段报告合并报告（task/wp-106-testing-stage → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: `wp-107-merge-testing`（`repository_action: merge`）
- **Handoff**: `state/handoffs/wp-107-merge-testing.json`（pin + snapshot + begin 已完成；本报告提交后运行 `finish wp-107-merge-testing`）
- **日期**: 2026-10-18
- **结果**: **MERGE 成功（`--no-ff`，无冲突）；合并结果上三项验证全部退出 0（host 697/697、crosscheck hard 66/66 ALL PASS、layering 0 violation）**。本报告是集成证据，**不替代任何 Gate 判定**。

## 1. 预检（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree；任务期间未建新 worktree） |
| 当前分支 | `feat/yaocore-app`（= handoff `base_branch`、`target_branch`；未切换） |
| 目标 HEAD | `e74a181cebec1968d9a197c38e350cd2dda6cc80`（= handoff `base_commit`、`feat/yaocore-app` tip） |
| 来源分支 | `task/wp-106-testing-stage` @ `7200543010f4fe95cc6805ac7845f0312e46b181`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `e74a181`（目标 tip 是来源 tip 的直接祖先，无分叉） |
| 工作区 | 干净（`git status --porcelain --untracked-files=all` 无输出）；HEAD 未脱离 |
| 守卫状态 | ACTIVE `wp-107-merge-testing`；无其他活动任务 |
| 快照 | `refs/swe/snapshots/20261018T024526Z-wp-107-merge-testing-74d9e3ba` @ `df6060b20c33a139af271cf480d64642a29e7357`；begin 校验通过 |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；合并前执行 `git fetch origin`（仅更新远端跟踪引用；`origin/main` = `7d6f4c9`）。按任务要求**未 push、未 pull**；本地 `main` 未移动 |
| 其他分支 | 全部 `task/*` 与 `main` 均未移动、未切换、未删除；`task/wp-106-testing-stage` 保留 |

冻结输入哈希复核（与 handoff pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- `gate_evidence_path` `artifacts/60-testing/testing-stage-report.md`：来源 `7200543` 内 blob sha256 `296ea215f73e04ad7266ec1f97aa403c846dd7fc345aed53a4970303f8de2a4c`（= handoff `gate_evidence_path_sha256`）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用 `config/git-policy.default.md` 默认规范，无公司策略覆盖）

来源提交核对（`git log --oneline e74a181..7200543`，1 个，与任务描述一致）：

```text
7200543 test(stage): 执行 TEST-002 最终候选矩阵
```

## 2. 合并

- 命令：`git merge --no-ff task/wp-106-testing-stage -m "chore(merge): 合并 TEST-002 测试阶段报告"`
- 合并提交：`6939574be099ece91e3e698d4815fa932957298b`（主题 `chore(merge): 合并 TEST-002 测试阶段报告`）
- 父提交：`e74a181`（目标，第一父）+ `7200543`（来源，第二父）
- 策略：`ort`；**无冲突**（未手工编辑任何文件）
- 树一致性：目标自 base 后无独立提交，`git diff --quiet 6939574 7200543` 退出 0，合并结果树与来源 tip 完全一致
- 合并范围：`git diff --stat e74a181 6939574` 为 **19 个路径，+6458 / −0**（均为新增）：`artifacts/60-testing/testing-stage-report.md`（+371）与 `artifacts/60-testing/evidence/` 下 18 份证据日志；全部落在 handoff `writes` 的 `artifacts/60-testing/` 内；未触及 `input/`、产品代码、测试断言、工具、构建配置、README 或状态文件
- 内容：仅 TEST-002 testing Stage 报告与证据日志——11 项强制矩阵结果、FR/NFR 映射、缺陷/残余清单、`PASS_WITH_ACCEPTED_RISKS` 结论与 G-016 进入 acceptance 的条件；未新增裁定

## 3. 合并后验证（在 `6939574` 上实际执行，早于任何证据改动）

| # | 检查 | 命令 | 实测结果 | 退出码 |
|---|---|---|---|---|
| 1 | Host 测试 | `entry/src/test/run-host-tests.sh` | **697/697 PASS**：`1..697`、`# tests 697 / # pass 697 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`；≈3065.4 ms | 0 |
| 2 | 协议资产交叉校验 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py` | **hard checks: ALL PASS**：66 条 `[PASS]` / 0 条 `[FAIL]`；14 条既有 frozen-input `FINDING`（非阻塞） | 0 |
| 3 | 分层检查 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | **PASS**：`files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0` | 0 |

补充：三项检查与 TEST-002 报告 §2 的对应结果一致（host 697/697、crosscheck 66/66、layering 0 violation）；完整日志暂存于 `/tmp/opencode/wp107/`（未提交）。命令均在合并提交的干净工作树上运行；Python 命令设置 `PYTHONDONTWRITEBYTECODE=1`；运行后已清理 `__pycache__`，证据提交前 `git status --porcelain` 仅显示两份 deliverable（ignored 构建产物除外）。

## 4. 证据更新

- `artifacts/90-integration/integration-report.md` 追加 **§15「TEST-002 测试阶段报告合并记录（2026-10-18，wp-107）」**：源/目标分支、合并提交与双亲、1 个源提交、19 个合并路径、三项验证矩阵、TEST-002 结论与残余、边界声明。
- 追加内容不回写 §1–§14 的历史结论；§15 与 §14 的验证焦点一致（host、crosscheck、layering），但 TEST-002 的完整 11 项矩阵仍以 `artifacts/60-testing/testing-stage-report.md` 为准。
- 本报告与上述 §15 同属唯一证据提交，路径均在 handoff `deliverables` 内。

## 5. 门禁引用

- 门禁证据：`artifacts/60-testing/testing-stage-report.md`（来源 `7200543`，blob sha256 `296ea215…` = handoff pin；Producer `agent:test-engineer`）。该文件是 TEST-002 testing Stage 报告和 handoff 固定证据，**不是独立审查报告**。
- TEST-002 Verdict：`PASS_WITH_ACCEPTED_RISKS`（代码级，@ `e74a181`）；建议 G-016 testing Stage `PASS_WITH_ACCEPTED_RISKS`，允许进入 acceptance 分析。
- 结论：本次合并只表示 TEST-002 报告与 18 份证据日志已进入集成分支，**不构成 Gate PASS、独立评审或验收结论**；Stage Gate 判定归 Orchestrator。

## 6. 工作树与分支状态（报告提交后）

| 项 | 值 |
|---|---|
| 当前分支 / HEAD | `feat/yaocore-app` / 本报告提交（父提交 `6939574`；SHA 由 `git rev-parse HEAD` 读取，无法写入自身） |
| 来源分支 | `task/wp-106-testing-stage` @ `7200543`，未删除、未移动 |
| 工作区 | 干净；本任务仅新增 `state/reports/wp-107-merge-report.md` 与追加 `artifacts/90-integration/integration-report.md` |
| 未提交 / 未跟踪 | 无（ignored 构建产物除外） |
| 远端 | 合并前仅 `fetch`；未 push、未 pull；未创建 PR/MR |

## 7. 冲突

**无冲突**。`ort` 自动合并；目标 tip 是来源 tip 的直接祖先；19 个路径全部来自来源历史，无目标侧独立改动，无删除/重命名冲突。

## 8. 残余与后续建议

1. **G-016 未裁定**：TEST-002 建议 `PASS_WITH_ACCEPTED_RISKS`；接受风险清单（`PORT-LOC-01`、`D-030/GAP-T18-01`、`R4-01`、i18n 债务、NFR 4.1/4.2/4.3 partial、ACK p95 `MOCK_ONLY`、设备 `BLOCKED`、测试 lint/覆盖率缺口、未签名产物）需由 Orchestrator 在 Stage Gate 记录中逐项处理。
2. **设备/真实环境仍 BLOCKED**：无 `hdc` target、模拟器与签名；`BLK-01..08` 必须由用户侧设备矩阵执行并回填，不得用 host/build 结果外推为验收 PASS。
3. **文档同步债务**：README 仍写 “596 条 `PENDING_REVIEW`” 旧口径，应在 documentation 阶段改为 triage 新口径并处理 RR-03。
4. **后续集成**：`feat/yaocore-app` 对受保护 `main` 按 `main_merge_mode: review_request_when_remote` 走 PR/MR；在补齐 Stage Gate、独立评审与 CI 证据前不得本地直并 `main`。
