# 契约基线（Contract Baseline v1.0）

- **Artifact ID**: CONTRACT-BASELINE-001
- **Producer**: agent:solution-architect
- **Type**: Architecture / Interface Contract Baseline（规范性）
- **Status**: Proposed（待 G-004 门禁批准；批准后为实现与评审的约束基线）
- **Date**: 2026-10-17
- **Task**: `wp-004-contracts`（task 分支 `task/wp-004-contracts`，父分支 `feat/yaocore-app`，base commit `54c1d786`）
- **Workflow**: STANDARD / GATED_AUTO
- **决议引用**: D-011（Q1）、D-012（Q2）、D-014（Q3）；见文末「决议（RESOLVED，2026-10-17）」
- **Upstream**: ADR-001（线格式与错误语义）、ADR-002（LAN 安全通道）、ADR-003（家庭凭据）、ADR-004（家庭/房间/设备边界）；`WP2`、`WP3`；26 项冻结输入
- **Downstream**: wp-005 交付规划、wp-006 DES-001 详细设计、实现任务、TEST-001、评审门禁（G-004 后续）、文档维护轮次（勘误与修订提案）
- **用法**: 本文档的 §1-§4 为**冻结基线**（实现必须遵守）；§5-§7 为裁定结果与勘误；§8 为 v1 范围声明；§9-§11 为索引、补丁提案与固件协同。任何条目变更须走 ADR/修订流程并触发 Change Impact。

---

## 1. 权威顺序声明（C-008）

面向"同一事实在哪份资料里最可信"的排序（`WP2` §4、`WP3` §0.3、`config/project.md` L66）：

| 域 | 权威顺序（高 → 低） | 说明 |
|---|---|---|
| **协议数据面（线格式、canonical、错误语义）** | ① `input/api/protocol/` schema 家族（12 个 JSON Schema）→ ② `input/api/protocol/README.md`（schema 不可表达的规则）→ ③ `input/api/protocol/*-test-vectors*.json` 4 份向量 → ④ `input/api/Gateway_API_Specification.md` 散文（**示例部分已勘误，见 §5.2**） | ADR-001 §1.2 |
| **BLE 配网** | ① `ble-enrollment-identity-*.schema.json` → ② `input/existing/docs/BLE配网设计.md`（协议语义、常量、验收）→ ③ `Gateway_API_Specification.md` §2（**身份示例已勘误**） | ADR-001 §3 |
| **外部模块** | ① `module-*.schema.json` + `module-hmac-test-vector.json` → ② `input/existing/docs/EXTERNAL_MODULE_PROTOCOL.md` | README L24-30 |
| **产品行为 / 需求** | PRD（`YaoCore_HarmonyOS_App_Requirements.md`） | `config/project.md` L55/L66 |
| **系统结构 / 模块职责** | 架构（`App_System_Architecture.md`） | 同上 |
| **数据与状态** | 数据模型（`Data_and_State_Models.md`），**受本基线 §2/§6 裁定与 DATA-001 修订提案约束** | ADR-001/004 |
| **界面与交互** | UIUX（`UI_UX_Specification.md`） | 同上 |
| **旧仓库文档/归档代码（LEGACY-001）** | 最低：行为参考与移植来源；与 schema/PRD 冲突时以高优先者为准 | `WP2` §4；`project-state.md` L17 |
| **测试夹具（仿真器、Python 工具）** | 期望清单来源，非权威；自述 DEV-only | README L5-6；`WP2` §8.5 |

**冲突处置规则**：高优先者与低优先者冲突时，以高优先者为准并登记勘误/提案（不得静默择一）；同域内冲突交给对应 ADR/维护轮次裁决。

---

## 2. 线格式 ↔ 内部模型字段映射（P0-1，ADR-001 §1/§5）

> **线格式权威 = schema 命名**（ADR-001 §1.2）。下表左列为线格式（出站必用），右列为 App 内部模型命名（允许保留，仅在本映射层转换）。**入站**：信封/身份/安全字段严格校验；状态别名（右列命名出现于线上）允许读取回退并计入 `protocolDeviation`，永不写出。

### 2.1 `GET /discover` 顶层

| 线格式（schema） | 类型/约束 | App 内部 | 语义与纪律 |
|---|---|---|---|
| `protocolVersion` | const `"2.0"`（v2.1 协商见 ADR-002 §3） | `DiscoveryResult.protocolVersion` | 非 2.0（且未经 ADR-002 §3 协商确认为 2.1）→ 拒绝整份发现 |
| `gatewayId` | `deviceIdentifier`（≤63，v1 禁 `:`） | `gatewayId` | 必须与 Security1 会话内 `yaocore-id` 完全一致（README L48-53） |
| `gatewayName` | 1..63 | `gatewayName` | 展示名；不影响身份 |
| `serviceId` | const `"SmartHomeService"` | `serviceId` | IoTDA 命名空间常量（≠ 身份端点 `YaoCoreGateway`，ADR-001 §3.2） |
| `generatedAt` | `timestamp` | `generatedAt` | 快照生成时刻（informational） |
| `security.alg` | const `"HMAC-SHA256"` | `security.alg` | 不匹配即拒绝 |
| `security.keyId` | const `"app-key-v1"` | `security.keyId` | 密钥版本标签（ADR-002 §8.1） |
| `security.timeWindowSeconds` | const `120` | `security.timeWindowSeconds` | 与请求时间窗一致才接受 |
| `security.nonceTtlSeconds` | const `300` | `security.nonceTtlSeconds` | 同上 |
| `devices[]` | 数组（可空） | `devices[]` | 逐项见 §2.2 |

### 2.2 `discover.devices[]` 与 ACK `reported_state.deviceState`

| 线格式 | App 内部 | 说明 |
|---|---|---|
| `deviceId` | `deviceId`（+派生 `globalDeviceId = gatewayId:deviceId`） | 两级标识（ADR-001 §5） |
| `deviceName` | `deviceName` | 网关侧名：仅首次导入提示（ADR-004 §1.2/§2.1） |
| `roomName` | `roomNameHint`（非 `roomName`） | 仅导入建议；本地归属权威（ADR-004 §1/§2.5） |
| `deviceType` | `deviceType` | 9 值枚举（schema L96-98）→ v1 支持范围见 §8.1 |
| `brand` | `brand` | 自由字符串 ≤31 |
| `online` | `isOnline` | 物理在线（网关真值） |
| `power` | `powerStatus` | 电源 |
| `open` | `openStatus` | 门锁/门磁开合 |
| `brightness` | `brightness` | 0..100 |
| `color` | `color` | `#RRGGBB`（大写归一化由 App 处理） |
| `temperature` | `temperature` | 传感器读数 |
| `humidity` | `humidity` | 0..100 |
| `presence` | `presence` | PIR |
| `targetTemp` | `targetTemperature` | 16..30（空调目标温度） |
| `mode` | `mode` | ≤15（LAN）；词表见 §6.3 |
| `position` | `position` | **v1 LAN 契约无此字段**（C-021，§6.2） |
| `speed` | `speed` | **v1 LAN 契约无此字段**；单位见 §6.2 |
| `volume` | `volume` | **v1 LAN 契约无此字段**（C-021） |
| `stateSource` | `stateSource` | 取值集见 §6.1 |
| `triggerDeviceId` | `triggerDeviceId` | 联动触发源（传感器） |
| `automationId` | `automationId` | 网关本地规则 ID |
| `lastRequestId` | `lastRequestId` | 最近一次被接受的命令追踪号（按设备） |
| `lastSeq` | `lastSeq` | 上述命令的序号 |
| `updatedAt` | `updatedAt`（+派生 `stateEpochMs`） | 状态时刻；仲裁见 §2.6 |

**已知旧别名（仅入站回退，ADR-001 §1.2-3）**：`isOnline→online`、`powerStatus→power`、`openStatus→open`、`targetTemperature→targetTemp`；`success` 任何取值一律忽略且不计入成功判定。

### 2.3 `POST /control` ACK（`local-control-ack.schema.json`）

| 线格式 | App 内部 | 说明 |
|---|---|---|
| `request_id` | `ControlResult.requestId` | 必须逐字符等于请求 `request_id` |
| `seq` | `ControlResult.sequence` | 必须等于请求 `seq` |
| `result_code` | `ControlResult.resultCode` | `0` 唯一成功值；统一语义见 §4 |
| `error_code` | `ControlResult.errorCode`（网关侧命名空间） | 稳定字符串；缺失容忍（§4.3） |
| `message` | 仅日志/诊断 | **不得**直接展示给用户（用户文案走 i18n，§4.4） |
| `server_time` | `serverTime`（informational） | 网关时钟；用于偏差提示，不作新鲜度判定（§2.5） |
| `idempotent_replay` | `idempotentReplay` | 出现即"精确重传命中缓存"；不得判为失败、不得重复应用状态 |
| `reported_state`（deviceState） | `reportedState` | `result_code==0` 时 schema 要求存在（L49-63）；缺省 → 协议违规（fail-closed） |
| `reported_state`（gatewayState：`gatewayId/online/boardLed/updatedAt`） | `gatewayBoardState` | `target==gatewayId` 时返回；`boardLed` 用于绑定期板载 LED 确认（BLE 设计 L143） |

**App 判定顺序（实现契约）**：
1. 响应 HMAC 验签（`YAOCORE-RESPONSE-V1`）+ correlation=`request_id:seq`（ADR-002 §2）；
2. `request_id`/`seq` 严格相等；
3. `result_code==0` 且 `reported_state` 存在 → 成功；否则失败（含前端三态回弹，FR-DEV-001）；
4. `idempotent_replay` 不改变判定，仅标记。

### 2.4 身份端点（`yaocore-id`）与云命令（`paras`）映射

| 身份端点线格式 | 说明 |
|---|---|
| `protocolVersion` | const `"2.0"`（v2.1 协商 ADR-002 §3） |
| `serviceId` | const `"YaoCoreGateway"`（**≠云 `SmartHomeService`**） |
| `gatewayId` | 1..63；与 discover 严格比对 |
| `gatewayName` | 1..63（键名权威，ADR-001 §3） |

| 云 `paras`（`cloud-command.schema.json`） | LAN 对应（logical canonical 值） | 说明 |
|---|---|---|
| `RequestId` | `request_id` | 值直接复用 |
| `CmdId` | `cmd_id` | 云恒为 `3001`；LAN 恒为 `2001` |
| `Seq` | `seq` | 值直接复用 |
| `TargetDevice` | `target` | 设备 ID 另置于 REST URI（README L176-178） |
| `Action` / `Value` | `payload.action` / `payload.value` | `Value` = **紧凑 JSON 原子文本**（字符串需带引号/转义；无值即省略） |
| `Timestamp` / `Nonce` / `Alg` / `KeyId` / `Sign` | 同名字段 | `Alg=HMAC-SHA256`；`KeyId=app-key-v1` |
| `object_device_id` | — | 仅允许出现在顶层（MQTT 下行/代理包装），**禁止**出现在 `paras`（CC 描述 L5/L9-12） |

**云命令 canonical 规则（消解 README L164-181 的表述二义）**：签名原文 = 与 LAN 控制**同一 10 行规范串**，各行取"映射后字段的值"，顺序不变：`RequestId / CmdId / Seq / TargetDevice / Action / Value / Timestamp / Nonce / Alg / KeyId`；无末尾换行；`Value` 按 JSON 原子文本；`Sign=hex_lower(HMAC-SHA256(commandSecret, canonical_utf8))`。

### 2.5 时间戳 / `seq` / `request_id` / `nonce` 语义（P0-1）

| 概念 | 规范 | 来源 |
|---|---|---|
| `timestamp` | UTC 紧凑 `yyyyMMddTHHmmssZ`（秒级，无时区偏移）；App 以系统 UTC 时钟生成；网关接受 ≤±120s | README L32-33/L89-92；`local-control-request.schema.json` L58-60 |
| `server_time` | 网关响应生成时刻（同格式）；**informational**：可用于偏差提示（\|\|server_time − 本地\|\| > 120s → 提示校准时间），不参与成功判定 | `local-control-ack.schema.json` L31-33 |
| `nonce`（控制） | `^[A-Za-z0-9_-]{8,64}$`；建议 16 字节小写 hex（32 字符）；同 `(key_id, nonce)` 300s 内不得复用（精确重传除外） | schema L61-64；README L89-103 |
| `nonce`（发现请求） | 16 字节小写 hex；同 300s 规则 | README L113-117/L128-131 |
| `request_id` | `^[A-Za-z0-9][A-Za-z0-9_.:-]{0,126}$`；App 格式 `req-<epochMillis>-<counter>`（示例：`req-1729000000-001`）；按网关作用域生成；用于 correlation 与 ACK 匹配 | schema L60-62/L77-80；`Gateway_API_Specification.md` L130 |
| `seq` | 每网关持久化单调计数器（0..2147483647）；同一值只在**同一命令的精确重传**中复用；回绕策略：达到上限且无在途命令时重置为 0（记录事件） | schema L25-29；README L94-103 |
| `updatedAt` / `generatedAt` / `event_time` | 网关时钟，同 UTC 格式；用于展示与仲裁输入 | schema 各 `timestamp` def |
| 状态仲裁 | 应用规则：仅当 `updatedAt` 不早于已应用状态，或 ACK 与在途命令的 `(request_id,seq)` 匹配且在途命令的 `notBeforeMs` 之后，才应用状态；内部维护单调 `stateEpochMs=max(prior, parsed(updatedAt))` 丢弃陈旧包 | 数据模型 L147-148；归档 `DeviceRepository.ets` L596-603；需求 L125-126 |

### 2.6 显示名与身份纪律（复述）

`deviceName`/`roomName`/`gatewayName` 均为显示名，改名不改 ID、不触发协议动作（FR-ROOM-002/006；ADR-004 §1/§2）；一切签名/路由/索引只用 `gatewayId`/`deviceId`（FR-ROOM-006 L95）。

---

## 3. HMAC 通道契约摘要（ADR-002 §2，规范性引用）

| 项 | 规则 | 来源 |
|---|---|---|
| 控制 canonical | 10 行值串（`request_id,cmd_id,seq,target,action,value,timestamp,nonce,alg,key_id`），无末尾换行；`cmd_id=2001`；value 单 JSON 原子（缺省=空行） | README L57-87 |
| 发现请求 canonical | `YAOCORE-DISCOVER-V2\nchallenge\ntimestamp\nnonce\nHMAC-SHA256\napp-key-v1` | README L117-126 |
| 响应 canonical | `YAOCORE-RESPONSE-V1\nkind\ncorrelation\nsha256_lower_hex(body_utf8)`，`kind∈{discover,control}`；correlation=challenge 或 `request_id:seq` | README L137-157 |
| 时间窗 / nonce TTL | ±120s / 300s；仅通过全部校验后入缓存；失败不消耗 nonce | README L89-103 |
| 幂等 | 精确重传 → 原状态+原 ACK（可加 `idempotent_replay:true`）；同 nonce 异内容 → HTTP 409 / `1005` | README L94-103 |
| 比对 | 常数时间；失败一律 fail-closed；不降级 | README L86-87/L155-157；ADR-002 §2 |
| 通道档案 | P-HMAC（HTTP+HMAC，基线）/ P-TLS-PIN（HTTPS+指纹固定+HMAC）/ P-BLOCKED（拒绝明文回退） | ADR-002 §6 |
| 指纹 | `sha256-spki-der` = SPKI-DER 的 SHA-256，64 位小写 hex；多 pin 有序；与 `gatewayId` 绑定；轮换重叠期规则 | ADR-002 §4 |
| 密钥 | per-gateway `command_secret`（≥16B，建议 32B）；`key_id` 为版本标签；家庭容器=逐网关 secret+pin；存储与轮换 | ADR-002 §8 |

---

## 4. 统一错误码表与用户提示映射（ADR-001 §2）

### 4.1 网关结果码（唯一权威表）

| `result_code` | 稳定名称（`error_code`） | 触发条件 | 建议 HTTP | App 内部处理分类 |
|---|---|---|---|---|
| `0` | —（必须缺省） | 硬件/下位机真实确认且 `reported_state` 完整 | 200 | `COMMITTED` |
| `1001` | `invalid_request` | 结构非法/缺字段/额外字段/越界/`cmd_id≠2001` | 400 | 协议缺陷（记录并上报诊断，不重试） |
| `1002` | `unsupported_security` | 未知 `key_id`/`alg` | 401 | 安全配置错误（引导重新配网/更新密钥） |
| `1003` | `timestamp_rejected` | 时间偏差/格式错误 | 401 | 时钟问题（提示校准时间） |
| `1004` | `bad_signature` | HMAC 不匹配 | 401 | 密钥不一致（引导重新配网/更新密钥） |
| `1005` | `replay` | 同 nonce 异内容 | 409 | 客户端缺陷（应查 retry/缓存逻辑；可安全重试新 nonce） |
| `1006` | `unsupported_command`（细分：`unknown_device` / `unsupported_action` / `unsupported_gateway_action`） | 目标不存在/动作不支持 | 422 | 能力不匹配（刷新设备列表；v1 范围外设备提示"暂不支持控制"） |
| `1007` | `device_offline` | 外设/下位机离线 | 503 | 可重试（回弹 + "设备离线"） |
| `1008` | `hardware_timeout` | 硬件超时无物理 ACK | 504（建议） | 可重试/提示"未确认到位"（门锁场景联动 ADR-004 §6） |
| `1009..9999` | `unknown_<code>`（App 本地合成） | 保留/未来 | — | **失败**（fail-closed）；提示通用失败 + 记录偏差 |

> 表来源：ADR-001 §2.2（仿真器编码 + API 散文表 1008 语义保留）；HTTP 列为仿真器实测/建议值，**HTTP 状态不构成成功判定**（ADR-001 §2.2-4）。

### 4.2 App 自有错误编码（不复用网关码）

传输/校验/环境失败使用 App 命名空间（字符串编码，参考归档做法）：`LOCAL_REQUEST_FAILED`、`HTTP_<code>`、`CONTROL_RESPONSE_AUTH_FAILED`、`DEV_SIMULATOR_REJECTED`、`TLS_PIN_MISMATCH`、`TLS_HANDSHAKE_FAILED`、`TLS_UNAVAILABLE_ADVERTISED`、`ACK_CORRELATION_MISMATCH`、`INVITE_INVALID/EXPIRED/REVOKED` 等（详表归 DES-001；命名规范 `SCREAMING_SNAKE`）。

### 4.3 双轨判定策略

1. `result_code` 主判（§4.1）；2. `error_code` 存在时优先用于细分提示（否则按 `result_code` 兜底）；3. `error_code` 缺失 → 容忍（v2.0 存量网关）；4. 未知码 → 失败 + 记录 `protocolDeviation`；5. `result_code==0` 携带 `error_code` → 记录偏差，不影响成功判定。

### 4.4 用户提示映射（i18n 键约定）

- 键族：`errors.gateway.<stable_name>`（例：`errors.gateway.bad_signature`、`errors.gateway.unknown_device`）与 `errors.app.<SCREAMING_SNAKE 小写化>`（例：`errors.app.local_request_failed`）；
- 映射唯一入口：一个 `errorCodeToI18nKey(code, errorCode?)` 纯函数（wp-006 定义签名）；UI **禁止**直接展示 `message` 或拼接文本；
- 门锁/门磁专项键：`door.state.secured/unconfirmed/unknown`、`door.alert.unconfirmed`（ADR-004 §6.4）；
- 通行键：`common.retry`、`common.cancel`、`common.confirm`（`docs/internationalization.md` L39-42）；
- 键位规范与 key parity 门禁见 `i18n-resource-design.md`。

---

## 5. 身份端点字段表与 `Gateway_API_Specification.md` 勘误清单（WP2-F01/F03）

### 5.1 身份端点（裁定结果，详 ADR-001 §3）

| 字段 | 权威值/约束 | 依据 |
|---|---|---|
| 请求 | `{"op":"get_identity","protocolVersion":"2.0"}`（v2.1 协商见 ADR-002 §3） | `ble-enrollment-identity-request.schema.json` L6-15 |
| `protocolVersion` | const `"2.0"` | 同上 |
| `serviceId` | const `"YaoCoreGateway"`（**≠** 云 `SmartHomeService`） | `ble-enrollment-identity-response.schema.json` L12-14 |
| `gatewayId` | 1..63，pattern `^[A-Za-z0-9][A-Za-z0-9_.:-]{0,62}$`；fail-closed 校验 | 同上 L15-20 |
| `gatewayName` | 1..63（键名权威） | 同上 L21-25 |
| 封闭性 | `additionalProperties:false`；任何额外字段 → `PROVISIONING_IDENTITY_INVALID` | 同上 L6；归档 `BleProvisioningService.ets` L655-657 |

### 5.2 勘误清单（Errata；不改原文，供文档维护）

| ID | 目标位置 | 原文问题 | 取代为 | 关联证据 |
|---|---|---|---|---|
| E-01 | `Gateway_API_Specification.md` L88-121（discover 示例） | 设备用 `isOnline/powerStatus`；顶层多 `keyId`、缺 `generatedAt/security` | schema 命名 + 顶层补 `generatedAt/security`、删 `keyId` | `WP2` §6-F01/F.15-F.16；ADR-001 §1 |
| E-02 | 同上 L187-204（ACK 示例） | 多 `success`；缺 `server_time`；`reported_state` 缺 `online`、多 `deviceType`、用 `powerStatus` | 删 `success`；补 `server_time`；`reported_state` 按 `deviceState` 修订 | `WP2` §6-F01/F.17-F.18b；`WP3` §2.1-C001 |
| E-03 | 同上 L215-227（结果码表） | 与仿真器编码冲突 | 替换为 §4.1 统一表（含 1008 语义保留） | ADR-001 §2；`WP2` §6-F02 |
| E-04 | 同上 L44-45（身份示例） | `serviceId:"SmartHomeService"` + `displayName` | `serviceId:"YaoCoreGateway"` + `gatewayName` | ADR-001 §3；`WP2` §6-F03 |
| E-05 | README L37-41 | "display name" 未给键名 | 明确为 `gatewayName` | ADR-001 §3；补丁 P-02 |
| E-06 | 需求 L67；数据模型 L47 | 邀请码"6~8 位" | "6 位（Crockford Base32 去歧义）" | ADR-004 §3；ADR-003 §4.2 |
| E-07 | 数据模型 L109；需求 L93 | `GW-9A216D:LIGHT_01` / `GW-01:LIGHT-01` | 两级标识模型（复合键为 App 派生；线上一律裸 id） | ADR-001 §5；DATA-001 提案 |
| E-08 | 数据模型 §3 L192-217；API L146-166 | GCM 载荷示例被当作 v1 正常路径 | 归档为 `EXT-GCM-001`（v1 不实现） | ADR-002 §5 |
| E-09 | 数据模型 L133 | 空调 `mode` 5 值注释 | 7 值词表（§6.3） | ADR-001 §2；`WP3` §2.3-C025 |
| E-10 | 数据模型 L135 | 风扇 `speed` "档位 1~5" | 线上单位 = percent 0..100（§6.2） | `WP3` §2.3-C022 |
| E-11 | 需求 L126；数据模型 L144 | `stateSource` 4 值 | 5 值集合（§6.1） | `WP3` §2.3-C016 |
| E-12 | `Gateway_API_Specification.md` L126 | 请求路径未区分 v1 通道档案 | 依 ADR-002 §6（HTTP+HMAC / HTTPS+pin） | ADR-002 §6；补丁 P-07 |

---

## 6. 协议枚举与状态字段裁定（C-016 / C-021 / C-022 / C-025）

### 6.1 `stateSource` 取值集（C-016）

- 冲突：PRD L126（4 值）与数据模型 L144（4 值）vs protocol README L197-198（5 值）vs API L106/L200 与归档 UI 标签（`device.feedback`）。
- **裁定**：v1 采用**并集 5 值**：`sensor.physical`、`device.feedback`、`automation.local`、`app.lan`、`app.cloud`。
  - 依据：机器契约散文（README L197-198）列出 5 值；归档 UI 对 `device.feedback` 有专门标签（`DevicePage.ets` L2224）；`automation.local` 在 PRD/DM/README 三处存在；4 值版本是对 protocol 的遗漏。
- 纪律：App 对 5 值均有 i18n 标签（`stateSource.*`）；未知值 → 通用标签 + 记录偏差；出站不生成 `stateSource`（只由网关生成，PRD L125-126 为展示需求）。
- 影响：FR-DEV-005、FR-HOME-003；补丁 E-11。

### 6.2 LAN 状态字段缺口（`position/speed/volume`）与 v1 设备范围（C-021 / C-022）

- 事实：`discover-response.schema.json` 设备对象（L82-167）与 `local-control-ack.schema.json` `deviceState`（L80-149）**均封闭且无 `position/speed/volume`**；而 `module-state.schema.json` L38-40 定义了三者（percent 0..100），`网关接口协议.md` L40-42 声明 curtain/fan/speaker 支持。
- **裁定**：
  1. **v1 设备范围 = `door` / `light` / `sensor` / `ac`**（完整支持，见 §8.1）；`curtain/fan/speaker/switch/camera` 为"**可识别但不受支持**"：DTO 必须能解析并持有其状态（schema 合法），UI 降级为只读展示 + "暂不支持控制"标记，**不下发任何控制命令**（D-011）。
  2. 不修改 v1 schema；`position/speed/volume` 的 LAN 表达能力记入扩展提案 **`EXT-LAN-STATE-001`**（需固件协同，归档依据：ADR-001 §1.4-A4 与 `WP2` §7.3）。
  3. **`speed` 单位裁定**：线上/模型一律 **percent 0..100**（依据：`module-state.schema.json` L22/L39；`EXTERNAL_MODULE_PROTOCOL.md` L159；归档 `DeviceRepository.ets` L608 以 0..100 clamp）。"1~5 档"是**适配/展示层**表达（可由适配器映射或由 UI 以档位标签呈现），不得作为线格式单位（E-10）。
  4. `position` 语义（未来扩展沿用）：0=全关、100=全开（`EXTERNAL_MODULE_PROTOCOL.md` L162）。
- 影响：FR-DEV-002/003/004（支持的 4 类）、FR-HOME-004；`contract-baseline.md` §8.1；测试计划需覆盖"不受支持类型只读降级"。

### 6.3 空调 `mode` 词表（C-025）

- 冲突：数据模型 L133（5 值）vs `module-state.schema.json` L37（7 值，含 `ECO/SLEEP`）vs LAN schema 仅限长度（DR L139-142 / CA L120-123；SR ≤32）vs 归档格力适配器把"节能"归一为 `ECO`（`GreeAcAdapter.ets` L21）。
- **裁定**：v1 规范词表 = **`AUTO` / `COOL` / `HEAT` / `DRY` / `FAN` / `ECO` / `SLEEP`**（7 值）。
  - App 出站 `SET_MODE` 只发送 7 值常量（长度必然 ≤15，满足 LAN schema）；
  - 入站接受 ≤32（对齐 SR L120-123）但**归一化**：词表内直接采纳；表外值保留原文用于展示并标记"非标准模式"，**禁止**将其回发；
  - UI 标签本地化（`ac.mode.cool` 等），代码中不得出现中文字面量（i18n 设计约束）；
  - 注意：`hmac-sha256-test-vectors.json` 的 `"制冷"` 值是**签名编码夹具**（unicode/escape 验证），不构成词表授权（ADR-001 §2；README L18-19 自述为公开测试数据）。
- 影响：FR-DEV-004；`GreeAcAdapter` 的移植以 7 值为基线；补丁 E-09。

---

## 7. 云路径裁定（C-023）与 WP2-F04 处置

### 7.1 `App ↔ IoTDA` v1 落地设计（范围：配置 + 命令 + 影子读取；不做 Token 自动获取）

| 项 | v1 契约 | 依据 |
|---|---|---|
| 配置项 | `endpoint`（region 域名）、`projectId`、`deviceId`（网关的 IoTDA 设备 ID）、`accessToken`（IAM，用户提供）；`shadowEndpoint` 可覆盖 | 归档 `CloudService.ets` L142/L718/L728/L739/L751；需求 FR-SET-003 L138-139 |
| Token 存储 | `accessToken` → Asset Store（别名 `yaocore.cloud.token.v2`）；其余 → Preferences/RDB | ADR-002 §8.3；归档 `SecureStorageService.ets` L18 |
| 命令下发 | `POST https://{endpoint}/v5/iot/{projectId}/devices/{deviceId}/commands`，头 `X-Auth-Token`；Body == `cloud-command.schema.json`（`service_id=\"SmartHomeService\"`、`command_name=\"SetDeviceStatus\"`、`paras` 按 §2.4 映射） | README L164-181；CC 全文；归档 L718 |
| 签名 | `Sign = hex_lower(HMAC-SHA256(commandSecret, canonical_utf8))`，canonical 见 §2.4 | README L164-181 |
| 影子读取 | `GET .../devices/{deviceId}/shadow`（X-Auth-Token）；解析 `services[].properties`（`SmartHomeService`） | README L248-249；归档 L728；SR 全文 |
| **命令完成判定** | 影子中出现 `*_LastRequestId == RequestId` 且 `*_LastSeq == Seq`（内置设备），或 `DeviceInventoryJson` 中同 id 设备的 `lastRequestId/lastSeq` 匹配（外部模块设备）；**且**该属性 `event_time` 不早于命令时刻（容差 2s）。IoTDA 受理、旧影子、网关缓存均不构成执行确认 | 需求 L10；`网关接口协议.md` L66；SR L47-51/L73-101；参考归档新鲜度判定（`NetworkService.ets` L520-525，`eventMs + 2000 >= notBeforeMs`） |
| 设备 inventory | **SR 固定属性为一等公民**（`Door_01_Online` 等内置属性，SR L37-45）；其他设备一律经 `DeviceInventoryJson`（≤8192，JSON 字符串，按稳定 `device_id` 键的状态数组）承载；不向固件提协议变更（D-014） | SR L37-45/L47-51 |
| Token 生命周期 | v1 **不做**自动刷新/后端换取（D-012；`网关接口协议.md` L66：IAM Token 不应烧录网关；正式部署用受控后端短期权限）；Token 过期 → 明确错误提示并要求用户更新 | GWO L66；归档 L739 |
| 云错误映射 | IoTDA HTTP 4xx/5xx + 业务错误体 → App 命名空间错误码（§4.2）+ i18n（`errors.cloud.*`）；**不得**与网关 `result_code` 混用 | §4.2；假设见下 |
| 范围外（v1 声明） | IoTDA 应用侧设备 CRUD、IAM Token 服务端换取、MQTTS 直连、产品模型在线管理 | 需求只要求配置与命令/影子 |

**假设 A-CB-1**：IoTDA REST 响应体字段名（如错误 `error_code/error_msg`）未在冻结语料中定义，v1 以归档实现与 IoTDA 公开 REST 约定为准（`CloudService.ets` 解析路径 L460-470/L728-770，作为行为证据而非权威）；实现时必须对未知响应结构 fail-closed 并记录。

### 7.2 WP2-F04（`cloud/iotda/product-profile.json` 缺失）

- 现状：全仓库 0 命中；阻塞 2 个 Python 网关套件用例与 `state-report` 子集校验（`WP2` §3.3-A）。
- **裁定：补建（测试资产）+ 降级（不阻塞 App）**：
  1. 以 `state-report.schema.json`（L35-151 属性全集）为**唯一权威**反推产品模型属性清单与命令（`SetDeviceStatus`）定义；
  2. 产物落在测试资产区（如 `tools/test-fixtures/iotda/product-profile.json`），**不**作为产品运行时资产；
  3. wp-005 规划中将该补建列为测试任务（关联 `WP3` §5-P2-15）；
  4. App 实现**不依赖**该文件（云路径契约按 §7.1）。

---

## 8. v1 范围声明（Scope Declaration）

### 8.1 设备类型范围（C-021 依据）

| `deviceType` | v1 处置 | 依据 |
|---|---|---|
| `door` | **完整支持**（开合控制 + ACK 确认 + 门磁到位语义，ADR-004 §6） | FR-DEV-003；schema `open`；`网关接口协议.md` L36 |
| `light` | **完整支持**（开关/亮度/颜色 + 55ms 节流） | FR-DEV-002；schema `power/brightness/color` |
| `sensor` | **完整支持**（温湿度/PIR 只读 + 溯源） | FR-HOME-003；schema `temperature/humidity/presence` |
| `ac` | **完整支持**（目标温度/模式/多品牌适配） | FR-DEV-004；schema `targetTemp/mode` |
| `switch` / `camera` | 可解析、只读降级（不提供控制） | schema 枚举含之；PRD 无 FR；`网关接口协议.md` 能力表不含 camera |
| `curtain` / `fan` / `speaker` | 可解析、只读降级（不提供控制）；状态字段缺口见 §6.2 | schema 枚举含之；LAN 契约缺 `position/speed/volume`；PRD 无 FR；UIUX 无对应组件 |
| 未知 `deviceType` 值 | 解析保留 + "未知类型"只读展示 + 偏差记录 | schema 封闭枚举 → 未知值即偏差 |

> 依据链：PRD 功能需求仅覆盖 door/light/sensor/ac（§3.5、§3.3）；UIUX 组件集（`StatusBanner/ClimateCard/LightCard/DoorCard/SceneCard/RoomCard`，L58）无窗帘/风扇/音箱；LAN 契约字段缺位（§6.2）。产品形态已由 **D-011** 裁定为**只读降级**（保留本表、不隐藏），见文末「决议（RESOLVED，2026-10-17）」与 §9 R-26。

### 8.2 云路径

- v1 **在范围**：IoTDA 配置（§7.1）、签名云命令、影子轮询确认、Token 过期提示（D-012）。
- v1 **范围外**：Token 自动获取/刷新、MQTTS 直连、应用侧设备管理、后端代理（D-012）。
- 依据：FR-SET-003、FR-HOME-001（云状态展示）、需求 L10（广域网回退）与 GWO L62-66 的边界要求。

### 8.3 GCM 扩展归档

`EncryptedPayloadEnvelope` / `SecureLocalControlPacket`（数据模型 §3）与 API L146-166 → **`EXT-GCM-001`**（归档，不实现；`cmd_id=2002` 与字段名保留为文档常量；App 无运行分支）。见 ADR-002 §5。

### 8.4 旧版本面适用性映射（C-003）

| 旧文档内容 | v1 适用性 | 说明 |
|---|---|---|
| `BLE配网设计.md` §2-§5：GATT 发现（`0x2901` 动态映射）、Security1 数学（X25519/PoP/AES-CTR 流）、protobuf（ESP-IDF 5.2 文件清单）、MTU ≥247、串行 GATT 纪律、身份 fail-closed | **适用**（协议语义与常量） | 目标网关固件仍为 ESP32-S3/ESP-IDF；App 必须与之互操作（`WP2` 向量 5/5） |
| `BLE配网设计.md` L151 "当前 target API 22 使用 `ohos.permission.ACCESS_BLUETOOTH`" | **仅权限名适用；API 级别陈述不适用** | 本 App 目标 API 14+/targetSdk 26.0.0（`config/project.md` L32/L42）；权限声明与运行时授权按当前 SDK 在实现中验证（module.json5 目前无声明——实现任务） |
| `BLE配网设计.md` L104-114 ESP-IDF 版本/构建细节 | **仅协议文件清单适用**（作为互操作常量） | 固件构建链不在本仓库（`config/project.md` L50/L55） |
| `网关接口协议.md` §2-§5 | **适用**（控制确认、路由、模块身份、云边界） | 与 README/schema 一致部分 |
| `EXTERNAL_MODULE_PROTOCOL.md` 全文 | **适用**（模块协议为网关↔模块域；App 不实现，但需理解状态来源） | README L24-30 指向其完整指南 |
| 归档 App 的 API 用法（HTTP/BLE/Asset） | **行为参考**（非权威） | 与当前 SDK 的差异在实现期验证 |

### 8.5 UML 取舍声明（C-014）

- `input/uml/` 为空（`WP3` §2.1-C014）。**裁定**：architecture 阶段**不**产出独立 UML 工件集；交互/流程以 UIUX 内嵌 Mermaid（L80-103/L113-138/L203-221）与 DES-001（wp-006）中的状态机文本/Mermaid 为准；若后续阶段需要模型工件，由 wp-005 在交付规划中立项（不隐含在 v1 契约）。

### 8.6 DEV-ONLY 拒收（C-026）

- 生产构建必须拒绝 `X-YaoCore-Simulator: DEV-ONLY` 响应与 `DEV_SIMULATOR_ONLY` 健康文档；Mock/仿真器仅限开发/测试（ADR-004 §7.1；`网关接口协议.md` L11；README L224-226）。列为安全约束 SC-11（`project-constraints.md`）。

### 8.7 版本修订机制建议（C-013）

- 建议为主文档（PRD/架构/API/数据/UIUX/BLE/模块协议）引入页首元数据：`版本 | 生效日期 | 维护者`；变更以"勘误（Errata）+ 版本小版本递增"记录；
- 协议契约变更走版本化（`protocolVersion` 递增 + schema 新文件，如 ADR-002 §3 的 v2.1）；不原地改写已发布语义；
- 建议由文档维护轮次执行（关联 `WP3` §5-P2-16）；本基线 §5.2/§10 的勘误与提案即为首批输入。

### 8.8 测试移植口径（衔接 wp-005；C-007 部分缓解）

- 保留为 Python 契约层工具（DEV-only）：仿真器、crosscheck、密钥派生工具（`WP2` §7.1）；
- 移植为 ArkTS/Hypium：canonical/HMAC 向量、响应验签、发现签名、BLE Security1 编解码与 RFC7748 向量、ACK 解析语义、发现 DTO 映射、身份 fail-closed（`WP2` §7.2）；
- 不可移植（缺资产）：网关 C 源码断言、Arduino 源断言、依赖 `module.json5` 的旧断言（`WP2` §7.3）；
- TLS Mock 形态与计时口径（NFR 4.3）归 TEST-001（ADR-002 §7.3；`WP3` §5-P1-13）。

---

## 9. 裁定 → 证据 → 影响索引

| # | 裁定 | 证据（主） | 影响的 FR / 工件 |
|---|---|---|---|
| R-01 | 线格式权威 = schema 家族（ADR-001 §1） | `WP2` §4.1；4 方可运行证据 | FR-DEV-001/005、FR-HOME-003；全部 DTO/契约测试 |
| R-02 | 统一错误码 + `error_code` 双轨（ADR-001 §2） | `WP2` §6-F02；仿真器 L50-56 | FR-DEV-001；UI 错误文案；固件 FC-01/FC-02 |
| R-03 | 身份端点字段（ADR-001 §3） | `WP2` §6-F03；归档 L655-657 | FR-GW-002；勘误 E-04/E-05 |
| R-04 | 校验边界宽容策略（ADR-001 §4） | `WP2` §5 末 | 测试计划；仿真器对齐（F06） |
| R-05 | 两级标识 + id 字符集冻结（ADR-001 §5） | `WP3` §2.1-C010；DM L109 | FR-ROOM-006；DATA-001 提案 P-11 |
| R-06 | HMAC 全链必做（ADR-002 §2） | README L55-189；`WP2` 66/66 | NFR-4.1；FR-DEV-001/002 |
| R-07 | 指纹经身份 v2.1 下发 + 三通道档案（ADR-002 §3/§6） | `WP3` §4.1（C-019/G-D7-1/3） | FR-SET-002、FR-GW-002/003；固件 FC-01/FC-02 |
| R-08 | 指纹格式/绑定/轮换（ADR-002 §4） | 架构 L135-137；DM L233-234 | FR-SET-002 |
| R-09 | 密钥模型/存储/轮换（ADR-002 §8） | PRIV L37；`EXTERNAL_MODULE_PROTOCOL.md` L24；归档 Asset Store | FR-SET-002；NFR-4.2；DES-001 |
| R-10 | GCM 归档 `EXT-GCM-001`（ADR-002 §5） | DM §3；API L146-166；D-007 | FR-SET-002（预留不实现） |
| R-11 | 离线凭据容器与双路径封装（ADR-003 §3/§4；D-009） | `WP3` §4.2（G-D8-1/2） | FR-FAM-002/003；DATA-001 提案 P-12 |
| R-12 | 离线校验语义 + 回执（ADR-003 §5；D-010） | `WP3` §4.2（G-D8-3） | FR-FAM-002/003/004 |
| R-13 | 撤销=轮换模型与成本（ADR-003 §6；D-013） | `WP3` §4.2（G-D8-4） | FR-FAM-003；ADR-002 §8.4 |
| R-14 | 指纹随凭据分发（ADR-003 §7） | `WP3` §4.2（G-D8-5）；架构 L112-113 | FR-FAM-002 |
| R-15 | 威胁模型 14 项（ADR-003 §8） | `WP3` §4.2（G-D8-6） | 评审/UI 文案义务 |
| R-16 | 房间=本地、`roomName` 提示、仲裁表（ADR-004 §1/§2） | `WP3` §2.1-C005/§2.3-C015 | FR-ROOM-001..006、FR-HOME-002 |
| R-17 | 改名/换房/删除=本地（ADR-004 §2） | `WP3` §2.1-C006；MC L12 | FR-ROOM-003/004/005/006 |
| R-18 | 未分配/禁用本地态（ADR-004 §2.1-4） | DM L165-179；UIUX L126-147 | FR-ROOM-004 |
| R-19 | 邀请码 6 位（ADR-004 §3） | UX L90/98/106 | FR-FAM-002；勘误 E-06 |
| R-20 | Guest 时效（ADR-004 §4；ADR-003 §9.2；D-013） | `WP3` §2.3-C017 | FR-FAM-002/003 |
| R-21 | 手动 IP=定位非身份；高级入口保留（ADR-004 §5；D-015） | `WP3` §2.1-C012；BLE 设计 L143 | FR-HOME-001；安全 |
| R-22 | 门锁-门磁四阶段 + 一次性关联引导（ADR-004 §6；D-016） | 需求 L121-122；GWO L24 | FR-DEV-001/003；UIUX 补丁 P-13 |
| R-23 | DEV-ONLY 落位（ADR-004 §7.1） | GWO L11；README L224-226 | 安全约束 SC-11；测试边界 |
| R-24 | 语言入口（ADR-004 §7.2） | 需求 L139；架构 L56 | FR-SET-003；i18n 设计；补丁 P-10 |
| R-25 | 5 值 `stateSource`（§6.1） | README L197-198；归档 L2224 | FR-DEV-005；勘误 E-11 |
| R-26 | 设备范围 4 类 + 只读降级（§6.2/§8.1；D-011） | PRD §3.5；UIUX 组件集；DR/CA 封闭 | FR-DEV-002/003/004；扩充提案 `EXT-LAN-STATE-001` |
| R-27 | `speed` percent / `mode` 7 值（§6.2/§6.3） | MS L22/L37；Gree L21 | FR-DEV-004；勘误 E-09/E-10 |
| R-28 | 云路径 v1 范围与完成判定（§7.1；D-012） | CC/SR；GWO L62-66；归档 CloudService | FR-SET-003、FR-HOME-001 |
| R-29 | WP2-F04 补建+降级（§7.2） | `WP2` §3.3-A | 测试计划；`WP3` §5-P2-15 |
| R-30 | v1 范围与修订机制（§8） | `WP3` §2.1-C003/C013/C014、§5 | wp-005 规划 |
| R-31 | `state-report` 固定属性一等公民；其他设备走 `DeviceInventoryJson`（D-014） | SR L37-51；§7.1 | FR-SET-003；云命令完成判定；无协议变更 |

---

## 10. 补丁提案汇总（Patch Proposals — 不直接修改 `input/`）

| # | 目标 | 改动摘要 | 来源 |
|---|---|---|---|
| P-01 | `Gateway_API_Specification.md` L88-121 | discover 示例按 schema 重写（E-01） | ADR-001 §7 |
| P-02 | `protocol/README.md` L37-41 | "display name" → `gatewayName`；注明两个 `serviceId` 命名空间（E-05） | ADR-001 §7 |
| P-03 | `Gateway_API_Specification.md` L187-204 | ACK 示例修订（E-02） | ADR-001 §7 |
| P-04 | `Gateway_API_Specification.md` L215-227 | 结果码表替换（E-03 → §4.1） | ADR-001 §7 |
| P-05 | `Gateway_API_Specification.md` L44-45 | 身份示例修订（E-04） | ADR-001 §7 |
| P-06 | 仿真器（未来 `tools/simulator/`） | 生成侧对齐 schema 边界；接受侧宽容声明 | ADR-001 §7 |
| P-07 | `Gateway_API_Specification.md` L126 | 通道档案表述（P-TLS-PIN/P-HMAC） | ADR-002 §6 |
| P-08 | `Data_and_State_Models.md` §3 | 标注 `EXT-GCM-001` 归档（E-08） | ADR-002 §5 |
| P-09 | 需求 L67；数据模型 L47 | 邀请码 6 位（E-06） | ADR-004 §3 |
| P-10 | `UI_UX_Specification.md` L70 | 增加语言入口（C-018） | ADR-004 §7.2 |
| P-11 | `Data_and_State_Models.md` L107-120 | 两级标识与存储注释（E-07） | ADR-001 §5 |
| P-12 | `Data_and_State_Models.md` L26-56 | 成员/邀请字段增补（C-017/C-020） | ADR-003 §9 |
| P-13 | `UI_UX_Specification.md` L151-186 | 门锁到位三态与文案纪律（C-024） | ADR-004 §6 |
| P-14 | `Data_and_State_Models.md` L133/L135/L144；需求 L126 | 词表/单位/`stateSource` 修订（E-09/E-10/E-11） | §6 |
| P-15 | 测试资产 | 补建 `product-profile.json`（由 SR 反推） | §7.2 |
| P-16 | 主文档页首 | 版本头机制（C-013） | §8.7 |
| P-17 | v2.1 新 schema 文件（协议目录） | `ble-enrollment-identity-request-v2/response-v2`（提案） | ADR-002 §3 |

## 11. 需固件协同项汇总（Firmware Coordination）

| # | 项 | v1 阶段性策略 | 来源 |
|---|---|---|---|
| FC-01 | `yaocore-id` v2.1 + TLS 发布/轮换 | 无固件时回退 v2.0 → P-HMAC；App 不阻塞 | ADR-002 §10 |
| FC-02 | ACK `error_code` 补齐；1008 发出 | App 容忍缺失；1008 预留映射 | ADR-001 §8 |
| FC-03 | key_id 版本滚动窗口（app-key-v1→v2） | v1 不滚动；材料轮换走 BLE | ADR-002 §8.4 |
| FC-04 | 控制密钥轮换固件流程 | BLE 重配为唯一路径 | ADR-002 §8.4 |
| FC-05 | （未来）`EXT-LAN-STATE-001`：position/speed/volume；`EXT-ROOM-STATE-001`；`EXT-FAMILY-COORD-001`；`EXT-ACL-001` | v1 不做；v1 范围声明 §6.2/§8.1 | §6.2；ADR-003 §13；ADR-004 §1.3 |

---

## 决议（RESOLVED，2026-10-17）

> 原澄清项的三项问题已按 **GATED_AUTO** 裁定，生效值为架构师推荐选项；用户可覆盖，覆盖时须走 Change Impact（至少修订本文档相关章节与测试计划）。权威决策记录：`state/decisions/wp-004-resolutions.md`；ADR/CB 状态维持 `Proposed`，待 G-004 门禁批准。

| 原问题 | 生效裁定 | 编号 | 决策来源 |
|---|---|---|---|
| Q1 不受支持设备类型的产品形态（§8.1） | **选项 A**：`switch/camera/curtain/fan/speaker` 可解析 + 只读降级 + "暂不支持控制"标记；保留 §8.1 只读降级表，**不隐藏**；不扩展协议 | **D-011** | GATED_AUTO（架构师推荐；用户可覆盖） |
| Q2 云路径 Token 体验（§7.1） | **选项 A**：保持用户手工填写 IAM Token；过期明确提示更新；**不做**自动获取/刷新（OAuth 与后端换取在 v1 范围外） | **D-012** | GATED_AUTO（架构师推荐；用户可覆盖） |
| Q3 `state-report` 固定属性与外部模块设备命名（§7.1/§2.4） | **选项 A**：SR 固定属性为一等公民；其他设备一律经 `DeviceInventoryJson` 承载；不向固件提协议变更 | **D-014** | GATED_AUTO（Orchestrator 代决） |

**对实现的约束**：

1. **D-011**：§8.1 表即 v1 产品形态基线；UI 不得隐藏已知但不受支持的设备，须显示只读状态与"暂不支持控制"标记。
2. **D-012**：测试须覆盖"Token 过期提示 + 用户更新"路径；不得引入自动刷新或后端换取的隐式依赖。
3. **D-014**：命令完成判定同时支持内置固定属性与 `DeviceInventoryJson` 两种承载（§7.1），不得为外部设备扩展固定属性名。

**覆盖方式**：用户如选择其他选项，回复对应编号并触发 Change Impact（至少修订 §8.1/§7.1 与测试计划）。

---

*契约基线结束。本文件为 wp-004 的规范性核心；其裁定条目全部来自 ADR-001..004 与冻结输入证据（路径+行）。任何条目变更须走 Change Impact 重评，并更新 §9 索引。*
