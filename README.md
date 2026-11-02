# YaoCore（爻构）

<p align="center">
  <img src="AppScope/resources/base/media/layered_image.json" width="100" height="100" alt="YaoCore Logo" style="border-radius: 20px;" />
</p>

<p align="center">
  <b>面向真实家庭环境的开源智能家居 HarmonyOS NEXT 原生应用 (ArkTS)</b>
</p>

<p align="center">
  <a href="https://developer.huawei.com/consumer/cn/harmonyos/"><img src="https://img.shields.io/badge/HarmonyOS-NEXT%20(API%2014+)-blue.svg" alt="HarmonyOS NEXT"></a>
  <a href="https://www.typescriptlang.org/"><img src="https://img.shields.io/badge/Language-ArkTS%20%7C%20TypeScript-blue.svg" alt="ArkTS"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-green.svg" alt="License"></a>
  <a href="https://github.com/Quirkybrain/claude-code-swe-framework"><img src="https://img.shields.io/badge/Developed%20with-claude--code--swe--framework-orange.svg" alt="Workflow Framework"></a>
  <a href="#"><img src="https://img.shields.io/badge/Tests-697%20passed-brightgreen.svg" alt="Tests"></a>
</p>

---

## 📖 项目简介

**YaoCore（爻构）** 是一款专为 HarmonyOS NEXT 打造的现代智能家居原生控制应用。

打破传统智能家居软件冷硬机械的工具质感，YaoCore 将鸿蒙新一代**空间流体光影、毛玻璃拟态、弹性微动效**与**严谨的端到端安全传输、硬件抽象解耦**深度融合。以“真实确认、离线可用、空间自由”为基石，为家庭提供温润舒心、安全灵动的全屋物联体验。

---

## 🌟 核心设计哲学

### 1. 光影生息 · 柔彩舒心
- **动态流动光核**：基于自然节律的四组弥散呼吸光核（晨曦暖杏、晴空薄荷、云水淡蓝、极光柔紫），实时映射家居环境与时段；
- **纯净毛玻璃材质**：自适应高光倒角与大光圈磨砂背板，让信息悬浮通透；
- **物理弹簧交互**：卡片手势跟随与动态弹性阻尼（Spring 180/16），操作温润治愈。

### 2. 真实状态 · 执行确认（Anti-Optimistic）
- **杜绝虚假乐观更新**：摒弃前端“假开假关”欺骗用户的做法。用户操作开关或场景后，卡片进入微光呼应等待态，只有在收到物理网关明确的执行确认（ACK）及硬件回读校验通过后，界面才渲染为执行成功；
- **柔性弹性回滚**：若网络超时或硬件执行异常，系统通过弹性弹簧动效柔和回滚至前置状态，并附带明确的微弱触觉与 Toast 提示；
- **高频操作节流合并**：滑条拖拽（调光/调温）支持 55ms 动态节流合并（Throttle-Debounce Coalescing），界面刻度丝滑随动，仅向网络下发最终收敛值，防止网关消息队列拥塞。

### 3. 空间与设备松耦合（空间自由）
- **永久不变 ID**：设备（`deviceId`）与房间（`roomId`）基于独立且不可变的 UUID 关联，用户自由重命名房间或设备绝不破坏系统路由、场景联动与底层数据持久化；
- **未分配设备安全保护池**：删除房间时绝不级联销毁物理设备，设备平滑脱离并置入“未分配设备池”（安全降级为保护性禁用），重新指派新房间后即可自动满血复活；
- **家庭多成员邀请与 RBAC**：支持 `ADMIN`（家庭创建者）、`MEMBER`（日常全量成员）、`GUEST`（受限访客，支持指定授权房间与安全设备硬件级拦截）。通过 6 位动态短码或二维码安全流转凭证，无需重复进行繁杂的蓝牙扫码重配。

### 4. 端到端机密传输与协议解耦
- **BLE 安全配网**：采用标准的 Protocomm Security1 握手（X25519 密钥交换 + SHA256 PoP 派生密钥 + AES-256-CTR 加密传输信道）；
- **局域网安全通信**：基于标准 REST JSON 报文，覆盖端到端应用层加密（AES-256-GCM / 本地 HTTPS）结合 HMAC-SHA256 签名与 Nonce/时间戳防重放机制；
- **边缘硬件完全解耦**：本仓库专注于鸿蒙 App 自身，硬件网关作为外部物理设备。App 通信层全部面向接口协议编程（`IGatewayClient`、`IBleProvisioningClient`），原生适配 **聆思科技 LS26 ARCS mini3**、**ESP32-S3** 或通用 Linux 边缘计算盒，更换网关板卡时 App 代码零修改。

---

## 🤖 软件工程框架与研发架构

本项目从需求建模、架构设计、组件分层、代码实现到全量测试，全过程均由 **[claude-code-swe-framework](https://github.com/Quirkybrain/claude-code-swe-framework.git)**（由 [Quirkybrain](https://github.com/Quirkybrain) 原创研发的专业级多智能体软件工程工作流系统）自动化驱动与质量把关。

```text
               ┌────────────────────────────────────────────────────────┐
               │    claude-code-swe-framework (Stage Orchestrator)      │
               └────────────────────────────────────────────────────────┘
                                           │
         ┌───────────────────┬─────────────┴───────┬────────────────────┐
         ▼                   ▼                     ▼                    ▼
  [Asset Analyst]   [Solution Architect]   [Implementation Eng]   [Quality Reviewer]
  需求解耦与资产整理     MVVM架构与端口契约定义      ArkTS全量核心研发        独立第三方架构评审
         │                   │                     │                    │
         └───────────────────┴─────────────┬───────┴────────────────────┘
                                           ▼
               ┌────────────────────────────────────────────────────────┐
               │  全链路质量门禁 (G-001 ~ G-019 全部严格 PASS，0 架构违规) │
               │  • 697/697 Host 纯逻辑测试通过                         │
               │  • 66/66 协议资产交叉重算校验通过                      │
               │  • 221 个 ArkTS 源码文件严格符合单向依赖分层规则         │
               └────────────────────────────────────────────────────────┘
```

通过 SWE Framework 独创的：
1. **机械守卫与状态防漂移 (`swe_guard`)**：每一个研发任务均在独立的任务分支上由专职智能体隔离提交，杜绝代码交叉污染与暗箱修改；
2. **严格的架构分层检查 (`check_layering`)**：自动化拦截跨层污染（`pages` 严禁反向越权访问底层 `service` / `repository`，必须经过 `viewmodel` 与 `contracts`）；
3. **作者与评审者分离**：所有功能实现必须由独立的第三方评审智能体（`quality-reviewer`）执行代码与设计合规审计，不可自审自批。

---

## 📁 仓库代码结构

```text
YaoCore/
├── AppScope/                  # 鸿蒙应用全局配置、图标与多语言基础资源
├── entry/                     # 核心 ArkTS 原生应用模块
│   ├── src/main/ets/
│   │   ├── app/               # 组合根 (AppCompositionRoot)、权限门禁与生命周期装配
│   │   ├── common/            # 全局常量、主题规范 (AppTheme)、安全工具与错误模型
│   │   ├── components/        # 柔彩光影卡片、调光滑条、未分配池等复用 UI 组件
│   │   ├── contracts/         # 核心抽象端口 (Ports) 与接口契约 (纯类型定义，零跨层反向依赖)
│   │   ├── model/             # 领域模型、DTO、协议枚举 (Family / Room / Device / Control)
│   │   ├── pages/             # 38 个页面与导航流 (Home / Rooms / Scenes / Profile / Onboarding)
│   │   ├── repository/        # 本地关系型数据库 (RdbStore) 与持久化仓储层
│   │   ├── service/           # 蓝牙配网 (BLE Protocomm)、局域网加密通信、云通道与 i18n 服务
│   │   ├── viewmodel/         # 严格 MVVM 架构下的状态机与表现层逻辑
│   │   └── entryability/      # 鸿蒙 UIAbility 入口
│   ├── src/main/resources/    # 页面布局、色值、图标与中英双语资源
│   └── src/test/              # 自动化测试套件（含 697 项 Host 逻辑测试与测试报告）
├── tools/                     # 自测工具链与协议仿真器
│   ├── simulator/             # DEV-ONLY 本地网关协议仿真器 (HTTP / HTTPS / TLS)
│   ├── contract/              # 协议交叉重算验证、分层合规检查器 (check_layering)
│   ├── acceptance/            # 真机设备验收数据包校验工具
│   └── i18n/                  # 国际化文案一致性核验工具
├── build-profile.json5        # 编译构建配置
├── code-linter.json5          # 静态代码规则检查配置
├── hvigorfile.ts              # Hvigor 构建脚本
├── oh-package.json5           # ohpm 包依赖声明
└── README.md                  # 项目说明文档
```

---

## 🚀 快速上手与本地构建

### 前置环境要求
- **IDE**：[DevEco Studio NEXT](https://developer.huawei.com/consumer/cn/deveco-studio/)（建议最新 Release 版本）
- **SDK**：HarmonyOS NEXT (API 14+ / SDK 26.0.0+)
- **构建环境**：Node.js 20+，Python 3.10+（用于运行配套的协议仿真桩与分层测试）

### 1. 克隆代码
```bash
git clone https://github.com/Quirkybrain/YaoCore.git
cd YaoCore
```

### 2. 安装依赖
```bash
ohpm install
```

### 3. 执行本地自动化测试（697 项纯逻辑测试）
本项目配备了完备的离线 Host 单元测试套件，无需连接真机即可完成全逻辑回归：
```bash
# 运行 697 项领域模型、状态机、加密与分层测试
entry/src/test/run-host-tests.sh

# 运行架构分层合规性检查（保证无跨层代码污染）
python3 tools/contract/check_layering.py

# 运行网关协议契约自测
python3 tools/contract/crosscheck_protocol_assets.py
```

### 4. 启动本地网关模拟器（开发调试）
在没有物理网关硬件时，可一键启动内置的 DEV 仿真器测试局域网控制闭环：
```bash
python3 tools/simulator/gateway_contract_server.py --host 127.0.0.1 --port 9200
```

### 5. 在 DevEco Studio 中运行
1. 打开 DevEco Studio，选择 **Open Project** 并导入当前 `YaoCore` 目录；
2. 等待 Gradle / Hvigor 依赖同步完成；
3. 连接 HarmonyOS NEXT 真机设备（或启动 DevEco 远程/本地模拟器）；
4. 点击顶部工具栏 **Run 'entry'** (Shift + F10) 即可部署点亮！

---

## 📄 开源许可证推荐与声明

本项目采用 **[Apache License 2.0](LICENSE)** 开源许可证。

### 为什么选择 Apache 2.0？
1. **明确的专利许可授权（Patent Grant）**：智能家居涉及蓝牙、局域网加密通信与物联协议，Apache 2.0 明确提供了针对专利诉讼的防御性保护条款，对开发者和使用者更安全；
2. **商业友好与生态接轨**：允许任何个人或企业免费用于二次开发或商业产品，同时与 OpenHarmony / 华为鸿蒙生态主流开源协议高度保持一致；
3. **署名保护**：衍生作品必须保留原始版权信息与项目贡献声明。

---

## 🤝 鸣谢与贡献

- 感谢开源社区及 OpenHarmony / HarmonyOS 生态提供的基础技术支持；
- 特别鸣谢 **[claude-code-swe-framework](https://github.com/Quirkybrain/claude-code-swe-framework.git)** 提供的智能多智能体研发范式与严格的工程质量保障。
- 欢迎提交 Issue 与 Pull Request 共同完善全屋智能原生鸿蒙体验！
