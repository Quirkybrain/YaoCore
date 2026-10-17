# T-12 评审修复报告：C-19 BLE 配网

- **Artifact ID**: IMP-T12-FIX-001
- **Producer**: agent:implementation-engineer
- **Type**: Implementation Fix Report / Handoff
- **Status**: READY_FOR_REVIEW
- **Date**: 2026-10-17
- **Task**: `wp-042-fix-t12`（task 分支 `task/wp-040-ble`，父分支 `feat/yaocore-app`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`（Component Quality Gate 前）
- **Base revision**: `ba0de0c`（评审报告 `REV-T12-001` 所在 HEAD；实现 `27dc537`）
- **Inputs**: `artifacts/70-review/t12-review.md`（pin 一致）、`artifacts/50-implementation/t12-ble.md`、DES-A §16.1-§16.11、ADR-002 §3.2/§4/§6、`contract-baseline.md`、`project-constraints.md`（SC-04/SC-05/SC-06、PR-06/PR-12/PR-13）、`test-plan.md`、BLE 设计、identity v2.0/v2.1 schema
- **Write scope**: `entry/src/main/ets/service/ble/`、`entry/src/test/`、`artifacts/50-implementation/`（未修改 `module.json5`、model、其他 Stage 产物）

---

## 1. 结论摘要

按 `REV-T12-001`（CHANGES_REQUIRED）逐条处置：**F-01/F-02/F-03/F-04/F-05/F-06/F-07/F-08/F-09/F-10/F-11 全部修复**，无遗留 Finding 降级或忽略。新增 **14 条** host 回归/负例，host 测试由 435/435 增至 **449/449 PASS**。四项规定命令及 ohosTest 编译全部实际执行并通过（exit 0）。

未改动 Security1 冻结向量语义、CTR 连续流顺序、秘密清零纪律、identity fail-closed、探针 gatewayId 严格一致；未改动 D-4 命名（仍待 architect 裁定）。

---

## 2. 逐条处置（F-01 … F-11）

| ID | 处置 | 变更点 | 说明与新增证据 |
|---|---|---|---|
| **F-01** | **FIXED** | `IdentityNegotiator.readGatewayNameOptional` | 改为按字符串字符数校验 1..63（`value.stringValue.length`），不再按 UTF-8 字节。v2.0 与 v2.1 共用该函数。新增 `C19_IdentityNegotiator_gatewayNameUsesCharacterLength`：63 ASCII 通过、22 个“网”（66 字节）通过、63 个中文通过、64 ASCII/64 中文拒绝、v2.1 同规则。 |
| **F-02** | **FIXED** | `BleProvisioningService.startScan` / `onDeviceFound` / `resolveDevice` | 每次 `startScan` 开始时清空 `scannedDevices` 与 `lastDevice`；`onDeviceFound` 始终把 `lastDevice` 更新为最近发现的设备；`resolveDevice` 仍只在本次扫描唯一（`scannedDevices.size <= 1`）时省略 `request.device`，多设备仍 `PROVISIONING_MULTIPLE_DEVICES`。新增 `C19_BleProvisioningService_latestScanWinsWhenDeviceOmitted`：扫描 A → 扫描 B → 省略 device → 连接 B（`connectedDeviceId` 断言）。 |
| **F-03** | **FIXED** | `BleProvisioningService.provision` 入口 | `credentialDraftId` 为空/未提供且 `expectedGatewayId` 未提供 → `CONFIGURATION_ERROR`（field=`expectedGatewayId`），在 `running`、扫描、连接、credential 读取之前 fail-fast。选择 `CONFIGURATION_ERROR` 而非 `PROVISIONING_CREDENTIAL_MISSING`：这是调用方请求配对错误，尚未进入“已绑定网关读取失败”语义；与 `BleProvisioningRequest` 对非法字段的既有 `CONFIGURATION_ERROR/PROTOCOL_*` 风格一致。新增 `C19_BleProvisioningService_emptyDraftRequiresExpectedGatewayId`（缺失 → 0 次连接/0 次 credential 读取；仅凭 draft 的新绑定仍可成功）；既有 `expectedGatewayId=gateway_other` → `PROVISIONING_BINDING_IDENTITY_MISMATCH` 负例保留并通过。 |
| **F-04** | **FIXED** | `GattChannel.writeRead` / `runWithBusyRetry` | 平台 **写** busy → 50ms 后重试一次，且**复用同一字节缓冲**；安全请求因此不会二次加密/推进 CTR。**读** busy 不重试（写可能已送达，重发会造成命令重复/响应错位），由服务清理会话并断连。队列获取超时的“未开始”重试语义保留。新增 3 条：`C19_GattChannel_writeBusyRetriesOnceWithSameBytes`（2 次写尝试、1 次完成写、同一字节）、`C19_GattChannel_readBusyIsTerminalWithoutResend`（写 1 次、读 1 次、`PROVISIONING_GATT_BUSY`）、`C19_GattChannel_writeBusyRetryPreservesCtrStream`（真实 Security1 握手 + 加密请求，重试后仍正确解密 `192.168.1.50`，两次写入密文逐字节相同）。 |
| **F-05** | **FIXED** | `BindingProbe.probe` | 重试延迟改为 `ProbeBackoff.nextDelayMs(attempt - 1)`（1-based）：首次重试 500ms；入口以 `ProbeBackoff.bindingProbeTotalBudgetMs()`（30s）计算 deadline，每次尝试前及每次等待前检查，超限统一 `PROVISIONING_BINDING_PROBE_FAILED`，且不会跨预算睡眠。新增 `C19_BindingProber_firstRetryWaits500msAndExhausts7500ms`（首次重试 500ms；5 次尝试总延迟 500+1000+2000+4000=7500ms）与 `C19_BindingProber_enforcesThirtySecondTotalBudget`（每次 probe 耗 7s → 第 5 次不启动，probeCalls=4，耗时 ≥30s）。 |
| **F-06** | **FIXED** | `ProtoVerParser.parse` | `prov.require('ver')` 改为 `prov.get('ver')` + 显式缺失判断，缺 `prov.ver` 直接 `PROVISIONING_CAPABILITY_UNSUPPORTED`，不再泄漏 `PROTOCOL_MISSING_FIELD`。新增 `C19_ProtoVerParser_missingProvVerAndShapeFailCapabilityGate`（缺 `prov.ver`、`prov` 为数组、缺 `sec_ver` 均映射能力错误）。 |
| **F-07** | **FIXED** | `BleProvisioningService.provision` catch/finally | 新增局部 `issuedDraftId`：probe 成功后记录 `outcome.credentialDraftId`；任何未交付结果的异常（含 `emitState(BOUND)`/`listener.onCompleted` 抛错）都在 catch/finally 销毁新重签 draft，原 draft 仍按原逻辑销毁。新增 `C19_BleProvisioningService_postProbeListenerFailureDestroysReissuedDraft`：`onCompleted` 抛错 → `INTERNAL_ERROR`，`probeCalls=1`，`drafts.size()==0`。 |
| **F-08** | **FIXED** | `GattRequestQueue` | 超时即置 `broken`；等待中的后继请求被唤醒后检查 `broken` 并以 `PROVISIONING_GATT_BUSY` 失败，**不会**与仍可能运行的超时操作并发。`reset()` 仅开启新 epoch，不复活已 broken 的链路；重连必须使用新队列。迟到结果/拒绝被显式吸收，避免 unhandled rejection。新增 `C19_GattRequestQueue_timeoutNeverStartsConcurrentOperation`：10ms 超时 + 50ms 操作，事件序列仅 `a-start`，排队请求与后续请求均 `GATT_BUSY`，`a-end` 在队列失败后单独完成；注释/契约语义已更新。 |
| **F-09** | **FIXED** | `WifiProvisioningFlow.scan` 分页循环 | 每个 `scan_result` 请求前检查与状态轮询相同的 15s deadline；超时统一 `PROVISIONING_WIFI_SCAN_FAILED`。新增 `C19_WifiProvisioningFlow_scanPagesShareFifteenSecondDeadline`：`finished=true` 后首个分页耗时 16s，第二页不再请求，`pages=1` 且返回扫描失败。 |
| **F-10** | **FIXED** | `BleProvisioningService.provision` | 首个 `emitStage(CONNECTING)` 移入 `try`；`popCopy/passwordCopy` 在 try 内分配；`finally` 增加内层 `finally` 保证即使 teardown/清理抛错也复位 `running=false`、`activeListener=undefined`。新增 `C19_BleProvisioningService_listenerExceptionsDoNotLockRunning`：`onStage` 抛错、`onStateChanged` 抛错各失败一次后，第三次 `provision` 仍能成功。 |
| **F-11** | **FIXED** | `Protobuf.Reader.readLength` | 新增严格长度读取：长度 varint 超过 32 位（含 `2^32`、10 字节 varint）直接 `fail('length')`；`readBytes/readString/skip(WIRE_LENGTH)` 统一使用它。`readUnsigned` 仍保留低 32 位用于 int32 负数语义，未改变冻结向量。新增 `C19_ProtobufReader_rejectsLengthVarintAbove32Bits`（`0a 80 80 80 80 10` 与 10 字节长度均拒绝；合法小长度仍可读）。 |

**F-04 口径说明**：本次选择“按 §16.2 安全重试一次”而不是登记偏离；重试只发生在“平台写调用被拒绝”这一可确认写未受理的信号上，并复用密文，避免 CTR 二次推进。读 busy 因写可能已送达而保持 fail-closed 清理，与 DES-A §16.2-3910“写/读失败 → 清理会话、断开、从 step0 重来”一致。

---

## 3. 新增/更新测试

### 3.1 新增 14 条（435 → 449）

| # | 文件 | 用例 | 覆盖 |
|---|---|---|---|
| 1 | `entry/src/test/host/BleSecurity.test.mjs` | `C19_IdentityNegotiator_gatewayNameUsesCharacterLength` | F-01 |
| 2 | `entry/src/test/host/BleGattFlow.test.mjs` | `C19_ProtoVerParser_missingProvVerAndShapeFailCapabilityGate` | F-06 |
| 3 | `entry/src/test/host/BleGattFlow.test.mjs` | `C19_GattRequestQueue_timeoutNeverStartsConcurrentOperation` | F-08 |
| 4 | `entry/src/test/host/BleGattFlow.test.mjs` | `C19_GattChannel_writeBusyRetriesOnceWithSameBytes` | F-04 |
| 5 | `entry/src/test/host/BleGattFlow.test.mjs` | `C19_GattChannel_readBusyIsTerminalWithoutResend` | F-04 |
| 6 | `entry/src/test/host/BleGattFlow.test.mjs` | `C19_GattChannel_writeBusyRetryPreservesCtrStream` | F-04 |
| 7 | `entry/src/test/host/BleGattFlow.test.mjs` | `C19_WifiProvisioningFlow_scanPagesShareFifteenSecondDeadline` | F-09 |
| 8 | `entry/src/test/host/BleGattFlow.test.mjs` | `C19_BindingProber_firstRetryWaits500msAndExhausts7500ms` | F-05 |
| 9 | `entry/src/test/host/BleGattFlow.test.mjs` | `C19_BindingProber_enforcesThirtySecondTotalBudget` | F-05 |
| 10 | `entry/src/test/host/BleService.test.mjs` | `C19_BleProvisioningService_latestScanWinsWhenDeviceOmitted` | F-02 |
| 11 | `entry/src/test/host/BleService.test.mjs` | `C19_BleProvisioningService_emptyDraftRequiresExpectedGatewayId` | F-03 |
| 12 | `entry/src/test/host/BleService.test.mjs` | `C19_BleProvisioningService_postProbeListenerFailureDestroysReissuedDraft` | F-07 |
| 13 | `entry/src/test/host/BleService.test.mjs` | `C19_BleProvisioningService_listenerExceptionsDoNotLockRunning` | F-10 |
| 14 | `entry/src/test/host/BleCodec.test.mjs` | `C19_ProtobufReader_rejectsLengthVarintAbove32Bits` | F-11 |

### 3.2 既有用例更新

- `BleService.test.mjs`：因 F-03 入口守卫，所有“无 draft”的 `createRequest` 现在显式传 `expectedGatewayId: GATEWAY_ID`（25 处机械更新 + `deviceSelection` 3 处格式化更新）；`missingExistingCredentialFailsClosed` 仍验证“已绑定但 Asset Store 无 secret → `PROVISIONING_CREDENTIAL_MISSING`”。用例语义未放宽。
- `BleFakes.mjs`：`FakeBleConnection` 增加 `writeBusyOnce`/`readBusyOnce` 注入与 `writeAttempts/readAttempts` 记录（仅测试 fake）。

---

## 4. 验证证据（本次实际执行，cwd=仓库根）

| 命令 | 结果 | 证据文件 |
|---|---|---|
| `ohpm install` | **PASS，exit 0**（install completed） | `entry/src/test/evidence/t12-fix-ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | **PASS，exit 0，BUILD SUCCESSFUL**（35 tasks） | `entry/src/test/evidence/t12-fix-clean-assemble.log` |
| `codelinter -c code-linter.json5 -p default .` | **PASS，exit 0**，`No defects found in your code.` | `entry/src/test/evidence/t12-fix-codelinter.log` |
| `entry/src/test/run-host-tests.sh` | **PASS，exit 0：449 tests / 449 pass / 0 fail / 0 skip / 0 todo** | `entry/src/test/evidence/t12-fix-host-node-tests.tap` |
| 附加 `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **PASS，exit 0，BUILD SUCCESSFUL**（仅编译，不等于设备执行） | `entry/src/test/evidence/t12-fix-ohosTest-assemble.log` |

测试数如实统计：**449**（基线 435 + 新增 14）。未把 ohosTest 编译或 host PASS 写成设备验证。

---

## 5. 未改变的不变量

- **Security1**：X25519 raw 32B、`SHA256(UTF8(PoP)) XOR shared`、AES-256-CTR 单一连续流、client/device verify 顺序、失败销毁与错误 PoP 不进入 Wi-Fi；冻结向量与 `C19_ProtobufCodec_step0MatchesFrozenVector` 等用例保持通过。
- **秘密清零**：PoP/Wi-Fi 密码副本、Security1 key/stream、draft、密文缓冲清理路径未削弱；新增 draft 销毁只增强 SC-06。
- **身份 fail-closed**：v2.0 严格四字段、v2.1 严格 pin/pinAlg/port/tls、单次 v2.0 回退、`expectedGatewayId` 严格一致均未改变（F-01 仅把长度口径改为字符）。
- **探针**：gatewayId/snapshot/profile/LED 校验严格一致；失败有限重试；不写绑定。
- **D-4 命名**：未改；`R-2` 非零 Status 仍映射 `PROVISIONING_SECURITY_HANDSHAKE_FAILED`，等待 architect/D-4 owner 裁定。
- **宿主安全边界**：BLE 产品代码仍无 `@ohos`/`@kit` import（适配器除外）；i18n 无新增硬编码文案。

---

## 6. 未决项与残余风险（不在本任务写范围/权限内）

| ID | 状态 | 说明 | 所有者 |
|---|---|---|---|
| **R-1** | OPEN | C-07 要求 `draftId === result.credentialDraftId`，C-19 “消费原 draft → 新 id 重签”需 architect 正式裁定；C-23 只能把 `result.credentialDraftId` 传给 C-07。修复未改变该语义。 | solution-architect |
| **R-2 / D-4** | OPEN | protocomm 非 0 `Status` 统一映射 `PROVISIONING_SECURITY_HANDSHAKE_FAILED`；无专用 stable code。当前 fail-closed。 | architect / D-4 owner |
| **R-3 / R-4** | OPEN（跟踪） | 隐藏 SSID 手动入口属 DES-B/UI；identity schema 允许 `gatewayId` 含 `:` 而 C-02 模型拒绝（仍 fail-closed）。 | T-13/DES-B；C-02 owner |
| **R-5** | BLOCKED（证据） | 真实 BLE/MTU/0x2901/平台 X25519/AES-CTR/真实 ESP-IDF 网关/板载 LED 未在设备执行；本次仅 host + 编译。 | T-19 |
| **R-6** | OPEN（T-17） | `module.json5` 未声明 `ACCESS_BLUETOOTH`；本任务按范围未修改。 | T-17 |
| **R-8** | 协议固有 | Security1 AES-CTR 无完整性；主动 BLE MITM 的理论版本剥离/篡改风险仍按既有威胁模型记录。 | 架构/文档 |
| **R-12** | BLOCKED（证据） | `onDeviceTest` 仍无设备；不得写成 PASS。 | T-19 |
| **F-01 残余** | 记录 | 字符长度使用 JS UTF-16 code units（与 `BleProvisioningIdentity` 模型一致）。BMP 中文（含 22/63 字符）符合 schema；>63 code point 的 astral 字符名会被现有模型一并 fail-closed，未在本任务写范围放宽。 | C-02/后续 schema 对齐 |
| **F-03 错误码** | 记录 | 选择 `CONFIGURATION_ERROR(field=expectedGatewayId)`；若 architect 更偏好 `PROVISIONING_CREDENTIAL_MISSING`，可后续统一（不影响 fail-fast 与负例）。 | architect（低风险） |

---

## 7. 变更文件与范围

产品代码（8）：
- `entry/src/main/ets/service/ble/IdentityNegotiator.ets`
- `entry/src/main/ets/service/ble/BleProvisioningService.ets`
- `entry/src/main/ets/service/ble/BindingProbe.ets`
- `entry/src/main/ets/service/ble/GattChannel.ets`
- `entry/src/main/ets/service/ble/GattRequestQueue.ets`
- `entry/src/main/ets/service/ble/ProtoVerParser.ets`
- `entry/src/main/ets/service/ble/Protobuf.ets`
- `entry/src/main/ets/service/ble/WifiProvisioningFlow.ets`

测试与证据（`entry/src/test/`）：
- `host/BleSecurity.test.mjs`、`host/BleGattFlow.test.mjs`、`host/BleService.test.mjs`、`host/BleCodec.test.mjs`、`host/BleFakes.mjs`
- `evidence/t12-fix-*.log|tap`（5 个）

报告：本文件。全部路径在 handoff `writes`/`commit_paths` 范围内；未修改 `module.json5`、model、DES/ADR、其他 Stage 产物。

---

## 8. Handoff

```text
STATUS: READY_FOR_REVIEW
SUMMARY: 按 REV-T12-001 修复 F-01..F-11 全部 11 项（F-04/F-05/F-06/F-08/F-09/F-10/F-11 一并完成，无降级/忽略）；新增 14 条 host 回归/负例，host 449/449 PASS；ohpm install、clean assembleHap、codelinter、host tests 及 ohosTest 编译全部 exit 0。Security1/清零/identity fail-closed/探针 gatewayId/D-4 命名未改变。
ARTIFACTS_CREATED: artifacts/50-implementation/t12-fix-report.md; entry/src/test/evidence/t12-fix-{ohpm-install.log,clean-assemble.log,codelinter.log,host-node-tests.tap,ohosTest-assemble.log}
ARTIFACTS_UPDATED: entry/src/main/ets/service/ble/{IdentityNegotiator,BleProvisioningService,BindingProbe,GattChannel,GattRequestQueue,ProtoVerParser,Protobuf,WifiProvisioningFlow}.ets; entry/src/test/host/{BleSecurity,BleGattFlow,BleService,BleCodec}.test.mjs; entry/src/test/host/BleFakes.mjs
DECISIONS: F-03 使用 CONFIGURATION_ERROR(field=expectedGatewayId) 作为入口 fail-fast；F-04 采用“平台写 busy 500ms/50ms 重试一次且复用密文”的契约内方案，读 busy 不重试；F-08 超时后队列 broken，重连需新队列。
ASSUMPTIONS: 平台 writeCharacteristic 拒绝 busy 表示该次写入未被接受；FakeBleConnection 的 busy 注入与真实适配器映射一致（代码审查层面）。
RISKS: R-1 草稿重签与 C-23 集成待 architect；R-2/D-4 错误码命名待裁定；R-5/R-12 设备项仍 BLOCKED；R-6 module.json5 权限属 T-17；F-01 astral 字符仍受 C-02 模型 UTF-16 长度限制。
VALIDATION: ohpm install exit 0; hvigorw clean assembleHap BUILD SUCCESSFUL exit 0 (35 tasks); codelinter No defects exit 0; run-host-tests 449/449 pass exit 0; ohosTest assembleHap BUILD SUCCESSFUL exit 0（仅编译）。
NEEDS_CLARIFICATION: R-1（solution-architect）、R-2/D-4（architect/D-4 owner）；R-3/R-4 由 DES-B/C-02 owner 跟踪。
NEXT_ACTION: 独立 reviewer 复审本修复（含 F-01/F-02/F-03/F-04/F-05/F-07/F-08/F-10/F-11 新用例与产品代码）；CQG-T12 通过前不得标 STABLE；T-19 设备验收前设备项保持 BLOCKED。
```
