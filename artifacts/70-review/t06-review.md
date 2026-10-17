# T-06 独立代码评审：C-01..C-03 基础模型与协议映射

- **Artifact ID**: REV-T06-001
- **Producer**: agent:quality-reviewer
- **Type**: Independent Code Review / CQG-T06 Evidence
- **Status**: CHANGES_REQUIRED（独立评审完成；不授予 STABLE 或 Stage/用户验收）
- **Date**: 2026-10-17
- **Task**: `wp-013-review-t06`（task 分支 `task/wp-012-foundation`，父分支 `feat/yaocore-app`）
- **Reviewed revision**: `4d361bdba790da686839b30ce1feffec2215b0f7`（parent `5901cd7081dc5a9b12f5d4f51dbed71ef7bb5ae8`）
- **Review scope**: 67 files changed（43 个产品文件 + 测试/证据/实现报告）；详见 §1
- **Review snapshot**: `refs/swe/snapshots/20261017T075228Z-wp-013-review-t06-cc17f15b`（`5811fad`）
- **Independence**: **本报告由未参与 T-06 实现的质量评审者（agent:quality-reviewer）编写；T-06 作者为 agent:implementation-engineer。作者之外的独立评审，作者不能批准本报告或自行修复后直接关闭本评审。**

> 结论先行：构建、lint、Node host 测试与主要 golden/向量覆盖良好；未发现 Critical/High 问题，也未发现伪造 HMAC、秘密泄漏或乐观成功的直接路径。但 ACK 严格 schema 的错误码、gateway ACK 的 `shouldApplyState`、`SET_MODE` 非标准模式的 `stateVerification` 三处与冻结契约不一致（Medium），且有若干 Low 级严格性/文档问题。故不授予 PASS，判 **CHANGES_REQUIRED**。

---

## 1. 评审范围、输入与排除

### 1.1 范围

| 类别 | 路径 | 文件数 |
|---|---|---:|
| C-01 公共类型/常量/工具 | `entry/src/main/ets/common/**` | 21 |
| C-02 领域模型共享面 | `entry/src/main/ets/model/**` | 9 |
| C-03 协议 DTO/映射 | `entry/src/main/ets/service/protocol/**` | 13 |
| Node host 测试 | `entry/src/test/host/*.test.mjs` | 7 |
| Hypium host suite | `entry/src/test/foundation/**`、`entry/src/test/protocol/**` | 7 |
| 设备侧骨架 | `entry/src/ohosTest/ets/test/foundation/FoundationDevice.test.ets` | 1 |
| 证据/聚合/报告 | `entry/src/test/evidence/t06-*`、`entry/src/test/List.test.ets`、`artifacts/50-implementation/t06-foundation.md` | 9 |
| **合计** | | **67** |

`git show --name-only 4d361bd` 逐一核对：上述文件均在 handoff 的 `review_targets` 内；无 `contracts/**`、`repository/**`、`service/cloud/**` 或产品 UI 文件被越界修改。工作树在评审开始时为 clean。

### 1.2 权威输入与 pin 校验

| 输入 | 核对结果 |
|---|---|
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | SHA-256 `5599e693…bfe1c1`，与 handoff 一致 |
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | SHA-256 `0b417932…80ef1c`，与 handoff 一致 |
| `artifacts/20-architecture/contract-baseline.md` | SHA-256 `6673a990…fadee89`，与 handoff 一致 |
| `artifacts/20-architecture/project-constraints.md` | SHA-256 `28304621…23da9528`，与 handoff 一致 |
| `artifacts/60-testing/test-plan.md` | SHA-256 `33485cc3…56055fae`，与 handoff 一致 |
| `artifacts/50-implementation/t06-foundation.md` | SHA-256 `0bbf48dd…4f350f78`，与 handoff 一致 |
| `config/git-policy.json` | SHA-256 `3b8ddffd…9241a014`，与 handoff 一致 |

### 1.3 明确排除

以下不属于 T-06 的评审结论，且本报告不把它们写成 PASS：

- **HMAC/签名/验签/nonce 生成**：T-07（C-05）职责；T-06 只定义 `HmacSignerPort`、序列化已签名 DTO，未计算任何 HMAC。
- **存储/仓储/端口迁移**：T-08/T-09 及后续任务；`common/types/Ports.ets` 的物理位置为已记录偏差（R-13）。
- **真实 BLE/TLS/设备/云**：无设备、无签名、无真实 IoTDA；`onDeviceTest`、Hypium 运行时、TLS pin、BLE、云完成判定均为 `BLOCKED`/`UNAVAILABLE`。
- **云完成判定/DeviceInventoryJson 解析**：T-14（C-15）/PB-02；T-06 只保留属性，不参与完成判定。

---

## 2. 评审方法

1. **Diff first**：先读 `5901cd7..4d361bd` 的 67 文件变更，再读周边实现与调用路径。
2. **契约对照**：逐条对照 DES-A §3/§4/§5/§6/§18/§27.4、DES-B §8/§23、CB §2/§4/§6/§7、PC 的 PL/PR/SC/DP 约束、TEST-001 §4/§5/§10。
3. **边界追踪**：重点追踪 discover 信封 → 设备别名/偏差；control ACK → 判定链；identity → fail-closed；cloud command → `paras` 10 字段；state report → 固定属性路径；以及 App/Gateway 错误命名空间。
4. **独立复跑**（只读命令；未修改被测文件）：
   - `entry/src/test/run-host-tests.sh` → `1..81`、`# pass 81`、`# fail 0`、exit 0、约 401.6 ms。
   - `codelinter -c code-linter.json5 -p default .` → `No defects found in your code.`、exit 0。
   - 针对 ACK 严格性、gateway ACK、Base64Url、ErrorCatalog、serializer、state report 的定向 Node 探针（见 §6 证据）。
5. **构建/Hypium/设备**：核对同 revision 的证据日志（`t06-clean-assemble.log`、`t06-hvigor-test-compile.log`、`t06-ohostest-assemble.log`、`t06-onDeviceTest-blocked.log`）。为避免越出只读边界，未重跑 `hvigorw` 构建（其会写入被忽略的 build 输出）；日志中的命令、退出码、任务数与提交 revision 一致。
6. **过程合规**：`git show --stat`、`git show --name-only`、`git status --short --ignored`、secret 扫描、构建产物扫描、scope 检查。

> 评审者未修改任何被测文件；唯一写入是本报告。`swe_guard` snapshot 已覆盖评审目标，`finish` 会再次校验字节一致性。

---

## 3. Findings

> 严重度定义：**Critical** = 可导致错误成功/密钥泄漏/不可恢复数据损坏；**High** = 明确安全或核心协议破坏；**Medium** = 冻结契约不一致、可影响下游行为但有明确修复路径；**Low** = 严格性、可维护性、文档或防御性缺口。

| ID | 严重度 | 位置（文件:行） | 问题 | 违反的契约/约束 | 建议修复方向 |
|---|---|---|---|---|---|
| **R-01** | **Medium** | `entry/src/main/ets/service/protocol/ControlAckMapper.ets:83, 186, 291, 425-432`；`entry/src/test/host/ProtocolAck.test.mjs:231` | ACK 根对象与 `reported_state` 的未知字段由 `rejectUnknownFields` 抛 `PROTOCOL_UNKNOWN_FIELD`。按 §18.7 第 6 步，ACK 严格 schema 失败应为 `ACK_PROTOCOL_VIOLATION`（`ACK_CORRELATION_MISMATCH` 仅用于 correlation）。错误码类别从 GATEWAY 变成 PROTOCOL，可能使 C-17/C-10 的错误分类、i18n 与诊断路径偏离契约。测试把该错误码固化为期望值。 | DES-A §6.1.4 第 1 步、§6.3（control ACK required/unknown 严格）、§18.7 第 6 步；SC-13 的 ACK 判定链 | 为 ACK 的 `rejectUnknownFields` 传入 `ACK_PROTOCOL_VIOLATION`（根对象、deviceState、gatewayState 三处一致）；更新 `ProtocolAck.test.mjs` 的期望并补 deviceState/gatewayState 未知字段负例。 |
| **R-02** | **Medium** | `entry/src/main/ets/service/protocol/ControlAckMapper.ets:159-167`；`entry/src/main/ets/model/ControlModels.ets:133-139`；`entry/src/test/host/ProtocolAck.test.mjs:188-204` | gatewayState ACK 中 `reportedState` 为 `undefined`、`gatewayBoardState` 有值，但 `shouldApplyState` 仍被设为 `true`（仅当 replay 且 alreadyApplied 时 false）。DES-A §5.1.4 明确定义 `shouldApplyState = ackAccepted && reportedState !== undefined && !(idempotentReplay && alreadyApplied)`；gatewayState 不应触发设备状态应用。报告 §5.2-6 已记录此选择，但未获得契约所有者的接受。 | DES-A §5.1.4 `ControlOutcome.shouldApplyState` 定义、§6.1.4 第 9 步 | 将 `shouldApplyState` 设为 `reportedState !== undefined && ...`；若产品确需应用 `gatewayBoardState`，新增独立标志或走 Change Impact 修改冻结定义，并由 C-10/T-19 复核；补 gateway ACK 的 `shouldApplyState=false` 测试。 |
| **R-03** | **Medium** | `entry/src/main/ets/service/protocol/ControlAckMapper.ets:355-362`；`entry/src/test/host/ProtocolAck.test.mjs:244-259` | `SET_MODE` 的 `mode` 存在但不在 7 值词表时直接返回 `UNVERIFIED`，即使其与请求值不同。DES-A §5.1.4/§6.1.4 第 8 步规定：字段缺失 → `UNVERIFIED`；存在且不等 → `MISMATCH`；相等 → `MATCH`。当前实现会把“网关返回非标准模式且未达到请求模式”降级为“无法验证”，可能抑制 VM 的 REVERT/提示路径。测试把该行为固化为期望。 | DES-A §5.1.4 `stateVerification` 定义、§6.1.4 第 8 步；CB §6.3 的 7 值词表 | 按原始 `mode` 值与请求比较：缺失 → UNVERIFIED；存在且不同 → MISMATCH；相同 → MATCH。DES-B §8.1.6 对云路径的“非标准值 → UNVERIFIED”是另一条规则；若要在 LAN 复用，必须走 Change Impact 并明确记录。 |
| **R-04** | **Low** | `entry/src/main/ets/service/protocol/ControlAckMapper.ets:121-128` | `result_code != 0` 时在解析 `reported_state` 之前直接返回，因此非零 ACK 中畸形/双形态/未知字段的 `reported_state` 不会被 schema 校验。定向探针确认：`result_code=1007` 且 `reported_state` 同时含 `deviceId`/`gatewayId` 被接受为 `ackAccepted=false` 的正常错误结果。该路径不产生成功，但违反“先严格 schema、后分类”的顺序。 | DES-A §6.1.4 第 1 步、§18.7 第 6 步；`local-control-ack.schema.json` 的 `oneOf`/`additionalProperties:false` | 对非零 ACK 中“存在”的 `reported_state` 仍执行 oneOf/字段/未知字段校验；失败抛 `ACK_PROTOCOL_VIOLATION`；补负例。若有意容忍，需在 §6.1.4 记录并获接受。 |
| **R-05** | **Low** | `entry/src/main/ets/common/utils/Base64Url.ets:36-39`；`entry/src/test/host/Foundation.test.mjs:167` | `Base64Url.decode('')` 返回零长度数组；DES-A §4.2 明确要求空串抛 `SECRET_ENCODING_INVALID`（邀请上下文由 C-13 包装成 `INVITE_INVALID`）。测试把空串接受固化为期望。 | DES-A §4.2（Base64Url 错误语义）、§4.3 第 6 条 | 空串抛 `SECRET_ENCODING_INVALID`；更新测试；保留 `encode(empty) === ''` 的合法行为。 |
| **R-06** | **Low** | `entry/src/main/ets/common/types/AppError.ets:94-96, 134-139` | `INVITE_VERSION_UNSUPPORTED` 走通用 `INVITE_*` 分支，得到 `errors.app.invite_version_unsupported`；DES-A §3.2.3 表指定 `errors.app.invite_invalid`。C-14/T-10 的键 parity/fallback 会显示错误文案或出现缺键。 | DES-A §3.2.3（唯一 App 错误码表）、I18N-05/C-14 键映射 | 在 `i18nKeyOf` 增加 `INVITE_VERSION_UNSUPPORTED` 特例；补一个覆盖该行的 ErrorCatalog 单测。 |
| **R-07** | **Low** | `entry/src/main/ets/service/protocol/ControlRequestSerializer.ets:102-139` | 序列化器校验了字符串长度/数值范围，但没有按 `DeviceConstants.actionToValueKind(action)` 校验 value 类型；例如 `SET_BRIGHTNESS` + `"oops"`、`PING` + `true`、`BOARD_LED_ON` + `42` 均可通过并进入签名。DES-A §6.1.3 要求“序列化前必须完成结构校验”，§4.1.3 已提供动作→值类型映射。**注意**：7 值 `SET_MODE` 词表不应在本序列化器强制，因为公开 V-01 向量使用 `"制冷"` 作为编码夹具；该词表应由 C-11/C-16 在构造命令时强制。 | DES-A §6.1.3、§4.1.3；CB §6.3（出站 7 值，但由命令层负责） | 增加 action→value kind 校验（不改变向量兼容性）；在报告中明确“7 值词的归属是 C-11/C-16”，并补类型不匹配负例。 |
| **R-08** | **Low** | `entry/src/main/ets/service/protocol/ControlRequestSerializer.ets:88-90`；`entry/src/main/ets/service/protocol/CloudCommandSerializer.ets:95-97` | 控制/云 nonce 只校验 schema 的 `^[A-Za-z0-9_-]{8,64}$`，未校验 App 生成契约要求的 16B → 32 位小写 hex（`HEX_LOWER_32`）。T-07/C-17 应生成正确 nonce，但序列化器是签名前最后一道结构门；当前可签名短/含大写或 `-` 的 nonce。 | DES-A §3.3、§18.5；CB §2.5 | 出站 DTO 强制 `HEX_LOWER_32`（或至少在 T-07 的签名入口强制），并补负例；若保留 schema 宽容度，记录 generator ownership。 |
| **R-09** | **Low** | `entry/src/main/ets/service/protocol/StateReportMapper.ets:71-94, 301-321` | SERVICES 形态未强制 `state-report.schema.json` 的 7 个 required 固定属性，也未拒绝未知属性/顶层未知字段；定向探针确认 `{services:[{service_id:'SmartHomeService',properties:{Foo:1},event_time:...}]}` 被接受为 0 设备的快照。该路径不产生成功判定（T-14 才做完成判定），但“spec 严格解析”的声明不完整。 | `state-report.schema.json` required/additionalProperties；PR-01；DES-B §8.1.5/§8.3.3 | 明确 T-06 的容忍边界：对 SERVICES 形态校验 required/additionalProperties，或由 T-14 接管完整 strict adapter 并在 T-06 报告/测试中说明“partial report 容忍”。补缺属性/未知属性负例。 |
| **R-10** | **Low** | `entry/src/main/ets/service/protocol/DiscoverMapper.ets:318-320`；`entry/src/test/host/ProtocolDiscover.test.mjs:118` | 别名回退（`isOnline/powerStatus/openStatus/targetTemperature`）会把整个 `DiscoverySnapshot.isPartial` 置 true。DES-A §5.1.5 的注释是“有设备被跳过/字段缺失”；别名设备本身完整，canonical 缺失可解释为“字段缺失”，因此该选择有歧义。它会让使用旧别名的网关永远处于 partial，C-10 无法据此标记“网关已移除”的设备。报告 §5.2-5 已记录但需 C-10/T-19 接受。 | DES-A §5.1.5 `isPartial` 注释、§6.3 别名行、§18.8 | 由 C-10/T-19 明确接受“alias ⇒ partial”，或拆分为 `aliasUsed` 诊断位而不置 partial；补 C-10 合并测试。 |
| **R-11** | **Low** | `entry/src/main/ets/service/protocol/DiscoverMapper.ets:173-177` | 未知 deviceType 的 `ProtocolDeviation.detail` 直接放入原始 `deviceTypeRaw`。§4.1.10/§18.8 要求 `detail` 只允许字段名/原因码，不得是完整报文/设备名；该值由入站控制，可能很长并污染诊断/日志。不是秘密泄漏。 | DES-A §4.1.10（detail 约束）、§18.8 | 将 detail 改为稳定原因码（如 `unrecognized_type`）；原始值如确需诊断，做长度上限并在非日志路径使用。 |
| **R-12** | **Low** | `entry/src/test/README.md:46-54` | README 仍写“当前结果 15/15（`evidence/host-node-tests.tap`）”；当前 revision 是 81/81，证据为 `t06-host-node-tests.tap`。T-19/CQG 复核时会产生错误预期。 | TEST-001 §5/§10 证据纪律；项目文档一致性 | 更新为 81/81 + T-06 证据，或明确区分“T-05 基线 15/15”与“T-06 revision 81/81”。 |
| **R-13** | **Low** | `entry/src/main/ets/common/types/Ports.ets`；`entry/src/main/ets/service/protocol/CloudCommandSerializer.ets`、`StateReportMapper.ets`；报告 §5.2-1/2 | 端口放在 `common/types/` 而非 DES-A §2.1/§3.7 的 `contracts/**`；云映射放在 `service/protocol/` 而非 DES-B §8 的 `service/cloud/**`。原因是 handoff 写范围不含 contracts/cloud；无依赖方向错误，但与冻结目录布局不一致，后续任务可能 import 错位置。 | DES-A §2.1/§3.7、DES-B §8（C-15 路径） | 在 T-07/T-14 迁移到 `contracts/**`/`service/cloud/**` 并保持签名，或在 CQG/Gate 记录明确例外；不要复制两套实现。 |

### 3.1 非阻塞观察（不作为独立 finding）

1. **`GatewayResultClassifier.classify(resultCode, errorCode)` 未使用 `errorCode`**：这与 §3.2.4 的 `GatewayResultClass.i18nKey='errors.gateway.<stableName>'` 契约一致；`error_code` 的细分 key（如 `errors.gateway.unknown_device`）应由 C-14 的 `I18nKeys.gatewayKey` 处理。C-14 必须实现该映射，否则 1006 的细分文案会退化为 `unsupported_command`。
2. **双级 ID 的入站宽度**：`DiscoverMapper`/`DeviceSnapshot` 接受 64..128 字符的入站 `deviceId` 并记录 `OVERSIZE_INBOUND_IDENTIFIER`，但 `DeviceKey` 构造器上限为 63。C-10 必须把超长 ID 作为“展示/关联”记录处理，不能直接构造 `DeviceKey` 或持久化为主键；需在 C-10 设计/测试中明确。
3. **数组只读是编译期**：`DeviceSnapshot.devices`/`GatewayRoute.pins`/`GatewayRoute.gatewayIds` 等为 `ReadonlyArray`，运行时仍可被调用方改写。报告 T06-R07 已记录；后续组件按约定禁止改写，必要时在边界复制。
4. **未知 `result_code` 的 deviation 缺口**：§18.9 要求记录 `protocolDeviation`，但 `DeviationCode` 没有对应值；实现正确 fail-closed（`known=false/success=false/retryable=false`）但不记录偏差。报告 §5.2-3 已请求上游裁定；建议在 C-05/C-14 决定新增 `UNKNOWN_GATEWAY_RESULT_CODE` 或明确不记录。
5. **`ackAccepted` 与 `stateVerification=UNVERIFIED` 的组合**：当 `reported_state` 缺少动作字段时，`ackAccepted=true` 但 `stateVerification=UNVERIFIED`（定向探针确认）。这是 schema 允许的，但 C-21/C-10 必须只把 `MATCH` 视为“确认到位”，不得因 `ackAccepted` 单独显示 COMMITTED（SC-13/SC-14）。
6. **`success` 字段的层级**：ACK 顶层与 reported_state 接受 `success` 并记偏差（设计 §6.3 明确“忽略并偏差”）；discover 顶层 `success` 会被 `DISCOVERY_INVALID_RESPONSE` 拒绝。若存量网关在 discover 顶层携带 `success`，需确认是否应像设备级一样忽略；当前实现按严格信封 fail-closed，建议在 C-17 联调时确认。

---

## 4. CQG-T06 检查项对照

> CQG-T06 的最小必填证据（TEST-001 §4.3）：`mapDiscoverResponse`/`mapControlAck` golden、identity fail-closed、构建/lint。

| 检查项 | 结果 | 证据/说明 |
|---|---|---|
| 构建 | **PASS** | `hvigorw clean assembleHap --no-daemon` → exit 0，`BUILD SUCCESSFUL in 6 s 835 ms`，35 tasks（34 executed, 1 up-to-date）；unsigned HAP warning。证据 `t06-clean-assemble.log`。未重跑以保持只读边界。 |
| lint | **PASS** | 复跑 `codelinter -c code-linter.json5 -p default .` → `No defects found in your code.`，exit 0；与 `t06-codelinter.log` 一致。 |
| Node host 测试 | **PASS 81/81** | 复跑 `entry/src/test/run-host-tests.sh` → `1..81`、`# pass 81`、`# fail 0`、exit 0、约 401.6 ms；与 `t06-host-node-tests.tap` 一致。 |
| 契约：discover golden/别名/负例 | **PASS（覆盖范围内）** | V-04 4 设备、别名回退/冲突、unknown type/stateSource/mode、oversize ID、device skip、顶层 fail-closed；`ProtocolDiscover.test.mjs` 9 例。isPartial 语义见 R-10。 |
| 契约：ACK golden/replay/判定链 | **PARTIAL/FAIL** | golden/replay、correlation、非零码、缺 `reported_state`、目标不一致、动作字段 MATCH/MISMATCH/UNVERIFIED 均有覆盖；但 R-01（错误码）、R-02（gateway shouldApplyState）、R-03（非标准 mode）、R-04（非零 ACK 严格性）与冻结契约不一致。 |
| 契约：control 向量/序列化 | **PASS（覆盖范围内）** | V-01 4 条向量字段顺序、sign 复用、canonical oracle、UTF-8/无尾换行均通过；HMAC 本身明确归 T-07。R-07/R-08 为 Low 级防御性缺口。 |
| 契约：identity fail-closed | **PASS** | v2.0 严格 4 字段、多余字段/常量/ID 边界；v2.1 `security.lan` 的 tls/port/pins/pinAlg 正负例；统一 `PROVISIONING_IDENTITY_INVALID`。 |
| 契约：cloud envelope/state report | **PASS（覆盖范围内）** | `paras` 10 字段、无 `object_device_id`、`Value` canonical、三种 shape、固定路径、未来时间 fail-closed；R-09 为严格性缺口，T-14 接管完成判定。 |
| Hypium host | **COMPILED_ONLY / BLOCKED** | `UnitTestArkTS` 编译成功（4.288 s），随后 `> hvigor Linux` 挂起；`hvigorw test` 退出 124。不得写成 PASS。证据 `t06-hvigor-test-compile.log`。 |
| 设备侧 | **BLOCKED** | 骨架编译通过；`onDeviceTest` exit 255、`ErrorCode: 00507013`（need connect-key），无 `hdc` target。证据 `t06-onDeviceTest-blocked.log`。 |
| i18n 适用项 | **NOT_APPLICABLE（本任务）** | 无 UI/locale 资源变更；无用户可见硬编码文案；无重复 codebase。`ErrorCatalog` 键映射已审计（R-06）；CHK-01..09 留给 C-14/T-10。 |
| 分层/依赖方向 | **PASS** | 未发现 `@ohos.*`/UI import 进入 `common/model/service/protocol`；`common → model → service/protocol` 方向正确；无 `any`（grep + codelinter）。R-13 是目录落点偏差，不是依赖错误。 |
| 安全纪律 | **PASS（带残余）** | 未发现伪造 HMAC/签名、真实 secret/证书/Token、秘密日志；identity/ACK/未知结果码 fail-closed；无乐观成功路径。R-01/R-04 的错误码/严格性需修复。 |
| 评审 | **本报告** | `Producer: agent:quality-reviewer`；作者之外的独立评审；只读被测文件。 |
| 追溯 | **PARTIAL** | 报告 §2/§6 的 FR/SC/测试映射可核对；81 个 Node 用例可复现。R-02/R-03 的测试断言了与契约不一致的行为，修复时需同步改测试。 |
| **CQG-T06 总体** | **NOT PASS / CHANGES_REQUIRED** | 构建/lint/host/golden 通过，但 Medium 契约偏差未解决；组件应保持 `UNVERIFIED`，不得进入 `STABLE`。 |

---

## 5. Verdict

**CHANGES_REQUIRED**

理由：

1. **无 Critical/High**：未发现可伪造成功、密钥泄漏、绕过 HMAC/验签、乐观成功或秘密入库的直接路径；HMAC/签名边界正确留给 T-07。
2. **三处 Medium 与冻结契约不一致**：R-01（ACK schema 错误码）、R-02（gateway ACK `shouldApplyState`）、R-03（非标准 mode 的 `stateVerification`）。三者都不是“风格偏好”，而是 §6.1.4/§18.7/§5.1.4 的实现契约；其中 R-02 与 R-03 的现有测试还把偏差行为写成期望，不能作为通过证据。
3. **R-04 及 Low 级严格性/文档问题**：应在同一次修复中处理，或在 CQG/Gate 记录明确的接受理由。
4. **构建/lint/host 证据充分**：T-06 的工程基线可靠，81/81 可复现，设备/Hypium 的 `BLOCKED`/`COMPILED_ONLY` 标注诚实；这些不构成 PASS 的充分条件，因为契约符合项未过。

> 本评审不授予 STABLE、Stage Gate 或用户验收。修复后必须由**作者之外**的评审者重新评审；作者不能自行批准自己的修复。

---

## 6. 关键证据

### 6.1 复跑命令

```text
$ entry/src/test/run-host-tests.sh
1..81
# tests 81
# pass 81
# fail 0
exit 0

$ codelinter -c code-linter.json5 -p default .
No defects found in your code.
exit 0
```

### 6.2 定向探针（只读，加载被测 `.ets` 模块）

```text
ACK nonzero malformed reported_state: ACCEPTED false 1007
ACK unknown field code: PROTOCOL_UNKNOWN_FIELD
gateway ACK reportedState: undefined shouldApplyState: true
mode TURBO vs COOL => UNVERIFIED ackAccepted true
missing brightness => UNVERIFIED ackAccepted true shouldApply true
Base64Url.decode("") length: 0
SET_BRIGHTNESS string serialized: {"request_id":"...","payload":{"action":"SET_BRIGHTNESS","value":"oops"},...}
INVITE_VERSION_UNSUPPORTED i18n: errors.app.invite_version_unsupported
missing required props accepted; devices: 0 props: [ 'Foo' ]
```

### 6.3 过程/仓库检查

- `git show --stat 4d361bd`：67 files changed；43 个产品文件 + 23 个测试/证据 + 1 个实现报告。
- scope check：无文件落在 `review_targets` 之外；无 `build/`、`.hvigor`、HAP/HAR、证书、私钥、Token 或真实凭据入库。
- `git status --short`：评审开始时 clean；本次评审仅新增本报告。
- 设备/Hypium：`t06-onDeviceTest-blocked.log` 的 `ErrorCode: 00507013`；`t06-hvigor-test-compile.log` 的 `UnitTestArkTS` 完成 + `> hvigor Linux`；未写成 PASS。
- 实现报告的证据与命令输出一致；`t06-host-node-tests.tap` 的 81/81 与复跑一致。

---

## 7. 残余风险与后续跟踪

| ID | 风险 | 影响 | 处置 |
|---|---|---|---|
| T06-RISK-01 | HMAC/签名/nonce 未实现 | 控制请求不能在 T-07 前真实发送 | T-07 逐条复算 V-01 canonical + HMAC；不得复用向量签名作为实现 |
| T06-RISK-02 | Hypium/设备运行时阻塞 | 无设备侧运行时 PASS | T-19 在设备/CI 复跑；保持 `COMPILED_ONLY`/`BLOCKED` |
| T06-RISK-03 | `isPartial`/gateway `shouldApplyState` 语义 | C-10 合并/应用行为可能偏离设计 | 修复 R-02/R-10 或由 C-10/T-19 书面接受；补集成测试 |
| T06-RISK-04 | 未知 `result_code` 无 deviation 码 | 与 §18.9 文字不完全一致 | 上游裁定新增 `UNKNOWN_GATEWAY_RESULT_CODE` 或明确不记录 |
| T06-RISK-05 | `DeviceInventoryJson`/云完成判定未实现 | 云路径不可验收 | T-14/PB-02；本任务不声明云 PASS |
| T06-RISK-06 | 64..128 入站 ID 与 `DeviceKey` 63 上限 | C-10 可能无法持久化超长设备 | C-10 明确“展示/关联”策略并测试 |
| T06-RISK-07 | 模型数组只读仅编译期 | 调用方可运行时改写 | 后续组件约定不改写；必要时边界复制 |
| T06-RISK-08 | StateReport 严格性不足 | 畸形 report 被当成合法快照 | R-09 或 T-14 完整 strict adapter |
| T06-RISK-09 | `GatewayResultClass` 不使用 errorCode | 1006 细分文案可能退化 | C-14 `I18nKeys.gatewayKey(resultCode, errorCode)` 必须实现 |
| T06-RISK-10 | 真实设备/性能/云不可用 | 无真实 LAN/BLE/云证据 | T-11/T-12/T-19；保持 `UNAVAILABLE` |
| T06-RISK-11 | Test README 陈旧 | T-19 误读 15/15 | R-12 更新 |

---

## 8. 独立性与结论边界

- **独立性声明**：本报告由 `agent:quality-reviewer` 独立编写；评审者不是 T-06 的实现者，未参与被测代码的编写，只读审查并在本报告上写入结论。T-06 作者为 `agent:implementation-engineer`。
- 评审结论仅覆盖 `4d361bd` 的 diff 与 §1 范围；不覆盖 T-07 的 HMAC/签名、T-14 的云完成判定、设备/真实网络/性能。
- 构建/Hypium/设备结论基于同 revision 的证据日志；host/lint 已独立复跑。未修改被测文件，未写入构建产物。
- 本报告不构成 Stage Gate、用户验收或 `STABLE` 声明；修复后需重新评审。
