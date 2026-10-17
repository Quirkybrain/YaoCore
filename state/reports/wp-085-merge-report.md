# wp-085 合并集成报告（task/wp-085-tooling → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-085-merge（repository_action: merge）
- **Handoff**: `state/handoffs/wp-085-merge.json`（pin + snapshot + begin 已完成；本报告提交后运行 `finish wp-085-merge`）
- **日期**: 2026-10-18
- **结果**: **MERGE 成功（`--no-ff`，无冲突）；合并后四项指定验证全部 PASS（host 697/697、clean 构建成功、layering violations=0/pending=0、fixture 10/10）**。本报告是集成证据，**不替代 IG / G-013 / G-014 Stage Gate 判定**，也不表示端口迁移已完成。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree） |
| 目标分支 | `feat/yaocore-app` @ `1cd79986aab2b974855e111de79dd77007c12427`（= handoff `base_commit`；合并前 HEAD 即此，任务期间未切换） |
| 来源分支 | `task/wp-085-tooling` @ `d69ad61613cc63042e84ad604c4e0896ee1af65d`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `1cd7998`（目标 tip；`git merge-base --is-ancestor 1cd7998 d69ad61` 通过，来源可直接 `--no-ff` 合并） |
| 工作区 | 干净（`git status --porcelain` 无输出） |
| 守卫状态 | ACTIVE `wp-085-merge`（begin 已完成）；无其他活动任务 |
| 快照 | `refs/swe/snapshots/20261017T195637Z-wp-085-merge-75d09ca3` @ `870cdf0c4e13aedfff0ce06d0c74d686799697d6`；来源任务快照 `refs/swe/snapshots/20261017T194845Z-wp-085-tooling-2c8cde5a` @ `006de2cef5c87522f2810a5d4704e253629e418b` |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；本次**未 push**、未 fetch 也未改写任何跟踪分支（合并仅本地 task → 汇总分支） |
| 本地 `main` | 未移动、未读取改动 |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- `gate_evidence_path` `artifacts/60-testing/tooling-cleanup-report.md`：来源提交 `d69ad61` 中 sha256 `a59242405177e62f4f967bf4130ee78f9d6a2a6b94c5d5b8b69898405bdae002`（= handoff `gate_evidence_path_sha256`，合并后复算一致）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用 `config/git-policy.default.md` 默认规范，无公司策略覆盖）

## 2. 来源与预检

来源提交（`git log --oneline 1cd7998..d69ad61`，单提交）：

```text
d69ad61 test(contract): 收口分层例外与工具语义
```

预检结果：目标工作区干净；来源 tip 精确等于 handoff `source_commit`；目标 tip 是来源的直接祖先（无分叉）。`git diff --stat 1cd7998..d69ad61` 为 **52 个路径，+7430 / −155**，全部落在 handoff `writes`（`tools/contract/`、`entry/src/test/`、`artifacts/60-testing/`、`entry/src/main/ets/service/`）内。

## 3. 合并

- 命令：`git merge --no-ff task/wp-085-tooling -m "chore(merge): 合并 T-20 工具收口到 feat/yaocore-app"`
- 合并提交：`59a2506e5b308643487a66b2b5f04a449c7f26b5`（主题 `chore(merge): 合并 T-20 工具收口到 feat/yaocore-app`）
- 父提交：`1cd7998`（目标，第一父）+ `d69ad61`（来源，第二父）
- 策略：`ort`；**无冲突**（未手工编辑任何文件）
- 树一致性：目标自 base 后无独立提交，合并结果树与来源 tip 完全一致

## 4. 变更统计（`1cd7998..59a2506`）

| 路径/类别 | 文件数 | + | − |
|---|---:|---:|---:|
| `tools/contract/`（check_layering 检查器、`layering_allowlist.json`、fixture 自测、fixtures、README） | 28 | 944 | 120 |
| `entry/src/test/`（evidence 日志/TAP/JSON、host 测试、i18n 检查器与 fixture） | 20 | 6384 | 14 |
| `artifacts/60-testing/`（tooling-cleanup-report、test-plan、test-report） | 3 | 94 | 5 |
| `entry/src/main/ets/service/`（`MockGatewayService.ets` 退役别名对齐） | 1 | 8 | 16 |
| **合计** | **52** | **7430** | **155** |

## 5. 合并后验证（在 `59a2506` 上执行，早于证据提交且不含任何代码改动）

| # | 检查 | 命令 | 结果 |
|---|---|---|---|
| 1 | Host 测试 | `bash entry/src/test/run-host-tests.sh` | ✅ **697/697 PASS**（`1..697`、`# pass 697 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`，exit 0，duration ≈ 2964.4 ms） |
| 2 | 构建 | `hvigorw clean assembleHap --no-daemon` | ✅ **BUILD SUCCESSFUL in 14 s 338 ms**（35 tasks：34 executed / 1 up-to-date；仅既有 ArkTS 警告与“未配置 signingConfigs，跳过签名”提示，均为预期；unsigned HAP） |
| 3 | 分层检查 | `python3 tools/contract/check_layering.py` | ✅ `files=209 violations=0 exceptions_used=13 pending=0 pending_used=0 port_exceptions_used=10 port_pending=0 port_pending_used=0`；**PASS**，exit 0 |
| 4 | 检查器 fixture 自测 | `python3 tools/contract/test_check_layering.py` | ✅ **Ran 10 tests ... OK**（10/10），exit 0，用时 1.540 s |
| 5 | 工作区 | `git status --porcelain` | ✅ 干净（构建产物均被忽略） |

说明：上述为 handoff 指定的四项合并后验证；未复跑 codelinter、i18n strict、协议 crosscheck 与设备矩阵。`check_layering` 的 0 violation 含**已登记的版本化例外**（13 条 D-12 + 10 条实际使用的端口位置例外），**不等于端口物理位置合规**；端口迁移仍未执行，属独立任务。

## 6. 冲突

**无冲突**。`ort` 自动合并；目标 tip 是来源 tip 的直接祖先；52 个路径均为新增或既有文件增量修改，无删除、无重叠修改。

## 7. 门禁引用

- 门禁证据：`artifacts/60-testing/tooling-cleanup-report.md`（`TOOLING-CLEANUP-REPORT-001`，Producer `agent:test-engineer`；来源提交 `d69ad61`，sha256 `a59242405177e62f4f967bf4130ee78f9d6a2a6b94c5d5b8b69898405bdae002` = handoff pin）。
- 内容要点：F-01..F-06 全部工具侧 CLOSED——端口位置 17 条例外改为 allowlist 读取、13 条 `T20-D12-01..13` 置 `accepted` 并强制状态、ACK p95 报告数字与证据对齐、Mock 退役别名对齐、`--strict-ui` 成为真实门禁、补齐 D-03/D-05 与端口例外 fixture；来源分支上 8 项验证（含 host 697/697、fixture 10/10、layering 0/0、crosscheck 66/66、i18n 0 blocking）已实际执行。
- 结论：合并只表示 T-20 工具收口已进入集成分支，**不构成 Gate PASS**；IG / G-013 / G-014 判定归 Stage 流程。

## 8. 证据提交与分支

- 合并后 `feat/yaocore-app` 新 tip：本证据提交（主题 `chore(repo): 记录 wp-085 合并集成证据`，第一父为合并提交 `59a2506`；仅包含本报告路径 `state/reports/wp-085-merge-report.md`）。该提交 SHA 无法写入自身，由 `git rev-parse HEAD` / `finish` 记录读取。
- `finish wp-085-merge` 通过后，从该证据提交 tip 创建（不切换）`task/wp-086-docs`，其 tip 恒等于本证据提交 SHA。

## 9. 后续建议

1. 由 Orchestrator 在 `feat/yaocore-app` 上安排 wp-086（文档任务）及其余待办任务的 `task/` 分支。
2. 端口物理迁移按 DES-A §27.6.3 的 P1..P4 另立任务；迁移后逐条归零 `port_exceptions_used` 并删除对应登记。
3. 汇总分支后续对 `main` 的集成仍按 `main_merge_mode: review_request_when_remote` 走 PR/MR（不得本地直并 `main`）。
