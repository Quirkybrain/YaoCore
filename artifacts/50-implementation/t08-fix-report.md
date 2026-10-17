# T-08 评审修复报告（R-01..R-07）

- **Artifact ID**: IMP-T08-FIX-001
- **Producer**: agent:implementation-engineer
- **Type**: Implementation Fix / Verification Evidence
- **Status**: Proposed（修复完成；待作者之外的评审者复审，未授予 PASS/STABLE/CQG-T08）
- **Date**: 2026-10-17
- **Task**: `wp-022-fix-t08`（task 分支 `task/wp-020-storage`，父分支 `feat/yaocore-app`，base commit `71f45ce3bce92c912d88766b89d1dbccc7cf0185`）
- **Reviewed revision**: `66b6e1d48f1e4e920d8d79e43748bcc5b58ae9af`（REV-T08-001，CHANGES_REQUIRED）
- **Workflow**: STANDARD / GATED_AUTO
- **Inputs（pinned）**:
  - `artifacts/70-review/t08-review.md`（REV-T08-001，CHANGES_REQUIRED）
  - `artifacts/50-implementation/t08-storage.md`（IMP-T08-STORAGE）
  - `artifacts/40-detailed-design/des-001a-foundation-transport.md` §9/§10/§22
  - `artifacts/20-architecture/adr-002-lan-security-channel.md` §4/§6/§8.2/§8.3/§8.4
  - `artifacts/20-architecture/contract-baseline.md`、`artifacts/20-architecture/project-constraints.md`（SC-04/SC-09/SC-12）
  - `artifacts/60-testing/test-plan.md` §2-§5
- **Write scope**: `entry/src/main/ets/service/storage/`、`entry/src/main/ets/repository/`、`entry/src/test/`、`entry/src/ohosTest/ets/test/`、`artifacts/50-implementation/`
- **组件状态**: C-06/C-07 保持 `UNVERIFIED`；本次修复不改变该状态，等待复审与设备证据。

---

## 0. 结论摘要

| 项 | 结果 |
|---|---|
| R-01..R-07 | **Fixed**（7/7；逐条见 §1） |
| Node host 测试 | **PASS 166/166**（修复前 161；本次 +5） |
| `ohpm install` | **PASS**（exit 0） |
| `hvigorw clean assembleHap --no-daemon` | **PASS**（BUILD SUCCESSFUL，35 tasks） |
| `codelinter -c code-linter.json5 -p default .` | **PASS**（No defects found；仅产品源码） |
| ohosTest HAP 编译（附加） | **PASS**（BUILD SUCCESSFUL；storage 设备套件已注册，执行仍 BLOCKED） |
| 设备侧 Asset/RDB/Preferences 运行 | **BLOCKED**（无设备、无签名；不写成 PASS） |

本次修复不改变 §10.1 公开签名、canonical/HMAC 语义、`key_id=app-key-v1`、P-HMAC/P-TLS-PIN/P-BLOCKED 规则；新增一个平台无关事务运行器文件。

---

## 1. 逐条处置

| ID | 严重度 | 处置 | 位置 | 测试/证据 |
|---|---|---|---|---|
| **R-01** | Medium | **Fixed**：draft 命令密钥强制 16..4096B；失败销毁 draft、不写 secret/route；错误码 `CONFIGURATION_ERROR`（与 `rotateSecret` 一致） | `GatewayRepository.ets` `commitBinding`（取 draft 后校验）；`MIN/MAX_COMMAND_SECRET_BYTES` 常量 | `C07_commitBinding_rejectsShortAndOversizedDraftSecretsBeforePersisting`（1B + 4097B 负例） |
| **R-02** | Medium | **Fixed**：begin/commit/rollback 状态机抽到平台无关 `RdbTransactionRunner`；begin 失败 best-effort rollback、映射 `STORAGE_RDB_ERROR`（保留 `platformCode`）、`active` 仅在 begin 成功后置位且 finally 复位；后续事务可恢复 | 新增 `service/storage/RdbTransactionRunner.ets`；`RdbStoreAdapter.ets` 委托运行器，删除 `transactionChain/inTransaction` | `C06_RdbTransactionRunner_beginFailureMapsAndRecovers`（fake driver 注入 begin 失败 + 复用成功） |
| **R-03** | Low | **Fixed**：`storageDeviceTest` 注册进 ohosTest `List.test.ets`；补“事务内 `setVersion` + 后续语句失败 → 版本/表回滚”与“锁屏前置条件下 `ASSET_ACCESS_DENIED`”设备骨架；报告措辞已收紧为“已注册、未执行、锁屏需前置条件” | `entry/src/ohosTest/ets/test/List.test.ets`；`storage/StorageDevice.test.ets`；`t08-storage.md` §3.4/§5.2；ohosTest README | `t08-fix-ohosTest-assemble.log`（编译 PASS）；设备执行 **BLOCKED** |
| **R-04** | Low | **Fixed**：host README 更新为当前 **166/166**，补 T-08 套件/Fake/设备骨架/T-08 证据表，注明 `codelinter` 不覆盖测试源码 | `entry/src/test/README.md` | `t08-fix-host-node-tests.tap` |
| **R-05** | Low | **Fixed**：`commitBinding` 的 `markSeen` 改为 post-commit best effort；回读失败返回已提交 route 快照，绝不把已落盘绑定报告为失败；复用路径同样处理；语义写入方法注释/报告 | `GatewayRepository.ets` `completeCommit`；两处调用点 | `C07_commitBinding_markSeenFailureStillReportsCommittedBinding`、`C07_commitBinding_reusePath_markSeenFailureStillReportsCommittedBinding`、`C07_commitBinding_readBackFailureReturnsCommittedSnapshot` |
| **R-06** | Low | **Fixed**：`t08-storage.md` C-06 文件计数 12 → **11**（初版），注明 wp-022 新增 `RdbTransactionRunner.ets` 后为 12；测试数补“修复后 166/166”勘误 | `artifacts/50-implementation/t08-storage.md` §0/§1.1/§3.4/§4/§5 | 本报告 §2；`git diff --check` 无输出 |
| **R-07** | Low | **Fixed（约束记录，未改签名）**：`setPersistentProfile` 方法注释明确 P-TLS-PIN→P-HMAC 仅限显式重配网；运行期 TLS 失败必须由 C-17 走 P-BLOCKED，禁止调用降级。选择**不新增**守卫参数以保持 §10.1 冻结签名 | `GatewayRepository.ets` `setPersistentProfile` 注释；本报告 §1.2 | 现有 `C07_setPersistentProfile_rejectsBlockedAndMigratesHmacTls` 保持通过 |

### 1.1 R-01 长度校验

- 校验点：`commitBinding` 在 `secretDrafts.take(draftId)` 之后、`buildRoute`/`secrets.put` 之前。
- 规则：`draft.length` 必须 ∈ [16, 4096]；否则 `draft.destroy()` 后抛 `AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'secret')])`。
- 与 `rotateSecret` 使用同一对常量，避免两处阈值漂移。
- 复用路径（`draftId === ''`）不重写 secret；其可读性由 `probeSecret` 保证，持久 secret 只能经 `commitBinding`/`applyInvitedGateway`/`rotateSecret` 写入（后两者已有下限校验）。
- 未采纳“把长度限制放进 `SecretDraftStore.put`”：该端口是通用内存草稿端口，DES-A §9.1.5 未规定命令密钥长度，限制在 C-07 绑定边界更符合职责。

### 1.2 R-05 post-commit 语义与 R-07 降级边界

**R-05**：`writeRoute` 事务成功返回即表示 route+secret 已提交。此后的 `markSeen` 失败只影响 `last_seen_at` 新鲜度，不回滚、不改变绑定成功事实；回读失败时返回刚提交的 `GatewayRoute` 快照（`lastSeenAt` 可能滞后，下一次 `markSeen` 会补齐）。因此调用方不会把“已绑定但索引未确认”误判为“绑定失败”。跨存储补偿仍只覆盖 route 写失败（DES-A §10.3 第 7 步）。

**R-07**：仓库层无法区分“用户显式重配网”与“TLS 校验失败回调”，新增布尔/证据参数会改变 §10.1 冻结签名并需要契约修订。本次选择在方法注释与本报告固化调用边界：C-17/T-11 在 TLS 校验失败时只能维持持久 P-TLS-PIN、运行期选择 P-BLOCKED，绝不调用 `setPersistentProfile(P_HMAC)`；该约束纳入 T-11 实现与测试。

### 1.3 R-02 事务运行器语义

- `RdbTransactionRunner.transaction` 仍按 store 串行化（`chain`），`active` 仅在 `driver.begin()` 成功后置 `true`，`finally` 复位。
- `begin()` 抛错：best-effort `rollBack()`、不执行回调、`mapRdbError` 映射平台数字码到 `STORAGE_RDB_ERROR`，随后事务链可继续使用。
- 回调/commit 失败：best-effort `rollBack()`，保留原始 `AppError`（如 `CONFIGURATION_ERROR`），否则映射 `STORAGE_RDB_ERROR`。
- `open()`/`driverFactory` 失败同样映射；`RdbStoreAdapter` 继续是唯一导入平台 RDB API 的文件。
- O-1（普通 `execute/query` 未进入事务串行队列、callback 内嵌套 await 事务可能等待自身）**未改变**；C-08/T-09 复用前仍需约定禁止嵌套。

---

## 2. 验证命令与结果（实际执行）

| 命令 | 退出码 | 结果 | 日志 |
|---|---|---|---|
| `ohpm install` | 0 | install completed | `entry/src/test/evidence/t08-fix-ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | 0 | `BUILD SUCCESSFUL in 4 s 921 ms`；35 tasks（34 executed / 1 up-to-date）；仅 unsigned HAP warning | `entry/src/test/evidence/t08-fix-clean-assemble.log` |
| `codelinter -c code-linter.json5 -p default .` | 0 | `No defects found in your code.`（产品源码；测试源码被配置忽略） | `entry/src/test/evidence/t08-fix-codelinter.log` |
| `entry/src/test/run-host-tests.sh` | 0 | **166/166 PASS**，`# fail 0`，`duration_ms 1154.905572` | `entry/src/test/evidence/t08-fix-host-node-tests.tap` |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon`（附加） | 0 | `BUILD SUCCESSFUL in 6 s 739 ms`；35 tasks；仅 unsigned HAP warning | `entry/src/test/evidence/t08-fix-ohosTest-assemble.log` |

### 2.1 Host 测试计数

| 范围 | 修复前 | 修复后 | 增量 |
|---|---|---|---|
| C-06（`Storage.test.mjs`） | 14 | **15** | +1（R-02 begin 失败/恢复） |
| C-07（`GatewayRepository.test.mjs`） | 25 | **29** | +4（R-01 ×1、R-05 ×3） |
| 总计 | 161 | **166** | **+5** |

TAP 中 166 个 subtest 全部 `ok`，`# pass 166`、`# fail 0`；无 skipped/todo。

### 2.2 代码/文件计数

| 组件 | 修复后 | 说明 |
|---|---|---|
| C-06 `entry/src/main/ets/service/storage/` | **12 文件** | 初版 11 + `RdbTransactionRunner.ets`（R-02） |
| C-07 `entry/src/main/ets/repository/` | **2 文件** | 未新增文件 |
| Host 测试 | `Storage.test.mjs`、`GatewayRepository.test.mjs`、`FakeStores.ets`、`StorageHost.test.ets` | 见 README |
| 设备骨架 | `ohosTest/.../storage/StorageDevice.test.ets` | 已注册进 `List.test.ets` |

---

## 3. 变更路径

```text
entry/src/main/ets/service/storage/RdbTransactionRunner.ets   (new)
entry/src/main/ets/service/storage/RdbStoreAdapter.ets
entry/src/main/ets/repository/GatewayRepository.ets
entry/src/test/host/Storage.test.mjs
entry/src/test/host/GatewayRepository.test.mjs
entry/src/test/README.md
entry/src/test/evidence/t08-fix-*.{log,tap}
entry/src/ohosTest/ets/test/List.test.ets
entry/src/ohosTest/ets/test/storage/StorageDevice.test.ets
entry/src/ohosTest/ets/test/README.md
artifacts/50-implementation/t08-storage.md
artifacts/50-implementation/t08-fix-report.md
```

无 `common/**`、`model/**`、`service/protocol/**`、`service/crypto/**`、构建配置、`input/**` 或评审报告修改；无分支切换/merge/rebase/push。

---

## 4. 未决项与残余风险

| 项 | 状态 | 说明/处置 |
|---|---|---|
| 设备 Asset/RDB/Preferences 真实行为 | **BLOCKED** | 无设备/模拟器/签名；`onDeviceTest` 未执行。storage 套件已注册，设备可用后必须复跑；不得把 HAP 编译写成 PASS。 |
| 事务内 `setVersion` 回滚 / 锁屏 `ASSET_ACCESS_DENIED` | **骨架已补，未执行** | `StorageDevice.test.ets` 新增两条骨架；锁屏分支需 runner 先建立锁屏前置条件。 |
| O-1 事务隔离/嵌套 | **未改，继续跟踪** | 普通 `execute/query` 未进入事务串行队列；C-08/T-09 复用前明确“禁止嵌套/单飞”（评审 O-1）。 |
| O-2 非法 port 错误码 | **上游设计冲突，未改** | DES-A §10.2 `TLS_PIN_CONFIG_INVALID` vs C-02 `PROTOCOL_VALUE_OUT_OF_RANGE`；由架构/契约 owner 裁定。 |
| O-3 其余测试缺口 | **部分关闭** | 已补短/超长 secret、begin 失败、markSeen/回读半成功；`rotateSecret` active 写失败、`applyInvitedGateway` route 写失败、SC-12 行为断言仍未补（非本次 finding 直接要求）。 |
| C-17/T-11 运行期 P-BLOCKED / 禁止降级 | **交接约束** | R-07 已写入方法注释；C-17 实现与测试必须固化“TLS 失败不调用 `setPersistentProfile(P_HMAC)`”。 |
| R-T08-01/02 | **BLOCKED** | Asset alias BYTES 编码与无 alias 全量 query 语义仍需设备复核；禁止明文回退。 |
| CQG-T08 / STABLE | **未授予** | 本报告不替代独立复审；C-06/C-07 保持 `UNVERIFIED`。 |

---

## 5. 复审建议

1. 重跑 §2 四项命令（host 预期 166/166）。
2. 重点复核 `RdbTransactionRunner` 的 begin 失败映射/状态复位与 `RdbStoreAdapter` 委托无行为回归。
3. 复核 `commitBinding` 长度校验位置（take 之后、写 secret/route 之前）与 post-commit 语义是否满足 DES-A §10.3 第 9 步。
4. 确认设备套件注册不改变“设备未执行”的证据边界。

*Implementation engineer: agent:implementation-engineer | Base revision: 71f45ce | Verdict: Fixed, pending independent re-review*
