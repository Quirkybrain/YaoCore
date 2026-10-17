# 协议契约交叉检查（tools/contract）

- **Producer**: agent:test-engineer
- **Task**: T-05 / TEST-001（`wp-010-test-plan`）
- **Origin**: `artifacts/10-verification/fixtures/crosscheck_protocol_assets.py`
  - pinned SHA-256：`eeaf8f884d6d61e71afd4d93110ea4dbaebc226bfc27351813876a3605ab3530`
- **性质**: Python 标准库 DEV-only 检查器；不进入 App 构建。

## 1. 作用

独立复算 `input/api/protocol/` 的全部公开测试向量与 schema 约束，并交叉检查：

- A：schema 清单与 draft 2020-12；
- B：4 条控制请求 HMAC 向量（canonical、sign、request key 集合）；
- C：响应验签 / 发现请求签名向量；
- D：模块 HMAC 派生向量；
- E：canonical 字段 ↔ `local-control-request.schema.json`；
- F：C-001 字段命名证据（schema / 仿真器实跑 / API 规范示例）；
- G：API 规范结果码表 ↔ 仿真器常量（记录 FINDING，不硬失败）；
- H：BLE 身份 schema 约束；
- I：归档原 App 解析器字段优先级。

## 2. 运行

```bash
export PYTHONDONTWRITEBYTECODE=1
python3 tools/contract/crosscheck_protocol_assets.py
```

当前结果（T-05）：

```text
hard checks: ALL PASS   # 66/66
findings about frozen inputs: 14
exit code: 0
```

- 硬检查 66 项全部 PASS；任何 FAIL 都会返回退出码 1。
- 14 项 `FINDING` 是对**冻结输入**的观测（API 散文示例违反 schema、result_code 编号冲突等），
  不是本检查器失败，也不在本任务中擅自裁定；证据与处置见
  `artifacts/10-verification/wp-002-protocol-fixture-validation.md` §4/§6。

完整运行日志：`tools/contract/evidence/run-crosscheck.txt`。

## 3. 证据文件

`evidence/` 中的 golden 实跑捕获来自 wp-002（`artifacts/10-verification/fixtures/evidence/`），
用于 F.7–F.14 的 live-capture 检查：

| 文件 | 来源 SHA-256（wp-002 pin） |
|---|---|
| `discover-response.json` | `31f515d50b747625737a0cefb00624453eb0f3931ec59ceefc15a260b8f3ba5a` |
| `control-ack.json` | `3593af0d13641c842818c8d15ff7a537ef900f99275b722a643879bcca21b235` |
| `health.json` / replay / bad-sign 捕获 | 同目录，wp-002 证据副本 |

这些文件是 **PUBLIC TEST DATA ONLY**，不含真实秘密。

## 4. 适配差异

| 项 | wp-002 副本 | 本目录 |
|---|---|---|
| 仓库根 | `parents[3]` | `parents[2]` |
| 协议目录 | `input/api/protocol` | 不变（仓库根相对） |
| 仿真器模块 | `fixtures/tools/` | `tools/simulator/` |
| 证据目录 | `fixtures/evidence/` | `tools/contract/evidence/` |

检查逻辑未改；`G` 段仍以 FINDING 记录冻结输入的 result_code 冲突。

## 5. 限制

- 未引入 JSON Schema 校验器；schema 检查是结构性断言（与 wp-002 一致）。
- 不校验真实网关、真实 TLS/云、BLE 射频。
- `input/` 只读；本工具不修改冻结输入。
