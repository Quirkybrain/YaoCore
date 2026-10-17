# T-07 独立复审报告（R-01..R-08 关闭确认）

- **Artifact ID**: REV-T07-002
- **Producer**: agent:quality-reviewer
- **Type**: Independent Code Review / CQG-T07 Re-review Evidence
- **Status**: PASS（代码级复审通过；不授予 CQG-T07 总体 PASS、C-04/C-05 STABLE、Stage Gate 或用户验收）
- **Date**: 2026-10-17
- **Task**: `wp-019-review-t07b`（task 分支 `task/wp-016-security`，父分支 `feat/yaocore-app`）
- **Reviewed revision**: `11a291c3d4000435a0d07c2a733245dc4c21c807`（修复提交；父 `df13b29386c3f15dbe5cfe7b103819308b21dcd8` 为上轮评审报告，再父 `ee678793b91f79c30e086b983c48b954395c9350` 为 T-07 实现）
- **Review base**: `11a291c`（`git diff df13b29..11a291c`）
- **Review snapshot**: `refs/swe/snapshots/20261017T084908Z-wp-019-review-t07b-4f5aa4af`（覆盖 `entry/src/main/ets/service/crypto/`、`service/security/`、`entry/src/test/`、`entry/src/ohosTest/ets/test/`、`artifacts/50-implementation/t07-fix-report.md` 与本报告）
- **Workflow**: STANDARD / GATED_AUTO
- **Independence**: 本报告由未参与 T-07 实现与 wp-018 修复的 `agent:quality-reviewer` 编写；作者为 `agent:implementation-engineer`。本报告只读代码，不修改被审文件，唯一写入是本报告。

> 结论先行：上轮 R-01..R-07 已按修复报告关闭；R-08 以已书面记录的位置例外关闭并继续跟踪。R-01 的错误分层、R-02 的秘密清零、R-03 的设备 GCM 向量、R-04 的设备套件注册、R-05/R-06 的文档计数、R-07 的前缀防御性副本均可在当前 revision 复核。独立复跑 `122/122`、`codelinter`、`hvigorw clean assembleHap` 全部通过，未发现新的 Critical/High/Medium 代码缺陷。仅发现 1 项非阻塞的 Low 文档一致性问题（R2-01）。设备/真实 `cryptoFramework` 运行仍为 `COMPILED_ONLY` / `BLOCKED_ON_DEVICE_RUNNER`，本报告不把设备证据写成 PASS。

---

## 1. 复审范围、输入与方法

### 1.1 范围与 revision

| 项 | 内容 |
|---|---|
| 被审提交 | `11a291c`（16 路径，+1581/-72） |
| 上轮评审 | `artifacts/70-review/t07-review.md`（REV-T07-001，`CHANGES_REQUIRED`，R-01..R-08） |
| 修复报告 | `artifacts/50-implementation/t07-fix-report.md`（IMP-T07-FIX-001，`Proposed`） |
| 实现报告 | `artifacts/50-implementation/t07-security.md` |
| 产品代码 | `entry/src/main/ets/service/crypto/`：`CryptoErrorClassifier.ets`（新增）、`OhosCryptoProvider.ets`、`X25519KeyCodec.ets`、`CryptoPort.ets` |
| 测试 | `entry/src/test/host/Crypto.test.mjs`（+4 用例）、`entry/src/test/README.md`；`entry/src/ohosTest/ets/test/List.test.ets`、`security/SecurityDevice.test.ets`、`README.md` |
| 证据 | `entry/src/test/evidence/t07-fix-*` |
| 未修改（已核对） | `service/security/**`、`common/**`、`model/**`、`service/protocol/**`、构建配置、`input/**` |

`git show --name-status 11a291c` 与 `git diff --stat df13b29..11a291c` 核对：16 个路径均在复审 target 与 `artifacts/50-implementation/` 内；`service/security/**` 无代码改动，未发现越界修改或第二套实现。

### 1.2 权威输入 pin

`python3 scripts/swe_guard.py begin state/handoffs/wp-019-review-t07b.json` 与 `sha256sum` 均核对通过：

| 输入 | SHA-256（与 handoff 一致） |
|---|---|
| `artifacts/70-review/t07-review.md` | `493ff3e136c0b5d603adf170bfffcf9a771ca7793c70c92c6beb62a85f98f9de` |
| `artifacts/50-implementation/t07-fix-report.md` | `c95bbf3f33169eb5061b965aed1cb763c7776e15a7660732e5c686e2b5f7cd79` |
| `artifacts/50-implementation/t07-security.md` | `a48099f8d96d9e9b275213dfe71340a8e3be948668eee347d2e55aa12a001e53` |
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `5599e693fafe405443c5d28efaec0bd2091064eee5c3f1a619dc22d3dcbfe1c1` |
| `artifacts/20-architecture/contract-baseline.md` | `6673a990d5020c0b70dd4ae30bd75fa13d33d4d573a4d953961371296fadee89` |
| `artifacts/20-architecture/project-constraints.md` | `283046210e68dfbce9119abbbac849bd1f9a23cf7ef2fb51dcb4aa1e23da9528` |
| `artifacts/60-testing/test-plan.md` | `33485cc39abd9a917e94b6568b29e162cd90897adfad509e3f59403a56055fae` |

### 1.3 方法

1. Diff first：先读 `df13b29..11a291c` 的 16 个路径，再读 `CryptoErrorClassifier`、`OhosCryptoProvider`、`X25519KeyCodec`、`CryptoService` 及测试上下文。
2. 逐条对照 DES-A §7.2/§7.3/§7.4、CB §4.2、PC SC-04/05/06/13/15、TEST-001 §4.3/§5。
3. 追踪 GCM/HMAC/CTR/DER 的成功、失败、提前返回、`finally` 与所有权转移路径；核对每个平台调用前的 `CryptoFailureStage`。
4. 独立复算 AES-256-GCM 16B 零明文向量，核对设备断言。
5. 只读复验：`entry/src/test/run-host-tests.sh`、`codelinter -c code-linter.json5 -p default .`、`hvigorw clean assembleHap --no-daemon`、附带的 `ohosTest assembleHap`、`git diff --check` / `git show --check`。
6. 安全扫描：产品代码无 `console`/`hilog`/`Math.random`；`@ohos.security.cryptoFramework` 仍仅在 `OhosCryptoProvider`；`TestCryptoProvider`/`FakeCryptoPort` 未被 main import；变更文件未发现真实 secret/私钥。

> 评审者未修改任何被测文件；构建只产生被 `.gitignore` 忽略的 `entry/build` 与 `.hvigor` 输出。写入本报告前 `git status --short` 为空。

---

## 2. 独立复验结果

| 命令 | 本次结果 | 与修复报告/证据对比 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS 122/122**，`# fail 0`，exit 0；两次复跑 `duration_ms` 1155.039528 / 1491.701167 | 与 `t07-fix-host-node-tests.tap` 的 122/122、`duration_ms 1093.669064` 结果一致；时间波动正常 |
| `codelinter -c code-linter.json5 -p default .` | **PASS**，`No defects found in your code.`，exit 0 | 与 `t07-fix-codelinter.log` 一致 |
| `hvigorw clean assembleHap --no-daemon` | **PASS**，`BUILD SUCCESSFUL in 5 s 419 ms`，35 tasks（34 executed / 1 up-to-date），exit 0；仅 unsigned HAP warning | 与 `t07-fix-hvigor-assemble.log` 一致 |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **PASS**，`BUILD SUCCESSFUL in 6 s 903 ms`，35 tasks，exit 0 | 与 `t07-fix-ohosTest-assemble.log` 一致；验证 R-04 注册可编译 |
| `git diff --check` / `git show --check 11a291c` | 无输出，exit 0 | 无空白错误 |
| `git status --short`（写入本报告前） | clean | 无未提交构建产物/测试改动 |
| `hvigorw test` / `onDeviceTest` | **未重跑**；设备/Previewer 仍为 `BLOCKED` | 不把 `COMPILED_ONLY`/`BLOCKED` 写成 PASS |

测试计数核对：`Crypto.test.mjs` 18 个用例（T-07 原 14 + 本次新增 4），`Security.test.mjs` 16 个，其余 host 用例 88 个，合计 **122**。新增 4 个用例均出现在 TAP 的 `ok 14..17`，名称与修复报告 §2.2 一致。

独立 GCM 复算（Node `crypto`，key=32B zero、iv=12B zero、AAD 空、plaintext=16B zero）：

```text
ciphertext = cea7403d4d606b6e074ec5d3baf39d18
tag        = d0d1c8a799996bf0265b98b5d48ab919
```

与 `SecurityDevice.test.ets:99-103` 的期望值一致；`d0d1...` 对应 16B 零明文，`530f...` 是空明文 tag，原 R-03 已修正。

---

## 3. R-01..R-08 关闭状态

| ID | 上轮 finding | 本次核查证据 | 关闭状态 |
|---|---|---|---|
| **R-01** | 错误分类不完整，create/init/key conversion/operation/GCM tag 被统一误映射 | 新增 `CryptoErrorClassifier.ets`：`CREATE→UNAVAILABLE`、`KEY_CONVERSION→INVALID_KEY`、`OPERATION→OPERATION_FAILED`、`GCM_DECRYPT_FINAL` 仅平台 code `17630001→AUTH_TAG`（`CryptoErrorClassifier.ets:25-55`）。逐调用核对：`createMd/createMac/createSymKeyGenerator/createKdf/createCipher/createRandom/createAsyKeyGenerator/createKeyAgreement` 均在 `CREATE`；`convertKeySync/getEncoded` 与 X25519 DER codec 在 `KEY_CONVERSION`；`initSync/updateSync/doFinalSync/generateSecret/generateKeyPairSync/generateRandomSync` 在 `OPERATION`（`OhosCryptoProvider.ets:77-343`）。既有 `CryptoProviderError` 保留原 kind（`CryptoErrorClassifier.ets:41-43`）。host 新增 3 个相关用例并全部通过 | **Closed**（带设备假设） |
| **R-02** | GCM 初始化失败未清 `SymKey`；X25519 私钥 DER 临时副本未清零；HMAC/CTR 路径需覆盖 | GCM `encryptAesGcm`/`decryptAesGcm` 的 `symKey` 在整个函数作用域 `finally` 中 `clearMem()`，覆盖 convert/createCipher/init/doFinal/长度校验所有路径（`OhosCryptoProvider.ets:261-331`）；HMAC 保留统一 `finally`（91-111）；`importX25519PrivateRaw` 的 PKCS#8 DER 在 `finally` 中 `fill(0)`，成功/失败/异常均覆盖（169-187）；CTR `process` 失败即 `destroy()`，创建成功时所有权转移给 stream、失败时 `finally` 清理（48-75, 234-259）；`AesCtrStreamImpl` 失败仍置 `BROKEN`（`CryptoService.ets:301-316`）。`SecurityDevice.test.ets:119-125` 增加失败后再次成功解密的设备骨架断言 | **Closed（代码级）**；`clearMem` 可观测性与 Heap 证据留 T-19 |
| **R-03** | 设备 GCM tag 向量错误且未断言明文 | 期望 tag 改为 `d0d1c8a799996bf0265b98b5d48ab919`（`SecurityDevice.test.ets:101-103`）；新增 `opened` 逐字节 `00000000000000000000000000000000` 断言（104-107）；篡改 tag 仍断言 `CRYPTO_TAG_MISMATCH`（109-117）。Node 独立复算一致 | **Closed**；设备执行仍 `BLOCKED` |
| **R-04** | 设备套件未注册进 `ohosTest/List.test.ets` | `List.test.ets:10-17` 注册 `baselineTest()`、`foundationDeviceTest()`、`securityDeviceTest()`；`ohosTest assembleHap` 复跑通过。注册只表示设备可用时会执行，未写成 PASS | **Closed（接线/编译）**；执行仍 `BLOCKED` |
| **R-05** | README 仍写 88/88，目录树缺 T-07 文件 | `entry/src/test/README.md:61` 当前 revision 为 **122/122 PASS**；目录树补齐 `Crypto.test.mjs`、`Security.test.mjs`、`TestCryptoProvider.ets`、`foundation/`、`protocol/`、`security/`；§4 表格为 122/122。实际 host 用例 122 个与证据一致 | **Closed** |
| **R-06** | 实现报告 C-04/C-05 文件数 7/6 与实际 6/5 不符 | `t07-security.md:26-27` 改为 6/5；§1.1 标题改为“T-07 时 6 文件”，并加勘误说明修复后 crypto 目录 7 个、测试数 118→122（55-57）；§5 的 118/118 标注为 T-07 revision 证据（233）。实际目录：T-07 时 C-04 6 文件、C-05 5 文件；修复后 C-04 7 文件（新增分类器） | **Closed**（计数）；另有 R2-01 文档残留 |
| **R-07** | `SPKI_PREFIX`/`PKCS8_PREFIX` 为可变 public 数组 | 改为 `private static readonly *_PREFIX_BYTES` backing array；公开 `static get SPKI_PREFIX/PKCS8_PREFIX` 每次返回 `BytesUtil.copyOf` 副本；codec 内部只用私有数组（`X25519KeyCodec.ets:13-55`）。host `C04_X25519KeyCodec_prefixesAreDefensiveCopies` 先改写返回副本再验证 DER 输出未被污染，测试通过 | **Closed** |
| **R-08** | `CryptoPort` 位置与 `CryptoService` 构造 seam 为已记录偏差 | `CryptoPort.ets:5-12` 头注释记录位置例外与 C-17 迁移计划；`t07-security.md:252-257` 记录端口位置/构造 seam；修复报告 §4 记录理由与跟踪。全仓仅一个 `CryptoPort.ets`、一个 `OhosCryptoProvider`，无第二套端口/实现 | **Closed（例外已记录）**；迁移仍由 C-17/T-19 跟踪 |

### 3.1 R-01 判读说明

- 修复将 `initSync` 失败归 `OPERATION_FAILED`，将 `createCipher`/`createKdf` 等原语创建失败归 `CRYPTO_UNAVAILABLE`。这与上轮 R-01 给出的修复方向（创建失败→UNAVAILABLE、key 转换→INVALID_KEY、操作→OPERATION_FAILED）一致；DES-A §7.2 的“cryptoFramework 不可用/初始化失败”按“原语/算法初始化”理解，而非每个 `initSync` 调用的参数/操作失败。该判读已在修复报告 §1.1 记录。
- GCM tag 依赖平台 code `17630001`（`cryptoFramework.Result.ERR_CRYPTO_OPERATION`）的假设已在 `CryptoErrorClassifier.ets:17-18,32-33` 注释和修复报告 `FIX-RISK-02` 明确标注；设备测试会先断言 `CRYPTO_TAG_MISMATCH`，若实测 code 不同则失败并暴露分类偏差，不会静默 fail-open。
- `CryptoErrorClassifier.ets:10` 注释将 `CREATE` 描述为包含 “initialisation failure”，但代码把 `initSync` 放在 `OPERATION`；这是注释措辞与实现的细节差异，不改变运行时行为，列入 R2-01 供后续澄清。

---

## 4. 新发现

| ID | 严重度 | 位置 | 问题 | 影响/建议 |
|---|---|---|---|---|
| **R2-01** | **Low（非阻塞，文档一致性）** | `artifacts/50-implementation/t07-security.md:279,282`；`entry/src/main/ets/service/crypto/CryptoErrorClassifier.ets:10` | 实现报告 §7 风险表仍把已修复问题写成开放风险：第 279 行称 “`OhosCryptoProvider` create 失败统一映射 `CRYPTO_INVALID_KEY`”，第 282 行称 “`X25519KeyCodec` 静态前缀数组可变”；二者在 `11a291c` 已分别由 R-01/R-07 修复。分类器注释把 `CREATE` 描述为包含 “initialisation failure”，而 `initSync` 实际归 `OPERATION`。 | 不改变代码、契约或当前测试结论；但 T-19/Gate 读者可能误读当前错误语义或前缀生命周期。建议后续 doc-only 更新（可在 T-19 汇总时）把两行标记为已修复并指向修复报告，同时把 `CREATE` 注释改为“primitive/algorithm creation”，明确 `initSync` 属 `OPERATION`。 |

未发现新的 Critical/High/Medium 代码级缺陷；未发现伪造签名、秘密日志、乐观成功、fail-open 或第二套实现。

---

## 5. CQG-T07 检查项对照

> CQG-T07 最小必填（TEST-001 §4.3）：V-01..V-03 全通过、RFC7748、CTR 流、±120s/300s 负例、常数时间审查、SEC 记录。

| 检查项 | 结果 | 说明/证据 |
|---|---|---|
| 构建 | **PASS** | `hvigorw clean assembleHap --no-daemon` exit 0；35 tasks；unsigned warning |
| lint（产品源码） | **PASS** | `codelinter` exit 0，`No defects found`；`src/test`/`src/ohosTest` 仍按配置不在 lint 范围 |
| Node host 测试 | **PASS 122/122** | 独立复跑 `# fail 0`；Crypto 18 / Security 16 / 其余 88；新增 4 用例通过 |
| V-01/V-02/V-03 | **PASS（host）** | TAP：`ok 49`（4/4 control）、`ok 50`（response）、`ok 51`（discovery）；与上轮一致 |
| RFC7748 / CTR / GCM | **PARTIAL / BLOCKED（设备项）** | X25519 DER↔raw、CTR 流、GCM tag/长度负例在 host 通过；真实 `cryptoFramework` 设备运行仍 `BLOCKED_ON_DEVICE_RUNNER`。R-03 向量已修正、R-04 已注册并可编译，但未执行 |
| ±120s/300s 负例 | **PASS（App 侧）** | C-05 host 用例继续通过；网关 replay cache/失败不消耗 nonce 属 C-20/T-11 |
| 常数时间审查 | **PASS（代码/行为）** | `constantTimeEqual` 仍无提前返回；未做统计时序测量（T-19/设备） |
| 契约一致性 | **PASS** | DES-A §7.2 错误分层、§7.3 清理/流状态、§7.4 seam 与 §8 语义均未被破坏；§8 无代码改动 |
| 安全纪律 | **PASS** | fail-closed 保持；GCM/HMAC/CTR/DER 清理覆盖；无 `console`/`hilog`/`Math.random`；平台 message/code 不进入用户文本；无真实 secret |
| 分层/依赖方向 | **PASS** | `CryptoErrorClassifier` 纯函数、无 `@ohos` import；`OhosCryptoProvider` 仍是唯一平台 import；无第二套端口/实现 |
| SEC 记录 | **PARTIAL** | Host 覆盖 SEC-N07/N08/N26 的 App 侧行为；T-19 汇总设备/全量记录 |
| i18n | **NOT_APPLICABLE** | 本任务无用户可见文案；无重复 codebase |
| 独立评审 | **本报告** | 作者之外、只读复核；结论见 §6 |
| 设备 BLOCKED 边界 | **BLOCKED** | 无设备/签名，`onDeviceTest` 未执行；不得把注册/编译写成 PASS |
| CQG-T07 总体 | **代码级条件满足；设备项 BLOCKED** | 建议 Gate 明确记录“代码级复审通过、设备证据待 T-19/T-12 复跑”，不写成 CQG-T07 完成或 C-04/C-05 STABLE |

---

## 6. Verdict

**PASS（代码级复审通过；可进入 CQG-T07 裁决/合并流程）**

理由：

1. **R-01..R-07 全部关闭**：错误分层、秘密清理、设备 GCM 向量、设备套件接线、README/报告计数、前缀防御性副本均有代码/测试/证据对应；R-08 作为已书面记录的位置例外继续跟踪，未发现第二套实现。
2. **无新的阻塞缺陷**：122/122、lint、主 HAP 构建、ohosTest 编译均通过；错误分类改动未破坏既有 host 测试或 C-05 语义；未发现 fail-open、秘密泄漏或伪造签名。
3. **仅 1 项 Low 文档一致性**（R2-01）：不涉及代码行为、契约或安全边界，建议后续文档更新或 T-19 汇总时修正，不阻塞本次复审。
4. **边界**：本 PASS 仅覆盖 `11a291c` 的代码级复审与 R-01..R-08 关闭；**不授予** CQG-T07 总体 PASS、C-04/C-05 `STABLE`、Stage Gate 或用户验收。设备/真实平台证据仍为 `BLOCKED`，CQG-T07 的设备向量项必须保持 BLOCKED，待 T-19/T-12 在设备环境复跑后关闭。

---

## 7. 残余风险与后续跟踪

| ID | 风险 | 影响 | 后续动作 |
|---|---|---|---|
| T07B-RISK-01 | GCM tag 分类依赖平台 code `17630001` | 若设备实际返回其他 code，tag mismatch 可能落到 `CRYPTO_OPERATION_FAILED`（仍 fail-closed） | 设备测试已断言 `CRYPTO_TAG_MISMATCH`；T-19/T-12 首次设备运行按实测扩展分类器 |
| T07B-RISK-02 | `clearMem()` 在 ArkTS 不可观测 | 无法用 host 证明平台秘密已清零 | `SecurityDevice.test` 增加失败后可用性断言；Heap/内存证据留 T-19 |
| T07B-RISK-03 | `clearMem()` 若自身失败，可能覆盖原始错误（既有风险，非本次引入） | provider 可能抛出平台错误而非稳定 `CryptoProviderError`；`CryptoService` 仍 fail-closed | 设备验证 `clearMem` syscap/行为；必要时在 `finally` 内捕获并保持原错误 |
| T07B-RISK-04 | 设备套件仅注册/编译，未执行 | 真实 `cryptoFramework` 算法名、X25519 DER、CTR/GCM/随机行为无设备 PASS | T-19/T-12 连接设备+签名后执行 `onDeviceTest`；在此之前保持 `BLOCKED` |
| T07B-RISK-05 | SEC 记录/统计时序未汇总 | CQG-T07 的全量 SEC 证据不完整 | T-19 汇总；必要时设备/基准测量 |
| T07B-RISK-06 | R-08 端口位置例外未迁移 | 后续 import 位置可能分叉 | C-17 组合根迁移到 `contracts/**`；保持单套实现 |
| T07B-RISK-07 | R2-01 文档残留 | T-19 可能误读当前错误/前缀状态 | doc-only 更新 §7 两行与 `CREATE` 注释 |

---

## 8. 独立评审声明与边界

- **独立性**：本报告由 `agent:quality-reviewer` 编写；评审者不是 T-07 实现者，也不是 wp-018 修复作者；未参与被测代码编写，未修改任何被测文件；唯一写入是本报告。作者不能批准本报告或自行关闭本复审。
- **只读边界**：复验命令只产生被 ignore 的构建输出；写入前 `git status --short` 为 clean；`finish` 将再次校验 snapshot 字节覆盖与提交范围。
- **范围边界**：结论仅覆盖 `11a291c` 的修复 diff、R-01..R-08 与所列复审 target；不覆盖 T-11/T-12/T-13/T-14/T-17/T-19/T-20 的完整集成、设备、性能、云、UI/用户验收。
- **证据边界**：`hvigorw test`/`onDeviceTest` 未在本次重跑；报告不把 `COMPILED_ONLY`/`BLOCKED` 写成 PASS。设备侧结论必须在设备环境重新执行同一组向量后才能更新。
- **Gate 边界**：本报告授予 **代码级复审 PASS**，不授予 CQG-T07 总体 PASS、C-04/C-05 `STABLE`、Stage Gate 或用户验收；设备证据项仍为 `BLOCKED`。

---

*Reviewer: agent:quality-reviewer | Revision: 11a291c | Verdict: PASS (code-level; device BLOCKED)*
