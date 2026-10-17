# wp-035 合并集成报告（task/wp-035-transport → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-035-merge（repository_action: merge）
- **Handoff**: `state/handoffs/wp-035-merge.json`（pin + snapshot + begin 已完成；本报告提交后运行 `finish wp-035-merge`）
- **日期**: 2026-10-17
- **结果**: SUCCESS —— `--no-ff` 合并完成、无冲突；合并树与来源 tip 逐字节一致；合并后 host 回归 355/355 PASS；恰好一个证据提交（本报告）；待守卫 `finish wp-035-merge` 归档。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree） |
| 目标分支 | `feat/yaocore-app` @ `4ae8af24df938227fdcc22b63f93168e5cb24aa2`（= handoff `base_commit`；合并前 HEAD 即此） |
| 来源分支 | `task/wp-035-transport` @ `8c095f27e49fe759b2572138a4b776456564bd53`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `4ae8af2`（目标 tip；来源为线性追加 5 提交，仍按策略强制 `--no-ff`） |
| 工作区 | 干净（`git status --porcelain=v1 --untracked-files=all` 无输出） |
| 守卫状态 | ACTIVE `wp-035-merge`（begin 已完成）；合并前无其他活动任务 |
| 快照 | `refs/swe/snapshots/20261017T123903Z-wp-035-merge-2a18728d` @ `94782e95f0dd3bd254d159786070caad0d1635b0`（7 个选择路径、228 个文件；含 handoff 自身） |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；`origin/main` @ `7d6f4c9`；`feat/yaocore-app` 无上游、远端无同名分支；本次**未 fetch 变更、未 push**（`git ls-remote` 仅只读查询，远端无 `feat/yaocore-app`） |
| 本地 `main` | `a6f6558`（未移动） |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序` 出现次数 = 1）
- `state/handoffs/wp-035-merge.json` sha256 `164c6e18490080a9b6986dbcb4bf401175976a50a1487a59afe1e2aabe6c7382`（与 begin 记录一致）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用 `config/git-policy.default.md` 默认规范，无公司策略覆盖）

预检差异复核：`git diff --stat 4ae8af2..8c095f2` = **47 files changed, 13671 insertions(+), 7 deletions(-)**；`--name-status` 为 41 个 `A` + 6 个 `M`，无 `D`/`R`；`git diff --check 4ae8af2..8c095f2` 通过。全部路径落在 handoff `writes` 范围内，**无范围外文件**。

## 2. 来源提交（5 个）

| # | SHA | 主题 |
|---|---|---|
| 1 | `698883f7b8b57808750d51311cc0c1302a66bacb` | `feat(transport): 实现局域网传输发现与 Mock 服务` |
| 2 | `3285d4b882e96204e6ea44a28778c6d2210ddf1f` | `docs(review): T-11 传输层独立评审` |
| 3 | `36ce10bcd8ae23f8622b04b04d09481014b3dcc7` | `fix(transport): 修复 T-11 评审发现` |
| 4 | `514671d8cdcb47a46073a1a58d260d8fd03a07f9` | `build(compat): 核验 API14 兼容性配置` |
| 5 | `8c095f27e49fe759b2572138a4b776456564bd53` | `docs(review): T-11 聚焦复审（F-01 至 F-12 关闭确认）` |

## 3. 合并执行

按 pin 的 `merge_strategy: no-ff` 与 handoff 指定主题执行：

```text
git merge --no-ff task/wp-035-transport -m "chore(merge): 合并 T-11 传输层实现到 feat/yaocore-app"
```

- 结果：`Merge made by the 'ort' strategy`；**无冲突**（未发生 rebase、reset、amend 或强制操作）。
- **merge 提交**：`1b4c671a3f1c5b3a494af5a41fa7c5b738a55426`
- 主题：`chore(merge): 合并 T-11 传输层实现到 feat/yaocore-app`（与 handoff 指定主题逐字一致）
- 双亲验证（`git rev-list --parents -n 1 1b4c671`）：`^1 = 4ae8af24df938227fdcc22b63f93168e5cb24aa2`（固定目标 tip）、`^2 = 8c095f27e49fe759b2572138a4b776456564bd53`（固定来源 tip）
- 合并规模：**47 files changed, 13671 insertions(+), 7 deletions(-)**，与预检 diff 完全一致
- 内容一致性：`git diff --quiet 8c095f2 1b4c671` 通过（exit 0）—— 合并结果树与来源 tip **逐字节相同**。因此 CQG-T11 在 `514671d` 代码 revision（复审 @ `8c095f2`）上的验证结论可直接适用于合并结果。

### 3.1 合并后集成复核

```text
bash entry/src/test/run-host-tests.sh
# EXIT 0：1..355 / tests 355 / pass 355 / fail 0 / cancelled 0 / skipped 0
```

- 该脚本只读（Node 内置 test runner + `register-ets.mjs`），运行后 `git status --porcelain` 仍为空。
- TAP 输出未作为新证据提交；长期证据仍以 CQG-T11 已提交的 `entry/src/test/evidence/t11-fix-host-node-tests.tap`（355/355）为准。
- Hypium/设备路径仍为 BLOCKED（见 §6、§10），本次未改变该边界。

## 4. 变更清单摘要（按目录统计）

| 目录 | 文件数 | 增/删行 | 说明 |
|---|---:|---:|---|
| `entry/src/main/ets/service/` | 16 | +3314/−0 | gateway（服务/策略/端口/适配器/discovery）、mock、ble 端口、device 命令执行器扩展 |
| `entry/src/test/` | 17 | +6743/−6 | host 套件（Discovery/Local/Mock/Boundary/DomainDevice）、TransportFakes、11 份 T-11 证据、README 更新 |
| `entry/src/ohosTest/ets/test/` | 3 | +100/−0 | `gateway/GatewayTransportDevice.test.ets`、`List.test.ets`、README |
| `artifacts/50-implementation/` | 8 | +3026/−0 | `t11-transport.md`、`t11-fix-report.md`、`t11-build-compat.md` + 5 份 build-compat 证据日志 |
| `artifacts/70-review/` | 2 | +486/−0 | `t11-review.md`、`t11-review-b.md` |
| `build-profile.json5` | 1 | +2/−1 | API14 兼容性配置（见 §4.1） |
| **合计** | **47** | **+13671/−7** | 41 新增 + 6 修改；无删除/重命名 |

### 4.1 `build-profile.json5` 变更（受保护前身）

来源分支对既有 `build-profile.json5` 做了 3 行变更（+2/−1），合并后与来源 tip 逐字节一致：

```diff
         "name": "default",
         "signingConfig": "default",
+        "compileSdkVersion": "26.0.0",
         "targetSdkVersion": "26.0.0",
-        "compatibleSdkVersion": "26.0.0",
+        "compatibleSdkVersion": "5.0.2(14)",
         "runtimeOS": "HarmonyOS",
```

含义：编译 SDK 仍为 26.0.0，运行时最低兼容下调至 API 14（`5.0.2(14)`），由 `514671d` 的构建兼容核验支撑（HAP `minAPIVersion=50002014`、compatible=14，见 `artifacts/50-implementation/t11-build-compat.md`）。该变更属 handoff `writes` 内，且原始字节已由快照保存（§5）。

## 5. 前身保护核对

快照范围 `entry/src/main/ets/service/`、`entry/src/test/`、`entry/src/ohosTest/ets/test/`、`build-profile.json5`、`artifacts/50-implementation/`、`artifacts/70-review/` 及 handoff 自身，合并前共 **228 个文件**：

- 快照覆盖哈希与本报告生成时工作区逐路径比对：**228/228 匹配，mismatch = 0**；快照 ref `94782e9` 内含全部原始字节。
- 合并涉及的既有前身 **6/6 均被快照覆盖**，且快照保存的是合并前原始字节：

| 文件 | 变更 | 预期性核对 |
|---|---|---|
| `build-profile.json5` | +2/−1 | API14 兼容性配置（`514671d`，CQG-T11 构建条件） |
| `entry/src/main/ets/service/device/DeviceCommandRunner.ets` | 修改 | T-11 传输命令接线（+16 行） |
| `entry/src/test/host/DomainDevice.test.mjs` | +55/−0 | 回归适配（host 套件） |
| `entry/src/test/README.md` | +25/−6 | 当前 revision 更新为 355/355，登记 T-11 测试/证据 |
| `entry/src/ohosTest/ets/test/List.test.ets` | 修改 | 注册 gateway 设备套件 |
| `entry/src/ohosTest/ets/test/README.md` | 修改 | 登记 gateway 设备套件（BLOCKED 边界） |

- 快照范围内另新增 **41 个文件**（gateway/mock/ble 实现、host/设备测试、T-11 工件与证据）；**无删除、无重命名、无既有 evidence 覆盖**。
- `build-profile.json5` 合并前 sha256 = `810fc1e7293f5581220f36bc2383ed91a426f7697262b758d8e21ba3cce217bf`，与快照 `94782e9:build-profile.json5` 完全一致；`finish` 可据快照验证并恢复被修改前身。

## 6. 门禁证据引用（按来源 tip 固定）

| 项 | 值 |
|---|---|
| 上游裁定 | **CQG-T11 Component Quality Gate — PASS（代码级）**（Orchestrator，2026-10-17；实现 `698883f` + 修复 `36ce10b` + 构建兼容 `514671d`；复审 @ `8c095f2`；记录 `state/gates/CQG-T11.md`） |
| 门禁结论 | C-17/C-18/C-20 → **STABLE（代码级，条件式）** @ `514671d`；构建 SUCCESS（含 ohosTest 编译，HAP `minAPIVersion=50002014`、compatible=14）、codelinter 零缺陷、Host **355/355 PASS**、F-01..F-12：F-01..F-06/F-09..F-12 Closed（F-07/F-08 转 T-19/T-20）、传输安全三通道禁明文回退；设备/PB-03 运行时保持 `BLOCKED` |
| handoff `gate_evidence_path` | `artifacts/70-review/t11-review-b.md` @ `8c095f2`（轮 2 复审 PASS，条件式） |
| 门禁证据 sha256 | `bfdf0176e43c9ba61d29d8a4737bf0188b6be22146fc8039e80d10405660dda7`（合并前 `git show 8c095f2:<path> \| sha256sum` 与 handoff pin 一致；合并后 `git show 1b4c671:<path>` 同值） |
| 其他随合并落位的证据 | `artifacts/70-review/t11-review.md`、`artifacts/50-implementation/t11-transport.md`、`t11-fix-report.md`、`t11-build-compat.md` 及 5 份 build-compat 日志、11 份 `entry/src/test/evidence/t11-*` 日志/TAP |
| CQG 记录 | `state/gates/CQG-T11.md` sha256 `a4aa9a822d9e82cfe98c91586180b1f4a3cd6a02f6e9f0464ef05fb92f9f9ecb`（工作区文件；`state/` 被忽略，仅本地） |
| 合并后复核 | 合并树与来源树 `git diff 1b4c671^2 1b4c671` 为空，故 CQG 对 `514671d`/`8c095f2` 的验证结论适用于合并结果；本次另重跑 host 355/355 PASS（§3.1） |

必须继续跟踪的 CQG-T11 条件与残余（本次合并不改变其裁定）：

1. **PB-03 运行时**：Path B 语义（`skipRemoteValidation`/`getRemoteCertificate`/SPKI 对齐）、TLS 版本、错误码区分、p95 → T-19 设备矩阵；期间 P-TLS-PIN 不得声称已验证。
2. **F-07/F-08**：HAP source-map 探针非区分性（组合根后重跑）；设备占位 `it` 修正 → T-19/T-20。
3. **D-4/R-20**：`RESPONSE_*` vs `CONTROL_*/ACK_*` 错误码命名 → solution-architect 统一裁定。
4. **R2-01**：C-10 编译期 import C-17 `GatewayRequestPolicy`（纯逻辑无环）→ architect 确认共享分工。
5. **R-21/R-22**：`usingCache:false` 运行时与 API 14 运行时兼容 → T-19。
6. **R2-02**：P-TLS `control()` "无 TlsVerification → TLS_VERIFIER_UNAVAILABLE" 负例 → T-19/后续补测。

## 7. 冲突

**无冲突**。目标 `feat/yaocore-app` 的 tip 为来源分支祖先，`--no-ff` 合并由 `ort` 策略生成双亲提交；未修改任何冲突文件，未触发 rebase/reset/force。`build-profile.json5` 虽为目标分支既有文件，但与来源修改基于同一基线、无重叠冲突，合并后内容即来源版本。

## 8. 证据提交（恰好一个，紧随 merge 提交）

- 提交主题：`chore(repo): 记录 wp-035 合并集成证据`
- 唯一变更路径：`state/reports/wp-035-merge-report.md`（本报告；`state/` 被 `.gitignore` 忽略，以 `git add -f` 显式暂存，暂存集仅此一个路径）
- 提交前检查：`git diff --cached --check` 通过（无空白错误）；`git diff --cached --name-only` 仅 1 个路径；`git show --stat` 仅含单文件
- 提交后复核：本提交为 merge 提交 `1b4c671` 的唯一直接后继（`git rev-list --first-parent 1b4c671..HEAD` 长度为 1）
- **证据提交自身 SHA 说明**：提交内容无法内嵌其自身哈希（哈希自引用不可满足），故此处不给字面值。权威值即守卫 `finish wp-035-merge` 写入归档的 `result_commit` 字段；复核命令：`git log -1 --format=%H feat/yaocore-app`（= 本报告所在提交）。

## 9. 合并后状态与新任务分支

| 项 | 值 |
|---|---|
| `feat/yaocore-app` tip | merge `1b4c671` + 证据提交（本报告，§8；`git log -1 --format=%H`） |
| 工作区 | 干净（`git status --porcelain` 无输出） |
| `task/wp-035-transport` | 保持 @ `8c095f2`，未移动 |
| `main` | 本地 `a6f6558`、`origin/main` `7d6f4c9`，均未移动 |
| 新任务分支 | `task/wp-040-ble`：按 handoff 步骤，在 `finish` 成功后从本证据提交 tip 创建（`git branch task/wp-040-ble`，**不切换**）；其 tip = 本证据提交（创建后以 `git rev-parse` 校验与 `feat/yaocore-app` 相等） |
| 其他 | 未创建 worktree；未 push；未切换/移动其他分支；未使用 reset/force；未 amend |

## 10. 风险与观察

1. **合并仅完成结构集成，不等于新的 Stage Gate**：合并树与来源树逐字节相同，尚无跨组件适配；T-12 BLE、T-17/T-18 接线后，应按 Integration Gate 执行回归。
2. **API14 兼容性已生效**：`compatibleSdkVersion` 由 `26.0.0` 下调为 `5.0.2(14)`，后续 HAP 构建与设备矩阵须以 API 14 为最低基线复核；不得在未验证情况下恢复旧值。
3. **Host 证据边界**：Linux 上可执行的仅是 Node host 路径；Hypium 与设备测试仍 BLOCKED，不能将 355/355 外推为设备侧验证。
4. **PB-03/TLS pin 仍未运行时验证**：Path B 语义与真实 TLS/mDNS/HTTP 缓存/BLE 交互 → T-19；相关 Gate 不得折算为 PASS。
5. **错误码命名与共享分工待裁定**：D-4/R-20（`RESPONSE_*` vs `CONTROL_*/ACK_*`）与 R2-01（C-10 编译期依赖 C-17 纯逻辑）需 architecture owner 确认，避免后续契约漂移。
6. **`state/` 被忽略且未 push**：本报告仅存在于本地提交，非远端备份；证据完整性依赖本地仓库与守卫归档。远端亦无 `feat/yaocore-app` 分支。
7. **远端历史分叉（既有状态）**：本地 `main` 与 `origin/main` 无共同祖先；未来按 `main_merge_mode: review_request_when_remote` 发起 PR/MR 前，需先确认远端基线策略。

## 11. 下一步建议

1. Orchestrator 执行 `python3 scripts/swe_guard.py finish wp-035-merge`，确认 `result_commit` 与本报告提交一致、`status` 无活动任务。
2. 从证据提交 tip 创建 `task/wp-040-ble`（不切换），派发 **T-12 BLE 配网**；handoff 显式带入 CQG-T11 残余（PB-03/T-19、F-07/F-08、D-4/R-20、R2-01/R-21/R-22、R2-02）与 `state/gates/CQG-T11.md`。
3. T-19/T-20 承接设备/运行时证据与 API 14 运行时兼容复核；T-12 完成后按 Integration Gate 验证 BLE 与传输层组合行为。
4. 后续主线按 `main_merge_mode: review_request_when_remote` 处理受保护 `main` 的 PR/MR（需先解决远端历史对应关系）。
