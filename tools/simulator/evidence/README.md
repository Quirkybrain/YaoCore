# 仿真器运行证据（T-05）

- **Producer**: agent:test-engineer
- **性质**: localhost DEV simulator 证据；**不是**真实网关/硬件证据。

| 文件 | 说明 |
|---|---|
| `http-server.log` | HTTP 模式启动横幅（`Listening on http://127.0.0.1:9200`） |
| `http-health.txt` / `http-discover.txt` | `curl -i` 捕获；HTTP 200 + `X-YaoCore-Simulator: DEV-ONLY` |
| `tls-server.log` | TLS 模式启动横幅 + `SPKI-SHA256: 63f9…3243` |
| `tls-health.txt` / `tls-discover.txt` | `curl -k -i https://127.0.0.1:9443/...`；HTTP 200 + DEV-ONLY |
| `tls-control-ack.json` | TLS 模式下签名 `POST /control` 的 ACK；`result_code:0`、`reported_state` |
| `run-test_gateway_contract.txt` | `python3 -m unittest tools.simulator.test_gateway_contract -v` 的 20/20 日志 |

## 复现要点

- 服务均以 `python3 -u` 启动，采集后**主动 kill**；因此进程退出码 143 是预期终止，不是测试失败。
- `curl` 必须加 `--noproxy '*'`，否则本机代理可能改写响应头（WP2-F05）。
- TLS 使用自签名测试证书；`curl -k` 仅用于 localhost。
- 证书/私钥是 `PUBLIC TEST DATA ONLY`，见 `../certs/README.md`。
