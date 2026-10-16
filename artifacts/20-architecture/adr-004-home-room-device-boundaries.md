# ADR-004 — 家庭/房间/设备边界与相关裁定（C-005/C-006/C-015/C-009/C-017/C-012/C-024/C-026/C-018）

- **Artifact ID**: ADR-004
- **Producer**: agent:solution-architect
- **Type**: Architecture Decision Record
- **Status**: Proposed（待 G-004 门禁批准）
- **Date**: 2026-10-17
- **Task**: `wp-004-contracts`（task 分支 `task/wp-004-contracts`，父分支 `feat/yaocore-app`，base commit `54c1d786`）
- **Workflow**: STANDARD / GATED_AUTO
- **Upstream 证据**: `WP3` §2.1（C-005/C-006/C-009/C-012/C-017/C-018/C-024）、§2.3（C-015/C-021/C-026）；ADR-001（标识形态）、ADR-002（安全通道）、ADR-003（成员/访客模型）
- **Downstream 消费者**: `contract-baseline.md`（§6 枚举裁定/§7 云与范围/§9 v1 范围）、DES-001（wp-006：Room/Device/Family 模块）、UIUX 修订提案（C-018/C-024）、DATA-001 修订提案（C-017）、测试计划
- **Traceability**: FR-ROOM-001..006、FR-HOME-001..004、FR-DEV-001/003、FR-FAM-002/003/004、FR-SET-003；NFR-4.1/4.2/4.3

---

## 1. Decision 1：家庭/房间 = App 本地实体，网关只有 `roomName` 提示（C-005）

### 1.1 Context

三份语料互斥（`WP3` §2.1-C005）：

- `Data_and_State_Models.md` L65-74：`RoomModel` 以 **`roomId` (UUID)** 为主键；L115 `DeviceState.roomId`，L116 `roomName` 仅作 UI 缓存；
- `discover-response.schema.json` L91-95：设备携带 **`roomName` 字符串**（必填、`minLength:1`、`maxLength:31`）；L77 顶层无房间列表；`module-register` 的 `room` 同为字符串（`module-*` 家族）；
- `YaoCore_HarmonyOS_App_Requirements.md` L78-82、L101-102：房间是 App 侧创建/命名/过滤的实体，PRD 从未要求网关理解 `roomId`。

同时 `discover-response.schema.json` 设备对象封闭（L168）且无 `roomId`、无未分配/禁用表达（C-015）。

### 1.2 Decision

1. **房间是 App 本地实体**：`RoomModel`（`roomId` UUID + `roomName` + `icon` + `orderIndex`）只在 App 存储中存在；**不进入任何 LAN/云协议**。`familyId` 归属、排序、图标均为本地语义。
2. **网关 `roomName` 是"导入提示"而非事实源**：
   - 仅用于**首次纳管**（该 `deviceId` 在本家庭首次出现）时的默认建议：与本地房间名做**精确匹配**（区分大小写），命中则预填建议房间（需用户确认或按用户设置自动应用）；未命中则设备进入"未分配"池；
   - 纳管后**本地归属为唯一权威**：`roomName` 提示不再驱动任何状态变化（不覆盖、不迁移、不产生冲突提示）；
   - 设备详情页可低优先级展示"网关建议位置：X"（透明性），仅作信息。
3. **不扩展协议**（v1）：不向 discover/模块协议添加 `roomId`、`isUnassigned`、`isEnabled` 字段。理由：FR-ROOM 全部需求可在 App 本地满足；扩展需固件协同且破坏封闭契约（ADR-001 §1）。未来如需网关侧镜像房间状态，记 `EXT-ROOM-STATE-001`（固件协同，不实现）。
4. **改名/换房/删除的边界**（C-006，见 Decision 2）：全部本地动作，不下行网关。

### 1.3 Consequences

**正**：房间生命周期（创建/重命名/删除保护）完全在 App 内闭环，零协议风险；与 FR-ROOM-002 的"仅 `roomId` 索引"一致；网关固件无需变更。
**负**：网关侧无从得知房间归属（多 App/多成员场景下房间结构不跨设备同步——与 ADR-003 §5.2 第 5 条的收敛边界一致）；`roomName` 提示在设备物理迁移后可能过时（仅影响首次导入建议）。

### 1.4 Alternatives

- **A1 扩展协议用 `roomId`**：否决——需要固件协同、破坏封闭 schema，且无 FR 要求网关理解房间。
- **A2 以网关 `roomName` 为权威、App 只做映射**：否决——违反 FR-ROOM-002（重命名零风险/仅本地）、无法表达未分配池与保护性禁用（C-015）。
- **A3 双层（本地权威 + 网关镜像）**：v1 否决（镜像需要协议扩展与双向冲突解决）；记为 EXT-ROOM-STATE-001。
- **A4 房间仅名称标识（去 roomId）**：否决——违反 L82/L140 的 ID 不变原则与已有数据模型。

### 1.5 References

`Data_and_State_Models.md` L63-74/L107-116；`discover-response.schema.json` L52-57/L73-95/L168；`YaoCore_HarmonyOS_App_Requirements.md` L77-95/L101-102；`UI_UX_Specification.md` L111-147；`WP3` §2.1-C005；`WP2` §4。

---

## 2. Decision 2：设置类动作的定位（C-006）与未分配/禁用态（C-015）

### 2.1 `SET_DEVICE_NAME` / `SET_DEVICE_ROOM` = App 本地动作，不得伪装为网关能力

**Context**：`Data_and_State_Models.md` L102-103 把两者列入 `DeviceAction` 枚举；`local-control-request.schema.json` L37-40 的 `action` 为**开放正则**（可携带任意大写动作）；但网关↔模块命令枚举**封闭**且不含二者（`module-command.schema.json` L12），网关路由（`网关接口协议.md` L34-42 能力表）亦无此二动作。

**Decision**：

1. `SET_DEVICE_NAME` / `SET_DEVICE_ROOM` 定位为 **App 领域命令**（本地数据操作），**不是网关能力**：
   - App 内部可以有对应的本地 command，但**禁止**经 `POST /control` 或云命令下发；
   - 若被下发：网关会以 `1006 unsupported_command` 拒绝（统一表，ADR-001 §2.2），属实现缺陷；
   - 契约测试需包含"本地改名/换房不产生任何 LAN/云请求"的断言（归 wp-005 测试计划）。
2. 设备显示名以**本地 `deviceName` 为准**（FR-ROOM-006）；网关侧 `deviceName` 只作首次导入提示（与 `roomName` 同规则，Decision 1.2）。
3. **设备删除（FR-ROOM-005）**：本地删除该设备的家庭记录与索引；为避免下次 `discover` 立即"复活"，本地维护 **`dismissedDeviceIds`（按 `gatewayId` 作用域）**：
   - discover 中出现已 dismissed 的 `deviceId` → 不自动重新纳管，仅在"未纳管/已移除"入口提供"重新添加"；
   - 设备重置/换绑（`deviceId` 变化）→ 视为新设备正常纳管；
   - 清理策略（保留时长）由 DES-001 定，默认永久保留至用户显式恢复。
4. **未分配/禁用态（C-015）在 v1 为本地状态机**（协议无表达，Decision 1.3）：

| 本地维度 | 取值 | 来源 | 协议关系 |
|---|---|---|---|
| `assignment` | `ASSIGNED(roomId)` / `UNASSIGNED` | 本地 | 无关（`roomName` 仅导入建议） |
| `enabled` | `true` / `false` | 本地（房间删除→保护性禁用；重新指派→启用） | 无关 |
| `online` | `true`/`false` | **网关真值**（discover/ACK） | 直接映射 |

   - 房间删除：`roomId=""`、`isUnassigned=true`、`isEnabled=false`（数据模型 L165-179；UIUX L126-147）；设备入"未分配设备池"；控制入口禁用；
   - 重新指派：`isUnassigned=false`、`isEnabled=true`（数据模型 L153-164）；
   - **`online` 与禁用正交**：禁用设备仍可收到网关状态（只读展示"在线/离线"），但不可控制——避免用户误以为"设备坏了"。
5. **discover 同步仲裁规则（合并规则全表）**：

| 场景 | 规则 |
|---|---|
| 已知设备再次出现，字段冲突（如 `deviceName/roomName`） | 本地字段不变（提示仅首次导入使用）；网关状态字段（`online/power/...`）按时间新鲜度仲裁（`updatedAt` + App 内 `stateEpochMs` 单调丢弃陈旧，数据模型 L147-148；归档实现同款策略 `DeviceRepository.ets` L596-603） |
| `roomName` 缺失/空串（违反 schema `minLength:1`） | 视为"无提示"，**不**因提示字段导致整体发现失败；记录 `protocolDeviation`（宽容策略，ADR-001 §1.2-3） |
| 设备在网关被移除（不再出现在 discover） | 本地保留记录并标记"网关已移除"（不自动删除用户数据）；用户可显式删除 → dismissed |
| 同 `deviceId` 出现在不同 `gatewayId` | 两个独立设备（两级标识，ADR-001 §5）；本地键为复合键 |
| 状态字段缺失（如 light 无 `power`） | 保留旧值并标"部分状态"；不得以缺字段推断状态变化 |
| `online=false` | 保留最后已知状态字段，`online` 置 false；UI 显示离线（不清空亮度等） |

### 2.2 Consequences

**正**：能力边界清晰——"本地改名换房"与"网关控制"从命令层分离，杜绝 1006 类实现缺陷；未分配/禁用态完整落在本地状态机，与 FR-ROOM-003/004 一一对应；仲裁表消除发现同步的二义。
**负**：dismissed 机制与"网络已移除"标记是新增本地状态（DES-001 需定义存储与 UI）；若未来固件要镜像房间/禁用状态，需要 `EXT-ROOM-STATE-001`。

### 2.3 Alternatives

- **B1 把 SET_DEVICE_NAME/ROOM 实现为网关命令**：否决——`module-command.schema.json` L12 封闭枚举无此二项；网关无处理器；会造成不可达能力。
- **B2 删除设备同时从网关删除**：否决——违反 FR-ROOM-005（房间无感、仅清理本地）与物理设备不可被 App 删除的事实。
- **B3 未分配态用 `roomId=""` 单字段表达**：部分采纳（数据模型 L115 既有），但补充 `isUnassigned/isEnabled` 双标志（数据模型 L119-120 既有），并与 `online` 正交。
- **B4 以网关 `roomName` 覆盖本地归属**：否决（违反 FR-ROOM-002 与用户预期）。

### 2.4 References

`Data_and_State_Models.md` L90-105/L107-149/L153-179/L180-188；`module-command.schema.json` L12；`local-control-request.schema.json` L37-40；`网关接口协议.md` L28-42；`YaoCore_HarmonyOS_App_Requirements.md` L83-95；`UI_UX_Specification.md` L126-147；`DeviceRepository.ets` L493-507/L596-603；`WP3` §2.1-C006/§2.3-C015；ADR-001 §1/§2/§5。

---

## 3. Decision 3：邀请码长度收敛为 6 位（C-009）

- 三方冲突：需求 L67（6~8 位字母数字）vs UIUX L90/L98/L106（6 位，示例 `7F3K9D`）vs 数据模型 L47（6~8 位）。
- **裁定**：v1 固定 **6 位**，字母表 = Crockford Base32 去歧义集合（排除 `I/L/O/U`），输入归一化、显示大写；码空间与安全边界、弱模式约束见 **ADR-003 §4.2**。
- 需求/数据模型的"6~8 位"记入勘误与补丁提案（`contract-baseline.md` §5 勘误 E-06；补丁 P-09）。
- 依据：UIUX 为产品行为权威（`config/project.md` L66）；6 位示例贯穿邀请流程与倒计时 UI；拉长到 8 位并非安全性充分手段（30→40 bit），安全强度由 KEY_WRAP 路径承担（ADR-003 §4）。

---

## 4. Decision 4：Guest 时效模型（C-017）

- 现状：需求 L36-38/L67 要求访客具时效性；数据模型 `FamilyMember`（L32-41）无 `expiresAt`，`MemberStatus`（L26-30）无 `EXPIRED`；仅邀请凭据有 `expireAt`（L53），"接受后到时失效"的执行语义未定义。
- **裁定（模型增补见 ADR-003 §9.2）**：
  1. `FamilyMember.expiresAt?`（GUEST 必填，随邀请头写入）；`MemberStatus.EXPIRED` 为到期冻结态；
  2. 到期语义：本地冻结（不可控制、设备列表仅显示授权房间的只读信息或直接隐藏——由 UIUX 采纳后确定，v1 采用"冻结为只读可见"以避免用户误解设备消失");
  3. 续期：Admin 在成员面板延长 `expiresAt`（**策略性**，不改变密码学边界）或重新发放邀请；
  4. `expiresAt` 校验与时钟信任同 ADR-003 §5.2；
  5. 到期后自动轮换**不**默认执行（成本分析见 ADR-003 §6.2），提示 Admin。
- **重要边界（复述 ADR-003 §6.3）**：GUEST 的房间限制是 App 策略，不是密码学边界；UI 与评审必须引用该声明。
- 依据：`WP3` §2.3-C017；需求 L36-38/L66-69；数据模型 L26-41/L46-56。

---

## 5. Decision 5：手动 IP 定位兜底与身份强校验（C-012）

### 5.1 Context

- 归档实现具备手动 IP/端口输入（`SettingsPage.ets` L545-560、L1053、L1253）与硬编码默认 `192.168.1.88`（`DeviceConstants.ets` L22）；
- 绑定安全规则明确：BLE 名称/MAC 后缀/UDP 只作定位，**不作身份证据**；绑定要求 discover `gatewayId` === Security1 读取值（`BLE配网设计.md` L143；README L48-53）；
- UIUX/架构未描述手动 IP 入口（`UI_UX_Specification.md` L70 的设置页清单无网络项）→ 语料不足以推定产品形态。

### 5.2 Decision（安全规则 + 产品形态分开处置）

**安全规则（裁定）**：

1. 手动地址（IP/端口）在 v1 仅是**定位手段**，与 UDP/mDNS/BLE 名称同类；
2. 使用手动地址的前提：该家庭**已绑定**该 `gatewayId`（存在路由记录）；手动入口**不得创建新绑定**；
3. 校验流程（全部通过才接受）：`GET /discover`（按该记录的通道档案：HTTP+HMAC 或 HTTPS+pin，ADR-002 §6）→ 响应验签 → `gatewayId` **精确相等**于记录 → 才更新路由 `localIp/port`；
4. 失败处理：不猜测、不切换到其他发现结果，提示"该地址不是已绑定的网关"；
5. **移除**硬编码默认 IP：改用"上次已知地址"，手动输入为高级入口（默认折叠）。
6. 绑定过程本身（首次）**禁止**经手动 IP 完成（必须 BLE 配网链路，README L48-53）。

**产品形态（需澄清）**：手动 IP 入口是否保留在 UI → `## ORCHESTRATOR_CLARIFICATION` Q1（推荐保留为"高级/诊断"入口并施加上述规则）。

### 5.3 References

`SettingsPage.ets` L545-560/L1053/L1253；`DeviceConstants.ets` L22；`BLE配网设计.md` L143；README L48-53；`UI_UX_Specification.md` L70；ADR-002 §6；`WP3` §2.1-C012/§5-P2-16。

---

## 6. Decision 6：门锁-门磁确认与超时报警的 App 侧语义（C-024）

### 6.1 Context

- 需求 L121-122（FR-DEV-003）："只有门磁传感器到位回传确认才显示已锁好，未到位超时触发警报"；
- 协议：门锁只暴露 `open` 布尔（`discover-response.schema.json` L109-111；`local-control-ack.schema.json` L90-92；`网关接口协议.md` L36）；门磁是**可选**硬件输入，可经网关并入门状态或作为独立实体（`网关接口协议.md` L24/L46）；无"门锁-门磁关联"协议字段；
- 超时参考：门磁/空调下位机的可配置执行超时最高 10 秒（`LocalGatewayService.ets` L323-325）；App ACK 超时 3000ms（UIUX L248）；
- UIUX 仅定义通用三态回弹（L151-186）。

### 6.2 Decision（App 侧语义，零协议扩展）

1. **锁闭流程（CLOSE）四阶段**：
   1. `PENDING`：发出 `CLOSE`（UIUX 三态）；
   2. **网关确认**：ACK `result_code==0` + 响应验签 + `reported_state.open==false` → 进入"等待门磁到位"；
   3. **门磁到位确认**：若存在**已关联**的就位传感器（见 6.2-2），等待其上报 `open==false`（或网关上报的门磁确认状态）→ 判定 **SECURED（已锁好）**；
   4. **超时分支**：超过 `T_doorConfirm`（默认 **10s**，与固件执行超时上限一致，可配置）未收到到位确认：
      - 若传感器在线 → 状态 = **UNCONFIRMED（未确认到位）**：琥珀色警示 + 记录事件 + 触发 **App 侧警报**（应用内显著提示 + 可选系统通知；v1 **不**联动声光报警器——无该能力）；
      - 若传感器离线 → 状态 = **UNKNOWN（无法确认）**：明确提示门磁离线，不得显示"已锁好"。
2. **关联规则（本地）**：同一 `gatewayId` 下的门锁设备 ↔ 门磁设备建立本地关联（`doorLockId → contactSensorId`）：
   - 默认无关联；提供"选择门磁"入口；若网关把门磁并入门的 `open` 状态（固件层面），则该网关下无需独立关联，ACK `open==false` 直接视为到位确认（由用户在关联页选择"网关已并入门磁"模式）；
   - 关联关系仅本地存储，不进入协议。
3. **开锁流程（OPEN）**：按 FR-DEV-001 单次 ACK 确认（`open==true`），不做门磁等待（开门后门磁状态由用户动作决定）。
4. **文案纪律（防虚报）**：未见门磁确认时，UI 文案必须是"已执行/未确认到位"，**禁止**使用"已锁好"（需求 L122 的语义即"到位确认才显示已锁好"）。
5. **超时/警报的语义边界**：`UNCONFIRMED` 是"未收到物理确认"，不等于"门未锁"（可能门磁故障/离线）；警报文案必须如实（`door.unconfirmed_alert` 等键位，见 `i18n-resource-design.md`）。

### 6.3 Consequences

**正**：把"已锁好"的显示条件严格对齐需求；不依赖任何协议扩展；超时与离线两种情况区分明确，消除"假成功"。
**负**：依赖用户配置关联（默认无关联时只能显示"网关确认，未验证到位"）；门磁并网/独立的两种固件形态需要用户选择一次；10s 等待期增加交互延迟（可配置）。

### 6.4 Alternatives

- **C1 协议扩展（门磁-门锁关联/到位字段）**：v1 否决——需要固件协同与 schema 变更；本地关联已可满足 FR。
- **C2 仅凭 ACK 显示"已锁好"**：否决——直接违反需求 L122 与"真实状态"原则（`config/project.md` L50）。
- **C3 超时即判定"未锁"**：否决——语义错误（传感器离线/故障不等于门未锁）；应为 UNCONFIRMED/UNKNOWN。
- **C4 联动声光报警外设**：v1 无此能力（协议无对应动作），记为未来能力需求（需固件/设备支持）。

### 6.5 References

`YaoCore_HarmonyOS_App_Requirements.md` L121-122；`discover-response.schema.json` L109-111；`local-control-ack.schema.json` L90-92；`网关接口协议.md` L24/L36/L46；`EXTERNAL_MODULE_PROTOCOL.md` L153；`UI_UX_Specification.md` L151-186/L247-248；`LocalGatewayService.ets` L323-325；`WP3` §2.3-C024。

---

## 7. Decision 7：DEV-ONLY 拒收约束落位（C-026）与语言入口（C-018）

### 7.1 DEV-ONLY（C-026）

- **条款来源**：正式 App 拒绝带 `X-YaoCore-Simulator: DEV-ONLY` 的开发桩响应（`网关接口协议.md` L11）；DEV 标记不得进入生产构建（README L224-226）；归档实现已有拒收逻辑（`LocalGatewayService.ets` L500-507 定义、L328-329 控制路径用法、L229-237 发现路径用法）。
- **裁定（落位方式，不改需求文件）**：作为**安全约束 SC-11** 与**实现强制项**写入 `project-constraints.md`（Must/Forbidden 清单），成为评审检查项；同时在 `contract-baseline.md` §8 记入 v1 行为声明：
  1. 生产构建的 LAN 客户端**必须**检查响应标记：`X-YaoCore-Simulator: DEV-ONLY`（大小写不敏感）与 `/health` 的 `DEV_SIMULATOR_ONLY`；命中 → 拒绝该响应用于任何绑定/控制/状态更新，提示"检测到开发模拟器，已拒绝"；
  2. Mock/仿真器仅允许出现在开发/测试构建与 TEST-001 明确的测试配置中；生产构建不得提供打开该开关的用户入口；
  3. 该约束**不**依赖云端或固件；
  4. 若未来需要"开发者模式"（明确、非默认、带警示的旁路），需另立 ADR（v1 不提供）。
- 依据：`WP3` §2.3-C026；`网关接口协议.md` L11；README L224-226；`LocalGatewayService.ets` L500-507（拒收判定）。

### 7.2 语言入口（C-018）

- **缺口**：需求 L139（zh-CN/en-US 切换）与架构 L56（SettingsPage 含"多语言"）要求语言入口，但 UIUX 的 Settings 页清单（L70）未包含。
- **裁定**：Settings 页必须包含语言入口（跟随系统 / 简体中文 / English），并即时生效（无需重启）；实现细节（控件形态、位置）以 wp-006 与 UIUX 修订提案为准；i18n 资源、键位、fallback 与防硬编码门禁见 `i18n-resource-design.md`。
- **UIUX 修订提案（不直接改 `input/`）**：在 `UI_UX_Specification.md` L70 的"系统设置"清单中加入"语言与地区（跟随系统/简体中文/English）"（补丁 P-10）。

---

## 8. 关联裁定索引（供契约基线与评审引用）

| 议题 | 本 ADR 裁定 | 相关文档 |
|---|---|---|
| 房间/网关边界（C-005） | §1：本地实体 + `roomName` 提示 | `contract-baseline.md` §2/§6 |
| 改名/换房/删除（C-006） | §2.1：本地动作，不下行 | `contract-baseline.md` §8.1 |
| 未分配/禁用（C-015） | §2.1-4/2.5：本地状态机 + 仲裁表 | `contract-baseline.md` §6.4 |
| 邀请码长度（C-009） | §3：6 位 CAC 字母表 | ADR-003 §4.2；勘误 E-06 |
| Guest 时效（C-017） | §4：`expiresAt`/`EXPIRED` | ADR-003 §9.2 |
| 手动 IP（C-012） | §5：定位非身份；强校验 | `contract-baseline.md` §8.4；Clarification Q1 |
| 门锁-门磁（C-024） | §6：四阶段 + 关联 + 报警 | `i18n-resource-design.md`；DES-001 |
| DEV-ONLY（C-026） | §7.1：安全约束 SC-11 | `project-constraints.md` §2 |
| 语言入口（C-018） | §7.2：Settings 必须包含 | `i18n-resource-design.md`；补丁 P-10 |
| 设备类型范围（C-021/C-022） | `contract-baseline.md` §6.2（因涉及状态字段缺口的统一处置） | ADR-001 §1；`contract-baseline.md` §9 |

## 9. 补丁提案（Patch Proposals — 不直接修改 `input/`）

| # | 目标 | 位置 | 改动 | 关联 |
|---|---|---|---|---|
| P-09 | `YaoCore_HarmonyOS_App_Requirements.md` L67；`Data_and_State_Models.md` L47 | 邀请码 6~8 位 | 收敛为"6 位（Crockford Base32 去歧义字母表）" | C-009 / §3 |
| P-10 | `UI_UX_Specification.md` L70 | 设置页清单 | 增加"语言与地区"入口 | C-018 / §7.2 |
| P-11 | `Data_and_State_Models.md` L115-120 | `DeviceState` | 增补"复合键分解存储"注释（`gatewayId`/`deviceId` 分字段；复合串为派生显示键） | ADR-001 §5 / DATA-001 |
| P-12 | `Data_and_State_Models.md` L26-41/L46-56 | `FamilyMember`/`FamilyInvitation` | 按 ADR-003 §9 增补字段 | C-017 / ADR-003 |
| P-13 | `UI_UX_Specification.md` L151-186 | 门锁交互 | 增补"等待门磁到位确认 / 未确认到位 / 无法确认"三态与文案纪律 | C-024 / §6 |

## 10. References（总）

`YaoCore_HarmonyOS_App_Requirements.md` L36-38/L66-74/L77-95/L101-102/L117-126/L134-139；`Data_and_State_Models.md` L26-56/L63-188；`UI_UX_Specification.md` L62-70/L78-107/L111-147/L151-186/L247-248；`discover-response.schema.json` L52-95/L168；`local-control-ack.schema.json` L77-149；`local-control-request.schema.json` L30-57；`module-command.schema.json` L12；`网关接口协议.md` L11/L24/L28-46；`EXTERNAL_MODULE_PROTOCOL.md` L147-162；`BLE配网设计.md` L133-147；README L48-53/L224-226；`SettingsPage.ets` L545-560/L1053/L1253；`DeviceConstants.ets` L13-16/L20/L22；`LocalGatewayService.ets` L323-325/L500-507；`DeviceRepository.ets` L493-507/L596-603/L608；`WP2` §4/§6；`WP3` §2.1/§2.3/§5；ADR-001/ADR-002/ADR-003。

---

## ORCHESTRATOR_CLARIFICATION（需用户/产品决策）

**Q1（手动 IP 入口的产品形态，C-012）**：安全规则已裁定（§5.2：仅定位、不建绑定、强校验）。是否在 v1 UI 保留手动 IP/端口入口？

- **选项 A（推荐）**：保留，置于"高级/诊断"折叠区，仅对已绑定网关生效并施加 §5.2 全部规则；移除硬编码默认 IP。
- **选项 B**：v1 完全移除手动入口（仅自动发现 + BLE 重配更新地址），最简且无误用风险；代价是网络变更/多网段场景无法自救。
- **选项 C**：保留但在非管理员角色下隐藏。

**Q2（门锁到位确认的默认配置，C-024）**：`T_doorConfirm` 默认 10s；当门磁未关联时，锁闭流程止于"网关已确认（未验证到位）"。是否需要引导用户在门锁首次使用时**强制**完成门磁关联（无门磁则明确选择"无门磁"）？

- **选项 A（推荐）**：一次性的引导（可选跳过），跳过则记录"未验证到位"能力缺口并在详情页常驻提示。
- **选项 B**：强制关联/明示无门磁后才允许"锁好"语义的任何展示。

---

*ADR-004 结束。本地状态机/存储/类结构细节归 wp-006 DES-001；本 ADR 的裁定条目已按 §8 索引与契约基线互链。*
