# YaoCore（爻构）v1.0.0 发布说明

- **Artifact ID**: RELEASE-NOTES-001（v1.0.0 草案）
- **Producer**: agent:technical-writer
- **Status**: DRAFT / `NOT_READY`（发布准备稿；**未发布**）
- **Version**: `1.0.0`（`versionCode 1000000`；待冻结）
- **Date**: 2026-10-18
- **Applies to**: `feat/yaocore-app` 的 release 准备基线 @ `6cd9a88`；产品代码内容与 TEST-002 @ `e74a181` 一致
- **Upstream**: RELEASE-001、RELEASE-CHECKLIST-001、ACCEPT-001、TEST-002、README-001 v1.2

> **发布状态：`NOT_READY`（未发布）**
>
> 这是一份**发布准备稿**，不是对外发布公告。当前没有可下载的安装包；仓库构建产物为**未签名 HAP，不可安装**。发布需要项目所有者授权、完成签名，并完成设备/用户验收（B-01..B-08）。在发布授权前，请勿对外分发或宣称可用。

## 1. 版本与适用平台

| 项 | 值 |
|---|---|
| 应用 | YaoCore（爻构）v1.0.0 |
| versionCode | 1000000（待冻结） |
| 包标识 | `com.example.yaocore` / `vendor example`（待项目所有者确认） |
| 操作系统 | HarmonyOS NEXT |
| 编译 / 目标 SDK | 26.0.0（API 26） |
| 最低兼容 | API 14（`compatibleSdkVersion 5.0.2(14)`） |
| 已验证构建环境 | Linux x86_64；HarmonyOS SDK 26.0.0.105；Node 24；Java 21；ohpm 26.0.0.630；hvigorw 6.26.8 |
| 签名 | 未配置（`signingConfigs: []`）；当前产物未签名 |
| 发布通道 | 未选择、未授权 |
| 许可证 | **TODO**（未确定） |

**平台说明**：v1 目标为 HarmonyOS NEXT。最低兼容 API 14 尚未在真实 API 14 设备上验证；已验证的构建工具链为 SDK 26.0.0.105。其他宿主平台未验证。

## 2. 支持的设备范围

| `deviceType` | v1 支持 |
|---|---|
| `door` / `light` / `sensor` / `ac` | **完整支持**：控制、状态同步、真实 ACK 确认；门锁/门磁、灯光 55ms 节流、空调模式与目标温度 |
| `switch` / `camera` / `curtain` / `fan` / `speaker` | **只读降级**：可解析并展示状态，不提供控制，不下发控制命令 |
| 未知 `deviceType` | 只读展示并记录协议偏差 |

硬件由外部 ESP32-S3 网关提供；网关固件不在本仓库内。局域网控制要求手机与网关在同一网络；云通道需要可用的华为云 IoTDA 配置与 Token。

## 3. 功能亮点

- **真实状态，不虚构成功**：只有收到网关真实 ACK，并完成响应验签、`request_id:seq` correlation、`result_code == 0` 与 `reported_state` 校验后，才显示控制成功；超时或校验失败会回退并提示。
- **家庭与成员**：创建家庭并成为 ADMIN；多家庭切换；成员邀请、角色管理、移除、退出、ADMIN 转让与解散家庭。v1 为本地语义，家庭/密钥变更通过邀请凭据接触式收敛，不提供实时在线状态。
- **房间与设备**：创建/改名房间（ID 不变）；设备自由加入、跨房间转移、未分配池；删除房间时设备进入未分配池并保护性禁用，不级联删除。
- **设备控制**：门锁/门磁、灯光、传感器与空调完整支持；其余常见类型只读降级；灯光连续调光按 55ms 节流；空调支持 Gree / Haier / Midea / Generic 适配与 16..30°C 温控。
- **场景**：编排并逐步执行设备动作，展示每一步结果；局部失败不回滚已执行步骤；同一场景并发执行会被拒绝。
- **BLE 配网**：扫描 `YaoCore-GW-*`，使用 Protocomm Security1（X25519 + SHA256(PoP) + AES-256-CTR）完成握手，下发 Wi-Fi 并做加密探针校验，最后绑定到家庭。
- **局域网与云**：日常控制优先走局域网 P-HMAC；网关固件支持时启用 HTTPS + SPKI pinning；可选接入华为云 IoTDA，云命令“受理”不等于“执行”，需影子证据确认。
- **双语与安全存储**：zh-CN / en-US 资源与运行时切换；Asset Store 安全存储；PBKDF2|SHA256 120,000 次加盐；邀请码有效期与过期作废；秘密用后清零。
- **四 Tab 主壳层**：首页、房间、场景、我的，以及家庭 / 设备 / 配网 / 设置等二级页面。

## 4. 安装前提

1. **需要签名 HAP**：当前仓库没有可安装包。`build-profile.json5` 的 `signingConfigs` 为空，构建产物为**未签名 HAP**，不能安装到设备，也不能作为正式分发物。
2. **签名材料由项目所有者/授权签名人提供**：发布证书（`.cer`）、发布 Profile（`.p7b`）、密钥库（`.p12`）与 key alias。证书、私钥、Profile 与口令**不得**提交到仓库或写入日志。
3. **设备要求**：HarmonyOS NEXT，最低兼容 API 14；已验证的构建工具链为 API 26 / SDK 26.0.0.105。真实 API 14 设备运行未验证。
4. **权限**：应用声明 `INTERNET` 与 `ACCESS_BLUETOOTH`；首次 BLE 配网需要授予蓝牙权限。应用不提供用户可开启的开发者模式。
5. **网络**：局域网控制需手机与 ESP32-S3 网关在同一网络；云通道需可访问华为云 IoTDA，且 Token 由用户手工填写。
6. **从源码构建（可选）**：需 HarmonyOS SDK 26.0.0、DevEco Studio 或命令行工具、Node 24、Java 21、Python 3.10+；具体命令与已验证结果见 [`README.md`](../README.md)。默认 `assembleHap` 产物为 `buildMode=debug`；发布候选必须使用 `buildMode=release` 重新构建并签名。
7. **升级路径**：作为首次发布，当前没有公开旧版本。若曾在内部分发过同 `bundleName` 的构建，升级安装必须使用更高的 `versionCode`。

## 5. 首次使用

1. **创建家庭**：首次启动后创建家庭；创建者成为 ADMIN。家庭、房间、设备与场景数据保存在本机。
2. **添加网关（BLE 配网）**：授予蓝牙权限，扫描 `YaoCore-GW-*`，输入网关 PoP，选择 Wi-Fi 并提交；应用完成 Security1 握手、Wi-Fi 探针校验与家庭绑定。配网期间请保持手机靠近网关。
3. **局域网控制**：确保手机与网关在同一网络。v1 基线使用 P-HMAC（完整性与防重放）；网关固件 v2.1 宣告 LAN TLS 档案时可启用 HTTPS + SPKI pinning。TLS 校验失败会进入 P-BLOCKED，不会回退明文。
4. **接入华为云（可选）**：在设置中填写 IoTDA 参数与 Token。Token 需手工维护，过期后由用户更新；云命令被受理后，仍需匹配 `LastRequestId/LastSeq` 或不早于命令时刻的影子证据才视为完成。
5. **邀请成员**：通过邀请凭据邀请成员，设置角色与授权房间；邀请有过期时间。成员/密钥变更通过接触式导入收敛，不提供服务器实时同步。
6. **整理房间与设备**：创建房间、把设备移入房间或留在未分配池；设备别名可修改，但 `deviceId` 不变。
7. **创建场景**：选择设备与动作，保存后执行；逐步查看结果，局部失败不会回滚已执行的步骤。

## 6. 已知限制

| 限制 | 说明 |
|---|---|
| **P-HMAC 不提供机密性** | 局域网默认通道只保证完整性与防重放，**不提供载荷机密性**。在网关固件 v2.1 未就绪、使用 P-HMAC 时，不得宣称“端到端加密”或“TLS 已验证”。AES-256-GCM 载荷信封归档为 `EXT-GCM-001`，v1 不实现。 |
| **真实 TLS 依赖固件 v2.1** | P-TLS-PIN（HTTPS + SPKI pinning）需要网关固件 v2.1 与 LAN TLS 档案；当前仅在 host/mock 验证，真实 TLS 未验证。TLS 失败进入 P-BLOCKED，不提供明文回退。 |
| **设备矩阵未执行** | 无真机、模拟器实例与签名；真实 BLE、LAN、TLS pin、华为云 IoTDA、视觉/动效/无障碍、60/120fps 与真实硬件（门锁/门磁/AC/SHT30/PIR）均未执行（BLK-01..08）。ACCEPT-001 的 U-01..U-12 未执行，**用户验收未完成**。 |
| **i18n 残余** | 615 行 legacy triage 中仍有 6 条 `PENDING_REVIEW`、11 条 `B_REWRITE_REQUIRED`、C 类 6（4 `RECHECK_REQUIRED` + 2 `SAFETY_RECHECK_REQUIRED`）、D 类 3；544 条 `OBSOLETE_LEGACY` 不是删除清单。当前 UI 无 blocking 硬编码（0 blocking / 0 missing）。 |
| **D-030 / GAP-T18-01** | `FamilyRepository.addGatewayToFamily` 缺少 actor/RBAC；D-030 已书面接受为 v1 风险（RA-01），补偿控制为 UI ADMIN 门 + BLE PoP 前置 + 内部 API 边界。**缺口未关闭**。 |
| **R4-01** | `addGatewayToFamily` 已发起后的配网取消只能抑制 `BOUND` 发布，不能回滚已发起的 durable 写（Info）。 |
| **PORT-LOC-01** | `ClockPort` / `IdPort` 仍位于 `common/types/Ports.ets`；`check_layering` 的 0 violation 不等于 100% 端口位置合规。 |
| **ACK p95 不是验收数据** | 仅 `MOCK_ONLY`：localhost p50 0.553 ms / p95 0.609 ms / max 0.650 ms（N=100，warmup=5），随环境波动；不包含真实 LAN/TLS/BLE/UI。NFR 4.1/4.2/4.3 均为 partial。 |
| **GAP-AC-01..03** | 首页未显示局域网 IP；多家庭切换为跳转家庭管理页而非首页弹窗；房间图标未接线/展示。均为 Low，待用户接受为 v1 简化或派发修复。 |
| **云 Token 手工管理** | 无自动刷新/后端换取；Token 过期需用户更新。`DeviceInventoryJson` 云完成判定受 `PB-02` 未决结构限制，未知结构一律 `UNSUPPORTED`。 |
| **家庭同步为接触式收敛** | 无服务器；不提供实时同步或成员在线状态（v1 声明性限制）。 |
| **部分交互 DEFERRED** | 扫码/相机二维码、设备删除/改名、场景编辑、通知系统权限状态等未在 v1 UI 开放或仅保留诚实提示。 |
| **测试 lint / 覆盖率** | 测试源码未纳入 `codelinter`；无行/分支覆盖率；25 条 lint warning 为非阻断性能建议。 |
| **未签名构建** | 当前 HAP 未签名、不可安装、不可发布；默认构建为 `buildMode=debug`，发布候选需 `buildMode=release` 重建并签名。 |
| **包标识与版本未冻结** | `com.example.yaocore` / `vendor example` 待确认；`1.0.0` / `1000000` 未冻结。正式发布前变更包名会改变应用身份与签名 Profile。 |
| **许可证 TODO** | 仓库无项目级 `LICENSE`；在许可证确定前请勿假定可再分发。 |

## 7. 验证与证据边界

### 7.1 代码级验证（TEST-002 @ `e74a181`）

TEST-002 在最终集成候选上实际执行 11 项强制矩阵，全部 exit 0；RELEASE-001 在 `6cd9a88` 复跑关键项，结果一致：

| 检查 | 结果 |
|---|---|
| Host 纯逻辑测试 | **697/697 PASS** |
| 协议资产 crosscheck | **66/66 hard checks PASS**（14 条既有 `FINDING`） |
| 仿真器契约（HTTP + TLS） | **20/20 PASS** |
| 分层检查 | **221 files / 0 violation**（6 条 active D-12 例外） |
| 分层检查器 fixture | **27/27 PASS** |
| i18n `--strict-ui` | **0 blocking / 0 missing**；73 warning / 16 hardcoded |
| i18n legacy triage | **615 rows 一致** |
| 静态检查 | **0 error / 25 warning** |
| HAP 构建 | **BUILD SUCCESSFUL**（未签名） |
| 设备/模拟器测试 | **BLOCKED**（无 `hdc` target、无模拟器、无签名） |
| ACK p95 | **MOCK_ONLY**（0.609 ms，不作为 NFR 4.3 验收） |

### 7.2 验收就绪状态（ACCEPT-001）

- Verdict：**`READY_FOR_USER_ACCEPTANCE`（有条件）**；这是“可以开始用户验收”，**不是验收完成**。
- FR：26 项中 **24 covered（functional）+ 2 partial + 0 gap**；partial 为 `FR-HOME-003`（真实 SHT30/PIR 数据）与 `FR-SET-002`（P-HMAC 无机密性、真实 TLS pin）。
- NFR 4.1 / 4.2 / 4.3 均为 **partial**；4.3.3 的 60/120fps 无测量证据。
- 用户验收 U-01..U-12 **未执行**；设备矩阵 BLK-01..08 **未执行**。

### 7.3 构建产物边界

| 产物 | 大小 | SHA-256 | 模式 | 签名 |
|---|---|---|---|---|
| 默认构建（非发布候选） | 4,597,005 B | `1983ea22f54305c4817106e9bfc55122f42636071caceacca6f3dd3b219839c7` | `debug` | 无 |
| 补充 release 模式探测 | 1,616,146 B | `1602110da9213ffe0520e83d60836e96f964d97f339c571a21dd8239f735bd03` | `release` | 无 |

两类产物都**未签名、不可安装**。构建不是字节级可复现（同代码两次构建大小相同、哈希不同）；发布证据必须绑定 commit、工具链、命令、产物 SHA-256。签名后的最终 HAP 需在冻结 revision 上重新构建并重新记录。

> **证据边界**：代码级 `PASS` 只证明对应 revision、对应环境中的断言通过，**不等于设备验收、用户验收、NFR 达标或发布就绪**。不得把 Host/仿真器/构建结果外推为真实 BLE、LAN、TLS、云、传感器或性能结论。

详细证据：

- [`artifacts/60-testing/testing-stage-report.md`](../artifacts/60-testing/testing-stage-report.md)（TEST-002）
- [`artifacts/65-acceptance/acceptance-report.md`](../artifacts/65-acceptance/acceptance-report.md)（ACCEPT-001）
- [`artifacts/85-release/release-plan.md`](../artifacts/85-release/release-plan.md)（RELEASE-001）
- [`docs/release-checklist.md`](release-checklist.md)（RELEASE-CHECKLIST-001）

## 8. 反馈与支持

当前**没有正式发布渠道或支持承诺**。发布授权后，由项目所有者指定问题反馈渠道、支持范围与响应时限；在此之前，请勿把本草案作为对外支持文档。

反馈问题时请附：应用版本、设备型号与 OS/API、网关固件版本、复现步骤、脱敏日志与截图。以下内容**不得**出现在反馈、日志或截图中：

- Wi-Fi 密码、PoP、HMAC/控制密钥、云 Token；
- 证书私钥、密钥库/Profile 口令；
- 完整邀请凭据、家庭密钥；
- 用户个人信息或其他敏感数据。

## 9. 发布状态：`NOT_READY`

以下阻塞项来自 RELEASE-001 §2；未全部关闭（或经用户书面按范围接受）前，不得发布：

| ID | 阻塞项 | 当前状态 | 关闭条件 |
|---|---|---|---|
| **B-01** | 项目级许可证未定 | **BLOCKED**；无 `LICENSE`，README 标 TODO | 项目所有者选择 SPDX 许可证并提交 `LICENSE`；完成第三方依赖/模板许可证核对 |
| **B-02** | 无签名配置，HAP 不可安装 | **BLOCKED**；`signingConfigs: []` | 用户提供证书/Profile/密钥库与口令（不入库）；完成签名、签名校验与安装 smoke |
| **B-03** | 设备/用户验收未执行 | **BLOCKED**；U-01..U-12 未执行；`hdc` target 为空 | 按维护计划 §4 执行 BLK-01..08，或用户书面接受残余并限定范围 |
| **B-04** | GAP-AC-01..03 未决 | **PENDING** | 用户书面接受为 v1 简化，或派发 bounded fix 后重跑相关测试 |
| **B-05** | 远端/发布通道未授权 | **UNAUTHORIZED**；无 tag、未 push；本地 `main` 与 `origin/main` 历史不相关 | 用户选择远端/分支/PR-MR 策略并授权；配置保护分支与 CI |
| **B-06** | 包标识/版本/发布构建模式未冻结 | **PENDING**；`com.example.yaocore` / `example` 待确认；默认构建为 debug | 用户确认 bundleName/vendor/version；以 `buildMode=release` 重建 |
| **B-07** | CHANGELOG / Release Notes 缺失 | **本次已产出草案**；仍待发布评审/签核 | 评审并定稿 `CHANGELOG.md` 与本发布说明；用户/发布负责人签核 |
| **B-08** | 残余风险未逐项书面确认 | **PENDING** | 用户在发布 Gate 记录中逐项接受 D-030/R4-01/PORT-LOC-01/i18n/设备/ACK/NFR/测试 lint/未签名等风险，或派发修复 |

**结论**：`NOT_READY`。本文件不构成发布授权、签名授权、验收结论或法律意见；push、PR/MR、tag、签名、应用市场与任何远端发布操作均需项目所有者显式授权。

## 10. 许可证

项目级许可证仍为 **TODO**：仓库中没有 `LICENSE`。在项目所有者确定并提交许可证之前，请勿假定本仓库内容可再分发，也不要公开分发构建产物。`entry/` 中的模板/第三方文件保留其原始版权与许可声明；相关组件版权归各自权利人所有。

## 11. 相关文档

- 变更记录：[`CHANGELOG.md`](../CHANGELOG.md)
- 项目说明与已验证命令：[`README.md`](../README.md)
- 发布准备计划：[`artifacts/85-release/release-plan.md`](../artifacts/85-release/release-plan.md)
- 发布检查单：[`docs/release-checklist.md`](release-checklist.md)
- 测试 Stage 报告：[`artifacts/60-testing/testing-stage-report.md`](../artifacts/60-testing/testing-stage-report.md)
- 验收就绪报告：[`artifacts/65-acceptance/acceptance-report.md`](../artifacts/65-acceptance/acceptance-report.md)

*RELEASE-NOTES-001 v1.0.0 草案结束。未发布，未授权发布。*
