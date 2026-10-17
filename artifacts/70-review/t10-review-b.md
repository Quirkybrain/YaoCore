# T-10 i18n 修复独立复审报告（F-01..F-08 关闭确认 / CQG-T10）

- **Artifact ID**: REVIEW-T10-I18N-B
- **Producer**: agent:quality-reviewer
- **Type**: Independent Code Review（C-14 / T-10 复审）
- **Status**: **PASS（代码级，条件式）** — 上轮 F-01..F-08 全部关闭；R2-01/R2-02 为非阻断跟踪项；设备/运行时证据保持 `BLOCKED`。
- **Date**: 2026-10-17
- **Task**: `wp-034-review-t10b`（被审修复 `wp-033-fix-t10`；原始实现 `wp-031-i18n`）
- **Reviewed Revision**: `1bf318338c2078aa7d99bf2a484925d7bbf36cdc`（`fix(i18n): 修复 T-10 评审发现`）
- **Fix Diff Base**: `a932cfc99192aa38acdbaf2d5fa4cd11b472bfe6`（上轮评审报告提交）；原始实现 revision `ce780d724aa8ea6261cbbf43b8399e321de456ea`
- **Branch**: `task/wp-031-i18n`；父集成分支 `feat/yaocore-app`
- **Workflow**: STANDARD / GATED_AUTO
- **独立性声明**: 被审修复的 Producer 为 `agent:implementation-engineer`；本复审由未参与 T-10 实现、上轮评审及 `wp-033-fix-t10` 的 `agent:quality-reviewer` 执行。被审代码、资源、测试、证据、修复报告与上游 Artifact 均未修改；评审探针仅通过 Node stdin 与 `/tmp` 执行；本报告的唯一仓库写入为 `artifacts/70-review/t10-review-b.md`。

---

## 1. 复审范围、revision 与输入完整性

### 1.1 范围内

| 类别 | 路径/内容 |
|---|---|
| 修复 diff | `a932cfc..1bf3183`，25 个文件（3 个产品代码文件、2 个 rawfile、11 个测试/README/设备测试/检查器/夹具/迁移表文件、7 个修复证据、修复报告与实现报告） |
| 产品代码 | `entry/src/main/ets/service/i18n/{I18nService,I18nKeys,I18nModels}.ets` |
| 资源 | `entry/src/main/resources/rawfile/i18n/{zh-CN,en-US}.json`；生产 `string.json` 本次未改动 |
| 测试 | `entry/src/test/host/I18n.test.mjs`、`entry/src/test/i18n/{check_i18n.py,allowlist.json,legacy-migration.csv,fixtures/**,README.md,migration-boundary.md}`、`entry/src/ohosTest/ets/test/{List.test.ets,i18n/I18nDevice.test.ets,README.md}`、`entry/src/test/README.md` |
| 证据 | `entry/src/test/evidence/t10-fix-*.log` / `.tap` / `.json` |
| 修复报告 | `artifacts/50-implementation/t10-fix-report.md`（pinned input） |
| 上游契约 | 上轮评审 `t10-review.md`、`t10-i18n.md`、DES-B §7/§23.4、I18N-DESIGN、CB、PROJECT-CONSTRAINTS §5、TEST-001 |

- `1bf3183` 的改动全部落在 `wp-033-fix-t10` handoff 的 `writes`/`commit_paths` 内；未发现构建产物、HAP、证书、密钥或 `.hvigor` 内容入库。
- 修复对产品 rawfile 只做**新增**：zh/en 各新增 23 个键，删除 0、既有值变更 0；生产 `string.json` 未改动（本次 `string.json` 的变更仅为 bad fixture）。

### 1.2 排除/未覆盖

- 真实设备/模拟器：`RawfileI18nLoader`、`OhosLocaleApplier`、`ApplicationContext.setLanguage`、Preferences 设备适配、运行时 `$r`/`t()` 同步重渲染仍无 target/签名，保持 `BLOCKED`。
- Hypium 实际执行：`hvigorw test` 的 Linux Previewer 限制未改变；本复审只以 ohosTest HAP 编译作为附加证据。
- T-17/T-18 的 596 条 UI 文案迁移、Settings 语言入口、`$r` 迁移：不在本次修复范围；本报告只确认检查器基线与计数口径。
- T-11..T-16 的未来组件、C-28 组合根/EntryAbility 的 I18nService 装配：不在本次复审范围。
- 未重新逐行评审初始实现全部 8 个 i18n 文件；上轮已评审的服务 API/fallback/插值/复数/持久化/通知语义作为基线，本次重点复核修复 diff 与回归影响。

### 1.3 输入与快照

- `state/handoffs/wp-034-review-t10b.json` 的 8 个 pinned input 经 `swe_guard check` 校验，sha256 全部匹配。
- 复审快照：`refs/swe/snapshots/20261017T114720Z-wp-034-review-t10b-fd383e5f`，覆盖评审目标、`artifacts/50-implementation/t10-fix-report.md`、上轮评审与本报告占位。
- 评审前后 `HEAD=1bf3183`，`git status --short` 为 clean；构建/测试产物被 ignore 规则覆盖。

---

## 2. 独立复验结果

### 2.1 规定命令

| 命令 | 本次结果 | 说明 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS：275 tests / 275 pass / 0 fail / 0 skip / exit 0** | 独立复跑；TAP `1..275`、`# fail 0`；T10_C14 共 28 条。 |
| `python3 entry/src/test/i18n/check_i18n.py --root . --report /tmp/t10b-i18n-report.json --allowlist entry/src/test/i18n/allowlist.json --strict-ui` | **PASS：CHK-01..09 PASS，blockingFailures=0，warnings=2，missingKeys=0，hardcoded=2，exit 0** | 报告写入 `/tmp`，不覆写仓库证据；2 条告警均为 `pages/Index.ets` 的既有短英文占位（T-17/T-18）。 |
| `codelinter -c code-linter.json5 -p default .` | **PASS：No defects found in your code，exit 0** | 覆盖产品源码；`src/test/**`、`src/ohosTest/**` 按 `code-linter.json5` 忽略。 |
| `hvigorw clean assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，35 tasks（34 executed, 1 up-to-date），exit 0** | `Will skip sign 'hos_hap'`（未配置签名）；不得写成设备 PASS。 |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon`（附加） | **PASS：BUILD SUCCESSFUL，35 tasks（34 executed, 1 up-to-date），exit 0** | 验证 `List.test.ets` 注册 `i18nDeviceTest()` 后设备测试 HAP 可编译；未执行。 |
| HAP 内容抽查 | **PASS** | `entry-default-unsigned.hap` 含 `resources/rawfile/i18n/{zh-CN,en-US}.json`，并含修复后的 `device_disabled` 文案。 |
| `git status --short`（全部复验后） | **clean** | 未产生未声明仓库改动。 |

### 2.2 独立探针（生产 rawfile + 真实服务）

使用与 host harness 相同的 Node ESM loader，在 stdin 中加载生产 rawfile 与 `I18nService`；未落盘、未修改仓库：

```text
# 23 个新增键，en-US / zh-CN 双 locale
raw keys returned = 0（23/23 均渲染为实际文案，非 key 文本）
getMissingKeys() = 0（en-US、zh-CN）
errors.app.device_disabled  => "This device is disabled and cannot be controlled." / "该设备已停用，无法控制。"
errors.app.asset_unavailable => "Local secure storage is unavailable." / "本机安全存储不可用。"

# 5 个当前可达动态 code
DEVICE_DISABLED      -> errors.app.device_disabled
DEVICE_UNASSIGNED    -> errors.app.device_unassigned
ASSET_UNAVAILABLE    -> errors.app.asset_unavailable
ASSET_ACCESS_DENIED  -> errors.app.asset_access_denied
ASSET_IO_FAILED      -> errors.app.asset_io_failed
# ErrorI18nMapper.appKey 与 I18nKeys.appError 一致；t() 不返回原始 key。

# 特殊 code 委托（I18nKeys.provisioningError/cloudError == ErrorCatalog）
PROVISIONING_SECRET_DRAFT_EXPIRED   -> provisioning.error.credential_missing
PROVISIONING_WIFI_AUTH_ERROR        -> provisioning.error.auth_error
PROVISIONING_WIFI_NETWORK_NOT_FOUND -> provisioning.error.network_not_found
CLOUD_COMPLETION_TIMEOUT            -> cloud.command.accepted_not_confirmed
CLOUD_COMPLETION_UNSUPPORTED        -> cloud.completion.unsupported
CLOUD_INVENTORY_UNSUPPORTED         -> cloud.completion.unsupported

# F-08：en-US current 失败 + zh-CN base 成功
initialize => loaded=false, locale=zh-CN, getLocale=zh-CN, applied=["zh-CN"],
              t('errors.gateway.success')="成功",
              warn=["I18N_RESOURCE_LOAD_FAILED"]
```

### 2.3 证据一致性与回归

- `t10-fix-host-node-tests.tap`：275/275、0 fail；本次复跑 TAP 名称与计数一致。
- 与初版 271 条 TAP 名称对比：270 条原样保留；1 条被拆分重命名（`T10_C14_productionResources_parityAndEveryCatalogKeyExists` → `T10_C14_productionResources_parity`）；新增 5 个名称（其中 4 条为新增用例，1 条为拆分后的 parity 用例）；**无旧用例被删除**。
- `t10-fix-i18n-checker.log`、`t10-fix-i18n-report.json`：CHK-01..09 PASS、summary `blockingFailures=0 warnings=2 missingKeys=0 hardcoded=2`；本次 `/tmp` 报告同构。
- `t10-fix-codelinter.log`、`t10-fix-clean-assemble.log`、`t10-fix-ohosTest-compile.log`：与本次独立复跑一致。
- 证据 revision：`t10-fix-*` 对应 `wp-033-fix-t10`；初版 `t10-*` 保留为历史 revision，未混用。
- 检查器夹具独立复验：`fixtures/good` exit 0；`fixtures/bad` exit 1，CHK-01/02/03/04/06/07/08/09 FAIL、CHK-05 仅 PASS（warning-only）；CHK-04 命中 `bad_placeholder`/`bad_brace`；malformed allowlist exit 2。

### 2.4 键统计与 parity

| 项 | zh-CN | en-US |
|---|---:|---:|
| rawfile 逻辑键 | 212 | 212 |
| rawfile 物理键 | 212 | 213（`device.count_one/_other`） |
| `errors.*` | 110 | 110 |
| `errors.app.*` | 83 | 83 |
| `errors.cloud.*` | 13 | 13 |
| `provisioning.error.*` | 23 | 23 |
| `string.json` | 25 | 25 |

- 双向差集为空；en-US 资源无 CJK 字符、无空值，zh/en 参数集合一致；无跨存储重复键。
- 权威表覆盖：DES-A §3.2.3 96 行（95 个具体 code + `HTTP_<status>` 模板）+ DES-B §23.4 36 行 = 131 个具体 code（132 行）；全部在 zh/en 存在。
- 当前可达错误面：69 个静态 `AppErrors.*('CODE')` + 5 个动态 code = **74** 个；全部有 zh/en 键。

### 2.5 迁移登记表

- CSV 615 条：A 606（`ACCEPTED` 10 + `PENDING_REVIEW` 596）、C 6、D 3；owner T-17=521、T-18=75、T-10=10、LEGACY-001=9。
- 前 8 个基础列（旧中文/旧英文/分类/目标存储/目标键/审查结论/负责人/批次）与父提交逐行一致；`备注` 列仅在 13 行追加 B/C 说明；10 条 `ACCEPTED` 目标键均存在于对应存储。
- `重译审查`：`B_REWRITE_REQUIRED`=11、`B_PENDING`=585、`B_REVIEWED_ACCEPTED`=10、`NOT_APPLICABLE`=9；B 为 A 类英文子审查。
- `复核标记`：`SAFETY_RECHECK_REQUIRED`=2（模拟器/DEV-ONLY 文案）、`RECHECK_REQUIRED`=4；6 条 C 类均需复核。

---

## 3. F-01..F-08 关闭状态

| ID | 上轮严重度 | 状态 | 关闭证据 |
|---|---|---|---|
| **F-01** | High / 阻断 | **CLOSED** | 23 个缺失键 zh/en 全部落地；catalog 测试从 DES-A/DES-B 权威表派生；5 个动态 code 显式登记并双语渲染；探针 23/23 非 key、0 raw key。 |
| **F-02** | Medium | **CLOSED** | `provisioningError`/`cloudError` 委托 `ErrorCatalog`；`stripPrefix` 删除；特殊 code 与 HTTP `{status}` 用例通过。 |
| **F-03** | Medium | **CLOSED（设备执行 BLOCKED）** | 设备测试改用 `errors.gateway.success`；`i18nDeviceTest()` 注册进 ohosTest `List.test.ets`；README 更新；ohosTest HAP 编译 PASS。 |
| **F-04** | Low | **CLOSED** | CHK-04 覆盖 `string.json` 占位/括号；CHK-07 短英文 UI 检测（2 条告警）；allowlist 非空字段/理由校验；bad 夹具与 exit 2 用例。 |
| **F-05** | Low | **CLOSED** | pending 更正为 596；CSV 新增 `重译审查`/`复核标记`；B=11/585/10、C 安全复核=2；报告/README 同步；摘要表断行修复。 |
| **F-06** | Low | **CLOSED** | 正式例外 **T10-EX-01** 记录（handoff 写范围收窄），指定迁移 owner/条件；本报告 CQG 章节记录。 |
| **F-07** | Low | **CLOSED** | `initialize` 调用 `warnBaseFailure`；新增 `warnCurrentFailure`（仅 locale/fallback）；base/current 失败用例断言日志。 |
| **F-08** | Medium | **CLOSED** | current 失败 + base 成功时 effective locale=zh-CN、只 apply zh-CN、`I18nLoadResult.locale`=zh-CN、`loaded=false`；en-fail/zh-ok 用例与生产探针均通过。 |

### 3.1 F-01 详证

- `entry/src/main/resources/rawfile/i18n/{zh-CN,en-US}.json`：23 键全部存在，双 locale 语义完整；只增不删、既有值不变。
- `entry/src/test/host/I18n.test.mjs:471` `T10_C14_authoritativeCatalog_everyDeclaredCodeHasBothLocaleKeys`：直接解析 `des-001a-foundation-transport.md` §3.2.3 与 `des-001b-domain-presentation.md` §23.4，断言 96/36 行、`ErrorCatalog.resolve` 与权威键逐项一致、键在 zh/en 存在；`SCENE_RUN_IN_PROGRESS` 契约键与兼容键双断言；静态源码扫描 69 个 `AppErrors.*('CODE')` 均在权威表。
- `entry/src/test/host/I18n.test.mjs:516` `T10_C14_reachableDynamicErrorCodes_renderBothLocales`：5 个动态 code 在 en/zh 均不返回原始 key；`ErrorI18nMapper.appKey`/`I18nKeys.appError` 一致。
- 动态路径审计：`DeviceCommandRunner.reject`（DEVICE_DISABLED/UNASSIGNED 等）、`AssetStoreSecretStore.mapError`（ASSET_*）、`ProtocolErrors`/`DiscoverMapper` 的变量 code 均由内部字面量调用点约束；未发现未登记的当前可达 code。未来新增变量路径仍需加入显式清单（残余风险）。

### 3.2 F-02 详证

- `I18nKeys.ets:54-61` 两个方法均为 `return ErrorCatalog.resolve(code).i18nKey;`；`I18nKeys` 内已无 `stripPrefix`/前缀拼接映射。
- `T10_C14_keyBuilders` 断言 3 个 provisioning 特殊 code、3 个 cloud 特殊 code；`T10_C14_errorMapper` 断言 `HTTP_503` key=`errors.app.http_error`、参数 `{status=503}`，并断言 5 个动态 code 的 mapper/key 一致。
- 独立探针：6 个特殊 code 的 `provisioningError`/`cloudError`/`appError` 输出与 `ErrorCatalog` 完全一致。

### 3.3 F-03 详证

- `I18nDevice.test.ets:56,60,65` 使用 rawfile 键 `errors.gateway.success`（en `Success` / zh `成功`），不再使用 `common_*`（后者属 `string.json` 的 `$r` 键）。
- `List.test.ets:12,21` 已 import 并调用 `i18nDeviceTest()`；`entry/src/ohosTest/ets/test/README.md` 已更新目录、注册说明与 T-10 状态。
- ohosTest HAP 编译 PASS；无设备/签名，执行仍 `BLOCKED_ON_DEVICE_RUNNER`，未写成 PASS。

### 3.4 F-04 详证

- `check_i18n.py:386-393` 对 `string.json` 执行空值、`TODO`/`??`、未闭合 `{}` 检查；bad fixture 新增 `bad_placeholder`/`bad_brace`，host 用例断言 CHK-04 命中。
- `check_i18n.py:477-490` 新增短英文 UI 检测（1-3 个首字母大写词，排除 CamelCase/`.id(`）；生产树报告 `pages/Index.ets:19 Hello World`、`:32 Welcome` 2 条 warning；CHK-07 无阻断。
- `check_i18n.py:189-220` 校验 `entries` 的 file/正行号/理由、`keyEntries` 的 key/理由、`keyPrefixes` 的前缀/理由；非法 allowlist exit 2；夹具与缺失输入用例通过。
- 已知局限保留：CHK-05 的 0 告警依赖 15 个 `keyPrefixes` 与动态前缀，不等于“无未使用键”；T-17/T-18 接入后应逐步删除按域前缀。

### 3.5 F-05 详证

- CSV 615 条、A 606（10 已落地 + 596 pending）、C 6、D 3；与上轮评审的独立统计一致。
- `重译审查` 11 条 `B_REWRITE_REQUIRED`（`档案` → `file(s)`/`machine`）均有备注；`复核标记` 2 条模拟器安全文案为 `SAFETY_RECHECK_REQUIRED`，备注指向 `errors.app.dev_simulator_rejected`/`GATEWAY_PROFILE_BLOCKED`。
- `t10-i18n.md`/`migration-boundary.md`/README 的 606/596 口径已统一；摘要表 33/35 行断行已修复。
- **R2-01（Low）**：`t10-fix-report.md:258` 仍写“3 条 B_REWRITE_REQUIRED”，与 CSV/§5.1 的 11 条不一致；属报告笔误，不影响 CSV 与迁移工作量，但应在 CQG 记录/合并前更正。

### 3.6 F-06 详证

- `t10-fix-report.md` §5.2、`t10-i18n.md` 与 i18n README 均登记 **T10-EX-01**；`migration-boundary.md` 也说明同一路径偏差（handoff 写范围收窄）。契约路径为 `tools/i18n/*`、`reports/i18n/*`，实际落在 `entry/src/test/i18n/` 与 `entry/src/test/evidence/`；原因是 `wp-031-i18n` handoff 写范围收窄，不是 delivery-plan 缺少路径。
- 例外关闭条件：后续工具任务/T-19 迁移文件，命令、报告 schema、CSV 列语义不变；不影响 CHK 语义。

### 3.7 F-07 详证

- `I18nService.ets:104-105` 在 `initialize` 中调用 `warnBaseFailure`/`warnCurrentFailure`；`:510-527` 仅在 base 缺失或 current 缺失时记录 code 与 locale/fallback，不含翻译内容、用户数据或密钥。
- `T10_C14_baseBundleFailure...` 与 `T10_C14_currentBundleFailure...` 均断言 `logger.warnMessages` 含 `I18N_RESOURCE_LOAD_FAILED`。

### 3.8 F-08 详证

- `I18nService.ets:97-107`：`effectiveLocale = current 已加载 ? requested : ZH_CN`；`effectiveCurrent = current ?? base`；`applyPlatform(effectiveLocale)`；`I18nLoadResult.locale` 使用 effective locale。
- en-US current 失败 + zh-CN base 成功：`loaded=false`、`getLocale()=zh-CN`、`applied=["zh-CN"]`、`t()` 返回中文、`warn` 含 `I18N_RESOURCE_LOAD_FAILED`（独立生产探针）。
- both-fail：回退 zh-CN、不加载 bundle、不 apply 失败 locale；用例断言 `applied=["zh-CN"]`。

---

## 4. 新发现

| ID | 严重度 | 位置 | 证据/影响 | 建议 |
|---|---|---|---|---|
| **R2-01** | **Low（文档）** | `artifacts/50-implementation/t10-fix-report.md:258` | R-02 写“3 条 B_REWRITE_REQUIRED”，实际 CSV/§5.1/README/migration-boundary 均为 **11**；若按修复报告的残余风险表分配 T-17/T-18 工作，会低估 8 条重译。 | 将 3 改为 11；仅文档更正，无需重跑代码/测试；在 CQG 记录或合并前完成。 |
| **R2-02** | **Low（API 语义观察，非当前缺陷）** | `entry/src/main/ets/service/i18n/I18nService.ets` `reload()` | 生产探针：initialize 因 en-US 失败回退 zh-CN 后，再次 `reload()` 失败返回 `I18nLoadResult.locale=en-US`、`loaded=false`，而 `getLocale()=zh-CN`、`t()` 仍中文。合同未规定失败时 `locale` 字段语义，当前也无调用方使用 `reload().locale`，故不构成本轮阻断。 | T-17/T-18 接线前明确：失败时返回 requested locale（并在文档写清）或 effective/old locale；补一条 reload 失败用例，避免调用方误用。 |

- 未发现新的代码、资源、安全、性能或分层阻断缺陷。
- 未来风险：`staticProductErrorCodes()` 只能扫描字面量 code；新增变量 code 路径必须加入 `DYNAMIC_REACHABLE_CODES`/权威表，否则仍可能逃逸。

---

## 5. CQG-T10 对照

| 检查项 | 结果 | 证据/说明 |
|---|---|---|
| build | **PASS** | 主 HAP `clean assembleHap` BUILD SUCCESSFUL、35 tasks、exit 0；ohosTest HAP 编译 PASS；未签名。 |
| lint | **PASS（产品源码）** | codelinter No defects、exit 0；`src/test/**`/`src/ohosTest/**` 按配置忽略，设备测试仅由 ohosTest 编译覆盖。 |
| host | **PASS** | 275/275、0 fail/skip；28 条 T10_C14；本次独立复跑。 |
| checker/CT | **PASS（含已知局限）** | CHK-01..09 PASS；0 阻断、2 条短英文 UI warning、missingKeys=0；good/bad/malformed exit 0/1/2。 |
| key parity | **PASS** | rawfile 212/212 逻辑键（en 213 物理键）；string.json 25/25；无跨存储重复。 |
| 错误键覆盖 | **PASS** | 131 个权威具体 code 全部有 zh/en 键；74 个当前可达 code（69 静态 + 5 动态）全部覆盖；5 个动态 code 双语渲染非 key。 |
| 无硬编码 UI 文案 | **PARTIAL（基线成立）** | CHK-07 0 阻断；`pages/Index.ets` 仍有 `Hello World`/`Welcome` 2 条既有短英文占位 warning。按 T-10 DoD“UI 硬编码扫描基线形成”满足；按 test-plan 字面“无硬编码 UI 文案”尚未完全满足，owner=T-17/T-18。 |
| runtime switch | **BLOCKED** | 无设备/模拟器；`OhosLocaleApplier`/`$r` 重渲染未执行。 |
| device | **BLOCKED** | 无 `hdc` target/签名/镜像；`I18nDevice` 已注册且编译，未执行。 |
| security | **PASS（逻辑/资源边界）** | 无 secret/token/用户数据进入日志或资源；`warnCurrentFailure` 只记 locale/fallback；纯 JSON、无网络加载。设备侧平台 API 仍 `BLOCKED`。 |
| migration | **PASS（代码级，迁移待 T-17/T-18）** | 615 条完整性；596 pending 口径统一；B=11/585/10；C 6 条复核、2 条安全复核；CSV 前 8 列逐行未改写，备注仅追加 B/C 说明。 |
| 路径例外 | **RECORDED** | T10-EX-01：handoff 收窄导致 `entry/src/test/i18n/`、`entry/src/test/evidence/`；关闭条件=迁移 `tools/i18n`/`reports/i18n`，命令/schema 不变。 |
| independent review | **PASS** | 本报告；上轮 F-01..F-08 全部关闭；无阻断新发现。 |
| **总体** | **PASS（代码级，条件式）** | 建议 CQG-T10 以代码级 PASS 记录；C-14 可置 `STABLE（代码级）`，设备/运行时与用户验收不在本报告授权范围。 |

---

## 6. 裁决与条件

**Verdict: PASS（代码级，条件式）**

理由：

1. 上轮阻断项 F-01 已实质关闭：23 个缺失键 zh/en 全部落地，catalog 测试从 DES-A/DES-B 权威表派生，5 个当前可达动态 code 有显式登记与双语渲染证据；独立探针确认 `t()` 不再返回原始 key。
2. F-02/F-03/F-07/F-08 的代码级缺陷均已修复并有针对性用例；F-04/F-05/F-06 的检查器、迁移口径与路径例外均已落地并记录。
3. 五项规定命令与附加 ohosTest 编译全部 PASS；275/275 host、0 阻断检查器、0 codelinter 缺陷、构建成功；无旧 host 用例被删除，回归风险低。
4. 仍有 2 条非阻断跟踪项（R2-01 文档笔误、R2-02 reload 失败字段语义）和既有的设备/UI 迁移边界，均不影响 C-14 代码级质量结论。

**CQG-T10 建议记录的条件/残余：**

1. **设备/运行时**：`RawfileI18nLoader`、`OhosLocaleApplier`、`ApplicationContext.setLanguage`、Preferences 设备适配、`$r`/`t()` 同步重渲染 → `BLOCKED`，由设备 owner/T-17/T-18/T-19 执行；不得把编译 PASS 写成设备 PASS。
2. **UI 迁移**：T-17/T-18 仍需处理 A 类 596 条 `PENDING_REVIEW`，其中 11 条 `B_REWRITE_REQUIRED`；2 条 C 类安全文案需 `SAFETY_RECHECK_REQUIRED` 人工复核；`Index.ets` 2 条短英文占位迁移后 CHK-07 升级为阻断。
3. **路径例外 T10-EX-01**：接受为正式例外；后续工具任务/T-19 迁移到 `tools/i18n/*`、`reports/i18n/*`，命令/schema/CSV 列语义不变。
4. **R2-01**：修复报告 R-02 的“3 条”更正为 11 条；文档级，CQG 记录前完成。
5. **R2-02**：T-17/T-18 接线 `reload()` 前明确失败时 `I18nLoadResult.locale` 语义并补测。
6. C-14 可置 `STABLE（代码级）`，但本报告**不授予** Stage Gate、用户验收或设备验收；CQG 最终记录由 Orchestrator 依据本意见与证据作出。

---

## 7. 残余风险与跟踪

| ID | 风险/跟踪项 | owner/动作 |
|---|---|---|
| R-01 | 设备侧 rawfile/applier/setLanguage/Preferences/$r 未执行；C-14 设备行为 `UNVERIFIED` | 设备 owner/T-17/T-18/T-19 |
| R-02 | T-17/T-18 迁移 596 条；11 条 B 重译；2 条 C 安全复核 | T-17/T-18 |
| R-03 | CHK-07 2 条短英文占位为 warning；UI 迁移后升级阻断 | T-17/T-18 |
| R-04 | CHK-05 的 0 告警依赖 15 个 keyPrefixes/动态前缀，不能证明无未使用键 | T-17/T-18 逐步删除按域前缀 |
| R-05 | 检查器/迁移表路径偏离 `tools/i18n`/`reports/i18n`（T10-EX-01） | 后续工具任务/T-19 |
| R-06 | `hvigorw test` Previewer 不可执行；仅 ohosTest HAP 编译证据 | 测试环境 owner |
| R-07 | `SCENE_RUN_IN_PROGRESS` 双键长期保留会复制文案 | T-17/T-18 统一经 mapper 后删除兼容键 |
| R-08 | `I18nKeys.appError('HTTP_*')` 只返回 key，`{status}` 由 `ErrorI18nMapper.appKey` 添加 | UI/VM 统一用 mapper；补文档/测试 |
| R-09 | en-US 20–40% 文本膨胀/截断未做 UI 验证 | T-17/T-18 UI 评审/设备截图 |
| R-10 | `I18nService` 未接入 C-28 组合根/EntryAbility | T-17/T-18/C-28 装配时验证 |
| R-11 | 未来变量 code 路径可能逃逸静态扫描 | 新增动态 code 必须登记 `DYNAMIC_REACHABLE_CODES`/权威表 |
| R2-01 | 修复报告 R-02 的 B_REWRITE_REQUIRED 数量笔误（3 vs 11） | implementation-engineer 文档更正 |
| R2-02 | `reload()` 失败时 `I18nLoadResult.locale` 为 requested locale，而服务仍服务旧/fallback locale | T-17/T-18 接线前明确语义并补测 |

---

## 8. 独立性与结论声明

本报告由 `agent:quality-reviewer` 独立完成，未参与 T-10 实现、上轮评审或 `wp-033-fix-t10`；未修改被审产品代码、资源、测试、证据、修复报告或上游 Artifact。评审探针通过 Node stdin 与 `/tmp` 执行，未写入仓库；本报告的唯一仓库写入为 `artifacts/70-review/t10-review-b.md`。裁决仅针对 revision `1bf3183` 与 §1.1 范围，不覆盖 T-11..T-18 的实现、设备/模拟器执行或真实 UI 验收；不授予 Stage Gate 或用户验收。

**Final Verdict: PASS（代码级，条件式）**

### 8.1 本次复验命令摘要

```text
entry/src/test/run-host-tests.sh
  -> 1..275 / # pass 275 / # fail 0 / # skipped 0 / exit 0

python3 entry/src/test/i18n/check_i18n.py --root . \
  --report /tmp/t10b-i18n-report.json \
  --allowlist entry/src/test/i18n/allowlist.json --strict-ui
  -> CHK-01..09 PASS / blockingFailures=0 warnings=2 missingKeys=0 hardcoded=2 / exit 0

codelinter -c code-linter.json5 -p default .
  -> No defects found in your code. / exit 0

hvigorw clean assembleHap --no-daemon
  -> BUILD SUCCESSFUL in 5 s 642 ms
  -> 35 tasks in total: 34 executed, 1 up-to-date / exit 0
  -> WARN: Will skip sign 'hos_hap'（未配置签名）

hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon
  -> BUILD SUCCESSFUL in 7 s 185 ms / 35 tasks / exit 0

git status --short
  -> clean
```

### 8.2 关键探针摘要

- 23 个新增键在 en-US/zh-CN 均渲染为实际文案；`getMissingKeys()`=0。
- 5 个动态 code 的 `ErrorCatalog`/`I18nKeys`/`ErrorI18nMapper` 一致，`t()` 不返回 key 文本。
- `I18nKeys.provisioningError/cloudError` 与 `ErrorCatalog` 对 6 个特殊 code 输出完全一致。
- F-08：en-US current 失败 + zh-CN base 成功 → `loaded=false`、`locale/getLocale=zh-CN`、`applied=["zh-CN"]`、`t()` 中文。
- 迁移表 615 条、596 pending、B_REWRITE_REQUIRED=11、SAFETY_RECHECK=2；前 8 列逐行未变，备注仅追加。
