# wp-086 合并集成报告（task/wp-086-docs → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-086-merge（repository_action: merge）
- **Handoff**: `state/handoffs/wp-086-merge.json`（pin + snapshot + begin 已完成；本报告提交后运行 `finish wp-086-merge`）
- **日期**: 2026-10-18
- **结果**: **MERGE 成功（`--no-ff`，无冲突）；合并后两项指定验证全部 PASS（host 697/697、clean 构建成功）**。本报告是集成证据，**不替代任何 Gate 判定**，也不表示 T-21 文档已通过 Stage Gate。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree） |
| 目标分支 | `feat/yaocore-app` @ `13dc8393a54031b768bcef876e0220987aa5a2f6`（= handoff `base_commit`；合并前 HEAD 即此，任务期间未切换） |
| 来源分支 | `task/wp-086-docs` @ `fd35fd708e10fe1f2b1a8b7c2486d576c45db146`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `13dc839`（目标 tip；目标 tip 是来源的直接祖先，可 `--no-ff` 合并） |
| 工作区 | 干净（`git status --porcelain` 无输出） |
| 守卫状态 | ACTIVE `wp-086-merge`（begin 已完成）；无其他活动任务 |
| 快照 | `refs/swe/snapshots/20261017T200400Z-wp-086-merge-7d33b8be` @ `264b2fe497439546a3b15843982926efa3cbba54`；来源任务快照 `refs/swe/snapshots/20261017T195801Z-wp-086-docs-0e317534` @ `bd49bf709045ba846560b23790f06de68604739a` |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；本次**未 push、未 fetch**，未改写任何远端跟踪引用（合并仅本地 task → 汇总分支） |
| 本地 `main` | 未移动、未读取改动 |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- `gate_evidence_path` `README.md`：来源提交 `fd35fd7` 中 sha256 `355f8f33de4bd13cb5a15871f626b698724756da37892e8696c107dadabe1b5b`（= handoff `gate_evidence_path_sha256`；合并后工作树 blob `8ae011b27ed69d70d9219c96def22d76284c9bf0`，与来源一致）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用 `config/git-policy.default.md` 默认规范，无公司策略覆盖）

## 2. 来源与预检

来源分支仅 1 个提交（`git log --oneline 13dc839..fd35fd7`）：

```text
fd35fd7 docs(readme): 更新交付状态与维护计划
```

预检结果：目标工作区干净；来源 tip 精确等于 handoff `source_commit`；目标 tip 为来源直接祖先（无分叉）。`git diff --stat 13dc839..fd35fd7` 为 **2 个路径，+564 / −84**，全部落在 handoff `writes`（`README.md`、`artifacts/80-maintenance/`）内。

## 3. 合并

- 命令：`git merge --no-ff task/wp-086-docs -m "chore(merge): 合并 T-21 文档收尾到 feat/yaocore-app"`
- 合并提交：`942b7513a988e8d4ba0a0ac51cd083166eff1349`（主题 `chore(merge): 合并 T-21 文档收尾到 feat/yaocore-app`）
- 父提交：`13dc839`（目标，第一父）+ `fd35fd7`（来源，第二父）
- 策略：`ort`；**无冲突**（未手工编辑任何文件）
- 树一致性：目标自 base 后无独立提交，`git diff --quiet 942b751 fd35fd7` 通过，合并结果树与来源 tip 完全一致

## 4. 变更统计（`13dc839..942b751`）

| 路径 | 文件数 | + | − | 说明 |
|---|---:|---:|---:|---|
| `README.md` | 1 | 193 | 84 | 从脚手架描述更新为已实现 App 状态；补充 v1 范围、安全边界、验证命令、已知限制、仓库结构与文档入口 |
| `artifacts/80-maintenance/maintenance-plan.md` | 1（新增） | 371 | 0 | `MAINTENANCE-PLAN-001` v1.0：维护待办、风险接受、验证矩阵与文档修订机制（C-013） |
| **合计** | **2** | **564** | **84** | 与 handoff `writes` 一致；未触及代码、构建配置、契约、测试或 `input/` |

## 5. 合并后验证（在 `942b751` 上执行，早于证据提交且不含任何代码改动）

| # | 检查 | 命令 | 结果 |
|---|---|---|---|
| 1 | Host 测试 | `bash entry/src/test/run-host-tests.sh` | ✅ **697/697 PASS**（`1..697`、`# pass 697 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`，exit 0，duration ≈ 2987.4 ms） |
| 2 | 构建 | `hvigorw clean assembleHap --no-daemon` | ✅ **BUILD SUCCESSFUL in 14 s 595 ms**（35 tasks：34 executed / 1 up-to-date；仅既有 ArkTS 警告与“未配置 signingConfigs，跳过签名”提示，均为预期；unsigned HAP） |
| 3 | 工作区 | `git status --porcelain` | ✅ 干净（构建产物均被忽略） |

说明：上述为 handoff 指定的两项合并后验证；未复跑 codelinter、i18n strict、协议 crosscheck、layering 与设备矩阵。文档合并不改变代码，验证用于确认集成分支在合并 revision 上仍可构建、Host 测试仍全绿。

## 6. 冲突

**无冲突**。`ort` 自动合并；目标 tip 是来源 tip 的直接祖先；2 个路径为 1 个既有文件修改 + 1 个新文件，无删除、无重叠修改。

## 7. 门禁引用

- 门禁证据：`README.md`（来源提交 `fd35fd7`，sha256 `355f8f33de4bd13cb5a15871f626b698724756da37892e8696c107dadabe1b5b` = handoff pin；Producer `agent:technical-writer`，Status ACTIVE，适用代码基线 `13dc839`）。
- 配套交付物：`artifacts/80-maintenance/maintenance-plan.md`（`MAINTENANCE-PLAN-001` v1.0，Producer `agent:technical-writer`；明确声明“不授予任何 Gate PASS”）。
- 内容要点：README 从“脚手架 + Hello World”更新为 v1 已实现状态，如实区分 `PASS` / `COMPILED_ONLY` / `MOCK_ONLY` / `BLOCKED` / `UNAVAILABLE`；维护计划登记设备 / 真实网络验证、端口位置迁移、i18n 历史文案、固件协同与文档维护等待办及风险接受。
- 结论：合并只表示 T-21 文档收尾已进入集成分支，**不构成 Gate PASS**；IG / G-013 / G-014 及 Stage Gate 判定归 Stage 流程。

## 8. 证据提交与分支

- 本报告单独提交（主题 `chore(repo): 记录 wp-086 合并集成证据`，第一父为合并提交 `942b751`；仅包含 `state/reports/wp-086-merge-report.md`）。该提交 SHA 无法写入自身，由 `git rev-parse HEAD` / `finish` 记录读取。
- `finish wp-086-merge` 通过后，从该证据提交 tip 创建（不切换）`task/wp-087-integration`，其 tip 恒等于本证据提交 SHA。

## 9. 后续建议

1. 由 Orchestrator 在 `feat/yaocore-app` 上安排下一任务分支 `task/wp-087-integration`（已按要求从证据提交 tip 创建）。
2. 设备 / 真实 BLE / LAN / TLS / 云 / 视觉 / fps 验证由用户按维护计划设备矩阵执行；仓库侧不得将其改写为 PASS。
3. 端口物理迁移、i18n 历史文案收口与固件协同项按 `MAINTENANCE-PLAN-001` 另立任务；迁移后逐条归零 `port_exceptions_used` 并删除对应登记。
4. 汇总分支后续对 `main` 的集成仍按 `main_merge_mode: review_request_when_remote` 走 PR/MR（不得本地直并 `main`）。
