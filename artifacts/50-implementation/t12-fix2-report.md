# T-12 复审收窄修复报告（R2-01 / R2-03 / R2-04 / R2-02 / R2-05）

- **Artifact ID**: IMP-T12-FIX2-001
- **Producer**: agent:implementation-engineer
- **Type**: Implementation Fix Report / Handoff
- **Status**: READY_FOR_REVIEW
- **Date**: 2026-10-17
- **Task**: `wp-044-fix-t12b`（task 分支 `task/wp-040-ble`，父分支 `feat/yaocore-app`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`（Component Quality Gate 前）
- **Base revision**: `1eae08c1b60db4099e093d902cfeb3b5bfc926a2`（含 `a6a3053` 修复与 `REV-T12-002` 复审报告）
- **Inputs**: `artifacts/70-review/t12-review-b.md`（REV-T12-002）、`artifacts/50-implementation/t12-fix-report.md`、`artifacts/50-implementation/t12-ble.md`、DES-A §16、ADR-002、`contract-baseline.md`、`project-constraints.md`、`test-plan.md`、BLE 设计；handoff pin 9/9 一致。
- **Write scope**: `entry/src/main/ets/service/`、`entry/src/test/`、`artifacts/50-implementation/`（未修改 `module.json5`、model、DES/ADR、其他 Stage 产物）

---

## 1. 结论摘要

按 `REV-T12-002` 逐条处置：**R2-01（Medium，阻断）已收窄**，写重试现在只发生在平台**确认写未受理**的 busy（`2900011`/`2901004`），`2900099`、无数字码/未知写失败与无标记的 `GATT_BUSY` 一律不重试。R2-03/R2-04/R2-02/R2-05 均已按任务要求处理。

新增 **2 条** host 用例（451 = 449 + 2）：

- `C19_GattChannel_ambiguousWriteFailureIsNotRetried`（R2-01 负例，含 4 个变体：`ble:2900099`、无标记 `GATT_BUSY`、无数字码未知错误、`ble:2900001` fallback）。
- `C19_ProtobufReader_rejectsNonCanonicalLengthVarint`（R2-04，10 字节零长度与 2 字节 overlong 零长度均拒绝）。

四项规定命令及 ohosTest 编译全部实际执行并通过（exit 0）。Security1 冻结向量语义、秘密清零、身份 fail-closed、探针 gatewayId 严格一致、F-01..F-11 已关闭行为均未改变（仅 F-04 按 R2-01 收窄）。

---

## 2. 逐条处置

### 2.1 R2-01（Medium，阻断）：写重试只允许确认 busy

**采用复审建议 A + B 的组合**：适配器只对确认 busy 生成可重试信号，通道侧再做一次显式判定，双重保证不会因 fallback 映射而重发未确认送达的密文。

**适配器映射**（`entry/src/main/ets/service/ble/adapters/OhosBleTransport.ets`）：

- 新增 `mapWriteError()`；`writeCharacteristic` 的 catch 改为调用它。
- `2900011`（GATT busy）/`2901004`（connection congested）→ `PROVISIONING_GATT_BUSY`，并携带显式标记 `NameValue('retryable', 'write-busy')`（由 `BleSupport.confirmedWriteBusy()` 构造）。
- `2900099 Operation failed`、`2900001 Service stopped`、`2901005..2901007`、无数字码/未知写失败 → `mapBleError(error, 'PROVISIONING_GATT_INCOMPLETE')`：
  - `2900099` 等未知码 → `PROVISIONING_GATT_INCOMPLETE` + `field=ble:<code>`；
  - 无数字码 → `PROVISIONING_GATT_INCOMPLETE`（无 details）；
  - `2901003`/权限/蓝牙关闭仍按既有 `mapBleError` 映射为 `PROVISIONING_CONNECT_FAILED` / `PROVISIONING_PERMISSION_DENIED` / `PROVISIONING_BLUETOOTH_OFF`。
- **不再有任何非 busy 写失败被映射为 `PROVISIONING_GATT_BUSY`**；`readCharacteristic` 的映射保持不变（读失败本身是终止路径，服务清理会话，不存在重发）。

**通道判定**（`entry/src/main/ets/service/ble/GattChannel.ets`）：

- 新增共享判定 `BleSupport.isConfirmedWriteBusy(error)`：仅当 `code === PROVISIONING_GATT_BUSY` **且** details 含 `retryable=write-busy` 时返回 true。
- `GattChannel.writeRead` 的写重试条件从 `isCode(..., 'PROVISIONING_GATT_BUSY')` 收窄为 `isConfirmedWriteBusy(typed)`。
- 无标记的 `GATT_BUSY`（例如队列超时、其他端口实现）不会被当作确认 busy；安全请求的重试仍复用 `writeRead` 内同一 `encrypted` 帧，**不重新加密、不推进 CTR**。
- 错误向上抛出后由既有 `BleProvisioningService` catch/finally 清理：停止扫描、断连、销毁 session/queue、清零副本；本次未削弱清理路径。

**语义保持**：

- “确认写未发生” = 平台明确返回 GATT busy / congested；只有该信号允许重发同一帧。
- `2900099` 等模糊失败可能发生在“写已发出但未确认”的窗口，现为终止错误，避免命令重复或网关/客户端 CTR 错位。

### 2.2 R2-03（Low）：队列获取超时的“未开始 50ms 重试”已删除

**事实核对**：`GattRequestQueue.execute` 的超时计时器覆盖排队等待；超时即 `broken=true`。旧 `GattChannel.runWithBusyRetry` 在 `!started` 时仍等待 50ms 再 `queue.run`，但第二次调用会在入口因 `broken` 立即抛 `PROVISIONING_GATT_BUSY`，重试不可能成功。

**处置**：

- 删除该无效重试；`runWithBusyRetry` 更名为 `runSerialized`，只做一次 `queue.run` + `mapProvisioningError`。
- 代码注释明确：队列超时后 broken，第二次运行必然失败；写 busy 处理在 `writeRead` 内完成。
- `t12-fix-report.md` 中“队列获取超时的‘未开始’重试语义保留”的表述已更正，并指向本报告。
- 既有 `C19_GattRequestQueue_timeoutNeverStartsConcurrentOperation` 继续通过，F-08 单飞不变量未改变。

### 2.3 R2-04（Low/Info）：非规范 10 字节零 varint — 选择**严格拒绝**

**决定**：长度前缀采用**最小编码（canonical）**。`ProtobufReader.readLength()` 在终止字节处增加检查：多字节 varint 的最后一个 payload 为 0 即为 overlong，`fail('length')`（`PROTOCOL_INVALID_JSON`）。

- 覆盖 `80 80 80 80 80 80 80 80 80 00`（10 字节零）与 `80 00`（2 字节零）；`2^32`、10 字节非零高位长度仍按 F-11 拒绝。
- 合法小长度编码不受影响；`readUnsigned` 的 int32 二补码语义未改，冻结向量不受影响。
- 理由：与 DES-A §16.5“拒绝截断/超长/未知 wire type/越界长度”的严格解析方向一致；ESP-IDF/protobuf-c 对实际长度使用最小编码，严格拒绝不引入互操作回归。
- 新增负例 `C19_ProtobufReader_rejectsNonCanonicalLengthVarint`；既有 `C19_ProtobufReader_rejectsLengthVarintAbove32Bits` 继续通过。

### 2.4 R2-02（Low，既有行为）：显式 `request.device` 覆盖 `lastDevice`

**决定**：本次不改变行为，仅在报告中记录（复审建议允许 CQG 作为 Low 跟踪项）。

- `BleProvisioningService.resolveDevice` 在 `request.device !== undefined` 时执行 `this.lastDevice = request.device` 后返回该设备。因此一次显式传参后，后续省略 `request.device` 且本次扫描唯一时，会返回该显式设备，而不是“最近扫描发现的设备”。
- 该赋值在 `ba0de0c` 已存在，非本次引入；F-02 的“扫描 A → 扫描 B → 省略 device → 连接 B”已由 `latestScanWinsWhenDeviceOmitted` 覆盖并通过。
- 若产品希望省略路径只接受扫描来源，可在后续任务为 `lastDevice` 增加扫描代次或移除该赋值；本次不改，以避免改变已关闭的 F-02 行为。
- `t12-ble.md` §9-14 已记录“省略 device 使用扫描唯一设备”；本报告补充显式 device 的覆盖语义。

### 2.5 R2-05（Info，过程）：旧报告标注 superseded

- `artifacts/50-implementation/t12-ble.md` 顶部新增 **SUPERSEDED** 注记：该报告冻结于 `27dc537`，§2.1 `GattChannel` 的“GATT busy 仅未开始时重试一次（50ms）”及 §3 相关表述以 `t12-fix-report.md` 与 `t12-fix2-report.md` 为准。
- 同步在该表的 `GattChannel.ets` 行内标注“已过时”并指向本报告。
- `t12-fix-report.md` 顶部增加复审更新注记，F-04 行与口径说明按 R2-01/R2-03 更正。

---

## 3. 新增/更新测试与负例证据

### 3.1 新增 2 条（449 → 451）

| # | 文件 | 用例 | 覆盖 |
|---|---|---|---|
| 1 | `entry/src/test/host/BleGattFlow.test.mjs` | `C19_GattChannel_ambiguousWriteFailureIsNotRetried` | R2-01：`ble:2900099`、无标记 `GATT_BUSY`、无数字码未知错误、`ble:2900001` 四类写失败均 `writeAttempts === 1`、无成功写、无 50ms 重试延迟，并抛出对应错误 |
| 2 | `entry/src/test/host/BleCodec.test.mjs` | `C19_ProtobufReader_rejectsNonCanonicalLengthVarint` | R2-04：10 字节零长度与 2 字节 overlong 零长度均 `PROTOCOL_INVALID_JSON` |

### 3.2 既有用例更新

- `BleFakes.mjs`：`writeBusyOnce` 现在抛出带 `retryable=write-busy` 标记的 `PROVISIONING_GATT_BUSY`，模拟适配器确认 busy；新增 `writeErrorOnce` 注入任意写错误。标记字面量在 fake 中固定，避免产品 helper 与测试共享同一常量而掩盖标记漂移。
- 既有 3 条 F-04 用例（`writeBusyRetriesOnceWithSameBytes`、`readBusyIsTerminalWithoutResend`、`writeBusyRetryPreservesCtrStream`）语义不变并继续通过；其中 CTR 用例仍断言两次写入密文逐字节相同。

### 3.3 R2-01 负例断言要点

```text
case ble:2900099        -> PROVISIONING_GATT_BUSY,      writeAttempts=1, writes=0, no delay
case unmarked GATT_BUSY -> PROVISIONING_GATT_BUSY,      writeAttempts=1, writes=0, no delay
case unknown Error      -> PROVISIONING_GATT_BUSY,      writeAttempts=1, writes=0, no delay
case ble:2900001        -> PROVISIONING_GATT_INCOMPLETE, writeAttempts=1, writes=0, no delay
```

确认 busy 的正例仍为：第一次写抛确认 busy → 等待 50ms → 第二次写同一密文 → 读成功；`writeAttempts=2`、`writes=1`，CTR 用例解密结果仍为 `192.168.1.50`。

> 适配器 `mapWriteError` 是 `COMPILED_ONLY`（`@kit` 平台依赖，host 不可执行）；host 负例用与适配器 fallback 相同的 `field=ble:<code>` 形状验证通道判定。真实平台错误码语义仍由 T-19 设备验证。

---

## 4. 验证证据（本次实际执行，cwd = 仓库根）

| 命令 | 结果 | 证据文件 |
|---|---|---|
| `ohpm install` | **PASS，exit 0**（`install completed in 0s 55ms`） | `entry/src/test/evidence/t12-fix2-ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | **PASS，exit 0，BUILD SUCCESSFUL**（5 s 234 ms；35 tasks，34 executed / 1 up-to-date） | `entry/src/test/evidence/t12-fix2-clean-assemble.log` |
| `codelinter -c code-linter.json5 -p default .` | **PASS，exit 0**，`No defects found in your code.` | `entry/src/test/evidence/t12-fix2-codelinter.log` |
| `entry/src/test/run-host-tests.sh` | **PASS，exit 0：451 tests / 451 pass / 0 fail / 0 skip / 0 todo** | `entry/src/test/evidence/t12-fix2-host-node-tests.tap` |
| 附加 `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **PASS，exit 0，BUILD SUCCESSFUL**（35 tasks；**仅编译，不是设备执行**） | `entry/src/test/evidence/t12-fix2-ohosTest-assemble.log` |

测试数如实统计：**451**（449 基线 + 2 新增）。未把 ohosTest 编译或 host PASS 写成设备验证。

---

## 5. 未改变的不变量

- **Security1**：X25519 raw 32B、`SHA256(UTF8(PoP)) XOR shared`、AES-256-CTR 单一连续流、client/device verify 顺序、失败销毁均未改；冻结向量用例通过。
- **秘密清零**：PoP/Wi-Fi 密码副本、Security1 key/stream、密文缓冲 `finally` 清零未改。
- **身份 fail-closed**：v2.0 严格四字段、v2.1 严格 pin/pinAlg/port/tls、单次 v2.0 回退、`expectedGatewayId` 严格一致未改。
- **探针**：gatewayId/snapshot/profile/LED 校验、有限重试、失败不写绑定未改。
- **F-01 / F-02 / F-03 / F-05 / F-06 / F-07 / F-08 / F-09 / F-10 / F-11**：行为未改；F-04 仅按 R2-01 收窄重试条件、按 R2-03 删除无效队列重试。
- **D-4 命名**：未改；`R-2` 非零 Status 仍映射 `PROVISIONING_SECURITY_HANDSHAKE_FAILED`，等待 architect/D-4 owner 裁定。
- **宿主安全边界**：BLE 纯逻辑仍无 `@ohos`/`@kit` import（适配器除外）；本次未新增 i18n 文案。

---

## 6. 变更文件与范围

产品代码（4）：

- `entry/src/main/ets/service/ble/BleSupport.ets`（确认 busy 标记与判定）
- `entry/src/main/ets/service/ble/GattChannel.ets`（收窄写重试；删除无效队列重试）
- `entry/src/main/ets/service/ble/Protobuf.ets`（长度 varint 最小编码）
- `entry/src/main/ets/service/ble/adapters/OhosBleTransport.ets`（写错误映射）

测试与证据（`entry/src/test/`）：

- `host/BleGattFlow.test.mjs`、`host/BleCodec.test.mjs`、`host/BleFakes.mjs`
- `evidence/t12-fix2-{ohpm-install.log,clean-assemble.log,codelinter.log,host-node-tests.tap,ohosTest-assemble.log}`（5 个）

报告：

- 本文件；更新 `artifacts/50-implementation/t12-fix-report.md`、`artifacts/50-implementation/t12-ble.md`。

全部路径在 handoff `writes`/`commit_paths` 范围内；未修改 `module.json5`、model、DES/ADR、其他 Stage 产物。

---

## 7. 决策、假设与残余风险

| ID | 状态 | 说明 | 所有者 |
|---|---|---|---|
| R2-01 | **FIXED（待独立复审）** | 写重试仅确认 busy；`2900099`/未知/无标记 busy 不重试；负例通过 | quality-reviewer（未参与本次修复） |
| R2-03 | **FIXED** | 删除无效队列获取重试；代码/报告口径一致 | 复审确认 |
| R2-04 | **FIXED（选择严格拒绝）** | 非规范 overlong 长度 varint 拒绝；新增负例 | 复审确认 |
| R2-02 | **记录（不改代码）** | 显式 `request.device` 覆盖 `lastDevice` 为既有行为；如需扫描代次语义另行立项 | CQG / 产品 |
| R2-05 | **FIXED** | `t12-ble.md` 标注 superseded；`t12-fix-report.md` F-04 口径更正 | 复审确认 |
| 写失败错误码选择 | 记录 | 非 busy 写失败映射 `PROVISIONING_GATT_INCOMPLETE`（未知码带 `field=ble:<code>`）；DES-A §16.10 未单列“写失败”码，未新增 stable code | architect（低风险） |
| R-1 | OPEN | 草稿重签语义待 architect 正式裁定；C-23 必须使用 `result.credentialDraftId` | solution-architect |
| R-2 / D-4 | OPEN | protocomm 非零 Status 命名待裁定；当前 fail-closed | architect / D-4 owner |
| R-5 / R-12 | BLOCKED（证据） | 真实 BLE/MTU/`0x2901`/平台 X25519/AES-CTR/真实网关/LED 未在设备执行；本次仅 host + 编译 | T-19 |
| R-6 | OPEN（T-17） | `module.json5` 未声明 `ACCESS_BLUETOOTH`；本任务按范围未修改 | T-17 |

**假设**：平台 `writeCharacteristicValue` 返回 `2900011`/`2901004` 时，写调用在平台侧被拒绝（未受理），重发同一帧安全；该假设与复审建议及 BLE 设计“GATT busy”语义一致，仍需 T-19 设备确认。

---

## 8. Handoff

```text
STATUS: READY_FOR_REVIEW
SUMMARY: 按 REV-T12-002 收窄写重试（R2-01）：仅适配器确认 busy（2900011/2901004，标记 retryable=write-busy）重试一次并复用同一密文；2900099、无数字码/未知写失败、无标记 GATT_BUSY 均不重试。删除无效的队列获取 50ms 重试（R2-03）；长度 varint 采用最小编码，拒绝 10 字节零/overlong（R2-04）；报告记录显式 request.device 覆盖 lastDevice（R2-02）；t12-ble.md 标注 superseded（R2-05）。新增 2 条 host 用例，451/451 PASS；四项规定命令及 ohosTest 编译全部 exit 0。
ARTIFACTS_CREATED: artifacts/50-implementation/t12-fix2-report.md; entry/src/test/evidence/t12-fix2-{ohpm-install.log,clean-assemble.log,codelinter.log,host-node-tests.tap,ohosTest-assemble.log}
ARTIFACTS_UPDATED: entry/src/main/ets/service/ble/{BleSupport,GattChannel,Protobuf}.ets; entry/src/main/ets/service/ble/adapters/OhosBleTransport.ets; entry/src/test/host/{BleGattFlow,BleCodec}.test.mjs; entry/src/test/host/BleFakes.mjs; artifacts/50-implementation/{t12-fix-report.md,t12-ble.md}
DECISIONS: R2-01 采用复审建议 A+B（适配器只对确认 busy 生成可重试信号 + 通道显式标记判定）；R2-03 删除无效队列重试；R2-04 选择严格拒绝非规范 overlong 长度 varint；R2-02 不改既有 device 覆盖行为，仅记录。
ASSUMPTIONS: 2900011/2901004 表示平台拒绝写（写未受理），重发同一帧安全；适配器仅编译，真实语义待 T-19。
RISKS: 写失败错误码使用 PROVISIONING_GATT_INCOMPLETE 属本任务选择，待 architect 低风险确认；R-1/R-2/D-4 仍为 architect 未关闭项；R-5/R-12 设备项保持 BLOCKED；R-6 属 T-17。
VALIDATION: ohpm install exit 0; hvigorw clean assembleHap BUILD SUCCESSFUL exit 0 (35 tasks); codelinter No defects exit 0; run-host-tests 451/451 pass exit 0; ohosTest assembleHap BUILD SUCCESSFUL exit 0（仅编译）。
NEEDS_CLARIFICATION: 无新增阻断项；R-1（solution-architect）、R-2/D-4（architect/D-4 owner）继续跟踪。
NEXT_ACTION: 未参与本次修复的 quality-reviewer 复审 R2-01/R2-03/R2-04 与新增负例；CQG-T12 通过前不得标 STABLE；T-19 设备验收前设备项保持 BLOCKED。
```
