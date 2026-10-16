# ADR-001 — 线格式权威、错误语义与标识形态裁定

- **Artifact ID**: ADR-001
- **Producer**: agent:solution-architect
- **Type**: Architecture Decision Record
- **Status**: Proposed（待 G-004 门禁批准）
- **Date**: 2026-10-17
- **Task**: `wp-004-contracts`（task 分支 `task/wp-004-contracts`，父分支 `feat/yaocore-app`，base commit `54c1d786`）
- **Workflow**: STANDARD / GATED_AUTO（`config/project.md` L17-19）
- **Upstream 证据**: wp-002 报告（`artifacts/10-verification/wp-002-protocol-fixture-validation.md`，下文 `WP2`）、wp-003 报告（`artifacts/10-verification/wp-003-cross-artifact-consistency.md`，下文 `WP3`）
- **Downstream 消费者**: `contract-baseline.md`（规范性表格与映射）、wp-005 交付规划、wp-006 DES-001 详细设计、实现/测试/评审任务、`Gateway_API_Specification.md` 勘误（补丁提案）
- **Traceability**: C-001 / WP2-F01 / WP2-F02 / WP2-F03 / WP2-F06 / C-010（`WP3` §2.1/§2.2）；FR-DEV-001/004/005、FR-GW-002/003、FR-HOME-003、NFR-4.1；`INV` §6

> 本 ADR 的裁定对象是**线格式（wire format）**与**错误语义**。产品行为、界面文案、内部数据结构不在本 ADR 范围（分别由契约基线、UIUX、wp-006 详细设计承接）。所有裁定均标注一手证据（文件+行）；与冻结输入冲突之处以证据 + 用户决策（D-007/D-008）为准，并在 §6 记录被取代/被澄清的条款。

---

## 1. Decision 1：线格式权威 = schema 家族 + protocol README + 测试向量（C-001 / WP2-F01）

### 1.1 Context

同一字段族存在两套命名：

| 证据来源 | 设备状态字段 | 顶层/回执字段 | 性质 |
|---|---|---|---|
| `input/api/protocol/discover-response.schema.json` L74-81、L103-138 | `online` / `power` / `open` / `targetTemp` | required 含 `generatedAt` / `security` / `devices` | **机器契约（schema）** |
| `input/api/protocol/local-control-ack.schema.json` L77-89、L151-169 | `online` / `power` / `open` / `targetTemp` | `idempotent_replay` 布尔；**无 `success`**；`additionalProperties:false`（L171） | **机器契约（schema）** |
| `input/api/protocol/README.md` L57-107、L183-206 | canonical 与 ACK 规则使用线格式字段名 | `result_code`、`idempotent_replay` | **机器契约（散文规则）** |
| `artifacts/10-verification/fixtures/tools/gateway_contract_server.py`（字节级与 pin 一致的仿真器）+ 实跑证据 `fixtures/evidence/discover-response.json`、`control-ack.json` | 输出 `online/power/open/targetTemp` | ACK 无 `success` | **可执行实现** |
| 15 项可运行契约测试（`WP2` §3.2） | 断言线格式字段 | — | **测试锚定** |
| 归档原 App `input/existing/original_app/service/LocalGatewayService.ets` L429-441、L483-498 | 解析**优先**线格式，`isOnline/powerStatus` 仅作回退 | 读取 `reported_state` | **可执行互操作证据** |
| `input/api/Gateway_API_Specification.md` L88-121（discover 示例）、L187-204（ACK 示例） | `isOnline`（L102/L114）、`powerStatus`（L103/L198） | 多 `keyId`（L95）、多 `success`（L193）、缺 required `server_time` 与 `online` | **散文示例（自违反 schema）** |
| 归档原 App **内部模型**：`NetworkService.ets` L539-546、`DeviceRepository.ets` L602-603 | `isOnline/powerStatus/openStatus/targetTemperature` 为 App 内部字段 | — | 说明驼峰词的归属 |

结论性事实（`WP2` §4.1/§4.2，`WP3` §2.1-C001）：**四方可运行证据（schema ↔ 仿真器实跑 ↔ 可运行契约测试 ↔ 归档 App 线格式解析器）一致指向 schema 命名**；散文规范示例是唯一反例，且其驼峰词与归档 App 的**内部模型**词汇完全一致（推断为"内部模型词汇写入了线格式示例"的文档缺陷），示例本身附加/遗漏字段、违反其对应 schema（`additionalProperties:false`）。

### 1.2 Decision

1. **线格式权威顺序（协议数据面）**：
   1. `input/api/protocol/` 下 12 个 schema（机器契约，`$schema draft/2020-12`）；
   2. `input/api/protocol/README.md`（canonical 串、时间窗、nonce/重放、响应验签、ACK 规则等不可被 schema 表达的语义规则）；
   3. `input/api/protocol/*-test-vectors*.json` 4 份测试向量（跨语言互操作夹具）；
   4. `input/api/Gateway_API_Specification.md`（散文规范，**examples 部分为本 ADR 认定的缺陷来源**，按 §6 勘误；其余文字描述在无冲突时有效）。
   产品行为/界面/数据以 PRD、架构、数据模型、UIUX 为准（`config/project.md` L66；`WP3` §0.3）。
2. **App 内部模型命名可保留**：`isOnline/powerStatus/openStatus/targetTemperature` 等内部命名**仅属 App 实现细节**，不构成线格式；两者之间必须有单一映射层（映射表见 `contract-baseline.md` §2），DTO 边界是唯一允许出现字段名转换的位置。
3. **出站一律 schema 命名**；入站按 schema 严格校验**信封与安全字段**，对**附加状态别名**（`isOnline`→`online` 等已知旧别名）允许读取回退，并计入 `protocolDeviation` 计数（理由：归档 App 的回归行为已证明该回退在现网兼容上有效，见 `LocalGatewayService.ets` L429-441；回退仅限读取，永不写出）。
4. **`success` 字段永不参与判定**：出现即忽略并记为 deviation；执行确认仍以 `result_code === 0` + 响应 HMAC + correlation 为准（README L183-189）。
5. **`Gateway_API_Specification.md` 不改原文**：以勘误清单（`contract-baseline.md` §5）逐条记录被取代的示例与理由；补丁提案（§7）供文档维护修订。

### 1.3 Consequences

**正**：与现网可运行行为一致（零迁移风险）；契约测试与仿真器可继续作为 App 单测的期望清单；内部模型命名保留，重构成本低；勘误以文档方式解决权威冲突（C-008 的权威顺序也随之收敛）。
**负**：同一概念存在两套词汇（线格式/内部模型），依赖映射表纪律；散文规范与机器契约不一致状态需在文档修订前持续标注；容忍读取别名引入少量分支（以 deviation 计数约束）。

### 1.4 Alternatives

- **A1 以散文规范（camelCase + `success`）为权威**：否决——与 schema、可运行实现、契约测试、归档 App 解释器全部冲突（`WP2` §4.1），且示例自身违反 schema；采用即要求改写网关固件与全部向量。
- **A2 双格式双向兼容（同时接受/输出两套命名）**：否决——同一报文两义增加解析歧义与安全面，且无任何一方证据表明网关输出驼峰；仅保留 A3 的读取回退。
- **A3 严格拒绝任何非 schema 字段**：部分否决——对信封/身份字段严格（保留 fail-closed），对状态别名保留读取回退（兼容存量行为，见 §1.2-3）。
- **A4 全面改写 schema 为驼峰**：否决——schema 为最可靠机器契约且与 IoTDA/模块协议/state-report 属性命名族一致（`state-report.schema.json` L37-45 等），改写将级联破坏云与模块契约。

### 1.5 References

`discover-response.schema.json` L74-81/L96-98/L103-138/L168；`local-control-ack.schema.json` L77-89/L151-169/L171；`README.md` L57-107/L183-189；`gateway_contract_server.py`（fixtures 副本）L417-461/L580-592/L626-633；`Gateway_API_Specification.md` L88-121/L187-204；`LocalGatewayService.ets` L429-441/L483-498；`NetworkService.ets` L539-546；`DeviceRepository.ets` L602-603；`WP2` §4；`WP3` §2.1-C001/§2.2-F01。

---

## 2. Decision 2：`result_code` 统一语义 + `error_code` 稳定字符串双轨（WP2-F02）

### 2.1 Context

`local-control-ack.schema.json` L16-20 仅把 `result_code` 约束为 `0..9999` 整数（无枚举），L26-30 另有一个可选的 `error_code` 稳定字符串（1..47 字符，无词表）。两套冻结文档给出不兼容的数值语义（`WP2` §6-F02；`WP3` §2.2-F02）：

| code | `Gateway_API_Specification.md` L217-227 | `gateway_contract_server.py` L50-56 + 实跑证据 |
|---|---|---|
| 0 | SUCCESS | 成功（`control-ack.json`） |
| 1001 | `INVALID_SIGNATURE` | `RESULT_INVALID_REQUEST`（结构/字段非法） |
| 1002 | `EXPIRED_TIMESTAMP` | `RESULT_UNSUPPORTED_SECURITY`（未知 key_id/alg） |
| 1003 | `MISSING_FIELD` | `RESULT_TIMESTAMP_REJECTED`（±120s 外） |
| 1004 | `UNKNOWN_DEVICE` | `RESULT_BAD_SIGNATURE`（HMAC 不匹配，HTTP 401，实跑 `control-ack-bad-sign-401.json`） |
| 1005 | `REPLAY` | `RESULT_REPLAY`（HTTP 409，实跑 `control-ack-bad-sign.json`） |
| 1006 | `UNSUPPORTED_ACTION` | `RESULT_UNSUPPORTED_COMMAND`（未知 target/不支持动作，HTTP 422） |
| 1007 | `DEVICE_OFFLINE` | `RESULT_DEVICE_OFFLINE`（HTTP 503） |
| 1008 | `HARDWARE_TIMEOUT` | **不存在** |

双方在 `0 / 1005 / 1007` 上一致，说明同源；分歧集中在 1001/1002/1003/1004/1006 与 1008。可执行证据（仿真器 + 15 项契约测试 + `WP2` 复算 66/66）优于散文表格；且散文表格所在文档已因示例缺陷（F-01）与身份示例冲突（F-03）被认定为最弱一环。

### 2.2 Decision

1. **主判字段 = `result_code`，以冒号左侧为 v1 统一数值语义**（出自可运行实现与 schema 家族对齐的编码）：

| `result_code` | 稳定名称（`error_code`） | 触发条件 | 对应 HTTP（仿真器实测） | 语义边界 |
|---|---|---|---|---|
| `0` | （必须缺省） | 已获硬件/下位机真实执行确认且 `reported_state` 完整 | 200 | 唯一成功值 |
| `1001` | `invalid_request` | 结构非法、缺字段、未知额外字段、值域/格式越界、`cmd_id≠2001` | 400 | 合并旧 `INVALID_SIGNATURE(1001)`/`MISSING_FIELD(1003)` 的**结构类**含义 |
| `1002` | `unsupported_security` | 未知/不支持的 `key_id` 或 `alg` | 401 | 密钥版本协商失败 |
| `1003` | `timestamp_rejected` | 时间戳超 ±120s / 格式或时区非法 | 401 | 不消耗 nonce（README L102-103） |
| `1004` | `bad_signature` | HMAC 校验不匹配、响应正文与签名不符 | 401 | 常数时间比对（README L86-87） |
| `1005` | `replay` | 同 `(key_id, nonce)` 不同签名内容（含精确重放缓存冲突） | 409 | 重放缓存**先于**新鲜度检查（README L94-103） |
| `1006` | `unsupported_command`（细分：`unknown_device` / `unsupported_action` / `unsupported_gateway_action`） | 目标不存在、动作不被设备类型支持、网关不识别 | 422 | 细分差异由 `error_code` 承载 |
| `1007` | `device_offline` | 外设/下位机离线 | 503 | — |
| `1008` | `hardware_timeout` | 网关已下发硬件指令但超时未收到物理 ACK | 504（建议） | **保留并采用**：语义真实（`网关接口协议.md` L24 门磁/下位机 ACK 要求；`LocalGatewayService.ets` L323-325 注释"门磁和空调下位机的可配置执行超时最高为 10 秒"），数值与机器表无冲突；仿真器暂不发出，属**需固件协同项**（§8） |
| `1009..9999` | 保留 | — | 4xx/5xx | 未列入表的码一律按**失败**处理（fail-closed），禁止当作成功 |

2. **双轨规则**：`result_code` 为强制主判；`error_code` 为非零结果时的**稳定机读字符串**（schema 已含该字段，L26-30），采用 `snake_case`，禁止本地化文本（人类可读文本只在 `message`/App i18n 层）。
   - App 侧判定顺序：`result_code==0` → 成功前置条件校验（schema 必含 `reported_state`，L49-63）；非零 → 优先按 `error_code` 精确映射用户提示，缺失时按 `result_code` 映射。
   - App **必须容忍 `error_code` 缺失**（v2.0 存量网关）；**建议固件**在协同修订中补齐（§8）。
   - `result_code==0` 且 `error_code` 存在视为协议违规 → 记录 deviation，按成功前置条件继续（不改变成功判定）。
3. **未知码处置**：任何未列出的 `result_code` → 判定失败、提示通用失败文案、记录 `protocolDeviation`（禁止乐观成功；`config/project.md` L50 禁止虚构成功状态）。
4. **HTTP 状态不构成执行确认**：唯一确认 = 响应验签通过 + correlation（`request_id:seq`）匹配 + `result_code==0` + `reported_state` 完整（`网关接口协议.md` L17-26；README L183-189）。
5. **用户提示映射策略**：`result_code`/`error_code` → i18n key 的映射表归 `contract-baseline.md` §4（键位规范见 `i18n-resource-design.md`），实现层不得在 UI 拼接自然语言。
6. **App 侧错误编码与网关错误码分离**：传输/验证失败（超时、HMAC 响应校验失败、连接失败等）使用 App 自有稳定编码（参考归档 `LocalGatewayService.ets` L454-479 的 `LOCAL_REQUEST_FAILED` / `HTTP_5xx` 家族做法），**不得复用**网关 `result_code` 数值空间。

### 2.3 Consequences

**正**：与唯一可运行实现一致，契约测试与仿真器可继续作为门禁；双轨使 UI 精确提示与固件前向兼容同时成立；全表（0/1001-1008）处置明确，无悬空码；1008 保留使"硬件超时"语义不下沉为通用失败。
**负**：散文规范 L217-227 需整体勘误（含 1008 建议 HTTP 映射）；若存量网关实际按旧表编码，则 1001-1004/1006 的**机器读数**语义将与旧文档相反——因此 App **不得**从旧表推断语义，必须依赖 `error_code` 或统一表；固件补齐 `error_code` 前，细分提示（`unknown_device` vs `unsupported_action`）不可用。

### 2.4 Alternatives

- **B1 采用散文表为主判**：否决——与可运行实现、契约测试、仿真器全部冲突，采用后现网行为全部被判为错误。
- **B2 保留两表并用，按 HTTP 状态区分**：否决——HTTP 状态已被明确判定为非权威（GWO L17-26），叠加映射产生二义。
- **B3 删除 `error_code`，纯数值**：否决——schema 已定义该字段（L26-30），且 UI 精确提示需要稳定字符串；数值表在固件分歧期内不可自解释。
- **B4 重编号并同时改 schema+固件**：否决——无必要的大爆炸式变更，且违反"不改动 input/ 冻结契约"的任务约束。

### 2.5 References

`local-control-ack.schema.json` L16-20/L26-30/L49-63；`Gateway_API_Specification.md` L217-227；`gateway_contract_server.py` L50-56/L199/L274/L499-513/L520-556/L583-592/L620-706；实跑证据 `fixtures/evidence/control-ack.json`、`control-ack-bad-sign.json`(409/1005)、`control-ack-bad-sign-401.json`(401/1004)；README L94-103/L183-189；`网关接口协议.md` L17-26；`LocalGatewayService.ets` L323-325/L454-479；`WP2` §6-F02；`WP3` §2.2-F02。

---

## 3. Decision 3：BLE 身份端点字段以 schema + 归档 App 可执行证据为准（WP2-F03）

### 3.1 Context

三方冲突（`WP2` §6-F03；`WP3` §2.2-F03）：

- `ble-enrollment-identity-response.schema.json` L7-25：required `protocolVersion/serviceId/gatewayId/gatewayName`，`serviceId` **const `YaoCoreGateway`**，封闭（L6）。
- 归档原 App `BleProvisioningService.ets` L655-657：`identity.serviceId !== 'YaoCoreGateway'` 即抛 `PROVISIONING_IDENTITY_INVALID`（**fail-closed**），且只读取 `gatewayId`/`gatewayName`/`protocolVersion`（L649-661）。
- `Gateway_API_Specification.md` L44-45：示例 `serviceId:"SmartHomeService"` + `displayName`；README L37-41 用文字 "display name"（未给键名）。

schema 与归档 App 的可执行行为一致；散文示例为孤例。

### 3.2 Decision

1. **身份端点（`yaocore-id`）响应字段 = schema 版本为准**：`serviceId` const `YaoCoreGateway`、`gatewayName`、`gatewayId`、`protocolVersion`；`additionalProperties:false`，App 必须 fail-closed（任何多余字段或常量不符 → `PROVISIONING_IDENTITY_INVALID`，终止配网）。
2. **两个 `serviceId` 常量的关系（设计意图显式记录）**：二者属于**不同命名空间**，同名不同义，禁止互相替代或校验：
   - `SmartHomeService` = **IoTDA 服务/命令/属性命名空间**（`discover-response.schema.json` L27-29；`cloud-command.schema.json` L13-15；`state-report.schema.json` L16-18）；
   - `YaoCoreGateway` = **BLE 配网身份命名空间**，用于证明"这是一台 YaoCore 网关的 Security1 身份端点"，不是云服务 ID。
   散文示例把两个命名空间混写，是 WP2-F03 的根因。
3. `Gateway_API_Specification.md` L44-45 计入勘误（`contract-baseline.md` §5）；README L37-41 的 "display name" 建议在文档修订中明确为 `gatewayName`（补丁提案 §7）。
4. 身份端点**不承载** PoP、HMAC 密钥、Wi-Fi 密码、云凭据（README L38-41）；证书指纹的下发方案见 ADR-002 §3（身份端点 v2.1 提案），与本节约束不冲突（指纹是公开值，但仍须遵守版本化扩展流程）。

### 3.3 Consequences

**正**：配网身份校验与 Archived 实现、schema、可运行向量一致；两常量并存歧义被显式消解，后续评审可引用本条第 2 点判定类似"同名不同义"问题。
**负**：散文规范修订前，该冲突仍有被误读的风险（已由勘误清单缓解）。

### 3.4 Alternatives

- **C1 以散文示例为准（`SmartHomeService`/`displayName`）**：否决——与 schema 和 fail-closed 可执行证据冲突；采用即要求改 schema 与归档 App 行为，且会把云命名空间混进配网身份。
- **C2 双字段兼容（同时输出 `gatewayName` 与 `displayName`）**：否决——schema 封闭，双字段即违反 `additionalProperties:false`；旧解析器也会因多余字段失败。
- **C3 统一两常量为同一值**：否决——`SmartHomeService` 被 IoTDA 产品模型与 3 份 schema 固定引用（L13-15 等），改动成本巨大且无收益。

### 3.5 References

`ble-enrollment-identity-response.schema.json` L6-26；`ble-enrollment-identity-request.schema.json` L6-15；`BleProvisioningService.ets` L640-665；`Gateway_API_Specification.md` L43-46；README L35-46；`WP2` §6-F03；`WP3` §2.2-F03。

---

## 4. Decision 4：schema 与仿真器校验边界差异的宽容策略（WP2-F06）

### 4.1 Context

同名字段在 schema 与仿真器上的边界不一致（`WP2` §5 末；`WP3` §2.2-F06）：

| 字段 | schema 上界 | 仿真器上界 | 证据 |
|---|---|---|---|
| `target`（deviceIdentifier） | 63 | 128（`IDENTIFIER_RE`） | `local-control-request.schema.json` L83；`gateway_contract_server.py` L58/L199 |
| `request_id` | 127 | 128 | 同上 |
| `payload.action` | 47 | 64（`ACTION_RE`） | schema L39；simulator L59/L274 |
| `mode` | 15（discover L139-142 / ack L120-123） | 32（且 `state-report.schema.json` L120-123 允许 32） | `WP2` §5 末 |

仿真器理论上可生成 schema 不接受的输出（边界值）；该差异不导致当前任何测试失败（`WP2` §5）。

### 4.2 Decision

1. **出站一律遵循 schema 上界**（App 是 `target/request_id/action/mode`（控制面）与接收方的发送方；网关是 discover/ACK 的发送方）：任何出站值超 schema 边界即视为 App 缺陷（单测覆盖）。
2. **入站宽容策略**：App 对入站字段按真值域校验（数值/枚举/格式），对上界差异采取"接受但不放大"：
   - `mode`：入站接受 ≤32（对齐 `state-report.schema.json` L120-123 的云属性域），内部归一化到 v1 空调词表（见 `contract-baseline.md` §6.3）；出站 `SET_MODE` 仅发送 v1 词表值（长度必然 ≤15）。
   - `deviceIdentifier/requestIdentifier`：入站接受 ≤128，仅用于展示/关联，**不得**因此放宽 App 本地主键长度假设（本地主键为复合键，见 §5）。
3. **仿真器对齐为测试侧任务**（补丁提案 §7，交由 wp-005 测试计划执行）：仿真器生成路径必须与 schema 一致；接受路径可保留宽容，但需在 fixture 注释/测试中显式声明宽容度，避免"仿真器校验通过 = schema 校验通过"的错误假设。
4. **v1 不修改 schema**（冻结输入；如需修订走 §7 提案流程）。

### 4.3 Consequences

**正**：App 与云属性域（32 字符 `mode`）兼容；边界差异不再成为实现期歧义；测试仍以 schema 为生成标准。
**负**：仿真器短期内仍是"更宽"的一方，需要测试计划显式对齐（已列为 P2-14 的落地项）。

### 4.4 Alternatives

- **D1 收紧仿真器并同步 schema**：部分采纳（仿真器生成侧对齐；schema 保持不变）。
- **D2 按仿真器边界放宽 schema**：否决——schema 是共享契约，放宽会同时影响固件与云适配方，且无需求支撑 128 长度。
- **D3 忽略差异**：否决——`WP2` 已将其列为实现期歧义源。

### 4.5 References

`local-control-request.schema.json` L37-40/L77-88；`discover-response.schema.json` L64-71/L139-142；`local-control-ack.schema.json` L120-123；`state-report.schema.json` L120-123；`gateway_contract_server.py` L58-62/L199/L274/L687-693；`WP2` §5 末；`WP3` §2.2-F06。

---

## 5. Decision 5：`gatewayId` / `deviceId` 形态与两级标识模型（C-010）

### 5.1 Context

四种形态并存（`WP3` §2.1-C010）：

| 来源 | 形态 | 证据 |
|---|---|---|
| 数据模型（App 主键示例） | `GW-9A216D:LIGHT_01`（复合） | `Data_and_State_Models.md` L109 |
| PRD 示例 | `GW-01:LIGHT-01`（复合、连字符风格） | `YaoCore_HarmonyOS_App_Requirements.md` L93 |
| API 示例 | `LIGHT_01`（裸） | `Gateway_API_Specification.md` L98 |
| 机器 schema | `^[A-Za-z0-9][A-Za-z0-9_.:-]{0,62}$`（裸 token，允许 `:`） | `discover-response.schema.json` L64-67 |
| 仿真器实测/归档常量 | `gateway_01`、`Door_01`、`Light_01`、`Sensor_01`、`AC_01`、`Presence_01` | `fixtures/evidence/discover-response.json`；`DeviceConstants.ets` L13-16/L20 |
| IoTDA 属性命名 | `Door_01_Online` 等由裸 id 派生 | `state-report.schema.json` L37-45 |
| 物理身份规则（模块协议） | `(gatewayId, deviceId)` 二元组 | `EXTERNAL_MODULE_PROTOCOL.md` L22 |

### 5.2 Decision

1. **两级标识模型**：
   - **线格式 id（`gatewayId` / `deviceId`）**：schema 约束的**裸 token**，各由网关定义并保持稳定；出现在 `/discover`、`/control.target`、ACK `deviceState.deviceId`、模块协议与 IoTDA 属性派生中。**线上一律裸 id，不发送复合串。**
   - **App 全局键（`globalDeviceId`）**：`gatewayId + ':' + deviceId` 复合串，仅用于 App 本地存储索引/路由/展示（对应 DM L109 的意图）；App 持久化时**分别存储** `gatewayId` 与 `deviceId` 两个字段，复合串为派生值，禁止反向解析。
2. **v1 字符集冻结**：`gatewayId`、`deviceId` 在 v1 采用 `[A-Za-z0-9_][A-Za-z0-9_.\-]{0,62}`（**禁止 `:`**，保留 `:` 作为复合分隔符；schema 允许但契约收窄，避免复合串二义）。既有族 `gateway_01` / `Door_01` / `Light_01` / `Sensor_01` / `AC_01` / `Presence_01` 及其模块扩展（`<Name>_01`）为 v1 规范形态，**禁止**大小写变换或短横线重写（IoTDA 属性名 `Door_01_Online` 等由裸 id 派生，改形即断云链）。
3. **`gatewayId` 绑定纪律**（安全相关）：`gatewayId` 仅从 Security1 会话内的 `yaocore-id` 与已验签的 `/discover` 获得；BLE 广播名/MAC 后缀/UDP/mDNS 只作定位（`BLE配网设计.md` L143；README L48-53）；绑定必须满足"discover `gatewayId` === Security1 读取值"（README L48-52）；纯本地比较，不做任何形态推断或模糊匹配。
4. **示例与示例性文案不具权威**：`GW-9A216D`、`GW-01:LIGHT-01`、`GW-XXXXXX` 均记为**示例**（`contract-baseline.md` §5 勘误/澄清清单）；真实字段形态以本条冻结规则 + 机器资产为准。
5. **`roomName`/`deviceName` 等显示名不参与身份**：改名不影响任何 id（FR-ROOM-002/006；DM L181-188），协议层不因此产生变更。

### 5.3 Consequences

**正**：多网关家庭中同 `deviceId` 不冲突（物理身份为二元组）；IoTDA 属性派生稳定；复合串二义被消除；绑定安全规则与 BLE 验证链条一致。
**负**：与 DM L109 的单一复合串字段写法不同（需在 DATA-001 修订提案中登记，见 `contract-baseline.md` §7.3）；禁止 `:` 收窄了 schema 的宽容度，需在入站校验中显式拒绝（记为 deviation/结构失败）。

### 5.4 Alternatives

- **E1 全线格式使用复合 id**：否决——IoTDA 属性/模块协议/仿真器/state-report 全部按裸 id 工作，且 schema 示例族为裸 id；复合化破坏云链与既有测试锚。
- **E2 App 内部沿用裸 id 作为全局键**：否决——多网关家庭必然撞键（DM L13 `gatewayIds[]` 支持多网关）。
- **E3 允许 `:` 出现在 id 内部**：否决——复合键解析二义；无证据需要该字符。
- **E4 统一大小写规范化**：否决——会破坏 IoTDA 属性名对齐（`Door_01_Online`），且无证据要求。

### 5.5 References

`discover-response.schema.json` L64-67；`local-control-ack.schema.json` L69-72；`state-report.schema.json` L37-45/L157-160；`Data_and_State_Models.md` L109/L13；`YaoCore_HarmonyOS_App_Requirements.md` L93；`Gateway_API_Specification.md` L93-98；`DeviceConstants.ets` L13-16/L20/L22；`fixtures/evidence/discover-response.json`；`EXTERNAL_MODULE_PROTOCOL.md` L22；README L48-53；`BLE配网设计.md` L143；`WP3` §2.1-C010。

---

## 6. 被取代 / 被澄清的条款（Superseded & Clarified Clauses）

| # | 条款（冻结输入） | 处置 | 依据 |
|---|---|---|---|
| 1 | `Gateway_API_Specification.md` L88-121 discover 示例（camelCase、`keyId`、缺 `generatedAt/security`） | **被取代**（勘误 E-01） | §1；`WP2` §6-F01/F.15-F.16 |
| 2 | `Gateway_API_Specification.md` L187-204 ACK 示例（`success`、缺 `server_time`、`reported_state` 缺 `online`） | **被取代**（勘误 E-02） | §1；`WP2` §6-F01/F.17-F.18b；`WP3` §2.1-C001 |
| 3 | `Gateway_API_Specification.md` L215-227 结果码表 | **被取代**（勘误 E-03；1008 语义保留并入统一表） | §2 |
| 4 | `Gateway_API_Specification.md` L44-45 身份示例（`SmartHomeService` + `displayName`） | **被取代**（勘误 E-04） | §3 |
| 5 | README L37-41 "display name" 文字 | **被澄清**：键名 = `gatewayName`（补丁 P-02） | §3 |
| 6 | `Gateway_API_Specification.md` L146-166 AES-GCM 载荷示例 | **被澄清**：记为扩展提案归档（见 ADR-002 §5） | D-007 |
| 7 | `Data_and_State_Models.md` L109 复合 deviceId 示例 | **被澄清**：两级标识模型（复合为 App 派生键） | §5；DATA-001 修订提案 |
| 8 | `YaoCore_HarmonyOS_App_Requirements.md` L93 `GW-01:LIGHT-01` | **被澄清**：示例非规范 | §5 |
| 9 | 仿真器校验边界（L58/L199/L274/L687-693） | **被澄清**：宽容策略 + 仿真器生成侧对齐任务 | §4 |

## 7. 补丁提案（Patch Proposals — 不直接修改 `input/`）

| # | 目标文件 | 位置 | 具体改动 | 建议时机 |
|---|---|---|---|---|
| P-01 | `input/api/Gateway_API_Specification.md` | §3.1 discover 示例（L88-121） | 按 `discover-response.schema.json` 重写示例：顶层补 `generatedAt`/`security`，删 `keyId`；设备项 `online/power/open/targetTemp` 命名 | 文档维护轮次（C-013 机制建立后） |
| P-02 | `input/api/protocol/README.md` | L37-41 | 将 "display name" 明确为 `gatewayName`，并注明身份 `serviceId` const `YaoCoreGateway` 与云 `SmartHomeService` 属不同命名空间 | 同上 |
| P-03 | `input/api/Gateway_API_Specification.md` | §3.2 ACK 示例（L187-204） | 删 `success`；补 `server_time`；`reported_state.online` 补齐；`powerStatus`→`power` | 同上 |
| P-04 | `input/api/Gateway_API_Specification.md` | §3.3（L215-227） | 替换为 `contract-baseline.md` §4 统一错误表 + `error_code` 字符串列 | 同上 |
| P-05 | `input/api/Gateway_API_Specification.md` | §2.2（L43-46） | 身份响应示例改为 `serviceId:"YaoCoreGateway"`、`gatewayName` | 同上 |
| P-06 | 仿真器/测试夹具（未来移植后仓库路径 `tools/simulator/`） | 生成路径 | 按 schema 边界生成（`target/request_id ≤63/127`、`action ≤47`、`mode ≤15`）；接受路径保留宽容并注释 | wp-005 测试计划 |
| P-07 | `input/api/Gateway_API_Specification.md` | §3.2 请求路径（L126） | 依 D-007 更新：v1 基线为 `http://`（HMAC profile）+ 条件性 `https://`（指纹固定 profile），描述与 ADR-002 §2-4 对齐 | 文档维护轮次 |
| P-08 | `input/existing/docs/网关接口协议.md` L11（DEV-ONLY 拒绝） | — | 不需改动；落位方式见 `contract-baseline.md` §8.6（C-026） | — |

## 8. 需固件协同项（Firmware Coordination — 本 ADR 范围）

| # | 协同项 | v1 阶段性策略 |
|---|---|---|
| FC-01 | ACK 非零结果补齐 `error_code`（§2.2 词表） | App 容忍缺失；补齐后自动获得精确提示；不阻塞 v1 |
| FC-02 | `1008 hardware_timeout` 在硬件路径（门磁/下位机 ACK 超时）真实发出 | App 预留映射（超时/未确认文案）；仿真器不发出时不影响 v1 |
| FC-03 | 1001-1007 语义确认与仿真器一致（本 ADR §2.2 表） | 若某网关实现与统一表不一致，以 `error_code` 兜底；差异登记为偏差 |

## 9. 未决与假设

- **假设 A-ADR1-1**：真实网关固件与仿真器 L50-56 使用同一编码（二者同源；`WP2` 未获硬件证据，仿真器自述 DEV-only，`WP2` §8.5）。若未来硬件证据推翻，按 Change Impact 重开本 ADR §2。
- **假设 A-ADR1-2**：`state-report.schema.json` 的固定属性名（`Door_01_Online` 等）对应内置设备族；外部模块设备经 `DeviceInventoryJson`（L47-51）承载——归 C-023 落地设计（`contract-baseline.md` §7）。
- 未决：勘误后的散文规范是否保留对旧驼峰命名的"历史注记"——由文档维护决策，不影响实现。

---

*ADR-001 结束。本裁定的规范性表格、映射表与勘误全文见 `artifacts/20-architecture/contract-baseline.md`；本 ADR 与 `WP2`/`WP3` 证据在行号级对应，任何证据输入变更应触发 Change Impact 重评。*
