# wp-006 合并集成报告（task/wp-006-build-baseline → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-006-merge（repository_action: merge）
- **Handoff**: state/handoffs/wp-006-merge.json（pin + begin 由 Orchestrator 完成；本报告所在提交后运行 finish）
- **日期**: 2026-10-17
- **结果**: SUCCESS —— `--no-ff` 合并完成、无冲突；恰好一个证据提交（本报告）；待守卫 `finish wp-006-merge` 归档。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore` |
| 目标分支 | `feat/yaocore-app` @ `b08646b311eaaf1464644332d321bad3f246f97b`（= handoff `base_commit`） |
| 来源分支 | `task/wp-006-build-baseline` @ `83c60dbdefe3d1c8c3e7928ced70a5504c148591`（= handoff `source_commit`，与 `git rev-parse` 实查一致） |
| 来源提交 | 单提交 `83c60db` `build(baseline): 验证本地构建与测试运行路径`（7 文件，830 行新增；G-009 记录一致） |
| 合并基 | `git merge-base` = `b08646b311eaaf1464644332d321bad3f246f97b`（即目标 tip；来源为线性追加） |
| 工作区 | 干净（`git status --porcelain` 无输出）；HEAD = 目标 tip；主分支 `main` @ `a6f6558` 未动 |
| 守卫状态 | ACTIVE `wp-006-merge`（begin 已由 Orchestrator 完成）；无其他活动任务 |
| 快照 | 无（handoff `snapshot_paths: []`；7 个路径在目标分支均首次引入，无前身文件需保护） |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；本次**未 fetch、未 push**（handoff 未要求，且不得改变远端状态） |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- 策略：`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用默认规范）
- 门禁证据字节固定复核见 §4。

预检差异复核：`git diff --stat b08646b..83c60db` = **7 files changed, 830 insertions(+)**，全部为新增（`A`），路径与 handoff `writes`（`artifacts/50-implementation/`、`tools/build/`、`entry/src/ohosTest/`、`oh-package-lock.json5`）一致。合并前逐一确认 7 个路径在目标分支均 `ABSENT`。

## 2. 合并执行

按 pin 的策略 `merge_strategy: no-ff` 与 handoff 指定主题执行：

```text
git merge --no-ff task/wp-006-build-baseline -m "chore(merge): 合并 T-01 构建基线到 feat/yaocore-app"
```

- 结果：`Merge made by the 'ort' strategy`；**无冲突**（未发生任何冲突解决、rebase、reset 或强制操作）。
- **merge 提交**：`e89814a80ae00527e5c0caf6a809c4e4c32aff1a`
- 主题：`chore(merge): 合并 T-01 构建基线到 feat/yaocore-app`（与 handoff 指定主题逐字一致，无正文）
- 双亲验证（`git show -s --format=%P e89814a`）：`^1 = b08646b311eaaf1464644332d321bad3f246f97b`（固定目标 tip）、`^2 = 83c60dbdefe3d1c8c3e7928ced70a5504c148591`（固定来源 tip）
- 合并规模：**7 files changed, 830 insertions(+), 0 deletions**，全部位于 handoff `writes` 范围内（明细见 §3）。

| # | 路径 | blob | 行 / 字节 | 模式 | 说明 |
|---|---|---|---|---|---|
| 1 | `artifacts/50-implementation/build-baseline.md` | `c39db740…` | 498 / 22371 | 100644 | BUILD-BASELINE-001（G-009 门禁证据） |
| 2 | `tools/build/README.md` | `79f2b540…` | 83 / 4699 | 100644 | 命令与限制说明；受 `**/build` ignore 匹配，来源分支已 force-add（tracked） |
| 3 | `tools/build/verify-baseline.sh` | `a7cb9d29…` | 183 / 6628 | 100755 | 可复现验证脚本；同上 ignore/tracked 状态，保留可执行位 |
| 4 | `entry/src/ohosTest/module.json5` | `509a3a28…` | 11 / 176 | 100644 | ohosTest 模块配置 |
| 5 | `entry/src/ohosTest/ets/test/List.test.ets` | `bf9d6135…` | 5 / 103 | 100644 | Hypium 测试套件入口 |
| 6 | `entry/src/ohosTest/ets/test/Baseline.test.ets` | `e1e8fd94…` | 22 / 674 | 100644 | 构建基线测试探针 |
| 7 | `oh-package-lock.json5` | `c5a91ec3…` | 27 / 975 | 100644 | `ohpm install` 锁文件 |

- 内容一致性（`git diff task/wp-006-build-baseline e89814a` 为空）：合并树在改动范围内与来源 tip 逐字节一致；7 个 blob 与来源分支同路径逐一相同。
- **无覆盖**：目标分支此前不存在上述任何路径，7 项均为 `A`（新增），无 `M`/`D`。

## 3. 证据提交（恰好一个，紧随 merge 提交）

- 提交主题：`chore(repo): 记录 wp-006 合并集成证据`
- 唯一变更路径：`state/reports/wp-006-merge-report.md`（本报告；`state/` 被 `.gitignore:37` 忽略，以 `git add -f` 显式暂存，暂存集仅此一个路径）
- 提交前检查：`git diff --cached --check` 通过（无空白错误）
- 提交后复核：`git show --stat` 仅含单文件；本提交为 merge 提交 `e89814a` 的唯一直接后继（`git rev-list --first-parent e89814a..HEAD` 长度为 1）
- **证据提交自身 SHA 说明**：提交内容无法内嵌其自身哈希（哈希自引用不可满足），故此处不给字面值。权威值即守卫 finish 写入 `state/handoffs/history/` 的 `result_commit` 字段；复核命令：`git log -1 --format=%H feat/yaocore-app`（= 本报告所在提交）。

## 4. 门禁证据引用（按来源提交固定）

| 项 | 值 |
|---|---|
| Gate | **G-009 Build Baseline Artifact Validation + Component Quality（构建基线证据）— PASS**（Orchestrator 裁定，日期 2026-10-17 / revision `83c60db`） |
| 门禁记录 | `state/gates/G-009-build-baseline.md` |
| 门禁结论 | 构建与静态检查基线成立，可作为后续任务的 CQG 证据口径；测试探针编译 PASS、运行 BLOCKED（无设备/模拟器、`signingConfigs: []`），如实分类未虚报 PASS |
| 来源分支已提交门禁工件 | `artifacts/50-implementation/build-baseline.md` @ `83c60db`（handoff `gate_evidence_path`） |
| 守卫 pin 的工件字节 | sha256 `a65f78ad66350b27c9d83839288b9bd9348077ae7e976466ced49e0071a13d68`（合并前以 `git show 83c60db:artifacts/50-implementation/build-baseline.md \| sha256sum` 复核一致；合并后 blob `c39db740…` 对应同一内容） |
| 合并后 blob 复核 | `git rev-parse e89814a:artifacts/50-implementation/build-baseline.md` = `c39db740ae1166cde13efa6a58dcd6e881b2cc6b`，与来源分支同路径 blob 完全一致 |
| 门禁附带约束 | D-018（后续任务写范围须含 `entry/src/test/**` 以取得可运行单测证据）；设备级运行证据长期 BLOCKED（T-19/Stage Gate 如实列入）；`tools/build/**` ignore/tracked 状态需后续以 `-f` 或 P2 轮次细化规则处理 |

## 5. 冲突与合并后复核

- **冲突解决记录：无冲突** —— `ort` 策略直接完成合并；无手工解决、无 `reset`、无 `rebase`、无强制操作。
- 合并后拓扑：`b08646b → e89814a`（双亲 `b08646b` + `83c60db`）；`task/wp-006-build-baseline` 仍 @ `83c60db`（引用未移动）。
- 合并后工作区：干净（`git status --porcelain` 无输出；证据提交另行创建）。
- 其他分支引用未变：`main` @ `a6f6558`、`task/wp-001-intake` @ `fc66ec4`、`task/wp-002-fixture-validation` @ `e2d32b3`、`task/wp-003-consistency` @ `07687fd`、`task/wp-004-contracts` @ `697762c`、`task/wp-005-plan` @ `6699173`；`task/wp-006-build-baseline` @ `83c60db`；未创建 worktree（`git worktree list` 仅主工作区）；未 push。

## 6. 新任务分支与下一步

- 按 handoff 步骤 5，`finish` 通过后从汇总分支新 tip（证据提交）创建：**`task/wp-007-readme`**（`git branch`，不切换；当前分支保持 `feat/yaocore-app`）。
- 其 tip = 证据提交（本报告所在提交）——因创建发生在证据提交之后且不产生新提交，完整 SHA 可由 `git rev-parse task/wp-007-readme` 复核，并记录于守卫 finish 记录。
- **下一步建议**：
  1. Orchestrator 运行 `python3 scripts/swe_guard.py status` 确认 `wp-006-merge` 已归档（无活动任务）。
  2. 按 G-009 Next action 派发 **T-02 README-001 v0.1（technical-writer）** 于 `task/wp-007-readme`（需按守卫流程 pin + begin；handoff 声明 `task_branch: task/wp-007-readme`、`parent_branch: feat/yaocore-app`；命令块直接复用 `artifacts/50-implementation/build-baseline.md` §7）。
  3. T-05（TEST-001）交接必须含 `entry/src/test/**` 与 host 单测路径实证（D-018）。
  4. 后续小任务逐一经 `feat/yaocore-app` 汇总；全部完成后，因 `main_merge_mode: review_request_when_remote` 且存在 `origin`，须经托管平台 PR/MR（独立评审 + 必需 CI + 讨论解决）合并至受保护 `main`；守卫将拒绝本地 main merge。
