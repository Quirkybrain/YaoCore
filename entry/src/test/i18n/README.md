# i18n 资源、I18nService 与检查器（T-10）

- **Producer**: agent:implementation-engineer
- **Task**: T-10 / `wp-031-i18n`；评审修复 `wp-033-fix-t10`；证据化 triage `wp-096-i18n-triage`
- **Contract**: DES-B §7；`artifacts/20-architecture/i18n-resource-design.md`（I18N-DESIGN-001）；CB §4.4；PROJECT-CONSTRAINTS §5；`docs/internationalization.md`
- **状态**: 产品代码/资源/host 逻辑测试/检查器完成；T-10 评审修复已落地；组件 `UNVERIFIED`（待独立复审与 CQG-T10）。设备侧执行 `BLOCKED`。

## 1. 目录

```text
entry/src/main/ets/service/i18n/
├── I18nModels.ets        # SupportedLocale/LocaleMode/I18nParams/I18nKey/事件/加载结果
├── I18nPorts.ets         # I18nResourceLoaderPort / LocaleApplierPort
├── I18nService.ets       # locale 解析/加载/t()/fallback/复数/插值/观察者/回滚
├── I18nKeys.ets          # 语义化键构造（错误/状态来源/AC 模式/成员/设备/安全档案）
├── ErrorI18nMapper.ets   # DES-A §24 唯一错误映射入口的包装实现
├── I18nBundleCodec.ets   # 纯 JSON→扁平 bundle 解析与校验（host 可测）
├── RawfileI18nLoader.ets # COMPILED_ONLY：ResourceManager 读取 rawfile
└── OhosLocaleApplier.ets # COMPILED_ONLY：系统 locale 读取 + ApplicationContext.setLanguage

entry/src/main/resources/
├── base/element/string.json       # zh-CN 静态 UI + 元数据（25 键）
├── en_US/element/string.json      # en-US（键集 100% 对齐）
└── rawfile/i18n/{zh-CN,en-US}.json # 动态/参数化/错误/状态标签（212 个逻辑键）
```

## 2. 存储边界（I18N-DESIGN §3.2）

| 文本类型 | 存储 | 访问 |
|---|---|---|
| 非 UI/带参数/错误/通知/数据驱动标签 | `rawfile/i18n/*.json` | `I18nService.t()` / `I18nKeys` / `ErrorI18nMapper` |
| ArkUI 静态字面量（按钮/固定标签/语言选项） | `base`/`en_US` `string.json` | `$r('app.string.common_confirm')` |
| app/ability 元数据 | `AppScope` + `string.json` | `$string:` / `$r` |
| 动态数据（设备名/房间名/数值） | 不进资源包 | 数据 + 标签键 |

- 一个逻辑文案只落一个存储；rawfile 使用点分语义键（≤4 层），`string.json` 使用 `snake_case`。
- 英文复数只用 `_one`/`_other`；中文只用基键。`en-US` 缺变体时回退基键，再回退 zh-CN 基键。
- `t()` 同步、不抛异常、不返回空白；当前 locale 缺失时回退 zh-CN，再缺失返回 key 文本并记录诊断。

## 3. 键统计与 parity

| 存储 | zh-CN | en-US | 说明 |
|---|---|---|---|
| rawfile 逻辑键 | 212 | 212（213 个物理键，`device.count` + `_one`/`_other`） | CHK-01/03/04 PASS |
| `string.json` | 25 | 25 | CHK-02 PASS |
| `errors.*` | 110 | 110 | 含 `errors.scene.run_in_progress` 与 `errors.app.scene_run_in_progress` 兼容键 |
| `provisioning.error.*` | 23 | 23 | 配网错误族 |
| `stateSource.*` / `ac.mode.*` | 6 / 8 | 6 / 8 | 5 值溯源 + unknown；7 值模式 + unknown |

权威错误码覆盖：DES-A §3.2.3（96 行，含 `HTTP_<status>` 模板）+ DES-B §23.4（36 行）共 131 个具体 code；
`ErrorCatalog.resolve()` 的 i18nKey 与权威表逐项一致，并全部存在于 zh/en rawfile。产品当前可达 code 为
69 个静态 `AppErrors.*` 调用 + 5 个动态 code（`DEVICE_DISABLED`/`DEVICE_UNASSIGNED`/`ASSET_*`）= 74 个。
Host 测试 `T10_C14_authoritativeCatalog_everyDeclaredCodeHasBothLocaleKeys` 直接解析 DES-A/DES-B
权威表，另扫描产品源码中的静态 code，防止再次遗漏。

## 4. 检查器（CHK-01..CHK-09）

```bash
python3 entry/src/test/i18n/check_i18n.py \
  --root . \
  --report entry/src/test/evidence/t10-i18n-report.json \
  --allowlist entry/src/test/i18n/allowlist.json \
  --strict-ui
```

- 退出码：`0` 全部阻断项通过；`1` 存在阻断失败；`2` 输入/工具错误。
- CHK-01 rawfile 键集（含复数展开）；CHK-02 string.json 键集；CHK-03 插值参数；CHK-04 两个存储的空值/占位/括号；
  CHK-05 未使用键（告警）；CHK-06 未定义键；CHK-07 硬编码（UI 阻断、非 UI 告警 + allowlist；短英文 UI 占位默认
  **advisory warning**，`--strict-ui` 时提升为 **blocking**）；CHK-08 多语言代码分叉；CHK-09 locale 目录结构。
- `--strict-ui` 不是 no-op（T-20 F-05）：它只提升短英文 UI 文案的严重级别，不改变 CJK/英文句子规则；
  SCREAMING_SNAKE/CamelCase 等技术常量不作为 UI 文案。报告字段 `strictUi` 记录本次是否启用。
- `allowlist.json` 支持三类条目：`entries`（文件+正行号，用于 CHK-07）、`keyEntries`（精确键）、
  `keyPrefixes`（为 T-17/T-18 预留的 UI/动态键前缀）。每项必须有非空前缀/键/文件名与理由，否则检查器以
  exit 2 拒绝。
- 正负夹具：`entry/src/test/i18n/fixtures/good|bad/`；host 测试断言 good=0、bad=1 且 CHK-01/02/03/04/06/07/08/09 阻断；
  bad 夹具同时验证 `string.json` 的 `TODO` 与未闭合括号会被 CHK-04 命中。`fixtures/short-ui/` 专门验证
  `--strict-ui` 将短英文 UI 从 warning 提升为 blocking（默认 exit 0，strict exit 1）。
- 当前生产树：0 阻断；CHK-07 不再对状态常量（如 `'LOADING'`/`'RECONFIGURE'`）误报，当前短英文 UI 告警为 0；
  `--strict-ui` 用于门禁时仍会阻断未来真实短文案回归。CHK-05 的 0 告警依赖 keyPrefixes 与动态前缀，
  不等于“无未使用键”。

> **路径偏差（正式例外 T10-EX-01）**：DES-B §7.4.4 / delivery-plan 指定 `tools/i18n/check_i18n.py`、
> `tools/i18n/allowlist.json`、`tools/i18n/legacy_migration.csv`、`reports/i18n/*`；`wp-031-i18n` handoff 的
> 写范围未授权 `tools/`，因此检查器/allowlist/迁移表落在 `entry/src/test/i18n/`、报告落在
> `entry/src/test/evidence/`。该偏差不影响 CHK 语义；后续工具任务迁移到契约路径，命令与报告 schema 不变。
> `wp-096-i18n-triage` 已将 triage 工具落到契约目录 `tools/i18n/triage_legacy.py`；登记表仍留在
> `entry/src/test/i18n/legacy-migration.csv`，`T10-EX-01` 对检查器/allowlist/迁移表继续有效。

## 5. 迁移边界与登记表 triage

- 旧 `input/existing/original_app/service/I18nService.ets` 的 615 条“中文即键”字典**不进入产品代码**；
  逐条登记表见 `legacy-migration.csv`（615 条），边界与批次见 `migration-boundary.md`。
- **证据化 triage（wp-096）**：`tools/i18n/triage_legacy.py` 对 615 行逐条重算，结果：
  - A 类 606：`ACCEPTED` 10（仅 T-10 人工复核）、`MIGRATED` 46（精确唯一当前键，机器证据）、
    `PENDING_REVIEW` 6（多键歧义，需人工择一）、`INLINE_LITERAL` 0、`OBSOLETE_LEGACY` 544
    （无精确当前引用；不等于业务废弃）；
  - C 类 6：`DEPRECATED (heuristic)`，4 条 `RECHECK_REQUIRED` + 2 条 `SAFETY_RECHECK_REQUIRED`；
  - D 类 3：`EXCLUDED (brand data)`。
  - `MIGRATED` 不等于 `ACCEPTED`；本次 triage **未新增**任何 `ACCEPTED`。
- B 类（重译）是 A 类的英文子审查，登记于 `重译审查` 列：11 条已识别 `B_REWRITE_REQUIRED`（`档案` →
  `file(s)`/`machine`），585 条 `B_PENDING`；10 条 `B_REVIEWED_ACCEPTED`。这 11 条旧英文仍含
  machine/file(s) 术语，当前 en-US 已不使用该术语（使用 `profile`）；triage 未改其 `审查结论` 为
  `ACCEPTED`。C 类模拟器/DEV-ONLY 两条标记 `SAFETY_RECHECK_REQUIRED`，不得按关键词删除。
- 工具命令：`python3 tools/i18n/triage_legacy.py --check`（只读重算，CSV 漂移/不变量失败非零退出）与
  `--summary`（状态计数 + `PENDING_REVIEW`/`INLINE_LITERAL`/B 明细）；工具默认写入登记表。
- 迁移完成判据：CHK-01..09 全通过、零硬编码、旧字典无构建引用、术语符合 CB 术语表。

## 6. 测试与设备限制

- Host（Node）：`entry/src/test/host/I18n.test.mjs`，28 条；覆盖 auto 解析、fallback、插值、复数、通知、回滚、
  Preferences 失败、reload、dispose、bundle codec、键构造、错误映射、权威 catalog 派生、动态 code 渲染、
  生产资源 parity、检查器夹具/退出码。全仓 host 总量见 `entry/src/test/README.md` 与当前 TAP 证据。
- Hypium 编译套件：`entry/src/test/i18n/I18nHost.test.ets`（已注册 `List.test.ets`）。
- 设备骨架：`entry/src/ohosTest/ets/test/i18n/I18nDevice.test.ets`（已注册 ohosTest `List.test.ets`）；
  `BLOCKED_ON_DEVICE_RUNNER`，无设备/签名，由 host 套件导入进入 ArkTS 编译图；不得把它写成 PASS。
- 运行时 `$r` 与 `t()` 的同步重渲染、en-US 20–40% 文本膨胀、截图抽查由 T-17/T-18 + 设备测试执行。
