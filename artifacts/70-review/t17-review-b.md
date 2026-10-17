# T-17 复审报告（F-01..F-13 / U-01 关闭确认 + CQG-T17 最终意见）

- **Artifact ID**: REVIEW-T17-B
- **Producer**: agent:quality-reviewer
- **Type**: Independent Code Review（复审 / CQG-T17 最终意见 + IG-3 预检）
- **Status**: **PASS（C-28 应用壳，代码级，条件式）**；F-07 的 T-17/T-18 范围落文仍为条件；设备/UI 证据 **BLOCKED**
- **Date**: 2026-10-18
- **Task**: `wp-072-review-t17b`（task 分支 `task/wp-067-ui-shell`，父分支 `feat/yaocore-app`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`（CQG-T17；IG-3 预检）
- **Reviewed revision**: `6b10975bc44e3675e9751d39218c2b38a5087c37`（修复 `7ffa985` + 裁定 `6b10975`；`50f0443..6b10975` 共 72 个路径；本轮新增差异 `83dd3ef..7ffa985` 23 路径 + `6b10975` 1 路径）
- **Review snapshot**: `refs/swe/snapshots/20261017T173451Z-wp-072-review-t17b-4cd45ba3`（commit `e8b0698bd24116b3f064a35569151895635deea3`）
- **Independence**: 本复审由未参与 T-17 实现、编译修复、评审修复、测试或实现报告编写的 `quality-reviewer` 执行；评审期间只读被审代码/报告，唯一仓库写入为本报告。构建/测试输出仅落在 ignored 目录（`entry/build/**`、`.hvigor/**`）及 `/tmp/opencode`。

> **结论先行**：上轮 3 个 High（F-01/F-02/F-03）与 3 个 Medium（F-04/F-05/F-06）的代码修复经独立复验成立；F-08/F-10/F-12/F-13 亦已关闭（代码级）；F-09/U-01 已由 `6b10975` 的 DES-B §0.8 裁定同步；F-11 已由修复报告 §4.3 记录 supersession。独立复跑结果：host **656/656**、`codelinter` **0 error / 15 warning**、`hvigorw clean assembleHap` **BUILD SUCCESSFUL** 且无 `@Entry`/`fill`/`getContext` 警告、ohosTest 仅编译 **BUILD SUCCESSFUL**、`check_i18n --strict-ui` **0 blocking**；生产 HAP 无 `Mock*`，权限仍为 INTERNET + ACCESS_BLUETOOTH，资源 parity（含复数后缀归一化）217/217、strings 53/53、colors 20/20。
>
> **但 F-07 不能写成“已完全关闭”**：`6b10975` 只包含 U-01/F-01/F-09 的 DES-B 文字裁定，**不包含 T-17/T-18 范围重定义**；`delivery-plan.md` 仍把 C-24/C-25 列在 T-17、T-18 写范围仍未扩围，`state/project-state.md`/`state/checkpoint.md` 也未记录该重定义。修复报告 §4.1 只是建议，不是裁定落文。该项不阻断 C-28 壳层的代码级 CQG，但必须由 Orchestrator 在 CQG-T17 文档/计划中补记；否则只能按原 T-17 DoD（含 C-24/C-25）判为未完成。
>
> **CQG-T17 最终意见**：在“T-17 = C-28 应用壳 + 导航 + 组合根 + 权限 + 资源 + 最小 onboarding；C-24/C-25 移交 T-18”的重定义前提下，建议 **PASS（代码级，仅 C-28）**，条件见 §5。**IG-3 预检仍为 NOT READY**：T-18 未交付，设备/UI/BLE/LAN/云证据缺失，C-24/C-25 仍未交付。设备/真实网络/UI 视觉/用户验收均不授予 PASS。

---

## 1. 范围、revision 与输入完整性

### 1.1 评审范围

```text
entry/src/main/ets/app/                 # 组合根/AppContext/导航/权限/onboarding/模板
entry/src/main/ets/entryability/        # EntryAbility 窗口与启动接线
entry/src/main/ets/pages/               # Index/MainShell/ShellViews/OnboardingView/占位页
entry/src/main/resources/               # string/color/rawfile/backup
entry/src/main/module.json5             # 权限/模块配置
entry/src/main/ets/common/              # Base64Url 编译修复（回归）
entry/src/main/ets/service/             # BLE/Cloud 五文件修复（回归）
entry/src/test/                         # host 测试、i18n 检查器、证据
artifacts/50-implementation/t17-fix-report.md   # 修复报告（只读）
```

- 本轮修复提交 `7ffa985` 的 23 个路径全部落在 `entry/src/main/ets/{app,entryability,pages}/`、`entry/src/test/**` 与 `artifacts/50-implementation/t17-fix-report.md`；未触及 `resources/**`、`module.json5`、`service/**`、`repository/**`、`viewmodel/**`、`contracts/**`、计划或评审报告。
- 裁定提交 `6b10975` 只修改 `artifacts/40-detailed-design/des-001b-domain-presentation.md`（92+/49−）。
- 回归复核覆盖 `50f0443..6b10975` 的 72 个路径（T-17 初始实现 `9422e37` + 编译修复 `eda5083` + 评审 `83dd3ef` + 评审修复 `7ffa985` + 裁定 `6b10975`）。
- 明确排除：真实设备/模拟器、真实 BLE/LAN/云、UI 视觉/动效/时序、T-18 完整页面与 C-24 组件、T-19 全量测试、T-20 安全评审、Stage Gate/User Acceptance。上述保持 `BLOCKED`/`UNAVAILABLE`，本报告不将其写成 PASS。

### 1.2 输入 pin 与快照

handoff 的 **11 个 `inputs` SHA-256 全部一致**；`config/git-policy.json` 的 SHA-256（`3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`）与 handoff 一致。HEAD = `6b10975`，base commit 与 handoff 一致；snapshot 覆盖 `review_targets`、两份评审输入及本报告占位文件。`begin` 复核输出全部输入 `OK`；任务已处于 active 状态，未重新 pin 或改写输入。

| 输入 | SHA-256 前 12 位 | 结果 |
|---|---|---|
| `artifacts/70-review/t17-review.md` | `3c1e73096e9f` | 一致 |
| `artifacts/50-implementation/t17-fix-report.md` | `ea78d8955b24` | 一致 |
| `artifacts/50-implementation/t17-ui-shell.md` | `5ed8035de0d6` | 一致 |
| `artifacts/50-implementation/t17-compile-fix-report.md` | `e37358d84f17` | 一致 |
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | `975d873a2403` | 一致（含 §0.8 裁定） |
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `3a02ecbf266b` | 一致 |
| `artifacts/20-architecture/contract-baseline.md` | `883e09bb34ea` | 一致 |
| `artifacts/20-architecture/project-constraints.md` | `283046210e68` | 一致 |
| `artifacts/20-architecture/i18n-resource-design.md` | `3fa7f3881cda` | 一致 |
| `artifacts/60-testing/test-plan.md` | `33485cc39abd` | 一致 |
| `input/design/UI_UX_Specification.md` | `11bd1399240c` | 一致 |

### 1.3 本评审实际复验（cwd = 仓库根）

| 命令 | 结果 | 说明 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS：656 tests / 656 pass / 0 fail / 0 skipped / 0 todo，exit 0** | 与 `entry/src/test/evidence/t17-fix-host-node-tests.tap` 一致；`T17_*` 用例 43 条（原 26 + 新增 17）；基线 639 条无删除 |
| `codelinter -c code-linter.json5 -p default .` | **PASS：Errors 0 / Warns 15 / Suggestions 0，exit 0** | 与修复证据一致；均为既有 `@performance/avoid-overusing-custom-component-check` 提示，仅覆盖产品源码 |
| `hvigorw clean assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL in 11 s 621 ms，exit 0**（35 tasks；34 executed / 1 up-to-date） | 生产 HAP：`entry/build/default/outputs/default/entry-default-unsigned.hap`；68 条 ArkTS warning，均为既有 API 26→14/异常处理提示；**无 `'@Entry' should have a parameter`、无 `fill`、无 `getContext` 警告** |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL in 9 s 857 ms，exit 0** | 仅编译证据，**不是设备执行**；`onDeviceTest` 仍 BLOCKED（D-019） |
| `check_i18n.py --strict-ui`（不带 allowlist） | **PASS：blockingFailures=0 / warnings=56 / missingKeys=0 / hardcoded=10，exit 0** | 10 条 hardcoded 全为既有 C-16/Mock 文件；无 T-17 新增硬编码 |
| `check_i18n.py --strict-ui --allowlist entry/src/test/i18n/allowlist.json` | **PASS：blockingFailures=0 / warnings=10 / hardcoded=10，exit 0** | 与修复证据一致；`brand.*`/既有前缀键均在 allowlist |
| 独立资源 parity 脚本 | **PASS** | rawfile 按复数后缀（`_one`/`_other`）归一化后 **217/217**；base/en_US strings **53/53**；base/dark colors **20/20**；`brand.*` 4 键与 `settings.cloud.single_gateway_required` 均存在 |
| 生产 HAP 内容检查 | **PASS（Mock 排除）** | `modules.abc` 中 `MockGatewayService` / `MockBleProvisioningClient` / `MockScenario` 均 **0** 命中；`DEV-ONLY` 与 `DEV_SIMULATOR_ONLY` 为 C-17 拒收常量（SC-11 allowlist），不是 Mock |
| HAP 配置检查 | **PASS** | `module.json` 仅 INTERNET + ACCESS_BLUETOOTH；`backup_config.json` = `allowToBackupRestore:false`；`main_pages.json` 仅 `pages/Index` |
| 五文件补丁等价性 | **PASS** | `git apply --reverse --check artifacts/50-implementation/t17-c28-compile-fix.patch` 成功；5 文件/42+/19−；5 个目标文件自 `83dd3ef` 起无变化 |
| 静态分层扫描 | **PASS（有 R2-04 提示）** | `pages/**` 无 `@Provide`/`@Consume`；`components/**` 目录尚不存在；`pages/**` import 均在 DES-B §0.8 D-12 白名单；`viewmodel/repository/service/model/common` 无反向 `app/**` import；`AppCompositionRoot.create` 为唯一构造点；页面未 `new` 服务/仓储/VM（`Index` 仅 `new NavigationService`，属 UI seam） |
| `git status --short` / `git diff --cached --check` | **PASS** | 复验前后工作树 clean；仅 ignored 构建缓存；本报告提交前 staged check 通过 |

### 1.4 测试边界（诚实声明）

- `T17_*` 43 条 host 用例真实执行，覆盖纯逻辑/静态接线：启动 LocalStorage 源级断言、gate 入口映射、onboarding 状态/编排、API 14 权限策略、路由校验、dispose 顺序、Mock 扫描、API 14 形状、全屏接线、会话/家庭一致性。
- ArkUI 页面/EntryAbility/LocalStorage 运行时绑定、权限系统弹窗、安全区/视觉、真实 BLE/LAN/云没有 host 渲染器或设备；这些不能由 656/656 推出 PASS。F-01/F-02/F-03/F-04/F-06 的剩余风险均归 T-19 设备/Previewer 矩阵（`BLOCKED`）。

---

## 2. Findings 关闭状态（F-01..F-13 + U-01）

严重度沿用上轮定义；本轮所有“Closed（代码级）”均只代表当前 revision 的代码/构建/主机证据，不代表设备或用户验收。

| ID | 上轮严重度 | 本轮状态 | 证据/说明 |
|---|---|---|---|
| **F-01** | High | **Closed（代码级）** | `pages/Index.ets:27` 为 `@Entry({ useSharedStorage: true })`，`:30` 为 `@LocalStorageProp('bootstrap')`；`entryability/EntryAbility.ets:141-144` 创建 ability `LocalStorage`、写入 `ShellBootstrap` 并 `loadContent('pages/Index', storage)`；`Index.ets:43-50` 对 `bootstrap.appContext` 为空/启动错误做显式分支。构建日志无 `@Entry` 参数警告；`T17_entryUsesSharedStorageAndAbilityWritesBootstrap` 覆盖源级接线。Previewer/真机启动 smoke 仍 **BLOCKED**（T-19）。 |
| **F-02** | High | **Closed（代码级）** | `app/ShellGateRouting.ets:19-27` 将 `NO_PROFILE` 映射为 `CREATE_FAMILY`+`JOIN_FAMILY`；`pages/ShellViews.ets:84-116` 渲染创建/加入入口与 `OnboardingView`；`app/OnboardingService.ets` 实现 C-22 create/join（`FamilyService`/`FamilyJoinSession`/`AuthService`），完成后只到 `LOCKED`，不自动解锁；`T17_gateEntryMappingCoversFreshInstallAndLock`、`T17_onboardingCreateAndJoinLandLocked`、`T17_onboardingService*` 覆盖。真实 UI smoke **BLOCKED**；入口标签复用问题见 R2-02。 |
| **F-03** | High | **Closed（代码级）** | `app/PermissionGate.ets:94-108` 以 `deviceInfo.sdkApiVersion >= 20` 守卫 `getSelfPermissionStatus`；API 14–19 走 `checkAccessTokenSync`，`PermissionPolicy.stateFromTokenCheck(false, <20)` 返回 `NOT_DETERMINED`（`PermissionPolicy.ets:116-122`）；`ensure()` 对未决状态请求一次 `requestPermissionsFromUser`，`requestedInProcess` 防重复弹窗，之后未决返回 `DENIED` + `canOpenSettings`（`PermissionGate.ets:45-81`）。`T17_permissionApi14FallbackIsRequestableOnce` 覆盖纯策略与源级接线；真实 API 14–19 权限弹窗 **BLOCKED**（T-19）。 |
| **F-04** | Medium | **Closed（代码级）** | `pages/ShellViews.ets:26/28` 对 `gate`/`activeFamilyId` 加 `@Watch`；`:44-66` 在 gate/家庭变化时重置选择、密码、错误与 onboarding 模式并重新 `loadProfiles()`；`:203-224` 加载失败置 `profilesError` 并提供重试。`T17_sessionGateViewWiresOnboardingAndReloadsOnGateOrFamilyChange` 覆盖源级接线。UI smoke 仍 BLOCKED。 |
| **F-05** | Medium | **Closed（代码级）** | `app/NavigationService.ets:177-213` 在 `push`/`replace` 调用 `AppRouteValidation.accepts()`，非法目标替换为内部哨兵 `invalid-route`；`pages/MainShell.ets:75-106` 的 `routeBuilder` 先校验路由名与参数，再构造页面，非法时渲染 `UnknownRouteView`。`T17_routeValidationWiredIntoPushAndReplace`、`T17_routeBuilderValidatesParametersBeforeConstructingPage` 覆盖。 |
| **F-06** | Medium | **Closed（代码级）** | `entryability/EntryAbility.ets:119-134` 调用 `setWindowLayoutFullScreen(true)` 并设置透明状态栏/导航栏；`pages/ShellBackdrop.ets:58` 仅背景层 `expandSafeArea(SYSTEM, TOP/BOTTOM)`，交互内容不扩边。`T17_entryAbilityAppliesImmersiveWindowLayout` 覆盖源级接线。428×872、避让区、手势条视觉需 Previewer/真机确认（T-19，**BLOCKED**）。 |
| **F-07** | Medium（范围/计划） | **未完全关闭（条件）** | 修复报告 §4.1 已如实记录“T-17 = 壳层；C-24/C-25 未交付”，`6b10975` 的 DES-B §0.8 也声明“不关闭 F-01..F-13”。但 **`6b10975` 未包含 T-17/T-18 范围重定义**；`artifacts/30-plan/delivery-plan.md:437-446` 仍把 C-24/C-25 列入 T-17，`:453` 的 T-18 写范围仍未包含 `components/**`、`common/theme/**`、`HomePage/RoomsPage/DeviceControlPage`；`state/project-state.md`/`state/checkpoint.md` 也未记录该重定义。CQG-T17 必须在 gate 文档补记，且 T-18 派发前扩围；否则按原 T-17 DoD 不能 PASS。 |
| **F-08** | Low | **Closed（代码级）** | `app/AppCompositionRoot.ets:529-556` 的 `dispose()` 在关闭存储前 best-effort `await appContextValue.lock()`（`authService.lockAll()` + `refreshSessionGate()`），失败只记录 warning；`T17_disposeLocksSessionBeforeClosingStorage` 断言 lock 早于 `storage.close()`。root 释放路径无 host 运行时测试，属可接受残余。 |
| **F-09** | Low | **Closed（记录）** | `app/CompositionPlan.ets:10-20` 与 `AppCompositionRoot.ets:211-218` 记录 `CryptoService` 在 PLATFORM（第 1 步）的偏差及理由；DES-B §0.8 将其登记为 T-17 接受项。`T17_compositionPlanOrderAndDependencies` 仍覆盖顺序/依赖。 |
| **F-10** | Low | **Closed（代码级）** | `pages/MainShell.ets:52-58` 与 `pages/ShellBackdrop.ets:25-50` 将 `Circle` 改为等宽等高 `Ellipse`，使用 API 10/11 `CommonShapeMethod.fill(ResourceColor)`；构建中 5 条 `fill` API 26 警告消失。设备视觉等价性需 T-19 确认（**BLOCKED**）。 |
| **F-11** | Low（文档） | **Closed（supersession 已记录；主报告保持冻结）** | 修复报告 §4.3 明确声明 `t17-ui-shell.md` 为冻结输入，其 `BLOCKED`/HAP FAIL 文字由修复报告 superseded；`DES-B §0.8` 也要求 CQG 以修复/复审证据为准。主报告本身未改写，CQG-T17 必须引用修复报告 + 本复审作为最终状态；不再保留两个互相竞争的“最终状态”叙述。 |
| **F-12** | Low（测试/SC-11） | **Closed（静态守卫扩围 + HAP 检查）** | `entry/src/test/host/AppShell.test.mjs:875-896` 的 `T17_productionMockExclusionCoversAllMainSources` 遍历全部 `entry/src/main/ets/**`（排除 `service/mock/**` 自身），检查 `Mock`/`ohosTest` import，并扫描 `app/pages/entryability` 的 `DEV-ONLY`/`DEV_ONLY`；生产 HAP 对三个 Mock 类 0 命中。独立 `check_production_mock_exclusion.py`（C-29）仍未实现，归 T-20；本项以静态扫描 + HAP 证据关闭 T-17 范围。 |
| **F-13** | Low（会话一致性） | **Closed（代码级）** | `app/AppContext.ets:191-197` 的 `setActiveFamily()` 先 `lockAll()` 再 `refreshSessionGate()`；`:169-176` 的 `refreshSessionGate()` 要求 `session.familyId === activeFamilyId` 才 `UNLOCKED`；`T17_setActiveFamilyLocksPreviousSession`、`T17_sessionFromAnotherFamilyCannotUnlock` 覆盖。 |
| **U-01** | Low（上游/架构） | **Closed（裁定）** | `6b10975` DES-B §0.8 明确 D-12（pages/components import 白名单）与 D-17（app 依赖方向/可见性）分工；确认 `AppCompositionRoot` 构造注入为唯一生产装配、显式 `@Require`/`@Prop` props 为唯一 UI 依赖传递、禁止 `@Provide/@Consume`；D-12 增补 `ShellBootstrap/ShellTheme/ShellGateRouting/ContinuousGestureGuard/PermissionPolicy` seam；`@LocalStorageProp('bootstrap')` 仅用于 EntryAbility→Index 启动交接。静态扫描未发现生产 pages/components 的 `@Provide`/`@Consume`，未发现反向 import。 |

---

## 3. 新发现（R2-xx）

以下为本轮独立发现，均不是 C-28 代码阻断项；按严重度记录并给出归属。

| ID | 严重度 | 位置 | 问题/影响 | 建议/归属 |
|---|---|---|---|---|
| **R2-01** | **Medium（文档/计划，承接 F-07）** | `artifacts/30-plan/delivery-plan.md:437-446`、`:453`；`artifacts/50-implementation/t17-fix-report.md` §4.1；`artifacts/40-detailed-design/des-001b-domain-presentation.md` §0.8；`state/project-state.md`/`state/checkpoint.md` | 修复报告和 DES-B 都只“记录/建议”，没有把 T-17/T-18 重定义写成计划或决策：交付计划仍将 C-24/C-25 归 T-17，T-18 写范围未扩；项目状态/检查点也未更新。结果：CQG-T17 若直接 PASS，读者可能误以为 C-24/C-25 已完成；T-18 派发可能漏掉 C-24/C-25。 | Orchestrator 在 `state/gates/CQG-T17.md` 与 `delivery-plan.md` 落文（T-17 = C-28 壳层；C-24/C-25 → T-18），并在 T-18 handoff 扩写范围；在此之前不得把完整 T-17 DoD 记为 PASS，IG-3 保持 NOT READY。 |
| **R2-02** | Low（UX/i18n） | `pages/OnboardingView.ets:45-46`、`:52`、`:62`、`:101`、`:110` | 最小 onboarding 复用了语义不匹配的键：加入家庭入口显示 `family.switch`（“切换家庭”），家庭名字段 placeholder 为 `page_family`（“家庭成员与权限”），显示名字段为 `tab_profile`（“我的”），邀请容器 placeholder 为 `session_no_profile_message`（“创建或加入家庭后即可开始使用。”），邀请码字段为 `invite.mode.code_kek`（“邀请码 + KEK”）。功能可用但首次用户容易误解字段。 | T-18 新增 `family.join`/字段标签键并替换；或在本轮资源写范围书面放宽后修复。`resources/**` 不在 `7ffa985` 写范围，故不作为 CQG 代码阻断。 |
| **R2-03** | Low（失败路径/数据卫生） | `app/OnboardingService.ets:34-42`；`service/family/FamilyService.ets:98-108`；`service/auth/AuthService.ets:141-166` | `createFamily` 先创建家庭 + ADMIN 成员，再创建 `LocalProfile`。若 `auth.createProfile` 在家庭已创建后失败（存储/加密/密码策略等），家庭行与成员保留、无档案；用户重试会再创建一个家庭，旧家庭成为无档案的孤儿行（v1 每家庭一档案，后续切换会 `AUTH_PROFILE_NOT_FOUND`）。无数据丢失/越权，但家庭列表会出现不可用条目。 | T-18/C-22 增加幂等创建或失败清理（删除刚创建的家庭/成员），或记录为可接受的 v1 恢复边界并在 Family 页面提供清理入口。 |
| **R2-04** | Info（分层/C-29） | `app/AppCompositionRoot.ets:69`、`:351`、`:486-496`；DES-B §0.8 D-17 | `AppCompositionRoot` 除 VM 工厂/端口适配外还 import 并构造 `viewmodel/core/DeviceControlCoordinator`（供 Climate/Door VM 注入）。按 §0.8 “仅限 VM 工厂与 VM 端口适配”的字面，C-29 可能把它报为越界；实际这是组合根为 VM 工厂装配依赖，不是 app 内业务规则。 | C-29 实现时显式允许该 composition edge，或把 coordinator 的构造移入 VM 工厂 seam；在 T-20/C-29 前记录，不影响当前运行/构建。 |
| **R2-05** | Low（权限回退） | `app/PermissionGate.ets:94-108`；`app/PermissionPolicy.ets:116-122` | 在 API ≥20 上若 `getSelfPermissionStatus` 抛错，代码回退到 `checkAccessTokenSync`，`stateFromTokenCheck(false, >=20)` 返回 `DENIED`；`ensure()` 因此不会调用 `requestPermissionsFromUser`。这只会发生在 API 20+ 的 SDK/设备异常路径，但会让“从未请求”看起来像“已拒绝”。 | T-19 设备验证；可把 API ≥20 的回退非授权映射为一次 `NOT_DETERMINED`（带进程内 flag）或记录可观测告警。 |
| **R2-06** | Info（状态传播，T-18 接线） | `pages/Index.ets:139-146`；`pages/ShellViews.ets:28` | `Index` 以 `this.appContext.activeFamilyName/activeFamilyId` 直接取值传给 `SessionGateView`，但未把 active family 作为 `@State`/可观察值；`@Watch('onFamilyChanged')` 只有父组件重渲染、prop 变化时才触发。当前可达路径（onboarding/switchFamily）都会改变 gate 状态并触发重渲染，故未发现实际缺陷；未来若在 `LOCKED` 下直接 `setActiveFamily`，UI 可能不刷新。 | T-18 将 active family 做成可观察状态或在家庭切换回调中显式刷新；补 UI 测试。 |

---

## 4. CQG-T17 对照

**范围声明**：本节只对 **C-28 应用壳/导航/组合根/权限/资源/最小 onboarding** 给出代码级意见；C-24 完整设计系统与 C-25 Home/Rooms/DeviceControl 页面**未交付**，不在本次 PASS 范围。

| 检查 | 结果 | 证据 |
|---|---|---|
| 构建 | ✅ PASS | `hvigorw clean assembleHap` BUILD SUCCESSFUL（11 s 621 ms）；无 `@Entry`/`fill`/`getContext` 警告；68 条既有 ArkTS 兼容提示 |
| 静态检查 | ✅ PASS | `codelinter` 0 error / 15 warning；均为既有自定义组件性能提示 |
| Host 测试 | ✅ PASS | **656/656**；`T17_*` 43 条；新增 17 条覆盖 F-01..F-13 的纯逻辑/静态接线 |
| 契约符合 | ✅ PASS（条件式） | F-01..F-06/F-08..F-10/F-12/F-13 关闭；U-01/F-09 由 DES-B §0.8 裁定；F-11 supersession 记录；**F-07 计划落文仍为条件**（R2-01） |
| 安全 | ✅ PASS（代码级） | 权限声明最小集 INTERNET + ACCESS_BLUETOOTH；API 14–19 一次性请求路径；fail-closed 权限状态；HAP 无 Mock；无秘密/构建产物入库；设备权限弹窗仍 BLOCKED |
| 分层/依赖 | ✅ PASS（有 C-29 提示） | D-12/D-17 静态扫描通过；无 `@Provide/@Consume`；无反向 app import；R2-04 的 `DeviceControlCoordinator` composition edge 待 C-29 明确 |
| 独立评审 | ✅ PASS | 上轮 `t17-review.md`（CHANGES_REQUIRED）+ 本复审（独立、未参与修复）；修复证据与 revision 绑定 |
| C-24/C-25 | ❌ 未交付（DEFERRED） | `components/**` 不存在；Home/Rooms/DeviceControl 仍为占位；T-18 当前写范围未覆盖；不得写成完成 |
| 设备/UI/真实网络 | ⚠️ **BLOCKED** | 无 Previewer/真机；启动、onboarding、LocalStorage、权限弹窗、安全区、BLE/LAN/云均未运行；`onDeviceTest` 仍 BLOCKED（D-019） |

### 4.1 CQG-T17 最终意见

**建议：PASS（代码级，条件式，范围仅 C-28 应用壳 + 最小 onboarding）**，即：

- C-28 可进入 **STABLE（代码级，条件式）**；上轮 3 个 High/3 个 Medium 阻断已关闭。
- **条件 1（F-07/R2-01）**：Orchestrator 必须在 `state/gates/CQG-T17.md`（并更新 `delivery-plan.md`）记录“T-17 = C-28 壳层 + 最小 onboarding；C-24/C-25 → T-18”，并在 T-18 handoff 扩围 `components/**`、`common/theme/**`、`pages/{HomePage,RoomsPage,DeviceControlPage}.ets`。未完成前，不得把完整 T-17 DoD 记为 PASS，IG-3 保持 NOT READY。
- **条件 2（F-11）**：CQG 文档必须引用 `t17-fix-report.md` + 本复审作为最终状态，不引用 `t17-ui-shell.md` 的旧 `BLOCKED` 状态。
- **条件 3（设备）**：设备/Previewer/真实 BLE/LAN/云证据由 T-19 补齐；本报告不授予设备 PASS、用户验收或 Stage Gate。
- **若 Orchestrator 不接受上述范围重定义**：CQG-T17 只能按原 DoD 判为 **CHANGES_REQUIRED**（C-24/C-25 未交付、T-18 未扩围），不能给出 PASS。

---

## 5. IG-3 预检

**预检结论：NOT READY（不通过）。** 本复审只确认了 C-28 壳层与最小 onboarding 的代码级质量；IG-3（G-012，UI+VM 集成）仍不满足预检条件：

1. **T-18 未交付**：C-26/C-27 页面、配网 6 步、设置/云 UI、Profile 完整交互尚不存在；C-24 完整组件与 C-25 Home/Rooms/DeviceControl 仍为占位。
2. **T-18 范围未落文/未扩围**：F-07/R2-01 未关闭，T-18 写范围仍不含 C-24/C-25 路径；IG-3 不能在范围未定义时开始集成验收。
3. **集成证据缺失**：没有设备/Previewer UI smoke（导航、SessionGate、onboarding、权限拒绝、安全区、设置/云、Mock 排除）；没有 T-18 页面数据流、i18n 切换、RBAC 可见性、真实/模拟 BLE/LAN/云集成证据；`onDeviceTest` 仍 BLOCKED。
4. **IG-3 前置**：CQG-T17 条件关闭、T-18 完成并通过 CQG-T18 后，重跑 host/codelinter/clean assemble/ohosTest/i18n，并执行 IG-3 的 Contract 校验、集成测试与回归；本报告不是 IG-3 Gate 决定。

预检中已可确认的正面项：C-28 组合根构造/依赖注入、权限声明与 API 14 回退策略、资源 parity、生产 HAP Mock 排除、五文件修复等价性、656/656 host 回归；但这些不足以让 IG-3 通过。

---

## 6. 残余风险与跟踪

| 跟踪项 | 风险/内容 | 归属/时机 |
|---|---|---|
| **R2-01/F-07** | T-17/T-18 范围重定义未写入计划/决策；CQG 可能误报 C-24/C-25 完成 | Orchestrator；CQG-T17 前 |
| **F-11** | `t17-ui-shell.md` 仍显示 BLOCKED/HAP FAIL；仅修复报告记录 supersession | Orchestrator/CQG；CQG-T17 前 |
| **启动/onboarding/LocalStorage** | 无 Previewer/真机 smoke；无法证明 `bootstrap.appContext` 非空、Index 进入 SessionGate/MainShell | T-19 设备/Previewer |
| **API 14–19 蓝牙权限** | 代码分支正确，但真实 `requestPermissionsFromUser`、拒绝后“去设置”、`ohos.settings.app.info` 未验证 | T-19 设备矩阵 |
| **全屏/安全区/428×872/手势条** | 代码已设置全屏 + 背景 expandSafeArea；视觉/避让区未验证 | T-19 |
| **R2-02 onboarding 标签** | 复用 `family.switch`/`page_family`/`tab_profile`/`invite.mode.code_kek`，语义不匹配 | T-18 资源任务 |
| **R2-03 createFamily 部分失败** | 家庭已建/档案失败会留下孤儿家庭；重试会新增家庭 | T-18/C-22 |
| **R2-04 C-29 分层边界** | `DeviceControlCoordinator` 的 composition edge 需 C-29 显式允许/迁移 | T-20/C-29 |
| **R2-05 API≥20 权限回退** | `getSelfPermissionStatus` 异常时映射 DENIED，可能不发起请求 | T-19/T-20 |
| **R2-06 active family 可观察性** | 未来 LOCKED 下直接切换家庭时 `@Watch` 可能不触发 | T-18 |
| **C-29 检查器** | `check_production_mock_exclusion.py`/`check_layering.py` 仍未实现；本任务用静态扫描 + HAP 检查替代 | T-20 |
| **设备/真实 BLE/LAN/云** | 既有 D-019；ohosTest 仅编译 | T-19/T-20 |
| **HAP 未签名** | 未配置 signingConfigs；构建仅 SDK 26 目标/14 兼容 | 发布阶段 |
| **i18n 既有 warning** | 10 条来自 C-16/Mock 既有硬编码；不是 T-17 新增 | C-16/T-18 |

---

## 7. Verdict

**Verdict: `PASS`（C-28 应用壳，代码级，条件式）。**

- **CQG-T17**：在 T-17 已重定义为 C-28 壳层 + 最小 onboarding 的前提下，建议 PASS（代码级）；F-01..F-06/F-08..F-10/F-12/F-13 Closed，U-01/F-09 已裁定，F-11 supersession 已记录；F-07/R2-01 为 CQG 文档条件，不是 C-28 代码阻断。
- **不得声明**：完整 T-17 DoD（含 C-24/C-25）完成、C-24/C-25 完成、设备/真实 BLE/LAN/云 PASS、IG-3 PASS、Stage Gate 或用户验收通过。
- **IG-3 预检**：`NOT READY`；T-18 未交付、F-07/R2-01 范围未落文、设备/UI/BLE/LAN/云证据缺失。
- **复验要求**：CQG 条件落文后，T-18 完成时重跑 host/codelinter/clean assemble/ohosTest/i18n，并在设备/Previewer 上补启动、onboarding、权限拒绝/设置、安全区、BLE/LAN/云 smoke；由新的独立复审确认。

本评审的 PASS 条件不是“测试通过”，而是上轮阻断项关闭、修复证据与 `6b10975` 重新绑定，且 CQG 对范围重定义作出明确记录；当前 656/656、构建成功、lint 0 error 不能覆盖设备/运行时/兼容性语义。

---

## 8. 独立性与证据声明

- 本复审由 `quality-reviewer` 独立执行，未参与 T-17 实现 `9422e37`、编译修复 `eda5083`、评审修复 `7ffa985`、测试或任何实现报告编写。
- 评审期间未修改被审产品代码、测试、证据、`t17-ui-shell.md` 或 `t17-fix-report.md`；未修改 `entry/src/main/**`、`entry/src/test/**`、`entry/src/ohosTest/**`、资源或 `module.json5`。唯一仓库写入为本报告。
- 复验命令均在 `/home/quirkybrain/code/harmony-projects/YaoCore` 执行；构建输出只落在 ignored 目录；未执行 `pull`/`merge`/`rebase`/`push`，未切换分支。
- 外部平台依据：ArkUI `@Entry` EntryOptions（`useSharedStorage` 默认 false，API 12+）、`@ohos.abilityAccessCtrl.d.ts`（`getSelfPermissionStatus` `@since 20`；`PermissionStatus` DENIED=-1/GRANTED=0/NOT_DETERMINED=1）、`window.setWindowLayoutFullScreen`/`setWindowSystemBarProperties`、`expandSafeArea`、`Ellipse.fill(ResourceColor)`（API 10/11）。这些是平台 API 语义校验，不替代设备测试。
- 本报告只对 `6b10975`（`50f0443..6b10975`）的 T-17 范围负责；T-18 完整页面、C-24 组件、T-19 全量执行、T-20 安全评审与 Stage Gate 不在本报告结论内。
