# RELEASE-001 发布准备计划

- **Artifact ID**: RELEASE-001
- **Producer**: agent:release-engineer
- **Type**: Release Readiness Assessment / Release Plan / Rollback Plan / Stage Gate Input
- **Status**: **COMPLETE（发布准备评估完成；已完成复审 F-01..F-06 修订）**；**Release Verdict: `NOT_READY`（不满足发布授权条件）**
- **Date**: 2026-10-18
- **Task**: `wp-112-release-plan`（task 分支 `task/wp-112-release-plan`，父分支 `feat/yaocore-app`，base commit `6cd9a88d0fdc1b08cc6ffca233c12c41df737519`）
- **Revision task**: `wp-116-release-fix`（`task/wp-116-release-fix`，父分支 `feat/yaocore-app` @ `b716207`；处理独立复审 `artifacts/70-review/t26-release-review.md` 的 F-01..F-06）
- **Code evidence baseline**: **TEST-002 @ `e74a181`**（产品代码内容自该 revision 至本修订未变）；RELEASE-001 构建探针 @ `6cd9a88`
- **Final release revision/tag**: **未冻结**（待 B-06/B-09 与用户决策后确定；当前无 tag；`e74a181` 是代码证据基线，不是最终发布 commit）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `release`（用户 2026-10-18 选择「Release 准备（不发布）」）
- **Upstream**: `state/project-state.md`（Release 准备段）；`artifacts/65-acceptance/acceptance-report.md`（ACCEPT-001）；`artifacts/60-testing/testing-stage-report.md`（TEST-002 @ `e74a181`）；`artifacts/80-maintenance/maintenance-plan.md`（MAINTENANCE-PLAN-001 v1.1）；`README.md`（README-001 v1.3）；`config/project.md`；`AppScope/app.json5`；`build-profile.json5`；`config/git-policy.json`；`docs/git-collaboration.md`；G-014..G-018；`artifacts/70-review/t26-release-review.md`（T26-RELEASE-REVIEW）
- **Write scope**: `artifacts/85-release/`、`docs/`；本任务唯一交付为 `artifacts/85-release/release-plan.md` 与 `docs/release-checklist.md`。未修改代码、版本号、签名配置、测试断言、契约、Gate 记录、release notes/CHANGELOG/README 或 `input/`。
- **Input pins**: 原始任务 `wp-112` 的 10 项输入 10/10 一致（§11.1）；修订任务 `wp-116` 的 4 项输入与只读复核见 §11.5。

> **结论先行**
>
> 1. **发布准备已完成**：版本/标识、构建、签名、文档、测试、风险、远端与回滚项已盘点；已实际构建并校验**未签名 HAP**；发布检查单已产出。
> 2. **Release Verdict 为 `NOT_READY`**：许可证未定、无签名配置、设备/用户验收未执行、GAP-AC-01..03 未决、远端/发布通道未授权，另有公开旧版本身份/版本/许可证需用户在 §4.4 A/B/C 中决定、CHANGELOG/Release Notes 草案待评审签核、构建硬化/API 14 兼容性（B-09）未决。上述任一未关闭，均不得进入发布授权或市场/远端发布。
> 3. **本报告不构成发布授权、部署授权、签名授权或用户验收**。push、PR/MR、tag、签名、市场发布与任何远端写操作仍需用户显式授权。
> 4. **当前构建产物为未签名 HAP，不可安装、不可发布**。`hvigorw clean assembleHap` 的默认产物为 `buildMode=debug`；发布候选应使用 `buildMode=release` 重新构建，并在签名后重新记录大小与 SHA-256。

---

## 1. 范围、revision 与权威边界

| 项 | 值 |
|---|---|
| 仓库根 / cwd | `/home/quirkybrain/code/harmony-projects/YaoCore` |
| 文档修订分支 / HEAD | `task/wp-116-release-fix` / `f1fbe0d`（修订起点；本次修订提交见 Git 记录）；代码内容与 `e74a181` 一致 |
| 父分支 / 集成基线 | `feat/yaocore-app` / `b716207`（本修订 handoff 父提交）；release 准备基线曾为 `6cd9a88` |
| 发布候选代码内容 | TEST-002 @ `e74a181`；产品代码/构建配置自 `e74a181` 至本修订 **无差异**（`git diff --quiet` exit 0） |
| 代码证据基线 vs 最终发布 revision | **代码证据基线 = `e74a181`/TEST-002**（`6cd9a88` 为构建探针 revision）；**最终 release revision/tag = 未冻结**（当前无 tag） |
| 公开旧版本 | `origin/main` @ `7d6f4c9`：公开 YaoCore 1.0.0（`io.github.quirkybrain.yaocore`、versionCode 1000000、Apache-2.0 + NOTICE）；详见 §4.4 |
| 目标 | release **仅准备**：就绪评估、发布计划、发布检查单、未签名构建校验、签名与远端清单 |
| 明确不授权 | push、force push、PR/MR、`main` 合并、tag 创建/删除、签名证书使用、应用市场/远端发布、任何远端写操作 |
| 发布通道 | 未选择；远端候选见 §7.2；身份/版本/许可证选项见 §4.4 |
| 发布身份/许可证 | **未决定**；待用户在 §4.4 选项 A/B/C 中选择，本计划不代为选择 |
| 用户验收 | **未执行**（ACCEPT-001 仅 `READY_FOR_USER_ACCEPTANCE`） |
| 设备 | `hdc` 不在 PATH；SDK 内 `hdc list targets` 返回 `[Empty]`；无模拟器实例 |
| 签名 | `build-profile.json5` 的 `signingConfigs: []` |

**权威顺序**：用户当前请求 → `config/project.md` → 已验证资产/标准（`input/`）→ 持久化 Artifacts/Decisions/State → 框架文档 → 已记录假设。`input/` 为冻结语料，本任务未修改。

**非目标**：不重新定义需求、不做架构决策、不修复 UI 偏离、不签署或安装 HAP、不创建远端分支、不推送、不发布。

---

## 2. Release Verdict 与阻塞项

### 2.1 Verdict

**`NOT_READY`**

含义：
- **发布准备可以做、且已完成**：本计划、检查单与未签名构建证据可作为后续授权输入的基线。
- **不能进入发布授权/执行**：许可证、签名、设备/用户验收、UI 偏离、远端策略等发布前置未满足。
- **不能宣称**：产品验收完成、设备验收完成、NFR 达标、可安装、可发布、签名完成、已推送或已上架。

### 2.2 阻塞项（发布前必须关闭或有书面风险接受）

| ID | 阻塞项 | 现状 | 关闭条件 | 责任 |
|---|---|---|---|---|
| **B-01** | 项目级许可证未定，且未处理公开旧版本许可证 | 当前树无 `LICENSE`/`NOTICE`；README 标 **TODO**；`entry/oh-package.json5` license 为空。`origin/main` @ `7d6f4c9` 的公开 YaoCore 1.0.0 为 **Apache-2.0 + `LICENSE` + `NOTICE`**（Copyright 2026 Zhang HaoXuan，来源 `https://github.com/Quirkybrain/YaoCore`） | **待用户在 §4.4 选项 A/B/C 中决定**：A 继承 Apache-2.0/NOTICE；B 为新应用确定独立许可证（若存在衍生关系仍须评估 Apache-2.0 义务）；C 的混合/迁移方案单独裁定。随后提交 `LICENSE`/`NOTICE` 并完成第三方依赖核对 | 项目所有者 / `technical-writer` |
| **B-02** | 无签名配置，HAP 不可安装 | `signingConfigs: []`；构建日志 `Will skip sign 'hos_hap'`；产物未签名 | 用户提供证书/Profile/密钥库与口令（不入库）；完成签名、签名校验与安装 smoke | 用户 / 授权签名人 / `release-engineer` |
| **B-03** | 设备/用户验收未执行 | ACCEPT-001 U-01..U-12 全部 **NOT RUN/BLOCKED**；`hdc` target 为空 | 按维护计划 §4 执行 BLK-01..08，或用户书面接受残余并限定发布范围 | 用户 / `system-verifier` |
| **B-04** | GAP-AC-01..03 未决 | LAN IP 未显示；多家庭切换为跳转而非首页弹窗；房间图标未接线/展示 | 用户书面接受为 v1 简化，或派发 bounded fix 后重跑相关测试 | 用户 / `implementation-engineer` |
| **B-05** | 远端/发布通道未授权，公开旧版本的用户/Release 影响未决策 | `origin` 存在；`origin/main=7d6f4c9` 是公开 YaoCore 1.0.0（本地 `main` 与其历史不相关）；`feat/yaocore-app` 未推送；无 tag；`main_merge_mode: review_request_when_remote` | **待用户在 §4.4 选项 A/B/C 中决定身份/许可证后**，再按 §7.2 选择远端通道 A-E 并授权；配置保护分支与 CI；不得强推改写共享历史；须评估旧公开版本用户、Release/tag 与来源声明 | 用户 / `repository-manager` |
| **B-06** | 发布标识、版本与发布构建模式未最终冻结 | 当前 `bundleName=com.example.yaocore`、`vendor=example`、`versionName=1.0.0`、`versionCode=1000000` 未冻结；旧公开 1.0.0 已使用 `io.github.quirkybrain.yaocore` + versionCode **1000000**；默认构建为 `buildMode=debug` | **待用户在 §4.4 选项 A/B/C 中决定**：A 沿用旧 bundleName 且 versionCode 必须 **>1000000**（如 1000001），重建/重签/升级验证；B 保留新 bundleName 作为独立应用并声明旧用户无法升级；C 记录迁移/商店策略。随后以 `buildMode=release` 干净重建 | 用户 / `release-engineer` / `implementation-engineer` |
| **B-07** | CHANGELOG/Release Notes 未评审/签核 | **草案已产出 @ `63d2235`**：`CHANGELOG.md`（`Status: DRAFT`）与 `docs/release-notes-v1.0.0.md`（`DRAFT / NOT_READY`）；内容仍待评审与用户/发布负责人签核 | 完成发布评审与签核；按 B-09 与 §4.4 决定同步已知限制、身份/版本与许可证表述；**不得把草案写成已定稿或对外发布版本** | `technical-writer` + 用户/发布负责人 |
| **B-08** | 残余风险未逐项书面确认 | D-030/RA-01、R4-01/RA-02、PORT-LOC-01、i18n 残余、设备 BLOCKED、ACK p95 MOCK_ONLY、NFR partial、测试 lint/覆盖率缺口、未签名产物 | 用户在发布 Gate 记录中逐项接受，或派发修复；不得静默忽略 | 用户 / Orchestrator / 各 owner |
| **B-09** | 构建硬化/兼容性决策未完成 | API 18 `ColumnType/TEXT/BLOB` 与 compatible **API 14** 的运行时兼容性未验证；混淆/裁剪未启用且未决定；符号化/崩溃定位与回归方案未记录 | 完成 API 14 运行时验证，或用户书面接受“未验证”的范围与残余风险；记录混淆/裁剪启用与否的决策、理由、符号化/崩溃定位方案与回归结果；不得仅以“构建成功”关闭 | 用户 / `implementation-engineer` / `release-engineer` |

> B-01..B-09 未全部关闭时，发布 Gate 结论保持 `NOT_READY`；不得用“代码级 PASS”替代发布授权。`release-notes-v1.0.0.md` §9 与 `docs/release-checklist.md` §7 使用同一 B-01..B-09 编号（wp-117 已同步）；本任务只改本计划与检查单，不改变任何阻塞项状态。

### 2.3 已就绪的部分（可复用证据）

- 代码级 Gate 链：G-015 review、G-016 testing、G-017 acceptance readiness、G-018 documentation 均为 `PASS`/`PASS_WITH_ACCEPTED_RISKS`；release 为独立阶段，不自动继承为发布 PASS。
- TEST-002：11/11 强制矩阵 exit 0；host 697/697、crosscheck 66/66、仿真器 20/20、layering 0 violation、fixture 27/27、i18n 0 blocking、triage 615 行一致、构建/lint 通过。
- 本任务在 `6cd9a88` 上重新构建并复跑关键检查（见 §11），未发现产品行为失败或测试断言失败。
- README v1.3（README-001）、ACCEPT-001、TEST-002、维护计划 v1.1 与 G-014..G-018 可作为发布说明/风险登记的上游。

---

## 3. 就绪盘点

> 状态口径：`DONE` = 当前 revision 有可复现证据；`PARTIAL` = 部分完成；`PENDING` = 待用户/owner 决定；`BLOCKED` = 前置条件缺失；`UNAUTHORIZED` = 需显式授权；`NOT_RUN` = 未执行。不得把 `BLOCKED`/`NOT_RUN`/`MOCK_ONLY` 写成 PASS。

| 维度 | 当前值 / 证据 | 状态 | 发布影响 / 必做动作 |
|---|---|---|---|
| **版本** | `versionName=1.0.0`、`versionCode=1000000`（`AppScope/app.json5`；HAP `module.json`、`pack.info` 一致）。公开旧版本 `origin/main` @ `7d6f4c9` 已使用 `1.0.0` / `1000000` | `PENDING` | **待 §4.4 A/B/C 决定**：A 沿用旧 bundleName 时 versionCode 必须 >1000000；B/C 按方案记录策略。签名后不得再改版本 |
| **包标识** | `bundleName=com.example.yaocore`、`vendor=example`、`label=$string:app_name`。公开旧版本为 `io.github.quirkybrain.yaocore` / `YaoCore` | `PENDING` | **待 §4.4 A/B/C 决定**：`com.example.*` 通常为示例标识；沿用旧标识会改变升级路径与签名 Profile；新标识需明确独立应用身份。须在签名前完成 |
| **SDK / API** | `compileSdkVersion=26.0.0`、`targetSdkVersion=26.0.0`、`compatibleSdkVersion=5.0.2(14)`、`runtimeOS=HarmonyOS`；本机构建 SDK `26.0.0.105` | `PARTIAL` | 构建 PASS；`RdbStoreAdapter` 使用 API 18 的 `ColumnType/TEXT/BLOB`，compatible 14 运行时未验证；需设备/兼容性验证或显式风险接受（B-09） |
| **签名** | `signingConfigs: []`；product 引用 `signingConfig: "default"` 但无配置；构建跳过签名 | `BLOCKED` | 见 §6；未签名 HAP 不可安装/发布 |
| **构建产物** | 默认 `clean assembleHap`：`entry/build/default/outputs/default/entry-default-unsigned.hap`，4,597,005 B，SHA-256 `1983ea22…839c7`，14 条目，`buildMode=debug`；补充 `buildMode=release` 干净构建：1,616,146 B，SHA-256 `1602110d…35bd03`，13 条目，`buildMode=release`、`debug=false`，均未签名 | `DONE（unsigned build）` / `NOT_INSTALLABLE` | 发布候选须以 release 模式在冻结 revision 上重建；签名后重新记录大小/SHA-256；构建目录被 gitignore，产物不提交 |
| **CHANGELOG / Release Notes** | **草案已产出 @ `63d2235`**：`CHANGELOG.md`（`Status: DRAFT`）与 `docs/release-notes-v1.0.0.md`（`DRAFT / NOT_READY`） | `PARTIAL` | 内容待发布评审与用户/发布负责人签核（B-07）；按 B-09 与 §4.4 决定同步 B 列表、身份/版本与许可证表述 |
| **LICENSE** | 当前树无项目级 `LICENSE`；README §许可与致谢为 **TODO**；`entry/oh-package.json5` 的 `license` 为空；模板/第三方文件保留各自版权声明。公开旧版本为 **Apache-2.0 + `LICENSE` + `NOTICE`** | `BLOCKED` | **待 §4.4 A/B/C 决定**：A 继承旧 Apache-2.0/NOTICE；B 为新应用确定许可证（如有衍生关系仍须评估 Apache-2.0 义务）；C 单独裁定。许可证未定前不得公开再分发 |
| **文档** | README-001 v1.3、ACCEPT-001、TEST-002、MAINTENANCE-PLAN-001 v1.1、G-014..G-018；本任务维护发布计划与检查单；CHANGELOG/release notes 草案 @ `63d2235` | `PARTIAL` | release notes/CHANGELOG 待评审/签核；商店文案/隐私说明（如适用）仍缺；文档数字须与本计划/证据一致 |
| **测试证据** | TEST-002 @ `e74a181`：11/11 矩阵 exit 0；`6cd9a88` 复跑：ohpm install、build、host 697/697、crosscheck 66/66、simulator 20/20、layering 0 violation、fixture 27/27、i18n 0 blocking、triage 615、codelinter 0 error/25 warning；产品代码自 `e74a181` 至本修订未变 | `DONE（code-level；代码证据基线 e74a181/TEST-002）` | 设备/真实网络/性能仍见下；最终 release revision/tag 未冻结；任何代码/配置变更使证据失效，需 Change Impact 与重跑 |
| **验收** | ACCEPT-001：`READY_FOR_USER_ACCEPTANCE`（有条件）；U-01..U-12 未执行；G-017 仅为 acceptance readiness | `PENDING` | 用户验收/设备矩阵完成前，不得宣称产品验收或发布就绪 |
| **已接受风险** | D-030/GAP-T18-01（RA-01）、R4-01（RA-02）、PORT-LOC-01、i18n 6 PENDING + 11 B + 6 C + 3 D、设备 BLOCKED（RA-05）、ACK p95 MOCK_ONLY（RA-06）、NFR 4.1/4.2/4.3 partial（RA-07）、测试 lint/覆盖率缺口（RA-08）、未签名（RA-10）；构建硬化/API 14 兼容性（B-09） | `PENDING_RELEASE_SIGNOFF` | 发布 Gate 前逐项书面接受或修复；不得把 partial 写成达标 |
| **设备矩阵** | BLK-01..08：Hypium host、设备/模拟器、真实 BLE、真实 LAN/TLS、IoTDA、视觉/A11y、性能、真实硬件 | `BLOCKED` / `NOT_RUN` | 由用户按维护计划 §4 执行；至少完成签名安装 + 启动/核心链路 smoke 才可考虑发布 |
| **远端/通道** | `origin=https://github.com/Quirkybrain/YaoCore.git`；公开 `origin/main=7d6f4c9`（YaoCore 1.0.0）；本地 `main=a6f6558` 与其 **无 merge-base（历史不相关）**；`feat/yaocore-app` 仅本地；无 tag；未 push | `UNAUTHORIZED` | **待 §4.4 A/B/C 与 §7.2 远端通道 A-E 决定并授权**；`main_merge_mode: review_request_when_remote` 禁止本地直并 main；须评估旧公开版本用户/Release/来源声明 |
| **依赖** | `oh-package.json5` 无运行时依赖；devDependencies `@ohos/hypium 1.0.25`、`@ohos/hamock 1.0.0`；`oh-package-lock.json5` 存在 | `PARTIAL` | 需在发布前核对依赖许可证/来源与锁文件一致性；本任务未做法律级许可证审计 |

### 3.1 关键事实

- **代码内容未漂移**：`git diff --quiet e74a181..HEAD -- entry/src/main tools entry/src/test entry/src/ohosTest` exit 0；`git diff --quiet e74a181..HEAD -- build-profile.json5 AppScope/app.json5 oh-package.json5 entry/oh-package.json5 hvigorfile.ts` exit 0。因此 TEST-002 的代码级结论适用于当前代码内容；但发布构建仍需按当前 revision 重新执行。
- **证据基线与最终发布 revision 不同**：`e74a181`/TEST-002 是**代码证据基线**；`6cd9a88` 是 RELEASE-001 构建探针 revision；本修订（`f1fbe0d` 之上）只改发布文档。**最终 release revision/tag 尚未冻结**，当前无 tag；必须待 B-06/B-09 关闭后创建 tag、重建、签名并复验。
- **公开旧版本存在**：`origin/main` @ `7d6f4c9` 是公开的 YaoCore 1.0.0（`io.github.quirkybrain.yaocore`、versionCode 1000000、Apache-2.0 + `NOTICE`）。因此不能无条件写“首次发布/当前无公开旧版本”；身份/版本/许可证选项见 §4.4（未决定）。
- **默认构建不是 release 模式**：任务指定的 `hvigorw clean assembleHap --no-daemon` 产物 `module.json` 为 `"buildMode":"debug"`、`"debug":true`。这是本次发布准备发现的重要构建边界；发布候选必须使用 `buildMode=release` 并验证。
- **HAP 未签名**：最终 release-mode HAP 的 13 个条目中无 `META-INF`/签名材料；构建日志 `Will skip sign 'hos_hap'`。不得把“BUILD SUCCESSFUL”写成可安装/可发布。
- **构建非字节可复现**：同一 release-mode 代码的两次构建大小相同（1,616,146 B）但 SHA-256 不同（`be83926d…` vs `1602110d…`），说明归档时间戳/打包元数据导致字节差异；发布证据必须绑定 commit + 工具链 + 命令 + 产物 SHA，而不是承诺哈希可复现。

---

## 4. 发布范围与版本策略

### 4.1 发布范围

- **产品**：YaoCore（爻构）HarmonyOS NEXT 原生 App，v1 代码级交付；`entry` 模块，C-01..C-29 的代码/资源/测试/文档。
- **设备范围**：`door`/`light`/`sensor`/`ac` 完整支持；`switch`/`camera`/`curtain`/`fan`/`speaker` 只读降级；未知类型只读并记录偏差。
- **明确不在本仓库/本发布内**：ESP32-S3 固件构建链、真实固件 v2.1/TLS Profile、云端后端、应用市场素材/隐私政策定稿、设备矩阵实测结果。
- **本次 release 任务不改代码**：当前候选为 `6cd9a88` 的已提交内容。任何版本号、bundleName、签名配置、UI 偏离修复或缺陷修复都属于新的变更任务，必须重新构建、重跑受影响矩阵并更新证据。

### 4.2 版本策略（建议，未修改代码）

| 场景 | versionName | versionCode | 说明 |
|---|---|---|---|
| 新应用身份（§4.4-B/C；当前候选 `com.example.yaocore`） | `1.0.0` | `1,000,000` | 作为独立应用可使用 `1,000,000`；不得暗示覆盖或升级旧公开应用 |
| 沿用旧公开身份（§4.4-A；`io.github.quirkybrain.yaocore`） | 由用户决定（可保持 `1.0.0` 或升为 `1.0.1`） | **必须 >1,000,000**（如 `1,000,001`） | 旧公开 1.0.0 已占用 `1,000,000`；必须验证覆盖安装/AGC 版本校验与旧数据兼容性 |
| 补丁 | `1.0.1` | `1,000,001` | 缺陷/安全修复；不得降低 versionCode |
| 次版本 | `1.1.0` | `1,001,000` | 新能力/兼容性变更 |
| 主版本 | `2.0.0` | `2,000,000` | 不兼容变更 |

建议规则：`versionCode = major × 1,000,000 + minor × 1,000 + patch`（与当前 `1.0.0 → 1,000,000` 一致）。这是**建议**，不是已实施变更；`AppScope/app.json5` 当前仍为 `1.0.0/1000000`。若采用 §4.4-A，必须在该规则之外确保 versionCode > 旧公开版本的 `1,000,000`，具体值由用户确认。

**冻结顺序**：确认 bundleName/vendor → 确认 versionName/versionCode → 完成签名配置 → 干净 release 构建 → 签名 → 记录最终产物 SHA-256 → 打 tag/发布。签名后再改版本/包名会使已签产物与发布记录失效。

### 4.3 包标识与升级路径

- 当前 `bundleName=com.example.yaocore`、`vendor=example`。正式发布前必须由项目所有者确认；若替换为组织域名反写，签名 Profile/AGC 应用记录必须同步重建。
- bundleName 是应用身份的一部分；发布后不能通过同名升级切换到不同 bundleName。若沿用已公开的 `io.github.quirkybrain.yaocore`，则必须使用更高 versionCode 覆盖旧公开 1.0.0；若保留 `com.example.yaocore`，则是独立应用身份，旧公开用户无法升级。两种路径均需用户决定，见 §4.4。
- 若曾在内部分发过同 bundleName 的构建，也必须用更高 versionCode 做升级安装验证；不得再以“无公开旧版本”为由跳过升级验证。

### 4.4 公开旧版本对照与身份/版本/许可证选项（待用户决定）

> 本节只呈现可核对事实与选项后果，**不替用户选择**，也不构成法律意见。**选项 A/B/C 是身份/版本/许可证选项**，与 §7.2 的**远端通道选项 A–E** 是两组独立决策。

**事实对照**（只读复核 `origin/main`；本任务未 fetch、未写入远端）：

| 项 | 公开旧版本（`origin/main` @ `7d6f4c9`） | 本地当前工作树（本修订） |
|---|---|---|
| bundleName | `io.github.quirkybrain.yaocore` | `com.example.yaocore` |
| vendor | `YaoCore` | `example` |
| versionName / versionCode | `1.0.0` / `1000000` | `1.0.0` / `1000000` |
| 许可证 | **Apache-2.0**（`entry/oh-package.json5`）；`LICENSE` + `NOTICE` 存在 | `entry/oh-package.json5` 的 license 为空；当前树无 `LICENSE`/`NOTICE` |
| NOTICE 内容 | `YaoCore（爻构）`、`Copyright 2026 Zhang HaoXuan`、来源 `https://github.com/Quirkybrain/YaoCore`，并要求再分发时保留版权/许可证/来源声明 | 无对应 `NOTICE` |
| 用户/升级关系 | 公开 YaoCore 1.0.0 | 本地 `main` 与 `origin/main` 历史不相关；不能自动视为旧版本升级 |
| 远端状态 | `refs/heads/main=7d6f4c99fa1bf0baf5e40d1948a97f564a647401` | `feat/yaocore-app` 未推送；无 tag |

**选项与后果**（未决定；不得在文档或发布记录中暗示已选定）：

| 选项 | 做法 | 后果 / 必须完成的工作 |
|---|---|---|
| **A. 沿用旧公开身份** | 采用 `io.github.quirkybrain.yaocore` + **递增 versionCode（>1000000，如 1000001）** + 继承 Apache-2.0 / `LICENSE` / `NOTICE` | 旧公开用户可升级；需验证覆盖安装、旧数据/旧包名兼容性、AGC/Profile 同步、版权/来源声明与合规审查；versionName 由用户决定（可保持 1.0.0 或升为 1.0.1） |
| **B. 新应用身份** | 保留 `com.example.yaocore`（或另选新 bundleName）作为独立应用；明确新产品身份与许可证 | 旧公开用户**无法升级**；需在 release notes/商店页明确这是独立应用而非旧版升级；versionCode 可从 1000000 开始。若代码/设计与旧公开版本存在衍生关系，Apache-2.0 的版权/许可证/来源义务仍需评估；新许可证由用户决定 |
| **C. 混合/迁移方案** | 例如新 bundleName + 数据迁移/导入，或旧 bundleName + 迁移工具/双应用过渡 | 需额外的数据迁移设计、旧数据兼容验证、商店策略（双应用/下架/迁移说明）与用户支持成本；在方案、风险与商店规则明确前不可执行 |

**未决定项**：B-01（许可证）、B-05（远端/通道）、B-06（身份/版本）均等待用户在 A/B/C 中决定；本计划不推荐、不选择。选择后必须更新 §4.2 版本策略、§6 签名计划、§7 远端策略、§9 Gate 判据与检查单，并重新构建/签名/复验受影响证据。

**只读复核命令**（不得写入或 fetch/push）：

```bash
git show 7d6f4c9:AppScope/app.json5
git show 7d6f4c9:entry/oh-package.json5
git show 7d6f4c9:LICENSE | head -5
git show 7d6f4c9:NOTICE
git show 7d6f4c9:README.md | grep -n 'Apache License'
git merge-base main origin/main   # 空：历史不相关
```

---

## 5. 构建与产物

### 5.1 工具链与环境（实测）

| 项 | 值 |
|---|---|
| OS | Linux x86_64 |
| Node | v24.15.0 |
| `ohpm` | 26.0.0.630 |
| `hvigorw` | 6.26.8 |
| `codelinter` | 6.0.240 |
| Java | OpenJDK 21（`java` 可用） |
| Python | 3.12.3（仅标准库） |
| HarmonyOS SDK | `26.0.0.105`；`DEVECO_SDK_HOME=/home/quirkybrain/harmonyos/command-line-tools/sdk` |
| 设备 | `hdc` 不在 PATH；SDK 内 `hdc list targets` = `[Empty]`；无模拟器 |
| 签名 | `signingConfigs: []`；未签名构建 |

### 5.2 实际执行的命令与结果

> 全部在仓库根、`task/wp-112-release-plan @ 6cd9a88` 执行；使用 `set -o pipefail`；构建目录为 gitignored，不进入提交。

| # | 命令 | 实测结果 | Exit |
|---|---|---|---|
| 1 | `ohpm install` | `install completed in 0s 49ms` | **0** |
| 2 | `hvigorw clean assembleHap --no-daemon` | `BUILD SUCCESSFUL in 15 s 529 ms`；35 tasks（34 executed / 1 up-to-date）；unsigned HAP；`buildMode=debug` | **0** |
| 3 | `find entry/build -name '*.hap' -type f` | `entry/build/default/outputs/default/entry-default-unsigned.hap`（唯一 HAP） | **0** |
| 4 | `sha256sum <hap>` | 默认构建：`1983ea22f54305c4817106e9bfc55122f42636071caceacca6f3dd3b219839c7` | **0** |
| 5 | `ls -lh <hap>` / `stat` | 默认构建：4,597,005 B（`4.4M`） | **0** |
| 6 | `hvigorw clean --mode module -p module=entry@default -p product=default -p buildMode=release assembleHap --no-daemon`（补充） | `BUILD SUCCESSFUL in 16 s 992 ms`；34 tasks（33 executed / 1 up-to-date）；`buildMode=release`、`debug=false`；unsigned | **0** |
| 7 | `sha256sum` / `stat`（release 产物） | `1602110da9213ffe0520e83d60836e96f964d97f339c571a21dd8239f735bd03`；1,616,146 B（`1.6M`）；13 条目 | **0** |
| 8 | `unzip -p <hap> module.json` / `pack.info` | `versionName=1.0.0`、`versionCode=1000000`、`bundleName=com.example.yaocore`、`compileSdkVersion=26.0.0.105` | **0** |
| 9 | HAP 内容扫描 | `MockGatewayService`/`MockBleProvisioningClient`/`ohosTest`/`service/mock` 均 **0 命中**；无 `META-INF`/签名材料 | **0** |

### 5.3 产物清单

| 产物 | 路径 | 大小 | SHA-256 | 模式 | 签名 | 说明 |
|---|---|---|---|---|---|---|
| 任务指定默认构建 | 同路径（构建时；现已被 release 构建覆盖） | **4,597,005 B** | `1983ea22f54305c4817106e9bfc55122f42636071caceacca6f3dd3b219839c7` | `debug`（`module.json`） | 无 | 14 条目；含 `ets/sourceMaps.map`；证明 clean build 可成功，**不是发布候选** |
| 补充干净 release 构建 | `entry/build/default/outputs/default/entry-default-unsigned.hap`（当前工作区产物） | **1,616,146 B** | `1602110da9213ffe0520e83d60836e96f964d97f339c571a21dd8239f735bd03` | `release`（`module.json`） | 无 | 13 条目；无 source map；**建议作为后续签名/发布候选的构建方式** |
| 增量 release 构建（对比） | 同路径（已被覆盖） | 1,616,146 B | `be83926d8156ddb6468a81b7bc1ed8553f4eeb2247cb6c432f7cb673beda91a6` | `release` | 无 | 与干净构建同大小、不同哈希；证明构建非字节可复现 |

> 默认构建的 HAP 副本保存在本机 `/tmp/opencode/wp112/entry-default-unsigned-mandated.hap`（不提交、不作为发布资产）。当前 `entry/build/default/outputs/default/entry-default-unsigned.hap` 是补充 `buildMode=release` 干净构建的产物。两者都**未签名、不可安装/发布**。

### 5.4 可复现性边界

- **可复现**：源码 revision（`6cd9a88`）、依赖锁文件、工具链版本、构建命令、HAP 条目清单、功能/测试证据。
- **不承诺**：HAP 字节级一致。归档时间戳/打包元数据会产生不同 SHA-256；同一 release 代码的两次构建已实测同大小不同哈希。发布记录必须同时保存 commit、工具链、命令、大小与 SHA-256。
- **保留**：签名的最终 HAP、构建日志、`pack.info`、HAP 条目清单、SHA-256、release notes 与审批记录；构建目录被 `.gitignore` 忽略，不得只依赖工作树留存。
- **变更影响**：任何源码/构建配置/版本/签名配置变更都会使当前产物 SHA 与构建证据失效；需重新构建并重跑受影响测试。

### 5.5 构建相关发现

1. **默认构建为 debug 模式**：`hvigorw clean assembleHap` 未指定 buildMode 时产物 `"buildMode":"debug"`、`"debug":true`，含 source map。发布必须显式 `buildMode=release`，并验证 `module.json` 的 `buildMode`/`debug` 字段。
2. **release 构建通过但未启用混淆**：构建日志提示如需要混淆需配置 obfuscation；当前未配置。是否在 v1 启用混淆/裁剪属于发布硬化决策（B-09），需评估符号化/崩溃定位与回归；本任务不修改。
3. **API 兼容性 warning**：`RdbStoreAdapter` 使用 API 18 的 `ColumnType/TEXT/BLOB`，而 compatible 为 API 14；构建成功但 API 14 运行时未验证，需设备/兼容性验证或风险接受（B-09）。
4. **未签名**：`signingConfigs: []`；构建日志 `Will skip sign 'hos_hap'`。签名计划见 §6。
5. **Mock 生产排除**：release HAP 中 4 类测试替身字符串 0 命中；这是 HAP 级证据，不替代真实设备测试。

---

## 6. 签名计划（用户提供材料；本任务不执行签名）

### 6.1 当前状态

- `build-profile.json5`：`signingConfigs: []`；product `signingConfig: "default"` 指向未定义的配置。
- 构建日志：`Will skip sign 'hos_hap'. No signingConfigs profile is configured in current project.`
- 产物：未签名 HAP，不能安装到设备，也不能作为应用市场/正式分发物。
- 本任务**未使用、未请求、未写入任何证书、私钥、Profile、密钥库或口令**。

### 6.2 用户需提供的材料（不写入仓库）

| 材料 | 用途 | 注意事项 |
|---|---|---|
| HarmonyOS 开发者账号 / AGC 应用记录 | 创建应用、证书与 Profile | bundleName 必须与 `AppScope/app.json5` 最终值一致 |
| 发布证书（`.cer`） | 签名身份 | 有效期、证书链、与 Profile 匹配 |
| 发布 Profile（`.p7b`） | 声明 bundleName、证书、设备/发布类型 | 发布 Profile 与调试 Profile 不同；设备调试需包含 UDID |
| 密钥库（`.p12`）与 key alias | 私钥存储 | **不得提交**；口令用本地秘密管理/环境变量，不进入日志 |
| 签名工具/DevEco Studio | 生成/校验签名 | 以所在 SDK/IDE 实际提供的能力为准；本机 SDK 未暴露 `hapsigntool` |

### 6.3 签名步骤（授权后由用户/授权签名人执行）

1. **冻结身份**：按 §4.4 的用户决定确认最终 bundleName、vendor、versionName、versionCode；同步 AGC 应用记录与 Profile。若沿用旧公开身份，versionCode 必须 >1000000。
2. **配置签名**：在 DevEco Studio 的 Signing Configs 或本地 `build-profile.json5` 中配置证书、Profile、密钥库、alias 与口令引用；`signingConfigs` 的 `name` 与 product 的 `signingConfig` 对齐。不要把真实口令写入受版本控制的文件。
3. **干净构建**：
   ```bash
   hvigorw clean --mode module -p module=entry@default -p product=default -p buildMode=release assembleHap --no-daemon
   ```
   确认日志不再出现 `Will skip sign`，并记录实际签名产物文件名。
4. **产物校验**：记录签名 HAP 路径、大小、SHA-256；检查 `module.json` 的 bundleName/version/buildMode；确认签名材料存在（以实际签名格式为准）。
5. **安装 smoke**：通过 SDK 的 `hdc install` 安装到目标设备/模拟器；确认启动、版本、权限提示、4 Tab/核心页面可用。`hdc` 当前不在 PATH，需使用 SDK toolchains 中的 `hdc` 或配置 PATH。
6. **升级验证**：若采用 §4.4 选项 A（沿用 `io.github.quirkybrain.yaocore`），必须对已公开的 1.0.0 执行更高 versionCode 的覆盖安装验证，并检查旧数据/行为；若采用选项 B（新身份），记录旧公开应用无法升级及产品身份说明；**不得再标记为“N/A（无公开旧版本）”**。若曾在内部分发同 bundleName 构建，同样必须验证升级。
7. **证据归档**：签名配置摘要（不含秘密）、构建日志、HAP SHA-256、安装日志、设备型号/OS/API、截图/录屏。

### 6.4 签名后复验项

- [ ] 签名成功日志；无 `Will skip sign`。
- [ ] HAP 签名材料/签名校验通过（使用签名环境提供的工具；不得凭文件名判断）。
- [ ] 证书/Profile 未过期，bundleName 与最终包标识一致。
- [ ] 安装成功；启动无崩溃；版本号与 `AppScope/app.json5` 一致。
- [ ] `buildMode=release`、`debug=false`；无调试 source map/调试开关。
- [ ] 权限提示（INTERNET / ACCESS_BLUETOOTH）符合预期；无多余敏感权限。
- [ ] 签名后 HAP 的 SHA-256、大小、路径写入发布证据；与未签名产物分开保存。
- [ ] 若签名后仍需改代码/版本/包名：重新走构建、签名与全部受影响复验，不复用旧证据。

### 6.5 秘密与最小权限

- 证书私钥、密钥库口令、Profile 口令只存放在用户控制的秘密存储/本机，不进入 Git、Artifact、日志、截图或聊天记录。
- 签名环境建议使用专用账号/最小权限；发布后按组织策略轮换/吊销不再使用的证书。
- 本任务的所有日志与 Artifact 均不含签名秘密。

---

## 7. 发布通道与远端策略

### 7.1 当前事实

| 项 | 值 |
|---|---|
| `origin` | `https://github.com/Quirkybrain/YaoCore.git` |
| 本地 `main` | `a6f6558`（`init: initialize YaoCore HarmonyOS project workspace`） |
| `origin/main`（本地跟踪引用） | `7d6f4c9`（`Initial public release of YaoCore`；公开 YaoCore 1.0.0，`io.github.quirkybrain.yaocore`、versionCode 1000000、Apache-2.0 + NOTICE；见 §4.4） |
| merge-base | **空**（历史不相关） |
| 集成分支 | `feat/yaocore-app @ b716207`（仅本地；未推送） |
| 当前任务分支 | `task/wp-116-release-fix @ f1fbe0d` |
| tag | 无 |
| Git 策略 | `main_merge_mode: review_request_when_remote`；有 remote 时禁止本地 main merge handoff；默认 `--no-ff`；托管主分支需 PR/MR |
| 本任务远端操作 | **无**（未 fetch/push/PR/MR/merge/tag） |

> `origin/main` 为本地跟踪引用；本任务未 `git fetch`。若远端已变化，需在授权后重新核对。`origin/main` 不只是“旧历史”，而是公开 YaoCore 1.0.0；远端选择必须与 §4.4 的身份/许可证决定一起评估。

### 7.2 处理选项（远端通道 A–E；独立于 §4.4 的身份/许可证 A/B/C）

| 选项 | 做法 | 优点 | 风险/约束 | 授权 |
|---|---|---|---|---|
| **A. 新远端仓库（推荐优先评估）** | 新建专用 App 仓库；将 `feat/yaocore-app` 作为初始 `main`（或先推 `release/1.0.0`/`next`）；配置保护分支、CI、PR/MR | 历史干净；不触碰原项目；升级/发布路径清晰 | 需用户创建仓库/确定可见性/迁移 issue/文档；新远端写操作 | 用户明确授权 + 仓库权限 |
| **B. 原远端新分支** | 在 `origin` 推送 `feat/yaocore-app` 为 `next`/`app-v1`；PR/MR 进入该分支；保留 `origin/main` 不动 | 不重写历史；可在原项目内评审 | 默认分支仍是旧项目；用户/克隆者可能混淆；需平台分支保护与默认分支设置 | 用户授权 push + 分支保护配置 |
| **C. 替换 `origin/main`** | 强制推送新历史覆盖 `origin/main` | 单一 main | **破坏性**：丢失旧历史/链接/协作基线；覆盖公开 1.0.0 的 main、旧用户、许可证与来源声明；违反“不得强推掩盖分歧”的默认规范；需备份、协调与平台保护临时调整 | **高风险，默认不建议**；需用户书面授权与备份 |
| **D. 合并不相关历史到 `origin/main`** | `git merge --allow-unrelated-histories` 后 PR/MR | 保留旧历史与旧公开版本 | 大量冲突/无关文件；评审与回滚成本高；容易把旧项目内容带入发布；需明确新旧身份/许可证关系 | 需用户/架构决策；默认不建议 |
| **E. 仅本地归档，不发布** | 本地 tag/产物留存；不 push、不发布 | 零远端风险；适合继续设备验证 | 无公开交付；不是 release | 当前默认安全状态 |

**远端通道建议**：优先 A（新远端仓库）；若必须留在原仓库，选 B。C/D 只有在用户明确接受历史风险并完成备份后才可评估。无论 A/B，最终 `main` 必须由平台保护、要求独立评审与必需 CI；`release/1.0.0`（如使用）从冻结基线创建，只接纳经验证的发布变更。以上仅是远端通道建议，不替代 §4.4 的身份/许可证决定。

### 7.3 发布通道选项

| 通道 | 适用 | 前置 | 备注 |
|---|---|---|---|
| **本地/受控产物分发** | 内部测试、设备验证 | 签名 HAP、校验和、安装说明 | 不等于公开市场发布；需控制访问 |
| **GitHub Releases（或等价托管 Release）** | 开源/测试版分发 | 新远端策略（A/B）、tag、release notes、签名产物、SHA-256 | 需用户授权 push/tag；应用市场之外的分发仍需签名与合规 |
| **华为应用市场 / AGC** | 公开上架 | 开发者实名/应用记录、签名、隐私政策、商店素材、审核 | 审核周期与合规要求以渠道最新规则为准；本任务未准备商店素材 |
| **企业/内部渠道** | 组织内分发 | 企业签名/分发资质、受控设备 | 由组织策略决定；不得假定可用 |

> 发布通道是产品/合规决策，本计划只列选项，不代为选择。`main_merge_mode: review_request_when_remote` 意味着一旦配置 remote，本地 main merge 被守卫拒绝；必须走托管 PR/MR。

### 7.4 远端/平台检查单（授权后）

- [ ] 用户书面选择 A/B/C/D/E，并指定目标仓库/分支/可见性。
- [ ] 备份原 `main` 与关键 tag；确认无人依赖将被改写的历史。
- [ ] 推送集成分支（或新仓库初始分支）；不 push 当前 task 分支作为发布分支。
- [ ] 保护 `main`/发布分支：禁止直接 push/强推；要求 PR/MR、至少一次独立评审、必需 CI、讨论解决。
- [ ] CI 覆盖：`ohpm install`、release 构建、codelinter、host、crosscheck、simulator、layering、fixture、i18n、triage；设备矩阵作为人工证据。
- [ ] 配置 CODEOWNERS（如适用）；确认 release 权限最小化。
- [ ] 记录 PR/MR 链接、CI 结果、审批记录、合并提交；更新 Checkpoint。
- [ ] tag/发布操作单独授权；不得把“合并到 main”当成“对外发布”。

---

## 8. 回滚与保留

### 8.1 回滚触发条件（P0 定性；P1/P2 阈值提案待用户批准）

| 级别 | 触发示例 | 动作 |
|---|---|---|
| **P0 立即回滚/停止发布** | 无法安装或启动；崩溃/ANR 阻塞主流程；家庭/房间/设备控制核心链路失效；秘密泄露/认证绕过/数据丢失；商店合规拒绝 | 停止 staged rollout/下架当前版本；保留现场证据；发布更高 versionCode 的修复；必要时吊销/轮换证书与密钥 |
| **P1 快速修复** | 关键设备类型控制失败；BLE/LAN 主路径高失败率；严重 i18n/布局问题影响使用；性能显著回退 | 评估热修复；若渠道支持，回退到上一稳定版本；否则尽快发布补丁 |
| **P2 计划修复** | 非核心 UI/A11y 缺陷；低频兼容问题；文档错误 | 记录并排入维护轮；不阻断当前版本，但需用户接受 |

#### 8.1.1 P1/P2 可量化阈值提案（**需用户批准后生效**）

> 以下数值是**提案**，不是已批准策略；**批准前 P1/P2 仍按上表定性条件判断，且不构成回滚授权**。P0 仍按上表立即处置；任何指标与 P0 定性条件冲突时，以 P0 为准。

| 指标 | P0 立即处置（现行定性，供对照；不以数值替代） | P1 快速修复/停止扩大 rollout | P2 计划修复 | 观察窗口 / 最小样本 |
|---|---|---|---|---|
| 安装失败率 | 任何构建无法安装/启动 | >2%（且 ≥100 次安装尝试），或同一设备型号集中失败 | 0.5%–2% | 发布后 24h；按渠道/设备分群 |
| 崩溃率（crash sessions / sessions） | >5% 或核心路径崩溃循环 | >1.0%，或 crash-free sessions <99.0%（≥1000 sessions） | 0.5%–1.0% | 24h 与 7d |
| ANR 率 | >1.0% 或 ANR 阻塞核心流程 | >0.5%（≥1000 sessions） | 0.2%–0.5% | 24h 与 7d |
| 核心控制失败率（`door`/`light`/`ac`；排除用户取消与不支持类型） | ≥20%，或某支持设备类系统性 100% 失败 | >5%（≥200 条命令） | 1%–5% | 发布后 7d |
| BLE 配网失败率 | 100% 失败或无法完成配网 | >15%（≥50 次尝试） | 5%–15% | 发布后 7d |
| LAN 控制 p95 | 不可用/持续超时 | >3,000 ms，或 >3× 同设备/同网络基线（≥200 样本） | 1,500–3,000 ms，或 2–3× 基线 | 发布后 7d；基线须真机测量，不得使用 `MOCK_ONLY` |
| 用户报告的核心路径失败率 | 无法安装/启动/控制 | ≥5% 活跃用户报告（≥100 活跃用户） | 1%–5% | 发布后 7d |

**执行规则**：

- 达到 P1 阈值：停止扩大 rollout，评估热修复；渠道支持时回退到上一稳定版本（仅当存在同 bundleName 的上一版本；见 §4.4-A/B）。
- 达到 P2 阈值但未达 P0/P1：记录并排入维护轮，需用户接受；不阻断当前版本。
- 样本不足：低于最小样本时不得仅凭比例触发 P1/P2；由发布负责人结合定性证据判断并记录。
- 阈值经用户批准后写入发布 Gate 记录；任何修改需用户重新批准。

> 若采用 §4.4-A，旧公开 1.0.0 可作为上一公开版本参考；若采用 B/C，则没有同 bundleName 的上一公开版本可回退，P0/P1 的实际动作是停止发布/下架 + 热修复。若渠道支持 staged rollout，先小比例发布并监控。

### 8.2 回滚步骤（发布后）

1. **冻结**：停止继续上传/扩大 rollout；保留发布产物、日志、商店记录与用户反馈。
2. **判定**：确认是产品缺陷、签名/安装问题、渠道配置还是环境问题；记录根因与影响范围。
3. **遏制**：按渠道能力停止发布/下架/回退到上一版本；通知用户/支持团队；不隐藏失败证据。
4. **修复**：在新分支/新任务修复；重跑受影响测试与设备 smoke；递增 versionCode；重新签名。
5. **重新发布**：走同一发布 Gate；不得复用失效证据；记录新产物 SHA-256 与审批。
6. **复盘**：更新维护计划/风险登记/检查单；必要时新增 ADR 或测试用例。

### 8.3 产物与证据保留

- **源码**：发布 tag 永久保留；不得移动/覆盖对外发布 tag；修复用新 tag。
- **产物**：保留签名 HAP、未签名对照产物、`pack.info`、构建日志、SHA-256 清单；建议至少保留最近两个公开发布及当前 RC，具体期限按项目/公司策略。
- **证据**：测试日志、设备矩阵、签名校验、安装 smoke、商店审核/发布记录、回滚记录；访问受控，不含秘密。
- **分支**：发布分支/远端 main 受保护；不得用 force push 改写对外发布历史；删除分支/tag 需单独授权。
- **数据**：v1 为本地数据；本次无服务端迁移。未来若引入数据库 schema 变更，必须提供备份/迁移/回滚方案后才可发布。

### 8.4 回滚权责

- 回滚决策：用户/项目所有者（或授权的发布负责人）。
- 执行：`release-engineer` 准备步骤与证据；`repository-manager` 处理分支/tag/远端操作；签名/渠道操作由授权人执行。
- 本任务不执行任何回滚/远端操作；本计划仅为授权后的操作预案。

---

## 9. 发布 Gate 判据

### 9.1 Go / No-Go 判据

| ID | 判据 | 证据形式 | 当前状态 |
|---|---|---|---|
| **R-G01** | **代码证据基线**已确认且工作树干净；**最终 release revision/tag** 已冻结并指向该 commit | `git status`、commit SHA、tag | **PARTIAL（代码证据基线 PASS：TEST-002 @ `e74a181`；最终 release revision/tag 未冻结；待 B-06 后创建 tag）** |
| **R-G02** | 许可证已确定并提交 `LICENSE`/`NOTICE`；依赖许可证核对完成；公开旧版本 Apache-2.0/NOTICE 关系已裁定 | LICENSE 文件、依赖清单、法律/owner 确认、§4.4 决定 | **FAIL（B-01；待 §4.4 A/B/C 决定）** |
| **R-G03** | bundleName/vendor/versionName/versionCode 最终确认并与 HAP 一致；升级路径符合 §4.4 决定 | `AppScope/app.json5`、HAP `module.json`/`pack.info`、用户确认 | **PENDING（B-06；待 §4.4 A/B/C 决定）** |
| **R-G04** | CHANGELOG + 用户可读 release notes + 已知限制；评审/签核完成 | `CHANGELOG.md`、release notes、README 链接、评审记录 | **PARTIAL（草案已产出 @ `63d2235`；待评审/签核，B-07）** |
| **R-G05** | 冻结 revision 上干净 `buildMode=release` 构建成功；产物大小/SHA 记录 | 构建日志、HAP、`module.json`、SHA-256 | **CONDITIONAL PASS（本次 probe；身份/版本冻结后需重建）** |
| **R-G06** | 签名成功；签名校验通过；安装 smoke 通过 | 签名日志、证书/Profile 校验、`hdc install` 日志、设备信息 | **BLOCKED（B-02）** |
| **R-G07** | 设备矩阵/用户验收完成，或用户书面接受限定范围 | BLK-01..08 证据；用户签核 | **BLOCKED（B-03）** |
| **R-G08** | GAP-AC-01..03 已接受或修复 | 用户书面决定；若修复，相关测试/复审 | **PENDING（B-04）** |
| **R-G09** | D-030/R4-01/PORT-LOC-01/i18n/NFR/ACK MOCK_ONLY/test lint/unsigned 等风险逐项签核；B-09 构建硬化/API 14 兼容性决策完成 | 风险接受记录、发布 Gate 记录、B-09 决策/验证记录 | **PENDING（B-08/B-09）** |
| **R-G10** | 远端/通道策略授权；公开旧版本用户/Release/来源声明已评估；保护分支与 CI 就绪；无强推/历史改写 | 用户授权、§4.4/§7.2 决策记录、平台设置截图/链接、CI 记录 | **UNAUTHORIZED（B-05；待 §4.4 A/B/C + §7.2 A-E）** |
| **R-G11** | 回滚计划、保留策略、责任人与沟通路径就绪；P1/P2 阈值经用户批准 | 本计划 §8；发布负责人确认；阈值签核 | **PARTIAL（计划；§8.1.1 阈值提案待用户批准）** |
| **R-G12** | 无未关闭 P0/P1；无未接受 High/Critical；文档/证据与 revision 一致 | 评审/测试/风险记录 | **PASS（代码级）；设备/发布侧待定** |
| **R-G13** | 发布证据归档：产物、SHA、测试、签名、安装、审批、发布记录 | 证据目录/清单/链接 | **PARTIAL** |

> **R-G01 口径**：`PASS` 仅指**代码证据基线**（TEST-002 @ `e74a181`；产品代码至本修订未变）。**最终 release revision/tag 未冻结**，当前无 tag；必须在 B-06/B-09 关闭后创建 annotated tag，并在该 revision 上重建、签名、复验。不得把 `e74a181` 或 `6cd9a88` 写成最终发布 commit。

**规则**：R-G01..R-G13 全部 `PASS`，或对未满足项有用户书面、按范围的明确接受，才可给出 `READY_FOR_PUBLISH_AUTHORIZATION`。任何 P0/安全问题、未签名产物、许可证未定、未授权远端操作均为 **No-Go**。

### 9.2 本任务明确未授权事项

- 不 push、不 force push、不 fetch/pull（本任务未执行）、不创建/删除远端分支、不创建/删除 tag。
- 不创建 PR/MR，不合并 `main`/发布分支，不 rebase 共享历史。
- 不使用签名证书/私钥/Profile，不生成签名 HAP，不安装到设备。
- 不上传应用市场、不发布 GitHub Release、不做任何远端写操作。
- 不修改代码、版本号、bundleName、签名配置、测试/契约/`input/`。
- 不做破坏性数据迁移、不引入停机/成本性 rollout。

### 9.3 停止条件

- 任一 R-G 判据失败且无书面接受。
- 用户未授权远端/签名/发布操作。
- 发现新的 P0/High 安全、数据或兼容性问题。
- 发布 revision 与证据 revision 不一致，或工作树不干净。
- 渠道/商店要求（隐私、合规、素材）未满足。

---

## 10. Release Notes / CHANGELOG 输入（草案，待 `technical-writer` 定稿）

发布前至少需要以下内容；不得直接复制未经核实的营销表述：

1. **产品与版本**：YaoCore（爻构）v1.0.0；HarmonyOS NEXT App；目标设备/API 范围；**公开旧版本（origin/main 1.0.0）对照与 §4.4 A/B/C 最终选择**（不得再写“首次发布/当前无公开旧版本”）。
2. **本次内容**：v1 代码级交付；家庭/房间/设备/场景/设置能力；支持的设备类型与只读降级范围。
3. **验证边界**：Host/契约/仿真器/构建证据；真实 BLE/LAN/TLS/云/硬件/视觉/性能未验证或由用户执行；不得写成“已通过设备验收”。
4. **已知限制**：P-HMAC 无机密性；TLS/固件 v2.1 依赖；云 Token 手工；家庭同步为接触式收敛；部分 UI DEFERRED；GAP-AC-01..03；D-030/R4-01；PORT-LOC-01；i18n 残余；测试 lint/覆盖率缺口；未签名构建（发布前应关闭）；API 14 运行时/混淆裁剪（B-09）。
5. **安装/升级**：签名要求、设备/OS 要求、首次安装/升级说明；未签名包不可安装；若选择 §4.4-A 必须说明从公开 1.0.0 升级与 versionCode 要求；若选择 B/C 必须说明独立应用身份与旧用户无法升级。
6. **安全与隐私**：权限（INTERNET、ACCESS_BLUETOOTH）、秘密处理、DEV-ONLY 仿真器拒收；隐私政策链接（如渠道要求）。
7. **许可证**：项目许可证与第三方声明；按 §4.4 A/B/C 记录旧公开版本 Apache-2.0/`NOTICE` 的继承、独立或迁移关系（待 B-01 关闭）。
8. **反馈/支持**：问题渠道、日志脱敏要求。

`CHANGELOG.md` 建议采用 Keep a Changelog 风格或项目既有约定；v1.0.0 标注初始发布，后续按 Added/Changed/Fixed/Security 分类。最终文案需与 README、ACCEPT-001、TEST-002 的证据边界一致。

---

## 11. 本任务验证证据

### 11.1 输入 pin 校验

对 handoff `inputs` 的 10 个文件逐项计算 SHA-256，与 `state/handoffs/wp-112-release-plan.json` 比较：**10/10 一致**。

| 输入 | 结果 |
|---|---|
| `state/project-state.md` | OK |
| `artifacts/65-acceptance/acceptance-report.md` | OK |
| `artifacts/60-testing/testing-stage-report.md` | OK |
| `artifacts/80-maintenance/maintenance-plan.md` | OK |
| `README.md` | OK |
| `config/project.md` | OK |
| `AppScope/app.json5` | OK |
| `build-profile.json5` | OK |
| `config/git-policy.json` | OK |
| `docs/git-collaboration.md` | OK |

### 11.2 复跑矩阵（构建探针 revision `6cd9a88`）

| # | 命令 | 结果 | Exit |
|---|---|---|---|
| 1 | `entry/src/test/run-host-tests.sh` | `1..697`；tests 697 / pass 697 / fail 0 / skipped 0；≈3,819.8 ms | **0** |
| 2 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | `files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0`；`PASS` | **0** |
| 3 | `no_proxy=127.0.0.1,localhost NO_PROXY=127.0.0.1,localhost PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tools.simulator.test_gateway_contract -v` | `Ran 20 tests`；`OK`（HTTP+TLS） | **0** |
| 4 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py` | `hard checks: ALL PASS`；14 条既有 `FINDING` | **0** |
| 5 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/test_check_layering.py` | `Ran 27 tests`；`OK` | **0** |
| 6 | `PYTHONDONTWRITEBYTECODE=1 python3 entry/src/test/i18n/check_i18n.py --strict-ui` | `blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16` | **0** |
| 7 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/i18n/triage_legacy.py --check` | `615 rows`；`OK: CSV matches computed triage` | **0** |
| 8 | `codelinter -c code-linter.json5 -p default .` | `Defects: 25; Errors: 0; Warns: 25; Suggestions: 0` | **0** |
| 9 | `ohpm install` | 完成 | **0** |
| 10 | `hvigorw clean assembleHap --no-daemon` | `BUILD SUCCESSFUL`；默认 debug 产物 | **0** |
| 11 | `hvigorw clean --mode module -p module=entry@default -p product=default -p buildMode=release assembleHap --no-daemon` | `BUILD SUCCESSFUL`；release 产物 | **0** |

> **TEST-002 第 6 项说明**：TEST-002 §2 的第 6 项为仿真器契约套件；本任务已在 `6cd9a88` 复跑 **20/20（HTTP+TLS）**。TEST-002 的第 4 项 host、第 7 项 layering、第 5 项 crosscheck、第 8 项 fixture、第 9 项 i18n、第 10 项 triage 亦已复跑；第 11 项 ACK p95 未复跑（仍为 `MOCK_ONLY`，且不用于 NFR 验收）；第 12 项 ohosTest 编译未复跑；第 13 项 HAP Mock 排除已在 release 产物上复检（0 命中）；第 14 项设备边界保持 `BLOCKED`。

### 11.3 工作区与范围

- `git status --porcelain` 在文档写入前为空；构建产物位于 gitignored `entry/build/**`。
- `git diff --quiet e74a181..HEAD -- entry/src/main tools entry/src/test entry/src/ohosTest` exit 0；产品代码/测试内容未变。
- 本任务只写 `artifacts/85-release/` 与 `docs/`；未改代码、版本号、签名配置、测试/契约/`input/`。
- 未执行：push、PR/MR、merge、rebase、tag、fetch、签名、安装、设备矩阵、市场发布。
- 未执行：ACK p95 复测、ohosTest 复跑、`.app` 打包、许可证法律审计、真实 BLE/LAN/TLS/云/硬件/视觉/fps 验证。

### 11.4 明确非声明（Non-claims）

- 不声明“可安装”“签名完成”“可发布”“对外发布”“已推送”。
- 不声明产品验收、设备验收、NFR 4.1/4.2/4.3 达标。
- 不声明真实 BLE/LAN/TLS/云/视觉/A11y/60-120fps 通过。
- 不把 `MOCK_ONLY`（ACK p95）写成验收数据。
- 不把 `check_layering` 的 0 violation 写成 100% 端口位置合规（`PORT-LOC-01` 仍 OPEN）。
- 不把 release-mode 构建成功写成签名/安装成功。
- 不把 `com.example.yaocore` 写成已确定的正式发布包名。

### 11.5 修订验证（`wp-116-release-fix`）

> 本节由 `wp-116-release-fix` 在 `task/wp-116-release-fix @ f1fbe0d`（修订提交前）执行；不改变 §11.2 的原始构建/测试证据。

| # | 检查 | 结果 |
|---|---|---|
| 1 | handoff `wp-116` 的 4 项输入 SHA-256（基线 `f1fbe0d`） | **4/4 一致**（review `19b3cd2c…`、release-plan `3e2cd615…`、checklist `d1ca3caf…`、acceptance `794fd588…`）；其中 release-plan/checklist 是本次修改目标，修订后哈希按预期变化 |
| 2 | 只读复核 `origin/main` | `7d6f4c9`：`io.github.quirkybrain.yaocore` / `YaoCore` / 1.0.0 / 1000000；Apache-2.0 + LICENSE + NOTICE；与 §4.4 记录一致 |
| 3 | 产品代码未变 | `git diff --quiet e74a181..HEAD -- entry/src/main tools entry/src/test entry/src/ohosTest build-profile.json5 AppScope/app.json5 oh-package.json5 entry/oh-package.json5 hvigorfile.ts` exit 0 |
| 4 | 跨文档 B 编号/章节引用 | B-01..B-09 连续；plan↔checklist 的 §4.4/§7.2/§8.1.1/§9.1 引用一致（见提交前检查记录） |
| 5 | 链接检查 | 发布计划/检查单中的相对链接（checklist→plan）存在；0 broken |
| 6 | 越界肯定词扫描 | 0 命中（发布/签名/验收/就绪的越界肯定词均未出现；否定/禁止语境亦已改写） |
| 7 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | `files=221 violations=0 exceptions_used=6 ...`；PASS，exit 0 |
| 8 | `entry/src/test/run-host-tests.sh` | `1..697`；697/697 pass；exit 0 |
| 9 | 工作树/提交范围 | 仅修改 `artifacts/85-release/` 与 `docs/`；未改代码/版本/签名/测试/契约/`input/` |

---

## 12. 追溯

| 项 | 映射 |
|---|---|
| 发布目标/不发布 | `state/project-state.md` §Release 准备；用户 2026-10-18 指令 |
| 验收就绪 | `artifacts/65-acceptance/acceptance-report.md`（ACCEPT-001） |
| 测试证据 | `artifacts/60-testing/testing-stage-report.md`（TEST-002 @ `e74a181`，代码证据基线）；§11.2（`6cd9a88` 构建探针）；§11.5（本修订验证） |
| 维护/设备矩阵 | `artifacts/80-maintenance/maintenance-plan.md` §4、§5 |
| 文档/限制 | `README.md`（README-001 v1.3）；`CHANGELOG.md` 与 `docs/release-notes-v1.0.0.md` 草案 @ `63d2235`；MAINTENANCE-PLAN-001 v1.1 |
| 公开旧版本 | `origin/main` @ `7d6f4c9`（`io.github.quirkybrain.yaocore`、1.0.0/1000000、Apache-2.0 + NOTICE）；§4.4 |
| 复审输入 | `artifacts/70-review/t26-release-review.md`（T26-RELEASE-REVIEW；F-01..F-06） |
| Gate | G-014（implementation）、G-015（review）、G-016（testing）、G-017（acceptance readiness）、G-018（documentation） |
| 版本/构建 | `AppScope/app.json5`；`build-profile.json5`；HAP `module.json`/`pack.info` |
| Git 策略 | `config/git-policy.json`；`docs/git-collaboration.md`；`config/git-policy.default.md` |
| 发布检查单 | `docs/release-checklist.md`（本任务；修订 `wp-116-release-fix`） |

---

*RELEASE-001 结束。本文件只完成发布准备评估；`NOT_READY` 不授予发布授权。所有远端、签名、安装、发布与用户验收动作需显式授权并由授权人执行。*
