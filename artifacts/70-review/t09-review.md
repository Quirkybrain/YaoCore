# T-09 独立代码评审报告（C-08..C-11 领域仓储与服务）

- **Artifact ID**: REVIEW-T09-DOMAIN
- **Producer**: agent:quality-reviewer
- **Type**: Independent Code Review
- **Status**: CHANGES_REQUIRED（本报告不授予 `STABLE`，不作为 CQG-T09 / Stage Gate 的通过证据）
- **Date**: 2026-10-17
- **Task**: `wp-025-review-t09` / 被审任务 `wp-024-domain`（task 分支 `task/wp-024-domain`，父分支 `feat/yaocore-app`）
- **Reviewed Revision**: `5e110db71b800e99da1ccbe2331b422f48843ec0`（`feat(domain): 实现家庭房间设备与场景仓储服务`）
- **Base Revision**: `57f64d45c7442289db489df4cb6e62816815c43c`
- **Workflow**: STANDARD / GATED_AUTO
- **评审方式**: 只读代码审查 + 只读复验；未修改被审代码、测试或实现报告。唯一写入为本报告。
- **独立性声明**: 被审实现的 Producer 为 `agent:implementation-engineer`；本评审由未参与该实现的 `agent:quality-reviewer` 执行。作者未参与本报告的裁决。

---

## 1. 评审范围与排除

### 1.1 范围内

| 类别 | 路径/内容 |
|---|---|
| 仓储 | `entry/src/main/ets/repository/`（10 个新增文件：Family/Room/Device/Scene、DomainModels、DomainPorts、DomainMigrations、DomainOperationGate、DeviceSnapshotCodec、SqlCells） |
| 服务 | `entry/src/main/ets/service/family/`、`room/`、`device/`、`scene/`（10 个新增文件） |
| Host 测试与证据 | `entry/src/test/host/`、`entry/src/test/domain/`、`entry/src/test/evidence/t09-*`、`entry/src/test/storage/FakeStores.ets`、`entry/src/test/List.test.ets`、`entry/src/test/README.md` |
| 设备侧骨架 | `entry/src/ohosTest/ets/test/domain/DomainDevice.test.ets` |
| 实现报告 | `artifacts/50-implementation/t09-domain.md` |

`git diff --name-status 57f64d45..5e110db` 共 39 个路径；全部落在 T-09 的 repository/service/test/implementation 写范围或声明的测试支撑文件内。未发现产品源码范围外修改、构建产物、HAP、证书、密钥或 `.hvigor` 内容入库。

### 1.2 输入完整性

6 个 pinned input 的 sha256 与 handoff `state/handoffs/wp-025-review-t09.json` 一致；评审目标在 dispatch 前已有 Git snapshot（`refs/swe/snapshots/20261017T101330Z-wp-025-review-t09-e087704d`）。评审期间未修改任何 protected snapshot 路径。

### 1.3 排除/未覆盖

- 真实 HarmonyOS RDB、Preferences、Asset Store 的设备运行（无 `hdc` target、无签名、无模拟器；与实现报告一致，标记 `BLOCKED`）。
- `hvigorw test` 的 Hypium 实际执行（Linux Previewer 限制；仅编译证据，不作为测试 PASS）。
- UI/ViewModel（T-15/T-16）、C-12 AuthService、C-13 InviteService、C-15 CloudService、C-28 组合根的最终装配；仅评审 T-09 提供的端口边界与调用语义。
- HAP 默认可达图：现有 `pages/Index` 尚未装配 C-28 组合根，`assembleHap` 不会把全部新增模块拉入可达图；新增模块的编译证据来自实现报告的 `hvigorw test` UnitTestArkTS / ohosTest compile probe。
- 真实网关/设备 ACK 与场景时延（无真实设备）。

---

## 2. 复验结果（本次评审独立执行）

| 命令 | 结果 | 说明 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS**，`1..216`、`# pass 216`、`# fail 0`，exit 0 | 本次复跑；新增 T-09 用例共 50（C-08 15、C-09 8、C-10 16、O-1 1、C-11 10；C-10 与 O-1 合计 17）。 |
| `codelinter -c code-linter.json5 -p default .` | **PASS**，`No defects found in your code.`，exit 0 | 产品源码静态检查；`code-linter.json5` 忽略 `src/test/**` 与 `src/ohosTest/**`，故该结果不覆盖新增测试源码。 |
| `hvigorw clean assembleHap --no-daemon` | **PASS**，`BUILD SUCCESSFUL in 5 s 386 ms`，`35 tasks in total: 34 executed, 1 up-to-date`，exit 0 | 仅证明当前 HAP 默认可达图可构建；新增领域模块未全部进入该图（见 §1.3）。 |
| `git status --short`（复验后） | clean | 构建产物被 `.gitignore` 忽略；评审未产生未声明仓库改动。 |

已核对实现报告证据：`t09-host-node-tests.tap` 的 216/216、`t09-codelinter.log`、`t09-clean-assemble.log` 与本次复跑结果一致。`t09-hvigor-test-compile.log` 的 `UnitTestArkTS` 编译成功、Previewer 超时 exit 124，以及 `t09-ohosTest-compile-probe.log` 的编译成功，均按实现报告所述保留为附加证据，不当作设备执行 PASS。

---

## 3. 裁决

**Verdict: CHANGES_REQUIRED**

C-08..C-11 的主体结构、SSOT 仲裁、房间删除单事务、场景串行/局部失败/取消、共享 gate 串行化和安全边界总体方向正确，Host 216/216 与静态检查通过。但存在必须修复的**状态一致性与契约偏差**，尤其是：

1. 回执导入在邀请状态校验之前创建/激活成员，失败路径会留下 ACTIVE 成员；
2. 同一场景允许并发 `run`，可重复下发命令；
3. `MISMATCH` 的 ACK 状态未写入 SSOT，违反仲裁规则；
4. O-1“禁止嵌套事务”的验证证据不成立，重入只排队而非 fail-fast。

因此本 revision 不能标记 `STABLE`，也不满足 CQG-T09 的独立评审通过条件。

---

## 4. Findings

严重度定义：**High** = 必须在 CQG-T09 前修复；**Medium** = 应在 Gate 前修复，或由 Orchestrator 书面接受并登记 Change Impact/跟踪项；**Low** = 建议改进或残余风险。以下所有位置均指被审 revision `5e110db`。

| ID | 严重度 | 位置 | 契约引用 | 问题与影响 | 建议 |
|---|---|---|---|---|---|
| R-01 | **High** | `service/family/FamilyService.ets:380-407`；`repository/FamilyRepository.ets:695-724` | DES-B §3.1.3 `importReceipt`；§3.3.3 邀请状态机；§3.2 `INVITE_RECEIPT_INVALID` | `importReceipt` 先创建/激活成员，随后才由 `applyReceipt` 检查邀请状态。对 REVOKED/EXPIRED 邀请，导入仍会留下 ACTIVE 成员；对 ACCEPTED/超限邀请同样可能先改成员再失败。评审只读探针复现：`revoked_error=INVITE_REVOKED member_after=ACTIVE`。 | 在成员写入前校验 `PENDING`、`expireAt > now`、`usedCount < maxUses`、`verification.inviteId === inviteId`；把成员 upsert/状态更新与 `applyReceipt` 放入同一事务；重复回执映射 `INVITE_RECEIPT_INVALID`；补 REVOKED/EXPIRED/重复且成员不存在的测试。 |
| R-02 | **High** | `service/scene/SceneService.ets:67,140-190` | DES-B §6.1.4 方法语义第 7 条（同一场景同一时间只允许一个 run） | `runs` 只按 `runId` 索引，没有 `sceneId` 单飞检查。评审探针并发调用两次 `run(sceneId)`：`same_scene_states=SUCCEEDED,SUCCEEDED commands=2`；同一场景命令被重复执行。 | 增加 `activeRunByScene` 或在 `runs` 中按 scene 检查；重复调用应返回明确错误（或返回现有 run），不得双发；补并发测试。 |
| R-03 | **High** | `service/scene/SceneExecutor.ets:161-183`；`255-268` | DES-B §5.3.2 规则 6（MISMATCH 仍应用 reportedState）；§6.3.3 | `SceneExecutor` 仅在成功路径调用 `applyAckBestEffort`。`stateVerification=MISMATCH` 时把步骤标 FAILED 并直接 `failAt`，未应用网关真值；评审探针：`mismatch_state=FAILED snapshot_power=undefined`，SSOT 未回写。 | MISMATCH 属于执行失败但仍是网关真值：在 `failAt` 前调用 `applyControlAck`（或始终对含 `reportedState` 的 outcome 应用状态），保留 `stateVerification`；补“步骤失败 + SSOT 更新”测试。 |
| R-04 | **High** | `repository/DomainOperationGate.ets:22-35`；`entry/src/test/storage/FakeStores.ets:161-210`；`implementation/t09-domain.md` §3 | O-1（CQG-T08 带入）；DES-B §2.8；DES-A §9.1.2 | 目前只证明“串行”，没有证明“禁止嵌套”。`DomainOperationGate.run` 重入会排队等待当前操作；fake `InMemoryRdbStore.transaction` 的 `inTransaction` 检查在链内，嵌套调用会等待当前事务完成而不是抛出；`T09_O1_gateSerializesOperations` 只覆盖串行。实现报告“fake RDB 遇到嵌套直接抛”的断言不成立。 | 在调度前增加 active/reentrancy fail-fast 检查，或用显式 `RdbTransaction` 类型/上下文隔离防止嵌套；新增带超时的“嵌套 transaction / 嵌套 gate 不得挂起”负例；修正报告证据表述。当前代码未发现实际嵌套调用，但 Gate 不应接受未证明的约束。 |
| R-05 | Medium | `service/scene/SceneExecutor.ets:128-133,196-207` | DES-B §6.1.1 `SceneStepState`；§6.3.1 | `totalTimeoutMs` 超时时 `failAt` 只把 `failedIndex+1..` 标 SKIPPED，未把 `failedIndex` 本身标 FAILED，步骤停在 PENDING；评审探针：`total_timeout_state=FAILED step0=PENDING failedIndex=0`。进度 UI 会把失败步骤显示为未执行。 | 在 `failAt` 中把 `failedIndex` 标 FAILED（或在超时分支先设置），补 total timeout 测试。 |
| R-06 | Medium | `repository/RoomRepository.ets:26-48`；`repository/DeviceRepository.ets:60-94`；`repository/SceneRepository.ets:34-56` | DES-B §2.5（`MigrationSink` 静态 `registerMigrations`）；§4.1.2、§5.1.3、§6.1.3 | 三个仓储都缺少契约声明的静态 `registerMigrations`；v4 仅由 `DomainMigrations` 集中注册。若 C-28 按 DES-B §2.5/§4-§6 调用组件静态方法，会出现接口缺失；与实现报告 §6 的“位置例外”不是同一类问题。 | 为 Room/Device/Scene 增加静态 `registerMigrations`（委托 `DomainMigrations` 或拆分各自 DDL），或走 Change Impact 明确修改组合根契约并更新 DES-B/实现报告；补注册/重复版本测试。 |
| R-07 | Medium | `repository/DeviceRepository.ets:516-533` | DES-B §4.1.1 `DeviceAssignmentPort`；§5.3.4 `assignRoom`；DP-01/§4.3.1 家庭边界 | `assignRoom` 只校验房间存在，不校验 `room.familyId === familyId`。评审探针直接调用端口即可把家庭 A 的设备写入家庭 B 的房间：`assign_cross_family_error=none device_room=<roomB>`。`RoomService.assignDevice` 的分层检查不能保护其他端口调用者。 | 在 `DeviceRepository.assignRoom` 内比较 `room.familyId`，不匹配返回 `ROOM_NOT_FOUND`/`CONFIGURATION_ERROR`；补跨家庭负例。 |
| R-08 | Medium | `service/family/FamilyService.ets:139-165,474-488`；`repository/FamilyRepository.ets:608-621` | DES-B §3.1.3 `dissolveFamily`（`gatewayIds` 来自 `routes.listRoutesByFamily`）；§3.3.6；`FamilyDissolutionPlan.gatewayIds` 数组 | `dissolveFamily` 的 `gatewayIds` 取自 `removeFamilyLocal` 返回的 `family.gateway_ids_json`，不是 `routes.listRoutesByFamily`；`rotationPlanForFamily` 只取 `routes[0]`，`leaveFamily` 最多返回一个网关。路由与家庭行不一致或多网关时，轮换/解绑引导不完整。现有 `T09_C08_dissolveFamily...` 只用 family 行、未建立 route，等于把偏差固化为期望。 | `dissolveFamily` 以 route 列表为权威（必要时与 family 行合并去重）；多网关返回完整 `gatewayIds`/逐网关引导，或登记明确的上游限制（T-13/C-23）；补 route/family 不一致和多网关测试。 |
| R-09 | Medium | `repository/FamilyRepository.ets:351-374,747-757`；`service/family/FamilyService.ets:222-303` | DES-B §3.3.1 家庭生命周期；§3.3.6 转让/退出；`Family.ownerMemberId` 语义 | 当存在第二个 ADMIN 时，`updateMemberRole`/`removeMember` 可以降级或移除 `family.owner_member_id` 指向的成员，但不会更新 owner 指针；`transferAdmin` 又要求 current 必须等于 owner 且为 ACTIVE ADMIN。评审探针：`owner_role=MEMBER owner_pointer=true transfer_after_owner_demotion=AUTH_RBAC_DENIED`，家庭会卡在无法转让的状态。 | 禁止降级/移除 owner，除非在同一事务内先完成 owner 转移；或自动把 owner 转给另一 ACTIVE ADMIN；补 owner 相关负例。 |
| R-10 | Medium | `repository/FamilyRepository.ets:695-724`；`service/family/FamilyService.ets:334-345` | DES-B §3.1.3/§3.3.3 CODE_KEK `maxUses>=1`；`InvitationView.usesRemaining` | `createCodeInvitation` 接受 `maxUses>1` 并显示剩余次数，但 `applyReceiptInTransaction` 第一次就写 `ACCEPTED`，之后任何回执都因 `ACCEPTED` 被拒。评审探针：`maxUses=2` 时第二次导入 `second_receipt_error=CONFIGURATION_ERROR used=1/2 status=ACCEPTED`。DES-B 状态图把 ACCEPTED 画为终态，与 CODE_KEK 多次使用存在上游矛盾。 | 请 requirements/architecture 裁定：要么允许 `ACCEPTED + usedCount<maxUses` 的后续回执，要么限制 CODE_KEK `maxUses=1` 并修改契约/文案；当前实现不能同时满足 `maxUses>1` 与可再次导入。 |
| R-11 | Medium | `service/family/FamilyService.ets:316-345`；`repository/FamilyRepository.ets:789-803`；`test/host/DomainFamily.test.mjs:217-232` | DES-B §3.2（targetRole=ADMIN → `PROTOCOL_VALUE_OUT_OF_RANGE`）；§3.1.3；DES-A §11.2 | C-08 在调用 C-13 前没有校验 `targetRole`、GUEST 的 `allowedRoomIds`、`ttlMs`/`maxUses`；无效角色/空房间由 `InvitationRecord` 构造器抛出 `CONFIGURATION_ERROR`，与契约错误码不符，且 C-13 可能在拒绝前已产生 seed alias 等副作用。测试 `T09_C08_invitationValidationNegativeCases` 明确断言 `CONFIGURATION_ERROR`，固化了该偏差。 | 在 C-08 调用端口前完成输入校验，按契约映射 `PROTOCOL_VALUE_OUT_OF_RANGE`/`PROTOCOL_INVALID_IDENTIFIER`，再调用 C-13；更新测试期望；明确失败后的跨存储补偿责任。 |
| R-12 | Medium | `repository/DeviceRepository.ets:191,250-251,285,369,589,906-910`；`service/scene/SceneExecutor.ets:97-119,274-283`；`service/room/RoomService.ets:193-199,243-247` | DES-B §2.6（事件是通知，不是事实源；订阅者不得泄漏）；§2.8 | 设备事件在 `rdb.transaction` 回调内 emit；若 commit 失败，监听器已收到回滚前事件。`applyDiscoverInTransaction` 的 catch 还会把监听器抛出的异常当作 `INVALID_DEVICE`，导致“已写入但计数为 invalid”的不一致。Room/Scene 的监听器直接调用，监听器抛错会让已成功的事务/执行对调用方表现为失败。 | 在事务成功后统一派发事件；隔离监听器异常（记录诊断但不改变事实结果）；补“监听器抛错 / commit 失败”测试。 |
| R-13 | Medium | `repository/DeviceRepository.ets:619-655` | O-1；DES-B §2.8；§5.3.4 `removeDevicesForGateway` | `removeDevicesForGateway` 在已打开的 `rdb.transaction` 内调用 `routes.getRoute`；`GatewayRoutePort` 不是 tx-context 端口，生产实现会通过 `RdbStore` 直接读，绕过当前事务。注入 fake 时测试无法暴露该边界。 | 在事务外先读取 route/family 列表，或扩展 tx-aware route 端口；保证事务内只访问 `tx`。补“removeDevicesForGateway + 真实路由端口”测试。 |
| R-14 | Medium | `repository/DeviceRepository.ets:252-260,289-290` | DES-B §5.3.3（设备级跳过/字段缺失 → isPartial）；§5.2 | `partial` 结果只回传 `snapshot.isPartial`，仓库自身因重复 deviceId、家庭不匹配、解码失败等增加的 `invalidDropped` 不置 partial，也不阻止 full snapshot 的 missing 标记。诊断/部分快照语义不完整。 | `partial = snapshot.isPartial || invalidDropped > 0`（至少对重复/解码失败），或为每类偏差单独定义；补 duplicate/family mismatch/invalid 设备测试。 |
| R-15 | Medium | `test/host/DomainFamily.test.mjs`、`DomainDevice.test.mjs`、`DomainScene.test.mjs`、`DomainRoom.test.mjs` | DES-B §3.4、§5.4、§6.4 host 测试清单；§2.8 O-1 | 50 个新增用例覆盖了核心仲裁/删除事务/场景串行与取消，但缺少：`removeMember` 成功 + `invalidateSessionsForMember`、`changeMemberRole` 成功、`leaveFamily` profile 清理、unbound gateway/family mismatch/duplicate discover、DeviceCommandRunner 的 UNASSIGNED 分支、same-scene 并发、step/total timeout 与迟到 outcome、O-1 嵌套负例、owner 降级/移除、revoked/expired receipt。现有 216/216 不能证明这些契约路径。 | 为上述路径补 host 用例；测试断言应覆盖状态/副作用，而不仅是错误码；设备端骨架继续保持 `COMPILED_ONLY` 声明。 |
| R-16 | Low | `repository/DeviceRepository.ets:73-83,104-113` | DES-B §5.3.3（未绑定网关忽略整份 discover） | `routes` 为可选注入；未注入时 `applyDiscoverSnapshot` 不检查网关是否绑定，会纳管未绑定网关的设备。当前 Host harness 总是注入，生产组合根若遗漏则边界失效。 | 将 `GatewayRoutePort` 设为必需，或在缺失时 fail-closed（返回空结果/偏差），并在组合根测试中验证。 |
| R-17 | Low | `repository/DomainModels.ets:109-125`；`repository/DeviceRepository.ets:308-371` | CB §2.5（`notBeforeMs`）；PR-10（云完成不早于命令）；DES-B §5.3.2 规则 9 | `ControlApplyContext.notBeforeMs` 未被使用；`applyCloudState` 直接写调用方提供的 `requestId`/`seq`，未校验格式/范围。若 C-15 判定有缺陷，陈旧但 epoch 较新的状态可能被应用。属于防御纵深，不是已证实的生产缺陷。 | 在 cloud/ACK 应用边界校验 `patch.stateEpochMs >= context.notBeforeMs`（按秒级语义处理等号）、`requestId`/`seq` 格式；或在接口注释明确由 C-15/C-17 保证并补契约测试。 |
| R-18 | Low | `repository/DeviceRepository.ets:619-655`；DES-B §5.3.4 | `removeDevicesForGateway` 不写 tombstone，但也没有清理该网关既有 `gw_dismissed_device` 行 | 网关解绑后重新配对时，旧的 dismissed 记录可能继续跳过设备，用户只能逐个 restore；当前无测试。 | 评估解绑时清理该 gateway 的 tombstone，或明确保留策略并补测试。 |
| R-19 | Low | `repository/DeviceRepository.ets:396-460,839-851`；`RoomService.previewDelete` | 性能/索引（PF-01 为控制 RTT，不直接约束列表；DES-B §2.7 索引） | `listRecords`/`listUnassigned`/`listRecordsByRoom` 先按 family 全量取行，再在内存过滤；每个设备还额外查一次 tombstone（N+1）。设备数量大时会产生不必要的查询。 | 用带 `room_id`/`is_unassigned` 的 SQL 和 anti-join 利用已定义索引；至少在 C-10/C-21 集成前评估。 |

### 4.1 高严重度问题复现记录

使用 fake RDB + Node host loader 的只读探针（未提交；不改仓库）：

```text
revoked_error=INVITE_REVOKED member_after=ACTIVE
second_receipt_error=CONFIGURATION_ERROR used=1/2 status=ACCEPTED
owner_role=MEMBER owner_pointer=true transfer_after_owner_demotion=AUTH_RBAC_DENIED
same_scene_states=SUCCEEDED,SUCCEEDED commands=2
mismatch_state=FAILED snapshot_power=undefined
total_timeout_state=FAILED step0=PENDING failedIndex=0
assign_cross_family_error=none device_room=<roomB>
```

这些结果分别对应 R-01、R-10、R-09、R-02、R-03、R-05、R-07。O-1（R-04）未执行嵌套探针以避免挂起；其结论来自链式实现分析：嵌套调用会等待当前 chain，`inTransaction` 检查位于 chain 内，无法在重入时 fail-fast。

---

## 5. 已确认的正向证据

- **SSOT/仲裁（C-10）**：`applyDiscoverSnapshot` 对 `incomingEpoch < prior` 整条丢弃；相等 epoch 允许覆盖并记录 `SAME_EPOCH_OVERWRITE`；缺字段保留旧值；`isOnline=false` 不清空状态；`isPartial` 不标记网关移除；`aliasUsed` 只作诊断；tombstone 在 discover 中跳过、restore 后重新纳管；`removeDevice` 在同一事务中清理 scene 引用；ACK 的 stale/`DEVICE_MISMATCH`/idempotent replay/NO_REPORTED_STATE 路径与测试一致。
- **房间删除（C-09）**：`RoomService.deleteRoom` 在同一个顶层 `rdb.transaction` 内执行 room 删除、设备未分配/保护性禁用、成员 grant 清理；预览后重读并在事务内重新计数；失败整体回滚；无网络端口调用。
- **场景执行（C-11）**：预检先行且失败 0 命令；动作严格串行；`delayMs` 在动作前；失败后剩余步骤 SKIPPED，已执行步骤不回滚，`noRollbackNotice=true`；取消在每步/延迟期间生效；`UNVERIFIED` 视为成功，`MISMATCH` 视为失败。
- **O-1 串行**：共享 `DomainOperationGate` 的串行队列有效；Room/Device/Scene 的事务内方法均为 `tx`-context，不取 gate；`T09_O1_gateSerializesOperations` 证明第二个操作等待第一个完成。组合根共享 gate 的要求已在实现报告 §3 记录。
- **安全/隐私**：新增产品代码未 import `@ohos`/网络/平台 API；日志字段仅含 gatewayId/deviceId/roomId/familyId/action 等非秘密值；未发现 secret/token/password/seed 进入日志或异常；`FamilyRbac` 明确声明 GUEST 房间限制不是密码学边界（DP-06）。
- **范围/过程**：39 个路径均在声明的写范围；无构建产物、密钥、证书或 out-of-scope 产品文件；实现报告对设备侧 `BLOCKED` 与 `hvigorw test` 仅编译的表述诚实，没有把编译/骨架当作设备 PASS。
- **i18n**：新增代码没有硬编码用户可见文案；视图返回 `member.role.*`、`member.status.*`、`invite.mode.*` 等语义键。对应 locale 资源尚未由 C-14 落地，属于下游跟踪项（见 §6）。

---

## 6. 残余风险与跟踪项

| ID | 风险/跟踪项 | 处理建议 |
|---|---|---|
| T09-RV-01 | 真实 RDB/Preferences/Asset Store 未执行：迁移、重启、真实事务回滚、Asset 别名行为仍为 `BLOCKED` | 由设备/模拟器环境 owner 执行 `DomainDevice.test.ets` 或等价 IT；在环境可用前不得宣称 C-08..C-11 `STABLE`。 |
| T09-RV-02 | Hypium `hvigorw test` 在 Linux Previewer 无法启动；只有 `UnitTestArkTS` 编译证据 | 保持 `COMPILED_ONLY`；由设备/CI owner 在支持环境执行 Hypium。 |
| T09-RV-03 | C-13 的 container/seed/回执实现尚未存在；T-09 只用 fake 验证状态机 | T-13 适配 `InviteServicePort`；重点验证 R-01/R-10/R-11 的跨存储补偿与错误码。 |
| T09-RV-04 | C-12 的 AuthService 尚未存在；`FamilyAuthPort` 的 profile 清理与 session 失效仅为 fake | T-12 适配，验证 owner 转移、leave/dissolve profile 清理、`invalidateSessionsForMember` 的真实语义。 |
| T09-RV-05 | C-15 云完成判定 / `notBeforeMs` 尚未实现 | T-14 负责 `CloudCompletionVerdict` 的“不早于命令”保证；T-09 的 `notBeforeMs` 防御建议见 R-17。 |
| T09-RV-06 | i18n 键未落地：`member.role.*`、`member.status.*`、`invite.mode.*`、`invite.rotation.step.reprovision` 等 | C-14 资源包必须补齐并保持 zh-CN/en-US key parity；否则 UI fallback 会显示 key 文本。 |
| T09-RV-07 | 多网关轮换/解绑计划当前不完整；`leaveFamily`/`removeMember` 只携带首个网关计划 | 与 R-08 一并处理；若确认为 v1 限制，需在 DES-B/需求与 UI 文案中书面声明。 |
| T09-RV-08 | `removeMember` 不清理该成员的本地 profile；`dissolveFamily` 不删除 room/device/scene 行；邀请 seed alias 的清理归 C-13 | 在 C-22/C-13 的集成测试中确认没有孤儿 profile/asset；若负责人认为需要 T-09 负责，登记 Change Impact。 |
| T09-RV-09 | `FamilyService` 的 actor 参数可选；不提供时依赖 C-12 调用点做 RBAC | C-28/C-22 必须保证所有 UI 调用点传入 actor 或先做 session 校验；补集成级越权测试。 |
| T09-RV-10 | `FamilyContactSyncState.STALE` 当前没有产生路径；`FamilyChangeEvent` 未实现 | 由 C-22/T-15 决定是否需要；若 UI 依赖事件/STALE，补契约与实现。 |
| T09-RV-11 | `DeviceRepository.listRecords` 的 N+1 tombstone 查询与内存过滤未做基准 | C-21/C-25 集成前评估设备规模；必要时使用 SQL anti-join。 |
| T09-RV-12 | `entry/src/test/README.md` 的 Producer/Task 元数据仍只列到 T-08 | 由测试文档 owner 更新为包含 T-09，保持证据 provenance 一致（非产品代码阻塞项）。 |

---

## 7. 修复后的必需再验证

1. 修复 R-01..R-05（High）及 R-06..R-15 中确认的 Medium 项，或由 Orchestrator 对剩余项书面记录接受理由、范围与补偿控制。
2. 新增对应的 Host 用例：revoked/expired/duplicate receipt 且成员不存在、same-scene 并发、MISMATCH 状态回写、total timeout 步骤状态、owner 降级/移除、跨家庭 assign、unbound gateway、O-1 嵌套 fail-fast（带超时）。
3. 重新运行 `entry/src/test/run-host-tests.sh`（期望 ≥216，新增用例全部 PASS）、`codelinter`、`hvigorw clean assembleHap --no-daemon`，并重新生成/更新 T-09 证据。
4. 重新执行本评审（新 revision），确认 R-01..R-04 已关闭；在此之前不得将 C-08..C-11 标记为 `STABLE` 或通过 CQG-T09。
5. 设备环境可用时补真实 RDB/Preferences/Asset IT；设备骨架的 `BLOCKED_ON_DEVICE_RUNNER` 状态保持不变。

---

## 8. 独立性与结论声明

本报告由 `agent:quality-reviewer` 独立完成，未参与 T-09 实现，未修改被审代码、测试、证据或 `artifacts/50-implementation/t09-domain.md`。本报告的唯一写入为 `artifacts/70-review/t09-review.md`。评审裁决仅针对 revision `5e110db` 与 §1 范围，不覆盖 C-12/C-13/C-15/UI/组合根，也不授予 Stage Gate 或用户验收。

**Final Verdict: CHANGES_REQUIRED**
