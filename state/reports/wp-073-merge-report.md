# wp-073 合并集成报告（task/wp-073-ui-pages → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-073-merge（repository_action: merge）
- **Handoff**: `state/handoffs/wp-073-merge.json`（pin + snapshot + begin 已完成；本报告提交后运行 `finish wp-073-merge`）
- **日期**: 2026-10-18
- **结果**: **MERGE 成功（`--no-ff`，无冲突）；合并后集成验证 PASS（host 694/694、clean 构建成功）**。本次合并将 T-18 设计系统（C-24）与全量页面（C-25/C-26/C-27）实现、DES-A/DES-B 增量契约与 D-12 修订及其四轮评审证据带入 `feat/yaocore-app`。本报告是集成证据，**不替代 Stage Gate 判定**。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree） |
| 目标分支 | `feat/yaocore-app` @ `6737303929bbe868a552da7f985dc46c8fdf1aed`（= handoff `base_commit`；合并前 HEAD 即此） |
| 来源分支 | `task/wp-073-ui-pages` @ `21db67fbac094515f53d06fda422d6c7febcdb6b`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `6737303`（目标 tip，`git merge-base` 实查；来源为基于该 tip 的线性提交链，仍按策略强制 `--no-ff`） |
| 工作区 | 干净（`git status --porcelain` 无输出） |
| 守卫状态 | ACTIVE `wp-073-merge`（begin 已完成）；未见其他活动任务 |
| 快照 | `refs/swe/snapshots/20261017T191652Z-wp-073-merge-4eaa5d00` @ `e8911cc9816a4d677229024627213e6eae732101`，tree `6069f19f32dec587066477c38baa4f3ae0a8f1fa`（`SWE snapshot wp-073-merge`，父提交 `6737303`，捕获 handoff 声明的 10 个路径 + handoff 本身，共 656 个文件条目） |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；已执行 `git fetch origin --prune`（exit 0）；`origin/main` @ `7d6f4c99fa1bf0baf5e40d1948a97f564a647401`；本次**未 push** |
| 本地 `main` | `a6f6558882f7ec53be548c85e15a1a291c5a41fd`（未移动） |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- `gate_evidence_path` `artifacts/70-review/t18-review-d.md` sha256 `3f940e840c6e0034aab22cb510d84af0b2aabe9bc6fb8932adcb46b58da131ad`（在来源 tip `21db67f` 上实查一致，= handoff `gate_evidence_path_sha256`；合并后树中再次复核一致）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用 `config/git-policy.default.md` 默认规范，无公司策略覆盖）

## 2. 来源与预检

来源提交链（`git log --oneline 6737303..21db67f`，11 个提交；与任务说明实查一致）：

```text
21db67f docs(review): T-18 最终聚焦复审（R3-02 关闭确认）
967e266 fix(provisioning): 加取消代际防止晚到提交绑定
78eaca9 docs(review): T-18 聚焦复审（R2 与契约登记关闭确认）
4b99e64 docs(design): 登记 T-18 增量契约与 D-12 修订
74e9157 fix(ui): 隐藏引导打开时的关联门磁重复入口
f6e9c9b fix(ui): 修复 T-18 复审 R2 项
8f3d969 docs(review): T-18 复审（核心 F 项关闭确认）
a9d0bb5 fix(ui): 修复 T-18 评审发现
7974305 docs(review): T-18 页面组件独立评审
155be17 test(ui): 增加 T-18 页面设备编译骨架
ba9dca6 feat(ui): 实现设计系统与全量页面
```

预检结果：目标工作区干净；来源 tip 精确等于 handoff `source_commit`；目标 tip 是来源 tip 的直接祖先（`git merge-base` = `6737303`，来源线性链无分叉）；`git diff --stat 6737303..21db67f` 为 **79 files changed, 22801 insertions(+), 813 deletions(-)**；目标分支不存在 `entry/src/main/ets/components/` 与 `entry/src/main/ets/common/theme/`（本任务新增目录）；目标分支已存在 `artifacts/40-detailed-design/des-001a-foundation-transport.md` 与 `des-001b-domain-presentation.md`（由来源 `4b99e64` 修订，受合并前快照保护）。

## 3. 合并

- 命令：`git merge --no-ff task/wp-073-ui-pages -m "chore(merge): 合并 T-18 全量页面与设计系统到 feat/yaocore-app"`
- 合并提交：`b764f9b15b401deb9630a8f08e3add08d683fc18`（主题 `chore(merge): 合并 T-18 全量页面与设计系统到 feat/yaocore-app`）
- 父提交：`6737303`（目标，第一父）+ `21db67f`（来源，第二父）
- 策略：`ort`；**无冲突**（未手工编辑任何文件）
- 树一致性：`git diff --stat 21db67f..b764f9b` 为空，即合并结果树与来源 tip 完全一致（目标自 base 后无独立提交）

## 4. 变更统计（`6737303..b764f9b`，按目录）

| 目录 | 文件数 | + | − |
|---|---:|---:|---:|
| `artifacts/40-detailed-design/`（DES-001A + DES-001B 修订，`4b99e64`） | 2 | 258 | 13 |
| `artifacts/50-implementation/`（`t18-ui-pages.md` + 3 份修复报告） | 4 | 566 | 0 |
| `artifacts/70-review/`（`t18-review.md`、`-b`、`-c`、`-d` 四轮评审） | 4 | 821 | 0 |
| `entry/src/main/ets/app/`（`AppContext`、`AppContextAdapters`、`PageVmFactory`、`NavigationService` 等；删除 `ShellTheme.ets` 迁至 theme） | 8 | 190 | 74 |
| `entry/src/main/ets/common/theme/`（**新目录**：`AppEnums`、`AppTheme`、`ShellTheme`） | 3 | 305 | 0 |
| `entry/src/main/ets/components/`（**新目录**：`CommonControls`、`DeviceCards`、`DeviceGrid`、`RoomChipBar`、`StatusPanels`、`support/UiMapping`） | 6 | 2297 | 0 |
| `entry/src/main/ets/pages/`（全量页面改造；删除 `PlaceholderContent.ets`） | 16 | 5093 | 305 |
| `entry/src/main/ets/service/`（BLE provisioning 端口/服务/取消代际、Room/Scene 服务） | 5 | 257 | 25 |
| `entry/src/main/ets/viewmodel/`（BLE/Room/Scene/Settings 视图模型与端口） | 5 | 256 | 44 |
| `entry/src/main/resources/`（base/dark `color.json` 设计 token、zh-CN/en-US i18n） | 4 | 1490 | 333 |
| `entry/src/ohosTest/`（`UiPagesDevice.test.ets` + `List.test.ets` 注册） | 2 | 92 | 0 |
| `entry/src/test/`（host `UiPages.test.mjs` 等 7 个测试变更 + 12 个 evidence 日志） | 20 | 11176 | 19 |
| **合计** | **79** | **22801** | **813** |

设计文档修订明细（净 diff，均归属 `4b99e64`）：

| 文档 | 净 +/− | 内容 |
|---|---|---|
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | +69 / −13 | T-18 增量契约登记（BLE provisioning 取消代际/端口扩展等） |
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | +202 / −13 | T-18 增量契约与 D-12 白名单修订（页面 DTO/枚举边界、设计系统约定） |

## 5. 前身保护确认

目标分支中已存在的 DES-001A/DES-001B 由合并前快照保护；快照内字节与合并前目标字节一致：

| 文档 | 快照/合并前 blob | 快照/合并前 sha256 | 合并后 sha256（= 来源 tip） |
|---|---|---|---|
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `e44ba54474fcc9e12f88abc032161aa63c179676` | `3a02ecbf266bfcc293bb648e89fa8d594831c1e07adf38900f6061dd51f12121` | `6c0f0a4e3abd8249e187eb754c2e348bfe9a1944ee64c71cf1f7597bb4c27b6c` |
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | `f5f481db75b25a4abe7940c037942de4c3d15ee2` | `975d873a2403a43c4ead04c3c81e2badf5e4a75dc49225ecdff67c837ff8518b` | `645876f9b07f2ab837dd35ba029aaa14290a2a98d86046ab6b5c805f5ffbb521` |

- 快照 ref 可完整恢复合并前状态；两份设计文档的快照 blob 与合并前目标完全一致。
- 目标分支合并前不存在 `entry/src/main/ets/components/` 与 `entry/src/main/ets/common/theme/`（快照内同样 absent），二者为纯新增；`pages/` 仅 `PlaceholderContent.ets` 删除、其余为改造/新增；`app/ShellTheme.ets` 删除并以 `common/theme/ShellTheme.ets` 承接。
- 本次未改写历史、未 reset、未 force；合并提交保留双亲，来源修订以独立提交进入历史（`4b99e64` 等），可追溯。

## 6. 合并后验证（在 `b764f9b` 上执行）

| 检查 | 命令 | 结果 |
|---|---|---|
| Host 测试 | `bash entry/src/test/run-host-tests.sh` | ✅ **694/694 PASS**（`# tests 694 / # pass 694 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`，duration ≈ 2999 ms） |
| 构建 | `hvigorw clean assembleHap --no-daemon` | ✅ **BUILD SUCCESSFUL in 14 s 577 ms**（35 tasks：34 executed / 1 up-to-date；生产图全量编译；签名跳过警告为预期，项目未配置 signingConfigs） |
| 工作区 | `git status --porcelain` | ✅ 干净（构建产物均被忽略） |

说明：本任务未复跑 codelinter 与 i18n checker；静态检查/i18n 证据沿用 CQG-T18 判定的 `t18-*-codelinter.log`、`t18-i18n-checker.log`（合并树与来源树一致）。设备/UI 视觉/A11y/真实 BLE/LAN/云验证仍按 CQG-T18 保持 **BLOCKED**（T-19）。

## 7. 冲突

**无冲突**。`ort` 自动合并；目标 tip 是来源 tip 的直接祖先；DES-A/DES-B 的修改以来源版本线性覆盖并保留 `4b99e64` 提交归属；`components/` 与 `common/theme/` 为纯新增目录。

## 8. 门禁引用

- Gate：`state/gates/CQG-T18.md` — **PASS（代码级）**；C-24/C-25/C-26/C-27 → **STABLE（代码级，条件式）** @ `967e266`（评审至 `21db67f`）。
- 门禁证据：`artifacts/70-review/t18-review-d.md` sha256 `3f940e840c6e0034aab22cb510d84af0b2aabe9bc6fb8932adcb46b58da131ad`。
- 残余（不因合并而关闭）：GAP-T18-01 `addGatewayToFamily` RBAC 缺口（D-030 书面接受，Stage Gate 必须记录）；R3-01 pages DTO/枚举 D-12 allowlist → T-20；R4-01 取消后 durable 边界 → T-19/文档；F-15/F-17/F-21 → T-20/T-19；设备/视觉/动效/读屏/BLE/LAN/云 → T-19；IG-3 **NOT READY**。详见 CQG-T18 §条件与残余。

## 9. 分支与下一步

- 合并后 `feat/yaocore-app` tip：本证据提交（主题 `chore(repo): 记录 wp-073 合并集成证据`，第一父为合并提交 `b764f9b`）。
- `finish wp-073-merge` 校验通过后，从本证据提交（新 tip）创建 `task/wp-082-verify`（不切换、不建 worktree），分支 tip 即本证据提交。
- 下一步：派发 **T-19**（全量测试矩阵与证据；设备/视觉/A11y/BLE/LAN/云验证解阻）与 **T-20**（R3-01 D-12 allowlist 收口及 F-15/F-17/F-21 跟踪项）；IG-3 在设备矩阵与 T-20 完成前维持 NOT READY。
- 约束遵守：未 push；未切换/移动其他分支；未创建 worktree；未修改本报告之外文件；未使用 reset/force。

```text
Evidence commit subject: chore(repo): 记录 wp-073 合并集成证据
Evidence commit: 见 feat/yaocore-app tip（本报告提交）
Merge commit: b764f9b15b401deb9630a8f08e3add08d683fc18
Source tip: 21db67fbac094515f53d06fda422d6c7febcdb6b
Target pre-merge: 6737303929bbe868a552da7f985dc46c8fdf1aed
Post-merge host tests: 694/694 PASS
Post-merge build: BUILD SUCCESSFUL
```
