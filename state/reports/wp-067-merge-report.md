# wp-067 合并集成报告（task/wp-067-ui-shell → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-067-merge（repository_action: merge）
- **Handoff**: `state/handoffs/wp-067-merge.json`（pin + snapshot + begin 已完成；本报告提交后运行 `finish wp-067-merge`）
- **日期**: 2026-10-18
- **结果**: **MERGE 成功（`--no-ff`，无冲突）；合并后集成验证 PASS（host 656/656、clean 构建成功）**。本次合并将 T-17 应用壳/组合根/权限/资源（C-28）实现、DES-B DI/架构裁定及其评审证据带回 `feat/yaocore-app`。本报告是集成证据，**不替代 Stage Gate 判定**。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree） |
| 目标分支 | `feat/yaocore-app` @ `50f04430cccb2408057c3cb5c2d9d8142901c9c4`（= handoff `base_commit`；合并前 HEAD 即此） |
| 来源分支 | `task/wp-067-ui-shell` @ `fc20a5f8dded91a7ce4f87786d7b4e090e789a38`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `50f0443`（目标 tip，`git merge-base` 实查；来源为基于该 tip 的线性提交链，仍按策略强制 `--no-ff`） |
| 工作区 | 干净（`git status --porcelain` 无输出） |
| 守卫状态 | ACTIVE `wp-067-merge`（begin 已完成）；未见其他活动任务 |
| 快照 | `refs/swe/snapshots/20261017T174141Z-wp-067-merge-be0deb69` @ `df02efe01250e3363f9776315c75b2fc997f51a7`，tree `a2b0a53c5f429fa214d01cd3267f9f7be2940f71`（`SWE snapshot wp-067-merge`） |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；已执行 `git fetch origin`（exit 0）；`origin/main` @ `7d6f4c99fa1bf0baf5e40d1948a97f564a647401`；本次**未 push** |
| 本地 `main` | `a6f6558882f7ec53be548c85e15a1a291c5a41fd`（未移动） |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- `gate_evidence_path` `artifacts/70-review/t17-review-b.md` sha256 `d1793ebd62233094d6866dd71b1570be0143418efa3f48a78936e6d3036bfb71`（在来源 tip `fc20a5f` 上实查一致，= handoff `gate_evidence_path_sha256`；合并后树中再次复核一致）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用 `config/git-policy.default.md` 默认规范，无公司策略覆盖）

## 2. 来源与预检

来源提交链（`git log --oneline 50f0443..fc20a5f`，6 个提交；与任务说明实查一致）：

```text
fc20a5f docs(review): T-17 复审（F 项与 U-01 关闭确认）
6b10975 docs(design): 裁定 UI 依赖注入与架构约定
7ffa985 fix(shell): 修复 T-17 评审发现
83dd3ef docs(review): T-17 应用壳独立评审
eda5083 fix(build): 修复生产图五文件 ArkTS 编译错误
9422e37 feat(shell): 实现应用壳组合根与权限资源
```

预检结果：目标工作区干净；来源 tip 精确等于 handoff `source_commit`；目标 tip 是来源 tip 的直接祖先（`git merge-base` = `50f0443`，来源线性链无分叉）；`git diff --stat 50f0443..fc20a5f` 为 **73 files changed, 19925 insertions(+), 118 deletions(-)**；目标分支不存在 `entry/src/main/ets/app/`（本任务新增目录）；目标分支已存在 `artifacts/40-detailed-design/des-001b-domain-presentation.md`（由来源 `6b10975` 修订，受合并前快照保护）。

## 3. 合并

- 命令：`git merge --no-ff task/wp-067-ui-shell -m "chore(merge): 合并 T-17 应用壳与组合根到 feat/yaocore-app"`
- 合并提交：`e33d551ba55a7b45296cf1e8aa360e171ac9db61`（主题 `chore(merge): 合并 T-17 应用壳与组合根到 feat/yaocore-app`）
- 父提交：`50f0443`（目标，第一父）+ `fc20a5f`（来源，第二父）
- 策略：`ort`；**无冲突**（未手工编辑任何文件）
- 树一致性：`git diff --stat fc20a5f..HEAD` 为空，即合并结果树与来源 tip 完全一致（目标自 base 后无独立提交）

## 4. 变更统计（`50f0443..e33d551`，按目录）

| 目录 | 文件数 | + | − |
|---|---:|---:|---:|
| `artifacts/40-detailed-design/`（DES-001B 修订，`6b10975`） | 1 | 92 | 49 |
| `artifacts/50-implementation/`（`t17-ui-shell.md`、编译修复报告/patch、修复报告、evidence 6 个日志） | 10 | 4839 | 0 |
| `artifacts/70-review/`（`t17-review.md`、`t17-review-b.md`） | 2 | 432 | 0 |
| `entry/src/main/ets/app/`（**新目录**：组合根、上下文、导航、权限、onboarding 等 15 个模块） | 15 | 2236 | 0 |
| `entry/src/main/ets/pages/`（15 个新页面/壳视图 + `Index.ets` 改造） | 16 | 1343 | 24 |
| `entry/src/main/ets/entryability/`（`EntryAbility.ets`） | 1 | 120 | 21 |
| `entry/src/main/ets/common/`（`utils/Base64Url.ets`） | 1 | 1 | 1 |
| `entry/src/main/ets/service/`（`ble/` 3 + `cloud/` 1） | 4 | 41 | 18 |
| `entry/src/main/resources/`（base/dark/en_US 元素、i18n rawfile、backup 配置） | 7 | 402 | 4 |
| `entry/src/main/module.json5`（权限与页面声明） | 1 | 15 | 0 |
| `entry/src/test/`（`host/AppShell.test.mjs`、`i18n/allowlist.json`、evidence 13 个日志/报告） | 15 | 10404 | 1 |
| **合计** | **73** | **19925** | **118** |

设计文档修订明细（净 diff）：

| 文档 | 净 +/− | 归属提交 |
|---|---|---|
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | +92 / −49 | `6b10975`（T-17 裁定同步：UI 依赖注入与架构约定 D-12/D-17 统一，禁止 `@Provide/@Consume`；不改变冻结签名与既有 DES-B 基线语义之外的部分） |

`entry/src/main/ets/app/` 明细：`ActiveCloudScope`、`AppCompositionRoot`、`AppContext`、`AppContextAdapters`、`AppPlatformPorts`、`CompositionPlan`、`ContinuousGestureGuard`、`NavigationService`、`OnboardingService`、`PermissionGate`、`PermissionPolicy`、`ShellBootstrap`、`ShellGateRouting`、`ShellTheme`、`ViewModelAppContextBridge`。

## 5. 前身保护确认

目标分支中已存在的 DES-001B 由合并前快照保护；快照内字节与合并前目标字节一致：

| 文档 | 快照/合并前 blob | 快照/合并前 sha256 | 合并后 sha256（= 来源 tip） |
|---|---|---|---|
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | `4cb9e96a9c03d4c8a960590c0b360ddcd921dde5` | `42e6912806e39a490aecc36b42b33e717419dc098a4c387d11f9a46fec0b310d` | `975d873a2403a43c4ead04c3c81e2badf5e4a75dc49225ecdff67c837ff8518b` |

- 快照 ref 可完整恢复合并前状态；快照内 DES-001B blob 与合并前目标完全一致（`4cb9e96`）。
- 目标分支合并前不存在 `entry/src/main/ets/app/`（快照内同样 absent），该目录由本任务新增，无覆盖前身文件；pages/ 的 15 个新文件同理为纯新增，仅 `Index.ets` 为改造。
- 本次未改写历史、未 reset、未 force；合并提交保留双亲，来源修订以独立提交进入历史（`6b10975` 等），可追溯。

## 6. 合并后验证（在 `e33d551` 上执行）

| 检查 | 命令 | 结果 |
|---|---|---|
| Host 测试 | `bash entry/src/test/run-host-tests.sh` | ✅ **656/656 PASS**（`# tests 656 / # pass 656 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`，duration ≈ 2876 ms） |
| 构建 | `hvigorw clean assembleHap --no-daemon` | ✅ **BUILD SUCCESSFUL in 11 s 853 ms**（35 tasks：35 executed / 0 up-to-date；生产图含全部组件；签名跳过警告为预期，项目未配置 signingConfigs） |
| 工作区 | `git status --porcelain` | ✅ 干净（构建产物均被忽略） |

说明：本任务未复跑 codelinter；静态检查证据沿用 CQG-T17 判定的 `t17-*-codelinter.log`（合并树与来源树一致）。设备/UI 视觉验证仍按 CQG-T17 保持 BLOCKED（T-19）。

## 7. 冲突

**无冲突**。`ort` 自动合并；目标 tip 是来源 tip 的直接祖先；DES-001B 的修改以来源版本线性覆盖并保留 `6b10975` 提交归属；`app/` 与 15 个 pages 文件为纯新增目录/文件。

## 8. 门禁引用

- Gate：`state/gates/CQG-T17.md` — **PASS（代码级）**；C-28 → STABLE（代码级，条件式）@ `6b10975`；C-24/C-25 DEFERRED → T-18（不得写成完成）；T-17/T-18 范围重定义已在该 Gate 正式落文。
- 门禁证据：`artifacts/70-review/t17-review-b.md` sha256 `d1793ebd62233094d6866dd71b1570be0143418efa3f48a78936e6d3036bfb71`。
- 残余（不因合并而关闭）：R2-02 onboarding 复用键 → T-18；R2-03 `createFamily` 孤儿家庭 → T-18/C-22；R2-04 `DeviceControlCoordinator` 构造位置 → C-29 白名单或迁移；R2-05 API≥20 权限异常回退 → T-19；R2-06 `activeFamilyId` 可观察性 → T-18；IG-3 NOT READY（T-18 未交付，无设备/UI/集成证据）。详见 CQG-T17 §条件与残余。

## 9. 分支与下一步

- 合并后 `feat/yaocore-app` tip：本证据提交（主题 `chore(repo): 记录 wp-067 合并集成证据`，第一父为合并提交 `e33d551`）。
- `finish wp-067-merge` 校验通过后，从本证据提交（新 tip）创建 `task/wp-073-ui-pages`（不切换、不建 worktree），分支 tip 即本证据提交。
- 下一步：派发 **T-18**（C-24 设计系统/token/复用组件 + C-25 Home/Rooms/DeviceControl 页面），写范围按 CQG-T17 §范围重定义扩至 `components/**`、`common/theme/**`、`pages/**`。
- 约束遵守：未 push；未切换/移动其他分支；未创建 worktree；未修改本报告之外文件；未使用 reset/force。

```text
Evidence commit subject: chore(repo): 记录 wp-067 合并集成证据
Evidence commit: 见 feat/yaocore-app tip（本报告提交）
Merge commit: e33d551ba55a7b45296cf1e8aa360e171ac9db61
Source tip: fc20a5f8dded91a7ce4f87786d7b4e090e789a38
Target pre-merge: 50f04430cccb2408057c3cb5c2d9d8142901c9c4
Post-merge host tests: 656/656 PASS
Post-merge build: BUILD SUCCESSFUL
```
