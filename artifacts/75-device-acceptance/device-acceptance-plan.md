# DEVICE-ACCEPT-001 设备验收计划

- **Artifact ID**: DEVICE-ACCEPT-001
- **Producer**: agent:test-engineer
- **Type**: Device Acceptance Plan / Case Set / Evidence & Redaction Rules
- **Status**: `READY_FOR_USER_EXECUTION`（用例、证据模板与校验工具已准备；**设备测试未执行**）
- **Date**: 2026-10-19
- **Task**: `wp-121-device-acceptance`（task 分支 `task/wp-121-device-acceptance`，父分支 `feat/yaocore-app`，base commit `938867e84a42b860230cdb1ce6a1c3d84a8e246a`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `release`（设备验收输入；不授予 release）
- **Upstream**: `input/requirements/YaoCore_HarmonyOS_App_Requirements.md`（PRD）；`artifacts/65-acceptance/acceptance-report.md`（ACCEPT-001）；`artifacts/60-testing/testing-stage-report.md`（TEST-002）；`artifacts/85-release/release-plan.md`（RELEASE-001）；`docs/release-checklist.md`（RELEASE-CHECKLIST-001）；`artifacts/80-maintenance/maintenance-plan.md` §4（MAINTENANCE-PLAN-001）；`README.md`（README-001）；`input/existing/docs/BLE配网设计.md` §8；`input/api/Gateway_API_Specification.md`
- **Write scope**: `artifacts/75-device-acceptance/`、`tools/acceptance/`。未修改产品代码、测试、契约、`input/`、Gate 或状态文件。
- **Evidence CSV**: [`device-evidence-template.csv`](device-evidence-template.csv)
- **Defect template**: [`defect-report-template.md`](defect-report-template.md)
- **Validator**: [`../../tools/acceptance/validate_device_evidence.py`](../../tools/acceptance/validate_device_evidence.py)
- **Evidence root**: `artifacts/75-device-acceptance/evidence/<case_id>/`

> **结论先行**
>
> 1. 本计划是**用户执行设备验收的准备包**：定义 31 个可执行用例、证据模板、脱敏规则、结果判定与复验/缺陷流程。它**不执行**设备测试，也**不宣称**任何设备 PASS。
> 2. 当前仓库环境**不具备设备条件**：`hdc` 无目标、`signingConfigs: []`、无真实 ESP32-S3 网关/固件、无华为云 IoTDA 账号/Token、无真实硬件与性能测量环境。因此所有用例初始为 `NOT_RUN`。
> 3. 代码级证据（TEST-002 / ACCEPT-001 的 Host、Contract、Simulator、layering、i18n）**不等于**设备验收；`MOCK_ONLY`、`COMPILED_ONLY`、`BLOCKED` 不得写成 PASS。
> 4. 本计划覆盖 ACCEPT-001 的 `BLK-01..08` 与 `U-01..U-12`，并覆盖 PRD 的 26 个 FR 与 NFR 4.1/4.2/4.3 的用户侧验证点。
> 5. 用户完成回填、证据脱敏与签核前，**用户验收未完成、release 未授权**。

---

## 0. 文档控制

| 项 | 值 |
|---|---|
| 适用产品基线 | `938867e`（本任务 base commit；产品代码证据基线仍为 TEST-002 `e74a181`） |
| 最终 release revision/tag | **未冻结**（见 RELEASE-001 B-06；本计划不创建 tag） |
| 执行主体 | 用户在自有 HarmonyOS NEXT 设备与 DevEco Studio 签名环境执行 |
| 结果文件 | `artifacts/75-device-acceptance/device-evidence-template.csv`（执行时直接回填） |
| 证据目录 | `artifacts/75-device-acceptance/evidence/<case_id>/` |
| 校验命令 | `python3 tools/acceptance/validate_device_evidence.py --template artifacts/75-device-acceptance/device-evidence-template.csv` |
| 执行后校验 | `python3 tools/acceptance/validate_device_evidence.py artifacts/75-device-acceptance/device-evidence-template.csv` |
| 变更记录 | v1.0（2026-10-19）初始设备验收计划、31 用例、CSV 模板、缺陷模板与校验脚本 |

---

## 1. 范围与边界

### 1.1 In scope

1. 签名 HAP 在真实 HarmonyOS NEXT 设备上的安装、启动、升级与 UI smoke。
2. 真实 ESP32-S3 网关的 BLE 配网（Security1、PoP、Wi-Fi、取消/重试、权限拒绝、绑定探针）。
3. 真实局域网 HMAC 控制（签名、时间窗、nonce、重放、离线/超时）。
4. 固件 v2.1 条件下的 LAN HTTPS/TLS 与 SPKI pinning；失败时 fail-closed，不回退明文。
5. 真实华为云 IoTDA 配置、手动 Token、云命令、影子收敛与 Token 失效。
6. `door` / `light` / `sensor` / `ac` 全功能，以及 `switch` / `camera` / `curtain` / `fan` / `speaker` 与未知类型只读降级。
7. 家庭、成员、邀请、角色、房间、场景的真实设备/多设备流程。
8. zh-CN / en-US 运行时切换与长英文布局。
9. 视觉、暗黑、文本膨胀、安全区、对比度、读屏、触控目标与动效降级。
10. 真实 LAN ACK p95、55ms 节流、60/120fps。
11. 安全负例与恢复：错误 PoP、重放、证书错误、权限拒绝、秘密清零/安全存储。

### 1.2 Out of scope

- 固件烧录、固件构建、ESP32-S3 硬件维修、网关 PoP/HMAC 密钥生产与注入。
- 证书申请、Profile 生成、签名材料保管；本计划只要求用户提供**已签名** HAP，不接收秘密。
- 华为云账号注册、IoTDA 产品/设备创建、IAM Token 自动刷新（v1 为手工 Token）。
- 许可证选择、bundleName/versionCode 最终冻结、远端 push/PR/tag/发布授权（见 RELEASE-001 B-01..B-09）。
- 修改产品代码、测试断言、契约、`input/` 或 Gate 结论。
- 将本计划的结果用于替代 `quality-reviewer` 评审、`system-verifier` 验收判定或 Orchestrator 的 Gate 决策。

### 1.3 证据边界

| 证据类型 | 本计划中的含义 | 能否作为设备验收 PASS |
|---|---|---|
| Host / Contract / Simulator（TEST-002） | 本机 Node/Python 逻辑与 localhost 仿真 | **否**；只能作为代码级输入 |
| `COMPILED_ONLY` | 仅编译通过，未执行断言 | **否** |
| `MOCK_ONLY` | 仅 localhost/测试替身测得（如 ACK p95 0.609ms） | **否** |
| `BLOCKED` | 前置条件不满足 | **否**；不是产品失败，也不是 PASS |
| `NOT_RUN` | 尚未执行 | **否** |
| 本计划 `PASS` | 用户在真实设备/网络/云/硬件上执行并附脱敏证据 | 仅对该用例、该矩阵、该 revision 有效 |

### 1.4 当前环境状态（2026-10-19）

| 项 | 当前状态 | 影响 |
|---|---|---|
| `hdc` target | 无目标（`hdc list targets` 为空） | 安装、启动、UI、设备测试均 `BLOCKED` |
| 签名配置 | `build-profile.json5` 的 `signingConfigs: []` | 未签名 HAP 不可安装；需用户配置证书/Profile |
| 真实网关 | 无 | BLE/LAN/TLS 用例 `BLOCKED` |
| 固件 v2.1 | 未提供 | TLS/identity v2.1 用例 `BLOCKED`；P-HMAC 机密性限制仍适用 |
| 华为云 IoTDA | 无 endpoint/token | 云用例 `BLOCKED` |
| 真实硬件 | 无门锁/门磁/AC/SHT30/PIR | 硬件用例 `BLOCKED` |
| 性能工具 | 无设备/真实 LAN | p95/fps 用例 `BLOCKED` |

> 以上状态来自 TEST-002、ACCEPT-001 与本任务的只读检查；本任务**没有**执行任何设备命令，也没有把 `hdc` 输出解释为设备可用。

---

## 2. 前置条件

### 2.1 用户决策与风险前置

执行前必须由用户书面确认以下事项；未确认的项在对应用例中记 `BLOCKED`，不得臆测：

1. **发布身份 A/B/C**（RELEASE-001 §4.4；身份/版本为 B-06，许可证 B-01 是独立决策）：是否沿用公开旧身份 `io.github.quirkybrain.yaocore`。只有选择 A 时才执行覆盖升级（DA-002），且 `versionCode` 必须大于 `1000000`。
2. **当前本地身份风险**：当前树为 `bundleName=com.example.yaocore`、`versionCode=1000000`；它**不是**公开旧身份，不能覆盖升级公开 1.0.0。若选择 B/C，DA-002 记 `BLOCKED`（不适用），不得写“升级通过”。
3. **GAP-AC-01..03**：LAN IP 未显示、首页家庭切换为跳转、房间图标未接线/展示。用户接受为 v1 简化或要求 bounded fix；设备验收按现状记录，不把偏离写成 PASS。
4. **P-HMAC 机密性限制**：P-HMAC 只保证完整性与防重放，不提供载荷机密性；TLS 需固件 v2.1。未提供 v2.1 时，DA-012 记 `BLOCKED`，不得宣称 TLS/机密性完成。
5. **残余风险**：D-030 / R4-01 / PB-01 / PB-02 / i18n 历史文案 / 测试 lint 与覆盖率 / 未签名产物等（RELEASE-001 B-08）。
6. **发布范围**：是否把本设备矩阵作为 v1 验收范围；未覆盖的设备/OS/固件组合必须明确列为未验证。

### 2.2 设备与签名

| 项 | 要求 |
|---|---|
| 设备 | HarmonyOS NEXT 真机，`compatibleSdkVersion` API 14+；至少 2 台不同型号/系统版本用于 BLE 交叉验证（BLE §8 第 7 条） |
| 兼容性 | 至少 1 台 API 14 设备用于 B-09 运行时兼容性验证（若无法提供，记录 `BLOCKED`） |
| 开发环境 | DevEco Studio 或 HarmonyOS 命令行工具；`hdc` 可用 |
| 签名 | 用户自有证书、Profile、密钥库与口令；`signingConfigs` 仅保存在本地，不提交 |
| 构建 | 从精确 revision 构建的 **已签名 HAP**；记录构建命令、`buildMode`、产物路径、大小与 SHA-256 |
| 安装 | `hdc list targets` 非空；`hdc install <signed-hap>` 成功 |
| 设备设置 | 允许安装未知来源/调试应用（按用户环境）；关闭自动锁屏干扰；准备截图/录屏权限 |
| 隐私 | 不安装来源不明 HAP；不在共享设备上保留家庭/云凭据 |

### 2.3 网关与固件

| 项 | 要求 |
|---|---|
| 网关 | ESP32-S3（或兼容边缘板卡），已烧录可配网固件 |
| 固件版本 | 记录精确版本/commit；BLE 基线固件与 v2.1（TLS/identity v2.1）分别记录 |
| 配网状态 | 首次配网需擦除 NVS 或 BOOT 长按重置；记录重置方式 |
| PoP | 每台设备独立；用户从机身标签/安全记录获取；**不得**写入证据 |
| HMAC 密钥 | 与 PoP 不同用途；用户配置；**不得**写入证据 |
| 网关身份 | 支持 `YaoCore-GW-*` 广播与 Primary Service UUID `7a6e0001-4d7b-4f67-9a21-6d13c52ae3b8` |
| TLS | 仅固件 v2.1 且宣告 LAN TLS 档案时启用；准备 SPKI 指纹（公开值） |
| 硬件 | 门锁/门磁、灯、AC（Gree/Haier/Midea/Generic 至少各一台或说明缺失）、SHT30/PIR |
| 网关日志 | 可读取串口/日志；记录前脱敏 |

### 2.4 网络

| 项 | 要求 |
|---|---|
| Wi-Fi | 2.4 GHz SSID；网关与手机同一 LAN；关闭 AP 客户端隔离 |
| 隐藏 SSID | 准备一个隐藏 SSID 用于 DA-006 |
| 互联网 | 云用例需要可访问华为云 IoTDA；局域网用例不应依赖公网 |
| 代理 | 本地请求绕过 HTTP(S)_PROXY；不要在证据中记录代理凭据 |
| 时间 | 手机与网关 UTC 偏差在 ±120s 内；记录时区 |
| 抓包 | 如启用，只保留脱敏后的请求/响应；不得导出包含秘密的原始 pcap |

### 2.5 华为云 IoTDA

| 项 | 要求 |
|---|---|
| 账号 | 用户自有华为云账号；本计划不创建/代管 |
| 参数 | endpoint、projectId、deviceId、产品/服务 ID |
| Token | IAM Token 由用户手工填写；不自动刷新；**不得**写入证据、日志或 Git |
| 设备 | IoTDA 侧设备在线；影子/属性可查询 |
| 网络 | 手机可访问 IoTDA endpoint |

### 2.6 工具与证据

- 截图：系统截图或 `hdc shell snapshot_display`（按设备支持）。
- 录屏：系统录屏；长流程分段。
- 日志：`hdc shell hilog`（按 PID/关键字过滤）；只保留脱敏后的片段。
- 性能：ArkUI frame callback/profiler、系统性能工具或用户自有测量脚本；记录样本数、设备、刷新率、网络。
- 脱敏：见 §5。证据文件在提交/共享前必须完成脱敏并人工复核。

### 2.7 停止条件

执行中遇到以下情况应停止该用例并记录 `BLOCKED` 或 `FAIL`，不得继续猜测：

- 无签名 HAP / 无 `hdc` target / 设备无法启动。
- 网关固件/硬件与计划不符（如无 v2.1 却要求 TLS）。
- 需要输入的秘密无法安全提供，或证据无法脱敏。
- 观察到秘密泄露、认证绕过、数据丢失、崩溃/ANR 阻塞主流程（按 S1 处理并停止扩大测试）。
- 预期行为本身不明确（回到需求/契约 owner 澄清）。

---

## 3. 环境矩阵

每台设备/网络组合单独一行；同一用例跨设备执行时，在 CSV `notes` 记录 `matrix_id`。`TBD` 由用户在执行前填写，不得用估算值代替。

| matrix_id | 设备型号 | OS / API | 固件版本 | App revision | HAP SHA-256 | 网络 | 云账号/项目 | 用途 |
|---|---|---|---|---|---|---|---|---|
| M-01 | TBD | TBD / TBD | TBD | TBD | TBD | 2.4GHz 家庭 LAN + 互联网 | TBD | 主测机：安装、配网、LAN、云、UI、性能 |
| M-02 | TBD | TBD / TBD | TBD | TBD | TBD | 同一 LAN | TBD | 交叉验证机：BLE §8 第 7 条、邀请/多成员 |
| M-03 | TBD | TBD / **API 14** | TBD | TBD | TBD | 同一 LAN | TBD | B-09 API 14 兼容性 |
| M-04 | 模拟器（可选） | TBD / TBD | N/A | TBD | TBD | localhost/宿主网络 | N/A | 仅 UI 补充；**不替代**真机 BLE/LAN/TLS/性能 |

> 记录要求：设备型号、OS 版本、API level、固件版本、App revision、HAP SHA-256、网络 SSID（可脱敏为 `home-2g`）、账号标识（脱敏）。同一用例在不同矩阵上的结果分别记录；CSV 一行只能代表一个主矩阵，其他矩阵写入 `notes` 或拆分为新的证据文件。

---

## 4. 用例集

### 4.1 用例索引

| case_id | 标题 | 目标 FR/NFR | BLK | U | 严重度 |
|---|---|---|---|---|---|
| DA-001 | 签名 HAP 全新安装与启动 smoke | FR-HOME-001；NFR-4.2.2 | BLK-02 | U-01; U-03 | S1 |
| DA-002 | 覆盖升级（仅发布身份 A） | RELEASE-001 §4.4-A；B-06 | BLK-02 | U-01 | S1 |
| DA-003 | BLE 扫描、权限与去重 | FR-GW-001 | BLK-03 | U-04 | S1 |
| DA-004 | Security1 正确 PoP 握手与 `yaocore-id` | FR-GW-002 | BLK-03 | U-04 | S1 |
| DA-005 | 错误 PoP fail-closed 与重试 | FR-GW-002；NFR-4.1.1 | BLK-03 | U-04 | S1 |
| DA-006 | Wi-Fi 扫描/下发/状态与错误分类 | FR-GW-003 | BLK-03 | U-04 | S1 |
| DA-007 | 配网取消、蓝牙关闭与 GATT 断连恢复 | FR-GW-001; FR-GW-003 | BLK-03 | U-04 | S2 |
| DA-008 | 绑定探针三要素一致与 `yaocore-done` | FR-GW-003 | BLK-03 | U-04 | S1 |
| DA-009 | LAN HMAC 发现/控制/ACK 主路径 | FR-DEV-001; FR-HOME-004；NFR-4.1.2 | BLK-04 | U-05 | S1 |
| DA-010 | HMAC 时间窗、nonce、重放、坏签名 | NFR-4.1.2, NFR-4.1.3 | BLK-04 | U-05 | S1 |
| DA-011 | 网关离线、断网与超时回弹 | FR-DEV-001；FR-HOME-001 | BLK-04 | U-05 | S1 |
| DA-012 | TLS pin 成功与证书错误 fail-closed | FR-SET-002；NFR-4.1.1 | BLK-04 | U-05; U-10 | S1 |
| DA-013 | 云 IoTDA 手动 Token 配置与连接 | FR-SET-003 | BLK-05 | U-06 | S2 |
| DA-014 | 云命令、影子与完成判定 | FR-SET-003；FR-DEV-001 | BLK-05 | U-06 | S1 |
| DA-015 | 云 Token 失效/过期提示 | FR-SET-003 | BLK-05 | U-06 | S2 |
| DA-016 | light 全功能与 55ms 节流 | FR-DEV-002；NFR-4.3.2 | BLK-07; BLK-08 | U-09 | S1 |
| DA-017 | door/门磁四阶段与超时警报 | FR-DEV-003 | BLK-08 | U-09 | S1 |
| DA-018 | AC 品牌/模式/温度 | FR-DEV-004 | BLK-08 | U-09 | S1 |
| DA-019 | SHT30/PIR 与状态来源 | FR-HOME-003；FR-DEV-005 | BLK-08 | U-09 | S2 |
| DA-020 | 只读设备类型与未知类型 | README v1；FR-DEV-005 | BLK-08 | U-09 | S2 |
| DA-021 | 房间创建/改名/换房/删除保护 | FR-ROOM-001, FR-ROOM-002, FR-ROOM-003, FR-ROOM-004, FR-ROOM-005, FR-ROOM-006；FR-HOME-002 | BLK-06; BLK-08 | U-09 | S1 |
| DA-022 | 家庭/成员/邀请/角色/退出 | FR-FAM-001, FR-FAM-002, FR-FAM-003, FR-FAM-004；FR-SET-001 | BLK-06 | U-09 | S1 |
| DA-023 | 场景执行与局部失败不回滚 | FR-SCN-001 | BLK-06; BLK-08 | U-09 | S1 |
| DA-024 | zh/en 运行时切换与长英文 | FR-SET-003 | BLK-06 | U-11 | S2 |
| DA-025 | 视觉/暗黑/文本膨胀/安全区 | FR-HOME-001；FR-ROOM-001 | BLK-06 | U-07 | S2 |
| DA-026 | 无障碍：对比度/读屏/触控/动效 | U-07；BLK-06（PRD 未单列 A11y NFR） | BLK-06 | U-07 | S2 |
| DA-027 | 真实 LAN ACK p95 ≤500ms | NFR-4.3.1 | BLK-07 | U-08 | S1 |
| DA-028 | 60/120fps 与滑动帧率 | NFR-4.3.2, NFR-4.3.3 | BLK-07 | U-08 | S2 |
| DA-029 | 权限拒绝与恢复 | FR-GW-001 | BLK-06 | U-04 | S2 |
| DA-030 | 设备安全存储/秘密清零/重启 | NFR-4.2.1; NFR-4.2.2 | BLK-02 | U-12 | S1 |
| DA-031 | Hypium host / onDeviceTest 执行记录 | BLK-01；U-02 | BLK-01 | U-02 | S2 |

### 4.2 安装与升级

#### DA-001 签名 HAP 全新安装与启动 smoke

- **目标**: `FR-HOME-001`；`NFR-4.2.2`；ACCEPT-001 `U-01`/`U-03`；`BLK-02`。
- **前置**: 用户已配置签名；已从精确 revision 构建签名 HAP；`hdc list targets` 非空；设备已备份/无重要数据；记录 `matrix_id`、HAP 路径与 SHA-256。
- **步骤**:
  1. `hdc list targets`，截图/保存输出。
  2. `sha256sum <signed-hap>`，记录 64 位 SHA-256。
  3. `hdc install <signed-hap>`；保存完整安装日志。
  4. 启动 App；记录冷启动时间；确认无崩溃/ANR。
  5. 依次打开 Home、Rooms、Scenes、Settings 四个 Tab，执行一次进入/返回。
  6. 在 About/设置中核对 `versionName`、`versionCode`、`bundleName`；必要时用 `hdc shell bm dump -n <bundleName>` 交叉核对。
  7. 检查首页/设置是否出现 `DEV-ONLY`、Mock 或测试入口。
- **预期**: 安装成功；启动进入主界面；4 个 Tab 可用且返回正常；版本/包名与构建记录一致；无崩溃/ANR；无 Mock/DEV-ONLY 入口；未签名/签名不匹配时安装被拒绝而不是“成功”。
- **证据**: `01-hdc-targets.txt`、`02-hap-sha256.txt`、`03-install.log`、`04-launch.png`、`05-tabs.png`、`06-version.png`。
- **判定**: 全部满足为 PASS；安装/启动/版本/包名任一失败为 FAIL（S1）；无设备/签名/`hdc` 为 BLOCKED；未执行 NOT_RUN。
- **严重度**: S1。

#### DA-002 覆盖升级（仅发布身份 A）

- **目标**: RELEASE-001 §4.4-A；RELEASE-CHECKLIST-001 §1.7.7；`B-06`（身份/版本；`B-01` 为许可证，独立于升级路径）；ACCEPT-001 `U-01`。
- **前置**: 用户已书面选择身份 A；已安装公开旧版 1.0.0（`io.github.quirkybrain.yaocore`）；新 HAP 使用相同 `bundleName` 且 `versionCode > 1000000`；已备份旧数据。
- **步骤**:
  1. 在设备上记录旧版 `versionName`/`versionCode`/`bundleName`。
  2. 直接安装新 HAP（不先卸载）；保存安装日志。
  3. 启动 App；检查版本、家庭/房间/设备/场景数据与旧数据兼容性。
  4. 检查是否出现降级、签名冲突、数据丢失或启动失败。
  5. 记录升级前后截图与 `bm dump` 输出。
- **预期**: 覆盖安装成功；`versionCode` 单调递增；应用启动；声明的数据迁移/兼容行为符合；无签名冲突/降级。
- **证据**: `01-old-version.png`、`02-upgrade-install.log`、`03-new-version.png`、`04-data-check.png`、`05-bm-dump.txt`。
- **判定**: 身份 A 且全部满足为 PASS；身份 B/C 记 BLOCKED（不适用）并在 `notes` 引用用户决定；身份 A 下安装失败/数据丢失为 FAIL（S1）。
- **严重度**: S1。
- **当前身份说明**: 当前树为 `com.example.yaocore`/`1000000`，与公开旧身份不同；**不得**用当前 HAP 执行或宣称覆盖升级。若用户选 B/C，旧公开用户无法升级，必须在发布说明中声明。

### 4.3 BLE 配网

#### DA-003 BLE 扫描、权限与去重

- **目标**: `FR-GW-001`；BLE 设计 §8 第 1/6/7 条；`BLK-03`；`U-04`。
- **前置**: 网关进入配网模式（NVS 擦除或 BOOT 重置）；手机蓝牙开启；初次安装未授予蓝牙权限；至少 2 台设备/系统版本。
- **步骤**:
  1. 首次点击“添加网关”；观察运行时权限弹窗。
  2. 拒绝权限；确认出现前往系统设置的说明且不崩溃。
  3. 在系统设置授权后返回；重新发起扫描。
  4. 观察 `YaoCore-GW-XXXXXX` 广播、Primary Service UUID 过滤与去重；记录同一设备重复广播是否合并。
  5. 关闭蓝牙后重试；再打开蓝牙重试。
  6. 在无网关环境下等待 10s，确认超时提示与重试入口。
- **预期**: 权限仅在用户触发时请求；拒绝后不静默扫描/不崩溃；扫描只接受匹配 Service UUID 的设备；重复广播按 `deviceId` 去重；10s 无结果有明确提示；蓝牙关闭有提示；无重复监听器。
- **证据**: `01-permission.png`、`02-permission-denied.png`、`03-scan-list.png`、`04-timeout.png`、`05-bluetooth-off.png`、脱敏 `06-scan.log`；M-01/M-02 分别记录。
- **判定**: 全部满足为 PASS；权限拒绝后卡死/静默扫描/重复设备为 FAIL（S1）；无网关为 BLOCKED。
- **严重度**: S1。

#### DA-004 Security1 正确 PoP 握手与 `yaocore-id`

- **目标**: `FR-GW-002`；BLE 设计 §3/§4/§8 第 1/8 条；`BLK-03`；`U-04`。
- **前置**: 网关可连接；正确 PoP；2.4GHz Wi-Fi；HMAC 密钥已配置；手机时间准确。
- **步骤**:
  1. 选择网关并连接；记录实际 MTU（目标 512，最低 247）。
  2. 查询 `proto-ver`；确认 `sec_ver=1`、无 `no_sec`/`no_pop`、具备 Wi-Fi 扫描能力。
  3. 输入正确 PoP；观察 Security1 第 0/1 阶段与 `device_verify_data` 校验。
  4. 在加密会话内调用 `yaocore-id`，记录 `gatewayId` 与 `protocolVersion`。
  5. 确认此时**尚未**发送 Wi-Fi 凭据，且 PoP/会话密钥未出现在日志/界面。
  6. 继续进入 Wi-Fi 扫描页面。
- **预期**: 能力门禁通过；X25519/AES-CTR 握手成功；设备证明通过；`yaocore-id` 返回一致身份；Wi-Fi 凭据仅在身份读取后发送；PoP 与会话密钥不出现在证据中。
- **证据**: `01-mtu.png`、`02-proto-ver.redacted.txt`、`03-security1-states.png`、`04-identity.redacted.txt`、`05-no-secret-log.txt`。
- **判定**: 全部满足为 PASS；能力不兼容仍继续/明文下发/身份读取失败为 FAIL（S1）；无网关为 BLOCKED。
- **严重度**: S1。

#### DA-005 错误 PoP fail-closed 与重试

- **目标**: `FR-GW-002`；`NFR-4.1.1`；BLE 设计 §8 第 2 条；`BLK-03`；`U-04`。
- **前置**: 网关、正确 Wi-Fi、错误 PoP 与正确 PoP 各一份（正确值不写入证据）。
- **步骤**:
  1. 输入错误 PoP；观察失败提示与状态回退。
  2. 检查网关/App 日志，确认未发送 `set_config`/`apply_config`，未泄露 Wi-Fi 凭据。
  3. 确认会话被销毁、GATT 关闭；重新连接并输入正确 PoP。
  4. 完成一次成功配网；对比两次会话，确认未复用 CTR 流/会话密钥。
- **预期**: 错误 PoP 明确提示“配网码不正确”；不发送 Wi-Fi 凭据；失败后会话清理；正确 PoP 可重新握手成功；无 CTR 复用；日志无 PoP/密码。
- **证据**: `01-wrong-pop.png`、`02-no-credentials.redacted.log`、`03-retry-success.png`、`04-session-reset.txt`。
- **判定**: fail-closed 且可重试为 PASS；错误 PoP 被接受/凭据被发送/日志泄露为 FAIL（S1）。
- **严重度**: S1。

#### DA-006 Wi-Fi 扫描/下发/状态与错误分类

- **目标**: `FR-GW-003`；BLE 设计 §5/§8 第 3/4 条；`BLK-03`；`U-04`。
- **前置**: 网关、正确 PoP、2.4GHz SSID/口令、隐藏 SSID、错误口令、不存在 SSID。
- **步骤**:
  1. 触发 AP 扫描；确认 2.4GHz 列表、分页、SSID 聚合与隐藏 SSID 手输入口。
  2. 下发正确 SSID/口令；观察 `set_config`/`apply_config`/`get_status`；记录最终 IPv4。
  3. 使用错误口令；确认 `AuthError` 与重新输入路径。
  4. 使用不存在 SSID；确认 `NetworkNotFound`。
  5. 不重启 App，完成一次新的成功流程。
  6. 检查密码字段在成功/失败/取消后清空；日志无明文口令。
- **预期**: 扫描与分页正常；隐藏 SSID 可手输；正确凭据连接并返回 IP；`AuthError`/`NetworkNotFound` 可区分；失败后可重试成功；密码不持久化/不落日志。
- **证据**: `01-ap-list.png`、`02-hidden-ssid.png`、`03-connected.png`、`04-auth-error.png`、`05-network-not-found.png`、`06-retry-success.png`、脱敏 `07-wifi.log`。
- **判定**: 全部满足为 PASS；错误分类错误/密码泄露/成功后仍显示未连接为 FAIL（S1）。
- **严重度**: S1。

#### DA-007 配网取消、蓝牙关闭与 GATT 断连恢复

- **目标**: `FR-GW-001`/`FR-GW-003`；BLE 设计 §7/§8 第 5/6 条；`BLK-03`；`U-04`。
- **前置**: 网关；可操作蓝牙开关；可中断 GATT（离开范围/关闭蓝牙/网关重启）。
- **步骤**:
  1. 分别在扫描、连接、Security1、AP 扫描、等待 Wi-Fi 阶段点击取消。
  2. 每次取消后确认回到 Idle、扫描停止、GATT 关闭、页面可再次操作。
  3. 配网中断开蓝牙；重新打开并重试。
  4. 在握手/传输中断开网关电源；恢复后重试。
  5. 观察是否有重复监听、卡死、崩溃或旧会话复用。
- **预期**: 所有阶段可取消并回到可重试状态；蓝牙关闭有提示；断连后重新建立新 Security1 会话；无重复监听/卡死/崩溃；秘密清理。
- **证据**: `01-cancel-scan.mp4`、`02-cancel-handshake.mp4`、`03-bluetooth-off.png`、`04-reconnect.png`、脱敏 `05-state.log`。
- **判定**: 全部满足为 PASS；卡死/重复监听/旧会话复用/崩溃为 FAIL（S2）。
- **严重度**: S2。

#### DA-008 绑定探针三要素一致与 `yaocore-done`

- **目标**: `FR-GW-003`；BLE 设计 §8 第 8 条；`BLK-03`；`U-04`。
- **前置**: Wi-Fi 已连接并取得 IP；手机与网关同一 LAN；HMAC 密钥已配置；网关 LED 可观察。
- **步骤**:
  1. 记录 Security1 内读取的 `gatewayId`。
  2. App 探测返回 IP 的 `/discover`；确认请求/响应 HMAC 通过，记录 HTTP 身份 `gatewayId`。
  3. 观察网关板载 LED 回传/确认。
  4. 确认三要素（Security1、HTTP、LED）一致后才绑定。
  5. 故意使用错误 IP/错误密钥制造不一致；确认拒绝绑定且不猜测其他设备。
  6. 成功后观察 `yaocore-done` 与 BLE 释放。
- **预期**: 仅在身份一致时绑定；不一致明确拒绝；不按广播名/MAC 后缀/邻居顺序猜测；`yaocore-done` 后 BLE 释放；绑定状态持久化。
- **证据**: `01-security1-id.redacted.txt`、`02-http-id.redacted.txt`、`03-led.mp4`、`04-bound.png`、`05-mismatch-rejected.png`。
- **判定**: 三要素一致且不一致被拒绝为 PASS；错误绑定/猜测身份为 FAIL（S1）。
- **严重度**: S1。

### 4.4 局域网 HMAC 控制

#### DA-009 LAN HMAC 发现/控制/ACK 主路径

- **目标**: `FR-DEV-001`；`FR-HOME-004`；`NFR-4.1.2`；`BLK-04`；`U-05`。
- **前置**: 已绑定网关；HMAC 密钥；同一 LAN；灯/门锁等可控设备；手机与网关时间同步。
- **步骤**:
  1. 打开设备卡片；执行开/关；观察“同步中”状态。
  2. 确认网关返回 ACK：`result_code=0`、`request_id:seq` correlation、`reported_state`。
  3. 确认 UI 仅在验签、correlation、`result_code` 与 `reported_state` 都通过后提交。
  4. 观察状态来源标记（如 `app.lan`）与更新时间。
  5. 记录一次请求/响应头（脱敏）与端到端时间。
- **预期**: 无 ACK 不显示成功；pending 状态可见；ACK 有效后提交；签名/相关 ID/状态任一不匹配不提交；无明文回退；状态来源正确。
- **证据**: `01-pending.png`、`02-ack-success.png`、`03-response.redacted.txt`、`04-state-source.png`、`05-latency.csv`。
- **判定**: 全部满足为 PASS；乐观成功/correlation 不匹配仍提交为 FAIL（S1）；无网关/LAN 为 BLOCKED。
- **严重度**: S1。

#### DA-010 HMAC 时间窗、nonce、重放、坏签名

- **目标**: `NFR-4.1.2`；`NFR-4.1.3`；API §3.3 `1001/1002/1005`；`BLK-04`；`U-05`。
- **前置**: 可重放/篡改请求的代理或测试脚本；网关；HMAC 密钥；可控设备；手机时间可调（仅测试环境）。
- **步骤**:
  1. 发送有效请求作为基线。
  2. 修改签名（坏签名）；确认 `1001`，设备状态不变。
  3. 使用超出 ±120s 的时间戳；确认 `1002`。
  4. 在 300s 内重复使用同一 nonce；确认 `1005`。
  5. 篡改 body/action；确认验签失败。
  6. 重放一条已成功的完整请求；确认拒绝且不重复执行。
  7. 观察 App 是否显示失败、是否错误显示成功、是否回退到明文。
- **预期**: 坏签名/过期/重放/篡改均被拒绝；错误码符合契约；无状态变更；UI 不显示成功；无明文回退；时间窗边界（±120s）与 nonce 缓存行为符合契约。
- **证据**: `01-baseline.redacted.txt`、`02-bad-signature.txt`、`03-expired.txt`、`04-replay.txt`、`05-ui-failure.png`。
- **判定**: 全部拒绝且无副作用为 PASS；任一绕过/重复执行/明文回退为 FAIL（S1）。
- **严重度**: S1。

#### DA-011 网关离线、断网与超时回弹

- **目标**: `FR-DEV-001`；`FR-HOME-001`；`BLK-04`；`U-05`。
- **前置**: 已绑定网关且控制正常；可关闭网关/断开 LAN；未配置云或云不可用。
- **步骤**:
  1. 在线执行一次控制，确认成功。
  2. 关闭网关电源或阻断 LAN；再次执行控制。
  3. 观察 pending 状态、3s 超时、错误提示与状态回弹。
  4. 恢复网关；确认状态收敛/可重试，不出现幽灵成功。
  5. 关闭手机 Wi-Fi/切飞行模式重复一次。
- **预期**: 离线可见；超时回弹；不伪造成功；不静默排队无限重试；恢复后可重试；状态最终与网关一致。
- **证据**: `01-online.png`、`02-offline-pending.mp4`、`03-timeout-revert.png`、`04-recovery.png`、`05-network-state.txt`。
- **判定**: 全部满足为 PASS；离线仍显示成功/无限 pending 为 FAIL（S1）。
- **严重度**: S1。

### 4.5 TLS 与 pinning

#### DA-012 TLS pin 成功与证书错误 fail-closed

- **目标**: `FR-SET-002`；`NFR-4.1.1`；`BLK-04`；`U-05`/`U-10`；固件 v2.1。
- **前置**: 网关固件 v2.1 且宣告 LAN TLS 档案；已知 SPKI 指纹（公开值）；HMAC 密钥；手机与网关同一 LAN；准备错误 pin/错误证书场景。
- **步骤**:
  1. 在设置中启用/配置 TLS 档案；确认 App 使用 HTTPS 且校验 SPKI pin。
  2. 执行一次控制；确认 ACK 与状态正常。
  3. 使用错误 pin 或替换证书；再次控制。
  4. 观察是否进入 `P-BLOCKED` / `TLS_PIN_MISMATCH`；确认**没有** HTTP 明文回退、没有控制发送、没有成功提示。
  5. 恢复正确 pin；确认可重试成功。
- **预期**: 正确 pin 下 TLS 控制成功；pin 不匹配/握手失败 fail-closed；不降级 HTTP；不发控制；UI 说明清楚；恢复后可用。
- **证据**: `01-tls-config.png`、`02-spki.txt`、`03-tls-success.png`、`04-pin-mismatch.png`、`05-no-fallback.redacted.txt`。
- **判定**: fail-closed 且无明文回退为 PASS；任何明文回退/控制仍发送/成功提示为 FAIL（S1）；固件非 v2.1 为 BLOCKED，并记录 P-HMAC 无机密性。
- **严重度**: S1。

### 4.6 华为云 IoTDA

#### DA-013 云 IoTDA 手动 Token 配置与连接

- **目标**: `FR-SET-003`；`BLK-05`；`U-06`。
- **前置**: 华为云 IoTDA endpoint/projectId/deviceId；手工 IAM Token；互联网；产品/服务已配置。
- **步骤**:
  1. 在设置页填写 endpoint、projectId、deviceId 与 Token；确认 Token 输入被遮蔽。
  2. 测试连接；观察在线/离线状态。
  3. 使用错误 endpoint 或错误 projectId；确认错误提示。
  4. 检查日志/截图无 Token 明文。
- **预期**: 配置可保存；Token 遮蔽且不落日志；连接状态真实；错误配置有明确失败；不宣称自动刷新。
- **证据**: `01-cloud-config-masked.png`、`02-connected.png`、`03-invalid-endpoint.png`、`04-redacted.log`。
- **判定**: 全部满足为 PASS；Token 泄露/连接状态造假为 FAIL（S2）；无云环境为 BLOCKED。
- **严重度**: S2。

#### DA-014 云命令、影子与完成判定

- **目标**: `FR-SET-003`；`FR-DEV-001`；`BLK-05`；`U-06`。
- **前置**: 云配置有效；设备在线；可查询设备影子；可下发命令。
- **步骤**:
  1. 下发一条云命令；观察“已受理”与最终状态的区别。
  2. 查询影子/属性；核对 `LastRequestId`/`LastSeq` 或等价完成证据。
  3. 确认只有匹配且时间不早于命令时刻的影子证据才提交成功。
  4. 构造不匹配/陈旧影子；确认不完成、不显示成功。
  5. 如使用外部 `DeviceInventoryJson`，记录 `UNSUPPORTED` 行为，不声明成功。
- **预期**: 受理 ≠ 完成；匹配证据后提交；陈旧/不匹配不提交；无伪造成功；外部模块路径按契约 fail-closed。
- **证据**: `01-command-accepted.png`、`02-shadow-before.json`、`03-shadow-after.json`、`04-completion.png`、`05-stale-no-commit.png`。
- **判定**: 完成判定严格为 PASS；受理即成功/陈旧影子提交为 FAIL（S1）。
- **严重度**: S1。

#### DA-015 云 Token 失效/过期提示

- **目标**: `FR-SET-003`；`BLK-05`；`U-06`。
- **前置**: 有效 Token；可撤销/使用过期 Token。
- **步骤**:
  1. 使用有效 Token 完成一次连接/查询。
  2. 更换为过期/无效 Token；再次查询或下发。
  3. 观察 401/鉴权失败提示、是否自动刷新、是否显示成功。
  4. 更新有效 Token；重试。
- **预期**: 明确提示 Token 失效/过期；无自动刷新宣称；不显示成功；更新后可恢复。
- **证据**: `01-valid.png`、`02-token-expired.png`、`03-updated-retry.png`、`04-redacted.log`。
- **判定**: 提示与恢复正确为 PASS；静默失败/假成功为 FAIL（S2）。
- **严重度**: S2。

### 4.7 设备类型与硬件

#### DA-016 light 全功能与 55ms 节流

- **目标**: `FR-DEV-002`；`NFR-4.3.2`；`BLK-07; BLK-08`；`U-09`。
- **前置**: 灯设备；LAN 控制可用；可观察网关日志/命令时间。
- **步骤**:
  1. 开关灯；确认 ACK 后状态提交。
  2. 亮度设为 0/1/50/100；确认边界与显示。
  3. 设置颜色（RGB）；确认 ACK 与显示。
  4. 连续拖动亮度 5s；记录命令数量/时间；确认约 55ms 合并、TouchUp 发送最终值。
  5. 拖动中取消/滑出；确认不提交未确认值。
- **预期**: 开关/亮度/颜色正确；连续滑动不命令风暴；最终值发送；取消不误提交；状态来源正确。
- **证据**: `01-power.png`、`02-brightness.png`、`03-color.png`、`04-slider.mp4`、`05-command-timestamps.csv`。
- **判定**: 全部满足为 PASS；命令风暴/取消后误提交/无 ACK 成功为 FAIL（S1）。
- **严重度**: S1。

#### DA-017 door/门磁四阶段与超时警报

- **目标**: `FR-DEV-003`；`BLK-08`；`U-09`。
- **前置**: 门锁 + 门磁；物理门可开合；网关；可触发超时。
- **步骤**:
  1. 上锁；观察 `SECURED/UNCONFIRMED/UNKNOWN` 阶段。
  2. 开门/关门；确认只有门磁到位证据才显示“已锁好”。
  3. 制造门未到位/传感器超时；确认警报与文案。
  4. 解锁；确认状态与来源。
- **预期**: 无证据不升级为 SECURED；四阶段/三态文案正确；超时警报；解锁可用。
- **证据**: `01-lock-stages.mp4`、`02-door-open.png`、`03-timeout-alarm.png`、`04-unlock.png`、脱敏 `05-lock.log`。
- **判定**: 全部满足为 PASS；无证据显示已锁好为 FAIL（S1）。
- **严重度**: S1。

#### DA-018 AC 品牌/模式/温度

- **目标**: `FR-DEV-004`；`BLK-08`；`U-09`。
- **前置**: Gree/Haier/Midea/Generic AC（至少各一台，或明确记录缺失）；网关；可观察 AC 显示。
- **步骤**:
  1. 绑定各品牌 AC；确认适配器识别。
  2. 设置模式（按契约 7 值词表）与目标温度 16/30；确认 ACK 与 AC 实际显示。
  3. 设置越界温度（如 15/31）；确认拒绝/钳制，不伪造成功。
  4. 切换风速/摆风（如支持）；确认状态来源。
- **预期**: 品牌适配正确；模式/温度符合契约；越界有明确处理；ACK 后提交；AC 实际响应与 App 一致。
- **证据**: `01-brand.png`、`02-mode.png`、`03-temp-16-30.png`、`04-out-of-range.png`、`05-ac-display.jpg`。
- **判定**: 全部满足为 PASS；App 显示与 AC 不一致/越界伪造成功为 FAIL（S1）。
- **严重度**: S1。

#### DA-019 SHT30/PIR 与状态来源

- **目标**: `FR-HOME-003`；`FR-DEV-005`；`BLK-08`；`U-09`。
- **前置**: SHT30/PIR 实物；网关上报；可对比物理环境。
- **步骤**:
  1. 观察温湿度数值与时间戳；与物理温湿度计对比。
  2. 触发 PIR；观察人体感应状态与时间戳。
  3. 检查状态来源标记（如 `sensor.physical`）。
  4. 断开传感器/等待超时；确认不伪造旧值为新值。
- **预期**: 数值合理且更新；PIR 状态正确；来源/时间戳真实；无数据时不伪造。
- **证据**: `01-sensor-values.png`、`02-pir.png`、`03-source.png`、`04-sensor-photo.jpg`。
- **判定**: 全部满足为 PASS；数值/来源伪造为 FAIL（S2）。
- **严重度**: S2。

#### DA-020 只读设备类型与未知类型

- **目标**: README v1 设备范围；`FR-DEV-005`；`AC-C10`；`BLK-08`；`U-09`。
- **前置**: `switch`/`camera`/`curtain`/`fan`/`speaker` 设备与一个未知类型；网关。
- **步骤**:
  1. 发现并打开每种设备；确认状态可展示。
  2. 尝试寻找控制入口；确认不存在或明确只读。
  3. 检查未知类型：只读展示 + 协议偏差记录；不崩溃。
  4. 通过网关日志确认 App 未发送控制命令。
- **预期**: 只读类型不提供控制、不下发命令；状态展示可用；未知类型容忍；无死按钮/崩溃。
- **证据**: `01-readonly-list.png`、`02-readonly-detail.png`、`03-unknown.png`、04-no-control.redacted.log`。
- **判定**: 全部满足为 PASS；只读设备可控制/发命令为 FAIL（S2）。
- **严重度**: S2。

### 4.8 房间、家庭、场景

#### DA-021 房间创建/改名/换房/删除保护

- **目标**: `FR-ROOM-001, FR-ROOM-002, FR-ROOM-003, FR-ROOM-004, FR-ROOM-005, FR-ROOM-006`；`FR-HOME-002`；`BLK-06; BLK-08`；`U-09`。
- **前置**: Admin 家庭；至少 2 个房间与 2 个设备；可重启 App。
- **步骤**:
  1. 创建房间；记录 `roomId`（可用调试/日志，脱敏非必要）。
  2. 重命名房间；确认设备归属不变、无网络请求。
  3. 设备分配/跨房转移/移入未分配池；确认原子更新。
  4. 删除含设备的房间；确认设备未级联删除，而是未分配 + 禁用。
  5. 删除一个设备；确认房间无感、场景引用清理。
  6. 在首页使用房间快捷切换栏（全部/各房间/未分配）过滤设备，确认与房间归属一致；横向滑动可用。
  7. 重启 App；确认 `roomId`/`deviceId` 不变、数据持久化。
- **预期**: ID 不变；改名零网络；换房正确；删除房间保护设备；删除设备不影响房间；首页房间过滤正确；重启后一致。
- **证据**: `01-create-room.png`、`02-rename.png`、`03-move.png`、`04-delete-room.png`、`05-restart.png`、`06-ids.txt`。
- **判定**: 全部满足为 PASS；级联删除/ID 变化/重启丢失为 FAIL（S1）。
- **严重度**: S1。

#### DA-022 家庭/成员/邀请/角色/退出

- **目标**: `FR-FAM-001, FR-FAM-002, FR-FAM-003, FR-FAM-004`；`FR-SET-001`；`BLK-06`；`U-09`。
- **前置**: 两个账号/两台设备；Admin；邀请码/凭据；可执行角色变更与移除。
- **步骤**:
  1. Admin 创建家庭；设置名称；确认 Admin 角色。
  2. 创建第二个家庭并切换；确认数据隔离。
  3. 生成 MEMBER/GUEST 邀请（含时限/授权房间）；在第二台设备加入。
  4. 确认成员无需重新 BLE 配网即可获得家庭密钥/访问；邀请过期/错误码失败。
  5. Admin 修改角色、移除成员；确认被移除方令牌/本地数据失效。
  6. 成员退出；Admin 转让/解散；验证最后 Admin 不能退出。
- **预期**: RBAC 正确；邀请/过期/授权房间生效；密钥同步不重新配网；移除失效；退出/转让/解散符合 v1 本地语义；不宣称实时在线。
- **证据**: `01-create-family.png`、`02-switch.png`、`03-invite.png`、`04-join.png`、`05-role-remove.png`、`06-leave-transfer.png`（邀请凭据脱敏）。
- **判定**: 全部满足为 PASS；越权/移除后仍可控制/邀请泄露为 FAIL（S1）。
- **严重度**: S1。

#### DA-023 场景执行与局部失败不回滚

- **目标**: `FR-SCN-001`；`BLK-06; BLK-08`；`U-09`。
- **前置**: 场景含 3 个动作；至少一个设备可制造失败/离线。
- **步骤**:
  1. 创建场景并执行；观察每一步结果。
  2. 使第二步失败（设备离线/错误动作）；确认第一步已生效不回滚，第二步明确失败，第三步按策略继续/停止并显示。
  3. 重复执行同一场景；确认不重复派发。
  4. 检查最终状态与步骤结果一致。
- **预期**: 逐步结果可见；局部失败不回滚已生效动作；不伪造全部成功；并发执行拒绝；最终状态真实。
- **证据**: `01-scene-steps.png`、`02-partial-failure.mp4`、`03-no-rollback.png`、04-concurrent-rejected.png`。
- **判定**: 全部满足为 PASS；失败仍显示全成功/回滚已生效动作为 FAIL（S1）。
- **严重度**: S1。

### 4.9 i18n、视觉与无障碍

#### DA-024 zh/en 运行时切换与长英文

- **目标**: `FR-SET-003`；`BLK-06`；`U-11`。
- **前置**: 设备；zh-CN/en-US；长英文标签；可重启。
- **步骤**:
  1. 在设置切换 en-US；确认无需重启、当前页面更新。
  2. 遍历 Home/Rooms/Scenes/Settings/Device/Family/Room/Provisioning/Settings 子页；检查无 raw key/缺失文案。
  3. 使用长英文（如设备名、房间名、错误提示）；检查截断/换行。
  4. 切回 zh-CN；重启 App；确认语言持久化。
- **预期**: 运行时切换生效；无 raw key/空白；长英文不遮挡/不截断关键操作；重启后保持；无崩溃。
- **证据**: `01-en-home.png`、`02-en-long-text.png`、`03-zh.png`、`04-restart.png`。
- **判定**: 全部满足为 PASS；raw key/切换需重启/布局破坏为 FAIL（S2）。
- **严重度**: S2。

#### DA-025 视觉/暗黑/文本膨胀/安全区

- **目标**: `FR-HOME-001`；`FR-ROOM-001`；`BLK-06`；`U-07`。
- **前置**: 真机/模拟器；浅色/暗黑；字体缩放 75%；长英文；428×872 或目标视口。
- **步骤**:
  1. 截图 4 Tab（浅色/暗黑）。
  2. 设置字体 75% 文本膨胀；检查卡片、按钮、导航、错误提示。
  3. 检查底部安全区/手势区域；检查长英文。
  4. 记录 GAP-AC-01（LAN IP 未显示）、GAP-AC-02（家庭切换跳转）、GAP-AC-03（房间图标）的实际呈现。
- **预期**: 无重叠/截断/不可点击；暗黑对比可读；安全区正确；GAP-AC-01..03 按现状记录，不声称满足原始子句。
- **证据**: `01-light.png`、`02-dark.png`、`03-text-75.png`、`04-safe-area.png`、`05-gap-ac.png`。
- **判定**: 无布局阻断为 PASS；严重遮挡/不可操作为 FAIL（S2）；GAP-AC 偏离单独记录，等待用户接受/修复。
- **严重度**: S2。

#### DA-026 无障碍：对比度/读屏/触控/动效

- **目标**: 设备 UI 无障碍质量；`BLK-06`；`U-07`（PRD 未单列 A11y NFR，按 UI 质量验收）。
- **前置**: 系统读屏（如屏幕朗读）；对比度测量工具；可开启减少动效。
- **步骤**:
  1. 开启读屏；遍历 4 Tab 与主要按钮；记录标签/角色/焦点顺序。
  2. 检查图标按钮、开关、滑杆是否有可读标签。
  3. 测量正文/按钮对比度；记录不达标项。
  4. 检查触控目标尺寸；检查减少动效模式。
- **预期**: 可读标签与合理焦点顺序；无未标注图标按钮；文字对比度达到项目采用标准（至少 4.5:1，非文本 3:1）；触控目标可用；动效可降级。
- **证据**: `01-screenreader.mp4`、`02-focus-order.txt`、`03-contrast.csv`、`04-motion-reduced.mp4`。
- **判定**: 无阻断性无障碍问题为 PASS；关键操作不可读/不可触达为 FAIL（S2）。
- **严重度**: S2。

### 4.10 性能

#### DA-027 真实 LAN ACK p95 ≤500ms

- **目标**: `NFR-4.3.1`；`BLK-07`；`U-08`。
- **前置**: 真实 LAN；网关；设备；N≥100，warmup≥5；网络相对安静；记录设备/固件/网络。
- **步骤**:
  1. 执行 100 次有效控制（同一设备/动作，避免 UI 节流干扰）。
  2. 记录每次请求到 ACK 的时间戳；计算 p50/p95/max、失败数。
  3. 重复至少 3 组（可选）；记录均值和波动。
  4. 与设备型号、Wi-Fi 频段、网关固件、App revision 关联。
- **预期**: p95 ≤500ms；无失败；样本/环境记录完整；结果不是 `MOCK_ONLY`。
- **证据**: `01-raw-latency.csv`、`02-summary.json`、`03-device-network.txt`、`04-run.log`。
- **判定**: p95 ≤500ms 且样本合规为 PASS；>500ms 为 FAIL（S1）；无真实 LAN 为 BLOCKED。**不得**引用 localhost 0.609ms。
- **严重度**: S1。

#### DA-028 60/120fps 与滑动帧率

- **目标**: `NFR-4.3.2, NFR-4.3.3`；`BLK-07`；`U-08`。
- **前置**: 60Hz 与（如可用）120Hz 设备；ArkUI profiler/frame callback；页面切换/滚动/滑杆。
- **步骤**:
  1. 记录 10s 页面切换/滚动/动画帧率与 p95 帧时间。
  2. 连续拖动亮度滑杆 10s；记录命令节流与 UI 帧。
  3. 在 120Hz 设备重复；记录实际刷新率。
  4. 记录卡顿/jank 与设备温度/负载。
- **预期**: 60Hz 设备稳定 60fps；120Hz 设备在支持场景达到 120fps；无明显 jank；55ms 节流下 UI 流畅；报告实际值而非估算。
- **证据**: `01-60fps.mp4`、`02-120fps.mp4`、`03-frame-times.csv`、`04-slider.mp4`。
- **判定**: 达到目标且记录完整为 PASS；明显掉帧/卡顿为 FAIL（S2）；无 profiler 为 BLOCKED。
- **严重度**: S2。

### 4.11 安全恢复与环境

#### DA-029 权限拒绝与恢复

- **目标**: `FR-GW-001`；`BLK-06`；`U-04`；R2-05。
- **前置**: 初次安装；可拒绝/授予蓝牙权限；可开关蓝牙。
- **步骤**:
  1. 拒绝蓝牙权限；点击添加网关；确认提示与“去设置”入口。
  2. 从系统设置授权；返回 App；重试。
  3. 关闭蓝牙；重试；再打开。
  4. 重复拒绝/授予；确认无重复监听/崩溃。
- **预期**: 权限拒绝可恢复；提示明确；授权后无需重启；蓝牙关闭有提示；无静默扫描/卡死。
- **证据**: `01-permission-denied.png`、`02-settings-cta.png`、`03-after-grant.png`、`04-bluetooth-off.png`。
- **判定**: 全部满足为 PASS；卡死/无法恢复为 FAIL（S2）。
- **严重度**: S2。

#### DA-030 设备安全存储/秘密清零/重启

- **目标**: `NFR-4.2.1; NFR-4.2.2`；`BLK-02`；`U-12`。
- **前置**: 设备；已创建家庭/绑定网关；已配置 HMAC 密钥与云 Token；可强制停止/重启 App。
- **步骤**:
  1. 完成配网与控制；确认 HMAC 密钥、家庭成员配置在重启后仍可用。
  2. 强制停止 App；重启；检查家庭/网关/设备状态。
  3. 取消一次配网/成功一次配网；检查 Wi-Fi 口令、PoP、会话密钥不残留（UI/日志/可观察存储）。
  4. 检查云 Token 是否被遮蔽/不落明文日志。
  5. 如设备支持安全存储检查工具，记录 Asset Store/RDB 行为；不得导出秘密。
- **预期**: 必要配置持久化；Wi-Fi 口令/PoP/会话秘密用后清零；Token 不落明文；重启后状态一致；无秘密泄露。
- **证据**: `01-restart-state.png`、`02-secret-clear.txt`、`03-token-masked.png`、`04-storage-check.redacted.txt`。
- **判定**: 全部满足为 PASS；秘密残留/明文存储/重启丢失关键配置为 FAIL（S1）。
- **严重度**: S1。

#### DA-031 Hypium host / onDeviceTest 执行记录

- **目标**: `BLK-01`；`U-02`；ACCEPT-001 `U-02`。
- **前置**: 受支持的 Hypium host 环境或确认 Node runner 为正式 host 路径；设备 + 签名用于 `onDeviceTest`。
- **步骤**:
  1. 执行 `hvigorw test --no-daemon`；保存完整日志。
  2. 若 host Hypium 不可用，记录根因，并确认 Node runner（`entry/src/test/run-host-tests.sh`）被正式接受为 host 路径；不得把 Node 结果写成 Hypium 设备测试。
  3. 执行 `hvigorw --mode module -p module=entry@ohosTest -p product=default onDeviceTest --no-daemon`；保存设备测试报告。
  4. 记录设备型号/OS/API、测试 HAP 与结果。
- **预期**: Hypium host 可用并全绿，或 Node runner 的替代地位有书面记录；`onDeviceTest` 实际执行并全绿；`COMPILED_ONLY` 不被写成 PASS。
- **证据**: `01-hvigor-test.log`、`02-node-runner.tap`、`03-onDeviceTest.log`、`04-device-info.txt`。
- **判定**: 实际执行且通过为 PASS；无环境为 BLOCKED；仅编译为 `COMPILED_ONLY`（不是 PASS）。
- **严重度**: S2。

---

## 5. 证据与脱敏

### 5.1 目录与命名

```text
artifacts/75-device-acceptance/
├── device-acceptance-plan.md
├── device-evidence-template.csv
├── defect-report-template.md
└── evidence/
    ├── DA-001/
    │   ├── 01-hdc-targets.txt
    │   ├── 02-hap-sha256.txt
    │   ├── 03-install.log
    │   ├── 04-launch.png
    │   └── 05-tabs.png
    ├── DA-002/
    └── ...
```

命名规则：

- 目录名必须等于 `case_id`（`DA-001`…`DA-031`）。
- 文件名：`<两位序号>-<内容>.<扩展名>`，例如 `01-install.log`、`02-p95.csv`、`03-slider.mp4`。
- 扩展名：日志 `.log` / `.txt`；截图 `.png`；照片 `.jpg`；录屏 `.mp4`；测量 `.csv` / `.json`；说明 `.md`。
- 同一用例多次执行：保留原文件，新增 `10-retest-<yyyyMMdd>.log` 等；不要覆盖首次失败证据。
- `BLOCKED` 行至少保留 `00-blocked.txt`，写明阻塞原因、已检查的环境项与下一步；不要只写“无设备”。
- 大文件（录屏）可压缩，但保留原始时间戳/设备信息；不要只保留剪辑后片段。

### 5.2 禁止进入证据的内容

以下内容**任何情况下**不得出现在 CSV、计划回填、缺陷报告、日志、截图、录屏、文件名或 Git 中：

- Wi-Fi 口令/预共享密钥。
- 网关 PoP 明文、二维码原图（如含 PoP）。
- HMAC 控制密钥、会话密钥、AES-CTR 密钥流。
- 华为云 IAM Token、AK/SK、临时凭据。
- 证书私钥、密钥库口令、Profile 口令、签名私钥。
- 完整邀请凭据/邀请码（可保留脱敏后的前缀/长度/过期时间）。
- 用户手机号、地址、账号密码、身份证等个人信息。
- 未脱敏的完整抓包（pcap/HAR）——如必须，先脱敏并只保留协议字段。

### 5.3 允许保留的内容

- HAP SHA-256、公钥/SPKI 指纹、证书主题（不含私钥）。
- 网关 `gatewayId`（如 `GW-9A216D`；可按需遮住后 2 位）。
- 请求 ID、seq、nonce 的**脱敏哈希/截断值**（不要保留可用于重放的完整 nonce）。
- 错误码（`1001`/`1002`/`1005` 等）、状态文本、时间戳。
- 设备型号、OS/API、固件版本、App revision、网络频段/SSID 别名。
- 脱敏后的截图与日志片段。

### 5.4 采集建议

```bash
# 设备与安装
hdc list targets
sha256sum <signed-hap>
hdc install <signed-hap>
hdc shell bm dump -n <bundleName>

# 日志（按 PID/关键字过滤；输出到文件后再脱敏）
hdc shell hilog -T <tag> > 03-app.log
```

- 截图/录屏前关闭通知详情，避免泄露个人信息。
- 日志中如出现 Token/密钥字段，先替换为 `<REDACTED>`，再保存。
- 对截图中的 Token、Wi-Fi 名称、邀请码、手机号做遮挡/裁剪；遮挡必须不可逆。
- 证据文件提交前由用户复核 `redaction_confirmed=true`。

### 5.5 CSV 回填

`device-evidence-template.csv` 的列：

```text
case_id,title,fr_nfr,build_revision,hap_sha256,device_model,os_api,firmware,network,result,expected,actual,evidence_path,severity,owner,date,redaction_confirmed,notes
```

回填规则：

1. 每个用例一行；`case_id` 不得重复、不得新增计划外 ID。
2. 初始 `result=NOT_RUN`、`redaction_confirmed=false`；执行后更新。
3. `result` 只能是 `PASS` / `FAIL` / `BLOCKED` / `NOT_RUN`。
4. `build_revision` 填实际构建的 commit（7–40 位小写 hex）；`hap_sha256` 填签名 HAP 的 64 位 hex。
5. `device_model`、`os_api`、`firmware`、`network` 填实际值；不要用 `TBD` 冒充已执行。
6. `expected` 可保留计划摘要；`actual` 填实际观察（非 NOT_RUN 必填）。
7. `evidence_path` 填 `artifacts/75-device-acceptance/evidence/<case_id>/` 或其中的具体文件；非 `NOT_RUN` 必须非空且路径存在。
8. `date` 填执行日期 `YYYY-MM-DD`；模板中的 `2026-10-19` 是准备日期，执行时必须改为实测日期；`owner` 填执行人/角色；`notes` 记录 matrix_id、重试/缺陷/偏离。
9. `redaction_confirmed` 只有 `true`/`false`；任何非 `NOT_RUN` 行必须为 `true`。
10. `hap_sha256` 的 64 个 `0` 是模板哨兵；`PASS`/`FAIL` 行必须替换为真实值；`BLOCKED` 行如尚无构建可保留哨兵，但必须在 `notes` 说明。
11. 文件保持 UTF-8（无 BOM）/LF；不要用 Excel 另存为 CRLF（如使用 Excel，导出后检查）。

### 5.6 结果判定

| 结果 | 含义 | 证据要求 | 是否算通过 |
|---|---|---|---|
| `PASS` | 所有步骤与预期均实际观察到，且证据完整/脱敏 | 非空 `actual` + 存在且脱敏的 `evidence_path` | 是，仅限该用例/矩阵/revision |
| `FAIL` | 产品行为与预期不符，或出现安全/数据/崩溃问题 | 失败证据、复现步骤、缺陷 ID | 否；必须开缺陷 |
| `BLOCKED` | 前置条件不满足（设备/固件/云/身份决定/权限） | 非空 `actual` + `evidence_path` 下的 `00-blocked.txt`（阻塞原因与已尝试的环境检查）；可无截图/录屏 | 否；不是产品失败 |
| `NOT_RUN` | 尚未执行 | 无 | 否 |

补充规则：

- 不得把 `COMPILED_ONLY`、`MOCK_ONLY`、`UNAVAILABLE`、`SKIPPED`、`FLAKY` 写成 `PASS`。
- 部分步骤通过不构成 `PASS`；拆分为独立用例或记 `FAIL`。
- 首次失败后“重试通过”不能抹掉失败：保留首次失败证据；如判定为环境/偶发，记录 `FLAKY` 说明并至少一次受控复跑；如重复失败，转 `debug-specialist` 诊断。
- 同一用例跨矩阵执行时，主矩阵写 CSV，其他矩阵写 `notes` 或独立证据文件；不得用一台设备的结果代表全部设备。

### 5.7 缺陷流程

1. `FAIL` 发生后，从 [`defect-report-template.md`](defect-report-template.md) 复制一份，命名为 `DEF-<yyyyMMdd>-<NN>.md`（存放在证据目录或用户缺陷系统）。
2. 记录严重度、环境、复现步骤、预期/实际、脱敏证据、影响版本、责任人、状态。
3. 在 CSV `notes` 写缺陷 ID；不要修改 `case_id`。
4. 修复后使用新 revision/HAP 重跑该用例与受影响回归；更新 CSV 的 revision/hash/date/result/actual/evidence_path，并在 `notes` 保留旧结果与旧证据路径。
5. 只有复验 `PASS` 且证据完整，缺陷才可 `CLOSED`；`ACCEPTED_RISK` 需用户书面接受，不得当作 `PASS`。

### 5.8 复验规则

- 新构建 → 重新计算 HAP SHA-256；旧证据不删除。
- 复核范围：失败用例 + 受影响 FR/Contract + 相关回归（至少 DA-009/DA-010/DA-012 中受影响项）。
- 复验结果写入同一行，`notes` 记录 `retest_of=<旧日期/旧 revision>`；证据目录新增 `10-retest-*`。
- 若代码/契约/固件变化影响多个用例，按 Change Impact 标记受影响用例为 `NOT_RUN` 并重跑；不得复用旧 PASS。

### 5.9 校验脚本

```bash
# 模板结构校验（允许 NOT_RUN 无实际/证据路径，不检查路径存在）
python3 tools/acceptance/validate_device_evidence.py --template artifacts/75-device-acceptance/device-evidence-template.csv

# 执行后严格校验（非 NOT_RUN 必须有 actual/evidence_path，且路径存在）
python3 tools/acceptance/validate_device_evidence.py artifacts/75-device-acceptance/device-evidence-template.csv

# 校验器自测（正/负例，临时目录，不触碰真实证据）
python3 tools/acceptance/validate_device_evidence.py --self-test
```

退出码：`0` 通过；`1` 证据/结构校验失败；`2` 用法、IO 或自测失败。校验器还会检查计划中的 `### DA-xxx` 章节与 CSV 用例一一对应。

---

## 6. 执行顺序与停止条件

建议顺序（可按环境并行，但前置必须先满足）：

1. **决策**：身份 A/B/C、GAP-AC-01..03、P-HMAC/TLS、风险接受（§2.1）。
2. **签名与安装**：DA-001、DA-031（以及身份 A 时的 DA-002）。
3. **BLE**：DA-003 → DA-004 → DA-005 → DA-006 → DA-007 → DA-008。
4. **LAN/HMAC**：DA-009 → DA-010 → DA-011。
5. **TLS**：DA-012（仅固件 v2.1；否则 BLOCKED）。
6. **云**：DA-013 → DA-014 → DA-015。
7. **设备类型/硬件**：DA-016 → DA-017 → DA-018 → DA-019 → DA-020。
8. **房间/家庭/场景**：DA-021 → DA-022 → DA-023。
9. **i18n/视觉/A11y**：DA-024 → DA-025 → DA-026。
10. **性能**：DA-027 → DA-028。
11. **安全恢复/存储**：DA-029、DA-030。
12. **回填与总校验**：更新 CSV、脱敏复核、运行 §5.9 严格校验、用户签核。

停止/转交：

- `S1` 失败或发现秘密泄露/认证绕过/数据丢失 → 停止扩大测试，保留证据，按缺陷流程处理。
- 环境/固件/云不可用 → 标记 `BLOCKED`，不猜测产品失败。
- 预期行为不明确 → 回到需求/契约 owner 澄清，不自行改写预期。
- 重复失败/跨层问题 → 转 `debug-specialist` 诊断，不继续本地试错。

---

## 7. 追溯矩阵（BLK / U）

| 用例 | BLK | U | 主要 FR/NFR |
|---|---|---|---|
| DA-001 | BLK-02 | U-01; U-03 | FR-HOME-001；NFR-4.2.2 |
| DA-002 | BLK-02 | U-01 | RELEASE-001 §4.4-A；B-06 |
| DA-003 | BLK-03 | U-04 | FR-GW-001 |
| DA-004 | BLK-03 | U-04 | FR-GW-002 |
| DA-005 | BLK-03 | U-04 | FR-GW-002；NFR-4.1.1 |
| DA-006 | BLK-03 | U-04 | FR-GW-003 |
| DA-007 | BLK-03 | U-04 | FR-GW-001; FR-GW-003 |
| DA-008 | BLK-03 | U-04 | FR-GW-003 |
| DA-009 | BLK-04 | U-05 | FR-DEV-001; FR-HOME-004；NFR-4.1.2 |
| DA-010 | BLK-04 | U-05 | NFR-4.1.2, NFR-4.1.3 |
| DA-011 | BLK-04 | U-05 | FR-DEV-001；FR-HOME-001 |
| DA-012 | BLK-04 | U-05; U-10 | FR-SET-002；NFR-4.1.1 |
| DA-013 | BLK-05 | U-06 | FR-SET-003 |
| DA-014 | BLK-05 | U-06 | FR-SET-003；FR-DEV-001 |
| DA-015 | BLK-05 | U-06 | FR-SET-003 |
| DA-016 | BLK-07; BLK-08 | U-09 | FR-DEV-002；NFR-4.3.2 |
| DA-017 | BLK-08 | U-09 | FR-DEV-003 |
| DA-018 | BLK-08 | U-09 | FR-DEV-004 |
| DA-019 | BLK-08 | U-09 | FR-HOME-003；FR-DEV-005 |
| DA-020 | BLK-08 | U-09 | README v1；FR-DEV-005 |
| DA-021 | BLK-06; BLK-08 | U-09 | FR-ROOM-001, FR-ROOM-002, FR-ROOM-003, FR-ROOM-004, FR-ROOM-005, FR-ROOM-006；FR-HOME-002 |
| DA-022 | BLK-06 | U-09 | FR-FAM-001, FR-FAM-002, FR-FAM-003, FR-FAM-004；FR-SET-001 |
| DA-023 | BLK-06; BLK-08 | U-09 | FR-SCN-001 |
| DA-024 | BLK-06 | U-11 | FR-SET-003 |
| DA-025 | BLK-06 | U-07 | FR-HOME-001；FR-ROOM-001 |
| DA-026 | BLK-06 | U-07 | UI 质量（PRD 未单列 A11y NFR） |
| DA-027 | BLK-07 | U-08 | NFR-4.3.1 |
| DA-028 | BLK-07 | U-08 | NFR-4.3.2, NFR-4.3.3 |
| DA-029 | BLK-06 | U-04 | FR-GW-001 |
| DA-030 | BLK-02 | U-12 | NFR-4.2.1; NFR-4.2.2 |
| DA-031 | BLK-01 | U-02 | Hypium host / onDeviceTest |

覆盖检查：

- `BLK-01`：DA-031；`BLK-02`：DA-001/002/030；`BLK-03`：DA-003..008；`BLK-04`：DA-009..012；`BLK-05`：DA-013..015；`BLK-06`：DA-021..026/029；`BLK-07`：DA-016/027/028；`BLK-08`：DA-016..023。
- `U-01`：DA-001/002；`U-02`：DA-031；`U-03`：DA-001；`U-04`：DA-003..008/029；`U-05`：DA-009..012；`U-06`：DA-013..015；`U-07`：DA-025/026；`U-08`：DA-027/028；`U-09`：DA-016..023；`U-10`：DA-012；`U-11`：DA-024；`U-12`：DA-030。

---

## 8. 本包的验证与验收

本包自身的验证（不执行设备测试）：

```bash
python3 tools/acceptance/validate_device_evidence.py --template artifacts/75-device-acceptance/device-evidence-template.csv
python3 tools/acceptance/validate_device_evidence.py --self-test
entry/src/test/run-host-tests.sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py
```

附加断言：

- CSV 行数 ≥ 15（本包 31 行）。
- 每个 CSV `case_id` 在本文有且仅有一个 `### DA-xxx` 章节；本文没有计划外 `DA-xxx` 章节。
- CSV/计划/缺陷模板/脚本相互引用的路径存在。
- 模板无秘密：校验器的秘密扫描对 CSV 通过；计划与缺陷模板只使用占位描述，不包含真实凭据。
- 计划/模板/脚本保持 UTF-8/LF，无 BOM。

本包通过的边界：**只证明“设备验收准备就绪”**；不证明设备行为、云连通性、TLS、性能或用户签核。

---

## 9. 非声明（Non-claims）

- 不声明任何设备用例已执行或通过；当前全部 `NOT_RUN`。
- 不声明 BLE/LAN/TLS/云/硬件/视觉/A11y/fps 已验收。
- 不声明 NFR 4.1/4.2/4.3 达标；`MOCK_ONLY` 的 ACK p95 不是 NFR 4.3 证据。
- 不声明未签名 HAP 可安装/可发布；不声明已签名或已升级。
- 不声明用户验收完成、产品验收完成、release 授权或 Gate PASS。
- 不声明 P-HMAC 提供机密性；TLS 仅以固件 v2.1 的真实证据为准。
- 不声明 GAP-AC-01..03 已修复或已被用户接受；设备结果只记录现状，接受决定由用户书面作出。

---

## 10. 变更记录

| 版本 | 日期 | 变更 | Producer |
|---|---|---|---|
| v1.0 | 2026-10-19 | 初始设备验收计划：31 用例、环境矩阵、证据/脱敏规则、结果/缺陷/复验流程、BLK/U 追溯 | `agent:test-engineer` |

*DEVICE-ACCEPT-001 结束。设备执行由用户完成；未回填、未脱敏、未签核的证据不构成验收。*
