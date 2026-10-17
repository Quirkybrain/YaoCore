# 项目约束基线（Project Constraints v1.0）

- **Artifact ID**: PROJECT-CONSTRAINTS-001
- **Producer**: agent:solution-architect
- **Type**: Project Constraints（归一化规范，供实现与评审统一引用）
- **Status**: Proposed（待 G-004 门禁批准）
- **Date**: 2026-10-17
- **Task**: `wp-004-contracts`（task 分支 `task/wp-004-contracts`，父分支 `feat/yaocore-app`，base commit `54c1d786`）
- **Workflow**: STANDARD / GATED_AUTO
- **归一化流程**: 按 `input/standards/README.md` L27（"Project Intake 会发现这些来源，分析/架构责任会将目标相关内容统一整理为带来源引用的 Project Constraints"）执行；来源文档不重写、不复制全文，只做**带路径+行号的约束抽取**。
- **来源**（全部为冻结输入或已批准语料）：
  1. `input/standards/ArkTS_Coding_Standards.md`（STD）
  2. `config/project.md`（CFG）
  3. `input/existing/docs/隐私与本地配置.md`（PRIV，安全红线）
  4. `input/existing/docs/BLE配网设计.md`（BLE，安全与配网纪律）
  5. `input/api/protocol/README.md` + `input/api/protocol/*.schema.json`（PROTO，协议纪律）
  6. `docs/internationalization.md`（INT）+ STD L26-28（i18n 规范）
  7. 已批准 ADR/契约基线（ADR-001..004、`contract-baseline.md`）中**从上述来源派生**的约束
- **使用方式**：实现与评审引用**本文件的约束 ID**（如 `SC-03`、`AC-11`），不再各自重新解释原始规范；约束变更须走 ADR/修订并更新本文档。

---

## 1. 语言、平台与工程基线

| ID | 级别 | 约束 | 来源 | 验证方式 |
|---|---|---|---|---|
| PL-01 | Must | 开发语言 ArkTS（TypeScript 超集，遵循 HarmonyOS 静态类型强化规范） | STD L5 | 构建通过（hvigor + ArkTS 编译） |
| PL-02 | Must | 运行环境 HarmonyOS NEXT API 14 / targetSdkVersion 26.0.0 及以上 | STD L6；CFG L32/L42/L54 | 构建配置核对 |
| PL-03 | Must | 构建链 DevEco Studio + Hvigor + ohpm | STD L7；CFG L39-40 | 构建日志 |
| PL-04 | Must | 开启严苛类型检查；**禁止**非受控 `any` | STD L8 | 静态检查/评审 |
| PL-05 | Must | 所有外部 JSON 与协议报文使用明确 `interface`/`class` 反序列化与结构校验 | STD L8 | 代码评审 + DTO 单测 |
| PL-06 | Must | 分层：UI（`pages/`、`components/`）只建视图树与数据绑定；ViewModel 管状态与派发；Service 管业务/系统 API/协议解析 | STD L22-24 | 代码评审（依赖方向） |
| PL-07 | Must | 架构分层遵循 MVVM 与单向依赖（表现/状态管理/业务仓储/适配/传输五层） | CFG L51；AR L42-99 | 详细设计与评审 |
| PL-08 | Should | 连续控制节流合并（~55ms）与多品牌适配器解耦 | CFG L51 | 单测/评审 |
| PL-09 | Must | 测试栈：Hypium 单元测试 + 协议契约测试 + Mock 仿真（实机测试由用户自行进行） | CFG L41/L55/L67；PRD L17-18 | 测试报告 |

## 2. 安全红线（Security Constraints）

> 编号 `SC-*` 为评审门禁的强制检查项；任何违反必须阻断 Gate 或走书面豁免（§13）。

| ID | 级别 | 约束 | 来源 | 验证方式 |
|---|---|---|---|---|
| SC-01 | Must | 公开仓库只保存源码、协议、无秘密模板与可复现构建基线；Wi-Fi 凭据、设备密钥、云端 Secret、签名材料与现场网络信息只存在于开发者电脑/手机安全存储/实体设备 | PRIV L3 | 仓库扫描 + 评审 |
| SC-02 | Forbidden | 禁止提交：`gateway/esp32s3m/sdkconfig`、`devices/**/config.h`、`/build-profile.json5`、`signing/`、`*.cer/*.p12/*.pem/*.key`、`.env`、`*.token`、`*.secret`、`.hvigor/`、`**/build/`、`dist/`、`*.hap/*.bin/*.elf`、`managed_components/` | PRIV L7-15 | 提交前检查（见 SC-07） |
| SC-03 | Must | 协议目录中的测试密钥必须标注 `PUBLIC_TEST_SECRET` 且**永不**用于真实设备 | PRIV L17；README L18-27 | 夹具代码审查 |
| SC-04 | Must | 每台网关使用独立 PoP 与独立 App/网关 HMAC 密钥（≥16 字节）；不得共用、不得由 MAC 推导 | PRIV L37；BLE L153 | 配网/密钥流程评审 |
| SC-05 | Must | PoP 与局域网 HMAC 密钥用途分离，不得复用 | BLE L154 | 代码/设计评审 |
| SC-06 | Must | Wi-Fi 密码、PoP、会话密钥仅保存在局部临时内存，用后立即置空覆盖；**禁止**写入日志、持久化数据库或前端异常文本；设备私钥同样禁止 | STD L62-64；BLE L155 | 代码评审 + 内存生命周期单测 |
| SC-07 | Must | 提交前执行：`git status --short --ignored`、`git check-ignore` 抽查、`git diff --cached --name-only` 核查；暂存列表不得出现密钥/证书/HAP/固件/构建目录/抓包 | PRIV L49-58 | CI/评审记录 |
| SC-08 | Must | 秘密一旦进入历史：立即轮换 Wi-Fi/PoP/HMAC/云端 Secret/签名凭据，必要时 `git filter-repo`；仅删除最新提交不足以使旧秘密失效 | PRIV L60-66 | 事件流程 |
| SC-09 | Must | 秘密存储边界：泄露即可获控制能力或冒充身份的值 → **Asset Store**（`@ohos.security.asset`，`DEVICE_FIRST_UNLOCKED`）；公开值/可由 Asset 重建的路由元数据 → Preferences/RDB；Wi-Fi 密码/PoP 永不落盘 | ADR-002 §8.3；归档 `SecureStorageService.ets` L18-19/L35/L44；PRIV | 存储设计评审 |
| SC-10 | Forbidden | 禁止明文凭据传输（含：为省事在日志/异常/遥测中携带秘密；在无 TLS/GCM 的通道上传输新增密钥） | CFG L50；ADR-002 §8.4 | 评审 + 测试 |
| SC-11 | Must | 生产构建必须拒绝开发桩响应：`X-YaoCore-Simulator: DEV-ONLY`（大小写不敏感）与 `DEV_SIMULATOR_ONLY`；Mock/仿真器不得出现在生产路径；不提供用户可开的开发者模式 | ADR-004 §7.1；`网关接口协议.md` L11；README L224-226 | 单测（拒收路径）+ 评审 |
| SC-12 | Must | 密钥/成员配置存放在系统级安全首选项；App 删除网关仅解除本机绑定并清除本机安全存储（不擦除实体网关） | 需求 L153；PRIV L70 | 设计评审 |
| SC-13 | Must | 局域网控制必须满足真实执行确认：响应验签 + correlation（`request_id:seq`）匹配 + `result_code==0` + `reported_state` 完整；HTTP 2xx 或缓存变化不构成确认 | README L183-189；`网关接口协议.md` L17-26；PRD L117-118 | 契约测试 + 评审 |
| SC-14 | Forbidden | **禁止虚构成功**：未收到网关/云端真实 ACK 前不得显示成功状态（三态 PENDING/COMMITTED/REVERT 必须真实驱动） | CFG L50；PRD L9；UIUX L151-186 | 单测 + 评审 |
| SC-15 | Must | 签名比对必须常数时间；签名/时间戳/nonce 校验失败一律 fail-closed，不得降级、不得跳过 | STD L60；README L86-87/L102-103 | 代码评审 + 契约测试 |
| SC-16 | Must | 家庭邀请凭据按 D-008 离线加密设计执行（容器版本化、AEAD、单次/短时、撤销=轮换的真实现），所有安全边界（无用户级鉴权、GUEST 房间限制非密码学边界）必须如实告知用户 | ADR-003 §4/§6.3/§8 | 评审 + i18n 文案检查 |

## 3. 协议与互操作约束

| ID | 级别 | 约束 | 来源 | 验证方式 |
|---|---|---|---|---|
| PR-01 | Must | 线格式以 schema 家族为权威；出站一律 schema 命名；内部模型命名仅经映射层（`contract-baseline.md` §2） | ADR-001 §1；`contract-baseline.md` §1 | DTO 单测 + 契约测试 |
| PR-02 | Must | canonical 串精确匹配（无末尾换行；value 单 JSON 原子编码规则） | README L62-87 | 4 向量单测 |
| PR-03 | Must | 时间窗 ±120s、nonce 300s 缓存、精确重传幂等、冲突 409/`1005`、失败不消耗 nonce | README L89-103 | 契约测试 |
| PR-04 | Must | 时间戳统一 UTC `yyyyMMddTHHmmssZ`，秒级、无时区偏移 | README L32-33 | 单测 |
| PR-05 | Must | `key_id` 为版本标签、与密钥材料解耦；v1 恒为 `app-key-v1` | README L105-107 | 常量审查 |
| PR-06 | Must | 绑定时序：BLE 名称/MAC/UDP/mDNS 仅定位；仅当已验签 `GET /discover` 的 `gatewayId` 与 Security1 会话内 `yaocore-id` 完全一致才允许绑定 | README L48-53；BLE L143 | 集成测试（仿真器） |
| PR-07 | Must | 身份端点 fail-closed：`additionalProperties:false` 违规、常量不符、网关名越界 → `PROVISIONING_IDENTITY_INVALID` 并终止配网 | ADR-001 §3；identity schemas L6-25 | 单测 |
| PR-08 | Must | 错误语义使用统一表（`contract-baseline.md` §4.1）；未知 `result_code` 一律判失败并记录偏差 | ADR-001 §2 | 单测 |
| PR-09 | Must | 云命令 `paras` 仅含 10 个 CamelCase 字段；`object_device_id` 仅允许顶层、**禁止**进入 `paras`；`Value` 为紧凑 JSON 原子文本 | `cloud-command.schema.json` L5-76；README L164-181 | schema 校验/单测 |
| PR-10 | Must | 云命令完成判定必须基于"不早于命令时刻的状态/影子"（`LastRequestId/LastSeq` 匹配 或 `DeviceInventoryJson` 匹配）；IoTDA 受理不构成确认 | `contract-baseline.md` §7.1；`网关接口协议.md` L66；SR L47-51/L73-101 | 云契约测试（Mock） |
| PR-11 | Must | 不再改写 `input/` 冻结契约；任何 schema/文档变更走勘误与补丁提案（`contract-baseline.md` §5.2/§10） | `contract-baseline.md` §1；任务约束 | 评审 |
| PR-12 | Must | BLE GATT 严格串行；`0x2901` 缺失/重名/端点缺失即终止（不得按 Characteristic 顺序猜测）；不得降级 Security0 或明文下发凭据 | BLE L43-45/L58 | 代码评审 + 仿真测试 |
| PR-13 | Must | 配额与可移植性：BLE 扫描 10s 无结果给提示；绑定探测有限次数 + 指数退避；MTU 目标 512、下限 247 | BLE L134/L143/L145 | 实现评审 + 测试计划 |
| PR-14 | Should | 协议扩展（GCM、v2.1 身份、房间/ACL 等）只允许以版本化提案存在，不得在 v1 引入可运行分支 | ADR-002 §5/§3；ADR-004 §1.3 | 代码评审 |

## 4. 数据与隐私约束

| ID | 级别 | 约束 | 来源 | 验证方式 |
|---|---|---|---|---|
| DP-01 | Must | 房间/设备以不变 ID（`roomId`/`deviceId`）索引；改名/换房/删除为本地动作，不改 ID、不下行网关 | 需求 L78-95；ADR-004 §1/§2 | 单测（无网络请求断言） |
| DP-02 | Must | 房间删除：设备 `roomId=""`、`isUnassigned=true`、`isEnabled=false`，进入未分配池；**禁止**级联物理删除设备 | 需求 L86-89；数据模型 L165-179；UIUX L126-147 | 单测 |
| DP-03 | Must | 设备删除仅清理本地引用；已删设备经 tombstone（dismissed）不再自动重新纳管 | FR-ROOM-005；ADR-004 §2.1-3 | 单测 |
| DP-04 | Must | 用户密码采用 PBKDF2\|SHA256 加盐哈希 120,000 次；邀请凭据具备有效期，过期作废 | 需求 L152 | 单测 |
| DP-05 | Must | 家庭/成员/密钥的跨设备一致性在无服务器模型下为"接触式收敛"；UI 不得暗示实时同步或成员在线状态（v1 声明性限制） | ADR-003 §5.2/§5.4；D-010 | UI 文案评审 |
| DP-06 | Must | GUEST 的房间范围限制是 App 策略而非密码学边界，必须在管理员与评审可读处声明 | ADR-003 §6.3 | 评审 + UI 文案 |

## 5. 国际化（i18n）约束

| ID | 级别 | 约束 | 来源 | 验证方式 |
|---|---|---|---|---|
| I18N-01 | Must | 单一代码库铁律：严禁为不同语言维护多套业务代码/分支 | INT L16-18 | 评审（分支审查） |
| I18N-02 | Forbidden | 业务逻辑、控制层、组件模板中**禁止硬编码**任何用户可见文本 | INT L20-23；STD L27 | 静态扫描门禁（见 i18n 设计 §6） |
| I18N-03 | Must | 语言资源按 locale 独立文件隔离；禁止单巨型文件杂糅 | INT L25-36 | 资源布局审查 |
| I18N-04 | Must | 语义化键（点分隔命名空间）；参数插值 `{name}`；**禁止**用 `+` 拼接句子 | INT L38-48 | 评审 + 键位检查 |
| I18N-05 | Must | 必须配置 fallback（缺 key 平滑降级，不得抛异常/空白）；key 集合跨 locale 100% 对齐 | INT L50-52/L66 | parity 脚本 |
| I18N-06 | Must | 语言入口：跟随系统 / 简体中文（zh-CN）/ English（en-US），即时生效 | 需求 L139；架构 L56；UIUX 补丁 P-10 | 手动/UI 测试 |
| I18N-07 | Should | UI 容器预留 20%~40% 文本膨胀空间；避免固定像素宽度按钮 | INT L64 | UI 评审 |
| I18N-08 | Must | 颜色定义在 `color.json` 并经 `$r('app.color.…')` 引用（含暗黑模式适配） | STD L28 | 资源审查 |

## 6. 性能与响应约束

| ID | 级别 | 约束 | 来源 | 验证方式 |
|---|---|---|---|---|
| PF-01 | Must | 局域网控制 RTT **p95 ≤ 500ms**（测量口径由 TEST-001 定义后才可作为门禁数据） | CFG L52；需求 L156；`WP3` §3.7 | TEST-001 计时口径 |
| PF-02 | Must | 连续滑动控制 55ms 节流合并；TouchUp 强同步；UI 不卡顿 | UX L190-195/L247；需求 L157 | 单测（节流器）+ 自测 |
| PF-03 | Should | 页面切换 60fps/120fps | 需求 L158 | 性能测试（口径待定） |
| PF-04 | Must | BLE 扫描/连接低时延且带防抖去重（10s 提示、有限退避） | CFG L52；BLE L134/L143 | 仿真/单测 |

## 7. 兼容性与范围约束

| ID | 级别 | 约束 | 来源 | 验证方式 |
|---|---|---|---|---|
| CP-01 | Must | 兼容 HarmonyOS NEXT API 14 及以上 | CFG L54 | 构建配置 |
| CP-02 | Must | 本仓库仅承载 App 源码：**禁止**包含 ESP32 C 固件构建链；网关以外部设备 + 协议契约 + Mock/Simulator 桩存在 | CFG L50/L55/L64 | 仓库审查 |
| CP-03 | Forbidden | 不得假定或阻塞要求 Agent 进行物理真机测试；工程门禁 = 静态检查、ArkTS 构建、单元测试、契约/Mock 测试 | CFG L50/L67；PRD L17-18 | 流程记录 |
| CP-04 | Must | v1 设备支持范围：door/light/sensor/ac 完整；其余类型只读降级（`contract-baseline.md` §8.1） | `contract-baseline.md` §6.2/§8.1 | 评审 + 测试 |
| CP-05 | Must | 云路径范围（配置/命令/影子确认；Token 手工管理）按 `contract-baseline.md` §7.1/§8.2 执行 | 同上 | 设计评审 |
| CP-06 | Should | 旧文档（BLE/网关接口/模块协议）的**协议语义**适用；其中的 API 级别/构建陈述按当前 API 14+/targetSdk 26 重新验证 | `contract-baseline.md` §8.4 | 实现期核对 |

## 8. 工程流程约束（来自项目配置，供协作引用）

| ID | 级别 | 约束 | 来源 |
|---|---|---|---|
| WP-01 | Must | Target Stage = `implementation`；Workflow = STANDARD；Execution = GATED_AUTO；未达目标前不得越级进入后续阶段 | CFG L17-19 |
| WP-02 | Must | Git 分支/合并/托管规则遵循 `config/git-policy.json`（缺省 `git-policy.default.md`）；任务分支与多智能体合并步骤见 `docs/git-collaboration.md` | CFG L59 |
| WP-03 | Must | 本基线及后续实现的变更走 ADR/修订流程；契约条目变更须触发 Change Impact（`FRAMEWORK_ARCHITECTURE.md` 的 Artifact 纪律） | 框架；本任务约束 |

## 9. 约束 → 与 ADR/契约基线的交叉引用

| 约束族 | 核心裁定来源 |
|---|---|
| SC-01..SC-08（秘密治理） | PRIV 全文；本文件 §2 |
| SC-09（存储边界） | ADR-002 §8.3 |
| SC-11（DEV-ONLY） | ADR-004 §7.1；`contract-baseline.md` §8.6 |
| SC-13/SC-15（确认与验签） | ADR-001 §2；ADR-002 §2/§6 |
| SC-16（离线凭据） | ADR-003 §4/§6/§8 |
| PR-01..PR-10（协议纪律） | ADR-001 §1/§2/§5；`contract-baseline.md` §2/§4/§7 |
| DP-01..DP-06（数据/隐私） | ADR-004 §1/§2/§4/§6；ADR-003 §5/§6 |
| I18N-01..I18N-08 | `i18n-resource-design.md` |
| CP-04/CP-06（范围与旧版本面） | `contract-baseline.md` §8.1/§8.4 |

## 10. 例外与豁免（Exception Process）

- 原始标准建议的豁免授权方式（`input/standards/README.md` L24）在本项目落为：**不得由实现者自我豁免**；例外必须由 Orchestrator 在对应 Gate 记录（约束 ID、理由、范围、有效期、补偿控制），重大安全例外（SC-10/SC-13/SC-14/SC-15）另需用户决策；
- 任何豁免不改变 `input/` 原文，仅记录在本约束基线的增补条目或 Gate 证据中。

## 11. 冲突处理原则

1. 来源优先级：用户当前明确要求 > `config/project.md` > 已验证项目资产/标准 > 持久化工件 > 框架结构文档 > 低风险假设（框架 Source of Truth）；
2. 同一域内的规范冲突（如 PRD vs UIUX 的码长）以本约束基线与其上游 ADR 的裁定为准（例：C-009 → 6 位，ADR-004 §3）；
3. 任何冲突不得静默解决：登记勘误/提案（`contract-baseline.md` §5.2/§10）后按裁定执行。

---

*Project Constraints v1.0 结束。评审引用约束 ID；任何来源文档版本变化应触发本文件的 STALE 重评（Change Impact）。*
