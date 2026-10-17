# wp-031 合并集成报告（task/wp-031-i18n → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-031-merge（repository_action: merge）
- **Handoff**: `state/handoffs/wp-031-merge.json`（pin + snapshot + begin 已完成；本报告提交后运行 `finish wp-031-merge`）
- **日期**: 2026-10-17
- **结果**: SUCCESS —— `--no-ff` 合并完成、无冲突；合并树与来源 tip 逐字节一致；合并后 host 回归 275/275 PASS；恰好一个证据提交（本报告）；待守卫 `finish wp-031-merge` 归档。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree） |
| 目标分支 | `feat/yaocore-app` @ `0a6d5bc5b24a4b56200f3df56f7ee7195aee6d8b`（= handoff `base_commit`；合并前 HEAD 即此） |
| 来源分支 | `task/wp-031-i18n` @ `2786b1a457bf05f4b2b10865204af41a52801e5f`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `0a6d5bc`（目标 tip；来源为线性追加，仍按策略强制 `--no-ff`） |
| 工作区 | 干净（`git status --porcelain=v1 -b` 仅输出分支行） |
| 守卫状态 | ACTIVE `wp-031-merge`（begin 已完成）；合并前无其他活动任务 |
| 快照 | `refs/swe/snapshots/20261017T115327Z-wp-031-merge-4e714b70` @ `9aab10a1eb6046136de1152aec5784b69a2fc061`（342 个文件；覆盖全部 `snapshot_paths`，142/142 个既有受跟踪文件） |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；`git fetch origin --prune` 成功（exit 0，无更新）；`origin/main` @ `7d6f4c9`；`feat/yaocore-app` 无上游；本次**未 push** |
| 本地 `main` | `a6f6558`（未移动） |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序` 出现次数 = 1）
- `state/handoffs/wp-031-merge.json` sha256 `0e1f1406866b4350a2b755d95501e86fd8e9842d9cf552ead4ac3fba66713c91`（与 begin 记录一致）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用 `config/git-policy.default.md` 默认规范，无公司策略覆盖）

预检差异复核：`git diff --stat 0a6d5bc..2786b1a` = **55 files changed, 9981 insertions(+), 14 deletions(-)**；`--name-status` 为 50 个 `A` + 5 个 `M`，无 `D`/`R`；`git diff --check 0a6d5bc..2786b1a` 通过。全部路径落在 handoff `writes` 范围内，**无范围外文件**。

## 2. 来源提交（4 个）

| # | SHA | 主题 |
|---|---|---|
| 1 | `ce780d724aa8ea6261cbbf43b8399e321de456ea` | `feat(i18n): 实现双语资源包与国际化服务` |
| 2 | `a932cfc99192aa38acdbaf2d5fa4cd11b472bfe6` | `docs(review): T-10 i18n 独立评审` |
| 3 | `1bf318338c2078aa7d99bf2a484925d7bbf36cdc` | `fix(i18n): 修复 T-10 评审发现` |
| 4 | `2786b1a457bf05f4b2b10865204af41a52801e5f` | `docs(review): T-10 复审（F-01 至 F-08 关闭确认）` |

## 3. 合并执行

按 pin 的 `merge_strategy: no-ff` 与 handoff 指定主题执行：

```text
git merge --no-ff task/wp-031-i18n -m "chore(merge): 合并 T-10 i18n 资源实现到 feat/yaocore-app"
```

- 结果：`Merge made by the 'ort' strategy`；**无冲突**（未发生 rebase、reset、amend 或强制操作）。
- **merge 提交**：`b38a4842761560db279fe25d8e00b5fc236981cd`
- 主题：`chore(merge): 合并 T-10 i18n 资源实现到 feat/yaocore-app`（与 handoff 指定主题逐字一致）
- 双亲验证（`git rev-list --parents -n 1 b38a484`）：`^1 = 0a6d5bc5b24a4b56200f3df56f7ee7195aee6d8b`（固定目标 tip）、`^2 = 2786b1a457bf05f4b2b10865204af41a52801e5f`（固定来源 tip）
- 合并规模：**55 files changed, 9981 insertions(+), 14 deletions(-)**，与预检 diff 完全一致
- 内容一致性：`git diff --quiet 2786b1a b38a484` 通过（exit 0）—— 合并结果树与来源 tip **逐字节相同**。因此 CQG-T10 在 `1bf3183` 代码 revision（复审 @ `2786b1a`）上的验证结论可直接适用于合并结果。

### 3.1 合并后集成复核

```text
bash entry/src/test/run-host-tests.sh
# EXIT 0：1..275 / tests 275 / pass 275 / fail 0 / cancelled 0 / skipped 0
```

- 该脚本只读（Node 内置 test runner + `register-ets.mjs`），运行后 `git status --porcelain` 仍为空。
- TAP 输出未作为新证据提交；长期证据仍以 CQG-T10 已提交的 `entry/src/test/evidence/t10-fix-host-node-tests.tap`（275/275）为准。
- Hypium/设备路径仍为 BLOCKED（见 §6 残余项），本次未改变该边界。

## 4. 变更清单摘要（按目录统计）

| 目录 | 文件数 | 增/删行 | 说明 |
|---|---:|---:|---|
| `entry/src/main/ets/service/i18n/` | 8 | +1110/−0 | `I18nService`、Models/Keys/Ports、BundleCodec、Rawfile loader、locale applier、错误映射 |
| `entry/src/main/resources/rawfile/i18n/` | 2 | +613/−0 | `en-US.json`（307 行）、`zh-CN.json`（306 行） |
| `entry/src/main/resources/base/element/` | 1 | +92/−4 | `string.json`：3 条既有值本地化 + 22 条通用 UI 键，共 25 条 |
| `entry/src/main/resources/en_US/element/` | 1 | +104/−0 | 新建 `string.json`，25 条英文 UI 键 |
| `entry/src/test/` | 36 | +6666/−6 | host 28 用例、i18n 检查器/夹具/迁移表、Hypium 编译套件、14 份 T-10 证据、README/List 更新 |
| `entry/src/ohosTest/ets/test/` | 3 | +86/−4 | `i18n/I18nDevice.test.ets`、`List.test.ets`、README |
| `artifacts/50-implementation/` | 2 | +601/−0 | `t10-i18n.md`、`t10-fix-report.md` |
| `artifacts/70-review/` | 2 | +709/−0 | `t10-review.md`、`t10-review-b.md` |
| **合计** | **55** | **+9981/−14** | 50 新增 + 5 修改；无删除/重命名 |

### 4.1 资源与键统计

| 资源 | 条目/键 | 说明 |
|---|---:|---|
| `rawfile/i18n/en-US.json` | 212 逻辑键 / 213 叶子字符串 | `device.count` 逻辑键含 `count_one` + `count_other` 复数变体 |
| `rawfile/i18n/zh-CN.json` | 212 逻辑键 / 212 叶子字符串 | `device.count` 单条复数形式 |
| 双语共同键 | 211 | 唯一差异为英文复数变体；逻辑键 212/212 对齐 |
| 键分区（zh 逻辑键） | errors 110、provisioning 23、cloud 4、stateSource 6、ac 8、door 5、gateway 6、invite 9、member 9、device 15、scene 5、room 4、family 4、home 4 | 合计 212 |
| `base/element/string.json` | 25 条 | 含 3 条既有应用名/模块描述本地化 |
| `en_US/element/string.json` | 25 条 | 与 base 键集合一致 |

## 5. 前身保护核对

快照范围 `entry/src/main/resources/`、`entry/src/test/`、`entry/src/ohosTest/ets/test/`、`artifacts/50-implementation/`、`artifacts/70-review/`，合并前共 **142 个受跟踪文件**：

- **137/142 逐字节未变**（逐路径比较 `0a6d5bc:<path>` 与 `b38a484:<path>` 的 blob，mismatch = 0），包括既有资源、storage/domain/service 代码、baseline/host 测试、T-05..T-09 evidence 与既有 `artifacts/50/70` 工件。
- **5/142 按任务需求修改**，均为预期内修改，且全部在 handoff `writes` 内：

| 文件 | 变更 | 预期性核对 |
|---|---|---|
| `entry/src/main/resources/base/element/string.json` | +92/−4 | 既有 3 条描述/标签值本地化，新增通用 UI 键至 25 条（T-10 资源契约） |
| `entry/src/test/List.test.ets` | +2/−0 | 注册 i18n host 套件 |
| `entry/src/test/README.md` | +27/−6 | 当前 revision 更新为 275/275，登记 i18n 测试/证据 |
| `entry/src/ohosTest/ets/test/List.test.ets` | +2/−0 | 注册 i18n 设备套件 |
| `entry/src/ohosTest/ets/test/README.md` | +7/−4 | 登记 i18n 设备套件（BLOCKED 边界） |

- 快照范围内另新增 **42 个文件**（资源、测试、检查器/夹具/迁移表、T-10 工件与证据）；**无删除、无重命名、无既有 evidence 覆盖**。
- 另有 8 个新增生产文件位于 `entry/src/main/ets/service/i18n/`（不在快照范围，因合并前不存在前身；均在 handoff `writes` 内）。
- 快照 ref `9aab10a` 含上述 142 个前身文件的原始字节，且覆盖 handoff 自身；`finish` 可据此验证变更前身可恢复；合并前可恢复基准同为提交 `0a6d5bc`。

## 6. 门禁证据引用（按来源 tip 固定）

| 项 | 值 |
|---|---|
| 上游裁定 | **CQG-T10 Component Quality Gate — PASS（代码级）**（Orchestrator，2026-10-17；实现 `ce780d7` + 修复 `1bf3183`；复审 @ `2786b1a`；记录 `state/gates/CQG-T10.md`） |
| 门禁结论 | C-14 → **STABLE（代码级）** @ `1bf3183`；构建 SUCCESS（含 ohosTest 编译）、codelinter 零缺陷、Host **275/275 PASS**、i18n 检查器 CHK-01..09 PASS（0 阻断/2 条已知 UI 占位告警/0 missingKeys）、F-01..F-08 Closed；设备/运行时证据保持 `BLOCKED` |
| handoff `gate_evidence_path` | `artifacts/70-review/t10-review-b.md` @ `2786b1a`（轮 2 复审 PASS，条件式） |
| 门禁证据 sha256 | `ccd62b10224de3e1ab9806fde0ddca97fdc7dca467779908f39a6b1bccfb9f6f`（合并前 `git show 2786b1a:<path> \| sha256sum` 与 handoff pin 一致；合并后 `git show b38a484:<path>` 同值） |
| 其他随合并落位的证据 | `artifacts/70-review/t10-review.md`、`artifacts/50-implementation/t10-i18n.md`、`t10-fix-report.md`、14 份 `entry/src/test/evidence/t10-*` 日志/TAP/JSON |
| CQG 记录 | `state/gates/CQG-T10.md` sha256 `7ecb5f43589db99866919378eb14a056c0ce1cfc7d2c6f9aadd7f88aecc5688d`（工作区文件；`state/` 被忽略，仅本地） |
| 合并后复核 | 合并树与来源树 `git diff b38a484^2 b38a484` 为空，故 CQG 对 `1bf3183`/`2786b1a` 的验证结论适用于合并结果；本次另重跑 host 275/275 PASS（§3.1） |

必须继续跟踪的 CQG-T10 条件与残余（本次合并不改变其裁定）：

1. **T10-EX-01**：检查器/迁移表暂在 `entry/src/test/i18n/`（契约路径 `tools/i18n/`）→ 迁移 owner 工具任务/T-19。
2. **596 条迁移**（A 606 = 10 accepted + 596 pending；B_REWRITE_REQUIRED=11；C 安全复核 2）→ T-17/T-18。
3. **R2-01（Low，doc）**：`t10-fix-report` 写“3 条 B”实为 11；已在复审报告更正，下次文档修订同步。
4. **R2-02（Low）**：`reload()` 的 `I18nLoadResult.locale` 语义待 T-17/T-18 接线前明确。
5. `pages/Index.ets` 2 条短英文占位（CHK-07 warning）→ T-17/T-18 迁移后升级阻断。
6. 设备/运行时（`$r`/setLanguage/Preferences）→ T-19。

## 7. 冲突

**无冲突**。目标 `feat/yaocore-app` 的 tip 为来源分支祖先，`--no-ff` 合并由 `ort` 策略生成双亲提交；未修改任何冲突文件，未触发 rebase/reset/force。

## 8. 证据提交（恰好一个，紧随 merge 提交）

- 提交主题：`chore(repo): 记录 wp-031 合并集成证据`
- 唯一变更路径：`state/reports/wp-031-merge-report.md`（本报告；`state/` 被 `.gitignore` 忽略，以 `git add -f` 显式暂存，暂存集仅此一个路径）
- 提交前检查：`git diff --cached --check` 通过（无空白错误）；`git diff --cached --name-only` 仅 1 个路径；`git show --stat` 仅含单文件
- 提交后复核：本提交为 merge 提交 `b38a484` 的唯一直接后继（`git rev-list --first-parent b38a484..HEAD` 长度为 1）
- **证据提交自身 SHA 说明**：提交内容无法内嵌其自身哈希（哈希自引用不可满足），故此处不给字面值。权威值即守卫 `finish wp-031-merge` 写入归档的 `result_commit` 字段；复核命令：`git log -1 --format=%H feat/yaocore-app`（= 本报告所在提交）。

## 9. 合并后状态与新任务分支

| 项 | 值 |
|---|---|
| `feat/yaocore-app` tip | merge `b38a484` + 证据提交（本报告，§8；`git log -1 --format=%H`） |
| 工作区 | 干净（`git status --porcelain` 无输出） |
| `task/wp-031-i18n` | 保持 @ `2786b1a`，未移动 |
| `main` | 本地 `a6f6558`、`origin/main` `7d6f4c9`，均未移动 |
| 新任务分支 | `task/wp-035-transport`：按 handoff 步骤，在 `finish` 成功后从本证据提交 tip 创建（`git branch task/wp-035-transport`，**不切换**）；其 tip = 本证据提交（创建后以 `git rev-parse` 校验与 `feat/yaocore-app` 相等） |
| 其他 | 未创建 worktree；未 push；未切换/移动其他分支；未使用 reset/force；未 amend |

## 10. 风险与观察

1. **合并仅完成结构集成，不等于新的 Stage Gate**：合并树与来源树逐字节相同，尚无跨组件适配；T-11/T-17/T-18/T-19 引入链路与 UI 接线后，应按 Integration Gate 执行回归。
2. **Host 证据边界**：Linux 上可执行的仅是 Node host 路径；Hypium 与设备测试仍 BLOCKED，不能将 275/275 外推为设备侧验证。
3. **资源键双存储边界**：`rawfile/i18n/*.json`（212 逻辑键）与 `element/string.json`（25 键）按 C-14 契约并存；迁移完成前不得单方面删除任一存储。
4. **T10-EX-01 路径偏差**：检查器/迁移表仍在 `entry/src/test/i18n/`，与契约 `tools/i18n/` 不一致；派发 T-19/工具任务时须显式 pin 该残余。
5. **设备/运行时 BLOCKED**：`$r` 重渲染、平台 locale、Preferences 持久化 → T-19；不得在后续 Gate 中折算为 PASS。
6. **`state/` 被忽略且未 push**：本报告仅存在于本地提交，非远端备份；证据完整性依赖本地仓库与守卫归档。
7. **远端历史分叉（既有状态）**：本地 `main` 与 `origin/main` 无共同祖先；未来按 `main_merge_mode: review_request_when_remote` 发起 PR/MR 前，需先确认远端基线策略。

## 11. 下一步建议

1. Orchestrator 执行 `python3 scripts/swe_guard.py finish wp-031-merge`，确认 `result_commit` 与本报告提交一致、`status` 无活动任务。
2. 从证据提交 tip 创建 `task/wp-035-transport`（不切换），派发 **T-11（C-17/C-18/C-20 + PB-03 TLS pin spike）**；handoff 显式带入 CQG-T10 残余、`entry/src/test/evidence/t10-fix-host-node-tests.tap` 275/275 基线与 `state/gates/CQG-T10.md`。
3. T-17/T-18 承接 596 条迁移与 UI 文案接线；T-19 承接设备/运行时证据与 `tools/i18n/` 路径归位。
4. 后续主线按 `main_merge_mode: review_request_when_remote` 处理受保护 `main` 的 PR/MR（需先解决远端历史对应关系）。
