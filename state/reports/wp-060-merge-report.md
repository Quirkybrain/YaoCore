# wp-060 合并集成报告（task/wp-060-vm → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-060-merge（repository_action: merge）
- **Handoff**: `state/handoffs/wp-060-merge.json`（pin + snapshot + begin 已完成；本报告提交后运行 `finish wp-060-merge`）
- **日期**: 2026-10-18
- **结果**: **MERGE 成功（`--no-ff`，无冲突）；合并后集成验证 PASS（host 613/613、clean 构建成功）**。本次合并将 T-15/T-16 ViewModel 层（C-21/C-22/C-23）实现及其评审/裁定证据带回 `feat/yaocore-app`。本报告是集成证据，**不替代 Stage Gate 判定**。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree） |
| 目标分支 | `feat/yaocore-app` @ `2a37a6a24da753105cf45022c532febe64009bfa`（= handoff `base_commit`；合并前 HEAD 即此） |
| 来源分支 | `task/wp-060-vm` @ `c59fe9862dcb34a5450588c672f4d11194b27b22`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `2a37a6a`（目标 tip，`git merge-base` 实查；来源为基于该 tip 的线性提交链，仍按策略强制 `--no-ff`） |
| 工作区 | 干净（`git status --porcelain` 无输出） |
| 守卫状态 | ACTIVE `wp-060-merge`（begin 已完成）；未见其他活动任务 |
| 快照 | `refs/swe/snapshots/20261017T163420Z-wp-060-merge-af778feb` @ `8c83647380a2b7b9d4b01f866f974e899937835f`，tree `c109986796928346a721deafcb5548c9d6b67d49`（`SWE snapshot wp-060-merge`） |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；已执行 `git fetch origin`（exit 0）；`origin/main` @ `7d6f4c9`；远端不存在 `feat/yaocore-app`；本次**未 push** |
| 本地 `main` | `a6f6558`（未移动） |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- `gate_evidence_path` `artifacts/70-review/t15-16-review-c.md` sha256 `f773f884533a11f36ee0151b3cf13ba70c222354f6e887e35a23e275fa4fe2cc`（在来源 tip `c59fe98` 上实查一致，= handoff `gate_evidence_path_sha256`）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用 `config/git-policy.default.md` 默认规范，无公司策略覆盖）

## 2. 来源与预检

来源提交链（`git log --oneline 2a37a6a..c59fe98`，8 个提交）：

```text
c59fe98 docs(review): T-15/16 聚焦复审（R2 项关闭确认）
3dd0639 fix(viewmodel): 修正门锁命令值并按设备隔离节流
59c27b1 docs(review): T-15/16 复审（F 项与 U-01 关闭确认）
e77b192 fix(viewmodel): 加固门锁控制确认值语义
625eabe fix(viewmodel): 修复 T-15/16 评审发现并修通 C-18 编译
1e7487e docs(design): 裁定成员加入完成状态语义
8369218 docs(review): T-15/16 ViewModel 独立评审
ffadebf feat(viewmodel): 实现设备家庭场景与配网视图模型
```

预检结果：目标工作区干净；来源 tip 精确等于 handoff `source_commit`；目标 tip 是来源 tip 的祖先（线性链，无分叉）；`git diff --stat 2a37a6a..c59fe98` 为 **61 files changed, 23132 insertions(+), 40 deletions(-)**；目标分支不存在 `entry/src/main/ets/viewmodel/`（本任务新增目录）。

## 3. 合并

- 命令：`git merge --no-ff task/wp-060-vm -m "chore(merge): 合并 T-15/16 ViewModel 实现到 feat/yaocore-app"`
- 合并提交：`b3105d4efbff936bbb28ef4623821bcafa539178`
- 父提交：`2a37a6a`（目标，第一父）+ `c59fe98`（来源，第二父）
- 策略：`ort`；**无冲突**（未手工编辑任何文件）
- 树一致性：`git diff --stat c59fe98..HEAD` 为空，即合并结果树与来源 tip 完全一致（目标自 base 后无独立提交）

## 4. 变更统计（`2a37a6a..c59fe98`，按目录）

| 目录 | 文件数 | + | − |
|---|---:|---:|---:|
| `artifacts/40-detailed-design/`（DES-001B 修订） | 1 | 100 | 19 |
| `artifacts/50-implementation/`（`t15-16-vm.md`、`t15-16-fix-report.md`、`t15-16-fix2-report.md`） | 3 | 536 | 0 |
| `artifacts/70-review/`（`t15-16-review.md`、`-review-b.md`、`-review-c.md`） | 3 | 627 | 0 |
| `entry/src/main/ets/viewmodel/`（**新目录**：10 个 ViewModel/端口 + `core/` 4 个） | 14 | 5289 | 0 |
| `entry/src/main/ets/service/`（`family/` 2 + `gateway/` 1） | 3 | 78 | 11 |
| `entry/src/ohosTest/ets/test/`（`List.test.ets`、README、`viewmodel/ViewModelsDevice.test.ets`） | 3 | 72 | 2 |
| `entry/src/test/README.md` | 1 | 21 | 4 |
| `entry/src/test/host/`（16 个 host 测试/辅助文件） | 16 | 3134 | 4 |
| `entry/src/test/evidence/`（17 个构建/测试/探针日志） | 17 | 13275 | 0 |
| **合计** | **61** | **23132** | **40** |

设计文档修订明细（净 diff）：

| 文档 | 净 +/− | 归属提交 |
|---|---|---|
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | +100 / −19 | `1e7487e`（T-15/16 裁定同步：成员加入完成状态语义；不改变冻结签名与既有 DES-B 基线） |

`entry/src/main/ets/viewmodel/` 明细：根目录 `BleProvisioningViewModel`、`ClimateViewModel`、`DeviceViewModel`、`DoorViewModel`、`FamilyViewModel`、`HomeViewModel`、`RoomViewModel`、`SceneViewModel`、`SettingsViewModel`、`ViewModelPorts`；`core/` 下 `DeviceControlCoordinator`、`DoorConfirmationTracker`、`ThrottleGate`、`ViewModelCore`。`service/` 修改为 `FamilyJoinSession`、`FamilyModels`、`GatewayDiscoveryService`（C-18 编译与成员加入语义配套）。

## 5. 前身保护确认

目标分支中已存在的 DES-001B 由合并前快照保护；快照内字节与合并前目标字节一致：

| 文档 | 快照/合并前 blob | 快照/合并前 sha256 | 合并后 sha256（= 来源 tip） |
|---|---|---|---|
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | `67ea6606bebdf5aba9035ad41a4f3237d4410205` | `e8d3869b099008e493ca5a67bed7f54ca2506a761520cc4293c4d6152d184083` | `42e6912806e39a490aecc36b42b33e717419dc098a4c387d11f9a46fec0b310d` |

- 快照 ref 可完整恢复合并前状态；快照内 DES-001B blob 与合并前目标完全一致（`67ea660`）。
- 目标分支合并前不存在 `entry/src/main/ets/viewmodel/`（快照内同样 absent），该目录由本任务新增，无覆盖前身文件。
- 本次未改写历史、未 reset、未 force；合并提交保留双亲，来源修订以独立提交进入历史（`1e7487e` 等），可追溯。

## 6. 合并后验证（在 `b3105d4` 上执行）

| 检查 | 命令 | 结果 |
|---|---|---|
| Host 测试 | `bash entry/src/test/run-host-tests.sh` | ✅ **613/613 PASS**（`# tests 613 / # pass 613 / # fail 0 / # skipped 0 / # todo 0`，duration ≈ 3024 ms） |
| 构建 | `hvigorw clean assembleHap --no-daemon` | ✅ **BUILD SUCCESSFUL in 4 s 917 ms**（35 tasks：34 executed / 1 up-to-date；签名跳过警告为预期，项目未配置 signingConfigs） |
| 工作区 | `git status --porcelain` | ✅ 干净（构建产物均被忽略） |

说明：本任务未复跑 codelinter；静态检查证据沿用 CQG-T15/T16 判定的 `t15-16-fix*/codelinter.log`（合并树与来源树一致）。

## 7. 冲突

**无冲突**。`ort` 自动合并；目标 tip 是来源 tip 的直接祖先，DES-001B 的修改以来源版本线性覆盖并保留 `1e7487e` 提交归属；`viewmodel/` 为纯新增目录。

## 8. 门禁引用

- Gate：`state/gates/CQG-T15-T16.md` — **PASS（组件级）**；C-21/C-22/C-23 → STABLE（代码级，条件式）@ `3dd0639`（聚焦复审 `c59fe98`）。
- 门禁证据：`artifacts/70-review/t15-16-review-c.md` sha256 `f773f884533a11f36ee0151b3cf13ba70c222354f6e887e35a23e275fa4fe2cc`。
- 残余（不因合并而关闭）：R3-01 跨设备并发/失败隔离用例 → T-17/T-19 前补；R3-02 `cancelContinuous` 后 `endContinuous` 调用顺序 → T-17 接线或契约澄清；F-05 `GATEWAY_CONFIRMED` 中间态不可观察；U-02 `settings.cloud.single_gateway_required`/`brand.*` 资源键 → T-18；U-03 `pinMatched`/`rotationRecommended`/`addGatewayToFamily` → C-18/C-27/C-08；设备/真实网络/UI 时序 → T-19/T-20（BLOCKED）。详见 CQG-T15/T16 §条件与残余。

## 9. 分支与下一步

- 合并后 `feat/yaocore-app` tip：本证据提交（主题 `chore(repo): 记录 wp-060 合并集成证据`，第一父为合并提交 `b3105d4`）。
- `finish wp-060-merge` 校验通过后，从本证据提交（新 tip）创建 `task/wp-067-ui-shell`（不切换、不建 worktree），分支 tip 即本证据提交。
- 下一步：派发 **T-17**（应用壳/导航/组合根/权限/资源），见 CQG-T15/T16 §Next action。
- 约束遵守：未 push；未切换/移动其他分支；未创建 worktree；未修改本报告之外文件；未使用 reset/force。

```text
Evidence commit subject: chore(repo): 记录 wp-060 合并集成证据
Evidence commit: 见 feat/yaocore-app tip（本报告提交）
Merge commit: b3105d4efbff936bbb28ef4623821bcafa539178
Source tip: c59fe9862dcb34a5450588c672f4d11194b27b22
Target pre-merge: 2a37a6a24da753105cf45022c532febe64009bfa
Post-merge host tests: 613/613 PASS
Post-merge build: BUILD SUCCESSFUL
```
