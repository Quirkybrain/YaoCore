# T-13 — C-12 AuthService + C-13 InviteService（含 R3-01 回执账本）

- **Producer**: `agent:implementation-engineer`
- **Task**: `T-13` / handoff `wp-049-family`
- **Status**: `UNVERIFIED`（实现与本地验证完成，等待独立 CQG-T13 / SEC 评审）
- **Contracts**: DES-A §12、§13、§3.2/§3.5；DES-B §3.1.2/§3.1.3/§3.3.3/§23.6；ADR-003 §3–§6、§9；D-009/D-013/D-019/D-022/D-023
- **Write scope used**: `entry/src/main/ets/service/{auth,invite}/`、`entry/src/test/`、`entry/src/ohosTest/ets/test/`、`artifacts/50-implementation/`
- **G-004 semantics**: unchanged. No new LAN cryptography, no server, no cross-device online state.

---

## 1. 实现范围

### 1.1 C-12 AuthService（DES-A §12）

| 契约 | 实现 |
|---|---|
| `LocalProfile` / `SessionInfo` / `PolicyDecision` / `AuthPolicy` / `CreateProfileInput` | `service/auth/AuthModels.ets` |
| v3 `auth_profile` 迁移（`AuthService.registerMigrations`） | 与 DES-A §12.4 完全一致的 DDL + family index |
| PBKDF2\|SHA256 120,000、salt 16B、输出 32B | `AuthService.deriveHash`；hash 只写 `SecretStore`（`yaocore.auth.profile.<profileId>`），RDB 只存 salt/iterations 元数据 |
| `createProfile` / `getProfile` / `listProfiles` / `changePassword` | 实现；重复 profile 与同成员重复档案均 `AUTH_PROFILE_EXISTS`；密码变更失败恢复旧 hash；成功后 `lockAll` |
| 会话 idle 15min / absolute 24h | 内存 `SessionRecord`；`touch` 续 idle 且受 absolute 硬上限；读取时惰性清理 |
| `lock` / `lockAll` / `invalidateSessionsForMember` / `getSession` / `getActiveSession` | 实现；`invalidateSessionsForMember` 同步清除该成员全部会话 |
| RBAC 矩阵 | `isAdmin` / `canControl` / `canManageFamily` / `canManageRooms` / `canInvite` / `canExecuteScene`；规则按 DES-A §12.1（SESSION_EXPIRED/MEMBER_INACTIVE/DEVICE_DISABLED/DEVICE_UNASSIGNED/ROOM_NOT_ALLOWED/UNSUPPORTED_DEVICE_TYPE） |
| 多家庭 | 每家庭独立 profile；`FamilyService.switchFamily` 的 `lockAll + listProfiles` 由本服务满足；无 `rebindProfile` |
| `FamilyAuthPort` | `AuthService implements FamilyAuthPort`，供 C-08 直接注入 |
| EXT-DES-B-20 | `removeProfilesForFamily` / `removeProfilesForMember`；删除 Asset hash 与 RDB 行并使相关会话失效 |

**补充语义**：
- 错误密码与不存在 profile 统一 `AUTH_PASSWORD_INVALID`（防枚举）。
- 连续失败 5 次后进入 30s 本机内存退避窗口（指数增长，最多 4 次翻倍）；不持久化。
- GUEST 到期通过会话内 `memberExpiresAt` 惰性判定为 `MEMBER_INACTIVE`；角色/状态变化仍由 C-08 调用 `invalidateSessionsForMember`。
- `canControl` 不把 RBAC 当密码学边界（ADR-003 §6.3）：持有 `commandSecret` 者可绕过 App 策略。

### 1.2 C-13 InviteService（DES-A §13 + DES-B §23.6）

| 契约 | 实现 |
|---|---|
| `JoinRequest` / `JoinRequestContainer` / `InviteKdf` / `InviteHeader` / `GatewaySecretEntry` / `FamilySecretBundle` / `InvitationContainer` / `CreateInvitationInput` / `InvitationCreationResult` / `AcceptInvitationOptions` / `AcceptedInvitation` / `ReceiptVerification` / `RotationPlan` | `service/invite/InviteModels.ets` |
| YCR1 编解码 | `InviteCodec`：严格 2 段、b64url 无 padding、严格 JSON、字段封闭、`v=1`、`memberId` 16B hex、`pub` 32B、UTC 紧凑时间 |
| YCI1 编解码 | 4 段 `YCI1.<header>.<iv>.<ciphertext||tag>`；header 键名字典序 canonical JSON；AAD = 收到的 header 原始字节；header ≤4096B、明文 ≤32KB、容器 ≤65536B |
| KEY_WRAP | 成员一次性 X25519 密钥对（私钥仅 `yaocore.invite.join.<memberId>`）；Admin 临时 X25519；`HKDF-SHA256(shared, headerBytes, "yaocore-family-invite-v1", 32)`；`maxUses` 强制 1 |
| CODE_KEK | 6 位 Crockford Base32（`0123456789ABCDEFGHJKMNPQRSTVWXYZ`），大小写不敏感 + `O→0`、`I/L→1`；PBKDF2 120k + HKDF；salt 16B；`maxUses>=1`；码仅创建时返回 |
| AES-256-GCM | 12B 随机 IV，16B tag；AEAD/AAD 失败统一 `INVITE_INVALID`（不区分版本/码/篡改） |
| Bundle | seed 32B、逐网关 `commandSecret`（lower hex，≥16B）、可选 TLS pins/port；接受时经 `InvitationApplicationPort.applyInvitedGateway` 落路由/凭据，`SecureBytes` 用后销毁 |
| 接受 | 检查 `expireAt`/`familyId`/`keyId`/`v`；写本地 `FamilyMember(ACTIVE)`；生成回执；KEY_WRAP 成功后销毁 join 私钥别名 |
| 回执 | `HMAC-SHA256(seed, "YAOCORE-INVITE-RECEIPT-V1\n"+inviteId+"\n"+memberId+"\n"+acceptedAt)`；常数时间比较；失败 `INVITE_RECEIPT_INVALID` |
| 持久账本（R3-01） | 见 §2；唯一 `(inviteId, receiptHash)`；跨进程重启有效；重放不递增 `usedCount` |
| 撤销 | 标记本地 `REVOKED`；不执行 BLE；真正失效需逐网关轮换 |
| 轮换引导 | `rotateGatewaySecret` 返回 `invite.rotation.step.reprovision` / `verify`，不发网络、不做 BLE |
| `discardJoinRequest` | EXT-DES-B-18：删除 `yaocore.invite.join.<memberId>` 并清理内存显示名 |
| C-08 端口适配 | `InviteServiceAdapter implements InviteServicePort`，只做值形状转换；记录持久化仍由 C-08 负责 |

---

## 2. 回执账本与 D-022 语义

### 2.1 账本存储

- **介质**：平台 `SecretStore`（Asset Store）。DES-B §23.6 明确“存储介质/schema 由 T-13 实现”；C-13 冻结构造器没有 `RdbStore`，因此不新增 RDB 迁移。
- **唯一键**：`receiptHash = SHA-256("YAOCORE-INVITE-RECEIPT-HASH-V1\n" + inviteId + "\n" + receiptText)`；别名 `yaocore.invite.receipt.<receiptHash>`。因 `receiptHash` 已域分离绑定 `inviteId`，别名唯一性等价于 `(inviteId, receiptHash)` 唯一。
- **最小记录**：别名对应 JSON 元数据 `{v, inviteId, memberId, acceptedAt, receiptHash, recordedAt}`；**不存明文回执**。
- **并发**：`InviteService.LEDGER_GATE`（静态 `DomainOperationGate`）串行化“检查存在 + 写入”；单进程内无 check-then-put 竞态。跨进程单设备由 Asset Store 别名唯一性约束；不声称多进程并发 CAS。
- **验证**：`verifyReceipt` 在 HMAC 通过后检查别名；已存在 → `INVITE_RECEIPT_INVALID`，不写库、不递增 `usedCount`。

### 2.2 行为（与 §23.6 / D-022 对齐）

1. 首次回执：验证 HMAC → 写账本 → `valid=true`；C-08 随后在单事务内 `usedCount++`。
2. 历史回执重放：同 `(inviteId, receiptHash)` 再次导入（即使 `record.receipt/acceptedByMemberId` 已被其他成员覆盖）→ `INVITE_RECEIPT_INVALID`；不递增、不建/改成员。
3. 不同回执：`usedCount < maxUses` 且未过期时继续接受，按 `(inviteId, receiptHash)` 追加。
4. 错误优先级：`REVOKED` → `INVITE_REVOKED`；`EXPIRED`/`expireAt<=now` → `INVITE_EXPIRED`；`usedCount>=maxUses` → `INVITE_MAX_USES`；随后才做 HMAC/账本判定。
5. `ACCEPTED` 非终态：C-08 保持 `PENDING/ACCEPTED` 多用途语义；C-13 不把 `ACCEPTED` 当作拒绝条件。
6. 同一成员再次接受：沿用 C-08 `acceptedByMemberId` 即时防御（§23.6 明确不新增 `(inviteId,memberId)` 唯一约束）。

**R3-01 证据**：`C13_receiptLedger_replayAcrossRestart_d022`（`maxUses=3`：a→b→重放 a 拒绝且 `usedCount` 不变→重启服务再重放 a 拒绝→c 成功→用尽 `INVITE_MAX_USES`）。

---

## 3. 测试

### 3.1 新增 host 测试（18 项）

**C-12（7）** — `entry/src/test/host/AuthService.test.mjs`
1. `C12_profile_pbkdf2ParamsAndUnifiedPasswordErrors`
2. `C12_changePassword_restoresOnWrongOldAndLocksAll`
3. `C12_sessions_idleAndAbsoluteTimeout`
4. `C12_lockAllAndMemberInvalidation`
5. `C12_rbacMatrix_adminMemberGuestAndDeviceStates`
6. `C12_backoffAfterFiveFailuresAndProfileCleanup`
7. `C12_multiFamilyProfilesStayScoped`

**C-13（11）** — `entry/src/test/host/InviteService.test.mjs`
8. `C13_joinRequest_roundTripAndStrictParsing`
9. `C13_keyWrap_roundTripAppliesGatewayAndCreatesMemberReceipt`
10. `C13_codeKek_normalizesCodeAndWrongCodeFailsClosed`
11. `C13_containerRejectsAadTamperCiphertextAndUnknownVersion`
12. `C13_expiredAndRevokedInvitationsFailClosed`
13. `C13_familyJoinSession_drivesRealInviteServiceToCompleted`
14. `C13_keyWrapMaxUsesMustBeOne`
15. `C13_receiptLedger_replayAcrossRestart_d022`
16. `C13_expireInvitations_marksAcceptedMultiUseAsExpired`
17. `C13_rotationGuidanceAndDiscardAreLocalOnly`
18. `C13_ledgerStoresOnlyDomainSeparatedHash`

支撑文件：
- `family-host-helpers.mjs`：家庭/成员、fake credentials/application、错误断言。
- `host-crypto.mjs`：Node `crypto` 独立 oracle 的 `CryptoPort`（SHA/HMAC/HKDF/PBKDF2/X25519/AES-256-GCM），仅测试使用。
- `DomainHarness.ets`：v3 迁移改为 `AuthService.registerMigrations`，新增 `secrets` / `random` seam。
- `entry/src/ohosTest/ets/test/family/AuthInviteDevice.test.ets` + `List.test.ets`：设备侧真实 platform crypto 骨架；`BLOCKED_ON_DEVICE_RUNNER`。

### 3.2 结果

| 命令 | 结果 | 证据 |
|---|---|---|
| `ohpm install` | `install completed in 0s 48ms` | `artifacts/50-implementation/evidence/t13-family/ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | `BUILD SUCCESSFUL`（35 tasks；未配置签名 WARN，预期；见日志） | `.../hvigor-assemble-hap.log` |
| `codelinter -c code-linter.json5 -p default .` | `No defects found in your code.` | `.../codelinter.log` |
| `entry/src/test/run-host-tests.sh` | **469 tests / 469 pass / 0 fail**（含本次新增 18） | `.../host-tests.log` |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | `BUILD SUCCESSFUL`（仅编译，不执行；见日志） | `.../ohostest-compile.log` |

设备侧 `ohosTest` **未执行**：本环境无设备/模拟器/签名配置；`AuthInviteDevice.test.ets` 仅编译（已由上述 ohosTest HAP 编译验证 `List.test.ets` 注册），不得报告为 PASS。设备骨架覆盖真实平台 PBKDF2/X25519/AES-256-GCM + `AuthService.registerMigrations`；C-13 容器 codec 的严格路径由 host 套件覆盖（若在 ohosTest 直接 import `InviteCodec`，会触发 `common/utils/Base64Url.ets` 既有的 ArkTS 严格编译问题，该文件不在 T-13 写范围，见 T13-R-10）。

---

## 4. 安全性

- **秘密清零**：密码 UTF-8 字节、PBKDF2 输出、HKDF 输出、X25519 shared、KEK、seed、命令 secret 的临时 `Uint8Array`/`SecureBytes` 在成功/失败/取消路径 `zeroize`/`destroy`；join 私钥仅存 Asset Store，KEY_WRAP 接受成功后删除别名。
- **无日志泄漏**：C-12/C-13 不引入 `LoggerPort` 调用；错误 details 只含字段名，不含秘密/回执明文/码。
- **AEAD fail-closed**：header 原始字节作 AAD；任何 header/iv/ciphertext/tag 改动 → `INVITE_INVALID`；未知版本拒绝。
- **防 oracle**：解封失败统一 `INVITE_INVALID`；码格式错误才是 `INVITE_CODE_INVALID`；常量时间比较回执。
- **回执账本**：只存域分离 hash 与公开元数据；不存明文回执；重放拒绝先于任何 C-08 状态写。
- **RBAC 边界声明**：`canControl` 为 App 策略，不是密码学边界；GUEST 房间限制可被持有 `commandSecret` 的设备绕过（ADR-003 §6.3/DP-06）。
- **无 LAN GCM**：C-13 只使用 ADR-003 邀请容器 AES-GCM；未新增 LAN control GCM。

---

## 5. 偏离 / 契约备注（需独立评审）

1. **回执文本封装（CONTRACT-NOTE，需上游确认）**
   DES-A §13.2 将 `receipt` 定义为裸 `hex_lower(HMAC(...))`，但冻结签名 `verifyReceipt(receiptText, inviteId)` 无法从裸 HMAC 恢复 HMAC 预image 中的 `memberId`/`acceptedAt`（CODE_KEK 尤其没有 `record.memberId`）。实现保留**完全相同的 HMAC 公式**，外层增加自描述信封：
   `YCP1.<b64url(sorted JSON {v,inviteId,memberId,acceptedAt,mac})>`。
   `mac` 仍是 `HMAC-SHA256(seed, "YAOCORE-INVITE-RECEIPT-V1\n"+inviteId+"\n"+memberId+"\n"+acceptedAt)`；账本仍只存 hash。
   **建议**：DES-A §13.2 增补该封装或另给 `verifyReceipt` 明确的 `memberId/acceptedAt` 输入。未改变 G-004/D-022 语义，但属于对“回执文本形态”的边界扩展。
2. **退避错误码**：连续失败 5 次后使用本机内存 30s 拒绝窗口，返回 `AUTH_PASSWORD_INVALID`；未发 `AUTH_LOCKED_OUT`（DES-A 标为预留，错误目录/ i18n 键尚未登记）。这是有意的错误空间控制；若上游要求 `AUTH_LOCKED_OUT`，需先登记 code/i18n。
3. **账本介质**：使用 Asset Store 别名而非 RDB v5。原因：C-13 冻结构造器无 `RdbStore`；§23.6 允许 T-13 选择介质。若后续要求 SQL 可查询审计，需 Change Impact 增加 `RdbStore` 注入与 v5 迁移。
4. **C-13 写成员前置条件**：`acceptInvitation` 需要本地已有 `family` 行（`FamilyRepository` 没有由 C-13 调用的“仅建家庭行”API）。Host 集成在共享 harness 中验证；新成员设备的 family 元数据同步/建行仍属 C-08/C-22 组合根职责。
5. **seed 补偿**：`createInvitation` 在返回前写 seed 别名；若 C-08 `putInvitation` 随后失败，别名可能残留。现有 `InviteServicePort` 无 `discardInvitation` 回滚入口，登记为残余风险（`T09-RV-03` 的 C-13 侧未完全闭合）。
6. **密码最短长度 8**：沿用既有 App 约定；DES-A 只要求“非空/长度合法”。无最大长度限制（移除任意上限）。
7. **GUEST `canExecuteScene` 拒绝**：场景可跨房间且接口无场景上下文；与 `FamilyCapabilities.canControlAll=ADMIN/MEMBER` 一致。若产品要求 GUEST 场景，需 C-08/C-22 提供房间级预检。
8. **CODE_KEK 显示名**：无 YCR1 时成员 `displayName` 回退为随机 `memberId`；DES-A 未在 YCI1 头中携带显示名。

---

## 6. 残余风险 / 后续

| ID | 风险 | 级别 | 处理 |
|---|---|---|---|
| T13-R-01 | 回执封装需上游确认与跨版本互操作 | Medium | 评审 CQG-T13；建议 DES-A §13.2 补文 |
| T13-R-02 | 账本跨进程并发无 CAS（单设备常规路径单实例） | Low/Medium | 已用静态门串行化；如需多进程需 RDB 唯一约束 |
| T13-R-03 | C-08 `putInvitation` 失败导致 seed 别名残留 | Low | 增加 `discardInvitation` 或 C-08 补偿事务（Change Impact） |
| T13-R-04 | 成员设备无 family 行时接受失败 | Medium | 组合根/加入同步设计确认 |
| T13-R-05 | 平台 PBKDF2/X25519/GCM/Asset 未在真机验证 | High（证据） | `BLOCKED_ON_DEVICE_RUNNER`；设备套件已注册 |
| T13-R-06 | Asset hash 缺失被当作密码错误（防枚举） | Low | 设计选择；运维需区分存储告警 |
| T13-R-07 | 字符串密码/PBKDF2 输入无法原地擦除 | Low | 记录为 DES-A §26 残留；调用方及时清空输入 |
| T13-R-08 | 未接入组合根（C-28）注册 v3/构造服务 | Medium | T-17 组合根任务消费本报告 |
| T13-R-09 | 未实现真实 BLE 轮换/网关撤绑 | 范围外 | D-013 只要求引导；C-23 执行 |
| T13-R-10 | `InviteCodec` 进入 ohosTest 编译会触发 `common/utils/Base64Url.ets` 的既有 ArkTS 严格问题（`AppError` 类型引用/`throw` 限制） | Low（证据面） | 已从设备骨架移除该 import；主 HAP 编译与 host codec 测试通过；需 C-01 维护者在后续任务修复 Base64Url 后恢复设备 codec 用例 |

---

## 7. 追踪

| 需求/约束 | 证据 |
|---|---|
| FR-FAM-002/003/004 | C-12 profile/RBAC/session；C-13 YCR1/YCI1、回执、撤销引导 |
| FR-SET-001（成员管理） | `AuthService.canInvite/canManageFamily`；C-13 `InvitationRecord` |
| NFR-4.2 / DP-04 | PBKDF2 120k + Asset-only hash；host 参数断言 |
| ADR-003 §3–§6 | 容器、双路径、离线校验、撤销/轮换边界 |
| D-009 / D-010 / D-013 | KEY_WRAP 主路径；无在线状态；到期只提示轮换 |
| D-022 | `maxUses`/`ACCEPTED` 非终态/过期回执；`C13_expireInvitations_*` |
| §23.6 / R3-01 | 持久 `(inviteId, receiptHash)` 账本；跨重启重放测试 |
| SC-01..SC-08 / SC-16 | 秘密不落明文、不日志、无 oracle；弱模式 CODE_KEK 不默认 |
| SEC-N22 / SEC-N23 | AAD 篡改/过期/重放；GUEST 房间 RBAC 用例 |
| D-019 host layer | 469 host tests PASS；device 证据 BLOCKED |

---

## 8. 变更文件

```text
entry/src/main/ets/service/auth/AuthModels.ets              (new)
entry/src/main/ets/service/auth/AuthService.ets             (new)
entry/src/main/ets/service/invite/InviteModels.ets          (new)
entry/src/main/ets/service/invite/InviteCodec.ets           (new)
entry/src/main/ets/service/invite/InviteService.ets         (new)
entry/src/main/ets/service/invite/InviteServiceAdapter.ets  (new)
entry/src/test/host/AuthService.test.mjs                    (new)
entry/src/test/host/InviteService.test.mjs                  (new)
entry/src/test/host/family-host-helpers.mjs                 (new)
entry/src/test/host/host-crypto.mjs                         (new)
entry/src/test/domain/DomainHarness.ets                     (modified: v3 via AuthService; secrets/random seams)
entry/src/ohosTest/ets/test/family/AuthInviteDevice.test.ets (new, COMPILED_ONLY)
entry/src/ohosTest/ets/test/List.test.ets                   (modified: register device skeleton)
artifacts/50-implementation/evidence/t13-family/*.log       (new evidence; includes ohosTest compile)
```

**未改动**：`entry/src/main/ets/repository/**`、`model/**`、`contracts/**`、组合根、i18n 资源、DES/ADR 文档。
