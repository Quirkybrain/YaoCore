# T-14 独立评审报告（C-15 CloudService + C-16 AC 品牌适配）

- **Artifact ID**: REVIEW-T14
- **Producer**: agent:quality-reviewer
- **Type**: Independent Code Review
- **Status**: **CHANGES_REQUIRED（代码级；不是 PASS）**
- **Date**: 2026-10-17
- **Task**: `wp-056-review-t14`（task 分支 `task/wp-055-cloud`，父分支 `feat/yaocore-app`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`（CQG-T14 前）
- **Reviewed revision**: `039adecee6d98541fe22e55441d07fe3caf6e0f7`（实现 diff `de1b9b6..039adec`，33 路径）
- **Review snapshot**: `refs/swe/snapshots/20261017T145857Z-wp-056-review-t14-22a0cc51`（commit `740e4053e94961aee94a4dd778e72577d431defd`）
- **Independence**: 本评审由未参与 T-14 实现、测试或实现报告编写的 `quality-reviewer` 执行。评审期间未修改任何被审产品代码、测试、证据或 `artifacts/50-implementation/t14-cloud-ac.md`；唯一仓库写入为本报告。行为探针通过 Node stdin 执行，未在仓库落盘。

> 结论先行：云命令 10 字段/HMAC、2xx 仅受理、双匹配完成判定、PB-02 inventory fail-closed、AC 七值/温度/非标准不回发、秘密卫生与构建测试主体质量良好。但存在 **1 个 High 阻断项**：`RdbCloudConfigStore` 自建 `cloud_config` 表与 T-09/DES-B §2.7 已冻结的 v4 `cloud_config` DDL（`singleton_id`/`updated_at`）不兼容，真实迁移后的库上配置读写会失败；实现报告 §6.5 对此的事实描述也不准确。另有 3 个 Medium 状态/完成判定缺口和 2 个 Medium 集成/资源缺口。**本轮不能给出 PASS，CQG-T14 应记为 CHANGES_REQUIRED。**

---

## 1. 范围、revision 与输入完整性

### 1.1 评审范围

```text
entry/src/main/ets/service/                  # 重点 service/cloud/** 与 service/ac/**，并核对被调用的 model/common/security/protocol/storage 边界
entry/src/test/                              # host 测试、CloudFakes、证据日志
entry/src/ohosTest/ets/test/                 # 设备骨架与注册
artifacts/50-implementation/t14-cloud-ac.md  # 实现报告（只读）
```

- 实际被审变更为 `de1b9b6..039adec` 的 **33 个路径**：C-15/C-16 产品代码 22 个（cloud 15 + ac 7）、host 测试/fake 3 个、ohosTest 2 个、实现报告 1 个、证据日志 5 个（`t14-*.log|tap`；其中 ohpm/assemble/codelinter/ohosTest 为 4 个日志 + 1 个 TAP，共 5 个）。
- 交叉读取但未修改：`model/CloudModels.ets`、`model/ControlModels.ets`、`model/DeviceState.ets`、`model/FamilyModels.ets`、`service/protocol/StateReportMapper.ets`、`service/security/CanonicalBuilder.ets`、`repository/DomainMigrations.ets`、`repository/GatewayPorts.ets`、`service/storage/*`。
- 明确排除：真实设备/模拟器、真实 IoTDA/IAM/影子、C-28 组合根、C-24/C-27 UI 与资源、用户验收、完整 Stage Gate。这些保持 `BLOCKED`/`COMPILED_ONLY`/`UNAVAILABLE`，本报告不将其写成 PASS。

### 1.2 输入 pin 与快照

handoff 的 9 个 `inputs` SHA-256 **9/9 一致**；`config/git-policy.json` 的 SHA-256（`3b8ddffd…`）与 handoff 一致；复验前后 `git status` clean，HEAD = `039adec`，任务计划 **33 路径** 与 commit 一致。

| 输入 | SHA-256 前 12 位 | 结果 |
|---|---|---|
| `artifacts/50-implementation/t14-cloud-ac.md` | `de5a46fa8a54` | 一致 |
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | `8d094bb5affa` | 一致 |
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `3a02ecbf266b` | 一致 |
| `artifacts/20-architecture/contract-baseline.md` | `883e09bb34ea` | 一致 |
| `artifacts/20-architecture/project-constraints.md` | `283046210e68` | 一致 |
| `artifacts/60-testing/test-plan.md` | `33485cc39abd` | 一致 |
| `input/api/Gateway_API_Specification.md` | `b8961ead830b` | 一致 |
| `input/api/protocol/cloud-command.schema.json` | `ce70a1396a62` | 一致 |
| `input/api/protocol/state-report.schema.json` | `6233f8292512` | 一致 |
| `config/git-policy.json` | `3b8ddffd4494` | 一致 |

### 1.3 本评审实际复验（cwd = 仓库根）

| 命令 | 结果 | 说明 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS：497 tests / 497 pass / 0 fail / 0 skipped / 0 todo，exit 0** | 与 `entry/src/test/evidence/t14-host-node-tests.tap` 的 497/497 一致；T-14 新增 18 条（C-15 10 + C-16 8），基线 479 条（T-13 修复后）无删除 |
| `codelinter -c code-linter.json5 -p default .` | **PASS：No defects found in your code，exit 0** | 与 `t14-codelinter.log` 一致 |
| `hvigorw clean assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0**（35 tasks；34 executed / 1 up-to-date） | 与 `t14-clean-assemble.log` 一致 |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0**（35 tasks） | 与 `t14-ohosTest-assemble.log` 一致；**仅编译，不是设备执行** |
| `python3 entry/src/test/i18n/check_i18n.py --root . --strict-ui` | **PASS：CHK-01..09 全部 PASS，0 blocking findings，13 warnings** | 新增代码触发 6 条 CJK 协议别名 warning + 1 条 SQL 字符串 warning；详见 F-08 |
| `git status --short` / `git diff --stat` | **PASS：clean / 空** | 构建与 lint 未产生跟踪文件变化 |

测试证据核对：`t14-host-node-tests.tap` 的 497 条 `ok` 与本次独立复跑一致；T-14 的 18 个用例名（10 个 `C15_*` + 8 个 `C16_*`）均实际执行；`t14-clean-assemble.log`、`t14-ohosTest-assemble.log`、`t14-codelinter.log`、`t14-ohpm-install.log` 的命令与结果与实现报告 §3 一致。

### 1.4 独立只读探针（通过 stdin，不落盘）

除现有测试外，本评审直接调用真实 `CloudService`/`CloudCompletionEvaluator` 与共享 host fake，确认了三个关键行为：

1. **token 过期状态被无 token 的 saveConfig 复位**（F-02）：
   `401 → CLOUD_TOKEN_EXPIRED`，`getState()=TOKEN_EXPIRED`；随后 `saveConfig(config)`（不传 token）→ `getState()=CONFIGURED`，而旧 token 仍在 credentials 中。
2. **testConnection 成功不清除 UNAVAILABLE**（F-03）：
   两次 500 → `getState()=UNAVAILABLE`；随后 `testConnection()` 读取到 200 影子（`valid=true`）→ `getState()` 仍为 `UNAVAILABLE`。
3. **Gateway 目标可经 inventory 被 CONFIRMED**（F-04）：
   期望 `target=Gateway`、`requestId=req-<NOW>-7`、`seq=7`；影子 `DeviceInventoryJson` 含 `device_id=Gateway` 且携带匹配的 `last_request_id/last_seq/event_time` → 判定 `CONFIRMED`（`CONFIRMED_INVENTORY`，`stateVerification=MATCH`），而 DES-B §8.1.6 规则 2 要求 `Gateway`/其他固定名无云完成属性时返回 `UNSUPPORTED`。

探针仅使用内存 fake 与公开测试数据，不构成设备/真实云证据。

---

## 2. Findings

严重度定义：**High** = 会导致真实迁移/主链路失败、可绕过核心 fail-closed 语义或阻断 CQG-T14；**Medium** = 契约/状态/集成/测试缺口，需修复或书面裁定；**Low/Info** = 卫生、并发、文档与已登记残余。低级别项不单独阻断，但应进入 CQG 记录。

| ID | 严重度 | 位置 | 契约/依据 | 问题/影响 | 建议 |
|---|---|---|---|---|---|
| **F-01** | **High（数据/集成，阻断）** | `CloudConfigStore.ets:25-31`（自建 DDL）、`:34-55`（`id` 列读写）；对照 `repository/DomainMigrations.ets:48-56`；`t14-cloud-ac.md:212` | DES-B §2.7 v4 DDL；§8.1.3；T-09 v4 迁移 | v4 迁移的 `cloud_config` 为 `singleton_id INTEGER PRIMARY KEY …`、`updated_at TEXT NOT NULL`、`CHECK(singleton_id=1)`；T-14 的 `RdbCloudConfigStore` 却使用 `id TEXT PRIMARY KEY` 且无 `updated_at`。真实启动顺序（DES-B §2.7 step 4 v4 迁移先于 step 19 CloudConfigStore）下，`initialize()` 的 `CREATE TABLE IF NOT EXISTS` 静默 no-op，随后 `SELECT/INSERT/DELETE … WHERE id=?` 因无 `id` 列失败；若 `initialize()` 先跑，则创建了与冻结 v4 不同的表，v4 迁移因 `IF NOT EXISTS` 失去约束。设备骨架在全新库直接 `initialize()`，恰好掩盖冲突。实现报告 §6.5 “尚未纳入 C-06 迁移注册表”与事实不符（v4 `DomainMigrations` 已纳入） | 对齐 DES-B §2.7：使用 `singleton_id=1` + `updated_at`（通过注入 `ClockPort` 或可靠时间源写入），删除/改造 `initialize()` 为“只校验不建表”；补一条 host/设备测试：先跑 v1..v4 迁移，再打开 `RdbCloudConfigStore` 完成 save/load/clear；同步修正实现报告 §6.5 与 traceability |
| **F-02** | **Medium（状态机/UX）** | `CloudService.ets:133-149`（`saveConfig` 末尾 `resetFailureState`）、`:375-381` | DES-B §8.3.1：`TOKEN_EXPIRED/INVALID --> CONFIGURED: saveConfig(new token)`；D-012 手工 Token | 401/403 已把 `tokenFailure` 置为 `TOKEN_EXPIRED/INVALID`；调用 `saveConfig(config)` 不传新 token 时仍执行 `resetFailureState()`，状态回到 `CONFIGURED`，旧 token 未更换。UI 会丢失“令牌已过期、请更新”的提示，下一次发送继续用旧 token；与状态机“仅新 token 才能回到 CONFIGURED”不一致（探针已复现） | 仅在 `token !== undefined && token.length > 0` 时清除 `tokenFailure/authFailureAt`；`token=''` 显式清除 token 时回到 `TOKEN_MISSING`；不传 token 时保留过期状态。补 `401 → TOKEN_EXPIRED → saveConfig(no token) 仍 TOKEN_EXPIRED → saveConfig(new token) CONFIGURED` 测试 |
| **F-03** | **Medium（契约冲突/恢复）** | `CloudService.ets:182-204`（`testConnection` 成功路径）、`:369-373`（`recordNetworkSuccess` 未调用） | DES-B §8.3.1：`UNAVAILABLE --> CONFIGURED: testConnection success`；§8.1.7 又写 testConnection“不写入状态” | 两次网络失败后 `unavailable=true`；`testConnection()` 成功时只返回 `valid=true`，不清除 `unavailable`，`getState()` 仍为 `UNAVAILABLE`（探针已复现）。用户在“测试连接成功”后仍看到云不可用；两条规范的“不写入状态”与状态迁移存在冲突，当前实现选择了两者都不满足的行为 | 由 architect 书面裁定冲突：建议成功时调用 `recordNetworkSuccess()` 并通知（不写入“失败状态”不等于不恢复成功），补 `UNAVAILABLE → testConnection 成功 → CONFIGURED` 测试；若坚持 testConnection 完全只读，则把该 UI 恢复路径改由 `send`/`getState` 明确承担并记录 |
| **F-04** | **Medium（完成判定 fail-closed）** | `CloudCompletionEvaluator.ets:53-63`（只判 `Sensor_01/Presence_01` 只读后直接进入 inventory）、`:101-146` | DES-B §8.1.6 规则 2/§8.3.3：`Gateway`/其他固定名无云完成属性 → `UNSUPPORTED`；PR-10 | `Gateway` 目标不在 `FIXED_PREFIXES` 与 `READ_ONLY_FIXED` 中，落入 inventory 查找。若影子 `DeviceInventoryJson` 含 `device_id=Gateway` 且携带匹配的 `last_request_id/last_seq/event_time`，会返回 `CONFIRMED`（探针已复现），违反“Gateway/其他固定名无载体 → UNSUPPORTED”和“绝不乐观成功”。现有测试只用“inventory 无 Gateway 条目”的负例，未覆盖此路径 | 在进入 inventory 前显式拦截 `Gateway` 与已知固定名（可维护一个 `NON_INVENTORY_FIXED` 集合），返回 `UNSUPPORTED`（`CLOUD_COMPLETION_UNSUPPORTED` 或 `CLOUD_INVENTORY_UNSUPPORTED`）；补“inventory 冒充 Gateway”回归测试。若上游认为 Gateway 可走 inventory，必须修订 DES-B 并书面裁定 |
| **F-05** | **Medium（i18n/集成）** | `AcModels.ets:152-154`（`brandI18nKey` 返回 `brand.*`）；`AcAdapterFactory`/四个 adapter 的展示路径；`resources/rawfile/i18n/{en-US,zh-CN}.json` | DES-B §9.1 `brandI18nKey`；I18N-02；`docs/internationalization.md` key parity | `brand.gree/haier/midea/generic` 在 en-US/zh-CN 两份 locale 中均不存在；适配器只返回键（符合“不调用 t()”），但 C-16 的展示路径在资源补齐前会显示原始键。`brand.*` 是动态构造键，CHK-06/CHK-07 不会报 missing key。实现报告已登记 `DEFERRED`，但没有对应的 Gate/跟踪 ID | 由 i18n 资源归属任务（C-24/C-27 或 T-18）补齐四个 `brand.*` 键并验证 zh/en parity；在 CQG-T14/CQG-T10 记录跨组件依赖；为动态 `brand.*` 增加 checker 覆盖或显式 allowlist，避免“看起来通过” |
| **F-06** | **Medium（多网关/契约缺口，已登记）** | `CloudCommandClient.ets:93-171`（URL 用 `config.deviceId`，secret/seq 用 `command.gatewayId`）；`CloudService.ets:223-245`（ShadowReader 只用 `config.deviceId`） | DES-B §8.3.1 最后一条：命令 `gatewayId` 与云配置网关不一致 → `CLOUD_NOT_CONFIGURED`；`CloudConfig` 无 `gatewayId` | 当前没有把 `command.gatewayId` 与 active 云配置网关做一致性校验；`CloudConfig` 冻结形状无 `gatewayId`，DES-B 自己也承认这是 Change Impact。多网关家庭下，命令可能按 B 的 secret 签名却发往 A 的 IoTDA 设备/影子；v1 单 active 配置下可解释，但必须在 UI/验收中明确 | 由 architect 走 Change Impact：扩展 `CloudConfig`/映射表增加 `gatewayId`，或在 v1 明确“单网关云配置”限制并在 `CloudService` 入口拒绝无法映射的 gateway；补配置/命令不一致负例。保留 `RISK-CLOUD-MULTIGATEWAY` 跟踪 |
| **F-07** | **Low（测试完整性）** | `CloudService.test.mjs`（`enqueueError` 未使用；无 service 级 UNSUPPORTED/INVALID）；`CloudDevice.test.ets:46-67`（新库直接 `initialize()`）；`DeviceInventoryParser` 负例 | DES-B §8.5 host 测试清单；TEST-001 CQG-T14；D-019 | 18 条新用例覆盖主路径与多数负例，但仍有缺口：传输抛错→`CLOUD_REQUEST_FAILED` 映射未覆盖；service 级 `UNSUPPORTED`/`INVALID` 返回未覆盖；F-02/F-03 状态路径未覆盖；F-01 的迁移兼容没有测试；429 重试未单独覆盖（500 覆盖同一分支）；inventory parser 的根为对象/非法 `event_time` 未单测 | 按风险补 example 级测试；设备骨架改为先跑 v1..v4 迁移再测 `RdbCloudConfigStore`；保持设备 `BLOCKED` 标签 |
| **F-08** | **Low（i18n 卫生/诊断）** | `AcAdapterFactory.ets:36-42`、`GreeAcAdapter.ets:16`、`HaierAcAdapter.ets:16`、`MideaAcAdapter.ets:16`；`CloudConfigStore.ets:51`；CHK-07 13 warnings | DES-B §9.1（中文别名是协议别名、allowlist 登记）；I18N-02；DES-B §9.2（未知品牌记录诊断） | `chinese` 字面量是协议入站别名而非用户可见文案，DES-B §9.1 明确允许，不应作为 UI 硬编码阻断；但当前 allowlist 只按 key 前缀登记，CHK-07 仍以 warning 记录。`CloudConfigStore` 的 SQL 字符串被误报为英文句子。另：`normalizeBrand` 对未知品牌回退 GENERIC 时没有可观察的诊断（DES-B §9.2 要求“记录诊断”），纯工厂也没有 logger | 把品牌/模式别名集中为显式的 `PROTOCOL_ALIASES` 常量并登记到 i18n allowlist/说明；在调用侧记录 `unknown brand → GENERIC` 诊断（工厂保持纯函数）；SQL warning 作为已知误报记录。不要把这些 warning 写成 UI 文案违规 |
| **F-09** | **Low（并发/生命周期）** | `SystemTimerPort.ets:13-49`（单 `timer`/`rejecter`）；`CloudCancellation.ets:13-22`（父监听不移除）；`CloudModels.ets:284`（`maxShadowAgeMs` 未用）；`CloudCommandClient.ets:235`（`errorMessage` 未用） | DES-B §8.1.7/§8.5；§2.8 取消/定时器 | `SystemTimerPort` 只有一个定时器槽；若被并发 `awaitCompletion` 或与其他组件共享，第二个 `sleep` 会覆盖第一个的 timer/rejecter。`CloudService.pollCancellation` 也只有一个槽，两个并发轮询时 `stopPolling` 只能取消后者。`maxShadowAgeMs` 未使用（离线判定不在本任务） | 在 `CloudService`/组合根明确“单 active 轮询、每个 CloudService 独立 `SystemTimerPort`”；若未来需要并发，改为多槽 timer 并补测试；对 `maxShadowAgeMs`/`errorMessage` 的未用字段加注释或移除。均为 Low，不单独阻断 |
| **F-10** | **Low（契约边界）** | `DeviceInventoryParser.ets:41-47` | DES-B §8.4：`DeviceInventoryJson` ≤8192 **字符**；state-report schema `maxLength: 8192` | 实现额外检查 UTF-8 字节数 ≤8192。若合法 inventory 含多字节内容（如允许的非 ASCII `mode/state_source`），字符数合规但字节数超限会被判 `CLOUD_INVENTORY_UNSUPPORTED`。方向是 fail-closed，不是安全漏洞，但比契约更严格 | 保留字符上限为权威；字节上限若作为防 DoS 需要，明确写进契约/报告并测试边界；否则移除字节检查，避免合法 inventory 被误拒 |
| **F-11** | **Info（过程/范围）** | `t14-cloud-ac.md` §5/§6；`entry/src/main/module.json5`；DES-B §8 路径 / §9 路径 | 路径例外；SC-01/SC-09；CP-05 | 路径例外（C-16 在 `service/ac` 而非 `adapter/ac`、CloudPorts/模型在 `service/cloud`）已记录且与既有任务先例一致，本评审接受；`ohos.permission.INTERNET` 缺失（既有清单，写范围外）会阻断真实云；A-CB-1 的 IoTDA 错误体假设、PB-02 固件 schema 未冻结、设备/真实云 `BLOCKED`/`UNAVAILABLE` 均如实登记。TEST-001 的 CQG-T14/C-15/C-16 行仍为 `NOT_RUN`，需 Gate 后由 test-engineer/Orchestrator 更新 | 路径迁移放入 C-28；INTERNET 权限在清单任务补齐；A-CB-1/PB-02 保持 `UNVERIFIED`/`FIRMWARE_PENDING`；不要把本报告当 Stage Gate |

### 2.1 F-01 关键阻断项展开

```text
DES-B §2.7 v4（DomainMigrations.ets:48-56，已实现并测试）:
  cloud_config(
    singleton_id INTEGER PRIMARY KEY NOT NULL,
    endpoint TEXT NOT NULL, project_id TEXT NOT NULL, device_id TEXT NOT NULL,
    access_token_alias TEXT NOT NULL, shadow_endpoint TEXT,
    updated_at TEXT NOT NULL, CHECK (singleton_id = 1))

T-14 CloudConfigStore.ets:25-55:
  cloud_config(
    id TEXT PRIMARY KEY NOT NULL, endpoint, project_id, device_id,
    access_token_alias, shadow_endpoint)              -- 无 singleton_id / updated_at
  SELECT ... WHERE id = ?; INSERT OR REPLACE (id,...); DELETE WHERE id = ?
```

- 组合根顺序（DES-B §2.7）：StorageService/migrations（step 4）先于 CloudConfigStore（step 19）。v4 表已存在时，`initialize()` 的 `CREATE TABLE IF NOT EXISTS` 不会改表；`load/save` 对 `id` 的读写会报 SQL 错误（无此列），云配置无法持久化。
- 若 `initialize()` 在迁移前被调用：创建了 `id` 表，v4 迁移因 `IF NOT EXISTS` 跳过，`singleton_id`/`updated_at`/`CHECK` 全部丢失，违反冻结 DDL。
- `CloudDevice.test.ets` 在全新库直接调用 `RdbCloudConfigStore.initialize()`，只验证了该实现自定义的 schema，未验证 v4 迁移后的互操作；这也是测试未被发现的原因。
- 实现报告 §6.5 把问题描述为“尚未纳入 C-06 迁移注册表”，与 `DomainMigrations.ets` 的 v4 事实不符；应改为“与 v4 DDL 列名/主键/updated_at 不一致”，并给出修复后的测试证据。

### 2.2 其它关键项展开

#### F-02 — 无 token 的 saveConfig 复位过期提示（Medium）

- 入口：`CloudService.saveConfig(config, token?)` 在任何分支都执行 `resetFailureState()`。
- 复现：发送 401 → `getState()=TOKEN_EXPIRED`；`saveConfig(config)` → `getState()=CONFIGURED`，且 `credentials.token` 仍是旧值。
- 契约：DES-B §8.3.1 明确规定只有 `saveConfig(new token)` 才从 `TOKEN_EXPIRED/TOKEN_INVALID` 回到 `CONFIGURED`；D-012 要求用户手动更新 token。当前行为会让 UI 误以为已恢复。
- 修复：以“是否提供了新的非空 token（或显式清空）”作为复位条件；补状态测试。

#### F-03 — testConnection 成功不恢复 UNAVAILABLE（Medium）

- 复现：两次 500 → `UNAVAILABLE`；`testConnection()` 200 影子 → `valid=true`，`getState()` 仍 `UNAVAILABLE`。
- 契约冲突：§8.3.1 有 `UNAVAILABLE -> CONFIGURED: testConnection success`；§8.1.7 说 testConnection“不写入状态”。当前实现既不清除失败状态，也未通知。
- 处理：由 architect 裁定；如果按状态机，成功时 `recordNetworkSuccess()`（并 `notify()`）即可；如果按“不写入状态”，需把恢复路径明确移到别处并记录。无论哪种，都应有测试。

#### F-04 — Gateway 目标可经 inventory 确认（Medium）

- 复现：期望 `target=Gateway`、`action=TURN_ON`；影子带 `DeviceInventoryJson=[{device_id:"Gateway", last_request_id:<匹配>, last_seq:<匹配>, event_time:<新鲜>}]` → `CONFIRMED`。
- 契约：DES-B §8.1.6 规则 2 规定 `Gateway`/其他固定名无云完成属性 → `UNSUPPORTED`；§8.3.3 流程图同样先判断内置固定属性。
- 修复：在 `evaluate()` 进入 inventory 前维护“禁止 inventory 的固定名”集合（至少 `Gateway`，并覆盖已知固定名），返回 `UNSUPPORTED`；补回归测试。

#### F-05/F-06 — 跨组件与上游缺口（Medium，跟踪项）

- F-05：`brand.*` 两份 locale 均缺失，适配器返回键本身正确；必须在 C-24/C-27/T-18 的资源任务补齐，并在 CQG/Stage Gate 中保留依赖，不要以“测试通过”掩盖展示层缺口。
- F-06：多网关映射是 DES-B 自己承认的 `RISK-CLOUD-MULTIGATEWAY`；T-14 的单 active 配置可接受为 v1 限制，但必须由 Change Impact/ADR 或 UI/验收书面说明，不能默认多网关安全。

---

## 3. 契约符合性评估（按评审重点）

| # | 评审重点 | 结论 | 证据/说明 |
|---|---|---|---|
| 1 | 云命令签名：10 字段 canonical/HMAC、`CmdId=3001`、`paras` 无 `object_device_id`、不复用网关 `result_code` | **符合** | `CloudCommandClient` + `CanonicalBuilder.cloudCommand`；host 测试用 Node `crypto` 独立计算 HMAC；body 字段顺序/值、无 `object_device_id`、`CmdId=3001`、`Alg/KeyId`、`X-Auth-Token` 均验证；错误码为 `CLOUD_*` 字符串，不混用 §4.1 数值空间 |
| 2 | 完成判定：2xx 仅受理；`LastRequestId`+`LastSeq` 双匹配 + 新鲜度才 `CONFIRMED`；重放/旧序号/时间戳边界；不得乐观成功 | **基本符合，F-04 缺口** | `sendAndConfirm` 2xx 后仍轮询；双匹配 CONFIRMED、单匹配 PENDING、3s 旧影子 STALE、2s 边界 CONFIRMED、未来 >5min INVALID、MISMATCH 仍 CONFIRMED（按 DES）、SET_COLOR UNVERIFIED；`Gateway` 可经 inventory 确认违反规则 2（F-04） |
| 3 | PB-02 fail-closed：缺字段/重复/越界/超限/未知结构 → `CLOUD_INVENTORY_UNSUPPORTED` 且绝不 CONFIRMED；内置固定路径不受非法 inventory 影响 | **符合（inventory 结构层面）** | `DeviceInventoryParser` 严格字段/上限/重复/类型；解析失败由 `ShadowDtoAdapter` 标记 `inventoryUnsupported`；固定路径先于 inventory，非法 inventory 不阻断 Door/Light/AC 完成；18 条测试含缺 seq、重复、33 条、8193 字符负例；未知字段按 §8.5 忽略并记录。F-04 是固定名路由问题，不是 parser 结构问题 |
| 4 | Token：手工管理/无自动刷新/过期提示（401/403 语义）；无秘密日志 | **部分符合（F-02/F-03）** | Token 只在 Asset Store；`X-Auth-Token` 头；无刷新代码；401→`CLOUD_TOKEN_EXPIRED`、403→`CLOUD_TOKEN_INVALID`，不自动重试；日志/错误 details 不含 token（测试与探针检查）；但无 token 的 saveConfig 会复位过期提示（F-02），testConnection 成功不恢复 UNAVAILABLE（F-03） |
| 5 | AC 适配：7 值 mode、16..30°C、非标准模式保留原文但不可回发；品牌归一化/未知回退；纯映射无网络/仓储 import | **符合（资源缺口 F-05）** | 四品牌均共享 7 值/16..30/无颜色/无风速；`setMode` 运行时二次校验；`normalizeInboundMode` 保留 raw 并标 NON_STANDARD；Gree/Haier/Midea 入站别名；Factory 归一化 ASCII/中文/组合别名，未知回退 GENERIC；静态扫描无 `@ohos`/网络/仓储/i18n import；`brand.*` 资源键缺失（F-05） |
| 6 | 安全/错误：云错误命名空间、敏感信息、fail-closed 完整性 | **符合** | `CloudErrors` 全部 `CLOUD_*`；`ErrorCatalog` 映射到 `errors.cloud.*`/`cloud.*`；`AppError.details` 只含 httpStatus/requestId/seq/deviceId/shape；签名 secret 在回调内使用并清零 HMAC 结果；TLS 适配器仅 HTTPS、拒绝 pin 策略；无 token/body/cert 日志 |
| 7 | 测试质量：18 新用例（497/497）有效性、负例覆盖；设备骨架诚实（COMPILED_ONLY/BLOCKED） | **基本符合（F-07 缺口）** | 18 条实际执行；主路径/错误映射/双匹配/边界/PB-02/AC 边界均覆盖；设备骨架标注 `BLOCKED_ON_DEVICE_RUNNER`，未写成 PASS；缺口见 F-07（传输抛错、service 级 UNSUPPORTED/INVALID、F-01 迁移、429、F-02/F-03 状态） |
| 8 | 过程：33 路径范围；证据一致；路径例外（service/ac、service/cloud）记录合理 | **符合，报告 §6.5 需更正** | commit 33 路径与 handoff 一致；5 个证据日志 + TAP 与报告命令/计数一致；C-16/CloudPorts 路径例外已在报告 §1.2/§6.1 记录且与 T-06/T-07/T-08/T-11 先例一致；但 §6.5 对 v4 迁移的描述与事实不符（F-01） |

---

## 4. 残余风险与跟踪

| 风险/缺口 | 级别 | 跟踪建议 |
|---|---|---|
| `cloud_config` 与 v4 DDL 冲突（F-01） | **High / 阻断** | 修复前不授予 CQG-T14；修后补迁移兼容测试并复审 |
| `saveConfig` 无 token 复位过期状态（F-02） | Medium | 修复并补状态测试；与 D-012 UI 提示联动 |
| testConnection 成功不恢复 UNAVAILABLE（F-03） | Medium | architect 裁定 §8.1.7 与 §8.3.1 冲突；按裁定实现并测试 |
| `Gateway` 经 inventory 被 CONFIRMED（F-04） | Medium | 显式固定名拦截 + 回归测试；与 PR-10/“绝不乐观成功”一起复核 |
| `brand.*` locale 键缺失（F-05） | Medium | C-24/C-27/T-18 资源任务补齐；CQG/Stage Gate 记录依赖 |
| 多网关云配置映射（F-06） | Medium | `RISK-CLOUD-MULTIGATEWAY`；Change Impact/ADR 或 v1 书面限制 |
| 传输错误/service 级 UNSUPPORTED/INVALID/F-02/F-03 测试缺口（F-07） | Low | 修复轮补测；设备骨架先迁移再测 |
| 中文协议别名/SQL warning（F-08） | Low | allowlist/协议常量；未知品牌诊断由调用侧记录 |
| SystemTimerPort/CloudCancellation 并发与未用字段（F-09） | Low | C-28 明确单 active 轮询/独立 timer；后续多槽化 |
| inventory 字节上限严于契约（F-10） | Low | 明确契约或移除字节检查 |
| `ohos.permission.INTERNET` 未声明（既有） | RISK | 真实云运行前的清单任务必须补齐；本任务写范围外，不能写成已可运行 |
| A-CB-1（IoTDA 错误体字段未冻结） | RISK | 以 HTTP 状态为主映射；真实 IoTDA 联调后按 Change Impact 调整 |
| PB-02 固件 schema 未冻结 | `UNRESOLVED` | 合成 fixture 仅 `PUBLIC TEST DATA ONLY`；真实固件确认后重写 parser/测试 |
| 设备/真实云证据 | `BLOCKED`/`COMPILED_ONLY`/`UNAVAILABLE` | 不得作为 CQG-T14 PASS 或 Stage Gate 证据；C-28 后再补真机/IT |

---

## 5. Verdict 与复验要求

**Verdict: CHANGES_REQUIRED。**

- **F-01 阻断**：`RdbCloudConfigStore` 必须与 DES-B §2.7 v4 `cloud_config` DDL 对齐，修复真实迁移库上的读写；实现报告 §6.5 必须更正并给出新证据。
- **F-02/F-03/F-04** 必须在下一轮修复或由 architect/用户给出书面裁定；每项都要有回归测试。
- **F-05/F-06** 作为跨组件/上游跟踪项，必须在 CQG/Stage Gate 记录；F-07 补测试；F-08/F-09/F-10 卫生/限制项可随修复轮处理。
- 修复后必须重新执行：`entry/src/test/run-host-tests.sh`、`codelinter`、`hvigorw clean assembleHap --no-daemon`、ohosTest 编译，并对新 revision 重新独立评审；不得复用本 revision 的测试/评审证据。
- 设备与真实云仍为 `BLOCKED`/`COMPILED_ONLY`/`UNAVAILABLE`；本报告不授予 STABLE、CQG-T14、Integration Gate 或 Stage Gate。

---

## 6. 独立性与过程声明

- 本评审由未参与 T-14 实现的 `quality-reviewer` 执行；作者与评审者分离。
- 只读边界：未修改被审代码、测试、证据、快照或 `t14-cloud-ac.md`；唯一仓库写入为本报告 `artifacts/70-review/t14-review.md`。
- 3 个行为探针通过 `node --import entry/src/test/host/register-ets.mjs --input-type=module -` stdin 执行，未写入仓库；使用公开测试数据与内存 fake，不构成设备/真实云证据。
- 评审以 `039adec` 为唯一 revision；实现报告、输入 pin、快照 ref 与任务分支一致。
