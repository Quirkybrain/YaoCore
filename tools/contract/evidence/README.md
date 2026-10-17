# 契约检查证据（T-05）

- **Producer**: agent:test-engineer
- **`run-crosscheck.txt`**: `python3 tools/contract/crosscheck_protocol_assets.py` 的完整日志。
  - 硬检查：**66 PASS / 0 FAIL**；退出码 0。
  - 冻结输入 FINDING：14 项（API 散文示例 vs schema、result_code 冲突等），不是本工具失败。
- **golden 实跑捕获**: `discover-response.json`、`control-ack.json`、`control-ack-replay.json`、
  `control-ack-bad-sign*.json`、`health.json`，来自 wp-002 `artifacts/10-verification/fixtures/evidence/`；
  用于 crosscheck F.7–F.14 的 live-capture 检查。
- 所有内容均为 `PUBLIC TEST DATA ONLY`，不含真实秘密。
