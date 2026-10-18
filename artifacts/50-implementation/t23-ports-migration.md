# T-23 端口位置迁移报告（P1-P3 / 16/17 关闭，PORT-LOC-01 OPEN）

- **Artifact ID**: T23-PORTS-MIGRATION
- **Producer**: agent:implementation-engineer
- **Task**: `wp-090-ports`（Handoff `state/handoffs/wp-090-ports.json`）
- **Branch**: `task/wp-090-ports`（base/parent `feat/yaocore-app`，base commit `1d4b202`）
- **Inputs**: `artifacts/40-detailed-design/des-001a-foundation-transport.md` §2.1/§3.7/§27.6、`artifacts/40-detailed-design/des-001b-domain-presentation.md` §18.1、`tools/contract/check_layering.py`、`tools/contract/layering_allowlist.json`、`artifacts/60-testing/test-plan.md`、`entry/src/test/run-host-tests.sh`（SHA-256 与 handoff 冻结值一致）
- **Status**: **COMPLETE（代码/构建/主机测试/检查器通过；待独立复审）**
- **Date**: 2026-10-18
- **Workflow**: STANDARD / GATED_AUTO

> **文档勘误（agent:technical-writer，wp-110，2026-10-18）**：本报告是 T-23 原始实现报告，**Producer 保留 `agent:implementation-engineer`**；§10 的 `wp-093` 执行记录同样保留。以下勘误只修正“文首 / §1 / §5 / §6 / §7.2 的旧口径”，不改变 T-23 首次交付与 wp-093 修复的历史事实，也不改写 §10：
>
> 1. **标题**：原“关闭 17 条端口位置例外”与正文“16 条关闭、1 条保留”不一致；以 **16/17 关闭、PORT-LOC-01 OPEN** 为准。
> 2. **layering 12/12**：原文把 `test_check_layering.py` 的 12 条 fixture 写成“layering 12/12”。`check_layering` 本体结果是 `files=221 / violations=0 / exceptions_used=6 / port_exceptions_used=0`；fixture 在 T-23 时 12 条，wp-093 后 22 条，**TEST-002 / G-016 最终为 27/27**。
> 3. **八项命令**：见 §6 与 §10.3；原文列举不完整。当前最终证据以 **TEST-002 @ `e74a181`** 为准。
> 4. **ohosTest**：§7.2 原写“未修复”；wp-093 §10.2 已修复 7 文件 / 12 条 import 并使 ohosTest HAP 编译通过。**设备运行仍 BLOCKED**，不写成设备 PASS。
> 5. **D-12 历史条目**：§5.2 原写“13 条保持不变、7 条 unused 留待退休”；wp-093 §10.1 F-07 已把 live allowlist prune 为 **6 active + 7 retired**，`exceptions_used=6`、`unused_exceptions=[]`。
> 6. **PORT-LOC-01**：`ClockPort`/`IdPort` 仍留在 `common/types/Ports.ets`，**OPEN**；不得写成“全部关闭”。

> **结论先行（保留原文；以 §10 与上方勘误为最终状态）**：按 DES-A §27.6.3 P1-P3 建立 `entry/src/main/ets/contracts/**`，迁移 16 个端口/契约文件与 1 个纯映射 seam；17 条 `port_location_exceptions` 中 **16 条关闭**，仅保留 **PORT-LOC-01** 的 `ClockPort`/`IdPort`（原因见 §7.1）。混合文件按“端口→`contracts/**`、DTO/枚举→`model/**`”拆分，`check_layering` 删除全部硬编码端口路径放行，改为只读版本化登记；`violations=0`、`port_exceptions_used=0`。八项必跑命令（见 §6）全部退出 0：`ohpm install`、`assembleHap` BUILD SUCCESSFUL、codelinter 0 error、host **697/697**、`check_layering` files=221/violations=0、`test_check_layering` 12/12（当时）、i18n blocking=0/missing=0、crosscheck hard checks ALL PASS。未改冻结端口签名、错误码、G-004 语义或 DES 文档。

---

## 1. 盘点结果（迁移前）

> **现状提示（wp-110 勘误）**：本节记录的是 T-23 **迁移前**的 17 条盘点，不是当前状态。迁移结果：**16/17 关闭，PORT-LOC-01 OPEN**；最终以 §10 与 DES-A §27.6.4 为准。

17 条登记与 DES-A §27.6.2 逐条一致；盘点确认 `contracts/**` 在迁移前不存在，端口实际分布在 `common/types/**`、`service/**`、`repository/**`、`viewmodel/**`。迁移同时清除了端口间接造成的 `service/** → repository/**` 反向可见性（`GatewayTransportPorts -> GatewayPorts`、`DomainPorts -> RdbStore`）。

| ID | 原路径 | kind | 迁移前使用方（摘要） |
|---|---|---|---|
| PORT-LOC-01 | `common/types/Ports.ets` | port-only | 63 个文件/72 条 import |
| PORT-LOC-02 | `service/crypto/CryptoPort.ets` | mixed-contract-dto | 22 条 import |
| PORT-LOC-03 | `service/storage/RdbStore.ets` | port-only | 17 条 import |
| PORT-LOC-04 | `service/storage/PreferencesStore.ets` | port-only | 9 条 import |
| PORT-LOC-05 | `service/storage/SecretStore.ets` | mixed-contract-dto | 7 条 import |
| PORT-LOC-06 | `service/storage/SecretDraftPort.ets` | port-only | 7 条 import |
| PORT-LOC-07 | `service/storage/MigrationPort.ets` | port-only | 8 条 import |
| PORT-LOC-08 | `service/ble/BleProvisioningPorts.ets` | mixed-contract-dto | 15 条 import（pages/VM 含 D-12 值 import） |
| PORT-LOC-09 | `service/ble/GattEndpointMap.ets` | pure-seam | 5 条 import |
| PORT-LOC-10 | `service/gateway/GatewayTransportPorts.ets` | mixed-contract-dto | 21 条 import |
| PORT-LOC-11 | `service/gateway/DiscoveryModels.ets` | mixed-contract-dto | 6 条 import |
| PORT-LOC-12 | `service/cloud/CloudPorts.ets` | port-only | 7 条 import |
| PORT-LOC-13 | `service/i18n/I18nPorts.ets` | port-only | 3 条 import |
| PORT-LOC-14 | `service/scene/SceneTimerPort.ets` | port-only | 4 条 import |
| PORT-LOC-15 | `repository/DomainPorts.ets` | port-only | 11 条 import |
| PORT-LOC-16 | `repository/GatewayPorts.ets` | mixed-contract-dto | 17 条 import |
| PORT-LOC-17 | `viewmodel/ViewModelPorts.ets` | mixed-contract-dto | 11 条 import |

---

## 2. 17 条迁移对照表

> 端口文件保持在 `contracts/**` 扁平命名（与 DES-A §2.1/§3.7/§27.6.3 的关闭条件一致）；DTO/枚举进入 `model/**`，避免 `contracts/**` 依赖 `repository/**`/`service/**`（D-03）。

| ID | 原路径 | 新位置 | 结果 |
|---|---|---|---|
| PORT-LOC-01 | `common/types/Ports.ets` | `contracts/Ports.ets`（`RandomPort`/`LoggerPort`/`MetricsPort`/`HmacSignerPort`）+ `common/types/CancellationToken.ets`（`CancellationToken`）；**保留** `common/types/Ports.ets`（`ClockPort`/`IdPort`） | **部分关闭**；保留 1 条，理由 §7.1 |
| PORT-LOC-02 | `service/crypto/CryptoPort.ets` | `contracts/CryptoPort.ets`（`CryptoPort` + X25519/AES/GCM 值类型） | 关闭 |
| PORT-LOC-03 | `service/storage/RdbStore.ets` | `contracts/RdbStore.ets` | 关闭 |
| PORT-LOC-04 | `service/storage/PreferencesStore.ets` | `contracts/PreferencesStore.ets` | 关闭 |
| PORT-LOC-05 | `service/storage/SecretStore.ets` | `contracts/SecretStore.ets`（端口）+ `common/types/SecretAlias.ets`（值 helper） | 关闭 |
| PORT-LOC-06 | `service/storage/SecretDraftPort.ets` | `contracts/SecretDraftPort.ets` | 关闭 |
| PORT-LOC-07 | `service/storage/MigrationPort.ets` | `contracts/MigrationPort.ets` | 关闭 |
| PORT-LOC-08 | `service/ble/BleProvisioningPorts.ets` | `contracts/BleProvisioningPorts.ets`（6 个端口/监听器）+ `model/ProvisioningModels.ets`（12 个 DTO/枚举） | 关闭；D-12 09/10 不再使用 |
| PORT-LOC-09 | `service/ble/GattEndpointMap.ets` | `model/GattEndpointMap.ets`（纯映射，非端口） | 关闭 |
| PORT-LOC-10 | `service/gateway/GatewayTransportPorts.ets` | `contracts/GatewayTransportPorts.ets`（3 个端口）+ `model/GatewayTransportModels.ets`（6 个 DTO） | 关闭 |
| PORT-LOC-11 | `service/gateway/DiscoveryModels.ets` | `model/DiscoveryModels.ets`（6 个模型/枚举）+ `contracts/DiscoveryTransport.ets`（`DiscoveryTransport`；并收敛 `ManualDiscoveryPort`） | 关闭 |
| PORT-LOC-12 | `service/cloud/CloudPorts.ets` | `contracts/CloudPorts.ets`（3 个端口）+ `contracts/TimerPort.ets`（`TimerPort`） | 关闭 |
| PORT-LOC-13 | `service/i18n/I18nPorts.ets` | `contracts/I18nPorts.ets`；`I18nModels.ets` 同步迁至 `model/I18nModels.ets` | 关闭 |
| PORT-LOC-14 | `service/scene/SceneTimerPort.ets` | `contracts/SceneTimerPort.ets` | 关闭 |
| PORT-LOC-15 | `repository/DomainPorts.ets` | `contracts/RoomPorts.ets`（4 个）、`contracts/ScenePorts.ets`（1 个）、`contracts/DevicePorts.ets`（3 个） | 关闭；端口反向依赖消除 |
| PORT-LOC-16 | `repository/GatewayPorts.ets` | `contracts/GatewayPorts.ets`（6 个接口）+ `model/InvitedGateway.ets`（值对象） | 关闭 |
| PORT-LOC-17 | `viewmodel/ViewModelPorts.ets` | `contracts/ControlPorts.ets`（`DeviceControlCoordinatorPort`）、`contracts/PermissionPort.ets`（`PermissionKind`/`PermissionPort`）、`contracts/DiscoveryTransport.ets`（`ManualDiscoveryPort`） | 关闭；`ManualDiscoveryPort` 与 C-18 收敛 |

**关闭计数**：17 条中 16 条完全关闭，1 条（PORT-LOC-01）保留为 `ClockPort`/`IdPort` 的受控位置例外。`layering_allowlist.json` 的 `port_location_exceptions`：**17 → 1**。

### 2.1 为满足 D-03 同步落位的 DTO（不属于 17 条端口例外）

`contracts/**` 只允许 import `common/**`、`model/**`，以及 **type-only 且无环**的同层 `contracts/**`（T-23 F-02 裁定，见 DES-A §2.2/附录 E §E.3）；以下 DTO/值类型必须随端口迁移离开 `repository/**`/`service/**`/`viewmodel/**`，否则新 `contracts/**` 会立即触发 D-03：

| 原路径 | 新位置 | 内容 | 影响 |
|---|---|---|---|
| `repository/DomainModels.ets` | `model/DeviceRecord.ets` | `DeviceRecord`/merge/discover/control-apply/removal 等 15 个类型 | 关闭 D-12 01..05 的使用；pages/components 改为直接 import `model/**` |
| `repository/DomainModels.ets` | `model/SceneExecutionModels.ets` | `SceneRunState`/`SceneStepResult`/`SceneExecution*` 等 8 个类型 | 关闭 D-12 04/05 |
| `service/cloud/CloudModels.ets` | `model/CloudControlModels.ets` | `CloudCommandReceipt`/`CloudCompletion`/`CloudCompletionVerdict`/`CloudControlOutcome` | `ControlExecution` 不再依赖 `service/cloud` |
| `viewmodel/core/ViewModelCore.ets` | `model/ControlExecution.ets` | `ControlExecution`、`ControlTransport` | `contracts/ControlPorts.ets` 可只依赖 `model/**` |
| `service/i18n/I18nModels.ets` | `model/I18nModels.ets` | i18n 值对象/枚举 | pages/components/service 统一 import `model/**` |

---

## 3. 符号级拆分明细

### 3.1 PORT-LOC-08（BLE）

- **端口（`contracts/BleProvisioningPorts.ets`）**：`BleScanListener`、`BleProvisioningProgressListener`、`IBleProvisioningClient`、`BleConnection`、`BleTransport`、`BlePermissionGate`。
- **DTO/枚举（`model/ProvisioningModels.ets`）**：`ProvisioningState`、`BleProvisioningStage`、`BleProvisioningDevice`、`BleScanDevice`、`BleScanFilter`、`WifiAp`、`ProvisioningProgress`、`BleProvisioningRequest`、`BleWifiScanRequest`、`BleServiceRef`、`BleCharacteristicRef`、`BleDescriptorRef`。
- 页面/VM 改为 import `model/ProvisioningModels`；`ProvisioningPage` 不再从 `service/ble` 读取 DTO/枚举。

### 3.2 PORT-LOC-10（Gateway transport）

- **端口（`contracts/GatewayTransportPorts.ets`）**：`HttpTransport`、`TlsPinVerifier`、`IGatewayClient`。
- **DTO（`model/GatewayTransportModels.ets`）**：`HttpRequest`、`TlsVerification`、`HttpResponse`、`TlsPolicy`、`GatewayTarget`、`ProbeResult`。
- `contracts/GatewayTransportPorts` 通过 `contracts/GatewayPorts` 引用 `GatewayCredentialPort`，不再 import `repository/**`。

### 3.3 PORT-LOC-11（Discovery）

- **模型（`model/DiscoveryModels.ets`）**：`DiscoverySource`、`DiscoveryTransportKind`、`DiscoveryCandidate`、`DiscoveryOptions`、`DiscoveryReport`、`DiscoveryBeacon`（与既有 `DiscoverySnapshot` 合并）。
- **端口（`contracts/DiscoveryTransport.ets`）**：`DiscoveryTransport`、`ManualDiscoveryPort`。
- `DiscoveryOptions.cancellation` 使用 `common/types/CancellationToken`（DES-A §2.1 目标布局），不引入 model→contracts 反向依赖。

### 3.4 PORT-LOC-15（Domain ports）

- `contracts/RoomPorts.ets`：`RoomLookupPort`、`DeviceAssignmentPort`、`RoomDeviceNamePort`、`MemberRoomGrantPort`。
- `contracts/ScenePorts.ets`：`SceneReferencePort`。
- `contracts/DevicePorts.ets`：`DeviceControlPort`、`DeviceStatePort`、`DeviceRecordQueryPort`。
- 事务类型统一引用 `contracts/RdbStore`；DTO 统一引用 `model/**`；`repository/**` 不再 import `service/storage/**`。

### 3.5 PORT-LOC-16/17

- `contracts/GatewayPorts.ets` 仅保留 6 个接口；`InvitedGateway` 移至 `model/InvitedGateway.ets`，`repository`/`service` 不再需要从契约文件取值类。
- `contracts/ControlPorts.ets` / `contracts/PermissionPort.ets` / `contracts/DiscoveryTransport.ets` 分别承载控制协调器、权限、手工发现端口；`viewmodel/ViewModelPorts.ets` 删除。

---

## 4. Import 更新与文件变更

| 指标 | 数值 |
|---|---|
| 既有文件改写 | **125** 个（`entry/src/main/ets` + `entry/src/test`） |
| 新增源文件 | **30** 个（`contracts/**` 20、`model/**` 8、`common/types/**` 2） |
| 删除旧文件 | **18** 个（17 条登记文件 + `repository/DomainModels.ets` 拆分源） |
| import 语句改写 | 既有文件新增 **394** 条 / 删除 **318** 条（混合文件拆分会产生多条新 import） |
| 受影响层 | service、repository、app、viewmodel、pages、components、host tests、storage/i18n/security host tests |
| 未改动 | 端口方法名/参数/返回/错误语义；页面/组件/VM 运行时逻辑；冻结契约文本 |

代表性更新：

- `common/types/Ports` 的 63 个使用文件按符号拆为 `common/types/Ports`（Clock/Id）、`contracts/Ports`（Random/Logger/Metrics/HmacSigner）、`common/types/CancellationToken`。
- `pages/ProvisioningPage`、`viewmodel/BleProvisioningViewModel` 改为 DTO 从 `model/ProvisioningModels`、端口从 `contracts/BleProvisioningPorts`。
- `pages/ScenePage`、`components/**`、`viewmodel/**`、`repository/**` 的 `repository/DomainModels` import 按符号拆到 `model/DeviceRecord` / `model/SceneExecutionModels`。
- 测试侧同步更新 `entry/src/test/host/*.test.mjs`、`entry/src/test/{storage,i18n,security,domain}/**`；`TransportBoundary.test.mjs` 的纯逻辑文件清单改为迁移后的 `contracts/**`/`model/**` 路径，断言不变。

---

## 5. 检查器与白名单收口

### 5.1 `tools/contract/check_layering.py`

- 元数据/状态从 T-20 更新为 **T-23 / wp-090-ports**；docstring 明确 `contracts/**` 为规范端口位置，仓库层/VM/UI 可直接 import。
- 保留并继续强制 `port_location_exceptions` 读取：精确路径、非空 `symbols` 子集、`accepted-location-exception` 状态；未登记端口路径仍按 D-09/D-11 失败。**无任何硬编码端口路径放行**。
- 删除迁移后失效的硬编码 DTO 放行：`_is_pages_repository_dto`、`_is_components_repository_dto`。迁移后 `pages/**`/`components/**` 不得再 import `repository/**`；只读 DTO 走 `model/**`（D-12 本身允许）。
- `service/i18n` 白名单移除已迁走的 `I18nModels.ets`（`I18nService.ets`、`I18nKeys.ets` 保留）；页面/组件 import `model/I18nModels` 不再需要 service 例外。
- `port_location_exceptions` 仍只替代 D-09/D-11 端口路径判断；D-12 由 `entries` 独立控制，两者取更严格者。

### 5.2 `tools/contract/layering_allowlist.json`

- `producer`/`task`/`policy` 更新为 T-23；`policy` 记录迁移完成状态与唯一保留条目。
- `port_location_exceptions` 删除 16 条已完成迁移条目，保留 **PORT-LOC-01**（`ClockPort`、`IdPort`；`kind: port-only`；`status: accepted-location-exception`；close condition 改为需上游 D-01/冻结签名变更）。
- 13 条 D-12 `entries` 在 T-23 首次迁移提交中保持 `accepted`；迁移后使用数 **13 → 6**（仅 `T20-D12-06/07/08/11/12/13` 仍被使用；`01..05/09/10` 变为 unused）。**【勘误】wp-093 §10.1 F-07 已从 live allowlist 删除 7 条 retired，最终 `entries=6`、`exceptions_used=6`、`unused_exceptions=[]`；历史 13 条仅保留在 DES-B §18.1 与 Git 历史。**

### 5.3 Fixture / 自测

- 新增 `tools/contract/fixtures/layering/post-migration/`：合法树，`repository`/`viewmodel`/`pages` 直接 import `contracts/**` 与 `model/**`，空端口登记通过、`port_exceptions_used=0`。
- 新增 `tools/contract/fixtures/layering/post-migration-bad/`：空端口登记下，`repository -> service/storage`（D-09）、`viewmodel -> service/storage`（D-11）、`pages -> service/room`（D-12）全部失败，并报告 “not registered in port_location_exceptions”。
- 既有 legal / bad / pending / symbol-overflow / wildcard 负例保留；`test_check_layering.py` 更新仓库期望为 `exceptions_used=6`、`port_exceptions_used=0`、登记数 1，并新增 2 条 post-migration 测试（T-23 时共 **12** 条，全部通过；wp-093 后 22 条；TEST-002 最终 27/27）。

---

## 6. 验证矩阵（实际执行）

| # | 命令 | 退出码 | 关键结果 |
|---|---|---|---|
| 1 | `ohpm install` | 0 | install completed |
| 2 | `hvigorw clean assembleHap --no-daemon` | 0 | **BUILD SUCCESSFUL**（14 s 723 ms） |
| 3 | `codelinter -c code-linter.json5 -p default .` | 0 | **Errors: 0**；Warns 25（迁移前既有的性能/自定义组件告警） |
| 4 | `entry/src/test/run-host-tests.sh` | 0 | **tests 697 / pass 697 / fail 0**（与迁移前 697 持平） |
| 5 | `python3 tools/contract/check_layering.py` | 0 | files=221 **violations=0** exceptions_used=6 pending=0 **port_exceptions_used=0** |
| 6 | `python3 tools/contract/test_check_layering.py` | 0 | **Ran 12 tests / OK**（T-23 当时；wp-093 后 22；TEST-002 最终 27/27） |
| 7 | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | 0 | blockingFailures=0 missingKeys=0 hardcoded=16（迁移前既有 warning，73 条） |
| 8 | `python3 tools/contract/crosscheck_protocol_assets.py` | 0 | **hard checks: ALL PASS**；14 条 frozen-input findings（既有，不因迁移变化） |

补充静态核对：

- 旧 17 条路径中 16 个文件已不存在；`common/types/Ports.ets` 仅保留 `ClockPort`/`IdPort`（24 行）。
- 全仓相对 import 解析：`entry/src/main/ets` + `entry/src/test` 无 missing module（0）。
- `viewmodel/**` 不再 import `service/{gateway,ble,crypto,storage}`；`repository/**` 不再 import `service/storage/**`。

---

## 7. 偏差、风险与残余

### 7.1 保留的端口位置例外（PORT-LOC-01）

`ClockPort`/`IdPort` 仍位于 `common/types/Ports.ets`，原因不是遗漏：

1. 冻结签名 `DateTimeUtil.nowUtcCompact(clock: ClockPort)` 与 `UuidUtil.newUuid(ids: IdPort)` 位于 `common/utils/**`（DES-A §4.1.5/§4.4）。
2. D-01 规定 `common/**` 不得 import `contracts/**`；若把两个端口移入 `contracts/**`，必须修改 D-01 或上述冻结签名。
3. DES-A §27.6.3 明确禁止“复制一套端口”；因此在无上游裁定的情况下，保留 1 条符号级例外是唯一不产生重复定义的方案。
4. 该条目在 checker 中 `used=0`（D-09/D-11 不限制 common 目标），但作为架构登记保留，close condition 已改为“需 D-01 或冻结签名变更”。

**建议**：由 `solution-architect` 在后续契约任务中裁定是否允许 `common/**` type-only import `contracts/**`；若允许，可移动这两个端口并删除最后一条例外。

### 7.2 残余风险

> **状态说明（wp-110 勘误）**：下表前两行是 T-23 首次交付时的残余；**ohosTest import 已由 wp-093 §10.2 修复**，**7 条 D-12 已由 wp-093 §10.1 F-07 退休并从 live allowlist 删除**。保留原文以记录历史，最终状态以 §10 为准。

| 风险 | 影响 | 处置 |
|---|---|---|
| `entry/src/ohosTest/**` 未在本次写范围，仍有 7 个文件/12 条旧路径 import（I18nModels、GatewayTransportPorts、BleProvisioningPorts、GattEndpointMap、RdbStore、SecretStore、DomainModels、common/types/Ports 的 RandomPort 与 LoggerPort×2；9 条失效模块 + `RandomPort` + `LoggerPort`×2） | `assembleHap`/host 测试不编译 ohosTest，本次验证不受影响；设备测试编译会失败 | **已由 wp-093 §10.2 关闭**：12 条 import 已修正，ohosTest HAP 编译通过；设备运行仍 **BLOCKED**，不写成设备 PASS |
| 7 条 D-12 entries 变为 unused（T20-D12-01..05/09/10） | 白名单保留历史条目，与 DES-B §18.1 当前文本一致 | **已由 wp-093 §10.1 F-07 处理**：live allowlist 删除 7 条 retired，保留 6 条 active；`exceptions_used=6`、`unused_exceptions=[]`；历史仅保留在 DES-B/Git |
| `service/**` 仍 import `repository/**` 用例实现（`FamilyService`/`SceneService` 等） | 这是用例→仓储的正常依赖，不是端口反向可见性；D-09 仅禁止 repository→service | 记录为架构既有形态，不在本任务扩大范围 |
| codelinter 25 条 warn / i18n 73 条 warning / crosscheck 14 条 frozen-input findings | 均为迁移前既有；本次未新增 error/blocking | 保持基线，交由各自 Stage 处置 |

### 7.3 未执行项

- 设备/模拟器 ohosTest、真实 BLE、真实网关：本任务验证范围不含，保持 **BLOCKED/NOT RUN**。
- 未修改 DES-A/DES-B 文本（§27.6 表格关闭状态与 §2.1/§3.7 注记需由契约同步任务更新）。

---

## 8. 追溯

| 输入/契约 | 落实 |
|---|---|
| DES-A §27.6.2 PORT-LOC-01..17 | §2 对照表逐条映射；16 关闭，1 保留并说明 |
| DES-A §27.6.3 P1 | 16 个端口文件迁入 `contracts/**`；`common/types/Ports.ets` 拆分 |
| DES-A §27.6.3 P2 | BLE/Gateway/Discovery/SecretStore/GatewayPorts/ViewModelPorts 拆分端口与 DTO |
| DES-A §27.6.3 P3 | `GattEndpointMap` → `model/GattEndpointMap.ets`（非端口） |
| DES-A §27.6.3 P4 | checker 读取登记、无硬编码端口路径、新增 post-migration 正/负 fixture |
| DES-A §2.1/§3.7 | `contracts/**` 目标布局；DTO 落 `model/**` |
| DES-B §18.1 D-12 | 13 条 entries 保留；使用数降至 6；post-migration 后 pages/components 不再 import repository |
| DES-B §2.3 D-01..D-17 | build + layering `violations=0`；D-03 在 `contracts/**` 存在后真正生效 |

---

## 9. 复现命令

```bash
ohpm install
hvigorw clean assembleHap --no-daemon
codelinter -c code-linter.json5 -p default .
entry/src/test/run-host-tests.sh
python3 tools/contract/check_layering.py
python3 tools/contract/test_check_layering.py
python3 entry/src/test/i18n/check_i18n.py --strict-ui
python3 tools/contract/crosscheck_protocol_assets.py
```

---

## 10. T-23 裁定修复执行记录（2026-10-18，wp-093）

> **性质**：按 `artifacts/40-detailed-design/des-001a-foundation-transport.md` / `des-001b-domain-presentation.md` **附录 E**（commit `76c47f4`）逐条落地 F-01..F-07 与 ohosTest import 修复。**边界**：只改 `entry/src/main/ets/**`、`entry/src/test/**`、`entry/src/ohosTest/**`、`tools/contract/**`、`artifacts/50-implementation/**`；不改 DES 文本、冻结签名、错误码或 G-004 语义。**Harness**：`task/wp-090-ports`，base `76c47f4`。

### 10.1 逐条实现

| Finding | 实现位置 | 结果 |
|---|---|---|
| **F-01** `TimerPort` 归属 | `contracts/TimerPort.ets` 文件头删除 `EXT-DES-B-01` 错误引用，写明 C-15 云轮询 `sleep/cancel`；`VmTimerPort` 指向 DES-B §23.1 `EXT-DES-B-33`；`SceneTimerPort.ets` 与 `viewmodel/core/ViewModelCore.ets` 的 `VmTimerPort` 声明注释同步“三分保留” | 仅注释；`TimerPort.sleep/cancel` 签名未变；`grep -R "scheduleOnce\|scheduleRepeating\|TimerHandle" entry/src/main/ets entry/src/test` 无命中 |
| **F-02** D-03 type-only/无环 | `tools/contract/check_layering.py`：`contracts/**` 同层仅接受 `import type`/`export type`；值/副作用/namespace 值导入报 D-03；新增 contracts 同层有向图 DFS 环检测（含 type-only 边，每环报一次） | 现有 4 条 type-only 边保留未写；repo `violations=0`；新增 `contracts-type-only-ok`、`value-import-bad`、`side-effect-bad`、`cycle-bad` fixture |
| **F-03** C-23 符号重命名 | `contracts/PermissionPort.ets` → `ProvisioningPermissionPort`/`ProvisioningPermissionKind`，不导出 `PermissionResult`；`viewmodel/BleProvisioningViewModel.ets`、`app/PermissionGate.ets`、`entry/src/test/host/ViewModelBle.test.mjs` 同步；`app/PermissionPolicy.ets` 的 C-28 `PermissionPort`/`PermissionKind`/`PermissionState`/`PermissionResult` 未改 | `grep -R "export interface PermissionPort\|export enum PermissionKind" entry/src/main/ets/contracts` 无命中；`BleViewModelPermissionGate` 仍是唯一适配器；host ViewModelBle 通过 |
| **F-04** 例外元数据/pending | `load_port_location_exceptions()`：`id` 非空唯一，`owner`/`reason`/`close_condition`/`evidence` 去空白非空；畸形 → `ValueError` → exit 2；`main()` 对任何 `pending-*`（used 或 unused）exit 1，保留 `used && status != accepted` 路径 | 新增 `missing-owner`/`missing-close-condition`/`missing-evidence`/`missing-id`/`duplicate-id`（exit 2）与 `pending-unused`（exit 1）fixture；`port_pending=0` |
| **F-05** 陈旧文件头 | `contracts/CryptoPort.ets`、`contracts/PreferencesStore.ets` 删除“仍留在 service/**”段落，改为“T-23 已迁移、历史例外关闭、不得在旧目录重建副本” | 仅注释；无接口/字段变更 |
| **F-06** 报告勘误 | 本报告 §1/§2 的“§6.1” → “§7.1”；§2.1 改为“common/model + contracts type-only 无环”；§7.2 ohosTest 清单补 `LoggerPort`×2（7 文件/12 条 = 9 模块失效 + `RandomPort` + `LoggerPort`×2）；本 §10 记录执行结果 | 交叉引用与清单一致；不改变原结论 |
| **F-07** allowlist policy | `tools/contract/layering_allowlist.json` 删除 7 条 retired D-12（`T20-D12-01..05/09/10`），保留 6 条 active；`policy` 按附录 E §E.6 文本更新（PORT-LOC-01 保留；`VmTimerPort` 为 VM 本地 seam；C-28 app seam 说明） | `entries=6`、`exceptions_used=6`、`unused_exceptions=[]`；`port_location_exceptions=1`（仅 PORT-LOC-01） |

### 10.2 ohosTest import 修复（7 文件 / 12 条原失效 import）

| 文件 | 原 import | 新 import |
|---|---|---|
| `viewmodel/ViewModelsDevice.test.ets` | `service/i18n/I18nModels`（`SupportedLocale`） | `model/I18nModels` |
| `gateway/GatewayTransportDevice.test.ets` | `service/gateway/GatewayTransportPorts`（`HttpRequest`/`TlsPolicy`） | `model/GatewayTransportModels` |
| `storage/StorageDevice.test.ets` | `service/storage/SecretStore`（`SecretAlias`） | `common/types/SecretAlias` |
| `storage/StorageDevice.test.ets` | `service/storage/RdbStore`（`RdbTransaction`） | `contracts/RdbStore` |
| `ble/BleProvisioningDevice.test.ets` | `service/ble/BleProvisioningPorts`（`BlePermissionGate`） | `contracts/BleProvisioningPorts` |
| `ble/BleProvisioningDevice.test.ets` | 同上语句的 `BleCharacteristicRef` | `model/ProvisioningModels`（混合语句按符号拆分） |
| `ble/BleProvisioningDevice.test.ets` | `service/ble/GattEndpointMap` | `model/GattEndpointMap` |
| `ble/BleProvisioningDevice.test.ets` | `common/types/Ports`（`RandomPort`） | `contracts/Ports` |
| `cloud/CloudDevice.test.ets` | `service/gateway/GatewayTransportPorts`（`HttpRequest`/`TlsPolicy`） | `model/GatewayTransportModels` |
| `domain/DomainDevice.test.ets` | `repository/DomainModels`（`DiscoverApplyOptions`） | `model/DeviceRecord` |
| `domain/DomainDevice.test.ets` | `common/types/Ports`（`LoggerPort`） | `contracts/Ports` |
| `i18n/I18nDevice.test.ets` | `common/types/Ports`（`LoggerPort`） | `contracts/Ports` |
| `i18n/I18nDevice.test.ets` | `service/i18n/I18nModels` | `model/I18nModels` |

- `ClockPort`/`IdPort` 仍从 `common/types/Ports` import（PORT-LOC-01，3 个文件），不属于失效路径。
- 静态检索：`grep -REn "from ['\"][^'\"]*(service/i18n/I18nModels|service/gateway/GatewayTransportPorts|service/ble/BleProvisioningPorts|service/ble/GattEndpointMap|service/storage/RdbStore|service/storage/SecretStore|repository/DomainModels)(\.ets)?['\"]" entry/src/ohosTest` → **0**；ohosTest 全部相对 import 解析缺失 **0/122**。
- 未改任何断言/测试语义；`BleCharacteristicRef` 的拆分由 ohosTest 编译错误发现并修正（该 DTO 属 `model/**`，端口文件只 import type）。

### 10.3 验证矩阵（wp-093 实际执行）

| # | 命令 | 退出码 | 关键结果 |
|---|---|---|---|
| 1 | `ohpm install` | 0 | install completed |
| 2 | `hvigorw clean assembleHap --no-daemon` | 0 | **BUILD SUCCESSFUL**（14 s 976 ms） |
| 3 | `codelinter -c code-linter.json5 -p default .` | 0 | **Errors: 0**；Warns 25（迁移前既有） |
| 4 | `entry/src/test/run-host-tests.sh` | 0 | **tests 697 / pass 697 / fail 0** |
| 5 | `python3 tools/contract/check_layering.py` | 0 | files=221 **violations=0** exceptions_used=6 pending=0 **port_exceptions_used=0** port_pending=0 |
| 6 | `python3 tools/contract/test_check_layering.py` | 0 | **Ran 22 tests / OK**（含 4 条 D-03、6 条 F-04 fixture 用例） |
| 7 | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | 0 | blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16（既有基线） |
| 8 | `python3 tools/contract/crosscheck_protocol_assets.py` | 0 | **hard checks: ALL PASS**；14 条 frozen-input findings（既有） |
| 9 | `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | 0 | **BUILD SUCCESSFUL**（13 s 233 ms）；ohosTest 编译通过 |

### 10.4 残余与风险

- **PORT-LOC-01 仍为 OPEN**：`ClockPort`/`IdPort` 留在 `common/types/Ports.ets`，关闭条件不变（需批准的 D-01 或冻结签名变更）；不得写成“17 条全关闭”。
- **D-12 历史保留**：7 条 retired 条目只在 live allowlist 删除；DES-B §18.1 历史表与旧 JSON 证据保留，Stage Gate 记录“6 active / 7 retired”。
- **设备运行未执行**：ohosTest 仅完成编译；设备/模拟器、真实 BLE/网关仍 **BLOCKED/NOT RUN**。
- **基线告警**：codelinter 25 warn、i18n 73 warning/16 hardcoded、crosscheck 14 findings 均与迁移前一致，本任务未新增 error/blocking。
- **F-01 三分**：未合并 `TimerPort`/`VmTimerPort`/`SceneTimerPort`；`VmTimerPort` 未进入 `contracts/**` 或端口位置例外。

---

> **文档勘误结束（agent:technical-writer，wp-110，2026-10-18）**：以上 §10 执行记录保留原文；本报告标题、§1、§5.2、§5.3、§6 第 6 项、§7.2 已按 wp-093 之后的最终状态勘误。**不改变 T-23 首次交付的代码/证据，也不改变 wp-093 执行记录**。当前权威状态：16/17 端口关闭、PORT-LOC-01 OPEN、D-12 6 active / 7 retired、fixture 27/27；最终测试候选以 TEST-002 @ `e74a181` 为准。
