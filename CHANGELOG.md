# Changelog / 变更记录

YaoCore（爻构）的版本变更记录。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循语义化版本建议，日期使用 ISO 8601（UTC+8）。

- **Producer**: agent:technical-writer
- **Status**: DRAFT（发布准备文档；不构成发布记录、发布授权或验收结论）
- **Applies to**: `feat/yaocore-app` 的 v1.0.0 发布准备基线（RELEASE-001 @ `6cd9a88`；产品代码内容与 TEST-002 @ `e74a181` 一致）
- **Last updated**: 2026-10-18

> ## 发布状态：未发布
>
> 本文件中的 `[1.0.0]` 条目是 **v1.0.0 发布准备基线**，不是对外发布版本。当前 Release Verdict 为 **`NOT_READY`**（B-01..B-08 未全部关闭）。
>
> 对外发布前至少需要：
>
> 1. 项目所有者完成**发布授权**（发布范围、通道、远端与 tag 策略）；
> 2. 完成**签名**并产出可安装的签名 HAP（当前 `signingConfigs: []`，产物未签名）；
> 3. 完成**设备/用户验收**（ACCEPT-001 U-01..U-12、维护计划 §4 BLK-01..08）。
>
> 许可证仍为 **TODO**；在许可证确定前，请勿假定本仓库内容可再分发。

## [Unreleased]

（无。后续变更在此登记。）

## [1.0.0] - 2026-10-18

> 该日期是 **release 准备基线日期**，不是发布日期。版本号 `1.0.0` / `versionCode 1000000` 仍待项目所有者冻结；包标识 `com.example.yaocore` / `vendor example` 同样待确认。
>
> 代码级证据基线：TEST-002 @ `e74a181`（11 项矩阵 exit 0）；RELEASE-001 在 `6cd9a88` 复跑关键矩阵。设备/真实环境与用户验收未执行。

### Added（新增）

- **应用与架构**：HarmonyOS NEXT 原生 ArkTS 应用（`entry` 模块），MVVM + 单向依赖；组合根 `app/AppCompositionRoot.ets`；C-01..C-29 组件交付；`entry/src/main/ets/**` 221 个 ArkTS 文件（C-29 扫描口径）。
- **家庭与成员**：家庭创建与多家庭切换（创建者为 ADMIN）；成员邀请、角色调整、移除、退出、ADMIN 转让与解散家庭；v1 为本地语义，成员/密钥变更通过邀请凭据接触式收敛。
- **房间与设备**：房间创建/改名（`roomId` 不变）；设备加入、跨房间转移、未分配池；删除房间时设备置空并保护性禁用，不级联删除；设备别名与不可变 `deviceId`。
- **设备控制**：`door` / `light` / `sensor` / `ac` 完整支持；`switch` / `camera` / `curtain` / `fan` / `speaker` 只读降级；未知类型只读并记录协议偏差；真实 ACK 确认（响应验签、`request_id:seq` correlation、`result_code == 0`、`reported_state`）；灯光 55ms 节流；门锁/门磁到位确认；空调 Gree / Haier / Midea / Generic 适配与 16..30°C 温控。
- **场景**：场景编排与执行、逐步结果、局部失败不回滚、同一场景并发执行拒绝。
- **BLE 配网**：扫描 `YaoCore-GW-*`；Protocomm Security1（X25519 + SHA256(PoP) + AES-256-CTR）；身份 v2.1 / v2.0 受控回退；Wi-Fi 下发与加密探针校验；绑定到家庭。PoP、Wi-Fi 密码与会话秘密仅保存在临时内存并在用后清零。
- **局域网控制**：P-HMAC（HTTP + HMAC-SHA256 双向认证、防篡改、防重放、nonce 缓存与时钟容差）；身份 v2.1 且网关宣告 LAN TLS 档案时启用 P-TLS-PIN（HTTPS + SPKI 证书指纹固定）；TLS 校验失败进入 P-BLOCKED，禁止明文回退。
- **云通道**：华为云 IoTDA 参数配置与校验、签名云命令、影子轮询确认、`LastRequestId/LastSeq` 完成判定、Token 过期提示；Token 由用户手工填写，不做自动获取/刷新、MQTTS 直连或后端代理。
- **国际化**：zh-CN / en-US 资源与运行时切换；语义化 key 与资源加载/回退；i18n 检查器与 legacy triage 工具。
- **安全存储与凭据**：Asset Store 安全存储端口与实现；PBKDF2|SHA256 120,000 次加盐；邀请码有效期与过期作废；成员变更/移除后的会话失效；秘密用后清零。
- **工程与证据工具**：Node 24 Host 纯逻辑测试运行器；协议资产 crosscheck；DEV-ONLY localhost HTTP/TLS 网关仿真器；分层检查与 fixture；i18n 检查/triage；ACK 延迟 harness（仅 `MOCK_ONLY`）。
- **文档**：README（实现状态、已验证命令、已知限制）、契约基线、ADR-001..004、DES-A/DES-B、测试/验收/评审/集成/维护与发布准备文档。

### Security（安全）

- **BLE PoP 校验 fail-closed**：PoP 错误、设备验签失败或握手状态非法时销毁会话，不进入后续流程。
- **请求完整性与防重放**：HMAC-SHA256 请求签名；随机 nonce 与 ±120s 时钟窗口；重复/过期 nonce 拒绝；响应验签失败不得显示控制成功。
- **TLS 失败不回退明文**：SPKI pin 不匹配或 TLS 握手失败进入 P-BLOCKED；不提供“忽略证书错误”或明文降级路径。
- **Mock/仿真生产排除**：生产客户端拒收 `X-YaoCore-Simulator: DEV-ONLY` 与 `DEV_SIMULATOR_ONLY`；release 模式 HAP 扫描中 `MockGatewayService` / `MockBleProvisioningClient` / `ohosTest` / `service/mock` 均 0 命中。
- **凭据与秘密纪律**：Wi-Fi 密码、PoP、HMAC 密钥、云 Token 与会话秘密不写入日志/证据/仓库；临时秘密用后清零；日志与发布证据需脱敏。
- **成员与角色边界**：UI ADMIN 门、邀请过期、角色变更/移除后的会话失效；服务层 RBAC 缺口 D-030 仍为已接受风险，见 Known Issues。

### Known Issues（已知问题与限制）

| ID / 主题 | 状态与影响 |
|---|---|
| **D-030 / GAP-T18-01** | `FamilyRepository.addGatewayToFamily` 缺少 actor/RBAC；D-030 已书面接受为 v1 风险（RA-01），补偿控制为 UI ADMIN 门 + BLE PoP 前置 + 内部 API 边界。**缺口未关闭**，不得宣称服务层 RBAC 已闭合。 |
| **R4-01 / RA-02** | `addGatewayToFamily` 已发起后的配网取消只能抑制 `BOUND` 发布，不能回滚已发起的 durable 写（Info）。 |
| **PORT-LOC-01** | `ClockPort` / `IdPort` 因冻结签名与 D-01 仍位于 `common/types/Ports.ets`；17 条端口登记中 16 条已迁移。`check_layering` 的 0 violation **不等于** 100% 端口位置合规。 |
| **i18n 残余** | 615 行 legacy triage：10 ACCEPTED / 46 MIGRATED / 6 PENDING_REVIEW / 0 INLINE_LITERAL / 544 OBSOLETE_LEGACY；另 11 条 B_REWRITE_REQUIRED、C 类 6（4 RECHECK + 2 SAFETY_RECHECK）、D 类 3。`MIGRATED` 不等于人工签收，`OBSOLETE_LEGACY` 不是删除清单。当前 UI 无 blocking 硬编码（0 blocking / 0 missing）。 |
| **设备/真实环境未验证** | 无真机、模拟器实例与签名；真实 BLE、LAN、TLS pin、华为云 IoTDA、视觉/动效/无障碍与 60/120fps 均未执行（BLK-01..08）。ACCEPT-001 的 U-01..U-12 未执行，**用户验收未完成**。 |
| **ACK p95 仅 MOCK_ONLY** | localhost 测得 p50 0.553 ms / p95 0.609 ms / max 0.650 ms（N=100，warmup=5），随环境波动；不包含 ArkTS 验签、状态应用、真实 LAN/TLS/BLE/UI。**不是 NFR 4.3 验收数据**。 |
| **未签名构建** | `signingConfigs: []`；当前 HAP 未签名、不可安装、不可发布。默认 `assembleHap` 为 `buildMode=debug`；发布候选需以 `buildMode=release` 重建并签名。 |
| **GAP-AC-01..03** | `FR-HOME-001` 未显示 LAN IP；多家庭切换为跳转家庭管理页而非首页弹窗；`FR-ROOM-001` 房间图标未接线/展示。均为 Low，待用户书面接受为 v1 简化或派发 bounded fix。 |
| **NFR partial** | NFR 4.1 / 4.2 / 4.3 均为 partial；4.3.3 的 60/120fps 无测量证据。P-HMAC 不提供载荷机密性；AES-256-GCM 载荷信封归档为 `EXT-GCM-001`，v1 不实现。 |
| **TLS 依赖固件 v2.1** | 真实 LAN TLS / SPKI pin 需网关固件 v2.1 与 LAN TLS 档案；当前仅在 host/mock 验证，真实 TLS 未验证。 |
| **云 Token 手工管理** | 无自动刷新/后端换取；Token 过期需用户更新。`DeviceInventoryJson` 云完成判定受 `PB-02` 未决结构限制，未知结构一律 `UNSUPPORTED`。 |
| **家庭同步为接触式收敛** | 无服务器；不提供实时同步或成员在线状态（v1 声明性限制）。 |
| **部分交互 DEFERRED** | 扫码/相机二维码、设备删除/改名、场景编辑、通知系统权限状态等未在 v1 UI 开放或仅保留诚实提示。 |
| **测试 lint / 覆盖率** | `code-linter.json5` 忽略 `src/test/**`、`src/ohosTest/**`；无行/分支覆盖率；25 条 lint warning 为非阻断性能建议。 |
| **构建可复现性** | 同一 release 代码的两次构建大小相同但 SHA-256 不同（归档时间戳/打包元数据）；不得承诺字节级可复现，证据须绑定 commit + 工具链 + 命令 + SHA-256。 |
| **包标识/版本未冻结** | `bundleName=com.example.yaocore`、`vendor=example` 待项目所有者确认；`versionName 1.0.0` / `versionCode 1000000` 未冻结。 |
| **许可证 TODO** | 仓库无项目级 `LICENSE`；在许可证确定前不得假定可再分发，也不得公开分发产物。 |

### Verification（验证，代码级）

> 以下结果来自 TEST-002 @ `e74a181`；RELEASE-001 在 `6cd9a88` 复跑关键项，exit 0。`PASS` 仅表示对应 revision、对应环境实际执行且断言通过，**不等于设备验收、用户验收或发布就绪**。

| 检查 | 结果 | 边界 |
|---|---|---|
| Host 纯逻辑测试 | **697/697 PASS** | Node 24 runner；不是 ArkTS/Hypium 设备运行 |
| 协议资产 crosscheck | **66/66 hard checks PASS**（14 条既有 `FINDING`） | 冻结输入勘误线索，不阻断 |
| 仿真器契约（HTTP + TLS） | **20/20 PASS** | localhost；DEV-ONLY 测试夹具 |
| 分层检查 | **221 files / 0 violation**；`exceptions_used=6` | 含 6 条 active D-12 例外；`PORT-LOC-01` OPEN |
| 分层检查器 fixture | **27/27 PASS** | 检查器自测 |
| i18n `--strict-ui` | **0 blocking / 0 missing**；73 warning / 16 hardcoded | 短英文 UI 文案会提升为 blocking |
| i18n legacy triage | **615 rows 一致** | CSV 与计算 triage 一致；不等于人工签收 |
| 静态检查 | **0 error / 25 warning** | warning 为非阻断性能建议 |
| HAP 构建 | **BUILD SUCCESSFUL** | 未签名；默认产物为 debug 模式 |
| 设备/模拟器测试 | **BLOCKED** | 无 `hdc` target、无模拟器实例、无签名 |
| ACK p95 | **MOCK_ONLY** | localhost 0.609 ms；不是 NFR 4.3 验收数据 |

详细证据与分类见 [`artifacts/60-testing/testing-stage-report.md`](artifacts/60-testing/testing-stage-report.md)（TEST-002）、[`artifacts/65-acceptance/acceptance-report.md`](artifacts/65-acceptance/acceptance-report.md)（ACCEPT-001）与 [`artifacts/85-release/release-plan.md`](artifacts/85-release/release-plan.md)（RELEASE-001）。

---

## 链接

- 用户发布说明（草案）：[`docs/release-notes-v1.0.0.md`](docs/release-notes-v1.0.0.md)
- 发布准备计划：[`artifacts/85-release/release-plan.md`](artifacts/85-release/release-plan.md)
- 发布检查单：[`docs/release-checklist.md`](docs/release-checklist.md)
- 项目 README：[`README.md`](README.md)

*本文件为发布准备文档，不构成发布授权、签名授权、验收结论或法律意见。*
