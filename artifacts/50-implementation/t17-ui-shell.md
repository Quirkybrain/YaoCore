# T-17 应用壳 / 导航 / 组合根 / 权限 / 资源（C-28 + C-24 主题接入）

- **Artifact ID**: T17-UI-SHELL
- **Producer**: agent:implementation-engineer
- **Task**: `wp-067-ui-shell`（T-17，交付计划 §3.2）
- **Branch**: `task/wp-067-ui-shell`（base `50f0443`，父分支 `feat/yaocore-app`）
- **Status**: **BLOCKED — in-scope implementation complete; HAP build exposes 5 out-of-scope component compile defects**
- **Date**: 2026-10-18
- **Workflow**: STANDARD / GATED_AUTO

> **结论先行**：C-28 壳层、组合根、导航、SessionGate/PermissionGate、权限声明、资源与 host 测试均已完成；`ohpm install`、host `639/639`、`codelinter`（0 error）、`check_i18n`（0 blocking）均通过。首次把 C-08..C-19 接入生产 HAP 后，ArkTS 编译器在 **5 个任务写范围之外**的既有文件中报出 14 条真实编译错误（此前这些文件只被 host/ohosTest 引用，从未进入 `assembleHap` 图）。最小修复补丁已验证可使 `hvigorw clean assembleHap` **BUILD SUCCESSFUL**，补丁保存在 `artifacts/50-implementation/t17-c28-compile-fix.patch`。本任务未越界修改这些文件；需由 Orchestrator 扩围后重派/修复。

---

## 1. 实现范围（in-scope，已落地）

### 1.1 应用壳与导航（C-28）

| 文件 | 内容 |
|---|---|
| `entryability/EntryAbility.ets` | 能力生命周期；创建唯一 `AppCompositionRoot` + `AppContext`；初始化完成后 `loadContent('pages/Index', LocalStorage)`；前台/后台委托；销毁 `root.dispose()`；失败写入 `ShellBootstrap.startupError`，不抛未捕获异常 |
| `app/AppContext.ets` | `SessionGateState` 计算（NO_PROFILE/LOCKED/UNLOCKED）；`activeFamilyId/Name`；`unlock/lock/setActiveFamily`；`subscribeSessionGate`；前台/后台固定顺序；初始化失败与重试；motion 偏好读取；host 可测（无 `@ohos/@kit`） |
| `app/AppContextAdapters.ets` | ArkTS 名义类型适配：`SessionGateAuthAdapter`、`ActiveFamilyAdapter`、`ManualDiscoveryAdapter`（避免 `arkts-no-structural-typing`） |
| `app/NavigationService.ets` | `AppRoute` / `AppRouteParams` / `AppRouteValidation` / `NavPathStack` 操作；Tab 切换、二级页 push/replace/pop/popTo、`onBack` 消费语义 |
| `app/ShellBootstrap.ets` | 单个 LocalStorage 启动值（context 或 startupError），不引入第二组合根 |
| `app/CompositionPlan.ets` | 构造/初始化步骤枚举、顺序常量、`AssemblyTrace`（乱序 = `CONFIGURATION_ERROR`） |
| `app/AppPlatformPorts.ets` | 生产平台端口：`SystemClock`、`UuidGenerator`、`HilogLogger`、`HilogMetrics`、`SystemVmTimer`、`SystemSceneTimer` |
| `pages/Index.ets` | 唯一 `@Entry`；加载/启动错误/SessionGate/MainShell 分支；订阅 gate 与 locale；`onBackPress` |
| `pages/MainShell.ets` | Tabs（首页/房间/场景/我的）+ Navigation/NavDestination 路由；自定义 TabBar；未知路由 → ErrorState |
| `pages/HomePage.ets`、`RoomsPage.ets`、`ScenePage.ets`、`ProfilePage.ets` | Tab 占位页（T-18 替换）；Profile 的锁定/家庭/设置/关于入口为真实导航 |
| `pages/DeviceControlPage.ets`、`FamilyManagePage.ets`、`RoomManagePage.ets`、`ProvisioningPage.ets`、`SettingsPage.ets`、`AboutPage.ets` | NavDestination 占位页；Settings 已消费 `settings.cloud.single_gateway_required` |
| `pages/ShellViews.ets` | `SessionGateView`（NO_PROFILE/LOCKED、档案选择、密码解锁、错误键）、`StartupErrorView`、`UnknownRouteView` |
| `pages/PlaceholderContent.ets`、`ShellBackdrop.ets` | 占位内容与静态光核背景 |
| `app/ShellTheme.ets` | T-17 壳层 token（间距/圆角/字号/弹簧参数/光核周期）；见 §6 偏差 |
| `app/ContinuousGestureGuard.ets` | R3-02 防回归守卫；T-18 滑杆必须使用 |

**导航层级**：`Index → MainShell(Tabs) → Home/Rooms/Scene/Profile`；`DeviceControl/Family/RoomManage/Provisioning/Settings/About` 为 `NavDestination`。`main_pages.json` 仍只注册 `pages/Index`。

### 1.2 组合根（DES-B §2.4/§2.7/§2.8）

`app/AppCompositionRoot.ets`，全部构造注入、无全局单例/服务定位器：

```text
1  Platform: SystemClock / UuidGenerator / HilogLogger / HilogMetrics
   CryptoService(OhosCryptoProvider) + CryptoRandomSource
2  PreferencesStoreAdapter / RdbStoreAdapter / AssetStoreSecretStore / SecretDraftStore
3  MigrationRegistry:
     FamilyRepository.registerMigrations (v2)
     AuthService.registerMigrations      (v3)
     DomainMigrations.register           (v4)
4  StorageService (constructor registers v1) + initialize()
5  Security: NonceCache / RequestSigner / ResponseVerifier / ClockSkewTracker
6  Repositories (shared DomainOperationGate, bounded wait 2000ms):
     GatewayRepository / FamilyRepository / RoomRepository / SceneRepository / DeviceRepository
7  AuthService.initialize + SessionGateAuthAdapter / ActiveFamilyAdapter
8  InviteService + InviteServiceAdapter
9  FamilyService / RoomService
10 OhosHttpTransport
11 UI_CONTROL LocalGatewayService (2000/3000/1/3000) + BACKGROUND (defaults)
12 SceneService (BACKGROUND DeviceControlPort; DES-B §2.4 note)
13 GatewayDiscoveryService (PB-01: mdns/udp 传 undefined，不猜测 service type)
14 OhosBleTransport + OhosBlePermissionGate + BleProvisioningService
15 Cloud: RdbCloudConfigStore / AssetCloudCredentialStore / OhosCloudHttpTransport /
     CloudCommandClient(+CloudActiveScopePort+ClockPort) / ShadowReader /
     CloudCompletionEvaluator / CloudService(+SystemTimerPort)
16 DeviceCommandRunner(UI client) / DeviceControlCoordinator(LAN→cloud fallback)
17 I18nService(RawfileI18nLoader + OhosLocaleApplier) + initialize()
18 AppContext + ViewModelAppContextBridge + PermissionGate/BleViewModelPermissionGate
```

- **CQG-T14 条件**：`ActiveCloudScope` 作为 `CloudActiveScopePort` 注入 `CloudCommandClient`；`ClockPort` 注入 cloud store/client/service/evaluator/credentials；`isGatewayBound` 只走 `GatewayRoutePort.isBound`，不读 command secret。`ActiveCloudScope` 仅在 active family **恰好 1 条路由**时返回 gatewayId，0/多网关 fail-closed。
- `AuthService.registerMigrations`、`InviteService` 构造、`DomainOperationGate` 共享均已接线。
- 初始化幂等；失败保留 `getInitializationError()` 并重置 promise，`AppContext.retryInitialization()` 支持 StartupError 重试。
- **SC-11**：生产组合根只 import 生产适配器；无 `Mock*` / `ohosTest` / 开发开关。host 静态测试断言。
- 设备骨架：`assembleHap` 可编译（修复补丁后）；真实设备运行仍 `BLOCKED`（D-019）。

### 1.3 权限（`module.json5`）

```json5
"requestPermissions": [
  { "name": "ohos.permission.INTERNET" },
  { "name": "ohos.permission.ACCESS_BLUETOOTH",
    "reason": "$string:permission_bluetooth_reason",
    "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" } }
]
```

- 仅声明 INTERNET（system_grant）与 ACCESS_BLUETOOTH（user_grant）。
- **未声明** CAMERA / LOCATION / APPROXIMATELY_LOCATION / GET_NETWORK_INFO；不猜测。
- `PermissionGate`：`INTERNET → GRANTED`；`BLUETOOTH → check/request`；CAMERA/LOCATION/NOTIFICATIONS → `UNAVAILABLE`（v1 不支持，调用方使用文本/粘贴回退）。
- `PermissionPolicy.requiredForProvisioning()` 只返回 BLUETOOTH。
- `openSettings()` 使用 `ohos.settings.app.info`。
- `backup_config.json` 改为 `allowToBackupRestore: false`（DES-B §17.1.6 审查结论：避免备份 RDB/Asset/Preferences 中的家庭/凭据数据）。

### 1.4 资源与 i18n

| 资源 | 内容 |
|---|---|
| `base/en_US string.json` | 新增 28 键，两语言 53/53 对齐：4 Tab、壳标题/无家庭、占位页标题、SessionGate、启动错误、未知路由、权限 reason、页面/按钮标签 |
| `base/dark color.json` | 新增 19 个 `shell_*` / `orb_*` token，明暗各 20 个颜色，全部经 `$r('app.color.*')` 引用 |
| `rawfile/i18n/zh-CN.json`、`en-US.json` | 补齐顶层 `brand.gree/haier/midea/generic`；新增 `settings.cloud.single_gateway_required`；两语言键集 100% 对齐 |
| `allowlist.json` | 登记 4 个 `brand.*` 固定键（F-05），说明由 C-16 固定映射返回、C-24/C-27 消费 |

`check_i18n`：**0 blocking / 10 warnings**（warning 均来自既有 C-16/C-20 文件，非本任务新增）。

### 1.5 R3-02（cancel → end）

`ContinuousGestureGuard` 提供 `begin/cancel/end`：`cancel()` 后 `end()` 返回 false，UI 不得再调用 `endContinuous()`。host 测试覆盖 cancel→TouchUp 抑制；静态测试断言 `pages/**` 不出现 `cancelContinuous` 与 `endContinuous` 同时接线。T-18 滑杆必须使用该守卫（或等价显式 flag）。

---

## 2. 验证证据（实际执行）

### 2.1 当前任务树（未应用越界补丁）

| 命令 | 结果 | 证据 |
|---|---|---|
| `ohpm install` | ✅ 完成 | `entry/src/test/evidence/t17-ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | ❌ **FAIL**：14 条 ArkTS 错误（全部在写范围外，见 §3） | `entry/src/test/evidence/t17-clean-assemble.log` |
| `codelinter -c code-linter.json5 -p default .` | ✅ exit 0：0 error / 15 performance warning（自定义组件建议） | `entry/src/test/evidence/t17-codelinter.log` |
| `entry/src/test/run-host-tests.sh` | ✅ **639/639 PASS**（新增 26 条 T17 用例） | `entry/src/test/evidence/t17-host-node-tests.tap` |
| `python3 entry/src/test/i18n/check_i18n.py ... --strict-ui` | ✅ 0 blocking（10 既有 warning） | `entry/src/test/evidence/t17-i18n-checker.log` / `t17-i18n-report.json` |

### 2.2 应用最小补丁后的独立验证（只读副本 `/tmp/opencode/yaocore-probe`，未改任务树）

| 命令 | 结果 |
|---|---|
| `hvigorw clean assembleHap --no-daemon` | ✅ **BUILD SUCCESSFUL in 11 s 499 ms** |
| `entry/src/test/run-host-tests.sh` | ✅ **639/639 PASS** |
| `codelinter` | ✅ exit 0：0 error / 15 warning |
| `check_i18n --strict-ui` | ✅ 0 blocking / 10 warning |

补丁：`artifacts/50-implementation/t17-c28-compile-fix.patch`（5 文件，163 行 diff）。

---

## 3. BLOCKER：写范围外的既有编译缺陷（首次进入生产 HAP 图）

`AppCompositionRoot` 首次让 C-08..C-19 进入 `assembleHap` 编译图；以下文件此前只被 host/ohosTest 引用，ArkTS 编译器现在报错：

| # | 文件 | 错误 | 最小修复 |
|---|---|---|---|
| 1 | `common/utils/Base64Url.ets:113` | `Cannot find name 'AppError'` | 导入 `AppError`（并消除 7 条 throw 级联错误） |
| 2-4 | `service/ble/BleProvisioningService.ets:146/396/459` | 对象字面量不能实现 `BleScanListener`；`throw error` 类型过宽 | 命名 `DelegatingScanListener` 类；`throw error as Error` |
| 5 | `service/ble/BindingProbe.ets:234` | `throw error` 类型过宽 | `throw error as Error` |
| 6 | `service/cloud/SystemTimerPort.ets:47` | reject 回调 `Error` 与 `AppError` 名义类型不兼容 | `rejecter: (error: AppError) => void` |
| 7 | `service/ble/GattRequestQueue.ets:83` | 同上 | reject 参数类型改为 `AppError` |

这些文件均不在 `writes`/`commit_paths`：
`entry/src/main/ets/service/ble/**`、`entry/src/main/ets/service/cloud/**`、`entry/src/main/ets/common/utils/**`。
按框架“不得越界扩围”和 `swe_guard` 的 actual-change 校验，**本任务未修改它们**；因此当前分支的 HAP 构建为 FAIL，不能声明 COMPLETE。

**建议处置**：Orchestrator 以本分支 tip 为基线创建一个扩围修复任务（`writes` 增加上述 5 个文件，`commit_paths` 同步），应用 `t17-c28-compile-fix.patch` 后复跑四项验证；通过后与壳层一起合并。补丁已在只读副本验证 BUILD SUCCESSFUL，不需要重新设计。

---

## 4. 文件清单

- **新增**：`app/` 13 文件；`pages/` 15 文件；`entry/src/test/host/AppShell.test.mjs`。
- **修改**：`entryability/EntryAbility.ets`、`pages/Index.ets`、`module.json5`、`base|dark color.json`、`base|en_US string.json`、`rawfile/i18n/{zh-CN,en-US}.json`、`base/profile/backup_config.json`、`entry/src/test/i18n/allowlist.json`。
- **证据**：`entry/src/test/evidence/t17-*.log|tap|json`。
- **补丁**：`artifacts/50-implementation/t17-c28-compile-fix.patch`。

---

## 5. 偏离项（已记录，不改变 G-004 语义）

1. **C-24 token 位置**：DES-B §13 的规范位置是 `common/theme/**`，不在 T-17 写范围；`app/ShellTheme.ets` 是本任务唯一 token 定义（UIUX §2/§5 原值）。T-18 应迁移/扩展到 `common/theme/**`，不得再定义第二套。T-17 只实现壳层所需子集，未实现完整 `AppColors` 静态方法封装（页面直接 `$r('app.color.*')`，符合 I18N-08）。
2. **壳层 DI 语法**：页面通过显式 `@Require` props 接收 `AppContext/NavigationService/I18nService`，未使用 `@Provide/@Consume`。原因：`@Provide` 无法从可选 `@LocalStorageProp` 安全初始化，且 ArkTS 对可选对象注入更严格；语义仍是 Index 单实例向下传递，无全局单例/服务定位器。T-18 可在页面内改为 `@Consume`（Index 已提供实例）。
3. **组合根 SceneService 顺序**：DES-B §2.4 将 SceneService 列在步骤 13；它依赖 `BACKGROUND` `DeviceControlPort`（步骤 16），因此实际构造在 `GATEWAY_CLIENTS` 之后。`CompositionPlan` 与 host 测试显式记录该依赖顺序。
4. **启动重试**：`AppCompositionRoot.initialize()` 失败后重置 in-flight promise，`AppContext.retryInitialization()` 重新执行一次；成功路径仍幂等。用于满足 DES-B 的 StartupError retry，不改变启动状态机。
5. **`backup_config.json`**：关闭备份（而非逐项排除），作为“至少不得备份 secret”的最保守实现；T-19 可评估是否需要细粒度备份。
6. **设备骨架**：`CloudDevice.test.ets` 的“全新库直接 initialize”问题在 `entry/src/ohosTest/**`（写范围外），仍 `DEFERRED`；本任务只保证 `assembleHap` 生产图（补丁后）可编译。
7. **C-24 完整组件**：`components/**` 不在写范围；T-17 只交付壳层与占位页，完整 GlassSurface/StatusBanner/卡片由 T-18 承接。

---

## 6. 风险 / DEFERRED

| 项 | 级别 | 说明 | 归属 |
|---|---|---|---|
| 5 文件编译缺陷 | **阻断（本任务）** | 见 §3；补丁已验证 | Orchestrator 扩围修复任务 |
| `CloudDevice.test.ets` 迁移/Clock 注入 | Medium（设备） | 写范围外；设备 BLOCKED | T-18/T-19 |
| C-24 完整 token/组件 | Medium | 仅壳层 token；T-18 必须迁移而非复制 | T-18 |
| `@Provide` 未使用 | Low（契约语法） | 显式 props 等价；记录于 §5.2 | T-18 可替换 |
| `brand.*` 动态拼接 | Low（C-16 既有） | 资源已补齐；F-05 固定映射仍由 C-16/T-18 收敛 | T-18 |
| 真实 BLE/LAN/云/UI 时序 | BLOCKED | 无设备/模拟器；D-019 | T-19 |
| 10 条 i18n warning | Low（既有） | 均来自 C-16/C-20 文件，非本任务新增 | 维护轮 |

---

## 7. 下一步

1. Orchestrator 决策：以 `task/wp-067-ui-shell` tip 为基线创建扩围修复任务（写范围加入 §3 的 5 个文件），应用 `t17-c28-compile-fix.patch`。
2. 修复任务复跑：`ohpm install` → `hvigorw clean assembleHap --no-daemon` → `codelinter` → `run-host-tests.sh` → `check_i18n`；预期 639/639、0 error、0 blocking。
3. 之后执行 T-17 独立评审（CQG-T17/IG-3），再进入 T-18 完整页面/资源面。
4. 本任务在评审/修复前不得合并到 `feat/yaocore-app`；设备证据保持 `BLOCKED`。
