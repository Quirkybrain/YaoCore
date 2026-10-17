# wp-004 合并集成报告（task/wp-004-contracts → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-004-merge（repository_action: merge）
- **Handoff**: state/handoffs/wp-004-merge.json（pin + begin 由 Orchestrator 完成；本报告所在提交后运行 finish）
- **日期**: 2026-10-17
- **结果**: SUCCESS —— `--no-ff` 合并完成、无冲突；恰好一个证据提交（本报告）；待守卫 `finish wp-004-merge` 归档。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore` |
| 目标分支 | `feat/yaocore-app` @ `54c1d7863bad779971b228b56767bb5542b2eca3`（= handoff `base_commit`） |
| 来源分支 | `task/wp-004-contracts` @ `697762c55cdd0e5eed275bcc07de21afb01d77e2`（= handoff `source_commit`，与 `git rev-parse` 实查一致） |
| 来源提交链 | `aaf4789` / `9e90175` / `2e61de9` / `697762c`（4 个提交，G-004 记录一致） |
| 合并基 | `git merge-base` = `54c1d7863bad779971b228b56767bb5542b2eca3`（即目标 tip；来源为线性追加） |
| 工作区 | 干净（`git status --porcelain` 无输出）；HEAD = 目标 tip；主分支 `main` @ `a6f6558` 未动 |
| 守卫状态 | ACTIVE `wp-004-merge`（begin 已由 Orchestrator 完成）；无其他活动交接 |
| 快照 | 无（handoff `snapshot_paths: []`；`artifacts/20-architecture/` 在目标分支首次引入，无前身文件需保护） |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；合并前 `git fetch origin --prune` 成功（仅更新远端跟踪引用，未切换/移动本地分支） |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- 策略：`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用默认规范）
- 门禁证据字节固定复核见 §4。

预检差异复核：`git diff --stat 54c1d78..697762c` = **7 files changed, 2087 insertions(+)**，全部为 `artifacts/20-architecture/` 下新增（`A`），与 handoff 声明一致。

## 2. 合并执行

按 pin 的策略 `merge_strategy: no-ff` 与 handoff 指定主题执行：

```text
git merge --no-ff task/wp-004-contracts -m "chore(merge): 合并 wp-004 契约基线到 feat/yaocore-app"
```

- 结果：`Merge made by the 'ort' strategy`；**无冲突**（未发生任何冲突解决、rebase、reset 或强制操作）。
- **merge 提交**：`1ece30ba408c274f6b14e69793e41a68bb0b2bc4`
- 主题：`chore(merge): 合并 wp-004 契约基线到 feat/yaocore-app`（与 handoff 指定主题逐字一致，无正文）
- 双亲验证（`git rev-list --parents -n 1 1ece30b`）：`^1 = 54c1d7863bad779971b228b56767bb5542b2eca3`（固定目标 tip）、`^2 = 697762c55cdd0e5eed275bcc07de21afb01d77e2`（固定来源 tip）
- 合并规模：**7 files changed, 2087 insertions(+), 0 deletions**，全部位于 handoff `writes: ["artifacts/20-architecture/"]` 范围内：

  ```text
  A  artifacts/20-architecture/adr-001-protocol-authority-and-error-semantics.md  (blob cbadc0c1f8baa85a983a4f452f5986790fd99532)
  A  artifacts/20-architecture/adr-002-lan-security-channel.md                    (blob ce49e3fea21dda71404cd4b33dba940c0eb690ca)
  A  artifacts/20-architecture/adr-003-family-credential-distribution.md          (blob 4414ddf2ad7723a4a0684d85a0f45a7f9887b66b)
  A  artifacts/20-architecture/adr-004-home-room-device-boundaries.md             (blob a3037651b396a717ba6e00ec74909a06dcc4800b)
  A  artifacts/20-architecture/contract-baseline.md                               (blob 6fa3baa981bea6199371daeb034008bf7880a06f)
  A  artifacts/20-architecture/i18n-resource-design.md                            (blob 24dfce96c77237588faf04a5abc4d0c35a5be729)
  A  artifacts/20-architecture/project-constraints.md                             (blob 6b434056b16505fce9d3416978e989f9016150d0)
  ```

- 内容一致性（`git diff task/wp-004-contracts 1ece30b` 为空）：合并树与来源 tip 逐字节一致；7 个 blob 与 `git ls-tree -r 697762c artifacts/20-architecture/` 完全相同。
- **无覆盖**：目标分支此前不存在 `artifacts/20-architecture/`，7 项均为 `A`（新增），无 `M`/`D`。

## 3. 证据提交（恰好一个，紧随 merge 提交）

- 提交主题：`chore(repo): 记录 wp-004 合并集成证据`
- 唯一变更路径：`state/reports/wp-004-merge-report.md`（本报告；`state/` 被 `.gitignore` 忽略，以 `git add -f` 显式暂存，且暂存集仅此一个路径）
- 提交前检查：`git diff --cached --check` 通过（无空白错误）
- 提交后复核：`git show --stat` 仅含单文件；本提交为 merge 提交 `1ece30b` 的唯一直接后继（`git rev-list --first-parent 1ece30b..HEAD` 长度为 1）
- **证据提交自身 SHA 说明**：提交内容无法内嵌其自身哈希（哈希自引用不可满足），故此处不给字面值。权威值即守卫 finish 写入 `state/handoffs/history/` 的 `result_commit` 字段；复核命令：`git log -1 --format=%H feat/yaocore-app`（= 本报告所在提交）。

## 4. 门禁证据引用（按来源提交固定）

| 项 | 值 |
|---|---|
| Gate | **G-004 Artifact Validation Gate — PASS**（Orchestrator 裁定，日期 2026-10-17 / revision `697762c`） |
| 门禁记录 | `state/gates/G-004-contract-baseline.md` |
| 门禁结论 | 契约基线 v1.0 对实现阶段 `VALID`；**ADR-001..004 状态 Accepted**；Project Constraints 与 i18n 资源设计生效为约束基线 |
| 来源分支已提交门禁工件 | `artifacts/20-architecture/contract-baseline.md` @ `697762c`（handoff `gate_evidence_path`） |
| 守卫 pin 的工件字节 | sha256 `6673a990d5020c0b70dd4ae30bd75fa13d33d4d573a4d953961371296fadee89`（合并前以 `git show 697762c:artifacts/20-architecture/contract-baseline.md \| sha256sum` 复核一致；合并后 blob `6fa3baa9…` 对应同一内容） |
| 合并后 blob 复核 | `git rev-parse 1ece30b:artifacts/20-architecture/contract-baseline.md` = `6fa3baa981bea6199371daeb034008bf7880a06f`，与来源分支同路径 blob 完全一致 |

注：ADR 文件头 `Status` 行仍写 `Proposed`，G-004 记录明确"Approved 状态以 Gate 记录为准，下次文档修订同步"；属非阻塞文档维护项，不改变本次合并合法性。

## 5. 冲突与合并后复核

- **冲突解决记录：无冲突** —— `ort` 策略直接完成合并；无手工解决、无 `reset`、无 `rebase`、无强制操作。
- 合并后拓扑：`54c1d78 → 1ece30b`（双亲 `54c1d78` + `697762c`）；`task/wp-004-contracts` 仍 @ `697762c`（引用未移动）。
- 合并后工作区：干净（`git status --porcelain` 无输出；证据提交另行创建）。
- 其他分支引用：`main` @ `a6f6558`、`task/wp-001-intake` @ `fc66ec4`、`task/wp-002-fixture-validation` @ `e2d32b3`、`task/wp-003-consistency` @ `07687fd` 均未被切换或移动；未创建 worktree（`git worktree list` 仅主工作区）；未 push。

## 6. 新任务分支与下一步

- 按 handoff 步骤 5，`finish` 通过后从汇总分支新 tip（证据提交）创建：**`task/wp-005-plan`**（`git branch`，不切换；当前分支保持 `feat/yaocore-app`）。
- 其 tip = 证据提交（本报告所在提交）——因创建发生在证据提交之后且不产生新提交，完整 SHA 可由 `git rev-parse task/wp-005-plan` 或 `git log -1 --format=%H feat/yaocore-app` 复核，并记录于守卫 finish 记录。
- **下一步建议**：
  1. Orchestrator 运行 `python3 scripts/swe_guard.py status` 确认 `wp-004-merge` 已归档（无活动任务）。
  2. 按 G-004 Next action 推进：派发 **wp-005 交付规划**（delivery-planner）于 `task/wp-005-plan`（需按守卫流程 pin + begin；handoff 声明 `task_branch: task/wp-005-plan`、`parent_branch: feat/yaocore-app`；输入为 G-004 批准的 7 份架构基线 + G-004 记录中的 TEST-001 口径与固件协同项）。
  3. 后续小任务逐一经 `feat/yaocore-app` 汇总；全部完成后，因 `main_merge_mode: review_request_when_remote` 且存在 `origin`，须经托管平台 PR/MR（独立评审 + 必需 CI + 讨论解决）合并至受保护 `main`；守卫将拒绝本地 main merge。
