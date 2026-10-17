# T-14 云服务（C-15）与 AC 品牌适配层（C-16）实现报告

- **Artifact ID**: IMPL-T14
- **Producer**: agent:implementation-engineer
- **Task**: T-14 / `wp-055-cloud`（task 分支 `task/wp-055-cloud`，父分支 `feat/yaocore-app`）
- **Base commit**: `de1b9b60eb4839ee78c2298c2834650a5628279d`
- **Workflow**: STANDARD / GATED_AUTO
- **Status**: 实现与本地验证完成，待独立质量评审；不自我批准。T-14 评审修复轮（`wp-058-fix-t14`）的处置与新增证据见 [`t14-fix-report.md`](t14-fix-report.md)；本文件 §3 的 497 条计数与日志属于 `039adec` revision 的历史证据。
- **上游**:
  - DES-001B §8（C-15）/ §9（C-16）@ `8d094bb5…`
  - DES-001A（传输/安全/错误/端口）@ `3a02ecbf…`
  - `contract-baseline.md`（§2.4/§4/§6.3/§7.1/§8.2）@ `883e09bb…`
  - `project-constraints.md` @ `28304621…`
  - TEST-001 测试计划 @ `33485cc3…`

---

## 1. 实现范围

### 1.1 新增产品代码

```text
entry/src/main/ets/service/cloud/
├── CloudPorts.ets                # CloudConfigStore / CloudCredentialPort / TimerPort
├── CloudModels.ets               # 配置视图、命令回执、影子快照、完成判定、策略
├── CloudErrors.ets               # 云错误命名空间/HTTP 映射/诊断详情
├── CloudConfigValidator.ets      # HTTPS/ID/token alias/端点派生
├── CloudCommandClient.ets        # CreateCommand canonical/HMAC/2xx 回执/错误/有限重试
├── ShadowReader.ets              # 影子 REST 读取（无缓存）
├── ShadowDtoAdapter.ets          # 三形态 → ShadowSnapshot；64 KiB；inventory 分流
├── DeviceInventoryParser.ets     # PB-02 候选结构严格解析（fail-closed）
├── CloudCompletionEvaluator.ets  # 固定属性/inventory 完成判定 + 状态验证
├── CloudService.ets              # 配置/Token 状态机、send/awaitCompletion/sendAndConfirm
├── CloudConfigStore.ets          # RdbCloudConfigStore（单 active 行）
├── CloudCredentialStore.ets      # AssetCloudCredentialStore（token 仅 Asset Store）
├── CloudCancellation.ets         # 内部+外部取消桥
├── SystemTimerPort.ets           # 生产定时器适配器
└── adapters/OhosCloudHttpTransport.ets  # 平台 HTTPS（COMPILED_ONLY）
```

### 1.2 AC 品牌适配层（位置例外）

DES-B §9 名义路径为 `entry/src/main/ets/adapter/ac/**`。本 handoff 的产品写范围仅
`entry/src/main/ets/service/**`，因此实现落在：

```text
entry/src/main/ets/service/ac/
├── AcModels.ets            # AcBrand/AcModeView/AcCommand/AcCapabilities/AcViewState/词表
├── AcAdapter.ets           # 接口
├── GenericAcAdapter.ets    # 默认纯映射
├── GreeAcAdapter.ets       # 入站别名 节能→ECO
├── HaierAcAdapter.ets      # 入站别名 制冷→COOL
├── MideaAcAdapter.ets      # 入站别名 睡眠→SLEEP
└── AcAdapterFactory.ets    # 品牌归一化/创建
```

这是**路径位置例外**，不改变 DES-B 的接口语义；C-28 组合根接入时如要求原路径可一次性迁移。
同样，`CloudPorts`/DES-B 新增云模型按既有 T-06/T-07/T-08/T-11 先例放在
`service/cloud/**`，未写入 `contracts/**` 或 `model/**`。

### 1.3 测试与证据

```text
entry/src/test/host/CloudFakes.ets          # 云 host fakes（PUBLIC TEST DATA ONLY）
entry/src/test/host/CloudService.test.mjs   # C-15 host 测试（10 条）
entry/src/test/host/AcAdapter.test.mjs      # C-16 host 测试（8 条）
entry/src/ohosTest/ets/test/cloud/CloudDevice.test.ets  # 设备骨架（BLOCKED_ON_DEVICE_RUNNER）
entry/src/ohosTest/ets/test/List.test.ets   # 注册 cloudDeviceTest
entry/src/test/evidence/t14-*.log|tap       # 本 revision 命令证据
```

---

## 2. 契约对照

### 2.1 C-15 CloudService（DES-B §8）

| 契约点 | 实现 | 证据 |
|---|---|---|
| IoTDA 配置 endpoint/projectId/deviceId/token alias；无自动刷新 | `CloudConfigValidator`、`CloudService.saveConfig/clearToken/getState`；Token 仅 `AssetCloudCredentialStore` | `C15_cloudCommand_missingConfigTokenAndValidation`、`C15_service_configTokenStateAndTestConnection` |
| `CreateCommand` 10 字段 canonical + HMAC-SHA256（`CmdId=3001`，`paras` 不含 `object_device_id`） | `CloudCommandClient.send`；`CanonicalBuilder.cloudCommand`；`CloudCommandSerializer` | `C15_cloudCommand_exactEnvelopeCanonicalAndHmac`（Node HMAC oracle 一致） |
| 2xx 仅为受理回执 | `CloudCommandReceipt`；`CloudService.send` 不产生 `executionAccepted` | `C15_responseMapping_2xxReceiptOnlyAndHttpErrors`、`C15_sendAndConfirm_acceptanceIsNotCompletion` |
| HTTP/网络/限流错误映射；401/403 不重试；5xx/429 默认 1 次精确重发 | `CloudErrors`、`CloudSendRetryPolicy` | 同上 |
| 影子三形态 SERVICES/SHADOW/DEVICES；64 KiB；非法结构 fail-closed | `ShadowReader` + `ShadowDtoAdapter`（复用 C-03 严格 mapper） | `C15_shadow_threeShapesAndStrictInvalidCases` |
| 完成判定：`LastRequestId` + `LastSeq` 双匹配 + 2s 新鲜度 | `CloudCompletionEvaluator` | `C15_completion_builtInDoubleMatchStaleAndVerification`（双匹配/单匹配/旧影子/边界） |
| 只读传感器/Gateway 无完成载体 → UNSUPPORTED | 同上 | 同上 |
| 状态验证 MATCH/UNVERIFIED/MISMATCH（含 SET_COLOR 无云字段） | 同上 | 同上 |
| Token 过期语义：401→`TOKEN_EXPIRED`，403→`TOKEN_INVALID`；保存新 token 复位 | `CloudService.recordFailure/getState/saveConfig` | `C15_service_configTokenStateAndTestConnection`、`C15_sendAndConfirm_acceptanceIsNotCompletion` |
| 轮询超时/取消/`stopPolling`/`dispose` | `CloudService.awaitCompletion/stopPolling/dispose`、`CloudCancellation` | `C15_stopPollingCancelDisposeAndSubscription`、`C15_sendAndConfirm_acceptanceIsNotCompletion` |
| 云错误独立命名空间，不复用网关 `result_code` | `CloudErrors`/`ErrorCatalog` 既有 `CLOUD_*` | 代码评审 + 错误映射测试 |
| 云不影响 LAN | 本组件不引用 `LocalGatewayService` 或 LAN 服务状态 | 静态依赖方向 |

### 2.2 PB-02 / DeviceInventoryJson 处置

- **内置固定属性路径完整**：`Door_01` / `Light_01` / `AC_01` 的
  `*_LastRequestId` / `*_LastSeq` + `event_time` 新鲜度；`Sensor_01` / `Presence_01`
  只读 → `UNSUPPORTED`。该路径有完整正负例。
- **inventory 路径 fail-closed**：
  - `DeviceInventoryParser` 只接受候选字段；上限 8192 字节/32 条/63 字符 device_id；
  - 缺 `device_id` / `last_request_id` / `last_seq` / `event_time`、重复 ID、类型/范围错误、
    超限、未知根结构 → `CLOUD_INVENTORY_UNSUPPORTED`；
  - 解析失败被 `ShadowDtoAdapter` 标记为 `inventoryUnsupported`，**不阻断**内置固定属性路径；
  - 目标在 inventory 中无条目/缺载体 → `UNSUPPORTED`，绝不 `CONFIRMED`；
  - 未知字段忽略并记录 `CLOUD_INVENTORY_FIELD_IGNORED`；其他分页名记录
    `CLOUD_INVENTORY_PAGE_UNSUPPORTED` 且不使用。
- 合成 fixture 仅为 PUBLIC TEST DATA / PROPOSED_PB02；**不声称真实固件互操作**。

### 2.3 C-16 AC 适配层（DES-B §9）

| 契约点 | 实现 | 证据 |
|---|---|---|
| 品牌归一化（ASCII/中文/组合别名/未知回退 GENERIC） | `AcAdapterFactory.normalizeBrand` | `C16_factoryNormalizesAsciiChineseAliasesAndUnknown` |
| 四个 adapter 能力一致：7 值、16..30、无颜色、v1 无风速 | `AcCapabilities` | `C16_allBrandsShareSevenModesAndTemperatureRange` |
| 出站仅 7 值，禁止非标准/私有码回发 | `GenericAcAdapter.setMode` 运行时二次校验 | `C16_outboundModeVocabularyIsExactlySevenCanonicalValues`、`C16_nonStandardModeCannotBeSentBack` |
| 温度边界 16/30 接受；15.9/30.1/NaN/Infinity 拒绝且不 clamp | `setTargetTemperature` / `normalizeInboundTemperature` | `C16_powerAndTargetTemperatureMappingAndBoundaries` |
| 入站表外值保留原文、NON_STANDARD、禁止回发 | `AcVocabulary.view` / `normalizeInboundMode` | `C16_inboundModeStandardNonStandardAndBrandAliases` |
| 品牌仅影响入站归一/展示键 | Gree 节能/ Haier 制冷/ Midea 睡眠；`brandI18nKey` | 同上 |
| 纯同步映射，无网络/仓储/I18nService 依赖 | 仅 import `common/**`、`model/**` | `C16_adaptersHaveNoNetworkRepositoryOrI18nDependency` |

### 2.4 AC 品牌 × 模式/温度矩阵

| 品牌 | 出站模式 | 入站中文别名 | 温度 | 颜色/风速 |
|---|---|---|---|---|
| GENERIC | AUTO/COOL/HEAT/DRY/FAN/ECO/SLEEP | 无（表外 NON_STANDARD） | 16..30 | 不支持 |
| GREE | 同上（唯一词表） | 节能→ECO | 16..30 | 不支持 |
| HAIER | 同上 | 制冷→COOL | 16..30 | 不支持 |
| MIDEA | 同上 | 睡眠→SLEEP | 16..30 | 不支持 |

所有品牌 `setMode` 只接受 7 值；非标准入站值以 `raw` 保留、`kind=NON_STANDARD`、
`i18nKey=ac.mode.unknown`，不存在回发路径。

---

## 3. 实际命令与结果（当前 revision）

```bash
ohpm install
# install completed in 0s 57ms

hvigorw clean assembleHap --no-daemon
# BUILD SUCCESSFUL in 5 s 179 ms / 35 tasks

codelinter -c code-linter.json5 -p default .
# No defects found in your code.

entry/src/test/run-host-tests.sh
# tests 497 / pass 497 / fail 0
```

补充（设备骨架只编译，不执行）：

```bash
hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon
# BUILD SUCCESSFUL in 8 s 528 ms / 35 tasks
```

证据文件：

- `entry/src/test/evidence/t14-ohpm-install.log`
- `entry/src/test/evidence/t14-clean-assemble.log`
- `entry/src/test/evidence/t14-codelinter.log`
- `entry/src/test/evidence/t14-host-node-tests.tap`
- `entry/src/test/evidence/t14-ohosTest-assemble.log`

**测试计数**：当前 host 总数 497；T-14 新增 18 条（C-15 10 条 + C-16 8 条），
其余 479 条为既有回归。未把 `COMPILED_ONLY` 或设备 `BLOCKED` 写成 PASS。

---

## 4. Traceability

| 需求/约束 | 测试/实现 |
|---|---|
| FR-SET-003 云端配置 | `C15_service_configTokenStateAndTestConnection` |
| FR-HOME-001 云状态展示 | `CloudTransportState` / `CloudConfigView`；状态机测试 |
| PR-09 10 字段/无 `object_device_id` | `C15_cloudCommand_exactEnvelopeCanonicalAndHmac` |
| PR-10 受理≠执行 | `C15_responseMapping_2xxReceiptOnlyAndHttpErrors`、`C15_sendAndConfirm_acceptanceIsNotCompletion` |
| D-012 手工 Token | `AssetCloudCredentialStore`、401/403 状态测试 |
| D-014 固定属性一等公民 | `C15_completion_builtInDoubleMatchStaleAndVerification` |
| PB-02 inventory fail-closed | `C15_inventory_candidateMatchAndFailClosed` |
| A-CB-1 影子 DTO 假设 | `C15_shadow_threeShapesAndStrictInvalidCases` |
| FR-DEV-004 / CB §6.3 / PL-08 | `C16_*` 8 条测试 |
| CB §4.2 云错误命名空间 | `CloudErrors` + HTTP 映射测试 |

---

## 5. 设备与环境限制

| 项 | 状态 | 说明 |
|---|---|---|
| 真机/模拟器 `onDeviceTest` | **BLOCKED** | `hdc list targets` 为空、`signingConfigs: []`；未执行 |
| 设备测试 HAP 编译 | **COMPILED_ONLY** | `t14-ohosTest-assemble.log` BUILD SUCCESSFUL；不等于 PASS |
| 真实 IoTDA/IAM/影子 | **UNAVAILABLE** | 无真实 endpoint/token/tenant；所有 HTTP 为注入 fake |
| 平台 HTTPS 适配器 | **COMPILED_ONLY** | `OhosCloudHttpTransport` 仅编译；无网络运行证据 |
| `Brand` 显示资源 | **DEFERRED** | `brand.gree/haier/midea/generic` 键尚不在 `resources/**`（写范围外），由 C-24/C-27/i18n 资源任务补齐 |
| `ohos.permission.INTERNET` | **RISK（既有）** | `module.json5` 当前未声明；云/网关真实 HTTPS 运行前必须在清单任务中补齐（写范围外） |

---

## 6. 偏离项、假设与风险

1. **路径位置例外**：C-16 位于 `service/ac/**` 而非 `adapter/ac/**`；CloudPorts/新增模型位于
   `service/cloud/**` 而非 `contracts/**`/`model/**`。原因均为本任务写范围；接口语义未变。
2. **单云配置作用域**：`CloudConfig` 冻结形状无 `gatewayId`，无法实现 DES-B §8.3.1 的
   “命令 gatewayId 与云配置网关不一致 → `CLOUD_NOT_CONFIGURED`”检查。v1 按单 active 配置
   使用；多网关映射保留 `RISK-CLOUD-MULTIGATEWAY`，需要 Change Impact/后续配置模型扩展。
3. **A-CB-1**：IoTDA 错误体字段名未冻结；实现以 HTTP 状态为主映射
   （401→`TOKEN_EXPIRED`、403→`TOKEN_INVALID`、404/429/5xx/4xx 分别映射），
   响应体仅用于 `command_id` 与诊断，不构成成功判定。若真实 IoTDA 语义不同，需要调整映射。
4. **PB-02 非冻结**：`DeviceInventoryJson` 采用 §8.4 候选字段与 `PROPOSAL-PB02-1`
   的诊断口径；未升级为冻结契约。真实固件 schema 确认后需按 Change Impact 重写 parser/测试。
5. **`RdbCloudConfigStore` 与 v4 `cloud_config` 对齐**：直接消费 T-09 `DomainMigrations`
   已冻结的 v4 `cloud_config`（`singleton_id INTEGER PRIMARY KEY CHECK (singleton_id=1)` +
   `updated_at TEXT NOT NULL`），由 `ClockPort`（缺省 `Date.now()`，组合根应显式注入）
   写入 `updated_at`；`initialize()` 只校验 schema、不建表，`load/save/clear` 均以
   `singleton_id=1` 定位单例行。C-28 组合根必须按 DES-B §2.7 先执行 v1..v4 迁移再构造
   本存储。真实 v4 迁移库上的 `save/load/clear` 由 host 测试
   `C15_rdbConfigStore_v4MigrationInterop` 覆盖，未迁移库 fail-closed 由
   `C15_rdbConfigStore_neverCreatesItsOwnSchema` 覆盖（T-14 修复轮，见 `t14-fix-report.md`
   F-01）。
6. **`brand.*` i18n 键**：适配器只返回键（符合契约），资源文件当前缺失；不在本任务写范围。
7. **设备/真实网络未验证**：按 TEST-001 分类为 `BLOCKED`/`UNAVAILABLE`，不得视为发布证据。

---

## 7. 结论

C-15 与 C-16 的实现、host 测试、构建、lint 均在本 revision 通过；设备/真实云证据仍为
`BLOCKED`/`COMPILED_ONLY`。本报告不构成独立评审或 Stage Gate 通过。
