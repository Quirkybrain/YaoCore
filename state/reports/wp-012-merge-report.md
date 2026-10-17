# wp-012 合并集成报告（task/wp-012-foundation → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-012-merge（repository_action: merge）
- **Handoff**: state/handoffs/wp-012-merge.json（pin + snapshot + begin 由 Orchestrator 完成；本报告提交后运行 `finish wp-012-merge`）
- **日期**: 2026-10-17
- **结果**: SUCCESS —— `--no-ff` 合并完成、无冲突；合并后 host 测试 88/88 PASS；恰好一个证据提交（本报告）；待守卫 `finish wp-012-merge` 归档。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree） |
| 目标分支 | `feat/yaocore-app` @ `5901cd7081dc5a9b12f5d4f51dbed71ef7bb5ae8`（= handoff `base_commit`；合并前 HEAD 即此） |
| 来源分支 | `task/wp-012-foundation` @ `7b622680573c201dec8a4a394f4afdb4a0acde89`（= handoff `source_commit`，与 `git rev-parse` 实查一致） |
| 合并基 | `5901cd7`（目标 tip；来源为线性追加，仍按策略强制 `--no-ff`） |
| 工作区 | 干净（`git status --porcelain` 无输出） |
| 守卫状态 | ACTIVE `wp-012-merge`（begin 已由 Orchestrator 完成）；无其他活动任务 |
| 快照 | `refs/swe/snapshots/20261017T081757Z-wp-012-merge-367a16ce` @ `5c25c09400f5394dd508df0f414fcb2ebf35b249`（`entry/src/test/`、`artifacts/50-implementation/` 前身保护） |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；`git fetch origin --prune` 后仅 `origin/main` @ `7d6f4c9`，无 `feat/yaocore-app` 上游；本次**未 push** |
| 本地 `main` | `a6f6558882f7ec53be548c85e15a1a291c5a41fd`（未移动；与 `origin/main` 为不相关历史，属既有状态） |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用默认规范，无公司策略覆盖）
- 门禁证据字节固定复核见 §6。

预检差异复核：`git diff --stat 5901cd7..7b62268` = **76 files changed, 10628 insertions(+), 6 deletions(-)**（与 handoff 描述的“≈90+ 文件”量级一致，实际 76 个文件）。`--name-status` 为 74 个 `A` + 2 个 `M`（`entry/src/test/List.test.ets`、`entry/src/test/README.md`），无 `D`/`R`；全部路径落在 handoff `writes` 范围内，**无范围外文件**。

## 2. 来源提交（4 个）

| # | SHA | 主题 |
|---|---|---|
| 1 | `4d361bdba790da686839b30ce1feffec2215b0f7` | `feat(foundation): 实现公共类型、领域模型与协议映射` |
| 2 | `5eb4d67a34aa384bc40ef20304c1e7d14d4961cd` | `docs(review): T-06 基础协议映射独立评审` |
| 3 | `4d97e41d1a0cba278ba99631c7625e00b1a185aa` | `fix(foundation): 修复 T-06 评审发现 R-01 至 R-13` |
| 4 | `7b622680573c201dec8a4a394f4afdb4a0acde89` | `docs(review): T-06 复审（R-01 至 R-13 关闭确认）` |

## 3. 合并执行

按 pin 的 `merge_strategy: no-ff` 与 handoff 指定主题执行：

```text
git merge --no-ff task/wp-012-foundation -m "chore(merge): 合并 T-06 基础协议映射实现到 feat/yaocore-app"
```

- 结果：`Merge made by the 'ort' strategy`；**无冲突**（未发生冲突解决、rebase、reset、amend 或强制操作）。
- **merge 提交**：`a0c5db644d57e8ae3f0ce2fb3904a8b7181f7785`
- 主题：`chore(merge): 合并 T-06 基础协议映射实现到 feat/yaocore-app`（与 handoff 指定主题逐字一致）
- 双亲验证（`git rev-list --parents -n 1 HEAD`）：`^1 = 5901cd7081dc5a9b12f5d4f51dbed71ef7bb5ae8`（固定目标 tip）、`^2 = 7b622680573c201dec8a4a394f4afdb4a0acde89`（固定来源 tip）
- 合并规模：**76 files changed, 10628 insertions(+), 6 deletions(-)**，与预检 diff 完全一致
- 内容一致性：`git diff 7b62268 HEAD` 为空 —— 合并结果树与来源 tip **逐字节相同**（来源基于目标 tip 线性追加，无并行改动需要融合）

### 3.1 合并后集成复核（无冲突，仍需验证合并树可运行）

```text
bash entry/src/test/run-host-tests.sh
# EXIT 0：1..88 / tests 88 / pass 88 / fail 0 / skipped 0（duration ≈ 2.83s）
```

- 该脚本只读（Node 内置 test runner + `register-ets.mjs`），运行后 `git status --porcelain` 仍为空。
- TAP 输出保存在仓库外 `/tmp/opencode/wp-012-merge-host-tests.tap`，未作为证据提交；长期证据仍以 CQG-T06 已提交的 `entry/src/test/evidence/t06-fix-host-node-tests.tap` 为准。
- Hypium/设备路径仍为 BLOCKED（见 §6 残余项），本次未改变该边界。

## 4. 变更清单摘要（按目录统计）

| 目录 | 文件数 | 增/删行 | 说明 |
|---|---:|---:|---|
| `entry/src/main/ets/common/constants/` | 3 | +232/−0 | 设备/协议/存储常量 |
| `entry/src/main/ets/common/types/` | 9 | +720/−0 | 错误、结果、JSON、端口、安全字节等公共类型 |
| `entry/src/main/ets/common/utils/` | 9 | +1045/−0 | Base64Url、Bytes、DateTime、IP、JSON、UTF-8、UUID 工具 |
| `entry/src/main/ets/model/` | 9 | +1527/−0 | 设备状态/类型/密钥、发现、控制、云、家庭、网关、配网模型 |
| `entry/src/main/ets/service/protocol/` | 8 | +2148/−0 | 协议映射器、序列化器、解析器、错误与偏差 |
| `entry/src/main/ets/service/protocol/dto/` | 5 | +182/−0 | 协议 DTO |
| `entry/src/ohosTest/ets/test/foundation/` | 1 | +60/−0 | 设备侧基础测试（BLOCKED 边界内） |
| `entry/src/test/evidence/` | 12 | +1386/−0 | T-06 构建/静态检查/测试/设备阻塞证据 |
| `entry/src/test/foundation/` | 2 | +76/−0 | Hypium host 基础套件 |
| `entry/src/test/host/` | 7 | +1931/−0 | Node host 套件（协议/领域模型，含 oracle） |
| `entry/src/test/protocol/` | 5 | +300/−0 | Hypium host 协议套件 |
| `entry/src/test`（根） | 2 | +27/−6 | `List.test.ets` 套件注册、`README.md` revision 更新 |
| `artifacts/50-implementation/` | 2 | +523/−0 | `t06-foundation.md`、`t06-fix-report.md` |
| `artifacts/70-review/` | 2 | +471/−0 | `t06-review.md`、`t06-review-b.md` |
| **合计** | **76** | **+10628/−6** | 74 新增 + 2 修改 |

前身文件保护核对（快照范围 `entry/src/test/`、`artifacts/50-implementation/`，合并前共 21 个受跟踪文件）：

- **19/21 逐字节未变**（`git rev-parse 5901cd7:<path>` == `git rev-parse HEAD:<path>`），包括既有 `HostBaseline.test.ets`、`host/*.mjs`（baseline/protocol/perf/oracle/loader）、既有 evidence 日志、`artifacts/50-implementation/build-baseline.md`。
- **2/21 按任务需求修改**：`entry/src/test/List.test.ets`（新增 7 个 T-06 套件 import 与注册，保留原 host 聚合器语义）、`entry/src/test/README.md`（当前 revision 更新为 88/88，并保留 T-05 基线说明）。二者均在 handoff `writes` 内，**未被意外改写**。
- 新增文件只追加，不改写既有产物；无删除、无重命名、无既有 evidence 覆盖。

## 5. 证据提交（恰好一个，紧随 merge 提交）

- 提交主题：`chore(repo): 记录 wp-012 合并集成证据`
- 唯一变更路径：`state/reports/wp-012-merge-report.md`（本报告；`/state/` 被 `.gitignore:37` 忽略，以 `git add -f` 显式暂存，暂存集仅此一个路径）
- 提交前检查：`git diff --cached --check` 通过（无空白错误）；`git diff --cached --name-only` 仅 1 个路径
- 提交后复核：`git show --stat` 仅含单文件；本提交为 merge 提交 `a0c5db6` 的唯一直接后继（`git rev-list --first-parent a0c5db6..HEAD` 长度为 1）
- **证据提交自身 SHA 说明**：提交内容无法内嵌其自身哈希（哈希自引用不可满足），故此处不给字面值。权威值即守卫 `finish wp-012-merge` 写入归档的 `result_commit` 字段；复核命令：`git log -1 --format=%H feat/yaocore-app`（= 本报告所在提交）。

## 6. 门禁证据引用（按来源 tip 固定）

| 项 | 值 |
|---|---|
| 上游裁定 | **CQG-T06 Component Quality Gate — PASS**（Orchestrator，2026-10-17，revision `4d97e41` + 复审 `7b62268`；记录 `state/gates/CQG-T06.md`） |
| 门禁结论 | C-01/C-02/C-03 → **STABLE** @ `4d97e41`；构建 SUCCESS、codelinter 零缺陷、Host 88/88 PASS、R-01..R-13 中 12 Closed + 1 Partially |
| handoff `gate_evidence_path` | `artifacts/70-review/t06-review-b.md` @ `7b62268` |
| 门禁证据 sha256 | `cc616db3338b41fa34225df232989dcd0d83e6d35041bc4f4cfa21d4e1d8e33f`（合并前 `git show 7b62268:<path> \| sha256sum` 与 handoff pin 一致；合并后 `git show a0c5db6:<path>` 同值） |
| 其他随合并落位的证据 | `t06-foundation.md` sha256 `0bbf48ddc5a3429058ddf3c9aab70e184c1e8e3894cfc2042d72b9ef4f350f78`；`t06-fix-report.md` sha256 `371cdb86a8d1805caf395cb6b17457e3044314a1565785ac28477b85d5e1f8d2`；`t06-review.md` sha256 `4894498a2887a339c0cc4edf389a870567499affb3dad038cff649a3d166696a` |
| 合并后复核 | 合并树与来源树 `git diff 7b62268 a0c5db6` 为空，故 CQG 对 `4d97e41` 的验证结论适用于合并结果；本次另重跑 host 88/88 PASS（§3.1） |

必须继续跟踪的 CQG 残余（本次合并不改变其裁定）：

1. **R-13 目录例外**：`common/types/Ports.ets`（T-07 → `contracts/**`）、`service/protocol/` 云映射（T-14 → `service/cloud/**`）。
2. **R2-01（Low）**：ACK 严格 schema 部分失败模式错误码不一致 → C-17/T-19。
3. **R2-02（Low）**：SERVICES 未强制 `Light_01_Brightness` 为 integer → T-14 strict adapter。
4. **V-01**：12-hex nonce 夹具与 DES-A §3.3 冲突 → T-07 必须生成 32-hex；T-19 澄清夹具。
5. **Hypium/设备运行时 BLOCKED**（Linux Previewer/无设备）——长期证据边界，不得折算 PASS。
6. **D-020 流程校准**：后续评审任务采用“预置交付物占位”模式闭环 `finish`。

## 7. 合并后状态与新任务分支

| 项 | 值 |
|---|---|
| `feat/yaocore-app` tip | merge `a0c5db6` + 证据提交（§5；`git log -1 --format=%H`） |
| 工作区 | 干净（`git status --porcelain` 无输出） |
| `task/wp-012-foundation` | 保持 @ `7b62268`，未移动 |
| `main` | 本地 `a6f6558`、`origin/main` `7d6f4c9`，均未移动 |
| 新任务分支 | `task/wp-016-security`：按 handoff 步骤，在 `finish` 成功后从本证据提交 tip 创建（`git branch task/wp-016-security`，**不切换**）；其 tip 即本报告所在提交，创建后以 `git rev-parse` 校验与 `feat/yaocore-app` 相等 |
| 其他 | 未创建 worktree；未 push；未切换/移动其他分支；未使用 reset/force |

## 8. 风险与观察

1. **合并仅完成结构集成，不等于新 Stage Gate**：合并树与来源树逐字节相同，尚无跨组件适配；真正的集成风险从 T-07（Crypto/Security）及后续服务组合开始，届时需 Integration Gate + 回归。
2. **Host 证据边界**：Linux 上可执行的仅是 Node host 路径；Hypium 与设备测试仍 BLOCKED，不能将 88/88 外推为设备侧验证。
3. **远端历史分叉（既有状态）**：本地 `main` 与 `origin/main` 无共同祖先；未来按 `main_merge_mode: review_request_when_remote` 发起 PR/MR 前，需先确认远端基线策略（与 wp-011 报告 §6 相同观察）。
4. **`state/` 被忽略且未 push**：本报告仅存在于本地提交，非远端备份；证据完整性依赖本地仓库与守卫归档。

## 9. 下一步建议

1. Orchestrator 执行 `python3 scripts/swe_guard.py finish wp-012-merge`，确认 `result_commit` 与本报告提交一致。
2. 从证据提交 tip 创建 `task/wp-016-security`（不切换），派发 **T-07 CryptoService + SecurityService**：HMAC 全链、逐条复算 V-01..V-03、强制 32-hex nonce。
3. T-07 及后续任务 handoff 需 pin 本报告 §6 的合并后基线；T-14/T-19 承接 R2-01/R2-02、V-01 与 R-13 目录迁移。
4. 汇总分支完成全部小任务后，在 `feat/yaocore-app` 上运行集成/回归、独立评审与 Stage Gate，再按策略处理受保护 `main` 的 PR/MR（需先解决远端历史对应关系）。
