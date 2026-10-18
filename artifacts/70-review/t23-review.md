# A1 端口迁移独立评审报告（T-23 / wp-090-ports）

- **Artifact ID**: T23-REVIEW
- **Producer**: agent:quality-reviewer
- **Task**: `wp-091-review-ports`（Handoff `state/handoffs/wp-091-review-ports.json`）
- **Role**: quality-reviewer（未参与 `wp-090-ports` 实现或修复；未编辑被审代码）
- **Reviewed revision**: `aa9bdd1`（`refactor(contracts): 迁移端口到 contracts 并收口例外`；base/parent `1d4b202`，`task/wp-090-ports`）
- **Base branch**: `task/wp-090-ports`（父分支 `feat/yaocore-app`）
- **Review scope**: `entry/src/main/ets/`、`entry/src/test/`、`tools/contract/`、`artifacts/50-implementation/t23-ports-migration.md`
- **Inputs**: `t23-ports-migration.md`、DES-A §27.6、DES-B、`check_layering.py`、`layering_allowlist.json`、`test-plan.md`；6 个 handoff SHA-256 逐项一致
- **Workflow**: STANDARD / GATED_AUTO
- **Date**: 2026-10-18
- **Verdict**: **CHANGES_REQUIRED（代码级，仅限 `aa9bdd1` 与本次范围）** —— 位置迁移、构建、主机测试和 checker 回归均可复现；但 `contracts/TimerPort.ets` 与 DES-B `EXT-DES-B-01` 的冻结契约形状冲突、D-03 的字面规则与 checker/报告不一致，二者在修复或取得上游裁定前不能宣告端口契约已收口
- **Status**: COMPLETE（独立评审完成；不授予 Stage Gate、IG 或用户验收）

> **结论先行**：`aa9bdd1` 的 17 条位置例外按 DES-A §27.6.3 P1-P3 完成迁移，16 条位置例外关闭，仅保留 `PORT-LOC-01` 的 `ClockPort`/`IdPort`；旧 17 个文件中的 51 个接口、24 个值类经归一化比对无签名/实现变化；`main/test` 相对 import 解析 0 缺失、221 个 `.ets` 文件 0 环；host **697/697**、`clean assembleHap` **BUILD SUCCESSFUL**、codelinter **0 error / 25 warn**、layering **12/12**、i18n **blocking=0 / missing=0**、crosscheck **hard ALL PASS** 均独立复现。**但本评审不给出 PASS**：`contracts/TimerPort.ets` 装入的是 C-15 云轮询 `sleep/cancel` 端口，而 DES-B §23.1 `EXT-DES-B-01` 明确把同一路径定义为 VM 回调定时器 `scheduleOnce/scheduleRepeating/cancel` + `TimerHandle`；报告未记录该冲突，文件头还错误引用了 `EXT-DES-B-01`。同时 `contracts/** → contracts/**` 的 4 条 type-only import 被 checker 放行，而 DES-A §2.2 D-03 的字面允许集只有 `common/**`、`model/**`，报告 §2.1 也写成“只允许 common/model”，与实际代码和 checker 行为不一致。上述两项属冻结契约/门禁语义问题，需解决后再复评。

---

## 1. 范围、revision、输入与独立性

| 项 | 本次结论 | 证据 |
|---|---|---|
| 仓库 / 分支 | `/home/quirkybrain/code/harmony-projects/YaoCore`；`task/wp-090-ports` | `git branch --show-current` |
| Reviewed HEAD | `aa9bdd1b9a87c1d7ed51fa1fd7050615ce7daf51` | `git rev-parse HEAD` |
| Base / 父分支 | base `1d4b202`；父分支 `feat/yaocore-app` 指向 `1d4b202` | handoff + `git rev-parse` |
| 工作树 | 评审前干净；评审期间未修改产品代码/测试/契约 | `git status --short --branch` |
| 输入完整性 | 6 个 handoff 输入 SHA-256 全部一致 | `sha256sum` 对照 handoff |
| 作者独立性 | 本评审未参与 `wp-090-ports` 实现；唯一写入为本报告 | 本任务 `writes`/`commit_paths` 仅 `artifacts/70-review/` |
| 评审限制 | 无设备/模拟器/签名；未运行 ohosTest、真实 BLE/LAN/云/TLS；`assembleHap` 不编译 `entry/src/ohosTest/**` | 与报告 §7.3 的 BLOCKED 边界一致 |

**变更范围核对**：commit 共 178 个路径；`entry/src/main/ets` + `entry/src/test` 中既有文件修改 **125** 个、新增/重命名源文件 **30** 个（contracts 20、model 8、common/types 2）、旧文件删除/重命名 **18** 个；`tools/contract/**` 与实现报告另有修改。报告 §4 的 30/18/125 计数与 `git show --name-status` 一致。

**不在本次范围**：`entry/src/ohosTest/**`（不在 handoff 写范围，存在已知 7 文件/12 条失效 import）、DES-A/DES-B 文本更新、设备矩阵、Stage Gate。

---

## 2. 独立复验结果（cwd = 仓库根，本次实际执行）

| # | 命令 | 本次实测 | 与实现报告的一致性 |
|---|---|---|---|
| 1 | `entry/src/test/run-host-tests.sh` | **tests 697 / pass 697 / fail 0 / skipped 0**；exit 0；duration ≈ 3018 ms | 一致（697/697） |
| 2 | `hvigorw clean assembleHap --no-daemon` | **BUILD SUCCESSFUL in 16 s 274 ms**；exit 0；0 ERROR；unsigned HAP | 一致（耗时因缓存不同） |
| 3 | `codelinter -c code-linter.json5 -p default .` | **Defects 25 / Errors 0 / Warns 25 / Suggestions 0**；exit 0 | 一致 |
| 4 | `python3 tools/contract/check_layering.py` | `files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0`；exit 0 | 一致 |
| 5 | `python3 tools/contract/test_check_layering.py` | **Ran 12 tests / OK**；exit 0 | 一致（12/12） |
| 6 | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | `blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16`；exit 0 | 一致 |
| 7 | `python3 tools/contract/crosscheck_protocol_assets.py` | **hard checks: ALL PASS**；14 条 frozen-input findings；exit 0 | 一致（14 条既有 finding） |

补充静态核对（评审自建脚本，未入库）：

- `entry/src/main/ets` + `entry/src/test` 相对 import 解析：**0 missing module**。
- 全量 `entry/src/main/ets/**/*.ets`（221 文件）import 图：**0 循环依赖**。
- 旧 17 个文件中的 **51 个 interface**、**24 个 value class** 归一化（去注释/空白）比对：新位置全部存在，**无签名/实现变化**；`ManualDiscoveryPort` 仅将 inline `import()` 类型改为命名 `import type`，语义等价。
- `contracts/**` 仅 import `common/**`、`model/**`、同层 `contracts/**`；**无 service/repository/viewmodel/app/pages 依赖、无 `@ohos.*`/`@kit.*`/`node:` import**。
- `repository/** → service/**`：**0**；`viewmodel/** → service/{gateway,ble,crypto,storage}`：**0**；`pages/components → repository`：**0**；`pages → service/**` 仅剩 6 条已登记 D-12（FamilyModels/RoomService/CloudModels）与 i18n 白名单（见 §4）。
- `entry/src/ohosTest/**`：**7 个文件 / 12 条失效 import**（9 条失效模块 + `RandomPort`、`LoggerPort`×2 三个已迁出 `common/types/Ports` 的符号）；报告已披露 7/12，但清单漏列两处 `LoggerPort`，见 F-06。

> 上述复验证明构建、主机逻辑、checker 与 i18n 门禁；**不证明** ohosTest 编译、设备行为或 DES 文本已同步。

---

## 3. 17 条迁移对照结论

> 独立按 DES-A §27.6.2 的 17 条 ID、原路径/符号逐项核对；旧文件符号集合与 DES-A 表一致。结论中的“位置关闭”只表示旧路径已删除/符号已落位，**不等同于目标契约文件形状已与 DES-B 对齐**（见 F-01/F-03）。

| ID | 原路径 | 新位置 / 保留 | 结论 |
|---|---|---|---|
| PORT-LOC-01 | `common/types/Ports.ets` | `contracts/Ports.ets`（`RandomPort`/`LoggerPort`/`MetricsPort`/`HmacSignerPort`）+ `common/types/CancellationToken.ets`（`CancellationToken`）；`common/types/Ports.ets` 保留 `ClockPort`/`IdPort` | **部分关闭（合理）**；保留理由成立（见 §4.3） |
| PORT-LOC-02 | `service/crypto/CryptoPort.ets` | `contracts/CryptoPort.ets`（`CryptoPort` + `X25519KeyHandle`/`X25519KeyPair`/`AesCtrState`/`AesCtrStream`/`GcmCiphertext`） | 位置关闭；签名不变 |
| PORT-LOC-03 | `service/storage/RdbStore.ets` | `contracts/RdbStore.ets`（`RdbValue`/`RdbRow`/`RdbTransaction`/`RdbStore`） | 关闭；签名不变 |
| PORT-LOC-04 | `service/storage/PreferencesStore.ets` | `contracts/PreferencesStore.ets` | 关闭 |
| PORT-LOC-05 | `service/storage/SecretStore.ets` | `contracts/SecretStore.ets`（`SecretStore`）+ `common/types/SecretAlias.ets`（`SecretAlias`） | 关闭；`repository` 不再 import `service/storage` |
| PORT-LOC-06 | `service/storage/SecretDraftPort.ets` | `contracts/SecretDraftPort.ets` | 关闭 |
| PORT-LOC-07 | `service/storage/MigrationPort.ets` | `contracts/MigrationPort.ets`（`MigrationSink`/`MigrationRegistryPort`） | 关闭 |
| PORT-LOC-08 | `service/ble/BleProvisioningPorts.ets` | `contracts/BleProvisioningPorts.ets`（6 端口/监听器）+ `model/ProvisioningModels.ets`（12 DTO/枚举） | 关闭；D-12 09/10 变为 unused |
| PORT-LOC-09 | `service/ble/GattEndpointMap.ets` | `model/GattEndpointMap.ets`（纯映射） | 关闭 |
| PORT-LOC-10 | `service/gateway/GatewayTransportPorts.ets` | `contracts/GatewayTransportPorts.ets`（3 端口）+ `model/GatewayTransportModels.ets`（6 DTO） | 关闭；`contracts/GatewayTransportPorts.ets:22` 引用同层 `GatewayCredentialPort`（见 F-02） |
| PORT-LOC-11 | `service/gateway/DiscoveryModels.ets` | `model/DiscoveryModels.ets`（6 模型/枚举）+ `contracts/DiscoveryTransport.ets`（`DiscoveryTransport`/`ManualDiscoveryPort`） | 关闭；`ManualDiscoveryPort` 与 C-18 收敛 |
| PORT-LOC-12 | `service/cloud/CloudPorts.ets` | `contracts/CloudPorts.ets`（3 端口）+ `contracts/TimerPort.ets`（`TimerPort`：`sleep`/`cancel`） | **位置关闭，但目标 `TimerPort` 与 DES-B `EXT-DES-B-01` 冲突**（F-01） |
| PORT-LOC-13 | `service/i18n/I18nPorts.ets` | `contracts/I18nPorts.ets` + `model/I18nModels.ets` | 关闭 |
| PORT-LOC-14 | `service/scene/SceneTimerPort.ets` | `contracts/SceneTimerPort.ets` | 关闭；仍与 `VmTimerPort`/`TimerPort` 并存（F-07） |
| PORT-LOC-15 | `repository/DomainPorts.ets` | `contracts/RoomPorts.ets`（4）+ `contracts/ScenePorts.ets`（1）+ `contracts/DevicePorts.ets`（3） | 关闭；`service → repository` 反向可见性消除 |
| PORT-LOC-16 | `repository/GatewayPorts.ets` | `contracts/GatewayPorts.ets`（6 接口）+ `model/InvitedGateway.ets`（值对象） | 关闭 |
| PORT-LOC-17 | `viewmodel/ViewModelPorts.ets` | `contracts/ControlPorts.ets`（1）+ `contracts/PermissionPort.ets`（2）+ `contracts/DiscoveryTransport.ets`（`ManualDiscoveryPort`） | **位置关闭；同名 `PermissionPort`/`PermissionResult` 契约残留在 app（F-03）** |

**计量**：17 条中 **16 条位置例外关闭**，仅 PORT-LOC-01 保留；`port_location_exceptions` 从 17 条降为 1 条。旧 17 个文件除 `common/types/Ports.ets` 外均不存在；`repository/DomainModels.ets` 另行拆分为 `model/DeviceRecord.ets`/`model/SceneExecutionModels.ets`。

---

## 4. D-12 收口、PORT-LOC-01 与 checker 语义

### 4.1 D-12 entries

- 13 条 `T20-D12-01..13` 与 DES-B §18.1 表逐条一致；`entries` 内容与 `1d4b202` 完全相同，只有 `producer`/`task`/`policy` 更新。
- 迁移后实际使用 **6 条**：`T20-D12-06/07/08/11/12/13`；**7 条 unused**：`T20-D12-01..05/09/10`。checker 报告 `exceptions_used=6`、`pending=0`，与报告 §5.2 一致。
- `used && status !== accepted` 仍按 `_allowed()` 失败；`pending` 在 CLI/JSON 中报告。当前 13 条全部 `accepted`，无 pending。
- 7 条 unused 中 01..05/09/10 指向已迁走/已删除的旧路径；保留它们不会放宽当前检查，但属于 **DES-B §18.1 待退休的登记债**。报告 §7.2 已如实记录“后续 DES-B 同步任务退休”；Stage Gate 不得把 13 条仍被使用写成已收口。

### 4.2 PORT-LOC-01 保留理由

`ClockPort`/`IdPort` 保留在 `common/types/Ports.ets` 的理由经代码核实成立：

1. `common/utils/DateTimeUtil.ets:10,65` 的冻结签名 `nowUtcCompact(clock: ClockPort)` 与 `common/utils/UuidUtil.ets:7,13` 的 `newUuid(ids: IdPort)` 都从 `common/types/Ports` type-import 这两个端口。
2. DES-A §2.2 D-01 禁止 `common/**` import `contracts/**`；若移动这两个端口，必须改 D-01 或改冻结签名。
3. DES-A §27.6.3 禁止复制一套端口；保留 1 条已审阅的位置例外是当前无上游裁定下不产生重复定义的方案。
4. 该条目在 checker 中 `used=0`（D-09/D-11 不限制 `common` 目标），但 `validate_port_location_files()` 仍会检查该文件本身；close condition 已改为“需批准 D-01 或冻结签名变更”，不是无条件永久接受。

**建议**：由 `solution-architect` 决定是否允许 `common/**` 对 `contracts/**` 的 type-only import；若允许，可移动两个端口并删除最后一条例外。报告 §7.1 的建议方向正确。

### 4.3 checker 语义与 allowlist

- `load_port_location_exceptions()` 使用精确路径、非空 `symbols` 子集、`kind` 枚举、`accepted-location-exception`/`pending-*` 状态；通配路径/重复路径/空 symbols 均 exit 2，符合“fail closed”。
- `_match_port_exception()` 只在 D-09/D-11 目标路径匹配时使用，未登记路径、symbols 越界、非 accepted 状态均失败；`port_exceptions_used=0` 与当前唯一保留条目的 `used=0` 一致。
- `validate_port_location_files()` 检查已登记端口文件的 platform/adapter/未登记 repository 依赖；当前 PORT-LOC-01 文件无 import，未触发。
- **但** checker 对 `port_location_exceptions` 的 `.owner`/`.close_condition`/`.evidence` 不校验非空（`check_layering.py:409-438`），也不让“未使用的 pending port exception”单独失败（`:907-923`）。当前数据字段齐全，尚无实际违规；这是 F-04 的工具债，不能把“schema is intentionally strict”当作已经完整实现。

---

## 5. Import 更新、纯度与依赖

| 检查 | 结果 | 证据 |
|---|---|---|
| 旧路径残留（main/test） | 0 个失效模块 import；旧 17 文件除 `common/types/Ports.ets` 外均不存在 | 自建 resolver；`git show --name-status` |
| 旧符号残留（main/test） | 无 `RandomPort`/`LoggerPort`/`MetricsPort`/`HmacSignerPort`/`CancellationToken` 从 `common/types/Ports` 的 import | grep + ArkTS 构建 |
| contracts 纯度 | 无 `@ohos.*`/`@kit.*`/`node:`；无 service/repository/viewmodel/app/pages import | grep + 全量 import 图 |
| contracts → contracts | 4 条 type-only：`GatewayTransportPorts.ets:22`、`MigrationPort.ets:10`、`RoomPorts.ets:9`、`ScenePorts.ets:9` | 见 F-02（与 D-03 字面冲突） |
| model 纯度 | 无 contracts/service/repository/viewmodel/platform import；model→model 为既有形态 | grep；D-02 字面/checker 同层允许问题见 §7 残余 |
| `repository → service` | 0 | checker + grep |
| `viewmodel → service/{gateway,ble,crypto,storage}` | 0 | checker + grep |
| 循环依赖 | 221 文件，0 环 | 自建 Tarjan 扫描 |
| 端口签名 | 51 接口 / 24 类归一化比对全部一致 | 自建脚本；旧/新文件对照 |

**例外说明**：`contracts/**` 的 4 条同层 import 是 F-02 的争议点；它们均为 `import type`，不引入运行时实现依赖，但字面上超出 DES-A D-03 的“只 `common/**`、`model/**`”允许集，且 checker 的消息仍写着“only import common/** or model/**”。

---

## 6. 检查器、fixtures 与报告事实核对

### 6.1 正向

- 旧硬编码端口路径放行函数 `_is_storage_port_path`/`_is_viewmodel_service_port` 在两个提交前已由 T-20 移除；T-23 未重新引入。checker 当前只读 `port_location_exceptions`。
- T-23 删除了失效的 `_is_pages_repository_dto`/`_is_components_repository_dto`，并把 `service/i18n` 白名单收缩为 `I18nService`/`I18nKeys`（`I18nModels` 已迁 `model/**`）。
- 新增 post-migration 正/负 fixture：合法树（contracts/model 直连、空登记）通过；负例覆盖 `repository → service/storage`（D-09）、`viewmodel → service/storage`（D-11）、`pages → service/room`（D-12）；既有 `bad` fixture 覆盖 D-03/D-05；`port-exceptions` 覆盖合法、未登记、symbols 溢出、pending；`test_check_layering.py` 12/12 通过。
- checker 报告 `files=221`、`violations=0`、`exceptions_used=6`、`pending=0`、`port_exceptions_used=0`；与实现报告一致。

### 6.2 覆盖/语义缺口

- **D-03 同层放行未测试**：`bad` fixture 只测 `contracts → service/repository`，没有 `contracts → contracts` 的正/负例；checker 条件 `target_layer in (None,"common","model","contracts")` 与消息不一致（F-02）。
- **registry schema 只校验部分字段**：owner/close_condition/evidence 为空仍可通过（F-04）。
- **unused pending**：pending port exception 未使用时不会单独失败；`main()` 只在 `port_pending_used > 0` 时打印，但退出码仍为 0。当前条目为 accepted，故不改变本次结论；若未来新增 pending，门禁可能漏报。
- **D-02 同层**：checker 允许 model→model，而 DES-A D-02 字面只列 common；迁移新增了 model→model 边（如 `ControlExecution → DeviceRecord/CloudControlModels`、`SceneExecutionModels → FamilyModels`）。这是既有 checker/契约措辞的同类问题，建议与 D-03 一起做一次措辞/裁定同步。

### 6.3 报告事实核对

- 报告 §4 计数 125/30/18、§5.2 的 6/7、§6 的 697/25/12/0/0/14 均可复现。
- 报告 §1 的 17 条原路径/符号与 DES-A §27.6.2 一致；§2 的映射逐条可追溯。
- **报告错误 1**：§2.1 第 70 行“`contracts/**` 只允许 import `common/**`、`model/**`”与 4 条同层 import 不符（F-02）。
- **报告错误 2**：§8 未记录 `contracts/TimerPort.ets` 与 DES-B `EXT-DES-B-01` 的形状冲突；文件头 `TimerPort.ets:4-5` 误引 `EXT-DES-B-01`（F-01）。
- **报告错误 3**：§3.5/§2 对 PORT-LOC-17 标记“关闭”，但未记录 `app/PermissionPolicy.ets` 仍保留另一个 `PermissionPort`/`PermissionKind`/`PermissionResult` 的同名技术债（DES-B §23.7 已记录，T-23 未在报告中重申）（F-03）。
- **报告错误 4**：§1/§2 的 “理由见 §6.1” 应为 §7.1（正文实际章节为 7.1）；§7.2 ohosTest 清单写 7/12 是正确的，但只列 `RandomPort`，实际还有两处 `LoggerPort`（F-06）。

---

## 7. Findings

> 严重度按“对本迁移契约声明/门禁的影响”评定；“Blocking”表示在修复或取得上游书面裁定前不应把 A1 端口迁移写成契约收口/进入 Stage Gate PASS。

| ID | 严重度 | 位置 | Finding / 影响 | 建议 |
|---|---|---|---|---|
| **F-01** | **Major（Blocking）** | `entry/src/main/ets/contracts/TimerPort.ets:4-5,14-17`；`artifacts/40-detailed-design/des-001b-domain-presentation.md:6191,6206-6211`；`entry/src/main/ets/viewmodel/core/ViewModelCore.ets:193-195` | 新 `contracts/TimerPort.ets` 是 C-15 云轮询端口 `sleep(ms,cancellation?)/cancel()`，但 DES-B §23.1 `EXT-DES-B-01` 把同一路径定义为 VM 回调定时器 `scheduleOnce/scheduleRepeating/cancel(handle)` + `TimerHandle`；文件头却引用 `EXT-DES-B-01`。`CloudService.ets:19` 与 `SystemTimerPort.ets:11` 已按云形状 import；`VmTimerPort` 仍是第三个定时器 seam。影响：目标冻结路径被错误接口占用，按 DES-B 实现的 VM 定时器无法在 `contracts/TimerPort.ets` 落地；报告的“未改冻结端口签名/17 条关闭”在此条目上只对旧云签名成立，未对 DES-B 目标契约成立。 | 由 `solution-architect` 在 Change Impact 中二选一：①把云端口改名（如 `CloudDelayPort`/`PollTimerPort`），把 `contracts/TimerPort.ets` 留给 `EXT-DES-B-01`；或②正式修订 DES-B `EXT-DES-B-01` 为云 `sleep/cancel` 形状并说明 `VmTimerPort` 的归属。同步更新 imports、allowlist、报告和 checker 文档；重新全量复验。 |
| **F-02** | **Major（Blocking）** | `tools/contract/check_layering.py:527-531`；`artifacts/40-detailed-design/des-001a-foundation-transport.md:442`；`contracts/GatewayTransportPorts.ets:22`、`MigrationPort.ets:10`、`RoomPorts.ets:9`、`ScenePorts.ets:9`；`artifacts/50-implementation/t23-ports-migration.md:70` | D-03 字面规则是 `contracts/**` 只 import `common/**`、`model/**`；checker 条件却允许 `contracts` 同层，消息仍写“only common/** or model/**”。实际有 4 条 `contracts → contracts` type-only import，报告 §2.1 又声称只允许 common/model。影响：`violations=0` 不能证明 D-03 字面合规；“D-03 在 contracts 存在后真正生效”的结论建立在一个未登记的放宽上；未来同层 import 可无评审扩张。 | 由 `solution-architect` 明确是否允许**仅 type-only** 的 `contracts/** → contracts/**`（从类型依赖看很可能应允许）。若允许：更新 DES-A §2.2 D-03 的允许集/注记、checker 条件与消息、报告 §2.1，并补 `contracts→contracts` 正/负 fixture；若不允许：把共享类型移到 `model/**` 或重构端口，删除同层 import。 |
| **F-03** | **Medium（需在收口前记录/裁定）** | `contracts/PermissionPort.ets:8-16`；`artifacts/40-detailed-design/des-001b-domain-presentation.md:6200,6390`；`app/PermissionPolicy.ets:14-49`；`app/PermissionGate.ets:22-24` | `EXT-DES-B-22` 列出的 `contracts/PermissionPort.ets` 应含 `PermissionPort`/`PermissionKind`/`PermissionResult`；实际 contracts 文件只有 VM-facing `PermissionKind`/`PermissionPort`，`PermissionResult` 与另一个同名 `PermissionPort` 仍在 `app/PermissionPolicy.ets`。DES-B §23.7 已把它登记为“同名技术债，不裁定”，但 T-23 报告 §2/§3.5 将 PORT-LOC-17 直接标“关闭”，未重申该残留。影响：PORT-LOC-17 的**物理位置**关闭成立，但 `EXT-DES-B-22` 的**文件形状**没有完全对齐；后续按 DES-B 在 contracts 使用 `PermissionResult` 会与 app 定义冲突。 | 在报告中明确“位置关闭、同名冲突仍按 DES-B §23.7 保留”；由 `solution-architect` 决定：将 C-23 VM 端口改名（如 `ProvisioningPermissionPort`）或把 `PermissionResult` 收敛到 contracts/独立文件，并同步 `BleViewModelPermissionGate`/host fake/文档。若维持现状，必须在 §7.2 记录为未关闭契约债，不能宣称 `EXT-DES-B-22` 完整实现。 |
| **F-04** | **Medium（工具/门禁）** | `tools/contract/check_layering.py:409-438,907-923`；DES-A §27.6.1 | `load_port_location_exceptions()` 未校验 `owner`/`close_condition`/`evidence` 非空；`pending-*` 端口例外未使用时不会单独失败（只有 used pending 失败）。当前唯一 PORT-LOC-01 字段齐全且 accepted，故不改变本次结果；但“schema is intentionally strict”与“不得以永久接受替代关闭”尚未由工具强制。 | 在 checker 中校验 owner/close_condition/evidence 非空并 fail closed；对任何 `pending-*` port exception 在 Gate 包装中失败（或至少 exit 1），补 fixture；保留 unused 报告用于审计。 |
| **F-05** | **Low（可维护性）** | `contracts/CryptoPort.ets:9-12`；`contracts/PreferencesStore.ets:11-14` | 两个已迁入 `contracts/**` 的文件头仍写着“仍留在 service/crypto/ 或 service/storage/ 的位置例外”，与实际路径和迁移结论矛盾；会误导后续维护者/评审。 | 更新文件头为迁移后的位置与契约说明；保留历史依据但不要写成现状。 |
| **F-06** | **Low（报告准确性）** | `artifacts/50-implementation/t23-ports-migration.md:12,48,198` | §1/§2 的“理由见 §6.1”应为 §7.1；§7.2 的 ohosTest 清单漏列两处 `LoggerPort`（实际 12 条 = 9 条失效模块 + `RandomPort` + `LoggerPort`×2）；总计数 7 文件/12 条本身正确。 | 修正交叉引用与清单；不改变已知缺口结论。 |
| **F-07** | **Info（登记/措辞）** | `tools/contract/layering_allowlist.json:6`；`viewmodel/core/ViewModelCore.ets:193-195`；`app/PermissionPolicy.ets:44` | allowlist policy 写“T-23 migrated all port declarations to contracts/**”；严格说 `VmTimerPort` 仍在 `viewmodel/core/ViewModelCore.ets`，C-28 的 `PermissionPort` 仍在 app（后者是 app seam，D-17 允许）。17 条登记范围本身完整，但“all port declarations”是过宽表述；也未登记 `VmTimerPort` 的位置/关闭条件。 | 把 policy 改为“17 条登记条目已迁移，仅 PORT-LOC-01 保留”；若要覆盖 `VmTimerPort`，另开 bounded inventory/登记任务，不在本迁移中静默扩大范围。 |

---

## 8. 残余风险、未执行项与后续任务

| 项 | 状态 | 影响/归属 |
|---|---|---|
| `contracts/TimerPort.ets` 与 DES-B `EXT-DES-B-01` 冲突 | **Open（F-01，Blocking）** | 需 `solution-architect` 裁定；在此之前不得宣告 17 条端口契约全部收口 |
| D-03 字面规则/checker 放宽 | **Open（F-02，Blocking）** | 需 Change Impact 或代码重构；当前 `violations=0` 不是 D-03 字面合规证据 |
| `PermissionPort`/`PermissionResult` 同名契约债 | **Recorded upstream（DES-B §23.7）/未关闭（F-03）** | Stage Gate 必须记录；不得写成 `EXT-DES-B-22` 完整实现 |
| 7 条 D-12 entries unused（01..05/09/10） | 已记录（报告 §7.2） | 待 DES-B §18.1 同步任务退休；当前 checker 报告可见 |
| `entry/src/ohosTest/**` 7 文件/12 条失效 import | **已知、未修复（out of write scope）** | `assembleHap`/host 不编译 ohosTest；设备测试前必须更新 imports（不改断言），建议 bounded follow-up |
| DES-A §27.6.2 17 条表、§2.1/§3.7 注记、DES-B §18.1 13 条表 | **STALE** | T-23 写范围不含 DES；报告 §7.3 已声明；Stage Gate 不得引用旧表作为迁移后状态 |
| `VmTimerPort` / `TimerPort` / `SceneTimerPort` 三个定时器 seam | **既有设计债** | `ViewModelCore.ets:188-196` 明确 `VmTimerPort` 与云 `TimerPort` 分离；需在 F-01 裁定中一并收敛或登记 |
| 设备/真实 BLE/LAN/云/TLS、ohosTest 运行 | **BLOCKED / NOT RUN** | 本任务范围不含；不写成 PASS |
| codelinter 25 warn、i18n 73 warning、crosscheck 14 findings | 既有基线（迁移前后同量级） | 未发现本次新增 error/blocking；交各自 Stage 处置 |

**后续任务建议（按优先级）**：

1. **F-01/F-02 契约裁定**：`solution-architect` 出具 Change Impact，明确 `TimerPort` 目标路径/形状与 D-03 同层 type-only 允许集；更新 DES-A/DES-B 的对应文字、checker 条件/消息、allowlist/report；随后重跑 host/build/lint/layering/i18n/crosscheck。
2. **F-03**：在报告中记录 `PermissionPort` 同名债；若改 contracts 形状，先做 C-28/C-23 影响分析，保持 `BleViewModelPermissionGate` 的单一所有权语义。
3. **F-04/F-05/F-06/F-07**：checker schema 硬化、stale header、报告交叉引用/清单、policy 措辞；可作为紧随的 bounded tooling/docs 任务。
4. **ohosTest**：紧随的 bounded 任务更新 7 文件 12 条 imports（I18nModels/GatewayTransportPorts/BleProvisioningPorts/GattEndpointMap/RdbStore/SecretStore/DomainModels/common/types/Ports 的 RandomPort·LoggerPort），不改断言；之后运行 ohosTest 编译/设备矩阵。
5. **DES 同步**：退休 7 条 unused D-12；更新 DES-A §27.6 关闭状态、§2.1/§3.7 注记、DES-B §18.1；Stage Gate 以更新后的表为准。

**修复后复审要求**：至少重跑本报告 §2 的 7 项命令；若 F-01/F-02 涉及代码/checker 改动，必须重新做 51 接口/24 类的签名比对、main/test import 解析和 0 环检查；若只改文档，仍需重跑 checker 与 fixture 以确认报告与工具一致。

---

## 9. 独立声明与裁决边界

1. 本评审由 `quality-reviewer` 独立完成；未参与 `wp-090-ports` 的实现、修复或报告撰写；未编辑任何被审代码、测试、checker、allowlist 或 DES 文本。唯一写入为 `artifacts/70-review/t23-review.md`（覆写 guard 前置占位）。
2. 评审基于 `aa9bdd1`（父 `1d4b202`）与 handoff 冻结输入；6 个输入 SHA-256 与 handoff 一致；工作树在评审前干净，评审期间未修改被审范围。
3. 复验命令均在本机实际执行：host 697/697、clean assembleHap BUILD SUCCESSFUL、codelinter 0 error/25 warn、check_layering 0 violation/6 used/0 pending、test_check_layering 12/12、i18n blocking 0/missing 0、crosscheck hard ALL PASS；自建 import resolver 0 missing（main/test）、221 文件 0 环、51 接口/24 类签名比对一致。
4. **Verdict 仅覆盖本报告 §1 的 revision 与范围**：`CHANGES_REQUIRED`（代码级）。本报告不授予 Stage Gate、IG-3/IG-4、用户验收；设备/真实 BLE/LAN/云/TLS 仍 BLOCKED；ohosTest 未编译/未运行。
5. 未发现作者自审替代；未发现越界产品代码/测试/契约改动；未发现秘密或构建产物入库；未把 `COMPILED_ONLY`/`BLOCKED` 写成 PASS。F-01/F-02 属契约/门禁阻断项，修复或取得上游书面裁定前不得把 A1 端口迁移写成“契约收口”。

```text
STATUS: COMPLETE
SUMMARY: 独立复审 aa9bdd1（A1 端口迁移）；17 条中 16 条位置例外关闭、PORT-LOC-01 保留理由成立；51 接口/24 类签名不变，main/test import 0 缺失、221 文件 0 环；host 697/697、clean assembleHap SUCCESS、codelinter 0 error/25 warn、layering 0 violation/6 used/0 pending、fixture 12/12、i18n blocking=0/missing=0、crosscheck hard ALL PASS。Verdict CHANGES_REQUIRED：contracts/TimerPort.ets 与 DES-B EXT-DES-B-01 形状冲突；D-03 字面规则被 checker 同层放宽且报告误称只允许 common/model；PermissionPort/PermissionResult 同名债未在报告中重申；另有 checker schema/报告交叉引用等低风险项。
ARTIFACTS_CREATED: artifacts/70-review/t23-review.md
ARTIFACTS_UPDATED: artifacts/70-review/t23-review.md（覆写 guard 占位）
RISKS: F-01 TimerPort 契约冲突（Blocking）；F-02 D-03 字面/checker 放宽（Blocking）；F-03 PermissionPort 同名债（Medium）；F-04 checker schema（Medium）；F-05 stale comments（Low）；F-06 report refs（Low）；F-07 all-port policy wording（Info）；ohosTest 7/12 失效 import；DES-A §27.6/DES-B §18.1 未同步；设备/BLE/LAN/云/TLS BLOCKED
VALIDATION: host 697/697 exit 0；clean assembleHap BUILD SUCCESSFUL 16s274 exit 0；codelinter Errors 0/Warns 25 exit 0；check_layering files=221 violations=0 exceptions_used=6 pending=0 port_exceptions_used=0 exit 0；test_check_layering Ran 12 OK exit 0；i18n blocking=0 warnings=73 missingKeys=0 hardcoded=16 exit 0；crosscheck hard ALL PASS 14 findings exit 0；main/test missing imports 0；221 files cycles 0；51 interfaces/24 classes unchanged
NEEDS_CLARIFICATION: F-01 TimerPort 目标契约形状与 F-02 contracts→contracts 允许集需 solution-architect 裁定；F-03 PermissionPort 同名债收敛方式
NEXT_ACTION: 先取得 F-01/F-02 上游裁定并修复/同步 checker、imports、报告；再修 F-03/F-04/F-05/F-06/F-07，重跑 §2 全部命令；另开 ohosTest import 与 DES 同步 bounded 任务后复评
```
