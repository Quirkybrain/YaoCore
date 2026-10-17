# T-09 复审修复报告（R2-01 / R2-02 / R2-03 / R2-05）

- **Artifact ID**: IMP-T09-FIX2
- **Producer**: agent:implementation-engineer
- **Type**: Implementation / Verification Evidence
- **Status**: Proposed（本地构建/lint/host 测试通过；待独立复评与 CQG-T09 Gate）
- **Date**: 2026-10-17
- **Task**: `wp-028-fix-t09b`（task 分支 `task/wp-024-domain`，父分支 `feat/yaocore-app`，base commit `430620d2af350eaef93cb23440ebfde9cf83ba89`）
- **上游输入**: `artifacts/70-review/t09-review-b.md`（CHANGES_REQUIRED）、`IMP-T09-FIX`、DES-B §3.4、ADR-003 §5.4、契约基线、Project Constraints、Test Plan、D-023
- **Workflow**: STANDARD / GATED_AUTO
- **组件状态**: C-08..C-11 保持 `UNVERIFIED`；本报告不授予 `STABLE`、CQG-T09 或 Stage Gate

---

## 0. 摘要

| 项 | 结果 |
|---|---|
| 处置范围 | R2-01（Medium，阻断）**Fixed**；R2-02（Medium，按 D-023）**Fixed（语义书面化 + 配置说明 + 合法排队用例）**；R2-03（Low）**Fixed**；R2-05（Low）**Fixed** |
| 新增 Host 用例 | +4（243 → **247**），全部 PASS |
| `ohpm install` | PASS（exit 0） |
| `hvigorw clean assembleHap --no-daemon` | PASS（BUILD SUCCESSFUL，35 tasks，exit 0） |
| `codelinter -c code-linter.json5 -p default .` | PASS（No defects found，exit 0） |
| `entry/src/test/run-host-tests.sh` | PASS（`1..247`、`# pass 247`、`# fail 0`，exit 0） |
| ArkTS 编译（附加） | `hvigorw test` 的 `UnitTestArkTS` 成功（8 s 240 ms）；随后 Previewer 等待超时 exit 124（环境限制不变） |
| 既有行为 | R-01..R-15 的 243 个既有 host 用例全部保持 PASS；D-022 不同回执语义、O-1 同步重入 fail-fast 未改变 |

---

## 1. 变更文件

产品代码（均在 handoff 写范围内）：

```text
entry/src/main/ets/repository/
├── FamilyRepository.ets      # R2-01：重复回执检测（同一回执 / 同一成员）→ INVITE_RECEIPT_INVALID
├── DomainOperationGate.ets   # R2-02：有界等待语义书面化（D-023），实现与默认 2000 ms 不变
└── DeviceRepository.ets      # R2-05：事务失败恢复 mergeStates/partialKeys 诊断快照
```

测试与证据（`entry/src/test/**`）：

```text
host/DomainFamily.test.mjs    # +2：同回执重放不消耗 use（CODE_KEK）、KEY_WRAP 重放拒绝
host/DomainDevice.test.mjs    # +2：合法排队在超时内成功（O-1）、commit 失败回滚诊断（R2-05）
README.md                     # R2-03：分类计数/total 修正，新增 wp-028 证据表
evidence/t09-fix2-*.log|tap   # 本次四条必需命令 + 附加 ArkTS 编译证据
```

未修改 `service/`、`pages/`、`service/storage/`、C-06/C-12/C-13/C-28 或任何写范围外文件。

---

## 2. 逐条处置

### R2-01（Medium，阻断）同一回执重放重复消耗 `usedCount` — Fixed

**实现**：`FamilyRepository.applyReceiptInTransaction` 在状态/过期/`usedCount`/patch 校验之后、写库之前调用 `isDuplicateReceipt(record, patch)`；命中则抛 `INVITE_RECEIPT_INVALID`，事务整体不产生任何写入（`usedCount` 不递增、无成员 upsert/激活）。

**重复判定**（`FamilyRepository.isDuplicateReceipt`）：

- `record.receipt === patch.receipt`（同一回执文本重放）；
- 或 `record.acceptedByMemberId === patch.acceptedByMemberId`（同一成员再次提交回执即同一接受事实的重放，即使回执文本重新生成）。

**语义选择：拒绝（`INVITE_RECEIPT_INVALID`），而非幂等成功。理由**：

1. DES-B §3.4 明确要求“重复回执拒绝”；ADR-003 §5.4 规定回执在 Admin 侧一次性，重复回执应被拒绝。选择拒绝与上游契约一致。
2. 幂等成功需要区分“合法重试”与“重放”，而在只有单个 `receipt`/`acceptedByMemberId` 持久列（DES-B §3.3.3）的模型下无法可靠区分；拒绝是确定性的、无副作用的。
3. Admin 重试/重复扫码时显式失败可被 UI 展示并引导，不会静默耗尽多用途 CODE_KEK。

**错误码优先级（保持已关闭行为）**：REVOKED → EXPIRED → 过期时间 → `usedCount >= maxUses` → patch 完整性 → 重复回执。因此 KEY_WRAP（maxUses=1）在已消耗后重放仍得到既有的 `INVITE_MAX_USES`（R-01/D-022 已关闭行为），同样不递增、不建成员；多用途 CODE_KEK（`usedCount < maxUses`）重放得到 `INVITE_RECEIPT_INVALID`。两种路径均满足“不得递增 `usedCount`、不产生新成员”。

**新增用例**：

- `T09_C08_sameReceiptReplayDoesNotConsumeUse`：CODE_KEK maxUses=2；member-a/receipt-a 首次成功（used=1，成员 2）；同一回执重放 → `INVITE_RECEIPT_INVALID`，used 仍 1、成员仍 2；同一成员不同回执 → 同样拒绝；member-b/receipt-b 不同回执 → 成功（used=2，成员 3，两人均 ACTIVE）。
- `T09_C08_keyWrapReceiptReplayIsRejectedWithoutExtraConsumption`：KEY_WRAP maxUses=1；重放同一回执 → `INVITE_MAX_USES`（优先级），used 仍 1、成员仍 2、无 member-b。

**未改变**：D-022 的“不同成员、不同回执、`usedCount < maxUses` 时可继续接受”语义不变（`T09_C08_codeKekMultipleReceiptsFollowD022` 仍 PASS）。

### R2-02（Medium，按 D-023）有界等待的语义与配置 — Fixed

**实现**：保留 `DomainOperationGate(waitTimeoutMs = 2000)` 构造注入与有界等待；未改变同步重入 fail-fast（`nestedGateOperation`）。`DomainOperationGate.ets` 头部注释按 D-023 书面化：

- 该超时是**全局队列等待上限**，不是嵌套调用检测器，也会作用于排在慢操作之后的合法独立调用；
- 合法域操作预期显著低于默认 2000 ms；已知可能更长的操作应由**调用方串行化**（先 await 前一操作），而不是依赖 gate 排队；
- 组合根可通过 `new DomainOperationGate(ms)` 注入更大的预算；`<= 0` 关闭有界等待（不推荐，异步重入将挂起）。

**修正上轮报告表述**：`IMP-T09-FIX` §3.2 的“不改变正常串行行为”不准确。准确表述为：正常串行顺序不变，但独立调用排在超过预算的操作之后会被确定性拒绝；D-023 接受“确定性失败优先于挂起”的取舍，并要求如上串行化/配置。

**新增用例**：

- `T09_O1_gateAllowsLegitQueueWithinTimeout`：`new DomainOperationGate(200)`；两个串行操作各耗时约 20 ms（均小于预算），第二个排队后仍成功，顺序为 `first-start → first-end → second`。
- 既有 `T09_O1_gateRejectsSynchronousNestedRun`、`T09_O1_gateRejectsAsyncReentrantCallInsteadOfHanging`、`T09_O1_nestedFakeTransactionFailsFast` 全部保持 PASS。

### R2-03（Low）测试分类计数 — Fixed

`entry/src/test/README.md` 按 `test('T09_<component>_...')` 前缀重新统计并修正：

| 分类 | 原 README | 修正后（当前） | 说明 |
|---|---|---|---|
| C-08 | 25 | **27** | 原 25 + R2-01 新增 2 |
| C-09 | 9 | **10** | 含 `T09_C09_v4StaticRegistrationIsDelegatedAndIdempotent`（原被归入 O-1） |
| C-10 | 26 | **24** | 原 23 + R2-05 新增 1；原 26 为误计 |
| C-11 | 15 | **15** | 不变 |
| O-1 | 5 | **5** | 原 4（去掉 v4 静态注册）+ 合法排队 1 |
| T-09 合计 | 80（误） | **81** | 27+10+24+15+5 |
| 全部 host | 243 | **247** | 166 条 T-05..T-08 基线 + 81 |

README 同时写明计数口径，并更新 `§4` 边界表、当前 revision 与 wp-028 证据表。

### R2-05（Low）设备诊断缓存事务失败不回滚 — Fixed

**实现**：`DeviceRepository.runTransactionWithDiagnostics<T>` 在事务开始前复制 `mergeStates` 与 `partialKeys`；事务抛错时清空并恢复快照后原样抛错。应用于所有会修改诊断缓存的顶层事务：

- `applyDiscoverSnapshot`（ADDED/UNCHANGED/UPDATED/SAME_EPOCH/PARTIAL 与 partial 标记）；
- `removeDevice`、`restoreDevice`、`removeDevicesForGateway`（事务内删除缓存项）。

持久事实仍完全以 RDB 为准；事件仍仅在提交成功后派发（R-12 不变）。

**配套 ArkTS 修正**：`hvigorw test` 的 UnitTestArkTS 首次编译发现 `catch` 中对任意类型 `throw error` 触发 `arkts-limited-throw`；改为 `error instanceof Error` 后再抛出，否则映射 `STORAGE_RDB_ERROR`。这是新增代码的编译修正，不改变语义。

**新增用例**：

- `T09_C10_commitFailureRollsBackDiagnostics`：先以 partial 快照新增 Light_01（`merge.lastResult=ADDED`、`hasPartialState=true`）；注入 `failCommit` 后以 full 快照更新（本应改写诊断并清除 partial），事务以 `STORAGE_RDB_ERROR` 失败；随后记录的诊断仍为 `ADDED`、`hasPartialState` 仍为 `true`、DB 快照未被改写。

---

## 3. 验证命令与结果（本次实际执行）

### 3.1 `ohpm install`

```text
install completed in 0s 40ms
exit=0
```

证据：`entry/src/test/evidence/t09-fix2-ohpm-install.log`。

### 3.2 `hvigorw clean assembleHap --no-daemon`

```text
BUILD SUCCESSFUL in 6 s 494 ms
35 tasks in total: 34 executed, 1 up-to-date
exit=0
```

证据：`entry/src/test/evidence/t09-fix2-clean-assemble.log`。说明不变：HAP 默认可达图仍由 `pages/Index` 驱动，C-28 组合根未装配；新增模块的 ArkTS 编译由 §3.5 覆盖。

### 3.3 `codelinter -c code-linter.json5 -p default .`

```text
No defects found in your code.
exit=0
```

证据：`entry/src/test/evidence/t09-fix2-codelinter.log`（产品源码；`code-linter.json5` 不含 `src/test/**`）。

### 3.4 `entry/src/test/run-host-tests.sh`

```text
1..247
# tests 247
# pass 247
# fail 0
exit=0
```

证据：`entry/src/test/evidence/t09-fix2-host-node-tests.tap`。相较基线的 243 增加 4 个用例。

### 3.5 `hvigorw test --no-daemon`（附加编译证据）

```text
Finished :entry:default@UnitTestArkTS... after 8 s 240 ms
（随后 Linux Previewer 等待，150s 超时 exit=124）
```

证据：`entry/src/test/evidence/t09-fix2-hvigor-test-compile.log`。**仅证明 ArkTS 编译**（拉入全部新增/修改的产品模块），不是 Hypium 执行 PASS；T09-FIX-02 的 Previewer 限制未改变。

### 3.6 回归与范围核对

- R-01..R-15 既有 243 个用例全部保持 PASS（同一 TAP 中）。
- `git diff` 仅包含 §1 列出的产品/测试/README 路径；无构建产物、HAP、证书、密钥入库。
- 未切换分支、未 pull/merge/rebase/push。

---

## 4. 追溯

| 源 | 修复/证据 |
|---|---|
| R2-01（REVIEW-T09B） | `FamilyRepository.applyReceiptInTransaction`/`isDuplicateReceipt`；`T09_C08_sameReceiptReplayDoesNotConsumeUse`、`T09_C08_keyWrapReceiptReplayIsRejectedWithoutExtraConsumption` |
| DES-B §3.4（重复回执拒绝） | 选择 `INVITE_RECEIPT_INVALID`，见 §2 R2-01 |
| ADR-003 §5.4（回执一次性） | 同回执/同成员重放不消耗 use |
| D-022（多回执） | 不同成员/不同回执仍按 `usedCount < maxUses` 消耗（既有用例 PASS） |
| D-023（有界等待取舍） | `DomainOperationGate` 注释语义 + `T09_O1_gateAllowsLegitQueueWithinTimeout` |
| R2-03 | `entry/src/test/README.md` 计数口径与证据表 |
| R2-05 | `DeviceRepository.runTransactionWithDiagnostics`；`T09_C10_commitFailureRollsBackDiagnostics` |
| R-01/R-12（已关闭） | 回执失败无成员残留、commit 失败无事件；既有用例保持 PASS |

---

## 5. 未决项与残余风险

| ID | 项 | 状态/归属 |
|---|---|---|
| R2-04 | `SCENE_RUN_IN_PROGRESS` 与 D-022 的 DES-B/i18n 契约漂移 | **不在本 handoff 范围**（任务仅 R2-01/02/03/05）；仍按复审报告由 Orchestrator 登记 Change Impact，C-14/T-13 补齐 |
| T13-RECEIPT | 真实 C-13 `verifyReceipt` 的重放语义（同一回执文本或同成员）需与本次 C-08 防御一致 | T-13 适配时验证；建议把“重复回执拒绝/同成员一次接受”写入 `InviteServicePort` 契约 |
| GATE-BUDGET | 组合根仍需选择 gate 预算并保证长操作调用方串行化 | C-28 装配时按 D-023 配置 |
| T09-FIX-01/02 | 真实 RDB/Preferences/Asset Store 与 Hypium 执行 | 仍 **BLOCKED**（无设备/模拟器；Previewer 限制不变） |
| T09-FIX-03 | C-06 `RdbTransactionRunner` 生产嵌套事务语义 | 仍归 C-06/T-08 跟踪，本次未触碰 |
| T09-FIX-04/05/06/08 | `SCENE_RUN_IN_PROGRESS` 登记、多网关 `RotationPlan`、C-13 补偿、i18n 键 | 归属不变（R2-04/T-13/C-23/C-14） |

---

## 6. 结论

R2-01、R2-02、R2-03、R2-05 已按复审报告与 D-023 处置；四条必需命令全部通过，host 测试 247/247。R-01..R-15 已关闭行为、D-022 语义和 O-1 约束未改变。C-08..C-11 仍为 `UNVERIFIED`，等待独立复评与 CQG-T09；设备/真实 RDB/Hypium 证据继续 `BLOCKED`。
