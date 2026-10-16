# i18n 资源设计（Internationalization Resource Design v1.0）

- **Artifact ID**: I18N-DESIGN-001（I18N-001 的架构设计部分）
- **Producer**: agent:solution-architect
- **Type**: Architecture / Detailed Design Contract（i18n 资源与键位规范）
- **Status**: Proposed（待 G-004 门禁批准）
- **Date**: 2026-10-17
- **Task**: `wp-004-contracts`（task 分支 `task/wp-004-contracts`，父分支 `feat/yaocore-app`，base commit `54c1d786`）
- **Workflow**: STANDARD / GATED_AUTO
- **Upstream**: `docs/internationalization.md`（INT）；`input/standards/ArkTS_Coding_Standards.md` L26-28（STD）；需求 L138-139（FR-SET-003）；`config/project.md` L53；`WP3` §3.6/§5-P1-11；`INV` I18N-001/L170/L259；ADR-004 §7.2（语言入口）
- **Downstream**: wp-006 DES-001（I18nService 接口）、实现任务（UI/服务/错误文案）、TEST-001（locale 切换与 fallback 测试）、评审门禁（防硬编码 + key parity）

---

## 1. 目标与范围

1. 落实 INT 的"单代码库 + 外部化资源包 + 动态键值查找"三原则，满足 FR-SET-003（zh-CN/en-US 切换，需求 L139）与 STD L26-28（资源引用或 `I18nService.t('...')`）。
2. 定义：locale 集合与解析、资源文件布局与**存储边界**、语义化键规范、fallback 链、旧 615 条内联字典的迁移边界、**评审用键位对齐与防硬编码门禁**。
3. 不在本文范围：具体页面文案内容（由 UIUX/实现产出）、I18nService 的类结构（wp-006）、翻译流程与外包工具。

---

## 2. Decision 1：locale 集合与解析

| 项 | 裁定 | 依据 |
|---|---|---|
| 支持 locale | **zh-CN（基准/源语言）**、**en-US** | 需求 L139（中英双语）；INT L62（默认基准源语言 + 英文） |
| 代码/接口中的 locale 标识 | BCP-47：`zh-CN`、`en-US` | 本设计（与 rawfile 文件名一致） |
| HarmonyOS 资源目录限定符 | `base`（= zh-CN 内容）、`en_US`（**下划线**命名，平台约定） | STD L27 的 `resources/base` + `resources/en_US` 写法 |
| 用户偏好 | `auto`（跟随系统）/ `zh-CN` / `en-US`，持久化于 Preferences（非秘密） | ADR-004 §7.2；INT L62 |
| `auto` 解析规则 | `zh*` → `zh-CN`；`en*` → `en-US`；**其他系统语言 → 基准（zh-CN）** | 与 HarmonyOS 资源解析行为保持一致：`en_US` 限定符只匹配 en 系 locale，其他 locale 落到 `base`；若 App 自研解析与平台不一致，会出现"`$r` 文案中文、`t()` 文案英文"的混排 |

**拒绝的替代**：非中英系统语言回退 en-US（会导致两套存储的解析结果劈裂，见上）；增加第三 locale（ja-JP 等，INT L32 示例）——v1 不做，但目录/命名规范预留扩展位（新增 locale = 新增 `resources/<lang>_<REGION>/element/string.json` + `resources/rawfile/i18n/<lang>-<REGION>.json`，代码零改动）。

**语言入口**（C-018）：Settings 页提供"跟随系统 / 简体中文 / English"，切换即时生效（重载资源并重渲染，无需重启）；位置与控件形态见 ADR-004 §7.2 与 UIUX 补丁 P-10。

---

## 3. Decision 2：资源布局与存储边界（HarmonyOS 资源限定符 vs I18nService）

### 3.1 布局

```text
entry/src/main/resources/
├── base/
│   └── element/
│       └── string.json          # 基准语言（zh-CN 内容）：静态 UI 文本 + 应用元数据
├── en_US/
│   └── element/
│       └── string.json          # English：与 base 键集 100% 对齐
└── rawfile/
    └── i18n/
        ├── zh-CN.json           # 动态/参数化文本（源语言）
        └── en-US.json           # 动态/参数化文本（英文，键集 100% 对齐）
```

- `string.json`：ArkTS 资源系统（`$r('app.string.<key>')`）；平台负责 locale 限定符匹配与系统级 fallback；
- `rawfile/i18n/*.json`：由 `I18nService` 在启动与切换语言时加载（`resourceManager.getRawFileContent`，UTF-8），支持点分键查找与 `{param}` 插值（INT L38-48、L115-133 的参考实现语义）。

### 3.2 存储边界（决定性规则：一个 key 只能存在于一个存储）

| # | 情形 | 存储 | 访问方式 |
|---|---|---|---|
| 1 | 非 UI 层（Service/ViewModel/协议错误映射/通知）产生的文本；或需要运行时参数（`{name}`/`{count}`）的文本 | **rawfile/i18n** | `I18nService.t('errors.gateway.bad_signature', { … })` |
| 2 | ArkUI 组件中的**静态**字面文案（页面标题、Tab、按钮、固定标签），无需参数 | **base/en_US string.json** | `Text($r('app.string.tab_home'))` |
| 3 | 系统/配置要求经资源引用的项（app 名称、ability label、通知 label 等元数据） | **string.json** | 资源引用 |
| 4 | 动态数据（设备名、房间名、网关名、传感器数值、状态来源标签值） | 不进入资源包 | 数据驱动 + 第 1 类的标签键（如 `stateSource.sensor_physical`） |

- 规则 1 与 2 的判定口诀：**"会带参数或来自代码路径 → rawfile；纯静态 UI 字面量 → string.json；不确定时选 rawfile"**（避免出现"某个 key 在另一个存储里"的返工）；
- **禁止**同一逻辑文案在两个存储各写一份（评审项，见 §6.4）；
- 键名格式差异：`string.json` 的资源名只允许 `[A-Za-z0-9_]`（用 `snake_case`，如 `tab_home`）；rawfile 用点分命名空间（如 `home.tab.title`）。

### 3.3 键位命名规范（rawfile 存储）

- 点分命名空间，层级 ≤4：`<域>.<子域>.<元素>[.<变体>]`（INT L38-42）；
- 域清单（v1，扩展需评审）：`common`、`home`、`room`、`device`、`door`、`ac`、`scene`、`family`、`invite`、`member`、`provisioning`、`gateway`、`ble`、`security`、`cloud`、`settings`、`onboarding`、`errors`、`stateSource`、`notifications`、`a11y`；
- 示例：`errors.gateway.bad_signature`、`errors.app.local_request_failed`、`door.state.unconfirmed`、`invite.security.weak_mode_warning`、`stateSource.device_feedback`、`home.metric.rtt_ms`；
- 参数插值只允许 `{name}` 形式（INT L43-49）；**禁止**句子拼接（`t('a') + name + t('b')`）；
- 复数处理（v1 最小契约，避免引入 ICU）：英文按 `_one` / `_other` 变体后缀（如 `device.count_one` = `{count} device` / `device.count_other` = `{count} devices`），中文只用基键；选择规则：`count==1 → _one`，否则 `_other`（仅 en-US 生效）；无变体时回退基键；
- 键名不得包含文案本身（**取代**旧字典的"文本即键"方案，见 §5）；
- 状态/错误键的取值化命名：`errors.gateway.<error_code 小写>`、`stateSource.<值去点转下划线>`（`device.feedback`→`stateSource.device_feedback`）。

---

## 4. Decision 3：fallback 链与缺失行为

```text
t(key)：
  1) 当前 locale 的 rawfile 包 → 命中即返回（含复数变体选择与插值）
  2) 基准 locale（zh-CN）rawfile 包 → 命中即返回（记录 missing-in-locale 警告，供 parity 门禁消费）
  3) 返回 key 文本本身（非空、可追踪），并在 Debug 构建输出告警；Release 不得抛异常、不得空白
```

- 与 INT L50-52（"必须配置兜底默认语言…严禁直接抛出未捕获异常或展示空白界面"）及参考实现 L128-133（最后返回 `key`）一致；
- `string.json` 侧由平台处理 `en_US → base` 回退（首选项设置 `auto` 时按 §2 解析）；
- `I18nService` 必须在语言切换后**立即**重载 rawfile 包并通知 UI（观察者/AppStorage），使两类存储的显示语言始终一致；
- **运行时不联网获取语言包**（离线优先；与 INT 的"按需加载"指本地加载，不引入网络依赖）。

---

## 5. Decision 4：旧 615 条内联字典的迁移边界

### 5.1 现状（证据）

- 归档 `input/existing/original_app/service/I18nService.ets`：685 行，`case '<中文>': return '<英文>';` 形式的 **615 条**"文本即键"内联字典（`INV` L170/L259）；
- 字典仅覆盖 zh→en；无资源包文件；模板工程为单语占位（`INV` I18N-001）；
- 归档代码属 LEGACY-001（行为参考，非权威；`WP2` §4）。

### 5.2 裁定

1. **禁止机械迁移键名**：`case '中文'` 的键方案与"语义化键"（INT L38-42）直接冲突，**不得**照搬为新键；旧"中文键"仅可作为**翻译记忆**来源（把旧英文值用作新英文文案的草稿）。
2. **禁止整体导入**：旧 `I18nService` 不进入新代码库；新 App 从零建立键空间（由 PRD/UIUX/`contract-baseline.md` §4.4 推导）。
3. **逐条分类（迁移任务执行，规则化）**：

| 分类 | 判定规则 | 处置 | 估算（启发式，需逐条登记） |
|---|---|---|---|
| **A 迁移（重键）** | 文案对应 v1 仍在实现的行为（设备/房间/家庭/配网/控制/错误/状态来源/云配置等） | 抽取到目标键；英文取旧值草稿并做语法/术语审查 | 约 70% |
| **B 重译** | 英文为机翻痕迹/术语不一致（如大小写不一、直译）；或与 `contract-baseline.md` 术语表冲突 | 重写英文；不得沿用旧值 | 约 15-20% |
| **C 废弃** | 旧版专属：版本/关于文案、已移除功能、demo 提示、旧存储迁移提示等（启发式命中：`版本`/`关于`/`旧版本机`/`模拟器` 等，初筛 4+13+1 条） | 不迁移；仅存档于 LEGACY-001 | 约 3-5% |
| **D 排除** | 品牌专名（`Gree/格力`、`Midea/美的` 等 3 条）与纯数据值 | 品牌名作为**数据显示**（不进入资源包）；如确需展示用 `brand.<key>` 专名表且英文=原名 | 3 条（已确认） |

   > 估算方法：对 615 条做关键词/模式启发式分类（版本/关于 4 条；模拟器/开发 13 条（含应迁移的协议提示）；品牌 3 条；旧存储迁移 1 条；其余 594 条落入 A/B 待逐条判定）。**数量仅供任务估算，迁移任务必须以逐条登记表为准**（登记表列：旧中文、旧英文、分类、目标键、审查结论）。
4. **迁移完成的判据**：v1 全部 UI/代码路径的文本均经 §6 门禁（零硬编码 + key parity + 无 missing）；旧字典不再被任何构建产物引用。
5. **术语一致性**：以 `contract-baseline.md` 的命名（gateway/device/room/family/ACK/影子 等）为术语基准，避免"AP/热点/路由"等混用（翻译审查项）。

---

## 6. Decision 5：评审用键位对齐检查方案（防硬编码门禁）

### 6.1 为什么需要（对应 INT L62-67 的职责分工）

评审必须能机械验证：① 零硬编码；② 各 locale 键集 100% 对齐；③ 插值与复数变体一致；④ 无未使用/未定义键；⑤ 无多语言代码分叉。为此定义可在 CI 与人工评审重复执行的检查方案。

### 6.2 检查工具形态与落位（供 wp-005 立项）

- **形态**：独立脚本（Python 3 标准库或 Node；运行于开发机/CI，**不进入** ArkTS 构建链）；
- **路径建议**：`tools/i18n/check_i18n.py`（或 `.mjs`）+ 报告输出 `reports/i18n/<date>-i18n-report.json`；
- **输入**：`base/en_US string.json`、`rawfile/i18n/{zh-CN,en-US}.json`、源码树（`entry/src/main/ets/**`）、允许清单文件（§6.4）。

### 6.3 检查项（CHK-01..CHK-09）

| ID | 检查 | 方法 | 失败级别 |
|---|---|---|---|
| CHK-01 | **键集对齐（rawfile）** | 比较 `zh-CN.json`/`en-US.json` 的键路径集合（含 `_one/_other` 变体展开） | 阻断（INT L66） |
| CHK-02 | **键集对齐（string.json）** | 比较 `base`/`en_US` 的键集合 | 阻断 |
| CHK-03 | **插值参数对齐** | 提取每个键的 `{param}` 集合，跨 locale 必须相同（顺序无关）；参数名只允许 `[a-zA-Z][a-zA-Z0-9_]*` | 阻断 |
| CHK-04 | **空值/占位检测** | 值不得为空、不得全为占位符（如 `TODO`、`??`）；不得含未闭合大括号 | 阻断 |
| CHK-05 | **未使用键** | 扫描代码中 `t('…')`、`$r('app.string.…')`、拼装键模式（禁止动态拼键，例外需登记） | 告警（报告）+ 评审确认 |
| CHK-06 | **未定义键** | 代码引用的键必须存在于对应存储；缺失 → 运行时会退化到 key 文本 | 阻断 |
| CHK-07 | **硬编码扫描** | 对 `entry/src/main/ets/**` 中字符串字面量/模板串扫描：包含 CJK 字符或英文句子（≥3 个词）即命中；对 UI 目录（`pages/`、`components/`）命中即阻断；对非 UI 目录落入允许清单判定 | 阻断（UI）/告警（其余） |
| CHK-08 | **多语言代码分叉** | 检测疑似分叉：文件/目录名含 `_en`/`_zh`/`English`/`Chinese`；`if (isChinese())` 直接返回字面量（非 `t()`） | 阻断（INT L17/L66） |
| CHK-09 | **locale 目录结构** | 存在且仅存在声明支持的资源目录；两个存储的 locale 集合一致（`base`/`zh-CN` 视为基准） | 阻断 |

### 6.4 允许清单（Allowlist 规则，评审可核）

| 类别 | 判定 |
|---|---|
| 注释与文档字符串 | 允许 |
| 协议常量/键名（`online`、`app-key-v1`、端点名 `yaocore-id`、header 名等） | 允许（非用户可见文本） |
| `console.*`/异常抛出里的技术文本 | 允许，但必须英文、不得含用户数据/秘密（SC-06/SC-13） |
| 测试夹具/`ohosTest` 中的期望值 | 允许（置于测试目录，不进生产包） |
| DEV-only 仿真器标记（`DEV-ONLY` 等） | 允许（协议常量） |
| 其它 | 必须由评审在允许清单文件中逐条登记（文件+行+理由），清单纳入版本控制 |

### 6.5 评审执行约定

1. **门禁时点**：Component Quality Gate（每次实现交付）与 Integration Gate（跨组件）各执行一次 CHK-01..CHK-09；Stage Gate 复核报告与允许清单差异；
2. **人工抽查**：评审者抽查 ≥10 个 UI 文案的键路径与两种 locale 的实际渲染（含 `en-US` 下长文本不截断，INT L64 的 20-40% 膨胀检查）；
3. **locale 切换测试**：TES（`test-engineer`）验证运行中切换（无需重启）后 UI 与 `t()` 文本同步更新、缺 key 走 fallback 且不崩溃（INT L67）；
4. **报告留痕**：`reports/i18n/` 报告作为 Gate 证据（约束 ID：I18N-02/I18N-05）。

---

## 7. Decision 6：错误与状态文案的键映射约定（与契约基线联动）

| 来源 | 键模式 | 示例 |
|---|---|---|
| 网关 `result_code`（`contract-baseline.md` §4.1） | `errors.gateway.<error_code 小写 snake>` | `errors.gateway.bad_signature`、`errors.gateway.device_offline`、`errors.gateway.hardware_timeout` |
| 网关 `error_code` 细分（1006） | `errors.gateway.<细分>` | `errors.gateway.unknown_device`、`errors.gateway.unsupported_action` |
| 未知 result_code | `errors.gateway.unknown`（+ `${code}` 参数） | `t('errors.gateway.unknown', {code})` |
| App 自有错误（§4.2） | `errors.app.<SNAKE 小写>` | `errors.app.tls_pin_mismatch`、`errors.app.local_request_failed` |
| 状态来源 | `stateSource.<值>` | `stateSource.sensor_physical`、`stateSource.device_feedback`、`stateSource.automation_local`、`stateSource.app_lan`、`stateSource.app_cloud` |
| 空调模式 | `ac.mode.<小写>` | `ac.mode.cool`、`ac.mode.eco` |
| 门锁三态/报警（ADR-004 §6） | `door.state.*` / `door.alert.*` | `door.state.secured`、`door.state.unconfirmed`、`door.alert.unconfirmed` |
| 安全通道（ADR-002 §6.3） | `gateway.security.*` | `gateway.security.tls_pinned`、`gateway.security.hmac_only`、`gateway.security.pin_mismatch` |
| 邀请安全边界（ADR-003 §8） | `invite.security.*` | `invite.security.weak_mode_warning`、`invite.security.rotate_recommended` |
| BLE 配网错误（BLE 设计 §7） | `provisioning.error.*` | `provisioning.error.pop_invalid`、`provisioning.error.auth_error`、`provisioning.error.network_not_found` |

- **映射实现**：`errorCodeToI18nKey(resultCode, errorCode?)` 与 `stateSourceToI18nKey(value)` 为纯函数（wp-006 定义签名）；UI 层禁止手工 if-else 字面量；
- **文案纪律**：不得把 `message` 原文展示给用户（`contract-baseline.md` §2.3/§4.4）；安全边界提示（弱邀请模式、机密性未启用、未验证到位）为**强制存在**的文案键（缺失即评审不通过）。

---

## 8. Consequences / Alternatives / Risks

**正**：单一代码库 + 双存储边界明确，UI 与代码路径都有统一入口；键集与插值可机械校验（门禁可执行）；旧字典的"文本即键"缺陷被显式禁止，翻译资产以翻译记忆方式复用；fallback 与平台解析行为一致（无双存储劈裂）。

**负 / 风险**：
- 双存储带来两套键格式与两个 parity 检查（CHK-01/CHK-02）——以"一个 key 只存一处"的规则与边界口诀缓解；
- 615 条迁移是一次性人工成本（含重译与术语统一），估算 3-5 天量级（归 wp-005 任务切分）；
- CHK-07 的"英文句子"启发式可能误报（技术字符串），需允许清单维护纪律；
- ArkTS 生态缺少现成 i18n 校验工具，脚本需自建（低成本，纯文本处理）。

**Alternatives**：
- **A1 全部使用 rawfile + `t()`（单一存储）**：部分采纳（用于动态/参数化），但会失去 `$r`/平台 fallback 与系统资源引用（app 元数据必须 `string.json`），且 UI 文案全部经函数调用；否决"全部"、采用 §3.2 边界。
- **A2 全部使用 `string.json`**：否决——`string.json` 不适合参数化（无插值语义）与 Service 层动态文案（需 ResourceManager 依赖），且无法承载复数/结构键。
- **A3 保留"文本即键"字典迁移**：否决——违反 INT L38-42 语义化键，且键内容随文案变化而漂移（旧实现已出现键/值不同步风险）。
- **A4 引入第三方 i18n 库**：v1 否决（ArkTS/HarmonyOS NEXT 生态整合成本、离线与审核约束）；自研轻量 `I18nService`（INT 参考实现语义）足够。
- **A5 运行时下载语言包**：否决（离线优先；无服务器依赖）。

**假设**：
- I18N-A1：HarmonyOS 资源限定符目录命名 `en_US`（下划线）与 `$r('app.string.*')` 可用性在目标 SDK 已验证（STD L27 即为该写法；实现期在构建中确认）。
- I18N-A2：rawfile 读取在 API 14+ 可用同步/异步两形态（实现期以 wp-006 选定形态）。

---

## 9. References

`docs/internationalization.md` L7-67/L73-133；`ArkTS_Coding_Standards.md` L26-28；`YaoCore_HarmonyOS_App_Requirements.md` L138-139；`UI_UX_Specification.md` L68-70；`config/project.md` L53；`artifacts/00-project-intake/inventory.md` L170/L259；`input/existing/original_app/service/I18nService.ets`（685 行 / 615 case）；归档 `DevicePage.ets` L2216-2227（旧状态来源文案，弃用）；ADR-004 §7.2；`contract-baseline.md` §4.4/§6.1/§6.3；`WP3` §3.6/§5-P1-11。

---

*i18n 资源设计结束。工具脚本与门禁整合由 wp-005 立项（TEST-001 并行）；I18nService 接口形态由 wp-006 DES-001 定义，本文档的规则为其约束输入。*
