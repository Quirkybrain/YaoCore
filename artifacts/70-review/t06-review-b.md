# T-06 复审（第二次）：R-01..R-13 关闭确认与 CQG-T06 意见

- **Artifact ID**: REV-T06-002
- **Producer**: agent:quality-reviewer
- **Type**: Independent Re-Review / CQG-T06 Evidence
- **Status**: **PASS（带已记录 Low 残余/例外；不授予 STAGE 或用户验收）**
- **Date**: 2026-10-17
- **Task**: `wp-015-review-t06b`（task 分支 `task/wp-012-foundation`，父分支 `feat/yaocore-app`，base commit `4d97e41`）
- **Reviewed revision**: `4d97e41d1a0cba278ba99631c7625e00b1a185aa`（parent `5eb4d67a34aa384bc40ef20304c1e7d14d4961cd`；上轮评审 `5eb4d67`，上轮被评审实现 `4d361bd`）
- **Review scope**: `4d97e41` 的 24 文件修复提交；10 个产品文件 + 14 个测试/证据/修复报告；详见 §1
- **Review snapshot**: `refs/swe/snapshots/20261017T081142Z-wp-015-review-t06b-7764c1a5`（`e83599ce5b7296f17ab38f98ab25aa0d16358c3e`）
- **Independence**: **本报告由未参与 T-06 实现、也未参与本轮修复的质量评审者（agent:quality-reviewer）编写；T-06 实现者为 agent:implementation-engineer，修复者为同一实现角色。本复审为作者之外的独立复审，作者不能批准本报告，也不能以本报告替代 CQG 或 Stage Gate 决策。**

> 结论先行：上轮 **R-01、R-02、R-03 三个 Medium 均已关闭**；R-05..R-13 关闭；**R-04 的核心缺陷（非零 ACK 未校验 `reported_state`）已关闭**，但其“失败一律抛 `ACK_PROTOCOL_VIOLATION`”的报告措辞对“缺少 required 字段”不成立，作为 Low 残余转入 R2-01。构建、lint、88/88 host 测试均独立复跑通过；未发现新的 High/Critical 或阻塞性回归。判定 **PASS**，可进入合并与 CQG-T06，但必须在 CQG 记录 R-13 目录例外、R2-01/R2-02 Low 残余与 Hypium/设备侧阻塞状态。

---

## 1. 复审范围、输入与独立性

### 1.1 范围

`git show --name-only 4d97e41` 共 24 文件，全部落在 handoff 的 `review_targets` / `writes` 范围内：

| 类别 | 路径 | 文件数 |
|---|---|---:|
| C-01 公共类型/常量/工具 | `entry/src/main/ets/common/**` | 3 |
| C-02 领域模型共享面 | `entry/src/main/ets/model/**` | 2 |
| C-03 协议 DTO/映射 | `entry/src/main/ets/service/protocol/**` | 5 |
| Node host 测试 | `entry/src/test/host/*.test.mjs` | 5 |
| Hypium host 测试 | `entry/src/test/protocol/*.test.ets` | 2 |
| 测试 README/证据 | `entry/src/test/README.md`、`entry/src/test/evidence/t06-fix-*` | 6 |
| 修复报告 | `artifacts/50-implementation/t06-fix-report.md` | 1 |
| **合计** | | **24** |

核对结果：

- 未修改 `contracts/**`、`repository/**`、`service/cloud/**`、`input/**`、`ohosTest` 契约夹具、构建配置或签名/nonce 生成实现（T-07 边界未越界）。
- 未发现 `build/`、`.hvigor/`、HAP/HAR、证书、私钥、Token 或真实凭据入库；构建产物仍为 ignored。
- 工作树在复审开始时为 clean；本复审唯一写入为本报告。

### 1.2 权威输入与 pin 校验

| 输入 | SHA-256 核对 |
|---|---|
| `artifacts/70-review/t06-review.md`（上轮评审 REV-T06-001） | `4894498a…d166696a`，与 handoff 一致 |
| `artifacts/50-implementation/t06-fix-report.md` | `371cdb86…d5e1f8d2`，与 handoff 一致 |
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `5599e693…bfe1c1`，与 handoff 一致 |
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | `0b417932…80ef1c`，与 handoff 一致 |
| `artifacts/20-architecture/contract-baseline.md` | `6673a990…fadee89`，与 handoff 一致 |
| `artifacts/20-architecture/project-constraints.md` | `28304621…23da9528`，与 handoff 一致 |
| `artifacts/60-testing/test-plan.md` | `33485cc3…56055fae`，与 handoff 一致 |
| `config/git-policy.json` | `3b8ddffd…9241a014`，与 handoff 一致 |

### 1.3 明确排除

以下结论不属于 T-06 复审，且不写成 PASS：

- **HMAC/签名/验签/nonce 生成**：T-07/C-05；T-06 只定义端口、序列化已签名 DTO 和结构门。
- **存储/仓储/端口迁移**：T-08/T-09；`common/types/Ports.ets` 的物理位置为已记录例外（R-13）。
- **真实 BLE/TLS/设备/云完成判定**：无真实设备、无 IoTDA 联调；`onDeviceTest`、Hypium 运行时、TLS pin、BLE、云完成判定为 `BLOCKED`/`UNAVAILABLE`。
- **`DeviceInventoryJson` 内部解析/云完成判定**：T-14/PB-02；T-06 只保留字符串属性。
- **CQG/Stage Gate/用户验收**：本报告只提供复审证据和建议；最终 Gate 由 Orchestrator 决定。

### 1.4 方法

1. **Diff first**：先读 `5eb4d67..4d97e41` 的 24 文件 diff，再读周边实现与判定链。
2. **逐条对照**：R-01..R-13 的原始 finding、修复报告逐条处置表、DES-A/DES-B/CB/PC/TEST-001 的对应条款。
3. **代码事实优先**：不以修复报告“声称”作为关闭依据；对每个 finding 定位到实际代码与测试断言。
4. **定向探针**：加载被测 `.ets` 模块，对 ACK 错误码、非零 ACK、缺 required 字段、V-01 nonce、SERVICES 严格性做独立探针。
5. **独立复跑**：`entry/src/test/run-host-tests.sh`、`codelinter`、`hvigorw clean assembleHap`；核对 `git show`/`git status`/输入哈希。
6. **只读边界**：未修改任何被测文件；唯一写入是本报告。`swe_guard` snapshot 覆盖评审目标，`finish` 会再次校验字节一致性。

---

## 2. 复验证据（本次复审独立执行）

### 2.1 命令与结果

```text
$ entry/src/test/run-host-tests.sh
1..88
# tests 88
# pass 88
# fail 0
# cancelled 0
# skipped 0
# todo 0
# duration_ms 612.275496
exit 0

$ codelinter -c code-linter.json5 -p default .
No defects found in your code.
exit 0

$ hvigorw clean assembleHap --no-daemon
BUILD SUCCESSFUL in 7 s 276 ms
35 tasks in total: 34 executed, 1 up-to-date
WARN: Will skip sign 'hos_hap'. No signingConfigs profile is configured...
exit 0
```

说明：

- host 测试 88/88 与修复报告 `t06-fix-host-node-tests.tap` 一致；8 个新增/替换用例均出现在 TAP 中（`unknownFieldsUseAckProtocolViolationInAllShapes`、`nonZeroResultStillValidatesReportedStateSchema`、`nonStandardModeComparesRawValue`、`fixtureNoncesAreOutsideOutboundContract`、`enforcesActionValueKind`、`enforcesHexLower32Nonce`、`servicesShapeIsStrictPerSchema`、`aliasAndPartialAreIndependentDiagnostics`）。
- 构建/lint 为本次复跑，不依赖修复报告日志；构建只写入 ignored 的 build 输出，未改动受评审源文件。
- Hypium host：未在本次复审重跑 `hvigorw test`（已知 Linux Previewer 挂起）；核对 `t06-fix-hvigor-test-compile.log`：`UnitTestArkTS` 6.340 s 完成，随后 `> hvigor Linux`，超时 124。结论保持 **COMPILED_ONLY / BLOCKED**，不写成 PASS。
- 设备侧：沿用上轮与修复报告的 `onDeviceTest` 阻塞证据（`ErrorCode: 00507013`，无 hdc target）；保持 **BLOCKED**。

### 2.2 定向探针（只读，加载被测 `.ets` 模块）

```text
ACK unknown root field           -> ACK_PROTOCOL_VIOLATION
ACK unknown deviceState field    -> ACK_PROTOCOL_VIOLATION
ACK unknown gatewayState field   -> ACK_PROTOCOL_VIOLATION
nonzero ACK + both shapes        -> ACK_PROTOCOL_VIOLATION
nonzero ACK + unknown field      -> ACK_PROTOCOL_VIOLATION
nonzero ACK + wrong type         -> ACK_PROTOCOL_VIOLATION
nonzero ACK + valid state        -> OK, ackAccepted=false, shouldApplyState=false
nonzero ACK + missing online     -> PROTOCOL_MISSING_FIELD（R2-01）
ACK missing message              -> PROTOCOL_MISSING_FIELD（R2-01）
ACK malformed JSON               -> PROTOCOL_INVALID_JSON（R2-01）
ACK duplicate key                -> PROTOCOL_DUPLICATE_KEY（R2-01）
ACK bad server_time              -> PROTOCOL_INVALID_TIMESTAMP（R2-01）
gateway ACK                      -> ackAccepted=true, reportedState=undefined, shouldApplyState=false
SET_MODE TURBO vs COOL           -> MISMATCH
SET_MODE TURBO vs TURBO          -> MATCH (+ NON_STANDARD_AC_MODE deviation)
SET_MODE missing mode            -> UNVERIFIED
Base64Url.decode('')             -> SECRET_ENCODING_INVALID
serializer 12-hex nonce          -> PROTOCOL_INVALID_IDENTIFIER
SERVICES fractional brightness   -> ACCEPTED 42.5（R2-02）
SERVICES 8193-char inventory     -> PROTOCOL_BODY_TOO_LARGE（JsonParser 字符串上限 8192，实际覆盖 schema maxLength）
```

### 2.3 过程/仓库检查

- `git rev-parse HEAD` = `4d97e41…`；`git rev-parse HEAD^` = `5eb4d67…`；`git status --short` clean。
- 24 文件全部在声明范围内；无范围外产品代码、无 `input/**` 修改、无重复实现（`class CloudCommandSerializer`/`StateReportMapper`/`interface HmacSignerPort` 各只有一处定义）。
- 未发现秘密、证书、Token、真实凭据；未发现乐观成功路径。
- codelinter 与 host 测试为同 revision 复跑；构建产物未入库。

---

## 3. R-01..R-13 关闭状态

> 状态定义：**Closed** = 原 finding 的缺陷在代码/测试中不再可复现；**Partially** = 核心缺陷已修复但报告声称的某一方面仍不成立；**Not closed** = 原缺陷仍可复现。

| ID | 上轮严重度 | 状态 | 代码/测试证据 |
|---|---|---|---|
| **R-01** | Medium | **Closed** | `ControlAckMapper.rejectUnknownFields` 已统一调用 `ProtocolErrors.ackProtocolViolation`（`ControlAckMapper.ets:457-463`）；根对象（`:83`）、deviceState（`:216`）、gatewayState（`:321`）三处一致。`ProtocolAck.test.mjs:245-266` 覆盖根/device/gateway 三种未知字段；探针确认均返回 `ACK_PROTOCOL_VIOLATION`。根对象缺 required 字段的错误码另见 R2-01（不改变 R-01 的“未知字段”关闭结论）。 |
| **R-02** | Medium | **Closed** | `shouldApplyState = ackAccepted && deviceState !== undefined && !(idempotentReplay && expected.alreadyApplied)`（`ControlAckMapper.ets:172-174`），与 DES-A §5.1.4 的 `reportedState !== undefined` 定义一致；`deviceState` 即设备侧 `reported_state`。gateway ACK 测试 `:188-205` 断言 `reportedState=undefined`、`shouldApplyState=false`；device golden/replay `:77-104` 保持 true/false 正确。`ControlOutcome.create` 新增 `shouldApplyState ⇒ reportedState` 不变式（`ControlModels.ets:140-143`）。 |
| **R-03** | Medium | **Closed** | `compareAction` 的 SET_MODE 分支不再要求 `modeStandard`，改为按请求原始字符串比较（`ControlAckMapper.ets:385-394`）：缺失 → `UNVERIFIED`；存在且不同 → `MISMATCH`；相同 → `MATCH`。`ProtocolAck.test.mjs:315-357` 覆盖 TURBO≠COOL、TURBO=TURBO、缺失三种情况；仍记录 `NON_STANDARD_AC_MODE` 诊断偏差。 |
| **R-04** | Low | **Partially closed（核心已关闭；Low 残余 R2-01）** | 非零 `result_code` 且存在 `reported_state` 时调用 `validateReportedState`（`ControlAckMapper.ets:121-134, 178-198`）：双形态/未知字段/类型错误均抛 `ACK_PROTOCOL_VIOLATION`；合法负例返回 `ackAccepted=false`、`reportedState=undefined`、`shouldApplyState=false`。`ProtocolAck.test.mjs:268-313` 覆盖四种情况。**残余**：`reported_state` 缺少 required 字段（如 `deviceId`/`online`/`updatedAt`）时，`JsonNode.require` 抛 `PROTOCOL_MISSING_FIELD`，并非修复报告所称的一律 `ACK_PROTOCOL_VIOLATION`；见 R2-01。 |
| **R-05** | Low | **Closed** | `Base64Url.decode('')` 现在抛 `SECRET_ENCODING_INVALID`（`Base64Url.ets:36-40`）；`encode(empty)` 仍返回 `''`，`isValid('')=false`。`Foundation.test.mjs:162-179` 更新并断言。 |
| **R-06** | Low | **Closed** | `ErrorCatalog.i18nKeyOf` 将 `INVITE_VERSION_UNSUPPORTED` 加入 `errors.app.invite_invalid` 分支（`AppError.ets:94-97`），与 DES-A §3.2.3 一致；`Foundation.test.mjs:43-68` 断言该码及 `INVITE_AEAD_FAILED`。 |
| **R-07** | Low | **Closed** | `ControlRequestSerializer.validateValue` 按 `DeviceConstants.actionToValueKind(action)` 强制类型（`ControlRequestSerializer.ets:105-148`）：NONE 带值、BOOLEAN/NUMBER/STRING/COLOR 类型不匹配均 `PROTOCOL_INVALID_TYPE`。`DeviceConstants.actionToValueKind` 将 `OPEN/CLOSE/ON/OFF/BOARD_LED_*` 修正为 BOOLEAN（`DeviceConstants.ets:107-112`），与 DES-A §14.2.3 “boolean 或省略”一致。`ProtocolControl.test.mjs:141-158` 覆盖六种不匹配及 `'制冷'` 仍可编码；7 值 SET_MODE 词表明确由 C-11/C-16 强制，未在序列化器越权。 |
| **R-08** | Low | **Closed** | 控制/云出站 nonce 均改为 `HEX_LOWER_32`（`ControlRequestSerializer.ets:91-93`、`CloudCommandSerializer.ets:95-98`）；`ProtocolControl.test.mjs:160-168`、`ProtocolCloud.test.mjs:149-158` 覆盖 12-hex/大写/含 `-` 负例。**V-01 兼容性说明成立**：公开夹具 4 条 nonce 确为 12-hex（`9f2a7c001122` 等），与 §3.3/§18.5 的 32 位小写 hex 生成契约冲突；`C03_ControlRequestSerializer_allPublicVectorsMatchSchemaOrder` 仅替换 nonce 做字段顺序/结构断言，`controlCanonical(vector.request)` 仍逐字验证原始夹具 canonical，`HostProtocol.test.mjs:47-67` 仍逐字复算 HMAC/expectedSign；`fixtureNoncesAreOutsideOutboundContract` 明确记录序列化器拒绝夹具 nonce。T-07 必须以 32-hex 生成 nonce，不得把夹具 nonce 当生成器证据；T-19 若要求“公开向量可直接序列化”，需上游澄清/更新夹具。 |
| **R-09** | Low | **Closed（原 finding）** | SERVICES 形态新增：顶层仅允许 `services`（`StateReportMapper.ets:103`）、service 仅允许 `service_id/properties/event_time`（`:112`）、7 个 required 固定属性（`:337-342`）、全量属性 allowlist（`:343-348`）、6 个 Online 必须 boolean、`Gateway_RSSI` 必须 -127..0 整数（`:349-358`）。`ProtocolCloud.test.mjs:243-278` 覆盖缺 required、未知属性、顶层未知字段、布尔/整数类型负例；SHADOW/DEVICES 的 partial 容忍在 `:266-278` 显式保留。**残余**：`Light_01_Brightness` 的 schema `integer` 未强制（小数被接受），见 R2-02。 |
| **R-10** | Low | **Closed** | 别名回退不再置 `isPartial`；新增独立诊断位 `DiscoverySnapshot.aliasUsed`（`DiscoveryModels.ets:41,55,67`），`DiscoverMapper` 按设备偏差区间收集别名使用（`:99-132, 329-331, 476-483`），catch 路径也覆盖（`:112-116`）。`ProtocolDiscover.test.mjs:102-144` 覆盖 alias-only（`isPartial=false, aliasUsed=true`）、alias+skip、仅 alias 的跳过设备、clean 三种组合；Hypium `DiscoverMapper.test.ets` 同步。`isPartial` 仍只表示“设备被跳过/字段缺失”，未被混淆。 |
| **R-11** | Low | **Closed** | 未知 `deviceType` 的 `ProtocolDeviation.detail` 改为稳定原因码 `unrecognized_type`（`DiscoverMapper.ets:184-187`），不再放入原始值/设备名；`ProtocolDiscover.test.mjs:156-185` 断言 `detail='unrecognized_type'` 且不含 `'weird'`。 |
| **R-12** | Low | **Closed** | `entry/src/test/README.md:46` 更新为当前 revision **88/88 PASS**（`evidence/t06-fix-host-node-tests.tap`）；`:56` 明确 T-05 历史基线 15/15 不代表当前 revision；`:97` 同步。 |
| **R-13** | Low | **Closed（记录例外）** | `Ports.ets` 暂留 `common/types/`，云命令/状态映射暂留 `service/protocol/`；修复报告 §3.1 明确“签名不变、无第二套实现、T-07→`contracts/**`、T-14→`service/cloud/**`”迁移计划。代码检查：`class CloudCommandSerializer`、`class StateReportMapper`、`interface HmacSignerPort` 各只有一处定义；无重复实现。CQG-T06 必须把该目录例外写入接受记录。 |

**计数：Closed 12 / Partially 1（R-04，Low 残余 R2-01）/ Not closed 0。**

> 说明：R-04 的“核心”是“非零 ACK 中存在的 `reported_state` 仍执行严格 schema 校验”；该行为已由代码与测试证实。将其标为 Partially 是因为修复报告“失败抛 `ACK_PROTOCOL_VIOLATION`”的措辞对“缺少 required 字段”不成立；该残余为 Low、fail-closed，转入 R2-01，不构成本轮阻塞。

---

## 4. 新发现问题（R2-xx）

### R2-01（Low，非阻塞）：ACK 严格 schema 的部分失败模式仍抛 `PROTOCOL_*`，而非 `ACK_PROTOCOL_VIOLATION`

- **位置**：`ControlAckMapper.ets:88-99`（root required 字段）、`:222-229`（deviceState required 字段）、`:327-334`（gatewayState required 字段）；`JsonNode.require`（`JsonNode.ets:84-92`）；`JsonParser`/`DateTimeUtil` 的 JSON/时间错误。
- **事实（定向探针）**：
  - `reported_state` 缺 `online`（非零 ACK）→ `PROTOCOL_MISSING_FIELD`，不是 `ACK_PROTOCOL_VIOLATION`；
  - ACK 缺 `message`/`server_time`/`seq` → `PROTOCOL_MISSING_FIELD`；
  - ACK JSON 语法错误 → `PROTOCOL_INVALID_JSON`；重复键 → `PROTOCOL_DUPLICATE_KEY`；`server_time` 格式错误 → `PROTOCOL_INVALID_TIMESTAMP`。
- **契约对照**：DES-A §18.7 第 6 步“ACK 严格 JSON/schema”失败、§14.4“ACK schema/`reported_state` 结构非法”均指向 `ACK_PROTOCOL_VIOLATION`；但 DES-A §6.2 的 C-03 表又列出 `PROTOCOL_MISSING_FIELD`/`PROTOCOL_INVALID_TIMESTAMP`，两处文本存在张力。当前实现选择了 §6.2 的通用 `PROTOCOL_*`，而修复报告 R-04 声称“失败抛 `ACK_PROTOCOL_VIOLATION`”。
- **影响**：仅影响畸形 ACK 的错误分类/i18n/诊断（`PROTOCOL` vs `GATEWAY`），所有路径仍 fail-closed，不产生成功、不应用状态；不影响正常 ACK 或安全边界。
- **建议**：由 C-17/C-05 在调用边界把 ACK schema/JSON/时间失败统一映射为 `ACK_PROTOCOL_VIOLATION`，或在 `ControlAckMapper` 内包装；补 `deviceState`/`gatewayState` 缺 required、ACK 缺 root required、malformed JSON 负例。若上游确认 §6.2 的 `PROTOCOL_*` 优先，则应在 §6.1.4/§18.7 记录该例外并撤销 R-04 的“一律”措辞。
- **是否阻塞**：否（Low；fail-closed；CQG 可记录为例外）。

### R2-02（Low，非阻塞）：SERVICES 严格解析未强制 `Light_01_Brightness` 的 `integer`，测试名“strictPerSchema”略有过度声称

- **位置**：`StateReportMapper.ets:286-288`（`bag.number('Light_01_Brightness', 0, 100)`）；`PropertyBag.number`（`:506-519`）只校验范围，不校验整数。
- **事实（定向探针）**：`{Light_01_Brightness: 42.5}` 在完整 required 属性下被接受，生成 `brightness=42.5`；`state-report.schema.json` 对 `Light_01_Brightness` 声明 `"type": "integer"`。
- **影响**：云状态快照可出现小数亮度；T-06 不据此做完成判定，T-14/PB-02 才消费，故当前不产生成功误判，但会偏离 schema 并可能影响后续比较/展示。
- **建议**：在 `validateServiceProperties` 或 `PropertyBag` 增加整数校验；或由 T-14 的严格适配器接管并在 T-06 报告/测试中明确“SERVICES 的 `Light_01_Brightness` 整数约束由 T-14 补强”。其余 SERVICES schema 约束（required/allowlist/布尔/RSSI/`DeviceInventoryJson` 8192 上限）已由校验或 `JsonParser` 的 8192 字符串上限实际覆盖。
- **是否阻塞**：否（Low；T-14 领域；无成功/安全影响）。

### 非阻塞观察（不作为独立 finding）

1. **`ControlOutcome.create` 新增不变式缺少直接负例**：`C02_ControlOutcome_refusesOptimisticSuccess`（`DomainModels.test.mjs:209-244`）未构造 `ackAccepted=true + gatewayBoardState!=undefined + shouldApplyState=true + reportedState=undefined` 的组合来命中 `ControlModels.ets:140-143`；该分支目前只靠代码审查确认。建议补一条 host 断言。
2. **ACK `mode` 上界与 schema 不一致**：`ControlAckMapper.ets:268` 使用 `MAX_MODE_LENGTH_INBOUND=32`，而 `local-control-ack.schema.json` 的 `deviceState.mode` 为 `maxLength:15`。这是修复前已有行为，非本轮引入；因 SET_MODE 出站 mode≤15，不会把超长 mode 误判为 MATCH，但会接受 schema 之外的 16..32 字符 mode。
3. **非零 ACK 的合法 `reported_state` 仅在内部校验、不暴露**：符合修复报告 FIX-RISK-06 的记录；若 C-17 需要诊断字段，应走 Change Impact，不要在错误路径恢复“应用”语义。
4. **`aliasUsed` 是新增、add-only 诊断位**：C-10/T-19 只能用于诊断/迁移提示，不得单独改变“网关已移除”或 partial 合并语义；`isPartial` 定义未变。
5. **严格 SERVICES 可能拒绝真实 partial 云报文**：若固件只上报变更属性，会得到 `CLOUD_SHADOW_INVALID`；这是 schema 驱动的选择，T-14 若确认固件 partial，应增加显式 partial adapter，不得静默放宽 T-06。

---

## 5. CQG-T06 检查项对照

| 检查项 | 结果 | 证据/说明 |
|---|---|---|
| 构建 | **PASS** | 本次复跑 `hvigorw clean assembleHap --no-daemon` → `BUILD SUCCESSFUL in 7 s 276 ms`，35 tasks（34 executed, 1 up-to-date），exit 0；unsigned HAP warning 为已知构建配置。 |
| lint | **PASS** | 本次复跑 `codelinter -c code-linter.json5 -p default .` → `No defects found in your code.`，exit 0。 |
| Node host 测试 | **PASS 88/88** | 本次复跑 `entry/src/test/run-host-tests.sh` → `1..88`、`# pass 88`、`# fail 0`、exit 0、约 612.3 ms；与 `t06-fix-host-node-tests.tap` 一致。 |
| 契约：discover golden/别名/负例 | **PASS** | V-04 4 设备 golden、别名回退/冲突、未知 type/stateSource/mode、超长入站 ID、device skip、顶层 fail-closed 均通过；R-10 `aliasUsed` 与 `isPartial` 独立有正/负例；R-11 detail 已改为原因码。 |
| 契约：ACK golden/replay/判定链 | **PASS（带 R2-01 Low 例外）** | R-01/R-02/R-03 关闭；R-04 核心关闭；golden/replay/correlation/非零码/缺 `reported_state`/目标不一致/动作字段 MATCH/MISMATCH/UNVERIFIED 均有测试。R2-01 的错误码分类为 Low、fail-closed，建议 CQG 记录或由 C-17 修复。 |
| 契约：control 向量/序列化 | **PASS** | V-01 4 条向量字段顺序、canonical oracle、HMAC oracle 均通过；R-07 value kind、R-08 HEX_LOWER_32 严格门有正/负例；夹具 12-hex nonce 的差异在测试与修复报告中明确记录。 |
| 契约：identity fail-closed | **PASS** | v2.0 严格 4 字段、多余字段/常量/ID 边界；v2.1 `security.lan` tls/port/pins/pinAlg 正负例；统一 `PROVISIONING_IDENTITY_INVALID`（未受本轮修改影响，88/88 包含）。 |
| 契约：cloud envelope/state report | **PASS（带 R2-02 Low 例外）** | `paras` 10 字段、无 `object_device_id`、`Value` canonical、三种 shape、固定路径、未来时间 fail-closed；R-09 的 required/allowlist/布尔/RSSI 严格性有测试；`Light_01_Brightness` 整数约束残余见 R2-02。`DeviceInventoryJson` 内部结构仍由 T-14/PB-02 接管。 |
| Hypium host | **COMPILED_ONLY / BLOCKED** | `t06-fix-hvigor-test-compile.log`：`UnitTestArkTS` 6.340 s 完成，随后 `> hvigor Linux` 挂起，超时 124；本次未重跑，不写成 PASS。 |
| 设备侧 | **BLOCKED** | 沿用上轮/修复报告：`onDeviceTest` exit 255、`ErrorCode: 00507013`，无 hdc target；无设备运行时证据。 |
| i18n 适用项 | **NOT_APPLICABLE（本任务）/ PASS（错误键映射）** | 无 UI/locale 资源变更，无用户可见硬编码文案，无重复 codebase；`ErrorCatalog` 的 `INVITE_VERSION_UNSUPPORTED → errors.app.invite_invalid` 已验证（R-06）；CHK-01..09 留给 C-14/T-10。 |
| 分层/依赖方向 | **PASS** | `common/model/service/protocol` 未出现 `@ohos.*`/ArkUI/`struct` import；无 `any`；`common → model → service/protocol` 方向正确。R-13 是目录落点例外，不是依赖错误。 |
| 安全纪律 | **PASS（带 R2-01 Low 残余）** | 未发现伪造 HMAC/签名、真实 secret/证书/Token、秘密日志；identity/ACK/未知结果码 fail-closed；无乐观成功路径；R2-01 仍 fail-closed，只影响错误分类。 |
| 独立评审 | **PASS（本报告）** | `Producer: agent:quality-reviewer`；作者之外的独立复审；只读被测文件；作者不能批准本报告。 |
| 追溯 | **PASS** | 修复报告 §1 的 R-01..R-13 处置表可逐条核对；新增/替换 8 个测试均有 Contract/component 命名；88 个 Node 用例可复现；V-01 夹具差异有明确记录。 |
| **CQG-T06 总体** | **PASS（带已记录例外/残余）** | 三个 Medium 全部关闭；构建/lint/host 通过；无新的阻塞性缺陷；R-13 目录例外、R2-01/R2-02 Low 残余、Hypium/设备 BLOCKED 必须在 CQG 记录。组件在 CQG 通过前保持 `UNVERIFIED`；本报告不授予 `STABLE`。 |

---

## 6. Verdict

**PASS**

理由：

1. **三个 Medium 全部关闭**：R-01（ACK 未知字段错误码三处一致）、R-02（`shouldApplyState` 定义与 gateway ACK）、R-03（SET_MODE 原始值比较）均有代码事实与有效测试，且探针独立复核。
2. **R-04 核心缺陷关闭**：非零 ACK 中存在 `reported_state` 时已执行 oneOf/字段/未知字段校验；合法负例不暴露状态、不应用状态。剩余“缺 required 字段的错误码”为 Low、fail-closed，归入 R2-01，不改变“先严格校验、后分类”的顺序。
3. **其余 Low 全部有落实**：R-05/R-06/R-07/R-08/R-09/R-10/R-11/R-12 均有代码/测试证据；R-13 以“签名不变、无重复实现、T-07/T-14 迁移”的例外记录，CQG 需正式接受。
4. **工程质量**：本次复跑构建成功、lint 零缺陷、host 88/88；无范围外修改、无秘密/凭据、无重复实现、无 High/Critical 新缺陷。
5. **残余不阻塞**：R2-01/R2-02 均为 Low，分别属于错误分类与 T-14 云严格性领域；Hypium/设备侧阻塞与上轮一致，已诚实标注 `COMPILED_ONLY`/`BLOCKED`，不得写成 PASS。

> 本复审不授予 `STABLE`、Stage Gate 或用户验收。建议 Orchestrator 在 CQG-T06 记录：R-13 目录例外、R2-01/R2-02 Low 残余、Hypium/设备侧 BLOCKED、V-01 夹具 nonce 差异；随后按 Git 策略合并，并保留 T-07/T-14/T-19 的后续验证。

---

## 7. 残余风险与后续跟踪

| ID | 风险 | 影响 | 处置 |
|---|---|---|---|
| REV2-RISK-01 | R2-01：ACK 部分 schema 失败仍抛 `PROTOCOL_*` | C-17 错误分类/i18n/诊断可能与 §18.7/§14.4 不一致；fail-closed | C-17 统一映射或上游澄清 §6.2 vs §18.7；补缺 required/malformed 负例 |
| REV2-RISK-02 | R2-02：SERVICES `Light_01_Brightness` 未强制 integer | 云快照可能含小数亮度；T-14 消费时偏离 schema | T-14 strict adapter 或 T-06 补整数校验 |
| REV2-RISK-03 | R-13 目录例外未迁移 | 后续任务可能 import 错位置或复制实现 | T-07→`contracts/**`、T-14→`service/cloud/**`；CQG 记录例外；禁止双实现 |
| REV2-RISK-04 | V-01 夹具 12-hex nonce 与 §3.3 生成契约冲突 | T-07 可能误把夹具 nonce 当生成器合规证据 | T-07 必须生成 32-hex；T-19 澄清是否更新公开夹具 |
| REV2-RISK-05 | Hypium/设备运行时 BLOCKED | 无设备侧运行时 PASS | T-19 在设备/CI 复跑；保持 `COMPILED_ONLY`/`BLOCKED` |
| REV2-RISK-06 | `aliasUsed` 被误用为 partial/移除判定 | C-10 合并语义可能偏离 | C-10/T-19 只作诊断；`isPartial` 定义不变 |
| REV2-RISK-07 | 严格 SERVICES 可能拒绝真实 partial 云报文 | T-14 得到 `CLOUD_SHADOW_INVALID` | 以 schema 为准联调；若固件 partial，T-14 增加显式 adapter |
| REV2-RISK-08 | `ControlOutcome.create` 新不变式缺直接负例 | 后续调用方可能构造非法对象 | 补 host 断言；C-17/C-10 使用工厂 |
| REV2-RISK-09 | `SET_MODE` 非标准值现为 MISMATCH | VM 可能 REVERT/提示 | 按 DES-A §5.1.4 处理；云路径按 DES-B §8.1.6 由 T-14 实现 |
| REV2-RISK-10 | 无真实 BLE/TLS/云/性能证据 | 不能声明端到端可用 | T-11/T-12/T-19；保持 `UNAVAILABLE`/`BLOCKED` |

---

## 8. 独立性与结论边界

- **独立性声明**：本报告由 `agent:quality-reviewer` 独立编写；评审者不是 T-06 实现者，也不是本轮修复作者，未参与被测代码/测试的编写；只读审查并在本报告上写入结论。T-06 作者为 `agent:implementation-engineer`。
- 本复审仅覆盖 `4d97e41` 的 diff 与 §1 范围；不覆盖 T-07 的 HMAC/签名/nonce 生成、T-14 的云完成判定/`DeviceInventoryJson` 解析、T-08/T-09 的存储/端口迁移、真实 BLE/TLS/云/性能。
- 构建/lint/host 为本次复跑；Hypium/设备结论基于同 revision 的证据日志，未重跑（已知 Linux Previewer/设备限制），未写成 PASS。
- 本报告不构成 Stage Gate、用户验收或 `STABLE` 声明；CQG-T06 的最终判定与合并决策由 Orchestrator 依据本报告及上游证据作出。
