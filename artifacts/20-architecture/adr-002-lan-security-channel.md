# ADR-002 — 局域网安全通道：HMAC 全链必做 + 本地 HTTPS/证书指纹固定（D-007 形式化）

- **Artifact ID**: ADR-002
- **Producer**: agent:solution-architect
- **Type**: Architecture Decision Record
- **Status**: Proposed（待 G-004 门禁批准）
- **Date**: 2026-10-17
- **Task**: `wp-004-contracts`（task 分支 `task/wp-004-contracts`，父分支 `feat/yaocore-app`，base commit `54c1d786`）
- **Workflow**: STANDARD / GATED_AUTO
- **Upstream 证据**: D-007 用户决策（`state/project-state.md` L57）；`WP2`、`WP3` §4.1（G-D7-1..6 / C-019）；冻结输入 26 项
- **Downstream 消费者**: `contract-baseline.md`（密钥模型与错误码表）、ADR-003（指纹随凭据分发 / 密钥轮换）、wp-005 规划、wp-006 DES-001、实现任务（传输/加密/设置）、TEST-001（TLS Mock 形态）
- **Traceability**: C-002 / C-019 / G-D7-1..6；FR-SET-002、FR-GW-002/003、FR-DEV-001；NFR-4.1；`隐私与本地配置.md`（PRIV）

> **方向已决（不得重开）**：D-007 = HMAC-SHA256 双向认证**必做** + 局域网 HTTPS/证书指纹固定（机密性）；AES-256-GCM 载荷信封（`EncryptedPayloadEnvelope`）记为**扩展提案归档**（§5）。本 ADR 只解决"如何落地"，不再评估方案取舍。

---

## 1. Context

### 1.1 可依据的既有条款（HMAC 侧充分）

| # | 内容 | 证据 |
|---|---|---|
| 1 | 控制请求 canonical（10 行、无末尾换行、value 原子编码规则） | `README.md` L57-87；`local-control-request.schema.json` L18-74；`hmac-sha256-test-vectors.json` 4 向量（`WP2` 复算一致） |
| 2 | 时间窗 ±120s、nonce 300s 缓存、精确重传幂等、冲突 409/1005、失败不消耗 nonce | `README.md` L89-103；`discover-response.schema.json` L33-51；仿真器实跑（`WP2` §3.3-F） |
| 3 | 发现请求签名（`YAOCORE-DISCOVER-V2`）+ 响应验签（`YAOCORE-RESPONSE-V1`，discover/control 两类） | `README.md` L109-157；`discovery-request-auth-test-vectors.json`；`response-auth-test-vectors.json`；归档 `SecurityService.ets` L94-135 |
| 4 | ACK 规则：`result_code==0` 才确认；`reported_state` 完整状态要求；correlation=`request_id:seq` | `README.md` L183-189；`local-control-ack.schema.json` L49-63；`网关接口协议.md` L17-26 |
| 5 | 方向与字段占位：方案 B 陈述、`certFingerprint`、`secureTransport/tlsEnabled` | 需求 L148；架构 L135-137；数据模型 L232-234；`config/project.md` L53 |

### 1.2 缺口（WP3 §4.1，本 ADR 逐项解决）

- **G-D7-1（阻塞，=C-019）** 证书指纹无协议承载：身份响应 schema 封闭且无 `certFingerprint`（`ble-enrollment-identity-response.schema.json` L6-26）；discover `security` 块封闭（`discover-response.schema.json` L33-51）；全语料 grep `certFingerprint` 仅命中架构 L136 与数据模型 L234 → **§3**。
- **G-D7-2** 指纹格式与证书体系未定义（编码/大小写/多指纹/与 `gatewayId` 绑定）→ **§4**。
- **G-D7-3** 首次信任、启用流程、失败回退、用户语义未定义 → **§6**。
- **G-D7-4** TLS 端口/共存策略与 Mock/仿真器 TLS 形态未定义（现仿真器仅 HTTP，`WP2` §7.3）→ **§7**。
- **G-D7-5** HMAC 密钥模型未定义：`app-key-v1` 与密钥材料解耦（`README.md` L105-107）；"家庭控制密钥"（需求 L69/L137）与每网关 `command_secret`（`EXTERNAL_MODULE_PROTOCOL.md` L24；PRIV L37）的作用域/数量/存储/轮换未定义 → **§8**。
- **G-D7-6** 数据模型 §3 GCM 信封与 D-007 不一致（C-002 遗留）→ **§5**。

---

## 2. Decision 1：HMAC 层为必做契约（v1 冻结，逐条锁定）

以下规则**原样接受**为 v1 契约基线，实现与评审必须逐条引用（`contract-baseline.md` §3 汇总）：

1. **控制请求（`POST /control`）**：10 行 canonical（`request_id / cmd_id / seq / target / action / value / timestamp / nonce / alg / key_id`），无末尾换行；`cmd_id=2001` 常量；`payload` 仅 `{action,value}` 且封闭；`value` 编码 = 单个 JSON 原子（缺省=空行；字符串=带引号 JSON；布尔；紧凑有限数字）；`sign=hex_lower(HMAC-SHA256(secret, canonical_utf8))`。
2. **发现请求（`GET /discover`）**：`X-YaoCore-Challenge`（16 字节小写 hex）、`X-YaoCore-Request-Nonce`（16 字节小写 hex）、`X-YaoCore-Request-Timestamp`、`X-YaoCore-Request-Alg`、`X-YaoCore-Key-Id`、`X-YaoCore-Request-Sign`；canonical `YAOCORE-DISCOVER-V2 / challenge / timestamp / nonce / HMAC-SHA256 / app-key-v1`。
3. **响应验签**：`X-YaoCore-Response-Alg/Key-Id/Response-Correlation/Response-Sign`；canonical `YAOCORE-RESPONSE-V1 / kind / correlation / sha256_lower_hex(body_utf8)`，`kind∈{discover,control}`；correlation = challenge（discover）或 `request_id:seq`（control）。
4. **时钟与重放**：网关接受 ≤±120s 偏移；记住 `(key_id, nonce)` 300s；nonce 仅在全部校验通过后入缓存；精确重传返回原状态与原 ACK（可加 `idempotent_replay:true`）；同 nonce 异内容 409/1005；签名/时间戳失败不消耗 nonce。
5. **比对纪律**：所有签名比对常数时间；密钥只存在于内存/Asset Store，不入日志（PRIV L3-17；ArkTS 规范 L60-64）。
6. **判定纪律**：HTTP 2xx 不是执行确认；确认 = 响应验签 + correlation 匹配 + `result_code==0` + `reported_state` 完整（`网关接口协议.md` L17-26）。
7. **降级禁止**：任何校验失败不得触发"跳过验签/跳过时间窗/回退明文载荷"的路径。

**结论**：HMAC 层在 v1 无缺口，**不随 TLS 是否启用而改变**（`README.md` L159-162 已明确 HMAC 保持必做）。

---

## 3. Decision 2：证书指纹载体 = 身份端点协议 v2.1（解决 C-019 / G-D7-1）

### 3.1 Context

- 架构要求：BLE 配网 `yaocore-id` 阶段传递 `certFingerprint`（架构 L135-137）；数据模型预留 `GatewayState.certFingerprint`（L234）与 `tlsEnabled`（L233）。
- 现实约束：身份响应 schema **封闭**（const `protocolVersion:"2.0"`，`additionalProperties:false`）；discover `security` 块同样封闭；本仓库不包含固件源码（`config/project.md` L50/L64），**改写现网封闭 schema 将破坏既有网关**。
- 安全前提：指纹必须在**已认证信道**内下发（Security1 会话），否则存在 TOFU/剥离攻击；配网是唯一的"带 PoP 的被认证绑定时机"。

### 3.2 Decision（方案）

新增**身份端点协议 v2.1**（版本化协议扩展，不修改 v2.0 语义）：

1. **请求**（新 schema `ble-enrollment-identity-request-v2.schema.json`）：
   ```json
   { "op": "get_identity", "protocolVersion": "2.1" }
   ```
2. **响应**（新 schema `ble-enrollment-identity-response-v2.schema.json`）：在 v2.0 四字段基础上增加**可选** `security` 对象（封闭）：
   ```json
   {
     "protocolVersion": "2.1",
     "serviceId": "YaoCoreGateway",
     "gatewayId": "gateway_01",
     "gatewayName": "客厅网关",
     "security": {
       "lan": {
         "tls": true,
         "port": 9200,
         "pins": ["<64 位小写 hex SPKI-SHA256>"],
         "pinAlg": "sha256-spki-der"
       }
     }
   }
   ```
   - `security.lan` 缺省 = 该网关**不提供 TLS**（HMAC-only profile）。
3. **协商流程（App 侧，fail-closed）**：
   1. App 先请求 `protocolVersion:"2.1"`；
   2. 若响应不能通过 v2.1 schema 校验（旧固件会以 v2.0 响应或拒绝）→ **在同一 Security1 会话内重试一次** `"2.0"` 请求，取得 v2.0 身份（无 TLS 信息）；
   3. v2.1 响应通过校验 → 在内存中固定 `pins`，与 `gatewayId` 绑定后写入本地路由记录（`tlsEnabled=true`、`certFingerprint=pins[0]`，字段沿用 DM L233-234 命名）；
   4. 任何无法归类的响应 → `PROVISIONING_IDENTITY_INVALID`（fail-closed，禁止猜测）。
   5. **降级说明**：降级唯一发生路径是"网关只支持 2.0"。请求 2.1→响应 2.0 的落差无法被 LAN 攻击者伪造（PoP 绑定对端），因此不存在可被 MITM 利用的版本剥离。
4. **为何不扩展 `/discover.security`**：discover 在绑定后才可用，且首次 discover 必然是 HMAC-only 明文传输——在此下发指纹等于把指纹交给 LAN 上的中间人（可同时篡改 HTTP 响应，仅有 HMAC 防篡改不防替换指纹的目标指向），无法建立可信首信。**否决**。
5. **为何不改写 v2.0 响应 schema**：现网封闭契约（`additionalProperties:false`）与向后兼容；旧 App 收到多余字段会 fail-closed（正是归档实现的行为）。**否决**。
6. **兼容策略**：v2.0 网关完全不受影响（HMAC-only profile，见 §6）；v2.1 为纯增量扩展，由固件在协同修订中实现（§10-FC-01）。

---

## 4. Decision 3：指纹格式、`gatewayId` 绑定与轮换（G-D7-2）

1. **指纹定义**：`sha256-spki-der` = 对**证书公钥的 DER 编码 SubjectPublicKeyInfo（SPKI）**做 SHA-256，输出 **64 位小写十六进制**。
   - 选择 SPKI 而非整证书的原因：自签名证书续期/重签时公钥可复用，SPKI 固定不因有效期变化而失效；整证书哈希会强迫证书字节完全不变（脆弱）。
2. **边界与校验**：`pins` 为**有序数组**（1..4 项），App 接受"任一 pin 匹配即通过"（支持轮换重叠期）；`port` 与 `gatewayId` **必须同一来源**；pin 字符串正则 `^[0-9a-f]{64}$`（大小写敏感小写；大写视为非法 → fail-closed）。
3. **绑定规则**：指纹在 Security1 会话内取得，存储时以 `gatewayId` 为键；App **禁止**把 gateway A 的 pin 用于 gateway B；`/discover` 返回的 `gatewayId` 与记录不符 → 按绑定校验失败处理（README L48-52），并保留原记录。
4. **轮换流程（v1）**：
   1. 网关生成新密钥对/新证书，并在配网会话（`yaocore-id`）中同时返回 `pins:[新, 旧]`（重叠期）；
   2. App 首次以新 pin 成功完成一次 HTTPS 校验后，将记录更新为单 pin（新），删除旧 pin；
   3. 网关在重叠期结束后停用旧证书。
   - 无在线推送；轮换只在**下一次配网/重新配对**时发生（与 BLE 就近安全前提一致）。轮换实现属固件协同项（§10-FC-02）。
5. **指纹不是秘密**：可存 Preferences/RDB（非 Asset Store），但须与路由记录同源更新；**禁止**允许用户手工"添加/编辑指纹"（替代信任）——唯一可信来源是配网会话。

---

## 5. Decision 4：GCM 载荷信封归档（C-002 遗留 / G-D7-6）

1. `Data_and_State_Models.md` §3 L192-217（`EncryptedPayloadEnvelope`、`SecureLocalControlPacket`）与 `Gateway_API_Specification.md` L146-166 的 AES-GCM 请求示例，**归档为扩展提案 `EXT-GCM-001`**：
   - 与 v2 schema 不兼容（`local-control-request.schema.json` L23 `cmd_id` const 2001、L90 封闭、payload 封闭）；
   - D-007 已将其定位为"协议扩展提案，App 侧预留接口，待网关固件协同后另行 ADR"。
2. **归档位置**：本 ADR §5 为规范记录点；`contract-baseline.md` §8.3 记 v1 范围声明；GCM 的完整提案文本不进入本仓库实现范围。
3. **App 侧预留（不实现）**：
   - 保留 `cmd_id = 2002` 与 `encrypted_payload` 名称作为**保留标识**（常量与文档注释，不写实现路径）；
   - 传输抽象（方案 B/TLS 与明文 HMAC 的语法选择）由 `LocalGatewayService` 承担（wp-006 详设），**不为 GCM 预置可运行分支**；
   - v1 行为：若请求 `cmd_id≠2001` → 网关按 1001 拒绝（结构非法），App 不发 2002。
4. **DATA-001 修订提案**（不直接改 `input/`）：把 §3 标题改为"扩展提案（EXT-GCM-001，v1 不实现）"，并注明密钥派生 `HKDF(secret,"yaocore-lan-enc")` 属提案内容。

---

## 6. Decision 5：启用、校验、失败与回退策略（G-D7-3）

### 6.1 三种通道档案（Channel Profiles）

| Profile | 条件 | 传输 | 机密性 | App 行为 |
|---|---|---|---|---|
| **P-HMAC**（基线） | 网关无 v2.1/未宣告 TLS | `http://<ip>:<port>` + HMAC 全链 | 无（仅防篡改/防重放） | 允许；网关详情页显式标注"局域网机密性未启用（仅防篡改）"；建议用户保持家庭 Wi-Fi 受信 |
| **P-TLS-PIN**（目标） | v2.1 宣告 TLS 且 pin 已固定 | `https://<ip>:<port>` + HMAC 全链 | 有（指纹固定防 MITM） | 全部 LAN 操作走 HTTPS；TLS 校验与 HMAC 双重校验 |
| **P-BLOCKED**（失败态） | v2.1 宣告 TLS 但握手/指纹校验失败 | 无 | — | **禁止明文回退**；LAN 能力整体不可用；提示修复路径（见 §6.3） |

### 6.2 启用与校验规则（P-TLS-PIN）

1. **启用时机**：配网绑定成功后第一次 LAN `discover` 起，即按记录 `tlsEnabled=true` 使用 HTTPS；绑定流程本身要求"HTTPS 探针 + discover 验签 + gatewayId 一致 + 板载 LED 回传"（README L48-53；BLE 设计 L143）。
2. **校验内容（全部必须）**：
   - TLS 版本 ≥ TLS 1.2（建议 1.3）；
   - 服务端证书链对"固定 pin"匹配（SPKI-SHA256，§4）；
   - 应用层 HMAC 响应验签通过（README L137-157）；
   - `gatewayId` 与绑定记录一致。
3. **失败语义（P-BLOCKED）**：pin 不匹配/握手失败/超时 → 该网关 LAN 通道**硬失败**：
   - 不发送任何控制请求（防止降级为可被 MITM 的明文控制）；
   - UI 提示"网关安全通道校验失败，已停止局域网控制"；提供"重新配网以更新信任"入口（走 BLE）；
   - 可选：若已配置云端（C-023），云路径独立可用（提示中注明）；
   - 记录安全事件（不记密钥/指纹以外的敏感数据）。
4. **明文回退判定**：
   - **P-TLS-PIN 失败 → 禁止自动或静默回退到 HTTP**（拒绝）；
   - **P-HMAC（未宣告 TLS）→ 不是"回退"**，是基线档案，允许并如实标注；
   - **用户显式选择"降级为仅防篡改"**：v1 **不提供**该开关（理由：D-007 将 HTTPS 定为机密性手段；提供一键降级会实质架空它）。例外通道：用户在设备详情显式"解除该网关 TLS 绑定（重新配网）"，其效果是回到 P-HMAC，需再次通过 BLE 会话取得新 pin（若网关仍宣告 TLS，重新配网将再次进入 P-TLS-PIN，因此该路径实际只服务于"网关不再提供 TLS"的降级场景）。

### 6.3 用户语义（i18n key 归 `i18n-resource-design.md`）

| 场景 | 用户可见语义（要点） | i18n key（示例） |
|---|---|---|
| P-HMAC 常态 | "局域网控制已启用防篡改；机密性未启用" | `gateway.security.hmac_only` |
| TLS 启用成功 | "安全通道已建立（证书指纹已固定）" | `gateway.security.tls_pinned` |
| pin 不匹配 | "网关身份校验失败，已停止局域网控制" + 重新配网入口 | `gateway.security.pin_mismatch` |
| 握手失败/超时 | "无法建立安全通道" + 重试/重新配网 | `gateway.security.handshake_failed` |
| 网关宣告 TLS 但记录无 pin（异常） | 同上按 P-BLOCKED 处理 | `gateway.security.state_inconsistent` |

---

## 7. Decision 6：TLS 端口/共存与 Mock/仿真器形态（G-D7-4）

1. **端口策略**：默认端口保持 **9200**（需求/数据模型 L228；README L219 仿真器示例）。启用 TLS 时，**同一端口以 HTTPS 提供服务**；同一 socket 不能同时是 HTTP 与 HTTPS，因此：
   - P-TLS-PIN 网关：9200 = HTTPS；
   - P-HMAC 网关：9200 = HTTP；
   - **迁移共存**：可选在**独立端口 9201** 保留 HTTP 明文监听，仅用于迁移验证窗口，且必须在文档中标注"过渡用途，非产品默认"。App 侧**不使用** 9201（不使用明文端点），端口仅作信息/诊断记录。
2. **手动 IP/端口边界**：手动地址（C-012）仅是**定位手段**，不得创建绑定；校验规则见 ADR-004 §5。端口默认 9200，允许用户经高级面板修改（仅在同一 gatewayId 校验通过时生效）。
3. **Mock/仿真器 TLS 形态（供测试）**：
   - `gateway_contract_server.py`（未来 `tools/simulator/`）新增 `--tls --cert <pem> --key <pem>`：以**自签名测试证书**在同一端口提供 HTTPS；启动日志打印 SPKI-SHA256 指纹（64 位小写 hex），便于测试断言；
   - 测试夹具：仓库内提供 `fixtures/tls/test-cert.pem`（**公开测试材料**，注释 `PUBLIC TEST DATA ONLY`，与协议向量同级纪律，PRIV L17）；
   - `MockGatewayService`（App 侧）支持 `tlsMode=false|pin-match|pin-mismatch|handshake-fail` 四种注入，用于三态（P-TLS-PIN / P-BLOCKED）与失败路径单测；
   - Hypium 集成测试可在本机启动 Python 仿真器 + 真实 TLS 握手（开发机环境，非真机）——归 TEST-001。
4. **协议扩展文档状态**：`--tls` 属测试夹具能力，不进入协议契约；协议契约以 §3 v2.1 schema 提案为准。

---

## 8. Decision 7：密钥模型（G-D7-5）

### 8.1 `key_id` 与密钥材料解耦（既有条款的形式化）

`key_id = app-key-v1` 是**版本标签**，与密钥材料解耦；换材料不改标签，直至协同版本滚动（README L105-107）。所有协议读写使用常量 `app-key-v1`（`local-control-request.schema.json` L68-70；`discover-response.schema.json` L40-42；`cloud-command.schema.json` L67-69）。

### 8.2 作用域与数量关系（多网关家庭）

| 概念 | 定义 | 数量关系 | 证据 |
|---|---|---|---|
| **网关命令密钥** `command_secret` | 单台网关的 HMAC 秘密（≥16 字节，每网关独立、不共用；不与 PoP 复用） | 1 : 1 于网关 | PRIV L37；`BLE配网设计.md` L154；`EXTERNAL_MODULE_PROTOCOL.md` L24 |
| **家庭控制密钥**（Family Control Secret Set） | **分发逻辑容器**：家庭内每台网关的 `command_secret` + 每台网关的 TLS pin 集合 + `familyId` + `keyId` 标签 | 1 : N（N=家庭网关数） | 需求 L69/L137；架构 L111-113；ADR-003 |
| **模块主密钥** `gatewayMasterSecret` | 网关↔外部模块派生链的根（`moduleKey=HMAC(master,"YAOCORE-MODULE-KEY-V1\n"+moduleId)`），**App 不持有** | 1 : 1 于网关 | `EXTERNAL_MODULE_PROTOCOL.md` L24-33 |

**禁止**：把多网关合并为一把共享密钥（违反每网关独立与最小暴露面）；把模块主密钥下发给 App/成员。

### 8.3 存储边界（Asset Store vs Preferences/RDB）

| 数据 | 存储 | 别名/键（建议） | 依据 |
|---|---|---|---|
| 每网关 `command_secret` | **Asset Store**（`@ohos.security.asset`，`Accessibility.DEVICE_FIRST_UNLOCKED`） | `yaocore.gateway.hmac.<gatewayId>`（替代归档单别名 `yaocore.gateway.hmac.v2`） | 归档 `SecureStorageService.ets` L18-19/L35/L44；需求 L153；PRIV |
| 云 token / refresh | Asset Store | `yaocore.cloud.token.v2`（沿用） | 归档 `SecureStorageService.ets` L18 |
| TLS pin、`tlsEnabled`、gatewayId、IP、port、lastSync | Preferences/RDB（非秘密） | `GatewayRoute` 记录 | DM L224-236；pin 为公开值（§4.5） |
| 家庭密钥容器快照 | 不落明文；仅存 Asset Store 单条目标识与各网关别名清单 | `yaocore.family.<familyId>.keyrefs` | ADR-003 §4 |
| Wi-Fi 密码 / PoP | **仅临时内存**，配网后立即覆盖 | — | ArkTS 规范 L62-64；`BLE配网设计.md` L155 |

**边界判定规则**（写为规范供评审引用）：凡泄露即可直接产生控制能力或冒充身份的值 → Asset Store；可由 Asset Store 内容重建或本身为公开值 → Preferences/RDB。**禁止**把密钥写入日志、异常文本、UI（ArkTS 规范 L64）。

### 8.4 轮换流程（v1）

| 步骤 | 内容 | 通道要求 |
|---|---|---|
| R1 | 用户（Admin）在网关详情触发"轮换控制密钥" | UI（Admin 权限） |
| R2 | App 进入 BLE 重新配网流程（PoP + Security1） | **BLE 就近**（Security1 已认证） |
| R3 | 网关生成新 `command_secret`（≥16B）并在已认证会话内交付 | Security1 会话 |
| R4 | App 写入 Asset Store（新别名值）→ 以新密钥完成一次签名 discover 验证（成功后才移除旧值） | LAN |
| R5 | 家庭成员凭据再分发（新 `command_secret` 随 ADR-003 凭据或局域网同步） | ADR-003 |
| R6 | 若需跨版本滚动（`app-key-v2`）：网关与 App 同时支持新旧 key_id 的**协调窗口**，窗口结束停用旧值 | 固件协同 FC-03 |

- **禁止**在无 TLS/GCM 的明文通道上传输新密钥（HMAC 不提供机密性；`README.md` L159-162 自述"passive LAN observer"可见 body）。**因此"空中轮换"在 v1 不可用**，必须 BLE 就近；待 TLS（本 ADR）或 GCM（EXT-GCM-001）就绪后可另立 ADR 启用远程轮换。
- 旧 App 忽略新增别名（`<gatewayId>` 后缀），无迁移负担（重构为全新 App，无历史用户数据迁移，见 `INV` AS-038/`project-state.md` L17）。

---

## 9. Consequences

**正**：

- C-019/G-D7-1..6 六个缺口全部有确定承载（v2.1 身份扩展、SPKI pin 格式、三档案策略、端口/Mock 形态、密钥模型与存储边界、GCM 归档）。
- v1 可在**无固件改动**下全部实现：HMAC 全链 + 配置文件驱动的 TLS 客户端能力 + Mock TLS 仿真；TLS 真机生效仅等待固件 v2.1。
- 与 ADR-003 共享同一信任材料分发模型（家庭容器 = per-gateway secret + pin），交叉缺口 G-D8-5 闭环。
- 存储边界给出了可机检的判定规则，供 wp-006 与评审统一引用。

**负 / 成本**：

- v2.1 需新 schema 文件 + 固件协同（§10）；在固件推出前，**机密性承诺不可宣称**（必须如实标注 P-HMAC）。
- 明文回退被禁止意味着 TLS 故障期的 LAN 能力不可用（安全优先），用户需重配网修复——这是刻意的可用性代价。
- 密钥轮换成本高（每网关一次 BLE 近距离流程 + 成员再分发）；ADR-003 的撤销分析依赖该成本模型。
- pin 采用 SPKI 后，"整证书替换但同密钥"仍被信任（设计取舍，见 §11-A2）。

## 10. 需固件协同项（Firmware Coordination）

| # | 协同项 | 需求方 | v1 阶段性策略（无固件时的行为） |
|---|---|---|---|
| FC-01 | `yaocore-id` v2.1：接收 `protocolVersion:"2.1"`，响应带 `security.lan{tls,port,pins,pinAlg}` | App 绑定流程 | 无 v2.1 → 回退 v2.0 身份 → P-HMAC；不打补丁不阻塞 |
| FC-02 | TLS 监听（9200，自签名证书，SPKI 指纹计算/轮换重叠期） | App 传输层 | 仿真器 `--tls` 提供等价测试形态（§7.3）；真机保持 HTTP |
| FC-03 | key_id 版本滚动窗口（`app-key-v1→v2`） | 密钥轮换 | v1 不滚动标签；材料轮换只走 BLE 重配（§8.4） |
| FC-04 | （关联 ADR-001 §8）ACK `error_code` 补齐、1008 发出 | 错误语义 | App 容忍缺失 |
| FC-05 | 控制密钥轮换的固件侧流程（生成/交付/停用旧值） | §8.4 | BLE 重配为唯一路径 |

所有 FC 项同时登记于 `contract-baseline.md` §9（v1 范围与阶段性策略表）。

## 11. Alternatives（被考虑并记录）

- **A1 用 `/discover` 扩展承载指纹**：否决（§3.2-4：首次发现无被认证信道，存在指纹替换窗口）。
- **A2 采用整证书哈希指纹**：保留为备选；否决理由为续期脆弱（§4.1）；若固件无法计算 SPKI，可退化为 `pinAlg:"sha256-cert-der"`（需本 ADR 修订与 schema 枚举扩展——留作 Future）。
- **A3 直接改写 v2.0 身份 schema**：否决（破坏现网封闭契约，旧 App fail-closed）。
- **A4 允许 TLS 失败后明文回退（可用性优先）**：否决（D-007 的机密性目标被架空；MITM 可主动制造 TLS 失败以迫使降级）。
- **A5 家庭共享一把命令密钥**：否决（违反每网关独立的最小暴露面原则，且与 PRIV L37 冲突）。
- **A6 远程（空中）密钥轮换**：v1 否决（HMAC 无机密性，明文通道泄露新密钥）；待 TLS/GCM。
- **A7 自建 CA/PKI（App 携带 CA 证书固定）**：否决（自签名 + pin 已达成 MITM 防护；CA 引入生命周期管理成本，超出 App 仓库边界）。

## 12. References

`README.md` L55-189；`local-control-request.schema.json` 全文；`local-control-ack.schema.json` L49-63；`discover-response.schema.json` L33-51；`ble-enrollment-identity-request/response.schema.json`；`Gateway_API_Specification.md` L126-166/L206-213；`App_System_Architecture.md` L128-137；`Data_and_State_Models.md` L192-217/L223-238；`YaoCore_HarmonyOS_App_Requirements.md` L145-149；`网关接口协议.md` L11/L17-26；`BLE配网设计.md` L133/L143/L154-157；`EXTERNAL_MODULE_PROTOCOL.md` L20-33；`隐私与本地配置.md` L3-17/L37/L60-66；`ArkTS_Coding_Standards.md` L53-64；`SecureStorageService.ets` L18-19/L35/L44；`SecurityService.ets` L94-135；`WP2` §3.3/§6；`WP3` §4.1/§4.3/§7-5；`state/project-state.md` L57。

---

*ADR-002 结束。本 ADR 与 ADR-003 构成"家庭信任材料分发"的联合设计；契约基线（`contract-baseline.md` §3/§9）汇总其规范性条目。*
