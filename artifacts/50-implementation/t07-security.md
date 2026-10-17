# T-07 CryptoService + SecurityService 实现报告

- **Artifact ID**: IMP-T07-SECURITY
- **Producer**: agent:implementation-engineer
- **Type**: Implementation / Verification Evidence
- **Status**: Proposed（本地验证完成；待独立评审与 CQG-T07 Gate）
- **Date**: 2026-10-17
- **Task**: T-07 / `wp-016-security`（task 分支 `task/wp-016-security`，父分支 `feat/yaocore-app`，base commit `61768271f85651217f5a8ed9899ac9ebd4945dfa`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`
- **Upstream 契约**:
  - DES-A `artifacts/40-detailed-design/des-001a-foundation-transport.md` §3.2/§3.3/§3.5/§7/§8/§18/§27.4
  - `artifacts/20-architecture/contract-baseline.md` §2.3/§2.5/§3/§4
  - `artifacts/20-architecture/project-constraints.md`（SC-04/05/06/13/15；D-019）
  - `input/api/protocol/hmac-sha256-test-vectors.json`、`response-auth-test-vectors.json`、`discovery-request-auth-test-vectors.json`
  - `artifacts/60-testing/test-plan.md` §4/§5/§10
- **Downstream**: T-08/T-11/T-13/T-14/T-19、CQG-T07、Stage Gate
- **组件状态**: C-04 `UNVERIFIED`、C-05 `UNVERIFIED`（本报告不授予 `STABLE`）

---

## 0. 摘要

| 项 | 结果 | 证据 |
|---|---|---|
| C-04 CryptoService（SHA-256/HMAC/HKDF/PBKDF2/X25519/CTR/GCM/Random/CT-compare） | **实现完成** | 7 个产品文件；`Crypto.test.mjs` 14 用例 |
| C-05 SecurityService（canonical/sign/verify/nonce/skew） | **实现完成** | 6 个产品文件；`Security.test.mjs` 16 用例 |
| V-01 四条控制 HMAC 向量 | **4/4 canonical + sign 复算一致** | `Security.test.mjs` + Node `crypto` oracle |
| 发现请求 / 响应验签向量 | **各 1/1 复算一致** | 同上 |
| Node host 测试 | **PASS 118/118**（新增 30） | `entry/src/test/evidence/t07-host-node-tests.tap` |
| `ohpm install` | **PASS**（exit 0） | `evidence/t07-ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | **PASS**（BUILD SUCCESSFUL，35 tasks） | `evidence/t07-hvigor-assemble.log` |
| `codelinter -c code-linter.json5 -p default .` | **PASS**（No defects found） | `evidence/t07-codelinter.log` |
| Hypium host 编译（附加检查） | **COMPILED_ONLY**；`UnitTestArkTS` 3.238 s 成功，Previewer 执行 **BLOCKED**（timeout 124） | `evidence/t07-hvigor-test-compile.log` |
| 设备侧骨架（X25519/CTR/GCM/RFC7748） | **COMPILED_ONLY**；`onDeviceTest` **BLOCKED** | `evidence/t07-hvigor-test-compile.log`（`SecurityDevice.test` 进入编译图） |
| 真实 cryptoFramework 运行/设备射频 | **UNAVAILABLE**（无设备、无签名） | D-019 分层；不写成 PASS |

**结论**：C-04/C-05 的产品实现、纯逻辑 host 测试与公开向量复算已完成；构建、静态检查、host 测试全绿。真实 `@ohos.security.cryptoFramework` 行为仅完成 ArkTS 编译，必须由后续设备 runner 复跑同一组向量；本报告不宣布 `STABLE`。

---

## 1. 实现范围与文件清单

### 1.1 C-04（`entry/src/main/ets/service/crypto/`，7 文件）

```text
CryptoPort.ets          # CryptoPort/X25519KeyPair/X25519KeyHandle/AesCtrStream/GcmCiphertext
CryptoProvider.ets      # 低层 provider seam + CryptoProviderError(kind)
CryptoService.ets       # 参数校验/错误映射/CTR 状态机/常数时间比较
OhosCryptoProvider.ets  # 唯一 import @ohos.security.cryptoFramework 的生产文件
X25519KeyCodec.ets      # SPKI/PKCS#8 DER <-> 32B raw（严格前缀/长度）
CryptoRandomSource.ets  # RandomPort -> CryptoPort.randomBytes
```

关键实现：

- **SHA-256/HMAC-SHA256**：`createMd('SHA256')` / `createMac('SHA256') + createSymKeyGenerator('HMAC')`，输出必须 32B。
- **HKDF-SHA256**：`createKdf('HKDF|SHA256')`，`length` 严格 1..8160。
- **PBKDF2-SHA256**：`createKdf('PBKDF2|SHA256')`，强制 `iterations >= 120000`、salt 16B、输出 32B。
- **X25519**：raw 32B；DER 前缀 `302a300506032b656e032100` / `302e020100300506032b656e04220420`；全零共享秘密拒绝（低阶点防护）。
- **AES-256-CTR**：单实例连续 `updateSync`，`ACTIVE→BROKEN/DESTROYED`，`bytesProcessed` 单调，输出长度必须等于输入；失败即销毁且终止。
- **AES-256-GCM**：key 32B / iv 12B / tag 16B；解密失败映射 `CRYPTO_TAG_MISMATCH`，不返回部分明文；**仅邀请容器**，LAN 控制路径未实现 GCM（`EXT-GCM-001` 保持归档）。
- **随机**：`createRandom().generateRandomSync(n)`；长度必须精确且不得全零。
- **常数时间比较**：遍历 `max(a.length,b.length)`，长度差并入累加器，无提前返回。
- **错误映射**：provider 只抛 `CryptoProviderError(kind)`；平台 message/code 不进入 `AppError` 文本。

### 1.2 C-05（`entry/src/main/ets/service/security/`，6 文件）

```text
CanonicalBuilder.ets  # Control/Discover/Response/Cloud canonical + ResponseKind
RequestSigner.ets     # SigningInput/SignedControlRequest/SignedDiscoverRequest
ResponseVerifier.ets  # ExpectedResponse/VerifiedResponse/固定校验顺序
NonceCache.ets        # (keyId,nonce) TTL 300s / capacity 2048 / 最旧驱逐
ClockSkewTracker.ets  # server_time 偏差提示，不影响成功判定
```

关键实现：

- **Control canonical**：10 行、LF、无末尾换行；`value` 缺省为空行；`cmd_id=2001`；`alg=HMAC-SHA256`；`key_id=app-key-v1`。
- **Discover canonical**：6 行，首行 `YAOCORE-DISCOVER-V2`。
- **Response canonical**：4 行，首行 `YAOCORE-RESPONSE-V1`；body 使用**收到的原始字节** SHA-256，不重新序列化。
- **Cloud canonical**：10 行、云字段名、`CmdId=3001`（C-15 消费，C-05 不发起云请求）。
- **签名**：`hex_lower(HMAC-SHA256(secret, UTF8(canonical)))`；`signControl` 的 `timestamp` 与 `request_id` 使用同一 `clock.nowMs()` 快照（`request_id` 保留 13 位毫秒；时间戳秒级截断）。
- **nonce**：16B 随机 → `^[0-9a-f]{32}$`；`NonceCache` 重试最多 3 次，仍重复 → `INTERNAL_ERROR`。
- **响应验签固定顺序**：alg → keyId → correlation → sign 形状 → body SHA-256 → canonical → HMAC → 常数时间比较；响应不使用时间窗。
- **correlation**：discover=challenge；control=`requestId + ':' + seq`（十进制，无前导零）。
- **ACK 链**：不修改 C-03；host 集成测试证明 `ResponseVerifier` 通过后可原样交给 `ControlAckMapper`（签名→correlation→result_code→reported_state）。
- **边界**：App 不做网关侧 replay cache；`NonceCache` 只防出站 nonce 重复。精确重传由 C-17 复用原 `request_id/seq/nonce/sign`。

---

## 2. 契约对照

| 契约 | 实现位置 | 结果 |
|---|---|---|
| DES-A §7.1.1 `CryptoPort` 全方法 | `CryptoPort.ets` / `CryptoService.ets` | 实现 |
| DES-A §7.1.2 平台封装/随机/CT 比较 | `OhosCryptoProvider.ets` / `CryptoService.ets` | 实现；唯一平台 import |
| DES-A §7.1.3 DER↔raw | `X25519KeyCodec.ets` | 实现并 RFC 7748/Node 验证 |
| DES-A §7.1.4 算法参数 | `CryptoService.ets` | 实现；GCM 仅邀请用途注释 |
| DES-A §7.2 错误表 | `mapCryptoError` | UNAVAILABLE/INVALID_KEY/OPERATION/TAG/STREAM 映射 |
| DES-A §7.3 不变量 | `CryptoService.ets` / `AesCtrStreamImpl` | key 无缓存；CTR 状态机；全零 X25519 拒绝；PBKDF2 120k；随机非全零 |
| DES-A §8.1.1 canonical | `CanonicalBuilder.ets` | 10/6/4/10 行；无末尾换行 |
| DES-A §8.1.2 请求签名 | `RequestSigner.ets` | 实现；nonce 32-hex；不返回 secret |
| DES-A §8.1.3 响应验签 | `ResponseVerifier.ets` | 固定 9 步；不解析 body |
| DES-A §8.1.4 nonce 缓存 | `NonceCache.ets` | TTL/capacity/驱逐 |
| DES-A §8.1.5 时钟偏差 | `ClockSkewTracker.ets` | 仅提示；不阻断 |
| DES-A §8.2 错误 | `RequestSigner`/`ResponseVerifier`/`CryptoService` | 使用稳定 App code；无秘密 details |
| DES-A §8.3 不变量 | 同上 | canonical 行安全；nonce 生命周期；响应幂等无状态；correlation 精确 |
| DES-A §18.1-§18.6 | `CanonicalBuilder`/`RequestSigner` | 实现 |
| DES-A §18.7 判定链 | `ResponseVerifier` + C-03 `ControlAckMapper` | 保持 C-03 语义 |
| CB §2.5 / §3 | `DateTimeUtil` + `RequestSigner` | 时间戳紧凑 UTC；±120s；nonce 32-hex |
| CB §4 错误分类 | C-01 `GatewayResultClassifier`（未改） | 未复制网关码；安全失败 fail-closed |
| SC-15 常数时间 | `CryptoService.constantTimeEqual` | 实现；行为测试 |

---

## 3. 公开向量复算（Node `crypto` 独立 oracle）

所有 secret 均为 `PUBLIC TEST DATA ONLY`。产品 canonical 由 `CanonicalBuilder` 生成；产品 HMAC 由 `CryptoService(TestCryptoProvider)` 计算；Node `crypto.createHmac` 二次复算。

### 3.1 V-01 控制 HMAC（`hmac-sha256-test-vectors.json`，4/4）

| # | 向量 | canonical | expectedSign | 结果 |
|---|---|---|---|---|
| 1 | `number-value` | 与夹具逐字节一致 | `3555f16eeee3c30e0f79e967357f057d9a5387a8bf13aa2f8a32e80e944fbaae` | **MATCH** |
| 2 | `string-value-unicode` | 一致（`"制冷"` 保留非 ASCII） | `ce9e02332550418d91c8fcf3dbd4321145892a9db278e3f7e8d72bfdd239e9b8` | **MATCH** |
| 3 | `boolean-value` | 一致（`true`） | `be436609837789cbfd36e063ebec4bed3add05c7edb68b10c12378364d92bba0` | **MATCH** |
| 4 | `absent-value` | 一致（空 value 行） | `d1d9a61e8a6dbc59a2dc807347a1dab99907ed4944cbc9f442a401c438eb2169` | **MATCH** |

附加断言：每条 canonical 均为 10 行且无末尾换行；`request.sign == expectedSign`。

### 3.2 发现请求（`discovery-request-auth-test-vectors.json`，1/1）

- `fresh-discovery-request`：canonical 6 行、首行 `YAOCORE-DISCOVER-V2`，签名
  `97efb70951b827c43a2596a354a591081e50a0239b2f03f697228dcdbfbf664e` **MATCH**。

### 3.3 响应验签（`response-auth-test-vectors.json`，1/1）

- `discover-response`：body SHA-256
  `4d66e9571deecc0156ea4383a393058c6755c79bb60ff613d4ab070702b111a0` **MATCH**；
  `ResponseVerifier` 接受，签名
  `71165b69b2a7cb8cdcce63764f89e8df5005ca946e98f2c8269fed4ae86faa54` **MATCH**。
- 负例：坏签名、签名大写、签名长度错误、alg/keyId 不符、correlation 缺失/不等、
  body 篡改、secret <16B 均按契约失败关闭。

### 3.4 V-01 nonce 差异记录（T-19 澄清）

- 夹具 `nonce` 为 12 位小写 hex（如 `9f2a7c001122`），与 DES-A §3.3/§18.5
  “16B → 32 位小写 hex” 的出站生成契约冲突。
- 处理：**oracle 复算使用夹具原值**（`CanonicalBuilder` 只做行安全校验，不复用出站生成门）；
  `RequestSigner` 生成侧强制 32-hex，并由测试断言
  `^[0-9a-f]{32}$`。该差异不改变 V-01 的 canonical/HMAC 结论。
- 建议 T-19 明确：夹具保留历史 12-hex 仅用于向量；生产/联调以 32-hex 为准。

---

## 4. 测试清单

### 4.1 Node host（`entry/src/test/host/`，新增 30 用例）

**`Crypto.test.mjs`（14）**

1. SHA-256 对空串/ASCII/中文/长输入与 Node oracle 一致。
2. HMAC-SHA256 多组 key/message 与 Node oracle 一致。
3. HKDF-SHA256 RFC 5869 Test Case 1（L=42）一致。
4. PBKDF2-SHA256 120,000 次与 Node oracle 一致。
5. KDF 参数越界/盐长度错误失败关闭。
6. X25519 raw→DER 被 Node 接受，JWK 的 `x/d` 与 RFC 7748 raw 一致。
7. X25519 codec 拒绝错误长度/前缀/尾随数据。
8. X25519 输入长度、非 X25519 handle、全零共享秘密、平台不可用映射。
9. `constantTimeEqual` 等长/首字节/末字节/不等长行为。
10. CTR 连续流状态机：ACTIVE/bytesProcessed/DESTROYED/BROKEN。
11. CTR 输出长度不匹配 → BROKEN。
12. GCM 长度校验、tag mismatch、密文长度不匹配。
13. 随机长度精确、全零/短输出拒绝、不可用映射。
14. provider 输出长度不匹配/不可用映射。

**`Security.test.mjs`（16）**

1. V-01 四条 canonical + HMAC + fixture sign。
2. 发现请求 canonical + HMAC。
3. 响应验签向量（body SHA/correlation/signature）。
4. 响应 header 大小写不敏感 + 无时间窗。
5. 响应验签全部负例。
6. `ExpectedResponse` correlation 精确/参数负例。
7. `signControl` 同快照、13 位 request_id、32-hex nonce、10 行 canonical、签名 oracle。
8. `signControl` 四种 value 编码（number/string/boolean/absent）。
9. `signDiscover` 独立 challenge/nonce、6 行 canonical、六头齐全。
10. nonce 重复 3 次 → `INTERNAL_ERROR`；随机失败/短 secret/非法 target/seq 负例。
11. `NonceCache` TTL 边界 299999/300000、容量驱逐。
12. canonical 行注入/空字段/非法 seq/非法 body hash/cloud 10 行。
13. 时间窗 ±120000/±120001 与过期 3 分钟时间戳。
14. `ClockSkewTracker` 边界与非法时间戳。
15. ACK 链：响应验签 → C-03 `ControlAckMapper`（accepted/MATCH/apply），坏签名前置失败。
16. control correlation 无前导零 + 生成 nonce 32-hex。

### 4.2 Hypium host 编译套件（`entry/src/test/security/SecurityHost.test.ets`）

- 将 C-04/C-05（含 `OhosCryptoProvider`）拉入 `UnitTestArkTS` 编译图；
- 5 个 smoke 用例（构造、codec、canonical、signer/verifier、nonce/skew）；
- 同时以 compile-only import 引入设备骨架 `SecurityDevice.test.ets`；
- 执行仍 **BLOCKED**（Linux Previewer 限制，TEST-001 §3）。

### 4.3 设备侧骨架（`entry/src/ohosTest/ets/test/security/SecurityDevice.test.ets`）

标注 `BLOCKED_ON_DEVICE_RUNNER`，包含：

- SHA-256 `abc`、HMAC RFC 4231 Case 2；
- HKDF RFC 5869 Case 1；
- PBKDF2 120,000（公开预期值）；
- X25519 RFC 7748 §6.1 Alice/Bob 共享秘密 + DER round-trip；
- AES-256-CTR NIST SP 800-38A F.5.5 连续三块；
- AES-256-GCM 零向量 + tag 篡改；
- X25519 错误长度。

编译证据：`UnitTestArkTS` 产物
`entry/.test/default/cache/default/default@UnitTestArkTS/esmodule/debug/entry_test/src/ohosTest/ets/test/security/SecurityDevice.test.protoBin`。
`onDeviceTest` 未运行、无 `test_result.txt`，不得记为 PASS。

---

## 5. 命令与证据

| 命令 | 退出码 | 结果摘要 |
|---|---|---|
| `ohpm install` | 0 | `install completed in 0s 51ms` |
| `hvigorw clean assembleHap --no-daemon` | 0 | `BUILD SUCCESSFUL in 5 s 468 ms`；35 tasks（34 executed / 1 up-to-date）；仅 unsigned HAP warning |
| `codelinter -c code-linter.json5 -p default .` | 0 | `No defects found in your code.` |
| `entry/src/test/run-host-tests.sh` | 0 | `tests 118 / pass 118 / fail 0`；`duration_ms 1217` |
| `hvigorw test --no-daemon`（附加） | 124（Previewer 挂起） | `UnitTestArkTS` 3.238 s 完成；无 ArkTS ERROR；随后 `> hvigor Linux`，与 T-05/T-06 环境阻塞一致 |

证据文件（`entry/src/test/evidence/`）：

```text
t07-ohpm-install.log
t07-hvigor-assemble.log
t07-codelinter.log
t07-host-node-tests.tap
t07-hvigor-test-compile.log
```

---

## 6. 已知限制与契约偏差

1. **设备 API 未运行（D-019）**：`cryptoFramework` 的真实 SHA/HMAC/HKDF/PBKDF2/X25519/CTR/GCM/随机仅通过 ArkTS 编译；
   host 用独立 pure-TS `TestCryptoProvider` + Node oracle 验证同构逻辑。设备骨架已编译但 `BLOCKED`。
2. **端口物理位置**：DES-A §7 写 `contracts/CryptoPort.ets`，本任务写范围仅允许
   `service/crypto/**`/`service/security/**`，故 `CryptoPort.ets` 暂放
   `service/crypto/`。无第二套端口/实现；后续 `contracts/**` 迁移随 C-17 组合根进行，需 Gate 记录。
3. **CryptoService 构造 seam**：契约示例为 `CryptoService(new OhosCryptoProvider())`；实现接受
   `CryptoProvider` 低层接口，使 host 可注入独立 provider。生产仍由 `OhosCryptoProvider` 提供，
   且它是唯一平台 import；属于 §7.4 测试 seam 的显式参数化。
4. **平台算法名未设备验证**：`createMac('SHA256')` + `createSymKeyGenerator('HMAC')`、
   `createKdf('PBKDF2|SHA256')`、`createCipher('AES256|CTR|NoPadding')`、
   `'AES256|GCM|NoPadding'` 依据本地 SDK d.ts 与归档用法；首次设备运行必须复跑向量。
5. **GCM 使用边界**：仅实现邀请容器所需原语；没有 LAN 控制 GCM 分支，也没有 `cmd_id=2002`
   路径；`EXT-GCM-001` 保持归档。
6. **V-01 nonce 差异**：见 §3.4，转 T-19 澄清；实现未放宽生产 nonce 生成。
7. **ACK 编排不在 C-05**：C-05 只做验签/correlation；`ControlAckMapper` 与 `ControlOutcome`
   仍属 C-03/C-17。host 集成测试只证明链条可组合，不改变 C-03 语义。
8. **无网关 replay cache**：`NonceCache` 是 App 出站防护；网关侧“全部校验通过后入缓存、失败不消耗”
   属 C-20 Mock/固件，未在 C-05 实现。
9. **未测时序**：`constantTimeEqual` 只验证行为（长度/字节差异不提前返回的代码路径），
   未做统计时序测量（设备/性能阶段）。
10. **i18n**：本次无用户可见文案；错误仅使用既有稳定 code/i18n key，无硬编码文案。

---

## 7. 风险与后续

| 风险 | 影响 | 后续动作 |
|---|---|---|
| 平台 HMAC/KDF/Cipher 算法名或 X25519 DER 行为与 host 预期漂移 | 首次设备运行可能失败 | 设备 runner 执行 `SecurityDevice.test.ets`；失败按 T-19/失败诊断处理 |
| `OhosCryptoProvider` create 失败统一映射 `CRYPTO_INVALID_KEY`（X25519/Cipher 路径） | 平台不可用时应为 `CRYPTO_UNAVAILABLE` | 设备可用后按 BusinessError code 细化映射；不改变 fail-closed |
| V-01 nonce 夹具与生成契约冲突 | 互操作测试口径二义 | T-19 明确夹具历史值 vs 生产 32-hex |
| 无真实网关/ACK 时序 | 无法证明端到端成功率 | T-11/T-17 集成；模拟器与设备联调 |
| `X25519KeyCodec` 静态前缀数组可变 | 理论上可被调用方改写 | 评审可要求改为私有副本/冻结；当前无外部写入 |

---

## 8. Traceability

| 需求/约束 | 覆盖 |
|---|---|
| FR-GW-002 / BLE §4 | X25519、AES-256-CTR、SHA-256（PoP 原语） |
| ADR-002 §2 / §5 | HMAC 全链、AES-GCM 仅邀请、LAN 不实现 GCM |
| ADR-003 §3/§4 | HKDF-SHA256、GCM（邀请容器原语） |
| DP-04 / REQ L152 | PBKDF2-SHA256 120,000 |
| SC-04/05/06 | 每网关 secret 由调用方传入；CryptoService 无长期密钥状态；无秘密日志 |
| SC-13 | 响应验签 + C-03 ACK 链；HTTP/`success` 不参与成功判定 |
| SC-15 | `constantTimeEqual` 固定遍历 + 行为测试 |
| CB §2.5 / §3 | 时间窗、request_id、nonce、canonical、correlation |
| CB §4 | 不复制网关码；失败 fail-closed；错误分类留在 C-01/C-03 |
| DES-A §7.4 / §8.4 | host/device seam 与向量清单 |
| TEST-001 §3/§5 | host Node 证据、Hypium BLOCKED、设备骨架 BLOCKED |
