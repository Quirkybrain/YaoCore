# YaoCore（爻构）

面向真实家庭环境的开源智能家居 HarmonyOS NEXT 原生应用（ArkTS）。

YaoCore 连接 ESP32-S3 边缘网关，并可选用华为云 IoTDA 作为广域网通道。App 负责 BLE 配网、局域网设备控制、真实状态同步、场景联动，以及家庭 / 房间 / 设备管理。ESP32-S3 网关是外部物理设备，其固件不在本仓库内。

## 核心设计原则

| 原则 | 含义 |
|---|---|
| 真实状态 + 执行确认 | 只有收到网关真实 ACK，并完成响应验签、`request_id:seq` correlation 匹配、`result_code == 0` 与 `reported_state` 校验后，才允许显示控制成功；禁止虚构成功状态。 |
| 局域网优先 / 离线可用 | 日常控制优先走本地网络，不依赖云端；云端不可用时，已绑定的局域网设备仍应可用。 |
| 端到端机密性与完整性（按通道如实标注） | BLE 配网使用 Protocomm Security1；局域网控制使用 HMAC-SHA256 双向认证与防重放；网关支持时启用 HTTPS + 证书指纹固定（SPKI pinning）。仅有 P-HMAC 时只保证完整性与防重放，机密性须如实标注为未启用。 |
| 家庭 - 房间 - 设备松耦合 | 房间与设备使用不变 ID 关联；改名、换房是本地操作；删除房间时设备进入未分配池并保护性禁用，而不是级联删除。 |

## 当前交付状态

> **状态：implementation 阶段进行中。当前仓库为脚手架 + 工程基线，不可用于生产。**

- 当前为 HarmonyOS 工程脚手架：`entry/` 仍是模板入口与 `Hello World` 页面，业务组件尚未实现。
- 已建立的工程基线包括：依赖安装、未签名 HAP 构建、未签名 `.app` 打包、静态检查、ohosTest Hypium 探针编译。
- 设计、契约、ADR、规划、验证与实现证据位于 `artifacts/` 工作流目录；原始设计资产位于 `input/`（只读）。
- 当前环境无真机、无模拟器实例、未配置签名，**测试用例尚未实际执行**。
- Mock / 仿真基础设施尚未实现；真机烧录、物理联调与真实网络验证由用户自行执行。

| 能力 | 当前状态 |
|---|---|
| `ohpm install` | **PASS** |
| 未签名 HAP 构建 | **PASS** |
| 未签名 `.app` 打包 | **PASS** |
| 静态检查（codelinter） | **PASS**（`No defects found`） |
| Hypium 测试代码编译 | **PASS（仅编译）** |
| Host / 设备测试运行 | **BLOCKED**（无设备、无签名、host 测试入口未建立） |
| 业务功能 | **未实现** |

## 前置条件

| 项 | 要求 |
|---|---|
| 开发环境 | DevEco Studio，或 HarmonyOS 命令行工具（`ohpm`、`hvigorw`、`codelinter`） |
| HarmonyOS SDK | 26.0.0（API 26）；`DEVECO_SDK_HOME` 指向 SDK 根目录（包含 `default/sdk-pkg.json`） |
| Java | 21 |
| Node.js | 24 |
| 包管理器 | `ohpm` 26.0.0.630 或更高（基线验证值：26.0.0.630） |
| 构建工具 | `hvigorw` 6.26.8（基线验证值） |
| 静态检查 | `codelinter` 6.0.240（基线验证值） |
| 网络 | 首次 `ohpm install` 需可访问 ohpm registry（`https://ohpm.openharmony.cn/ohpm/`） |
| PATH | `ohpm`、`hvigorw`、`codelinter`、`node`、`java` 可用 |
| 签名 | 构建未签名包不需要签名；安装到设备、运行设备测试需要单独配置签名 |

> 构建与命令基线在 Linux x86_64 上验证；其他平台未验证。当前构建配置的 `targetSdkVersion` / `compatibleSdkVersion` 为 `26.0.0`。

## 已验证命令

以下命令来自构建基线任务（2026-10-17）的实际执行记录，详细环境、日志与结果见
[`artifacts/50-implementation/build-baseline.md`](artifacts/50-implementation/build-baseline.md) §7。

### 1. 环境准备

```bash
# 在仓库根目录执行
export DEVECO_SDK_HOME="/home/quirkybrain/harmonyos/command-line-tools/sdk"  # 本机验证值，请按实际安装位置调整

# 确保 ohpm、hvigorw、codelinter、node、java 在 PATH 中
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

# 应用打包（未签名）
hvigorw assembleApp --no-daemon
```

主要产物（均不提交，位于 gitignore 的构建目录）：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
build/outputs/default/YaoCore-default-unsigned.app
```

`build-profile.json5` 当前 `signingConfigs` 为 `[]`，构建日志中的
`Will skip sign 'hos_hap'` / `Will skip sign 'app'` 是预期行为：构建仍成功，但产物**未签名、不可安装**。

### 4. 静态检查

```bash
codelinter -c code-linter.json5 -p default .
```

基线结果：`No defects found in your code.`。当前 `code-linter.json5` 不检查测试源码（`ohosTest` / `test` / `mock` 被显式忽略）。

### 5. 测试

```bash
# 1) 编译 ohosTest Hypium 探针（只编译，不执行）
hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon

# 2) 设备 / 模拟器测试（当前 BLOCKED）
hvigorw --mode module -p module=entry@ohosTest -p product=default onDeviceTest --no-daemon

# 3) Host 本地单测（当前不可用）
hvigorw test --no-daemon
```

**当前测试运行状态：BLOCKED，未执行任何测试用例。**

- `hdc list targets` 为空，且没有已创建 / 已下载的模拟器实例。
- `signingConfigs: []` 导致 HAP 未签名，无法安装到设备。
- `hvigorw test` 需要 `entry/src/test/List.test.ets`，该入口尚未创建。
- **测试 HAP 编译通过只证明测试代码可编译，不证明任何断言在运行时通过。不得写成“测试通过”。**

设备 / 模拟器就绪并配置签名后，才能执行 `onDeviceTest`；真机烧录、物理板卡通信与真实网络联调由用户自行完成。

### 6. 一键基线验证

```bash
# 默认：安装依赖 + 干净 HAP 构建 + 静态检查 + ohosTest HAP 编译 + unsigned app 打包
tools/build/verify-baseline.sh

# 有真机 / 模拟器时，额外运行 on-device Hypium 测试
tools/build/verify-baseline.sh --with-device-tests

# entry/src/test/List.test.ets 就绪后，运行 host 单测
tools/build/verify-baseline.sh --with-host-tests
```

脚本默认不会伪造运行时测试 PASS，而是把 host / 设备测试明确标记为 `NOT RUN` / `BLOCKED`。更多说明见
[`tools/build/README.md`](tools/build/README.md)。

## 仓库结构

```text
YaoCore/
├── AppScope/                  # 应用级配置与资源（bundleName、应用名、图标等）
├── entry/                     # HarmonyOS entry 模块（ArkTS 应用）
│   └── src/
│       ├── main/
│       │   ├── ets/           # 当前仅模板入口与 Hello World 页面
│       │   │   ├── entryability/
│       │   │   ├── entrybackupability/
│       │   │   └── pages/
│       │   ├── resources/     # 字符串、颜色、图标等资源
│       │   └── module.json5
│       └── ohosTest/          # Hypium 测试探针（编译可用，运行受环境阻塞）
├── tools/build/               # 构建 / 测试基线脚本与说明
├── artifacts/                 # 工作流工件：intake、验证、架构 / ADR、规划、实现证据
├── input/                     # 原始设计资产（需求 / 架构 / 数据 / API / UIUX，只读）
├── build-profile.json5        # 应用级构建配置
├── code-linter.json5          # 静态检查配置
├── hvigorfile.ts              # hvigor 构建入口
├── oh-package.json5           # ohpm 依赖声明
└── oh-package-lock.json5      # ohpm 锁文件
```

说明：

- 业务分层目录（`pages/`、`components/`、`viewmodel/`、`service/`、`model/`、`common/` 等）将在实现阶段按架构逐步创建；当前尚未实现。
- `input/` 是本地只读设计资产池，当前未被 Git 跟踪；`artifacts/` 保存可追溯的设计、验证、规划与实现证据。

## 已知限制

| 限制 | 说明 |
|---|---|
| 无业务实现 | 当前只有脚手架与工程基线；UI、领域模型、协议客户端、持久化、场景与家庭管理均未实现。 |
| 未签名构建不可安装 | 可产出未签名 HAP 与 `.app`，但不能安装到设备，也不能用于发布。 |
| 测试运行 BLOCKED | 无真机 / 模拟器、无签名配置，Hypium 用例未执行；host 单测入口尚未创建。 |
| 设备级测试由用户执行 | 真机烧录、物理板卡通信、实际网络环境联调不在本工程的自动化范围；工程门禁以构建、静态检查、单元 / 契约测试与 Mock / 仿真为准。 |
| Mock / 仿真未落地 | `MockGatewayService`、协议契约测试与仿真器属于后续任务，当前不存在可运行的 Mock 证据。 |
| v1 设备范围 | `door` / `light` / `sensor` / `ac` 为完整支持；`switch` / `camera` / `curtain` / `fan` / `speaker` 只读降级（可解析状态、不下发控制命令）；未知类型只读展示并记录偏差。 |
| LAN 安全 | v1 基线为 **P-HMAC**：HTTP + HMAC-SHA256 全链认证、防篡改与防重放；**可选 HTTPS + 证书指纹固定（P-TLS-PIN）**，仅在网关宣告 TLS 且 pin 已固定时启用。TLS 校验失败进入 P-BLOCKED，禁止明文回退。AES-256-GCM 载荷信封归档为扩展 `EXT-GCM-001`，v1 不实现。 |
| 云路径范围 | v1 仅包含 IoTDA 配置、签名云命令、影子轮询确认与 Token 过期提示；不做 Token 自动获取 / 刷新、MQTTS 直连或后端代理。 |
| 无性能 / 覆盖率证据 | 当前未测量 ACK p95、55ms 节流、帧率或测试覆盖率；相关测量口径由后续测试计划定义。 |

v1 范围、错误语义与安全通道的权威定义见
[`artifacts/20-architecture/contract-baseline.md`](artifacts/20-architecture/contract-baseline.md) 及 ADR-001..004；本文只做摘要，不复制契约全文。

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
| 架构决策记录（ADR） | [`artifacts/20-architecture/`](artifacts/20-architecture/)（ADR-001..004） |
| 项目约束基线 | [`artifacts/20-architecture/project-constraints.md`](artifacts/20-architecture/project-constraints.md) |
| 交付计划 / 组件图 | [`artifacts/30-plan/delivery-plan.md`](artifacts/30-plan/delivery-plan.md)、[`artifacts/30-plan/component-graph.md`](artifacts/30-plan/component-graph.md) |
| 构建与测试基线 | [`artifacts/50-implementation/build-baseline.md`](artifacts/50-implementation/build-baseline.md) |

`input/` 为冻结的设计语料，只读；如与契约基线或 ADR 冲突，按变更提案流程处理，不直接修改 `input/`。

## 许可与致谢

- 本仓库尚未声明项目级开源许可证（**TODO**：由项目所有者确认并补充 `LICENSE`）。在许可证确定前，请勿假定可再分发。
- `entry/` 脚手架等文件保留其原始版权与许可声明（如 Apache License 2.0）。
- 本工程使用 HarmonyOS SDK、Hvigor、ohpm，以及 Hypium / Hamock 测试框架；相关组件的版权与许可归各自权利人所有。
