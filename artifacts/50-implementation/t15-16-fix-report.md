# T-15 / T-16 评审修复报告（F-01..F-04、F-06..F-08、U-01）

- **Artifact ID**: IMP-T15-T16-FIX
- **Producer**: agent:implementation-engineer
- **Task**: `wp-063-fix-vm`（task 分支 `task/wp-060-vm`，父分支 `feat/yaocore-app`，base `1e7487e`）
- **Date**: 2026-10-18
- **Workflow**: STANDARD / GATED_AUTO
- **Status**: 修复与本地验证完成；C-21/C-22/C-23 仍为 `UNVERIFIED`，等待 `quality-reviewer` 复审与 CQG-T15/CQG-T16。本报告不宣告 `STABLE`、不是 Stage Gate。
- **Inputs（handoff 冻结）**: `artifacts/70-review/t15-16-review.md`、`artifacts/50-implementation/t15-16-vm.md`、DES-001B（§0.7/§3/§10/§11/§12）、DES-001A、contract-baseline、project-constraints、TEST-001、`entry/src/test/run-host-tests.sh`。
- **裁定依据**: `1e7487e docs(design): 裁定成员加入完成状态语义`（DES-B §0.7、`EXT-DES-B-27`）。
- **不改变**: D-009/D-010/D-013/D-022/D-023、R-1、F-08 GUEST 语义、三态/55ms 节流主语义（除本报告列出的缺陷修复）。

## 1. 结论摘要

| 项 | 严重度 | 处置 | 状态 |
|---|---|---|---|
| F-01 连续控制 cancel/supersede 后晚到结果写回 | High | 修复 + 竞态负例 | **FIXED（本地验证）** |
| F-02 门锁把控制 ACK 当门状态确认 | High | 修复 + 四类负例 | **FIXED（本地验证）** |
| F-03 配网 `back()` 未停扫描/清 10s 定时器 | Medium | 修复 + 竞态负例 | **FIXED（本地验证）** |
| F-04 Settings Token 过期不刷新 `state.cloud` | Medium | 修复 + 正/负例 | **FIXED（本地验证）** |
| F-06 C-08/C-22 `COMPLETED` 定义冲突 | Low（裁定） | 按 §0.7 修复 | **FIXED（本地验证）** |
| F-07 加入部分失败重试/`needsUnlock` | Low（裁定） | 按 §0.7 修复 | **FIXED（本地验证）** |
| F-08 缺少 F-01..F-04 负例 | Low | 新增 17 条回归 | **FIXED（本地验证）** |
| U-01 C-18 `GatewayDiscoveryService` 编译阻断 | High（上游） | 修复 + 持久编译探针 | **FIXED（本地验证）** |
| F-05 `GATEWAY_CONFIRMED` 不可观察 | Low | 不在本轮裁定/任务范围 | **OPEN（跟踪）** |
| U-02 `settings.cloud.single_gateway_required` 资源键 | Low | 不在本轮写范围 | **DEFERRED（T-18）** |
| U-03 `pinMatched`/`rotationRecommended`/`addGatewayToFamily` | Info | 不在本轮写范围 | **DEFERRED（T-17/T-18）** |

## 2. 逐项修复

### 2.1 F-01：连续控制会话代际（Device / Climate）

**根因**：`beginContinuous` 把 `token` 传入 `dispatchContinuous`，但后者从未校验；`cancelContinuous` 只销毁 gate 并发布 `IDLE`，在途 `execute` 晚到成功后仍重新写入 `PENDING`。`endContinuous` 在 `await gate.onCommit` 后没有确认会话是否已被取消/替换。

**实现**（`viewmodel/DeviceViewModel.ets`）：

- 新增 `gateToken` 会话代际；`beginContinuous` 在取消旧门后捕获当前代际，dispatch 闭包携带该代际。
- `dispatchContinuous` 在入口与 `await control.execute` 返回后都校验 `disposed / gate 实例 / gateToken / gateKey`；不匹配直接丢弃，不写 `gateLastOk`、不发布 `PENDING`。
- `cancelContinuous` 递增 `gateToken`，使所有在途 dispatch 失效；`dispose` 同样递增。
- `endContinuous` 捕获 `gate + sessionToken`；`onCommit` 返回后仅当两者仍匹配才发布 `COMMITTED/REVERT`，随后递增代际。`cancel` 与 `end` 并发时 `cancel` 先发布 `IDLE`，`end` 恢复后直接返回。
- `ClimateViewModel.beginTemperature/dispatchTemperature/endTemperature/disposeGate` 采用相同代际校验；`endTemperature` 不再允许旧的温度结果覆盖新会话。

**回归**（`ViewModelDevice.test.mjs`、`ViewModelClimate.test.mjs`、`ViewModelThrottle.test.mjs`）：

- `T15_Device_cancelWhileDispatchInFlightDropsLateSuccess`：延迟 dispatch → cancel → resolve，保持 `IDLE`、无乐观值/确认值。
- `T15_Device_newBeginInvalidatesAnOlderDispatchResult`：旧会话结果不得覆盖新会话的 `PENDING/optimisticValue`。
- `T15_Device_cancelRacingEndCommitNeverPublishesCommitted`：cancel 与 end 并发，最终 `IDLE`，不出现 `COMMITTED`。
- `T15_Climate_newBeginDropsAnOlderInFlightTemperatureResult`：温度旧结果被丢弃，新会话最终 `COMMITTED=26`。
- `T15_Throttle_commitBefore55msSendsFinalValueImmediately`、`T15_Throttle_cancelWithWaiterResolvesWithoutExtraDispatch`。

### 2.2 F-02：门锁控制 ACK ≠ 门状态确认

**根因**：`DoorViewModel.applyLock` 用控制层 `succeeded()` 判定成功后，CLOSE 只让 tracker 记录结果但仍无条件发布 `COMMITTED`；unlock 无条件 `markUnlocked()`，把 `UNVERIFIED`/无 reported `open` 写成 `OPEN`。`DoorConfirmationTracker.markUnlocked()` 本身不读任何门态证据。

**实现**（`viewmodel/DoorViewModel.ets`、`viewmodel/core/DoorConfirmationTracker.ets`）：

- 删除无证据的 `markUnlocked()`，新增 `onUnlockResult(execution)`：
  - reported `open === true` → `DoorStage.OPEN / DoorLockState.OPEN`；
  - reported `open === false` → `FAILED / UNCONFIRMED` + `ACK_STATE_MISMATCH`（不得显示 OPEN）；
  - 无 reported `open` → `UNVERIFIED`，保留上一确认 `lockState`，不显示 OPEN；
  - ACK 拒绝/错误/MISMATCH → `FAILED`。
- `DoorViewModel.applyLock` 改为由 tracker 的门结果驱动控制态：tracker `FAILED` → `REVERT`（使用 tracker 的 `ACK_STATE_MISMATCH`/错误）；CLOSE 的 `UNVERIFIED`（明确无回报）允许 `COMMITTED` 作为“已执行、状态未回传”；`SECURED/WAITING_CONTACT` → `COMMITTED`；任何路径都不把 `UNVERIFIED` 写成 `OPEN`。
- CLOSE 的 `ackAccepted && reported open === true` 由 tracker 判为 `FAILED/OPEN`，VM 必须 `REVERT`，不得 `COMMITTED`。

**回归**（`ViewModelDoorVM.test.mjs`，新增 4 条）：

- `T15_DoorView_unlockWithNoReportedOpenIsUnverifiedNotOpen`
- `T15_DoorView_unlockWithReportedClosedIsARejectedAttempt`
- `T15_DoorView_closeWithReportedOpenStillRevertsEvenWhenAckSucceeded`
- `T15_DoorView_closeWithoutReportedOpenStaysUnverifiedAndNeverOpen`

### 2.3 F-03：配网 `back()` 清理扫描

**实现**（`viewmodel/BleProvisioningViewModel.ets`）：

- 新增 `scanGeneration`。`startScan` 在 `await ble.startScan` 后校验代际/step；若已 back/cancel/dispose，清定时器并 `stopScan()` 后返回，不安装晚到定时器。
- 10s 定时器回调同样校验代际与 step。
- `back()` 从 `STEP_1_SCAN` 先递增代际、`clearScanTimer()`、调用 `stopScan()`，再发布 `STEP_0/IDLE`；不再允许 10s 后跳回 `STEP_1` 或报 `PROVISIONING_DEVICE_NOT_FOUND`。
- `cancel()`/`dispose()`/`stopScan()` 递增代际；`onScanError` 在非 `STEP_1` 时忽略晚到错误。

**回归**（`ViewModelBle.test.mjs`）：

- `T16_Ble_backFromScanStopsScanAndDropsTheTenSecondTimer`：`stopScan` 调用 1 次、timer pending=0、推进 10s 无错误且仍为 STEP_0。
- `T16_Ble_backDuringStartScanCannotInstallLateTimer`：`startScan` 未返回时 back，释放后也不安装定时器。

### 2.4 F-04：Settings Token 过期同步持久层

**实现**（`viewmodel/SettingsViewModel.ets`）：

- `testCloudConnection` 在 `result.valid === false` 时重新 `loadCloud()` 并发布 `state.cloud`（失败仅记录警告、保留旧视图）。
- 新增私有 `cloudState()` 统一构造状态，成功分支复用。
- 网络类失败不主动改写云状态；只有 C-15 已记录的 `TOKEN_EXPIRED/TOKEN_INVALID` 会体现在 `state.cloud.state`。

**回归**（`ViewModelSettings.test.mjs`）：

- `T16_Settings_testConnectionSuccessRefreshesAndFailureMapsTokenError` 增加断言：失败后 `state.cloud.state === 'TOKEN_EXPIRED'`。
- 新增 `T16_Settings_networkTestFailureDoesNotDowngradeCloudState`：`CLOUD_REQUEST_FAILED` 后仍保持 `CONFIGURED`。

### 2.5 F-06 / F-07：成员加入完成语义（按 `1e7487e` / DES-B §0.7）

**实现**：

- `service/family/FamilyModels.ets`：
  - `FamilyJoinPhase` 新增 `MEMBER_BOUND`；
  - `FamilyProfileRef` 增加 `memberId`（`EXT-DES-B-27` 允许的内部 seam 增量，用于精确成员校验）。
- `service/family/FamilyJoinSession.ets`：
  - `submitInvitation` 成功终态改为 `MEMBER_BOUND`，保存 `AcceptedInvitation` 与原文；同一容器在 `MEMBER_BOUND/COMPLETED` 幂等返回，不同容器抛 `INVITE_INVALID` 且不改变阶段/`accepted`；
  - 新增 `markProfileBound()`，是唯一 `COMPLETED` 写入点；前置校验 `MEMBER_BOUND`、成员 ACTIVE、`(familyId, memberId)` 精确档案、active family 匹配；失败抛 `CONFIGURATION_ERROR` 并保持 `MEMBER_BOUND + accepted`；已 `COMPLETED` 幂等；
  - `cancel()` 在 `MEMBER_BOUND/COMPLETED` 为 no-op，不调用 `discardJoinRequest`；
  - `start()` 在终态拒绝；`dispose()` 清理内存中的 accepted。
- `viewmodel/FamilyViewModel.ets`：
  - `completeJoinWithProfile` 固定顺序：`createProfile → switchFamily → 发布 needsUnlock → markProfileBound → appContext.lock() → refreshSessionGate() → refresh()`；
  - `AUTH_PROFILE_EXISTS` 仅当 `(familyId, memberId)` 已有同成员档案时视为幂等继续（通过 `AuthService.listProfiles` 复核），否则原样抛出；不重置密码；
  - `switchFamily` 的 `requiresUnlock` 写入 `needsUnlock`；失败时按 `getActiveFamily()`/`getActiveSession()` 不变量重算，保留 `accepted`/`MEMBER_BOUND` 与错误，允许重试；
  - `startJoin` 在 `MEMBER_BOUND` 拒绝且不 `disposeJoin()`；`cancelJoin` 在终态拒绝；不同容器提交时仍发布 `INVITE_INVALID` 错误。
- 测试夹具：`FakeJoinSession` 改为 `submit → MEMBER_BOUND`、`markProfileBound → COMPLETED`；`FakeFamilyAuth.createProfile` 对重复 `(familyId, memberId)` 抛 `AUTH_PROFILE_EXISTS` 并支持 `listProfiles`；`FakeFamilyWorkflow` 支持一次性 switch 失败。

**回归**：

- `T16_Family_joinStateMachineAndProfileCompletion`（更新旧“submit 即 COMPLETED”期望）：`submit → MEMBER_BOUND`；完成后 `COMPLETED`、profile 唯一、`lock/refreshSessionGate` 各 1 次、`needsUnlock=true`。
- `T16_Family_joinPartialFailureKeepsMemberBoundAndRetriesViaProfileExists`：createProfile 成功 + switchFamily 失败 → 保持 `MEMBER_BOUND+accepted+error`；重试遇 `AUTH_PROFILE_EXISTS` 幂等继续 → `COMPLETED`，profile 数不增。
- `T16_Family_joinTerminalPhasesRejectStartCancelAndOtherContainers`：`MEMBER_BOUND` 下拒绝 start/cancel、不同容器 `INVITE_INVALID`，`accepted` 保留。
- C-08 host（`DomainFamily.test.mjs`）：`T15_C08_memberBoundIsIdempotentRejectsOtherContainerAndCancelNoop`、`T15_C08_markProfileBoundRequiresActiveMemberAndAcceptedFamily`；原 join 用例改为 `MEMBER_BOUND → markProfileBound → COMPLETED`。
- C-13 host（`InviteService.test.mjs`）：真实 `FamilyJoinSession` 驱动链改为 `MEMBER_BOUND → markProfileBound → COMPLETED`。

### 2.6 U-01：C-18 `GatewayDiscoveryService` 编译阻断

**复现**：在 `ViewModelsDevice.test.ets` 加入 `GatewayDiscoveryService` import 后，ohosTest 编译 exit 255，报两个 `arkts-no-structural-typing`：`GatewayDiscoveryService.ets:331:18` 与 `:344:18`。

**根因**：`withProbeTimeout` 的 Promise executor 将 `reject` 显式声明为 `(reason: Error) => void`，但两个调用传入 `AppError`（`AppErrors.transport(...)` / `asAppError(...)`）。ArkTS 在结构化回调参数位置拒绝该赋值。

**修复**：将 `reject` 声明为 `(reason: AppError) => void`（保持错误码语义，不把 `AppError` 包成通用 `Error`），并保留注释说明 U-01。

**编译探针**：`entry/src/ohosTest/ets/test/viewmodel/ViewModelsDevice.test.ets` 持久 import 并断言 `GatewayDiscoveryService !== undefined`，确保该类不会被未引用裁掉。修复后 ohosTest `assembleHap` **BUILD SUCCESSFUL**。

**证据**：

- 修复前：`evidence/t15-16-fix-u01-probe-before.log`（exit 255，两处 structural typing）。
- 修复后：`evidence/t15-16-fix-u01-probe-after.log`、`evidence/t15-16-fix-ohosTest-assemble.log`（BUILD SUCCESSFUL）。

### 2.7 F-08：回归测试补齐

本轮新增 **17** 条 host 用例（610 - 593）：

| 文件 | 新增 | 覆盖 |
|---|---:|---|
| `ViewModelDevice.test.mjs` | 3 | cancel-in-flight、new-begin 旧结果、cancel/end 并发 |
| `ViewModelClimate.test.mjs` | 1 | 温度在途代际 |
| `ViewModelThrottle.test.mjs` | 2 | commit-before-55、cancel-with-waiter |
| `ViewModelDoorVM.test.mjs` | 4 | unlock UNVERIFIED/open=false、CLOSE open=true/无回报 |
| `ViewModelBle.test.mjs` | 2 | back 停扫/定时器、晚到 startScan |
| `ViewModelSettings.test.mjs` | 1 | 网络失败不降级云状态（token 过期断言并入原用例） |
| `ViewModelFamily.test.mjs` | 2 | 部分失败重试、终态拒绝 |
| `DomainFamily.test.mjs` | 2 | C-08 MEMBER_BOUND 幂等/终态/cancel、markProfileBound 前置 |

## 3. 验证（实际执行，cwd = 仓库根）

```bash
ohpm install
hvigorw clean assembleHap --no-daemon
codelinter -c code-linter.json5 -p default .
entry/src/test/run-host-tests.sh
# 附加：ohosTest 编译（含 C-18 编译探针）
hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon
```

| 命令 | 结果 | 证据 |
|---|---|---|
| `ohpm install` | exit 0，`install completed in 0s` | `evidence/t15-16-fix-ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | **BUILD SUCCESSFUL**，exit 0 | `evidence/t15-16-fix-clean-assemble.log` |
| `codelinter -c code-linter.json5 -p default .` | **No defects found in your code**，exit 0 | `evidence/t15-16-fix-codelinter.log` |
| `entry/src/test/run-host-tests.sh` | **610/610 PASS**，0 fail / 0 skipped / 0 todo，exit 0 | `evidence/t15-16-fix-host-node-tests.tap` |
| ohosTest `assembleHap` | **BUILD SUCCESSFUL**，exit 0 | `evidence/t15-16-fix-ohosTest-assemble.log` |

- 测试数如实统计：本轮 610（首轮 593 + 本轮 17）；T-15/T-16 合计 105 条 host 用例。
- ohosTest 仍为 `COMPILED_ONLY` / `BLOCKED_ON_DEVICE_RUNNER`：无设备/模拟器/签名，未执行设备用例，不把编译成功写成设备 PASS。
- `codelinter` 仅覆盖产品源码；测试由 host runner 与 ohosTest 编译覆盖。

## 4. 变更文件

```text
entry/src/main/ets/service/family/FamilyJoinSession.ets
entry/src/main/ets/service/family/FamilyModels.ets
entry/src/main/ets/service/gateway/GatewayDiscoveryService.ets
entry/src/main/ets/viewmodel/BleProvisioningViewModel.ets
entry/src/main/ets/viewmodel/ClimateViewModel.ets
entry/src/main/ets/viewmodel/DeviceViewModel.ets
entry/src/main/ets/viewmodel/DoorViewModel.ets
entry/src/main/ets/viewmodel/FamilyViewModel.ets
entry/src/main/ets/viewmodel/SettingsViewModel.ets
entry/src/main/ets/viewmodel/core/DoorConfirmationTracker.ets
entry/src/ohosTest/ets/test/viewmodel/ViewModelsDevice.test.ets
entry/src/ohosTest/ets/test/README.md
entry/src/test/host/DomainFamily.test.mjs
entry/src/test/host/InviteService.test.mjs
entry/src/test/host/ViewModelBle.test.mjs
entry/src/test/host/ViewModelClimate.test.mjs
entry/src/test/host/ViewModelDevice.test.mjs
entry/src/test/host/ViewModelDoorVM.test.mjs
entry/src/test/host/ViewModelFamily.test.mjs
entry/src/test/host/ViewModelSettings.test.mjs
entry/src/test/host/ViewModelThrottle.test.mjs
entry/src/test/host/viewmodel-admin-helpers.mjs
entry/src/test/README.md
entry/src/test/evidence/t15-16-fix-*（5 个验证日志 + 2 个 U-01 探针日志）
artifacts/50-implementation/t15-16-fix-report.md
```

## 5. 决策、假设与残余风险

**决策**

1. F-02 的 unlock 无 reported `open` 采用 `UNVERIFIED`（保留上一确认 lockState），控制态允许 `COMMITTED` 作为“已执行、状态未回传”；reported `open=false` 采用 `FAILED + REVERT`，不显示 OPEN。CLOSE 的 `UNVERIFIED` 同样 `COMMITTED`，但门态不得为 OPEN/SECURED。
2. F-01 用 VM 层会话代际（`gateToken`）而不是依赖 `ThrottleGate` 的 generation，因为 VM 在 gate 之外还写 `controls`/`gateLast*`；两层代际同时保留。
3. F-06/F-07 严格按 `1e7487e`：C-08 不创建档案、不发布 `COMPLETED`；`FamilyProfileRef.memberId` 是裁定允许的内部 seam 增量，不改冻结方法签名。
4. U-01 选择显式 `reject: (reason: AppError) => void`，保持 `AppError` 错误码，不改为通用 `Error`。

**假设**

- 生产 `CloudService.getState()` 在 `testConnection` 401/403 后已按 T-14 F-03 记录 `TOKEN_EXPIRED/TOKEN_INVALID`；VM 只负责重新读取并发布。
- `FamilyService.switchFamily` 的成功结果包含 `requiresUnlock`；失败可能发生在 `auth.lockAll()` 之后，因此失败分支按 Session 不变量重算 `needsUnlock`。
- 无设备环境，ohosTest 只能提供编译证据；真实 BLE/LAN/云/门磁时序仍由 T-19 执行。

**残余风险 / 未决**

- **F-05**：`DoorStage.GATEWAY_CONFIRMED` 仍不可观察；不在本轮裁定/修复范围，保持 OPEN。
- **U-02**：`settings.cloud.single_gateway_required` 与 `brand.*` 资源键仍缺失，T-18 补。
- **U-03**：`pinMatched`/`rotationRecommended` 仍无来源；`FamilyRepository.addGatewayToFamily` 与 C-08 契约缺口仍由 T-17/T-18 处理。
- 真实设备、真实 BLE/LAN/云、三态动画、p95 性能均未在本轮验证，保持 `UNAVAILABLE/BLOCKED`。
- `FamilyJoinSession` 的 `markProfileBound` 依赖 `getActiveFamily()`；若 C-22 在 `switchFamily` 失败后重试，必须确保 active family 已正确设置——当前由 `FamilyService.switchFamily` 的既有语义保证。

**结论**：F-01/F-02/F-03/F-04/F-06/F-07/F-08 与 U-01 已按裁定与评审建议修复，本地 build/test/lint/ohosTest 编译均通过；C-21/C-22/C-23 保持 `UNVERIFIED`，下一步交 `quality-reviewer` 复审（至少覆盖 F-01/F-02 与新回归），再进入 CQG-T15/CQG-T16。
