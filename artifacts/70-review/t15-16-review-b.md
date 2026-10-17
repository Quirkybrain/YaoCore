# T-15 / T-16 修复复审报告（C-21 / C-22 / C-23）

- **Artifact ID**: REVIEW-T15-T16-B
- **Producer**: agent:quality-reviewer
- **Type**: Independent Code Review / Re-review
- **Status**: **CHANGES_REQUIRED（组件级；F-01..F-04/F-06..F-08 与 U-01 的修复目标已关闭，但新发现 R2-01 阻断 CQG-T15）**
- **Date**: 2026-10-18
- **Task**: `wp-064-review-t15-16b`（task 分支 `task/wp-060-vm`，父分支 `feat/yaocore-app`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`（CQG-T15 / CQG-T16 前）
- **Reviewed revision**: `e77b192ee02034858898f6ca8b228f3b9738389f`（HEAD；修复 `1e7487e..e77b192`，其中 `625eabe` 为主修复、`e77b192` 为门锁确认值加固；父裁定 `1e7487e`）
- **Previous review**: `artifacts/70-review/t15-16-review.md`（CHANGES_REQUIRED，revision `ffadebf`）
- **Review snapshot**: `refs/swe/snapshots/20261017T161925Z-wp-064-review-t15-16b-fa06fc9c`（commit `e02383f6a99d2dda028da41c23a4cc7dccaaecc7`）
- **Independence**: 本报告由未参与 T-15/T-16 实现、测试、实现报告或修复报告编写的 `quality-reviewer` 执行。评审期间未修改任何被审产品代码、测试、证据或实现/修复报告；唯一仓库写入为本报告。行为探针通过 `node --import ... --input-type=module -e` 在内存中执行，未在仓库落盘；复验前后工作区保持 clean，HEAD 为 `e77b192`。

> 结论先行：上轮 8 个代码/测试项（F-01、F-02、F-03、F-04、F-06、F-07、F-08、U-01）均已按裁定和评审建议落实；`entry/src/test/run-host-tests.sh` 独立复跑 **610/610 PASS**，`codelinter`、clean `assembleHap`、ohosTest（含 C-18 编译探针）**全部成功**。但独立复审在未改动的门锁命令构造路径发现一个 **High 阻断项 R2-01**：`DoorViewModel.lock()` 对 `CLOSE` 发送 `value=true`，与 `ControlPolicy` 的 CLOSE 布尔期望相反，生产路径会在发出前被 `PROTOCOL_VALUE_OUT_OF_RANGE` 拒绝，导致“锁门”功能不可用；现有 DoorVM 用例使用不校验命令值的 Fake，未暴露该问题。另发现 **Medium R2-02**：`DeviceViewModel` 仍只有一个全局 `ThrottleGate`，与 DES-B §10.3.2“不同设备各自独立节流”不符，跨设备 `beginContinuous` 会把旧设备永久留在 `PENDING`。因此 **CQG-T15/T16 不能记为 PASS；C-21/C-22/C-23 继续保持 `UNVERIFIED`**。

---

## 1. 复审范围、revision 与输入完整性

### 1.1 范围

```text
entry/src/main/ets/viewmodel/                 # 产品 VM（Device/Climate/Door/Ble/Family/Settings + core/**）
entry/src/main/ets/service/                   # 修复涉及的 C-08/C-18/C-22 依赖
entry/src/test/                               # host 测试、helper、证据日志
entry/src/ohosTest/ets/test/                  # 设备编译骨架（含 C-18 编译探针）
artifacts/50-implementation/t15-16-fix-report.md
```

- 被审 diff `1e7487e..e77b192` 共 **31 个路径**：10 个产品/服务文件、10 个 host 测试/helper、1 个 ohosTest 骨架、2 个 README、7 个证据日志、1 个修复报告（另含 `t15-16-fix-*` 证据文件）。与修复报告 §4 的变更清单一致。
- 交叉读取但未修改：上轮评审、`t15-16-vm.md`、DES-B §0.7/§3/§10/§11/§12、DES-A、`contract-baseline.md`、`project-constraints.md`、`test-plan.md`、`GatewayRequestPolicy`/`DeviceCommandRunner`/`CloudService`/`AuthService` 等契约消费面。
- 明确排除：真实设备/模拟器、真实 BLE/LAN/云、UI 三态视觉与动画、NFR 4.3 p95、T-17/T-18 页面与资源落地、T-19 全量执行、T-20 安全评审、用户验收与完整 Stage Gate。这些保持 `BLOCKED` / `COMPILED_ONLY` / `UNAVAILABLE`，本报告不将其写成 PASS。

### 1.2 输入 pin 与快照

handoff 的 8 个 `inputs` SHA-256 **8/8 一致**；`config/git-policy.json` 的 SHA-256（`3b8ddffd4494…`）与 handoff 一致。复验前后 `git status --short` clean，HEAD = `e77b192`。

| 输入 | SHA-256 前 12 位 | 结果 |
|---|---|---|
| `artifacts/70-review/t15-16-review.md` | `b00cc41a159b` | 一致 |
| `artifacts/50-implementation/t15-16-fix-report.md` | `ff00904d589d` | 一致 |
| `artifacts/50-implementation/t15-16-vm.md` | `75638e1c9990` | 一致 |
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | `42e6912806e3` | 一致 |
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `3a02ecbf266b` | 一致 |
| `artifacts/20-architecture/contract-baseline.md` | `883e09bb34ea` | 一致 |
| `artifacts/20-architecture/project-constraints.md` | `283046210e68` | 一致 |
| `artifacts/60-testing/test-plan.md` | `33485cc39abd` | 一致 |
| `config/git-policy.json` | `3b8ddffd4494` | 一致 |

### 1.3 本评审实际复验（cwd = 仓库根，全部只读）

| 命令 | 结果 | 说明 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS：610 tests / 610 pass / 0 fail / 0 skipped / 0 todo，exit 0** | 与 `evidence/t15-16-fix-host-node-tests.tap` 的 610/610 一致；较首轮 593 新增 17 条，无删除/跳过 |
| `codelinter -c code-linter.json5 -p default .` | **PASS：No defects found in your code，exit 0** | 与 `t15-16-fix-codelinter.log` 一致 |
| `hvigorw clean assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0**（35 tasks） | 与 `t15-16-fix-clean-assemble.log` 一致 |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0**（35 tasks） | 编译骨架已 import `GatewayDiscoveryService`，因此这是 **ArkTS 类型/编译证据**，不是设备执行证据 |
| `python3 entry/src/test/i18n/check_i18n.py --root . --strict-ui` | **PASS：blockingFailures=0，warnings=67，missingKeys=0，exit 0** | 新增 ViewModel 无硬编码 UI 文案；warnings 为既有 Index/T-14 协议别名等 |
| `git status --short` | **clean** | 构建仅产生 ignored 目录，未产生跟踪文件变化 |

测试计数核对：17 条新增用例逐一存在且真实执行（Device 3、Climate 1、Throttle 2、DoorVM 4、Ble 2、Settings 1、Family 2、DomainFamily 2），与修复报告 §2.7 一致；无 `skip`/`todo`。设备骨架保持 `BLOCKED_ON_DEVICE_RUNNER`，未把编译成功写成设备 PASS。

---

## 2. 上轮 Findings 关闭状态

| ID | 上轮严重度 | 本轮状态 | 复核证据与说明 |
|---|---|---|---|
| **F-01** 连续控制 cancel/supersede 晚到结果 | High | **CLOSED（限定同 key/同会话；跨设备见 R2-02）** | `DeviceViewModel` 新增 `gateToken`，`beginContinuous` 捕获会话代际，`dispatchContinuous` 在入口与 `await control.execute` 后均校验 disposed/gate/token/gateKey；`cancelContinuous`/`endContinuous`/`dispose` 递增代际；`endContinuous` 在 `onCommit` 后仅当代际仍匹配才发布 `COMMITTED/REVERT`。`ClimateViewModel` 同样处理。新增 3 条 Device + 1 条 Climate + 2 条 Throttle 用例均有效：cancel-in-flight 保持 `IDLE`；新 begin 丢弃旧结果；cancel/end 并发不出现 `COMMITTED`。上轮探针时序已被覆盖。 |
| **F-02** 门锁控制 ACK ≠ 门状态确认 | High | **CLOSED（状态/confirmedValue 语义）；但生产命令值被 R2-01 阻断** | `DoorConfirmationTracker.onUnlockResult` 仅在 reported `open===true` 时 `OPEN`；`open===false` → `FAILED/UNCONFIRMED`；无 reported → `UNVERIFIED` 且保留上一 `lockState`。`onResult` 对 CLOSE reported `open=true` 进入 `FAILED/OPEN`，VM 由 `door.stage===FAILED` 驱动 `REVERT`，不再无条件 `COMMITTED`。PENDING/COMMITTED 的 `confirmedValue` 取 reported 或上一确认值，不再用请求值冒充。4 条负例 + 正例断言均通过。**注意**：这些用例使用不校验命令值的 Fake，无法证明 `lock()` 在真实 `ControlPolicy` 下可发出（见 R2-01）。 |
| **F-03** 配网 `back()` 未停扫/清 10s 定时器 | Medium | **CLOSED** | `back()` 在 `STEP_1_SCAN` 先递增 `scanGeneration`、`clearScanTimer()`、调用 `stopScan()`，再发布 `STEP_0/IDLE`；`startScan` 在 `await` 后校验代际/step，晚到 continuation 不再安装定时器；定时器回调与 `onScanError` 同样校验代际/step。2 条 Ble 回归覆盖“已扫描后 back”和“startScan 未返回时 back”，断言 `stopCalls=1`（前者）、timer=0、推进 10s 无错误。 |
| **F-04** Settings Token 过期不刷新 `state.cloud` | Medium | **CLOSED** | `testCloudConnection` 在 `result.valid===false` 时重新 `loadCloud()` 并 `publish(cloudState(...))`；C-15 `getState()` 已在 401/403 后映射 `TOKEN_EXPIRED/TOKEN_INVALID`，因此持久视图同步。测试断言 token 过期后 `state.cloud.state==='TOKEN_EXPIRED'`，网络失败保持 `CONFIGURED`。 |
| **F-06** C-08/C-22 `COMPLETED` 定义冲突 | Low（裁定） | **CLOSED（按 `1e7487e` / DES-B §0.7）** | `FamilyJoinPhase` 新增 `MEMBER_BOUND`；`submitInvitation` 成功终态为 `MEMBER_BOUND`；`markProfileBound()` 是唯一 `COMPLETED` 写入点（grep 确认无其他写入）；前置校验成员 ACTIVE、精确 `(familyId, memberId)` 档案、active family。`FamilyViewModel` 按固定顺序 `createProfile → switchFamily → 发布 needsUnlock → markProfileBound → appContext.lock() → refreshSessionGate() → refresh()`。DomainFamily/InviteService/ViewModelFamily 用例已从旧“submit 即 COMPLETED”更新。 |
| **F-07** 加入部分失败重试/`needsUnlock` | Low（裁定） | **CLOSED** | `AUTH_PROFILE_EXISTS` 仅在 `listProfiles(familyId)` 存在同 `memberId` 档案时幂等继续，否则原样抛出；`switchFamily` 的 `requiresUnlock` 写入 `FamilyViewState.needsUnlock`；失败保留 `MEMBER_BOUND + AcceptedInvitation`，按 `getActiveFamily()/getActiveSession()` 重算 `needsUnlock`，允许重试且不重复创建档案。新增“profile 成功 + switch 失败 → AUTH_PROFILE_EXISTS 重试成功”用例。 |
| **F-08** 缺少 F-01..F-04 负例 | Low | **CLOSED（17 条真实回归；DoorVM 仍缺命令值断言）** | 17 条新增用例与修复报告一致：Device 3、Climate 1、Throttle 2、DoorVM 4、Ble 2、Settings 1、Family 2、DomainFamily 2。用例断言状态、调用次数、定时器与 `confirmedValue`，不是走过场。**残余测试缺口**：DoorVM 的 FakeControlCoordinator 不校验 `command.value`，因此 4 条门锁负例无法暴露 R2-01；建议补真实 `ControlPolicy`/`DeviceCommandRunner` 集成断言或至少断言 `calls[0].command.value===false`。 |
| **U-01** C-18 `GatewayDiscoveryService` 编译阻断 | High（上游） | **CLOSED（编译级）** | `withProbeTimeout` 的 executor `reject` 显式声明为 `(reason: AppError) => void`，超时和 `asAppError` 均传入 `AppError`，保留错误码语义。ohosTest 骨架持久 import `GatewayDiscoveryService` 并断言“defined”，确保该类不被未引用裁掉；修复前证据 `t15-16-fix-u01-probe-before.log` 在 `:331:18`/`:344:18` 报 `arkts-no-structural-typing`，修复后证据与本轮 ohosTest assemble 均为 BUILD SUCCESSFUL。生产编译图可包含 C-18。 |
| **F-05** `GATEWAY_CONFIRMED` 不可观察 | Low | **OPEN（跟踪）** | 不在本轮裁定/修复范围；`onResult` 仍直接进入 SECURED/WAITING_CONTACT/UNVERIFIED，`DoorStage.GATEWAY_CONFIRMED` 公开枚举值不可达。保留为 CQG/后续跟踪。 |
| **U-02** `settings.cloud.single_gateway_required` 资源键 | Low | **DEFERRED（T-18）** | i18n 检查 missingKeys=0（常量/动态键未被静态检查捕获），但该键在 zh-CN/en-US 仍缺失；`brand.*` 属 T-14 F-05 上游。保持 T-18 跟踪。 |
| **U-03** `pinMatched`/`rotationRecommended`/`addGatewayToFamily` | Info | **DEFERRED（T-17/T-18）** | VM 诚实留空/false；C-08 `addGatewayToFamily` 缺口仍由 T-17/C-08 owner 处理。保持跟踪。 |

**结论**：上轮列出的 F-01..F-04、F-06..F-08 与 U-01 的修复目标已达成，且新回归真实有效；F-05/U-02/U-03 按原计划保留跟踪。**但组件级 CQG 仍不能 PASS，原因见 R2-01/R2-02。**

---

## 3. 新发现（R2-xx）

### R2-01（High，阻断 CQG-T15）：`DoorViewModel.lock()` 发送错误的 CLOSE 命令值，生产路径必然失败

| 项 | 内容 |
|---|---|
| 位置 | `entry/src/main/ets/viewmodel/DoorViewModel.ets:130-136`（`lock()` → `applyLock(DeviceAction.CLOSE, true)`）、`:233-234`（构造 `DeviceControlCommand`）、`:236`（执行） |
| 违反 | DES-B §10.1.7 `lock()`/`unlock()` 控制语义；`ControlPolicy` 的 CLOSE 布尔期望（`GatewayRequestPolicy.ets:172-179`：`expected = action===TURN_ON || action===OPEN || action===BOARD_LED_ON`，即 CLOSE 必须 `value=false`）；`DeviceCommandRunner` precheck 与 `LocalGatewayService.control` 均调用该策略 |
| 问题 | `lock()` 以 `value=true` 构造 CLOSE 命令。`ControlPolicy.validateValue` 对 CLOSE + `true` 抛 `PROTOCOL_VALUE_OUT_OF_RANGE`；`DeviceCommandRunner`（UI_CONTROL 预检）在调用传输前即拒绝，`DoorViewModel.applyLock` 随后进入 `REVERT`。因此**生产中“锁门”永远无法成功**，F-02 的 CLOSE 修复在真实路径上不可达。 |
| 证据 | 独立探针（真实 `ControlPolicy`）：`CLOSE value=true -> rejected PROTOCOL_VALUE_OUT_OF_RANGE`；`CLOSE value=false -> accepted`；`OPEN value=true -> accepted`。现有 `ViewModelDoorVM.test.mjs` 的 `FakeControlCoordinator` 直接返回预置 execution，不校验 `command.value`；用例 `closeWithReportedOpen...` 构造的 `executionOf(..., { value: false })` 只影响返回的 execution，不影响 VM 实际发出的命令。 |
| 影响 | C-21 门锁 `lock()` 为安全相关核心 API；虽然失败是 fail-closed（不会把门误开），但用户无法锁门，CQG-T15 的“契约/功能”项不成立。该缺陷在 `ffadebf` 已存在，不是本修复引入；上轮评审未发现，本轮因复核门锁路径而暴露。 |
| 建议 | 将 `lock()` 改为 `applyLock(DeviceAction.CLOSE, false)`（或由 `action` 推导布尔值，禁止调用方传错）；补一条使用真实 `ControlPolicy` 或至少断言 `FakeControlCoordinator.calls[0].command.value===false` 的宿主/集成用例；修复后重新执行 610+ host、codelinter、clean assemble、ohosTest 编译并复审。 |
| 归属/时机 | implementation-engineer；**CQG-T15 前必须修复**；不需要新设计裁定（与 `DeviceViewModel.closeDoor` 的既有 `false` 约定一致）。 |

### R2-02（Medium，契约/状态机）：`DeviceViewModel` 单一全局 `ThrottleGate` 与“不同设备独立节流”冲突

| 项 | 内容 |
|---|---|
| 位置 | `entry/src/main/ets/viewmodel/DeviceViewModel.ets:191-223`（`beginContinuous`）、`:280-296`（`cancelContinuous`）；全局字段 `gate/gateKey/gateAction/gateMin/gateMax/gateLast*` |
| 违反 | DES-B §10.3.2：`不同设备各自独立节流；同设备不同 action 串行`；DES-B §10.1.3 连续控制接口按 `DeviceKey` 区分 |
| 问题 | `beginContinuous(keyB)` 先调用 `cancelContinuous(keyB)`，该调用无条件 `dispose` 当前（可能属于 keyA 的）gate，并清空 `gateKey`；随后只把 **keyB** 的控制态置 `PENDING`。keyA 的控制态停留在 `PENDING`，但已无存活 gate/定时器能完成或回弹，形成永久“发送中”。同时 `gateAction/gateMin/gateMax` 被 keyB 覆盖，无法表达两设备并行节流。 |
| 证据 | 独立探针（真实 `DeviceViewModel` + 两个 record）：`beginContinuous(A) -> A PENDING`；`beginContinuous(B) -> A 仍 PENDING、B PENDING`。现有 610 条用例没有跨设备连续控制用例。 |
| 影响 | 用户从设备 A 的连续控制直接进入设备 B 的连续控制（或页面未先 cancel A）时，A 的 UI 可能永久显示 PENDING；违反按设备独立节流的契约。非安全虚构成功，但属于三态状态机/契约缺口。该缺陷在 `ffadebf` 已存在，本修复的代际只解决同一 gate 会话的晚到结果，未解决跨设备会话隔离。若 C-28 最终为每个设备页创建独立 VM 实例，该缺陷在生产中可能是潜伏的；但类契约本身未限制单设备，且 `initialize` 明确加载多设备，应按组件缺陷处理。 |
| 建议 | 二选一并与契约 owner 确认：(a) 按 key 维护 gate/会话状态（契约正确）；(b) 明确 v1 仅允许一个 active 连续控制，在 `beginContinuous` 切换 key 前用旧 `gateKey` 取消并发布旧 key 的 `IDLE`/回弹，同步更新 DES-B 说明与测试。补“A begin → B begin → A 不残留 PENDING”用例；若采用 (b)，需书面记录为 v1 限制，不能静默保留。 |
| 归属/时机 | implementation-engineer + solution-architect（若选择 (b) 需契约文字）；CQG-T15 前修复或书面接受。 |

> 说明：未把 BLE `back()` 在“startScan 未返回”场景可能触发两次 `stopScan`（back 一次 + 晚到 continuation 一次）列为独立 finding；`stopScan` 已 catch 错误，影响限于重复调用，建议后续在 T-17/T-19 真机复核时观察。门锁 unlock 超时未更新 tracker 属既有行为，保持残余观察。

---

## 4. 契约与回归核对

| # | 核对项 | 结论 | 说明 |
|---|---|---|---|
| 1 | 三态：COMMITTED 仅 `ackAccepted + verification!=MISMATCH`；PENDING/REVERT 3s；禁止乐观成功；replay 不重复应用 | **符合（F-02 路径受 R2-01 阻断）** | Device/Climate 成功/失败/MISMATCH/3s 回弹与测试正确；F-01 代际关闭；门锁状态语义按 F-02 修复，但 CLOSE 命令值错误使真实 lock() 不可用（R2-01）。replay 仍由 C-10/C-17 层处理。 |
| 2 | 55ms/TouchUp：合并、1 在途、latest 不丢、最终值强同步 | **符合（同设备）** | `ThrottleGate` 核心状态机、55ms、1 在途、TouchUp、cancel、dispatch 失败测试均通过；新增 commit-before-55/cancel-with-waiter 有效。跨设备独立节流不满足（R2-02）。 |
| 3 | 门锁四阶段：10s/门磁到位/在线离线；无门磁如实“未验证到位” | **部分符合** | GATEWAY_MERGED、CONTACT_SENSOR 到位/10s 在线 UNCONFIRMED/离线 UNKNOWN/NONE→UNVERIFIED、open 报警、dismiss 与 §10.1.7 一致；F-02 的 unlock/CLOSE 状态与 confirmedValue 已修复；F-05 `GATEWAY_CONFIRMED` 仍不可观察；R2-01 阻断真实 CLOSE。 |
| 4 | LAN→云回退边界：仅网络类错误；安全/设备错误不回退；单网关 v1 | **符合** | `DeviceControlCoordinator` 仅对 `GATEWAY_UNREACHABLE/GATEWAY_TIMEOUT/LOCAL_REQUEST_FAILED` 且云 `CONFIGURED` 回退；`DEVICE_OFFLINE/TLS_*/TOKEN_*` 不回退；云 `UNSUPPORTED` 不 apply/不成功；本次未改该逻辑。 |
| 5 | RBAC/F-08：GUEST 控制矩阵/`RBAC_DENIED`；房间删除保护/未分配池 | **符合（VM 层）** | `FamilyCapabilities` 由 C-12 派生，GUEST `canExecuteScene=false`；F-08 fail-closed 未变；房间删除/未分配池未改；本次 Family 变更只影响加入完成语义。 |
| 6 | 配网 VM：6 步/取消清理/R-1 `credentialDraftId` | **符合** | 6 步映射、权限、扫描去重/10s、取消 `ble.cancel`+销毁草稿、R-1 `commitBinding(result, result.credentialDraftId, familyId)` 未变；F-03 清理/代际修复通过。 |
| 7 | 错误→i18n：经 `ErrorI18nMapper`，无硬编码；键存在性 | **符合** | 所有 VM 只保存 `i18nKey`，`translate*` 才调用 `t()`；新增代码无硬编码 UI 文案；CHK-01..09 通过。U-02 常量键仍缺失（T-18）。 |
| 8 | 上游编译：C-18 如实记录/隔离，不得在 T-17 爆雷 | **符合** | U-01 已修复；持久 make-probe 在 ohosTest 中 import `GatewayDiscoveryService`，本轮 assemble 成功；生产编译图可含 C-18。 |
| 9 | 测试质量：新用例有效、负例、设备骨架诚实 | **符合（有 R2-01 测试缺口）** | 17 条真实执行，状态/调用/定时器断言明确；设备骨架 `BLOCKED_ON_DEVICE_RUNNER` 诚实。DoorVM Fake 不校验命令值，是 R2-01 未被发现的直接原因。 |
| 10 | 过程/卫生：变更路径、证据一致、无秘密/构建产物 | **符合** | 31 路径与修复报告 §4 一致；5 个验证日志 + 2 个 U-01 探针日志可复核；`git status` clean；未发现 `.hap/build/oh_modules/密钥` 进入提交。 |

### 4.1 不改变项核对

- **D-009**：成员加入主路径仍为 `acceptInvitation → 成员 ACTIVE → MEMBER_BOUND → markProfileBound`；密码仅调用期存在；测试未泄漏密码。
- **D-010**：接触式收敛未改；门磁/在线/离线事件路径未改。
- **D-013**：本次未改 TLS/安全路由逻辑；U-01 只改 Promise reject 类型，不改变错误码语义。
- **D-022/D-023**：邀请容器/回执账本/`DomainOperationGate` 未改；`FamilyJoinSession.cancel()` 在 `MEMBER_BOUND/COMPLETED` no-op 符合裁定。
- **R-1**：`BleProvisioningViewModel` 仍使用 `commitBinding(result, result.credentialDraftId, familyId)`；请求草稿与结果草稿分离未变。
- **F-08 GUEST**：C-12 能力派生未改；GUEST 场景 fail-closed 未改。
- **三态/55ms**：Device/Climate 主语义未破坏；新增代际只丢弃晚到结果；host 610/610 覆盖原有用例。

---

## 5. CQG-T15 / CQG-T16 对照

| CQG 项 | 结论 | 依据/限制 |
|---|---|---|
| 构建（clean assembleHap） | **PASS** | 独立复跑 BUILD SUCCESSFUL，exit 0 |
| Lint（codelinter） | **PASS** | No defects found，exit 0 |
| Host 测试 | **PASS** | 610/610，0 fail/skip/todo |
| 契约（C-21/C-22/C-23） | **CHANGES_REQUIRED** | F-01..F-04/F-06..F-08 与 U-01 修复目标关闭；但 **R2-01（High）** 使 C-21 `lock()` 生产不可用；**R2-02（Medium）** 违反跨设备独立节流；F-05 仍 OPEN |
| 安全（VM 层，非 T-20 全量） | **PARTIAL** | F-02 不再把 UNVERIFIED/矛盾状态写成 OPEN/SECURED；门锁命令在策略层 fail-closed；未发现秘密/凭据进入 state 或日志；完整安全评审仍属 T-20，R2-01 为功能阻断而非“误开” |
| 分层/架构 | **PASS** | VM 不 import 平台 API；服务/仓储边界未破坏；`FamilyProfileRef.memberId` 是 §0.7 允许的内部 seam；无协议/错误码/线格式变更 |
| i18n | **PASS（含 U-02 跟踪）** | CHK-01..09 通过，0 blocking，missingKeys=0；U-02 常量键与 `brand.*` 仍由 T-18 补齐 |
| 独立评审 | **本报告** | 未参与实现/测试/报告；只读复审；不授予 STABLE/Stage Gate |
| 设备执行 | **BLOCKED** | 无设备/模拟器/签名；ohosTest 仅编译，`BLOCKED_ON_DEVICE_RUNNER` |
| **CQG-T15/T16 最终意见** | **CHANGES_REQUIRED** | 修复轮 F 项可关闭，但组件整体因 R2-01（阻断）+ R2-02（需处理/书面接受）不能 PASS；C-21/C-22/C-23 保持 `UNVERIFIED` |

---

## 6. 残余风险与跟踪

| 跟踪项 | 风险/内容 | 归属/时机 |
|---|---|---|
| **R2-01 门锁 CLOSE 命令值** | `lock()` 发送 `value=true`；`ControlPolicy` 拒绝；真实锁门不可用；DoorVM Fake 不校验命令值 | implementation-engineer；CQG-T15 前修复 + 补断言 + 重跑 host/build/ohosTest + 复审 |
| **R2-02 跨设备连续控制** | 单一全局 gate；A begin → B begin 后 A 永久 PENDING；与 §10.3.2 独立节流冲突 | implementation-engineer；CQG-T15 前修复或 architect 书面接受 v1 单 active 限制 |
| **F-05 `GATEWAY_CONFIRMED`** | 中间态不可观察；四阶段在可观察状态上只有三段 | T-17/T-18 或后续设计同步；不计入本轮 F 关闭 |
| **U-02 资源键** | `settings.cloud.single_gateway_required` 与 `brand.*` 缺失；i18n 静态检查未捕获常量键 | T-18 资源任务；CQG/Stage Gate 记录 |
| **U-03 端口/字段缺口** | `pinMatched`/`rotationRecommended` 无来源；C-08 `addGatewayToFamily` 契约缺口 | C-18/C-27/C-08 owner；T-17/T-18 |
| **真实设备/真实 BLE/LAN/云** | ohosTest 仅编译；真实三态视觉、10s 门磁、BLE 全流程、云影子、p95 均未执行 | T-19 设备矩阵、T-20 安全评审；本报告不授予 PASS |
| **DoorVM 测试缺口** | FakeControlCoordinator 忽略 `command.value`，4 条门锁负例只验证状态映射 | 随 R2-01 补真实策略/命令值断言 |
| **BLE back/restart 竞态** | `back()` 未 await `stopScan()`；连续 back→startScan 在真实适配器上可能互相干扰；in-flight back 可能重复 `stopScan` | T-17/T-19 真机复核；低风险观察 |
| **TEST-001 状态** | C-21..C-23、SEC-N09/N11/N12/N14/N20/N23 等仍为 `NOT_RUN` | CQG 后由 test-engineer/Orchestrator 更新；不得把本报告当全量测试 PASS |

---

## 7. Verdict 与后续

### 7.1 Verdict

**CHANGES_REQUIRED（组件级，scoped to `e77b192`）**。

- 上轮 F-01..F-04、F-06..F-08 与 U-01 的修复目标：**已关闭/可复核**（F-01/F-02 的限定语义见 §2）。
- **R2-01（High）必须优先修复**：`DoorViewModel.lock()` 的 CLOSE 命令值；否则 CQG-T15 的 C-21 门锁契约不成立。
- **R2-02（Medium）**：修复或由 `solution-architect` 书面接受 v1 单 active 连续控制限制；不得静默保留。
- F-05、U-02、U-03 与设备/真实网络项保持跟踪；C-21/C-22/C-23 不得进入 `STABLE`。
- 本报告不是 Stage Gate、不是用户验收、不授予任何 `STABLE`。

### 7.2 修复后的最低复验

1. R2-01：`lock()` 改发 `value=false`；DoorVM 用例断言实际 `command.value`（或接入真实 `ControlPolicy`/`DeviceCommandRunner`）。
2. R2-02：补跨设备 begin/cancel 用例；若选择单 active 限制，更新 DES-B 并记录 v1 例外。
3. `entry/src/test/run-host-tests.sh`（预期 ≥ 610/610，新增用例全过）；`codelinter`；`hvigorw clean assembleHap`；ohosTest assemble（保留 C-18 import 探针）。
4. 重新执行 `quality-reviewer` 复审（至少覆盖 R2-01/R2-02 与新增测试），再进入 CQG-T15/T16。

### 7.3 独立声明

本报告由未参与 T-15/T-16 实现、测试、实现报告或修复报告编写的 `quality-reviewer` 独立作出。评审期间未修改任何被审产品代码、测试、证据或实现/修复报告；唯一仓库写入为本报告。行为探针在 `node --import` 的内存进程中执行，未在仓库落盘；U-01 编译探针复用仓库内已有的 ohosTest import 与证据日志，原工作区在复验前后保持 clean，HEAD 为 `e77b192`。本报告的 CHANGES_REQUIRED 结论仅针对 `e77b192` 这一被审 revision，不延伸到修复后的 revision 或任何后续 Stage。

---

*复审结束。*
