# T-18 UI 设计系统与全量页面（C-24 / C-25 / C-26 / C-27）

- **Artifact ID**: T18-UI-PAGES
- **Producer**: agent:implementation-engineer
- **Task**: `wp-073-ui-pages`（Handoff `state/handoffs/wp-073-ui-pages.json`）
- **Branch**: `task/wp-073-ui-pages`（base `6737303`，父分支 `feat/yaocore-app`）
- **Status**: **COMPLETE（代码/构建/主机测试/i18n 检查完成；待独立复审与 CQG-T18；设备/视觉 BLOCKED）**
- **Date**: 2026-10-18
- **Workflow**: STANDARD / GATED_AUTO
- **Scope source**: DES-001B §13/§14/§15/§16/§17、UIUX §2/§3/§4/§5、T-17 裁定、CQG-T17 范围重定义（C-24/C-25 转 T-18）

> **结论先行**：已交付 C-24 设计 token 与 21 个复用组件，C-25（Home/Rooms/DeviceControl）、C-26（Family/Room/Scene）、C-27（Provisioning/Settings/About/Profile）全部页面体；T-17 残余 R2-02/R2-03/R2-06 已处理，R2-01 范围重定义已在 CQG-T17 与本报告登记。五项必跑命令全部通过：`ohpm install` exit 0、`hvigorw clean assembleHap` BUILD SUCCESSFUL、`codelinter` 0 error、host **672/672 PASS**、i18n **blockingFailures=0**；额外 ohosTest 仅编译 BUILD SUCCESSFUL。设备/Previewer/视觉/动效/触感仍为 **BLOCKED**，本报告不把编译或主机证据写成设备 PASS。

---

## 1. 实现范围

### 1.1 文件与组件计数

| 类别 | 数量 | 路径 |
|---|---:|---|
| 页面文件 | 15 | `entry/src/main/ets/pages/**`（11 个业务页面 + MainShell/Index/Shell 视图） |
| 页面 struct | 16 | Home/Rooms/DeviceControl/Family/RoomManage/Scene/Provisioning/Settings/About/Profile + MainShell/Index/Shell 组件 |
| 复用组件文件 | 6 | `entry/src/main/ets/components/**` |
| 复用组件 struct | 21 | 10 通用控件 + StatusBanner/EnvironmentPanel/RoomChipBar + Light/Climate/Door/Sensor/Scene/Room 卡片 + DeviceGrid/UnassignedPool |
| 设计系统文件 | 3 | `common/theme/{AppTheme,AppEnums,ShellTheme}.ets` |
| 新增 i18n 资源键 | 326（净增） | zh-CN 543 / en-US 545（含 2 个英文 plural variant） |
| 新增 host 测试 | 16 | `entry/src/test/host/UiPages.test.mjs`（总 672/672） |
| 设备编译骨架 | 1 | `entry/src/ohosTest/ets/test/ui/UiPagesDevice.test.ets`（COMPILED_ONLY，BLOCKED） |

### 1.2 C-24 设计系统

- `AppColors`：ink/inkSoft/muted/mutedLight/surface/surfaceStrong/field/edge/line/primary/primaryDark/green/amber/red/orb*；全部来自 `$r('app.color.*')`，base/dark 双份定义。
- `AppMotionTokens`：UIUX §5 同名常量（SPRING_TOUCH/MODAL/REVERT、55ms 节流、3s/30s/10s 超时、320ms 回弹、阴影/光晕、光核周期），并提供 `motionMs(enabled)`。
- `AppSpacing`/`AppRadius`/`AppTypography`/`AppShadows`/`AppLayout`。
- `AsyncUiState`/`CardVisualState`/`UiAction`（`common/theme/AppEnums.ets`，host 可导入，无 ArkUI 全局依赖）。
- `ShellTheme` 从 `app/ShellTheme.ets` **迁移**到 `common/theme/ShellTheme.ets`；所有旧页面引用已更新，原文件删除，不存在第二套 token。
- 复用组件（全部显式 `@Require i18n` + `@Prop localeRevision`，不访问仓储/传输/VM）：
  `GlassSurface`、`SectionHeader`、`PrimaryButton`、`IconButton`、`AppTextField`、`SliderControl`、`EmptyState`、`ErrorState`、`LoadingSkeleton`、`AppDialog`、`StatusBanner`、`EnvironmentPanel`、`RoomChipBar`、`LightCard`、`ClimateCard`、`DoorCard`、`SensorTile`、`SceneCard`、`RoomCard`、`DeviceGrid`、`UnassignedPool`。
- 三态视觉：`IDLE/PENDING/COMMITTED/REVERT` 映射、离线/禁用/只读覆盖、琥珀 REVERT 描边、COMMITTED 光晕、PENDING 跟手；`AppMotionTokens.motionMs` 已提供，卡片接收 `motionEnabled` 在关闭动效时使用 0ms/短动画。
- 背景光核：`ShellBackdrop` 保持四光核 + 62px 模糊 + 降低动效透明度；长周期呼吸动画仍为静态（视觉证据 BLOCKED）。

### 1.3 C-25 / C-26 / C-27 页面

| 页面 | 交付要点 | 契约 |
|---|---|---|
| HomePage | StatusBanner（家庭/LAN/云/RTT/刷新）、环境看板（温度/湿度/PIR/来源/时间）、房间胶囊、DeviceGrid 快捷卡片、空/错/加载态、Add gateway | §14.1.2/§14.3 |
| RoomsPage | RoomCard 网格、房间设备列表、未分配池、Add room、房间过滤高亮（Home→Rooms） | §14.1.3 |
| DeviceControlPage | Light 开关/亮度 55ms+TouchUp/颜色、AC 16..30 与 7 模式/非标只读、Door 四阶段/UNVERIFIED/报警/门磁引导、Sensor 只读、Unsupported/Disabled/offline banner、设备信息 | §14.1.4/§14.2 |
| FamilyManagePage | 成员/角色/状态/最近同步（不显示在线）、RBAC 可见性、YCR1→YCI1 两步 KEY_WRAP、CODE_KEK 弱模式警告+6 位码、回执导入、撤销、转让/移除/退出/解散二次确认、轮换提示 | §15.1.2 |
| RoomManagePage | 创建/改名/排序、previewDelete→阻断确认→confirmDelete、设备数变化重预览、未分配池指派；删除不删物理设备 | §15.1.3 |
| ScenePage | SceneCard、执行进度浮层、✓/✗/– 步骤、百分比、取消、PARTIAL_FAILED/FAILED/CANCELLED no-rollback 强制提示、编辑暂缓的诚实提示 | §15.1.4 |
| ProvisioningPage | 6 步指示、权限/扫描/安全握手/Wi-Fi/下发/绑定、取消清理、错误映射回退步骤、成功进入未分配池并跳转房间 | §16.1.2 |
| SettingsPage | 语言三选一即时切换+重启提示、云状态/endpoint/projectId/deviceId/token/test/clear、单网关限制、按网关安全档案/P-HMAC 无机密性/P-TLS-PIN/P-BLOCKED/轮换入口、高级手动 IP+端口+探测、通知/动效开关、锁定、关于入口 | §16.1.3 |
| AboutPage | 版本、隐私、安全边界、GUEST 非密码学边界、开源/许可证；不显示 endpoint/token/secret | §16.1.4 |
| ProfilePage | 本机档案/角色/家庭、GUEST 到期、家庭/设置/关于/添加网关、锁定；无跨设备在线状态 | §16.1.4 |
| MainShell/Index | 4 Tab、NavDestination 路由参数校验、`localeRevision`/`motionEnabled`/`vmFactory` 显式传递、未知路由 ErrorState | §17.1.5 |

## 2. DI / 主题迁移记录（T-17 裁定落地）

1. **唯一 DI 方式**：构造注入 + 显式 props。`pages/**`/`components/**` 无 `@Provide`/`@Consume`；页面不 `new` 服务、仓储或 VM。
2. **新增 C-28 增量 seam**：`app/PageVmFactory.ets` 定义 `PageVmFactoryPort`；`AppContext.pageVms` → `AppCompositionRoot.pageVms` 委托转发（未改 `AppContext`/`AppCompositionRoot` 既有方法签名，仅 additive getter）。`Index` 读取一次并传给 `MainShell`，再以显式 prop 传给每个页面。
3. **页面生命周期**：`aboutToAppear` 通过 `vmFactory.create*ViewModel()` 创建、订阅；`aboutToDisappear` 取消订阅并 `dispose()`；Home 额外创建 DeviceViewModel 供快捷三态/控制，Rooms 使用 RoomViewModel + DeviceViewModel。
4. **ShellTheme 迁移**：`app/ShellTheme.ets` 删除；`common/theme/ShellTheme.ets` 仅作为 token facade，全部值来自 `AppMotionTokens`/`AppSpacing`/`AppTypography`/`AppRadius`。未保留 app 层第二份常量。
5. **R2-06 可观察性**：`AppContext.subscribeActiveFamily(listener)`，在 `refreshSessionGate`/`onForeground` 检测 activeFamilyId 变化时通知；Home 订阅刷新。host 测试 `T18_activeFamilyIsObservable` 覆盖。
6. **R2-02 专用 onboarding 标签键**：`OnboardingView` 改用 `onboarding.*` 键（标题/字段/动作/提示），不再复用 `family.create/family.switch` 等语义不匹配键。
7. **R2-03 createFamily 清理/幂等**：`OnboardingService.createFamily` 在 profile 创建失败时 best-effort `FamilyService.dissolveFamily` 清理孤家庭；`AUTH_PROFILE_EXISTS` 仅对同一 member 幂等。host 测试覆盖清理与幂等两条路径。
8. **路由补充**：`NavigationService.openRoomsWithHighlight/consumeRoomsHighlight` 支持 Home 房间胶囊→Rooms 选中；`MainShell` 在切 Tab 时消费并传 `highlightRoomId`。
9. **颜色/主题**：新增 24 个 base/dark 颜色别名（surface/field/scrim/shadow/committed/revert/pending 等）；页面/组件不写死 `#RRGGBB` 主题色。仅 `UiMapping.LIGHT_COLOR_PRESETS` 保存设备 SET_COLOR 负载色（非 UI 主题色，已注释）。
10. **i18n 重渲染**：所有页面/组件接收 `localeRevision`；页面根容器 `.id('<page>-locale-'+localeRevision)`，Index/SessionGate/Onboarding 同样绑定，运行时语言切换可重建；`SettingsViewModel` 另订阅 `onLocaleChanged`。

## 3. 状态、错误与 i18n

- 三态：`ControlPhase.IDLE/PENDING/COMMITTED/REVERT` → `CardVisualState`；离线/禁用/只读覆盖；Door `SECURED/UNCONFIRMED/UNKNOWN/UNVERIFIED` 文案严格，`UNVERIFIED` 使用 `door.link.unverified`，不显示“已锁好”。
- 空/加载/错误：各页面均有 `LoadingSkeleton`/`EmptyState`/`ErrorState`；错误仅显示 `ViewModelError.i18nKey`/`AppError.i18nKey`，不展示原始网关 message。
- 成功/失败：Scene 局部失败不显示成功并强制 `scene.no_rollback`；Door 无证据不升级 SECURED；控制 REVERT 只影响当前设备。
- i18n key：页面/组件用户文案全部 `t()` 或 `$r('app.string.*')`；新增键覆盖 home/rooms/device/family/scene/provisioning/settings/about/profile/onboarding/common/card/cloud 等命名空间；参数名 zh/en 完全一致。
- `ErrorI18nMapper` 保持唯一错误→键入口；未新增错误码、未改契约语义。

### 3.1 legacy 596 中已迁移页字符串（可核对清单）

> 匹配方式：旧中文与 `zh-CN.json` 现值为精确/去标点归一匹配。共 59 条可自动核对；另有大量旧文案按页面语义重写为新键（非逐字），见页面实现。本任务未改写 `legacy-migration.csv`，避免把未人工复核的条目误标 ACCEPTED。

| # | 旧中文 | 新键 | 匹配 |
|---|---|---|---|
| 1 | Wi-Fi 认证失败，请检查密码 | `provisioning.error.auth_error` | normalized |
| 2 | 编辑 | `common.edit` | exact |
| 3 | 操作失败，请重试 | `errors.app.internal_error` | normalized |
| 4 | 查看 | `common.view` | exact |
| 5 | 成功 | `scene.step.succeeded` | exact |
| 6 | 除湿 | `ac.mode.dry` | exact |
| 7 | 传感器 | `device.type.sensor` | exact |
| 8 | 灯光 | `device.type.light` | exact |
| 9 | 端口 | `settings.advanced.port` | exact |
| 10 | 格力 | `brand.gree` | exact |
| 11 | 关闭 | `common.close` | exact |
| 12 | 海尔 | `brand.haier` | exact |
| 13 | 节能 | `ac.mode.eco` | exact |
| 14 | 开关 | `device.type.switch` | exact |
| 15 | 空调 | `device.type.ac` | exact |
| 16 | 离线 | `device.state.offline` | exact |
| 17 | 美的 | `brand.midea` | exact |
| 18 | 门已打开 | `device.door.stage.open` | exact |
| 19 | 密码（至少 8 位） | `onboarding.password` | exact |
| 20 | 密码至少 8 位 | `onboarding.password` | normalized |
| 21 | 扫描中 | `provisioning.progress.scanning` | exact |
| 22 | 删除 | `common.delete` | exact |
| 23 | 上锁 | `device.door.lock` | exact |
| 24 | 设备 | `device.info.device` | exact |
| 25 | 设备离线 | `errors.gateway.device_offline` | normalized |
| 26 | 摄像头 | `device.type.camera` | exact |
| 27 | 失败 | `scene.step.failed` | exact |
| 28 | 湿度 | `home.environment.humidity` | exact |
| 29 | 收起 | `common.collapse` | exact |
| 30 | 刷新 | `common.refresh` | exact |
| 31 | 睡眠 | `ac.mode.sleep` | exact |
| 32 | 送风 | `ac.mode.fan` | exact |
| 33 | 添加 | `common.add` | exact |
| 34 | 添加网关 | `provisioning.title` | exact |
| 35 | 已完成 | `family.join.phase.completed` | exact |
| 36 | 网关在线 | `home.gateway.online` | exact |
| 37 | 未发现设备 | `provisioning.scan.empty.title` | exact |
| 38 | 未找到场景 | `errors.app.scene_not_found` | normalized |
| 39 | 项目 ID | `settings.cloud.project_placeholder` | exact |
| 40 | 新建 | `room.new` | exact |
| 41 | 移除 | `common.remove` | exact |
| 42 | 已配置 | `cloud.state.configured` | exact |
| 43 | 已上锁 | `door.state.secured` | exact |
| 44 | 已选择 | `provisioning.scan.selected` | exact |
| 45 | 云端 | `settings.section.cloud` | exact |
| 46 | 在线 | `device.state.online` | exact |
| 47 | 执行 | `scene.run` | exact |
| 48 | 执行中 | `scene.step.running` | exact |
| 49 | 制冷 | `ac.mode.cool` | exact |
| 50 | 制热 | `ac.mode.heat` | exact |
| 51 | 自动 | `ac.mode.auto` | exact |
| 52 | 简体中文 | `settings.language.zh_cn` | exact |
| 53 | 跳过 | `scene.step.skipped` | exact |
| 54 | 上一步 | `common.previous` | exact |
| 55 | 下一步 | `common.next` | exact |
| 56 | 语言 | `settings.section.language` | exact |
| 57 | 通用 | `brand.generic` | exact |
| 58 | 取消 | `common.cancel` | exact |
| 59 | 刷新失败，请重试 | `common.refresh_failed` | normalized |

TOTAL 59

## 4. 验证（实际执行，cwd = 仓库根）

| # | 命令 | 结果 | 证据 |
|---|---|---|---|
| 1 | `ohpm install` | exit 0；`install completed in 0s 46ms` | `entry/src/test/evidence/t18-ohpm-install.log` |
| 2 | `hvigorw clean assembleHap --no-daemon` | **BUILD SUCCESSFUL in 15 s 471 ms**；COMPILE RESULT 无 ERROR；68 条既有 ArkTS warning（SDK 26→API14 兼容提示，非本任务新增） | `entry/src/test/evidence/t18-clean-assemble.log` |
| 3 | `codelinter -c code-linter.json5 -p default .` | exit 0；**Errors 0 / Warns 25 / Suggestions 0**（均为自定义组件性能建议） | `entry/src/test/evidence/t18-codelinter.log` |
| 4 | `entry/src/test/run-host-tests.sh` | **672/672 PASS**，fail 0 / skipped 0（新增 T18 16 条） | `entry/src/test/evidence/t18-host-node-tests.tap` |
| 5 | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | exit 0；**blockingFailures=0 / missingKeys=0**；warnings=134（既有 C-16/C-20/Mock 与本次技术枚举字符串）；hardcoded=77 条 warning 均为技术状态/枚举，不是用户文案 | `entry/src/test/evidence/t18-i18n-checker.log` |
| 6 | `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon`（附加） | **BUILD SUCCESSFUL**（仅编译，不代表设备执行）；新增 `ui/UiPagesDevice.test.ets` 把全部页面/组件纳入 ohosTest 编译图 | `entry/src/test/evidence/t18-ohosTest-assemble.log` |

### 4.1 Host 新增覆盖（16 条）

`T18_cardVisualState_mapsControlPhaseAndOverrides`、`T18_cardVisualState_readOnlyWhenUnsupportedOrUnassigned`、`T18_brightnessAndTemperatureFollowPendingValueThenConfirmed`、`T18_roomJoinAndCountsUseRoomEntitiesNotHints`、`T18_filtersMatchAllRoomAndUnassigned`、`T18_sceneProgressMarkersAndNoRollback`、`T18_familyJoinAndInviteGuards`、`T18_doorStagesNeverUpgradeWithoutEvidence`、`T18_provisioningStepAndErrorMapping`、`T18_settingsStateLocaleCloudAndSecurityKeys`、`T18_loadStateAndColorPresets`、`T18_routeParametersRequireDeviceIdentity`、`T18_activeFamilyIsObservable`、`T18_onboardingCreateFamilyCleansUpFailedProfile`、`T18_onboardingCreateFamilyIsIdempotentForSameMember`、`T18_pagesUseExplicitPropsAndNoProvideConsume`。

既有 `ViewModelDevice`/`ViewModelThrottle`/`DoorConfirmationTracker`/`ViewModelClimate`/`ViewModelDoor`/`ViewModelFamily`/`ViewModelRoom`/`ViewModelScene`/`ViewModelSettings`/`ViewModelBle` 测试继续通过，覆盖 55ms 节流/TouchUp、三态、门锁四阶段、邀请流、场景进度、云/语言状态。

## 5. 设备/视觉限制（BLOCKED，不作为 PASS）

| 项 | 状态 | 说明 |
|---|---|---|
| Previewer/真机启动、4 Tab、NavDestination 返回 | **BLOCKED** | 无设备/Previewer；仅 ArkTS 编译与 host 纯逻辑 |
| 视觉：光核/毛玻璃/暗黑/428×872/长英文/安全区 | **BLOCKED** | 需截图评审；token 已定义 |
| 动效/触感：springMotion、COMMITTED 轻震、REVERT 回弹 | **BLOCKED** | `motionEnabled=0ms` 降级已接线，实际观感未验证 |
| 75% 文本膨胀/对比度/读屏 | **BLOCKED** | 交互控件已统一到 ≥44vp；读屏标签多数已加，需设备抽查 |
| BLE 配网/权限弹窗/真实扫描/绑定探针 | **BLOCKED** | 依赖真机与网关；页面仅渲染 C-23 状态 |
| 门磁联动/真实开锁确认 | **BLOCKED** | DoorViewModel 已实现四阶段；页面未接 DeviceChangeEvent 总线（VM 无页面级事件入口） |

## 6. 偏离项 / DEFERRED / 风险

### 6.1 已记录偏离（不改变契约语义）

1. **组件 props 命名**：`PrimaryButton`/`IconButton` 的 `enabled`/`onClick` 与 ArkUI `CustomComponent` 基类成员冲突，按编译器要求改名为 `isEnabled`/`onTap`；语义与契约一致。`AppTextField`/`SliderControl` 的 `enabled` 同样改 `isEnabled`；`SliderControl` 额外提供 `onBegin` 以正确接 55ms 起点。
2. **Provisioning 凭据收集顺序**：C-23 `submit(pop, ssid, wifiPassword)` 是聚合入口，首次调用才真正开始 BLE/Security1/AP 扫描。因此页面在 Step2 收 PoP、Step3 收 SSID（AP 列表可用时展示，否则手输）、Step4 收密码后一次下发；C-23 内部状态机、30s 超时、取消清理、绑定探针仍由 VM 执行。`expectedGatewayId` 仅展示/路由提示，VM 未暴露 expectedGateway 校验入口。
3. **扫码/二维码**：未引入 ScanKit/CAMERA 权限（T-17 权限最小集保持 INTERNET+ACCESS_BLUETOOTH）；邀请以可选文本 YCR1/YCI1 容器呈现，二维码位以可选择文本替代。
4. **设备删除/改名**：C-21/C-22 未暴露 UI 级 `removeDevice`/`renameDevice` VM API；未分配池隐藏删除按钮，改名对话框 DEFERRED，避免页面直接访问仓储。
5. **场景编辑**：SceneEditSheet DEFERRED；ScenePage 对编辑显示诚实提示，执行/进度/取消/no-rollback 全部实现。
6. **通知系统权限状态**：仅持久化开关；未接 `notificationManager` 系统状态（页面无该 Port）。
7. **权限“去设置”**：`PermissionPort` 只有 `ensure`，未暴露 `openSettings`；页面显示拒绝/蓝牙关闭文案，不提供跳设置按钮。
8. **动效开关即时性**：Index 启动时读取 `isMotionEnabled`；Settings 切换后下次进入/重启生效，已在设置页提示“外观跟随系统”。卡片 `motionEnabled` 显式 prop 已接线。
9. **背景光核动画**：保留静态四光核；长周期呼吸动画未启动（视觉 BLOCKED），周期 token 已定义。
10. **StatusBanner IP**：`GatewayStatus` 无 IP 字段，显示家庭/网关名/LAN/云/RTT/警告，不显示 IP。
11. **Role change to GUEST**：成员行“改角色”没有房间授权参数（C-22 VM API 限制）；无授权房间时服务会拒绝并显示错误。
12. **Home 与 Rooms 双 VM**：Home 为快捷控制创建 DeviceViewModel（与 HomeViewModel 同源 SSOT），避免在页面直接访问仓储；不影响契约。

### 6.2 DEFERRED

- ScanKit/相机二维码、设备删除/改名、Scene 编辑、通知系统权限、权限去设置、Provisioning expectedGateway 强校验、视觉/动效/触感/读屏设备验证。

### 6.3 风险

- **视觉与交互未实机验证**：本报告只能证明编译/主机逻辑，不能证明 UI 外观、暗黑、长英文、动效。
- **组件分层**：components 仍 import `viewmodel/core` 状态类型（C-24 props 契约要求）与 `service/ac/AcModels` 纯 DTO；同时 `components/support/UiMapping` 构造 AC/Door 预览。T-20 `check_layering.py` 落地时若按最严格 D-12 解释，可能需要把预览构造上移到页面层；当前未使用任何仓储/传输/service 实现调用。
- **Family 成员改 GUEST 缺少房间授权输入**，服务层可能拒绝；需 C-22 增量 API 或页面房间选择 + 新 use case。
- **Onboarding cleanup** 失败时仍可能留孤家庭（dissolve 依赖存储可用）；原错误优先返回。
- **i18n 资源 543/545**：英文多 2 个 plural variant，规范化 parity 100%；无缺失键。

## 7. 约束核对

- 未修改 `entry/src/main/ets/service/**`、`repository/**`、`viewmodel/**`、`entryability/**`、`module.json5`、`AppScope/**`、契约/计划/评审报告。
- 未改变既有错误码、错误分类、Contract 语义、Mock 排除、权限最小集。
- 未切换分支、未 pull/merge/rebase/push；验证输出仅落在 ignored 构建目录与 `entry/src/test/evidence/`。
- 新增 `PageVmFactoryPort`/`AppContext.pageVms`/`subscribeActiveFamily`/`openRoomsWithHighlight` 均为 additive seam，按 DES-B §17.1.2 T-18 增量工厂条款记录。
- `ShellTheme` 删除原文件是任务指定的迁移动作，不是分叉。

## 8. Next action

提交 `task/wp-073-ui-pages` 全部声明路径 → `swe_guard finish` → 独立 `quality-reviewer` 复审（重点：DI 无 @Provide/@Consume、i18n 硬编码、Room 删除保护、Door UNVERIFIED、Provisioning 取消清理、设置云/语言/手动 IP）→ CQG-T18 → IG-3 设备矩阵（T-19，BLOCKED）。
