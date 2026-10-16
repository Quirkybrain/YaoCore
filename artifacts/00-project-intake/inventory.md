# YaoCore 项目 Intake — 资产与候选工件清单

- **Producer**: agent:asset-analyst
- **Task**: wp-001-intake（Project Intake）
- **Handoff**: state/handoffs/wp-001-intake.json
- **日期**: 2026-10-16
- **仓库修订**: `task/wp-001-intake`（盘点时 HEAD = `a6f6558882f7ec53be548c85e15a1a291c5a41fd`，工作区干净；输入哈希与 handoff pin 一致）
- **Target Stage**: `implementation`；Project Workflow: `STANDARD`；Execution: `GATED_AUTO`（config/project.md L17-19）
- **状态词表**（docs/artifact-model.md L40-51）：`MISSING` / `PARTIAL` / `UNVERIFIED` / `VALID` / `STALE` / `INVALID`。本次 Intake 对所有既有资产只给出 `UNVERIFIED` 或 `PARTIAL`，**不授予 `VALID`**；推断性结论一律标注 `（INFERRED）`。
- **只读声明**: 本任务未修改 `input/`、业务代码或任何配置文件；唯一写入为本文档。仓库业务代码当前为脚手架状态（见 AS-042..AS-047）。

---

## 1. 覆盖范围与方法

### 1.1 覆盖范围

| 范围 | 内容 | 覆盖方式 |
|---|---|---|
| `input/` 全部资产 | 113 个文件（含 6 个空目录 + 13 个 `.gitkeep`） | 内容审阅 + 统计 + 交叉核对 |
| 仓库 HarmonyOS 脚手架 | `entry/`、`AppScope/`、`build-profile.json5`、`hvigorfile.ts`、`hvigor/`、`oh-package.json5`、`code-linter.json5`（24 个文件，含 5 个 PNG） | 内容全读（PNG 仅登记） |
| 工作流框架资产 | `config/`、`docs/`、`scripts/`、`state/`、`.claude/`、`.opencode/`、根级框架文档 | 仅列举（第 2 节 AS-049..AS-055），未深读 |
| 本任务声明范围外 | `origin` 远端历史（wp-000 报告已核实与本仓库不相关）；框架设计文档全文 | 未检查，见 1.3 |

### 1.2 方法

1. 文件计数与行数统计（`find`/`wc -l`）：`input/` 113 文件；原应用 55 个 `.ets` 共 16,678 行；Python 工具 14 个共 2,717 行；旧文档 5 篇共 742 行。
2. **内容优先分类**：逐一打开关键文件，按内容判定类型（如 `input/existing/original_app` 按导出符号/职责判定为 ArkTS 源码快照，而非仅凭扩展名）。
3. 交叉核对：需求/架构/UI/数据文档与协议 schema、测试向量、旧仓库文档之间的字段、流程、版本一致性。
4. 程序化检查：
   - 原应用 55 个 `.ets` 的相对 import 解析（结果：0 缺失，快照内部自洽）；
   - `input/api/protocol/*.json` 全部可解析为合法 JSON；
   - 敏感内容模式扫描（见第 7 节）；
   - demo HTML 的 JS/交互内容检查（见 C-004）。
5. 抽样深读与全量统计结合：全量文件均已打开或统计；逐行精读集中在需求/架构/UI/协议/数据/旧仓库文档及代表性代码文件。

### 1.3 未检查 / 不可读 / 覆盖限制（显式声明）

- **未逐行审阅**：55 个 `.ets` 中仅深读代表性文件（DeviceModel、GatewayModel、DeviceRepository、UserModel、AuthService、I18nService、LiveActivityService、SecureStorageService、AcAdapter 系列等）与全量导出符号/行数；其余文件的内部逻辑细节为 `（INFERRED）`。
- **未深读**：`design.md`、`FRAMEWORK_ARCHITECTURE.md`、`CLAUDE.md`/`AGENTS.md`、`docs/*.md` 框架方法论文档、`.claude/` 技能与规则全文——它们属工作流框架资产，不构成本项目产品工件（其中 `docs/artifact-model.md` 因本任务消费需要已通读）。
- **未打开内容**：5 个 PNG（`AppScope/resources/base/media/*.png`、`entry/src/main/resources/base/media/*.png`，二进制模板图标）；其余资源 JSON（float.json、backup_config.json 等）已抽查。
- **未执行**：13 个 Python 测试工具与 1 个仿真器均未运行（旧仓库布局依赖，见 C-007；且本任务含只读约束）；未执行 ArkTS 构建（无 SDK/DevEco 环境声明）。
- **未核验**：远端 `origin/main`（原项目公开发布）内容未与 `input/` 快照做逐文件比对；其不相关性已由 wp-000 报告核实（`git merge-base` 退出码 1）。
- **不可读文件**：**无**。113 个 `input/` 文件全部为文本/JSON/HTML，均可读。
- **数量核对差异**：任务简报称 `input/existing/tools/` 为“16 个 Python 契约测试工具”；实际文件清单复核为 **14 个文件（13 `.py` + 1 `.ps1`）**（INFERRED：差异可能因简报估算或统计口径不同）。本报告以文件清单为准。

### 1.4 统计复核（证据）

| 项 | 数值 | 来源 |
|---|---|---|
| `input/` 文件总数 | 113 | `find input -type f \| wc -l` |
| 空目录（仅 `.gitkeep`） | `input/uml`、`input/tests`、`input/project`、`input/competitors`、`input/references`、`input/other` | `find` + 内容确认 |
| 原应用代码 | 55 个 `.ets` / 16,678 行，全部带 Apache-2.0 头（Created: 2026-07-17，作者 Zhang HaoXuan） | `wc -l` + 头部检查 |
| 协议契约 | 16 个 JSON（12 schema + 4 测试向量）+ README | 目录清点 |
| 旧仓库文档 | 5 篇 / 742 行 | `wc -l` |
| Python/脚本工具 | 14 个文件（13 `.py` + 1 `.ps1`）/ 2,717 行 —— 任务简报称“16 个 Python 契约测试工具”，以文件清单复核为准（差异见 §1.3 覆盖限制） | `find input/existing/tools -type f` + `wc -l` |

---

## 2. Asset Inventory

> 说明：`input/existing/original_app` 的 55 个文件按模块整体登记（AS-032..AS-039），逐文件行数与职责见第 4 节；协议契约按文件逐个登记（AS-008..AS-023）。多文件资产在「路径」列标注文件数。

### 2.1 需求 / 架构 / 设计 / API / 数据 / 规范

| Asset ID | 路径 | 内容分类 | 分类依据（关键行/章节） | 修订/新鲜度信号 | 置信度 | Target 相关性 |
|---|---|---|---|---|---|---|
| AS-001 | `input/README.md` | 资产池使用说明（框架模板） | L1 “Project Asset Pool”；L46-50 识别原则 | 框架模板 | 高 | 低（流程说明） |
| AS-002 | `input/requirements/YaoCore_HarmonyOS_App_Requirements.md` | 需求规格说明书（PRD） | L1 标题；L60-139 FR-FAM/ROOM/HOME/GW/DEV/SCN/SET；L143-158 NFR | 无版本头；示例时间戳 20261015 | 高 | **高**（实现目标的功能基线） |
| AS-003 | `input/architecture/App_System_Architecture.md` | 系统架构设计说明（MVVM 五层） | L42-99 五层框图；L143-156 `IGatewayClient`/`IBleProvisioningClient` 接口；L158-162 MockGatewayService | 无版本头；协议引用 v2 | 高 | **高** |
| AS-004 | `input/design/UI_UX_Specification.md` | UI/UX 交互规范（含设计 token 与状态机） | L16-52 色彩/材质 token；L80-235 四类交互状态机；L239-258 动效常量类 `AppMotionTokens` | 无版本头；引用 demo 作视觉参考 | 高 | **高** |
| AS-005 | `input/design/demo/YaoCore_Ambient_Demo.html` | 交互原型 Demo（**实测仅 CSS，无 JS**） | L7 meta 声称“可交互原型”；L913-916 仅空挂载点 `#app`/`#portal`；全文无 `<script>`（见 C-004） | 无版本头 | 高 | 中（视觉 token 参考） |
| AS-006 | `input/api/Gateway_API_Specification.md` | 网关 API 协议规范（人类可读 prose） | L1 标题；L14-121 BLE/LAN 契约；L123-227 /control 与错误码；L231-249 IoTDA 映射 | “当前 v2 协议阶段”（L9）；KeyId `app-key-v1` | 高 | **高**，但与 AS-007..AS-023 存在字段/范围冲突（C-001/C-002） |
| AS-007 | `input/api/protocol/README.md` | 协议 v2 契约说明（规范正文） | L1 “protocol v2 contract”；L55-107 签名 canonical；L109-162 响应认证；L164-206 云端与 ACK 规则 | v2；签名 key `app-key-v1` | 高 | **高**（与 schema 配套的权威说明） |
| AS-008 | `input/api/protocol/discover-response.schema.json` | JSON Schema：`GET /discover` 响应 | L4 title；L6-14 required 含 `security`；L72-169 device 定义（`online`/`power`/`open`，**无 roomId**） | draft 2020-12 | 高 | **高** |
| AS-009 | `input/api/protocol/local-control-request.schema.json` | JSON Schema：签名控制请求 | L4 title；L23 `cmd_id const 2001`；L33-57 `payload{action,value}`；L90 `additionalProperties:false` | v2 | 高 | **高**（与 C-002 相关） |
| AS-010 | `input/api/protocol/local-control-ack.schema.json` | JSON Schema：控制 ACK | L6 required 含 `server_time`；L34 `idempotent_replay`；L49-63 result_code=0 ⇒ 必须有 `reported_state` | v2 | 高 | **高** |
| AS-011 | `input/api/protocol/cloud-command.schema.json` | JSON Schema：IoTDA 命令信封 | L4 title；L17 `SetDeviceStatus`；L38 `CmdId const 3001`；L19-75 paras 字段 | v2 | 高 | 中（云端路径） |
| AS-012 | `input/api/protocol/state-report.schema.json` | JSON Schema：IoTDA 属性上报 | L4 title；L17 `SmartHomeService`；L37-45 required 属性清单；L47-50 `DeviceInventoryJson` 动态库存 | v2 | 高 | 中 |
| AS-013 | `input/api/protocol/ble-enrollment-identity-request.schema.json` | JSON Schema：`yaocore-id` 请求 | L4 title（Security1 保护端点） | v2 | 高 | **高**（BLE 配网契约） |
| AS-014 | `input/api/protocol/ble-enrollment-identity-response.schema.json` | JSON Schema：`yaocore-id` 响应 | L4 title；仅身份字段（gatewayId 等，见 AS-007 L37-41） | v2 | 高 | **高** |
| AS-015 | `input/api/protocol/hmac-sha256-test-vectors.json` | 跨语言签名测试向量 | L2 `PUBLIC TEST DATA ONLY` 警告；canonical/secret 字段 | 公开测试数据 | 高 | **高**（契约测试锚点） |
| AS-016 | `input/api/protocol/response-auth-test-vectors.json` | 响应验签测试向量 | `version 1.0`；canonicalFormat `YAOCORE-RESPONSE-V1\nkind\ncorrelation\nsha256...` | v1.0 | 高 | **高** |
| AS-017 | `input/api/protocol/discovery-request-auth-test-vectors.json` | 发现请求鉴权测试向量 | `version 2.0`；canonicalFormat `YAOCORE-DISCOVER-V2...` | v2.0 | 高 | **高** |
| AS-018 | `input/api/protocol/module-register.schema.json` | Schema：外部模块注册 v1 | L4 title；L7 required（module/device/state）；`room` 为字符串字段 | v1 | 高 | 中（外部模块范围） |
| AS-019 | `input/api/protocol/module-state.schema.json` | Schema：模块状态事件 v1 | L4 title（state 定义被 register/ack 引用） | v1 | 高 | 中 |
| AS-020 | `input/api/protocol/module-heartbeat.schema.json` | Schema：模块心跳 v1 | L4 title | v1 | 高 | 低-中 |
| AS-021 | `input/api/protocol/module-command.schema.json` | Schema：网关→模块命令 v1 | L4 title；L10-11 **封闭 action 枚举**（不含 `SET_DEVICE_ROOM`/`SET_DEVICE_NAME`） | v1 | 高 | 中（见 C-006） |
| AS-022 | `input/api/protocol/module-command-ack.schema.json` | Schema：模块执行 ACK v1 | L4 title；L9 `reportedState` 引用 module-state | v1 | 高 | 中 |
| AS-023 | `input/api/protocol/module-hmac-test-vector.json` | 模块派生密钥互操作向量 | `description: Public interoperability fixture only`；masterSecret+derivedKeyHex | 公开测试数据 | 高 | 中 |
| AS-024 | `input/data/Data_and_State_Models.md` | 数据模型与状态管理规范 | L5-57 Family/Member/Invitation；L63-149 Room/Device；L196-217 加密信封；L223-237 GatewayState；L244-259 Scene | 无版本头；含 AES-GCM 信封（与 schema 冲突，C-002） | 高 | **高** |
| AS-025 | `input/standards/ArkTS_Coding_Standards.md` | 团队工程/编码规范 | L3-8 语言基线（API14/26、严类型）；L14-28 ArkUI/分层；L34-49 异步/资源；L53-64 加密与敏感数据 | 无版本号；含 targetSdk 26 说明 | 高 | **高**（规范源，待归一化） |
| AS-026 | `input/standards/README.md` | standards 目录说明（框架模板） | L3 用途；L27 归一化流程说明；L31 i18n 默认规范引用 | 框架模板 | 高 | 低（流程说明） |

### 2.2 原项目资产（`input/existing/`）

| Asset ID | 路径 | 内容分类 | 分类依据（关键行/章节） | 修订/新鲜度信号 | 置信度 | Target 相关性 |
|---|---|---|---|---|---|---|
| AS-027 | `input/existing/docs/BLE配网设计.md` | BLE 配网设计与验收规范（最详细互操作依据） | L21-31 GATT/端点契约；L60-100 Security1 精确流程与 X25519 向量；L159-197 状态机与验收用例 | 引用 “当前 target API 22”（L151）与 ESP-IDF 5.2 —— 与本项目 API 基线不同（C-003） | 高 | **高**（配网实现/测试细节） |
| AS-028 | `input/existing/docs/EXTERNAL_MODULE_PROTOCOL.md` | 外部模块接入协议 v1（含 UDP 扩展） | L22-65 身份/密钥/签名；L67-96 注册；L119-164 命令与 ACK 能力表；L179-199 UDP 遥测 | v1；引用 2026-07 示例 | 高 | 中（网关侧协议参考） |
| AS-029 | `input/existing/docs/网关接口协议.md` | 原项目网关接口协议（全栈视角） | L7-26 发现/控制/成功条件；L28-46 统一设备路由；L50-60 外部模块；L62-66 IoTDA | 旧仓库文档；含固件视角 | 中-高 | 中（协议交叉参考；与 AS-006 重叠，C-001） |
| AS-030 | `input/existing/docs/YaoCore用户使用手册.md` | 原项目用户手册（安装/配网/故障/发布） | L3-12 系统组成；L36-45 OpenHarmony 构建；L72-98 首启配网；L165-178 安全隐私 | 引用 `gateway/`、`devices/`、`tools/build_openharmony.ps1` —— 路径不在本仓库（C-007） | 高 | 中（用户流程参考；发布流程属历史） |
| AS-031 | `input/existing/docs/隐私与本地配置.md` | 隐私与本地配置政策（安全红线） | L5-17 不提交文件清单；L49-58 提交前检查；L68-73 设备清除 | 旧仓库政策 | 高 | 中（安全约束参考） |
| AS-032 | `input/existing/original_app/adapter/ac/`（6 文件，197 行） | 空调品牌适配层代码 | `AcAdapter.ets` L12 接口；`AcAdapterFactory.ets` L17-35 品牌归一化；`GenericAcAdapter.ets` L16 基类（经 DeviceRepository 下发） | Created 2026-07-17 | 高 | **高**（五层之适配层直接复用候选） |
| AS-033 | `input/existing/original_app/common/`（6 文件，315 行） | 公共常量/类型/工具代码 | `DeviceConstants.ets` L12-25（DeviceIds、默认 IP/端口 9200）；`CommandTypes.ets` L22-88（Command/Result/Route） | 同上 | 高 | 中-高（数据类型与工具复用候选） |
| AS-034 | `input/existing/original_app/components/`（5 文件，556 行） | ArkUI 复用组件代码 | 5 个 `@Component`：StatusBanner/ClimateCard/LightCard/DoorCard/SceneCard | 同上 | 高 | 中-高（UI 组件参考/复用候选） |
| AS-035 | `input/existing/original_app/entryability/EntryAbility.ets`（58 行） | UIAbility 入口代码 | `export default class EntryAbility extends UIAbility`（标准生命周期） | 同上 | 高 | 中 |
| AS-036 | `input/existing/original_app/model/`（10 文件，558 行） | 领域数据模型代码 | DeviceModel L12-113（DeviceType/Action/State）；GatewayModel L14-93；UserModel L18-43；SceneModel | 同上；**无 Family/Room(roomId) 实体** | 高 | **高**（新数据模型对照基线，C-005） |
| AS-037 | `input/existing/original_app/pages/`（7 文件，6,281 行） | 页面层代码 | Index L32 `@Entry`（Tabs 壳）；DevicePage 2,253 行（含 BLE 配网 UI）；SettingsPage 1,400 行；ScenePage 916 | 同上；DevicePage 含“删除网关”流程（旧测试锚点） | 高 | **高**（UI 行为重构基线） |
| AS-038 | `input/existing/original_app/service/`（13 文件，7,827 行） | 服务层代码（业务+传输） | BleProvisioningService 1,409 行；GatewayDiscoveryService 1,046；DeviceRepository 1,031；CloudService 896；I18nService 685（615 条 zh→en case）；SecurityService 262；LocalGatewayService 547；SecureStorageService 76 | 同上；**无 MockGatewayService**；无 AES-GCM/HKDF（grep 0 命中） | 高 | **高**（核心逻辑挖掘来源） |
| AS-039 | `input/existing/original_app/viewmodel/`（7 文件，886 行） | ViewModel 层代码 | DeviceViewModel 293；HomeViewModel 184；SettingsViewModel 153；其余 4 个 | 同上 | 高 | **高**（分层重构基线） |
| AS-040 | `input/existing/tools/` 协议契约/仿真组（6 文件，2,088 行） | 开发仿真器 + 协议契约测试 | `gateway_contract_server.py` L12-19 声明“仅开发仿真器”；L47 `PUBLIC_TEST_SECRET`；`test_gateway_contract.py` 532 行；`test_app_response_auth.py`；`test_ble_provisioning_contract.py`（含 protobuf/X25519 向量）；`test_external_module_protocol.py`；`derive_module_key.py`（L5 getpass 隐藏输入） | 2026-07-17 起 | 高 | **高**（契约测试移植来源，C-007） |
| AS-041 | `input/existing/tools/` 旧仓库源码检查组（8 文件，629 行） | 旧实现字符串级测试 + 构建脚本 | `test_brand_localization.py`（校验旧 `Index.ets`/`OnboardingPage.ets` 文案）；`test_gateway_removal_flow.py`（校验 `DevicePage.ets` 特有代码串）；`test_esp32_gateway_source.py`（引用 `gateway/esp32s3m`）；`test_local_cloud_routing.py`、`test_multidevice_contract.py`、`test_scene_gateway_closure.py`、`test_sensor_automation_flow.py`（引用旧 entry 源码/固件/`cloud/iotda`）；`build_openharmony.ps1` | 同上 | 高 | 中（行为期望参考；**按原样不可运行**，见 C-007） |

### 2.3 仓库脚手架与工作流资产

| Asset ID | 路径 | 内容分类 | 分类依据（关键行/章节） | 修订/新鲜度信号 | 置信度 | Target 相关性 |
|---|---|---|---|---|---|---|
| AS-042 | `build-profile.json5` | App 级构建配置 | `targetSdkVersion/compatibleSdkVersion 26.0.0`、`runtimeOS HarmonyOS`、strictMode | 模板默认（signingConfigs 空） | 高 | **高**（构建基线） |
| AS-043 | `oh-package.json5` + `entry/oh-package.json5` | 包管理与依赖 | devDependencies：`@ohos/hypium 1.0.25`、`@ohos/hamock 1.0.0` | 模板默认 | 高 | 高（测试框架依赖已就位） |
| AS-044 | `code-linter.json5` | 静态检查配置 | 性能/TS 推荐规则集 + `@security/no-unsafe-*` 系列 | 模板默认 | 高 | 高（安全 lint 门禁可用） |
| AS-045 | `hvigorfile.ts`、`entry/hvigorfile.ts`、`hvigor/hvigor-config.json5` | 构建工具链配置 | `appTasks`/`hapTasks`，模板注释 “Template file” | 模板默认 | 高 | 高 |
| AS-046 | `entry/` 工程外壳（19 文件） | HarmonyOS entry 模块外壳 | `module.json5`：单 EntryAbility、deviceTypes ["phone"]、**无 requestPermissions**；`Index.ets` L29-31 `'Hello World'`；EntryAbility/EntryBackupAbility 为模板代码；resources 为模板字符串/颜色 | 模板默认（Huawei 许可证头） | 高 | **高**（待实现替换：权限/页面/资源均缺） |
| AS-047 | `AppScope/`（5 文件） | 应用级配置与资源 | `app.json5`：bundleName `com.example.yaocore`、app_name `YaoCore`；图标 PNG 为模板 | 模板默认 | 高 | 中（bundle 标识/图标待定） |
| AS-048 | `.gitignore` | 忽略规则 | 忽略 `input/ artifacts/ state/ docs/ config/ scripts/ tests/ .claude/ .opencode/` 等（“仓库仅保留业务代码”） | 项目定制 | 高 | 中（影响交付/发布清理，state 开放项 2） |
| AS-049 | `config/`（4 文件） | 工作流配置 | `project.md`（项目目标/约束）、`git-policy.json`、`git-policy.default.md`、`project.example.md` | 2026-10-16 更新 | 高 | 高（元配置） |
| AS-050 | `docs/`（10 文件） | 框架方法论文档 | artifact/state/gate/operational-guards/git-collaboration/opencode 等 | 框架版本随仓库 | 高 | 中（流程依据） |
| AS-051 | `scripts/`（2 文件）+ `tests/`（2 文件） | 工作流守卫与自测 | `swe_guard.py`（pin/begin/finish）、`sync_opencode.py`；`test_swe_guard.py`、`test_opencode_adapter.mjs` | 框架 | 高 | 中 |
| AS-052 | `.claude/` + `.opencode/` | 智能体/技能/规则/插件定义 | 15+1 个 agent 定义、23 个 skills、9 个 rules、hooks；`swe-guards.js` 插件 | 框架 | 高 | 中 |
| AS-053 | 根级框架文档（`AGENTS.md`、`CLAUDE.md`、`design.md`、`FRAMEWORK_ARCHITECTURE.md`、`START_PROJECT.md`、`CONTINUE_PROJECT.md`、`ADOPT_EXISTING_PROJECT.md`、`EXECUTE_TASK.md`、`opencode.json`） | 框架入口与说明 | 仅登记 | 框架 | 高 | 低-中 |
| AS-054 | 空目录集：`input/uml`、`input/tests`、`input/project`、`input/competitors`、`input/references`、`input/other`（各仅 `.gitkeep`）；`input/` 共 13 个 `.gitkeep`（其中 7 个位于有内容的目录） | 覆盖事实（**内容为空**） | `find input -type f` 全量为 113；上述目录无内容文件 | — | 高 | 记录事实：UML/测试/商业背景/竞品/参考资料**未提供** |
| AS-055 | `state/`（checkpoint/state/报告/handoffs）+ `artifacts/`（本清单位置）+ `output/`（空） | 工作流状态与产出目录 | `state/project-state.md`、`checkpoint.md`、wp-000 报告 | 2026-10-16 | 高 | 中（恢复与交付位置） |

---

## 3. 候选 Artifact Inventory

> 初始状态仅允许 `MISSING`/`PARTIAL`/`UNVERIFIED`；`VALID` 须经 Artifact Validation Gate（本表不授予）。「建议下游用途」不指定固定 Agent 链。

### 3.1 既有资产构成的候选工件

| 建议 ID | 工件类型 | 来源资产 | 初始状态 | 依据/备注 | 建议下游用途 |
|---|---|---|---|---|---|
| REQ-001 | Requirements（App 功能+NFR） | AS-002（主）；AS-027（配网运行细节补充） | UNVERIFIED | 7 组 FR + RBAC + NFR 覆盖完整；但配网权限/MTU 等细节在 AS-027/AS-029 中更精确，需合并验证 | 需求验证、验收标准、追溯链起点 |
| ARCH-001 | Architecture（五层 MVVM + 网关抽象） | AS-003 | UNVERIFIED | 五层职责、接口签名、Mock 要求明确；需与 REQ-001/DATA-001 一致性验证 | 组件规划、契约定义（IClient 接口） |
| UIUX-001 | UI/UX Specification | AS-004；AS-005（视觉素材） | UNVERIFIED | tokens/状态机/动效参数完整；demo 无 JS（C-004）仅作视觉参考 | UI 实现基线、组件视觉验收 |
| API-001 | API Specification（人类可读） | AS-006 | UNVERIFIED | 与 PROTO-001 字段/范围冲突（C-001/C-002）；需以 schema 为准或以澄清裁定 | 协议实现说明、错误码映射 |
| PROTO-001 | API Contract：LAN/Cloud 协议 v2（schema+向量） | AS-007..AS-012、AS-015..AS-017 | UNVERIFIED | 机器可读、字段精确（`online/power/open/targetTemp`、时长窗口、重放语义）；当前最可靠契约源候选 | 契约测试、serialization 实现、Mock 校验 |
| PROTO-002 | API Contract：BLE 配网（Security1+身份端点） | AS-013、AS-014、AS-027 | UNVERIFIED | schema + AS-027 精确流程（X25519 向量、endpoint 映射、错误闭环） | 配网实现、配网契约测试 |
| PROTO-003 | API Contract：外部模块 v1 | AS-018..AS-023、AS-028 | UNVERIFIED | 网关侧模块接入契约（App 侧消费者为设备状态来源） | 网关协议边界说明、测试向量复用 |
| DATA-001 | Data & State Models | AS-024 | UNVERIFIED | 新实体（Family/Member/Invitation/Room/Device/Scene/Gateway）；与 PROTO-001 `roomName` 差异见 C-005 | 领域模型实现、状态机设计 |
| STD-001 | Project Constraints 候选源：ArkTS 编码规范 | AS-025；AS-026（流程） | UNVERIFIED | 属“规范源”，应由架构责任一次性归一化为 Project Constraints 并带引用 | 实现规范、评审检查单 |
| STD-002 | Git 协作约束 | AS-049（config/git-policy.json + 默认政策） | UNVERIFIED | 已 pin 生效于守卫；公司规范缺省（`company_policy_path: null`） | 仓库/提交流程约束 |
| LEGACY-001 | Code（重构基线，行为证据） | AS-032..AS-039（55 文件/16,678 行） | UNVERIFIED | 内部自洽（import 0 缺失）；**缺 Family/Room 实体、Mock、AES-GCM**；逐行仅抽样（第 1.3 节） | 行为挖掘（默认值/错误语义）、测试用例来源、UI 参考 |
| LEGACY-002 | Reference Docs（原项目文档集） | AS-027..AS-031 | PARTIAL | 内容权威度分层：AS-027/028 协议细节高价值；AS-030 安装/发布流程与本仓库无关（C-007）；AS-031 安全红线仍适用 | 配网/模块协议细节、安全约束 |
| TEST-REF-001 | Test Assets：协议契约/仿真 | AS-040 | PARTIAL | 测试逻辑可移植；运行路径依赖旧仓库布局（C-007），需适配后执行 | 契约测试套件移植、Mock 仿真基线 |
| TEST-REF-002 | Test Assets：旧实现字符串检查 | AS-041 | PARTIAL | 编码的是旧实现行为期望（示例：配网向导文案、网关删除流程）；直接运行无意义，价值在“期望清单” | 回归用例来源（需重新映射到新实现） |
| SHELL-001 | Code：HarmonyOS 工程骨架 | AS-042..AS-047 | PARTIAL | 构建/依赖/测试框架就位；无业务实现、无权限声明、Hello World 页面 | 实现起点（替换 Index/资源/权限） |
| UIREF-001 | UI Reference：Demo HTML | AS-005 | PARTIAL | 仅 CSS token/样式类；无 JS/无渲染内容（C-004） | 视觉 token 对照（严格以 UIUX-001 为准） |

### 3.2 目标所需但当前缺失的候选工件（`MISSING`）

| 建议 ID | 工件类型 | 来源要求 | 初始状态 | 说明 | 建议下游用途 |
|---|---|---|---|---|---|
| README-001 | Documentation（项目根构建/运行/测试说明） | AGENTS.md 测试要求；Target Stage implementation | MISSING | 当前根目录无项目 README；交付代码前必须补齐并验证 | 代码交付 DoD |
| MOCK-001 | Code：MockGatewayService 测试桩 | AS-003 L158-162 | MISSING | 原应用无 Mock（grep 0 命中）；架构明确要求 100% 脱机验证 | 单元/契约测试基础设施 |
| IMPL-FAM-001 | Code：家庭/成员/RBAC 实现 | REQ-001 FR-FAM-001..004；DATA-001 | MISSING | 原应用无 familyId/MemberRole/invite（grep 0 命中） | 组件规划与实现 |
| IMPL-ROOM-001 | Code：房间实体/未分配池实现 | REQ-001 FR-ROOM-001..006；DATA-001 | MISSING | 原应用仅 `roomName` 自由文本（无 roomId） | 组件规划与实现 |
| SEC-CH-001 | Code：LAN 安全通道（AES-256-GCM 或 HTTPS pinning） | REQ-001 §4.1；AS-024 §3 | MISSING（范围待澄清） | 原应用无 GCM/HKDF；协议 schema 无加密载荷字段（C-002） | 安全实现（澄清后） |
| I18N-001 | Resources：双语资源包 | AS-025 L26-28；docs/internationalization.md | MISSING | 原应用为 615 条内联映射（非资源包）；模板 resources 为单语占位 | 国际化实现与评审基线 |
| ADR-001 | Decision Records | 框架要求（重大技术决策） | MISSING | 当前无任何 ADR；安全通道/协议版本决策将产生首批 ADR | 决策持久化 |
| DES-001 | Detailed Design / Component Contracts | ARCH-001 + Target implementation | MISSING | 实现前需组件级契约（接口、数据结构、错误语义） | 组件规划输入 |
| TEST-001 | Test Plan/Report | 框架测试要求 | MISSING | 无项目测试计划/报告；框架自测（AS-051）不覆盖产品 | 测试工程规划 |

---

## 4. 原应用代码模块盘点（55 文件 / 16,678 行）

### 4.1 模块汇总与五层映射

| 模块 | 文件数 | 行数 | 职责一句话 | 与新架构五层对应（AS-003 L44-99） |
|---|---|---|---|---|
| `adapter/ac/` | 6 | 197 | 空调品牌适配（接口/工厂/通用基类/Gree/Haier/Midea） | 4. 适配层 |
| `common/` | 6 | 315 | 常量、数据类型与工具（时间/头部/数值） | 跨层基础类型 |
| `components/` | 5 | 556 | 复用 UI 卡片与状态横幅 | 1. UI 表现层 |
| `entryability/` | 1 | 58 | UIAbility 生命周期入口 | 应用入口 |
| `model/` | 10 | 558 | 领域数据模型（设备/网关/场景/云/配网/用户等） | 跨层数据模型 |
| `pages/` | 7 | 6,281 | 页面与导航壳（含配网/设置/场景大页面） | 1. UI 表现层 |
| `service/` | 13 | 7,827 | 业务+传输服务（配网/发现/仓库/安全/存储/云/场景/i18n） | 3. 业务逻辑与数据层 + 5. 转发与传输层（混合，需解耦） |
| `viewmodel/` | 7 | 886 | 页面状态聚合与控制编排 | 2. ViewModel 层 |
| **合计** | **55** | **16,678** | — | — |

> `（INFERRED）` 分层映射按导出符号与文件职责判定；未逐行审阅内部实现。
> 关键缺口（相对新架构）：无 `MockGatewayService`、无 `FamilyRepository/RoomRepository`、无 CryptoService（AES-GCM/X25519 封装）、无 HTTPS pinning。

### 4.2 逐文件清单

**adapter/ac（197 行）**

| 文件 | 行数 | 要点（导出/职责） | 五层 |
|---|---|---|---|
| AcAdapter.ets | 18 | `AcAdapter` 接口：getBrand/powerOn/powerOff/setTargetTemperature/setMode | 适配层 |
| AcAdapterFactory.ets | 36 | 品牌字符串归一化（中英/组合别名）→ 适配器实例 | 适配层 |
| GenericAcAdapter.ets | 71 | 通用实现，经 `DeviceRepository.control` 下发统一命令 | 适配层 |
| GreeAcAdapter.ets | 24 | 格力：模式归一化（'节能'→'ECO'） | 适配层 |
| HaierAcAdapter.ets | 24 | 海尔品牌覆写 | 适配层 |
| MideaAcAdapter.ets | 24 | 美的品牌覆写 | 适配层 |

**common（315 行）**

| 文件 | 行数 | 要点 | 五层 |
|---|---|---|---|
| constants/AppTheme.ets | 60 | AppColors/AppMetrics/AppTypography 视觉常量 | UI/跨层 |
| constants/DeviceConstants.ets | 25 | DeviceIds（Door_01/Light_01/Sensor_01/AC_01）、GatewayDefaults（IP 192.168.1.88、端口 9200） | 跨层 |
| types/CommandTypes.ets | 88 | DeviceControlCommand/DeviceReportedState/ControlRoute/ControlResult/INetworkControlService（含 ACK、防乐观语义注释） | 跨层 |
| utils/DateTimeUtil.ets | 83 | 紧凑 UTC 时间戳工具 | 跨层 |
| utils/HttpHeaderUtil.ets | 34 | `X-YaoCore-*` 请求头构造 | 传输层辅助 |
| utils/NumberUtil.ets | 25 | 数值处理工具 | 跨层 |

**components（556 行）**：ClimateCard 152、StatusBanner 138、LightCard 104、DoorCard 91、SceneCard 71 —— 均为 `@Component` 声明式卡片（UI 表现层）。

**entryability**：EntryAbility.ets 58 行，标准 UIAbility 生命周期（应用入口）。

**model（558 行）**

| 文件 | 行数 | 要点 | 五层 |
|---|---|---|---|
| BleProvisioningModel.ets | 51 | 配网设备/请求/结果/Wi-Fi 网络/进度接口 | 数据模型 |
| ClimateModel.ets | 43 | ClimateSnapshot/ClimateModel | 数据模型 |
| CloudModel.ets | 49 | CloudConfig/CloudSyncResult/default | 数据模型 |
| CommunicationModel.ets | 30 | LocalRouteConfig/default | 数据模型 |
| DeviceModel.ets | 130 | DeviceType/DeviceAction/DeviceState/DeviceDraft + 工具函数 | 数据模型 |
| DoorModel.ets | 32 | DoorSnapshot/DoorModel | 数据模型 |
| GatewayModel.ets | 107 | GatewayState/DiscoveredGateway/PendingGatewayBindingState/DiscoveryResult | 数据模型 |
| LightModel.ets | 32 | LightSnapshot/LightModel | 数据模型 |
| SceneModel.ets | 41 | SceneAction/SceneDefinition/SceneDraft/Cleanup | 数据模型 |
| UserModel.ets | 43 | LocalCredential/AuthSession（本地档案，非云账号） | 数据模型 |

**pages（6,281 行）**

| 文件 | 行数 | 要点 | 五层 |
|---|---|---|---|
| Index.ets | 447 | `@Entry` 壳：启动页/引导/四 Tab（Home/Device/Scene/Settings） | UI |
| HomePage.ets | 467 | 家庭看板（网关状态/房间胶囊/设备网格/环境看板） | UI |
| DevicePage.ets | 2,253 | 设备与网关管理（扫描/绑定/BLE 配网 UI/删除网关二次确认/未分配提示）——旧契约测试锚点最集中 | UI |
| DeviceControlPage.ets | 589 | 设备详情控制（调光/空调/门锁） | UI |
| ScenePage.ets | 916 | 场景卡片与步骤级执行反馈 | UI |
| SettingsPage.ets | 1,400 | 设置：网关/云/密钥/诊断/语言/账号分区 | UI |
| OnboardingPage.ets | 209 | 首启 Swiper 引导（与 BLE 配网流程对接） | UI |

**service（7,827 行）**

| 文件 | 行数 | 要点 | 五层 |
|---|---|---|---|
| BleProvisioningService.ets | 1,409 | BLE 扫描/MTU/0x2901 端点映射/Security1/Wi-Fi 下发/探针绑定 | 传输层（配网） |
| GatewayDiscoveryService.ets | 1,046 | UDP/mDNS 发现 + 双向 HMAC `/discover` 校验 + 绑定状态机 | 传输层 |
| DeviceRepository.ets | 1,031 | 设备单一可信源、控制编排、持久化、云同步协调 | 业务数据层 |
| CloudService.ets | 896 | IoTDA MQTT/HTTPS 命令与设备影子 | 传输层（云） |
| I18nService.ets | 685 | zh→en 内联字典（615 case）+ 语言偏好（**非资源包模式**） | 业务（横切） |
| NetworkService.ets | 611 | 本地/云路由切换、云配置、控制入口 | 业务+传输 |
| LocalGatewayService.ets | 547 | 局域网 HTTP 控制打包、HMAC 签名与 ACK 校验 | 传输层（LAN） |
| SceneService.ets | 478 | 场景串行执行、部分失败记录、网关移除清理 | 业务数据层 |
| AppStorageService.ets | 414 | Preferences 持久化（设备/路由/凭据/场景等） | 业务数据层 |
| AuthService.ets | 265 | 本地 PBKDF2（120,000 次）凭据与会话 | 业务数据层 |
| SecurityService.ets | 262 | HMAC canonical 串、时间窗、nonce、响应验签 | 业务（安全） |
| LiveActivityService.ets | 107 | 通知快照发布（notificationManager，非实况窗） | 横切 |
| SecureStorageService.ets | 76 | Asset Store 保存 token/命令密钥（CLOUD_TOKEN/COMMAND_KEY alias） | 业务数据层 |

**viewmodel（886 行）**：DeviceViewModel 293、HomeViewModel 184、SettingsViewModel 153、SceneViewModel 102、ClimateViewModel 60、BleProvisioningViewModel 53、DoorViewModel 41（ViewModel 层）。

---

## 5. 规范（Standards）来源索引

> 原则（input/standards/README.md L27）：Intake 只发现来源；归一化为带来源引用的 Project Constraints 属架构责任，本文不越权归一化。

| 来源 | 路径 | 性质 | 关键约束摘要 |
|---|---|---|---|
| 编码/工程规范 | `input/standards/ArkTS_Coding_Standards.md` | 项目/团队规范源 | API14/26 基线；严类型；UI/逻辑分离；异常与资源释放；cryptoFramework；常数时间比对；敏感数据生命周期 |
| 规范目录流程 | `input/standards/README.md` | 框架说明 | 规范放置与归一化流程；i18n 默认规范引用 |
| 项目约束配置 | `config/project.md` §Constraints and Preferences | 项目配置（已生效） | Must/Forbidden 技术、性能（ACK≤500ms、55ms 节流）、安全要求、兼容性、i18n |
| Git 协作 | `config/git-policy.json` + `config/git-policy.default.md` | 流程规范（pin 生效） | BRANCH_PER_TASK、no-ff、托管 PR 合并模式；公司规范未配置（`company_policy_path: null`） |
| 框架流程规范 | `docs/internationalization.md`、`docs/artifact-model.md`、`docs/state-model.md`、`docs/gate-model.md`、`docs/operational-guards.md`、`docs/git-collaboration.md` | 框架规范 | i18n 解耦资源包；工件状态机；门禁与守卫 |
| 旧仓库隐含规范 | `input/existing/docs/BLE配网设计.md`（互操作验收）、`input/existing/docs/隐私与本地配置.md`（安全红线） | 存量规范源（`PARTIAL`） | Security1 精确流程与矢量为高价值；安全红线（密钥不入库）仍适用；部分版本面已过时（C-003） |

---

## 6. 冲突 / 重复 / 过时 / 不可读 / 不确定日志

> 所有冲突均只记录、不擅自裁定。

| ID | 类别 | 描述 | 证据 | 影响 |
|---|---|---|---|---|
| **C-001** | 字段命名冲突（权威待定） | 人类可读 API 规范用 `isOnline/powerStatus/openStatus/targetTemperature/success` 等驼峰字段与示例；协议 v2 schema 用 `online/power/open/targetTemp/server_time/idempotent_replay`（无 `success`） | AS-006 L96-119、L187-203 vs AS-008 L72-169、AS-010 L6-46 | 序列化/数据模型/DTO 实现若择错字段将全链路不兼容；契约测试与 Mock 无法同时对两者成立 |
| **C-002** | 范围冲突：LAN 加密模式 | PRD/API 规范/数据模型包含 `EncryptedPayloadEnvelope`（AES-256-GCM、cmd_id 2002）；协议 v2 README 明确“消息认证不加密正文，机密性须用 HTTPS pin”，且 request schema `cmd_id const 2001` + `additionalProperties:false` 无 `encrypted_payload` | AS-002 L146-149、AS-006 L146-166、AS-024 L196-217 vs AS-007 L159-162、AS-009 L23/L90 | v1 实现范围（GCM 载荷 vs HTTPS-pin vs 两者）未决；直接影响 SEC-CH-001、契约与测试设计 |
| **C-003** | 版本/平台过时 | 旧文档按 “target API 22 / OpenHarmony / ESP-IDF 5.2 / 网关固件” 描述；本项目 config 为 HarmonyOS NEXT API 14+（targetSdk 26.0.0）且仅 App 仓库 | AS-027 L151、AS-030 L3-12/L36-45 vs config/project.md L32/L42/L54 | 旧文档中运行环境/构建/权限细节可能不再适用（如蓝牙权限模型）；需按现行基线复验 |
| **C-004** | 资产不完整/名实不符 | Demo HTML 元数据声称“可交互原型”，但全文无 `<script>`/JS，仅 CSS（L11-904，约 892 行样式）+ 空挂载点；无法渲染任何页面 | AS-005 L7、L913-916；`grep -ci script` 仅 3 处（meta/CSS 类名/noscript） | 不能从 demo 提取任何交互逻辑；只能取视觉 token（与 config/project.md L66 定位一致，可降级为已解释差异） |
| **C-005** | 模型/协议不匹配 | 新数据模型要求房间为不可变实体 `roomId`（UUID），但协议 v2 discover 响应 device 必有 `roomName`（字符串）且无 roomId；module-register 亦用 `room` 字符串 | AS-024 L63-74 vs AS-008 L77/L91-95、AS-018 | 房间-设备关系在网关协议中的表达方式未定义：App 本地实体与网关 roomName 的映射/同步策略缺失 |
| **C-006** | 契约能力缺口 | `DeviceAction` 含 `SET_DEVICE_NAME/SET_DEVICE_ROOM`，但网关→模块命令 schema 为封闭枚举且不含二者；local-control-request 的 action 为开放正则（App→网关可能可行） | AS-024 L90-105、AS-009 L39 vs AS-021 L10-11 | “改名/换房是否需要下发到网关”未定义；若实现依赖网关执行将不兼容 |
| **C-007** | 工具不可直接运行 | 14 个 Python 工具按原仓库布局编写（`ROOT/entry/...`、`ROOT/gateway/esp32s3m`、`ROOT/protocol`、`cloud/iotda/product-profile.json`）；本仓库无 `gateway/`、`cloud/`，`entry/` 为模板 | AS-040 各文件 `ROOT` 定义（如 test_gateway_contract.py L42-44、test_ble_provisioning_contract.py L19-23）；AS-041 各文件 | 契约测试/仿真需路径适配或迁移后才可执行；TEST-REF-002 绑定旧实现字符串，移植价值在“期望清单” |
| **C-008** | 重复资产（内容重叠） | `input/existing/docs/网关接口协议.md` 与 `input/api/Gateway_API_Specification.md` 覆盖范围重叠（发现/控制/路由/IoTDA）；前者为固件视角、后者为 App 视角；IModule 协议同时有 EXTERNAL_MODULE_PROTOCOL.md 与 6 个 module schema | AS-029 vs AS-006；AS-028 vs AS-018..AS-023 | 若同时引用可能出现表述不同步；应指定权威顺序（schema/README 优先）或合并 |
| **C-009** | 轻微不一致 | 邀请码长度：PRD “6~8 位”（L67），UI 规范与流程用“6 位”（L90、L106），数据模型 `inviteCode` 注释 “6~8 位”（L47） | AS-002、AS-004、AS-024 | UI 校验/生成规则需统一 |
| **C-010** | 标识格式不一致 | `deviceId` 示例存在多种形态：`Light_01`（旧代码/状态报告）、`LIGHT_01`（API 规范）、`GW-9A216D:LIGHT_01`（数据模型 `（INFERRED）` 复合键）、`GatewayDefaults.ID='gateway_01'` | AS-033 L12-18、AS-006 L98、AS-024 L109、AS-012 | 网关身份/设备身份规范未统一；影响持久化与协议匹配 |
| **C-011** | 安全设计张力 | FR-FAM-002 要求邀请凭据经安全通道同步“家庭控制密钥”，使新成员无需 BLE 配网；旧 BLE 规范规定“命令密钥绝不通过 BLE 发送”且 HMAC secret 为“App↔网关”配对语义 | AS-002 L66-69 vs AS-027 L133 | 成员密钥交付机制（谁来托管/如何加密传输）未定义；影响安全模型设计 |
| **C-012** | 敏感/运行假设冲突 | 旧 `GatewayDefaults.LOCAL_IP='192.168.1.88'` 硬编码默认值、旧 UI 允许手动填写 IP/端口；新发现流程要求“不得按广播名/邻居顺序猜测身份”（AS-027 L143） | AS-033 L19-25、AS-037（SettingsPage L555 端口输入）vs AS-027 L143 | 手动 IP 兜底与新绑定安全规则的边界需澄清 |
| **C-013** | 新鲜度不确定 | 10 份主文档（PRD/架构/UI/API/数据/规范）均无版本号/生效日期头；仅内容可推断（协议 v2、2026 示例日期）；原应用代码头部 Created 2026-07-17，原项目公开发布 2026-07-19（wp-000 报告） | 各文档首部；wp-000 报告 | 无法确认文档之间的“最新版”关系；验证时须以字段/流程交叉一致性代替版本比对 |
| **C-014** | 未提供内容 | `input/uml`、`tests`、`project`、`competitors`、`references`、`other` 六目录为空（仅 `.gitkeep`）；无 UML、无既有测试报告、无商业背景/竞品/参考资料 | AS-054；`find input -type f` 全量清单 | 无本仓库 UML/测试证据；模型与测试工件需从头规划（或注明不需要） |

**不可读文件**：无。**重复**：见 C-008。**过时**：见 C-003、C-007。**不确定**：C-013，以及所有标注 `（INFERRED）` 的结论。

---

## 7. 敏感内容检查结果

| 检查 | 方法 | 结果 |
|---|---|---|
| 私钥/证书材料 | 模式扫描 `BEGIN *PRIVATE KEY`、`*.pem` 内容等 | **0 命中** |
| 云/API 凭据 | AWS Key 模式、`password=/token=` 赋值模式扫描 | **0 命中** |
| 公开测试密钥（非真实凭据，需保留标注） | 逐文件确认 | `input/existing/tools/gateway_contract_server.py` L47 `PUBLIC_TEST_SECRET="YaoCore-Contract-Secret-v2"`（标注开发仿真专用，L12-19/L224 输出 `DEV-ONLY`）；`input/api/protocol/hmac-sha256-test-vectors.json`、`response-auth-test-vectors.json`、`discovery-request-auth-test-vectors.json`、`module-hmac-test-vector.json` 中的 secret 均为**公开测试数据**（文件内显式警告）；`derive_module_key.py` 以 getpass 隐藏输入派生真实密钥，不入库 |
| Wi-Fi/PoP/IoTDA 真实凭据 | 全文扫描 | 未发现；`input/existing/docs/隐私与本地配置.md`、用户手册均明确此类值不得入库 |
| 报告安全性 | 本清单仅记录路径与性质，未复制任何疑似敏感值 | 合规 |

结论：`input/` 与仓库脚手架中**未发现真实密钥/生产凭据/个人隐私数据**；已发现的“密钥”均为显式标注的公开测试向量，风险为误用而非泄露（建议保留其 `PUBLIC TEST` 标注与使用禁令）。

---

## 8. 建议的下一步验证或澄清

> 仅给出最小必要动作，不指定固定 Agent 链。

### 8.1 建议优先验证（Artifact Validation Gate 输入）

1. **主文档一致性验证**：以 C-001/C-002/C-005/C-006 为清单，对 REQ-001/ARCH-001/API-001/PROTO-001/DATA-001/UIUX-001 做交叉一致性检查并给出权威裁定建议（schema/README 与 PRD 谁优先、加密模式范围、房间映射）。
2. **规范归一化**：将 AS-025 + config/project.md 约束归一化为带来源引用的 Project Constraints（STD-001），供实现与评审统一使用。
3. **契约测试可运行化**：对 AS-040 中纯协议层测试（gateway_contract/test_app_response_auth/external_module_protocol + ble 的向量部分）做路径适配试跑，验证 `input/api/protocol` 自洽性——注意不得在未授权时改动工具内容。
4. **旧代码行为挖掘**：以 LEGACY-001 为输入提取行为契约（错误语义、默认值、防乐观控制语义），一律标注 `UNVERIFIED（INFERRED）`，供实现与测试参考。

### 8.2 需要澄清的事项（Clarification Gate 候选，按影响排序）

1. **LAN 安全通道 v1 范围（C-002）**：AES-256-GCM 载荷模式（PRD/数据模型，但不在协议 v2 schema）与本地 HTTPS pinning（协议 README）谁是实现目标？是否两者都要？——影响安全实现、报文字段与契约测试。
2. **字段命名权威（C-001）**：`online/power/open/targetTemp`（schema）与 `isOnline/powerStatus/...`（API 规范示例）以哪个为准？——影响数据模型与序列化。
3. **房间/家庭与网关协议边界（C-005/C-006）**：App 侧 familyId/roomId 是否为纯本地实体（网关仅感知 roomName 字符串）？改名/换房是否需要下发网关？——影响数据流与协议扩展。
4. **成员密钥交付机制（C-011）**：邀请凭据如何安全同步家庭控制密钥（无 BLE 前提）？——影响安全模型与联网安全设计。
5. **旧文档版本面处置（C-003）**：AS-027 中 API 22 权限/MTU 细节与 ESP-IDF 版本引用，哪些仍按现行 HarmonyOS NEXT 基线执行？——影响配网实现细节。

### 8.3 已可确认的结论（低风险）

- demo HTML 无交互逻辑（C-004），按 config/project.md L66 的既有定位，仅作视觉参考，无需补救动作。
- 六类空目录（AS-054）作为“未提供”事实记录；是否需要 UML/竞品等工件由规划阶段决定。
- 原应用代码可作为重构基线与行为证据，但其缺失 Family/Room/Mock/AES-GCM 属真实缺口而非“文件未找到”。

### 8.4 覆盖限制重申

本次 Intake 的逐行置信范围见 §1.3；所有未逐行审阅的代码内部逻辑、未运行的工具与未打开的媒体文件，其相关结论均保持 `UNVERIFIED`/`（INFERRED）`，不得直接作为实现或验证依据。

---

*本报告为 Project Intake 产物（Producer: agent:asset-analyst），供 Artifact Validation Gate 与后续 Gap Analysis / 交付规划消费。*
