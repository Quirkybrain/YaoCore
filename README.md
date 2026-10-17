# YaoCore（爻构）

面向真实家庭环境的开源智能家居 HarmonyOS NEXT 原生应用（ArkTS）。

YaoCore 连接 ESP32-S3 边缘网关，并可选用华为云 IoTDA 作为广域网通道。App 负责 BLE 配网、局域网设备控制、真实状态同步、场景联动，以及家庭 / 房间 / 设备管理。ESP32-S3 网关是外部物理设备，其固件不在本仓库内。

> **Producer**: agent:technical-writer · **Status**: ACTIVE · **文档版本**: README-001 v1.0 · **生效日期**: 2026-10-18 · **适用代码基线**: `13dc839`
> **变更记录**: T-21 将 README 从脚手架状态更新为已实现 App 状态，补充 v1 范围、验证命令、已知限制、仓库结构与文档入口。
> 维护节奏、待办与风险接受登记见 [`artifacts/80-maintenance/maintenance-plan.md`](artifacts/80-maintenance/maintenance-plan.md)。

## 核心设计原则

| 原则 | 含义 |
|---|---|
| 真实状态 + 执行确认 | 只有收到网关真实 ACK，并完成响应验签、`request_id:seq` correlation 匹配、`result_code == 0` 与 `reported_state` 校验后，才允许显示控制成功；禁止虚构成功状态。 |
| 局域网优先 / 离线可用 | 日常控制优先走本地网络，不依赖云端；云端不可用时，已绑定的局域网设备仍应可用。 |
| 端到端机密性与完整性（按通道如实标注） | BLE 配网使用 Protocomm Security1；局域网控制使用 HMAC-SHA256 双向认证与防重放；网关支持时启用 HTTPS + 证书指纹固定（SPKI pinning）。仅有 P-HMAC 时只保证完整性与防重放，机密性须如实标注为未启用。 |
| 家庭 - 房间 - 设备松耦合 | 房间与设备使用不变 ID 关联；改名、换房是本地操作；删除房间时设备进入未分配池并保护性禁用，而不是级联删除。 |

## 当前交付状态

> **状态：implementation 阶段代码已完成（T-06..T-20），Stage Gate 尚未判定。可用于代码审阅与本地构建验证，不可用于生产。**

- 29 个组件（C-01..C-29）的 v1 代码、资源、测试与文档收尾已落地；实现报告、组件质量门禁与评审证据位于 [`artifacts/`](artifacts/)。
- 代码级证据限当前 revision 与当前主机环境：构建、静态检查、Host 纯逻辑测试、协议资产交叉校验、仿真器契约测试、i18n 与分层检查。
- **设备 / 真实硬件 / 真实网络测试由用户自行执行**：BLE、真实 LAN、真实 TLS pin、华为云 IoTDA、视觉 / 动效 / 无障碍与 60/120fps 尚未验证（见 [已知限制](#已知限制)）。
- **Mock / 仿真仅 DEV-ONLY**：仿真器响应固定携带 `X-YaoCore-Simulator: DEV-ONLY`；生产客户端必须拒收，Mock/仿真器不进入生产路径，也不构成物理网关可用的证据。
- 构建产物为**未签名** HAP / `.app`，不能安装到设备，也不是 release 交付物。

| 证据项 | 本次结果 | 说明 |
|---|---|---|
| `ohpm install` | **PASS** | 依赖安装完成 |
| 干净 HAP 构建 | **PASS** | `BUILD SUCCESSFUL`；未签名 HAP |
| 静态检查（codelinter） | **PASS（0 error / 25 warning）** | warning 为性能建议，非阻断 |
| Host 纯逻辑测试 | **PASS 697/697** | Node 24 测试运行器；非 Hypium 设备测试 |
| 协议资产交叉校验 | **PASS 66/66 hard checks** | 14 项冻结输入 `FINDING` 为已知勘误线索，不阻断 |
| 仿真器契约测试（HTTP + TLS） | **PASS 20/20** | localhost；DEV-ONLY 测试夹具 |
| i18n 检查（`--strict-ui`） | **PASS：0 blocking / 0 missing** | 73 条 advisory warning（其中 hardcoded 16 条，均为非 UI 技术字符串） |
| 分层检查（C-29） | **PASS：0 violation** | 13 条 D-12 例外已登记；10/17 条端口位置例外当前被使用，迁移未完成 |
| ohosTest HAP 编译 | **COMPILED_ONLY** | 仅证明测试代码可编译，不证明设备断言通过 |
| 设备 / 模拟器测试 | **BLOCKED** | 无 `hdc` target、无模拟器实例、无签名 |
| 真实 BLE / LAN / TLS / 云 / 视觉 / fps | **BLOCKED / UNAVAILABLE** | 由用户按设备矩阵执行 |
| ACK p95 | **MOCK_ONLY** | T-19/T-20 证据 p95 0.598 ms；T-21 复跑 0.589 ms；不是 NFR 4.3 验收数据 |

> `PASS` 仅表示对应 revision、对应环境实际执行且断言通过。本表命令于 T-21 在 `13dc839` 复跑；ACK p95 采用 T-19/T-20 已对齐的证据，仍为 `MOCK_ONLY`。`COMPILED_ONLY`、`BLOCKED`、`NOT_RUN`、`UNAVAILABLE` 均不写成 PASS；测试 HAP 编译通过不等于测试通过。详细证据与分类见 [`artifacts/60-testing/test-report.md`](artifacts/60-testing/test-report.md) 和 [`artifacts/70-review/final-system-review.md`](artifacts/70-review/final-system-review.md)。

## v1 范围与安全边界

### 设备支持范围

| `deviceType` | v1 处置 |
|---|---|
| `door` / `light` / `sensor` / `ac` | **完整支持**：控制、状态同步、ACK 确认、门锁 / 门磁、灯光 55ms 节流、空调模式与目标温度 |
| `switch` / `camera` / `curtain` / `fan` / `speaker` | **只读降级**：可解析并展示状态，不提供控制，不下发任何控制命令 |
| 未知 `deviceType` | 只读展示并记录协议偏差 |

### 通信与安全（按通道如实标注）

- **BLE 配网**：Protocomm Security1（X25519 + SHA256(PoP) + AES-256-CTR）；身份 v2.1 不可用时按 v2.0 受控回退，v2.0 校验仍不通过则 fail-closed；Wi-Fi 密码、PoP 与会话秘密仅保存在临时内存，用后清零。
- **局域网控制**：v1 基线为 **P-HMAC**——HTTP + HMAC-SHA256 双向认证、防篡改与防重放。网关固件支持身份 v2.1 并宣告 LAN TLS 档案时，可启用 **P-TLS-PIN**（HTTPS + SPKI 证书指纹固定）；TLS 校验失败进入 **P-BLOCKED**，禁止明文回退。
- **P-HMAC 的机密性限制**：P-HMAC 只保证完整性与防重放，**不提供载荷机密性**；在网关固件 v2.1 未就绪、App 使用 P-HMAC 时，界面与文档必须如实标注。AES-256-GCM 载荷信封归档为扩展 `EXT-GCM-001`，v1 不实现。
- **云路径**：仅包含 IoTDA 配置、签名云命令、影子轮询确认与 Token 过期提示；**Token 由用户手工填写**，不做自动获取 / 刷新、MQTTS 直连或后端代理。云命令“受理”不等于“执行”，必须有匹配的 `LastRequestId/LastSeq` 或不早于命令时刻的影子证据。
- **开发桩拒收**：生产路径拒绝 `X-YaoCore-Simulator: DEV-ONLY` 与 `DEV_SIMULATOR_ONLY`，不提供用户可开启的开发者模式。

## 已知限制

| 限制 | 说明 |
|---|---|
| 设备 / 真实环境未验证 | 无真机、模拟器实例与签名；真实 BLE 配网、LAN 控制、TLS pin、云 IoTDA、视觉 / 动效 / 无障碍与 fps 均未执行。设备矩阵与执行前置见维护计划 §4。 |
| Mock / 仿真仅 DEV-ONLY | `tools/simulator/` 是 localhost 契约夹具；测试证书与私钥均为 `PUBLIC TEST DATA ONLY`，不得用于真实设备或生产环境。 |
| P-HMAC 无机密性 | LAN 默认通道只保证完整性与防重放；TLS / pinning 依赖网关固件 v2.1，未就绪时不得宣称“端到端加密”或“TLS 已验证”。 |
| 云 Token 手工管理 | 无自动刷新 / 后端换取；Token 过期需用户更新。外部模块 `DeviceInventoryJson` 云完成判定受 `PB-02` 未决结构限制，未知结构一律 `UNSUPPORTED`，不声明成功。 |
| 家庭同步为接触式收敛 | 无服务器；家庭 / 成员 / 密钥变更通过邀请凭据与接触式导入收敛，不提供实时同步或成员在线状态（v1 声明性限制）。 |
| 部分交互 DEFERRED | 扫码 / 相机二维码、设备删除 / 改名、场景编辑、通知系统权限状态等未在 v1 UI 开放或仅保留诚实提示；不伪造未实现能力。 |
| 网关管理服务层 RBAC 缺口 | `FamilyRepository.addGatewayToFamily` 缺少 actor/RBAC（`GAP-T18-01`）；D-030 已书面接受 v1 风险，补偿控制为 UI ADMIN 门 + BLE PoP 前置 + 内部 API 边界。**该缺口未关闭**，不得宣称网关管理服务层 RBAC 已闭合。 |
| 配网取消的 durable 边界 | `addGatewayToFamily` 已发起后的取消只能抑制 `BOUND` 发布，不能回滚已发起的 durable 写（R4-01，Info）。 |
| 端口位置例外 / 迁移未完成 | DES-A 名义端口位置为 `contracts/**`，当前实际位于 `service/**`、`repository/**`、`viewmodel/**` 等；T-20 已将 17 条例外登记进 allowlist，但 P1-P3 迁移未执行。`check_layering` 的 0 violation **不代表端口位置已合规**。 |
| i18n 旧文案仍待迁移 | `legacy-migration.csv` 仍有 **596 条 `PENDING_REVIEW`**（A 类 606 条中）；当前 UI 无 blocking 硬编码，但历史文案未逐条人工签署。 |
| 性能证据不足 | ACK p95 仅 `MOCK_ONLY`（T-19/T-20 0.598 ms；T-21 复跑 0.589 ms，随环境波动）；真实 LAN p95 ≤500ms、60/120fps 未测量。55ms 节流仅有 Host 逻辑证据。 |
| 测试源码未 lint / 无覆盖率 | `code-linter.json5` 忽略 `src/test/**`、`src/ohosTest/**`；无行 / 分支覆盖率；25 条 lint warning 为非阻断性能建议。 |
| 未签名构建不可安装 | `signingConfigs: []`，可产出未签名 HAP / `.app`，但不能安装或发布。 |
| 视觉 / 无障碍未验收 | 布局、暗黑模式、长英文、文本膨胀、对比度、读屏、动效与触感均需设备 / 截图评审。 |
| 许可证未声明 | 项目级 `LICENSE` 仍为 **TODO**；在许可证确定前请勿假定可再分发。 |

v1 范围、错误语义与安全通道的权威定义见 [`artifacts/20-architecture/contract-baseline.md`](artifacts/20-architecture/contract-baseline.md) 及 ADR-001..004；本文只做摘要，不复制契约全文。

## 前置条件

| 项 | 要求 |
|---|---|
| 开发环境 | DevEco Studio，或 HarmonyOS 命令行工具（`ohpm`、`hvigorw`、`codelinter`） |
| HarmonyOS SDK | 26.0.0（API 26）；`DEVECO_SDK_HOME` 指向 SDK 根目录（包含 `default/sdk-pkg.json`） |
| 兼容范围 | `compatibleSdkVersion` 为 HarmonyOS NEXT API 14 |
| Java | 21 |
| Node.js | 24（Host 测试运行器使用 `node:test`） |
| 包管理器 | `ohpm` 26.0.0.630 或更高（基线验证值：26.0.0.630） |
| 构建工具 | `hvigorw` 6.26.8（基线验证值） |
| 静态检查 | `codelinter` 6.0.240（基线验证值） |
| Python | 3.10+（仅标准库；用于契约 / 仿真器检查） |
| 网络 | 首次 `ohpm install` 需可访问 ohpm registry；仿真器仅使用 localhost |
| PATH | `ohpm`、`hvigorw`、`codelinter`、`node`、`java`、`python3` 可用 |
| 签名 | 构建未签名包不需要签名；安装到设备、运行设备测试需要单独配置签名 |

> 构建与命令基线在 Linux x86_64 上验证；其他平台未验证。首次安装与构建需要可用的 HarmonyOS SDK；`DEVECO_SDK_HOME` 的本机示例见下文。

## 已验证命令

以下命令于 **2026-10-18** 在仓库根、Linux x86_64、`task/wp-086-docs` @ `13dc839` 实际复跑；详细日志见 [`artifacts/60-testing/test-report.md`](artifacts/60-testing/test-report.md) 与 [`entry/src/test/evidence/`](entry/src/test/evidence/)。

| 命令 | 本次结果 |
|---|---|
| `ohpm install` | PASS |
| `hvigorw clean assembleHap --no-daemon` | PASS（`BUILD SUCCESSFUL`，未签名 HAP） |
| `codelinter -c code-linter.json5 -p default .` | PASS（0 error / 25 warning） |
| `entry/src/test/run-host-tests.sh` | PASS（697/697） |
| `python3 tools/contract/check_layering.py` | PASS（209 files / 0 violation） |
| `python3 tools/contract/test_check_layering.py` | PASS（10/10） |
| `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | PASS（0 blocking / 0 missing） |
| `python3 tools/contract/crosscheck_protocol_assets.py` | PASS（66/66 hard checks） |
| `python3 -m unittest tools.simulator.test_gateway_contract -v` | PASS（20/20；localhost 需 `no_proxy`） |

### 1. 环境准备

```bash
# 在仓库根目录执行
export DEVECO_SDK_HOME="/home/quirkybrain/harmonyos/command-line-tools/sdk"  # 本机验证值，请按实际安装位置调整

# 确保 ohpm、hvigorw、codelinter、node、java、python3 在 PATH 中
```

### 2. 安装依赖

```bash
ohpm install
```

首次执行需要访问 ohpm registry，并生成 / 刷新 `oh-package-lock.json5`。

### 3. 构建

```bash
# 干净 HAP 构建（未签名）
hvigorw clean assembleHap --no-daemon
```

主要产物（均不提交，位于 gitignore 的构建目录）：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

`build-profile.json5` 当前 `signingConfigs` 为 `[]`，构建日志中的
`Will skip sign 'hos_hap'` 是预期行为：构建仍成功，但产物**未签名、不可安装**。应用打包可使用 `hvigorw assembleApp --no-daemon`，产物同样未签名。

### 4. 静态检查

```bash
codelinter -c code-linter.json5 -p default .
```

本次结果：`Defects: 25; Errors: 0; Warns: 25; Suggestions: 0`。warning 为自定义组件性能建议，非阻断。当前 `code-linter.json5` 不检查测试源码（`ohosTest` / `test` / `mock` 被显式忽略）。

### 5. Host 纯逻辑测试

```bash
entry/src/test/run-host-tests.sh
```

本次结果：`tests 697 / pass 697 / fail 0 / skipped 0`。该运行器使用 Node 24 的 `node:test` 执行纯逻辑测试，不依赖设备、模拟器或 Hypium Previewer；它不能替代设备断言。

### 6. 契约与分层检查

```bash
# 协议 schema / 向量 / 实现交叉校验
python3 tools/contract/crosscheck_protocol_assets.py

# 契约基线分层规则（D-01..D-17）
python3 tools/contract/check_layering.py

# 检查器 fixture 自测
python3 tools/contract/test_check_layering.py
```

本次结果：crosscheck `66/66 hard checks`（14 项冻结输入 `FINDING` 为已知勘误线索）；分层检查 `209 files / violations=0 / exceptions_used=13 / port_exceptions_used=10`。

> 分层检查的 0 violation 包含已登记例外：13 条 D-12 文件 / 符号级例外（`accepted`）与 17 条端口位置例外中的 10 条。端口迁移未完成前，**不得**把该结果解释为“端口位置已合规”。

性能 harness（`MOCK_ONLY`，**不是** NFR 4.3 验收）：

```bash
python3 tools/contract/measure_ack_latency.py --samples 100 --warmup 5
```

本次复跑结果：p50 0.521 ms / p95 0.589 ms / max 0.647 ms，0 failures；输出标注 `MOCK_ONLY`，不包含 ArkTS 客户端验签、状态应用、真实 LAN、TLS pin、BLE 或 UI 帧。

### 7. i18n 检查

```bash
python3 entry/src/test/i18n/check_i18n.py --strict-ui
```

本次结果：`blockingFailures=0 / missingKeys=0`；warnings 73（其中 hardcoded 16 条，均为技术状态 / 品牌 / Mock 字符串）；`--strict-ui` 会把短英文 UI 文案提升为 blocking。历史 596 条迁移状态见维护计划。

### 8. 仿真器契约测试（DEV-ONLY）

```bash
# 若本机设置了 HTTP(S)_PROXY，需要绕过 localhost 代理
no_proxy='127.0.0.1,localhost' NO_PROXY='127.0.0.1,localhost' \
  python3 -m unittest tools.simulator.test_gateway_contract -v
```

本次结果：`Ran 20 tests ... OK`（HTTP + TLS）。

启动 HTTP 仿真器：

```bash
python3 tools/simulator/gateway_contract_server.py --host 127.0.0.1 --port 9200 --quiet
curl -sS -i http://127.0.0.1:9200/health
```

启动 TLS 仿真器（自签名测试证书，仅 localhost）：

```bash
python3 tools/simulator/gateway_contract_server.py \
  --host 127.0.0.1 --port 9443 --quiet \
  --tls --cert tools/simulator/certs/dev-test-cert.pem \
  --key tools/simulator/certs/dev-test-key.pem

curl -sS -k -i https://127.0.0.1:9443/health
```

TLS 启动会打印测试证书的 SPKI-SHA256（当前为
`63f928c4c645b242ffb2a90a624258035e2a5ffb515756e0fb2f88113afa3243`）。`--cert` 与 `--key` 必须成对出现。

> **安全声明**：仿真器与测试证书仅用于 localhost 契约验证，属于 `PUBLIC TEST DATA ONLY`；禁止复用到真实网关、真实云或生产环境。仿真器始终返回 `X-YaoCore-Simulator: DEV-ONLY`，生产客户端必须拒收。

### 9. 当前不可执行 / 不作为 PASS 的测试

```bash
# 设备 / 模拟器 Hypium：BLOCKED（无 hdc target、无模拟器、无签名）
hvigorw --mode module -p module=entry@ohosTest -p product=default onDeviceTest --no-daemon

# Host Hypium：BLOCKED（Linux Previewer 不支持；使用上面的 Node 运行器替代）
hvigorw test --no-daemon
```

测试 HAP 可通过以下命令仅编译（**COMPILED_ONLY，不运行断言**）：

```bash
hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon
```

## 仓库结构

```text
YaoCore/
├── AppScope/                  # 应用级配置与资源（bundleName、应用名、图标等）
├── entry/                     # HarmonyOS entry 模块（ArkTS 应用）
│   ├── src/main/ets/
│   │   ├── app/               # 组合根、应用上下文、导航、权限与启动装配
│   │   ├── common/            # 常量、主题、通用类型与工具
│   │   ├── components/        # 复用 UI 组件与设计系统
│   │   ├── model/             # 领域 / 协议 / 云 / 配网模型
│   │   ├── pages/             # 页面与导航壳
│   │   ├── repository/        # 本地持久化仓储与领域端口
│   │   ├── service/           # 协议、安全、存储、网关、BLE、云、AC、i18n 等服务
│   │   ├── viewmodel/         # Home/Device/Climate/Door/Family/Room/Scene/Provisioning/Settings VM
│   │   ├── entryability/      # EntryAbility
│   │   └── entrybackupability/
│   ├── src/main/resources/    # base / en_US / zh-CN / dark 资源与 rawfile/i18n
│   ├── src/test/              # Host 纯逻辑测试、i18n 检查器、证据日志
│   └── src/ohosTest/          # Hypium 设备测试骨架（COMPILED_ONLY / BLOCKED）
├── tools/
│   ├── build/                 # 构建 / 测试基线脚本
│   ├── contract/              # 协议 crosscheck、分层检查、ACK 延迟 harness
│   ├── simulator/             # DEV-ONLY 网关仿真器、localhost 测试证书
│   └── test-fixtures/         # 测试夹具（如 IoTDA product-profile）
├── artifacts/                 # 工作流工件：验证、架构 / ADR、规划、设计、实现、测试、评审、维护
├── input/                     # 原始设计资产（需求 / 架构 / 数据 / API / UIUX，只读；未纳入 Git）
├── build-profile.json5        # 应用级构建配置
├── code-linter.json5          # 静态检查配置
├── hvigorfile.ts              # hvigor 构建入口
├── oh-package.json5           # ohpm 依赖声明
└── oh-package-lock.json5      # ohpm 锁文件
```

说明：

- `entry/src/main/ets/` 采用 MVVM 与单向依赖：页面 / 组件不直接构造 service、repository 或 ViewModel；生产组合根为 `app/AppCompositionRoot.ets`。
- `input/` 是本地只读设计资产池，**修改 `input/` 不在本仓库工作流内**；任何契约变更走勘误 / 补丁提案与 Change Impact。
- `artifacts/` 保存可追溯的设计、验证、规划、实现与评审证据；详细命令日志位于 `entry/src/test/evidence/`。

## 文档入口

| 内容 | 路径 |
|---|---|
| 原始需求 | `input/requirements/YaoCore_HarmonyOS_App_Requirements.md` |
| 系统架构 | `input/architecture/App_System_Architecture.md` |
| 数据与状态模型 | `input/data/Data_and_State_Models.md` |
| 网关 API / 协议规范 | `input/api/Gateway_API_Specification.md`、`input/api/protocol/` |
| UI / UX 规范 | `input/design/UI_UX_Specification.md` |
| 编码规范 | `input/standards/ArkTS_Coding_Standards.md` |
| 契约基线（v1 权威） | [`artifacts/20-architecture/contract-baseline.md`](artifacts/20-architecture/contract-baseline.md) |
| 项目约束基线 | [`artifacts/20-architecture/project-constraints.md`](artifacts/20-architecture/project-constraints.md) |
| 架构决策记录（ADR） | [`artifacts/20-architecture/`](artifacts/20-architecture/)（ADR-001..004） |
| 详细设计 DES-A / DES-B | [`artifacts/40-detailed-design/des-001a-foundation-transport.md`](artifacts/40-detailed-design/des-001a-foundation-transport.md)、[`artifacts/40-detailed-design/des-001b-domain-presentation.md`](artifacts/40-detailed-design/des-001b-domain-presentation.md) |
| 交付计划 / 组件图 | [`artifacts/30-plan/delivery-plan.md`](artifacts/30-plan/delivery-plan.md)、[`artifacts/30-plan/component-graph.md`](artifacts/30-plan/component-graph.md) |
| 构建与测试基线（T-01 历史基线） | [`artifacts/50-implementation/build-baseline.md`](artifacts/50-implementation/build-baseline.md)；当前命令与结果以本 README / 测试报告为准 |
| 测试计划 / 测试报告 | [`artifacts/60-testing/test-plan.md`](artifacts/60-testing/test-plan.md)、[`artifacts/60-testing/test-report.md`](artifacts/60-testing/test-report.md) |
| 独立系统评审 | [`artifacts/70-review/final-system-review.md`](artifacts/70-review/final-system-review.md) |
| 维护计划与风险登记 | [`artifacts/80-maintenance/maintenance-plan.md`](artifacts/80-maintenance/maintenance-plan.md) |

`input/` 为冻结的设计语料，只读；如与契约基线或 ADR 冲突，按变更提案流程处理，不直接修改 `input/`。文档版本与修订机制见维护计划 §2。

## 许可与致谢

- 本仓库尚未声明项目级开源许可证（**TODO**：由项目所有者确认并补充 `LICENSE`）。在许可证确定前，请勿假定可再分发。
- `entry/` 中的模板 / 第三方文件保留其原始版权与许可声明（如 Apache License 2.0）。
- 本工程使用 HarmonyOS SDK、Hvigor、ohpm，以及 Hypium / Hamock 测试框架；相关组件的版权与许可归各自权利人所有。
