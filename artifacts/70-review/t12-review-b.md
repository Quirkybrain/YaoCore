# T-12 复审核查报告：F-01..F-11 关闭确认与 CQG-T12 意见

- **Artifact ID**: REV-T12-002
- **Producer**: agent:quality-reviewer
- **Type**: Independent Re-Review / Review Handoff
- **Status**: **CHANGES_REQUIRED**
- **Date**: 2026-10-17
- **Task**: `wp-043-review-t12b`（task 分支 `task/wp-040-ble`，父分支 `feat/yaocore-app`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`（Component Quality Gate 前）
- **Reviewed revision**: `a6a30533881a7f6bb6ac83f66a93a8bf3bd91f8e`（修复提交；父 `ba0de0c` 评审报告，原实现 `27dc537`）
- **Review snapshot**: `refs/swe/snapshots/20261017T131830Z-wp-043-review-t12b-33a6967a`（commit `c77feb2`）
- **Previous review**: `artifacts/70-review/t12-review.md`（REV-T12-001，CHANGES_REQUIRED，F-01..F-11）
- **Independence**: 本复审由未参与 T-12 实现、`wp-042-fix-t12` 修复或修复报告编写的 `quality-reviewer` 执行；唯一仓库写入为本报告。被审产品代码、测试、证据与修复报告均未修改；复验产生的构建产物只写入 Git 忽略目录，未入库。

> 结论先行：上轮 **F-01/F-02/F-03/F-05/F-06/F-07/F-08/F-09/F-10/F-11 已关闭**，F-04 的“平台写 busy 重试”已落地但**重试触发条件过宽**，构成新的 Medium 风险 **R2-01**：真实适配器把无法确认写未受理的通用写失败（如 `2900099 Operation failed`、无数字码错误）也映射为 `PROVISIONING_GATT_BUSY`，`GattChannel` 会据此重发同一密文；这违反上轮 F-04 要求的“确认写未发生”安全前提，可能造成命令重复或 Security1 CTR 错位。当前 revision 独立复跑 **449/449 host**、`codelinter`、`clean assembleHap`、ohosTest 编译均通过，Security1/清零/identity/探针语义无回归；但 R2-01 未关闭前不能授予 CQG-T12/`STABLE`。

---

## 1. 复审范围、revision 与输入完整性

### 1.1 范围

```text
entry/src/main/ets/service/            # C-19 产品代码（含 ble/adapters/OhosBleTransport.ets）
entry/src/test/                        # host fakes、449 条测试、证据日志
artifacts/50-implementation/t12-fix-report.md
```

- 修复 diff：`ba0de0c..a6a3053`，共 **19 文件**（8 个产品文件、5 个测试文件、5 个证据日志、1 个修复报告）；全部落在 `entry/src/main/ets/service/`、`entry/src/test/`、`artifacts/50-implementation/` 内。
- 未修改 `entry/src/main/module.json5`（`ACCESS_BLUETOOTH` 仍归 T-17）；未修改 model、DES/ADR、其他 Stage 产物；未发现构建产物、`.hap`/`.har`、`oh_modules` 或秘密入库。
- 范围外/明确排除：真实 BLE 射频、真实 MTU/`0x2901`、平台 X25519/AES-CTR 运行时、真实 ESP-IDF 网关、真实 LAN/HTTPS pin、板载 LED 硬件、API 14/15 设备安装、Hypium/`hvigorw test` 运行时。

### 1.2 输入 pin（handoff `wp-043-review-t12b`）

本复审核对了全部 9 个 pin 输入，SHA-256 **9/9 一致**：

| 输入 | SHA-256 前 12 位 | 结果 |
|---|---|---|
| `artifacts/70-review/t12-review.md` | `a9ad50007387` | 一致 |
| `artifacts/50-implementation/t12-fix-report.md` | `b127ad0f5e07` | 一致 |
| `artifacts/50-implementation/t12-ble.md` | `8a19011b2fb1` | 一致 |
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `5599e693fafe` | 一致 |
| `artifacts/20-architecture/adr-002-lan-security-channel.md` | `67943a6e1d8d` | 一致 |
| `artifacts/20-architecture/contract-baseline.md` | `6673a990d502` | 一致 |
| `artifacts/20-architecture/project-constraints.md` | `283046210e68` | 一致 |
| `artifacts/60-testing/test-plan.md` | `33485cc39abd` | 一致 |
| `input/existing/docs/BLE配网设计.md` | `d466c5bad4a5` | 一致 |

`git-policy.json` 的 SHA-256 亦与 handoff 一致（`3b8ddffd...`）；快照 ref 存在，审前 `git status` clean，`HEAD = a6a3053`。

### 1.3 复验命令（本复审实际执行，cwd = 仓库根）

| 命令 | 结果 | 备注 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS：449 tests / 449 pass / 0 fail / 0 skip / 0 todo，exit 0** | 与 `entry/src/test/evidence/t12-fix-host-node-tests.tap` 的 449/449 一致；14 条新增用例全部出现并通过 |
| `codelinter -c code-linter.json5 -p default .` | **PASS：No defects found in your code，exit 0** | 与 `t12-fix-codelinter.log` 一致 |
| `hvigorw clean assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0**（35 tasks；34 executed / 1 up-to-date） | 与 `t12-fix-clean-assemble.log` 一致；未配置签名 |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0**（35 tasks） | 与 `t12-fix-ohosTest-assemble.log` 一致；**仅编译，不是设备执行** |
| `git diff --name-only ba0de0c a6a3053` | **19 路径，全部在 handoff 范围** | 无 `module.json5`、无构建产物、无秘密 |
| `git status --short` / pin 复核 | **clean；9/9 输入一致；快照存在** | 复审前后均 clean |
| 设备执行 | **BLOCKED（未写成 PASS）** | 无设备/签名；ohosTest 仅编译，符合 CP-03 |

### 1.4 独立探针（不只依赖新增测试）

除运行 449 条测试外，复审者用现有 fakes 与直接导入做了只读独立复验：

- **F-01**：`parseV20` 接受 22 个“网”（66 UTF-8 字节）与 63 个中文；拒绝 64 ASCII/64 中文。
- **F-02**：扫描 A → 扫描 B → 省略 `request.device` → `connectedDeviceId = AA:...:02`；显式 `device` 仍优先。
- **F-03**：无 draft、无 `expectedGatewayId` → `CONFIGURATION_ERROR`，0 次连接、0 次 credential 读取；仅 draft 的新绑定成功。
- **F-05**：首次重试 elapsed = 500ms；`failProbes=5` 总延迟 7500ms。
- **F-06**：缺 `prov.ver` → `PROVISIONING_CAPABILITY_UNSUPPORTED`。
- **F-07**：`onCompleted` 抛错 → `INTERNAL_ERROR`，`drafts.size() === 0`。
- **F-08**：10ms 超时 + 50ms 操作，事件序列仅 `a-start`，排队/后续请求均 `GATT_BUSY`，`a-end` 迟到。
- **F-10**：`onStage`/`onStateChanged` 各抛错一次后，第三次 `provision` 成功。
- **F-11**：`2^32` length 与 10 字节非零长度均拒绝；合法小长度仍可读。
- **R2-01 复现**：用 `PROVISIONING_GATT_BUSY` + detail `ble:2900099` 模拟真实适配器对“非确认 busy”的写失败映射，`GattChannel` **仍重试**（`writeCalls === 2`）。

---

## 2. F-01..F-11 关闭状态

> 状态：**CLOSED** = 代码/测试/独立探针足以关闭；**PARTIAL** = 主症状已修但仍有阻断/条件；**OPEN** = 未关闭。

| ID | 上轮严重度 | 状态 | 当前代码/测试证据 | 复审判断 |
|---|---|---|---|---|
| **F-01** | Medium | **CLOSED** | `IdentityNegotiator.ets:302-306` 改为 `value.stringValue.length` 1..63；`C19_IdentityNegotiator_gatewayNameUsesCharacterLength`（63 ASCII/22 中文/63 中文通过，64 拒绝，v2.1 同规则）；独立探针一致 | 按字符长度符合 identity schema；`BleProvisioningIdentity` 模型仍用同一 UTF-16 长度口径。astral 字符仍受 C-02 模型 UTF-16 限制，修复报告已登记，非本次回归 |
| **F-02** | Medium | **CLOSED** | `BleProvisioningService.ets:139-142` 每次 `startScan` 清空 `scannedDevices`/`lastDevice`；`:156-158` 始终更新最新设备；`:382-384` 仅在本次扫描唯一时省略；`C19_BleProvisioningService_latestScanWinsWhenDeviceOmitted` + 独立探针 A→B→省略 → B | 上轮“连接过期 A”的场景已关闭；`resolveDevice` 的显式 device 会覆盖 `lastDevice`（R2-02，Low，既有行为） |
| **F-03** | Medium | **CLOSED** | `BleProvisioningService.ets:206-212`：无 draft 且无 `expectedGatewayId` → `CONFIGURATION_ERROR(field=expectedGatewayId)`，位于 `running`/扫描/连接/credential 读取之前；`C19_BleProvisioningService_emptyDraftRequiresExpectedGatewayId` + 独立探针（0 连接/0 credential；仅 draft 成功） | 选 `CONFIGURATION_ERROR` 而非 `PROVISIONING_CREDENTIAL_MISSING` 属调用方请求配对错误，语义可接受；修复报告已登记供 architect 复核 |
| **F-04** | Medium | **PARTIAL（R2-01 阻断）** | `GattChannel.ets:107-122` 写 busy → 50ms 后重试一次并复用同一 `value`；读 busy 不重发、由服务清理；3 条新用例通过 | 主症状（平台写 busy 不重试）已修；但重试条件为 `isCode(PROVISIONING_GATT_BUSY)`，真实适配器把非 busy/未知写失败也映射为 GATT_BUSY（见 R2-01），未满足“确认写未发生”的安全前提，故 F-04 只能条件关闭 |
| **F-05** | Medium | **CLOSED** | `BindingProbe.ets:181-196`：入口 deadline（30s）；`nextDelayMs(attempt - 1)` 首次 500ms；每次尝试前/睡眠前检查预算；`C19_BindingProber_firstRetryWaits500msAndExhausts7500ms`、`..._enforcesThirtySecondTotalBudget`；独立探针 500ms | 上轮要求的 500/1000/2000/4000 序列与 30s 预算检查已实现。残余：单次 probe 在途时不能中断，最坏可超出预算一个 C-17 超时（约 8s），属低风险（见 §6） |
| **F-06** | Low | **CLOSED** | `ProtoVerParser.ets:56-62`：`prov.get('ver')` + 显式缺失判断 → `unsupported('prov.ver')`；`C19_ProtoVerParser_missingProvVerAndShapeFailCapabilityGate`；独立探针缺 `prov.ver`/`prov` 数组 → `PROVISIONING_CAPABILITY_UNSUPPORTED` | 不再泄漏 `PROTOCOL_MISSING_FIELD`；组件 API 与契约一致 |
| **F-07** | Low/Medium | **CLOSED** | `BleProvisioningService.ets:290-296` 记录 `issuedDraftId`；`:310-326` catch 先销毁新 id；`:331-338` finally 在未完成时销毁原/新 id；`C19_BleProvisioningService_postProbeListenerFailureDestroysReissuedDraft`；独立探针 `drafts.size() === 0` | 覆盖 `onCompleted`/`emitState(BOUND)`/结果构造异常等 post-probe 路径；成功路径仍返回新 id 给 C-07 |
| **F-08** | Low | **CLOSED** | `GattRequestQueue.ets:20,35-57,78-97`：超时置 `broken`，等待者醒来检查 `broken` 后 `GATT_BUSY`，迟到结果/拒绝显式吸收；`C19_GattRequestQueue_timeoutNeverStartsConcurrentOperation`；独立探针事件仅 `a-start` | 严格单飞不变量恢复；`reset()` 不复活 broken，服务在 `discover()` 每次新建队列（`:512`），teardown 销毁（`:629-632`）。队列获取超时的 50ms 重试实际上会因 broken 立即失败（R2-03，Low） |
| **F-09** | Low | **CLOSED** | `WifiProvisioningFlow.ets:79-88`：每个 `scan_result` 请求前检查同一 15s deadline；`C19_WifiProvisioningFlow_scanPagesShareFifteenSecondDeadline`（首页 16s → 第二页不请求，`pages=1`） | 分页循环不再脱离 15s 预算；单页在途仍可超出（低风险，与 F-05 同类） |
| **F-10** | Low | **CLOSED** | `BleProvisioningService.ets:222-229` 首个 `emitStage` 移入 try；`:327-343` 内层 finally 必然复位 `running`/`activeListener`；`C19_BleProvisioningService_listenerExceptionsDoNotLockRunning`；独立探针第三次成功 | 监听器异常不再永久锁死服务；`onError` 抛错时 finally 仍复位（错误本身可能替换原错误，属回调边界，低风险） |
| **F-11** | Low | **CLOSED（核心缺陷）** | `Protobuf.ets:224-252` 新增 `readLength()`：`2^32`/10 字节非零长度 → `fail('length')`；`readBytes/readString/skip(LENGTH)` 使用；`C19_ProtobufReader_rejectsLengthVarintAbove32Bits`；独立探针 `2^32` 与 10 字节非零拒绝 | 上轮“2^32 被当作 0”的缺陷已关闭。残余：非规范 10 字节“零”varint 仍被接受为长度 0（R2-04，Low；不改语义/越界，报告“10 字节 varint 直接 fail”表述不精确） |

**小结**：上轮 11 项中 **10 项完全关闭**；F-04 主症状已修但触发条件存在新的 Medium 安全缺口（R2-01），故 F-04 为 **部分关闭**。

---

## 3. 新发现（R2-xx）

### R2-01（**Medium / 阻断**）：写 busy 重试触发条件过宽，可能重发未确认送达的密文

- **位置**：`entry/src/main/ets/service/ble/GattChannel.ets:107-122`；`entry/src/main/ets/service/ble/adapters/OhosBleTransport.ets:58-80,388-395`。
- **事实**：
  1. `GattChannel.writeRead` 对**任何** `PROVISIONING_GATT_BUSY` 的首次写失败都在 50ms 后重试，并复用同一密文。
  2. `OhosBleTransport.writeCharacteristic` 以 `mapBleError(error, 'PROVISIONING_GATT_BUSY')` 处理写错误：只有 `2900011`（GATT busy）和 `2901004`（connection congested）是显式 busy；`2900099 Operation failed`、`2901001 Write forbidden`、`2900001 Service stopped`、`2901005..2901007` 以及**无数字码**错误都会落入 fallback，同样返回 `PROVISIONING_GATT_BUSY`（fallback 还带 `field=ble:<code>`，显式 busy 不带 details）。
  3. 因此“平台写调用被拒绝”并不等于“确认写未发生”。`2900099 Operation failed` 尤其可能发生在写已发出但未得到确认的模糊窗口；补发同一帧可能让网关重复处理命令，或推进网关 CTR 而客户端只推进一次，导致后续解密/响应错位。BLE 设计 §5-176 对“GATT busy/读写超时”的处置是**清理会话、重新连接**，不是重发。
  4. 修复报告的测试 `C19_GattChannel_writeBusyRetriesOnceWithSameBytes` / `...PreservesCtrStream` 使用 `FakeBleConnection` 直接抛 `PROVISIONING_GATT_BUSY`，等价于“确认 busy”，**没有覆盖真实适配器的 fallback 映射**；修复报告 §2 F-04 的“重试只发生在可确认写未受理的信号上”在当前代码中不成立。
- **独立复现**：用 `PROVISIONING_GATT_BUSY` + `NameValue('field','ble:2900099')` 模拟 fallback 写失败，`GattChannel.requestPlain` 仍发起第二次写（`writeCalls === 2`，最终成功）。这说明无需真实设备即可证明触发条件过宽。
- **影响**：协议正确性/可靠性风险；不是直接密码学绕过，但可能造成命令重复、CTR 错位、配网失败，属于上轮 F-04 明确要求避免的方向。严重度 **Medium**。
- **建议（任选其一，优先 A/B）**：
  - **A**：`OhosBleTransport.writeCharacteristic` 只对 `2900011`/`2901004` 返回可重试的 `PROVISIONING_GATT_BUSY`；对其他写错误使用不可重试码（如 `PROVISIONING_CONNECT_FAILED`/`PROVISIONING_GATT_INCOMPLETE`）或携带明确的 `retryable=false` detail。
  - **B**：`GattChannel` 仅在某明确标记（如 detail `ble:2900011`/`2901004`，或空 details 的确认 busy）下重试；其他 GATT_BUSY 直接失败并由服务清理。
  - **C**：若决定不重试任何已开始的写失败，撤回写重试并在修复报告/DES-A §16.2/测试计划登记偏离（上轮 F-04 的另一条允许路径）。
  - 增加“fallback/未知写错误 → 不重试”的 host 负例；T-19 用真实设备确认 busy/失败码语义。

### R2-02（Low，非阻断，既有行为）：显式 `request.device` 会覆盖最近扫描的 `lastDevice`

- **位置**：`BleProvisioningService.ets:378-380`（`resolveDevice` 显式 device 分支）。
- **事实**：扫描唯一发现 A 后，若某次 `provision` 显式传 `device=B`，`lastDevice` 被改为 B；之后省略 `request.device` 的调用会在 `scannedDevices.size <= 1` 时返回 B，尽管“最近一次扫描的唯一设备”是 A。该赋值在 `ba0de0c` 已存在，**不是本次修复引入**；F-02 的“扫描 A→扫描 B”场景已正确。
- **影响**：低；通常 UI 会显式传 device 或重新扫描。若产品允许“显式一次后再省略”，可能使用非扫描来源的设备。
- **建议**：`resolveDevice` 不把显式 device 写入 `lastDevice`，或为 `lastDevice` 增加扫描代次，只有本次扫描可满足省略路径；CQG 记录为 Low 跟踪项即可。

### R2-03（Low，非阻断）：队列获取超时的“未开始重试”实际不可用

- **位置**：`GattRequestQueue.ets:78-97`；`GattChannel.ets:78-99`。
- **事实**：`execute` 的计时器覆盖排队等待；超时即 `broken=true`。`GattChannel.runWithBusyRetry` 在 `started=false` 时仍按 50ms 重试，但第二次 `queue.run` 会在入口因 `broken` 立即抛 `GATT_BUSY`，重试不可能成功。修复报告 §2 F-04 称“队列获取超时的‘未开始’重试语义保留”，与实现不一致（服务是严格串行调用，实际很少触发该路径）。
- **影响**：低；多 50ms 延迟与一处注释/报告口径不一致，不造成并发或重复写。
- **建议**：删除该无效重试并更新注释/报告，或仅在“未开始且队列未 broken”时保留重试；CQG 记录口径修正。

### R2-04（Low/Info，非阻断）：`readLength` 仍接受非规范 10 字节“零”varint

- **位置**：`Protobuf.ets:224-252`。
- **事实**：`2^32` 与 10 字节**非零**高位长度均被拒绝；但 `0a 80 80 80 80 80 80 80 80 80 00`（10 字节编码的长度 0）仍被接受为 0。修复报告 §2 F-11 写“10 字节 varint 直接 fail”，表述不精确；旧 `readUnsigned` 也曾接受该非规范编码。
- **影响**：Info/Low；长度仍受缓冲区边界检查，不构成越界/安全绕过；protobuf 解析器通常也接受非规范 varint。若 DES-A §16.5 的“超长”包含非规范编码，需显式拒绝。
- **建议**：如要求严格规范编码，在 `readLength` 增加“非首字节 payload 为 0 的 overlong 直接 fail”规则并补负例；否则在报告/CQG 中明确“超长”指 >32 位或越界，不改代码。

### R2-05（Info，过程）：`t12-ble.md` 的 F-04/§3 表述已过时

- **位置**：`artifacts/50-implementation/t12-ble.md:39` 及其 §3/§9。
- **事实**：原实现报告仍写“GATT busy 仅未开始时重试一次（50ms）”“§16.2 完整满足”，与当前 `GattChannel` 的写 busy 重试/读 busy 终止不一致；`t12-fix-report.md` 已记录新行为，但原报告未标注 superseded。
- **影响**：过程/证据一致性 Low；不影响代码。
- **建议**：CQG 记录引用 `t12-fix-report.md` 为当前行为来源，或在 `t12-ble.md` 顶部加“frozen at 27dc537; F-04 行为见 t12-fix-report”注记；不要求本次修改代码。

---

## 4. 回归检查

| 回归面 | 结论 | 证据 |
|---|---|---|
| Security1 冻结向量 | **PASS** | `C19_ProtocommCodec_step0MatchesFrozenVector`、`C19_Security1_rfc7748Vector`、`C19_Security1_handshakeAndContinuousCtrStream` 等 449/449 通过；`Security1Session.ets` 本次未改 |
| 秘密清零（SC-06） | **PASS（增强）** | PoP/Wi-Fi 密码副本零化、Security1 key/stream 销毁、密文缓冲 `finally` 清零未改；F-07 新增 post-probe 新 draft 销毁，仅增强清理 |
| 身份 fail-closed | **PASS** | v2.0 严格四字段/额外字段/常量/空名负例、v2.1 pin/pinAlg/port/tls 负例、单次 v2.0 回退、`expectedGatewayId` 严格一致均通过；F-01 只改长度口径 |
| 探针语义 | **PASS（行为）** | gatewayId/snapshot/profile/LED 校验、identity mismatch 不重试、有限 5 次、失败不写绑定均通过；F-05 只改退避/预算，未改验签与终端判定 |
| GATT 串行/`0x2901`/MTU | **PASS（host）** | `0x2901` 映射/缺失/重名/只读、MTU 512/247、单飞队列用例通过；F-08 强化超时后不并发 |
| 无秘密日志 | **PASS（代码/host）** | BLE 产品代码无 secret 日志；错误 details 仅 field/gatewayId；新增测试只用公开假数据 |
| i18n | **PASS/N/A** | 本次无新增 UI/错误文案；`provisioning.error.*` 既有键在 zh-CN/en-US 均存在；无重复代码变体 |
| 宿主安全边界 | **PASS** | 新增逻辑仍在纯 ArkTS 模块；BLE 产品代码无 `@ohos`/`@kit` import（适配器除外）；`TransportBoundary` 测试通过 |
| 设备边界 | **BLOCKED（诚实）** | ohosTest 仅编译；无设备/签名；未把 host/编译写成设备 PASS |

**回归结论**：未发现 F-01..F-11 修复破坏 Security1 向量、秘密清零、身份 fail-closed、探针语义或单飞/MTU/`0x2901` 行为；449/449 可复现。

---

## 5. CQG-T12 检查项对照

> 本表是评审意见，不是 Orchestrator 的 Gate 记录。`PASS` 仅指当前 revision 的代码/构建/host 证据；`PARTIAL`/`FAIL` 不等于 Gate 通过。

| CQG 检查项 | 结果 | 证据与边界 |
|---|---|---|
| 构建 | **PASS** | `hvigorw clean assembleHap --no-daemon` exit 0，BUILD SUCCESSFUL（35 tasks）；未签名 |
| 静态检查 | **PASS** | `codelinter -c code-linter.json5 -p default .` exit 0，No defects |
| Host 测试 | **PASS** | 449/449，0 fail/0 skip/0 todo，exit 0；14 条新增用例与证据 TAP 一致 |
| 契约符合 | **PARTIAL** | F-01/F-02/F-03/F-05..F-11 已关闭；F-04 写 busy 重试存在 R2-01（触发条件过宽），不能判为完全符合 DES-A §16.2-3911；R-1（draft 重签）、R-2/D-4（非零 Status 命名）仍为 architect 未关闭项 |
| 安全 | **PARTIAL/FAIL（R2-01）** | Security1 派生/连续 CTR/常数时间/失败销毁、身份 fail-closed、探针验签、无 secret 日志均通过；但 R2-01 的重发条件可能造成命令重复/CTR 错位，安全前提未满足。设备侧平台 busy 语义仍 `BLOCKED` |
| 分层/依赖方向 | **PASS** | 平台 API 仅在适配器；C-19 纯逻辑可由 host 运行；无新增跨层依赖或重复实现 |
| 独立评审 | **PASS** | 本报告由未参与实现/修复的 reviewer 出具；作者不能自批 |
| 设备/真实平台 | **BLOCKED** | 无设备/签名；ohosTest 仅编译；真实 BLE/MTU/`0x2901`/平台 X25519/AES-CTR/真实网关/LED 未验证；不得写成设备 PASS |
| i18n | **PASS/N/A** | 无新增硬编码文案；既有 locale 键齐备 |
| 可追溯/证据 | **PARTIAL** | 修复报告列出 F-01..F-11 与 14 条测试；但 `t12-ble.md` 的 F-04/§3 未标注 superseded（R2-05），TEST-001 的 CQG-T12 状态仍需 CQG 更新；不得把本报告当 Gate PASS |
| **CQG-T12 总体** | **暂不通过（CHANGES_REQUIRED）** | 构建/lint/host/分层/独立评审绿；R2-01 为唯一阻断项，R-1/R-2/D-4 为 architect 未关闭项，设备项 BLOCKED |

---

## 6. Verdict

**CHANGES_REQUIRED**

理由：

1. **已关闭**：上轮 F-01、F-02、F-03、F-05、F-06、F-07、F-08、F-09、F-10、F-11 均有代码位置、通过的新增测试与独立探针支持；449/449 host、codelinter、clean assemble、ohosTest 编译均独立复现。
2. **F-04 部分关闭**：平台写 busy 的重试已实现，读 busy 终止并清理的方向也合理；但 `GattChannel` 对**所有** `PROVISIONING_GATT_BUSY` 重试，而真实适配器把 `2900099 Operation failed`、无数字码等**未确认写未发生**的写失败也映射为 GATT_BUSY。该条件不满足上轮 F-04 的“确认写未发生”安全前提，可能重发已送达的密文，构成新的 **Medium R2-01**。
3. **没有 High 级密码学绕过**：Security1 派生/CTR/常数时间验证/失败销毁、identity fail-closed、探针 gatewayId/LED 校验、秘密清零均未发现回归；R2-01 的影响是协议正确性/命令重复风险，不是 PoP 或密钥绕过。
4. **不能授予**：CQG-T12 总体 PASS、C-19 `STABLE`、Integration/Stage Gate 或用户验收；设备项保持 `BLOCKED`。

**修复后必须**：

1. 按 R2-01 建议 A/B（优先）缩小重试触发条件：只对确认 busy（`2900011`/`2901004`）重试，其他写失败直接失败并由服务清理；或按 C 撤回写重试并登记偏离。
2. 补“未知/fallback 写错误 → 不重试”的 host 负例，并重跑 `run-host-tests.sh`、`codelinter`、`clean assembleHap`、ohosTest 编译。
3. 由**未参与修复**的 reviewer 复审 R2-01；R-1 由 solution-architect 裁定，R-2/D-4 由 architect/D-4 owner 统一命名；R-3/R-4/R-6 继续跟踪。
4. 设备可用后由 T-19 执行真实 BLE/MTU/`0x2901`/平台 X25519/AES-CTR/真实 ESP-IDF 网关/LED 端到端；在此之前设备证据保持 `BLOCKED`。

---

## 7. 残余风险与跟踪项

| ID | 风险 | 级别 | 下一步/所有者 |
|---|---|---|---|
| R2-RISK-01 | R2-01 写重试可能重发未确认送达的密文 | **Medium（阻断）** | implementation-engineer 缩小触发条件；复审后关闭 |
| R2-RISK-02 | `t12-ble.md` F-04/§3 过时，可能误导 CQG | Low（过程） | CQG 引用 `t12-fix-report.md`；或标注 superseded |
| R2-RISK-03 | 队列获取超时重试因 broken 失效，报告口径不一致 | Low | 修复注释/报告，或保留明确的未开始重试 |
| R2-RISK-04 | `readLength` 接受非规范 10 字节零 varint | Low/Info | 明确“超长”定义；如需严格，补 canonicality 检查 |
| R2-RISK-05 | F-05 单次 probe 在途可超出 30s 预算 | Low（协议/实现边界） | C-17 已有 connect 3s/read 5s 上界；T-19 设备验证 |
| R2-RISK-06 | F-09 单页在途可超出 15s deadline | Low | 与 F-05 同类；当前在下一页前检查，属可接受实现 |
| R-1 | 草稿重签语义（消费原 draft → 新 id）未经 architect 正式裁定；C-23 必须使用 `result.credentialDraftId` | Medium | solution-architect；未关闭前不得标 `STABLE` |
| R-2 / D-4 | protocomm 非零 Status 统一映射 `PROVISIONING_SECURITY_HANDSHAKE_FAILED`；命名待裁定 | Medium | architect / D-4 owner；当前 fail-closed |
| R-3 / R-4 / R-6 | 隐藏 SSID 入口、gatewayId `:`、`ACCESS_BLUETOOTH` 声明 | Low/High（依赖） | T-13/DES-B、C-02 owner、T-17 |
| R-5 / R-12 | 真实 BLE/平台 crypto/设备测试未执行 | High（证据） | T-19；保持 `BLOCKED`，不得写成 PASS |
| R-8 | Security1 AES-CTR 无完整性；主动 BLE MITM 理论降级/篡改 | Medium（协议固有） | 记录威胁模型；不得宣称 AEAD/完整 MITM 防护 |
| R-9 | TEST-001 CQG-T12 状态未由本报告更新 | Low（过程） | CQG-T12 记录 host/设备分层 |

---

## 8. 独立声明与限制

- 本报告由 `agent:quality-reviewer` 独立出具；评审者未编写 T-12 产品代码、测试或修复报告，未修改任何被审代码；唯一仓库写入为本报告。
- 评审基于 `a6a3053` 与上表 9 个 pin 输入；独立执行 449/449 host、codelinter、clean assemble、ohosTest 编译、`git diff`/pin 校验，并用现有 fakes 做 F-01/F-02/F-03/F-05/F-06/F-07/F-08/F-10/F-11 的只读独立探针；R2-01 通过模拟 `ble:2900099` fallback 写入复现，未修改仓库。
- 未覆盖：真实设备/模拟器、真实 BLE 射频、真实平台 X25519/AES-CTR、真实 ESP-IDF 网关、真实 LAN/HTTPS pin、板载 LED 硬件、API 14/15 安装、Hypium/`hvigorw test` 运行时。上述均为 `BLOCKED`/`UNAVAILABLE`，不是 PASS。
- 本报告不替代 CQG、Integration Gate 或 Stage Gate；最终 Gate 记录由 Orchestrator 依据本意见与证据作出。

---

## 9. Handoff

```text
STATUS: RETURNED_FOR_GATE / CHANGES_REQUIRED
SUMMARY: 上轮 F-01/F-02/F-03/F-05/F-06/F-07/F-08/F-09/F-10/F-11 全部关闭；F-04 写 busy 重试已实现但触发条件过宽（R2-01，Medium）：真实适配器将 2900099/无数字码等未确认写未发生的失败也映射为 GATT_BUSY，GattChannel 会重发同一密文，可能重复命令或 CTR 错位。449/449 host、codelinter、clean assemble、ohosTest 编译独立复现；Security1/清零/identity/探针无回归；设备项 BLOCKED。当前不能授予 CQG-T12/STABLE。
ARTIFACTS_CREATED: artifacts/70-review/t12-review-b.md
ARTIFACTS_UPDATED: none
RISKS: R2-01 写重试触发条件（Medium，阻断）；R-1 草稿重签（architect）；R-2/D-4 非零 Status 命名；R-5/R-12 设备项 BLOCKED；R-8 CTR 无完整性；R2-02/R2-03/R2-04/R2-05 Low/过程。
VALIDATION: host 449/449 pass（exit 0）；codelinter No defects（exit 0）；hvigorw clean assembleHap BUILD SUCCESSFUL（exit 0，35 tasks）；ohosTest assembleHap BUILD SUCCESSFUL（exit 0，仅编译）；19 文件均在范围；9/9 输入 pin 一致；git status clean；设备 onDeviceTest BLOCKED。
NEEDS_CLARIFICATION: R-1 由 solution-architect 裁定；R-2/D-4 由 architect/D-4 owner 统一；R2-01 由 implementation-engineer 修复后独立复审；R2-02/R2-03/R2-04/R2-05 由 CQG 记录或后续任务处理。
NEXT_ACTION: implementation-engineer 按 R2-01 建议 A/B 缩小写重试触发条件（或按 C 撤回并登记偏离），补“未知/fallback 写错误不重试”负例，重跑四项命令；未参与修复的 reviewer 复审；T-19 设备验收前不得标 STABLE。
```
