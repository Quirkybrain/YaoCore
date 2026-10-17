# T-11 聚焦复审报告（F-01..F-12 关闭确认 / CQG-T11）

- **Artifact ID**: REV-T11-002
- **Producer**: agent:quality-reviewer
- **Type**: Independent Code Review / Review Handoff
- **Status**: **PASS（代码级，条件式）**
- **Date**: 2026-10-17
- **Task**: `wp-039-review-t11b`（task 分支 `task/wp-035-transport`，父分支 `feat/yaocore-app`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`
- **Reviewed revision**: `514671d8cdcb47a46073a1a58d260d8fd03a07f9`（HEAD，`build(compat): 核验 API14 兼容性配置`）
- **Fix revisions**: `36ce10b`（F-01..F-05、F-09..F-12 修复；F-08 未修）、`514671d`（F-06 构建配置）
- **Previous review**: `3285d4b`（`artifacts/70-review/t11-review.md`，CHANGES_REQUIRED）
- **Independence**: 本复审由未参与 T-11 产品代码、`wp-037-fix-t11` 修复或 `wp-038-build-compat` 构建配置修改的 `quality-reviewer` 执行。被审代码、测试、证据、修复报告与上游 Artifact 均未修改；评审中的构建产物仅写入被 Git 忽略的构建目录，未入库。唯一仓库写入为本报告。

---

## 1. 复审范围与输入完整性

### 1.1 范围内

```text
entry/src/main/ets/service/gateway/**        # C-17/C-18 路由、策略、端口、适配器、发现
entry/src/main/ets/service/device/DeviceCommandRunner.ets  # C-10 控制用例（F-04）
entry/src/main/ets/service/mock/**           # C-20 Mock（F-12）
entry/src/test/host/**                       # 355 条 host 测试与 fakes
entry/src/test/evidence/**                   # 修复与构建兼容证据
build-profile.json5                          # F-06 构建配置
artifacts/50-implementation/t11-fix-report.md
artifacts/50-implementation/t11-build-compat.md
artifacts/50-implementation/t11-transport.md # revision note 与 D-5 修正
```

- 复审目标与 handoff `review_targets` 一致；`entry/src/test/` 覆盖 host 测试与证据，未包含 `entry/src/ohosTest/**`。
- 修复 diff 范围：`3285d4b..36ce10b`（19 文件）与 `36ce10b..514671d`（7 文件）；全部落在对应 handoff 声明范围内，未发现构建产物、HAP、证书/私钥或 `oh_modules` 入库。
- `git status --porcelain` 在复验前后均为空；`git diff --check` 通过。

### 1.2 输入 pin（handoff `wp-039-review-t11b`）

本节实际重新计算了全部 pin 输入的 SHA-256：

| 输入 | 期望（pin 前缀） | 实际 | 结果 |
|---|---|---|---|
| `artifacts/70-review/t11-review.md` | `aa8e1a62ea35` | `aa8e1a62ea35` | 一致 |
| `artifacts/50-implementation/t11-fix-report.md` | `89c9964ae2eb` | `89c9964ae2eb` | 一致 |
| `artifacts/50-implementation/t11-build-compat.md` | `24f54fc71998` | `24f54fc71998` | 一致 |
| `artifacts/50-implementation/t11-transport.md` | `696322cb0ae0` | `696322cb0ae0` | 一致 |
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `5599e693fafe` | `5599e693fafe` | 一致 |
| `artifacts/20-architecture/adr-002-lan-security-channel.md` | `67943a6e1d8d` | `67943a6e1d8d` | 一致 |
| `artifacts/20-architecture/contract-baseline.md` | `6673a990d502` | `6673a990d502` | 一致 |
| `artifacts/20-architecture/project-constraints.md` | `283046210e68` | `283046210e68` | 一致 |
| `artifacts/60-testing/test-plan.md` | `33485cc39abd` | `33485cc39abd` | 一致 |

- 评审快照：`refs/swe/snapshots/20261017T123254Z-wp-039-review-t11b-c37f13a2`（snapshot commit `66b4c2ebb50c85099fbc5929062f526c2cb967fe`）。
- 权威章节：DES-A §14/§15/§18.9/§19；ADR-002 §4/§6/§7；contract-baseline §3/§4/§8.6；project-constraints CP-01、SC-11/SC-13/SC-15、PR-03/PR-06/PR-13；TEST-001 §4.2/§5/§7；delivery-plan §4.1 CQG。
- 被审代码未发生“评审中修改”；构建仅影响 `entry/build/**` 等忽略路径。

### 1.3 排除/未覆盖

- 真实设备/模拟器、真实 LAN 网关、真实 mDNS/UDP 线格式（PB-01）、真实证书/SPKI/TLS 1.2/1.3 运行时行为、API 14/15 设备安装与运行。
- Python 仿真器与 App 的真实网络契约执行；当前仅复核 host/fake 层与仿真器工具层既有证据。
- 设备侧 Hypium 的 `GatewayTransportDevice.test.ets` 执行；整体仍 `BLOCKED`。
- C-17/C-18/C-20 之外的组件（T-12+、VM/UI、组合根 C-28）不在本次复审范围。

---

## 2. 独立复验结果

### 2.1 规定命令（cwd = 仓库根，`514671d`）

| 命令 | 本次实际结果 | 说明 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS：355 tests / 355 pass / 0 fail / 0 skip，exit 0** | TAP `1..355`；`# fail 0`；T-11 净新增 20 条测试（新增 21、改写 1）均出现：335 基线 − 1 改写 + 21 新增 = 355。 |
| `codelinter -c code-linter.json5 -p default .` | **PASS：No defects found in your code，exit 0** | 产品源码范围；`entry/src/test/**`、`entry/src/ohosTest/**` 按配置不在 lint 范围。 |
| `hvigorw clean assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0** | 35 tasks（34 executed，1 up-to-date）；仅有既有“未配置 signingConfigs，跳过签名”WARN；不得据此写成设备 PASS。 |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon`（附加） | **PASS：BUILD SUCCESSFUL，exit 0** | 35 tasks（35 executed）；仅验证设备测试 HAP 可编译，未执行设备断言。 |
| HAP 元数据抽查 | **PASS** | `module.json`：`minAPIVersion=50002014`、`targetAPIVersion=260000026`、`compileSdkVersion=26.0.0.105`；`pack.info`：`apiVersion={compatible:14,target:26}`。 |
| HAP 内容探针（Mock/网关代码） | **PASS（非区分性）** | `ets/sourceMaps.map`、`ets/modules.abc` 均无 `service/mock`、`MockGatewayService`、`MockBleProvisioningClient`；同时也不含 `service/gateway`/`LocalGatewayService`（当前无生产组合根），因此该探针仍不能证明“组合根不会装配 Mock”。F-07 保持 T-19/T-20 门禁。 |
| `git status --porcelain` / `git diff --check`（全部复验后） | **clean / 通过** | 构建产物均被忽略；未产生未声明仓库改动。 |

### 2.2 关键回归断言

复验确认以下既有行为未被 F-01/F-03/F-04/F-05/F-11 修复破坏：

- 正常 2xx ACK 链：`C17_control_success_appliesAckChain`、`C17_sendUsesBoundRouteAndRejectsUnboundGateway`；
- 精确重传：`C17_control_retriesExactBytesOnTimeout` 仍复用同一 body/nonce/seq；
- P-BLOCKED 零请求、P-TLS pin mismatch 不回退明文、DEV-ONLY 先于验签；
- 非零 `result_code` 不抛异常；缺 `reported_state` → `ACK_PROTOCOL_VIOLATION`；目标不一致 → `ACK_STATE_MISMATCH`；
- 传输失败 3 次精确重传；无材料 5xx 3 次、4xx 1 次；带认证材料的错误响应 1 次且 fail-closed；
- P-TLS probe/control 的匹配证据正例；C-18 identity/profile/pin 三层验证；
- C-20 真实 ACK 链（`CanonicalBuilder`/`ResponseVerifier`/`ControlAckMapper`）未改变。

---

## 3. F-01..F-12 关闭状态

> 状态口径：**CLOSED** = 代码、测试/证据与报告在当前 revision 一致，未发现阻断问题；**CLOSED（构建/代码）** = 仅该层可证，运行时留 T-19；**DEFERRED** = 修复报告已如实记录并明确转移，不构成本次代码阻断；**OPEN** = 仍未关闭，但已记录到残余风险。

| ID | 严重度 | 状态 | 关闭证据 | 残余/边界 |
|---|---|---|---|---|
| **F-01** | High | **CLOSED** | `LocalGatewayService.ets:283-379`：非 2xx 先经 `hasAckAuthenticationMaterial()`；有材料直接 `mapControlAck()`，验签/correlation/protocol 异常原样抛出；无材料才归 `HTTP_<status>`；`sendWithRetry` 在分类后立即检查 `isRetryable`，4xx 不再空跑 3 次。新增负例：500+bad sign、500+bad correlation、500+signed malformed ACK、422+bad sign、404+无材料、500 无材料 3 次（`GatewayLocal.test.mjs:283-345`）。 | 该修复同时把“4xx 无材料”从错误的 3 次重试改为 1 次，符合 DES-A §14.4；无新阻断。 |
| **F-02** | Medium | **CLOSED（代码）/ 运行时待证** | `OhosHttpTransport.ets:118-123`：`usingCache:false`；注释明确 `/discover` 固定 URL 的旧 challenge 风险。P-HMAC discover/control 均走该路径；P-TLS 走 `TLSSocket`，不经过系统 HTTP 缓存。 | Host 无法驱动真实 `@ohos.net.http` 缓存；R-21 保持，T-19 重复 discover/网络测试。 |
| **F-03** | Medium | **CLOSED** | C-17：`requireTlsEvidence()`（`LocalGatewayService.ets:387-405`）在 `performDiscover`、`sendWithRetry`、`probe` 三处检查 `TlsVerification`；缺失 → `TLS_VERIFIER_UNAVAILABLE`，pin 不在目标 → `TLS_PIN_MISMATCH`，matched pin 与 peer SPKI 不一致 → `TLS_HANDSHAKE_FAILED`。C-18：`requireRouteTlsEvidence()`（`GatewayDiscoveryService.ets:283-299`）在 `probeRoute`/`consumeBeacon` 检查 profile 与 pin 证据。新增 6 条测试（3 条 probe fail-closed、1 条 control 正例、2 条 C-18）；未改变“先验 pin 后发字节”。 | 无。P-TLS 真实运行时仍归 R-03。 |
| **F-04** | Medium | **CLOSED（行为）** | `DeviceCommandRunner.ets:80-90`：`precheck=true` 且记录存在时，在 `port.send` 前调用 `ControlPolicy.validate(record.state.snapshot.deviceType, record.isSupported, action, value)`；拒绝路径直接返回，端口零调用。`T09_C10_commandRunnerEnforcesActionDeviceTypeMatrix` 覆盖 door×OPEN、door×SET_BRIGHTNESS、light×SET_BRIGHTNESS、light×SET_MODE、ac×SET_MODE、ac×温度、ac×越界、sensor、light×缺值。 | R2-01：C-10 现在编译期依赖 C-17 的 `GatewayRequestPolicy.ets`（纯逻辑、无环），建议架构确认或后续移动到共享纯逻辑模块；不阻断。D-5 更新已记录。 |
| **F-05** | Medium | **CLOSED** | `sendWithRetry` 每次 transport 返回后记录 `lan.control.transport.ms`（tag `attempt`），成功确认后记录 `lan.control.commit.ms`（`LocalGatewayService.ets:293-305`）；TLS 失败安全事件 `tls_security_event`（`gatewayId/profile/errorCode/atMs`，无 secret/证书/body）在 `sendTransport`、`requireTlsEvidence`、`resolveRuntimeProfile` 及 C-18 `logTlsEvent` 中记录。测试 `C17_control_success...`、`C17_control_retriesHttp500WithoutSignedAck`、`C17_tlsHandshakeFailureIsLoggedWithoutSecret`、`C17_pBlockedSendsNoRequest` 断言计数/字段。 | 无阻断；真实设备上的日志落盘/脱敏仍由 T-19 复核。 |
| **F-06** | High（上游） | **CLOSED（构建配置）/ 运行时待证** | `build-profile.json5:8-10`：`compileSdkVersion="26.0.0"`、`targetSdkVersion="26.0.0"`、`compatibleSdkVersion="5.0.2(14)"`；独立 clean assemble 成功；HAP `minAPIVersion=50002014`、`pack.info compatible=14`。详见 §3.1。 | CP-01 运行时与 API 14 设备安装仍 `UNVERIFIED`（R-22）；不得把构建基线写成 CP-01 PASS。 |
| **F-07** | Low（证据） | **DEFERRED（T-19/T-20）** | 修复报告 §0/§3 明确“未处理”；`t11-transport.md` revision note 保留原始 335 证据；本次 HAP 探针再次确认非区分性（无 gateway 代码，也无 Mock 字符串）。静态 import 扫描仍是当前 SC-11 门禁。 | T-19 组合根出现后必须重跑 source map 原始命令并保存；不得以本次探针替代。 |
| **F-08** | Low（测试诚实性） | **OPEN / DEFERRED（T-19）** | 修复报告 §1 F-08、§3 D-1、§5 已如实记录“未修复，超出 handoff 写范围”；`GatewayTransportDevice.test.ets:87-94` 的占位 `it` 仍只断言默认端口；当前设备套件整体 `BLOCKED`，报告未把它写成 PB-03 证据。 | 需 T-19/测试负责人删除或使用 Hypium skip/pending；R-27 保留。不得把该占位断言当设备 pin 契约证据。 |
| **F-09** | Low | **CLOSED** | `consumeBeacon` 将 `!reachable`、identity 不等、TLS 证据问题分别归类；`requireRouteTlsEvidence` 抛 `TLS_PROFILE_INCONSISTENT`/`TLS_VERIFIER_UNAVAILABLE`/`TLS_PIN_MISMATCH`，warning 与候选 errorCode 一致。测试 `C18_mdns_profileMismatchIsTlsProfileInconsistent`。 | 无。 |
| **F-10** | Low | **CLOSED（代码）** | `resetManualFailures(gatewayId)` 清零失败计数与 2s 间隔（`GatewayDiscoveryService.ets:220-223`），自动发现不调用；`DiscoveryBeacon` 构造器与 mDNS `toBeacon` 使用 `IpAddressUtil.isAllowedLanIpv4`（`DiscoveryModels.ets:136`、`MdnsDiscoveryTransport.ets:101`）。测试 `C18_manual_explicitReset...`、`C18_beacon_rejectsNonLanAddresses`。 | reset 尚无生产 UI 入口（T-19/T-15 接入）；R-25 低风险保留。`GatewayRoute` 的地址仍只做 IPv4 语法校验（绑定来源可信），未扩大范围。 |
| **F-11** | Low | **CLOSED** | `GatewayRequestPolicy.ets:117-120`：`SET_BRIGHTNESS/SET_COLOR/SET_TARGET_TEMPERATURE/SET_MODE` 缺值 → `PROTOCOL_VALUE_OUT_OF_RANGE`；`normalizeValue` 同时大写 `SET_COLOR` 与 `SET_MODE`（`:108-114`），C-17 用于签名与 ACK 期望。测试 `C17_controlPolicyRequiresValueForSetActions`、`C17_controlPolicyNormalizesAcModeCase`、`C17_controlNormalizesAcModeBeforeSigning`。 | 无。 |
| **F-12** | Low（测试保真度） | **CLOSED** | `MockGatewayService.ets:118-130`：ACK_LOST 首次生成 ACK 后连同 outcome 存入 `MockRecord` 并抛 `GATEWAY_TIMEOUT`；同命令再次调用返回同一 outcome（同 `request_id/seq`，不生成新身份）。测试 `C20_ackLost_firstAttemptTimedOutThenOriginalAckIsReturned` 断言 `seq=1`、固定 requestId、`idempotentReplay=false`、`shouldApplyState=true`。 | 这是 Mock 客户端级语义；C-17 字节级精确重传仍由 `C17_control_retriesExactBytesOnTimeout` 覆盖。报告 §2.3 表述已修正。 |

### 3.1 F-06 单独评估：`compatibleSdkVersion`、`minAPIVersion` 与“API 14 可安装基线”

**结论：构建/打包层的 API 14 可安装基线成立；运行时 API 14 兼容性不成立（未验证），报告对该边界基本如实。**

1. **配置合法且生效**：`compatibleSdkVersion="5.0.2(14)"` 符合当前 hvigor/HarmonyOS 字符串版本格式；`compileSdkVersion` 显式固定 `26.0.0`，`targetSdkVersion` 保持 `26.0.0`。独立 clean assemble 成功，说明 schema/API 配置校验通过。
2. **产物元数据可复现**：本次独立构建得到 `minAPIVersion=50002014`（5.0.2.14）、`targetAPIVersion=260000026`、`compileSdkVersion=26.0.0.105`；`pack.info` 为 `compatible=14, target=26`。因此“HAP 声明的最低兼容 API 为 14、安装门槛为 API >= 14”这一**构建侧**结论成立。
3. **不能推出的结论**：构建使用 API 26 SDK，`minAPIVersion` 只描述安装/兼容声明，不证明运行时不调用高于 API 14 的接口；`TLSSocket`/证书 pin/自签名 + `skipRemoteValidation`/TLS 版本/错误码区分/性能仍无 API 14/15 设备证据。因此 CP-01 的运行时部分仍为 `UNVERIFIED`，CQG 不得把 CP-01 标为 PASS。
4. **报告诚实性**：`t11-build-compat.md` §0/§4 明确写出“不证明 API 14 设备运行时行为”“编译通过不代表运行时不会调用高于 API 14 的接口”，并保留 R-22；该边界声明成立。唯一可加强的是明确“未签名 HAP 仍需签名才能实际安装”，但报告已在 R-29/证据日志中披露无签名，本次不作为 finding。
5. **残余**：R-22（Medium）保留；T-19 需在 API 14/15 设备/模拟器矩阵安装并验证 `TLSSocket`/pin/控制链路，CI 固定 SDK 26.0.0.105。

### 3.2 D-4、F-08 等残余的接受状态

| 项 | 状态 | 说明 |
|---|---|---|
| **D-4 错误码命名** | **OPEN（契约命名，非代码阻断）** | C-17 生产路径使用 `RESPONSE_AUTH_FAILED`/`RESPONSE_CORRELATION_MISMATCH`（§18.7/TEST-001 SEC-N07/N08）；DES-A §14.4/contract-baseline §4.2 仍写 `CONTROL_RESPONSE_AUTH_FAILED`/`ACK_CORRELATION_MISMATCH`。两者 i18n key 相同（`errors.app.control_response_auth_failed`/`ack_correlation_mismatch`），但 `ErrorCategory` 分别为 SECURITY/GATEWAY。修复报告 D-4 已如实记录“等待 solution-architect 裁定”；CQG 应把它列为未关闭契约项（R-20），不得声称命名已统一。 |
| **F-08 设备占位测试** | **OPEN / DEFERRED** | 未修复原因（写范围不含 `entry/src/ohosTest/**`）已记录；占位 `it` 仍会“通过”但不验证 pin 契约。T-19/测试负责人必须删除或显式 skip，且不得把它当作 PB-03 证据。 |
| **F-07 / R-16 Mock 组合根门禁** | **DEFERRED（T-19/T-20）** | 当前 HAP 无 Mock 字符串是不可否认的弱证据，但同时无生产 gateway 代码；静态 import 扫描继续有效。组合根出现后重跑 source map。 |
| **R-21 `usingCache:false` 运行时** | **DEFERRED（T-19）** | 仅编译可证；真实重复 discover/缓存行为待网络测试。 |
| **R-22 CP-01 运行时** | **DEFERRED（T-19）** | 构建基线已修正；运行时 API 14 未验证。 |
| **R-03 PB-03 Path B 运行时** | **BLOCKED** | 无设备/签名；pin-match/mismatch/handshake-fail、SPKI 对齐、TLS 1.2/1.3、p95 均未执行。不得授予设备 PASS。 |
| **R-23 设备/签名** | **BLOCKED** | `hdc` 无 target、未签名；ohosTest 仅编译。 |

---

## 4. 新发现（R2-xx）

本次未发现阻断级新缺陷。以下为低风险、非阻断的独立观察：

| ID | 严重度 | 位置 | 事实与影响 | 建议 |
|---|---|---|---|---|
| **R2-01** | **Low（架构/可维护性）** | `entry/src/main/ets/service/device/DeviceCommandRunner.ets:22` | C-10 用例现在编译期 import C-17 文件 `service/gateway/GatewayRequestPolicy.ets` 中的 `ControlPolicy`。该文件是纯逻辑、无 `@ohos` 依赖、无循环，host 与 ArkTS 构建均通过；但 component-graph 未列 C-10 → C-17 的编译期依赖，DES-B §5.1.4 又写“只调 DeviceControlPort”。这是行为修复带来的真实耦合，不是运行时缺陷。 | solution-architect 在 CQG 记录中确认该“共享纯策略”分工，或后续把 `ControlPolicy` 移到共享纯逻辑模块；不要求本次修复重做。 |
| **R2-02** | **Low（测试覆盖）** | `entry/src/test/host/GatewayLocal.test.mjs:562-574` | F-03 的 `probe()` 无证据/pin 不在目标/inconsistent peer SPKI 均有负例，`control()` 只有“匹配证据成功”的正例；C-17 `sendWithRetry` 的同一 `requireTlsEvidence` 负向路径未由 control 测试直接覆盖。代码检查无缺陷，但测试证据可以更完整。 | T-19 或后续变更补一条 `P-TLS control + HttpResponse 无 tlsVerification → TLS_VERIFIER_UNAVAILABLE` 的 host 负例；不阻断本次 CQG。 |

---

## 5. CQG-T11 对照

> 本表是评审意见，不是 Orchestrator 的 Gate 记录；`PASS` 仅指当前 revision 的代码/构建/host 证据。

| CQG 检查 | 结果 | 证据与边界 |
|---|---|---|
| 构建 | **PASS** | `hvigorw clean assembleHap --no-daemon` exit 0（35 tasks）；ohosTest HAP 附加编译 exit 0。 |
| 静态检查 | **PASS** | `codelinter` exit 0，No defects。 |
| 单元测试 | **PASS（host）** | 355/355，0 fail/0 skip，exit 0；T-11 新增负例覆盖 F-01/F-03/F-04/F-09/F-10/F-11/F-12。 |
| 契约测试 | **PASS（host/协议链）** | C-17/C-18/C-20 host 契约链与 Mock 通过；真实 Python 仿真器 TLS/网络契约未执行，归 T-19，不计入 PASS。 |
| 契约符合 | **PASS（有 R-20/D-4）** | 与 DES-A §14.2/§14.3/§14.4/§15、CB §3/§4/§8.6 的行为一致；D-4 命名仍是未关闭契约歧义。 |
| 分层/依赖 | **PASS（有 R2-01 记录）** | 无平台 import 进入纯逻辑；C-10 → C-17 `ControlPolicy` 为低风险编译期耦合，建议架构确认。 |
| 安全 | **PASS（代码/host）** | P-BLOCKED 前置、无明文回退、先验 pin 后发字节、DEV-ONLY 先于验签、非 2xx 认证材料 fail-closed、安全日志无 secret；设备 TLS 运行时 `BLOCKED`。 |
| i18n | **N/A（T-11 无 UI 文案）** | 错误码 i18n key 存在；D-4 两套 code 映射到相同 key（category 不同）。 |
| 代码评审 | **PASS** | 本报告为独立 reviewer；未参与实现/修复。 |
| 可追溯 | **部分** | 修复报告与 D-4/D-5 已记录；TEST-001 的 C-17/C-18/C-20 仍为 `NOT_RUN`，客户端侧 SEC-N07/N08/N10/N13/N15/N17/N25 仍为 `NOT_RUN`/`BLOCKED`（SEC-N13 仅 simulator 发出标记为既有 PASS），CQG 必须更新，不能把本报告当成全量测试 PASS。 |
| 设备 | **BLOCKED** | 无 `hdc` target/签名；ohosTest 仅编译；F-08 占位 `it` 仍在；PB-03 运行时未验证。 |
| Mock 生产排除 | **PASS（静态）/ 非区分性 HAP 探针** | 主树无生产 import；HAP 无 Mock 字符串；但当前无 gateway 生产代码，T-19/T-20 需 source-map 门禁。 |

**CQG-T11 建议意见**：以**代码级 PASS（条件式）**记录。C-17/C-18/C-20 可进入 `STABLE（代码级，条件式）` 的建议状态，条件为：D-4 契约命名由 solution-architect 裁定/R-20 记录；F-07/F-08 转 T-19/T-20；R-21/R-22/CP-01 运行时由 T-19 设备矩阵补齐；设备/PB-03 保持 `BLOCKED`。最终 CQG/STABLE 与 Stage Gate 决定由 Orchestrator 依据本意见与证据作出。

---

## 6. Verdict

**PASS（代码级，条件式）**

理由：

1. 上轮 **F-01（High）已关闭**：非 2xx 响应按认证材料分流，验签/correlation/protocol 失败不重试，4xx 无材料不重试；新增 6 条 host 负例，精确重传与正常错误路径无回归。
2. **F-02/F-03/F-04/F-05/F-09/F-10/F-11/F-12 已关闭**（其中 F-02 仅代码层、运行时归 T-19），并有对应的正/负例或结构化证据。
3. **F-06 在构建配置层关闭**：`compatibleSdkVersion` 修正为 API 14，HAP `minAPIVersion=50002014` 与 `pack.info compatible=14` 独立复现；运行时 API 14 兼容性仍为 `UNVERIFIED`，报告未过度宣称。
4. **F-07/F-08 已如实记录并明确转 T-19/T-20**；D-4 仍是已登记的契约命名项（R-20），不构成本次代码阻断。
5. host 355/355、codelinter、clean assembleHap 与附加 ohosTest 编译均通过；未发现新的阻断级缺陷。

**未授予**：设备/PB-03 运行时 PASS、CP-01 运行时 PASS、Stage Gate、用户验收。CQG-T11 的最终 Gate 记录由 Orchestrator 完成。

**放行条件（CQG 记录必须包含）**：

1. 记录本报告的 revision `514671d`、355/355 host、codelinter、clean assemble、HAP `minAPIVersion` 证据。
2. 记录 D-4（R-20）未关闭契约命名、F-08（R-27）设备占位测试、F-07/R-16 组合根 source-map 门禁，以及 R-21/R-22 的 T-19 运行时验证项。
3. 不得把 ohosTest 编译、HAP 元数据或“无 Mock 字符串”探针写成设备/TLS 运行时 PASS。
4. T-19 在组合根出现后补跑 source map、F-08 修正、R2-02 的 control 负例与 API 14/15 设备矩阵。

---

## 7. 残余风险

| ID | 风险 | 级别 | 下一步/所有者 |
|---|---|---|---|
| R-03 | Path B 真机语义未证（SPKI 编码、skip 行为、错误码、TLS 1.2/1.3、p95） | High（阻断 P-TLS-PIN 可用性） | T-19/设备 runner；`tools/simulator --tls` + openssl 对齐。 |
| R-23 | 无设备/签名；ohosTest 全部 `BLOCKED` | High（证据） | 设备可用后执行；不得用编译代替。 |
| R-16/F-07 | Mock 在生产树；HAP 探针当前非区分性 | Medium | T-19/T-20 组合根 + source map 门禁。 |
| R-21 | `usingCache:false` 仅编译验证 | Medium | T-19 真实重复 discover/网络测试。 |
| R-22 | CP-01 运行时 API 14 未验证 | Medium | T-19 API 14/15 设备矩阵；CI 固定 SDK。 |
| R-20/D-4 | 错误码命名不一致 | Low/Medium（契约） | solution-architect 统一或正式记录接受。 |
| R-25 | `resetManualFailures` 尚无生产 UX 入口 | Low | T-19/T-15 接入显式重试/地址变更动作。 |
| R-27/F-08 | 设备占位测试可能误报通过 | Low | T-19/测试负责人删除或 Hypium skip。 |
| R-18/R-24 | 每请求新建 TLSSocket、无连接池；probe 超时不取消底层、mDNS listener 未移除、响应无大小上限 | Low | T-19 资源/p95/取消测试。 |
| R2-01 | C-10 → C-17 `ControlPolicy` 编译期耦合 | Low（架构） | solution-architect 确认或移动共享纯逻辑。 |
| R2-02 | P-TLS control 缺“无证据”负例 | Low（测试） | T-19/后续变更补测。 |

---

## 8. 独立声明与限制

- 本报告由 `agent:quality-reviewer` 独立出具；评审者未编写 T-11 产品代码、host 测试、Mock、修复报告或构建配置，未修改任何被审文件。
- 评审基于 `514671d` 快照与 §1.2 的 pin 输入；所有命令在仓库根执行，构建/测试输出只写入忽略目录与 `/tmp/opencode`。
- 未覆盖真实设备、真实 LAN、真实 mDNS/UDP、真实证书/TLS 运行时、API 14 设备安装；上述均为 `BLOCKED`/`UNAVAILABLE`，不是 PASS。
- 本报告不替代 CQG-T11、Integration Gate、Stage Gate 或用户验收；组件 `STABLE` 的最终状态由 Orchestrator 依据 CQG 记录决定。

---

## 9. Handoff

```text
STATUS: RETURNED_FOR_GATE / PASS_CODE_LEVEL
SUMMARY: 上轮 F-01（High）及 F-02/F-03/F-04/F-05/F-09/F-10/F-11/F-12 已关闭；F-06 构建配置层关闭（HAP minAPIVersion=50002014，运行时 UNVERIFIED）；F-07/F-08 已如实记录并转 T-19/T-20；D-4 命名仍开放（R-20，非代码阻断）。host 355/355、codelinter、clean assembleHap、ohosTest 附加编译均通过，无新阻断缺陷。
CLOSURE_TABLE: F-01 CLOSED; F-02 CLOSED(code)/T-19 runtime; F-03 CLOSED; F-04 CLOSED(behavior); F-05 CLOSED; F-06 CLOSED(build)/runtime UNVERIFIED; F-07 DEFERRED T-19/T-20; F-08 OPEN/DEFERRED T-19; F-09 CLOSED; F-10 CLOSED(code); F-11 CLOSED; F-12 CLOSED.
VERDICT: PASS（代码级，条件式）；建议 CQG-T11 以代码级 PASS 记录，C-17/C-18/C-20 可建议 STABLE（代码级，条件式）；不授予设备/PB-03/CP-01 runtime/Stage Gate。
EVIDENCE: reviewed revision 514671d; host 355/355 exit 0; codelinter No defects exit 0; clean assembleHap BUILD SUCCESSFUL exit 0; ohosTest assemble exit 0; HAP minAPIVersion=50002014 / pack.info compatible=14; input pins all match; snapshot refs/swe/snapshots/20261017T123254Z-wp-039-review-t11b-c37f13a2.
NEW_FINDINGS: R2-01 Low（C-10 → C-17 ControlPolicy 编译期耦合，建议架构确认/移动共享纯逻辑）；R2-02 Low（P-TLS control 缺“无 TLS 证据”负例）。均非阻断。
RISKS: R-03/R-23 设备与 PB-03 运行时 BLOCKED；R-16/F-07 组合根 source-map 门禁；R-21 usingCache 运行时；R-22 CP-01 运行时；R-20/D-4 契约命名；R-27/F-08 占位测试；R-18/R-24 资源/取消；R-25 reset UX。
NEXT_ACTION: Orchestrator 记录 CQG-T11 代码级 PASS 与上述条件/残余；T-19/T-20 执行设备矩阵、组合根 source-map、F-08 修正与 R2-02 补测；solution-architect 处理 D-4/R2-01。
```
