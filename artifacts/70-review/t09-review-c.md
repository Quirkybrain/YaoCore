# T-09 聚焦复审报告（R2 项关闭确认与 CQG-T09 最终意见）

- **Artifact ID**: REVIEW-T09C-DOMAIN
- **Producer**: agent:quality-reviewer
- **Type**: Independent Code Review（Focused Re-review）
- **Status**: **PASS（代码级，条件式）** — 四项 R2 修复的代码/测试证据成立；R3-01 需 CQG 记录接受或安排修复（回执账本/C-13 契约）；R2-04 仍由 architect 单独任务同步；本报告不授予 Stage Gate、CQG 总体通过或用户验收
- **Date**: 2026-10-17
- **Task**: `wp-029-review-t09c`（被审修复任务 `wp-028-fix-t09b`）
- **Reviewed Revision**: `9473ae03bccfad14eebda5b02428ae079687f8b8`（`fix(domain): 修复 T-09 复审 R2 项`）
- **Prior Review Revision**: `430620d2af350eaef93cb23440ebfde9cf83ba89`（`REVIEW-T09B-DOMAIN` / `t09-review-b.md`）
- **Implementation Revision**: `5e110db71b800e99da1ccbe2331b422f48843ec0`（T-09 初版）
- **Base Revision**: `430620d2af350eaef93cb23440ebfde9cf83ba89`（本轮 fix 的父提交）
- **Workflow**: STANDARD / GATED_AUTO
- **独立性声明**: 被审实现与修复的 Producer 为 `agent:implementation-engineer`；本复审由未参与 T-09 实现或 `wp-026`/`wp-028` 修复的 `agent:quality-reviewer` 执行。被审代码、测试、证据、上游 Artifact 均未修改；本报告的唯一仓库写入为 `artifacts/70-review/t09-review-c.md`。

---

## 1. 复审范围、revision 与输入完整性

### 1.1 范围内

| 类别 | 路径/内容 |
|---|---|
| 修复提交 | `9473ae0` 相对 `430620d` 的 12 个路径 |
| 仓储修复 | `entry/src/main/ets/repository/FamilyRepository.ets`（R2-01）、`DomainOperationGate.ets`（R2-02）、`DeviceRepository.ets`（R2-05） |
| 测试与证据 | `entry/src/test/host/DomainFamily.test.mjs`、`DomainDevice.test.mjs`、`README.md`、`evidence/t09-fix2-*` |
| 修复报告 | `artifacts/50-implementation/t09-fix2-report.md` |

`git diff --name-status 430620d..9473ae0` 的全部路径均落在 handoff 的 `review_targets` / `snapshot_paths` 声明范围内；未发现产品源码范围外修改、构建产物、HAP、证书、密钥或 `.hvigor` 内容入库。

### 1.2 输入与快照

- 8 个 pinned input 的 sha256 与 `state/handoffs/wp-029-review-t09c.json` 全部一致（逐项校验通过）。
- 评审目标已有 Git snapshot：`refs/swe/snapshots/20261017T105240Z-wp-029-review-t09c-37485166`，覆盖 `entry/src/main/ets/repository/`、`entry/src/main/ets/service/`、`entry/src/test/`、`artifacts/50-implementation/t09-fix2-report.md`、`artifacts/70-review/t09-review-b.md`、`artifacts/70-review/t09-review-c.md`。
- 复验前后 `git status --short` 均为 clean；构建/测试产物被 ignore 规则覆盖。
- 本报告仅覆写 `artifacts/70-review/t09-review-c.md`（原占位文件）；独立探针通过 stdin 执行，未在仓库落盘。

### 1.3 排除/未覆盖

- 真实 HarmonyOS RDB、Preferences、Asset Store、真实事务回滚与设备 ACK（无 `hdc` target、无签名、无模拟器；保持 `BLOCKED`）。
- `hvigorw test` 的 Hypium 实际执行（Linux Previewer 限制；仅有 `UnitTestArkTS` 编译证据，保持 `COMPILED_ONLY`）。
- C-12 AuthService、C-13 InviteService、C-15 CloudService、C-22/C-28 组合根与 UI/ViewModel 的最终实现；仅评审 T-09 的端口边界与调用语义。
- R2-04 的 DES-B/i18n 契约同步（按 handoff 由 architect 单独任务处理；本报告仅记录状态）。
- HAP 默认可达图：`pages/Index` 尚未装配 C-28 组合根，`assembleHap` 不证明全部新增模块进入 HAP 可达图。

---

## 2. 本次独立复验结果

| 命令 | 结果 | 说明 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS**：`1..247`、`# pass 247`、`# fail 0`、exit 0 | 本次独立复跑；与 `t09-fix2-host-node-tests.tap` 的 247/247 完全一致。 |
| `codelinter -c code-linter.json5 -p default .` | **PASS**：`No defects found in your code.`、exit 0 | 本次独立复跑。 |
| `hvigorw clean assembleHap --no-daemon` | **PASS**：`BUILD SUCCESSFUL in 6 s 375 ms`、`35 tasks in total: 34 executed, 1 up-to-date`、exit 0 | 仅证明当前 HAP 默认可达图可构建；`Will skip sign 'hos_hap'`（未配置签名），不得写成设备/签名 PASS。 |
| `hvigorw test --no-daemon`（附加） | **编译 PASS，执行 BLOCKED**：`UnitTestArkTS` 完成（10 s 55 ms），随后 Linux Previewer 等待超时 exit 124 | 独立确认新增 ArkTS 代码可编译；不当作 Hypium 执行 PASS。 |
| `git status --short`（全部复验后） | clean | 未产生未声明仓库改动。 |

### 2.1 证据核对

- `t09-fix2-host-node-tests.tap`：247 条 `ok`，名称集合与本次复跑逐项一致；与 `t09-fix-host-node-tests.tap`（243）比较，旧用例 **0 删除/改名**，仅新增 4 条：
  - `T09_C08_sameReceiptReplayDoesNotConsumeUse`
  - `T09_C08_keyWrapReceiptReplayIsRejectedWithoutExtraConsumption`
  - `T09_O1_gateAllowsLegitQueueWithinTimeout`
  - `T09_C10_commitFailureRollsBackDiagnostics`
- `t09-fix2-clean-assemble.log`：`BUILD SUCCESSFUL`、35 tasks，与本次复跑一致。
- `t09-fix2-codelinter.log`：`No defects found`，与本次复跑一致。
- `t09-fix2-hvigor-test-compile.log`：`UnitTestArkTS` 完成，随后 Previewer 等待；与本次独立复跑同一边界。
- `t09-fix2-ohpm-install.log`：附加证据；本次未重复执行（不影响三条必需命令的结论）。

### 2.2 独立探针（只读；不落盘）

使用与 host harness 相同的 Node ESM loader，在 stdin 中直接调用公开类；未创建/修改仓库文件。关键结果：

```json
{
  "immediate_replay": {
    "first_ok": true,
    "used_after_first": 1,
    "members_after_first": 2,
    "replay_error": "INVITE_RECEIPT_INVALID",
    "used_after_replay": 1,
    "members_after_replay": 2,
    "distinct_member_receipt_ok": true,
    "used_after_distinct": 2,
    "members_after_distinct": 3
  },
  "delayed_replay": {
    "max_uses": 3,
    "used_before": 2,
    "replayed_receipt": "receipt-a",
    "replay_ok": true,
    "used_after_replay": 3,
    "members_after_replay": 3,
    "next_distinct_member_error": "INVITE_MAX_USES"
  },
  "same_member_new_receipt": {
    "error": "INVITE_RECEIPT_INVALID",
    "used_after": 1,
    "members_after": 2
  },
  "keywrap_replay": {
    "error": "INVITE_MAX_USES",
    "used_after": 1,
    "members_after": 2
  },
  "diagnostics_rollback": {
    "failed_error": "STORAGE_RDB_ERROR",
    "merge_after": "ADDED",
    "partial_after": true,
    "retry_ok": true,
    "retry_merge": "UNCHANGED",
    "retry_partial": false
  },
  "gate_queue_within_budget": {
    "first": "first",
    "second": "second",
    "order": ["first-start", "first-end", "second"]
  },
  "gate_default_boundary": {
    "slow": "slow-done",
    "queued_error": "CONFIGURATION_ERROR"
  },
  "gate_sync_reentry": "CONFIGURATION_ERROR(nestedGateOperation)"
}
```

- `immediate_replay` 正例：同回执重放被拒绝、`usedCount` 不递增、无新成员；不同成员的不同回执正常消耗（D-022 保持）。
- `delayed_replay` 新发现：在 `maxUses=3` 的 CODE_KEK 上，member-a 的回执在 member-b 接受后被重放，会被当作新 use 接受，随后 member-c 被 `INVITE_MAX_USES` 拒绝。见 §4 R3-01。
- `diagnostics_rollback` 正例：commit 失败后 `mergeStates`/`partialKeys` 恢复到事务前；重试成功并清除 partial，证明缓存未被污染。
- `gate_queue_within_budget` 正例：两个合法串行调用均成功且顺序正确；`gate_sync_reentry` 仍为 fail-fast。

---

## 3. R2 项逐条关闭状态

状态定义：**Closed** = 代码、测试与本次独立探针均支持关闭；**Closed（报告路径）** = 上轮报告的具体复现路径已关闭，但同族窄路径另见新发现；**Open** = 未关闭；**Out of scope** = 不在本 handoff 范围。

| ID | 上轮严重度 | 本轮结论 | 本次证据与判断 |
|---|---|---|---|
| **R2-01** | Medium（阻断） | **Closed（报告路径）**；同族历史重放见 R3-01 | `applyReceiptInTransaction` 在状态/过期/`usedCount`/patch 校验后、写库前调用 `isDuplicateReceipt`（`FamilyRepository.ets:745-810`）；同回执或同成员命中即 `INVITE_RECEIPT_INVALID`，事务无写入。独立探针与 `T09_C08_sameReceiptReplayDoesNotConsumeUse`、`T09_C08_keyWrapReceiptReplayIsRejectedWithoutExtraConsumption` 均通过。 |
| **R2-02** | Medium（设计风险） | **Closed（按 D-023）** | `DomainOperationGate` 构造注入默认 2000 ms（`DomainOperationGate.ets:56`），D-023 语义写入头部注释（`:30-44`）；`T09_O1_gateAllowsLegitQueueWithinTimeout`（`DomainDevice.test.mjs:408`）证明两个合法串行调用在预算内均成功；同步重入 fail-fast 用例（`:582`）与独立探针仍通过。`IMP-T09-FIX` 的“正常串行行为不变”表述已被修正为“顺序不变，但超预算的独立调用会被确定性拒绝”。 |
| **R2-03** | Low | **Closed** | 按 `test('T09_<component>_...')` 前缀实测：C-08 27、C-09 10、C-10 24、C-11 15、O-1 5，合计 81；其余 166，总计 **247**。与 `entry/src/test/README.md` 的 §2 分类、§4 边界表和当前 revision 一致。 |
| **R2-05** | Low | **Closed** | `DeviceRepository.runTransactionWithDiagnostics`（`:894-920`）在事务前复制 `mergeStates`/`partialKeys`，事务失败时清空并恢复快照；应用于 `applyDiscoverSnapshot`（`:122`）、`removeDevice`（`:598`）、`restoreDevice`（`:632`）、`removeDevicesForGateway`（`:671`）。`T09_C10_commitFailureRollsBackDiagnostics`（`DomainDevice.test.mjs:517`）与独立探针均确认 commit 失败后诊断不变、DB 未改写、重试正常。 |
| **R2-04** | Low | **Open / Out of scope** | DES-B §3.3.3 状态图仍把 `ACCEPTED` 画为终态、§3.1.3 仍写 `expireInvitations` 仅处理 PENDING；`SCENE_RUN_IN_PROGRESS` 仍未在 DES-B §6.2/§23.4 与 i18n 资源登记。按 handoff 由 architect 单独任务处理；本次未修改 DES-B，不构成本次代码阻断，但 CQG 记录时不得写成“契约已完全同步”。 |

### 3.1 R2-01 的选择是否合理

**结论：拒绝（`INVITE_RECEIPT_INVALID`）而非幂等成功，是合理的。**

1. DES-B §3.4 明确要求“重复回执拒绝”；ADR-003 §5.4 规定回执在 Admin 注册表内一次性。拒绝与上游契约一致。
2. 单 `receipt`/`acceptedByMemberId` 持久列（DES-B §3.3.3）无法可靠区分“合法重试”与“重放”；拒绝是确定性、无副作用的。
3. Admin 重复扫码/重试会显式失败，不会被静默当作一次新 use；UI 可提示重复回执。
4. 错误码优先级为 REVOKED → EXPIRED → 过期时间 → `usedCount >= maxUses` → patch 完整性 → 重复回执。因此：
   - 非耗尽的 CODE_KEK 同回执重放 → `INVITE_RECEIPT_INVALID`（本轮报告路径）；
   - 已耗尽的 KEY_WRAP（maxUses=1）或 CODE_KEK（maxUses=1）重放 → `INVITE_MAX_USES`。
   两种路径都不递增 `usedCount`、不建成员；后者的错误码与 DES-B §3.2 “用尽 → `INVITE_MAX_USES`”一致，属于合理的前置优先级，而不是绕过重复检测。

**覆盖缺口**：`isDuplicateReceipt` 只比较**当前记录的最后一次** `receipt`/`acceptedByMemberId`；一旦另一成员接受并覆盖这两个字段，较早回执的历史重放不再被识别。见 §4 R3-01。

### 3.2 R2-02 的边界与残余

- D-023 已书面接受“2000 ms 可配置有界等待”作为 ArkTS 无 async-context 下的防误嵌套折中；本次实现仅书面化语义，未改变行为与默认值。
- 合法排队用例使用 `new DomainOperationGate(200)`、两个约 20 ms 的操作；验证的是“预算内的合法排队可成功”的机制，不是默认 2000 ms 的边界。D-023 只要求“文档化 + 补合法排队用例”，因此满足关闭标准。
- 默认 gate 下，首个合法操作耗时 2100 ms 时，第二个独立调用仍在约 2000 ms 被 `CONFIGURATION_ERROR(nestedOperationOrQueueTimeout)` 拒绝；这是 D-023 明确接受的取舍，不是新回归。调用方应按 D-023 串行化，组合根（C-28）需选择预算；跟踪为 `GATE-BUDGET`/`T09-FIX-03`。
- 同步重入 fail-fast、异步重入有界失败、fake 事务嵌套 fail-fast 三条既有用例全部保持 PASS。

### 3.3 R2-05 的实现细节核对

- `mergeStates`/`partialKeys` 中的 `DeviceMergeState` 为只读值对象；备份保存引用是安全的，事务中的 `rememberMerge` 通过替换对象而不是原地修改。
- 事件仍在事务提交后派发；`runTransactionWithDiagnostics` 只包裹事务本身，失败时不派发事件（R-12 保持）。
- `catch` 中 `error instanceof Error` 后原样抛出，否则映射 `STORAGE_RDB_ERROR`；这是为 ArkTS `arkts-limited-throw` 所做的最小编译修正，未改变正常错误路径。
- 未发现其他会在事务内修改诊断缓存但未被该包装器覆盖的顶层事务（`applyControlAck`/`applyCloudState`/assign/rename 等不修改 `mergeStates`/`partialKeys`）。

---

## 4. 新发现（R3-xx）

### R3-01（Medium；非阻断，建议 CQG 记录接受或安排修复）一收据模型下的历史回执重放仍会消耗 use

- **位置**：`entry/src/main/ets/repository/FamilyRepository.ets:745-810`（`applyReceiptInTransaction`/`isDuplicateReceipt`）；`FamilyRepository.ets:539-559`（`applyReceiptAndEnsureMember` 在应用回执后才读取成员行）。
- **事实**：`invitation` 只持久化最后一次 `receipt` 与 `acceptedByMemberId`（DES-B §3.3.3）。在 `maxUses >= 3` 的 CODE_KEK 邀请上：
  1. member-a / receipt-a 首次接受 → `usedCount=1`，`acceptedByMemberId=member-a`，`receipt=receipt-a`；
  2. member-b / receipt-b 接受 → `usedCount=2`，`acceptedByMemberId=member-b`，`receipt=receipt-b`；
  3. 重放 member-a / receipt-a → `record.receipt !== receipt-a` 且 `record.acceptedByMemberId !== member-a`，未被判重 → `usedCount=3`，成员数仍为 3；
  4. member-c 的合法回执 → `INVITE_MAX_USES`，无法加入。
- **影响**：历史回执重放可消耗一次 use 并耗尽多用途 CODE_KEK 邀请，阻塞后续合法成员；`usesRemaining`/UI 失真。不产生未授权成员，不泄漏 secret；需要 `maxUses>=3` 且 Admin 重扫陈旧回执，属于弱模式窄路径。
- **归因**：不是 R2-01 报告路径（同一回执立即重放）的回归；是单 receipt/acceptedByMemberId 持久列的模型限制。ADR-003 T6 已将“已接受邀请重放（CODE_KEK）”列为中风险并写明“轮换兜底”；但 DES-B §3.4 “重复回执拒绝”的严格解释尚未完全满足。
- **建议**（按修复完整性排序）：
  1. **首选（完整闭合）**：在 C-08 增加回执账本（例如 `invitation_receipt(invite_id, receipt_hash, member_id, accepted_at)`，唯一约束 `(invite_id, receipt_hash)`；如需要“每成员一次”再加 `(invite_id, member_id)`），走 v5 迁移并更新 DES-B §3.3.3/§3.4。或在 C-13 的 Admin 注册表中持久化所有已接受回执，由 `verifyReceipt` 拒绝重放，并把该语义写入 `InviteServicePort` 契约；此时 C-08 的当前检查保留为即时防御。
  2. **C-08 轻量缓解（不能替代完整修复）**：在应用回执前读取 `family_member`，仅当“该邀请已记录过其他成员的接受（`usedCount > 0` 且 `acceptedByMemberId` 非空）且 incoming member 已 `ACTIVE`”时拒绝；必须同时补“首次回执导入时成员已 ACTIVE（接触式同步）”和“成员移除后重入”用例，避免把合法首次导入/重入误判为重复。该规则仍无法区分活跃成员的合法新 use，因此不能单独作为完整闭合。
  3. **若 CQG 接受为一收据模型限制**：必须在 CQG 记录并由 T-13/C-13 明确 `verifyReceipt` 的重放语义（含同回执、同成员、跨重启），不得默认为 C-13 会兜底；C-08 的 `usedCount`/UI 失真作为已登记残余。
- **关闭标准**：若做代码修复，新增 `maxUses=3` 用例（member-a → member-b → 重放 member-a 被拒且 `usedCount` 不变 → member-c 成功），并覆盖首次导入/重入不误拒；全量 host PASS；复跑本报告 §2 命令。若接受为残余，则需 CQG/架构书面记录与 C-13 跟踪项，且不得写成“重复回执已完全拒绝”。

### 4.1 同成员判定的设计后果（记录，不单列缺陷）

`isDuplicateReceipt` 的 `acceptedByMemberId` 比较会拒绝“同一成员、不同回执”的再次接受（包括该成员行被移除后、仍持有同一邀请的情况下重新加入）。这与“一次接受”语义一致，也是上轮 R2-01 建议的防御；但 C-22/T-13 若需要“移除后用同一邀请重新加入”，应由新邀请完成。属产品/集成语义确认项，不是本轮代码缺陷。

---

## 5. 回归检查（R-01..R-15 / D-022 / O-1）

### 5.1 范围与差异

- 产品代码仅改 3 个文件：`FamilyRepository.ets`（+27）、`DomainOperationGate.ets`（+19/-5，注释）、`DeviceRepository.ets`（+114/-68，包装器与缩进）。
- `service/`、`pages/`、`service/storage/`、C-06/C-12/C-13/C-28 未修改；未触碰 `RdbTransactionRunner` 的嵌套事务语义。
- `entry/src/test/` 仅新增 4 条用例与 README/证据；旧 243 条用例名称全部保留，无删除/改名。

### 5.2 逐项回归

| 项 | 结论 | 证据/说明 |
|---|---|---|
| R-01（回执失败无残留成员） | 保持 Closed | 既有 revoked/expired/mismatch 用例 PASS；`applyReceiptAndEnsureMember` 仍在同一事务内先应用回执再 upsert；重复拒绝发生在任何写入之前。 |
| R-02（同场景单飞） | 保持 Closed | `SceneService` 未改；`T09_C11_sameSceneConcurrentRun...` PASS。 |
| R-03（MISMATCH 回写 SSOT） | 保持 Closed | `SceneExecutor` 未改；`T09_C11_mismatchWritesGatewayTruthToSsot` PASS。 |
| R-04（O-1 重入） | 保持 Closed（T-09 边界） | 同步重入/异步有界失败/fake 嵌套三条用例 PASS；本次仅书面化 D-023。 |
| R-05（超时步骤 FAILED） | 保持 Closed | `SceneExecutor` 未改；相关 C-11 用例 PASS。 |
| R-06..R-15 | 保持 Closed | 既有 243 条全部 PASS；本次未改 Room/Scene/迁移/事件派发路径。 |
| D-022（不同回执可继续消耗） | 保持 | `T09_C08_codeKekMultipleReceiptsFollowD022` PASS；独立探针确认 immediate replay 后不同成员回执成功（used 2、成员 3）。 |
| O-1（gate） | 保持 | 串行、同步重入 fail-fast、异步有界失败、fake 嵌套 fail-fast 全部 PASS；新增合法排队用例 PASS。 |
| R2-05 相邻的 R-12（commit 失败 0 事件） | 保持 Closed | `T09_C10_commitFailureEmitsNoDeviceEvent` PASS；包装器失败路径不派发事件。 |

### 5.3 安全与分层

- 新增产品代码未 import `@ohos`/网络/平台 API；repository/service 仅依赖 ports、模型与工具。
- 重复回执拒绝只抛 `INVITE_RECEIPT_INVALID`，不带 receipt 文本、seed、token 或成员秘密；未新增日志。
- `runTransactionWithDiagnostics` 仅处理进程内诊断缓存；持久事实仍以 RDB 为准，未引入新的秘密副本。
- `FamilyService.importReceipt` 仍在 RBAC（`requireAdmin`）与邀请状态校验之后调用 verify/repository；未扩大调用面。
- 测试数据为公开 fake 数据；未发现真实家庭数据、证书私钥或 secret 进入证据。

---

## 6. CQG-T09 检查项对照

| 检查项 | 结果 | 证据/说明 |
|---|---|---|
| build | **PASS（限可达图）** | `hvigorw clean assembleHap --no-daemon`：BUILD SUCCESSFUL、35 tasks、exit 0；未签名，C-28 组合根未装配。新增模块的 ArkTS 编译由独立 `UnitTestArkTS`（10 s 55 ms）补充。 |
| lint | **PASS** | `codelinter`：No defects、exit 0。 |
| host | **PASS** | `run-host-tests.sh`：247/247、0 fail；证据 TAP 名称与本次复跑逐项一致；旧 243 条全部保留。 |
| contract | **PASS（代码级）/ 文档同步 OPEN** | SSOT/仲裁、房间删除、场景局部失败、邀请/回执状态机（同回执立即重放拒绝、D-022 不同回执）均通过；R2-04 的 DES-B/i18n 文档漂移仍未同步（architect 任务）；R3-01 为同族窄路径残余。 |
| security | **PASS（秘密/平台边界）** | 无新平台/网络 import；无 secret/receipt 文本日志；重复拒绝无副作用；GUEST 策略边界未变化。 |
| layer | **PASS** | repository/service 无 UI/平台反向依赖；包装器留在 repository；无 service 层越界修改。 |
| i18n | **NOT_APPLICABLE / TRACKED** | 新增代码无硬编码用户可见文案；`INVITE_RECEIPT_INVALID` 按 `errors.app.invite_receipt_invalid` 目录映射；C-14 资源尚未落地；`errors.app.scene_run_in_progress` 仍待 R2-04/C-14。 |
| review | **本报告** | R2-01/02/03/05 关闭；R2-04 记录为 out of scope/open；R3-01 新发现。 |
| device | **BLOCKED** | 无 `hdc`/模拟器/签名；`hvigorw test` 仅 `UnitTestArkTS` 编译，Previewer 不可执行；不得写成设备 PASS。 |
| trace | **PASS（R2 测试）/ R2-04 open** | 新用例名可追溯到 R2-01/02/05 与 DES-B §3.4/§6.x；R2-04 的契约/i18n 条目仍无对应测试或资源。 |
| **总体** | **PASS（代码级，条件式）** | 四项 R2 修复的代码、测试、独立复验成立；设备/真实 RDB/Hypium 仍 BLOCKED；C-08..C-11 不得标记 `STABLE`。 |

### 6.1 CQG-T09 最小必填证据（test-plan §4.3）

| 必填项 | 结果 |
|---|---|
| SSOT/仲裁 | **PASS**：`T09_C10_*` 全套通过（陈旧包、同 epoch、缺字段、partial、tombstone、ACK stale/replay/mismatch）。 |
| 房间删除 | **PASS**：`T09_C09_deleteRoomIsOneTransaction...`、`...RollsBack...`、监听器隔离全部通过。 |
| 场景局部失败 | **PASS**：首步/次步失败、`noRollbackNotice`、MISMATCH、取消、step/total timeout、迟到 outcome 全部通过。 |
| 邀请/回执状态机 | **PASS（报告路径）**：revoked/expired/mismatch、D-022 不同回执、同回执立即重放拒绝、KEY_WRAP 重放无额外消耗均通过；历史回执重放见 R3-01（需 CQG 记录/跟踪）。 |

---

## 7. 裁决

**Verdict: PASS（代码级，条件式）**

理由：

1. **R2-01 的报告路径已关闭**：同一 CODE_KEK 回执立即重放返回 `INVITE_RECEIPT_INVALID`，`usedCount` 不递增、无新成员；不同成员的不同回执按 D-022 正常消耗。代码、host 用例与独立探针三方一致。拒绝而非幂等的选择有 DES-B §3.4 / ADR-003 §5.4 依据。
2. **R2-02 已按 D-023 关闭**：默认 2000 ms 可配置有界等待、D-023 语义注释、合法排队用例、同步重入 fail-fast 均成立；超预算合法调用被拒是 D-023 明确接受的取舍。
3. **R2-03 已关闭**：247 条用例的实际前缀计数与 README 完全一致（27/10/24/15/5 + 166）。
4. **R2-05 已关闭**：commit 失败后诊断缓存恢复，新增用例与独立探针均有效；事件派发时点未变。
5. **无回归**：旧 243 条全部保留并通过，247/247；产品 diff 仅限 3 个声明文件；build/lint/host 均通过。
6. **R3-01 是本次唯一同族残余**：需要 `maxUses>=3`、陈旧回执和弱模式 CODE_KEK，不产生未授权成员/秘密泄漏；ADR-003 T6 已把 CODE_KEK 重放列为中风险并以轮换兜底。它不构成本轮报告路径的回归，但在 CQG 层面不得被默示忽略。

**条件（CQG-T09 记录时需明确）**：

1. **R3-01**：CQG 记录“接受为一收据模型残余并由 T-13/C-13 验证重放语义”，或要求按 §4 建议做 C-08 回执账本/C-13 契约修复；若只做轻量缓解，必须按 §4 的精确规则并补首次导入/重入不误拒用例。二者择一，不得无记录通过。
2. **R2-04**：DES-B §3.3.3/§3.1.3/§6.2/§23.4 与 i18n 键由 architect 单独任务同步；CQG 记录“文档同步 pending”，不得写成完全同步。
3. **设备边界**：真实 RDB/Preferences/Asset/Hypium/设备 ACK 仍 `BLOCKED`；C-08..C-11 保持 `UNVERIFIED`，不得因本报告标记 `STABLE`。
4. 本报告不授予 Stage Gate、CQG 总体 PASS 或用户验收；CQG 的最终裁决由 Orchestrator 按其 Gate 程序作出。

---

## 8. 残余风险与跟踪项

| ID | 风险/跟踪项 | 建议 |
|---|---|---|
| R3-01 | `maxUses>=3` 的 CODE_KEK 历史回执重放可消耗 use，阻塞后续成员 | CQG 记录接受，或按 §4 建议做回执账本/C-13 契约修复；T-13 验证真实 `verifyReceipt` 语义。 |
| R2-04 | DES-B §3.3.3 终态图、§3.1.3 expire、`SCENE_RUN_IN_PROGRESS` 表/i18n 漂移 | architect 单独任务同步；C-14/T-13 补资源键；CQG 记录 pending。 |
| T09-RV-01 | 真实 RDB/Preferences/Asset Store、迁移重启、真实事务回滚未执行 | 设备/模拟器 owner 执行 `DomainDevice.test.ets` 或等价 IT；在此之前不得宣称 C-08..C-11 `STABLE`。 |
| T09-RV-02 | Hypium `hvigorw test` 在 Linux Previewer 无法启动；仅 `UnitTestArkTS` 编译 | 保持 `COMPILED_ONLY`；由设备/CI owner 执行。 |
| T09-FIX-03 | C-06 `RdbTransactionRunner` 生产嵌套事务仍排队 | C-06/T-08 O-1 跟踪；T-09 仅以 `RdbTransaction` 类型隔离。 |
| GATE-BUDGET | 组合根需选择 gate 预算并保证长操作调用方串行化 | C-28 装配时按 D-023 配置并记录。 |
| T13-RECEIPT | 真实 C-13 `verifyReceipt` 的重放语义需与 C-08 防御一致 | T-13 适配时验证“同回执/同成员”语义，并写入 `InviteServicePort` 契约。 |
| 同成员重入 | 成员行被移除后，用同一邀请重新接受会被 `acceptedByMemberId` 命中拒绝 | C-22/T-13 确认是否可接受；若需要重入，使用新邀请或在成员不存在时放行。 |
| T09-FIX-05/06/08 | 多网关 `RotationPlan`、C-13 补偿、i18n 键 | 归属不变（T-13/C-23/C-14）。 |
| T09-FIX-07 | 设备侧 `DomainDevice.test.ets` 未注册/未运行 | 保持 `BLOCKED_ON_DEVICE_RUNNER`。 |

---

## 9. 独立性与结论声明

本报告由 `agent:quality-reviewer` 独立完成，未参与 T-09 实现、`wp-026-fix-t09` 或 `wp-028-fix-t09b` 修复，未修改被审代码、测试、证据、`t09-fix2-report.md` 或任何上游 Artifact。独立探针通过 stdin 与 `/tmp/opencode` 执行，未写入仓库；本报告的唯一仓库写入为 `artifacts/70-review/t09-review-c.md`。评审裁决仅针对 revision `9473ae0` 与 §1 范围，不覆盖 C-12/C-13/C-15/UI/组合根，也不授予 Stage Gate、CQG-T09 总体 PASS 或用户验收。

**Final Verdict: PASS（代码级，条件式）**

### 9.1 本次复验命令摘要

```text
entry/src/test/run-host-tests.sh
  -> 1..247 / # pass 247 / # fail 0 / exit 0

codelinter -c code-linter.json5 -p default .
  -> No defects found in your code. / exit 0

hvigorw clean assembleHap --no-daemon
  -> BUILD SUCCESSFUL in 6 s 375 ms
  -> 35 tasks in total: 34 executed, 1 up-to-date / exit 0
  -> WARN: Will skip sign 'hos_hap'（未配置签名）

hvigorw test --no-daemon（附加编译证据）
  -> UnitTestArkTS 完成（10 s 55 ms）
  -> Linux Previewer 等待超时 exit 124（环境限制，保持 COMPILED_ONLY）

git status --short
  -> clean
```

### 9.2 独立探针摘要

- `immediate_replay`：`INVITE_RECEIPT_INVALID`、used 1→1、成员 2→2；不同回执 used 2、成员 3 → R2-01 报告路径关闭。
- `delayed_replay`：maxUses=3 时历史 receipt-a 重放被接受、used 2→3、成员仍 3；member-c 被 `INVITE_MAX_USES` → R3-01。
- `same_member_new_receipt`：`INVITE_RECEIPT_INVALID`、used 1、成员 2 → 同成员防御生效（对当前 acceptedByMemberId）。
- `keywrap_replay`：`INVITE_MAX_USES`、used 1、成员 2 → 无额外消耗。
- `diagnostics_rollback`：`STORAGE_RDB_ERROR` 后 merge `ADDED`、partial `true`；重试成功并变为 `UNCHANGED/false` → R2-05 关闭。
- `gate_queue_within_budget`：两个合法串行操作均成功、顺序正确；`gate_sync_reentry` 仍 fail-fast → R2-02 关闭。
