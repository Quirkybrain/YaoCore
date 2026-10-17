# i18n 资源、I18nService 与检查器（T-10）

- **Producer**: agent:implementation-engineer
- **Task**: T-10 / `wp-031-i18n`
- **Contract**: DES-B §7；`artifacts/20-architecture/i18n-resource-design.md`（I18N-DESIGN-001）；CB §4.4；PROJECT-CONSTRAINTS §5；`docs/internationalization.md`
- **状态**: 产品代码/资源/host 逻辑测试/检查器完成；组件 `UNVERIFIED`（待独立评审与 CQG-T10）。设备侧执行 `BLOCKED`。

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
└── rawfile/i18n/{zh-CN,en-US}.json # 动态/参数化/错误/状态标签（189 个逻辑键）
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
| rawfile 逻辑键 | 189 | 189（190 个物理键，`device.count` + `_one`/`_other`） | CHK-01/03/04 PASS |
| `string.json` | 25 | 25 | CHK-02 PASS |
| `errors.*` | 93 | 93 | 含 `errors.scene.run_in_progress` 与 `errors.app.scene_run_in_progress` 兼容键 |
| `provisioning.error.*` | 17 | 17 | 配网错误族 |
| `stateSource.*` / `ac.mode.*` | 6 / 8 | 6 / 8 | 5 值溯源 + unknown；7 值模式 + unknown |

所有 `AppError` code（65 个产品代码）经 `ErrorCatalog.resolve()` 的 i18nKey 均能在生产 rawfile 中找到（host 测试
`T10_C14_productionResources_parityAndEveryCatalogKeyExists`）。

## 4. 检查器（CHK-01..CHK-09）

```bash
python3 entry/src/test/i18n/check_i18n.py \
  --root . \
  --report entry/src/test/evidence/t10-i18n-report.json \
  --allowlist entry/src/test/i18n/allowlist.json \
  --strict-ui
```

- 退出码：`0` 全部阻断项通过；`1` 存在阻断失败；`2` 输入/工具错误。
- CHK-01 rawfile 键集（含复数展开）；CHK-02 string.json 键集；CHK-03 插值参数；CHK-04 空值/占位/括号；
  CHK-05 未使用键（告警）；CHK-06 未定义键；CHK-07 硬编码（UI 阻断、非 UI 告警 + allowlist）；
  CHK-08 多语言代码分叉；CHK-09 locale 目录结构。
- `allowlist.json` 支持三类条目：`entries`（文件+行，用于 CHK-07）、`keyEntries`（精确键）、
  `keyPrefixes`（为 T-17/T-18 预留的 UI/动态键前缀）。每项必须写理由。
- 正负夹具：`entry/src/test/i18n/fixtures/good|bad/`；host 测试断言 good=0、bad=1 且 CHK-01/02/03/04/06/07/08/09 阻断。

> **路径偏差**：DES-B §7.4.4 指定 `tools/i18n/check_i18n.py`，但 T-10 的写范围不含 `tools/`；检查器/allowlist/
> 迁移表落在 `entry/src/test/i18n/`。T-17/T-18 或后续工具任务可迁移到 `tools/i18n/`，命令与报告 schema 不变。

## 5. 迁移边界

- 旧 `input/existing/original_app/service/I18nService.ets` 的 615 条“中文即键”字典**不进入产品代码**；
  逐条登记表见 `legacy-migration.csv`（615 行），边界与批次见 `migration-boundary.md`。
- T-10 只落服务/错误/通用文案（10 条旧文案已重键）；其余 606 条按 A 类待 T-17/T-18 逐页面/组件迁入，
  3 条品牌名 D 类排除，6 条旧版/模拟器启发式 C 类待复核。
- 迁移完成判据：CHK-01..09 全通过、零硬编码、旧字典无构建引用、术语符合 CB 术语表。

## 6. 测试与设备限制

- Host（Node）：`entry/src/test/host/I18n.test.mjs`，24 条；覆盖 auto 解析、fallback、插值、复数、通知、回滚、
  Preferences 失败、reload、dispose、bundle codec、键构造、错误映射、生产资源 parity、检查器夹具。
- Hypium 编译套件：`entry/src/test/i18n/I18nHost.test.ets`（已注册 `List.test.ets`）。
- 设备骨架：`entry/src/ohosTest/ets/test/i18n/I18nDevice.test.ets`；`BLOCKED_ON_DEVICE_RUNNER`，无设备/签名，
  由 host 套件导入进入 ArkTS 编译图；不得把它写成 PASS。
- 运行时 `$r` 与 `t()` 的同步重渲染、en-US 20–40% 文本膨胀、截图抽查由 T-17/T-18 + 设备测试执行。
