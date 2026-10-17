# T-13 评审修复报告（F-01..F-13）

- **Artifact ID**: IMPL-T13-FIX
- **Producer**: `agent:implementation-engineer`
- **Task**: `wp-052-fix-t13`（task 分支 `task/wp-049-family`；父分支 `feat/yaocore-app`）
- **Base commit**: `5b54a1fa61ca46706eba4842d24c31300bfca4d1`（T-13 实现 + 评审 + architect 裁定同步）
- **Status**: `UNVERIFIED`（修复与本地验证完成；等待独立复审/CQG-T13）
- **Inputs**: `artifacts/70-review/t13-review.md`、`artifacts/50-implementation/t13-family-auth.md`、DES-A §12/§13（含 T-13 裁定同步）、DES-B §3.1.2/§3.3.4/§23.6、ADR-003、`contract-baseline.md`、`project-constraints.md`、`test-plan.md`
- **Frozen semantics**: D-022、回执 HMAC 公式、AEAD/AAD 语义、G-004 均未改变。

---

## 1. 逐条处置

| Finding | 严重度 | 处置 | 代码/证据 |
|---|---|---|---|
| **F-01** YCP1 语义重放 | High | **Fixed**。`decodeReceipt` 强制 `encodeReceipt(decodeReceipt(text)) === text`：拒绝非字典序键、空白、转义差异、额外字段、重复键、非 canonical b64url、裸 hex、畸形/多段信封、未知 `v`。`receiptHash` 改为对 `encodeReceipt(payload)` 的 canonical 字节计算，不再哈希原始输入；`receiptHash` 域分离仍绑定 `inviteId`。 | `entry/src/main/ets/service/invite/InviteCodec.ets`、`InviteService.ets`；测试 `C13_receipt_variantReplayIsRejectedWithoutConsumingUse`、`C13_receipt_negativeMatrixDoesNotWriteLedger` |
| **F-02** 新成员设备无 family 行 | High（集成） | **Fixed**。`FamilyRepository.importFamily(familyId, familyName)`（`EXT-DES-B-25`）按已认证邀请固定 `familyId` 创建/确保家庭行：幂等、不生成 UUID、不创建成员/档案/ADMIN、`owner_member_id=IMPORTED_FAMILY_OWNER_PLACEHOLDER`、不写 `activeFamilyId`。C-13 在 AEAD/bundle 校验通过后调用；删除“无 family 行 → CONFIGURATION_ERROR”前置检查。 | `FamilyRepository.ets`、`InviteService.ets`；测试 `C13_accept_newDevice_importsFamilyWithoutPreSeededRow`（两个 harness，KEY_WRAP 端到端）、`C13_importFamily_idempotentAndKeepsNameOnSameIdOnly` |
| **F-03** CODE_KEK 设备级重复接受 | Medium | **Fixed**。认证成功后写持久标记 `yaocore.invite.accepted.<inviteId>`（Asset Store，跨服务重启）；同一设备再次接受在写成员/路由前以 `INVITE_INVALID` 拒绝；后续步骤异常时删除标记以允许合法重试。KEY_WRAP 仍删除一次性 join 私钥。 | `InviteService.ets`；测试 `C13_codeKek_sameDeviceAcceptsInviteOnlyOnceAcrossRestart`、`C13_keyWrap_joinKeyDeleteFailureStillCannotBeAcceptedTwice` |
| **F-04** 账本跨进程声明不准确 | Medium | **Fixed（文档/注释）**。删除“Asset 别名唯一性保证跨进程单接受者”的措辞；明确 `put` 为 upsert、`LEDGER_GATE` 仅单进程、`(inviteId, receiptHash)` 键设计保证单进程唯一；多进程需 RDB 唯一约束/互斥。实现报告 §2.1 与 `InviteService.ets` 顶部注释已同步。 | `InviteService.ets`、`t13-family-auth.md` §2.1 |
| **F-05** 账本 write-ahead 烧毁回执 | Medium | **Fixed（补偿）**。新增 `InviteServicePort.releaseReceipt(receiptText, inviteId)`：C-08 `applyReceiptAndEnsureMember`/成员构造/家庭读取任一失败时删除本次 canonical 账本条目并重抛原始错误；补偿失败只记录稳定原因码。重试同一合法回执可成功。 | `FamilyModels.ets`、`InviteServiceAdapter.ets`、`InviteService.ets`、`FamilyService.ets`；测试 `C13_receiptLedger_c08FailureCompensatesAndRetrySucceeds` |
| **F-06** 回执负例缺口 | Medium | **Fixed（测试）**。新增错误 MAC、错误 `inviteId`、未知版本、额外字段、空白、重复键、多段/空载荷、错误前缀、裸 hex、非 JSON 载荷；所有失败均不写账本。 | `entry/src/test/host/InviteService.test.mjs` |
| **F-07** YCP1 未入契约 | Medium | **由 architect 裁定同步关闭**（`5b54a1f`，DES-A §13.2/§13.2.1）；本轮实现按 canonical 信封收紧并拒绝裸 hex，不再声称互操作。 | `artifacts/40-detailed-design/des-001a-foundation-transport.md` |
| **F-08** GUEST `canExecuteScene` | Low/Medium | **Fixed（按裁定）**。v1 对 GUEST 一律 `RBAC_DENIED`（DES-A §12.1 裁定）；实现本已 fail-closed，本轮补充注释、测试断言原因码并同步报告。 | `AuthService.ets`；`C12_rbacMatrix_adminMemberGuestAndDeviceStates` |
| **F-09** 秘密清零残余 | Low | **登记，不代码修复**。`Uint8Array`/`SecureBytes` 已清零；bundle JSON、`seedHex`/`commandSecretHex` 是不可变字符串，Admin 临时 X25519 私钥 handle 无 `CryptoPort` 销毁入口。报告 §4/T13-R-07 明确不得声称“全部秘密已清零”。 | `t13-family-auth.md` §4、§6 |
| **F-10** join 私钥删除 best-effort | Low | **缓解 + 登记**。保留 best-effort 删除；新增设备级 accepted marker，即使删除失败也无法在同一设备重复接受（含重启）。补删除失败路径测试。 | `InviteService.ets`；`C13_keyWrap_joinKeyDeleteFailureStillCannotBeAcceptedTwice` |
| **F-11** changePassword 双存储崩溃窗口 | Low | **测试 + 登记**。异常注入验证失败后旧 hash 恢复、旧密码仍可用；进程崩溃窗口仍为残余（T13-R-13）。 | `AuthService.ets` 行为未改；`C12_changePassword_rdbFailureRestoresOldHash` |
| **F-12** createProfile 并发 alias 删除 | Low | **Fixed（单进程）**。静态 `PROFILE_GATE` 串行化“复查 + Asset 写入 + RDB 插入”；失败者不再可能删除成功者的 hash。并发用例证明只有一个成功且胜者凭据有效。多进程仍需唯一索引（T13-R-14）。 | `AuthService.ets`；`C12_createProfile_concurrentSameAliasKeepsWinnerHash` |
| **F-13** seed/账本生命周期 | Low/Medium | **部分 Fixed + 登记**。`revokeInvitation` 成功后删除 Admin seed 别名并补测试；解散/过期清理与账本保留策略需要 C-08/C-13 cleanup 契约（Change Impact），账本仅存 hash/公开元数据且按每邀请 `maxUses` 有界，记入 T13-R-12。 | `InviteService.ets`；`C13_revoke_removesAdminSeedAlias` |

### 1.1 明确未处理（不在本轮委托范围）

- **F-14**：设备 skeleton 迁移断言仍为 `COMPILED_ONLY`；设备执行仍 `BLOCKED_ON_DEVICE_RUNNER`。
- **F-15**：`test-plan.md` 的 SEC-N22/N23 状态更新归 `test-engineer`/Orchestrator。
- **F-16**：实现 finish 覆盖范围由 Orchestrator/CQG 记录。
- **F-17/F-18**：C-12 共享 gate 的分层说明、KEY_WRAP displayName 传递属于后续契约定稿；本轮未改。

---

## 2. 新增/修改的测试

新增 10 项（host 总数 469 → **479**）：

| 测试 | 覆盖 |
|---|---|
| `C12_changePassword_rdbFailureRestoresOldHash` | F-11 异常恢复 |
| `C12_createProfile_concurrentSameAliasKeepsWinnerHash` | F-12 并发 alias/回滚 |
| `C13_accept_newDevice_importsFamilyWithoutPreSeededRow` | F-02 全新成员设备 KEY_WRAP 端到端 |
| `C13_importFamily_idempotentAndKeepsNameOnSameIdOnly` | F-02 幂等/同名不同 id/无成员 |
| `C13_codeKek_sameDeviceAcceptsInviteOnlyOnceAcrossRestart` | F-03 持久单次接受 |
| `C13_keyWrap_joinKeyDeleteFailureStillCannotBeAcceptedTwice` | F-10 删除失败仍不可重复接受 |
| `C13_receipt_variantReplayIsRejectedWithoutConsumingUse` | F-01 评审复现场景 |
| `C13_receipt_negativeMatrixDoesNotWriteLedger` | F-01/F-06 负例矩阵 |
| `C13_receiptLedger_c08FailureCompensatesAndRetrySucceeds` | F-05 补偿 + 重试成功 |
| `C13_revoke_removesAdminSeedAlias` | F-13 撤销清理 |

修改的既有用例：`C13_receiptLedger_replayAcrossRestart_d022` 改为多个成员设备 harness（每设备独立 accepted marker）验证 D-022；`C12_rbacMatrix_*` 增加 GUEST 场景原因码断言。

---

## 3. 验证（cwd = 仓库根）

| 命令 | 结果 | 证据 |
|---|---|---|
| `ohpm install` | `install completed in 0s 54ms`，exit 0 | `artifacts/50-implementation/evidence/t13-fix/ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | **BUILD SUCCESSFUL**（35 tasks；34 executed / 1 up-to-date；未配置签名 WARN，预期），exit 0 | `.../t13-fix/hvigor-assemble-hap.log` |
| `codelinter -c code-linter.json5 -p default .` | **No defects found in your code.**，exit 0 | `.../t13-fix/codelinter.log` |
| `entry/src/test/run-host-tests.sh` | **479 tests / 479 pass / 0 fail / 0 skipped / 0 todo**，exit 0 | `.../t13-fix/host-tests.log` |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **BUILD SUCCESSFUL**（仅编译，不执行），exit 0 | `.../t13-fix/ohostest-compile.log` |
| `git diff --check` | exit 0（提交前 `git diff --cached --check` 复验） | 本次提交 |

**设备/真实平台**：`BLOCKED_ON_DEVICE_RUNNER`。真实 Asset Store、RDB、PBKDF2/X25519/GCM 未执行；不得把 ohosTest 编译写成设备 PASS。

---

## 4. 残余风险

| ID | 风险 | 级别 | 说明 |
|---|---|---|---|
| R-FIX-01 | Asset 账本/设备 marker 单进程语义 | Low/Medium | 多进程/多 VM 无 CAS；需 RDB 唯一约束或进程互斥（与 DES-B §23.6 一致）。host 不覆盖多进程，标 `NOT_RUN`。 |
| R-FIX-02 | accepted marker 写后崩溃/极窄失败窗口 | Low | 异常路径会删除 marker；写 marker 后进程崩溃会阻止同一设备重试，需清除 App 数据。CODE_KEK 若在成员 upsert 之后、回执生成之前失败并删除 marker，重试会生成新 memberId（极窄窗口，登记为残余）。 |
| R-FIX-03 | join 私钥删除 best-effort | Low | 删除失败时 marker 仍阻止重复接受；私钥可能驻留 Asset Store。 |
| R-FIX-04 | 不可变字符串/无 key handle destroy | Low | F-09；不得声称全部秘密已清零。 |
| R-FIX-05 | `changePassword` 崩溃窗口 | Low | RDB salt 更新与 Asset hash 非原子；异常路径已恢复旧 hash。 |
| R-FIX-06 | 解散/过期 seed 与账本保留 | Low/Medium | 撤销已清理；解散/过期需 cleanup 契约；账本按 `maxUses` 有界且不含明文秘密。 |
| R-FIX-07 | 设备/平台证据 | High（证据） | 保持 `BLOCKED`；T-19/设备阶段消费。 |

---

## 5. 变更文件

```text
entry/src/main/ets/service/invite/InviteCodec.ets
entry/src/main/ets/service/invite/InviteService.ets
entry/src/main/ets/service/invite/InviteServiceAdapter.ets
entry/src/main/ets/service/family/FamilyModels.ets
entry/src/main/ets/service/family/FamilyService.ets
entry/src/main/ets/service/auth/AuthService.ets
entry/src/main/ets/repository/FamilyRepository.ets
entry/src/test/domain/DomainFakes.ets
entry/src/test/host/AuthService.test.mjs
entry/src/test/host/InviteService.test.mjs
entry/src/test/host/family-host-helpers.mjs
artifacts/50-implementation/t13-family-auth.md
artifacts/50-implementation/t13-fix-report.md
artifacts/50-implementation/evidence/t13-fix/*.log
```

---

## 6. 结论

F-01/F-02/F-03/F-04/F-05/F-06/F-08/F-10（缓解）/F-11（测试）/F-12（单进程）已修复或补齐证据；F-07 由 architect 裁定关闭；F-09/F-13（解散/过期/账本保留）已明确登记残余。构建、lint、host 479/479 与 ohosTest 编译全部通过。C-12/C-13 仍为 `UNVERIFIED`，等待独立复审与 CQG-T13/SEC 判定；本报告不授予 STABLE、Integration Gate、Stage Gate 或设备 PASS。
