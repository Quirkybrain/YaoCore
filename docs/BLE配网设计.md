# YaoCore BLE 配网设计与验收规范

## 1. 结论与范围

YaoCore 网关采用 ESP-IDF 5.2 的官方 Unified Provisioning 协议栈：BLE GATT 负责传输，Protocomm Security1 负责应用层安全，Wi-Fi Provisioning protobuf 负责扫描、下发凭据和查询连接状态。手机端不是向一个自定义特征写入 SSID/密码 JSON；它必须实现同一套 Protocomm/protobuf 协议。

本规范以仓库中的实际常量为唯一基准：

| 项目 | 值 |
|---|---|
| 广播设备名前缀 | `YaoCore-GW-` |
| 完整设备名 | `YaoCore-GW-` + STA MAC 后 3 字节（6 位大写十六进制） |
| Primary Service UUID | `7a6e0001-4d7b-4f67-9a21-6d13c52ae3b8` |
| 传输 | BLE GATT |
| 会话安全 | Protocomm Security1 + 每台设备独立 PoP |
| 配网协议 | ESP-IDF Wi-Fi Provisioning protobuf |
| 重置配网 | 固件运行时长按 BOOT/GPIO0，默认 5 秒 |

不要再使用 ESP-IDF 示例的 `021a...` Service UUID、`PROV_...`/`YaoCore_...` 广播名或自定义明文 JSON 协议。

## 2. GATT 发现契约

ESP-IDF 会根据注册顺序为各 Protocomm endpoint 自动分配 Characteristic UUID。当前构建中可能观察到 `7a6eff4f...` 至 `7a6eff53...` 一类值，但这些值只适合串口日志和抓包诊断，**不是手机端的稳定接口**。新增 endpoint、调整 ESP-IDF 版本或注册顺序后，它们可能变化。

手机端必须执行以下发现流程：

1. 扫描广告中的 Primary Service UUID；设备名 `YaoCore-GW-` 只作为展示和辅助过滤条件。
2. 连接目标设备，协商 MTU，目标值为 512。
3. 发现 `7a6e0001-4d7b-4f67-9a21-6d13c52ae3b8` 下的全部 Characteristics。
4. 对每个 Characteristic 读取 User Characteristic Description 描述符 `0x2901`（完整 UUID 为 `00002901-0000-1000-8000-00805f9b34fb`）。
5. 以描述符的 UTF-8 文本建立 endpoint 到 Characteristic 的动态映射，并确认标准 endpoint 与 YaoCore 身份 endpoint 存在；新版固件还提供显式完成 endpoint。

| endpoint | 作用 | 安全会话要求 |
|---|---|---|
| `proto-ver` | 查询协议版本和能力 | 明文 |
| `prov-session` | Security1 握手 | 握手报文 |
| `prov-scan` | 启动 AP 扫描、查询结果 | 握手后加密 |
| `prov-config` | 设置/应用 Wi-Fi、查询状态 | 握手后加密 |
| `prov-ctrl` | 配网状态机控制 | 握手后加密 |
| `yaocore-id` | 读取待入网网关的逻辑身份 | 握手后加密，且必须在发送 Wi-Fi 凭据前调用 |
| `yaocore-done` | App 确认已取得最终 IP 后关闭 BLE 配网 | 握手后加密；旧固件可选兼容 |

若 `0x2901` 缺失、描述符不可读、endpoint 重名或任一必需 endpoint 缺失，App 应终止本次配网并提示“网关配网协议不完整”，不能按 Characteristic 顺序猜测。

每次 Protocomm 请求均为“向 endpoint Characteristic 执行有响应写入，再从同一 Characteristic 读取响应”。不要把它实现成通知订阅协议。所有 GATT 操作必须严格串行；上一笔写和读完成前不得发送下一笔请求，以避免 HarmonyOS GATT busy 错误和 Security1 密码流错位。

## 3. `proto-ver` 能力门禁

Security1 握手前，App 向 `proto-ver` 写入非空探测值（官方客户端使用 `ESP`），再读取明文 JSON。App 至少应验证：

- `prov.ver` 为兼容的 `v1.1`；
- 安全版本包含 `sec_ver = 1`；
- 未声明 `no_sec`；
- 未声明 `no_pop`；
- 提供 Wi-Fi 扫描能力；
- YaoCore 应用信息为 `yaocore` 版本 `2.0`，或包含等价的 YaoCore 2.0 能力信息。

能力不兼容时立即断开，不能降级到 Security0 或明文下发 Wi-Fi 密码。

## 4. Security1 精确互操作流程

Security1 使用 X25519、`SHA-256(PoP)` 和 AES-256-CTR。它提供基于 PoP 的设备证明和链路机密性，但 AES-CTR 不是 AEAD，不能把 Security1 描述成具有 AES-GCM 等价的密文完整性保护。

### 4.1 第 0 阶段

1. App 生成一次性 X25519 密钥对。
2. App 将 **32 字节原始公钥** 放入 `SessionData(sec_ver=1, sec1.sc0.client_pubkey=...)`，发送至 `prov-session`。
3. 网关返回 `device_pubkey`（32 字节原始公钥）和 `device_random`（16 字节 IV）。

HarmonyOS `publicKey.getEncoded()` 通常返回 X.509 SubjectPublicKeyInfo DER，而 ESP-IDF protobuf 要求原始 32 字节 X25519 公钥。禁止直接把整段 DER 发送给网关；必须经过已验证的 DER 解包/封装转换，或使用能够导入导出原始 X25519 key material 的接口。

### 4.2 密钥派生与证明

```text
shared_secret = X25519(client_private_raw, device_public_raw)
pop_digest    = SHA256(UTF8(PoP))
session_key[i] = shared_secret[i] XOR pop_digest[i]   // i = 0..31
iv = device_random                                    // 16 bytes
```

随后初始化一个 AES-256-CTR/NoPadding 流：

1. 使用该流加密 `device_public_raw`，结果作为 `client_verify_data` 发送到 Security1 第 1 阶段。
2. 使用**同一个连续密码流**解密网关返回的 `device_verify_data`。
3. 常量时间比较解密结果与 `client_public_raw`；不相等即判定 PoP 或设备身份错误并断开。
4. 继续使用这一个密码流，按顺序加密请求、解密响应。不能为每条消息重新使用初始 IV，也不能跳过失败消息后继续复用流。

一旦发生写失败、读失败、超时、取消或 BLE 断开，App 必须关闭 GATT、丢弃密钥与 cipher 状态，重新连接并从第 0 阶段建立新会话。只有在成功读到一笔响应后才推进协议状态。

### 4.3 X25519 端序验收门

HarmonyOS 真机实现必须先通过 RFC 7748 的 X25519 向量，避免 DER、端序或 key-spec 转换错误：

```text
scalar   a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4
u        e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c
expected c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552
```

X25519 的 32 字节 scalar 和 u-coordinate 按 RFC 7748 的 little-endian 编码处理。

## 5. protobuf 与 Wi-Fi 配网流程

协议定义以 ESP-IDF 5.2 对应文件为准：

```text
$IDF_PATH/components/protocomm/proto/constants.proto
$IDF_PATH/components/protocomm/proto/sec1.proto
$IDF_PATH/components/protocomm/proto/session.proto
$IDF_PATH/components/wifi_provisioning/proto/wifi_constants.proto
$IDF_PATH/components/wifi_provisioning/proto/wifi_config.proto
$IDF_PATH/components/wifi_provisioning/proto/wifi_scan.proto
$IDF_PATH/components/wifi_provisioning/proto/wifi_ctrl.proto
```

不要在 App 和固件之间再添加 YaoCore 自定义帧头。protobuf 序列化结果直接作为 Protocomm payload；Security1 建立后，业务 payload 先经过连续 AES-CTR 流再写入 GATT。

可用于编解码器回归测试的最小向量：客户端原始公钥为 `00 01 ... 1f` 时，第 0 阶段明文 protobuf 必须等于：

```text
10015a25a201220a20000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
```

另外两个 Wi-Fi Config 明文向量为：

```text
get_status   5200
apply_config 08047200
```

完整用户流程：

1. 用户点击“BLE 配网”，App 先检查“我的 > 安全配置”中已保存与目标网关一致的命令 HMAC 密钥，再申请 `ohos.permission.ACCESS_BLUETOOTH` 运行时权限。命令密钥只用于配网后的 HTTP 认证，绝不通过 BLE 发送。
2. 扫描网关，按 `deviceId` 去重；10 秒无结果时给出蓝牙、距离、网关配网模式检查提示。
3. 连接、请求 MTU 512、发现 Service、通过 `0x2901` 动态映射 endpoint。
4. 查询 `proto-ver` 并执行能力门禁。
5. 用户输入/扫码获得该设备的 PoP，完成 Security1。
6. App 在该 Security1 会话内调用 `yaocore-id`，请求 `{"op":"get_identity","protocolVersion":"2.0"}`，保存响应中的 `gatewayId`；此处不交换命令密钥。
7. 通过 `prov-scan` 启动阻塞式扫描，分页获取 AP；每页最多请求 4 条。原始 AP 可按 SSID+BSSID 区分，当前 UI 按 SSID 聚合并保留信号最强的一条，也要保留隐藏 SSID 的手动输入入口。
8. 用户选择 2.4 GHz Wi-Fi，App 发送 `set_config`，再发送 `apply_config`。
9. 每 1 至 2 秒查询一次 `get_status`，总超时 30 秒；明确区分 `AuthError` 和 `NetworkNotFound`。
10. 新版固件关闭 ESP-IDF 自动停止机制：App 取得 `get_status=connected` 和最终 IPv4 后，通过 `yaocore-done` 明确确认；网关延迟清理 BLE，确保完成 ACK 可读取。旧固件成功阶段的 BLE 断开仍按兼容路径处理。
11. App 优先对 `get_status` 返回的 IP 做有限次数指数退避探测。只有 `/discover` 请求/响应 HMAC 均通过、响应 `gatewayId` 与 Security1 内读取值完全相同，且板载 LED 执行回传确认后才绑定。失败时提示手机切换到同一新 SSID，不按广播名、MAC 后缀或邻居发现顺序猜测身份。自动绑定采用有限次数和指数退避，超过上限后暂停并等待用户检查网络或控制密钥，不能无限刷新页面。BLE 成功不等于绑定完成。

协商 MTU 512 是目标而非绝对保证。网关明确把 NimBLE 首选 MTU 设为 256，App 读取实际协商结果并要求至少 247；该下限可以容纳一页 4 条最坏长度的 AP 结果。低于下限时必须提示“蓝牙数据长度协商失败”，不能截断 protobuf。AP 扫描仍采用每页最多 4 条以控制响应大小。

`WiFiScanResult.rssi` 是 protobuf `int32`。负数会以 10 字节符号扩展 varint 编码，例如 `-100` 的 value bytes 为 `9cffffffffffffffff01`。ArkTS 解码器不能把这个 64-bit 无符号中间值直接累计到 JavaScript `Number` 后再转换，因为超过 `2^53` 会丢失低位；应使用 BigInt，或在读取 varint 时明确保留低 32 位，再按 two's-complement 转换为有符号值。

## 6. 权限、隐私与密钥

- 当前 target API 22 使用 `ohos.permission.ACCESS_BLUETOOTH`，该权限是 `user_grant`，必须在用户触发配网时调用运行时授权；拒绝后提供前往系统设置的说明。
- 首次扫描前检查蓝牙是否开启；不要在页面加载时静默扫描。
- PoP 必须逐设备生成，不得由 MAC 地址推导，不得所有设备共用，不得提交正式值到仓库。生产设备建议至少包含 128 bit 随机熵，再编码为可打印的 Base32/二维码内容，并通过机身标签或安全记录交付。
- PoP 与局域网控制 HMAC secret 是不同用途的秘密，不能复用。
- App 不应持久化 Wi-Fi 密码；退出、成功、失败或取消时清空页面字段，并尽快释放包含密码、PoP、session key 的临时缓冲。
- ESP-IDF 默认把 Wi-Fi 凭据写入 NVS。只有同时正确启用 Flash Encryption/NVS Encryption 时，才能宣称凭据“静态加密存储”；产品文档不能仅凭 Security1 就作此宣称。
- BLE 配网使用 Security1 应用层加密，为兼容不同 HarmonyOS 手机，本设计不强制 BLE bonding/link encryption。产品化可评估 Security2（SRP6a + AES-GCM）或完整的设备证书体系，但不能在未完成 HarmonyOS 互操作实现时临时切换协议。

## 7. 状态机与错误闭环

```text
Idle -> Permission -> Scanning -> Connecting -> Discovering
     -> CapabilityCheck -> SecurityHandshake -> SecureIdentity -> ApScanning
     -> SendingCredentials -> WaitingForWiFi -> DiscoveringOnLAN -> Bound
```

所有中间状态都必须支持用户取消并回到 `Idle`，同时停止扫描、关闭 GATT、注销监听器和销毁密码学状态。错误建议映射如下：

| 场景 | 用户提示 | 后续动作 |
|---|---|---|
| 权限拒绝 | 需要蓝牙权限才能配置网关 | 提供系统设置入口 |
| 蓝牙关闭 | 请先开启蓝牙 | 等用户开启后重试 |
| 找不到设备 | 请确认网关处于首次配网/重置配网状态 | 重新扫描 |
| endpoint 不完整 | 网关配网协议不兼容 | 断开，不降级 |
| PoP/设备证明失败 | 配网码不正确 | 清理会话，重新连接 |
| GATT busy/读写超时 | 蓝牙通信中断 | 清理会话，重新连接 |
| `AuthError` | Wi-Fi 密码错误 | 重新输入；重新建立安全会话 |
| `NetworkNotFound` | 未找到该 2.4 GHz Wi-Fi | 重新扫描或手输 SSID |
| 网关已连 Wi-Fi、局域网未发现 | 手机需回到同一家庭网络 | 保留“重试发现”，不重复下发密码 |
| BLE 身份与 HTTP 身份不一致 | 已拒绝绑定错误网关 | 不猜测、不切换到其他发现结果 |

固件在凭据错误后调用 `wifi_prov_mgr_reset_sm_state_on_failure()`，可继续接受新凭据。App 为避免复用失步的 CTR/GATT 状态，应关闭后重新连接并建立新 Security1 会话。

## 8. 端到端验收用例

发布固件前至少完成以下实机记录：

1. 全新擦除 NVS 后上电，手机能看到 `YaoCore-GW-XXXXXX` 并用正确 PoP 配入 2.4 GHz Wi-Fi。
2. 错误 PoP 不会泄露或接受 Wi-Fi 凭据；修正 PoP 后可重新配网。
3. 错误 Wi-Fi 密码得到 `AuthError`，不重启 App 也能走完一次新的成功流程。
4. 不存在 SSID 得到 `NetworkNotFound`；隐藏 SSID 可手动填写。
5. 配网期间断开蓝牙，重连后重新握手并成功；不存在 CTR 会话复用。
6. 权限拒绝、蓝牙关闭、扫描超时和用户取消都能恢复到可再次操作状态，无重复监听和卡死。
7. 至少两款 HarmonyOS 手机/不同系统版本验证扫描、MTU、`0x2901` 读取、X25519 和 AES-CTR 互通。
8. Wi-Fi 成功后 BLE 自动断开，App 优先探测返回 IP；记录 Security1 身份、HTTP 双向 HMAC 身份和板载 LED 回传三者一致后才绑定。
9. 网关重启后直接使用 NVS 凭据联网，不再次广播配网服务。
10. 固件运行时长按 BOOT 约 5 秒并在提示后松开；固件等待 GPIO0 回到高电平才重启，避免误入 ROM 下载模式。只清除 Wi-Fi 凭据，其他网关配置不丢失。
11. 执行 `python -m unittest tools.test_ble_provisioning_contract -v`，所有静态契约与 protobuf 向量通过。

## 9. 官方依据

- [ESP-IDF Wi-Fi Provisioning Manager](https://docs.espressif.com/projects/esp-idf/en/v5.0.6/esp32s3/api-reference/provisioning/wifi_provisioning.html)
- [ESP-IDF Protocomm](https://docs.espressif.com/projects/esp-idf/en/v5.1.3/esp32s3/api-reference/provisioning/protocomm.html)
- [ESP-IDF 5.2 provisioning 示例](https://github.com/espressif/esp-idf/blob/v5.2.3/examples/provisioning/wifi_prov_mgr/main/app_main.c)
- [ESP-IDF 5.2 `esp_prov.py`](https://github.com/espressif/esp-idf/blob/v5.2.3/tools/esp_prov/esp_prov.py)
- [Espressif Android BLE transport](https://github.com/espressif/esp-idf-provisioning-android/blob/master/provisioning/src/main/java/com/espressif/provisioning/transport/BLETransport.java)
- [Espressif Android Security1](https://github.com/espressif/esp-idf-provisioning-android/blob/master/provisioning/src/main/java/com/espressif/provisioning/security/Security1.java)
- [RFC 7748: Elliptic Curves for Security](https://www.rfc-editor.org/rfc/rfc7748)
- [ESP-IDF NVS Encryption](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/storage/nvs_encryption.html)
- [HarmonyOS BLE 官方 Codelab](https://developer.huawei.com/consumer/en/codelab/HarmonyOS-BLE/)
