# YaoCore UNO R4 WiFi RGB 测试灯

`YaoCoreRgbLightUnoR4WiFi` 是 YaoCore 实物联调使用的单板 RGB 灯执行器。它不是 App 内的模拟设备，也不是面向所有品牌的通用配网方案。

## 数据链路

```text
HarmonyOS App / 云端
  → ESP32-S3M 家庭网关
  → 已认证的 UNO R4 WiFi 灯具模块
  → RGB LED

App / 云端
  ← 网关验证后的真实状态
  ← R4 执行 ACK、旋钮状态上报
```

App 不直接连接 R4。R4 通过 DHCP 接入测试网络，使用 UDP 发现网关，并在完成模块 HMAC 注册后接受网关命令。网关地址变化时会自动重新发现。

## 配置

编译前复制配置模板：

```text
YaoCoreRgbLightUnoR4WiFi/config.example.h
→ YaoCoreRgbLightUnoR4WiFi/config.h
```

私有 `config.h` 保存测试 Wi-Fi、期望网关 ID、唯一 `moduleId`、`deviceId` 和独立模块密钥，不应提交到 Git。模块密钥可在仓库根目录生成：

```powershell
python tools/derive_module_key.py module.standard.rgb.01
```

## 接线

- RGB 红、绿、蓝通道默认连接 UNO R4 的 D3、D5、D6，每路必须串联限流电阻。
- 颜色旋钮 OUT 默认连接 A1，VCC 和 GND 分别连接 5V 与 GND。
- 更换电气类型不同的 RGB 灯时，在 `config.h` 中调整公共阳极/阴极配置。

旋钮映射到完整的 0–359° 色相。首次使用时将旋钮从一端完整转到另一端一次，固件会学习实际 ADC 范围。旋钮改变颜色后，R4 会经网关上报真实状态，App 收到状态后同步控制页面。

## 编译与烧录

```powershell
arduino-cli compile --fqbn arduino:renesas_uno:unor4wifi devices/arduino_rgb_light/YaoCoreRgbLightUnoR4WiFi
arduino-cli upload -p COM7 --fqbn arduino:renesas_uno:unor4wifi devices/arduino_rgb_light/YaoCoreRgbLightUnoR4WiFi
```

串口号按实际设备修改。详细配置、协议行为和故障排查见 [UNO R4 说明](YaoCoreRgbLightUnoR4WiFi/README.md)。
