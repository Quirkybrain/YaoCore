# 测试夹具（tools/test-fixtures）

- **Producer**: agent:test-engineer
- **Task**: T-05 / TEST-001（`wp-010-test-plan`）
- **性质**: **PUBLIC TEST DATA ONLY**；不进入 App 构建，不含真实凭据。

## iotda/product-profile.json（P-15）

- **背景**：wp-002 发现 `cloud/iotda/product-profile.json` 全仓库缺失（WP2-F04），
  导致 `test_gateway_contract` 的 2 个用例 ERROR：
  - `test_all_json_assets_are_valid`
  - `test_iotda_profile_contains_core_properties_and_commands`
- **来源**：由 `input/api/protocol/state-report.schema.json` 反推，并对照
  `input/api/protocol/cloud-command.schema.json` 补齐 `SetDeviceStatus` 命令参数。
- **内容**：
  - 唯一 service `SmartHomeService`；
  - 属性 = `state-report.schema.json` 的 required + 全部 optional properties
    （含 `DeviceInventoryJson`、`Gateway_RSSI`、`*_LastRequestId/LastSeq/StateSource`、
    `Door_01_Status`、`Light_01_*`、`Room_01_*`、`AC_01_*`）；
  - 命令 `SetDeviceStatus`，`paras` 为 schema required 的 10 项 + `Value`
    （`Value` 为 string，`KeyId.enumList = ["app-key-v1"]`）。
- **验证**：`tools/simulator/test_gateway_contract.py` 的 20 项测试全部 PASS，
  其中此前 2 项 ERROR 已转为 PASS；`state-report` required 属性是 profile 属性的子集。
- **限制**：这是测试用最小产品模型，不声明与真实 IoTDA 产品模型/固件完全一致；
  缺少 `DeviceInventoryJson` 的固件 schema，PB-02 仍为 `FIRMWARE_PENDING`。

## 复现

```bash
export PYTHONDONTWRITEBYTECODE=1
no_proxy='*' NO_PROXY='*' python3 -m unittest tools.simulator.test_gateway_contract -v
```

## 纪律

- 禁止把真实家庭数据、Wi-Fi/PoP/HMAC/云 Token、生产证书放入本目录。
- 新增夹具时在文件内或本 README 记录来源路径、SHA-256、生成/复核命令。
