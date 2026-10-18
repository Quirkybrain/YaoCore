# wp-095 A1 端口迁移合并报告（task/wp-090-ports → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: `wp-095-merge-a1`（`repository_action: merge`）
- **Handoff**: `state/handoffs/wp-095-merge-a1.json`（pin + snapshot + begin 已完成；本报告提交后运行 `finish wp-095-merge-a1`）
- **日期**: 2026-10-18
- **结果**: **MERGE 成功（`--no-ff`，无冲突）；合并结果上六项验证全部退出 0（host 697/697、layering 0 violation、fixture 22/22、i18n 0 blocking、crosscheck hard ALL PASS、clean assembleHap BUILD SUCCESSFUL）**。本报告是集成证据，**不替代任何 Gate 判定**。**注意**：任务要求与本 handoff 的 `deliverables` 存在契约冲突，`finish` 预计在证据提交路径检查处阻塞；详见 §8 与任务返回。

## 1. 预检（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree；任务期间未建新 worktree） |
| 当前分支 | `feat/yaocore-app`（= handoff `base_branch`；未切换） |
| 目标 HEAD | `1d4b202a8ee68acb1679e9c7472c883e0e30ca9e`（= handoff `base_commit`、`feature/yaocore-app` tip） |
| 来源分支 | `task/wp-090-ports` @ `0eda9933a0b3d52a1a8a429b05b2587d19583105`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `1d4b202`（目标 tip 是来源 tip 的直接祖先，无分叉） |
| 工作区 | 干净（`git status --porcelain` 无输出）；HEAD 未脱离 |
| 守卫状态 | ACTIVE `wp-095-merge-a1`（begin 已完成）；无其他活动任务 |
| 快照 | begin 前已创建 3 个本地快照 refs（`20261018T015908Z-wp-095-merge-a1-8b617a99`、`20261018T015916Z-...-0abba79d`、`20261018T015921Z-...-81def1c9`）；begin 校验通过，本任务未改写快照 |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；按任务要求**未 push、未 fetch、未 pull**，未改写任何远端跟踪引用 |
| 其他分支 | `main` @ `a6f6558` 与全部 `task/*` 均未移动、未切换、未删除；`task/wp-090-ports` 保留 |

冻结输入哈希复核（与 handoff pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- `gate_evidence_path` `artifacts/70-review/t23-rereview.md`：来源 `0eda993` 与合并后工作树 sha256 均为 `f1bc436e4730a01f197f1a3b1c0537d55a25303d4da7043095b76d6e79ab3b13`（= handoff `gate_evidence_path_sha256`）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用 `config/git-policy.default.md` 默认规范，无公司策略覆盖）

来源提交核对（`git log --oneline 1d4b202..0eda993`，5 个，与任务描述一致）：

```text
aa9bdd1 refactor(contracts): 迁移端口到 contracts 并收口例外
f290f69 docs(review): A1 端口迁移独立评审
76c47f4 docs(design): T-23 裁定与端口契约同步
cc2233d fix(contracts): 应用 T-23 裁定并修复 ohosTest imports
0eda993 docs(review): T-23 修复聚焦复评
```

## 2. 合并

- 命令：`git merge --no-ff task/wp-090-ports -m "merge: A1 端口迁移与 T-23 裁定修复"`
- 合并提交：`54f2a0b3a5e2b91dbc3cb66b08a85be0d8498782`（主题 `merge: A1 端口迁移与 T-23 裁定修复`）
- 父提交：`1d4b202`（目标，第一父）+ `0eda993`（来源，第二父）
- 策略：`ort`；**无冲突**（未手工编辑任何文件）
- 树一致性：目标自 base 后无独立提交，`git diff --quiet 54f2a0b 0eda993` 退出 0，合并结果树与来源 tip 完全一致
- 合并范围：`git diff --name-only 1d4b202 54f2a0b` 为 **215 个路径，+3407 / −2470**；全部落在 handoff `writes` 内（含端口迁移、T-23 裁定同步、review/实现报告与 checker fixture）；未触及 `input/`、构建配置或状态文件

## 3. 合并后验证（在 `54f2a0b` 上实际执行，早于任何证据改动）

| # | 检查 | 命令 | 实测结果 | 退出码 |
|---|---|---|---|---|
| 1 | Host 测试 | `entry/src/test/run-host-tests.sh` | **697/697 PASS**：`1..697`、`# tests 697 / # pass 697 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`；duration ≈ 3080.5 ms | 0 |
| 2 | 分层检查 | `python3 tools/contract/check_layering.py` | **PASS**：`files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0`（D-12 6 条 active；无端口位置例外被使用） | 0 |
| 3 | 分层夹具自测 | `python3 tools/contract/test_check_layering.py` | **Ran 22 tests in 2.112s / OK**（22/22） | 0 |
| 4 | i18n strict-ui | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | `blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16`；CHK-08/CHK-09 PASS | 0 |
| 5 | 协议资产交叉校验 | `python3 tools/contract/crosscheck_protocol_assets.py` | **hard checks: ALL PASS**；14 条既有 frozen-input findings（非阻塞，未改写冻结输入） | 0 |
| 6 | 构建 | `hvigorw clean assembleHap --no-daemon` | **BUILD SUCCESSFUL in 14 s 936 ms**；35 tasks（34 executed / 1 up-to-date）；unsigned HAP；仅既有 ArkTS 警告与“未配置 signingConfigs”提示 | 0 |

补充：以上命令均在合并提交的干净工作树上运行；构建产物位于 ignored `entry/build/`，运行后 `git status --porcelain` 仍为空。

## 4. 证据更新

- `artifacts/90-integration/integration-report.md` 追加 **§11「A1 合并记录（2026-10-18，wp-095）」**：源/目标分支、合并提交与双亲、5 个源提交、六项验证矩阵、残余（`PORT-LOC-01` OPEN、`RR-01..RR-04`、设备 BLOCKED）与边界声明。
- 追加内容不回写 §1–§10 在 `d2896fb` 上的历史结论；该文件同时是 T-22 的 `gate_evidence_path`，本次只做尾部增量，未修改既有章节。

## 5. 门禁引用

- 门禁证据：`artifacts/70-review/t23-rereview.md`（来源提交 `0eda993`，sha256 `f1bc436e…` = handoff pin；Producer `agent:quality-reviewer`，Verdict **PASS（仅限 `cc2233d` 与本次范围）**）。
- 内容要点：F-01..F-07 与 ohosTest import 修复按附录 E 落地；独立复验 8 项退出 0；`PORT-LOC-01` OPEN、`RR-01`/`RR-02` 为既有工具债、`RR-03`/`RR-04` 为文档/元数据一致性；不授予 Stage Gate、IG-3/IG-4 或用户验收。
- 结论：本次合并只表示 A1 端口迁移与 T-23 裁定修复已进入集成分支，**不构成 Gate PASS**；Stage Gate 判定归 Orchestrator。

## 6. 工作树与分支状态（报告提交后）

| 项 | 值 |
|---|---|
| 当前分支 / HEAD | `feat/yaocore-app` / 本报告提交（父提交 `54f2a0b`；SHA 由 `git rev-parse HEAD` 读取，无法写入自身） |
| 来源分支 | `task/wp-090-ports` @ `0eda993`，未删除、未移动 |
| 工作区 | 干净；本任务仅新增/修改 §4 与 §6 所列两个路径 |
| 未提交 / 未跟踪 | 无（ignored 构建产物除外） |
| 远端 | 未 push / fetch / pull；未创建 PR/MR |

## 7. 冲突

**无冲突**。`ort` 自动合并；目标 tip 是来源 tip 的直接祖先；215 个路径全部来自来源历史，无目标侧独立改动，无删除/重命名冲突。

## 8. Handoff 契约冲突（finish 阻塞点）

任务指令要求把 `artifacts/90-integration/integration-report.md` 与 `state/reports/wp-095-merge-report.md` **同一提交**暂存并执行 `finish`。但冻结 handoff 的 `deliverables` 仅含：

```json
"deliverables": ["state/reports/wp-095-merge-report.md"]
```

`swe_guard.py` 的 `check_merge_result()` 要求“合并后恰好一个证据提交，且该提交的每个路径都必须被 `deliverables` 覆盖”，否则报：

```text
merge evidence commit must contain only declared deliverables
```

同时，未提交的 `artifacts/90-integration/` 修改会触发 `merge output remains dirty: artifacts/90-integration/`。因此“追加集成报告 + 通过 finish”在**当前冻结 handoff 下不可同时满足**；这是 handoff 设计缺口（`deliverables` 应同时包含两个路径，或集成报告更新应在来源分支完成），不是代码/合并失败。

本任务按指令提交两个路径后运行 `finish`，实际错误原样记录在任务返回中；**未通过修改 handoff、改写守卫、amend 合并提交或 reset 等方式绕过**。

## 9. 残余风险与后续建议

1. **finish 未通过（handoff 契约）**：建议 Orchestrator 以 `finish wp-095-merge-a1 --failed` 关闭当前活动记录，并按“`deliverables` 含 `artifacts/90-integration/integration-report.md`”重新设计后续证据任务；或在不违反守卫语义的前提下手工接收本报告与合并提交，并在 Gate 记录中注明偏差。不得把本报告当作 Gate PASS。
2. **`PORT-LOC-01` OPEN**：`ClockPort`/`IdPort` 仍在 `common/types/Ports.ets`；关闭需批准的 D-01 或冻结签名变更；`used=0`。
3. **`RR-01..RR-04`**：分别为 `export * from` checker 覆盖缺口、行号/环诊断错位、实现报告文首/§7.2 与 §10 状态不一致、checker/allowlist 元数据仍标 wp-090；均为非阻塞，建议 bounded 工具/文档任务处理。
4. **设备/真实环境 BLOCKED**：ohosTest 仅编译；真实 BLE/LAN/TLS/云/视觉/A11y/fps 无设备、无模拟器、无签名，不得用 host/mock 外推为验收 PASS。
5. **后续集成**：汇总分支对 `main` 按 `main_merge_mode: review_request_when_remote` 走 PR/MR；在补齐 Stage Gate 证据前不得本地直并 `main`。
