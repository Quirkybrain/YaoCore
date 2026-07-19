# YaoCore ESP32-S3M 网关

本目录是正点原子 DNESP32S3M 开发板的 ESP-IDF 网关工程，目标为 ATK-MWS3S/ESP32-S3-WROOM-1 N16R8（16 MB Flash、8 MB Octal PSRAM），推荐 ESP-IDF 5.2.5。它与仓库 `protocol/` 下的 v2 契约一致，不是模拟器。

## 已实现

- ESP-IDF Unified Provisioning BLE 配网、Protocomm Security1、逐设备 PoP；
- 无 Wi-Fi 凭据时进入配网，已有 NVS 凭据时直接连接；
- 运行中长按 BOOT（GPIO0）5 秒，松开后仅清除 Wi-Fi 凭据并重启配网；
- Wi-Fi STA、指数退避重连和 SNTP UTC 校时；
- mDNS `_yaocore._tcp`、UDP 发现和 `GET /discover`；
- 正点原子 DNESP32S3M 板载 0.96 英寸 ST7735S 160x80 LCD 状态面板，实时显示启动、BLE 配网、
  Wi-Fi 重连、IPv4 地址以及局域网服务端口；
- HMAC-SHA256 `POST /control`、120 秒时间窗、300 秒 Nonce 缓存；
- 精确重传只返回缓存 ACK，不重复执行；
- 门禁、LEDC 调光、SHT30、PIR 和空调 UART 桥接的真实硬件驱动；
- 门磁启用时必须读回目标位置才 ACK；灯光亮度使用真实 0～100% PWM 占空比；
- 空调命令必须收到匹配 `requestId` 的下位机结构化 ACK 才更新状态，支持
  `GREE`、`MIDEA`、`HAIER`、`GENERIC` 品牌路由；
- 未配置、初始化失败、采集失败或握手失败的设备保持离线，不填充演示状态；
- 华为云 IoTDA 强制 MQTTS、CA 验证、命令订阅/响应、30 秒周期及状态变化上报；
- `Presence_01`/`Sensor_01` 先形成传感器状态，再由独立本地规则通过统一设备路由控制执行器；
- 状态携带 `stateSource`、`triggerDeviceId`、`automationId`，App 可追踪物理、手机和自动化来源；
- 云端上报实际 Wi-Fi RSSI，并始终携带门、灯、环境、人体存在、空调的 Online 字段；
- 按 IoTDA 规范动态生成 `deviceId_0_1_YYYYMMDDHH` ClientId 和 HMAC-SHA256 Password，
  并在每次 MQTT 初连/重连前按当前 UTC 小时刷新凭据。

## 构建

安装 ESP-IDF 5.2.5 并打开对应版本的 ESP-IDF 终端。不要直接使用 ESP-IDF 6.x：6.x 已把内置 `wifi_provisioning` 迁移为独立的 `network_provisioning` 组件，API 名称也不同；本工程的组件清单有意限制为 `>=5.2,<6.0`。

```powershell
cd gateway/esp32s3m
idf.py set-target esp32s3
idf.py menuconfig
idf.py build
idf.py -p COMx flash monitor
```

本仓库版本已使用 ESP-IDF 5.2.5、目标 `esp32s3` 完成全量编译，主固件约
`0x15e0a0` 字节。构建产物位于 `dist/esp32-idf52-build/firmware/`；它使用无正式密钥的
验证配置，只证明代码可编译，不应代替为每块板执行 `menuconfig` 后重新构建。

首次切换到本版本时建议先执行一次：

```powershell
idf.py fullclean
idf.py set-target esp32s3
```

这是因为旧版 `sdkconfig` 可能仍保留已经删除的编译期 Wi-Fi SSID/密码选项，并且本版本新增了 NimBLE、Wi-Fi Provisioning 和 Protocomm Security1 组件。

在 `YaoCore Gateway` 菜单至少填写：

- `BLE provisioning proof-of-possession`：8～64 字节的逐设备配网 PoP；
- `App/gateway HMAC secret`：至少 16 字节，须与 App“我的 > 控制安全”一致；
- 网关 ID、显示名称和下文所列的实际硬件 GPIO/总线参数。

Wi-Fi 名称和密码不再写入 `menuconfig` 或固件，而由手机通过加密 BLE 会话发送，并由 ESP-IDF Wi-Fi 驱动保存到 NVS。PoP、HMAC 密钥及 IoTDA Secret 都不能以正式值提交到仓库。建议每台网关使用独立 PoP，并通过机身标签、包装二维码或安全记录交给配网者。

`sdkconfig` 是 `idf.py menuconfig` 为当前电脑和当前网关生成的完整设备配置，其中可能包含 PoP、App/网关 HMAC 密钥、IoTDA Secret、实际 GPIO 和本地构建选项，因此被 `.gitignore` 明确排除。仓库应跟踪的是不含设备秘密的 `sdkconfig.defaults` 和 `main/Kconfig.projbuild`：前者保存可复现的 ESP32-S3、16 MB Flash、PSRAM、BLE、IPv4 和 socket 基线，后者定义 YaoCore 配置项及安全空默认值。新环境运行 `idf.py set-target esp32s3` 后会根据这两份文件生成本地 `sdkconfig`，再由使用者在 `menuconfig` 填入每台设备的私有参数。不要通过 `git add -f` 强行提交真实 `sdkconfig`。

若使用 IoTDA，启用开关并填写 `mqtts://` URI、设备 ID 和设备原始 Secret。
固件会拒绝明文 `mqtt://`。固件在 SNTP 成功后派生 MQTT ClientId/Password；TLS
使用 ESP x509 Certificate Bundle 验证服务器证书。

## 正点原子开发板引脚

DNESP32S3M 板载用户 LED 已确认连接 GPIO1，采用灌电流方式，低电平点亮；工程已将它设为默认值。智能家居外设没有通用固定接线，必须按实际硬件在 menuconfig 设置：

- `Board LED GPIO`：默认 GPIO1
- `Board LED is active-low`：默认开启
- 门禁：执行输出 GPIO、开门有效电平；可选门磁/位置反馈 GPIO、反馈有效电平、命令超时、
  后台轮询间隔和稳定去抖时间；
- 调光灯：LEDC PWM GPIO、有效极性、频率和默认亮度；
- SHT30：启用开关、I2C 控制器、SDA/SCL、地址 `0x44/0x45` 和采集周期；
- PIR：输入 GPIO、有效电平、无人超时、PIR→灯规则开关、目标灯 `deviceId` 及触发亮度；
- 温度联动：可选启用 SHT30→空调规则，并设置开启/关闭温度回差；
- 空调桥：UART1/2、TX/RX、波特率、ACK 超时、健康查询间隔、连续失败阈值和品牌。

门锁、灯光或空调 GPIO 保持 `-1` 时对应板载执行器不会启动。PIR 即使未配置板载灯光也可作为
独立 `Presence_01` 传感器上报；存在规则的目标 ID 既可保持默认 `Light_01`，也可改为已认证
外部灯（例如当前测试执行器 `StandardRgbLight_01`）。目标必须已注册且在线才会执行联动。门禁没有反馈输入
时返回非零 `ACTUATION_ACCEPTED_UNCONFIRMED`（继电器写入已接受、实体位置未确认），门禁
保持离线且 App 不会把它当作闭环成功；实际部署建议
始终连接门磁/位置反馈。GPIO 只能接
MOSFET、继电器、电机驱动器或隔离模块的控制输入，严禁直接驱动门锁线圈或大功率灯具。
SHT30 只有 CRC 正确的真实采样到达后才上线，连续三次采集失败会离线；空调只有
UART 握手、周期状态查询或业务命令返回有效完整状态后才上线。空调默认每 30 秒进行
一次低频健康查询，连续 3 次没有获得有效完整状态才转离线；两个值均可在 menuconfig
调整。恢复握手或状态查询第一次成功时立即恢复在线。

门磁反馈并非只在启动或命令期间读取：后台任务持续轮询，信号稳定达到配置的去抖时间后
更新 `Door_01`。因此人工开关门也会触发路由状态回调和 IoTDA 即时上报。ESP-IDF 的
`gpio_get_level` 对已配置 GPIO 没有独立硬件错误码；代码仍会对非 0/1 异常值连续计数并
转离线，正常情况下至少保证所有稳定位置变化都被上报。

PIR 驱动不直接修改灯：它先上报 `Presence_01` 的有人/无人状态，本地自动化引擎再生成
带规则 ID 和触发设备 ID 的内部命令，通过与 App/IoTDA 完全相同的设备路由执行。有人时
仅接管原本关闭的灯；已经由用户或场景开启的灯不会被覆盖。无人超时后仅关闭仍由本规则
拥有的灯。App、场景或云端对灯的有效命令会先释放规则所有权。可选温度规则同理：高温时
只开启原本关闭且在线的空调，低温时只关闭规则自己开启的空调，UART 完整 ACK 仍是成功
前提。设备事务 mutex 保证物理执行、状态提交和 ACK 顺序一致。

## 空调南向 UART 协议

空调红外/原生总线时序由独立下位机实现，本仓库只实现 ESP32 网关桥接，符合“单片机
代码不在这里”的边界。每帧为一行 UTF-8 JSON，以 `\n` 结束。ESP32 请求示例：

```json
{"version":"1.0","requestId":"req-123","target":"AC_01","brand":"GREE","action":"SET_TARGET_TEMPERATURE","value":25}
```

下位机在真实发射/执行完成后返回完整状态快照：

```json
{"version":"1.0","requestId":"req-123","target":"AC_01","resultCode":0,"message":"executed","state":{"power":true,"targetTemperature":25,"mode":"COOL"}}
```

启动及链路恢复时网关发送 `HANDSHAKE`，在线期间周期发送 `STATUS_QUERY`。这两个动作
都不得执行红外发射等有副作用的操作，只读取桥接器及空调的当前状态。ACK 必须版本、目标
和请求 ID 一致；成功 ACK 必须同时含
`power`、`targetTemperature`、`mode`。超时、请求 ID 不匹配、拒绝或状态缺失都不会修改
已确认业务状态，也不会向 App/云端伪报成功。负响应可用非零 `resultCode` 和 `message`
返回下位机失败原因。

周期查询帧示例（`requestId` 每次不同）：

```json
{"version":"1.0","requestId":"health-123456","target":"AC_01","brand":"GREE","action":"STATUS_QUERY","value":null}
```

下位机必须按上面的完整 ACK 格式返回实时状态；只返回“串口收到”或缓存的虚假状态不能
作为健康成功。`HANDSHAKE` 和 `STATUS_QUERY` 都必须幂等。

健康查询和 App/IoTDA 业务命令严格共用同一个南向事务 mutex，且路由层从 UART 请求到
内存状态提交都持有同一个 AC 状态 mutex，所以不会出现查询任务读走控制 ACK、两帧交错
或旧查询覆盖新命令。连续失败达到阈值时，`AC_01_Online` 变为 `false` 并触发 IoTDA
即时属性上报；恢复后的首个完整状态 ACK 将真实状态写回、恢复在线并再次触发上报。

当前 UART 契约是严格的请求/响应模式；下位机主动推送空调遥控器变化属于后续协议扩展，
本轮不启动常驻 UART 解析，避免主动帧与命令 ACK 争用同一接收流。下位机不应主动发送
帧；网关以周期 `STATUS_QUERY` 获取真实状态和链路存活性。若以后加入主动帧，必须增加
独立 UART 接收任务、帧分类和事务关联后才能启用，不能直接与当前请求/响应读取并行。

板上有两个 USB-C 接口：照片中丝印 `USB` 的接口连接 ESP32-S3 原生 USB，建议优先用于 ESP-IDF 下载；丝印 `UART` 的接口通过 USB 转串口，可用于下载和串口日志。如果原生 USB 未识别，改接 UART 口并在需要时按住 BOOT、短按 RESET 进入 Download Boot。

## BLE 配网使用流程

首次启动时，NVS 内没有 Wi-Fi 凭据，串口会输出类似：

```text
No stored Wi-Fi credentials found
Starting BLE provisioning as YaoCore-GW-A1B2C3 (Security1 + PoP)
BLE Wi-Fi provisioning service ready
```

手机端流程为：

1. 扫描名称前缀 `YaoCore-GW-` 或主 Service UUID；
2. 连接目标网关并读取 `proto-ver`；
3. 使用用户提供的 PoP 完成 Protocomm Security1 会话；
4. 通过加密的 `yaocore-id` 读取 `gatewayId`，作为入网后身份关联值；
5. 通过 `prov-scan` 获取 ESP32 周围的 2.4 GHz Wi-Fi；
6. 通过 `prov-config` 依次发送 `set_config`、`apply_config`；
7. 轮询 `get_status`，收到已连接和 IP 成功状态后等待 BLE 自动关闭；
8. App 优先探测返回 IP，只接受 HMAC 已认证且 `gatewayId` 与 BLE 安全会话完全一致的网关。

凭据验证失败时固件会清除本次无效配置并保持 BLE 配网服务，允许 App 重新输入。已经配网但路由器密码改变时，在固件正常运行后持续按住 BOOT 约 5 秒；看到串口提示后松开 BOOT，固件才会重启进入 BLE 配网。它只清除 ESP-IDF Wi-Fi 持久配置，不清除网关 HMAC、IoTDA 或设备配置。必须先松开再重启，因为 GPIO0 也是下载模式绑带脚；不要把“上电时按住 BOOT 进入下载模式”和“固件运行时长按 BOOT 恢复配网”混淆。

### BLE GATT 互操作契约

本工程没有定义私有的 SSID/密码 JSON 帧，而是严格采用 ESP-IDF 5.2 `wifi_provisioning` + `protocomm` 协议：

- 广播名：`YaoCore-GW-` 加 STA MAC 后 3 字节的 6 位大写十六进制；
- Transport：BLE GATT；
- Security：Security1（X25519 密钥交换、PoP 验证、AES-256-CTR）；
- Primary Service UUID：`7a6e0001-4d7b-4f67-9a21-6d13c52ae3b8`；
- `proto-ver` 明文返回 JSON，包含 `prov` 版本及 `yaocore` 2.0 能力；
- 其余业务端点必须在 Security1 会话建立后发送加密 protobuf 数据。

ESP-IDF 5.2 固定端点如下。客户端应优先读取每个 Characteristic 的 User Characteristic Description（描述符 UUID `0x2901`）来识别端点名称，不应只依赖 UUID 数值：

| 端点 | Characteristic UUID | 用途 |
|---|---|---|
| `prov-ctrl` | `7a6eff4f-4d7b-4f67-9a21-6d13c52ae3b8` | 配网状态机控制 |
| `prov-scan` | `7a6eff50-4d7b-4f67-9a21-6d13c52ae3b8` | AP 扫描请求和结果 |
| `prov-session` | `7a6eff51-4d7b-4f67-9a21-6d13c52ae3b8` | Security1 会话握手 |
| `prov-config` | `7a6eff52-4d7b-4f67-9a21-6d13c52ae3b8` | Wi-Fi 设置、应用和状态 |
| `proto-ver` | `7a6eff53-4d7b-4f67-9a21-6d13c52ae3b8` | 明文协议版本/能力查询 |
| `yaocore-id` | 动态分配（当前注册顺序通常从 `...ff54...` 起） | Security1 内读取网关 ID/名称；客户端必须按 `0x2901` 映射 |

`yaocore-id` 必须在 Wi-Fi 凭据提交前调用；请求和响应契约见
`protocol/ble-enrollment-identity-*.schema.json`。它只返回非秘密身份字段，不返回 PoP、
命令 HMAC 密钥或云端凭据。

BLE 特征值本身不增加 YaoCore 自定义帧头或 JSON 包装：请求是对应 protobuf 的序列化字节（安全会话建立后，配置/扫描请求为 Protocomm 加密后的字节），写入端点 Characteristic；响应从同一 Characteristic 读取。客户端必须协商 MTU，并支持 GATT 长写/Prepare Write、带 offset 的长读，不能假定所有 protobuf 都能放进单个 20 字节 ATT 数据包。

手机端生成代码或手工实现时，协议定义以当前 ESP-IDF 安装目录为准：

```text
$IDF_PATH/components/protocomm/proto/constants.proto
$IDF_PATH/components/protocomm/proto/sec1.proto
$IDF_PATH/components/protocomm/proto/session.proto
$IDF_PATH/components/wifi_provisioning/proto/wifi_constants.proto
$IDF_PATH/components/wifi_provisioning/proto/wifi_config.proto
$IDF_PATH/components/wifi_provisioning/proto/wifi_scan.proto
$IDF_PATH/components/wifi_provisioning/proto/wifi_ctrl.proto
```

`prov-session` 的 `SessionData/Sec1Payload` 完成两阶段握手：客户端发送 32 字节 X25519 公钥的 `Session_Command0`；设备返回 32 字节设备公钥和 16 字节随机数的 `Session_Response0`；双方以 X25519 shared secret XOR SHA-256(PoP) 得到 32 字节会话密钥。随后客户端用该随机数作为 AES-256-CTR nonce 加密设备公钥并发送 `Session_Command1`，设备验证后以同一条连续 CTR 流加密客户端公钥返回 `Session_Response1`。握手后的请求和响应继续消费同一会话 CTR 流，不能为每个 GATT 消息重新初始化计数器。

`prov-scan` 使用 `WiFiScanPayload`；`prov-config` 使用 `WiFiConfigPayload`，顺序是 `TypeCmdSetConfig` → `TypeCmdApplyConfig` → `TypeCmdGetStatus`。HarmonyOS 可以用 BLE GATT、X25519/AES-CTR 和 protobuf 直接实现，但普通 BLE 写字符串接口不能与该固件互通。开发阶段可先用 Espressif 官方 provisioning App（连接时传入扫描结果中的主 Service UUID）或 `$IDF_PATH/tools/esp_prov` 验证网关端，再联调 HarmonyOS 客户端。

## 局域网接口

HTTP 和 UDP 默认都使用端口号 9200（分别属于 TCP/UDP，不冲突）。UDP 请求包含
`YAOCORE_DISCOVER` 时只返回 `protocolVersion`、网关 ID/名称、serviceId 和 HTTP 端口，
不包含设备列表或任何状态。局域网 HTTP 使用 HMAC 保证命令身份、完整性和防重放；
正式网络如要求抵抗被动抓包并保护内容机密性，仍须启用 ESP HTTPS Server，并在 App
固定网关证书——消息 HMAC 不能替代 TLS 加密。

UDP 返回值只用于发现候选地址，不能直接建立信任。App 随后的 `GET /discover` 必须携带
32 位小写十六进制 `X-YaoCore-Challenge`；缺失、长度错误、含大写或非十六进制字符都会
返回 HTTP 400。请求还必须携带 16 位紧凑 UTC `X-YaoCore-Request-Timestamp`、32 位小写
十六进制随机 `X-YaoCore-Request-Nonce`、`X-YaoCore-Request-Alg: HMAC-SHA256`、
`X-YaoCore-Key-Id: app-key-v1` 和 `X-YaoCore-Request-Sign`。请求 canonical 为
`YAOCORE-DISCOVER-V2\n<challenge>\n<timestamp>\n<nonce>\nHMAC-SHA256\napp-key-v1`；
缺少认证头返回 401，常量时间验签、±120 秒新鲜度或 nonce 防重放任一失败返回 403，认证
nonce 在 RAM 中保留 300 秒，只有全部通过后才生成完整设备快照。发现响应和所有已解析控制 ACK 均包含
`X-YaoCore-Response-Alg`、`X-YaoCore-Key-Id`、
`X-YaoCore-Response-Correlation`、`X-YaoCore-Response-Sign`。签名严格绑定响应正文
SHA-256、响应类型及 challenge 或 `request_id:seq`；无法生成签名时只返回 500，绝不发送
未签名的 2xx。浏览器直接打开 `/discover` 因没有 challenge 而返回 400 属于预期行为。

局域网服务在 DHCP 获得 IP 后立即启动，不依赖公网 SNTP。冷启动且系统时钟无效时，
网关先验证完整 canonical HMAC；只有签名正确、UTC 位于 2024～2100 合理范围且严格晚于
NVS 中 `last_auth_epoch` 的 App 命令，才能通过 `settimeofday` 引导本机时间。命令执行并
写入幂等缓存后，最大认证时间会提交到 NVS；因此断电重启后，旧抓包即使 HMAC 正确也会
被持久化时间水位拒绝。正常时钟有效时仍执行 ±120 秒新鲜度检查和 300 秒 RAM Nonce
防重放，同一精确重试只返回缓存 ACK、不重复驱动硬件。

该离线校时机制把“持有 App/网关 HMAC 密钥的手机时间”作为首次信任来源：手机时间若被
人为调到很远的未来，会导致后续命令在时间追平前被回滚保护拒绝。正式部署应保护手机和
网关密钥、开启自动时间，并优先让 SNTP 完成；IoTDA 始终等待 SNTP 成功后才启动，绝不
使用未经公网校验的时间派生云端凭据。若 NVS 读取/提交失败，固件将停止接受新的控制命令，
避免在失去跨重启防重放保护时降级运行。

固件不会在 NVS 空间/版本异常时自动执行整区擦除，因为那会同时删除重放水位。需要真正
恢复出厂时，必须在受控现场使用 `idf.py erase-flash`，随后重新烧录、BLE 配网并更换
PoP/HMAC/IoTDA 凭据；运行中的 BOOT 长按只清 Wi-Fi，不会删除安全水位。

## 外部设备模块

第三方 Wi-Fi 传感器和执行器不需要写入本板的 GPIO 驱动，可通过带逐模块派生密钥、时间戳、nonce 和 HMAC 的南向协议动态注册。网关会对模块进行心跳离线检测，将传感器事件放入异步自动化队列，并只在模块返回真实最终状态 ACK 后更新 App/云端。接口、状态模型和参考报文见 [`docs/EXTERNAL_MODULE_PROTOCOL.md`](../../docs/EXTERNAL_MODULE_PROTOCOL.md)。

## IoTDA Topic

- 下行命令：`$oc/devices/{device_id}/sys/commands/#`
- 命令响应：`$oc/devices/{device_id}/sys/commands/response/request_id={request_id}`
- 属性上报：`$oc/devices/{device_id}/sys/properties/report`

产品模型使用仓库 `cloud/iotda/product-profile.json`。App、产品模型和固件的设备 ID/属性名必须保持一致。

每次属性报告都包含 `Door_01_Online`、`Light_01_Online`、`Sensor_01_Online`、
`Presence_01_Online`、`AC_01_Online`；离线设备不上传容易误解的测量值。联网时每 30 秒完整报告一次，任何
本地自动化、传感器、局域网控制或云命令导致的状态变化都会唤醒上报任务。`Gateway_RSSI`
来自当前 Wi-Fi AP 记录；驱动查询异常时明确上报 `-127` 并记录警告，不使用固定演示值，
也不会遗漏产品模型要求的必填字段。

门、灯和空调每次成功命令还会保存精确的 `request_id`/`seq`。局域网状态输出
`lastRequestId`/`lastSeq`，IoTDA 分别输出 `{Door|Light|AC}_01_LastRequestId/LastSeq`；
字段仅在至少一次真实成功命令后出现，供 App 将影子状态与本次命令严格关联，避免把旧的
同值状态误判为本次执行确认。自动化命令使用独立 `auto:` 请求号；此外
`stateSource`/`triggerDeviceId`/`automationId` 明确记录最新状态的产生来源。

## 实物验收（提交前必须完成）

驱动代码不会替代接线和真机验收。按实际模块填写 menuconfig 后，至少记录以下证据：

1. 调光命令对应示波器/逻辑分析仪占空比 0%、25%、50%、100%；
2. SHT30 加热/加湿时数据真实变化，断开传感器后三次失败转为离线；
3. PIR 断网状态下仍可开灯并超时关灯，手动控制优先级正确；
4. 门禁反馈不一致时 App 和云端均收到失败，状态不伪更新；
5. 空调下位机启动在线后断电，达到健康检查连续失败阈值时自动离线并即时上报；重新上电
   后无需 App 发命令，首次恢复握手/状态查询完整 ACK 即自动上线并上报；
6. 同一动作分别通过局域网和 IoTDA 下发，设备只执行一次且状态双向同步；
7. 抓包确认云连接只使用 MQTTS，Wi-Fi RSSI 与路由器现场强度一致。
