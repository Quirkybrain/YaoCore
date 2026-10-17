# T-08 独立 Code Review：C-06 存储服务 + C-07 GatewayRepository

- **Artifact ID**: REV-T08-001
- **Producer**: agent:quality-reviewer
- **Type**: Independent Code Review / CQG-T08 Evidence
- **Status**: CHANGES_REQUIRED（独立评审完成；不授予 PASS、STABLE、CQG-T08 完成或 Stage/用户验收）
- **Date**: 2026-10-17
- **Task**: `wp-021-review-t08`（task 分支 `task/wp-020-storage`，父分支 `feat/yaocore-app`，base commit `66b6e1d48f1e4e920d8d79e43748bcc5b58ae9af`，parent `0713aca8f6b4e8a326f94842eb21bc3df61fd444`）
- **Workflow**: STANDARD / GATED_AUTO
- **Reviewed revision**: `66b6e1d48f1e4e920d8d79e43748bcc5b58ae9af`（26 路径：C-06 11 文件、C-07 2 文件、测试/证据/实现报告）
- **Review scope**: `entry/src/main/ets/service/storage/`、`entry/src/main/ets/repository/`、`entry/src/test/`、`entry/src/ohosTest/ets/test/storage/`、`artifacts/50-implementation/t08-storage.md`
- **Review snapshot**: `refs/swe/snapshots/20261017T092605Z-wp-021-review-t08-b87a84b0`（commit `6e2f6ff437ba1dd354f8b37f984947413d803a56`；manifest 覆盖上述产品目录、测试目录与 `artifacts/`）
- **Independence**: 本报告由未参与 T-08 实现的质量评审者（`agent:quality-reviewer`）编写；T-08 作者为 `agent:implementation-engineer`。作者之外独立裁决，作者不能批准本报告或自行关闭本评审。

> 结论先行：C-06/C-07 的结构、命名、错误命名空间、补偿事务、draft 生命周期、pin 规则与秘密边界总体实现质量较高；构建、静态检查、Node host 测试（161/161，新增 39）均可复现。但发现两处 **Medium**：`commitBinding` 的 draft 路径可以持久化短于 16 字节的命令密钥（违反 SC-04 Must，评审探针已实证 1 字节 secret 成功绑定）；`RdbStoreAdapter` 在 `beginTransaction()` 抛错时不会复位 `inTransaction`，此后所有事务永久失败且泄漏平台原始错误。另有一组 Low 级证据/集成问题（设备套件未注册、报告文件计数错误、README 过期、post-commit 失败语义等）。故判 **CHANGES_REQUIRED**；设备/真实 Asset Store/RDB 证据仍为 `COMPILED_ONLY`/`BLOCKED`，本次评审不授予 CQG-T08 或 STABLE。

---

## 1. 评审范围、输入与方法

### 1.1 范围

| 类别 | 路径 | 本次核对 |
|---|---|---|
| C-06 产品代码 | `entry/src/main/ets/service/storage/**` | 11 文件：`PreferencesStore`、`RdbStore`、`SecretStore`、`SecretDraftPort`、`MigrationPort`、`MigrationRegistry`、`SecretDraftStore`、`StorageService`、`PreferencesStoreAdapter`、`RdbStoreAdapter`、`AssetStoreSecretStore` |
| C-07 产品代码 | `entry/src/main/ets/repository/**` | 2 文件：`GatewayPorts`、`GatewayRepository` |
| Host 测试 | `entry/src/test/host/{Storage,GatewayRepository}.test.mjs`、`entry/src/test/storage/FakeStores.ets`、`StorageHost.test.ets`、`List.test.ets` | 39 个新用例（C-06 14 + C-07 25）；fake 边界；Hypium 编译入口 |
| 设备骨架 | `entry/src/ohosTest/ets/test/storage/StorageDevice.test.ets` | `BLOCKED_ON_DEVICE_RUNNER`；Preferences/RDB/Asset 适配器骨架 |
| 证据/报告 | `entry/src/test/evidence/t08-*`、`artifacts/50-implementation/t08-storage.md` | 与命令输出逐项核对 |

`git show --name-only 66b6e1d` 核对：26 个变更路径均在 `wp-020-storage` 的 `commit_paths` 内；没有越界修改 `common/**`、`model/**`、`service/protocol/**`、`service/crypto/**`、构建配置或 `input/**`。评审开始时工作树 clean；本次评审唯一受版本控制的写入是本报告（构建只写 `.gitignore` 覆盖的 `entry/build`/`.hvigor` 输出）。

> 实现报告两处写 C-06 为 "12 文件"（`t08-storage.md:25,42`），实际为 11 文件；见 R-06（Low，不影响代码结论）。

### 1.2 权威输入 pin

| 输入 | SHA-256 核对 |
|---|---|
| `artifacts/50-implementation/t08-storage.md` | `913e7a371f837c30bdd5f99ad6668e1209c057b149fe25ed12f7dd2acdb39489`，与 handoff 一致 |
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `5599e693fafe405443c5d28efaec0bd2091064eee5c3f1a619dc22d3dcbfe1c1`，一致 |
| `artifacts/20-architecture/adr-002-lan-security-channel.md` | `67943a6e1d8dc78d3ad974e4aa17ca984588ac673cf1cda3447eefbb80d1c86f`，一致 |
| `artifacts/20-architecture/contract-baseline.md` | `6673a990d5020c0b70dd4ae30bd75fa13d33d4d573a4d953961371296fadee89`，一致 |
| `artifacts/20-architecture/project-constraints.md` | `283046210e68dfbce9119abbbac849bd1f9a23cf7ef2fb51dcb4aa1e23da9528`，一致 |
| `artifacts/60-testing/test-plan.md` | `33485cc39abd9a917e94b6568b29e162cd90897adfad509e3f59403a56055fae`，一致 |

### 1.3 明确排除

以下不属于本次 T-08 结论，且不写成 PASS：

- 真实 `@ohos.security.asset`、`@ohos.data.relationalStore`、`@ohos.data.preferences` 的设备运行（无设备/无签名；`onDeviceTest` 为 `BLOCKED`）。
- `hvigorw test` 的 Hypium 运行时（Linux Previewer 限制；仅 `COMPILED_ONLY`）。
- C-17/T-11 的运行期 P-BLOCKED 选择、HTTPS/TLS 实际连接、`gateway.bound`/轮换事件发布。
- C-18/C-19/C-23 的发现、BLE 配网、身份协商、绑定编排；本任务只提供存储/路由端口。
- C-08/T-09 的 FamilyRepository 迁移与 RDB 复用；C-10 的 `gw_dismissed_device` 读写。
- CQG-T08 的最终通过、C-06/C-07 `STABLE`、Stage Gate 或用户验收。
- i18n 资源包实现（T-08 没有新增 UI 文案；错误 key 由 `ErrorCatalog` 解析，资源落地归后续 i18n 任务）。

### 1.4 方法

1. **Diff first**：先读 `0713aca..66b6e1d` 的 26 文件，再读周边 `SecureBytes`、`BytesUtil`、`Utf8`、`AppError`、`GatewayRoute`、`ProvisioningModels`、`ProtocolConstants`、`StorageConstants`。
2. **逐条对照**：DES-A §9/§10/§22、ADR-002 §4/§6/§8.3/§8.4、CB §4/§7、PC SC-04/SC-09/SC-12/PR-06/FC-03、TEST-001 §2-§5。
3. **边界追踪**：draft 输入 → Asset Store → `gw_route` → 读取/回调清零；secret alias 生命周期；迁移事务/版本；route 补偿；pin 收缩；sequence 并发/上限。
4. **只读复验**：`entry/src/test/run-host-tests.sh`、`codelinter`、`hvigorw clean assembleHap`、ohosTest HAP 编译、`git show/diff --check/status`。
5. **独立探针（/tmp/opencode，不写仓库）**：短 secret 绑定（R-01）；`markSeen` 失败后的提交状态（R-05）。
6. **安全扫描**：产品代码无 `console`/`hilog`/`print`；无硬编码生产 secret/证书/Token；`@ohos.security.asset` 仅出现在 `AssetStoreSecretStore`，`@ohos.data.relationalStore` 仅出现在 `RdbStoreAdapter`，`@ohos.data.preferences` 仅出现在 `PreferencesStoreAdapter`。

> 评审者未修改任何被测文件；构建/lint 只产生被 `.gitignore` 忽略的 `entry/build`、`.hvigor`、`oh_modules` 输出；`git status --short` 在写入本报告前为空。

---

## 2. 独立复验结果

| 命令 | 结果 | 与实现报告/证据对比 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS 161/161**，`# tests 161`、`# pass 161`、`# fail 0`，exit 0，`duration_ms 1300.288334` | 与 `t08-host-node-tests.tap` 的 161/161 一致；新增 39（C-06 14 + C-07 25） |
| `codelinter -c code-linter.json5 -p default .` | **PASS**，`No defects found in your code.`，exit 0 | 与 `t08-codelinter.log` 一致；注意 `code-linter.json5` 忽略 `src/test`/`src/ohosTest`，不覆盖测试源码 |
| `hvigorw clean assembleHap --no-daemon` | **PASS**，`BUILD SUCCESSFUL in 5 s 202 ms`，35 tasks（34 executed / 1 up-to-date），exit 0；仅 unsigned HAP warning | 与 `t08-clean-assemble.log` 的 5 s 530 ms/35 tasks 一致（正常时间浮动） |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **PASS**，`BUILD SUCCESSFUL in 6 s 616 ms`，35 tasks，exit 0 | 与 `t08-ohosTest-assemble.log` 一致；只证明测试 HAP 可编译，不证明设备执行 |
| `git show --stat 66b6e1d` | 26 files changed，5380 insertions(+) | 与 handoff/实现报告一致；全部路径在 commit scope 内 |
| `git diff --check 0713aca..66b6e1d` | 无输出 | 无空白错误 |
| `git status --short`（评审开始） | clean | 无未提交构建产物/测试改动 |
| 输入 SHA-256 | 6/6 与 handoff 一致 | 无输入漂移 |
| `hvigorw test` / `onDeviceTest` | **未重跑**；同 revision 证据为 `UnitTestArkTS` 编译成功 + `> hvigor Linux`（124）与 `BLOCKED` | 不把 `COMPILED_ONLY` 写成 PASS；设备/Previewer 仍是已知环境限制 |

补充核对：

- `entry/src/test/evidence/t08-host-node-tests.tap` 中 C-06/C-07 subtest 各 14/25，无重复，`# fail 0`。
- `entry/src/test/evidence/*` 只含命令输出和公开测试数据，未发现真实 secret、证书、Token 或构建产物；`entry/build/`、`.hvigor/`、`oh_modules/` 均被 ignore。
- `StorageHost.test.ets` 通过 `import '../../ohosTest/ets/test/storage/StorageDevice.test'` 把设备骨架拉入 host 编译图；这只证明可编译，不证明设备可执行。
- 独立探针一：`SecretDraftStore.put(SecureBytes.fromHex('00'))` → `commitBinding` 成功，`withCommandSecret` 读出长度 1（R-01 证据）。
- 独立探针二：注入 `markSeen` 的 RDB UPDATE 失败后，`commitBinding` 抛 `STORAGE_RDB_ERROR`，但 route 已存在、secret 已写入、draft 已消费（R-05 证据）。

---

## 3. Findings

> 严重度：**Critical** = 可导致错误成功/密钥泄漏/不可恢复数据损坏；**High** = 明确安全或核心协议破坏；**Medium** = 冻结契约不一致或安全生命周期缺口，有明确修复路径；**Low** = 严格性、测试集成、文档或防御性缺口。

| ID | 严重度 | 位置 | 问题 | 违反契约/约束 | 修复建议 |
|---|---|---|---|---|---|
| **R-01** | **Medium** | `entry/src/main/ets/repository/GatewayRepository.ets:196-235`（draft 路径，`secrets.put` 在 212）；`entry/src/main/ets/service/storage/SecretDraftStore.ets:49-57` | `commitBinding` 在 `draftId` 非空时直接 `take` 并写入 Asset Store，未校验命令密钥长度；`SecretDraftStore.put` 也接受任意长度。独立探针已实证 1 字节 secret 可成功绑定并读出。`InvitedGateway` 构造器（`GatewayPorts.ets:73-75`）与 `rotateSecret`（`GatewayRepository.ets:388-390`）均强制 ≥16B/16..4096，只有 draft 路径缺失，属明显不对称。 | **SC-04（Must）**：每台网关 HMAC 密钥 ≥16 字节；ADR-002 §8.2；DES-A §22.2 `yaocore.gateway.hmac.<gatewayId>` = 原始 command secret 字节（≥16B）；DES-A §10.3 绑定语义 | 在 `commitBinding` 取到 draft 后、写 Asset Store 前校验 `draft.length ∈ [16, 4096]`，失败即销毁 draft 且不写 secret/route（建议 `CONFIGURATION_ERROR`，与 `rotateSecret` 一致）；或把下限校验集中到 `SecretDraftStore.put` 并在复用路径 `probeSecret` 也检查长度。补短 secret/超长 secret 负例；报告需说明错误码选择。 |
| **R-02** | **Medium** | `entry/src/main/ets/service/storage/RdbStoreAdapter.ets:107-128`（`beginTransaction()` 在 113，`try/finally` 从 114 开始） | `store.beginTransaction()` 位于 `try` 之外。若平台在该调用抛错：1) 原始 `BusinessError` 直接逃逸，未映射为 `AppError`/`STORAGE_RDB_ERROR`；2) `inTransaction` 保持 `true`，此后所有 `transaction()` 调用都因 `if (this.inTransaction)` 永久失败，直到进程重启。 | DES-A §9.1.2：`transaction` 异常必须 `rollBack` 并重抛 `AppError`；§9.2：RDB 失败 → `STORAGE_RDB_ERROR`；§9.3 事务原子性/可恢复性 | 将 `beginTransaction` 纳入 `try`，在 `catch/finally` 中复位 `inTransaction` 并把错误映射为 `STORAGE_RDB_ERROR`；仅在 begin 成功后进入 `commit/rollBack` 路径。增加可注入的底层 store/fake seam 验证 begin 失败后状态复位；同时评估重入（见 O-1）。 |
| **R-03** | **Low** | `entry/src/ohosTest/ets/test/storage/StorageDevice.test.ets:44-73`；`entry/src/ohosTest/ets/test/List.test.ets:10-16`；`artifacts/50-implementation/t08-storage.md:180-186,239-244` | `StorageDevice.test.ets` **未注册**进 ohosTest 的 `List.test.ets`（当前只 import baseline/foundation/security），即使设备可用，`onDeviceTest` 也不会执行它。此外设备 RDB 用例只测试了数据回滚和独立 `setVersion(version+1)`，**没有**测试“`setVersion` 在事务内失败后回滚”；也没有测试锁屏/`ASSET_ACCESS_DENIED`，而报告 R-T08-03/R-T08-04 写“设备用例覆盖事务回滚与版本”“设备用例/安全评审”，覆盖声明强于骨架实际。 | TEST-001 §2.3/§4.3；D-019 host/device 分层；报告证据诚实性 | 由 T-19/后续设备任务把 `storageDeviceTest` 注册进 `ohosTest/.../List.test.ets`（或扩展本任务范围）；增加“事务内 `setVersion` + 后续语句失败 → 版本和表均回滚”用例，以及锁屏/`ASSET_ACCESS_DENIED`（环境允许时）；在此之前把报告措辞改为“设备骨架待接线；版本回滚/锁屏尚未覆盖”。 |
| **R-04** | **Low** | `entry/src/test/README.md:10-20,61,115` | Host 测试 README 仍写“当前 revision 122/122 PASS”，目录树也未列出 `Storage.test.mjs`、`GatewayRepository.test.mjs`、`FakeStores.ets`、`StorageHost.test.ets`、`StorageDevice.test.ets` 与 `t08-*` 证据；与当前 161/161 不一致。 | TEST-001 §5/§10 证据纪律；实现报告 §3/§4 的 161/161 | 更新为 161/161（`t08-host-node-tests.tap`），补 T-08 目录/用例/证据说明，并注明 `codelinter` 不覆盖测试源码。 |
| **R-05** | **Low** | `entry/src/main/ets/repository/GatewayRepository.ets:217-228`（`markSeen` 在 224、`readRoute` 在 225；复用路径 187-193 同类） | `writeRoute` 成功后，`markSeen` 或随后 `readRoute` 的失败会被当成 `commitBinding` 整体失败抛出；但 route 与 secret 已持久化，draft 已消费。独立探针确认：`markSeen` 失败后 route 存在、secret 存在、draft 已消费，重放同 draft 得到 `PROVISIONING_SECRET_DRAFT_EXPIRED`。DES-A §10.3 第 9 步未定义 post-commit 失败的补偿，调用方可能误判绑定失败。 | DES-A §10.3 步骤 9；§10.1 `commitBinding` 成功语义；错误/恢复一致性 | 将 `markSeen` 视为 post-commit best-effort（失败记录/忽略，或把 `last_seen_at/updated_at` 合并进 route INSERT），或明确文档化“route 已存在即视为绑定成功，可用空 draft 走复用路径恢复”；补失败注入用例。 |
| **R-06** | **Low** | `artifacts/50-implementation/t08-storage.md:25,42` | 报告两处称 C-06 为“12 文件”，实际 `service/storage/` 为 11 文件，§1.1 代码块也只列 11 项；26 路径统计因此自相矛盾。 | 实现报告自我一致性/证据准确性（与 T-07 R-06 同类） | 改为 11，并复核所有文件计数；无需改代码。 |
| **R-07** | **Low** | `entry/src/main/ets/repository/GatewayRepository.ets:314-347`；DES-A §10.4 持久 profile 迁移表 | `setPersistentProfile` 允许直接把 P-TLS-PIN 写成 P-HMAC（测试也明确覆盖 TLS→HMAC），但 §10.4 表把 P-TLS-PIN→P-HMAC 归因于“rebind v2.0（用户显式重新配网）”；仓库无法判断调用是否来自 rebind。若 C-17 在 TLS 校验失败时调用该方法，就会形成持久明文回退，违反 ADR-002 §6.2 “禁止自动/静默回退”。当前代码本身不会自动降级，风险在调用边界。 | DES-A §10.4；ADR-002 §6.2；SC-09/安全档案纪律 | 在 C-17/T-11 约定并测试：TLS 失败只能进入运行期 P-BLOCKED，绝不调用 `setPersistentProfile(P_HMAC)`；为方法补充注释/契约约束。若架构希望仓库层强制，需要新增“rebind 证据”参数或由 `commitBinding` 独占 profile 迁移，另立契约修订，不在本次代码评审中重设计。 |

### 3.1 非阻塞观察（不作为 blocking finding）

1. **O-1 事务隔离/重入**：`RdbStoreAdapter` 只串行化 `transaction()`（36-72、107-128）；普通 `execute/query` 未进入同一队列，理论上可在事务等待期间落到同一连接上，参与该事务的提交/回滚。嵌套 `transaction()` 会先排队到外层链尾，`inTransaction` 检查实际不可达，可能死锁而非快速拒绝。当前 C-06/C-07 路径没有嵌套调用；C-08/T-09 复用 `RdbStore` 前应明确“禁止嵌套/单飞”或统一串行化所有操作。
2. **O-2 §10.2 端口错误码**：§10.2 写“非法 pin/port → `TLS_PIN_CONFIG_INVALID`”，但 C-02 的 `GatewayAddress`/`ProvisioningTlsMaterial` 对非法 port 抛 `PROTOCOL_VALUE_OUT_OF_RANGE`（`GatewayRoute.ets:17-20,117-125`；`ProvisioningModels.ets:21-24`），C-07 复用模型后实际返回后者。两者是详细设计内部不一致，建议由 solution-architect/契约 owner 裁定，不在 T-08 单方面改码。
3. **O-3 测试缺口**：`C07_removeLocalBinding_deletesRouteSecretsAndSequenceWithoutNetwork` 的 `transport = { calls: 0 }` 从未注入仓库，SC-12 断言是结构性的而非行为性的；未覆盖 `rotateSecret` active 写入失败、`applyInvitedGateway` route 写入失败、`markSeen` 失败、短 secret（R-01）与 begin 失败（R-02）。建议在修复时补高价值负例。
4. **O-4 已记录偏离**：端口位置（`contracts/**` → 实现目录）、draftId 生成（clock+counter，非凭据）、`commitBinding` 校验顺序（先 family 后 take draft）、pin 轮换事件延后、`StorageService.close()` 不关平台句柄、`removeLocalBinding` 先删 secret 再删 RDB、`nextSequence` 上限保守报错，均与实现报告 §5.1 一致；未发现第二套实现或明文回退。C-17/DES-B/T-19 需关闭事件、组合根与序列重置项。

---

## 4. 契约对照

### 4.1 DES-A §9 C-06

| 契约条目 | 结果 | 说明/证据 |
|---|---|---|
| §9.1.1 `PreferencesStore` | **PASS** | 端口/适配器形状一致；只做 Map/字符串；无 secret 调用点；`getString` 把空串视为 `undefined`（非契约键，低风险）。 |
| §9.1.2 `RdbStore`/事务/版本 | **PARTIAL（R-02）** | 端口；事务链串行、begin→fn→commit、异常 rollback；但 `beginTransaction` 抛错路径未复位/未映射（R-02），普通 execute/query 未串行（O-1）。 |
| §9.1.3 `SecretStore`/alias/withSecret | **PASS（带 R-01）** | alias `^[a-zA-Z0-9._-]{1,127}$`；`put` 覆盖；`withSecret` finally 清零副本；`list` 只返回 alias；无明文回退。长度校验缺口在 draft→binding（R-01）。 |
| §9.1.4 `StorageService`/`MigrationRegistry` | **PASS（host）** | v1 DDL 字段逐项一致；`setVersion` 与 DDL 在同一 `rdb.transaction` 内；版本连续、重复注册/缺口/高版本均失败；失败回滚（host fake 验证）。真实 `store.version` 事务语义见 R-T08-03/R-03。 |
| §9.1.5 `SecretDraftPort` | **PASS（带 R-01）** | 默认 10min、一次性 take、过期删除+清零、`clearAll`、复制输入、destroy；缺失/过期映射符合。长度未限制（R-01）。 |
| §9.1.6 v1 DDL | **PASS（带已记录索引）** | `gw_route`/`gw_sequence`/`gw_dismissed_device` 字段、类型、主键一致；额外 `gw_route_family_idx` 为加法索引，已在报告中记录，不改变列语义。 |
| §9.2 错误 | **PARTIAL（R-02/O-2）** | Preferences/RDB/Asset 数字码映射正确，无平台 message；`beginTransaction` 原始错误逃逸（R-02）；非法 port 错误码与 §10.2 有设计冲突（O-2）。 |
| §9.3 不变量 1–8 | **PASS（带 R-01/R-02）** | 迁移单向、事务原子（带 R-02）、秘密边界、alias 生命周期、内存擦除、Asset 失败阻断、幂等迁移、keyId 固定均实现；`AssetStoreSecretStore.initialize` 存在但组合根尚未接线（residual）。 |
| §9.4 seam | **PASS** | 平台 API 三文件隔离；host fake 不默认成功；设备骨架已标 `BLOCKED_ON_DEVICE_RUNNER`。 |

### 4.2 DES-A §10 C-07

| 契约条目 | 结果 | 说明/证据 |
|---|---|---|
| §10.1 端口与方法 | **PASS** | 全部方法/签名实现；`commitBinding` 三参数语义保留；`applyInvitedGateway`/`markSeen`/`pinVerified`/`rotateSecret`/`removeLocalBinding` 均在。事件发布按报告延后。 |
| §10.2 错误表 | **PARTIAL（R-01/O-2）** | 未绑定、secret 缺失、Asset 失败、P-BLOCKED、draft 过期/缺失、轮换失败、RDB 失败均映射；短 secret 无错误（R-01）；非法 port 错误码冲突（O-2）。 |
| §10.3 绑定与补偿 | **PASS（带 R-05）** | draft 校验先于消费；family 冲突拒绝；旧 secret 恢复；恢复失败 fail-closed 删除；secret 写失败不写 route；draft 一次性；成功后 markSeen。post-commit 语义见 R-05。 |
| §10.4 profile/pin/sequence | **PASS（带 R-07）** | P-BLOCKED 拒绝且不落盘；P-HMAC 清空 pins/tls；P-TLS-PIN 要求 pins 合法；多 pin 收缩/未知 pin fail-closed；TLS_PROFILE_INCONSISTENT；sequence 事务内递增/上限保守报错。调用边界见 R-07。 |
| §10.5 seam | **PASS** | 仅依赖端口；host 覆盖 route/绑定/补偿/pin/轮换/并发 sequence；fake 记录清零/调用；设备测试 `BLOCKED`。 |
| §10.6 traceability | **PASS（带 R-03）** | FR-GW-003/FR-SET-002、SC-09/SC-12、ADR-002 §4/§6/§8.3/§8.4 均有测试/实现锚点；设备证据待接线。 |

### 4.3 §22、ADR-002、约束

| 契约条目 | 结果 | 说明 |
|---|---|---|
| §22.1 分工 | **PASS** | Preferences 无 secret 调用；RDB 只存 pins/alias/route/sequence；secret 只在 Asset Store；draft/PoP 类内存。 |
| §22.2 键/别名 | **PARTIAL（R-01）** | `yaocore.gateway.hmac.<gatewayId>`、`...pending.<gatewayId>.<rotationId>`、cloud/auth/invite alias 常量齐全；命令密钥 ≥16B 未在 binding 路径强制（R-01）。 |
| §22.3 生命周期 | **PASS（带 R-05）** | put 复制/清零；withSecret finally 清零；draft clearAll；remove 失败不转存；Asset 失败阻断；post-commit 见 R-05。 |
| ADR-002 §4 pin 格式/绑定/轮换 | **PASS** | 64 位小写 hex；1..4；任一匹配；多 pin 首成功收缩；pin 只来自路由记录；无手工编辑 API；事件延后已记录。 |
| ADR-002 §6 三档案/禁止回退 | **PASS（带 R-07）** | P-HMAC/P-TLS-PIN/P-BLOCKED 语义在持久层正确；P-BLOCKED 不持久化；`tlsMaterial` 对空 pins 抛 `TLS_PROFILE_INCONSISTENT`；无明文回退。调用方降级约束见 R-07。 |
| ADR-002 §8.3/§8.4 | **PASS** | Asset Store + alias；pending→verify→active→delete；失败 active 不变；`initialize` 清 pending。 |
| SC-09/SC-12 | **PASS** | 无 Preferences secret；RDB 无明文；删除仅本机、无 transport 依赖。 |
| SC-04 | **PARTIAL（R-01）** | 命令密钥 ≥16B 未在 draft binding 路径强制；`InvitedGateway`/`rotateSecret` 已强制。 |
| PR-06/FC-03 | **PASS（边界）** | 绑定 identity 来自 `BleProvisioningResult.identity.gatewayId`；验签/一致性归 C-19/C-23；`keyId=app-key-v1` 固定。 |
| i18n | **N/A / PASS（无新增 UI 文案）** | 产品代码无用户可见硬编码字符串；错误经 `ErrorCatalog` 解析为 `errors.app.*`；未新增/复制语言代码分支；资源包落地归后续 i18n 任务。 |

---

## 5. 测试质量与证据诚实性

### 5.1 有效覆盖

39 个新用例全部真实运行并通过（161/161），重点覆盖：

- **C-06（14）**：draft 复制/一次性/TTL 边界/clearAll/destroy/非法 TTL/多草稿；迁移 0→2、重复迁移、重复注册/缺口、失败回滚表+版本、拒绝高版本；v1 初始化/幂等/close；`InMemorySecretStore` 成功/异常清零、alias 语法、list 不含 secret。
- **C-07（25）**：HMAC/TLS 绑定、draft 重放、draft 不匹配/家庭迁移负例；route 写失败恢复旧 secret、恢复再失败 fail-closed、首次失败无残留、secret 写失败无 route；复用 secret/缺失 draft；邀请幂等/createdAt/家庭冲突；P-BLOCKED 拒绝、TLS→HMAC；多 pin 收缩/未知 pin；轮换成功/验证 false/验证异常；initialize 清 pending；remove 本机解绑；sequence 读/增/重置/上限/40 并发；route 列表/家庭索引/地址更新；未绑定错误；secret 泄漏审计。
- **Fake 边界**：`InMemoryRdbStore` 不支持的表/列/SQL 默认失败，事务快照回滚，调用计数；`InMemorySecretStore` 记录清零次数；未发现“默认成功”假阳性。

### 5.2 测试缺口与证据问题

- **R-01 短 secret**：无负例；探针已证明 1 字节可通过。
- **R-02 begin 失败**：host fake 无平台 begin 语义；适配器无 seam 测试。
- **R-05 markSeen/readRoute post-commit**：无失败注入；探针已证明半成功状态。
- **O-3**：active 写入失败、applyInvitedGateway route 失败、`setPersistentProfile(P_TLS_PIN)` 成功路径、SC-12 行为断言缺失。
- **R-03 设备**：`StorageDevice.test` 未注册进 `onDeviceTest`；没有事务内 `setVersion` 回滚、没有锁屏拒绝用例；报告 R-T08-03/04 的“设备用例覆盖”措辞过强。
- **R-04 文档**：`entry/src/test/README.md` 仍写 122/122，且未列 T-08 测试/证据。
- **Lint 边界**：`code-linter.json5` 忽略 `src/test`/`src/ohosTest`；报告 “静态检查全部通过” 应理解为产品源码，不覆盖测试源码。

### 5.3 证据诚实性

- Host 161/161、codelinter、构建、ohosTest 编译均可复现；实现报告没有把设备/Previewer 写成 PASS。
- `t08-hvigor-test-compile.log` 的 ArkTS “Function may throw exceptions” 是编译警告，不是失败；但 R-02 正是其中一类需要处理的异常路径。
- 设备证据仍为 `UNAVAILABLE`/`BLOCKED`；报告 §0/§3.4/§5.3 总体诚实，仅 R-03/R-06/R-04 的措辞/计数需要收紧。

---

## 6. 过程与仓库

- **范围**：26 路径均在 `wp-020-storage` 的 `commit_paths` 内；无越界修改；无构建产物、无真实 secret、无 `input/**` 变更。
- **分支**：评审在 `task/wp-020-storage` 的 `66b6e1d` 上执行；未创建/切换/合并/推送分支；本报告提交到 `artifacts/70-review/`。
- **快照**：review handoff 的 snapshot 覆盖 `service/storage/`、`repository/`、`entry/src/test/`、`ohosTest/.../storage/`、`artifacts/`；manifest 字节哈希与当前 reviewed revision 一致。
- **实现 handoff**：`wp-020-storage.snapshot_paths` 只含 `entry/src/test/` 与 `artifacts/50-implementation/`，未含新增产品目录；本次 review handoff 已覆盖产品目录，不影响本次结论。后续实现 handoff 建议把产品写范围纳入 snapshot（与 T-07 R-08 同类过程观察）。
- **报告元数据**：`t08-storage.md` 的 `Producer: agent:implementation-engineer`、`Status: Proposed`、组件 `UNVERIFIED` 均正确；唯一实质错误是 C-06 文件计数（R-06）。
- **证据文件**：`t08-*` 日志均与复验结果一致；设备日志没有伪造 PASS。

---

## 7. CQG-T08 检查项对照

| 检查项 | 结果 | 证据 |
|---|---|---|
| 构建 | **PASS** | `hvigorw clean assembleHap --no-daemon` exit 0，35 tasks；unsigned HAP warning |
| lint（产品源码） | **PASS** | `codelinter` No defects；测试源码不在 lint 范围 |
| Node host | **PASS 161/161** | 复跑通过；新增 39（14+25） |
| fake store 事务/回滚 | **PASS（host）** | 迁移失败回滚、route 补偿、并发 sequence；真实 RDB 语义待设备 |
| pin 绑定/轮换 | **PASS（host）** | 多 pin 收缩、未知 pin fail-closed、TLS 材料、P-BLOCKED 拒绝 |
| 无明文 secret 日志 | **PASS（代码/host）** | 无 console/hilog；Preferences/RDB leak dump；错误 details 只有字段/数字码 |
| Asset/RDB/Preferences 真实运行 | **BLOCKED** | 无设备/签名；`StorageDevice` 未注册（R-03） |
| 设备测试 HAP 编译 | **PASS（编译）** | `t08-ohosTest-assemble.log`；不代表运行 |
| 独立评审 | **本报告** | 作者之外；只读；CHANGES_REQUIRED |
| CQG-T08 总体 | **NOT PASS / CHANGES_REQUIRED** | R-01/R-02 未解决；设备证据仍 BLOCKED |

---

## 8. Verdict

**CHANGES_REQUIRED**

必须修复后才能进入 CQG-T08 复审：

1. **R-01**：在 draft binding 路径强制命令密钥长度 ≥16B（建议 16..4096），失败即销毁 draft、不得写 secret/route；补负例。
2. **R-02**：修复 `beginTransaction` 异常路径：复位 `inTransaction`、映射 `STORAGE_RDB_ERROR`、保证后续事务可恢复；补可注入 seam 测试。

建议在同一修复中处理（不单独阻断，但应在复审前给出结论）：

- R-03 设备套件注册与版本文档回滚/锁屏用例；R-04 README 161/161；R-05 post-commit 语义；R-06 文件计数；R-07 C-17 降级边界约束。

复审要求：修复后重跑 `run-host-tests.sh`、`codelinter`、`hvigorw clean assembleHap`（以及受影响的负例），由作者之外的评审者在新 revision 上复审。C-06/C-07 保持 `UNVERIFIED`；本报告不授予 PASS、STABLE、CQG-T08 完成、Stage Gate 或用户验收。

---

## 9. 残余风险与后续跟踪

| 项 | 风险/跟踪 | 处置 |
|---|---|---|
| R-T08-01 | Asset Store `ALIAS` 按 BYTES 编码；若平台实际要求 string，设备运行失败 | 设备环境复核 `StorageDevice`；禁止明文回退；必要时调整适配器并重跑冻结测试。 |
| R-T08-02 | `list()` 无 alias 的 `ATTRIBUTES` 全量 query 平台语义未验证 | 设备用例覆盖；若不允许，改为按已知 alias 集合查询（仍不读 secret）。 |
| R-T08-03 | RDB `store.version` 与 `begin/commit/rollBack` 真实事务语义 | 设备环境补“事务内 setVersion 失败回滚”用例（R-03）；host 只证明逻辑/ fake。 |
| R-T08-04 | 锁屏/首次解锁 Asset 访问 `ASSET_ACCESS_DENIED` | 设备/安全评审；当前骨架未实际锁屏测试（R-03）。 |
| R-T08-05 | 补偿写回旧 secret 失败时删除 alias（fail-closed） | host 已断言；设备/故障注入阶段复核。 |
| R-T08-06 | Preferences 适配器不识别 secret | 端口注释+调用点复核；当前无产品调用把 secret 写入 Preferences。 |
| C-17/T-11 | 运行期 P-BLOCKED、禁止明文回退、`setPersistentProfile` 不降级、seq 上限/reset、`gateway.bound` 事件 | 在 C-17 实现与测试中固化；R-07 为调用边界约束。 |
| T-12/C-19 | 配网取消/失败/后台 `SecretDraftStore.clearAll()`；draftId 熵；短 secret 输入校验 | 由 C-19/T-12 接线；R-01 修复后仍需端到端取消清理测试。 |
| T-09/C-08 | `RdbStore` 事务复用、禁止嵌套/单飞、迁移注册顺序 | O-1；C-08 复用前明确 API 使用约定。 |
| C-17/组合根 | `AssetStoreSecretStore.initialize`、Preferences/RDB/Asset close/句柄生命周期、端口迁移 `contracts/**` | 组合根任务统一接线；端口位置偏离已记录，不在 T-08 重复实现。 |
| DES-B/C-17 | pin 轮换事件、`gateway.bound` 事件 | 事件契约由 DES-B 定义；T-08 只持久化 pins/状态，报告已记录。 |
| T-19 | 全量测试报告、设备证据、README 计数、i18n 资源、错误 key 资源落地 | T-19 更新；R-04/R-03 需在 T-19 前关闭。 |
| 环境 | 无设备/模拟器/签名；`hvigorw test` Previewer BLOCKED | 不写成 PASS；设备可用后执行 `onDeviceTest` 并复跑同一组用例。 |

---

## 10. 独立评审声明与边界

- **独立性**：评审者未参与 T-08 的需求、设计或实现；T-08 作者为 `agent:implementation-engineer`。本报告不接受作者授权，也不由作者关闭。
- **只读边界**：未修改任何被审代码、测试、证据或实现报告；唯一受版本控制的写入是 `artifacts/70-review/t08-review.md`。独立探针位于 `/tmp/opencode`，不进入仓库，不改变被测 revision。
- **证据边界**：本报告的 PASS 仅指 host 逻辑、构建/静态检查与代码审查；Asset Store/RDB/Preferences 真实行为、`hvigorw test` 运行时、设备 `onDeviceTest` 均为 `COMPILED_ONLY`/`BLOCKED`，未写成 PASS。
- **Gate 边界**：本报告不授予 CQG-T08 PASS、C-06/C-07 `STABLE`、Stage Gate 或用户验收；修复后必须重跑受影响测试并由作者之外的评审者复审。

*Reviewer: agent:quality-reviewer | Revision: 66b6e1d | Verdict: CHANGES_REQUIRED*
