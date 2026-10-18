# i18n 615 条证据化 triage 独立复审（wp-097）

- **Producer**: agent:quality-reviewer
- **Task**: `wp-097-i18n-review`
- **Review target**: `2d45628b3e0ac4fecb6660727103f1b61b8498d6`（`task/wp-096-i18n-triage`）
- **Base**: `07895fd98b222264aec566cefd43a0ee9cb10f5e`
- **Date**: 2026-10-18
- **Verdict**: **CHANGES_REQUIRED**（CSV/工具/回归通过；报告证据链 F-01 需修正）
- **Reviewer**: `quality-reviewer`（未参与 `wp-096-i18n-triage` 实现）

## 1. 复审范围与 revision

| 项 | 值 |
|---|---|
| 被审 commit | `2d45628 chore(i18n): 证据化 triage 615 条历史文案` |
| Base | `07895fd chore(repo): 记录 A1 合并与验证证据` |
| 分支 | `task/wp-096-i18n-triage` |
| 变更 | 5 文件：`legacy-migration.csv`、`triage_legacy.py`、`migration-boundary.md`、`i18n/README.md`、`t24-i18n-triage.md` |
| 复审判定对象 | CSV 615 行、triage 工具、迁移边界/README、实现报告 |
| 排除 | `input/existing/original_app/service/I18nService.ets`（旧源，只作登记表来源）；locale 值/UI 代码/DES（本次未改）；设备侧测试；T-17/T-18 的页面语义与英文翻译质量；544 条的业务语义确认 |

本次只读复审。除本报告 `artifacts/70-review/t24-i18n-review.md` 外，未修改仓库任何文件；临时写入/篡改实验均在 `/tmp/opencode/` 的副本中进行。

## 2. 复验矩阵（实际执行，cwd = 仓库根）

| # | 命令 | 实际结果 | Exit |
|---:|---|---|---:|
| 1 | `python3 tools/i18n/triage_legacy.py --check`（第 1 次） | `615 rows`；`OK: CSV matches computed triage; invariants pass` | 0 |
| 2 | `python3 tools/i18n/triage_legacy.py --check`（第 2 次） | 同上；CSV SHA-256 前后均为 `efaf44fe…50c67d` | 0 |
| 3 | `python3 tools/i18n/triage_legacy.py --summary` | `rows: 615`；A 606 / C 6 / D 3；状态计数与 §4 一致；`csv_status: UP_TO_DATE` | 0 |
| 4 | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | `blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16`；CHK-01/02/03/04/06/08/09 PASS；CHK-05 57 findings | 0 |
| 5 | `python3 entry/src/test/i18n/check_i18n.py --root . --allowlist entry/src/test/i18n/allowlist.json --strict-ui` | `blockingFailures=0 warnings=55 missingKeys=0 hardcoded=16`；CHK-05 39 findings | 0 |
| 6 | `entry/src/test/run-host-tests.sh` | `# tests 697`、`# pass 697`、`# fail 0`、`# skipped 0` | 0 |
| 7 | `python3 tools/contract/check_layering.py` | `files=221 violations=0 exceptions_used=6 pending=0`；`PASS` | 0 |
| 8 | 临时副本 `--write` ×2 + `--check` | 两次写入后 CSV SHA-256 不变；`--check` 通过 | 0 |
| 9 | 临时副本篡改：改 `审查结论` | `DIFF row 62 [审查结论]`；`FAIL: 1 difference(s)` | 1 |
| 10 | 临时副本篡改：仅改 `旧英文` | `OK: CSV matches computed triage; invariants pass`（未检出，见 F-03） | 0 |

补充核对：

- 工具 SHA-256 = `c577dae2055f1f529787c11bd1e92084f4cd9caef464b61c4c9d7d2bc873de4e`，与报告 §2 一致。
- 四个输入哈希（zh-CN `97e97745…`、en-US `557496ff…`、`string.json` `4a870425…`、维护计划 `09383556…`）与报告 §2 表一致。
- Base CSV SHA-256 = `e7723819a11f958a197106ae454b739771e9ed21b6d3dc6fc1659250f0690189`；当前 CSV = `efaf44fe61aa900883b7c6450d50b248409c7ceeb80087f59a14f3803d50c67d`。
- `entry/src/main/ets/**/*.{ets,ts}` 实际 221 个文件，与报告 §3.4 一致。

## 3. 数据完整性

| 检查 | 结果 |
|---|---|
| 数据行数（不含表头） | **615**；文件 616 行（含表头） |
| 列顺序/表头 | 11 列，顺序与 `EXPECTED_COLUMNS` 完全一致 |
| 旧中文/旧英文逐行不变 | 与 `07895fd` 版本逐行比对，**0 行差异**；行顺序不变 |
| 旧中文唯一性 | 615/615 唯一；无重复行、无丢失行 |
| UTF-8 / BOM | UTF-8，**无 BOM** |
| 行尾 | **LF only**；0 个 CR；末尾有换行 |
| CSV 列数 | 所有行均为 11 列；无 `None` 额外字段 |
| 嵌入式换行 | 0 个单元格含 `\n`/`\r` |
| CSV 注入前置字符 | 0 个单元格以 `=`、`+`、`-`、`@` 或 TAB 开头 |
| 引号 | 3 个旧英文单元格含合法的双引号（`"My > Security Configuration"`），CSV 解析正常，无引号破坏 |
| 字段变更范围 | 仅 A 类行：`审查结论` 590、`备注` 596、`目标键` 46、`目标存储` 37；`旧中文/旧英文/分类/负责人/批次/重译审查/复核标记` 均 **0 变更** |
| ACCEPTED / C / D 行 | 10 条 ACCEPTED、6 条 C、3 条 D 与 base **逐字段完全一致** |
| `目标存储` | 仅 46 条 MIGRATED 中的 37 条被替换为实测存储；其余保留原启发式建议（报告已说明） |

结论：**数据完整性通过**。615 行未丢失、未重排、未改旧文案；写入格式符合 UTF-8/LF/11 列约定；当前数据不存在 CSV 注入或引号破坏。

## 4. 计数与状态语义

`--summary` 与独立脚本一致：

| 状态 | 数量 | 占比 |
|---|---:|---:|
| `ACCEPTED` | 10 | 1.6% |
| `MIGRATED` | 46 | 7.5% |
| `PENDING_REVIEW` | 6 | 1.0% |
| `INLINE_LITERAL` | 0 | 0.0% |
| `OBSOLETE_LEGACY` | 544 | 88.5% |
| `DEPRECATED (heuristic)` | 6 | 1.0% |
| `EXCLUDED (brand data)` | 3 | 0.5% |
| **合计** | **615** | **100%** |

- 分类：A 606 = 10+46+6+0+544；C 6；D 3；A+C+D = 615。
- 原 596 `PENDING_REVIEW` 去向：46 `MIGRATED` + 6 仍 `PENDING_REVIEW` + 544 `OBSOLETE_LEGACY` = 596。
- 负责人/批次：T-17 521、T-18 75、T-10 10、LEGACY-001 9；与 `migration-boundary.md` §3 一致。
- `重译审查`：`B_REVIEWED_ACCEPTED` 10、`B_PENDING` 585、`B_REWRITE_REQUIRED` 11、`NOT_APPLICABLE` 9；与 README/边界文档一致。
- 每行 `审查结论` 合法，`备注` 非空；A 类状态均在允许集内；C/D 状态分别为 `DEPRECATED (heuristic)` / `EXCLUDED (brand data)`。
- **ACCEPTED 基线**：10 条旧中文集合与 T-10 基线完全相等；`负责人/批次=T-10`、`重译审查=B_REVIEWED_ACCEPTED`；**未新增任何 ACCEPTED**。
- ACCEPTED 的目标键在当前 zh 值中：**6 条逐字精确**（编辑、查看、成功、删除、失败、取消）；**4 条仅差末尾句号 `。`**（Wi-Fi 认证失败…、保存失败，请重试、设备离线、刷新失败，请重试）。报告 §1/§8 的“7 条 T-10 精确匹配”与实际不符，见 F-01。
- `INLINE_LITERAL=0` 与工具重算一致；当前 221 个源文件与资源中无“无 locale 键但旧中文作为精确字面量存在”的 A 类行。

## 5. 映射抽查（32 条，覆盖全部状态；另全量机器校验）

> 全量校验：46 条 `MIGRATED` 逐条验证目标键存在且 zh 值等于旧中文；6 条 `PENDING_REVIEW` 逐条验证候选键与备注；11 条 B 逐条验证术语/状态；6 C + 3 D 逐条验证状态/标记；544 条 `OBSOLETE_LEGACY` 逐条验证无 locale 精确值匹配、无源码/资源精确字面量匹配。下表为可读抽查样本。

### 5.1 `MIGRATED`（10 条样本；全量 46 条通过）

| CSV 行 | 旧中文 | 目标存储:键 | 核对 |
|---:|---|---|---|
| 66 | 除湿 | `rawfile/i18n:ac.mode.dry` | 当前 zh 值 = 除湿；唯一命中，通过 |
| 67 | 传感器 | `rawfile/i18n:device.type.sensor` | 当前 zh 值 = 传感器；唯一命中，通过 |
| 94 | 端口 | `rawfile/i18n:settings.advanced.port` | 当前 zh 值 = 端口；唯一命中，通过 |
| 110 | 格力 | `rawfile/i18n:brand.gree` | 当前 zh 值 = 格力；唯一命中，通过 |
| 222 | 门已打开 | `rawfile/i18n:device.door.stage.open` | 当前 zh 值 = 门已打开；唯一命中，通过 |
| 225 | 密码（至少 8 位） | `rawfile/i18n:onboarding.password` | 当前 zh 值 = 密码（至少 8 位）；唯一命中，通过 |
| 62 | 场景 | `string.json:tab_scenes` | 当前 zh 值 = 场景；唯一命中，通过 |
| 351 | 添加设备 | `string.json:page_provisioning` | 当前 zh 值 = 添加设备；唯一命中，通过 |
| 418 | 未发现设备 | `rawfile/i18n:provisioning.scan.empty.title` | 当前 zh 值 = 未发现设备；唯一命中，通过 |
| 581 | 通用 | `rawfile/i18n:brand.generic` | 当前 zh 值 = 通用；唯一命中，通过 |

全量：41 条 `rawfile/i18n` + 5 条 `string.json`；目标键在 en-US 中也全部存在且非空。`备注` 均为 `zh value match: <key> @ <file>` 形式。**机器映射证据成立，但不等于人工签收**。

### 5.2 `PENDING_REVIEW`（全量 6 条）

| CSV 行 | 旧中文 | 候选键（实际重算） | 核对 |
|---:|---|---|---|
| 112 | 关闭 | `common.close`（rawfile）；`common_close`（string.json） | 2 候选；`目标键` 空；备注列出全部；通过 |
| 339 | 刷新 | `common.refresh`（rawfile）；`common_refresh`（string.json） | 2 候选；`common_refresh` 无产品引用；通过 |
| 352 | 添加网关 | `profile.provisioning`、`provisioning.title`（rawfile）；`home_add_gateway`（string.json） | 3 候选；三义成立；通过 |
| 528 | 执行中 | `card.state.pending`、`scene.running`、`scene.step.running`（rawfile） | 3 候选；同存储三义；通过 |
| 563 | 简体中文 | `settings.language.zh_cn`（rawfile）；`settings_language_zh_cn`（string.json） | 2 候选；跨存储重复；通过 |
| 569 | 语言 | `settings.section.language`（rawfile）；`settings_language_title`（string.json） | 2 候选；静态标题未引用；通过 |

### 5.3 B_REWRITE_REQUIRED（4 条样本；全量 11 条通过）

| CSV 行 | 旧中文 | 旧英文术语 | 状态 | 核对 |
|---:|---|---|---|---|
| 44 | 本机安全档案保存失败 | file | `OBSOLETE_LEGACY` | B 标记保留；当前 en-US 0 machine/file；通过 |
| 49 | 本机使用档案锁定失败 | file, machine | `OBSOLETE_LEGACY` | 同上；备注含完整 B 证据；通过 |
| 144 | 解锁本机档案 | files | `OBSOLETE_LEGACY` | 同上；`目标键` 空；通过 |
| 347 | 锁定本机档案 | files | `OBSOLETE_LEGACY` | 同上；`目标键` 空；通过 |

全量 11 条均满足：`重译审查=B_REWRITE_REQUIRED`、`旧英文` 含 `machine`/`file(s)`、`备注` 含 `B_REWRITE_REQUIRED:` 与术语证据；当前 en-US 的 machine/file 值计数为 **0**（已使用 `profile` 术语）。

### 5.4 C / D（7 条样本；全量 9 条通过）

| CSV 行 | 旧中文 | 状态 | 复核标记 | 核对 |
|---:|---|---|---|---|
| 33 | 版本 | `DEPRECATED (heuristic)` | `RECHECK_REQUIRED` | 通过 |
| 118 | 关于 YaoCore | `DEPRECATED (heuristic)` | `RECHECK_REQUIRED` | 通过 |
| 137 | 检测到开发协议模拟器，拒绝其控制响应 | `DEPRECATED (heuristic)` | `SAFETY_RECHECK_REQUIRED` | 对应安全文案，禁止按关键词删除；通过 |
| 149 | 旧版本机档案使用不安全的可逆存储，已失效并清除，请重新创建。 | `DEPRECATED (heuristic)` | `RECHECK_REQUIRED` | 通过 |
| 13 | Gree/格力 | `EXCLUDED (brand data)` | `NONE` | 品牌数据显示；通过 |
| 14 | Haier/海尔 | `EXCLUDED (brand data)` | `NONE` | 同上；通过 |
| 23 | Midea/美的 | `EXCLUDED (brand data)` | `NONE` | 同上；通过 |

C 类共 6 条：4 条 `RECHECK_REQUIRED` + 2 条 `SAFETY_RECHECK_REQUIRED`；D 类 3 条；与 base 逐字段一致，未删除、未降级。

### 5.5 `OBSOLETE_LEGACY`（5 条样本；全量 544 条通过）

| CSV 行 | 旧中文 | 精确 locale 匹配 | 源码/资源精确字面量 | 核对 |
|---:|---|---:|---:|---|
| 136 | 家庭状态 | 0 | 0 | 通过 |
| 282 | 扫描失败，请重试 | 0 | 0 | 通过 |
| 169 | 客厅 | 0 | 0 | 通过 |
| 257 | 请先打开手机蓝牙 | 0 | 0 | 通过 |
| 587 | 当前网关 | 0 | 0 | 通过（仅作为 `当前网关不支持…` 的子串出现，不是精确引用） |

全量 544 条：无 locale 精确值匹配；无源码/资源精确字面量匹配。另有约 30 条旧中文以**更长 locale 值的子串**出现（如 `家` 出现在 `家庭`、`本机使用档案` 出现在 `该家庭已存在本机使用档案。`），不构成精确引用，符合工具/报告定义的 `OBSOLETE_LEGACY` 语义。**该状态不是业务废弃证明，也不是可删除清单**；T-17/T-18 归档前仍需语义确认。

## 6. 工具正确性

| 维度 | 结论 |
|---|---|
| JSON 解析 | `rawfile` 嵌套对象展平为 543 个 zh 叶子 / 545 个 en 叶子；`string.json` 53 个条目；无数组/非字符串叶子导致失败；重复 JSON key / 重复 `name` 会报错 |
| 复数/数组 | 代码对 dict/list/string 通用展平；当前 en-US 有 `device.count_one`/`device.count_other`，`en_values_for_key` 也覆盖 `_one`/`_other`；当前 zh 无复数变体 |
| trim/匹配 | 旧中文与当前值均 `strip()` 后做**精确**索引；唯一命中 MIGRATED、多命中 PENDING、无命中再扫源码/资源；未使用模糊匹配 |
| 源码扫描 | 221 个 `.ets/.ts`；忽略 `//`、`/* */` 注释；解码转义；记录 `file:line`；资源 JSON 按叶子值、其他文本按引号字面量 |
| `--check` 语义 | 只读重算，比较工具拥有字段（审查结论/目标键/备注；MIGRATED 目标存储；C 复核标记）并执行 T-10/T-18 不变量；连续两次 exit 0，CSV 哈希不变；篡改 `审查结论` 时 exit 1 |
| `--summary` | 输出计数、PENDING/INLINE/B 明细、C/D 清单；exit 0；`csv_status: UP_TO_DATE` |
| `--write` 幂等 | 临时副本连续两次 `--write`，CSV SHA-256 均保持 `efaf44fe…50c67d`；写入前重读校验旧中文/旧英文未变；原子替换 |
| 退出码 | `--check` 漂移/不变量失败 1；输入/工具错误 2；正常 0；实测符合 |
| 路径 | `tools/i18n/triage_legacy.py` 存在；README/迁移边界引用的命令可执行 |

**工具限制（非当前数据缺陷）**：

1. `--check` 不校验 `旧中文/旧英文/负责人/批次`（见 F-03）；它只保护工具拥有字段。当前 615 行旧文案由 base diff 独立验证为 0 变更。
2. C 行缺失/非法 `复核标记` 会被静默规范为 `RECHECK_REQUIRED`，而不是报错（见 F-04）。
3. B 证据的 `global_hits` 按 en 叶子计数而非文本出现次数；当前全局计数为 0，无影响。
4. 源码扫描不覆盖 `.js/.mjs`、动态拼接/模板 `${}`、`input/`、`entry/src/test/**`、`artifacts/**`；报告 §7.4 已如实披露。

## 7. Findings

| ID | 严重度 | 位置 | 结论 | 建议 |
|---|---|---|---|---|
| **F-01** | **Major（报告证据链）** | `artifacts/50-implementation/t24-i18n-triage.md:35-38,319,362`；T-18 对照 `artifacts/50-implementation/t18-ui-pages.md:80-146` | “46 MIGRATED + 6 PENDING + 7 T-10 精确匹配 = 59，与 T-18 的 59 条记录一致”不成立：T-18 的 59 实际映射为 41 MIGRATED + 6 PENDING + 9 ACCEPTED + 3 OBSOLETE；当前 46 MIGRATED 含 5 条 T-18 之外的 `string.json` 行；T-10 精确匹配实际 6 条，不是 7 条 | 重写 §1/§7.3/§8 的 T-18 对账：明确集合关系与 53 exact + 6 normalized；列出 5 条 string.json MIGRATED、3 条 normalized-only OBSOLETE、4 条 T-10 句号归一化行；删除“7 条”和“一致”或限定为“总数巧合” |
| **F-02** | **Low（证据保留/措辞）** | `tools/i18n/triage_legacy.py:584-593`；`t24-i18n-triage.md:69-70`；CSV 行 44–54 等 11 条 B | 报告称“追加”B 证据，但工具实际用 `base` **整体替换** `备注`；原备注“待 T-17/T-18 按页面/组件抽取语义化键; 旧英文机翻/术语错误…”不再存在于新 CSV | 若“B/C/D 证据保留”要求原文保留，改为在原备注后追加 `base`；否则把报告措辞改为“重写备注并保留 B_REWRITE_REQUIRED/术语证据”。改动 CSV 后需重跑 `--check`/复审 |
| **F-03** | **Low（工具完整性边界）** | `tools/i18n/triage_legacy.py:705-721`；报告 §2/§7.10 | 临时副本仅修改 ACCEPTED 行 `旧英文` 为 `TAMPERED ENGLISH ONLY`，`--check` 仍 exit 0；`--check` 不能发现旧文案/owner/batch 篡改 | 增加 615 对 `(旧中文,旧英文)` 的基线 SHA-256 或 `--check-baseline` 模式；至少在文档中明确“`--check` 不是 legacy 文本完整性校验” |
| **F-04** | **Info（防御性）** | `tools/i18n/triage_legacy.py:520-527` | C 行缺失/非法 `复核标记` 被静默改为 `RECHECK_REQUIRED` 后通过校验；当前 6 条 C 全部合法，无实际影响 | 建议缺失/非法标记时报错或至少打印 warning，避免未来掩盖坏证据 |
| **F-05** | **Low（文档一致性）** | `entry/src/test/i18n/README.md:78-80`（本 commit 修改的文件） | README §4 仍保留“CHK-05 的 0 告警”旧表述；实测无 allowlist 57、带 allowlist 39。报告 §7.9 已披露该既有基线漂移，但本 commit 修改 README 时未修正 | 更新为当前实测计数，或明确标注为历史基线；与下一轮文档同步一起处理 |

### F-01 详细证据（为什么 59 不构成集合一致）

对 `t18-ui-pages.md` 的 59 行逐条映射到当前 CSV：

| T-18 59 的组成 | 数量 | 当前 CSV 状态 | 说明 |
|---|---:|---|---|
| MIGRATED（rawfile） | 41 | `MIGRATED` | 与当前 41 条 rawfile MIGRATED 对应 |
| PENDING_REVIEW | 6 | `PENDING_REVIEW` | 6 条全部对应 |
| T-10 行 | 9 | `ACCEPTED` | 6 条 exact + 3 条 normalized（Wi-Fi/设备离线/刷新失败） |
| normalized-only | 3 | `OBSOLETE_LEGACY` | `操作失败，请重试`、`密码至少 8 位`、`未找到场景` |
| **合计** | **59** | | |

当前 CSV 另有 **5 条** `string.json` MIGRATED（场景/房间/首页/添加设备/我的）不在 T-18 的 59 中；T-10 共 10 条 ACCEPTED，其中 **6 条 exact**、**4 条仅句号归一化**（Wi-Fi、保存失败、设备离线、刷新失败）；T-18 的 9 条 T-10 行未列 `保存失败，请重试`。因此：

- T-18 的 59 = **53 exact + 6 normalized**；当前精确规则下的 exact 行 = 46 MIGRATED + 6 PENDING + 6 exact ACCEPTED = **58**；
- 报告写的“46 + 6 + 7 = 59 精确匹配”既把 5 条 T-18 外行算进来，又把 3 条 normalized-only 行忽略掉，并把 T-10 exact 数写成 7（实际 6）。总数 59 只是巧合，不是同一集合。

影响：不影响 615 行 CSV 的状态/映射正确性，但会误导 T-18 对账与后续归档判断（尤其 3 条 normalized-only 行需要语义确认、5 条 string.json MIGRATED 未在 T-18 清单中）。修正为文本更正即可，无需改 CSV/工具；修正后重跑 §2 的复验命令并做聚焦复审。

## 8. 残余与风险（不阻塞数据结论，但必须保留）

1. **6 条 `PENDING_REVIEW` 仍未人工择一**：关闭、刷新、添加网关、执行中、简体中文、语言。候选键与跨存储歧义已逐条记录；需 T-17/T-18/solution-architect 按页面上下文决定。
2. **11 条 `B_REWRITE_REQUIRED` 仍未重译**：全部 `OBSOLETE_LEGACY`、`目标键` 空；旧英文仍含 `file(s)`/`machine`；当前 en-US 0 处该术语（使用 `profile`）。复用文案前必须按 CB 术语表重写。
3. **6 条 C 类仍需人工复核**：4 条 `RECHECK_REQUIRED`；2 条模拟器/DEV-ONLY 为 `SAFETY_RECHECK_REQUIRED`，不得仅凭关键词删除。
4. **3 条 D 类品牌名保持排除**：Gree/格力、Haier/海尔、Midea/美的；作为数据显示，不进入资源包。
5. **544 条 `OBSOLETE_LEGACY` 只是“无精确当前引用”**：不是业务废弃证明，也不是可批量删除清单；T-18 曾按语义非逐字重写大量文案，归档前必须由 T-17/T-18 做语义确认。
6. **46 条 MIGRATED 是机器证据，不等于 ACCEPTED**：未人工复核英文、上下文、术语或可访问性；`重译审查` 仍为 `B_PENDING`（11 条 B 行为 `B_REWRITE_REQUIRED`）。
7. **ACCEPTED 的 4 条为句号归一化匹配**：Wi-Fi 认证失败…、保存失败，请重试、设备离线、刷新失败，请重试；它们已由 T-10 人工签署，但不能在“精确匹配”统计中计为 exact。
8. **检查器告警基线**：`--strict-ui` 0 blocking / 0 missing；总 warnings 73（CHK-07 16 条），无 allowlist CHK-05 57 条；带 allowlist 55 warnings / 39 CHK-05。0 blocking 不等于 0 warnings。
9. **上游文档仍写 596**：`maintenance-plan.md` §3.4、根 `README.md` 第 78 行、`integration-report.md` 仍保留旧计数；本 commit 写范围不含这些文件，报告 §7.9 已披露，需后续文档同步。
10. **工具/报告边界**：F-03 的 `--check` 旧文案盲区、F-02 的 B 原备注替换、F-04 的 C 标记静默规范化；均不影响当前 615 行数据，但应在下一轮收口。
11. **未执行**：设备侧测试（`BLOCKED_ON_DEVICE_RUNNER`）；T-17/T-18 页面语义复核；英文翻译质量审查；544 条业务语义确认。本复审不把这些写成 PASS。

## 9. Verdict

**CHANGES_REQUIRED**（范围：报告证据链；不是 CSV/工具/回归失败）。

- **通过**：615 行数据完整性；11 列/UTF-8/LF/旧文案 0 变更；状态计数与语义；46 MIGRATED 精确映射；6 PENDING 候选；11 B 证据；6 C/3 D 原证据；544 OBSOLETE 精确无引用；`--check` 两次幂等、`--summary`、`--write` 幂等；`check_i18n --strict-ui` 0 blocking/0 missing；host 697/697；layering 0 violation。
- **阻塞项**：**F-01** —— `t24-i18n-triage.md` 的“46+6+7=59 与 T-18 一致”不成立，需按 §7 的 T-18 实际组成重写。该错误不改变 CSV 的任何状态，但会使 T-18 对账/归档证据失真。
- **建议同批处理（非阻塞）**：F-02（B 原备注追加或措辞修正）、F-03（`--check` 旧文案基线）、F-05（README CHK-05 旧表述）；F-04 可作为工具防御性改进。
- **修正后复验**：重跑 §2 的 1–7 项；若仅改报告文本，无需改 CSV/工具，但仍需 `--check`/`--summary` 与聚焦复审；若改 CSV/工具，需重新全量复审。
- 本判定不是 Stage Gate、Component Quality Gate 或用户验收；不得据此把 544 条写成已废弃、把 46 条写成已签署、把 615 条写成已完成迁移。

## 10. 独立声明

本复审由 `quality-reviewer` 独立执行，未参与 `wp-096-i18n-triage` 的实现或报告撰写；复审依据为被审 commit、base 版本、locale/源码实测与 `swe_guard` handoff。唯一仓库写入为本报告；未修改 CSV、工具、locale、UI、README、migration-boundary 或任何上游 Artifact。临时副本与篡改实验位于 `/tmp/opencode/`，不进入仓库。评审结论仅覆盖本次 revision 与声明范围；不授予 Stage/User Acceptance，不宣告 Component `STABLE`。

---

STATUS: DONE

SUMMARY: 独立复审 `2d45628`（base `07895fd`）的 i18n 615 条证据化 triage：数据完整性、状态计数、46 MIGRATED 映射、6 PENDING 候选、11 B、6 C/3 D、544 OBSOLETE 精确无引用、工具 `--check`/`--summary`/`--write` 幂等、check_i18n 0 blocking/0 missing、host 697/697、layering 0 violation 均通过。Verdict **CHANGES_REQUIRED**：报告 `t24-i18n-triage.md` §1/§7.3/§8 的“46+6+7=59 与 T-18 一致”不成立——T-18 的 59 实际为 41 MIGRATED + 6 PENDING + 9 ACCEPTED + 3 OBSOLETE；当前 46 MIGRATED 含 5 条 T-18 外 string.json 行；T-10 exact 为 6 条而非 7 条。另有 F-02（B 备注被整体替换而非追加）、F-03（`--check` 不校验旧文案）、F-04（C 标记静默规范化）、F-05（README CHK-05 旧表述）等低风险项。

ARTIFACTS_CREATED: `artifacts/70-review/t24-i18n-review.md`

ARTIFACTS_UPDATED: 无（同路径占位文件被本报告覆写）

RISKS: 6 PENDING 未人工择一；11 B 未重译；6 C 待复核（2 条 SAFETY）；3 D 品牌排除；544 OBSOLETE 仅“无精确引用”，非业务废弃/删除清单；46 MIGRATED 非人工签收；T-10 4 条仅句号归一化；上游文档仍写 596；`--check` 不校验旧文案；B 原备注未保留；README CHK-05 基线漂移。

VALIDATION: `triage_legacy.py --check` ×2 exit 0（CSV SHA `efaf44fe…` 不变）；`--summary` 计数 10/46/6/0/544/6/3；`check_i18n.py --strict-ui` exit 0（0 blocking/0 missing/73 warnings）；allowlist 版 55 warnings/39 CHK-05；host 697/697；layering files=221 violations=0；临时副本 `--write` ×2 哈希不变；篡改 `审查结论` 使 `--check` exit 1；仅改 `旧英文` 仍 exit 0（F-03 证据）。

NEEDS_CLARIFICATION: none（F-01 的修正口径明确；无需用户产品决策）

NEXT_ACTION: 由 `implementation-engineer` 修正 F-01（并按需处理 F-02/F-05/F-04），保持 CSV/工具不变则重跑 `--check`/`--summary`/`check_i18n`/host/layering 后提交；随后由 `quality-reviewer` 做聚焦复审。不得在修正前把本 triage 用于 Stage Gate 或宣告 615 条迁移关闭。
