# Release 资产修正聚焦复评（T-26 复评 / wp-119）

- **Artifact ID**: T26-RELEASE-REREVIEW
- **Producer**: agent:quality-reviewer
- **Role**: quality-reviewer（独立复评；未参与 `wp-116-release-fix` / `wp-117-release-notes-sync` / `wp-118-release-consistency` 的编写）
- **Task**: `wp-119-release-rereview`（HANDOFF `state/handoffs/wp-119-release-rereview.json`）
- **Reviewed revision**: `3501f5e69da159bcbf1547d6d5906d24388bbe95`（`task/wp-118-release-consistency`；包含 `972f177`、`19df893`、`3501f5e`）
- **Original review**: `artifacts/70-review/t26-release-review.md` @ `63d2235`（T26-RELEASE-REVIEW；F-01..F-06）
- **Release preparation base**: `6cd9a88d0fdc1b08cc6ffca233c12c41df737519`（RELEASE-001 构建探针 revision）
- **Code evidence baseline**: `e74a181` / TEST-002（产品代码与构建配置至本复评未变）
- **Review scope**: `artifacts/85-release/release-plan.md`（RELEASE-001）、`docs/release-checklist.md`（RELEASE-CHECKLIST-001）、`docs/release-notes-v1.0.0.md`、`CHANGELOG.md`、`README.md` 发布小节
- **Workflow**: STANDARD / GATED_AUTO
- **Date**: 2026-10-18
- **Verdict**: **`PASS`（仅限发布准备文档修正；release 仍为 `NOT_READY`，不是发布批准）**
- **Status**: COMPLETE

> **结论先行**
>
> 1. **F-01..F-06 的核心修正均已闭环**：公开旧版本事实、A/B/C 身份/版本/许可证选项、B-01/B-05/B-06 待用户决定、B-07 草案状态、代码证据基线与最终 revision/tag 的区分、B-09 构建硬化项、1.2.4/1.10.3 状态、P1/P2 阈值提案，均与当前文档一致。
> 2. **未发现阻断性 Finding**：B-01..B-09 在 RELEASE-001、发布检查单 §7 与 release notes §9 中编号连续、状态一致；README 引用 README-001 v1.3；5 个被审文档的相对链接 53 条、0 broken；未发现肯定式“已发布/已签名/已验收/生产就绪/已上架”等越界声明；`NOT_READY`、未发布、未授权口径保留。
> 3. **回归复验通过**：host 697/697、layering `files=221 violations=0 exceptions_used=6`、crosscheck 66 `[PASS]` / 0 `[FAIL]` / `hard checks: ALL PASS`；仿真器 20/20、fixture 27/27、i18n 0 blocking / 0 missing、triage 615 行一致；文档数字与 TEST-002 / ACCEPT-001 一致。
> 4. **PASS 的边界**：本结论只覆盖 `3501f5e` 的发布准备文档修正，不授予 release、签名、安装、push/PR/MR/tag、应用市场或用户验收任何权限。B-01..B-09 仍未关闭，release 仍为 `NOT_READY`；最终 release revision/tag 未冻结。

---

## 1. 范围、revision、输入与独立性

| 项 | 本次结论 | 证据 |
|---|---|---|
| 仓库 / 分支 | `/home/quirkybrain/code/harmony-projects/YaoCore`；`task/wp-118-release-consistency` | `git branch --show-current` |
| Reviewed HEAD | `3501f5e69da159bcbf1547d6d5906d24388bbe95` | `git rev-parse HEAD` |
| 原复审 revision | `63d2235`（`task/wp-114-release-notes`） | `git show -s --format=%H 63d2235` |
| 修订链 | `63d2235` → `f1fbe0d`（原复审报告）→ `972f177`（plan/checklist 修正）→ `19df893`（release notes/CHANGELOG/README 同步）→ `3501f5e`（交叉引用统一） | `git log --oneline 63d2235..3501f5e` |
| 变更规模 | `63d2235..3501f5e` 共 6 个路径，`+706 / -142`；其中 5 个被审发布资产 `+304 / -142`，原复审报告 `+402 / -0` | `git diff --numstat 63d2235..3501f5e` |
| 输入完整性 | handoff 的 **6/6** 个输入 SHA-256 与文件实算一致 | Python `hashlib.sha256` 对照 handoff |
| 独立声明 | 未参与 RELEASE-001、RELEASE-CHECKLIST-001、release notes、CHANGELOG、README v1.2/v1.3 的编写；未编辑任何被审文件；唯一写入为本报告 | 本任务 `writes` / `commit_paths` 仅 `artifacts/70-review/` |
| 授权边界 | 未 push、未 fetch、未 pull、未创建/修改/删除分支或 tag、未签名、未安装、未发布；`git show` / `git ls-remote` 仅为只读查询 | 见 §2、§6 |
| 明确排除 | 设备/真实 BLE/LAN/TLS/云/硬件/视觉/fps 验收；实际签名与安装；应用市场/远端发布；法律级许可证审计；HAP 重新构建；codelinter 重跑 | 见 §7 |

**审核限制**：本次聚焦复评以文档修正与回归证据为主，**未重新执行 clean build 或 codelinter**。当前 `entry/build/default/outputs/default/entry-default-unsigned.hap` 为既有 release-mode 构建产物；本次只核对了其大小/SHA-256/条目/模式/签名材料。`codelinter 0 error / 25 warning` 沿用 TEST-002 结果，未在本轮重跑。

---

## 2. 独立复验矩阵（cwd = 仓库根，2026-10-18 实际执行）

| # | 命令 / 检查 | 本次实测 | 退出码 |
|---|---|---|---|
| 1 | `git rev-parse HEAD` / `git branch --show-current` / `git status --porcelain` | `3501f5e69da159bcbf1547d6d5906d24388bbe95`；`task/wp-118-release-consistency`；工作树 clean | 0 |
| 2 | `git diff --numstat 63d2235..3501f5e` | 6 files changed, 706 insertions(+), 142 deletions(-)；5 个被审资产 `+304/-142` | 0 |
| 3 | handoff 6 个输入 SHA-256 | **6/6** 一致 | 0 |
| 4 | `entry/src/test/run-host-tests.sh` | `1..697`；tests 697 / pass 697 / fail 0 / skipped 0；约 3,630 ms | 0 |
| 5 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | `files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0`；`PASS` | 0 |
| 6 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py` | 66 `[PASS]` / 0 `[FAIL]`；`hard checks: ALL PASS`；14 条既有 `FINDING` | 0 |
| 7 | `no_proxy=127.0.0.1,localhost NO_PROXY=127.0.0.1,localhost PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tools.simulator.test_gateway_contract` | `Ran 20 tests`；`OK`（HTTP+TLS） | 0 |
| 8 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/test_check_layering.py` | `Ran 27 tests`；`OK` | 0 |
| 9 | `PYTHONDONTWRITEBYTECODE=1 python3 entry/src/test/i18n/check_i18n.py --strict-ui` | `blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16` | 0 |
| 10 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/i18n/triage_legacy.py --check` | `615 rows`；`OK: CSV matches computed triage; invariants pass` | 0 |
| 11 | HAP 核对 | `1,616,146 B`；SHA-256 `1602110da9213ffe0520e83d60836e96f964d97f339c571a21dd8239f735bd03`；13 entries；`buildMode=release`、`debug=false`；无 `META-INF` | 0 |
| 12 | 公开旧版本事实核对 | `origin/main=7d6f4c9`；`bundleName=io.github.quirkybrain.yaocore`、`vendor=YaoCore`、`1.0.0/1000000`；`license=Apache-2.0`；`LICENSE`/`NOTICE` 存在；NOTICE 含版权/来源/保留声明 | 0 |
| 13 | 历史关系核对 | 本地 `main=a6f6558`；`git merge-base main origin/main` 无输出（exit 1，历史不相关）；`git tag -l` 为空 | 0 |
| 14 | 代码/配置未漂移 | `git diff --quiet e74a181..HEAD -- entry/src/main tools entry/src/test entry/src/ohosTest` exit 0；`build-profile.json5 AppScope/app.json5 oh-package.json5 entry/oh-package.json5 hvigorfile.ts` exit 0 | 0 |
| 15 | B 编号集合 | RELEASE-001、检查单、release notes 均为 **B-01..B-09 连续**；无 B-10、无缺号 | 0 |
| 16 | 相对链接检查 | 5 个文档共 **53** 条相对链接；**0 broken** | 0 |
| 17 | 越界肯定词扫描 | 未发现肯定式“已发布/已签名/已验收/生产就绪/已上架/可发布/可安装/已推送”声明；命中均为否定、禁止、条件或状态要求语境；唯一保留的项目自述“开源”见 O-01 | 0 |
| 18 | README 版本引用 | README 头部为 README-001 **v1.3**；RELEASE-001/检查单/release notes 均引用 v1.3 | 0 |
| 19 | 文档数字与 TEST-002 / ACCEPT-001 对照 | host 697/697、crosscheck 66/66、simulator 20/20、fixture 27/27、layering 221/0/6、i18n 0 blocking/0 missing/73 warning/16 hardcoded、triage 615、codelinter 0 error/25 warning、FR 26=24 covered+2 partial+0 gap、NFR 4.1/4.2/4.3 partial、U-01..U-12 未执行 | 0 |

**复验结论**：§2 的 19 项均实际执行并返回上述结果。文档中的代码级关键数字与 TEST-002 / ACCEPT-001 一致；HAP 现有产物与 RELEASE-001 §5.3 记录一致；公开旧版本事实与 `origin/main` @ `7d6f4c9` 一致。未复现的是第二次 release 构建的 `be83926d…` 哈希（既有报告已说明构建非字节可复现）；未执行设备、签名、远端与用户验收。

---

## 3. F-01..F-06 逐项闭环

| Finding | 原严重度 | 本轮结论 | 主要证据 |
|---|---|---|---|
| **F-01** 公开旧版本未核对 | High | **CLOSED（核心）** | RELEASE-001 §1/§4.4/B-01/B-05/B-06；release notes §1.1；README 发布小节；CHANGELOG §1.0.0 |
| **F-02** B-07 状态陈旧 | Medium | **CLOSED** | RELEASE-001 B-07/§3/R-G04；检查单 1.4.4/1.4.5/§7 第 7 条；release notes §9 |
| **F-03** 证据基线写成发布 revision 冻结 | Medium | **CLOSED** | RELEASE-001 头部/§1/§3.1/R-G01；检查单头部/§0/1.1.1；release notes/CHANGELOG 头部 |
| **F-04** No-Go 未覆盖构建 warning/混淆 | Medium | **CLOSED** | RELEASE-001 B-09/R-G09；检查单 1.2.6/1.5.9/§7 第 9 条；release notes B-09 |
| **F-05** 1.2.4/1.10.3 状态标注 | Low | **CLOSED** | 检查单 1.2.4 `PARTIAL`；1.10.3 `PENDING` |
| **F-06** P1/P2 阈值不可量化 | Low | **CLOSED（文档）**；阈值仍待用户批准 | RELEASE-001 §8.1.1；检查单 1.10.1 `PENDING` |

### 3.1 F-01：公开旧版本事实、A/B/C 选项与“待用户决定”

**事实准确性（实测）**

- `git show 7d6f4c9:AppScope/app.json5`：`bundleName=io.github.quirkybrain.yaocore`、`vendor=YaoCore`、`versionName=1.0.0`、`versionCode=1000000`。
- `git show 7d6f4c9:entry/oh-package.json5`：`"license": "Apache-2.0"`。
- `git show 7d6f4c9:LICENSE`：Apache License 2.0；`git show 7d6f4c9:NOTICE`：`YaoCore（爻构）`、`Copyright 2026 Zhang HaoXuan`、来源 `https://github.com/Quirkybrain/YaoCore`，并要求再分发保留版权/许可证/来源声明。
- `git ls-remote --heads origin`：`7d6f4c99fa1bf0baf5e40d1948a97f564a647401 refs/heads/main`。
- 当前树：`com.example.yaocore` / `example` / `1.0.0` / `1000000`；无项目级 `LICENSE`/`NOTICE`；`entry/oh-package.json5` 的 license 为空。

**文档闭环**

- RELEASE-001 头部 `:36`、§1 `:35`、§3.1 `:112`、§4.4 `:148-183`、§7.1 `:307` 均记录旧公开版本；§4.4 给出 A（沿用旧身份 + versionCode >1000000 + 继承 Apache-2.0/NOTICE）、B（新应用身份、旧用户无法升级）、C（混合/迁移）的做法与后果，并明确“只呈现可核对事实与选项后果，不替用户选择”。
- B-01 `:66`、B-05 `:70`、B-06 `:71` 均标记“**待用户在 §4.4 选项 A/B/C 中决定**”；B-01 同时覆盖旧公开版本 Apache-2.0/NOTICE 的继承或 clean-room 评估；B-05 覆盖旧用户/Release/tag/来源声明；B-06 覆盖旧 `io.github.quirkybrain.yaocore` + `1000000` 与 versionCode 递增要求。
- release notes §1.1 `:36-59` 与 RELEASE-001 §4.4 同步：事实对照、A/B/C 选项、当前状态“均未选择、本草案不推荐/不选择”，并明确在决定前不得写“首个公开版本 / 无公开旧版本 / 独立应用 / 可升级”。
- README `:66`、`:117` 与 CHANGELOG `:20`、`:35`、`:41-47` 同步了旧公开版本、身份/版本/许可证待决定与 A/B/C 分支。
- 全文检索“首次发布/当前无公开旧版本/无公开旧版本/首个公开版本”仅出现在**否定、禁止或“不得再写”**语境；未发现无条件的“首次发布/无公开旧版本”表述。

**结论**：F-01 的核心问题已关闭；未替用户做身份、版本或许可证决策。唯一遗留是 README 首行“开源”措辞（O-01，非阻塞，见 §5）。

### 3.2 F-02：B-07 状态统一为“草案已产出，待评审/签核”

- RELEASE-001 B-07 `:72`：“草案已产出 @ `63d2235`：`CHANGELOG.md`（`Status: DRAFT`）与 `docs/release-notes-v1.0.0.md`（`DRAFT / NOT_READY`）；内容仍待评审与用户/发布负责人签核”；§3 表 `:98` 状态 `PARTIAL`；R-G04 `:420` 为 `PARTIAL（草案已产出 @ 63d2235；待评审/签核，B-07）`。
- 检查单 1.4.4 `:91` 与 1.4.5 `:92` 均为 `PARTIAL（草案已产出 @63d2235；待评审/签核）`；§7 第 7 条 `:302` 为“草案已产出 @ `63d2235`；待评审/签核，不得写成已定稿或对外发布版本”。
- release notes §9 B-07 `:197` 与 README `:77` 同口径。
- 全文检索“无 CHANGELOG / 无正式 release notes / CHANGELOG 缺失”**0 命中**。

**结论**：F-02 关闭；B-07 仍为未签核草案，没有被误写成已定稿或已关闭。

### 3.3 F-03：代码证据基线与最终 release revision/tag 已区分

- RELEASE-001 头部 `:10-11`：代码证据基线 `TEST-002 @ e74a181`；构建探针 `6cd9a88`；**最终 release revision/tag 未冻结**（当前无 tag；`e74a181` 不是最终发布 commit）。
- §1 `:35`、§3.1 `:111`、§4.1 `:126` 与 §5.2 `:206` 均区分“代码证据基线/构建探针/最终发布 revision”；§9.1 R-G01 `:417` 为 `PARTIAL（代码证据基线 PASS：TEST-002 @ e74a181；最终 release revision/tag 未冻结；待 B-06 后创建 tag）`，`:431` 再次明确不得把 `e74a181` 或 `6cd9a88` 写成最终发布 commit。
- 检查单头部 `:7`、§0 `:27`、1.1.1 `:49` 均为“代码证据基线已确认；最终 release revision/tag 未冻结”；1.1.1 状态 `PARTIAL`，未写成 `DONE`。
- release notes `:9`、`:32` 与 CHANGELOG `:7` 采用同一口径。
- `git tag -l` 为空，`git branch --points-at 6cd9a88` 无输出，符合“未冻结、无 tag”。

**结论**：F-03 关闭。`已冻结` 仅出现在**判据要求文本**中，状态列均为 `PARTIAL/未冻结`；未发现“发布 revision 已冻结”的肯定结论。

### 3.4 F-04：B-09 已新增并进入 No-Go 门禁

- RELEASE-001 §2.2 B-09 `:74`：覆盖 API 18 `ColumnType/TEXT/BLOB` 与 compatible API 14 的运行时兼容性未验证；混淆/裁剪未启用且未决定；符号化/崩溃定位与回归方案未记录；关闭条件为 API 14 运行时验证或用户书面风险接受，并记录混淆/裁剪决策、理由、符号化方案与回归结果，不得仅以“构建成功”关闭。
- RELEASE-001 R-G09 `:425` 将 B-09 纳入风险签核；§5.5 `:240-241` 记录构建 warning/混淆发现；§10 `:461` 将 B-09 纳入 release notes 输入；§11.5 `:535` 记录 B-01..B-09 连续、cross-doc 引用一致。
- 检查单 1.2.6 `:66` 状态 `PENDING（B-09；需签核/修复决定）`；1.5.9 `:108` 为 B-09 专项签核；§7 第 9 条 `:304` 纳入 No-Go 摘要。
- release notes §9 B-09 `:199`、§6 已知限制 `:124`、README `:68`/`:116` 同步 B-09。
- §7 No-Go 摘要为 B-01..B-09 连续 9 条，未漏 B-09。

**结论**：F-04 关闭；1.2.6 的构建 warning/混淆裁剪决策已有 B-09 承接，并进入 No-Go/R-G09/1.5.9。

### 3.5 F-05：1.2.4 / 1.10.3 状态修正

- 检查单 1.2.4 `:64`：`PARTIAL（结构/值已记录 @6cd9a88；待 1.1.3/1.1.4 冻结后最终确认）`，不再在依赖未满足时标 `DONE`。
- 检查单 1.10.3 `:168`：`PENDING（建议已提出；待用户确认）`，不再把“建议”写成“已确认”。

**结论**：F-05 关闭。

### 3.6 F-06：P1/P2 量化阈值提案

- RELEASE-001 §8.1.1 `:363-384` 提供安装失败率、crash sessions、ANR、核心控制失败率、BLE 配网失败率、LAN 控制 p95、用户报告核心路径失败率 7 类指标，区分 P0/P1/P2，并给出观察窗口/最小样本（24h、7d、≥100 次、≥1000 sessions、≥200 条命令/样本等）。
- 标题与正文明确“**需用户批准后生效**”；“批准前 P1/P2 仍按定性条件判断，且不构成回滚授权”；“阈值经用户批准后写入发布 Gate 记录；任何修改需用户重新批准”。
- 检查单 1.10.1 `:166` 为 `PENDING（计划已起草；§8.1.1 阈值待用户批准）`；release notes `:127`、CHANGELOG `:86`、README `:119` 同步“未批准”状态。

**结论**：F-06 的文档修正关闭；阈值本身仍待用户批准，符合“提案、不代替用户决策”的要求。

---

## 4. 一致性、链接与回归

### 4.1 B-01..B-09 跨文档一致

| ID | RELEASE-001 §2.2 | 检查单 §7 | release notes §9 | 判定 |
|---|---|---|---|---|
| B-01 许可证 | 待用户 A/B/C；含旧公开 Apache-2.0/NOTICE | 待用户 A/B/C | `BLOCKED`；待 A/B/C | 一致 |
| B-02 签名 | 无签名配置 | 无签名/安装 smoke | `BLOCKED` | 一致 |
| B-03 设备/验收 | U-01..U-12 NOT RUN/BLOCKED | U-01..U-12 未执行 | `BLOCKED` | 一致 |
| B-04 GAP-AC | 未决 | 未决 | `PENDING` | 一致 |
| B-05 远端/通道 | UNAUTHORIZED；待 A/B/C + §7.2 | 未授权；待 A/B/C + §7.2 A-E | `UNAUTHORIZED` | 一致 |
| B-06 身份/版本 | PENDING；旧公开 1000000 | 未冻结；旧公开 1000000 | `PENDING` | 一致 |
| B-07 CHANGELOG/notes | 草案 @63d2235；待评审/签核 | 草案 @63d2235；待评审/签核 | 草案 @63d2235；待评审/签核 | 一致 |
| B-08 残余风险 | PENDING_RELEASE_SIGNOFF | 未逐项签核 | `PENDING` | 一致 |
| B-09 构建硬化/API 14 | PENDING；API 14/混淆未决 | 1.2.6/1.5.9 PENDING | `PENDING` | 一致 |

### 4.2 README 与文档引用

- README 头部为 README-001 **v1.3**，变更记录明确 wp-117 同步 B-09/旧公开版本，且未改变既有验证数字与 `NOT_READY`。
- RELEASE-001 `:14`、`:83`、检查单 1.4.3 `:90`、release notes `:10` 均引用 README v1.3。
- README 发布小节链接 CHANGELOG、release notes、RELEASE-001、RELEASE-CHECKLIST-001、原复审报告，均有效。
- 5 个被审文档相对链接 **53 条 / 0 broken**；未发现指向不存在文件或旧路径的链接。

### 4.3 状态诚实性与越界词

- 5 个文档均保留 `NOT_READY`、未发布、未签名、未验收、未授权口径；未发现“可安装/可发布/已签名/已验收/生产就绪/已上架/已推送”的肯定式声明。
- `已冻结` 仅出现在 R-G01/1.1.1 的判据要求文本；状态列明确为 `PARTIAL/未冻结`。
- `首个公开版本/无公开旧版本` 仅出现在否定、禁止或“不得再写”的语境。
- `开源` 在 README 首行仍有项目自述（O-01）；README §许可与致谢明确许可证 TODO，未据此授予再分发许可。

### 4.4 数字与证据一致性

| 文档数字 | TEST-002 / ACCEPT-001 | 本次复验 |
|---|---|---|
| Host 697/697 | TEST-002 §2 第 4 项 | 实测 697/697 |
| crosscheck 66/66 hard checks + 14 FINDING | TEST-002 §2 第 5 项 | 实测 66 PASS / 0 FAIL / 14 FINDING |
| 仿真器 20/20（HTTP+TLS） | TEST-002 §2 第 6 项 | 实测 20/20 |
| 分层 221 files / 0 violation / 6 exceptions | TEST-002 §2 第 7 项 | 实测一致 |
| fixture 27/27 | TEST-002 §2 第 8 项 | 实测 27/27 |
| i18n 0 blocking / 0 missing / 73 warning / 16 hardcoded | TEST-002 §2 第 9 项 | 实测一致 |
| triage 615 行 | TEST-002 §2 第 10 项 | 实测 615 行一致 |
| codelinter 0 error / 25 warning | TEST-002 §2 第 3 项 | 未重跑，沿用 TEST-002 |
| FR 26 = 24 covered + 2 partial + 0 gap | ACCEPT-001 §1/§3 | 文档一致 |
| NFR 4.1/4.2/4.3 partial | ACCEPT-001 §2.3 | 文档一致 |
| U-01..U-12 未执行 | ACCEPT-001 §用户侧 | 文档一致 |

**回归结论**：发布文档修正未改变产品代码/构建配置（`e74a181..HEAD` 代码/配置 diff exit 0），host/layering/crosscheck 等回归复验通过；文档数字与 TEST-002 / ACCEPT-001 一致。

---

## 5. Findings 与非阻塞观察

**阻断性 Findings：无。** F-01..F-06 的核心要求均已闭环，未发现需要返工的发布事实错误、门禁漏洞、越界发布声明或跨文档状态冲突。

以下为**不影响本轮 Verdict** 的文档维护建议（建议在后续发布文档维护轮或 B-01/B-06 决策落地时处理，不要求本轮返工）：

| ID | 位置 | 观察 | 影响 / 建议 |
|---|---|---|---|
| **O-01** | `README.md:3` | 首行仍称“开源智能家居”，而项目级许可证仍为 TODO（README `:389`）。这是原复审 F-01 的建议项之一，但不在本轮 README“发布小节”范围内，且 README 已在许可与致谢、发布小节、已知限制中明确许可证 TODO。 | 非阻塞；公开宣传前建议改为“智能家居”或“计划开源”，待 B-01 关闭后再恢复“开源”。 |
| **O-02** | `docs/release-notes-v1.0.0.md:8-9`；`CHANGELOG.md:7` | 两处 pin `RELEASE-001 @ 972f177`；当前 HEAD 为 `3501f5e`。`3501f5e` 仅调整交叉引用/README v1.3 引用，未改变 RELEASE-001 的实质结论。 | 非阻塞；读者可能误以为 `972f177` 是当前 HEAD。建议下次文档维护时改为“972f177 实质修订；3501f5e 交叉引用更新”或更新 pin。 |
| **O-03** | `artifacts/85-release/release-plan.md:126` | §4.1 写“当前候选为 `6cd9a88` 的已提交内容”。同文档 §1/§3.1/R-G01 已明确 `6cd9a88` 是构建探针、最终 release revision 未冻结。 | 非阻塞；该句可能被读成“候选 revision 已锚定 6cd9a88”。建议后续改为“构建探针/代码内容与 `e74a181` 一致”。 |
| **O-04** | `artifacts/85-release/release-plan.md:537` | §11.5 第 6 项写“越界肯定词扫描 0 命中（…否定/禁止语境亦已改写）”。实际文档仍保留“不可安装/不可发布”等正确的否定表述。 | 非阻塞的措辞备注；建议改为“扫描仅针对肯定式；否定/禁止语境不构成越界”，避免被读成否定词已被移除。 |

---

## 6. Verdict 与残余

### 6.1 Verdict

**`PASS`（仅限 `3501f5e` 的发布准备文档修正）**

- **通过理由**：F-01..F-06 的核心内容均已修正；B-01..B-09 跨文档编号/状态一致；公开旧版本事实经只读核对准确；A/B/C 选项与后果完整且未替用户决策；代码证据基线与最终 release revision/tag 区分清晰；B-09 已进入 No-Go/R-G09/1.2.6/1.5.9；1.2.4/1.10.3 状态正确；P1/P2 阈值提案完整且明确待用户批准；链接 0 broken；无越界发布声明；回归复验通过。
- **不是代码/测试否决**：host 697/697、layering 0 violation、crosscheck ALL PASS、仿真器 20/20、fixture 27/27、i18n 0 blocking/0 missing、triage 615 行一致；未发现产品行为、测试断言或安全负例失败。
- **不是发布批准**：本 PASS 不改变 `NOT_READY`，不授予 release、签名、安装、push/PR/MR/tag、应用市场或用户验收任何权限。

### 6.2 残余与未关闭项

| ID | 当前状态 | 复评结论 |
|---|---|---|
| B-01 许可证 | 当前树无 `LICENSE`/`NOTICE`；公开旧版本 Apache-2.0 + NOTICE | **仍阻塞**；待用户 A/B/C 决定与许可证落地 |
| B-02 签名 | `signingConfigs: []`；HAP 未签名 | **仍阻塞**；未使用/未请求任何证书或秘密 |
| B-03 设备/用户验收 | U-01..U-12 未执行；`hdc` target 空 | **仍阻塞**；未执行设备验证 |
| B-04 GAP-AC-01..03 | 未决 | **仍阻塞**；待用户接受或 bounded fix |
| B-05 远端/通道 | 未授权；`origin/main=7d6f4c9` 为公开 1.0.0 | **仍阻塞**；待 A/B/C + §7.2 A-E 授权 |
| B-06 身份/版本 | `com.example.yaocore`/`example`/1.0.0/1000000 未冻结；默认 debug | **仍阻塞**；待 A/B/C 决定 |
| B-07 CHANGELOG/notes | 草案 @63d2235；待评审/签核 | **部分进展**；状态已一致，签核未完成 |
| B-08 残余风险 | 未逐项书面接受 | **仍阻塞**；需发布 Gate 记录逐项签核 |
| B-09 构建硬化/API 14 | API 14 未验证；混淆/裁剪未决定 | **仍阻塞**；需验证或书面风险接受 |
| 最终 release revision/tag | 未冻结；当前无 tag | **未就绪**；待 B-06/B-09 关闭后创建 |
| P1/P2 阈值 | §8.1.1 提案；未批准 | **待用户批准**；批准前不构成回滚授权 |

**其他残余**：`PORT-LOC-01` 仍 `OPEN`；ACK p95 仍 `MOCK_ONLY`；NFR 4.1/4.2/4.3 仍 partial；设备/真实 BLE/LAN/TLS/云/硬件/视觉/fps 仍 `BLOCKED`；发布通道未选择；远端写、签名、安装、tag、发布均未授权。

### 6.3 后续条件

- 用户完成 §4.4 A/B/C 身份/版本/许可证决定后，应同步更新 RELEASE-001、检查单、release notes、CHANGELOG、README，并重新核对 B-01/B-05/B-06 与 §7.2 远端通道。
- 最终 release revision/tag 冻结后，必须在该 revision 上重新构建、签名、安装 smoke/升级验证，并重新记录 HAP 大小/SHA-256；不得复用 `6cd9a88` 的构建产物或 `e74a181` 的测试证据作为最终发布证据。
- 任何代码、版本、bundleName、签名配置、测试/契约或 `input/` 变化都会使本复评的相关证据失效，需 Change Impact 与重跑。

---

## 7. 独立性、限制与非声明

- **独立性**：本报告作者未参与被审文档的编写；未编辑任何被审文件；唯一写入为 `artifacts/70-review/t26-release-rereview.md`。本任务只读复核，不执行 push/fetch/pull、分支/tag 操作、签名、安装、发布或用户验收。
- **未重新构建**：HAP 为既有 release-mode 产物；本次只核对大小、SHA-256、条目、`buildMode`/`debug`、签名材料。未重新执行 clean build，未承诺构建可字节级复现。
- **未重跑 codelinter**：`0 error / 25 warning` 沿用 TEST-002；本轮未重跑。
- **未做法律审计**：Apache-2.0/NOTICE 的事实核对不等于法律意见；旧公开版本与当前树的衍生关系、许可证继承/独立/迁移仍需用户与必要时的法律顾问决定。
- **远端引用时效**：`origin/main=7d6f4c9` 为本地跟踪引用，本次未 `git fetch`；若远端已变化（新增 tag/Release 或改写 main），B-01/B-05/B-06 的旧版本分析需在授权后重新核对。
- **非声明**：不声明可安装、已签名、可发布、已发布、已推送、生产就绪、用户验收完成、设备验收完成、NFR 4.1/4.2/4.3 达标；不把 `MOCK_ONLY`（ACK p95）写成验收数据；不把 `check_layering` 0 violation 写成 100% 端口位置合规；不把 release-mode 构建成功写成签名/安装成功。

---

## 8. Handoff

```text
STATUS: COMPLETE
SUMMARY: 对 3501f5e（含 972f177/19df893/3501f5e）的 Release 资产修正做聚焦复评。F-01..F-06 核心均已闭环：公开旧版本 io.github.quirkybrain.yaocore/1.0.0/1000000/Apache-2.0+NOTICE 事实经只读核对准确；A/B/C 选项与后果完整，B-01/B-05/B-06 均标“待用户决定”，未替用户决策；B-07 三处统一为“草案已产出 @63d2235，待评审/签核”；代码证据基线 e74a181/TEST-002 与最终 release revision/tag（未冻结）区分清晰；B-09 已纳入 No-Go/R-G09/1.2.6/1.5.9；1.2.4 为 PARTIAL、1.10.3 为 PENDING；P1/P2 阈值提案完整且明确待用户批准。B-01..B-09 三文档编号/状态一致；README v1.3；5 文档 53 条相对链接 0 broken；未发现越界肯定声明；NOT_READY 保留。回归复验 host 697/697、layering 221/0/6、crosscheck 66/66 hard ALL PASS、仿真器 20/20、fixture 27/27、i18n 0 blocking/0 missing、triage 615；文档数字与 TEST-002/ACCEPT-001 一致。Verdict PASS，仅限发布准备文档修正。
ARTIFACTS_CREATED: artifacts/70-review/t26-release-rereview.md（覆写 guard 占位）
ARTIFACTS_UPDATED: none
RISKS: release 仍 NOT_READY；B-01..B-09 未关闭（B-07 仅草案待签核）；无签名/安装/设备/用户验收；远端/发布未授权；旧公开版本身份/版本/许可证未裁定；最终 release revision/tag 未冻结；P1/P2 阈值未批准；API 14 运行时/混淆裁剪未决；PORT-LOC-01 OPEN；ACK p95 MOCK_ONLY；NFR partial；HAP 未签名且非字节可复现。非阻塞观察：README 首行“开源”措辞（O-01）、release notes/CHANGELOG 的 RELEASE-001 @972f177 pin（O-02）、RELEASE-001 §4.1 “当前候选为 6cd9a88”措辞（O-03）、§11.5 扫描措辞（O-04）。
VALIDATION: reviewed HEAD=3501f5e；diff 63d2235..3501f5e 6 files +706/-142（5 个被审资产 +304/-142）；输入 pin 6/6；host 697/697 exit 0；layering files=221 violations=0 exceptions_used=6 exit 0；crosscheck 66 PASS/0 FAIL/hard ALL PASS exit 0；simulator 20/20 exit 0；fixture 27/27 exit 0；i18n 0 blocking/0 missing/73 warning/16 hardcoded exit 0；triage 615 rows OK exit 0；HAP 1,616,146 B/1602110d…/13 entries/release/unsigned；origin/main=7d6f4c9、main=a6f6558、merge-base 空、tag 空；e74a181..HEAD 代码/配置 diff exit 0；B-01..B-09 连续；53 relative links/0 broken；越界肯定词 0 命中（否定/条件语境除外）。本任务提交与 finish 输出见最终 handoff。
NEEDS_CLARIFICATION: 用户仍需决定 §4.4 A/B/C（旧公开身份/新应用身份/迁移方案，及 Apache-2.0 继承或独立许可证）；选择 §7.2 远端通道 A-E；批准 §8.1.1 P1/P2 阈值；完成 B-09 API 14/混淆裁剪决策；授权签名/安装/设备验收/远端与发布。
NEXT_ACTION: 将本 PASS 作为 wp-118 修正的复评证据；release 保持 NOT_READY。用户决定 A/B/C 与阈值后，按 B-06/B-09 冻结最终 release revision/tag，重建、签名、安装/升级 smoke 与复验；任何签名、push/PR/MR/tag 或发布仍需显式授权。
```

---

*T26-RELEASE-REREVIEW 结束。本报告只完成 `3501f5e` 的 Release 准备文档聚焦复评；`PASS` 不改变 `NOT_READY`，也不授予任何发布、签名、远端或用户验收权限。*
