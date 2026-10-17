# TEST-001 测试计划与可执行测试骨架

- **Artifact ID**: TEST-001
- **Producer**: agent:test-engineer
- **Type**: Test Plan / Test Harness Baseline / Measurement Contract
- **Status**: **Accepted @ G-008**（`fa21c67`）；**T-19 执行结果见 §14**（2026-10-18，`wp-082-verify`，不改写 §0..§13 的既有语义）
- **Date**: 2026-10-17
- **Task**: `wp-010-test-plan`（T-05；task 分支 `task/wp-010-test-plan`，父分支 `feat/yaocore-app`，base commit `1c44503e0720c0305ab5d1d0d894af09ea06a009`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`
- **Upstream**:
  - G-004 @ `697762c`：`contract-baseline.md`、ADR-001..004、`project-constraints.md`、`i18n-resource-design.md`
  - G-005 @ `artifacts/30-plan/{delivery-plan,component-graph}.md`
  - G-006/G-007 @ `artifacts/40-detailed-design/des-001a-foundation-transport.md` / `des-001b-domain-presentation.md`
  - WP2 @ `artifacts/10-verification/wp-002-protocol-fixture-validation.md`（§5/§7 向量与移植清单）
  - T-01 @ `artifacts/50-implementation/build-baseline.md`（工具链/命令/限制）
  - 本任务 handoff 冻结的 26 项输入（SHA-256 已由 guard pin 校验）
- **Downstream**: T-06..T-18 组件测试、CQG-T06..T-18、G-010..G-013、T-19 执行报告、T-20 评审、G-014 Stage Gate
- **写范围纪律**: 只写 `artifacts/60-testing/`、`tools/simulator/`、`tools/contract/`、`tools/test-fixtures/`、`entry/src/ohosTest/ets/test/`、`entry/src/test/`；未修改任何产品代码、构建配置或 `input/`。

---

## 0. 摘要与证据分类

| 项 | 当前结果 | 证据 |
|---|---|---|
| Host 纯逻辑测试（Node runner） | **PASS 15/15** | `entry/src/test/evidence/host-node-tests.tap` |
| Hypium host 入口编译 | **PASS（仅编译）** | `entry/src/test/evidence/hvigor-test-default-timeout.log` §UnitTestArkTS |
| `hvigorw test` 实际执行 | **BLOCKED（环境）** | Previewer 缺库 / Linux 不支持；`evidence/previewer-*.log` |
| 设备/模拟器 ohosTest | **BLOCKED（未运行）** | 无 `hdc` target + 未签名；`entry/src/test/evidence/onDeviceTest-blocked.log` |
| 测试 HAP 编译 | **PASS（仅编译）** | `entry/src/test/evidence/ohosTest-assemble.log` |
| 仿真器 HTTP 模式 | **PASS（启动/响应）** | `tools/simulator/evidence/http-*.txt`、`http-server.log` |
| 仿真器 TLS 模式 | **PASS（启动/响应）** | `tools/simulator/evidence/tls-*.txt`、`tls-server.log`、SPKI 行 |
| 网关契约套件 | **PASS 20/20**（原 17 + 3 TLS） | `tools/simulator/evidence/run-test_gateway_contract.txt` |
| 协议 crosscheck | **PASS 66/66**；14 项冻结输入 FINDING | `tools/contract/evidence/run-crosscheck.txt` |
| product-profile（P-15） | **PASS**（2 个此前 ERROR 用例转 PASS） | 同上套件日志；`tools/test-fixtures/iotda/product-profile.json` |
| 静态检查 `codelinter` | **PASS**（`No defects found`） | `entry/src/test/evidence/codelinter.log` |
| NFR 4.3 真实性能 | **UNAVAILABLE** | 无设备/真实 LAN；只有 harness 与口径 |
| UI 渲染/60/120fps/BLE 射频/真实云 | **UNAVAILABLE** | 环境限制，见 §11 |

**分类图例（全文强制）**

| 分类 | 含义 |
|---|---|
| `PASS` | 当前 revision、当前环境实际执行且断言通过 |
| `FAIL_PRODUCT` | 实际执行失败，定位为产品行为/契约不符 |
| `FAIL_TEST` | 实际执行失败，定位为测试缺陷（断言/夹具/脚本） |
| `FAIL_ENV` | 实际执行失败，定位为环境问题（工具链/代理/缺库） |
| `BLOCKED` | 前置条件不满足，未能执行（设备/签名/运行器） |
| `COMPILED_ONLY` | 只编译通过，未执行断言；**不是 PASS** |
| `NOT_RUN` | 计划存在但尚未执行（无阻塞证据或不适用） |
| `UNAVAILABLE` | 当前环境无法获得的证据（真实硬件/性能/视觉） |

> 本计划不把 `COMPILED_ONLY`、`BLOCKED`、`NOT_RUN`、`UNAVAILABLE` 写成 PASS。

---

## 1. 环境、前置条件与数据纪律

### 1.1 环境事实（2026-10-17，继承 T-01 并补充）

| 项 | 实测值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore` |
| OS | `Linux 7.0.0-38-generic x86_64` |
| `hvigorw` | `6.26.8` |
| `ohpm` | `26.0.0.630` |
| `codelinter` | `6.0.240` |
| Node | `v24.15.0`（内置 `node:test`、TypeScript type stripping） |
| Java | OpenJDK `21.0.12.1` |
| Python | `3.12.3`（仅标准库；本任务未安装依赖） |
| OpenSSL | `3.0.13` |
| SDK | HarmonyOS `26.0.0.105`（apiVersion 26） |
| `DEVECO_SDK_HOME` | `/home/quirkybrain/harmonyos/command-line-tools/sdk` |
| `DISPLAY` | `:1`（X.Org 21.1.11；仅影响 Previewer 启动实验） |
| `hdc list targets` | `[Empty]` |
| 模拟器实例 | `[Empty]`；镜像均未下载 |
| 签名 | `build-profile.json5` 的 `signingConfigs: []` |

### 1.2 通用前置

```bash
cd /home/quirkybrain/code/harmony-projects/YaoCore
export DEVECO_SDK_HOME=/home/quirkybrain/harmonyos/command-line-tools/sdk
# 确保 ohpm / hvigorw / codelinter / node / java / python3 在 PATH
export PYTHONDONTWRITEBYTECODE=1   # Python 工具运行时避免生成 __pycache__
```

### 1.3 测试数据与秘密纪律

1. 只使用 `PUBLIC TEST DATA ONLY`：`YaoCore-Contract-Secret-v2`、`0123456789abcdef*` 等公开向量 secret；测试证书/私钥仅用于 localhost。
2. 禁止真实 Wi-Fi 密码、PoP、HMAC secret、云 Token、生产证书、家庭数据进入测试夹具或日志（SC-01..SC-03、SC-06）。
3. `tools/simulator/certs/*.pem` 是 T-05 授权的**测试专用**例外（SC-02），已在 `tools/simulator/certs/README.md` 登记；禁止复用到真实设备/生产 HAP。
4. 日志/断言失败消息不得包含 secret 或完整 canonical 中的敏感值；当前测试只使用公开向量。
5. `input/` 只读；本任务未修改任何冻结输入。

---

## 2. 测试分层、命令与证据

### 2.1 分层总表

| 层 | 范围/路径 | 运行环境 | 命令（cwd=仓库根） | 证据产物 | 当前状态 |
|---|---|---|---|---|---|
| **L0 构建/静态** | ArkTS 产品源码、测试 HAP | 本机 | `hvigorw clean assembleHap --no-daemon`；`codelinter -c code-linter.json5 -p default .`；`hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | 构建日志、lint 日志、unsigned HAP | 构建/lint/测试 HAP **PASS**；HAP 未签名 |
| **L1 Host 纯逻辑** | `entry/src/test/host/**`（Node + 纯 `.ets`/`.mjs`） | 本机，无设备 | `entry/src/test/run-host-tests.sh` | TAP 日志 | **PASS 15/15** |
| **L1b Hypium host** | `entry/src/test/List.test.ets`、`HostBaseline.test.ets` | 本机 `hvigorw test` + Linux Previewer | `hvigorw test --no-daemon` | `UnitTestArkTS` 日志、Previewer 日志 | **COMPILED_ONLY + BLOCKED**（见 §2.3） |
| **L2 协议契约（Python）** | `tools/contract/**` | 本机 Python | `python3 tools/contract/crosscheck_protocol_assets.py` | `run-crosscheck.txt` | **PASS 66/66** |
| **L2b 仿真器契约（Python）** | `tools/simulator/**` | 本机 Python + localhost | `python3 -m unittest tools.simulator.test_gateway_contract -v`；HTTP/TLS CLI | 套件日志、HTTP/TLS 捕获 | **PASS 20/20 + 两种模式实启** |
| **L3 设备/UI（ohosTest）** | `entry/src/ohosTest/**` | 设备/模拟器 + 签名 | `hvigorw --mode module -p module=entry@ohosTest -p product=default onDeviceTest --no-daemon` | 设备测试报告 | **BLOCKED / UNAVAILABLE** |
| **L3 集成（Mock/仿真器）** | T-11/T-12/T-13 起的 Mock + 仿真器 | 本机/设备（未来） | 各任务 CQG 命令 | 集成报告 | `NOT_RUN`（组件未实现） |
| **L4 性能** | ACK p95、55ms 节流、60/120fps | 本机 fake clock / 设备 | `entry/src/test/host/PerfHarness.test.mjs` + 未来计时 harness | 报告 JSON | 口径/harness **PASS**；真实数值 **UNAVAILABLE** |

### 2.2 构建与静态检查命令（复用 T-01）

```bash
# 依赖（首次需要 registry 网络）
ohpm install

# 干净 HAP 构建（未签名）
hvigorw clean assembleHap --no-daemon

# 静态检查（独立 CLI，不是 hvigor task）
codelinter -c code-linter.json5 -p default .

# 测试 HAP 只编译（不等于执行）
hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon
```

当前证据：`entry/src/test/evidence/clean-assemble.log`（主 HAP `BUILD SUCCESSFUL`）、`ohosTest-assemble.log`（测试 HAP `BUILD SUCCESSFUL`，35 tasks）、`codelinter.log`（`No defects found in your code.`）。

> `code-linter.json5` 当前忽略 `src/test/**`、`src/ohosTest/**`（T-01 BL-R06）。测试源码的静态检查策略见 §2.4；在 T-10 增加检查器前，测试源码**没有 lint PASS**。

### 2.3 Host 运行路径：Node runner（已实证）与 `hvigorw test`（阻塞）

#### A. Node runner（本环境唯一已实证的 host 执行路径）

```bash
entry/src/test/run-host-tests.sh
# 等价：
node --no-warnings \
  --import ./entry/src/test/host/register-ets.mjs \
  --test --test-reporter=tap \
  entry/src/test/host/*.test.mjs
```

当前结果：`1..15`、`# pass 15`、`# fail 0`、退出码 0（`entry/src/test/evidence/host-node-tests.tap`）。

机制：

- `entry/src/test/host/ets-hooks.mjs` 注册 ESM loader，把 `.ets`/`.ts` 源码用 `node:module.stripTypeScriptTypes` 去类型后加载；
- `protocol-oracle.ets` 是**测试 oracle**（纯 TS、无 `@ohos`），用于独立复算 canonical；
- 测试只 import 无平台依赖的纯逻辑；UI/平台文件不得进入 host 图。

#### B. `hvigorw test` 的真实状态（不得写成 PASS）

```bash
export DEVECO_SDK_HOME=/home/quirkybrain/harmonyos/command-line-tools/sdk
hvigorw test --no-daemon
```

| 阶段 | 实测 | 分类 |
|---|---|---|
| `GenerateUnitTestTemplate` / `UnitTestArkTS` | **成功**；`entry/src/test/List.test.ets` 已被编译；此前“缺少 List.test”根因消除 | PASS（编译） |
| 启动 SDK Linux Previewer（默认环境） | `./Previewer: error while loading shared libraries: libshared_libz.so: cannot open shared object file` | **BLOCKED / FAIL_ENV** |
| 用 `/tmp` shim 补齐缺库后 | Previewer 启动，但 `[ERROR][JsAppImpl.cpp][RunDebugAbility][451]: JsApp::Run ability start failed.Linux is not supported.`；不生成 `test_result.txt` | **BLOCKED / FAIL_ENV** |
| hvigor 进程 | 等待 Previewer 结果，45s 超时（exit 124） | **BLOCKED** |

根因证据：

- `entry/src/test/evidence/previewer-default-env.log`（缺 `libshared_libz.so`，exit 127）；
- `entry/src/test/evidence/previewer-with-lib-shim.log`（`Linux is not supported`）；
- `entry/src/test/evidence/hvigor-test-default-timeout.log`、`hvigor-test-with-lib-shim.log`（`UnitTestArkTS` 完成后挂起，exit 124）。

结论：`hvigorw test` 在本 Linux 环境**不能执行 Hypium 断言**；这不是测试代码失败。Node runner 是替代路径，覆盖纯逻辑层；平台/UI/设备证据仍为 `BLOCKED`/`UNAVAILABLE`。

### 2.4 测试源码静态检查策略（T-05 定义）

| 项 | 策略 | 当前 |
|---|---|---|
| 产品源码 | `codelinter`（现有配置） | PASS |
| `entry/src/test/**` | 不进入 `code-linter.json5` 范围；Node 测试由 Node 解析 + 断言执行；ArkTS 测试由 `UnitTestArkTS` 编译 | 编译 PASS；无 lint |
| `entry/src/ohosTest/**` | 同上；设备测试 HAP 编译作为语法门禁 | 编译 PASS；无 lint |
| 未来（T-10/T-19） | 由 T-10 增加 `tools/i18n/check_i18n.py`；T-19 可增加独立 `tsc --noEmit`/`codelinter` 测试源码配置（需 build/lint 配置变更，另行授权） | `NOT_RUN` |

> 本任务不修改 `code-linter.json5`（写范围外）。因此“测试源码 lint 通过”不是当前证据。

### 2.5 设备/模拟器测试（BLOCKED）

```bash
hvigorw --mode module -p module=entry@ohosTest -p product=default onDeviceTest --no-daemon
```

当前结果：

- 退出码 `255`，`ErrorCode: 00507013`，`[Fail]ExecuteCommand need connect-key? please confirm a device by help info`；
- `hdc list targets` 为空；无模拟器实例；`signingConfigs: []`；
- 证据：`entry/src/test/evidence/onDeviceTest-blocked.log`；设备引导见 `entry/src/ohosTest/ets/test/README.md`。

设备可用后的必跑项：契约 fixtures、仿真器 HTTP/TLS 闭环、DEV-ONLY 拒收、身份 fail-closed、ACK 三态/门锁时序、i18n 运行时切换、UI smoke。真实硬件/射频/真实云仍由用户执行（CP-03）。

---

## 3. 向量与夹具清单

### 3.1 已落地/可运行夹具

| ID | 夹具/向量 | 源（SHA-256） | 落位 | 用途 | 当前状态 |
|---|---|---|---|---|---|
| V-01 | 控制 HMAC 4 向量 | `input/api/protocol/hmac-sha256-test-vectors.json`（`46b33cda…`） | `entry/src/ohosTest/ets/test/contract/fixtures/`；host 直接读取 | canonical + HMAC + request.sign；4 向量 | **PASS（host 测试内 4 向量）** |
| V-02 | 响应验签向量 | `response-auth-test-vectors.json`（`b41aad4f…`） | 同上 | bodySha256 + response canonical + HMAC | **PASS（host）** |
| V-03 | 发现请求签名向量 | `discovery-request-auth-test-vectors.json`（`be24bded…`） | 同上 | discover canonical + HMAC | **PASS（host）** |
| V-04 | 发现 golden | wp-002 实跑 `discover-response.json`（`31f515d5…`） | 同上 | 顶层/设备字段、`online`、无 `success`、security 常量 | **PASS（host 结构断言）** |
| V-05 | ACK golden | wp-002 实跑 `control-ack.json`（`3593af0d…`） | 同上 | `result_code==0`、`request_id:seq`、`reported_state.online`、无 `success` | **PASS（host）** |
| V-06 | ACK replay golden | wp-002 实跑 `control-ack-replay.json`（`6ce7466c…`） | 同上 | `idempotent_replay:true` 仅增量 | **PASS（host）** |
| V-07 | 仿真器 TLS 证书 | T-05 自签名（PUBLIC TEST DATA） | `tools/simulator/certs/` | TLS 启动 + SPKI pin | **PASS（HTTP/TLS 实启；SPKI 一致）** |
| V-08 | product-profile | 由 `state-report.schema.json` 反推（P-15） | `tools/test-fixtures/iotda/product-profile.json` | 网关套件 2 个 ERROR → PASS | **PASS** |
| V-09 | 模块 HMAC 向量 | `module-hmac-test-vector.json` | `input/api/protocol/`（crosscheck 读取） | 网关↔模块域；App 不实现 | **PASS（crosscheck D 段）** |
| V-10 | BLE Security1 / RFC7748 / protobuf 常量 | WP2 §7.2；`test_ble_provisioning_contract.py` | 计划复制到 `entry/src/ohosTest/ets/test/contract/fixtures/ble/`（T-12） | Security1 step0、Wi-Fi 帧、RFC7748 三元组 | `NOT_RUN`（T-12） |
| V-11 | 身份 schema 严格解析 | `ble-enrollment-identity-request/response.schema.json` | `input/api/protocol/` | `get_identity`、多余字段 fail-closed | `NOT_RUN`（T-06/T-12） |
| V-12 | 云命令/影子 golden | `cloud-command.schema.json`、state-report schema | `input/api/protocol/`；T-14 新增 fixture | `paras` 10 字段、`CmdId=3001`、`Value` 原子、签名 | `NOT_RUN`（T-14） |
| V-13 | i18n bundle/CHK fixtures | I18N-DESIGN §6.3 | `resources/rawfile/i18n/*`、`tools/i18n/`（T-10） | key parity/插值/复数/缺失 | `NOT_RUN`（T-10） |
| V-14 | 领域/VM fixtures | DES-B §21.3 | T-09/T-15/T-16 测试目录 | 房间/设备/场景/门锁/RBAC/VM | `NOT_RUN`（组件未实现） |

### 3.2 夹具纪律

1. 复制 `input/api/protocol` 向量时保留文件名/内容，并在 `entry/src/ohosTest/ets/test/contract/fixtures/README.md` 记录源路径与 SHA-256。
2. 不修改 golden 以迁就实现；实现与 golden 不一致时按 §8 记录 `FAIL_PRODUCT` 或 `FAIL_TEST`，走 Change Impact/失败诊断。
3. 每个用例新建 fake/可变状态，不共享可变对象（DES-B §21.3）。
4. 所有 secret 标注 `PUBLIC TEST DATA ONLY`；禁止真实凭据。

---

## 4. 每组件 CQG 证据模板

### 4.1 通用模板（对照 delivery-plan §4.1）

```text
CQG-Txx（component C-xx） @ revision <commit>
- build:   <command> -> PASS/FAIL/COMPILED_ONLY (log path)
- lint:    <command> -> PASS/FAIL (report path)
- host:    <command> -> PASS (n tests) / FAIL / BLOCKED (reason, evidence)
- contract:<vector/golden/crosscheck/simulator> -> PASS/FAIL/NOT_RUN (evidence)
- device:  onDeviceTest -> PASS / BLOCKED / UNAVAILABLE (reason)
- i18n:    CHK-01..09 -> PASS/FAIL/NOT_APPLICABLE (report)
- layer:   check_layering / production-mock-exclusion -> PASS/FAIL (report)
- security: no secret logs / fail-closed / PM-02 -> PASS/FAIL (SEC note)
- review:  independent reviewer / review record -> PASS/FAIL
- trace:   FR/SC/component -> test names (table)
PASS rule: every Must item has current-revision evidence; otherwise FAILED/UNVERIFIED.
```

### 4.2 组件 → 证据层矩阵（29 组件）

> 状态为**计划**；组件当前均为 `UNIMPLEMENTED`，所以除 T-05 工具层（C-29）外均无组件 CQG 证据。

| 组件 | 名称 | 主测试层 | 关键证据/负例 | 目标 CQG | 当前 |
|---|---|---|---|---|---|
| C-01 | 公共类型、常量与工具 | Host UT | 时间戳/±120s、JSON 原子、hex/b64url、紧凑数字 | CQG-T06 | `NOT_RUN` |
| C-02 | 领域模型与枚举 | Host UT | 不变量、默认值、`stateEpochMs` 派生 | CQG-T06 | `NOT_RUN` |
| C-03 | 协议 DTO/映射/校验 | Host UT + CT | V-01..V-06、别名、`success` 忽略、identity fail-closed | CQG-T06 | `NOT_RUN` |
| C-04 | CryptoService | Host UT/CT + device | RFC7748、HMAC、CTR 连续流、常数时间 | CQG-T07 | `NOT_RUN` |
| C-05 | SecurityService | Host UT/CT + SEC | V-01..V-03、nonce 失败不消耗、correlation fail-closed | CQG-T07 | `NOT_RUN` |
| C-06 | 存储服务 | Host UT + device IT | fake store、alias 生命周期、擦除、迁移 | CQG-T08 | `NOT_RUN` |
| C-07 | GatewayRepository | Host UT + device IT | route CRUD、P-HMAC/P-TLS-PIN/P-BLOCKED、pin 绑定 | CQG-T08 | `NOT_RUN` |
| C-08 | FamilyRepository | Host UT + IT | 家庭/成员/邀请/回执、GUEST 到期、RBAC | CQG-T09 | `NOT_RUN` |
| C-09 | RoomRepository | Host UT + IT | 删除保护、未分配池、改名零网络 | CQG-T09 | `NOT_RUN` |
| C-10 | DeviceRepository | Host UT/CT + IT | 陈旧包丢弃、别名、tombstone、ACK 应用 | CQG-T09 | `NOT_RUN` |
| C-11 | SceneService | Host UT + IT | 串行、局部失败不回滚、引用清理 | CQG-T09 | `NOT_RUN` |
| C-12 | AuthService | Host UT/CT | PBKDF2 参数、RBAC 矩阵、锁定 | CQG-T13 | `NOT_RUN` |
| C-13 | InviteService | Host UT/CT + SEC | YCI1/YCR1、AEAD/AAD 篡改、过期/maxUses、回执 | CQG-T13 | `NOT_RUN` |
| C-14 | I18nService/资源包 | Host UT + CT | CHK-01..09、fallback/插值/复数、运行时切换 | CQG-T10 | `NOT_RUN` |
| C-15 | CloudService | Host UT/CT + IT | `paras` 映射、签名、Token 过期、inventory fail-closed | CQG-T14 | `NOT_RUN` |
| C-16 | AC 品牌适配 | Host UT/CT | 7 值、16..30、percent、非标准回退 | CQG-T14 | `NOT_RUN` |
| C-17 | LocalGatewayService | Host UT/CT + IT + device | V-01..V-06、TLS pin、DEV-ONLY、幂等 | CQG-T11 | `NOT_RUN` |
| C-18 | GatewayDiscoveryService | Host UT/CT | 候选去重、手动 IP 仅已绑定、PB-01 seam | CQG-T11 | `NOT_RUN` |
| C-19 | BleProvisioningService | Host UT/CT + device | V-10、Security1、身份 v2.0/v2.1、清理 | CQG-T12 | `NOT_RUN` |
| C-20 | MockGateway/MockBle | Host UT + IT + SEC | 行为矩阵、TLS 四模式、生产排除 | CQG-T11/T12 | `NOT_RUN` |
| C-21 | Home/Device/Climate/Door VM | Host UT + IT | 三态、55ms、TouchUp、门锁 10s/离线 | CQG-T15 | `NOT_RUN` |
| C-22 | Family/Room/Scene VM | Host UT + IT | RBAC、房间删除、场景局部失败、邀请状态 | CQG-T16 | `NOT_RUN` |
| C-23 | Provisioning/Settings VM | Host UT + IT | 配网状态机、取消清理、Token 过期、手动 IP | CQG-T16 | `NOT_RUN` |
| C-24 | 设计系统/UI 组件 | Build + UI smoke | 主题 token、i18n 键、空/错误/加载态 | CQG-T17 | `BLOCKED`（设备） |
| C-25 | Home/Rooms/DeviceControl 页面 | Build + UI smoke | 导航、三态 UI、房间池、可访问性 | CQG-T17 | `BLOCKED`（设备） |
| C-26 | Family/Room/Scene 页面 | Build + UI smoke | 邀请展示/扫码粘贴、RBAC 可见性 | CQG-T18 | `BLOCKED`（设备） |
| C-27 | Provisioning/Settings/About/Profile | Build + UI smoke | 6 步向导、语言/云/TLS/高级 IP、安全文案 | CQG-T18 | `BLOCKED`（设备） |
| C-28 | 应用壳/EntryAbility/权限/组合根 | Build + startup smoke | 导航、权限、生产 Mock 排除、启动失败 | CQG-T17/T18 | `BLOCKED`（设备） |
| C-29 | 构建/仿真/README 工具 | Tool self-test | 本文件 §2/§9；simulator 20/20；crosscheck 66/66 | T-05/G-008 | **工具证据 PASS；组件 CQG 未运行** |

### 4.3 每个 CQG 的最小必填证据

| CQG | 必填 |
|---|---|
| CQG-T06 | `mapDiscoverResponse`/`mapControlAck` golden、identity fail-closed、构建/lint |
| CQG-T07 | V-01..V-03 全通过、RFC7748、CTR 流、±120s/300s 负例、常数时间审查、SEC 记录 |
| CQG-T08 | fake store 事务/回滚、pin 绑定/轮换、无明文 secret 日志 |
| CQG-T09 | SSOT/仲裁、房间删除、场景局部失败、邀请/回执状态机 |
| CQG-T10 | CHK-01..09 报告、key parity 100%、无硬编码 UI 文案 |
| CQG-T11 | discover→control→ACK、TLS pin 三态、DEV-ONLY、幂等/重试 |
| CQG-T12 | Security1 向量、身份协商、Wi-Fi 状态机、取消清理 |
| CQG-T13 | YCI1/YCR1、AEAD/AAD、过期/去重、回执 HMAC |
| CQG-T14 | 云命令 canonical/签名、shadow 解析、完成判定、错误命名空间 |
| CQG-T15/T16 | VM 纯逻辑 + fake clock + Mock 集成；UI 仅 smoke/静态 |
| CQG-T17/T18 | 构建 + 导航/权限/UI smoke（设备可用时）；i18n/RBAC 静态检查 |

---

## 5. 安全负例矩阵

> 目标：证明 fail-closed、防重放、防乐观成功、DEV-ONLY 拒收、秘密不泄漏。`Owner` 为实现任务；`Layer` 为最低可执行层。

| ID | 前置/输入 | 期望 | Layer | Owner | 当前 |
|---|---|---|---|---|---|
| SEC-N01 | 新 nonce + 篡改 `sign` | HTTP 401 / `1004`；不执行、不消耗 nonce | Python + Host + Device | T-07/T-11 | **PASS（simulator 套件）** |
| SEC-N02 | 过期时间戳（>±120s）+ 合法结构 | 401 / `1003`；不消耗 nonce；新 nonce 可重试 | Python + Host | T-07/T-11 | **PASS（simulator 套件）** |
| SEC-N03 | 精确重传（同 key/nonce/request_id/seq/sign） | 原 ACK；可加 `idempotent_replay:true`；不重复执行 | Python + Host | T-07/T-11 | **PASS（simulator 套件）** |
| SEC-N04 | 同 nonce + 改 payload/sign | HTTP 409 / `1005`；不执行 | Python + Host | T-07/T-11 | **PASS（simulator 套件）** |
| SEC-N05 | 未知 `key_id` | 401 / `1002`；不降级 | Python + Host | T-07 | **PASS（simulator 套件）** |
| SEC-N06 | 未知 `alg` | 401 / `1002`；不降级 | Host | T-07 | `NOT_RUN` |
| SEC-N07 | 响应签名坏 / 缺 header | `RESPONSE_AUTH_FAILED`；不解析/不应用 | Host | T-07/T-11 | `NOT_RUN` |
| SEC-N08 | 响应 correlation 错（`request_id:seq`/challenge） | `RESPONSE_CORRELATION_MISMATCH`；不应用 | Host | T-07/T-11 | `NOT_RUN` |
| SEC-N09 | ACK `result_code!=0`（1004/1005/1006/1007/1008/未知） | `ackAccepted=false`；VM 不显示成功；未知码 fail-closed | Host | T-06/T-11/T-15 | `NOT_RUN` |
| SEC-N10 | `result_code==0` 但缺 `reported_state` | `ACK_PROTOCOL_VIOLATION`；不应用 | Host | T-06/T-11 | `NOT_RUN` |
| SEC-N11 | `reported_state` 目标/动作不一致 | `ACK_STATE_MISMATCH` / `MISMATCH`；REVERT/提示 | Host | T-10/T-15 | `NOT_RUN` |
| SEC-N12 | `reported_state` 含 `success:true` / 仅 HTTP 2xx | 不得视为成功（SC-13/SC-14） | Host | T-06/T-15 | `NOT_RUN` |
| SEC-N13 | 响应头 `X-YaoCore-Simulator: DEV-ONLY`（大小写变体） | 拒收 `DEV_SIMULATOR_REJECTED`；不解析 | Host + Device | T-11 | **PASS（simulator 发出标记）**；客户端拒收 `NOT_RUN` |
| SEC-N14 | 未知 `result_code`（如 9999） | `known=false`、`success=false`、记录偏差；UI 通用失败 | Host | T-06/T-15 | `NOT_RUN` |
| SEC-N15 | TLS pin mismatch | `TLS_PIN_MISMATCH`；不发控制；不降级 HTTP | Device/Mock | T-11 | `BLOCKED`（无设备；仿真器 SPKI 已就绪） |
| SEC-N16 | TLS handshake fail / 证书解析失败 | `TLS_HANDSHAKE_FAILED`；P-BLOCKED | Device/Mock | T-11 | `BLOCKED` |
| SEC-N17 | TLS 网关宣告但 route 无 pin/非法 pin | `TLS_UNAVAILABLE_ADVERTISED`/`TLS_PROFILE_INCONSISTENT`；不发控制 | Host | T-11 | `NOT_RUN` |
| SEC-N18 | 重复 JSON key / `NaN`/`Infinity` | 400 / `1001`；严格解析拒绝 | Python + Host | T-06 | **PASS（simulator 套件）** |
| SEC-N19 | 未知设备 / 不支持动作 / 离线设备 | 422 / `1006`（细分）或 503 / `1007`；不确认成功 | Python + Host | T-06/T-11 | **PASS（simulator 套件）** |
| SEC-N20 | 硬件超时 / `1008` | `hardware_timeout`；可重试/“未确认到位”；不显示成功 | Host | T-06/T-15 | `NOT_RUN`（FC-02 合成用例） |
| SEC-N21 | identity 响应多余字段/常量不符 | `PROVISIONING_IDENTITY_INVALID`；fail-closed | Host + Device | T-12 | `NOT_RUN` |
| SEC-N22 | 邀请容器 AAD 篡改/过期/maxUses/重放 | `INVITE_INVALID/EXPIRED/REVOKED`；不加入 | Host | T-13 | `NOT_RUN` |
| SEC-N23 | RBAC：GUEST 控制未授权房间 | 拒绝/不可见；UI 不显示可操作控件 | Host + UI | T-13/T-16 | `NOT_RUN` |
| SEC-N24 | 日志/异常含 secret/PoP/Wi-Fi/密钥 | 静态扫描零命中；测试断言不输出 | Host + Review | T-07/T-20 | `NOT_RUN` |
| SEC-N25 | 生产组合根 import Mock | 静态检查失败；构建 source map 无 mock | Build + Review | T-11/T-20 | `NOT_RUN` |
| SEC-N26 | 签名比较非常数时间/长度提前返回 | 代码审查 + 单测（长度不等 false、无泄漏时序分支） | Host + Review | T-07 | `NOT_RUN` |

> 当前 PASS 仅指 **Python 仿真器层**；客户端 ArkTS 的对应负例要等 T-06/T-07/T-11 实现，不能把仿真器 PASS 写成 App PASS。

---

## 6. i18n 检查（CHK-01..09 落地方案）

### 6.1 检查项与门禁

| ID | 检查 | 实现方式（T-10） | 失败级别 | 当前 |
|---|---|---|---|---|
| CHK-01 | rawfile 键集对齐 | `tools/i18n/check_i18n.py` 比较 `zh-CN.json`/`en-US.json` 键路径（含 `_one/_other` 展开） | 阻断 | `NOT_APPLICABLE`（资源未建） |
| CHK-02 | `string.json` 键集对齐 | 比较 `base`/`en_US` 键集合 | 阻断 | `NOT_APPLICABLE` |
| CHK-03 | 插值参数对齐 | 提取 `{param}` 集合；参数名 `[a-zA-Z][a-zA-Z0-9_]*` | 阻断 | `NOT_APPLICABLE` |
| CHK-04 | 空值/占位 | 空值、`TODO`/`??`、未闭合大括号 | 阻断 | `NOT_APPLICABLE` |
| CHK-05 | 未使用键 | 扫描 `t('…')`/`$r('app.string.…')`；动态拼键禁止 | 告警 + 评审 | `NOT_APPLICABLE` |
| CHK-06 | 未定义键 | 代码引用必须存在于对应存储 | 阻断 | `NOT_APPLICABLE` |
| CHK-07 | 硬编码扫描 | UI 目录 CJK/英文句子命中即阻断；非 UI 走 allowlist | 阻断（UI） | `NOT_APPLICABLE` |
| CHK-08 | 多语言代码分叉 | 文件名 `_en/_zh/English/Chinese`；`if (isChinese())` 直接返回字面量 | 阻断 | `NOT_APPLICABLE` |
| CHK-09 | locale 目录结构 | 仅声明支持的目录；两个存储 locale 集合一致 | 阻断 | `NOT_APPLICABLE` |

### 6.2 测试计划

1. **Host**：`I18nService.t` 纯函数测试——fallback（当前→zh-CN→key）、插值、复数 `_one/_other`、缺 key 不抛/不空白；`errorCodeToI18nKey`/`stateSourceToI18nKey` 映射矩阵。
2. **Contract**：CHK-01..09 报告，key parity 100%；allowlist 文件逐条登记（文件+行+理由）。
3. **Device/UI**：运行时切换 zh-CN↔en-US，无需重启；`$r` 与 `t()` 同步；en-US 长文本不截断（20-40% 膨胀）；截图/人工抽查 ≥10 条 UI 文案。
4. **当前**：资源与 `I18nService` 未实现 → 全部 `NOT_APPLICABLE`；不得预先声称 i18n PASS。

---

## 7. NFR 4.3 可执行测量口径

### 7.1 ACK p95 ≤ 500ms

| 项 | 口径 |
|---|---|
| 计时点 | `t0` = 写入控制请求前；`t1` = 响应验签 + correlation + `result_code==0` + `reported_state` 通过并应用之后 |
| 分段 | 记录 `transportMs`（t0→收到 body）与 `commitMs`（body→状态应用），总时延 `ackMs=t1-t0` |
| 样本 | 每动作/每 profile `N≥100`；丢弃前 5 次 warm-up；单调时钟 |
| 环境 | 分别记录 localhost 仿真器、模拟器 LAN、真机 LAN；记录设备/OS/网络/commit |
| 报告 | p50/p95/max、样本数、环境、profile、`resultClass`（`MOCK_ONLY`/`EMULATOR_ONLY`/`DEVICE_ONLY`/`ESTIMATE`/`UNAVAILABLE`） |
| 限制 | 仅对定义环境有效；真实 LAN/真机 `USER_RUN_REQUIRED`；不得外推 |

Harness（已落地并自测）：`entry/src/test/host/perf-harness.mjs`

```js
import { measureOperation, buildPerfReport } from './perf-harness.mjs';

const summary = await measureOperation(async () => {
  const t0 = performance.now();
  await gateway.sendControl(profile, command); // includes write
  await applyAckAndState(profile, command);    // auth + correlation + result_code + reported_state
  return performance.now() - t0;
}, { samples: 100, warmup: 5 });

const report = buildPerfReport(summary, {
  metric: 'ack.p95',
  resultClass: 'MOCK_ONLY',              // or EMULATOR_ONLY / DEVICE_ONLY / ESTIMATE
  environment: 'linux localhost Python simulator',
  profile: 'light/SET_BRIGHTNESS',
  warmup: 5,
  limitation: 'not a real LAN/device measurement',
});
```

当前状态：harness **PASS（4 项自测）**；真实 ACK 数值 **UNAVAILABLE**（无设备/真实 LAN；产品 C-17 未实现）。

### 7.2 55ms 节流

| 项 | 口径 |
|---|---|
| 单元 | `FakeTimer` 精确推进；55ms 窗口最多 1 个在途请求；窗口内多次输入仅最新值胜出 |
| TouchUp | TouchUp 立即发送最终值（强同步），不等待窗口 |
| 样本 | 20 次拖动/1s；断言请求数、合并数、TouchUp 延迟 |
| 集成 | 真实计时仅作报告，不作为 UI 帧率证据 |
| 当前 | `NOT_RUN`（T-15 实现后）；不得把“节流常量存在”写成 PASS |

### 7.3 60/120fps

| 项 | 口径 |
|---|---|
| 设备/模拟器 | ArkUI frame callback/profiler；10s 滚动/动画；平均 FPS、p95 帧时间；记录分辨率/刷新率/负载 |
| 当前 | `UNAVAILABLE`（无设备/模拟器实例） |
| 替代 | 仅静态审查（UI 线程无同步 IO、`LazyForEach`、缓存、避免大列表全量重绘）；标残余风险 |
| 禁止 | 用 Node/仿真器数字冒充帧率；用 55ms 节流数字冒充 FPS |

### 7.4 结果标注纪律

- 所有性能结果必须带 `MOCK_ONLY`/`ESTIMATE`/`EMULATOR_ONLY`/`DEVICE_ONLY`/`UNAVAILABLE`；
- 不得把 Mock 数字写成产品验收 PASS；
- 无设备时 `UNAVAILABLE` 是合法证据，不是失败，但必须列出。

---

## 8. 失败/未运行记录模板

```text
TEST-RESULT
- Artifact/Requirement: <ID>
- Revision: <commit/task branch>
- Environment: <OS/toolchain/device/signing>
- Layer: <host/contract/simulator/device/perf>
- Command: <exact command>
- Expected: <oracle/contract/acceptance>
- Actual: <output/exit code>
- Classification: PASS | FAIL_PRODUCT | FAIL_TEST | FAIL_ENV | BLOCKED | COMPILED_ONLY | NOT_RUN | UNAVAILABLE
- Evidence: <log path>
- Reproduction: <minimal steps>
- Owner/Next: <implementation-engineer | debug-specialist | environment | user>
- Notes: <flaky? skipped? known limitation?>
```

规则：

1. 失败必须保留原始输出；只允许在 flaky/环境可疑时做**一次**受控重跑。
2. 跳过/隔离/超时/无断言执行**不计** PASS。
3. 产品行为失败与测试缺陷/环境失败分开；不得改断言换 PASS。
4. 连续两次修复失败 → 停止局部补丁，交 `debug-specialist`/Failure Escalation。

---

## 9. 当前执行证据矩阵（本 revision）

> 执行 revision：`task/wp-010-test-plan` @ base `1c44503` + 本任务工作树；最终提交 ID 由 `swe_guard finish` 记录。

| # | 命令 | 结果 | 分类 | 证据 |
|---|---|---|---|---|
| 0 | `hvigorw clean assembleHap --no-daemon` | `BUILD SUCCESSFUL`；unsigned HAP | **PASS（构建）** | `entry/src/test/evidence/clean-assemble.log` |
| 1 | `entry/src/test/run-host-tests.sh` | `1..15`、pass 15、fail 0、exit 0 | **PASS** | `entry/src/test/evidence/host-node-tests.tap` |
| 2 | `hvigorw test --no-daemon` | `UnitTestArkTS` 完成；Previewer 缺 `libshared_libz.so`；超时 124 | **COMPILED_ONLY / BLOCKED** | `hvigor-test-default-timeout.log`、`previewer-default-env.log` |
| 3 | `LD_LIBRARY_PATH=<shim> hvigorw test --no-daemon` | Previewer `Linux is not supported`；超时 124 | **BLOCKED / FAIL_ENV** | `hvigor-test-with-lib-shim.log`、`previewer-with-lib-shim.log` |
| 4 | `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | `BUILD SUCCESSFUL`；unsigned HAP | **PASS（编译）** | `entry/src/test/evidence/ohosTest-assemble.log` |
| 5 | `hvigorw ... onDeviceTest --no-daemon` | exit 255；`00507013 need connect-key` | **BLOCKED** | `entry/src/test/evidence/onDeviceTest-blocked.log` |
| 6 | `codelinter -c code-linter.json5 -p default .` | `No defects found in your code.` | **PASS** | `entry/src/test/evidence/codelinter.log` |
| 7 | `python3 -m unittest tools.simulator.test_gateway_contract -v` | `Ran 20 tests ... OK` | **PASS 20/20** | `tools/simulator/evidence/run-test_gateway_contract.txt` |
| 8 | `python3 tools/contract/crosscheck_protocol_assets.py` | 66 PASS / 0 FAIL / 14 FINDING；exit 0 | **PASS 66/66** | `tools/contract/evidence/run-crosscheck.txt` |
| 9 | HTTP simulator + `curl /health,/discover` | 200 + `X-YaoCore-Simulator: DEV-ONLY` | **PASS** | `tools/simulator/evidence/http-*.txt` |
| 10 | TLS simulator + `curl -k /health,/discover` | 200 + DEV-ONLY；SPKI 打印 | **PASS** | `tools/simulator/evidence/tls-*.txt`、`tls-server.log` |
| 11 | TLS 签名 `POST /control` | 200；`result_code:0`；`reported_state` | **PASS** | `tools/simulator/evidence/tls-control-ack.json` |
| 12 | `openssl` SPKI 复算 vs Python/Node | 三者一致 `63f928c4…3243` | **PASS** | `tools/simulator/evidence/tls-server.log`；host test |
| 13 | `ohpm install` | 已在 T-01 验证；本任务未重跑 | **NOT_RUN（复用 T-01）** | `artifacts/50-implementation/build-baseline.md` §2 |
| 14 | 设备/真实 LAN/BLE/云/UI 性能 | 无设备/无签名/无真实环境 | **UNAVAILABLE** | 本文 §11 |

> 证据日志在提交前仅做行尾空白/CRLF 规范化（`git diff --cached --check` 要求），命令输出与退出码未改。

### 9.1 关键结论

- **Host 纯逻辑路径已实证可运行**：Node runner 15/15，覆盖全部公开 HMAC/响应/发现向量、ACK/discover golden、SPKI、测量 harness。
- **`hvigorw test` 仍未产生任何 Hypium 运行时断言**；原因是 Linux Previewer 缺库/不支持，不是测试代码失败。该结论与 T-01 的 `hvigorw test` 失败不同：T-01 是缺 `entry/src/test/List.test.ets`，本任务已创建该入口并验证编译通过。
- **仿真器 HTTP/TLS 两种模式均可启动/响应**，TLS 启动打印 SPKI-SHA256；这仍只是 localhost 工程证据，不是真实网关 TLS 证据。
- **契约检查 66/66** + **网关套件 20/20**，其中 2 个此前因缺 `product-profile.json` 的 ERROR 已修复；14 项 crosscheck FINDING 是冻结输入观测，不是本任务失败。
- **设备测试 BLOCKED**；未把测试 HAP 编译写成测试通过。

---

## 10. 复用指南（T-06 起）

### 10.1 新增 host 测试

1. 在 `entry/src/test/host/` 新建 `*.test.mjs`（Node `node:test` + `node:assert/strict`）。
2. 纯逻辑 oracle/产品模块可放在 `.ets`/`.ts`，但不得 import `@ohos.*`、ArkUI 装饰器、`struct`。
3. 运行 `entry/src/test/run-host-tests.sh`；失败时保留 TAP 输出。
4. 若需要把产品 `.ets` 引入 host，先用 `protocol-oracle.ets` 的模式验证其无平台依赖；有平台依赖的组件走 ohosTest/设备层。

### 10.2 新增向量/golden

1. 从 `input/api/protocol/` 复制到 `entry/src/ohosTest/ets/test/contract/fixtures/`，保留文件名与内容。
2. 在 `fixtures/README.md` 记录源路径、SHA-256、公开测试数据标注。
3. 在 host 测试中独立复算；不要调用产品实现来生成期望值。
4. golden 改变视为契约变更：先记录 Change Impact，再更新测试。

### 10.3 使用仿真器

```bash
# HTTP
python3 tools/simulator/gateway_contract_server.py --host 127.0.0.1 --port 9200 --quiet

# TLS（自签名测试证书；启动打印 SPKI）
python3 tools/simulator/gateway_contract_server.py --host 127.0.0.1 --port 9443 --quiet \
  --tls --cert tools/simulator/certs/dev-test-cert.pem \
  --key tools/simulator/certs/dev-test-key.pem
```

- 客户端必须拒收 `X-YaoCore-Simulator: DEV-ONLY`（SC-11）；
- TLS 测试只证明 localhost 握手/协议，不是真实网关/证书链证据；
- 禁止把仿真器 secret/证书用于生产。

### 10.4 每个实现任务的 CQG 步骤

1. `hvigorw clean assembleHap --no-daemon`；
2. `codelinter ...`；
3. `entry/src/test/run-host-tests.sh`（新增/修改的纯逻辑必须覆盖正/负/边界）；
4. `python3 tools/contract/crosscheck_protocol_assets.py`（协议变更时）；
5. `python3 -m unittest tools.simulator.test_gateway_contract -v`（仿真器/协议变更时）；
6. 设备可用时 `onDeviceTest`；不可用则写 `BLOCKED` + 原因；
7. 按 §4.1 填 CQG 模板，附日志路径与 traceability。

---

## 11. 风险与限制

| ID | 限制/风险 | 影响 | 处置 |
|---|---|---|---|
| T05-R01 | `hvigorw test` 的 Linux Previewer 缺 `libshared_libz.so` 且 `Linux is not supported` | Hypium host 断言无法执行 | Node runner 替代；记录根因；不伪造 PASS；设备/CI 环境复跑 |
| T05-R02 | 无真机/模拟器/签名 | 设备/UI/TLS/BLE/云/性能无运行时证据 | 标 `BLOCKED`/`UNAVAILABLE`；用户/CI 执行；CP-03 |
| T05-R03 | Node runner 不是 ArkTS 运行时 | 类型/语义差异（enum/装饰器/平台 API）不能由 host 证明 | 仅测纯逻辑；平台行为走 ohosTest；T-19 明确边界 |
| T05-R04 | `.ets` loader 使用 Node 实验性 `stripTypeScriptTypes` | Node 版本升级可能变化 | 固定 Node 24.15；T-19 记录版本；失败时改纯 `.mjs` |
| T05-R05 | 测试源码不在 `code-linter` 范围 | 测试代码 lint 无证据 | T-10/T-19 增加独立检查；当前如实记录 |
| T05-R06 | 仿真器/证书是公开测试材料，SC-02 例外 | 误用可能造成“测试证书当生产” | `certs/README` + 本计划登记；禁止复制到 main/resources/签名配置 |
| T05-R07 | 14 项 crosscheck FINDING 未裁定 | API 散文示例/result_code 冲突仍存在 | 归 wp-004/CB；T-06 以 schema 为准；不在本任务改 `input/` |
| T05-R08 | golden 时间戳静态（2026-07/10） | 不能直接用于实时请求 | 只用于 canonical/结构测试；实时请求由 fake clock/当前时间生成 |
| T05-R09 | 无覆盖率工具 | 无法报告行/分支覆盖率 | T-19 评估 `collectCoverage`/设备覆盖率；当前只报告用例数 |
| T05-R10 | 设备测试命令在 `ohosTest` 上误用 `test` 会失败 | 团队误判 | 明确 `hvigorw test`=host，`onDeviceTest`=设备（BUILD-BASELINE §5、ohosTest README） |

---

## 12. Traceability（骨架，T-19 补全）

| 需求/约束 | 组件 | 测试层/测试 ID（计划或已落地） | 状态 |
|---|---|---|---|
| FR-DEV-001/002/005；NFR-4.1 | C-03/C-05/C-17 | V-01..V-06；SEC-N01..N04/N07..N10 | 向量 PASS；客户端 `NOT_RUN` |
| FR-GW-001..003；ADR-002 §6 | C-07/C-17/C-18/C-19 | TLS pin mock/仿真器；SEC-N15..N17；V-10 | 仿真器 TLS PASS；pin `BLOCKED` |
| FR-FAM-001..004；ADR-003 | C-08/C-12/C-13/C-22 | 家庭/RBAC/邀请/回执 fixture；SEC-N22/N23 | `NOT_RUN` |
| FR-ROOM-001..006；ADR-004 | C-09/C-10/C-22 | 房间删除/未分配/改名零网络 | `NOT_RUN` |
| FR-SCN-001 | C-11/C-22 | 场景串行/局部失败/不回滚 | `NOT_RUN` |
| FR-SET-002/003；I18N-02/05 | C-14/C-23/C-27 | CHK-01..09；运行时切换；硬编码扫描 | `NOT_APPLICABLE`（未实现） |
| NFR-4.3（ACK p95/55ms/FPS） | C-17/C-21/C-25 | §7 harness/口径 | harness PASS；数值 `UNAVAILABLE` |
| SC-01..SC-08（秘密治理） | 全组件 | §5 SEC-N24；提交前 SC-07 检查 | 部分工具层 PASS；产品 `NOT_RUN` |
| SC-11（DEV-ONLY） | C-11/C-20/C-28 | SEC-N13/N25；仿真器标记 | 仿真器 PASS；客户端 `NOT_RUN` |
| SC-13/SC-15（确认/验签） | C-05/C-17/C-21 | SEC-N07..N14；V-02/V-05 | 向量/golden PASS；客户端 `NOT_RUN` |
| SC-16（邀请） | C-13 | V-14/SEC-N22 | `NOT_RUN` |
| CP-03（无真机门禁） | 全组件 | 设备项 `BLOCKED`/`UNAVAILABLE` | 已遵守 |

> 完整 FR/NFR → component → task → test 映射由 T-19 执行报告补齐；本表只冻结测试层的锚点。

---

## 13. G-008 自检与建议结论

### 13.1 T-05 DoD 对照

| DoD | 结果 | 证据 |
|---|---|---|
| 1. §6 测试分层/向量复用/边界写实，不把未运行写成 PASS | **满足** | 本文件 §0/§2/§9/§11 |
| 2. 仿真器移植 + `--tls --cert --key` + SPKI + 公开测试证书 | **满足** | `tools/simulator/**`；HTTP/TLS 实启；SPKI 一致 |
| 3. crosscheck 适配并 66/66；product-profile 反推（P-15） | **满足** | 66/66；20/20；2 个 ERROR 转 PASS |
| 4. NFR 4.3 可执行测量脚本/harness 约定；明确不可测项 | **满足** | §7；`perf-harness.mjs` + 4 项自测；`UNAVAILABLE` 清单 |
| 5. 测试骨架可复用；记录精确命令/前置 | **满足** | §2/§10；`run-host-tests.sh`；host 15/15 |

### 13.2 建议 Gate 结论（供 Orchestrator 判定）

- **G-008 Artifact Validation**：建议对“计划完整性、分层/命令、向量清单、CQG 模板、安全负例、i18n 方案、NFR 口径、证据分类”判 **PASS**。
- **CQG-T05/工具证据**：host 15/15、simulator 20/20、crosscheck 66/66、HTTP/TLS 实启、测试 HAP 编译、codelinter PASS 可用。
- **不得声称**：Hypium host 用例通过、设备测试通过、真实 TLS/BLE/云/UI 性能通过。它们分别是 `BLOCKED`/`UNAVAILABLE`/`COMPILED_ONLY`。
- **后续**：T-06 起按 §4/§5/§10 消费；T-19 汇总执行报告；T-20 复核测试真实性与 Mock 生产排除。

---

*TEST-001 结束。所有命令在 `task/wp-010-test-plan`、base `1c44503` 上执行；测试资产来源/哈希与限制见各目录 README 及本文件 §3/§9/§11。*

---

## 14. T-19 全量执行结果（2026-10-18，wp-082-verify）

> 执行 revision：`task/wp-082-verify` @ base `4f7c26be664a8db8aaba136fce1f128ccc72223a`；最终 commit 由 `swe_guard finish` 记录。完整分层表、FR/NFR 矩阵、安全负例与限制见 [`test-report.md`](test-report.md)（TEST-REPORT-001）。

### 14.1 状态更新（追加，不改变既有条目语义）

| 层/项 | T-05 状态 | T-19 当前状态 | 证据 |
|---|---|---|---|
| Host 纯逻辑 | PASS 15/15 | **PASS 696/696**（新增 2 条 R3-01 并发/失败隔离） | `entry/src/test/evidence/t19-host-node-tests.tap` |
| 构建 | PASS | **PASS**（`BUILD SUCCESSFUL`，unsigned） | `t19-clean-assemble.log` |
| `codelinter` | PASS | **PASS（0 error / 25 warning）** | `t19-codelinter.log` |
| 测试 HAP | PASS（编译） | **COMPILED_ONLY**（编译成功，未执行） | `t19-ohosTest-assemble.log` |
| 契约 crosscheck | PASS 66/66 | **PASS 66/66** | `t19-crosscheck.log` |
| 仿真器套件 | PASS 20/20 | **PASS 20/20**（`no_proxy` 受控重跑；默认代理首跑 FAIL_ENV） | `t19-simulator-contract.log`、`t19-simulator-contract-proxy-fail.log` |
| i18n CHK-01..09 | NOT_APPLICABLE（资源未建） | **PASS**；blocking 0 / missing 0 / warnings 121 / hardcoded 82 | `t19-i18n-report.json` |
| 分层检查器（C-29） | 未实现 | **PASS 0 violation**；13 条 R3-01 `pending-T-20` 例外可见；fixture 4/4 | `t19-layering.json`、`t19-layering-fixture-tests.log` |
| 安全负例矩阵 | 部分（仿真器） | **SEC-N01..N26 均有当前证据**；设备相关项仍 BLOCKED | `t19-security-negative.tap`、`test-report.md` §4 |
| NFR 4.3 | harness PASS / 数值 UNAVAILABLE | 55ms **PASS**；ACK p95 **MOCK_ONLY 0.598ms**；真实 p95/60/120fps **UNAVAILABLE** | `t19-ack-p95-mock.json` |
| 设备/UI/BLE/LAN/云 | BLOCKED/UNAVAILABLE | **不变：BLOCKED/UNAVAILABLE** | `test-report.md` §7 |

### 14.2 CQG / 阶段状态

- **C-01..C-29 组件级证据**：T-06..T-18 CQG 已记录；T-19 未重新授予 CQG，只补充全量执行证据。
- **IG-4（全量测试）**：证据就绪（构建/静态/host/契约/仿真/i18n/分层/安全/性能口径），但设备矩阵仍 BLOCKED；**IG-3 仍 NOT READY**，不得因本报告宣布 Stage Gate PASS。
- **T-20 输入**：`test-report.md` §3.2 的 13 条 R3-01 `pending-T-20` 例外、端口位置例外、SEC-N26 常数时间复核。
- **GAP-T18-01 / R4-01**：仍为 T-18 遗留；Stage Gate 必须记录，本任务未关闭。

### 14.3 新增/变更测试资产

| 路径 | 变更 |
|---|---|
| `entry/src/test/host/ViewModelDevice.test.mjs` | +2 用例（R3-01：跨设备同时在途、单侧失败隔离）；原 694 条全部保留 |
| `tools/contract/check_layering.py` | C-29 分层检查器（D-01/02/03/05/06/08/09/11/12/13/17） |
| `tools/contract/layering_allowlist.json` | 文件/符号级例外；13 条 R3-01 pending-T-20 |
| `tools/contract/fixtures/layering/**` | 合法/违规 fixture |
| `tools/contract/test_check_layering.py` | 4 条 fixture 自测 |
| `tools/contract/measure_ack_latency.py` | MOCK_ONLY ACK p95 测量 harness（NFR 4.3 口径，不代表产品验收） |

### 14.4 结论

- 当前集成候选的**主机可执行证据充分**：696 host、66/66 契约、20/20 仿真器、i18n 0 blocking、分层 0 violation、构建/lint 通过。
- **不得声称**：设备/UI/BLE/LAN/TLS/云/视觉/fps 通过；ACK p95 达到 NFR 4.3；R3-01 已关闭；IG-3 已 READY。
- **下一步**：T-20 独立评审（含 R3-01/端口位置收口、SEC-N26、Mock 排除复核）→ T-21 README/维护计划 → T-22 IG-4/G-014。
