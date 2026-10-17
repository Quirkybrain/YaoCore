# YaoCore DEV 网关契约仿真器（tools/simulator）

- **Producer**: agent:test-engineer
- **Task**: T-05 / TEST-001（`wp-010-test-plan`）
- **Origin**: `input/existing/tools/gateway_contract_server.py`
  - pinned SHA-256：`80136a0c6cd6ca6be7c53c9370245e6e597536efae68ff42377a2a53fbd2c352`
- **性质**: **DEV-ONLY 契约夹具**。不是 OpenHarmony 固件、不是 IoTDA 客户端、不是硬件驱动，也不是“物理网关可用”的证据。
- **测试数据**: 所有 secret、证书、私钥均为 **PUBLIC TEST DATA ONLY**，禁止用于任何真实设备/生产环境。

## 1. 与 wp-002 原夹具的差异

仅做以下最小改动；协议行为、canonical、nonce/replay、ACK 语义未改：

1. 新增 `--tls`、`--cert`、`--key`：同端口以 HTTPS 提供服务。
2. TLS 启动时打印证书 **SPKI-SHA256**（64 位小写 hex），用于与 ADR-002/CB 的 `sha256-spki-der` pin 对齐。
3. 增加 T-05 移植说明头；HTTP 响应头 `X-YaoCore-Simulator: DEV-ONLY` 保留。
4. 测试文件改为仓库相对路径，并新增 3 个 TLS 测试；原 17 个网关契约测试语义不变。

`--cert/--key` 与 `--tls` 必须成对出现；缺少任一参数时进程返回退出码 2，不启动服务。

## 2. 前置条件

| 项 | 要求 |
|---|---|
| Python | 3.10+（本机 3.12.3），仅标准库 |
| 工作目录 | 仓库根 `/home/quirkybrain/code/harmony-projects/YaoCore` |
| 网络 | 仅 localhost；无需外网 |
| 证书 | `tools/simulator/certs/dev-test-cert.pem` + `dev-test-key.pem`（已入库，仅测试） |

## 3. HTTP 模式

```bash
python3 tools/simulator/gateway_contract_server.py --host 127.0.0.1 --port 9200 --quiet
curl -sS -i http://127.0.0.1:9200/health
curl -sS -i http://127.0.0.1:9200/discover
```

预期：HTTP 200，响应头含 `X-YaoCore-Simulator: DEV-ONLY`，`/health` 返回
`{"simulator":true,...,"status":"DEV_SIMULATOR_ONLY"}`。

## 4. TLS 模式

```bash
python3 tools/simulator/gateway_contract_server.py \
  --host 127.0.0.1 --port 9443 --quiet \
  --tls --cert tools/simulator/certs/dev-test-cert.pem \
  --key tools/simulator/certs/dev-test-key.pem
```

启动输出包含：

```text
Listening on https://127.0.0.1:9443
SPKI-SHA256: 63f928c4c645b242ffb2a90a624258035e2a5ffb515756e0fb2f88113afa3243
TLS certificate/key are PUBLIC TEST DATA ONLY; never use in production.
```

自签名证书仅用于本地握手/pin 测试，客户端需显式跳过系统 CA 校验或信任该测试证书：

```bash
curl -sS -k -i https://127.0.0.1:9443/health
```

独立复算 SPKI（应与启动打印一致）：

```bash
openssl x509 -in tools/simulator/certs/dev-test-cert.pem -pubkey -noout \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256
```

当前证书 SPKI-SHA256：
`63f928c4c645b242ffb2a90a624258035e2a5ffb515756e0fb2f88113afa3243`

## 5. 证书/密钥（仅测试）

| 文件 | 用途 | 说明 |
|---|---|---|
| `certs/dev-test-cert.pem` | 自签名测试证书 | CN=localhost；SAN `DNS:localhost, IP:127.0.0.1`；3650 天 |
| `certs/dev-test-key.pem` | 对应私钥 | 无口令；**PUBLIC TEST DATA ONLY** |

生成命令（可复现）：

```bash
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout tools/simulator/certs/dev-test-key.pem \
  -out tools/simulator/certs/dev-test-cert.pem \
  -days 3650 -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=serverAuth"
```

> SC-02 通常禁止提交 `*.pem/*.key`。本目录是 T-05 明确授权的**测试专用例外**：
> 私钥只保护 localhost 自签名测试证书，不授予任何真实资产访问权；若该私钥被滥用，
> 唯一后果是能冒充本地测试仿真器。禁止把同一材料复用到真实网关/云端。

## 6. 测试

```bash
export PYTHONDONTWRITEBYTECODE=1
no_proxy='*' NO_PROXY='*' python3 -m unittest tools.simulator.test_gateway_contract -v
```

当前结果：**20/20 PASS**（原 17 项网关契约 + 3 项 TLS/SPKI）。

## 7. 已知限制

- TLS 模式只证明“自签名证书 + HMAC 协议在 localhost 可启动/响应”，**不证明**真实网关 TLS、
  证书链、pin 匹配流程或性能。
- 仿真器输出永远带 `DEV-ONLY`；生产客户端必须拒收（SC-11）。
- 本工具不进入 App 构建，不进入 HAP。
