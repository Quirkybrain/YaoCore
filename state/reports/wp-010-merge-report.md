# wp-010 合并集成报告（task/wp-010-test-plan → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-010-merge（repository_action: merge）
- **Handoff**: state/handoffs/wp-010-merge.json（pin + snapshot + begin 由 Orchestrator 完成；本报告所在提交后运行 finish）
- **日期**: 2026-10-17
- **结果**: SUCCESS —— `--no-ff` 合并完成、无冲突；恰好一个证据提交（本报告）；待守卫 `finish wp-010-merge` 归档。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore` |
| 目标分支 | `feat/yaocore-app` @ `1c44503e0720c0305ab5d1d0d894af09ea06a009`（= handoff `base_commit`；合并前 HEAD 即此） |
| 来源分支 | `task/wp-010-test-plan` @ `fa21c67ae49e0350d8c4ea76f1ecdeaf67e70cba`（= handoff `source_commit`，与 `git rev-parse` 实查一致） |
| 来源提交 | **1 个提交**：`test(harness): 测试计划、仿真器移植与 host 测试骨架` |
| 合并基 | `git merge-base` = `1c44503e0720c0305ab5d1d0d894af09ea06a009`（即目标 tip；来源为线性追加，仍按策略强制 `--no-ff`） |
| 工作区 | 干净（`git status --porcelain` 无输出）；`main` @ `a6f6558` 未动 |
| 守卫状态 | ACTIVE `wp-010-merge`（begin 已由 Orchestrator 完成）；无其他活动任务 |
| 快照 | `refs/swe/snapshots/20261017T072536Z-wp-010-merge-335a6070` @ `a701646`（`entry/src/ohosTest/` 前身保护） |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；合并前/后 `git fetch origin --prune` 均无引用变化；本次**未 push** |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- 策略：`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用默认规范）
- 门禁证据字节固定复核见 §4。

预检差异复核：`git diff --stat 1c44503..fa21c67` = **57 files changed, 4749 insertions(+), 0 deletions**。`git diff --name-status` 全部为 `A`（新增），无 `M`/`D`/`R`；路径全部落在 handoff `writes` 声明范围内（`artifacts/60-testing/`、`tools/simulator/`、`tools/contract/`、`tools/test-fixtures/`、`entry/src/ohosTest/ets/test/`、`entry/src/test/`）。

## 2. 合并执行

按 pin 的策略 `merge_strategy: no-ff` 与 handoff 指定主题执行：

```text
git merge --no-ff task/wp-010-test-plan -m "chore(merge): 合并 T-05 TEST-001 测试基础设施到 feat/yaocore-app"
```

- 结果：`Merge made by the 'ort' strategy`；**无冲突**（未发生任何冲突解决、rebase、reset 或强制操作）。
- **merge 提交**：`624f28356044a8fa77cf0f42b944352bb9de8cb8`
- 主题：`chore(merge): 合并 T-05 TEST-001 测试基础设施到 feat/yaocore-app`（与 handoff 指定主题逐字一致，无正文）
- 双亲验证（`git log -1 --format=%P 624f283`）：`^1 = 1c44503e0720c0305ab5d1d0d894af09ea06a009`（固定目标 tip）、`^2 = fa21c67ae49e0350d8c4ea76f1ecdeaf67e70cba`（固定来源 tip）
- 合并规模：**57 files changed, 4749 insertions(+), 0 deletions**
- 内容一致性：`git diff task/wp-010-test-plan 624f283` 为空（合并结果与来源 tip 内容完全相同）。

### 2.1 57 文件按目录统计（全部为 `A` 新增）

| 目录 | 文件数 | 内容摘要 |
|---|---:|---|
| `entry/src/test/` | 20 | Host 测试骨架与证据：`run-host-tests.sh`、`host/*.mjs`（7）、`HostBaseline.test.ets`、`List.test.ets`、`README.md`、`evidence/*.log`+`.tap`（9） |
| `tools/simulator/` | 16 | `gateway_contract_server.py`、`test_gateway_contract.py`、`README.md`；`certs/`（README + 测试证书/私钥 2）；`evidence/`（README + HTTP/TLS 日志与响应 10） |
| `tools/contract/` | 10 | `crosscheck_protocol_assets.py`、`README.md`；`evidence/`（README + 冻结协议响应 JSON 6 + `run-crosscheck.txt`） |
| `entry/src/ohosTest/ets/test/` | 8 | `README.md` + `contract/fixtures/`（README + 7 个协议/鉴权夹具） |
| `tools/test-fixtures/` | 2 | `README.md`、`iotda/product-profile.json` |
| `artifacts/60-testing/` | 1 | `test-plan.md`（597 行，G-008 门禁证据） |
| **合计** | **57** | **+4749 行，-0 行** |

**前身保护复核（无意外覆盖）**：目标分支合并前既有的 ohosTest 文件——`entry/src/ohosTest/ets/test/Baseline.test.ets`（blob `e1e8fd94…`）、`entry/src/ohosTest/ets/test/List.test.ets`（blob `bf9d6135…`）、`entry/src/ohosTest/module.json5`（blob `509a3a28…`）——在合并后 blob 逐一相同；`git diff --name-status 1c44503 624f283 -- entry/src/ohosTest` 仅 8 项 `A`，无任何 `M`/`D`。既有 `tools/build/**` 与 `entry/src/ohosTest/**`（T-01）零改动。

## 3. 证据提交（恰好一个，紧随 merge 提交）

- 提交主题：`chore(repo): 记录 wp-010 合并集成证据`
- 唯一变更路径：`state/reports/wp-010-merge-report.md`（本报告；`state/` 被 `.gitignore:37` 忽略，以 `git add -f` 显式暂存，暂存集仅此一个路径）
- 提交前检查：`git diff --cached --check` 通过（无空白错误）
- 提交后复核：`git show --stat` 仅含单文件；本提交为 merge 提交 `624f283` 的唯一直接后继（`git rev-list --first-parent 624f283..HEAD` 长度为 1）
- **证据提交自身 SHA 说明**：提交内容无法内嵌其自身哈希（哈希自引用不可满足），故此处不给字面值。权威值即守卫 finish 写入 `state/handoffs/history/` 的 `result_commit` 字段；复核命令：`git log -1 --format=%H feat/yaocore-app`（= 本报告所在提交）。

## 4. 门禁证据引用（按来源 tip 固定）

| 项 | 值 |
|---|---|
| Gate | **G-008 Artifact Validation Gate（TEST-001 测试计划与骨架）— PASS**（Orchestrator 裁定，日期 2026-10-17） |
| **验证 revision** | **`fa21c67ae49e0350d8c4ea76f1ecdeaf67e70cba`**（来源 tip，单提交） |
| 门禁记录 | `state/gates/G-008-test-plan.md`（`state/` 不入库，记录在本地状态） |
| 门禁结论 | TEST-001 对声明范围 `VALID`（Accepted @ G-008, revision `fa21c67`）；D-019 校准：Host 官方路径 `entry/src/test/run-host-tests.sh`，CQG 必含 hvigorw + codelinter + host runner（+ 适用契约/仿真器证据） |
| 来源分支已提交门禁工件 | `artifacts/60-testing/test-plan.md` @ `fa21c67`（handoff `gate_evidence_path`；597 行 / 42265 字节） |
| 守卫 pin 的工件字节 | sha256 `33485cc39abd9a917e94b6568b29e162cd90897adfad509e3f59403a56055fae`（合并前以 `git show fa21c67:<path> \| sha256sum` 复核一致） |
| 合并后复核 | `git rev-parse 624f283:artifacts/60-testing/test-plan.md` = `73d5ee09a9ec7d60324732343867183bb3432a4d`，与来源 tip 同路径 blob 完全一致；`git show HEAD:<path> \| sha256sum` 仍为 `33485cc3…` |
| 门禁 Next action | 合并 `task/wp-010-test-plan` → `feat/yaocore-app`（创建 `task/wp-011-des-a-sync`），随后派发 DES-A §27 同步修订小任务（T-06 前） |

## 5. 冲突与合并后复核

- **冲突解决记录：无冲突** —— `ort` 策略直接完成合并；无手工解决、无 `reset`、无 `rebase`、无强制操作。
- 合并后拓扑：`1c44503 → 624f283`（双亲 `1c44503` + `fa21c67`）；`task/wp-010-test-plan` 仍 @ `fa21c67`（引用未移动）。
- 合并后工作区：干净（证据提交前 `git status --porcelain` 无输出；证据提交另行创建）。
- 其他分支引用未变：`main` @ `a6f6558`（fetch 后 `origin/main` @ `7d6f4c9`，本地 main 未动）、`task/wp-001-intake` @ `fc66ec4`、`task/wp-002-fixture-validation` @ `e2d32b3`、`task/wp-003-consistency` @ `07687fd`、`task/wp-004-contracts` @ `697762c`、`task/wp-005-plan` @ `6699173`、`task/wp-006-build-baseline` @ `83c60db`、`task/wp-007-readme` @ `67a7b42`、`task/wp-008-des-a` @ `6c186f0`、`task/wp-009-des-b` @ `0b5e636`、`task/wp-010-test-plan` @ `fa21c67`；未创建 worktree（`git worktree list` 仅主工作区）；未 push。

## 6. 新任务分支与下一步

- 按 handoff 步骤 5，`finish` 通过后从汇总分支新 tip（证据提交）创建：**`task/wp-011-des-a-sync`**（`git branch`，不切换；当前分支保持 `feat/yaocore-app`）。
- 其 tip = 证据提交（本报告所在提交）——因创建发生在证据提交之后且不产生新提交，完整 SHA 可由 `git rev-parse task/wp-011-des-a-sync` 复核，并记录于守卫 finish 记录。
- **下一步建议**：
  1. Orchestrator 运行 `python3 scripts/swe_guard.py status` 确认 `wp-010-merge` 已归档（无活动任务）。
  2. 按 G-008 Next action 派发 **DES-A §27 同步修订小任务** 于 `task/wp-011-des-a-sync`（需按守卫流程 pin + begin；handoff 声明 `task_branch: task/wp-011-des-a-sync`、`parent_branch: feat/yaocore-app`；目标 `artifacts/40-detailed-design/des-001a-foundation-transport.md`，记录 "extended by DES-001B §23"）。
  3. 之后启动 **T-06（C-01..C-03 基础/协议映射实现）**；每个组件任务 CQG 必须遵循 D-019：`hvigorw` 构建 + `codelinter` + host runner 新增测试通过 + 适用时 `tools/contract`/`tools/simulator` 证据。
  4. 后续小任务逐一经 `feat/yaocore-app` 汇总；全部完成后，因 `main_merge_mode: review_request_when_remote` 且存在 `origin`，须经托管平台 PR/MR（独立评审 + 必需 CI + 讨论解决）合并至受保护 `main`；守卫将拒绝本地 main merge。
