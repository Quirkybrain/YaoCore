# T-14 评审修复报告（C-15 CloudService + C-16 AC 适配）

- **Artifact ID**: IMPL-T14-FIX
- **Producer**: agent:implementation-engineer
- **Task**: `wp-058-fix-t14`（task 分支 `task/wp-055-cloud`，父分支 `feat/yaocore-app`，base commit `9eca54ec2ff955113fa94c0220586d0b7a1c69a8`）
- **Workflow**: STANDARD / GATED_AUTO
- **Status**: 修复与本地验证完成，待独立复审；不自我批准。
- **上游输入**:
  - `artifacts/70-review/t14-review.md` @ `df4ec2fa…`（F-01/F-02/F-03/F-04/F-06/F-07）
  - `artifacts/50-implementation/t14-cloud-ac.md` @ `de5a46fa…`
  - `artifacts/40-detailed-design/des-001b-domain-presentation.md` @ `e8d3869b…`（含 §0.6 T-14 裁定与 §8.1.4/§8.1.6/§8.1.7/§8.3.1/§8.3.3/§9.6）
  - `artifacts/40-detailed-design/des-001a-foundation-transport.md` @ `3a02ecbf…`
  - `artifacts/20-architecture/contract-baseline.md` @ `883e09bb…`
  - `artifacts/20-architecture/project-constraints.md` @ `28304621…`
  - `artifacts/60-testing/test-plan.md` @ `33485cc3…`
- **写范围**: `entry/src/main/ets/service/`、`entry/src/test/`、`artifacts/50-implementation/`（未改冻结 v4 DDL、`repository/**`、`ohosTest/**`）。

---

## 1. 逐条处置

### F-01（High，阻断）— `RdbCloudConfigStore` 对齐冻结 v4 DDL

**处置：已修复。**

- `CloudConfigStore.ets` 删除自建 `id TEXT PRIMARY KEY` 表；`load/save/clear` 全部改为
  `where singleton_id = 1`，`save` 写入 7 列
  `(singleton_id, endpoint, project_id, device_id, access_token_alias, shadow_endpoint, updated_at)`。
  `updated_at` 由注入的 `ClockPort` 生成（未注入时回退 `Date.now()`；C-28 应显式注入）。
- `initialize()` 改造为**只校验不建表**：`SELECT singleton_id, ..., updated_at FROM cloud_config LIMIT 0`；
  表/列缺失映射为 `STORAGE_MIGRATION_FAILED`，不会创建与 v4 不一致的 schema。
- 未修改 `entry/src/main/ets/repository/DomainMigrations.ets`（v4 DDL 冻结）。
- 实现报告 `t14-cloud-ac.md` §6 第 5 项已更正，不再声称“尚未纳入迁移注册表”。

**迁移测试证据**（host）：

- `C15_rdbConfigStore_v4MigrationInterop`：通过 `DomainHarness` 先执行真实 v1..v4 迁移链
  （v1 probe、v2 `FamilyRepository`、v3 `AuthService`、v4 `DomainMigrations`），再构造
  `RdbCloudConfigStore` 完成 `initialize → clear → save → load → clear`；并直接查询
  `cloud_config` 断言 `singleton_id = 1`、`updated_at = 20261017T080000Z`。
- `C15_rdbConfigStore_neverCreatesItsOwnSchema`：全新空库上 `initialize()` 返回
  `STORAGE_MIGRATION_FAILED`，`tableNamesForTest()` 仍为空，证明不会自建表。

### F-02（Medium）— `saveConfig` 仅在提供新 token 时复位失败状态

**处置：已修复。**

- 只有 `token !== undefined`（新非空 token 或显式 `''` 清空）才调用 `resetFailureState()`；
  不传 token 时保留 `TOKEN_EXPIRED`/`TOKEN_INVALID` 及旧 credentials。
- 显式 `token=''` 删除 token 并复位，状态落到 `TOKEN_MISSING`。

**回归**：`C15_saveConfig_tokenFailureOnlyClearedByNewToken`
（401 → TOKEN_EXPIRED → `saveConfig(config)` 仍 TOKEN_EXPIRED 且旧 token 不变 →
`saveConfig(config, newToken)` → CONFIGURED；403 → TOKEN_INVALID → 裸保存仍 INVALID →
`saveConfig(config, '')` → TOKEN_MISSING）。

### F-03（Medium）— `testConnection` 两层状态语义（DES-B §0.6/§8.1.7/§8.3.1）

**处置：按 architect 裁定实现。**

- **L1 持久配置层（不写）**：`testConnection` 不调用 `CloudConfigStore.save/clear`，也不调用
  `CloudCredentialPort.putToken/removeToken`；无配置 → `CLOUD_NOT_CONFIGURED`，无 token →
  `CLOUD_TOKEN_MISSING`，配置非法 → 校验错误；这些情况不发起网络请求。
- **L2 瞬时健康层（按探测更新）**：成功 → 清零连续网络失败/`unavailable`/网络类 `lastError`，
  若 `getState()` 因此变化则 `notify()`（`UNAVAILABLE → CONFIGURED`）；401/403 → 记录
  `TOKEN_EXPIRED`/`TOKEN_INVALID`、`authFailureAt`、`lastError` 并 `notify()`，不回写 token、
  不自动重试；其他错误只返回 `valid=false` + errors，不增加失败计数、不单独提升 `UNAVAILABLE`。
- Token 失败状态只由新的非空 `saveConfig` token 清除（与 F-02 一致）。

**回归**：`C15_testConnection_twoLayerHealth`（两次 500 → UNAVAILABLE → 成功探测 → CONFIGURED
且订阅通知；探测 500 不重新提升 UNAVAILABLE；探测 401 → TOKEN_EXPIRED 且 token 不变；
`CloudConfigStore`/credentials 写调用计数不变）、
`C15_testConnection_preconditionsDoNotTouchNetwork`（无 token/无配置零网络请求）。

### F-04（Medium）— 固定名注册表与 inventory 路由（DES-B §0.6/§8.1.6/§8.3.3）

**处置：已修复。**

- `CloudCompletionEvaluator` 增加 `NON_INVENTORY_FIXED = {Gateway, Door_01, Light_01, AC_01, Sensor_01, Presence_01}`：
  - `Door_01/Light_01/AC_01` 只走固定属性载体，**永不**查 inventory；
  - `Sensor_01/Presence_01` → `UNSUPPORTED`（`READ_ONLY_SENSOR`，`CLOUD_COMPLETION_UNSUPPORTED`）；
  - `Gateway` → `UNSUPPORTED`（`GATEWAY_NOT_SUPPORTED`，`CLOUD_COMPLETION_UNSUPPORTED`），
    即使 inventory 伪造匹配的 `last_request_id/last_seq/event_time` 也不得 CONFIRMED；
  - 仅注册表外目标进入 `DeviceInventoryJson`（PB-02），缺载体仍 `UNSUPPORTED`。

**回归**：`C15_completion_reservedFixedNamesNeverUseInventory`（Gateway/Sensor/Presence 伪造
inventory → UNSUPPORTED；Door/AC 有匹配 inventory 但缺固定载体 → PENDING；Light 固定载体
不匹配而 inventory 匹配 → PENDING；注册表外 `MODULE_01` 缺条目 → UNSUPPORTED）。
既有 `C15_completion_builtInDoubleMatchStaleAndVerification` 的 Gateway 断言同步更新为新错误码。

### F-06（Medium）— v1 单 active 云作用域 fail-closed

**处置：已按裁定实现，v1 单网关限制接受。**

- `CloudPorts.ets` 新增 `CloudActiveScopePort`
  （`activeGatewayId()` + `isGatewayBound(gatewayId)`），由 C-28 的 active-gateway 装配提供。
- `CloudCommandClient.send` 在 `credentials.hasToken()`、`nextSequence`、secret 读取、签名和
  HTTP **之前**执行 `assertActiveGateway`：
  - scope 已提供：`command.gatewayId` 必须等于 active gateway 且已绑定，否则
    `CLOUD_NOT_CONFIGURED`；
  - scope 未提供：通过 `GatewayCredentialPort` 做绑定预检（缺失 → `CLOUD_NOT_CONFIGURED`）；
  - 发送阶段把 `GATEWAY_NOT_BOUND`/`ASSET_NOT_FOUND` 统一映射为 `CLOUD_NOT_CONFIGURED`。
- 不重试、不消耗 seq、失败路径不读取 secret、不发 HTTP。
- `CloudConfig` 冻结形状未改，未增加 `gatewayId`；多网关家庭限制与
  `RISK-CLOUD-MULTIGATEWAY = ACCEPTED (v1)` 由 DES-B §8.3.1/C-23 承担。

**回归**：`C15_command_activeScopeAndCredentialFailClosed`（scope 不匹配、active 未绑定、
无 scope 且无凭据、`CloudService.send` 路径）断言 transport 请求数 0、`peekSequence=0`、
`secretReads=0`；同 test 验证 scope 内命令照常发送。

### F-07（Low，测试完整性）— 补齐缺口

**处置：已补齐。**

| 缺口 | 新增/更新测试 |
|---|---|
| 传输抛错 → `CLOUD_REQUEST_FAILED` | `C15_transportFailureRateLimitAndServiceOutcomes`（`HTTP_TIMEOUT`） |
| 429 限流单独重试 | 同上（429 → 200，同一 body/headers/seq，2 次请求） |
| service 级 `UNSUPPORTED` | 同上（`Sensor_01` → outcome UNSUPPORTED） |
| service 级 `INVALID` | 同上（缺 `event_time` 影子 → outcome INVALID + `CLOUD_SHADOW_INVALID`） |
| F-01 迁移兼容 | `C15_rdbConfigStore_v4MigrationInterop`、`C15_rdbConfigStore_neverCreatesItsOwnSchema` |
| F-02 状态迁移 | `C15_saveConfig_tokenFailureOnlyClearedByNewToken` |
| F-03 状态迁移/零写入 | `C15_testConnection_twoLayerHealth`、`C15_testConnection_preconditionsDoNotTouchNetwork` |
| inventory 根为对象/非法 `event_time` | `C15_inventory_candidateMatchAndFailClosed` 追加两条负例 |

未改变：canonical/HMAC 10 字段、2xx 仅受理、`LastRequestId`+`LastSeq` 双匹配+新鲜度、
PB-02 fail-closed、AC 七值/温度/非标准不回发。既有 497 条测试全部保留并通过。

---

## 2. 变更文件

```text
entry/src/main/ets/service/cloud/CloudConfigStore.ets        # F-01
entry/src/main/ets/service/cloud/CloudPorts.ets              # F-06 端口
entry/src/main/ets/service/cloud/CloudCommandClient.ets      # F-06 前置门
entry/src/main/ets/service/cloud/CloudService.ets            # F-02/F-03
entry/src/main/ets/service/cloud/CloudCompletionEvaluator.ets# F-04
entry/src/test/host/CloudFakes.ets                           # active-scope fake / HttpResponse 值导入
entry/src/test/host/TransportFakes.ets                       # secretReads 计数
entry/src/test/host/CloudService.test.mjs                    # 8 条新测试 + 既有断言同步
entry/src/test/evidence/t14-fix-*.log|tap                    # 本 revision 命令证据
artifacts/50-implementation/t14-cloud-ac.md                  # §6.5 更正
artifacts/50-implementation/t14-fix-report.md                # 本报告
```

---

## 3. 实际命令与结果（当前 revision）

```bash
ohpm install
# install completed in 0s 55ms

hvigorw clean assembleHap --no-daemon
# BUILD SUCCESSFUL in 5 s 206 ms / 35 tasks (34 executed, 1 up-to-date)

codelinter -c code-linter.json5 -p default .
# No defects found in your code.

entry/src/test/run-host-tests.sh
# tests 505 / pass 505 / fail 0 / cancelled 0 / skipped 0 / todo 0 / exit 0
```

补充（设备骨架只编译，不执行）：

```bash
hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon
# BUILD SUCCESSFUL in 8 s 561 ms / 35 tasks (34 executed, 1 up-to-date)
```

证据文件：

- `entry/src/test/evidence/t14-fix-ohpm-install.log`
- `entry/src/test/evidence/t14-fix-clean-assemble.log`
- `entry/src/test/evidence/t14-fix-codelinter.log`
- `entry/src/test/evidence/t14-fix-host-node-tests.tap`
- `entry/src/test/evidence/t14-fix-ohosTest-assemble.log`

**测试计数**：505 条（T-14 原 18 条 + 修复轮新增 8 条；基线 479 条无删除）。测试新增
`C15_rdbConfigStore_v4MigrationInterop`、`C15_rdbConfigStore_neverCreatesItsOwnSchema`、
`C15_saveConfig_tokenFailureOnlyClearedByNewToken`、`C15_testConnection_twoLayerHealth`、
`C15_testConnection_preconditionsDoNotTouchNetwork`、
`C15_completion_reservedFixedNamesNeverUseInventory`、
`C15_command_activeScopeAndCredentialFailClosed`、
`C15_transportFailureRateLimitAndServiceOutcomes`。

---

## 4. 偏离、假设与限制

1. **`CloudActiveScopePort` 为新增可选端口**：`CloudCommandClient` 构造函数追加可选尾参，
   不改变 DES-B §8.1.4 冻结签名与 wire 语义；C-28 必须注入真实实现才能启用 active-scope
   一致性校验，未注入时仅做网关凭据绑定前置校验。多网关 UI 限制（已绑定网关数 `>1` 禁用云）
   属于 C-23/C-28，不在本任务写范围。
2. **`RdbCloudConfigStore` 的 `ClockPort` 为可选参数**：`ohosTest/**` 不在本任务写范围，
   旧设备骨架仍以单参构造并通过编译；但该骨架在全新库直接 `initialize()` 的路径已不再成立，
   仍为 `BLOCKED_ON_DEVICE_RUNNER`/`COMPILED_ONLY`，不得作为 PASS 证据。C-28 应显式注入
   `ClockPort`，并按 DES-B §2.7 先迁移后构造。
3. **设备骨架未更新**：`entry/src/ohosTest/ets/test/cloud/CloudDevice.test.ets` 的迁移顺序
   修正需要 ohosTest 写权限，超出 handoff 写范围；已在本报告与残余风险中登记。
4. **F-05/F-08/F-09/F-10/F-11 未在本修复轮处理**：`brand.*` 资源仍由 T-18 资源任务补齐
   （DES-B §9.6，`DEFERRED`）；中文协议别名/SQL 字符串 warning、单 timer/取消槽、
   inventory 字节上限、路径例外/INTERNET 权限保持原评审跟踪。
5. **A-CB-1 / PB-02 / 真实云**：仍为 `RISK`/`UNRESOLVED`/`UNAVAILABLE`；本报告不含真实
   IoTDA/IAM/影子或设备证据。

---

## 5. 结论

F-01/F-02/F-03/F-04/F-06/F-07 已按评审与 architect 裁定修复并补齐回归；构建、lint、
host 505/505 与 ohosTest 编译在本 revision 通过。设备、真实云与 F-05 资源仍未验证，
C-15/C-16 证据保持 `UNVERIFIED`，待独立复审与 CQG-T14。
