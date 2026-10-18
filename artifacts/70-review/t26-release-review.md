# Release 准备资产独立复审（T-26 / wp-115）

- **Artifact ID**: T26-RELEASE-REVIEW
- **Producer**: agent:quality-reviewer
- **Role**: quality-reviewer（独立复审；未参与 `wp-112-release-plan` 或 `wp-114-release-notes` 的编写）
- **Task**: `wp-115-release-review`（HANDOFF `state/handoffs/wp-115-release-review.json`）
- **Reviewed revision**: `63d22354461f51c686e6cd721474e352990d779f`（`task/wp-114-release-notes`；handoff `base_commit`；parent `b716207eee7ac07fe3b08edba9f9e193cb38f2c8`）
- **Release preparation base**: `6cd9a88d0fdc1b08cc6ffca233c12c41df737519`（RELEASE-001 的证据基线；`560d08a` 为其文档提交）
- **Review scope**: `artifacts/85-release/release-plan.md`（RELEASE-001）、`docs/release-checklist.md`（RELEASE-CHECKLIST-001）、`CHANGELOG.md`、`docs/release-notes-v1.0.0.md`、`README.md` 发布小节；以 ACCEPT-001、TEST-002、README 既有验证口径、Git 策略为权威输入
- **Workflow**: STANDARD / GATED_AUTO
- **Date**: 2026-10-18
- **Verdict**: **`CHANGES_REQUIRED`（仅限发布准备资产；release 仍为 `NOT_READY`，不是发布批准）**
- **Status**: COMPLETE

> **结论先行**
>
> 1. **数字与构建事实基本可信**：versionName/versionCode、bundleName/vendor、SDK/API、HAP 路径/大小/SHA-256、release 与 debug 两种构建的区分、host 697/697、crosscheck 66/66、仿真器 20/20、fixture 27/27、layering 221 files / 0 violation / 6 exceptions、i18n 0 blocking / 0 missing、triage 615 行，均与当前仓库/实际复验一致。
> 2. **发布状态表述诚实**：文档一致使用 `NOT_READY`、未签名、未发布、未验收、许可证 TODO；未发现“已发布/已签名/已验收/生产就绪”等越界肯定表述；签名与密钥纪律、远端写授权边界总体清晰。
> 3. **但发现 1 个 High + 3 个 Medium 的发布资产缺陷**：`origin/main` 上已有一个公开的 YaoCore 1.0.0（`io.github.quirkybrain.yaocore`、versionCode 1000000、Apache-2.0 + NOTICE），而 RELEASE-001、release notes 与 checklist 的“首次发布/当前无公开旧版本”表述及 B-01/B-06/B-05 分析未把它纳入；B-07 的当前状态在 RELEASE-001/checklist 中仍是“无 CHANGELOG/Release Notes”，与 `63d2235` 已产出的草案矛盾；R-G01/1.1.1 把“代码证据基线”写成“发布 revision 已冻结”；B-01..B-08/§7 的 No-Go 清单未覆盖 checklist 1.2.6 的构建 warning / 混淆裁剪决策。
> 4. **因此本轮不能给 PASS**：发布准备资产的状态与门禁完整性需要修正后再审。该结论**不否定代码、测试或 Gate 证据**，也不授予 release、签名、远端或用户验收任何权限。

---

## 1. 范围、revision、输入与独立性

| 项 | 本次结论 | 证据 |
|---|---|---|
| 仓库 / 分支 | `/home/quirkybrain/code/harmony-projects/YaoCore`；`task/wp-114-release-notes` | `git branch --show-current` |
| Reviewed HEAD | `63d22354461f51c686e6cd721474e352990d779f` | `git rev-parse HEAD` |
| Revision / parent | reviewed `63d2235`；release-plan 证据基线 `6cd9a88`；handoff parent `b716207` | `git rev-parse`；`git log --oneline -5` |
| 变更规模 | `6cd9a88..63d2235` 共 7 个路径，`+1274 / -5`；其中发布文档 5 个路径 `+1088 / -5`，另含 `artifacts/90-integration/integration-report.md` 与 `state/reports/wp-113-merge-report.md` 的合并证据 | `git diff --stat 6cd9a88..63d2235` |
| 输入完整性 | handoff 的 **7/7** 个输入 SHA-256 与文件实算一致 | Python `hashlib.sha256` 对照 handoff |
| 独立声明 | 未参与 RELEASE-001 / RELEASE-CHECKLIST-001 / CHANGELOG / release notes / README v1.2 的编写；未编辑任何被审文件；唯一写入为本报告 | 本任务 `writes` / `commit_paths` 仅 `artifacts/70-review/` |
| 授权边界 | 未 push、未 fetch、未 pull、未创建/修改/删除分支或 tag、未签名、未安装、未发布；`git ls-remote` 仅为只读远端引用查询 | 见 §2、§6 |
| 明确排除 | 设备/真实 BLE/LAN/TLS/云/硬件/视觉/fps 验收；实际签名与安装；应用市场/远端发布；法律级许可证审计；HAP 重新构建；codelinter / 完整构建日志重跑 | 见 §6 |

**审核限制**：本次没有重新执行 clean build 或 codelinter；当前 `entry/build/default/outputs/default/entry-default-unsigned.hap` 是既有 release-mode 构建产物，`/tmp/opencode/wp112/entry-default-unsigned-mandated.hap` 是既有 debug-mode 备份。构建类数字与 TEST-002 / RELEASE-001 的记录交叉核对，未以本次重构建替代。设备、签名、远端与用户验收均未执行。

---

## 2. 独立复验矩阵（cwd = 仓库根，2026-10-18 实际执行）

| # | 命令 / 检查 | 本次实测 | 退出码 |
|---|---|---|---|
| 1 | `git log --oneline -5` | `63d2235`、`b716207`、`40fe2a8`、`560d08a`、`6cd9a88` | 0 |
| 2 | `git diff --stat 6cd9a88..63d2235` | 7 files changed, 1274 insertions(+), 5 deletions(-) | 0 |
| 3 | `sha256sum entry/build/default/outputs/default/entry-default-unsigned.hap` | `1602110da9213ffe0520e83d60836e96f964d97f339c571a21dd8239f735bd03`；`1,616,146 B`；13 entries | 0 |
| 4 | HAP `module.json` / `pack.info` 解析 | `buildMode=release`、`debug=false`、`bundleName=com.example.yaocore`、`versionName=1.0.0`、`versionCode=1000000`、`compileSdkVersion=26.0.0.105`、`compatible=14`、`target=26`；无 `META-INF` | 0 |
| 5 | `entry/src/test/run-host-tests.sh` | `1..697`；tests 697 / pass 697 / fail 0 / skipped 0；约 3.7 s | 0 |
| 6 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | `files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0`；PASS | 0 |
| 7 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py` | 66 `[PASS]` / 0 `[FAIL]`；`hard checks: ALL PASS`；14 条既有 `FINDING` | 0 |
| 8 | `no_proxy=127.0.0.1,localhost NO_PROXY=127.0.0.1,localhost PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tools.simulator.test_gateway_contract` | `Ran 20 tests`；`OK`（HTTP+TLS） | 0 |
| 9 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/test_check_layering.py` | `Ran 27 tests`；`OK` | 0 |
| 10 | `PYTHONDONTWRITEBYTECODE=1 python3 entry/src/test/i18n/check_i18n.py --strict-ui` | `blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16` | 0 |
| 11 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/i18n/triage_legacy.py --check` | `615 rows`；`OK: CSV matches computed triage; invariants pass` | 0 |
| 12 | zh-CN / en-US 资源 key parity（Python） | 各 26 keys；双向 missing 0；空值 0 | 0 |
| 13 | 文档相对链接检查（Python） | 5 个文档共 **49** 条相对链接；**0 broken** | 0 |
| 14 | 秘密/凭据模式扫描 | 未发现私钥块、AWS/GitHub/OpenAI 风格 token；文档只出现 `.cer`/`.p7b`/`.p12` 等材料名称，无秘密值 | 0 |
| 15 | HAP Mock 生产排除扫描 | `MockGatewayService` / `MockBleProvisioningClient` / `ohosTest` / `service/mock` 均 **0 命中**；release HAP 无 `sourceMaps.map` | 0 |
| 16 | 既有 debug HAP 备份核对 | `/tmp/opencode/wp112/entry-default-unsigned-mandated.hap`：`4,597,005 B`；`1983ea22f54305c4817106e9bfc55122f42636071caceacca6f3dd3b219839c7`；14 entries；`buildMode=debug`、`debug=true`、含 `ets/sourceMaps.map`；未签名 | 0 |
| 17 | `git rev-parse main origin/main` / `git merge-base main origin/main` | `main=a6f6558`；`origin/main=7d6f4c9`；merge-base **空**（历史不相关） | 0 |
| 18 | `git tag -l` / `git branch --points-at 6cd9a88` | tag 为空；无分支指向 `6cd9a88`（`feat/yaocore-app` 当前为 `b716207`） | 0 |
| 19 | `git remote -v` / `git ls-remote --heads origin` | `origin=https://github.com/Quirkybrain/YaoCore.git`；远端仅 `main=7d6f4c9` | 0 |
| 20 | 配置核对 | `AppScope/app.json5` 为 `com.example.yaocore` / `example` / `1.0.0` / `1000000`；`build-profile.json5` 为 `signingConfigs: []`、`compileSdkVersion/targetSdkVersion 26.0.0`、`compatibleSdkVersion 5.0.2(14)` | 0 |
| 21 | 工具链核对 | Node `v24.15.0`；ohpm `26.0.0.630`；hvigorw `6.26.8`；Java `21.0.12.1`；Python `3.12.3` | 0 |
| 22 | 设备边界核对 | `hdc` 不在 PATH；SDK 绝对路径 `hdc list targets` 返回 `[Empty]` | 0 |

**复验结论**：§2 的 22 项均实际执行并返回上述结果；host/crosscheck/仿真器/fixture/layering/i18n/triage/HAP 的关键数字与文档一致。第 18 项（tag/分支）暴露 F-03 的冻结状态问题；第 19 项与旧公开版本相关，配合 `git show 7d6f4c9` 暴露 F-01。未发现产品行为、测试断言或构建模式方面的失败。**未复现**的是：第二次 release 构建的 `be83926d…` 哈希（当前工作区只有 `1602110d…` 产物；报告已说明构建非字节可复现）、设备/签名/发布类证据。

---

## 3. 逐项结论

### 3.1 事实与数字（符合）

- **版本/标识**：`AppScope/app.json5` 为 `versionName=1.0.0`、`versionCode=1000000`、`bundleName=com.example.yaocore`、`vendor=example`；HAP `module.json` 与 `pack.info` 一致。文档将其标为“待冻结”，正确。
- **SDK/API**：`build-profile.json5` 为 `compileSdkVersion=26.0.0`、`targetSdkVersion=26.0.0`、`compatibleSdkVersion=5.0.2(14)`；HAP `module.json` 的 `compileSdkVersion=26.0.0.105`、`compatible=14`、`target=26`。文档区分“工程配置 26.0.0”与“实际构建 SDK 26.0.0.105”，正确。
- **HAP 路径/大小/SHA**：当前 HAP `entry/build/default/outputs/default/entry-default-unsigned.hap` 为 `1,616,146 B`、`1602110d…`、release mode、13 entries；debug 备份为 `4,597,005 B`、`1983ea22…`、debug mode、14 entries。两种 HAP 的区分正确，均未签名、不可安装。
- **构建模式**：默认 `clean assembleHap` 为 debug；发布候选必须显式 `buildMode=release`；当前工作区 HAP 为 release mode，`debug=false`，无 source map。文档与实测一致。
- **测试数字**：host `697/697`、crosscheck `66/66`、仿真器 `20/20`、fixture `27/27`、layering `221 files / 0 violation / 6 exceptions`、i18n `0 blocking / 0 missing / 73 warning / 16 hardcoded`、triage `615 rows`，全部与本次复验一致；host 耗时与报告略有差异（约 3.7 s vs 3.8 s），不构成数字不一致。
- **Mock 排除**：release HAP 4 类字符串 0 命中；无 `META-INF`/签名材料。文档未把“BUILD SUCCESSFUL”写成“可安装/可发布”，正确。

### 3.2 发布状态诚实性（符合；一处措辞需与许可证联动）

- 五份文档均明确 `NOT_READY`、未签名、未发布、未验收、许可证 TODO；未发现肯定式“已发布/已签名/已验收/生产就绪/已上架”等越界表述。
- RELEASE-001 §11.4、release notes §9、CHANGELOG 头部、README 发布小节均有 non-claims / 授权边界；签名与密钥纪律明确“证书/Profile/密钥库/口令不入库、不写日志、由用户/授权签名人提供”。
- **唯一措辞张力**：`README.md:3` 仍称“开源智能家居”，而 `README.md:381` 与 B-01 明确许可证 TODO；这属于既有 README 文案，不是本次新增，但在公开前应与 F-01 的许可证决定一起收口。

### 3.3 B-01..B-08 完整性（B-01/B-05/B-06 的旧公开版本分析缺失；B-07 状态陈旧；B-08 未覆盖构建 warning/混淆）

- **B-01**：当前树无 `LICENSE`/`NOTICE`，README TODO，`entry/oh-package.json5` license 为空——事实正确；但未纳入 `origin/main` 旧公开版本的 **Apache-2.0 + NOTICE**。见 F-01。
- **B-02**：`signingConfigs: []`、`Will skip sign`、未签名 HAP——正确；签名材料/重建/复验/安装 smoke 的关闭条件完整。
- **B-03**：ACCEPT-001 U-01..U-12 未执行、`hdc` target 空——正确；设备矩阵 BLK-01..08 与用户验收边界清晰。
- **B-04**：GAP-AC-01..03 未决——正确；接受或 bounded fix 的关闭条件清晰。
- **B-05**：`origin/main` 与本地 `main` 无 merge-base、`feat/yaocore-app` 未推送、无 tag、`main_merge_mode: review_request_when_remote`——均正确；但把 `origin/main` 仅描述为“旧项目/旧历史”，未分析其作为**公开 YaoCore 1.0.0** 的用户、版本、许可证与 Release 影响。见 F-01。
- **B-06**：`com.example.yaocore`/`example`/version 未冻结、默认 debug——正确；但未把 `origin/main` 旧公开版本的 `versionCode=1000000` 作为“已分发构建”纳入身份/升级路径分析。见 F-01。
- **B-07**：RELEASE-001/checklist 仍写“无 CHANGELOG/Release Notes”；`63d2235` 已有 CHANGELOG 与 release notes 草案——状态陈旧。见 F-02。
- **B-08**：D-030/R4-01/PORT-LOC-01/i18n/设备/ACK/NFR/test lint/unsigned 已列；但未列 checklist 1.2.6 的 **API 18 vs compatible 14 warning** 与 **混淆/裁剪决策**。见 F-04。
- **结论**：B-01..B-08 的“逐项关闭即可 No-Go 解除”不成立；至少需补 F-01/F-02/F-04 的信息或阻塞项。

### 3.4 检查单可执行性（总体良好；状态标注与回滚阈值需修正）

- 发布前/中/后步骤、责任人、证据形式齐全；签名、设备、远端、回滚、证据归档均有对应条目。
- push/PR/MR/tag/签名/发布授权边界清晰；§5 未授权事项与 §2.2 授权记录明确。
- 回滚触发条件 P0 可判定；P1/P2 的“高失败率/显著回退/低频兼容”缺少量化阈值，且计划自己写“建议阈值由用户批准”。见 F-06。
- 个别状态标注与前置条件矛盾：1.2.4 在版本/标识未冻结时标 `DONE`；1.10.3 把“建议”标 `DONE`；1.1.1 与 R-G01 把“代码证据基线”标成“发布 revision 已冻结”。见 F-03/F-05。
- checklist §7 的 No-Go 摘要只列 B-01..B-08，与 1.2.6 的 PENDING 不闭合。见 F-04。

### 3.5 签名与密钥纪律（符合）

- 文档明确证书 `.cer`、Profile `.p7b`、密钥库 `.p12`、alias、口令由用户/授权签名人提供，不入库、不写日志、不进入 Artifact/截图/聊天。
- 签名步骤要求干净 release 构建、验证 `Will skip sign` 消失、记录签名 HAP 大小/SHA、安装 smoke、签名后复验；签名后再改版本/包名需重建/重签/复验。
- 本次扫描未发现秘密值；`release-plan.md` 与 release notes 只出现材料类型名称。**未发现签名/密钥纪律缺陷。**

### 3.6 远端策略正确性（事实正确；旧公开版本影响分析不足）

- `main=a6f6558`、`origin/main=7d6f4c9`、merge-base 空、远端仅 `main`、无 tag——本次实测一致。
- `main_merge_mode: review_request_when_remote` 的解释正确：有 remote 时禁止本地 main merge，需托管 PR/MR；force push/历史改写被列为高风险。
- A-E 选项、建议 A/B、C/D 的风险提示总体合理；`origin/main` 为本地跟踪引用、未 fetch 的说明诚实。
- **不足**：未分析 `origin/main` 旧公开版本的 bundleName/versionCode/Apache-2.0/NOTICE/用户与 Release 影响；见 F-01。

### 3.7 CHANGELOG / Release Notes（内容完整、链接有效、无过度承诺）

- CHANGELOG：`Status: DRAFT`、发布状态“未发布”、`[1.0.0]` 为准备基线日期而非发布日期；范围/安全/已知问题/验证边界齐全。
- Release notes：版本与平台、设备支持矩阵、安装前提（签名/设备/权限/网络/源码构建/升级）、首次使用、已知限制、验证证据边界、反馈与支持、B-01..B-08、许可证、相关文档齐全。
- 链接：5 个文档 49 条相对链接全部存在；未发现断链。
- 证据边界：明确 Host/仿真器/构建 PASS 不等于设备验收、用户验收、NFR 达标或发布就绪；ACK p95 明确 `MOCK_ONLY`；未签名 HAP 明确不可安装。
- **旧公开版本**：release notes §4 #7 的“作为首次发布，当前没有公开旧版本”不准确；见 F-01。

### 3.8 一致性与链接（除 B-07/旧公开版本外基本一致）

- README 发布小节链接 CHANGELOG、release notes、RELEASE-001、RELEASE-CHECKLIST-001 均有效；`NOT_READY` 口径一致。
- `B-01..B-08 的当前状态见 RELEASE-001 §2 与发布检查单 §7` 的指向在 B-07 上不成立：RELEASE-001/checklist 仍写“无 CHANGELOG”，而 README/release notes 说草案已产出。见 F-02。
- README 的 G-018 行仍写“Gate 由 Orchestrator 判定”，而 `state/project-state.md:72-74` 已记录 G-018 PASS @ `13de4d7`；这不是本次发布资产新增内容，属既有 README 状态口径，建议后续同步，不影响本轮 release 结论。
- 非阻塞观察：checklist 1.9.1 的远端选项未列 RELEASE-001 §7.2 的 D（合并不相关历史）；建议在后续文档同步时对齐 A-E。

### 3.9 i18n（符合）

- zh-CN / en-US 资源各 26 keys，双向 missing 0、空值 0；`check_i18n.py --strict-ui` 为 `0 blocking / 0 missing`。
- 16 条 hardcoded warning 为 `AppTheme` 阴影颜色字符串、AC 品牌协议别名、Mock 错误消息；均非用户可见 UI/错误文案，且 Mock 不进入生产 HAP（0 命中）。
- 未发现重复代码库变体或按语言分叉的应用代码；单代码库 + 资源文件模式符合 `docs/internationalization.md` 的默认要求。

---

## 4. Findings

> 严重度按“对发布准备结论/门禁可信度的实际影响”评定；F-01 为 High，F-02/F-03/F-04 为 Medium，F-05/F-06 为 Low。所有 Finding 均绑定当前 revision 的具体位置与证据。

| ID | 严重度 | 主题 | 位置（当前文件行） | 结论 |
|---|---|---|---|---|
| **F-01** | **High** | 未核对 `origin/main` 已有公开 YaoCore 1.0.0：不同 bundleName、versionCode 1000000、Apache-2.0 | `artifacts/85-release/release-plan.md:136,260`；`docs/release-checklist.md:129`；`docs/release-notes-v1.0.0.md:62`；`release-plan.md:60,65,92` | **CHANGES_REQUIRED** |
| **F-02** | **Medium** | B-07 当前状态仍写“无 CHANGELOG/Release Notes”，与 63d2235 草案冲突 | `release-plan.md:66,91,352`；`docs/release-checklist.md:91,300` | **CHANGES_REQUIRED** |
| **F-03** | **Medium** | R-G01 / checklist 1.1.1 把“代码证据基线”写成“发布 revision 已冻结” | `release-plan.md:349`；`docs/release-checklist.md:49`；对照 `release-plan.md:65,351`、`git tag -l` 空 | **CHANGES_REQUIRED** |
| **F-04** | **Medium** | B-01..B-08 / §7 No-Go 清单未覆盖 1.2.6 构建 warning / 混淆裁剪决策 | `docs/release-checklist.md:66,290-303`；`release-plan.md:67,193` | **CHANGES_REQUIRED** |
| **F-05** | **Low** | checklist 1.2.4 / 1.10.3 在依赖未满足时标 `DONE` | `docs/release-checklist.md:64,166` | 建议修正 |
| **F-06** | **Low** | P1/P2 回滚触发条件缺少可量化阈值 | `release-plan.md:308-314`；`docs/release-checklist.md:164` | 建议修正 |

### F-01 [High] 未核对 `origin/main` 已有公开 YaoCore 1.0.0（不同 bundleName、versionCode 1000000、Apache-2.0）

**位置**

- `artifacts/85-release/release-plan.md:136`：“首次发布不存在‘从旧版本升级’的公开路径；若曾在内部分发过同 bundleName 的构建，必须用更高 versionCode 做升级安装验证。”
- `artifacts/85-release/release-plan.md:260`：仅记录 `origin/main` 为 `7d6f4c9`（`Initial public release of YaoCore`），未分析其内容。
- `docs/release-checklist.md:129`：1.7.7 升级安装状态为 `N/A（当前无公开旧版本；若有内部分发则必须执行）`。
- `docs/release-notes-v1.0.0.md:62`：“作为首次发布，当前没有公开旧版本。”
- `artifacts/85-release/release-plan.md:60,92`（B-01/许可证）与 `:65`（B-06/版本）未把旧公开版本作为输入。

**证据**

```text
$ git show 7d6f4c9:AppScope/app.json5
bundleName: io.github.quirkybrain.yaocore
vendor: YaoCore
versionCode: 1000000
versionName: 1.0.0

$ git show 7d6f4c9:entry/oh-package.json5
"license": "Apache-2.0"

$ git show 7d6f4c9:LICENSE | head -3
Apache License
Version 2.0, January 2004

$ git show 7d6f4c9:NOTICE
YaoCore（爻构）
Copyright 2026 Zhang HaoXuan
Source: https://github.com/Quirkybrain/YaoCore

$ git show 7d6f4c9:README.md（第 227 行）
本项目采用 Apache License 2.0 开源。

$ git ls-remote --heads origin
7d6f4c99fa1bf0baf5e40d1948a97f564a647401  refs/heads/main
```

当前树对照：

```text
AppScope/app.json5: bundleName=com.example.yaocore, vendor=example, versionCode=1000000, versionName=1.0.0
entry/oh-package.json5: license 为空
当前树无 LICENSE / NOTICE / AUTHORS.md
git merge-base main origin/main: 空（历史不相关）
```

**影响**

1. **身份/升级路径**：`origin/main` 是公开的 YaoCore 1.0.0，bundleName 为 `io.github.quirkybrain.yaocore`。如果新应用采用这个旧公开 bundleName（一个可能的正式选择），`versionCode 1000000` 已被公开 1.0.0 使用；必须递增（>1000000），否则升级安装/AGC 版本校验可能失败或被拒绝。如果保留 `com.example.yaocore`，则它是独立应用身份，旧公开用户无法升级；“首次发布/没有公开旧版本”会误导用户与发布评审。
2. **许可证**：旧公开版本是 Apache-2.0，带 `LICENSE` 与 `NOTICE`；当前树没有 `LICENSE`/`NOTICE`，`entry/oh-package.json5` 的 license 为空。若新代码/设计与之存在衍生关系，需保留版权、许可证与来源声明；若为 clean-room 重写，也应明确与旧公开版本的关系，不能只写“项目从未有许可证”。README 首行“开源智能家居”在许可证决定前也缺乏依据。
3. **远端策略**：`origin/main` 不只是“旧历史”，而是公开版本；选项 C/D 的影响不仅是历史/链接，还包括旧用户、旧许可证、可能的 Release/tag/下载与来源声明。计划应把它作为发布决策输入；当前选项 A-E 的分析没有覆盖这一点。
4. **B-05/B-06 门禁完整性**：B-06 的“若已有任何已分发构建，必须递增 versionCode”事实上可以覆盖旧公开版本，但计划没有把它点名；B-05 的远端分析也没有把旧公开版本的用户/许可证纳入。结果是评审者需要在两个文档间自行推断，容易漏掉。

**违反的约束/目标**：发布事实准确性（本轮复审重点 #1/#6/#7）；RELEASE-001 B-01（许可证）、B-05（远端/通道）、B-06（身份/版本）的关闭条件；release notes“范围/安装/升级/许可证”完整性。

**建议**

1. 在 RELEASE-001 新增“已有公开版本（origin/main）”小节，记录旧 bundleName/vendor/versionCode/versionName、Apache-2.0 `LICENSE`/`NOTICE`、旧 README 的许可证声明、旧公开树范围。
2. 在 release notes §1/§4 #7 与 checklist 1.7.7 明确两种身份路径：
   - **保留新 bundleName**（如 `com.example.yaocore` 或另一新名）：说明这是独立应用身份，旧公开应用无法升级；versionCode 可从 1000000 开始，但不得暗示覆盖旧应用。
   - **采用旧 bundleName** `io.github.quirkybrain.yaocore`：versionCode 必须 >1000000；重新构建、签名、安装升级验证；同步 AGC/Profile；旧数据/旧应用身份的影响需评估。
3. B-01 增加“旧公开版本 Apache-2.0/NOTICE 的继承或 clean-room 裁定”；如果新代码/设计有衍生关系，补齐 `LICENSE`/`NOTICE` 与版权声明；如果决定新许可证，记录与旧许可证的关系。
4. B-06 把旧公开 1.0.0 明确列为“已分发构建”；B-05/§7 增加旧公开版本用户、许可证、Release/tag 保留分析；C/D 选项的风险说明补充旧用户/来源声明。
5. README 首行“开源”在许可证决定前改为“智能家居”或“计划开源”；许可证落地后再恢复“开源”。

### F-02 [Medium] B-07 当前状态仍写“无 CHANGELOG/Release Notes”，与 `63d2235` 实际草案冲突

**位置**

- `artifacts/85-release/release-plan.md:66`：B-07“仓库无 `CHANGELOG.md`；无正式 release notes”。
- `artifacts/85-release/release-plan.md:91`：CHANGELOG 行“无 `CHANGELOG.md`；无正式 release notes”，状态 `PENDING`。
- `artifacts/85-release/release-plan.md:352`：R-G04 `FAIL（B-07）`。
- `docs/release-checklist.md:91`：1.4.4“`CHANGELOG.md` 已创建并覆盖本版本”状态 `PENDING`。
- `docs/release-checklist.md:300`：§7 No-Go 第 7 条“无 CHANGELOG/Release Notes（B-07）”。

**证据 / 对照**

- `CHANGELOG.md` 已存在，头部 `Status: DRAFT`，含 `[1.0.0]` 条目；`docs/release-notes-v1.0.0.md` 已存在，头部 `Status: DRAFT / NOT_READY`。
- `README.md:73` 已明确“`CHANGELOG.md` 与 `docs/release-notes-v1.0.0.md` 当前为发布准备草案：B-07 的文档缺口已补齐草案，但仍需发布评审/用户签核”。
- `docs/release-notes-v1.0.0.md:163` 已把 B-07 状态更新为“本次已产出草案；仍待发布评审/签核”。
- RELEASE-001/checklist 是 `6cd9a88` 快照；在该 revision 上“无 CHANGELOG”曾为真。但 `README.md:64` 把 `RELEASE-001 §2` 与 checklist §7 作为“当前状态”的指向，导致读者在 `63d2235` 得到错误的当前状态。

**影响**

- B-07 的“现状/关闭条件”与 release notes/README 不一致；R-G04 的 `FAIL` 与 checklist §7 的“无 CHANGELOG”不再反映当前资产。
- 发布经理可能重复创建 CHANGELOG/notes，或误以为 B-07 尚未开始；也可能反过来在签核未完成时误判 B-07 已关闭。两种都不利于门禁判断。
- 该问题不导致越界发布声明（所有文档仍为 `NOT_READY`），但属于发布事实准确性与跨文档一致性缺陷。

**建议**

- 将 RELEASE-001 B-07/§3 CHANGELOG/R-G04 与 checklist 1.4.4/§7 第 7 条更新为“草案已产出（`63d2235`：`CHANGELOG.md`、`docs/release-notes-v1.0.0.md`）；待评审/用户签核”，与 release notes/README 对齐。
- 或者，如果坚持 RELEASE-001/checklist 为 `6cd9a88` 快照，在文档头部显著标注“状态截至 `6cd9a88`；B-07 已由 `63d2235` 草案部分关闭”，并修正 README 的“当前状态”指向（改为 RELEASE-001 §2 + release notes §9）。

### F-03 [Medium] R-G01 / checklist 1.1.1 把“代码证据基线”写成“发布 revision 已冻结”

**位置**

- `artifacts/85-release/release-plan.md:349`：R-G01“发布 revision 冻结且工作树干净；无未提交代码/配置”状态 `PASS（6cd9a88；docs-only 本任务）`。
- `docs/release-checklist.md:49`：1.1.1“发布 commit 已冻结，分支/tag 指向该 commit；工作树干净”状态 `DONE（6cd9a88）`。
- 对照 `release-plan.md:65`（B-06 PENDING）、`:351`（R-G03 PENDING）、`:130`（冻结顺序：确认 bundleName/vendor → version → 签名 → 干净 release 构建 → 签名 → 记录 SHA → tag/发布）。

**证据**

- `git tag -l` 为空；`git branch --points-at 6cd9a88` 无输出；`feat/yaocore-app` 当前为 `b716207`，不是 `6cd9a88`。
- `release-plan.md:264` 自己写“tag：无”；`:262` 写 `feat/yaocore-app @ 6cd9a88`，但这是 `6cd9a88` 时点的快照；`63d2235` 已前进。
- B-06/R-G03 明确承认 bundleName/vendor/version 未冻结；如果身份/版本后续变化，发布 revision 必然变化。

**影响**

- R-G01 是 Go/No-Go 的第一项；把它标 `PASS` 会让读者以为最终发布 commit/tag 已锚定，而实际只有“代码证据基线 6cd9a88”。在 B-06 未关闭、无 tag 的情况下，最终发布 revision 尚未存在。
- checklist 1.1.1 的“分支/tag 指向该 commit”在 `6cd9a88` 时点可能由 `feat/yaocore-app` 满足，但在 `63d2235` 已不成立；该状态至少应标为 `PARTIAL` 并说明“快照分支已前进，最终 tag 待 B-06 后创建”。
- 这会影响发布证据链的可审计性：签名 HAP 必须绑定最终 commit/tag，而不是仅绑定一个中途快照。

**建议**

- 把 R-G01 拆成两项：`code evidence baseline = 6cd9a88（PASS）` 与 `final release revision/tag = PENDING（B-06 后创建）`；或将 R-G01 改为 `PARTIAL`，明确最终 tag 未创建。
- checklist 1.1.1 改为 `PARTIAL（6cd9a88 代码基线；feat 已前进到 b716207；最终 tag 待 B-06）`；在 B-06 关闭后创建 annotated tag，重新构建/签名/复验并更新 SHA。
- 在 §1/§7.1 明确“6cd9a88 是证据基线，不是最终发布 commit”；避免把快照值当当前值。

### F-04 [Medium] B-01..B-08 / §7 No-Go 清单未覆盖 1.2.6 构建 warning / 混淆裁剪决策

**位置**

- `docs/release-checklist.md:66`：1.2.6“构建 warning 已 triage（API 18 vs compatible 14、混淆未启用等）”状态 `PENDING（需签核/修复决定）`。
- `artifacts/85-release/release-plan.md:193`：§5.5 第 2 条“是否在 v1 启用混淆/裁剪属于发布硬化决策，需评估符号化/崩溃定位与回归；本任务不修改”。
- `artifacts/85-release/release-plan.md:67`：B-08 列表未包含上述 warning/混淆项。
- `docs/release-checklist.md:290-303`：§7 No-Go 摘要只列 B-01..B-08，未列 1.2.6。

**影响**

- 发布经理按 §7 关闭 B-01..B-08 后，1.2.6 仍可能 `PENDING`；而“B-01..B-08 关闭即可发布”的文案没有覆盖它，形成门禁缺口。
- API 18 `ColumnType/TEXT/BLOB` 与 compatible 14 的运行时兼容性尚未验证；混淆/裁剪会直接影响崩溃定位、符号化与回归成本。两者都需要明确的修复/接受决定，不能只留在 checklist 的 PENDING 行。
- 这不是说必须在 v1 启用混淆；而是要求把“启用/不启用”的决策、理由与回归/符号化计划记录为发布 Gate 输入。

**建议**

- 新增 **B-09**（或扩展 B-08 的显式列表）：“构建 warning/API 兼容与混淆/裁剪决策”，关闭条件为：API 14 运行时验证或用户书面风险接受；混淆/裁剪启用与否的决策、符号化/崩溃定位方案、回归结果。
- 把 checklist 1.2.6 映射到 B-09/B-08，并在 §7 No-Go 摘要中加入该条；更新 release notes §9 的 B 列表。
- 如果用户接受“不启用混淆 + API 14 未验证”，在发布 Gate 记录中写明范围与残余风险；不得仅以“构建成功”关闭。

### F-05 [Low] checklist 1.2.4 / 1.10.3 在依赖未满足时标 `DONE`

**位置**

- `docs/release-checklist.md:64`：1.2.4“`module.json`/`pack.info` 的 bundleName、versionName、versionCode、compatible/target API 与预期一致”状态 `DONE（值待 1.1.3/1.1.4 冻结）`。
- `docs/release-checklist.md:166`：1.10.3“versionCode 单调递增策略已确认；不得降级”状态 `DONE（建议）`。

**影响**

- 1.2.4 的“与预期一致”在 1.1.3/1.1.4 未冻结时无法最终判定；标 `DONE` 与“值待冻结”自相矛盾。
- 1.10.3 的“建议”不等于“已确认”；标 `DONE` 会让读者以为用户已批准版本策略。
- 属于状态标注问题，不会直接导致错误发布，但会削弱 checklist 的“PASS 只用于实际执行且断言通过”的纪律。

**建议**：1.2.4 改为 `PARTIAL（结构/值已记录；待 1.1.3/1.1.4 冻结后最终确认）`；1.10.3 改为 `PENDING（建议已提出；待用户确认）`。

### F-06 [Low] P1/P2 回滚触发条件缺少可量化阈值

**位置**

- `artifacts/85-release/release-plan.md:308-314`：P1“关键设备类型控制失败；BLE/LAN 主路径高失败率；严重 i18n/布局问题；性能显著回退”；P2“非核心 UI/A11y 缺陷；低频兼容问题；文档错误”。
- `docs/release-checklist.md:164`：1.10.1 回滚触发条件/动作/责任人已批准，状态 `DONE（plan）；待签核`。

**影响**

- P0 条件（无法安装/启动、崩溃/ANR 阻塞主流程、核心链路失效、秘密泄露等）可判定；P1/P2 的“高失败率/显著回退/低频”没有数值阈值，发布后 on-call 难以一致判断是否停止 rollout/回滚。
- 计划已写“建议阈值由用户批准”，说明这是待决项；但在 Go/No-Go 前应形成可执行的阈值表，而不是仅保留定性描述。

**建议**：在 §8.1 增加可量化阈值（示例：核心控制失败率、安装失败率、crash-free sessions、ANR 率、LAN 控制 p95、回滚观察窗口），由用户/发布负责人签核；checklist 1.10.1 在阈值签核前保持 `PENDING`。

### 非阻塞观察

1. **README 首行“开源”与许可证 TODO**：已并入 F-01 的建议；在 B-01 关闭前，公开文案应避免无条件“开源”。
2. **README G-018 行**：`README.md:22,37` 仍写“G-018 Stage Gate 由 Orchestrator 判定”，而 `state/project-state.md:72-74` 已记录 G-018 PASS @ `13de4d7`；这是本次发布任务之前的既有 README 状态口径，建议后续同步，不影响本轮 release 结论。
3. **checklist 1.9.1 远端选项**：列出“新仓库/原远端新分支/替换 main/不发布”，未列 RELEASE-001 §7.2 的 D（合并不相关历史）；建议后续对齐 A-E。
4. **RELEASE-001 上游 README 版本**：`release-plan.md:11` 写 README-001 v1.1，当前 README 为 v1.2；这是 `6cd9a88` 快照的上游版本，不是事实错误，但建议在最终发布基线重述时更新。
5. **构建非字节可复现的原因**：报告称“归档时间戳/打包元数据”导致两次构建 SHA 不同；本次只验证了当前 `1602110d…` 与 debug `1983ea22…`，未复现第二次 release 构建 `be83926d…`。报告没有承诺字节级可复现，结论方向正确；原因表述可改为“观察到的差异与归档元数据一致，未做逐字节归因”。

---

## 5. Verdict

**`CHANGES_REQUIRED`（仅限 `63d2235` 的发布准备资产；release 仍为 `NOT_READY`）**

- **不是代码/测试否决**：本次复验的 host 697/697、crosscheck 66/66、仿真器 20/20、fixture 27/27、layering 221/0、i18n 0 blocking/0 missing、triage 615 均通过；未发现产品行为、测试断言或安全负例失败。
- **不是发布批准**：F-01..F-04 修正后，仍需 B-01..B-08（及新增 B-09 如适用）关闭、用户书面风险接受、签名/安装/设备验收、远端/通道授权与发布 Gate 判定；本报告不授予任何这些权限。
- **必须修正的核心项**：
  1. **F-01 High**：把 `origin/main` 公开 YaoCore 1.0.0（`io.github.quirkybrain.yaocore`、versionCode 1000000、Apache-2.0/NOTICE）纳入 B-01/B-05/B-06、release notes 与 checklist 的身份/升级/许可证/远端分析；移除无条件的“首次发布/当前无公开旧版本”。
  2. **F-02 Medium**：把 B-07/R-G04/checklist 1.4.4/§7 更新为“草案已产出（`63d2235`）；待评审/签核”，或显著标注 `6cd9a88` 快照并修正 README 的“当前状态”指向。
  3. **F-03 Medium**：区分“`6cd9a88` 代码证据基线”与“最终发布 revision/tag”；R-G01/1.1.1 改为 `PARTIAL/PENDING`，待 B-06 关闭后创建 tag、重建、签名、复验。
  4. **F-04 Medium**：新增 B-09 或扩展 B-08，覆盖 API 18 vs compatible 14 warning、混淆/裁剪决策；把 checklist 1.2.6 纳入 §7 No-Go 清单。
  5. **F-05/F-06 Low**：修正 1.2.4/1.10.3 状态；在 Go/No-Go 前形成用户批准的回滚阈值表。
- **PASS 的最低条件**：上述 1-4 修正后，重新检查链接/跨文档状态一致性，并由独立 reviewer 复审受影响章节；代码/构建配置变化时，按 Change Impact 重跑受影响证据。

**Verdict 仅覆盖本报告 §1 的 revision 与范围**；不授予 Stage Gate、release、签名、push/PR/MR/tag、应用市场或用户验收。设备/真实 BLE/LAN/TLS/云/硬件/视觉/fps 仍 `BLOCKED`；`PORT-LOC-01` 仍 `OPEN`；ACK p95 仍 `MOCK_ONLY`；NFR 4.1/4.2/4.3 仍为 partial。

---

## 6. 残余风险与后续验证

### 6.1 发布阻塞（承接 B-01..B-08，未关闭）

| ID | 当前状态 | 本次复审结论 |
|---|---|---|
| B-01 许可证 | 当前树无 `LICENSE`/`NOTICE`；旧公开版本为 Apache-2.0 | **仍阻塞**；需 F-01 的旧公开版本许可证裁定 |
| B-02 签名 | `signingConfigs: []`；未签名 HAP | **仍阻塞**；未使用/未请求任何证书或秘密 |
| B-03 设备/用户验收 | U-01..U-12 未执行；`hdc` target 空 | **仍阻塞**；未执行设备验证 |
| B-04 GAP-AC-01..03 | 未决 | **仍阻塞**；待用户接受或 bounded fix |
| B-05 远端/通道 | 未授权；`origin/main` 旧公开版本与本地历史不相关 | **仍阻塞**；需 F-01 的旧公开版本/远端分析 |
| B-06 身份/版本/构建模式 | `com.example.yaocore`/`example`/1.0.0/1000000 未冻结；默认 debug | **仍阻塞**；需 F-01 的身份/versionCode 决策 |
| B-07 CHANGELOG/notes | 草案已产出；待评审/签核 | **部分进展**；RELEASE-001/checklist 状态需按 F-02 更新 |
| B-08 残余风险 | 未逐项书面接受 | **仍阻塞**；需补 F-04 的构建 warning/混淆项 |
| 新增建议 B-09 | 未列入 | **建议新增**；API 14 兼容/混淆裁剪决策 |

### 6.2 明确未执行/未声明

- 未执行：push、fetch、pull、PR/MR、merge、rebase、tag、签名、安装、应用市场/远端发布、设备矩阵、用户验收、法律级许可证审计、HAP 重新构建、codelinter 重跑、ohosTest 设备运行。
- 未声明：可安装、已签名、可发布、已发布、已推送、生产就绪、用户验收完成、设备验收完成、NFR 4.1/4.2/4.3 达标、真实 BLE/LAN/TLS/云/视觉/A11y/60-120fps 通过。
- 未把 `MOCK_ONLY`（ACK p95）写成验收数据；未把 `check_layering` 0 violation 写成 100% 端口位置合规（`PORT-LOC-01` 仍 OPEN）；未把 release-mode 构建成功写成签名/安装成功。
- 未把 `com.example.yaocore` 写成已确定的正式发布包名；未把旧公开版本与当前新 lineage 混为一谈。

### 6.3 证据时效

- 本报告所有结论绑定 `63d2235` 与当前工作区；任何代码、构建配置、版本、bundleName、签名配置、测试/契约或 `input/` 变化都会使相关证据失效，需 Change Impact 与重跑。
- `origin/main` 为本地跟踪引用；本次未 fetch。若远端已变化（例如新增 tag/Release 或改写 main），F-01 的旧公开版本分析需在授权后重新核对；C/D 选项尤其需要先备份并确认远端实际状态。
- HAP 非字节可复现；发布证据必须绑定 commit + 工具链 + 命令 + 产物 SHA-256，签名后重新记录，不能只依赖工作树产物。

---

## 7. Handoff

```text
STATUS: COMPLETE
SUMMARY: 独立复审 63d2235 的 Release 准备资产。22 项复验完成；host 697/697、crosscheck 66/66、仿真器 20/20、fixture 27/27、layering 221/0/6、i18n 0 blocking/0 missing、triage 615 行、HAP 1602110d/1,616,146 B/release/unsigned、链接 49/0、输入 pin 7/7 均一致；发布状态 NOT_READY/未签名/未发布/未验收/许可证 TODO 表述诚实，未发现“已发布/已签名/已验收/生产就绪”等越界肯定声明。Verdict CHANGES_REQUIRED：F-01 High（未核对 origin/main 公开 YaoCore 1.0.0：io.github.quirkybrain.yaocore、versionCode 1000000、Apache-2.0/NOTICE，导致“首次发布/无公开旧版本”、升级路径、许可证与远端分析不完整）；F-02 Medium（B-07 仍写无 CHANGELOG/notes，与 63d2235 草案冲突）；F-03 Medium（R-G01/1.1.1 把代码证据基线写成发布 revision 已冻结，B-06/R-G03 PENDING、无 tag）；F-04 Medium（No-Go 清单未覆盖 1.2.6 构建 warning/混淆裁剪）。F-05/F-06 Low（1.2.4/1.10.3 状态标注、回滚阈值不可量化）。
ARTIFACTS_CREATED: artifacts/70-review/t26-release-review.md
ARTIFACTS_UPDATED: none
RISKS: release 仍 NOT_READY；B-01..B-08 未关闭（B-07 草案待签核）；无签名/安装/设备/用户验收；远端/发布未授权；旧公开版本身份/版本/许可证未裁定；HAP 未签名且非字节可复现；API 14 运行时/混淆裁剪未决；PORT-LOC-01 OPEN；ACK p95 MOCK_ONLY；NFR partial；README “开源”措辞待许可证收口。
VALIDATION: git HEAD=63d2235；diff 6cd9a88..63d2235 7 files +1274/-5；HAP sha256 1602110d…、1,616,146 B、release、13 entries、无 META-INF；host 697/697 exit 0；layering files=221 violations=0 exceptions_used=6 exit 0；crosscheck hard ALL PASS 66/66 exit 0；simulator 20/20 exit 0；fixture 27/27 exit 0；i18n blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16 exit 0；triage 615 rows OK exit 0；zh/en 26/26 keys；49 relative links 0 broken；main=a6f6558、origin/main=7d6f4c9、merge-base 空；tag 空；origin 仅 main；输入 pin 7/7。
NEEDS_CLARIFICATION: 旧公开版本身份/许可证/升级策略（F-01）需用户决定：保留 com.example.yaocore（独立新应用、无旧版升级）还是采用 io.github.quirkybrain.yaocore（versionCode 必须 >1000000、重建/签名/复验）；是否继承旧 Apache-2.0/NOTICE。另需用户批准回滚阈值（F-06）。
NEXT_ACTION: 由 release-engineer/technical-writer 修正 RELEASE-001/checklist 的 B-07、R-G01/1.1.1、B-08/1.2.6 状态，并在 RELEASE-001/release notes/checklist 中加入 origin/main 公开 1.0.0 的身份/版本/许可证/升级分析；更新后重跑链接与跨文档一致性检查，并由独立 reviewer 复审受影响章节。release 保持 NOT_READY；任何签名、push/PR/MR/tag 或发布仍需用户显式授权。
```

---

*T26-RELEASE-REVIEW 结束。本报告只完成 `63d2235` 的 Release 准备资产独立复审；`CHANGES_REQUIRED` 不改变 `NOT_READY`，也不授予任何发布、签名、远端或用户验收权限。*
