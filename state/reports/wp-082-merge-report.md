# wp-082 合并集成报告（task/wp-082-verify → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-082-merge（repository_action: merge）
- **Handoff**: `state/handoffs/wp-082-merge.json`（pin + snapshot + begin 已完成；本报告提交后运行 `finish wp-082-merge`）
- **日期**: 2026-10-18
- **结果**: **MERGE 成功（`--no-ff`，无冲突）；合并后集成验证 PASS（host 696/696、clean 构建成功、layering 0 violation）**。本次合并将 T-19 全量测试矩阵、覆盖证据与 C-29 分层检查器带入 `feat/yaocore-app`。本报告是集成证据，**不替代 G-014 Stage Gate / T-20 独立评审判定**。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree） |
| 目标分支 | `feat/yaocore-app` @ `4f7c26be664a8db8aaba136fce1f128ccc72223a`（= handoff `base_commit`；合并前 HEAD 即此） |
| 来源分支 | `task/wp-082-verify` @ `7f9ac217a94b1e355b9aac6473d8d993db505f42`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `4f7c26b`（目标 tip，`git merge-base` 实查；来源为单个线性提交，仍按策略强制 `--no-ff`） |
| 工作区 | 干净（`git status --porcelain` 无输出） |
| 守卫状态 | ACTIVE `wp-082-merge`（begin 已完成）；无其他活动任务 |
| 快照 | `refs/swe/snapshots/20261017T192754Z-wp-082-merge-f0e31543` @ `a4c504b141473a54989809672c39121fb2a4c137`，tree `6ae47a62d1fedabca353d7f9cf601ac163f6f36c`（`SWE snapshot wp-082-merge`，父提交 `4f7c26b`，捕获 handoff 声明的 `artifacts/60-testing/`、`entry/src/test/`、`tools/contract/` + handoff 本身） |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；已执行 `git fetch origin --prune`（exit 0）；`origin/main` @ `7d6f4c99fa1bf0baf5e40d1948a97f564a647401`；本次**未 push** |
| 本地 `main` | `a6f6558882f7ec53be548c85e15a1a291c5a41fd`（未移动） |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- `gate_evidence_path` `artifacts/60-testing/test-report.md` sha256 `55944200d1393f92d1edc65cecb939f144f82aec8fa084c6af5614e73cbb3a85`（= handoff `gate_evidence_path_sha256`；合并后树中复核一致）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用 `config/git-policy.default.md` 默认规范，无公司策略覆盖）

## 2. 来源与预检

来源提交（`git log --oneline 4f7c26b..7f9ac21`，单提交，与任务说明实查一致）：

```text
7f9ac21 test(verify): 全量测试矩阵与覆盖证据
```

预检结果：目标工作区干净；来源 tip 精确等于 handoff `source_commit`；目标 tip 是来源 tip 的直接祖先（`git merge-base` = `4f7c26b`，无分叉）；`git diff --stat 4f7c26b..7f9ac21` 为 **59 files changed, 8321 insertions(+), 1 deletion(-)**，路径全部落在 handoff `writes`（`artifacts/60-testing/`、`entry/src/test/`、`tools/contract/`）内，与交接描述一致。

## 3. 合并

- 命令：`git merge --no-ff task/wp-082-verify -m "chore(merge): 合并 T-19 全量验证证据到 feat/yaocore-app"`
- 合并提交：`8a3509ad6973a13095aba409dc98cf6f4ea47689`（主题 `chore(merge): 合并 T-19 全量验证证据到 feat/yaocore-app`）
- 父提交：`4f7c26b`（目标，第一父）+ `7f9ac21`（来源，第二父）
- 策略：`ort`；**无冲突**（未手工编辑任何文件）
- 树一致性：`git diff --stat 7f9ac21..8a3509a` 为空，即合并结果树与来源 tip 完全一致（目标自 base 后无独立提交）

## 4. 变更统计（`4f7c26b..8a3509a`，按目录）

| 目录 | 文件数 | + | − |
|---|---:|---:|---:|
| `artifacts/60-testing/`（`test-plan.md` 更新 + `test-report.md` 新增） | 2 | 300 | 1 |
| `entry/src/test/`（20 个 evidence 日志/TAP/JSON + host `ViewModelDevice.test.mjs`） | 20 | 6861 | 0 |
| `tools/contract/`（`check_layering.py`、allowlist、`test_check_layering.py`、`measure_ack_latency.py`、33 个 fixture `.ets`） | 37 | 1160 | 0 |
| **合计** | **59** | **8321** | **1** |

`tools/contract/` 明细：`check_layering.py` +726、`layering_allowlist.json` +139、`measure_ack_latency.py` +152、`test_check_layering.py` +67、`fixtures/layering/{bad,good}/**` 33 文件 +76。

## 5. 合并后验证（在 `8a3509a` 上执行）

| 检查 | 命令 | 结果 |
|---|---|---|
| Host 测试 | `bash entry/src/test/run-host-tests.sh` | ✅ **696/696 PASS**（`1..696`、`# pass 696 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`，exit 0，duration ≈ 2972 ms） |
| 构建 | `hvigorw clean assembleHap --no-daemon` | ✅ **BUILD SUCCESSFUL in 14 s 618 ms**（35 tasks：34 executed / 1 up-to-date；仅既有 ArkTS 警告与“未配置 signingConfigs，跳过签名”提示，均为预期；unsigned HAP） |
| 分层静态扫描（C-29） | `python3 tools/contract/check_layering.py` | ✅ **PASS**：`files=209 violations=0 exceptions_used=13 pending=13`，exit 0（13 条 `pending-T-20` D-12 例外可见，与 T-19 证据一致） |
| 工作区 | `git status --porcelain` | ✅ 干净（构建产物均被忽略） |

说明：本次未复跑 codelinter、i18n checker、协议 crosscheck、仿真器套件与 fixture 自测；其证据沿用 T-19 来源提交（`7f9ac21`）且合并树与来源树一致（§3）。设备/模拟器/真实 BLE/LAN/TLS/云/视觉/fps 仍按 `test-report.md` 保持 **BLOCKED/UNAVAILABLE**；ACK p95 仅有 **MOCK_ONLY** 值。

## 6. 冲突

**无冲突**。`ort` 自动合并；目标 tip 是来源 tip 的直接祖先；全部 59 路径为新增或以来源版本线性更新；无删除文件，无重叠修改。

## 7. 门禁引用

- 门禁证据：`artifacts/60-testing/test-report.md`（TEST-REPORT-001，Producer `agent:test-engineer`，Status `COMPLETE`，供 T-20 独立评审、IG-4 与 G-014 Stage Gate 消费；**不授予 Gate PASS**），sha256 `55944200d1393f92d1edc65cecb939f144f82aec8fa084c6af5614e73cbb3a85`。
- 该报告记录的 T-19 结果：host **696/696 PASS**、crosscheck **66/66 PASS**、仿真器 **20/20 PASS**（`no_proxy=127.0.0.1`；默认代理首跑 `FAIL_ENV` 已留证）、i18n CHK-01..09 **全 PASS**、layering **0 violation（13 pending-T-20）**、构建 **BUILD SUCCESSFUL**、codelinter **0 error / 25 warning**；设备/视觉/真实网络等仍 **BLOCKED/UNAVAILABLE**。
- 残余：R3-01 D-12 allowlist → T-20；设备矩阵、ACK p95 NFR 4.3 实测 → 后续；IG-4 与 G-014 判定归 Stage 流程，不因合并自动通过。

## 8. 分支与下一步

- 合并后 `feat/yaocore-app` tip：本证据提交（主题 `chore(repo): 记录 wp-082 合并集成证据`，第一父为合并提交 `8a3509a`）。
- `finish wp-082-merge` 校验通过后，从本证据提交（新 tip）创建 `task/wp-083-review`（不切换、不建 worktree），分支 tip 即本证据提交。
- 下一步：在 `task/wp-083-review` 上派发 **T-20 独立评审**（消费 `artifacts/60-testing/test-report.md`，核对 696/696、layering 例外与 BLOCKED 项），随后进入 IG-4 / G-014 Stage Gate。
- 来源分支 `task/wp-082-verify` 保持 @ `7f9ac21`（未移动、未删除）。
- 约束遵守：未 push；未切换/移动其他分支；未创建 worktree；未修改本报告之外文件；未使用 reset/force。

```text
Evidence commit subject: chore(repo): 记录 wp-082 合并集成证据
Evidence commit: 见 feat/yaocore-app tip（本报告提交）
Merge commit: 8a3509ad6973a13095aba409dc98cf6f4ea47689
Source tip: 7f9ac217a94b1e355b9aac6473d8d993db505f42
Target pre-merge: 4f7c26be664a8db8aaba136fce1f128ccc72223a
Post-merge host tests: 696/696 PASS
Post-merge build: BUILD SUCCESSFUL
Post-merge layering: 0 violations (13 pending-T-20 exceptions)
```
