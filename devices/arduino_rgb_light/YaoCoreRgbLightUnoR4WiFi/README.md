# YaoCore UNO R4 WiFi RGB 参考灯具

该程序把 Arduino UNO R4 WiFi 作为真实受控执行器参考实现，不代表 YaoCore 定义了一套面向所有品牌的统一灯具配网方式。开发网络写入私有 `config.h`，App 不负责配置这块板；RA4M1 直接产生三路 PWM 驱动 RGB 灯。

```text
App / 云端 / 本地自动化
        ↓
ESP32-S3M YaoCore 家庭网关
        ↓ 带 HMAC-SHA256 认证的设备命令
UNO R4 WiFi 测试执行器
        ↓
RGB 实体灯

PWM 最终状态 ACK → 家庭网关 → App / 云端
```

App 不能直接配置或控制 UNO R4 WiFi。测试灯只接受家庭网关签名的命令，控制结果也只通过家庭网关上报。正式多品牌产品应由品牌自己的配网体系、网关适配器或 Matter 等标准完成接入。

## 硬件与接线

默认使用共阴极小功率 RGB LED，每个颜色通道必须串联一个 220–330 Ω 电阻：

| UNO R4 WiFi | RGB LED |
|---|---|
| D3 PWM | 电阻 → 红色引脚 |
| D5 PWM | 电阻 → 绿色引脚 |
| D6 PWM | 电阻 → 蓝色引脚 |
| GND | 公共阴极 |

270° 三线旋钮（电位器）接线：

| UNO R4 WiFi | MAKEROBOT 旋钮 |
|---|---|
| 5V | VCC |
| GND | GND |
| A1 | OUT |

旋钮连续映射到 0–359° 色相。固件会压缩两端的小段电气死区，并在用户完成一次大范围旋转后自动学习该旋钮的真实 ADC 最小值和最大值，因此 270° 机械行程可以覆盖完整色相环。R4 在本地立即更新 PWM，并将颜色变化经网关上报；App 订阅到网关最终状态后会同步更新颜色滑块。A1 为 5 V 模拟输入场景，不能把该旋钮的 5 V OUT 接到 ESP32 等只允许 3.3 V 的引脚。若更换旋钮模块，可在 `config.h` 中调整 `YAOCORE_COLOR_KNOB_ADC_MIN/MAX` 初始死区。

手机和旋钮采用软接管仲裁：每条 App 命令执行后，手机拥有约 650 ms 的短期控制权；旋钮在此期间只更新采样基准，不改变灯光。租期结束后，旋钮必须在 300 ms 内连续转动累计至少 6° 才能接管，零星 ADC 噪声不会把 App 关闭的灯重新打开。旋钮成功接管时会恢复上次非零亮度并开灯，其最终状态通过网关回写 App。下一条 App 命令会再次取得控制权。

共阳极 LED 的公共端接 5 V，并将 `YAOCORE_COMMON_ANODE` 改成 `1`。灯带或大功率灯不能由 GPIO 直接供电，必须增加逻辑电平 MOSFET、独立电源并与开发板共地。

## 配置

复制 `config.example.h` 为 `config.h`，填写：

- 开发环境使用的 2.4 GHz Wi-Fi 名称和密码；
- 期望连接的网关 ID（网关地址由 UDP 自动发现，不能写死 IP）；
- 全局唯一且稳定的模块 ID 与设备 ID；
- 为该模块派生的 32 字节密钥。

在仓库根目录派生模块密钥：

```powershell
python tools/derive_module_key.py module.standard.rgb.01
```

输入网关当前的 `command_secret`，将输出的 64 位十六进制值写入 `YAOCORE_MODULE_KEY_HEX`。不要把网关主控制密钥直接写入灯具。`config.h` 已被仓库 `.gitignore` 排除。

每增加一块 UNO R4 WiFi，都必须使用不同的 `YAOCORE_MODULE_ID` 和 `YAOCORE_DEVICE_ID`，并重新派生对应模块密钥，否则网关会拒绝重复身份或防重放序号。

## 编译与烧录

依赖：

- Arduino Renesas UNO Boards 1.6.0 或兼容版本；
- ArduinoJson 7；
- ArduinoHttpClient；
- Crypto（Rhys Weatherley）。

Arduino IDE 中选择 `Arduino UNO R4 WiFi` 和对应串口后上传。也可以使用：

```powershell
arduino-cli compile --fqbn arduino:renesas_uno:unor4wifi devices/arduino_rgb_light/YaoCoreRgbLightUnoR4WiFi
arduino-cli upload -p COM端口 --fqbn arduino:renesas_uno:unor4wifi devices/arduino_rgb_light/YaoCoreRgbLightUnoR4WiFi
```

当前程序支持：

- `ON`、`OFF`；
- `SET_BRIGHTNESS`，范围 0–100；
- `SET_COLOR`，格式 `#RRGGBB`；
- 启动注册、5 秒心跳、断线重连；
- 真实 PWM 应用后的完整状态 ACK；
- 签名 UDP 心跳与主动状态上报，避免 WiFiS3 的单通道 HTTP 阻塞控制；
- A1 物理旋钮连续调色，并经网关同步回 App；
- 模块独立 HMAC 密钥、UTC 时间窗、随机 nonce、防重放缓存；
- EEPROM 单调序号分块预留，降低断电后序号回退风险。

网关下发命令与 R4 的物理状态 ACK 继续使用可靠 TCP；周期心跳和旋钮主动状态使用带 HMAC、时间戳、nonce、序号及网关签名 ACK 的 UDP。连续三次未收到有效 UDP ACK 时，R4 会保留设备身份并重新注册。该拆分用于避免周期心跳占用 WiFiS3 通道造成约数秒的控制卡顿，并不降低命令执行确认的可靠性。

## 验证边界

当前“真实状态”指 RA4M1 已更新实际 PWM 输出，而不是仅在 App 中模拟成功。它不能检测 LED 损坏、限流电阻断路或实际光色偏差。若产品要求闭环检测灯是否真正发光，应增加电流检测或颜色/光照传感器，并把传感器检测结果加入 ACK。
