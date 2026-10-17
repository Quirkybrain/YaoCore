# ohosTest 契约 golden fixtures

- **Producer**: agent:test-engineer
- **Task**: T-05 / TEST-001（`wp-010-test-plan`）
- **用途**: 设备/模拟器 ohosTest（`onDeviceTest`）的协议 golden 夹具；host 侧 Node 骨架也复用同一份文件。
- **状态**: **BLOCKED** —— 当前环境无设备/模拟器、无签名，`onDeviceTest` 未运行；这些文件本身可编译/可解析。

## 文件与来源

| 文件 | 来源 | SHA-256 | 标注 |
|---|---|---|---|
| `hmac-sha256-test-vectors.json` | `input/api/protocol/` | `46b33cda37513ea7fdc088f31825bb097c3686ec8cfa4d70eed1c414c3b742c4` | PUBLIC TEST DATA ONLY |
| `response-auth-test-vectors.json` | `input/api/protocol/` | `b41aad4f1c92d6099696de1181eb7e5040403ebe4a8aebb37d5a544363dd93d0` | PUBLIC TEST DATA ONLY |
| `discovery-request-auth-test-vectors.json` | `input/api/protocol/` | `be24bdedfba3dc5aa0aaee088b0eb5768bc8e9d69858424f2c9064a3a461d1f8` | PUBLIC TEST DATA ONLY |
| `discover-response.json` | wp-002 实跑捕获（`artifacts/10-verification/fixtures/evidence/`） | `31f515d50b747625737a0cefb00624453eb0f3931ec59ceefc15a260b8f3ba5a` | PUBLIC TEST DATA ONLY |
| `control-ack.json` | wp-002 实跑捕获 | `3593af0d13641c842818c8d15ff7a537ef900f99275b722a643879bcca21b235` | PUBLIC TEST DATA ONLY |
| `control-ack-replay.json` | wp-002 实跑捕获（`idempotent_replay:true`） | `6ce7466c94d8002efa9a60dca3296760021272dee26bd550f82d9463852863ed` | PUBLIC TEST DATA ONLY |

## 覆盖点（计划；设备可用时执行）

1. 4 条控制 HMAC 向量：canonical + `sign` 逐项断言（T-07）。
2. 响应验签向量 + 发现请求签名向量（T-07）。
3. 发现 DTO 映射：顶层/设备字段命名以 schema 为准，禁止 `success`（T-06）。
4. ACK golden：`request_id`/`seq` correlation、`result_code==0`、`reported_state.online`、无 `success`、`idempotent_replay` 语义（T-06/T-11）。
5. 坏签名/重放/过期输入由测试内合成（不复制真实秘密）。

## 纪律

- 所有 secret 均为公开测试数据；不得替换为生产密钥。
- 不得修改 golden 文件来迁就实现；实现不一致时按 Change Impact / 失败诊断处理。
- 设备测试命令（BLOCKED）：
  ```bash
  hvigorw --mode module -p module=entry@ohosTest -p product=default onDeviceTest --no-daemon
  ```
  详见 `entry/src/ohosTest/ets/test/README.md`。
