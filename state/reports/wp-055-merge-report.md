# wp-055 合并集成报告（task/wp-055-cloud → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-055-merge（repository_action: merge）
- **Handoff**: `state/handoffs/wp-055-merge.json`（pin + snapshot + begin 已完成；本报告提交后运行 `finish wp-055-merge`）
- **日期**: 2026-10-17
- **结果**: **MERGE 成功（`--no-ff`，无冲突）；合并后集成验证 PASS（host 505/505、clean 构建成功）**。本次合并将 T-14 云服务（C-15）与空调品牌适配（C-16）实现及其评审/裁定证据带回 `feat/yaocore-app`。本报告是集成证据，**不替代 Stage Gate 判定**。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree） |
| 目标分支 | `feat/yaocore-app` @ `de1b9b60eb4839ee78c2298c2834650a5628279d`（= handoff `base_commit`；合并前 HEAD 即此） |
| 来源分支 | `task/wp-055-cloud` @ `1119eca3c0839eb5aa5060b6ec7e9ae63bc13c54`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `de1b9b6`（目标 tip，`git merge-base` 实查；来源为基于该 tip 的线性提交链，仍按策略强制 `--no-ff`） |
| 工作区 | 干净（`git status --porcelain` 无输出） |
| 守卫状态 | ACTIVE `wp-055-merge`（begin 已完成）；`status` 未见其他活动任务 |
| 快照 | `refs/swe/snapshots/20261017T152842Z-wp-055-merge-28f55a9f` @ `4f3051e6ee18ac24e9b1796bc4c21f7d096295db`，tree `2b7391323d3be594d66d6bb444874e99b99dae99`（`SWE snapshot wp-055-merge`） |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；已执行 `git fetch origin`（exit 0）；`origin/main` @ `7d6f4c9`；远端无 `feat/yaocore-app`；本次**未 push** |
| 本地 `main` | `a6f6558`（未移动） |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- `gate_evidence_path` `artifacts/70-review/t14-review-b.md` sha256 `7b1e438a30eb298d7333f17864df143029b17ec56d78b085c2bc380e804e8a85`（在来源 tip `1119eca` 上实查一致，= handoff `gate_evidence_path_sha256`）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用 `config/git-policy.default.md` 默认规范，无公司策略覆盖）

## 2. 来源与预检

来源提交链（`git log --oneline de1b9b6..1119eca`，5 个提交）：

```text
039adec feat(cloud): 实现云服务与空调品牌适配
aadf26d docs(review): T-14 云与适配独立评审
9eca54e docs(design): 裁定云连接状态与完成判定边界
db33485 fix(cloud): 修复 T-14 评审发现
1119eca docs(review): T-14 复审（F-01 至 F-07 关闭确认）
```

预检结果：目标工作区干净；来源 tip 精确等于 handoff `source_commit`；目标 tip 是来源 tip 的祖先（线性链，无分叉）；`git diff --stat de1b9b6..1119eca` 为 **43 files changed, 12431 insertions(+), 27 deletions(-)**。

## 3. 合并

- 命令：`git merge --no-ff task/wp-055-cloud -m "chore(merge): 合并 T-14 云服务与适配实现到 feat/yaocore-app"`
- 合并提交：`41d9471722c334ed3af287ee35e13ed6c3135080`
- 父提交：`de1b9b6`（目标，第一父）+ `1119eca`（来源，第二父）
- 策略：`ort`；**无冲突**（未手工编辑任何文件）
- 树一致性：`git diff --stat 1119eca..HEAD` 为空，即合并结果树与来源 tip 完全一致（目标自 base 后无独立提交）

## 4. 变更统计（`de1b9b6..1119eca`，按目录）

| 目录 | 文件数 | + | − |
|---|---:|---:|---:|
| `artifacts/40-detailed-design/` | 1 | 121 | 27 |
| `artifacts/50-implementation/`（`t14-cloud-ac.md`、`t14-fix-report.md`） | 2 | 443 | 0 |
| `artifacts/70-review/`（`t14-review.md`、`t14-review-b.md`） | 2 | 458 | 0 |
| `entry/src/main/ets/service/`（`ac/` 7 + `cloud/` 15） | 22 | 2861 | 0 |
| `entry/src/ohosTest/ets/test/`（`List.test.ets` + `cloud/CloudDevice.test.ets`） | 2 | 114 | 0 |
| `entry/src/test/`（host 测试 4 + evidence 日志 10） | 14 | 8434 | 0 |
| **合计** | **43** | **12431** | **27** |

设计文档修订明细（净 diff）：

| 文档 | 净 +/− | 归属提交 |
|---|---|---|
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | +121 / −27 | `9eca54e`（T-14 裁定同步：新增 §0.6 F-03/F-04/F-05/F-06；`brand.*` 顶层资源键；v1 active-scope 前置条件；不改变冻结签名与 G-004 语义） |

`entry/src/main/ets/service/` 明细：`ac/` 7 个文件（`AcAdapter`、`AcAdapterFactory`、`AcModels`、`GenericAcAdapter` 及 Gree/Haier/Midea 三个品牌适配器）；`cloud/` 15 个文件（`CloudService`、`CloudCommandClient`、`CloudCompletionEvaluator`、`CloudConfigStore`/`CloudConfigValidator`、`CloudCredentialStore`、`CloudCancellation`、`CloudErrors`、`CloudModels`、`CloudPorts`、`DeviceInventoryParser`、`ShadowDtoAdapter`、`ShadowReader`、`SystemTimerPort`、`adapters/OhosCloudHttpTransport`）。

## 5. 前身保护确认

目标分支中已存在的 DES-001B 由合并前快照保护；快照内字节与合并前目标字节一致：

| 文档 | 快照/合并前 blob | 快照/合并前 sha256 | 合并后 sha256（= 来源 tip） |
|---|---|---|---|
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | `4c5c5a7e4f8dd192c41201ae79bf96d18ed57348` | `8d094bb5affa524dc950e56117d9e1c6f10510aea3846f1f588e0d9ca537dbff` | `e8d3869b099008e493ca5a67bed7f54ca2506a761520cc4293c4d6152d184083` |

- 快照 ref 可完整恢复合并前状态；快照内 DES-001B blob 与合并前目标完全一致（`4c5c5a7`）。
- 本次未改写历史、未 reset、未 force；合并提交保留双亲，来源修订以独立提交进入历史（`9eca54e` 等），可追溯。

## 6. 合并后验证（在 `41d9471` 上执行）

| 检查 | 命令 | 结果 |
|---|---|---|
| Host 测试 | `bash entry/src/test/run-host-tests.sh` | ✅ **505/505 PASS**（`# tests 505 / # pass 505 / # fail 0 / # skipped 0`） |
| 构建 | `hvigorw clean assembleHap --no-daemon` | ✅ **BUILD SUCCESSFUL in 5 s 152 ms**（35 tasks：34 executed / 1 up-to-date，exit 0；签名跳过警告为预期，项目未配置 signingConfigs） |
| 工作区 | `git status --porcelain` | ✅ 干净（构建产物均被忽略） |

说明：本任务未复跑 codelinter；静态检查证据沿用 CQG-T14 判定的 `t14-fix/codelinter.log`（合并树与来源树一致）。

## 7. 冲突

**无冲突**。`ort` 自动合并；目标 tip 是来源 tip 的直接祖先，DES-001B 的修改以来源版本线性覆盖并保留 `9eca54e` 提交归属。

## 8. 门禁引用

- Gate：`state/gates/CQG-T14.md` — **PASS（代码级）**；C-15/C-16 → STABLE（代码级，条件式）@ `db33485`（复审 `1119eca`）。
- 门禁证据：`artifacts/70-review/t14-review-b.md` sha256 `7b1e438a30eb298d7333f17864df143029b17ec56d78b085c2bc380e804e8a85`。
- 残余（不因合并而关闭）：F-05 `brand.*` 资源补齐 → T-18；R2-01/R2-02（Low）→ C-28/维护轮；F-06 v1 单 active 云配置与 `CloudActiveScopePort`/`ClockPort` 注入 → C-28；`RISK-CLOUD-MULTIGATEWAY = ACCEPTED (v1)`；`ohos.permission.INTERNET` → T-17；设备/真实云证据 → T-19（BLOCKED）。详见 CQG-T14 §条件与残余。

## 9. 分支与下一步

- 合并后 `feat/yaocore-app` tip：本证据提交（主题 `chore(repo): 记录 wp-055 合并集成证据`，第一父为合并提交 `41d9471`）。
- `finish wp-055-merge` 校验通过后，从本证据提交（新 tip）创建 `task/wp-060-vm`（不切换、不建 worktree），分支 tip 即本证据提交。
- 下一步：派发 **T-15 + T-16**（ViewModel 组），见 CQG-T14 §Next action。
- 约束遵守：未 push；未切换/移动其他分支；未创建 worktree；未修改本报告之外文件；未使用 reset/force。

```text
Evidence commit subject: chore(repo): 记录 wp-055 合并集成证据
Evidence commit: 见 feat/yaocore-app tip（本报告提交）
Merge commit: 41d9471722c334ed3af287ee35e13ed6c3135080
Source tip: 1119eca3c0839eb5aa5060b6ec7e9ae63bc13c54
Target pre-merge: de1b9b60eb4839ee78c2298c2834650a5628279d
Post-merge host tests: 505/505 PASS
Post-merge build: BUILD SUCCESSFUL
```
