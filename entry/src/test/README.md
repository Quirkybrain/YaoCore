# Host 单元测试（无设备）

- **Producer**: agent:test-engineer (baseline) / agent:implementation-engineer（T-06..T-11、T-15/T-16 及修复 wp-018-fix-t07、wp-022-fix-t08、wp-026-fix-t09、wp-028-fix-t09b、wp-033-fix-t10、wp-035-transport、wp-060-vm）
- **Task**: T-05 / TEST-001（`wp-010-test-plan`）；T-06..T-11；**T-15/T-16 `wp-060-vm`（C-21..C-23 ViewModel host 套件，88 用例）**
- **状态**: **可运行（Node host runner）**；`hvigorw test` 的 Hypium 入口可编译，但本环境无法执行（见 §3）。

## 1. 目录与约定

```text
entry/src/test/
├── List.test.ets                 # Hypium host 入口（hvigorw test 固定导入）
├── HostBaseline.test.ets         # Hypium 冒烟（仅编译，未执行）
├── run-host-tests.sh             # 可运行的 Node host runner
├── host/
│   ├── HostBaseline.test.mjs     # 基线断言
│   ├── HostProtocol.test.mjs     # 向量/golden/SPKI host 测试
│   ├── ProtocolDiscover.test.mjs # 发现 canonical/映射
│   ├── ProtocolControl.test.mjs  # 控制 canonical/序列化
│   ├── ProtocolAck.test.mjs      # ACK 判定链
│   ├── ProtocolCloud.test.mjs    # 云 canonical
│   ├── ProtocolIdentity.test.mjs # 身份/SPKI
│   ├── DomainModels.test.mjs     # 域模型
│   ├── DomainDevice.test.mjs     # T-09 C-10 仲裁/墓碑/ACK/命令预检
│   ├── DomainRoom.test.mjs       # T-09 C-09 房间/删除事务/回滚/未分配池
│   ├── DomainScene.test.mjs      # T-09 C-11 场景串行/局部失败/取消
│   ├── DomainFamily.test.mjs     # T-09 C-08 家庭/成员/邀请/加入/RBAC
│   ├── domain-helpers.mjs        # T-09 值对象夹具
│   ├── Foundation.test.mjs       # 基础工具
│   ├── PerfHarness.test.mjs      # NFR 4.3 测量 harness
│   ├── Crypto.test.mjs           # T-07 C-04 host 测试（含 R-01 分类器/R-07 前缀副本）
│   ├── Security.test.mjs         # T-07 C-05 向量与负例
│   ├── Storage.test.mjs          # T-08 C-06 存储/迁移/draft/事务运行器（15 用例）
│   ├── GatewayRepository.test.mjs # T-08 C-07 路由/绑定/补偿/profile/sequence（29 用例）
│   ├── I18n.test.mjs             # T-10 C-14 locale/fallback/插值/复数/键映射/权威 catalog/CHK（28 用例）
│   ├── GatewayLocal.test.mjs     # T-11 C-17 discover/control/ACK/重试/TLS tri-state/DEV-ONLY（21 用例）
│   ├── GatewayDiscovery.test.mjs # T-11 C-18 LAST_KNOWN/mDNS/手动 IP/UDP seam/退避（19 用例）
│   ├── GatewayMock.test.mjs      # T-11 C-20 Mock 行为矩阵/TLS 四模式/MockBLE（17 用例）
│   ├── TransportBoundary.test.mjs # T-11 SC-11/D-04 生产边界静态检查（3 用例）
│   ├── ViewModelThrottle.test.mjs # T-15 55ms/TouchUp/cancel（5）
│   ├── ViewModelDevice.test.mjs   # T-15 三态/超时/连续控制/房间池（7）
│   ├── ViewModelCoordinator.test.mjs # T-15 LAN→云回退矩阵（7）
│   ├── ViewModelDoor.test.mjs     # T-15 门锁四阶段/10s/离线（9）
│   ├── ViewModelDoorVM.test.mjs   # T-15 DoorViewModel 控制组合（4）
│   ├── ViewModelHome.test.mjs     # T-15 Home 状态/过滤/环境（7）
│   ├── ViewModelClimate.test.mjs  # T-15 AC 状态/温度（4）
│   ├── ViewModelFamily.test.mjs   # T-16 家庭/RBAC/邀请/加入（10）
│   ├── ViewModelRoom.test.mjs     # T-16 房间 CRUD/删除保护/池（7）
│   ├── ViewModelScene.test.mjs    # T-16 场景进度/局部失败/取消（7）
│   ├── ViewModelBle.test.mjs      # T-16 配网 6 步/取消/R-1（11）
│   ├── ViewModelSettings.test.mjs # T-16 语言/云/单网关/手动 IP（10）
│   ├── viewmodel-helpers.mjs      # T-15/T-16 clock/timer/record/control fakes
│   ├── viewmodel-admin-helpers.mjs # T-16 family/join/room/scene fakes
│   ├── TransportFakes.ets        # T-11 clock/random/route/credential/transport fakes
│   ├── TestCryptoProvider.ets    # 测试专用纯 TS provider（仅 SHA/HMAC/HKDF/PBKDF2）
│   ├── protocol-oracle.ets       # 纯 TS canonical oracle（无 @ohos）
│   ├── ets-hooks.mjs             # Node loader：.ets -> TS strip -> ESM
│   └── register-ets.mjs
├── domain/
│   ├── DomainHarness.ets         # T-09 共享 fake RDB + O-1 gate 装配
│   ├── DomainFakes.ets           # T-09 Invite/Auth/Control/Route/Timer fakes
│   └── DomainHost.test.ets       # T-09 ArkTS 编译套件（仅编译）
├── foundation/                   # Hypium host 冒烟（仅编译）
├── protocol/                     # Hypium host 冒烟（仅编译）
├── security/
│   └── SecurityHost.test.ets     # T-07 C-04/C-05 Hypium 冒烟（仅编译）
├── storage/
│   ├── FakeStores.ets            # T-08 C-06/C-07 内存 fake（不默认成功）
│   └── StorageHost.test.ets      # T-08 Hypium 编译/冒烟（仅编译）
├── i18n/
│   ├── I18nFakes.ets             # T-10 loader/applier/preferences/logger fakes
│   ├── I18nHost.test.ets         # T-10 Hypium 编译/冒烟（仅编译）
│   ├── check_i18n.py             # CHK-01..CHK-09 可执行检查器（Python stdlib）
│   ├── allowlist.json            # CHK-05/CHK-07 允许清单（文件行 + 键前缀）
│   ├── legacy-migration.csv      # 615 条旧字典逐条迁移登记表
│   ├── migration-boundary.md     # 迁移边界/批次/判据
│   └── fixtures/{good,bad}/      # 检查器正负夹具
└── evidence/                     # 运行日志（当前 revision 证据）
```

约定：

1. `entry/src/test/host/**` 的测试**不得** import `@ohos.*`、ArkUI 装饰器或 `struct`。
2. 纯逻辑产品模块应能在 host 加载；Node loader 支持 `.ets`/`.ts`（TypeScript 语法），但 UI/平台文件不可加载。
3. Hypium `List.test.ets` 只做 suite 聚合；每个 `*Suite` 导出同名函数（DES-A §23.1）。
4. 新增测试时同时保留 Requirement/Contract/component ID 注释（traceability）。
5. `code-linter.json5` 忽略 `src/test/**` 与 `src/ohosTest/**`；`codelinter` 的 PASS 只覆盖产品源码，不覆盖测试源码。

## 2. 可运行命令（推荐）

```bash
cd /home/quirkybrain/code/harmony-projects/YaoCore
entry/src/test/run-host-tests.sh
```

等价命令：

```bash
node --no-warnings \
  --import ./entry/src/test/host/register-ets.mjs \
  --test --test-reporter=tap \
  entry/src/test/host/*.test.mjs
```

当前 revision：**593/593 PASS**（T-15/T-16 新增 88；T-14 修复基线 505）。T-15/T-16 覆盖：

- 4 条控制 HMAC 向量（canonical + HMAC-SHA256）与 T-06 出站 nonce/值类型严格门；
- 响应验签向量、发现请求签名向量；
- golden discover / ACK / replay 结构断言与 ACK 严格 schema 负例；
- `valueAtom` 语义；
- 测试证书 SPKI-SHA256 与 Python 仿真器 pin 一致；
- NFR 4.3 测量 harness（percentile/样本/报告分类）；
- T-07 C-04：SHA/HMAC/HKDF/PBKDF2 对照 Node/RFC 向量、X25519 DER↔raw 对照 Node JWK、常数时间行为、CTR 状态机、GCM 标签/长度负例、随机长度/不可用；
- T-07 C-04 R-01/R-07 修复：分层错误分类器（CREATE/KEY_CONVERSION/OPERATION/GCM tag）、X25519 前缀防御性副本；
- T-07 C-05：V-01 4/4、发现/响应向量、correlation/nonce/TTL/±120s 负例与 ACK 链组合；
- T-08 C-06（15）：draft 复制/一次性/TTL/clearAll/非法 TTL、迁移 0→2/重复/缺口/失败回滚/拒绝降版本、v1 初始化/幂等/close、secret 副本清零与 alias 语法、`RdbTransactionRunner` begin 失败映射与状态复位；
- T-08 C-07（29）：HMAC/TLS 绑定、短/超长 draft secret 拒绝（R-01）、draft 重放/不匹配/家庭迁移负例、route/secret 补偿与 fail-closed、secret 写失败、复用路径、markSeen/回读 post-commit 语义（R-05）、邀请幂等、P-BLOCKED 拒绝、TLS→HMAC、多 pin 收缩/未知 pin、轮换成功/失败/异常、initialize 清理 pending、本机解绑、sequence 读/增/重置/上限/40 并发、路由列表/家庭索引/地址更新、未绑定错误、秘密泄漏审计；
- T-09 C-08（27）：家庭创建/activeFamily、切换锁会话/档案、RBAC 矩阵/actor 拒绝、最后 ADMIN、转让、GUEST 到期/续期、邀请/回执状态机（D-022 多回执）、撤销/过期、回执失败不留成员（R-01）、同回执重放拒绝且不消耗 use（R2-01，KEY_WRAP/CODE_KEK）、owner 防降级/移除（R-09）、多网关解散/退出（R-08）、加入会话 KEY_WRAP/CODE_KEK、接触式收敛、退出/解散/profile 清理；
- T-09 C-09（10）：房间创建/改名/ID 不变、排序校验、指派/换房/未分配池、删除预览/确认竞态、删除事务（设备禁用+授权清理）、失败回滚、空/最后房间、监听器抛错隔离、零网络、v4 静态迁移注册幂等（R-06）；
- T-09 C-10（24）：发现新增未分配/禁用、陈旧包整条丢弃、同 epoch 覆盖、缺字段保留/离线不清空、partial 不标记网关移除、aliasUsed 仅诊断、未知类型只读、tombstone/restore、设备删除场景清理/回滚、ACK 应用/陈旧/不匹配/重放、applyCloudState 边界、跨家庭 assign 拒绝（R-07）、未绑定/家庭不匹配/重复 partial（R-14）、监听器隔离/commit 失败无事件（R-12）、commit 失败回滚诊断缓存（R2-05）、网关删除路由事务外读取（R-13）、命令预检含 UNASSIGNED、事件后置派发；
- T-09 C-11（15）：场景 CRUD/值校验、串行成功/事件、预检 0 命令、首步/次步失败、局部失败不回滚、MISMATCH/UNVERIFIED（MISMATCH 回写 SSOT，R-03）、delayMs、取消、same-scene 单飞（R-02）、step/total timeout（R-05）、迟到 outcome 丢弃、监听器抛错隔离、房间删除后预检失败、禁用/空场景；
- T-09 O-1（5）：gate 串行、合法排队在超时内成功（D-023/R2-02）、同步重入 fail-fast、异步重入有界失败、fake RDB 嵌套事务 fail-fast（R-04）；
- T-10 C-14（28）：auto locale 解析（zh/en/其他/读取失败）、fallback 链与 missing 诊断、插值/缺参数/单次替换、英文 `_one/_other`/中文基键/缺变体回退、setLocaleMode 持久化+通知、apply 失败 `platformApplied=false`、加载失败回滚、Preferences 失败、reload 重解析、监听器隔离/退订、dispose、`has`/`tKey`、bundle codec 负例、I18nKeys/ErrorI18nMapper、权威 catalog 派生（DES-A §3.2.3 + DES-B §23.4）、5 个动态 code 双 locale 渲染、生产资源 parity、CHK good/bad 夹具与 exit 2、current-only/base-only/both 缺失降级；
- T-11 C-17（21）：discover/control 全链、P-HMAC/P-TLS-PIN/P-BLOCKED、pin 缺失/不匹配禁回退、明文禁用、DEV-ONLY 先于验签、精确重传（同 body/nonce/seq）、300/900 重试、签名/correlation/缺 reported_state/目标不一致负例、`send` 路由装配、ControlPolicy 矩阵；
- T-11 C-18（19）：LAST_KNOWN 成功/失败隔离/identity/profile 不符、去重排序、mDNS hint/无 hint/扫描失败、手动 IP 绑定/非法/限频/失败预算、UDP PB-01 warning 与 locator-only、超时/取消、ProbeBackoff 500/1000/2000/4000/8000；
- T-11 C-20（17）：normal/offline/ack-lost/replay/timeout/dev-only、TLS pin-match/pin-mismatch/handshake-fail、resultCode/omitReportedState/badSignature/badCorrelation、failAtAttempt、MockBLE 正常/v2.1/离线/超时/取消；
- T-11 边界（3）：生产树无 Mock/ohosTest import、Mock TEST ONLY 标记、纯逻辑 gateway 无 `@ohos`/`@kit`；
- host runner 基线断言；
- T-15（43）：ThrottleGate 55ms/在途/latest/TouchUp/cancel/failure；DeviceViewModel 三态/MISMATCH/超时/连续/取消/筛选；DeviceControlCoordinator LAN 成功/回退边界/云 Token/UNSUPPORTED；DoorConfirmationTracker 四阶段/10s 在线离线/无关联/开门报警；DoorViewModel；Home 状态/环境/过滤/解锁；Climate AC；
- T-16（45）：Family RBAC/F-08/GUEST 房间范围/切换解锁/创建档案/加入状态机/CODE_REQUIRED/弱模式；Room 预览/确认计数竞态/删除事务结果/指派；Scene 进度/局部失败/noRollback/cancel/单飞；BLE 6 步映射/权限/扫描去重/取消清理/R-1 `result.credentialDraftId`/retry；Settings 语言/云单网关 F-06/token/手动 IP/安全档案/Preferences。

计数口径：T-11 新增 60 条（21+19+17+3）；T-10 基线 275；当前总数 **335**。

T-08 修复前基线为 **161/161 PASS**（`evidence/t08-host-node-tests.tap`）；T-06 修复时基线为 **88/88 PASS**（`evidence/t06-fix-host-node-tests.tap`）；T-05 历史基线为 **15/15 PASS**（`evidence/host-node-tests.tap`）。这些旧数字仅代表当时范围，不代表当前 revision。

T-11 传输发现/Mock 证据（wp-035-transport，当前 revision）：

| 文件 | 内容 |
|---|---|
| `evidence/t11-host-node-tests.tap` | 当前 335/335 TAP |
| `evidence/t11-ohpm-install.log` | `ohpm install` |
| `evidence/t11-clean-assemble.log` | `hvigorw clean assembleHap --no-daemon` |
| `evidence/t11-codelinter.log` | `codelinter -c code-linter.json5 -p default .`（产品源码） |
| `evidence/t11-ohosTest-assemble.log` | 附加：ohosTest HAP 编译（不等于设备执行） |

T-10 评审修复证据（wp-033-fix-t10，历史 revision）：

| 文件 | 内容 |
|---|---|
| `evidence/t10-fix-host-node-tests.tap` | 当前 275/275 TAP |
| `evidence/t10-fix-ohpm-install.log` | `ohpm install` |
| `evidence/t10-fix-clean-assemble.log` | `hvigorw clean assembleHap --no-daemon` |
| `evidence/t10-fix-codelinter.log` | `codelinter -c code-linter.json5 -p default .`（产品源码） |
| `evidence/t10-fix-i18n-checker.log` | CHK-01..09；0 阻断、2 条短英文 UI 告警 |
| `evidence/t10-fix-i18n-report.json` | 检查器 JSON 报告 |

T-09 复审修复证据（wp-028-fix-t09b，历史 revision；当前总数已由 T-10 修复取代）：

| 文件 | 内容 |
|---|---|
| `evidence/t09-fix2-host-node-tests.tap` | 当前 247/247 TAP |
| `evidence/t09-fix2-ohpm-install.log` | `ohpm install` |
| `evidence/t09-fix2-clean-assemble.log` | `hvigorw clean assembleHap --no-daemon` |
| `evidence/t09-fix2-codelinter.log` | `codelinter -c code-linter.json5 -p default .`（产品源码） |
| `evidence/t09-fix2-hvigor-test-compile.log` | `hvigorw test` UnitTestArkTS 编译成功（8 s 240 ms）；随后 Previewer 等待超时 exit 124（附加编译证据） |

T-09 修复证据（wp-026-fix-t09，历史 revision）：

| 文件 | 内容 |
|---|---|
| `evidence/t09-fix-host-node-tests.tap` | 243/243 TAP（wp-026-fix-t09） |
| `evidence/t09-fix-ohpm-install.log` | `ohpm install`（修复 revision） |
| `evidence/t09-fix-clean-assemble.log` | `hvigorw clean assembleHap --no-daemon`（修复 revision） |
| `evidence/t09-fix-codelinter.log` | `codelinter -c code-linter.json5 -p default .`（产品源码） |
| `evidence/t09-fix-hvigor-test-compile.log` | `hvigorw test` UnitTestArkTS 编译成功；Previewer 仍 BLOCKED（附加证据） |

T-09 初版证据（wp-024-domain，历史 revision）：

| 文件 | 内容 |
|---|---|
| `evidence/t09-host-node-tests.tap` | 历史 216/216 TAP（wp-024-domain） |
| `evidence/t09-clean-assemble.log` | `hvigorw clean assembleHap --no-daemon`（wp-024-domain） |
| `evidence/t09-codelinter.log` | `codelinter -c code-linter.json5 -p default .`（wp-024-domain） |
| `evidence/t09-hvigor-test-compile.log` | `hvigorw test` UnitTestArkTS 编译成功；Previewer 仍 BLOCKED |
| `evidence/t09-ohosTest-compile-probe.log` | 临时注册设备骨架后的 ohosTest 编译通过（注册本身不在该任务写范围） |
| `evidence/t08-fix-host-node-tests.tap` | 历史 166/166 TAP（wp-022-fix-t08） |
| `evidence/t08-fix-ohpm-install.log` | `ohpm install`（修复 revision） |
| `evidence/t08-fix-clean-assemble.log` | `hvigorw clean assembleHap --no-daemon`（修复 revision） |
| `evidence/t08-fix-codelinter.log` | `codelinter -c code-linter.json5 -p default .`（产品源码） |
| `evidence/t08-fix-ohosTest-assemble.log` | 附加：ohosTest HAP 编译（不等于设备执行） |
| `evidence/t08-host-node-tests.tap` 等 | T-08 初版证据（历史 revision） |

## 3. `hvigorw test` 的真实状态：BLOCKED（环境）

```bash
export DEVECO_SDK_HOME=/home/quirkybrain/harmonyos/command-line-tools/sdk
hvigorw test --no-daemon
```

实测（当前 revision）：

1. `UnitTestArkTS` **编译成功**（`entry/src/test/List.test.ets` 已存在，之前的“缺少 List.test”根因已消除）。
2. 随后 hvigor 启动 SDK 的 Linux Previewer；默认环境立即失败：
   `error while loading shared libraries: libshared_libz.so: cannot open shared object file`
   （`evidence/previewer-default-env.log`）。
3. 用临时 `/tmp` shim 补齐 `libshared_libz.so`（仅环境实验，不改仓库/SDK）后，Previewer 能启动，
   但返回：
   `JsApp::Run ability start failed.Linux is not supported.`
   （`evidence/previewer-with-lib-shim.log`），且不生成 `test_result.txt`；
   hvigor 进程一直等待，45s 超时退出（`evidence/hvigor-test-default-timeout.log` / `hvigor-test-with-lib-shim.log`）。

   复现 shim（可选，仅为确认根因；不会让测试执行）：

   ```bash
   mkdir -p /tmp/opencode/yaocore-t05/previewer-shim
   ln -sf /lib/x86_64-linux-gnu/libz.so.1 \
     /tmp/opencode/yaocore-t05/previewer-shim/libshared_libz.so
   export LD_LIBRARY_PATH="/tmp/opencode/yaocore-t05/previewer-shim:\
   /home/quirkybrain/harmonyos/command-line-tools/sdk/default/openharmony/previewer/common/bin:\
   /home/quirkybrain/harmonyos/command-line-tools/sdk/default/hms/toolchains/lib"
   hvigorw test --no-daemon   # still BLOCKED at "Linux is not supported"
   ```
4. 因此：**没有 Hypium 用例在 host 运行时通过**。不得把 `UnitTestArkTS` 编译成功写成测试 PASS。

结论：`hvigorw test` 在本 Linux 环境的阻塞是 **Previewer 运行时限制 + SDK 预览器缺库**，不是测试代码/断言失败；
Node host runner 是本环境唯一已实证的可执行 host 路径，覆盖纯逻辑层；平台适配器/设备测试仍需设备。

## 4. 与 ohosTest 的边界

| 层 | 路径 | 运行条件 | 当前 |
|---|---|---|---|
| Host 纯逻辑 | `entry/src/test/host/**` | Node（无设备） | **PASS 335/335**（T-11） |
| Hypium host | `entry/src/test/List.test.ets` | `hvigorw test` + Linux Previewer | **BLOCKED**（见 §3） |
| 设备/模拟器 | `entry/src/ohosTest/**` | `onDeviceTest` + 设备 + 签名 | **BLOCKED**（见 ohosTest README；storage 套件已注册但未执行） |

## 5. 证据纪律

- 每次修复/变更后重跑 `run-host-tests.sh`，把 TAP 输出保存到 `evidence/` 或 T-19 报告；
- 测试失败必须保留命令、退出码、失败断言；不得删除断言换 PASS；
- host 测试通过不等于产品验收；性能/真实网络/真实 BLE/UI 渲染仍标 `UNAVAILABLE`；
- `codelinter` 不覆盖测试源码，报告“静态检查通过”时须限定为产品源码。
