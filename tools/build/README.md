# 构建与测试基线工具（T-01）

- **Producer**: agent:implementation-engineer
- **Task**: `wp-006-build-baseline`（T-01）
- **Date**: 2026-10-17
- **Status**: 仅记录本机已验证事实；运行时测试在本环境被阻塞，见下文。

本目录提供 T-01 的**可复现命令封装**。详细环境事实、逐项结果、错误根因与复用命令见
[`artifacts/50-implementation/build-baseline.md`](../../artifacts/50-implementation/build-baseline.md)。

## 前置条件

| 项 | 本机已验证值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore` |
| `DEVECO_SDK_HOME` | `/home/quirkybrain/harmonyos/command-line-tools/sdk` |
| SDK | HarmonyOS 26.0.0 (`26.0.0.105`)，apiVersion `26` |
| `ohpm` | `26.0.0.630` |
| `hvigorw` | `6.26.8` |
| `codelinter` | `6.0.240` |
| Node | `v24.15.0` |
| Java | OpenJDK `21.0.12.1` |

- `ohpm`、`hvigorw`、`codelinter`、`node`、`java` 必须在 `PATH`。
- `DEVECO_SDK_HOME` 必须指向包含 `default/sdk-pkg.json` 的 SDK 根目录。
- 首次 `ohpm install` 需要能访问 ohpm registry（本机已验证可达）。
- 不修改任何构建配置；脚本只生成被 `.gitignore` 忽略的 `oh_modules/`、`entry/build/`、`build/`、`entry/.test/`、`.hvigor/`。

## 用法

```bash
# 默认：安装依赖 + 干净 HAP 构建 + 静态检查 + ohosTest HAP 编译 + unsigned app 打包
tools/build/verify-baseline.sh

# 有真机/模拟器时：额外运行 on-device Hypium 测试
tools/build/verify-baseline.sh --with-device-tests

# 当 entry/src/test/List.test.ets 已由其他任务创建时：运行 host 单测
tools/build/verify-baseline.sh --with-host-tests

# 日志目录可指定；默认 mktemp 临时目录
YAOCORE_BASELINE_LOG_DIR=/tmp/opencode/yaocore-baseline tools/build/verify-baseline.sh
```

## 每一步做什么

| 步骤 | 命令 | 本机结果 |
|---|---|---|
| 依赖 | `ohpm install` | **PASS**，生成 `oh-package-lock.json5` |
| 干净构建 | `hvigorw clean assembleHap --no-daemon` | **PASS**，产出未签名 HAP |
| 静态检查 | `codelinter -c code-linter.json5 -p default .` | **PASS**，`No defects found in your code.` |
| 测试代码编译 | `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **PASS**，产出未签名测试 HAP |
| 应用打包 | `hvigorw assembleApp --no-daemon` | **PASS**，产出未签名 `.app` |
| Host 单测 | `hvigorw test --no-daemon` | **未运行/当前不可用**：要求 `entry/src/test/List.test.ets` |
| 设备测试 | `hvigorw --mode module -p module=entry@ohosTest -p product=default onDeviceTest --no-daemon` | **环境阻塞**：无 hdc 目标/模拟器 |

## 产物（均不提交）

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap
build/outputs/default/YaoCore-default-unsigned.app
```

`build-profile.json5` 的 `signingConfigs` 为 `[]`，hvigor 会打印
`Will skip sign 'hos_hap'` / `Will skip sign 'app'`，但**仍可产出未签名包**。
未签名包不能安装到设备，因此设备测试还需要证书/签名配置，见报告。

## 测试探针

- `entry/src/ohosTest/module.json5`：最小 `entry_test` feature 模块配置。
- `entry/src/ohosTest/ets/test/List.test.ets` + `Baseline.test.ets`：Hypium 冒烟测试（仅验证测试框架与 ArkTS 运行时链路，不测试产品行为）。
- 测试 HAP 成功编译且 `sourceMaps.map` 包含 `Baseline.test.ets` / `List.test.ets`，但**未执行**。
- `hvigorw test --no-daemon` 的 host 单测运行器期望 `entry/src/test/List.test.ets`；该路径不在 T-01 handoff 写范围内，不能为跑通而越界创建。
- `onDeviceTest` 需要 `hdc` 已连接设备；本机 `hdc list targets` 为空，且无已创建/已下载的模拟器实例。

## 已知警告与限制

1. 测试 HAP 构建出现 `'start_window_background' conflict` 警告：生成模板与 `entry/src/main/resources/base/element/color.json` 同名资源冲突，当前不阻断构建；后续测试任务可清理模板资源。
2. `entry/src/ohosTest` 未纳入 `code-linter.json5` 的检查范围（配置显式忽略 `**/src/ohosTest/**/*`）；测试代码静态检查留待 TEST-001 定义。
3. 无真机、无模拟器实例、无签名配置是本环境的硬限制；不得把“测试 HAP 编译通过”写成“测试通过”。
4. `hvigorw test` 是 host/本地单测任务，不是 `ohosTest` 的运行方式；对 `ohosTest` 目标执行 `test` 会因生成路径不匹配而失败。
5. 本目录脚本不修改 `build-profile.json5`、`entry/build-profile.json5`、`oh-package.json5` 或任何冻结输入。
