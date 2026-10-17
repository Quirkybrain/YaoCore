# 全系统独立评审报告（T-20 / IG-4 前置）

- **Artifact ID**: REV-001-FINAL-SYSTEM
- **Producer**: agent:quality-reviewer
- **Type**: Independent System Review Report（代码级 / 测试证据真实性 / Stage Gate 建议）
- **Status**: COMPLETE（供 IG-4、G-013/G-014 消费；**不授予** Stage Gate、IG-3/IG-4 或用户验收）
- **Date**: 2026-10-18
- **Task**: `wp-083-review-system`（T-20；task 分支 `task/wp-083-review`，父分支 `feat/yaocore-app`，base commit `577dbc633e70ff9e9a2062b0adf8d33715cb5af1`）
- **Reviewed revision**: `577dbc6`（`chore(repo): 记录 wp-082 合并集成证据`；T-19 证据基线 `4f7c26b`，`4f7c26b..577dbc6` 未修改产品代码）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`
- **Review scope**: `entry/src/main/ets/**`、`entry/src/main/resources/`、`entry/src/test/`、`tools/contract/`、`artifacts/60-testing/test-report.md`；只读复验，未修改被审代码/测试/契约。
- **唯一写入**: 本报告（覆写占位文件；占位文件的 Producer 偏差不适用于本正式报告）。

> **结论先行**：在 `577dbc6` 上独立复跑，T-19 的主要声明可复现：host **696/696**、crosscheck **66/66**、仿真器契约 **20/20（HTTP+TLS）**、构建 **BUILD SUCCESSFUL**、`codelinter` **0 error / 25 warning**、i18n **0 blocking / 0 missing**、分层检查器 **0 violation（13 条 pending 例外可见）**。安全核心（SEC-N26 常数时间比较、Mock 生产排除、HMAC/DEV-ONLY/TLS pin fail-closed）未发现 High/Critical 缺陷。
>
> 但本评审给出 **PASS_WITH_ACCEPTED_RISKS（代码级，条件式）**，不是无条件 PASS：**端口位置例外仍由检查器硬编码放行、未进入版本化 allowlist/契约登记（Medium）**；R3-01 的 13 条 `pending-T-20` 尚未被架构 owner 正式化；T-19 报告的 ACK p95 数字与证据文件不一致；C-20 Mock 仍产出退役错误码别名；i18n 的 `--strict-ui` 实际是 no-op；C-29 fixture 自测缺 D-03/D-05。上述均为治理/工具/文档级问题，不影响产品运行路径，但 **Stage Gate 必须逐项记录或关闭**。同时，README 仍停留在“Hello World/未实现”状态，T-21/T-22 未完成，**G-013/G-014 当前均不能判定 PASS**。

---

## 1. 范围、revision、输入与独立性

| 项 | 本次实测 / 结论 | 证据 |
|---|---|---|
| 仓库 / 分支 | `/home/quirkybrain/code/harmony-projects/YaoCore`；`task/wp-083-review` | `git branch --show-current` |
| Reviewed HEAD | `577dbc633e70ff9e9a2062b0adf8d33715cb5af1` | `git rev-parse HEAD` |
| T-19 证据基线 | `4f7c26b`；`4f7c26b..577dbc6` 仅新增测试证据、`ViewModelDevice.test.mjs`、`tools/contract/**`、test-plan/report 与合并报告，**无 `entry/src/main/ets/**`/资源变更** | `git diff --name-status 4f7c26b..577dbc6` |
| 工作树 | 评审期间保持干净（构建产物均在 ignored `build/`/`.hvigor/`） | `git status --short` |
| 输入完整性 | 8 个 handoff 输入的 SHA-256 全部一致 | 逐项 `sha256sum` 对照 |
| 作者独立性 | 本评审未参与 T-06..T-19 的实现/修复，也未修改被审代码、测试或契约；唯一写入为本报告 | 本文件为唯一变更 |
| 评审限制 | 无真机/模拟器/签名；无法执行 ArkUI 渲染、视觉/A11y、真实 BLE/LAN/TLS/云、真实 ACK p95、60/120fps | 与 T-19 的 `BLOCKED`/`UNAVAILABLE` 边界一致 |

**评审目标覆盖**：`entry/src/main/ets/**`（209 个 ArkTS 文件，C-29 扫描口径）、`entry/src/main/resources/`（base/en_US/zh-CN/dark）、`entry/src/test/`（host 696 + 证据 + i18n 检查器）、`tools/contract/`（C-29/crosscheck/ACK harness）、`artifacts/60-testing/test-report.md`（TEST-REPORT-001）。

**不在本次范围**：README（T-21）、T-22 集成报告、设备/视觉/真实网络验收、用户验收、release 打包。README 仅作为 Stage Gate 依赖被提及，不作为本报告的被审对象。

---

## 2. 独立复验结果（cwd = 仓库根，2026-10-18 本次实际执行）

| # | 命令 | 本次实测 | 与 T-19 声明的一致性 |
|---|---|---|---|
| 1 | `entry/src/test/run-host-tests.sh` | **`1..696` / tests 696 / pass 696 / fail 0 / skipped 0**；exit 0；duration ≈ 3006 ms | 一致 |
| 2 | `hvigorw clean assembleHap --no-daemon` | **BUILD SUCCESSFUL in 15 s 596 ms**；35 tasks；unsigned HAP；0 ERROR | 一致（耗时随缓存不同） |
| 3 | `codelinter -c code-linter.json5 -p default .` | **Defects 25 / Errors 0 / Warns 25 / Suggestions 0**；exit 0 | 一致 |
| 4 | `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **BUILD SUCCESSFUL in 13 s 183 ms**；**COMPILED_ONLY**（未运行断言） | 一致 |
| 5 | `python3 tools/contract/crosscheck_protocol_assets.py` | **66 PASS / 0 FAIL / 14 FINDING**；hard checks ALL PASS；exit 0 | 一致 |
| 6 | `no_proxy=127.0.0.1,localhost python3 -m unittest tools.simulator.test_gateway_contract -v` | **Ran 20 tests … OK**；exit 0（含 3 条 TLS 测试） | 一致 |
| 7 | 仿真器 HTTP 实启（`:9388`）+ `curl --noproxy '*'` | 200；**4 devices**；`X-YaoCore-Simulator: DEV-ONLY` | 一致 |
| 8 | 仿真器 TLS 实启（`:9449`，`--tls --cert --key`）+ `curl --noproxy '*' -k` | 200；`X-YaoCore-Simulator: DEV-ONLY`；SPKI 测试由 #6 的 `test_bundled_certificate_spki_is_lower_hex_sha256` 覆盖 | 一致 |
| 9 | `python3 entry/src/test/i18n/check_i18n.py --root . --report … --allowlist … --strict-ui` | exit 0；**blocking 0 / missing 0 / warnings 121 / hardcoded 82**；CHK-01..09 全 PASS | 一致 |
| 10 | `python3 tools/contract/check_layering.py --root . --report …` | **209 files / violations 0 / exceptions_used 13 / pending 13**；exit 0 | 一致 |
| 11 | `python3 -m unittest tools.contract.test_check_layering -v` | **4/4 PASS**；exit 0 | 一致 |
| 12 | `python3 tools/contract/measure_ack_latency.py --samples 100 --warmup 5` | **MOCK_ONLY**：p50 **0.537 ms** / p95 **0.599 ms** / max 0.633 ms；0 failures | **数字与报告不一致，见 F-03** |
| 13 | HAP 内容独立检查 | 14 个条目；`entry-default-unsigned.hap` ≈ 4.4 MB；`modules.abc` ≈ 2.7 MB；`sourceMaps.map` 中 **`Mock` = 0、`ohosTest` = 0、`service/mock` = 0** | 补充 T-19 未提供的 HAP 级证据 |
| 14 | `git status --short --ignored` / 证书与产物审计 | 无 HAP、`.env`、签名材料、构建目录入库；仅 `tools/simulator/certs/*.pem`（T-05 授权的 PUBLIC TEST DATA） | 与 SC-02/SC-07 一致 |

> 复验只证明上述命令在当前 revision/环境的结果；不证明 ArkUI 渲染、真实 BLE/LAN/TLS/云、真实硬件 ACK、视觉/A11y、真实 p95 或 60/120fps。

---

## 3. 逐层结论（T-19 声明核对）

| 层 | T-19 声明 | 本次复核 | 结论 |
|---|---|---|---|
| 依赖安装 | `ohpm install` exit 0 | 未重复安装；依赖已就绪（host/build 可复跑） | 采信 T-19 证据；不作为独立复验项 |
| 构建 | BUILD SUCCESSFUL | **BUILD SUCCESSFUL**；unsigned | PASS |
| 静态检查 | 0 error / 25 warning | **0 error / 25 warning** | PASS（25 条均为性能建议，见 §8） |
| 测试 HAP | COMPILED_ONLY | **BUILD SUCCESSFUL**，未运行 | COMPILED_ONLY（不是 PASS） |
| Host | 696/696 | **696/696** | PASS |
| 契约 crosscheck | 66/66 | **66/66** | PASS |
| 仿真器契约 | 20/20（HTTP+TLS） | **20/20**；HTTP/TLS 实启均 200 + DEV-ONLY | PASS |
| i18n | 0 blocking / 0 missing | **0 / 0**；parity 经 plural 归一后 100% | PASS（工具债务见 F-05） |
| 分层 | 0 violation + 13 pending | **0 / 13 pending** | PASS（含未正式化例外，见 F-01/F-02） |
| 安全负例 | 19/19 focused | 全量 696 已包含全部 19 条；未单独重跑 focused 命令 | 采信全量 TAP；不作为独立 focused 复验 |
| ACK p95 | MOCK_ONLY 0.601 ms | **MOCK_ONLY**；本次 0.599 ms | **MOCK_ONLY；报告数字与证据不一致（F-03）** |
| 设备/UI/BLE/LAN/云/视觉/fps | BLOCKED / UNAVAILABLE | 同左；无设备/签名 | **BLOCKED / UNAVAILABLE；未写成 PASS** |

### 3.1 测试真实性核对

- T-19 报告未发现把 `BLOCKED`、`COMPILED_ONLY`、`NOT_RUN`、`UNAVAILABLE` 写成 PASS 的情况；设备矩阵与真实性能均保持显式边界。
- 696 条 host 用例中，报告引用的关键用例名（SEC-N01..N26、FR 矩阵示例、`T19_R3_*` 新用例、`T11/T17` Mock 守卫）均可在本次 TAP 中找到并通过；仿真器侧 9 条用例由 `Ran 20 tests … OK` 覆盖。
- 唯一实质不一致是 ACK p95 的三项数字（F-03）；该指标本身标注为 `MOCK_ONLY`，不影响 NFR 4.3 的 `partial` 分类，但报告应与证据文件逐字一致。
- T-19 报告称“新增 2 条 R3-01 并发/失败隔离用例、原 694 条保留”：本次 696 条通过；`git diff 4f7c26b..577dbc6` 的 `ViewModelDevice.test.mjs` 仅新增两条 `T19_R3_*` 用例，未删除/弱化既有断言，支持该声明。

---

## 4. FR/NFR 覆盖复核

### 4.1 26 FR（24 covered / 2 partial / 0 gap）

| 项 | 复核结论 | 说明 |
|---|---|---|
| 行数与分类 | **26 FR；24 covered（host/source）；2 partial；0 gap** | 与 T-19 §5 统计一致；无缺行 |
| 2 个 partial | **FR-HOME-003**（真实 SHT30/PIR 数据 UNAVAILABLE）、**FR-SET-002**（P-HMAC 无机密性；真实 TLS pin 设备 BLOCKED；LAN GCM 归档） | 分类有证据支撑，未把真实设备/机密性写成 covered |
| UI/设备列 | 全部 `BLOCKED`/`UNAVAILABLE`，未计入 covered | 与 §7 一致 |
| v1 限制 | FR-FAM-004 明确标注“v1 本地语义” | 与 D-009/D-010/ADR-003 一致 |
| 证据抽取 | 抽查的 host 用例名均存在且通过；`T18_*` 源级守卫被明确标为 host/source | 未发现“只有测试名、没有实现”的引用 |

**保留意见**：`covered (host)` 的含义是组件/VM/协议纯逻辑有当前 revision 的 host 证据，不等于 UI/设备/真实网络验收。`FR-HOME-004`、`FR-DEV-005`、`FR-SET-001` 等行含 `source-level` 断言，证明力弱于行为测试；报告已用 `(host/source)` 标注，属于诚实披露。Stage Gate 不得把 `covered` 扩展解释为“设备/视觉完成”。

### 4.2 NFR 4.1 / 4.2 / 4.3

| NFR | T-19 分类 | 复核 | 结论 |
|---|---|---|---|
| 4.1 传输安全 | **partial** | HMAC/时间窗/nonce/replay/TLS pin 全链有 host/仿真证据；P-HMAC 按 D-007/ADR-002 明确无机密性；真实 TLS 设备 BLOCKED | **partial 成立** |
| 4.2 存储安全 | **partial** | PBKDF2 120k、SecretStore/SecretDraft zeroize、邀请过期/账本 host PASS；设备 Asset Store/RDB 未执行 | **partial 成立** |
| 4.3 性能 | **partial** | 55ms 7 条 PASS；ACK p95 仅 `MOCK_ONLY`；真实 p95/60/120fps UNAVAILABLE | **partial 成立**；不得用 mock 数字通过验收 |

**BLOCKED/UNAVAILABLE 清单完整性**：T-19 §7 的 BLK-01..BLK-08 覆盖了本阶段测试计划/交付计划中列出的设备、UI 视觉/A11y、真实 BLE、LAN/TLS、真实云、AC/门磁/SHT30/PIR、fps/真实 p95、onDeviceTest/Hypium 运行限制；未发现遗漏的“应测但未列”类别。覆盖工具缺失、测试源码未 lint 等属于 §8.2 的已知 gap，不是被伪装成 PASS 的项。

---

## 5. 安全复核

### 5.1 SEC-N26（常数时间比较）

**代码复核结论：PASS（算法级；未做统计计时测量）。**

| 调用点 | 实现 | 结论 |
|---|---|---|
| `service/crypto/CryptoService.ets:218-227` | 扫描 `max(a.length,b.length)`；长度 XOR 折入累加器；无 early return；长度不匹配返回 false | **常数时间实现正确**；长度本身是公开量 |
| `service/security/ResponseVerifier.ets:102` | HMAC-SHA256 期望签名与响应 `sign` 均转 UTF-8 后调用 `constantTimeEqual` | PASS；且 header 的 alg/key_id/correlation 在验签前 fail-closed |
| `service/gateway/adapters/TlsPinCheck.ets:54` | SPKI SHA-256 与 pin 字节调用 `constantTimeEqual` | PASS |
| `service/ble/Security1Session.ets:148` | `device_verify_data` 解密结果与 client public 调用 `constantTimeEqual` | PASS；错误 PoP 直接 BROKEN/destroy |
| `service/auth/AuthService.ets:686` | PBKDF2 派生哈希与存储哈希调用 `constantTimeEqual` | PASS |
| `service/invite/InviteService.ets:396` | 回执 HMAC 与期望值调用 `constantTimeEqual` | PASS |

**负例/证据**：`C04_CryptoService_constantTimeEqualHandlesEveryShape` 覆盖相等、首/尾字节不等、长短不等、双方空数组；`C04_CryptoService_inputLengthMismatchFromProviderFailsClosed` 覆盖 provider 返回 31/33 字节时 fail-closed。产品代码中未发现对签名/MAC/pin/口令哈希的非常数时间字节比较；`X25519KeyCodec.ets:62` 的前缀比较是公开 DER 前缀，不属于秘密比较。

**限制**：上述是代码/负例层面的常数时间证据，不是统计计时测量；在无设备/无高精度计时环境时，不应宣称“已用计时实验证明无时序泄漏”。T-19 的“PASS（host）+ 待 T-20 复核”在本次复核后可以关闭其“待复核”部分，但保留该测量限制。

### 5.2 安全矩阵 SEC-N01..N26

- 26 项均有当前 revision 的 host 和/或仿真器证据；设备相关项（SEC-N15/N16/N21 等）明确标注 `BLOCKED`，没有把设备项写成 PASS。
- 抽查的 host 用例（SEC-N01..N14、N17..N26）全部在本次 696 TAP 中通过；仿真器侧 9 条用例由 20/20 套件覆盖。
- SEC-N25（Mock 生产排除）：源级 `T11_noProductionFileImportsC20MockOrOhosTest`、`T17_productionMockExclusionCoversAllMainSources` 通过；本次另外检查 HAP：`modules.abc`/`sourceMaps.map` 中 `Mock`、`ohosTest`、`service/mock` 均为 **0**，14 个 HAP 条目无测试/源文件泄漏。**源级 + HAP 级均通过**。
- SEC-N13/SC-11：`LocalGatewayService.rejectDevOnly` 在 `verifier.verify` 与 JSON 解析之前执行；DEV-ONLY / DEV_SIMULATOR_ONLY 均 fail-closed。P-BLOCKED 不发送请求；TLS pin 失败不走明文回退。

---

## 6. 架构、契约与 i18n 合规

### 6.1 D-12/D-17 与 DI

| 检查 | 结论 | 证据 |
|---|---|---|
| `pages/**`/`components/**` import 白名单 | **PASS（13 条例外可见，未正式化）** | `check_layering` 0 violation；13 条 D-12 pending |
| `app/**` 依赖方向 / 反向 import | **PASS** | 检查器 D-17 0 violation |
| `@Provide/@Consume` | **PASS（0 命中）** | 检查器 per-file 规则 + 手工 grep（仅注释提及） |
| 页面/组件构造 service/repository/VM | **PASS（0 命中）** | 检查器 D-11/D-12 per-file `new` 检查；手工 grep 仅 `Index.ets` 构造 `NavigationService`（D-12 seam） |
| 生产组合根唯一装配 | **PASS** | `AppCompositionRoot` 构造/注入；`EntryAbility` 仅创建 root；页面通过 `PageVmFactoryPort`/显式 props |
| 显式 props DI | **PASS** | 页面/组件无 `@Provide/@Consume`；`i18n`/`localeRevision` 显式传递 |

### 6.2 RBAC 服务层

- `RoomService` 的创建/改名/删除/分配/移除等管理动作调用 `requireAdmin`，actor 缺省为 v1 local-admin trust（已在 T-18/R2-07 记录）；显式非 ADMIN actor 被拒绝。
- `FamilyService` 的邀请/成员/角色/解散/移除等管理动作同样有 `requireAdmin`；`SceneService` 的 GUEST 场景变更 fail-closed。
- **GAP-T18-01 仍在**：`FamilyRepository.addGatewayToFamily(familyId, gatewayId)` 无 actor/RBAC；`BleProvisioningViewModel` 直接调用该仓储方法。D-030 已书面接受 v1 风险，但 **未关闭**。本评审重申：不得宣称“网关管理服务层 RBAC 已闭合”；Stage Gate 必须按 D-030 记录限制与补偿控制（UI ADMIN 门 + BLE PoP 前置）。

### 6.3 错误命名/双轨

- 生产路径：`ResponseVerifier`、`LocalGatewayService`、`ProtocolErrors` 使用 `RESPONSE_AUTH_FAILED`/`RESPONSE_CORRELATION_MISMATCH`（header）与 `ACK_CORRELATION_MISMATCH`（ACK body），符合 contract-baseline §4.5/DES-A §3.2.3。
- **C-20 MockGatewayService 仍产出退役别名**：`MockGatewayService.ets:302-306` 把 header 验签失败映射为 `CONTROL_RESPONSE_AUTH_FAILED`，把 header correlation 失败映射为 `ACK_CORRELATION_MISMATCH`；`GatewayMock.test.mjs:179` 反而断言退役 code。该问题自 T-12 D-4 起已登记为“后续 mock 对齐”，至今未关闭。它仅影响测试替身/测试保真度，不影响生产 `LocalGatewayService` 路径。见 F-04。

### 6.4 i18n 纪律

| 项 | 结论 | 证据 |
|---|---|---|
| 单一代码库（I18N-01） | **PASS** | CHK-08 0 findings；无 `_en/_zh` 分支文件或 `isChinese()` 分支 |
| key parity（I18N-05） | **PASS（100%）** | rawfile：en 545 / zh 543，差异仅 `device.count_one/_other` 复数变体；base/en_US string.json 各 53，键集相同 |
| 硬编码 UI 文案（I18N-02） | **PASS（人工复核）** | 页面/组件未发现 `Text('字面量')`/`Button('字面量')`/未走 `t()` 的 placeholder；82 条 hardcoded 警告经逐条抽查均为状态 token、CSS shadow 字符串、AC 协议品牌别名或 Mock 测试文案，不是用户可见 UI |
| fallback/插值/语言入口 | **PASS（host）** | `I18nService` 纯逻辑；CHK-01..09 0 blocking；语言切换设备 UI 仍 BLOCKED |
| 颜色资源（I18N-08） | **PASS（有已知别名）** | 新 `AppColors` 使用 `$r('app.color.*')`；旧 shell `shell_*` 仍存在（F-22/T-18 已记录为 Info），未造成功能错误 |

**工具债务**：`check_i18n.py` 的 `--strict-ui` 参数从未被读取（F-05）；短 UI 文案仍以 `warning` 输出，注释称“T-17/T-18 迁移后提升为 blocking”，但迁移已完成而未提升。当前没有实际硬编码 UI 违规，但门禁的“strict”语义有误导性。

---

## 7. R3-01 与端口位置例外收口建议

### 7.1 R3-01（13 条 pages DTO/枚举 import）

**现状**：`tools/contract/layering_allowlist.json` 有 13 条 D-12 例外（10 条 `type_only: true`，3 条值 import：`FamilyManagePage` 的 `CreateInvitationInput`/`FamilyJoinPhase`、`ProvisioningPage` 的 `BleProvisioningDevice`/`ProvisioningState`/`WifiAp`、`SettingsPage` 的 `CloudTransportState`），全部 `status: pending-T-20`；检查器报告 13 条 used。T-19 报告 §8.2 明确不得把当前 0 violation 解释为 D-12 已完全收口。

**建议（优先 A，T-20 无权代替架构 owner 落文）**：

- **A. 正式化（推荐，符合 DES-B §23.7 的既有裁定方向）**：由 `solution-architect` 在下一维护轮/Change Impact 中把 13 条按“公共只读 DTO/UI 枚举”纳入 DES-B §2.3 D-12 与 §18.1 的文件/符号级 allowlist；对 3 条值 import 单独说明“页面本地表单状态/枚举，不调用 service 实现、无 I/O”，或将其迁移到 `model/**`。随后把 allowlist `status` 从 `pending-T-20` 改为 `accepted`。**不得**把整目录 `service/**`/`repository/**` 放宽。
- **B. 迁移（不作为 v1 Gate 前置）**：把 UI 需要的类型迁到 `model/**`（DES-B §23.7 已给出可选集合）；工作量大、会触及已稳定组件，建议作为独立重构任务，不与 T-20 并行。
- **C. 若 Stage Gate 选择受控接受**：必须在 G-014 记录每一项、理由、范围、补偿控制与失效条件；`pending-T-20` 不能原样进入 Gate 后仍无限期存在。

**责任边界**：T-20 是只读评审，不能修改 DES-B 或 allowlist；当前 T-19 把“T-20 必须正式纳入”写成执行动作，超出了 T-20 的写边界。实际 owner 应为 `solution-architect`（契约变更）或 Orchestrator（Stage Gate 受控接受）。

### 7.2 端口位置例外

**现状**：DES-A §0.3/§2.1/§3.7 名义上把端口放在 `entry/src/main/ets/contracts/**`；仓库中 **没有 `contracts/` 目录**。端口实际散落在：

- `common/types/Ports.ets`
- `service/crypto/CryptoPort.ets`
- `service/storage/{RdbStore,PreferencesStore,SecretStore,SecretDraftPort,MigrationPort}.ets`
- `service/ble/BleProvisioningPorts.ets`、`service/ble/GattEndpointMap.ets`
- `service/gateway/GatewayTransportPorts.ets`、`service/gateway/DiscoveryModels.ets`
- `service/cloud/CloudPorts.ets`、`service/cloud/SystemTimerPort.ets`
- `service/i18n/I18nPorts.ets`
- `repository/DomainPorts.ets`、`repository/GatewayPorts.ets`
- `viewmodel/ViewModelPorts.ets`、`app/AppPlatformPorts.ets`、`service/scene/SceneTimerPort.ets` 等

`check_layering.py` 通过 `_is_storage_port_path`（:550-561）和 `_is_viewmodel_service_port`（:564-578）把这些路径**硬编码**视为端口，因此 `layering_allowlist.json` 中 **没有端口位置条目**。T-19 报告 §3.2 称之为“accepted（实现内置）”，但只有 CQG-T06/T07 有文字记录，T-08/T-09/T-11/T-14 未形成统一登记；报告又把迁移指向“C-17/T-20”，而 C-17 已完成、T-20 只读，**没有后续实现任务实际承接迁移**。

**建议（受控接受或迁移，不得无声放宽）**：

- **A. v1 受控接受（推荐给 Stage Gate，若不希望 Gate 前做大重构）**：由 `solution-architect` 在 DES-A §2.1/§3.7 与 DES-B §2.3/§18.1 增加“端口物理位置例外”登记（逐文件、理由、签名不变、无重复实现、失效条件/迁移触发），并把同样条目写入 `layering_allowlist.json`（`status: accepted-location-exception`、`evidence` 指向 Gate/评审），让检查器从 allowlist 读取，而不是在代码里硬编码“这些 service 文件就是端口”。这样 Gate 的 PASS 不再隐含“端口位置合规”。
- **B. 迁移**：建立 `entry/src/main/ets/contracts/**` 并迁移端口；这是独立重构任务，需 Change Impact、逐文件签名保持、全量回归，不建议在 T-20/T-22 窗口内执行。
- **无论 A/B**：Stage Gate 必须明确“当前 0 violation 不代表端口位置已合规”；不得把 `check_layering` PASS 解释为 DES-A 路径契约已满足。

---

## 8. 可维护性、性能与已知限制

| 项 | 观察 | 风险/建议 |
|---|---|---|
| 剩余 lint warning | 25 条：23 条 `@performance/avoid-overusing-custom-component-check`（CommonControls/DeviceCards/DeviceGrid/RoomChipBar/ShellBackdrop/ShellViews/StatusPanels），2 条 `hp-arkui-no-state-var-access-in-loop`（DeviceControlPage:213、ProfilePage:77） | 非阻断；两条 loop 警告在事件/异步回调而非渲染循环，当前无证据表明影响帧率；设备/视觉 BLOCKED，不能宣称性能 PASS |
| 资源体积 | HAP ≈ 4.4 MB；`modules.abc` ≈ 2.7 MB；`sourceMaps.map` ≈ 1.7 MB；resources ≈ 156 KB | 对 v1 可接受；source map 进入 HAP 是调试构建设置，release 打包时需评估是否剥离 |
| API 兼容 | `compatibleSdkVersion 5.0.2(14)`；`getSelfPermissionStatus` 有 API≥20 守卫；`Circle.fill` 已避免，改用 `Ellipse.fill` | 静态/构建级 PASS；API 14 设备运行时未验证（BLOCKED）；其余 `@since` API 未逐一审计 |
| 列表/渲染 | 20 处 `ForEach(...slice())`，全仓无 `LazyForEach`；设备/房间/成员列表当前规模小 | 不是已证实的缺陷；若设备数量增长，`slice()` 每次 build 复制数组与全量 `ForEach` 可能带来开销；建议在性能任务中评估 `LazyForEach`/缓存，不要用 mock 结果外推 |
| 测试源码 lint | `code-linter.json5` 忽略 `src/test/**`、`src/ohosTest/**`；测试代码只有 Node 解析/编译门禁 | 已知 gap（T-19 §8.2-5）；建议独立 lint 配置，不与产品 lint 混用 |
| 覆盖率 | 无行/分支覆盖率 | 已知 gap；本报告只以用例数/矩阵为证据，不宣称覆盖率 |
| 文档 | README 仍写“Hello World/业务未实现/host 测试未建立/Mock 未落地”，与 577dbc6 实际状态明显不符 | **T-21 必须完成**；在此之前 code-delivery README DoD 不满足，G-013 不得 PASS |
| 状态文件 | `state/checkpoint.md` 仍为 CP-009（M3），`state/project-state.md` 当前路径仍停在 T-05/T-19 前 | Stage Gate 前必须写新 Checkpoint/更新状态；本报告不作为状态更新 |

---

## 9. Findings

> 严重度定义：High = 可导致安全/数据/契约错误且无补偿；Medium = 架构/门禁治理缺口或需 Stage Gate 明确接受的风险；Low = 文档/工具/测试保真度问题；Info = 已记录残余/跟踪项。所有 finding 均给出可复现位置；本评审未修改被审代码。

| ID | 严重度 | 位置 / 证据 | 问题与影响 | 建议 / 责任 |
|---|---|---|---|---|
| **F-01** | **Medium** | `tools/contract/check_layering.py:550-578`；`tools/contract/layering_allowlist.json`（无端口条目）；T-19 test-report.md:102/215 | 端口位置例外由检查器硬编码放行，未进入版本化 allowlist/契约登记；`contracts/**` 不存在。影响：0 violation 不能证明端口位置合规；未来新增端口需手工修改检查器而非 allowlist，容易绕过 Change Impact；迁移责任在 C-17/T-20 之间悬空。 | 由 `solution-architect` 做受控接受登记（DES-A/B + allowlist 条目）或单独立项迁移；检查器改为读取 allowlist；Stage Gate 明确“PASS 不代表端口位置合规”。**不阻塞产品运行，但 G-014 前必须记录。** |
| **F-02** | **Low** | `tools/contract/layering_allowlist.json:6`、13 条 `pending-T-20`；T-19 test-report.md:101/212 | R3-01 的 13 条 D-12 例外仍为 pending；T-20 只读，无法代替架构 owner 正式化；`status` 字段也不被检查器强制。影响：契约登记未收口，后续维护者可能把“pending”误读为已批准。 | 由 `solution-architect` 按 DES-B §23.7 正式化（含 3 条值 import 的说明），或迁移到 `model/**`；完成后把 status 改为 accepted；不得保留 pending 进入 G-014。 |
| **F-03** | **Low** | `artifacts/60-testing/test-report.md:69/174/183`；`artifacts/60-testing/test-plan.md:618`；`entry/src/test/evidence/t19-ack-p95-mock.json` | 报告写 p50 0.526 / p95 0.601 / max 0.647；证据文件与 `.log` 为 p50 0.536 / p95 0.598 / max 0.684；本次复跑为 0.537/0.599/0.633。影响：T-19 报告不能从证据文件逐字复现；虽为 MOCK_ONLY、不影响 NFR 分类，但削弱测试报告可信度。 | `test-engineer` 修正 T-19 报告/计划数字或重新生成一致的证据；建议增加一个报告↔JSON 一致性检查。 |
| **F-04** | **Low** | `entry/src/main/ets/service/mock/MockGatewayService.ets:302-306`；`entry/src/test/host/GatewayMock.test.mjs:179/183` | C-20 Mock 仍产出退役 `CONTROL_RESPONSE_AUTH_FAILED`，并把 header correlation 映射为 `ACK_CORRELATION_MISMATCH`；测试断言固化了退役 code。生产 `LocalGatewayService` 路径正确，因此是测试替身/契约保真度问题。 | 小任务对齐 mock/test 为 `RESPONSE_AUTH_FAILED`/`RESPONSE_CORRELATION_MISMATCH`（同时保留 ACK body 的 `ACK_CORRELATION_MISMATCH`），或 Stage Gate 记录为 test-only 受控例外并设失效条件。 |
| **F-05** | **Low** | `entry/src/test/i18n/check_i18n.py:244-246`、`:497-504` | `--strict-ui` 参数从未被读取；短 UI 文案仍为 `warning`，注释“T-17/T-18 后提升为 blocking”已过期。影响：门禁自称 strict 但实际不阻断短硬编码 UI；82 条 warning 中的技术字符串噪声会掩盖真实回归。 | 实现真正的 strict 提升 + 技术字符串 allowlist/排除规则，或移除/重命名该参数并在测试计划中明确“短 UI 仅 advisory”；对 82 条 warning 做分类 triage。当前人工复核未发现真实硬编码 UI，故不阻断。 |
| **F-06** | **Low** | `tools/contract/test_check_layering.py:42-45`；`check_layering.py` D-03/D-05 | fixture 自测只断言 D-01/D-02/D-06/D-08/D-09/D-11/D-12/D-13/D-17，缺 D-03（contracts 违反）与 D-05（repository platform import）负例。影响：检查器两条规则回归时自测不会失败，门禁工具可信度下降。 | 增加 `bad` fixture（contracts 导入实现/平台；repository 导入 `@ohos.*`）并断言 D-03/D-05；与 F-01 一并处理。 |
| **F-07** | **Info** | `BleProvisioningViewModel.ets:625-639`；T-18 R4-01（t18-review-d.md） | `addGatewayToFamily` 已发起后的取消边界无 durable 回滚测试；VM 正确不发布 BOUND，但 durable 写可能完成。 | T-21 README/维护计划如实记录；可选补边界 host 用例；不阻断 CQG/Stage Gate。 |
| **F-08** | **Info** | `FamilyRepository.ets:284-307`；`state/project-state.md` D-030；T-19 test-report.md:213 | GAP-T18-01：`addGatewayToFamily` 无 actor/RBAC；D-030 仅 v1 风险接受，未关闭。 | Stage Gate 记录 D-030 限制/补偿控制；不得宣称服务层 RBAC 已闭合；后续 C-22/C-09/C-15 关闭或重评。 |
| **F-09** | **Info（Gate 阻塞项）** | `README.md:16-24/33/116/177`；`state/checkpoint.md`（CP-009） | README 仍描述“Hello World/业务未实现/host 测试未建立/Mock 未落地”，与 577dbc6 不符；Checkpoint 仍为 M3。 | T-21 更新 README + 维护计划；Orchestrator 在 G-014 前写 CP-011/更新 project-state；**T-21 完成前 G-013/ G-014 不得 PASS**。 |

**无 High/Critical finding。** F-01 是 Medium，但属于架构/门禁治理，不是运行时缺陷；若 Stage Gate 无法在 G-014 前记录受控接受，则应把 G-013/G-014 保持 `NOT READY`，而不是把 F-01 写成 PASS。

---

## 10. Stage Gate 建议（G-013 / G-014，implementation Stage）

> 本报告只给建议；Gate 判定权在 Orchestrator。`577dbc6` 是代码级评审通过候选，但 **T-21/T-22/IG-3 尚未完成**。

| # | §4.4 判定清单项 | 结论 | 依据 / 条件 |
|---|---|---|---|
| 1 | G-004 契约基线仍 VALID；无未处置 Change Impact；D-009..D-016 未覆盖 | **条件性满足** | G-004/ADR 仍 Accepted；T-12/T-18 裁定已登记；但 F-01（端口位置）、F-02（R3-01）、F-04（Mock 别名）需在 G-014 记录/关闭；D-030 为已接受上游缺口。 |
| 2 | 29 组件均有状态；进入集成的组件 STABLE；未完成项有范围/风险接受 | **代码级满足，Gate 记录待补** | CQG-T06..T18 全 PASS（C-24..C-27 在 CQG-T18；C-29 在 T-19）；CQG-T18 仍有条件（D-030/R3-01/设备）；CQG-T17 残余已在 T-18 处置/记录；**IG-3 仍 NOT READY**。 |
| 3 | T-01/T-03/T-04/T-05/T-19/T-20/T-21/T-22 均 VALID | **不满足** | T-19/T-20 就绪；**T-21 README/维护计划缺失**（README 目前严重过期）；**T-22 集成报告缺失**；T-20 本报告为条件式结论。 |
| 4 | 构建/静态/UT/CT/IT 通过；无 P0/P1；失败/未运行如实列出 | **部分满足** | build/lint/UT/CT PASS；**IT（T-22）未执行**；无 P0/P1；GAP-T18-01 为 Medium 已 D-030 接受；设备/真实环境 BLOCKED 如实列出。 |
| 5 | i18n CHK-01..09 通过；无硬编码 UI；parity 100% | **满足（工具债务 F-05）** | 0 blocking/0 missing；en/zh parity 100%（复数变体归一）；人工复核未发现真实硬编码 UI；`--strict-ui` no-op 需修复/记录。 |
| 6 | SC-01..SC-16 独立评审通过；无秘密/证书/HAP/构建目录入库；Mock 生产排除；P-TLS-PIN 未就绪时 P-HMAC 如实标注；SC-07 检查 | **满足（记录例外）** | 无生产秘密/签名/HAP/构建目录入库；仅 T-05 授权的 PUBLIC TEST DATA 证书；源级 + HAP 级 Mock 排除通过；P-HMAC 无机密性已如实标注；SEC-N26 常数时间通过；F-04 为 test-only 别名。 |
| 7 | v1 范围：door/light/sensor/ac 完整；其余只读降级；无 GCM 运行分支；云 Token 手工；无固件构建链 | **满足** | `CryptoService` GCM 仅被 `InviteService`（ADR-003 容器）使用；无 MQTT/ESP32 构建链；云 Token 手工；D-011 只读类型在 `DeviceConstants`/映射中；设备行为仍 BLOCKED，不能把 scope 满足写成设备 PASS。 |
| 8 | FR 追溯完整：26 FR/NFR 有 component→task→test 链接；FR-FAM-004 v1 限制已声明 | **部分满足** | 26 行/24 covered/2 partial/0 gap；FR-FAM-004 标注 v1 本地语义；UI/设备列 BLOCKED；T-21 README 必须把该限制告知用户。 |
| 9 | 实机/真实网络未完成项列为用户自行执行，不作为 Agent 阻塞 | **满足（如实）** | BLK-01..08 完整；CP-03/D-018 允许；但不得把 BLOCKED 写成 PASS，也不得据此宣称 IG-3/IG-4 PASS。 |
| 10 | Target Stage=implementation 已达到；写 Checkpoint；PAUSED_AT_STAGE；不自动进入 testing/release | **未达到** | T-21/T-22 未完成；CP-009 过期；IG-3 仍 NOT READY；当前只能 `PAUSED_AT_STAGE` 于“T-20 完成、待 T-21/T-22”的中间点。 |

### 10.1 总体建议

- **G-013（IG-4 全量）: NOT READY**。原因：T-21 README/维护计划、T-22 集成回归/Stage Gate 报告未完成；F-01/F-02/F-04/F-05/F-06 需关闭或受控接受；IG-3（G-012）仍无 PASS 记录。
- **G-014（Stage Gate）: NOT READY**。在 G-013 未 PASS 前不得判定；即使 Orchestrator 按 CP-03/D-018 接受设备 BLOCKED，也必须先完成 T-21/T-22、记录 D-030/R4-01/F-01/F-02/F-04，并写新 Checkpoint。
- **T-20 独立评审本身**: **PASS_WITH_ACCEPTED_RISKS（代码级，限于 577dbc6）**；无 High/Critical；Medium 为治理例外，须由 Stage Gate 记录；Low 项建议在 T-22 前处置。
- **不得声明**：IG-3/IG-4 PASS、设备/真实 BLE/LAN/TLS/云/视觉/fps PASS、NFR 4.3 达标、端口位置已合规、R3-01 已关闭、T-21/T-22 已完成。

### 10.2 残余风险接受建议

| 风险 | 建议 |
|---|---|
| **GAP-T18-01 / D-030** | 接受为 v1 上游限制：只在“UI ADMIN 门 + BLE PoP 前置 + 内部 API 边界”范围内接受；Stage Gate 明确“服务层 RBAC 未闭合”；后续 C-22/C-09/C-15 关闭或重评。 |
| **R4-01（Info）** | 在 T-21 README/维护计划如实记录“`addGatewayToFamily` 已发起后的 durable 边界不可回滚”；可选补 host 边界用例；不阻断 Stage Gate。 |
| **设备 BLOCKED 矩阵** | 按 CP-03/D-018 作为用户自行执行项接受；逐项列明 BLK-01..08，不把 mock/host 证据外推；IG-3/IG-4 不得据此宣称设备 PASS。 |
| **NFR 4.1/4.2/4.3 partial** | 接受 v1 边界：P-HMAC 无机密性、设备 Asset Store/RDB 未执行、真实 p95/fps UNAVAILABLE；T-21 README 必须如实告知。 |
| **F-15/F-17/F-21/R2-05 残余** | 作为 T-21 维护计划 backlog 记录（未消费组件、effective profile、邀请 usedCount/回执/转让过滤、C-23 VM permission 状态）；不是本次 T-20 的新阻断项。 |
| **C-20 mock alias、C-29 fixture、i18n strict 参数** | 作为 T-21/T-22 或独立小任务关闭；若 Gate 接受，必须写明 test/tool-only、失效条件与 owner。 |

---

## 11. 独立声明与限制

1. 本评审未参与 C-01..C-29 的实现或修复；未修改被审代码、测试、契约、资源或构建配置；唯一写入为本报告。
2. 本评审结论仅覆盖 `577dbc6` 与 §1 列出的 review scope；不覆盖 T-21/T-22、设备/真实网络/视觉/用户验收。
3. 本评审不授予 CQG、IG-3、IG-4、G-013、G-014 或用户验收；`PASS_WITH_ACCEPTED_RISKS` 是代码级意见，接受主体为 Orchestrator/Stage Gate。
4. 设备/模拟器/签名/真实网关缺失，故所有设备/真实环境项保持 `BLOCKED`/`UNAVAILABLE`；本报告未把 `COMPILED_ONLY` 写成 PASS。
5. 本报告引用的命令、数字、路径与 SHA-256 均为本次实际执行/核对结果；T-19 报告 F-03 的数字不一致已单列，不替原作者修改。

---

*REV-001-FINAL-SYSTEM 结束。*
