# T-15 / T-16 复审 R2 修复报告（R2-01 / R2-02）

- **Artifact ID**: IMP-T15-T16-FIX2
- **Producer**: agent:implementation-engineer
- **Task**: `wp-065-fix-vm2`（task 分支 `task/wp-060-vm`，父分支 `feat/yaocore-app`，base `59c27b1`）
- **Date**: 2026-10-18
- **Workflow**: STANDARD / GATED_AUTO
- **Status**: R2-01、R2-02 已修复并完成本地验证；C-21/C-22/C-23 仍为 `UNVERIFIED`，等待 `quality-reviewer` 复审与 CQG-T15/CQG-T16。本报告不宣告 `STABLE`，不是 Stage Gate。
- **Inputs（handoff 冻结）**: `artifacts/70-review/t15-16-review-b.md`（R2-01/R2-02 逐条）、`artifacts/50-implementation/t15-16-fix-report.md`、DES-001B（§10.1.3/§10.1.7/§10.3.2/§10.3.3）、`artifacts/60-testing/test-plan.md`、`entry/src/test/run-host-tests.sh`。
- **不改变**: D-009/D-010/D-013/D-022/D-023、R-1、F-08 GUEST、三态与 55ms 节流主语义（per-key 为契约扩展）、U-01 编译修复。

## 1. 结论摘要

| 项 | 严重度 | 处置 | 状态 |
|---|---|---|---|
| R2-01 `DoorViewModel.lock()` 发送 `CLOSE=true`，被真实 `ControlPolicy` 拒绝 | High（阻断 CQG-T15） | `lock()` 改发 `CLOSE=false`；补 Fake `command.value` 断言 + 真实 `ControlPolicy` 集成用例 | **FIXED（本地验证）** |
| R2-02 `DeviceViewModel` 单一全局 `ThrottleGate`，跨设备 begin 使旧设备永久 `PENDING` | Medium | 改为 per-key（per-device）gate/session；旧 key 会话清理；补跨设备 begin/cancel 回归 | **FIXED（本地验证）** |
| F-05 `GATEWAY_CONFIRMED` 不可观察 | Low | 不在本轮范围 | OPEN（跟踪） |
| U-02/U-03 | Low/Info | 不在本轮写范围 | DEFERRED（T-17/T-18） |

## 2. R2-01：门锁 CLOSE 命令值

### 2.1 根因

`DoorViewModel.lock()` 调用 `applyLock(DeviceAction.CLOSE, true)`，构造 `CLOSE` 命令时写入 `value=true`。C-17 `ControlPolicy.validateValue`（`GatewayRequestPolicy.ets`）对布尔动作计算 `expected = action===TURN_ON || action===OPEN || action===BOARD_LED_ON`；`CLOSE` 的期望值为 `false`，因此 `CLOSE=true` 在任何真实传输前即被 `PROTOCOL_VALUE_OUT_OF_RANGE` 拒绝。生产路径上“锁门”永远进入 `REVERT`；既有 DoorVM Fake 不校验命令值，未暴露该缺陷。

### 2.2 实现

`entry/src/main/ets/viewmodel/DoorViewModel.ets`：

```ts
async lock(): Promise<void> {
  // R2-01 / DES-B §10.1.7: CLOSE carries boolean `false`; C-17
  // ControlPolicy rejects CLOSE=true with PROTOCOL_VALUE_OUT_OF_RANGE.
  await this.applyLock(DeviceAction.CLOSE, false);
}
```

`unlock()` 保持 `OPEN=true`，与 `DeviceViewModel.closeDoor` 的既有 `CLOSE=false` 约定一致。未改 `applyLock`、tracker 或三态语义。

### 2.3 回归

`entry/src/test/host/ViewModelDoorVM.test.mjs`：

1. `T15_DoorView_lockWithGatewayMergedReachesSecuredAndCommitted` 增加
   `assert.equal(h.control.calls[0].command.value, false)`，直接锁定 Fake 收到的真实命令值。
2. 新增 `T15_DoorView_lockCommandPassesRealControlPolicy`：
   - 包装 `FakeControlCoordinator.execute`，在委托前调用**真实** `ControlPolicy.validate(DeviceType.DOOR, true, command.action, command.value)`，与 `DeviceCommandRunner`/`LocalGatewayService` 生产预检一致；
   - `lock()` 必须在策略下成功，断言实际命令为 `CLOSE/false`、门态 `SECURED`、控制态 `COMMITTED`；
   - 显式断言 `ControlPolicy.validate(..., CLOSE, false)` accepted、`CLOSE, true` 抛 `PROTOCOL_VALUE_OUT_OF_RANGE`。

该用例在修复前会因策略拒绝导致 `calls.length=0` 且 VM 进入 `REVERT`，故能真实捕获 R2-01。

## 3. R2-02：按设备隔离连续控制节流

### 3.1 根因

`DeviceViewModel` 仅持有单个 `gate/gateKey/gateAction/gateMin/gateMax/gateLast*`。`beginContinuous(keyB)` 先 `cancelContinuous(keyB)`，该调用无条件 `dispose` 当前 gate（可能属于 keyA）并清空全局 `gateKey`；随后只把 keyB 置 `PENDING`。keyA 的 `ControlUiState` 停留在 `PENDING` 且已无存活 gate/定时器，违反 DES-B §10.3.2“不同设备各自独立节流”。

### 3.2 实现（采用 per-key 方案）

`entry/src/main/ets/viewmodel/DeviceViewModel.ets`：

- 新增私有 `ContinuousSession`：`action/min/max/token/gate/lastOk/lastExecution/lastError`，每个设备 key 独占一份。
- 用 `Map<string, ContinuousSession> sessions`（key = `DeviceKey.globalId()`）替换全部全局 gate 字段；`gateGeneration` 只用于生成全局唯一会话 token。
- `beginContinuous(key, ...)`：
  - 仅取消**该 key** 的旧会话；
  - 创建该 key 的 `ThrottleGate`，dispatch 闭包携带 `(key, token)`；
  - 其他设备会话及其 gate/在途 dispatch 完全不受影响。
- `updateContinuous(key, ...)`：仅当该 key 存在会话时生效，使用该会话的 `action/min/max`，不再读取其他设备的全局状态。
- `endContinuous(key, ...)`：
  - 捕获该 key 的会话；`onCommit` 返回后仅当 `sessions.get(id) === session` 才发布 `COMMITTED/REVERT`；随后删除该会话（旧 key 清理）；
  - 无会话时回退到该 key 最近一次连续 action（`continuousActions`），不再复用其他设备的 `gateAction`。
- `cancelContinuous(key)`：只 dispose/删除该 key 的会话并把该 key 置 `IDLE`；不影响其他设备。
- `dispatchContinuous(key, token, value)`：入口与 `await execute` 后均通过 `currentSession(key, token)` / 会话对象身份校验；旧会话、cancel、dispose、同 key 新 begin 的晚到结果被丢弃。F-01 语义保留，且不再跨设备误伤。
- `dispose()`：dispose 并清空所有会话的 gate。

保留项：55ms 合并、1 在途、latest 不丢、TouchUp 最终值、三态 PENDING/COMMITTED/REVERT、3s 超时/320ms 回弹、单命令路径均未改变。

### 3.3 回归

`entry/src/test/host/ViewModelDevice.test.mjs` 新增 2 条：

1. `T15_Device_crossDeviceContinuousSessionsAreIndependent`：
   - A begin → B begin 后，A 与 B 均为 `PENDING`（A 不残留失效会话）；
   - B begin 后 A 仍可 `updateContinuous`，dispatch 目标为 `dev-a`、值 60；
   - A `endContinuous` 后 A `COMMITTED/confirmed=60`，B 仍 `PENDING`；
   - B 随后 update/end 正常 `COMMITTED/confirmed=75`。
2. `T15_Device_cancelOnOneDeviceKeepsAnotherSessionAlive`：
   - A begin → B begin → cancel B；A 仍 `PENDING`、B `IDLE`；
   - A 仍可 update/end 并 `COMMITTED`，证明取消一个设备不会清除另一设备会话。

既有 F-01 用例（cancel-in-flight、new-begin 旧结果、cancel/end 并发）全部继续通过。

## 4. 不改变项核对

| 约束 | 结论 |
|---|---|
| D-009/D-010/D-013/D-022/D-023 | 未修改相关文件或语义 |
| R-1 `credentialDraftId` | 未触及 `BleProvisioningViewModel` |
| F-08 GUEST | 未触及能力派生/控制矩阵 |
| 三态 / 55ms 主语义 | 仅将会话状态由全局改为 per-key；PENDING/COMMITTED/REVERT、55ms、TouchUp、超时回弹不变 |
| U-01 C-18 编译修复 | 未修改；ohosTest 编译仍含 C-18 import 探针并通过 |
| 写范围 | 仅 `entry/src/main/ets/viewmodel/`、`entry/src/test/`、`artifacts/50-implementation/` |

## 5. 验证（实际执行，cwd = 仓库根）

```bash
ohpm install
hvigorw clean assembleHap --no-daemon
codelinter -c code-linter.json5 -p default .
entry/src/test/run-host-tests.sh
# 附加（handoff 要求 ohosTest 编译）：
hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon
```

| 命令 | 结果 | 证据 |
|---|---|---|
| `ohpm install` | exit 0，`install completed` | `entry/src/test/evidence/t15-16-fix2-ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | **BUILD SUCCESSFUL**，exit 0（35 tasks） | `entry/src/test/evidence/t15-16-fix2-clean-assemble.log` |
| `codelinter -c code-linter.json5 -p default .` | **No defects found in your code**，exit 0 | `entry/src/test/evidence/t15-16-fix2-codelinter.log` |
| `entry/src/test/run-host-tests.sh` | **613 tests / 613 pass / 0 fail / 0 skipped / 0 todo**，exit 0 | `entry/src/test/evidence/t15-16-fix2-host-node-tests.tap` |
| ohosTest `assembleHap` | **BUILD SUCCESSFUL**，exit 0（35 tasks） | `entry/src/test/evidence/t15-16-fix2-ohosTest-assemble.log` |

- 测试数如实统计：610 → **613**（新增 3 条：Door 策略集成 1、跨设备连续控制 2）；既有 610 条全部保留通过。
- ohosTest/设备仍为 `COMPILED_ONLY` / `BLOCKED_ON_DEVICE_RUNNER`：无设备/模拟器/签名，不把编译成功写成设备 PASS。
- `codelinter` 覆盖产品源码；host 测试由 Node runner 执行，ohosTest 由编译覆盖。

## 6. 变更文件

```text
entry/src/main/ets/viewmodel/DeviceViewModel.ets
entry/src/main/ets/viewmodel/DoorViewModel.ets
entry/src/test/host/ViewModelDevice.test.mjs
entry/src/test/host/ViewModelDoorVM.test.mjs
entry/src/test/evidence/t15-16-fix2-ohpm-install.log
entry/src/test/evidence/t15-16-fix2-clean-assemble.log
entry/src/test/evidence/t15-16-fix2-codelinter.log
entry/src/test/evidence/t15-16-fix2-host-node-tests.tap
entry/src/test/evidence/t15-16-fix2-ohosTest-assemble.log
artifacts/50-implementation/t15-16-fix2-report.md
```

## 7. 决策、假设与残余风险

**决策**

1. R2-01 直接修正 `lock()` 的命令值，不在 VM 层复制策略；真实策略仍由 C-10/C-17 执行，测试用真实 `ControlPolicy` 包装 Fake 以验证生产预检路径。
2. R2-02 选择评审首选的 per-key 方案，而非 v1 单 active 限制；无需修改 DES-B 契约文字，符合 §10.3.2“不同设备各自独立节流”。
3. F-01 代际校验保留，但归属改为“key + 会话对象身份”；`gateGeneration` 仅保证 token 唯一，不承担跨设备全局失效。

**假设**

- 生产 `DeviceCommandRunner`/`LocalGatewayService` 在发送前调用同一 `ControlPolicy.validate`，因此 DoorVM 集成用例与实际预检等价。
- `DeviceViewModel` 是多设备列表 VM，可能同时存在多个设备的连续控制会话；单设备页面 `ClimateViewModel` 的单一 gate 语义不在本轮范围。

**残余风险 / 未决**

- F-05 `GATEWAY_CONFIRMED` 仍不可观察（跟踪，不在本轮）。
- U-02 资源键、U-03 `pinMatched`/`rotationRecommended`/`addGatewayToFamily` 仍按 T-17/T-18 跟踪。
- 真实设备/真实 BLE/LAN/云、三态动画与 p95 未验证，保持 `UNAVAILABLE/BLOCKED`；真实 TouchUp 时序仍由 T-19 设备矩阵复核。
- 跨设备并发连续控制目前仅 host 级验证；UI 是否为每设备页创建独立 VM 实例（C-28）不影响本类的多 key 契约。

**结论**：R2-01、R2-02 已修复，610 条既有 host 用例全部保留并通过（现 613/613），clean assemble、codelinter、ohosTest 编译均通过。C-21/C-22/C-23 保持 `UNVERIFIED`，下一步交 `quality-reviewer` 复审（至少覆盖 R2-01/R2-02 与新增回归），再进入 CQG-T15/CQG-T16。
