# YaoCore 外部设备模块接入协议 v1

该协议把第三方 Wi-Fi 传感器/执行器模块接入 YaoCore 网关，使设备状态来自真实硬件，而不是 App 模拟值。它覆盖注册、心跳、异步状态上报、网关下行命令和执行后的真实状态 ACK。

## 闭环链路

```text
手机控制：App -> 网关 -> 模块 -> 实体设备
          App <- 已认证最终状态 <- 网关 <- 模块 ACK

本地自动化：传感器模块 -> 网关状态队列 -> 本地规则 -> 执行器模块
            App/云端 <- 最终状态与触发来源 <- 网关 <- 执行器 ACK

远程控制：异地 App -> IoTDA -> 家庭网关 -> 执行器模块
          异地 App <- IoTDA 影子 <- 网关 <- 模块最终状态
```

传感器规则在独立 FreeRTOS 队列中异步执行。即使传感器与执行器位于同一个单线程 HTTP 模块，模块上报请求也不会因为网关回调模块而互相等待。网络断开时，本地规则仍在网关执行。

## 身份、密钥与防重放

每个模块必须拥有稳定且唯一的 `moduleId`，每个设备必须拥有稳定且唯一的 `deviceId`。网关以 `(gatewayId, deviceId)` 作为家庭范围内的实体身份；名称、品牌和房间不是身份字段，因此可添加多个同品牌同型号设备。

正式部署应给每个网关设置独立 `command_secret`。每个模块使用派生密钥：

```text
moduleKey = HMAC-SHA256(
  gatewayMasterSecret,
  "YAOCORE-MODULE-KEY-V1\n" + moduleId
)
```

这样一个模块泄露后不能伪装成另一个 `moduleId`。模块密钥应在可信安装阶段写入模块的加密存储，不能通过普通 HTTP 返回，也不能提交到 Git。仓库的 `module-hmac-test-vector.json` 仅为公开测试数据。

可在开发电脑上交互式派生（主密钥使用隐藏输入，不进入命令历史）：

```powershell
python tools/derive_module_key.py module.vendor.livingroom.01
```

所有 HTTP 请求和响应都带这些请求头：

```text
X-YaoCore-Alg: HMAC-SHA256
X-YaoCore-Key-Id: app-key-v1
X-YaoCore-Module-Id: <moduleId>
X-YaoCore-Timestamp: yyyyMMddTHHmmssZ
X-YaoCore-Nonce: <64 lowercase hex>
X-YaoCore-Sign: <64 lowercase hex>
```

签名原文没有末尾换行：

```text
YAOCORE-MODULE-V1
kind
moduleId
timestamp
nonce
HMAC-SHA256
app-key-v1
sha256_lower_hex(exact_http_body_bytes)
```

`kind` 取 `register`、`state`、`heartbeat`、`command`、`command_ack` 或 `gateway_ack`。接收方校验时间窗口、HMAC 和 nonce；相同模块的 nonce 在 300 秒内不能重用。请求 JSON 必须先序列化，再对实际发送的 UTF-8 字节签名。

## 模块注册

模块启动或重新联网后向网关发送：

```http
POST http://<gateway-ip>:9200/module/v1/register
```

```json
{
  "protocolVersion": "1.0",
  "moduleId": "module.vendor.livingroom.01",
  "commandPort": 8080,
  "commandPath": "/yaocore/v1/command",
  "heartbeatSeconds": 20,
  "sequence": 100,
  "device": {
    "deviceId": "LivingLight_01",
    "name": "客厅主灯",
    "room": "客厅",
    "brand": "Vendor",
    "protocol": "vendor-http-v3",
    "deviceType": "light"
  },
  "state": { "online": true, "power": false, "brightness": 0, "color": "#FFFFFF" }
}
```

网关不会相信正文中的目标主机地址；下行命令地址始终绑定为注册 HTTP 连接的来源 IPv4，仅采用模块声明的端口和路径，避免把网关变成任意请求代理。同一 `deviceId` 不能被内部驱动或另一个模块重复注册。一个模块包含多个设备时，为每个设备发送一次注册，`moduleId` 保持相同。

## 心跳与主动状态上报

心跳发送至 `POST /module/v1/heartbeat`：

```json
{"protocolVersion":"1.0","moduleId":"module.vendor.livingroom.01","sequence":101}
```

状态变化立即发送至 `POST /module/v1/state`，不要等待 App 轮询：

```json
{
  "protocolVersion": "1.0",
  "moduleId": "module.vendor.sensor.01",
  "deviceId": "Presence_Living_01",
  "sequence": 302,
  "state": { "online": true, "presence": true }
}
```

`sequence` 必须在模块重启后仍保持单调递增，建议持久化高位计数器。网关拒绝旧序号；连续三个心跳周期未收到有效消息时，将该模块设备标记离线并同步到 App/云端。

## 网关下行命令和真实 ACK

模块必须在注册的 `commandPath` 接受网关命令：

```json
{
  "protocolVersion": "1.0",
  "requestId": "lan:1721220000000:42",
  "targetDevice": "LivingLight_01",
  "action": "SET_BRIGHTNESS",
  "value": 60,
  "source": "app.lan",
  "triggerDeviceId": "",
  "automationId": ""
}
```

模块应先驱动真实硬件，再读取硬件状态，最后返回 HTTP 200 和经过 `command_ack` 签名的正文：

```json
{
  "requestId": "lan:1721220000000:42",
  "resultCode": 0,
  "message": "physical state confirmed",
  "reportedState": { "online": true, "power": true, "brightness": 60, "color": "#FFFFFF" }
}
```

网关会同时校验响应签名、`moduleId`、`requestId`、`resultCode` 以及设备类型要求的完整状态。灯必须返回 `power+brightness`；注册时带 `color` 的 RGB 灯还可接收 `SET_COLOR`，并在 ACK 中返回大写 `#RRGGBB`。空调必须返回 `power+targetTemperature+mode`，风扇必须返回 `power+speed`，音箱必须返回 `power+volume`。未收到完整且已认证的最终状态时，App/云端命令均判定失败，网关不会乐观修改状态。

## 能力和动作

| deviceType | 必要状态 | 支持动作 |
|---|---|---|
| door | `open` | `OPEN`、`CLOSE` |
| light | `power`、`brightness`，RGB 灯另带 `color` | `ON`、`OFF`、`SET_BRIGHTNESS`、可选 `SET_COLOR` |
| sensor | `presence` 或 `temperature+humidity` | 只上报 |
| ac | `power`、`targetTemperature`、`mode` | `ON`、`OFF`、`SET_TARGET_TEMPERATURE`、`SET_MODE` |
| switch | `power` | `ON`、`OFF` |
| curtain | `position` | `OPEN`、`CLOSE`、`STOP`、`SET_POSITION` |
| fan | `power`、`speed` | `ON`、`OFF`、`SET_SPEED` |
| speaker | `power`、`volume` | `ON`、`OFF`、`SET_VOLUME` |

窗帘位置统一定义为 `0=完全关闭`、`100=完全打开`。网关拒绝与注册设备类型不相容的状态字段，也会核对 ACK 最终值是否与动作相符；例如请求亮度 60 却返回亮度 20 不能被判定为成功。

协议适配器负责把这些统一能力转换为厂商 Zigbee、Modbus、UART、RS-485、红外或私有无线协议。YaoCore 不会把“已发送厂商帧”当作成功；适配器必须获得实体设备回读或厂商确认。

## 当前自动化目标

任意已认证、带 `presence` 能力的传感器都可触发本地存在感应规则，默认目标为 `Light_01`，也可在 `menuconfig` 中把 `Presence automation target light deviceId` 改为外部灯的稳定 ID；任意带 `temperature+humidity` 能力的传感器都可触发温控规则，默认目标为 `AC_01`。目标既可以是板载直连驱动，也可以是注册的外部模块。规则开关、阈值和默认亮度在网关 `menuconfig` 中设置。

## 机器可读合同

- `protocol/module-register.schema.json`
- `protocol/module-state.schema.json`
- `protocol/module-heartbeat.schema.json`
- `protocol/module-command.schema.json`
- `protocol/module-command-ack.schema.json`
- `protocol/module-hmac-test-vector.json`

## 低延迟 UDP 遥测扩展

资源受限且只有单一网络协处理通道的模块，可以在完成一次 HTTP 注册后，把周期 `heartbeat` 和主动 `state` 改为 UDP 数据报。网关下发命令与执行器最终 ACK 仍使用可靠 TCP，不能改成无确认控制。

UDP 外层为紧凑 JSON：

```json
{
  "type": "YAOCORE_MODULE_EVENT",
  "kind": "state",
  "moduleId": "module.standard.rgb.01",
  "timestamp": "20260719T080000Z",
  "nonce": "<64 lowercase hex>",
  "signature": "<64 lowercase hex>",
  "body": "{\"protocolVersion\":\"1.0\",...}"
}
```

`body` 必须是实际签名的原始紧凑 JSON 字符串，签名继续使用 `YAOCORE-MODULE-V1` canonical form，`kind` 只能为 `state` 或 `heartbeat`。网关在验签、时间窗、nonce、模块身份和单调序号全部通过后才更新状态，并返回带 `gateway_ack` HMAC 的 `YAOCORE_MODULE_ACK`。模块连续三个心跳周期没有收到有效 ACK 时必须重新注册；不能因为 UDP `send` 返回成功就认为网关已经接受状态。

该扩展让旋钮和传感器及时上报而不占用模块接收下行命令的 TCP 通道。它不替代 HTTP 注册、TCP 控制和物理状态 ACK。

这些文件定义传输合同，但不能代替真实硬件联调。发布或部署前应至少用一个传感器模块和一个执行器模块完成三条链路的断网、重连、重复消息、错误 ACK 和云端回读测试。
