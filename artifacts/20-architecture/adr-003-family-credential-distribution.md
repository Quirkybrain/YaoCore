# ADR-003 — 家庭凭据的离线加密分发（D-008 形式化）

- **Artifact ID**: ADR-003
- **Producer**: agent:solution-architect
- **Type**: Architecture Decision Record
- **Status**: Proposed（待 G-004 门禁批准）
- **Date**: 2026-10-17
- **Task**: `wp-004-contracts`（task 分支 `task/wp-004-contracts`，父分支 `feat/yaocore-app`，base commit `54c1d786`）
- **Workflow**: STANDARD / GATED_AUTO
- **Upstream 证据**: D-008 用户决策（`state/project-state.md` L58）；`WP3` §4.2（C-020 / G-D8-1..6）；ADR-002（局域网安全通道与密钥模型）；26 项冻结输入
- **Downstream 消费者**: `contract-baseline.md`（§9 范围声明）、DES-001（wp-006：Family 模块详细设计）、DATA-001 修订提案、实现任务（Family/Security/存储）、TEST-001（离线凭据测试夹具）
- **Traceability**: C-011 / C-020 / G-D8-1..6、C-009、C-017、FR-FAM-001/002/003/004、FR-SET-001/002、NFR-4.2

> **方向已决（不得重开）**：D-008 = 家庭成员邀请的家庭控制密钥交付采用**离线加密凭据**（邀请码/二维码携带加密密钥材料，无服务器依赖）。本 ADR 形式化机制、格式、校验主体、撤销轮换与威胁模型；不重新评估方向，不引入服务器。

---

## 1. Context

### 1.1 可依据的既有条款

| # | 内容 | 证据 |
|---|---|---|
| 1 | 邀请凭据要素：邀请码（6~8 位字母数字）、生效时限（默认 24h）、目标角色（`MEMBER`/`GUEST`）、可选授权房间、`maxUses`/`usedCount` | 需求 L66-69；数据模型 L46-56 |
| 2 | 加密 Token 方向：本地生成含 `familyId/role/expireAt/encryptedKey`；"向 Admin 设备或安全服务交换凭据"；成员**无需**再走 BLE 配网 | 架构 L111-113；需求 L69 |
| 3 | 界面流程：角色选择→6 位码/二维码→24h 倒计时→输入邀请码→"请求安全信道"→凭据交换→加入成功 | UIUX L89-102/L106 |
| 4 | 本地安全基础（可复用）：PBKDF2\|SHA256 120,000 加盐；Asset Store 密钥存储；幂等/单次语义参考 | 需求 L152；归档 `AuthService.ets` L31/L91-171/L194-202；`SecureStorageService.ets` L18-19/L35/L44 |
| 5 | 局域网信任材料形态：per-gateway `command_secret`（≥16B，每网关独立）+ TLS pin 集合 | ADR-002 §8；PRIV L37；`EXTERNAL_MODULE_PROTOCOL.md` L24 |

### 1.2 缺口（WP3 §4.2，本 ADR 逐项解决）

- **G-D8-1（阻塞，=C-020）** 凭据载荷格式未定义 → **§3**。
- **G-D8-2** 密钥封装方案未定义（接收方公钥？邀请码派生密钥？）→ **§4**。
- **G-D8-3** 校验主体与离线语义未定义（expireAt/maxUses/重放/时钟信任）→ **§5**。
- **G-D8-4** 撤销与轮换未定义（成员移除 → 网关密钥轮换的成本与边界）→ **§6**。
- **G-D8-5** 与 D-007 交叉：指纹随凭据分发 → **§7**。
- **G-D8-6** 威胁模型未产出 → **§8**。

### 1.3 关键约束（决定设计空间）

1. **无服务器**：验收时不存在任何在线协调点（云/后端/账号中心）。家庭网关虽在线，但其协议无家庭/成员端点（`discover-response.schema.json` L6-14 顶层封闭；`cloud-command.schema.json` 仅有设备命令），**v1 不把网关当成员协调点**（若将来需要，属固件协同扩展）。
2. **成员可能远程加入**：远程场景下可用信道只有"用户自选的人类信道"（聊天/语音/邮件），其机密性不可假设。
3. **协议无按用户/按设备鉴权**：局域网控制只有网关级 HMAC（ADR-002 §8.2），**无角色维度**——GUEST 的房间范围限制只能是 App 侧策略，不是密码学边界（§6.3，必须在 UI 与文档中如实声明）。
4. **一次性能力**：v1 密钥轮换只能经 BLE 就近（ADR-002 §8.4），因此"撤销"的密码学强度受该成本约束（§6）。

---

## 2. Decision 1：分发模型总览

**离线加密凭据 = 版本化容器 + 密钥封装 + 家庭秘密包（Family Secret Bundle）**。三种要素分离：

| 要素 | 作用 | 是否秘密 |
|---|---|---|
| **邀请头（Header）** | 版本、`inviteId`、`familyId/familyName`、角色、授权房间、`expireAt`、`maxUses`、封装参数 | 否（作为 AEAD 的 AAD 被认证） |
| **封装密钥（KEK）** | 解封家庭秘密包的对称密钥 | 由成员私钥或邀请码派生 |
| **家庭秘密包（Bundle）** | `command_secret`（逐网关）+ TLS pin（逐网关）+ `seed` + `keyId` | **是**（AEAD 密文，仅持有 KEK 者可解） |

**两条分发路径**（同一容器家族，`kdf.mode` 区分）：

| 路径 | 触发场景 | 密钥来源 | 安全边界 |
|---|---|---|---|
| **A. 密钥封装（KEY_WRAP，主路径/推荐）** | 成员设备可展示"加入请求"（现场扫码或远程粘贴文本） | 成员一次性 X25519 密钥对（接收方公钥已知，admin 侧临时密钥对做 ECDH） | **密文泄露不构成密钥泄露**（必须同时持有成员私钥）；邀请码仅作确认/管理句柄 |
| **B. 码派生密钥（CODE_KEK，次路径）** | 成员只能口头/短信传码，无法传"加入请求" | 6 位邀请码 + PBKDF2/HKDF | 密文泄露 + 码泄露即失守；30 bit 码空间依赖 KDF 拉伸与短有效期；**默认单次使用** |

两路径共用 §3 的容器、§5 的离线校验语义、§6 的撤销模型与 §8 的威胁模型；差异仅在于 KEK 的派生。

---

## 3. Decision 2：凭据载荷格式（版本化；G-D8-1）

### 3.1 容器编码

文本化、可扫可贴、版本前缀显式：

```text
YCI1.<b64url(header)>.<b64url(iv)>.<b64url(ciphertext||tag)>
```

- 前缀 `YCI1` = **Y**ao**C**ore **I**nvitation v1（版本硬编码在字符串首，旧解析器 fail-closed）；
- `header` = 紧凑 UTF-8 JSON（键序按字典序序列化，禁止空白），字段：

```json
{
  "v": 1,
  "inviteId": "<uuid>",
  "familyId": "<uuid>",
  "familyName": "<≤63>",
  "targetRole": "MEMBER|GUEST",
  "allowedRoomIds": ["<roomId>", "..."],
  "expireAt": "20261018T153000Z",
  "maxUses": 1,
  "kdf": {
    "mode": "KEY_WRAP|CODE_KEK",
    "alg": "X25519-HKDF-SHA256|PBKDF2-SHA256-120000+HKDF-SHA256",
    "adminEphemeralPub": "<b64url 32B，仅 KEY_WRAP>",
    "salt": "<b64url 16B，仅 CODE_KEK>",
    "iterations": 120000
  },
  "keyId": "app-key-v1"
}
```

- `ciphertext||tag` = **AES-256-GCM(KEK, iv=12B 随机, aad=header_bytes_exact)`**，明文 = §3.3 的 Bundle JSON；
- 邀请头**不加密**但被认证（AAD）；任何头字段改动都会导致解封失败——防止"改写角色/有效期"的篡改（角色提升、延长有效期均被密码学拒绝）。

### 3.2 加入请求（仅 KEY_WRAP）

```text
YCR1.<b64url(joinReq)>
joinReq = { "v":1, "memberId":"<16B 随机 hex 安装标识>",
            "pub":"<b64url 32B X25519 公钥>", "createdAt":"<UTC>", "displayName":"<可选昵称>" }
```

- 由成员设备生成；`pub` 对应私钥只存 Asset Store（`yaocore.invite.join.<inviteId>` 别名，接受后即销毁）；
- **一次性**：每个加入请求只接受一个邀请封装；请求未接受前可重复使用（重试友好），接受成功后设备删除私钥。

### 3.3 家庭秘密包（Bundle，AEAD 明文）

```json
{
  "v": 1,
  "familyId": "<uuid>",
  "issuedAt": "<UTC>",
  "keyId": "app-key-v1",
  "seed": "<32B 随机 hex>",
  "gateways": [
    {
      "gatewayId": "<id>",
      "name": "<可选>",
      "commandSecret": "<≥16B 小写 hex，建议 32B>",
      "tls": { "pins": ["<64 hex>"], "port": 9200 }
    }
  ]
}
```

- `seed`：用于**接受回执**（§5.4）与邀请审计的对称密钥；与 `commandSecret` 用途分离；
- `gateways[].tls` 仅当该网关已宣告 TLS（ADR-002 §3.2），否则省略；pin 一律 64 位小写 hex（ADR-002 §4）；
- **`commandSecret` 绝不落盘明文**（除 Asset Store 以外），不写日志、不进异常文本（ArkTS 规范 L62-64）。

### 3.4 版本化与扩展

- 容器版本在字符串前缀（`YCI1`）与头 `v` 双重声明；未知版本一律拒绝（fail-closed）；
- 向前扩展（如新增网关字段）通过头 `v` 递增 + 旧 App 拒绝策略管理；不引入隐式兼容。

---

## 4. Decision 3：密钥封装方案（分析、选择与理由；G-D8-2）

### 4.1 备选方案分析

| 方案 | 机密性来源 | 离线可行性 | 优点 | 缺点/风险 | 结论 |
|---|---|---|---|---|---|
| **S1 接收方一次性公钥（X25519 ECDH + HKDF + AES-GCM）** | 成员私钥 + Admin 临时私钥 | ✅（加入请求经扫码/文本传递） | 密文泄露不可破（无码空间上限）；自然支持远程（加入请求可粘贴）；一次性前向性（Admin 临时密钥） | 需要"成员先给出加入请求"一步；多一次交互 | **采纳为主路径（KEY_WRAP）** |
| **S2 邀请码派生 KEK（PBKDF2 120k + HKDF）** | 6 位码（30 bit 有效空间）的保密性 + KDF 拉伸 | ✅（零额外交互） | 符合 UX 既有"输入邀请码"形态；实现最简 | 码空间小；密文一旦泄露成为离线爆破目标；必须单次/短时 | **采纳为次路径（CODE_KEK）**，标注弱模式 |
| **S3 双方临时 ECDH（PAKE 风格，需两轮交互）** | 交互式 | ✅（可行性高） | 抗码泄露（PAKE 特性） | 协议复杂度高（需自研 PAKE 或引入库）；ArkTS 生态缺现成实现；超出 v1 工程预算 | 归档提案 `EXT-INVITE-PAKE-001`（未来） |
| **S4 明文秘密包 + 短码校验** | 无 | ✅ | 极简 | 直接违反 D-008"加密凭据" | **否决** |
| **S5 服务器托管（代管密钥）** | 服务器 | ❌ | 支持在线撤销/计数 | 直接违反 D-008 无服务器依赖 | **否决** |
| **S6 家庭主密钥直接随码分发（无信封）** | 码 | ✅ | 极简 | 同 S4 | **否决** |

### 4.2 选择与派生规范

**KEK 派生**：

- **KEY_WRAP**：`shared = X25519(memberPriv, adminEphemeralPub)`（Admin 侧对称计算 `X25519(adminEphemeralPriv, memberPub)`）；
  `KEK = HKDF-SHA256(ikm=shared, salt=header_bytes, info="yaocore-family-invite-v1", L=32)`；
- **CODE_KEK**：`pass = PBKDF2-HMAC-SHA256(normalize(code), salt, 120000, 32)`；
  `KEK = HKDF-SHA256(ikm=pass, salt=header_bytes, info="yaocore-family-invite-v1", L=32)`。

**邀请码规范（C-009 裁定）**：**固定 6 位**，字母表 = Crockford Base32 去歧义集合（`0123456789ABCDEFGHJKMNPQRSTVWXYZ`，排除 `I/L/O/U`），输入大小写不敏感并做 `O→0 / I,L→1` 归一化；显示为大写（如 `7F3K9D`，与 UIUX L98 示例一致）。需求 L67 的"6~8 位"在 v1 收敛为 6（补丁提案 §11-P-01）；**30 bit 有效空间是弱模式的固有上限，因此默认单次 + 24h，且推荐使用 KEY_WRAP**。

**关键纪律**：
1. 成员私钥与 Admin 临时私钥均只在内存/Asset Store；使用后立即销毁（一次性）；
2. GCM `iv` 12B 随机、一次一密；禁止复用；
3. 解封失败一律 fail-closed，不给出"可能是版本/可能是码"的区分性提示（防 oracle）；
4. 码与密文建议**分信道**传递（如：码口头、密文聊天），CODE_KEK 的 UI 需显式提示该建议。

---

## 5. Decision 4：校验主体与离线语义（G-D8-3）

### 5.1 校验主体（无服务器时的责任划分）

| 校验项 | 执行主体 | 时机 | 强度性质 |
|---|---|---|---|
| 容器格式/版本/AEAD 完整性 | **成员设备**（本地） | 接受时 | 密码学（强） |
| `expireAt` | 成员设备本地时钟 | 接受时 | 客户端策略（软） |
| `targetRole/allowedRoomIds/familyId` | 成员设备（来自被认证的头） | 接受时 | 密码学（强，AAD 绑定） |
| `maxUses/usedCount/撤销` | **Admin 设备**（邀请注册表） | 生成时 + **回执到达时**（延迟） | 策略（弱/延迟） |
| 密钥材料真实性 | 成员设备（AEAD + 封装来源） | 接受时 | 密码学（强） |

### 5.2 离线语义（明确声明）

1. **无在线判定**：接受动作完全发生在成员设备上；不存在"服务端校验邀请码"的步骤。
2. **`expireAt` 是策略性约束**：成员设备在解封前检查绝对时间；时钟被回拨/错误的成员设备可能被拒绝（可用性问题）或在校验宽松时接受过期邀请（安全问题）。v1 采用**严格检查 + 显式提示**（"邀请已过期，请管理员重新生成"），并接受"用户时钟可靠性"为残留风险；家庭内所有时间使用 UTC 紧凑格式（README L32-33）。
3. **`maxUses` 是尽力而为**：真正生效需要回执（§5.4）；**默认 `maxUses=1`**；多用途邀请在 UI 上显式标注为"可重复使用（安全性降低）"。
4. **重放防护（离线）**：
   - `inviteId` 在 Admin 注册表内一次性（PENDING→ACCEPTED 后拒绝重复回执）；
   - 同一成员设备对同一 `inviteId` 只接受一次（本地去重）；
   - KEY_WRAP 天然绑定单一成员公钥（同一密文不能被第三方解封）；
   - CODE_KEK 无法阻止"持有码+密文的第二台设备"加入 → 这是弱模式的已知边界，靠单次使用 + 回执检测 + 轮换兜底。
5. **家庭/成员状态的收敛边界（v1 如实声明）**：成员列表、角色、房间等家庭元数据在各设备本地维护；无服务器下**只在设备间直接交换时收敛**（现场或同一局域网内用户触发）。v1 **不提供**成员"在线状态"的跨设备可见性（需求 L71 的"在线状态"降级为：本机可见的最近同步信息 + 未同步标记），并且**不实现**自动后台同步。此为 v1 声明性限制（见 `## ORCHESTRATOR_CLARIFICATION` Q2 与 `contract-baseline.md` §9）。

### 5.3 接受流程（成员设备）

1. 解析容器 → 校验版本/头 → 派生 KEK（§4.2）→ AEAD 解封；
2. 校验 `familyId/expireAt/targetRole/allowedRoomIds`；
3. 写入 Asset Store：逐网关 `commandSecret`（ADR-002 §8.3 别名）；写入路由记录：`gatewayId`、`pins/tlsEnabled`（若有）、`tls.port`；
4. 生成本地成员记录（`status=ACTIVE`、`expiresAt`（GUEST）、`joinedVia`）；
5. 生成**接受回执**（§5.4）并本地保存；
6. 销毁加入请求私钥与所有临时缓冲区。

### 5.4 接受回执（离线可校验的"已使用"证据）

```text
receipt = hex_lower(HMAC-SHA256(bundle.seed,
  "YAOCORE-INVITE-RECEIPT-V1\n" + inviteId + "\n" + memberId + "\n" + acceptedAt))
```

- 成员设备在 UI 显示回执二维码/6 位确认码；**Admin 设备在双方再次接触时（现场扫码、或同一局域网用户触发的直接交换）导入回执** → `usedCount++`、`status=ACCEPTED`、记录 `acceptedByMemberId/acceptedAt`；
- Admin 可校验回执（持有 `seed` 副本，保存于 Asset Store 的邀请记录中）；
- 若回执始终未到达，邀请保持 `PENDING` 直至 `expireAt`——**这是检测控制，不是阻止控制**（真正的阻止 = 轮换，§6）。

---

## 6. Decision 5：撤销与轮换（G-D8-4）

### 6.1 离线撤销的真实边界（必须先讲清楚）

被移除成员已经**持有**过 `commandSecret` 与可能的 TLS pin。App 侧"立即失效"（需求 L72）只能做到：

| 层面 | 效果 | 强度 |
|---|---|---|
| 被移除成员的本机 | App 收到/得知移除后删除家庭数据与凭据 | 依赖该成员的**配合**（非对抗假设）实时可达；对恶意成员无效 |
| 其他成员设备 | 在其设备下次与 Admin 设备直接交换时收敛成员表 | 延迟、尽力而为 |
| 网关 | 旧 `commandSecret` **仍然有效** | **必须轮换才能失效** |

### 6.2 轮换流程与成本分析（与 ADR-002 §8.4 共用）

`成员移除 / 设备丢失 / 邀请泄露 / GUEST 到期清理` 触发轮换建议：

| 步骤 | 内容 | 成本 |
|---|---|---|
| 逐网关 | BLE 就近：PoP + Security1 → 交付新 `commandSecret`（ADR-002 §8.4 R2-R4） | **每网关一次近距离操作**（N 网关 = N 次） |
| 成员再分发 | 对每个保留成员发放**新**邀请（KEY_WRAP 路径，现场或远程） | 每成员一次（KEY_WRAP 可远程，成本低） |
| 平台侧 | 更新 Asset Store、路由记录、回执注册表 | 本地零成本 |
| 云路径 | 若启用 C-023 云命令：网关 `KeyId/Sign` 与管理端 Token 不受影响（云命令由网关代理签名，App 不持有云端签名密钥），无需云侧改动 | 无 |

**结论**：v1 的撤销强度 = "轮换强度"，轮换成本 = **O(N 网关)** 次 BLE 就近操作 + O(M 成员) 次凭据重发。因此：
- 移除流程必须显式提示"该成员仍可能持有旧密钥，建议执行密钥轮换"（默认勾选，可跳过但要记录）；
- **GUEST 到期**（C-017）：到期时 App 本地冻结权限；**不自动轮换**（成本高），提示 Admin"若访客为不可信对象请执行轮换"；
- 高安全家庭建议：不向 GUEST 分发长期凭据，而用短有效期 + 到期后轮换。

### 6.3 必须如实声明的安全边界（评审与 UI 共同义务）

1. **无用户级鉴权**：局域网协议按网关鉴权（ADR-002 §8.2；`local-control-request.schema.json` 无用户/角色字段）。持有 `commandSecret` 即可对**该网关**上任意设备发令（App 侧房间限制不是密码学边界）；
2. 因此 **GUEST 凭据的语义 = "受限 UI + 可被轮换的网关级能力"**，不是"只能控制某几间房"的密码学保证；
3. Admin 生成 GUEST 邀请的 UI 必须包含上述提示与"默认 24h + 到期轮换建议"；
4. 该边界是 v1 声明性限制；若未来需要密码学级房间权限，需协议扩展（网关侧按 target 鉴权/多密钥分区），属固件协同提案 `EXT-ACL-001`（不实现）。

---

## 7. Decision 6：与 D-007 的交叉（G-D8-5）

1. **同一容器承载两类信任材料**：`commandSecret`（逐网关）+ `tls.pins/port`（逐网关）——成员**无需 BLE** 即获得局域网信任材料（架构 L111-113 的目标达成）；
2. **pin 随凭据的格式**：与 ADR-002 §4 完全一致（64 位小写 hex SPKI-SHA256；`sha256-spki-der`；有序多 pin），并与 `gatewayId` 同源绑定（bundle 内按网关分项）；成员设备解封后按 ADR-002 §8.3 存储（Preferences 存 pin、Asset Store 存 secret）；
3. **pin 轮换的再分发**：网关轮换 pin（ADR-002 §4.4）后，新 pin 需要到达所有成员。v1 路径：(a) 成员下一次配网/接触时更新；(b) 或 Admin 重新发放邀请（KEY_WRAP）批量更新。**不做**在线推送（无服务器）；提示 Admin 在轮换后重新分发；
4. **密钥模型交叉引用**：家庭容器的定义、存储边界与轮换流程以 ADR-002 §8 为准，本 ADR 只定义其**离线分发载体**。

---

## 8. Decision 7：威胁模型（G-D8-6）

> 约定：攻击者能力标注为 [网络] / [物理近场] / [成员设备被控] / [管理员设备被控] / [信道提供商]。

| # | 场景 | 攻击者能力 | 影响 | 对策 | 残留风险 |
|---|---|---|---|---|---|
| T1 | 邀请码离线爆破（密文泄露后） | [网络] | CODE_KEK 失守 → 家庭密钥泄露 | 30 bit 码 + PBKDF2 120k + HKDF（每猜测成本 ≈ 120k SHA256）；默认单次/24h；推荐 KEY_WRAP | **中**：CODE_KEK 密文泄露后仍存在可行爆破窗口（须靠短有效期与轮换兜底）→ 故弱模式必须显式标注 |
| T2 | 邀请二维码被拍照/截屏（KEY_WRAP） | [物理近场] | 无（密文不可解） | ECDH 绑定成员一次性公钥 | 低（照片无用） |
| T3 | 邀请二维码被拍照（CODE_KEK） | [物理近场] | 需要码（另信道）才可解 | 码/密文分信道；单次 | 中（若码同屏可见则等同 T4） |
| T4 | 码 + 密文双泄露 | [信道提供商]+[近场] | 家庭密钥泄露（成员设备可解封） | 单次、短时、回执检测、轮换 | **高（轮换前）**：明确写为可接受残余，UI 强制提示 |
| T5 | 传输信道 MITM（聊天/邮件） | [网络] | 可篡改/扣留（DoS）；AEAD 使篡改失效 | AEAD + AAD 绑定头部 + 版本前缀 fail-closed | 低（扣留导致可用性问题） |
| T6 | 已接受邀请重放（重入） | [网络/近场] | KEY_WRAP：不可（需成员私钥）；CODE_KEK：可能（第二台设备） | Admin 注册表单次 + 成员去重 + 回执检测 | 中（CODE_KEK）→ 轮换兜底 |
| T7 | 加入请求伪造（冒充新成员骗取邀请） | [网络/社交工程] | 攻击者获得家庭密钥 | 现场扫码时由 Admin 目视确认；远程时显示成员昵称 + 确认码（SAS）由双方核对 | 中（社交工程不可消除） |
| T8 | 成员设备被盗/被控（已入家庭） | [成员设备被控] | 持有全部家庭密钥 | 移除 + **轮换**（BLE，O(N) 网关）；提示用户优先处理 | 中（轮换完成前有效） |
| T9 | 被移除成员恶意保留密钥 | [成员设备被控] | 长期可控制 | §6 轮换；否则协议层无法失效 | **高（未轮换时）**——v1 的硬边界，必须如实告知 |
| T10 | Admin 设备被控 | [管理员设备被控] | 最高价值目标：全部密钥、注册表、seed | 设备解锁安全（系统级）；Asset Store `DEVICE_FIRST_UNLOCKED`；禁止导出明文；必要时重置家庭并逐网关轮换 | 高（设计上无补偿手段） |
| T11 | 过期邀请被接受（时钟错误） | 用户自身 | 策略失效 | 严格本地检查 + 明确提示；UTC 统一 | 低（多为可用性问题） |
| T12 | `maxUses` 超用（回执未达） | [网络/成员] | 超出预期人数入网 | 默认单次；回执机制；Admin 面板显示"待回执"邀请并支持轮换 | 中 |
| T13 | GUEST 越权（房间限制绕过） | [成员设备被控] | 可控制该网关全部设备 | App 侧 RBAC（策略层）；短时凭据；到期轮换 | **中（密码学边界不存在）**——§6.3 已声明 |
| T14 | 回执伪造（冒充已使用/未使用） | [成员设备被控] | 注册表污染（审计失真） | 回执 HMAC(seed)；Admin 校验；无法伪造 `memberId` 以外的语义 | 低 |

**结论**：离线模型的机密性在"成员私钥 + 一次性容器"上成立；**撤销性**受轮换成本约束，属于 v1 的显式属性而非缺陷；所有弱模式与边界必须进入 UI 文案（`i18n-resource-design.md` 的 `invite.security.*` 键族）与评审清单。

---

## 9. `FamilyInvitation` / `FamilyMember` 模型增补提案（DATA-001 修订提案）

> **不直接修改 `input/`**；以下为提案内容，供文档维护轮次（C-013 机制）合并。

### 9.1 `FamilyInvitation`（现状见 `Data_and_State_Models.md` L46-56）

| 字段 | 类型 | 语义 |
|---|---|---|
| `inviteId` | string (UUID) | 邀请唯一 ID；注册表主键、回执绑定 |
| `version` | number | 容器版本（与 `YCI1.v` 一致） |
| `mode` | `'KEY_WRAP' \| 'CODE_KEK'` | 分发路径 |
| `transport` | `'QR' \| 'TEXT'` | 实际分发形态（审计用） |
| `status` | `'PENDING' \| 'ACCEPTED' \| 'EXPIRED' \| 'REVOKED'` | 取代仅 `usedCount` 的状态表达 |
| `codeSalt?` / `kdfIterations?` | string / number | CODE_KEK 参数（**不存明文码**；码仅在生成时展示一次，可"重新生成"） |
| `memberId?` | string | KEY_WRAP 绑定的加入请求标识 |
| `payloadString?` | string | 邀请容器文本（密文，可重分享；非秘密） |
| `seedRef` | string | `seed` 的 Asset Store 别名（不存明文） |
| `issuerDeviceId` | string | 发起邀请的 Admin 设备安装标识 |
| `acceptedAt?` / `acceptedByMemberId?` / `receipt?` | string | 回执与接受信息（§5.4） |
| `revokedAt?` / `revokedReason?` | string | 撤销审计 |
| `usedCount` / `maxUses` / `expireAt` / `targetRole` / `allowedRoomIds` / `familyId` / `familyName` / `inviterId` | 既有 | 语义保留；`maxUses` 默认 1 |

### 9.2 `FamilyMember`（C-017 时效模型；现状 L26-41）

| 增补 | 语义 |
|---|---|
| `status` 增加 `EXPIRED` | GUEST 到期后的冻结态（权限不可用，需 Admin 续期或重新邀请） |
| `expiresAt?: string` | GUEST 时效（随邀请头写入）；`MEMBER/ADMIN` 缺省无期限 |
| `memberDeviceId?` | 成员设备安装标识（与邀请 `memberId` 对应，用于回执核对与移除告知） |
| `joinedVia?: 'INVITE_KEY_WRAP' \| 'INVITE_CODE_KEK' \| 'ADMIN_LOCAL'` | 加入路径审计 |
| `secretsVersion?` | 该成员设备当前持有的密钥版本（轮换后据此判断"待更新成员"） |

### 9.3 相关函数语义（供 DES-001 引用，不在本 ADR 展开）

`createInvitation(...)`、`acceptInvitation(container, code?|joinPrivateKey)`、`revokeInvitation(inviteId)`、`reconcileReceipt(receiptText)`、`rotateGatewaySecret(gatewayId)`、`markMemberRemoved(memberId)` 的职责边界归 wp-006 详细设计。

---

## 10. 家庭生命周期（FR-FAM-004 的 v1 设计声明）

| 场景 | v1 行为 | 密码学后果 |
|---|---|---|
| 成员退出家庭 | 本机删除家庭数据与凭据（或保留"已退出"记录）；Admin 在其下次接触时收敛成员表 | 退出者保留旧密钥 → 与移除同：提示 Admin 轮换 |
| Admin 转让 | 本地角色更新（新 Admin = 既有成员，已持有密钥）；经设备间交换收敛 | 无新增暴露 |
| 解散家庭 | Admin 本机删除家庭与全部成员凭据记录；网关侧**建议**重置/解绑（必要时重新配网）；所有成员设备在下次接触时得知家庭不存在 | 旧密钥仍在网关有效 → 需逐网关轮换（§6.2）；v1 提供引导流程，不自动执行 |
| GUEST 到期 | `status=EXPIRED`；冻结控制与房间可见性 | 密钥未失效 → 提示轮换（§6） |

**范围声明**：FR-FAM-004 在 v1 为**本地语义 + 引导流程**，不承诺跨设备强一致（无服务器；§5.2 第 5 条）。

---

## 11. Consequences

**正**：

- G-D8-1..6 全部闭环：版本化容器、双路径封装、离线校验主体、轮换成本模型、指纹交叉分发、14 项威胁清单。
- KEY_WRAP 路径把机密性建立在 ECDH 一次性密钥上（不受 6 位码空间限制），同时保留 UX 既有的 6 位码弱路径（可用性兼容）。
- 与 ADR-002 共用"每网关独立密钥 + pin"的信任材料模型，成员加入路径与配网路径的密钥语义一致（无需 BLE）。
- 所有限制（撤销、无用户级鉴权、成员状态收敛）显式声明，避免"看起来安全"的实现偏差。

**负 / 成本**：

- KEY_WRAP 引入"成员先出示加入请求"的交互步骤（产品形态变化 → 见 Clarification Q1）。
- CODE_KEK 的 30 bit 上限不可消除，只能收敛使用条件（单次、短时、分信道）。
- 撤销依赖 O(N) 次 BLE 轮换，体验成本高；UI 必须如实呈现。
- 成员列表/角色/房间的跨设备一致性弱（本地 + 接触式收敛），需求中"在线状态"无法完整兑现。

## 12. Alternatives（记录）

- 见 §4.1（S1-S6 全表）；另：
- **A1 单路径（仅 CODE_KEK）**：否决——把家庭密钥安全性压到 30 bit 弱边界，且违背"架构 L112 encryptedKey + 交换"的设计意图。
- **A2 单路径（仅 KEY_WRAP）**：部分否决——把"只想知道邀请码"的轻量场景排除（UX L98 的输入码路径消失），保留双路径更贴合语料。
- **A3 用网关做接受校验/计数**：v1 否决（网关协议无家庭端点；需固件扩展；且远程成员不可达）→ 记为 `EXT-FAMILY-COORD-001`（未来，若固件愿意承担）。
- **A4 云中转校验**：否决（违反 D-008）。
- **A5 只做"邀请码=会话句柄 + 现场 ECDH"（强制就近）**：否决——剥夺远程加入能力（需求 L69 未限制场景；UIUX 未要求就近）。

## 13. 需固件协同项（Firmware Coordination）

| # | 协同项 | v1 阶段性策略 |
|---|---|---|
| FC-D8-01 | （可选，未来）网关家庭协调端点 `EXT-FAMILY-COORD-001`：接受回执上报/成员表同步 | v1 不做；接受回执靠设备间接触交换 |
| FC-D8-02 | 与 ADR-002 FC-01/FC-05 共用：TLS v2.1、密钥轮换流程 | 同 ADR-002 §10 |
| FC-D8-03 | （可选）`EXT-ACL-001`：网关按设备/角色鉴权以支撑房间级密码学权限 | v1 不做；以 §6.3 声明边界 |

## 14. References

`Data_and_State_Models.md` L26-56；`App_System_Architecture.md` L105-113；`YaoCore_HarmonyOS_App_Requirements.md` L36-38/L66-74/L136-139/L152-153；`UI_UX_Specification.md` L78-107；`README.md` L32-33/L89-107；`local-control-request.schema.json` L30-33；`AuthService.ets` L31/L91-171/L194-202；`SecureStorageService.ets` L18-19/L35/L44；`BLE配网设计.md` L153-155；`隐私与本地配置.md` L37/L60-66；ADR-002 §4/§8/§10；`WP3` §4.2/§4.3/§5(P0-4/P1-10)；`WP2` §7.3；`docs/internationalization.md` L20-49。

---

## ORCHESTRATOR_CLARIFICATION（需用户/产品决策）

> 以下为**实质产品取舍**，语料与已决方向不足以可靠推定；列选项与权衡，未擅自决定。实现不受阻塞的部分按正文推荐值推进（KEY_WRAP 主路径 + CODE_KEK 兼容路径）；仅 Q1 影响 UI 流程形态。

**Q1（邀请交互形态）**：KEY_WRAP 主路径需要"成员先出示加入请求（YCR1）"一步；UX 现行流程（`UI_UX_Specification.md` L89-102）是 Admin 先出码/码。请选择：

- **选项 A（推荐）**：加入流改为"成员先出示加入码 → Admin 扫描/粘贴 → Admin 出邀请二维码/文本"。安全性最高（密文泄露不可破），交互多一步。
- **选项 B**：维持 Admin 先出码的现行 UI，弱模式（CODE_KEK）为默认，KEY_WRAP 作为"高级/安全模式"入口。安全性依赖码与密文分信道传递的自觉性。
- **选项 C**：两者并存，成员端首屏提供两个按钮（"扫描邀请"与"出示我的加入码"），由操作方选择。UI 复杂度最高，兼容性最好。

**Q2（成员状态一致性）**：无服务器下，成员列表/角色/房间只能"接触式收敛"，且需求 L71 的"成员在线状态"无法跨设备实现。请确认 v1 处置：

- **选项 A（推荐，先声明后演进）**：v1 如实降级（本地权威 + 手动/接触同步 + 无在线状态），把跨设备实时性留待云端路径（C-023）或固件协调端点（FC-D8-01）。
- **选项 B**：把"成员在线状态/成员表同步"提为 v1 阻塞需求，改动 ADR-002/003 引入新通道（云端或网关端点）——需重开范围。

**Q3（GUEST 到期后的轮换）**：GUEST 到期是否**强制**进入轮换引导（成本 O(N) 次 BLE），或仅提示？

- **选项 A（推荐）**：提示 + 一键进入轮换引导，不强制（避免家庭体验过重）。
- **选项 B**：强制轮换（把访客模型做成密码学强隔离）——成本高，且与 §6.3 的"无用户级鉴权"边界一致后才可能真正生效。

---

*ADR-003 结束。机制落地细节（类/函数/状态机）归 wp-006 DES-001；模型修订以 §9 提案形式提交文档维护轮次（C-013）。*
