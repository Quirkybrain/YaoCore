# T-25 checker 复评债务修复（RR-01 / RR-02 / RR-04）

- **Artifact ID**: T25-CHECKER-RR
- **Producer**: agent:implementation-engineer
- **Task**: `wp-101-checker-rr`（Handoff `state/handoffs/wp-101-checker-rr.json`）
- **Branch / base**: `task/wp-101-checker-rr` @ `b7e1e24c7a18c135b971359232e368c10d62b763`（父分支 `feat/yaocore-app`）
- **Inputs**: `artifacts/70-review/t23-rereview.md`（RR-01/RR-02/RR-04）、`tools/contract/check_layering.py`、`tools/contract/layering_allowlist.json`、`tools/contract/test_check_layering.py`（SHA-256 与 handoff 一致）
- **Write scope**: `tools/contract/`、`artifacts/50-implementation/`
- **Date**: 2026-10-18
- **Workflow**: STANDARD / GATED_AUTO
- **Status**: `COMPLETE`（实现与本地验证完成；待独立质量门禁，不自我签署）

> **结论先行**：RR-01/RR-02/RR-04 已全部修复。checker 现在识别 `export * from`、`export { a, b } from`、`export type { ... } from`、`export type * from`（及 `export * as ns from`），其中 `contracts/**` 同层的 `export *`/命名值再导出按 D-03 失败（exit 1），type-only 再导出放行且全部再导出边进入 contracts 无环图；行号改由 `import`/`export` 关键字位置计算，环违规改用闭合边自身的 `source_file/line/spec`。元数据新增 `updated_by: [wp-093-t23-fixes, wp-101-checker-rr]` 并在 allowlist policy 记录 provenance。自测 **22 → 27**；仓库 `files=221 violations=0`；全部 6 项必跑命令 exit 0；host **697/697**；手工负例确认 `export *`/命名值再导出 exit 1、type-only 再导出 exit 0。

---

## 1. 修复内容

### RR-01 `export * from` 的 D-03 与环覆盖缺口

**位置**：`tools/contract/check_layering.py`

- 重写 `EXPORT_FROM_RE`：不再要求 `* from` 后出现第二个 `from`，统一匹配公共 `\s*from\s*'<spec>'` 尾部；分支覆盖：
  - `export * from './B'` → `kind=value`（值再导出）；
  - `export * as NS from './B'` → `kind=value`（运行时命名空间值）；
  - `export { a, b } from './B'` → `kind=value`；
  - `export type { a, b } from './B'` → `kind=type`；
  - `export type * from './B'` / `export type * as NS from './B'` → `kind=type`。
- 命名再导出现在解析 `symbols`（`_parse_named`），与 import 语义一致；`export *` 保持空符号集。
- D-03 复用既有分支：`source_layer == "contracts"` 且 `target_layer == "contracts"` 时，`kind != "type"` 即报
  `contracts/** same-layer imports must be type-only (import type/export type)` 并 exit 1。
- 所有 `export ... from` 记录与 import 记录一起进入 `_contract_import_cycles()`；type-only 再导出边同样参与 DFS（`_contract_import_cycles` 未按 kind 过滤）。仓库 221 文件仍 0 环。

**新增 fixture**（`tools/contract/fixtures/layering/`，每个含 `allowlist.json` + 2 个 `.ets`）：

| fixture | 语句 | 期望 |
|---|---|---|
| `export-star-bad` | `export * from './Base'`（第 4 行，前置 3 行注释） | D-03，exit 1 |
| `export-type-star-ok` | `export type * from './Base'` | PASS，exit 0 |
| `export-named-value-bad` | `export { Base } from './Base'` | D-03，exit 1 |
| `export-named-type-ok` | `export type { Base } from './Base'` | PASS，exit 0 |

**手工负例（临时副本，`/tmp/opencode/wp-101-negatives/`，未入库）**：

```text
star-bad          D-03 Bad.ets:4 ./Base ... same-layer imports must be type-only   EXIT=1
named-value-bad   D-03 Bad.ets:2 ./Base ... same-layer imports must be type-only   EXIT=1
named-type-ok     check_layering: PASS                                             EXIT=0
type-star-ok      check_layering: PASS                                             EXIT=0
```

### RR-02 行号诊断

**位置**：`tools/contract/check_layering.py` `parse_imports()` / `_contract_import_cycles()`

- `IMPORT_RE` 新增 `(?P<import_kw>import)`，行号改为
  `masked[:match.start("import_kw")].count("\n") + 1`；`EXPORT_FROM_RE` 同理使用 `export_kw`。
  根因是行首 `^\s*` 在 `re.MULTILINE | re.DOTALL` 下可跨换行吞掉文件头注释，旧实现用
  `match.start()` 会把首个 import 报成第 1 行。
- 环违规不再用 `cycle[0]` 作 path、闭合边 `record.line/spec` 作位置的错位组合，改为闭合边自身的
  `record.source_file` + `record.line` + `record.spec`；环路径仍完整输出在消息中。
- 实测仓库真实文件：`contracts/MigrationPort.ets` 同层 type 边 `./RdbStore` → **line 10**；
  `contracts/GatewayTransportPorts.ets` → **line 22**（与复评记录的实际行号一致）。
- fixture 断言：`export-star-bad` 断言 `contracts/Bad.ets:4 ./Base`；既有 `cycle-bad` 增加断言
  `contracts/B.ets:1 ./A`；新增 type-only 再导出环用例断言 `contracts/B.ets:2 ./A`。

### RR-04 元数据 provenance

**位置**：`tools/contract/check_layering.py`（docstring / `render_report()`）、`tools/contract/layering_allowlist.json`

- checker docstring 增加 `Updated: agent:implementation-engineer | Tasks: wp-093-t23-fixes, wp-101-checker-rr`，
  Status 补 `wp-101 checker debt`。
- `render_report()` 增加 `"updated_by": ["wp-093-t23-fixes", "wp-101-checker-rr"]`；
  保留原始 `producer`/`task`（`T-23 / wp-090-ports`）作为历史 provenance，不再让读者误以为元数据从未更新。
- `layering_allowlist.json` 增加同名顶层 `updated_by` 数组；`policy` 末尾追加
  `Provenance: created for T-23 / wp-090-ports; updated by wp-093-t23-fixes (F-01..F-07) and wp-101-checker-rr (RR-01/RR-02/RR-04).`
- 两处均为附加字段/文本：`_load_allowlist_payload()` 只校验顶层为对象，未知键被忽略；现有 schema 校验、
  退出码（0/1/2）与报告字段语义未变。
- `test_check_layering.py` 文首 provenance 同步为 `Tasks: T-23 / wp-093-t23-fixes, wp-101-checker-rr`。

---

## 2. 变更文件

| 文件 | 变更 |
|---|---|
| `tools/contract/check_layering.py` | `EXPORT_FROM_RE` 重写；行号改用关键字组；环违规 path/line 修正；`render_report()` 增加 `updated_by`；docstring provenance |
| `tools/contract/layering_allowlist.json` | 顶层 `updated_by`；policy 追加 provenance 说明 |
| `tools/contract/test_check_layering.py` | 新增 5 个用例（4 个 fixture + 1 个临时目录再导出环）；cycle 用例增加 path/line 断言；provenance 更新 |
| `tools/contract/fixtures/layering/export-star-bad/**` | 新增（3 文件） |
| `tools/contract/fixtures/layering/export-type-star-ok/**` | 新增（3 文件） |
| `tools/contract/fixtures/layering/export-named-value-bad/**` | 新增（3 文件） |
| `tools/contract/fixtures/layering/export-named-type-ok/**` | 新增（3 文件） |
| `artifacts/50-implementation/t25-checker-rr.md` | 本报告 |

未修改产品代码、host/ohosTest、DES、协议资产、构建配置或 i18n 资源；未切换分支、未 pull/merge/rebase/push。

---

## 3. 验证矩阵（cwd = 仓库根，本次实际执行）

| # | 命令 | 结果 | 退出码 |
|---|---|---|---|
| 1 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/test_check_layering.py` | **Ran 27 tests / OK**（2.367 s；原 22 → 新增 5） | 0 |
| 2 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | `files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0`；PASS | 0 |
| 3 | `entry/src/test/run-host-tests.sh` | **tests 697 / pass 697 / fail 0 / skipped 0**（3055.3 ms） | 0 |
| 4 | `hvigorw clean assembleHap --no-daemon` | **BUILD SUCCESSFUL in 14 s 931 ms**；35 tasks（34 executed / 1 up-to-date）；unsigned HAP | 0 |
| 5 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py` | **hard checks: ALL PASS**；14 条既有 frozen-input findings | 0 |
| 6 | `PYTHONDONTWRITEBYTECODE=1 python3 entry/src/test/i18n/check_i18n.py --strict-ui` | `blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16` | 0 |

负例/定向证据（临时副本，未入库）：

- `export * from` → D-03，exit 1；命名值再导出 → D-03，exit 1。
- `export type * from` / `export type { ... } from` → PASS，exit 0。
- type-only 再导出环（A ⇄ B）→ D-03 cycle，exit 1，路径 `A.ets -> B.ets -> A.ets`，位置 `B.ets:2 ./A`。
- 真实仓库同层边行号：`MigrationPort.ets:10`、`GatewayTransportPorts.ets:22`。

---

## 4. 残余与限制

1. **保守判定**：`export { type A } from './B'`（内联 type 说明符）未单独识别，按值再导出处理（可能误报）。
   当前仓库无该语法；如 ArkTS 后续采用，可再以 bounded 任务扩展。`export *` 即使源文件只导出类型也按值
   再导出处理，这是 RR-01 要求的保守门禁语义。
2. **fixture 非编译对象**：`export type *` 为解析器级正例，不证明 ArkTS 编译器接受该语法；当前仓库未使用。
3. **行号断言范围**：仅锁定本任务新增/既有 fixtures 的行号；未对 221 个产品文件逐条断言行号，但 checker
   全量运行 `violations=0`，且抽查两个真实文件行号正确。
4. **元数据历史保留**：`producer`/`task` 仍记录原始 `wp-090-ports`，最近修改通过 `updated_by` 与 policy
   provenance 表达；这是有意保留历史，不改变报告/allowlist 的判定语义。
5. **未执行**：设备/模拟器 ohosTest、真实 BLE/LAN/云/TLS、codelinter（本任务未改动产品代码，且不在必跑矩阵；
   如需 Stage Gate 证据，沿用既有基线 0 error/25 warn）。
6. **提交**：本报告随代码同次提交；commit hash 见 `swe_guard finish wp-101-checker-rr` 记录与本任务返回。

---

## 5. Traceability

- `artifacts/70-review/t23-rereview.md` RR-01 → §1「RR-01」、`check_layering.py` `EXPORT_FROM_RE`、
  4 个 fixture、5 个新用例；
- RR-02 → §1「RR-02」、`parse_imports()` 行号、`_contract_import_cycles()` path/line、3 处行号断言；
- RR-04 → §1「RR-04」、`render_report().updated_by`、allowlist `updated_by`/policy；
- DES-A §2.2 D-03 / 附录 E §E.3（contracts 同层 type-only + 无环）→ 上述实现与 fixtures；
- `test_check_layering.py` 22 → 27 用例；`check_layering` 0 violation；host 697/697。

```text
STATUS: COMPLETE
SUMMARY: 修复 RR-01 export* 再导出解析/D-03/环覆盖、RR-02 行号与环诊断位置、RR-04 checker/allowlist provenance；新增 4 个 fixture 与 5 个用例（22→27），全部验证 exit 0。
ARTIFACTS_CREATED: tools/contract/fixtures/layering/{export-star-bad,export-type-star-ok,export-named-value-bad,export-named-type-ok}/**（12 文件）; artifacts/50-implementation/t25-checker-rr.md
ARTIFACTS_UPDATED: tools/contract/check_layering.py; tools/contract/layering_allowlist.json; tools/contract/test_check_layering.py
DECISIONS: 保留 producer/task 历史值，用 updated_by + policy provenance 表达最近任务；export * 与命名值再导出按 D-03 失败，type-only 再导出放行并进入环图；环违规位置改为闭合边自身。
ASSUMPTIONS: `export type *` 作为解析器级语法处理；仓库当前无相关语句；附加 JSON 键不影响既有 loader/schema。
RISKS: 内联 `export { type A }` 保守按值处理（潜在误报，当前无使用）；fixture 不证明 ArkTS 编译支持 export type *；producer/task 仍为原始 wp-090（有意保留）。
VALIDATION: tests 27/27 OK exit 0；layering files=221 violations=0 exit 0；host 697/697 exit 0；clean assembleHap BUILD SUCCESSFUL exit 0；crosscheck hard ALL PASS exit 0；i18n blocking=0 missingKeys=0 exit 0；临时负例 export*/命名值 exit 1、type-only exit 0；真实行号 MigrationPort:10 / GatewayTransportPorts:22。
NEEDS_CLARIFICATION: none
NEXT_ACTION: 独立 quality-review 复核本任务；通过后由 repository-manager 合并 task/wp-101-checker-rr；RR-03 报告一致性与 DES 状态同步仍属其他任务。
```
