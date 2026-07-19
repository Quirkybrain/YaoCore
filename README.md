# 爻构 YaoCore

> 爻联万物，构筑智慧。<br>
> Connecting Things, Building Intelligence.

爻构（YaoCore）是一个面向真实家庭环境的开源智能家居系统，由 HarmonyOS 应用、ESP32-S3 边缘网关、统一设备协议和可选云端链路组成。系统支持 BLE 配网、局域网优先控制、远程云端控制、设备状态同步、传感器自动化以及多品牌设备适配。

本项目坚持“真实状态、执行确认、离线可用”的设计原则：App 发出的命令只有在网关或云端返回有效确认后才会显示为成功；传感器触发的本地自动化也会同步到 App，而不是只在界面中模拟状态。

仓库默认配置不会虚构任何已接线设备。首次部署必须在 ESP-IDF `menuconfig` 中按实际电路设置门禁、灯光、SHT30、PIR、空调 UART 和 IoTDA；未配置的驱动不会注册为在线设备。格力、美的、海尔适配层负责统一命令和品牌路由，具体红外或厂商总线下位机仍需按实际型号实现并返回可验证 ACK。源码构建通过不能替代实物联调。

## 主要能力

- HarmonyOS 原生 App，提供首页、设备、场景和设置等完整操作流程
- ESP32-S3 网关，通过 BLE Security1/PoP 接收家庭 2.4 GHz Wi-Fi 配置
- mDNS、UDP 和受限同网段扫描发现局域网网关
- HMAC-SHA256 请求签名、随机数、时效窗口及防重放校验
- 局域网优先、云端兜底的控制路由
- 设备执行 ACK、状态回读和 App 实时同步
- 以 `(gatewayId, deviceId)` 隔离同品牌/同类型设备，并通过动态云影子清单同步状态
- PIR、温湿度等传感器驱动的网关本地自动化
- 灯光、门禁、窗帘、空调等设备类型的统一抽象
- 可扩展的品牌适配器与 UART/自定义驱动接口
- 外部模块注册、心跳离线检测、主动状态上报和物理状态 ACK；协议见 [外部模块接入指南](docs/EXTERNAL_MODULE_PROTOCOL.md)
- 可选华为云 IoTDA 命令下发、属性上报和设备影子同步

## 系统结构

```text
HarmonyOS App
   |-- BLE provisioning ----> ESP32-S3 Gateway
   |-- LAN signed control --> ESP32-S3 Gateway --> Sensors / Actuators
   `-- Cloud control -------> IoT platform -----> ESP32-S3 Gateway

Sensor event --> Gateway automation --> Device command
             `-> State report --------> App / Cloud
```

主要目录：

- `entry/`：HarmonyOS App 的页面、视图模型、服务和设备适配器
- `gateway/esp32s3m/`：基于 ESP-IDF 的 ESP32-S3 网关固件
- `devices/arduino_rgb_light/`：UNO R4 WiFi + RGB 灯真实闭环演示设备
- `protocol/`：App、网关和云端共用的 JSON Schema 与签名测试向量
- `cloud/iotda/`：可选的 IoTDA 产品模型
- `config/`：HarmonyOS/OpenHarmony 构建配置模板
- `tools/`：协议联调服务与自动化测试
- `docs/`：可公开的使用与技术文档

## 快速开始与使用教程

### 1. 获取源码并准备环境

```powershell
git clone https://github.com/Quirkybrain/YaoCore.git
cd YaoCore
```

建议准备：

- DevEco Studio 及 HarmonyOS SDK 6.0.2(22)；
- ESP-IDF 5.2.x；
- 可选 Arduino IDE 2 或 `arduino-cli`，用于 UNO R4 WiFi 参考灯具；
- 支持 BLE 的 HarmonyOS 手机、2.4 GHz Wi-Fi，以及 ESP32-S3M 网关。

仓库不包含任何真实设备凭据。先阅读[隐私与本地配置](docs/隐私与本地配置.md)，不要把下面生成的本地配置、证书或构建产物提交到 Git。

### 2. 配置并构建 App

复制公开模板作为本机构建配置：

```powershell
Copy-Item config/build-profile.harmonyos.template.json5 build-profile.json5
```

用 DevEco Studio 打开仓库，等待项目同步，选择 `entry` 模块，并在 `File > Project Structure > Signing Configs` 中配置自己的调试签名。连接手机后直接运行；也可以使用命令行构建：

```powershell
$env:DEVECO_SDK_HOME='<DevEco Studio>\sdk'
hvigorw --mode module -p module=entry@default -p product=default assembleHap --no-daemon
```

如果手机提示 `no signature file`，说明安装的是 unsigned HAP，应回到签名设置生成并安装 `entry-default-signed.hap`。

### 3. 配置并烧录 ESP32-S3M 网关

```powershell
cd gateway/esp32s3m
idf.py set-target esp32s3
idf.py menuconfig
```

在 `YaoCore Gateway` 菜单至少设置：

1. `BLE provisioning proof-of-possession`：每台网关独立的 PoP；
2. `App/gateway HMAC secret`：至少 16 字节的控制密钥；
3. 唯一网关 ID；
4. 按真实接线启用的传感器、执行器和 GPIO；
5. 如需远程控制，再启用并配置 IoTDA。

PoP 只用于 BLE 配网握手，控制密钥用于局域网命令和身份认证，两者不是同一个值。配置只写入本地 `sdkconfig`。

首次部署或需要彻底清除旧测试数据时执行：

```powershell
idf.py -p COMx erase-flash
idf.py -p COMx flash monitor
```

正常升级只需执行 `idf.py -p COMx flash monitor`。串口号按本机修改。无 Wi-Fi 凭据时，板载屏幕应显示 `BLE SETUP`、广播名和 PoP；联网成功后显示真实 IP、`ONLINE` 和 `LAN READY PORT 9200`。

### 4. 在 App 中添加网关

1. 首次启动完成滑动引导并创建本机用户资料；
2. 进入“设备”，先在“控制安全”中保存与网关一致的控制密钥；
3. 点击添加网关，允许蓝牙权限，选择屏幕对应的 `YaoCore-GW-*`；
4. 输入网关屏幕显示的 PoP；
5. 扫描并选择网关附近可用的 2.4 GHz Wi-Fi，输入 Wi-Fi 密码；
6. 等待 BLE Security1 配网完成；App 随后会在局域网验证同一个 `gatewayId` 和 HMAC 响应；
7. 首页顶部出现网关名称、局域网 IP 和延迟后，才表示绑定真正完成。

若只看到“Wi-Fi 配网已完成，但尚未通过局域网身份验证”，请确认手机与网关处于同一局域网，并等待网关屏幕显示 `LAN READY PORT 9200` 后点击继续绑定。不要把 `ONLINE` 的静态旧画面当作服务可达证明；必要时短按 RESET 并观察串口重连日志。

### 5. 可选：接入 UNO R4 WiFi RGB 参考灯具

回到仓库根目录，创建不会被 Git 跟踪的私有配置：

```powershell
Copy-Item devices/arduino_rgb_light/YaoCoreRgbLightUnoR4WiFi/config.example.h `
  devices/arduino_rgb_light/YaoCoreRgbLightUnoR4WiFi/config.h
python tools/derive_module_key.py module.standard.rgb.01
```

填写 2.4 GHz Wi-Fi、目标网关 ID、唯一模块/设备 ID 和派生模块密钥，然后编译烧录：

```powershell
arduino-cli compile --fqbn arduino:renesas_uno:unor4wifi devices/arduino_rgb_light/YaoCoreRgbLightUnoR4WiFi
arduino-cli upload -p COMx --fqbn arduino:renesas_uno:unor4wifi devices/arduino_rgb_light/YaoCoreRgbLightUnoR4WiFi
```

R4 会通过 UDP 自动发现网关并完成带 HMAC 的动态注册，不需要在 App 中配置灯具 Wi-Fi。注册成功后，灯具出现在设备列表；App 的开关、亮度和颜色命令必须经过网关，旋钮产生的颜色变化也会经网关回写 App。

### 6. 日常使用

- 首页查看网关连接方式、延迟、在线设备和最近反馈；
- 设备页进入不同类型的控制面板，只有收到真实 ACK 后才提交状态；
- 场景页组合多个设备动作；
- 传感器自动化在网关本地运行，断开手机或公网仍可执行；
- 异地控制需要配置 IoTDA，命令仍由家庭网关转发并以上报的最终状态为准；
- 删除网关只解除当前手机的绑定，不会擦除实体网关或其他手机。

更完整的界面说明和故障处理见 [YaoCore 用户使用手册](docs/YaoCore用户使用手册.md)。

## 工作流程

### 首次配网

1. ESP32-S3 网关在没有 Wi-Fi 配置时进入 BLE 配网模式。
2. App 搜索并选择附近的 `YaoCore-GW-*` 网关。
3. 用户选择 2.4 GHz Wi-Fi，输入密码和设备 PoP。
4. App 加密发送配置；网关联网后启动局域网服务和可选云连接。
5. App 验证网关身份并绑定，不以未认证设备冒充可用网关。

### 控制与状态同步

```text
App -> signed command -> Gateway -> physical device
App <- verified ACK + reported state <- Gateway
```

传感器自动化不依赖手机在线：传感器先上报网关，网关规则引擎执行设备命令，再将触发来源、规则和最终设备状态同步给 App 与云端。

## 构建

### HarmonyOS App

使用 DevEco Studio 打开项目，选择 `entry` 模块并配置本机签名后构建或运行。命令行示例：

```powershell
$env:DEVECO_SDK_HOME='<DevEco Studio SDK path>'
hvigorw --mode module -p module=entry@default -p product=default assembleHap --no-daemon
```

签名证书、HAP、构建目录和本地配置不会纳入版本控制。

### ESP32-S3 网关

固件基于 ESP-IDF 5.2.x。进入 `gateway/esp32s3m` 并执行：

```powershell
idf.py set-target esp32s3
idf.py build
idf.py -p COM5 flash monitor
```

串口号需要按实际设备修改。详细配置见 [网关说明](gateway/esp32s3m/README.md)。

## 测试

```powershell
python -m unittest discover -s tools -p "test_*.py" -v
```

协议联调服务仅用于开发测试，不能代替真实网关、外设和云端环境的测试。

## 安全提示

- 不要提交 Wi-Fi 密码、PoP、HMAC 密钥、云端 Token、设备证书或签名私钥。
- 正式部署时应为每个网关生成独立密钥，并启用密钥轮换和最小权限。
- 示例配置只用于开发；公网服务必须使用 TLS 并执行服务端鉴权。

## 兼容与扩展

设备能力通过统一模型与适配器暴露。新增品牌或协议时，应实现命令转换、执行确认和状态回读；只有成功写入且回读一致时才返回成功。协议定义位于 [`protocol/`](protocol/README.md)。

## 作者

- 开发者网名：Quirkybrain
- 作者及版权持有人：Zhang HaoXuan
- Email: 403723093@qq.com
- GitHub: [Quirkybrain/YaoCore](https://github.com/Quirkybrain/YaoCore)

## 许可证

Copyright © 2026 Zhang HaoXuan.

本项目采用 [Apache License 2.0](LICENSE) 开源。允许个人及商业使用、修改和闭源分发，但必须遵守许可证要求，保留版权、许可证及来源声明。第三方组件仍适用其各自的许可证。
