# T-17 评审修复报告（F-01..F-13 / U-01）

- **Artifact ID**: T17-FIX
- **Producer**: agent:implementation-engineer
- **Task**: `wp-070-fix-t17`（Handoff `state/handoffs/wp-070-fix-t17.json`）
- **Branch**: `task/wp-067-ui-shell`（base `83dd3ef`，父分支 `feat/yaocore-app`）
- **Status**: **COMPLETE（本地五项验证 + ohosTest 编译通过；待独立复审 / CQG-T17）**
- **Date**: 2026-10-18
- **Workflow**: STANDARD / GATED_AUTO
- **Reviewed source**: `artifacts/70-review/t17-review.md`（`CHANGES_REQUIRED`）

> **结论先行**：评审的 3 个 High（F-01/F-02/F-03）与 3 个 Medium（F-04/F-05/F-06）已修复；F-08/F-10/F-12/F-13 已修复；F-07/F-09/F-11/U-01 按“记录/文档”要求处理，未擅自修改契约、计划或上游分层规则。五项必跑命令全部通过：host **656/656**（新增 17 条）、`codelinter` **0 error**、`clean assembleHap` **BUILD SUCCESSFUL** 且不再出现 `@Entry` / `fill` / `getContext` 警告、`check_i18n --strict-ui` **0 blocking**、`ohpm install` exit 0；额外 ohosTest 仅编译 **BUILD SUCCESSFUL**。设备/Previewer UI smoke 仍为 **BLOCKED**，本报告不把编译/主机证据写成设备 PASS。

---

## 1. 逐条处置

| ID | 严重度 | 处置 | 证据/位置 |
|---|---|---|---|
| **F-01** | High | **已修复**。`Index.ets` 改为 `@Entry({ useSharedStorage: true })`（API 12+），`@LocalStorageProp('bootstrap')` 现在读取 `EntryAbility` 写入并传给 `loadContent` 的 ability LocalStorage。新增静态断言测试；构建日志不再有 `'@Entry' should have a parameter`。 | `pages/Index.ets:27`；`entryability/EntryAbility.ets:118-120`；`T17_entryUsesSharedStorageAndAbilityWritesBootstrap` |
| **F-02** | High | **已修复**。`SessionGateView` 的 `NO_PROFILE` 通过 `ShellGateRouting` 提供“创建家庭 / 加入家庭（切换家庭）”入口；`OnboardingView` 实现创建家庭（家庭名/显示名/密码）与两步加入（生成 YCR1 → 粘贴 YCI1 + 可选邀请码），`OnboardingService` 调用 C-22 `FamilyService` / `FamilyJoinSession` / C-12 `AuthService`，完成后 gate 进入 `LOCKED`，不自动解锁。host 覆盖状态→入口映射与 create/startJoin/completeJoin。 | `app/ShellGateRouting.ets`、`pages/OnboardingView.ets`、`app/OnboardingService.ets`、`pages/ShellViews.ets:84-114`；`T17_gateEntryMappingCoversFreshInstallAndLock`、`T17_onboardingCreateAndJoinLandLocked` |
| **F-03** | High | **已修复（API 14 语义）**。`PermissionGate.check()` 以 `deviceInfo.sdkApiVersion` 守卫：API ≥ 20 才调用 `getSelfPermissionStatus`；API 14–19 走 `checkAccessTokenSync`，未授权映射为 `NOT_DETERMINED`；`ensure()` 在动作入口请求一次 `requestPermissionsFromUser`，进程内 flag 防止重复弹窗，之后的未决状态返回 `DENIED` + `canOpenSettings`。纯策略映射与静态接线测试已补。 | `app/PermissionGate.ets:38-115`；`app/PermissionPolicy.ets:54-135`；`T17_permissionApi14FallbackIsRequestableOnce` |
| **F-04** | Medium | **已修复**。`SessionGateView` 对 `gate` 与 `activeFamilyId` 加 `@Watch`，gate 变化/家庭切换时重置选择与密码并重新 `loadProfiles()`；档案加载失败显示错误与重试。静态测试覆盖接线。 | `pages/ShellViews.ets:24-66`、`:203-229`；`T17_sessionGateViewWiresOnboardingAndReloadsOnGateOrFamilyChange` |
| **F-05** | Medium | **已修复**。`NavigationService.push/replace` 调用 `AppRouteValidation.accepts()`；非法路由 push/replace 为内部哨兵 `invalid-route`；`MainShell.routeBuilder` 同样校验并渲染 `UnknownRouteView`/ErrorState。缺失 DeviceControl 参数与非法 Provisioning mode 的 host 测试已补。 | `app/NavigationService.ets:155-215`；`pages/MainShell.ets:70-101`；`T17_routeValidationWiredIntoPushAndReplace`、`T17_routeBuilderValidatesParametersBeforeConstructingPage` |
| **F-06** | Medium | **已修复（代码/构建）**。`EntryAbility.onWindowStageCreate` 调用 `getMainWindowSync().setWindowLayoutFullScreen(true)` 并设置透明系统栏；`ShellBackdrop` 仅背景层 `expandSafeArea(SYSTEM, TOP/BOTTOM)`，交互内容保持在安全区。静态接线测试已补；视觉/避让区仍需 Previewer/真机确认（`BLOCKED`）。 | `entryability/EntryAbility.ets:78-137`；`pages/ShellBackdrop.ets:58`；`T17_entryAbilityAppliesImmersiveWindowLayout` |
| **F-07** | Medium（范围） | **记录，未改代码/计划**。T-17 实际交付为壳层；C-24 完整设计系统与 C-25 Home/Rooms/DeviceControl 仍未交付。Orchestrator 必须在 CQG-T17/IG-3 前把该重定义写入决策/交付计划，并将 T-18 写范围扩至 `components/**`、`common/theme/**` 与 `HomePage/RoomsPage/DeviceControlPage`；本报告不得把 C-24/C-25 写成已完成。 | 本报告 §4 |
| **F-08** | Low | **已修复**。`AppCompositionRoot.dispose()` 在关闭存储前 best-effort `await appContextValue.lock()`：既 `authService.lockAll()` 又 `refreshSessionGate()` 重置会话门；失败只记录 warning，不跳过后续关闭。 | `app/AppCompositionRoot.ets:541-551`；`T17_disposeLocksSessionBeforeClosingStorage` |
| **F-09** | Low | **已记录**。`CryptoService` 在 PLATFORM（第 1 步）构造，而 DES-B §2.4 列在安全栈（第 5 步）；原因：仅依赖 `OhosCryptoProvider`/`CryptoRandomSource`，无存储依赖。已在 `CompositionPlan` 与构造点注释、本报告 §4 记录。 | `app/CompositionPlan.ets:10-20`；`app/AppCompositionRoot.ets:211-218` |
| **F-10** | Low | **已修复**。`Circle().fill(Resource)` 在兼容 SDK 14 下解析到 API 26 `ColorMetrics` 重载；改用等宽等高 `Ellipse().fill(...)`（API 10/11 `CommonShapeMethod.fill(ResourceColor)`）。构建中 5 条 `fill` API 警告消失。设备视觉等价性待 T-19 确认。 | `pages/MainShell.ets:52-58`；`pages/ShellBackdrop.ets:25-50`；`T17_shellUsesApi14CompatibleEllipseFill` |
| **F-11** | Low（文档） | **记录 supersession**。`t17-ui-shell.md` 是本次 Handoff 的冻结输入（SHA-256 pin），本任务不能改写；其 `BLOCKED` 状态与 §3/§7 由本报告声明 superseded。Orchestrator/复审应将主报告最终状态更新为“实现 + 编译修复 + 评审修复完成”，或在本报告基础上记录 supersession。 | 本报告 §4；`t17-ui-shell.md` 未修改 |
| **F-12** | Low（测试） | **已修复（静态守卫扩围）**。Mock/ohosTest 导入扫描从 `app/` 扩展到全部 `entry/src/main/ets/**`（排除 `service/mock/**` 自身），并扫描 `app/pages/entryability` 的 `DEV-ONLY`/`DEV_ONLY`；生产 HAP `ets/modules.abc` 的 `MockGatewayService`/`MockBleProvisioningClient`/`MockScenario` 命中 **0**。独立 C-29 检查器仍由 T-20 补齐。 | `entry/src/test/host/AppShell.test.mjs` `T17_productionMockExclusionCoversAllMainSources`；`entry/src/test/evidence/t17-fix-hap-mock-check.log` |
| **F-13** | Low（会话一致性） | **已修复**。`AppContext.setActiveFamily()` 先 `lockAll()` 再刷新 gate；`refreshSessionGate()` 还比较 `session.familyId === activeFamilyId`，其他家庭会话不能解锁当前家庭。host 覆盖家庭切换与跨家庭会话。 | `app/AppContext.ets:168-199`；`T17_setActiveFamilyLocksPreviousSession`、`T17_sessionFromAnotherFamilyCannotUnlock` |
| **U-01** | Low（上游） | **记录，未改契约**。`app/AppCompositionRoot` 的 viewmodel 工厂导入由 DES-B §17.1.2 解释，但 D-17 文字未允许；D-12 pages allowlist 未含 `ShellTheme`/`ShellBootstrap`；`@Provide` 与显式 props 的最终 DI 契约也未裁定。需 `solution-architect` 在 IG-3 前更新 D-12/D-17 并明确提供方式。本次修复未新增 viewmodel 导入，未改动分层规则。 | 本报告 §4 |

---

## 2. 代码变更

### 2.1 修改

| 文件 | 内容 |
|---|---|
| `entry/src/main/ets/pages/Index.ets` | F-01 `@Entry({ useSharedStorage: true })`；向 `SessionGateView` 传 `activeFamilyId`；`exit()` 改用 `getUIContext().getHostContext()`（消除 deprecation warning） |
| `entry/src/main/ets/pages/ShellViews.ets` | F-02 NO_PROFILE 创建/加入入口；F-04 `@Watch` gate/activeFamilyId、重置选择/密码、加载失败重试 |
| `entry/src/main/ets/pages/MainShell.ets` | F-05 routeBuilder 参数校验；F-10 Tab 圆点改 `Ellipse` |
| `entry/src/main/ets/pages/ShellBackdrop.ets` | F-10 光核改 `Ellipse`；F-06 背景 `expandSafeArea` |
| `entry/src/main/ets/entryability/EntryAbility.ets` | F-06 全屏 + 透明系统栏；保持 LocalStorage bootstrap 接线 |
| `entry/src/main/ets/app/AppContext.ets` | F-02 `OnboardingPort` + create/startJoin/completeJoin/cancelJoin；F-13 会话/家庭一致性 |
| `entry/src/main/ets/app/OnboardingService.ets`（新增） | F-02 最小 C-22 onCreate/join 编排；不自动解锁；`AUTH_PROFILE_EXISTS` 仅对同一 member 幂等 |
| `entry/src/main/ets/app/ShellGateRouting.ets`（新增） | F-02 纯状态→入口映射（host 可测） |
| `entry/src/main/ets/app/PermissionGate.ets` | F-03 API 20 守卫 + API 14 一次性请求路径 |
| `entry/src/main/ets/app/PermissionPolicy.ets` | F-03 `stateFromTokenCheck`、`shouldRequestPermission`、`stateAfterSuppressedRequest` 纯策略 |
| `entry/src/main/ets/app/NavigationService.ets` | F-05 push/replace 校验与 `INVALID_ROUTE_NAME` 哨兵 |
| `entry/src/main/ets/app/AppCompositionRoot.ets` | F-02 构造/暴露 onboarding；F-08 dispose 锁会话；F-09 顺序注释 |
| `entry/src/main/ets/app/CompositionPlan.ets` | F-09 记录 CryptoService 顺序偏差 |
| `entry/src/test/host/AppShell.test.mjs` | 新增 14 条 T17 修复测试；FakeRoot 增补 onboarding；会话 fake 补 `familyId` |

### 2.2 新增测试（17 条，656 = 639 + 17）

```text
T17_gateEntryMappingCoversFreshInstallAndLock
T17_sessionGateViewWiresOnboardingAndReloadsOnGateOrFamilyChange
T17_entryUsesSharedStorageAndAbilityWritesBootstrap
T17_onboardingCreateAndJoinLandLocked
T17_setActiveFamilyLocksPreviousSession
T17_sessionFromAnotherFamilyCannotUnlock
T17_routeValidationWiredIntoPushAndReplace
T17_routeBuilderValidatesParametersBeforeConstructingPage
T17_permissionApi14FallbackIsRequestableOnce
T17_disposeLocksSessionBeforeClosingStorage
T17_productionMockExclusionCoversAllMainSources
T17_shellUsesApi14CompatibleEllipseFill
T17_entryAbilityAppliesImmersiveWindowLayout
T17_indexExitUsesNonDeprecatedHostContext
T17_onboardingServiceCreatesFamilyProfileThenSwitches
T17_onboardingServiceJoinIsTwoStepAndDisposesSession
T17_onboardingServiceProfileConflictOnlyIdempotentForSameMember
```

> 说明：ArkUI 页面/EntryAbility 无 host 渲染器，F-01/F-02/F-04/F-06 的接线证据由“纯逻辑测试 + 源级断言”组成；真正的启动/安全区/onboarding smoke 仍归 T-19 设备/Previewer 矩阵（`BLOCKED`，不写成 PASS）。

---

## 3. 验证（实际执行，cwd = 仓库根）

| # | 命令 | 结果 | 证据 |
|---|---|---|---|
| 1 | `ohpm install` | exit 0，`install completed in 0s 47ms` | `entry/src/test/evidence/t17-fix-ohpm-install.log` |
| 2 | `hvigorw clean assembleHap --no-daemon` | **BUILD SUCCESSFUL in 11 s 808 ms**；34 executed / 1 up-to-date；**无 `@Entry` / `fill` / `getContext` 警告** | `entry/src/test/evidence/t17-fix-clean-assemble.log` |
| 3 | `codelinter -c code-linter.json5 -p default .` | exit 0：**Errors 0 / Warns 15 / Suggestions 0**（均为既有自定义组件性能提示） | `entry/src/test/evidence/t17-fix-codelinter.log` |
| 4 | `entry/src/test/run-host-tests.sh` | **656/656 pass**，fail 0 / skipped 0 / todo 0 | `entry/src/test/evidence/t17-fix-host-node-tests.tap` |
| 5 | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | exit 0：**blockingFailures=0**，warnings=56，missingKeys=0，hardcoded=10（均为既有 C-16/C-20/Mock 文件） | `entry/src/test/evidence/t17-fix-i18n-checker.log` |
| 6 | `hvigorw --mode module -p module=entry@ohosTest ... assembleHap --no-daemon`（额外） | **BUILD SUCCESSFUL in 9 s 855 ms**（仅编译，非设备执行） | `entry/src/test/evidence/t17-fix-ohosTest-assemble.log` |
| 7 | 生产 HAP Mock 检查（`unzip -p ... ets/modules.abc \| strings`） | `MockGatewayService` / `MockBleProvisioningClient` / `MockScenario` 命中 **0**；`DEV_SIMULATOR_ONLY` 拒收常量存在（SC-11 allowlist） | `entry/src/test/evidence/t17-fix-hap-mock-check.log` |

ArkTS 文件级警告从 75 条降至 68 条；减少项为本任务修复的 `@Entry`、5×`fill`、`getContext` 共 7 条。其余 68 条为既有 SDK 26→API 14 兼容提示/异常处理提示，未在本任务写范围。

---

## 4. 范围重定义与上游事项（未改契约/计划）

1. **F-07 T-17/T-18 范围（Orchestrator 决策）**：本轮按“T-17 = 应用壳 + 导航 + 组合根 + 权限 + 资源 + 最小 onboarding”验收。C-24 完整设计系统与 C-25 Home/Rooms/DeviceControl 仍未交付；T-18 当前计划写范围也不含它们。CQG-T17 不得把 C-24/C-25 写成已完成。建议 Orchestrator 记录该重定义，并把以下路径加入 T-18：`entry/src/main/ets/components/**`、`entry/src/main/ets/common/theme/**`、`entry/src/main/ets/pages/{HomePage,RoomsPage,DeviceControlPage}.ets`。
2. **F-09 组合根顺序**：`CryptoService` 在 PLATFORM（第 1 步）而非 §2.4 第 5 步；已在 `CompositionPlan`/`AppCompositionRoot` 注释与本报告记录，不改行为。
3. **F-11 主报告状态**：`t17-ui-shell.md` 是本次 Handoff 冻结输入，未修改。其 `BLOCKED`/HAP FAIL 文字由本报告 superseded；复审/Orchestrator 应在 CQG 前更新主报告状态或引用本报告作为最终状态。
4. **U-01 分层/DI（solution-architect）**：D-17 未明确允许 `app → viewmodel` 工厂导入；D-12 pages allowlist 未含 `app/ShellTheme.ets`/`app/ShellBootstrap.ets`；§17.1.5 的 `@Provide` 与当前显式 props 实现不一致。需在 IG-3 前裁定 D-12/D-17 与最终 DI 契约。本次修复未新增 viewmodel 导入，也未改动分层规则。
5. **F-01 bootstrap 键偏差**：DES-B §17.1.4 写 `appContext` 键；实现继续使用 `bootstrap` 包装对象（同时携带 `startupError`）。`useSharedStorage` 接线后语义等价；该包装偏差在此明确记录，未改契约。
6. **F-02 标签资源**：`resources/**` 不在本任务写范围，无法新增 `family.join`/字段标签键。入口复用既有 `family.create` 与 `family.switch`，邀请容器/邀请码输入复用既有键；T-18 拥有完整 Family 页面时应补齐专用键并替换本 shell 文案。
7. **F-08 说明**：`dispose()` 通过既有 `AppContext.lock()` 锁会话并重算 gate；不新增公开的 dispose/复位 API，root 释放后由 EntryAbility 丢弃引用。

---

## 5. 残余风险 / 未验证项（如实记录）

| 项 | 状态 | 说明 | 归属 |
|---|---|---|---|
| 启动 LocalStorage / onboarding / SessionGate UI smoke | **BLOCKED** | 无设备/Previewer；host 只能证明纯逻辑与源级接线 | T-19 |
| API 14–19 蓝牙权限真实请求 | **BLOCKED（设备）** | 代码已按 API 级别分支；需真机验证 `requestPermissionsFromUser` 与“去设置” | T-19 |
| 全屏/安全区视觉、428×872、手势条 | **BLOCKED（设备）** | 代码已设置全屏 + 背景 expandSafeArea；需 Previewer/真机确认内容不压系统栏 | T-19 |
| Join 中断恢复 | 风险（Low） | join session 仅内存；进程终止后需重新生成 YCR1。成员已持久化时按 C-22 不变量走解锁；完整恢复入口归 T-18 | T-18 |
| `openSettings()` action | 未验证（设备） | `ohos.settings.app.info` 需真机确认可打开应用详情 | T-19 |
| C-24/C-25 交付 | **未完成** | 见 §4.1；不得写成已完成 | T-18 / Orchestrator |
| 独立 C-29 检查器 | **未完成** | 本任务用 host 静态扫描 + HAP 内容检查覆盖；正式检查器归 T-20/C-29 | T-20 |
| 设备/真实 BLE/LAN/云 | **BLOCKED** | 既有 D-019；本任务未改变 | T-19 |

---

## 6. 约束核对

- 未修改 `entry/src/main/resources/**`、`module.json5`、`service/**`、`repository/**`、`viewmodel/**`、`contracts/**`、计划或评审报告。
- 未改变既有 API 签名、错误码、错误分类、Contract 语义、Mock 排除、权限最小集（INTERNET + ACCESS_BLUETOOTH）。
- 新增 `OnboardingPort`/`AppContext` onboarding 方法为加载态入口的 additive seam，不替换既有 `unlock/lock/setActiveFamily` 语义。
- 未切换分支，未 pull/merge/rebase/push；验证构建输出仅落在 ignored 目录。
- 环境：`ohpm`/`hvigorw`/`codelinter` 均实际执行；设备/Previewer 不可用。
