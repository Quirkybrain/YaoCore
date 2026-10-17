# wp-040 合并集成报告（task/wp-040-ble → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-040-merge（repository_action: merge）
- **Handoff**: `state/handoffs/wp-040-merge.json`（pin + snapshot + begin 已完成；本报告提交后运行 `finish wp-040-merge`）
- **日期**: 2026-10-17
- **结果**: **MERGE 成功（结构集成，无冲突）；集成验证 FAIL（1 个 host 回归）**。合并本身按 `--no-ff` 完成且合并树与来源 tip 逐字节一致，但合并后 `run-host-tests.sh` 为 **450/451**，失败项为 T-10 I18n 对 DES-A §3.2.3 的表解析。本报告**不构成 Gate 通过**；`feat/yaocore-app` 在修复并复跑全绿前不得晋升 main 或用于后续 Stage 证据。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree） |
| 目标分支 | `feat/yaocore-app` @ `3834f5dadcf253816bd1ed6f14eb7e829367311f`（= handoff `base_commit`；合并前 HEAD 即此） |
| 来源分支 | `task/wp-040-ble` @ `a93cc3e59f2c4e539b3fb5810955cb0b58a9cd1f`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `3834f5d`（目标 tip；来源为线性追加 7 提交，仍按策略强制 `--no-ff`） |
| 工作区 | 干净（`git status --porcelain=v1 --untracked-files=all` 无输出） |
| 守卫状态 | ACTIVE `wp-040-merge`（begin 已完成）；合并前无其他活动任务 |
| 快照 | `refs/swe/snapshots/20261017T134414Z-wp-040-merge-6f0536f4` @ `a3d783cf623ef780f4c17eda52c2ba36f89b1778`（8 个选择路径、277 个文件；含 handoff 自身） |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；已执行 `git fetch`（无错误）；`origin/main` @ `7d6f4c9`；`feat/yaocore-app` 无上游、远端无同名分支；本次**未 push** |
| 本地 `main` | `a6f6558`（未移动） |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- `state/handoffs/wp-040-merge.json` sha256 `1427471f0d9e8762696e5f6364f46012b25faa07eac2418f0d76cdaf99ad2d6c`（与 begin 记录一致）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用 `config/git-policy.default.md` 默认规范，无公司策略覆盖）

预检差异复核：`git diff --stat 3834f5d..a93cc3e` = **48 files changed, 18636 insertions(+), 46 deletions(-)**；`--name-status` 为 42 个 `A` + 6 个 `M`，无 `D`/`R`；全部路径落在 handoff `writes` 范围内，**无范围外文件**。

## 2. 来源提交（7 个）

> handoff 前置说明写“8 提交”，但实际 `git log --oneline 3834f5d..a93cc3e` 与 `git rev-list --count` 均为 **7**；以下为实查清单（低风险元数据不一致，见 §10）。

| # | SHA | 主题 |
|---|---|---|
| 1 | `27dc537ca3e2de4f50f41d7572a09a1ab2aa4f82` | `feat(ble): 实现 Security1 配网与身份协商` |
| 2 | `ba0de0c6f0eb44d624fcac9181551a413d608282` | `docs(review): T-12 BLE 配网独立评审` |
| 3 | `a6a30533881a7f6bb6ac83f66a93a8bf3bd91f8e` | `fix(ble): 修复 T-12 评审发现` |
| 4 | `1eae08c1b60db4099e093d902cfeb3b5bfc926a2` | `docs(review): T-12 复审（F-01 至 F-11 关闭确认）` |
| 5 | `74255fc111a470a14eb8a6ee231c8482134f594e` | `fix(ble): 收窄写重试条件并校正文档口径` |
| 6 | `d9d868afcb04fc328618adeeb891f7f42a9c780b` | `docs(review): T-12 聚焦复审（R2 项关闭确认）` |
| 7 | `a93cc3e59f2c4e539b3fb5810955cb0b58a9cd1f` | `docs(design): 裁定 T-12 草稿重签与错误码命名` |

## 3. 合并执行

按 pin 的 `merge_strategy: no-ff` 与 handoff 指定主题执行：

```text
git merge --no-ff task/wp-040-ble -m "chore(merge): 合并 T-12 BLE 配网实现到 feat/yaocore-app"
```

- 结果：`Merge made by the 'ort' strategy`；**无冲突**（未发生 rebase、reset、amend 或强制操作）。
- **merge 提交**：`49f720c5b50ecac7ccb1a372a5ad2aabf266b4a1`
- 主题：`chore(merge): 合并 T-12 BLE 配网实现到 feat/yaocore-app`（与 handoff 指定主题逐字一致）
- 双亲验证（`git rev-list --parents -n 1 49f720c`）：`^1 = 3834f5dadcf253816bd1ed6f14eb7e829367311f`（固定目标 tip）、`^2 = a93cc3e59f2c4e539b3fb5810955cb0b58a9cd1f`（固定来源 tip）
- 合并规模：**48 files changed, 18636 insertions(+), 46 deletions(-)**，与预检 diff 完全一致
- 内容一致性：`git diff --quiet a93cc3e 49f720c` 通过（exit 0）—— 合并结果树与来源 tip **逐字节相同**。因此 T-12 在 `74255fc` 代码 revision 上的构建/测试结论对合并树本身仍成立，但**不能覆盖 `a93cc3e` 文档修订引入的跨工件回归**（见 §3.1）。

### 3.1 合并后集成复核（FAIL）

```text
bash entry/src/test/run-host-tests.sh
# EXIT 1
# tests 451 / pass 450 / fail 1 / cancelled 0 / skipped 0
# not ok 358 - T10_C14_authoritativeCatalog_everyDeclaredCodeHasBothLocaleKeys
#   DES-A §3.2.3 rows (95 codes + HTTP_<status>)
#   94 !== 96  (expected 96, actual 94)
#   entry/src/test/host/I18n.test.mjs:474
```

- 该脚本只读；运行后 `git status --porcelain=v1 --untracked-files=all` 仍为空。
- **根因（change impact）**：`a93cc3e` 在 DES-A §3.2.3 两行的 code 单元格内追加了说明文字：
  - `CONTROL_RESPONSE_AUTH_FAILED（**DEPRECATED**，仅兼容读取）`
  - `ACK_CORRELATION_MISMATCH（仅 ACK body request_id/seq）`
  T-10 的 `parseDeclaredCodes`（`entry/src/test/host/I18n.test.mjs:399-413`）要求行尾为 `` `i18nKey` `` 且 code 反引号后紧接 `|`；追加文字使这两行不再匹配，解析数由 96 降为 **94**。这是**文档修订与既有 host 测试解析假设的冲突**，不是 BLE 实现代码缺陷。
- 反证：来源分支已提交的 `entry/src/test/evidence/t12-fix2-host-node-tests.tap`（生成于 `74255fc`，早于 `a93cc3e`）为 451/451，且第 358 项 `ok`。`a93cc3e` 只改 `artifacts/20-architecture/contract-baseline.md` 与 DES-A，未重跑 host，故 **CQG-T12 的 451/451 对来源 tip 已失效（stale）**。
- 本次为定位失败额外在 `/tmp/opencode` 对 `3834f5d`、`74255fc` 做只读 `git archive` 抽取运行；因 archive 不含被忽略的测试夹具，golden 用例失败，结果不作为证据，仅用于确认失败项与夹具无关（正式证据以上述工作区运行与已提交 TAP 为准）。

## 4. 变更清单摘要（按目录统计）

| 目录 | 文件数 | 增/删行 | 说明 |
|---|---:|---:|---|
| `artifacts/20-architecture/` | 1 | +36/−1 | `contract-baseline.md`：T-12 裁定同步（§4.2/§4.5、R-32、FC-06） |
| `artifacts/40-detailed-design/` | 1 | +77/−16 | `des-001a-foundation-transport.md`：§0.5、§3.2.3/§8.2/§14.4/§16.8/§16.10/§17/§18.7 裁定落点 |
| `artifacts/50-implementation/` | 3 | +638/−0 | `t12-ble.md`、`t12-fix-report.md`、`t12-fix2-report.md` |
| `artifacts/70-review/` | 3 | +778/−0 | `t12-review.md`、`t12-review-b.md`、`t12-review-c.md`（门禁证据） |
| `entry/src/main/ets/service/` | 15 | +4366/−27 | `ble/`：Security1、Protocomm、GATT、身份协商、配网服务与 OHOS 适配器；`BleProvisioningPorts.ets` 修改 |
| `entry/src/ohosTest/ets/test/` | 2 | +185/−0 | `ble/BleProvisioningDevice.test.ets`、`List.test.ets` 注册 |
| `entry/src/test/evidence/` | 16 | +9755/−0 | T-12 构建/codelinter/host/ohosTest/设备阻塞证据（含 3 份 TAP） |
| `entry/src/test/host/` | 7 | +2801/−2 | BLE codec/GATT/security/service/fakes 套件；`GatewayMock.test.mjs`、`TransportBoundary.test.mjs` 微调 |
| **合计** | **48** | **+18636/−46** | 42 新增 + 6 修改；无删除/重命名 |

### 4.1 受保护前身修订（2 份 Artifact）

- `artifacts/20-architecture/contract-baseline.md`：+36/−1；新增 §4.5 响应验签/相关性错误码唯一命名、R-32、FC-06；§4.2 更新 `RESPONSE_*` 命名与 `CONTROL_RESPONSE_AUTH_FAILED` 退役说明。
- `artifacts/40-detailed-design/des-001a-foundation-transport.md`：+77/−16；新增 §0.5 裁定摘要；更新 §3.2.3、§8.2、§14.4、§16.8/§16.10、§17.2/§17.4、§18.7 的 R-1/R-2/D-4/R3-01 口径。
- 两份文件合并后 sha256 分别为 `883e09bb34ea8adc98c2b504d419eb6d5bb0c1d150eb5b9cf8b515bdf6cc01f5`、`9ac732811ed6800878b64baa560a07db33927b77928212e946d46629d51b0f95`，与来源 tip `a93cc3e` 的 blob **逐字节一致**。
- **注意**：上述 DES-A §3.2.3 的格式修订正是 §3.1 host 回归的直接触发点；契约语义本身（错误码唯一命名、退役别名、R-1 重签）未被本报告否定，需由架构/测试 owner 以可解析格式落位并复跑。

## 5. 前身保护核对

快照范围 `entry/src/main/ets/service/`、`entry/src/test/`、`entry/src/ohosTest/ets/test/`、`artifacts/20-architecture/`、`artifacts/40-detailed-design/`、`artifacts/50-implementation/`、`artifacts/70-review/` 及 handoff 自身，合并前共 **277 个文件**：

- 快照覆盖和工作区逐路径比对：**270/270 未修改文件哈希匹配，mismatch = 0，missing = 0**；其余 6 个为合并修改的前身，快照内保存的是合并前原始字节，另 1 个为 handoff。
- 合并涉及的既有前身 **6/6 均被快照覆盖**，且快照保存的是合并前原始字节：

| 文件 | 合并前 sha256（= 快照 blob） | 变更 |
|---|---|---|
| `artifacts/20-architecture/contract-baseline.md` | `6673a990d5020c0b70dd4ae30bd75fa13d33d4d573a4d953961371296fadee89` | +36/−1 |
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `5599e693fafe405443c5d28efaec0bd2091064eee5c3f1a619dc22d3dcbfe1c1` | +77/−16 |
| `entry/src/main/ets/service/ble/BleProvisioningPorts.ets` | `6589589cf292e2d608687988db9d55e4107d39a53fc86e6ddb51789c24bc1dd5` | 修改 |
| `entry/src/test/host/GatewayMock.test.mjs` | `8cb533aa688fba55681a4559014080c199df61464e7761b363892339d1d63eec` | +3/−2 |
| `entry/src/test/host/TransportBoundary.test.mjs` | `acb5c4734c69502f0a2cfd55077ba8fac773c4f999515d5465f74711d86e12fe` | +13/−0 |
| `entry/src/ohosTest/ets/test/List.test.ets` | `7bbbe1bd3cd33edee9d7262ec6a700ac93bf523db9ef240329746019bc479c04` | +2/−0 |

- 快照范围内另新增 **42 个文件**（BLE 实现、host/设备测试、T-12 工件与证据）；**无删除、无重命名、无既有 evidence 覆盖**。
- `finish` 可据 `a3d783c` 恢复全部 6 个被修改前身；本报告不修改任何前身文件。

## 6. 门禁证据引用（按来源 tip 固定）

| 项 | 值 |
|---|---|
| 上游门禁 | **CQG-T12 Component Quality Gate — PASS（代码级）**（Orchestrator，2026-10-17；实现 `27dc537` + 修复 `a6a3053` + 收窄 `74255fc`；复审 @ `d9d868a`；裁定 `a93cc3e`；记录 `state/gates/CQG-T12.md`） |
| 门禁结论 | C-19 → **STABLE（代码级）** @ `74255fc`；构建 SUCCESS、codelinter 零缺陷、Host **451/451 PASS**、F-01..F-11 / R2-01/R2-03/R2-04 关闭；设备/真实 BLE/MTU/0x2901/平台 crypto/网关端到端保持 **BLOCKED**（T-19） |
| handoff `gate_evidence_path` | `artifacts/70-review/t12-review-c.md` @ `a93cc3e`（轮 3 聚焦复审，PASS 条件式） |
| 门禁证据 sha256 | `47f16912eba6e0e6d62c97ff93552c894d3adc2a3ae73e3c7cfdde1627e59b4a`（合并前 `git show a93cc3e:<path> \| sha256sum` 与 handoff pin 一致；合并后 `git show 49f720c:<path>` 同值） |
| 其他随合并落位的证据 | `artifacts/70-review/t12-review.md`、`t12-review-b.md`、`artifacts/50-implementation/t12-ble.md`、`t12-fix-report.md`、`t12-fix2-report.md`、`entry/src/test/evidence/t12-*`（16 份日志/TAP） |
| CQG 记录 | `state/gates/CQG-T12.md` sha256 `6e2d11715051e3da1706211ce175b2c04cd1b9477811c7138c6b59436dd61063`（工作区文件；`state/` 被忽略，仅本地） |
| 合并后复核 | `git diff a93cc3e 49f720c` 为空，故 CQG 对 `74255fc`/`d9d868a` 的验证结论适用于合并树；但 `a93cc3e` 文档修订使 T-10 host 用例失败（§3.1），**门禁证据对来源 tip 已 stale**，不得据此宣称合并结果全绿 |

必须继续跟踪的 CQG-T12 条件与残余（本次合并不改变其裁定，且 §3.1 新增一项阻塞）：

1. **C-20 Mock 对齐**：`MockGatewayService` 仍发 `CONTROL_RESPONSE_AUTH_FAILED` / header→`ACK_CORRELATION_MISMATCH`，与 CB §4.5 唯一映射冲突；后续实现任务对齐并重跑 host。
2. **DES-001B Change Impact**：§10.2 旧错误码、C-23 配网流仍传原始 draftId（与 R-1 冲突）→ architect 同步。
3. **R3-02/T-19**：平台 busy 码（`2900011`/`2901004`/`2900099`）与 protocomm 非零 `Status` 语义待设备。
4. **R-6**：`module.json5` 权限声明 → T-17。
5. **R-8**：Security1 CTR 无完整性（协议固有风险，如实记录）。
6. **新增阻塞（本次发现）**：DES-A §3.2.3 两行注释破坏 T-10 `parseDeclaredCodes`，host 450/451；需修复并复跑后方可继续。

## 7. 冲突

**无冲突**。目标 `feat/yaocore-app` 的 tip 为来源分支祖先（`git merge-base 3834f5d a93cc3e` = `3834f5d`），`--no-ff` 合并由 `ort` 策略生成双亲提交；未修改任何冲突文件，未触发 rebase/reset/force。DES-A 与 contract-baseline 虽为目标分支既有文件，但与来源修改基于同一基线，合并后即来源版本（§4.1）。

## 8. 证据提交（恰好一个，紧随 merge 提交）

- 提交主题：`chore(repo): 记录 wp-040 合并集成证据`
- 唯一变更路径：`state/reports/wp-040-merge-report.md`（本报告；`state/` 被 `.gitignore` 忽略，以 `git add -f` 显式暂存，暂存集仅此一个路径）
- 提交前检查：`git diff --cached --check` 通过（无空白错误）；`git diff --cached --name-only` 仅 1 个路径；`git show --stat` 仅含单文件
- 提交后复核：本提交为 merge 提交 `49f720c` 的唯一直接后继（`git rev-list --first-parent 49f720c..HEAD` 长度为 1）
- **证据提交自身 SHA 说明**：提交内容无法内嵌其自身哈希（哈希自引用不可满足），故此处不给字面值。权威值即守卫 `finish wp-040-merge` 写入归档的 `result_commit` 字段；复核命令：`git log -1 --format=%H feat/yaocore-app`（= 本报告所在提交）。

## 9. 合并后状态与新任务分支

| 项 | 值 |
|---|---|
| `feat/yaocore-app` tip | merge `49f720c` + 证据提交（本报告，§8；`git log -1 --format=%H`） |
| 工作区 | 干净（`git status --porcelain` 无输出） |
| `task/wp-040-ble` | 保持 @ `a93cc3e`，未移动 |
| `main` | 本地 `a6f6558`、`origin/main` `7d6f4c9`，均未移动 |
| 新任务分支 | 按 handoff 步骤，在 `finish` 成功后从证据提交 tip 创建 `task/wp-047-family`（`git branch task/wp-047-family`，**不切换**）；其 tip = 证据提交。**因 §3.1 回归，建议在该分支派发 T-13 前先完成修复，或在修复合并后重新创建/重 pin。** |
| 其他 | 未创建 worktree；未 push；未切换/移动其他分支；未使用 reset/force；未 amend |

## 10. 风险与观察

1. **【阻塞】Host 回归**：合并结果 450/451，失败 `T10_C14_authoritativeCatalog_everyDeclaredCodeHasBothLocaleKeys`（DES-A §3.2.3 解析 94 vs 96）。修复前 `feat/yaocore-app` 不具备晋升 main/Stage Gate 的测试证据。
2. **CQG-T12 证据 stale**：门禁的 451/451 生成于 `74255fc`；`a93cc3e` 文档修订后未复跑。应更新 CQG 记录或在修复任务后重新出具集成证据，不能继续引用 451/451 作为当前 tip 结论。
3. **修复层级判定**：这是文档格式（DES-A 表）与测试解析器的契约冲突。优先由 `solution-architect` 调整 DES-A 两行使 key 仍为行尾单元格（语义不变），或由 `test-engineer` 扩展解析器容忍 code 单元格注释；两者都不应改 BLE 实现。修复后必须复跑 `bash entry/src/test/run-host-tests.sh` 至 451/451，并复核 `ErrorCatalog` 映射未漂移。
4. **既有 CQG 残余仍在**：C-20 mock 错误码未对齐、DES-B §10.2/C-23 的 R-1 冲突、R3-02/T-19 设备语义、R-6 权限、R-8 CTR 完整性；本合并不关闭这些条件。
5. **设备证据边界**：仅有 Node host 路径可执行；Hypium/真实 BLE/MTU/0x2901/网关端到端仍 BLOCKED，不能把 450/451 或 451/451 外推为设备验证。
6. **`state/` 被忽略且未 push**：本报告与 `state/gates/CQG-T12.md` 仅存在于本地提交；证据完整性依赖本地仓库与守卫归档。远端亦无 `feat/yaocore-app` 分支。
7. **元数据轻微不一致**：handoff 前置说明称来源 8 提交，实查为 7；不影响合并内容，但后续 handoff 宜以 `git rev-list --count` 生成。
8. **远端历史分叉（既有状态）**：本地 `main` 与 `origin/main` 无共同祖先；按 `main_merge_mode: review_request_when_remote` 晋升前需先解决远端基线策略。

## 11. 下一步建议

1. Orchestrator 执行 `python3 scripts/swe_guard.py finish wp-040-merge`，确认 `result_commit` 与本报告提交一致、`status` 无活动任务。
2. **先修复 §3.1 回归**（建议新小任务，owner：`solution-architect` 调整 DES-A 表格式，或 `test-engineer` 调整解析器），复跑 host 至 451/451，并复核 `t12-review-c.md` 契约语义未被改动。
3. 修复合并后，再决定 `task/wp-047-family` 的基线：若已按 handoff 创建，应从修复后的 `feat/yaocore-app` tip 重新创建或重 pin，避免 T-13 在红色基线上开工。
4. 在 CQG-T12 记录中补记本次集成回归与关闭证据；未关闭前不得把 `feat/yaocore-app` 作为已集成全绿基线。
5. 后续主线按 `main_merge_mode: review_request_when_remote` 处理受保护 `main` 的 PR/MR（需先解决远端历史对应关系）。
