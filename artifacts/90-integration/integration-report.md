# INTEGRATION-REPORT-001 集成验证与 IG-4/G-013 报告（T-22）

- **Artifact ID**: INTEGRATION-REPORT-001
- **Producer**: agent:integration-engineer
- **Type**: Integration Verification Report / Regression Evidence / Stage Gate Input
- **Status**: COMPLETE（供 G-013/G-014 消费；**不授予** Gate）
- **Date**: 2026-10-18
- **Task**: `wp-087-integration`（T-22；task 分支 `task/wp-087-integration`，父分支 `feat/yaocore-app`）
- **Integration revision**: `d2896fbee100749b894ec0f965c448d15417eb86`（`feat/yaocore-app` 集成候选；任务工作树与父分支同 revision）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`
- **Upstream**: T-19 `TEST-REPORT-001` @ `4f7c26b`（报告 revision）；T-20 `REV-001-FINAL-SYSTEM` @ `577dbc6`；T-20 工具收口 @ `d69ad61`；T-21 README v1.0 / 维护计划 @ `fd35fd7`；G-004 契约基线 @ `697762c`；CQG-T06..T18
- **写范围**: `artifacts/90-integration/`；未修改产品代码、测试、工具、构建配置、`input/` 或状态文件
- **输入完整性**: handoff 的 10 项输入 SHA-256 全部与 `state/handoffs/wp-087-integration.json` 一致（t22 实算）

> **结论先行**：在集成候选 `d2896fb` 上实际执行并通过：host **697/697**、`hvigorw clean assembleHap` **BUILD SUCCESSFUL**（unsigned）、`codelinter` **0 error / 25 warning**、分层检查 **0 violation / 0 pending**（13 条 D-12 accepted；10/17 条端口位置例外被使用）、fixture **10/10**、`check_i18n --strict-ui` **0 blocking / 0 missing**、crosscheck **66/66**、仿真器契约 **20/20（HTTP+TLS）**、ohosTest HAP **仅编译**、HAP 内 Mock/ohosTest **0 命中**。与 T-19/T-20 证据对比**未发现产品回归**；所有数字差异均可由 T-20 工具收口、T-21 文档更新或 `MOCK_ONLY` 抖动解释。设备/真实 BLE/LAN/TLS/云/视觉/fps 仍为 **BLOCKED/UNAVAILABLE**，ACK p95 仍为 **MOCK_ONLY**，不得写成验收 PASS。
>
> **IG-4 范围：PASS（代码级）**。**G-013 建议：PASS_WITH_ACCEPTED_RISKS**。**G-014 建议：PASS_WITH_ACCEPTED_RISKS**，前提是 Orchestrator 在 Gate 记录中逐项接受本报告 §7 的残余风险并完成 §8.3 的 State/Checkpoint 动作；否则保持 `NOT READY`。

---

## 0. 分类与边界

| 分类 | 含义 |
|---|---|
| `PASS` | 在当前 revision、当前主机环境实际执行且断言通过 |
| `COMPILED_ONLY` | 只编译通过，未执行断言；**不是 PASS** |
| `BLOCKED` | 前置条件不满足（设备/签名/运行器） |
| `UNAVAILABLE` | 当前环境无法获得的证据 |
| `MOCK_ONLY` | 仅在 localhost/测试替身上测得，不得外推为产品验收 |
| `ACCEPTED_RISK` | 已登记并由 Stage Gate/Orchestrator 接受的风险 |

> 本报告不把 `COMPILED_ONLY`、`BLOCKED`、`UNAVAILABLE`、`MOCK_ONLY` 写成 PASS，也不把 `check_layering` 的 0 violation 解释为“端口位置已合规”。

---

## 1. 环境与 revision

| 项 | 实测值 |
|---|---|
| 仓库根 / cwd | `/home/quirkybrain/code/harmony-projects/YaoCore` |
| 分支 / HEAD | `task/wp-087-integration` / `d2896fbee100749b894ec0f965c448d15417eb86` |
| 父分支 / merge-base | `feat/yaocore-app` / `d2896fb`（与父分支同一 revision） |
| OS | Linux x86_64 |
| `ohpm` | 26.0.0.630 |
| `hvigorw` | 6.26.8 |
| `codelinter` | 6.0.240 |
| Node | v24.15.0 |
| Java | OpenJDK 21.0.12.1 |
| Python | 3.12.3（标准库） |
| SDK | HarmonyOS 26.0.0.105；`DEVECO_SDK_HOME=/home/quirkybrain/harmonyos/command-line-tools/sdk` |
| 设备 | `hdc list targets` 空；无模拟器实例；`signingConfigs: []`（unsigned HAP） |
| 代理 | 环境存在本机代理；仿真器套件以 `no_proxy=127.0.0.1,localhost` 运行（与 T-19 一致） |
| 工作树 | 验证期间除 `artifacts/90-integration/` 外无变更；构建产物均在 ignored `entry/build/` |

### 1.1 集成候选的构成

| 基线 | Commit | 内容 |
|---|---|---|
| T-19 证据基线 | `4f7c26b` | 696 host 用例、测试报告与证据 |
| T-20 独立评审 | `577dbc6` | 全系统评审 + 1 条 R3-01 并发用例（697） |
| T-20 契约例外正式化 | `fec06e5` → `0d6e806` | DES-A §27.6 / DES-B §18.1 的端口与 D-12 登记 |
| T-20 工具收口 | `d69ad61` → `59a2506` | checker 读取版本化 allowlist、fixture 10 条、i18n strict 生效、Mock 别名对齐 |
| T-21 文档收尾 | `fd35fd7` → `942b751` | README v1.0、维护计划、风险/设备矩阵 |
| 集成候选 | `d2896fb` | 合并证据；代码与 `13dc839` 一致 |

`4f7c26b..d2896fb` 的产品代码差异只有 `entry/src/main/ets/service/mock/MockGatewayService.ets`（T-20 F-04，测试替身；**生产 HAP 排除**）；其余为测试、工具、证据与文档。该事实用于判断 T-19/T-20 证据在 `d2896fb` 的适用性。

---

## 2. 执行命令与结果矩阵（cwd = 仓库根）

| # | 命令 | 实际结果 | 分类 | 证据 |
|---|---|---|---|---|
| 1 | `entry/src/test/run-host-tests.sh` | `1..697`；tests 697 / pass 697 / fail 0 / skipped 0；exit 0；≈3.0 s | **PASS** | `evidence/t22-host-node-tests.tap` |
| 2 | `hvigorw clean assembleHap --no-daemon` | `BUILD SUCCESSFUL in 14 s 618 ms`；35 tasks；unsigned HAP | **PASS** | `evidence/t22-clean-assemble.log` |
| 3 | `codelinter -c code-linter.json5 -p default .` | `Defects: 25; Errors: 0; Warns: 25; Suggestions: 0`；exit 0 | **PASS（0 error）** | `evidence/t22-codelinter.log` |
| 4 | `python3 tools/contract/check_layering.py --root . --report ...` | `files=209 violations=0 exceptions_used=13 pending=0 pending_used=0 port_exceptions_used=10 port_pending=0 port_pending_used=0`；exit 0 | **PASS（含已登记例外）** | `evidence/t22-layering.log`、`t22-layering.json` |
| 5 | `python3 tools/contract/test_check_layering.py` | `Ran 10 tests ... OK`；exit 0 | **PASS 10/10** | `evidence/t22-layering-fixture-tests.log` |
| 6 | `python3 entry/src/test/i18n/check_i18n.py --root . --report ... --allowlist entry/src/test/i18n/allowlist.json --strict-ui` | `blockingFailures=0 warnings=55 missingKeys=0 hardcoded=16`；CHK-01..09 全 PASS；exit 0 | **PASS** | `evidence/t22-i18n-checker.log`、`t22-i18n-report.json` |
| 7 | `python3 tools/contract/crosscheck_protocol_assets.py` | **66 PASS / 0 FAIL**；14 项冻结输入 `FINDING`；`hard checks: ALL PASS`；exit 0 | **PASS 66/66** | `evidence/t22-crosscheck.log` |
| 8 | `no_proxy=127.0.0.1,localhost NO_PROXY=127.0.0.1,localhost python3 -m unittest tools.simulator.test_gateway_contract -v` | `Ran 20 tests ... OK`；含 HTTP 与 3 条 TLS 用例；exit 0 | **PASS 20/20（MOCK_ONLY）** | `evidence/t22-simulator-contract.log` |
| 9 | `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | `BUILD SUCCESSFUL in 13 s 264 ms`；35 tasks；未运行断言 | **COMPILED_ONLY** | `evidence/t22-ohosTest-assemble.log` |
| 10 | HAP 内容检查（`unzip` + `grep`） | 14 个条目；`modules.abc` 2,826,316 B、`sourceMaps.map` 1,698,148 B；`MockGatewayService`/`MockBleProvisioningClient`/`ohosTest`/`service/mock` **0 命中** | **PASS（Mock 生产排除）** | 本报告 §5.4；HAP `entry-default-unsigned.hap` ≈4.4 MB |
| 11 | `python3 tools/contract/measure_ack_latency.py --samples 100 --warmup 5 --json ...` | p50 **0.542 ms** / p95 **0.612 ms** / max 0.692 ms；0 failures；`resultClass=MOCK_ONLY` | **MOCK_ONLY（非验收）** | `evidence/t22-ack-p95-mock.json`、`.log` |
| 12 | 设备/真实环境验证 | 无 `hdc` target、无模拟器、无签名、无真实网关/云/硬件 | **BLOCKED / UNAVAILABLE** | 本报告 §7、维护计划 §4 |

### 2.1 Host 用例与分层检查说明

- 697 条 host 用例通过 Node 24 runner 加载**生产 `.ets` 源码**（`register-ets.mjs`/`ets-hooks.mjs`），注入 fake transport/clock/store；覆盖基础/协议、Crypto/Security、存储/路由、领域、i18n、云/AC、BLE、VM/UI 壳与性能 harness。它不是设备/Hypium 运行，也不替代 ArkUI 渲染证据。
- 分层检查器覆盖 D-01/02/03/05/06/08/09/11/12/13/17；D-04/D-10、D-07/D-14、D-15、D-16 由其他检查器/评审负责（工具 JSON 中 `rules_delegated` 已声明）。`t22-layering.json` 的 `producer/task` 字段是 checker 的静态元数据（T-20），命令、报告路径与计数为本任务实测。
- i18n 的 `55 warnings` 与 `16 hardcoded` 是**带 allowlist** 的结果，与 T-20 表格一致；README 中的 `73 warnings` 是**不带 allowlist** 的同一 checker 计数。两者 `blockingFailures=0`、`missingKeys=0` 一致。

---

## 3. 与 T-19 / T-20 的无回归对比

| 项 | T-19 @ `4f7c26b` | T-20 @ `d69ad61` / 评审 @ `577dbc6` | T-22 @ `d2896fb` | 结论 |
|---|---|---|---|---|
| Host | 696/696 | 697/697（T-20 工具收口）；评审时为 696（早于收口） | **697/697** | 与 T-20 收口一致；T-19→T-20 的 +1 是 F-05 strict-ui 测试，未删除/弱化既有断言 |
| 构建 | BUILD SUCCESSFUL | BUILD SUCCESSFUL | **BUILD SUCCESSFUL** | 一致（耗时随缓存变化） |
| `codelinter` | 0 error / 25 warning | 0 error / 25 warning | **0 error / 25 warning** | 一致；warning 为非阻断性能建议 |
| 分层 | 0 violation；13 pending | 0 violation；**pending 0**（accepted） | **0 violation；pending 0** | 与 T-20 一致；13 条例外已正式化 |
| fixture | 4/4 | 10/10 | **10/10** | 与 T-20 一致（D-03/D-05/端口 fixture 已补齐） |
| i18n | 0 blocking；121 warn/82 hardcoded（旧 checker） | 0 blocking；55 warn/16 hardcoded（allowlist） | **0 blocking；55 warn/16 hardcoded** | 与 T-20 一致；T-19 差异由 checker 语义修复解释 |
| crosscheck | 66/66 | 66/66 | **66/66** | 一致 |
| 仿真器契约 | 20/20（HTTP+TLS） | 20/20（HTTP+TLS） | **20/20（HTTP+TLS）** | 一致 |
| ohosTest HAP | COMPILED_ONLY | 未单列 | **COMPILED_ONLY** | 仅编译，不是 PASS |
| ACK p95 | 0.598 ms（MOCK_ONLY） | 0.598 ms（MOCK_ONLY） | **0.612 ms（MOCK_ONLY）** | localhost 抖动；无功能含义；均不得作为 NFR 4.3 验收 |
| HAP Mock 排除 | 源级守卫 | 源级 + HAP 检查（评审） | **HAP 级 0 命中** | 证据增强，无回归 |

**无回归结论**：所有必须一致项（构建、lint、host 通过率、crosscheck、仿真器、i18n blocking、layering 门禁）在 `d2896fb` 与最新证据（T-20 收口）一致；与 T-19 的差异均可由后续已登记任务解释。**未发现产品行为、契约或安全路径回归。**

---

## 4. 集成与跨组件契约验证

### 4.1 契约基线与裁定一致性

| 检查 | 结果 | 证据 |
|---|---|---|
| G-004 契约基线仍 VALID | **PASS** | `state/gates/G-004-contract-baseline.md`；ADR-001..004 Accepted；`contract-baseline.md` @ `697762c` |
| DES-A/DES-B 冻结签名未被 T-22 改变 | **PASS** | T-12/T-18/T-20 裁定同步只登记语义/例外，不改变冻结签名（文件头 Revision 记录） |
| 端口物理位置例外已版本化 | **PASS（登记）** | DES-A §27.6；`layering_allowlist.json` 17 条 `port_location_exceptions`；checker `port_exceptions_used=10`、`port_pending=0` |
| D-12 UI 白名单已正式化 | **PASS（登记）** | DES-B §2.3/§18.1 `T20-D12-01..13`，13 条全部 `accepted` 且命中 |
| 无未处置 Change Impact | **PASS（记录）** | G-004 未变；F-01/F-02/F-04/F-05/F-06 已在 T-20 工具/契约侧关闭；D-030/R4-01 为已登记风险，不是 Change Impact |

### 4.2 错误语义双轨

- **生产路径**：`ResponseVerifier` 对 header 的 alg/key_id/correlation/sign 失败统一为 `RESPONSE_AUTH_FAILED`，header correlation 不匹配为 `RESPONSE_CORRELATION_MISMATCH`；ACK body 的 `request_id`/`seq` 不匹配由 C-03 映射为 `ACK_CORRELATION_MISMATCH`（contract-baseline §4.5、DES-A §3.2.3）。
- **Mock 对齐**：`CONTROL_RESPONSE_AUTH_FAILED` 在 `entry/src/main/ets` 与 `entry/src/test` 中 **0 命中**；`MockGatewayService` 已删除 try/catch 别名转换，header 验签失败原样传播 `RESPONSE_AUTH_FAILED`。
- **双轨判定**：`result_code == 0` 仍必须同时满足响应验签、correlation、`reported_state`；`success`/HTTP 2xx 不作为成功依据。host SEC-N01..N14 与仿真器 20/20 覆盖坏签名、时间窗、nonce、重放、未知 code、缺 `reported_state` 等负例。
- **结论**：**PASS（代码级）**；生产与测试替身错误码语义一致，无退役别名残留。

### 4.3 DI、分层与 RBAC

| 检查 | 结果 | 证据 |
|---|---|---|
| 分层规则 D-01/02/03/05/06/08/09/11/12/13/17 | **PASS：209 文件 / 0 violation** | `t22-layering.log` |
| `@Provide` / `@Consume` | **PASS：0 生产命中**（仅注释说明） | `grep`；T-20 §6.1 |
| 页面/组件直接构造 service/repository/VM | **PASS：0 命中**（`new` 均为本地 DTO/值对象；唯一 `NavigationService` 构造在 `Index` 的 D-12 seam） | 分层检查；T-20 §6.1 |
| 生产组合根唯一装配 | **PASS** | `AppCompositionRoot`；`EntryAbility` 仅创建 root；host `AppShell` 用例 |
| 显式 props / VM 工厂注入 | **PASS** | 页面/组件使用 `@Require` props 与 `PageVmFactoryPort` |
| 服务层 RBAC（家庭/房间/场景） | **PASS（已覆盖动作）** | host RBAC 矩阵；`RoomService`/`FamilyService` 管理动作 `requireAdmin`；`SceneService` GUEST fail-closed |
| `addGatewayToFamily` actor/RBAC | **已知缺口（D-030 / GAP-T18-01）** | `FamilyRepository.addGatewayToFamily` 无 actor；v1 接受，补偿控制 UI ADMIN 门 + BLE PoP + 内部 API 边界；**未关闭** |

> `check_layering` 的 0 violation **不代表**端口位置合规：17 条例外中 10 条当前被使用，P1-P4 迁移未开始；13 条 D-12 例外已 `accepted`，但 UI 类型迁移仍未执行。两者必须由 G-014 记录。

### 4.4 i18n、Mock 排除与权限最小集

| 检查 | 结果 | 证据 |
|---|---|---|
| CHK-01..09 | **全 PASS**；0 blocking / 0 missing | `t22-i18n-checker.log` |
| key parity | **100%**（rawfile 复数变体归一后；base/en_US 键集一致） | T-20 §6.4；checker |
| 硬编码 UI 文案 | **0 blocking**；16 条 hardcoded 均为非 UI 技术字符串（主题颜色注释、AC 品牌 CJK 名称、Mock 错误消息） | `t22-i18n-checker.log`；T-20 §3 |
| 历史文案 | **615 行：596 条 `PENDING_REVIEW`、10 条 ACCEPTED、6 条 DEPRECATED (heuristic)、3 条 EXCLUDED (brand data)**；重译审查 11 条 `B_REWRITE_REQUIRED`、2 条 `SAFETY_RECHECK_REQUIRED` | `legacy-migration.csv` 实算 |
| Mock 生产排除（源级） | **PASS** | `T11_noProductionFileImportsC20MockOrOhosTest`、`T17_productionMockExclusionCoversAllMainSources` |
| Mock 生产排除（HAP 级） | **PASS：0 命中** | `modules.abc` 与 `sourceMaps.map` 对 `MockGatewayService`/`MockBleProvisioningClient`/`ohosTest`/`service/mock` 全部 0 命中；HAP 14 条目 |
| DEV-ONLY 拒收 | **PASS** | `LocalGatewayService.rejectDevOnly` 在验签/JSON 解析前执行；仿真器固定发送 `X-YaoCore-Simulator: DEV-ONLY` |
| 权限声明 | **最小集：`INTERNET`（system_grant）+ `ACCESS_BLUETOOTH`（user_grant）** | `entry/src/main/module.json5`；`PermissionPolicy`/`PermissionGate`；CAMERA/LOCATION 明确不启用 |
| 运行时权限 | **代码级 PASS；设备授予 BLOCKED** | `PermissionGate.requestPermissionsFromUser`；真实权限对话框未在设备验证 |

### 4.5 v1 范围与 FR 追溯

| 检查 | 结果 | 证据 |
|---|---|---|
| door/light/sensor/ac 完整控制 | **PASS（代码级）** | `DeviceConstants.SUPPORTED_TYPES`；`GatewayRequestPolicy`/`DeviceCommandRunner` 的 `isSupported` 前置校验 |
| 其余设备只读降级 | **PASS（代码级）** | `READ_ONLY_TYPES`（switch/camera/curtain/fan/speaker）；`UiMapping`/`DeviceCards` 控制门；`DiscoverMapper` 归一 |
| 无 LAN GCM 运行分支 | **PASS** | GCM 仅用于 ADR-003 邀请容器（`InviteCodec`/`OhosCryptoProvider`）；网关/云无 GCM 路径；无 MQTT |
| 云 Token 手工管理 | **PASS** | `CloudService` 头注释与代码：manual token、无 refresh；过期/无效只提示用户更新 |
| 无固件构建链 | **PASS** | 仓库仅 HarmonyOS App；无 ESP32/MQTT/固件构建目录或脚本 |
| 26 项 FR 映射 | **PASS：26 行；24 covered（host/source）/ 2 partial / 0 gap** | `test-report.md` §5 实算 26 行；FR-HOME-003（真实传感器 UNAVAILABLE）、FR-SET-002（P-HMAC 无机密性/真实 TLS BLOCKED）如实 partial |
| FR-FAM-004 v1 限制 | **PASS（已声明）** | 家庭退出/转让为 v1 本地语义；README 与测试报告均声明 |
| NFR 4.1/4.2/4.3 | **partial（如实）** | HMAC/防重放/存储/55ms 有 host 证据；真实 TLS、设备存储、真实 p95/fps 缺失 |

---

## 5. IG-4 / G-013 检查清单（交付计划 §4.2）

| # | 必检项 | 结果 | 证据/说明 |
|---|---|---|---|
| 1 | 全量构建 | **PASS** | `t22-clean-assemble.log` |
| 2 | 全量测试（UT/CT/仿真器/回归） | **PASS** | host 697/697；crosscheck 66/66；仿真器 20/20；fixture 10/10 |
| 3 | 独立评审 | **PASS_WITH_ACCEPTED_RISKS** | T-20 评审（`577dbc6`）；F-01/F-02/F-04/F-05/F-06 已由 `d69ad61` 关闭；F-07/F-08 Info 仍登记；无 High/Critical |
| 4 | README / 限制说明 | **PASS** | README v1.0 @ `fd35fd7`（基于 `13dc839`）；限制/设备矩阵/风险与 T-19/T-20 一致；T-22 复跑数字与 README 状态表一致或可解释 |
| 5 | 回归 | **PASS** | §3 无回归；所有数字差异有解释 |
| 6 | 文档/证据一致性 | **PASS（1 条说明）** | ACK p95 由 0.598→0.612 属 MOCK_ONLY 抖动；i18n 73（无 allowlist）vs 55（有 allowlist）已解释 |
| 7 | IG-1/IG-2/IG-3 历史 Gate 记录 | **记录缺失（治理项）** | 交付计划 §4.2 的 G-010/G-011/G-012 无独立 Gate 文件；其代码级范围由 CQG + T-19 全量 + T-20 系统评审 + 本 T-22 复跑覆盖；设备部分仍 BLOCKED。**G-014 必须显式记录该事实，或补写 Gate 后再判定** |

**IG-4 判定建议：PASS（代码级集成范围）**。所有可执行的集成/契约/回归检查在 `d2896fb` 通过；未执行项均为设备/真实环境，已如实分类。

**G-013 判定建议：PASS_WITH_ACCEPTED_RISKS**。理由：集成证据充分；残余项是已登记的 v1 风险与用户侧设备验证，不是本次集成失败。

---

## 6. 组件状态汇总（C-01..C-29，代码级）

> 组件状态来自各 CQG；`STABLE` 均为**代码级**，设备/视觉证据保持 `BLOCKED`。C-20 在 T-20 的 Mock 别名修复属于测试替身对齐，host 697 与 HAP 排除已复验；C-29 无独立 CQG，按交付计划由 T-19/T-20/T-21/T-22 工具证据承载。

| 组件 | 名称/范围 | 状态 | CQG / 证据 revision | 备注 |
|---|---|---|---|---|
| C-01 | 公共类型/常量/工具 | **STABLE（代码级）** | CQG-T06 @ `4d97e41` | — |
| C-02 | 领域模型/枚举 | **STABLE（代码级）** | CQG-T06 @ `4d97e41` | — |
| C-03 | 协议 DTO/映射 | **STABLE（代码级）** | CQG-T06 @ `4d97e41` | — |
| C-04 | CryptoService | **STABLE（代码级）** | CQG-T07 @ `11a291c` | 设备向量 BLOCKED |
| C-05 | SecurityService | **STABLE（代码级）** | CQG-T07 @ `11a291c` | — |
| C-06 | 存储服务 | **STABLE（代码级）** | CQG-T08 @ `1f1fb4d` | 设备 Asset Store/RDB 未执行 |
| C-07 | GatewayRepository | **STABLE（代码级）** | CQG-T08 @ `1f1fb4d` | — |
| C-08 | FamilyRepository | **STABLE（代码级）** | CQG-T09 @ `9473ae0` | GAP-T18-01/D-030 关联 |
| C-09 | RoomRepository | **STABLE（代码级）** | CQG-T09 @ `9473ae0` | — |
| C-10 | DeviceRepository | **STABLE（代码级）** | CQG-T09 @ `9473ae0` | — |
| C-11 | SceneService | **STABLE（代码级）** | CQG-T09 @ `9473ae0` | — |
| C-12 | AuthService | **STABLE（代码级）** | CQG-T13 @ `69d5374` | — |
| C-13 | InviteService | **STABLE（代码级）** | CQG-T13 @ `69d5374` | 设备邀请流程未验证 |
| C-14 | I18nService/资源包 | **STABLE（代码级）** | CQG-T10 @ `1bf3183` | 596 条历史文案待 triage |
| C-15 | CloudService | **STABLE（代码级）** | CQG-T14 @ `db33485` | 真实 IoTDA UNAVAILABLE |
| C-16 | AC 品牌适配器 | **STABLE（代码级）** | CQG-T14 @ `db33485` | 真实 AC BLOCKED |
| C-17 | LocalGatewayService | **STABLE（代码级）** | CQG-T11 @ `514671d` | 真实 LAN/TLS BLOCKED |
| C-18 | GatewayDiscoveryService | **STABLE（代码级）** | CQG-T11 @ `514671d` | PB-01/UDP 未决 |
| C-19 | BleProvisioningService | **STABLE（代码级）** | CQG-T12 @ `74255fc` | 真实 BLE BLOCKED |
| C-20 | MockGateway/MockBle | **STABLE（代码级）** | CQG-T11 @ `514671d` + T-20 F-04 @ `d69ad61` | 测试替身；生产 HAP 0 命中 |
| C-21 | Home/Device/Climate/Door VM | **STABLE（代码级）** | CQG-T15/16 @ `3dd0639` | 视觉/fps BLOCKED |
| C-22 | Family/Room/Scene VM | **STABLE（代码级）** | CQG-T15/16 @ `3dd0639` | — |
| C-23 | BleProvisioning/Settings VM | **STABLE（代码级）** | CQG-T15/16 @ `3dd0639` | — |
| C-24 | 设计系统/复用 UI | **STABLE（代码级）** | CQG-T18 @ `967e266` | 视觉/A11y BLOCKED |
| C-25 | Home/Rooms/DeviceControl 页面 | **STABLE（代码级）** | CQG-T18 @ `967e266` | 视觉 BLOCKED |
| C-26 | Family/Room/Scene 页面 | **STABLE（代码级）** | CQG-T18 @ `967e266` | 视觉 BLOCKED |
| C-27 | Provisioning/Settings/About/Profile 页面 | **STABLE（代码级）** | CQG-T18 @ `967e266` | 视觉/设备 BLOCKED |
| C-28 | 应用壳/EntryAbility/权限/组合根 | **STABLE（代码级）** | CQG-T17 @ `6b10975` | 启动设备 smoke BLOCKED |
| C-29 | 构建/仿真/README 工具 | **STABLE（代码级，工具证据）** | T-19 @ `4f7c26b`；T-20 @ `d69ad61`；T-21 @ `fd35fd7`；T-22 @ `d2896fb` | **无独立 CQG**（计划归 T-19）；T-22 复跑全部工具 |

**统计**：29/29 有状态；28 个有 CQG（C-01..C-28），C-29 由 T-19/T-20/T-21/T-22 工具证据承载。所有进入集成的组件为 **STABLE（代码级）**；未完成/未验证项均有明确范围与风险记录（设备、视觉、真实网络、端口/D-12 迁移、i18n 历史文案）。

---

## 7. 残余风险清单与接受建议

| ID | 风险 | 级别/分类 | 现状与证据 | 建议 |
|---|---|---|---|---|
| **D-030 / GAP-T18-01** | `FamilyRepository.addGatewayToFamily` 无 actor/RBAC | Medium / 已接受 | 服务层授权缺口**未关闭**；UI ADMIN 门 + BLE PoP 前置 + 内部 API 边界；CQG-T18 §1、T-20 §6.2/F-08、维护计划 §5.1 | G-014 明确“服务层 RBAC 未闭合”；后续 C-22/C-09/C-15 变更时复审 |
| **R4-01** | `addGatewayToFamily` 已发起后的取消不可 durable 回滚 | Info / 已接受 | VM 只抑制 `BOUND`；durable 写可能完成；README/维护计划已声明；无 durable 回滚测试 | 接受为 v1 边界；后续配网 VM 变更时补边界用例 |
| **端口位置迁移** | 17 条端口例外（10 条当前使用），`contracts/**` 未建立 | Medium / 治理 | DES-A §27.6；`port_exceptions_used=10`、`port_pending=0`；P1-P4 未开始 | 记录“0 violation ≠ 端口位置合规”；下一维护窗口执行 P1-P3，完成后删除例外并重跑全量 |
| **R3-01 / D-12** | 13 条 pages DTO/枚举 import | Low / 已登记 | 已 `accepted`（10 type-only + 3 值 import）；迁移未完成；检查器命中 13 | 记录为已登记例外；P2 迁移后改为 `model/**` 并删除条目 |
| **i18n 596** | 615 条 legacy 映射中 596 条 `PENDING_REVIEW` | Low / 已登记 | 当前 UI 0 blocking；16 条 hardcoded 均为非 UI 技术字符串；CSV 实算 | 维护轮次逐条 triage；不得把 596 写成已签署 |
| **设备/真实环境 BLOCKED** | BLE/LAN/TLS/云/视觉/A11y/fps/硬件 | Medium / 用户侧 | `hdc` 空、无模拟器、无签名；BLK-01..08；维护计划 §4 矩阵 | 按 §8.4 由用户执行；结果回填；不得用 host/mock 外推 |
| **ACK p95 MOCK_ONLY** | localhost p95 0.612 ms | Info / 非验收 | 本次 N=100/warmup=5；T-19/T-20 0.598、T-21 0.589；`resultClass=MOCK_ONLY` | 不用于 NFR 4.3；真实 LAN p95 由 BLK-07 执行 |
| **NFR 4.1/4.2/4.3 partial** | 传输机密性、设备存储、真实性能 | Medium / 已登记 | P-HMAC 无机密性；真实 TLS/Asset Store/p95/fps 缺失 | G-014 记录 partial；README 已如实告知 |
| **测试源码 lint / 覆盖率** | `src/test/**`、`src/ohosTest/**` 未 lint；无覆盖率 | Low / 已登记 | `code-linter.json5` 忽略；测试仅 Node 解析/编译门禁 | 维护计划 M-08；不阻断 v1 |
| **IG-1/2/3 Gate 记录缺失** | G-010/G-011/G-012 无独立 Gate 文件 | Medium / 治理 | §5 #7；CQG + T-19 + T-20 + T-22 覆盖代码级范围；设备部分 BLOCKED | G-014 记录“以 IG-4 全量证据替代历史 IG 记录”或补写后再判定 |
| **State/Checkpoint 过期** | `state/checkpoint.md` 仍为 CP-009（M3）；`project-state.md` 未更新到 T-22 | Medium / 流程 | T-20 §8/§F-09；T-22 写范围不允许改 state | Orchestrator 在 G-014 前写新 Checkpoint、更新 project-state |
| **C-29 无独立 CQG** | 工具/文档组件 | Low / 治理 | T-19/T-20/T-21/T-22 证据；本报告 §2 全量复跑 | G-014 明确 C-29 的状态依据；如需可补一个工具 CQG |
| **UI 视觉/A11y 未验收** | 仅源码级 + host VM | Medium / 用户侧 | 无设备/模拟器；T-20 §8；维护计划 §4.2 | 用户按 §8.4 抽查；不宣称视觉 PASS |
| **许可证 TODO** | 项目级许可证未声明 | Low / 项目所有者 | README 明确 TODO | 首次公开发布前处理；不假设可再分发 |

---

## 8. G-014 Stage Gate 建议

### 8.1 逐项判定（交付计划 §4.4）

| # | 判定清单项 | 结果 | 依据/条件 |
|---|---|---|---|
| 1 | G-004 契约基线仍 VALID；无未处置 Change Impact；D-009..D-016 未被覆盖 | **PASS** | G-004 PASS；ADR-001..004 Accepted；T-12/T-18/T-20 裁定只登记语义/例外；D-030 已书面接受 |
| 2 | 29 组件均有状态；进入集成的组件 STABLE；未完成项有范围/风险接受 | **PASS（代码级）** | §6；设备/视觉/迁移项明确排除并登记；C-29 无独立 CQG 已记录 |
| 3 | T-01/T-03/T-04/T-05/T-19/T-20/T-21/T-22 均 VALID | **条件性 PASS** | 各工件证据完整；T-22 本报告待 Orchestrator 的 Artifact Validation；T-01/T-03/T-04/T-05 已有 G-009/G-006/G-007/G-008 |
| 4 | 构建/静态/UT/CT/IT 通过；无 P0/P1；失败/未运行如实列出 | **PASS（代码级）** | §2；无产品失败；设备/真实环境 BLOCKED/UNAVAILABLE 如实列出；IT 仅限 host/仿真器，真实 IT BLOCKED |
| 5 | i18n CHK-01..09 通过；无硬编码 UI；parity 100% | **PASS** | 0 blocking/0 missing；16 条非 UI 告警；596 条历史文案为已登记残余；parity 100% |
| 6 | SC-01..SC-16 独立评审通过；无秘密/证书/HAP/构建入库；Mock 排除；P-TLS-PIN 如实标注；SC-07 检查 | **PASS（记录例外）** | T-20 §5；本报告 §4.4；仅 T-05 授权 PUBLIC TEST DATA 证书；HAP/build ignored；源级 + HAP 级 Mock 0 命中；P-HMAC 无机密性已声明 |
| 7 | v1 范围：door/light/sensor/ac 完整；其余只读；无 GCM 运行分支；云 Token 手工；无固件构建链 | **PASS（代码级）** | §4.5；设备行为仍 BLOCKED |
| 8 | FR 追溯：26 项有 component→task→test；FR-FAM-004 v1 限制已声明 | **PASS（含 2 partial）** | §4.5；24 covered / 2 partial / 0 gap |
| 9 | 实机/真实网络未完成项列为用户自行执行，不作为 Agent 阻塞 | **PASS** | §8.4；CP-03/D-018；未把 BLOCKED 写成 PASS |
| 10 | Target Stage=implementation 已达到；写 Checkpoint；`PAUSED_AT_STAGE`；不自动进入 testing/release | **待 Orchestrator** | §8.3；T-22 写范围不含 `state/`；当前 CP-009 过期 |

### 8.2 Gate 建议

- **G-013（IG-4 全量）：PASS_WITH_ACCEPTED_RISKS**。集成构建/测试/契约/回归在 `d2896fb` 通过；无产品回归；残余为已登记风险与设备侧验证。
- **G-014（Stage Gate, implementation）：PASS_WITH_ACCEPTED_RISKS（条件式）**。建议理由：
  1. 代码级交付与 29 组件状态完整，集成证据可复现；
  2. 无 P0/P1；所有 BLOCKED/UNAVAILABLE/MOCK_ONLY 已如实分类；
  3. 残余风险有 owner、补偿控制与复审触发条件；
  4. 设备/真实网络按 CP-03/D-018 由用户执行，不作为 Agent 阻塞；
  5. README/维护计划已如实告知限制。
- **前置条件（未满足则不得判 PASS）**：
  1. Orchestrator 对 T-22 本报告与上游工件执行 Artifact Validation；
  2. 在 G-014 记录 D-030/GAP-T18-01、R4-01、端口/D-12 迁移、i18n 596、设备 BLOCKED、NFR partial、ACK p95 MOCK_ONLY、测试 lint/覆盖率；
  3. 明确记录 IG-1/IG-2/IG-3 无独立 Gate 文件，且以 IG-4 全量证据作为代码级覆盖；若要求正式 IG 记录，则先补 Gate；
  4. 写新 Checkpoint 并更新 `state/project-state.md`，标记 `PAUSED_AT_STAGE`，不自动进入 testing/release；
  5. 不把本报告或 T-20 评审等同于用户验收/设备验收。

### 8.3 Orchestrator 收尾动作（T-22 写范围外）

```text
1. Artifact Validation: T-22 integration-report.md + T-19/T-20/T-21 状态
2. 写 state/gates/G-013（IG-4）与 G-014（Stage Gate）
3. 更新 state/checkpoint.md（CP-011 或下一编号）与 state/project-state.md
4. 记录 §7 风险接受与设备矩阵（引用 maintenance-plan §4/§5）
5. 标记 PAUSED_AT_STAGE；不启动 testing/release
```

### 8.4 用户侧设备矩阵指引

按 `artifacts/80-maintenance/maintenance-plan.md` §4.1/§4.2 执行，至少覆盖：

- **BLK-01/02**：受支持运行器或签名 HAP + `hdc` target + 模拟器/真机；运行 `onDeviceTest`；4 Tab/NavDestination 返回。
- **BLK-03**：真实 ESP32-S3 BLE 配网（Security1、身份 v2.0/v2.1、Wi-Fi 扫描/下发、取消清理、PoP 错误）。
- **BLK-04**：真实 LAN discover/control/ACK；验签、correlation、`reported_state`；pin mismatch/握手失败必须 P-BLOCKED 且无明文回退。
- **BLK-05**：真实华为云 IoTDA（endpoint/projectId/deviceId/IAM Token；签名命令/影子/完成判定/Token 过期；不期望自动刷新）。
- **BLK-06**：视觉/无障碍/动效（4 Tab、暗黑、428×872、长英文、75% 文本膨胀、对比度、读屏、动效降级）。
- **BLK-07**：真实 LAN ACK p95 ≤500ms、55ms 节流、60/120fps；记录设备型号/网络/样本数。
- **BLK-08**：门锁/门磁/AC/SHT30/PIR 实物状态与来源。
- **§4.2 抽查**：非 ADMIN 网关入口、配网取消、门磁引导、权限 CTA、按钮禁用可见性、长英文/文本膨胀。

记录设备型号、OS/API、固件版本、网络、App revision、签名方式；日志必须脱敏；失败保留首跑证据；结果回填测试报告/维护计划，不反向修改代码级 Gate 结论。

---

## 9. 限制与声明

1. 本报告只覆盖 `d2896fb` 与 §1 环境；不覆盖设备、真实网络、视觉/A11y、真实性能或用户验收。
2. host 测试在 Node 24 下加载生产 `.ets` 源码并注入 fake；不是 ArkTS/Hypium 设备运行，也不证明 ArkUI 渲染。
3. 仿真器 20/20 只证明 localhost 契约夹具与 TLS 夹具；不证明真实网关固件、证书链或 LAN 时延。
4. ACK p95 为 `MOCK_ONLY`，不得作为 NFR 4.3 验收；55ms 节流为 fake clock/host 逻辑证据。
5. `check_layering` 0 violation 是“在已登记例外下通过”，不是端口位置合规；D-12 13 条为 `accepted` 例外，不是迁移完成。
6. 本报告不授予 G-013/G-014、CQG、IG-1/2/3、用户验收或 release 完成；Gate 判定权在 Orchestrator。
7. 本报告未修改产品代码、测试、工具、构建配置、`input/` 或状态文件；唯一写入为 `artifacts/90-integration/`。

---

## 10. 证据索引与追溯

### 10.1 本任务证据（`artifacts/90-integration/evidence/`）

| 文件 | 内容 |
|---|---|
| `t22-host-node-tests.tap` | 697 条 host TAP |
| `t22-clean-assemble.log` | clean HAP 构建 |
| `t22-codelinter.log` | 静态检查 |
| `t22-layering.log` / `t22-layering.json` | 分层检查与例外明细 |
| `t22-layering-fixture-tests.log` | 10/10 fixture 自测 |
| `t22-i18n-checker.log` / `t22-i18n-report.json` | CHK-01..09 与计数 |
| `t22-crosscheck.log` | 66/66 协议资产交叉校验 |
| `t22-simulator-contract.log` | 20/20 HTTP+TLS 契约套件 |
| `t22-ohosTest-assemble.log` | ohosTest HAP 编译（COMPILED_ONLY） |
| `t22-ack-p95-mock.json` / `.log` | ACK p95 MOCK_ONLY |

> 证据日志为原始 stdout 的 **ANSI 转义与行尾空白规范化**版本（通过 `git diff --cached --check`）；断言内容、计数与顺序未改写。

### 10.2 上游追溯

- 需求：`input/requirements/YaoCore_HarmonyOS_App_Requirements.md` §3（26 FR）/§4（NFR 4.1..4.3）。
- 契约：`artifacts/20-architecture/contract-baseline.md`（§4.3/§4.5）；ADR-001..004；DES-A §27.6；DES-B §2.3/§18.1。
- 计划：`artifacts/30-plan/delivery-plan.md` §3.4 T-22、§4.2 G-013、§4.4 Stage Gate；`component-graph.md` C-01..C-29。
- 组件 Gate：`state/gates/CQG-T06..T18.md`（C-01..C-28）；C-29 工具证据见 T-19/T-20/T-21。
- 测试：`artifacts/60-testing/test-report.md`、`test-plan.md`、`tooling-cleanup-report.md`；`entry/src/test/**`。
- 评审：`artifacts/70-review/final-system-review.md`（F-01..F-09）。
- 文档/风险：`README.md`（README-001 v1.0）；`artifacts/80-maintenance/maintenance-plan.md`（§3/§4/§5）。
- 输入完整性：`state/handoffs/wp-087-integration.json`（10 项 SHA-256 实算一致）。

---

*INTEGRATION-REPORT-001 结束。所有 PASS 均对应当前集成 revision `d2896fb` 与本报告 §1 环境实际执行；设备/真实环境、`COMPILED_ONLY`、`MOCK_ONLY` 均未写成 PASS。*

---

## 11. A1 合并记录（2026-10-18，wp-095）

> 本节由 `repository-manager` 在合并任务 `wp-095-merge-a1` 中追加，记录 `task/wp-090-ports` → `feat/yaocore-app` 的本地合并与合并后验证。§1–§10 的历史结论仍针对 `d2896fb`，本节不回溯改写。

### 11.1 分支、合并与源提交

| 项 | 值 |
|---|---|
| 源分支 | `task/wp-090-ports` @ `0eda9933a0b3d52a1a8a429b05b2587d19583105` |
| 目标分支 | `feat/yaocore-app` @ `1d4b202a8ee68acb1679e9c7472c883e0e30ca9e`（合并前 = handoff `base_commit`） |
| 合并基 | `1d4b202`（目标 tip 为来源 tip 的直接祖先） |
| 合并策略 | `git merge --no-ff`（`ort`，无冲突；未手工编辑冲突文件） |
| 合并提交 | `54f2a0b3a5e2b91dbc3cb66b08a85be0d8498782`（`merge: A1 端口迁移与 T-23 裁定修复`） |
| 父提交 | `1d4b202`（目标，第一父）+ `0eda993`（来源，第二父） |
| 结果树 | 与来源 tip 一致：`git diff --quiet 54f2a0b 0eda993` 退出 0 |
| 合并范围 | 215 个路径（+3407 / −2470），全部落在 handoff `writes` 内；未改 `input/`、构建配置或状态文件 |

源提交（`1d4b202..0eda993`，5 个）：

| # | Commit | Subject |
|---|---|---|
| 1 | `aa9bdd1b9a87c1d7ed51fa1fd7050615ce7daf51` | refactor(contracts): 迁移端口到 contracts 并收口例外 |
| 2 | `f290f69a43a5377c3b9d916261cac987c6c826fc` | docs(review): A1 端口迁移独立评审 |
| 3 | `76c47f4afd94e820b6186d183e7e2287380af7a6` | docs(design): T-23 裁定与端口契约同步 |
| 4 | `cc2233dcf8f348fd619b508889de9e94edfad88c` | fix(contracts): 应用 T-23 裁定并修复 ohosTest imports |
| 5 | `0eda9933a0b3d52a1a8a429b05b2587d19583105` | docs(review): T-23 修复聚焦复评 |

### 11.2 合并后验证矩阵（在 `54f2a0b` 上实际执行）

| # | 检查 | 命令 | 实测结果 | 退出码 |
|---|---|---|---|---|
| 1 | Host 测试 | `entry/src/test/run-host-tests.sh` | `1..697`；`# pass 697 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`；≈3080.5 ms | 0 |
| 2 | 分层检查 | `python3 tools/contract/check_layering.py` | `files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0`；PASS | 0 |
| 3 | 分层夹具自测 | `python3 tools/contract/test_check_layering.py` | `Ran 22 tests in 2.112s ... OK`（22/22） | 0 |
| 4 | i18n strict-ui | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | `blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16`；CHK-08/CHK-09 PASS | 0 |
| 5 | 协议资产交叉校验 | `python3 tools/contract/crosscheck_protocol_assets.py` | `hard checks: ALL PASS`；14 条既有 frozen-input findings（非阻塞） | 0 |
| 6 | 构建 | `hvigorw clean assembleHap --no-daemon` | `BUILD SUCCESSFUL in 14 s 936 ms`；35 tasks（34 executed / 1 up-to-date）；unsigned HAP；仅既有 ArkTS 警告 | 0 |

### 11.3 残余与边界

| 项 | 状态 | 说明 |
|---|---|---|
| `PORT-LOC-01`（`ClockPort`/`IdPort` 留在 `common/types/Ports.ets`） | **OPEN（已登记）** | 需批准的 D-01 或冻结签名变更；live `port_location_exceptions` 仅此 1 条，`used=0`；不得写成“17 条全关闭” |
| `RR-01` `export * from` 未触发 D-03/环检查 | Low（工具债，未修复） | 当前仓库无使用；建议紧随 checker 任务修复并补 fixture |
| `RR-02` 行号/环违规诊断错位 | Low（既有，未修复） | 不影响门禁判定与退出码 |
| `RR-03` 实现报告文首/§7.2 与 §10 状态不一致 | Low（文档，非阻塞） | 建议后续文档同步任务统一 |
| `RR-04` checker/allowlist 元数据仍标 wp-090 | Info（provenance） | 可加 `updated_by: wp-093-t23-fixes` 或保持历史并在 Gate 注明 |
| 设备/模拟器 ohosTest、真实 BLE/LAN/TLS/云/视觉/A11y/fps | **BLOCKED / NOT RUN** | 无 `hdc` target、无模拟器、无签名；不得用 host/mock 外推为验收 PASS |

### 11.4 边界声明

1. 本记录只证明上述 5 个源提交已以 `--no-ff` 合并入 `feat/yaocore-app`，并在合并结果上重新执行了 §11.2 的六项检查；不构成 Stage Gate、IG-3/IG-4、设备验收或 release PASS。
2. 合并与验证均在本地完成：未 push、未 fetch/pull、未 rebase、未改写任何已评审提交；`task/wp-090-ports` 仍保留。
3. 合并后证据更新与报告提交见 `state/reports/wp-095-merge-report.md`；handoff 为 `state/handoffs/wp-095-merge-a1.json`。

---

## 12. i18n 合并记录（2026-10-18，wp-100）

> 本节由 `repository-manager` 在合并任务 `wp-100-merge-i18n` 中追加，记录 `task/wp-096-i18n-triage` → `feat/yaocore-app` 的本地合并与合并后验证。§1–§11 的历史结论仍针对各自标注的 revision，本节不回溯改写；凡旧章节仍写“596 条 `PENDING_REVIEW`”的表述，以本节与 `artifacts/50-implementation/t24-i18n-triage.md` 的新口径为准，旧文档待后续同步。

### 12.1 分支、合并与源提交

| 项 | 值 |
|---|---|
| 源分支 | `task/wp-096-i18n-triage` @ `875c12da56b7b390ad85e732a2de14eac68f1ea0`（= handoff `source_commit`） |
| 目标分支 | `feat/yaocore-app` @ `07895fd98b222264aec566cefd43a0ee9cb10f5e`（合并前 = handoff `base_commit`） |
| 合并基 | `07895fd`（目标 tip 为来源 tip 的直接祖先，无分叉） |
| 合并策略 | `git merge --no-ff`（`ort`，无冲突；未手工编辑冲突文件） |
| 合并提交 | `0d7f1f89cdd7f44e86f09cd022916ff72bf3f9cb`（`chore(merge): 合并 i18n 证据化 triage 与修正`） |
| 父提交 | `07895fd`（目标，第一父）+ `875c12d`（来源，第二父） |
| 结果树 | 与来源 tip 一致：`git diff --quiet 0d7f1f8 875c12d` 退出 0 |
| 合并范围 | 7 个路径（+2555 / −625），全部落在 handoff `writes` 内；未改 `input/`、构建配置、locale 值或 UI 代码 |

合并路径：

| 状态 | 路径 |
|---|---|
| A | `artifacts/50-implementation/t24-i18n-triage.md` |
| A | `artifacts/70-review/t24-i18n-review.md` |
| A | `artifacts/70-review/t24-i18n-rereview.md` |
| A | `tools/i18n/triage_legacy.py` |
| M | `entry/src/test/i18n/README.md` |
| M | `entry/src/test/i18n/legacy-migration.csv` |
| M | `entry/src/test/i18n/migration-boundary.md` |

源提交（`07895fd..875c12d`，4 个）：

| # | Commit | Subject |
|---|---|---|
| 1 | `2d45628b3e0ac4fecb6660727103f1b61b8498d6` | chore(i18n): 证据化 triage 615 条历史文案 |
| 2 | `818cb790bf6f94b44e9bee2839a5081ffc5a1dcb` | docs(review): i18n triage 独立复审 |
| 3 | `9d22b5b2abe44bd03f6ee7de3714ec37a580ec9e` | fix(i18n): 修正 triage 证据链与检查器校验 |
| 4 | `875c12da56b7b390ad85e732a2de14eac68f1ea0` | docs(review): i18n 修正聚焦复评 |

门禁证据：`artifacts/70-review/t24-i18n-rereview.md`（Producer `agent:quality-reviewer`，Verdict **PASS**，仅覆盖复评 revision `9d22b5b` 与报告 §1 声明范围；来源提交内 sha256 `f455c80079f307e0b540c43d2d986d3016c559f7d9c20cc45dc7c2abb131d139` = handoff pin）。提交 `875c12d` 仅把该复评报告写入分支，不改变 `9d22b5b` 的被审内容。

### 12.2 合并后验证矩阵（在 `0d7f1f8` 上实际执行）

| # | 检查 | 命令 | 实测结果 | 退出码 |
|---|---|---|---|---|
| 1 | triage 一致性 | `python3 tools/i18n/triage_legacy.py --check` | `615 rows`；`OK: CSV matches computed triage; invariants pass` | 0 |
| 2 | triage 汇总 | `python3 tools/i18n/triage_legacy.py --summary` | `A 606`（`ACCEPTED 10` / `MIGRATED 46` / `PENDING_REVIEW 6` / `OBSOLETE_LEGACY 544`）、`C 6`、`D 3`、`INLINE_LITERAL 0`；`csv_status: UP_TO_DATE` | 0 |
| 3 | i18n strict-ui | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | CHK-01..09 PASS；`blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16`；CHK-05 57 条 unused key、CHK-07 16 条 hardcoded 均非 blocking | 0 |
| 4 | Host 测试 | `entry/src/test/run-host-tests.sh` | `1..697`；`# tests 697 / # pass 697 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`；≈3059.5 ms | 0 |
| 5 | 分层检查 | `python3 tools/contract/check_layering.py` | `files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0`；PASS | 0 |
| 6 | 分层夹具自测 | `python3 tools/contract/test_check_layering.py` | `Ran 22 tests in 2.119s`；`OK`（22/22） | 0 |
| 7 | 构建 | `hvigorw clean assembleHap --no-daemon` | `BUILD SUCCESSFUL in 14 s 778 ms`；35 tasks（34 executed / 1 up-to-date）；unsigned HAP；仅既有 ArkTS 警告 | 0 |

补充：以上命令均在合并提交的干净工作树上运行，Python 命令设置 `PYTHONDONTWRITEBYTECODE=1`；运行后清理 `__pycache__`，`git status --porcelain` 为空（ignored 构建产物除外）。

### 12.3 残余与边界

| 项 | 状态 | 说明 |
|---|---|---|
| 615 条 triage 状态 | **已登记，语义待确认** | A 类 606 = `ACCEPTED 10` + `MIGRATED 46` + `PENDING_REVIEW 6` + `OBSOLETE_LEGACY 544`；另有 C 6、D 3。`MIGRATED`/`OBSOLETE_LEGACY` 表示证据化分类，不等于 544/46 条业务语义已人工签署 |
| 6 条 `PENDING_REVIEW` | **OPEN** | 关闭/刷新/添加网关/执行中/简体中文/语言；其中 5 条跨 rawfile 与 `string.json` 双存储，`执行中` 为同存储三义；需 T-17/T-18/solution-architect 裁定单一存储与目标键 |
| 11 条 `B_REWRITE_REQUIRED` | **OPEN** | 全部落在 `OBSOLETE_LEGACY`，旧英文存在 machine/file(s) 术语问题；本次只补证据并保留原备注，未重译、未改状态 |
| 6 条 C + 3 条 D | **保留待复核** | C：4 条 `RECHECK_REQUIRED` + 2 条 `SAFETY_RECHECK_REQUIRED`；D：3 条品牌数据 `NONE`；均未删除、未降级 |
| 文档 596 旧口径 | **待同步（非阻塞）** | 根 `README.md` 第 78/202 行、`artifacts/80-maintenance/maintenance-plan.md` §3.4，以及本报告 §4/§6/§7/§8 仍写“596 条 `PENDING_REVIEW`”。按旧基线（596 = 46 + 6 + 544）总数仍可解释，但新口径应以本轮 triage 的 10/46/6/0/544 + C 6 + D 3 为准；本节为 append-only 增量，旧章节由对应 owner 在后续文档任务同步 |
| 检查器告警 | **非阻塞** | `--strict-ui` 0 blocking / 0 missing；CHK-05 57 条未使用键（带 allowlist 39 条）与 CHK-07 16 条技术/品牌/Mock 字面量为 warning，非本次 triage 的 A 类旧字典行 |
| locale/UI 变更 | **未涉及** | 本次合并未修改任何 locale 值或 UI 代码；`INLINE_LITERAL=0` 不等于源码零硬编码 |
| 设备/真实环境 | **BLOCKED / NOT RUN** | 无设备、模拟器与签名；不得用 host/构建结果外推为设备验收或 Stage Gate PASS |

### 12.4 边界声明

1. 本记录只证明上述 4 个源提交已以 `--no-ff` 合并入 `feat/yaocore-app`，并在合并结果上重新执行了 §12.2 的七项检查；不构成 Stage Gate、Component Quality、设备验收或 release PASS。
2. 合并与验证均在本地完成：未 push、未 fetch/pull、未 rebase、未改写任何已评审提交；未切换分支；`task/wp-096-i18n-triage` 仍保留。
3. 合并后证据更新与报告提交见 `state/reports/wp-100-merge-report.md`；handoff 为 `state/handoffs/wp-100-merge-i18n.json`。

---

## 13. 检查器 RR 修复合并记录（2026-10-18，wp-103）

> 本节由 `repository-manager` 在合并任务 `wp-103-merge-checker` 中追加，记录 `task/wp-101-checker-rr` → `feat/yaocore-app` 的本地合并与合并后验证。§1–§12 的历史结论仍针对各自标注的 revision，本节不回溯改写。本节只关闭 T-25 工具侧 RR-01/RR-02/RR-04 的合并；不关闭 RR-03、DES 状态同步或任何 Stage Gate。

### 13.1 分支、合并与源提交

| 项 | 值 |
|---|---|
| 源分支 | `task/wp-101-checker-rr` @ `eb73a2c246d4833c3d8ab24772fc6827589dfba5`（= handoff `source_commit`） |
| 目标分支 | `feat/yaocore-app` @ `b7e1e24c7a18c135b971359232e368c10d62b763`（合并前 = handoff `base_commit`） |
| 合并基 | `b7e1e24`（目标 tip 为来源 tip 的直接祖先，无分叉） |
| 合并策略 | `git merge --no-ff`（`ort`，无冲突；未手工编辑冲突文件） |
| 合并提交 | `6446a977d74455b06fac2ad0a72772296839a317`（`chore(merge): 合并检查器 RR 修复`） |
| 父提交 | `b7e1e24`（目标，第一父）+ `eb73a2c`（来源，第二父） |
| 结果树 | 与来源 tip 一致：`git diff --quiet 6446a97 eb73a2c` 退出 0 |
| 合并范围 | 17 个路径（+505 / −11）：3 M + 14 A；全部落在 handoff `writes` 内；未改 `input/`、产品代码、构建配置或状态文件 |

合并路径：

| 状态 | 路径 |
|---|---|
| M | `tools/contract/check_layering.py` |
| M | `tools/contract/layering_allowlist.json` |
| M | `tools/contract/test_check_layering.py` |
| A | `tools/contract/fixtures/layering/export-star-bad/**`（3 文件） |
| A | `tools/contract/fixtures/layering/export-type-star-ok/**`（3 文件） |
| A | `tools/contract/fixtures/layering/export-named-value-bad/**`（3 文件） |
| A | `tools/contract/fixtures/layering/export-named-type-ok/**`（3 文件） |
| A | `artifacts/50-implementation/t25-checker-rr.md` |
| A | `artifacts/70-review/t25-checker-review.md` |

源提交（`b7e1e24..eb73a2c`，2 个）：

| # | Commit | Subject |
|---|---|---|
| 1 | `16b0f7c99a06ee773772df779ed5963373087617` | fix(contract): 补齐 export* 检查与诊断行号 |
| 2 | `eb73a2c246d4833c3d8ab24772fc6827589dfba5` | docs(review): 检查器 RR 修复独立复审 |

门禁证据：`artifacts/70-review/t25-checker-review.md`（Producer `agent:quality-reviewer`，Verdict **PASS（仅限 `16b0f7c` 与报告 §1 声明范围）**；blob sha256 `0c742cdb9d9b386e67ba797ec93514cf162b9ac2feb7d15d829efb2769abbadf` = handoff `gate_evidence_path_sha256`）。提交 `eb73a2c` 仅把该复审报告写入分支，不改变 `16b0f7c` 的被审内容。

### 13.2 合并后验证矩阵（在 `6446a97` 上实际执行）

| # | 检查 | 命令 | 实测结果 | 退出码 |
|---|---|---|---|---|
| 1 | 分层夹具自测 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/test_check_layering.py` | `Ran 27 tests in 2.428s`；`OK`（27/27；原 22 + 新增 5） | 0 |
| 2 | 分层检查 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | `files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0`；PASS | 0 |
| 3 | Host 测试 | `entry/src/test/run-host-tests.sh` | `1..697`；`# tests 697 / # pass 697 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`；≈3166.9 ms | 0 |
| 4 | 协议资产交叉校验 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py` | `hard checks: ALL PASS`；14 条既有 frozen-input findings（非阻塞） | 0 |
| 5 | i18n strict-ui | `PYTHONDONTWRITEBYTECODE=1 python3 entry/src/test/i18n/check_i18n.py --strict-ui` | CHK-01..09 PASS；`blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16` | 0 |
| 6 | 构建 | `hvigorw clean assembleHap --no-daemon` | `BUILD SUCCESSFUL in 14 s 651 ms`；35 tasks（34 executed / 1 up-to-date）；unsigned HAP；仅既有 ArkTS 警告 | 0 |

补充：六项命令均在合并提交的干净工作树上运行；Python 命令设置 `PYTHONDONTWRITEBYTECODE=1`；运行后清理 `__pycache__`，证据提交前 `git status --porcelain` 仅显示两份 deliverable（ignored 构建产物除外）。

### 13.3 残余与边界

| 项 | 状态 | 说明 |
|---|---|---|
| `V-01` `export * as ns` 无永久 fixture | **OPEN（Low，测试覆盖）** | 实现已覆盖且临时探针验证 exit 1；建议后续 bounded 任务补 fixture |
| `V-02` 无空白 `export{…}from` 旁路 | **OPEN（Info，既有解析边界）** | 当前仓库无使用；长期可改 tokenizer |
| `V-03` 内联 `export { type A }` / `import { type A }` 保守按值 | **已知保守（Info）** | 仓库当前无使用；可能误报 |
| `V-04` 值再导出环文案仍写 “type-only import cycle” | **Info（诊断文案）** | path/line/spec 正确，不影响退出码 |
| `V-05` `export type *` 仅解析器级正例 | **未验证（Info）** | 未经 ArkTS 编译器验证；当前仓库未使用 |
| `V-06` `updated_by`/policy 无自动断言 | **Info（元数据测试）** | 本次手工验证；schema 与退出码语义未变 |
| `RR-03` 实现报告历史章节一致性 | **OPEN（文档，非阻塞）** | 仍待后续文档同步任务统一 |
| DES 文本状态同步 | **待同步（非阻塞）** | DES-A/DES-B 的 checker 债务状态未随本任务改写 |
| `PORT-LOC-01`（`ClockPort`/`IdPort`） | **OPEN（已登记）** | 非本次范围；live `port_location_exceptions` 仍为 1 条 |
| 设备/模拟器 ohosTest、真实 BLE/LAN/TLS/云/视觉/A11y/fps | **BLOCKED / NOT RUN** | 无 `hdc` target、无模拟器、无签名；不得用 host/build 结果外推为验收 PASS |

### 13.4 边界声明

1. 本记录只证明上述 2 个源提交已以 `--no-ff` 合并入 `feat/yaocore-app`，并在合并结果上重新执行了 §13.2 的六项检查；不构成 Stage Gate、Component Quality、设备验收或 release PASS。
2. 合并与验证均在本地完成：未 push、未 fetch/pull、未 rebase、未改写任何已评审提交；未切换分支；`task/wp-101-checker-rr` 仍保留。
3. 合并后证据更新与报告提交见 `state/reports/wp-103-merge-report.md`；handoff 为 `state/handoffs/wp-103-merge-checker.json`。

---

## 14. DES F-03 状态同步合并记录（2026-10-18，wp-105）

> 本节由 `repository-manager` 在合并任务 `wp-105-merge-des` 中追加，记录 `task/wp-104-des-sync` → `feat/yaocore-app` 的本地合并与合并后验证。§1–§13 的历史结论仍针对各自标注的 revision，本节不回溯改写。本节只记录 DES-A/DES-B 的状态同步文本已进入集成分支；不新增裁定、不宣告 Stage Gate 或验收 PASS。

### 14.1 分支、合并与源提交

| 项 | 值 |
|---|---|
| 源分支 | `task/wp-104-des-sync` @ `b2d92d7ae372b407974cda5f3adf762e95b85f67`（= handoff `source_commit`） |
| 目标分支 | `feat/yaocore-app` @ `40044c092d56e2ad1ef91453b0029517adb19b98`（合并前 = handoff `base_commit`） |
| 合并基 | `40044c0`（目标 tip 为来源 tip 的直接祖先，无分叉） |
| 合并策略 | `git merge --no-ff`（`ort`，无冲突；未手工编辑冲突文件） |
| 合并提交 | `4fe9ccf04028e68d967c4bef4ffe72ff603c0b75`（`chore(merge): 合并 DES F-03 状态同步`） |
| 父提交 | `40044c0`（目标，第一父）+ `b2d92d7`（来源，第二父） |
| 结果树 | 与来源 tip 一致：`git diff --quiet 4fe9ccf b2d92d7` 退出 0 |
| 合并范围 | 2 个路径（+59 / −18）：`des-001a-foundation-transport.md`（+31 / −8）、`des-001b-domain-presentation.md`（+28 / −10）；全部落在 handoff `writes` 的 `artifacts/40-detailed-design/` 内；未改 `input/`、产品代码、构建配置或状态文件 |

源提交（`40044c0..b2d92d7`，1 个）：

| # | Commit | Subject |
|---|---|---|
| 1 | `b2d92d7ae372b407974cda5f3adf762e95b85f67` | docs(design): 同步 T-23 F-03 落地状态 |

门禁证据：`artifacts/40-detailed-design/des-001a-foundation-transport.md`（来源分支 blob sha256 `04a61be8b7db300cfbcaa6df6a7240846705d17da6178172f1e93a1f7b5c51f9` = handoff `gate_evidence_path_sha256`；Producer `agent:solution-architect`）。该文件是本次状态同步的载体与 handoff 固定证据，**不是独立审查报告**；本节不据此宣告新的 Gate PASS。

### 14.2 合并后验证矩阵（在 `4fe9ccf` 上实际执行，早于任何证据改动）

| # | 检查 | 命令 | 实测结果 | 退出码 |
|---|---|---|---|---|
| 1 | 协议资产交叉校验 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py` | **hard checks: ALL PASS**；14 条既有 frozen-input findings（非阻塞） | 0 |
| 2 | 分层检查 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | **PASS**：`files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0` | 0 |
| 3 | Host 测试 | `entry/src/test/run-host-tests.sh` | **697/697 PASS**：`1..697`、`# tests 697 / # pass 697 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`；≈3043.0 ms | 0 |

补充：以上命令均在合并提交的干净工作树上运行；Python 命令设置 `PYTHONDONTWRITEBYTECODE=1`；运行后清理 `__pycache__`，证据提交前 `git status --porcelain` 仅显示两份 deliverable。

### 14.3 状态同步要点

| 项 | 同步后状态 | 依据 |
|---|---|---|
| T-23 F-03 C-23 符号 | **CLOSED @ `cc2233d`**：`ProvisioningPermissionPort`/`ProvisioningPermissionKind` 已落地；C-28 app seam（`PermissionPort`/`PermissionKind`/`PermissionState`/`PermissionResult`）未变 | `wp-093-t23-fixes`；独立复审 `wp-094-t23-rereview` PASS |
| §27.6.4 `PORT-LOC-17` | **CLOSED（位置 + 符号）** | DES-A §27.6.4；`cc2233d` + 复审 PASS |
| §27.6.4 `PORT-LOC-01` | **仍 OPEN**：`ClockPort`/`IdPort` 仍在 `common/types/Ports.ets`，为唯一 live 端口位置例外 | DES-A §27.6.4；未因本次同步改变 |
| RR-01/RR-02 checker 缺口 | 已由 `wp-101-checker-rr` @ `16b0f7c` 修复；再导出覆盖与诊断行号补齐 | `artifacts/70-review/t25-checker-review.md`（PASS） |
| D-03 规则文本 | **未改变**（`contracts/**` 同层 type-only + 无环） | DES-A §2.2/§27.6.2；本次仅同步状态 |
| 冻结签名 / G-004 语义 | **未改变**；未新增裁定 | DES-A/DES-B 文件头与附录 E.10/E.9 |
| DES-B `EXT-DES-B-34` | **CLOSED @ `cc2233d`**；`EXT-DES-B-22` 仍为历史/SUPERSEDED | DES-B §23.7 |
| 文档落点 | DES-A：文件头、§2.1 树注记、§27.6.2/§27.6.3 P4、§27.6.4、§29、附录 E §E.10；DES-B：文件头、§12.1.1、§23.7、附录 E §E.4/§E.7/§E.9 | 源提交 `b2d92d7` |

### 14.4 边界声明

1. 本记录只证明上述 1 个源提交已以 `--no-ff` 合并入 `feat/yaocore-app`，并在合并结果上重新执行了 §14.2 的三项检查；不构成 Stage Gate、Component Quality、独立评审、设备验收或 release PASS。
2. 合并与验证均在本地完成：未 push、未 fetch/pull、未 rebase、未改写任何已评审提交；未切换分支；`task/wp-104-des-sync` 仍保留。
3. 合并后证据更新与报告提交见 `state/reports/wp-105-merge-report.md`；handoff 为 `state/handoffs/wp-105-merge-des.json`。

---

## 15. TEST-002 测试阶段报告合并记录（2026-10-18，wp-107）

> 本节由 `repository-manager` 在合并任务 `wp-107-merge-testing` 中追加，记录 `task/wp-106-testing-stage` → `feat/yaocore-app` 的本地合并与合并后验证。§1–§14 的历史结论仍针对各自标注的 revision，本节不回溯改写。本节只记录 TEST-002 测试阶段报告与 18 份证据日志已进入集成分支；不新增裁定、不宣告 Stage Gate、产品验收或 release PASS。

### 15.1 分支、合并与源提交

| 项 | 值 |
|---|---|
| 源分支 | `task/wp-106-testing-stage` @ `7200543010f4fe95cc6805ac7845f0312e46b181`（= handoff `source_commit`） |
| 目标分支 | `feat/yaocore-app` @ `e74a181cebec1968d9a197c38e350cd2dda6cc80`（合并前 = handoff `base_commit`） |
| 合并基 | `e74a181`（目标 tip 为来源 tip 的直接祖先，无分叉） |
| 合并策略 | `git merge --no-ff`（`ort`，无冲突；未手工编辑冲突文件） |
| 合并提交 | `6939574be099ece91e3e698d4815fa932957298b`（`chore(merge): 合并 TEST-002 测试阶段报告`） |
| 父提交 | `e74a181`（目标，第一父）+ `7200543`（来源，第二父） |
| 结果树 | 与来源 tip 一致：`git diff --quiet 6939574 7200543` 退出 0 |
| 合并范围 | 19 个路径（+6458 / −0）：`artifacts/60-testing/testing-stage-report.md`（+371）与 `artifacts/60-testing/evidence/` 下 18 份证据日志；全部落在 handoff `writes` 的 `artifacts/60-testing/` 内；未改 `input/`、产品代码、测试断言、工具、构建配置、README 或状态文件 |

源提交（`e74a181..7200543`，1 个）：

| # | Commit | Subject |
|---|---|---|
| 1 | `7200543010f4fe95cc6805ac7845f0312e46b181` | test(stage): 执行 TEST-002 最终候选矩阵 |

门禁证据：`artifacts/60-testing/testing-stage-report.md`（来源分支 blob sha256 `296ea215f73e04ad7266ec1f97aa403c846dd7fc345aed53a4970303f8de2a4c` = handoff `gate_evidence_path_sha256`；Producer `agent:test-engineer`）。该文件是 testing Stage 的测试报告与 handoff 固定证据，**不是独立审查报告**；本节不据此宣告新的 Gate PASS。

### 15.2 合并后验证矩阵（在 `6939574` 上实际执行，早于任何证据改动）

| # | 检查 | 命令 | 实测结果 | 退出码 |
|---|---|---|---|---|
| 1 | Host 测试 | `entry/src/test/run-host-tests.sh` | **697/697 PASS**：`1..697`、`# tests 697 / # pass 697 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`；≈3065.4 ms | 0 |
| 2 | 协议资产交叉校验 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py` | **hard checks: ALL PASS**：66 条 `[PASS]` / 0 条 `[FAIL]`；14 条既有 frozen-input `FINDING`（非阻塞） | 0 |
| 3 | 分层检查 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | **PASS**：`files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0` | 0 |

补充：三项检查与 TEST-002 报告 §2 的对应结果一致（host 697/697、crosscheck 66/66、layering 0 violation）。命令均在合并提交的干净工作树上运行；Python 命令设置 `PYTHONDONTWRITEBYTECODE=1`；运行后清理 `__pycache__`，证据提交前 `git status --porcelain` 仅显示两份 deliverable（ignored 构建产物除外）。

### 15.3 TEST-002 结论与残余

| 项 | 结论 | 依据 |
|---|---|---|
| TEST-002 Verdict | **`PASS_WITH_ACCEPTED_RISKS`（代码级 testing Stage @ `e74a181`）**；11 项强制矩阵命令全部实际执行且 exit 0；0 `FAIL_PRODUCT` / 0 `FAIL_TEST` / 0 `FAIL_ENV` | `artifacts/60-testing/testing-stage-report.md` §2、§6 |
| 强制矩阵 | host 697/697、crosscheck 66/66、仿真器契约 20/20（HTTP+TLS）、layering 0 violation、layering fixture 27/27、i18n `--strict-ui` 0 blocking / 0 missing、构建与 lint（0 error / 25 warning）通过；ACK p95 `0.609 ms` 仅 **`MOCK_ONLY`** | 同上 §2 |
| FR / NFR | 26 FR：24 covered (host)、2 partial、0 gap；NFR 4.1/4.2/4.3 均 **partial**（设备/真实环境证据缺失，非代码级回归） | 同上 §3、§4 |
| 建议 | G-016 testing Stage **`PASS_WITH_ACCEPTED_RISKS`**，允许进入 acceptance 分析；Gate 判定归 Orchestrator，本节不代行 | 同上 §7 |
| `PORT-LOC-01` | **仍 OPEN**：`ClockPort`/`IdPort` 仍在 `common/types/Ports.ets`，为唯一 live 端口位置例外；0 violation 不代表端口位置完全合规 | 同上 §5.2 |
| `D-030 / GAP-T18-01` | `FamilyRepository.addGatewayToFamily` 无 actor/RBAC；D-030 书面接受 v1 风险，**未关闭**；acceptance 必须记录 | 同上 §5.2、§7.2 |
| `R4-01` | `addGatewayToFamily` 已发起后的取消不能 durable 回滚；v1 边界，无 durable 回滚测试 | 同上 §5.2 |
| i18n / crosscheck 债务 | 73 warning / 16 hardcoded（均非用户可见 UI 字符串，0 blocking）；crosscheck 14 条既有 `FINDING`（冻结输入勘误线索，不阻断 hard checks） | 同上 §5.2 |
| i18n legacy triage | 615 行：606 A（ACCEPTED 10 / MIGRATED 46 / PENDING_REVIEW 6 / OBSOLETE_LEGACY 544）、6 C、3 D；11 条 `B_REWRITE_REQUIRED`、6 条 `C_REVIEW`；不得把 544/46 写成业务语义已签署 | 同上 §5.2 |
| 其他残余 | 测试源码 lint/覆盖率缺口；README 仍写 “596 条 `PENDING_REVIEW`” 旧口径（documentation 阶段同步）；unsigned HAP；构建 API warning | 同上 §5.2 |
| 设备/真实环境 | `BLK-01..08` 仍 **BLOCKED / UNAVAILABLE**（无 `hdc` target、无模拟器、无签名、无真实 BLE/LAN/TLS/云）；不得用 host/build 结果外推为设备或产品验收 PASS | 同上 §5.3、§7.3 |

### 15.4 边界声明

1. 本记录只证明上述 1 个源提交已以 `--no-ff` 合并入 `feat/yaocore-app`，并在合并结果上重新执行了 §15.2 的三项检查；不构成 Stage Gate、Component Quality、独立评审、产品验收、设备验收或 release PASS。
2. 合并与验证均在本地完成：合并前执行 `git fetch origin`（仅更新远端跟踪引用），未 push、未 pull、未 rebase，未改写任何已评审提交；未切换分支；`task/wp-106-testing-stage` 仍保留。
3. 合并后证据更新与报告提交见 `state/reports/wp-107-merge-report.md`；handoff 为 `state/handoffs/wp-107-merge-testing.json`。

---

## 16. ACCEPT-001 合并记录（2026-10-18，wp-109）

> 本节由 `repository-manager` 在合并任务 `wp-109-merge-acceptance` 中追加，记录 `task/wp-108-acceptance` → `feat/yaocore-app` 的本地合并与合并后验证。§1–§15 的历史结论仍针对各自标注的 revision，本节不回溯改写。本节只记录 ACCEPT-001 验收就绪报告已进入集成分支；**不新增裁定、不宣告 G-017、用户验收、产品验收或 release PASS**。

### 16.1 分支、合并与源提交

| 项 | 值 |
|---|---|
| 源分支 | `task/wp-108-acceptance` @ `d649ac78a13efbaf64c19cd6b5ce381787150c7e`（= handoff `source_commit`） |
| 目标分支 | `feat/yaocore-app` @ `b10d2f50c931b7c82cd8a2105fbe804582d24b32`（合并前 = handoff `base_commit`） |
| 合并基 | `b10d2f5`（目标 tip 为来源 tip 的直接祖先，无分叉） |
| 合并策略 | `git merge --no-ff`（`ort`，无冲突；未手工编辑冲突文件） |
| 合并提交 | `06265fdfce27834e4bc202b08df5558c793b5d67`（`chore(merge): 合并 ACCEPT-001 验收就绪报告`） |
| 父提交 | `b10d2f5`（目标，第一父）+ `d649ac7`（来源，第二父） |
| 结果树 | 与来源 tip 一致：`git diff --quiet 06265fd d649ac7` 退出 0 |
| 合并范围 | 1 个路径（+534 / −3）：`artifacts/65-acceptance/acceptance-report.md`（base 为 3 行占位，来源替换为 535 行报告）；落在 handoff `writes` 的 `artifacts/65-acceptance/` 内；未改 `input/`、产品代码、测试、工具、构建配置或状态文件 |

源提交（`b10d2f5..d649ac7`，1 个）：

| # | Commit | Subject |
|---|---|---|
| 1 | `d649ac78a13efbaf64c19cd6b5ce381787150c7e` | docs(acceptance): 产出 ACCEPT-001 验收就绪报告 |

门禁证据：`artifacts/65-acceptance/acceptance-report.md`（来源分支 blob sha256 `794fd588d7bbfbf9f7856dd3e5d9606e008c97faa973596abb01798a742a3e3c` = handoff `gate_evidence_path_sha256`；Producer `agent:system-verifier`）。该文件是 acceptance readiness 报告与 handoff 固定证据，**不是独立审查报告**；本节不据此宣告 Gate PASS。

### 16.2 合并后验证矩阵（在 `06265fd` 上实际执行，早于任何证据改动）

| # | 检查 | 命令 | 实测结果 | 退出码 |
|---|---|---|---|---|
| 1 | Host 测试 | `PYTHONDONTWRITEBYTECODE=1 entry/src/test/run-host-tests.sh` | **697/697 PASS**：`1..697`、`# tests 697 / # pass 697 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`；≈3068.6 ms | 0 |
| 2 | 协议资产交叉校验 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py` | **hard checks: ALL PASS**：66 条 `[PASS]` / 0 条 `[FAIL]`；14 条既有 frozen-input `FINDING`（非阻塞） | 0 |
| 3 | 分层检查 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | **PASS**：`files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0` | 0 |

补充：三项检查与 ACCEPT-001 §0.3 的对应复验一致（host 697/697、crosscheck 66/66、layering 0 violation），且与 TEST-002 的基线相同；完整日志暂存于 `/tmp/opencode/wp109-*`（未提交）。命令均在合并提交的干净工作树上运行；Python 命令设置 `PYTHONDONTWRITEBYTECODE=1`；运行后已清理 `__pycache__`。证据提交前 `git status --porcelain` 仅显示已跟踪的 `artifacts/90-integration/integration-report.md` 修改；新增的 `state/reports/wp-109-merge-report.md` 位于 `.gitignore` 的 `/state/` 忽略路径下，按 handoff 要求以 `git add -f` 纳入唯一证据提交。

### 16.3 Verdict 与待决项去向

| 项 | 内容 | 去向 | 是否由本次合并关闭 |
|---|---|---|---|
| ACCEPT-001 Verdict | **`READY_FOR_USER_ACCEPTANCE`（有条件）**：代码级证据完整，可开始用户验收；用户验收（U-01..U-12 / BLK-01..08）未执行，**不得**写成产品验收或 release PASS | G-017 acceptance 由 Orchestrator 判定；§6.2 六个条件 | **否** |
| `GAP-AC-01` | FR-HOME-001 未显示局域网 IP（`GatewayStatus` 无 IP 字段） | 用户书面接受为 v1 简化，或派发 bounded fix（`implementation-engineer`，补 host 断言） | **否**（需用户决定） |
| `GAP-AC-02` | FR-HOME-001 多家庭切换未实现首页弹窗，改为跳转家庭管理页 | 用户书面接受跳转式切换，或派发 `bindSheet` bounded fix（UI/implementation） | **否**（需用户决定） |
| `GAP-AC-03` | FR-ROOM-001 房间图标未提供设置/展示（服务层支持 `icon?`，页面未接线/未展示） | 用户书面接受为 v1 简化，或派发图标选择/展示 bounded fix，补 UI/source 守卫 | **否**（需用户决定） |
| `D-AC-01` | README 基线/分层数字过期（`13dc839`、209 files/13 D-12/17 port/10 used；结构未列 `contracts/**`） | documentation 阶段：`technical-writer` 按 TEST-002/G-016 数字统一 | **否**（文档任务） |
| `D-AC-02` | README/维护计划/G-014 仍写“596 条 `PENDING_REVIEW`” | documentation：`technical-writer` + `test-engineer` 改为 6 PENDING / 544 OBSOLETE / 46 MIGRATED / 10 ACCEPTED 口径 | **否**（文档任务） |
| `D-AC-03` | 维护计划仍称端口迁移未开始、13 D-12/17 端口例外 | documentation：`technical-writer` + `solution-architect` 同步 A1/T-23 结果（6 D-12 accepted、16/17 端口关闭、PORT-LOC-01 OPEN） | **否**（文档任务） |
| `D-AC-04` | TEST-REPORT-001 历史计数与 `contracts/**` 表述过期（`T09_C11_*` 16 vs 15、`T16_Scene_*` 8 vs 7） | documentation/维护轮：`test-engineer` 加注“历史 @ `4f7c26b`，已被 TEST-002 取代”，不改写历史结论 | **否**（文档任务） |
| `D-AC-05` | G-013/G-014 文本仍含旧端口/i18n 数字 | Orchestrator 在 G-017 记录“历史 Gate 数字以 G-015/G-016 为准”；不回改旧 Gate | **否**（Gate 记录任务） |
| `D-AC-06` | `RR-03`：T-23 实现报告文首/§7.2 与 §10 状态不一致 | documentation：`technical-writer` + `solution-architect` | **否**（文档任务） |
| `D-AC-07` | PRD/数据模型与 CB/ADR 差异（邀请码、stateSource、AC mode、GCM 等） | `solution-architect` 走 P-09/P-14/E-06/E-09/E-10/E-11 勘误提案；`input/` 冻结不改 | **否**（后续提案） |
| `D-AC-08` | README ACK p95 仍写 0.598/0.589 ms | documentation：`technical-writer` 统一为 `MOCK_ONLY` 且数值随环境波动、不作验收 | **否**（文档任务） |

补充：`OBS-AC-01`（`ContinuousGestureGuard` 未接线）、`OBS-AC-02`（设计系统未使用组件 / `MdnsDiscoveryTransport` 未接线）为维护观察项，仍按 ACCEPT-001 §4.3 保留；`PORT-LOC-01`、`D-030/GAP-T18-01`、`R4-01` 等既有风险状态不因本次合并改变。

### 16.4 边界声明

1. 本记录只证明上述 1 个源提交已以 `--no-ff` 合并入 `feat/yaocore-app`，并在合并结果上重新执行了 §16.2 的三项检查；不构成 G-017、Component Quality、用户验收、产品验收、设备验收或 release PASS。
2. 合并与验证均在本地完成：未 fetch/pull、未 push、未 rebase、未改写任何已评审提交；未切换分支；`task/wp-108-acceptance` 仍保留。
3. 合并后证据更新与报告提交见 `state/reports/wp-109-merge-report.md`；handoff 为 `state/handoffs/wp-109-merge-acceptance.json`。证据提交为仅含两份 deliverable 的 `docs(repo): 记录 ACCEPT-001 合并证据`。

---

## 17. documentation 收尾（2026-10-18，wp-110）

> 本节由 `technical-writer` 在 `wp-110-documentation` 中追加，记录 G-018 documentation 阶段的最终 revision、Gate 结论、文档同步与残余。§1–§16 的历史结论仍针对各自标注的 revision，本节不回溯改写；**本节不宣告 G-018 PASS、用户验收、产品验收或 release PASS**，G-018 由 Orchestrator 判定。

### 17.1 Revision 与阶段结论

| 项 | 值 |
|---|---|
| 文档任务 | `wp-110-documentation`（task 分支 `task/wp-110-documentation`，父分支 `feat/yaocore-app`） |
| 文档基线 | `422c687`（G-017 acceptance Stage Gate PASS） |
| 最终集成候选 | `feat/yaocore-app @ 4faf3e3`（G-017 输入；ACCEPT-001 合并后） |
| 产品代码基线 | `e74a181`（TEST-002）；`git diff e74a181..4faf3e3 -- entry/src/main tools entry/src/test entry/src/ohosTest` 为空 |
| G-015 review | **PASS_WITH_ACCEPTED_RISKS** @ `09e1b46` |
| G-016 testing | **PASS_WITH_ACCEPTED_RISKS** @ `1cccec5`；TEST-002 @ `e74a181` |
| G-017 acceptance | **PASS_WITH_ACCEPTED_RISKS（acceptance readiness）** @ `4faf3e3`；用户验收未完成 |
| G-018 documentation | 文档同步完成；**待 Orchestrator 判定** |

### 17.2 本轮文档同步

| 文件 | 变更 | 对应输入 |
|---|---|---|
| `README.md` | v1.1：阶段状态（review/testing/acceptance readiness PASS；documentation 完成）、221 files / 0 violation / 6 D-12 / 1 port exception / fixture 27、i18n triage 新口径、PORT-LOC-01 OPEN、`MOCK_ONLY` 性能口径、`no_proxy` 仿真器命令、`contracts/**` 仓库结构 | D-AC-01/02/03/08；TEST-002；G-015..G-017 |
| `artifacts/80-maintenance/maintenance-plan.md` | v1.1：§3.2 P1-P3 完成 / PORT-LOC-01 OPEN；§3.3 D-12 6 active / 7 retired；§3.4 triage 完成与残余；§5.1 RA-03/RA-04 当前状态；追加 §8 收尾记录 | D-AC-02/03；T-23；TEST-002 |
| `artifacts/60-testing/test-report.md` | 追加历史注记；`T09_C11_*` / `T16_Scene_*` 由 16/8 勘误为 15/7；D-03 / D-12 历史快照注记；末尾指向 TEST-002 | D-AC-04 |
| `artifacts/50-implementation/t23-ports-migration.md` | 文首/文末“文档勘误（agent:technical-writer，wp-110）”：标题、§1、§5.2、§5.3、§6、§7.2 与 §10 状态对齐；保留原 Producer 与 §10 | D-AC-06 / RR-03 |
| `artifacts/90-integration/integration-report.md` | 追加本节；不改写 §1–§16 | G-018 收尾 |

### 17.3 本轮实际复跑（cwd = 仓库根）

| # | 命令 | 实测结果 | Exit |
|---|---|---|---|
| 1 | `PYTHONDONTWRITEBYTECODE=1 entry/src/test/run-host-tests.sh` | `1..697`；tests 697 / pass 697 / fail 0 / skipped 0；≈3326.4 ms | 0 |
| 2 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py` | 66 `[PASS]` / 0 `[FAIL]`；14 条既有 `FINDING`；`hard checks: ALL PASS` | 0 |
| 3 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | `files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0`；`PASS` | 0 |
| 4 | `PYTHONDONTWRITEBYTECODE=1 python3 entry/src/test/i18n/check_i18n.py --strict-ui` | CHK-01..09 全 PASS；`blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16` | 0 |
| 5 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/i18n/triage_legacy.py --check` | `615 rows`；`OK: CSV matches computed triage; invariants pass` | 0 |
| 6 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/test_check_layering.py` | `Ran 27 tests ... OK` | 0 |
| 7 | `no_proxy=127.0.0.1,localhost NO_PROXY=127.0.0.1,localhost PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tools.simulator.test_gateway_contract -v` | `Ran 20 tests ... OK`（HTTP + TLS） | 0 |

> 构建 / lint 未在 documentation 阶段重跑；引用 TEST-002 @ `e74a181` 的 `BUILD SUCCESSFUL` 与 `codelinter 0 error / 25 warning`。产品代码自 `e74a181` 至 `4faf3e3` 未变，该证据适用。

### 17.4 最终状态与残余

| 项 | 状态 | 证据 / 去向 |
|---|---|---|
| 端口位置 | **16/17 CLOSED；PORT-LOC-01 OPEN**（`ClockPort`/`IdPort` 在 `common/types/Ports.ets`） | DES-A §27.6.4；维护计划 §3.2 |
| D-12 | **6 active / 7 retired**；`exceptions_used=6`、`unused_exceptions=[]` | DES-B §18.1；T-23 F-07 |
| i18n | **615 行一致**：10 ACCEPTED / 46 MIGRATED / 6 PENDING / 0 INLINE / 544 OBSOLETE_LEGACY；11 B / 6 C / 3 D 残余 | TEST-002；维护计划 §3.4 |
| 测试 / 构建 | Host 697/697；crosscheck 66/66；layering 0 violation；fixture 27/27；i18n 0 blocking；simulator 20/20；build/lint 引用 TEST-002 | 本节 §17.3；TEST-002 |
| FR / NFR | 26 FR：24 COVERED / 2 PARTIAL / 0 GAP；NFR 4.1/4.2/4.3 均 PARTIAL | ACCEPT-001 §2 |
| UI 偏离 | GAP-AC-01..03 待用户接受或 bounded fix | ACCEPT-001 §4.3 |
| 设备 / 真实环境 | BLOCKED / UNAVAILABLE；用户验收未执行 | BLK-01..08；维护计划 §4 |
| 风险接受 | D-030/RA-01、R4-01、P-HMAC、PB-01/02、PORT-LOC-01、i18n 残余均登记 | G-014/G-015/G-016/G-017；维护计划 §5 |
| 构建产物 | 未签名；不可安装 / 发布 | `signingConfigs: []` |
| release | **未授权** | 需用户签名 / 推送 / PR/MR / main 合并决策 |

### 17.5 边界声明

1. 本节只证明 documentation 文档同步与本轮复跑结果；不构成 G-018、用户验收、产品验收、设备验收或 release PASS。
2. 未修改产品代码、测试断言、工具、构建配置、契约或 `input/`；未改写 §1–§16 的历史 Gate/数字。
3. 未执行设备 / 真实 BLE / LAN / TLS / 云 / 视觉 / A11y / fps；相关项继续 `BLOCKED` / `UNAVAILABLE`。
4. 历史 Gate（G-013/G-014）与历史报告（TEST-REPORT-001、T-23 原始段落）保留原文；当前数字以 G-015/G-016/G-017、TEST-002 与本节为准。

---

## 18. documentation 合并记录（2026-10-18，wp-111）

> 本节由 `repository-manager` 在合并任务 `wp-111-merge-docs` 中追加，记录 `task/wp-110-documentation` → `feat/yaocore-app` 的本地合并与合并后复验。§17 是 `technical-writer` 的 documentation 收尾内容；本节只记录该内容已进入集成分支并重新执行检查，**不新增裁定、不宣告 G-018、用户验收、产品验收、设备验收或 release PASS**。

### 18.1 分支、合并与源提交

| 项 | 值 |
|---|---|
| 源分支 | `task/wp-110-documentation` @ `83beda0ce343a3ca16f48e39482dda865dfe388c`（= handoff `source_commit`） |
| 目标分支 | `feat/yaocore-app` @ `422c687de68b39a203cd3a868cdb85cb29a71a81`（合并前 = handoff `base_commit`；G-017 acceptance Stage Gate PASS） |
| 合并基 | `422c687`（目标 tip 为来源 tip 的直接祖先，无分叉） |
| 合并策略 | `git merge --no-ff`（`ort`，无冲突；未手工编辑冲突文件） |
| 合并提交 | `6dc380876e6dedf97ca93a59d9d69e9191976d46`（`chore(merge): 合并 documentation 文档收尾`） |
| 父提交 | `422c687`（目标，第一父）+ `83beda0`（来源，第二父） |
| 结果树 | 与来源 tip 一致：`git diff --quiet 6dc3808 83beda0` 退出 0 |
| 合并范围 | 6 个路径（+308 / −110）：`README.md`、`artifacts/50-implementation/t23-ports-migration.md`、`artifacts/60-testing/test-report.md`、`artifacts/60-testing/testing-stage-report.md`、`artifacts/80-maintenance/maintenance-plan.md`、`artifacts/90-integration/integration-report.md`；全部落在 handoff `writes` 内；未改 `input/`、产品代码、测试断言、工具、契约或构建配置 |

源提交（`422c687..83beda0`，1 个）：

| # | Commit | Subject |
|---|---|---|
| 1 | `83beda0ce343a3ca16f48e39482dda865dfe388c` | docs(stage): 同步 README 与维护/测试/集成报告 |

门禁证据：`README.md`（来源分支 blob sha256 `c73f8c0f01e06fae2023b68055c025c86205c74f6a7c9729c3532de1cc532acb` = handoff `gate_evidence_path_sha256`）。该文件是 documentation 阶段的 Gate 输入之一，**不是独立审查报告**；本节不据此宣告 Gate PASS。

### 18.2 合并后验证矩阵（在 `6dc3808` 上实际执行，早于任何证据改动）

| # | 检查 | 命令 | 实测结果 | 退出码 |
|---|---|---|---|---|
| 1 | Host 测试 | `PYTHONDONTWRITEBYTECODE=1 entry/src/test/run-host-tests.sh` | **697/697 PASS**：`1..697`、`# tests 697 / # pass 697 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`；`duration_ms 3288.402978` | 0 |
| 2 | 协议资产交叉校验 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py` | **`hard checks: ALL PASS`**：66 条 `[PASS]` / 0 条 `[FAIL]`；14 条既有 frozen-input `FINDING`（非阻塞） | 0 |
| 3 | 分层检查 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | **PASS**：`files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0` | 0 |
| 4 | i18n strict-ui | `PYTHONDONTWRITEBYTECODE=1 python3 entry/src/test/i18n/check_i18n.py --strict-ui` | **CHK-01..09 PASS**；`blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16` | 0 |
| 5 | i18n triage 一致性 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/i18n/triage_legacy.py --check` | `615 rows`；`OK: CSV matches computed triage; invariants pass` | 0 |

补充：五项检查均在合并提交的干净工作树上运行，与 §17.3 的 documentation 阶段复跑结果一致（host 697/697、crosscheck 66/66、layering `files=221 / 0 violation`、i18n 0 blocking、triage 615 行一致）。命令统一设置 `PYTHONDONTWRITEBYTECODE=1`；运行后 `git status --porcelain` 无输出，`__pycache__` 已在证据提交前清理。完整日志暂存于 `/tmp/opencode/wp111/`（未提交）。构建 / lint 未在本次合并中重跑，仍引用 TEST-002 @ `e74a181` 的 `BUILD SUCCESSFUL` 与 `codelinter 0 error / 25 warning`。

### 18.3 G-018 documentation 同步范围

| 文件 | 来源变更 | 对应输入 |
|---|---|---|
| `README.md` | v1.1：阶段状态、221 files / 0 violation / 6 D-12 / 1 port exception / fixture 27、i18n triage 新口径、`PORT-LOC-01` OPEN、`MOCK_ONLY` 性能口径、`no_proxy` 仿真器命令、`contracts/**` 仓库结构 | D-AC-01/02/03/08；TEST-002；G-015..G-017 |
| `artifacts/80-maintenance/maintenance-plan.md` | v1.1：§3.2 P1-P3 完成 / `PORT-LOC-01` OPEN；§3.3 D-12 6 active / 7 retired；§3.4 triage 完成与残余；§5.1 RA-03/RA-04 当前状态；追加 §8 收尾记录 | D-AC-02/03；T-23；TEST-002 |
| `artifacts/60-testing/test-report.md` | 追加历史注记；`T09_C11_*` / `T16_Scene_*` 由 16/8 勘误为 15/7；D-03 / D-12 历史快照注记；末尾指向 TEST-002 | D-AC-04 |
| `artifacts/60-testing/testing-stage-report.md` | 追加文档注记：测试证据仍针对 `e74a181`；README 旧口径 596 条已在 documentation 阶段关闭 | wp-110 文档同步 |
| `artifacts/50-implementation/t23-ports-migration.md` | 文首/文末“文档勘误（agent:technical-writer，wp-110）”：标题、§1、§5.2、§5.3、§6、§7.2 与 §10 状态对齐；保留原 Producer 与 §10 | D-AC-06 / RR-03 |
| `artifacts/90-integration/integration-report.md` | 追加 §17（documentation 收尾）；不改写 §1–§16 | G-018 收尾 |

范围声明：上述提交只改文档与报告；`git diff 422c687 6dc3808 -- entry/src tools contracts input` 为空（产品代码、测试、工具、契约与 `input/` 未变）。

### 18.4 残余与去向

| 项 | 状态 | 去向 |
|---|---|---|
| G-018 documentation | 文档同步完成并已合并；**待 Orchestrator 判定** | G-018 Gate 记录 |
| i18n 残余 | 615 行一致：10 ACCEPTED / 46 MIGRATED / 6 PENDING_REVIEW / 0 INLINE / 544 OBSOLETE_LEGACY；另 11 B / 6 C / 3 D 待处理；分类有证据不等于业务语义已签署 | 维护计划 §3.4；后续维护轮 |
| 端口位置 | **16/17 CLOSED；`PORT-LOC-01` OPEN**（`ClockPort`/`IdPort` 仍在 `common/types/Ports.ets`）；0 violation 不代表端口位置完全合规 | DES-A §27.6.4；维护计划 §3.2 |
| D-12 | **6 active / 7 retired**；`exceptions_used=6`、`unused_exceptions=[]` | DES-B §18.1；T-23 F-07 |
| UI 偏离 | `GAP-AC-01..03` 待用户书面接受或 bounded fix | ACCEPT-001 §4.3 |
| 用户 / 设备验收 | 用户验收未执行；设备/真实 BLE/LAN/TLS/云/视觉/fps 仍 `BLOCKED` / `UNAVAILABLE`；ACK p95 仅 `MOCK_ONLY` | BLK-01..08；维护计划 §4 |
| 构建 / 发布 | unsigned HAP；`signingConfigs: []`；release 未授权 | 需用户签名 / 推送 / PR/MR / main 合并决策 |

### 18.5 工作树与边界声明

1. 本记录只证明上述 1 个源提交已以 `--no-ff` 合并入 `feat/yaocore-app`，并在合并结果上重新执行了 §18.2 的五项检查；不构成 G-018、Component Quality、独立评审、用户验收、产品验收、设备验收或 release PASS。
2. 合并与验证均在本地完成：按任务“仅本地”要求未 fetch、未 pull、未 push、未 rebase，未改写任何已评审提交；未切换分支；`task/wp-110-documentation` 仍保留。
3. 合并后证据更新与报告提交见 `state/reports/wp-111-merge-report.md`；handoff 为 `state/handoffs/wp-111-merge-docs.json`。证据提交为仅含两份 deliverable 的 `docs(repo): 记录 documentation 合并证据`。

---

## 19. release 准备计划合并记录（2026-10-18，wp-113）

> 本节由 `repository-manager` 在合并任务 `wp-113-merge-release-plan` 中追加，记录 `task/wp-112-release-plan` → `feat/yaocore-app` 的本地合并与合并后复验。目的是把 RELEASE-001 发布准备计划与发布检查单纳入集成分支，并留下可追溯的合并证据。**本节不构成发布授权、部署授权、签名授权、用户验收或 release Gate PASS。**

### 19.1 分支、合并与源提交

| 项 | 值 |
|---|---|
| 源分支 | `task/wp-112-release-plan` @ `560d08a9e76ac949c0a00b51500fcedee137958b`（= handoff `source_commit`） |
| 目标分支 | `feat/yaocore-app` @ `6cd9a88d0fdc1b08cc6ffca233c12c41df737519`（合并前 = handoff `base_commit`；`chore(release): 目标扩展至 release 准备（不发布）`） |
| 合并基 | `6cd9a88`（目标 tip 为来源 tip 的直接祖先，无分叉） |
| 合并策略 | `git merge --no-ff`（`ort`，无冲突；未手工编辑冲突文件） |
| 合并提交 | `40fe2a8895aa80fb4ef2191fdd973e3da3d5e1f1`（`chore(merge): 合并 release 准备计划与检查单`） |
| 父提交 | `6cd9a88`（目标，第一父）+ `560d08a`（来源，第二父） |
| 结果树 | 与来源 tip 一致：`git diff --quiet 40fe2a8 560d08a` 退出 0 |
| 合并范围 | 2 个路径（+780 / −3）：`artifacts/85-release/release-plan.md`（+476/−3）、`docs/release-checklist.md`（新建，307 行）；全部落在 handoff `writes` 内；未改 `input/`、产品代码、测试断言、工具、契约或构建配置 |

源提交（`6cd9a88..560d08a`，1 个）：

| # | Commit | Subject |
|---|---|---|
| 1 | `560d08a9e76ac949c0a00b51500fcedee137958b` | docs(release): 发布就绪评估与检查单 |

门禁证据：`artifacts/85-release/release-plan.md`（合并后 blob sha256 `3e2cd6158216f58d2a84cad9bc1bb2e87a9c84c29aee3252c58399bc02756411` = handoff `gate_evidence_path_sha256`）。该文件是 RELEASE-001 的发布准备评估，**不是发布批准或独立审查报告**；本节不据此宣告 release Gate PASS。

### 19.2 合并后验证矩阵（在 `40fe2a8` 上实际执行，早于任何证据改动）

| # | 检查 | 命令 | 实测结果 | 退出码 |
|---|---|---|---|---|
| 1 | Host 测试 | `PYTHONDONTWRITEBYTECODE=1 entry/src/test/run-host-tests.sh` | **697/697 PASS**：`1..697`、`# tests 697 / # pass 697 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`；`duration_ms 3604.514874` | 0 |
| 2 | 协议资产交叉校验 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py` | **`hard checks: ALL PASS`**：66 条 `[PASS]` / 0 条 `[FAIL]`；14 条既有 frozen-input `FINDING`（非阻塞） | 0 |
| 3 | 分层检查 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | **PASS**：`files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0` | 0 |

补充：三项检查均在 `40fe2a8` 的干净工作树上运行，与 documentation 合并（§18.2）及 TEST-002 的基线一致（host 697/697、crosscheck 66/66、layering `files=221 / 0 violation`）。命令统一设置 `PYTHONDONTWRITEBYTECODE=1`；运行后已清理 `__pycache__`；完整日志暂存于 `/tmp/opencode/wp113/`（未提交）。构建 / lint 未在本次合并中重跑，仍引用 TEST-002 @ `e74a181` 的 `BUILD SUCCESSFUL` 与 `codelinter 0 error / 25 warning`。

### 19.3 交付物与内容检查

| 文件 | 合并后状态 | 说明 |
|---|---|---|
| `artifacts/85-release/release-plan.md` | 474 行；完整章节与评估 | RELEASE-001；Producer `agent:release-engineer`；sha256 与 handoff 门禁证据一致 |
| `docs/release-checklist.md` | 307 行；新建 | 发布检查单，含检查项、命令与责任角色；非占位内容 |

`docs/` 受 `.gitignore` 忽略，但来源分支已以 `-f` 提交该检查单，合并后仍为已跟踪文件（`git ls-files docs/release-checklist.md` 可验证）。两份交付物中出现的 `TODO` 均为对既有 README 许可证占位的事实描述（B-01），不是本次交付物的未完成占位。

### 19.4 RELEASE-001 裁定与阻塞项（摘要，权威文本在 release-plan.md）

RELEASE-001 的 Release Verdict 为 **`NOT_READY`**（不满足发布授权条件）。以下 8 项阻塞在合并时点全部 **未关闭**；任一项未关闭即不得进入发布授权或市场/远端发布：

| # | 阻塞项 | 摘要 |
|---|---|---|
| B-01 | 项目级许可证未定 | 无 `LICENSE`；README 仍为 TODO；不得假定可再分发 |
| B-02 | 无签名配置，HAP 不可安装 | `signingConfigs: []`；构建跳过签名；产物未签名 |
| B-03 | 设备/用户验收未执行 | ACCEPT-001 U-01..U-12 均 NOT RUN/BLOCKED；无 `hdc` target |
| B-04 | GAP-AC-01..03 未决 | LAN IP 显示、多家庭切换交互、房间图标接线未决 |
| B-05 | 远端/发布通道未授权 | 未 push；无 tag；远端策略与保护分支/CI 未就绪 |
| B-06 | 发布标识/版本/构建模式未冻结 | bundleName/vendor/version 待确认；未签名产物为 `buildMode=debug` |
| B-07 | CHANGELOG/Release Notes 缺失 | 无 `CHANGELOG.md` 与正式 release notes |
| B-08 | 残余风险未逐项书面确认 | PORT-LOC-01、i18n 残余、设备 BLOCKED、ACK p95 `MOCK_ONLY`、NFR partial、lint/覆盖率缺口等 |

### 19.5 未授权边界与工作树声明

1. 本任务**仅本地合并**：未 fetch、未 pull、未 push、未创建 PR/MR、未创建 tag、未签名、未执行任何市场或远端发布写操作；`task/wp-112-release-plan` 分支保留，未切换分支。
2. 合并未改写任何已评审提交；合并提交新增的只有两份 release 准备交付物。
3. 本节只证明 1 个源提交已以 `--no-ff` 合并入 `feat/yaocore-app`，并在合并结果上重新执行了 §19.2 的三项检查；不构成独立评审、release Gate PASS、发布授权、部署授权、签名授权或用户验收。发布相关裁定仍归 Orchestrator / 用户。
4. 合并后证据更新与报告提交见 `state/reports/wp-113-merge-report.md`；handoff 为 `state/handoffs/wp-113-merge-release-plan.json`。证据提交为仅含两份 deliverable 的 `docs(repo): 记录 release 准备合并证据`。

---

## 20. Release 文档合并记录（2026-10-18，wp-120）

> 本节由 `repository-manager` 在合并任务 `wp-120-merge-release-notes` 中追加，记录 `task/wp-118-release-consistency` → `feat/yaocore-app` 的本地合并与合并后复验。目的是把 v1.0.0 CHANGELOG、Release Notes、RELEASE-001 修正、发布检查单与复审/复评报告纳入集成分支，并留下可追溯的合并证据。**本节不构成发布授权、部署授权、签名授权、tag 授权、用户验收或 release Gate PASS。**

### 20.1 分支、合并与源提交

| 项 | 值 |
|---|---|
| 源分支 | `task/wp-118-release-consistency` @ `1e955a8d7f4fa8890c195f7097e7ee215104fe7e`（= handoff `source_commit`） |
| 目标分支 | `feat/yaocore-app` @ `b716207eee7ac07fe3b08edba9f9e193cb38f2c8`（合并前 = handoff `base_commit`；`docs(repo): 记录 release 准备合并证据`） |
| 合并基 | `b716207`（目标 tip 为来源 tip 的直接祖先，无分叉） |
| 合并策略 | `git merge --no-ff`（`ort`，无冲突；未手工编辑冲突文件） |
| 合并提交 | `21c601d5234b1e313c811fb395140a09b5dd06d7`（`chore(merge): 合并 release 发布说明与修正`） |
| 父提交 | `b716207`（目标，第一父）+ `1e955a8`（来源，第二父） |
| 结果树 | 与来源 tip 一致：`git diff --quiet 21c601d 1e955a8` 退出 0 |
| 合并范围 | 7 个路径（+1258 / −112）：`CHANGELOG.md`（+128/−0）、`README.md`（+29/−3）、`artifacts/70-review/t26-release-review.md`（+402/−0）、`artifacts/70-review/t26-release-rereview.md`（+276/−0）、`artifacts/85-release/release-plan.md`（+150/−62）、`docs/release-checklist.md`（+52/−47）、`docs/release-notes-v1.0.0.md`（+221/−0）；全部落在 handoff `writes` 内；未改 `input/`、产品代码、测试断言、工具、契约或构建配置 |

源提交（`b716207..1e955a8`，6 个，与任务 handoff 一致）：

| # | Commit | Subject |
|---|---|---|
| 1 | `63d2235` | docs(release): 添加 CHANGELOG 与 v1.0.0 发布说明 |
| 2 | `f1fbe0d` | docs(review): Release 准备资产独立复审 |
| 3 | `972f177` | docs(release): 修正发布计划与检查单（F-01..F-06） |
| 4 | `19df893` | docs(release): 同步发布说明 B-09 与身份分析 |
| 5 | `3501f5e` | docs(release): 统一发布文档交叉引用 |
| 6 | `1e955a8` | docs(review): Release 修正聚焦复评 |

门禁证据：`artifacts/70-review/t26-release-rereview.md`（来源分支 blob sha256 `f4ed5a80a74df61c611bfab5a77407d773cf2fd08f85ca4fed59c2e8dc9cc476` = handoff `gate_evidence_path_sha256`；合并后文件字节一致）。该文件是 `3501f5e` 的聚焦复评报告，**不是发布批准**；本节不据此宣告 release Gate PASS。

### 20.2 合并后验证矩阵（在 `21c601d` 上实际执行，早于任何证据改动）

| # | 检查 | 命令 | 实测结果 | 退出码 |
|---|---|---|---|---|
| 1 | Host 测试 | `PYTHONDONTWRITEBYTECODE=1 entry/src/test/run-host-tests.sh` | **697/697 PASS**：`1..697`、`# tests 697 / # pass 697 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`；`duration_ms 3516.551613` | 0 |
| 2 | 协议资产交叉校验 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py` | **`hard checks: ALL PASS`**：66 条 `[PASS]` / 0 条 `[FAIL]`；14 条既有 frozen-input `FINDING`（非阻塞） | 0 |
| 3 | 分层检查 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | **PASS**：`files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0` | 0 |

补充：三项检查均在合并提交的干净工作树上运行；命令统一设置 `PYTHONDONTWRITEBYTECODE=1`；运行后 `git status --porcelain` 无输出，`__pycache__` 已在证据提交前清理；完整日志暂存于 `/tmp/opencode/wp120/`（未提交）。构建 / lint 未在本次合并中重跑，仍引用 TEST-002 @ `e74a181` 的 `BUILD SUCCESSFUL` 与 `codelinter 0 error / 25 warning`。合并未改变产品代码/构建配置：`git diff --stat b716207..21c601d -- entry/src tools contracts input build-profile.json5 AppScope/app.json5 oh-package.json5 entry/oh-package.json5 hvigorfile.ts` 为空。

### 20.3 交付物存在性与内容检查

| 文件 | 合并后状态 | sha256（合并后） | 说明 |
|---|---|---|---|
| `CHANGELOG.md` | 128 行；新建 | `d96d6df572f8b7d1cf3fc8414aae3d9f45abf12a3eb3c13f13a63d6a042a299d` | `Status: DRAFT`；`[1.0.0]` 明示为发布准备基线，不是发布记录 |
| `docs/release-notes-v1.0.0.md` | 221 行；新建 | `4fdf237325dc6f336d9fad3f5548cedc3b71eafdfd30fa14e2ec8cb585b0467a` | `DRAFT / NOT_READY`；含 §1.1 公开旧版本身份/版本/许可证待决 |
| `artifacts/85-release/release-plan.md` | 562 行 | `ea38c7ccf1fe3642b255a67103fc4e172fea6c977964795fbe65d91103b93dfc` | RELEASE-001；`Release Verdict: NOT_READY`；F-01..F-06 修订完成 |
| `docs/release-checklist.md` | 312 行 | `b8a36d5366ffb890746575d019a616191232d3a0ca2e7d3333d1e5260dca004f` | RELEASE-CHECKLIST-001 v1.1；`Current verdict: NOT_READY` |

占位扫描：`TODO` 仅出现在“许可证仍为 TODO / README 标 TODO”的**事实描述**（B-01），不是上述交付物的未完成占位；未发现 `TBD`、`FIXME`、`待填写` 或 Lorem 占位。越界表述扫描：未发现肯定式“已发布 / 已推送 / 已签名 / 已上架 / 生产就绪 / 可安装 / 可发布”等声明；命中均为否定、禁止、条件或状态要求语境（如 `## [Unreleased]`、“没有正式发布渠道”、“正式发布前必须…”）。`docs/` 受 `.gitignore` 忽略，但两个 `docs/release-*` 文件仍为已跟踪文件（`git ls-files` 可验证）。

### 20.4 复评 PASS 的范围

`artifacts/70-review/t26-release-rereview.md`（T26-RELEASE-REREVIEW，Producer `agent:quality-reviewer`）的 `PASS` 只覆盖 **`3501f5e` 的发布准备文档修正**：

- F-01..F-06 核心闭环（公开旧版本事实、A/B/C 选项、B-07 状态、证据基线 vs 最终 revision、B-09、1.2.4/1.10.3、P1/P2 阈值提案）；
- B-01..B-09 在 RELEASE-001、检查单、release notes 中编号连续、状态一致；5 个文档 53 条相对链接 0 broken；无越界肯定声明；
- 回归复验 host 697/697、layering 221/0/6、crosscheck 66/66 hard ALL PASS、仿真器 20/20、fixture 27/27、i18n 0 blocking/0 missing、triage 615 行一致；
- 非阻塞观察 O-01..O-04（README“开源”措辞、`972f177` pin、§4.1 候选措辞、§11.5 扫描措辞）保留待后续维护轮。

**范围限制**：复评未重新 clean build、未重跑 codelinter、未做设备/签名/远端/用户验收，也未做法律级许可证审计。源 tip `1e955a8` 相对 `3501f5e` 只新增该复评报告本身；被审文档字节未变（`git diff --quiet 3501f5e 1e955a8 -- CHANGELOG.md README.md docs/ artifacts/85-release/` 退出 0）。该 `PASS` **不是 release 批准**；`NOT_READY` 未被改变。

### 20.5 B-01..B-09 与发布未授权边界

合并时点 **B-01..B-09 全部未关闭**（B-07 仅“草案已产出 @ `63d2235`，待评审/签核”的部分进展）：

| # | 阻塞项 | 当前状态 |
|---|---|---|
| B-01 | 项目级许可证未定（公开旧版本 Apache-2.0 + NOTICE 关系未裁定） | 待用户 A/B/C 决定 |
| B-02 | 无签名配置，未签名 HAP 不可安装 | 阻塞 |
| B-03 | 设备/用户验收未执行（U-01..U-12、BLK-01..08） | 阻塞 |
| B-04 | GAP-AC-01..03 未决 | 待用户接受或 bounded fix |
| B-05 | 远端/发布通道未授权 | 阻塞 |
| B-06 | 发布标识/版本/构建模式未冻结 | 待 A/B/C 决定 |
| B-07 | CHANGELOG / Release Notes 已产出草案 | 部分进展；待评审/签核，不得写成已定稿 |
| B-08 | 残余风险未逐项书面确认 | 阻塞 |
| B-09 | 构建硬化 / API 14 运行时兼容未决 | 阻塞 |

未授权边界（本任务严格遵守）：

1. **仅本地合并**：未 fetch、未 pull、未 push、未创建 PR/MR、未创建或删除 tag、未签名、未安装、未执行任何应用市场或远端发布写操作。
2. 未切换分支；`task/wp-118-release-consistency` 分支保留，未删除、未移动；未改动任何已评审提交。
3. 合并与验证结果只证明 6 个源提交已以 `--no-ff` 进入 `feat/yaocore-app`，并在合并结果上重跑三项检查；**不构成 release Gate PASS、独立评审、发布授权、部署授权、签名授权、tag 授权或用户验收**。
4. Release 仍为 `NOT_READY`；最终 release revision/tag 未冻结。发布相关裁定归 Orchestrator / 用户。

### 20.6 证据与工作树声明

1. 合并后证据更新与报告提交见 `state/reports/wp-120-merge-report.md`；handoff 为 `state/handoffs/wp-120-merge-release-notes.json`。证据提交为仅含两份 deliverable 的 `docs(repo): 记录 release 文档合并证据`。
2. 本节只记录合并事实与实测证据；不改写 §1–§19 的历史结论。
