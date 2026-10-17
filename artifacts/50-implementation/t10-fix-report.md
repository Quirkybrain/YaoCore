# T-10 i18n 评审修复报告（C-14 / wp-033-fix-t10）

- **Artifact ID**: IMP-T10-I18N-FIX
- **Producer**: agent:implementation-engineer
- **Type**: Implementation / Verification Evidence（评审修复）
- **Status**: Proposed（F-01..F-08 已处置；待独立复审与 CQG-T10）
- **Date**: 2026-10-17
- **Task**: `wp-033-fix-t10`（task 分支 `task/wp-031-i18n`，父分支 `feat/yaocore-app`，base commit `a932cfc99192aa38acdbaf2d5fa4cd11b472bfe6`）
- **Reviewed Revision**: `ce780d724aa8ea6261cbbf43b8399e321de456ea`
- **Review Input**: `artifacts/70-review/t10-review.md`（CHANGES_REQUIRED；sha256 `5e3cbfc7…`）
- **Upstream Contracts**: DES-A §3.2.3/§24；DES-B §7/§23.4；I18N-DESIGN §4-§6；CB §4.4；PROJECT-CONSTRAINTS §5；TEST-001
- **Component State**: C-14 保持 `UNVERIFIED`；本报告不授予 `STABLE`、CQG-T10 或 Stage Gate。

---

## 0. 摘要

| Finding | 严重度 | 处置 | 关键证据 |
|---|---|---|---|
| F-01 错误键缺口 | High / 阻断 | **Fixed**：23 个缺失键全部落地（zh/en）；host 改为从 DES-A/DES-B 权威表派生并扫描静态 code；5 个动态 code 双语渲染用例 | 212/212 逻辑键；131 个具体 code + 74 个可达 code |
| F-02 `I18nKeys` 复制映射 | Medium | **Fixed**：`provisioningError`/`cloudError` 统一委托 `ErrorCatalog.resolve()`；删除本地前缀映射 | 特殊 code + HTTP `{status}` 用例 |
| F-03 设备测试键/注册 | Medium | **Fixed**：改用 `errors.gateway.success`；`i18nDeviceTest()` 注册进 ohosTest `List.test.ets`；README 更新 | ohosTest HAP 编译 PASS |
| F-04 检查器覆盖 | Low | **Fixed**：CHK-04 覆盖 `string.json` 占位/括号；CHK-07 增加短英文 UI 占位；allowlist 校验非空字段/理由；bad 夹具补强 | CHK-04 命中 `bad_placeholder`/`bad_brace`；2 条 UI 告警 |
| F-05 迁移口径/分类 | Low | **Fixed**：pending 更正为 **596**；CSV 增加 B 子审查与 C 安全复核标记；报告摘要表断行修复 | CSV 615 条；B_REWRITE_REQUIRED=11；SAFETY_RECHECK=2 |
| F-06 路径偏差依据 | Low | **Fixed**：登记正式例外 **T10-EX-01**（handoff 收窄写范围），指定后续迁移 owner/条件 | 本报告 §5 |
| F-07 initialize 基准失败日志 | Low | **Fixed**：`initialize` 调用 `warnBaseFailure` 并新增 current 失败诊断（仅 locale 字段） | host 日志断言 |
| F-08 current-only 失败语言劈裂 | Medium | **Fixed**：current bundle 失败时回退 zh-CN base、`I18nLoadResult.locale` 反映实际加载 locale、不 apply 失败 locale | en-fail/zh-ok 用例 |

**结论**：五项规定命令全部 PASS；host **275/275**；检查器 **0 阻断**（2 条短英文 UI 迁移告警）。
设备/模拟器执行与运行时 `$r` 重渲染仍为 `BLOCKED`；C-14 不得标记 `STABLE`。

---

## 1. F-01：AppError 键覆盖与权威派生测试

### 1.1 落地键（23 个，zh-CN/en-US 同步）

| # | code | `ErrorCatalog` key | 当前可达 |
|---:|---|---|---|
| 1 | `TLS_VERIFIER_UNAVAILABLE` | `errors.app.tls_verifier_unavailable` | 否（T-12） |
| 2 | `MANUAL_ADDRESS_REJECTED` | `errors.app.manual_address_rejected` | 否（T-11） |
| 3 | `MANUAL_ADDRESS_NOT_BOUND` | `errors.app.manual_address_not_bound` | 否（T-11） |
| 4 | `ASSET_UNAVAILABLE` | `errors.app.asset_unavailable` | **是（T-08）** |
| 5 | `ASSET_ACCESS_DENIED` | `errors.app.asset_access_denied` | **是（T-08）** |
| 6 | `ASSET_IO_FAILED` | `errors.app.asset_io_failed` | **是（T-08）** |
| 7 | `AUTH_PROFILE_EXISTS` | `errors.app.auth_profile_exists` | 否（T-13） |
| 8 | `AUTH_PASSWORD_INVALID` | `errors.app.auth_password_invalid` | 否（T-13） |
| 9 | `AUTH_SESSION_INVALID` | `errors.app.auth_session_invalid` | 否（T-13） |
| 10 | `AUTH_SESSION_EXPIRED` | `errors.app.auth_session_expired` | 否（T-13） |
| 11 | `AUTH_KDF_FAILED` | `errors.app.auth_kdf_failed` | 否（T-13） |
| 12 | `INVITE_KEY_MISSING` | `errors.app.invite_key_missing` | 否（T-13） |
| 13 | `PROVISIONING_PERMISSION_DENIED` | `provisioning.error.permission_denied` | 否（T-11） |
| 14 | `PROVISIONING_MULTIPLE_DEVICES` | `provisioning.error.multiple_devices` | 否（T-11） |
| 15 | `PROVISIONING_GATT_INCOMPLETE` | `provisioning.error.gatt_incomplete` | 否（T-11） |
| 16 | `PROVISIONING_MTU_TOO_SMALL` | `provisioning.error.mtu_too_small` | 否（T-11） |
| 17 | `PROVISIONING_CAPABILITY_UNSUPPORTED` | `provisioning.error.capability_unsupported` | 否（T-11） |
| 18 | `PROVISIONING_BINDING_IDENTITY_MISMATCH` | `provisioning.error.binding_identity_mismatch` | 否（T-11） |
| 19 | `DEVICE_DISABLED` | `errors.app.device_disabled` | **是（T-08）** |
| 20 | `DEVICE_UNASSIGNED` | `errors.app.device_unassigned` | **是（T-08）** |
| 21 | `CLOUD_NOT_CONFIGURED` | `errors.cloud.not_configured` | 否（T-14/T-15） |
| 22 | `CLOUD_TOKEN_MISSING` | `errors.cloud.token_missing` | 否（T-14/T-15） |
| 23 | `CLOUD_DEVICE_NOT_FOUND` | `errors.cloud.device_not_found` | 否（T-14/T-15） |

- 当前产品可达的 5 个 code：`DEVICE_DISABLED`、`DEVICE_UNASSIGNED`、`ASSET_UNAVAILABLE`、
  `ASSET_ACCESS_DENIED`、`ASSET_IO_FAILED`。
- 未改动既有错误码语义、类别、可重试标记或 `ErrorCatalog`（写范围外）；仅补资源与测试。

### 1.2 测试改为权威派生

`entry/src/test/host/I18n.test.mjs` 不再使用手写 `CATALOG_CODES` 子集：

1. `parseDeclaredCodes()` 直接解析 `artifacts/40-detailed-design/des-001a-foundation-transport.md`
   §3.2.3（96 行，含 `HTTP_<status>`）与 `des-001b-domain-presentation.md` §23.4（36 行）。
2. 逐项断言 `ErrorCatalog.resolve(code).i18nKey` 与权威表一致（`SCENE_RUN_IN_PROGRESS` 保留
   `errors.app.scene_run_in_progress` 兼容键，同时断言契约键 `errors.scene.run_in_progress` 存在）。
3. 断言每个 key 在 zh-CN/en-US rawfile 均存在。
4. `staticProductErrorCodes()` 扫描产品源码全部 `AppErrors.*('CODE')`，断言均被权威表覆盖（69 个）。
5. 显式登记 5 个动态 code（`DeviceCommandRunner.reject` / `AssetStoreSecretStore.mapError`），
   防止变量路径再次逃逸。
6. `T10_C14_reachableDynamicErrorCodes_renderBothLocales` 用生产 rawfile 装载真实服务，验证 5 个
   动态 code 在 en-US/zh-CN 下均不返回原始 key。

### 1.3 直接探针（生产 rawfile + 真实服务）

```text
DEVICE_DISABLED      en => This device is disabled and cannot be controlled.
DEVICE_UNASSIGNED    en => This device is not assigned to a room.
ASSET_UNAVAILABLE    en => Local secure storage is unavailable.
ASSET_ACCESS_DENIED  en => Access to local secure storage was denied.
ASSET_IO_FAILED      en => Local secure storage read/write failed. Please retry.
DEVICE_DISABLED      zh => 该设备已停用，无法控制。
DEVICE_UNASSIGNED    zh => 该设备尚未分配房间。
ASSET_UNAVAILABLE    zh => 本机安全存储不可用。
ASSET_ACCESS_DENIED  zh => 无权限访问本机安全存储。
ASSET_IO_FAILED      zh => 本机安全存储读写失败，请重试。
```

`t()` 不再返回原始 key 文本；`ErrorI18nMapper.appKey` 路径与 `I18nKeys.appError` 一致。

### 1.4 键统计与 parity

| 项 | zh-CN | en-US |
|---|---:|---:|
| rawfile 逻辑键 | 212 | 212 |
| rawfile 物理键 | 212 | 213（`device.count_one/_other`） |
| `errors.*` | 110 | 110 |
| `errors.app.*` | 83 | 83 |
| `errors.cloud.*` | 13 | 13 |
| `provisioning.error.*` | 23 | 23 |
| `string.json` | 25 | 25 |

- 权威表具体 code：DES-A 95 + `HTTP_<status>` 模板 + DES-B 36 = 131 个具体 code（132 行）。
- 当前可达：69 个静态 `AppErrors.*` + 5 个动态 = **74** 个；全部有 zh/en 键。
- CHK-01/02/03/04/06 parity 全 PASS；无跨存储重复键。

---

## 2. F-02：`I18nKeys` 委托 `ErrorCatalog`

```ts
static provisioningError(code: string): string {
  return ErrorCatalog.resolve(code).i18nKey;
}
static cloudError(code: string): string {
  return ErrorCatalog.resolve(code).i18nKey;
}
```

- 删除 `stripPrefix` 及本地拼接映射；特殊 code 只保留在 `ErrorCatalog` 单一映射表。
- 验证：`PROVISIONING_SECRET_DRAFT_EXPIRED → provisioning.error.credential_missing`；
  `PROVISIONING_WIFI_AUTH_ERROR → provisioning.error.auth_error`；
  `PROVISIONING_WIFI_NETWORK_NOT_FOUND → provisioning.error.network_not_found`；
  `CLOUD_COMPLETION_TIMEOUT → cloud.command.accepted_not_confirmed`；
  `CLOUD_COMPLETION_UNSUPPORTED`/`CLOUD_INVENTORY_UNSUPPORTED → cloud.completion.unsupported`。
- `ErrorI18nMapper.appKey(AppErrors.of('HTTP_503'))` 断言 key=`errors.app.http_error`、参数=`{status=503}`；
  5 个动态 code 的 mapper/key 映射一致。

---

## 3. F-03：设备骨架修正与注册

- `I18nDevice.test.ets` 使用 rawfile 键 `errors.gateway.success`（`common_*` 属 `string.json`，不能经 `t()` 读取）：
  en-US 断言 `Success`，zh-CN 断言 `成功`，并保留 missing-key/复数/映射断言。
- `entry/src/ohosTest/ets/test/List.test.ets` 已 import 并调用 `i18nDeviceTest()`。
- `entry/src/ohosTest/ets/test/README.md` 目录、注册说明与 T-10 状态已更新。
- 证据：`hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon`
  BUILD SUCCESSFUL；设备/模拟器执行仍 `BLOCKED_ON_DEVICE_RUNNER`，未写成 PASS。

---

## 4. F-04：检查器补强

1. **CHK-04**：`string.json` 现在与 rawfile 一样检查空值、`TODO`/`??`、未闭合 `{}`；bad 夹具新增
   `bad_placeholder`/`bad_brace`，host 测试断言 CHK-04 命中这两个键。
2. **CHK-07**：新增短英文 UI 占位检测（1-3 个首字母大写英文词；排除 `.id(`/CamelCase/技术串）。
   当前生产树命中 `pages/Index.ets:19 Hello World`、`:32 Welcome`，作为 **warning**（T-17/T-18 迁移后
   升级为阻断）；CHK-07 仍为 0 阻断。
3. **allowlist**：`entries` 要求非空 `file` + 正行号 + 理由；`keyEntries` 要求非空 `key` + 理由；
   `keyPrefixes` 要求非空前缀 + 理由；非法 allowlist 以 exit 2 拒绝（host 用例覆盖）。
4. **限制披露**：CHK-05 的 0 告警依赖 15 个 `keyPrefixes` 与动态前缀，**不等于**“无未使用键”；
   报告与 README 已明确。T-17/T-18 接入后应逐步删除按域前缀豁免。

---

## 5. F-05 / F-06：迁移口径与路径例外

### 5.1 迁移统计（CSV 实测）

| 分类 | 数量 | 审查结论 |
|---|---:|---|
| A 迁移 | 606 | `ACCEPTED` 10 + **`PENDING_REVIEW` 596** |
| C 废弃（启发式） | 6 | `DEPRECATED (heuristic)` |
| D 排除（品牌） | 3 | `EXCLUDED (brand data)` |
| **合计** | **615** | |

- 报告/README 的“606 条待迁”已全部更正为 **596 条待迁**（606 是 A 类总数）。
- 新增 `重译审查` 列：`B_REWRITE_REQUIRED`=11（`档案` 被机翻为 `file(s)`/`machine`，
  如 `解锁本机档案`、`本机使用档案`、`创建本机档案`），`B_PENDING`=585，`B_REVIEWED_ACCEPTED`=10。
  B 类明确为 A 类的英文子审查，不改变 596 的迁移工作量。
- 新增 `复核标记` 列：6 条 C 类全部 `RECHECK_REQUIRED`；其中两条模拟器/DEV-ONLY 文案标记
  `SAFETY_RECHECK_REQUIRED`，备注对应 `errors.app.dev_simulator_rejected` / `GATEWAY_PROFILE_BLOCKED`，
  要求 T-17/T-18 禁止仅凭关键词删除。
- `t10-i18n.md` 摘要表第 33/35 行的 `||` 断行已拆为独立行。

### 5.2 路径例外 T10-EX-01

| 项 | 内容 |
|---|---|
| 契约路径 | `tools/i18n/check_i18n.py`、`tools/i18n/allowlist.json`、`tools/i18n/legacy_migration.csv`、`reports/i18n/*`（DES-B §7.4.4 / delivery-plan T-10） |
| 实际路径 | `entry/src/test/i18n/check_i18n.py`、`allowlist.json`、`legacy-migration.csv`；报告 `entry/src/test/evidence/` |
| 原因 | `wp-031-i18n` handoff 的写范围收窄，未授权 `tools/` 与 `reports/`（不是 delivery-plan 缺少该路径） |
| 影响 | 不影响 CHK 语义/退出码/schema；仅契约路径查找与 CI 约定不一致 |
| 后续 owner | 后续工具任务或 T-19 |
| 迁移条件 | 文件迁移到契约路径；命令、报告 schema、CSV 列语义保持不变；更新 README/测试引用 |
| CQG 记录 | 需在 CQG-T10 记录本例外及其关闭条件 |

---

## 6. F-07 / F-08：initialize 失败语义

### 6.1 F-08 current-only 失败

`initialize` 现在计算有效 locale：

```ts
const effectiveLocale = loaded.current !== undefined ? locale : ZH_CN;
const effectiveCurrent = loaded.current !== undefined ? loaded.current : loaded.base;
this.currentLocale = effectiveLocale;
this.assignBundles(effectiveCurrent, loaded.base);
await this.applyPlatform(effectiveLocale);
```

- current bundle（如 en-US）失败、zh-CN base 成功时：`getLocale()`/`I18nLoadResult.locale` = `zh-CN`，
  `t()` 服务 zh-CN base，`applyPlatform` 只应用 `zh-CN`，不再出现 `$r`=en / `t()`=zh 的语言劈裂。
- `loaded` 仍返回 `false`，`error` 保留 `I18N_RESOURCE_LOAD_FAILED`；调用方可提示/重试。
- both-fail 时同样回退 `zh-CN`（无 bundle，`t()` 返回 key 文本），不 apply 失败 locale。
- 用例：`T10_C14_currentBundleFailure_fallsBackToBaseLocaleWithoutApplyingFailedLocale`、
  both-fail 用例；均断言 `applied` 不含 en-US。

### 6.2 F-07 诊断日志

- `initialize` 调用 `warnBaseFailure(loaded)`：current 成功、base 缺失时记录 `I18N_RESOURCE_LOAD_FAILED`。
- 新增 `warnCurrentFailure`：current 缺失时记录 `{locale, fallback}`（requested=zh-CN 时只记 locale），
  不含用户数据/密钥/翻译内容。
- 用例：base-fail 用例断言 logger 含 `I18N_RESOURCE_LOAD_FAILED`；current-fail 用例同样断言。

---

## 7. 验证命令与结果（当前 revision）

| 命令 | 结果 | 证据 |
|---|---|---|
| `ohpm install` | **PASS**，exit 0，install completed | `entry/src/test/evidence/t10-fix-ohpm-install.log` |
| `hvigorw clean assembleHap --no-daemon` | **PASS**，BUILD SUCCESSFUL，35 tasks（34 executed, 1 up-to-date） | `t10-fix-clean-assemble.log` |
| `codelinter -c code-linter.json5 -p default .` | **PASS**，No defects found，exit 0 | `t10-fix-codelinter.log` |
| `entry/src/test/run-host-tests.sh` | **PASS：275 tests / 275 pass / 0 fail / 0 skip / exit 0**；T10_C14 28 条 | `t10-fix-host-node-tests.tap` |
| `python3 entry/src/test/i18n/check_i18n.py --root . --report entry/src/test/evidence/t10-fix-i18n-report.json --allowlist entry/src/test/i18n/allowlist.json --strict-ui` | **PASS**，CHK-01..09；blockingFailures=0；warnings=2；missingKeys=0；hardcoded=2；exit 0 | `t10-fix-i18n-checker.log`、`t10-fix-i18n-report.json` |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon`（附加） | **PASS**，BUILD SUCCESSFUL（设备测试仅编译，未执行） | `t10-fix-ohosTest-compile.log` |

T-10 初版证据（`t10-*.log|tap|json`）保留为历史 revision；本报告只以 `t10-fix-*` 作为当前证据。

---

## 8. 不变项与风险

### 8.1 未改变

- `I18nService` 公开 API、fallback 链（current+suffix → current → base+suffix → base → key）、
  插值单次替换、英文 `_one/_other` 与中文基键语义。
- 双存储边界（rawfile 动态/错误/状态；`string.json` 静态 UI/元数据）。
- D-022 / `SCENE_RUN_IN_PROGRESS` 双键兼容策略；`ErrorCatalog` 不在本任务修改。

### 8.2 残余风险

| ID | 风险 | owner/动作 |
|---|---|---|
| R-01 | 设备/模拟器未执行；`RawfileI18nLoader`、`OhosLocaleApplier`、`$r` 重渲染未验证 | 设备 owner / T-17/T-18；C-14 保持 `UNVERIFIED` |
| R-02 | T-17/T-18 仍需迁移 **596** 条；3 条 B_REWRITE_REQUIRED、2 条 C 类 SAFETY_RECHECK_REQUIRED | T-17/T-18 |
| R-03 | CHK-07 短英文仅为告警；`Index.ets` 仍含 `Hello World`/`Welcome` | T-17/T-18 后升级为阻断 |
| R-04 | CHK-05 0 告警依赖前缀豁免，不能证明无未使用键 | T-17/T-18 移除按域前缀 |
| R-05 | 检查器/迁移表仍偏离 `tools/i18n`、`reports/i18n` | 后续工具任务 / T-19（T10-EX-01） |
| R-06 | `hvigorw test` Previewer 仍不可执行；本报告仅以 ohosTest HAP 编译作为附加证据 | 测试环境 owner |

---

## 9. 追溯

| 需求/契约 | 修复证据 |
|---|---|
| DES-A §3.2.3 / §24.3-4 | 23 键落地；131 code 权威派生用例 |
| DES-B §23.4 | 5 个新增错误码键；device/cloud 双 locale |
| DES-B §7.1.4 | `provisioningError`/`cloudError` 委托 `ErrorCatalog` |
| DES-B §7.1.3 / §7.3.1 | initialize current/base 失败语义与日志 |
| DES-B §7.5 / §7.3.2 | 设备测试 rawfile 键与注册 |
| DES-B §7.4.4 / I18N-DESIGN §6.3 | CHK-04/07/allowlist 补强；路径例外 T10-EX-01 |
| I18N-DESIGN §5 / DES-B §7.4.3 | 596 pending；B 子审查；C 安全复核标记 |
| I18N-05 | 0 missing/0 阻断；动态 code 不返回原始 key |
| TEST-001 | host 275/275；ohosTest 仅编译；设备 `BLOCKED` |

---

## 10. 结论

F-01（阻断）与 F-02..F-08 已按评审报告逐条修复，当前 revision 的五项规定命令全部 PASS，检查器 0 阻断。
C-14 仍为 `UNVERIFIED`：设备/模拟器执行、运行时 `$r` 同步、T-17/T-18 的 596 条 UI 文案迁移均未完成。
本报告不授予 `STABLE`、不替代独立复审或 CQG-T10。
