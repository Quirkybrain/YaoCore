# T-17 编译修复报告（C-08..C-19 生产图 ArkTS 错误）

- **Artifact ID**: T17-COMPILE-FIX
- **Producer**: agent:implementation-engineer
- **Task**: `wp-068-t17-compile-fix`（T-17 后续修复，Handoff `state/handoffs/wp-068-t17-compile-fix.json`）
- **Branch**: `task/wp-067-ui-shell`（base `9422e37`，父分支 `feat/yaocore-app`，parent `50f0443`）
- **Status**: **COMPLETE（本地验证通过；待独立评审/CQG-T17 Gate）**
- **Date**: 2026-10-18
- **Workflow**: STANDARD / GATED_AUTO

> **结论**：按已验证补丁 `artifacts/50-implementation/t17-c28-compile-fix.patch` 对 5 个前置文件应用最小修复，未改变任何冻结 API 语义。五项命令全部通过：`assembleHap` **BUILD SUCCESSFUL**（生产图含 C-08..C-19），host 测试 **639/639**，`codelinter` **0 error**，`check_i18n` **0 blocking**。

---

## 1. 输入与基线核对

| 输入 | 期望 sha256（Handoff） | 实际 sha256 | 结果 |
|---|---|---|---|
| `artifacts/50-implementation/t17-ui-shell.md` | `5ed8035d…c8385bf` | `5ed8035de0d6ac82a15195a6140bc57fa5761df3d918e8d7273463543c8385bf` | ✅ 匹配 |
| `artifacts/50-implementation/t17-c28-compile-fix.patch` | `6120ae68…a2fe3e` | `6120ae689e7465fa7d461fdc1a07fcf769aa1618f7dae6a786dd529511a2fe3e` | ✅ 匹配 |
| `entry/src/test/run-host-tests.sh` | `dc838451…d7c0a1d` | `dc838451f2d8a1866005de3ebc948ddf3b99960447f97251dd2a94a15d7c0a1d` | ✅ 匹配 |

- 基线提交：`9422e377e61dfa640b9f49904ae9e7b374d24ab0`（HEAD = T-17 实现）。
- 应用补丁前工作树干净（`git status --short` 为空）。
- 未切换分支，未执行 pull/merge/rebase/push。

## 2. 补丁应用记录

```text
git apply --check --verbose artifacts/50-implementation/t17-c28-compile-fix.patch   # 5 文件全部检查通过
git apply           artifacts/50-implementation/t17-c28-compile-fix.patch          # 干净应用，无 fuzz / 无 reject
```

应用后 `git diff --stat`：

```text
 entry/src/main/ets/common/utils/Base64Url.ets      |  2 +-
 entry/src/main/ets/service/ble/BindingProbe.ets    |  2 +-
 .../ets/service/ble/BleProvisioningService.ets     | 49 ++++++++++++++++------
 entry/src/main/ets/service/ble/GattRequestQueue.ets|  4 +-
 entry/src/main/ets/service/cloud/SystemTimerPort.ets| 4 +-
 5 files changed, 42 insertions(+), 19 deletions(-)
```

补丁与当前树上下文完全一致，未发生冲突，因此没有做任何等价改写。

## 3. 逐文件修复说明

| # | 文件（应用后行号） | 修改 | 修复的编译错误 | 语义影响 |
|---|---|---|---|---|
| 1 | `common/utils/Base64Url.ets:9` | `import { AppError, AppErrors }` | `invalid(): AppError` 缺少 `AppError` 名称，并级联 7 条 throw 错误 | 仅补类型导入；运行时不变 |
| 2 | `service/ble/BleProvisioningService.ets:80-104` | 新增名义类 `DelegatingScanListener implements BleScanListener`，构造注入 `found/finished/failed` 回调 | ArkTS 不允许对象字面量实现 `BleScanListener`（`arkts-no-structural-typing`） | 类仅按原顺序转发三个回调；两处调用点（`:171`、`:420`）的闭包捕获与调用顺序不变 |
| 3 | `service/ble/BleProvisioningService.ets:482` | `throw error` → `throw error as Error` | `error` 为 `unknown`/过宽类型，不能直接 throw | `as` 为编译期断言，运行时抛出对象不变 |
| 4 | `service/ble/BindingProbe.ets:234` | `throw error` → `throw error as Error` | 同上（清理路径需原样重抛） | 运行时不变 |
| 5 | `service/ble/GattRequestQueue.ets:13,80` | 导入 `AppError`；timeout Promise 的 reject 参数类型 `Error` → `AppError` | `AppErrors.of(...)` 返回名义类型 `AppError`，与 `(error: Error) => void` 回调不兼容 | reject 值本来就只可能是 `AppErrors.of('PROVISIONING_GATT_BUSY')`；类型收窄与实现一致 |
| 6 | `service/cloud/SystemTimerPort.ets:9,15` | 导入 `AppError`；`rejecter` 类型 `(error: Error)` → `(error: AppError)` | `cancel()` reject 的 `AppErrors.of(...)` 名义类型不兼容 | 同上；取消仍 reject `PROVISIONING_CANCELLED` |

**未改变**：任何公开方法签名、Contract 行为、错误码、错误分类、回调时序、扫描/连接状态机。改动全部为类型层或等价委托结构。

## 4. 验证结果（实际执行，2026-10-18）

| # | 命令 | 结果 | 证据 |
|---|---|---|---|
| 1 | `ohpm install` | ✅ exit 0，`install completed in 0s 47ms` | `artifacts/50-implementation/evidence/t17-compile-fix/ohpm-install.log` |
| 2 | `hvigorw clean assembleHap --no-daemon` | ✅ **BUILD SUCCESSFUL in 11 s 532 ms**；34 executed / 1 up-to-date；产出 `entry-default-unsigned.hap`（3.18 MB） | `…/clean-assemble.log` |
| 3 | `codelinter -c code-linter.json5 -p default .` | ✅ exit 0：`Errors: 0; Warns: 15; Suggestions: 0`（15 条均为既有自定义组件性能提示） | `…/codelinter.log` |
| 4 | `entry/src/test/run-host-tests.sh` | ✅ **639/639 pass**，`fail 0 / skipped 0 / todo 0` | `…/host-node-tests.tap` |
| 5 | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | ✅ exit 0，`blockingFailures=0`（warnings=61，见下注） | `…/i18n-checker.log` |
| 5b | 同上 + `--allowlist entry/src/test/i18n/allowlist.json` | ✅ exit 0，`blockingFailures=0 warnings=10 missingKeys=0 hardcoded=10`，与 T-17 证据完全一致 | `…/i18n-checker-with-allowlist.log` |

> **i18n 注**：Handoff 指定的命令未带 `--allowlist`，因此 CHK-05 把 51 个已登记前缀键（`scene.*`、`device.*`、`common_*` 等）报为 unused-key **warning**；该检查 `blocking=False`，两项命令均为 **0 blocking**。按脚本文档的完整调用（含 allowlist）复跑得到 10 条既有 CJK 硬编码 warning，与 T-17 证据逐项一致，证明本次修复无 i18n 回归。

## 5. 范围与约束核对

- 实际修改文件全部位于 Handoff `writes` 允许的 `entry/src/main/ets/common/`、`entry/src/main/ets/service/`、`artifacts/50-implementation/`。
- 未修改 `entry/src/ohosTest/**`、`entry/src/test/evidence/**`、页面、资源、module 配置或其他文件。
- 提交时 `commit_paths` 与上述范围一致；`artifacts/` 被 `.gitignore` 忽略，按 Handoff 要求使用 `git add -f`。
- 构建产物：unsigned HAP（项目未配置 signingConfigs，沿用既有状态）。

## 6. 残余风险

| 项 | 级别 | 说明 | 归属 |
|---|---|---|---|
| 设备/真实 BLE/云路径未验证 | BLOCKED（既有） | 本次仅证明生产 HAP 可编译、host 逻辑 639/639；无设备/模拟器（D-019） | T-19 |
| `as Error` 断言的运行时边界 | Low | 若底层抛出非 `Error` 值，`isCode` 等既有辅助函数行为与修复前一致；本次不改变运行时对象 | 维护轮 |
| 15 条 codelinter 性能 warning | Low（既有） | 自定义组件建议，非错误；分布于 T-17 页面 | T-18/维护轮 |
| 51 条 CHK-05 unused-key warning（无 allowlist 调用时） | Low | 仅因省略 `--allowlist`；完整调用为 10 条既有 warning | CI 调用约定 |
| HAP 未签名 | Low（既有） | 未配置 signingConfigs；不影响 `assembleHap` 编译验证 | 发布阶段 |
| `fill` API 兼容性 warning（MainShell/ShellBackdrop） | Low（既有） | SDK 26 API 与 compatibleSdk 14 的构建告警，T-17 引入 | T-18 |

## 7. 与 T-17 主报告的关系

- 本报告补齐 `t17-ui-shell.md` §3 的五文件编译阻断；T-17 报告状态可从 **BLOCKED** 更新为“实现 + 编译修复完成，待独立评审”。
- 补丁文件保留原样（内容未改），已在任务树实际应用并验证。
- 后续：`quality-reviewer` 对 `9422e37 + 本修复提交` 执行 CQG-T17/IG-3；通过后由 `repository-manager` 合并到 `feat/yaocore-app`。
