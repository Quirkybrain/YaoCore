# T-10 i18n 资源包与 I18nService 独立评审报告（C-14）

- **Artifact ID**: REVIEW-T10-I18N
- **Producer**: agent:quality-reviewer
- **Type**: Independent Code Review（C-14 / T-10）
- **Status**: **CHANGES_REQUIRED（代码级，阻断项见 F-01）** — 服务主体、资源 parity、271 条 host 测试、检查器、构建与 lint 通过；但当前产品可达的 5 个 `AppError` code 无资源键，host "全 catalog" 断言不完整，设备骨架存在必失败断言且未注册。本报告不授予 CQG-T10、Stage Gate 或用户验收。
- **Date**: 2026-10-17
- **Task**: `wp-032-review-t10`（被审实现任务 `wp-031-i18n`）
- **Reviewed Revision**: `ce780d724aa8ea6261cbbf43b8399e321de456ea`（`feat(i18n): 实现双语资源包与国际化服务`）
- **Base Revision**: `0a6d5bc5b24a4b56200f3df56f7ee7195aee6d8b`（`task/wp-031-i18n` 的父提交）
- **Branch**: `task/wp-031-i18n`；父集成分支 `feat/yaocore-app`
- **Workflow**: STANDARD / GATED_AUTO
- **独立性声明**: 被审实现的 Producer 为 `agent:implementation-engineer`；本评审由未参与 T-10 实现或 `wp-031-i18n` 的 `agent:quality-reviewer` 执行。被审代码、资源、测试、证据与上游 Artifact 均未修改；本报告的唯一仓库写入为 `artifacts/70-review/t10-review.md`。评审探针通过 Node stdin 与 `/tmp` 执行，未修改仓库文件。

---

## 1. 评审范围、revision 与输入完整性

### 1.1 范围内

| 类别 | 路径/内容 |
|---|---|
| 产品代码 | `entry/src/main/ets/service/i18n/`（8 文件：Models/Ports/Service/Keys/ErrorI18nMapper/BundleCodec/RawfileI18nLoader/OhosLocaleApplier） |
| 资源 | `entry/src/main/resources/rawfile/i18n/{zh-CN,en-US}.json`、`entry/src/main/resources/{base,en_US}/element/string.json` |
| 测试 | `entry/src/test/host/I18n.test.mjs`（24 条）、`entry/src/test/i18n/`（fakes、Hypium smoke、检查器、allowlist、迁移表、fixtures）、`entry/src/ohosTest/ets/test/i18n/I18nDevice.test.ets` |
| 证据 | `entry/src/test/evidence/t10-*.log/tap/json` |
| 实现报告 | `artifacts/50-implementation/t10-i18n.md` |
| 上游契约 | DES-B §7（C-14）、DES-A §3.2.3/§24、`i18n-resource-design.md`、CB §4.1/§4.4/§6.1/§6.3、PROJECT-CONSTRAINTS §5、`docs/internationalization.md`、TEST-001/test-plan §6 |

`wp-031-i18n` 的 commit 路径全部落在其 handoff `writes`/`commit_paths` 内；未发现构建产物、HAP、证书、密钥或 `.hvigor` 内容入库。

### 1.2 排除/未覆盖

- 真实设备/模拟器：`RawfileI18nLoader`、`OhosLocaleApplier`、`ApplicationContext.setLanguage`、Preferences 设备适配、运行时 `$r` 与 `t()` 同步重渲染；无 `hdc` target、无签名、无模拟器，保持 `BLOCKED`。
- Hypium 实际执行：`hvigorw test` 仅有 `UnitTestArkTS` 编译证据；Linux Previewer 不可执行，保持 `COMPILED_ONLY / BLOCKED`。
- UI 文案迁移、Settings 语言入口、`$r` 使用的 606/596 条旧文案：T-17/T-18 范围；本评审只检查资源基线、键空间与检查器。
- T-11..T-16 的未来组件（Gateway/BLE/Auth/Invite/Cloud/UI VM）；本评审只检查其已声明错误键是否需要由 T-10 预置。
- C-28 组合根/EntryAbility 的 I18nService 装配；T-10 产品代码未接线，本报告不把“服务可编译”写成“运行时已接入”。

### 1.3 输入与快照

- `state/handoffs/wp-032-review-t10.json` 的 6 个 pinned input 由 `swe_guard` 校验通过（sha256 全部匹配）。
- 评审目标快照：`refs/swe/snapshots/20261017T112537Z-wp-032-review-t10-60e74da5`，覆盖 `entry/src/main/ets/service/i18n/`、`entry/src/main/resources/`、`entry/src/test/`、`entry/src/ohosTest/ets/test/i18n/`、`artifacts/50-implementation/t10-i18n.md`、`artifacts/70-review/t10-review.md`。
- 评审前后 `git status --short` 均为 clean；构建/测试产物被 ignore 规则覆盖。`HEAD` 与 handoff `base_commit` 一致。

---

## 2. 独立复验结果

| 命令 | 本次结果 | 说明 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS：271 tests / 271 pass / 0 fail / exit 0** | 独立复跑；与 `evidence/t10-host-node-tests.tap` 的 271/271 一致；无 skip/todo。 |
| `python3 entry/src/test/i18n/check_i18n.py --root . --report /tmp/t10-i18n-report.json --allowlist entry/src/test/i18n/allowlist.json --strict-ui` | **PASS：CHK-01..09 全 PASS，blockingFailures=0 warnings=0 missingKeys=0 hardcoded=0，exit 0** | 报告写入 `/tmp`，不覆写仓库证据；与 `evidence/t10-i18n-checker.log` 一致。 |
| `codelinter -c code-linter.json5 -p default .` | **PASS：No defects found in your code，exit 0** | 本次独立复跑；仅覆盖产品源码（`src/test/**`、`src/ohosTest/**` 被 `code-linter.json5` 忽略）。 |
| `hvigorw clean assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，35 tasks（34 executed, 1 up-to-date），exit 0** | 与 `evidence/t10-clean-assemble.log` 一致；`Will skip sign 'hos_hap'`（未配置签名），不得写成设备 PASS。 |
| `unzip -l entry/build/default/outputs/default/entry-default-unsigned.hap` | **PASS（包内容抽查）** | HAP 含 `resources/rawfile/i18n/{en-US,zh-CN}.json`；证明资源进入构建产物。 |
| `git status --short`（全部复验后） | **clean** | 未产生未声明仓库改动。 |

### 2.1 证据一致性

- `t10-host-node-tests.tap`：271/271；本次复跑同为 271/271、0 fail。TAP 名称集合与报告 §6 的“新增 T10_C14 24 条”一致；未发现旧用例删除/改名。
- `t10-i18n-checker.log`：CHK-01..09 PASS、summary 全 0；本次复跑结果一致。
- `t10-i18n-report.json`：`schemaVersion/locales/checks/summary/allowlist` 字段齐全；本次 `/tmp` 报告同构，summary 全 0。
- `t10-codelinter.log`：`No defects found`；本次复跑一致。
- `t10-clean-assemble.log`：BUILD SUCCESSFUL、35 tasks；本次复跑一致。
- `t10-hvigor-test-compile.log`：`UnitTestArkTS` 成功，随后 Linux Previewer 等待/timeout；本次未重复执行，报告与日志均未把它写成 Hypium 执行 PASS。
- `t10-ohpm-install.log`：`install completed`；本次未重复执行（不改变四条规定命令的结论）。

### 2.2 只读探针（关键证据）

使用与 host harness 相同的 Node ESM loader，在 stdin 中加载生产 rawfile 与 `I18nService`，直接查询 `ErrorCatalog.resolve(code).i18nKey` 再调用 `t()`；未落盘、未修改仓库：

```text
DEVICE_DISABLED        -> errors.app.device_disabled        => "errors.app.device_disabled"
DEVICE_UNASSIGNED      -> errors.app.device_unassigned      => "errors.app.device_unassigned"
ASSET_UNAVAILABLE      -> errors.app.asset_unavailable      => "errors.app.asset_unavailable"
ASSET_ACCESS_DENIED    -> errors.app.asset_access_denied    => "errors.app.asset_access_denied"
ASSET_IO_FAILED        -> errors.app.asset_io_failed        => "errors.app.asset_io_failed"
PROVISIONING_SECRET_DRAFT_EXPIRED -> provisioning.error.credential_missing => "Provisioning credentials are missing."
CLOUD_COMPLETION_TIMEOUT          -> cloud.command.accepted_not_confirmed  => "The cloud accepted the command, but the device has not confirmed execution."
PROVISIONING_WIFI_AUTH_ERROR      -> provisioning.error.auth_error          => "Wi-Fi authentication failed. Check the password."
PROVISIONING_WIFI_NETWORK_NOT_FOUND -> provisioning.error.network_not_found => "The requested Wi-Fi network was not found."
getMissingKeys() = 0
```

结论：前 5 个当前可达错误码在两种 locale 都缺失，`t()` 按合同 fail-soft 返回 key 文本；`getMissingKeys()` 不包含“两种 bundle 都缺失”的 key（合同语义如此），因此该缺陷不会被 missing 诊断或当前 host 用例发现。详见 F-01。

---

## 3. 契约符合性评估

### 3.1 服务 API、locale 状态与查找语义

| 契约 | 结论 | 证据/说明 |
|---|---|---|
| DES-B §7.1.1 值对象 | **PASS** | `I18nModels.ets` 的 `SupportedLocale`/`LocaleMode`/`I18nParams`/`I18nKey`/`I18nResourceBundle`/`LocaleChangedEvent`/`I18nLoadResult` 与契约一致；`I18nParams.count` 仅用于英文复数。 |
| §7.1.2 端口与平台隔离 | **PASS** | `I18nService` 仅依赖 `I18nResourceLoaderPort`/`LocaleApplierPort`/`PreferencesStore`/`LoggerPort`；无 `@ohos.*` import；平台细节仅在两个 adapter。 |
| §7.1.3 initialize | **PASS（含 F-07 低风险）** | 读 Preferences → 解析 mode/locale → 加载 current+base → apply；Preferences 读失败 fail-soft；load 失败返回 `I18nLoadResult.error`；apply 失败只记 warning，不阻断 rawfile 文案。 |
| §7.1.3 setLocaleMode | **PASS** | 非法 mode → `I18N_LOCALE_UNSUPPORTED`；写 Preferences → 解析/加载 → apply → notify；写失败透传 `STORAGE_PREFERENCES_ERROR`；load 失败恢复旧 mode/preference；apply 失败仍切换 rawfile 并 `platformApplied=false`。 |
| §7.1.3 reload | **PASS** | AUTO 重新解析系统 locale；失败保持旧 bundle；成功 apply + notify。 |
| §7.1.3 t/tKey/has | **PASS** | `t()` 同步、永不抛错、非空 key 不返回空白；五级 fallback；缺参数保留 `{name}` 并 warning；`tKey` 使用 `I18nKey.params`；`has` 覆盖基键与复数变体。 |
| §7.1.3 observers/dispose | **PASS** | 注册不立即触发；set/reload 成功才通知；listener 抛错隔离；unsubscribe 幂等；dispose 清空与 listener 移除。 |
| §7.1.3 getMissingKeys | **PASS（合同语义）** | 只记录“当前 locale 缺失、回退 zh-CN”的 key；不回退（两 bundle 都缺）不进入诊断；该语义导致 F-01 的缺口只能靠 catalog 枚举发现。 |
| §7.3.1 locale 解析/持久化 | **PASS** | `zh*→zh-CN`、`en*→en-US`、其他/空→zh-CN；非法 pref→auto+warning；auto 不持久化具体 locale；手动 mode 精确匹配。 |
| §7.3.3 fallback/复数/插值 | **PASS** | current[key+suffix]→current[key]→base[key+suffix]→base[key]→key；仅 en-US 使用 `_one/_other`；中文只用基键；缺变体回退基键；参数单次替换、不递归、不 HTML/正则。 |
| §7.2 错误语义 | **PARTIAL** | 服务自身错误映射与 fail-soft 正确；但产品 `AppError` 键覆盖不完整（F-01），`I18nKeys` 的特殊 code 映射有缺失（F-02）。 |

### 3.2 双存储边界、parity 与资源质量

| 检查 | 结论 | 证据 |
|---|---|---|
| rawfile 布局 | **PASS** | `resources/rawfile/i18n/{zh-CN,en-US}.json`；HAP 抽查包含两文件。 |
| rawfile key parity | **PASS** | zh 189 物理=189 逻辑；en 190 物理=189 逻辑（`device.count_one/_other`）；归一化后双向差集为空；CHK-01/03/04 PASS。 |
| `string.json` parity | **PASS** | base/en_US 各 25 键，键集完全一致；CHK-02 PASS。 |
| 一个 key 一个存储 | **PASS** | `common_*`/`settings_language_*`/元数据仅在 `string.json`；错误/状态/复数/插值仅在 rawfile；未发现跨存储重复键。 |
| 元数据/模板键保留 | **PASS** | `module_desc`/`EntryAbility_desc`/`EntryAbility_label` 保留并由 `module.json5` 引用；`AppScope` 保持 `app_name` 唯一来源，避免构建冲突。 |
| 参数集合/命名 | **PASS** | `{count}`/`{status}`/`{time}`/`{value}`/`{mode}`/`{code}` 跨 locale 一致；参数名符合 `[A-Za-z][A-Za-z0-9_]*`；CHK-03 PASS。 |
| 空值/占位/括号 | **PASS（rawfile）** | 无空值、`TODO`/`??`、未闭合括号；CHK-04 PASS；`string.json` 侧覆盖不足见 F-04。 |
| 复数语义 | **PASS** | zh `{count} 个设备`；en `_one`/`_other` 成对；0/1/2 选择正确；host 用例覆盖。 |
| 插值语义 | **PASS** | 命中、缺参数保留占位符、多参数、参数值含 `{name}` 不二次展开；host 用例覆盖。 |
| 语言纯度 | **PASS** | en-US 资源 CJK 字符数 0；zh-CN 为中文；未发现空/乱码。 |
| 术语一致性 | **PASS** | 网关/设备/房间/家庭/邀请/成员/场景/配网/云端/令牌与 CB 术语一致；ACK/KEK 作为技术词保留；无 “AP/热点/路由” 混用。 |
| 强制安全文案 | **PASS** | `gateway.security.hmac_only`、`invite.security.weak_mode_warning`、`invite.security.guest_scope_not_crypto`、`door.alert.unconfirmed` 均存在且语义明确。 |
| DES-B §7.4.2 最小基线 | **PARTIAL（跟踪项）** | 域覆盖大体齐全，但 `home.tab.title`、`ac.temperature.target`、`ac.brand.*`、`provisioning.step.*`、`provisioning.cancel`、`a11y.*` 尚未落地；当前无代码引用，故 CHK-05/06 不阻断，T-17/T-18 必须补。 |

- **夹具有效性**：`fixtures/good` exit 0；`fixtures/bad` exit 1，CHK-01/02/03/04/06/07/08/09 均 FAIL、CHK-05 仅 warning（host 用例断言）；与 §4 报告一致。该夹具证明检查器的阻断路径可执行，但不覆盖 F-01 的动态 code 缺键与 F-04 的 `string.json` 值校验。

### 3.3 错误键覆盖（本评审的关键发现）

按 DES-A §3.2.3（96 个 AppError code）与 DES-B §23.4（新增错误码，明确“必须补 i18n 键”）逐项对照生产 rawfile：

| 来源 | 缺失键数 | 当前是否可达 | 代表 code |
|---|---:|---|---|
| DES-A §3.2.3 | 18 | 部分（3 个 Asset code 当前可达） | `ASSET_UNAVAILABLE`、`ASSET_ACCESS_DENIED`、`ASSET_IO_FAILED`、`AUTH_*`、`MANUAL_ADDRESS_*`、`TLS_VERIFIER_UNAVAILABLE`、`INVITE_KEY_MISSING`、`PROVISIONING_PERMISSION_DENIED` 等 |
| DES-B §23.4 | 5 | 2 个 Device code 当前可达 | `DEVICE_DISABLED`、`DEVICE_UNASSIGNED`、`CLOUD_NOT_CONFIGURED`、`CLOUD_TOKEN_MISSING`、`CLOUD_DEVICE_NOT_FOUND` |
| **合计** | **23** | **至少 5 个当前可达** | 见 F-01 |

当前可达的 5 个缺失键（均在 zh/en 两文件同时缺失）：

| code | `ErrorCatalog` key | 抛错位置 |
|---|---|---|
| `DEVICE_DISABLED` | `errors.app.device_disabled` | `entry/src/main/ets/service/device/DeviceCommandRunner.ets:66`（经 `:115` `AppErrors.of(code)`） |
| `DEVICE_UNASSIGNED` | `errors.app.device_unassigned` | `DeviceCommandRunner.ets:69`（经 `:115`） |
| `ASSET_UNAVAILABLE` | `errors.app.asset_unavailable` | `entry/src/main/ets/service/storage/AssetStoreSecretStore.ets:194-206` |
| `ASSET_ACCESS_DENIED` | `errors.app.asset_access_denied` | `AssetStoreSecretStore.ets:199-201` |
| `ASSET_IO_FAILED` | `errors.app.asset_io_failed` | `AssetStoreSecretStore.ets:194/202-205` |

这 5 个 code 都属于当前已实现组件（T-08/T-09）的产品错误面；`ErrorI18nMapper.appKey` 会返回上述缺失 key，UI 将显示原始 key 文本（探针已证）。这直接违反 I18N-05 的“无 missing/平滑降级”、DES-A §24.3-4 的“所有 `AppError.code` 必须有对应键”以及 DES-B §23.4 的“必须补 i18n 键”。

### 3.4 安全、健壮性与平台假设

| 项 | 结论 | 说明 |
|---|---|---|
| `t()` fail-soft | **PASS** | 未初始化/缺 key/参数缺失均不抛错；缺 key 返回 key 文本，缺参数保留 `{name}`；host 用例覆盖。 |
| 加载失败/回滚 | **PASS** | base 缺失仍可用 current；current 缺失回退 base；setLocaleMode 加载失败恢复旧 locale/pref；apply 失败 `platformApplied=false`；host 用例覆盖。 |
| Preferences 语义 | **PASS** | 初始化读失败 fail-soft；setLocaleMode 写失败透明抛 `STORAGE_PREFERENCES_ERROR`；T10-R11 与实现/测试一致。 |
| 秘密/用户数据 | **PASS** | 日志仅 key/locale/mode/param 名；错误 details 仅 locale 等；未发现 secret/token/用户数据进入日志或资源。 |
| 资源解析安全 | **PASS** | 纯 JSON、2MB/深度 8/字符串 32KB 限制；重复/空值/非法键/非法占位符拒绝；无网络加载；无 HTML 注入路径。 |
| 语言分叉 | **PASS（当前树）** | 单一服务、单一代码库；CHK-08 0 阻断；未发现 `_en`/`_zh` 分叉文件。 |
| 平台适配假设 | **PARTIAL（已诚实登记）** | `getSystemLocaleInstance()`、`ApplicationContext.setLanguage('zh-CN'/'en-US')` 仅编译验证；T10-R05/R06 与 §7 已标 `COMPILED_ONLY`/设备验证；未发现被写成设备 PASS。 |
| 性能 | **PASS（低风险）** | `t()` 为 Map O(1) 查找+线性插值；加载时一次性排序/建图；未见明显热点；未做基准，属残余风险。 |

### 3.5 迁移边界

- 登记表完整：`legacy-migration.csv` 615 行（表头+615），源文件 SHA-256 `dc8e5e4d…2c44`、615 个 case 与源文件一致；无重复旧中文；10 条 `ACCEPTED` 的目标键均存在于对应存储。
- 分类统计：A 606（含 10 条已落地 + 596 条 `PENDING_REVIEW`）、C 6、D 3；owner 分布 T-17=521、T-18=75、T-10=10、LEGACY-001=9，合计 615。
- **报告口径错误**：`t10-i18n.md`/`migration-boundary.md`/`entry/src/test/i18n/README.md` 多处把“606 条待 T-17/T-18”与“其余 606 条 PENDING_REVIEW”混用；实际 pending 为 **596**，606 是 A 类总数（含已落地 10 条）。见 F-05。
- **B 类缺失**：I18N-DESIGN §5 的 A/B/C/D 四分类在 CSV 中只出现 A/C/D；`审查结论` 只有 `PENDING_REVIEW`/`ACCEPTED`/`DEPRECATED`/`EXCLUDED`，没有 B（重译）的逐条登记。报告/边界文档声称 A/B/C/D 逐条登记，与 CSV 不一致。见 F-05。
- **启发式风险实例**：CSV 第 137/138 行把“检测到开发协议模拟器，拒绝其控制响应”“正式版禁止将其绑定为真实网关”归为 C 废弃；这两条对应当前 DEV-ONLY/SC-11 安全行为与已有 `errors.app.dev_simulator_rejected`/`GATEWAY_PROFILE_BLOCKED` 语义，不能仅凭“模拟器”关键词自动归档。T-17/T-18 必须复核。见 F-05。

---

## 4. Findings

| ID | 严重度 | 位置 | 违反契约/约束 | 建议 |
|---|---|---|---|---|
| **F-01** | **阻断 / High** | `entry/src/main/ets/service/device/DeviceCommandRunner.ets:66,69,115`；`entry/src/main/ets/service/storage/AssetStoreSecretStore.ets:194-206`；`resources/rawfile/i18n/{zh-CN,en-US}.json`；`entry/src/test/host/I18n.test.mjs:358-387`；`artifacts/50-implementation/t10-i18n.md:28,114,147,287`；`entry/src/test/README.md:103`；`entry/src/test/i18n/README.md:50` | DES-A §3.2.3/§24.3-4；DES-B §23.4；I18N-05；DES-B §7.2 | 至少补齐 5 个当前可达键；建议一次性补齐 DES-A/§23.4 全部 23 个缺失键；host 测试改为从权威表派生并新增 5 个动态 code 用例；重跑规定命令后复审。 |
| **F-02** | **中 / Medium** | `entry/src/main/ets/service/i18n/I18nKeys.ets:53-59`；`entry/src/test/host/I18n.test.mjs:323-356` | DES-B §7.1.4（I18nKeys 只是便捷包装，不得复制映射表）；DES-A §3.2.3/§24.2；I18N-05 | `provisioningError`/`cloudError` 委托 `ErrorCatalog.resolve(code).i18nKey`；为特殊 code 与 `ErrorI18nMapper.appKey` 的 HTTP `{status}` 增加用例。 |
| **F-03** | **中 / Medium** | `entry/src/ohosTest/ets/test/i18n/I18nDevice.test.ets:55,59-61,65-67`；`entry/src/ohosTest/ets/test/List.test.ets:10-19`；`entry/src/test/i18n/I18nHost.test.ets:26-30`；`entry/src/ohosTest/ets/test/README.md` | DES-B §7.3.2（`common_*` 静态 UI 在 string.json，而非 rawfile）；DES-B §7.5/设备测试；TEST-001 | 设备测试改用现有 rawfile 键（如 `errors.gateway.success`/`device.state.online`）；把 `i18nDeviceTest()` 注册进 ohosTest `List.test.ets` 并更新 README；继续诚实标 `BLOCKED`。 |
| **F-04** | **低 / Low** | `entry/src/test/i18n/check_i18n.py:344-360,375-405,420-463`；`entry/src/test/i18n/allowlist.json:4-65`；`entry/src/main/ets/pages/Index.ets:19,32` | DES-B §7.4.4 CHK-04/05/07；I18N-02；I18N-DESIGN §6.3 | CHK-04 覆盖 `string.json` 的 `TODO`/`??`/括号；为 allowlist 条目校验非空前缀/理由；不要把 CHK-05 的 0 告警当作“无未使用键”证明；T-17/T-18 替换 Index 占位文案并用更严格的 UI 扫描/人工抽查复核。 |
| **F-05** | **低 / Low** | `artifacts/50-implementation/t10-i18n.md:30,33,35,110,196-203,288`；`entry/src/test/i18n/migration-boundary.md:14,37`；`entry/src/test/i18n/README.md:78`；`entry/src/test/i18n/legacy-migration.csv:137-138` | I18N-DESIGN §5；DES-B §7.4.3；报告证据一致性 | 把“606 待迁”改为“596 pending（A 606 含 10 已落地）”；补 B 类逐条登记或明确 B 为 A 的子审查并记录；复核 C 类中的 DEV-ONLY/模拟器安全文案；修复 summary 表 33/35 行的 `||` 断行。 |
| **F-06** | **低 / 流程** | `artifacts/50-implementation/t10-i18n.md:182-183,260`；`entry/src/test/i18n/README.md:71-72`；`entry/src/test/i18n/check_i18n.py` | DES-B §7.4.4（`tools/i18n/check_i18n.py`、`reports/i18n/*`）；delivery-plan T-10 写范围（含 `tools/i18n/check_i18n.py`） | 该偏差由 `wp-031-i18n` handoff 收窄写范围造成，报告应明确“handoff 收窄”而非泛称“T-10 写范围不含 tools/”；CQG 记录正式例外，后续工具任务迁移到契约路径（命令/schema 不变）。 |
| **F-07** | **低 / Low** | `entry/src/main/ets/service/i18n/I18nService.ets:92-99,502-506` | DES-B §7.3.1（基准缺失→记录错误） | `initialize` 也调用 `warnBaseFailure(loaded)`，或在报告中明确“仅通过 `I18nLoadResult.error` 返回、不写日志”；补对应测试。 |
| **F-08** | **中 / Medium** | `entry/src/main/ets/service/i18n/I18nService.ets:92-99,274-298`；`entry/src/test/host/I18n.test.mjs:471-490` | DES-B §7.1.3 initialize / §7.3.1；I18N-DESIGN §4（两类存储显示语言始终一致）；I18N-05 | current bundle 加载失败而 base 成功时，不要保持 `currentLocale=en` 并 apply en；回退 zh-CN（或保持旧 locale）并返回 `loaded=false`，补 current-only 失败用例。 |

### 4.1 F-01 详情：当前可达 AppError 缺键与测试盲区

**事实链**：

1. `DeviceCommandRunner.reject(command, startedAt, 'DEVICE_DISABLED')` / `'DEVICE_UNASSIGNED'` 在命令预检阶段返回 `AppErrors.of(code)`；这是 DES-B §6/§23.4 明列的当前行为。
2. `AssetStoreSecretStore.mapError` 将 Asset 平台码映射为 `ASSET_UNAVAILABLE`/`ASSET_ACCESS_DENIED`/`ASSET_IO_FAILED`/`ASSET_NOT_FOUND`；前 3 个没有资源键。
3. `ErrorCatalog.resolve` 分别为它们生成 `errors.app.device_disabled`、`errors.app.device_unassigned`、`errors.app.asset_unavailable`、`errors.app.asset_access_denied`、`errors.app.asset_io_failed`；两种 rawfile 均不存在这些 key。
4. `I18nService.t()` 按合同 fail-soft 返回 key 文本；探针已证（§2.2）。UI 若经 `ErrorI18nMapper.appKey`/`error.i18nKey` 展示，会出现原始 key。
5. `T10_C14_productionResources_parityAndEveryCatalogKeyExists` 使用手写 `CATALOG_CODES`（100 项），未包含上述 5 个 code；因此测试通过不能证明“所有产品 code 有键”。报告 §0/§2/§3 的“65 个产品 code 全部有键”只覆盖了静态 `AppErrors.*('CODE')` 调用（65 个），漏掉变量 code 路径（`reject`/`mapError`）；静态 65 + 动态 5 = 当前产品错误面至少 **70** 个 code 未被完整断言。
6. 按 DES-A §3.2.3 与 DES-B §23.4 的权威表，合计 23 个缺失键；其中 5 个当前可达，18 个属于 T-11..T-15 的未来组件（`AUTH_*`、`MANUAL_ADDRESS_*`、`TLS_VERIFIER_UNAVAILABLE`、`INVITE_KEY_MISSING`、`PROVISIONING_PERMISSION_DENIED` 等）。

**缺失键清单（按权威表）**：

```text
# DES-A §3.2.3（18）
errors.app.tls_verifier_unavailable
errors.app.manual_address_rejected
errors.app.manual_address_not_bound
errors.app.asset_unavailable
errors.app.asset_access_denied
errors.app.asset_io_failed
errors.app.auth_profile_exists
errors.app.auth_password_invalid
errors.app.auth_session_invalid
errors.app.auth_session_expired
errors.app.auth_kdf_failed
errors.app.invite_key_missing
provisioning.error.permission_denied
provisioning.error.multiple_devices
provisioning.error.gatt_incomplete
provisioning.error.mtu_too_small
provisioning.error.capability_unsupported
provisioning.error.binding_identity_mismatch

# DES-B §23.4（5）
errors.app.device_disabled
errors.app.device_unassigned
errors.cloud.not_configured
errors.cloud.token_missing
errors.cloud.device_not_found
```

**建议**：

1. **阻断修复的最小集合**：在 zh/en rawfile 同时加入上述 5 个当前可达键（建议文案：`errors.app.device_disabled` “该设备已停用，无法控制。”/“This device is disabled and cannot be controlled.”；`device_unassigned` “该设备尚未分配房间。”/“This device is not assigned to a room.”；`asset_unavailable` “本机安全存储不可用。”/“Local secure storage is unavailable.”；`asset_access_denied` “无权限访问本机安全存储。”/“Access to local secure storage was denied.”；`asset_io_failed` “本机安全存储读写失败。”/“Local secure storage read/write failed.”）。
2. **建议一次性补齐**剩余 18 个 DES-A/§23.4 键，避免 T-11..T-15 反复改资源；若决定延后，必须在报告中逐项列出 owner（T-11/T-12/T-13/T-14）与“不得声称全 catalog 覆盖”的说明。
3. **测试改为权威派生**：从 DES-A §3.2.3 + DES-B §23.4 维护一份单一 catalog（或从产品代码/`ErrorCatalog` 可枚举常量派生），断言每个 code 的 `ErrorCatalog.resolve().i18nKey` 在 zh/en 都存在；显式加入 `DeviceCommandRunner.reject` 与 `AssetStoreSecretStore.mapError` 的 5 个动态 code。测试名可改为 `...EveryDeclaredAppErrorCodeExists`，避免“EveryCatalogKeyExists”夸大。
4. **补充 `ErrorI18nMapper.appKey` 与 `I18nKeys.appError` 的渲染测试**（至少覆盖 HTTP `{status}` 与 5 个当前 code），防止“key 存在但参数/映射路径错误”。

**关闭标准**：5 个当前键在 zh/en 存在；23 个缺失键全部落地或逐项登记延迟；host 271+ 用例、checker、codelinter、assembleHap 重跑 PASS；复审确认 `t()` 不再返回这 5 个 key 文本。

### 4.2 F-02 详情：`I18nKeys.provisioningError`/`cloudError` 复制映射

| 输入 code | `I18nKeys` 输出 | 资源是否存在 | `ErrorCatalog` 输出（权威/安全路径） |
|---|---|---|---|
| `PROVISIONING_SECRET_DRAFT_EXPIRED` | `provisioning.error.secret_draft_expired` | **否** | `provisioning.error.credential_missing` |
| `PROVISIONING_WIFI_AUTH_ERROR` | `provisioning.error.wifi_auth_error` | **否** | `provisioning.error.auth_error` |
| `PROVISIONING_WIFI_NETWORK_NOT_FOUND` | `provisioning.error.wifi_network_not_found` | **否** | `provisioning.error.network_not_found` |
| `CLOUD_COMPLETION_TIMEOUT` | `errors.cloud.completion_timeout` | **否** | `cloud.command.accepted_not_confirmed` |
| `CLOUD_COMPLETION_UNSUPPORTED` | `errors.cloud.completion_unsupported` | **否** | `cloud.completion.unsupported` |
| `CLOUD_INVENTORY_UNSUPPORTED` | `errors.cloud.inventory_unsupported` | 是 | `cloud.completion.unsupported`（两个键不一致） |

- `I18nKeys.appError` 已按要求委托 `ErrorCatalog`；但 `provisioningError`/`cloudError` 用 `stripPrefix + toLowerCase` 重新实现映射，违反 DES-B §7.1.4“I18nKeys 只是便捷包装，不得复制映射表”。`PROVISIONING_SECRET_DRAFT_EXPIRED` 是当前 T-08 产品代码会抛出的 code；一旦 UI 按 `I18nKeys` 使用，就会显示原始 key。`ErrorI18nMapper.provisioningKey` 目前走 `error.i18nKey` 是安全的，但不能依赖所有调用方都走 mapper。
- **建议**：`provisioningError(code)` / `cloudError(code)` 直接 `return ErrorCatalog.resolve(code).i18nKey;`；未知 code 走 `provisioning.error.unknown`/`errors.cloud.*` 的统一策略（若需要）。在 host 测试中枚举上述特殊 code 与 `HTTP_<status>` 的 `{status}` 参数。

### 4.3 F-03 详情：设备骨架会失败且未注册

- `I18nDevice.test.ets` 第 55、59-61、65-67 行使用 `service.t('common.ok')`。生产 rawfile **没有** `common.ok`；`common_*` 是 `string.json` 的静态 UI 键，按 DES-B §7.3.2 不应由 `t()` 读取。设备首次执行时第 55 行 `assertFalse()` 即失败（返回 `"common.ok"`）。
- 该文件由 `I18nHost.test.ets:26-30` import 但仅 `void i18nDeviceTest;`，不会调用；`entry/src/ohosTest/ets/test/List.test.ets` 只注册 baseline/foundation/security/storage，**没有** i18n。即使设备可用，`onDeviceTest` 也不会执行该套件。
- `entry/src/ohosTest/ets/test/README.md` 仍写“本目录设备套件已全部注册（T-06/T-07/T-08）”，未更新 T-10；报告 §7 的“已通过 UnitTestArkTS 编译图”只证明编译，不证明注册/执行。
- **建议**：把测试键改为 `errors.gateway.success`（“成功”/“Success”）或 `device.state.online`；注册 `i18nDeviceTest()`；更新 README；在设备执行前保持 `BLOCKED`，不得写成 PASS。

### 4.4 F-04 详情：检查器覆盖与 allowlist 合理性

- **CHK-04**：`check_i18n.py:344-360` 对 rawfile 检查空值/`TODO`/`??`/括号计数，但对 `string.json` 只检查“非空字符串”。因此 `string.json` 中的 `TODO`、未闭合括号或占位符不会被阻断；CHK-04 的合同文本未限定只查 rawfile。建议把同样的值检查应用到 `string.json`（保留合法 `%s`/`%d` 等按需 allowlist），并补 bad fixture。
- **CHK-05**：`allowlist.json` 的 15 个 `keyPrefixes` 覆盖 `common_`/`settings_language_`/`home.`/`room.`/`family.`/`scene.`/`door.`/`invite.`/`member.`/`device.`/`cloud.`/`gateway.security.`/`ac.mode.`/`stateSource.`/`provisioning.error.`；此外 `ErrorCatalog`/`I18nKeys` 中的 `'errors.app.'`/`'errors.cloud.'` 等前缀字面量会让 CHK-05 把整族键视为“已使用”。因此“0 告警”不等于“无未使用键”；报告 §4 已部分披露前缀豁免，但没有披露动态前缀的抑制效果。作为警告级检查可以接受，但 CQG 不得把 CHK-05=0 当作无未使用键的证明；T-17/T-18 接入后应删除按域前缀豁免并保留精确 `keyEntries`。
- **CHK-07**：UI 目录的英文启发式要求 ≥3 词（合同如此），所以 `pages/Index.ets:19` 的 `'Hello World'`、`:32` 的 `'Welcome'` 不会被命中，但它们仍是用户可见硬编码；T-17/T-18 必须替换。检查器 0 阻断只证明“未命中启发式”，不证明“零硬编码”。建议在 UI 迁移后对 `pages/`/`components/` 做人工抽查，并考虑更严格的短文案规则（或以 `string.json`/`t()` 引用白名单方式）。
- **退出码**：checker 支持 0/1/2，但 host 仅断言 good=0、bad=1；未覆盖 exit 2（缺失文件/非法 JSON）。建议补一条工具错误用例。

### 4.5 F-05 详情：迁移登记口径与分类

- CSV 统计（独立读取）：615 行；A 606（`ACCEPTED` 10 + `PENDING_REVIEW` 596）、C 6、D 3；owner T-17 521、T-18 75、T-10 10、LEGACY-001 9。
- 报告/README 的“其余 606 条 PENDING_REVIEW”与“606 条待 T-17/T-18”应为 **596**；606 是 A 类总数（含 10 条已落地）。这会直接导致 T-17/T-18 工作量与批次统计偏差。
- CSV 没有 B 类（重译）行；`审查结论` 也没有“B/重译”值。若 B 类按设计应由 T-17/T-18 逐条判定，应在登记表中保留 `分类=B` 或增加 `重译决定` 列；否则“逐条 A/B/C/D”声明不成立。
- 启发式 C 类第 137/138 行（模拟器拒绝控制响应/禁止绑定为真实网关）对应当前 DEV-ONLY/SC-11 行为与已有 `errors.app.dev_simulator_rejected`/`GATEWAY_PROFILE_BLOCKED`，不应仅凭“模拟器”关键词归档；T-17/T-18 必须逐条复核，避免丢失安全提示。
- 文档排版：`t10-i18n.md` 摘要表第 33/35 行使用 `||` 把 codelinter/设备行接在上一行，Markdown 渲染为单行；建议恢复为独立行。

### 4.6 F-06 详情：路径偏差的授权依据

- DES-B §7.4.4 与 delivery-plan T-10 写范围都指定 `tools/i18n/check_i18n.py`、`tools/i18n/allowlist.json`、`tools/i18n/legacy_migration.csv`、`reports/i18n/*`；实际落在 `entry/src/test/i18n/` 与 `entry/src/test/evidence/`。
- `wp-031-i18n` handoff 的 `writes` 确实只列 `entry/src/test/`、`entry/src/main/resources/` 等，不含 `tools/`；因此实际偏差是 **handoff 收窄写范围** 造成的，而不是 delivery-plan 原本没有该路径。报告的 T10-R01 说“T-10 写范围不含 tools/”容易让读者误以为计划本身没有该路径，建议改写为“本 handoff 写范围未授权 tools/；delivery-plan/DES-B 的契约路径待后续工具任务迁移”。
- 功能上检查器不进入 ArkTS 构建链，放在 test 目录不改变 CHK 语义；但 CI/评审若按 DES-B 路径查找会找不到。建议 CQG 记录正式例外并指定后续迁移 owner（工具任务或 T-19）。

### 4.7 F-07 详情：initialize 的 base 失败日志

- `I18nService.initialize()` 在 `loadBundles` 返回后只使用 `loaded.error` 构造 `I18nLoadResult`，未调用 `warnBaseFailure`；`setLocaleMode`/`reload` 都调用了 `warnBaseFailure`。
- DES-B §7.3.1 要求“基准缺失 → 仍可 t() 返回 key；记录错误”。`I18nLoadResult.error` 是返回值，但若调用方忽略返回值，服务没有日志。建议在 `initialize` 末尾调用 `warnBaseFailure(loaded)`，或明确记录“仅返回 error，不写日志”的合同解释；补 base 失败日志用例。

### 4.8 F-08 详情：current bundle 加载失败时仍 apply 平台 locale，造成 `$r`/`t()` 语言劈裂

- `loadBundles(locale)` 在 `locale !== zh-CN` 且 loader 失败时返回 `current=undefined, base=zh`；`initialize` 随后仍执行 `this.currentLocale = locale`（en-US）和 `applyPlatform(locale)`（en-US），而 `t()` 只能回退 base zh-CN。独立探针结果：

  ```text
  en-US current bundle fail, zh-CN base ok
  initialize: loaded=false, locale=en-US, applied=["en-US"], t('errors.gateway.success')="成功", getMissingKeys=1
  ```

- 这违反 I18N-DESIGN §4“I18nService 必须在语言切换后立即重载 rawfile 包并通知 UI，使两类存储的显示语言始终一致”，也违反 DES-B §7.1.3 的 initialize 步骤精神（当前 locale 未加载时不应假装已应用）。`setLocaleMode` 对同一路径会回滚/抛错，`reload` 会保持旧 bundle，只有 `initialize` 不一致。
- 影响：en-US rawfile 损坏/缺失时，`$r` 静态 UI 切到英文、`t()` 动态文案仍中文；`I18nLoadResult.loaded=false` 可被调用方忽略。属于低概率但真实的一致性缺陷。
- **建议**：current 加载失败而 base 成功时，把 `currentLocale` 设为 base（zh-CN）并 skip/ignore `applyPlatform(en-US)`，或保持旧 locale/不 apply；`I18nLoadResult` 可增加 `resolvedLocale`（合同外可选）或保证 `locale` 字段与实际查找 locale 一致；补“en fail + zh ok”host 用例（当前只有 base-fail 与 both-fail 用例）。

### 4.9 `SCENE_RUN_IN_PROGRESS` 双键的评估（非阻断）

- 两键 `errors.scene.run_in_progress`（契约键）与 `errors.app.scene_run_in_progress`（兼容 `ErrorCatalog`）均在 rawfile、同一存储；不违反“一个 key 只存在于一个存储”。
- `ErrorCatalog` 仍返回 `errors.app.scene_run_in_progress`；`I18nKeys.appError`/`ErrorI18nMapper.appKey` 返回契约键。T-09 复审已记录该漂移，T-10 以双键桥接是可接受的临时折中，且报告 T10-R02 已记录。
- **残余**：只要其他代码直接使用 `AppError.i18nKey`，双键就仍需保留；T-17/T-18 应统一经 `ErrorI18nMapper`/`I18nKeys`，并明确“何时删除兼容键”的 owner/条件（建议随 `AppError` 映射任务更新，不得无限期保留双份文案）。

---

## 5. CQG-T10 检查项对照

| 检查项 | 结果 | 证据/说明 |
|---|---|---|
| build | **PASS** | `hvigorw clean assembleHap --no-daemon`：BUILD SUCCESSFUL、35 tasks、exit 0；未签名。 |
| lint | **PASS（产品源码）** | `codelinter`：No defects、exit 0；不覆盖 `src/test/**`/`src/ohosTest/**`。 |
| host | **PASS** | `run-host-tests.sh` 271/271、0 fail；本次独立复跑。 |
| contract/CT | **PASS（CHK-01..09）/ PARTIAL（错误键覆盖）** | checker 全 PASS；但 CHK 无法发现动态缺失键，F-01 证明覆盖率不足。 |
| key parity | **PASS** | rawfile 189/189 逻辑键；string.json 25/25；本次独立统计与测试一致。 |
| 无硬编码 UI 文案 | **NOT PROVEN** | CHK-07=0 只代表启发式未命中；`pages/Index.ets` 仍有短占位文案（F-04）；T-17/T-18 必须替换并复扫。 |
| 运行时切换 | **BLOCKED** | 无设备/模拟器；`OhosLocaleApplier`/`$r` 重渲染未执行。 |
| device | **BLOCKED** | 无 `hdc` target/签名/镜像；设备骨架未注册且有必失败断言（F-03）。 |
| security | **PASS（逻辑/资源边界）** | 无 secret 日志、无网络加载、无用户数据；平台 API 仅 adapter。 |
| migration | **PARTIAL** | 615 行完整、10 条落地；606/596 口径、B 类缺失、C 类启发式需修正（F-05）。 |
| review | **本报告** | Verdict CHANGES_REQUIRED；C-14 不得标记 `STABLE`。 |
| **总体** | **CHANGES_REQUIRED** | F-01 阻断；F-02/F-03/F-08 需在设备/UI 前修复；F-04..F-07 可同批或跟踪。 |

---

## 6. 裁决

**Verdict: CHANGES_REQUIRED**

理由：

1. **服务核心与资源主体质量良好**：`I18nService` 的 API、fallback、复数、插值、locale 解析、持久化/回滚/通知语义与 DES-B §7 一致；host 24 条新用例覆盖主要分支，271/271 可复现。
2. **双存储与 parity 成立**：zh 189 逻辑键 / en 190 物理键、string.json 25/25、无跨存储重复、HAP 含 rawfile；CHK-01..09 全 PASS。
3. **但错误键覆盖存在当前产品缺陷**：`DEVICE_DISABLED`、`DEVICE_UNASSIGNED`、`ASSET_UNAVAILABLE`、`ASSET_ACCESS_DENIED`、`ASSET_IO_FAILED` 这 5 个当前可达 code 在两种 locale 均无键，`t()` 返回原始 key；host 的 100 项 `CATALOG_CODES` 漏掉变量 code 路径，因此“65 个产品 code 全部有键”与“EveryCatalogKeyExists”声明不成立。该缺陷直接违反 I18N-05、DES-A §24.3-4、DES-B §23.4，属于阻断。
4. **次级缺陷会影响下游**：`I18nKeys.provisioningError`/`cloudError` 复制映射（F-02）和 `I18nDevice` 的 `common.ok`/未注册（F-03）必须在本组件进入 UI/设备验证前修复；`initialize` current-only 失败的语言劈裂（F-08）也需修复。
5. **文档口径需纠正**：606/596、B 类缺失、C 类启发式（F-05）与路径偏差授权依据（F-06）影响 CQG/T-17/T-18 的可追踪性；F-07 为低风险可观测性改进。

**修复后关闭标准**：

1. F-01：5 个当前键落地（建议 23 个全落地）；host catalog 测试改为权威派生并覆盖动态 code；checker/lint/build/host 重跑 PASS。
2. F-02：`provisioningError`/`cloudError` 委托 `ErrorCatalog`；特殊 code 与 `HTTP_<status>` 参数用例通过。
3. F-03：设备测试使用现有 rawfile 键并注册进 ohosTest `List.test.ets`；设备执行前保持 `BLOCKED`。
4. F-08：current bundle 失败时回退 base/保持旧 locale，不 apply 失败 locale；补“en fail + zh ok”用例。
5. F-04/F-05/F-06/F-07：至少在报告中记录跟踪 owner/关闭条件；若同批修复，重跑 checker/测试并更新证据。
6. 复审确认 C-14 的 `ErrorI18nMapper` 对当前 70 个可达 code 均返回已定义键；在此之前不得标记 `STABLE`，不得把 CQG-T10 写成 PASS。

---

## 7. 残余风险与跟踪项

| ID | 风险/跟踪项 | 建议 owner/动作 |
|---|---|---|
| R-01 | DES-A §3.2.3 剩余 18 个未来 code 无键（`AUTH_*`、`MANUAL_*`、`TLS_VERIFIER_UNAVAILABLE`、`INVITE_KEY_MISSING`、`PROVISIONING_*`） | T-13/T-11/T-12 或 T-10 追加；每个组件落地时必须补 zh/en 并跑 catalog 测试。 |
| R-02 | DES-B §23.4 云键 `errors.cloud.not_configured`/`token_missing`/`device_not_found` 未落地 | T-14/T-15；不得让 CloudService 直接显示 raw key。 |
| R-03 | T-17/T-18 迁移 596 条（非 606）；B 类重译未登记；C 类模拟器安全文案误归档 | T-17/T-18 逐条复核；C 类不得仅按关键词删除；B 类需记录重译决定。 |
| R-04 | 设备侧 `RawfileI18nLoader`/`OhosLocaleApplier`/`ApplicationContext.setLanguage`/`$r` 重渲染未执行 | 设备/模拟器 owner；T-17/T-18 验证；在此之前 C-14 保持 `UNVERIFIED`。 |
| R-05 | `SCENE_RUN_IN_PROGRESS` 双键长期保留会复制文案 | T-17/T-18 统一经 mapper 后，随 `AppError` 映射更新删除兼容键。 |
| R-06 | CHK-05 的 0 告警依赖 15 个 keyPrefixes + 动态前缀；不能证明无未使用键 | T-17/T-18 接入后逐步删除按域前缀，改用精确 `keyEntries`；CQG 记录检查器局限。 |
| R-07 | CHK-04 未覆盖 `string.json` 占位/括号；CHK-07 未命中短英文占位 | 工具任务或 T-19 补强；UI 迁移后人工抽查。 |
| R-08 | 检查器/迁移表/报告路径偏离 DES-B/delivery-plan 的 `tools/i18n`、`reports/i18n` | CQG 记录 handoff 收窄例外；后续工具任务迁移；命令/schema 不变。 |
| R-09 | `initialize` base 失败不写日志；仅返回 `I18nLoadResult.error` | 小修 F-07 或文档明确；补测试。 |
| R-10 | en-US 20–40% 文本膨胀/截断未做 UI 验证 | T-17/T-18 UI 评审；设备/截图检查。 |
| R-11 | `I18nService` 未接入 C-28 组合根/EntryAbility；运行时不会自动初始化 | T-17/T-18/C-28 装配时验证；T-10 不宣称已接入。 |
| R-12 | `I18nKeys.appError('HTTP_*')` 只返回 key，`{status}` 由 `ErrorI18nMapper.appKey` 添加；调用方误用会显示占位符 | 在 UI/VM 中统一使用 `ErrorI18nMapper`；补测试/文档。 |
| R-13 | `initialize` 在 current bundle 失败、base 成功时仍 apply 失败 locale，造成 `$r`/`t()` 语言劈裂 | 修 F-08；补“en fail + zh ok”host/设备用例。 |

---

## 8. 独立性与结论声明

本报告由 `agent:quality-reviewer` 独立完成，未参与 T-10 实现、`wp-031-i18n` 或任何 T-10 修复；未修改被审产品代码、资源、测试、证据、`t10-i18n.md` 或上游 Artifact。评审探针通过 Node stdin 与 `/tmp` 执行，未写入仓库；本报告的唯一仓库写入为 `artifacts/70-review/t10-review.md`。评审裁决仅针对 revision `ce780d7` 与 §1.1 范围，不覆盖 T-11..T-18 的实现、设备/模拟器执行或真实 UI 验收；不授予 CQG-T10 总体通过、Stage Gate 或用户验收。

**Final Verdict: CHANGES_REQUIRED**

### 8.1 本次复验命令摘要

```text
entry/src/test/run-host-tests.sh
  -> 1..271 / # pass 271 / # fail 0 / exit 0

python3 entry/src/test/i18n/check_i18n.py --root . \
  --report /tmp/t10-i18n-report.json \
  --allowlist entry/src/test/i18n/allowlist.json --strict-ui
  -> CHK-01..09 PASS / blockingFailures=0 warnings=0 missingKeys=0 hardcoded=0 / exit 0

codelinter -c code-linter.json5 -p default .
  -> No defects found in your code. / exit 0

hvigorw clean assembleHap --no-daemon
  -> BUILD SUCCESSFUL in 5 s 765 ms
  -> 35 tasks in total: 34 executed, 1 up-to-date / exit 0
  -> WARN: Will skip sign 'hos_hap'（未配置签名）

git status --short
  -> clean
```

### 8.2 关键探针摘要

- 生产 rawfile `t('errors.app.device_disabled' | 'device_unassigned' | 'asset_unavailable' | 'asset_access_denied' | 'asset_io_failed')` 均返回原始 key → F-01。
- `ErrorCatalog.resolve` 对上述 5 个 code 的 key 与资源缺失一致；`getMissingKeys()` 返回 0（两 bundle 都缺，合同不回退）→ F-01 诊断盲区。
- `I18nKeys.provisioningError`/`cloudError` 对 5 个特殊 code 输出缺失键；`ErrorCatalog` 输出存在键 → F-02。
- 生产资源 `errors.app.device_disabled`/`device_unassigned`/`asset_*` 在两个 rawfile 均无定义；`DES-B §23.4` 明确要求 device 两键 → F-01。
