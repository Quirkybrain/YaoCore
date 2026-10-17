# 构建与测试基线验证（BUILD-BASELINE-001）

- **Artifact ID**: BUILD-BASELINE-001
- **Producer**: agent:implementation-engineer
- **Type**: Build / Test Baseline Evidence
- **Status**: Proposed（待 G-009 Build Baseline Artifact Validation 与 CQG-T01 构建证据）
- **Date**: 2026-10-17
- **Task**: `wp-006-build-baseline`（T-01；task 分支 `task/wp-006-build-baseline`，父分支 `feat/yaocore-app`，base commit `b08646b`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`
- **Upstream**:
  - `artifacts/30-plan/delivery-plan.md` §3.1（T-01 DoD）@ G-005
  - `artifacts/20-architecture/project-constraints.md` PL-01..PL-09、CP-03 @ G-004
  - `config/project.md` @ pin
  - `state/reports/wp-000-repo-bootstrap.md` @ pin（工具链侦察）
  - handoff 冻结的 14 项输入（构建配置、hvigor 配置、linter 配置、module 配置均未修改）
- **Downstream**: T-02 README、T-03/T-04 DES-001、T-05 TEST-001、T-06 起的实现任务、T-19 全量测试、G-009/G-014

---

## 0. 摘要

| 项 | 结果 | 证据位置 |
|---|---|---|
| 环境事实 | **PASS（已记录）** | §1 |
| `ohpm install` | **PASS** | §2；`oh-package-lock.json5` |
| 干净 HAP 构建 | **PASS** | §3；`entry-default-unsigned.hap` |
| 应用打包 `assembleApp` | **PASS（未签名）** | §3；`YaoCore-default-unsigned.app` |
| 静态检查 `codelinter` | **PASS**（`No defects found`） | §4 |
| Hypium 测试探针编译 | **PASS**（仅编译） | §5 |
| Hypium 测试实际执行 | **环境阻塞 / 未运行** | §5；无设备/模拟器、无签名 |
| Host 本地单测 `hvigorw test` | **未运行/当前不可用** | §5；要求 `entry/src/test/List.test.ets`，不在写范围 |
| 签名行为 | **已查明**：`signingConfigs: []` → 跳过签名，产出未签名包 | §6 |
| 首条可用命令 | `tools/build/verify-baseline.sh` | §7 |

**结论**：本仓库在当前环境可复现地完成依赖安装、ArkTS 干净构建、静态检查、测试代码编译和 unsigned app 打包；**没有**执行任何 Hypium 测试用例。测试运行路径被“无真机/无模拟器实例/无签名配置”阻塞，且 host 单测所需的 `entry/src/test/` 不在本次 handoff 写范围内。不得把“测试 HAP 编译通过”写成“测试通过”。

---

## 1. 环境事实

采集日期：2026-10-17；仓库根：`/home/quirkybrain/code/harmony-projects/YaoCore`；分支：`task/wp-006-build-baseline`；基线 commit：`b08646b311eaaf1464644332d321bad3f246f97b`。

| 项 | 实测值 |
|---|---|
| 操作系统 | `Linux 7.0.0-38-generic x86_64` |
| `command -v ohpm` | `/home/quirkybrain/harmonyos/command-line-tools/bin/ohpm` |
| `ohpm --version` | `26.0.0.630` |
| `ohpm config get registry` | `https://ohpm.openharmony.cn/ohpm/` |
| `command -v hvigorw` | `/home/quirkybrain/harmonyos/command-line-tools/bin/hvigorw` |
| `hvigorw --version` | `6.26.8` |
| `codelinter --version` | `6.0.240` |
| `node -v` | `v24.15.0` |
| `java -version` | OpenJDK `21.0.12.1` 2026-08-18（Ubuntu 24.04.4） |
| `DEVECO_SDK_HOME` | `/home/quirkybrain/harmonyos/command-line-tools/sdk` |
| SDK `default/sdk-pkg.json` | `apiVersion: 26`；`displayName: HarmonyOS 26.0.0`；`version: 26.0.0.105`；`stage: Release` |
| `hdc` | `Ver: 3.2.0f`（位于 `$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc`，**不在 PATH**） |
| `hdc list targets` | `[Empty]`（无连接设备/模拟器） |
| 模拟器实例 | `Emulator -list -details` → `[Empty]`（未创建实例） |
| 模拟器镜像 | `Emulator -imageList` 返回 phone/2in1/foldable 等条目，均 `downloaded: false` |
| 当前产品/目标 | `default`；模块 `entry`；ohosTest 目标 `entry@ohosTest` |

**判定**：工具链、SDK、Java、Node、静态检查器和 ohpm registry 均可用；设备与模拟器不可用。环境事实为后续任务的**前置条件基线**，不是产品运行时验证。

---

## 2. 依赖安装

### 2.1 命令与结果

```bash
ohpm install
```

首次执行（2026-10-17）：

```text
ohpm INFO: MetaDataFetcher fetching meta info of package '@ohos/hypium' ...
ohpm INFO: MetaDataFetcher fetching meta info of package '@ohos/hamock' ...
ohpm INFO: fetch meta info of package '@ohos/hypium' success ...
ohpm INFO: fetch meta info of package '@ohos/hamock' success ...
install completed in 0s 327ms
```

脚本复跑（`tools/build/verify-baseline.sh`）：`install completed in 0s 67ms`，退出码 0。

### 2.2 锁文件与依赖版本

`ohpm install` 生成根级 `oh-package-lock.json5`（应入库工程锁文件）：

| 包 | 解析版本 | 来源 |
|---|---|---|
| `@ohos/hypium` | `1.0.25` | `https://ohpm.openharmony.cn/ohpm/@ohos/hypium/-/hypium-1.0.25.har` |
| `@ohos/hamock` | `1.0.0` | `https://ohpm.openharmony.cn/ohpm/@ohos/hamock/-/hamock-1.0.0.har` |

- 锁文件 SHA-256：`63261e4afee2280ca28b240d99956d666f0efc6be6b2cc76dd53470c10d3cf71`
- `oh-package.json5` 未修改；依赖声明仍是 `@ohos/hypium: 1.0.25`、`@ohos/hamock: 1.0.0`。
- `oh_modules/`、`entry/build/`、`build/`、`entry/.test/`、`.hvigor/` 均被 `.gitignore`/`entry/.gitignore` 忽略，不提交。

**判定**：**PASS**。首次安装需要 ohpm registry 网络；本机已验证可达。

---

## 3. 构建

### 3.1 任务发现

- `hvigorw --help`：列出 `version`、`tasks`、`taskTree`、`prune`、`collectCoverage` 等命令。
- `hvigorw tasks --no-daemon`：项目级任务包含 `assembleApp`、`clean`、`PackageApp`、`SignApp` 等；模块级任务默认只显示 `tasks`/`taskTree`/`init`。
- `hvigorw taskTree --no-daemon`：确认 `:entry:assembleHap` 及 `:entry:default@*` 任务链存在。
- `hvigorw --mode module -p module=entry@default tasks --no-daemon` 未列出额外的 `assembleHap` 别名；直接使用 `assembleHap` 可执行。

### 3.2 干净 HAP 构建（已验证成功）

```bash
hvigorw clean assembleHap --no-daemon
```

结果：

```text
> hvigor Finished :entry:default@CompileArkTS...
> hvigor WARN: Will skip sign 'hos_hap'. No signingConfigs profile is configured in current project.
> hvigor Finished :entry:default@SignHap...
> hvigor BUILD SUCCESSFUL in 7 s 44 ms
35 tasks in total: 34 executed, 1 up-to-date
exit code: 0
```

首次手工执行耗时 `8 s 111 ms`；脚本复跑 `7 s 44 ms`。两次均为 `clean` 后成功，说明当前 scaffold 的 ArkTS 编译与 HAP 打包可重复。

产物：

| 路径 | 大小 | 说明 |
|---|---|---|
| `entry/build/default/outputs/default/entry-default-unsigned.hap` | `14,614` bytes | 未签名 HAP（主构建产物） |
| `entry/build/default/outputs/default/mapping/sourceMaps.map` | `3,674` bytes | source map（不提交） |
| `entry/build/default/outputs/default/pack.info` | `604` bytes | 包信息（不提交） |

### 3.3 应用打包（已验证成功）

```bash
hvigorw assembleApp --no-daemon
```

结果：

```text
> hvigor WARN: Will skip sign 'hos_hap'. No signingConfigs profile is configured in current project.
> hvigor WARN: Will skip sign 'app'. No signingConfigs profile is configured in current project.
> hvigor BUILD SUCCESSFUL in 8 s 26 ms
42 tasks in total: 31 executed, 11 up-to-date
exit code: 0
```

产物：

| 路径 | 大小 | 说明 |
|---|---|---|
| `build/outputs/default/YaoCore-default-unsigned.app` | `7,881` bytes | 未签名 `.app` 包 |
| `entry/build/default/outputs/default/app/entry-default.hap` | `14,614` bytes | `.app` 内打包的 HAP；签名任务被跳过，仍为未签名 |

### 3.4 构建告警

| 告警 | 出现场景 | 影响 |
|---|---|---|
| `Will skip sign 'hos_hap'` | 主 HAP / ohosTest HAP / assembleApp | 预期，`signingConfigs: []`；产物未签名 |
| `Will skip sign 'app'` | `assembleApp` | 预期；`.app` 未签名 |
| `If obfuscation is needed...` | `assembleApp` | release 混淆未启用；当前 debug 构建不影响 |
| `'start_window_background' conflict` | ohosTest HAP 构建 | 生成模板资源与 `entry/src/main/resources/base/element/color.json` 同名；不阻断构建，见 §8 |

**判定**：**PASS**（HAP 与 app 打包均成功；产物未签名，不可安装）。

---

## 4. 静态检查

### 4.1 命令发现

`hvigorw tasks`/`taskTree` 没有暴露名为 `codeLinter` 的 hvigor 任务；本机 DevEco command-line tools 提供独立 `codelinter` CLI（`6.0.240`），按仓库 `code-linter.json5` 执行：

```bash
codelinter -c code-linter.json5 -p default .
```

### 4.2 结果

```text
The configuration file /home/quirkybrain/code/harmony-projects/YaoCore/code-linter.json5 is in use.
Currently active product:default
Finished...[==================================================]100%
No defects found in your code.
exit code: 0
```

- 在测试探针与 `.test/` 生成物存在后再次执行，结果仍为 `No defects found in your code.`，退出码 0。
- `code-linter.json5` 的范围是 `**/*.ets`，并显式忽略 `**/src/ohosTest/**/*`、`**/src/test/**/*`、`**/src/mock/**/*`、`**/build/**/*`、`**/oh_modules/**/*`、`**/.preview/**/*`；因此**测试源码本身未被 lint**。测试代码静态检查留待 TEST-001 定义。

**判定**：**PASS**（当前产品源码无 lint 缺陷；测试源码不在检查范围）。

---

## 5. 测试探针与运行路径

### 5.1 已创建的探针

| 路径 | 作用 |
|---|---|
| `entry/src/ohosTest/module.json5` | 最小 `entry_test` feature 模块配置，声明 `phone`、`deliveryWithInstall`、`installationFree`；不包含手写 TestAbility，交由 hvigor 的 `GenerateOhosTestTemplate` 生成 |
| `entry/src/ohosTest/ets/test/List.test.ets` | Hypium suite 入口，导入 `Baseline.test` |
| `entry/src/ohosTest/ets/test/Baseline.test.ets` | 两个纯断言用例：字符串/数值求值、`assertLarger`/`assertLess`；仅验证测试框架与 ArkTS 运行时链路，不测试产品行为 |

探针不含秘密、真实凭据或硬件依赖。

### 5.2 测试代码编译：**PASS**

```bash
hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon
```

结果：

```text
> hvigor Finished :entry:ohosTest@GenerateOhosTestTemplate...
> hvigor WARN: 'start_window_background' conflict ...
> hvigor Finished :entry:ohosTest@OhosTestCompileArkTS...
> hvigor WARN: Will skip sign 'hos_hap'. ...
> hvigor BUILD SUCCESSFUL in 7 s 917 ms
35 tasks in total: 34 executed, 1 up-to-date
exit code: 0
```

产物：

| 路径 | 大小 |
|---|---|
| `entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap` | `1,256,837` bytes |

检查 HAP 内容：

```text
module.json: mainElement=TestAbility, name=entry_test, abilities=[TestAbility]
ets/modules.abc: 存在
ets/sourceMaps.map: 包含 Baseline.test.ets、List.test.ets
```

**这说明测试源码被 ArkTS 编译器接受并打入测试 HAP；不等于测试用例已执行。**

### 5.3 尝试 1：host 本地单测 `hvigorw test`

```bash
hvigorw test --no-daemon
```

结果：**失败（未运行）**，退出码 `255`。

```text
ERROR: Failed :entry:default@UnitTestArkTS...
00305015 Rollup Error
Could not resolve "../../../src/test/List.test" from "entry/.test/testability/pages/Index.ets".
10505001 ArkTS Compiler Error
Cannot find module '../../../src/test/List.test' or its corresponding type declarations.
COMPILE RESULT:FAIL {ERROR:2}
BUILD FAILED in 6 s 494 ms
```

**根因**：该任务是 DevEco 的 host/本地单测运行器，生成的 `.test/testability/pages/Index.ets` 固定导入 `entry/src/test/List.test.ets`；本任务 handoff 的写范围只有 `entry/src/ohosTest/`，因此不能为跑通而创建 `entry/src/test/`。这不是产品代码失败，也不是 `ohosTest` 的运行方式。

**替代路径**：由后续获得 `entry/src/test/**` 写范围的任务（T-05/T-06 或明确授权的测试任务）创建本地测试入口后执行：

```bash
hvigorw test --no-daemon
```

在 `entry/src/test/List.test.ets` 存在前，该命令不可用。

### 5.4 尝试 2：对 `ohosTest` 目标执行 `test`

```bash
hvigorw --mode module -p module=entry@ohosTest -p product=default test --no-daemon
```

结果：**失败（未运行）**，退出码 `255`。

```text
ERROR: Failed :entry:ohosTest@UnitTestArkTS...
Error Code: 00308018 Unknown Error
ERROR: srcEntry file
'/home/quirkybrain/code/harmony-projects/YaoCore/entry/.test/default/intermediates/.test/testability/TestAbility.ets'
does not exist.
BUILD FAILED in 3 s 613 ms
```

**根因**：`test` 是 host/本地单测任务，不是 instrumented test 运行器；把 `ohosTest` 目标交给它会导致生成路径不匹配。`ohosTest` 应通过 `onDeviceTest`（设备）或先编译测试 HAP 后由 `hdc`/TestRunner 执行。该失败是命令路径错误，不是测试用例失败。

### 5.5 尝试 3：设备测试 `onDeviceTest`

```bash
hvigorw --mode module -p module=entry@ohosTest -p product=default onDeviceTest --no-daemon
```

结果：**环境阻塞（未运行）**，退出码 `255`。

```text
> hvigor Finished :entry:ohosTest@OhosTestCompileArkTS...
> hvigor WARN: Will skip sign 'hos_hap'. ...
> hvigor ERROR: Failed :entry:default@GenerateDeviceCoverage...
ErrorCode: 00507013
Description: Error: [Fail]ExecuteCommand need connect-key? please confirm a device by help info
BUILD FAILED in 9 s 102 ms
```

环境事实：

```text
hdc list targets -> [Empty]
Emulator -list -details -> [Empty]
Emulator -imageList -> phone/2in1/foldable 等均 downloaded: false
build-profile.json5 -> signingConfigs: []
```

**根因**：
1. 没有连接任何 HarmonyOS 设备，也没有已创建/已下载的模拟器实例；`hdc` 无 target，`onDeviceTest` 无法执行 device coverage/安装/启动测试。
2. 即使有模拟器，当前 `signingConfigs: []` 导致测试 HAP 未签名；未签名 HAP 不能安装到目标设备。
3. 因此测试用例执行被两层环境条件阻塞：**目标设备**与**签名配置**。

**替代路径（需要用户/环境决策，不在 T-01 擅自修改冻结配置）**：
- 方案 A：连接真机或创建/下载模拟器，并在获得授权的任务中配置 debug 签名（`build-profile.json5` 的 `signingConfigs`），然后执行上面的 `onDeviceTest` 命令。
- 方案 B：由 T-05/T-06 获得 `entry/src/test/**` 写范围，补 host 本地测试入口，执行 `hvigorw test`；仅覆盖纯逻辑，不覆盖真实设备/网络。
- 方案 C：T-05 TEST-001 把设备/模拟器测试列为 `USER_RUN_REQUIRED` 或 CI 环境项，T-19 只报告可执行的部分。

### 5.6 分类结论

| 项 | 分类 |
|---|---|
| 测试探针存在且 ArkTS 编译通过 | **已通过（编译）** |
| Hypium 用例实际执行 | **未运行 / 环境阻塞** |
| Host 本地单测 | **未运行 / 当前不可用（`entry/src/test` 不在写范围）** |
| 设备/模拟器安装运行 | **环境阻塞（无 target、无签名）** |

**禁止误读**：`entry-ohosTest-unsigned.hap` 编译成功只证明测试代码可编译，不证明任何断言在运行时通过。

---

## 6. 签名与 HAP 行为

### 6.1 配置事实

`build-profile.json5`（冻结输入，未修改）：

```json5
"signingConfigs": [],
"products": [{
  "name": "default",
  "signingConfig": "default",
  ...
}]
```

`signingConfigs` 为空，但 product 仍引用 `"default"` 签名配置；hvigor 的处理是**跳过签名任务**而不是构建失败。

### 6.2 实测行为

| 命令 | 签名日志 | 产物 |
|---|---|---|
| `hvigorw clean assembleHap --no-daemon` | `Will skip sign 'hos_hap'` | `entry-default-unsigned.hap`（14,614 bytes） |
| `hvigorw --mode module -p module=entry@ohosTest ... assembleHap` | `Will skip sign 'hos_hap'` | `entry-ohosTest-unsigned.hap`（1,256,837 bytes） |
| `hvigorw assembleApp --no-daemon` | `Will skip sign 'hos_hap'` + `Will skip sign 'app'` | `YaoCore-default-unsigned.app`（7,881 bytes） |

结论：

- **可以产出未签名 HAP 与未签名 `.app`**；构建链不因 `signingConfigs: []` 失败。
- **未签名包不可安装/运行**；设备测试与任何安装验证需要证书/签名配置。
- 未创建、未提交任何证书、密钥、HAP 或 `.app`；产物均在 gitignore 的构建目录中。
- `assembleApp` 中名为 `entry-default.hap` 的文件仍是未签名 HAP（签名任务被跳过），不能因文件名缺少 `unsigned` 而误判为已签名。

---

## 7. 后续任务可直接复用的命令块

### 7.1 环境准备（每个新 shell）

```bash
cd /home/quirkybrain/code/harmony-projects/YaoCore
export DEVECO_SDK_HOME=/home/quirkybrain/harmonyos/command-line-tools/sdk
# 确保 ohpm / hvigorw / codelinter / node / java 在 PATH
```

### 7.2 一键基线验证（推荐）

```bash
tools/build/verify-baseline.sh
# 可选：有设备时
tools/build/verify-baseline.sh --with-device-tests
# 可选：entry/src/test 已存在时
tools/build/verify-baseline.sh --with-host-tests
```

默认脚本执行：`ohpm install` → `hvigorw clean assembleHap --no-daemon` → `codelinter` → ohosTest HAP 编译 → `hvigorw assembleApp --no-daemon`；运行时测试明确标记为 NOT RUN/BLOCKED，不伪造 PASS。

### 7.3 分步命令（与脚本等价）

```bash
# 依赖（生成/刷新 oh-package-lock.json5）
ohpm install

# 干净 HAP 构建
hvigorw clean assembleHap --no-daemon

# 静态检查（codelinter 是独立 CLI；不是 hvigor task）
codelinter -c code-linter.json5 -p default .

# 编译 ohosTest Hypium 探针（只编译，不执行）
hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon

# 应用打包（未签名）
hvigorw assembleApp --no-daemon
```

### 7.4 测试运行命令（当前受环境阻塞）

```bash
# 设备/模拟器测试：需要已连接 target + 已配置签名
hvigorw --mode module -p module=entry@ohosTest -p product=default onDeviceTest --no-daemon

# host 本地单测：需要 entry/src/test/List.test.ets（T-01 写范围外）
hvigorw test --no-daemon
```

### 7.5 任务发现

```bash
hvigorw tasks --no-daemon
hvigorw taskTree --no-daemon
hvigorw --mode module -p module=entry@default tasks --no-daemon
```

### 7.6 提交注意

- `.gitignore` 的 `**/build` 会忽略 `tools/build/` 目录本身；提交时必须使用：
  ```bash
  git add -f tools/build
  ```
- 构建产物（`entry/build/`、`build/`、`entry/.test/`、`oh_modules/`、`.hvigor/`）不得提交。
- `oh-package-lock.json5` 是应入库的锁文件，不受 `tools/build` 忽略影响。

---

## 8. 已知限制与风险

| ID | 限制/风险 | 影响 | 处置 |
|---|---|---|---|
| BL-R01 | 无真机、无模拟器实例、镜像均未下载 | 不能安装/运行 HAP；Hypium 用例未执行；BLE/LAN/TLS/UI 运行时无证据 | 作为环境限制记录；由 T-05/T-19 或用户环境决策；不伪造 PASS |
| BL-R02 | `signingConfigs: []`，无证书/签名材料 | 所有 HAP/`.app` 未签名，不可安装；设备测试被阻塞 | 在获得授权的任务/环境中配置 debug 签名；T-01 不修改冻结配置 |
| BL-R03 | `hvigorw test` 要求 `entry/src/test/List.test.ets`，该路径不在 T-01 写范围 | host 单测当前不可用 | 由后续拥有 `entry/src/test/**` 写范围的任务创建；或在 handoff 中扩展写范围 |
| BL-R04 | `tools/build/` 被 `**/build` 忽略 | 后续普通 `git add` 可能漏提交构建脚本 | 必须 `git add -f tools/build`；已在 handoff 的 commit 命令中体现 |
| BL-R05 | ohosTest HAP 构建出现 `'start_window_background'` 资源冲突警告 | 当前不阻断；未来资源扩展可能出现歧义 | 后续 T-05/T-17 清理生成模板资源或显式声明覆盖 |
| BL-R06 | `code-linter.json5` 忽略测试源码 | 测试代码无 lint 证据 | TEST-001 定义测试源码检查策略；T-19 报告 |
| BL-R07 | 对 `ohosTest` 目标执行 `test` 任务失败 | 团队可能误用该命令 | 明确：host 单测用 `hvigorw test`；设备测试用 `onDeviceTest`；测试 HAP 编译用 ohosTest `assembleHap` |
| BL-R08 | `ohpm install` 首次需要网络 | 离线环境无法复现安装 | 锁文件固定版本；离线缓存/镜像由环境负责 |
| BL-R09 | 当前构建只覆盖 scaffold 与测试探针，无业务代码 | 不能据此推断后续业务组件可编译 | 每个实现任务按 CQG 重新构建；本基线只固定命令与工具链 |
| BL-R10 | 未测量覆盖率/性能 | 无 NFR 4.3 证据 | T-05 定义测量口径；T-19 输出 `MOCK_ONLY`/`ESTIMATE`/`UNAVAILABLE` |

---

## 9. 覆盖边界（无真机）

**本基线能证明**：

- `ohpm`/`hvigorw`/SDK/Java/Node/`codelinter` 可用；
- `ohpm install` 可解析并锁定 `@ohos/hypium`/`@ohos/hamock`；
- ArkTS 源码可编译，HAP/`.app` 可打包（未签名）；
- `code-linter.json5` 对当前产品源码无缺陷；
- ohosTest Hypium 探针可被 ArkTS 编译并打入测试 HAP；
- 构建与静态检查命令可在当前工作区重复执行（clean build 连续两次成功）。

**本基线不能证明**：

- 任何 Hypium 断言在运行时通过；
- HAP 可安装、启动或运行；
- 真机 UI、BLE/GATT、局域网 HTTP/TLS、云 IoTDA、邀请/密钥、真实硬件 ACK；
- 性能（ACK p95、55ms 节流、60/120fps）；
- 签名、发布包、应用市场兼容性；
- `entry/src/ohosTest` 源码的 lint 质量（当前配置忽略）。

**实测状态**：无真机、无模拟器实例、无签名配置。按 CP-03，不阻塞 Agent 工程门禁，但必须在测试报告与 Stage Gate 中如实列为 `UNAVAILABLE`/`USER_RUN_REQUIRED`，不得写成 PASS。

---

## 10. 建议的 Gate 结论（供 Orchestrator 判定）

- **G-009 Build Baseline Artifact Validation**：建议对“环境事实、安装、构建、静态检查、测试探针编译、签名行为、复用命令”判 **PASS**；对“测试运行时执行”判 **BLOCKED/未运行**，并作为已知限制进入 T-05/T-19。
- **CQG-T01 构建证据**：构建、静态检查、测试代码编译证据可用；**不得**把测试运行写成 PASS。
- 后续 T-02 README 可直接复用 §7 命令块；T-03/T-04 可引用 §1 的环境事实；T-05 必须解决 host 测试路径与设备/模拟器测试策略；T-19 汇总时保留本节 `BLOCKED`/`UNAVAILABLE` 分类。

---

*BUILD-BASELINE-001 结束。所有命令均在 `task/wp-006-build-baseline` 分支、base `b08646b` 上执行；未修改任何 handoff 冻结的构建配置。*
