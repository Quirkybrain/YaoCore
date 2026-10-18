# i18n 修正聚焦复评（wp-099）

- **Producer**: agent:quality-reviewer
- **Task**: `wp-099-i18n-rereview`
- **Review target**: `9d22b5b2abe44bd03f6ee7de3714ec37a580ec9e`（`fix(i18n): 修正 triage 证据链与检查器校验`，`task/wp-096-i18n-triage`）
- **Base**: `818cb790bf6f94b44e9bee2839a5081ffc5a1dcb`
- **修正前被审**: `2d45628b3e0ac4fecb6660727103f1b61b8498d6`
- **原始预 triage 基线**: `07895fd98b222264aec566cefd43a0ee9cb10f5e`
- **Date**: 2026-10-18
- **Verdict**: **PASS**（仅覆盖本次 revision 与 §1 声明范围；不授予 Stage / Component Quality / 用户验收）
- **Reviewer**: `quality-reviewer`（未参与 `wp-096-i18n-triage` / `wp-098-i18n-fix` 实现）

## 1. 复评范围与 revision

| 项 | 值 |
|---|---|
| 复评 commit | `9d22b5b`（相对 `818cb79` 仅 1 个 commit） |
| 变更文件 | 5 个：`tools/i18n/triage_legacy.py`、`entry/src/test/i18n/legacy-migration.csv`、`entry/src/test/i18n/README.md`、`entry/src/test/i18n/migration-boundary.md`、`artifacts/50-implementation/t24-i18n-triage.md` |
| 复评对象 | F-01..F-05 闭环、§2 不变量、§3 回归；工具基线/负例行为；T-18 对账数学 |
| 排除 | locale 值、UI 代码、DES/架构、allowlist/checker 语义、设备侧测试、T-17/T-18 页面语义与英文翻译质量、544 条业务语义确认、上游“596”文档同步（不在本 commit 写范围） |
| 写入边界 | 只读；唯一仓库写入为本报告。所有临时副本/篡改实验在 `/tmp/opencode/wp099-neg/`，不进入仓库 |

本复评独立重算，不采用实现报告中的断言作为证据；实现报告仅用于对照其表述是否与实测一致。

## 2. F-01..F-05 逐条闭环

| Finding | 原严重度 | 闭环结论 | 关键证据 |
|---|---|---|---|
| **F-01** | Major（报告证据链） | **CLOSED** | T-18 §3.1 独立解析 59 行：53 exact + 6 normalized；构成为 41 MIGRATED + 6 PENDING + 9 ACCEPTED + 3 OBSOLETE；当前 46 MIGRATED 含 5 条 T-18 外 `string.json` 行；T-10 为 6 exact + 4 句号归一化，T-18 只列其中 9 条 |
| **F-02** | Low（证据保留） | **CLOSED** | 11 条 B 行 `备注` 均以 `07895fd` 原备注原文为前缀并追加证据；相对 `2d45628` 仅 11 个 `备注` 字段变化（行 44/46/48/49/52/53/69/79/104/144/347），原始 CSV 字段级比对仅第 9 列变化 |
| **F-03** | Low（工具完整性） | **CLOSED** | `legacy_text_digest()` 独立重算 = `ff9bb3…c3c3f5`（对 `07895fd` 与当前均一致）；篡改 `旧中文` 或仅篡改 `旧英文` → exit 1；614 行/重复 `旧中文` → exit 1；615 行/唯一性校验有效 |
| **F-04** | Info（防御性） | **CLOSED** | C 行缺失/非法 `复核标记` → exit 1；D 行缺失/非法（含非 `NONE`）→ exit 1；C 行不再被静默规范化；`compare()` 已把 C/D `复核标记` 纳入比对 |
| **F-05** | Low（文档一致性） | **CLOSED** | README §4 已改为实测：无 allowlist 总 warnings 73 / CHK-05 57；带 allowlist 55 / CHK-05 39；`blockingFailures=0`、`missingKeys=0` |

### 2.1 F-01：T-18 59 条的集合关系（独立解析 `t18-ui-pages.md` §3.1）

独立正则解析 59 行（行号 1..59），匹配方式计数为 **53 exact + 6 normalized**。逐行映射到当前 CSV 后，构成为：

| T-18 §3.1 组成 | 数量 | 当前 CSV 状态 | 说明 |
|---|---:|---|---|
| rawfile exact | 41 | `MIGRATED` | 与当前 41 条 rawfile MIGRATED 一一对应 |
| pending exact | 6 | `PENDING_REVIEW` | 1 条 `rawfile/i18n` + 5 条 `string.json`；均 exact 命中但多候选 |
| T-10 exact | 6 | `ACCEPTED` | 编辑/查看/成功/删除/失败/取消（均 `string.json`） |
| T-10 normalized | 3 | `ACCEPTED` | Wi-Fi 认证失败…/设备离线/刷新失败，请重试 |
| normalized-only | 3 | `OBSOLETE_LEGACY` | 操作失败，请重试/密码至少 8 位/未找到场景；T-18 按归一匹配，当前精确规则无引用 |
| **合计** | **59** | | **53 exact + 6 normalized** |

数学核对：

- exact：41 + 6 + 6 = **53**；normalized：3 + 3 = **6**；53 + 6 = 59。
- 当前 46 条 `MIGRATED` = 41 条 T-18 rawfile + **5 条 T-18 外 `string.json`**：场景（`tab_scenes`）、房间（`tab_rooms`）、首页（`tab_home`）、添加设备（`page_provisioning`）、我的（`tab_profile`）。
- 当前精确规则下 exact 行 = 46 MIGRATED + 6 PENDING + 6 exact ACCEPTED = **58**，不是 59。
- T-10 共 10 条 `ACCEPTED`：**6 exact**（编辑/查看/成功/删除/失败/取消）+ **4 条仅差末尾句号 `。`**（`Wi-Fi 认证失败，请检查密码。`、`保存失败，请重试。`、`设备离线。`、`刷新失败，请重试。`）。
- T-18 清单包含 T-10 的 9 条（6 exact + 3 normalized），**未列 `保存失败，请重试`**。
- 报告 §1/§7.3/§8/Traceability 的上述数字与独立重算一致；旧“46+6+7=59 一致”仅作为被否定的引用出现，报告不再声称同一集合，明确写为“总数巧合、集合不同”。

结论：F-01 的阻塞原因已消除；新的对账同时说明 5 条额外 MIGRATED、3 条 normalized-only OBSOLETE 和 T-10 的 4 条句号归一行，未掩盖集合差异。

### 2.2 F-02：11 条 B 行原备注保留

- `07895fd` 的 11 条 B 行原备注只有两种：
  - 9 条：`待 T-17/T-18 按页面/组件抽取语义化键; 旧英文机翻/术语错误（file/machine），B 类重译`
  - 2 条（解锁本机档案/锁定本机档案）：`…（files/machine file），B 类重译`
- 当前 11 条 B 行 `备注` 均满足 `startswith(原备注 + ";")`；原备注之后依次是通用 `no current locale/source reference…` 证据与 `B_REWRITE_REQUIRED: …` 术语/当前 en-US 证据。工具 `b_original_remark()` 的两个常量与上述原文逐字一致，`triage_rows()` 以 `original; base; b_evidence` 组装，不再整体替换。
- 相对 `2d45628` 的字段级 diff：**11 个变化，全部为 `备注`**；行号与报告 §6.1 的 44/46/48/49/52/53/69/79/104/144/347 完全一致。
- 更严格的 CSV 原始单元格比对：11 行中仅第 9 列（`备注`）原始 token 变化，其余 10 列（含 `旧中文`/`旧英文` 的引号形式）完全不变。
- 报告 §2 步骤 3、§4、§6.1、§8 的“保留原备注并追加证据”表述与工具实现一致。

### 2.3 F-03：旧文案基线摘要与不可变列校验

- 工具常量：`LEGACY_BASELINE_COMMIT = 07895fd…`；`LEGACY_TEXT_BASELINE_SHA256 = ff9bb3f450c3e68b891ef1c0b9db96104d2cde1141ee39d611a14861f5c3c3f5`；`LEGACY_ROW_COUNT = 615`。
- 独立重算 `legacy_text_digest()`：对 `git show 07895fd:entry/src/test/i18n/legacy-migration.csv` 与当前 CSV 分别计算，结果均为 `ff9bb3f450c3e68b891ef1c0b9db96104d2cde1141ee39d611a14861f5c3c3f5`；615 行、615 个唯一 `旧中文`。
- 负例（临时副本）：
  - 篡改一条 `旧中文`（追加 `TAMPER`）→ `INVARIANT 旧中文/旧英文 digest differs…`，exit 1。
  - **仅**篡改一条 ACCEPTED 行 `旧英文` → 同样 digest 失败，exit 1（F-03 原盲区已覆盖）。
  - 删除一行（614 行）→ `expected 615 rows, found 614` + digest 失败，exit 1。
  - 复制一条 `旧中文` 制造重复 → `旧中文 must be unique across all rows; duplicates=[...]` + digest 失败，exit 1。
- `--write` 在错误状态下拒绝写入：篡改后 `--write` exit 2，输出 `refusing to write with invariant errors`，文件 SHA 不变；正常副本连续两次 `--write` 均 exit 0，SHA 保持 `75b2cba0…b77e79`。
- 报告 §2 步骤 6 对算法（NFC + CRLF/CR→LF、`U+001F`/`U+001E` 分隔、不 trim、不折叠标点）的描述与代码一致。

### 2.4 F-04：C/D `复核标记` 的显式校验

- C 行：删除 `复核标记` → `INVARIANT line 33: C row has missing/illegal 复核标记 ''; expected one of ['RECHECK_REQUIRED', 'SAFETY_RECHECK_REQUIRED']`，exit 1；改为 `NONE` → 同一错误（`'NONE'`），exit 1。
- D 行：删除 → `INVARIANT line 13: D row has missing/illegal 复核标记 ''; expected 'NONE'`，exit 1；改为 `RECHECK_REQUIRED` → `…'RECHECK_REQUIRED'; expected 'NONE'`，exit 1。
- `triage_rows()` 对 C 行只校验非空 `备注`，不再把缺失/非法标记补成 `RECHECK_REQUIRED`；`validate()` 对 C/D 标记显式报错；`compare()` 对 C/D 均比对 `复核标记`。
- 当前 6 条 C（4 `RECHECK_REQUIRED` + 2 `SAFETY_RECHECK_REQUIRED`）与 3 条 D（`NONE`）相对 `07895fd` 未变化；报告 §2 步骤 4、§5、§7.10 的表述与实测一致。

### 2.5 F-05：README 检查器基线

- `entry/src/test/i18n/README.md` §4 当前文字：`blockingFailures=0` / `missingKeys=0`；总 warnings=73（CHK-07 16 条）；CHK-05 无 allowlist 57 条、带 `allowlist.json` 39 条（总 warnings=55）。
- 独立执行：
  - `check_i18n.py --strict-ui`：`blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16`，CHK-05 57 findings。
  - 带 allowlist：`blockingFailures=0 warnings=55 missingKeys=0 hardcoded=16`，CHK-05 39 findings。
- README 同时保留“CHK-05 仍为 warning、不阻断门禁”的正确限定；F-05 闭环。

## 3. 复验矩阵（实际执行，cwd = 仓库根）

| # | 命令 | 实际结果 | Exit |
|---:|---|---|---:|
| 1 | `python3 tools/i18n/triage_legacy.py --check`（第 1 次） | `615 rows`；`OK: CSV matches computed triage; invariants pass` | 0 |
| 2 | `python3 tools/i18n/triage_legacy.py --check`（第 2 次） | 同上；CSV SHA-256 前后均为 `75b2cba0a8a27639ed5506804f0a8eb07a066dd6bb3e114557bb95f796b77e79` | 0 |
| 3 | `python3 tools/i18n/triage_legacy.py --summary` | `rows: 615`；A 606 / C 6 / D 3；状态 10/46/6/0/544 + C 6 + D 3；`csv_status: UP_TO_DATE` | 0 |
| 4 | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | `blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16`；CHK-05 57 findings；CHK-01/02/03/04/06/08/09 PASS | 0 |
| 5 | `python3 entry/src/test/i18n/check_i18n.py --root . --allowlist entry/src/test/i18n/allowlist.json --strict-ui` | `blockingFailures=0 warnings=55 missingKeys=0 hardcoded=16`；CHK-05 39 findings | 0 |
| 6 | `entry/src/test/run-host-tests.sh` | `# tests 697`、`# pass 697`、`# fail 0`、`# skipped 0` | 0 |
| 7 | `python3 tools/contract/check_layering.py` | `files=221 violations=0 exceptions_used=6 pending=0`；`PASS` | 0 |
| 8 | `git diff --stat 07895fd 9d22b5b -- entry/src/test/i18n/legacy-migration.csv` | `596 insertions(+), 596 deletions(-)`；字段级/原始前两列比对 **0 差异**（见 §4） | 0 |
| 9 | `git diff --stat 2d45628 9d22b5b -- entry/src/test/i18n/legacy-migration.csv` | `11 insertions(+), 11 deletions(-)`；仅 `备注` 列 11 行 | 0 |
| 10 | 独立 Python 断言（615 行/配对/digest/计数/T-18/T-10/B 前缀） | `ALL_ASSERTIONS_OK` | 0 |
| 11 | 临时副本负例（§2.3/§2.4 的 9 个篡改/缺失/重复/行数场景） | 预期 exit 1；仅改 `负责人` 的对照场景 exit 0（见 O-01） | 0/1 |
| 12 | 临时副本 `--write` ×2 + 篡改后 `--write` | 正常写入幂等（SHA 不变）；篡改后拒绝写入（exit 2，SHA 不变） | 0/2 |
| 13 | `python3 -m py_compile tools/i18n/triage_legacy.py` | `COMPILE_OK` | 0 |

## 4. 独立数据与不变量核对

### 4.1 CSV 形状与计数

- 文件 616 行（1 表头 + 615 数据），11 列，列顺序与 `EXPECTED_COLUMNS` 一致；UTF-8 无 BOM，0 个 CR，LF，末尾有换行；所有行 11 列，无 `None`/额外字段。
- 状态计数：`ACCEPTED=10`、`MIGRATED=46`、`PENDING_REVIEW=6`、`INLINE_LITERAL=0`、`OBSOLETE_LEGACY=544`；C=`DEPRECATED (heuristic)` 6；D=`EXCLUDED (brand data)` 3；合计 615。A 606 + C 6 + D 3 = 615。
- `旧中文` 615/615 唯一；无行丢失、无重排。

### 4.2 相对 `07895fd`（原始基线）

- 615 对 `(旧中文, 旧英文)` 解析值 **0 差异**；按 CSV 原始单元格（含引号形式）比对前两列 **0 差异**。
- 独立 digest = `ff9bb3f450c3e68b891ef1c0b9db96104d2cde1141ee39d611a14861f5c3c3f5`。
- 全字段变化范围：`审查结论` 590 行、`备注` 596 行、`目标键` 46 行、`目标存储` 37 行；`分类`/`负责人`/`批次`/`重译审查`/`复核标记` **0 变化**。596 个变化行即 596 行 `备注` 变化的并集，符合 triage 设计。
- 因此 `git diff --stat 07895fd..9d22b5b` 的 596/596 行是 triage 字段变化，不是旧文案变更；旧文案由字段级与原始 token 双重核对确认未变。

### 4.3 相对 `2d45628`（修正前）

- 字段级：11 个变化，全部为 `备注`；行 44/46/48/49/52/53/69/79/104/144/347。
- 原始 CSV token 级：仅第 9 列变化，同样 11 行；`旧中文`/`旧英文`/分类/目标存储/目标键/审查结论/负责人/批次/重译审查/复核标记原始 token 全部不变。
- 计数 10/46/6/0/544 + C 6 + D 3 不变；46 条 MIGRATED 的目标存储/键不变。

### 4.4 F-01 独立重算摘要

- `t18_rows 59`；`modes {'normalized': 6, 'exact': 53}`。
- 逐行映射：`41 MIGRATED + 6 PENDING + 9 ACCEPTED + 3 OBSOLETE = 59`；T-18 的 6 条 PENDING 为 关闭/刷新/添加网关/执行中/简体中文/语言。
- 当前 MIGRATED 46 = 41 T-18 rawfile + 5 条 T-18 外 `string.json`（场景/房间/首页/添加设备/我的）。
- T-10：exact 6（编辑/查看/成功/删除/失败/取消）；normalized 4（Wi-Fi 认证失败…/保存失败，请重试/设备离线/刷新失败，请重试）；T-18 只列 9 条，缺 `保存失败，请重试`。
- 3 条 normalized-only OBSOLETE（操作失败，请重试/密码至少 8 位/未找到场景）在当前 exact 规则下无精确引用，报告已如实标注。

### 4.5 F-02 独立重算摘要

- 11 条 B 行；`重译审查=B_REWRITE_REQUIRED`；全部 `OBSOLETE_LEGACY`、`目标键` 为空。
- 11 条 `备注` 均以 `07895fd` 原备注原文加 `;` 开头；原备注两种变体与工具常量逐字一致。
- 相对 `2d45628` 仅 11 个 `备注` 字段变化；相对 `07895fd` 的 11 条 B 行 `旧中文/旧英文` 未变。

## 5. Findings

**无阻塞 Findings。F-01..F-05 全部闭环，修正后的 CSV/工具/文档/回归证据支持 PASS。**

| ID | 严重度 | 位置/证据 | 结论 | 处置 |
|---|---|---|---|---|
| **O-01** | **Info（非阻塞观察）** | `tools/i18n/triage_legacy.py` `validate()`/`compare()`；临时副本仅改 `负责人` 后 `--check` exit 0 | `--check` 仍未逐列冻结 `负责人/批次`；本次独立比对确认当前 615 行这两列与 `07895fd` 完全一致，且实现报告未声称覆盖该列，故不构成本次修正缺陷 | 无需在本 revision 修改；若未来要求“全列冻结”，再扩展基线摘要或逐列校验 |

除 O-01 外，未发现新的正确性、数据完整性、文档一致性或回归问题；未把风格偏好或对 544 条业务语义的怀疑写成缺陷。

## 6. 残余与风险（不阻塞本次 PASS）

1. **6 条 `PENDING_REVIEW` 仍需人工择一**：关闭、刷新、添加网关、执行中、简体中文、语言。候选键与跨存储歧义见 `--summary`；机器不能替人工决定。
2. **11 条 `B_REWRITE_REQUIRED` 仍未重译**：全部 `OBSOLETE_LEGACY`、`目标键` 为空；旧英文仍含 `file(s)`/`machine`；当前 en-US 0 处该术语（使用 `profile`）。复用前必须按 CB 术语表重写。
3. **6 条 C 类仍需人工复核**：4 条 `RECHECK_REQUIRED`；2 条模拟器/DEV-ONLY 为 `SAFETY_RECHECK_REQUIRED`，不得仅凭关键词删除。
4. **3 条 D 类品牌名保持排除**：Gree/格力、Haier/海尔、Midea/美的；作为数据显示，不进入资源包。
5. **544 条 `OBSOLETE_LEGACY` 只是“无精确当前引用”**：不是业务废弃证明，也不是可批量删除清单；T-17/T-18 归档前必须做语义确认。
6. **46 条 `MIGRATED` 是机器证据，不等于人工签收**：未人工复核英文、上下文、术语或可访问性；`重译审查` 仍为 `B_PENDING`（11 条 B 行为 `B_REWRITE_REQUIRED`）。
7. **T-10 的 4 条为句号归一化匹配**：Wi-Fi 认证失败…、保存失败，请重试、设备离线、刷新失败，请重试；已由 T-10 人工签署，但不能在精确匹配统计中计为 exact。
8. **检查器基线**：`--strict-ui` 0 blocking / 0 missing，但总 warnings 73（CHK-07 16 条），CHK-05 无 allowlist 57 条；带 allowlist 55 warnings / CHK-05 39 条。0 blocking 不等于 0 warnings。
9. **上游文档仍写 596**：`artifacts/80-maintenance/maintenance-plan.md` §3.4、根 `README.md` 第 78 行、`artifacts/90-integration/integration-report.md`；本 commit 写范围不含这些文件，需后续文档同步。
10. **未执行**：设备侧测试（`BLOCKED_ON_DEVICE_RUNNER`）；T-17/T-18 页面语义复核；英文翻译质量审查；544 条业务语义确认。本复评不把这些写成 PASS。
11. **工具边界**：`--check` 覆盖 CSV 中 `旧中文/旧英文` 的规范化摘要、615 行/唯一性、C/D 标记及工具拥有字段；不校验 `负责人/批次`（O-01），不验证英文质量、语义正确性或 UI 上下文；源码扫描范围仍限 `entry/src/main/ets/**` 与 `entry/src/main/resources/**`。

## 7. Verdict

**PASS**（范围：`9d22b5b` 相对 `818cb79` 的 F-01..F-05 修正；不授予 Stage Gate、Component Quality Gate 或用户验收）。

- **通过**：F-01 的 T-18 59 条集合关系与 53 exact + 6 normalized；F-02 的 11 条 B 原备注保留与仅 `备注` 变化；F-03 的 615 对旧文案基线 digest、篡改 `旧中文`/`旧英文` 检出、行数/唯一性；F-04 的 C/D 标记显式校验与不再静默规范化；F-05 的 README 73/57 与 55/39 实测口径。
- **不变量通过**：相对 `07895fd` 旧中文/旧英文逐单元格（含原始 CSV token）不变；相对 `2d45628` 仅 11 个 `备注` 字段变化；计数 10/46/6/0/544 + C 6 + D 3 不变。
- **回归通过**：`--check` ×2 exit 0；`--summary` 计数正确；`check_i18n --strict-ui` 0 blocking/0 missing；host 697/697；layering 0 violation。
- **不宣称**：544 条已业务废弃、46 条已人工签署、615 条迁移完成、6 PENDING/11 B/6 C 已关闭。O-01 仅为工具边界观察，不影响本次 PASS。
- 本判定只覆盖本次 revision 与 §1 声明范围；修正后的聚焦复评已完成，后续 Stage/Component 决策仍需按对应 Gate 重新取证。

## 8. 独立声明

本复评由 `quality-reviewer` 独立执行，未参与 `wp-096-i18n-triage` 或 `wp-098-i18n-fix` 的实现、报告撰写或修复决策；结论依据为被审 commit、`07895fd`/`2d45628` 基线、T-18 §3.1、当前 CSV/locale/源码实测、独立 Python 重算与临时副本负例。唯一仓库写入为本报告；未修改 CSV、工具、locale、UI、README、migration-boundary 或任何上游 Artifact。临时副本与篡改实验位于 `/tmp/opencode/wp099-neg/`，不进入仓库。评审结论仅覆盖本次 revision 与声明范围；不授予 Stage/User Acceptance，不宣告 Component `STABLE`，不把 615 条 triage 写成迁移完成。

---

STATUS: DONE

SUMMARY: 聚焦独立复评 `9d22b5b`（base `818cb79`）的 i18n 修正：F-01..F-05 全部闭环。独立解析 T-18 §3.1 确认 59 = 41 MIGRATED + 6 PENDING + 9 ACCEPTED + 3 OBSOLETE、53 exact + 6 normalized；当前 46 MIGRATED 含 5 条 T-18 外 `string.json` 行；T-10 为 6 exact + 4 句号归一化。11 条 B 行原备注保留且相对 `2d45628` 仅 11 个 `备注` 字段变化；615 对旧文案 digest `ff9bb3…c3c3f5` 独立重算一致，篡改 `旧中文`/`旧英文` 均 exit 1；C/D 缺失/非法标记 exit 1；README 73/57 与 55/39 与实测一致；`--check` ×2、`--summary`、check_i18n 0 blocking/0 missing、host 697/697、layering 0 violation 全部通过。Verdict **PASS**。

ARTIFACTS_CREATED: `artifacts/70-review/t24-i18n-rereview.md`

ARTIFACTS_UPDATED: 无（同路径占位文件被本报告覆写）

RISKS: 6 PENDING 未人工择一；11 B 未重译；6 C 待复核（2 条 SAFETY）；3 D 品牌排除；544 OBSOLETE 仅“无精确引用”，非业务废弃/删除清单；46 MIGRATED 非人工签收；T-10 4 条仅句号归一化；上游文档仍写 596；检查器 73/55 warnings；`--check` 未校验 `负责人/批次`（O-01）；设备测试/T-17/T-18 语义/英文质量/544 业务语义未执行。

VALIDATION: `triage_legacy.py --check` ×2 exit 0（CSV SHA `75b2cba0…b77e79` 不变）；`--summary` 计数 10/46/6/0/544 + C 6 + D 3；`check_i18n --strict-ui` 0 blocking/0 missing/73 warnings（CHK-05 57）；allowlist 版 55 warnings/39 CHK-05；host 697/697；layering files=221 violations=0；`git diff --stat 07895fd..9d22b5b -- CSV` 596/596 行但旧中文/旧英文原始 token 0 差异；`2d45628..9d22b5b -- CSV` 11/11 行且仅 `备注`；独立 Python `ALL_ASSERTIONS_OK`；临时副本负例均按预期 exit 1/2。

NEEDS_CLARIFICATION: none（F-01..F-05 修正口径明确；6 PENDING/11 B/6 C/3 D/544 语义属于后续人工任务，不是本次复评阻塞）

NEXT_ACTION: 由主会话将本次 PASS 与残余风险纳入 Checkpoint/Stage 状态；后续按 T-17/T-18/solution-architect 计划处理 6 PENDING、11 B、6 C、3 D 与 544 条语义确认，并同步上游“596”文档。不得把本次 PASS 扩大为 Stage Gate、Component Quality Gate 或用户验收。
