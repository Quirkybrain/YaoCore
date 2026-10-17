# wp-016 合并集成报告（task/wp-016-security → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-016-merge（repository_action: merge）
- **Handoff**: `state/handoffs/wp-016-merge.json`（pin + snapshot + begin 已由 Orchestrator 完成；本报告提交后运行 `finish wp-016-merge`）
- **日期**: 2026-10-17
- **结果**: SUCCESS —— `--no-ff` 合并完成、无冲突；合并树与来源 tip 逐字节一致；host 回归 122/122 PASS；恰好一个证据提交（本报告）；待守卫 `finish wp-016-merge` 归档。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree） |
| 目标分支 | `feat/yaocore-app` @ `61768271f85651217f5a8ed9899ac9ebd4945dfa`（= handoff `base_commit`；合并前 HEAD 即此） |
| 来源分支 | `task/wp-016-security` @ `c76cad2f69ff6a2726545a713026494915c7063c`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `6176827`（目标 tip；来源为线性追加，仍按策略强制 `--no-ff`） |
| 工作区 | 干净（`git status --porcelain` 无输出） |
| 守卫状态 | ACTIVE `wp-016-merge`（begin 已完成）；合并前无其他活动任务 |
| 快照 | `refs/swe/snapshots/20261017T085345Z-wp-016-merge-4748d254` @ `5a9c4f8c00a0bc013cb387f95e3a0bf089197532`；`refs/swe/snapshots/20261017T085341Z-wp-016-merge-34022415` @ `9afcf3b9e6da5cd86b0382213a393087083ed220` |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；`git fetch origin --prune` 成功（exit 0），`origin/main` @ `7d6f4c9`；`feat/yaocore-app` 无上游；本次**未 push** |
| 本地 `main` | `a6f6558882f7ec53be548c85e15a1a291c5a41fd`（未移动；与 `origin/main` 为不相关历史，属既有状态） |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用默认规范，无公司策略覆盖）
- 门禁证据字节固定复核见 §6。

预检差异复核：`git diff --stat 6176827..c76cad2` = **35 files changed, 6146 insertions(+), 9 deletions(-)**；`--name-status` 为 31 个 `A` + 4 个 `M`，无 `D`/`R`。全部路径落在 handoff `writes` 范围内，**无范围外文件**。

## 2. 来源提交（4 个）

| # | SHA | 主题 |
|---|---|---|
| 1 | `ee67879` | `feat(security): 实现加密原语与 HMAC 验签全链` |
| 2 | `df13b29` | `docs(review): T-07 加密安全独立评审` |
| 3 | `11a291c` | `fix(security): 修复 T-07 评审发现 R-01 至 R-08` |
| 4 | `c76cad2` | `docs(review): T-07 复审（R-01 至 R-08 关闭确认）` |

## 3. 合并执行

按 pin 的 `merge_strategy: no-ff` 与 handoff 指定主题执行：

```text
git merge --no-ff task/wp-016-security -m "chore(merge): 合并 T-07 加密安全服务到 feat/yaocore-app"
```

- 结果：`Merge made by the 'ort' strategy`；**无冲突**（合并前 `git merge-tree --write-tree feat/yaocore-app task/wp-016-security` 仅返回一棵结果树、无冲突条目；合并未发生冲突解决、rebase、reset、amend 或强制操作）。
- **merge 提交**：`2ebceadb37a80b1932bd80e2b35c4a4bb05d0a2c`
- 主题：`chore(merge): 合并 T-07 加密安全服务到 feat/yaocore-app`（与 handoff 指定主题逐字一致）
- 双亲验证（`git rev-list --parents -n 1 2ebcead`）：`^1 = 61768271f85651217f5a8ed9899ac9ebd4945dfa`（固定目标 tip）、`^2 = c76cad2f69ff6a2726545a713026494915c7063c`（固定来源 tip）
- 合并规模：**35 files changed, 6146 insertions(+), 9 deletions(-)**，与预检 diff 完全一致
- 内容一致性：`git diff c76cad2 2ebcead` 为空 —— 合并结果树与来源 tip **逐字节相同**（目标 tip 为来源祖先，无并行改动需要融合）。因此 CQG-T07 在 `11a291c` + 复审 `c76cad2` 上的验证结论可直接适用于合并结果。

### 3.1 合并后集成复核（无冲突，仍需验证合并树可运行）

```text
bash entry/src/test/run-host-tests.sh
# EXIT 0：1..122 / tests 122 / pass 122 / fail 0 / cancelled 0 / skipped 0（duration ≈ 1.23s）
```

- 该脚本只读（Node 内置 test runner + `register-ets.mjs`），运行后 `git status --porcelain` 仍为空。
- TAP 输出保存在仓库外 `/tmp/opencode/wp-016-merge-host-tests.tap`，未作为证据提交；长期证据仍以 CQG-T07 已提交的 `entry/src/test/evidence/t07-fix-host-node-tests.tap` 为准。
- Hypium/设备路径仍为 BLOCKED（见 §6 残余项），本次未改变该边界。

## 4. 变更清单摘要（按目录统计）

| 目录 | 文件数 | 增/删行 | 说明 |
|---|---:|---:|---|
| `entry/src/main/ets/service/crypto/` | 7 | +986/−0 | CryptoPort/Provider/Service、OHOS provider、错误分类、随机源、X25519 编解码 |
| `entry/src/main/ets/service/security/` | 5 | +657/−0 | CanonicalBuilder、RequestSigner、ResponseVerifier、NonceCache、ClockSkewTracker |
| `entry/src/ohosTest/ets/test/` | 3 | +156/−2 | `SecurityDevice.test.ets` 新增；`List.test.ets` 注册；README 更新 |
| `entry/src/test/` | 16 | +3400/−7 | host 测试 `Crypto.test.mjs`/`Security.test.mjs`/`TestCryptoProvider.ets`、Hypium `SecurityHost.test.ets`、10 份 T-07 证据日志、`List.test.ets` 注册、README 更新 |
| `artifacts/50-implementation/` | 2 | +493/−0 | `t07-security.md`、`t07-fix-report.md` |
| `artifacts/70-review/` | 2 | +454/−0 | `t07-review.md`、`t07-review-b.md` |
| **合计** | **35** | **+6146/−9** | 31 新增 + 4 修改 |

前身文件保护核对（快照范围 `entry/src/test/`、`entry/src/ohosTest/ets/test/`、`artifacts/50-implementation/`、`artifacts/70-review/`，合并前共 **62 个受跟踪文件**）：

- **58/62 逐字节未变**（逐文件比较 `git rev-parse 6176827:<path>` 与 `2ebcead:<path>`，mismatches = 0），包括既有 `Baseline.test.ets`、`host/*.mjs`（baseline/protocol/perf/oracle/loader）、既有 T-05/T-06 evidence 日志、既有 `artifacts/50-implementation/build-baseline.md`、`t06-*.md` 与 `artifacts/70-review/t06-*.md`。
- **4/62 按任务需求修改**，均为预期内修改，且全部在 handoff `writes` 内：

| 文件 | 变更 | 预期性核对 |
|---|---|---|
| `entry/src/test/List.test.ets` | +4/−2 | 仅新增 `SecurityHostSuite` import/注册并更新 Producer/Task 注释；原 T-05/T-06 套件注册保留 |
| `entry/src/test/README.md` | +23/−5 | 更新当前 revision 为 122/122、登记 T-07 host 测试与证据；保留 T-05/T-06 历史基线说明 |
| `entry/src/ohosTest/ets/test/List.test.ets` | +12/−0 | 仅新增 foundation/security 设备套件 import/注册；baseline 注册保留 |
| `entry/src/ohosTest/ets/test/README.md` | +6/−2 | 登记设备套件注册状态与 `BLOCKED_ON_DEVICE_RUNNER` 边界 |

- 快照范围内另新增 19 个文件（设备套件、host 测试、evidence、T-07 工件）；**无删除、无重命名、无既有 evidence 覆盖**。
- `entry/src/test/`、`entry/src/ohosTest/ets/test/` 下除上述 4 个文件外，所有合并前已跟踪文件内容不变。

## 5. 证据提交（恰好一个，紧随 merge 提交）

- 提交主题：`chore(repo): 记录 wp-016 合并集成证据`
- 唯一变更路径：`state/reports/wp-016-merge-report.md`（本报告；`state/` 被 `.gitignore` 忽略，以 `git add -f` 显式暂存，暂存集仅此一个路径）
- 提交前检查：`git diff --cached --check` 通过（无空白错误）；`git diff --cached --name-only` 仅 1 个路径
- 提交后复核：`git show --stat` 仅含单文件；本提交为 merge 提交 `2ebcead` 的唯一直接后继（`git rev-list --first-parent 2ebcead..HEAD` 长度为 1）
- **证据提交自身 SHA 说明**：提交内容无法内嵌其自身哈希（哈希自引用不可满足），故此处不给字面值。权威值即守卫 `finish wp-016-merge` 写入归档的 `result_commit` 字段；复核命令：`git log -1 --format=%H feat/yaocore-app`（= 本报告所在提交）。

## 6. 门禁证据引用（按来源 tip 固定）

| 项 | 值 |
|---|---|
| 上游裁定 | **CQG-T07 Component Quality Gate — PASS（代码级）**（Orchestrator，2026-10-17，revision `11a291c` + 复审 `c76cad2`；记录 `state/gates/CQG-T07.md`） |
| 门禁结论 | C-04/C-05 → **STABLE（代码级）** @ `11a291c`；构建 SUCCESS（含 ohosTest 编译）、codelinter 零缺陷、Host 122/122 PASS、R-01..R-08 中 7 Closed + 1 例外（R-08 位置，跟踪迁移） |
| handoff `gate_evidence_path` | `artifacts/70-review/t07-review-b.md` @ `c76cad2`（复审 PASS，revision `11a291c`） |
| 门禁证据 sha256 | `ef35597de19224711c16e861d698ce8ddc4be257881e3c15d1b19314aadde9f9`（合并前 `git show c76cad2:<path> \| sha256sum` 与 handoff pin 一致；合并后 `git show 2ebcead:<path>` 同值） |
| 其他随合并落位的证据 | `t07-review.md` sha256 `493ff3e136c0b5d603adf170bfffcf9a771ca7793c70c92c6beb62a85f98f9de`；`t07-security.md` sha256 `a48099f8d96d9e9b275213dfe71340a8e3be948668eee347d2e55aa12a001e53`；`t07-fix-report.md` sha256 `c95bbf3f33169eb5061b965aed1cb763c7776e15a7660732e5c686e2b5f7cd79` |
| 合并后复核 | 合并树与来源树 `git diff c76cad2 2ebcead` 为空，故 CQG 对 `11a291c` + `c76cad2` 的验证结论适用于合并结果；本次另重跑 host 122/122 PASS（§3.1） |

必须继续跟踪的 CQG 残余（本次合并不改变其裁定）：

1. **R-08 目录例外**：`CryptoPort` 位于 `service/crypto/`（迁移跟踪 C-17/T-19）。
2. **R2-01（Low，doc-only）**：`t07-security.md` 开放风险小节与 `CryptoErrorClassifier` 注释残留旧表述 → 下次文档修订清理。
3. **设备侧证据 BLOCKED**：`SecurityDevice.test`/`FoundationDevice.test` 待设备/签名环境复跑（T-19/T-12）；平台 GCM tag code `17630001` 假设与 `clearMem()` 不可观测性待设备验证（T-19）。
4. **V-01 12-hex 夹具差异口径**待 T-19 明确（T-07 实现已生成 32-hex nonce）。
5. **Hypium/设备运行时 BLOCKED**（Linux Previewer/无设备）——长期证据边界，不得折算 PASS。

## 7. 合并后状态与新任务分支

| 项 | 值 |
|---|---|
| `feat/yaocore-app` tip | merge `2ebcead` + 证据提交（本报告，§5；`git log -1 --format=%H`） |
| 工作区 | 干净（`git status --porcelain` 无输出） |
| `task/wp-016-security` | 保持 @ `c76cad2`，未移动 |
| `main` | 本地 `a6f6558`、`origin/main` `7d6f4c9`，均未移动 |
| 新任务分支 | `task/wp-020-storage`：按 handoff 步骤，在 `finish` 成功后从本证据提交 tip 创建（`git branch task/wp-020-storage`，**不切换**）；其 tip 即本报告所在提交，创建后以 `git rev-parse` 校验与 `feat/yaocore-app` 相等 |
| 其他 | 未创建 worktree；未 push；未切换/移动其他分支；未使用 reset/force |

## 8. 风险与观察

1. **合并仅完成结构集成，不等于新的 Stage Gate**：合并树与来源树逐字节相同，尚无跨组件适配；跨组件集成风险从 T-08 存储服务与后续组合开始累积，届时需 Integration Gate + 回归。
2. **Host 证据边界**：Linux 上可执行的仅是 Node host 路径；Hypium 与设备测试仍 BLOCKED，不能将 122/122 外推为设备侧验证。
3. **远端历史分叉（既有状态）**：本地 `main` 与 `origin/main` 无共同祖先；未来按 `main_merge_mode: review_request_when_remote` 发起 PR/MR 前，需先确认远端基线策略。
4. **`state/` 被忽略且未 push**：本报告仅存在于本地提交，非远端备份；证据完整性依赖本地仓库与守卫归档。
5. **变更窗口**：合并未产生冲突或既有文件覆盖；后续任务应从本证据提交派生，避免在 `task/wp-016-security` 上继续追加。

## 9. 下一步建议

1. Orchestrator 执行 `python3 scripts/swe_guard.py finish wp-016-merge`，确认 `result_commit` 与本报告提交一致、且 `status` 无活动任务。
2. 从证据提交 tip 创建 `task/wp-020-storage`（不切换），派发 **T-08 存储服务 + GatewayRepository（C-06/C-07）**，handoff pin 本报告 §6 的合并后基线。
3. T-19/T-12 承接设备侧复跑、R2-01 文档清理、R-08 迁移与 V-01 夹具口径；后续主线按 `main_merge_mode: review_request_when_remote` 处理受保护 `main` 的 PR/MR（需先解决远端历史对应关系）。
