# 测试证书与私钥（PUBLIC TEST DATA ONLY）

- **Producer**: agent:test-engineer
- **Task**: T-05 / TEST-001（`wp-010-test-plan`）
- **用途**: 仅用于 `tools/simulator --tls` 的 localhost 自签名 HTTPS 启动与 SPKI pin 工程测试。

## 文件

| 文件 | 内容 |
|---|---|
| `dev-test-cert.pem` | 自签名 X.509 证书，CN=localhost，SAN `DNS:localhost, IP:127.0.0.1` |
| `dev-test-key.pem` | 对应 RSA-2048 私钥，无口令 |

## 纪律

1. **不是秘密**：这是公开测试材料，可随仓库分发；不得用于真实网关、真实 IoTDA、生产 HAP 或任何真实用户数据。
2. **不复用**：禁止把该证书/私钥复制到 `entry/src/main/resources`、签名配置或发布包。
3. **可轮换**：若测试材料被误用，直接重新生成并更新本 README 与测试计划中的 SPKI 值。
4. **SC-02 例外**：T-05 明确要求仓库内提供仅测试用自签名证书/密钥；该例外仅限本目录，并已在本文件与 TEST-001 中登记。

## SPKI-SHA256（`sha256-spki-der`，64 位小写 hex）

```text
63f928c4c645b242ffb2a90a624258035e2a5ffb515756e0fb2f88113afa3243
```

复算：

```bash
openssl x509 -in tools/simulator/certs/dev-test-cert.pem -pubkey -noout \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256
```
