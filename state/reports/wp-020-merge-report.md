# wp-020 合并集成报告（task/wp-020-storage → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-020-merge（repository_action: merge）
- **Handoff**: `state/handoffs/wp-020-merge.json`（pin + snapshot + begin 已由 Orchestrator 完成；本报告提交后运行 `finish wp-020-merge`）
- **日期**: 2026-10-17
- **结果**: SUCCESS —— `--no-ff` 合并完成、无冲突；合并树与来源 tip 逐字节一致；host 回归 166/166 PASS；恰好一个证据提交（本报告）；待守卫 `finish wp-020-merge` 归档。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree） |
| 目标分支 | `feat/yaocore-app` @ `0713aca8f6b4e8a326f94842eb21bc3df61fd444`（= handoff `base_commit`；合并前 HEAD 即此） |
| 来源分支 | `task/wp-020-storage` @ `9061321b1dd431f461c2d5f8d39a12186a70ddd4`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `0713aca`（目标 tip；来源为线性追加，仍按策略强制 `--no-ff`） |
| 工作区 | 干净（`git status --porcelain` 无输出） |
| 守卫状态 | ACTIVE `wp-020-merge`（begin 已完成）；合并前无其他活动任务 |
| 快照 | `refs/swe/snapshots/20261017T094353Z-wp-020-merge-3261ba48` @ `efe8e0c2d4268710a3c8d6ffc4a3a6a5167c42ae`（仅含 pinned handoff；begin 时工作区干净，故无未提交前身字节需要另存） |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；`git fetch origin --prune` 成功（exit 0），`origin/main` @ `7d6f4c9`；`feat/yaocore-app` 无上游；本次**未 push** |
| 本地 `main` | `a6f6558`（未移动；与 `origin/main` 为不相关历史，属既有状态） |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用默认规范，无公司策略覆盖）
- 门禁证据字节固定复核见 §6。

预检差异复核：`git diff --stat 0713aca..9061321` = **38 files changed, 7623 insertions(+), 12 deletions(-)**；`--name-status` 为 34 个 `A` + 4 个 `M`，无 `D`/`R`。全部路径落在 handoff `writes` 范围内，**无范围外文件**。

## 2. 来源提交（4 个）

| # | SHA | 主题 |
|---|---|---|
| 1 | `66b6e1d` | `feat(storage): 实现存储服务与网关路由仓库` |
| 2 | `71f45ce` | `docs(review): T-08 存储路由独立评审` |
| 3 | `1f1fb4d` | `fix(storage): 修复 T-08 评审发现 R-01 至 R-07` |
| 4 | `9061321` | `docs(review): T-08 复审（R-01 至 R-07 关闭确认）` |

## 3. 合并执行

按 pin 的 `merge_strategy: no-ff` 与 handoff 指定主题执行：

```text
git merge --no-ff task/wp-020-storage -m "chore(merge): 合并 T-08 存储路由实现到 feat/yaocore-app"
```

- 结果：`Merge made by the 'ort' strategy`；**无冲突**（目标 tip 为来源祖先，合并未发生冲突解决、rebase、reset、amend 或强制操作）。
- **merge 提交**：`f2c4ed2bef52a50cbae6085f6ddd6cbca1cc64b9`
- 主题：`chore(merge): 合并 T-08 存储路由实现到 feat/yaocore-app`（与 handoff 指定主题逐字一致）
- 双亲验证（`git rev-list --parents -n 1 f2c4ed2`）：`^1 = 0713aca8f6b4e8a326f94842eb21bc3df61fd444`（固定目标 tip）、`^2 = 9061321b1dd431f461c2d5f8d39a12186a70ddd4`（固定来源 tip）
- 合并规模：**38 files changed, 7623 insertions(+), 12 deletions(-)**，与预检 diff 完全一致
- 内容一致性：`git diff 9061321 f2c4ed2` 为空（exit 0）—— 合并结果树与来源 tip **逐字节相同**。因此 CQG-T08 在 `1f1fb4d` + 复审 `9061321` 上的验证结论可直接适用于合并结果。

### 3.1 合并后集成复核（无冲突，仍需验证合并树可运行）

```text
bash entry/src/test/run-host-tests.sh
# EXIT 0：1..166 / tests 166 / pass 166 / fail 0 / cancelled 0 / skipped 0（duration ≈ 1.55s）
```

- 该脚本只读（Node 内置 test runner + `register-ets.mjs`），运行后 `git status --porcelain` 仍为空。
- TAP 输出未作为证据提交；长期证据仍以 CQG-T08 已提交的 `entry/src/test/evidence/t08-fix-host-node-tests.tap` 为准。
- Hypium/设备路径仍为 BLOCKED（见 §6 残余项），本次未改变该边界。

## 4. 变更清单摘要（按目录统计）

| 目录 | 文件数 | 增/删行 | 说明 |
|---|---:|---:|---|
| `entry/src/main/ets/service/storage/` | 12 | +1039/−0 | StorageService、RDB/Preferences/SecretStore 适配器、事务运行器、迁移注册表、端口定义 |
| `entry/src/main/ets/repository/` | 2 | +960/−0 | GatewayPorts、GatewayRepository |
| `entry/src/ohosTest/ets/test/` | 3 | +170/−5 | `storage/StorageDevice.test.ets` 新增；`List.test.ets` 注册；README 更新 |
| `entry/src/test/` | 17 | +4547/−7 | host 测试 `GatewayRepository.test.mjs`/`Storage.test.mjs`、Hypium `StorageHost.test.ets`/`FakeStores.ets`、11 份 T-08 证据日志、`List.test.ets` 注册、README 更新 |
| `artifacts/50-implementation/` | 2 | +445/−0 | `t08-storage.md`、`t08-fix-report.md` |
| `artifacts/70-review/` | 2 | +462/−0 | `t08-review.md`、`t08-review-b.md` |
| **合计** | **38** | **+7623/−12** | 34 新增 + 4 修改 |

前身文件保护核对（快照范围 `entry/src/test/`、`entry/src/ohosTest/ets/test/`、`artifacts/50-implementation/`、`artifacts/70-review/`，合并前共 **81 个受跟踪文件**）：

- **77/81 逐字节未变**（逐路径比较 `0713aca:<path>` 与 `f2c4ed2:<path>` 的 blob，mismatches = 0），包括既有 baseline/host 测试、T-05/T-06/T-07 evidence 日志与既有 `artifacts/50-implementation/`、`artifacts/70-review/` 工件。
- **4/81 按任务需求修改**，均为预期内修改，且全部在 handoff `writes` 内：

| 文件 | 变更 | 预期性核对 |
|---|---|---|
| `entry/src/test/List.test.ets` | +2/−0 | 仅新增 storage host 套件 import/注册；原 T-05/T-06/T-07 套件注册保留 |
| `entry/src/test/README.md` | +27/−7 | 更新当前 revision 为 166/166、登记 T-08 host 测试与证据；保留历史基线说明 |
| `entry/src/ohosTest/ets/test/List.test.ets` | +4/−1 | 仅新增 storage 设备套件 import/注册；baseline/foundation/security 注册保留 |
| `entry/src/ohosTest/ets/test/README.md` | +7/−4 | 登记设备套件注册状态与 `BLOCKED_ON_DEVICE_RUNNER` 边界 |

- 快照范围内另新增 20 个文件（设备套件、host 测试、evidence、T-08 工件）；**无删除、无重命名、无既有 evidence 覆盖**。
- 快照 ref `efe8e0c` 仅包含 pinned handoff（begin 时工作区干净）；前身内容的可恢复基准确认为合并前提交 `0713aca`。

## 5. 证据提交（恰好一个，紧随 merge 提交）

- 提交主题：`chore(repo): 记录 wp-020 合并集成证据`
- 唯一变更路径：`state/reports/wp-020-merge-report.md`（本报告；`state/` 被 `.gitignore` 忽略，以 `git add -f` 显式暂存，暂存集仅此一个路径）
- 提交前检查：`git diff --cached --check` 通过（无空白错误）；`git diff --cached --name-only` 仅 1 个路径
- 提交后复核：`git show --stat` 仅含单文件；本提交为 merge 提交 `f2c4ed2` 的唯一直接后继（`git rev-list --first-parent f2c4ed2..HEAD` 长度为 1）
- **证据提交自身 SHA 说明**：提交内容无法内嵌其自身哈希（哈希自引用不可满足），故此处不给字面值。权威值即守卫 `finish wp-020-merge` 写入归档的 `result_commit` 字段；复核命令：`git log -1 --format=%H feat/yaocore-app`（= 本报告所在提交）。

## 6. 门禁证据引用（按来源 tip 固定）

| 项 | 值 |
|---|---|
| 上游裁定 | **CQG-T08 Component Quality Gate — PASS（代码级）**（Orchestrator，2026-10-17，revision `1f1fb4d` + 复审 `9061321`；记录 `state/gates/CQG-T08.md`） |
| 门禁结论 | C-06/C-07 → **STABLE（代码级）** @ `1f1fb4d`；构建 SUCCESS（含 ohosTest 编译）、codelinter 零缺陷、Host 166/166 PASS、R-01..R-07 全 Closed；设备证据保持 `BLOCKED` |
| handoff `gate_evidence_path` | `artifacts/70-review/t08-review-b.md` @ `9061321`（复审 PASS，revision `1f1fb4d`） |
| 门禁证据 sha256 | `152ad214dc9ec95c756cd1d40980994e34dea43c01258b8b897a1fb34a75dbf6`（合并前 `git show 9061321:<path> \| sha256sum` 与 handoff pin 一致；合并后 `git show f2c4ed2:<path>` 同值） |
| 其他随合并落位的证据 | `t08-review.md` sha256 `67a616f04bfd163bddea0be6ae1c703f2ac0fcb338adc3daa6d8fdbbd94ea11a`；`t08-storage.md` sha256 `de16d45d3f69bc8e54e03df711223730718a0164c1c707d62d1c7e8336c7f5d4`；`t08-fix-report.md` sha256 `fdc3430e059a4e9092dc128753c7d14c51d2d4b4608ebc36176f4bbbceeeaf99` |
| CQG 记录 | `state/gates/CQG-T08.md` sha256 `a3b0a8c23c3c16f5765d168d3041d5b0a6a406b0931910236623cb869cc065af`（工作区文件） |
| 合并后复核 | 合并树与来源树 `git diff 9061321 f2c4ed2` 为空，故 CQG 对 `1f1fb4d` + `9061321` 的验证结论适用于合并结果；本次另重跑 host 166/166 PASS（§3.1） |

必须继续跟踪的 CQG 残余（本次合并不改变其裁定）：

1. **O-1**：普通 execute/query 与事务单飞/嵌套约束 → **C-08/T-09 派发时必须作为约束明确**。
2. **O-2**：DES-A §10.2 端口错误码设计冲突 → 待契约 owner 裁定（已记录）。
3. **O-3**：rotateSecret active 写失败、applyInvitedGateway route 写失败、SC-12 断言 → 延期（T-17/T-19）。
4. **R2-01/R2-02（Low）**：`completeCommit` 返回快照的 `lastSeenAt` 瞬时一致性/异常吞没 → C-17 不得把该返回值作为权威（已记录）。
5. **设备侧证据 BLOCKED**：Asset ALIAS 编码、RDB version 回滚、锁屏语义、事务回滚待设备复跑（T-19）；Hypium/设备运行时在本环境不可执行，不得折算 PASS。

## 7. 合并后状态与新任务分支

| 项 | 值 |
|---|---|
| `feat/yaocore-app` tip | merge `f2c4ed2` + 证据提交（本报告，§5；`git log -1 --format=%H`） |
| 工作区 | 干净（`git status --porcelain` 无输出） |
| `task/wp-020-storage` | 保持 @ `9061321`，未移动 |
| `main` | 本地 `a6f6558`、`origin/main` `7d6f4c9`，均未移动 |
| 新任务分支 | `task/wp-024-domain`：按 handoff 步骤，在 `finish` 成功后从本证据提交 tip 创建（`git branch task/wp-024-domain`，**不切换**）；其 tip 即本报告所在提交，创建后以 `git rev-parse` 校验与 `feat/yaocore-app` 相等 |
| 其他 | 未创建 worktree；未 push；未切换/移动其他分支；未使用 reset/force |

## 8. 风险与观察

1. **合并仅完成结构集成，不等于新的 Stage Gate**：合并树与来源树逐字节相同，尚无跨组件适配；跨组件集成风险从 T-09 领域层与存储/安全组合开始累积，届时应按 Integration Gate 执行回归。
2. **Host 证据边界**：Linux 上可执行的仅是 Node host 路径；Hypium 与设备测试仍 BLOCKED，不能将 166/166 外推为设备侧验证。
3. **O-1 未决约束**：T-09 若在事务上下文复用普通 execute/query，可能与单飞/嵌套设计冲突；派发 handoff 时必须显式 pin CQG-T08 的 O-1 条款。
4. **远端历史分叉（既有状态）**：本地 `main` 与 `origin/main` 无共同祖先；未来按 `main_merge_mode: review_request_when_remote` 发起 PR/MR 前，需先确认远端基线策略。
5. **`state/` 被忽略且未 push**：本报告仅存在于本地提交，非远端备份；证据完整性依赖本地仓库与守卫归档。
6. **变更窗口**：合并未产生冲突或既有文件覆盖；后续任务应从本证据提交派生，避免在 `task/wp-020-storage` 上继续追加。

## 9. 下一步建议

1. Orchestrator 执行 `python3 scripts/swe_guard.py finish wp-020-merge`，确认 `result_commit` 与本报告提交一致、且 `status` 无活动任务。
2. 从证据提交 tip 创建 `task/wp-024-domain`（不切换），派发 **T-09（C-08..C-11）**，handoff 中显式带入 O-1 事务约束与 O-2 契约裁定状态。
3. T-19/T-12 承接设备侧复跑与 O-3/R2-01/R2-02 跟踪；后续主线按 `main_merge_mode: review_request_when_remote` 处理受保护 `main` 的 PR/MR（需先解决远端历史对应关系）。
