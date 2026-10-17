# T-07 评审修复报告（R-01..R-08）

- **Artifact ID**: IMP-T07-FIX-001
- **Producer**: agent:implementation-engineer
- **Type**: Implementation Fix / Verification Evidence
- **Status**: Proposed（修复完成；待作者之外的评审者复审，未授予 PASS/STABLE）
- **Date**: 2026-10-17
- **Task**: `wp-018-fix-t07`（task 分支 `task/wp-016-security`，父分支 `feat/yaocore-app`，base commit `df13b29386c3f15dbe5cfe7b103819308b21dcd8`）
- **Workflow**: STANDARD / GATED_AUTO
- **Inputs（pinned）**:
  - `artifacts/70-review/t07-review.md`（REV-T07-001，CHANGES_REQUIRED）
  - `artifacts/50-implementation/t07-security.md`（IMP-T07-SECURITY）
  - `artifacts/40-detailed-design/des-001a-foundation-transport.md` §7/§8/§18
  - `artifacts/20-architecture/contract-baseline.md` §2.5/§3/§4
  - `artifacts/20-architecture/project-constraints.md`（SC-04/05/06/13/15）
  - `artifacts/60-testing/test-plan.md` §4/§5
- **Write scope**: `entry/src/main/ets/service/crypto/`、`entry/src/main/ets/service/security/`、`entry/src/test/`、`entry/src/ohosTest/ets/test/`、`artifacts/50-implementation/`
- **组件状态**: C-04/C-05 保持 `UNVERIFIED`；本次修复不改变该状态，等待复审与设备证据。

---

## 0. 结论摘要

| 项 | 结果 |
|---|---|
| R-01..R-07 | **Fixed**（见 §1） |
| R-08 | **Exception（书面记录，继续跟踪）**（见 §1） |
| Node host 测试 | **PASS 122/122**（T-07 的 118 + 本次新增 4） |
| `ohpm install` | **PASS**（exit 0） |
| `hvigorw clean assembleHap --no-daemon` | **PASS**（BUILD SUCCESSFUL，35 tasks） |
| `codelinter -c code-linter.json5 -p default .` | **PASS**（No defects found） |
| 设备侧 `SecurityDevice.test` / `FoundationDevice.test` | **COMPILED_ONLY / BLOCKED_ON_DEVICE_RUNNER**（无设备、无签名；不写成 PASS） |

本次修复不改变 canonical/签名/验签语义、ACK 判定链、32-hex nonce 生成契约，也未新增 LAN GCM 分支。`service/security/**` 无代码改动。

---

## 1. 逐条处置

| ID | 严重度 | 处置 | 位置 | 测试/证据 |
|---|---|---|---|---|
| **R-01** | Medium | **Fixed** | 新增 `CryptoErrorClassifier.ets`；`OhosCryptoProvider.ets` 每个平台调用显式标注 `CryptoFailureStage` | `C04_CryptoErrorClassifier_mapsDesAErrorTable`、`C04_CryptoErrorClassifier_preservesExplicitProviderKind`、`C04_CryptoService_gcmOperationFailureIsNotTagMismatch` |
| **R-02** | Medium | **Fixed** | `OhosCryptoProvider.ets` GCM/HMAC/CTR/DER 清理路径；`SecurityDevice.test.ets` 设备断言骨架/注释 | host 行为回归 + 设备骨架断言；`clearMem` 不可直接观测，设备 Heap 证据留 T-19 |
| **R-03** | Medium | **Fixed** | `SecurityDevice.test.ets` GCM 向量与明文断言 | Node `crypto` 复算见 §2.1；保持 `BLOCKED_ON_DEVICE_RUNNER` |
| **R-04** | Low | **Fixed** | `entry/src/ohosTest/ets/test/List.test.ets` 注册 foundation + security 套件 | `t07-fix-ohosTest-assemble.log`（编译 PASS；执行仍 BLOCKED） |
| **R-05** | Low | **Fixed** | `entry/src/test/README.md` 更新为当前 122/122 与目录/覆盖说明 | `t07-fix-host-node-tests.tap` |
| **R-06** | Low | **Fixed** | `artifacts/50-implementation/t07-security.md` 修正 C-04/C-05 文件数为 6/5，并记录测试数勘误 | 本报告 §2.2 |
| **R-07** | Low | **Fixed** | `X25519KeyCodec.ets` 前缀改为私有 backing array + 公开 getter 返回副本 | `C04_X25519KeyCodec_prefixesAreDefensiveCopies` |
| **R-08** | Low | **Exception（记录并继续跟踪）** | `CryptoPort.ets` 位置与 `CryptoService` 构造 seam 保持现状 | 见 §4；C-17/T-19 迁移 |

### 1.1 R-01 错误分类（DES-A §7.2）

新增 host 可测的纯函数 `classifyCryptoFailure(stage, error)`（`entry/src/main/ets/service/crypto/CryptoErrorClassifier.ets`），provider 在每次平台调用前显式设置阶段：

| 阶段 | 触发调用（示例） | `CryptoErrorKind` | App code |
|---|---|---|---|
| `CREATE` | `createMd`、`createMac`、`createKdf`、`createCipher`、`createRandom`、`createAsyKeyGenerator`、`createKeyAgreement`、`createSymKeyGenerator` | `UNAVAILABLE` | `CRYPTO_UNAVAILABLE` |
| `KEY_CONVERSION` | `convertKeySync`、`getEncoded`、X25519 DER↔raw codec | `INVALID_KEY` | `CRYPTO_INVALID_KEY` |
| `OPERATION` | `initSync`、`updateSync`、`doFinalSync`（非 GCM 解密）、`generateKeyPairSync`、`generateSecret`、`generateRandomSync` | `OPERATION_FAILED` | `CRYPTO_OPERATION_FAILED` |
| `GCM_DECRYPT_FINAL` | GCM 解密 `doFinalSync` 且平台 code = `17630001` | `AUTH_TAG` | `CRYPTO_TAG_MISMATCH` |
| `GCM_DECRYPT_FINAL` | GCM 解密 `doFinalSync` 的其他平台 code（401/17620003 等）或非平台错误 | `OPERATION_FAILED` | `CRYPTO_OPERATION_FAILED` |

- 已存在的 `CryptoProviderError` 在所有阶段保持原 kind，不被重新分类。
- 说明：按评审 §3 R-01 的修复建议，**原语创建失败**归 `CRYPTO_UNAVAILABLE`；**init/operation 失败**归 `CRYPTO_OPERATION_FAILED`。`createKdf`/`createCipher` 属于创建失败，不再落入 `OPERATION_FAILED`/`INVALID_KEY`。
- 平台 message/code 仍不进入 `AppError.message`；只有分类结果跨过 provider seam。

### 1.2 R-02 秘密清理

| 路径 | 修复 |
|---|---|
| GCM `encryptAesGcm` / `decryptAesGcm` | `symKey` 在整个函数作用域的 `finally` 中 `clearMem()`；覆盖 `convertKeySync`、`createCipher`、`initSync`、`doFinalSync` 及长度校验的所有失败路径 |
| `importX25519PrivateRaw` | PKCS#8 DER 临时副本 `der` 在 `finally` 中 `fill(0)`（成功/失败/异常均已清零） |
| HMAC `hmacSha256` | 原有 `finally` 保留；`convertKeySync` 失败时无 key 对象可清 |
| CTR `OhosAesCtrStream.process` | 失败即 `destroy()`（幂等）释放平台 key，再抛 `OPERATION_FAILED`；`CryptoService` 仍保持 `ACTIVE→BROKEN` |
| CTR 创建 | 成功时所有权转移给 stream；失败时 `finally` 清 `symKey` |
| KDF（HKDF/PBKDF2） | 未分配 provider 自有的临时 key 缓冲；平台 spec 直接引用调用方内存，调用方负责其生命周期 |
| 设备骨架 | `SecurityDevice.test.ets` 在篡改 tag 失败后增加“再次成功解密”断言与注释，证明失败路径清理后 provider 仍可用；`clearMem` 本身不可从 ArkTS 观测，Heap 级验证留给 T-19 |

### 1.3 R-03 设备 GCM 向量

- 16B 零明文、零 key、零 IV、空 AAD 的 Node `crypto` 复算：密文 `cea7403d4d606b6e074ec5d3baf39d18`，tag `d0d1c8a799996bf0265b98b5d48ab919`。
- 设备测试期望 tag 已改为 `d0d1c8a799996bf0265b98b5d48ab919`（原 `530f...` 是空明文 tag）。
- 新增 `opened` 明文逐字节断言：`00000000000000000000000000000000`；篡改 tag 仍断言 `CRYPTO_TAG_MISMATCH`。
- 文件仍标注 `BLOCKED_ON_DEVICE_RUNNER`；首次设备运行必须复跑该向量。

### 1.4 R-04 设备测试接线

`entry/src/ohosTest/ets/test/List.test.ets` 现注册：

```text
baselineTest()
foundationDeviceTest()   // T-06 C-01..C-03
securityDeviceTest()     // T-07 C-04/C-05
```

`ohosTest` 编译验证通过（`t07-fix-ohosTest-assemble.log`）。注册不等于执行：无设备/签名时 `onDeviceTest` 仍为 `BLOCKED`。

### 1.5 R-05/R-06 文档准确性

- `entry/src/test/README.md`：当前 revision 更新为 **122/122 PASS**（`t07-fix-host-node-tests.tap`），目录树补齐 `Crypto.test.mjs`、`Security.test.mjs`、`TestCryptoProvider.ets`、`foundation/`、`protocol/`、`security/` 与全部 T-07 host 覆盖；保留 T-05 15/15、T-06 88/88 为历史基线。
- `artifacts/50-implementation/t07-security.md`：C-04 文件数 7→**6**、C-05 6→**5**；§1.1 标题改为“T-07 时 6 文件”；118/118 标注为 T-07 revision 证据，并加勘误说明本修复新增分类器文件后 crypto 目录为 7 个、测试数为 122。§1.1/§2 的错误映射与 GCM 描述同步为修复后语义。

### 1.6 R-07 固定前缀不可变

`X25519KeyCodec`：

- `SPKI_PREFIX_BYTES` / `PKCS8_PREFIX_BYTES` 改为 `private static readonly` backing array；
- 保留 `X25519KeyCodec.SPKI_PREFIX` / `PKCS8_PREFIX` 公开读取面，但改为 `static get`，每次返回 `BytesUtil.copyOf(...)` 的新副本；
- codec 内部 DER 包装/剥离直接使用私有 backing array，不受外部写入影响；
- host 测试先改写返回的副本，再验证后续 DER 前缀仍为 `302a...` / `302e...`，并验证 `rawToDer*` 输出未被污染。

---

## 2. 验证命令与证据

### 2.1 实际执行（修复后，cwd = 仓库根）

| 命令 | 退出码 | 结果 | 证据 |
|---|---|---|---|
| `ohpm install` | 0 | `install completed in 0s 62ms` | `entry/src/test/evidence/t07-fix-ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | 0 | `BUILD SUCCESSFUL in 5 s 539 ms`；35 tasks（34 executed / 1 up-to-date）；仅 unsigned HAP warning | `entry/src/test/evidence/t07-fix-hvigor-assemble.log` |
| `codelinter -c code-linter.json5 -p default .` | 0 | `No defects found in your code.` | `entry/src/test/evidence/t07-fix-codelinter.log` |
| `entry/src/test/run-host-tests.sh` | 0 | `# tests 122 / # pass 122 / # fail 0`；`duration_ms 1093.669064` | `entry/src/test/evidence/t07-fix-host-node-tests.tap` |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon`（附加） | 0 | `BUILD SUCCESSFUL in 7 s 149 ms`；35 tasks；验证 R-04 接线可编译 | `entry/src/test/evidence/t07-fix-ohosTest-assemble.log` |

### 2.2 测试计数

- T-07 实现时：118/118。
- 本次新增 4 个 host 用例：`C04_CryptoErrorClassifier_mapsDesAErrorTable`、`C04_CryptoErrorClassifier_preservesExplicitProviderKind`、`C04_X25519KeyCodec_prefixesAreDefensiveCopies`、`C04_CryptoService_gcmOperationFailureIsNotTagMismatch`。
- 修复后：**122/122 PASS**（`fail 0`）。

### 2.3 设备侧独立复算

```text
AES-256-GCM key=32B zero, iv=12B zero, aad=empty, plaintext=16B zero
ciphertext = cea7403d4d606b6e074ec5d3baf39d18
tag        = d0d1c8a799996bf0265b98b5d48ab919   (Node crypto, 2026-10-17)
```

---

## 3. 变更文件

| 路径 | 变更 |
|---|---|
| `entry/src/main/ets/service/crypto/CryptoErrorClassifier.ets` | **新增**：host 可测的分层错误分类器（R-01） |
| `entry/src/main/ets/service/crypto/OhosCryptoProvider.ets` | 阶段化错误映射、GCM/HMAC/CTR/DER 清理、GCM 认证失败判定（R-01/R-02） |
| `entry/src/main/ets/service/crypto/X25519KeyCodec.ets` | 私有 backing prefix + 公开副本 getter（R-07） |
| `entry/src/main/ets/service/crypto/CryptoPort.ets` | R-08 位置例外注释（无签名/行为变化） |
| `entry/src/ohosTest/ets/test/List.test.ets` | 注册 foundation/security 设备套件（R-04） |
| `entry/src/ohosTest/ets/test/security/SecurityDevice.test.ets` | GCM tag/明文断言、清理路径骨架（R-02/R-03） |
| `entry/src/ohosTest/ets/test/README.md` | 设备套件目录/注册状态同步（R-04） |
| `entry/src/test/host/Crypto.test.mjs` | 新增 4 个分类器/前缀/服务映射用例（R-01/R-07） |
| `entry/src/test/README.md` | 当前 122/122 与目录/覆盖更新（R-05） |
| `entry/src/test/evidence/t07-fix-*.log/.tap` | 本次验证证据 |
| `artifacts/50-implementation/t07-security.md` | 文件数 6/5、测试数勘误与错误语义同步（R-06） |
| `artifacts/50-implementation/t07-fix-report.md` | 本报告 |

未修改：`entry/src/main/ets/service/security/**`、canonical/HMAC/ACK 判定语义、`common/**`、`model/**`、`service/protocol/**`、构建配置、`input/**`。

---

## 4. R-08 例外与后续跟踪

- **现状**：`CryptoPort.ets` 仍在 `entry/src/main/ets/service/crypto/`，未迁移到 DES-A §7 名义位置 `contracts/CryptoPort.ets`；`CryptoService` 构造参数为低层 `CryptoProvider`，便于 host 注入独立 provider。
- **理由**：本任务 write scope 不含 `contracts/**`；仓内只有一套端口/实现，生产仍注入 `OhosCryptoProvider`，无行为/契约分叉。
- **跟踪**：C-17 组合根迁移时保持签名迁移到 `contracts/**`；T-19/Gate 复核。已在 `CryptoPort.ets` 头注释与 `t07-security.md` §6 记录，禁止复制第二套端口。

---

## 5. 未决项与残余风险

| ID | 项 | 状态/后续 |
|---|---|---|
| FIX-RISK-01 | 真实 `cryptoFramework` 行为未运行（SHA/HMAC/KDF/X25519/CTR/GCM/Random） | **BLOCKED**；T-12/T-19 设备 runner 复跑 `SecurityDevice.test` |
| FIX-RISK-02 | GCM tag mismatch 的平台 code 依赖 `17630001`（`ERR_CRYPTO_OPERATION`） | 设备测试会断言 `CRYPTO_TAG_MISMATCH`；若设备返回其他 code，该用例失败并暴露分类偏差，需按实测 code 扩展分类器 |
| FIX-RISK-03 | `clearMem()` 无 ArkTS 可观测性 | 设备行为骨架已补；Heap/内存验证留 T-19 |
| FIX-RISK-04 | R-04 仅证明“设备套件被注册并可编译”，未执行 | `onDeviceTest` 仍 `BLOCKED`（无设备/无签名） |
| FIX-RISK-05 | R-08 端口位置例外未迁移 | C-17 组合根 / T-19 跟踪 |
| FIX-RISK-06 | 常数时间仅行为/代码审查，无统计时序 | T-19/安全评审 |
| FIX-RISK-07 | CTR 并发调用约定（评审观察 2）未改 | 非阻塞；C-17 调用约定明确串行 await |

---

## 6. 声明

- 本报告由 `agent:implementation-engineer` 编写，不自我批准、不授予 CQG-T07 PASS、C-04/C-05 `STABLE`、Stage Gate 或用户验收。
- 修复提交位于 `task/wp-016-security` 分支，base commit `df13b29386c3f15dbe5cfe7b103819308b21dcd8`；提交后由 `swe_guard.py finish` 校验路径范围。
- 所有验证命令均在当前工作树实际执行；未把 `COMPILED_ONLY`/`BLOCKED` 写成 PASS。

---

*Implementation Engineer: agent:implementation-engineer | Base: df13b29 | Status: Proposed for re-review*
