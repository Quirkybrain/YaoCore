# T-09 评审修复报告（R-01..R-15）

- **Artifact ID**: IMP-T09-FIX
- **Producer**: agent:implementation-engineer
- **Type**: Implementation / Verification Evidence
- **Status**: Proposed（本地构建/lint/host 测试通过；待独立复评与 CQG-T09 Gate）
- **Date**: 2026-10-17
- **Task**: `wp-026-fix-t09`（task 分支 `task/wp-024-domain`，父分支 `feat/yaocore-app`，base commit `207e7ada865a1f41f3fe310f4ae3f2f621bdcbf4`）
- **上游输入**: `artifacts/70-review/t09-review.md`（CHANGES_REQUIRED）、`IMP-T09-DOMAIN`、DES-A/DES-B、ADR-003、契约基线、Project Constraints、Test Plan、`state/project-state.md` D-022
- **Workflow**: STANDARD / GATED_AUTO
- **组件状态**: C-08..C-11 保持 `UNVERIFIED`；本报告不授予 `STABLE`、CQG-T09 或 Stage Gate

---

## 0. 摘要

| 项 | 结果 |
|---|---|
| 处置范围 | R-01..R-15 全部处置；High 4/4 Fixed，Medium 11/11 Fixed（其中 R-08 的 `RotationPlan` 单网关为已登记上游类型限制） |
| 新增/更新 Host 用例 | +27（216 → **243**），全部 PASS |
| `ohpm install` | PASS（exit 0） |
| `hvigorw clean assembleHap --no-daemon` | PASS（BUILD SUCCESSFUL，35 tasks） |
| `codelinter -c code-linter.json5 -p default .` | PASS（No defects found，exit 0） |
| `entry/src/test/run-host-tests.sh` | PASS（`1..243`、`# pass 243`、`# fail 0`，exit 0） |
| ArkTS 编译（附加） | `hvigorw test` 的 `UnitTestArkTS` 成功（9 s 456 ms）；Previewer 仍 BLOCKED（exit 124，环境限制，见 §4.5） |
| 真实 RDB/设备运行 | 仍 **BLOCKED**（无设备/模拟器；不因本次修复改变） |

---

## 1. 变更文件

产品代码（均在 T-09 写范围内）：

```text
entry/src/main/ets/repository/
├── DomainOperationGate.ets   # R-04：同步重入 fail-fast + 有界队列等待
├── DomainMigrations.ets      # R-06：v4 注册按 sink 幂等
├── FamilyRepository.ets      # R-01/R-09/R-10：回执单事务、owner 不变量、D-022
├── RoomRepository.ets        # R-06：静态 registerMigrations
├── DeviceRepository.ets      # R-06/R-07/R-12/R-13/R-14：家庭边界、事务后事件、路由事务外读取、partial
└── SceneRepository.ets       # R-06：静态 registerMigrations

entry/src/main/ets/service/
├── family/FamilyService.ets  # R-01/R-08/R-10/R-11：回执预校验、路由权威、D-022、邀请输入校验
├── room/RoomService.ets      # R-12：监听器异常隔离
└── scene/
    ├── SceneService.ets      # R-02/R-12：同场景单飞、监听器异常隔离
    └── SceneExecutor.ets     # R-03/R-05/R-12：MISMATCH 回写、超时步骤 FAILED、进度监听器隔离
```

测试与证据（`entry/src/test/**`）：

```text
host/DomainFamily.test.mjs   # 15 → 25 用例
host/DomainRoom.test.mjs     #  8 →  9 用例
host/DomainDevice.test.mjs   # 17 → 28 用例（含 O-1 负例）
host/DomainScene.test.mjs    # 10 → 15 用例
domain/DomainFakes.ets       # 认证 profile 清理记录、receipt inviteId 失配探针
domain/DomainHarness.ets     # 改为调用 Room/Device/Scene 三个静态 v4 注册
domain/DomainHost.test.ets   # 静态 registerMigrations 编译断言
storage/FakeStores.ets       # 嵌套事务在入队前 fail-fast；failCommit 注入
README.md                    # 243/243 与修复证据
evidence/t09-fix-*.log|tap   # 本次四条命令与编译证据
```

---

## 2. 逐条处置（R-01..R-15）

| ID | 严重度 | 处置 | 位置 | 关键实现 | 测试/证据 |
|---|---|---|---|---|---|
| R-01 | High | **Fixed** | `FamilyService.importReceipt`；`FamilyRepository.applyReceiptAndEnsureMember` / `applyReceiptInTransaction` | 在 `verifyReceipt`/成员写入前校验 `REVOKED`/`EXPIRED`/`expireAt <= now`/`usedCount >= maxUses`；`verification.inviteId` 必须匹配；回执更新与成员 upsert/激活在**同一仓库事务**内，失败整体回滚。REVOKED/EXPIRED/超限路径不产生成员行。重复回执按 DES-B §3.2“用尽”映射 `INVITE_MAX_USES`（KEY_WRAP maxUses=1），非 `CONFIGURATION_ERROR`；CODE_KEK 的多次回执语义见 R-10/D-022。 | `T09_C08_revokedReceiptLeavesNoActiveMember`、`T09_C08_expiredReceiptLeavesNoActiveMember`、`T09_C08_receiptInviteMismatchIsRejectedBeforeMemberWrite`；旧回执用例改为断言 `INVITE_MAX_USES` 且成员数不变 |
| R-02 | High | **Fixed** | `SceneService.run` / `dispose` | 新增 `activeSceneRuns: sceneId → runId`；同场景第二次 `run` 在任何命令下发前返回 `SCENE_RUN_IN_PROGRESS`；`finally` 释放 | `T09_C11_sameSceneConcurrentRunIsRejectedAndNeverDoubleDispatches`：首 run 阻塞在 `send`，第二 run 拒绝，释放后命令数 2（非 4），完成后可再次运行 |
| R-03 | High | **Fixed** | `SceneExecutor.execute` 失败路径 | `outcome.ackAccepted` 且步骤失败（含 `MISMATCH`）时，先 `applyControlAck` 把网关 `reportedState` 写回 SSOT，再 `failAt`；步骤仍标 FAILED 并保留 `stateVerification` | `T09_C11_mismatchWritesGatewayTruthToSsot`：MISMATCH → `FAILED`，步骤 `stateVerification=MISMATCH`，`snapshot.powerStatus=true` |
| R-04 | High | **Fixed** | `DomainOperationGate`；`entry/src/test/storage/FakeStores.ets` | ① 同步重入（`operation()` 首次同步执行窗口内再次 `run`）立即返回 `CONFIGURATION_ERROR(field=nestedGateOperation)`；② 异步重入无法与普通排队区分（ArkTS 无 async-context），改为每操作 **有界队列等待（默认 2000 ms，可构造注入）**，超时返回 `CONFIGURATION_ERROR(field=nestedOperationOrQueueTimeout)` 且排队体不再执行，避免 O-1 死锁挂起；③ fake `transaction()` 在入队前检查 `inTransaction`，嵌套事务立即 `STORAGE_RDB_ERROR` | `T09_O1_gateRejectsSynchronousNestedRun`、`T09_O1_gateRejectsAsyncReentrantCallInsteadOfHanging`、`T09_O1_nestedFakeTransactionFailsFast`（均带超时包装）、`T09_O1_gateSerializesOperations`（串行保持） |
| R-05 | Medium | **Fixed** | `SceneExecutor.failAt` | `failedIndex` 仍为 `PENDING` 时置 `FAILED`（总超时发生在步骤进入 RUNNING 之前）；后续步骤仍 SKIPPED | `T09_C11_totalTimeoutMarksTheBlockedStepFailedNotPending`：`steps[1]=FAILED`，命令仅 1 条 |
| R-06 | Medium | **Fixed** | `RoomRepository`/`DeviceRepository`/`SceneRepository` 静态 `registerMigrations`；`DomainMigrations.register` | 三个组件各自暴露 DES-B 静态入口并委托 `DomainMigrations`；v4 是同一 schema 版本，注册按 `MigrationSink` 实例幂等，组合根可调用任意/全部而不会重复版本失败；非规范重复 v4 注册仍由 `MigrationRegistry` 拒绝 | `T09_C09_v4StaticRegistrationIsDelegatedAndIdempotent`；`DomainHarness` 实际通过三个静态入口完成 v1..v4 迁移；`DomainHost.test.ets` 编译断言 |
| R-07 | Medium | **Fixed** | `DeviceRepository.assignRoom` | 端口层直接比较 `room.familyId === familyId`，不匹配返回 `ROOM_NOT_FOUND`（不再依赖 `RoomService` 的分层检查） | `T09_C10_assignRoomRejectsRoomFromAnotherFamily`：跨家庭 assign 拒绝，设备仍在未分配池 |
| R-08 | Medium | **Fixed（单计划类型为已登记限制）** | `FamilyService.dissolveFamily` / `leaveFamily` / `gatewayIdsForFamily` | `dissolveFamily` 以 `routes.listRoutesByFamily` 为权威，并与家族行 `gateway_ids_json` 合并去重；`leaveFamily` 返回完整网关列表；`FamilyDissolutionPlan.gatewayIds` 不再只取首个/仅家族行。`RemoveMemberResult`/`ExpireGuestsResult` 的 `RotationPlan` 类型只承载单网关（DES-B §3.1.3），保留确定性首个计划，多网关逐网关引导登记给 T-13/C-23 | `T09_C08_dissolveUsesRouteAuthorityAndReturnsEveryGateway`（两路由 + 陈旧家族行）、`T09_C08_leaveFamilyReturnsEveryBoundGatewayAndRemovesProfile` |
| R-09 | Medium | **Fixed** | `FamilyRepository.updateMemberRole` / `updateMemberStatus` / `upsertMemberInTransaction` / `removeMemberInTransaction` | 禁止降级/停用/移除 `family.owner_member_id` 指向的成员，除非先 `transferAdmin`；owner 必须保持 ACTIVE ADMIN，避免 owner 指针悬空且无法转让 | `T09_C08_ownerCannotBeDemotedOrRemovedAndTransferRemainsPossible`：降级/移除/停用均 `AUTH_RBAC_DENIED`，指针不变，随后 `transferAdmin` 成功且旧 owner 可移除 |
| R-10 | Medium | **Fixed（D-022）** | `FamilyRepository.applyReceiptInTransaction`；`FamilyService.revokeInvitation` / `expireInvitations` | `ACCEPTED` 不是终态：`usedCount < maxUses` 且未过期可继续回执；每次回执记录 `acceptedAt/acceptedBy/receipt` 并 `usedCount++`；达到 maxUses → `INVITE_MAX_USES`；过期回执 → `INVITE_EXPIRED`；ACCEPTED 且未用尽仍可撤销/过期 | `T09_C08_codeKekMultipleReceiptsFollowD022`（maxUses=2 两次成功、第三次 `INVITE_MAX_USES`、无第三成员）、`T09_C08_acceptedCodeKekCanStillBeRevokedWhileUsesRemain`、`T09_C08_expiredReceiptLeavesNoActiveMember` |
| R-11 | Medium | **Fixed** | `FamilyService.validateInvitationInput`；`createInvitationForJoinRequest` / `createCodeInvitation` | 在调用 C-13 前校验：`targetRole∈{MEMBER,GUEST}`（ADMIN → `PROTOCOL_VALUE_OUT_OF_RANGE`）、GUEST 至少一个房间、房间 UUID、`ttlMs>0`、CODE_KEK `maxUses≥1`、mode 匹配；校验失败不调用 `InviteServicePort`，因此不产生 seed alias 等副作用。C-13 内部创建失败后的跨存储补偿仍归 T-13 | `T09_C08_invitationValidationNegativeCases`（含 `h.invites.createRequests` 零增量断言） |
| R-12 | Medium | **Fixed** | `DeviceRepository`（collect + post-commit dispatch）；`RoomService.emit`；`SceneService.run/emit`；`SceneExecutor.emit` | 设备事件先在事务内收集，提交成功后统一派发；监听器异常逐订阅者隔离并记录诊断，不改变已提交事实/执行结果；`applyDiscoverInTransaction` 的 catch 不再可能把监听器异常当作 `INVALID_DEVICE` | `T09_C10_throwingListenerDoesNotAbortDiscover`、`T09_C10_commitFailureEmitsNoDeviceEvent`（`failCommit` 注入，0 事件 + 回滚）、`T09_C09_throwingListenerDoesNotFailRoomDeletion`、`T09_C11_throwingProgressAndEventListenersDoNotFailRun` |
| R-13 | Medium | **Fixed** | `DeviceRepository.removeDevicesForGateway` | `GatewayRoutePort.getRoute` 在 `rdb.transaction` 之前读取；事务回调内只访问 `tx`；设备行家族仍从 `tx` 读取并合并去重 | `T09_C10_removeDevicesForGatewayReadsRouteOutsideTransaction`：包装路由端口断言读取时 `isInTransactionForTest()===false`，并验证 2 台设备与场景引用清理 |
| R-14 | Medium | **Fixed** | `DeviceRepository.applyDiscoverInTransaction` | 结果 `partial = snapshot.isPartial \|\| invalidDropped > 0`；`invalidDropped > 0` 时不推断 `gateway_removed`，避免部分无效快照误标其他设备 | `T09_C10_duplicateAndFamilyMismatchDevicesSetPartial`：重复/家庭不匹配 → `partial=true`、`invalidDropped=1`、`gatewayRemovedMarked=0` |
| R-15 | Medium | **Fixed** | `entry/src/test/host/DomainFamily|Room|Device|Scene.test.mjs` | 补齐评审清单：`removeMember` 成功+session 失效、`changeMemberRole` 成功、`leaveFamily` profile 清理、未绑定/家庭不匹配/重复 discover、`DeviceCommandRunner` UNASSIGNED、same-scene 并发、step/total timeout + 迟到 outcome、O-1 嵌套负例、owner 降级/移除、revoked/expired receipt | 新增 27 用例，216 → 243 全 PASS（`evidence/t09-fix-host-node-tests.tap`） |

---

## 3. 契约与实现细化

1. **`SCENE_RUN_IN_PROGRESS`（新增 SCENE_* 码）**：用于同场景并发 `run` 的明确拒绝（R-02）。`ErrorCatalog` 按 `SCENE_` 前缀自动解析 i18n key `errors.app.scene_run_in_progress`；DES-B §23 的正式登记/文案由下游契约维护任务补齐。若上游选择“返回现有 run”语义，可在 T-13/C-28 适配，当前实现选择**拒绝且不下发命令**，满足“绝不重复下发”。
2. **O-1 有界等待（2000 ms 默认）**：ArkTS 无 async-context，无法在异步重入后区分“同一操作的重入”与“独立并发调用”。因此保留串行队列语义，并增加同步重入即时拒绝 + 异步重入有界失败；默认值可由组合根 `new DomainOperationGate(ms)` 覆盖。这是对“排队/挂起”死锁的确定性防护，不改变正常串行行为（`T09_O1_gateSerializesOperations` 保持通过）。
3. **C-06 生产事务运行器**：本次未修改 `service/storage/RdbTransactionRunner`（C-06 所有权；T-08 O-1 已登记）。T-09 自身通过 `RdbTransaction` 类型隔离禁止嵌套事务，host fake 已改为入队前 fail-fast；真实 RDB 下 C-06 的嵌套/并发事务策略仍需 T-08/CQG 跟踪。
4. **v4 静态注册**：DES-B 将 v4 定义为单一 schema 版本，但 §4/§5/§6 各自要求组件静态 `registerMigrations`。实现采用“组件入口 + 按 sink 幂等的集中 v4 注册”，避免拆分版本或重复版本错误；组合根调用任意子集均可。
5. **多网关轮换计划**：`FamilyDissolutionPlan.gatewayIds` 返回完整列表；`RemoveMemberResult`/`ExpireGuestsResult` 的 `RotationPlan` 仍为单网关类型（DES-B §3.1.3），逐网关引导登记 T-13/C-23。
6. **邀请失败补偿**：C-08 在调用 C-13 前完成全部输入校验；若 C-13 的 `createInvitation`/`verifyReceipt` 在内部失败，seed alias/容器临时状态由 T-13 负责补偿（T09-RV-03）。
7. **i18n**：本次未新增用户可见文案；新增错误码走既有 `errors.app.*` 映射。

---

## 4. 验证命令与结果（本次实际执行）

### 4.1 `ohpm install`

```text
$ ohpm install
install completed in 0s 47ms
exit=0
```

证据：`entry/src/test/evidence/t09-fix-ohpm-install.log`。

### 4.2 `hvigorw clean assembleHap --no-daemon`

```text
BUILD SUCCESSFUL in 6 s 621 ms
35 tasks in total: 34 executed, 1 up-to-date
exit=0
```

证据：`entry/src/test/evidence/t09-fix-clean-assemble.log`。说明：HAP 默认可达图仍由 `pages/Index` 驱动，C-28 组合根尚未装配本任务模块；新增模块的 ArkTS 编译由 §4.5 的 `UnitTestArkTS` 覆盖。

### 4.3 `codelinter -c code-linter.json5 -p default .`

```text
No defects found in your code.
exit=0
```

证据：`entry/src/test/evidence/t09-fix-codelinter.log`（产品源码；`code-linter.json5` 不含 `src/test/**`）。

### 4.4 `entry/src/test/run-host-tests.sh`

```text
1..243
# tests 243
# pass 243
# fail 0
exit=0
```

证据：`entry/src/test/evidence/t09-fix-host-node-tests.tap`。相较 T-09 初版 216 增加 27 个用例。

### 4.5 `hvigorw test --no-daemon`（附加编译证据）

```text
Finished :entry:default@UnitTestArkTS... after 9 s 456 ms
（随后 Linux Previewer 启动失败/等待，120s 超时 exit=124）
```

证据：`entry/src/test/evidence/t09-fix-hvigor-test-compile.log`。**仅证明 ArkTS 编译**（`DomainHost.test.ets` 拉入全部新增模块），不是 Hypium 执行 PASS；设备/Previewer 限制未改变。

### 4.6 Git 复验

```text
git diff --cached --check
（无输出，exit=0）
```

---

## 5. 未决项与残余风险

| ID | 项 | 状态/归属 |
|---|---|---|
| T09-FIX-01 | 真实 RDB/Preferences/Asset Store 运行、迁移重启、真实事务回滚 | **BLOCKED**（无设备/模拟器）；T09-RV-01 不变 |
| T09-FIX-02 | Hypium `hvigorw test` 执行 | **BLOCKED**（Linux Previewer 不支持）；T09-RV-02 不变，保持 `COMPILED_ONLY` |
| T09-FIX-03 | C-06 `RdbTransactionRunner` 的生产嵌套事务语义 | 仍归 C-06/T-08 O-1 跟踪；T-09 仅在自身边界内保证不嵌套并使用 tx-context |
| T09-FIX-04 | `SCENE_RUN_IN_PROGRESS` 的 DES-B §23 正式登记/文案 | 下游契约维护（T-13/C-28 或评审裁定） |
| T09-FIX-05 | 多网关 `RotationPlan`（`RemoveMemberResult`/`ExpireGuestsResult`） | 上游类型为单网关；逐网关引导归 T-13/C-23 |
| T09-FIX-06 | C-13 内部失败（seed alias/临时容器）补偿 | T-13 负责；C-08 已保证调用前零副作用 |
| T09-FIX-07 | 设备侧 `DomainDevice.test.ets` 未注册/未运行 | 保持 `COMPILED_ONLY`/`BLOCKED_ON_DEVICE_RUNNER` |
| T09-FIX-08 | i18n 键 `member.role.*`/`member.status.*`/`invite.mode.*` 资源未落地 | C-14（T09-RV-06 不变） |

---

## 6. 追溯

| 源 | 修复/证据 |
|---|---|
| REVIEW-T09 R-01..R-04（High） | §2 四行；新增用例见 §4.4 TAP |
| REVIEW-T09 R-05..R-15（Medium） | §2 十一行；全部 Fixed（R-08 单计划类型已登记限制） |
| D-022（邀请 maxUses） | `T09_C08_codeKekMultipleReceiptsFollowD022`、`T09_C08_acceptedCodeKekCanStillBeRevokedWhileUsesRemain` |
| DES-B §2.6/§2.8（事件/O-1） | 事务后派发、监听器隔离；gate 负例 |
| DES-B §3.1.3/§3.3.1/§3.3.3/§3.3.6 | 回执单事务、owner 不变量、D-022、路由权威 |
| DES-B §5.3.2/§5.3.4/§6.1.4/§6.3 | MISMATCH 回写、家庭边界、same-scene 单飞、超时步骤状态 |

---

## 7. 结论

R-01..R-15 已全部处置，四条必需命令与附加 ArkTS 编译证据均通过（host 243/243）。C-08..C-11 仍为 `UNVERIFIED`，等待独立复评确认 High 项关闭后再进入 CQG-T09；真实 RDB/设备/Previewer 证据继续 `BLOCKED`。
