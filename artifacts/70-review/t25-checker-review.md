# T-25 检查器 RR-01/RR-02/RR-04 修复独立复审

- **Artifact ID**: T25-CHECKER-REVIEW
- **Producer**: agent:quality-reviewer
- **Task**: `wp-102-checker-review`（Handoff `state/handoffs/wp-102-checker-review.json`）
- **Role**: quality-reviewer（未参与 `wp-101-checker-rr` 的实现；只读复审，唯一写入为本报告）
- **Reviewed revision**: `16b0f7c99a06ee773772df779ed5963373087617`（`fix(contract): 补齐 export* 检查与诊断行号`；base `b7e1e24c7a18c135b971359232e368c10d62b763`，分支 `task/wp-101-checker-rr`）
- **Parent branch**: `feat/yaocore-app`
- **Review scope**: `tools/contract/`（15 个变更路径：3 M + 12 A）、`artifacts/50-implementation/t25-checker-rr.md`
- **Workflow**: STANDARD / GATED_AUTO
- **Date**: 2026-10-18
- **Verdict**: **PASS（仅限 `16b0f7c` 与本次范围）** —— RR-01/RR-02/RR-04 的修复均可独立复现，6 项必跑命令全部 exit 0，自测 27/27；未发现阻塞项。本 PASS 不授予 Stage Gate、合并批准或用户验收
- **Status**: COMPLETE

> **结论先行**：`check_layering.py` 现已把 `export * from`、命名值再导出、`export type {…} from`、`export type * from`、`export * as ns from` 纳入 D-03 判定；`contracts/**` 同层值再导出 exit 1、type-only 放行，且全部再导出边进入无环图。行号改由 `import`/`export` 关键字位置计算，真实文件 `MigrationPort.ets:10`、`GatewayTransportPorts.ets:22` 与 fixture 断言一致；环诊断的 path/line/spec 指向闭合边自身。RR-04 的 `updated_by`/policy provenance 已落地且不改变 schema 与退出码语义。独立实测：fixture 自测 **27/27**、layering `files=221 violations=0`、host **697/697**、clean assembleHap **BUILD SUCCESSFUL**、crosscheck **hard ALL PASS**、i18n **blocking=0**；另以 19 个临时正/负例复核解析、行号、环与元数据。剩余均为非阻塞的工具健壮性/测试覆盖提示。

---

## 1. 范围、revision、输入与独立性

| 项 | 本次结论 | 证据 |
|---|---|---|
| 仓库 / 分支 | `/home/quirkybrain/code/harmony-projects/YaoCore`；`task/wp-101-checker-rr` | `git branch --show-current` |
| Reviewed HEAD | `16b0f7c99a06ee773772df779ed5963373087617` | `git rev-parse HEAD` |
| Base / commit parent | `b7e1e24c7a18c135b971359232e368c10d62b763` | `git log --oneline -2`；`16b0f7c^` |
| 工作树 | 评审前干净；复验后仍干净（构建产物被忽略） | `git status --short` |
| 变更范围 | `b7e1e24..16b0f7c` 共 **16** 个路径：**3 M + 13 A + 0 D**；全部在 `wp-101` 声明的 `tools/contract/`、`artifacts/50-implementation/` 写范围内 | `git diff --name-status` |
| 输入完整性 | 5 个 handoff 输入 SHA-256 全部一致 | `sha256sum` 对照 handoff |
| 作者独立性 | 未参与 `wp-101-checker-rr` 实现；未编辑被审代码、fixture、allowlist 或实现报告；唯一写入为 `artifacts/70-review/t25-checker-review.md` | 本任务 `writes`/`commit_paths` 仅 `artifacts/70-review/` |
| 评审限制 | 未运行设备/模拟器；未用 ArkTS 编译器验证 `export type *` 语法；未重跑 codelinter/ohosTest（本任务未改产品代码） | 见 §6 |

**输入 SHA-256 核对**：`t25-checker-rr.md` `f6f19674…`、`t23-rereview.md` `f1bc436e…`、`check_layering.py` `bd6c23a3…`、`layering_allowlist.json` `b9ad9596…`、`test_check_layering.py` `ffa8b31e…`，均与 `wp-102-checker-review.json` 一致。

**变更清单核对**：3 个修改文件（`tools/contract/check_layering.py`、`layering_allowlist.json`、`test_check_layering.py`）、13 个新增文件（4 个 fixture 目录共 12 文件 + `t25-checker-rr.md`）。无删除/重命名/权限位变化；`git diff --check b7e1e24..16b0f7c` 无输出。

**不在本次范围**：设备/真实 BLE/LAN/云/TLS；DES 文本同步；RR-03（实现报告历史章节一致性）；Stage Gate 与用户验收。

---

## 2. 独立复验矩阵（cwd = 仓库根，2026-10-18 实际执行）

| # | 命令 | 本次实测 | 退出码 |
|---|---|---|---|
| 1 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/test_check_layering.py` | **Ran 27 tests / OK**（2.419 s；原 22 + 新增 5） | 0 |
| 2 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | `files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0`；PASS | 0 |
| 3 | `entry/src/test/run-host-tests.sh` | **tests 697 / pass 697 / fail 0 / skipped 0**（3062.6 ms） | 0 |
| 4 | `hvigorw clean assembleHap --no-daemon` | **BUILD SUCCESSFUL in 14 s 664 ms**；35 tasks（34 executed / 1 up-to-date）；unsigned HAP | 0 |
| 5 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py` | **hard checks: ALL PASS**；14 条既有 frozen-input findings | 0 |
| 6 | `PYTHONDONTWRITEBYTECODE=1 python3 entry/src/test/i18n/check_i18n.py --strict-ui` | `blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16` | 0 |

**补充独立核对（未入库）**：

- 4 个新 fixture 逐一以 CLI 运行：`export-star-bad` / `export-named-value-bad` → exit 1（D-03，行 4 / 行 2）；`export-type-star-ok` / `export-named-type-ok` → exit 0（PASS）。
- 既有 `cycle-bad` fixture → exit 1，诊断为 `entry/src/main/ets/contracts/B.ets:1 ./A`，环路径 `A.ets -> B.ets -> A.ets`。
- 真实仓库 `contracts/**` 同层边：`MigrationPort.ets:10`（`./RdbStore`）、`GatewayTransportPorts.ets:22`（`./GatewayPorts`）、`RoomPorts.ets:9`、`ScenePorts.ets:9`；均为 `kind=type`，与实际行号一致。
- 临时目录 `/tmp/opencode/wp-102-negatives/` 下 19 个正/负例全部符合预期（详见 §3/§4）。

---

## 3. RR-01：`export * from` 与再导出的 D-03/环覆盖（已关闭）

### 3.1 语法覆盖

| 语句（`contracts/**` 同层） | 分类 | 实测结果 |
|---|---|---|
| `export * from './Base'`（第 4 行，前置 3 行注释） | value | **exit 1**；`Bad.ets:4 ./Base`；D-03 same-layer type-only 消息 |
| `export { Base } from './Base'` | value | **exit 1**；`Bad.ets:2 ./Base` |
| `export type { Base as Renamed } from './Base'` | type | **exit 0**（PASS） |
| `export type * from './Base'` | type | **exit 0**（PASS） |
| `export * as NS from './Base'` | value | **exit 1**；`Bad.ets:2 ./Base` |
| `export type * as NS from './Base'` | type | **exit 0**（PASS） |

值/type-only 判定与 `EXPORT_FROM_RE` 的 `kind` 分支一致；D-03 分支（`source_layer == contracts` 且 `target_layer == contracts` 且 `kind != type`）正确复用。命名再导出使用 `_parse_named()` 解析符号，`export *` 保持空符号集。

### 3.2 再导出边进入环检测（含 type-only）

临时副本 `type-cycle`：

```text
A.ets: export type { B } from './B';
B.ets: export type { A } from './A';
```

实测 **exit 1**，输出：

```text
D-03 entry/src/main/ets/contracts/B.ets:2 ./A -- contracts/** type-only import cycle: A.ets -> B.ets -> A.ets
```

证明 type-only 再导出边参与 DFS，且诊断位置为闭合边自身。`mixed-cycle`（A type-only、B 值再导出）同样 exit 1；除值边 D-03 外，环诊断也指向 `B.ets:2 ./A`。

### 3.3 Fixture 与负例真实性

- 4 个新 fixture 目录（每目录 `allowlist.json` + 2 个 `.ets`，共 12 文件）均被 `test_check_layering.py` 通过子进程真实调用；本次逐目录 CLI 复核结果与断言一致（§2）。
- `export-star-bad` 的 3 行注释用于锁定 RR-02 行号：实际断言 `contracts/Bad.ets:4 ./Base`。
- 临时负例另覆盖：`export * as NS`、命名值/type 再导出、type-only 环、值/type 混合环、注释内导出、块注释后行号、多行 `import type`、值导入。
- **原 22 条测试未被削弱**：`git show b7e1e24:tools/contract/test_check_layering.py` 中 `def test_` 计数为 22；当前 27 条中新增 5 条（4 个 fixture + 1 个临时目录再导出环），既有 `cycle-bad` 仅新增一条 path/line 断言。

---

## 4. RR-02：行号与环诊断精度（已关闭）

1. **行号根因修复**：`IMPORT_RE`/`EXPORT_FROM_RE` 分别以 `import_kw`/`export_kw` 的 `match.start()` 计算行号，不再受 `^\s*` 在 `MULTILINE|DOTALL` 下跨行吞掉文件头注释的影响。
2. **真实文件抽查**（直接调用 `parse_imports()`，非仅看报告）：
   - `entry/src/main/ets/contracts/MigrationPort.ets` 的 `./RdbStore` → **line 10**（`nl` 确认第 10 行）；
   - `entry/src/main/ets/contracts/GatewayTransportPorts.ets` 的 `./GatewayPorts` → **line 22**（`nl` 确认第 22 行）；
   - 同文件多行 `import type { … }` 从第 14 行开始，解析行号为 14。
3. **环诊断**：改为使用闭合边 `record.source_file` + `record.line` + `record.spec`；`cycle-bad` 实测 `B.ets:1 ./A`，新增 type-only 再导出环实测 `B.ets:2 ./A`，均与闭合边实际书写位置一致，未再出现 `cycle[0]` 与闭合边位置错配。
4. **无回归**：27/27 测试通过；多行 import、`import type`、注释遮蔽（行注释/块注释）均实测正常。

---

## 5. RR-04：`updated_by` 与 policy provenance（已关闭）

- `render_report()` 新增 `"updated_by": ["wp-093-t23-fixes", "wp-101-checker-rr"]`；`producer`/`task` 保留 `agent:test-engineer` / `T-23 / wp-090-ports` 作为历史 provenance。
- `layering_allowlist.json` 新增同名顶层 `updated_by` 数组；`policy` 末尾追加 “Provenance: created for T-23 / wp-090-ports; updated by wp-093-t23-fixes (F-01..F-07) and wp-101-checker-rr (RR-01/RR-02/RR-04).”。
- **Schema/退出码未破坏**（独立实测）：
  - 顶层为数组 `[]` → **exit 2**；
  - `port_location_exceptions` 为对象 `{}` → **exit 2**；
  - JSON 畸形 → **exit 2**；
  - 缺少 `owner` 的 port exception（保留 `updated_by`）→ **exit 2**，消息 `port exception P-1 owner must be non-empty`。
- 真实仓库 `--report` 输出字段完整：`updated_by` 正确，`producer=agent:test-engineer`、`task=T-23 / wp-090-ports`、`file_count=221`、`violation_count=0`、`exceptions_used_count=6`、`port_exceptions_used_count=0`；既有报告消费者仅读取 `violation_count` 等字段，未发现对新键的破坏。
- `test_check_layering.py` 文首 provenance 已同步为 `Tasks: T-23 / wp-093-t23-fixes, wp-101-checker-rr`。

---

## 6. 正确性边界、残余与报告一致性

### 6.1 已知保守/解析边界

1. **`export { type A } from './B'`**：当前按 value 处理，可能在 `contracts/**` 同层产生误报（exit 1）。实现报告 §4 已披露；仓库当前无该语法（grep 0 命中）。`import { type A }` 亦沿用同一保守行为（既有，非本次引入）。
2. **`export * from` 的保守性**：即使源文件只导出类型，也按 value 再导出处理；这是 RR-01 要求的保守门禁语义，已披露。
3. **无空白形式**：`export{Base}from './Base'`、`export*from './Base'` 因 `export\s+` 要求空白而不被匹配（临时探针实测 PASS/exit 0）。属既有格式化假设，仓库当前无使用；建议未来以 tokenizer 或补充负例消除该旁路。
4. **`export type *` / `export type * as NS`**：仅证明解析器分类正确，未证明 ArkTS 编译器接受该语法；实现报告 §4 已披露，当前仓库未使用。
5. **值再导出环的诊断文案**：值边环会同时产生 D-03 value 与 “type-only import cycle” 两条消息（`mixed-cycle` 实测 2 violations）。path/line/spec 正确；文案沿用既有逻辑（所有边到达该处时要么 type-only，要么已单独报 value），不影响 exit code。
6. **文本级解析器**：字符串/模板内的 `export ... from` 理论上有命中风险；属既有解析器限制，非本次回归。

### 6.2 `t25-checker-rr.md` 一致性核对

| 项 | 报告值 | 本次实测 | 结论 |
|---|---|---|---|
| 新增 fixture | 4 组（每组 3 文件） | 4 组 / 12 文件 | 一致 |
| 自测数 | 22 → 27 | 27（旧 22 + 新 5） | 一致 |
| layering | files=221 violations=0 exceptions_used=6 pending=0 | 同左 | 一致 |
| host | 697/697 | 697/697 | 一致 |
| build | BUILD SUCCESSFUL | BUILD SUCCESSFUL（14 s 664 ms） | 一致（耗时随环境波动） |
| crosscheck | hard ALL PASS；14 findings | 同左 | 一致 |
| i18n | blocking=0 warnings=73 missingKeys=0 hardcoded=16 | 同左 | 一致 |
| 真实行号 | MigrationPort:10 / GatewayTransportPorts:22 | 同左 | 一致 |
| 临时负例 | star/命名值 exit 1；type-only exit 0；环 `B.ets:2 ./A` | 全部复现 | 一致 |

报告未把 `COMPILED_ONLY`/`BLOCKED` 写成 PASS；残余与限制章节与实现一致。

### 6.3 残余风险

| 项 | 状态 | 影响/归属 |
|---|---|---|
| `export * as ns` 无永久 fixture | **测试覆盖缺口（Low）** | 实现已正确，手工探针已验证；建议后续加 fixture 锁定 |
| 无空白 `export{…}from` 旁路 | **既有解析边界（Info）** | 当前无使用；未来统一 tokenizer 更稳 |
| `export { type A }` / `import { type A }` 保守按值 | **已知保守（Info）** | 可能误报；当前无使用，报告已披露 export 侧 |
| `export type *` 未经 ArkTS 编译器验证 | **未验证（Info）** | 仅解析器正例；不代表编译器支持 |
| `updated_by`/policy 无自动断言 | **测试覆盖（Info）** | 本次手工验证；不影响判定 |
| `PORT-LOC-01`（`ClockPort`/`IdPort`） | **OPEN（已登记）** | 非本次范围 |
| 设备/真实 BLE/LAN/云/TLS | **BLOCKED / NOT RUN** | 本任务仅工具/静态/主机侧验证 |

---

## 7. Findings

> 以下均**非阻塞**；未发现需要 `CHANGES_REQUIRED` 的代码、D-03 判定或元数据缺陷。

| ID | 严重度 | 位置 | Finding / 影响 | 建议 |
|---|---|---|---|---|
| **V-01** | Low（测试覆盖） | `tools/contract/test_check_layering.py:174-231`；fixture 目录 | `export * as ns from` 已由新正则覆盖且本次临时探针 exit 1，但无永久 fixture/断言；未来改动可能回归而不被自测捕获。 | 在后续 bounded checker 任务中补 `export-star-as-ns-bad` fixture（值）及如需的 `export type * as ns` 正例。 |
| **V-02** | Info（既有解析边界） | `EXPORT_FROM_RE` / `IMPORT_RE` 的 `\s+` | `export{Base}from './Base'` 等无空白形式不被匹配；当前仓库无使用，且既有 import 解析同样有此假设。 | 长期可改用轻量 tokenizer；短期在报告中保留说明。 |
| **V-03** | Info（保守误报） | `_parse_named()` / `EXPORT_FROM_RE` | `export { type A } from` 与 `import { type A }` 按值处理；若未来在 `contracts/**` 使用会产生 D-03 误报。实现报告已披露 export 侧，import 侧未单列。 | 保持保守门禁；必要时扩展 inline type 说明符识别并补正例。 |
| **V-04** | Info（诊断文案） | `_contract_import_cycles()` 消息 | 值再导出环同时报 value D-03 与 “type-only import cycle”；位置正确，文案沿用既有逻辑。 | 可在消息中区分 “value/type-only cycle”，非必需。 |
| **V-05** | Info（编译器验证） | `export-type-star-ok` fixture | `export type *` 仅解析器级正例，未由 ArkTS 编译器验证；当前仓库未使用。 | 保持部署前不引入该语法；如采用先在目标 SDK 编译验证。 |
| **V-06** | Info（元数据测试） | `render_report()` / allowlist | `updated_by` 与 policy provenance 无自动断言；本次已手工验证其输出与 schema 兼容。 | 可在测试中加一条 report 元数据断言。 |

**无发现（已逐项排除）**：值再导出漏报；type-only 再导出误拒；再导出边未入环；行号仍为 1；环 path/line/spec 错配；`updated_by` 破坏 allowlist schema；缺失/畸形 allowlist 未 exit 2；测试断言削弱；越界产品代码改动；新增 TODO/FIXME；把 BLOCKED 写成 PASS。

---

## 8. 独立声明与裁决边界

1. 本复审由 `quality-reviewer` 独立完成；未参与 `wp-101-checker-rr` 的实现或 `t25-checker-rr.md` 的撰写，未编辑任何被审代码、fixture、allowlist 或测试。唯一写入为 `artifacts/70-review/t25-checker-review.md`（覆写 guard 前置占位）。
2. 评审基于 `16b0f7c`（base `b7e1e24`）与 handoff 冻结输入；5 个输入 SHA-256 与 handoff 一致；评审前工作树干净，复验后仍干净。
3. 复验命令均在本机实际执行：fixture 自测 27/27、layering files=221 violations=0、host 697/697、clean assembleHap BUILD SUCCESSFUL、crosscheck hard ALL PASS/14 findings、i18n blocking=0/missingKeys=0；补充 19 个 `/tmp/opencode` 临时正/负例、4 个 fixture 逐一 CLI 运行、真实文件行号与 `--report` 元数据核对。
4. **Verdict PASS 仅覆盖 §1 的 revision 与范围**；不授予 Stage Gate、`feat/yaocore-app` 合并批准或用户验收；设备/真实 BLE/LAN/云/TLS 仍 BLOCKED；`PORT-LOC-01` 仍 OPEN；RR-03 与 DES 状态同步不在本次范围。
5. 未发现作者自审替代或越界改动；V-01..V-06 均为非阻塞的测试覆盖/解析边界/文案/验证提示，不影响 RR-01/RR-02/RR-04 的关闭结论。

```text
STATUS: COMPLETE
SUMMARY: 独立复审 16b0f7c（检查器 RR-01/RR-02/RR-04 修复，base b7e1e24）。export*/命名/type-only 再导出 D-03 与环覆盖、 import/export 真实行号、环闭合边 path/line/spec、updated_by/policy provenance 与 schema 退出码均独立复现；自测 27/27、layering files=221 violations=0、host 697/697、build SUCCESSFUL、crosscheck hard ALL PASS、i18n blocking=0；另以 19 个临时正/负例复核。Verdict PASS（仅限本 revision/范围）。
ARTIFACTS_CREATED: artifacts/70-review/t25-checker-review.md
ARTIFACTS_UPDATED: artifacts/70-review/t25-checker-review.md（覆写 guard 前置占位）
RISKS: V-01 export * as ns 无永久 fixture（Low）；无空白 export{…}from 旁路（既有）；export/import 内联 type 说明符保守按值（潜在误报）；export type * 仅解析器级未编译验证；值再导出环文案仍写 type-only（Info）；updated_by 无自动断言（Info）；PORT-LOC-01 OPEN；设备/真实 BLE/LAN/云/TLS BLOCKED
VALIDATION: test_check_layering 27/27 OK exit 0（2.419 s）；check_layering files=221 violations=0 exceptions_used=6 pending=0 port_pending=0 exit 0；host tests 697/pass 697/fail 0 exit 0（3062.6 ms）；clean assembleHap BUILD SUCCESSFUL 14 s 664 ms exit 0；crosscheck hard ALL PASS、14 findings exit 0；i18n blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16 exit 0；4 个新 fixture 逐一 CLI 结果与断言一致；19 个临时正/负例全通过；真实行号 MigrationPort:10 / GatewayTransportPorts:22；--report updated_by 正确且 schema 兼容；畸形 allowlist/port exception 仍 exit 2
NEEDS_CLARIFICATION: none（V-01..V-06 均可在后续 bounded 任务处理，不阻塞本次 PASS）
NEXT_ACTION: 保留本 PASS 作为 16b0f7c 的独立评审证据；由 repository-manager 按 Git 策略将 task/wp-101-checker-rr 合并至 feat/yaocore-app；后续可补 export * as ns fixture、内联 type 说明符策略与 RR-03/DES 状态同步；Stage Gate 记录 PORT-LOC-01 OPEN、设备验证 BLOCKED
```
