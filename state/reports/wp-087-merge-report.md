# wp-087 合并集成报告（task/wp-087-integration → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-087-merge（repository_action: merge）
- **Handoff**: `state/handoffs/wp-087-merge.json`（pin + begin 已完成；本报告提交后运行 `finish wp-087-merge`）
- **日期**: 2026-10-18
- **结果**: **MERGE 成功（`--no-ff`，无冲突）；合并后三项指定验证全部 PASS（host 697/697、clean 构建成功、分层检查 0 violation）**。本报告是集成证据，**不替代任何 Gate 判定**；IG-4 / G-013 / G-014 与 Stage Gate 结论归 Orchestrator 的 Stage 流程。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree，无新建 worktree） |
| 目标分支 | `feat/yaocore-app` @ `d2896fbee100749b894ec0f965c448d15417eb86`（= handoff `base_commit`；合并前 HEAD 即此，任务期间未切换） |
| 来源分支 | `task/wp-087-integration` @ `7413704c8382623c8d4460e612c879b5c48d1e3a`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `d2896fb`（目标 tip；目标 tip 是来源的直接祖先，可 `--no-ff` 合并） |
| 工作区 | 干净（`git status --porcelain` 无输出）；HEAD 未脱离 |
| 守卫状态 | ACTIVE `wp-087-merge`（begin 已完成）；无其他活动任务 |
| 快照 | 本任务 `snapshot_paths` 为空，未创建快照 ref；来源任务快照见 `refs/swe/snapshots/` 历史项（本次合并只读来源，未改写） |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；本次**未 push、未 fetch**，未改写任何远端跟踪引用 |
| 其他分支 | `main` @ `a6f6558` 及全部 `task/*` 未移动、未切换、未删除 |

冻结输入哈希复核（与 handoff pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- `gate_evidence_path` `artifacts/90-integration/integration-report.md`：来源 `7413704` 中 sha256 `9651afbc093b9c66c4f4080dffd87aadb5e249c1ed9a35d66cf1f752cf41b99b`（= handoff `gate_evidence_path_sha256`；合并后工作树 blob `92473ffab13ec667efcd1274abf1f528a0539cd8`，与来源一致）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用 `config/git-policy.default.md` 默认规范，无公司策略覆盖）

## 2. 来源与预检

来源分支仅 1 个提交（`git log --oneline d2896fb..7413704`）：

```text
7413704 docs(integration): 集成验证与 Stage Gate 输入报告
```

预检结果：目标工作区干净；来源 tip 精确等于 handoff `source_commit`；目标 tip 为来源直接祖先（无分叉）。`git diff --stat d2896fb..7413704` 为 **14 个路径，+6945 / −0**，全部为新增，均落在 handoff `writes`（`artifacts/90-integration/`）内；无代码、测试、工具、构建配置、契约或 `input/` 改动。

## 3. 合并

- 命令：`git merge --no-ff task/wp-087-integration -m "chore(merge): 合并 T-22 集成报告到 feat/yaocore-app"`
- 合并提交：`69ed298aa7fe3a0a35112a66f21ea378803b4d57`（主题 `chore(merge): 合并 T-22 集成报告到 feat/yaocore-app`）
- 父提交：`d2896fb`（目标，第一父）+ `7413704`（来源，第二父）
- 策略：`ort`；**无冲突**（未手工编辑任何文件）
- 树一致性：目标自 base 后无独立提交，`git diff --quiet 69ed298 7413704` 通过，合并结果树与来源 tip 完全一致
- 证据 blob 复核：`git diff --quiet 69ed298:artifacts/90-integration/integration-report.md 7413704:...` 等价于上一条；工作树 sha256 `9651af…`，与 pin 一致

## 4. 变更统计（`d2896fb..69ed298`）

| 路径 | 文件数 | + | − | 说明 |
|---|---:|---:|---:|---|
| `artifacts/90-integration/integration-report.md` | 1（新增） | 361 | 0 | INTEGRATION-REPORT-001：T-22 集成验证、IG-4/G-013/G-014 输入与残余风险 |
| `artifacts/90-integration/evidence/*` | 13（新增） | 6584 | 0 | host TAP、clean assemble、codelinter、crosscheck、i18n、layering、ohosTest、simulator、ACK p95 mock 证据 |
| **合计** | **14** | **6945** | **0** | 与 handoff `writes` 一致；未触及产品代码、测试、构建配置或状态文件 |

文件清单：

```text
artifacts/90-integration/integration-report.md
artifacts/90-integration/evidence/t22-ack-p95-mock.json
artifacts/90-integration/evidence/t22-ack-p95-mock.log
artifacts/90-integration/evidence/t22-clean-assemble.log
artifacts/90-integration/evidence/t22-codelinter.log
artifacts/90-integration/evidence/t22-crosscheck.log
artifacts/90-integration/evidence/t22-host-node-tests.tap
artifacts/90-integration/evidence/t22-i18n-checker.log
artifacts/90-integration/evidence/t22-i18n-report.json
artifacts/90-integration/evidence/t22-layering-fixture-tests.log
artifacts/90-integration/evidence/t22-layering.json
artifacts/90-integration/evidence/t22-layering.log
artifacts/90-integration/evidence/t22-ohosTest-assemble.log
artifacts/90-integration/evidence/t22-simulator-contract.log
```

## 5. 合并后验证（在 `69ed298` 上执行，早于证据提交且不含任何代码改动）

| # | 检查 | 命令 | 结果 |
|---|---|---|---|
| 1 | Host 测试 | `bash entry/src/test/run-host-tests.sh` | ✅ **697/697 PASS**（`1..697`、`# pass 697 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`，exit 0，duration ≈ 3039.0 ms） |
| 2 | 构建 | `hvigorw clean assembleHap --no-daemon` | ✅ **BUILD SUCCESSFUL in 14 s 753 ms**（35 tasks：34 executed / 1 up-to-date；仅既有 ArkTS 警告与“未配置 signingConfigs，跳过签名”提示，均为预期；unsigned HAP） |
| 3 | 分层检查 | `python3 tools/contract/check_layering.py` | ✅ **PASS**：`files=209 violations=0 exceptions_used=13 pending=0 pending_used=0 port_exceptions_used=10 port_pending=0 port_pending_used=0`，exit 0 |
| 4 | 工作区 | `git status --porcelain` | ✅ 干净（构建产物均被忽略） |

说明：以上为 handoff 指定的合并后三项验证，作为 Stage Gate 的最终集成证据；未复跑 codelinter、i18n strict、协议 crosscheck、fixture 与设备矩阵（其 T-22 证据已随本合并进入汇总分支，且本合并不改变产品代码）。

## 6. 冲突

**无冲突**。`ort` 自动合并；目标 tip 是来源 tip 的直接祖先；14 个路径全部为新增，无删除、无重叠修改。

## 7. 门禁引用

- 门禁证据：`artifacts/90-integration/integration-report.md`（来源提交 `7413704`，sha256 `9651afbc093b9c66c4f4080dffd87aadb5e249c1ed9a35d66cf1f752cf41b99b` = handoff pin；Producer `agent:integration-engineer`，Status COMPLETE，集成 revision `d2896fb`）。
- 内容要点：host 697/697、`clean assembleHap` BUILD SUCCESSFUL（unsigned）、codelinter 0 error / 25 warning、layering 0 violation / 0 pending、fixture 10/10、i18n `--strict-ui` 0 blocking、crosscheck 66/66、simulator 20/20、ohosTest 仅编译、HAP 内 Mock/ohosTest 0 命中；与 T-19/T-20 对比无产品回归。
- 报告结论（引用，非本任务判定）：**IG-4 代码级 PASS；G-013 建议 PASS_WITH_ACCEPTED_RISKS；G-014 建议 PASS_WITH_ACCEPTED_RISKS**，前提是 Orchestrator 逐项接受 §7 残余风险并完成 §8.3 State/Checkpoint 动作；设备 / 真实 BLE/LAN/TLS/云/视觉/fps 为 BLOCKED/UNAVAILABLE，ACK p95 为 MOCK_ONLY，不得改写为验收 PASS。
- 结论：本次合并只表示 T-22 集成报告及其证据已进入集成分支，**不构成 Gate PASS**；Stage Gate 判定归 Orchestrator。

## 8. 证据提交与分支

- 本报告单独提交（主题 `chore(repo): 记录 wp-087 合并集成证据`，第一父为合并提交 `69ed298`；仅包含 `state/reports/wp-087-merge-report.md`）。该提交 SHA 无法写入自身，由 `git rev-parse HEAD` / `finish` 记录读取；其 tip 即最终 `feat/yaocore-app` tip。
- `git diff --cached --check` 已执行（无空白错误）；`git add -f` 用于纳入被忽略的 `state/` 路径。
- **未创建新任务分支**（实现阶段任务已全部完成）；未切换/移动其他分支，未建 worktree，未 push，未使用 reset/force。

## 9. Stage Gate 交接

1. `feat/yaocore-app` 现包含 T-22 集成报告与全部证据，可作为 G-014 Stage Gate 的最终集成候选 revision（证据提交 tip）。
2. Orchestrator 需在 Gate 记录中引用本报告与 INTEGRATION-REPORT-001，逐项接受或拒绝其 §7 残余风险；未接受前保持 `NOT READY`。
3. 设备 / 真实网络 / 云 / 视觉 / fps 验证由用户按报告 §8.4 设备矩阵执行，仓库侧不得改写为 PASS。
4. 汇总分支对 `main` 的集成按 `main_merge_mode: review_request_when_remote` 走 PR/MR（不得本地直并 `main`），并等待所需 CI、独立审阅与讨论关闭。
