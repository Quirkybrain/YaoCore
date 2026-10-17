# YaoCore 维护计划（MAINTENANCE-PLAN-001）

- **Artifact ID**: MAINTENANCE-PLAN-001
- **Producer**: agent:technical-writer
- **文档版本**: MAINTENANCE-PLAN-001 v1.0（初始版本，T-21）
- **Type**: Maintenance Plan / Backlog / Risk Acceptance Register / Verification Matrix
- **Status**: ACTIVE（T-21 交付；供 G-013/G-014 与后续维护轮次消费；不授予任何 Gate PASS）
- **Date**: 2026-10-18
- **Task**: `wp-086-docs`（T-21；task 分支 `task/wp-086-docs`，父分支 `feat/yaocore-app`，base commit `13dc839`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`
- **Upstream**: `README.md` @ T-21 基线；`artifacts/60-testing/test-report.md`（TEST-REPORT-001，T-19）；`artifacts/70-review/final-system-review.md`（REV-001-FINAL-SYSTEM，T-20）；`artifacts/60-testing/tooling-cleanup-report.md`（TOOLING-CLEANUP-REPORT-001，T-20）；`artifacts/20-architecture/contract-baseline.md` §5.2/§8.7/§10/§11；`artifacts/20-architecture/project-constraints.md`；`artifacts/40-detailed-design/des-001a-foundation-transport.md` §27.6；`config/project.md`
- **写范围**: `README.md`、`artifacts/80-maintenance/`。未修改代码、构建配置、契约、测试或 `input/`。
- **权威边界**: 本计划只登记待办、责任、风险与验证矩阵；不改变需求、契约、ADR、测试结论或 Gate 判定。`input/` 为冻结语料，**不得直接修改**；所有补丁 / 勘误均以提案形式登记，由对应 owner 走 Change Impact。

> **结论先行**：v1 代码级交付已具备可复现的构建、Host 测试、契约 / 仿真器、i18n 与分层证据；剩余工作集中在**真实设备 / 真实网络验证（用户执行）**、**端口位置迁移与契约清理**、**i18n 历史文案收口**、**固件协同项**与**文档维护**。本计划不把任何 `BLOCKED` / `MOCK_ONLY` / `PENDING` 项写成完成，也不把 `check_layering` 的 0 violation 解释为端口位置合规。

---

## 1. 目的、范围与权威

1. 保持 `README.md` 与当前代码、测试和评审证据一致，避免再次出现“脚手架 / Hello World”式过期描述。
2. 把 T-19/T-20 的 `BLOCKED` / `UNAVAILABLE` / `MOCK_ONLY` / 已接受风险，以及交付计划中的 P2 待办，转成可跟踪、有 owner、有触发条件的维护条目。
3. 建立统一的文档版本 / 修订机制（C-013），使需求、契约、设计、测试、评审与 README 的变更可追溯。
4. 明确设备 / 真实环境验证由用户执行；本仓库的工程门禁只覆盖构建、静态检查、Host 测试、契约测试与 Mock / 仿真。

**权威顺序**（沿用 `config/project.md` 与契约基线 §1）：

1. 用户当前明确请求与决策；
2. `config/project.md`；
3. 已验证项目资产与标准（`input/`）；
4. 持久化 Artifacts、Decisions、State；
5. `FRAMEWORK_ARCHITECTURE.md` / `design.md`；
6. 已记录的低风险假设与惯例。

发生冲突时不得静默择一：登记勘误 / 提案，交给对应 owner 裁定并触发 Change Impact。

---

## 2. 版本与修订机制（C-013）

### 2.1 文档头规范

所有受维护的文档（README、契约、DES、测试计划 / 报告、评审报告、维护计划）在页首使用统一元数据：

```text
- 文档版本: <NAME> v<major>.<minor>.<patch>
- 生效日期: YYYY-MM-DD
- 维护者: <role / agent>
- 适用 revision: <git commit / Gate revision>
- 变更记录: <一句话摘要；详细条目见文末或独立变更记录>
```

要求：

- `适用 revision` 必须是可解析的 commit 或 Gate 记录；禁止写“最新”“当前”等不可验证表述。
- 评审报告与测试报告以**被评审 / 被测试 revision** 为准，不用作者工作树时间替代。
- 文档版本号与产品 `versionName` 解耦；应用版本以 `AppScope/app.json5` 为准。

### 2.2 版本号与变更类型

| 变更类型 | 版本位 | 示例 | 处理 |
|---|---|---|---|
| 契约 / 范围 / 安全语义不兼容 | major | 设备范围、错误码语义、LAN 安全通道变更 | ADR + Change Impact + 全量回归 + Gate |
| 新增能力 / 结构 / 章节 | minor | 新增维护条目、验证矩阵、扩展提案 | Change Impact + 相关测试 / 检查器 |
| 勘误 / 文字 / 链接 / 计数修正 | patch | 数字与证据文件不一致、失效引用 | 直接修订并记录来源 |
| 纯格式 | patch | 排版、术语统一 | 可合并到最近一次修订 |

**协议契约**不走文档 minor 版本原地改写：按 ADR-002 §3 / 契约基线 §8.7，使用 `protocolVersion` 递增 + 新 schema 文件（例如 v2.1）；已发布语义不得原地覆盖。

### 2.3 修订流程

1. **提出**：维护者登记勘误（E-*）或补丁提案（P-*），附来源、目标位置、理由、影响范围。
2. **裁定**：`solution-architect` 对契约 / 架构类提案裁定；产品范围类由 Orchestrator / 用户裁定。
3. **Change Impact**：识别受影响的 Requirements、Contracts、DES、组件、测试、检查器、README 与维护计划；受影响项标 `STALE` / `UNVERIFIED`。
4. **实施**：在授权范围内更新文档 / 代码 / 测试；`input/` 只接收提案，不直接改写。
5. **验证**：重跑受影响命令；报告 / 计划 / README 的数字必须与证据文件逐字一致。
6. **记录**：更新版本头、变更记录、Gate 证据与 Checkpoint；必要时新增 ADR 或修订 ADR 状态行（需 Change Impact）。

### 2.4 文档清单与责任

| 文档 | 当前基线 | 维护 owner | 下次触发 |
|---|---|---|---|
| `README.md` | README-001 v1.0 @ T-21 | `technical-writer` | 代码 / 契约 / 命令 / 设备状态变化；每个 Gate 前 |
| `artifacts/20-architecture/contract-baseline.md` | CONTRACT-BASELINE-001 v1.0（G-004 批准） | `solution-architect` | P/E 提案、固件协同、协议变更 |
| `artifacts/20-architecture/project-constraints.md` | PROJECT-CONSTRAINTS-001 v1.0 | `solution-architect` | 新约束 / 豁免 / 风险评估 |
| `artifacts/20-architecture/adr-001..004` | Accepted（G-004） | `solution-architect` | 契约 / 安全 / 数据边界变化 |
| `artifacts/40-detailed-design/des-001a/b` | G-006 / G-007 | `solution-architect` | 端口迁移、增量契约、Change Impact |
| `artifacts/60-testing/test-plan.md` / `test-report.md` | TEST-001 / TEST-REPORT-001 | `test-engineer` | 测试范围 / 运行器 / 证据变化 |
| `artifacts/70-review/*` | 各任务评审 | `quality-reviewer` | 新 revision / 复审请求 |
| `artifacts/80-maintenance/maintenance-plan.md` | 本文件 | `technical-writer` | 上游变更、固件协同、安全修复、每个 Gate 前 |

### 2.5 更新节奏与触发条件

| 触发 | 动作 | owner | 时限 |
|---|---|---|---|
| 需求 / `input/` / 契约 / ADR 变更 | Change Impact；标 `STALE`；重算最小必要路径 | `solution-architect` + Orchestrator | 下一个任务派发前 |
| 代码合并影响命令 / 行为 / 范围 | 重跑命令；更新 README 状态、证据表、限制 | `technical-writer` + 实现 owner | 合并后、下一个 Gate 前 |
| 固件 v2.1 / TLS / `FC-*` 就绪 | 更新安全声明、P-TLS-PIN 证据、固件跟踪表 | `solution-architect` + 用户 | 固件可用后 1 个维护轮次 |
| 安全修复 / 秘密泄露 / 高危缺陷 | 立即升级；README 安全声明 + 风险登记 + 回归 | Orchestrator + 安全 owner | 立即（P0） |
| SDK / hvigor / ohpm / codelinter 升级 | 重跑全部验证命令；更新前置条件与基线值 | 实现 owner + `test-engineer` | 升级任务内 |
| 每个 Stage Gate / release 前 | 全量文档核对、版本头、证据对齐、Checkpoint | `technical-writer` + Orchestrator | Gate 前 |
| 常规卫生 | 失效链接、计数、术语、未使用告警 triage | `technical-writer` | 建议每 30 天；不替代 Gate 检查 |

> 节奏是维护建议，不是产品承诺；任何 Gate 仍以实际证据和 Definition of Done 为准。

---

## 3. 待办清单与 owner

### 3.1 优先级定义

| 优先级 | 含义 |
|---|---|
| **P0** | 安全 / 数据 / 契约阻断；必须立即处理，未关闭不得进入下一 Gate |
| **P1** | 进入下一个 Stage Gate / release 前必须关闭或有书面风险接受 |
| **P2** | 计划内工程债务；不阻断 v1，但应排入后续维护轮次 |
| **P3** | 卫生 / 体验 / 文档清理；可批量处理 |

### 3.2 端口位置迁移（DES-A §27.6.3，阶段 P1-P4）

**现状**：DES-A 名义位置为 `entry/src/main/ets/contracts/**`，仓库中尚无 `contracts/`；端口实际位于 `common/types/Ports.ets`、`service/{storage,crypto,ble,gateway,cloud,i18n,scene}/**`、`repository/{DomainPorts,GatewayPorts}.ets`、`viewmodel/ViewModelPorts.ets` 等。T-20 已把 17 条 `port_location_exceptions` 写入 `tools/contract/layering_allowlist.json`，并让检查器读取该登记；**迁移本身尚未执行**。

| 阶段 | 内容 | 状态 | owner | 验收 / 关闭条件 |
|---|---|---|---|---|
| **P1** | 纯端口文件迁移到 `contracts/**`：`common/types/Ports.ets`、`service/storage/{RdbStore,PreferencesStore,SecretStore,SecretDraftPort,MigrationPort}.ets`、`service/cloud/CloudPorts.ets`、`service/i18n/I18nPorts.ets`、`service/scene/SceneTimerPort.ets`、`service/crypto/CryptoPort.ets`、`repository/{DomainPorts,GatewayPorts}.ets`、`viewmodel/ViewModelPorts.ets` | **未开始** | `solution-architect`（布局）+ `implementation-engineer`（迁移） | 方法名 / 参数 / 返回 / 错误语义不变；imports 更新；全量回归；D-03 获得真实输入 |
| **P2** | 拆分混合文件：`BleProvisioningPorts.ets`、`GatewayTransportPorts.ets`、`DiscoveryModels.ets` → `contracts/**`（端口）与 `model/**`（DTO / 枚举）；页面 / VM 改 import `model/**` | **未开始**（依赖 P1） | `solution-architect` + `implementation-engineer` | 13 条 D-12 中值 import 例外可删除；页面不再 import service / repository DTO |
| **P3** | `GattEndpointMap.ets` 迁到 `common/**` / `model/**`，或把 VM 所需常量下沉到 VM 本地 | **未开始**（依赖 P2） | `implementation-engineer` | `GattEndpointMap` 不再被当作端口；检查器无例外 |
| **P4** | 检查器读取 `port_location_exceptions`，未登记路径 / 符号越界 / 非 `accepted-location-exception` fail-closed | **已完成（T-20）** | `test-engineer` | `check_layering` 读取 allowlist；fixture 覆盖合法 / 未登记 / 符号越界 / pending；T-20 证据见 `t20-layering*` |

**关闭标准**：P1-P3 完成后，`port_exceptions_used` 逐条归零，删除 `port_location_exceptions` 条目并更新 DES-A §2.1/§3.7；`check_layering` 仍为 0 violation；Stage Gate 记录“端口位置合规”。**在新的迁移任务完成前，0 violation 不代表位置合规。**

### 3.3 R3-01 / D-12 例外清理

**现状**：T-20 已按 DES-B §2.3/§18.1 把 13 条 `T20-D12-01..13` 状态改为 `accepted`，检查器对 `used && status != accepted` fail-closed；当前 `pending=0`、`exceptions_used=13`。这完成了“登记”，**未完成“迁移”**。

| 项 | 内容 | owner | 优先级 | 关闭条件 |
|---|---|---|---|---|
| D-12 值 import | `FamilyManagePage` 的 `CreateInvitationInput` / `FamilyJoinPhase`；`ProvisioningPage` 的 `BleProvisioningDevice` / `ProvisioningState` / `WifiAp`；`SettingsPage` 的 `CloudTransportState` | `solution-architect` + `implementation-engineer` | P2 | 迁移到 `model/**` 或由架构 owner 正式登记为“页面本地表单状态 / UI 枚举，无 I/O”；删除对应 allowlist 条目 |
| D-12 类型 import | 其余 10 条 `type_only` 的 pages → service / repository 只读 DTO / 枚举 | `solution-architect` | P2 | 纳入 `model/**` 或保留为文件 / 符号级、永不目录级放宽；`exceptions_used` 下降 |
| 检查器回归 | 13 条全部命中且仅命中一次；`pending=0`；`unused_exceptions=[]` | `test-engineer` | P1（已满足） | 每次迁移后重跑 `check_layering` 与 fixture；不得放宽 D-12 规则 |

> 禁止把整目录 `service/**` / `repository/**` 放宽；每条例外必须有精确路径与符号子集。

### 3.4 i18n 596 条迁移

**现状**：`entry/src/test/i18n/legacy-migration.csv` 共 615 条；A 类 606 条中 10 条 `ACCEPTED`，**596 条 `PENDING_REVIEW`**；另有 `B_REWRITE_REQUIRED=11`、`SAFETY_RECHECK=2`。T-18 已新增 326 个净键并按页面语义重写大量 UI 文案（可直接核对 59 条），但**没有**回填 CSV，避免把未人工复核的条目标成 `ACCEPTED`。当前 `--strict-ui` 为 0 blocking，不代表 596 条已全部签署。

| 工作项 | 内容 | owner | 优先级 | 关闭条件 |
|---|---|---|---|---|
| 逐条 triage | 596 条按页面 / 组件 / 技术字符串分类；B 类 11 条重写；C 类 2 条安全复核 | `implementation-engineer` + `technical-writer` | P2 | CSV 每行有明确状态 / 目标键 / 证据；不得批量误标 |
| 回填与 parity | 把已落地的页面文案回填为 `ACCEPTED`；检查 en/zh parity、plural、插值 | `implementation-engineer` + `test-engineer` | P2 | `check_i18n.py --strict-ui` 0 blocking / 0 missing；parity 100% |
| 工具路径 | `T10-EX-01`：检查器仍在 `entry/src/test/i18n/`，未迁移到 `tools/i18n/` | `test-engineer` | P3 | 迁移或正式登记；命令与文档同步 |
| 告警 triage | 16 条 hardcoded（AC 品牌名 / Mock 文案 / 颜色注释）逐条确认非 UI 或移入 allowlist | `implementation-engineer` | P3 | 0 真实硬编码 UI；allowlist 有理由 |

### 3.5 P-01..P-17 补丁提案（契约基线 §10）

> 目标均为 `input/` 文档；**本仓库不直接修改 `input/`**。执行方式为维护轮次中的勘误 / 补丁提案，需 `solution-architect` 裁定并走 Change Impact。P/E 项不阻塞当前代码级 v1 Gate；若涉及契约语义变化，必须升级为 ADR / 契约修订并在 G-014 记录影响。P-06 / P-15 已落地，随协议 / schema 变更回归。

| ID | 目标 | 动作 | 状态 | owner | 优先级 |
|---|---|---|---|---|---|
| P-01 | `Gateway_API_Specification.md` L88-121 | discover 示例按 schema 重写（E-01） | 提案待执行 | `solution-architect` + `technical-writer` | P2 |
| P-02 | `protocol/README.md` L37-41 | “display name” → `gatewayName`；注明两个 `serviceId` 命名空间（E-05） | 提案待执行 | 同上 | P2 |
| P-03 | `Gateway_API_Specification.md` L187-204 | ACK 示例修订（E-02） | 提案待执行 | 同上 | P2 |
| P-04 | `Gateway_API_Specification.md` L215-227 | 结果码表替换为 §4.1 统一表（E-03） | 提案待执行 | 同上 | P2 |
| P-05 | `Gateway_API_Specification.md` L44-45 | 身份示例修订（E-04） | 提案待执行 | 同上 | P2 |
| P-06 | 仿真器 | 生成侧对齐 schema；接受侧宽容声明 | **已落地（T-05）**；随协议变更回归 | `test-engineer` | P2 |
| P-07 | `Gateway_API_Specification.md` L126 | 通道档案表述（P-TLS-PIN / P-HMAC） | 提案待执行 | `solution-architect` + `technical-writer` | P2 |
| P-08 | `Data_and_State_Models.md` §3 | 标注 `EXT-GCM-001` 归档（E-08） | 提案待执行 | 同上 | P2 |
| P-09 | 需求 L67；数据模型 L47 | 邀请码 6 位（E-06） | 提案待执行 | 同上 | P2 |
| P-10 | `UI_UX_Specification.md` L70 | 增加语言入口（C-018） | 提案待执行 | 同上 | P2 |
| P-11 | `Data_and_State_Models.md` L107-120 | 两级标识与存储注释（E-07） | 提案待执行 | 同上 | P2 |
| P-12 | `Data_and_State_Models.md` L26-56 | 成员 / 邀请字段增补（C-017/C-020） | 提案待执行 | 同上 | P2 |
| P-13 | `UI_UX_Specification.md` L151-186 | 门锁到位三态与文案纪律（C-024） | 提案待执行 | 同上 | P2 |
| P-14 | 数据模型 L133/135/144；需求 L126 | 词表 / 单位 / `stateSource` 修订（E-09/E-10/E-11） | 提案待执行 | 同上 | P2 |
| P-15 | 测试资产 | 补建 `product-profile.json`（由 SR 反推） | **已落地（T-05）**，测试资产 | `test-engineer` | P3 |
| P-16 | 主文档页首 | 版本头机制（C-013） | **机制已定义（本计划 §2）**；应用到 `input/` 待维护轮次 | `technical-writer` + `solution-architect` | P2 |
| P-17 | 协议目录 | v2.1 新 schema 文件（`ble-enrollment-identity-request-v2/response-v2`） | 提案待固件协同 | `solution-architect` | P2 |

**共同关闭条件**：提案被裁定 → 在获授权的维护副本 / 下一版本文档中执行 → 更新 `input/` 版本头 → 相关契约 / DES / 测试 / README 同步 → Gate 记录。

### 3.6 E-01..E-12 勘误（契约基线 §5.2）

| ID | 目标 | 勘误内容 | 状态 | owner |
|---|---|---|---|---|
| E-01 | `Gateway_API_Specification.md` L88-121 | discover 示例按 schema 命名 + 补 `generatedAt/security`、删 `keyId` | 待维护轮次 | `solution-architect` |
| E-02 | 同文件 L187-204 | ACK 示例删 `success`、补 `server_time`、按 `deviceState` 修订 | 待维护轮次 | 同上 |
| E-03 | 同文件 L215-227 | 结果码表替换为 §4.1 统一表 | 待维护轮次 | 同上 |
| E-04 | 同文件 L44-45 | `serviceId:"YaoCoreGateway"` + `gatewayName` | 待维护轮次 | 同上 |
| E-05 | `protocol/README.md` L37-41 | 明确 `gatewayName` | 待维护轮次 | 同上 |
| E-06 | 需求 L67；数据模型 L47 | 邀请码改为 6 位 Crockford Base32 | 待维护轮次 | 同上 |
| E-07 | 数据模型 L109；需求 L93 | 两级标识模型（线上裸 id） | 待维护轮次 | 同上 |
| E-08 | 数据模型 §3；API L146-166 | GCM 示例归档为 `EXT-GCM-001` | 待维护轮次 | 同上 |
| E-09 | 数据模型 L133 | 空调 `mode` 7 值词表 | 待维护轮次 | 同上 |
| E-10 | 数据模型 L135 | 风扇 `speed` 单位 = percent 0..100 | 待维护轮次 | 同上 |
| E-11 | 需求 L126；数据模型 L144 | `stateSource` 5 值集合 | 待维护轮次 | 同上 |
| E-12 | `Gateway_API_Specification.md` L126 | 区分 v1 通道档案（HTTP+HMAC / HTTPS+pin） | 待维护轮次 | 同上 |

> 勘误不得改变已批准契约语义；若涉及语义变化，升级为 ADR / 契约修订，而不是勘误。

### 3.7 FC-01..FC-06 固件协同

| ID | 项 | v1 阶段性策略 | 当前状态 | owner | 关闭条件 |
|---|---|---|---|---|---|
| FC-01 | `yaocore-id` v2.1 + TLS 发布 / 轮换 | 无固件时回退 v2.0 → P-HMAC；App 不阻塞 | **FIRMWARE_PENDING** | `solution-architect` + 固件维护者 | 固件 v2.1 可用；真实 TLS pin / P-BLOCKED 设备验证通过 |
| FC-02 | ACK `error_code` 补齐；1008 发出 | App 容忍缺失；1008 预留映射 | **FIRMWARE_PENDING** | 同上 | 真实 ACK 证据；错误码映射回归 |
| FC-03 | `key_id` 版本滚动窗口（`app-key-v1`→v2） | v1 不滚动；材料轮换走 BLE | **DEFERRED** | `solution-architect` | 协议 + 固件 + App 同步变更 |
| FC-04 | 控制密钥轮换固件流程 | BLE 重配为唯一路径 | **DEFERRED** | 同上 | 设备级轮换演练与回滚 |
| FC-05 | 未来扩展：`EXT-LAN-STATE-001`（position/speed/volume）、`EXT-ROOM-STATE-001`、`EXT-FAMILY-COORD-001`、`EXT-ACL-001` | v1 不做；范围声明 §6.2/§8.1 | **OUT_OF_SCOPE（v1）** | `solution-architect` | 新版本 ADR + schema + 组件变更 |
| FC-06 | protocomm 非零 `Status` 细分语义 | 统一 fail-closed 映射；不新增细分 stable code | **FIRMWARE_PENDING** | `solution-architect` + `test-engineer` | 设备验证后决定是否新增细分 |

> 任何“真实 TLS / 机密性 / 扩展设备控制”的完成声明必须等固件就绪；证据标注 `MOCK_ONLY` / `FIRMWARE_PENDING`，不得用 localhost 仿真器替代。FC 项不阻塞 v1 实现，但阻塞相关能力对外宣称完成；每次状态变化都要回写 README 与 §5。

### 3.8 WP2-F04 与测试夹具

| 项 | 现状 | owner | 维护动作 |
|---|---|---|---|
| `cloud/iotda/product-profile.json` 缺失（WP2-F04） | **已补建**为测试资产：`tools/test-fixtures/iotda/product-profile.json`（由 `state-report.schema.json` 反推；`PUBLIC TEST DATA ONLY`） | `test-engineer` | 当 `state-report` / 云命令 schema 变更时同步；不得作为产品运行时资产 |
| 仿真器契约夹具 | `tools/simulator/` 已移植；HTTP + TLS 20/20；证书仅 localhost | `test-engineer` | 随 P-06 / 协议变更回归；证书到期前评估替换 |
| 测试证书 | `tools/simulator/certs/*.pem` 为 T-05 授权测试例外 | `test-engineer` | 不用于真实设备；轮换时更新 SPKI 文档与测试 |

### 3.9 R2 / T-20 残余与工具债务

| ID | 项 | 来源 | 状态 | owner | 优先级 |
|---|---|---|---|---|---|
| M-01 | 未消费组件：`GlassSurface` / `IconButton` / `SliderControl` | T-18 F-15 | Recorded | `implementation-engineer` | P3 |
| M-02 | 云 `effectiveProfile` 未展示 | T-18 F-17 | Partial | `implementation-engineer` | P3 |
| M-03 | 邀请 `usedCount/maxUses`、回执状态、转让候选过滤、GUEST→MEMBER 入口 | T-18 F-21 | Recorded（依赖 C-22 API / 新 i18n 键） | `implementation-engineer` | P2 |
| M-04 | C-23 VM `view.permission` 中途失败不更新（页面已镜像） | T-18 R2-05 | Recorded | `implementation-engineer` | P2 |
| M-05 | `MainShell` 未使用 import；`width('auto')` / 长英文布局无设备证据 | T-18 R2-06 | Open（Low/Info） | `implementation-engineer` | P3 |
| M-06 | T-18 修复报告内部引用失效（`t18-fix-report.md` §1.2 → §3.1） | T-18 R2-08 | Open（Info） | `technical-writer` | P3 |
| M-07 | `tools/build/README.md` 仍描述脚手架时点（“No defects found”、host 测试未建立） | T-21 复核 | **Stale** | `technical-writer` + `implementation-engineer` | P2 |
| M-08 | 测试源码未纳入 lint；无行 / 分支覆盖率 | T-19 §8.2；T-20 §8 | Known gap | `test-engineer` | P2 |
| M-09 | 25 条 lint warning（23 条自定义组件性能建议 + 2 条 loop 警告） | T-20 §8 | Accepted（非阻断） | `implementation-engineer` | P3 |
| M-10 | `T10-EX-01` i18n 检查器路径未迁移 | T-10/T-20 | Known deviation | `test-engineer` | P3 |
| M-11 | 16 条 hardcoded 技术字符串告警（strict 模式下仍为非阻断；需逐条 triage） | T-20 §5 | Recorded | `implementation-engineer` | P3 |
| M-12 | ADR 文件头 Status 行同步（P2 提案） | T-21 原 DoD | 提案待执行 | `solution-architect` | P3 |
| M-13 | DEFERRED：扫码 / 相机二维码、设备删除 / 改名、场景编辑、通知系统权限状态 | T-18 §6.2 | Deferred（v1） | `implementation-engineer` | P3 |
| M-14 | 家庭 / 成员为接触式收敛，无实时同步 / 在线状态 | ADR-003 / DP-05 | v1 声明性限制 | `solution-architect` + `technical-writer` | P3 |

> T-20 的 F-01..F-06 已在工具侧关闭：端口例外登记、D-12 accepted、ACK p95 数字修正、Mock 退役别名对齐、`--strict-ui` 真正生效、fixture 补齐 D-03/D-05。**工具侧关闭不等于迁移 / 合规完成**；对应条目见 §3.2/§3.3。

### 3.10 排期与门禁影响

| 窗口 | 建议纳入 | 门禁影响 |
|---|---|---|
| **G-013 / G-014 前** | README / 本计划 / 风险登记 / Checkpoint / Gate 记录；**不启动端口迁移**（避免与 T-22 集成窗口冲突） | 文档与风险记录是 Stage Gate 输入；端口迁移不得被当作 Gate 前置 |
| **下一个维护窗口** | P1 端口迁移、M-07 工具文档刷新、596 条 i18n triage、M-08 测试 lint / 覆盖率方案 | 每项完成后重跑对应检查；不改变 v1 契约语义 |
| **固件 v2.1 / 设备可用后** | FC-01/FC-02/FC-06、BLK-02..BLK-08、真实 p95 / fps | 真实 TLS / 云 / 设备声明以用户证据为准；未执行项保持 BLOCKED |
| **持续** | 安全修复、依赖升级、文档卫生、失效链接 / 计数 | 安全 / 依赖升级触发全量回归；文档卫生不替代 Gate |
| **后续版本** | P2 端口拆分、D-12 值 import 迁移、FC-03..FC-05、M-03 邀请能力 | 需 ADR / Change Impact；不得在本版本静默扩展 |

---

## 4. 设备与真实环境验证矩阵（用户侧执行）

> 本节来自 T-19 §7（BLK-01..BLK-08）与 T-18 §5。所有项当前为 `BLOCKED` / `UNAVAILABLE`；执行结果应回填本矩阵或测试报告，并附证据路径。**不得把编译、Host、Mock 结果外推为设备 PASS。**

### 4.1 验证矩阵

| ID | 待验证能力 | 前置条件 | 用户侧执行要点 | 验收证据 | 当前状态 |
|---|---|---|---|---|---|
| BLK-01 | Hypium Host 运行 | 受支持的 Linux Previewer / 运行器 | 运行 `hvigorw test`；若仍不可用，保留 Node 运行器为正式 Host 路径 | 命令日志、失败根因 | **BLOCKED（环境）** |
| BLK-02 | 设备 / 模拟器 Hypium、UI 启动 | 签名 HAP、`hdc` target、模拟器或真机 | 安装签名包；运行 `onDeviceTest`；4 Tab / NavDestination 返回 | 测试日志、设备信息、截图 | **BLOCKED** |
| BLK-03 | BLE 配网 / Security1 / 身份 | ESP32-S3 网关固件、真实 BLE、PoP、Wi-Fi AP | 扫描 → 连接 → Security1 → 身份 v2.0/v2.1 → Wi-Fi 扫描 / 下发 → 绑定；取消后清理秘密 | 脱敏日志、状态机截图、失败注入结果 | **BLOCKED** |
| BLK-04 | 真实 LAN / TLS pin | 真实网关、LAN 地址、HMAC 密钥；TLS 需固件 v2.1 + pin | discover / control / ACK；校验验签、correlation、`reported_state`；pin mismatch / 握手失败必须 P-BLOCKED、无明文回退 | 抓包（脱敏）、profile、错误路径日志 | **BLOCKED** |
| BLK-05 | 真实华为云 IoTDA | endpoint / projectId / deviceId / IAM Token | 配置、签名命令、影子轮询、`LastRequestId/LastSeq` 完成判定、Token 过期提示；不期望自动刷新 | 脱敏请求 / 响应、影子前后快照 | **UNAVAILABLE** |
| BLK-06 | UI 视觉 / 无障碍 / 动效 | 真机或模拟器、字体缩放 / 读屏工具 | 4 Tab、暗黑、428×872、长英文、75% 文本膨胀、对比度、读屏、动效降级 | 截图 / 录屏、A11y 检查记录 | **BLOCKED** |
| BLK-07 | 性能 | 真实 LAN + 设备；性能工具 | ACK p95 ≤500ms；55ms 节流；60/120fps；记录样本数、网络、设备型号 | 原始测量数据、脚本版本 | **UNAVAILABLE** |
| BLK-08 | 真实硬件 | 门锁 / 门磁 / AC / SHT30 / PIR 等实物 | 状态正确性、门锁四阶段、AC 模式 / 温度、传感器读数与来源 | 设备照片 / 脱敏日志 / 截图 | **BLOCKED** |

### 4.2 IG-3 / UI 设备抽查项

| 项 | 来源 | 检查点 | 证据 |
|---|---|---|---|
| 非 ADMIN 的网关管理入口 | T-18 R2-01 | Settings `RECONFIGURE` / `ROTATE_SECRET` 对 MEMBER / GUEST 隐藏或禁用 | 截图 + 角色矩阵 |
| 配网取消随时可用 | T-18 R2-02 | 扫描 / Security1 / Wi-Fi 等待期间点击取消；状态回到可重试；秘密清理 | 录屏 + 日志 |
| 门磁引导一次性 / 显式入口 | T-18 R2-04 | skip 后显式“关联门磁”仍可打开；不出现死按钮 | 截图 |
| 配网中途权限 / 蓝牙失败 | T-18 R2-05 | 非 Step0 失败时显示“去设置”CTA；恢复路径可用 | 截图 |
| 按钮禁用可见性 / 取消 | T-18 §5 | 无权限、离线、只读、PENDING 状态的可操作性 | 截图 |
| 长英文 / 文本膨胀 / 安全区 | T-18 §5 | en-US 长标签、75% 膨胀、底部安全区 | 截图 / 测量 |

### 4.3 执行记录要求

- 记录设备型号、OS / API 版本、固件版本、网络环境、App revision 与签名方式。
- 日志必须脱敏：不得包含 Wi-Fi 密码、PoP、HMAC 密钥、IAM Token、私钥或完整邀请凭据。
- 失败项保留复现步骤与原始错误；不得用“重试后通过”覆盖首次失败证据。
- 设备结果不改变本仓库的代码级 Gate 证据；它是用户侧验收输入。

---

## 5. 风险接受登记

### 5.1 已接受 / 已登记风险

| ID | 风险 | 影响 | 补偿控制 / 现状 | 接受主体 | 复审触发 |
|---|---|---|---|---|---|
| **D-030 / GAP-T18-01** | `FamilyRepository.addGatewayToFamily` 无 actor / RBAC | 服务层网关管理授权缺口；内部 API 边界 | UI ADMIN 门 + BLE PoP 前置 + 内部 API 边界；**未关闭** | Orchestrator（v1 风险接受，D-030） | G-014、C-22/C-09/C-15 变更、下个 release |
| **R4-01** | `addGatewayToFamily` 已发起后的取消边界不可回滚 | durable 写可能完成；VM 仅抑制 BOUND | 文档声明；可选补 Host 边界用例 | Orchestrator / Stage Gate（Info） | 下一次配网 VM 变更 |
| **A-CB-1** | IoTDA REST 错误体 / 影子字段未在冻结语料定义 | 云错误分类 / 影子解析偏差 | `ShadowDtoAdapter` 容忍已知形态，未知形态 `CLOUD_SHADOW_INVALID` fail-closed；真实云验证 | `solution-architect`（假设登记） | 真实 IoTDA 联调、SR / CC schema 更新 |
| **PB-02** | `DeviceInventoryJson` 字段级结构未决 | 外部模块云完成判定不完整 | 内置 `LastRequestId/LastSeq` 路径完整；inventory 路径 `UNSUPPORTED`；固件提案 `PROPOSAL-PB02-1` | `solution-architect` + 固件维护者 | 固件 schema 冻结 / 云联调 |
| **P-HMAC 边界** | P-HMAC 无机密性 | LAN 载荷可被同网段观察 | 如实标注；TLS 需固件 v2.1；pin 失败 P-BLOCKED 不回退；GCM 归档 | 用户 / G-004（ADR-002） | 固件 v2.1、用户要求机密性 |
| **端口位置例外** | 17 条端口不在 `contracts/**`；10 条当前被使用 | 0 violation 不等于位置合规；未来端口可能绕过 Change Impact | T-20 allowlist + fail-closed；迁移计划 §3.2 | Stage Gate 记录（P2） | 迁移完成 / 新增端口 |
| **R3-01 D-12** | 13 条 pages DTO / 枚举 import | 契约登记已 accepted，但迁移未完成 | 文件 / 符号级 allowlist；禁止目录级放宽 | Stage Gate 记录（P2） | P2 迁移完成 |
| **设备 / 真实环境 BLOCKED** | BLE/LAN/TLS/云/视觉/fps 未验证 | 用户侧验收未完成 | 按 §4 由用户执行；Mock/Host 证据不外推 | Orchestrator（CP-03/D-018） | 用户提供设备结果 |
| **NFR 4.1/4.2/4.3 partial** | 传输机密性、设备存储、真实 p95/fps 缺证据 | NFR 未全部验收 | 证据边界如实标注；真实环境补齐 | Stage Gate 记录 | 设备 / 真实网络验证 |
| **ACK p95 MOCK_ONLY** | localhost 约 0.6 ms（T-19/T-20 0.598 ms；T-21 复跑 0.589 ms）不能外推 | 性能验收缺失 | 测量脚本 + 限制说明；真实 p95 由用户执行 | Stage Gate 记录 | BLK-07 执行 |
| **i18n 596 / 工具债务** | 历史文案未逐条签署；检查器路径偏差 | 文案质量 / 维护成本 | 当前 0 blocking；§3.4 收口 | Stage Gate 记录（P2） | 维护轮次 |
| **测试源码 lint / 覆盖率缺失** | 测试代码仅 Node 解析 / 编译门禁 | 测试质量盲区 | 已知 gap；独立 lint / 覆盖率任务 | Stage Gate 记录（P2） | CI / 测试基础设施变更 |
| **UI 视觉 / A11y 未验收** | 仅源码级 + Host VM 证据 | 可用性 / 无障碍风险 | §4.2 设备抽查 | 用户 / Stage Gate | 设备可用 |
| **许可证 TODO** | 项目级许可证未声明 | 再分发 / 合规不确定 | README 明确 TODO；不假设可再分发 | 项目所有者 | 首次公开发布前 |

### 5.2 交付计划风险表现状（R-01..R-17）

| ID | 当前状态 | 残余动作 |
|---|---|---|
| R-01 构建 / 签名 / 运行器 | 构建、lint、Host 已可用；签名 / 设备运行器仍不可用 | 签名与设备由用户配置；保持未签名构建边界 |
| R-02 Hypium 设备依赖 | Node Host 运行器替代；设备 Hypium BLOCKED | 设备可用后执行 `onDeviceTest`（BLK-02） |
| R-03 SPKI pin API | 已实现 socket + pin 校验；仅 localhost / mock 证据 | 真实网关 v2.1 验证（BLK-04） |
| R-04 Asset Store 语义 | 已实现并有 Host / fake 证据；设备 Asset Store 未执行 | 设备存储验证（BLK-02 / NFR 4.2） |
| R-05 BLE 互操作 | Host / fake 覆盖；真实 BLE BLOCKED | BLK-03 |
| R-06 邀请容器 | Host 负例 / AAD / 回执覆盖；真实多设备未验证 | 设备级邀请流程（BLK-03 / BLK-06） |
| R-07 PB-02 | 仍 `UNRESOLVED`；外部模块云完成 `UNSUPPORTED` | §5.1 PB-02 |
| R-08 PB-01 / UDP / mDNS | 手动 / 上次地址路径存在；真实发现未验证 | 真实网关发现（BLK-04） |
| R-09 UI / VM 范围 | 代码落地；视觉 / 设备 BLOCKED | BLK-06 / §4.2 |
| R-10 i18n 迁移成本 | 596 条 PENDING_REVIEW | §3.4 |
| R-11 覆盖不足 | 697 Host 用例；无覆盖率；设备 BLOCKED | §3.9 M-08 |
| R-12 用户覆盖 / 固件变化 | 无用户覆盖；FC-01..FC-06 待固件 | §3.7 / Change Impact |
| R-13 串行 / 上下文 | 已通过任务拆分与 Checkpoint 控制 | 保持单任务交接 |
| R-14 文档维护遗忘 | **本计划 + Checkpoint + 每 Gate 更新** | 按 §2.5 执行 |
| R-15 旧文档 / 旧代码权威 | 契约 / ADR / `input/` 权威顺序已登记 | 持续评审 |
| R-16 Mock 进入生产 | 源级 + HAP 级排除检查通过；DEV-ONLY 拒收 | 每次构建 / 评审回归 |
| R-17 产物 / 证书误提交 | `.gitignore` + SC-02/SC-07 审计通过；测试证书为授权例外 | 每次提交前检查 |

---

## 6. 维护轮次模板与验收

每次维护轮次建议执行：

1. **读取**：最新 Checkpoint、README、本计划、上游变更与 Gate 记录。
2. **核对**：文档版本头、`适用 revision`、命令结果、测试 / 评审证据、失效链接。
3. **分类**：P0 / P1 立即处理；P2 / P3 排期；新增风险登记到 §5。
4. **修订**：仅改授权范围；`input/` 走提案；代码 / 契约变更走 Change Impact。
5. **验证**：至少重跑构建、Host、layering、i18n、crosscheck；设备相关项保持 `BLOCKED` 或记录用户证据。
6. **记录**：更新版本头、变更记录、本计划状态、Gate / Checkpoint；提交并 `finish`。
7. **关闭条件**：所有声明与证据一致；无未登记 `STALE`；无被误写为 PASS 的 `BLOCKED` / `MOCK_ONLY`；`git diff --cached --check` 通过。

**本轮（T-21）已完成**：README 从脚手架状态更新为已实现 App 状态；关键命令复跑；P/E/FC、端口迁移、i18n 596、WP2-F04、R2 残余、风险接受与设备矩阵登记；`input/` 未修改。

**本轮未做 / 不得声称**：未执行端口迁移；未关闭 GAP-T18-01 / R4-01 / PB-02 / A-CB-1；未完成 596 条 i18n 迁移；未执行真实设备 / 网络 / 云 / 视觉 / fps 验证；未判定 G-013/G-014；未声明 release 或生产就绪。

---

## 7. 追溯

| 项 | 映射 |
|---|---|
| 文档版本机制 | 契约基线 §8.7（C-013）；P-16 |
| 端口迁移 | DES-A §27.6.3；`tools/contract/layering_allowlist.json`；TOOLING-CLEANUP-REPORT-001 §1/§5 |
| D-12 / R3-01 | DES-B §2.3/§18.1；`t18-review-c.md` §R3-01；T-20 F-02 |
| i18n | I18N-DESIGN §5；`legacy-migration.csv`；`t10-i18n.md` / `t10-fix-report.md`；T-18 §3.1 |
| P / E / FC | 契约基线 §5.2/§10/§11 |
| WP2-F04 | 契约基线 §7.2；`tools/test-fixtures/iotda/product-profile.json` |
| 测试 / 评审 | TEST-REPORT-001；REV-001-FINAL-SYSTEM；TOOLING-CLEANUP-REPORT-001 |
| 设备矩阵 | T-19 §7（BLK-01..08）；T-18 §5 |
| 风险 | `state/project-state.md` D-030；`t18-review-d.md` R4-01；契约基线 A-CB-1/PB-02；交付计划 §8.1 |

---

*MAINTENANCE-PLAN-001 结束。所有待办与风险均需在对应 Gate / 维护轮次重新核对；本文件不替代 Gate 判定或用户验收。*
