# T-12 BLE 配网（C-19）实现报告

- **Artifact ID**: T12-BLE-IMPLEMENTATION-001
- **Producer**: agent:implementation-engineer
- **Task**: T-12 / `wp-040-ble`（task 分支 `task/wp-040-ble`，父分支 `feat/yaocore-app`）
- **Base commit**: `3834f5dadcf253816bd1ed6f14eb7e829367311f`
- **Date**: 2026-10-17
- **Workflow**: STANDARD / GATED_AUTO
- **Status**: 实现与本机验证完成，等待独立 Review / Component Quality Gate。
- **权威契约**: DES-001A §16（C-19）、§20、§3.2、§23；ADR-002 §3；`input/existing/docs/BLE配网设计.md`；identity v2.0 schema；`contract-baseline.md`；`project-constraints.md`；`test-plan.md`。

> **SUPERSEDED（F-04 / GATT busy 口径）**：本报告冻结于原实现 `27dc537`。§2.1 `GattChannel` 行“GATT busy 仅未开始时重试一次（50ms）”及 §3 相关表述已过时；当前行为（仅确认写 busy `2900011`/`2901004` 重试一次并复用同一密文；`2900099`/未知写失败不重试；读 busy 终止；队列获取超时不重试）以 `t12-fix-report.md` 与 `t12-fix2-report.md` 为准。R2-05 / REV-T12-002。

---

## 1. 结论摘要

完成 C-19 `BleProvisioningService` 及配套纯逻辑组件、平台 BLE 适配器、host 测试与 ohosTest 设备骨架：

- GATT 发现严格使用 `0x2901` User Description 动态映射 endpoint，不按 characteristic 顺序猜测。
- Security1 使用 X25519 → `SHA256(PoP) XOR shared` → AES-256-CTR/NoPadding 单一连续流；step0/step1、client/device verify、CTR 连续性、PoP 失败销毁均有 host 向量/负例。
- 身份协商 v2.1 → 同会话一次 v2.0 回退；v2.0 严格四字段 fail-closed。
- Wi-Fi 分页扫描（每页 4 条）、`set_config` → `apply_config`、30s `get_status` 轮询、AuthError/NetworkNotFound 区分、`yaocore-done` ACK。
- 绑定探针要求 `/discover` 已验签、`gatewayId` 严格一致、profile/pin 一致、板载 LED `BOARD_LED_ON` 执行回传；BLE 成功不直接产生绑定。
- 任意取消/失败/成功路径停止扫描、断开 GATT、销毁 Security1 流与队列、清零 PoP/Wi-Fi 密码/中间密钥。
- 本机验证：clean assemble、codelinter、ohosTest 编译全部通过；host 435/435 通过（其中新增 C-19 测试 80 项）。设备/射频/X25519 平台实现仍为 `BLOCKED_ON_DEVICE_RUNNER`。

---

## 2. 实现范围与文件清单

### 2.1 新增生产代码（`entry/src/main/ets/service/ble/`）

| 文件 | 职责 |
|---|---|
| `BleProvisioningPorts.ets` | §16.1 公共类型、`IBleProvisioningClient`、`BleTransport`/`BleConnection` 端口、`ProvisioningState`、`BleScanFilter`、`WifiAp`、请求/监听器 |
| `Protobuf.ets` | 严格 protobuf varint/length-delimited/int32 编解码；负 int32 10 字节二补码；截断/超长/越界/未知 wire type 拒绝 |
| `ProtocommCodec.ets` | SessionData step0/step1、Wi-Fi config/scan/status、自定义 JSON；冻结向量 |
| `GattEndpointMap.ets` | SERVICE_UUID、`0x2901` endpoint 映射、必需端点/重名/不可读写 fail-closed |
| `GattRequestQueue.ets` | 单飞 write→read 队列、超时 `PROVISIONING_GATT_BUSY`、reset/destroy |
| `GattChannel.ets` | 明文/密文请求统一串行；CTR 加解密在队列槽内完成；~~GATT busy 仅未开始时重试一次（50ms）~~ **已过时，见顶部 SUPERSEDED 注记与 `t12-fix2-report.md`** |
| `ProtoVerParser.ets` | `proto-ver` 能力门禁（v1.1、sec_ver=1、no_sec/no_pop、wifi_scan、yaocore 2.0） |
| `Security1Session.ets` | X25519/CTR 会话状态机、step0/step1、常数时间 verify、`destroy()` 清零 |
| `IdentityNegotiator.ets` | v2.1 严格解析、v2.0 同会话一次回退、pin/常量/多余字段 fail-closed、expectedGatewayId |
| `WifiProvisioningFlow.ets` | 分页扫描、set/apply、1s 轮询/30s 超时、Auth/NetworkNotFound、done ACK |
| `BindingProbe.ets` | `DraftCredentialPort`、草稿惰性消费/成功后重签、有限退避探针、gatewayId/profile/pin、板载 LED |
| `ProvisioningStateMachine.ets` | §16.9 转移矩阵、取消/失败/重置 |
| `BleProvisioningService.ets` | C-19 主编排：扫描/连接/MTU/发现/proto-ver/Security1/identity/Wi-Fi/done/探针/清理 |
| `BleSupport.ets` | 可注入 delay、取消、错误映射辅助 |
| `adapters/OhosBleTransport.ets` | 生产 BLE 适配器（`@ohos.bluetooth.ble`/`access`/`abilityAccessCtrl`），COMPILED_ONLY |

### 2.2 修改

| 文件 | 变更 |
|---|---|
| `entry/src/main/ets/service/ble/BleProvisioningPorts.ets` | 由 T-11 最小面扩展到 §16.1 完整面；保留字节缓冲 PoP/密码（SC-06） |
| `entry/src/test/host/GatewayMock.test.mjs` | 适配新 `BleScanFilter(serviceUuid, namePrefix?)` |
| `entry/src/test/host/TransportBoundary.test.mjs` | 将 13 个新增纯逻辑文件纳入 host-safe import 检查 |
| `entry/src/ohosTest/ets/test/List.test.ets` | 注册 C-19 设备骨架 |

### 2.3 测试与证据（`entry/src/test/`）

| 文件 | 内容 |
|---|---|
| `host/BleFakes.mjs` | Node crypto X25519/SHA-256/AES-CTR oracle、ESP-IDF 风格 fake gateway、fake BLE transport/connection、fake gateway client |
| `host/BleCodec.test.mjs` | 13 项：protobuf/scan/config/session/负 RSSI/严格边界 |
| `host/BleSecurity.test.mjs` | 17 项：RFC7748、Security1 握手/CTR/PoP、identity v2.0/v2.1 |
| `host/BleGattFlow.test.mjs` | 31 项：endpoint map、proto-ver、队列、状态机、Wi-Fi flow、binding probe |
| `host/BleService.test.mjs` | 19 项：C-19 全流程/失败/取消/清理/草稿/重试 |
| `evidence/t12-*.log` / `.tap` | 四项验证命令、ohosTest 编译、onDeviceTest BLOCKED 原始输出 |

未修改 `entry/src/main/module.json5`（权限声明归 T-17，见 §8）。

---

## 3. 契约对照

| 契约/约束 | 实现 | 证据 |
|---|---|---|
| DES-A §16.1 公开面 | `BleProvisioningService` 实现 `IBleProvisioningClient`；`startScan`/`stopScan`/`provision`/`cancel` | `BleService.test.mjs` |
| §16.1.3 BLE 端口 | `BleTransport`/`BleConnection`/refs，无平台类型泄漏 | `TransportBoundary` host-safe 检查 |
| §16.2 GATT 发现 | `0x2901` 读取、NUL/空白清理、精确匹配、必需端点、重名/属性/不可读 fail-closed、单飞队列 | `BleGattFlow` 6 项 + `BleService` 2 项 |
| §16.3 proto-ver | 明文 `ESP`、v1.1/sec_ver=1/no_sec/no_pop/wifi_scan/yaocore 2.0，失败不降级 | `BleGattFlow` 3 项；`BleService` capability |
| §16.4 Security1 | X25519 raw 32B、SHA256(PoP) XOR、AES-256-CTR 连续流、常数时间 verify、失败销毁/重连 | `BleSecurity` 5 项；`BleService` retry |
| §16.5 protobuf | 冻结 step0/Wi-Fi/scan 向量、负 RSSI、严格 reader、无自定义帧头 | `BleCodec` 13 项 |
| §16.6 identity | v2.1 先请求；失败同会话一次 v2.0；v2.0 封闭四字段；额外字段/常量/pin fail-closed；expectedGatewayId | `BleSecurity` 12 项；`BleService` 2 项 |
| §16.7 Wi-Fi | 阻塞扫描、每页 4 条、15s/20 页上限、set→apply、1s 轮询/30s、AuthError vs NetworkNotFound、done ACK/旧固件可选 | `BleGattFlow` 6 项；`BleService` 3 项 |
| §16.8 绑定探针 | 有限退避、`/discover` 验签由 C-17 probe 保证、gatewayId/profile/pin 严格一致、LED ON 执行确认、LED OFF best-effort、无绑定写入 | `BleGattFlow` 11 项；`BleService` 3 项 |
| §16.9 状态机/清理 | 全转移矩阵；任意非终态 CANCEL/FAIL；stopScan/disconnect/session destroy/queue destroy/zeroize/draft 清理 | `BleGattFlow` 3 项；`BleService` cancel/MTU/PoP |
| §16.10 错误 | 按表映射权限/蓝牙/找不到/多设备/连接/GATT/MTU/能力/PoP/Security1/identity/scan/auth/network/timeout/done/probe/LED/cancel/credential | 各负例断言 |
| §16.11 host seam | 纯逻辑无 `@ohos/@kit`；平台仅适配器；fake BLE + Node crypto oracle | `TransportBoundary`；host 435 项 |
| ADR-002 §3.2 | v2.1 `security.lan` 可选；无 security = HMAC-only；pin 小写 64 hex、1..4、`sha256-spki-der`；v2.1→v2.0 仅旧固件路径 | `BleSecurity` identity 组 |
| BLE §2-§7 | 广播 UUID/名称、MTU 512/≥247、0x2901、写→读、Security1、分页、30s、probe+LED、状态机 | 同上 |
| PR-06 | BLE 名称/MAC 不作身份；gatewayId 来自 Security1 identity 并与 discover 严格一致 | `BindingProber` |
| PR-07 | identity 封闭 schema，多余字段/常量不符 `PROVISIONING_IDENTITY_INVALID` | `BleSecurity` |
| PR-12 | GATT 严格串行；不按顺序猜 endpoint；不降级 Security0 | `GattRequestQueue`/`GattEndpointMap`/`ProtoVerParser` |
| PR-13 | 10s 扫描提示、有限探针退避、MTU 512/247 | `BleService`/`BindingProber` |
| SC-04/SC-05 | PoP 仅内存；与命令密钥分离；不通过 BLE 发送命令密钥 | `BleProvisioningPorts`/`BindingProbe` 注释与实现 |
| SC-06 | 密码/PoP 副本、session key、protobuf 明文草稿在退出路径清零 | `BleProvisioningService` finally、`Security1Session.destroy`、`ProtobufWriter.destroy`、`WifiProvisioningFlow.apply` |
| SC-11 | 生产代码不 import Mock；Mock 边界测试继续通过 | `TransportBoundary` |
| CP-03 | 无真机不写 PASS；设备项 BLOCKED | §6 |

---

## 4. Security1 与向量结果

### 4.1 派生与流

```text
client keypair  = CryptoPort.generateX25519KeyPair()       // raw 32B public, 不发送 DER
shared          = X25519(client_private, device_pub)
pop_digest      = SHA256(UTF8(PoP))
session_key[i]  = shared[i] XOR pop_digest[i]              // i=0..31
iv              = device_random                            // 16B
stream          = AES-256-CTR(session_key, iv)
client_verify   = stream.process(device_pub)
plain           = stream.process(device_verify) == client_pub (constant-time)
```

`session_key`/`pop_digest`/`shared` 在 stream 建立后立即清零；`client_verify` 临时缓冲清零；失败/取消/断开调用 `destroy()` 清零 PoP 副本并销毁 stream。

### 4.2 冻结向量（host 实测）

| 向量 | 期望 | 实测 |
|---|---|---|
| step0（pub `00 01 … 1f`） | `10015a25a201220a20000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f` | 一致 |
| `get_status` | `5200` | 一致 |
| `apply_config` | `08047200` | 一致 |
| scan start | `52080801100018002078` | 一致 |
| scan status | `08026200` | 一致 |
| scan result（start=0,count=4） | `08047204…` | `0804720408001004` |
| 负 RSSI `-100` value bytes | `9cffffffffffffffff01` | 一致 |
| RFC 7748 §6.1 scalar/u/expected | `c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552` | Node X25519 oracle 一致 |

### 4.3 负例

- 错误 PoP：device 返回不可验证的 `device_verify_data` → `PROVISIONING_POP_INVALID`，session `DESTROYED`，后续 `encrypt` 抛 `PROVISIONING_SECURITY_HANDSHAKE_FAILED`。
- 篡改 `device_verify_data`：同样 `POP_INVALID` + `DESTROYED`。
- 截断/错误长度/错误 status 的 SessionData：`PROVISIONING_SECURITY_HANDSHAKE_FAILED`。
- 同一明文两次加密密文不同（CTR 连续推进）；gateway 侧并行流可解密两次请求。
- PoP 错误后修正并重试：`keyPairCalls` 从 1→2，两次 step0 的客户端公钥不同，证明不复用 CTR/密钥。
- 所有 host Security1 使用 Node `crypto`（X25519/SHA-256/AES-256-CTR）作为独立 oracle，不是同一实现自证。

---

## 5. 身份协商结果

- v2.1 + `security.lan.tls=true`：返回 `IdentityVersion.V21`、pins/port/pinAlg；探针使用 `P-TLS-PIN`。
- v2.1 无 `security`：返回 V21 + 无 TLS（HMAC-only），探针 `P-HMAC`。
- v2.1 `security.lan.tls=false`：同上；若同时携带 port/pins/pinAlg → fail-closed。
- v2.1 解析失败/旧固件返回 v2.0：同会话发送一次 v2.0 请求；请求序列实测 `['2.1','2.0']`。
- 两次均失败、额外字段、错误 `serviceId`、大写 pin、非法 pinAlg、空/超长名称 → `PROVISIONING_IDENTITY_INVALID`。
- 多 pin（1..4）合法；`expectedGatewayId` 不一致 → `PROVISIONING_BINDING_IDENTITY_MISMATCH`，不重试、不切换候选。
- 身份端点不承载 PoP/命令密钥/Wi-Fi 密码。

---

## 6. 状态机、取消与清理

主状态机按 §16.9 实现：`IDLE → PERMISSION → SCANNING → CONNECTING → DISCOVERING → CAPABILITY_CHECK → SECURITY_HANDSHAKE → SECURE_IDENTITY → AP_SCANNING → SENDING_CREDENTIALS → WAITING_FOR_WIFI → DISCOVERING_ON_LAN → BOUND`。

- `CANCEL` 可从所有非终态进入 `CANCELLED`；`FAIL`（T-12 扩展事件）从所有非终态进入 `FAILED`；终态拒绝 CANCEL/FAIL；`RESET` 回 `IDLE`。
- 非法转移 → `CONFIGURATION_ERROR`。
- 每次 `provision` 退出（成功/失败/取消）执行：
  1. `transport.stopScan()`；
  2. `connection.disconnect()`（并将引用置空，幂等）；
  3. `Security1Session.destroy()`；
  4. `GattRequestQueue.destroy()`；
  5. 清零 Pop/Wi-Fi 密码副本；
  6. 失败/取消销毁请求草稿；成功由 C-07 消费重签后的草稿。
- host 断言：MTU 失败/PoP 失败/Auth 失败均 `disconnectCalls >= 1`；取消后状态 `CANCELLED`；草稿失败后 `take(originalId)` 抛 `PROVISIONING_CREDENTIAL_MISSING`。

---

## 7. 验证证据（本机实际执行）

> 所有命令 cwd 为仓库根。日志位于 `entry/src/test/evidence/`。

| 命令 | 结果 | 日志 |
|---|---|---|
| `ohpm install` | `install completed in 0s 46ms` | `t12-ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | `BUILD SUCCESSFUL in 4 s 938 ms` | `t12-clean-assemble.log` |
| `codelinter -c code-linter.json5 -p default .` | `No defects found in your code.` | `t12-codelinter.log` |
| `entry/src/test/run-host-tests.sh` | `435 tests / 435 pass / 0 fail` | `t12-host-node-tests.tap` |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | `BUILD SUCCESSFUL in 7 s 588 ms` | `t12-ohosTest-assemble.log` |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default onDeviceTest --no-daemon` | `BLOCKED`：`GenerateDeviceCoverage` → `need connect-key? please confirm a device` | `t12-onDeviceTest-blocked.log` |

### 7.1 Host 测试统计

- 基线（T-11 合并后）：355 项。
- 新增 C-19：**80 项**（`BleCodec` 13、`BleSecurity` 17、`BleGattFlow` 31、`BleService` 19）。
- 合计：**435 项，全部通过**。

覆盖对应关系：

| 任务要求 | 测试 |
|---|---|
| Security1 向量/CTR 连续性/验证失败 | `C19_Security1_*`、`C19_ProtocommCodec_step0*` |
| 身份 v2.0 fail-closed / v2.1 协商与回退 | `C19_IdentityNegotiator_*` |
| Wi-Fi 分页/30s 超时/错误区分 | `C19_WifiProvisioningFlow_*`、`C19_BleProvisioningService_wifi*` |
| 探针 gatewayId 不一致/LED/退避 | `C19_BindingProber_*`、`C19_BleProvisioningService_probe*` |
| 清理与清零 | `C19_BleProvisioningService_cancel/connectAndMtu/pop/draft*` |
| GATT 0x2901/必需端点/重名/不可读写 | `C19_GattEndpointMap_*` |
| proto-ver 降级/缺能力 | `C19_ProtoVerParser_*` |
| 状态机/非法转移 | `C19_ProvisioningStateMachine_*` |
| RFC7748 | `C19_Security1_rfc7748Vector` |
| 负 RSSI/int32 | `C19_ProtocommCodec_negativeRssi*`、`scanResult*` |

---

## 8. 设备限制与 COMPILED_ONLY 项

| 项 | 状态 | 说明 |
|---|---|---|
| 真实 BLE 扫描/连接/MTU/GATT/0x2901 | `COMPILED_ONLY` / `BLOCKED` | 无真机/模拟器；`OhosBleTransport` 仅编译。 |
| 真实 HarmonyOS X25519/AES-CTR | `COMPILED_ONLY` / `BLOCKED` | host 用 Node crypto oracle；ohosTest 骨架已用 `CryptoService` 写真实平台握手，待设备执行。 |
| BLE 射频/广播/名称过滤 | `UNAVAILABLE` | CP-03；测试计划 §11。 |
| `onDeviceTest` | `BLOCKED` | `GenerateDeviceCoverage` 要求连接设备；未写 PASS。 |
| `ohos.permission.ACCESS_BLUETOOTH` 声明 | **T-17 待办** | 本任务未改 `module.json5`；适配器已预留运行时 `requestPermissionsFromUser`。 |

设备侧骨架：`entry/src/ohosTest/ets/test/ble/BleProvisioningDevice.test.ets`，包含 step0 向量、0x2901 映射、v2.0 多余字段 fail-closed、真实平台 crypto 的完整 Security1 握手、`OhosBleTransport` 构造；已注册到 `List.test.ets`，但运行结果为 `BLOCKED_ON_DEVICE_RUNNER`。

---

## 9. 偏离项与 UNRESOLVED

1. **PoP/Wi-Fi 密码载体**：DES-A §16.1 草图用 `string`；实现保留 T-11 的 `Uint8Array`，以便 SC-06 原地清零。字符串不可清零，故不采用。语义不变。
2. **端口扩展**：`BleScanFilter` 现按 §16.1 为 `(serviceUuid, namePrefix?, timeoutMs)`；`BleProvisioningDevice` 增加 `serviceUuids`；`BleProvisioningRequest` 增加 `device/credentialDraftId/familyId/expectedGatewayId`。T-11 的 `BleScanDevice` 保留为兼容子类；Mock 与 T-11 测试已同步。
3. **进度监听器**：保留 T-11 的 `onStage` 为必选；DES-A 的 `onStateChanged/onAccessPoints/onError/onCompleted` 设为可选，避免 T-11 Mock/小消费者被迫实现。运行时服务会回调它们（若提供）。
4. **`ProvisioningEvent.FAIL`**：DES-A 事件表没有通用的连接/GATT/MTU 失败事件；T-12 增加 `FAIL`，其余事件保持原文。
5. **`WifiProvisioningFlow` 内部 seam**：方法消费 `SecureGattChannel`（request/requestPlain）而非裸 `connection+endpoints+session`；这样 CTR 顺序与单飞队列由同一 channel 拥有，行为与 §16.7 等价。设备/身份/Wi-Fi 对外行为不变。
6. **`IdentityNegotiator` 构造**：DES-A 草图 `constructor(codec)`；本实现 codec 为静态方法，构造无参；`negotiate(session, send, expectedGatewayId?)` 会先检查 session `ESTABLISHED`。
7. **草稿生命周期**：`SecretDraftPort` 没有非消费式 peek。C-19 在探针首次使用时 `take(request.credentialDraftId)`；成功后用同一 secret `put()` 重签一个新 draft id 写入 `BleProvisioningResult.credentialDraftId`，失败/取消销毁。C-07 仍按 `draftId === result.credentialDraftId` 消费；原 id 被 C-19 消费，重签 id 为一次性。此语义需 architect 确认（R-1）。
8. **`prov-ctrl`**：按 ESP-IDF 5.2 `wifi_ctrl.proto` 实现 `encodeCtrlReset()`（msg=1，`cmd_ctrl_reset` field 11）；`encodeCtrlStop()` 因 proto 无对应消息标 `UNRESOLVED-BLE-CTRL-PROTO`，抛 `PROVISIONING_CAPABILITY_UNSUPPORTED`。正常配网流程不调用 prov-ctrl。
9. **protocomm 非零 status 的错误码**：`set_config/apply_config/get_status` 返回非 0 `Status` 时映射为 `PROVISIONING_SECURITY_HANDSHAKE_FAILED`（安全信道协议失败）；DES-A §16.10 无更细码，待 D-4/architect 命名（R-2）。
10. **无效 IPv4 / connected 无 IP**：映射为 `PROVISIONING_SECURITY_HANDSHAKE_FAILED`（协议响应非法），不伪造 `WIFI_TIMEOUT`。
11. **隐藏 SSID 手动入口**：服务流程始终执行扫描；“跳过扫描、手输 SSID”属 UI/DES-B 路径，本任务未新增请求标志（R-3）。
12. **MTU 事件超时**：适配器在 12s 未收到 `BLEMtuChange` 时抛 `PROVISIONING_CONNECT_FAILED`（无法得到真实值，不能谎报 247/512）。
13. **`familyId`**：§16.1 请求字段；为兼容 T-11 Mock 构造器保持可选，探针前必须非空，否则 `CONFIGURATION_ERROR`。
14. **`device` 可省略**：正常 UI 应传 `request.device`；省略时服务使用最近一次扫描的唯一设备，多于一个 → `PROVISIONING_MULTIPLE_DEVICES`。
15. **`BleProvisioningIdentity` 的 gatewayId**：schema 允许 `:`，C-02 模型拒绝 `:`；实现先按 schema 校验、再构造模型，冒号会被 fail-closed 为 `PROVISIONING_IDENTITY_INVALID`。属既有 C-02 边界（R-4）。

---

## 10. 风险

| ID | 风险 | 影响 | 缓解 |
|---|---|---|---|
| R-1 | 草稿重签语义未经 architect 确认 | C-23/C-07 集成时可能期望原 draft id | 报告中显式记录；Review 时请 architect 裁定；当前 C-07 只要求 `draftId === result.credentialDraftId` |
| R-2 | protocomm 非零 status 无专用错误码 | UI 文案可能落到 security handshake failed | 待 D-4/architect 命名；当前 fail-closed |
| R-3 | 隐藏 SSID 手动路径未实现 | 隐藏网络用户需 UI 另走路径 | T-13/DES-B 决定；服务扫描失败不会伪造成功 |
| R-4 | schema 与 C-02 模型对 `:` 不一致 | 含冒号 gatewayId 的网关无法绑定 | 保持 fail-closed；需 C-02/schema owner 统一（非 T-12 写范围） |
| R-5 | 真实 BLE/MTU/0x2901/平台 crypto 未设备验证 | 互操作风险 | T-19 设备验收；ohosTest 骨架已就绪 |
| R-6 | `module.json5` 无蓝牙权限声明 | 真机运行时权限请求会被拒绝 | T-17 声明；适配器已调用 `requestPermissionsFromUser` |
| R-7 | `prov-ctrl` stop 未定义 | 若固件要求 stop 才能完成清理，当前不发送 | 正常流程不依赖；Review 确认 |

CQG-T11 残余带入：PB-03/TLS 运行时待设备；D-4 错误码命名待 architect；F-08 设备占位测试待 T-19；API 14 构建基线未回退（`compatibleSdkVersion 5.0.2(14)` 未改）。

---

## 11. CQG-T12

```text
CQG-T12
- build: hvigorw clean assembleHap --no-daemon -> PASS (entry/src/test/evidence/t12-clean-assemble.log)
- lint: codelinter -c code-linter.json5 -p default . -> PASS (t12-codelinter.log)
- host tests: entry/src/test/run-host-tests.sh -> PASS (435/435; 80 new C-19)
- ohosTest compile: assembleHap entry@ohosTest -> PASS (t12-ohosTest-assemble.log)
- device tests: onDeviceTest -> BLOCKED (no device/signing; t12-onDeviceTest-blocked.log)
- contract vectors: step0/Wi-Fi config/scan frames/negative RSSI/RFC7748 -> PASS
- security: no secret logs / fail-closed / PoP-Wi-Fi zeroization / mock exclusion -> PASS
- traceability: FR-GW-001/002/003; PR-06/07/12/13; SC-04/05/06; ADR-002 §3.2 -> host tests listed in §7.1
```

`onDeviceTest`、真实 BLE 射频、真实平台 X25519/CTR 均不得记为 PASS。

---

## 12. 下一步

1. `quality-reviewer` 对 T-12 聚焦复审（§16 全条、秘密生命周期、错误映射、草稿语义）。
2. architect 裁定 R-1（草稿重签）与 R-2（protocomm 非零 status 错误码）。
3. T-17 在 `module.json5` 声明 `ohos.permission.ACCESS_BLUETOOTH`。
4. T-19 设备验收：真实 BLE 扫描/连接/MTU/0x2901、平台 X25519/AES-CTR、真实网关端到端。
5. T-13/UI 消费 `IBleProvisioningClient` 时传 `request.device`、`familyId`，并实现隐藏 SSID/手动入口（R-3）。
