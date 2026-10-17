# T-08 复审：R-01..R-07 关闭确认与 CQG-T08 意见

- **Artifact ID**: REV-T08-002
- **Producer**: agent:quality-reviewer
- **Type**: Independent Re-Review / CQG-T08 Evidence
- **Status**: **PASS（代码级复审通过；不授予 CQG-T08 总体完成、C-06/C-07 `STABLE`、Stage Gate 或用户验收）**
- **Date**: 2026-10-17
- **Task**: `wp-023-review-t08b`（task 分支 `task/wp-020-storage`，父分支 `feat/yaocore-app`）
- **Reviewed revision**: `1f1fb4d8641525f5483bb0ed7bf6cd2e5d5a0dbd`（修复提交；父 `71f45ce3bce92c912d88766b89d1dbccc7cf0185`，实现 `66b6e1d48f1e4e920d8d79e43748bcc5b58ae9af`）
- **Review snapshot**: `refs/swe/snapshots/20261017T093944Z-wp-023-review-t08b-702e472c`（commit `2749fef5be5fb16f42824ef5203827b6b35655a7`；覆盖 storage/repository/host/ohosTest/artifacts 目标）
- **Workflow**: STANDARD / GATED_AUTO
- **Independence**: 本报告由未参与 T-08 实现与修复的质量评审者（`agent:quality-reviewer`）编写；实现/修复作者为 `agent:implementation-engineer`。作者之外独立裁决，作者不能批准或自行关闭本复审。

> 结论先行：上轮 REV-T08-001 的 **R-01..R-07 全部关闭**，两个 Medium（draft 密钥长度、begin 失败事务状态）均已由代码、负例和独立探针复核。当前 revision 独立复跑 host **166/166**、`codelinter`、`hvigorw clean assembleHap` 与 ohosTest HAP 编译全部通过；未发现新的 Critical/High/Medium 缺陷或修复引入的回归。仅保留 2 项非阻塞 Low/Info 观察与 O-1/O-2/O-3 的已记录延期。判定 **PASS（可进入 CQG-T08 裁决/合并）**；设备/真实 Asset Store/RDB 运行仍为 `BLOCKED`，不得写成 CQG-T08 完成或 `STABLE`。

---

## 1. 复审范围、输入与方法

### 1.1 范围

| 类别 | 路径 | 本轮核对 |
|---|---|---|
| C-06 产品代码 | `entry/src/main/ets/service/storage/**` | 12 文件；重点 `RdbTransactionRunner.ets`（新增）、`RdbStoreAdapter.ets`、`SecretDraftStore.ets` |
| C-07 产品代码 | `entry/src/main/ets/repository/**` | 2 文件；重点 `commitBinding`、`completeCommit`、`setPersistentProfile`、`rotateSecret` |
| Host 测试 | `entry/src/test/host/{Storage,GatewayRepository}.test.mjs`、`entry/src/test/storage/FakeStores.ets`、`StorageHost.test.ets` | 修复新增 5 用例（C-06 +1、C-07 +4）与既有 161 用例回归 |
| 设备骨架 | `entry/src/ohosTest/ets/test/storage/StorageDevice.test.ets`、`List.test.ets`、`README.md` | 注册、两条新骨架、措辞边界 |
| 文档/证据 | `entry/src/test/README.md`、`entry/src/test/evidence/t08-fix-*`、`artifacts/50-implementation/{t08-fix-report,t08-storage}.md` | 计数、证据表、R-06 勘误 |

**范围外 / 明确排除**：真实 `@ohos.security.asset`、`@ohos.data.relationalStore`、`@ohos.data.preferences` 的设备执行；`hvigorw test` 的 Hypium Previewer 运行时；C-17/T-11 运行期 P-BLOCKED/TLS 连接；C-08/T-09 的仓储复用；C-18/C-19/C-23 的发现/配网/绑定编排；CQG-T08 的最终 Gate 结论、`STABLE` 或用户验收。i18n 本任务无新增 UI 文案，资源包落地仍归后续任务。

### 1.2 权威输入 pin（复核）

| 输入 | SHA-256 | 结果 |
|---|---|---|
| `artifacts/70-review/t08-review.md` | `67a616f04bfd163bddea0be6ae1c703f2ac0fcb338adc3daa6d8fdbbd94ea11a` | 与 handoff 一致 |
| `artifacts/50-implementation/t08-fix-report.md` | `fdc3430e059a4e9092dc128753c7d14c51d2d4b4608ebc36176f4bbbceeeaf99` | 一致 |
| `artifacts/50-implementation/t08-storage.md` | `de16d45d3f69bc8e54e03df711223730718a0164c1c707d62d1c7e8336c7f5d4` | 一致 |
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `5599e693fafe405443c5d28efaec0bd2091064eee5c3f1a619dc22d3dcbfe1c1` | 一致 |
| `artifacts/20-architecture/adr-002-lan-security-channel.md` | `67943a6e1d8dc78d3ad974e4aa17ca984588ac673cf1cda3447eefbb80d1c86f` | 一致 |
| `artifacts/20-architecture/contract-baseline.md` | `6673a990d5020c0b70dd4ae30bd75fa13d33d4d573a4d953961371296fadee89` | 一致 |
| `artifacts/20-architecture/project-constraints.md` | `283046210e68dfbce9119abbbac849bd1f9a23cf7ef2fb51dcb4aa1e23da9528` | 一致 |
| `artifacts/60-testing/test-plan.md` | `33485cc39abd9a917e94b6568b29e162cd90897adfad509e3f59403a56055fae` | 一致 |

8/8 输入无漂移；handoff 的 `base_commit` 与工作树 HEAD 均为 `1f1fb4d`。评审开始与结束时 `git status --short` 为空。

### 1.3 方法

1. **Diff first**：逐文件审阅 `71f45ce..1f1fb4d` 的 16 个路径，重点追踪新增事务运行器、`completeCommit` 与 draft 长度校验。
2. **契约对照**：DES-A §9.1.2/§9.2/§9.3/§10.3/§10.4/§22.2、ADR-002 §6.2/§8.2/§8.3/§8.4、SC-04/SC-09/SC-12、TEST-001 §4.3。
3. **只读复验**：`entry/src/test/run-host-tests.sh`、`codelinter`、`hvigorw clean assembleHap`、ohosTest HAP 编译、`git diff --check`。
4. **独立探针**：在 shell 内联运行 Node（不写仓库、不改被测 revision），验证“已有绑定 + 非法 draft”不会覆盖旧 secret/route。
5. **回归扫描**：`RdbTransactionRunner` 的 begin/commit/rollback/异常/并发链；`completeCommit` 的 post-commit 语义；测试 fake 是否仍非默认成功。

---

## 2. 独立复验结果

| 命令 | 结果 | 与修复报告/证据对比 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS 166/166**，`# tests 166`、`# pass 166`、`# fail 0`、`# skipped 0`，exit 0，`duration_ms 1402.008133` | 与 `t08-fix-host-node-tests.tap` 166/166 一致；C-06 15、C-07 29 |
| `codelinter -c code-linter.json5 -p default .` | **PASS**，`No defects found in your code.`，exit 0 | 与 `t08-fix-codelinter.log` 一致；`code-linter.json5` 仍忽略 `src/test`/`src/ohosTest`，不覆盖测试源码 |
| `hvigorw clean assembleHap --no-daemon` | **PASS**，`BUILD SUCCESSFUL in 6 s 53 ms`，35 tasks（34 executed / 1 up-to-date），exit 0；仅 unsigned HAP warning | 与 `t08-fix-clean-assemble.log` 的 4 s 921 ms/35 tasks 一致（时间浮动正常） |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **PASS**，`BUILD SUCCESSFUL in 8 s 776 ms`，35 tasks，exit 0 | 与 `t08-fix-ohosTest-assemble.log` 一致；证明注册后的设备套件可编译，不证明设备执行 |
| `git diff --check 71f45ce..1f1fb4d` | 无输出 | 无空白错误 |
| `git status --short`（运行前/后） | clean | 构建输出均被 ignore；无未提交测试/产品改动 |
| 输入 SHA-256 | 8/8 一致 | 无输入漂移 |
| `onDeviceTest` / 真实 Asset/RDB/Preferences | **未运行；BLOCKED** | 无设备/模拟器/签名；不把 `COMPILED_ONLY`/`BLOCKED` 写成 PASS |

补充核对：

- TAP 中 166 个 subtest 全部 `ok`，无 skipped/todo；修复新增 5 个用例均可定位（见 §3）。
- 修复提交 16 个路径均在 `wp-022-fix-t08` 声明范围内；未修改 `common/**`、`model/**`、`service/protocol/**`、`service/crypto/**`、构建配置、`input/**` 或本评审报告之外的评审文件。
- 独立探针：先建立合法绑定，再分别用 1B 与 4097B draft 调用 `commitBinding`；两次均返回 `CONFIGURATION_ERROR`，旧 secret 字节不变、route 数量仍为 1、draft 表为空。**R-01 的“失败不写 secret/route、旧值不被覆盖”得到独立验证。**

---

## 3. R-01..R-07 关闭状态

| ID | 上轮严重度 | 修复位置/实现 | 独立证据 | 状态 |
|---|---|---|---|---|
| **R-01** | Medium | `GatewayRepository.ets:207-213`：`take` 之后、`buildRoute`/`secrets.put` 之前校验 `draft.length ∈ [16,4096]`；失败 `draft.destroy()` + `CONFIGURATION_ERROR(field=secret)`；常量与 `rotateSecret` 共用（54-55、404-405） | `C07_commitBinding_rejectsShortAndOversizedDraftSecretsBeforePersisting`（1B + 4097B，断言无 secret/route、draft 已消费）；上表独立探针验证既有绑定不被覆盖 | **Closed** |
| **R-02** | Medium | 新增 `RdbTransactionRunner.ets`：`begin()` 纳入 try/catch、失败 best-effort rollback、`mapRdbError` 保留数字 `platformCode`、`active` 仅在 begin 成功后置位且 finally 复位；`RdbStoreAdapter.ets:82-84,120-123` 委托运行器，删除 `transactionChain/inTransaction` | `C06_RdbTransactionRunner_beginFailureMapsAndRecovers`：begin 失败 → `STORAGE_RDB_ERROR(platformCode=14800000)`、callback 未执行、rollback 1 次、`isActive=false`；随后同一 runner 第二笔事务成功 | **Closed** |
| **R-03** | Low | `List.test.ets:13,19` 注册 `storageDeviceTest`；`StorageDevice.test.ets:81-105` 增加“事务内 `setVersion` + 后续语句失败 → 版本/表回滚”骨架，`134-157` 增加锁屏 `ASSET_ACCESS_DENIED` 骨架；`t08-storage.md` §3.4/§5.2 与 ohosTest README 收紧为“已注册、未执行、锁屏需前置条件” | ohosTest HAP 编译 PASS；设备执行仍 BLOCKED；报告未把骨架写成 PASS | **Closed（接线/编译）；执行 BLOCKED** |
| **R-04** | Low | `entry/src/test/README.md` 当前计数 **166/166**；目录树补 `Storage.test.mjs`、`GatewayRepository.test.mjs`、`FakeStores.ets`、`StorageHost.test.ets`、`StorageDevice.test.ets`；补 T-08 证据表与 “codelinter 不覆盖测试源码” | README 与本次复跑 166/166、TAP 文件名、目录实际内容一致 | **Closed** |
| **R-05** | Low | `GatewayRepository.ets:586-599` `completeCommit`：`markSeen` 为 post-commit best-effort；回读失败返回已提交 route 快照；复用路径 `193` 与 draft 路径 `232` 共用；方法注释与修复报告 §1.2 记录语义 | 3 个新用例：draft 路径 markSeen 失败、复用路径 markSeen 失败、回读失败返回快照；均断言 route/secret 仍已提交、draft 已消费 | **Closed** |
| **R-06** | Low | `t08-storage.md` §0/§1.1 将初版 C-06 计数改为 **11**，注明 wp-022 新增 `RdbTransactionRunner.ets` 后为 **12**；测试数补 161→166 勘误；§4/§5 同步 | 实际 `service/storage/` 12 文件；161/161 与 166/166 两组证据均可复现 | **Closed** |
| **R-07** | Low | `GatewayRepository.ets:317-329` 方法注释明确：P-TLS-PIN→P-HMAC 仅限显式重配网；运行期 TLS 失败必须由 C-17 保持持久 P-TLS-PIN/运行期 P-BLOCKED，不得调用 `setPersistentProfile(P_HMAC)`；未新增守卫参数，§10.1 冻结签名未变 | 现有 `C07_setPersistentProfile_rejectsBlockedAndMigratesHmacTls` 继续通过；注释/修复报告 §1.2 记录 C-17/T-11 交付约束 | **Closed（约束记录，未改签名）** |

**关闭判定**：7/7 关闭；两个 Medium 的原始触发条件均已被负例覆盖，且 R-02 的恢复路径有“失败后再次成功”的行为断言。

---

## 4. 回归检查与新发现

### 4.1 回归检查

| 检查点 | 结果 | 说明 |
|---|---|---|
| 事务运行器 begin/commit/rollback | **PASS** | begin 失败不置 `active`；commit/callback 失败 rollback 且保留主错误；finally 复位；失败后链可继续 |
| 事务串行化 | **PASS（保持原语义）** | `chain` 仍按 store 串行；未引入并发穿透。O-1 的普通 `execute/query` 不入队与嵌套等待问题未改变 |
| 补偿路径 | **PASS** | `completeCommit` 不改变 secret/route 补偿；route 写失败仍恢复旧 secret/fail-closed；非法 draft 在写 secret/route 前拒绝 |
| 负例有效性 | **PASS** | R-01 断言错误码/无残留/draft 消费；R-02 断言映射码、callback 未执行、rollback 次数、可恢复；R-05 断言半成功仍返回已提交结果 |
| 测试 fake 边界 | **PASS（未变）** | `InMemoryRdbStore` 仍对未知表/列/SQL 失败，不默认成功；新增 `FakeTransactionDriver` 仅用于事务运行器 |
| 构建/静态检查 | **PASS** | 主 HAP 与 ohosTest HAP 均编译成功；新增平台调用产生 ArkTS “Function may throw exceptions” 编译警告，但均处于已捕获路径且构建/lint 不失败 |
| 范围/证据 | **PASS** | 无越界文件、无真实 secret、无构建产物提交；证据日志与复跑结果一致 |

### 4.2 新发现（均不阻塞）

| ID | 严重度 | 位置 | 观察 | 处置建议 |
|---|---|---|---|---|
| **R2-01** | **Low / Info** | `GatewayRepository.ets:586-599` `completeCommit` | 回读失败时返回的 `route` 快照可能是 `lastSeenAt=undefined`，即使 `markSeen` 已成功、数据库行已有时间戳；该“可能滞后”已在注释/修复报告记录，但返回对象与持久状态存在瞬时不一致 | T-11/C-17 不把该次返回的 `lastSeenAt` 当作权威；需要时以 `getRoute`/`listRoutes` 重新读取。当前不构成契约违反，不阻塞 |
| **R2-02** | **Low / Info** | `GatewayRepository.ets:586-594` | `completeCommit` 吞掉 `markSeen` 的所有异常，包括理论上不应出现的 `GATEWAY_NOT_BOUND`；若 route 写入已返回成功但底层行实际不可见，调用方仍会得到成功快照 | 由 C-17 在异常监控/自检中用 `getRoute` 复核；若后续引入可观测性，可记录 best-effort 失败（不得回滚已提交绑定） |

未发现新的 Critical/High/Medium 缺陷；未发现第二套实现、明文回退或冻结签名变更。

---

## 5. 上轮 O-1/O-2/O-3 处置复评

| 项 | 当前处置 | 复评 |
|---|---|---|
| **O-1 事务隔离/重入** | **未改，继续跟踪**（修复报告 §1.3/§4）；`RdbTransactionRunner` 仍只串行化 `transaction()`，普通 `execute/query` 不入同一队列；嵌套事务仍会排队等待外层，`active` 检查在链内不可达 | **接受延期**：当前 C-06/C-07 无嵌套调用；这是 C-08/T-09 复用前的 API 使用约定，已明确记录。不得在 C-08 中默认“嵌套安全” |
| **O-2 §10.2 非法 port 错误码** | **未改**；DES-A §10.2 写 `TLS_PIN_CONFIG_INVALID`，C-02 实际抛 `PROTOCOL_VALUE_OUT_OF_RANGE`；修复报告 §4 记录为上游设计冲突 | **接受延期**：属详细设计内部不一致，应由 solution-architect/契约 owner 裁定；T-08 单方面改码会破坏 C-02 冻结行为。CQG-T08 应保留该记录 |
| **O-3 其余测试缺口** | **部分关闭**：已补短/超长 secret、begin 失败、markSeen/回读半成功；`rotateSecret` active 写入失败、`applyInvitedGateway` route 写入失败、SC-12 行为断言仍未补（修复报告 §4） | **接受延期（非阻塞）**：剩余项不是本次 R-01..R-07 的 Must；两路径已有成功路径与相邻失败用例（`applyInvitedGateway` secret 写失败、`rotateSecret` 验证失败/异常），但精确的 route/active 写入失败注入仍缺。建议在 C-08/C-17/T-19 前补齐，尤其是 SC-12 的行为性断言 |

---

## 6. CQG-T08 检查项对照

> 最小必填（TEST-001 §4.3）：fake store 事务/回滚、pin 绑定/轮换、无明文 secret 日志。设备 IT 仍为环境阻塞项。

| 检查项 | 结果 | 证据 |
|---|---|---|
| 构建 | **PASS** | `hvigorw clean assembleHap` exit 0，35 tasks；unsigned HAP warning |
| lint（产品源码） | **PASS** | `codelinter` exit 0，`No defects found`；测试源码按配置不在 lint 范围 |
| Node host | **PASS 166/166** | 独立复跑 `# fail 0`；C-06 15 + C-07 29；新增 5 用例全部通过 |
| 契约（DES-A §9/§10/§22） | **PASS（host/code）** | §9.1.2 事务异常映射/复位；§9.2 错误命名空间；§10.3 补偿与 post-commit；§10.4 profile/pin；§22.2 命令密钥 ≥16B |
| 安全（SC-04/SC-09/SC-12） | **PASS（host/code）** | draft/rotate 均强制 16..4096；Preferences 无 secret；Asset alias；失败不写 secret/route；无 `console`/`hilog`/明文日志；P-BLOCKED 不落盘、无自动回退 |
| 分层/依赖方向 | **PASS** | 平台 API 仍只在三个适配器；`RdbTransactionRunner` 平台无关；repository 只依赖端口与模型；无第二套实现 |
| 独立评审 | **PASS** | 本报告；作者之外、只读、当前 revision |
| pin 绑定/轮换 | **PASS（host）** | 多 pin 收缩、未知 pin fail-closed、TLS→HMAC 显式路径、P-BLOCKED 拒绝；真实 TLS 连接属 C-17 |
| fake store 事务/回滚 | **PASS（host）** | 迁移失败回滚、route 补偿、事务运行器 begin 失败/恢复、并发 sequence |
| 无明文 secret 日志 | **PASS（代码/host）** | 产品代码无日志调用；错误 details 仅字段/数字码；测试只含公开测试数据 |
| 设备 Asset/RDB/Preferences | **BLOCKED** | 无设备/模拟器/签名；storage 套件已注册且可编译，`onDeviceTest` 未执行 |
| 设备测试 HAP 编译 | **PASS（编译）** | `t08-fix-ohosTest-assemble.log` 与本轮复跑一致；不代表运行 |
| **CQG-T08 总体** | **代码级条件满足；设备项 BLOCKED** | R-01/R-02 已关闭，构建/lint/host/契约/安全/分层均通过；CQG 记录必须保留设备 BLOCKED 与 O-1/O-2/O-3 残余，组件在 Gate 前保持 `UNVERIFIED` |

---

## 7. Verdict

**PASS（代码级复审通过；可进入 CQG-T08 裁决/合并流程）**

理由：

1. R-01..R-07 全部关闭，两个 Medium 的修复有代码位置、负例和独立探针三方证据。
2. 当前 revision 的 166/166 host、`codelinter`、`hvigorw clean assembleHap` 与 ohosTest HAP 编译均可复现；未发现修复引入的回归。
3. 新增 R2-01/R2-02 为 Low/Info，已记录且不影响绑定安全/契约；O-1/O-2/O-3 的延期有明确理由与下游归属。

**边界**：本 PASS **不授予** CQG-T08 总体完成、C-06/C-07 `STABLE`、Stage Gate 或用户验收。设备/真实平台证据仍为 `BLOCKED`；CQG-T08 的设备 IT 项必须在 T-19/设备任务中复跑后才能关闭。

---

## 8. 残余风险

| ID | 风险 | 影响 | 处置 |
|---|---|---|---|
| R2-RISK-01 | 设备 Asset/RDB/Preferences 未运行 | 真实 alias 编码、事务版本回滚、锁屏 `ASSET_ACCESS_DENIED` 无设备证据 | T-19/设备任务执行已注册的 `storageDeviceTest`；保持 `BLOCKED`，禁止明文回退 |
| R2-RISK-02 | `completeCommit` 回读失败返回快照 | 瞬时 `lastSeenAt` 可能滞后（R2-01） | C-17 以 `getRoute` 复核；不把该字段作为安全判定依据 |
| R2-RISK-03 | O-1 普通 execute/query 与事务共用连接、嵌套事务等待自身 | C-08/T-09 复用可能产生隔离或死锁问题 | C-08 前明确“禁止嵌套/单飞”或统一串行化所有操作 |
| R2-RISK-04 | O-2 非法 port 错误码设计冲突 | 调用方可能期望 `TLS_PIN_CONFIG_INVALID` 却收到 `PROTOCOL_VALUE_OUT_OF_RANGE` | solution-architect/契约 owner 裁定并同步 DES-A；T-08 不单方面改码 |
| R2-RISK-05 | O-3 剩余测试缺口 | `rotateSecret` active 写入失败、`applyInvitedGateway` route 失败、SC-12 行为断言未覆盖 | 在 C-08/C-17/T-19 前补高价值负例；不阻塞本次代码级复审 |
| R2-RISK-06 | `RdbTransactionRunner` 的 ArkTS “Function may throw exceptions” 警告 | 平台调用均已在 try/catch 或 best-effort 路径；构建/lint 通过 | 设备运行时复核；若平台异常类型差异导致映射遗漏，再补映射 |

---

## 9. 独立评审声明与边界

- **独立性**：评审者未参与 T-08 需求、设计、实现或修复；T-08 作者为 `agent:implementation-engineer`。本报告不接受作者授权，也不由作者关闭。
- **只读边界**：未修改任何被测产品代码、测试、证据或实现报告；唯一受版本控制的写入是本报告。独立探针为 shell 内联 Node 执行，未写仓库、未改变被测 revision。
- **证据边界**：本报告的 PASS 仅覆盖 `1f1fb4d` 的代码级复审、host 逻辑、构建/静态检查与契约/安全审查；真实 Asset Store/RDB/Preferences、Hypium Previewer、`onDeviceTest` 均为 `COMPILED_ONLY`/`BLOCKED`，未写成 PASS。
- **Gate 边界**：本报告授予代码级复审 PASS，不授予 CQG-T08 总体 PASS、C-06/C-07 `STABLE`、Stage Gate 或用户验收。CQG 记录必须包含设备 BLOCKED、R2-01/R2-02 与 O-1/O-2/O-3 残余。

---

## 10. Handoff

```text
STATUS: PASS
SUMMARY: R-01..R-07 全部关闭；166/166 host、codelinter、主/测试 HAP 构建复验通过；无新的阻塞性缺陷。
ARTIFACTS_CREATED: artifacts/70-review/t08-review-b.md
ARTIFACTS_UPDATED: artifacts/70-review/t08-review-b.md（占位覆写为正式复审报告）
RISKS: 设备 Asset/RDB/Preferences 仍 BLOCKED；R2-01/R2-02 Low；O-1/O-2/O-3 已记录延期。
VALIDATION: run-host-tests 166/166；codelinter PASS；assembleHap PASS；ohosTest assembleHap PASS；diff --check clean；输入 hash 8/8 一致。
NEEDS_CLARIFICATION: 无（O-2 的 DES-A §10.2 错误码冲突由上游架构/契约 owner 裁定，不阻塞本复审）。
NEXT_ACTION: Orchestrator/CQG 记录设备 BLOCKED 与残余项；按 Git 策略合并；设备可用后执行 onDeviceTest 并关闭 R2-RISK-01。
```

*Reviewer: agent:quality-reviewer | Revision: 1f1fb4d | Verdict: PASS (code-level; device BLOCKED)*
