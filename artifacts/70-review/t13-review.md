# T-13 独立评审报告（C-12 AuthService + C-13 InviteService + R3-01 回执账本）

- **Artifact ID**: REVIEW-T13
- **Producer**: agent:quality-reviewer
- **Type**: Independent Code Review / Security Review
- **Status**: **CHANGES_REQUIRED（代码级；不是 PASS）**
- **Date**: 2026-10-17
- **Task**: `wp-050-review-t13`（task 分支 `task/wp-049-family`，父分支 `feat/yaocore-app`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`（CQG-T13 / SEC 前）
- **Reviewed revision**: `1c832e55b20cc3ea4fa8057987f1856a61570570`（实现 `1e17142`，纠偏 `0a5168c`/`520bfb3`/`1c832e5`；评审以最终 HEAD 为准）
- **Review snapshot**: `refs/swe/snapshots/20261017T140722Z-wp-050-review-t13-30d7a2db`（commit `e5ddbe9`）
- **Implementation diff**: `79ef41b..1c832e5`，19 个路径
- **Independence**: 本评审由未参与 T-13 实现、纠偏提交或实现报告编写的 `quality-reviewer` 执行；未修改被审产品代码、测试、证据或实现报告。唯一仓库写入为本报告；只读探针通过 stdin 执行，未落盘。

> 结论先行：**C-12 AuthService 与 C-13 InviteService 的主体实现质量较好**，构建、lint、host 469/469、契约 AAD/版本/过期/篡改主路径均通过；设备证据如实 `BLOCKED`。但 **R3-01 回执账本存在可复现的“同一回执不同文本编码”重放绕过**，新成员设备的家庭行前置条件也未闭合，另有 CODE_KEK 本地单次语义、账本跨进程声明、写入时序和回执篡改测试缺口。因此本轮不能给出 PASS；**CQG-T13 需记为 CHANGES_REQUIRED**，修复并复审后再评估 STABLE/Gate。

---

## 1. 范围、revision 与输入完整性

### 1.1 范围

```text
entry/src/main/ets/service/          # 重点 service/auth/、service/invite/，以及被调用的 storage/repository 边界
entry/src/test/                      # host 测试、DomainHarness、证据日志
entry/src/ohosTest/ets/test/         # 设备骨架与注册
artifacts/50-implementation/t13-family-auth.md
```

- 实际被审变更为 `79ef41b..1c832e5` 的 **19 个路径**：C-12/C-13 产品代码 6 个、host 测试/harness 6 个、ohosTest 2 个、实现报告 1 个、证据日志 4 个。
- 复审同时读取了 C-08 调用面（`FamilyService`、`FamilyJoinSession`、`FamilyRepository`）、存储端口（`SecretStore`/`AssetStoreSecretStore`）、C-04 加密端口（`CryptoService`/`CryptoPort`）与 `StorageConstants`，用于核对契约边界；这些文件不在 T-13 写范围内，未修改。
- 明确排除：真实设备/模拟器、真实平台 Asset/RDB/`cryptoFramework`、真实 BLE 轮换、C-08/C-22/C-28 组合根与 UI、用户验收、T-19 全量测试报告。上述内容保持 `BLOCKED`/`NOT_RUN`，本报告不将其写成 PASS。

### 1.2 输入 pin

handoff 的 7 个 `inputs` SHA-256 **7/7 一致**；`config/git-policy.json` 的 SHA-256（`3b8ddffd...`）与 handoff 一致；复验前后 `git status` clean，HEAD = `1c832e5`，快照 ref 存在。

| 输入 | SHA-256 前 12 位 | 结果 |
|---|---|---|
| `artifacts/50-implementation/t13-family-auth.md` | `33290cc1b670` | 一致 |
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | `46e15e371840` | 一致 |
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `3932dac62252` | 一致 |
| `artifacts/20-architecture/adr-003-family-credential-distribution.md` | `14b52fe6cd1b` | 一致 |
| `artifacts/20-architecture/contract-baseline.md` | `883e09bb34ea` | 一致 |
| `artifacts/20-architecture/project-constraints.md` | `283046210e68` | 一致 |
| `artifacts/60-testing/test-plan.md` | `33485cc39abd` | 一致 |

### 1.3 本评审实际复验（cwd = 仓库根）

| 命令 | 结果 | 说明 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS：469 tests / 469 pass / 0 fail / 0 skipped / 0 todo，exit 0** | 与 `artifacts/50-implementation/evidence/t13-family/host-tests.log` 的 469/469 一致；新增 18 条（C-12 7 + C-13 11），基线 451 条无删除 |
| `codelinter -c code-linter.json5 -p default .` | **PASS：No defects found in your code，exit 0** | 与 `.../codelinter.log` 一致 |
| `hvigorw clean assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0**（35 tasks；34 executed / 1 up-to-date） | 与 `.../hvigor-assemble-hap.log` 一致；未配置签名 WARN，预期 |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0**（35 tasks） | 与 `.../ohostest-compile.log` 一致；**仅编译，不是设备执行** |
| `git diff --check` / `git status --short` | **PASS：exit 0 / clean** | 无空白错误、无未声明仓库改动 |
| 设备执行 | **BLOCKED（未写成 PASS）** | 无设备/模拟器/签名配置；`AuthInviteDevice.test.ets` 仅编译 |

测试证据核对：`host-tests.log` 为 469 条 `ok`；本次独立复跑的 469 个用例名与证据一致。实现报告 §3.2 的命令、计数与证据文件相符；`1c832e5` 仅同步了时间戳表述，未改写结果。

### 1.4 独立只读探针（不修改仓库）

除现有测试外，本评审用 stdin 直接调用真实 `InviteService`/`FamilyService` 与共享 harness，得到三项关键结果：

1. **同一回执的文本重编码可绕过精确文本账本**（详见 F-01）：
   - `maxUses=4`，导入 member-a（`usedCount=1`）、member-b（`usedCount=2`）；
   - 将 member-a 的 `YCP1` 载荷按不同 JSON 键序重新编码（`v/memberId/mac/inviteId/acceptedAt`），字段与 MAC 完全不变；
   - 再次导入该变体：**被接受，`usedCount=3`**；随后重放 member-a 的原始文本：`INVITE_RECEIPT_INVALID`，`usedCount` 保持 3。
2. **全新成员设备无法完成接受**（详见 F-02）：
   - 管理端 harness 已建家庭并生成 YCI1；成员端为只有迁移、没有 `family` 行的独立 harness；
   - `acceptInvitation` 在解封后调用 `families.getFamily(header.familyId)`，返回 **`CONFIGURATION_ERROR`（`field=familyId`）**。
3. **CODE_KEK 同一设备可重复接受同一容器**（详见 F-03）：
   - 同一 `InviteService` 对同一 CODE_KEK 容器连续接受两次，均成功，生成两个不同 `memberId`（`4344...5152` 与 `5354...6162`）；服务内没有持久化“已接受 inviteId”标记。

探针仅使用内存 fake 与 Node host oracle，不构成设备证据。

---

## 2. Findings

严重度定义：**High** = 可绕过 R3-01 安全语义或阻断主要端到端流程；**Medium** = 契约/测试/一致性缺口，需修复或书面裁定；**Low/Info** = 卫生、过程或已登记的残余。低级别项不单独阻断，但应进入 CQG 记录。

| ID | 严重度 | 位置 | 契约/依据 | 问题/影响 | 建议 |
|---|---|---|---|---|---|
| F-01 | **High（安全）** | `InviteService.ets:374-380`（账本 hash 用原始 `receiptText`）；`InviteCodec.ets:369-392`（接受非规范化 JSON）；`InviteService.test.mjs:198-248`（只测精确文本） | DES-B §23.6 项 1/2；DES-A §13.2/§13.5；R3-01 | 同一 HMAC 回执可用不同 JSON 键序/空白重新编码；`receiptHash` 随之不同，账本视为新回执；在另一成员接受后，C-08 的“最后回执”防御也不再命中，`usedCount` 被额外消耗。历史回执重放未真正闭合 | 对解析后的回执字段做**规范化 hash**（或强制 `encodeReceipt(payload)` 与原文一致），拒绝非规范 `YCP1`；补变体重放、错误 MAC、错误 inviteId、畸形信封测试 |
| F-02 | **High（集成）** | `InviteService.ets:285-287`；`FamilyRepository.createFamily:209-231`；`InviteService.test.mjs:174-188`（先 seed 家庭） | DES-B §3.3.4；FR-FAM-002；DES-A §13.1 | 全新成员设备没有本地 `family` 行时，`acceptInvitation` 必失败（`CONFIGURATION_ERROR`）；C-08 没有“按给定 familyId 导入家庭行”的 API（`createFamily` 只会生成新 UUID 并建 ADMIN）。主 KEY_WRAP 加入流程无法端到端完成；host 测试因预置家庭而掩盖 | 增加 C-08/C-22 的“导入已加入家庭”路径（固定 familyId + 成员 upsert），或由上游明确 C-13 允许创建家庭行；用两个 harness（管理端/成员端）验证无预置家庭路径。T13-R-04 应从 Medium 提升为阻断性集成项 |
| F-03 | **Medium（契约/安全）** | `InviteService.ets:261-273`（CODE_KEK 每次随机 memberId，无接受标记）；`FamilyJoinSession.ets:30-33,91`（仅内存 set）；`InviteService.test.mjs:208-213`（同一 service 连续接受三次） | DES-A §13.4.7（同一成员设备对同一 inviteId 只接受一次）；D-022 | CODE_KEK 同一设备可重复接受同一容器，生成多个不同 memberId/回执；重启或新 session 后 C-08 内存 set 也丢失。会在成员端产生重复成员行，并可被 Admin 作为多条回执消耗 `maxUses` | 在 Asset Store 持久化“已接受 inviteId”标记（或由 C-08 持久化），成功后拒绝再次接受；补跨重启测试。若上游认为弱模式不要求设备级去重，必须书面裁定并修订报告措辞 |
| F-04 | **Medium（安全声明/并发）** | `t13-family-auth.md:63` 与 `:159`（T13-R-02）；`AssetStoreSecretStore.ets:65-101`（update-or-add）；`FakeStores.ets:668-680`；`InviteService.ets:688-720` | DES-B §23.6；R3-01；报告 §2.1 | 报告 §2.1 声称“跨进程单设备由 Asset Store 别名唯一性约束”，但 `put` 是 upsert：两个进程可同时判定不存在、同时写入并都返回成功；别名唯一只保证最终一行，不保证“只有一个接受者”。同文件 T13-R-02 又承认“不声称多进程 CAS”，两处矛盾 | 删除“别名唯一性保证”措辞，明确**仅支持单进程**；若多进程可达，改用 RDB 唯一约束/条件 add 或进程互斥；补说明与测试。T13-R-02 的风险描述应作为唯一口径 |
| F-05 | **Medium（一致性/可用性）** | `InviteService.ets:378-383`（验签后先写账本）；`FamilyService.ets:399-416`（随后单独事务导入） | DES-B §23.6 项 1/2；ADR-003 §5.4 | 账本是“先写后用”：C-13 写入成功但 C-08 事务失败（RDB 错误、撤销/过期的并发窗口）时，回执已被记入账本，重试返回 `INVITE_RECEIPT_INVALID`，`usedCount` 不增；成员端可能已生效。合法接受无法补记，需换邀请 | 明确这是 write-ahead reservation 并登记残余；或提供 reserve/commit/rollback 语义（受冻结签名限制时至少由 C-08 补偿）；补失败注入测试 |
| F-06 | **Medium（测试）** | `entry/src/test/host/InviteService.test.mjs`（无回执篡改/错误 inviteId/畸形 `YCP1` 用例） | DES-A §13.5（回执 HMAC 正确/篡改）；SEC-N22；§23.6 | 现有测试只覆盖精确重放与有效回执；错误 MAC、错误 inviteId、回执版本、非规范编码均未覆盖。F-01 因此未被发现 | 增加回执负例矩阵；与 F-01 的规范化修复一起提交 |
| F-07 | **Medium（契约）** | `InviteCodec.ets:346-392`；报告 §5.1；DES-A §13.2 的 `receipt = hex_lower(...)` | DES-A §13.1/§13.2/§13.5；DES-B §23.6；T13-R-01 | 实现把回执扩展为 `YCP1.<b64url(JSON)>`，而 DES-A/ADR 仍定义为裸 hex。HMAC 公式未变，但“回执文本形态”已被扩展；与裸 hex 消费方不兼容，且 `InviteServicePort` 未记录该信封 | 由 architect 走 Change Impact 修订 DES-A §13.2/§13.5 与端口注释，明确 canonical envelope、版本与兼容边界；不得声称与裸 hex 完全兼容。该修订与 F-01 的 canonical 化一并做 |
| F-08 | **Low（契约/功能）** | `AuthService.ets:466-478`；`AuthService.test.mjs:180` | DES-A §12.1 RBAC 矩阵（GUEST 在授权房间内可执行场景）；D-013 | `canExecuteScene` 对所有 GUEST 返回 `RBAC_DENIED`；测试把该行为固化为期望。接口没有房间上下文，fail-closed 合理，但与矩阵“GUEST 仅 allowedRoomIds 内”不一致，且未完成上游裁定 | 由 architect/产品裁定：要么扩展场景上下文并实现房间级判断，要么修订 DES-A 矩阵并记录“GUEST 场景在 C-22 预检”。在裁定前保留 fail-closed，但不要声称矩阵已完整实现 |
| F-09 | **Low（秘密卫生）** | `InviteService.ets:498-524`（bundle JSON、`seedHex`/`commandSecretHex` 字符串）；`InviteModels.ets:122-146`；`CryptoPort.ets:15-32/68-88`（无 handle destroy） | DES-A §13.4.9；§26；SC-06；报告 §4 | `Uint8Array`/`SecureBytes` 已清零，但 bundle JSON、seed/commandSecret 的十六进制字符串是 ArkTS 不可变字符串，无法原地擦除；Admin 临时 X25519 私钥 handle 也没有显式销毁入口。内存驻留时间取决于 GC | 在报告 §4/T13-R-07 中把字符串与 key handle 一并列为残余；后续可考虑字节化 bundle 编码或 C-04 增加 key handle 销毁；不得声称“全部秘密均已清零” |
| F-10 | **Low（安全卫生）** | `InviteService.ets:303-308,819-826` | DES-A §13.4.2/§13.4.9；ADR-003 §5.3 步骤 6 | 接受成功后 `removeQuietly` 吞掉所有删除 join 私钥的失败；KEY_WRAP 一次性语义依赖该删除。删除失败时私钥长期留在 Asset Store，同一容器可再次接受（Admin 端 maxUses=1 可挡，但成员端会重复写） | 记录/重试删除失败，或至少在报告中明确“best-effort”；补删除失败路径测试 |
| F-11 | **Low（可靠性）** | `AuthService.ets:229-268` | DES-A §12.3 不变式 8；NFR-4.2 | changePassword 先写新 hash 到 Asset，再更新 RDB salt；异常路径有恢复，但进程崩溃窗口会让“新 hash + 旧 salt”不匹配，用户被锁在档案外。恢复逻辑本身也依赖旧密码字符串与 old salt 可重算 | 登记为双存储非原子更新的残余；考虑版本化 hash 别名/恢复标记；补进程中断模型说明与测试（至少异常注入） |
| F-12 | **Low（并发）** | `AuthService.ets:145-192` | DES-A §12.3；报告 §1.1“重复档案” | 并发 `createProfile` 同一 profileId：两者都通过前置检查并使用同一 hash alias；后者事务失败后会 `removeSecretQuietly(hashAlias)`，可能删掉成功者的 hash。同成员重复档案也只靠前置查询，无 DB 唯一约束 | 在事务内先检查/占用后再写 Asset（或使用唯一索引 `(family_id, member_id)`）；补并发/失败注入测试 |
| F-13 | **Low/Medium（生命周期）** | `InviteService.revokeInvitation:389-406`（不删 seed）；`FamilyRepository.removeFamilyLocal:652-666`（只删 invitation 行）；`InviteService.ets:688-720`（账本无清理）；`t13-family-auth.md:158-167` | ADR-003 §5/§6；SC-06；DES-A §13.4.9 | 撤销/过期/解散后 seed 别名保留；账本条目随每次接受永久增长且无保留策略；Asset Store 可能长期累积敏感 seed 与审计资产。报告只提到 C-08 put 失败残留（T13-R-03） | 由 C-08/C-13 增加撤销/解散清理与账本保留策略（或明确永不清理并说明容量边界）；补生命周期测试 |
| F-14 | **Low（测试）** | `entry/src/ohosTest/ets/test/family/AuthInviteDevice.test.ets:30-36` | DES-A §12.5；D-019 设备层 | `C12_AuthService_registersV3Migration` 只断言 `registry !== undefined`，即使 `registerMigrations` 什么都不做也会通过；报告“设备骨架覆盖 AuthService.registerMigrations”略高于实际 | 用可观测的迁移注册断言替换（或在 fake RDB 上实际 migrate 后查询 `auth_profile`）；保持设备 `COMPILED_ONLY` 诚实标签 |
| F-15 | **Low（过程）** | `artifacts/60-testing/test-plan.md:334-335`；`:561/:569` | TEST-001；D-019；CQG-T13 | SEC-N22/N23 仍为 `NOT_RUN`，D-019 的证据表也未随 T-13 更新；实现报告 §7 直接引用 Host 证据。CQG 记录不应把 test-plan 状态与报告证据混同 | 由 test-engineer/Orchestrator 更新 SEC-N22/N23 的 Host 证据与状态；设备项仍 `BLOCKED`；不要把 test-plan 自动改成 PASS |
| F-16 | **Info（过程）** | handoff `base_commit=1c832e5`；实现 `finish` 记录覆盖至 `1e17142` | operational-guards；branch-per-task | 3 个纠偏提交 `0a5168c`/`520bfb3`/`1c832e5` 均在声明范围内，但实现任务的 finish 证据未覆盖它们；本评审以最终 HEAD 为准。流程上应由 Orchestrator 补记或重跑 finish/新 handoff | 在 CQG/Checkpoint 记录“实现 finish 覆盖 1e17142，纠偏 3 提交经本评审确认”；不要把它当作已覆盖的 finish |
| F-17 | **Low（O-1/分层）** | `AuthService.ets:174-186`（直接 `storage.rdb.transaction`，未注入共享 `DomainOperationGate`） | DES-B §2.8 O-1；DomainOperationGate 文档 | C-12 的唯一事务没有使用 C-08..C-11 共享 gate；`RdbTransactionRunner` 串行化事务，但普通仓储 query 仍可能与该事务交错。注释把 O-1 窄化为“无嵌套事务”，未覆盖 single-flight | 在组合根/文档中说明 `auth_profile` 事务隔离边界，或让 C-12 通过可注入的 gate/事务端口执行；至少登记契约限制。属于 Low 观察，不单独阻断 |
| F-18 | **Low（UX/数据）** | `FamilyService.importReceipt:407-410`（displayName=memberId）；`InviteService.acceptInvitation:259-260`（显示名仅内存 map）；报告 §5.8 只提 CODE_KEK | DES-A §13.1 `JoinRequest.displayName`；DES-B 成员展示 | KEY_WRAP 的显示名未随回执/邀请记录传到 Admin；Admin 导入后成员显示为 memberId，且 C-13 的 `joinDisplayNames` 不持久化。不是安全问题，但影响成员列表可读性 | 在回执信封或 C-08 邀请记录中携带/保存 displayName，或明确由后续接触同步；报告 §5.8 同步说明 KEY_WRAP Admin 侧 |

### 2.1 关键阻断项展开

#### F-01 — 回执“同一语义、不同文本”重放（High）

```text
导入 a: usedCount 1
导入 b: usedCount 2
a 的 YCP1 JSON 键序改为 v,memberId,mac,inviteId,acceptedAt 后重编码: 接受, usedCount 3
再导入 a 原文: INVITE_RECEIPT_INVALID, usedCount 仍 3
```

- `decodeReceipt` 只校验字段集合/类型，不校验 JSON 键序或空白；`Base64Url.decode` 本身是 canonical 的，因此变体完全来自 JSON 文本。
- `verifyReceipt` 的 HMAC 只覆盖 `inviteId/memberId/acceptedAt`，变体 MAC 仍然有效；账本 hash 覆盖 `receiptText` 原文，于是变体得到新的 `receiptHash`。
- C-08 `isDuplicateReceipt` 比较“最后一条 receipt 文本”和 `acceptedByMemberId`；当中间有另一个成员接受后，两项都不等于 a，变体通过 C-08 检查。
- 影响与 `RISK-INVITE-RECEIPT-REPLAY` 一致：陈旧/被截获回执可消耗 use，最终把 `maxUses` 耗尽，后续合法成员被 `INVITE_MAX_USES` 拒绝。这不是“成员自己伪造新 acceptedAt”的已知残余，而是**外部截获者可利用的等价回执重放**。
- 修复方向：账本 hash 使用解析后的 canonical receipt（例如 `v|inviteId|memberId|acceptedAt|mac` 或 `encodeReceipt(payload)` 的规范字节）；`decodeReceipt` 拒绝 `encodeReceipt(payload) !== text` 的非规范信封。若上游把“回执文本”本身定义为身份，则必须把该语义写入 §23.6 并撤销“历史回执重放已拒绝”的表述；当前实现不应默认通过。

#### F-02 — 全新成员设备的家庭行（High 集成）

- `acceptInvitation` 只接受“本地已存在 `family` 行”的容器；这是 `T13-R-04` 的实现事实，但报告把它描述为 C-08/C-22 组合根职责。
- 现存 `FamilyRepository.createFamily(name, ownerMemberId, ...)` 会生成新的 UUID 和 ADMIN 成员，不能用于“按邀请中的 familyId 导入家庭”；`FamilyService` 也没有导入方法。`FamilyJoinSession` 先调 C-13，故没有补救路径。
- 因此主 KEY_WRAP 流程（新设备扫码/粘贴 YCR1 → Admin 发 YCI1 → 新设备接受）在真实新装设备上不能完成；现有 `C13_familyJoinSession_...` 测试在 `inviteSetup` 中预置家庭，无法发现。
- 这不是单纯的产品 UX；它使 FR-FAM-002 的 C-13 消费链在组合根缺失时不可用。CQG-T13 必须把它登记为**阻断性集成项**，由 C-08/C-22 Change Impact 或 C-13 契约修正解决。

#### F-03 — CODE_KEK 本地单次语义（Medium）

- `acceptInvitation` 的 CODE_KEK 分支每次生成新的随机 `memberId`（`:271`），且没有任何“已接受 inviteId”持久标记；`FamilyJoinSession.acceptedContainers` 只在单次 session 内存中。
- 探针显示同一服务连续接受同一容器两次均成功；重启/新 session 后同样可重复。成员端会创建多个成员行，Admin 端若 `maxUses>1` 可接受多张回执。
- DES-A §13.4.7 明确“同一成员设备对同一 inviteId 只接受一次”。KEY_WRAP 通过删除 join 私钥实现；CODE_KEK 没有等价机制。需要持久化 marker 或上游书面裁定。

#### F-04 — 账本跨进程声明与实现不符（Medium）

- `AssetStoreSecretStore.put` 的顺序是 `update` → 不存在则 `add` → `ALREADY_EXISTS` 再 `update`，本质是 upsert；它不会把“已存在”暴露给调用者。
- `recordLedger` 的 `withSecret` 存在性检查与 `put` 是两次独立操作；静态 `LEDGER_GATE` 只约束同一 JS 进程。两个进程/两个 VM 可以同时检查为不存在并都写入，两个调用都返回 `true`。
- 报告 §2.1 的“别名唯一性约束”只保证最终只有一行，不保证只有一个接受者；T13-R-02 的“无多进程 CAS”才是准确描述。二者必须统一。若 HarmonyOS 进程模型保证单进程，应在报告中写明这一前提，而不是用别名唯一性作为安全论证。

#### F-05 — 账本 write-ahead 与 C-08 事务失败（Medium）

- `verifyReceipt` 在返回前写账本；`FamilyService.importReceipt` 随后才执行 `applyReceiptAndEnsureMember`。
- 如果 C-08 事务因 RDB 错误、撤销/过期竞态或任意异常失败，账本已经占用了该 `(inviteId, receiptHash)`；重试只能得到 `INVITE_RECEIPT_INVALID`，`usedCount` 不增。成员设备上可能已经 ACTIVE 并持有网关凭据（检测控制，不是阻止控制；ADR-003 §5.4）。
- 这是跨存储（Asset ledger + RDB）无法原子提交的固有限制；当前报告未登记。至少应写入残余风险并考虑补偿/两阶段设计。

---

## 3. T13-R-01..05 评估

| 风险 | 本评审评估 | 依据/理由 | 结论 |
|---|---|---|---|
| **T13-R-01** 回执封装需上游确认与跨版本互操作 | **合理但有条件**。`verifyReceipt(receiptText, inviteId)` 冻结签名确实无法从裸 HMAC 恢复 `memberId/acceptedAt`，`YCP1` 自描述信封是低侵入扩展；HMAC 公式未变，账本仍只存 hash。 | DES-A §13.2 明确写裸 hex；实现返回 `YCP1`；报告 §5.1 已披露“边界扩展”，但 DES-A/端口未修订；F-01 的规范化也属于信封定义的一部分。 | **ACCEPTED_WITH_CONDITION**：必须修订 DES-A §13.2/§13.5 与 `InviteServicePort` 注释、定义 canonical envelope、补互操作说明；不得声称与裸 hex 完全兼容。 |
| **T13-R-02** 账本跨进程并发无 CAS | **部分如实，部分夸大**。T13-R-02 的“无多进程 CAS”准确；报告 §2.1 的“Asset Store 别名唯一性约束”不准确（put 为 upsert），静态 gate 只覆盖单进程。 | `AssetStoreSecretStore.ets:65-101`；`InviteService.ets:688-720`；报告 §2.1 与 §6 自相矛盾。 | **PARTIALLY_ACCURATE / OPEN**：修正报告措辞，明确单进程边界；若多进程可达，改用 RDB 唯一约束/条件 add。 |
| **T13-R-03** C-08 `putInvitation` 失败导致 seed 别名残留 | **成立且未闭合**。C-08 在 C-13 成功后才 `putInvitation`；失败时 seed 已写入，且 `InviteServicePort` 没有 `discardInvitation` 回滚入口。撤销/过期/解散也没有 seed 清理，生命周期问题比报告描述更大。 | `FamilyService.ets:321-356`；`InviteService.ets:205-224`；`FamilyRepository.removeFamilyLocal:652-666`；F-13。 | **OPEN / Medium**：C-08/C-13 Change Impact，增加回滚/清理或明确接受残留。 |
| **T13-R-04** 成员设备无 family 行时接受失败 | **确认并应升级**。不是仅“组合根职责”提醒：现有 C-08 没有按 familyId 导入家庭的 API，主加入流程在新设备上不可完成；host 测试预置家庭掩盖。 | 探针 F-02；`InviteService.ets:285-287`；`FamilyRepository.createFamily:209-231`；`InviteService.test.mjs:174-188`。 | **CONFIRMED / HIGH integration blocker**：C-08/C-22 增加导入路径或 C-13 契约修正；补全新设备测试。 |
| **T13-R-05** 平台 PBKDF2/X25519/GCM/Asset 未在真机验证 | **如实、正确地保持 BLOCKED**。设备骨架只编译；`AuthInviteDevice` 的 PBKDF2 向量正确（本评审用 Node/OpenSSL 独立核对），但没有设备运行证据。 | `AuthInviteDevice.test.ets`；报告 §3.2 明确“未执行”；无签名/设备。 | **HONEST_BLOCKED / High evidence risk**：保持 `BLOCKED`，不得写成设备 PASS；T-19 设备阶段消费。 |

补充：**T13-R-06..R-10** 总体仍成立；其中 R-10（`InviteCodec` 进入 ohosTest 触发 `Base64Url` 既有 ArkTS 问题）在纠偏 `0a5168c` 后已从设备骨架移除，主 HAP/ohosTest 编译通过，属于诚实证据面限制；R-08（未接组合根）与 F-02 相关联；R-09（BLE 轮换范围外）无异议。

---

## 4. CQG-T13 / SEC 意见

| 检查面 | 结论 | 证据/说明 |
|---|---|---|
| 构建 | **PASS** | `hvigorw clean assembleHap --no-daemon` exit 0，35 tasks，未签名 WARN；当前 revision 可构建 |
| 静态检查 | **PASS** | `codelinter` exit 0，No defects；测试源码按配置不检查 |
| Host 测试 | **PASS** | 469/469，0 fail/0 skip/0 todo；新增 18 条，基线 451 条保留；证据日志一致 |
| 契约符合 | **CHANGES_REQUIRED** | F-01（R3-01 重放语义）、F-07（YCP1 未入 DES）、F-08（GUEST 场景矩阵）未闭合 |
| 安全（SEC） | **CHANGES_REQUIRED** | F-01 语义重放、F-03 CODE_KEK 本地单次、F-04 跨进程声明、F-05 write-ahead；F-06 回执篡改测试缺口；F-09/F-10 秘密卫生 |
| 分层/依赖方向 | **PASS（附 F-17 观察）** | C-12/C-13 无平台 import；依赖方向为 service → repository/storage/model；GCM 仅用于邀请容器，无 LAN GCM；AuthService 的事务未使用共享 gate 属于 O-1 边界观察 |
| 独立评审 | **PASS** | 本报告由未参与实现/纠偏的 reviewer 出具；作者不能自批 |
| 设备/真实平台 | **BLOCKED** | 无设备/签名；ohosTest 仅编译；真实 PBKDF2/X25519/GCM/Asset Store/RDB 未执行；不得写成 PASS |
| **CQG-T13 总体** | **CHANGES_REQUIRED** | 构建/lint/host 通过；安全与契约阻断项仍需修复后再评审；`STABLE`、Integration/Stage Gate 与用户验收均未授予 |

**SEC 结论**：主密码学路径（KEY_WRAP/CODE_KEK、AAD、版本、AEAD fail-closed、常数时间回执比较、无日志、无 LAN GCM）未发现新的密码学原语缺陷；阻断点在**回执账本的语义重放/规范化**、**CODE_KEK 本地单次**与**账本并发/写入时序**，属于安全机制的正确性而非 CryptoPort 原语。

---

## 5. 残余风险与跟踪

| ID | 风险 | 级别 | 处理/owner |
|---|---|---|---|
| F-01 | 同一回执不同文本编码可消耗额外 use，R3-01 语义重放 | **High** | implementation-engineer 修复；quality-reviewer 复审；规范来源 DES-B §23.6/DES-A §13.2 |
| F-02 | 新成员设备无 family 行，主加入流程不可完成 | **High（集成）** | C-08/C-22 Change Impact；Orchestrator 决定是否阻断 T-13 CQG 的端到端声明 |
| F-03 | CODE_KEK 同一设备可重复接受，违反 §13.4.7 | **Medium** | implementation-engineer/C-08 持久去重；或 upstream ruling |
| F-04 | 账本跨进程无 CAS，报告 §2.1 声明不准确 | **Medium** | 修报告；多进程时改 RDB 唯一/条件 add |
| F-05 | 账本 write-ahead，C-08 失败烧毁回执 | **Medium** | 登记残余/两阶段/补偿；补失败注入测试 |
| F-06 | 回执篡改/错误 inviteId/畸形信封测试缺失 | **Medium** | test-engineer/implementation-engineer |
| F-07 | YCP1 未进入 DES-A/端口契约，裸 hex 不兼容 | **Medium** | solution-architect Change Impact |
| F-08 | GUEST `canExecuteScene` 与矩阵不一致 | **Low/Medium** | architect/产品裁定；当前 fail-closed |
| F-09 | seed/commandSecret 字符串与 X25519 handle 无法清零 | **Low** | 报告残余；C-04 key handle destroy 可选 |
| F-10 | join 私钥删除 best-effort | **Low** | 记录/重试；测试 |
| F-11 | changePassword 双存储崩溃窗口 | **Low** | 报告残余；版本化/恢复标记 |
| F-12 | createProfile 并发 alias 删除/重复成员 | **Low** | 事务内占用/唯一索引 |
| F-13 | seed/账本资产无生命周期清理 | **Low/Medium** | C-08/C-13 cleanup/retention |
| F-14 | 设备 skeleton 迁移断言空泛 | **Low** | 设备测试改进 |
| F-15 | test-plan SEC-N22/N23 未更新 | **Low（过程）** | test-engineer/Orchestrator |
| F-16 | 实现 finish 仅覆盖 1e17142，纠偏 3 提交未覆盖 | **Info（过程）** | CQG/Checkpoint 记录 |
| F-17 | C-12 事务未共享 DomainOperationGate | **Low** | 组合根/契约说明 |
| F-18 | KEY_WRAP Admin 侧 displayName 丢失 | **Low** | 后续同步/回执扩展 |
| T13-R-01..05 | 见 §3 | — | 分别有条件接受/部分/开放/高/诚实 BLOCKED |
| T13-R-06..10 | 见实现报告 | Low/Info | 保持跟踪；R-10 为 Base64Url 既有 ArkTS 问题 |

**不会在本报告中授予**：CQG-T13 PASS、C-12/C-13 `STABLE`、Integration Gate、Stage Gate、设备/真实平台 PASS、用户验收。设备项保持 `BLOCKED_ON_DEVICE_RUNNER`。

---

## 6. Verdict

**CHANGES_REQUIRED。**

判定理由：

1. **F-01** 是 R3-01 核心安全语义的可复现绕过；不是测试/文档瑕疵。必须在同一 revision 上修复并补规范化/篡改测试后重新评审。
2. **F-02** 使 FR-FAM-002 的主加入流程在全新成员设备上不可完成；至少必须由 C-08/C-22 提供导入家庭行路径并纳入本轮变更/证据，或由上游明确 C-13 契约负责创建。
3. **F-03/F-04/F-05/F-06/F-07** 涉及 CODE_KEK 单次语义、账本跨进程声明、write-ahead 一致性、回执篡改测试与回执信封契约；属于 CQG 安全/契约证据的一部分。
4. 构建、lint、host 469/469、AAD/版本/过期/篡改主路径、秘密不落明文、无日志、无 LAN GCM 等已通过；修复后应重新执行同一组复验（host、codelinter、assembleHap、ohosTest 编译）并由独立 reviewer 复审。

修复前的 `CHANGES_REQUIRED` 不改变本报告对已存在代码的正面结论：C-12/C-13 主实现可读、分层清晰、fail-closed 主路径正确；但当前证据不足以支持 PASS。

---

## 7. 独立声明与排除

- **独立性**：本评审由未参与 T-13 实现、`0a5168c`/`520bfb3`/`1c832e5` 纠偏或实现报告编写的 `quality-reviewer` 执行；未修改 `entry/src/main/ets/service/**`、`entry/src/test/**`、`entry/src/ohosTest/ets/test/**`、证据日志或 `t13-family-auth.md`。唯一仓库写入为 `artifacts/70-review/t13-review.md`。
- **只读探针**：F-01/F-02/F-03 的复现通过 stdin 执行，未在仓库落盘；使用内存 fake 与 Node host oracle，不构成设备证据。
- **范围排除**：真实设备/模拟器、真实平台 PBKDF2/X25519/AES-GCM/Asset Store/RDB、真实 BLE 轮换、C-08/C-22/C-28 组合根与 UI、用户验收、T-19 全量测试报告；上述均为 `BLOCKED`/`UNAVAILABLE`/`NOT_RUN`，不是 PASS。
- **证据时效**：本报告只对 `1c832e5` 的代码、测试与证据负责；实现报告引用的 `1e17142` finish 记录不覆盖后续 3 个纠偏提交，本评审已独立复验最终 HEAD。
