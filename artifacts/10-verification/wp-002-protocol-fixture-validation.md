# wp-002 协议夹具验证报告（Protocol Fixture Validation）

- **Producer**: agent:test-engineer
- **Task**: `wp-002-fixture-validation`（task 分支 `task/wp-002-fixture-validation`，父分支 `feat/yaocore-app`，base commit `927b616`）
- **Date**: 2026-10-16 / 2026-10-17（跨午夜会话）
- **Environment**: Linux / Python 3.12.3（仅标准库，未安装任何依赖）/ localhost HTTP
- **Inputs**: handoff `state/handoffs/wp-002-fixture-validation.json` 列出的 **26 项冻结输入**（guard pin/begin 已核对 SHA256）；本轮只读
- **Writes**: `artifacts/10-verification/`（`fixtures/` 适配副本 + `evidence/` 原始证据）
- **结论纪律**: 只记录可复现事实；"工具/环境问题"与"契约矛盾"分开标注；C-001 最终裁定属 wp-004，本报告只给证据与建议

---

## 0. 结论摘要

1. **协议数据面自洽性**：12 个 schema、4 份测试向量与 protocol README 的规则**全部可复算一致**（crosscheck 66/66 硬检查通过；两份独立实现——原工具与新增 crosscheck——相互印证）。
2. **可运行互操作证据**：仿真器实跑输出、17 项网关契约测试中可运行的 15 项、归档原 App 的线格式解析器，**一致使用 `online / power / open / targetTemp`**（schema 命名），不产生且不读取 `success`；人类可读规范示例的 `isOnline / powerStatus / success` 与 schema 不兼容（C-001 证据见 §4，建议非裁定）。
3. **套件矩阵**：gateway 15/17 通过（2 项因缺 `cloud/iotda/product-profile.json`）；app_response_auth 6/6；ble 向量 5/5（另 23 项因缺网关 C 源码/module.json5 未运行）；external_module 2/8（6 项同因）；crosscheck 66 硬检查全过、14 项发现。
4. **冻结输入间不一致 14 项**（§6）：核心为 ① API 规范示例自身违反 schema（发现级证据）；② `result_code` 数值语义冲突；③ BLE 身份端点 `serviceId/gatewayName` 三方冲突（schema + 归档 App 可执行证据 vs 规范示例）。
5. **环境注记**：本沙箱 `http_proxy` 使 urllib 对 localhost 的请求也经过代理（`no_proxy=127.0.0.0/8` 的 CIDR 语法不被 urllib 解析），代理会改写响应头大小写，导致 1 个用例在默认环境误报、`no_proxy='*'` 下通过（§3.3）。

---

## 1. 方法与环境

1. **静态审读**：4 个测试工具、仿真器 `gateway_contract_server.py`、`derive_module_key.py`、protocol README、12 个 schema、4 份向量、`Gateway_API_Specification.md`（250 行，全量），以及作为交叉证据的归档原 App（`input/existing/original_app/`）与 `input/existing/docs/EXTERNAL_MODULE_PROTOCOL.md`。
2. **适配副本**：6 个工具复制到 `artifacts/10-verification/fixtures/tools/`；仅改路径常量/前缀映射（§2 逐处记录）；协议数据**不复制**，由适配后的常量直接只读指向 `input/api/protocol/`（单一事实源）。
3. **运行验证**：仿真器以 CLI 形态在 `127.0.0.1:9200` 启动并实跑；4 个套件 + 1 个新增 crosscheck 逐一运行；全部命令输出保存到 `evidence/`。
4. **收尾**：每轮服务都用同一 shell 命令启动→采集→`kill`→`wait`；最终核验 `ss -tln` 无 9200/9201 监听、无遗留进程（`PORTS_FREE`）。所有 Python 运行均设 `PYTHONDONTWRITEBYTECODE=1`，未在被测目录产生 `__pycache__`。
5. **环境限制**：Python 3.12.3 / Linux；无 JSON Schema 校验器（未开发依赖安装）；沙箱 HTTP 代理见 §3.3。

---

## 2. 适配对照表

### 2.1 哈希保真

- `fixtures/tools/gateway_contract_server.py` = `80136a0c6cd6ca6be7c53c9370245e6e597536efae68ff42377a2a53fbd2c352`（与 handoff pin 完全一致，**字节级未修改**）
- `fixtures/tools/derive_module_key.py` = `7abe3c96fae8408ceefdd5c0aea4abe9fb20bf372ebe400627ed87e182fde892`（同上，**字节级未修改**）
- 适配后测试文件与 crosscheck 的哈希见 `evidence/fixture-sha256.txt`。
- 每处修改可用 `diff -u input/existing/tools/<file> artifacts/10-verification/fixtures/tools/<file>` 复现。

### 2.2 逐处适配（文件 / 原值 → 新值 / 理由）

| # | 文件 | 原常量/表达式 | 适配后 | 理由 |
|---|---|---|---|---|
| 1 | `gateway_contract_server.py` | （无路径常量） | 字节级复制，未修改 | 纯标准库实现，与仓库布局无关 |
| 2 | `derive_module_key.py` | （无路径常量） | 字节级复制，未修改 | 同上 |
| 3 | `test_gateway_contract.py` | `ROOT = parents[1]`；`PROTOCOL_DIR = ROOT/"protocol"`；`PROFILE_PATH = ROOT/"cloud"/"iotda"/"product-profile.json"` | `REPO_ROOT = parents[4]`；`PROTOCOL_DIR = REPO_ROOT/"input"/"api"/"protocol"`；`PROFILE_PATH` 保留 `REPO_ROOT/"cloud"/...`（本仓库不存在该文件） | 协议目录不同；profile 不在冻结输入中，保留原相对位置使失败理由可诊断 |
| 4 | `test_app_response_auth.py` | `ROOT = parents[1]`；`read()` 直接 `ROOT / relative` | `REPO_ROOT = parents[4]`；新增 `PROTOCOL_DIR`、`APP_ETS(=input/existing/original_app)`；`read()` 对 `protocol/`、`entry/src/main/ets/` 两个前缀做映射，其余保持 | 仓库无 `entry/`；归档原 App 快照是最接近的对应物；保留测试语义 |
| 5 | `test_ble_provisioning_contract.py` | `ROOT=parents[1]`；`GATEWAY=ROOT/"gateway"/"esp32s3m"`；`APP_ETS=ROOT/"entry"/"src"/"main"/"ets"`；`MANIFEST=ROOT/"entry"/"src"/"main"/"module.json5"`；`DESIGN=ROOT/"docs"/"BLE配网设计.md"`；另 4 处 `ROOT /` 引用（protocol schema ×2、ets service ×2） | `REPO_ROOT=parents[4]`；`APP_ETS=REPO_ROOT/"input"/"existing"/"original_app"`；`DESIGN=REPO_ROOT/"input"/"existing"/"docs"/"BLE配网设计.md"`；新增 `PROTOCOL_DIR=REPO_ROOT/"input"/"api"/"protocol"` 并替换 4 处引用；`GATEWAY`、`MANIFEST` 保留原布局路径（本仓库不存在） | 只重定向存在的资产；缺失资产保留原路径，使错误信息精确定位到原仓库布局 |
| 6 | `test_external_module_protocol.py` | `ROOT=parents[1]`；`MAIN=ROOT/"gateway"/"esp32s3m"/"main"`；`PROTOCOL=ROOT/"protocol"`；1 处 `ROOT / "devices"/"arduino_rgb_light"/...` | `REPO_ROOT=parents[4]`；`PROTOCOL=REPO_ROOT/"input"/"api"/"protocol"`；`MAIN` 与 `devices/` 引用保留原布局路径（均不存在）；`from derive_module_key import derive` 裸导入保持不变（以 `fixtures/tools` 为 cwd 运行） | 同上；裸导入在 cwd=tools 下可解析 |
| 7 | `crosscheck_protocol_assets.py` | — | **新增**（Producer: agent:test-engineer，非 input 复制） | 独立重算全部向量 + C-001/schema/规范/归档 App 交叉验证 |

> 适配文件头部均含 `Producer: agent:test-engineer` 与 wp-002 说明注释。修正记录：`test_external_module_protocol.py` 曾遗漏一处 `ROOT` 引用（第 98 行 `devices/...ino`），已改为 `REPO_ROOT` 并重跑该套件（结果不变，见 §3.2）。

---

## 3. 各套件运行结果

### 3.1 精确命令

以下均在仓库根目录 `/home/quirkybrain/code/harmony-projects/YaoCore` 下执行（`F=artifacts/10-verification/fixtures`）：

```bash
# 1) 仿真器（CLI 启动与终止；端口 9200）
cd $F/tools && python3 gateway_contract_server.py --host 127.0.0.1 --port 9200 --quiet &
#   → curl /health、/discover；用 fixtures 内 sign_packet 生成签名 POST /control（首跑/重放/篡改）；见 3.3
#   → kill + wait；ss -tln 核验 PORTS_FREE

# 2) 主契约套件（cwd=$F；tools 为命名空间包）
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tools.test_gateway_contract -v
PYTHONDONTWRITEBYTECODE=1 no_proxy='*' NO_PROXY='*' python3 -m unittest tools.test_gateway_contract -v   # 复跑

# 3) 响应验签（cwd=$F/tools）
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest test_app_response_auth -v

# 4) BLE 配网（cwd=$F/tools）
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest test_ble_provisioning_contract -v

# 5) 外部模块（cwd=$F/tools）
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest test_external_module_protocol -v

# 6) 新增交叉验证（cwd=$F）
PYTHONDONTWRITEBYTECODE=1 python3 crosscheck_protocol_assets.py
```

### 3.2 结果矩阵

| 套件 | Ran | PASS | FAIL | SKIP | ERROR | 未执行 | 日志 |
|---|---|---|---|---|---|---|---|
| `test_gateway_contract`（默认环境） | 17 | 14 | 0 | 0 | 3 | 0 | `evidence/run-test_gateway_contract.txt` |
| `test_gateway_contract`（`no_proxy='*'`） | 17 | **15** | 0 | 0 | 2 | 0 | `evidence/run-test_gateway_contract-noproxy.txt` |
| `test_app_response_auth` | 6 | **6** | 0 | 0 | 0 | 0 | `evidence/run-test_app_response_auth.txt` |
| `test_ble_provisioning_contract` | 5 | 5 | 0 | 0 | 2（类级） | 23 个方法 | `evidence/run-test_ble_provisioning_contract.txt` |
| `test_external_module_protocol` | 8 | 2 | 0 | 0 | 6 | 0 | `evidence/run-test_external_module_protocol.txt` |
| `crosscheck_protocol_assets.py` | 66 硬检查 | **66** | 0 | – | 0 | –（另记录 14 项 findings） | `evidence/run-crosscheck.txt` |
| 身份 schema 等价断言（独立复跑） | 5 | 5 | 0 | 0 | 0 | – | `evidence/run-identity-schema-assertions.txt` |

### 3.3 关键输出与失败分类

**A. `test_gateway_contract` — 15 项通过，2 项 ERROR：缺夹具（非契约问题）**

- `test_all_json_assets_are_valid` / `test_iotda_profile_contains_core_properties_and_commands`：
  `FileNotFoundError: .../YaoCore/cloud/iotda/product-profile.json` —— 该 IoTDA 产品模型文件**不在本仓库任何位置**（`find` 全仓库 0 命中），也不在 26 项冻结输入中。分类：**缺夹具/资产**（C-007 子项），非契约矛盾。
- 其余 15 项覆盖：schema draft/2020-12 与关键 const、HMAC 向量复算、整数/浮点规范化、nonce 缓存 TTL、ACK 丢失后精确重放跨时窗、发现/健康端点、控制回执、Unicode 值、坏签名/过期时间戳不消耗 nonce、精确重放缓存、同 nonce 改数据 409、未知 key、未支持命令不确认（含重放）、重复 JSON key 拒绝。全部稳定通过（重跑两次一致）。

**B. 默认环境 1 项额外 ERROR → 环境根因（已定因果链）**

`test_discover_and_health_are_explicitly_simulated` 在默认环境 `KeyError: 'X-YaoCore-Simulator'`。根因证据：

1. 线格式正确：`curl -sS -i http://127.0.0.1:9200/discover` 显示 `X-YaoCore-Simulator: DEV-ONLY`（服务器 `gateway_contract_server.py` L827 发送该头）。
2. 沙箱为 urllib 配置了代理：`http_proxy=http://127.0.0.1:7890/`，`no_proxy=localhost,127.0.0.0/8,::1`；urllib 的 `proxy_bypass_environment` **不支持 CIDR 记法**，`127.0.0.1` 因此未按 no_proxy 绕过，请求经代理转发。
3. 代理改写/规范化响应头：urllib 视角 `[('X-Yaocore-Simulator','DEV-ONLY')]`（每段首字母大写化）；`http.client` 直连与 `parse_headers` 均保留正确大小写。
4. `no_proxy='*'` 复跑 → 该用例 **ok**（15/17 通过）。
   分类：**本沙箱环境问题**，非工具缺陷、非契约矛盾。对移植的含义：TS/ArkTS 测试与该问题无关；未来若保留 Python 工具，头部断言应改为大小写不敏感或固定 `no_proxy='*'`。

**C. `test_app_response_auth` — 6/6 通过（对归档原 App 快照运行）**

覆盖：响应 canonical（`YAOCORE-RESPONSE-V1` + kind + correlation + body sha256，含 `\\n` 转义约定）、SecurityService 全量响应验证标记、发现请求签名（`YAOCORE-DISCOVER-V2`）、"认证先于 JSON 解析"顺序、ACK 的 `request_id:seq` 强关联与 `resultCode === 0` 判定（且显式断言不存在 `success` 旧逻辑）、`eventMs + 2000 >= notBeforeMs` 新鲜度与 `Door_01_Online/Light_01_Online/Sensor_01_Online/AC_01_Online` 属性名。**结论：归档原 App 与协议夹具在响应鉴权范围互操作一致。**

**D. `test_ble_provisioning_contract` — 向量 5/5 通过；2 个类因 setUpClass 缺资产而 ERROR**

- 通过：Security1 会话 step0 protobuf 向量（`10015a25…1e1f`）、Wi-Fi 扫描帧（`52080801100018002078`、`08026200`、`08047204…`）、负 RSSI int32 十字节 varint（`9cffffffffffffffff01`）、RFC7748 三元组（文档内）、最小 Wi-Fi 配置十六进制（文档内）。
- `BleGatewaySourceContractTests` setUpClass：`FileNotFoundError: gateway/esp32s3m/main/network_manager.c`；
  `HarmonyBleClientContractTests` setUpClass：`FileNotFoundError: gateway/esp32s3m/sdkconfig.defaults`。
  分类：**缺原仓库资产**（App 仓库按 `config/project.md` L50/L55 不含 ESP32 C 固件；`entry/src/main/module.json5` 也不在归档快照中）。因 setUpClass 层面失败，**23 个方法未执行**（该类 28 个方法中 5 个向量方法来自另一个类并已运行）。
- 被跳过的 `test_identity_contract_is_machine_readable_and_fail_closed` 其断言（op const、两个 `additionalProperties=false`、gatewayId maxLength/pattern）经**等价独立复跑 5/5 通过**（`evidence/run-identity-schema-assertions.txt`）；但原用例本身记录为"未运行"。

**E. `test_external_module_protocol` — 2/8 通过**

- 通过：6 个模块契约 JSON 均可解析；模块 HMAC 向量（派生密钥、body sha256、canonical 第 7 行 `app-key-v1`、签名）逐项一致。
- 6 项 ERROR 均为 `FileNotFoundError: gateway/esp32s3m/main/*.c`（local_server.c、external_module.c、device_router.c、automation_engine.c、cloud_iotda.c）或 `devices/…ino`。分类：缺原仓库固件/Arduino 资产，非契约矛盾。

**F. 仿真器实跑摘录（evidence/ 内）**

- `/health`：`{"simulator":true,"status":"DEV_SIMULATOR_ONLY",...}`。
- `/discover`：顶层仅 `protocolVersion/gatewayId/gatewayName/serviceId/generatedAt/security/devices`；`security:{alg,keyId:"app-key-v1",timeWindowSeconds:120,nonceTtlSeconds:300}`；设备字段 `online/power/open/targetTemp/...`（`evidence/discover-response.json`）。
- 签名 `POST /control`（Light_01, SET_BRIGHTNESS 42）：HTTP 200，`result_code:0`，`reported_state:{deviceId,online:true,power:true,brightness:42,updatedAt}`（`control-ack.json`）。
- 同包重发：HTTP 200 + `idempotent_replay:true`，其余字段与首次一致（`control-ack-replay.json`）。
- 同 nonce 改签名重放：HTTP **409** / `result_code 1005`（命中重放缓存冲突路径，符合 README L94-103：冲突检查先于签名校验）（`control-ack-bad-sign.json`）。
- 新 nonce 篡改签名：HTTP **401** / `result_code 1004`（`control-ack-bad-sign-401.json`）。

---

## 4. C-001 字段命名证据表与结论建议

### 4.1 证据对照表

| 证据来源（文件+行） | 设备状态字段 | 顶层/回执字段 | 说明 |
|---|---|---|---|
| `discover-response.schema.json` L74-81、L103-138 | required `online`；props `online/power/open/targetTemp`、`stateSource`、`updatedAt`；无 `isOnline/powerStatus` | top-level required `...generatedAt/security/devices`；`security.keyId` | **schema=线格式** |
| `local-control-ack.schema.json` L77-89、L115-119、L151-169 | deviceState required `deviceId/online/updatedAt`；`power/open/targetTemp`；gatewayState `gatewayId/online/boardLed/updatedAt` | `idempotent_replay` 为布尔；**无 `success`**；`additionalProperties:false` | 同上 |
| `gateway_contract_server.py` L417-461、L585-592、L626-633、L701-724；实跑证据 | 仿真器输出 `online/power/open/targetTemp` | ACK 无 `success`；`idempotent_replay` 仅重放时出现 | **可执行实现** |
| `Gateway_API_Specification.md` L88-121（discover 示例）、L187-204（ACK 示例） | `isOnline`（L102、L114）、`powerStatus`（L103、L198） | 顶层 `keyId`（L95，schema 中不存在）；ACK 含 `success:true`（L193）；reported_state 缺 `online` | **prose 示例**（自身违反 schema，见 §6 F-01） |
| 归档原 App：`LocalGatewayService.ets` L429-431、L440-441、L483-498 | ACK 解析**优先线格式** `online/power/open/targetTemp`，`isOnline/powerStatus` 仅作回退；发现校验要求 `security` 块含 `HMAC-SHA256`/`app-key-v1` | 读取 `reported_state`/`reportedState` | **可执行互操作证据** |
| 归档原 App：`NetworkService.ets` L539-546、`DeviceRepository.ets` L602-603 | **内部模型**字段为 `isOnline/powerStatus/openStatus/targetTemperature`，解析时从线格式映射 | — | 说明驼峰命名的真实归属是 App 内部模型 |
| 契约测试（15 项可运行通过项，如 `test_gateway_contract.py` L371-388） | 断言 `reported_state.power` 等线格式字段 | — | **测试锚定** |

补充事实（精确化 inventory C-001 措辞）：`Gateway_API_Specification.md` 文本中实际出现的驼峰词是 `isOnline`（L102/L114）、`powerStatus`（L103/L198）、`success`（L193）、`displayName`（L45）；**`openStatus/targetTemperature` 未出现在该规范文本中**，它们存在于归档 App 内部模型（`DeviceRepository.ets` L493-507 等）。

### 4.2 结论建议（非最终裁定）

- **可运行互操作闭环一致指向 schema 命名**：schema（两份）↔ 仿真器实跑输出 ↔ 可运行契约测试 ↔ 归档原 App 线格式解析器，四者全部使用 `online/power/open/targetTemp` 且一致拒绝/不产生 `success`；`test_app_response_auth` L107 甚至显式断言旧 `success` 逻辑不存在。
- **规范示例是最弱一环**：其 devise/ACK 示例不仅命名不同，还**自违反**对应 schema（附加 `keyId`/`success`、缺 `security/generatedAt/online`），且驼峰命名与归档 App **内部模型**词汇一致——推断为"内部模型词汇写入了线格式示例"的文档缺陷。
- **建议**（受理归 wp-004）：线格式字段名以 `discover-response.schema.json`、`local-control-ack.schema.json`、protocol README 与仿真器/契约测试为权威；人类规范示例按 schema 修订；App 内部模型若保留 `isOnline/powerStatus` 命名，仅属内部实现，不影响线格式互操作。

---

## 5. 测试向量 ↔ schema 一致性结论

| 向量文件 | 检查内容 | 结果 |
|---|---|---|
| `hmac-sha256-test-vectors.json` | 4 向量 canonical（独立实现复算）+ HMAC 签名 + `request.sign` + 请求键集合 == schema required | **全部一致**（crosscheck B 段 16/16） |
| 同上 ↔ `local-control-request.schema.json` | canonical 10 行 ⇔ schema required（去 `sign`；`payload`→`action/value`）；payload 恰为 `{action,value}`、action 必填、payload/请求均 closed | **完全覆盖**（crosscheck E.1-E.5） |
| `response-auth-test-vectors.json` | `bodySha256`、canonical（`\\n` 转义 → 实际 LF）、HMAC 签名 | **一致**（C 段 3/3） |
| `discovery-request-auth-test-vectors.json` | `YAOCORE-DISCOVER-V2` canonical + 签名 | **一致**（C 段 2/2） |
| `module-hmac-test-vector.json` | 派生密钥（`YAOCORE-MODULE-KEY-V1\n<moduleId>`）、body sha256、canonical（含 `HMAC-SHA256`、`app-key-v1` 两行）、签名 | **一致**（D 段 4/4；与 `EXTERNAL_MODULE_PROTOCOL.md` L52-63 相符） |

向量层面**未发现任何不一致**。另记录 schema 与仿真器校验边界差异（非向量问题，属仿真器宽松性）：
- `target`：schema `deviceIdentifier` ≤63 字符（`local-control-request.schema.json` L83）vs 仿真器 `IDENTIFIER_RE` ≤128（`gateway_contract_server.py` L58、L199）；
- `request_id`：schema ≤127 vs 仿真器 ≤128；
- `action`：schema ≤47 vs 仿真器 `ACTION_RE` ≤64（L59、L274）；
- `mode`：schema（discover L139-142 / ack L120-123）≤15 字符 vs 仿真器接受 ≤32（L687-693）且 `state-report.schema.json` L120-123 允许 32。
仿真器理论上可生成 schema 不接受的输出（边界值），建议在 wp-004/实现阶段对齐或明确宽容策略。

---

## 6. 其他发现（逐条含证据）

| ID | 发现 | 证据 | 分类/影响 |
|---|---|---|---|
| **WP2-F01** | API 规范的两个 JSON 示例与 schema 互不兼容：discover 示例顶层多 `keyId`、缺 `generatedAt/security`；设备项含 `isOnline/powerStatus`；ACK 示例多 `success`、reported_state 多 `deviceType/powerStatus`、缺必需的 `online` | crosscheck `run-crosscheck.txt` findings F.15/F.15b/F.16/F.17/F.18/F.18b；规范 L88-121、L187-204；schema 均 `additionalProperties:false` | 文档缺陷（发现级，已有可运行反证）；支持 C-001 建议方向 |
| **WP2-F02** | `result_code` 数值语义冲突：规范 L215-227 `1001 INVALID_SIGNATURE / 1002 EXPIRED_TIMESTAMP / 1003 MISSING_FIELD / 1004 UNKNOWN_DEVICE / 1006 UNSUPPORTED_ACTION / 1008 HARDWARE_TIMEOUT` vs 仿真器 `1001 INVALID_REQUEST / 1002 UNSUPPORTED_SECURITY / 1003 TIMESTAMP_REJECTED / 1004 BAD_SIGNATURE / 1006 UNSUPPORTED_COMMAND`；`0/1005/1007` 双方一致；`1008` 仿真器不存在 | crosscheck G 段；`gateway_contract_server.py` L50-56；`Gateway_API_Specification.md` L217-227 | 契约缺口：ack schema（L16-20）只约束 `result_code` 为 0..9999 整数，无枚举；两份冻结文档语义不兼容，**须 wp-004 裁定并统一** |
| **WP2-F03** | BLE 身份响应三方冲突：schema `serviceId` const `YaoCoreGateway` + `gatewayName`（`ble-enrollment-identity-response.schema.json` L12-25）vs 规范示例 `serviceId:"SmartHomeService"` + `displayName`（L44-45）vs README 措辞 "display name"（L37-41，未给键名） | **可执行证据**：归档原 App `BleProvisioningService.ets` L652-656 校验 `identity.serviceId !== 'YaoCoreGateway'` 即失败关闭，且只读 `gatewayId/gatewayName` —— schema 与归档 App 一致，规范示例为孤例 | 与 C-001 同族；建议同上（wp-004 裁定） |
| **WP2-F04** | `cloud/iotda/product-profile.json` 全仓库缺失（含冻结输入之外），直接阻塞 2 个网关套件用例；`state-report.schema.json` required 属性 ↔ profile 属性的子集校验因此无法执行 | §3.3-A；`git`/`find` 全仓 0 命中 | 资产缺口（C-007 子项）；建议在 wp-005 前提供或用既有 state-report schema 重建产品模型 |
| **WP2-F05** | 沙箱代理使 urllib 无法按 `no_proxy=127.0.0.0/8`（CIDR）绕过 localhost，经代理后响应头被改写（`X-YaoCore-Simulator`→`X-Yaocore-Simulator`），导致 1 用例默认环境误报；`no_proxy='*'` 即通过 | §3.3-B 因果链（curl -i / urllib / http.client / 复跑） | 环境问题；工具头部断言对大小写敏感属可移植性弱点（建议移植时改正或固定环境变量） |
| **WP2-F06** | schema 与仿真器校验边界不一致（target/request_id/action/mode 长度，见 §5 末） | §5 末尾表格 | 轻微不一致；实现期应对齐或明确宽容策略 |
| **WP2-F07** | `test_ble_provisioning_contract.py` 的身份 schema 用例因类级 setUpClass 依赖缺失的网关源码而整类 ERROR；本任务以等价断言独立复跑通过（5/5），但该用例本身记为"未运行" | §3.3-D；两份日志 | 覆盖限制（如实记录，不折算为 PASS） |

---

## 7. 移植计划（供 wp-005 规划）

### 7.1 建议保留在仓库工具层（Python，不进入 App 构建）

| 资产 | 形态 | 理由 |
|---|---|---|
| `gateway_contract_server.py` | `tools/simulator/`（DEV-only，含 pub test secret 标注） | App 仓库不能构建 ESP32 固件（`config/project.md` L50/L55）；仿真器是局域网契约的开发 Mock 与手工联调端点 |
| `crosscheck_protocol_assets.py`（本任务新增） | 契约层 CI 检查（Python 或由 wp-005 决策改 TS/ajv） | 在无硬件情况下持续保证 schema+向量自洽 |
| `derive_module_key.py` | 网关侧运维工具（保留但非 App 范围） | 模块密钥派生属网关↔模块协议，App 不参与 |

### 7.2 建议移植为 ArkTS / Hypium 测试（同一向量，App 侧执行）

| 目标测试 | 复用向量/夹具 | 形态 |
|---|---|---|
| 控制请求 canonical + HMAC 签名（含 `24` vs `24.0` 规范化） | `hmac-sha256-test-vectors.json` 全部 4 向量 | 纯函数单测 |
| 响应验签 canonical + HMAC | `response-auth-test-vectors.json` | 纯函数单测 |
| 发现请求签名 | `discovery-request-auth-test-vectors.json` | 纯函数单测 |
| BLE Security1 编解码 | `test_ble_provisioning_contract.py` L86-90/L110-112/L115 内的十六进制常量与 RFC7748 三元组 | 纯函数单测（常量移植） |
| ACK 解析与执行确认语义（`result_code==0`、`idempotent_replay`、1004/1005 错误路径） | `evidence/control-ack*.json` 实跑捕获 | golden fixture + DTO 单测 |
| 发现响应 DTO 映射（字段命名以 §4 裁定为准） | `evidence/discover-response.json` | golden fixture + DTO 单测 |
| 身份端点严格解析（`get_identity`、多字段即失败关闭） | 两个 ble-enrollment schema | DTO/校验单测 |
| 契约集成（可选）：Hypium 对仿真器进程或 TS mock 跑发现→控制→ACK 闭环 | 仿真器 + 上述夹具 | 集成测试 |

### 7.3 不建议/不可移植（超出本仓库范围或依赖缺失资产）

- 网关 C 源码断言（`BleGatewaySourceContractTests`、`test_external_module_protocol` 的 6 项源码契约、`test_esp32_gateway_source.py` 等）：本仓库无 `gateway/**`；属网关仓库回归。
- 依赖 `entry/src/main/module.json5` 的 `HarmonyBleClientContractTests`：改为针对重构后 App 真实源码重写断言（原断言针对旧实现字符串，参考价值在"期望清单"）。
- 旧实现的源字符串检查（`test_app_response_auth` 的静态部分）：重构后由 §7.2 的行为测试取代。
- UDP 发现、HTTPS/TLS、AES-256-GCM（C-002）路径：仿真器/协议 v2 均不含，等待 wp-004 范围裁定。

---

## 8. 覆盖限制与未运行项

1. **未运行（如实记录，不折算为 PASS）**：
   - `test_gateway_contract` 2 项（缺 `cloud/iotda/product-profile.json`）；
   - `test_ble_provisioning_contract` 23 个方法（2 个类 setUpClass 缺 `gateway/esp32s3m/**`、`module.json5`）；其身份 schema 用例的断言已独立复跑通过；
   - `test_external_module_protocol` 6 项（缺网关 C 源与 Arduino 源）。
2. **未覆盖路径**：UDP 发现（仿真器仅 HTTP）、HTTPS/TLS、AES-GCM 载荷（C-002）、真实网关/硬件、云端 IoTDA 实网、时序/性能指标。
3. **方法限制**：未引入 JSON Schema 校验器（避免重依赖），schema 检查为结构性断言；crosscheck 的"发现"是观测记录，不是裁定。
4. **环境限制**：Python 3.12.3 + 沙箱代理（§3.3-B）；结论仅对上述版本/哈希的冻结输入成立。
5. **仿真器自述**：`gateway_contract_server.py` L11-13 明确其为 DEV fixture，不构成硬件证据；本报告同样不主张任何硬件行为。

### 证据文件索引（`artifacts/10-verification/fixtures/evidence/`）

- 实跑捕获：`health.json`、`discover-response.json`、`control-request.json`、`control-ack.json`、`control-ack-replay.json`、`control-request-bad-sign.json`、`control-ack-bad-sign.json`（409/1005）、`control-request-fresh-bad-sign.json`、`control-ack-bad-sign-401.json`（401/1004）、`control-bad-sign-http-code.txt`、`control-bad-sign-401-http-code.txt`、`server-run.log`
- 套件日志：`run-test_gateway_contract.txt`、`run-test_gateway_contract-noproxy.txt`、`run-test_app_response_auth.txt`、`run-test_ble_provisioning_contract.txt`、`run-test_external_module_protocol.txt`、`run-crosscheck.txt`、`run-identity-schema-assertions.txt`
- 夹具哈希：`fixture-sha256.txt`
