# wp-024 合并集成报告（task/wp-024-domain → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-024-merge（repository_action: merge）
- **Handoff**: `state/handoffs/wp-024-merge.json`（pin + snapshot + begin 已由 Orchestrator 完成；本报告提交后运行 `finish wp-024-merge`）
- **日期**: 2026-10-17
- **结果**: SUCCESS —— `--no-ff` 合并完成、无冲突；合并树与来源 tip 逐字节一致；host 回归 247/247 PASS；恰好一个证据提交（本报告）；待守卫 `finish wp-024-merge` 归档。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree） |
| 目标分支 | `feat/yaocore-app` @ `57f64d45c7442289db489df4cb6e62816815c43c`（= handoff `base_commit`；合并前 HEAD 即此） |
| 来源分支 | `task/wp-024-domain` @ `a56a84ddbe9639d9bb8fc6a45d694f0c76b6195b`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `57f64d4`（目标 tip；来源为线性追加，仍按策略强制 `--no-ff`） |
| 工作区 | 干净（`git status --porcelain` 无输出） |
| 守卫状态 | ACTIVE `wp-024-merge`（begin 已完成）；合并前无其他活动任务 |
| 快照 | `refs/swe/snapshots/20261017T110559Z-wp-024-merge-aed6c5cc` @ `12c25c5e97b5d7249e5f8cd655a52dbc4c0919b3`（覆盖全部 8 个 scope 路径，含 `artifacts/40-detailed-design/`、`entry/src/test/`；另有 `20261017T110553Z-...-3b808289` @ `2c72604` 子集快照） |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；`git fetch origin --prune` 成功（exit 0）；`origin/main` @ `7d6f4c9`；`feat/yaocore-app` 无上游；本次**未 push** |
| 本地 `main` | `a6f6558`（未移动；与 `origin/main` 为不相关历史，属既有状态） |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序` 出现次数 = 1）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用默认规范，无公司策略覆盖）

预检差异复核：`git diff --stat 57f64d4..a56a84d` = **55 files changed, 16107 insertions(+), 39 deletions(-)**；`--name-status` 为 51 个 `A` + 4 个 `M`，无 `D`/`R`；`git diff --check` 通过。全部路径落在 handoff `writes` 范围内，**无范围外文件**。

## 2. 来源提交（7 个）

| # | SHA | 主题 |
|---|---|---|
| 1 | `5e110db` | `feat(domain): 实现家庭房间设备与场景仓储服务` |
| 2 | `207e7ad` | `docs(review): T-09 领域仓储独立评审` |
| 3 | `621096b` | `fix(domain): 修复 T-09 评审发现` |
| 4 | `430620d` | `docs(review): T-09 复审（R-01 至 R-15 关闭确认）` |
| 5 | `9473ae0` | `fix(domain): 修复 T-09 复审 R2 项` |
| 6 | `8819810` | `docs(review): T-09 聚焦复审（R2 项关闭确认）` |
| 7 | `a56a84d` | `docs(design): DES-001B 同步 D-022/D-023 与场景错误码` |

## 3. 合并执行

按 pin 的 `merge_strategy: no-ff` 与 handoff 指定主题执行：

```text
git merge --no-ff task/wp-024-domain -m "chore(merge): 合并 T-09 领域仓储实现到 feat/yaocore-app"
```

- 结果：`Merge made by the 'ort' strategy`；**无冲突**（目标 tip 为来源祖先，合并未发生冲突解决、rebase、reset、amend 或强制操作）。
- **merge 提交**：`96d4281c9523a8212c68bb8e4492af4f693f5795`
- 主题：`chore(merge): 合并 T-09 领域仓储实现到 feat/yaocore-app`（与 handoff 指定主题逐字一致）
- 双亲验证（`git rev-list --parents -n 1 96d4281`）：`^1 = 57f64d45c7442289db489df4cb6e62816815c43c`（固定目标 tip）、`^2 = a56a84ddbe9639d9bb8fc6a45d694f0c76b6195b`（固定来源 tip）
- 合并规模：**55 files changed, 16107 insertions(+), 39 deletions(-)**，与预检 diff 完全一致
- 内容一致性：`git diff 96d4281^2 96d4281` 为空（exit 0）—— 合并结果树与来源 tip **逐字节相同**。因此 CQG-T09 在 `9473ae0` + 契约同步 `a56a84d` 上的验证结论可直接适用于合并结果。

### 3.1 合并后集成复核

```text
bash entry/src/test/run-host-tests.sh
# EXIT 0：1..247 / tests 247 / pass 247 / fail 0 / cancelled 0 / skipped 0（duration ≈ 1.71s）
```

- 该脚本只读（Node 内置 test runner + `register-ets.mjs`），运行后 `git status --porcelain` 仍为空。
- TAP 输出未作为新证据提交；长期证据仍以 CQG-T09 已提交的 `entry/src/test/evidence/t09-fix2-host-node-tests.tap` 为准。
- Hypium/设备路径仍为 BLOCKED（见 §6 残余项），本次未改变该边界。

## 4. 变更清单摘要（按目录统计）

| 目录 | 文件数 | 增/删行 | 说明 |
|---|---:|---:|---|
| `entry/src/main/ets/repository/` | 10 | +3849/−0 | Device/Family/Room/Scene 仓储、DomainModels/Ports/Migrations/OperationGate、DeviceSnapshotCodec、SqlCells |
| `entry/src/main/ets/service/` | 10 | +2384/−0 | family（Service/Models/Rbac/JoinSession）、room、scene（Service/Executor/Validation/TimerPort）、device（CommandRunner） |
| **域层生产代码合计**（repository + service） | **20** | **+6233/−0** | 域仓储、领域模型/端口、操作门、业务服务与执行器 |
| `entry/src/test/` | 27 | +8164/−30 | host 测试（Device/Family/Room/Scene + helpers）、Hypium harness/fakes、`List.test.ets`/`README.md`/`FakeStores.ets` 更新、14 份 T-09 证据日志 |
| `entry/src/ohosTest/ets/test/` | 1 | +176/−0 | `domain/DomainDevice.test.ets` 设备套件 |
| `artifacts/40-detailed-design/` | 1 | +52/−9 | **DES-001B 修订**（`des-001b-domain-presentation.md`，见 §4.1） |
| `artifacts/50-implementation/` | 3 | +698/−0 | `t09-domain.md`、`t09-fix-report.md`、`t09-fix2-report.md` |
| `artifacts/70-review/` | 3 | +784/−0 | `t09-review.md`、`t09-review-b.md`、`t09-review-c.md` |
| **合计** | **55** | **+16107/−39** | 51 新增 + 4 修改 |

### 4.1 DES-B 修订（来源提交 `a56a84d`，必须随合并落位）

`artifacts/40-detailed-design/des-001b-domain-presentation.md`（+52/−9，目标分支既有文件，受快照 `12c25c5` 保护）：

- **状态**：`Proposed（待 G-007）` → `Accepted（G-007 PASS @ 0b5e636）`，并登记 2026-10-17 `G-007 扩展 / T-09 复审同步` revision。
- **D-022（邀请生命周期）**：`ACCEPTED` 不再是邀请终态；`usedCount < maxUses` 且未过期时后续不同回执继续接受并递增；过期回执 → `INVITE_EXPIRED` 且不递增；状态机与 `importReceipt`/`expireInvitations` 文字同步。
- **D-023（域操作门）**：§2 契约表新增 O-1 行，`DomainOperationGate` 普通操作/顶层事务单飞、默认有界等待 2000 ms、同步重入 `CONFIGURATION_ERROR(nestedGateOperation)`、超预算 `nestedOperationOrQueueTimeout` 且不执行。
- **场景错误码**：登记 `SCENE_RUN_IN_PROGRESS`（§6.2/§23.4，资源键由 C-14/T-10 落地）。
- **回执账本**：登记 R3-01 的 C-13 持久回执账本（`(inviteId, receiptHash)` 唯一，§23.6）。
- 修订声明**不改变已冻结签名与 G-004 语义**；与实现头注释、`CQG-T09` 及三轮评审证据一致。

## 5. 前身保护核对

快照范围 `entry/src/main/ets/repository/`、`entry/src/main/ets/service/`、`entry/src/test/`、`entry/src/ohosTest/ets/test/`、`artifacts/40-detailed-design/`、`artifacts/50-implementation/`、`artifacts/70-review/`，合并前共 **142 个受跟踪文件**：

- **138/142 逐字节未变**（逐路径比较 `57f64d4:<path>` 与 `96d4281:<path>` 的 blob，mismatch = 0），包括既有 storage/service 代码、GatewayRepository、baseline/host 测试、T-05..T-08 evidence 日志与既有 `artifacts/40/50/70` 工件。
- **4/142 按任务需求修改**，均为预期内修改，且全部在 handoff `writes` 内：

| 文件 | 变更 | 预期性核对 |
|---|---|---|
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | +52/−9 | D-022/D-023/`SCENE_RUN_IN_PROGRESS`/C-13 账本同步（§4.1；a56a84d） |
| `entry/src/test/List.test.ets` | +2/−0 | 仅新增 domain host 套件 import/注册；原 T-05..T-08 套件注册保留 |
| `entry/src/test/README.md` | +47/−6 | 更新当前 revision 为 247/247、登记 T-09 host 测试与证据；保留历史基线说明 |
| `entry/src/test/storage/FakeStores.ets` | +99/−24 | 扩展 fake 以支持领域仓储测试；既有 storage 用例保持 |

- 快照范围内另新增 **51 个文件**（仓储/服务实现、host/设备测试、14 份 evidence、T-09 工件）；**无删除、无重命名、无既有 evidence 覆盖**。
- 快照 ref `12c25c5` 含上述 142 个前身文件的原始字节，`finish` 可据此验证变更前身可恢复；合并前可恢复基准同为提交 `57f64d4`。

## 6. 门禁证据引用（按来源 tip 固定）

| 项 | 值 |
|---|---|
| 上游裁定 | **CQG-T09 Component Quality Gate — PASS（代码级）**（Orchestrator，2026-10-17，实现 `5e110db`+修复 `621096b`+聚焦修复 `9473ae0`，契约同步 `a56a84d`；记录 `state/gates/CQG-T09.md`） |
| 门禁结论 | C-08..C-11 → **STABLE（代码级）** @ `9473ae0`；构建 SUCCESS（含 ohosTest 编译）、codelinter 零缺陷、Host **247/247 PASS**（三轮复跑）、R-01..R-15 + R2-01/02/03/05 全 Closed、R2-04 已通过 `a56a84d` 同步；设备证据保持 `BLOCKED` |
| handoff `gate_evidence_path` | `artifacts/70-review/t09-review-c.md` @ `a56a84d`（轮 3 聚焦复审 PASS，revision `9473ae0`） |
| 门禁证据 sha256 | `c9db8bcb5bed66918650b6ad72010b4fe10f8e2f5f13749ca0987599461faecb`（合并前 `git show a56a84d:<path> \| sha256sum` 与 handoff pin 一致；合并后 `git show 96d4281:<path>` 同值） |
| 其他随合并落位的证据 | `t09-review.md` sha256 `c66d725d9b70c939deb39ebdb533b09e55aeaac0828680394c6452ab9de1c459`；`t09-review-b.md` sha256 `94d6d6250d4e168dec9ada1d583b17f61daf1d894d119500d1fcf576fa83dd00` |
| CQG 记录 | `state/gates/CQG-T09.md` sha256 `5eb41ddb1df64d4f139e1e7a2938918a1d784307c4cfdd0752c432a12512bbf1`（工作区文件；`state/` 被忽略，仅本地） |
| 合并后复核 | 合并树与来源树 `git diff 96d4281^2 96d4281` 为空，故 CQG 对 `9473ae0`/`a56a84d` 的验证结论适用于合并结果；本次另重跑 host 247/247 PASS（§3.1） |

必须继续跟踪的 CQG-T09 条件与残余（本次合并不改变其裁定）：

1. **R3-01（Medium，已接受）**：`maxUses>=3` 的 CODE_KEK 历史回执重放可消耗一次 use（无未授权成员/秘密泄漏）→ **C-13/T-13 持久回执账本** 正式修复；C-08 保留即时防御（DES-B §23.6 已登记）。
2. **T09-FIX-03**：生产 C-06 `RdbTransactionRunner` 嵌套事务仍排队 → C-06 所有权跟踪（T-17/T-19 复议）。
3. **`SCENE_RUN_IN_PROGRESS`** 资源键由 C-14/T-10 落地；C-22 错误映射待 C-14 后补。
4. **设备侧证据 BLOCKED**：真实 RDB/Preferences/Asset/Hypium → T-19；Hypium/设备运行时在本环境不可执行，不得折算 PASS。
5. **多网关 `RotationPlan`** 单网关类型 → T-13/C-23。

## 7. 证据提交（恰好一个，紧随 merge 提交）

- 提交主题：`chore(repo): 记录 wp-024 合并集成证据`
- 唯一变更路径：`state/reports/wp-024-merge-report.md`（本报告；`state/` 被 `.gitignore` 忽略，以 `git add -f` 显式暂存，暂存集仅此一个路径）
- 提交前检查：`git diff --cached --check` 通过（无空白错误）；`git diff --cached --name-only` 仅 1 个路径
- 提交后复核：`git show --stat` 仅含单文件；本提交为 merge 提交 `96d4281` 的唯一直接后继（`git rev-list --first-parent 96d4281..HEAD` 长度为 1）
- **证据提交自身 SHA 说明**：提交内容无法内嵌其自身哈希（哈希自引用不可满足），故此处不给字面值。权威值即守卫 `finish wp-024-merge` 写入归档的 `result_commit` 字段；复核命令：`git log -1 --format=%H feat/yaocore-app`（= 本报告所在提交）。

## 8. 合并后状态与新任务分支

| 项 | 值 |
|---|---|
| `feat/yaocore-app` tip | merge `96d4281` + 证据提交（本报告，§7；`git log -1 --format=%H`） |
| 工作区 | 干净（`git status --porcelain` 无输出） |
| `task/wp-024-domain` | 保持 @ `a56a84d`，未移动 |
| `main` | 本地 `a6f6558`、`origin/main` `7d6f4c9`，均未移动 |
| 新任务分支 | `task/wp-031-i18n`：按 handoff 步骤，在 `finish` 成功后从本证据提交 tip 创建（`git branch task/wp-031-i18n`，**不切换**）；其 tip = 本证据提交（创建后以 `git rev-parse` 校验与 `feat/yaocore-app` 相等） |
| 其他 | 未创建 worktree；未 push；未切换/移动其他分支；未使用 reset/force；未 amend |

## 9. 风险与观察

1. **合并仅完成结构集成，不等于新的 Stage Gate**：合并树与来源树逐字节相同，尚无跨组件适配；T-10（i18n）与后续 UI/云适配会开始引入跨组件集成风险，届时应按 Integration Gate 执行回归。
2. **Host 证据边界**：Linux 上可执行的仅是 Node host 路径；Hypium 与设备测试仍 BLOCKED，不能将 247/247 外推为设备侧验证。
3. **DES-B 修订已随合并落位**：目标分支的既有 DES-B 被有意更新（+52/−9），下游若引用 §2/§3.3/§23 需按 revision `a56a84d` 重读；G-004 冻结签名未变。
4. **R3-01 / T09-FIX-03 仍未关闭**：分别在 C-13/T-13 与 C-06/T-17/T-19 跟踪；派发相关任务时必须在 handoff 中显式 pin。
5. **远端历史分叉（既有状态）**：本地 `main` 与 `origin/main` 无共同祖先；未来按 `main_merge_mode: review_request_when_remote` 发起 PR/MR 前，需先确认远端基线策略。
6. **`state/` 被忽略且未 push**：本报告仅存在于本地提交，非远端备份；证据完整性依赖本地仓库与守卫归档。
7. **变更窗口**：合并未产生冲突或意外覆盖；后续任务应从本证据提交派生，避免在 `task/wp-024-domain` 上继续追加。

## 10. 下一步建议

1. Orchestrator 执行 `python3 scripts/swe_guard.py finish wp-024-merge`，确认 `result_commit` 与本报告提交一致、`status` 无活动任务。
2. 从证据提交 tip 创建 `task/wp-031-i18n`（不切换），派发 **T-10（i18n 资源与键抽取）**；handoff 显式带入 DES-B revision `a56a84d`、CQG-T09 残余与 host 247/247 基线。
3. T-13/C-13 承接 R3-01 回执账本；T-17/T-19 承接 T09-FIX-03 与设备侧复跑；C-14/T-10 落地 `SCENE_RUN_IN_PROGRESS` 资源键。
4. 后续主线按 `main_merge_mode: review_request_when_remote` 处理受保护 `main` 的 PR/MR（需先解决远端历史对应关系）。
