# Host 单元测试（无设备）

- **Producer**: agent:test-engineer (baseline) / agent:implementation-engineer (T-06/T-07 and wp-018-fix-t07)
- **Task**: T-05 / TEST-001（`wp-010-test-plan`）；T-06 修复 `wp-014-fix-t06`；T-07 `wp-016-security` + 修复 `wp-018-fix-t07`
- **状态**: **可运行（Node host runner）**；`hvigorw test` 的 Hypium 入口可编译，但本环境无法执行（见 §3）。

## 1. 目录与约定

```text
entry/src/test/
├── List.test.ets                 # Hypium host 入口（hvigorw test 固定导入）
├── HostBaseline.test.ets         # Hypium 冒烟（仅编译，未执行）
├── run-host-tests.sh             # 可运行的 Node host runner
├── host/
│   ├── HostBaseline.test.mjs     # 基线断言
│   ├── HostProtocol.test.mjs     # 向量/golden/SPKI host 测试
│   ├── ProtocolDiscover.test.mjs # 发现 canonical/映射
│   ├── ProtocolControl.test.mjs  # 控制 canonical/序列化
│   ├── ProtocolAck.test.mjs      # ACK 判定链
│   ├── ProtocolCloud.test.mjs    # 云 canonical
│   ├── ProtocolIdentity.test.mjs # 身份/SPKI
│   ├── DomainModels.test.mjs     # 域模型
│   ├── Foundation.test.mjs       # 基础工具
│   ├── PerfHarness.test.mjs      # NFR 4.3 测量 harness
│   ├── Crypto.test.mjs           # T-07 C-04 host 测试（含 R-01 分类器/R-07 前缀副本）
│   ├── Security.test.mjs         # T-07 C-05 向量与负例
│   ├── TestCryptoProvider.ets    # 测试专用纯 TS provider（仅 SHA/HMAC/HKDF/PBKDF2）
│   ├── protocol-oracle.ets       # 纯 TS canonical oracle（无 @ohos）
│   ├── ets-hooks.mjs             # Node loader：.ets -> TS strip -> ESM
│   └── register-ets.mjs
├── foundation/                   # Hypium host 冒烟（仅编译）
├── protocol/                     # Hypium host 冒烟（仅编译）
├── security/
│   └── SecurityHost.test.ets     # T-07 C-04/C-05 Hypium 冒烟（仅编译）
└── evidence/                     # 运行日志（当前 revision 证据）
```

约定：

1. `entry/src/test/host/**` 的测试**不得** import `@ohos.*`、ArkUI 装饰器或 `struct`。
2. 纯逻辑产品模块应能在 host 加载；Node loader 支持 `.ets`/`.ts`（TypeScript 语法），但 UI/平台文件不可加载。
3. Hypium `List.test.ets` 只做 suite 聚合；每个 `*Suite` 导出同名函数（DES-A §23.1）。
4. 新增测试时同时保留 Requirement/Contract/component ID 注释（traceability）。

## 2. 可运行命令（推荐）

```bash
cd /home/quirkybrain/code/harmony-projects/YaoCore
entry/src/test/run-host-tests.sh
```

等价命令：

```bash
node --no-warnings \
  --import ./entry/src/test/host/register-ets.mjs \
  --test --test-reporter=tap \
  entry/src/test/host/*.test.mjs
```

当前 revision：**122/122 PASS**（`evidence/t07-fix-host-node-tests.tap`，wp-018-fix-t07 后）。覆盖：

- 4 条控制 HMAC 向量（canonical + HMAC-SHA256）与 T-06 出站 nonce/值类型严格门；
- 响应验签向量、发现请求签名向量；
- golden discover / ACK / replay 结构断言与 ACK 严格 schema 负例；
- `valueAtom` 语义；
- 测试证书 SPKI-SHA256 与 Python 仿真器 pin 一致；
- NFR 4.3 测量 harness（percentile/样本/报告分类）；
- T-07 C-04：SHA/HMAC/HKDF/PBKDF2 对照 Node/RFC 向量、X25519 DER↔raw 对照 Node JWK、常数时间行为、CTR 状态机、GCM 标签/长度负例、随机长度/不可用；
- T-07 C-04 R-01/R-07 修复：分层错误分类器（CREATE/KEY_CONVERSION/OPERATION/GCM tag）、X25519 前缀防御性副本；
- T-07 C-05：V-01 4/4、发现/响应向量、correlation/nonce/TTL/±120s 负例与 ACK 链组合；
- host runner 基线断言。

T-06 修复时基线为 **88/88 PASS**（`evidence/t06-fix-host-node-tests.tap`）；T-05 历史基线为 **15/15 PASS**（`evidence/host-node-tests.tap`）。这些旧数字仅代表当时范围，不代表当前 revision。

## 3. `hvigorw test` 的真实状态：BLOCKED（环境）

```bash
export DEVECO_SDK_HOME=/home/quirkybrain/harmonyos/command-line-tools/sdk
hvigorw test --no-daemon
```

实测（当前 revision）：

1. `UnitTestArkTS` **编译成功**（`entry/src/test/List.test.ets` 已存在，之前的“缺少 List.test”根因已消除）。
2. 随后 hvigor 启动 SDK 的 Linux Previewer；默认环境立即失败：
   `error while loading shared libraries: libshared_libz.so: cannot open shared object file`
   （`evidence/previewer-default-env.log`）。
3. 用临时 `/tmp` shim 补齐 `libshared_libz.so`（仅环境实验，不改仓库/SDK）后，Previewer 能启动，
   但返回：
   `JsApp::Run ability start failed.Linux is not supported.`
   （`evidence/previewer-with-lib-shim.log`），且不生成 `test_result.txt`；
   hvigor 进程一直等待，45s 超时退出（`evidence/hvigor-test-default-timeout.log` / `hvigor-test-with-lib-shim.log`）。

   复现 shim（可选，仅为确认根因；不会让测试执行）：

   ```bash
   mkdir -p /tmp/opencode/yaocore-t05/previewer-shim
   ln -sf /lib/x86_64-linux-gnu/libz.so.1 \
     /tmp/opencode/yaocore-t05/previewer-shim/libshared_libz.so
   export LD_LIBRARY_PATH="/tmp/opencode/yaocore-t05/previewer-shim:\
   /home/quirkybrain/harmonyos/command-line-tools/sdk/default/openharmony/previewer/common/bin:\
   /home/quirkybrain/harmonyos/command-line-tools/sdk/default/hms/toolchains/lib"
   hvigorw test --no-daemon   # still BLOCKED at "Linux is not supported"
   ```
4. 因此：**没有 Hypium 用例在 host 运行时通过**。不得把 `UnitTestArkTS` 编译成功写成测试 PASS。

结论：`hvigorw test` 在本 Linux 环境的阻塞是 **Previewer 运行时限制 + SDK 预览器缺库**，不是测试代码/断言失败；
Node host runner 是本环境唯一已实证的可执行 host 路径，覆盖纯逻辑层；平台适配器/设备测试仍需设备。

## 4. 与 ohosTest 的边界

| 层 | 路径 | 运行条件 | 当前 |
|---|---|---|---|
| Host 纯逻辑 | `entry/src/test/host/**` | Node（无设备） | **PASS 122/122**（wp-018-fix-t07 后） |
| Hypium host | `entry/src/test/List.test.ets` | `hvigorw test` + Linux Previewer | **BLOCKED**（见 §3） |
| 设备/模拟器 | `entry/src/ohosTest/**` | `onDeviceTest` + 设备 + 签名 | **BLOCKED**（见 ohosTest README） |

## 5. 证据纪律

- 每次修复/变更后重跑 `run-host-tests.sh`，把 TAP 输出保存到 `evidence/` 或 T-19 报告；
- 测试失败必须保留命令、退出码、失败断言；不得删除断言换 PASS；
- host 测试通过不等于产品验收；性能/真实网络/真实 BLE/UI 渲染仍标 `UNAVAILABLE`。
