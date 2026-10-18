# T-24 证据化 i18n 615 条登记表 triage

- **Producer**: agent:implementation-engineer
- **Task**: `wp-096-i18n-triage`；复审修正 `wp-098-i18n-fix`
- **Branch / base**: `task/wp-096-i18n-triage` @ `07895fd98b222264aec566cefd43a0ee9cb10f5e`；
  复审基线 `818cb79`；本修正任务 `wp-098-i18n-fix`
- **Date**: 2026-10-18
- **Status**: `COMPLETE`（实现与本地验证完成；`wp-098` 已修正 F-01..F-05，待聚焦独立复审，不自我签署）
- **上游**: `artifacts/80-maintenance/maintenance-plan.md` §3.4；`entry/src/test/i18n/migration-boundary.md`；
  `check_i18n.py`；I18N-DESIGN §5；DES-B §7.4.3/§7.4.4

## 1. 目标与结论

对 615 条旧 `I18nService.ets` 字典登记表做**逐条、可复现、证据化** triage：596 条原
`PENDING_REVIEW`（其中 11 条 `B_REWRITE_REQUIRED`）、6 条 C、3 条 D。核心约束：

- 不批量签收；不把未人工复核行标 `ACCEPTED`；
- 每条 A 类行必须有明确 `审查结论` 与非空 `备注` 证据；
- 只改登记表/工具/文档/本报告，不改 locale 值、UI 代码或 DES。

**结论**：615 行全部完成证据分类，`--check` 幂等通过。实际状态分布为：

| 状态 | 数量 | 占 615 |
|---|---:|---:|
| `ACCEPTED`（仅 T-10 人工复核） | 10 | 1.6% |
| `MIGRATED`（精确唯一当前键，机器证据） | 46 | 7.5% |
| `PENDING_REVIEW`（多键歧义） | 6 | 1.0% |
| `INLINE_LITERAL`（源码/资源仍含字面量） | 0 | 0.0% |
| `OBSOLETE_LEGACY`（无精确当前引用） | 544 | 88.5% |
| `DEPRECATED (heuristic)`（C 类） | 6 | 1.0% |
| `EXCLUDED (brand data)`（D 类） | 3 | 0.5% |
| **合计** | **615** | **100%** |

> **与任务预期的重要偏差**：交接说明预期“`MIGRATED` 占多数”。按任务规定的**精确匹配**规则，
> 实际只有 46/606 条 A 类可唯一映射；544 条无精确当前引用。这不是工具失败，也不是批量判废：
> 当前 zh-CN 两个存储共 526 个不同值，旧字典 615 条中包含大量 v1 未实现的旧功能文案；
> T-18 报告也明确记载“59 条可自动核对，另有大量旧文案按页面语义重写（非逐字）”。

**与 T-18 的 59 条对账（F-01 修正）**：`artifacts/50-implementation/t18-ui-pages.md` §3.1 的 59 条
按当前 triage 状态实际构成为 **41 `MIGRATED` + 6 `PENDING_REVIEW` + 9 `ACCEPTED` +
3 `OBSOLETE_LEGACY` = 59**，按匹配方式为 **53 exact + 6 normalized**。当前 46 条 `MIGRATED`
中有 **5 条 `string.json` 行**（场景/房间/首页/添加设备/我的）不在 T-18 的 59 条清单内；T-10 的
10 条 `ACCEPTED` 中精确匹配为 **6 条**，另 4 条仅差末尾句号 `。`（Wi-Fi 认证失败…、保存失败，请重试、
设备离线、刷新失败，请重试）；T-10 在 T-18 清单中只出现 9 条（未列 `保存失败，请重试`）。因此：

- T-18 的 59 = 53 exact + 6 normalized；其中 41 MIGRATED + 6 PENDING + 6 exact ACCEPTED = 53 exact，
  3 条 T-10 normalized + 3 条 normalized-only OBSOLETE = 6 normalized；
- 当前精确规则下的 exact 行 = 46 MIGRATED + 6 PENDING + 6 exact ACCEPTED = 58；
- 原报告“46 + 6 + 7 = 59 与 T-18 一致”不成立：7 条 T-10 精确匹配实为 6 条；46 条 MIGRATED 含 5 条
  T-18 之外的 `string.json` 行；同时漏计 3 条 normalized-only OBSOLETE。总数相同是**巧合**，
  不是同一集合。

结论：**T-18 的 59 条全部可核对（53 exact + 6 normalized）；当前 triage 另有 5 条 `string.json`
精确匹配**。证据来源：`t18-ui-pages.md` §3.1（59 行清单）；`legacy-migration.csv` 当前状态；
本报告 §7.3 的逐条对账。未为提高 `MIGRATED` 比例放宽匹配或伪造目标键。

## 2. 工具与方法

**工具**：`tools/i18n/triage_legacy.py`（本修正后 SHA-256
`48c5b502ecceb6c12facc236aa2865ea8211219810966179b31391d8a57c60cb`；`wp-096` 首版为
`c577dae2055f1f529787c11bd1e92084f4cd9caef464b61c4c9d7d2bc873de4e`）。

输入：

| 输入 | SHA-256（交接基线） |
|---|---|
| `entry/src/test/i18n/legacy-migration.csv` | `e7723819a11f958a197106ae454b739771e9ed21b6d3dc6fc1659250f0690189` |
| `entry/src/test/i18n/migration-boundary.md` | `e54ba24bda417bb76530e1d74593f31926be9e3d6a605c8708aae6ab89f500ed` |
| `entry/src/test/i18n/check_i18n.py` | `bce8e10780dc93f9e231f8c39b837c2120f315a94bf891fee6f321e4299a14d2` |
| `entry/src/main/resources/rawfile/i18n/zh-CN.json` | `97e97745ed257b6b1f7fd0495c67866eb25c6cd0943a936e742499cb21105627` |
| `entry/src/main/resources/rawfile/i18n/en-US.json` | `557496ff2db3e09790354065f2afe105c7a400f981fafacef3b7de9e28c5e8b7` |
| `entry/src/main/resources/base/element/string.json` | `4a8704256c78220380c8f0d8c140ca0f511b2d798019b629e55f9559bfcea973` |
| `artifacts/80-maintenance/maintenance-plan.md` | `093835568c5f1ab496b22e800f8eaab299b1ea1e15494878e48fdf89fb418514` |

算法（确定性、无模糊匹配）：

1. 解析 `rawfile/i18n/zh-CN.json`（嵌套对象，包含复数/数组叶子的通用展平）与
   `base/element/string.json`（`string[]` 的 `name`/`value`；值若为对象/数组则递归展平）。
2. 用旧中文 `strip()` 后对当前 zh 值做**精确**索引：
   - 唯一命中 → `MIGRATED`；写实际 `目标存储`（`rawfile/i18n` / `string.json`）与 `目标键`；
     `备注=zh value match: <key> @ <file>`；
   - 多键命中 → `PENDING_REVIEW`；`目标键` 清空，`备注` 列出全部候选键与文件；
   - 无命中 → 扫描 `entry/src/main/ets/**/*.{ets,ts}` 字符串字面量（去注释、解码转义）与
     `entry/src/main/resources/**` 文本/JSON 值；命中 → `INLINE_LITERAL` 并记录 `file:line` 或
     `file#key`；仍无命中 → `OBSOLETE_LEGACY`，证据固定包含
     `no current locale/source reference`。
3. `B_REWRITE_REQUIRED` 行：保持 `重译审查=B_REWRITE_REQUIRED`；**保留 `07895fd` 基线中的原备注**
   （F-02），在其后追加旧英文 `machine/file(s)` 术语证据、当前 en-US 同键值/全局术语出现次数；
   若唯一命中当前键则同时写 `目标键`。原备注不再被整体替换。
4. C/D 行：保持 `DEPRECATED (heuristic)` / `EXCLUDED (brand data)` 与原备注；C 的 `复核标记` 必须为
   `RECHECK_REQUIRED`/`SAFETY_RECHECK_REQUIRED`，D 必须为 `NONE`。缺失或非法值不再静默规范化，
   而是由 `--check` 明确报错（F-04；本次 6 条 C、3 条 D 均合法，数据未改）。
5. `ACCEPTED` 行：完全保留；工具用 T-10 固定基线（10 条旧中文、owner/batch、`B_REVIEWED_ACCEPTED`）
   校验，**不新增、不改写**。
6. `--check` 只读重算，比对工具拥有的字段（`审查结论`、`目标键`、`备注`；MIGRATED 的
   `目标存储`；C/D 的 `复核标记`）并执行不变量断言。不可变列额外校验（F-03）：
   - `旧中文`/`旧英文` 规范化 SHA-256 必须等于 `07895fd` 预 triage 基线常量
     `ff9bb3f450c3e68b891ef1c0b9db96104d2cde1141ee39d611a14861f5c3c3f5`；
   - 行数必须为 615，`旧中文` 必须 615/615 唯一。
   算法记录在工具 `legacy_text_digest()`：按文件顺序对每行
   `NFC(旧中文) + U+001F + NFC(旧英文，CRLF/CR→LF) + U+001E` 求 SHA-256；只做 NFC 与换行规范化，
   不 trim、不做标点折叠。`--summary` 输出计数与残余明细；默认写入时先写临时文件、重读校验
   旧中文/旧英文未变，再原子替换；基线/行数/唯一性/标记不变量失败时拒绝写入。

写入保证：列顺序固定为
`旧中文,旧英文,分类,目标存储,目标键,审查结论,负责人,批次,备注,重译审查,复核标记`；
UTF-8 无 BOM；LF；旧中文/旧英文原文逐字节不变（工具写入前后自校验；`07895fd` 基线摘要见上）。

## 3. 状态统计

### 3.1 全部 615 行

| 分类 | 数量 | `ACCEPTED` | `MIGRATED` | `PENDING_REVIEW` | `INLINE_LITERAL` | `OBSOLETE_LEGACY` | C/D 状态 |
|---|---:|---:|---:|---:|---:|---:|---|
| A 迁移 | 606 | 10 | 46 | 6 | 0 | 544 | — |
| C 废弃 | 6 | — | — | — | — | — | `DEPRECATED (heuristic)` 6 |
| D 排除 | 3 | — | — | — | — | — | `EXCLUDED (brand data)` 3 |
| **合计** | **615** | **10** | **46** | **6** | **0** | **544** | **9** |

原 596 条 `PENDING_REVIEW` 的去向：46 条 `MIGRATED` + 6 条仍 `PENDING_REVIEW` + 544 条
`OBSOLETE_LEGACY` = 596。11 条 `B_REWRITE_REQUIRED` 全部落在 `OBSOLETE_LEGACY`（无精确当前键），
其 `重译审查` 保持 `B_REWRITE_REQUIRED`。

### 3.2 A 类 `MIGRATED`（46 条，按存储）

`rawfile/i18n`：41 条

| 旧中文 | 目标键 |
|---|---|
| 除湿 | `ac.mode.dry` |
| 传感器 | `device.type.sensor` |
| 灯光 | `device.type.light` |
| 端口 | `settings.advanced.port` |
| 格力 | `brand.gree` |
| 海尔 | `brand.haier` |
| 节能 | `ac.mode.eco` |
| 开关 | `device.type.switch` |
| 空调 | `device.type.ac` |
| 离线 | `device.state.offline` |
| 美的 | `brand.midea` |
| 门已打开 | `device.door.stage.open` |
| 密码（至少 8 位） | `onboarding.password` |
| 扫描中 | `provisioning.progress.scanning` |
| 上锁 | `device.door.lock` |
| 设备 | `device.info.device` |
| 摄像头 | `device.type.camera` |
| 湿度 | `home.environment.humidity` |
| 收起 | `common.collapse` |
| 睡眠 | `ac.mode.sleep` |
| 送风 | `ac.mode.fan` |
| 添加 | `common.add` |
| 已完成 | `family.join.phase.completed` |
| 网关在线 | `home.gateway.online` |
| 未发现设备 | `provisioning.scan.empty.title` |
| 项目 ID | `settings.cloud.project_placeholder` |
| 新建 | `room.new` |
| 移除 | `common.remove` |
| 已配置 | `cloud.state.configured` |
| 已上锁 | `door.state.secured` |
| 已选择 | `provisioning.scan.selected` |
| 云端 | `settings.section.cloud` |
| 在线 | `device.state.online` |
| 执行 | `scene.run` |
| 制冷 | `ac.mode.cool` |
| 制热 | `ac.mode.heat` |
| 自动 | `ac.mode.auto` |
| 跳过 | `scene.step.skipped` |
| 上一步 | `common.previous` |
| 下一步 | `common.next` |
| 通用 | `brand.generic` |

`string.json`：5 条

| 旧中文 | 目标键 |
|---|---|
| 场景 | `tab_scenes` |
| 房间 | `tab_rooms` |
| 首页 | `tab_home` |
| 添加设备 | `page_provisioning` |
| 我的 | `tab_profile` |

> `格力/海尔/美的` 三条 A 类行精确命中 `brand.*` 专名键；D 类的 `Gree/格力`、`Haier/海尔`、
> `Midea/美的` 仍保持排除。两者不是重复签收：A 行是旧 UI 标签值，D 行是品牌数据显示规则。

### 3.3 残余 `PENDING_REVIEW`（6 条，逐条）

| # | 旧中文 | 旧英文 | 候选键（存储） | 当前使用证据 / 人工判断点 |
|---:|---|---|---|---|
| 1 | 关闭 | close | `common.close`（rawfile）；`common_close`（string.json） | `common.close` 用于 `DeviceCards/ProvisioningPage/ScenePage` 动态 `t()`；`common_close` 用于 `ShellViews` 静态 `$r()`。需确认旧文案原属哪个入口。 |
| 2 | 刷新 | Refresh | `common.refresh`（rawfile）；`common_refresh`（string.json） | `common.refresh` 用于 `StatusPanels/DeviceGrid`；`common_refresh` 未被产品代码引用（CHK-05 告警）。 |
| 3 | 添加网关 | Add gateway | `profile.provisioning`（rawfile）；`provisioning.title`（rawfile）；`home_add_gateway`（string.json） | 入口按钮（Profile）、配网页标题、首页静态文案三义；`home_add_gateway` 当前未被产品代码引用。 |
| 4 | 执行中 | Executing | `card.state.pending`（rawfile）；`scene.running`（rawfile）；`scene.step.running`（rawfile） | 设备卡片状态、场景整体运行、场景步骤运行三义；当前均由 `UiMapping`/`DeviceCards` 使用。 |
| 5 | 简体中文 | Simplified Chinese | `settings.language.zh_cn`（rawfile）；`settings_language_zh_cn`（string.json） | 语言选项动态标签（`UiMapping`）与静态 `$r()` 标签（`SettingsPage`）同时存在；需确认是否应消除跨存储重复。 |
| 6 | 语言 | Language | `settings.section.language`（rawfile）；`settings_language_title`（string.json） | 设置分区标题（`SettingsPage` 动态）与静态标题；`settings_language_title` 当前未被产品代码引用。 |

这 6 条不是“未处理”：每条都已重算并记录全部候选；由于同一中文在不同页面/存储有多个语义正确
目标，机器不能替人工择一。

### 3.4 `INLINE_LITERAL` 与 `OBSOLETE_LEGACY`

- `INLINE_LITERAL=0`：扫描了 221 个 `entry/src/main/ets/**/*.{ets,ts}` 源文件与
  `entry/src/main/resources/**` 文本/JSON；没有发现“无 locale 键但旧中文仍作为字面量存在”的 A 类行。
  当前源码中的 CJK 字面量（如 `AcAdapterFactory` 的 `格力/海尔/美的`、各 AC adapter 的
  `节能/睡眠/制冷`）都已有精确 locale 键，因此按规则先归 `MIGRATED`，不是 `INLINE_LITERAL`。
- `OBSOLETE_LEGACY=544`：当前 locale 与源码/资源均无**精确**引用。证据字段统一为：
  `no current locale/source reference (scanned entry/src/main/ets/** and entry/src/main/resources/**);
  not proof of business obsolescence (T-18 non-verbatim rewrites possible); T-17/T-18 semantic
  confirmation required before archival`。

## 4. B 重译清单（11 条，`重译审查` 保持 `B_REWRITE_REQUIRED`）

当前 en-US locale 的 `machine`/`file(s)` 出现次数为 **0**（已使用 `profile` 术语）。11 条旧英文
仍含 `file(s)`/`machine`；本次 triage 均无精确当前键，故 `审查结论=OBSOLETE_LEGACY`、`目标键` 为空。
11 条 B 行 `备注` 均保留 `07895fd` 基线中的原备注，并在其后追加术语/当前 en-US 证据（F-02）。
若复用其文案，必须先按 CB 术语表重写英文。

| # | 旧中文 | 旧英文 | 旧英文术语 | 审查结论 | owner |
|---:|---|---|---|---|---|
| 1 | 本机安全档案保存失败 | Failed to save local security file | file | `OBSOLETE_LEGACY` | T-18 |
| 2 | 本机档案已解锁 | Local file is unlocked | file | `OBSOLETE_LEGACY` | T-18 |
| 3 | 本机使用档案 | local usage file | file | `OBSOLETE_LEGACY` | T-18 |
| 4 | 本机使用档案锁定失败 | Failed to use file lock on this machine | file, machine | `OBSOLETE_LEGACY` | T-18 |
| 5 | 本机使用档案已锁定 | The local usage file is locked | file | `OBSOLETE_LEGACY` | T-18 |
| 6 | 本机已有使用档案，请直接解锁 | This machine already has a usage file, please unlock it directly. | file, machine | `OBSOLETE_LEGACY` | T-18 |
| 7 | 创建本机档案 | Create local file | file | `OBSOLETE_LEGACY` | T-18 |
| 8 | 档案已创建，但解锁状态未保存，请重新解锁 | The file has been created, but the unlock status has not been saved. Please unlock it again. | file | `OBSOLETE_LEGACY` | T-18 |
| 9 | 该档案仅保存在本机，不是云端账号，不提供家庭成员身份或设备控制授权。 | The file is only saved locally, not a cloud account, and does not provide family member identity or device control authorization. | file | `OBSOLETE_LEGACY` | T-18 |
| 10 | 解锁本机档案 | Unlock local files | files | `OBSOLETE_LEGACY` | T-18 |
| 11 | 锁定本机档案 | Lock local files | files | `OBSOLETE_LEGACY` | T-18 |

## 5. C/D 处置（9 条，原证据保留）

| 分类 | 旧中文 | 旧英文 | 审查结论 | 复核标记 | 处置 |
|---|---|---|---|---|---|
| C | 版本 | version | `DEPRECATED (heuristic)` | `RECHECK_REQUIRED` | 保留；仅存档 |
| C | 版本 1.1.0 | Version 1.1.0 | `DEPRECATED (heuristic)` | `RECHECK_REQUIRED` | 保留；仅存档 |
| C | 关于 YaoCore | About YaoCore | `DEPRECATED (heuristic)` | `RECHECK_REQUIRED` | 保留；仅存档 |
| C | 检测到开发协议模拟器，拒绝其控制响应 | Development protocol emulator detected, rejecting its control response | `DEPRECATED (heuristic)` | `SAFETY_RECHECK_REQUIRED` | 保留；对应 `errors.app.dev_simulator_rejected` / `GATEWAY_PROFILE_BLOCKED`，不得按关键词删除 |
| C | 检测到开发协议模拟器，正式版禁止将其绑定为真实网关 | The development protocol simulator is detected, and the official version prohibits binding it as a real gateway. | `DEPRECATED (heuristic)` | `SAFETY_RECHECK_REQUIRED` | 保留；同上 |
| C | 旧版本机档案使用不安全的可逆存储，已失效并清除，请重新创建。 | The old version of the machine file uses insecure reversible storage and has expired and been cleared. Please create it again. | `DEPRECATED (heuristic)` | `RECHECK_REQUIRED` | 保留；仅存档 |
| D | Gree/格力 | Gree/Gree | `EXCLUDED (brand data)` | `NONE` | 品牌名作为数据显示，不进入资源包 |
| D | Haier/海尔 | Haier/Haier | `EXCLUDED (brand data)` | `NONE` | 品牌名作为数据显示，不进入资源包 |
| D | Midea/美的 | Midea/美的 | `EXCLUDED (brand data)` | `NONE` | 品牌名作为数据显示，不进入资源包 |

C 类 6 条中 4 条 `RECHECK_REQUIRED`、2 条 `SAFETY_RECHECK_REQUIRED`；D 类 3 条不变。未删除任何 C/D 行。

## 6. 命令与验证证据

所有命令 cwd 为仓库根 `/home/quirkybrain/code/harmony-projects/YaoCore`。

| # | 命令 | 结果 | Exit |
|---:|---|---|---:|
| 1 | `python3 -m py_compile tools/i18n/triage_legacy.py` | `COMPILE_OK` | 0 |
| 2 | `python3 tools/i18n/triage_legacy.py --check`（第 1 次） | `615 rows`；`OK: CSV matches computed triage; invariants pass` | 0 |
| 3 | `python3 tools/i18n/triage_legacy.py --check`（第 2 次） | 同上；CSV SHA-256 前后均为 `75b2cba0…b77e79` | 0 |
| 4 | `python3 tools/i18n/triage_legacy.py --summary` | 615 行；`ACCEPTED=10`、`MIGRATED=46`、`PENDING_REVIEW=6`、`INLINE_LITERAL=0`、`OBSOLETE_LEGACY=544`、C=6、D=3 | 0 |
| 5 | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | `blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16`；CHK-01/02/03/04/06/08/09 PASS；CHK-05 57 findings | 0 |
| 6 | `python3 entry/src/test/i18n/check_i18n.py --root . --allowlist entry/src/test/i18n/allowlist.json --strict-ui` | `blockingFailures=0 warnings=55 missingKeys=0 hardcoded=16`；CHK-05 39 findings | 0 |
| 7 | `entry/src/test/run-host-tests.sh` | `# tests 697`、`# pass 697`、`# fail 0`、`# skipped 0` | 0 |
| 8 | `python3 tools/contract/check_layering.py` | `files=221 violations=0 exceptions_used=6 pending=0`；`PASS` | 0 |
| 9 | 独立断言脚本（见 §6.2） | `ASSERTIONS_OK rows=615`；`legacy_digest=ff9bb3…c3c3f5`；`b_original_remarks_preserved=true` | 0 |
| 10 | 临时副本篡改 `旧中文` 后 `--check` | `INVARIANT 旧中文/旧英文 digest differs from the pre-triage baseline 07895fd…` | 1 |
| 11 | 临时副本篡改 `审查结论` 后 `--check` | `DIFF row 62 [审查结论]`；`FAIL: 1 difference(s)` | 1 |
| 12 | 临时副本删除 C 行 `复核标记` 后 `--check` | `INVARIANT line 33: C row has missing/illegal 复核标记 ''` | 1 |
| 13 | 临时副本删除 D 行 `复核标记` 后 `--check` | `INVARIANT line 13: D row has missing/illegal 复核标记 ''; expected 'NONE'` | 1 |

### 6.1 `--check` 幂等与只读证明

```text
$ python3 tools/i18n/triage_legacy.py --check
i18n legacy triage check: 615 rows
OK: CSV matches computed triage; invariants pass

$ python3 tools/i18n/triage_legacy.py --check
i18n legacy triage check: 615 rows
OK: CSV matches computed triage; invariants pass

CSV sha256 before/after both checks:
75b2cba0a8a27639ed5506804f0a8eb07a066dd6bb3e114557bb95f796b77e79
```

`wp-098` 的第一次 `--write` 把 11 条 B 行恢复为“原备注 + 追加证据”，CSV 从
`efaf44fe…50c67d` 变为 `75b2cba0…b77e79`；再次执行 `--write` 后 SHA-256 保持不变，证明写入幂等。
逐字段核对：相对 `2d45628` 仅 11 个 `备注` 字段变化（CSV 行 44/46/48/49/52/53/69/79/104/144/347），
状态计数与全部映射字段不变。

### 6.2 独立断言脚本

```python
import csv, hashlib, unicodedata
from collections import Counter
rows = list(csv.DictReader(open('entry/src/test/i18n/legacy-migration.csv', encoding='utf-8', newline='')))
assert len(rows) == 615
assert len({r['旧中文'] for r in rows}) == 615

def norm(v):
    return unicodedata.normalize('NFC', v.replace('\r\n', '\n').replace('\r', '\n'))

h = hashlib.sha256()
for r in rows:
    h.update(norm(r['旧中文']).encode('utf-8')); h.update(b'\x1f')
    h.update(norm(r['旧英文']).encode('utf-8')); h.update(b'\x1e')
assert h.hexdigest() == 'ff9bb3f450c3e68b891ef1c0b9db96104d2cde1141ee39d611a14861f5c3c3f5'

accepted_expected = {
    'Wi-Fi 认证失败，请检查密码','保存失败，请重试','编辑','查看','成功',
    '删除','设备离线','失败','取消','刷新失败，请重试',
}
a_statuses = {'ACCEPTED','MIGRATED','PENDING_REVIEW','INLINE_LITERAL','OBSOLETE_LEGACY'}
b_file = '待 T-17/T-18 按页面/组件抽取语义化键; 旧英文机翻/术语错误（file/machine），B 类重译'
b_files = '待 T-17/T-18 按页面/组件抽取语义化键; 旧英文机翻/术语错误（files/machine file），B 类重译'
for i, r in enumerate(rows, 2):
    assert r['审查结论'].strip() and r['备注'].strip()
    assert r['旧中文'].strip() and r['旧英文'].strip()
    cat, status = r['分类'], r['审查结论']
    if cat.startswith('A'):
        assert status in a_statuses
        if status == 'ACCEPTED':
            assert r['目标存储'].strip() and r['目标键'].strip()
            assert r['负责人'] == 'T-10' and r['批次'] == 'T-10'
        elif status == 'MIGRATED':
            assert r['目标存储'].strip() and r['目标键'].strip()
        else:
            assert not r['目标键'].strip()
    elif cat.startswith('C'):
        assert status == 'DEPRECATED (heuristic)'
        assert r['复核标记'] in {'RECHECK_REQUIRED','SAFETY_RECHECK_REQUIRED'}
    elif cat.startswith('D'):
        assert status == 'EXCLUDED (brand data)'
        assert r['复核标记'] == 'NONE'
    else:
        raise AssertionError((i, cat))
accepted = {r['旧中文'] for r in rows if r['审查结论'] == 'ACCEPTED'}
assert accepted == accepted_expected
b_rows = [r for r in rows if r['重译审查'] == 'B_REWRITE_REQUIRED']
assert len(b_rows) == 11
assert all('B_REWRITE_REQUIRED' in r['备注'] for r in b_rows)
assert all(r['备注'].startswith(b_files if r['旧中文'] in {'解锁本机档案','锁定本机档案'} else b_file) for r in b_rows)
print('ASSERTIONS_OK rows=615')
print('status_counts=' + str(dict(Counter(r['审查结论'] for r in rows))))
print('legacy_digest=' + h.hexdigest())
print('accepted_set_is_T10_baseline=true')
print('accepted_new=0')
print('b_rewrite_required=11')
print('b_original_remarks_preserved=true')
print('a_migrated_targets_complete=true')
```

输出：

```text
ASSERTIONS_OK rows=615
status_counts={'OBSOLETE_LEGACY': 544, 'EXCLUDED (brand data)': 3, 'ACCEPTED': 10, 'DEPRECATED (heuristic)': 6, 'MIGRATED': 46, 'PENDING_REVIEW': 6}
legacy_digest=ff9bb3f450c3e68b891ef1c0b9db96104d2cde1141ee39d611a14861f5c3c3f5
accepted_set_is_T10_baseline=true
accepted_new=0
b_rewrite_required=11
b_original_remarks_preserved=true
a_migrated_targets_complete=true
```

### 6.3 负例验证（临时副本，不入库）

负例均在 `/tmp/opencode/wp098-neg/` 的 CSV 副本上执行，仓库文件未被篡改：

| 负例 | 实际输出（摘要） | Exit |
|---|---|---:|
| 修改一条 `旧中文`（追加 `TAMPER`） | `INVARIANT 旧中文/旧英文 digest differs from the pre-triage baseline 07895fd…: expected ff9bb3…, found 80a48d…` | 1 |
| 把一条 `MIGRATED` 改为 `OBSOLETE_LEGACY` | `DIFF row 62 [审查结论]: csv='OBSOLETE_LEGACY' computed='MIGRATED'`；`FAIL: 1 difference(s)` | 1 |
| 删除 C 行 `复核标记` | `INVARIANT line 33: C row has missing/illegal 复核标记 ''; expected one of ['RECHECK_REQUIRED', 'SAFETY_RECHECK_REQUIRED']` | 1 |
| 删除 D 行 `复核标记` | `INVARIANT line 13: D row has missing/illegal 复核标记 ''; expected 'NONE'` | 1 |

负例证明 F-03/F-04 的校验实际生效，且 `--check` 对不可变列与状态字段均返回 exit 1。

## 7. 诚实边界与残余风险

1. **`MIGRATED` ≠ `ACCEPTED`**：46 条只是“旧中文与当前 zh 值精确唯一匹配”的机器证据，没有人工
   复核英文、上下文、术语或可访问性。`重译审查` 仍为 `B_PENDING`（11 条 B 行为
   `B_REWRITE_REQUIRED`）。不得据此把 46 条视为已签署。
2. **`OBSOLETE_LEGACY` ≠ 业务废弃**：544 条只是“当前 locale/源码/资源无精确引用”。T-18 明确
   按页面语义非逐字重写了大量旧文案；这些行可能已有新键但文本不同。归档/删除前必须由 T-17/T-18
   做语义确认，不能把 544 当作可批量删除清单。
3. **实际分布与交接预期不一致**：交接预期“`MIGRATED` 占多数”，实际 46/606（7.6%），544 条
   `OBSOLETE_LEGACY`。原因见 §1：旧字典包含大量 v1 未实现的旧功能/旧版本/旧配网/旧云文案；
   当前 526 个不同 zh 值不可能与 615 条旧字符串多数一一对应。工具没有放宽匹配或批量签收。

   **T-18 的 59 条逐条对账（F-01 修正）**：

   | T-18 §3.1 组成 | 数量 | 当前 CSV 状态 | 说明 |
   |---|---:|---|---|
   | rawfile exact | 41 | `MIGRATED` | 与当前 41 条 rawfile MIGRATED 一一对应 |
   | pending exact | 6 | `PENDING_REVIEW` | 6 条全部对应 |
   | T-10 exact | 6 | `ACCEPTED` | 编辑/查看/成功/删除/失败/取消 |
   | T-10 normalized | 3 | `ACCEPTED` | Wi-Fi 认证失败…/设备离线/刷新失败，请重试 |
   | normalized-only | 3 | `OBSOLETE_LEGACY` | 操作失败，请重试/密码至少 8 位/未找到场景 |
   | **合计** | **59** | | **53 exact + 6 normalized** |

   当前 CSV 另有 5 条 `string.json` `MIGRATED` 不在 T-18 清单内：场景（`tab_scenes`）、房间
   （`tab_rooms`）、首页（`tab_home`）、添加设备（`page_provisioning`）、我的（`tab_profile`）。
   T-10 共 10 条 `ACCEPTED`：6 条 exact + 4 条仅句号归一化（Wi-Fi 认证失败…、保存失败，请重试、
   设备离线、刷新失败，请重试）；T-18 清单只列其中 9 条，未列 `保存失败，请重试`。因此：
   - T-18 的 59 = 53 exact + 6 normalized，全部可核对；
   - 当前精确规则下的 exact 行 = 46 MIGRATED + 6 PENDING + 6 exact ACCEPTED = 58；
   - “59 与 T-18 一致”只在总数上巧合，集合并不相同；当前 triage 比 T-18 多出 5 条 `string.json`
     精确匹配，同时 T-18 有 3 条 normalized-only OBSOLETE 不在当前 exact 统计中。
   证据见 §1 与 `artifacts/50-implementation/t18-ui-pages.md` §3.1。
4. **源码扫描范围有限**：只扫描 `entry/src/main/ets/**` 与 `entry/src/main/resources/**`；
   不扫描 `input/`（旧 `I18nService.ets` 本身是待迁移源，扫描会自证）、`entry/src/test/**`、
   `artifacts/**`。若旧文案以拆分拼接、动态构造、注释或文档形式存在，当前工具不会发现。
5. **`INLINE_LITERAL=0` 不等于源码零硬编码**：`check_i18n --strict-ui` 仍有 16 条 CHK-07 告警
   （AC 品牌/模式技术字面量、Mock 文案、主题注释）；它们不是本次 triage 的 A 类旧字典行，
   本次也未修改 UI 代码。另有 57 条 CHK-05 未使用键告警（无 allowlist 时）；带 allowlist 时
   CHK-05 仍为 39 条、总告警 55 条。0 blocking / 0 missing 是本次门禁要求，不等于 0 warnings。
6. **跨存储重复**：6 条 `PENDING_REVIEW` 中有 5 条暴露同一逻辑文案同时存在于 rawfile 与
   `string.json`（关闭/刷新/添加网关/简体中文/语言；`执行中` 是 rawfile 同存储三义）。这触及
   “一条逻辑文案只落一个存储”的设计规则；本次按规则保留歧义，未擅自删除任一键。需
   solution-architect/T-17/T-18 决定。
7. **B 类 11 条仍未重译**：当前 en-US 已使用 `profile` 且无 `machine/file(s)`，但 11 条旧英文
   仍有术语错误；本次只补证据，未改 `重译审查` 状态，也未改英文。
8. **C/D 仍需人工复核**：6 条 C（含 2 条 DEV-ONLY/模拟器安全文案）与 3 条 D 原样保留；
   未删除、未降级、未改复核标记。
9. **上游文档滞后**：`artifacts/80-maintenance/maintenance-plan.md` §3.4、根 `README.md` 第 78 行、
   `artifacts/90-integration/integration-report.md` 仍写“596 条 PENDING_REVIEW”。它们不在本次
   写范围（`entry/src/test/i18n/`、`tools/`、`artifacts/50-implementation/`），需由对应 owner
   在后续文档/维护任务同步。`entry/src/test/i18n/migration-boundary.md` 与
   `entry/src/test/i18n/README.md` 已同步本次 triage 结果；`README.md` §4 的 CHK-05 口径已在
   `wp-098` 更新为当前实测：无 allowlist 57 条、带 allowlist 39 条（总 warnings 73/55；
   0 blocking / 0 missing）。
10. **工具不变量边界**：`--check` 比对工具拥有的字段，校验 T-10/T-18 基线、615 行与 `旧中文`
    唯一性、`07895fd` 旧文案规范化 SHA-256（F-03），以及 C/D `复核标记` 合法性（F-04）；
    它不替代独立 quality-review，也不验证英文质量、语义正确性或 UI 上下文。`OBSOLETE_LEGACY` 的
    `目标存储` 保留原启发式建议，`目标键` 为空；这是有意区分“未验证目标”与“已验证映射”。

## 8. 变更文件与 traceability

| 文件 | 变更 | 说明 |
|---|---|---|
| `entry/src/test/i18n/legacy-migration.csv` | `wp-096`: 596 行更新；`wp-098`: 11 条 B 行 `备注` | `wp-096` 更新 `审查结论`/`目标存储`/`目标键`/`备注`；`wp-098` 仅恢复 11 条 B 行原备注并追加证据（F-02）；旧中文/旧英文原文不变；C/D/ACCEPTED 未变；状态计数不变 |
| `tools/i18n/triage_legacy.py` | 新增；`wp-098` 修改 | 可复现 triage/`--check`/`--summary`/T-10/T-18 基线不变量；新增 `07895fd` 旧文案摘要、615 行/唯一性、C/D `复核标记` 校验与 B 原备注保留（F-02..F-04） |
| `entry/src/test/i18n/migration-boundary.md` | 更新 §3/§5 | 新状态语义、统计、6 条 PENDING 清单、B/C/D 处置、工具路径与校验口径 |
| `entry/src/test/i18n/README.md` | 更新 §4/§5 | 登记表 triage 结果、工具路径与 CHK-05 当前实测口径（F-05） |
| `artifacts/50-implementation/t24-i18n-triage.md` | 新增；`wp-098` 修正 | 本报告；修正 T-18 59 条证据链（F-01）、B/C/D 与工具边界 |

Traceability：

- Maintenance plan §3.4（596 条逐条 triage 关闭条件）→ 本报告 §3–§6；
- `migration-boundary.md` §3（分类/状态语义）→ 本报告 §2–§5；
- I18N-DESIGN §5 / DES-B §7.4.3–§7.4.4 → `MIGRATED` 目标存储/键证据；
- T-10 的 10 条 `ACCEPTED` → 工具固定基线 + 独立断言；
- T-18 的“59 条可自动核对” → 本报告 §1/§7.3 的逐条对账：41 MIGRATED + 6 PENDING +
  9 ACCEPTED（6 exact + 3 normalized）+ 3 normalized-only OBSOLETE = 59（53 exact + 6 normalized）；
  当前 triage 另有 5 条 T-18 之外的 `string.json` `MIGRATED`；
- `artifacts/70-review/t24-i18n-review.md` F-01..F-05 → 本报告 §1/§2/§6/§7.3/§7.9/§7.10/§8、
  `tools/i18n/triage_legacy.py`、`entry/src/test/i18n/README.md`；
- B 类 11 条 → 本报告 §4 与 CSV `重译审查=B_REWRITE_REQUIRED`；
- C/D 9 条 → 本报告 §5 与 CSV 原证据。

**未做**：未修改任何 locale 值、UI 代码、DES/架构文档、allowlist、checker 或 host 测试；
未切换分支、未 pull/merge/rebase/push；未把任何未人工复核行标 `ACCEPTED`；未改变 46/6/544/10/6/3
计数或任何已核对映射。
