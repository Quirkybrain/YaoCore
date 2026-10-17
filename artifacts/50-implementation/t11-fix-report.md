# T-11 评审修复报告（REVIEW-T11-001）

- **Artifact ID**: IMP-T11-FIX
- **Producer**: agent:implementation-engineer
- **Type**: Implementation / Verification Evidence
- **Status**: Proposed（修复完成；待独立复审与 CQG-T11；组件仍为 `UNVERIFIED`）
- **Date**: 2026-10-17
- **Task**: `wp-037-fix-t11`（task 分支 `task/wp-035-transport`，父分支 `feat/yaocore-app`）
- **Base commit**: `3285d4b882e96204e6ea44a28778c6d2210ddf1f`（实现 `698883f` + 评审报告）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`
- **输入**（pin 校验通过）：REVIEW-T11-001、IMP-T11-TRANSPORT、DES-A/B、ADR-002、contract-baseline、project-constraints、TEST-001
- **上游**：`artifacts/70-review/t11-review.md`（CHANGES_REQUIRED）

> 本报告只记录 `wp-037-fix-t11` 的修复与当前 revision 的证据。原始 T-11 实现报告
> `t11-transport.md` 已就地修正 F-01 的“不重试验签/协议”表述、F-12 的 ack-lost
> 表述与 D-5 前提，并用 revision note 指向本报告。

---

## 0. 结果摘要

| 项 | 结果 |
|---|---|
| F-01（High/Blocking） | **已修复**：非 2xx 响应按“是否有 ACK 认证材料”分流；有材料则验签/协议异常原样抛出、不重试；4xx 无材料也不重试 |
| F-02（Medium） | **已修复**：明文 HTTP 请求显式 `usingCache:false` |
| F-03（Medium） | **已修复**：C-17 `probe()`/control 与 C-18 `probeRoute`/mDNS 均有独立 fail-closed pin 证据检查 |
| F-04（Medium） | **已修复**：C-10 `DeviceCommandRunner` 在 `port.send` 前执行 action↔deviceType 矩阵 |
| F-05（Medium） | **已修复**：`lan.control.transport.ms` + TLS 安全事件（gatewayId/profile/errorCode/time，无敏感值） |
| F-06（High/上游） | **未处理（上游）**：`build-profile.json5` 的 API 26 基线由 T-01/orchestrator 决策；本任务写范围不含构建配置 |
| F-07（Low/证据） | **未处理（T-19）**：HAP source-map 探针仍为非区分性预检；报告已加 revision note，不改历史证据 |
| F-08（Low） | **未修复（超出本 handoff 写范围）**：见 §3 偏离 D-1 |
| F-09（Low） | **已修复**：mDNS profile 不一致 → `TLS_PROFILE_INCONSISTENT` |
| F-10（Low） | **已修复**：`resetManualFailures()` 显式 reset；Beacon/mDNS 地址使用 `isAllowedLanIpv4` |
| F-11（Low） | **已修复**：set-* 动作值必填；`SET_MODE` 大写归一化后再签名 |
| F-12（Low） | **已修复**：Mock ack-lost 返回首次生成的同一 ACK（同 request_id/seq） |

**验证**：host **355/355 PASS**（T-11 基线 335 + 新增 20）；`codelinter` 无缺陷；
`hvigorw clean assembleHap --no-daemon` BUILD SUCCESSFUL；`ohpm install` exit 0。
设备/PB-03 运行时仍 `BLOCKED`，不得据此授予 `STABLE`/CQG。

---

## 1. 逐条处置

### F-01（High / Blocking）非 2xx 吞掉验签/协议异常并重试 5xx

**修复**（`service/gateway/LocalGatewayService.ets`）：

- `classifyControlResponse` 对非 2xx 先调用 `hasAckAuthenticationMaterial(response)`：
  - `X-YaoCore-Response-Alg` / `-Key-Id` / `-Response-Correlation` / `-Response-Sign`
    任一存在，或 body 可解析为含 `request_id`+`seq` 的对象 → **视为有认证材料**；
  - 有材料：直接 `mapControlAck`，`RESPONSE_AUTH_FAILED`、
    `RESPONSE_CORRELATION_MISMATCH`、`ACK_PROTOCOL_VIOLATION`、`ACK_STATE_MISMATCH`
    等异常原样抛出；`isRetryable` 为 false，不进入重试；
  - 无材料：保持 `HTTP_<status>` 分类；仅 5xx 按 300/900ms 精确重传。
- `sendWithRetry` 在得到 `HTTP_<status>` 后立即检查 `isRetryable`；4xx 无材料
  不再被循环重试（此前 4xx 会错误地跑满 3 次）。
- 注释中已删除“cannot be verified is just an HTTP failure, retryable for 5xx”
  的错误说明。
- 原始实现报告 §2.1 的重试声明已修正（见 `t11-transport.md` revision note）。

**新增负例**（`entry/src/test/host/GatewayLocal.test.mjs`）：

| 测试 | 断言 |
|---|---|
| `C17_control_http500WithBadSignatureFailsClosedWithoutRetry` | 1 次请求，`RESPONSE_AUTH_FAILED`，无 delay |
| `C17_control_http500WithBadCorrelationFailsClosedWithoutRetry` | 1 次请求，`RESPONSE_CORRELATION_MISMATCH` |
| `C17_control_http500WithSignedMalformedAckIsProtocolViolation` | 1 次请求，`ACK_PROTOCOL_VIOLATION` |
| `C17_control_http422WithBadSignatureFailsClosedWithoutRetry` | 1 次请求，`RESPONSE_AUTH_FAILED` |
| `C17_control_http4xxWithoutAckMaterialDoesNotRetry` | 1 次请求，`HTTP_404` |
| `C17_control_exhaustsThreeAttemptsOnUnsignedHttp500` | 3 次请求，delay `[300,900]`，`HTTP_500` |

精确重传语义未改变：仍复用同一 `HttpRequest`/body，未重新签名。

### F-02（Medium）明文路径未禁用 HTTP 缓存

**修复**（`service/gateway/adapters/OhosHttpTransport.ets`）：

- `sendCleartext` 的 `HttpRequestOptions` 增加 `usingCache: false`，并注释说明
  `/discover` 的固定 URL 若命中缓存会返回旧 challenge。
- 该路径同时覆盖 P-HMAC discover 与 control；TLS Path B 不经过系统 HTTP 缓存。

**验证限制**：`OhosHttpTransport` 为 COMPILED_ONLY；host 测试无法驱动真实
`@ohos.net.http` 缓存。已在代码层修复并通过 ArkTS 编译/lint；真实重复 discover
缓存行为仍需 T-19 设备/仿真器网络测试（R-21 保留）。

### F-03（Medium）P-TLS-PIN 服务层缺少独立 pin 证据检查

**修复**：

- `LocalGatewayService` 新增 `requireTlsEvidence(target, runtime, verification)`：
  - `P_TLS_PIN` 且无 `TlsVerification` → `TLS_VERIFIER_UNAVAILABLE`；
  - `matchedPin` 不在 `target.pins` → `TLS_PIN_MISMATCH`；
  - `matchedPin !== peerSpkiSha256Hex` → `TLS_HANDSHAKE_FAILED`。
- `performDiscover` 与 `sendWithRetry` 在收到响应后、任何解析/验签前调用；
  `probe()` 再独立调用一次（绑定探针契约的纵深防御）。
- `GatewayDiscoveryService` 新增 `requireRouteTlsEvidence(route, probe)`，在
  `probeRoute` 与 `consumeBeacon` 中独立要求：
  - `probe.profile === route.profile`；
  - P-TLS-PIN 时 `probe.tlsPinMatched` 必须属于 `route.pins`；
  - 否则分别抛出 `TLS_PROFILE_INCONSISTENT` / `TLS_VERIFIER_UNAVAILABLE` /
    `TLS_PIN_MISMATCH`，候选不进入 verified。
- 未改变“先验 pin 后发字节”的 Path B 顺序，也未引入明文回退。

**新增负例/正例**：`C17_tlsProbeWithoutVerificationEvidenceFailsClosed`、
`C17_tlsProbeWithPinOutsideRouteFailsClosed`、
`C17_tlsProbeWithInconsistentPeerSpkiFailsClosed`、
`C17_tlsControlWithMatchingEvidenceSucceeds`、
`C18_lastKnown_tlsRouteWithoutPinEvidenceIsNotVerified`、
`C18_lastKnown_tlsRouteWithPinOutsidePinsIsNotVerified`。

### F-04（Medium）C-10 未执行 action↔deviceType 矩阵

**修复**（`service/device/DeviceCommandRunner.ets`）：

- 在 `/@ohos import` 之外引入纯逻辑 `ControlPolicy`；`precheck=true` 且设备记录
  存在时，在 `port.send` 前调用
  `ControlPolicy.validate(record.state.snapshot.deviceType, record.isSupported,
  command.action, command.value)`。
- `CONFIGURATION_ERROR` / `PROTOCOL_VALUE_OUT_OF_RANGE` 直接返回拒绝，
  `DeviceControlPort.send` 零调用。
- C-17 `control()` 保持 `deviceType=undefined`（`GatewayTarget` 无设备类型），
  但不再依赖“C-10 已预检”的假设：C-10 现在确实执行矩阵。D-5 已同步更新。

**新增测试**：`T09_C10_commandRunnerEnforcesActionDeviceTypeMatrix`，覆盖
door×OPEN（允许）、door×SET_BRIGHTNESS（拒绝）、light×SET_BRIGHTNESS（允许）、
light×SET_MODE（拒绝）、ac×SET_MODE（允许）、ac×SET_TARGET_TEMPERATURE（允许）、
ac×越界温度（拒绝）、sensor×ON（拒绝）、light×缺值（拒绝），并断言拒绝时
`h.control.commands` 不增长。

### F-05（Medium）缺少 transport 指标与 TLS 安全事件

**修复**（`LocalGatewayService` + `GatewayDiscoveryService`）：

- control 每次 transport 返回后记录 `lan.control.transport.ms`
  （tag `attempt`）；成功确认后继续记录 `lan.control.commit.ms`。
- 新增 `tls_security_event` 日志（warn）：
  - `LocalGatewayService`：`TLS_PIN_MISMATCH`、`TLS_HANDSHAKE_FAILED`、
    `TLS_VERIFIER_UNAVAILABLE`、`TLS_PROFILE_INCONSISTENT`、
    `GATEWAY_PROFILE_BLOCKED`；
  - `GatewayDiscoveryService`：profile 不一致与 pin 证据失败。
  - 字段仅 `gatewayId`、`profile`、`errorCode`、`atMs`；无证书/秘密/body。
- `RecordingLogger` 增加结构化 `records`/`LoggerEntry.field()`，测试断言事件
  内容且确认不含测试 secret。

### F-08（Low）设备占位 `it` 可能误报通过

**未修复**：目标文件 `entry/src/ohosTest/ets/test/gateway/GatewayTransportDevice.test.ets`
不在本次 handoff 的 `writes`（`entry/src/test/` 不含 `ohosTest/`）。按“不得改其他
文件/不越界”的约束未修改。修复方案（供测试负责人/T-19 执行）：删除该 `it`
或使用 Hypium 的 skip/pending 机制，并在设备报告中把“占位断言通过”与 PB-03
运行时证据严格区分。

### F-09（Low）mDNS profile 不一致被误报为 GATEWAY_ID_MISMATCH

**修复**（`GatewayDiscoveryService.consumeBeacon`）：按 `!reachable` →
`GATEWAY_UNREACHABLE`、identity 不等 → `GATEWAY_ID_MISMATCH`、其余 TLS 证据
问题 → `TLS_PROFILE_INCONSISTENT`/`TLS_VERIFIER_UNAVAILABLE`/`TLS_PIN_MISMATCH`
分类；warning 与候选 `errorCode` 使用同一码。新增
`C18_mdns_profileMismatchIsTlsProfileInconsistent`。

### F-10（Low）手动失败预算无 reset；Beacon 地址未限制

**修复**：

- `GatewayDiscoveryService.resetManualFailures(gatewayId)`：显式用户动作可清零
  失败计数与 2s 间隔闸门；自动发现不会调用它。
  新增 `C18_manual_explicitResetClearsFailureBudgetAndInterval`。
- `DiscoveryBeacon` 构造器与 `MdnsDiscoveryTransport.toBeacon` 改用
  `IpAddressUtil.isAllowedLanIpv4`，拒绝 loopback/link-local/组播/广播/0.0.0.0。
  新增 `C18_beacon_rejectsNonLanAddresses`。

### F-11（Low）SET_MODE 大小写/缺值

**修复**（`GatewayRequestPolicy`）：

- `requiresValue`：`SET_BRIGHTNESS`/`SET_COLOR`/`SET_TARGET_TEMPERATURE`/`SET_MODE`
  缺值 → `PROTOCOL_VALUE_OUT_OF_RANGE`；布尔动作仍允许省略 value。
- `normalizeValue` 同时大写 `SET_COLOR` 与 `SET_MODE`；C-17 的签名输入与 ACK
  期望均使用归一化值。
- 新增 `C17_controlPolicyRequiresValueForSetActions`、
  `C17_controlPolicyNormalizesAcModeCase`、`C17_controlNormalizesAcModeBeforeSigning`。

### F-12（Low）Mock ack-lost 未返回原 ACK

**修复**（`service/mock/MockGatewayService.ets`）：首次 ack-lost 调用生成 ACK 后
连同 `ControlOutcome` 存入 `MockRecord` 并抛 `GATEWAY_TIMEOUT`；同命令再次调用
直接返回该 outcome（同 `request_id`/`seq`），不再生成新身份。测试
`C20_ackLost_firstAttemptTimedOutThenOriginalAckIsReturned` 断言 `seq=1`、
`requestId='req-<FIXED_MS>-1'`、`idempotentReplay=false`、`shouldApplyState=true`
（客户端从未收到首个 ACK，因此原 ACK 仍应应用）。
原始实现报告 §2.3 的“原 ACK + idempotent_replay”表述已修正。

---

## 2. 变更文件

```text
entry/src/main/ets/service/device/DeviceCommandRunner.ets        # F-04
entry/src/main/ets/service/gateway/DiscoveryModels.ets           # F-10
entry/src/main/ets/service/gateway/GatewayDiscoveryService.ets   # F-03/F-05/F-09/F-10
entry/src/main/ets/service/gateway/GatewayRequestPolicy.ets      # F-04 注释/F-11
entry/src/main/ets/service/gateway/LocalGatewayService.ets       # F-01/F-03/F-05
entry/src/main/ets/service/gateway/adapters/OhosHttpTransport.ets# F-02
entry/src/main/ets/service/gateway/discovery/MdnsDiscoveryTransport.ets # F-10
entry/src/main/ets/service/mock/MockGatewayService.ets           # F-12

entry/src/test/host/DomainDevice.test.mjs                        # F-04 矩阵测试
entry/src/test/host/GatewayDiscovery.test.mjs                    # F-03/F-09/F-10 测试
entry/src/test/host/GatewayLocal.test.mjs                        # F-01/F-03/F-05/F-11 测试
entry/src/test/host/GatewayMock.test.mjs                         # F-12 测试
entry/src/test/host/TransportFakes.ets                           # F-05 结构化 logger

entry/src/test/evidence/t11-fix-*.log|tap                        # 本次原始命令输出
artifacts/50-implementation/t11-transport.md                     # F-01/F-12/D-5 修正
artifacts/50-implementation/t11-fix-report.md                    # 本报告
```

未修改：`contracts/**`、`build-profile.json5`、`entry/src/ohosTest/**`、任何仓库外文件。

---

## 3. 偏离与待决

| # | 项 | 处置 |
|---|---|---|
| D-1 | F-08 无法修复 | `entry/src/ohosTest/**` 不在 handoff `writes`/`commit_paths`；本任务遵守写范围。需新 handoff 或 T-19/测试负责人处理。 |
| D-2 | D-5 语义更新 | C-10 现在实际调用 `ControlPolicy` 矩阵；C-17 直接调用仍传 `undefined`。建议 solution-architect 在 CQG 前确认该分工并同步 DES-A §14.2.3 的“预检”措辞。 |
| D-3 | F-06 未处理 | `compatibleSdkVersion: 26.0.0` 属上游/T-01 决策；本任务不修改构建配置，也不宣称 CP-01 已验证。 |
| D-4 | D-4 错误码命名 | `RESPONSE_AUTH_FAILED`/`RESPONSE_CORRELATION_MISMATCH` 与 §14.4/contract-baseline 的 `CONTROL_*`/`ACK_*` 仍未统一；等待 solution-architect 裁定（R-20）。 |
| D-5 | F-02 运行时验证 | `usingCache:false` 只能编译验证；真实缓存行为留待 T-19 设备/网络测试。 |

---

## 4. 验证（本 revision 实际执行，cwd = 仓库根）

```bash
ohpm install
hvigorw clean assembleHap --no-daemon
codelinter -c code-linter.json5 -p default .
entry/src/test/run-host-tests.sh
```

| 命令 | 结果 | 证据 |
|---|---|---|
| `ohpm install` | **exit 0**（install completed） | `entry/src/test/evidence/t11-fix-ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | **exit 0，BUILD SUCCESSFUL**（35 tasks：34 executed，1 up-to-date；无签名） | `entry/src/test/evidence/t11-fix-clean-assemble.log` |
| `codelinter -c code-linter.json5 -p default .` | **exit 0，No defects found** | `entry/src/test/evidence/t11-fix-codelinter.log` |
| `entry/src/test/run-host-tests.sh` | **exit 0，tests 355 / pass 355 / fail 0** | `entry/src/test/evidence/t11-fix-host-node-tests.tap` |

### 4.1 测试计数

| 层 | 数量 | 说明 |
|---|---|---|
| Host 总 | **355** | T-11 基线 335 + 本次新增 20 |
| C-17 相关新增 | 14 | F-01 负例 6、F-03 4、F-05 1、F-11 3 |
| C-18 相关新增 | 5 | F-03 2、F-09 1、F-10 2 |
| C-10 相关新增 | 1 | F-04 矩阵 |
| C-20 | 17（改写 1） | ack-lost 语义改为“原 ACK” |
| 设备侧 | 未执行 | 仍 `BLOCKED`（无 hdc target/签名）；不计入 PASS |

### 4.2 关键回归断言

- 精确重传：`C17_control_retriesExactBytesOnTimeout` 仍通过（同 body/nonce/seq）。
- P-BLOCKED 零请求、P-TLS pin mismatch 无明文回退仍通过。
- DEV-ONLY 先于验签拒绝仍通过。
- 非零 `result_code` 不抛异常、`reported_state` 缺失 → `ACK_PROTOCOL_VIOLATION` 仍通过。
- C-18 identity/profile/pin 三层验证：任何一层失败均不产生 verified 候选。
- C-20 生产 ACK 链（真实 `CanonicalBuilder`/`ResponseVerifier`/`ControlAckMapper`）不变。

---

## 5. 残余风险

| ID | 风险 | 级别 | 下一步 |
|---|---|---|---|
| R-03 | Path B 真机语义未证（SPKI 编码、skip 行为、错误码、TLS 版本） | High | T-19/设备 runner；openssl 对齐；不得把编译当运行证据 |
| R-21 | `usingCache:false` 仅编译验证 | Medium | T-19 真实网络重复 discover |
| R-22 | CP-01 构建基线 26（F-06） | High（上游） | T-01/orchestrator 决策并重跑构建 |
| R-25/R-27 | 手动 reset 的 UX 入口、设备占位测试误报 | Low | T-19/测试负责人接入 `resetManualFailures` 并修正 ohosTest |
| R-20 | D-4 命名不一致 | Low/Medium | solution-architect 统一 |
| — | F-08 未修复（写范围） | Low | 新 handoff 或 T-19 |

---

## 6. Handoff

```text
STATUS: RETURNED_FOR_GATE / FIXES_COMPLETE_PENDING_REVIEW
SUMMARY: F-01..F-05 与 F-08..F-12 中，除 F-08（超出 handoff 写范围）外全部修复；新增 20 条 host 测试与 4 类负例，host 355/355、codelinter 无缺陷、clean assemble 成功。
ARTIFACTS_CREATED: artifacts/50-implementation/t11-fix-report.md; entry/src/test/evidence/t11-fix-*.log|tap
ARTIFACTS_UPDATED: artifacts/50-implementation/t11-transport.md（F-01/F-12/D-5/可观测性修正）
DECISIONS: C-10 执行为矩阵权威（D-5 更新）；P-TLS 证据在 C-17/C-18 双层 fail-closed；ack-lost 返回原 ACK。
ASSUMPTIONS: 服务层允许对 ACK 形状 body 做“仅分类”解析；4xx 无材料不重试符合 DES-A §14.4。
RISKS: F-06/CP-01 上游；PB-03 运行时 BLOCKED；F-02 缓存行为待设备；F-08 未修复；D-4 命名待 architect。
VALIDATION: ohpm install exit 0；clean assembleHap BUILD SUCCESSFUL（exit 0）；codelinter No defects（exit 0）；host 355/355 fail 0（exit 0）。
NEEDS_CLARIFICATION: F-08 需扩展写范围或转 T-19；D-4 命名由 solution-architect 统一；D-5 分工建议 architect 确认。
NEXT_ACTION: 独立 reviewer 复审受影响代码并重跑三命令；F-06 由 T-01/orchestrator 处理；设备可用后执行 PB-03 清单。
```
