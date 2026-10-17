# T-18 评审修复报告（F-01..F-23）

- **Artifact ID**: T18-FIX-REPORT
- **Producer**: agent:implementation-engineer
- **Task**: `wp-075-fix-t18`（Handoff `state/handoffs/wp-075-fix-t18.json`）
- **Branch**: `task/wp-073-ui-pages`（base `7974305`，parent `feat/yaocore-app`）
- **Input**: `artifacts/70-review/t18-review.md`（CHANGES_REQUIRED）
- **Status**: **COMPLETE（代码/构建/主机测试/i18n 检查完成；待独立复审与 CQG-T18）**
- **Date**: 2026-10-18
- **Workflow**: STANDARD / GATED_AUTO

> **结论先行**：4 个 High（F-01..F-04）全部修复；Medium F-05/F-07/F-08/F-09/F-10 全部修复，F-06 按任务要求记录 D-12 扩展点（文档裁定归 architect）；Low 中 F-11/F-12/F-13/F-14/F-16/F-18/F-19/F-20 修复，F-15/F-17（部分）/F-21 记录为残余项。新增 13 条 host 测试（672→685），其中包含 LightCard toggle/PENDING、GUEST/MEMBER/ADMIN 场景矩阵、RoomService/Guest/Member/Admin 矩阵、离线控制、Door 阶段映射与 D-12/RBAC source-level 守卫。五项必跑命令全部通过；设备/视觉仍 **BLOCKED**。

---

## 1. 逐条处置

### 1.1 High（CQG-T18 阻断项）

| ID | 处置 | 实现与证据 |
|---|---|---|
| **F-01** LightCard 电源回调未接线 | **Fixed** | `components/DeviceCards.ets`：`LightCard` 增加 44vp 可访问电源 Button，点击调用 `this.onToggle()`；`DeviceGrid` 的 `onQuickToggle` 与 `DeviceControlPage` 的 `togglePower` 现有接线因此可达。`HomePage.quickToggle` 对 LIGHT/AC 走 `DeviceViewModel.togglePower`，失败/超时仍由 C-21 三态处理。测试：`T18_lightCardWiresPowerToggleAndKeepsPendingSliderLive`。 |
| **F-02** GUEST 场景执行未 fail-closed | **Fixed（跨层）** | **服务层**：`SceneService` 新增 `SceneExecutionAuthorizationPort`；`run()` 先 `authorizeExecution()`，无端口或 `canExecuteScene=false` 时抛 `AUTH_RBAC_DENIED`（fail-closed）。**组合根**：`SceneExecutionAuthAdapter` 调用 `AuthService.getActiveSession()` + `AuthService.canExecuteScene(session)`。**VM/UI**：`SceneViewModel.canExecuteScene()` 使用同一端口；`ScenePage` 无权限时禁用 Run 并显示 `errors.app.auth_rbac_denied`。测试：`T18_C11_sceneRunRbacMatrixAdminMemberGuestAndMissingPolicy`、`T18_SceneViewModel_capabilityAndRunRbacMatrix`、`T18_scenePageAndServiceUseTheSameRbacGate`。 |
| **F-03** 房间/未分配池/网关管理入口与服务层 RBAC | **Fixed（跨层）** | **服务层**：`RoomService` 的 `createRoom/renameRoom/setIcon/reorderRooms/deleteRoom/assignDevice/unassignDevice/moveDevice` 增加 `actorMemberId?`，通过 `RoomActorLookupPort` 查询 C-08 成员并 `FamilyRbac.requireAdmin`，非 ACTIVE/MEMBER/GUEST → `AUTH_RBAC_DENIED`。**VM**：`RoomViewModel` 通过 `RoomSessionPort` 传入当前 session memberId。**UI**：`RoomsPage` 隐藏 Add room、RoomCard 编辑/删除、UnassignedPool 指派；`RoomManagePage` 隐藏池指派；`HomePage` 隐藏 Add gateway；`ProfilePage` 隐藏配网入口；`SettingsPage` 隐藏高级手动 IP 区并保留 ADMIN 判断。测试：`T18_C09_roomMutationsRequireAdminActorMatrix`、`T18_RoomViewModel_passesActiveMemberIdToServiceActorChecks`、`T18_nonAdminRoomPoolAndGatewayEntriesAreHidden`。 |
| **F-04** PENDING 滑杆被禁用 | **Fixed** | `UiMapping.controlsEnabled(record)` 只排除 DISABLED/OFFLINE/READ_ONLY，不排除 PENDING；`LightCard` 滑杆改用 `.enabled(this.controlsEnabled())`，PENDING 中继续接收拖动。55ms `ThrottleGate` 与 TouchUp 终值语义未改；同动作幂等由 `DeviceViewModel.runSingle`/session 负责。测试：`T18_controlEnabled_allowsPendingButRejectsOfflineReadOnlyDisabled`、`T18_lightCardWiresPowerToggleAndKeepsPendingSliderLive`。 |

### 1.2 Medium

| ID | 处置 | 实现与证据 |
|---|---|---|
| **F-05** 离线设备仍可控制 | **Fixed** | 所有卡片控制（Light 电源/滑杆/颜色、Climate 电源/温度/模式、Door 锁/开）统一走 `UiMapping.controlsEnabled`；OFFLINE/READ_ONLY/DISABLED 禁用，状态文字仍保留。测试覆盖 OFFLINE/READ_ONLY/DISABLED/PENDING 四类。 |
| **F-06** D-12 白名单 | **Recorded（architect 裁定）** | 未静默放宽。当前真实依赖：① 页面 import `app/PageVmFactory`（T-18 seam，D-12 pages allowlist 未列）；② components 以值 import `viewmodel/core` 的 `ControlPhase`、`viewmodel/core/DoorConfirmationTracker` 的 `DoorLockState` 等纯枚举；③ `components/support/UiMapping` 为 C-24 预览构造 `AcViewState`/`DoorUiState` 并值 import `AcVocabulary/AcBrand/AcModeViewKind`；④ `import type` 读取 C-11/C-15 DTO。没有 components 调用 repository/transport/service 实现。建议 architect 增量修订 D-12（允许 `PageVmFactoryPort` 与 UI DTO/enum 的显式例外），或把 UI-facing 类型抽到 `model/**`；T-20 `check_layering.py` 按修订后规则落地。见 §3.1。 |
| **F-07** 配网 AP 列表/握手顺序 | **Fixed（additive seam）** | 新增 C-19 `IBleProvisioningClient.scanWifiAccessPoints(BleWifiScanRequest, listener, cancellation?)`：真实执行 permission→scan→connect→MTU/discovery→capability→Security1→identity，再返回 AP 列表；随后断链并清零 PoP。C-23 `BleProvisioningViewModel.prepareWifi(pop, expectedGatewayId?)` 在 Step2 “下一步”触发；Step3 显示真实 AP 列表；Step4 的 `submit` 仍是权威聚合流程。测试：`T18_C19_scanWifiAccessPointsHandshakesWithoutApplyingCredentials`、`T18_provisioningSeamsAndRecoveryAreWired`。**说明**：预览扫描与 `provision()` 各握手一次（为避免改动冻结聚合状态机的折中），已记录为代价/后续优化项。 |
| **F-08** 权限“去设置” | **Fixed** | `PermissionPort` 增加可选 `openSettings()`；`BleViewModelPermissionGate` 转发 `PermissionGate.openSettings()`；`BleProvisioningViewModel.openSettings()`；`ProvisioningPage` 在 DENIED/BLUETOOTH_OFF 时显示“设置”按钮。测试：source-level `T18_provisioningSeamsAndRecoveryAreWired`。 |
| **F-09** expectedGatewayId / RECONFIGURE | **Fixed（既有 C-19 能力接线）** | `ProvisioningPage` 读取 `params.expectedGatewayId`；ROTATE_SECRET/RECONFIGURE 缺失目标时拒绝进入向导；`BleProvisioningViewModel.submit(..., expectedGatewayId)` 将其写入 `BleProvisioningRequest.expectedGatewayId`，由 C-19 `IdentityNegotiator.negotiate(..., expectedGatewayId)` 校验；提示同时覆盖 ROTATE_SECRET/RECONFIGURE。测试：source-level + `T18_provisioningSeamsAndRecoveryAreWired`。 |
| **F-10** 门锁 UNVERIFIED 点亮四阶段 | **Fixed** | 新增纯选择器 `UiMapping.doorStageProgress(stage)`：WAITING_CONTACT/UNCONFIRMED/UNVERIFIED→3，SECURED/OPEN→4，FAILED/UNKNOWN→0；`DeviceControlPage` 改用该映射，不再把 UNVERIFIED/FAILED/UNKNOWN 显示为完成。测试：`T18_doorStageProgressNeverLightsSecuredWithoutEvidence`。 |

### 1.3 Low / Info

| ID | 处置 | 说明 |
|---|---|---|
| F-11 | **Fixed** | `ShellViews` NO_PROFILE 入口改用 `onboarding.join.title`，不再复用 `family.switch`；source-level 断言。 |
| F-12 | **Fixed** | `ProfilePage` 在 `family.phase === 'ERROR'` 显示 `ErrorState` + `family.error.i18nKey` + 重试。 |
| F-13 | **Fixed** | `PrimaryButton` 非全宽改为 `.width('auto')` + `.constraintSize({ minWidth: 168 })`，长英文可换行/扩展，不再固定 168vp。 |
| F-14 | **Fixed** | Light/Climate/Door 卡片统一使用 `AppMotionTokens.FADE_MS`（关闭动效时 0ms）；Climate/Door `motionEnabled` 显式 prop 接线；无散落 220 魔法数。 |
| F-15 | **Recorded** | `GlassSurface/IconButton/SliderControl` 仍未在页面使用；LightCard 保留原生 Slider 以不改变既有 55ms/TouchUp 逻辑。后续可把滑杆逻辑抽到 SliderControl 后替换。 |
| F-16 | **Fixed** | Home 家庭名点击传 `section: 'FAMILY'`；Rooms 的 `StatusBanner` 传 `showGateway: false`，不再显示误导性的“未绑定网关/云端未配置”。 |
| F-17 | **Partial** | 云测试成功/失败均显式呈现（成功使用 `errors.gateway.success`）；`effectiveProfile` 仍只显示持久 profile，因资源目录不在本次写范围且无专用 i18n 键，记录为待补键项。 |
| F-18 | **Fixed** | 新增 source-level/行为测试：LightCard toggle/PENDING、RBAC 入口隐藏、Scene 双门、Provisioning seams、低风险 UI 守卫、pages/components 分层守卫。 |
| F-19 | **Fixed** | `DoorCard.lockKey` 使用 `UiMapping.lockKeyFor`：UNKNOWN_INITIAL/UNKNOWN→`door.state.unknown`；门磁引导改为一次性（skip/成功配置后 dismissed，失败保留重试）。 |
| F-20 | **Fixed** | 取消后显示 `provisioning.error.cancelled` + 关闭按钮；`aboutToDisappear`/取消均清空 PoP/SSID/Wi-Fi 密码。 |
| F-21 | **Recorded** | 邀请 usedCount/maxUses、回执状态、转让候选过滤、GUEST→MEMBER 入口需 C-22 VM/API 与新增 i18n 键；本次未改资源目录。 |
| F-22/F-23 | **Info** | 旧 shell 颜色别名保留兼容；设备/视觉/动效/触感/读屏/BLE 真机仍 BLOCKED，未写成 PASS。 |

---

## 2. 新增/调整测试（672 → 685）

| 文件 | 新增用例 |
|---|---|
| `entry/src/test/host/DomainScene.test.mjs` | `T18_C11_sceneRunRbacMatrixAdminMemberGuestAndMissingPolicy` |
| `entry/src/test/host/DomainRoom.test.mjs` | `T18_C09_roomMutationsRequireAdminActorMatrix` |
| `entry/src/test/host/ViewModelScene.test.mjs` | `T18_SceneViewModel_capabilityAndRunRbacMatrix` |
| `entry/src/test/host/ViewModelRoom.test.mjs` | `T18_RoomViewModel_passesActiveMemberIdToServiceActorChecks` |
| `entry/src/test/host/BleService.test.mjs` | `T18_C19_scanWifiAccessPointsHandshakesWithoutApplyingCredentials` |
| `entry/src/test/host/UiPages.test.mjs` | `T18_controlEnabled_allowsPendingButRejectsOfflineReadOnlyDisabled`、`T18_doorStageProgressNeverLightsSecuredWithoutEvidence`、`T18_lightCardWiresPowerToggleAndKeepsPendingSliderLive`、`T18_nonAdminRoomPoolAndGatewayEntriesAreHidden`、`T18_scenePageAndServiceUseTheSameRbacGate`、`T18_provisioningSeamsAndRecoveryAreWired`、`T18_lowRiskUiGuards_sourceLevel`、`T18_pagesAndComponentsRespectLayeringGuards` |

矩阵覆盖：GUEST → `AUTH_RBAC_DENIED`；MEMBER/ADMIN → 允许场景执行；RoomService 的 ADMIN 允许、MEMBER/GUEST 拒绝；离线/只读/禁用控件禁用；PENDING 滑杆保持可用；UNVERIFIED/FAILED/UNKNOWN 不点亮第 4 阶段。

---

## 3. 验证（实际执行，cwd = 仓库根）

| # | 命令 | 结果 | 证据 |
|---|---|---|---|
| 1 | `ohpm install` | exit 0；`install completed in 0s 46ms` | `entry/src/test/evidence/t18-fix-ohpm-install.log` |
| 2 | `hvigorw clean assembleHap --no-daemon` | exit 0；**BUILD SUCCESSFUL in 14 s 541 ms**；0 ERROR | `entry/src/test/evidence/t18-fix-clean-assemble.log` |
| 3 | `codelinter -c code-linter.json5 -p default .` | exit 0；**Errors 0 / Warns 25 / Suggestions 0**（与修复前同量级，均为既有自定义组件性能建议） | `entry/src/test/evidence/t18-fix-codelinter.log` |
| 4 | `entry/src/test/run-host-tests.sh` | exit 0；**685/685 PASS**，fail 0 / skipped 0（新增 13 条） | `entry/src/test/evidence/t18-fix-host-tests.tap` |
| 5 | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | exit 0；**blockingFailures=0 / missingKeys=0**；warnings=139；hardcoded=82（新增 warning 来自 ROTATE_SECRET/RECONFIGURE 等技术枚举字符串，非用户文案） | `entry/src/test/evidence/t18-fix-i18n.log` |
| 附 | `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **BUILD SUCCESSFUL**（仅编译，未运行；设备仍 BLOCKED） | `entry/src/test/evidence/t18-fix-ohosTest-assemble.log` |

- i18n parity 未变：未新增/删除资源键、未改 zh/en 键值；base/dark 颜色与 base/en string parity 未触碰。
- Mock 排除未变：`AppCompositionRoot` 无 Mock import，`MockBleProvisioningClient.scanWifiAccessPoints` 仅为 C-20 测试实现。
- 权限最小集未变：`module.json5` 未修改；`openSettings` 只打开本应用设置页。
- T-17 DI 约定保持：生产 `pages/**`/`components/**` 无 `@Provide/@Consume`，页面不 `new` 服务/仓储/VM；新增依赖经显式 props/组合根注入。

---

## 4. 偏离、假设与残余风险

1. **D-12（F-06）仍需 architect 增量裁定**：见 §1.2；当前实现没有把 `PageVmFactory` 或 UI DTO 例外写入契约，T-20 前必须落文。报告仅记录实际依赖，不自行放宽。
2. **RoomService actor 省略约定**：`actorMemberId` 未提供时沿用 C-08 `FamilyService.requireAdmin` 的 v1 local-admin trust；生产 VM 始终传入 session memberId，UI 隐藏不是授权。该约定已在代码注释与测试中显式化。
3. **F-07 预览扫描的代价**：Step2/3 的真实握手/AP 扫描与 Step4 `submit` 的聚合流程各建一次 BLE 会话；功能/安全语义正确，但会多一次连接与 Security1。后续 C-23/C-19 若支持保留会话，可把两次合并。
4. **F-17 effective profile**：`GatewaySecurityView.effectiveProfile` 已存在，但缺少专用 i18n 标签键且资源目录不在本次写范围；当前仅显式化云测试成功/失败，effective profile 展示留待补键。
5. **F-21**：邀请 usedCount/回执、转让候选过滤、GUEST→MEMBER 入口依赖 C-22 VM/API 与新增键，未在本任务伪造。
6. **F-15**：`GlassSurface/IconButton/SliderControl` 仍未消费；保留组件与 LightCard 原生 Slider，避免在修复 High 时改变已验证的 55ms/TouchUp 交互。
7. **设备/视觉/动效/触感/读屏/BLE 真机**：仍 **BLOCKED**；本报告只证明构建、主机逻辑、源码守卫与 i18n 门禁。
8. **网关绑定服务层 RBAC**：Add gateway/配网入口已按 ADMIN 隐藏，`SettingsViewModel.probeManualAddress` 已加 ADMIN 守卫；`FamilyRepository.addGatewayToFamily` 仍无 actor 参数（C-08/C-22 上游），作为残余风险跟踪到 C-22/C-09/C-15 增量。

---

## 5. 变更文件

- 生产：`app/AppCompositionRoot.ets`、`app/AppContextAdapters.ets`、`app/PermissionGate.ets`、`components/{CommonControls,DeviceCards,DeviceGrid,StatusPanels}.ets`、`components/support/UiMapping.ets`、`pages/{DeviceControlPage,HomePage,ProfilePage,ProvisioningPage,RoomManagePage,RoomsPage,ScenePage,SettingsPage,ShellViews}.ets`、`service/ble/{BleProvisioningPorts,BleProvisioningService}.ets`、`service/mock/MockBleProvisioningClient.ets`、`service/room/RoomService.ets`、`service/scene/SceneService.ets`、`viewmodel/{BleProvisioningViewModel,RoomViewModel,SceneViewModel,SettingsViewModel,ViewModelPorts}.ets`。
- 测试：`entry/src/test/host/{BleService,DomainRoom,DomainScene,UiPages,ViewModelRoom,ViewModelScene,ViewModelSettings}.test.mjs`；`entry/src/test/evidence/t18-fix-*.log|tap`。
- 报告：本文件。

---

## 6. 约束核对

- 未修改 `entry/src/main/resources/**`、`entry/src/ohosTest/**`、`repository/**`、`module.json5`、`AppScope/**`、契约/计划/评审报告。
- 未切换分支、未 pull/merge/rebase/push；提交由本任务在 `task/wp-073-ui-pages` 上完成。
- 未改变错误码语义：新增拒绝统一使用既有 `AUTH_RBAC_DENIED`；未新增错误码或 i18n 键。
- `SceneService` 无授权端口时 fail-closed；`RoomService` 提供 actor 但无演员查询端口时 fail-closed。
