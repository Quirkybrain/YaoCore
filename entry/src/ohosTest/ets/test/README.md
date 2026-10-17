# ohosTest（设备/模拟器测试）引导

- **Producer**: agent:test-engineer；agent:implementation-engineer（T-06/T-07/T-08/T-10/T-15/T-16 设备骨架）
- **Task**: T-05 / TEST-001（`wp-010-test-plan`）；T-08 修复 `wp-022-fix-t08`；T-10 `wp-031-i18n` + 修复 `wp-033-fix-t10`
- **当前状态**: **BLOCKED / 未运行**。本环境无真机、无模拟器实例、无签名配置；以下命令保留为设备可用时的执行入口，**不得**把“测试 HAP 编译成功”写成“设备测试通过”。

## 1. 目录

```text
entry/src/ohosTest/
├── module.json5                         # entry_test feature 模块
└── ets/test/
    ├── List.test.ets                    # Hypium suite 入口（注册 baseline/foundation/security/storage/i18n）
    ├── Baseline.test.ets                # T-01 框架冒烟（仅编译过，未执行）
    ├── foundation/
    │   └── FoundationDevice.test.ets    # T-06 C-01..C-03 设备骨架（BLOCKED_ON_DEVICE_RUNNER）
    ├── security/
    │   └── SecurityDevice.test.ets      # T-07 C-04/C-05 设备向量（BLOCKED_ON_DEVICE_RUNNER）
    ├── storage/
    │   └── StorageDevice.test.ets       # T-08 C-06/C-07 适配器/事务/Asset 骨架（BLOCKED）
    ├── gateway/
    │   └── GatewayTransportDevice.test.ets  # T-11 C-17 HTTP/TLS pin path B 骨架（BLOCKED）
    ├── i18n/
    │   └── I18nDevice.test.ets          # T-10 C-14 rawfile/applier/Preferences 骨架（BLOCKED）
    ├── viewmodel/
    │   └── ViewModelsDevice.test.ets    # T-15/T-16 C-21..C-23 编译/接线骨架（BLOCKED）
    └── contract/
        └── fixtures/                    # 协议 golden（PUBLIC TEST DATA ONLY）
            ├── hmac-sha256-test-vectors.json
            ├── response-auth-test-vectors.json
            ├── discovery-request-auth-test-vectors.json
            ├── discover-response.json
            ├── control-ack.json
            ├── control-ack-replay.json
            └── README.md
```

## 2. 前置条件（设备测试）

| 项 | 要求 | 当前环境 |
|---|---|---|
| 设备/模拟器 | `hdc list targets` 非空；或已创建并下载模拟器镜像 | ❌ `[Empty]` |
| 签名 | `build-profile.json5` 的 `signingConfigs` 含可用 debug 证书 | ❌ `signingConfigs: []` |
| SDK | `DEVECO_SDK_HOME` 指向 HarmonyOS SDK | ✅ |
| 构建 | `hvigorw` 可用 | ✅ |

## 3. 命令

```bash
cd /home/quirkybrain/code/harmony-projects/YaoCore
export DEVECO_SDK_HOME=/home/quirkybrain/harmonyos/command-line-tools/sdk

# 1) 只编译测试 HAP（当前可 PASS；不等于测试执行）
hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon

# 2) 设备/模拟器执行（当前 BLOCKED）
hvigorw --mode module -p module=entry@ohosTest -p product=default onDeviceTest --no-daemon
```

当前实测：

- 步骤 1 **PASS**（产物 `entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap`，未签名）。
- 步骤 2 **BLOCKED**：无 `hdc` target + 未签名，错误码 `00507013`（`need connect-key`）。
- 不要使用 `hvigorw test` 运行 `ohosTest` 目标；该命令是 host/本地单测任务，路径不匹配（见 BUILD-BASELINE §5）。

## 4. 设备可用后的契约测试清单

1. 读取 `contract/fixtures/*.json`，断言 4 条控制 HMAC、响应验签、发现签名向量（T-07）。
2. 对 `tools/simulator`（HTTP/TLS）执行发现→控制→ACK 闭环；校验 `X-YaoCore-Simulator: DEV-ONLY` 拒收路径。
3. golden ACK：`request_id:seq` correlation、`result_code==0`、`reported_state.online`、无 `success`、`idempotent_replay`。
4. 负例：坏签名/过期时间戳/重放/nonce 冲突/未知码 fail-closed/DEV-ONLY 拒收。
5. 所有 secret 仅用公开测试数据；设备日志不得输出 PoP/Wi-Fi/密钥。

## 5. 限制

- 本目录的设备套件已全部注册进 `List.test.ets`（T-06 foundation、T-07 security、T-08 storage、T-10 i18n、T-15/T-16 viewmodel）；注册只表示设备可用时会执行，当前仍为 `BLOCKED_ON_DEVICE_RUNNER`，不得写成 PASS。
- T-10 i18n 设备骨架使用 rawfile 键 `errors.gateway.success`（`common_*` 是 `string.json` 的 `$r` 键，不能经 `t()` 读取）；同时校验 en-US/zh-CN 切换、fallback、复数与 `I18nKeys` 映射。运行时 `$r` 重渲染仍由 T-17/T-18 验证。
- T-08 storage 骨架包含 Preferences/RDB/Asset 读写、事务回滚、事务内 `setVersion` 回滚与锁屏 `ASSET_ACCESS_DENIED` 断言；锁屏分支需要 runner 先建立锁屏前置条件，未在无设备环境执行。
- 设备测试不覆盖真实硬件/射频/真实网关；这些由用户自行执行（CP-03）。
- `code-linter.json5` 当前忽略 `src/ohosTest/**`；测试源码检查策略见 TEST-001。
