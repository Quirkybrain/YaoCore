# T-18 修复提交独立复审（F-01..F-23 关闭确认 / CQG-T18 意见）

- **Artifact ID**: T18-REVIEW-B
- **Producer**: agent:quality-reviewer
- **Task**: `wp-076-review-t18b`（Handoff `state/handoffs/wp-076-review-t18b.json`）
- **Role**: quality-reviewer（未参与 T-18 实现与修复）
- **Reviewed revision**: `a9d0bb5`（`fix(ui): 修复 T-18 评审发现`；父/评审基线 `7974305`）
- **Base branch**: `task/wp-073-ui-pages`（parent `feat/yaocore-app`）
- **Review scope**: `entry/src/main/ets/{pages,components,viewmodel,service,app}/**`、`entry/src/test/**`、`artifacts/50-implementation/t18-fix-report.md`；对 `7974305..a9d0bb5` 的 41 个变更路径逐项复核
- **Inputs**: 上轮 `artifacts/70-review/t18-review.md`、`t18-fix-report.md`、`t18-ui-pages.md`、DES-A/DES-B、contract-baseline、project-constraints、i18n-resource-design、test-plan、UIUX、T-17 裁定（SHA-256 与 handoff 冻结值一致）
- **Workflow**: STANDARD / GATED_AUTO
- **Date**: 2026-10-18
- **Verdict**: **PASS（代码级，条件式）** — 上轮 4 个 High 全部关闭；3 个新增 Medium（R2-01..R2-03）须在 IG-3 前关闭或由架构师书面接受
- **Status**: COMPLETE（代码级独立复审；设备/视觉/真实 BLE/LAN/云仍 **BLOCKED**，不作为 PASS 证据）

> **结论先行**：修复提交 `a9d0bb5` 对 F-01..F-04 四个 High 的代码修复经独立源码核对与复验成立：LightCard 电源回调已接线、GUEST 场景在 VM 与服务层双重 fail-closed、房间/未分配池/场景服务层 RBAC 矩阵通过、PENDING 滑杆不再被禁用。F-05/F-07/F-08/F-09/F-10 及 F-11/F-12/F-13/F-14/F-16/F-18/F-19/F-20 基本关闭，F-06/F-15/F-17/F-21/F-22/F-23 按报告记录。构建、lint、host 685/685、i18n 门禁、ohosTest 编译均可复现通过。但本轮发现 3 个新的 Medium：**Settings 的“重新配网”入口对非 ADMIN 仍可点击**（网关管理 RBAC 未完全闭合，R2-01）；**配网向导在 busy 时禁用了“取消”按钮**，与 DES-B §16.3(1)“取消随时可用”冲突（R2-02）；**C-09/C-19/C-23 的公共方法/端口签名扩展未在 DES-B/DES-A 做增量登记或 Change Impact**（R2-03）。这三项不否定 High 修复，但应在 IG-3 前关闭或书面接受，因此 CQG-T18 只能给出条件式 PASS；设备矩阵仍 BLOCKED，IG-3 **NOT READY**。

---

## 1. 范围、revision 与过程核对

| 项 | 结果 | 证据 |
|---|---|---|
| Review base / HEAD | base `a9d0bb5`（父 `7974305`）；工作树干净 | `git rev-parse HEAD`、`git status --short`（无输出） |
| 修复提交 | `a9d0bb5 fix(ui): 修复 T-18 评审发现`；单提交，subject 符合格式 | `git log --format='%h %s' 7974305..a9d0bb5` |
| 变更范围 | 41 个路径：27 生产 `.ets`、7 host 测试、6 evidence、1 修复报告 | `git diff --name-status 7974305..a9d0bb5` |
| 越界修改 | 未发现 `repository/**`（除 DTO 消费）、`entry/src/main/resources/**`、`entry/src/ohosTest/**`、`module.json5`、`AppScope/**`、契约/计划/旧评审报告改动 | `git diff --stat`/路径核对 |
| 手写输入完整性 | 上轮评审、修复报告、实现报告 SHA-256 与 handoff 一致；未修改 `input/`/契约/旧报告 | `sha256sum` + handoff |
| 作者独立性 | 本评审未参与实现/修复；未编辑被审代码；唯一写入为本报告 | 本文件为唯一变更；`git diff` 仅本报告 |
| 评审限制 | 无设备/模拟器/Previewer/签名；无法执行 ArkUI 渲染、视觉、动效、触感、读屏、真实 BLE/LAN/云 | `COMPILED_ONLY` 与 `BLOCKED` 均不按 PASS 处理 |

---

## 2. 独立复验结果（cwd = 仓库根）

| # | 命令 | 本次结果 | 与修复报告的一致性 |
|---|---|---|---|
| 1 | `entry/src/test/run-host-tests.sh` | **685/685 PASS**，fail 0 / skipped 0；exit 0 | 一致（672 既有 + 13 新增） |
| 2 | `codelinter -c code-linter.json5 -p default .` | **Errors 0 / Warns 25 / Suggestions 0**；exit 0 | 一致 |
| 3 | `hvigorw clean assembleHap --no-daemon` | **BUILD SUCCESSFUL in 15 s 752 ms**；0 ERROR | 一致（耗时因缓存不同） |
| 4 | `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **BUILD SUCCESSFUL in 13 s 306 ms**（仅编译，未运行） | 一致（COMPILED_ONLY） |
| 5 | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | **blockingFailures=0 / missingKeys=0**；warnings 139；hardcoded 82 | 一致；新增 warning 均为技术枚举/既有项，非用户文案 |
| 6 | rawfile parity | zh-CN **543**、en-US **545**；en 仅多 `device.count_one/_other` 复数变体；基键对齐 | 支持“未改资源键/无回归” |
| 7 | base/dark color、base/en string | color **44/44**、string **53/53**，名称集合一致 | 支持 parity 声明 |
| 8 | Mock/DI/分层静态扫描 | `AppCompositionRoot` 无 Mock import；生产 `pages/**`/`components/**` 无 `@Provide`/`@Consume`；页面无 `new` 服务/仓储/VM | 支持报告 §3 声明（D-12 例外见 F-06/R2-03） |
| 9 | 提交/证据 | 41 路径与 handoff 一致；evidence 日志为测试证据；无秘密/HAP/构建目录 | 无范围外提交 |

> 复验通过只证明构建、主机逻辑、源码守卫与 i18n 检查；不证明 ArkUI 页面行为、真实 BLE 或视觉。以下结论均来自源码与运行证据。

---

## 3. F-01..F-23 关闭状态表

> 状态：**Closed** = 上轮 finding 的核心问题已修复并有代码/测试证据；**Partial** = 部分修复并如实记录；**Recorded** = 已按要求记录、由架构/后续任务承接；**Info** = 跟踪项。

| ID | 上轮严重度 | 本轮状态 | 证据与说明 |
|---|---|---|---|
| **F-01** LightCard toggle | High | **Closed** | `components/DeviceCards.ets:79-90` 新增 44vp 电源 Button，调用 `this.onToggle()`；`DeviceGrid.ets:48-62` 与 `DeviceControlPage.ets:259-273` 的 `onToggle` 接线可达；host `T18_lightCardWiresPowerToggleAndKeepsPendingSliderLive` 断言源码。 |
| **F-02** GUEST 场景 fail-closed | High | **Closed** | `service/scene/SceneService.ets:153,250-262` 在 `run()` 最前调用 `authorizeExecution()`；无授权端口或 deny 均抛 `AUTH_RBAC_DENIED`；`app/AppContextAdapters.ets:69-87` 用 `AuthService.getActiveSession()+canExecuteScene`；`SceneViewModel.canExecuteScene()`/`ScenePage` 禁用 Run 并显示 `errors.app.auth_rbac_denied`；host 服务矩阵 + VM 矩阵 + source-level 三组测试。 |
| **F-03** 房间/池/网关 RBAC | High | **Closed（原列项）＋ R2-01** | `RoomService` 8 个变更方法均加 `actorMemberId?` + `RoomActorLookupPort` + `FamilyRbac.requireAdmin`；`RoomViewModel` 传 active memberId；`RoomsPage`/`RoomManagePage` 隐藏 Add/Edit/Delete/Assign；`HomePage`/`ProfilePage` 隐藏配网入口；`SettingsPage` 隐藏 ADVANCED，`probeManualAddress` 加 ADMIN 守卫；`T18_C09_roomMutationsRequireAdminActorMatrix` 覆盖 ADMIN 允许、MEMBER/GUEST 拒绝。**残余**：Settings SECURITY 的“重新配网”按钮未套 `isAdmin()`，见 R2-01。 |
| **F-04** PENDING 滑杆 | High | **Closed** | `UiMapping.controlsEnabled()` 只排除 DISABLED/OFFLINE/READ_ONLY；`LightCard` 滑杆改为 `.enabled(this.controlsEnabled())`，PENDING 继续接收拖动；`DeviceViewModel`/`ThrottleGate`/TouchUp 未改动；host 断言 PENDING 可用且源码不再出现旧表达式。 |
| **F-05** 离线仍可控制 | Medium | **Closed** | Light/Climate/Door 的电源、滑杆、模式、锁/开均改用 `controlsEnabled()`；OFFLINE/READ_ONLY/DISABLED 禁用，状态文字保留；`T18_controlEnabled_*` 覆盖四类。 |
| **F-06** D-12 白名单 | Medium | **Recorded**（architect 待裁定） | 修复报告 §1.2/§4.1 记录 `PageVmFactory`、components→`viewmodel/core`/`service/ac` 值 import、`import type` DTO 等真实依赖；未静默放宽；需 solution-architect 增量修订 D-12 或抽 `model/**`；T-20 `check_layering.py` 依赖。 |
| **F-07** 配网 AP/握手顺序 | Medium | **Closed（功能）＋ R2-03** | `IBleProvisioningClient.scanWifiAccessPoints` + `BleWifiScanRequest` 实现真实 permission→scan→connect→capability→Security1→identity→AP 扫描，后断链/清零 PoP；`BleProvisioningViewModel.prepareWifi` 在 Step2 触发；`ProvisioningPage` Step3 渲染真实 `accessPoints`；host `T18_C19_scanWifiAccessPoints...` 断言不应用凭据。代价：预览与 `provision()` 各握手一次（报告已记录）。契约登记见 R2-03。 |
| **F-08** 权限“去设置” | Medium | **Closed（Step0）＋ R2-05** | `PermissionPort.openSettings?`、`BleViewModelPermissionGate.openSettings`、`BleProvisioningViewModel.openSettings`、`ProvisioningPage` Step0 DENIED/BLUETOOTH_OFF 按钮接通。**残余**：`prepareWifi`/`submit` 内 `ensureReady` 失败时 VM 不更新 `permission`，页面不在 Step0 时无“设置”CTA（R2-05，Low）。 |
| **F-09** expectedGatewayId | Medium | **Closed** | `ProvisioningPage.aboutToAppear` 对 ROTATE_SECRET/RECONFIGURE 缺 `expectedGatewayId` 直接 `blocked`；Step2 预览与 Step4 `submit` 均传 expected id；`IdentityNegotiator.checkExpected` 执行绑定前校验；Settings ROTATE/RECONFIGURE push 均带 id；source-level 测试。 |
| **F-10** 门锁 UNVERIFIED 进度 | Medium | **Closed** | `UiMapping.doorStageProgress`：UNVERIFIED/UNCONFIRMED/WAITING_CONTACT→3，SECURED/OPEN→4，FAILED/UNKNOWN→0；`DeviceControlPage.stageIndex()` 改用该纯选择器；`T18_doorStageProgressNeverLightsSecuredWithoutEvidence` 覆盖。 |
| **F-11** onboarding join 键 | Low | **Closed** | `ShellViews.ets:98` 改用 `onboarding.join.title`（zh“加入家庭”/en“Join a family”）；source-level 断言不再使用 `family.switch`。 |
| **F-12** Profile ERROR | Low | **Closed** | `ProfilePage.ets:180-193` 在 `family.phase === 'ERROR'` 渲染 `ErrorState` + `family.error.i18nKey`/`common.refresh_failed` + 重试。 |
| **F-13** 固定按钮宽度 | Low | **Closed（设备待验）** | `PrimaryButton` 非全宽改为 `.width('auto')` + `.constraintSize({ minWidth: 168 })`；长英文可扩展/换行。`width('auto')` 的实际布局需 T-19 设备/长文本抽查（R2-06）。 |
| **F-14** 动效 token | Low | **Closed（小残留）** | Light/Climate/Door 统一 `AppMotionTokens.FADE_MS`，`motionEnabled` 接线；无 `220` 魔法数。`MainShell.ets:22` 仍保留未使用的 `AppMotionTokens` import（R2-06，Info）。 |
| **F-15** 未消费组件 | Low | **Recorded** | `GlassSurface/IconButton/SliderControl` 仍未消费；LightCard 保留原生 Slider 以不改 55ms/TouchUp；报告如实记录。 |
| **F-16** Home/Rooms 语义 | Low | **Closed** | Home 家庭名点击传 `section:'FAMILY'`；FamilyManagePage 消费并 `setSection(FAMILY)`；Rooms StatusBanner `showGateway:false`，不再显示误导性的未绑定网关/云端状态。 |
| **F-17** 云测试/effective profile | Low | **Partial（记录）** | Settings 云测试成功/失败均显式呈现（`errors.gateway.success` / 错误键）；`effectiveProfile` 仍未展示，报告以缺专用 i18n 键记录待补。 |
| **F-18** 测试守卫 | Low | **Closed** | 新增 13 条 host：LightCard toggle/PENDING、GUEST/MEMBER/ADMIN 场景矩阵、RoomService 矩阵、离线控制、Door 阶段/文案、D-12/RBAC source-level 守卫；672 既有用例保留（总 685）。设备骨架仍 COMPILED_ONLY。 |
| **F-19** 门锁文案/一次性引导 | Low | **Closed＋R2-04** | `UiMapping.lockKeyFor`：UNKNOWN_INITIAL/UNKNOWN→`door.state.unknown`，不再误用“门磁未验证”；引导 dismissed 状态在 skip/成功后生效。**副作用**：页面级“关联门磁”显式按钮在 skip 后无响应（R2-04，Low）。 |
| **F-20** 取消清理/取消态 | Low | **Closed＋R2-02** | 取消后显示 `provisioning.error.cancelled` + 关闭；`aboutToDisappear`/取消清空 PoP/SSID/Wi-Fi 密码；VM `cancel/destroyDrafts` 保持。**新回归**：按钮在 `busy` 时被禁用，违反“取消随时可用”（R2-02，Medium）。 |
| **F-21** 邀请/转让/角色 | Low | **Recorded** | usedCount/maxUses、回执状态、转让候选过滤、GUEST→MEMBER 入口依赖 C-22 VM/API 与新 i18n 键；本次未伪造。 |
| **F-22** 颜色别名 | Info | **Recorded** | 旧 shell `shell_*` 与新 `AppColors` 并存；未造成功能错误，后续收敛或保留兼容 facade。 |
| **F-23** 设备/视觉 BLOCKED | Info | **Recorded** | 设备/视觉/动效/触感/读屏/BLE 真机、QR/ScanKit、SceneEditSheet、通知系统状态等仍 BLOCKED/DEFERRED；不得写成 PASS。 |

---

## 4. 新发现（R2-xx）

| ID | 严重度 | 位置 | 证据与影响 | 建议/归属 |
|---|---|---|---|---|
| **R2-01** | **Medium** | `pages/SettingsPage.ets:435-457`（SECURITY 区“重新配网”）；`repository/FamilyRepository.ets:284-307` | `ROTATE_SECRET` 按钮有 `.enabled(this.isAdmin())`，但同一 SecuritySection 的 `RECONFIGURE`（P_BLOCKED“重新配网”）按钮没有 ADMIN 门；SECURITY section 本身对所有角色可见。MEMBER/GUEST 可在近场 BLE + PoP 条件下进入 `RECONFIGURE` 向导，执行网关重配/绑定；`FamilyRepository.addGatewayToFamily` 仍无 actor/RBAC（修复报告 §4 第 8 条已记录）。这违反 DES-B §15.3(1)/§16.1.3（MEMBER 不可网关/密钥管理），是 F-03“网关管理 ADMIN 门”的残余。 | 立即给该按钮加 `.enabled(this.isAdmin())`（并补 source-level 测试），或由 architect 书面接受并跟踪到 C-22/C-09/C-15；`implementation-engineer` + `solution-architect`。 |
| **R2-02** | **Medium** | `pages/ProvisioningPage.ets:612` | 修复把取消按钮改为 `.enabled((canCancel \|\| localStep<5) && !this.busy)`。`prepareWifi`/`submit` 期间 `busy=true`，用户在 10s 扫描、Security1/AP 扫描、Wi-Fi 等待期间无法点击“取消”；DES-B §16.3(1) 明确“取消随时可用”，F-20 也要求任意失败/取消清理。系统返回键仍可触发 `aboutToDisappear→dispose→cancel`，但页面显式取消入口被禁用，属于新回归。 | 移除 `!this.busy`（或仅在不可取消状态禁用并在 UI 说明）；确保 `cancel()` 与 `submit/prepareWifi` 的竞态由 VM 的 `cancelled/generation` 保护；补 source-level/设备测试。 |
| **R2-03** | **Medium（契约/流程）** | `service/room/RoomService.ets`（8 个方法 + 构造器）、`service/ble/BleProvisioningPorts.ets`（`IBleProvisioningClient.scanWifiAccessPoints`、`BleWifiScanRequest`）、`viewmodel/BleProvisioningViewModel.ets`（`submit` 第 5 参数、`prepareWifi`）、`viewmodel/ViewModelPorts.ets`（`PermissionPort.openSettings?`）、`SceneService`/`SceneViewModel`/`RoomViewModel` 构造器 | 修复新增/扩展了 DES-B §4.1.3、§16.1.2 与 DES-A §16.1 的公共签名：`RoomService.*(…, actorMemberId?)`、`IBleProvisioningClient` 新方法、`submit(..., expectedGatewayId?)`、`PermissionPort.openSettings?`。DES-A §27.3 允许“新增方法”，但 DES-B 接口变更须更新共享类型边界并在 G-007/§23 登记；“修改端口方法签名”须走 Change Impact。当前只有修复报告记录，DES-A/DES-B 未登记 `EXT-*`，T-20 契约/分层检查可能无法追溯。不是运行时缺陷，但属于契约闭环缺口。 | `solution-architect` 在 DES-B §4.1.3/§16.1.2/§23 与 DES-A §27.4 登记增量（或明确将这些签名变更作为 T-18 受控例外），并触发 C-09/C-19/C-23 的 Change Impact；T-20 检查器按登记实现。 |
| **R2-04** | **Low** | `pages/DeviceControlPage.ets:204-212,386-391`；`components/DeviceCards.ets:403-411` | `doorGuideDismissed` 在 skip 后置 true，`onConfigureLink` 因此不再打开引导；但 `DoorCard` 的“关联门磁”按钮仍可见，点击无任何效果（死按钮）。F-19 的“一次性”应针对自动弹窗，不应让显式入口失效。 | 显式按钮点击时重置 `doorGuideVisible`/`doorGuideDismissed`（或隐藏按钮）；补 source-level/设备测试。 |
| **R2-05** | **Low** | `viewmodel/BleProvisioningViewModel.ets:186-195,520-525`；`pages/ProvisioningPage.ets:308-322` | F-08 的“设置”按钮只在 `view.permission === DENIED/BLUETOOTH_OFF` 且 Step0 渲染；`prepareWifi`/`submit` 内 `BleProvisioningService.ensureReady()` 失败时 `handleProvisionFailure` 只发布 FAILED，不把 `permission` 置为 DENIED/BLUETOOTH_OFF，页面停留在 Step2/4 时无“设置”CTA，用户只能退回。 | 在 `handleProvisionFailure` 中按 `PROVISIONING_PERMISSION_DENIED/BLUETOOTH_OFF` 更新 permission，或把 CTA 放到通用错误区；T-19 设备验证。 |
| **R2-06** | Low/Info | `pages/MainShell.ets:22`；`components/CommonControls.ets:89-90` | F-14 的未使用 `AppMotionTokens` import 未清理；`width('auto')`/`minWidth` 的实际布局与长英文换行尚无设备证据。 | 清理 import；T-19 做 en-US 长标签/安全区/小屏抽查。 |
| **R2-07** | Info | `service/room/RoomService.ets:274-286`；`repository/FamilyRepository.ets:284-307`；`service/scene/SceneService.ets:153` | RoomService 在 `actorMemberId` 缺省时沿用 v1 local-admin trust（与 FamilyService 一致，报告已记录）；`addGatewayToFamily` 无 RBAC；SceneService.run 无 familyId/room 上下文（GUEST 已全局 deny，MEMBER/ADMIN 仅按 active session 放行）。均为已声明/上游残余，不是本次修复引入。 | 跟踪到 C-22/C-09/C-15/C-12；IG-3 前专项评估。 |
| **R2-08** | Info | `artifacts/50-implementation/t18-fix-report.md:32` | §1.2 写“见 §3.1”，但修复报告没有 §3.1（只有 §3 验证）；文档引用失效。 | 修正引用或补节；不阻断。 |

---

## 5. CQG-T18 对照与最终意见

| 检查 | 结果 | 证据/说明 |
|---|---|---|
| 构建（生产图） | ✅ **PASS** | `clean assembleHap` BUILD SUCCESSFUL 15 s 752 ms，0 ERROR |
| 静态检查 | ✅ **PASS** | codelinter 0 error / 25 warn / 0 suggestion（与修复前同量级） |
| Host 测试 | ✅ **PASS** | **685/685**，fail/skipped 0；672 既有 + 13 新增 |
| i18n / parity | ✅ **PASS** | `--strict-ui` blocking 0 / missing 0；zh 543 / en 545（仅复数变体）；color 44/44；string 53/53 |
| 契约 | ⚠️ **条件式** | F-01..F-05/F-07..F-20 关闭或如实记录；F-06 D-12 已记录待 architect；R2-03 公共签名/端口扩展未登记到 DES-A/DES-B，需 Change Impact |
| 安全 | ⚠️ **条件式** | GUEST 场景服务层 fail-closed、房间/池服务层 RBAC、离线控制禁用成立；R2-01 网关“重新配网”入口仍可被非 ADMIN 触发；`addGatewayToFamily` 无 RBAC（已记录） |
| RBAC | ⚠️ **条件式** | 场景矩阵 ADMIN/MEMBER allow、GUEST deny；RoomService ADMIN allow、MEMBER/GUEST deny；R2-01 为网关管理残余 |
| 分层/DI | ✅ **PASS（有记录项）** | 无 `@Provide/@Consume`；页面无 `new` 服务/仓储/VM；Mock 生产排除；D-12 例外已由 F-06 记录，T-20 检查器待落地 |
| 独立评审 | ✅ **本轮完成** | 本报告为未参与实现/修复的 quality-reviewer 第二轮独立复审；非作者自审 |
| 设备/视觉 | ⚠️ **BLOCKED** | 无设备/模拟器/Previewer/签名；ohosTest 仅 COMPILED_ONLY；真实 BLE/权限弹窗/AP/绑定探针/LAN/云/TLS 未验证 |
| IG-3 | ❌ **NOT READY** | 设备矩阵未执行；R2-01/R2-02/R2-03 未关闭/未书面接受；F-06/D-12、F-15/F-17/F-21、C-22 网关服务层 RBAC 仍跟踪 |

### CQG-T18 最终意见

**PASS（代码级，条件式）**：`a9d0bb5` 对 T-18 上轮 4 个 High 的修复成立，构建/lint/host/i18n/契约主体/安全主体/分层/独立评审证据可复现；C-24..C-27 可进入代码级 STABLE（条件式）。条件如下：

1. **R2-01（Medium）**：在 IG-3 前隐藏/禁用 Settings 的 `RECONFIGURE` 入口给非 ADMIN（或 architect 书面接受并登记 C-22/C-09/C-15）。
2. **R2-02（Medium）**：恢复“取消随时可用”（移除 `busy` 对取消按钮的禁用，或给出等价可取消路径并补测试）。
3. **R2-03（Medium，契约）**：由 `solution-architect` 登记 C-09/C-19/C-23 的增量签名/端口并完成 Change Impact；T-20 按登记实现检查器。
4. R2-04/R2-05 在 T-19/后续修复；R2-06..R2-08 记录即可。
5. 设备/视觉/真实 BLE/LAN/云仍 **BLOCKED**；不得把 CQG-T18 写成设备 PASS，也不得写成 IG-3 PASS。

> 若 Orchestrator 的 CQG 口径要求“无未决 Medium”，则本轮应记为 **CHANGES_REQUIRED**；本评审基于项目既有“代码级条件式 PASS + 跟踪项”口径给出上述建议。最终 Gate 决定由 Orchestrator/Stage Gate 记录，本报告不授予 Stage 或用户验收。

---

## 6. 残余风险与跟踪

| 项 | 状态 | 归属 |
|---|---|---|
| R2-01 网关 reprovision 非 ADMIN 入口 | **未关闭（Medium）** | C-22/C-09/C-15 + `solution-architect`/`implementation-engineer` |
| R2-02 配网 busy 时取消不可用 | **未关闭（Medium）** | `implementation-engineer`；T-19 设备验证 |
| R2-03 C-09/C-19/C-23 签名/端口登记 | **未关闭（Medium，契约）** | `solution-architect`；T-20 检查器 |
| R2-04 门磁显式入口 skip 后死按钮 | **未关闭（Low）** | T-19/后续修复 |
| R2-05 中途权限失败无“设置”CTA | **未关闭（Low）** | `implementation-engineer`；T-19 |
| F-06 D-12/D-17 与 C-24 props 类型归属 | **Recorded，待 architect** | `solution-architect`；T-20 `check_layering.py` |
| F-15 未消费组件、F-17 effective profile、F-21 邀请字段/转让过滤 | **Recorded/Partial** | T-19/T-20 或后续任务 |
| `addGatewayToFamily` 无 actor/RBAC、RoomService 缺省 actor 的 v1 trust | **Recorded（Info）** | C-22/C-09/C-15 |
| GUEST 设备级 `allowedRoomIds`、SceneService 无 family/room 上下文 | **Upstream/Residual** | C-12/C-21；IG-3 前专项评估 |
| 设备/视觉/动效/触感/读屏/长英文/安全区 | **BLOCKED** | T-19 |
| 真实 BLE/权限弹窗/扫描/绑定探针/LAN/云/TLS | **BLOCKED** | T-19；用户实机（CP-03） |
| F-22 旧 shell 颜色别名 | **Info** | 后续收敛或兼容 facade |

**IG-3**：**NOT READY**。前置：T-19 设备矩阵（F-01 toggle、F-04 PENDING、F-05 离线、F-10 门锁阶段、F-13/F-14 视觉/动效、F-08/F-20 配网取消/权限/AP）；R2-01..R2-03 关闭/接受；F-06 D-12 裁定；C-22 网关服务层 RBAC 专项。**T-20**：把 D-12 分层、RBAC 静态检查、i18n 硬编码/parity、契约签名登记纳入正式门禁。

---

## 7. 独立声明与裁决边界

1. 本复审由 `quality-reviewer` 独立完成；未参与 T-18 实现或 `wp-075-fix-t18` 修复，未编辑任何被审代码/测试/契约；本任务唯一写入为 `artifacts/70-review/t18-review-b.md`。
2. 评审基于 `a9d0bb5`（父 `7974305`）与 handoff 冻结输入；输入 SHA-256 与 handoff 一致；未对 `input/`、DES-A/DES-B、contract-baseline、test-plan 或旧评审报告做修改。
3. 复验命令均在本机实际执行：host 685/685、codelinter 0 error、clean assembleHap BUILD SUCCESSFUL、ohosTest 编译 BUILD SUCCESSFUL、i18n 0 blocking；未把 `COMPILED_ONLY`/`BLOCKED` 写成 PASS。
4. **Verdict 仅覆盖本报告 §1 的 revision 与范围**：PASS（代码级，条件式）；条件 R2-01..R2-03 未关闭前不得宣告 IG-3 或设备 PASS；不授予 Stage Gate 或用户验收。
5. 未发现作者自审替代；未发现越界产品代码改动；未发现秘密/构建产物入库；未发现 672 既有 host 用例被删除或弱化。

---

## 8. Next action

1. **R2-01**：`SettingsPage` 的 `RECONFIGURE` 按钮加 `isAdmin()` 门（或 architect 接受并跟踪）。
2. **R2-02**：恢复配网向导“取消随时可用”，确认 `cancel` 与 `prepareWifi/submit` 竞态由 VM generation/cancelled 保护。
3. **R2-03**：派发 `solution-architect` 登记 C-09/C-19/C-23 增量签名/端口与 Change Impact；T-20 更新检查器。
4. **R2-04/R2-05**：T-19 或后续修复；补 source-level/设备测试。
5. 复跑 `run-host-tests.sh`、`codelinter`、`clean assembleHap`、ohosTest 编译、`check_i18n --strict-ui` 后，按 Orchestrator 口径记录 CQG-T18；T-19 设备矩阵完成后才评估 IG-3。

```text
STATUS: COMPLETE
SUMMARY: 复审 a9d0bb5；F-01..F-04 High 全部关闭；F-05..F-20 关闭/记录；新增 R2-01..R2-03 Medium（网关 reprovision ADMIN 门、配网 busy 取消不可用、C-09/C-19/C-23 签名未登记）
ARTIFACTS_CREATED: artifacts/70-review/t18-review-b.md
ARTIFACTS_UPDATED: artifacts/70-review/t18-review-b.md（占位覆写）
RISKS: R2-01/R2-02/R2-03 未关闭；F-06 D-12 待 architect；设备/真实 BLE/LAN/云 BLOCKED
VALIDATION: host 685/685；codelinter 0 error/25 warn；clean assembleHap SUCCESS；ohosTest 编译 SUCCESS；i18n blocking=0/missing=0
NEEDS_CLARIFICATION: no（R2-01..R2-03 已列明归属与条件）
NEXT_ACTION: 关闭/接受 R2-01..R2-03 后记录 CQG-T18；T-19 执行设备矩阵再评估 IG-3
```
