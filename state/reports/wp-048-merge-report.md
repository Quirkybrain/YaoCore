# wp-048 合并集成报告（task/wp-048-des-format-fix → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-048-merge（repository_action: merge）
- **Handoff**: `state/handoffs/wp-048-merge.json`（pin + snapshot + begin 已完成；本报告提交后运行 `finish wp-048-merge`）
- **日期**: 2026-10-17
- **结果**: **MERGE 成功（`--no-ff`，无冲突）；合并后集成验证 PASS（host 451/451、构建成功）**。本次合并将 `wp-048-des-format-fix` 对 DES-A §3.2.3 的机读格式修复带回 `feat/yaocore-app`，关闭 CQG-T12 Post-merge finding（合并 `wp-040` 后 450/451 回归）。本报告是集成证据，**不替代 Stage Gate 判定**。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree） |
| 目标分支 | `feat/yaocore-app` @ `71fd072ee839084d3260da7ddfbc5b87b32523c1`（= handoff `base_commit`；合并前 HEAD 即此） |
| 来源分支 | `task/wp-048-des-format-fix` @ `cd486b0695375e243dffb57da6ea724c2c31cc36`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `71fd072`（目标 tip；来源为基于该 tip 的线性单提交，仍按策略强制 `--no-ff`） |
| 工作区 | 干净（`git status --porcelain=v1 --untracked-files=all` 无输出） |
| 守卫状态 | ACTIVE `wp-048-merge`（begin 已完成）；合并前无其他活动任务 |
| 快照 | `refs/swe/snapshots/20261017T134918Z-wp-048-merge-81e74968` @ `c982762c7f99b8705d6f85fabb1ffe611830b951`；来源任务快照 `refs/swe/snapshots/20261017T134722Z-wp-048-des-format-fix-e53b1110` @ `db12474efebacc269c8dcb2bac73fe19b5f1f117` |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；已执行 `git fetch --prune`（无错误）；`origin/main` @ `7d6f4c99fa1bf0baf5e40d1948a97f564a647401`；远端无 `feat/yaocore-app`；本次**未 push** |
| 本地 `main` | `a6f6558`（未移动） |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- `gate_evidence_path` `artifacts/40-detailed-design/des-001a-foundation-transport.md` sha256 `3932dac62252b040330858d530c1f8988a83ba4185d0ce5e42bc736a05069600`（在来源 tip 与合并后 tip 上实查一致，= handoff `gate_evidence_path_sha256`）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用 `config/git-policy.default.md` 默认规范，无公司策略覆盖）

## 2. 来源与预检

- 来源仅 **1 个提交**：`cd486b0` `docs(design): 修复 DES-001A 代码表机读格式`；父提交即 `71fd072`。
- `git diff --stat 71fd072..cd486b0`：**1 file changed, 32 insertions(+), 3 deletions(-)**；`--name-status` 仅 `M artifacts/40-detailed-design/des-001a-foundation-transport.md`，无新增/删除/重命名，**无范围外文件**。
- 修复内容（仅格式，不改语义）：§3.2.3 两个 code 单元格恢复裸 code（`CONTROL_RESPONSE_AUTH_FAILED`、`ACK_CORRELATION_MISMATCH`），原行级注记移至表后 blockquote“表注（行级，T-12 裁定）”；附录 D 记录根因、修改点、验证证据与残余。表头/列结构、i18n 键映射、T-12 裁定语义、CB §4.5 引用均未改变。
- 未修改任何代码、测试、locale 资源或其他 Artifact。

## 3. 合并执行

按 pin 的 `merge_strategy: no-ff` 与 handoff 指定主题执行：

```text
git merge --no-ff task/wp-048-des-format-fix -m "chore(merge): 合并 DES-001A 机读格式修复到 feat/yaocore-app"
```

- 结果：`Merge made by the 'ort' strategy`；**无冲突**（未发生 rebase、reset、amend、force 或 worktree 操作）。
- **merge 提交**：`d6377e6dd468338a4f6f579db6d61c493746be22`
- 主题：`chore(merge): 合并 DES-001A 机读格式修复到 feat/yaocore-app`（与 handoff 指定主题逐字一致）
- 双亲验证（`git rev-list --parents -n 1 d6377e6`）：`^1 = 71fd072ee839084d3260da7ddfbc5b87b32523c1`（固定目标 tip）、`^2 = cd486b0695375e243dffb57da6ea724c2c31cc36`（固定来源 tip）
- 合并规模：**1 file changed, 32 insertions(+), 3 deletions(-)**，与预检 diff 完全一致。
- 内容一致性：`git diff --quiet cd486b0 d6377e6` 通过（exit 0）—— 合并结果树与来源 tip **逐字节相同**。

## 4. 合并后集成验证（PASS）

### 4.1 Host 测试

```text
bash entry/src/test/run-host-tests.sh
# tests 451 / suites 0 / pass 451 / fail 0 / cancelled 0 / skipped 0
# duration_ms 2039.355386
# 关键回归项：ok 358 - T10_C14_authoritativeCatalog_everyDeclaredCodeHasBothLocaleKeys
```

- **451/451 PASS，0 fail**。wp-040 合并后出现的 `T10_C14` 解析回归（94 ≠ 96）已消失；`CONTROL_RESPONSE_AUTH_FAILED` 与 `ACK_CORRELATION_MISMATCH` 两行重新被 `parseDeclaredCodes` 识别。
- 该脚本只读；运行后工作区仍干净（`git status --porcelain=v1 --untracked-files=all` 无输出）。

### 4.2 构建

```text
hvigorw clean assembleHap --no-daemon
# BUILD SUCCESSFUL in 5 s 127 ms
# 35 tasks in total: 34 executed, 1 up-to-date
```

- 唯一告警：`WARN: Will skip sign 'hos_hap'. No signingConfigs profile is configured in current project.`（既有环境限制，非本次合并引入；不影响 HAP 组装成功）。

## 5. Gate 引用与修复闭环

- **触发 finding**：CQG-T12 **Post-merge integration finding** —— `wp-040` 合并 `49f720c` 至 `71fd072` 后，`T10_C14_authoritativeCatalog_everyDeclaredCodeHasBothLocaleKeys` 因 DES-A §3.2.3 两个 code 单元格内联注记导致 `parseDeclaredCodes` 解析数 **94（期望 96）**，host 为 **450/451**。
- **修复任务**：`wp-048-des-format-fix`（solution-architect）@ `cd486b0`，仅调整 DES-A §3.2.3 表格格式并保留全部裁定语义（附录 D）。
- **修复证据**：`gate_evidence_path` 合并后 sha256 `3932dac6…69600`；合并后 host **451/451**（含上述 `T10_C14`）；构建成功。CQG-T12 的 451/451 证据现已在 `feat/yaocore-app` 新 tip 上复现，**可由 Stage Gate 补记关闭**。
- **仍按 CQG-T12 条件跟踪的残余**（本任务范围外，未改变其状态）：
  - C-20 mock 错误码对齐；
  - DES-001B §10.2 / C-23 同步。
- 本次合并的集成结论**不自动等于 Stage Gate 通过**；`main_merge_mode: review_request_when_remote` 仍要求后续经 hosted PR/MR 与 CI/评审后才可进入 protected `main`。

## 6. 文件清单

合并提交 `d6377e6`（相对 `71fd072`）：

| 状态 | 路径 | 变更 |
|---|---|---|
| M | `artifacts/40-detailed-design/des-001a-foundation-transport.md` | +32 / −3 |

本证据提交（仅 1 个文件，`git add -f`，因 `/state/` 被 `.gitignore` 忽略）：

| 状态 | 路径 | 说明 |
|---|---|---|
| A | `state/reports/wp-048-merge-report.md` | 本报告；`git diff --cached --check` 通过 |

除上述文件外，本任务未修改代码、测试、locale、配置或其他 Artifact。

## 7. 冲突与偏差

- **冲突**：无。合并为 clean merge，未手工编辑合并结果。
- **范围/边界**：未 push；未切换、移动或删除任何其他分支（`main`、`task/wp-040-ble`、`task/wp-047-family`、来源分支均保持原位）；未创建/移除 worktree；未使用 reset/force；未提交来源分支之外的内容。
- **流程说明**：为让本报告记录真实结果，合并后先运行 host 测试与构建，再撰写并提交本报告；证据提交仍恰好一个且仅含本报告，符合 handoff 交付范围。
- **元数据**：handoff 的 `writes` 为 `artifacts/40-detailed-design/`，本报告通过 handoff `deliverables` 与 `snapshot_paths` 授权以 `git add -f` 提交，未扩大产品范围。

## 8. 新分支与下一步

- 本报告提交后，从同一新 tip 创建（不切换）：`git branch task/wp-049-family`。该分支 tip **等于本报告提交 SHA**（可在 `git rev-parse task/wp-049-family` 复核；旧 `task/wp-047-family` 停在 `71fd072` 的红色 tip，已忽略且未移动）。
- **下一步建议**：
  1. Stage Gate 补记 CQG-T12 Post-merge finding 关闭（引用本报告 §4.1 的 451/451 与 merge `d6377e6`）。
  2. 在 `task/wp-049-family` 上继续 wp-049（family 相关任务），保持每个小任务独立 worktree/分支。
  3. 仅当 `feat/yaocore-app` 的集成/回归、独立评审与 Stage Gate 全部通过后，再按 `main_merge_mode: review_request_when_remote` 发起 hosted PR/MR；在此之前**不 push、不合入 `main`**。
  4. 继续跟踪 C-20 mock 对齐与 DES-001B §10.2/C-23 同步两项残余。

---

*本报告由 repository-manager 生成，作为 wp-048 合并的持久集成证据；验证结论绑定于 `feat/yaocore-app` @ 本报告提交的父提交 `d6377e6` 及其内容哈希。*
