# T-09 修复复审报告（R-01..R-15 关闭确认与 CQG-T09 意见）

- **Artifact ID**: REVIEW-T09B-DOMAIN
- **Producer**: agent:quality-reviewer
- **Type**: Independent Code Review（Re-review）
- **Status**: CHANGES_REQUIRED（本报告不授予 `STABLE`，不作为 CQG-T09 或 Stage Gate 的通过证据）
- **Date**: 2026-10-17
- **Task**: `wp-027-review-t09b` / 被审修复任务 `wp-026-fix-t09`
- **Reviewed Revision**: `621096babe646b90d620de0f1fba2729a22a4730`（`fix(domain): 修复 T-09 评审发现`）
- **Prior Review Revision**: `207e7ada865a1f41f3fe310f4ae3f2f621bdcbf4`（`REVIEW-T09-DOMAIN`）
- **Implementation Revision**: `5e110db71b800e99da1ccbe2331b422f48843ec0`
- **Base Revision**: `57f64d45c7442289db489df4cb6e62816815c43c`
- **Workflow**: STANDARD / GATED_AUTO
- **评审方式**: 只读代码审查 + 只读复验 + 独立 Node 探针（stdin 执行，不落盘、不改仓库）；唯一写入为本报告。
- **独立性声明**: 被审实现的 Producer 为 `agent:implementation-engineer`；本复审由未参与 T-09 修复实现的 `agent:quality-reviewer` 执行。作者未参与本报告的裁决。

---

## 1. 复审范围、revision 与输入完整性

### 1.1 范围内

| 类别 | 路径/内容 |
|---|---|
| 修复提交 | `621096b` 相对 `207e7ad` 的 25 个路径；相对 `5e110db` 的 27 个路径（含上轮评审报告与修复报告） |
| 仓储修复 | `repository/FamilyRepository.ets`、`DeviceRepository.ets`、`DomainOperationGate.ets`、`DomainMigrations.ets`、`RoomRepository.ets`、`SceneRepository.ets` |
| 服务修复 | `service/family/FamilyService.ets`、`service/room/RoomService.ets`、`service/scene/SceneService.ets`、`service/scene/SceneExecutor.ets` |
| 测试与证据 | `entry/src/test/host/**`、`domain/**`、`storage/FakeStores.ets`、`README.md`、`evidence/t09-fix-*` |
| 修复报告 | `artifacts/50-implementation/t09-fix-report.md` |

`git diff --name-status 5e110db..621096b` 的全部路径均落在 Writes / `snapshot_paths` 声明范围内；未发现产品源码范围外修改、构建产物、HAP、证书、密钥或 `.hvigor` 内容入库。

### 1.2 输入与快照

- 8 个 pinned input 的 sha256 与 `state/handoffs/wp-027-review-t09b.json` 全部一致（逐项校验通过）。
- 评审目标已有 Git snapshot：`refs/swe/snapshots/20261017T103728Z-wp-027-review-t09b-4c016e6d`，覆盖 `entry/src/main/ets/repository/`、`entry/src/main/ets/service/`、`entry/src/test/`、`artifacts/` 的相关内容。
- 复验前后 `git status --short` 均为 clean；构建产物被 `.gitignore` 忽略。
- 本报告仅覆写 `artifacts/70-review/t09-review-b.md`；未修改任何被审代码、测试、证据或上游 Artifact。

### 1.3 排除/未覆盖

- 真实 HarmonyOS RDB、Preferences、Asset Store、真实事务回滚与设备 ACK（无 `hdc` target、无签名、无模拟器；保持 `BLOCKED`）。
- `hvigorw test` 的 Hypium 实际执行（Linux Previewer 环境限制；仅有 `UnitTestArkTS` 编译证据，保持 `COMPILED_ONLY`）。
- C-12 AuthService、C-13 InviteService、C-15 CloudService、C-22/C-28 组合根与 UI/ViewModel 的最终实现；仅评审 T-09 的端口边界与调用语义。
- HAP 默认可达图：现有 `pages/Index` 尚未装配 C-28 组合根，`assembleHap` 不会把全部新增模块拉入可达图。

---

## 2. 本次独立复验结果

| 命令 | 结果 | 说明 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS**：`1..243`、`# pass 243`、`# fail 0`、exit 0 | 本次独立复跑；与 `t09-fix-host-node-tests.tap` 的 243/243 一致。 |
| `codelinter -c code-linter.json5 -p default .` | **PASS**：`No defects found in your code.`、exit 0 | 首次与 `hvigorw clean` 并行运行时在 2% 处出现一次 `Some error occurred during linting. This may cause incomplete report results.` 提示；随后单独复跑干净，无 defects、exit 0。 |
| `hvigorw clean assembleHap --no-daemon` | **PASS**：`BUILD SUCCESSFUL in 5 s 55 ms`、`35 tasks in total: 34 executed, 1 up-to-date`、exit 0 | 仅证明当前 HAP 默认可达图可构建；新增领域模块的 ArkTS 编译由修复证据的 `UnitTestArkTS` 覆盖，不等同设备执行。 |
| `git status --short`（复验后） | clean | 未产生未声明仓库改动。 |

### 2.1 证据核对

- `t09-fix-host-node-tests.tap`：243/243，TAP 行数与本次复跑一致。
- `t09-fix-clean-assemble.log`：`BUILD SUCCESSFUL`、35 tasks，与本次复跑一致。
- `t09-fix-codelinter.log`：`No defects found`、exit 0；本次复跑同样通过。
- `t09-fix-hvigor-test-compile.log`：`UnitTestArkTS` 完成（9 s 456 ms），随后 Previewer 超时；按修复报告保留为**编译证据**，不当作 Hypium 执行 PASS。
- 修复报告中的 `ohpm install` 为附加证据；本次未重复执行（不影响上述四条必需命令的结论）。

### 2.2 独立探针（只读；不落盘）

使用与 host harness 相同的 Node ESM loader，在 stdin 中直接调用公开类；未创建/修改仓库文件。关键结果：

```json
{
  "replay_same_receipt": {
    "second_error": "none",
    "usedCount": 2,
    "maxUses": 2,
    "members_after_second": 2,
    "distinct_second_receipt_error": "INVITE_MAX_USES",
    "members_after_distinct": 2
  },
  "receipt_atomic_rollback": {
    "error": "CONFIGURATION_ERROR",
    "usedCount": 0,
    "status": "PENDING",
    "member_exists": false
  },
  "gate_legit_queue": {
    "firstResult": "first",
    "secondResult": "none",
    "secondError": "CONFIGURATION_ERROR",
    "order": ["first-start", "first-end"]
  },
  "production_runner_nested": {
    "outcome": "timeout",
    "nestedSettled": false,
    "drivers_started": 1
  }
}
```

- **正例**：`receipt_atomic_rollback` 证明回执更新与成员写入在同一仓库事务内；成员写入失败后 `usedCount=0`、状态回到 `PENDING`、无残留成员。R-01 的核心失败路径已关闭。
- **新发现**：`replay_same_receipt` 证明同一回执（同一 member）第二次导入仍成功并把 `usedCount` 推到 `maxUses=2`，但成员数仍为 2（owner + member-a）；随后另一成员的有效回执被 `INVITE_MAX_USES` 拒绝。见 R2-01。
- **R-04 风险**：默认 gate 下，首个合法操作耗时 2100 ms 时，第二个**非嵌套**的普通调用在 2000 ms 后被 `CONFIGURATION_ERROR(field=nestedOperationOrQueueTimeout)` 拒绝，而不是继续排队。见 R2-02。
- **O-1 生产边界**：`RdbTransactionRunner` 的嵌套 `transaction` 仍然排队而不是 fail-fast；外层等待内层时 120 ms 超时未完成（`nestedSettled=false`）。这是 C-06/T-08 的已登记残余（T09-FIX-03），不是 T-09 内可修复的调用路径（T-09 的 tx-context 类型为 `RdbTransaction`，不含 `transaction`）。

---

## 3. R-01..R-15 逐条关闭状态

状态定义：**Closed** = 代码、负例与本次独立探针均支持关闭；**Closed with limitation** = 行为正确但有已登记的上游类型/范围限制；**Partially closed** = 核心问题已修复但仍有同族缺口。

| ID | 上轮严重度 | 状态 | 本次证据与判断 |
|---|---|---|---|
| R-01 | High | **Closed（核心）；同回执重放另见 R2-01** | `FamilyService.importReceipt` 在 `verifyReceipt` 与成员写入前调用 `requireUsableInvitation`（`FamilyService.ets:392-399`）；`FamilyRepository.applyReceiptAndEnsureMember` 在同一 `rdb.transaction` 内先 `applyReceiptInTransaction`、再成员 upsert/激活（`FamilyRepository.ets:539-556`）；失败整体回滚。`T09_C08_revokedReceiptLeavesNoActiveMember`、`T09_C08_expiredReceiptLeavesNoActiveMember`、`T09_C08_receiptInviteMismatchIsRejectedBeforeMemberWrite` 通过；独立探针 `receipt_atomic_rollback` 通过。**但同一回执重放会重复递增 `usedCount`，见 R2-01。** |
| R-02 | High | **Closed** | `SceneService.run` 以 `activeSceneRuns: Map<sceneId, runId>` 做单飞，第二次调用在命令下发前抛 `SCENE_RUN_IN_PROGRESS`（`SceneService.ets:153-169`）；`finally` 释放（`:200-204`）。`T09_C11_sameSceneConcurrentRunIsRejectedAndNeverDoubleDispatches` 证明首 run 阻塞时第二次被拒、释放后命令数 2、完成后可再次运行。 |
| R-03 | High | **Closed** | `SceneExecutor` 在 `ackAccepted` 且步骤失败（含 `MISMATCH`）时，先 `applyAckBestEffort` 写回网关 `reportedState`，再 `failAt`（`SceneExecutor.ets:165-180`）。`T09_C11_mismatchWritesGatewayTruthToSsot` 断言 `FAILED`、`stateVerification=MISMATCH`、SSOT `powerStatus=true`。 |
| R-04 | High | **Closed（T-09 边界）；有 R2-02 风险与 C-06 残余** | `DomainOperationGate` 同步重入 `dispatching` fail-fast（`:48-50`、`:94-101`）；异步重入以默认 2000 ms 有界队列等待（`:42-84`）；fake `RdbStore.transaction` 在入队前检查 `inTransaction`（`FakeStores.ets:163-168`）。`T09_O1_gateRejectsSynchronousNestedRun`、`T09_O1_gateRejectsAsyncReentrantCallInsteadOfHanging`、`T09_O1_nestedFakeTransactionFailsFast` 通过。T-09 的 tx-context 仅暴露 `execute/query`（`RdbStore.ets` 的 `RdbTransaction` 不含 `transaction`），类型上禁止 T-09 代码嵌套。**但 2000 ms 会误拒等待超过 2 s 的合法普通调用（R2-02）；生产 `RdbTransactionRunner` 的嵌套事务仍排队（C-06/T09-FIX-03）。** |
| R-05 | Medium | **Closed** | `SceneExecutor.failAt` 在 `failedIndex` 仍为 PENDING 时置 FAILED（`:202-208`）；`T09_C11_totalTimeoutMarksTheBlockedStepFailedNotPending` 断言 `steps[1]=FAILED`、仅 1 条命令。 |
| R-06 | Medium | **Closed** | `RoomRepository`/`DeviceRepository`/`SceneRepository` 均暴露静态 `registerMigrations`，委托 `DomainMigrations.register`；后者按 `MigrationSink` 实例幂等（`DomainMigrations.ets:65-75`）。`DomainHarness` 实际通过三个静态入口完成 v1..v4；`T09_C09_v4StaticRegistrationIsDelegatedAndIdempotent` 通过，且非规范重复注册仍由 `MigrationRegistry` 拒绝。 |
| R-07 | Medium | **Closed** | `DeviceRepository.assignRoom` 在端口层直接比较 `room.familyId === familyId`，不匹配返回 `ROOM_NOT_FOUND`（`DeviceRepository.ets:537-548`）。`T09_C10_assignRoomRejectsRoomFromAnotherFamily` 通过，设备仍在未分配池。 |
| R-08 | Medium | **Closed with limitation（已登记）** | `dissolveFamily` 以 `routes.listRoutesByFamily` 为权威并与 family 行合并去重（`FamilyService.ets:139-160`、`:514-545`）；`leaveFamily` 返回完整网关列表（`:174-196`）。`T09_C08_dissolveUsesRouteAuthorityAndReturnsEveryGateway`、`T09_C08_leaveFamilyReturnsEveryBoundGatewayAndRemovesProfile` 通过。`RemoveMemberResult`/`ExpireGuestsResult` 的 `RotationPlan` 仍为 DES-B §3.1.3 的单网关类型，逐网关引导登记 T-13/C-23（T09-FIX-05），属于已登记上游类型限制而非本次回归。 |
| R-09 | Medium | **Closed** | `updateMemberRole`、`updateMemberStatus`、`upsertMemberInTransaction`、`removeMemberInTransaction` 均拒绝降级/停用/移除 owner（`FamilyRepository.ets:357-405`、`:724-737`、`:800-818`）；`transferAdmin` 仍可显式转移 owner（`:582-620`）。`T09_C08_ownerCannotBeDemotedOrRemovedAndTransferRemainsPossible` 通过（降级/移除/停用均 `AUTH_RBAC_DENIED`，随后 transfer 成功且旧 owner 可移除）。 |
| R-10 | Medium | **Closed（按 D-022）** | `applyReceiptInTransaction` 将 ACCEPTED 视为“回执记录”而非终态；`usedCount < maxUses` 且未过期时继续可用（`FamilyRepository.ets:745-779`）；`markInvitationStatus` 允许 ACCEPTED 撤销/过期（`:868-887`）；`FamilyService.revokeInvitation`/`expireInvitations` 按 D-022 处理。`T09_C08_codeKekMultipleReceiptsFollowD022`（不同 member）、`T09_C08_acceptedCodeKekCanStillBeRevokedWhileUsesRemain` 通过。**但同回执重放未拒绝，见 R2-01；DES-B §3.3.3/§3.1.3 未同步 D-022，见 R2-04。** |
| R-11 | Medium | **Closed** | `FamilyService.validateInvitationInput` 在调用 `InviteServicePort` 前校验 targetRole、GUEST room、UUID、ttl、CODE_KEK maxUses（`FamilyService.ets:562-582`）；`createInvitationForJoinRequest`/`createCodeInvitation` 先校验后 `createInvitation`（`:322-355`）。`T09_C08_invitationValidationNegativeCases` 断言正确错误码且 `h.invites.createRequests` 零增量（无 C-13 侧副作用）。C-13 内部失败的跨存储补偿仍归 T-13（T09-FIX-06）。 |
| R-12 | Medium | **Closed（诊断缓存另见 R2-05）** | 设备事件在事务内收集、提交后 `dispatchEvents`（`DeviceRepository.ets:118-129`、`:310-322`、`:327-338`、`:942-950`）；`emit` 逐订阅者隔离并记录诊断；Room/Scene/SceneExecutor 的 listener 均隔离。`T09_C10_throwingListenerDoesNotAbortDiscover`、`T09_C10_commitFailureEmitsNoDeviceEvent`、`T09_C09_throwingListenerDoesNotFailRoomDeletion`、`T09_C11_throwingProgressAndEventListenersDoNotFailRun` 通过。**`mergeStates`/`partialKeys` 仍在事务内修改、提交失败不回滚，属于诊断缓存残余（R2-05 Low）。** |
| R-13 | Medium | **Closed** | `removeDevicesForGateway` 在 `rdb.transaction` 之前读取 route，事务回调内只访问 `tx`（`DeviceRepository.ets:649-685`）。`T09_C10_removeDevicesForGatewayReadsRouteOutsideTransaction` 通过（包装路由端口断言读取时 `isInTransactionForTest()===false`，并验证设备与场景引用清理）。 |
| R-14 | Medium | **Closed** | `DiscoverApplyResult.partial` 改为 `snapshot.isPartial || invalidDropped > 0`，且 `invalidDropped > 0` 时不推断 `gateway_removed`（`DeviceRepository.ets:277-298`）。`T09_C10_duplicateAndFamilyMismatchDevicesSetPartial` 通过（重复/家庭不匹配 → `partial=true`、`invalidDropped=1`、`gatewayRemovedMarked=0`）。 |
| R-15 | Medium | **Closed（覆盖缺口见 R2-01）** | 新增 27 个用例（216 → 243），覆盖 removeMember/session 失效、changeMemberRole、leaveFamily profile、unbound/family mismatch/duplicate discover、UNASSIGNED、same-scene、step/total timeout + 迟到 outcome、O-1 嵌套负例、owner 降级/移除、revoked/expired receipt。**同回执 CODE_KEK 重放未覆盖；README 的分类计数有误（R2-03）。** |

### 3.1 上轮未要求修复的 Low 项

R-16..R-19（可选路由端口 fail-closed、`notBeforeMs` 防御、网关解绑 tombstone 清理、列表 N+1）不在本次修复报告的 R-01..R-15 处置范围内；本次未发现它们被修复引入的新回归，仍按上轮报告保留为 Low 跟踪项。

---

## 4. 新发现（R2-xx）

### R2-01（Medium）同一回执重放会重复消耗 CODE_KEK 的 `usedCount`，且不产生新成员

- **位置**：`entry/src/main/ets/repository/FamilyRepository.ets:745-779`（`applyReceiptInTransaction` 只检查状态/过期/`usedCount`，不比较 `record.receipt` 与 `patch.receipt` 或 `acceptedByMemberId`）；`FamilyRepository.ets:539-553`（现有成员 ACTIVE 时不再 upsert，但仍先递增 `usedCount`）；`entry/src/main/ets/service/family/FamilyService.ets:392-419`。
- **契约引用**：ADR-003 §5.4（“Admin 注册表单次”“`inviteId` 在 Admin 注册表内一次性；拒绝重复回执”）；DES-B §3.4（host 测试要求“重复回执拒绝”）；上轮 R-01 建议“重复回执映射 `INVITE_RECEIPT_INVALID`”。D-022 允许 CODE_KEK 在 `usedCount < maxUses` 时接受**后续回执**，但未明确允许**同一回执**重放。
- **独立复现**：`maxUses=2` 的 CODE_KEK 邀请；同一 `receipt-a`/member-a 连续导入两次 → 第二次无错误，`usedCount=2/2`，成员数仍为 2（owner + member-a）；随后 member-b 的有效回执 → `INVITE_MAX_USES`，成员数仍为 2。
- **影响**：Admin 重试/重复扫码可能耗尽多用途 CODE_KEK 邀请，`usesRemaining` 与“可重复使用”UI 失真；后续成员无法加入，但不会产生未授权成员或秘密泄漏。属于弱模式（非默认路径）的审计/可用性缺陷。
- **补充**：若 T-13 的真实 `verifyReceipt` 自行拒绝同回执，必须把该语义写入 `InviteServicePort` 契约并在 C-08 侧补防御/测试；当前 fake 与 C-08 代码均未拒绝，因此至少是契约/测试缺口，不能默认为 C-13 会兜底。
- **建议**：在 `applyReceiptInTransaction` 中比较 `record.receipt === patch.receipt`（必要时同时比较 `acceptedByMemberId`）；重复回执应幂等返回或抛 `INVITE_RECEIPT_INVALID`，不得递增 `usedCount`；补“同回执重放不消耗 use、不同回执按 D-022 成功”的 host 用例（同时覆盖 KEY_WRAP/CODE_KEK）。
- **关闭标准**：修复 + 新用例 + 243→244（或等价）全 PASS；复跑本报告 §2 四条命令。

### R2-02（Medium，设计风险/需裁定）DomainOperationGate 的 2000 ms 有界等待会误拒合法普通调用

- **位置**：`entry/src/main/ets/repository/DomainOperationGate.ets:42-84`；修复报告 §3.2 声称“不改变正常串行行为”。
- **独立复现**：默认 `new DomainOperationGate()`；第一个**合法顶层操作**耗时 2100 ms；第二个独立的普通调用（非嵌套）在约 2000 ms 后收到 `CONFIGURATION_ERROR(field=nestedOperationOrQueueTimeout)`，第一个操作正常完成。
- **判断**：O-1 的核心意图是“禁止嵌套/不得挂起”。同步重入 fail-fast、异步重入有界失败、fake 事务 fail-fast 均成立；在 T-09 边界内类型隔离也成立。但 ArkTS 无 async-context，gate 无法区分“异步重入”和“普通排队”，因此 2000 ms 是一个**全局队列等待上限**，不是只针对嵌套调用的检测。它把“可能挂起”转换为“确定性失败”，代价是合法操作在长操作后排队超过 2 s 时被误拒。
- **影响**：低端设备/大设备集 discover 或长事务后，UI 的合法读/写可能显示 `CONFIGURATION_ERROR`；默认值由组合根决定，目前 C-28 尚未装配，故尚未成为生产缺陷。
- **建议**：由 Orchestrator 明确接受“确定性失败优先于挂起”的取舍并在组合根设置合适的超时/文档；或提高默认值并为合法长队列补测试。至少修正修复报告“正常串行行为不变”的表述。
- **关闭标准**：书面接受 + 组合根配置说明，或改为不影响普通排队的实现；补“合法长队列”用例。

### R2-03（Low）测试分类计数与 README 不一致

- **位置**：`entry/src/test/README.md:90-93`。
- **事实**：当前 host 共 243（正确）；按用例名前缀实际为 C-08 25、C-09 10（含 `T09_C09_v4StaticRegistration...` 在 Device 文件）、C-10 23、C-11 15、O-1 4，共 77 个 T-09 用例。README 写 C-09 9、C-10 26、O-1 5（合计 80），并把 v4 静态注册归入 O-1；修复报告的“+27 / 216→243”与总数正确。
- **影响**：不影响测试 PASS，但削弱证据可追溯性与 CQG 计数的一致性。建议修正 README 的分类口径（按文件或按前缀统一）。

### R2-04（Low）新增 `SCENE_RUN_IN_PROGRESS` 与 D-022 的契约/文档漂移

- **位置**：`entry/src/main/ets/service/scene/SceneService.ets:156`；`ErrorCatalog` 按 `SCENE_` 前缀映射到 `errors.app.scene_run_in_progress`；DES-B §6.2 的场景错误表与 §23.4 的新增错误码表均未登记该码；`resources/rawfile/i18n/{zh-CN,en-US}.json` 尚未落地该键（C-14 未实现）。
- **D-022 漂移**：DES-B §3.3.3 仍把 `ACCEPTED` 画为终态、§3.1.3 仍写 `expireInvitations` 只处理 PENDING；修复按 D-022 实现但未更新 DES-B/Change Impact。
- **影响**：当前代码行为有 D-022 依据，但正式契约表/状态图/资源键未同步，后续实现者可能按旧图回归。建议由 Orchestrator 登记 Change Impact（DES-B §3.3.3/§3.1.3/§6.2/§23.4）并在 C-14/T-13 落地 i18n 键；这不改变本次代码结论，但不应被“已固定”表述掩盖。

### R2-05（Low）DeviceRepository 的进程内诊断缓存在事务回滚后不回滚

- **位置**：`DeviceRepository.ets:202,230,259,917-940`（`mergeStates`/`partialKeys` 在事务内修改）；`T09_C10_commitFailureEmitsNoDeviceEvent` 只断言 DB 回滚与 0 事件。
- **影响**：`failCommit` 后内存中可能残留 ADDED/partial 诊断，后续 `recordFromRow` 的 `isPartial` 诊断可能短暂不一致；持久事实仍以 DB 为准，属于 Low 诊断问题。建议在事务成功后再提交内存缓存，或在 catch 中恢复快照。

---

## 5. CQG-T09 检查项对照

| 检查项 | 结果 | 证据/说明 |
|---|---|---|
| build | **PASS（限可达图）** | `hvigorw clean assembleHap --no-daemon`：BUILD SUCCESSFUL，35 tasks；HAP 未签名，C-28 组合根未装配，不能证明全部新增模块进入 HAP 可达图。 |
| lint | **PASS** | `codelinter`：No defects，exit 0；首次并行运行有 transient “Some error occurred” 提示，随后单独复跑干净。 |
| host | **PASS** | `run-host-tests.sh`：243/243，0 fail；独立复跑与 TAP 一致。 |
| contract | **PARTIAL** | SSOT/仲裁、房间删除单事务、场景串行/局部失败/MISMATCH 回写、跨家庭 assign、owner 不变量、v4 静态迁移、D-022 不同回执均通过；**同一回执重放未拒绝（R2-01）**，`SCENE_RUN_IN_PROGRESS`/D-022 文档漂移（R2-04）。 |
| security | **PASS（秘密/平台边界）** | 新增产品代码未 import `@ohos`/网络/平台 API；日志仅含 gatewayId/deviceId/roomId/familyId/event 等非秘密值；未发现 secret/token/receipt 文本进入日志或异常；GUEST 房间限制仍明确为策略边界。 |
| layer | **PASS** | repository/service 仅依赖 ports/模型/工具；无平台 import，无 UI/ViewModel 反向依赖。 |
| i18n | **NOT_APPLICABLE / TRACKED** | 新增代码无硬编码用户可见文案；返回 `member.role.*`/`member.status.*`/`invite.mode.*` 等语义键。C-14 资源尚未落地；`errors.app.scene_run_in_progress` 等键待 C-14/T-13 补齐，CHK-01..09 未运行。 |
| review | **本报告；R-01..R-15 见 §3** | 上轮 High 4/4 已关闭；Medium 11/11 已处置，R-08 有登记限制；R-15 有 R2-01 覆盖缺口。 |
| device | **BLOCKED** | 无 `hdc`/模拟器/签名；`hvigorw test` 仅 `UnitTestArkTS` 编译，Previewer 超时；不得写成设备 PASS。 |
| trace | **部分** | C-08..C-11 的 host 用例名与 DES-B 条款在 §3 对应；R2-01/R2-04 尚未有对应测试/契约登记。 |
| **总体** | **不可授予 CQG-T09 PASS** | 代码级 build/lint/host 通过，但 contract 仍为 PARTIAL（R2-01）；设备 BLOCKED。C-08..C-11 继续保持 `UNVERIFIED`，不得标记 `STABLE`。 |

### 5.1 CQG-T09 最小必填证据（test-plan §4.3）对照

| 必填项 | 结果 |
|---|---|
| SSOT/仲裁 | PASS：`T09_C10_*`（陈旧包、同 epoch、缺字段、partial、tombstone、ACK stale/replay/mismatch） |
| 房间删除 | PASS：`T09_C09_deleteRoomIsOneTransaction...`、`...RollsBack...`、监听器隔离 |
| 场景局部失败 | PASS：首步/次步失败、`noRollbackNotice`、MISMATCH、取消、step/total timeout |
| 邀请/回执状态机 | **PARTIAL**：revoked/expired/mismatch、D-022 不同回执通过；同回执重放（R2-01）未拒绝 |

---

## 6. 回归与新增问题检查

1. **场景执行**：`activeSceneRuns` 单飞未与 `cancel`/`dispose` 形成死锁；`finally` 释放；释放后可再次运行（测试）。未发现重复命令路径。
2. **家庭状态机**：owner 不变量阻止降级/停用/移除，`transferAdmin` 仍可恢复可操作性；未发现 owner 悬空新路径。
3. **事务 gate**：同步/异步重入与 fake 嵌套均快速失败；但 R2-02 的 2000 ms 误拒是新增行为风险，R2-05 的诊断缓存不回滚是既存/残余问题。
4. **事件与监听器**：设备事件提交后派发；Room/Scene/SceneExecutor listener 异常隔离；commit 失败 0 事件。`FamilyJoinSession.setState` 的 listener 未隔离不属于 R-12 修复范围（既存；未发现本次回归）。
5. **范围**：修复 diff 未触碰 `service/storage/RdbTransactionRunner`、`pages/`、C-12/C-13/C-28；符合 T-09 写范围与 C-06 所有权。
6. **测试真实性**：新增用例均断言状态/副作用；未发现“只断言错误码”或把旧偏差固化为期望的情况（旧 `CONFIGURATION_ERROR` 期望已改为契约码）。R2-01 是遗漏，不是自证。

---

## 7. 裁决

**Verdict: CHANGES_REQUIRED**

理由：

1. **上轮 High 4/4 已关闭**：R-01（核心失败无残留成员）、R-02（同场景单飞）、R-03（MISMATCH 回写 SSOT）、R-04（T-09 边界内的同步/异步重入 fail-fast）均有代码与独立证据支持。
2. **Medium 11/11 已处置**：R-05..R-15 的修复与测试基本成立；R-08 的单网关 `RotationPlan` 属于已登记上游类型限制。
3. **但 R2-01（Medium）仍是未关闭的邀请状态机缺口**：同一 CODE_KEK 回执重放会耗尽 `usedCount` 而不产生新成员，违反 ADR-003 §5.4 / DES-B §3.4 的“重复回执拒绝”要求，且直接落在 CQG-T09 的“邀请/回执状态机”必填证据内。该问题不能由本报告或 Orchestrator 默示接受；需要修复或用书面裁定明确“同回执重放按一次 use 计数”的语义并登记。
4. **R2-02（Medium 设计风险）需要显式裁定**：2000 ms 有界等待不是只针对嵌套调用，可能误拒合法长队列；修复报告“正常串行行为不变”的表述不准确。必须在组合根/文档中明确并接受，或调整实现。
5. R2-03/R2-04/R2-05 为 Low，可在同一修复轮次顺带修正文档/契约/诊断缓存，不单独阻断。

**若 Orchestrator 选择书面接受 R2-01 与 R2-02**（并登记 Change Impact/跟踪项），本复审可降级为“PASS（代码级，条件式）”；但当前独立评审不替代该裁定，CQG-T09 仍不得被本报告标记为 PASS。设备/真实 RDB/Asset/Hypium 证据继续 `BLOCKED`，C-08..C-11 不得 `STABLE`。

---

## 8. 残余风险与跟踪项

| ID | 风险/跟踪项 | 建议 |
|---|---|---|
| T09-RV-01 | 真实 RDB/Preferences/Asset Store、迁移重启、真实事务回滚未执行 | 由设备/模拟器 owner 执行 `DomainDevice.test.ets` 或等价 IT；在此之前不得宣称 C-08..C-11 `STABLE`。 |
| T09-RV-02 | Hypium `hvigorw test` 在 Linux Previewer 无法启动；仅 `UnitTestArkTS` 编译 | 保持 `COMPILED_ONLY`；由设备/CI owner 执行。 |
| T09-RV-03 | C-13 容器/seed/回执实现未存在；R2-01 的真实 `verifyReceipt` 重放语义待 T-13 验证 | T-13 适配时验证同回执/跨存储补偿。 |
| T09-RV-04 | C-12 AuthService 未实现；profile/session fake | T-12 验证 owner 转移、leave/dissolve、session 失效真实语义。 |
| T09-RV-05 | C-15 云完成判定/`notBeforeMs` 未实现 | T-14 负责；R-17 Low 仍跟踪。 |
| T09-RV-06 | i18n 键未落地（`member.*`、`invite.*`、`errors.app.scene_run_in_progress` 等） | C-14 补齐 zh-CN/en-US 并保持 key parity。 |
| T09-RV-07 | 多网关 `RotationPlan` 单网关类型 | T-13/C-23 逐网关引导；T09-FIX-05。 |
| T09-RV-08 | `removeMember` 不清理 profile；`dissolveFamily` 不删 room/device/scene | C-22/C-13 集成测试确认无孤儿；必要时 Change Impact。 |
| T09-RV-09 | `FamilyService` actor 可选，依赖 C-12 调用点 RBAC | C-28/C-22 保证所有 UI 调用点传入 actor 或先校验 session。 |
| T09-RV-10 | `FamilyContactSyncState.STALE` 无产生路径；`FamilyChangeEvent` 未实现 | 由 C-22/T-15 决定；若 UI 依赖则补契约。 |
| T09-RV-11 | `listRecords` N+1 tombstone 查询/内存过滤 | C-21/C-25 前评估规模；必要时 SQL anti-join。 |
| T09-RV-12 | `entry/src/test/README.md` Producer/计数元数据 | 修正 T-09 计数与分类（R2-03）。 |
| T09-FIX-01/02 | 真实 RDB/Asset 与 Hypium | 同 T09-RV-01/02，保持 BLOCKED。 |
| T09-FIX-03 | C-06 `RdbTransactionRunner` 生产嵌套事务语义仍排队 | C-06/T-08 O-1 跟踪；T-09 仅以 `RdbTransaction` 类型隔离。 |
| T09-FIX-04 | `SCENE_RUN_IN_PROGRESS` 未登记/无资源键 | R2-04；C-14/T-13 或契约任务补齐。 |
| T09-FIX-05 | 多网关 `RotationPlan` | T-13/C-23。 |
| T09-FIX-06 | C-13 内部失败补偿 | T-13。 |
| T09-FIX-07 | 设备侧 `DomainDevice.test.ets` 未注册/未运行 | 保持 `COMPILED_ONLY`/`BLOCKED_ON_DEVICE_RUNNER`。 |
| T09-FIX-08 | i18n 键未落地 | C-14。 |
| R2-01 | 同回执重放消耗 use | 修复 + 用例，或书面裁定并登记。 |
| R2-02 | 2000 ms 合法队列误拒 | 组合根配置/文档/裁定；补合法长队列测试。 |
| R2-03 | 测试分类计数不一致 | 修正 README/修复报告。 |
| R2-04 | SCENE 错误码与 D-022 契约漂移 | Change Impact + C-14/T-13。 |
| R2-05 | 诊断缓存不回滚 | 事务成功后提交缓存或 catch 恢复。 |

---

## 9. 独立性与结论声明

本报告由 `agent:quality-reviewer` 独立完成，未参与 T-09 实现或 `wp-026-fix-t09` 修复，未修改被审代码、测试、证据、`artifacts/50-implementation/t09-domain.md` 或 `t09-fix-report.md`。本报告的唯一写入为 `artifacts/70-review/t09-review-b.md`。评审裁决仅针对 revision `621096b` 与 §1 范围，不覆盖 C-12/C-13/C-15/UI/组合根，也不授予 Stage Gate、CQG-T09 总体 PASS 或用户验收。

**Final Verdict: CHANGES_REQUIRED**

### 9.1 本次复验命令摘要

```text
entry/src/test/run-host-tests.sh
  -> 1..243 / # pass 243 / # fail 0 / exit 0

codelinter -c code-linter.json5 -p default .
  -> No defects found in your code. / exit 0
  -> 首次并行运行有 transient "Some error occurred during linting" 提示；单独复跑干净

hvigorw clean assembleHap --no-daemon
  -> BUILD SUCCESSFUL in 5 s 55 ms
  -> 35 tasks in total: 34 executed, 1 up-to-date / exit 0

git status --short
  -> clean
```

### 9.2 独立探针摘要

- `receipt_atomic_rollback`：`CONFIGURATION_ERROR`、`usedCount=0`、`status=PENDING`、`member_exists=false` → R-01 核心关闭。
- `replay_same_receipt`：`usedCount=2/2`、成员数 2、后续不同回执 `INVITE_MAX_USES` → R2-01。
- `gate_legit_queue`：默认 gate 下 2100 ms 首操作导致普通第二调用被 `CONFIGURATION_ERROR(nestedOperationOrQueueTimeout)` 拒绝 → R2-02。
- `production_runner_nested`：`RdbTransactionRunner` 嵌套事务 120 ms 未完成、`nestedSettled=false` → C-06/T09-FIX-03 残余。
