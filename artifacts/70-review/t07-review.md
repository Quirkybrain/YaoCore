# T-07 独立 Code Review：C-04 CryptoService + C-05 SecurityService

- **Artifact ID**: REV-T07-001
- **Producer**: agent:quality-reviewer
- **Type**: Independent Code Review / CQG-T07 Evidence
- **Status**: CHANGES_REQUIRED（独立评审完成；不授予 PASS、STABLE、CQG-T07 完成或 Stage/用户验收）
- **Date**: 2026-10-17
- **Task**: `wp-017-review-t07`（task 分支 `task/wp-016-security`，父分支 `feat/yaocore-app`，base commit `ee678793b91f79c30e086b983c48b954395c9350`，parent `61768271f85651217f5a8ed9899ac9ebd4945dfa`）
- **Workflow**: STANDARD / GATED_AUTO
- **Reviewed revision**: `ee678793b91f79c30e086b983c48b954395c9350`（23 路径：C-04 6 文件、C-05 5 文件、测试/证据、实现报告）
- **Review scope**: `entry/src/main/ets/service/crypto/`、`entry/src/main/ets/service/security/`、`entry/src/test/`（T-07 新增文件及聚合入口）、`entry/src/ohosTest/ets/test/security/`、`artifacts/50-implementation/t07-security.md`
- **Review snapshot**: `refs/swe/snapshots/20261017T083330Z-wp-017-review-t07-799c9169`（commit `47ff3f8af810cf51113f90951b06a4724bab7879`）
- **Independence**: 本报告由未参与 T-07 实现的质量评审者（`agent:quality-reviewer`）编写；T-07 作者为 `agent:implementation-engineer`。作者之外独立裁决，作者不能批准本报告或自行关闭本评审。

> 结论先行：C-04/C-05 的构建、静态检查、Node host 测试与公开向量复算表现良好；未发现伪造 HMAC、秘密日志、乐观成功或可远程绕过的 fail-open 路径。但存在三处 **Medium** 问题：平台错误分类与 DES-A §7.2 不一致、GCM 初始化失败路径未清理 `SymKey`（另有 X25519 私钥 DER 临时副本未清零）、设备侧 GCM 测试标签向量错误。故不授予 PASS，判 **CHANGES_REQUIRED**。设备/真实 `cryptoFramework` 证据仍为 `COMPILED_ONLY`/`BLOCKED`，本次评审不授予 CQG-T07 或 STABLE。

---

## 1. 评审范围、输入与方法

### 1.1 范围

| 类别 | 路径 | 本次核对 |
|---|---|---|
| C-04 产品代码 | `entry/src/main/ets/service/crypto/**` | 6 文件：`CryptoPort`、`CryptoProvider`、`CryptoRandomSource`、`CryptoService`、`OhosCryptoProvider`、`X25519KeyCodec` |
| C-05 产品代码 | `entry/src/main/ets/service/security/**` | 5 文件：`CanonicalBuilder`、`ClockSkewTracker`、`NonceCache`、`RequestSigner`、`ResponseVerifier` |
| Host 测试 | `entry/src/test/host/{Crypto,Security}.test.mjs`、`TestCryptoProvider.ets` | 30 个新用例；Node oracle |
| Hypium host | `entry/src/test/security/SecurityHost.test.ets`、`entry/src/test/List.test.ets` | 编译图接入；5 个 smoke 用例（不执行） |
| 设备骨架 | `entry/src/ohosTest/ets/test/security/SecurityDevice.test.ets` | `BLOCKED_ON_DEVICE_RUNNER`；未注册进 ohosTest 聚合入口 |
| 证据/报告 | `entry/src/test/evidence/t07-*`、`artifacts/50-implementation/t07-security.md` | 与命令输出核对 |

`git show --name-status ee67879` 核对：23 个变更路径均在 `wp-016-security` 的 `commit_paths` 内；没有越界修改 `entry/src/main/ets/common/**`、`model/**`、`service/protocol/**`、构建配置或 `input/**`。工作树在评审开始时 clean；本次评审唯一写入是本报告。

### 1.2 权威输入 pin

| 输入 | SHA-256 核对 |
|---|---|
| `artifacts/50-implementation/t07-security.md` | `bb3acc10d5662c3c60645107841b4908757cf09c5b728500de84980228d28276`，与 handoff 一致 |
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `5599e693fafe405443c5d28efaec0bd2091064eee5c3f1a619dc22d3dcbfe1c1`，一致 |
| `artifacts/20-architecture/contract-baseline.md` | `6673a990d5020c0b70dd4ae30bd75fa13d33d4d573a4d953961371296fadee89`，一致 |
| `artifacts/20-architecture/project-constraints.md` | `283046210e68dfbce9119abbbac849bd1f9a23cf7ef2fb51dcb4aa1e23da9528`，一致 |
| `artifacts/60-testing/test-plan.md` | `33485cc39abd9a917e94b6568b29e162cd90897adfad509e3f59403a56055fae`，一致 |

### 1.3 明确排除

以下不属于本次 T-07 结论，且不写成 PASS：

- 真实 `@ohos.security.cryptoFramework` 的设备运行（无设备/无签名；`onDeviceTest` 为 `BLOCKED`）。
- `hvigorw test` 的 Hypium 运行时（Linux Previewer 限制；仅 `COMPILED_ONLY`）。
- T-11/T-17 的 discover→control→ACK 网络编排、DEV-ONLY 拒收、TLS pin、网关 replay cache。
- T-13 邀请容器 AEAD/过期/撤销的完整实现；本任务只提供 GCM 原语。
- T-14/C-15 云命令消费；本任务只实现 `cloudCommand` canonical。
- T-19 全量测试报告、状态更新、设备/性能/安全最终证据。
- C-03 `ControlAckMapper` 的重新评审；本任务未修改其语义。

### 1.4 方法

1. Diff first：先读 `6176827..ee67879` 的 23 文件，再读周边 `AppError`、`ProtocolConstants`、`DateTimeUtil`、`JsonAtom`、`HttpHeaders`、`GatewayResultClassifier`/`ControlAckMapper` 调用面。
2. 逐条对照 DES-A §7/§8/§18、CB §2.5/§3/§4、PC SC-04/05/06/13/15、TEST-001 §4.3/§5。
3. 追踪数据/控制/错误/信任边界：canonical → HMAC → header 形状 → body hash → 常数时间比较；nonce 生成/重试/缓存；CTR 状态机/资源释放；X25519 DER↔raw；GCM 初始化/失败路径。
4. 只读复验：`entry/src/test/run-host-tests.sh`、`codelinter -c code-linter.json5 -p default .`、`hvigorw clean assembleHap --no-daemon`、`git show/status/diff --check`。
5. 独立复算：用 Node `crypto` 复核 AES-256-GCM 零向量、AES-256-CTR、PBKDF2、HKDF、X25519 共享秘密，定位设备测试向量差异。
6. 安全扫描：产品代码无 `console`/`hilog`/`Math.random`；无硬编码签名/秘密；`TestCryptoProvider` 未被 main import；`@ohos.security.cryptoFramework` 仅在 `OhosCryptoProvider`。

> 评审者未修改任何被测文件；运行构建只产生被 `.gitignore` 忽略的 `entry/build` 与 `.hvigor` 输出；`git status --short` 在写入本报告前为空。

---

## 2. 独立复验结果

| 命令 | 结果 | 与实现报告/证据对比 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS 118/118**，`# fail 0`，exit 0，`duration_ms 1382.6766` | 与 `t07-host-node-tests.tap` 的 118/118 一致；新增 30 个 T-07 用例 |
| `codelinter -c code-linter.json5 -p default .` | **PASS**，`No defects found in your code.`，exit 0 | 与 `t07-codelinter.log` 一致；注意 `code-linter.json5` 忽略 `src/test`/`src/ohosTest`，不覆盖测试源码 |
| `hvigorw clean assembleHap --no-daemon` | **PASS**，`BUILD SUCCESSFUL in 5 s 590 ms`，35 tasks（34 executed / 1 up-to-date），exit 0；仅 unsigned HAP warning | 与 `t07-hvigor-assemble.log` 的 5 s 468 ms/35 tasks 一致（正常时间浮动） |
| `git show --stat ee67879` | 23 files changed，4176 insertions(+)，2 deletions(-) | 与 handoff/实现报告一致 |
| `git diff --check` | 无输出 | 无空白错误 |
| `git status --short`（评审开始） | clean | 无未提交构建产物/测试改动 |
| `hvigorw test` / `onDeviceTest` | **未重跑**；同 revision 证据为 `UnitTestArkTS` 编译成功 + `> hvigor Linux`（124）与 `BLOCKED` | 不把 `COMPILED_ONLY` 写成 PASS；设备/Previewer 仍是已知环境限制 |

补充核对：`entry/src/test/evidence/t07-*` 只含命令输出和公开测试数据，未发现真实 secret、证书、Token 或构建产物；`entry/build/`、`.hvigor/`、`oh_modules/` 均被 ignore。

---

## 3. Findings

> 严重度：**Critical** = 可导致错误成功/密钥泄漏/不可恢复数据损坏；**High** = 明确安全或核心协议破坏；**Medium** = 冻结契约不一致或安全生命周期缺口，有明确修复路径；**Low** = 严格性、测试集成、文档或防御性缺口。

| ID | 严重度 | 位置 | 问题 | 违反契约/约束 | 修复建议 |
|---|---|---|---|---|---|
| **R-01** | **Medium** | `entry/src/main/ets/service/crypto/OhosCryptoProvider.ets:142-221, 237-239, 273-275, 97-99, 278-282` | 错误分类不完整：X25519 的 `createAsyKeyGenerator`/`createKeyAgreement`、CTR/GCM 的 `createCipher` 及其 init 失败被统一映射为 `CRYPTO_INVALID_KEY`；`createKdf` 失败映射为 `CRYPTO_OPERATION_FAILED`；HMAC key 转换/init/update/final 失败统一映射为 `CRYPTO_OPERATION_FAILED`；GCM `doFinalSync` 的任何失败都映射为 `CRYPTO_TAG_MISMATCH`。`createMd`/`createMac`/`createRandom` 的创建失败已正确映射 `CRYPTO_UNAVAILABLE`，不在本 finding 的缺陷范围。 | DES-A §7.2（不可用/初始化失败 → `CRYPTO_UNAVAILABLE`；key 长度/格式/算法 → `CRYPTO_INVALID_KEY`；平台操作 → `CRYPTO_OPERATION_FAILED`；GCM tag → `CRYPTO_TAG_MISMATCH`）；CB §4.2；SC-15 仍 fail-closed | 将“创建原语/算法不可用”“key 转换/格式”“操作执行”“GCM 认证”分路径 catch；创建失败映射 `CRYPTO_UNAVAILABLE`，key 转换映射 `CRYPTO_INVALID_KEY`，操作映射 `CRYPTO_OPERATION_FAILED`，GCM doFinal 的认证失败保留 `CRYPTO_TAG_MISMATCH`；补 provider seam/设备负例。报告 §7 已记录此风险，本次评审要求修复而不是仅跟踪。 |
| **R-02** | **Medium** | `entry/src/main/ets/service/crypto/OhosCryptoProvider.ets:225-239, 261-275, 155-164`；`X25519KeyCodec.ets:38-40` | GCM `encrypt/decrypt` 在 `symKey` 创建后若 `createCipher`/`initSync` 抛错，catch 直接抛出，未调用 `symKey.clearMem()`；`importX25519PrivateRaw` 生成的 PKCS#8 DER 临时副本含 32B 私钥，`convertKeySync` 后未 `fill(0)`。 | SC-06（秘密用后立即置空覆盖、禁止持久化/日志）；DES-A §3.5；DES-A §7.3-1（操作结束清理临时缓冲）；§7.1.3（私钥 raw 只用于导入，不得返回/记录） | 在 GCM 初始化失败的 catch/`finally` 清 `symKey`（避免与第二段 `finally` 重复清理）；`importX25519PrivateRaw` 用 `try/finally { der.fill(0); }` 清零 DER；必要时用 `BytesUtil.zeroize`；补代码级/设备级验证。 |
| **R-03** | **Medium** | `entry/src/ohosTest/ets/test/security/SecurityDevice.test.ets:93-115`（期望 tag 在 101-102） | AES-256-GCM 设备测试的标签向量错误：密文 `cea7403d4d606b6e074ec5d3baf39d18` 对应 **16B 零明文**，但期望 tag `530f8afbc74536b9a963b4f1c4cb738b` 是 **空明文** 的 tag；Node `crypto` 对 16B 零明文的实际 tag 为 `d0d1c8a799996bf0265b98b5d48ab919`（空明文才得到 `530f...`）。此外测试只断言 `opened.length === 16`，未断言明文内容。 | TEST-001 §4.3 CQG-T07 设备向量证据；DES-A §7.4（GCM 向量）；NIST GCM 测试数据纪律 | 将期望 tag 改为 `d0d1c8a799996bf0265b98b5d48ab919`；断言 `opened` 与 16B 零明文逐字节相等；保留 `BLOCKED_ON_DEVICE_RUNNER`，首次设备运行必须复跑。 |
| **R-04** | **Low** | `entry/src/ohosTest/ets/test/List.test.ets:1-5`；`entry/src/test/security/SecurityHost.test.ets:23` | `SecurityDevice.test` 只被 host `SecurityHost` import（用于 `UnitTestArkTS` 编译），未注册进 `ohosTest/ets/test/List.test.ets`；`onDeviceTest` 即使设备可用也只会执行 `Baseline.test`。`FoundationDevice.test` 同样未注册（T-06 遗留）。 | TEST-001 §2.3/§4.3；T-07 报告 §4.3/§7 的“设备 runner 执行 SecurityDevice”实际尚未接线 | 由 T-19/T-12 在设备测试聚合入口 import `securityDeviceTest`（及 `FoundationDevice`），或在 T-07 write scope 扩展后由实现者接线；在此之前报告应明确“仅 host 编译图覆盖，onDeviceTest 未注册”。 |
| **R-05** | **Low** | `entry/src/test/README.md:46,97` | README 仍写“当前 revision：88/88 PASS”（T-06 修复后），目录树也未列出 `Crypto.test.mjs`/`Security.test.mjs`/`TestCryptoProvider.ets`/`security/`；与当前 118/118 证据不一致。 | TEST-001 §5/§10 证据纪律；实现报告 §5 的 118/118 | 更新为 118/118（`t07-host-node-tests.tap`）并补 T-07 目录/用例说明；T-19 复核。 |
| **R-06** | **Low** | `artifacts/50-implementation/t07-security.md:26-27,44-75` | 报告摘要写 C-04“7 个产品文件”、C-05“6 个产品文件”，但实际分别为 6、5；§1.1/§1.2 的代码清单也只有 6/5 项。 | 实现报告的自我一致性；评审证据准确性 | 修正为 6/5，或明确统计口径（例如是否计入 test-only 文件）；重新提交报告。 |
| **R-07** | **Low** | `entry/src/main/ets/service/crypto/X25519KeyCodec.ets:15-24` | `SPKI_PREFIX`/`PKCS8_PREFIX` 为 public `static readonly Uint8Array`；`readonly` 只保护绑定，不保护数组内容，外部可改写前缀导致 DER 包装错误。报告 §7 已自行记录。 | DES-A §7.1.3（固定前缀）；防御性/可维护性；当前无外部写入 | 优先保持内部私有副本并在公开处复制/只读访问；若必须保持 public（契约签名），在文档/测试中声明不可改写并禁止外部写入。T-17/C-17 组装时复核。 |
| **R-08** | **Low** | `entry/src/main/ets/service/crypto/CryptoPort.ets:1-83`；`CryptoService.ets:34-39` | 两处已记录的结构偏差：`CryptoPort` 暂放 `service/crypto/` 而非 DES-A §7 的 `contracts/CryptoPort.ets`；`CryptoService` 构造参数为低层 `CryptoProvider` 而非契约示例的 `OhosCryptoProvider`。无第二套实现，生产仍注入 `OhosCryptoProvider`。 | DES-A §7 路径/§7.1.2；§7.4 测试 seam；T-06 R-13 的迁移计划延伸 | 随 C-17 组合根迁移到 `contracts/**`，或在 CQG/Gate 记录书面例外；迁移时保持签名，不要复制两套端口/实现。 |

### 3.1 非阻塞观察（不作为 blocking finding）

1. **响应验签的常数时间比较表示**：`ResponseVerifier.ets:102-105` 比较的是两个 64 字符小写 hex 的 UTF-8 字节，而不是解码后的 32B HMAC 原始字节。行为上常量时间且数学等价（hex 为单射、长度固定），未发现可利用差异；但 §8.1.3 第 8 步写作 `expectedSignBytes/actualSignBytes`，建议后续统一为解码 32B 后比较，或在报告中记录该表示选择。
2. **CTR 并发调用**：`CryptoService.ets:301-317` 的 `AesCtrStreamImpl.process` 没有 in-flight 串行化；若调用方不 `await` 而并发调用，两个调用都可能先通过 `ACTIVE` 检查，失败/成功顺序可能造成状态与 `bytesProcessed` 语义偏差。当前调用面按顺序使用，未发现并发调用；建议在 C-17 调用约定中明确“必须串行 await”，或增加内部队列/忙碌拒绝。
3. **V-01 测试的 value 编码来源**：`entry/src/test/host/Security.test.mjs:42,117` 在 V-01 canonical 复算时使用测试 oracle 的 `valueAtom`，而不是产品 `JsonAtom.encode`；产品 `JsonAtom`/`RequestSigner` 另有测试覆盖，且 Node HMAC oracle 独立，故不影响当前向量结论。若要更强的端到端证据，可在 V-01 测试中改用产品 `JsonAtom.encode`（不改变 fixture 值）。
4. **`NonceCache.contains` 不主动 purge**：`NonceCache.ets:56-63` 只按 TTL 判断，过期条目由 `checkAndRemember`/`size` 清理；容量有界（2048），不构成泄漏；可考虑在 `contains` 中也清理或记录。
5. **`clearMem` 的 syscap warning**：`t07-hvigor-test-compile.log` 多次提示 `createCipher`/`clearMem`/`createRandom` 等“not supported on all devices”。这是编译期 syscap 提示，不是缺陷；设备阶段必须验证 `clearMem` 可用性，避免清理调用本身失败影响成功路径。
6. **平台 `BusinessError.code` 未进入 `details`**：`OhosCryptoProvider` 完全丢弃平台 code/message，安全上更保守；DES-A §7.2 允许 code 进入 `details`（数字），当前不提供诊断信息。若后续排障需要，可在不改变用户文案的前提下加入数字 code。
7. **T-06 端口例外仍未迁移**：T-06 R-13 计划 T-07 迁移 `Ports.ets`/`CryptoPort` 到 `contracts/**`；T-07 write scope 不含 `contracts/`，故 R-13 仍开放。C-17/T-19 需要继续跟踪，避免后续 import 错位置。
8. **实现 handoff 的 snapshot 覆盖**：`wp-016-security.snapshot_paths` 只含 `entry/src/test/` 与 `artifacts/50-implementation/`，未含 `service/crypto|security` 产品目录；本次评审 snapshot 已覆盖产品目录，未影响本次结论。后续实现 handoff 建议把产品写范围纳入 snapshot，避免只靠 `commit_paths`。

---

## 4. DES-A §7 / §8 / §18 对照要点

### 4.1 §7 C-04 CryptoService

| 契约条目 | 结果 | 说明/证据 |
|---|---|---|
| §7.1.1 `CryptoPort` 全方法 | **PASS（带 R-08 路径例外）** | 方法齐全；`X25519KeyPair`/`GcmCiphertext`/`AesCtrStream` 形状与契约一致；端口暂放 `service/crypto/`。 |
| §7.1.2 平台封装/随机/常数时间 | **PASS（带 R-01）** | `OhosCryptoProvider` 是唯一 `@ohos.security.cryptoFramework` import；`createRandom()` 用于随机；`constantTimeEqual` 遍历最大长度、无提前返回。创建失败的 `UNAVAILABLE` 分类见 R-01。 |
| §7.1.3 X25519 DER↔raw | **PASS（带 R-07）** | 前缀 `302a300506032b656e032100` / `302e020100300506032b656e04220420`，长度严格；Node `createPublicKey`/`createPrivateKey` + JWK 复核 raw 一致；测试拒绝错误长度/前缀/尾随数据。 |
| §7.1.4 算法参数 | **PASS（设备未验证）** | SHA-256/HMAC 32B；HKDF L≤8160；PBKDF2 120k/16B salt/32B；X25519 32B；CTR key32/iv16；GCM key32/iv12/tag16；GCM 仅邀请用途，无 LAN GCM 分支。 |
| §7.2 错误表 | **PARTIAL（R-01）** | 服务层 `mapCryptoError` 的 UNAVAILABLE/INVALID_KEY/AUTH_TAG/OPERATION 映射正确；provider create/init/key-conversion/decrypt 的分类不完整。仍 fail-closed，不泄漏平台 message。 |
| §7.3 不变量 | **PARTIAL（R-02）** | 无长期 key 缓存；CTR `ACTIVE→BROKEN/DESTROYED`；`bytesProcessed` 成功时单调；输出长度严格；X25519 全零共享秘密拒绝并清零；PBKDF2 120k；随机长度精确且拒绝全零；CT 行为正确。GCM 初始化失败路径的 `SymKey` 与 X25519 私钥 DER 临时副本未清零（R-02）。 |
| §7.4 seam | **PASS** | `TestCryptoProvider` 仅测试代码、未进入 main；host 用独立 provider；`SecurityHost` 仅编译；设备骨架已标注 `BLOCKED_ON_DEVICE_RUNNER`；设备算法名/`clearMem` 仍未验证。 |

### 4.2 §8 C-05 SecurityService

| 契约条目 | 结果 | 说明/证据 |
|---|---|---|
| §8.1.1 canonical | **PASS** | control 10 行、discover 6 行、response 4 行、cloud 10 行；LF、无末尾换行；`required`/`line`/`integer` 检查空串、LF/CR、非整数和越界；V-01 4 条 canonical 逐字节一致。 |
| §8.1.2 请求签名 | **PASS** | `signControl` 用同一 `nowMs` 生成 timestamp 与 13 位毫秒 requestId；nonce 16B→32 位小写 hex，重复最多 3 次后 `INTERNAL_ERROR`；不返回 secret；`signDiscover` 六头齐全；HMAC 用 UTF-8 canonical。 |
| §8.1.3 响应验签 | **PASS（表示观察）** | 固定顺序：alg → keyId → correlation 存在 → correlation 相等 → sign 形状 → body SHA-256 → canonical → HMAC → 常数时间比较；不使用时间窗；body 使用收到的原始字节；失败 `RESPONSE_AUTH_FAILED`/`RESPONSE_CORRELATION_MISMATCH`。比较的是 hex UTF-8 字节（观察 1）。 |
| §8.1.4 nonce 缓存 | **PASS** | `(keyId, nonce)`、TTL 300s、capacity 2048、最旧驱逐；TTL 边界 299999/300000 测试通过；`CAPACITY_EXCEEDED` 仅诊断，signer 接受并继续。 |
| §8.1.5 时钟偏差 | **PASS** | `observe` 返回 `skewMs`/`exceedsWindow`；`abs(skew) > 120000`；解析失败 `PROTOCOL_INVALID_TIMESTAMP`；不自动改签名时钟、不阻断响应成功判定。 |
| §8.2 错误 | **PASS（带 R-01）** | header/常量/签名失败 → `RESPONSE_AUTH_FAILED`；correlation → `RESPONSE_CORRELATION_MISMATCH`；secret <16B → `CRYPTO_INVALID_KEY`；随机失败 → `CRYPTO_OPERATION_FAILED`；canonical 字段非法 → `PROTOCOL_VALUE_OUT_OF_RANGE`。平台 crypto 分类见 R-01。 |
| §8.3 状态机/不变量 | **PASS** | canonical 行安全；nonce 生成→缓存→TTL；精确重传复用由 C-17 负责；响应验签无状态、可重复；correlation 精确 `requestId:seq`；signer/verifier 不保存 secret。网关侧“失败不消耗 nonce”属于 C-20/T-11，未在本组件实现。 |
| §8.4 seam | **PASS** | 仅依赖 `CryptoPort`/`ClockPort`/`RandomPort`，不 import 平台 API；host 向量测试；设备测试未运行。 |

### 4.3 §18 协议层细化

| 契约条目 | 结果 | 说明/证据 |
|---|---|---|
| §18.1 控制 canonical | **PASS** | 10 行、`cmd_id=2001`、`alg=HMAC-SHA256`、`key_id=app-key-v1`；value 缺省空行、string/boolean/number 编码；V-01 4/4 canonical 与 expectedSign 一致；无末尾换行。 |
| §18.2 发现 canonical | **PASS** | 6 行、首行 `YAOCORE-DISCOVER-V2`；challenge/nonce 32-hex；六头；公开向量 1/1 一致。 |
| §18.3 响应 canonical | **PASS** | 4 行、`YAOCORE-RESPONSE-V1`；body 使用原始字节 SHA-256；kind∈{discover,control}；公开向量 1/1 一致；常数时间比较；失败 fail-closed。 |
| §18.4 HMAC/常数时间 | **PASS** | secret UTF-8、HMAC 32B→64 hex lower；比较前统一为字节；`constantTimeEqual` 不因长度/首字节提前返回；失败不记录 secret/canonical。 |
| §18.5 时间窗/nonce | **PASS（App 侧）** | 时间窗 ±120000（含边界）测试；nonce/challenge 32-hex；生成即视为消耗；网关 replay cache/失败不消耗属于 C-20，未实现。V-01 夹具 12-hex 差异已如实记录，生成侧仍强制 32-hex。 |
| §18.6 request_id/seq | **PASS** | `req-<13 位 epochMillis>-<seq>`；timestamp 秒级截断、requestId 毫秒；同一 `nowMs` 快照；seq 0..2147483647；correlation 无前导零。 |
| §18.7 响应验签/ACK 判定链 | **PASS（C-05 范围）** | verifier 完成第 2..5 步；C-03 `ControlAckMapper` 未修改；host 集成测试证明验签通过后可原样交给 ACK mapper（签名→correlation→result_code→reported_state）。DEV-ONLY、HTTP、body 解析等由 C-17 处理。 |
| §18.9 失败关闭 | **PASS** | 无法验签/无法解析/无法 correlation → 不执行、不应用状态；response 不使用时间窗；`server_time` 不参与成功判定。 |

---

## 5. 测试质量与证据诚实性

### 5.1 有效覆盖

- **V-01**：4/4 canonical + product HMAC + Node `createHmac` 二次 oracle；四条 expectedSign 一致；value 四种形态均有覆盖。
- **V-02/V-03**：发现请求 1/1、响应验签 1/1；响应负例覆盖 alg/keyId、correlation 缺失/不等、sign 缺失/大写/长度错误/翻转、body 篡改、secret <16B。
- **签名/相关性**：同一 clock 快照、13 位 requestId、32-hex nonce、`requestId:seq` 无前导零、ACK 链组合。
- **nonce/skew**：TTL 299999/300000、容量驱逐、重复 nonce 3 次失败、随机失败、时间窗 ±120000/±120001、过期 3 分钟、ClockSkew 边界/非法时间戳。
- **Crypto**：SHA/HMAC/HKDF/PBKDF2 与 Node/RFC 对比；X25519 DER↔raw 与 Node JWK；CT 行为；CTR 状态机/失败终止/长度不匹配；GCM tag/长度；随机长度/全零/不可用；provider 输出长度错误。
- **独立性**：`TestCryptoProvider` 是测试专用纯 TS 实现，未进入 `entry/src/main`；Node oracle 与产品实现分离，主要断言不是同义反复。

### 5.2 设备/运行时证据诚实性

- `SecurityHost.test.ets` 明确标注以编译为主、执行 `BLOCKED`；`hvigorw test` 证据停在 `> hvigor Linux`，未伪造 `test_result.txt`。
- `SecurityDevice.test.ets` 文件头和 suite 名标注 `BLOCKED_ON_DEVICE_RUNNER`；报告 §4.3/§6.1 未把设备向量写成 PASS。
- **但**：设备测试聚合入口未注册（R-04）；设备 GCM 向量本身错误（R-03）；因此“设备 runner 复跑同一组向量”目前不是可直接执行的证据链。
- `code-linter.json5` 明确忽略 `src/test`/`src/ohosTest`，测试源码没有 lint 证据；这是 TEST-001 §2.4 的已知策略，不把 `codelinter PASS` 扩写为测试代码 PASS。

### 5.3 证据/文档一致性

- `t07-host-node-tests.tap`、`t07-codelinter.log`、`t07-hvigor-assemble.log`、`t07-hvigor-test-compile.log` 与实现报告 §5 的命令/退出码/结果一致。
- `entry/src/test/README.md` 仍为 88/88（R-05）；实现报告文件数 7/6 与实际 6/5 不一致（R-06）。
- 实现报告 §3.4 对 V-01 12-hex 夹具差异的记录准确：oracle 使用夹具原值，生成侧强制 32-hex；该差异不改变 canonical/HMAC 结论，应转 T-19 明确互操作口径。

---

## 6. 安全纪律、契约边界与过程

### 6.1 安全纪律

- **无伪造签名/密钥**：产品代码没有硬编码 expectedSign、secret 或伪造密钥；grep 未命中 V-01/response 的 expectedSign；测试使用 `PUBLIC TEST DATA ONLY`。
- **无秘密日志/异常文本泄漏**：产品 crypto/security 无 `console`/`hilog`/`print`；`CryptoProviderError` 只暴露 kind；`AppError` message 为稳定 code，details 只含字段名；平台 message/code 未进入用户文本（R-01 是分类问题，不是泄漏）。
- **fail-closed 完整**：response 验签失败、correlation 失败、sign 形状错误、body 篡改、CTR 失败、GCM tag 失败、随机失败、X25519 全零共享秘密均抛稳定 AppError；未发现降级/跳过/乐观成功路径。
- **随机源**：生产使用 `cryptoFramework.createRandom()`；未使用 `Math.random`；`CryptoService.randomBytes` 校验长度精确且拒绝全零；nonce/challenge 32-hex。
- **常数时间**：`constantTimeEqual` 遍历最大长度、长度差并入累加器、无提前返回；response verifier 使用它；未用字符串 `===` 比较签名。
- **秘密生命周期**：无长期 key 缓存；HMAC/AES 的 `SymKey` 在正常路径清理；GCM 初始化失败与 X25519 私钥 DER 临时副本存在 R-02 缺口。
- **GCM 边界**：只实现邀请容器所需原语；无 LAN GCM 分支、无 `cmd_id=2002`；`EXT-GCM-001` 保持归档；与 ADR-002 §5/ADR-003 一致。

### 6.2 契约/架构边界

- C-04/C-05 不 import UI/`@ohos`（`OhosCryptoProvider` 唯一平台适配）；`service/security` 只依赖 `CryptoPort`/common，依赖方向正确。
- C-03 未被修改；ACK 判定链仍由 C-03/C-17 持有；C-05 只提供验签/correlation。
- 端口物理位置与构造 seam 是已记录偏差（R-08）；无第二套端口/实现；T-06 R-13 迁移计划仍开放。
- 无网关 replay cache、无 DEV-ONLY/HTTP 处理、无云完成判定；这些明确留给 C-17/C-20/C-15。
- i18n：本任务无用户可见文案；错误使用稳定 code/i18n key；无重复 codebase；CHK-01..09 仍由 C-14/T-10 负责。

### 6.3 过程与仓库

- 23 个变更路径均在 `commit_paths` 内；未发现越界修改、构建产物、HAP、证书、Token、真实 secret。
- `git status --short` 在评审前 clean；`git diff --check` 无输出；构建输出均被 ignore。
- 实现报告 Producer 为 `agent:implementation-engineer`；本报告 Producer 为 `agent:quality-reviewer`。
- 实现 handoff 的 `snapshot_paths` 未含产品目录（观察 8）；本次评审 snapshot 覆盖 `service/crypto|security`、测试、设备骨架与 `artifacts/`。

---

## 7. CQG-T07 检查项对照

> CQG-T07 最小必填（TEST-001 §4.3）：V-01..V-03 全通过、RFC7748、CTR 流、±120s/300s 负例、常数时间审查、SEC 记录。

| 检查项 | 结果 | 说明 |
|---|---|---|
| 构建 | **PASS** | `hvigorw clean assembleHap --no-daemon` exit 0；unsigned HAP warning。 |
| lint（产品源码） | **PASS** | `codelinter` No defects；测试源码不在 lint 范围。 |
| Node host | **PASS 118/118** | 复跑通过；新增 30 用例。 |
| V-01/V-02/V-03 | **PASS** | 4/4 + 1/1 + 1/1；Node oracle 独立。 |
| ±120s/300s/负例 | **PASS（App 侧）** | 时间窗、TTL、correlation、nonce 重试/负例通过；网关 replay cache 不在本组件。 |
| 常数时间审查 | **PASS（行为/代码）** | 无提前返回、无签名 `===`；未做统计时序（T-19/设备）。 |
| RFC7748/CTR/GCM 真实平台 | **BLOCKED / COMPILED_ONLY** | 设备无签名/无设备；设备骨架已编译；R-03 向量错误必须先修；R-04 未注册。 |
| SEC 记录 | **PARTIAL** | Host 测试覆盖 SEC-N07/N08/N26 的 App 侧行为；测试计划状态未由 T-07 更新，T-19 汇总。 |
| i18n | **NOT_APPLICABLE** | 无 UI/文案；无重复 codebase。 |
| 独立评审 | **本报告** | 作者之外；只读；CHANGES_REQUIRED。 |
| CQG-T07 总体 | **NOT PASS / CHANGES_REQUIRED** | 代码级证据良好，但 R-01/R-02/R-03 未解决；设备层仍 BLOCKED。 |

---

## 8. Verdict

**CHANGES_REQUIRED**

理由：

1. **无 Critical/High 远程可利用缺陷**：未发现可伪造 HMAC、绕过 response 验签、泄露 secret 到日志/用户文本、乐观成功或秘密入库的直接路径；host/lint/build 通过，公开向量复算正确。
2. **R-01（Medium，产品代码）**：`OhosCryptoProvider` 的 create/init/key-conversion/GCM decrypt 错误分类与 DES-A §7.2 不一致；这不是风格偏好，而是冻结错误表。虽然 fail-closed 未被破坏，错误类别/i18n/重试语义会偏离契约，且实现报告已自行标记该风险。要求修复。
3. **R-02（Medium，安全生命周期）**：GCM 初始化失败路径未清理已创建的 `SymKey`，X25519 私钥 DER 临时副本未清零；违反 SC-06/DES-A §3.5/§7.3-1。修复成本低，应在 CQG-T07 前完成。
4. **R-03（Medium，测试证据）**：设备侧 GCM tag 向量错误，首次设备运行必然失败；且未断言明文内容。该测试是 CQG-T07 的设备证据路径，必须在设备可用前修正。
5. **R-04..R-08（Low）**：设备聚合注册、README/报告计数、X25519 前缀可变、端口/构造 seam 偏差；应在同一次修复或 Gate 记录中处理。
6. **C-04/C-05 保持 `UNVERIFIED`**：本报告不授予 PASS、STABLE、CQG-T07 完成、Stage Gate 或用户验收。修复后必须由作者之外的评审者复审；设备证据仍需 T-19/T-12 在真实环境复跑。

---

## 9. 残余风险与后续跟踪

| ID | 风险 | 影响 | 后续动作 |
|---|---|---|---|
| T07-RISK-01 | 真实 `cryptoFramework` 算法名/API 行为未运行 | 设备首次运行可能失败（HMAC/KDF/X25519/CTR/GCM/随机） | T-19/T-12：设备 runner 复跑 `SecurityDevice.test`；先修 R-03、接线 R-04 |
| T07-RISK-02 | `createCipher`/`clearMem`/`createRandom` 的 syscap warning | 某些设备可能不支持 API 或清理调用失败 | 设备验证；按 BusinessError 细化 R-01；准备受控降级/错误映射 |
| T07-RISK-03 | GCM `authTag`/`GcmParamsSpec` 的平台行为未验证 | 邀请容器加密/解密可能在设备上失败 | T-13/T-19 设备向量；保持 GCM 仅邀请 |
| T07-RISK-04 | X25519 DER↔raw 平台接受度未验证 | BLE Security1/邀请 KEY_WRAP 可能失败 | T-12/T-19 RFC 7748 设备向量；R-02 DER 清零 |
| T07-RISK-05 | 无网关 replay cache / 精确重传编排 | 重放/幂等仍无端到端证据 | T-11/T-17/C-20；C-05 只做 App 出站 nonce 防护 |
| T07-RISK-06 | 未测常数时间时序 | 代码/行为审查不能证明统计时序 | T-19/安全评审；必要时设备/基准测量 |
| T07-RISK-07 | V-01 夹具 12-hex nonce 与生成 32-hex 的互操作口径 | 联调/向量复用可能二义 | T-19 明确“夹具历史值 vs 生产 32-hex”；不得放宽生成侧 |
| T07-RISK-08 | 设备测试未注册/设备 GCM 向量错误 | CQG-T07 设备证据链不完整 | T-19/T-12：修 R-03、接线 R-04；保持 `BLOCKED` 直到真跑 |
| T07-RISK-09 | 端口/构造 seam 偏差未迁移 | 后续 import 位置可能分叉 | C-17/T-17 迁移 `contracts/**`；Gate 记录例外；不要复制实现 |
| T07-RISK-10 | 测试 README/实现报告计数陈旧 | T-19 可能误读证据 | R-05/R-06 更新；T-19 复核 |
| T07-RISK-11 | 云 canonical/ACK 集成未验证 | T-14/T-11 可能发现字段/顺序差异 | C-15/T-11 使用本 canonical；T-19 全量 |
| T07-RISK-12 | `X25519KeyCodec` 公开前缀可被外部改写 | DER 包装错误/协议失败 | R-07 处理；C-17 组装审查 |

---

## 10. 独立评审声明与边界

- **独立性**：本报告由 `agent:quality-reviewer` 编写；评审者不是 T-07 的实现者，未参与被测代码编写，未修改任何被测文件；唯一写入是本报告。作者不能批准本报告或自行关闭评审。
- **只读边界**：主机复验与构建只修改被 ignore 的构建输出；`git status --short` 在写入前 clean；`finish` 将再次校验 snapshot 字节覆盖与提交范围。
- **范围边界**：结论仅覆盖 `ee67879` 的 T-07 diff 与 §1 范围；不覆盖 T-11/T-12/T-13/T-14/T-17/T-19/T-20 的完整集成、设备、性能、云、UI/用户验收。
- **证据边界**：`hvigorw test`/`onDeviceTest` 未在本次重跑；报告不把 `COMPILED_ONLY`/`BLOCKED` 写成 PASS。设备侧结论必须在设备环境重新执行同一组向量后才能更新。
- **Gate 边界**：本报告不授予 CQG-T07 PASS、C-04/C-05 STABLE、Stage Gate 或用户验收；修复后需作者之外的复审与新的验证证据。

---

*Reviewer: agent:quality-reviewer | Revision: ee67879 | Verdict: CHANGES_REQUIRED*
