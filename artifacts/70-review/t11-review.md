# T-11 独立评审报告：C-17 LAN 传输 / C-18 发现 / C-20 Mock / PB-03 TLS spike

- **Artifact ID**: REV-T11-001
- **Producer**: agent:quality-reviewer
- **Type**: Review Report / Handoff
- **Status**: CHANGES_REQUIRED
- **Date**: 2026-10-17
- **Task**: `wp-036-review-t11`（task 分支 `task/wp-035-transport`，父分支 `feat/yaocore-app`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`
- **Reviewed revision**: `698883f7b8b57808750d51311cc0c1302a66bacb`（HEAD；31 路径；base/parent 见 handoff）
- **Review mode**: 独立 Code Review（Quick/Code/Architecture/Security/Integration 的组合；以安全与契约为主）
- **Independence**: 评审者未参与 T-11 实现；本次只读代码与证据，唯一写入为本报告。未修改任何被审代码。

---

## 1. 范围、输入与复验

### 1.1 评审目标

```text
entry/src/main/ets/service/            # C-17/C-18/C-20 产品代码、端口、适配器
entry/src/test/                        # host fakes、60 条新增测试、证据日志
entry/src/ohosTest/ets/test/           # 设备侧骨架（BLOCKED）
artifacts/50-implementation/t11-transport.md
```

### 1.2 权威依据（pin 输入均校验一致）

| 输入 | SHA-256（pin） | 结果 |
|---|---|---|
| `artifacts/50-implementation/t11-transport.md` | `d1f3f86199fd` | 一致 |
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `5599e693fafe` | 一致 |
| `artifacts/20-architecture/adr-002-lan-security-channel.md` | `67943a6e1d8d` | 一致 |
| `artifacts/20-architecture/contract-baseline.md` | `6673a990d502` | 一致 |
| `artifacts/20-architecture/project-constraints.md` | `283046210e68` | 一致 |
| `artifacts/60-testing/test-plan.md` | `33485cc39abd` | 一致 |

依据章节：DES-001A §14/§15/§17/§18/§19/§21；ADR-002 §4/§6/§7；contract-baseline §2/§3/§4/§8.6；project-constraints CP-01/CP-03、SC-11/SC-13/SC-15、PR-03/PR-06/PR-13；TEST-001 §4.2/§5/§7；D-019。

### 1.3 复验命令（本评审实际执行，cwd = 仓库根）

| 命令 | 结果 | 备注 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS：335/335，fail 0，exit 0** | 与提交内 `t11-host-node-tests.tap` 一致；T-11 新增 60 条全部出现 |
| `codelinter -c code-linter.json5 -p default .` | **PASS：No defects found，exit 0** | 只覆盖产品源码；`entry/src/test/**`、`entry/src/ohosTest/**` 不在其范围（README §1-5） |
| `hvigorw clean assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0** | 35 tasks（34 executed）；未签名，符合当前环境 |
| Mock 生产排除独立探针 | **PASS（无 Mock 字符串）** | 见 §1.4；注意证据的非区分性问题 F-07 |
| `git diff HEAD~1..HEAD` 范围 | **31 路径均在 handoff 范围** | 无构建产物/秘密入库 |
| 输入 pin 复核 | **全部一致** | `swe_guard check` 输出见运行记录 |

### 1.4 独立 Mock/HAP 探针结果与限制

对 `entry/build/default/outputs/default/entry-default-unsigned.hap` 解包后检查：

- `ets/sourceMaps.map`：无 `service/mock`、`MockGatewayService`、`MockBleProvisioningClient`、`MockScenario` 字符串；
- `ets/modules.abc`：无上述字符串；
- **同时也没有 `service/gateway` 产品代码**：当前没有生产组合根（T-19）导入 C-17/C-18，因此 ArkTS 构建把整块未引用代码裁掉。该探针只能证明“当前 HAP 不含 Mock”，不能证明“组合根不会装配 Mock”；真正有区分力的证据是 `TransportBoundary.test.mjs` 的静态 import 扫描。T-19/T-20 必须在组合根出现后重跑 source map 检查（F-07）。

### 1.5 证据一致性结论

- 实现报告 §0/§5 的 host 335/335、codelinter、clean assemble、ohosTest 编译声明与提交证据一致；
- `t11-transport.md` 对 PB-03 运行时证据、设备 `BLOCKED`、无签名、无 `hdc` target 的陈述**基本如实**，未把编译通过写成设备通过；
- 发现 1 处表述过强、1 处证据非区分性、1 处 API 14 构建基线不一致（见 F-01/F-06/F-07）。

---

## 2. Findings（按严重度排序）

> 严重度定义：**High** = 必须在 CQG/集成前修复或由架构明确裁定；**Medium** = 应修复或需有记录的接受决定；**Low** = 改进建议/测试诚实性/证据精度。F-06 是 T-11 之前已存在的基线问题，单独标注“上游”。

| ID | 严重度 | 位置 | 契约/依据 | 问题与证据 | 建议 |
|---|---|---|---|---|---|
| **F-01** | **High / Blocking** | `entry/src/main/ets/service/gateway/LocalGatewayService.ets:319-331`（`classifyControlResponse` catch）、`:290-296`（HTTP_* 重试） | DES-A §14.3“响应验签失败不自动重试”“ACK_CORRELATION_MISMATCH/ACK_PROTOCOL_VIOLATION 不重试”；§18.9“无法验签/解析/correlation → 不重试”；实现报告 §2.1 声明 | 非 2xx 响应进入 `classifyControlResponse` 后，`mapControlAck` 的**任何**异常（`RESPONSE_AUTH_FAILED`、`RESPONSE_CORRELATION_MISMATCH`、`ACK_PROTOCOL_VIOLATION`、`ACK_STATE_MISMATCH`、`ACK_CORRELATION_MISMATCH`）都被 `catch { return undefined; }` 吞掉；`sendWithRetry` 随后把它当成 `HTTP_<status>`，对 5xx 执行最多 3 次重传。现有测试 `C17_control_retriesHttp500WithoutSignedAck` 只覆盖“500 + 空 header”，没有覆盖“500 + 已存在但坏的签名/correlation”。代码注释明确写着“cannot be verified is just an HTTP failure, retryable for 5xx”，与 §14.3/§18.9 冲突。 | 非 2xx 分支先判断是否存在 ACK 认证材料：若 `Response-Alg/Key-Id/Correlation/Sign` 任一存在或 body 可解析为 ACK，则让验签/协议异常原样抛出、不重试；只有“完全没有认证材料”的 HTTP 错误才归 `HTTP_<status>` 并按 5xx 规则重试。补充 500+bad sign（1 次请求、`RESPONSE_AUTH_FAILED`）、500+bad correlation、500+signed malformed ACK（`ACK_PROTOCOL_VIOLATION`）、500+empty header（3 次）和 4xx+bad sign 的 host 负例。 |
| **F-02** | **Medium** | `entry/src/main/ets/service/gateway/adapters/OhosHttpTransport.ets:112-127` | DES-A §14.2.1/§18.2（每次 discover 新 challenge/nonce，响应必须对应当前 challenge）；PR-03/SC-13 | 明文适配器创建 `HttpRequestOptions` 时没有设置 `usingCache:false`。OpenHarmony SDK `@ohos.net.http.d.ts` 明确 `usingCache` 默认 **true**（L136-146）。`GET /discover` 使用固定 URL，响应没有 cache-control；一旦命中 HTTP 缓存，调用方会收到旧 challenge 的响应，HMAC/correlation 校验必然失败，表现为间歇性“验签失败/发现失败”。不会伪造成功（fail-closed），但会破坏 P-HMAC 基线的发现可靠性。 | 对所有签名 GET（至少 `/discover`）设置 `usingCache:false`；评估是否需要禁用/限制 redirect/proxy（当前未设置）；增加重复 discover 的适配器/设备检查项，并在 T-19 真实网络测试中覆盖。 |
| **F-03** | **Medium（纵深防御）** | `entry/src/main/ets/service/gateway/LocalGatewayService.ets:173-179`；`GatewayDiscoveryService.ets:222-232` | DES-A §14.1.3（`HttpTransport` 必须在返回前完成 pin 校验）、§14.2.4（P-TLS-PIN 时 `tlsPinMatched` 为匹配 pin）、§15.2（verified 条件） | `probe()` 对 P-TLS-PIN 目标只返回 `execution.tlsVerification?.matchedPin`；若 transport（未来 Path A 适配器/其他实现/测试 fake）返回响应但没有 `TlsVerification`，仍然得到 `reachable=true`、`profile=P_TLS_PIN`、`tlsPinMatched=undefined`。C-18 `probeRoute` 只比较 `probe.profile`，不要求 pin 证据。当前 `OhosHttpTransport` 总是提供证据，因此未观察到实际绕过；但服务层没有独立 fail-closed 检查。 | 对 P-TLS-PIN：若 `response.tlsVerification` 缺失、`matchedPin` 不在 `target.pins` 中，或 `peerSpkiSha256Hex` 与匹配 pin 不一致，抛出 `TLS_VERIFIER_UNAVAILABLE`/`TLS_HANDSHAKE_FAILED`；C-18 的 P-TLS-PIN verified 候选同时要求 `tlsPinMatched` 属于 route pins。增加“P-TLS fake 返回无 TlsVerification → 不 verified/抛错”的 host 测试。 |
| **F-04** | **Medium（契约/消费者）** | `LocalGatewayService.ets:186`（`ControlPolicy.validate(undefined, true, ...)`）；`GatewayRequestPolicy.ets:75-97`；`service/device/DeviceCommandRunner.ets` | DES-A §14.2.2/§14.2.3；D-5 | C-17 始终传 `deviceType=undefined`，只执行动作/值域规则。实现报告 D-5 声称“设备类型矩阵由 C-10/C-11 预检调用”，但 C-10 `DeviceCommandRunner` 只检查存在性/启用/isSupported，不调用 `ControlPolicy`，也不做 action↔deviceType 矩阵；C-11 `SceneValidation` 有矩阵，但只覆盖场景路径。直接 C-10 命令（如 door + `SET_BRIGHTNESS`）可到达 `send()`。网关大概率拒绝（不会虚假成功），但违反 §14.2.3“其他组合 → CONFIGURATION_ERROR”的本地预检意图，并产生无效流量。 | 由 C-10 在 `port.send` 前调用 `ControlPolicy.validate(record.snapshot.deviceType, record.isSupported, command.action, command.value)`；或给 C-17 `GatewayTarget` 增加受控的 deviceType/支持标志。D-5 必须由 solution-architect 明确接受并更新契约/报告，不能以“C-10 已预检”为前提。 |
| **F-05** | **Medium** | `LocalGatewayService.ets:282-311`；全文件无 TLS 安全事件 logger 调用 | DES-A §14.5“pin mismatch/handshake fail 记录 gatewayId/profile/errorCode/时间”；§14.2.2 成功路径要求 `lan.control.transport.ms` | 实现只在重试耗尽时 `logger.warn('control_exhausted')`。`TLS_PIN_MISMATCH`、`TLS_HANDSHAKE_FAILED`、`TLS_PROFILE_INCONSISTENT` 抛出前没有安全事件日志；成功路径只记录 `lan.control.commit.ms`，没有 `lan.control.transport.ms`。`resolveRuntimeProfile` 的 P-BLOCKED 也没有记录。 | 增加不含秘密的安全事件日志（gatewayId/profile/errorCode/time）；记录 `lan.control.transport.ms`（单次 transport 耗时）与 commit 时间；在 host fake logger/metrics 中断言。 |
| **F-06** | **High（上游/基线，非 T-11 引入）** | `build-profile.json5:9`（`compatibleSdkVersion: "26.0.0"`）；`t11-transport.md:191,207`；`project-constraints.md:116` | CP-01“兼容 HarmonyOS NEXT API 14 及以上”；`config/project.md` Compatibility；PL-02 | 实现报告和 D-12 声称“保持 CP-01 API 14 基线”，但项目构建配置的最小兼容版本是 **26.0.0**；用 API 26 SDK 构建不能证明 API 14 兼容，也无法在 API 14 设备安装。该配置在初始 commit `a6f6558` 已存在，**不是 T-11 的 31 路径变更**，但它直接削弱 PB-03 的“API 14 可用”结论和 CP-01 合规声明。 | 由 T-01/orchestrator 将 `compatibleSdkVersion` 调整为 14（或记录经批准的 CP-01 例外/延期，含影响范围），重跑构建；在设备矩阵中至少验证 API 14/15 的 `TLSSocket` 路径。T-11 报告不应把 CP-01 写成已验证。 |
| **F-07** | **Low（证据）** | `entry/src/test/evidence/t11-mock-exclusion.log`；`TransportBoundary.test.mjs`；报告 §0 | SC-11；DES-A §17.3；CQG-T11/T-20 | 见 §1.4：HAP 探针当前没有区分力，因为生产 HAP 里连 `service/gateway` 都没有。静态 import 扫描是有效的当前证据；HAP source map 检查必须在 T-19 组合根装配后重跑。证据日志是手写摘要，不是原始命令输出。 | 在报告/CQG 中把 HAP 探针标注为“组合根前的非区分性预检”；T-19/T-20 重跑并保存原始命令输出；保留静态扫描作为当前 SC-11 门禁。 |
| **F-08** | **Low（测试诚实性）** | `entry/src/ohosTest/ets/test/gateway/GatewayTransportDevice.test.ets:87-94` | DES-A §19.5；TEST-001 设备项；报告 §5.2/§6 | `C17_deviceSimulatorTlsPinContractIsPendingRunner` 的 `it()` 只断言 `DEFAULT_GATEWAY_PORT === 9200`；设备 runner 可用时它会**通过**，但完全没有验证 simulator TLS pin 契约。`BLOCKED` 只写在注释/describe 名称里，Hypium 不会因此跳过。 | 用 Hypium 的 skip/pending 机制显式标记，或删除该 `it` 直到 simulator 可运行；设备报告必须把“1 个占位断言通过”与 PB-03 运行时证据区分。 |
| **F-09** | **Low** | `GatewayDiscoveryService.ets:245-250` | DES-A §15.5（profile 不一致应为 `TLS_PROFILE_INCONSISTENT`/P-BLOCKED 证据） | `consumeBeacon` 在 `probe.reachable=true` 但 profile 不一致时统一返回 `GATEWAY_ID_MISMATCH`；profile 不一致和 identity 不一致被混为一类，诊断/UI 会误导。无对应 host 测试。 | 区分 `GATEWAY_ID_MISMATCH` 与 `TLS_PROFILE_INCONSISTENT`；增加 mDNS profile 不一致测试。 |
| **F-10** | **Low** | `GatewayDiscoveryService.ets:171-190`；`DiscoveryModels.ets:132-135`；`discovery/MdnsDiscoveryTransport.ets:97-104` | DES-A §15.3-6、§15.4、§21；PR-13/PR-06 | (a) 手动探测失败计数达到 5 后只有“成功”才清零；没有显式重试/换地址后的 reset，用户修正地址后仍可能被 `MANUAL_ADDRESS_REJECTED` 永久拒绝，除非重建服务。(b) `DiscoveryBeacon` 与 mDNS 适配器只校验 IPv4 语法，不拒绝 loopback/link-local/`0.0.0.0`；mDNS/UDP locator 可让 App 向本机/链路本地地址发签名 discover（不产生 verified 绑定，但有 SSRF/探测面）。 | 为手动重试/地址变化提供受限 reset（例如显式用户动作后清零）；beacon 地址复用 `IpAddressUtil.isAllowedLanIpv4`（或明确记录为何不限制）。 |
| **F-11** | **Low** | `GatewayRequestPolicy.ets:104-108,147-157` | DES-A §14.2.3；CB §6.3 | `validateValue` 在 `value===undefined` 时直接 return，导致 `SET_BRIGHTNESS`/`SET_COLOR`/`SET_TARGET_TEMPERATURE`/`SET_MODE` 可以不带值通过；`normalizeValue` 只大写 color，`SET_MODE` 校验用 `toUpperCase()` 接受小写但发送原值，而 `DeviceConstants.AC_MODES` 是大写词表。结果可能是网关 1002/1001 或 ACK state mismatch。 | 增加“动作→值是否必填”矩阵；`SET_MODE` 与大写词表一致地归一化（或明确拒绝小写），增加负例。 |
| **F-12** | **Low（测试保真度）** | `MockGatewayService.ets:115-123`；`GatewayMock.test.mjs:130-137` | DES-A §17.2 `ack-lost` 行“精确重传返回原 ACK” | Mock 的 ACK_LOST 第一次生成一个 ACK 后丢弃；第二次调用生成**新的** `request_id/seq` 和新的 ACK，仅带 `idempotent_replay`。它验证的是 client 级幂等结果，不是“同 request_id/seq 的原 ACK”。C-17 的字节级精确重传由 `FakeHttpTransport` 测试覆盖，但报告 §2.3 的“原 ACK”表述过强。 | 在报告中明确 C-20 ack-lost 是 client 级语义；若要覆盖“原 ACK”，使用 transport 级 fake/仿真器；或调整 Mock 接口以接收 request identity。 |

### 2.1 其他观察（不入阻断结论）

- **D-4 错误码命名**：C-17 header 验签抛 `RESPONSE_AUTH_FAILED`/`RESPONSE_CORRELATION_MISMATCH`，而 DES-A §14.4/contract-baseline §4.2 使用 `CONTROL_RESPONSE_AUTH_FAILED`/`ACK_CORRELATION_MISMATCH`。实现与 §18.7、TEST-001 SEC-N07/N08 一致，且两者映射到相同 i18n key；D-4 已登记。**建议** solution-architect 在 CQG 前统一命名并更新 contract-baseline/§14.4；这不是本次代码阻断项，但属于未关闭的契约歧义（R-20）。
- **C-20 Mock 生产位置**：`service/mock/**` 在 `main` 源树，符合 DES-A §17 的 fallback；当前无生产 import，静态扫描通过。R-16 仍有效，T-19/T-20 必须做组合根 source-map 门禁。
- **设备骨架**：`GatewayTransportDevice.test.ets` 的另外 3 个 `it` 是合理的“设备可用时”骨架；但无设备/无签名，整体 `BLOCKED`，不得写成 PASS。
- **文档一致性**：`entry/src/ohosTest/ets/test/README.md:13,74` 的 List/注册说明未列出 T-11 gateway suite；`t11-transport.md:173` 的 `oh-uni-package.json` 路径实际应为本机 `ets/oh-uni-package.json`/`sdk-pkg.json`（版本 26.0.0.105）。属于 Low 文档精度问题。
- **MockBle 取消测试**：`GatewayMock.test.mjs:241` 名为 `cancelIsObservedBetweenStages`，实际使用取消 token，不是 `MockBleProvisioningClient.cancel()`；`cancel()` 方法本身未覆盖。
- **资源/并发**：每请求新建 TLSSocket 并在 `finally` close（R-18）；`getRemoteCertificate` 无独立超时；C-18 `withProbeTimeout` 只拒绝外层 Promise，不取消底层 probe；`MdnsDiscoveryTransport.wait` 注册的 `onCancel` 监听器在超时后未移除。均为低风险/设备验证项，T-19 应纳入资源与 p95 检查。

---

## 3. 安全与契约逐项裁决

### 3.1 传输安全（最高优先）

| 检查项 | 结论 | 证据 |
|---|---|---|
| P-HMAC / P-TLS-PIN / P-BLOCKED 三档案 | **通过（有 F-01/F-03 限制）** | `resolveRuntimeProfile`；P-BLOCKED 在 `transport.send` 前抛 `GATEWAY_PROFILE_BLOCKED`；P-HMAC/P-TLS 构造校验 |
| P-BLOCKED 不发请求 | **通过** | `C17_pBlockedSendsNoRequest` 0 请求；`control`/`performDiscover` 均在 `withCommandSecret`/transport 前解析档案 |
| 禁止明文回退 | **通过** | `buildRequest` 仅 P-TLS 用 `https://`；`sendPinnedTls` 拒绝 `http://`；`TLS_*` 在 `isRetryable` 为 false；无二次明文调用 |
| Path B pin 校验时机 | **通过（编译/代码层）** | `connect(skipRemoteValidation)` → `getRemoteCertificate` → `getPublicKey().getEncoded` → SHA-256 → 常数时间匹配 → 才 `buildWireRequest`/`exchange`；失败 `close` |
| Path B fail-closed/错误分类 | **基本通过；运行时未证** | pin mismatch → `TLS_PIN_MISMATCH`；证书/SSL → `TLS_HANDSHAKE_FAILED`；超时/不可达 → `GATEWAY_TIMEOUT`/`GATEWAY_UNREACHABLE`；`mapError` 可能把未知错误笼统归 `TLS_HANDSHAKE_FAILED`（安全方向正确，诊断精度有限） |
| TOFU | **无** | 无证书持久化；pins 只来自已绑定 route；`TlsPinCheck` 只比较 SPKI-SHA256 |
| DEV-ONLY 拒收 | **通过** | `rejectDevOnly` 在 discover 状态检查/验签前，control 验签前；`trim().toUpperCase()` 大小写不敏感；测试覆盖 `dev-only` |
| HMAC/correlation 全链 | **通过（F-01 例外）** | `RequestSigner`/`ResponseVerifier` 未改；discover challenge/control requestId:seq；常数时间比较；`C17_control_badSignature/badCorrelation` |
| 精确重传 | **通过** | 复用同一 `HttpRequest`/body；`C17_control_retriesExactBytesOnTimeout` 字节/ nonce 相同 |
| 重试语义 | **不通过（F-01）** | 非 2xx 吞掉验签/协议异常并重试 5xx；与 §14.3/§18.9 冲突 |
| 安全事件记录 | **不通过（F-05）** | 无 TLS 失败日志 |

**结论**：核心“不发明文、不信任未验签响应、不复用 nonce、P-BLOCKED 前置”的设计正确；但 F-01 是明确的 fail-closed/重试语义缺陷，F-02 是 P-HMAC 发现可靠性缺陷；不能以 335 个 host 测试全绿替代修复。

### 3.2 发现服务（C-18）

| 检查项 | 结论 |
|---|---|
| LAST_KNOWN/手动 IP/mDNS 规则 | **基本通过**；手动仅已绑定、成功才更新地址；mDNS 无 hint 只 locator；identity/profile 严格比较 |
| gatewayId 严格一致 / 不可猜测绑定 | **通过**；`probeRoute` 校验 `probe.gatewayId === route.gatewayId`，服务/适配器无 route 创建路径 |
| 失败分类 | **部分**；LAST_KNOWN 失败警告不阻断其他 route；mDNS profile 不一致被误报 `GATEWAY_ID_MISMATCH`（F-09） |
| PB-01 seam | **通过**；`DiscoveryTransport` 只返回 locator；未实现 raw UDP；`includeUdp` 未注入 → warning；mDNS 服务类型/TXT 必须注入，无默认猜测 |
| 限频/失败预算/退避 | **基本通过**；500/1000/2000/4000/8000、总预算 30s；手动 2s/5 次；但 5 次后无 reset（F-10） |
| 资源/取消 | 阶段边界取消；probe 超时不取消底层；mDNS 监听器未移除（观察项） |

### 3.3 Mock（C-20）

| 检查项 | 结论 |
|---|---|
| 模式覆盖 | **通过**：normal/offline/ack-lost/replay/timeout/dev-only + TLS pin-match/mismatch/handshake-fail；17 条测试 |
| 确定性 | **通过**：FakeClock/SequenceRandom；无真实 sleep；`C20_normal_deterministic` |
| 生产 ACK 链 | **通过**：Mock 内部使用真实 `CanonicalBuilder`/`ResponseVerifier`/`ControlAckMapper`；但 ack-lost 不返回原 ACK（F-12） |
| 生产排除 | **静态 PASS；HAP 证据非区分性（F-07）**；Mock 文件带 TEST ONLY，主树无 import，HAP 无 Mock 字符串 |
| SC-11 边界 | **当前合规**；最终以 T-19/T-20 组合根 + source map 为准 |
| BLE Mock | 最小 port 面，扫描/阶段/v2.0/v2.1/离线/超时/取消覆盖；真实 C-19 归 T-12 |

### 3.4 契约与错误码

- **D-4**：C-17 采用 §18.7/TEST-001 的 `RESPONSE_AUTH_FAILED`/`RESPONSE_CORRELATION_MISMATCH`；§14.4/contract-baseline 仍写 `CONTROL_*`/`ACK_*`。实现选择有据且 D-4 已登记，**但契约尚未统一**，属 R-20；CQG 前应由 solution-architect 裁定并同步文档。两者 i18n key 实际一致，不是用户可见分叉。
- **ControlPolicy 边界**：D-5 的“C-10/C-11 预检”前提不完整（F-04）；C-17 直接 `control` 只做动作/值域规则。
- **App 错误码不复用网关数值空间**：通过；`result_code` 由 `GatewayResultClassifier`，App 使用字符串 code。
- **错误分类**：`HTTP_<status>`、`GATEWAY_*`、`TLS_*`、`ACK_*`、`DEV_SIMULATOR_REJECTED` 区分清楚；`TLS_PIN_CONFIG_INVALID` 等 i18n key 存在。

### 3.5 并发、资源与秘密

- **并发**：`GatewayMutex` 按 gatewayId 串行 control；不同网关可并行；discover/probe 未串行（没有共享 seq/nonce 状态，可接受）；`pending` map 每网关一条，有界。
- **资源**：每请求新建 TLSSocket/HttpRequest 并 `close`/`destroy`；无连接池（R-18）；`exchange` 累积响应无上限；`getRemoteCertificate` 无独立超时；C-18 timeout 不取消底层。Medium/Low，T-19 测量。
- **秘密**：`withCommandSecret` 回调内持有；`InMemoryCredentials` 复制并清零；日志无 secret/body/证书；Mock secret 为公开测试数据。**未发现秘密泄露**。

### 3.6 测试质量

- 335/335 PASS，T-11 60 条；正/负例覆盖面良好：P-BLOCKED 零请求、pin mismatch 不回退、DEV-ONLY 先于验签、精确重传、300/900、签名/correlation/缺 reported_state/目标不一致、C-18 identity/profile/手动/UDP/超时/取消、C-20 行为矩阵。
- **缺口**：F-01 的 500+bad-sign 未测；F-02 的 cache 未测；F-03 的无 TlsVerification 未测；F-04 的 C-10 类型矩阵未测；F-11 的缺值/小写 mode 未测；设备端 1 个占位用例（F-08）；`MockBle.cancel()` 未覆盖。
- **设备**：整体 BLOCKED（无 `hdc` target、无签名），不能把 ohosTest 编译成功当运行证据；报告对此基本诚实。

### 3.7 过程/仓库

- 31 路径全部在 handoff 范围；无 `contracts/**` 越界（D-1 位置例外沿用 T-06/T-07/T-08 记录）。
- 无构建产物/`oh_modules`/秘密入库；证据日志在 `entry/src/test/evidence/`。
- `git status` 干净；输入 pin 一致；commit subject 将使用 `docs(review): ...`，符合默认 policy。
- TEST-001 的 C-17/C-18/C-20 及 SEC-N07/N08/N10/N13/N17/N25 状态仍是 `NOT_RUN`/`BLOCKED`；CQG-T11 必须更新，不能把本报告当作 Gate 通过。

---

## 4. PB-03 结论评估

### 4.1 结论可信度：**有条件可信，但不能宣称已实现可用**

**成立的依据**：

1. 本地 SDK 为 API 26；SDK `@since` 事实核对一致：`certificatePinning` @12、`remoteValidation` @18、`TLSSocket.skipRemoteValidation` @12、`getRemoteCertificate` @9、`X509Cert.getPublicKey` @9、`PubKey.getEncoded` @9、`TLSConnectOptions.timeout` @22、`caData` @20。
2. Path A 因 `remoteValidation` API 18 下限不能覆盖 API 14-17，作为 v1 主路径不成立；Path B 的 API 表面覆盖 API 14+，选择 Path B 的理由成立。
3. Path B 实现顺序正确：先完成 TLS 握手与 SPKI pin 校验，再发送任何 HTTP 字节；pin 失败立即关闭，无明文回退、无 TOFU；这是本任务最重要的安全结论。
4. 报告没有把“编译通过/接口存在”写成“运行时验证通过”：`getRemoteCertificate` 的编码、`getEncoded()` 是否严格 SPKI DER、self-signed + `skipRemoteValidation` 行为、错误码区分、TLS 1.2/1.3、p95 均列为设备待验证（R-03/R-17/R-18）。这符合 PB-03 的诚实边界。

**不能成立的/被削弱的依据**：

1. **CP-01 构建基线**（F-06）：`build-profile.json5` 的 `compatibleSdkVersion` 是 26.0.0，因此“API 14+ 可用”目前只是 SDK `@since` 推断，不是项目构建/运行事实。PB-03 的 API 14 论证因此不能作为 CP-01 已验证证据。
2. **`X509Cert.getPublicKey()` 的文档措辞**：SDK 说该对象“used only for verify() of X509Cert”；`PubKey.getEncoded()` 的 X.509/ASN.1/DER 文档支持 SPKI 假设，但在该对象上是否可用需设备实证。实现正确地在失败时 fail-closed（TLS_HANDSHAKE_FAILED/PIN_MISMATCH），不会降级；但“Path B 可用”仍不能从编译推出。
3. **`getRemoteCertificate` 在 `skipRemoteValidation:true` 下是否始终返回完整证书**未证；失败方向是 P-BLOCKED，不是绕过。
4. **Path A 的 `publicKeyHash` hex/base64 语义**仍未证；R-17 保留；未来若改用 Path A，必须先做设备/仿真器对齐，不能在适配器里猜编码。
5. **无运行时 pin-match/mismatch**：设备骨架中的 simulator 用例是占位（F-08），不能作为 PB-03 证据。

### 4.2 评审结论

- **PB-03 选择 Path B 的设计判断：接受**（在 API 14 基线与 fail-closed 要求下合理）。
- **P-TLS-PIN 运行时可用性：BLOCKED，未证明**；C-17/C-18/C-20 保持 `UNVERIFIED`。报告 §0/§9 的 `UNVERIFIED` 正确。
- **设备验证清单必须包括**：`openssl x509 -pubkey` 对齐 SPKI-SHA256；pin-match/pin-mismatch/handshake-fail 三类错误码可区分；自签名证书 + skipRemoteValidation；TLS 1.2/1.3；每请求新建 vs 复用 p95；真实 `--tls` simulator 的 `X-YaoCore-Simulator` 拒收；API 14/15 设备矩阵。
- **不得**在设备证据缺失时把 P-TLS-PIN 标为 `STABLE` 或把 CP-01 标为 PASS。

---

## 5. 残余风险与跟踪项

| ID | 风险 | 级别 | 下一步/所有者 |
|---|---|---|---|
| R-03 | Path B 真机语义未证（SPKI 编码、skip 行为、错误码、TLS 版本） | High（阻断 P-TLS-PIN 可用性） | T-19/设备 runner；`tools/simulator --tls` + openssl 对齐 |
| R-17 | Path A `publicKeyHash` 编码/pin+skip 语义未证 | Medium | 设备 spike；未证前不使用 A |
| R-18 | 每请求新建 TLSSocket、无连接池；p95 未测 | Medium | T-19 性能测量；连接复用不得跳过 pin |
| R-16 | Mock 在 `main` 树，组合根可能误 import | Medium | T-19/T-20 静态 + source map 门禁；F-07 重跑 |
| R-19 | PB-01 未决；mDNS 服务类型/TXT/UDP 无生产定义 | Medium | 架构关闭 PB-01 后注入适配器；当前只 LAST_KNOWN/手动 |
| R-20 | D-4 错误码命名不一致 | Low/Medium | solution-architect 统一 §14.4/CB/TEST-001 |
| R-21 | `usingCache` 默认 true（F-02） | Medium | implementation-engineer 修复并重测 discover |
| R-22 | CP-01 构建基线 26（F-06） | High（上游） | T-01/orchestrator；compatibleSdkVersion 14 或批准例外 |
| R-23 | 无设备/签名；ohosTest 全部 BLOCKED | High（证据） | 设备可用后执行；不得用编译代替 |
| R-24 | C-18 probe 超时未取消底层、mDNS listener 未移除、响应无大小上限 | Low | T-19 资源/内存/取消测试 |
| R-25 | 手动失败 5 次后无 reset（F-10） | Low | UX/T-19 决定；提供显式重试路径 |
| R-26 | TEST-001 状态未更新（NOT_RUN/BLOCKED） | Low（过程） | CQG-T11 更新；不得把报告当 Gate PASS |
| R-27 | 设备占位测试可能误报通过（F-08） | Low | T-19/测试负责人修正 |

---

## 6. Verdict

**CHANGES_REQUIRED**

本实现的安全骨架（三档案、P-BLOCKED 前置、Path B 先验 pin 后发字节、DEV-ONLY 先于验签、HMAC/correlation、精确重传、Mock 生产边界）总体合理，host 证据、lint、构建均通过；但 **F-01** 是对 fail-closed/重试语义的明确违背（非 2xx 验签失败被吞掉并按 5xx 重试），**F-02** 使 P-HMAC 发现存在缓存导致的可靠性缺陷，**F-04/F-05** 是契约/可观测性缺口。考虑 C-17/C-18/C-20 仍为 `UNVERIFIED`，不能在当前 revision 通过 CQG-T11 或进入 `STABLE`。

修复后必须：

1. 重跑 `entry/src/test/run-host-tests.sh`、`codelinter`、`hvigorw clean assembleHap --no-daemon`；
2. 增加 F-01/F-02/F-03/F-04/F-11 的负例（至少 F-01 的 500+bad-sign）；
3. 由独立 reviewer 复审受影响代码；
4. 在设备可用时完成 PB-03 runtime 清单；CP-01 基线另由 orchestrator/T-01 处理（F-06）。

**未授予**：组件 `STABLE`、CQG-T11、Stage/Gate、用户验收。

---

## 7. 独立声明与限制

- 本报告由 `agent:quality-reviewer` 独立出具；评审者未编写 T-11 产品代码、测试或实现报告，未修改被审代码。
- 评审基于 `698883f` 快照与上述 pin 输入；未覆盖：真实设备/模拟器运行、真实网关 LAN、真实 mDNS/UDP 线格式（PB-01）、真实 TLS 证书语义、API 14 设备安装。上述均为 `BLOCKED`/`UNAVAILABLE`，不是 PASS。
- HAP 探针是评审者独立执行的只读检查；未将构建产物入库。
- 本报告不替代 CQG、Integration Gate 或 Stage Gate。

---

## 8. Handoff

```text
STATUS: RETURNED_FOR_GATE / CHANGES_REQUIRED
SUMMARY: T-11 安全骨架与 host 证据基本成立；335/335、codelinter、clean assemble 复验通过。但非 2xx 验签/协议失败被吞掉并按 5xx 重试（F-01，High/Blocking），P-HMAC discover 未禁用 HTTP 缓存（F-02，Medium），ControlPolicy 的 C-10 预检前提不成立（F-04），TLS 安全事件/transport 指标缺失（F-05）；CP-01 构建基线 26 与 API 14 要求不一致（F-06，上游）。当前不能授予 CQG/STABLE。
ARTIFACTS_CREATED: artifacts/70-review/t11-review.md
ARTIFACTS_UPDATED: none
RISKS: PB-03 runtime BLOCKED（R-03/R-17）；CP-01 基线（R-22）；Mock source-map 组合根门禁（R-16/F-07）；设备/签名缺失（R-23）；C-18 资源/手动 reset（R-24/R-25）。
VALIDATION: host 335/335（exit 0）；codelinter No defects（exit 0）；clean assembleHap BUILD SUCCESSFUL（exit 0）；HAP 无 Mock 字符串（但当前无 gateway 代码，非区分性）；输入 pin 全部一致。
NEEDS_CLARIFICATION: D-4 错误码命名由 solution-architect 统一；D-5 的 C-10 预检由架构确认；CP-01 兼容版本由 orchestrator/T-01 决策。
NEXT_ACTION: implementation-engineer 修复 F-01/F-02（并评估 F-03/F-04/F-05/F-11），补负例；技术负责人修正 F-08/F-09/F-10/F-12 与文档；独立复审后重跑三命令；设备可用后执行 PB-03/T-19 清单。
```
