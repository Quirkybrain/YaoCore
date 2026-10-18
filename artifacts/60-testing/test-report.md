# TEST-REPORT-001 全量测试执行与验证证据（T-19）

- **Artifact ID**: TEST-REPORT-001
- **Producer**: agent:test-engineer
- **Type**: Test Execution Report / Coverage Matrix / Evidence Record
- **Status**: COMPLETE（供 T-20 独立评审、IG-4 与 G-014 Stage Gate 消费；不授予 Gate PASS）
- **Date**: 2026-10-18
- **Task**: `wp-082-verify`（T-19；task 分支 `task/wp-082-verify`，父分支 `feat/yaocore-app`，base commit `4f7c26be664a8db8aaba136fce1f128ccc72223a`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`
- **Upstream**: TEST-001 @ G-008（`fa21c67`）；CQG-T06..T18；DES-A §2.2；DES-B §2.3/§18.1；T-18 裁定 `4b99e64`；T-17/T-18 评审 R3-01/R3-02/R4-01
- **写范围**: `artifacts/60-testing/`、`entry/src/test/`、`tools/contract/`；未修改产品代码、构建配置或 `input/`。

> **文档注记（agent:technical-writer，wp-110，2026-10-18）**：本报告是 T-19 在 base `4f7c26b` 的历史执行记录，**不是最终候选报告**。其后 T-20 将 Host 用例由 696 增至 697；T-23 / wp-090（修复 wp-093）建立 `contracts/**` 并把 D-12 收口为 6 active / 7 retired；最终候选测试以 **TEST-002 @ `e74a181`**（`artifacts/60-testing/testing-stage-report.md`）为准。以下原文与原始证据保留；仅对明确计数错误加 `【勘误】` 标记，不回溯改写历史结论。

> **结论先行**：在 base `4f7c26b` 的集成候选上，host 纯逻辑 **696/696 PASS**（新增 2 条 R3-01 并发/失败隔离用例），契约 crosscheck **66/66 PASS**，仿真器套件 **20/20 PASS**（需 `no_proxy=127.0.0.1` 绕过本机代理；默认环境首跑为 `FAIL_ENV`，已保留证据），i18n **CHK-01..09 全 PASS / 0 blocking / 0 missing**，分层检查器 **0 violation（13 条 R3-01 pending-T-20 例外可见）**，构建 **BUILD SUCCESSFUL**，`codelinter` **0 error / 25 warning**。设备/模拟器/真实 BLE/LAN/TLS/云/视觉/fps 仍 **BLOCKED/UNAVAILABLE**；ACK p95 仅有 **MOCK_ONLY** 值，不能作为 NFR 4.3 验收证据。
>
> **T-20 修订（2026-10-18）**：ACK p95 三项数字已按证据文件 `t19-ack-p95-mock.json` 更正为 p50 **0.536 ms** / p95 **0.598 ms** / max **0.684 ms**（原 0.526/0.601/0.647 为笔误，见 F-03）；i18n `--strict-ui` 在 T-20 真正生效，CHK-07 不再把 `LOADING`/`RECONFIGURE` 等状态常量计为短 UI 文案，重跑为 **0 blocking / 55 warnings / hardcoded 16**（T-19 的 121/82 是旧 checker 计数）。分层检查器已读取 `port_location_exceptions` 并把 13 条 D-12 例外定为 `accepted`；T-20 证据见 `tooling-cleanup-report.md`。

---

## 0. 分类图例

| 分类 | 含义 |
|---|---|
| `PASS` | 当前 revision、当前环境实际执行且断言通过 |
| `FAIL_PRODUCT` | 实际执行失败，定位为产品行为/契约不符 |
| `FAIL_TEST` | 实际执行失败，定位为测试缺陷 |
| `FAIL_ENV` | 实际执行失败，定位为环境问题 |
| `BLOCKED` | 前置条件不满足，未能执行（设备/签名/运行器） |
| `COMPILED_ONLY` | 只编译通过，未执行断言；**不是 PASS** |
| `NOT_RUN` | 计划存在但未执行 |
| `UNAVAILABLE` | 当前环境无法获得的证据 |

> 本报告不把 `COMPILED_ONLY`、`BLOCKED`、`NOT_RUN`、`UNAVAILABLE` 写成 PASS。

## 1. 环境与 revision

| 项 | 实测值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore` |
| 分支 / base | `task/wp-082-verify` / `4f7c26b`（`feat/yaocore-app` 集成候选） |
| OS | Linux x86_64 |
| `hvigorw` | 6.26.8 |
| `ohpm` | 26.0.0.630 |
| `codelinter` | 6.0.240 |
| Node | v24.15.0（`node:test` + `stripTypeScriptTypes`） |
| Java | OpenJDK 21.0.12.1 |
| Python | 3.12.3（仅标准库） |
| SDK | HarmonyOS 26.0.0.105（apiVersion 26） |
| `DEVECO_SDK_HOME` | `/home/quirkybrain/harmonyos/command-line-tools/sdk` |
| `hdc list targets` | 空；无模拟器实例；`signingConfigs: []` |
| 代理 | 环境设置 `HTTP(S)_PROXY=127.0.0.1:7890`；Python `urllib` 对 `127.0.0.1` 仍走代理并改写 header 大小写，套件需 `no_proxy=127.0.0.1,localhost` |

## 2. 分层结果总表

| # | 层 | 命令 | 结果 | 分类 | 证据 |
|---|---|---|---|---|---|
| 1 | 依赖安装 | `ohpm install` | exit 0，`install completed` | **PASS** | `entry/src/test/evidence/t19-ohpm-install.log` |
| 2 | 构建 | `hvigorw clean assembleHap --no-daemon` | `BUILD SUCCESSFUL in 14 s 274 ms`；35 tasks；unsigned HAP | **PASS** | `t19-clean-assemble.log` |
| 3 | 静态检查 | `codelinter -c code-linter.json5 -p default .` | `Defects: 25; Errors: 0; Warns: 25` | **PASS（0 error）** | `t19-codelinter.log` |
| 4 | 测试 HAP | `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | `BUILD SUCCESSFUL in 13 s 218 ms` | **COMPILED_ONLY** | `t19-ohosTest-assemble.log` |
| 5 | Host 纯逻辑 | `entry/src/test/run-host-tests.sh` | `1..696`、pass **696**、fail 0、skipped 0、exit 0 | **PASS** | `t19-host-node-tests.tap` |
| 6 | 协议 crosscheck | `python3 tools/contract/crosscheck_protocol_assets.py` | 66 PASS / 0 FAIL / 14 FINDING；exit 0 | **PASS 66/66** | `t19-crosscheck.log` |
| 7 | 网关契约套件（HTTP+TLS） | `no_proxy=127.0.0.1,localhost python3 -m unittest tools.simulator.test_gateway_contract -v` | `Ran 20 tests ... OK`；exit 0 | **PASS 20/20** | `t19-simulator-contract.log` |
| 7a | 同上，默认代理环境 | `python3 -m unittest ...`（无 `no_proxy`） | 1 ERROR：`KeyError: 'X-YaoCore-Simulator'`；代理把 header 改写为 `X-Yaocore-Simulator` | **FAIL_ENV**（受控重跑转为 #7 PASS） | `t19-simulator-contract-proxy-fail.log` |
| 8 | 仿真器 HTTP 实启 | `gateway_contract_server.py --port 9388` + `curl --noproxy '*' /discover` | 200；4 devices；`X-YaoCore-Simulator: DEV-ONLY` | **PASS（MOCK_ONLY）** | `t19-http-simulator.log` |
| 9 | 仿真器 TLS 实启 | `--tls --cert ... --key ...` + `curl --noproxy '*' -k /health` | 200；SPKI `63f928c4…3243`；DEV-ONLY | **PASS（MOCK_ONLY）** | `t19-tls-simulator.log` |
| 10 | i18n CHK-01..09 | `python3 entry/src/test/i18n/check_i18n.py --root . --report ... --allowlist ... --strict-ui` | exit 0；blocking **0**；missing **0**；warnings 121；hardcoded 82（均非阻断；T-20 重跑计数见修订说明） | **PASS** | `t19-i18n-checker.log`、`t19-i18n-report.json` |
| 11 | 分层静态扫描（C-29） | `python3 tools/contract/check_layering.py --root . --report ...` | 209 files；**0 violation**；13 条 `pending-T-20` R3-01 例外 | **PASS（含可见例外）** | `t19-layering.log`、`t19-layering.json` |
| 12 | 检查器 fixture 自测 | `python3 -m unittest tools.contract.test_check_layering -v` | 4/4 PASS（合法树通过；违规树覆盖 D-01/02/06/08/09/11/12/13/17；仓库树 0 违规；缺失根 exit 2） | **PASS** | `t19-layering-fixture-tests.log` |
| 13 | 安全负例聚焦 | Node runner + `--test-name-pattern`（9 文件） | 19/19 PASS | **PASS（host/仿真）** | `t19-security-negative.tap` |
| 14 | ACK p95（mock） | `python3 tools/contract/measure_ack_latency.py --samples 100 --warmup 5` | p50 0.536 ms / p95 **0.598 ms** / max 0.684 ms；0 failures | **MOCK_ONLY（非产品验收）** | `t19-ack-p95-mock.json` |
| 15 | 设备/UI/BLE/LAN/真实云/视觉/fps | `onDeviceTest`；真实环境 | 无设备/签名/真实网关 | **BLOCKED / UNAVAILABLE** | 见 §7 |

### 2.1 Host 用例分层（696）

| 领域 | 主要文件（用例数） |
|---|---|
| 基础/协议 | Foundation 16、HostBaseline 2、HostProtocol 9、ProtocolDiscover 10、ProtocolControl 8、ProtocolAck 16、ProtocolCloud 8、ProtocolIdentity 5 |
| 安全/存储/网关 | Crypto 18、Security 16、Storage 15、GatewayRepository 29、GatewayLocal 35、GatewayDiscovery 24、GatewayMock 17、TransportBoundary 3 |
| 领域 | DomainModels 10、DomainDevice 31、DomainRoom 10、DomainScene 16、DomainFamily 29 |
| i18n/云/AC | I18n 28、CloudService 18、AcAdapter 8 |
| BLE | BleCodec 15、BleSecurity 18、BleGattFlow 40、BleService 24 |
| ViewModel/UI 壳 | ViewModelThrottle 7、ViewModelDevice **12**（含新增 2）、ViewModelCoordinator 7、ViewModelDoor 9、ViewModelDoorVM 9、ViewModelHome 7、ViewModelClimate 5、ViewModelFamily 12、ViewModelRoom 8、ViewModelScene 8、ViewModelBle 18、ViewModelSettings 11、AppShell 43、UiPages 28 |
| 性能 harness | PerfHarness 4 |

> 新增：`T19_R3_concurrentCrossDeviceInFlightDispatchesAreIsolated`、`T19_R3_crossDeviceFailureDoesNotMutateOtherSession`（`ViewModelDevice.test.mjs`），关闭 t15-16-review-c §R3-01 的并发/失败隔离缺口；原 694 条全部保留。

## 3. C-29 分层检查器与 R3-01 处理

### 3.1 落地内容

- `tools/contract/check_layering.py`：D-01/02/03/05/06/08/09/11/12/13/17 的可执行实现；`--report` JSON、`--list-exceptions`、退出码 0/1/2。
- `tools/contract/layering_allowlist.json`：**文件/符号级**例外，禁止目录级放宽；每条含 `status`、`reason`、`evidence`。
- `tools/contract/fixtures/layering/{good,bad}/`：合法树 + 每类违规树。
- `tools/contract/test_check_layering.py`：4 条自测（含“仓库树 0 违规、R3-01 必须在报告中以 pending 可见”）。
- **D-03 当前无输入（历史 @ `4f7c26b`）**：本报告执行时仓库尚无 `contracts/**` 目录（端口位置例外，见 §3.2）；规则已就绪，待迁移后生效。**【勘误】T-23 / wp-093 已建立 `contracts/**`（20 个文件），D-03 现已有真实输入并执行 type-only / 无环规则；最终状态见 DES-A §27.6.4 与 TEST-002。**
- **D-13 实际路径**：设计名义 `adapter/ac/**`，实现位于 `service/ac/**`；检查器按实际路径执行。

### 3.2 当前例外（历史快照 @ `4f7c26b`）

> **历史说明**：下表是 T-19 执行时的例外状态。T-20 已将 13 条 D-12 定为 `accepted`；T-23 / wp-093 后 live D-12 为 **6 active / 7 retired**，端口位置例外为 **1 条（PORT-LOC-01，`used=0`）**，17 条中 16 条已迁移。此处保留原快照，不回溯改写；当前状态见 DES-A §27.6.4 / DES-B §18.1 与 TEST-002。

| 类别 | 条目 | 状态（历史） | 说明 |
|---|---|---|---|
| D-12 pages 既有只读 DTO/枚举（R3-01） | 13 条：`DeviceRecord`/`Scene*`、`FamilyMemberView`/`InvitationView`/`InviteCreation`、`CreateInvitationInput`/`FamilyJoinPhase`、`BleProvisioning*`、`RoomDeletionPreview`、`CloudTransportState`/`CloudConfigView` | **pending-T-20** | 与 `t18-review-c.md` §R3-01 一致；检查器不放宽整个 `service/**`/`repository/**` |
| 端口位置例外（T-06 R-13、T-07 R-08、T-08、T-09、T-11 D-1、T-14） | `repository/**` → `service/storage/{RdbStore,PreferencesStore,SecretStore,SecretDraftPort,MigrationPort}`；`viewmodel/**` → `service/{ble/BleProvisioningPorts,ble/GattEndpointMap,crypto/CryptoPort,gateway/GatewayTransportPorts,gateway/DiscoveryModels,storage/*}` | **accepted（实现内置）** | DES-A/B 名义位置为 `contracts/**`；T-23 后 16/17 已迁移，仅 PORT-LOC-01 OPEN |
| 适配器内部 helper | `service/gateway/adapters/OhosHttpTransport` / `SocketTlsPinVerifier` → `./TlsPinCheck` | **accepted（实现内置）** | 仅允许同一 `adapters/` 目录内 helper；任何纯逻辑层 import adapter 仍失败 |

> **工具边界**：D-04/D-10（host-safe）、D-07/D-14（Mock 生产排除）、D-15（云 HTTP 隔离）、D-16（i18n）由其他检查器/评审负责；当前 Mock 生产排除证据使用 host `TransportBoundary`/`AppShell` 源码守卫。检查器 PASS **不等于** T-20 已正式收口 R3-01。

## 4. 安全负例矩阵（TEST-001 SEC-N01..N26）

| ID | 场景 | 结果 | 证据（当前 revision） |
|---|---|---|---|
| SEC-N01 | 坏签名 | **PASS（host+sim）** | `C17_control_badSignatureFailsClosedWithoutRetry`、`test_bad_signature_does_not_consume_nonce` |
| SEC-N02 | 过期时间戳 >±120s | **PASS（host+sim）** | `C05_timeWindowBoundaryIsInclusiveAt120Seconds`、`test_stale_timestamp_does_not_consume_nonce` |
| SEC-N03 | 精确重传/重放 | **PASS（host+sim）** | `C17_control_retriesExactBytesOnTimeout`、`C03_ControlAckMapper_replayDoesNotDuplicateAlreadyAppliedState`、`test_exact_authenticated_retransmission_returns_cached_ack` |
| SEC-N04 | 同 nonce 改 payload/sign | **PASS（host+sim）** | `C05_RequestSigner_rejectsRepeatedNonceAndBadSecrets`、`C20_replay_sameCommandReplaysAndDifferentCommandReturns1005`、`test_same_nonce_with_changed_bound_data_is_rejected` |
| SEC-N05 | 未知 `key_id` | **PASS（sim）** | `test_unknown_key_is_rejected`；客户端出站 key 固定，无降级路径 |
| SEC-N06 | 未知 `alg` | **PASS（host）** | `C03_ControlRequestSerializer_rejectsFieldViolations`（HMAC-SHA1 → `PROTOCOL_UNSUPPORTED_VERSION`）、`C05_ResponseVerifier_negativePathsUseContractErrorCodes` |
| SEC-N07 | 响应签名坏/缺 header | **PASS（host）** | `C17_control_http500WithBadSignatureFailsClosedWithoutRetry`、`C05_ResponseVerifier_negativePathsUseContractErrorCodes` |
| SEC-N08 | correlation 错 | **PASS（host）** | `C03_ControlAckMapper_correlationMismatchFailsClosed`、`C17_control_badCorrelationFailsClosedWithoutRetry` |
| SEC-N09 | `result_code != 0`（含未知） | **PASS（host）** | `C03_ControlAckMapper_nonZeroResultNeverClaimsSuccess`（1004/1005/1006/1007/1008/9999） |
| SEC-N10 | `result_code==0` 缺 `reported_state` | **PASS（host）** | `C03_ControlAckMapper_zeroWithoutReportedStateIsProtocolViolation`、`C17_control_successWithoutReportedStateIsProtocolViolation` |
| SEC-N11 | 目标/动作不一致 | **PASS（host）** | `C03_ControlAckMapper_targetMismatchThrowsStateMismatch`、`C17_control_stateTargetMismatchIsRejected` |
| SEC-N12 | `success:true`/仅 HTTP 2xx | **PASS（host）** | `C03_ControlAckMapper_successFieldIsAlwaysIgnoredAndCounted`、`C17_control_successWithoutReportedStateIsProtocolViolation` |
| SEC-N13 | DEV-ONLY 响应 | **PASS（host+sim）** | `C17_devOnlyResponseRejectedBeforeVerification`；仿真器持续发送 `X-YaoCore-Simulator: DEV-ONLY` |
| SEC-N14 | 未知 `result_code=9999` | **PASS（host）** | `C03_ControlAckMapper_nonZeroResultNeverClaimsSuccess`、`C01_GatewayResultClassifier_separatesGatewayNamespace` |
| SEC-N15 | TLS pin mismatch | **PASS（host/mock）**；真实设备 **BLOCKED** | `C17_tlsPinMismatchNeverFallsBackToCleartext`、`C19_BleProvisioningService_tlsPinMismatchNeverBinds`、`C20_tlsPinMismatchAndHandshakeFail_areHardFailures` |
| SEC-N16 | TLS 握手失败 | **PASS（host/mock）**；真实设备 **BLOCKED** | `C17_tlsHandshakeFailureIsLoggedWithoutSecret`、`C20_tlsPinMismatchAndHandshakeFail_areHardFailures` |
| SEC-N17 | 宣告 TLS 但无 pin/非法 | **PASS（host）** | `C17_tlsProfileWithMissingPinsSendsNoRequest`、`C18_lastKnown_tlsRouteWithoutPinEvidenceIsNotVerified` |
| SEC-N18 | 重复 JSON key / NaN / Infinity | **PASS（host+sim）** | `test_duplicate_json_keys_are_rejected`、`C03_ControlAckMapper_rejectsUnknownFieldsAndInvalidTypes`、严格 JSON |
| SEC-N19 | 未知设备/不支持动作/离线 | **PASS（host+sim）** | `test_authenticated_but_unsupported_command_is_not_confirmed`、`C03_ControlRequestSerializer_enforcesActionValueKind`、`T09_C10_*` |
| SEC-N20 | 硬件超时/1008 | **PASS（host，分类级）** | `C01_GatewayResultClassifier`（1008 retryable）、`C03_ControlAckMapper_nonZeroResultNeverClaimsSuccess`；无独立硬件复现（FC-02） |
| SEC-N21 | identity 多余字段/常量不符 | **PASS（host/fake）**；设备 **BLOCKED** | `C19_IdentityNegotiator_v20ExtraFieldFailsClosed`、`C03_IdentityParser_v21FailsClosedOnUnknownOrInconsistentFields` |
| SEC-N22 | 邀请 AAD 篡改/过期/maxUses/重放 | **PASS（host）** | `C13_containerRejectsAadTamperCiphertextAndUnknownVersion`、`C13_expiredAndRevokedInvitationsFailClosed`、`C13_receiptLedger_replayAcrossRestart_d022` |
| SEC-N23 | GUEST 未授权房间/RBAC | **PASS（host）** | `C12_rbacMatrix_adminMemberGuestAndDeviceStates`、`T09_C08_rbacMatrixAndActorEnforcement`、`T18_C11_sceneRunRbacMatrix...` |
| SEC-N24 | 日志/异常泄漏 secret | **PASS（host）** | `C07_secretDiscipline_noPlaintextInPreferencesRdbOrErrors`、`C15_receiptSyntheticAndNoTokenLeakInDetails`、`C17_tlsHandshakeFailureIsLoggedWithoutSecret` |
| SEC-N25 | 生产组合根 import Mock | **PASS（host）** | `T11_noProductionFileImportsC20MockOrOhosTest`、`T17_productionMockExclusionCoversAllMainSources` |
| SEC-N26 | 非常数时间比较 | **PASS（host）+ 待 T-20 复核** | `C04_CryptoService_constantTimeEqualHandlesEveryShape`、`C04_CryptoService_inputLengthMismatchFromProviderFailsClosed`；代码评审归 T-20 |

> 新增的检查器不改变安全结论；`FAIL_ENV` 的仿真器首跑仅由本机代理 header 改写导致，受控重跑 20/20 PASS，未修改测试断言。

## 5. FR/NFR 覆盖矩阵（26 FR + NFR 4.1/4.2/4.3）

> `covered (host)` = 组件/VM 纯逻辑有当前 revision 实际执行的 host 证据；“UI/设备”列独立标注，不与 host PASS 混同。

| 需求 | 组件 → 接口/实现 | 关键宿主证据（示例） | 状态 | UI/设备 |
|---|---|---|---|---|
| FR-FAM-001 家庭创建/多家庭 | C-08 FamilyService/Repository → C-22 FamilyViewModel | `T09_C08_createFamilyCreatesAdminAndActivatesFirstFamily`、`T16_Family_createFamilyCreatesProfileAndActivates`、`T09_C08_switchFamily...` | **covered (host)** | BLOCKED |
| FR-FAM-002 成员邀请 | C-13 InviteService → C-08/C-22 | `InviteService` 19 条；`T09_C08_invitationReceiptStateMachine...`、`T16_Family_joinStateMachineAndProfileCompletion` | **covered (host)** | BLOCKED |
| FR-FAM-003 权限/移除 | C-12 AuthService/RbacPolicy → C-08/C-22 | `C12_rbacMatrix...`、`T09_C08_changeMemberRole...`、`T09_C08_removeMemberSuccess...` | **covered (host)** | BLOCKED |
| FR-FAM-004 退出/转让/解散 | C-08 → C-22 | `T09_C08_leaveFamilyRemovesMemberAndProfileOnly`、`T09_C08_transferAdmin...`、`T09_C08_dissolveFamily...` | **covered (host，v1 本地语义)** | BLOCKED |
| FR-ROOM-001 创建/独立 ID | C-09 RoomService/Repository → C-22 | `T09_C09_roomCreateRenameKeepsIdAndDefaultOrder` | **covered (host)** | BLOCKED |
| FR-ROOM-002 命名/ID 不变 | C-09 | `T09_C09_roomCreateRenameKeepsIdAndDefaultOrder`、`T16_Room_createRenameAndReorder` | **covered (host)** | BLOCKED |
| FR-ROOM-003 加入/跨房转移 | C-09/C-10 | `T09_C09_assignMoveAndUnassignFollowPoolSemantics`、`T16_Room_assignAndUnassignUseServicePorts` | **covered (host)** | BLOCKED |
| FR-ROOM-004 删除保护/禁用 | C-09 | `T09_C09_deleteRoomIsOneTransactionDevicesUnassignedGrantsRemoved`、`T09_C09_deleteRoomRollsBack...` | **covered (host)** | BLOCKED |
| FR-ROOM-005 设备删除房间无感 | C-10 | `T09_C10_removeDeviceCleansSceneReferences`、`T09_C10_removeDeviceRollsBack...` | **covered (host)** | BLOCKED |
| FR-ROOM-006 设备别名/ID 不变 | C-10 | `T09_C10_renameAndAssignNeverTouchTheNetwork` | **covered (host)** | BLOCKED |
| FR-HOME-001 家庭/网关状态 | C-21 HomeViewModel | `T15_Home_initializeLoadsFamilyRoomsRecordsAndGatewayStatus`、`T15_Home_gatewayFailure...` | **covered (host)** | 视觉 BLOCKED |
| FR-HOME-002 房间快捷切换 | C-21 | `T15_Home_roomFilterAndUnassignedPoolSelectors`、`T18_filtersMatchAllRoomAndUnassigned` | **covered (host)** | 视觉 BLOCKED |
| FR-HOME-003 环境/人体感知 | C-21 + C-10 | `T15_Home_environmentAggregatesLatestSensorValuesOnly` | **partial**：真实 SHT30/PIR 数据 UNAVAILABLE | UNAVAILABLE |
| FR-HOME-004 快捷设备卡片 | C-21/C-24/C-25 | `T15_Device_threePhase...`、`T18_lightCardWiresPowerToggle...`、`T18_brightnessAndTemperature...` | **covered (host/source)** | 视觉 BLOCKED |
| FR-GW-001 BLE 权限/扫描 | C-19 → C-23 | `C19_BleProvisioningService_scanPermissionAndBluetoothFailClosed`、`C19_BleProvisioningService_publicScanDedupesAndStops` | **covered (host/fake)** | 真实 BLE BLOCKED |
| FR-GW-002 Security1 握手 | C-19 | `C19_Security1_step0MatchesFrozenVector`、`C19_Security1_rfc7748Vector`、`C19_Security1_tamperedDeviceVerify...` | **covered (host/fake)** | 真实 BLE BLOCKED |
| FR-GW-003 Wi-Fi 下发/探针 | C-19/C-17 | `C19_WifiProvisioningFlow_*`、`C19_BindingProber_*`、`T16_Ble_submitMapsStates...` | **covered (host/fake)** | 真实 LAN/BLE BLOCKED |
| FR-DEV-001 真实 ACK 确认 | C-03/C-17/C-21 | `C03_ControlAckMapper_nonZeroResult...`、`C17_control_success...`、`T15_Device_threePhase...` | **covered (host)** | 设备 BLOCKED |
| FR-DEV-002 灯光/55ms | C-21 + C-10 | `T15_Throttle_*` 7 条、`T15_Device_continuous55ms...` | **covered (host)** | FPS UNAVAILABLE |
| FR-DEV-003 门锁/门磁 | C-21 + C-10 | `T15_Door_*` 9 条、`T15_DoorView_*` 9 条 | **covered (host)** | 物理传感器 BLOCKED |
| FR-DEV-004 空调/品牌 | C-16/C-21 | `C16_*` 8 条、`T15_Climate_*` 5 条 | **covered (host)** | 真实 AC BLOCKED |
| FR-DEV-005 状态来源标记 | C-03/C-14/C-25 | `C03_DiscoverMapper_unknownTypeRoomModeColorAndStateSourceAreTolerated`、`T10_C14_errorMapper`（`stateSourceKey`）、`T18_lowRiskUiGuards_sourceLevel`、`ViewModelHome` 环境来源 | **covered (host/source)** | 视觉 BLOCKED |
| FR-SCN-001 场景编排/局部失败 | C-11/C-22 | `T09_C11_*` **15 条**、`T16_Scene_*` **7 条**（【勘误】原文 16/8；实际 T-19 TAP 与当前 TAP 均为 15/7，见文首注记） | **covered (host)** | BLOCKED |
| FR-SET-001 家庭管理面板 | C-22/C-26 | `T16_Family_*`、`T18_familyJoinAndInviteGuards`、`T18_nonAdminRoomPool...` | **covered (host/source)** | 视觉 BLOCKED |
| FR-SET-002 E2E 加密/密钥配置 | C-04/C-05/C-07 + C-23 | `Security` 16、`Crypto` 18、`GatewayRepository` 29；P-TLS-PIN mock 全链 | **partial**：P-HMAC 按 ADR-002 无机密性；真实 TLS pin 设备 BLOCKED；LAN GCM `EXT-GCM-001` 归档 | 设备 BLOCKED |
| FR-SET-003 云/国际化 | C-15/C-14 | `CloudService` 18、`I18n` 28、`T16_Settings_*` 11；CHK-01..09 PASS | **covered (host)** | 真实 IoTDA UNAVAILABLE |
| NFR 4.1 传输安全 | C-04/C-05/C-17 | HMAC/±120s/nonce/replay/TLS pin 全链（host+sim） | **partial**：完整性/防重放 covered；P-HMAC 无机密性；真实 TLS BLOCKED | BLOCKED |
| NFR 4.2 存储安全 | C-06/C-12/C-13 | PBKDF2 120k、SecretStore/SecretDraft zeroize、邀请过期/账本；host PASS | **partial**：设备 Asset Store/RDB 未执行 | BLOCKED |
| NFR 4.3 性能 | C-17/C-21/C-25 | 55ms 7 条 PASS；ACK p95 **MOCK_ONLY 0.598 ms**；harness 4 条 PASS | **partial**：真实 p95 与 60/120fps UNAVAILABLE | UNAVAILABLE |

**统计**：26 FR 中 **24 covered (host)**、**2 partial**（FR-HOME-003 真实传感器、FR-SET-002 机密性/真实 TLS）、**0 gap**；NFR 4.1/4.2/4.3 均 **partial**（缺设备/真实环境证据）。所有 UI/设备格均为 `BLOCKED`/`UNAVAILABLE`，不计入 covered。

## 6. NFR 4.3 测量口径与结果

| 指标 | 结果 | 分类 | 口径/限制 |
|---|---|---|---|
| 55ms 节流 | **PASS** | host | `T15_Throttle_*` 7 条 + Device/Climate 连续控制；fake timer 精确推进 54/55ms、1 在途、latest 保留、TouchUp 强同步 |
| ACK p95 | **0.598 ms**（N=100，warmup=5，p50 0.536，max 0.684，0 fail） | **MOCK_ONLY** | localhost Python HTTP 仿真器；仅 transport+JSON 解析+结构校验；**不含** ArkTS 客户端验签/状态应用/真实 LAN/TLS pin/BLE/UI |
| 真实 ACK p95 ≤500ms | **UNAVAILABLE** | device/LAN | 无设备/模拟器/真实网关；不得用 mock 数字通过验收 |
| 60/120fps | **UNAVAILABLE** | device | 无 ArkUI frame profiler/设备；仅静态审查（无同步 IO/大列表策略） |
| 测量脚本 | `entry/src/test/host/perf-harness.mjs`（4 自测 PASS）、`tools/contract/measure_ack_latency.py`（本报告新增） | — | 结果 JSON 均带 `resultClass`/`limitations` |

## 7. BLOCKED / UNAVAILABLE 清单（如实）

| ID | 项 | 原因 | 现有替代证据 |
|---|---|---|---|
| BLK-01 | `hvigorw test`（Hypium host 断言） | Linux Previewer 缺 `libshared_libz.so` / `Linux is not supported` | Node runner 696/696；`UnitTestArkTS` 编译 PASS |
| BLK-02 | `onDeviceTest` | 无 `hdc` target、无模拟器、`signingConfigs: []` | ohosTest HAP 仅编译（COMPILED_ONLY） |
| BLK-03 | 真实 BLE 配网/射频 | 无设备/固件/ESP32 | host fakes 覆盖协议/状态机 |
| BLK-04 | 真实 LAN / TLS pin 对端 | 无真实网关；仿真器只证明 localhost 握手 | host/mock TLS 三态、SPKI 一致 |
| BLK-05 | 真实华为云 IoTDA | 无凭据/网络环境 | canonical/映射/完成判定 host 覆盖 |
| BLK-06 | UI 视觉/动效/可访问性/读屏 | 无设备/模拟器 | 构建 + 源码级 UI/RBAC 守卫 + host VM |
| BLK-07 | 60/120fps、真实 ACK p95 | 无设备/真实 LAN | mock harness + 明确不可外推 |
| BLK-08 | 真实硬件 AC/门磁/SHT30/PIR | 无设备 | 域/VM/协议 host 覆盖 |

## 8. 失败、缺口与建议

### 8.1 本次失败/异常

| ID | 现象 | 分类 | 处理 |
|---|---|---|---|
| T19-E01 | 仿真器套件默认代理环境 1 ERROR：`KeyError: 'X-YaoCore-Simulator'`；代理将 header 改写为 `X-Yaocore-Simulator` | **FAIL_ENV** | 受控重跑 `no_proxy=127.0.0.1,localhost` → 20/20 PASS；两份日志均保留；未改测试/产品 |
| — | 无产品行为失败、无测试断言失败 | — | — |

### 8.2 缺口与建议（不写成 PASS）

1. **R3-01（Low，T-20）**：13 条 pages 既有 service/repository DTO/枚举 import 仍是 `pending-T-20`；检查器已按文件/符号登记，T-20 必须正式纳入 DES-B §2.3/§18.1 或迁移到 `model/**`，不得把当前 PASS 解释为 D-12 已完全收口。
2. **T-18 GAP-T18-01（Medium）**：`addGatewayToFamily` 服务层 RBAC 缺口由 D-030 书面接受但未闭合；Stage Gate 必须记录，T-19 不改变该结论。
3. **R4-01（Info）**：`addGatewayToFamily` 已发起后的取消边界仅有文档声明，无 durable 回滚测试；建议 T-20/后续任务补边界用例或在 README 如实标注。
4. **端口位置例外**：`contracts/**` 迁移未完成；`check_layering` 以已登记例外放行，T-20 应决定迁移或正式合同化。
5. **测试源码 lint**：`code-linter.json5` 仍忽略 `src/test/**`、`src/ohosTest/**`；本任务未改构建配置。测试源码只有 Node 解析/编译门禁，无 lint PASS。
6. **覆盖工具**：无行/分支覆盖率；本报告只报告用例数与需求映射。
7. **设备矩阵**：T-18 评审要求的按钮禁用可见性/取消/门磁引导/权限 CTA 等 UI 设备项仍未执行；IG-3 仍 NOT READY。

## 9. 验证命令（可复现，cwd = 仓库根）

```bash
export DEVECO_SDK_HOME=/home/quirkybrain/harmonyos/command-line-tools/sdk
ohpm install
hvigorw clean assembleHap --no-daemon
codelinter -c code-linter.json5 -p default .
hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon
entry/src/test/run-host-tests.sh
python3 tools/contract/crosscheck_protocol_assets.py
no_proxy=127.0.0.1,localhost NO_PROXY=127.0.0.1,localhost \
  python3 -m unittest tools.simulator.test_gateway_contract -v
python3 entry/src/test/i18n/check_i18n.py --root . \
  --report entry/src/test/evidence/t19-i18n-report.json \
  --allowlist entry/src/test/i18n/allowlist.json --strict-ui
python3 tools/contract/check_layering.py --root . \
  --report entry/src/test/evidence/t19-layering.json
python3 -m unittest tools.contract.test_check_layering -v
python3 tools/contract/measure_ack_latency.py --samples 100 --warmup 5 \
  --json entry/src/test/evidence/t19-ack-p95-mock.json
```

## 10. Traceability

- Requirements：`input/requirements/YaoCore_HarmonyOS_App_Requirements.md` §3（26 FR）/§4（NFR 4.1..4.3）。
- Contracts：DES-A §2.2 D-01..D-08；DES-B §2.3 D-09..D-17、§18.1 C-29；ADR-002（P-HMAC/P-TLS-PIN、EXT-GCM-001）；ADR-003（邀请容器）。
- Components：`artifacts/30-plan/component-graph.md` C-01..C-29；CQG 证据 `state/gates/CQG-T06..T18.md`。
- Tests：`entry/src/test/host/**`（696）、`entry/src/test/i18n/check_i18n.py`、`tools/contract/**`、`tools/simulator/**`。
- Evidence：`entry/src/test/evidence/t19-*`（本报告引用的全部日志/JSON/TAP）。
- 下游：T-20 独立评审（安全/分层/测试真实性）、T-21 README/维护计划、T-22 IG-4/G-014 Stage Gate。

---

> **最终候选指向（wp-110）**：本报告的历史结论（696 host、13 pending D-12、无 `contracts/**`）不适用于最终候选。最终候选的构建 / lint / Host 697 / crosscheck / simulator / layering / fixture / i18n / triage 证据见 **TEST-002 @ `e74a181`**（[`testing-stage-report.md`](testing-stage-report.md)）；验收结论见 ACCEPT-001。本报告仅作为 T-19 历史证据保留。

*TEST-REPORT-001 结束。所有 PASS 均对应当前 base `4f7c26b` + 本任务工作树实际执行；设备/真实环境证据明确标为 BLOCKED/UNAVAILABLE。*
