# TEST-002 最终集成候选测试 Stage 报告

- **Artifact ID**: TEST-002
- **Producer**: agent:test-engineer
- **Type**: Testing Stage Report / Full Matrix Re-run / FR-NFR Acceptance Mapping
- **Status**: **COMPLETE @ `e74a181`**（本报告只陈述当前 revision 实际执行证据；不授予 acceptance、设备验收或 release PASS）
- **Date**: 2026-10-18
- **Task**: `wp-106-testing-stage`（G-016 testing Stage；task 分支 `task/wp-106-testing-stage`，父分支 `feat/yaocore-app`，base commit `e74a181cebec1968d9a197c38e350cd2dda6cc80`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `testing`
- **Upstream**: `test-plan.md`（TEST-001 @ G-008）、`test-report.md`（TEST-REPORT-001 @ T-19/T-20）、`integration-report.md`（INTEGRATION-REPORT-001 @ T-22 + §11–§14 合并记录）、`final-system-review.md`（REV-001-FINAL-SYSTEM @ T-20）、`README.md`（README-001 v1.0）、G-014/G-015
- **Write scope**: `artifacts/60-testing/`；未修改产品代码、测试断言、契约、构建配置、README 或 `input/`。

> **结论先行**：在最终集成候选 `e74a181` 上，**11 项强制矩阵命令全部实际执行且 exit 0**：`ohpm install`、干净 HAP 构建、`codelinter`（0 error / 25 warning）、Host 纯逻辑 **697/697**、协议 crosscheck **66/66 hard checks + 14 条既有 FINDING**、仿真器契约 **20/20（HTTP+TLS）**、分层检查 **0 violation（6 条 D-12 accepted；PORT-LOC-01 未触发）**、分层 fixture **27/27**、i18n `--strict-ui` **0 blocking / 0 missing / 73 warning / 16 hardcoded**、i18n triage **615 行一致**、ACK p95 **MOCK_ONLY 0.609 ms**。
>
> **未发现产品行为失败、测试断言失败或环境失败（0 FAIL_PRODUCT / 0 FAIL_TEST / 0 FAIL_ENV）。** 设备/模拟器/真实 BLE/LAN/TLS/云/视觉/fps 仍为 **BLOCKED/UNAVAILABLE**，ACK p95 只能标 **MOCK_ONLY**，不能作为 NFR 4.3 验收。
>
> **Verdict: `PASS_WITH_ACCEPTED_RISKS`（代码级 testing Stage）**。建议允许进入 **acceptance 分析**，但不得把本报告解释为产品验收、设备验收或 release 完成；条件见 §7。
>
> **文档注记（agent:technical-writer，wp-110，2026-10-18）**：本报告的测试证据仍针对 `e74a181`，不因文档同步改变。§5.2 所列“README 旧口径（596 条 `PENDING_REVIEW`）”已在 documentation 阶段关闭：README v1.1 已改为 10 ACCEPTED / 46 MIGRATED / 6 PENDING / 0 INLINE / 544 OBSOLETE_LEGACY（另 11 B / 6 C / 3 D）；当前状态见 README 与维护计划 v1.1。

---

## 0. 分类与证据边界

| 分类 | 本报告含义 |
|---|---|
| `PASS` | 在 `e74a181`、本机环境实际执行且断言通过 |
| `PASS（host）` | Node 24 runner 加载生产 `.ets` 纯逻辑并注入 fake；不是 ArkTS/Hypium 设备运行 |
| `PASS（mock/sim）` | localhost Python 仿真器/契约套件；不是真实网关、真实 LAN 或真实 TLS 对端 |
| `COMPILED_ONLY` | 只编译通过，未执行断言；**不是 PASS** |
| `MOCK_ONLY` | 仅 localhost 测试替身测得，不得外推为产品验收 |
| `BLOCKED` | 前置条件不满足（无设备/模拟器/签名/真实环境） |
| `UNAVAILABLE` | 当前环境无法获得的证据（真实 fps、真实 LAN p95 等） |
| `FAIL_ENV` | 环境导致失败；本次未出现 |

> 本报告不把 `COMPILED_ONLY`、`MOCK_ONLY`、`BLOCKED`、`UNAVAILABLE` 写成 PASS，也不把 Host 697/697 解释为 UI、BLE、LAN、TLS、云或硬件验收。

---

## 1. 范围、revision 与环境

### 1.1 Revision

| 项 | 实测 |
|---|---|
| 仓库根 / cwd | `/home/quirkybrain/code/harmony-projects/YaoCore` |
| 分支 | `task/wp-106-testing-stage` |
| HEAD / base commit | `e74a181cebec1968d9a197c38e350cd2dda6cc80`（G-015 review Stage Gate PASS） |
| 父分支 / 集成目标 | `feat/yaocore-app` |
| 工作树 | 执行前干净；本任务唯一写入 `artifacts/60-testing/` |
| 最终候选构成 | `d2896fb` 之后包含 A1 端口迁移、T-23 裁定修复、i18n triage、检查器 RR 修复、DES F-03 状态同步；测试仍为 697 条 |

### 1.2 环境

| 项 | 实测值 |
|---|---|
| OS | `Linux 7.0.0-38-generic x86_64` |
| `ohpm` | 26.0.0.630 |
| `hvigorw` | 6.26.8 |
| `codelinter` | 6.0.240 |
| Node | v24.15.0（`node:test` + `stripTypeScriptTypes`） |
| Java | OpenJDK 21.0.12.1 |
| Python | 3.12.3（仅标准库） |
| SDK | HarmonyOS 26.0.0.105（`DEVECO_SDK_HOME=/home/quirkybrain/harmonyos/command-line-tools/sdk`） |
| 兼容范围 | `compatibleSdkVersion 5.0.2(14)`；`compileSdkVersion/targetSdkVersion 26.0.0` |
| 设备 | `hdc` 不在 PATH；SDK 绝对路径 `hdc list targets` 返回 `[Empty]`；无模拟器实例 |
| 签名 | `build-profile.json5` 的 `signingConfigs: []`；产物为 unsigned HAP |
| 代理 | 环境存在本机代理；仿真器套件按任务要求以 `no_proxy=127.0.0.1,localhost` 运行 |
| 构建产物 | `entry/build/default/outputs/default/entry-default-unsigned.hap`（4,597,005 B，14 个条目） |

### 1.3 证据纪律

- 所有命令均在仓库根、上述 revision 实际执行；退出码来自命令本身（使用 `pipefail`），日志保留在 `artifacts/60-testing/evidence/`。
- 证据日志只做了 ANSI 转义与行尾空白规范化；命令、输出、计数与退出码未改写。
- 未修改任何测试断言或产品代码；未切换分支、未 pull/merge/rebase/push。
- 设备/真实环境项没有执行，也没有被计入 PASS。

---

## 2. 执行矩阵与结果

> 以下 1–11 为任务规定的强制矩阵；12–14 为补充证据（明确标注，不计入强制矩阵通过数）。

| # | 命令（cwd = 仓库根） | 实测结果 | Exit | 分类 | 证据 |
|---|---|---|---|---|---|
| 1 | `ohpm install` | `install completed in 0s 47ms` | 0 | **PASS** | `evidence/t26-ohpm-install.log` |
| 2 | `hvigorw clean assembleHap --no-daemon` | `BUILD SUCCESSFUL in 14 s 602 ms`；35 tasks（34 executed / 1 up-to-date）；unsigned HAP | 0 | **PASS（构建）** | `evidence/t26-clean-assemble.log` |
| 3 | `codelinter -c code-linter.json5 -p default .` | `Defects: 25; Errors: 0; Warns: 25; Suggestions: 0` | 0 | **PASS（0 error）** | `evidence/t26-codelinter.log` |
| 4 | `entry/src/test/run-host-tests.sh` | `1..697`；tests 697 / pass 697 / fail 0 / skipped 0；≈3,102 ms | 0 | **PASS（host）** | `evidence/t26-host-node-tests.tap` |
| 5 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py` | 66 `[PASS]` / 0 `[FAIL]`；14 条冻结输入 `FINDING`；`hard checks: ALL PASS` | 0 | **PASS 66/66** | `evidence/t26-crosscheck.log` |
| 6 | `no_proxy=127.0.0.1,localhost PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tools.simulator.test_gateway_contract -v` | `Ran 20 tests in 0.598s`；`OK`（含 3 条 TLS 用例） | 0 | **PASS（mock/sim）20/20** | `evidence/t26-simulator-contract.log` |
| 7 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | `files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0`；`PASS` | 0 | **PASS（含已登记例外）** | `evidence/t26-layering.log` |
| 8 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/test_check_layering.py` | `Ran 27 tests in 2.447s`；`OK` | 0 | **PASS 27/27** | `evidence/t26-layering-fixture-tests.log` |
| 9 | `PYTHONDONTWRITEBYTECODE=1 python3 entry/src/test/i18n/check_i18n.py --strict-ui` | `blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16`；CHK-01..09 PASS | 0 | **PASS（0 blocking）** | `evidence/t26-i18n-checker.log` |
| 10 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/i18n/triage_legacy.py --check` | `615 rows`；`OK: CSV matches computed triage; invariants pass` | 0 | **PASS** | `evidence/t26-i18n-triage-check.log` |
| 11 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/measure_ack_latency.py --samples 100 --warmup 5 --json artifacts/60-testing/evidence/t26-ack-p95-mock.json` | p50 **0.553 ms** / p95 **0.609 ms** / max **0.650 ms**；N=100，warmup=5；0 failures；`resultClass=MOCK_ONLY`（脚本默认值即 samples=100/warmup=5；显式参数用于落盘 JSON，语义等价） | 0 | **MOCK_ONLY（非验收）** | `evidence/t26-ack-p95-mock.json`、`evidence/t26-ack-p95-mock.log` |
| 12 | `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon`（补充） | `BUILD SUCCESSFUL in 13 s 185 ms`；35 tasks；未运行断言 | 0 | **COMPILED_ONLY** | `evidence/t26-ohosTest-assemble.log` |
| 13 | HAP 内容检查（`unzip -l` + 逐条目扫描，补充） | 14 个条目；`MockGatewayService` / `MockBleProvisioningClient` / `ohosTest` / `service/mock` 均 **0 命中** | 0 | **PASS（Mock 生产排除）** | `evidence/t26-hap-mock-exclusion.log` |
| 14 | 设备/签名边界检查（补充） | `hdc` 不在 PATH；绝对路径 `hdc list targets` = `[Empty]`；`signingConfigs: []` | 0 / 127 | **BLOCKED（设备）** | `evidence/t26-device-boundary.log` |

### 2.1 矩阵计数

| 项 | 数量 |
|---|---|
| 强制命令 | **11** |
| 强制命令 `PASS`（含 `PASS（host）` / `PASS（mock/sim）` / `PASS（0 error）`） | **10** |
| 强制命令 `MOCK_ONLY`（不是验收 PASS） | **1**（ACK p95） |
| 强制命令 `FAIL_PRODUCT` / `FAIL_TEST` / `FAIL_ENV` | **0** |
| 补充证据 | 3（ohosTest 编译 `COMPILED_ONLY`、HAP 排除 PASS、设备边界 BLOCKED） |
| Host 用例 | **697/697 PASS** |
| 协议 crosscheck | **66/66 PASS**（14 条既有 FINDING） |
| 仿真器契约 | **20/20 PASS（HTTP+TLS）** |
| 分层 fixture | **27/27 PASS** |
| i18n | **0 blocking / 0 missing / 73 warning / 16 hardcoded** |
| i18n triage | **615 行一致** |

### 2.2 关键日志摘录

```text
# 4. host
1..697
# tests 697
# pass 697
# fail 0
# cancelled 0
# skipped 0
# todo 0
# duration_ms 3101.588059

# 5. crosscheck
hard checks: ALL PASS
findings about frozen inputs: 14

# 6. simulator
Ran 20 tests in 0.598s
OK

# 7. layering
check_layering: files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0
check_layering: PASS

# 8. layering fixture
Ran 27 tests in 2.447s
OK

# 9. i18n
summary: blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16

# 10. triage
i18n legacy triage check: 615 rows
OK: CSV matches computed triage; invariants pass

# 11. ACK p95 (MOCK_ONLY)
p50Ms 0.553 / p95Ms 0.609 / maxMs 0.65 / failures []
```

---

## 3. FR 验收映射（26 FR）

> 映射方法：沿用 TEST-REPORT-001 §5 的 26 行 FR→组件→测试锚点，并在本 revision 的 `t26-host-node-tests.tap` 中**逐项复核所列关键用例存在且通过**；未重新定义需求，也未把 source-level 守卫解释为 UI/设备行为。`covered (host)` 仅指纯逻辑有当前 revision 的 host 证据；设备/UI 列独立标注。
>
> 统计：**26 FR = 24 covered (host) + 2 partial + 0 gap**。所有 UI/设备列均为 `BLOCKED`/`UNAVAILABLE`，不计入 covered。

| # | FR | 组件/路径 | 当前 revision 证据（697 TAP / 套件） | 状态 | UI/设备边界 |
|---|---|---|---|---|---|
| 1 | FR-FAM-001 家庭创建/多家庭 | C-08 → C-22 | `T09_C08_createFamilyCreatesAdminAndActivatesFirstFamily`、`T16_Family_createFamilyCreatesProfileAndActivates`、`T09_C08_switchFamilyLocksSessionAndRequiresTargetProfile` | **covered (host)** | UI 切换 BLOCKED |
| 2 | FR-FAM-002 成员邀请 | C-13 → C-08/C-22 | `C13_*` 19 条（如 `C13_keyWrap_roundTripAppliesGatewayAndCreatesMemberReceipt`、`C13_familyJoinSession_drivesRealInviteServiceToCompleted`）；`T09_C08_invitationReceiptStateMachineAndWeakModeView`、`T16_Family_joinStateMachineAndProfileCompletion` | **covered (host)** | 邀请 UI/设备 BLOCKED |
| 3 | FR-FAM-003 权限/移除 | C-12/C-08 → C-22 | `C12_rbacMatrix_adminMemberGuestAndDeviceStates`、`T09_C08_rbacMatrixAndActorEnforcement`、`T09_C08_changeMemberRoleSuccessInvalidatesSessions`、`T09_C08_removeMemberSuccessInvalidatesSessionsAndGuidesRotation` | **covered (host)** | 成员列表/视觉 BLOCKED |
| 4 | FR-FAM-004 退出/转让/解散 | C-08 → C-22 | `T09_C08_leaveFamilyRemovesMemberAndProfileOnly`、`T09_C08_transferAdminUpdatesOwnerAndInvalidatesBothSessions`、`T09_C08_dissolveFamilyRemovesLocalDataProfilesAndClearsActive`、`T09_C08_lastAdminCannotBeRemovedDemotedOrLeave` | **covered (host，v1 本地语义)** | 无服务器实时同步；设备 BLOCKED |
| 5 | FR-ROOM-001 创建/独立 ID | C-09 → C-22 | `T09_C09_roomCreateRenameKeepsIdAndDefaultOrder`、`T16_Room_createRenameAndReorder` | **covered (host)** | 房间 UI BLOCKED |
| 6 | FR-ROOM-002 命名/ID 不变 | C-09 | `T09_C09_roomCreateRenameKeepsIdAndDefaultOrder`、`T16_Room_createRenameAndReorder` | **covered (host)** | 视觉 BLOCKED |
| 7 | FR-ROOM-003 加入/跨房转移 | C-09/C-10 | `T09_C09_assignMoveAndUnassignFollowPoolSemantics`、`T16_Room_assignAndUnassignUseServicePorts` | **covered (host)** | 拖拽/选择 UI BLOCKED |
| 8 | FR-ROOM-004 删除保护/禁用 | C-09 | `T09_C09_deleteRoomIsOneTransactionDevicesUnassignedGrantsRemoved`、`T09_C09_deleteRoomRollsBackRoomDeviceAndGrantOnFailure`、`T16_Room_confirmDeleteSuccessClearsPreviewAndRefreshesPool` | **covered (host)** | 删除确认 UI BLOCKED |
| 9 | FR-ROOM-005 设备删除房间无感 | C-10 | `T09_C10_removeDeviceCleansSceneReferences`、`T09_C10_removeDeviceRollsBackWhenSceneCleanupFails` | **covered (host)** | 设备列表 UI BLOCKED |
| 10 | FR-ROOM-006 设备别名/ID 不变 | C-10 | `T09_C10_renameAndAssignNeverTouchTheNetwork`、`T09_C10_aliasUsedIsDiagnosticAndNotPartial` | **covered (host)** | 命名 UI BLOCKED |
| 11 | FR-HOME-001 家庭/网关状态 | C-21 | `T15_Home_initializeLoadsFamilyRoomsRecordsAndGatewayStatus`、`T15_Home_gatewayFailurePreservesRecordsAndReportsOffline`、`T15_Home_tlsFailureReportsBlocked` | **covered (host)** | 视觉/实时刷新 BLOCKED |
| 12 | FR-HOME-002 房间快捷切换 | C-21 | `T15_Home_roomFilterAndUnassignedPoolSelectors`、`T18_filtersMatchAllRoomAndUnassigned`、`T15_Device_roomFilterAndUnassignedPool` | **covered (host)** | 横向滑动视觉 BLOCKED |
| 13 | FR-HOME-003 环境/人体感知 | C-21 + C-10 | `T15_Home_environmentAggregatesLatestSensorValuesOnly` | **partial**：真实 SHT30/PIR 数据 UNAVAILABLE | UNAVAILABLE |
| 14 | FR-HOME-004 快捷设备卡片 | C-21/C-24/C-25 | `T15_Device_threePhasePendingThenCommitted`、`T18_lightCardWiresPowerToggleAndKeepsPendingSliderLive`、`T18_brightnessAndTemperatureFollowPendingValueThenConfirmed` | **covered (host/source)** | 视觉/交互 BLOCKED |
| 15 | FR-GW-001 BLE 权限/扫描 | C-19 → C-23 | `C19_BleProvisioningService_scanPermissionAndBluetoothFailClosed`、`C19_BleProvisioningService_publicScanDedupesAndStops`、`T16_Ble_scanDeduplicatesAndSelectMovesToHandshake`、`T16_Ble_scanTimeoutWithoutResultsShowsRetryableError` | **covered (host/fake)** | 真实 BLE 扫描/权限 BLOCKED |
| 16 | FR-GW-002 Security1 握手 | C-19 | `C19_Security1_stateGuardsAndStep0Vector`、`C19_Security1_rfc7748Vector`、`C19_Security1_handshakeAndContinuousCtrStream`、`C19_Security1_wrongPopFailsClosedAndDestroysSession`、`C19_Security1_tamperedDeviceVerifyFailsClosed` | **covered (host/fake)** | 真实 BLE 射频/固件 BLOCKED |
| 17 | FR-GW-003 Wi-Fi 下发/探针 | C-19/C-17 | `C19_WifiProvisioningFlow_*` 7 条、`C19_BindingProber_*` 13 条、`T16_Ble_submitMapsStatesAndCommitsWithReissuedResultDraft`、`T18_C19_scanWifiAccessPointsHandshakesWithoutApplyingCredentials` | **covered (host/fake)** | 真实 LAN/BLE BLOCKED |
| 18 | FR-DEV-001 真实 ACK 确认 | C-03/C-17/C-21 | `C03_ControlAckMapper_nonZeroResultNeverClaimsSuccess`、`C17_control_successWithoutReportedStateIsProtocolViolation`、`T15_Device_threePhasePendingThenCommitted`、`T15_Device_threeSecondTimeoutRevertsAndIgnoresLateResult` | **covered (host)** | 真实设备 ACK BLOCKED |
| 19 | FR-DEV-002 灯光/55ms | C-21 + C-10 | `T15_Throttle_*` 7 条、`T15_Device_continuous55msCoalescesAndTouchUpSendsFinalValue`、`T15_Climate_temperatureContinuousCoalescesAndTouchUpCommits` | **covered (host)** | FPS/真实触控 UNAVAILABLE |
| 20 | FR-DEV-003 门锁/门磁 | C-21 + C-10 | `T15_Door_*` 9 条、`T15_DoorView_*` 9 条、`T18_doorStagesNeverUpgradeWithoutEvidence`、`T18_doorStageProgressNeverLightsSecuredWithoutEvidence` | **covered (host)** | 物理门磁 BLOCKED |
| 21 | FR-DEV-004 空调/品牌 | C-16/C-21 | `C16_*` 8 条、`T15_Climate_*` 5 条 | **covered (host)** | 真实 AC BLOCKED |
| 22 | FR-DEV-005 状态来源标记 | C-03/C-14/C-25 | `C03_DiscoverMapper_unknownTypeRoomModeColorAndStateSourceAreTolerated`、`T10_C14_errorMapper`、`T18_lowRiskUiGuards_sourceLevel`、`T15_Home_environmentAggregatesLatestSensorValuesOnly` | **covered (host/source)** | 视觉标注 BLOCKED |
| 23 | FR-SCN-001 场景编排/局部失败 | C-11/C-22 | `T09_C11_*` 15 条（如 `T09_C11_secondStepFailureIsPartialFailedWithoutRollback`、`T09_C11_sameSceneConcurrentRunIsRejectedAndNeverDoubleDispatches`）、`T16_Scene_*` 7 条 | **covered (host)** | 场景 UI BLOCKED |
| 24 | FR-SET-001 家庭管理面板 | C-22/C-26 | `T16_Family_*` 12 条、`T18_familyJoinAndInviteGuards`、`T18_nonAdminRoomPoolAndGatewayEntriesAreHidden`、`T18_R2_settingsReprovisionRequiresAdmin` | **covered (host/source)** | 视觉/RBAC 可见性 BLOCKED |
| 25 | FR-SET-002 E2E 加密/密钥配置 | C-04/C-05/C-07 + C-23 | `C04_*` 18 条、`C05_*` 16 条、`C07_*` 29 条；`C17_tlsPinMismatchNeverFallsBackToCleartext`、`C19_BleProvisioningService_tlsPinMismatchNeverBinds`、`C20_tlsPinMismatchAndHandshakeFail_areHardFailures` | **partial**：P-HMAC 按 ADR-002 无机密性；真实 TLS pin 设备 BLOCKED；LAN GCM `EXT-GCM-001` 归档 | 设备 BLOCKED |
| 26 | FR-SET-003 云/国际化 | C-15/C-14 | `C15_*` 18 条（如 `C15_sendAndConfirm_acceptanceIsNotCompletion`、`C15_completion_builtInDoubleMatchStaleAndVerification`）、`T10_C14_*` 28 条、`T16_Settings_*` 11 条；CHK-01..09 PASS | **covered (host)** | 真实 IoTDA/语言切换 UI UNAVAILABLE |

### 3.1 FR 映射结论

- **24/26 covered (host)**：家庭、房间、网关配网、设备控制、场景与设置纯逻辑均有 `e74a181` 实际通过的 host 证据。
- **2/26 partial**：
  - `FR-HOME-003`：环境数值聚合逻辑有 host 证据，但真实 SHT30/PIR 数据未获得；
  - `FR-SET-002`：HMAC/防重放/TLS pin 失败语义有 host/mock 证据，但 P-HMAC 不提供机密性、真实 TLS 对端未验证、GCM 载荷信封归档。
- **0 gap**：未发现需求行完全没有组件/测试锚点。
- **边界**：`covered (host)` 不等于 UI/设备验收；所有设备/视觉/真实网络项保持 `BLOCKED`/`UNAVAILABLE`。

---

## 4. NFR 与安全/性能/兼容性映射

### 4.1 NFR 4.1 / 4.2 / 4.3

| NFR | 验收关注点 | 当前 revision 证据 | 证据等级 | 状态 |
|---|---|---|---|---|
| **NFR 4.1 传输安全** | HMAC 完整性、±120s 时钟窗、300s nonce 防重放、可选 TLS/SPKI pin | `C05_*` 16 条（含 `C05_timeWindowBoundaryIsInclusiveAt120Seconds`、`C05_RequestSigner_rejectsRepeatedNonceAndBadSecrets`、`C05_NonceCache_ttlBoundaryAndCapacityEviction`）；`C17_*` 35 条；仿真器 `test_bad_signature_does_not_consume_nonce`、`test_stale_timestamp_does_not_consume_nonce`、`test_same_nonce_with_changed_bound_data_is_rejected`、`test_exact_authenticated_retransmission_returns_cached_ack`；TLS 用例 3 条 | **HOST + MOCK_ONLY（sim）** | **partial**：完整性/防重放覆盖；P-HMAC 无机密性；真实 TLS pin **BLOCKED** |
| **NFR 4.2 存储安全/隐私** | PBKDF2-SHA256 120k 加盐、秘密用后清零、邀请过期、系统安全存储 | `C04_CryptoService_pbkdf2Sha256MatchesNodeOracleAtContractMinimum`、`C04_CryptoService_kdfParametersFailClosed`；`C06_SecretDraftStore_putTakeIsOneShotAndSurvivesSourceDestroy`、`C06_SecretDraftStore_ttlBoundaryAndExpiryZeroize`、`C06_SecretDraftStore_clearAllAndDestroyClearBuffers`；`C13_expiredAndRevokedInvitationsFailClosed`、`C13_receiptLedger_replayAcrossRestart_d022`；`C07_secretDiscipline_noPlaintextInPreferencesRdbOrErrors` | **HOST** | **partial**：设备 Asset Store/RDB 未执行（**BLOCKED**） |
| **NFR 4.3 性能/响应** | LAN 控制 p95 ≤500ms；55ms 节流；60/120fps | 55ms：`T15_Throttle_*` 7 条 + `T15_Device_continuous55msCoalescesAndTouchUpSendsFinalValue`；ACK p95：**MOCK_ONLY** p50 0.553 / p95 0.609 / max 0.650 ms（N=100，0 fail）；fps：无设备 | 55ms = **HOST**；p95 = **MOCK_ONLY**；fps = **UNAVAILABLE/BLOCKED** | **partial**：真实 LAN p95 与 60/120fps 未测，mock 数值不得用于验收 |

### 4.2 安全负例矩阵（SEC-N01..N26）

> 26 项均在本 revision 的 host TAP 或 20/20 仿真器套件中有当前证据；设备相关子断言保持 `BLOCKED`。完整逐项映射见 TEST-REPORT-001 §4；本节按组复核，抽查用例全部存在于 `t26-host-node-tests.tap` 并通过。

| 组 | 覆盖 | 结果 | 证据等级 |
|---|---|---|---|
| SEC-N01..N06 | 坏签名、过期时间戳、精确重放、同 nonce 改 payload、未知 key_id/alg | **PASS** | HOST + SIM |
| SEC-N07..N12 | 响应验签/相关性、非零 result_code、缺 `reported_state`、目标/动作不一致、`success` 忽略 | **PASS** | HOST |
| SEC-N13 | DEV-ONLY/DEV_SIMULATOR_ONLY 在验签/解析前拒收 | **PASS** | HOST + SIM |
| SEC-N14 | 未知 result_code=9999 fail-closed | **PASS** | HOST |
| SEC-N15..N17 | TLS pin mismatch/握手失败/宣告 TLS 无 pin：不降级明文 | **PASS（host/mock）**；真实设备 **BLOCKED** | HOST / MOCK_ONLY |
| SEC-N18..N19 | 重复 JSON key/NaN/Infinity；未知设备/不支持动作/离线 | **PASS** | HOST + SIM |
| SEC-N20 | 硬件超时/1008 分类与“未确认到位” | **PASS（分类级）**；无独立硬件复现 | HOST |
| SEC-N21 | identity 多余字段/常量不符 fail-closed | **PASS（host/fake）**；设备 **BLOCKED** | HOST |
| SEC-N22..N23 | 邀请 AAD/过期/maxUses/重放；GUEST RBAC | **PASS** | HOST |
| SEC-N24..N26 | 秘密不泄漏、Mock 生产排除、常数时间比较 | **PASS**；Mock 排除同时有 HAP 级 0 命中；常数时间为代码/负例级证据，非统计计时 | HOST + BUILD |

**安全结论**：未发现未关闭 High/Critical；SEC-N15/N16/N21 的真实设备子断言仍为 `BLOCKED`，不能写成设备 PASS。

### 4.3 性能证据

| 指标 | 结果 | 等级 | 说明 |
|---|---|---|---|
| 55ms 节流 | **PASS**（7 条 throttle + 1 条 Device 连续控制 + 1 条 Climate 连续控制） | HOST | fake clock 精确推进；1 在途、latest 保留、TouchUp 强同步 |
| ACK p95 | **0.609 ms**（p50 0.553 / max 0.650 / N=100 / 0 fail） | MOCK_ONLY | 仅 localhost Python 仿真器；不含 ArkTS 验签/状态应用/真实 LAN/TLS/BLE/UI |
| 真实 LAN p95 ≤500ms | **UNAVAILABLE** | BLOCKED | 无真实网关/设备；不得用 mock 数字替代 |
| 60/120fps | **UNAVAILABLE** | BLOCKED | 无 ArkUI frame profiler/设备；仅源码级性能建议（lint 25 warning） |

### 4.4 兼容性与构建面

| 项 | 结果 | 等级 | 说明 |
|---|---|---|---|
| 干净 HAP 构建 | **PASS** | BUILD | `BUILD SUCCESSFUL`；35 tasks；unsigned HAP |
| 静态检查 | **PASS（0 error / 25 warning）** | BUILD | 25 条为自定义组件性能建议与 2 条 loop 状态读取建议 |
| 测试 HAP 编译 | **COMPILED_ONLY** | BUILD | 仅证明测试代码可编译，不证明设备断言 |
| HAP Mock 排除 | **PASS** | BUILD/HAP | 4 类测试替身字符串在 14 个 HAP 条目中 0 命中 |
| `compatibleSdkVersion 5.0.2(14)` | **静态/构建级 PASS；API 14 运行时未验证** | BUILD/BLOCKED | 构建日志存在 `BLOB` API ≥18 的既有兼容性 warning；无设备无法验证运行时 |
| 未签名产物 | **BLOCKED（不可安装）** | BLOCKED | `signingConfigs: []`；HAP 不能安装到设备 |

---

## 5. 缺陷、失败与残余

### 5.1 本轮失败/异常

| ID | 现象 | 分类 | 处理 |
|---|---|---|---|
| — | 无产品行为失败、无测试断言失败、无环境失败 | — | 11 项强制命令均 exit 0 |

### 5.2 已知 warning 与债务（均为非阻断或已登记）

| ID / 项 | 当前实测 | 影响 | 归属/处置 |
|---|---|---|---|
| `codelinter` 25 warning | 23 条 `@performance/avoid-overusing-custom-component-check`；2 条 `hp-arkui-no-state-var-access-in-loop`（DeviceControlPage:213、ProfilePage:77） | 非阻断；无证据表明影响帧率；fps 仍 UNAVAILABLE | 维护计划；设备性能任务复核 |
| i18n 73 warning / 16 hardcoded | `--strict-ui` 下 0 blocking / 0 missing；16 条均为非 UI 技术字符串（主题颜色注释、AC 品牌 CJK 名称、Mock 错误消息）；带 allowlist 重跑为 55 warning（`t26-i18n-checker-with-allowlist.log`） | 不阻断 | 维护轮；不得把 16 条写成用户可见硬编码 |
| crosscheck 14 FINDING | 冻结输入中的规范散文/示例/schema 差异（F.15/F.16/F.17/F.18/G result code 0/1001/1002/1003/1004/1006/1008） | 既有勘误线索，不阻断 hard checks 66/66 | `wp-004`/契约 owner；不得修改冻结输入以换 PASS |
| i18n legacy triage | **615 行**：A 606（ACCEPTED 10 / MIGRATED 46 / PENDING_REVIEW 6 / OBSOLETE_LEGACY 544）、C 6、D 3；**11 条 B_REWRITE_REQUIRED**、**6 条 C_REVIEW**（4 RECHECK + 2 SAFETY_RECHECK）；证据 `evidence/t26-i18n-triage-summary.log` | 历史文案未逐条人工签署；当前 UI 0 blocking | maintenance-plan；不得把 544/46 写成业务语义已签署 |
| `PORT-LOC-01` | `ClockPort`/`IdPort` 仍在 `common/types/Ports.ets`；live `port_location_exceptions` 仅 1 条，`port_exceptions_used=0` | 0 violation **不代表**端口位置完全合规；冻结签名例外未关闭 | Stage Gate/维护窗口；需 D-01 或签名变更后才能迁移 |
| `D-030 / GAP-T18-01` | `FamilyRepository.addGatewayToFamily` 无 actor/RBAC；D-030 书面接受 v1 风险，**未关闭** | 服务层 RBAC 缺口；补偿控制为 UI ADMIN 门 + BLE PoP + 内部 API 边界 | 后续 C-22/C-09/C-15 变更时复审；G-016/acceptance 必须记录 |
| `R4-01` | `addGatewayToFamily` 已发起后的取消不能 durable 回滚；VM 仅抑制 `BOUND` | v1 边界；无 durable 回滚测试 | README/维护计划已声明；后续配网 VM 变更补边界用例 |
| 测试源码 lint / 覆盖率 | `src/test/**`、`src/ohosTest/**` 不在 `code-linter.json5` 范围；无行/分支覆盖率 | 测试代码只有 Node 解析/编译门禁 | 维护计划 M-08；不作为产品 lint PASS |
| README 旧口径 | README §已知限制仍写 “596 条 `PENDING_REVIEW`”，与 `triage_legacy` 新口径（6 PENDING_REVIEW + 544 OBSOLETE_LEGACY 等）不一致 | 文档一致性债务（RR-03/§12.3） | documentation 阶段同步；不阻断 testing |
| 构建 API warning | 构建日志存在 `BLOB` API supported since SDK 18、当前 compatible 14 的 warning | 静态构建仍成功；API 14 运行时未验证 | 兼容性维护项；设备验证时复核 |
| 未签名 HAP | `signingConfigs: []` | 不能安装/发布 | release 阶段需用户配置签名 |

### 5.3 BLOCKED / UNAVAILABLE 清单

| ID | 项 | 原因 | 现有替代证据 |
|---|---|---|---|
| BLK-01 | `hvigorw test`（Hypium host 断言） | Linux Previewer 缺库/不支持；T-05/T-19/T-20 已记录 | Node runner 697/697；`UnitTestArkTS` 编译 PASS |
| BLK-02 | `onDeviceTest` | `hdc list targets` = `[Empty]`；无模拟器；`signingConfigs: []` | ohosTest HAP 仅编译（COMPILED_ONLY） |
| BLK-03 | 真实 BLE 配网/射频 | 无设备/固件/ESP32 | host fakes 覆盖协议/状态机 |
| BLK-04 | 真实 LAN / TLS pin 对端 | 无真实网关；仿真器仅 localhost | host/mock TLS 三态、SPKI 一致 |
| BLK-05 | 真实华为云 IoTDA | 无凭据/网络环境 | canonical/映射/完成判定 host 覆盖 |
| BLK-06 | UI 视觉/动效/可访问性/读屏 | 无设备/模拟器 | 构建 + 源码级 UI/RBAC 守卫 + host VM |
| BLK-07 | 60/120fps、真实 ACK p95 | 无设备/真实 LAN | mock harness + 明确不可外推 |
| BLK-08 | 真实硬件 AC/门磁/SHT30/PIR | 无设备 | 域/VM/协议 host 覆盖 |

---

## 6. Verdict

**`PASS_WITH_ACCEPTED_RISKS`（代码级 testing Stage，revision `e74a181`）**

依据：

1. 11 项强制矩阵命令在最终集成候选上全部实际执行且 exit 0；Host 697/697、crosscheck 66/66、仿真器 20/20、layering 0 violation、fixture 27/27、i18n 0 blocking、构建/lint 通过。
2. 未发现产品行为失败、测试断言失败或环境失败；未修改产品代码或测试断言。
3. 26 FR：24 covered (host)、2 partial、0 gap；NFR 4.1/4.2/4.3 均 **partial**，原因是设备/真实环境证据缺失，而不是 code-level 回归。
4. 设备/真实 BLE/LAN/TLS/云/视觉/fps 仍 `BLOCKED/UNAVAILABLE`；ACK p95 仅 `MOCK_ONLY`。因此**不得**判定为产品验收或设备验收 PASS。

> 该 Verdict 只覆盖 `e74a181` 与本报告 §1 环境；不覆盖 acceptance、documentation、release 或用户侧设备矩阵。

---

## 7. Stage Gate 建议（G-016 → acceptance）

### 7.1 建议

**建议 G-016 testing Stage：`PASS_WITH_ACCEPTED_RISKS`，允许进入 acceptance 分析阶段。**

理由：代码级测试矩阵在最终候选上完整复跑且无回归；FR/NFR 映射完整、边界诚实；残余项均为已登记风险或用户侧设备验证，不存在未关闭 High/Critical。

### 7.2 进入 acceptance 的条件（必须同时满足）

1. **接受 host-only 证据边界**：acceptance 只能把 `covered (host)` 解释为代码级覆盖，不得解释为 UI/设备/真实网络验收。
2. **逐项登记接受风险**：`PORT-LOC-01`、`D-030/GAP-T18-01`、`R4-01`、i18n 6 PENDING/11 B/6 C/3 D、NFR 4.1/4.2/4.3 partial、ACK p95 `MOCK_ONLY`、设备 `BLOCKED`、测试 lint/覆盖率缺口、未签名产物。
3. **设备矩阵由用户执行**：按 `maintenance-plan §4` 执行 BLK-01..08；真实 BLE/LAN/TLS/云/视觉/A11y/fps 结果回填前，不得声称设备或产品验收 PASS。
4. **文档同步**：documentation 阶段修正 README 的 596 条旧口径（改为 triage 新口径），并处理 RR-03；不得把 544 `OBSOLETE_LEGACY` 写成已人工签署。
5. **无新变更**：若 acceptance 前代码/测试/契约再次变更，本报告的受影响证据自动失效，需按 Change Impact 重跑对应矩阵。

### 7.3 不得声明

- 不得声明 IG-4、G-016 或 acceptance 已授予产品/设备验收；
- 不得声明真实 BLE/LAN/TLS/云/视觉/A11y/60/120fps 通过；
- 不得把 ACK p95 `0.609 ms` 写成 NFR 4.3 达标；
- 不得把 `check_layering` 的 0 violation 写成“端口位置已合规”；
- 不得把 `COMPILED_ONLY` 写成测试通过。

---

## 8. Traceability 与证据索引

### 8.1 本任务证据（`artifacts/60-testing/evidence/`）

| 文件 | 内容 |
|---|---|
| `t26-ohpm-install.log` | 依赖安装 |
| `t26-clean-assemble.log` | 干净 HAP 构建 |
| `t26-codelinter.log` | 静态检查 |
| `t26-host-node-tests.tap` | 697 条 host TAP |
| `t26-crosscheck.log` | 66/66 协议资产交叉校验 |
| `t26-simulator-contract.log` | 20/20 HTTP+TLS 契约套件 |
| `t26-layering.log` | 分层检查（221 文件 / 0 violation / 6 D-12 例外） |
| `t26-layering-fixture-tests.log` | 27/27 fixture 自测 |
| `t26-i18n-checker.log` | i18n 默认（无 allowlist）strict-ui：73 warning / 16 hardcoded |
| `t26-i18n-checker-with-allowlist.log` | i18n 带 allowlist 补充：55 warning / 16 hardcoded |
| `t26-i18n-report-with-allowlist.json` | i18n 结构化报告 |
| `t26-i18n-triage-check.log` | 615 行 triage 一致性 |
| `t26-i18n-triage-summary.log` | 615 行分类/状态汇总 |
| `t26-ack-p95-mock.json` / `.log` | ACK p95 `MOCK_ONLY` |
| `t26-ohosTest-assemble.log` | 测试 HAP 编译（COMPILED_ONLY） |
| `t26-hap-mock-exclusion.log` | HAP 内容与 Mock/ohosTest 0 命中 |
| `t26-device-boundary.log` | `hdc` / `signingConfigs` 边界 |

### 8.2 上游追溯

- 需求：`input/requirements/YaoCore_HarmonyOS_App_Requirements.md` §3（26 FR）/§4（NFR 4.1..4.3）。
- 计划：`artifacts/60-testing/test-plan.md`（TEST-001，§2 分层、§4 CQG、§5 安全负例、§7 NFR 口径）。
- 历史测试证据：`artifacts/60-testing/test-report.md`（TEST-REPORT-001，§2 矩阵、§4 SEC、§5 FR/NFR、§7 BLOCKED）。
- 集成：`artifacts/90-integration/integration-report.md`（INTEGRATION-REPORT-001，§2/§3/§11–§14）。
- 评审：`artifacts/70-review/final-system-review.md`（REV-001-FINAL-SYSTEM，§5 安全、§9 findings）。
- Gate：`state/gates/G-014-stage-gate.md`、`state/gates/G-015-review-gate.md`。
- 文档/风险：`README.md`（README-001 v1.0）、`artifacts/80-maintenance/maintenance-plan.md`。

---

*TEST-002 结束。所有 PASS 均对应当前 revision `e74a181` 与 §1 环境实际执行；设备/真实环境、`COMPILED_ONLY`、`MOCK_ONLY`、`BLOCKED`、`UNAVAILABLE` 均未写成 PASS。*
