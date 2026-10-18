# Project Configuration

填写本文件以控制 Framework 在真实项目中的目标、流程强度、自主程度和技术约束。

- 未确定的字段填写 `auto`。
- 多项内容可使用逗号分隔或 Markdown 列表。
- 用户明确填写的值优先于 Framework 推断。
- `auto` 不表示可以忽略重大决策；高影响且无法可靠推断时，Orchestrator 必须询问。
- 示例见 [project.example.md](project.example.md)。

## Project

| Field | Value |
|---|---|
| Project Name | YaoCore (爻构) |
| Project Description | 面向真实家庭环境的开源智能家居 HarmonyOS 原生应用 (ArkTS)，连接 ESP32-S3 边缘网关与华为云 IoTDA，提供 BLE 配网、局域网安全控制、设备状态同步与场景联动。 |
| Target Stage | release |
| Workflow Mode | STANDARD |
| Execution Mode | GATED_AUTO |

`Target Stage` 常用值：`requirements`、`uml`、`architecture`、`detailed-design`、`implementation`、`review`、`testing`、`acceptance`、`documentation`、`release`、`maintenance` 或 `auto`。

`Workflow Mode`：`AUTO`、`LIGHTWEIGHT`、`STANDARD`、`STRICT`。

`Execution Mode`：`INTERACTIVE`、`GATED_AUTO`、`FULL_AUTO`。

## Technology

| Field | Value |
|---|---|
| Language | ArkTS / TypeScript |
| Language Version | API 14 / HarmonyOS NEXT (targetSdkVersion 26.0.0) |
| Framework | HarmonyOS NEXT ArkUI |
| Frontend | ArkUI Declarative UI |
| Backend | ESP32-S3 Gateway (外部物理硬件，App 内仅保留通信客户端接口与契约) |
| Database | HarmonyOS Preferences / RelationalStore (RDB) 本地持久化 |
| UI Framework | ArkUI |
| API Style | BLE Protocomm Security1 + Local HTTP REST (HMAC-SHA256) + Huawei Cloud IoTDA |
| Build System | hvigor |
| Package Manager | ohpm |
| Testing Framework | Hypium / Custom Protocol Contract Tests (注：实机与硬件测试由用户自行进行；工程及工作流负责单元测试、契约测试与 Mock 仿真) |
| Target Platform | HarmonyOS NEXT (API 14+) |
| Deployment Target | HarmonyOS Device HAP (entry) |

## Constraints and Preferences

| Field | Value |
|---|---|
| Must Use Technologies | ArkTS, ArkUI, @ohos.bluetooth.ble, @ohos.security.cryptoFramework, @ohos.net.http, HMAC-SHA256 |
| Forbidden Technologies | 虚构控制成功状态（未收到网关真实 ACK 前禁止模拟成功）、明文凭据传输、在 App 仓库包含 ESP32 C 固件构建链、假定或阻塞要求 Agent 进行物理真机测试 |
| Technical Preferences | 遵循“真实状态、执行确认、离线可用”设计原则；局域网优先；MVVM 分层架构；连续控制节流合并（~55ms）；多品牌适配器解耦 |
| Performance Requirements | 局域网控制响应 ACK <= 500ms；连续滑动控灯节流 55ms；BLE 配网扫描与连接低时延且带防抖去重 |
| Security Requirements | BLE 配网使用 Protocomm Security1 (X25519 + SHA256(PoP) + AES-256-CTR)；局域网通信支持端到端应用层对称加密 (AES-256-GCM / 本地 HTTPS) 与 HMAC-SHA256 双向防篡改/防重放；家庭邀请凭据安全流转与失效机制 |
| Compatibility Requirements | 兼容 HarmonyOS NEXT API 14 及以上环境 |
| Other Constraints | 本仓库仅放置鸿蒙 App 源码。ESP32-S3 网关作为外部物理设备，App 侧保留其完整的通信客户端、协议契约 Schema、服务接口与 Mock/Simulator 桩。全面支持家庭多成员管理 (Admin 创家庭/邀请 Member) 与房间-设备松耦合管理 (基于不变 ID 匹配，自由重命名与换房，房间删除设备保护性禁用入池)。实机测试由用户自行进行。交互 demo 仅作最简视觉参考，具体业务功能与交互严格以 input/ 设计分析规范为准。 |

## Git Collaboration

分支命名（包括 `feat/`、`fix/`、`docs/` 等）、合并策略、托管主分支 PR/MR 模式和公司规范入口在 [`git-policy.json`](git-policy.json)。`company_policy_path: null` 时使用 [`git-policy.default.md`](git-policy.default.md)；公司规范原文放入 `input/` 并在设置中填写路径。任务分支与多智能体合并步骤见 [`docs/git-collaboration.md`](../docs/git-collaboration.md)。

## Configuration Notes

- 本项目由原 YaoCore (https://github.com/Quirkybrain/YaoCore.git) 进行工程重构与分层解耦。
- 原项目包含网关 C 固件与 App 代码，本次重构此仓库专门承载 HarmonyOS NEXT ArkTS 原生应用。
- 完整需求分析、系统架构、协议规范、UI/UX 规范、数据模型及历史参考均已梳理并存放在 `input/` 资产池中。
- **关于 Demo 与设计规范的关系**：`input/design/demo/` 下的 HTML 演示仅作为最简的概念与视觉光影风格参考，很多业务功能和交互深度在 demo 中均有欠缺，具体实现严格以 `input/` 下的各项设计分析文档（PRD、架构设计、数据模型、API、UI/UX 交互规范）为准。
- **关于实机测试**：真机烧录、物理板卡通信、实际网络环境的联调与实机测试由用户自行进行；工程交付与工作流质量门禁以静态类型检查、ArkTS 构建、单元测试和 Mock 桩测试为准。
