# T-12 独立评审报告：C-19 BLE 配网（Security1 / 身份协商 / Wi-Fi / 绑定）

- **Artifact ID**: REV-T12-001
- **Producer**: agent:quality-reviewer
- **Type**: Review Report / Handoff
- **Status**: **CHANGES_REQUIRED**
- **Date**: 2026-10-17
- **Task**: `wp-041-review-t12`（task 分支 `task/wp-040-ble`，父分支 `feat/yaocore-app`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`（Component Quality Gate 前）
- **Reviewed revision**: `27dc537ca3e2de4f50f41d7572a09a1ab2aa4f82`（HEAD；base `3834f5d`；31 路径）
- **Review mode**: 独立 Code / Security / Integration Review（以安全关键路径与契约一致性为主）
- **Independence**: 评审者未参与 T-12 实现；本报告唯一写入为 `artifacts/70-review/t12-review.md`；未修改任何被审代码、测试或实现报告。

---

## 1. 范围、输入与复验

### 1.1 评审目标

```text
entry/src/main/ets/service/ble/            # C-19 产品代码（含 adapters/OhosBleTransport.ets）
entry/src/test/                            # host fakes、80 条新增测试、证据日志
entry/src/ohosTest/ets/test/               # 设备侧骨架与 List 注册
artifacts/50-implementation/t12-ble.md     # 实现报告
```

### 1.2 权威依据与 pin 校验

本次评审的 7 个 handoff 输入均按 SHA-256 复核，全部一致：

| 输入 | SHA-256 前 12 位 | 结果 |
|---|---|---|
| `artifacts/50-implementation/t12-ble.md` | `8a19011b2fb1` | 一致 |
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `5599e693fafe` | 一致 |
| `artifacts/20-architecture/adr-002-lan-security-channel.md` | `67943a6e1d8d` | 一致 |
| `artifacts/20-architecture/contract-baseline.md` | `6673a990d502` | 一致 |
| `artifacts/20-architecture/project-constraints.md` | `283046210e68` | 一致 |
| `artifacts/60-testing/test-plan.md` | `33485cc39abd` | 一致 |
| `input/existing/docs/BLE配网设计.md` | `d466c5bad4a5` | 一致 |

主要依据章节：DES-001A §3.2（错误体系）、§16.1-§16.11（C-19 全条）、§20（BLE 实现清单）；ADR-002 §3.2/§4/§6；BLE 设计 §2-§7；identity v2.0 schema；`contract-baseline.md` §2/§3/§4/§8；`project-constraints.md` SC-04/SC-05/SC-06、PR-06/PR-07/PR-12/PR-13、CP-03。

### 1.3 复验命令（本评审实际执行，cwd = 仓库根）

| 命令 | 结果 | 备注 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS：435 tests / 435 pass / 0 fail，exit 0** | 与 `entry/src/test/evidence/t12-host-node-tests.tap` 的 435/435 一致；新增 C-19 用例 80 条（13+17+31+19）均出现 |
| `codelinter -c code-linter.json5 -p default .` | **PASS：No defects found in your code，exit 0** | 与 `t12-codelinter.log` 一致；仅覆盖产品源码，测试目录不在其范围 |
| `hvigorw clean assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0**（35 tasks） | 与 `t12-clean-assemble.log` 一致；未配置签名 |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0** | 与 `t12-ohosTest-assemble.log` 一致；只证明编译，不是设备执行 |
| `git diff --name-only HEAD~1 HEAD` | **31 路径，全部在 handoff 范围** | 未修改 `entry/src/main/module.json5`；无构建产物、`.hap`/`.har`、`oh_modules` 或秘密入库 |
| `git status` / 输入 pin 复核 | **clean；7/7 输入一致** | 快照 `refs/swe/snapshots/20261017T130135Z-wp-041-review-t12-5deb2a1c` |
| 设备执行 | **BLOCKED（未写成 PASS）** | `t12-onDeviceTest-blocked.log` 显示 `GenerateDeviceCoverage` 要求连接设备；符合 CP-03 |

### 1.4 独立向量与协议核对

- 冻结向量由 host 测试逐项覆盖并通过：step0（`10015a25a201220a20...1e1f`）、`get_status`（`5200`）、`apply_config`（`08047200`）、scan start（`52080801100018002078`）、scan status（`08026200`）、scan result（`0804720408001004`）、负 RSSI `-100`（`9cffffffffffffffff01`）、RFC 7748 §6.1 三元组。
- 评审者对照 ESP-IDF **v5.2.3** 的 `sec1.proto`、`session.proto`、`wifi_config.proto`、`wifi_scan.proto`、`wifi_constants.proto`、`wifi_ctrl.proto` 核对字段号：`Sec1Payload` 20/21/22/23、`WiFiConfigPayload` 10-15、`WiFiScanPayload` 10-15、`WiFiConnectedState.ip4_addr` 为 **string field 1**、`WiFiCtrlPayload.cmd_ctrl_reset` 为 field 11，均与实现一致；未发现自定义帧头。
- Security1 派生链与 BLE 设计 §4.2 一致：X25519 raw 32B → `SHA256(UTF8(PoP))` → 逐字节 XOR → AES-256-CTR/NoPadding 单一连续流；`client_verify`/`device_verify`/业务请求响应共用同一流；验证数据用 C-04 的常数时间比较。
- X25519/AES-CTR 的 host oracle 使用 Node `crypto`，不是同一实现自证；冻结 protobuf 帧由独立向量校验。

### 1.5 证据一致性结论

实现报告 §1/§3/§4/§7 的 host 435/435、80 条新增、codelinter、clean assemble、ohosTest 编译声明与提交证据**一致**；`onDeviceTest` 明确为 `BLOCKED`，未把编译或 host 结果写成设备 PASS。设备骨架、真实平台 X25519/CTR、BLE 射频均保持 `BLOCKED`/`COMPILED_ONLY`，符合 CP-03。

### 1.6 评审限制

- 无真机/模拟器/签名配置：真实 BLE 扫描、连接、MTU、`0x2901` 读取、HarmonyOS X25519/AES-CTR 运行时行为**未验证**（`BLOCKED`）。
- 无真实 ESP-IDF 网关：host fake 的线格式与 Node crypto oracle 是当前最强证据，但不等于固件互操作。
- 未覆盖真实 LAN 探针、真实 TLS pin、板载 LED 硬件执行、API 14/15 设备安装。
- 未执行 `hvigorw test`/Hypium host runner；按 TEST-001 §2.3 该路径在当前 Linux Previewer 环境下阻塞。

---

## 2. Findings（按严重度排序）

> 严重度：**High/Blocking** = 必须在 CQG/集成前修复或由架构裁定；**Medium** = 应修复或必须有记录的接受决定；**Low** = 改进建议、测试诚实性或严格性缺口。本次**未发现 High 级安全绕过**；但存在多项明确的契约/正确性偏差，故 Verdict 为 CHANGES_REQUIRED。

| ID | 严重度 | 位置 | 契约/依据 | 问题与证据 | 建议 |
|---|---|---|---|---|---|
| **F-01** | **Medium** | `entry/src/main/ets/service/ble/IdentityNegotiator.ets:297-307`（`readGatewayNameOptional`）；`entry/src/main/ets/model/ProvisioningModels.ets:54-56` | DES-A §16.6；identity v2.0 schema `gatewayName` `minLength:1, maxLength:63`（按字符）；ADR-002 §3.2 | 实现用 **UTF-8 字节长度** `Utf8.encode(name).length` 限制 1..63，而 schema 的 `maxLength` 是字符数。含中文的网关名每字符 3 字节，**22 个中文字符（66 字节）会被错误拒绝**为 `PROVISIONING_IDENTITY_INVALID`，尽管 schema 允许最多 63 个字符。评审者用 22 个“网”字直接调用 `parseV20` 复现：`rejected PROVISIONING_IDENTITY_INVALID`。这是 fail-closed 的误拒绝，不是安全绕过，但会破坏合法设备的中文显示名。 | 改为按字符串字符数校验（`value.stringValue.length` 1..63），或交给 `BleProvisioningIdentity` 的现有字符长度校验；补充“63 个 ASCII / 22+ 个中文 / 64 字符拒绝”的 host 与设备用例。 |
| **F-02** | **Medium** | `entry/src/main/ets/service/ble/BleProvisioningService.ets:138-155`（`startScan` 清空 `scannedDevices` 但只在 `lastDevice === undefined` 时更新）、`:350-359`（`resolveDevice` 在 `scannedDevices.size <= 1` 时直接返回 `lastDevice`） | DES-A §16.1.1/§16.9；实现报告 §9-14“省略 device 时使用最近一次扫描的唯一设备” | `lastDevice` 只设置一次，后续 `startScan` 找到新设备时不会更新；第二次扫描只发现 B 时，`provision` 省略 `request.device` 仍会连接第一次扫描的 A。评审者用现有 fakes 复现：先扫描 `AA:...:01`，再扫描 `AA:...:02`，随后 `provision` 不带 device，`transport.connectedDeviceId` 仍为 `AA:...:01`。这违反“最近一次扫描的唯一设备”，可能使用户连接到错误/过期设备（PoP/identity 仍会二次校验，故不是静默错误绑定，但会失败或连错对象）。 | 在每次 `startScan` 开始时清空 `lastDevice`，或在 `onDeviceFound` 中始终更新为最新唯一设备；`resolveDevice` 只在“本次扫描恰好一个设备”时使用该设备，否则要求显式 `request.device`。补充“扫描 A → 扫描 B → 省略 device”的 host 用例。 |
| **F-03** | **Medium** | `entry/src/main/ets/service/ble/BleProvisioningService.ets:197-318`（`provision` 起始校验）、`:575-582`（`probeBinding` 直接使用 `this.credentials`） | DES-A §16.8-4116-4118：“`request.credentialDraftId` 为空 → `credentials.withCommandSecret` 读取已有 Asset Store 值（**仅重新配网且已绑定；`expectedGatewayId` 必须存在**）” | 当 `credentialDraftId` 未提供时，服务没有强制 `expectedGatewayId` 存在；只要 `credentials.withCommandSecret(identity.gatewayId)` 能取到既有 secret，就走“已有 secret”探针路径。现有 `C19_BleProvisioningService_happyPathV21` / `...tlsPinMismatchNeverBinds` 正是在无 draft、无 `expectedGatewayId` 的情况下成功/进入探针，证明该守卫缺失。当前 C-07 `commitBinding` 的 empty-draft 路径还要求既有 route，因此不会直接产生新绑定；但契约要求的 fail-fast 守卫不存在，且 UI 误用会把“是否重新配网”的决策留给下游。 | 在 `provision` 入口（进入 try 前）增加：`credentialDraftId === undefined && expectedGatewayId === undefined` → `CONFIGURATION_ERROR`（或按契约选择 `PROVISIONING_CREDENTIAL_MISSING`），并补充该负例；新绑定必须显式提供 draft。 |
| **F-04** | **Medium** | `entry/src/main/ets/service/ble/GattChannel.ets:72-91`（只在 `!started` 时重试一次）；`entry/src/main/ets/service/ble/adapters/OhosBleTransport.ets:388-406`（写/读把平台 busy 映射为 `PROVISIONING_GATT_BUSY`） | DES-A §16.2-3911：“GATT busy → 重试一次（50ms），仍失败 → `PROVISIONING_GATT_BUSY`”；PR-12 | `started = true` 在调用 `operation()` 之前设置，因此平台写/读返回的 `PROVISIONING_GATT_BUSY` 永远不会触发 50ms 重试；只有“排队等待超时且操作尚未开始”才重试。实现报告 §2.1 自述“GATT busy 仅未开始时重试一次”，但 §9 偏离项没有登记该收窄，§3 的 §16.2 对照仍写成完整满足。安全方向可接受（避免重复写导致 CTR/命令重复），但契约与证据口径不一致。 | 由 architect/实现者明确：要么按 §16.2 在“确认写未发生”的 busy 上安全重试一次；要么把“不重试已开始的 busy，直接清理会话”登记为 §9 偏离并更新 DES-A/测试计划。增加“平台 write busy → 1 次重试”或“busy → 清理”测试，明确期望。 |
| **F-05** | **Medium** | `entry/src/main/ets/service/ble/BindingProbe.ets:178-211`；`entry/src/main/ets/service/gateway/ProbeBackoff.ets:41-67` | DES-A §16.8-4123；§19 回退表（5 次，500ms×2，上限 8s，总预算 30s）；BLE §5-143；PR-13 | (a) 首次重试延迟使用 `nextDelayMs(attempt)`，attempt=2 得到 **1000ms**，而 `ProbeBackoff` 的 1-based 语义（1→500ms）意味着首次重试应为 500ms；存在一处 off-by-one。(b) 代码没有使用 `bindingProbeTotalBudgetMs()`，也没有 deadline；每次 C-17 probe 可能耗时较长，5 次尝试 + 延迟的总时间可超过 30s，违反“总预算 30s”。测试只验证尝试次数（5 次）与最终错误，没有验证延迟序列或总预算。 | 用 1-based 语义统一：重试前调用 `nextDelayMs(attempt - 1)`；在 `probe` 入口计算 deadline（`now + 30s`），每次尝试前检查，超时统一 `PROVISIONING_BINDING_PROBE_FAILED`；补 500/1000/2000/4000/8000 与 30s 预算的 fake-clock 用例。 |
| **F-06** | **Low** | `entry/src/main/ets/service/ble/ProtoVerParser.ets:52-60`（`prov.require('ver')`） | DES-A §16.3-3926：“`parse` 失败 → `PROVISIONING_CAPABILITY_UNSUPPORTED`” | 当 `prov` 存在但缺少 `ver` 时，`JsonNode.require` 抛出 `PROTOCOL_MISSING_FIELD`；评审者直接调用 `ProtoVerParser.parse` 复现为 `PROTOCOL_MISSING_FIELD`，不是契约声明的 `PROVISIONING_CAPABILITY_UNSUPPORTED`。服务层 `checkCapability` 的 `mapProvisioningError` 会把它兜底为 `CAPABILITY_UNSUPPORTED`，因此用户可见行为正确，但组件 API 契约与直接单元测试口径不一致，且现有 `downgradeAndMissingCapabilities` 用例没有覆盖“缺 `prov.ver`”。 | 在 `parse` 外层统一捕获 `AppError` 并转换为 `PROVISIONING_CAPABILITY_UNSUPPORTED`，或避免 `require` 直接抛 `PROTOCOL_*`；补“缺 `prov.ver` / `prov` 为数组 / 缺 `sec_ver`”用例。 |
| **F-07** | **Low/Medium** | `entry/src/main/ets/service/ble/BleProvisioningService.ets:275-288`（probe 成功后到 `completed=true` 之间）、`:289-318`（失败清理只销毁 `request.credentialDraftId`）；`entry/src/main/ets/service/ble/BindingProbe.ets:121-128`（`reissue()` 产生新 id） | SC-06；DES-A §16.9-4194-4202；实现报告 §9-7（草稿重签） | 若 `probeBinding` 已成功并 `reissue()` 出新 draft id，随后 `BleProvisioningResult` 构造、`emitState(BOUND)` 或 `listener.onCompleted` 抛错，catch/finally 只销毁**原** `request.credentialDraftId`（已被 probe 消费），不会销毁新 id；新命令密钥留在 `SecretDraftStore`（内存，TTL 10 分钟）。评审者用“onCompleted 抛错”复现：`INTERNAL_ERROR`，`drafts.size() == 1`。这是清理路径的 SC-06 缺口，不是网络攻击面，但“全路径清零”不成立。 | 将 `outcome.credentialDraftId` 提升到 try 外/局部变量，并在 catch/finally 中销毁未交付的新 id；或将 `onCompleted`/`onStateChanged` 回调异常隔离为日志，不影响成功结果与秘密所有权；补“post-probe 失败 → drafts.size()==0”的测试。 |
| **F-08** | **Low** | `entry/src/main/ets/service/ble/GattRequestQueue.ets:32-53,68-82` | DES-A §16.2-3901/3906；PR-12“严格串行、单飞” | `execute` 超时后 `Promise.race` reject，`run` 的 `finally` 立即 `release()`，但被超时的 `operation()` 仍可能在底层继续执行；此时排队的下一个 `run` 会开始，形成两个未完成的 GATT 操作。评审者用 10ms 超时 + 50ms 操作复现事件序列 `a-start,a-timeout,b-start,b-end`（`a-end` 延后）。当前服务在超时后立即销毁连接/会话，正常路径不会继续发请求，故未观察到 CTR 错位；但队列本身不再满足“严格单飞”的绝对不变量。 | 超时后不要立即释放槽位，直到底层 operation settle；或在超时同时关闭/废弃底层连接，并让后继请求以 `GATT_BUSY` 失败；在队列注释/契约中写明该语义；补“超时后不并发”的测试。 |
| **F-09** | **Low** | `entry/src/main/ets/service/ble/WifiProvisioningFlow.ets:55-90` | DES-A §16.7-4078：“扫描总超时 15s；最大页数 20”；BLE §5-139 | 15s deadline 只在 `scan_finished=false` 的状态轮询中检查；一旦 `scan_finished=true`，后续最多 20 页的 `scan_result` 请求不再受 deadline 约束，每页只受 15s GATT 队列超时保护，理论上可显著超过 15s。正常固件每页很快，故风险低。 | 在每个 `scan_result` 请求前检查同一 deadline，超时统一 `PROVISIONING_WIFI_SCAN_FAILED`；补“finished 后页码慢”的 fake-clock 用例。 |
| **F-10** | **Low** | `entry/src/main/ets/service/ble/BleProvisioningService.ets:203-210`（`emitStage(CONNECTING)` 在 `try` 之前） | 防御性/可恢复性；DES-A §16.9“所有中间状态支持取消” | `listener.onStage` 在 try/finally 之外调用；若监听器抛错，`provision` 以 rejected promise 返回，但 `running` 仍为 `true`、`activeListener` 未清空，后续 `provision`/`startScan` 永久返回 `CONFIGURATION_ERROR`。评审者复现：第一次 onStage 抛 `boom`，第二次 `provision` 得到 `CONFIGURATION_ERROR`。监听器是 App 代码，非网络攻击面，但服务不应被单个回调异常永久锁死。 | 把首个 `emitStage` 移入 try，或用统一 `try/catch` 包装监听器回调（记录 warning，不改变协议状态）；确保 `running` 在 `finally` 必然复位；补“onStage/onStateChanged 抛错后仍可再次 provision”的测试。 |
| **F-11** | **Low** | `entry/src/main/ets/service/ble/Protobuf.ets:174-230`（`readBytes` 复用 `readUnsigned`） | DES-A §16.5-4033：“必须拒绝截断/超长/未知 wire type/越界长度；不得把 64-bit varint 直接累加” | `readUnsigned` 按设计保留低 32 位（用于 int32 负数）；`readBytes` 也用它解析 length。一个 10 字节 varint 表示 `2^32` 时，低 32 位为 0，读取器把长度当作 0 并返回空字段，而不是拒绝“超长/越界长度”。评审者用 `0a 80 80 80 80 10` 复现：`accepted length 0`。当前所有必需字段都有非空语义检查（SSID/BSSID/IP/密钥长度），故实际影响低；但严格 reader 的 fail-closed 声明不完全成立。 | 增加 `readLength()`：对 10 字节 varint 或值 > `0xFFFFFFFF` 直接 `fail('length')`；`readBytes`/`readString` 使用它；补 `2^32` length、10 字节 length 的负例。 |

### 2.1 其他观察（不单独升级为 Finding）

- **R-1 草稿重签语义**：C-07 当前实现明确要求 `draftId === result.credentialDraftId`（`GatewayRepository.ets:177`），因此 C-19 的“消费原 draft → 以新 id 重签 → 返回新 id”与现有 C-07 自洽；但这是对 DES-A §16.8 一次性 draft 生命周期的解释性扩展，必须由 solution-architect 裁定，且 C-23 只能把 `result.credentialDraftId` 传给 C-07，不能传 `request.credentialDraftId`。建议在 R-1 关闭前不把 C-19 标为 `STABLE`。
- **R-2 / D-4**：`set_config/apply_config/get_status` 返回非 0 `Status` 时统一映射 `PROVISIONING_SECURITY_HANDSHAKE_FAILED`（实现报告 §9-9）。这是协议层失败，不是 PoP/密钥错误；DES-A §16.10 没有更细的 stable code，属 D-4 命名/契约待裁定。当前 fail-closed 方向正确。
- **Security1 的完整性限制**：AES-256-CTR 不是 AEAD；主动 BLE MITM 可在理论上翻转密文比特，迫使 v2.1 响应解析失败并触发一次 v2.0 回退（HMAC-only），或篡改 Wi-Fi 凭据。该限制来自 BLE 设计 §4-62/§7 与 Security1 协议本身，不是 T-12 新引入；ADR-002 §3.2-5 的“不可被 MITM 版本剥离”应理解为“LAN 攻击者无法伪造 PoP 绑定的 BLE 会话”，不能覆盖主动 BLE 链路 MITM。列为残余风险，不应据此单独阻断 T-12。
- **隐藏 SSID**：服务始终先扫描；扫描成功但为空时仍会用请求 SSID 下发，因此隐藏网络在扫描成功路径下可用；扫描失败/超时则无法进入下发。R-3（手动入口）仍属 DES-B/UI 待办。
- **gatewayId `:`**：identity schema 允许，C-02 模型拒绝；实现先 schema 后模型，含 `:` 的 gatewayId fail-closed。R-4 保持；非 T-12 写范围。
- **`prov-ctrl`**：`encodeCtrlReset()` 与 ESP-IDF v5.2.3 `wifi_ctrl.proto` 的 field 11 一致；`encodeCtrlStop()` 因 proto 无 stop 消息而 fail-closed；正常配网流程不调用。R-7 保持。
- **适配器兼容性**：`matchesService` 在 `result.serviceUuids === undefined` 时返回 true，依赖平台 `startBLEScan` 已按 service UUID 过滤；`namePrefix` 只作展示/辅助，未在适配器二次过滤。符合 BLE §2“名称仅辅助”，但 T-19 真机应确认平台过滤行为。
- **i18n**：BLE 代码未新增硬编码 UI/错误文案；`provisioning.error.*` 键在 `zh-CN.json`/`en-US.json` 均存在；en 的复数变体差异（`device.count_one/_other`）是既有设计，不是 T-12 回归。
- **测试计划状态**：SEC-N21（identity 多余字段/常量不符）host 部分已覆盖，设备部分仍 `BLOCKED`；SEC-N24（日志/异常含 secret）没有独立静态扫描证据，但评审者检查 BLE 产品代码无 secret 日志，且 `AppError.details` 只含 `field/gatewayId`。CQG-T12 应更新 TEST-001 状态，不能把本报告当作 Gate PASS。

---

## 3. 安全与契约逐项裁决

### 3.1 Security1（最高优先）

| 检查项 | 结论 | 证据 |
|---|---|---|
| X25519 raw 32B、非 DER | **PASS** | `Security1Session.createStep0`；`X25519KeyPair.publicKeyRaw`；step0 向量 |
| `SHA256(UTF8(PoP)) XOR shared` | **PASS** | `Security1Session.ets:99-111`；Node crypto oracle |
| AES-256-CTR/NoPadding 单一连续流 | **PASS** | `createAesCtrStream`；`GattChannel.request` 在队列槽内按序 encrypt/decrypt；连续密文测试 |
| client/device verify 顺序 | **PASS** | step1 加密 device pub；step1 用同一流解密 device verify |
| 常数时间比较 | **PASS** | `CryptoService.constantTimeEqual` 扫描 max 长度；长度不等折叠 |
| 失败销毁 / 不复用 CTR | **PASS** | 错误 PoP → `DESTROYED` + `POP_INVALID`；服务重试产生新 keypair（`keyPairCalls` 1→2） |
| 错误 PoP 不进入 Wi-Fi | **PASS** | handshake 失败在 identity/scan/apply 之前；测试 `pop.service.state=FAILED`、disconnect≥1 |
| 无秘密日志 | **PASS** | BLE 产品代码仅 `BindingProbe` LED reset warning，details 仅 gatewayId；无 PoP/密码/session key |
| 平台 X25519/CTR 运行时 | **BLOCKED** | 仅编译/设备骨架；R-5 |

**裁决**：Security1 的派生、流顺序、常数时间验证与失败销毁与冻结文档一致，未发现 High 级安全绕过。F-01/F-03/F-07 属于身份解析、守卫或清理边界，不是 Security1 密码学核心。

### 3.2 身份协商

| 检查项 | 结论 |
|---|---|
| 先请求 v2.1，失败同会话一次 v2.0 | **PASS**：`script.calls == ['2.1','2.0']`；两次失败 → `IDENTITY_INVALID` |
| v2.0 严格四字段 fail-closed | **PASS**：额外字段、错误 serviceId/version、空名、非法 gatewayId 均拒绝 |
| v2.1 严格解析 | **PASS（含 F-01）**：pins 1..4、小写 64 hex、pinAlg、port 1..65535、tls=false 携带 pin/port 拒绝；`gatewayName` 字符长度有 F-01 偏差 |
| expectedGatewayId 严格一致 | **PASS**：不一致 → `PROVISIONING_BINDING_IDENTITY_MISMATCH`，不重试/不切换 |
| MITM 版本剥离 | **条件通过**：单次回退按契约实现；Security1 CTR 无完整性，主动 BLE MITM 的理论降级属协议残余风险 |
| 身份端点不承载秘密 | **PASS**：仅 JSON 身份字段；无命令密钥/PoP/Wi-Fi 密码 |

### 3.3 秘密生命周期（SC-06）

- PoP：`request` 调用方持有；服务 `popCopy` 在 `finally` 清零；`Security1Session` 自持副本在 `destroy()` 清零；失败/取消/成功均经 `teardownBle`。
- Wi-Fi 密码：`passwordCopy` 在 `finally` 清零；`encodeSetConfig` 的 writer 清零；`GattChannel.request` 的密文缓冲清零；`WifiConfig` 只引用服务副本。
- session key / shared / popDigest / clientVerify：在 `Security1Session` 内用完即清零；平台 `SymKey.clearMem()` 在 stream destroy 时调用；X25519 私钥句柄为不透明平台对象（无法原地清零，残余 R-5）。
- 草稿：`SecretDraftStore.take` 复制并清零 entry；`LazyDraftCredentialPort` 回调副本清零；成功 `reissue` 后原 secret 销毁；**失败/取消时服务销毁原 draft id**。
- **缺口**：F-07（post-probe 异常时新 draft id 未销毁）；F-10（监听器异常导致服务锁死，虽不直接泄漏秘密，但阻碍清理/重试）。未发现通过日志/错误 details/HTTP 泄漏秘密。

### 3.4 GATT / MTU / `0x2901`

| 检查项 | 结论 |
|---|---|
| 仅按 `0x2901` 动态映射，不按顺序猜 | **PASS**：`GattEndpointMap.build`；NUL/空白清理；缺失/重名/不可读写 fail-closed |
| 必需 endpoint 集合 | **PASS**：`proto-ver`、`prov-session`、`prov-scan`、`prov-config`、`prov-ctrl`、`yaocore-id`；`yaocore-done` 可选 |
| 写→读同一 characteristic、严格串行 | **PASS（实现/服务路径）**；F-08 是队列超时边界，F-04 是 busy 重试口径 |
| 不实现通知订阅 | **PASS**：只用 write/read；无 notification |
| MTU 512 目标、<247 明确失败 | **PASS**：`requestMtu(512)`；非法/低值 → `PROVISIONING_MTU_TOO_SMALL`；不截断 protobuf |
| GATT busy | **部分**：队列未开始 busy 重试一次；已开始 busy 不重试（F-04） |
| 无自定义帧头 | **PASS**：protobuf/JSON 直接作为 payload；`encodeCustomJson` 无帧头 |
| `prov-ctrl` 未定义项 | **PASS**：reset 按 v5.2.3 field 11；stop 未定义 → `CAPABILITY_UNSUPPORTED`；正常流程不调用 |

### 3.5 Wi-Fi 扫描、下发与完成

| 检查项 | 结论 |
|---|---|
| 分页每页 4 条、最多 20 页/80 条 | **PASS**：`SCAN_PAGE_SIZE=4`、`MAX_SCAN_RESULTS=80` |
| 扫描总超时 15s | **部分**：状态轮询有 deadline；分页请求未受同一 deadline（F-09） |
| `set_config` → `apply_config` | **PASS**：顺序与 ACK 状态校验 |
| 1s 轮询、30s 总超时 | **PASS（轮询窗口）**：`WIFI_POLL_DELAY_MS=1000`、`WIFI_TOTAL_TIMEOUT_MS=30000`；单次慢请求可造成边界外耗时（低风险） |
| AuthError vs NetworkNotFound | **PASS**：分别映射 `PROVISIONING_WIFI_AUTH_ERROR` / `_NETWORK_NOT_FOUND` |
| 失败后销毁会话/断开/重连 | **PASS**：`provision` catch/finally 清理；重试新 keypair |
| 完成后 `yaocore-done` ACK / 旧固件可选 | **PASS**：`requiresDoneEndpoint`；无 endpoint 跳过；显式 `ok:false`/`status` 失败 → `DONE_REJECTED` |
| 隐藏 SSID 手动入口 | **部分**：服务可下发任意 request.ssid；扫描超时仍阻断；R-3 UI 待办 |

### 3.6 绑定探针

| 检查项 | 结论 |
|---|---|
| `/discover` 请求/响应 HMAC 双向验签 | **PASS（依赖 C-17）**：C-17 `probe` → `performDiscover` → `verifier.verify(...forDiscover(challenge))`；T-11 已测 |
| identity gatewayId 与 discover 严格一致 | **PASS**：`result.gatewayId`、`result.snapshot.gatewayId` 双重比较；不一致 terminal |
| profile 与 identity 一致 | **PASS**：`result.profile` 比较；TLS 时要求 `tlsPinMatched` 属于 pins |
| 板载 LED 执行回传 | **PASS**：`ackAccepted && boardLed && gatewayId 一致 && stateVerification=MATCH`；LED OFF best-effort |
| 失败不猜测/不切换候选 | **PASS**：identity mismatch 不重试；probe 失败有限 5 次后 `BINDING_PROBE_FAILED` |
| 不通过 BLE 发送命令密钥 | **PASS**：命令密钥只在 LAN probe；BLE 已 teardown |
| 不写绑定 | **PASS**：BindingProber 只 probe/control；C-07 负责 commit |
| 退避/总预算 | **部分**：F-05（首次延迟 off-by-one；30s 总预算未强制） |

### 3.7 状态机、取消与错误

- §16.9 正向链、任意非终态 `CANCEL`/`FAIL`、终态拒绝、`RESET` 均有 host 测试；`FAIL` 是已记录的 T-12 扩展（§9-4）。
- `cancel()` 停止扫描、断开、销毁 Security1/队列、清空 PoP/密码；host 断言 `disconnectCalls >= 1`、状态 `CANCELLED`。
- 错误映射总体按 §16.10：权限/蓝牙/找不到/多设备/连接/GATT/MTU/能力/PoP/Security1/identity/scan/auth/network/timeout/done/probe/LED/cancel/credential；F-04/F-06 是口径/组件级偏差。
- **F-10** 暴露监听器异常可锁死 `running`，属于可恢复性缺口。
- `R-2`（protocomm 非零 status → `SECURITY_HANDSHAKE_FAILED`）保持 fail-closed；D-4/architect 待命名。

### 3.8 测试质量

- **80 条新增用例有效**：13 codec（冻结向量/负 RSSI/严格 reader）、17 Security1/identity（RFC7748、错误 PoP、篡改 verify、CTR 连续、v2.0/v2.1、pin/expectedGatewayId）、31 GATT/状态机/Wi-Fi/绑定（0x2901、队列、状态矩阵、分页、Auth/Network/超时、LED/退避）、19 服务端到端/失败/取消/草稿/重试。
- **435/435 独立复跑通过**；无 skip/todo；证据 TAP 与复跑一致。
- **缺口**：F-01（长中文名）、F-02（二次扫描设备刷新）、F-03（无 draft 且无 expectedGatewayId）、F-04（平台 write busy）、F-05（延迟序列/30s 预算）、F-07（post-probe 监听器异常）、F-08（队列超时并发）、F-10（监听器异常恢复）、F-11（>32-bit length）均无对应测试。补测后才能证明修复。
- **设备骨架诚实**：`entry/src/ohosTest/ets/test/ble/BleProvisioningDevice.test.ets` 已注册，覆盖 step0 向量、0x2901、v2.0 多余字段、平台 crypto 全握手、适配器构造；`onDeviceTest` 明确 `BLOCKED`，未写成 PASS。

### 3.9 过程、仓库与 i18n

- 31 路径全部在 handoff `writes`/`commit_paths` 范围；`entry/src/main/module.json5` 未修改，`ACCESS_BLUETOOTH` 仍归 T-17（R-6）。
- 无构建产物/`.hap`/`.har`/`oh_modules`/秘密入库；证据日志在 `entry/src/test/evidence/`；`git status` clean。
- 输入 pin 7/7 一致；快照 ref 存在；commit 将使用 `docs(review): ...` 主题。
- i18n：BLE 代码无硬编码 UI/错误文案；`provisioning.error.*` 在两种 locale 均存在；无新增重复代码变体。
- `TransportBoundary` 已把 13 个新增纯逻辑文件纳入 host-safe import 检查；生产代码无 `@ohos`/`@kit` import（适配器除外）。

---

## 4. Verdict

**CHANGES_REQUIRED**

安全核心总体成立：Security1 派生/连续 CTR/常数时间验证/失败销毁、v2.0 严格解析与 v2.1 单次回退、GATT `0x2901` fail-closed、Wi-Fi 分页/30s/错误分类、LAN 双向验签 + gatewayId + LED、全路径 teardown 与秘密清零均有代码与 host 证据；435/435、codelinter、clean assemble、ohosTest 编译均通过；设备项诚实 `BLOCKED`。**未发现 High 级安全绕过。**

但不能在当前 revision 授予 CQG-T12/STABLE，原因是多项**明确的契约/正确性偏差**与**测试缺口**：

1. **F-01**：合法长中文 `gatewayName` 被按 UTF-8 字节误拒绝（identity schema 按字符）。
2. **F-02**：`lastDevice` 不随新扫描更新，省略 `request.device` 会连接过期设备。
3. **F-03**：empty-draft 路径未强制 `expectedGatewayId`，违反 §16.8 的守卫。
4. **F-05**：探针首次退避 off-by-one；30s 总预算未强制。
5. **F-07**：post-probe 异常时新 draft id 未销毁（SC-06）。
6. **F-04/F-06/F-08/F-09/F-10/F-11**：busy 重试口径、组件错误码、队列超时并发、扫描分页 deadline、监听器异常锁死、length varint 严格性。

修复后必须：

1. 重跑 `entry/src/test/run-host-tests.sh`、`codelinter -c code-linter.json5 -p default .`、`hvigorw clean assembleHap --no-daemon`、ohosTest `assembleHap`；
2. 补齐 F-01/F-02/F-03/F-04/F-05/F-07/F-08/F-10/F-11 的负例/回归用例；
3. 由**未参与修复**的 reviewer 复审受影响代码；
4. 由 solution-architect 裁定 R-1（草稿重签）与 R-2/D-4（非零 Status 错误码）；R-3/R-4/R-6/R-7 保持跟踪；
5. 设备可用后由 T-19 执行真实 BLE/MTU/0x2901/平台 X25519/AES-CTR/真实网关端到端；在此之前不得把 C-19 标为 `STABLE`。

**未授予**：CQG-T12、Integration Gate、Stage Gate、用户验收。

---

## 5. 残余风险与跟踪项

| ID | 风险 | 级别 | 下一步/所有者 |
|---|---|---|---|
| R-1 | 草稿重签语义未经 architect 确认；C-23 必须使用 `result.credentialDraftId` | Medium | solution-architect；C-07 当前 `draftId === result.credentialDraftId` 自洽，但需正式裁定 |
| R-2 | protocomm 非零 `Status` 统一映射 `SECURITY_HANDSHAKE_FAILED`，无专用 stable code | Medium | D-4/architect 命名；当前 fail-closed |
| R-3 | 隐藏 SSID 手动入口未由服务显式支持；扫描失败仍阻断 | Low | T-13/DES-B UI；服务可下发任意 SSID |
| R-4 | identity schema 允许 `gatewayId` 含 `:`，C-02 模型拒绝 | Low | C-02/schema owner 统一；当前 fail-closed |
| R-5 | 真实 BLE/MTU/0x2901/平台 X25519/AES-CTR/真实网关未设备验证 | High（证据） | T-19；`onDeviceTest` 当前 BLOCKED |
| R-6 | `module.json5` 未声明 `ACCESS_BLUETOOTH`；运行时权限会被拒绝 | High（T-17 依赖） | T-17；适配器已预留 `requestPermissionsFromUser` |
| R-7 | `prov-ctrl` stop 未定义；正常流程不依赖 | Low | 固件协同/确认；reset 已按 v5.2.3 实现 |
| R-8 | Security1 AES-CTR 无完整性；主动 BLE MITM 可理论触发 v2.0 回退/篡改 | Medium（协议固有） | 记录威胁模型；不得宣称“AEAD/完整 MITM 防护”；T-19 射频评估 |
| R-9 | TEST-001 SEC-N21/N24 状态未更新；CQG 需记录 host/设备分层 | Low（过程） | CQG-T12；不得以本报告代替 Gate |
| R-10 | 无生产组合根；HAP source-map 无法证明 C-19 运行时装配 | Low/Medium | T-19/T-20；当前 host 静态检查有效 |
| R-11 | `PROVISIONING_*` 错误码资源键已存在；无新增 i18n 文案 | Info | 保持 locale parity；T-17 UI 接入时复扫 |
| R-12 | 设备测试骨架已注册但整体 BLOCKED；`onDeviceTest` 日志为 BUILD FAILED（无设备） | High（证据） | T-19；不得写成 PASS |

---

## 6. 独立声明与限制

- 本报告由 `agent:quality-reviewer` 独立出具；评审者未编写 T-12 产品代码、测试或实现报告，未修改任何被审代码；唯一写入为本报告。
- 评审基于 `27dc537` 与上表 pin 输入；独立执行了 host 435/435、codelinter、clean assemble、ohosTest assemble、`git diff`/pin 校验，并用现有 fakes 做了只读复现（F-02/F-07/F-10/F-11）与 `ProtoVerParser`/`ProtobufReader` 直接调用（F-06/F-11）。
- 未覆盖：真实设备/模拟器、真实 BLE 射频、真实平台 X25519/AES-CTR、真实 ESP-IDF 网关、真实 LAN/HTTPS pin、板载 LED 硬件、API 14/15 安装。上述均为 `BLOCKED`/`UNAVAILABLE`，不是 PASS。
- 本报告不替代 CQG、Integration Gate 或 Stage Gate。

---

## 7. Handoff

```text
STATUS: RETURNED_FOR_GATE / CHANGES_REQUIRED
SUMMARY: T-12 C-19 安全核心（Security1、v2.0/v2.1 identity、0x2901、Wi-Fi、LAN 探针 + LED、清理）总体成立；host 435/435、codelinter、clean assemble、ohosTest 编译均独立复验通过，设备项诚实 BLOCKED。未发现 High 级安全绕过，但 F-01（中文 gatewayName 按字节误拒绝）、F-02（lastDevice 不随新扫描更新）、F-03（empty-draft 未强制 expectedGatewayId）、F-05（探针退避 off-by-one/30s 预算未强制）、F-07（post-probe 新 draft 未销毁）等明确契约/清理偏差，不能授予 CQG-T12/STABLE。
ARTIFACTS_CREATED: artifacts/70-review/t12-review.md
ARTIFACTS_UPDATED: none
RISKS: R-1 草稿重签与 C-23 集成（architect）；R-2/D-4 非零 Status 错误码；R-5 真机 BLE/平台 crypto（BLOCKED）；R-6 module.json5 ACCESS_BLUETOOTH（T-17）；R-8 Security1 CTR 无完整性；R-12 设备测试 BLOCKED。
VALIDATION: host 435/435（exit 0）；codelinter No defects（exit 0）；hvigorw clean assembleHap BUILD SUCCESSFUL（exit 0）；ohosTest assembleHap BUILD SUCCESSFUL（exit 0）；31 路径/无 module.json5/无秘密或构建产物；输入 pin 7/7 一致；设备 onDeviceTest BLOCKED。
NEEDS_CLARIFICATION: R-1 由 solution-architect 裁定；R-2/D-4 错误码命名由 architect/D-4 owner 统一；R-3/R-4 由 DES-B/C-02 owner 处理；R-6 由 T-17 声明权限。
NEXT_ACTION: implementation-engineer 按 F-01/F-02/F-03/F-04/F-05/F-07/F-10 优先修复并补齐负例（F-06/F-08/F-09/F-11 一并评估）；重跑四项命令；独立 reviewer 复审；T-19 设备验收前不得标 STABLE。
```
