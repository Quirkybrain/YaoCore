# T-18 R2 聚焦复审报告（R2 关闭确认 / CQG-T18 最终意见）

- **Artifact ID**: T18-REVIEW-C
- **Producer**: agent:quality-reviewer
- **Task**: `wp-079-review-t18c`（Handoff `state/handoffs/wp-079-review-t18c.json`）
- **Role**: quality-reviewer（未参与 T-18 实现，也未参与 `wp-075-fix-t18` / `wp-077-fix-t18b` 修复）
- **Reviewed revision**: `4b99e64`（`docs(design): 登记 T-18 增量契约与 D-12 修订`；R2 代码修复 `f6e9c9b` / `74e9157`；父提交 `6737303`；上一轮复审基线 `8f3d969`）
- **Base branch**: `task/wp-073-ui-pages`（parent `feat/yaocore-app`）
- **Review scope**: `entry/src/main/ets/{pages,components}/**`、`entry/src/test/**`、DES-A §0.7/§27.5、DES-B §0.9/§23.7、`artifacts/50-implementation/t18-fix2-report.md`；逐项核对 `8f3d969..4b99e64` 的 10 个变更路径
- **Inputs**: `artifacts/70-review/t18-review-b.md`、`artifacts/50-implementation/t18-fix2-report.md`、DES-A、DES-B、`contract-baseline.md`、`test-plan.md`；SHA-256 与 handoff 冻结值一致
- **Workflow**: STANDARD / GATED_AUTO
- **Date**: 2026-10-18
- **Verdict**: **PASS（代码级，条件式）** — R2-01、R2-02（主缺陷）、R2-03、R2-04、R2-05 与 F-06 的登记/修复关闭；新增 **R3-02（Medium，取消与 `submit`/`commitResult` 竞态）** 须在 IG-3 前关闭或由 Stage Gate 书面接受；设备/视觉/真实 BLE/LAN/云仍 **BLOCKED**；**IG-3 NOT READY**
- **Status**: COMPLETE（代码级独立复审；未把 `COMPILED_ONLY` / `BLOCKED` 写成 PASS）

> **结论先行**：R2-01 的 Settings `RECONFIGURE` 已与 `ROTATE_SECRET` 一样受 `isAdmin()` 门控，并有矩阵测试；R2-02 的取消按钮已移除 `!this.busy`，取消路径清理秘密、定时器、扫描与 BLE，并有 host 测试；R2-04 的显式“关联门磁”入口在 skip 后可重新打开引导，且引导打开时隐藏重复入口；R2-05 在页面层映射权限/BLE 错误并提供“去设置”CTA；R2-03 的 `EXT-DES-B-28..32` 已登记且与代码实际签名逐项一致，`GAP-T18-01`/`TRUST-T18-01` 已记录；F-06 的 D-12 文件/符号级白名单已覆盖 T-18 新增 import。构建、lint、host **690/690**、ohosTest 编译、i18n 门禁均可复现通过。仍有两项不得忽略：**R3-02**（`cancel()` 未在 VM 层阻止晚到的 `submit` 成功提交绑定；页面 `cancelled` 只遮挡 UI）与 **GAP-T18-01**（`addGatewayToFamily` 无服务层 actor/RBAC）。因此 CQG-T18 只能给出代码级条件式 PASS，设备矩阵与 IG-3 仍不满足。

---

## 1. 范围、revision 与过程核对

| 项 | 结果 | 证据 |
|---|---|---|
| Review base / HEAD | base `8f3d969`（上轮复审）；当前 HEAD `4b99e64`；工作树干净 | `git rev-parse HEAD`、`git status --short --branch`（无文件变更） |
| 变更范围 | 10 个路径：4 个 `pages/*.ets`、1 个 `components/*.ets`、2 个 host 测试、1 个修复报告、DES-A/DES-B | `git diff --name-status 8f3d969..HEAD` |
| 提交 | `f6e9c9b`（R2 修复）、`74e9157`（门磁重复入口）、`4b99e64`（契约登记/D-12） | `git log --format='%h %s' -3` |
| 越界修改 | 未发现 `entry/src/main/resources/**`、`entry/src/ohosTest/**`、`module.json5`、`AppScope/**`、`repository/**`、`viewmodel/**`、`service/**` 的改动 | `git diff --stat 8f3d969..HEAD` + 路径核对 |
| 输入完整性 | 上轮复审、修复报告、DES-A、DES-B、contract-baseline、test-plan 的 SHA-256 与 handoff 一致 | `sha256sum` 对照 handoff |
| 作者独立性 | 本评审未参与实现/修复；未编辑被审代码、测试或契约；唯一写入为本报告 | 本文件为唯一变更；`git diff` 仅本报告 |
| 评审限制 | 无设备/模拟器/Previewer/签名；无法执行 ArkUI 渲染、视觉、动效、读屏、真实 BLE/LAN/云 | `COMPILED_ONLY` 与 `BLOCKED` 不按 PASS 处理 |

> `contract-baseline.md` 的线格式/HMAC/错误码基线与 `test-plan.md` 的 T-19/T-20 下游项未被本次 UI/契约增量修改；本报告不将其作为 R2 阻塞项，但保留其作为 T-19/T-20 的权威输入。

---

## 2. 独立复验结果（cwd = 仓库根）

| # | 命令 | 本次结果 | 与修复报告的一致性 |
|---|---|---|---|
| 1 | `entry/src/test/run-host-tests.sh` | **690/690 PASS**；fail 0 / skipped 0；exit 0 | 一致；既有 685 条全部保留（`git grep` 计数：base 685 / HEAD 690） |
| 2 | `codelinter -c code-linter.json5 -p default .` | **Defects 25 / Errors 0 / Warns 25 / Suggestions 0**；exit 0 | 一致 |
| 3 | `hvigorw clean assembleHap --no-daemon` | **BUILD SUCCESSFUL in 14 s 632 ms**；0 ERROR | 一致（耗时因缓存不同） |
| 4 | `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **BUILD SUCCESSFUL in 13 s 75 ms**（仅编译，未运行） | 一致（COMPILED_ONLY） |
| 5 | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | **blockingFailures=0 / missingKeys=0**；warnings 139；hardcoded 82 | 一致；新增代码未改变计数 |
| 6 | i18n rawfile parity | zh-CN **543** / en-US **545**；en 仅多 `device.count_one/_other` 复数变体；基键集合无缺失 | 无资源键变更/无回归 |
| 7 | color / string parity | color **44/44**、string **53/53**，名称集合一致 | 无资源回归 |
| 8 | Mock/DI/分层静态扫描 | 生产 `AppCompositionRoot` 无 Mock import；`pages/**`/`components/**` 无 `@Provide/@Consume`；页面无 `new` 服务/仓储/VM（`Index.ets` 的 `new NavigationService` 属 app UI seam） | 支持 F-06/D-12 与 DI 检查 |
| 9 | 测试保留 | `git diff 8f3d969..HEAD -- entry/src/test/host` 仅新增 5 条 R2 测试与一处测试 setup 行替换；无测试删除/弱化 | 支持“685 既有用例保留” |
| 10 | 依赖/资源/构建产物 | 无资源、ohosTest、module、AppScope、HAP/秘密入库 | 无范围外提交 |

> 复验通过只证明构建、主机逻辑、源码守卫与 i18n 检查；不证明 ArkUI 页面行为、真实 BLE 或视觉。以下结论均来自源码与运行证据。

---

## 3. R2 关闭状态表

> 状态定义：**Closed** = 原 finding 的核心问题已修复并有代码/测试证据；**Closed（主缺陷）** = 用户可见主问题关闭，但存在已明确记录的残余；**Closed（登记）** = 契约登记完成，检查器/设备证据另行跟踪；**Open** = 未关闭。

| ID | 上轮严重度 | 本轮状态 | 证据与说明 |
|---|---|---|---|
| **R2-01** Settings `RECONFIGURE` 缺 ADMIN 门 | Medium | **Closed** | `pages/SettingsPage.ets:122-125` 的 `isAdmin()` 以 `session.role === MemberRole.ADMIN` 判定；`:447-461` 的 `RECONFIGURE` 按钮增加 `.enabled(this.isAdmin())`，与同区 `ROTATE_SECRET`（`:440`）一致；SECURITY 区两个网关管理动作均受门控。测试 `T18_R2_settingsReprovisionRequiresAdmin`（`UiPages.test.mjs:448-468`）断言两个动作的 `.enabled(this.isAdmin())` 矩阵。服务层 `GAP-T18-01` 仍为未关闭上游缺口（见 §4.6），UI 门不替代服务层授权。 |
| **R2-02** 配网 `busy` 时取消按钮被禁用 | Medium | **Closed（主缺陷）＋ R3-02 残余** | `pages/ProvisioningPage.ets:636-646` 的取消按钮改为 `.enabled(this.view.canCancel \|\| this.localStep < 5)`，不再受 `!this.busy` 约束；`:255-272` 的 `cancel()` 清空 PoP/SSID/Wi-Fi 密码、清错误、复位 `busy`，调用 `BleProvisioningViewModel.cancel()`（`:394-408`：递增扫描代际、清 10s 定时器、`ble.cancel()`、销毁 draft、发布 `CANCELLED`）。测试：`T18_R2_provisioningCancelStaysAvailableWhileBusy`（源码守卫）与 `T18_R2_cancelDuringPrepareWifiCancelsBleAndClearsTimer`（AP 扫描挂起→取消→`CANCELLED`、`ble.cancelCalls>=1`、定时器 0）。**残余**：VM 层没有 `cancelled` 标志，`prepareWifi`/`submit` 也不检查 `scanGeneration`；页面 `cancelled` 只在 `vm.cancel()` resolve 后置位，晚到 `submit` 成功仍可进入 `commitResult`，见 **R3-02**。 |
| **R2-03** C-09/C-19/C-23/C-28/C-11 公共签名/端口未登记 | Medium（契约） | **Closed（登记）** | DES-A §0.7/§27.5 与 DES-B §0.9/§23.7 已登记 `EXT-DES-B-28..32`、`GAP-T18-01`、`TRUST-T18-01` 与 Change Impact；逐项签名与代码一致（见 §4）。T-20 `check_layering.py`/契约检查器落地与 T-19 设备证据仍另行跟踪。 |
| **R2-04** DoorCard 显式入口 skip 后成死按钮 | Low | **Closed** | `pages/DeviceControlPage.ets:390-394` 的 `onConfigureLink` 重置 `doorGuideDismissed = false` 并打开 `doorGuideVisible = true`；`components/DeviceCards.ets:317` 新增 `linkGuideOpen` prop，`:404` 仅在 `door.link.mode === 'NONE' && !linkGuideOpen` 时渲染入口；页面 `:376` 传入 `this.doorGuideVisible`。测试 `T18_R2_doorExplicitLinkButtonReopensGuide`（`UiPages.test.mjs:485-501`）同时断言“显式入口重置 dismissed”与“引导打开时隐藏重复入口”。skip（`:462-470`）只设置 dismissed=true/visible=false，之后入口重新出现。 |
| **R2-05** 配网中途权限/蓝牙失败无“去设置”CTA | Low | **Closed（页面层）** | `pages/ProvisioningPage.ets:60` 新增 `@State permission` 镜像；订阅（`:78-110`）在每次发布时同步 `view.permission`，并在 `PROVISIONING_PERMISSION_DENIED`/`PROVISIONING_BLUETOOTH_OFF` 时映射为 `DENIED`/`BLUETOOTH_OFF`；`:101-107` 在 `localStep >= 2` 时保留当前 Step 2/4；`:699-710` 在通用错误区渲染“去设置”CTA；Step0 保留原 CTA。测试 `T18_R2_midFlowPermissionFailureKeepsStepAndOffersSettings`（`UiPages.test.mjs:503-517`）。**已记录残余**：C-23 VM 的 `view.permission` 不更新（修复报告 §5.1），页面镜像只解决 UI 恢复路径。 |
| **F-06** D-12 白名单 | Medium | **Closed（T-18 增量）＋ R3-01 Low** | DES-B §2.3 D-12、§18.1、§0.9 与 §23.7 已登记文件/符号级白名单；T-18 新增的 `pages→app/PageVmFactory`、`components→viewmodel/core/{ViewModelCore,DoorConfirmationTracker}`、`UiMapping→service/ac/AcModels`、`DeviceCards` 的 `import type AcViewState`、components→C-10/C-11/C-15 只读 DTO 均被覆盖。**残余**：pages 既有的 `service/**` 模型值与类型 import、`repository/DomainModels` 类型 import 未正式列入 §2.3/§18.1 清单，§23.7 仅以“public read-only DTO 由 T-20 纳入”作边界注记；见 **R3-01**。 |
| **R2-06** 未用 import / 设备布局 | Low/Info | **Closed（import）/ Recorded（设备）** | `pages/MainShell.ets:22` 已删除未使用的 `AppMotionTokens`；`PrimaryButton` 的 `width('auto')`/长英文换行仍归 T-19 设备抽查。 |
| **GAP-T18-01** `addGatewayToFamily` 无 actor/RBAC | Medium（上游） | **Open（登记完整）** | DES-B §23.7:6155、DES-A §27.5:5487 明确记录：`FamilyRepository.addGatewayToFamily(familyId, gatewayId)` 无 actor/RBAC；R2-01 的 UI 门不构成服务层授权；IG-3 前关闭或由 Stage Gate 书面接受。 |
| **IG-3** | — | **NOT READY** | 设备/视觉/真实 BLE 矩阵未执行；R3-02 未关闭/未书面接受；GAP-T18-01 未关闭/未接受；T-20 检查器未落地。 |

---

## 4. R2-03 契约登记与代码签名核对

| 登记 | 代码实际签名/行为 | 结论 |
|---|---|---|
| **`EXT-DES-B-28`（C-09）** | `RoomService.ets:113-115` 构造器 `actors?: RoomActorLookupPort`（并含早期 `gate?`/`deviceNames?`）；`:131-260` 的 `createRoom`/`renameRoom`/`setIcon`/`reorderRooms`/`deleteRoom`/`assignDevice`/`unassignDevice`/`moveDevice` 均有 `actorMemberId?: string`；`:283-295` 提供 actor 时要求 `ACTIVE` + `FamilyRbac.requireAdmin`，缺省 actor 为 v1 trust。 | **一致**；8 个变更方法、构造器与 `RoomActorLookupPort` 均已覆盖。 |
| **`EXT-DES-B-29`（C-19）** | `BleProvisioningPorts.ets:215-237` `BleWifiScanRequest`（pop 1..64、expectedGatewayId 格式校验）；`:239-254` `IBleProvisioningClient.scanWifiAccessPoints(request, listener, cancellation?)`；`BleProvisioningService.ets:379-453` 实现 permission→scan→connect→discovery→capability→Security1→identity→AP 扫描，结束断链/零化 PoP，不应用 Wi-Fi 凭据；`MockBleProvisioningClient.ets:105` 已实现。 | **一致**；非可选接口方法已由 C-19/C-20 实现补齐。 |
| **`EXT-DES-B-30`（C-23）** | `BleProvisioningViewModel.ets:272` `prepareWifi(pop, expectedGatewayId?)`；`:314-315` `submit(pop, ssid, wifiPassword, commandSecretHex?, expectedGatewayId?)`；`:261-266` `openSettings()`；`ViewModelPorts.ets:22-26` `PermissionPort.openSettings?()`；`SettingsViewModel.ets:354-362` 的 `probeManualAddress` 以 `auth.canManageFamily`（ADMIN-only）fail-closed。 | **一致**；`BleProvisioningRequest.expectedGatewayId` 字段已存在（`BleProvisioningPorts.ets:157-197`），未新增错误码。 |
| **`EXT-DES-B-31`（C-28）** | `PageVmFactory.ets:20-30` 9 个 `create*ViewModel`；`AppContext.ets:82,139,198` 的 `pageVms`/`subscribeActiveFamily`；`NavigationService.ets:255-264` 的 `openRoomsWithHighlight`/`consumeRoomsHighlight`；`AppContext.ets:63-69` 的 `OnboardingPort`、`OnboardingService.ets:23` 实现。 | **一致**；§17.1 的签名与代码对应，未改变既有 `AppContext`/`AppCompositionRoot` 方法。 |
| **`EXT-DES-B-32`（C-11）** | `SceneService.ets:45-47` `SceneExecutionAuthorizationPort`；`:81-84` 可选 `authorization`；`:153` `run()` 最前 `authorizeExecution()`；`:250-262` 缺失/deny 均 `AUTH_RBAC_DENIED`；`SceneViewModel.ets:59,68-74,79-84` 可选 `authorization` 与 `canExecuteScene()`。 | **一致**；服务层 fail-closed，VM 与服务共用同一端口。 |
| **`GAP-T18-01` / `TRUST-T18-01`** | `FamilyRepository.addGatewayToFamily` 仍无 actor 参数；`RoomService.requireAdmin` 缺省 actor 直接放行（v1 trust）。 | **登记准确**；`GAP` 未关闭，`TRUST` 是已声明边界，二者未混用。 |
| **Change Impact** | DES-A §27.5:5491-5495、DES-B §23.7:6163-6168 说明 C-19 新方法为非可选接口成员、C-09/C-11/C-23/C-28 为可选/新增兼容、C-08 缺口保留、T-19/T-20 另行跟踪；不使无关组件 `STALE`。 | **完整**；契约文本与 T-18 实现对齐，未改写冻结方法名/参数顺序/返回类型/错误语义。 |

> 结论：**R2-03 关闭**。`EXT-DES-B-28..32` 的 ID、位置、类型、兼容性/行为与代码实际签名一致；`GAP-T18-01` 未被“登记”误写成“已修复”。T-20 检查器与 T-19 设备矩阵仍是后续证据。

---

## 5. F-06 / D-12 白名单覆盖审计

### 5.1 T-18 新增/变更 import（全部覆盖）

| 位置 | 实际 import | D-12 登记 | 结论 |
|---|---|---|---|
| `pages/AboutPage.ets:12`、`DeviceControlPage.ets:14`、`HomePage.ets:13`、`ProvisioningPage.ets:14`、`SettingsPage.ets:14` 等 | `import type { PageVmFactoryPort } from '../app/PageVmFactory'` | §2.3 D-12 ①、§18.1 第 1 条（仅 `import type`） | 覆盖 |
| `components/DeviceGrid.ets:11`、`DeviceCards.ets:16-19`、`RoomChipBar.ets:8`、`StatusPanels.ets:5-10`、`support/UiMapping.ets:15-23,29-33` | `viewmodel/core/ViewModelCore`、`viewmodel/core/DoorConfirmationTracker` 的纯枚举/只读状态/纯值 | §2.3 D-12 ②、§18.1 第 2 条 | 覆盖；未 import `*ViewModel`/端口，未构造/调用 VM |
| `components/support/UiMapping.ets:26-28` | `service/ac/AcModels` 的 `AcModeViewKind`/`AcVocabulary`/`AcViewState`/`AcBrand` 值 | §2.3 D-12 ②、§18.1 第 3 条（仅 `UiMapping` 纯值） | 覆盖 |
| `components/DeviceCards.ets:14` | `import type { AcViewState }` | §2.3 D-12 ②、§18.1 第 3 条 | 覆盖 |
| `components/DeviceGrid.ets:8`、`DeviceCards.ets:10-11`、`support/UiMapping.ets:13-14` | `import type { DeviceRecord }` / `SceneExecutionResult` / `SceneExecutionProgress` | §2.3 D-12 ②、§18.1 第 4 条（C-10/C-11/C-15 只读 DTO 仅 `import type`） | 覆盖（`SceneExecutionProgress` 同属 C-11 只读 DTO；见 5.2 文档命名不完整） |
| `pages/**` | 无 `@Provide`/`@Consume`；无 `new RoomService/SceneService/.../ViewModel`；无 `app/AppCompositionRoot`/`app/CompositionPlan` import | §2.3 D-12 ①②③ | 覆盖 |
| `components/**` | 无 `app/**`、无 `repository/**` 值 import、无 `service/**` 实现类 import | §2.3 D-12 ② | 覆盖 |

### 5.2 未正式列入 D-12 的既有 pages 依赖（R3-01）

以下 import 在 `pages/**` 中真实存在，但不属于 §2.3 D-12 ① 的明确白名单，也不在 §18.1 第 1 条的 T-18 例外内：

| 位置 | 依赖 | 性质 |
|---|---|---|
| `pages/ProvisioningPage.ets:22-27` | `service/ble/BleProvisioningPorts`：`BleProvisioningDevice`、`ProvisioningState`、`WifiAp`（值 import） | 公共配网模型/枚举；非服务实现 |
| `pages/ProvisioningPage.ets:32` | `service/ble/BleProvisioningPorts`：`ProvisioningProgress`（`import type`） | 公共只读 DTO |
| `pages/FamilyManagePage.ets:30` | `service/family/FamilyModels`：`CreateInvitationInput`、`FamilyJoinPhase`（值 import） | 公共模型/枚举 |
| `pages/FamilyManagePage.ets:31-35` | `service/family/FamilyModels`：`FamilyMemberView`、`InvitationView`、`InviteCreation`（`import type`） | 公共只读 DTO |
| `pages/SettingsPage.ets:24` | `service/cloud/CloudModels`：`CloudTransportState`（值 import） | 公共枚举 |
| `pages/SettingsPage.ets:25` | `service/cloud/CloudModels`：`CloudConfigView`（`import type`） | 公共只读 DTO |
| `pages/RoomManagePage.ets:25` | `service/room/RoomService`：`RoomDeletionPreview`（`import type`） | 公共只读 DTO |
| `pages/ProfilePage.ets:23` | `service/family/FamilyModels`：`FamilyMemberView`（`import type`） | 公共只读 DTO |
| `pages/HomePage.ets:22`、`RoomsPage.ets:22`、`DeviceControlPage.ets:36` | `repository/DomainModels`：`DeviceRecord`（`import type`） | C-10 只读 DTO |
| `pages/ScenePage.ets:27-28` | `repository/DomainModels`：`SceneExecutionProgress`/`SceneExecutionResult`/`SceneStepResult`/`SceneRunState`（`import type`） | C-11 只读 DTO |

- **§23.7:6157 的边界注记**已说明：pages 既有 `import type` 的 C-08/C-09/C-11/C-15 公共 DTO（如 `FamilyMemberView`、`RoomDeletionPreview`、`ProvisioningProgress`、`CloudConfigView`）未在本次重新裁定，T-20 落地时按“公共只读 DTO”纳入文件级 allowlist，或另行 Change Impact。该注记承接了大部分风险，但**未列出** C-10 `DeviceRecord`、未列出上述值 import（`ProvisioningState`/`WifiAp`/`BleProvisioningDevice`/`CreateInvitationInput`/`FamilyJoinPhase`/`CloudTransportState`），且 §0.9/§18.1 的正式清单未同步。
- **host 守卫** `T18_pagesAndComponentsRespectLayeringGuards`（`UiPages.test.mjs:519-551`）只正则允许 pages 的 `repository/DomainModels|DomainPorts`，未检查 `service/**` 模型/值 import，也未检查 `service/ac` 的符号级白名单；因此该测试不能替代 T-20 的 D-12 检查器。
- **`SceneExecutionProgress`** 在 `components/support/UiMapping.ets:14` 为 `import type`，与 `DeviceRecord`/`SceneExecutionResult` 同属 C-11 只读 DTO；§0.9:160 与 §23.7:6158 的“当前实际为 `DeviceRecord`、`SceneExecutionResult`”命名不完整（类别仍合法）。

> 结论：**F-06 的 T-18 增量已登记并覆盖**；pages 既有 service/repository DTO 的正式 allowlist 收口属于 T-20，记为 **R3-01（Low）**，不是运行时缺陷，但不得被解释为“pages 可 import 任意 service 实现”。

---

## 6. 新发现（R3-xx）

### R3-01（Low，契约/检查器完整性）：D-12 正式清单未枚举 pages 既有 service/repository DTO import

- **位置**：`entry/src/main/ets/pages/{ProvisioningPage,FamilyManagePage,SettingsPage,RoomManagePage,ProfilePage,HomePage,RoomsPage,DeviceControlPage,ScenePage}.ets`；DES-B §2.3 D-12、§18.1 第 1-4 条、§23.7:6157。
- **证据/影响**：如 §5.2 所列，pages 对 `service/{ble,family,cloud,room}` 的模型/枚举值与 `repository/DomainModels` 的 C-10/C-11 只读 DTO 有真实 import；D-12 ① 只明确允许 `common/model/viewmodel/C-14/contracts/components/app seam`，§18.1 的 T-18 例外只针对 `PageVmFactory`/components；§23.7 的注记以“import type 公共 DTO”承接部分依赖，但未覆盖值 import 与 C-10 `DeviceRecord`。T-20 `check_layering.py` 若严格按 §2.3 实现，会把这些既有文件判为违规；若放宽为“pages 可 import service 模型”，又会削弱 D-12。
- **建议/归属**：T-20 在 `check_layering.py` 的 D-12 allowlist 中按文件/符号列出这些公共只读 DTO/枚举（C-08/C-09/C-10/C-11/C-15），或由 architect 在 §18.1 补登记；不要把整个 `service/**` 放宽。属 `solution-architect` + T-20，不阻断 T-18 代码级结论。

### R3-02（Medium，取消竞态/契约一致性）：`cancel()` 未在 VM 层阻止晚到的 `submit` 成功提交

- **位置**：`entry/src/main/ets/viewmodel/BleProvisioningViewModel.ets:272-312`（`prepareWifi`）、`:314-380`（`submit`）、`:394-408`（`cancel`）、`:531-557`（`commitResult`）；`entry/src/main/ets/pages/ProvisioningPage.ets:255-272`；DES-B §12.1.1（“取消……由 `cancelled`/扫描代际保护；晚到结果不得覆盖取消界面”）。
- **证据/影响**：
  - `cancel()` 只递增 `scanGeneration`、清定时器、`ble.cancel()`、销毁 draft 并发布 `CANCELLED`；**没有**设置 `disposed` 或 VM 级 `cancelled` 标志。
  - `prepareWifi`/`submit` 只检查 `disposed`；`await this.ble.scanWifiAccessPoints(...)` / `await this.ble.provision(...)` 返回后，即使 `cancel()` 已发生，仍可能发布 `AP_SCANNING` 或进入 `commitResult`。
  - `commitResult`（`:531-535`）会 `gateways.commitBinding(...)` 并 `families.addGatewayToFamily(...)`；页面 `cancelled` 只在 `vm.cancel().then(...)` 后置位，且只控制渲染分支，不能撤销已发生的绑定。
  - 现有测试 `T18_R2_cancelDuringPrepareWifiCancelsBleAndClearsTimer` 只覆盖 `prepareWifi` 的挂起/取消；没有覆盖 `submit` 在 `provision`/`commitBinding` 晚到成功时的取消。
  - 修复报告 §5.4 已记录“`prepareWifi` 晚到 AP 列表/VM 代际”的残余，但未覆盖 `submit`/`commitResult` 的绑定路径；DES-B §12.1.1 的保护表述强于实现。
- **建议/归属**：`implementation-engineer` 在 C-23 增量中给 VM 增加取消代际/`cancelled` 标志：`cancel()` 递增代际，`prepareWifi`/`submit` 捕获代际并在发布/`commitResult` 前检查；或让 `cancel()` 进入终态并阻止 `commitResult`。补 host 测试“取消后晚到 `provision` 成功不得 commitBinding/addGatewayToFamily”。若决定不在 T-18 修复，`solution-architect` 需把 DES-B §12.1.1 的表述改为“页面显示层保护；VM 层代际保护待 C-23 增量”，并由 Stage Gate 书面接受。**在 IG-3 前必须关闭或接受。**

### R3-03（Info，已记录残余，不新增阻断）

- `ProvisioningPage` 的 `permission` 镜像在后续 VM 发布中可能被 `view.permission` 覆盖；C-23 VM 的 `view.permission` 在 `prepareWifi`/`submit` 中途权限失败后仍保持旧值（修复报告 §5.1 已记录）。页面 CTA 已满足 R2-05 的 UI 恢复路径；VM 状态自洽归 C-23 增量/T-19。
- `T18_provisioningSeamsAndRecoveryAreWired` 与 R2 测试均为源码级/host 级；ArkUI 渲染与真实权限弹窗仍归 T-19 设备矩阵。

---

## 7. CQG-T18 对照与最终意见

| 检查 | 结果 | 证据/说明 |
|---|---|---|
| 构建（生产图） | ✅ **PASS** | `clean assembleHap` BUILD SUCCESSFUL 14 s 632 ms，0 ERROR |
| 静态检查 | ✅ **PASS** | codelinter 0 error / 25 warn / 0 suggestion（与修复前同量级） |
| Host 测试 | ✅ **PASS** | **690/690**，fail/skipped 0；既有 685 保留 + 5 新增 |
| i18n / parity | ✅ **PASS** | `--strict-ui` blocking 0 / missing 0；warnings 139 / hardcoded 82；zh 543 / en 545（仅复数变体）；color 44/44；string 53/53 |
| 契约 | ✅ **PASS（登记）** | `EXT-DES-B-28..32`、`GAP-T18-01`、`TRUST-T18-01` 与代码签名一致；Change Impact 完整；T-20 检查器待落地；R3-01 Low |
| 安全 | ⚠️ **条件式** | R2-01 UI ADMIN 门、`probeManualAddress` ADMIN fail-closed、场景/房间服务层 RBAC、离线控制禁用成立；**R3-02 Medium**（取消后晚到 submit 仍可提交绑定）；**GAP-T18-01**（`addGatewayToFamily` 无服务层 RBAC）未关闭 |
| RBAC | ⚠️ **条件式** | 场景矩阵 ADMIN/MEMBER allow、GUEST deny；RoomService ADMIN allow、MEMBER/GUEST deny；`T18_R2_settingsReprovisionRequiresAdmin` 通过；GAP-T18-01 与 R3-02 仍跟踪 |
| 分层/DI | ✅ **PASS（有 R3-01 记录项）** | 无 `@Provide/@Consume`；页面无 `new` 服务/仓储/VM；Mock 生产排除；D-12 T-18 例外已登记；pages 既有 DTO 的 T-20 allowlist 收口为 R3-01 Low |
| 独立评审 | ✅ **本轮完成** | 本报告为未参与实现/修复的 quality-reviewer 第三轮独立复审；非作者自审 |
| 设备/视觉 | ⚠️ **BLOCKED** | 无设备/模拟器/Previewer/签名；ohosTest 仅 COMPILED_ONLY；真实 BLE/权限弹窗/AP/绑定探针/LAN/云/TLS 未验证 |
| GAP-T18-01 | ❌ **OPEN（Medium，上游）** | `FamilyRepository.addGatewayToFamily` 无 actor/RBAC；R2-01 UI 门不替代服务层授权；IG-3 前关闭或由 Stage Gate 书面接受 |
| IG-3 | ❌ **NOT READY** | 设备矩阵未执行；R3-02 未关闭/未接受；GAP-T18-01 未关闭/未接受；T-20 检查器未落地 |

### CQG-T18 最终意见

**PASS（代码级，条件式）**：`4b99e64` 对 R2-01/R2-02（主缺陷）/R2-03/R2-04/R2-05 与 F-06 的修复/登记成立；构建、lint、host 690/690、ohosTest 编译、i18n 门禁与契约登记证据可复现。条件如下：

1. **R3-02（Medium）**：在 IG-3 前给 C-23 VM 增加取消代际/`cancelled` 保护，阻止晚到 `submit` 进入 `commitResult`；或由 `solution-architect` 修正 DES-B §12.1.1 表述并由 Stage Gate 书面接受。补 host 负例。
2. **GAP-T18-01（Medium，上游）**：`addGatewayToFamily` 的服务层 actor/RBAC 关闭或书面接受；不得把 R2-01 的 UI 门写成服务层 RBAC 已闭合。
3. **T-20**：按 §2.3/§18.1 落地 D-12 文件/符号级 allowlist，并处理 R3-01（pages 既有 service/repository DTO/枚举、`SceneExecutionProgress`、值 import）。
4. **T-19**：设备/视觉/真实 BLE/权限弹窗/AP/绑定探针/LAN/云/TLS 矩阵；不得把 `COMPILED_ONLY` 或 `BLOCKED` 写成 PASS。
5. 若 Orchestrator 的 CQG 口径要求“无未决 Medium”，本轮应记为 **CHANGES_REQUIRED**；本评审基于项目既有“代码级条件式 PASS + 跟踪项”口径给出上述建议。最终 Gate 决定由 Orchestrator/Stage Gate 记录，本报告不授予 Stage 或用户验收。

---

## 8. 残余风险与跟踪

| 项 | 状态 | 归属 |
|---|---|---|
| R3-01 pages 既有 service/repository DTO/枚举未正式列入 D-12 | **Open（Low）** | `solution-architect` + T-20 |
| R3-02 取消与 `submit`/`commitResult` 的 VM 级竞态 | **Open（Medium）** | `implementation-engineer` / C-23；T-19 设备验证 |
| R2-05 VM `view.permission` 不更新（页面镜像已修复 UI） | Recorded | C-23 增量/后续 |
| `FamilyRepository.addGatewayToFamily` 无 actor/RBAC（GAP-T18-01） | **Open（Medium，上游）** | C-22/C-09/C-15；Stage Gate 接受或关闭 |
| `RoomService` 缺省 actor 的 v1 local-admin trust（TRUST-T18-01） | Recorded（已声明边界） | 组合根/迁移调用约定；生产 UI 必须传 actor |
| `PrimaryButton` `width('auto')` + en-US 长标签/小屏/安全区 | **BLOCKED（设备）** | T-19 |
| 真实 BLE/权限弹窗/AP 扫描/绑定探针/LAN/云/TLS | **BLOCKED（设备）** | T-19 / 用户实机 |
| 设备/视觉/动效/触感/读屏 | **BLOCKED** | T-19 |
| T-20 分层/RBAC/i18n/契约检查器落地 | **Pending** | T-20 |
| F-15 未消费组件、F-17 effective profile、F-21 邀请字段/转让过滤 | Recorded/Partial | T-19/T-20 或后续任务 |

**IG-3**：**NOT READY**。前置：T-19 设备矩阵（R2-01 按钮禁用可见性、R2-02 取消、R2-04 门磁引导、R2-05 权限 CTA、F-01/F-04/F-05/F-10/F-13/F-14 设备/视觉）；R3-02 关闭/接受；GAP-T18-01 关闭/接受；T-20 检查器落地；F-06/R3-01 的 allowlist 收口。**T-20**：把 D-12 文件/符号 allowlist、RBAC 静态检查、i18n 硬编码/parity、契约签名登记纳入正式门禁。

---

## 9. 独立声明与裁决边界

1. 本复审由 `quality-reviewer` 独立完成；未参与 T-18 实现或 `wp-077-fix-t18b`/`wp-078-t18-contracts`，未编辑任何被审代码、测试或契约；本任务唯一写入为 `artifacts/70-review/t18-review-c.md`（覆写 guard 前置占位）。
2. 评审基于 `4b99e64`（R2 修复 `f6e9c9b`/`74e9157`，父 `6737303`，上轮基线 `8f3d969`）与 handoff 冻结输入；输入 SHA-256 与 handoff 一致；未对 `input/`、DES-A/DES-B、contract-baseline、test-plan 或旧评审报告做修改。
3. 复验命令均在本机实际执行：host 690/690、codelinter 0 error、clean assembleHap BUILD SUCCESSFUL、ohosTest 编译 BUILD SUCCESSFUL、i18n blocking 0/missing 0；未把 `COMPILED_ONLY`/`BLOCKED` 写成 PASS。
4. **Verdict 仅覆盖本报告 §1 的 revision 与范围**：PASS（代码级，条件式）；R3-02/GAP-T18-01 未关闭前不得宣告 IG-3 或设备 PASS；不授予 Stage Gate 或用户验收。
5. 未发现作者自审替代；未发现越界产品代码改动；未发现秘密/构建产物入库；未发现既有 685 条 host 测试被删除或弱化。

---

## 10. Next action

1. **R3-02**：`implementation-engineer` 在 C-23 VM 增加取消代际/`cancelled` 检查，阻止晚到 `submit` 进入 `commitResult`；补 host 测试；若不做，`solution-architect` 修正 DES-B §12.1.1 并由 Stage Gate 书面接受。
2. **GAP-T18-01**：C-22/C-09/C-15 关闭 `addGatewayToFamily` 服务层 actor/RBAC，或 Stage Gate 记录风险接受；不得宣称服务层 RBAC 已闭合。
3. **R3-01/T-20**：把 pages 既有 service/repository 公共只读 DTO/枚举、`SceneExecutionProgress` 与值 import 纳入 D-12 文件/符号 allowlist；为合法/违规 fixture 自测。
4. **T-19**：执行设备/视觉/真实 BLE/权限/AP/绑定探针/LAN/云/TLS 矩阵；复跑本报告 §2 命令并记录证据。
5. 完成上述后重新评估 IG-3；CQG-T18 的最终 Stage Gate 决定由 Orchestrator 记录。

```text
STATUS: COMPLETE
SUMMARY: 复审 4b99e64（R2 修复 f6e9c9b/74e9157 + 契约登记 4b99e64）；R2-01/R2-03/R2-04/R2-05 与 F-06 关闭，R2-02 主缺陷关闭；新增 R3-02（Medium，取消与 submit/commitResult 竞态）与 R3-01（Low，D-12 pages 既有 DTO allowlist 收口）
ARTIFACTS_CREATED: artifacts/70-review/t18-review-c.md
ARTIFACTS_UPDATED: artifacts/70-review/t18-review-c.md（覆写占位）
RISKS: R3-02 未关闭；GAP-T18-01 未关闭；R3-01 待 T-20；设备/真实 BLE/LAN/云 BLOCKED
VALIDATION: host 690/690；codelinter 0 error/25 warn；clean assembleHap SUCCESS 14s632；ohosTest 编译 SUCCESS 13s75；i18n blocking=0/missing=0；parity zh543/en545
NEEDS_CLARIFICATION: no（R3-02/GAP-T18-01 已列明归属与 Gate 条件）
NEXT_ACTION: C-23 取消代际/commit 保护 + GAP-T18-01 关闭/接受 + T-20 allowlist 后复评 IG-3
```
