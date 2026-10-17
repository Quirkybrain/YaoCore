# T-08 存储服务 + GatewayRepository 实现报告

- **Artifact ID**: IMP-T08-STORAGE
- **Producer**: agent:implementation-engineer
- **Type**: Implementation / Verification Evidence
- **Status**: Proposed（本地构建/lint/host 测试完成；待独立评审与 CQG-T08 Gate）
- **Date**: 2026-10-17
- **Task**: T-08 / `wp-020-storage`（task 分支 `task/wp-020-storage`，父分支 `feat/yaocore-app`，base commit `0713aca8f6b4e8a326f94842eb21bc3df61fd444`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`
- **Upstream 契约**:
  - DES-A `artifacts/40-detailed-design/des-001a-foundation-transport.md` §9（C-06）、§10（C-07）、§22（键空间/秘密生命周期）、§3.5/§3.7/§23（D-018）、§27
  - `artifacts/20-architecture/adr-002-lan-security-channel.md` §4/§6/§8.3/§8.4
  - `artifacts/20-architecture/contract-baseline.md`、`artifacts/20-architecture/project-constraints.md`（SC-09/SC-12、DP-04、PR-06、FC-03）
  - `artifacts/60-testing/test-plan.md` §4/§5/§10；D-019 host/device 分层
- **Downstream**: T-09（FamilyRepository 复用 `MigrationSink`/RDB）、T-11（`GatewayRepository`/`tlsMaterial`）、T-12（`SecretDraftStore`）、T-13、CQG-T08、T-20、Stage Gate
- **组件状态**: C-06 `UNVERIFIED`、C-07 `UNVERIFIED`（本报告不授予 `STABLE`）
- **评审修复**: `wp-022-fix-t08`（R-01..R-07）见 `artifacts/50-implementation/t08-fix-report.md`；本文件的文件计数、测试数与设备覆盖措辞已按评审同步更正

---

## 0. 摘要

| 项 | 结果 | 证据 |
|---|---|---|
| C-06 存储服务（Preferences/RDB/Asset 端口 + 适配器 + v1 迁移 + draft store） | **实现完成** | `service/storage/` 11 文件（初版；wp-022 新增 `RdbTransactionRunner.ets` 后 12） |
| C-07 GatewayRepository（route CRUD/profile/pin/commitBinding/rotate/sequence） | **实现完成** | `repository/` 2 文件 |
| 平台适配器（Preferences/RDB/AssetStore） | **COMPILED_ONLY** | 单文件隔离；无设备运行 |
| Node host 测试 | **PASS 161/161**（初版新增 39：C-06 14 + C-07 25）；wp-022 修复后 **166/166**（C-06 15 + C-07 29，见 `t08-fix-report.md`） | `entry/src/test/evidence/t08-host-node-tests.tap` / `t08-fix-host-node-tests.tap` |
| `ohpm install` | **PASS**（exit 0） | `evidence/t08-ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | **PASS**（BUILD SUCCESSFUL，35 tasks） | `evidence/t08-clean-assemble.log` |
| `codelinter -c code-linter.json5 -p default .` | **PASS**（No defects found） | `evidence/t08-codelinter.log` |
| Hypium host 编译（附加） | **COMPILED_ONLY**；`UnitTestArkTS` 成功，Previewer 执行 **BLOCKED**（timeout 124） | `evidence/t08-hvigor-test-compile.log` |
| ohosTest HAP 编译（附加） | **PASS**（BUILD SUCCESSFUL） | `evidence/t08-ohosTest-assemble.log` |
| 设备侧 Asset/RDB/Preferences 运行 | **BLOCKED**（无设备、无签名） | `entry/src/ohosTest/ets/test/storage/StorageDevice.test.ets` |

**结论**：C-06/C-07 产品实现、host 逻辑测试、公开构建与静态检查全部通过；真实平台存储行为仅完成 ArkTS 编译，必须由后续设备 runner 复跑同一组设备用例，本报告不宣布 `STABLE`，也不把编译成功写成设备通过。

---

## 1. 实现范围与文件清单

### 1.1 C-06（`entry/src/main/ets/service/storage/`，初版 11 文件）

> 评审更正（R-06）：本报告初版两处误写 12 文件；`66b6e1d` 实际为 11 文件。wp-022
> 修复新增平台无关的 `RdbTransactionRunner.ets`（R-02），修复 revision 为 12 文件。

```text
PreferencesStore.ets       # PreferencesStore 端口
RdbStore.ets               # RdbValue/RdbRow/RdbTransaction/RdbStore 端口
SecretStore.ets            # SecretStore 端口 + SecretAlias 校验（^[a-zA-Z0-9._-]{1,127}$）
SecretDraftPort.ets        # 一次性内存草稿端口
MigrationPort.ets          # MigrationSink / MigrationRegistryPort
MigrationRegistry.ets      # 连续版本校验、事务内迁移、失败不改版本
SecretDraftStore.ets       # 10min TTL、一次性、clearAll 清零、复制输入
StorageService.ets         # v1 DDL（gw_route/gw_sequence/gw_dismissed_device + family 索引）
PreferencesStoreAdapter.ets# 唯一 @kit.ArkData preferences 适配文件
RdbStoreAdapter.ets        # 唯一 @kit.ArkData relationalStore 适配文件；事务串行
AssetStoreSecretStore.ets  # 唯一 @kit.AssetStoreKit 适配文件；DEVICE_FIRST_UNLOCKED
```

要点：

- **v1 DDL** 与 DES-A §9.1.6 字段逐项一致；`gw_route_family_idx` 支持家庭-网关绑定索引，DDL 全部 `IF NOT EXISTS`，重复初始化安全。
- **迁移单向**：版本必须 1..N 连续（注册可乱序），每个版本在 RDB 事务内执行；`setVersion` 与 DDL 同事务；失败回滚、不删数据、不降级。数据库版本高于本构建 → `STORAGE_MIGRATION_FAILED`（不降级）。
- **SecretStore.withSecret** 只在回调期间提供副本，成功/异常均 `zeroize`；`put` 先复制 `SecureBytes` 视图，上传后清零临时缓冲；`list` 只返回 alias。
- **SecretDraftStore**：1) `put` 复制输入，调用方可立即销毁原对象；2) `take` 一次性删除并返回新 `SecureBytes`，过期/缺失分别 `PROVISIONING_SECRET_DRAFT_EXPIRED`/`PROVISIONING_CREDENTIAL_MISSING`；3) `clearAll` 清零全部；4) 默认 TTL 600000ms。
- **AssetStoreSecretStore**：按 DES-A §9.2 映射 `24000001/24000002/24000004/24000005/24000008/24000009/24000010/201`；只保留数字码；任何失败均 `ASSET_*`，**无明文回退**。
- `StorageService.close()` 只关闭逻辑生命周期，不清数据；平台句柄由组合根关闭适配器（端口契约无 `close`）。

### 1.2 C-07（`entry/src/main/ets/repository/`，2 文件）

```text
GatewayPorts.ets       # GatewayRoutePort/GatewayCredentialPort/GatewayAddressPort/
                       # GatewaySequencePort/SecretVerifier/InvitationApplicationPort/InvitedGateway
GatewayRepository.ets  # 实现全部端口
```

要点：

- **route CRUD**：`listRoutes`/`listRoutesByFamily`/`getRoute`/`isBound`；`GatewayRoute.create` 继续承担 profile/pin/port/timestamp/alias 不变量，不重复实现。
- **commitBinding**：校验参数与 `draftId === result.credentialDraftId`；家庭归属变更 → `CONFIGURATION_ERROR`（禁止静默迁移）；draft 命令密钥强制 16..4096B（SC-04，wp-022 R-01）；v2.0/无 TLS → `P-HMAC`，v2.1+TLS → `P-TLS-PIN`；secret → route 顺序写入；route 失败时恢复旧 secret，旧值恢复也失败则删除 alias（**fail-closed**，避免 route 指向未验证 secret）；draft 一次性消费（重放 → `PROVISIONING_SECRET_DRAFT_EXPIRED`）；成功后 `markSeen` 为 post-commit best effort（wp-022 R-05）。
- **applyInvitedGateway**：同一补偿语义；同 `gatewayId` 重复应用幂等，保留 `createdAt`；家庭变更拒绝。
- **setPersistentProfile**：只允许 `P-HMAC`/`P-TLS-PIN`；`P-BLOCKED` → `GATEWAY_PROFILE_BLOCKED` 且不落盘；`P-HMAC` 清空 pins/tls。
- **pinVerified**：格式/成员校验失败 `TLS_PIN_CONFIG_INVALID`；多 pin 首次匹配成功后收缩为单 pin（ADR-002 §4.4）；单 pin 匹配 no-op；非 TLS route → `TLS_PROFILE_INCONSISTENT`。
- **rotateSecret**：pending alias → 使用副本调用 `SecretVerifier`（回调后清零）→ 成功后覆盖 active → 删除 pending；验证失败/异常删除 pending、active 不变；pending 清理失败不掩盖主错误，由 `initialize()` 重试。
- **removeLocalBinding**：只删本机 route/active/pending/sequence，无 transport 依赖（不访问实体网关，SC-12）。
- **sequence**：`nextSequence` 事务内读取/递增；达到 `MAX_SEQ` → `CONFIGURATION_ERROR`（是否无在途由 C-17 通过 `resetSequenceIfIdle` 决定）；`resetSequenceIfIdle` 显式归零。
- **withCommandSecret / tlsMaterial**：未绑定 → `GATEWAY_NOT_BOUND`；HMAC → `undefined`；TLS 材料继续由 `TlsMaterial` 校验。

---

## 2. 契约对照

| 契约 | 实现位置 | 结果 |
|---|---|---|
| DES-A §9.1.1 `PreferencesStore` | `PreferencesStore.ets` / `PreferencesStoreAdapter.ets` | 实现 |
| DES-A §9.1.2 `RdbStore`/事务/版本 | `RdbStore.ets` / `RdbStoreAdapter.ets` | 实现；事务串行；错误映射 |
| DES-A §9.1.3 `SecretStore`/alias/withSecret 清零 | `SecretStore.ets` / `AssetStoreSecretStore.ets` | 实现 |
| DES-A §9.1.4 `StorageService`/`MigrationRegistry` | `StorageService.ets` / `MigrationRegistry.ets` | 实现 |
| DES-A §9.1.5 `SecretDraftPort` | `SecretDraftStore.ets` | 实现（默认 10min、一次性、clearAll） |
| DES-A §9.1.6 v1 DDL | `StorageService.registerMigrations` | 逐字段一致 + family 索引 |
| DES-A §9.2 错误映射 | `AssetStoreSecretStore.mapError` 等 | 数字码映射；无平台 message |
| DES-A §9.3 不变量 1–8 | 迁移/事务/秘密边界/别名/擦除/Asset 可用性/幂等/keyId | 实现（见 §5 未决） |
| DES-A §10.1 端口与方法 | `GatewayPorts.ets` / `GatewayRepository.ets` | 全部方法实现 |
| DES-A §10.2 错误表 | `GatewayRepository` | 使用稳定 App code |
| DES-A §10.3 绑定与补偿 | `commitBinding`/`applyInvitedGateway`/`rollbackSecret` | 实现（顺序见 R-01） |
| DES-A §10.4 profile/pin/sequence/alias | `setPersistentProfile`/`pinVerified`/sequence/常量 | 实现；P-BLOCKED 不持久化 |
| DES-A §10.5 host seam | `entry/src/test/storage/FakeStores.ets` | 内存 fake + SQL 子集 |
| ADR-002 §4 pin 格式/轮换 | `pinVerified`/`TlsMaterial` | 实现 |
| ADR-002 §6 三档案/禁止明文回退 | profile 持久化 + `tlsMaterial`/C-17 边界 | 实现；运行期 P-BLOCKED 留给 C-17 |
| ADR-002 §8.3/§8.4 存储边界/轮换 | alias/AssetStore/rotateSecret | 实现 |
| SC-09 秘密边界 | Preferences 不含 secret；RDB 仅 alias/pin；secret 仅 AssetStore | 测试断言 |
| SC-12 删除仅解绑 | `removeLocalBinding` 无网络依赖 | 测试断言 |
| FC-03 key_id 不滚动 | 恒 `app-key-v1` | 实现 |
| D-019 host/device 分层 | Node host + device skeleton | 见 §4 |

> G-004 语义未改变：`commitBinding(result, draftId, familyId)` 三参数语义、P-HMAC/P-TLS-PIN/P-BLOCKED 规则、pin 格式、`key_id=app-key-v1`、禁止明文回退均保持。

---

## 3. 测试清单与结果

### 3.1 C-06（14 用例，`entry/src/test/host/Storage.test.mjs`）

| 用例 | 覆盖 |
|---|---|
| `C06_SecretDraftStore_putTakeIsOneShotAndSurvivesSourceDestroy` | 复制输入、一次性、销毁源后仍可 take |
| `C06_SecretDraftStore_ttlBoundaryAndExpiryZeroize` | TTL 边界/过期错误 |
| `C06_SecretDraftStore_clearAllAndDestroyClearBuffers` | destroy/clearAll/size |
| `C06_SecretDraftStore_rejectsDestroyedSecretAndInvalidTtl` | `SECRET_DESTROYED`、非法 TTL |
| `C06_SecretDraftStore_multipleDraftsAreIndependentAndUniqueIds` | 多草稿独立、ID 唯一 |
| `C06_MigrationRegistry_appliesContiguousVersionsAndIsIdempotent` | 0→2、重复 migrate |
| `C06_MigrationRegistry_rejectsDuplicateRegistrationAndVersionGap` | `CONFIGURATION_ERROR`、缺口 `STORAGE_MIGRATION_FAILED` |
| `C06_MigrationRegistry_failedStatementRollsBackVersionAndTables` | 失败回滚表+版本 |
| `C06_MigrationRegistry_refusesNewerSchemaWithoutDowngrade` | 不降级 |
| `C06_StorageService_initializeRegistersV1AndIsIdempotent` | v1 表、版本、幂等 |
| `C06_StorageService_getVersionFailureSurfacesStorageRdbError` | `STORAGE_RDB_ERROR` |
| `C06_StorageService_closeDoesNotClearDataAndBlocksReinitialize` | close 不清数据、未初始化错误 |
| `C06_InMemorySecretStore_withSecretZeroizesViewOnSuccessAndFailure` | 成功/异常均清零副本 |
| `C06_InMemorySecretStore_aliasGrammarAndListingHaveNoSecretValues` | alias 语法、list 不含秘密 |

### 3.2 C-07（25 用例，`entry/src/test/host/GatewayRepository.test.mjs`）

| 用例 | 覆盖 |
|---|---|
| `C07_commitBinding_hmacPersistsRouteAndOneShotSecret` | HMAC 绑定、alias、markSeen、draft 重放 |
| `C07_commitBinding_tlsPersistsPinsPortAndMaterial` | TLS 绑定、pins/port/pinAlg/tlsMaterial |
| `C07_commitBinding_rejectsDraftMismatchBeforeConsumingDraft` | draft 校验先于消费 |
| `C07_commitBinding_rejectsSilentFamilyMigration` | 家庭归属不可静默迁移 |
| `C07_commitBinding_routeWriteFails_restoresPreviousSecret` | 补偿：恢复旧 secret |
| `C07_commitBinding_rollbackRestoreFailureDeletesUnverifiedSecret` | 补偿再失败 → fail-closed 删除 |
| `C07_commitBinding_freshRouteWriteFails_removesNewSecret` | 首次绑定失败无残留 secret |
| `C07_commitBinding_secretWriteFails_writesNoRoute` | secret 写失败不写 route |
| `C07_commitBinding_withoutDraftReusesSecretAndRequiresExistingBinding` | 沿用 secret、缺失 → `PROVISIONING_CREDENTIAL_MISSING` |
| `C07_commitBinding_missingDraftMeansExpired` | 缺失 draft → `PROVISIONING_SECRET_DRAFT_EXPIRED` |
| `C07_applyInvitedGateway_isIdempotentAndPreservesCreatedAt` | 邀请幂等、createdAt、家庭冲突 |
| `C07_applyInvitedGateway_secretWriteFailureWritesNoRoute` | 邀请 secret 失败无 route |
| `C07_setPersistentProfile_rejectsBlockedAndMigratesHmacTls` | P-BLOCKED 不持久化、TLS→HMAC、空 pin |
| `C07_pinVerified_shrinksMultiPinSetAndFailsClosedOnUnknownPin` | 多 pin 收缩、未知 pin fail-closed |
| `C07_rotateSecret_successPromotesActiveAndRemovesPending` | 轮换成功、pending 清理 |
| `C07_rotateSecret_verificationFailureKeepsActiveAndRemovesPending` | 验证 false → active 不变 |
| `C07_rotateSecret_verifierThrowKeepsActiveAndRemovesPending` | 验证异常 → active 不变 |
| `C07_initialize_cleansLeftoverPendingRotationAliases` | 启动清理 pending |
| `C07_removeLocalBinding_deletesRouteSecretsAndSequenceWithoutNetwork` | 本机解绑、无网络 |
| `C07_sequence_nextPeekResetAndSaturation` | 序列读/增/重置/上限 |
| `C07_sequence_concurrentNextCallsAreSerialized` | 40 并发无重复/丢失 |
| `C07_routes_listByFamilyIsBoundAndAddressUpdates` | 列表、家庭索引、last-known IP |
| `C07_credentials_unboundAndTlsOnlySemantics` | 未绑定错误、HMAC 无 TLS 材料 |
| `C07_initialize_requiresTablesAndInitializeState` | `STORAGE_NOT_INITIALIZED` |
| `C07_secretDiscipline_noPlaintextInPreferencesRdbOrErrors` | Preferences/RDB/错误文本无明文；回调副本清零 |

### 3.3 Fake 边界（D-019）

`entry/src/test/storage/FakeStores.ets`：

- `InMemoryPreferencesStore`：Map、失败注入、调用计数、dump。
- `InMemoryRdbStore`：`gw_*` 所需 SQL 子集（CREATE TABLE/INDEX、INSERT OR REPLACE/IGNORE、SELECT/WHERE/ORDER BY/LIMIT、UPDATE、DELETE）、主键、事务快照回滚、并发事务串行、失败注入、全表值 dump（泄漏审计）。
- `InMemorySecretStore`：alias 唯一/覆盖、withSecret 副本清零、失败注入、调用/清零计数。
- 未配置的 SQL/表/列默认抛 `STORAGE_RDB_ERROR`，不“默认成功”；错误均 `AppError`。

### 3.4 设备侧

`entry/src/ohosTest/ets/test/storage/StorageDevice.test.ets`（**BLOCKED_ON_DEVICE_RUNNER**）：

- Preferences 持久化/flush/delete；
- RDB 建表、插入/查询、事务回滚、user_version；
- Asset Store `put/withSecret/list/remove`。

初版该套件**未注册**进 `entry/src/ohosTest/ets/test/List.test.ets`；wp-022（R-03）已注册，并补充了
“事务内 `setVersion` + 后续语句失败 → 版本和表回滚”与“锁屏前置条件下 `ASSET_ACCESS_DENIED`”
设备骨架断言。锁屏分支需要 runner 先建立锁屏前置条件，当前环境无法执行，**不是 PASS**。

该文件经 `entry/src/test/storage/StorageHost.test.ets` 的 `import` 拉入 `hvigorw test` 的 ArkTS 编译图（`UnitTestArkTS` 成功），但**未在设备上执行**。`onDeviceTest` 在无设备/无签名环境为 `UNAVAILABLE`，不得写成 PASS；真实 RDB/Asset 行为仍为 `COMPILED_ONLY`/`BLOCKED`。

---

## 4. CQG-T08 可运行证据

```text
CQG-T08
- build: hvigorw clean assembleHap --no-daemon -> PASS
  log: entry/src/test/evidence/t08-clean-assemble.log (BUILD SUCCESSFUL, 35 tasks)
- lint: codelinter -c code-linter.json5 -p default . -> PASS
  log: entry/src/test/evidence/t08-codelinter.log (No defects found)
- host tests: entry/src/test/run-host-tests.sh -> PASS (161/161; new 39)
  log: entry/src/test/evidence/t08-host-node-tests.tap
- host tests (wp-022 fix): entry/src/test/run-host-tests.sh -> PASS (166/166; new 44)
  log: entry/src/test/evidence/t08-fix-host-node-tests.tap
- test HAP compile: hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon -> PASS
  log: entry/src/test/evidence/t08-ohosTest-assemble.log
- Hypium host compile: hvigorw test --no-daemon -> COMPILED_ONLY (UnitTestArkTS OK; Previewer BLOCKED, exit 124)
  log: entry/src/test/evidence/t08-hvigor-test-compile.log
- device tests: onDeviceTest -> UNAVAILABLE (no device/emulator/signing)
- contract vectors: 不适用（本任务无协议向量）；RDB/Asset 平台行为见设备用例
- security: no secret logs / fail-closed / no plaintext fallback -> PASS (host assertions + adapter review)
- traceability: SC-09/SC-12, ADR-002 §4/§6/§8.3/§8.4, FR-GW-003/FR-SET-002 -> 见 §3 用例
```

精确命令与日志路径：

| 命令 | 退出码 | 日志 |
|---|---|---|
| `ohpm install` | 0 | `entry/src/test/evidence/t08-ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | 0 | `entry/src/test/evidence/t08-clean-assemble.log` |
| `codelinter -c code-linter.json5 -p default .` | 0 | `entry/src/test/evidence/t08-codelinter.log` |
| `entry/src/test/run-host-tests.sh` | 0 | `entry/src/test/evidence/t08-host-node-tests.tap`（初版 161/161） |
| `entry/src/test/run-host-tests.sh`（wp-022 修复） | 0 | `entry/src/test/evidence/t08-fix-host-node-tests.tap`（166/166） |
| `hvigorw test --no-daemon`（附加） | 124（Previewer） | `entry/src/test/evidence/t08-hvigor-test-compile.log` |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon`（附加） | 0 | `entry/src/test/evidence/t08-ohosTest-assemble.log` |

---

## 5. 偏离、未决项与风险

### 5.1 记录性偏离（不改变契约行为）

1. **端口物理位置**：DES-A 名义上把端口放在 `contracts/**`；T-08 写范围仅 `service/storage/**` 与 `repository/**`，因此 `PreferencesStore/RdbStore/SecretStore/SecretDraftPort/MigrationPort` 与 `GatewayPorts` 留在实现目录。与 T-06 R-13、T-07 R-08 同类；待 C-17 组合根统一迁移。
2. **`SecretDraftStore` 的 draftId 生成**：契约 `put()` 同步，而 `RandomPort.nextBytes()` 异步。实现以 `clock.nowMs()+counter` 生成不透明本地句柄；若注入的 `RandomPort` 同时提供 `nextBytesSync()`（测试 fake），会混入随机熵。draftId 不是凭据（TTL 10min、进程内、一次性），不构成秘密边界。生产 `CryptoRandomSource` 仅异步，故生产路径为 clock+counter。
3. **`commitBinding` 校验顺序**：在消费 draft 之前先读取现有 route 并校验 familyId。DES-A §10.3 步骤 2/3 的编号上先 take draft；本实现先校验家庭归属再 take，避免家庭冲突时无谓销毁一次性 secret。三参数语义与失败错误码不变。
4. **`pinVerified` 轮换事件**：DES-A 要求“记录轮换事件”。T-08 没有事件总线/日志端口注入，当前通过持久化 pins 收缩 + `updated_at` 记录状态；`gateway.bound`（DES-B 定义）同样未发射。事件发布留给 C-17/DES-B 组合层；本任务不新增事件契约。
5. **`StorageService.close()`**：端口无 `close`，服务只清逻辑状态；平台句柄由组合根调用适配器的 `close()`。这是契约签名限制，不是漏实现。
6. **`removeLocalBinding` 删除顺序**：先删 secret、再事务删 route/sequence。若 RDB 删除失败，route 仍存在但 secret 已无（控制 fail-closed）；再次调用可完成，因为 secret 删除容忍 `ASSET_NOT_FOUND`。跨 Asset/RDB 无法共用事务，属 DES-A §10.3 已承认的补偿边界。
7. **`nextSequence` 上限**：仓库无法观察 C-17 的“在途命令”，到达 `MAX_SEQ` 时保守返回 `CONFIGURATION_ERROR`；显式空闲重置由 `resetSequenceIfIdle` 提供，是否调用由 C-17 决定。
8. **`commitBinding` post-commit 语义（wp-022 R-05）**：route + secret 成功落盘后，`markSeen`/回读失败不再把绑定报告为失败；`last_seen_at` 为 best effort，回读失败时返回已提交的 route 快照。评审修复报告补充半成功用例。
9. **`setPersistentProfile` 降级边界（wp-022 R-07）**：P-TLS-PIN → P-HMAC 仅允许显式重配网（网关不再宣告 TLS）；TLS 运行期校验失败必须由 C-17 走 P-BLOCKED，**不得调用**该方法。仓库层未增加降级守卫参数，以保持 §10.1 冻结签名；约束记录在方法注释与修复报告中。

### 5.2 设备侧未验证 / 风险

| ID | 内容 | 影响 | 处置 |
|---|---|---|---|
| R-T08-01 | Asset Store `ALIAS` 在本 SDK 的 `asset.Value` 类型中按 BYTES 处理，适配器使用 UTF-8 `Uint8Array` 写入/读回 | 若平台实际要求 string alias，设备运行会失败 | `StorageDevice.test.ets` 骨架包含 put/query/list，**未执行**；设备环境必须复核；不得回退明文 |
| R-T08-02 | `AssetStoreSecretStore.list()` 使用 `RETURN_TYPE=ATTRIBUTES` + 分页查询全部资产 | 平台是否允许无 alias 的全量 query 未在设备验证 | `StorageDevice.test.ets` 骨架包含 list，**未执行**；若不允许，改为按已知别名集合查询（仍不读取 secret） |
| R-T08-03 | RDB `store.version` 属性与 `beginTransaction/commit/rollBack` 的真实行为 | 迁移版本/回滚语义可能偏差 | 设备骨架已加“事务内 setVersion 失败回滚”（wp-022 R-03），**未在设备执行**；host 已覆盖事务运行器逻辑 |
| R-T08-04 | 锁屏/首次解锁 Asset 访问语义 | `DEVICE_FIRST_UNLOCKED` 失败应 `ASSET_ACCESS_DENIED` | 设备骨架已加锁屏 `ASSET_ACCESS_DENIED` 断言（需锁屏前置条件），**未在设备执行**；安全评审/设备复核仍待 |
| R-T08-05 | 补偿写回旧 secret 失败时删除 alias | 网关暂时不可控（fail-closed） | 已由 `C07_commitBinding_rollbackRestoreFailureDeletesUnverifiedSecret` 断言 |
| R-T08-06 | Preferences 适配器不主动识别/拒绝 secret | 误用可能违反 SC-09 | 端口注释 + 仓储不写 Preferences；评审检查调用点 |

### 5.3 未实现/后续任务

- 运行期 P-BLOCKED 选择与“不发送任何控制请求”属 C-17（T-11）；C-07 只保证不持久化 P-BLOCKED、TLS 材料可判定。
- `gateway.bound` / 轮换事件发布属 DES-B/C-17。
- `gw_dismissed_device` 的读写属 C-10。
- 真实 `onDeviceTest` 需要设备/模拟器与签名配置；当前 `UNAVAILABLE`。

---

## 6. 追溯

| 需求/约束 | 测试/实现 |
|---|---|
| SC-09 秘密边界 | `C07_secretDiscipline_noPlaintextInPreferencesRdbOrErrors`；AssetStore 适配器；Preferences 端口注释 |
| SC-12 删除仅解绑 | `C07_removeLocalBinding_deletesRouteSecretsAndSequenceWithoutNetwork` |
| FR-GW-003 / FR-SET-002 绑定/TLS 材料 | `C07_commitBinding_*`、`C07_pinVerified_*`、`tlsMaterial` |
| ADR-002 §4 pin 格式/轮换 | `TlsMaterial`/`ProvisioningTlsMaterial` + `pinVerified` |
| ADR-002 §6 三档案/禁止回退 | profile 持久化 + `P-BLOCKED` 拒绝 + `tlsMaterial` |
| ADR-002 §8.3/§8.4 存储边界/轮换 | `StorageConstants` alias + `rotateSecret` 用例 |
| PR-06 绑定 identity 一致 | `commitBinding` 使用 `BleProvisioningResult.identity.gatewayId`；C-19/C-23 负责验签一致性 |
| FC-03 key_id 不滚动 | `keyId = app-key-v1` |
| D-019 host/device | Node 161 用例（wp-022 后 166）+ 设备 skeleton（已注册，BLOCKED） |

---

## 7. 复现

```bash
cd /home/quirkybrain/code/harmony-projects/YaoCore
ohpm install
hvigorw clean assembleHap --no-daemon
codelinter -c code-linter.json5 -p default .
entry/src/test/run-host-tests.sh

# 附加（非门禁必需）：
hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon
timeout 300 hvigorw test --no-daemon   # 预期：UnitTestArkTS 成功后 Previewer BLOCKED
```
