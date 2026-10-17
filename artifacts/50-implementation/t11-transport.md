# T-11 LAN 传输/发现/Mock（C-17/C-18/C-20）与 PB-03 TLS pin spike 实现报告

- **Artifact ID**: IMP-T11-TRANSPORT
- **Producer**: agent:implementation-engineer
- **Type**: Implementation / Verification Evidence
- **Status**: Proposed（本地构建/lint/host 测试完成；PB-03 运行时证据 BLOCKED；待独立评审与 CQG-T11）
- **Date**: 2026-10-17
- **Task**: T-11 / `wp-035-transport`（task 分支 `task/wp-035-transport`，父分支 `feat/yaocore-app`，base commit `4ae8af24`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`

> **Post-review correction（2026-10-17，`wp-037-fix-t11`）**：REVIEW-T11-001 的
> F-01/F-02/F-03/F-04/F-05/F-09/F-10/F-11/F-12 已修复；逐条处置、当前
> revision 的命令证据与测试计数见 `artifacts/50-implementation/t11-fix-report.md`。
> 本文件 §2.1 中“不重试验签/协议”的原始表述对非 2xx 响应**不成立**，修复后
> 的语义见该行修正与修复报告 F-01。本文件其余 §5 的 335 条证据对应原始
> revision `698883f`，未被改写；修复 revision 的 host 总数为 **355/355**。
- **上游契约**:
  - DES-001A §14（C-17）、§15（C-18）、§17（C-20）、§18（协议配方）、§19（PB-03）、§21（发现与 PB-01）、§22/§23（fake/host 边界）
  - ADR-002 §4/§6/§7；contract-baseline §3/§4/§8.6；project-constraints SC-11/SC-13/SC-15、PR-03/PR-06/PR-13、CP-01/CP-03
  - TEST-001（`artifacts/60-testing/test-plan.md`）§4.2/§5；D-019 host 测试架构
- **Downstream**: T-12（BLE 绑定探针复用 C-18/C-17）、T-15..T-18（VM/UI 使用 Mock/三态）、T-19（真实适配器装配/设备测试）、T-20（安全评审）、CQG-T11、IG-1
- **组件状态**: C-17 / C-18 / C-20 `UNVERIFIED`（本报告不授予 `STABLE`）

---

## 0. 摘要

| 项 | 结果 | 证据 |
|---|---|---|
| C-17 `LocalGatewayService` + policy + ports | **实现完成**（discover/control/probe/send；三档案；精确重传；ACK 链；DEV-ONLY） | `service/gateway/` 7 文件 |
| C-17 平台适配器 | **实现完成（COMPILED_ONLY）**：P-HMAC `@ohos.net.http`；P-TLS-PIN Path B `TLSSocket` + SPKI 校验 | `adapters/` 3 文件 |
| C-18 `GatewayDiscoveryService` | **实现完成**（LAST_KNOWN/mDNS hint/手动 IP/UDP seam；identity 严格一致；有限退避） | `GatewayDiscoveryService.ets` 等 |
| C-18 mDNS 适配器 | **实现完成（COMPILED_ONLY）**；服务类型/TXT 字段必须注入，无默认猜测 | `discovery/MdnsDiscoveryTransport.ets` |
| PB-01 raw UDP | **未实现（按契约 UNRESOLVED）**；`DiscoveryTransport` seam + warning | 本报告 §4 |
| C-20 Mock | **实现完成**（normal/offline/ack-lost/replay/timeout/dev-only + TLS 四模式；生产 import 排除检查） | `service/mock/` 3 文件 |
| **PB-03 结论** | **选 Path B（TLSSocket + 手动 SPKI-SHA256）**；API 14+ 表面可用，真机运行时证据 **BLOCKED**；Path A（http `certificatePinning` + `remoteValidation:'skip'`）因 API 18 下限与语义未证暂不使用 | §3 |
| Host 测试 | **PASS 335/335**（T-11 新增 60：C-17 21 + C-18 19 + C-20 17 + 边界 3） | `evidence/t11-host-node-tests.tap` |
| `ohpm install` | **PASS**（exit 0） | `evidence/t11-ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | **PASS**（BUILD SUCCESSFUL） | `evidence/t11-clean-assemble.log` |
| `codelinter -c code-linter.json5 -p default .` | **PASS**（No defects found） | `evidence/t11-codelinter.log` |
| `entry/src/test/run-host-tests.sh` | **PASS**（exit 0，335/335） | `evidence/t11-host-node-tests.tap` |
| ohosTest HAP 编译（附加） | **PASS（仅编译）** | `evidence/t11-ohosTest-assemble.log` |
| 生产 HAP Mock 排除探针（附加） | **PASS**：source map/`modules.abc` 无 Mock 路径 | `evidence/t11-mock-exclusion.log` |
| 设备/模拟器运行 | **BLOCKED**（无 `hdc` target、无签名、无模拟器镜像） | 本报告 §6 |

**结论**：C-17/C-18/C-20 的产品代码、host 测试与四条规定命令全部通过；PB-03 在 API 表面可行并已实现 Path B，但运行时/证书语义仍需设备验证，不能宣称 P-TLS-PIN 已真机可用。组件保持 `UNVERIFIED`。

---

## 1. 实现范围与文件

### 1.1 产品代码（15 文件）

```text
entry/src/main/ets/service/gateway/
├── GatewayTransportPorts.ets     # IGatewayClient/GatewayTarget/HttpTransport/TlsPinVerifier/
│                                 # TlsPolicy/HttpRequest/HttpResponse/ProbeResult/TlsVerification
├── GatewayRequestPolicy.ets      # GatewayRequestPolicy（300/900 重试、超时、allowCleartext）
│                                 # + ControlPolicy（设备/动作矩阵、值域、颜色归一化）
├── LocalGatewayService.ets       # C-17 编排：discover/control/probe/send；P-BLOCKED；DEV-ONLY；
│                                 # 精确重传；ACK 判定链；每网关互斥；PendingCommand TTL
├── DiscoveryModels.ets           # C-18 候选/选项/报告/Beacon/DiscoveryTransport seam
├── ManualAddressPolicy.ets       # 手动地址 LAN/端口校验 + 已绑定要求
├── ProbeBackoff.ets              # 绑定探针 500/1000/2000/4000/8000，总预算 30s
├── GatewayDiscoveryService.ets   # LAST_KNOWN/mDNS/手动/UDP 阶段；去重排序；identity 校验
├── adapters/
│   ├── OhosHttpTransport.ets     # COMPILED_ONLY：cleartext http + P-TLS-PIN Path B（同连接先验 pin 后发请求）
│   ├── SocketTlsPinVerifier.ets  # COMPILED_ONLY：独立 TLSSocket SPKI 校验
│   └── TlsPinCheck.ets           # COMPILED_ONLY：X509→SPKI DER→SHA-256→常数时间匹配
└── discovery/
    └── MdnsDiscoveryTransport.ets # COMPILED_ONLY：注入 serviceType/TXT 字段的 mDNS locator

entry/src/main/ets/service/mock/
├── MockScenario.ets              # MockMode/MockTlsMode/确定性 scenario 工厂
├── MockGatewayService.ets        # TEST ONLY：IGatewayClient + DeviceControlPort；生产 ACK 链
└── MockBleProvisioningClient.ets # TEST ONLY：扫描/配网阶段/取消/v2.0/v2.1

entry/src/main/ets/service/ble/
└── BleProvisioningPorts.ets      # T-11 最小 C-19 port 面（T-12 扩展）
```

> 端口位置说明：DES-A §3.7 名义上把端口放在 `contracts/**`；本任务写范围不含 `contracts/`，沿用 T-06/T-07/T-08 已登记的“端口贴近实现”位置例外。所有端口文件无 `@ohos`/`@kit` import。

### 1.2 Host 测试与证据（5 测试文件 + 6 证据）

```text
entry/src/test/host/
├── TransportFakes.ets            # clock/random/logger/metrics/route/credential/sequence/address/transport fakes
├── GatewayLocal.test.mjs         # C-17（21）
├── GatewayDiscovery.test.mjs     # C-18（19）
├── GatewayMock.test.mjs          # C-20（17）
└── TransportBoundary.test.mjs    # SC-11/D-04 生产边界（3）

entry/src/test/evidence/
├── t11-ohpm-install.log
├── t11-clean-assemble.log
├── t11-codelinter.log
├── t11-host-node-tests.tap
├── t11-ohosTest-assemble.log
└── t11-mock-exclusion.log
```

### 1.3 设备侧骨架（编译，BLOCKED）

```text
entry/src/ohosTest/ets/test/gateway/GatewayTransportDevice.test.ets
entry/src/ohosTest/ets/test/List.test.ets        # 注册 suite
entry/src/ohosTest/ets/test/README.md            # 目录说明
```

设备套件只验证真实 `@ohos.net.http`/`TLSSocket` 适配器可构造、非法 pin 前置拒绝、不可达 TLS 对端 fail-closed；真实仿真器 TLS pin-match 用例需设备 + 本机 `tools/simulator`，当前无法执行。

---

## 2. 契约对照

### 2.1 C-17 `LocalGatewayService`（DES-A §14/§18/§19.4）

| 契约条目 | 实现 | 证据 |
|---|---|---|
| `IGatewayClient.discover/control/probe` | 全部实现；实现 `DeviceControlPort.send` | `LocalGatewayService.ets` |
| `GatewayTarget` 持久 profile 仅 P-HMAC/P-TLS-PIN | 构造校验；P-BLOCKED 操作时 `GATEWAY_PROFILE_BLOCKED` | `GatewayTransportPorts.ets`、`resolveRuntimeProfile` |
| P-HMAC | `http://` + HMAC；`allowCleartext=false` 拒绝（仅测试/高安全模式） | C17_cleartextDisabled |
| P-TLS-PIN | `https://` + `TlsPolicy` + HMAC；pins 1..4、64 位小写 hex、`sha256-spki-der` | C17_tlsProbe/pinMismatch |
| P-TLS-PIN 失败不回退明文 | 任何 `TLS_*` 直接抛出；transport 只收到 https URL；无二次明文请求 | C17_tlsPinMismatchNeverFallsBackToCleartext |
| discover 流水线 | 签名→GET→DEV-ONLY→验签→`DiscoverMapper`→metrics/skew | C17_discover_pipeline |
| control 流水线 | seq→签名→`ControlRequestSerializer`→发送/重传→DEV-ONLY→验签→`ControlAckMapper` | C17_control_success |
| ACK 判定链 | 签名/correlation/`result_code`/`reported_state`/目标/动作由 C-05+C-03 执行；非零不抛异常 | C17_control_doesNotRetrySignedGatewayError |
| 精确重传 | 同 `request_id/seq/timestamp/nonce/sign/body`；失败后不重新签名 | C17_control_retriesExactBytesOnTimeout |
| 重试策略 | `maxAttempts=3`，延迟 300/900ms；仅网络/超时/完全无 ACK 认证材料的 5xx；带认证材料的非 2xx 响应验签/协议失败**原样抛出、不重试**（F-01）；4xx 不重试；TLS/DEV-ONLY 不重试 | C17_control_exhaustsThreeAttempts*、C17_control_http500With* |
| 可观测性 | 成功路径记录 `lan.control.transport.ms` 与 `lan.control.commit.ms`；TLS pin/handshake/profile 失败记录 gatewayId/profile/errorCode/time 安全事件（F-05 修复） | C17 指标/日志断言 |
| 幂等 | `idempotent_replay` 原样映射；已应用状态不重复应用由 `AckExpectation.alreadyApplied` 支持 | C17/C20 重放用例 |
| DEV-ONLY | `X-YaoCore-Simulator` 大小写不敏感拒绝 `DEV-ONLY`/`DEV_SIMULATOR_ONLY`，先于验签/解析 | C17_devOnlyResponse |
| 错误分类 | `GATEWAY_UNREACHABLE/TIMEOUT`、`HTTP_<status>`、`TLS_*`、`ACK_*`、`GATEWAY_NOT_BOUND`；不复用网关数值空间 | §5 负例 |
| 并发 | 每网关异步互斥，不同网关可并行 | `GatewayMutex` |
| 秘密生命周期 | 只在 `withCommandSecret` 回调内持有；日志只含 gatewayId/requestId/code | 代码审查 + fakes 清零 |

### 2.2 C-18 `GatewayDiscoveryService`（DES-A §15/§21）

| 契约条目 | 实现 | 证据 |
|---|---|---|
| LAST_KNOWN | 按 route 的 `lastKnownIp`/`localIp` 独立 probe；失败不阻断其他 route | C18_lastKnown_* |
| identity 唯一 | `probe.gatewayId === route.gatewayId` 且 runtime profile 一致才 `verified=true` | C18_identityMismatch/profileMismatch |
| mDNS | 仅 hint 精确匹配已绑定 route 才 probe；无 hint / 未知 hint 只返回未验证 locator | C18_mdns_* |
| 手动 IP | `ManualAddressPolicy.validate`（IPv4、非 loopback/链路本地/组播/广播/0.0.0.0、端口）；必须已绑定；成功才更新地址 | C18_manual_* |
| 手动限频/失败预算 | 同 gateway ≥2s；连续 5 次失败后拒绝继续自动探测 | C18_manual_rateLimit |
| UDP/PB-01 | `includeUdp=true` 且未注入 → `DISCOVERY_TRANSPORT_UNAVAILABLE`；注入 fake 仅 locator，永不 verified；不实现 raw UDP adapter | C18_udp_* |
| 去重/排序 | 键 `(gatewayId|hint, ip, port)`；verified 优先；latency 升序 | C18_candidates_deduped |
| 取消 | 阶段边界 `throwIfCancelled`；mDNS scan 取消后不再继续 | C18_cancellation |
| 退避 | 500/1000/2000/4000/8000，总预算 30s | C18_probeBackoff |
| 不得建绑定 | 服务/适配器无 route 创建路径；测试断言 route 数不变 | C18_mdns_withoutHint |

### 2.3 C-20 Mock（DES-A §17）

| 场景 | 行为 | 测试 |
|---|---|---|
| `normal` | 4 设备快照；控制经**真实** `CanonicalBuilder` + `ResponseVerifier` + `ControlAckMapper` | C20_normal_* |
| `offline` | `GATEWAY_UNREACHABLE` | C20_offline |
| `ack-lost` | 首次 `GATEWAY_TIMEOUT`；同命令重试返回**首次生成的同一 ACK**（同 `request_id`/`seq`，不再生成新身份；F-12 修复） | C20_ackLost |
| `replay` | 同命令重放；同目标异内容返回签名 `1005`，`ackAccepted=false` | C20_replay |
| `timeout` | 注入 delay 后 `GATEWAY_TIMEOUT`（无真实 sleep） | C20_timeout |
| `dev-only` | 以 `I GatewayClient` 视角抛出生产拒收码 `DEV_SIMULATOR_REJECTED` | C20_devOnly |
| `pin-match` | P-TLS-PIN probe 返回匹配 pin | C20_tlsPinMatch |
| `pin-mismatch`/`handshake-fail` | `TLS_PIN_MISMATCH`/`TLS_HANDSHAKE_FAILED`；目标 P-HMAC 不受影响 | C20_tls* |
| `resultCode=1004` | 签名 ACK 但 `ackAccepted=false`，不抛异常 | C20_resultCode |
| `omitReportedState` | `ACK_PROTOCOL_VIOLATION` | C20_omitReportedState |
| `badSignature`/`badCorrelation` | `CONTROL_RESPONSE_AUTH_FAILED`/`ACK_CORRELATION_MISMATCH` | C20_bad* |
| 确定性 | 固定 clock/random/seed → 相同设备值/gatewayName/generatedAt | C20_normal_deterministic |
| 生产排除 | `service/mock/**` 带 TEST ONLY 注释；host 扫描生产树零 import；HAP source map/abc 无 Mock | `TransportBoundary.test.mjs`、`t11-mock-exclusion.log` |
| MockBLE | 1 设备扫描、阶段序列、v2.0/v2.1+TLS、离线/超时/取消 | C20_mockBle_* |

> Mock 的 `dev-only` 通过 `IGatewayClient` 接口无法暴露原始响应头，因此返回生产拒收结果；原始 header 拒收路径由 C-17 + `FakeHttpTransport` 单独覆盖（`C17_devOnlyResponseRejectedBeforeVerification`）。

---

## 3. PB-03 TLS pin spike（必做结论）

### 3.1 本地 SDK 证据（已实际读取）

SDK：`/home/quirkybrain/harmonyos/command-line-tools/sdk/default/openharmony`，`oh-uni-package.json` 为 **API 26.0.0**。

| 事实 | 文件/行（本地 SDK） | `@since` | 对本项目（API 14+）的影响 |
|---|---|---|---|
| `HttpRequestOptions.certificatePinning` | `@ohos.net.http.d.ts` L344 | 12 | 可用，但只解决 pin，不解决自签名 CA |
| `CertificatePinning.publicKeyHash` / `hashAlgorithm:'SHA-256'` | 同上 L1284-1294 | 12 | SDK **未文档化** hash 编码（hex/base64）；DES-A §19.1 证据指向 netstack 拼 `sha256//<base64>` |
| `HttpRequestOptions.remoteValidation` | 同上 L353 | 18 | API 14-17 **不可用**，无法作为唯一路径 |
| `RemoteValidation = 'system' \| 'skip' \| ValidationCallback` | 同上 L617 | 18（callback 26） | `skip`+pin 的强制语义需设备实证 |
| `TLSSocket.connect({skipRemoteValidation})` | `@ohos.net.socket.d.ts` L2969 | 12 | **API 14+ 可用** |
| `TLSSocket.getRemoteCertificate(): Promise<X509CertRawData>` | 同上 L2588 | 9 | 可用；`X509CertRawData` 携带 `data` + `encodingFormat` |
| `TLSSocket.getProtocol()` | 同上 L2616 | 9 | 可记录 TLSv1.2/1.3 |
| `TLSConnectOptions.timeout` | 同上（L2979 附近） | **22** | **禁止使用**（API 14 不兼容）；本实现改用 `setTimeout` + `close()` |
| `X509Cert.getPublicKey(): cryptoFramework.PubKey` | `@ohos.security.cert.d.ts` L686 | 9 | 可用 |
| `X509Cert.getEncoded(): Promise<EncodingBlob>` | 同上 L673 | 9 | 可用（证书 DER） |
| `EncodingFormat.FORMAT_DER` | 同上 L358 | 9 | 可用 |
| `PubKey.getEncoded(): DataBlob`，文档要求 “ASN.1 / X.509 / DER” | `@ohos.security.cryptoFramework.d.ts` L585 | 9 | **SPKI DER 假设的来源**；需设备与 `openssl x509 -pubkey` 对齐 |
| TLSv1.2/TLSv1.3 枚举 | `@ohos.net.socket.d.ts` L2995-3011 | 9 | 可强制 ≥TLS1.2 |

> 本任务未使用 `TLSConnectOptions.timeout`（API 22）；连接超时由纯逻辑 timer + `close()` 实现，保持 CP-01 API 14 基线。

### 3.2 候选路径对照（DES-A §19.2）

| 路径 | API 14 可用 | 结论 |
|---|---|---|
| **A. `@ohos.net.http` + `certificatePinning` + `remoteValidation:'skip'`** | **否**（`remoteValidation` 需 18） | 不作为 v1 主路径；API 18+ 快速路径待设备验证 |
| **B. `TLSSocket` + `skipRemoteValidation` + 手动 SPKI-SHA256** | **是**（skip 12 / cert 9 / getRemoteCertificate 9） | **选定** |
| C. `caData`（证书 PEM）+ pin | 否（`caData` 需 20） | 不可用；且 v2.1 身份只给 pin 不给证书 |
| D. NAPI 自定义 libcurl/OpenSSL | 是 | 超出 ArkTS App 仓库边界，否决 |
| E. 跳过校验 | — | **禁止**（SC-15；ADR-002 §6.2-4） |

### 3.3 选择与实现

**v1 主路径：Path B。** 理由：

1. 满足 API 14 基线；Path A 的 `remoteValidation` 在 18 才可用，无法覆盖 14-17。
2. 校验发生在**发送任何 HTTP 字节之前**：`connect(skipRemoteValidation)` → `getRemoteCertificate()` → `createX509Cert()` → `getPublicKey().getEncoded()` → SHA-256 → 常数时间匹配 pin → 成功后才 `send()`。pin 失败立即 `close()`，不泄露请求内容。
3. 与基线 `sha256-spki-der`（64 位小写 hex）语义一致；Path A 的 `publicKeyHash` 需要 hex→base64 转换且编码未在 SDK 文档化。
4. 两个适配器均通过 `HttpTransport`/`TlsPinVerifier` 端口隔离，C-17 不感知实现；未来 Path A 可在设备验证后按 `sdkApiVersion` 选择。

实现细节：

- `OhosHttpTransport.send`：P-HMAC 走 `@ohos.net.http`；P-TLS-PIN 走 Path B 最小 HTTP/1.1（`Connection: close`、Content-Length/chunked、status/header 解析、读超时）。
- `SocketTlsPinVerifier`：独立诊断/探针用途，同源 SPKI 校验。
- `TlsPinCheck`：`X509CertRawData.encodingFormat` 原样传入 `createX509Cert`；`PubKey.getEncoded().data` 即 SPKI DER；SHA-256 后用 `CryptoPort.constantTimeEqual` 比较。
- 失败语义：pin 不匹配 → `TLS_PIN_MISMATCH`；握手/证书解析/SSL → `TLS_HANDSHAKE_FAILED`；连接超时 → `GATEWAY_TIMEOUT`；不可达 → `GATEWAY_UNREACHABLE`。**任何 `TLS_*` 都不回退 http**。

### 3.4 PB-03 问题清单状态（DES-A §19.5）

| # | 问题 | 状态 |
|---|---|---|
| 1 | `publicKeyHash` 编码（hex vs base64） | **未实证**（无设备）；SDK 未文档化；Path A 未采用 |
| 2 | `remoteValidation:'skip'` + pin 是否仍强制 pin | **未实证**；Path A 未采用 |
| 3 | `getRemoteCertificate` 编码 / `PubKey.getEncoded` 是否 SPKI DER | **API 文档支持 SPKI DER**；设备与 `openssl x509 -pubkey` 对齐待做 |
| 4 | API 14/15/16/17/18+ 可用性 | 已按 SDK `@since` 给出；Path B 覆盖 14+；Path A 仅 18+ |
| 5 | 自签名 + `skipRemoteValidation:true` 握手；TLS 1.2/1.3 | **未实证**；设备项 `UNAVAILABLE` |
| 6 | 每请求新建连接 vs 复用对 p95 的影响 | **未测量**；当前每请求新建 TLSSocket，连接池延后 T-19 |
| 7 | pin mismatch/handshake fail 是否可区分 | 本实现按 AppError 区分；真实平台错误码映射待设备确认 |

### 3.5 若真机证明不可行

- 不降级跳过校验；P-TLS-PIN 网关保持 **P-BLOCKED**，LAN 不可用。
- 按 DES-A §19.5 停止 P-TLS-PIN 扩展，升级 solution-architect 重评 ADR-002 §6（延期/固件/其他机制），登记 R-03 残余风险。
- 当前无证据要求触发该升级：Path B 在本地 SDK API 表面完整可用，阻塞点是**设备运行环境**，不是 API 缺失。

---

## 4. PB-01 处置

- `DiscoveryTransport` 只返回“locator”（`DiscoveryBeacon`），不定义 UDP 报文、mDNS 服务类型/TXT。
- **未实现 raw UDP adapter**；`includeUdp=true` 且未注入时仅产生 `DISCOVERY_TRANSPORT_UNAVAILABLE` warning，不阻断其他阶段。
- mDNS 适配器不提供默认服务类型、不提供默认 TXT 字段；`serviceType` 由构造参数强制注入，`hintAttribute` 可选。未配置时生产组合根不应装配。
- UDP/mDNS Beacon 永远不会单独使候选 `verified`；验证只来自签名 discover + identity 严格一致。
- PB-01 关闭后新增 `UdpDiscoveryTransport` 即可复用 C-18，无需改本服务。

---

## 5. 测试清单与命令输出

### 5.1 命令（实际执行，cwd 仓库根）

```bash
ohpm install
hvigorw clean assembleHap --no-daemon
codelinter -c code-linter.json5 -p default .
entry/src/test/run-host-tests.sh
# 附加
hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon
```

| 命令 | 结果 | 证据 |
|---|---|---|
| `ohpm install` | exit 0 | `t11-ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | exit 0，BUILD SUCCESSFUL | `t11-clean-assemble.log` |
| `codelinter ...` | exit 0，No defects found | `t11-codelinter.log` |
| `run-host-tests.sh` | exit 0，tests 335 / pass 335 / fail 0 | `t11-host-node-tests.tap` |
| ohosTest assemble | exit 0，BUILD SUCCESSFUL（仅编译） | `t11-ohosTest-assemble.log` |

### 5.2 测试计数

| 层 | 数量 | 说明 |
|---|---|---|
| Host 总 | **335** | T-11 新增 60；T-10 基线 275 |
| C-17 host | 21 | discover/control/ACK/重试/TLS/DEV-ONLY/policy |
| C-18 host | 19 | LAST_KNOWN/mDNS/手动/UDP/去重/超时/取消/退避 |
| C-20 host | 17 | 行为矩阵/TLS 四模式/MockBLE |
| 边界 | 3 | 生产 Mock 排除、TEST ONLY、纯逻辑无平台 import |
| 设备骨架 | 4 `it()` | **COMPILED_ONLY / BLOCKED**，未执行 |

### 5.3 关键 host 断言

- 精确重传：两次 `HttpRequest.body` 字节完全一致，nonce/seq 不变（`C17_control_retriesExactBytesOnTimeout`）。
- 3 次尝试与 300/900ms 退避（`C17_control_exhaustsThreeAttemptsOnTransportFailure`）。
- P-BLOCKED / 缺失 pins → 0 次 transport 调用。
- TLS pin mismatch：1 次请求、https URL、无明文回退。
- DEV-ONLY：先于验签拒绝，garbage body 不解析。
- 签名/correlation 失败：1 次尝试、不重试。
- 非零 `result_code`：不抛异常、`ackAccepted=false`。
- 缺 `reported_state` → `ACK_PROTOCOL_VIOLATION`；目标不一致 → `ACK_STATE_MISMATCH`。
- C-18：mDNS 无 hint 仅 locator；identity/profile 不一致绝不 verified；手动 IP 成功才写地址。
- C-20：真实 `CanonicalBuilder`/`ResponseVerifier`/`ControlAckMapper` 链路；ack-lost 重放 `shouldApplyState=false`。

---

## 6. 设备/环境限制

| 项 | 状态 | 说明 |
|---|---|---|
| 真机/模拟器 | **BLOCKED** | `hdc list targets` 为空；无签名 `signingConfigs` |
| `onDeviceTest` | **BLOCKED** | 无设备；不得写成 PASS |
| 真实 TLS 握手/SPKI | **BLOCKED** | `SocketTlsPinVerifier`/`OhosHttpTransport` 为 COMPILED_ONLY |
| Path A `certificatePinning` 语义 | **UNAVAILABLE** | 无设备/无 API 18 运行环境 |
| mDNS 真实发现 | **BLOCKED** | 需设备 + 注入服务类型；PB-01 未关闭 |
| 真实网关 LAN RTT/p95 | **UNAVAILABLE** | 无真实网关；仅 Python 仿真器已有工具层证据（T-05） |

设备侧套件已注册进 `List.test.ets`；注册只表示设备可用时会执行，当前仍为 `BLOCKED_ON_DEVICE_RUNNER`。

---

## 7. 偏离项与契约注释（需评审确认）

| # | 项 | 处理 | 理由 |
|---|---|---|---|
| D-1 | 端口位置 | `GatewayTransportPorts.ets` 在 `service/gateway/`，非 `contracts/**` | T-11 写范围不含 `contracts/`；沿用已登记位置例外 |
| D-2 | `LocalGatewayService` 构造器 | 在 §14.1.2 参数外增加 `routes`、`addresses`、可选 `delay` | §14.6 要求 `GatewayRoutePort`；`send()` 需要路由；`delay` 为 host 确定性重试 seam |
| D-3 | `HttpResponse.tlsVerification` | 新增可选字段 | `probe().tlsPinMatched` 只能由 transport 在 pin 校验后提供；避免二次连接 |
| D-4 | C-05 错误码传播 | header 验签/correlation 失败抛 `RESPONSE_AUTH_FAILED`/`RESPONSE_CORRELATION_MISMATCH`（§18.7 + TEST-001 SEC-N07/N08）；`CONTROL_RESPONSE_AUTH_FAILED`/`ACK_CORRELATION_MISMATCH` 用于 C-20 mock 与 C-03 体内 correlation | DES-A §14.4 与 §18.7/测试计划命名不一致；当前选择与 §18.7 + TEST-001 一致，建议架构评审统一 |
| D-5 | `ControlPolicy.validate` 签名 | 保持 §14.2.3 `(deviceType, isSupported, action, value)`；C-17 直接调用传 `undefined/true`，只执行动作/值域规则；**C-10 `DeviceCommandRunner` 在 `port.send` 前用持久 `deviceType` 调用 `ControlPolicy`**（F-04 修复），设备类型矩阵不再依赖未兑现的预检假设 | `GatewayTarget` 无 deviceType；C-17 直接调用方无法提供类型；矩阵由 C-10 强制执行 |
| D-6 | Mock `dev-only` | 以 `IGatewayClient` 返回 `DEV_SIMULATOR_REJECTED`，不伪造 header | `IGatewayClient` 无 header 通道；原始 header 拒收由 C-17 host 测试覆盖 |
| D-7 | Mock 位置 | `entry/src/main/ets/service/mock/**`（§17 允许的 fallback） | 供 host/T-15+ 共享；生产 import 零命中 + HAP 探针；T-19/T-20 仍需 source-map 正式检查 |
| D-8 | `MockGatewayService` 构造器 | 增加 `crypto` 与可选 `delay` | 用真实 ACK 链生成/验签；host 无 sleep |
| D-9 | `MockBleProvisioningClient` port | 新增 `service/ble/BleProvisioningPorts.ets` 最小面 | T-12 拥有 C-19，可扩展；T-11 仅需 Mock 接口 |
| D-10 | `GatewayRequestPolicy.retryDelayMs` | 300/900ms（×3 上限），非纯指数 | §14.3 明确 300ms、900ms |
| D-11 | mDNS 适配器 | 必须注入 `serviceType`；`hintAttribute` 可选；无默认值 | PB-01 未决，禁止猜测协议 |
| D-12 | 连接超时 | 不使用 `TLSConnectOptions.timeout`（@since 22） | 保持 API 14 兼容；`setTimeout` + `close()` |

---

## 8. Traceability

| 需求/约束 | 实现/证据 |
|---|---|
| FR-DEV-001/002、FR-GW-003 | C-17 discover/control/probe；C-18 候选 |
| SC-11 | DEV-ONLY 拒收；Mock 生产边界；HAP 探针 |
| SC-13/SC-14/SC-15 | 验签/correlation/`result_code`/`reported_state`；无乐观成功；常数时间 pin/HMAC |
| NFR-4.1 | HMAC 必做 + 条件 TLS pin |
| ADR-002 §4/§6/§7 | SPKI pin 格式、三档案、P-BLOCKED、TLS Mock 四模式 |
| ADR-004 §5.2 / PR-06 | 手动 IP 仅已绑定；locator ≠ identity |
| PR-03 / §14.3 | 精确重传、300/900、TTL |
| PR-13 | 绑定探针有限退避 |
| PB-01 | `DiscoveryTransport` seam；无 raw UDP |
| PB-03 | Path B 实现 + 设备验证清单 |
| D-019 | host fakes + `run-host-tests.sh` |
| TEST-001 SEC-N07..N10/N13/N15..N17/N25 | C-17/C-20 host 覆盖；N15/N16 运行时仍 BLOCKED |

---

## 9. 风险与后续

| ID | 风险 | 影响 | 下一步 |
|---|---|---|---|
| R-03（残余） | Path B 真机语义未证：`getEncoded()` 是否严格 SPKI DER、自签名 + `skipRemoteValidation` 行为、错误码区分 | P-TLS-PIN 可能无法在真机启用 | T-19/设备 runner：对 `tools/simulator --tls` 做 pin-match/mismatch/handshake-fail；用 `openssl x509 -pubkey` 对齐 |
| R-17 | Path A `publicKeyHash` 编码/`skip`+pin 语义未证 | 无法作为 API 18+ 快速路径 | 设备 spike；若确认可改用 A 降低代码量 |
| R-16 | Mock 源文件位于 `main` 树，虽未被引用且 HAP 已排除，但后续组合根可能误 import | SC-11 回归 | `TransportBoundary.test.mjs` + T-19/T-20 source-map 门禁 |
| R-18 | 每请求新建 TLSSocket，无连接池 | p95 可能受握手影响 | T-19 性能测量；必要时加受 pin 保护的连接复用 |
| R-19 | PB-01 未决，mDNS 生产不可用 | 发现仅 LAST_KNOWN/手动 | 架构关闭 PB-01 后注入 adapter |
| R-20 | §14.4 与 §18.7/测试计划错误码命名不一致 | 评审/互操作歧义 | 本报告 D-4 登记，建议架构统一 |

**组件状态**：C-17/C-18/C-20 = `UNVERIFIED`。
**下一动作**：独立 `quality-reviewer` 评审（契约/安全/并发/错误码）；设备可用后执行 `GatewayTransportDevice.test.ets` 与 PB-03 运行时清单；T-19 装配组合根并复核 Mock 排除。

---

*T-11 实现报告结束。*
