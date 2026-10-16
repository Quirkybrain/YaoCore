# wp-003 跨工件一致性与实现就绪度验证报告

- **Producer**: agent:system-verifier
- **Task**: `wp-003-consistency`（task 分支 `task/wp-003-consistency`，父分支 `feat/yaocore-app`，base commit `6c75037255d508420d3c519eae78a3eab6d6c916`）
- **Handoff**: `state/handoffs/wp-003-consistency.json`（13 项冻结输入 SHA256 已逐一复验一致，见 §1.1）
- **Date**: 2026-10-17
- **Target Stage**: `implementation`；Project/Task Workflow: `STANDARD`；Execution: `GATED_AUTO`（`config/project.md` L17-19）
- **只读声明**: 本任务未修改 `input/`、业务代码、schema 或配置；唯一写入为本报告。结论仅对下列冻结修订成立。

> 状态词表（`docs/artifact-model.md`）：`MISSING` / `PARTIAL` / `UNVERIFIED` / `VALID` / `STALE` / `INVALID`。本报告不授予任何工件 `VALID`；不确定项标注 `UNVERIFIED`，推断标注 `（INFERRED）`。

---

## 0. 结论摘要（供 Stage Gate 消费）

### 0.1 分面结论

| 验证面 | 结论 | 依据 |
|---|---|---|
| 协议数据面自洽（PROTO-001/002/003 机器可读部分） | **PASS（整合 wp-002，未复算）**：66/66 硬检查、仿真器实跑、向量复算一致 | `WP2` §0/§3.2/§5 |
| 文档间一致性（REQ↔ARCH↔API↔PROTO↔DATA↔UIUX） | **FAIL（存在可复现的互斥示例与语义冲突）**：规范示例自身违反 schema；`result_code` 双语义；身份端点三方差 | `WP2` F-01/F-02/F-03；本报告 C-016/C-022/C-025 |
| 需求→设计覆盖（26 项 FR） | **PARTIAL**：覆盖 11 / 部分 14 / 缺口 1（FR-FAM-004） | §3 |
| D-007 可实现性（HMAC+HTTPS/指纹固定） | **BLOCKED**：HMAC 侧证据充分；证书指纹下发/固定契约缺失（C-019、§4.1） | §4.1 |
| D-008 可实现性（离线加密凭据） | **BLOCKED**：方向已决，机制无承载（C-020、§4.2） | §4.2 |
| 实现启动就绪度（Target Stage 入口） | **BLOCKED**：6 项 P0 闭环清单未完成（§5） | §5 |
| wp-004 证据输入充分性 | **PASS**：裁定所需的一手证据（可运行反证、字段级对照、缺口清单）已齐备 | §2/§4/§7 |

**系统验证推荐**: 对"声明设计语料基线已 VALID 并启动组件实现"→ **BLOCKED（不通过）**；对"以本报告为证据进入 wp-004 契约裁定/ADR"→ **PASS**。实现阶段不得在 P0 清单（§5）闭环前启动受影响模块的冻结实现。

### 0.2 复核与新增计数

- **C-001..C-014 复核**：已闭合/降级 3（C-002→D-007、C-011→D-008、C-004）；部分缓解 1（C-007）；仍开放/需裁定 10（C-001、C-003、C-005、C-006、C-008、C-009、C-010、C-012、C-013、C-014）。
- **WP2-F01..F07 复核**：已闭合（环境）1（F05）；记录性 1（F07）；仍开放 5（F01、F02、F03、F04、F06）。
- **新发现 12 项（C-015..C-026）**：按严重度——阻塞 2（C-019、C-020）；高 1（C-015）；中-高 1（C-021）；中 3（C-017、C-023、C-024）；低-中 1（C-016）；低 4（C-018、C-022、C-025、C-026）。

### 0.3 当前修订下"可用于实现输入"的工件

| 工件（候选 ID） | 当前修订 | 可用条件 |
|---|---|---|
| PROTO-001（LAN/云 v2：schema+README+向量） | 冻结输入 @pin | 可用于 canonical/HMAC/重放/ACK 解析的**原型与单测**（`WP2` §7.2）；冻结前须完成 C-001/WP2-F02 裁定与错误语义统一 |
| PROTO-002（BLE 配网：identity schema+BLE 规范） | 冻结输入 @pin | Security1 流程与向量可直接实现；身份字段以 schema+归档 App 证据为准（WP2-F03 待正式修订） |
| DATA-001（数据模型） | 冻结输入 @pin | Family/Room/Device/Scene 核心实体可用；C-005/C-015/C-017 解决前不得冻结房间-网关映射与访客时效实现 |
| UIUX-001（UI/UX 规范） | 冻结输入 @pin | 页面流/状态机/动效 token 可用；设置页语言入口待补（C-018） |
| REQ-001（PRD） | 冻结输入 @pin | 功能基线与验收标准可用；FR-DEV-003/004、FR-FAM-004 待补设计（§3） |
| STD-001（ArkTS 规范） | 冻结输入 @pin | 待归一化为带引用 Project Constraints（`INV` §5） |
| LEGACY-001（原应用代码） | 冻结输入 @pin | 行为参考/移植来源；**非权威**，与 schema 冲突时以后者为准（`WP2` §4） |

**必须补全（阻塞实现启动）**：D-007/D-008 的 ADR 契约（C-019/C-020）、C-001 裁定+字段映射表、WP2-F02 错误语义、C-005/C-006/C-015 家庭-房间-网关边界、DES-001 详细设计/组件契约（§5 P0）。

---

## 1. 方法与范围

### 1.1 引用工件（路径 + pin 哈希，全部复验一致）

| 别名 | 路径 | SHA256（handoff pin，已复验） |
|---|---|---|
| CFG | `config/project.md` | `eeb2a76e3b1b422ae9f10fd4383b569a7340f3806c62cf45f1a46a347591dea5` |
| INV | `artifacts/00-project-intake/inventory.md` | `78836e26a16b5900b29c5e0c3d5f2fcd6327701a9f51a9b84468e2dac597c067` |
| WP2 | `artifacts/10-verification/wp-002-protocol-fixture-validation.md` | `2bc6e130129ffb4798a3226edd52ad988540681f1bdc82c8a1ff8469b2fddab1` |
| RT | `input/requirements/YaoCore_HarmonyOS_App_Requirements.md` | `b06f7370ac74d52839847c157b9ff61c6a32898d89cff8521242540b9966c1f9` |
| AR | `input/architecture/App_System_Architecture.md` | `6ef5f980b29e57d765bb25ed006bee358b4fd46c128b779fea0f52c156d0898f` |
| UX | `input/design/UI_UX_Specification.md` | `11bd1399240ca6c75124135951e35c0f6389865d84c0fe5b7ca0239e07de4322` |
| API | `input/api/Gateway_API_Specification.md` | `b8961ead830bb73bd487b17fc6f0822ca70946e6508f5a9aec63e68ad71422d9` |
| PR | `input/api/protocol/README.md` | `7aa10fadf9cdff0bb5b39901999119e7739178bbf653463b612158db95f74213` |
| DM | `input/data/Data_and_State_Models.md` | `3d4817b1443c37aaa6923365f81f5fa6c6c8677fad49f7f9d050d2ee6142c116` |
| STD | `input/standards/ArkTS_Coding_Standards.md` | `b7db54a3c2435b450f01492a6ba7d232cc1aef902bd3b6157d40e208330d3674` |
| BLE | `input/existing/docs/BLE配网设计.md` | `d466c5bad4a5a04fd727cef347ba56cb528403039072cd3e02227af22b10763b` |
| GWO | `input/existing/docs/网关接口协议.md` | `d7a34bb01f7ef43ea928e21988ae83bd605ecd46be4070da59ca1cf83152dbc9` |
| EXT | `input/existing/docs/EXTERNAL_MODULE_PROTOCOL.md` | `cb5ffbbbfe89890af61c99a87cdc4a05cdf85a8a9e79edeb64d66d9ce207ce79` |

协议 schema/向量（同目录，均属 AS-007..AS-023 冻结资产）：下文用 `DR`=`discover-response.schema.json`、`CR`=`local-control-request.schema.json`、`CA`=`local-control-ack.schema.json`、`SR`=`state-report.schema.json`、`CC`=`cloud-command.schema.json`、`IR/IE`=`ble-enrollment-identity-request/response.schema.json`、`MR/MS/MH/MC/MA`=`module-register/state/heartbeat/command/command-ack.schema.json`、`HV/RV/DV/MV`=四份测试向量 JSON。

### 1.2 辅助证据（非冻结输入，仅作旁证）

- 归档原应用代码 `input/existing/original_app/**`（LEGACY-001，AS-032..AS-039）。
- 旧文档 `input/existing/docs/隐私与本地配置.md`（PRIV）、`YaoCore用户使用手册.md`（MAN）。
- 仓库脚手架（`build-profile.json5`、`entry/src/main/module.json5`，AS-042/AS-046）。
- wp-002 适配副本与实跑证据 `artifacts/10-verification/fixtures/**`（workspace 证据，非冻结输入；本报告只引用不改动）。

### 1.3 方法

1. 逐行交叉审读 13 项冻结输入 + wp-001/wp-002 报告；以"文件+行"为准记录矛盾点。
2. **不重复** wp-002 已完成的协议数据面复算；直接整合其 66/66 自洽结论与 F-01..F-07 发现。
3. 对 21 项既有发现（C-001..C-014、WP2-F01..F07）逐项复核**现状态**（已闭合/仍开放/需裁定/已降级），并主动扫描**新冲突**（C-015 起）。
4. 对全部 26 项 FR 与 NFR 4.1/4.2/4.3 做设计支撑映射（架构/数据/协议/UI/错误语义五维），标注覆盖/部分/缺口。
5. 对 D-007/D-008 做可实现性核查：仅列可依据条款与缺口，不重新质疑方向、不做裁定。
6. 限制：未运行 JSON Schema 校验器（schema 审读为结构性检查）；未执行构建/测试/硬件；原应用代码仅深读与本报告结论直接相关的文件（AuthService/SecurityService/LocalGatewayService/SecureStorageService/DeviceConstants/GreeAcAdapter/SettingsPage 局部等），其余沿用 wp-001 的抽样声明。

### 1.4 覆盖限制与未覆盖项

- 未覆盖：`origin` 远端历史；框架方法论文档全文；UI 视觉验收；真实硬件/网络行为；云端 IoTDA 实网；时序与性能实测。
- "复核已知冲突"（§2.1/§2.2）与"新发现"（§2.3）分开陈述；所有新发现均给编号与证据，供 wp-004 分流。
- 对 wp-002 未运行项（BLE 23 方法、external module 6 项、gateway 2 项）不折算为 PASS（`WP2` §8）。

---

## 2. 一致性矩阵

### 2.1 既有冲突 C-001..C-014 现状态复核

| ID | 现状态 | 复核要点与新证据 | 影响面 |
|---|---|---|---|
| C-001 字段命名 | **仍开放（需裁定；证据已强化）** | `WP2` §4 四方可运行证据（schema+仿真器实跑+契约测试+归档 App 解析器）一致使用 `online/power/open/targetTemp`；规范示例 `isOnline/powerStatus/success` 自身违反 schema（另见 WP2-F01，本次补充：ACK 示例还缺 required `server_time`，`CA` L6 vs `API` L189-204） | 数据/协议/UI |
| C-002 LAN 加密模式 | **已闭合（用户已决 D-007）→ 转化为实现缺口 C-019** | GCM 信封（`DM` §3 L196-217、`API` L146-166）与 v2 schema（`CR` L23 const 2001、L90 closed）仍不兼容，D-007 已将其记为扩展提案；证书指纹固定语料缺口见 C-019 | 安全/协议 |
| C-003 版本/平台过时 | **仍开放（需裁定适用范围）** | `BLE` L151（"当前 target API 22"）、L104-114（ESP-IDF 5.2 protobuf 文件清单）vs `CFG` L32/L42（API 14+、targetSdk 26.0.0）；需产出"旧版本面适用性映射" | 流程/实现 |
| C-004 Demo 名实不符 | **已闭合（解释性降级）** | `CFG` L66、`RT` L16、`UX` L4-5 三重定位声明；`INV` §8.3 无需补救 | UI（无动作） |
| C-005 房间-协议不匹配 | **仍开放（需裁定）；扩展出 C-015** | `DM` L65-74（roomId UUID）vs `DR` L91-95（roomName 字符串，必填）vs `MR` L18/L22（room 字符串）；未分配/禁用态表达缺失见 C-015 | 数据/协议/UI |
| C-006 契约能力缺口 | **仍开放（需裁定）** | `DM` L102-103（`SET_DEVICE_NAME/SET_DEVICE_ROOM`）vs `MC` L12（封闭枚举不含二者）vs `CR` L37-40（action 开放正则）；改名/换房是否下行未定义 | 协议/数据 |
| C-007 工具不可运行 | **部分缓解** | `WP2` §2 完成 6 工具适配并实跑（gateway 15/17、app_response_auth 6/6、ble 向量 5/5、external_module 2/8、crosscheck 66/66）；剩余：`cloud/iotda/product-profile.json` 缺失（WP2-F04）、依赖网关 C 源码的用例不可移植 | 测试/流程 |
| C-008 重复资产 | **仍开放（低）** | `GWO` vs `API` 覆盖重叠；`EXT` vs 6 个 module schema（wp-002 D 段证实一致）。权威顺序建议候选：机器契约（schema/README）优先 | 流程 |
| C-009 邀请码长度 | **仍开放（需裁定；低）** | `RT` L67（6~8 位）vs `UX` L90/L98/L106（6 位）vs `DM` L47（6~8 位） | UI/数据 |
| C-010 标识格式 | **仍开放（需裁定；中）** | `DM` L109（`GW-9A216D:LIGHT_01`）vs `RT` L93（`GW-01:LIGHT-01`）vs `API` L98（`LIGHT_01`）vs `DR` L64-67（宽松 pattern）vs `SR` L37-45（固定属性名 `Door_01_Online` 等）vs 归档 `DeviceConstants` L12-17/L20 | 数据/协议 |
| C-011 成员密钥交付 | **已闭合（用户已决 D-008）→ 转化为实现缺口 C-020** | 方向已决（离线加密凭据）；机制承载缺口见 C-020/§4.2 | 安全/流程 |
| C-012 手动 IP 边界 | **仍开放（需裁定；低-中）** | 归档 `DeviceConstants` L22（硬编码 `192.168.1.88`）、`SettingsPage` L545-560（手动 IP/端口输入）vs `BLE` L143（"不按广播名、MAC 后缀或邻居发现顺序猜测身份"）；手动兜底的新规则未定义 | 数据/UI/安全 |
| C-013 版本新鲜度 | **仍开放（持续注记）** | 10 份主文档均无版本头；建议建立修订编号机制（wp-004/文档维护） | 流程 |
| C-014 未提供内容 | **仍开放（规划输入）** | `input/uml/tests/project/competitors/references/other` 为空；UML 与测试工件是否产出由规划决定 | 流程 |

### 2.2 WP2-F01..F07 现状态复核

| ID | 现状态 | 复核要点 | 影响面 |
|---|---|---|---|
| WP2-F01 示例违反 schema | **仍开放（需裁定+文档修订）** | `WP2` §6 F.15-F.18b；补充：ACK 示例缺 required `server_time`（`CA` L6 vs `API` L189-204） | 协议/文档 |
| WP2-F02 `result_code` 语义 | **仍开放（阻塞错误语义；须裁定）** | `API` L215-227 vs 仿真器编码（`WP2` §6 证据）；`CA` L16-20 无枚举，仅 0..9999 整数 | 协议/UI/测试 |
| WP2-F03 身份端点冲突 | **仍开放（须裁定）** | `IE` L12-25（`serviceId` const `YaoCoreGateway`、`gatewayName`）vs `API` L44-45（`SmartHomeService`、`displayName`）vs `PR` L37-41；归档 `BleProvisioningService` L652-656 支持 schema（`WP2` §6） | 协议/配网 |
| WP2-F04 `product-profile.json` 缺失 | **仍开放（资产缺口）** | 全仓库 0 命中，阻塞 2 个网关套件用例与 `SR` 子集校验（`WP2` §3.3-A） | 测试/云 |
| WP2-F05 沙箱代理 | **已闭合（环境；非产品缺陷）** | 根因链见 `WP2` §3.3-B；后续 Python 运行需 `no_proxy='*'` | 环境 |
| WP2-F06 校验边界差异 | **仍开放（低）** | `WP2` §5 末（target/request_id/action/mode 长度）；实现期对齐或声明宽容策略 | 协议/测试 |
| WP2-F07 BLE 用例覆盖限制 | **记录性（不折算 PASS）** | 身份 schema 等价断言独立复跑 5/5（`WP2` §3.3-D）；待资产齐备后重跑 | 测试 |

### 2.3 新发现（C-015 起）

> 每项均标注严重度与影响面；"决策-契约缺口"类为 D-007/D-008 已决方向下的实现缺口记录，**不重新质疑决策**。

| ID | 类别 | 描述 | 证据（文件+行） | 严重度 | 影响面 |
|---|---|---|---|---|---|
| **C-015** | 需求-协议缺口 | **"未分配/禁用"设备在网关协议中无表达**：discover device 必填 `roomName` 且 minLength≥1（空串不合法），device 对象封闭且无 `isUnassigned/isEnabled/disabled` 字段；而 PRD/数据模型/UI 要求设备可处于"未分配池 + 保护性禁用"，全部设备状态最终来自网关快照 | `DR` L74-81、L91-95、L82-167（无对应字段）；`DM` L119-120；`RT` L84-89；`UX` L126-147 | **高** | 数据/协议/UI |
| **C-016** | 枚举不一致 | **`stateSource` 取值集合三方不一致**：PRD 与数据模型列 4 值；协议 README 与 API 示例列/使用第 5 值 `device.feedback`（归档 App UI 有对应标签）；机器 schema 仅约束长度 ≤31，不约束枚举 | `RT` L126（4 值）；`DM` L144（4 值）；`PR` L197-198（5 值）；`API` L106/L200（`device.feedback`）；`LEG` `DevicePage.ets` L2224（标签） | 低-中 | 协议/数据/UI |
| **C-017** | 需求-模型缺口 | **Guest 时效性未建模**：PRD 要求访客"具备时效性（如 24 小时或指定日期过期）"，但 `FamilyMember` 无 `expiresAt`、`MemberStatus` 无 `EXPIRED`；只有邀请凭据有 `expireAt`（接受后到时失效的执行语义未定义） | `RT` L36-38、L67；`DM` L26-30、L32-41、L53 | 中 | 数据/安全/流程 |
| **C-018** | 文档缺口（UI） | **UI 规范"系统设置"未列语言切换入口**：PRD 要求 zh-CN/en-US 切换，架构 SettingsPage 含"多语言"，UI 规范该页清单未包含 | `RT` L139；`AR` L56；`UX` L70 | 低 | UI/i18n |
| **C-019** | 决策-契约缺口（D-007） | **`certFingerprint` 无下发/固定契约承载**：架构规定在 `yaocore-id` 阶段经 Security1 会话传递证书 SHA-256 指纹，但身份响应 schema 封闭且无该字段、discover `security` 块封闭，任何协议 schema 均无指纹字段/格式/轮换/固定流程定义 | `AR` L135-137；`IE` L6-26（closed，4 字段）；`DR` L33-51（closed）；全语料 grep `certFingerprint` 仅命中 `AR` L136 与 `DM` L234 | **阻塞** | 安全/协议 |
| **C-020** | 决策-契约缺口（D-008） | **离线加密凭据无机制/模型承载**：架构声明邀请 Token 含 `encryptedKey` 并"向 Admin 设备或安全服务交换凭据"，但数据模型 `FamilyInvitation` 无任何密钥字段；凭据格式（二维码载荷）、密钥封装算法、校验主体（无服务器）、有效期/撤销/轮换均无定义；归档 App 无 family/invite 代码（grep 0）可参照 | `RT` L66-69；`AR` L111-113；`DM` L46-56；`UX` L89-99/L106 | **阻塞** | 安全/数据/流程 |
| **C-021** | 契约字段缺口 | **LAN 状态契约缺 `position/speed/volume`**：`DeviceType` 含 curtain/fan/speaker（schema 与数据模型均含），数据模型与模块协议定义 position/speed/volume，但 discover 设备对象与 ACK `deviceState` 封闭且无这三字段——这三类设备经 LAN 路径无法完成状态同步/ACK 校验 | `DR` L82-167、L97；`CA` L77-149；`DM` L134-136；`MS` L38-40 | 中-高 | 协议/数据/UI |
| **C-022** | 语义/单位冲突 | **风扇 `speed` 单位冲突**：数据模型"档位 1~5" vs 模块协议 percent 0~100（LAN 契约无 speed 字段，见 C-021） | `DM` L135；`MS` L39（percent 定义 L22）；`EXT` L159 | 低 | 数据/协议 |
| **C-023** | 契约缺口（云） | **App↔IoTDA 契约缺失**：仅定义网关侧命令信封（`CC`）与属性上报（`SR`）及散文描述；无 `CreateCommand` 请求/响应 schema、无设备影子查询契约、无 App 侧鉴权/Token 管理定义 | `API` L231-249；`PR` L164-181；`CC` L19-76；`SR` 全文 | 中 | 协议/云 |
| **C-024** | 需求-设计缺口 | **门锁-门磁联动确认语义未定义**：FR-DEV-003 要求"门磁到位回传确认才显示已锁好，未到位超时触发警报"，但协议门锁仅 `open` 状态，无门磁-门锁关联、就位判定、超时与报警语义 | `RT` L121-122；`GWO` L36；`EXT` L147/L153；`UX` L173-179（仅通用超时回弹） | 中 | 协议/UI/安全 |
| **C-025** | 枚举词表不一致 | **空调 `mode` 词表不一致**：数据模型注释 5 值；模块协议枚举 7 值（含 `ECO/SLEEP`）；LAN schema 仅限长度（开放）；归档格力适配器将"节能"归一化为 `ECO` | `DM` L133；`MS` L37；`DR` L139-142、`CA` L120-123；`LEG` `GreeAcAdapter.ets` L21 | 低 | 数据/协议 |
| **C-026** | 需求落位缺口 | **DEV-ONLY 拒绝约束未落位到 PRD/架构**：旧网关协议文档要求正式 App 拒绝 `X-YaoCore-Simulator: DEV-ONLY` 响应，协议 README 禁止其进入生产构建，但新 PRD/架构 FR/NFR 未收录该要求 | `GWO` L11；`PR` L224-226 | 低 | 安全/测试流程 |

---

## 3. FR 覆盖映射（26 项功能需求 + NFR 4.1/4.2/4.3）

> 状态定义：**覆盖** = 架构/数据/协议/UI/错误语义五维均有可执行设计支撑；**部分** = 主支撑存在但有明确缺口（标注编号）；**缺口** = 仅有需求文字，无设计支撑。
> 本表是"设计语料支撑度"，不等价于实现完成度；所有实现仍需 DES-001 详细设计（§5-P0）。

### 3.1 家庭与成员（FR-FAM）

| FR | 设计支撑 | 状态 | 缺口/备注 |
|---|---|---|---|
| FR-FAM-001 家庭创建与多家庭 | `DM` L7-24；`AR` L105-106；`UX` L82-105 | 覆盖 | familyId 本地生成/持久化切换归 DES-001；无冲突 |
| FR-FAM-002 成员邀请 | `DM` L46-56；`AR` L111-113；`UX` L89-99/L106；`RT` L66-69 | 部分 | **C-020**（凭据/密钥承载）、**C-009**（码长）、校验主体未定义 |
| FR-FAM-003 权限管理与移除 | `DM` L26-41；`UX` L92-93/L107 | 部分 | 成员"在线状态"无字段（`DM` L32-41）；移除后凭证失效机制缺（C-020） |
| FR-FAM-004 退出家庭 | `RT` L73-74（仅需求） | **缺口** | Admin 转让/解散无任何设计（数据/UI/流程） |

### 3.2 房间与设备（FR-ROOM）

| FR | 设计支撑 | 状态 | 缺口/备注 |
|---|---|---|---|
| FR-ROOM-001 房间创建/ID | `DM` L65-73；`UX` L113-120；`RT` L78-79 | 覆盖 | — |
| FR-ROOM-002 命名/ID 不变 | `DM` L181-188；`UX` L116-120/L140；`AR` L116-118 | 覆盖 | — |
| FR-ROOM-003 加入/换房 | `DM` L153-164；`UX` L122-124 | 部分 | 网关侧映射 C-005；未分配态 C-015 |
| FR-ROOM-004 房间删除保护 | `DM` L165-179；`UX` L126-147；`AR` L121-124 | 部分 | C-015（协议表达）；换房/改名是否下行网关 C-006 |
| FR-ROOM-005 设备删除 | `RT` L90-91（需求） | 部分 | 无设计级删除流程/数据函数（路由清理、场景引用、网关侧动作）；DES-001 补 |
| FR-ROOM-006 设备命名/ID 不变 | `DM` L180-188；`AR` L118 | 部分 | C-010（deviceId 形态）；C-006（SET_DEVICE_NAME 语义） |

### 3.3 首页看板（FR-HOME）

| FR | 设计支撑 | 状态 | 缺口/备注 |
|---|---|---|---|
| FR-HOME-001 家庭/网关状态 | `UX` L23；`DM` L224-236；`RT` L98-100 | 部分 | RTT 延迟测量与展示来源未定义（与 NFR 4.3 联动）；`secureTransport` 的 UI 状态映射未定义 |
| FR-HOME-002 房间快捷栏 | `UX` L62；`RT` L101-102；`DM` L70-71 | 覆盖 | — |
| FR-HOME-003 环境感知看板 | `DM` L138-148；`DR` L121-133；`PR` L191-206；`UX` L62 | 覆盖 | — |
| FR-HOME-004 快捷设备卡片 | `UX` L63/L105；`RT` L105-106；组件（`INV` AS-034） | 覆盖 | — |

### 3.4 配网（FR-GW）

| FR | 设计支撑 | 状态 | 缺口/备注 |
|---|---|---|---|
| FR-GW-001 蓝牙权限与扫描 | `BLE` §2 L21-45；`RT` L109-110；`CFG` L49 | 部分 | C-003（旧文档 API 22 权限面适用范围）；脚手架 `module.json5` 无权限声明（实现任务） |
| FR-GW-002 Security1 | `BLE` §4 L60-100；`AR` L94-97；`IR/IE`；向量（`WP2` 5/5） | 覆盖 | 身份字段修订见 WP2-F03 |
| FR-GW-003 Wi-Fi 下发与绑定 | `BLE` §5 L131-147；`PR` L48-53；`UX` L203-211/L249 | 覆盖 | 绑定三要素（HMAC 双向+gatewayId+LED）清晰 |

### 3.5 设备控制（FR-DEV）

| FR | 设计支撑 | 状态 | 缺口/备注 |
|---|---|---|---|
| FR-DEV-001 ACK 防乐观 | `RT` L117-118；`UX` L151-186（三态/3000ms）；`PR` L183-189；`CA` L49-62 | 覆盖 | 失败原因语义受 WP2-F02 影响（错误码统一前仅"0/非0"可用） |
| FR-DEV-002 灯光/55ms | `RT` L119-120；`UX` L190-195/L247-248；`DR` L112-120；`CR` | 覆盖 | — |
| FR-DEV-003 门锁/门磁 | `RT` L121-122；`GWO` L36；`EXT` L153 | 部分 | **C-024** |
| FR-DEV-004 空调多品牌 | `RT` L123-124；`AR` L85-88；`DM` L123/L133；`DR` L134-138；适配器（`INV` AS-032） | 部分 | **C-025**（mode 词表）；品牌枚举开放（`brand` 字符串） |
| FR-DEV-005 状态溯源 | `RT` L125-126；`PR` L191-206；`DM` L143-146；`DR` L151-155 | 部分 | **C-016**（取值集） |

### 3.6 场景（FR-SCN）与设置（FR-SET）

| FR | 设计支撑 | 状态 | 缺口/备注 |
|---|---|---|---|
| FR-SCN-001 场景编排与执行 | `DM` L244-259；`UX` L229-234；`AR` L76-77；`RT` L129-131 | 覆盖 | 执行语义（串行/局部失败不回滚）明确 |
| FR-SET-001 成员管理面板 | `RT` L134-135；`UX` L68 | 部分 | 同 FR-FAM-002/003/004 缺口 |
| FR-SET-002 加密与密钥配置 | `RT` L136-137；`AR` L128-137；`DM` L196-217/L232-234 | 部分 | **C-019**；密钥存储位置/作用域未定义（§4.1-G5） |
| FR-SET-003 云与 i18n | `RT` L138-139；`AR` L56/L96；`STD` L26-28；`CFG` L53 | 部分 | **C-023**（云契约）、**C-018**（语言入口）；I18N-001 资源包 MISSING |

### 3.7 NFR 工程可验证性

| NFR | 状态 | 分析 |
|---|---|---|
| 4.1 传输安全（HMAC+HTTPS/指纹；时钟/重放） | **部分可验证** | HMAC 全链（canonical/±120s/300s nonce/响应验签）规格完整且有 66/66 自洽与向量支撑（`PR` L55-157；`WP2`）；HTTPS/指纹固定无契约（C-019）；GCM 为扩展提案（D-007），`DM` §3 的报文模型与 v2 schema 不符（C-002 遗留） |
| 4.2 存储隐私 | **部分可验证** | PBKDF2|SHA256 120,000 需求（`RT` L152）与归档实现一致（`LEG` `AuthService.ets` L31/L194-202）；Wi-Fi 密码用后即清（`BLE` L155、`UX` L224）；邀请码过期（`DM` L53）但执行/撤销机制缺（C-020）；"系统级安全首选项"（`RT` L153）仅在归档中落到 Asset Store（`SecureStorageService.ets` L10-19），新语料未定义密钥存储规范——可验证性依赖 §5-P1 存储规范 |
| 4.3 性能 | **不可直接验证（需补测量口径）** | ACK p95≤500ms（`CFG` L52、`RT` L156）未定义测量点/样本/环境；55ms 节流有 token 与交互约束（`UX` L247）；60/120fps（`RT` L158）无测量方法。须在 TEST-001 中定义可执行口径（Mock 计时 harness 可选） |

**FR 覆盖统计**：覆盖 11 / 部分 14 / 缺口 1（共 26）。可用于实现输入的关键 FR：FR-GW-002/003、FR-DEV-001/002、FR-SCN-001、FR-HOME-002/003/004、FR-ROOM-001/002、FR-FAM-001 可直接进入详细设计；其余以 §5 闭环项为前置。

---

## 4. D-007 / D-008 可实现性核查（只列依据与缺口，不裁定）

### 4.1 D-007：HMAC 必做 + 本地 HTTPS/证书指纹固定

**可依据的条款（充分性：HMAC 侧高；HTTPS 侧低）**

| # | 可依据内容 | 证据 |
|---|---|---|
| 1 | 控制请求 canonical（10 行、无末尾换行、value 原子编码规则） | `PR` L55-87；`CR` L18-74；`HV` 4 向量（`WP2` 复算一致） |
| 2 | 时间窗 ±120s、nonce 300s 缓存、精确重传幂等、冲突 409/1005、失败不消耗 nonce | `PR` L89-103；`DR` L33-51（security const）；仿真器实跑（`WP2` §3.3-F） |
| 3 | 发现请求签名 + 响应验签（`YAOCORE-DISCOVER-V2`/`YAOCORE-RESPONSE-V1`、constant-time） | `PR` L109-157；`RV`/`DV`；`LEG` `SecurityService.ets` L94-135 |
| 4 | ACK 规则：`result_code==0` 才确认、`reported_state` 完整状态要求 | `PR` L183-189；`CA` L49-62；`GWO` L17-26 |
| 5 | 方向与字段占位：方案 B 陈述、`certFingerprint` 字段、`secureTransport/tlsEnabled` | `RT` L148；`AR` L135-137；`DM` L232-234；`CFG` L53 |

**缺口（G-D7）**

- **G-D7-1（阻塞）** 指纹下发无协议承载：身份响应 schema 封闭且无 `certFingerprint`（`IE` L6-26）；discover `security` 块封闭（`DR` L33-51）；无任何字段、版本迁移或备用端点定义（=C-019）。
- **G-D7-2** 指纹格式与证书体系未定义：SHA-256 指纹编码/大小写、自签名证书生成与有效期、多指纹（轮换/备用）、证书与 `gatewayId` 绑定关系。
- **G-D7-3** 固定与启用流程未定义：首次信任建立（何时获取、何时切 TLS）、HTTP→HTTPS 迁移与失败回退策略（明确禁止明文回退还是允许降级）、校验失败的用户语义（error taxonomy 联动 WP2-F02）。
- **G-D7-4** 服务端面未定义：TLS 端口/开关方式、与既有 9200 端口的共存策略；Mock/仿真器的 TLS 仿真形态（现仿真器仅 HTTP，`WP2` §7.3）。
- **G-D7-5** HMAC 密钥模型未定义：`key_id=app-key-v1` 与密钥材料解耦只写到"协调轮换"（`PR` L105-107）；"家庭控制密钥"（`RT` L69/L137）与每网关 `command_secret`（`EXT` L24、`PRIV` L37）的作用域/数量关系、多网关家庭、存储位置（Asset Store?）、轮换流程均未定义。
- **G-D7-6** 模型与决策不一致的表示方式：`DM` §3（`EncryptedPayloadEnvelope`、cmd_id 2002）需按 D-007 标注为扩展提案或拆分（C-002 遗留，建议 ADR 引用）。

### 4.2 D-008：离线加密凭据（邀请码/二维码携带密钥材料，无服务器依赖）

**可依据的条款（充分性：低——仅有方向与界面流程）**

| # | 可依据内容 | 证据 |
|---|---|---|
| 1 | 邀请凭据要素：邀请码、生效时限（默认 24h）、目标角色、可选授权房间、最大使用次数 | `RT` L66-69；`DM` L46-56 |
| 2 | 加密 Token 方向：本地生成含 `familyId/role/expireAt/encryptedKey`；"向 Admin 设备或安全服务交换凭据"；成员无需再走 BLE | `AR` L111-113；`RT` L69 |
| 3 | 界面流程：角色选择→6 位码/二维码→24h 倒计时→输入邀请码→"安全信道"交换→加入成功 | `UX` L89-102/L106 |
| 4 | 本地身份基础（可复用）：PBKDF2 本地档案、Asset Store 密钥存储 | `LEG` `AuthService.ets` L91-171；`SecureStorageService.ets` L17-42 |

**缺口（G-D8）**

- **G-D8-1（阻塞）** 凭据载荷格式未定义：二维码/邀请码字符串结构（版本、familyId、角色、expireAt、allowedRoomIds、密钥材料编码）无任何 schema/示例；`DM` 无字段承载（=C-020）。
- **G-D8-2** 密钥封装方案未定义：`encryptedKey` 的算法与密钥来源（接收方公钥？邀请码派生密钥？）；离线条件下 Admin 设备如何获得接收方可信公钥（先扫码回传公钥 or 预共享）；是否需要一次性对称密钥。
- **G-D8-3** 校验主体与离线语义未定义：`expireAt/maxUses/usedCount` 由谁校验（Admin 设备？网关？纯客户端解析）、无服务器/无在线交互时如何防重放/防超用；接收方时钟信任。
- **G-D8-4** 撤销与轮换未定义：成员移除后"控制令牌立即失效"（`RT` L72）在离线模型下的实现路径；网关 HMAC 密钥是否因成员移除而轮换、轮换成本（每网关一密钥时需逐网关更新）、被移除成员已持有密钥的失效边界。
- **G-D8-5** 与 D-007 的交叉缺口：成员手机不经 BLE 即无法按 `AR` L136 获取 `certFingerprint`——若启用 HTTPS pinning，指纹必须随邀请凭据一并安全分发；邀请凭据同时承载"家庭控制密钥 + 各网关指纹"的格式与版本管理未定义。
- **G-D8-6** 威胁模型未产出：邀请码泄露/拍照截获、二维码旁路、离线窗口期攻击、成员设备被接管等场景的安全假设与对策（`AR`/`RT` 均未提）。

### 4.3 交叉结论

- D-007 与 D-008 在"成员加入时如何获得网关信任材料（HMAC 密钥 + 证书指纹）"处强耦合；两个 ADR 需要共享同一"家庭信任材料分发"模型（§7-5/7-6 建议合一评审）。
- 两者均**不影响** FR-GW-002/003（配网路径）与 FR-DEV-001/002（控制/ACK 语义）的实现起步；影响 FR-SET-002、FR-FAM-002/003 与传输层加固。

---

## 5. 实现就绪度评估（实现启动前必须闭环，按阻塞程度排序）

| 优先级 | 依赖项 | 现状 | 为什么阻塞 | 需要的产出 |
|---|---|---|---|---|
| **P0-1** | C-001 字段命名裁定 + **线格式↔内部模型字段映射表** | 证据充分（`WP2` §4 四方可运行反证），未裁定 | DTO/序列化/契约测试若择错字段全链路不兼容 | wp-004 裁定记录 + 映射表工件（含时间戳、seq、request_id、"线格式权威=schema 家族"） |
| **P0-2** | WP2-F02 `result_code` 语义统一 + error 分类 | 两套语义互不兼容（`API` L215-227 vs 仿真器） | 防乐观回退、UI 提示、契约断言全部依赖错误语义 | 统一错误表（含 `error_code` 字符串、message 策略）；`CA` 是否加枚举 |
| **P0-3** | D-007 ADR：HTTPS/指纹固定契约 + HMAC 密钥作用域/存储 | 决策已定，契约缺失（C-019、G-D7-1..6） | 传输层（LocalGatewayService/CryptoService/SecurityService）与 FR-SET-002 无法冻结实现 | Q: 指纹载体（identity schema 扩展 or 其他）；TLS 启用/回退；密钥存储（Asset Store）与轮换 |
| **P0-4** | D-008 ADR：离线凭据机制 + `FamilyInvitation` 模型更新 | 决策已定，机制缺失（C-020、G-D8-1..6） | FAM/SET 模块与安全模型无法冻结 | 凭据格式规范、密钥封装、校验/撤销/轮换、威胁模型（含与 D-007 交叉） |
| **P0-5** | C-005/C-006/C-015 家庭-房间-网关边界裁定 | 三份语料互斥（roomId vs roomName；SET_* 动作缺口；未分配态无表达） | ROOM 模块、discover DTO、房间删除/换房流程无法实现 | 边界声明（本地实体 vs 协议扩展）+ 未分配态表达方式（含 schema 变更决策） |
| **P0-6** | DES-001 详细设计/组件契约（`INV` §3.2 MISSING） | 不存在 | 所有组件实现缺接口级契约 | `IGatewayClient/IBleProvisioningClient` 扩展（错误类型、超时）、控制三态状态机、配网状态机、场景步骤语义、依赖注入与 Mock 边界 |
| **P1-7** | WP2-F03 身份端点裁定 + 规范修订 | schema+归档 App 证据一致，规范示例为孤例 | 配网身份校验实现与文档不一致风险 | 修订 `API` L44-45 示例；明确两 `serviceId` 常量共存语义 |
| **P1-8** | C-021/C-022 状态字段与单位（position/speed/volume；speed 单位） | LAN 契约缺字段；单位冲突 | 窗帘/风扇/音箱类型状态同步不可实现；v1 范围含混 | 决定 v1 设备范围并据此扩展 schema 或声明降级 |
| **P1-9** | C-023 云端路径契约或明确延后 | 无 App 侧 IoTDA 契约 | FR-SET-003 云配置无法实现 | CreateCommand/影子/Token 契约 或 明确 v1 范围外 |
| **P1-10** | C-017/C-009 邀请与成员语义统一 | Guest 时效无模型；码长 6 vs 6~8 | FAM/SET 实现与 UI 校验规则 | 模型增补（expiresAt/EXPIRED 或声明）与码长裁定 |
| **P1-11** | I18N-001 资源包设计 + C-018 语言入口 | 资源包 MISSING；旧 615 条内联字典 | FR-SET-003、评审门禁（防硬编码） | 键空间/文件布局/fallback + 旧文案迁移边界 |
| **P1-12** | 存储与密钥管理规范（NFR 4.2） | 新语料未定义；仅归档 Asset Store 证据 | 敏感数据落位、密钥生命周期、隐私门禁 | Preferences/RDB/Asset Store 分工与密钥生命周期（并入 P0-3） |
| **P1-13** | TEST-001 测试计划 + NFR 4.3 测量定义 + MOCK-001 规范（含 TLS） | 均 MISSING；仿真器仅 HTTP | 门禁证据缺乏口径 | 测试分层、计时口径、Mock/TLS 仿真与移植计划（衔接 `WP2` §7） |
| **P2-14** | WP2-F01/F06 文档修订与边界对齐 | 开放（低） | 不阻塞实现，影响契约源清晰度 | 修订示例/边界宽容策略 |
| **P2-15** | WP2-F04 profile 补建或降级 | 开放（资产） | 影响 2 个测试用例与 `SR` 子集校验 | 补建 product-profile 或声明范围外 |
| **P2-16** | C-003/C-012/C-013/C-014/C-026 收尾 | 开放（低） | 流程/规划类 | 旧版本面映射、手动 IP 策略、版本头机制、UML 取舍、DEV-ONLY 落位 |

---

## 6. 追溯种子（REQ → ARCH/PROTO/DATA/UIUX 初始映射）

> 供后续双向 traceability 扩展；引用工件 ID（`INV` §2/§3）与章节锚点。状态 = 本报告 §3 覆盖状态。

| REQ（FR） | ARCH（AR/AS-003） | PROTO（AS-007..023） | DATA（AS-024） | UIUX（AS-004） | 状态 |
|---|---|---|---|---|---|
| FR-FAM-001 | §3.1 L105-106 | — | §1.1 L7-15 | §4.1 L82-105 | 覆盖 |
| FR-FAM-002 | §3.1 L111-113 | —（待 ADR 扩展） | §1.3 L46-56 | §4.1 L89-99/L106 | 部分 |
| FR-FAM-003 | §3.1 L107-110 | — | §1.2 L26-41 | §4.1 L92-93/L107 | 部分 |
| FR-FAM-004 | — | — | — | — | 缺口 |
| FR-ROOM-001 | §3.2 L116-118 | — | §2.1 L65-73 | §4.2 L113-120 | 覆盖 |
| FR-ROOM-002 | §3.2 L116-118 | — | §2.3 L181-188 | §4.2 L116-120/L140 | 覆盖 |
| FR-ROOM-003 | §3.2 L119-120 | C-005 待裁 | §2.3 L153-164 | §4.2 L122-124 | 部分 |
| FR-ROOM-004 | §3.2 L121-124 | C-015 待裁 | §2.3 L165-179 | §4.2 L126-147 | 部分 |
| FR-ROOM-005 | §3.2 L125-126 | — | —（DES 补） | —（DES 补） | 部分 |
| FR-ROOM-006 | §3.2 L118 | C-006/C-010 | §2.3 L180-188 | §4.2 L140 | 部分 |
| FR-HOME-001 | §2 L50 | DR（latency 无） | §4 L224-236 | §2.1 L23 | 部分 |
| FR-HOME-002 | §2 L50 | — | §2.1 L70-71 | §3 L62 | 覆盖 |
| FR-HOME-003 | §2 L50 | DR L121-133；PR L191-206 | §2.2 L138-148 | §3 L62 | 覆盖 |
| FR-HOME-004 | §2 L58 | CA deviceState | §2.2 L127-136 | §3 L63 | 覆盖 |
| FR-GW-001 | §5 L95 | BLE §2（AS-027） | — | §4.5 L199-206 | 部分 |
| FR-GW-002 | §4.1 L151-155 | IR/IE（AS-013/14）；BLE §4 | — | §4.5 L207 | 覆盖 |
| FR-GW-003 | §4.1 L145-148 | PR L48-53；BLE §5 | §4 L224-236 | §4.5 L209-211 | 覆盖 |
| FR-DEV-001 | §2 L64-68 | CA L49-62；PR L183-189 | §2.2 L107-149 | §4.3 L151-186 | 覆盖 |
| FR-DEV-002 | §2 L66 | CR payload L33-57；DR L112-120 | §2.2 L130-131 | §4.4 L190-195 | 覆盖 |
| FR-DEV-003 | §2 L67 | GWO L36；EXT L153 | §2.2 L129 | §4.3 L151-186 | 部分 |
| FR-DEV-004 | §4 L85-88 | DR L134-142；MS L36-37 | §2.2 L123/L133 | §4.1（AC 卡片） | 部分 |
| FR-DEV-005 | §2 L76 | PR L191-206；DR L151-163 | §2.2 L143-146 | （标签，LEG L2224） | 部分 |
| FR-SCN-001 | §2 L68 | —（App 本地串行） | §5 L244-259 | §4.6 L229-234 | 覆盖 |
| FR-SET-001 | §2 L54 | — | §1.2/1.3 | §3 L68 | 部分 |
| FR-SET-002 | §3.3 L128-137 | C-019 缺口 | §3 L196-217；§4 L232-234 | §3 L70 | 部分 |
| FR-SET-003 | §2 L56/L96 | C-023 缺口；SR/CC | —（CloudConfig DES 补） | §3 L70（C-018） | 部分 |
| NFR-4.1 | §3.3 | PR L55-157；DR L33-51 | §3 L196-217 | §4.3 | 部分 |
| NFR-4.2 | §2 L78-80 | — | §1.3 L53 | §4.5 L224 | 部分 |
| NFR-4.3 | §2 L66-67 | — | — | §5 L242-249 | 待定义 |

---

## 7. 对 wp-004 的建议（证据支持的方向性建议，非裁定）

1. **C-001**：采纳 `WP2` §4.2 证据方向——线格式以 schema 家族（`DR/CR/CA/PR`）为权威；内部模型命名可通过映射表解耦；同时修订 `API` 示例（含补 `server_time`）。
2. **WP2-F02**：在 `CA`/错误表之间二选一并统一 `1001..1008` 语义；建议 `result_code` 主判 + `error_code` 稳定字符串双轨；同步仿真器与 `API` L215-227。
3. **WP2-F03**：以 `IE` + 归档 App 可执行证据为准修订 `API` L44-45；显式记录"discover `SmartHomeService` / identity `YaoCoreGateway`"两常量并存的设计意图。
4. **C-005/C-006/C-015**：在"App 本地实体 + 网关 roomName 字符串"与"协议扩展 roomId/未分配表达"之间给出边界裁定；明确改名/换房/删除是否下行及未分配/禁用态的协议表达（含 `DR` 变更或声明）。
5. **D-007 ADR（合并评审）**：推荐一并覆盖——指纹载体（`IE` 扩展 or 配网后端点）、指纹格式与轮换、TLS 启用/回退策略、HMAC 密钥作用域（家庭/网关）与 Asset Store 存储、`key_id` 版本流程；并说明 GCM 扩展提案的档案位置（C-002 遗留收口）。
6. **D-008 ADR（与 D-007 同源评审）**：推荐覆盖——凭据载荷格式与版本、密钥封装、离线校验主体、撤销/轮换（含成员移除触发网关密钥轮换的成本分析）、指纹随凭据分发、威胁模型。
7. **STD-001 归一化**：按 `INV` §5 把 ArkTS 规范 + `CFG` 约束 + 安全红线（PRIV）+ 密钥存储规则归一化为带来源引用的 Project Constraints，供实现与评审统一引用。
8. **v1 设备范围声明**：建议明确 door/light/sensor/ac（以及是否含 curtain/fan/speaker），据此处置 C-021/C-022 与 `DR/CA` 扩展需求。
9. **云路径范围**：为 FR-SET-003 定义 App↔IoTDA 契约或明确标记 v1 范围外；同步处置 WP2-F04（profile 补建或降级）。
10. **文档修订机制**：为主文档引入版本头/生效日期（C-013），修复 WP2-F01 示例，记录权威顺序（C-008：机器契约 > 散文规范）。
11. **DEV-ONLY 约束落位**：将 `GWO` L11/`PR` L224-226 的拒绝要求写入 NFR 或安全约束（C-026），并规定 Mock 使用边界。
12. **测试计划接口**：wp-005 规划时纳入 NFR 4.3 测量口径、`WP2` §7 移植清单与 TLS/Mock 仿真形态。

**建议覆盖范围限制**：以上均为方向性输入，不含最终裁定；权威顺序、协议扩展与安全机制形态由 wp-004 决定；体验/产品取舍（如邀请流程形态、手动 IP 是否保留）如需业务判断应走 Clarification Gate。本报告不评估未冻结的 `input/` 外内容，也不主张任何硬件行为。

---

*本报告为系统验证产物（Producer: agent:system-verifier），供 Artifact Validation / Stage Gate 与 wp-004 契约裁定消费；结论仅对 §1.1 冻结修订成立。*
