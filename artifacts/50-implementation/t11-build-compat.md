# T-11 评审 F-06 修复：`compatibleSdkVersion` 与 API 14+ 基线

- Task: `wp-038-build-compat`
- Producer: `agent:implementation-engineer`
- Date: 2026-10-17
- Branch: `task/wp-035-transport`（base `36ce10b`）
- Inputs: `artifacts/70-review/t11-review.md`、`config/project.md`、`build-profile.json5`（前值）、`artifacts/50-implementation/build-baseline.md`
- Write scope: `build-profile.json5`、`artifacts/50-implementation/`

## 0. 结论（TL;DR）

**判定：已修正（构建/打包基线），无需登记"构建兼容性例外（待环境）"。**

| 字段 | 修改前 | 修改后 |
|---|---|---|
| `compileSdkVersion` | 未显式设置（默认 SDK 26.0.0） | `"26.0.0"` |
| `targetSdkVersion` | `"26.0.0"` | `"26.0.0"`（不变） |
| `compatibleSdkVersion` | `"26.0.0"` | **`"5.0.2(14)"`** |
| `runtimeOS` | `"HarmonyOS"` | `"HarmonyOS"`（不变） |

`hvigorw clean assembleHap --no-daemon` 成功；产物元数据证明最低兼容 API 已变为 14：

- HAP `module.json`：`minAPIVersion = 50002014`（即 5.0.2.14），`targetAPIVersion = 260000026`（26.0.0），`compileSdkVersion = 26.0.0.105`
- `pack.info`：`"apiVersion":{"compatible":14,"releaseType":"Release","target":26}`
- hvigor 解析缓存：`compatibleSdkVersion = 14`，`originCompatibleSdkVersion = "5.0.2(14)"`

**边界声明**：本次只修复"构建配置声明的最小兼容版本"，并证明 HAP 打包元数据为 API 14。它**不**证明 API 14 设备上的运行时行为（TLS/证书/网络语义、安装运行矩阵）已经验证；CP-01 的运行时部分仍为 `UNVERIFIED`，须由 T-19/设备矩阵补齐。

## 1. 调查：`compatibleSdkVersion` 的正确取值格式

### 1.1 hvigor 5.x/6.x schema 约束

来源：`$DEVECO_SDK_HOME/../hvigor/hvigor-ohos-plugin/res/schemas/ohos-project-build-profile-schema.json`

- 通用定义允许 `integer | string`，`exclusiveMinimum: 3`。
- 当 `runtimeOS: "HarmonyOS"` 时，schema 的 `then` 分支要求 `compileSdkVersion` 与 `compatibleSdkVersion` 为 **string**。
- 因此 HarmonyOS 产品不应写裸数字 `14`；且 hvigor 的 `apiConfigurationCheck` 规定：`runtimeOS != OpenHarmony` 且 `compatibleSdkVersion` 为数字时，必须显式提供 `compileSdkVersion`（否则报 `NO_COMPILESDKVERSION_IN_OPENHARMONY`）。

### 1.2 HarmonyOS 版本串与 API 的映射

来源：`@ohos/hos-sdkmanager-common/build/res/hos-config.json` 的 `osVersionMapper`（hvigor 自带依赖）：

| OS 版本 | API |
|---|---|
| `5.0.0` | 12 |
| `5.0.1` | 13 |
| **`5.0.2`** | **14** |
| `5.0.3` | 15 |
| `5.0.4` | 16 |
| `5.0.5` | 17 |
| `5.1.0` | 18 |
| `6.0.0` | 20 |
| `6.0.2` | 22 |
| `26.0.0` | 26 |

hvigor 的 `parseApiVersion`（`src/sdk/sdk-util.js`）对带括号的旧式版本串（`x.y.z(api)`）用**括号内数字**作为 API level。因此 API 14 的规范写法是 **`"5.0.2(14)"`**；如果写 `"14.0.0"`，`newDotSeparatedVersion`/`oldDotSeparatedVersion` 均不匹配，会触发 `HO_API_VERSION_VALIDATE_FAILED`。

`compileSdkVersion` 不设置时默认为工具链最新支持版本（本机 `26.0.0`）；本次显式写入 `"26.0.0"` 以固定编译 SDK、避免默认值随工具链漂移。`targetSdkVersion` 保持 `"26.0.0"`，与 `config/project.md` 一致。

### 1.3 SDK 可用性

本机仅安装 `apiVersion 26` SDK（`sdk/default/sdk-pkg.json`：`apiVersion 26`，`version 26.0.0.105`）。实验证明**设置 `compatibleSdkVersion` 为更低版本不需要安装对应 API 级 SDK**：编译仍使用已安装的 API 26 SDK，`compatibleSdkVersion` 仅作为 HAP `minAPIVersion` 元数据与兼容性声明参与构建。故不存在预想的"本机仅有 API 26 SDK 导致无法解析低版本"的阻塞。

## 2. 修改内容

`build-profile.json5`（product `default`）：

```diff
-        "targetSdkVersion": "26.0.0",
-        "compatibleSdkVersion": "26.0.0",
+        "compileSdkVersion": "26.0.0",
+        "targetSdkVersion": "26.0.0",
+        "compatibleSdkVersion": "5.0.2(14)",
         "runtimeOS": "HarmonyOS",
```

未改动 `signingConfigs`、`buildOption.strictMode`、模块结构或其他文件。

## 3. 验证证据

环境：`DEVECO_SDK_HOME=/home/quirkybrain/harmonyos/command-line-tools/sdk`，hvigor 6.26.8，SDK 26.0.0.105。

| # | 命令 | 结果 | 原始日志 |
|---|---|---|---|
| 1 | `ohpm install` | PASS（`install completed`） | `evidence/t11-build-compat/ohpm-install.log` |
| 2 | `hvigorw clean assembleHap --no-daemon` | **BUILD SUCCESSFUL**，35 tasks；schema/API 配置校验通过；仅沿用既有"未配置 signingConfigs，跳过签名"WARN | `evidence/t11-build-compat/hvigor-assemble-hap.log` |
| 3 | `codelinter -c code-linter.json5 -p default .` | **No defects found**，exit 0 | `evidence/t11-build-compat/codelinter.log` |
| 4 | `bash entry/src/test/run-host-tests.sh` | **355/355 pass**，0 fail / 0 skip，exit 0 | `evidence/t11-build-compat/host-tests.log` |
| 5 | 产物元数据探针（HAP `module.json` / `pack.info` / hvigor 缓存） | `compatible=14`、`minAPIVersion=50002014`、`target=26` | `evidence/t11-build-compat/metadata-probe.log` |

关键原始输出：

```text
> hvigor BUILD SUCCESSFUL in 5 s 5 ms
# exit=0

# HAP module.json app fields
{"compileSdkVersion": "26.0.0.105", "targetAPIVersion": 260000026,
 "minAPIVersion": 50002014, "compileSdkType": "HarmonyOS"}

# pack.info
"apiVersion":{"compatible":14,"releaseType":"Release","target":26}
```

## 4. 判定与理由

1. 配置**合法**：符合 hvigor schema；`runtimeOS: HarmonyOS` 下使用字符串版本串；构建期 `apiConfigurationCheck` 通过。
2. 配置**生效**：HAP `minAPIVersion` 与 `pack.info` 均为 API 14，证明产物允许安装在 API >= 14 的设备上（解决 F-06 指出的"无法在 API 14 设备安装"的构建侧问题）。
3. `targetSdkVersion` 保持 26.0.0，编译 SDK 固定 26.0.0，符合 `config/project.md` 的 "API 14 / HarmonyOS NEXT (targetSdkVersion 26.0.0)" 与 CP-01。
4. 因此不登记"构建兼容性例外"；保留修改，不回退。

**未证明（不得据此宣称 CP-01 PASS）**：

- 未在 API 14/15 真机或模拟器安装/运行；`TLSSocket`、证书 pin、网络栈行为在 API 14 的语义仍待 T-19 设备矩阵。
- 编译使用 API 26 SDK；构建通过不代表运行时不会调用高于 API 14 的接口。API 使用面的现有证据仍是 T-11 的 `@since` 静态审计（`t11-transport.md` §PB-03），不是运行时事实。

## 5. 残余风险与后续要求

| ID | 项 | 级别 | 建议 |
|---|---|---|---|
| R-22（更新） | 构建基线已改为 API 14；运行时 API 14 可用性未验证 | Medium（由 High 降级） | T-19：在 API 14/15 设备矩阵安装并验证 `TLSSocket`/pin/控制链路；CI 固定 SDK 26.0.0.105 |
| R-28 | 文档陈旧：`README.md:51` 仍写 "`targetSdkVersion` / `compatibleSdkVersion` 为 `26.0.0`"；`artifacts/00-project-intake/inventory.md:119`（AS-042）记录旧值 | Low | 超出本任务写范围；由 technical-writer/后续 T-01 文档更新同步 |
| R-29 | 无签名配置（既有状态）：产物为 unsigned HAP | Low（既有） | 设备安装/发布阶段由 release-engineer 配置签名 |
| R-30 | 若未来将 `compatibleSdkVersion` 改为裸数字，需同时显式 `compileSdkVersion` | Low | 保持 `"x.y.z(api)"` 字符串格式与 `compileSdkVersion` 显式化 |

环境要求（可复现）：

- SDK：HarmonyOS 26.0.0.105（`DEVECO_SDK_HOME` 指向 command-line-tools SDK）；hvigor 6.26.8。
- 构建 API 14 兼容产物**不要求**本机安装 API 14 SDK；若要直接验证 API 14 编译/模拟器路径，需额外安装 API 14 SDK 组件与对应模拟器镜像。
- 运行时验收需 API 14/15 设备或可运行 API 14 的模拟器。
