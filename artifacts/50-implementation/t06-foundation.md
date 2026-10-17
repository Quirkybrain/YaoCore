# T-06 基础模型、协议 DTO/映射实现报告

- **Artifact ID**: IMP-T06-FOUNDATION
- **Producer**: agent:implementation-engineer
- **Type**: Implementation / Verification Evidence
- **Status**: Proposed（本地验证完成；待独立评审与 CQG-T06 Gate）
- **Date**: 2026-10-17
- **Task**: T-06 / `wp-012-foundation`（task 分支 `task/wp-012-foundation`，父分支 `feat/yaocore-app`，base commit `5901cd7081dc5a9b12f5d4f51dbed71ef7bb5ae8`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`
- **Upstream 契约**:
  - DES-A `artifacts/40-detailed-design/des-001a-foundation-transport.md` §3.2、§4、§5、§6、§18、§23、§27.4
  - DES-B `artifacts/40-detailed-design/des-001b-domain-presentation.md` §8.1.4/§8.1.5/§8.3.3、§23
  - `artifacts/20-architecture/contract-baseline.md` §2.4/§4.1
  - `artifacts/60-testing/test-plan.md` §4/§5/§10
  - `input/api/protocol/*.schema.json`、HMAC/响应/发现向量
- **Downstream**: T-07（签名/验签/nonce）、T-08（存储）、T-10/T-11/T-12/T-14、CQG-T06、T-19/T-20

---

## 0. 摘要

| 项 | 结果 | 证据 |
|---|---|---|
| C-01 公共类型/常量/工具 | **实现完成** | 21 个文件；`Foundation.test.mjs` 16 用例 |
| C-02 领域模型共享面 | **实现完成** | 9 个文件；`DomainModels.test.mjs` 10 用例 |
| C-03 协议 DTO/映射/校验 | **实现完成** | 13 个文件；40 个协议用例 |
| Node host 测试 | **PASS 81/81** | `evidence/t06-host-node-tests.tap` |
| `ohpm install` | **PASS** | `evidence/t06-ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | **PASS**（BUILD SUCCESSFUL） | `evidence/t06-clean-assemble.log` |
| `codelinter` | **PASS**（No defects found） | `evidence/t06-codelinter.log` |
| Hypium host 编译（`hvigorw test`） | **COMPILED_ONLY**；执行 **BLOCKED** | `evidence/t06-hvigor-test-compile.log` |
| 设备侧骨架编译 | **PASS（仅编译）**；`onDeviceTest` **BLOCKED** | `evidence/t06-ohostest-assemble.log`、`evidence/t06-onDeviceTest-blocked.log` |
| HMAC/签名 | **未实现（T-07）** | 仅定义 `HmacSignerPort`；序列化使用公开向量签名 |
| 真实设备/性能/云 | **UNAVAILABLE** | 无设备、无签名、无真实 IoTDA |

**结论**：T-06 的 43 个产品文件、7 个 Node host 测试文件、7 个 Hypium host suite、1 个设备侧骨架已落地；本修订的构建、静态查、host 映射/负例均通过。组件状态应记为 `UNVERIFIED`，等待独立评审/CQG-T06，不得由本报告自行宣布 `STABLE`。

---

## 1. 实现范围

### 1.1 C-01 公共类型、常量与工具（21 文件）

```text
entry/src/main/ets/common/constants/
  ProtocolConstants.ets       # 协议常量 + ProtocolHeaders
  DeviceConstants.ets         # DeviceType/DeviceAction/词表/动作映射
  StorageConstants.ets        # 存储键/别名派生
entry/src/main/ets/common/types/
  NameValue.ets
  AppError.ets                # ErrorCategory/AppError/ErrorCatalog
  Result.ets                  # Result<T>
  GatewayResult.ets           # GatewayResultCode/Class/Classifier（独立命名空间）
  ProtocolDeviation.ets       # DeviationCode/ProtocolDeviation
  Ports.ets                   # Clock/Random/Id/Logger/Metrics/CancellationToken/HmacSigner
  JsonNode.ets                # JsonKind/NameValueNode/JsonNode
  HttpHeaders.ets
  SecureBytes.ets
entry/src/main/ets/common/utils/
  DateTimeUtil.ets            # UTC 紧凑时间/±120s/request_id
  BytesUtil.ets               # hex/UTF-8/zeroize
  Base64Url.ets               # 无 padding，严格解码
  Utf8.ets                    # 严格 UTF-8（拒绝 lone surrogate/overlong）
  IpAddressUtil.ets
  UuidUtil.ets
  JsonAtom.ets                # 24 vs 24.0、Unicode、控制字符
  JsonParser.ets              # 重复键/尾随/NaN/深度/长度/lone surrogate
  JsonCanonicalizer.ets       # 紧凑、可选字典序
```

关键实现点：

- `AppError` 只承载稳定 `code`、`category`、`retryable`、`i18nKey`、非敏感 `details`；`message` 仅诊断。
- `GatewayResultClass`/`GatewayResultClassifier` 与 App 命名空间物理分离；未知 `result_code` 一律 `known=false, success=false, retryable=false`。
- `DateTimeUtil.parseUtcCompact` 严格 `^[0-9]{8}T[0-9]{6}Z$`，手工校验闰年/月长，`formatUtcCompact` 秒级截断。
- `JsonParser` 拒绝重复键、尾随内容、`NaN/Infinity`、控制字符、lone surrogate、超限；保留插入顺序。
- `JsonAtom.encode(undefined)` 返回空串，字符串保留非 ASCII，数字用紧凑 JSON 表示。
- `SecureBytes` 支持 `withView`/`toHex`/`destroy`，销毁后抛 `SECRET_DESTROYED`。

### 1.2 C-02 领域模型共享面（9 文件）

```text
entry/src/main/ets/model/
  DeviceTypes.ets             # StateSource/AcMode/TransportProfile
  DeviceKey.ets               # 两级标识，globalId 仅派生
  DeviceState.ets             # DeviceSnapshot/Patch/State/RoomRef + 不变量
  GatewayRoute.ets            # GatewayAddress/TlsMaterial/GatewayRoute
  ControlModels.ets           # DeviceControlCommand/StateVerification/GatewayBoardState/ControlOutcome
  DiscoveryModels.ets         # DiscoverySecurity/DiscoverySnapshot
  ProvisioningModels.ets      # IdentityVersion/ProvisioningTlsMaterial/BleProvisioningIdentity/Result
  FamilyModels.ets            # Family/Member/Invitation/Room/Scene/SceneAction/CloudConfig
  CloudModels.ets             # ShadowShape/ShadowDeviceState/InventoryDeviceState/StateReportSnapshot
```

关键不变量：

- `DeviceKey` v1 ID 禁止 `:`；`globalId()` 不反向解析。
- `DeviceSnapshot`/`DeviceStatePatch` 由 `updatedAt` 派生 `stateEpochMs`；亮度/温度/湿度/目标温度/颜色/模式范围校验；`modeStandard`/`stateSourceKnown` 与词表一致。
- `DeviceState` 本地权威字段与 `snapshot` 网关权威字段分离；`roomId='' ⇔ isUnassigned=true`。
- `GatewayRoute`：P-HMAC ⇔ 无 TLS/pins/pinAlg；P-TLS-PIN ⇔ pins 1..4、64 位小写 hex、`sha256-spki-der`；P-BLOCKED 不可持久化；port 1..65535。
- `ControlOutcome` 禁止乐观成功：`ackAccepted` 必须 result 0 且存在 device/gateway 状态；`shouldApplyState` 必须 `ackAccepted`。
- `FamilyMember` GUEST 必须有 `expiresAt` 和非空 `allowedRoomIds`；`InvitationRecord` KEY_WRAP `maxUses=1` 且必须有 `memberId`；`usedCount<=maxUses`。
- `CloudConfig.accessTokenAlias` 必须是固定 Asset 别名；endpoint/shadowEndpoint 只接受 `https://host[:port]`。

### 1.3 C-03 协议 DTO/映射/校验（13 文件）

```text
entry/src/main/ets/service/protocol/
  ProtocolErrors.ets
  ProtocolDeviation.ets       # Sink/DeviationCounter/Noop
  dto/DiscoverDto.ets
  dto/ControlRequestDto.ets
  dto/ControlAckDto.ets
  dto/IdentityDto.ets
  dto/CloudDto.ets
  DiscoverMapper.ets
  ControlRequestSerializer.ets
  ControlAckMapper.ets
  IdentityParser.ets
  CloudCommandSerializer.ets
  StateReportMapper.ets
```

关键行为：

- `DiscoverMapper`：严格顶层信封；设备级失败跳过并 `isPartial=true`；别名 `isOnline→online`、`powerStatus→power`、`openStatus→open`、`targetTemperature→targetTemp` 仅在 canonical 缺失时读取并计数；canonical/alias 冲突优先 canonical 且记 `ALIAS_CONFLICT`；`success` 一律忽略并记 `SUCCESS_FIELD_IGNORED`；未知类型/状态源/非标准模式/小写入站 ID/小写 color/超长 ID 按 §18.8 记录偏差。
- `ControlRequestSerializer`：严格 10 字段顺序 `request_id, cmd_id, seq, target, payload, timestamp, nonce, alg, key_id, sign`；`payload` 仅 `{action, value?}`；紧凑无空白、无末尾换行；`SET_MODE` 出站 ≤15、其他字符串 ≤63；只校验/序列化已签名字段，**不计算 HMAC**。
- `ControlAckMapper`：严格 ACK schema；`request_id`/`seq` 严格相等；非 0 `result_code` 返回 `ackAccepted=false` 的 `ControlOutcome`（不抛）；0 且缺 `reported_state` → `ACK_PROTOCOL_VIOLATION`；device/gateway 形态互斥；目标不一致 → `ACK_STATE_MISMATCH`；动作字段比较输出 `MATCH/UNVERIFIED/MISMATCH`；`idempotent_replay` 不改变 `ackAccepted`；`success` 永不参与判定。
- `IdentityParser`：v2.0 严格 4 字段、`additionalProperties:false`；v2.1 只允许可选 `security.lan`，`tls=true` 要求 port/pins/pinAlg，`tls=false` 禁止携带三者；所有失败统一 `PROVISIONING_IDENTITY_INVALID`。
- `CloudCommandSerializer`：`service_id` + `command_name` + `paras` 固定顺序；`paras` 严格 10 字段；无 `object_device_id`；`Value` 为紧凑 JSON 原子文本（作为 JSON 字符串承载），并验证 canonical 形式。
- `StateReportMapper`：接受 `SERVICES`/`SHADOW`/`DEVICES` 三形态；严格 `event_time`、properties 值类型、未来 >5min fail-closed；内置固定路径 `Door_01_*`、`Light_01_*`、`Sensor_01_*`（含 `Room_01_Temperature/Humidity`）、`Presence_01_*`、`AC_01_*`、`Gateway_Online`；`DeviceInventoryJson` 保留但不解析（PB-02/T-14）。

---

## 2. 契约对照（DES-A/DES-B 章节）

| 契约 | 实现 | 覆盖测试 |
|---|---|---|
| DES-A §3.2 AppError/GatewayResult 双命名空间 | `common/types/AppError.ets`、`GatewayResult.ets` | `C01_AppError_*`、`C01_GatewayResultClassifier_*` |
| DES-A §3.3 时间/request_id/seq | `DateTimeUtil.ets` | `C01_DateTimeUtil_*` |
| DES-A §3.4 JSON 严格解析/canonical | `JsonParser/JsonCanonicalizer/JsonAtom` | `C01_JsonParser_*`、`C01_JsonCanonicalizer_*`、`C01_JsonAtom_*` |
| DES-A §4.1.1/§4.1.2 常量/头 | `ProtocolConstants.ets` | 构建/映射常量断言 |
| DES-A §4.1.3 设备词表/动作映射 | `DeviceConstants.ets` | `C02_RoomSceneCloudConfig_*` |
| DES-A §4.1.4 存储常量 | `StorageConstants.ets` | 模型/路由测试 |
| DES-A §4.1.5/§4.1.6/§4.1.7/§4.1.8/§4.1.9/§4.1.10 | 对应 utils/types | `Foundation.test.mjs` |
| DES-A §5.1.1..§5.1.7 模型 | `model/**` | `DomainModels.test.mjs` |
| DES-A §6.1.1 DTO | `service/protocol/dto/**` | 序列化/映射测试 |
| DES-A §6.1.2 discover 映射 | `DiscoverMapper.ets` | `C03_DiscoverMapper_*` |
| DES-A §6.1.3 控制请求序列化 | `ControlRequestSerializer.ets` | `C03_ControlRequestSerializer_*` |
| DES-A §6.1.4 ACK 判定链 | `ControlAckMapper.ets` | `C03_ControlAckMapper_*` |
| DES-A §6.1.5 identity | `IdentityParser.ets` | `C03_IdentityParser_*` |
| DES-A §6.1.6 偏差计数 | `ProtocolDeviation.ets` | `C03_DeviationCounter_*` |
| DES-A §18.1/§18.6/§18.7/§18.8/§18.9 | 映射/序列化/ACK 链 | 上述 C-03 用例 |
| DES-B §8.1.4 云命令信封 | `CloudCommandSerializer.ets` | `C03_CloudCommandSerializer_*` |
| DES-B §8.1.5/§8.3.3 影子/固定属性路径 | `StateReportMapper.ets`、`CloudModels.ets` | `C03_StateReportMapper_*` |
| DES-A §23 host 测试架构 | Node runner + Hypium suite 聚合 | `evidence/t06-host-node-tests.tap` |
| DES-A §27.4 DES-B 扩展边界 | 模型只增不改；未实现 C-15 行为 | 报告 §5 |

---

## 3. 测试与结果

### 3.1 Node host 测试（可执行路径）

命令：

```bash
entry/src/test/run-host-tests.sh
```

结果：`1..81`、`# pass 81`、`# fail 0`、退出码 0。证据：`entry/src/test/evidence/t06-host-node-tests.tap`。

新增 7 个测试文件（66 个新用例）：

| 文件 | 用例数 | 覆盖 |
|---|---:|---|
| `host/Foundation.test.mjs` | 16 | AppError/Result/时间窗/request_id/hex/base64url/UTF-8/JsonAtom/JsonParser/Canonicalizer/Headers/GatewayResult/IP/SecureBytes/UUID |
| `host/DomainModels.test.mjs` | 10 | DeviceKey/Snapshot/State/Patch/GatewayRoute/ControlOutcome/Discovery/Provisioning/Family/Room/Scene/CloudConfig |
| `host/ProtocolDiscover.test.mjs` | 9 | golden 4 设备、别名回退/冲突、未知类型/模式/状态源、超长 ID、设备跳过、顶层 fail-closed、偏差计数 |
| `host/ProtocolAck.test.mjs` | 14 | golden/replay、correlation、非 0/未知码、缺 `reported_state`、双形态、目标/字段不一致、gateway board、`success` 忽略、`error_code` on success、未知字段 |
| `host/ProtocolControl.test.mjs` | 5 | V-01 4 向量字段顺序、值类型、出站边界、UTF-8、无末尾换行 |
| `host/ProtocolIdentity.test.mjs` | 5 | v2.0 严格、多余字段、常量、v2.1 security/lan 合法/非法/pin/port、序列化 |
| `host/ProtocolCloud.test.mjs` | 7 | 云信封 10 字段/无 `object_device_id`、Value canonical、三种影子形态、固定属性、非法 envelope/未来时间 |

原有 15 个 T-05 用例保持通过。

### 3.2 Hypium host suite（仅编译）

新增 7 个 `.test.ets` suite，并由 `entry/src/test/List.test.ets` 聚合：

```text
entry/src/test/foundation/DateTimeUtil.test.ets
entry/src/test/foundation/JsonAtom.test.ets
entry/src/test/protocol/DiscoverMapper.test.ets
entry/src/test/protocol/ControlAckMapper.test.ets
entry/src/test/protocol/ControlRequestSerializer.test.ets
entry/src/test/protocol/IdentityParser.test.ets
entry/src/test/protocol/StateReportMapper.test.ets
```

`hvigorw test --no-daemon` 实测：`UnitTestArkTS` 编译成功（4.3s），随后 SDK Linux Previewer 输出 `Linux` 并等待，50s 超时（exit 124）。这是 T-05 已记录的 **BLOCKED（环境）**，不是断言失败；不得写成 PASS。证据：`evidence/t06-hvigor-test-compile.log`。

### 3.3 设备侧骨架（编译通过，执行 BLOCKED）

`entry/src/ohosTest/ets/test/foundation/FoundationDevice.test.ets` 包含 3 个设备侧用例（discover golden、ACK golden、state-report 固定路径），文件头与 suite 名标注 `BLOCKED_ON_DEVICE_RUNNER`。

- 由于 handoff 写范围只包含 `entry/src/ohosTest/ets/test/foundation/`，未持久修改 `entry/src/ohosTest/ets/test/List.test.ets`。
- 为验证编译，临时在 ohosTest `List.test.ets` 加一行 import 并在构建后**原样恢复**（最终 `git diff` 为空）；`assembleHap` exit 0、`BUILD SUCCESSFUL`。证据：`evidence/t06-ohostest-assemble.log`。
- `onDeviceTest` 实测 exit 255、`ErrorCode: 00507013`（need connect-key），`hdc list targets` 为 `[Empty]`；证据：`evidence/t06-onDeviceTest-blocked.log`。

### 3.4 向量/golden 对照

| ID | 对照 | 结果 |
|---|---|---|
| V-01 | 4 条控制 HMAC 向量：serializer 字段顺序 + 向量 `sign` + oracle canonical | PASS（不计算 HMAC，签名归 T-07） |
| V-04 | `discover-response.json`：4 设备、`online/power/open/targetTemp`、无 `success`、0 deviation | PASS |
| V-05 | `control-ack.json`：`request_id:seq`、`result_code=0`、`reported_state`、`MATCH` | PASS |
| V-06 | `control-ack-replay.json`：`idempotent_replay` 不重复应用 | PASS |
| V-11 | identity v2.0 合法/多余字段/常量；v2.1 合成 `security.lan` | PASS（v2.1 协商归 T-12） |

---

## 4. 命令与输出摘要

所有命令 cwd=`/home/quirkybrain/code/harmony-projects/YaoCore`，`DEVECO_SDK_HOME=/home/quirkybrain/harmonyos/command-line-tools/sdk`。

| 命令 | 退出码 | 输出摘要 | 证据 |
|---|---:|---|---|
| `ohpm install` | 0 | `install completed in 0s 63ms` | `evidence/t06-ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | 0 | `BUILD SUCCESSFUL in 6 s 835 ms`；35 tasks（34 executed, 1 up-to-date） | `evidence/t06-clean-assemble.log` |
| `codelinter -c code-linter.json5 -p default .` | 0 | `No defects found in your code.` | `evidence/t06-codelinter.log` |
| `entry/src/test/run-host-tests.sh` | 0 | `# tests 81 / # pass 81 / # fail 0` | `evidence/t06-host-node-tests.tap` |
| `hvigorw test --no-daemon` | 124（超时） | `UnitTestArkTS` 完成；Previewer `Linux` 挂起 | `evidence/t06-hvigor-test-compile.log` |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | 0 | `BUILD SUCCESSFUL in 6 s 161 ms`（临时聚合 import；已恢复） | `evidence/t06-ohostest-assemble.log` |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default onDeviceTest --no-daemon` | 255 | `ErrorCode: 00507013`（无设备） | `evidence/t06-onDeviceTest-blocked.log` |

---

## 5. 已知限制与偏离/未决项

### 5.1 明确延后（不是本任务缺陷）

1. **HMAC/签名/验签/nonce**：T-06 只定义 `HmacSignerPort`，不计算 HMAC。`ControlRequestSerializer` 只序列化已签名 DTO；V-01 的 `sign` 来自公开向量。T-07 必须逐条复算 canonical + HMAC。
2. **identity v2.1 协商**：`IdentityParser.parseV21` 按 ADR-002 §3.2 字段契约实现，但 Security1/proto-ver 协商、真实 BLE 传输归 T-12；`ble-enrollment-identity-request.schema.json` 当前只冻结 v2.0。
3. **DeviceInventoryJson / PB-02**：T-06 只保留 `DeviceInventoryJson` 属性，不解析、不参与完成判定；`DeviceInventoryParser` 与 `CloudCompletionEvaluator` 归 T-14。
4. **CloudService/ShadowReader**：云 HTTP、Token、轮询、完成判定归 T-14；本任务只做信封序列化与影子/状态报告映射。
5. **真实设备/性能/云**：无设备、无签名、无真实 IoTDA；`onDeviceTest`、TLS pin、BLE、UI、NFR 性能均为 `BLOCKED`/`UNAVAILABLE`。

### 5.2 实现决策/契约说明

1. **端口物理位置**：DES-A §2.1 把 `Clock/Random/Id/Logger/Metrics/CancellationToken` 放在 `contracts/**`；本 handoff 写范围不含 `contracts/`，故放在 `common/types/Ports.ets`（纯接口、无平台 import）。T-07/端口扩展任务可迁移到 `contracts/**`，不改变签名。
2. **云映射物理位置**：DES-B 将 `CloudCommandSerializer`/`ShadowDtoAdapter` 放在 `service/cloud/**`；本 handoff 写范围为 `service/protocol/**`，故以 C-03 线格式映射落在 `service/protocol/`。T-14 可迁移/包装为 C-15 实现。
3. **未知 `result_code` 的 deviation**：DES-A §3.2.4 要求记录 `protocolDeviation`，但 §4.1.10 的 `DeviationCode` 没有对应值。T-06 不 invent 新码，暴露 `GatewayResultClass.known=false`；建议上游在 `DeviationCode` 增补 `UNKNOWN_GATEWAY_RESULT_CODE` 或明确不记录。
4. **discover 顶层未知字段**：实现返回 `DISCOVERY_INVALID_RESPONSE`（§6.2 允许 `DISCOVERY_INVALID_RESPONSE`/`PROTOCOL_UNKNOWN_FIELD` 二者之一）；设备级未知字段返回 `PROTOCOL_UNKNOWN_FIELD` 并跳过设备。
5. **`isPartial` 语义**：对“设备被跳过、`roomName` 缺失、canonical 缺失改用别名、未知 `deviceType`”置 `true`；对“未知 `stateSource`、非标准 `mode`、color 归一化、超长但合法 ID”不置 `true`（设备完整，仅诊断）。该选择比“任何偏差都 partial”更精确，但需 C-10/T-19 复核。
6. **gateway ACK 的 `shouldApplyState`**：`BOARD_LED_*` 的 `reported_state` 映射为 `gatewayBoardState`（`reportedState` 为 undefined）；实现仍将 `shouldApplyState=true`（`reported_state` 存在且 `ackAccepted`）。建议 C-10 明确消费 `gatewayBoardState`。
7. **`Base64Url.decode` 严格尾位**：拒绝非零 trailing bits（如 `ab`），比“任意 base64url”更严格；与本仓库自生成邀请容器一致，若未来需兼容第三方非规范编码需评审。
8. **`DeviceStateValidation` 方法名**：ArkTS 禁止静态方法名 `name`（与 `Function.name` 冲突），内部方法改为 `text`；公开契约不受影响。
9. **测试临时 import**：为编译设备侧骨架，临时修改 ohosTest `List.test.ets` 后恢复；最终提交不含该修改，`git diff` 已确认。

---

## 6. Traceability

| 需求/约束 | 组件 | 测试/证据 |
|---|---|---|
| FR-DEV-001/SC-13 ACK 判定链 | C-03/C-17 | `C03_ControlAckMapper_*`（14） |
| FR-DEV-004/005 模式/状态源 | C-02/C-03 | `C03_DiscoverMapper_*`、`C02_*` |
| FR-GW-003 pin/TLS 模型 | C-02 | `C02_GatewayRoute_*` |
| FR-ROOM-002/006 DP-01 | C-02 | `C02_DeviceKey_*`、`C02_DeviceState_*` |
| FR-FAM-002/003/004 | C-02 | `C02_FamilyModels_*` |
| FR-SCN-001 | C-02 | `C02_RoomSceneCloudConfig_*` |
| FR-SET-003 云配置 | C-02/C-03 | `C02_RoomSceneCloudConfig_*`、`C03_CloudCommandSerializer_*` |
| DES-A §18.1 canonical 字段集 | C-03 | `C03_ControlRequestSerializer_allPublicVectorsMatchSchemaOrder` |
| DES-A §18.7 判定顺序 | C-03 | `C03_ControlAckMapper_*` |
| DES-A §18.8 别名/偏差 | C-03 | `C03_DiscoverMapper_*`、`C03_DeviationCounter_*` |
| PR-07 identity fail-closed | C-03 | `C03_IdentityParser_*` |
| PR-09 云 10 字段/无 object_device_id | C-03 | `C03_CloudCommandSerializer_*` |
| D-014 固定属性路径 | C-03 | `C03_StateReportMapper_*` |
| PC PL-04/PL-05 无 any/明确类型 | 全部 | `codelinter` PASS；无平台 import |
| D-019 host 可执行 | C-01..C-03 | Node 81/81 |

---

## 7. 风险

| ID | 风险 | 影响 | 处置 |
|---|---|---|---|
| T06-R01 | Hypium host 执行仍被 Linux Previewer 阻塞 | 无 Hypium 运行时 PASS | Node runner 为可执行路径；设备/CI 复跑；不得写 PASS |
| T06-R02 | 无设备/签名 | 设备侧骨架、onDeviceTest、TLS/BLE 无运行时证据 | 标 `BLOCKED`；T-12/T-19 在设备环境执行 |
| T06-R03 | HMAC 未实现 | 控制请求只能在 T-07 后真实发送 | T-07 必须用 V-01 逐条复算 canonical+sign |
| T06-R04 | 未知 result_code 无 deviation 码 | 与 §3.2.4 文字不完全一致 | 已记录 §5.2-3；请上游裁定 |
| T06-R05 | 云完成判定/inventory 未实现 | 云路径仍不可验收 | T-14 / PB-02；本任务不声明云 PASS |
| T06-R06 | `isPartial`/gateway `shouldApplyState` 语义选择 | C-10 合并/应用行为可能需调整 | 独立评审 + C-10/T-19 复核 |
| T06-R07 | 模型数组字段为 `ReadonlyArray`（编译期） | 调用方可运行时改写数组 | 后续组件按约定不修改；如需强不可变可复制数组 |

---

## 8. 下一步

1. 独立 `quality-reviewer` 对 43 个产品文件做 Code Review，重点：C-03 判定链、fail-closed 边界、错误命名空间、秘密不日志。
2. T-07 在 `HmacSignerPort`/C-05 上实现 canonical+HMAC+响应验签，逐条跑 V-01..V-03；不得复用本任务的向量签名作为实现。
3. C-10/T-14 消费 `DiscoverySnapshot`/`ControlOutcome`/`StateReportSnapshot`，复核 §5.2-5/6 的语义选择。
4. T-19 在设备/CI 环境复跑 `hvigorw test` 与 `onDeviceTest`；当前证据保持 `COMPILED_ONLY`/`BLOCKED`。
5. 上游裁定未知 `result_code` 的 `DeviationCode`（§5.2-3）。
