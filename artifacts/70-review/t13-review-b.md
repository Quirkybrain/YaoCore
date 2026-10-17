# T-13 复审报告 B（核心 F 项关闭确认与 CQG-T13 最终意见）

- **Artifact ID**: REVIEW-T13-B
- **Producer**: agent:quality-reviewer
- **Type**: Independent Code Review / Security Review（只读复审）
- **Status**: **PASS（代码级，条件式）**
- **Date**: 2026-10-17
- **Task**: `wp-053-review-t13b`（task 分支 `task/wp-049-family`；父分支 `feat/yaocore-app`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`（CQG-T13 / SEC）
- **Reviewed revision**: `69d5374e95f3211aaee49c9759751b22d9e09789`（修复提交；父 `5b54a1f` 裁定同步）
- **Review snapshot**: `refs/swe/snapshots/20261017T143502Z-wp-053-review-t13b-c7dcd3d3`（commit `9e878d8`）
- **Fix diff**: `5b54a1f..69d5374`，18 个路径（产品代码 7、测试/harness 4、报告/证据 7）
- **Independence**: 本报告由未参与 T-13 实现、`5b54a1f` 裁定同步或 `69d5374` 修复的 `quality-reviewer` 出具；未修改被审产品代码、测试、证据或实现/修复报告。唯一仓库写入为本报告；独立探针通过 stdin 执行，未落盘到仓库。

> 结论先行：上轮 `CHANGES_REQUIRED` 的**核心阻断项 F-01、F-02 已关闭**；F-03/F-05/F-06/F-07/F-08 已按修复/裁定关闭或降为登记残余。构建、lint、host 479/479、ohosTest 编译均独立复验通过；F-01 的规范化重放、F-02 的全新成员设备 KEY_WRAP 端到端、F-03 的跨重启单次接受、F-05 的失败补偿与重试均由独立探针复现通过。未发现新的 High/阻断级缺陷。仍有 **1 项 Medium 契约登记缺口（R2-01：`releaseReceipt` 未进入 DES-B §23.3）**、若干 Low/Info 残余（ADR-003 文本、撤销清理重试、补偿失败登记、报告 469 旧计数），因此给出**代码级条件式 PASS**；`STABLE`、Integration/Stage Gate、设备 PASS 与用户验收均未授予。

---

## 1. 范围、revision 与输入完整性

### 1.1 范围

```text
entry/src/main/ets/service/          # auth/、family/、invite/ 的修复面
entry/src/main/ets/repository/       # FamilyRepository.importFamily
entry/src/test/                      # host tests、DomainFakes、harness
artifacts/50-implementation/t13-fix-report.md
```

- 实际被审变更为 `5b54a1f..69d5374` 的 18 个路径；与修复报告 §5 的变更清单一致：`InviteCodec.ets`、`InviteService.ets`、`InviteServiceAdapter.ets`、`FamilyModels.ets`、`FamilyService.ets`、`AuthService.ets`、`FamilyRepository.ets`、`DomainFakes.ets`、`AuthService.test.mjs`、`InviteService.test.mjs`、`family-host-helpers.mjs`、`t13-family-auth.md`、`t13-fix-report.md`、5 个证据日志。
- 只读核对的上游/邻近面：`DES-A §12/§13`（含 T-13 裁定同步）、`DES-B §3.1.2/§3.3.4/§23.3/§23.6`、`ADR-003 §5.4`、`contract-baseline.md`、`project-constraints.md`、`test-plan.md`、C-08 调用面（`FamilyService`/`FamilyJoinSession`）与存储端口（`SecretStore`/`AssetStoreSecretStore`/`DomainOperationGate`）。这些文件未在本次写范围内，未修改。
- **明确排除**：真实设备/模拟器、真实平台 Asset Store/RDB/`cryptoFramework`、真实 BLE 轮换、C-08/C-22/C-28 组合根与 UI、用户验收、T-19 全量测试报告。上述保持 `BLOCKED`/`NOT_RUN`，本报告不写成 PASS。

### 1.2 输入 pin 与快照

handoff 的 9 个 `inputs` SHA-256 **9/9 一致**；`config/git-policy.json` 的 SHA-256（`3b8ddffd...`）与 handoff 一致；复验前后 `git status` clean，HEAD = `69d5374`，`base_commit`/`task_branch` 与 handoff 一致；snapshot ref `...20261017T143502Z-wp-053-review-t13b-c7dcd3d3` 存在。

| 输入 | SHA-256 前 12 位 | 结果 |
|---|---|---|
| `artifacts/70-review/t13-review.md` | `58f71f777fbf` | 一致 |
| `artifacts/50-implementation/t13-fix-report.md` | `49719e5abfb7` | 一致 |
| `artifacts/50-implementation/t13-family-auth.md` | `1acdb059de19` | 一致 |
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `3a02ecbf266b` | 一致 |
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | `b96eb113031f` | 一致 |
| `artifacts/20-architecture/adr-003-family-credential-distribution.md` | `14b52fe6cd1b` | 一致 |
| `artifacts/20-architecture/contract-baseline.md` | `883e09bb34ea` | 一致 |
| `artifacts/20-architecture/project-constraints.md` | `283046210e68` | 一致 |
| `artifacts/60-testing/test-plan.md` | `33485cc39abd` | 一致 |
| `config/git-policy.json` | `3b8ddffd4494` | 一致 |

### 1.3 独立复验命令（cwd = 仓库根）

| 命令 | 结果 | 说明 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS：479 tests / 479 pass / 0 fail / 0 skipped / 0 todo，exit 0** | 与 `artifacts/50-implementation/evidence/t13-fix/host-tests.log` 的 479/479 一致；修复新增 10 项，基线 469 项保留 |
| `codelinter -c code-linter.json5 -p default .` | **PASS：No defects found in your code.，exit 0** | 与 `.../t13-fix/codelinter.log` 一致 |
| `hvigorw clean assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0**（35 tasks；34 executed / 1 up-to-date） | 与 `.../t13-fix/hvigor-assemble-hap.log` 一致；未配置签名 WARN，预期 |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0**（35 tasks） | 与 `.../t13-fix/ohostest-compile.log` 一致；**仅编译，不是设备执行** |
| `git diff --check` / `git status --short` | **PASS：exit 0 / clean** | 无空白错误、无未声明仓库改动 |
| 设备执行 | **BLOCKED（未写成 PASS）** | 无设备/模拟器/签名；`AuthInviteDevice.test.ets` 仅编译 |

测试证据核对：修复轮 `host-tests.log` 为 479 条 `ok`；本次独立复跑用例名与证据一致；`t13-family-auth.md` §3 的 479/479 与修复报告一致。设备项仍为 `BLOCKED_ON_DEVICE_RUNNER`。

### 1.4 独立只读探针（不修改仓库）

除现有测试外，本评审通过 stdin 直接调用真实 `InviteService`/`FamilyService` 与共享 harness，复验四项核心行为：

1. **F-01 精确复现上轮绕过场景**：`maxUses=4`，member-a（used=1）、member-b（used=2）；将 a 的 YCP1 JSON 键序改为 `v/memberId/mac/inviteId/acceptedAt` 后重编码 → **`INVITE_RECEIPT_INVALID`，usedCount 保持 2，账本仍 2 条**；再重放 a 原文 → `INVITE_RECEIPT_INVALID`；member-c 成功 → usedCount=3。
2. **F-01/F-06 负例矩阵**：空白、额外字段、未知 `v`、错误 MAC、裸 hex、错误前缀、多段/空载荷、重复键、带 padding/非 canonical b64url 全部 `INVITE_RECEIPT_INVALID`；负例前后账本 0 条；随后 canonical 回执成功、账本 1 条。
3. **F-02 全新成员设备**：管理端 harness 建家庭并生成 YCI1；成员端为仅迁移、`listFamilies()==0` 的独立 harness；KEY_WRAP 接受成功，导入固定 `familyId`、`owner_member_id=00000000-...`、成员 1 名、档案 0、`activeFamily` 未写入、网关应用 1 次；重放返回 `INVITE_KEY_MISSING`。
4. **F-03/F-05**：CODE_KEK 首次接受写 `yaocore.invite.accepted.<inviteId>`；同服务再次接受与重启后新服务均 `INVITE_INVALID`，成员数不增。C-08 事务注入 `STORAGE_RDB_ERROR` 后账本 0 条，重试同一回执成功、`usedCount=1`。

探针仅使用内存 fake 与 Node host oracle，不构成设备证据。

---

## 2. F-01..F-18 关闭状态

严重度沿用上轮定义：**High** = 可绕过 R3-01 安全语义或阻断主流程；**Medium** = 契约/测试/一致性缺口；**Low/Info** = 卫生、过程或已登记残余。`CLOSED` 仅指本 revision 的代码/契约证据；`CLOSED_WITH_RESIDUAL` 表示行为已修复且残余已登记；`OPEN` 表示本轮未处理或仍待外部动作。

| ID | 上轮严重度 | 本轮状态 | 依据/说明 |
|---|---|---|---|
| **F-01** YCP1 语义重放 | High | **CLOSED** | `InviteCodec.decodeReceipt` 强制 `encodeReceipt(payload)===text`（`InviteCodec.ets:368-402`）：拒绝键序、空白、转义、额外字段、重复键、非 canonical b64url、裸 hex、多段信封、未知 `v`；`verifyReceipt` 对 canonical 字节计算 `receiptHash`（`InviteService.ets:404-416`），账本不再哈希原始文本。测试 `C13_receipt_variantReplayIsRejectedWithoutConsumingUse`、`C13_receipt_negativeMatrixDoesNotWriteLedger` 通过；独立探针复现关闭。残余见 R2-02（ADR-003 文本）。 |
| **F-02** 新成员无 family 行 | High（集成） | **CLOSED** | `FamilyRepository.importFamily`（`FamilyRepository.ets:236-267`）按邀请固定 `familyId`、幂等、不生成 UUID、owner 占位、不建成员/档案/ADMIN/activeFamily；`InviteService.acceptInvitation` 在解封及 `bundle.familyId===header.familyId` 后调用（`InviteService.ets:307-310`），删除旧 `CONFIGURATION_ERROR` 前置。测试 `C13_accept_newDevice_importsFamilyWithoutPreSeededRow`、`C13_importFamily_idempotentAndKeepsNameOnSameIdOnly` 与独立探针通过。 |
| **F-03** CODE_KEK 设备级单次 | Medium | **CLOSED_WITH_RESIDUAL** | 认证成功后写持久 marker `yaocore.invite.accepted.<inviteId>`（`InviteService.ets:300-339,760-788`）；重复/重启后接受在写成员/路由前 `INVITE_INVALID`；后续步骤异常删除 marker。测试 `C13_codeKek_...OnlyOnceAcrossRestart`、`C13_keyWrap_joinKeyDeleteFailure...` 与独立探针通过。marker 写后崩溃窗口（T13-R-11/R-FIX-02）已如实登记。 |
| **F-04** 账本跨进程声明 | Medium | **CLOSED（文档/注释）** | `InviteService.ets:12-21` 明确 `put` 为 upsert、`LEDGER_GATE` 仅单进程、多进程需 RDB 唯一约束/互斥；`t13-family-auth.md` §2.1 同步更正，不再以别名唯一性论证跨进程单接受者。多进程 host 不覆盖，`NOT_RUN`。 |
| **F-05** 账本 write-ahead | Medium | **CLOSED（行为）+ R2-01 契约登记** | 新增 `releaseReceipt`（`InviteService.ets:419-440`、`FamilyModels.ets:330-331`、Adapter `:68-70`）；C-08 在 `importReceipt` 失败后补偿并重抛（`FamilyService.ets:397-435`），补偿失败只记录稳定原因码。测试 `C13_receiptLedger_c08FailureCompensatesAndRetrySucceeds` 与独立探针通过。`releaseReceipt` 未登记到 DES-B §23.3，见 R2-01。 |
| **F-06** 回执负例缺口 | Medium | **CLOSED** | 新增错误 MAC、错误 `inviteId`、未知 `v`、额外字段、空白、重复键、多段/空载荷、错误前缀、裸 hex、非 JSON 载荷矩阵；所有失败不写账本（`InviteService.test.mjs:416-464`）；独立探针补充 padded/non-canonical b64url 亦拒绝。 |
| **F-07** YCP1 未入契约 | Medium | **CLOSED（DES-A/端口）** | `DES-A §13.2/§13.2.1`（`:3229-3258`）正式定义 canonical `YCP1`、拒绝非规范/裸 hex、`receiptHash` 对 canonical 字节；`InviteServicePort` JSDoc（`FamilyModels.ets:319-331`）同步。残余 R2-02：ADR-003 §5.4 仍写裸 hex，DES-A §13.2.1 已记录上游冲突但未改 ADR。 |
| **F-08** GUEST `canExecuteScene` | Low/Medium | **CLOSED（按裁定）** | `AuthService.ets:501-508` 对 GUEST 返回 `RBAC_DENIED`；`C12_rbacMatrix_adminMemberGuestAndDeviceStates` 断言原因码（`AuthService.test.mjs:179-183`）；DES-A §12.1 裁定 v1 fail-closed。 |
| **F-09** 秘密清零残余 | Low | **CLOSED_WITH_RESIDUAL** | `t13-family-auth.md` §4（`:145`）与 T13-R-07 明确 bundle JSON、`seedHex`/`commandSecretHex` 字符串及 X25519 handle 不可清零，未声称“全部秘密已清零”；修复报告 §1/§4 一致。 |
| **F-10** join 私钥删除 best-effort | Low | **MITIGATED / CLOSED_WITH_RESIDUAL** | accepted marker 使删除失败后同设备仍不能重复接受；`C13_keyWrap_joinKeyDeleteFailure...` 覆盖；删除失败仍登记（R-FIX-03/T13-R-11），私钥可能驻留 Asset Store。 |
| **F-11** changePassword 崩溃窗口 | Low | **CLOSED_WITH_RESIDUAL** | 新增 `C12_changePassword_rdbFailureRestoresOldHash`（`AuthService.test.mjs:217-230`）；行为未改，进程崩溃非原子窗口登记 T13-R-13/R-FIX-05。 |
| **F-12** createProfile 并发 alias | Low | **CLOSED（单进程）** | 静态 `PROFILE_GATE` 串行化复核 + Asset 写入 + RDB 插入（`AuthService.ets:100-106,168-217`）；`C12_createProfile_concurrentSameAliasKeepsWinnerHash` 证明唯一成功且胜者 hash 保留；多进程唯一索引仍登记 T13-R-14。 |
| **F-13** seed/账本生命周期 | Low/Medium | **PARTIAL / CLOSED_WITH_RESIDUAL** | 撤销成功后删除 Admin seed（`InviteService.ets:444-465`），`C13_revoke_removesAdminSeedAlias` 通过；解散/过期清理、账本保留策略登记 T13-R-12/R-FIX-06。新发现 R2-03：已 REVOKED 早退使首次删除失败后不再重试 seed 清理。 |
| **F-14** 设备 skeleton 迁移断言 | Low | **OPEN（未在本轮范围）** | 修复报告 §1.1 明确未改；设备仍 `COMPILED_ONLY`/`BLOCKED`。 |
| **F-15** test-plan SEC-N22/N23 | Low（过程） | **OPEN（未在本轮范围）** | `test-plan.md:334-335,561,569` 仍 `NOT_RUN`；由 test-engineer/Orchestrator 更新，不能把 host 证据自动写成 PASS。 |
| **F-16** 实现 finish 覆盖 | Info（过程） | **OPEN（记录项）** | 由 CQG/Checkpoint 记录“实现 finish 覆盖旧提交、修复提交 69d5374 经本复审确认”；本报告不把它当作已覆盖的 finish。 |
| **F-17** C-12 未共享 gate | Low（O-1） | **OPEN（观察项）** | 修复未改 AuthService 事务 gate 边界；保持 Low 观察，不单独阻断。 |
| **F-18** KEY_WRAP displayName | Low | **OPEN（后续契约定稿）** | 修复未改；Admin 侧仍以 memberId 作为显示名，登记后续同步。 |

**核心项结论**：F-01/F-02 关闭；F-03/F-05/F-06/F-07/F-08 关闭或按裁定关闭；F-09..F-13 的残余均已登记（R2-03 补充撤销清理缺口）。F-14..F-18 仍为 Low/Info/过程项，未在本轮修复范围内，CQG 记录不得把它们写成已关闭。

---

## 3. 新发现（R2-xx）

| ID | 严重度 | 位置 | 问题/影响 | 建议/依据 |
|---|---|---|---|---|
| **R2-01** | **Medium（契约/API 登记）** | `FamilyModels.ets:314-331`（`InviteServicePort.releaseReceipt`）；`InviteService.ets:419-440`；`InviteServiceAdapter.ets:68-70`；`DES-B §23.3:5681-5687` | 为 F-05 补偿新增了公开端口方法 `releaseReceipt`，并给 DES-A §13.1 冻结的 `InviteService` 增加了公开方法；但 DES-B §23.3 扩展表只有 `EXT-DES-B-24/25`，没有 `releaseReceipt` 的扩展条目，architect 的 `wp-051` 裁定也明确 F-05 不在其范围。影响：C-08 消费一个未登记的公开契约方法；该方法可删除 `(inviteId, receiptHash)` 账本条目，若未来暴露给 C-22/UI 会重新打开历史回执重放面。当前仅 C-08 失败补偿调用，未见外部利用路径。 | 由 solution-architect 在 DES-B §23.3/§23.6 登记（建议 `EXT-DES-B-26`），明确“仅 C-08 补偿、非通用 API”的语义与访问边界；在登记前不把 C-13 标 `STABLE`。本项不改变 F-05 行为已验证的事实。 |
| **R2-02** | **Low/Medium（契约一致性）** | `ADR-003 §5.4:214-218`（`receipt = hex_lower(HMAC(...))`）vs `DES-A §13.2.1:3229-3258`（canonical `YCP1`） | DES-A 已正式化 YCP1 并明确“不兼容裸 hex”，但 ADR-003 原文仍把回执定义为裸 hex；DES-A `:3246` 仅记录“ADR-003 未修改”的上游冲突。F-07 的代码/端口关闭成立，但上游文本仍不一致，读者可能按 ADR 实现裸 hex 消费方。 | architect 同步 ADR-003 §5.4，或在 Change Impact/Decision 中记录“DES-A §13.2.1 优先、ADR 文本待同步”；CQG 记录为 contract tracking，不阻断当前代码。 |
| **R2-03** | **Low（生命周期/秘密卫生）** | `InviteService.ets:449-451`（REVOKED 早退）；`:461-465`（seed 删除 best-effort）；`FamilyService.ets:378-390`（REVOKED 早退） | 首次撤销若 seed 删除失败，`removeQuietly` 吞掉错误；之后再次 revoke 因状态已 REVOKED 直接返回，不再尝试删除 seed。`C13_revoke_removesAdminSeedAlias` 只覆盖首次成功路径。影响：Admin seed 可能长期驻留 Asset Store；不是回执重放绕过（REVOKED 在读取 seed 前拒绝），但 F-13/报告“撤销已清理”应限定为 best-effort。 | 在撤销/清理任务中支持“已 REVOKED 仍重试 seed 删除”，或增加周期清理；报告 F-13/T13-R-12 明确首次删除失败不重试的性质。 |
| **R2-04** | **Low（残余登记）** | `t13-fix-report.md:21`（“补偿失败只记录稳定原因码”）；§4 残余表 `:78-86` | `releaseReceipt` 自身失败时账本条目保留，合法回执被烧毁、重试仍会失败；修复报告仅在 F-05 处置中描述，未把该失败路径作为独立残余/跟踪项登记。 | 在 T13-R 系列新增“补偿失败导致 reservation 残留”Low 残余；无需代码阻断，补测试或明确接受。 |
| **R2-05** | **Info（文档一致性）** | `t13-family-auth.md:203` vs `:135` | §7 追踪表仍写“469 host tests PASS”，而 §3 已更新为 479/479；同一实现报告内计数不一致。 | 更新为 479，避免 CQG/后续任务引用旧计数。 |

> R2-01 是本轮唯一 Medium；其余为 Low/Info。未发现新的 High/安全绕过或主流程阻断。

---

## 4. 关键项复核细节

### 4.1 F-01：canonical 信封与账本身份

- `decodeReceipt` 的规范化检查在 **HMAC 与账本之前**执行：非法编码不会读取 seed、不会写账本、不会触碰 C-08 状态；`receiptHash` 只对 `encodeReceipt(payload)` 的 canonical 字节计算（`InviteService.ets:404-416`）。因此“同字段、不同键序/空白/转义”的变体得到同一 hash，不能新增账本条目。
- 独立探针复现上轮 F-01 的精确攻击：variant 被拒、`usedCount` 保持 2、原回执重放仍被识别、后续 member-c 正常消耗到 3；负例矩阵覆盖 10 类非规范输入，均未写账本。
- **残余**：canonical 信封与旧裸 hex 消费方不兼容；DES-A 已明确“不声称互操作”。ADR-003 文本未同步（R2-02）。

### 4.2 F-02：全新成员设备 KEY_WRAP 主流程

- `importFamily` 使用 `header.familyId`，不调用 `UuidUtil.newUuid`；`owner_member_id` 为 `00000000-0000-0000-0000-000000000000`；不写 `activeFamilyId`、不建 `LocalProfile`/成员/ADMIN；重复导入返回原行且不覆盖名称（`FamilyRepository.ets:236-267`）。
- 独立探针从空 `family` 表开始，经管理端建家庭/YCI1、成员端接受：导入固定 ID、成员 1、档案 0、activeFamily 未设置、网关应用 1；第二次接受 `INVITE_KEY_MISSING`。关闭 F-02。
- **残余**：导入家庭 owner 为占位，`transferAdmin` 在权威 owner 收敛前不可用；DES-B `RISK-IMPORTED-FAMILY-OWNER` 已登记，属后续接触式收敛，不阻断本轮。

### 4.3 F-03/F-05：设备单次接受与 C-08 补偿

- `claimAcceptance` 在容器解封与 bundle 校验后、写家庭成员/路由前执行；marker 通过 Asset Store 持久化，跨 service 重启有效；后续异常路径删除 marker。独立探针与 `C13_codeKek_...AcrossRestart` 均显示第二次/重启后 `INVITE_INVALID` 且成员数不增。
- `FamilyService.importReceipt` 在 `verifyReceipt` 成功后进入 try；任何 C-08 失败调用 `releaseReceipt` 删除 canonical 账本条目并重抛；独立探针确认 `STORAGE_RDB_ERROR` 后账本 0、重试成功、`usedCount=1`。
- **残余**：marker 写后崩溃窗口（R-FIX-02/T13-R-11）；补偿失败残留（R2-04）；账本/标记单进程语义（R-FIX-01）。这些均为已知、可解释的残余，不是本轮新增加密缺陷。

### 4.4 F-07/F-08：契约与 RBAC

- DES-A §13.2/§13.2.1 与 `InviteServicePort` JSDoc 已落文 canonical YCP1、拒绝非规范/裸 hex、canonical hash；实现与文本一致。F-07 代码/端口关闭；ADR-003 文本冲突见 R2-02。
- `canExecuteScene` 对 GUEST 返回 `RBAC_DENIED`，测试断言原因码；DES-A §12.1 裁定 v1 fail-closed。F-08 关闭（低风险契约项）。

---

## 5. 回归与安全复核

| 检查面 | 结论 | 证据/说明 |
|---|---|---|
| D-022 / `maxUses` / `ACCEPTED` 非终态 | **PASS** | `C13_receiptLedger_replayAcrossRestart_d022` 及新增多设备 harness 通过；历史回执拒绝、不同回执继续消耗、用尽后 `INVITE_MAX_USES` |
| 回执 HMAC 公式 | **PASS（未变）** | `InviteCodec.receiptSigningText`/`buildReceipt`/`verifyReceipt` 的 `YAOCORE-INVITE-RECEIPT-V1\n...` 未改；YCP1 只承载 `memberId/acceptedAt`，未改变 MAC 覆盖范围 |
| AEAD/AAD 语义 | **PASS（未变）** | `InviteCodec.ets` 仅修改回执解码；YCI1 header 原始字节作为 AAD、IV/tag 长度检查未变；既有 AAD 篡改用例通过 |
| 版本/过期/撤销 fail-closed | **PASS** | `INVITE_INVALID/EXPIRED/REVOKED/MAX_USES` 既有用例与新增负例通过 |
| 秘密/日志卫生 | **PASS（代码/host）** | 未新增日志泄漏；F-09/F-10 残余如实登记；无“全部秘密已清零”表述 |
| 分层/依赖方向 | **PASS** | `InviteService`/`FamilyService`/`FamilyRepository` 无平台 import；依赖方向 service → repository/storage/model；`importFamily` 属 DES-B 明确扩展 |
| 测试质量 | **PASS（风险相称）** | 10 项新增测试覆盖 F-01/F-02/F-03/F-05/F-06/F-10/F-11/F-12/F-13；负例矩阵与独立探针补充了边界；设备层仍只编译 |
| i18n/重复代码 | **PASS/N/A** | 本次无新增 UI/错误文案；无重复代码变体 |
| 设备/真实平台 | **BLOCKED（诚实）** | 无设备/签名；ohosTest 仅编译；真实 PBKDF2/X25519/AES-GCM/Asset Store/RDB 未执行 |

**SEC 结论**：未发现新的密码学原语缺陷或可复现的 R3-01 绕过；F-01 的语义重放已关闭。剩余风险集中在设备级单次 marker 的崩溃窗口、补偿失败与账本/标记的单进程边界，均为已登记残余，不是新的 High 项。

---

## 6. CQG-T13 对照与最终意见

| 检查面 | 结论 | 证据/边界 |
|---|---|---|
| 构建 | **PASS** | `hvigorw clean assembleHap --no-daemon` exit 0，BUILD SUCCESSFUL（35 tasks）；未签名 WARN 预期 |
| 静态检查 | **PASS** | `codelinter` exit 0，No defects |
| Host 测试 | **PASS** | 479/479，0 fail/0 skip/0 todo，exit 0；新增 10，基线保留；证据日志一致 |
| 契约符合 | **PASS（代码级，条件式）** | F-01/F-02/F-03/F-05/F-06/F-07/F-08 已关闭或按裁定关闭；R2-01（`releaseReceipt` 未入 DES-B §23.3）与 R2-02（ADR-003 文本）为条件项；F-15 test-plan 状态仍 `NOT_RUN` |
| 安全（SEC） | **PASS（代码/host）** | F-01 规范化重放关闭；F-03 持久 marker；F-05 补偿；F-09/F-10/F-13 残余登记；无 LAN GCM/新原语 |
| 分层/依赖方向 | **PASS** | 无平台 import；repository/service 边界与 DES-B 扩展一致；C-12 的 `PROFILE_GATE` 为进程内串行化，已登记多进程边界 |
| 独立评审 | **PASS** | 本报告由未参与实现/裁定/修复的 reviewer 出具；作者未自批 |
| 设备/真实平台 | **BLOCKED** | 无设备/模拟器/签名；ohosTest 仅编译；真实平台 PBKDF2/X25519/GCM/Asset/RDB 未执行；不得写成 PASS |
| 可追溯/证据 | **PARTIAL** | F-14/F-15/F-16/F-17/F-18 仍为 Low/Info/过程项；R2-05 旧计数 469 待改；CQG 需记录修复 finish 覆盖 69d5374 |
| **CQG-T13 总体意见** | **PASS（代码级，条件式）** | 核心 F 项已关闭，构建/lint/host/安全/分层/独立评审满足当前 revision 的代码级证据；条件与残余见下 |

**建议 CQG 记录（条件）**：

1. 以 **`CQG-T13 @ 69d5374` 代码级 PASS（条件式）** 记录；附本报告、479/479 host、codelinter、clean assemble、ohosTest 编译（仅编译）证据与 snapshot ref。
2. **R2-01**：solution-architect 在 DES-B §23.3/§23.6 登记 `releaseReceipt`（建议 `EXT-DES-B-26`），明确仅 C-08 补偿、非通用 API；登记前不把 C-12/C-13 标 `STABLE`。
3. **R2-02**：architect 同步 ADR-003 §5.4 或记录 DES-A §13.2.1 优先的 Decision；F-07 代码/端口关闭不受影响。
4. **F-14..F-18**：按原分类继续跟踪；F-15 由 test-engineer/Orchestrator 更新 test-plan 的 SEC-N22/N23 与 CQG 状态，不得把 host 证据写成设备 PASS；F-16 由 CQG 记录实现/修复 finish 覆盖关系。
5. 设备项保持 `BLOCKED_ON_DEVICE_RUNNER`；T-19 在真实设备执行 PBKDF2/X25519/AES-GCM/Asset Store/RDB 前，不得授予设备 PASS、`STABLE`、Integration/Stage Gate 或用户验收。

---

## 7. Verdict

**PASS（代码级，条件式）**

判定理由：

1. **F-01/F-02 两个上轮 High 阻断项均已关闭**：规范化重放由代码、测试与独立探针三方验证；全新成员设备 KEY_WRAP 主流程在空 family 表上端到端通过，且不误建成员/档案/activeFamily。
2. **F-03/F-05/F-06** 的修复行为成立：持久 marker 跨重启阻止重复接受；C-08 失败补偿后同一回执可重试；回执负例矩阵齐备且失败不写账本。
3. **F-07/F-08** 已按 architect 裁定落文/落码；F-04 报告措辞已更正；F-09..F-13 残余如实登记（R2-03 补充撤销清理缺口）。
4. 构建、lint、host 479/479、ohosTest 编译独立复现；D-022/HMAC/AEAD/AAD 语义未变；未发现新的 High 缺陷。
5. **R2-01** 是本轮唯一 Medium 契约登记缺口，属于新增补偿端口的文档/裁定问题，不是行为或安全绕过；**R2-02..R2-05** 为 Low/Info。故给出代码级条件式 PASS，而非无条件 PASS 或 `STABLE`。

**未授予**：C-12/C-13 `STABLE`、Integration Gate、Stage Gate、设备/真实平台 PASS、用户验收。最终 Gate 记录由 Orchestrator 依据本意见与证据作出；设备项保持 `BLOCKED_ON_DEVICE_RUNNER`。

---

## 8. 残余风险与跟踪项

| ID | 风险/跟踪项 | 级别 | 处理/owner |
|---|---|---|---|
| R2-01 | `releaseReceipt` 公开端口/frozen service 方法未登记 DES-B §23.3；账本删除 API 边界未定义 | **Medium（契约）** | solution-architect；STABLE 前登记 `EXT-DES-B-26` 或约束为 C-08 专用 |
| R2-02 | ADR-003 §5.4 仍写裸 hex，与 DES-A §13.2.1 canonical YCP1 不一致 | Low/Medium（契约一致性） | architect 同步/记录优先关系 |
| R2-03 | 已 REVOKED 早退导致 seed 删除失败不重试 | Low（生命周期） | C-13/C-08 cleanup 或周期清理；报告限定 best-effort |
| R2-04 | `releaseReceipt` 补偿失败导致账本 reservation 残留、回执被烧毁 | Low（残余登记） | 补 T13-R 跟踪/失败注入测试；当前只记录原因码 |
| R2-05 | `t13-family-auth.md` §7 仍写 469 host tests | Info（文档） | 更新为 479 |
| R-FIX-01 | Asset 账本/设备 marker 单进程语义，多进程无 CAS | Low/Medium | 多进程需 RDB `UNIQUE`/互斥；host `NOT_RUN` |
| R-FIX-02/T13-R-11 | marker 写后崩溃阻止重试；CODE_KEK 极窄窗口重试可能生成新 memberId | Low | 已登记；清除 App 数据可恢复 |
| R-FIX-03 | join 私钥删除 best-effort，可能驻留 Asset Store | Low | marker 仍阻止重复接受；后续清理 |
| R-FIX-04/T13-R-07 | 不可变字符串/X25519 handle 无法清零 | Low | 不得声称全部秘密已清零 |
| R-FIX-05/T13-R-13 | changePassword 双存储进程崩溃窗口 | Low | 异常路径已恢复；崩溃窗口登记 |
| R-FIX-06/T13-R-12 | 解散/过期 seed、账本保留策略 | Low/Medium | C-08/C-13 cleanup 契约；账本按 maxUses 有界 |
| RISK-IMPORTED-FAMILY-OWNER | 导入家庭 owner 占位，`transferAdmin` 在权威收敛前不可用 | Low（设计限制） | DES-B 已登记；接触式同步/后续 Change Impact |
| T13-R-14 | createProfile 多进程仍无唯一索引 | Low | 后续 RDB `(family_id, member_id)` 唯一索引 |
| F-14 | 设备 skeleton 迁移断言空泛 | Low | T-19/设备测试改进 |
| F-15 | test-plan SEC-N22/N23 未更新 | Low（过程） | test-engineer/Orchestrator |
| F-16 | 修复 finish/原实现 finish 覆盖关系 | Info（过程） | CQG/Checkpoint 记录 |
| F-17/F-18 | C-12 gate 边界、KEY_WRAP displayName | Low | 后续契约定稿 |
| 设备证据 | 真实 PBKDF2/X25519/GCM/Asset/RDB 未执行 | **High（证据）** | T-19；保持 `BLOCKED`，不得写成设备 PASS |

---

## 9. 独立声明与排除

- **独立性**：本报告由未参与 T-13 实现、`5b54a1f` 裁定同步或 `69d5374` 修复的 `quality-reviewer` 执行；未修改 `entry/src/main/ets/service/**`、`entry/src/main/ets/repository/**`、`entry/src/test/**`、`entry/src/ohosTest/**`、证据日志、`t13-family-auth.md` 或 `t13-fix-report.md`。唯一仓库写入为 `artifacts/70-review/t13-review-b.md`；该文件原为 Orchestrator 的 guard 占位，本报告覆写并声明自己的 `Producer`。
- **只读探针**：F-01/F-02/F-03/F-05 的复核通过 stdin 执行，未在仓库落盘；使用内存 fake 与 Node host oracle，不构成设备证据。
- **范围排除**：真实设备/模拟器、真实平台 PBKDF2/X25519/AES-GCM/Asset Store/RDB、真实 BLE 轮换、C-08/C-22/C-28 组合根与 UI、用户验收、T-19 全量测试报告；上述均为 `BLOCKED`/`UNAVAILABLE`/`NOT_RUN`，不是 PASS。
- **证据时效**：本报告只对 `69d5374` 的代码、测试、修复报告与上述 pin 输入负责；不覆盖后续 revision。最终 CQG 记录、C-12/C-13 `STABLE` 与设备/Stage Gate 由 Orchestrator 依据本意见和证据决定。

---

## 10. Handoff

```text
STATUS: RETURNED_FOR_GATE / PASS_CODE_LEVEL_CONDITIONAL
SUMMARY: 上轮 High F-01/F-02 关闭；F-03/F-05/F-06/F-07/F-08 关闭或按裁定关闭；F-04 文档修正；F-09..F-13 残余如实登记。479/479 host、codelinter、clean assemble、ohosTest 编译与独立探针（F-01 变体/负例、F-02 新设备、F-03 重启、F-05 补偿）全部通过。唯一 Medium 新发现 R2-01：releaseReceipt 未登记 DES-B §23.3；R2-02 ADR-003 裸 hex 文本未同步；R2-03 撤销 seed 清理早退不重试；R2-04 补偿失败残余未入表；R2-05 旧计数 469。
CLOSURE_TABLE: F-01 CLOSED; F-02 CLOSED; F-03 CLOSED_WITH_RESIDUAL; F-04 CLOSED(doc); F-05 CLOSED(behavior)+R2-01; F-06 CLOSED; F-07 CLOSED(DES-A/port)+R2-02; F-08 CLOSED(ruling); F-09 CLOSED_WITH_RESIDUAL; F-10 MITIGATED; F-11/F-12/F-13 CLOSED_WITH_RESIDUAL/PARTIAL; F-14..F-18 OPEN (Low/Info/process).
VERDICT: PASS（代码级，条件式）；建议 CQG-T13 以代码级 PASS（条件式）记录；R2-01/R2-02 条件关闭前不标 C-12/C-13 STABLE；设备项 BLOCKED；不授予 Integration/Stage Gate 或用户验收。
EVIDENCE: reviewed revision 69d5374；host 479/479 exit 0；codelinter No defects exit 0；clean assembleHap BUILD SUCCESSFUL exit 0（35 tasks）；ohosTest assembleHap BUILD SUCCESSFUL exit 0（仅编译）；9/9 inputs + git-policy SHA 一致；snapshot refs/swe/snapshots/20261017T143502Z-wp-053-review-t13b-c7dcd3d3（9e878d8）；本报告提交与 finish 记录见 swe_guard。
NEW_FINDINGS: R2-01 Medium（releaseReceipt 契约登记）；R2-02 Low/Medium（ADR-003 §5.4 裸 hex 文本）；R2-03 Low（REVOKED 早退不重试 seed 清理）；R2-04 Low（补偿失败残余未登记）；R2-05 Info（报告 469 旧计数）。均非 High/阻断。
RISKS: R-FIX-01 单进程账本/marker；R-FIX-02/T13-R-11 marker 崩溃窗口；R-FIX-03 join 私钥 best-effort；R-FIX-04/T13-R-07 不可清零字符串；R-FIX-05/T13-R-13 changePassword 崩溃窗口；R-FIX-06/T13-R-12 解散/过期与账本保留；RISK-IMPORTED-FAMILY-OWNER；设备证据 High（BLOCKED）。
NEEDS_CLARIFICATION: R2-01/R2-02 由 solution-architect 登记/同步；F-15 由 test-engineer/Orchestrator 更新；F-16 由 CQG/Checkpoint 记录；设备语义由 T-19 执行。
NEXT_ACTION: Orchestrator 以 69d5374 + 本报告记录 CQG-T13 代码级 PASS（条件式）；安排 R2-01 契约登记与 R2-02 ADR 同步；保留 F-14..F-18 与设备 BLOCKED 跟踪；条件关闭后再评估 C-12/C-13 STABLE。
```
