# T-09 家庭/房间/设备/场景仓储与服务实现报告（C-08..C-11）

- **Artifact ID**: IMP-T09-DOMAIN
- **Producer**: agent:implementation-engineer
- **Type**: Implementation / Verification Evidence
- **Status**: Proposed（本地构建/lint/host 测试完成；待独立评审与 CQG-T09 Gate）
- **Date**: 2026-10-17
- **Task**: T-09 / `wp-024-domain`（task 分支 `task/wp-024-domain`，父分支 `feat/yaocore-app`，base commit `57f64d45c7442289db489df4cb6e62816815c43c`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`
- **上游契约**:
  - DES-B `artifacts/40-detailed-design/des-001b-domain-presentation.md` §3（C-08）、§4（C-09）、§5（C-10）、§6（C-11）、§2.4/§2.7/§2.8、§23（EXT-DES-B-04..12/17/20）
  - DES-A `artifacts/40-detailed-design/des-001a-foundation-transport.md` §3（错误/端口）、§5（共享模型）、§9（RDB/Preferences）、§11（FamilyRepository 基础面）、§12（AuthService 契约面）、§13（InviteService 契约面）
  - `artifacts/20-architecture/contract-baseline.md`、`project-constraints.md`（DP-01/DP-02/DP-03/DP-05/DP-06、SC-12/SC-13/SC-14、CP-04）
  - G-004 ADR-003/ADR-004 语义不改变；D-010/D-013/D-019
- **Downstream**: T-11（网关解绑引用清理）、T-12（Auth 端口适配）、T-13（真实 InviteService）、T-15/T-16（VM 消费）、T-19、T-20、CQG-T09
- **组件状态**: C-08 `UNVERIFIED`、C-09 `UNVERIFIED`、C-10 `UNVERIFIED`、C-11 `UNVERIFIED`（本报告不授予 `STABLE`）

---

## 0. 摘要

| 项 | 结果 | 证据 |
|---|---|---|
| C-08 FamilyRepository + FamilyService + FamilyJoinSession | **实现完成** | `repository/FamilyRepository.ets`；`service/family/` 4 文件 |
| C-09 RoomRepository + RoomService | **实现完成** | `repository/RoomRepository.ets`；`service/room/RoomService.ets` |
| C-10 DeviceRepository + DeviceCommandRunner | **实现完成** | `repository/DeviceRepository.ets`、`DeviceSnapshotCodec.ets`；`service/device/DeviceCommandRunner.ets` |
| C-11 SceneRepository + SceneService/Executor | **实现完成** | `repository/SceneRepository.ets`；`service/scene/` 4 文件 |
| v4 迁移（room/device_state/scene/cloud_config） | **实现完成** | `repository/DomainMigrations.ets` |
| O-1 单飞/禁止嵌套事务 | **实现并测试** | `repository/DomainOperationGate.ets`；Host `T09_O1_gateSerializesOperations` |
| Node host 测试 | **PASS 216/216**（新增 50：C-08 15 + C-09 8 + C-10 17 + C-11 10） | `entry/src/test/evidence/t09-host-node-tests.tap` |
| `ohpm install` | **PASS**（exit 0） | `entry/src/test/evidence/t09-ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | **PASS**（BUILD SUCCESSFUL，35 tasks） | `entry/src/test/evidence/t09-clean-assemble.log` |
| `codelinter -c code-linter.json5 -p default .` | **PASS**（No defects found） | `entry/src/test/evidence/t09-codelinter.log` |
| ArkTS 编译（附加） | **PASS（仅编译）**；`UnitTestArkTS` 成功，Previewer 执行仍 **BLOCKED**（timeout 124） | `entry/src/test/evidence/t09-hvigor-test-compile.log` |
| 设备侧骨架编译（附加） | **PASS（临时注册探针）**；`ohosTest@OhosTestCompileArkTS` BUILD SUCCESSFUL | `entry/src/test/evidence/t09-ohosTest-compile-probe.log` |
| 设备/模拟器实际运行 | **BLOCKED**（无 `hdc` target、无签名、无模拟器镜像） | 本报告 §7 |

**结论**：C-08..C-11 产品代码、host 逻辑测试、静态检查与 ArkTS 编译通过；真实 RDB/Asset/UI 运行未执行，不能宣布 `STABLE`。`assembleHap` 的默认可达图尚未由 C-28 组合根引用本任务模块（T-18 负责），因此本报告另以 `hvigorw test` 的 ArkTS 编译证明新增模块进入编译图。

---

## 1. 实现范围与文件

### 1.1 新增产品文件（20）

```text
entry/src/main/ets/repository/
├── DomainOperationGate.ets      # O-1 单飞 gate（依赖注入，无全局单例）
├── DomainPorts.ets              # C-08..C-11 跨组件端口（位置例外，见 §8.1）
├── DomainModels.ets             # DeviceRecord/合并/ACK/场景执行值对象
├── DomainMigrations.ets         # v4 DDL（room/device_state/scene/cloud_config）
├── SqlCells.ets                 # 严格 RDB cell/JSON 字符串数组编解码
├── DeviceSnapshotCodec.ets      # DeviceSnapshot 规范 JSON 编解码（same-epoch 身份比较）
├── FamilyRepository.ets         # C-08 数据访问 + v2 迁移 + MemberRoomGrantPort
├── RoomRepository.ets           # C-09 房间 CRUD/排序 + RoomLookupPort
├── DeviceRepository.ets         # C-10 SSOT/仲裁/墓碑/ACK/场景引用清理
└── SceneRepository.ets          # C-11 场景持久化 + SceneReferencePort

entry/src/main/ets/service/
├── family/
│   ├── FamilyService.ets        # 家庭/成员/邀请/退出/转让/解散用例
│   ├── FamilyJoinSession.ets    # 成员侧加入会话状态机
│   ├── FamilyModels.ets         # 视图/端口值对象（位置例外）
│   └── FamilyRbac.ets           # RBAC 矩阵（ADMIN/MEMBER/GUEST）
├── room/
│   └── RoomService.ets          # 删除事务/未分配池/零网络
├── device/
│   └── DeviceCommandRunner.ets  # C-10 控制用例（只调 DeviceControlPort）
└── scene/
    ├── SceneService.ets         # CRUD/run/cancel/事件
    ├── SceneExecutor.ets        # 预检/串行/局部失败/取消 + RunCancellation
    ├── SceneValidation.ets      # 预检清单与值校验
    └── SceneTimerPort.ets       # 可注入 delay seam（位置/形状例外）
```

### 1.2 测试与证据

```text
entry/src/test/
├── host/DomainFamily.test.mjs   # 15 用例
├── host/DomainRoom.test.mjs     # 8 用例
├── host/DomainDevice.test.mjs   # 17 用例
├── host/DomainScene.test.mjs    # 10 用例
├── host/domain-helpers.mjs      # 值对象夹具
├── domain/DomainHarness.ets     # fake RDB + v1..v4 迁移 + 共享 gate
├── domain/DomainFakes.ets       # Invite/Auth/Control/Route/Timer/Logger/Metrics fakes
├── domain/DomainHost.test.ets   # ArkTS 编译套件（仅编译）
├── List.test.ets                # 注册 DomainHostSuite（编译图）
├── storage/FakeStores.ets       # 扩展 mini RDB 复合 WHERE（向后兼容）
├── README.md                    # 更新当前测试数与 T-09 证据
└── evidence/t09-*.log|tap       # 本报告命令证据

entry/src/ohosTest/ets/test/domain/
└── DomainDevice.test.ets        # 设备侧 RDB 骨架（COMPILED_ONLY / BLOCKED）
```

---

## 2. 契约对照（DES-B 章节）

| 契约 | 实现位置 | 落地要点 | 证据 |
|---|---|---|---|
| DES-B §3 C-08 API/ERR/STATE/SEAM | `FamilyRepository`、`FamilyService`、`FamilyJoinSession`、`FamilyRbac` | 家庭创建/切换（activeFamilyId + 锁会话）、成员角色/状态、最后 ADMIN、GUEST 到期/续期、邀请 PENDING→ACCEPTED/EXPIRED/REVOKED、回执单次、退出/转让/解散、接触式收敛、无在线语义 | `DomainFamily.test.mjs` 15 用例 |
| DES-B §3.1.5 `MemberRoomGrantPort` | `FamilyRepository.removeRoomGrant` | 事务内移除 `allowed_room_ids_json`，不自开事务 | C-09 删除事务测试 |
| DES-B §4 C-09 API/ERR/STATE/SEAM | `RoomRepository`、`RoomService` | `roomId` 不变、改名/图标/排序、删除预览/确认竞态、单事务删除、设备未分配/禁用、授权清理、零网络 | `DomainRoom.test.mjs` 8 用例 |
| DES-B §4.3.3 删除事务 | `RoomService.deleteRoom` | 预览后重读 + 事务内重查设备数；`rooms.deleteRoom` → `devices.onRoomDeleted` → `grants.removeRoomGrant`；失败整体回滚 | 回滚负例通过 |
| DES-B §5 C-10 API/ERR/STATE/SEAM | `DeviceRepository`、`DeviceSnapshotCodec`、`DeviceCommandRunner` | SSOT、`stateEpochMs` 仲裁、字段级合并、partial/aliasUsed、网关移除提示、tombstone、ACK/云状态应用、场景引用清理、控制预检 | `DomainDevice.test.mjs` 17 用例 |
| DES-B §5.3.2 仲裁 | `DeviceRepository.applyDiscoverSnapshot` / `applyStateInTransaction` | `incoming < prior` 整条丢弃；相等允许覆盖并记 `SAME_EPOCH_OVERWRITE`；缺字段保留；`isOnline=false` 不清空状态；ACK 陈旧只影响状态应用、不否定执行确认 | 陈旧/相等/缺字段/stale ACK 用例 |
| DES-B §5.3.3 partial/aliasUsed | `applyDiscoverInTransaction` | `isPartial=true` 强制不标记网关移除；`aliasUsed` 只加诊断偏差，不置 partial | aliasUsed 用例 |
| DES-B §5.3.4 tombstone | `removeDevice`/`restoreDevice`/`removeDevicesForGateway` | 删除 = 删行 + `gw_dismissed_device` + 场景引用清理（同事务）；discover 跳过；restore 后重新纳管为未分配/禁用 | tombstone/restore/回滚用例 |
| DES-B §6 C-11 API/ERR/STATE/SEAM | `SceneRepository`、`SceneService`、`SceneExecutor`、`SceneValidation` | CRUD、预检先行、严格串行、逐步进度、局部失败不回滚（`noRollbackNotice=true`）、取消、设备删除引用清理 | `DomainScene.test.mjs` 10 用例 |
| DES-B §6.3.2 预检清单 | `SceneValidation.preflight` | 网关归属、设备存在/非 dismissed/非 gatewayRemoved、启用/已分配、类型受支持、动作-类型匹配、值域、delayMs | 预检 0 命令/类型不匹配用例 |
| DES-B §2.7 v4 DDL | `DomainMigrations` | room/device_state/scene/cloud_config + 索引；v2 由 FamilyRepository 注册；v3 留给 C-12 | Harness 迁移 v1..v4 + 设备骨架迁移 |
| DES-B §2.8 并发/取消/时间 | `DomainOperationGate`、`RunCancellation`、`SceneTimerPort` | 单飞、无嵌套事务、每步取消检查、`delayMs` 可注入 | O-1/取消/delay 用例 |

---

## 3. O-1 约束声明与落地

**规则（CQG-T08 带入，T-09 必须遵守）**

1. 普通 `execute`/`query` 与事务**单飞**；
2. **禁止嵌套事务**；
3. 跨仓储写操作必须在**单一顶层事务**内串行，通过端口注入完成。

**落地**

- `DomainOperationGate`：依赖注入的串行队列；所有仓储公共读写入口经 `gate.run(...)`；事务上下文方法（`tx` 参数）**不取 gate、不自开事务**。
- `RdbStore.transaction` 自身由 C-06 `RdbTransactionRunner` 全局串行；本任务不修改 C-06。
- 跨仓储事务：
  - `RoomService.deleteRoom`：`gate.run` → `rdb.transaction` → `rooms.deleteRoom(tx)` + `devices.onRoomDeleted(tx)` + `grants.removeRoomGrant(tx)`。
  - `DeviceRepository.removeDevice` / `removeDevicesForGateway`：`gate.run` → `rdb.transaction` → 设备行/墓碑 + `scenes.removeDeviceReferences(tx)` / `removeGatewayReferences(tx)`。
  - `FamilyService.dissolveFamily` / `leaveFamily`：可选 gate（组合根注入）→ `rdb.transaction` → `families.removeFamilyLocal(tx)` / `removeMemberLocal(tx)`；事务内只调用 tx-context 方法。
  - `SceneService.deleteScene`：可选 gate → `rdb.transaction` → `scenes.deleteScene(tx)`。
- 事务内调用的端口扩展：`RoomLookupPort.readRoomInTransaction`、`DeviceAssignmentPort.countByRoomInTransaction`；它们不取 gate。
- 代码注释在 `DomainOperationGate.ets`、`RoomService.ets`、`DeviceRepository.ets`、`SceneRepository.ets`、`FamilyService.ets` 显式记录该规则。
- 测试：`T09_O1_gateSerializesOperations` 验证第二个操作在第一个完成后才启动；房间删除/设备删除回滚用例同时证明事务内没有嵌套（fake RDB 遇到嵌套直接抛 `STORAGE_RDB_ERROR`）。

**组合根要求**：C-28 必须把**同一个** `DomainOperationGate` 实例注入 `FamilyRepository`、`RoomRepository`、`SceneRepository`、`DeviceRepository`、`RoomService`、`FamilyService`、`SceneService`。未注入时各仓储自建 gate，仍保证自身串行，但不保证跨仓储普通读与事务单飞。

---

## 4. 测试清单与结果

命令：`entry/src/test/run-host-tests.sh` → **216/216 PASS**（exit 0）。

| 套件 | 用例数 | 关键断言 |
|---|---|---|
| 既有 T-05..T-08 基线 | 166 | 全部保持通过（fake RDB 扩展向后兼容） |
| `DomainFamily.test.mjs` | 15 | 家庭创建/activeFamily；切换锁会话+档案；RBAC 矩阵+actor 拒绝；最后 ADMIN 不能删除/降级/退出；转让；GUEST 到期冻结/显式续期；邀请 KEY_WRAP/CODE_KEK；回执单次；撤销/过期；加入会话 KEY_WRAP/CODE_KEK；接触式收敛；退出/解散/profile 清理；Profile 清理失败仍保留本地删除结论 |
| `DomainRoom.test.mjs` | 8 | 创建/改名 ID 不变；默认排序；排序缺项/重复/跨家庭拒绝；指派/换房/未分配池；预览设备名/数量；确认数不一致拒绝；删除事务（设备禁用+成员授权清理）；注入失败整体回滚；空/最后房间；零网络 |
| `DomainDevice.test.mjs` | 17 | 新增未分配/禁用；陈旧包整条丢弃；同 epoch 覆盖诊断；缺字段保留/离线不清空；partial 不标记网关移除；aliasUsed 仅诊断；未知类型只读；tombstone→discover 跳过→restore→重新纳管；删除场景引用清理/回滚；ACK 应用/陈旧/不匹配/重放/无状态；`applyCloudState` accepted 边界；命令预检 0 端口调用；改名/换房零网络；O-1 gate 串行 |
| `DomainScene.test.mjs` | 10 | CRUD/名称/空动作/引用校验；串行成功+事件+指标；预检失败 0 命令；首步失败后 SKIPPED；次步失败 PARTIAL_FAILED 且不回滚；MISMATCH 失败/UNVERIFIED 成功；`delayMs` 由 fake timer 驱动；取消剩余 SKIPPED；房间删除后预检失败；禁用/不存在场景错误 |

> 设备侧 `DomainDevice.test.ets` **只编译**；本环境未运行，不计入 PASS。

---

## 5. 命令与输出

### 5.1 `ohpm install`

```text
$ ohpm install
install completed in 0s 52ms
exit=0
```

### 5.2 `hvigorw clean assembleHap --no-daemon`

```text
BUILD SUCCESSFUL in 7 s 136 ms
35 tasks in total: 34 executed, 1 up-to-date
exit=0
```

> 说明：HAP 默认可达图由 `pages/Index` 驱动，C-28 组合根尚未装配本任务模块（T-18），因此该命令不编译全部新增文件。新增文件的 ArkTS 编译证据由 §5.4 提供。

### 5.3 `codelinter -c code-linter.json5 -p default .`

```text
No defects found in your code.
exit=0
```

### 5.4 `hvigorw test --no-daemon`（附加编译证据）

```text
Finished :entry:default@UnitTestArkTS... after 11 s 459 ms
（随后 SDK Previewer 启动，Linux 环境 "Linux is not supported"/缺库，命令 90s 超时 exit=124）
```

- 结论：`DomainHost.test.ets` 把所有新增产品模块拉入 ArkTS 编译图并通过编译；**不是** Hypium 测试执行 PASS。
- 证据：`entry/src/test/evidence/t09-hvigor-test-compile.log`。

### 5.5 ohosTest 骨架编译（附加）

临时把 `DomainDevice.test` 注册进 `entry/src/ohosTest/ets/test/List.test.ets`（该文件不在 T-09 写范围，探针后已恢复）：

```text
Finished :entry:ohosTest@OhosTestCompileArkTS...
BUILD SUCCESSFUL in 8 s 622 ms
exit=0
```

- 证据：`entry/src/test/evidence/t09-ohosTest-compile-probe.log`。
- 永久注册需由 `List.test.ets` 的 owner 或后续任务完成；本任务提交不包含该文件改动。

### 5.6 Host 测试

```text
entry/src/test/run-host-tests.sh
1..216
# tests 216
# pass 216
# fail 0
exit=0
```

---

## 6. 契约/实现细化与位置例外

以下均为**增量**，不改变 DES-A/DES-B 已冻结字段语义；需评审确认或由下游任务适配。

1. **端口位置例外**：DES-B 名义上把端口放在 `contracts/**`。T-09 写范围是 `repository/**`/`service/**`，故 `RoomLookupPort`、`DeviceAssignmentPort`、`MemberRoomGrantPort`、`SceneReferencePort`、`DeviceControlPort`、`DeviceStatePort` 位于 `repository/DomainPorts.ets`；`InviteServicePort`/`FamilyAuthPort` 位于 `service/family/FamilyModels.ets`。纯接口、无平台依赖。
2. **模型位置例外**：`DeviceRecord`/`DiscoverApply*`/`ControlApply*`/`SceneExecution*` 等 DES-B `model/**` 值对象位于 `repository/DomainModels.ets`；`FamilyMemberView`/`InvitationView`/`JoinSessionState` 位于 `service/family/FamilyModels.ets`。T-15/T-16 可直接 import；若后续要求迁回 `model/**`，按 Change Impact 移动并保持导出名。
3. **端口扩展**：`RoomLookupPort.readRoomInTransaction`、`DeviceAssignmentPort.countByRoomInTransaction`、`RoomDeviceNamePort`、`DeviceRepository.isDismissed`、`FamilyRepository.clearActiveFamily` 为 O-1/删除竞态所需的最小增量。
4. **构造函数/方法可选参数**：`FamilyRepository`/`RoomRepository`/`DeviceRepository`/`SceneRepository` 增加可选 `DomainOperationGate`；`DeviceRepository` 增加可选 `GatewayRoutePort`（未绑定网关忽略整份 discover）；`FamilyRepository.createFamily` 增加可选 `ownerDisplayName`（避免创建后再回写成员名）；`FamilyService` 增加可选 `rdb`/`rooms`/`gate`；`SceneService` 增加可选 `rdb`/`gate`。DES-A 冻结签名保持可用，组合根负责注入。
5. **`SceneTimerPort`**：DES-B `TimerPort` 含 `scheduleOnce/scheduleRepeating`；本任务只需要 `delay(ms)`，为避免与 T-15 的 TimerPort 定义冲突，暂以 `SceneTimerPort` 命名；T-15/T-18 可适配到统一 TimerPort。
6. **merge 诊断持久性**：`DeviceMergeState.lastResult/lastDeviationCode` 与 `hasPartialState` 为进程内诊断；重启后由 `state_epoch_ms`/`last_merge_at` 重建为 `UNCHANGED`。冻结表未要求持久化诊断字段。
7. **`applyCloudState` 边界**：只接受调用方已判定 `accepted=true` 的状态补丁；PB-02/`DeviceInventoryJson` 完成判定不在本任务实现（C-15）。
8. **RBAC actor**：DES-B C-08 方法签名不含 actor；实现保留原签名并增加可选 `actorMemberId` 参数：提供时校验 `ADMIN+ACTIVE`，不提供时按 v1 本地管理员信任由 C-12 调用点校验；数据不变量（最后 ADMIN、邀请角色/房间/时效）无条件执行。
9. **回滚计划粒度**：`RemoveMemberResult.rotationPlan`/`LeaveFamily` 的 `FamilyDissolutionPlan.gatewayIds` 在单网关时完整；多网关时当前只携带首个网关的引导计划（DES-B 类型本身为单 `RotationPlan`）。多网关轮换引导由 T-13/C-23 扩展。
10. **FR-FAM-004 v1 限制声明**：退出/转让/解散为**本地语义 + 引导流程**，无服务器协调、无跨设备在线状态；跨设备一致性为接触式收敛（D-010/DP-05）。不自动删除网关绑定、不自动轮换密钥、不擦除实体网关（SC-12）。
11. **邀请/回执**：C-13 真实容器加密由 T-13 实现；本任务只消费 `InviteServicePort` 并以 fake 验证状态机。`FamilyJoinSession` 对 GUEST 的防御性 upsert 在容器未携带独立成员时效时使用本地 24h 兜底（正常路径由 C-13 写成员，不触发）。
12. **i18n**：本任务不新增用户可见文案；`FamilyMemberView`/`InvitationView` 只输出 `member.role.*`/`member.status.*`/`invite.mode.*` 等语义键；日志为英文诊断字段，不含姓名/邀请码/密钥。

---

## 7. 设备限制与未执行项

| 项 | 状态 | 原因/处置 |
|---|---|---|
| 真实 RDB 适配器运行（迁移/重启/事务回滚） | **BLOCKED** | 无 `hdc` target、无模拟器实例、`signingConfigs: []`；`DomainDevice.test.ets` 已编译，待设备 runner |
| 真实 Preferences/Asset/RDB 持久化 | **BLOCKED** | 同上 |
| 场景执行真实网关 ACK/时延 | **UNAVAILABLE** | 无真实网关/设备；仅 fake `DeviceControlPort` + 契约层既有仿真器 |
| UI/ViewModel 集成 | **NOT_RUN** | T-15/T-16 下游 |
| 云完成判定/PB-02 | **OUT_OF_SCOPE** | C-15（T-14） |
| ohosTest 永久注册 | **DEFERRED** | `entry/src/ohosTest/ets/test/List.test.ets` 不在 T-09 写范围；临时探针编译通过，提交不包含该改动 |
| HAP 默认可达图包含本任务模块 | **DEFERRED** | C-28 组合根（T-18）装配后才会进入 `assembleHap` 可达图 |

---

## 8. 偏离、未决项与风险

| ID | 类型 | 内容 | 处置 |
|---|---|---|---|
| T09-R01 | 未决 | 真实 `InviteService` 由 T-13 实现；本任务端口类型为最小结构子集 | T-13 适配 `InviteServicePort`；若签名冲突走 Change Impact |
| T09-R02 | 未决 | 真实 `AuthService` 由 T-12 实现；`FamilyAuthPort` 需其 `listProfiles/lockAll/invalidateSessionsForMember/removeProfiles*` | T-12 适配；`removeProfiles*` 为 DES-B §23.3 扩展 |
| T09-R03 | 风险 | 多家庭 `LocalProfile` 单值；切换家庭必须锁定并解锁目标家庭档案 | 已在 `switchFamily` 实现 `lockAll + listProfiles`；无档案返回 `AUTH_PROFILE_NOT_FOUND`；UI 需如实提示 |
| T09-R04 | 风险 | 合并诊断（lastResult/hasPartialState）仅进程内 | 冻结表不持久化；重启后诊断降级，不影响仲裁事实 |
| T09-R05 | 风险 | 场景 `stepTimeoutMs` 依赖注入 timer；真实实现需 C-28 提供 | 默认 8000ms；迟到 outcome 由 `Promise.race` 丢弃 |
| T09-R06 | 风险 | 邀请/成员跨设备一致性为接触式收敛，无在线状态 | FR-FAM-004 声明；UI 不得显示在线 |
| T09-R07 | 风险 | GUEST 房间限制是 App 策略，非密码学边界 | DP-06 已在 `FamilyRbac` 注释声明 |
| T09-R08 | 风险 | 设备删除时场景清理与设备行同事务；若场景行 JSON 损坏，删除整体失败 | 符合 DES-B §6.3.4“失败整体回滚”；诊断走 `STORAGE_RDB_ERROR` |

---

## 9. 追溯

| 需求/约束 | 实现/测试 |
|---|---|
| FR-FAM-001/002/003/004 | `FamilyService`、`FamilyRepository`、`FamilyJoinSession`；`DomainFamily` |
| FR-ROOM-001..006 | `RoomRepository`、`RoomService`、`DeviceRepository`；`DomainRoom`/`DomainDevice` |
| FR-DEV-001/005、FR-HOME-001..004 | `DeviceRepository`、`DeviceCommandRunner`；`DomainDevice` |
| FR-SCN-001、UIUX §4.6 | `SceneService`/`SceneExecutor`；`DomainScene` |
| DP-01/DP-02/DP-03/DP-05/DP-06 | 零网络断言、未分配池、tombstone、接触式收敛、GUEST 非密码学边界 |
| SC-12/SC-13/SC-14 | 本机删除不擦网关；ACK 真实接受链沿用 C-05/C-17 语义；不虚构成功 |
| CP-04、D-010/D-013/D-019 | 只读降级、无在线、到期提示轮换、host/device 分层 |
| DES-B §2.7/§2.8、O-1 | v4 迁移、gate、单事务、取消 |

---

## 10. 结论

C-08..C-11 的仓储/服务、O-1 并发约束、v4 迁移与 50 个新增 host 用例已完成并通过；`ohpm install`、`clean assembleHap`、`codelinter`、`run-host-tests.sh` 全部 exit 0。新增模块经 `hvigorw test` 的 ArkTS 编译与 ohosTest 临时注册探针验证可编译；设备侧真实运行仍 BLOCKED。组件保持 `UNVERIFIED`，等待独立评审与 CQG-T09。
