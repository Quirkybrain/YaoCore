# T-14 复审报告（C-15 CloudService + C-16 AC 品牌适配，修复轮）

- **Artifact ID**: REVIEW-T14-B
- **Producer**: agent:quality-reviewer
- **Type**: Independent Code Review（复审 / F-01..F-07 关闭确认）
- **Status**: **PASS（代码级）**；CQG-T14 建议通过，残余项按 §6 跟踪
- **Date**: 2026-10-17
- **Task**: `wp-059-review-t14b`（task 分支 `task/wp-055-cloud`，父分支 `feat/yaocore-app`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`（CQG-T14 前）
- **Reviewed revision**: `db334852aeec1ab4335eef8681ece27542a61a08`
  （修复提交；父/裁定提交 `9eca54ec2ff955113fa94c0220586d0b7a1c69a8`；修复 diff `9eca54e..db33485`，15 路径）
- **Review snapshot**: `refs/swe/snapshots/20261017T152207Z-wp-059-review-t14b-a5bf89fc`
  （commit `b6104281f567e1e29d6b442d5d6aaf301a1048ec`；base `db33485`）
- **Independence**: 本复审由未参与 T-14 实现、修复、测试或实现报告编写的 `quality-reviewer` 执行。评审期间未修改任何被审产品代码、测试、证据或实现报告；唯一仓库写入为本报告。行为探针通过 Node stdin 执行，未在仓库落盘。
- **Deliverable note**: 本路径原为 Orchestrator 在快照中创建的占位文件（`Producer: orchestrator:main-session` 的 guard 占位）；本报告已覆写该文件并声明独立 Producer。

> 结论先行：上轮评审的 **F-01/F-02/F-03/F-04/F-06/F-07 已正确关闭**；**F-05（`brand.*` 资源键）仍为 `DEFERRED`，按 DES-B §0.6/§9.6 归属 T-18**。本 revision 的 host 测试、lint、构建与 ohosTest 编译均通过，独立探针确认 F-01 迁移互操作、F-02/F-03 状态语义和 F-06 零 seq/零请求失败路径。发现 2 个 **Low** 观察项（R2-01：`testConnection` 成功会清除 token 类 `lastError`；R2-02：未注入 active-scope 时绑定预检会读取 secret 且无法证明 active scope）。二者不阻断 CQG-T14，但应跟踪到 C-28 或后续维护轮。

---

## 1. 范围、revision 与输入完整性

### 1.1 评审范围

```text
entry/src/main/ets/service/                  # 重点 service/cloud/5 个修复文件；核对被调用的 model/common/security/protocol/storage 边界
entry/src/test/                              # host 测试、CloudFakes、TransportFakes、修复轮证据
entry/src/ohosTest/ets/test/cloud/           # 设备骨架（只读；本轮仅编译，不执行）
artifacts/50-implementation/t14-fix-report.md # 修复报告（只读）
artifacts/50-implementation/t14-cloud-ac.md   # 实现报告（只读；§6.5 更正）
```

- 实际被审修复变更为 `9eca54e..db33485` 的 **15 个路径**：产品代码 5 个（`CloudCommandClient`、`CloudCompletionEvaluator`、`CloudConfigStore`、`CloudPorts`、`CloudService`）、host 测试/fake 3 个（`CloudService.test.mjs`、`CloudFakes.ets`、`TransportFakes.ets`）、证据 5 个（`t14-fix-*.log|tap`）、工件 2 个（`t14-cloud-ac.md`、`t14-fix-report.md`）。
- 交叉读取但未修改：`model/CloudModels.ets`、`model/FamilyModels.ets`、`model/ControlModels.ets`、`repository/DomainMigrations.ets`、`repository/GatewayPorts.ets`、`service/storage/RdbStore.ets`、`service/storage/MigrationRegistry.ets`、DES-B §0.6/§8/§9.6、DES-A、`contract-baseline.md`、`project-constraints.md`、`test-plan.md`。
- **明确排除**：真实设备/模拟器、真实 IoTDA/IAM/影子、C-28 组合根、C-24/C-27 UI 与资源、用户验收、完整 Stage Gate。这些保持 `BLOCKED`/`COMPILED_ONLY`/`UNAVAILABLE`，本报告不将其写成 PASS。

### 1.2 输入 pin 与快照

handoff 的 8 个 `inputs` SHA-256 **8/8 一致**；`config/git-policy.json` 的 SHA-256（`3b8ddffd…`）与 handoff 一致；`git status` 在复验前后 clean，HEAD = `db33485`；修复提交 15 路径与 diff 一致。

| 输入 | SHA-256 前 12 位 | 结果 |
|---|---|---|
| `artifacts/70-review/t14-review.md` | `df4ec2fa7357` | 一致 |
| `artifacts/50-implementation/t14-fix-report.md` | `98f2601fad1d` | 一致 |
| `artifacts/50-implementation/t14-cloud-ac.md` | `d9fb9c1b1063` | 一致 |
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | `e8d3869b0990` | 一致 |
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `3a02ecbf266b` | 一致 |
| `artifacts/20-architecture/contract-baseline.md` | `883e09bb34ea` | 一致 |
| `artifacts/20-architecture/project-constraints.md` | `283046210e68` | 一致 |
| `artifacts/60-testing/test-plan.md` | `33485cc39abd` | 一致 |
| `config/git-policy.json` | `3b8ddffd4494` | 一致 |

快照 `b610428…` 以 `db33485` 为基线，覆盖 `entry/src/main/ets/service/`、`entry/src/test/`、`artifacts/` 的评审目标及 handoff 文件；`swe_guard status` 显示 branch/HEAD clean。本报告不复用 `039adec` 的测试/评审证据。

### 1.3 本复审实际复验（cwd = 仓库根）

| 命令 | 结果 | 说明 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS：505 tests / 505 pass / 0 fail / 0 cancelled / 0 skipped / 0 todo，exit 0** | 与 `t14-fix-host-node-tests.tap` 的 505/505 一致；T-14 原 18 条 + 修复轮 8 条；基线 479 条无删除 |
| `codelinter -c code-linter.json5 -p default .` | **PASS：No defects found in your code，exit 0** | 与 `t14-fix-codelinter.log` 一致 |
| `hvigorw clean assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0**（35 tasks；34 executed / 1 up-to-date） | 与 `t14-fix-clean-assemble.log` 一致；unsigned HAP |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0**（35 tasks；34 executed / 1 up-to-date） | 与 `t14-fix-ohosTest-assemble.log` 一致；**仅编译，不是设备执行** |
| `python3 entry/src/test/i18n/check_i18n.py --root . --strict-ui` | **CHK-01..09 全部 PASS，0 blocking findings** | `brand.*` 仍缺失（F-05，T-18）；CHK-07 仍有协议别名/既有页面 warning，非本修复轮新增阻断 |
| `git status --short` / `git diff --stat` | **PASS：clean / 空** | 构建、lint 与探针未产生跟踪文件变化 |

独立探针（Node stdin，不落盘）确认：

1. **F-01**：`DomainHarness` 先执行真实 v1..v4 迁移注册链，`cloud_config` 存在；`RdbCloudConfigStore.initialize()` 只做列校验，`save → load → clear` 正常，`singleton_id=1`、`updated_at=20261017T080000Z`；空库 `initialize()` 返回 `STORAGE_MIGRATION_FAILED` 且 `tableNamesForTest()` 仍为空。
2. **F-02**：`401 → TOKEN_EXPIRED`；裸 `saveConfig(config)` 后仍 `TOKEN_EXPIRED` 且旧 token 保留；`saveConfig(config, newToken) → CONFIGURED`。
3. **F-03**：两次 500 → `UNAVAILABLE`；`testConnection()` 200 → `CONFIGURED` 且订阅收到通知；探测 500 不重新提升 `UNAVAILABLE`；探测 401 → `TOKEN_EXPIRED` 且 token 不变；`CloudConfigStore`/credentials 无写调用。
4. **F-04**：`Gateway`/`Sensor_01`/`Presence_01` 即使伪造匹配 inventory 仍 `UNSUPPORTED`；`Door_01`/`AC_01` 有匹配 inventory 但缺固定载体仍 `PENDING`；`Light_01` 固定载体不匹配而 inventory 匹配仍 `PENDING`；注册表外 `MODULE_01` 缺条目 `UNSUPPORTED`。
5. **F-06**：scope 不匹配、active 未绑定、无 scope 且无凭据三种失败均 `CLOUD_NOT_CONFIGURED`，transport 请求 0、seq 0、`secretReads=0`；scope 内命令正常发送。
6. **回归**：canonical/HMAC 10 字段、2xx 仅受理、双匹配+新鲜度、PB-02 fail-closed、AC 七值/温度/非标准不回发均通过既有 505 条测试；修复 diff 未改 canonical/serializer、AC 适配器或冻结 DDL。

> 说明：F-01 的 host 迁移库使用真实 `MigrationRegistry` + `DomainMigrations` v1..v4 语句，但底层是 `InMemoryRdbStore`（host fake），不执行真实 SQLite 的 `CHECK`/`NOT NULL` 约束。它足以捕获原 `id`/`singleton_id` 列不匹配缺陷，**不构成设备 SQLite 证据**；设备/真实迁移仍 `BLOCKED`。

---

## 2. F-01..F-07 关闭状态

| ID | 上轮严重度 | 修复证据（本 revision） | 独立确认 | 状态 |
|---|---|---|---|---|
| **F-01** | High / 阻断 | `CloudConfigStore.ets:24-49` 删除自建 DDL，`initialize()` 改为 `SELECT ... LIMIT 0` 只校验；`:51-80` 全部 `singleton_id=1` 读写，`updated_at` 由 `ClockPort`/`Date.now()` 写入；未改 `DomainMigrations` v4 | `C15_rdbConfigStore_v4MigrationInterop` + `C15_rdbConfigStore_neverCreatesItsOwnSchema` 实际执行；独立探针确认迁移库读写与空库 fail-closed | **CLOSED** |
| **F-02** | Medium | `CloudService.ets:133-152`：仅 `token !== undefined` 时 `resetFailureState()`；`token=''` 删除 token 并落到 `TOKEN_MISSING`；不传 token 保留 `TOKEN_EXPIRED/INVALID` | `C15_saveConfig_tokenFailureOnlyClearedByNewToken`；独立探针复现 | **CLOSED** |
| **F-03** | Medium | `CloudService.ets:185-239`：L1 不写 `cloud_config`/token；成功清 `networkFailures/unavailable` 并条件 `notify()`；401/403 `recordFailure` + `notify()`；其他错误只设 `lastError`，不提升 `UNAVAILABLE` | `C15_testConnection_twoLayerHealth`、`C15_testConnection_preconditionsDoNotTouchNetwork`；独立探针复现 | **CLOSED（含 R2-01 Low）** |
| **F-04** | Medium | `CloudCompletionEvaluator.ets:31-34` 增加 `NON_INVENTORY_FIXED`；`:58-85` 固定名先于 inventory 路由；`Gateway` → `GATEWAY_NOT_SUPPORTED`，传感器 → `READ_ONLY_SENSOR`；固定设备只走固定载体 | `C15_completion_reservedFixedNamesNeverUseInventory`；既有 Gateway 断言更新；独立探针 | **CLOSED** |
| **F-05** | Medium | 未在本修复轮处理；`brand.gree/haier/midea/generic` 仍不在 zh-CN/en-US 资源；DES-B §0.6/§9.6 已裁定归属 T-18 | i18n checker 仍 0 blocking；键缺失未被 host 测试掩盖 | **DEFERRED（T-18）** |
| **F-06** | Medium | `CloudPorts.ets:42-57` 新增 `CloudActiveScopePort`；`CloudCommandClient.ets:117` 在 token/seq/secret/sign/HTTP 前调用 `assertActiveGateway`；`:181-222` scope 校验 + 绑定预检 + `GATEWAY_NOT_BOUND/ASSET_NOT_FOUND → CLOUD_NOT_CONFIGURED` | `C15_command_activeScopeAndCredentialFailClosed`；独立探针确认 0 请求/0 seq/0 secret；**条件**：C-28 必须注入 scope | **CLOSED（v1 条件）** |
| **F-07** | Low | 新增 `C15_transportFailureRateLimitAndServiceOutcomes`（传输抛错/429/service UNSUPPORTED/INVALID）、F-01 两条迁移测试、F-02/F-03 状态测试、inventory 根对象/非法 `event_time` 负例 | 505/505 实际执行；新增 8 条均出现于 TAP | **CLOSED（host 缺口）；设备骨架更新仍跟踪** |

### 2.1 F-01（High，已关闭）

原缺陷是 `RdbCloudConfigStore` 自建 `id TEXT PRIMARY KEY` 表，与 v4 `cloud_config`（`singleton_id`/`updated_at`/`CHECK`）不兼容。本 revision：

- `initialize()` 不再 `CREATE TABLE`，只查询冻结列；失败映射 `STORAGE_MIGRATION_FAILED`；
- `load/save/clear` 全部使用 `singleton_id = 1`，`save` 写 7 列并写 `updated_at`；
- `DomainMigrations.ets` 的 v4 DDL 未被修改；
- `t14-cloud-ac.md` §6.5 已从“尚未纳入迁移注册表”更正为“与 v4 对齐、先迁移后构造”。

独立确认：`DomainHarness` 注册 v1 probe + 真实 `FamilyRepository` v2 + `AuthService` v3 + `DomainMigrations` v4；`RdbCloudConfigStore` 在该库上 `initialize → clear → save → load → clear` 全部成功，直接查询 `singleton_id=1`、`updated_at=NOW_TEXT`；空库上 `initialize` 失败且未建表。**测试不是自建表**。残余限制：host fake 不执行真实 SQLite 的 `CHECK`/`NOT NULL`，设备/真机迁移仍 `BLOCKED`。

### 2.2 F-02（Medium，已关闭）

`saveConfig` 的复位条件已收窄到 `token !== undefined`。独立探针：

```text
401 → CLOUD_TOKEN_EXPIRED → getState() = TOKEN_EXPIRED
saveConfig(config)            → state TOKEN_EXPIRED，旧 token 保留
saveConfig(config, newToken)  → state CONFIGURED，token 更新
saveConfig(config, '')        → state TOKEN_MISSING，token 删除
```

与 DES-B §8.3.1 的 `TOKEN_EXPIRED/INVALID --> CONFIGURED: saveConfig(new token)` 和 D-012 手工 Token 一致。**关闭。**

### 2.3 F-03（Medium，已关闭；R2-01 Low）

按 architect §0.6 裁定实现两层语义：

- **L1 持久配置层不写**：`testConnection` 不调用 `CloudConfigStore.save/clear`，不调用 `CloudCredentialPort.putToken/removeToken`；无配置/无 token/配置非法时零网络请求；
- **L2 瞬时健康层**：成功清 `networkFailures/unavailable`，状态变化时 `notify()`；401/403 记录 `tokenFailure/authFailureAt/lastError` 并 `notify()`；其他错误不增加失败计数、不单独提升 `UNAVAILABLE`；
- Token 失败只由新的非空 `saveConfig` token 清除（与 F-02 一致）。

独立探针确认 `UNAVAILABLE → CONFIGURED`、通知次数、401 记录与零持久写。**主行为关闭**；R2-01 是成功探测对 token 类 `lastError` 的清除过宽，见 §3。

### 2.4 F-04（Medium，已关闭）

`NON_INVENTORY_FIXED = {Gateway, Door_01, Light_01, AC_01, Sensor_01, Presence_01}` 精确匹配，路由顺序为：

```text
STALE/INVALID 全局前置
  → Door_01/Light_01/AC_01：只读固定属性载体
  → Sensor_01/Presence_01：UNSUPPORTED（READ_ONLY_SENSOR）
  → Gateway：UNSUPPORTED（GATEWAY_NOT_SUPPORTED）
  → 其他注册表固定名：UNSUPPORTED（FIXED_DEVICE_UNSUPPORTED）
  → 注册表外：DeviceInventoryJson（PB-02）
```

独立探针与 `C15_completion_reservedFixedNamesNeverUseInventory` 均确认伪造 inventory 不会让 Gateway/Sensor/Presence `CONFIRMED`，固定设备不会因 inventory 同名条目转为 `CONFIRMED`。**关闭。**

### 2.5 F-05（Medium，DEFERRED）

- `AcVocabulary.brandI18nKey`（`AcModels.ets:152-154`，经 `GenericAcAdapter` 使用）仍返回顶层 `brand.*` 键，但实现仍是 `'brand.' + String(brand).toLowerCase()` 动态拼接；zh-CN/en-US rawfile 均无 `brand.gree/haier/midea/generic`；
- 按 DES-B §0.6/§9.6，该资源由 **T-18（C-27 设置/关于资源面）** 拥有，C-24/C-27 消费；CQG-T14 记为 `DEFERRED` 跨组件依赖；§9.6 关闭条件 2 要求固定映射或显式 allowlist，动态拼接问题一并归 T-18；
- 本复审不把 host 505/505 或 i18n checker 的 0 blocking 写成 F-05 已关闭。**未关闭，跟踪 T-18。**

### 2.6 F-06（Medium，已关闭；v1 条件）

- `CloudCommandClient.send` 顺序：`configs.load → validate → assertActiveGateway → hasToken → nextSequence → sign → HTTP`；失败路径不消耗 seq、不读 secret（scope 提供时）、不发请求；
- scope 提供：`command.gatewayId === activeGatewayId()` 且 `isGatewayBound`，否则 `CLOUD_NOT_CONFIGURED`；
- scope 未提供：通过 `GatewayCredentialPort.withCommandSecret` 做绑定预检，缺失映射 `CLOUD_NOT_CONFIGURED`；发送阶段的 `GATEWAY_NOT_BOUND/ASSET_NOT_FOUND` 也统一映射；
- `CloudConfig` 冻结形状未改；`RISK-CLOUD-MULTIGATEWAY = ACCEPTED (v1)` 由 DES-B §8.3.1/C-23 承担。

测试与独立探针确认三种失败路径 **0 请求、0 seq、0 secret**；scope 内命令正常发送。**关闭**，但 C-28 必须注入真实 `CloudActiveScopePort`，否则仅剩绑定预检（见 R2-02 与 §7）。

### 2.7 F-07（Low，host 缺口已关闭；设备骨架跟踪）

| 上轮缺口 | 本 revision 覆盖 |
|---|---|
| 传输抛错 → `CLOUD_REQUEST_FAILED` | `C15_transportFailureRateLimitAndServiceOutcomes`（`HTTP_TIMEOUT`） |
| 429 单独重试 | 同测试（429 → 200，同 body/headers/seq，2 次请求） |
| service 级 `UNSUPPORTED` | 同测试（`Sensor_01` outcome UNSUPPORTED） |
| service 级 `INVALID` | 同测试（缺 `event_time` → INVALID + `CLOUD_SHADOW_INVALID`） |
| F-01 迁移兼容 | `C15_rdbConfigStore_v4MigrationInterop`、`C15_rdbConfigStore_neverCreatesItsOwnSchema` |
| F-02 状态迁移 | `C15_saveConfig_tokenFailureOnlyClearedByNewToken` |
| F-03 状态迁移/零写入 | `C15_testConnection_twoLayerHealth`、`C15_testConnection_preconditionsDoNotTouchNetwork` |
| inventory 根对象/非法 `event_time` | `C15_inventory_candidateMatchAndFailClosed` 追加两条负例 |

**设备骨架未更新**：`entry/src/ohosTest/ets/test/cloud/CloudDevice.test.ets:46-67` 仍在全新库直接 `new RdbCloudConfigStore(rdb)` + `initialize()`；F-01 后该路径在真实设备上会得到 `STORAGE_MIGRATION_FAILED`。文件标注 `BLOCKED_ON_DEVICE_RUNNER`/COMPILED_ONLY，修复报告 §4.2 已如实登记；C-28 必须先跑 v1..v4 迁移再构造。**host 测试缺口关闭；设备骨架更新继续跟踪。**

---

## 3. 新发现（R2）

| ID | 严重度 | 位置 | 依据 | 问题/影响 | 建议 |
|---|---|---|---|---|---|
| **R2-01** | **Low（状态/诊断）** | `CloudService.ets:404-408`（`recordNetworkSuccess` 清所有 `lastError`）；`:217-223`（成功探测调用） | DES-B §8.1.7：“成功…清除**网络类** `lastError`”；Token 失败只由新 token 清除（F-02/F-03） | 已 `401 → TOKEN_EXPIRED` 后，若后续探测成功（200），`testConnection` 返回 `valid=true`，`getState()` 仍为 `TOKEN_EXPIRED`（正确），但 `CloudConfigView.lastError` 被清空（独立探针：`state=TOKEN_EXPIRED, lastError=undefined`）。UI 会丢失“401/令牌过期”的诊断对象，只剩状态；与“只清网络类 lastError”的裁定不完全一致。非阻断。 | `recordNetworkSuccess` 保留 token 类 `lastError`（或 `testConnection` 成功时只清网络类错误）；补 `401 → probe 200 → state TOKEN_EXPIRED 且 lastError/401 仍可观察` 回归测试 |
| **R2-02** | **Low（F-06 fallback/秘密最小化）** | `CloudCommandClient.ets:188-205`（无 scope 时 `withCommandSecret` 预检）、`:207-222`（签名再次读取） | DES-B §8.1.4/§8.3.1 F-06：无法证明 active scope 时 fail-closed；C-28 提供 active scope；`RISK-CLOUD-MULTIGATEWAY=ACCEPTED (v1)` | 未注入 `CloudActiveScopePort` 时，绑定预检通过 `withCommandSecret` **读取 secret**（正常发送时预检 1 次 + 签名 1 次，共 2 次）；无 scope + 已绑定 secret + 无 token 时，会在 `CLOUD_TOKEN_MISSING` 前读取 1 次 secret。失败的网关绑定路径（无凭据）仍为 0 次，且不消耗 seq/不发 HTTP。该 fallback 只能证明“有凭据”，不能证明“属于 active 云作用域”；v1 依赖 C-23 单网关限制与 C-28 注入 scope。修复报告“失败路径不读取 secret”的表述对网关绑定失败成立，对 token/seq 等其他失败不成立。 | C-28 必须注入真实 `CloudActiveScopePort` 并加组合根测试；或提供不返回 secret 的 `isGatewayBound` 预检端口；将修复报告措辞限定为“网关绑定失败路径不读取 secret”；多网关启用仍由 C-23 禁用/清除云配置 |

> 两项均为 Low，且不改变 F-01..F-04/F-06/F-07 的关闭结论；它们应进入 CQG-T14 残余记录和后续维护轮，而不是被 host 505/505 掩盖。

---

## 4. 回归与契约符合性（按复审要求）

| # | 检查点 | 结论 | 证据/说明 |
|---|---|---|---|
| 1 | canonical/HMAC：10 字段、`CmdId=3001`、`paras` 无 `object_device_id`、不复用网关 `result_code` | **未回归** | 修复 diff 未改 `CanonicalBuilder`/`CloudCommandSerializer`；`C15_cloudCommand_exactEnvelopeCanonicalAndHmac` 用 Node `crypto` 独立算 HMAC，505/505 通过 |
| 2 | 2xx 仅受理，不产生执行成功 | **未回归** | `C15_responseMapping_2xxReceiptOnlyAndHttpErrors`、`C15_sendAndConfirm_acceptanceIsNotCompletion` 通过；2xx/202 仍只返回 receipt，完成判定独立轮询 |
| 3 | `LastRequestId`+`LastSeq` 双匹配 + 新鲜度才 `CONFIRMED`；单匹配 PENDING；旧影子 STALE；未来 >5min INVALID | **未回归** | `C15_completion_builtInDoubleMatchStaleAndVerification` 通过；修复只增加固定名路由，未改双匹配/新鲜度 |
| 4 | PB-02 fail-closed：缺字段/重复/越界/超限/未知结构 → `CLOUD_INVENTORY_UNSUPPORTED`，绝不 `CONFIRMED`；固定路径不受非法 inventory 影响 | **未回归** | `C15_inventory_candidateMatchAndFailClosed`、`C15_completion_reservedFixedNamesNeverUseInventory` 通过；解析失败仍由 `ShadowDtoAdapter` 标记 |
| 5 | AC：7 值 mode、16..30°C、非标准保留但不可回发、品牌归一化/未知回退、纯映射 | **未回归** | 修复 diff 未触及 `service/ac/**`；18 条 T-14 测试中的 8 条 C16 用例继续在 505 条中执行 |
| 6 | 安全/错误：`CLOUD_*` 命名空间、无 token/body/cert 日志、fail-closed | **符合** | `CloudErrors` 未改；测试与探针检查 details/logger 不含 token；F-06 失败路径 0 HTTP/0 seq；R2-02 是秘密读取最小化观察，不是泄漏 |
| 7 | 分层：service 纯逻辑、无 `@ohos`/网络适配器 import | **符合** | 修复只增加 `CloudPorts` 类型 import 和 host 测试 import；`T11_pureGatewayLogicHasNoPlatformImport` 在 505 条中 PASS |
| 8 | 测试有效性：新增 8 条真实执行、无删除/跳过；证据与命令一致 | **符合** | 独立复跑 505/505；TAP 505 `ok`、0 `not ok`；证据日志命令/计数与修复报告 §3 一致 |

---

## 5. CQG-T14 对照

CQG-T14 最小必填（test-plan §4.3）：云命令 canonical/签名、shadow 解析、完成判定、错误命名空间。

| CQG 项 | 本 revision 证据 | 结论 |
|---|---|---|
| build | `hvigorw clean assembleHap --no-daemon` → BUILD SUCCESSFUL（35 tasks） | **PASS** |
| lint | `codelinter …` → No defects | **PASS** |
| host | `run-host-tests.sh` → 505/505 pass，0 fail/skipped/todo | **PASS** |
| contract | 10 字段/HMAC（Node oracle）、2xx receipt-only、双匹配+新鲜度、PB-02、AC 映射；V-12 云 golden/外部向量仍 `NOT_RUN`（test-plan 计划夹具；输入无云命令 golden；本修复轮未新增） | **PASS（host 契约证据）；V-12 记录跟踪** |
| security | 无 token/secret 日志；F-04/F-06 fail-closed；401/403 不自动重试；F-06 失败路径 0 请求/0 seq/0 secret | **PASS（R2-02 Low 观察）** |
| layer | service 无平台 import；`T11_pureGatewayLogicHasNoPlatformImport` PASS；路径例外已在实现报告记录 | **PASS** |
| review | 本独立复审（作者/评审者分离） | **PASS** |
| device | 无设备/模拟器/签名；ohosTest 仅编译 | **BLOCKED（COMPILED_ONLY）** |
| i18n | CHK-01..09 0 blocking；`brand.*` 缺失，按 §0.6/§9.6 归 T-18 | **DEFERRED（F-05）** |
| trace | test-plan 的 C-15/C-16 行及 V-12 仍 `NOT_RUN`；CQG-T14 记录需 Gate 后由 test-engineer/Orchestrator 更新 | **待更新（非代码缺陷）** |

**CQG-T14 最终意见：PASS（组件级，建议 Orchestrator 授予；最终 Gate 由 Orchestrator 判定）。**

- 代码级 Must 项已有当前 revision 证据；F-05 按 architect 裁定作为 `DEFERRED` 跨组件依赖记录，未以 host 测试掩盖；设备项按 CP-03/环境限制为 `BLOCKED`，不伪造 PASS。
- 本意见不授予 STABLE、Integration Gate、Stage Gate 或用户验收；CQG 的最终记录与 traceability 更新仍由 Orchestrator/test-engineer 完成。

---

## 6. 残余风险与跟踪

| 风险/缺口 | 级别 | 跟踪 |
|---|---|---|
| F-05 `brand.*` 四键缺失 + 动态键拼接 | Medium / `DEFERRED` | T-18 资源任务补齐 zh-CN/en-US 并纳入 key parity；同时按 §9.6 关闭条件 2 改为固定映射或显式 allowlist；CQG-T14/CQG-T17/CQG-T18 记录依赖 |
| 设备骨架 `CloudDevice.test.ets` 仍在全新库直接 `initialize()` | Medium（设备层） | 设备 `BLOCKED`；C-28 或后续任务改为先跑 v1..v4 迁移、再构造并注入 `ClockPort`/`CloudActiveScopePort`；不得把 COMPILED_ONLY 写成 PASS |
| 多网关 v1 作用域 | Medium / `ACCEPTED (v1)` | C-23 已绑定网关数 >1 时禁用/清除云；C-28 必须注入 `CloudActiveScopePort`；`awaitCompletion` 直调依赖调用方处于 active scope；后续 Change Impact 扩展 `CloudConfig.gatewayId` |
| R2-01 `testConnection` 成功清 token 类 `lastError` | Low | 后续维护轮修正并补状态测试；CQG 记录 |
| R2-02 无 scope 绑定预检读取 secret / 无法证明 active scope | Low | C-28 注入 scope 或新增非 secret 绑定预检；修正修复报告措辞 |
| A-CB-1 IoTDA 错误体字段未冻结 | RISK / `UNVERIFIED` | 当前以 HTTP 状态为主映射；真实 IoTDA 联调后按 Change Impact 调整 |
| PB-02 固件 schema 未冻结 | `UNRESOLVED` | 合成 fixture 仅 `PUBLIC TEST DATA ONLY`；真实固件确认后重写 parser/测试 |
| V-12 云命令/影子外部 golden 未落地；test-plan CQG 行 `NOT_RUN` | 过程/证据 | Gate 后由 test-engineer/Orchestrator 更新；不把 host 自算 oracle 写成外部向量 |
| `ohos.permission.INTERNET` 未声明（既有） | RISK | 真实云运行前的清单任务必须补齐；本任务写范围外 |
| F-08 中文协议别名/未知品牌诊断/SQL warning；F-09 单 timer/取消槽；F-10 inventory 字节上限 | Low/Info | 上一轮已登记；本修复轮未处理，不单独阻断；本轮 i18n 检查未再出现 CloudConfigStore 的 SQL warning，协议别名 warning 仍存在 |
| 真实设备/真实 IoTDA/IAM/影子 | `BLOCKED`/`UNAVAILABLE` | 不得作为 CQG-T14 或 Stage Gate 证据；C-28 后补真机/IT |

---

## 7. Verdict 与复验要求

**Verdict: PASS（代码级）。**

- F-01/F-02/F-03/F-04/F-06/F-07 已按上轮评审与 architect 裁定关闭；F-05 按裁定 `DEFERRED` 到 T-18。
- 本 revision 的 build、lint、host 505/505、ohosTest 编译均通过，且由独立命令复跑；测试证据与修复报告一致。
- R2-01/R2-02 为 Low 跟踪项，不阻断 CQG-T14；若在 C-28/后续轮修复，需补对应测试并重新验证受影响范围。
- **不复用** `039adec` 的测试/评审证据；本 PASS 仅覆盖 `db33485`。
- 设备与真实云仍为 `BLOCKED`/`COMPILED_ONLY`/`UNAVAILABLE`；本报告不授予 STABLE、Integration Gate 或 Stage Gate。

---

## 8. 独立性与过程声明

- 本复审由未参与 T-14 实现、修复、测试或实现报告编写的 `quality-reviewer` 执行；作者与评审者分离。
- 只读边界：未修改被审产品代码、测试、证据、快照、冻结 DDL 或 `t14-cloud-ac.md`/`t14-fix-report.md`；唯一仓库写入为本报告 `artifacts/70-review/t14-review-b.md`。
- 行为探针通过 `node --import entry/src/test/host/register-ets.mjs --input-type=module -` 的 stdin 执行，未写入仓库；使用公开测试数据与内存 fake，不构成设备/真实云证据。
- 本报告覆盖 `db334852aeec1ab4335eef8681ece27542a61a08`（父/裁定 `9eca54e`）；输入 pin 8/8、git policy、快照 ref 与任务分支一致。
