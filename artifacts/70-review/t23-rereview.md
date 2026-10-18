# T-23 裁定修复聚焦复评（wp-094）

- **Artifact ID**: T23-REREVIEW
- **Producer**: agent:quality-reviewer
- **Task**: `wp-094-t23-rereview`（Handoff `state/handoffs/wp-094-t23-rereview.json`）
- **Role**: quality-reviewer（未参与 `wp-090-ports` 迁移或 `wp-093-t23-fixes` 修复；未编辑任何被审代码、测试、checker 或 allowlist）
- **Reviewed revision**: `cc2233d`（`fix(contracts): 应用 T-23 裁定并修复 ohosTest imports`；base `76c47f4`，分支 `task/wp-090-ports`）
- **Base**: `76c47f4`（DES-A/DES-B 附录 E 裁定与端口契约同步）
- **Parent branch**: `feat/yaocore-app` @ `1d4b202`
- **Review scope**: `entry/src/main/ets/`、`entry/src/test/`、`entry/src/ohosTest/`、`tools/contract/`、`artifacts/50-implementation/t23-ports-migration.md`
- **Workflow**: STANDARD / GATED_AUTO
- **Date**: 2026-10-18
- **Verdict**: **PASS（仅限 `cc2233d` 与本次范围）** —— F-01..F-07 与 ohosTest import 修复均按附录 E 落地，8 项复验全部退出 0；未发现阻塞项。本 PASS 不授予 Stage Gate、IG-3/IG-4 或用户验收
- **Status**: COMPLETE

> **结论先行**：本次聚焦复评确认 `cc2233d` 逐条落实了附录 E 的裁定：F-01 云 `TimerPort` 与 `SceneTimerPort`/`VmTimerPort` 三分归属及文件头正确，产品/测试代码无 `scheduleOnce`/`scheduleRepeating`/`TimerHandle` 残留；F-02 checker 精确执行 `contracts/**` 同层 type-only + 无环，现有 4 条 type-only 边保留，值/副作用/namespace 值导入与环均退出 1；F-03 `contracts/PermissionPort.ets` 仅导出 `ProvisioningPermissionPort`/`ProvisioningPermissionKind`，3 个 import 点正确，C-28 app seam 未变，`BleViewModelPermissionGate` 仍是唯一适配器，host 测试断言未被削弱；F-04 元数据 schema、`id` 唯一与任何 `pending-*` 退出 1 均已实现，6 类负例 fixture 与 22/22 自测通过；F-05/F-06/F-07 文件头、报告交叉引用/清单与 allowlist policy 按裁定修正；ohosTest 7 文件/12 条原失效 import 已修复且编译通过。独立实测：host **697/697**、clean assembleHap **BUILD SUCCESSFUL**、codelinter **0 error / 25 warn**、layering **files=221 violations=0**、fixture **22/22**、i18n **blocking=0/missing=0**、crosscheck **hard ALL PASS**、ohosTest **BUILD SUCCESSFUL**、main/test/ohosTest 相对 import **0 missing**、221 文件 **0 环**。剩余问题均为非阻塞的低风险工具/文档项（见 §4），其中 `export * from` 的 D-03 语法覆盖缺口为既有 checker 解析器遗留、当前仓库无实际使用，建议紧随工具任务修复。

---

## 1. 范围、revision、输入与独立性

| 项 | 本次结论 | 证据 |
|---|---|---|
| 仓库 / 分支 | `/home/quirkybrain/code/harmony-projects/YaoCore`；`task/wp-090-ports` | `git branch --show-current` |
| Reviewed HEAD | `cc2233dcf8f348fd619b508889de9e94edfad88c` | `git rev-parse HEAD` |
| Base / 父分支 | 修复 base `76c47f4`；父分支 `feat/yaocore-app` 指向 `1d4b202` | handoff + `git rev-parse` |
| 工作树 | 评审前干净；评审期间未修改产品/测试/checker/allowlist；复验后仍干净（构建产物被忽略） | `git status --short --branch` |
| 输入完整性 | 6 个 handoff 输入 SHA-256 全部一致 | `sha256sum` 对照 handoff |
| 作者独立性 | 未参与 `wp-090-ports` 实现或 `wp-093-t23-fixes` 修复；唯一写入为本报告 | 本任务 `writes`/`commit_paths` 仅 `artifacts/70-review/` |
| 变更范围 | `76c47f4..cc2233d` 共 **46** 个路径：**20 M + 26 A + 0 D**；全部在声明写范围内；未改 DES、协议资产或构建配置 | `git diff --name-status` |
| 评审限制 | 无设备/模拟器/签名配置；未运行设备 ohosTest、真实 BLE/LAN/云/TLS；ohosTest 仅编译 | 与报告 §10.4 的 BLOCKED 边界一致 |

**输入 SHA-256 核对**：`t23-review.md` `453d887d…`、DES-A `3c3b7b24…`、DES-B `d8245938…`、`t23-ports-migration.md` `b92d9f51…`、`check_layering.py` `8656fa23…`、`layering_allowlist.json` `5ebfe313…`，均与 `wp-094-t23-rereview.json` 一致。

**变更清单核对**：修改 20 个文件（报告、`app/PermissionGate.ets`、5 个 `contracts/**` 文件、`viewmodel/BleProvisioningViewModel.ets`、`viewmodel/core/ViewModelCore.ets`、7 个 ohosTest 文件、`ViewModelBle.test.mjs`、`check_layering.py`、`layering_allowlist.json`、`test_check_layering.py`）；新增 26 个 fixture 文件（4 类 D-03 fixture + 6 类 F-04 负例 fixture）。无删除、无重命名、无权限位变化。

**不在本次范围**：DES-A/DES-B 文本（裁定已在 `76c47f4` 提交）、设备运行、Stage Gate、后续 DES 同步任务。

---

## 2. 独立复验结果（cwd = 仓库根，本次实际执行）

| # | 命令 | 本次实测 | 退出码 |
|---|---|---|---|
| 1 | `entry/src/test/run-host-tests.sh` | **tests 697 / pass 697 / fail 0 / skipped 0**；duration ≈ 3068.9 ms | 0 |
| 2 | `hvigorw clean assembleHap --no-daemon` | **BUILD SUCCESSFUL in 14 s 753 ms**；35 tasks（34 executed / 1 up-to-date）；unsigned HAP | 0 |
| 3 | `codelinter -c code-linter.json5 -p default .` | **Defects 25 / Errors 0 / Warns 25 / Suggestions 0** | 0 |
| 4 | `python3 tools/contract/check_layering.py` | `files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0`；PASS | 0 |
| 5 | `python3 tools/contract/test_check_layering.py` | **Ran 22 tests / OK**（2.278 s） | 0 |
| 6 | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | `blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16` | 0 |
| 7 | `python3 tools/contract/crosscheck_protocol_assets.py` | **hard checks: ALL PASS**；14 条既有 frozen-input findings | 0 |
| 8 | `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **BUILD SUCCESSFUL in 13 s 300 ms**；`entry:ohosTest@OhosTestCompileArkTS` 完成；unsigned HAP | 0 |

补充静态核对（本次独立执行，未入库）：

- **相对 import 解析**：`entry/src/main/ets` + `entry/src/test` + `entry/src/ohosTest` 共 313 个 `.ets`/`.mjs` 文件、**2211** 条相对 import，**0 missing**（main 1562、test 526、ohosTest 123）。
- **全量 import 图**：`entry/src/main/ets/**/*.ets` 221 文件、1469 条可解析边，独立 DFS 扫描 **0 环**。
- **`contracts/**` 同层边**：恰好 4 条，全部 `kind=type`：`GatewayTransportPorts.ets:22`（`GatewayCredentialPort`）、`MigrationPort.ets:10`（`RdbStore`）、`RoomPorts.ets:9`（`RdbTransaction`）、`ScenePorts.ets:9`（`RdbTransaction`）；均保留未改写。
- **F-01 残留**：`grep -R "scheduleOnce\|scheduleRepeating\|TimerHandle" entry/src/main/ets entry/src/test entry/src/ohosTest tools/contract` → **0 命中**。
- **F-03 残留**：`contracts/**` 无 `export interface PermissionPort` / `export enum PermissionKind`；`PermissionResult` 在 `contracts/**` 仅出现在说明注释，无导出；全仓 `contracts/PermissionPort` 引用恰好 3 个文件（`PermissionGate.ets`、`BleProvisioningViewModel.ets`、`ViewModelBle.test.mjs`）。
- **ohosTest 旧路径**：精确正则检索 7 类旧路径 → **0 命中**；`common/types/Ports` 仅剩 `ClockPort`/`IdPort` 的 3 处合法 import。
- **diff 卫生**：`git diff --check 76c47f4..cc2233d` 无输出；新增行无 `TODO`/`FIXME`；无删除文件；无测试断言改写。

---

## 3. 逐项裁定 vs 实现结论

### F-01 `TimerPort` 归属与三分（已关闭）

- `contracts/TimerPort.ets` 头注释改为 C-15 云轮询 `sleep/cancel`，明确“VM callback timer is `VmTimerPort` (DES-B §23.1 `EXT-DES-B-33`), not this port”，并声明 `EXT-DES-B-01` 已退休、不得在本文件重建；接口签名 `sleep(ms, cancellation?)/cancel()` **未变**。
- `contracts/SceneTimerPort.ets` 头注释明确 scene-only `delay` seam，与云 `TimerPort`、VM `VmTimerPort` 三分；签名未变。
- `viewmodel/core/ViewModelCore.ets` 的 `VmTimerPort` 注释改为 DES-B `EXT-DES-B-33`、VM-local seam、与另两个 seam 分离；`setTimer/clearTimer` 签名未变。
- 三个文件本次 diff 均为**注释-only**（逐行过滤后无代码/签名变化）；`CloudService.ets`、`SystemTimerPort.ets`、`test/host/CloudFakes.ets` 未在本次 diff 中，C-15 import 路径保持 `contracts/TimerPort`。
- 产品/测试/ohosTest/tools 无 `scheduleOnce`/`scheduleRepeating`/`TimerHandle` 残留；`VmTimerPort` 仅出现在 VM/app 适配/test helper 与两个 contracts 文件的说明注释中，未进入 `contracts/**` 声明或端口位置例外。

**结论**：F-01 关闭，符合附录 E §E.2。

### F-02 D-03 type-only + 无环（已关闭；附 RR-01 潜在语法缺口）

- `check_layering.py` D-03 分支：`target_layer == "contracts"` 时，非 type-only 记录报 `contracts/** same-layer imports must be type-only (import type/export type)`；其他越界目标报 `contracts/** may only import common/**, model/**, or type-only contracts/**`。
- 新增 `_contract_import_cycles()`：纳入所有 `contracts → contracts` 边（含 type-only），DFS 检测、canonical 化后每环报一次、退出码 1；现有仓库 0 环。
- 手工负例（`/tmp/opencode/t23-rereview-check`，独立副本，未污染仓库）：
  - `import type` 同层 → **PASS/exit 0**；`export type { … } from` → **PASS/exit 0**。
  - 值导入 → **FAIL/exit 1**（D-03 same-layer type-only 消息）；副作用导入 → **FAIL/exit 1**；`import * as NS` namespace 值导入 → **FAIL/exit 1**；`import type * as NS` → PASS。
  - `export { X } from './B'` 值再导出 → **FAIL/exit 1**。
  - 3 个互不相交的 type-only 环 → **3 条 D-03、exit 1**，每个环只报一次；环消息含 `A.ets -> B.ets -> A.ets`。
  - 4 类新增 fixture（type-only-ok / value-import-bad / side-effect-bad / cycle-bad）均按预期被 `test_check_layering.py` 捕获，**22/22 OK**。
- 现有 4 条 type-only 同层 import 保留未写；仓库 `violations=0`。
- **潜在缺口（RR-01）**：`EXPORT_FROM_RE` 无法匹配 `export * from './B'`（值再导出），该语句既不触发 D-03 也不进入环图；手工 `export-star` fixture 实测 **PASS/exit 0**。当前仓库无任何 `export * from`，且该解析器缺陷在 `76c47f4` 之前即存在，不属于本次裁定列举的语法/负例；列为低风险工具债，建议紧随任务修复并补 fixture。

**结论**：按附录 E §E.3 的明确验收项关闭；RR-01 为非阻塞潜在覆盖缺口。

### F-03 `PermissionPort` 符号收敛（已关闭）

- `contracts/PermissionPort.ets` 仅导出 `ProvisioningPermissionKind`（`BLUETOOTH`）与 `ProvisioningPermissionPort`（`ensure(kind): Promise<void>` + 可选 `openSettings?()`）；**无 `PermissionResult` 导出**；头注释明确 `EXT-DES-B-22` 历史、`EXT-DES-B-34` 登记重命名、`PermissionResult` 属 C-28 app 层。
- 3 个 import 点与附录 E §E.4 精确清单一致：`BleProvisioningViewModel.ets`（type import + enum value import）、`PermissionGate.ets`（`as ViewModelPermissionPort`/`as ViewModelPermissionKind`）、`ViewModelBle.test.mjs`（enum value import）。字段/构造参数/`ensure(ProvisioningPermissionKind.BLUETOOTH)` 同步。
- `app/PermissionPolicy.ets` 未在本次 diff 中：C-28 `PermissionPort`/`PermissionKind`/`PermissionState`/`PermissionResult` 原样保留；`PermissionGate implements PermissionPort` 的 C-28 形状未变。
- `BleViewModelPermissionGate` 仍是唯一实现 C-23 适配器的类；`PermissionResult → void/错误` 转换只在该适配器内。
- `ViewModelBle.test.mjs` 本次仅改 import 行（`PermissionKind` → `ProvisioningPermissionKind`），测试体/断言 0 改动；host 697/697 通过。

**结论**：F-03 关闭，符合附录 E §E.4。

### F-04 例外元数据与 `pending-*`（已关闭）

- `load_port_location_exceptions()` 新增：`id` 非空且唯一；`owner`/`reason`/`close_condition`/`evidence` 去空白后非空；任一失败 → `ValueError` → `main()` **exit 2**。保留精确 `path`、非空 `symbols`、`kind` 枚举、`accepted-location-exception`/`pending-*` 状态校验。
- `main()` 在 `violations` 检查后新增：**任何** `port_pending` 非空 → **exit 1**，并逐条打印 `PORT PENDING <id> (<status>, used=<n>)`；`used && status != accepted` 路径仍在 `_match_port_exception()` 中失败。
- 手工实测：`missing-owner`/`missing-close-condition`/`missing-evidence`/`missing-id`/`duplicate-id` → **exit 2**（消息分别指名 `owner`/`close_condition`/`evidence`/`id`/`duplicate id`）；`missing-reason` 手工负例 → **exit 2**（`reason must be non-empty`）；`pending-unused` → **exit 1**（`port_pending=1 port_pending_used=0`）；既有 `pending`（used）→ **exit 1**（同时报 D-11 与 pending）。
- 6 类新增负例 fixture 全部在 `test_check_layering.py` 中被断言；**22/22 OK**。JSON 报告保留 `port_pending_exceptions`/`port_exceptions_unused`，供审计。

**结论**：F-04 关闭，符合附录 E §E.5 / 附录 E §E.1 的 CLI 契约。

### F-05 陈旧文件头（已关闭）

- `contracts/CryptoPort.ets`：已替换为“Moved to contracts/CryptoPort.ets by T-23 / wp-090-ports … historical T-07/T-19 location exception is closed; do not reintroduce a copy under service/crypto/**.”。
- `contracts/PreferencesStore.ets`：已替换为“Moved to contracts/PreferencesStore.ets by T-23 … historical T-08 location exception is closed; do not reintroduce a copy under service/storage/**.”。
- 两文件本次 diff 均为注释-only，无接口/字段变化；与附录 E §E.6 文本一致。

**结论**：F-05 关闭。

### F-06 报告勘误（已关闭；附 RR-03 文档一致性）

- §1 结论行“理由见 §6.1” → **§7.1**；§2 `PORT-LOC-01` 行“理由 §6.1” → **§7.1**。
- §2.1 已改为“`common/**`、`model/**`，以及 **type-only 且无环**的同层 `contracts/**`（T-23 F-02 裁定…）”，与 checker/裁定一致。
- §7.2 ohosTest 清单已补 `LoggerPort×2`，并明确“9 条失效模块 + `RandomPort` + `LoggerPort×2` = 7 文件/12 条”。
- §10 新增 wp-093 执行记录（F-01..F-07、ohosTest 清单、9 项验证矩阵、残余）。
- **遗留（RR-03）**：文首“结论先行”仍写“layering 12/12”“八项必跑命令”，而 §10.3 已是 **22/22** 且增加了 ohosTest 第 9 项；§7.2 的 ohosTest 行仍写“仍有 7 文件/12 条旧路径 import … 设备测试编译会失败”、D-12 行仍写“白名单保留历史条目 … 后续 DES-B 同步任务退休”，与 §10.1 的“已修复/已从 live allowlist 删除”形成时间线混读。两处均指向 §10，不影响代码结论，建议下次文档同步时统一为“wp-090 历史快照 + wp-093 结果”或直接更新现状。

**结论**：F-06 的指定勘误项关闭；RR-03 为非阻塞报告一致性问题。

### F-07 allowlist policy 与 D-12 退休（已关闭）

- `layering_allowlist.json` 的 `policy` 与附录 E §E.6 文本**逐字一致**（已比对）：明确 7 条 retired、6 条 active、PORT-LOC-01 保留、`VmTimerPort` 为 VM-local seam、C-28 app seam 归属、端口例外不扩张 D-12。
- `entries` 由 13 条 prune 为 **6** 条：`T20-D12-06/07/08/11/12/13`；`exceptions_used=6`、`unused_exceptions=[]`（由 22/22 测试与本次运行确认）。
- `port_location_exceptions` 仅 **PORT-LOC-01**：`ClockPort`/`IdPort`、`kind=port-only`、`status=accepted-location-exception`，`owner`/`reason`/`close_condition`/`evidence` 齐全；`port_exceptions_used=0` 与 `used=0` 一致。
- 备注：policy 原文按 E.6 只列 `owner`/`close_condition`/`evidence`，未写 E.5 同时强制的 `reason` 非空与 `id` 唯一；checker 已实际强制二者（手工 `missing-reason` exit 2 为证）。这是 E.6 文本自身的省略，不构成实现偏离；如需完全自描述可在后续文档任务补齐。

**结论**：F-07 关闭。

### ohosTest import 修复（已关闭）

- 7 个文件、**12 条原失效 import**（9 条失效模块 + `RandomPort` + `LoggerPort`×2）全部修复；`BleCharacteristicRef` 与 `BlePermissionGate` 的混合语句按符号拆分为 `model/ProvisioningModels` 与 `contracts/BleProvisioningPorts`，故实际新增 13 条 import 语句，原失效语句计数仍为 12。
- 符号归属逐项核对：`SupportedLocale`/`I18nParams`/`LocaleMode` → `model/I18nModels`；`HttpRequest`/`TlsPolicy` → `model/GatewayTransportModels`；`SecretAlias` → `common/types/SecretAlias`；`RdbTransaction` → `contracts/RdbStore`；`BlePermissionGate` → `contracts/BleProvisioningPorts`；`BleCharacteristicRef` → `model/ProvisioningModels`；`GattEndpointMap` → `model/GattEndpointMap`；`RandomPort`/`LoggerPort` → `contracts/Ports`；`DiscoverApplyOptions` → `model/DeviceRecord`。
- 7 个文件的 diff **仅 import 行**，无断言/测试体/语义改动；旧路径精确检索 **0 命中**；ohosTest 相对 import **0 missing**（本次解析 123 条；报告写 122 条，差 1 条为计数口径差异，不改变 0 missing 结论）。
- `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` **BUILD SUCCESSFUL**；设备运行仍 BLOCKED。

**结论**：ohosTest import 修复关闭（编译级）；设备执行不在本任务范围。

### diff 完整性（已核对）

- 46 个路径全部在声明的 main/test/ohosTest/tools/contract/报告范围内；无 DES、协议资产、构建配置或签名变更。
- 无删除/重命名；无测试断言削弱（host 仅 import 行，ohosTest 仅 import 行；checker 自测仅新增用例）。
- 无静默签名变化：`TimerPort`/`SceneTimerPort`/`VmTimerPort`/`CryptoPort`/`PreferencesStore` 为注释-only；`PermissionPort` 的重命名为附录 E §E.4 明确指令；`BleProvisioningViewModel`/`PermissionGate` 仅按裁定改符号/类型。
- 无新增 `TODO`/`FIXME`；`git diff --check` 无空白错误。

---

## 4. Findings

> 严重度按“对本次裁定修复结论/门禁可信度的实际影响”评定。以下均非阻塞；未发现需要 `CHANGES_REQUIRED` 的代码/契约缺陷。

| ID | 严重度 | 位置 | Finding / 影响 | 建议 |
|---|---|---|---|---|
| **RR-01** | **Low（潜在 checker 覆盖缺口）** | `tools/contract/check_layering.py:80-83`（`EXPORT_FROM_RE`）；手工 `export-star` 负例 | `export * from './B'` 未被 `EXPORT_FROM_RE` 匹配（该正则的 `\*\s+from` 后仍要求第二个 `from`），因此不会产生 D-03 记录、也不进入 contracts 环图；手工 fixture 实测 PASS/exit 0。当前仓库无 `export * from`，且该解析器行为在 `76c47f4` 前已存在；E.3 列举的值/副作用/namespace 值导入与 4 类 fixture 均已覆盖。影响：未来若在 `contracts/**` 使用 `export * from`，type-only/无环门禁可被静默绕过。 | 修复 `EXPORT_FROM_RE`（区分 `export * from` 与 `export type *`/`export {…} from`），把 `export * from` 作为值再导出报 D-03；补 `export-star-bad` fixture（及如 ArkTS 支持，`export type *` 正例）。可作为紧随的 bounded checker 任务。 |
| **RR-02** | **Low（诊断精度，既有）** | `tools/contract/check_layering.py:245-265, 764-766` | ① `parse_imports()` 用 `^\s*import` 的 match.start() 计算行号，`\s*` 可跨换行吞掉文件头注释，导致首个 import 报为第 1 行（实测 `MigrationPort.ets` 实际第 10 行、解析为 1；`GatewayTransportPorts.ets` 首条同样为 1）。② 环违规用 `cycle[0]` 作为 path、用闭合边 `record.line/spec` 作为位置，出现 `A.ets:1 ./A`（`./A` 实际写在 B.ets）的错位。门禁判定与退出码不受影响，消息仍含完整环路径。 | 以 `import` 关键字位置而非 match 起点计算行号；环违规改用闭合边 `source_file/line`，或把环上每条边的 path/line 一并输出。修 fixture 断言以锁定正确行号。 |
| **RR-03** | **Low（报告一致性）** | `artifacts/50-implementation/t23-ports-migration.md:12,198-199` | 文首仍写“layering 12/12”“八项必跑命令”，与 §10.3 的 22/22 和新增 ohosTest 第 9 项不一致；§7.2 仍写 ohosTest“仍有 7 文件/12 条旧路径 import…设备测试编译会失败”、D-12“白名单保留历史条目…后续退休”，而 §10.1 已修复 ohosTest 并从 live allowlist 删除 7 条。读者若只看 §7 会误判当前状态；§10 有指向，故不影响裁定结论。 | 将 §7.2 行改为“wp-090 当时状态；wp-093 已修复见 §10”；文首补“wp-093 后 layering 22/22、新增 ohosTest 编译”，或把文首明确标注为 wp-090 快照。 |
| **RR-04** | **Info（provenance）** | `tools/contract/check_layering.py:877`；`tools/contract/layering_allowlist.json:4-5` | checker 的 `render_report()` 仍输出 `"task": "T-23 / wp-090-ports"`，allowlist 的 `producer`/`task` 也仍是 wp-090，尽管本次 wp-093 修改了二者；文件头 docstring 已写“wp-093 fixes”。不影响判定，但 JSON 报告/白名单元数据可能与实际修改任务不一致。 | 更新 `render_report()` 的 task、allowlist 的 `producer`/`task`，或增加 `updated_by: wp-093-t23-fixes`；保持历史 provenance 时可接受现状，但建议在报告/Stage Gate 中注明。 |

**无发现**（已逐项排除）：签名/错误码静默变化；测试断言削弱；越界产品代码改动；新增 TODO/FIXME；秘密/构建产物入库；把 `COMPILED_ONLY`/`BLOCKED` 写成 PASS。

---

## 5. 残余风险、未执行项与后续任务

| 项 | 状态 | 影响/归属 |
|---|---|---|
| `PORT-LOC-01`（`ClockPort`/`IdPort` 留在 `common/types/Ports.ets`） | **OPEN（已登记）** | 关闭条件不变：需批准的 D-01 或冻结签名变更；live `port_location_exceptions` 仅此 1 条，`used=0`；不得写成“17 条全关闭” |
| 设备/模拟器 ohosTest、真实 BLE/LAN/云/TLS | **BLOCKED / NOT RUN** | 本任务只做编译与静态/host 验证；设备矩阵需另立任务 |
| `export * from` 的 D-03/环覆盖（RR-01） | **潜在工具债（未修复）** | 当前仓库无使用；建议紧随 checker 任务修复并补 fixture |
| DES-B §23.7/§12.1.1 仍写“代码重命名待 bounded implementation task”；DES-A §27.6.4 F-03 行仍写“符号重命名待实现任务” | **STALE（文档，写范围外）** | `cc2233d` 已落地重命名；后续 DES 同步任务应改为“已落地”，Stage Gate 不得据此声称“无同名冲突”未裁定 |
| 7 条 retired D-12 | **已从 live allowlist 删除；DES-B §18.1 历史表保留** | Stage Gate 记录“6 active / 7 retired”；`check_layering` 0 violation ≠ D-12 完全收口 |
| `VmTimerPort` | **VM-local seam（DES-B §23.1 `EXT-DES-B-33`）** | 不在 `contracts/**`、不在端口例外；三分保留，不得合并/复制 |
| codelinter 25 warn、i18n 73 warning/16 hardcoded、crosscheck 14 findings | **既有基线** | 本次未新增 error/blocking；交各 Stage 处置 |
| 无签名配置 | **已知** | `assembleHap`/ohosTest 产物未签名；设备安装/运行未验证 |

**后续任务建议（按优先级）**：

1. **RR-01**：修复 `EXPORT_FROM_RE` 对 `export * from` 的覆盖，补正/负 fixture；随后重跑 layering + 22 项自测（预计变 23+）。
2. **RR-03/RR-04**：统一实现报告文首/§7.2 与 §10 的现状，更新 checker/allowlist 元数据或加 `updated_by`。
3. **DES 同步**：把 DES-B §23.7/§12.1.1、DES-A §27.6.4 的“待实现”状态更新为已落地；退休的 7 条 D-12 仅在历史表保留。
4. **设备测试**：在 ohosTest 编译通过的基础上安排设备/模拟器矩阵；真实 BLE/网关仍 BLOCKED。

---

## 6. 独立声明与裁决边界

1. 本复评由 `quality-reviewer` 独立完成；未参与 `wp-090-ports` 的实现、`wp-093-t23-fixes` 的修复或 `t23-ports-migration.md` §10 的撰写；未编辑任何被审代码、测试、checker、allowlist 或 DES 文本。唯一写入为 `artifacts/70-review/t23-rereview.md`（覆写 guard 前置占位）。
2. 评审基于 `cc2233d`（base `76c47f4`）与 handoff 冻结输入；6 个输入 SHA-256 与 handoff 一致；评审前工作树干净，复验后仍干净。
3. 复验命令均在本机实际执行：host 697/697、clean assembleHap BUILD SUCCESSFUL、codelinter 0 error/25 warn、layering files=221 violations=0 exceptions_used=6 port_pending=0、fixture 22/22、i18n blocking=0/missing=0、crosscheck hard ALL PASS、ohosTest BUILD SUCCESSFUL；补充 313 文件/2211 相对 import 0 missing、221 文件 1469 边 0 环、4 条 contracts 同层边全为 type-only。
4. **Verdict PASS 仅覆盖本报告 §1 的 revision 与范围**；不授予 Stage Gate、IG-3/IG-4 或用户验收；设备/真实 BLE/LAN/云/TLS 仍 BLOCKED；`PORT-LOC-01` 仍 OPEN；本 PASS 不等于 D-12 完全收口或 DES 文本已同步。
5. 未发现作者自审替代或越界改动；RR-01/RR-02 为既有工具债/诊断精度问题，RR-03/RR-04 为文档/元数据一致性；均不阻塞本次裁定修复的验收。

```text
STATUS: COMPLETE
SUMMARY: 独立复评 cc2233d（T-23 裁定修复，base 76c47f4）。F-01..F-07 与 ohosTest 7 文件/12 条 import 均按附录 E 落地并独立复现：host 697/697、clean assembleHap BUILD SUCCESSFUL、codelinter 0 error/25 warn、layering files=221 violations=0 exceptions_used=6 port_pending=0、fixture 22/22、i18n blocking=0/missing=0、crosscheck hard ALL PASS、ohosTest BUILD SUCCESSFUL；313 文件/2211 相对 import 0 missing、221 文件 1469 边 0 环；contracts 4 条同层边全为 type-only；手工负例验证值/副作用/namespace 值导入与环退出 1，F-04 五类畸形 exit 2、pending used/unused exit 1。Verdict PASS（仅限本 revision/范围）。
ARTIFACTS_CREATED: artifacts/70-review/t23-rereview.md
ARTIFACTS_UPDATED: artifacts/70-review/t23-rereview.md（覆写 guard 占位）
RISKS: RR-01 export * from 未被 EXPORT_FROM_RE 捕获（潜在 D-03/环覆盖缺口，当前无使用，非阻塞）；RR-02 行号/环违规 path 诊断错位（既有，非阻塞）；RR-03 实现报告文首/§7.2 与 §10 状态不一致（非阻塞）；RR-04 checker/allowlist 元数据仍标 wp-090（Info）；PORT-LOC-01 OPEN；设备/真实 BLE/LAN/云/TLS BLOCKED；DES-B §23.7/§12.1.1 与 DES-A §27.6.4 仍写“代码重命名待实现任务”（文档 STALE）
VALIDATION: host 697/697 exit 0（3068.9 ms）；clean assembleHap BUILD SUCCESSFUL 14 s 753 ms exit 0；codelinter Errors 0/Warns 25 exit 0；check_layering files=221 violations=0 exceptions_used=6 pending=0 port_exceptions_used=0 port_pending=0 exit 0；test_check_layering Ran 22 OK exit 0；i18n blocking=0 warnings=73 missingKeys=0 hardcoded=16 exit 0；crosscheck hard ALL PASS 14 findings exit 0；ohosTest BUILD SUCCESSFUL 13 s 300 ms exit 0；相对 import 0 missing；221 文件 0 环；手工 D-03 值/副作用/namespace 值/环与 F-04 schema/pending 负例均符合预期
NEEDS_CLARIFICATION: none（RR-01/RR-03/RR-04 可在后续 bounded 任务处理；不阻塞本次 PASS）
NEXT_ACTION: 保留本 PASS 作为 cc2233d 的独立评审证据；随后按优先级处理 RR-01（checker export-star fixture）、RR-03/RR-04（报告/元数据）、DES 状态同步与设备测试；Stage Gate 记录 PORT-LOC-01 OPEN、D-12 6 active/7 retired、设备 BLOCKED
```
