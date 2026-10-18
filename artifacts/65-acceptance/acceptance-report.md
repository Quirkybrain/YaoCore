# ACCEPT-001 验收就绪报告（G-017 acceptance）

- **Artifact ID**: ACCEPT-001
- **Producer**: agent:system-verifier
- **Type**: Acceptance Readiness Report / Final Traceability / Stage Gate Input
- **Status**: COMPLETE（验收就绪分析完成；**不授予**用户验收、产品验收或 release）
- **Date**: 2026-10-18
- **Task**: `wp-108-acceptance`（task 分支 `task/wp-108-acceptance`，父分支 `feat/yaocore-app`，base commit `b10d2f50c931b7c82cd8a2105fbe804582d24b32`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `documentation`（用户 2026-10-18 扩展）；本次评估 Stage：`acceptance`
- **Upstream**: `input/requirements/YaoCore_HarmonyOS_App_Requirements.md`（PRD）；`artifacts/30-plan/delivery-plan.md`（DELIVERY-PLAN-001）；`artifacts/60-testing/testing-stage-report.md`（TEST-002）；`artifacts/60-testing/test-report.md`（TEST-REPORT-001）；`artifacts/70-review/final-system-review.md`（REV-001-FINAL-SYSTEM）；`artifacts/90-integration/integration-report.md`（INTEGRATION-REPORT-001）；`README.md`（README-001 v1.0）；`artifacts/80-maintenance/maintenance-plan.md`（MAINTENANCE-PLAN-001）；G-004/G-006..G-008/G-013..G-016
- **Write scope**: `artifacts/65-acceptance/`；唯一交付为本文件；未修改代码、测试、工具、契约、README、`input/`、state 或 Gate 记录
- **Input pins**: handoff 的 6 项输入 SHA-256 已逐项实算一致（requirements / delivery-plan / TEST-002 / TEST-REPORT-001 / REV-001 / INTEGRATION-REPORT-001）

> **结论先行**
>
> 1. **代码级证据完整且当前**：在最终集成候选 `b10d2f5` 上实际复跑 `host 697/697`、`crosscheck 66/66`、`simulator 20/20（HTTP+TLS）`、`layering 0 violation`、`i18n CHK-01..09 0 blocking / 0 missing`，全部 exit 0。构建与静态检查由 TEST-002 在 `e74a181` 覆盖；`e74a181..b10d2f5` 对 `entry/src/main`、`tools`、`entry/src/test`、`entry/src/ohosTest` 的 diff 为空，故该证据适用于当前代码内容。
> 2. **FR 映射**：26 FR = **24 covered（functional，host/sim）+ 2 partial + 0 gap**。partial 为 `FR-HOME-003`（真实 SHT30/PIR 数据缺失，BLK-08）与 `FR-SET-002`（P-HMAC 无机密性、真实 TLS pin 缺失，BLK-04 / FC-01）。NFR 4.1/4.2/4.3 均 **partial**。
> 3. **子句级核对发现 3 项 UI 呈现偏离**（均为 Low、无安全/数据/核心控制影响，但未获用户接受）：`FR-HOME-001` 未显示局域网 IP；`FR-HOME-001` 多家庭切换未实现“首页弹窗”而改为跳转家庭管理页；`FR-ROOM-001` 未提供房间图标设置/展示。另有文档漂移 `D-AC-01..08`（README 596 旧口径、端口/例外数字过期、RR-03 等），转 documentation 阶段处理。
> 4. **Verdict: `READY_FOR_USER_ACCEPTANCE`（有条件）**——可以开始用户验收；**用户验收尚未完成**，不得宣称产品验收、设备验收或 NFR 达标。
> 5. **G-017 建议：`PASS_WITH_ACCEPTED_RISKS`（仅 acceptance readiness 范围）**；可进入 documentation 阶段；**release 未授权**，仍需用户对签名、设备矩阵、发布与远端策略作出决定。

---

## 0. 范围、revision 与证据边界

### 0.1 Revision 与集成状态

| 项 | 值 |
|---|---|
| 仓库根 / cwd | `/home/quirkybrain/code/harmony-projects/YaoCore` |
| 当前分支 / HEAD | `task/wp-108-acceptance` / `b10d2f5` |
| 父分支 / 最终集成候选 | `feat/yaocore-app` / `b10d2f5`（与 handoff `base_commit` 一致） |
| 产品代码基线 | 与 TEST-002 的 `e74a181` **相同**：`git diff e74a181..HEAD -- entry/src/main tools entry/src/test entry/src/ohosTest` 输出为空 |
| TEST-002 / G-016 | TEST-002 @ `e74a181`；G-016 @ `1cccec5`；`1cccec5..b10d2f5` 仅新增 Gate/状态/验收占位文件 |
| Gate 链 | G-004、G-006..G-008、CQG-T06..T18、G-013/G-014 @ `1d4b202`、G-015 @ `09e1b46`、G-016 @ `1cccec5` |
| 环境 | Linux x86_64；Node 24.15；Python 3.12.3；HarmonyOS SDK 26.0.0.105；`signingConfigs: []`；`hdc list targets` 为空 |
| 本任务写入 | 仅 `artifacts/65-acceptance/acceptance-report.md` |

### 0.2 证据分类（沿用 TEST-002 口径）

| 分类 | 本报告含义 |
|---|---|
| `PASS（host）` | Node 24 runner 加载生产 `.ets` 纯逻辑并注入 fake；**不是** ArkTS/Hypium 设备运行 |
| `PASS（mock/sim）` | localhost Python 仿真器/契约套件；**不是**真实网关、LAN、TLS 或云 |
| `PASS（build/lint）` | 当前代码内容可构建、静态检查 0 error；**不是**设备安装或 UI 运行 |
| `COMPILED_ONLY` | 仅编译通过，未执行断言；**不是 PASS** |
| `MOCK_ONLY` | 仅 localhost/测试替身测得；不得外推为产品验收 |
| `BLOCKED` | 前置条件不满足（设备/签名/真实环境） |
| `UNAVAILABLE` | 当前环境无法获得证据 |
| `ACCEPTED_RISK` | 已登记并由 G-014/G-016 或用户接受的风险 |
| `UI-DEVIATION` | 需求子句与当前 UI 呈现不一致；需用户接受或 bounded fix |

> 本报告不把 `COMPILED_ONLY`、`MOCK_ONLY`、`BLOCKED`、`UNAVAILABLE` 写成 PASS，也不把 host/mock 结果解释为 UI、BLE、LAN、TLS、云、传感器或性能验收。

### 0.3 本次实际执行的复验（cwd = 仓库根，2026-10-18）

| # | 命令 | 实测结果 | Exit |
|---|---|---|---|
| 1 | `entry/src/test/run-host-tests.sh` | `1..697`；tests 697 / pass 697 / fail 0 / skipped 0；≈3050.9 ms | **0** |
| 2 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py` | 66 `[PASS]` / 0 `[FAIL]`；14 条既有 `FINDING`；`hard checks: ALL PASS` | **0** |
| 3 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | `files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0`；`PASS` | **0** |
| 4 | `PYTHONDONTWRITEBYTECODE=1 python3 entry/src/test/i18n/check_i18n.py --strict-ui` | CHK-01..09 全 PASS；`blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16` | **0** |
| 5 | `no_proxy=127.0.0.1,localhost NO_PROXY=127.0.0.1,localhost PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tools.simulator.test_gateway_contract -v` | `Ran 20 tests in 0.588s`；`OK`（HTTP + 3 条 TLS） | **0** |

> 第 5 项为补充复验（任务要求至少 4 项）；不改变“仿真器仅为 localhost”的边界。

---

## 1. 需求清点：26 FR + NFR 4.1/4.2/4.3

### 1.1 FR 计数与编号校验

对 PRD §3 逐条提取并按 ID 去重：

| 组 | 编号范围 | 数量 |
|---|---|---|
| 家庭/成员 | `FR-FAM-001..004` | 4 |
| 房间/设备 | `FR-ROOM-001..006` | 6 |
| 首页/看板 | `FR-HOME-001..004` | 4 |
| 网关配网 | `FR-GW-001..003` | 3 |
| 设备控制 | `FR-DEV-001..005` | 5 |
| 场景 | `FR-SCN-001` | 1 |
| 设置/安全/云 | `FR-SET-001..003` | 3 |
| **合计** | — | **26** |

**校验结论**：26 个 FR 编号连续、唯一、无重复、无遗漏；与 TEST-REPORT-001 §5、TEST-002 §3、`component-graph.md` §6、`delivery-plan.md` §4.4 的 26 行计数一致。

### 1.2 全部 FR（编号 + 简述）

| # | FR | 简述 |
|---|---|---|
| 1 | FR-FAM-001 | 家庭创建与多家庭支持；创建者成为 ADMIN；多家庭切换 |
| 2 | FR-FAM-002 | 成员邀请；邀请码/时限/角色/授权房间；安全通道同步家庭密钥，无需重新 BLE 配网 |
| 3 | FR-FAM-003 | 成员权限管理与移除；成员列表/角色/在线状态；移除后本地数据与令牌失效 |
| 4 | FR-FAM-004 | 退出家庭；Admin 须转让或解散；v1 本地语义 |
| 5 | FR-ROOM-001 | 房间创建与独立 `roomId`；名称与图标 |
| 6 | FR-ROOM-002 | 房间命名与 ID 不变性；仅 `roomId` 索引 |
| 7 | FR-ROOM-003 | 设备自由加入、跨房间转移、未分配池 |
| 8 | FR-ROOM-004 | 房间删除保护；设备置空/未分配/禁用，不级联删除 |
| 9 | FR-ROOM-005 | 设备删除对房间无感；清理本地记录 |
| 10 | FR-ROOM-006 | 设备用户命名与 `deviceId` 不变性；线上/签名使用不可变 ID |
| 11 | FR-HOME-001 | 当前家庭与网关状态；LAN/云/离线、LAN IP、RTT；多家庭快捷切换 |
| 12 | FR-HOME-002 | 房间快捷切换栏；全部/各房间/未分配过滤 |
| 13 | FR-HOME-003 | SHT30 温湿度 + PIR 人体感应；时间戳与来源 |
| 14 | FR-HOME-004 | 快捷设备卡片；开关、亮度、门锁安全状态 |
| 15 | FR-GW-001 | 蓝牙权限与扫描 `YaoCore-GW-*` + Primary Service UUID |
| 16 | FR-GW-002 | Protocomm Security1 握手；X25519 + SHA256(PoP) + AES-256-CTR；读取 `yaocore-id` |
| 17 | FR-GW-003 | Wi-Fi 下发与加密探针校验；绑定到家庭 |
| 18 | FR-DEV-001 | 真实 ACK 确认；验签 + correlation + `result_code==0` + `reported_state` |
| 19 | FR-DEV-002 | 灯光开关/亮度/颜色；55ms 连续滑动节流 |
| 20 | FR-DEV-003 | 门锁与门磁联动；到位才显示已锁好；超时警报 |
| 21 | FR-DEV-004 | 空调温控与 Gree/Haier/Midea/Generic 适配；16..30°C 与模式 |
| 22 | FR-DEV-005 | 状态来源标记（`sensor.physical` / `automation.local` / `app.lan` / `app.cloud` 等） |
| 23 | FR-SCN-001 | 场景编排与执行；逐步结果；局部失败不回滚 |
| 24 | FR-SET-001 | 家庭成员管理面板；邀请、解散家庭 |
| 25 | FR-SET-002 | 端到端加密/密钥配置；HMAC 控制密钥；本地 HTTPS 证书信任 |
| 26 | FR-SET-003 | 华为云 IoTDA 参数配置；zh-CN/en-US 切换 |

### 1.3 全部 NFR（PRD 未给编号，以下为项目内派生 ID）

> PRD §4 以分组标题和项目符号表述 NFR，没有 `NFR-xxx` 编号。项目内（`component-graph.md`、TEST-REPORT-001、TEST-002）统一使用 `NFR-4.1/4.2/4.3`，本报告沿用该派生编号，不改变 PRD 语义。

| NFR | 子项 | PRD 要求摘要 |
|---|---|---|
| **NFR-4.1 传输安全** | 4.1.1 机密性 | LAN 控制载荷 AES-256-GCM + HKDF 子密钥（方案 A）或本地 HTTPS/TLS + 证书指纹固定（方案 B） |
| | 4.1.2 完整性与防重放 | 外层 HMAC-SHA256 + 随机 nonce；防篡改、防重放 |
| | 4.1.3 时钟与 nonce | 时钟容差 ±120s；300s 内 nonce 不得重复 |
| **NFR-4.2 存储安全/隐私** | 4.2.1 凭据隔离 | Wi-Fi 密码用后即清；用户密码 PBKDF2\|SHA256 120,000 次加盐；邀请码有效期/过期作废 |
| | 4.2.2 本地安全沙箱 | 密钥与成员配置存放在系统级安全首选项/安全存储 |
| **NFR-4.3 性能/响应** | 4.3.1 LAN RTT | 局域网加密控制 RTT p95 ≤ 500ms |
| | 4.3.2 滑动调光 | 55ms 节流，连续滑动无卡顿 |
| | 4.3.3 帧率 | 页面切换 60fps/120fps |

---

## 2. 追溯完整性：Requirement → Design → Component → Task → Code → Test

### 2.1 追溯方法与证据口径

- **Requirement**：PRD §3/§4（26 FR + 3 NFR 组）。
- **Design/Architecture**：DES-A / DES-B、ADR-001..004、`contract-baseline.md`、`project-constraints.md`、UIUX/BLE 设计。
- **Component**：`component-graph.md` C-01..C-29（24 个产品组件 + Mock/工具组件）。
- **Task**：`delivery-plan.md` T-01..T-22（实际执行含 T-23..T-25 收尾）。本表使用 T-xx 任务编号；T-xx ↔ `wp-xxx` 的对应以 `state/handoffs/` 与 `state/reports/` 为准。
- **Code**：`entry/src/main/ets/**`（221 个 ArkTS 文件，C-29 扫描口径）。
- **Test**：`entry/src/test/host/**`（697 条当前 TAP）、`tools/contract/**`、`tools/simulator/**`、i18n 检查器。
- **Gate**：CQG-T06..T18、G-013..G-016。

**测试锚点校验**：TEST-002 §3 的 26 行 FR 表包含 **71 个精确用例名 + 17 个组锚点**；本报告逐项在 `b10d2f5` 的 697 条 TAP 中核对，**71/71 精确用例存在且 `ok`**；17 个组锚点的实际计数与声明计数**全部一致**（如 `C13_*` 19、`C16_*` 8、`T15_Throttle_*` 7、`T09_C11_*` 15、`T16_Scene_*` 7、`C04_*` 18、`C05_*` 16、`C07_*` 29、`C15_*` 18、`T10_C14_*` 28、`T16_Settings_*` 11）。

### 2.2 FR 追溯矩阵（26 行）

> 状态口径：`COVERED` = 功能主路径在当前 revision 有 host/sim 证据；`PARTIAL` = 核心子项缺证据；`GAP` = 无证据。UI/设备列独立标注；`UI-DEVIATION` 为子句级呈现偏离，不改变功能级 COVERED 计数，但必须由用户接受或修复。

| # | FR | 设计/ADR 锚点 | 组件 | 任务 | 代码主路径 | 当前测试锚点（697 TAP / 套件） | 状态 / 用户侧 |
|---|---|---|---|---|---|---|---|
| 1 | FR-FAM-001 | DES-B §3/§11.5；ADR-003 §2-3 | C-08, C-12, C-22, C-26 | T-09, T-13, T-16, T-18 | `service/family/FamilyService.ets`；`repository/FamilyRepository.ets`；`viewmodel/FamilyViewModel.ets`；`pages/FamilyManagePage.ets` | `T09_C08_createFamilyCreatesAdminAndActivatesFirstFamily`、`T16_Family_createFamilyCreatesProfileAndActivates`、`T09_C08_switchFamilyLocksSessionAndRequiresTargetProfile` | **COVERED（host）**；UI/BLK-06 |
| 2 | FR-FAM-002 | DES-A §13；DES-B §3；ADR-003 §4-5 | C-13, C-08, C-12, C-04, C-05, C-22, C-26 | T-13, T-09, T-16, T-18 | `service/invite/InviteService.ets`、`InviteCodec.ets`；`service/family/FamilyJoinSession.ets`；`FamilyViewModel.ets`；`FamilyManagePage.ets` | `C13_keyWrap_roundTripAppliesGatewayAndCreatesMemberReceipt`、`T09_C08_invitationReceiptStateMachineAndWeakModeView`、`T16_Family_joinStateMachineAndProfileCompletion`；`C13_*` 19 | **COVERED（host）**；邀请 UI/BLK-03/06 |
| 3 | FR-FAM-003 | DES-A §12；DES-B §3；ADR-003 §6/§9 | C-08, C-12, C-22, C-26 | T-13, T-09, T-16, T-18 | `service/auth/AuthService.ets`、`service/family/FamilyRbac.ets`；`FamilyRepository.ets`；`FamilyViewModel.ets` | `C12_rbacMatrix_adminMemberGuestAndDeviceStates`、`T09_C08_changeMemberRoleSuccessInvalidatesSessions`、`T09_C08_removeMemberSuccessInvalidatesSessionsAndGuidesRotation` | **COVERED（host）**；在线状态为 D-010 v1 声明性限制；UI/BLK-06 |
| 4 | FR-FAM-004 | DES-B §3.3.6/§3.5；ADR-003 §10 | C-08, C-12, C-22, C-26 | T-09, T-13, T-16, T-18 | `FamilyService.leaveFamily/transferAdmin/dissolveFamily`；`FamilyViewModel.ets` | `T09_C08_leaveFamilyRemovesMemberAndProfileOnly`、`T09_C08_transferAdminUpdatesOwnerAndInvalidatesBothSessions`、`T09_C08_dissolveFamilyRemovesLocalDataProfilesAndClearsActive`、`T09_C08_lastAdminCannotBeRemovedDemotedOrLeave` | **COVERED（host，v1 本地语义）**；无跨设备实时同步；UI/BLK-06 |
| 5 | FR-ROOM-001 | DES-B §4；ADR-004 §1 | C-09, C-22, C-26 | T-09, T-16, T-18 | `service/room/RoomService.ets`；`repository/RoomRepository.ets`；`viewmodel/RoomViewModel.ets`；`pages/RoomManagePage.ets` | `T09_C09_roomCreateRenameKeepsIdAndDefaultOrder`、`T16_Room_createRenameAndReorder` | **COVERED（host）**；**UI-DEVIATION**：房间图标未提供设置/展示；UI/BLK-06 |
| 6 | FR-ROOM-002 | DES-B §4.3；ADR-004 §1 | C-09, C-10, C-22, C-25/26 | T-09, T-16 | 同上；`DeviceRepository` 仅按 `roomId` 引用 | `T09_C09_roomCreateRenameKeepsIdAndDefaultOrder`、`T16_Room_createRenameAndReorder` | **COVERED（host）**；视觉/BLK-06 |
| 7 | FR-ROOM-003 | DES-B §4/§5；ADR-004 §2 | C-09, C-10, C-22, C-25 | T-09, T-16 | `RoomService.assignDevice/moveDevice`；`DeviceRepository.assignRoom` | `T09_C09_assignMoveAndUnassignFollowPoolSemantics`、`T16_Room_assignAndUnassignUseServicePorts` | **COVERED（host）**；选择/拖拽 UI/BLK-06 |
| 8 | FR-ROOM-004 | DES-B §4.3/§5.3；ADR-004 §2 | C-09, C-10, C-22, C-25 | T-09, T-16 | `RoomService.deleteRoom`；`DeviceAssignmentPort`；`DeviceRepository` | `T09_C09_deleteRoomIsOneTransactionDevicesUnassignedGrantsRemoved`、`T09_C09_deleteRoomRollsBackRoomDeviceAndGrantOnFailure`、`T16_Room_confirmDeleteSuccessClearsPreviewAndRefreshesPool` | **COVERED（host）**；删除确认 UI/BLK-06 |
| 9 | FR-ROOM-005 | DES-B §5.3；ADR-004 §2 | C-10, C-22, C-25 | T-09, T-16 | `DeviceRepository.removeDevice`；`SceneService` 引用清理 | `T09_C10_removeDeviceCleansSceneReferences`、`T09_C10_removeDeviceRollsBackWhenSceneCleanupFails` | **COVERED（host）**；设备列表 UI/BLK-06 |
| 10 | FR-ROOM-006 | DES-A §6.5；DES-B §5；ADR-004 §1 | C-03, C-10, C-22, C-25 | T-06, T-09, T-16 | `DeviceRepository.renameDevice/assignRoom`；`ControlRequestSerializer.ets` 使用 `deviceId` | `T09_C10_renameAndAssignNeverTouchTheNetwork`、`T09_C10_aliasUsedIsDiagnosticAndNotPartial` | **COVERED（host）**；命名 UI/BLK-06 |
| 11 | FR-HOME-001 | DES-B §10.5；CB §7.1；UIUX §4.1 | C-07, C-10, C-15, C-17, C-21, C-25 | T-08, T-11, T-14, T-15, T-17 | `viewmodel/HomeViewModel.ets`；`components/StatusPanels.ets`；`pages/HomePage.ets` | `T15_Home_initializeLoadsFamilyRoomsRecordsAndGatewayStatus`、`T15_Home_gatewayFailurePreservesRecordsAndReportsOffline`、`T15_Home_tlsFailureReportsBlocked` | **COVERED（host，功能）**；**UI-DEVIATION ×2**：LAN IP 未显示；家庭切换为跳转家庭页而非首页弹窗；UI/BLK-06 |
| 12 | FR-HOME-002 | DES-B §10.5 | C-09, C-10, C-21, C-25 | T-15, T-17 | `HomeViewModel` 过滤；`components/RoomChipBar.ets` | `T15_Home_roomFilterAndUnassignedPoolSelectors`、`T18_filtersMatchAllRoomAndUnassigned`、`T15_Device_roomFilterAndUnassignedPool` | **COVERED（host）**；横向滑动视觉/BLK-06 |
| 13 | FR-HOME-003 | DES-B §10.5；CB §6.1 | C-03, C-10, C-21, C-25 | T-09, T-15 | `HomeViewModel.environmentOf`；`DeviceRepository` 传感器记录；`StatusPanels.EnvironmentPanel` | `T15_Home_environmentAggregatesLatestSensorValuesOnly` | **PARTIAL**：聚合逻辑 host 覆盖；真实 SHT30/PIR 数据 **UNAVAILABLE / BLK-08** |
| 14 | FR-HOME-004 | DES-B §13.5；UIUX §4.3/4.4 | C-10, C-16, C-21, C-25 | T-15, T-17 | `components/DeviceCards.ets`；`components/DeviceGrid.ets`；`viewmodel/DeviceViewModel.ets` | `T15_Device_threePhasePendingThenCommitted`、`T18_lightCardWiresPowerToggleAndKeepsPendingSliderLive`、`T18_brightnessAndTemperatureFollowPendingValueThenConfirmed` | **COVERED（host/source）**；视觉/交互/BLK-06 |
| 15 | FR-GW-001 | DES-A §16.1/§16.12；BLE §2 | C-19, C-27, C-28 | T-12, T-16, T-17, T-18 | `service/ble/BleProvisioningService.ets`；`app/PermissionGate.ets`；`module.json5`；`ProvisioningPage.ets` | `C19_BleProvisioningService_scanPermissionAndBluetoothFailClosed`、`C19_BleProvisioningService_publicScanDedupesAndStops`、`T16_Ble_scanDeduplicatesAndSelectMovesToHandshake`、`T16_Ble_scanTimeoutWithoutResultsShowsRetryableError` | **COVERED（host/fake）**；真实 BLE 扫描/权限 **BLOCKED / BLK-03** |
| 16 | FR-GW-002 | DES-A §16.4/§16.12；ADR-001 §3；ADR-002 §3 | C-04, C-19 | T-07, T-12 | `Security1Session.ets`；`ProtocommCodec.ets`；`IdentityNegotiator.ets` | `C19_Security1_stateGuardsAndStep0Vector`、`C19_Security1_rfc7748Vector`、`C19_Security1_handshakeAndContinuousCtrStream`、`C19_Security1_wrongPopFailsClosedAndDestroysSession`、`C19_Security1_tamperedDeviceVerifyFailsClosed` | **COVERED（host/fake）**；真实 BLE 射频/固件 **BLOCKED / BLK-03** |
| 17 | FR-GW-003 | DES-A §16.7/§16.8；ADR-002 §4 | C-07, C-17, C-18, C-19, C-23, C-27 | T-11, T-12, T-16, T-18 | `WifiProvisioningFlow.ets`；`BindingProbe.ets`；`BleProvisioningViewModel.ets`；`ProvisioningPage.ets` | `C19_WifiProvisioningFlow_*` 7、`C19_BindingProber_*` 13、`T16_Ble_submitMapsStatesAndCommitsWithReissuedResultDraft`、`T18_C19_scanWifiAccessPointsHandshakesWithoutApplyingCredentials` | **COVERED（host/fake）**；真实 LAN/BLE **BLOCKED / BLK-03/04** |
| 18 | FR-DEV-001 | DES-A §18.7；DES-B §5.5/§10.5 | C-05, C-10, C-17, C-21, C-25 | T-06, T-07, T-08, T-11, T-15, T-17 | `ControlAckMapper.ets`；`ResponseVerifier.ets`；`DeviceCommandRunner.ets`；`DeviceViewModel.ets` | `C03_ControlAckMapper_nonZeroResultNeverClaimsSuccess`、`C17_control_successWithoutReportedStateIsProtocolViolation`、`T15_Device_threePhasePendingThenCommitted`、`T15_Device_threeSecondTimeoutRevertsAndIgnoresLateResult` | **COVERED（host）**；真实设备 ACK **BLOCKED / BLK-08** |
| 19 | FR-DEV-002 | DES-B §10.5；ADR-004 §6 | C-10, C-17, C-21, C-25 | T-09, T-11, T-15, T-17 | `viewmodel/core/ThrottleGate.ets`；`DeviceViewModel.ets`；`components/DeviceCards.ets` | `T15_Throttle_*` 7、`T15_Device_continuous55msCoalescesAndTouchUpSendsFinalValue`、`T15_Climate_temperatureContinuousCoalescesAndTouchUpCommits` | **COVERED（host）**；FPS/真实触控 **UNAVAILABLE / BLK-07** |
| 20 | FR-DEV-003 | DES-B §10.5；ADR-004 §6 | C-10, C-17, C-21, C-25 | T-09, T-11, T-15, T-17 | `viewmodel/core/DoorConfirmationTracker.ets`；`DoorViewModel.ets`；`DeviceCards.DoorCard` | `T15_Door_*` 9、`T15_DoorView_*` 9、`T18_doorStagesNeverUpgradeWithoutEvidence`、`T18_doorStageProgressNeverLightsSecuredWithoutEvidence` | **COVERED（host）**；物理门磁 **BLOCKED / BLK-08** |
| 21 | FR-DEV-004 | DES-B §9.5/§10.5；CB §6.3 | C-16, C-17, C-21, C-25 | T-14, T-15, T-17 | `service/ac/AcAdapterFactory.ets` + Gree/Haier/Midea/Generic；`ClimateViewModel.ets`；`DeviceCards.ClimateCard` | `C16_*` 8、`T15_Climate_*` 5 | **COVERED（host）**；真实 AC **BLOCKED / BLK-08** |
| 22 | FR-DEV-005 | DES-A §6.5；CB §6.1 | C-03, C-10, C-14, C-21, C-25 | T-06, T-09, T-10, T-15, T-17 | `DiscoverMapper.ets`；`ErrorI18nMapper.ets`；`HomeViewModel`；`components/support/UiMapping.ets` | `C03_DiscoverMapper_unknownTypeRoomModeColorAndStateSourceAreTolerated`、`T10_C14_errorMapper`、`T18_lowRiskUiGuards_sourceLevel`、`T15_Home_environmentAggregatesLatestSensorValuesOnly` | **COVERED（host/source）**；视觉标注/BLK-06 |
| 23 | FR-SCN-001 | DES-B §6.5/§11.5；CB §5 | C-11, C-17, C-22, C-26 | T-09, T-11, T-16, T-18 | `SceneService.ets`；`SceneExecutor.ets`；`SceneValidation.ets`；`SceneViewModel.ets`；`ScenePage.ets` | `T09_C11_*` 15（如 `T09_C11_secondStepFailureIsPartialFailedWithoutRollback`、`T09_C11_sameSceneConcurrentRunIsRejectedAndNeverDoubleDispatches`）、`T16_Scene_*` 7 | **COVERED（host）**；场景 UI **BLOCKED / BLK-06** |
| 24 | FR-SET-001 | DES-B §3.5/§11.5 | C-08, C-12, C-22, C-26 | T-09, T-13, T-16, T-18 | `FamilyViewModel.ets`；`FamilyManagePage.ets`；`FamilyService` | `T16_Family_*` 12、`T18_familyJoinAndInviteGuards`、`T18_nonAdminRoomPoolAndGatewayEntriesAreHidden`、`T18_R2_settingsReprovisionRequiresAdmin` | **COVERED（host/source）**；视觉/RBAC 可见性 **BLOCKED / BLK-06** |
| 25 | FR-SET-002 | DES-A §7-§14；ADR-002 §3-8 | C-04, C-05, C-07, C-13, C-17, C-19, C-23, C-27 | T-07, T-08, T-11, T-12, T-13, T-16, T-18 | `CryptoService.ets`；`ResponseVerifier.ets`；`GatewayRepository.ets`；`SettingsViewModel.ets`；`SettingsPage.ets` | `C04_*` 18、`C05_*` 16、`C07_*` 29、`C17_tlsPinMismatchNeverFallsBackToCleartext`、`C19_BleProvisioningService_tlsPinMismatchNeverBinds`、`C20_tlsPinMismatchAndHandshakeFail_areHardFailures` | **PARTIAL**：P-HMAC 无机密性；真实 TLS pin **BLOCKED / BLK-04**；LAN GCM `EXT-GCM-001` 归档 |
| 26 | FR-SET-003 | DES-B §7.6/§8.6/§12.5；CB §7.1 | C-14, C-15, C-23, C-27 | T-10, T-14, T-16, T-18 | `I18nService.ets`；`CloudService.ets`；`SettingsViewModel.ets`；`SettingsPage.ets` | `C15_*` 18、`T10_C14_*` 28、`T16_Settings_*` 11；CHK-01..09 PASS | **COVERED（host）**；真实 IoTDA **UNAVAILABLE / BLK-05**；语言切换 UI/BLK-06 |

**统计**：**24 COVERED（functional）+ 2 PARTIAL + 0 GAP**。`FR-HOME-001` 与 `FR-ROOM-001` 的 3 项 `UI-DEVIATION` 为呈现级偏离，不改变功能级 COVERED 计数，但列入 §4.3 待用户决定。

### 2.3 NFR 追溯矩阵

| NFR | 子项 | 设计/组件 | 当前证据（revision `b10d2f5`） | 状态 | 缺口 / BLK |
|---|---|---|---|---|---|
| **4.1** | 4.1.1 机密性 | ADR-002 §5/§6；C-04/C-17 | P-HMAC 仅完整性/防重放；GCM 归档 `EXT-GCM-001`；P-TLS-PIN 仅 host/mock | **PARTIAL** | 真实 TLS/机密性 **BLK-04 / FC-01**；P-HMAC 无机密性 |
| | 4.1.2 完整性与防重放 | ADR-002 §2；C-05/C-17 | `C05_*` 16、`C17_*` 35；仿真器坏签名/过期/重放/nonce 用例 | **COVERED（host/sim）** | 真实网关 **BLK-04** |
| | 4.1.3 时钟与 nonce | ADR-002 §2；C-05 | `C05_timeWindowBoundaryIsInclusiveAt120Seconds`、`C05_NonceCache_ttlBoundaryAndCapacityEviction`、`C05_RequestSigner_rejectsRepeatedNonceAndBadSecrets` | **COVERED（host/sim）** | 真实设备时钟/对端 **BLK-04** |
| **4.2** | 4.2.1 凭据隔离 | ADR-002 §8.3；ADR-003；C-04/C-06/C-12/C-13 | PBKDF2 120k、`SecretDraftStore` zeroize、邀请过期/账本、秘密纪律 | **COVERED（host）** | 设备 Asset Store/RDB **BLK-02** |
| | 4.2.2 本地安全沙箱 | ADR-002 §8.3；C-06/C-07 | Asset Store 端口/实现 + fake store；无设备运行 | **PARTIAL** | 设备安全存储未执行 **BLK-02** |
| **4.3** | 4.3.1 LAN RTT p95 | TEST-001 §7.1；C-17 | **MOCK_ONLY** p50 0.553 / p95 **0.609** / max 0.650 ms（N=100，warmup=5，0 fail） | **PARTIAL** | 真实 LAN p95 **BLK-07**；mock 不得用于验收 |
| | 4.3.2 55ms 节流 | TEST-001 §7.2；C-21 | `T15_Throttle_*` 7 + Device/Climate 连续控制 | **COVERED（host）** | 真实 UI 帧/触控 **BLK-06/07** |
| | 4.3.3 60/120fps | TEST-001 §7.3；C-25 | 无 frame profiler/设备；仅静态审查与 25 条 lint warning | **GAP（测量）** | **UNAVAILABLE / BLK-07**；不得宣称达标 |

**NFR 顶层结论**：4.1 / 4.2 / 4.3 均 **PARTIAL**。其中 4.3.3 作为“实测帧率”子项为 **GAP**（无测量证据），不得用 host/静态审查替代。

### 2.4 双向一致性核对

#### 2.4.1 Requirement → 实现（是否有需求没有实现）

- **26/26 FR 均有组件、任务、代码主路径与测试锚点**；无整条 FR 完全缺失。
- **3 项子句级 UI 呈现偏离**（详见 §4.3）：
  - `FR-HOME-001`：LAN IP 未显示；多家庭快捷切换未实现首页弹窗。
  - `FR-ROOM-001`：房间图标未提供设置/展示。
- **已声明的 v1 范围性缺失**（不是新发现，但必须由用户接受）：
  - `FR-FAM-003` 在线状态：D-010/ADR-003 明确 v1 无实时在线，仅接触式收敛。
  - `FR-FAM-004`：v1 本地语义，不承诺跨设备强一致。
  - `FR-SET-002` 机密性：P-HMAC 不提供载荷机密性；GCM 归档；TLS 依赖固件 v2.1。
  - `FR-HOME-001`/`FR-GW-003` 发现：PB-01 未决，raw UDP/mDNS 不作为 v1 默认路径；手动/上次地址可用。
  - `FR-SET-003` 云完成判定：PB-02 未决，外部模块 `DeviceInventoryJson` 路径 `UNSUPPORTED`，内置 `LastRequestId/LastSeq` 路径完整。
  - 扫码/二维码、设备删除/改名 UI、场景编辑、通知系统状态：T-18 已声明 DEFERRED（M-13）。

#### 2.4.2 实现 → Requirement（是否有代码没有需求/决策/维护理由）

- **未发现无需求归属的产品功能代码**。C-01..C-28 均可追溯到 FR/NFR 或明确的基础/安全/UI 支撑；C-29 为验证/工具链。
- **测试/工具代码**：`service/mock/**`（C-20）与 `tools/**`（C-29）为测试/验证资产；生产组合根不引用 Mock，HAP 级 0 命中，属于明确排除项。
- **未引用/低使用代码**（维护观察，不构成验收阻塞）：
  - `app/ContinuousGestureGuard.ets` 当前无页面引用；T-17 报告要求 T-18 滑杆“必须使用该守卫（或等价显式 flag）”，实际 `DeviceCards.ets` 使用原生 `Slider` + `SliderChangeMode.End/Click` 分支。属“等价显式 flag”的弱实现，取消/TouchUp 边界需设备验证（BLK-06/07）。
  - `components/CommonControls.ets` 的 `GlassSurface`/`IconButton`/`SliderControl` 未被页面使用（M-01 已登记）；`service/gateway/discovery/MdnsDiscoveryTransport.ets` 因 PB-01 未决而**有意不接线**（COMPILED_ONLY）。
- **结论**：无孤儿产品特性；上述为设计系统/工具/未决发现路径的维护债务，已路由到 maintenance/documentation。

#### 2.4.3 Requirement → 测试（是否有需求没有测试）

- **26/26 FR 在当前 697 TAP 中至少有一个精确测试锚点**；TEST-002 §3 的 71 个精确用例全部存在且通过，17 个组锚点计数全部匹配。
- **NFR**：4.1.2/4.1.3 有 host/sim 负例；4.2.1 有 host 证据；4.3.2 有 host 证据；4.1.1/4.2.2/4.3.1/4.3.3 为设备/真实环境缺口，已明确标 `BLOCKED/UNAVAILABLE/GAP`，**不存在“未运行却写成 PASS”**。
- **测试真实性**：host 用例加载生产 `.ets` 源码并注入 fake（如 `ViewModelDevice.test.mjs` 直接 import `DeviceViewModel.ets`），不是仅测试替身自测；仿真器 20/20 为 localhost 契约夹具。

#### 2.4.4 设计/架构 → 代码（是否脱节）

- DES-A/DES-B 的冻结签名、错误码、canonical/HMAC/ACK 语义与当前代码一致；T-23 端口迁移后 `contracts/**` 已建立，DES-A §27.6.4 记录 16 CLOSED / 1 OPEN（`PORT-LOC-01`）。
- **当前 `check_layering` 0 violation 不等于端口位置完全合规**：1 条 `PORT-LOC-01` 仍 OPEN（本 revision `port_exceptions_used=0`）；6 条 D-12 文件/符号级例外 `accepted` 且被使用。
- **设计层面的 PRD 偏离**：`FR-HOME-001` LAN IP/弹窗、`FR-ROOM-001` 房间图标未在 DES-B/UI 实现中体现；这是 §4.3 的 UI-DEVIATION 来源，需用户接受或补设计/实现。
- **历史文档**：TEST-REPORT-001、G-014、README、MAINTENANCE-PLAN-001 的若干数字停留在 A1 端口迁移/T-23/i18n triage 之前；属于文档漂移，不是代码回归（见 §4.2）。

### 2.5 Gate 证据新鲜度

| Gate/证据 | 评估 revision | 对当前 `b10d2f5` 的适用性 | 结论 |
|---|---|---|---|
| G-004 契约基线 | `697762c` | 未变更；ADR-001..004 仍 Accepted；T-23/T-20 仅登记语义/例外 | **VALID** |
| G-006/G-007 DES-A/B | `697762c` 基线 + 后续裁定同步 | DES-A/B 已同步 T-20/T-23/F-03；未改冻结签名 | **VALID（含同步记录）** |
| G-008 TEST-001 | `fa21c67` | 测试计划未改；执行证据由 TEST-002 更新 | **VALID** |
| CQG-T06..T18 | 各组件历史 revision | A1 端口迁移后由 G-015 独立评审 + G-016 全量回归覆盖；**未逐组件重发 CQG** | **VALID（条件：以 G-015/G-016 回归承载）** |
| G-013/G-014 | `1d4b202` | 后续 A1/i18n/checker/DES/TEST-002 变更由 G-015/G-016 覆盖 | **历史 Gate，接受** |
| G-015 review | `09e1b46` | 覆盖 A1、i18n triage、checker RR、DES 同步 | **PASS_WITH_ACCEPTED_RISKS** |
| G-016 testing | `1cccec5` | TEST-002 @ `e74a181`；`e74a181..b10d2f5` 产品代码无变化；本任务四项复验在 `b10d2f5` 通过 | **PASS_WITH_ACCEPTED_RISKS（当前）** |
| TEST-002 | `e74a181` | 代码内容与 `b10d2f5` 相同；报告数字与 `t26-*` 证据一致 | **VALID（当前代码内容）** |
| TEST-REPORT-001 | `4f7c26b` | 历史报告；部分计数/端口描述过期；由 TEST-002 取代 | **历史，需文档注记** |

> **治理注记**：CQG 证据未在最终 revision 逐组件重发，但 `e74a181..b10d2f5` 无产品代码变化，G-015/G-016 已在最终候选上完成全量回归；该事实支持验收使用，但不应被表述为“每个 CQG 都在 `b10d2f5` 重新执行”。

---

## 3. 验收标准

### 3.1 代码级验收（可在本仓库复核）

| ID | 验收条件 | 当前证据（revision / 命令） | 结果 | 边界 |
|---|---|---|---|---|
| AC-C01 | 干净 HAP 构建 | TEST-002 @ `e74a181`：`hvigorw clean assembleHap --no-daemon` BUILD SUCCESSFUL；35 tasks；unsigned HAP；代码内容与 `b10d2f5` 相同 | **PASS（build）** | 未签名、不可安装；不是设备运行 |
| AC-C02 | 静态检查 | TEST-002：`codelinter` 0 error / 25 warning | **PASS（0 error）** | 25 条为性能建议；测试源码不在 lint 范围 |
| AC-C03 | Host 纯逻辑 | 本任务 `b10d2f5`：697/697 pass，0 fail/skip，exit 0 | **PASS（host）** | Node runner，不是 ArkTS/Hypium 设备运行 |
| AC-C04 | 协议资产交叉校验 | 本任务：66 PASS / 0 FAIL / 14 FINDING，exit 0 | **PASS 66/66** | 14 FINDING 为冻结输入勘误线索，不阻断 hard checks |
| AC-C05 | 仿真器契约 | 本任务：20/20 HTTP+TLS，exit 0 | **PASS（mock/sim）** | localhost，不是真实网关/LAN/TLS |
| AC-C06 | 分层/依赖 | 本任务：files=221，violations=0，exceptions_used=6，pending=0，port_exceptions_used=0，exit 0 | **PASS（含登记例外）** | 0 violation ≠ 端口位置完全合规；`PORT-LOC-01` 仍 OPEN |
| AC-C07 | i18n CHK-01..09 | 本任务：0 blocking / 0 missing / 73 warning / 16 hardcoded，exit 0 | **PASS** | 16 hardcoded 均非用户可见 UI（技术/品牌/Mock）；历史文案未逐条签署 |
| AC-C08 | Mock 生产排除 | TEST-002 HAP 14 条目 0 命中；host `T11_noProductionFileImportsC20MockOrOhosTest`、`T17_productionMockExclusionCoversAllMainSources` 通过 | **PASS（源级 + HAP 级）** | C-20 仍为测试替身，不是产品功能 |
| AC-C09 | 安全负例 SEC-N01..N26 | TEST-002：26 项均有 host/sim 证据；本任务 697 TAP 包含相关用例 | **PASS（host/sim）** | 设备相关子断言（N15/N16/N21 等）仍 BLOCKED |
| AC-C10 | v1 范围 | README/CB/DES/TEST-002 一致：door/light/sensor/ac 完整；switch/camera/curtain/fan/speaker 只读；无 LAN GCM 运行分支；云 Token 手工；无固件构建链 | **PASS（代码级）** | 设备行为未验证；范围不等同于设备验收 |
| AC-C11 | FR 追溯 | 26 FR 唯一、无重复；24 covered / 2 partial / 0 gap；71 精确锚点 + 17 组锚点全部核对 | **PASS（含 2 partial）** | covered 为 host/sim，不是 UI/设备 |
| AC-C12 | NFR 证据分类 | 4.1/4.2/4.3 均 PARTIAL；ACK p95 标 `MOCK_ONLY`；fps 标 `GAP/UNAVAILABLE` | **PASS（分类）** | 不得把 partial 写成达标 |
| AC-C13 | README 代码交付 | README v1.0 存在，含已验证命令、限制、设备矩阵入口 | **PASS（存在）** | 含过期数字/596 旧口径，documentation 阶段修正 |
| AC-C14 | 测试源码 lint / 覆盖率 | `code-linter.json5` 忽略 `src/test/**`、`src/ohosTest/**`；无行/分支覆盖率 | **NOT MET（已知 gap）** | 不阻断 v1；维护计划 M-08 |

**代码级验收结论**：构建、静态检查、host、契约、仿真器、分层、i18n、Mock 排除与安全负例均有当前代码内容证据；**没有发现产品行为失败、测试断言失败或环境失败**。`AC-C14` 为已登记工具债务。

### 3.2 用户侧验收（必须由用户执行，Agent 不代办）

| ID | 能力/矩阵 | 执行前提 | 证据形式 | 不得宣称的边界 |
|---|---|---|---|---|
| **U-01** | 签名安装 | 用户配置 HarmonyOS 签名（`signingConfigs` 当前为 `[]`）；签名 HAP/`.app` | 签名配置、安装日志、设备型号/OS、App revision | 未签名 HAP 不可安装；**不得**把构建成功写成可安装/可发布 |
| **U-02** | BLK-01 Hypium host | 受支持的 Linux Previewer/运行器 | `hvigorw test` 日志；若仍不可用，保留 Node runner 为正式 host 路径 | 不得把 Node runner 写成 Hypium 设备测试；不得把 `COMPILED_ONLY` 写成 PASS |
| **U-03** | BLK-02 设备/模拟器 + UI 启动 | 签名 HAP、`hdc` target、模拟器/真机 | `onDeviceTest` 日志、4 Tab/NavDestination 返回、启动截图 | 不得用 host/编译证据替代 UI 渲染/启动 |
| **U-04** | BLK-03 真实 BLE 配网 | ESP32-S3 网关固件、真实 BLE、PoP、2.4GHz Wi-Fi AP | BLE §8 的 11 条验收记录：扫描、错误 PoP、错误 Wi-Fi、隐藏 SSID、断连重连、权限/取消、两款手机、绑定三要素、网关重启、BOOT 长按、静态契约命令；脱敏日志/截图 | 不得用 host fake 宣称真实 BLE/GATT/MTU/射频互通 |
| **U-05** | BLK-04 真实 LAN / TLS pin | 真实网关、LAN 地址、HMAC 密钥；TLS 需固件 v2.1 + pin | discover/control/ACK 日志；pin mismatch/握手失败必须 P-BLOCKED、无明文回退；抓包（脱敏）、profile | 不得用 localhost 仿真器宣称真实 LAN/TLS；pin 失败不得降级明文 |
| **U-06** | BLK-05 真实华为云 IoTDA | endpoint/projectId/deviceId/IAM Token；网络 | 脱敏请求/响应、影子前后快照、`LastRequestId/LastSeq` 完成判定、Token 过期提示 | 不得用 host/canonical 测试宣称真实云；Token 手工，无自动刷新 |
| **U-07** | BLK-06 视觉/A11y/动效 | 真机/模拟器、字体缩放/读屏工具 | 4 Tab、暗黑、428×872、长英文、75% 文本膨胀、对比度、读屏、动效降级截图/录屏 | 不得用源码级 UI 守卫宣称视觉/A11y PASS |
| **U-08** | BLK-07 性能 | 真实 LAN + 设备 + profiler | ACK p95 N≥100、55ms 节流、60/120fps；设备型号/网络/样本数 | **不得**用 `MOCK_ONLY 0.609 ms` 宣称 NFR 4.3；不得用静态审查宣称 fps |
| **U-09** | BLK-08 真实硬件 | 门锁/门磁/AC/SHT30/PIR 实物 | 状态正确性、门锁四阶段、AC 模式/温度、传感器读数与来源；照片/脱敏日志 | 不得用 host 域模型宣称硬件行为/传感器到位 |
| **U-10** | 固件 v2.1 / FC-01 / FC-02 | 网关固件提供 identity v2.1 + LAN TLS 档案 + ACK `error_code`/1008 | 固件版本、TLS 证书/SPKI、ACK 错误码证据 | 固件未就绪时**不得**宣称 P-TLS-PIN/机密性/1008 完整；P-HMAC 仅完整性/防重放 |
| **U-11** | i18n 设备切换 | 真机/模拟器 | zh-CN↔en-US 运行时切换、长英文布局、无重启；截图 | 不得用 host `I18nService`/CHK 报告宣称设备 UI 语言切换 |
| **U-12** | 设备存储/密钥沙箱 | 真机/模拟器 | Asset Store/RDB 读写、秘密用后清零、进程重启后状态 | 不得用 fake store/Preferences 证据宣称 NFR 4.2 设备达标 |

**用户侧验收结论**：所有 U-01..U-12 当前均为 **BLOCKED / UNAVAILABLE / NOT RUN**。本报告只能证明“可开始用户验收”，**不能证明用户验收完成**。

### 3.3 明确的非声明（Non-claims）

- 不得声明真实 BLE / LAN / TLS pin / 华为云 IoTDA / 60-120fps / 视觉 / A11y / 真实硬件 ACK 已通过。
- 不得声明 NFR 4.1/4.2/4.3 已达标；ACK p95 `0.609 ms` 仅 `MOCK_ONLY`。
- 不得把 `COMPILED_ONLY` 的 ohosTest HAP 写成测试通过。
- 不得把 `check_layering` 0 violation 写成“端口位置已合规”；`PORT-LOC-01` 仍 OPEN，6 条 D-12 例外为 `accepted`。
- 不得把 i18n `0 blocking` 写成“615 条历史文案已签署”；当前 triage 为 6 条 `PENDING_REVIEW`、544 条 `OBSOLETE_LEGACY`、46 条 `MIGRATED`、10 条 `ACCEPTED`，另有 6 C / 3 D。
- 不得把 P-HMAC 写成“端到端加密/机密性已实现”。
- 不得把未签名 HAP 写成可安装/可发布。
- 不得把本报告写成用户验收、产品验收、release 或 G-018 的 PASS。

---

## 4. 一致性核对：需求 ↔ 设计 ↔ 测试 ↔ 文档

### 4.1 一致项（通过）

| 项 | 核对结果 | 证据 |
|---|---|---|
| 26 FR 计数/编号 | 26 唯一、无重复/遗漏；7 组计数 4/6/4/3/5/1/3 | PRD §3；TEST-REPORT-001 §5；TEST-002 §3；component-graph §6；delivery-plan §4.4 |
| v1 设备范围 | door/light/sensor/ac 完整；switch/camera/curtain/fan/speaker 只读；未知类型只读+偏差 | README §v1；CB §8.1；DES-A §6.3；TEST-002 §4.5 |
| LAN 安全通道 | P-HMAC 基线（HTTP+HMAC-SHA256，防篡改/防重放）；P-TLS-PIN 条件启用；P-BLOCKED 禁止明文回退；GCM 归档 `EXT-GCM-001` | README §通信；CB §8.3；ADR-002 §5/§6；DES-A §14/§19 |
| 云端 | IoTDA 配置 + 签名命令 + 影子轮询 + Token 过期提示；Token 手工，无自动刷新/后端代理 | README §云；CB §7.1；DES-B §8 |
| 固件边界 | 仓库仅 HarmonyOS App；无 ESP32/固件构建链；真实固件 v2.1 外部依赖 | README §1/§仓库结构；CB §1；config/project.md |
| i18n | zh-CN/en-US 单代码库；资源外置；CHK-01..09 0 blocking/0 missing；parity 100%（复数归一） | README §i18n；DES-B §7；TEST-002 §4.4；本任务 CHK 复验 |
| FR-FAM-004 v1 限制 | 本地语义 + 引导；不承诺跨设备强一致 | DES-B §3.3.6；README §已知限制；TEST-002 §3 |
| 家庭在线状态 | D-010 明确 v1 无实时在线，仅接触式收敛 | ADR-003 §10；README §已知限制；FamilyViewModel 注释 |
| 门锁三态/文案 | SECURED/UNCONFIRMED/UNKNOWN；无证据不升级 | ADR-004 §6；DES-B §10；TEST-002 §3 |
| 邀请码/stateSource/AC mode 差异 | 邀请码 6 位、stateSource 5 值、AC mode 7 值；由 CB/ADR 裁定，PRD 文本待勘误 | CB §5.2/§6.1/§6.3（E-06/E-09/E-11）；DES-A §6.5 |

### 4.2 文档漂移（documentation 阶段输入）

> 以下为**文档一致性债务**，不影响代码级验收结论；不得在 documentation 阶段之前声称文档已同步。

| ID | 位置 | 问题 | 影响 | 处置 / owner |
|---|---|---|---|---|
| **D-AC-01** | `README.md` L7/L39/L116/L184/L186；仓库结构 L255-285 | 适用基线仍为 `13dc839`；分层数字仍为 `209 files / 13 D-12 / 17 port / 10 used`；当前为 `221 files / 6 D-12 accepted / 1 port exception / 0 used`；结构未列 `contracts/**` | 用户会误读端口/例外状态；新读者看不到 A1 迁移结果 | `technical-writer`，documentation 阶段按 TEST-002/G-016 数字统一；不得改代码 |
| **D-AC-02** | `README.md` L78/L202；`MAINTENANCE-PLAN-001` §3.4/§5.1；`G-014` RA-04 | 仍写“596 条 `PENDING_REVIEW`” | 与当前 triage（6 PENDING / 544 OBSOLETE / 46 MIGRATED / 10 ACCEPTED）不一致；596 是“非 ACCEPTED 总数”，不是 PENDING 数 | `technical-writer` + `test-engineer`，documentation 阶段改为新口径；不得把 544/46 写成已人工签署 |
| **D-AC-03** | `MAINTENANCE-PLAN-001` §3.2/§3.3/§5.1 | 仍称端口迁移 P1-P3“未开始”、13 条 D-12/17 条端口例外；A1/T-23 已完成 `contracts/**`、16/17 端口关闭、6 条 D-12 accepted、1 条 PORT-LOC-01 OPEN | 维修计划与 DES-A §27.6.4 冲突；会误导后续维护排序 | `technical-writer` + `solution-architect`，documentation 阶段同步 |
| **D-AC-04** | `TEST-REPORT-001` §3.1/§3.2/§5 | 仍称“仓库尚无 `contracts/**`”；13 条 pending；§5 写 `T09_C11_*` 16 条、`T16_Scene_*` 8 条，但 T-19 实际 TAP 为 15/7（TEST-002 已改为 15/7） | 历史报告不可逐字复现；T-19 计数可信度受损 | `test-engineer` 在 documentation/维护轮加注“历史 @4f7c26b，已被 TEST-002 取代”；不改写历史结论 |
| **D-AC-05** | `G-013`/`G-014` 文本 | 仍写 17 条端口/10 使用、596 PENDING；当前已由 G-015/G-016 演进 | Gate 历史记录不应回溯改写；但验收引用必须用最新数字 | Orchestrator 在 G-017 记录“历史 Gate 数字以 G-015/G-016 为准”；不改旧 Gate |
| **D-AC-06** | `RR-03`（T-23 实现报告） | 报告文首/§7.2 与 §10 状态不一致 | documentation 一致性债务 | `technical-writer` + `solution-architect`，documentation 阶段 |
| **D-AC-07** | PRD / 数据模型 vs CB/ADR | PRD 仍写邀请码 6~8、stateSource 4 值、GCM 正常路径；数据模型仍写 AC mode 5 值、风扇 1~5 档。实现按 CB/ADR 的 6 位/5 值/7 值/percent/EXT-GCM-001 | `input/` 为冻结语料；不改代码，但需勘误提案 | `solution-architect` 走 P-09/P-14/E-06/E-09/E-10/E-11；documentation 阶段登记 |
| **D-AC-08** | `README.md` L43/L79 | ACK p95 仍写 0.598/0.589 ms | 与 TEST-002 0.609 ms 不一致；且均为 `MOCK_ONLY` | `technical-writer` 统一为“`MOCK_ONLY`，数值随环境波动，不作为验收”；不得写成达标 |

### 4.3 UI 呈现偏离（需用户接受或 bounded fix）

> 以下为本次子句级核对新发现/复核项；均为 **Low**，无安全/数据/核心控制影响，但在“代码级完成”口径下不能静默忽略。

| ID | FR | 现状 | 需求/设计依据 | 影响 | 建议 owner / 处置 |
|---|---|---|---|---|---|
| **GAP-AC-01** | FR-HOME-001 | `GatewayStatus` 无 IP 字段（`viewmodel/core/ViewModelCore.ets:99-121`）；`StatusPanels` 仅显示状态/RTT/网关名（`components/StatusPanels.ets:110-116`）；T-18 报告已记录“不显示 IP”（`artifacts/50-implementation/t18-ui-pages.md:189`） | PRD FR-HOME-001“展示…局域网 IP 与往返延迟” | 用户看不到当前 LAN IP；排障/多网关识别能力弱 | `implementation-engineer`：在 `GatewayStatus` 增加只读 `lanIp` 并显示；或用户接受为 v1 UI 简化。补 host 断言 |
| **GAP-AC-02** | FR-HOME-001 | 首页家庭名点击 `push(AppRoute.FAMILY)`（`pages/HomePage.ets:236-240`）；切换在家庭管理页（`pages/FamilyManagePage.ets:880`），无首页弹窗 | PRD FR-HOME-001“多家庭快捷切换弹窗”；UIUX §4.1“点击左上角家庭名称展开切换弹窗” | 多家庭切换多一步跳转；与 UIUX 不一致 | `implementation-engineer`/UI：实现首页 `bindSheet` 家庭切换；或用户接受跳转式切换 |
| **GAP-AC-03** | FR-ROOM-001 | `Room` 有 `icon?`（`model/FamilyModels.ets:239`）；`RoomService.createRoom(..., icon?)` 支持（`service/room/RoomService.ets:128-133`）；但 `RoomManagePage.createRoom` 未传 icon（`:123`），`RoomCard`/`RoomChipBar` 不展示 icon | PRD FR-ROOM-001“设定房间名称与图标” | 房间图标能力不可用；属外观/识别性缺失 | `implementation-engineer`：增加图标选择/展示；或用户接受为 v1 简化。补 UI/source 守卫 |
| **OBS-AC-01** | FR-DEV-002（间接） | `app/ContinuousGestureGuard.ets` 无页面引用；T-17 报告要求 T-18 滑杆“必须使用该守卫（或等价显式 flag）”；`DeviceCards.ets` 用原生 `Slider` + `SliderChangeMode.End/Click` | T-17 报告 §3/§5；DES-B §10.3 | 取消/中断手势下 TouchUp 抑制依赖 Slider 模式；设备上可能有边界差异 | `implementation-engineer`：设备验证（BLK-06/07）时重点检查；或接入守卫。当前不阻断 |
| **OBS-AC-02** | 设计系统/工具 | `GlassSurface`/`IconButton`/`SliderControl` 未使用（M-01）；`MdnsDiscoveryTransport` 因 PB-01 未接线（COMPILED_ONLY） | M-01；DES-A §15.4/PB-01 | 维护债务；mDNS 非 v1 默认发现路径 | `implementation-engineer`/`technical-writer`：维护轮清理或在文档声明；不阻断 |

### 4.4 已接受的 v1 范围性偏离（用户须知悉）

| 项 | 现状 | 依据 | 验收含义 |
|---|---|---|---|
| 家庭/成员在线状态 | 无实时在线，仅接触式收敛 | D-010、ADR-003 §10、README L73 | 用户不能期待成员在线/实时同步；FR-FAM-003 的“在线状态”子句按 v1 声明性限制处理 |
| FR-FAM-004 | 本地语义 + 引导，不承诺跨设备强一致 | ADR-003 §10、DES-B §3.3.6 | 转让/解散/退出为本地流程 |
| 扫码/二维码、设备删除/改名 UI、场景编辑、通知状态 | DEFERRED | T-18 §6.2、README L74、M-13 | 不伪造未实现能力；用户验收不得按“已实现”检查 |
| PB-01 raw UDP/mDNS | 未决；生产不传 mDNS/UDP transport，手动/上次地址可用 | DELIVERY-PLAN PB-01、DES-A §15.4、composition root 注释 | 发现能力有限；真实网关发现需用户验证 |
| PB-02 `DeviceInventoryJson` | 外部模块云完成判定 `UNSUPPORTED`；内置 `LastRequestId/LastSeq` 完整 | DELIVERY-PLAN PB-02、DES-B §8.4 | 外部模块云完成判定不完整；不得声明成功 |
| P-HMAC 机密性 | 仅完整性/防重放；无载荷机密性 | ADR-002 §5/§6、README L61/L71 | 用户须接受，或等固件 v2.1/P-TLS-PIN；不得宣称“端到端加密” |
| 未签名构建 | `signingConfigs: []`，unsigned HAP | README L81、TEST-002 §4.4 | 不能安装/发布；用户须配置签名 |

---

## 5. 验收阻塞项与建议顺序

> “阻塞项”分为 **开始用户验收的前置** 与 **完成用户验收/发布的前置**。Agent 侧代码级证据已完成；以下均需用户/外部环境参与。

| 顺序 | 阻塞项 | 类型 | 责任 | 完成条件 |
|---|---|---|---|---|
| 1 | 3 项 UI 呈现偏离的用户决定（GAP-AC-01..03） | 产品/UI 决策 | 用户 / 项目所有者 | 书面接受为 v1 简化，或派发 bounded fix 并重跑相关测试 |
| 2 | D-030/GAP-T18-01、R4-01、FR-FAM-003/004、PB-01/02、P-HMAC 限制的确认 | 风险接受 | 用户 / Orchestrator | 在 G-017/G-018 记录接受或要求修复 |
| 3 | 签名配置与可安装 HAP | 环境/发布 | 用户 | `signingConfigs` 配置、签名 HAP、安装日志 |
| 4 | 设备/模拟器 + `hdc` target | 环境 | 用户 | `hdc list targets` 非空；`onDeviceTest`/启动/4 Tab 证据（BLK-01/02） |
| 5 | 真实 BLE 配网 | 设备 | 用户 + 固件维护者 | BLE §8 的 11 条验收记录（BLK-03） |
| 6 | 真实 LAN/HMAC | 设备/网络 | 用户 | discover/control/ACK、验签/correlation/`reported_state`、无明文回退（BLK-04） |
| 7 | 真实 TLS pin / 固件 v2.1 | 固件/安全 | 固件维护者 + `solution-architect` + 用户 | identity v2.1、LAN TLS、SPKI pin、P-BLOCKED（FC-01）；未就绪则用户接受 P-HMAC |
| 8 | 真实华为云 IoTDA | 外部云 | 用户 | endpoint/projectId/deviceId/IAM Token；命令/影子/完成判定/过期提示（BLK-05） |
| 9 | 门锁/门磁/AC/SHT30/PIR 实物 | 硬件 | 用户 | 状态正确性/门锁四阶段/AC 模式温度/传感器来源（BLK-08） |
| 10 | 视觉/A11y/动效 | 设备/UI | 用户 | BLK-06 截图/录屏/读屏/文本膨胀 |
| 11 | 真实 p95/55ms/60-120fps | 性能 | 用户 | BLK-07 原始测量数据；不得用 mock |
| 12 | 文档同步（D-AC-01..08、RR-03） | 文档 | `technical-writer` + `test-engineer` + `solution-architect` | README/维护计划/测试报告/Gate 引用一致；不修改 `input/` |
| 13 | i18n 历史文案收口（6 PENDING/11 B/6 C/3 D） | 质量/文档 | `technical-writer` + `implementation-engineer` | 逐条 triage/重写/复核；不得批量误标 |
| 14 | 许可证与发布策略 | 法律/发布 | 项目所有者 + 用户 | `LICENSE` 确定；push/PR/MR/远端基线策略授权；`main_merge_mode` 合规 |

**建议顺序**：1→2（用户决策/风险接受，无需环境）→ 3→4（签名/设备 smoke）→ 5→6（BLE/LAN 核心链路）→ 7（TLS/固件，或接受 P-HMAC）→ 8/9（云/硬件，可并行）→ 10/11（视觉/性能）→ 12/13（文档/i18n）→ 14（许可证/发布）。

---

## 6. Verdict 与条件

### 6.1 Verdict

**`READY_FOR_USER_ACCEPTANCE`（有条件）**

含义：
- **可以开始用户验收**：代码级功能/安全证据完整、当前 revision 可复现、用户侧清单明确。
- **不是“用户验收已通过”**：U-01..U-12 均未执行；用户验收完成仍需设备矩阵与用户决定。
- **不是“产品验收/release PASS”**：未签名、无真实设备/云/TLS、文档未收尾、许可证未定。

### 6.2 条件（全部满足才可完成用户验收）

1. **UI 偏离决定**：用户对 `GAP-AC-01..03` 作出“接受为 v1 简化”或“要求 bounded fix”的书面决定；若要求修复，修复后重跑 host/layering/i18n 与相关 UI 证据。
2. **P-HMAC/固件决定**：用户接受 P-HMAC 无机密性，或提供固件 v2.1 并完成 P-TLS-PIN 真实验证；不得在未验证时宣称机密性/TLS。
3. **设备矩阵**：用户按 §3.2 执行 BLK-01..08，提供脱敏证据；不得用 host/mock 外推。
4. **风险接受**：用户/Orchestrator 确认 D-030/GAP-T18-01、R4-01、PB-01/PB-02、FR-FAM-003/004、i18n 历史文案、测试 lint/覆盖率等已登记风险。
5. **文档同步**：documentation 阶段完成 D-AC-01..08 与 RR-03；README 不得再写 596 `PENDING_REVIEW`、13/17 例外或旧基线。
6. **发布授权**：release 需用户显式授权签名/推送/PR/MR/远端基线策略；本报告不授予。

---

## 7. Stage Gate 建议（G-017 acceptance）

### 7.1 逐项建议

| # | 检查项 | 结论 | 依据/条件 |
|---|---|---|---|
| 1 | 26 FR 清点/编号 | **PASS** | §1；唯一、无重复/遗漏 |
| 2 | FR → 设计 → 组件 → 任务 → 代码 → 测试 | **PASS（含 2 partial + 3 UI-DEVIATION）** | §2；71 精确锚点 + 17 组锚点全部核对 |
| 3 | Requirement 无实现 | **PASS（功能级）**：0 整条 FR 缺失；3 项 UI 子句偏离明确登记 | §2.4.1/§4.3；需用户决定 |
| 4 | 代码无 Requirement | **PASS**：无孤儿产品特性；Mock/工具/未引用组件有明确理由 | §2.4.2；OBS-AC-01/02 |
| 5 | Requirement 无测试 | **PASS**：26/26 有当前 TAP 锚点；无“未运行=通过” | §2.4.3 |
| 6 | 设计/代码一致 | **PASS（条件）**：冻结签名/错误码/安全语义一致；UI 偏离与文档漂移已登记 | §2.4.4/§4.2/§4.3 |
| 7 | Gate 证据新鲜度 | **PASS（治理注记）**：G-016 当前；CQG 历史由 G-015/G-016 回归承载 | §2.5 |
| 8 | 代码级验收 | **PASS**：build/lint/host/contract/sim/layering/i18n/Mock/安全负例 | §3.1；AC-C14 为已知 gap |
| 9 | 用户侧验收 | **NOT COMPLETE**：BLK-01..08 未执行 | §3.2；用户执行 |
| 10 | NFR | **PARTIAL（如实）**：4.1/4.2/4.3 均 partial；4.3.3 无测量 | §2.3；不得写成达标 |
| 11 | 文档一致性 | **ACTIONS REQUIRED**：D-AC-01..08/RR-03 | §4.2；documentation 阶段 |
| 12 | release | **NOT AUTHORIZED** | 签名/设备/文档/许可证/用户授权均未完成 |

### 7.2 Gate 建议

- **G-017 acceptance（acceptance readiness 范围）**：**`PASS_WITH_ACCEPTED_RISKS`**，前提是 Orchestrator 在 Gate 记录中逐项登记：
  1. 3 项 UI-DEVIATION 与用户决定状态；
  2. U-01..U-12/BLK-01..08 尚未执行，用户验收未完成；
  3. NFR 4.1/4.2/4.3 partial，P-HMAC 无机密性/真实 TLS 未验证；
  4. D-AC-01..08/RR-03 转 documentation；
  5. 不得把本报告解释为用户验收、产品验收或 release PASS。
- **是否可进入 documentation 阶段**：**可以**。documentation 阶段应消费 §4.2 的 D-AC 清单与 §4.3 的 UI 决定，更新 README/维护计划/测试报告/Gate 引用；**不得**修改 `input/`（走 P/E 提案）。
- **release**：**不启动**。需用户授权签名/推送/PR/MR/远端策略；需用户验收证据、文档收口、许可证确定。`main_merge_mode: review_request_when_remote`，本地 `main` 与 `origin/main` 历史不相关，禁止擅自本地直并。

### 7.3 不得由本报告声明

- 不得声明 G-017 已由 system-verifier 判定 PASS；Gate 判定权在 Orchestrator。
- 不得声明用户验收、产品验收、设备验收、release 或 G-018 PASS。
- 不得声明真实 BLE/LAN/TLS/云/视觉/A11y/fps/硬件通过。
- 不得声明 NFR 4.1/4.2/4.3 达标或端口位置已合规。

---

## 8. 残余风险登记（验收视角）

| ID | 风险 | 级别 | 现状/证据 | 接受/复审 |
|---|---|---|---|---|
| RA-AC-01 | P-HMAC 无机密性；“端到端机密性”未达成 | **High（安全声明）** | ADR-002 §5/§6；README L61/L71；真实 TLS BLK-04/FC-01 | 用户接受，或固件 v2.1 + P-TLS-PIN 设备验证；不得宣称机密性 |
| RA-AC-02 | 真实 BLE/LAN/TLS/云/硬件/视觉/fps 未验证 | **High（验收覆盖）** | BLK-01..08；TEST-002 §5.3 | 用户执行 §3.2；Agent 不代办 |
| RA-AC-03 | D-030/GAP-T18-01：`addGatewayToFamily` 无 actor/RBAC | **Medium** | G-014 RA-01；T-20 F-08；README L75 | v1 接受（UI ADMIN 门 + BLE PoP + 内部 API 边界）；后续 C-22/C-09/C-15 复审 |
| RA-AC-04 | R4-01：配网取消后 durable 写不可回滚 | **Info** | G-014 RA-02；README L76 | v1 接受；后续配网 VM 变更补边界用例 |
| RA-AC-05 | 端口位置例外 `PORT-LOC-01` 仍 OPEN；6 条 D-12 例外 accepted | **Medium（治理）** | 本任务 layering：port_exceptions_used=0；DES-A §27.6.4；DES-B §18.1 | 0 violation ≠ 合规；维护轮迁移；G-017 记录 |
| RA-AC-06 | i18n 历史文案未逐条签署（6 PENDING/11 B/6 C/3 D） | **Low** | TEST-002 §5.2；triage 615 行 | 维护轮/文档收口；不得写 596 PENDING |
| RA-AC-07 | 测试源码未 lint、无覆盖率 | **Low** | `code-linter.json5` 忽略 test/ohosTest；TEST-002 §5.2 | 维护计划 M-08；不阻断 v1 |
| RA-AC-08 | ACK p95 仅 MOCK_ONLY 0.609 ms | **Info** | `t26-ack-p95-mock.json`；resultClass MOCK_ONLY | 不作为 NFR 4.3；BLK-07 |
| RA-AC-09 | 未签名 HAP 不可安装 | **Medium（发布）** | `signingConfigs: []`；README L81 | 用户配置签名；release 前必须 |
| RA-AC-10 | 许可证 TODO | **Low（法律）** | README L317；MAINTENANCE-PLAN §5.1 | 首次公开发布前由项目所有者确定 |
| RA-AC-11 | CQG 未在最终 revision 逐组件重发 | **Low（治理）** | CQG revision vs `b10d2f5`；G-015/G-016 回归 | Gate 记录；不影响当前行为证据 |
| RA-AC-12 | UI-DEVIATION GAP-AC-01..03 | **Low（产品）** | §4.3 | 用户接受或 bounded fix |
| RA-AC-13 | PB-01 raw UDP/mDNS 未决；PB-02 外部模块 inventory 未决 | **Medium（功能范围）** | DELIVERY-PLAN §9；DES-A §15.4；DES-B §8.4 | v1 声明性限制；用户知悉 |
| RA-AC-14 | 家庭在线状态/实时同步缺失；FR-FAM-004 本地语义 | **Low（产品）** | D-010/ADR-003 §10；README L73 | v1 声明性限制；用户知悉 |
| RA-AC-15 | `ContinuousGestureGuard` 未接线；取消/TouchUp 边界未设备验证 | **Low** | T-17 报告 §3/§5；`DeviceCards.ets` 原生 Slider | BLK-06/07 设备验证；可选接入 |

---

## 9. 证据索引与可复现命令

### 9.1 本任务实际执行

```bash
# cwd = /home/quirkybrain/code/harmony-projects/YaoCore
git rev-parse HEAD                    # b10d2f50c931b7c82cd8a2105fbe804582d24b32
entry/src/test/run-host-tests.sh      # 697/697, exit 0
PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py
                                      # 66 PASS / 0 FAIL / 14 FINDING, exit 0
PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py
                                      # files=221 violations=0 exceptions_used=6 port_exceptions_used=0, exit 0
PYTHONDONTWRITEBYTECODE=1 python3 entry/src/test/i18n/check_i18n.py --strict-ui
                                      # 0 blocking / 0 missing / 73 warning / 16 hardcoded, exit 0
no_proxy=127.0.0.1,localhost NO_PROXY=127.0.0.1,localhost \
  PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tools.simulator.test_gateway_contract -v
                                      # Ran 20 tests ... OK, exit 0
```

### 9.2 既有证据（当前代码内容适用）

| 证据 | 路径 | 用途 |
|---|---|---|
| TEST-002 测试阶段报告 | `artifacts/60-testing/testing-stage-report.md` | 11 项矩阵、FR/NFR 映射、BLK 清单 |
| TEST-002 证据 | `artifacts/60-testing/evidence/t26-*` | host TAP、crosscheck、simulator、layering、i18n、ACK p95、HAP 排除 |
| TEST-REPORT-001 | `artifacts/60-testing/test-report.md` | T-19 历史矩阵/SEC 映射（数字以 TEST-002 为准） |
| 独立评审 | `artifacts/70-review/final-system-review.md` | F-01..F-09、安全/分层/i18n 复核 |
| 集成报告 | `artifacts/90-integration/integration-report.md` | IG-4、组件状态、残余风险、§11-§15 合并记录 |
| 交付计划 | `artifacts/30-plan/delivery-plan.md` | FR→任务/Gate 映射、Stage Gate 清单 |
| 组件图 | `artifacts/30-plan/component-graph.md` | C-01..C-29、FR 映射、任务/Gate 索引 |
| README / 维护计划 | `README.md`、`artifacts/80-maintenance/maintenance-plan.md` | 用户命令、限制、BLK 矩阵、风险接受 |
| Gate 记录 | `state/gates/G-013..G-016` | 集成/Stage/review/testing 判定链 |

### 9.3 追溯索引

- Requirements：`input/requirements/YaoCore_HarmonyOS_App_Requirements.md` §3（26 FR）/§4（NFR 4.1..4.3）。
- Contracts：`artifacts/20-architecture/contract-baseline.md`、ADR-001..004、`project-constraints.md`。
- Design：`artifacts/40-detailed-design/des-001a-foundation-transport.md`、`des-001b-domain-presentation.md`。
- Plan：`artifacts/30-plan/delivery-plan.md`、`component-graph.md`。
- Test：`artifacts/60-testing/test-plan.md`、`test-report.md`、`testing-stage-report.md`、`entry/src/test/**`、`tools/**`。
- Review/Integration：`artifacts/70-review/final-system-review.md`、`artifacts/90-integration/integration-report.md`。
- State/Gate：`state/project-state.md`、`state/checkpoint.md`、`state/gates/**`、`state/handoffs/wp-108-acceptance.json`。

---

## 10. 结论与下一步

1. **代码级**：26 FR 无整条缺失；24 covered（functional，host/sim）、2 partial、0 gap；NFR 4.1/4.2/4.3 partial。构建/lint/host/contract/sim/layering/i18n/Mock 排除/安全负例均有当前代码内容证据。
2. **用户侧**：U-01..U-12 全部待执行；BLK-01..08 是用户验收的主清单；ACK p95/fps/真实 TLS/云/硬件/视觉不得用 host/mock 替代。
3. **待决项**：3 项 UI-DEVIATION（GAP-AC-01..03）与 P-HMAC 机密性限制必须由用户作出接受/修复决定；D-AC-01..08/RR-03 转 documentation。
4. **Verdict**：`READY_FOR_USER_ACCEPTANCE`（有条件）；**用户验收未完成**。
5. **Stage Gate**：建议 G-017 acceptance `PASS_WITH_ACCEPTED_RISKS`（仅 readiness 范围），允许进入 documentation；**release 不启动**，需用户授权与设备/签名/文档/许可证闭环。

> 本报告只覆盖 `b10d2f5` 与 §0 环境，以及 §9 所列证据。设备/真实网络/视觉/性能/云/TLS 未验证项不在本报告 PASS 范围内；本报告不替代用户验收、产品验收、release 或 G-018 判定。

---

*ACCEPT-001 结束。*
