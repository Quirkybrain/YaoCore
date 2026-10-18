# wp-120 Release 文档合并报告（task/wp-118-release-consistency → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: `wp-120-merge-release-notes`（`repository_action: merge`）
- **Handoff**: `state/handoffs/wp-120-merge-release-notes.json`（pin + snapshot + begin 由 Orchestrator 完成；本报告提交后运行 `finish wp-120-merge-release-notes`）
- **日期**: 2026-10-18
- **结果**: **MERGE 成功（`--no-ff`，无冲突）；合并结果上三项验证全部退出 0（host 697/697、crosscheck `hard checks: ALL PASS` 66/66、layering 0 violation）**。RELEASE-001 的 Verdict 保持 **`NOT_READY`**。本报告是集成证据，**不替代任何 Gate 判定、不构成发布授权**。

## 1. 预检（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree；任务期间未建新 worktree） |
| 当前分支 | `feat/yaocore-app`（= handoff `base_branch`、`target_branch`；未切换） |
| 目标 HEAD | `b716207eee7ac07fe3b08edba9f9e193cb38f2c8`（= handoff `base_commit` 与 `feat/yaocore-app` tip；`docs(repo): 记录 release 准备合并证据`） |
| 来源分支 | `task/wp-118-release-consistency` @ `1e955a8d7f4fa8890c195f7097e7ee215104fe7e`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `b716207`（目标 tip 是来源 tip 的直接祖先，无分叉） |
| 工作区 | 干净（`git status --porcelain` 无输出）；HEAD 未脱离 |
| 守卫状态 | ACTIVE `wp-120-merge-release-notes`；快照 `refs/swe/snapshots/20261018T111820Z-wp-120-merge-release-notes-ea1e8083` @ `072362e03162c331dbfa351ef79bfa0b014a8498` |
| 远端 | 按任务“仅本地”要求**未 fetch、未 pull、未 push**，未改写远端跟踪引用 |
| 其他分支 | 全部 `task/*` 与 `main` 均未移动、未切换、未删除；`task/wp-118-release-consistency` 保留 |

冻结输入哈希复核（与 handoff pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- `gate_evidence_path` `artifacts/70-review/t26-release-rereview.md`：来源 blob sha256 `f4ed5a80a74df61c611bfab5a77407d773cf2fd08f85ca4fed59c2e8dc9cc476`（= handoff `gate_evidence_path_sha256`；合并后文件字节一致）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用 `config/git-policy.default.md` 默认规范，无公司策略覆盖）

来源提交核对（`git log --oneline b716207..1e955a8`，6 个，与任务描述一致）：

```text
1e955a8 docs(review): Release 修正聚焦复评
3501f5e docs(release): 统一发布文档交叉引用
19df893 docs(release): 同步发布说明 B-09 与身份分析
972f177 docs(release): 修正发布计划与检查单（F-01..F-06）
f1fbe0d docs(review): Release 准备资产独立复审
63d2235 docs(release): 添加 CHANGELOG 与 v1.0.0 发布说明
```

来源变更规模（`git diff --numstat b716207..1e955a8`）：

```text
128  0   CHANGELOG.md
29   3   README.md
276  0   artifacts/70-review/t26-release-rereview.md
402  0   artifacts/70-review/t26-release-review.md
150  62  artifacts/85-release/release-plan.md
52   47  docs/release-checklist.md
221  0   docs/release-notes-v1.0.0.md
```

## 2. 合并

- 命令：`git merge --no-ff task/wp-118-release-consistency -m "chore(merge): 合并 release 发布说明与修正"`
- 合并提交：`21c601d5234b1e313c811fb395140a09b5dd06d7`（主题 `chore(merge): 合并 release 发布说明与修正`）
- 父提交：`b716207`（目标，第一父）+ `1e955a8`（来源，第二父）
- 策略：`ort`；**无冲突**（未手工编辑任何文件）
- 树一致性：目标自 base 后无独立提交，`git diff --quiet 21c601d 1e955a8` 退出 0，合并结果树与来源 tip 完全一致
- 合并范围：**7 个路径，+1258 / −112** —— `CHANGELOG.md`（+128/−0）、`README.md`（+29/−3）、`artifacts/70-review/t26-release-review.md`（+402/−0）、`artifacts/70-review/t26-release-rereview.md`（+276/−0）、`artifacts/85-release/release-plan.md`（+150/−62）、`docs/release-checklist.md`（+52/−47）、`docs/release-notes-v1.0.0.md`（+221/−0）；全部落在 handoff `writes` 内（`CHANGELOG.md`、`README.md`、`docs/`、`artifacts/85-release/`、`artifacts/70-review/`、`artifacts/90-integration/`）；未触及 `input/`、产品代码、测试断言、工具、契约或构建配置
- `docs/` 受 `.gitignore` 忽略，但来源分支已以 `-f` 提交上述文件；合并后 `CHANGELOG.md`、`docs/release-notes-v1.0.0.md`、`docs/release-checklist.md`、`artifacts/85-release/release-plan.md` 均仍为已跟踪文件

## 3. 合并后验证（在 `21c601d` 上实际执行，早于任何证据改动）

| # | 检查 | 命令 | 实测结果 | 退出码 |
|---|---|---|---|---|
| 1 | Host 测试 | `PYTHONDONTWRITEBYTECODE=1 entry/src/test/run-host-tests.sh` | **697/697 PASS**：`1..697`、`# tests 697 / # pass 697 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`；`duration_ms 3516.551613` | 0 |
| 2 | 协议资产交叉校验 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py` | **`hard checks: ALL PASS`**：66 条 `[PASS]` / 0 条 `[FAIL]`；14 条既有 frozen-input `FINDING`（非阻塞） | 0 |
| 3 | 分层检查 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | **PASS**：`files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0` | 0 |

补充：三项检查均在合并提交的干净工作树上运行，与 §18.2/§19.2 的既有基线一致（host 697/697、crosscheck 66/66、layering `files=221 / 0 violation`）。命令统一设置 `PYTHONDONTWRITEBYTECODE=1`；运行后 `git status --porcelain` 无输出；`__pycache__` 已在证据提交前清理；完整日志暂存于 `/tmp/opencode/wp120/`（未提交）。构建 / lint 未在本次合并中重跑，仍引用 TEST-002 @ `e74a181` 的 `BUILD SUCCESSFUL` 与 `codelinter 0 error / 25 warning`。

范围检查：`git diff --stat b716207..21c601d -- entry/src tools contracts input build-profile.json5 AppScope/app.json5 oh-package.json5 entry/oh-package.json5 hvigorfile.ts` 为空（产品代码、测试、工具、契约、构建配置与 `input/` 未变）。

## 4. 交付物与文档检查

| 文件 | 合并后状态 | sha256（合并后） | 说明 |
|---|---|---|---|
| `CHANGELOG.md` | 128 行；新建 | `d96d6df572f8b7d1cf3fc8414aae3d9f45abf12a3eb3c13f13a63d6a042a299d` | `Status: DRAFT`；`[1.0.0]` 明示为发布准备基线，不是发布记录 |
| `docs/release-notes-v1.0.0.md` | 221 行；新建 | `4fdf237325dc6f336d9fad3f5548cedc3b71eafdfd30fa14e2ec8cb585b0467a` | `DRAFT / NOT_READY`；§1.1 记录公开旧版本身份/版本/许可证待决 |
| `artifacts/85-release/release-plan.md` | 562 行 | `ea38c7ccf1fe3642b255a67103fc4e172fea6c977964795fbe65d91103b93dfc` | RELEASE-001；`Release Verdict: NOT_READY`；F-01..F-06 修订完成 |
| `docs/release-checklist.md` | 312 行 | `b8a36d5366ffb890746575d019a616191232d3a0ca2e7d3333d1e5260dca004f` | RELEASE-CHECKLIST-001 v1.1；`Current verdict: NOT_READY` |

占位扫描：`TODO` 仅出现在“许可证仍为 TODO / README 标 TODO”的**事实描述**（B-01），不是交付物的未完成占位；未发现 `TBD`、`FIXME`、`待填写` 或 Lorem 占位。

越界表述扫描：未发现肯定式“已发布 / 已推送 / 已签名 / 已上架 / 生产就绪 / 可安装 / 可发布”等声明；命中均为否定、禁止、条件或状态要求语境（如 `## [Unreleased]`、“没有正式发布渠道”、“正式发布前必须…”）。四份文档均保留 `NOT_READY`/未发布口径。

## 5. 复评 PASS 的范围

`artifacts/70-review/t26-release-rereview.md`（T26-RELEASE-REREVIEW，Producer `agent:quality-reviewer`；source blob sha256 `f4ed5a80…` = handoff pin）的 `PASS` 只覆盖 **`3501f5e` 的发布准备文档修正**：

- F-01..F-06 核心闭环；B-01..B-09 三文档编号/状态一致；README v1.3；5 文档 53 条相对链接 0 broken；无越界肯定声明；
- 回归复验 host 697/697、layering 221/0/6、crosscheck 66/66 hard ALL PASS、仿真器 20/20、fixture 27/27、i18n 0 blocking/0 missing、triage 615 行一致；
- 非阻塞观察 O-01..O-04 保留待后续维护轮（README 首行“开源”措辞、`972f177` pin、§4.1 “当前候选为 6cd9a88”措辞、§11.5 扫描措辞）。

**范围限制**：复评未重新 clean build、未重跑 codelinter、未做设备/签名/远端/用户验收，也未做法律级许可证审计。源 tip `1e955a8` 相对 `3501f5e` 只新增该复评报告本身；被审文档字节未变（`git diff --quiet 3501f5e 1e955a8 -- CHANGELOG.md README.md docs/ artifacts/85-release/` 退出 0）。该 `PASS` **不是 release 批准**，`NOT_READY` 未被改变。

## 6. B-01..B-09 与未授权边界

合并时点 **B-01..B-09 全部未关闭**（B-07 为“草案已产出 @ `63d2235`，待评审/签核”的部分进展）：

| # | 阻塞项 | 当前状态 |
|---|---|---|
| B-01 | 项目级许可证未定（公开旧版本 Apache-2.0 + NOTICE 关系未裁定） | 待用户 A/B/C 决定 |
| B-02 | 无签名配置，未签名 HAP 不可安装 | 阻塞 |
| B-03 | 设备/用户验收未执行（U-01..U-12、BLK-01..08） | 阻塞 |
| B-04 | GAP-AC-01..03 未决 | 待用户接受或 bounded fix |
| B-05 | 远端/发布通道未授权 | 阻塞 |
| B-06 | 发布标识/版本/构建模式未冻结 | 待 A/B/C 决定 |
| B-07 | CHANGELOG / Release Notes 已产出草案 | 部分进展；待评审/签核，不得写成已定稿 |
| B-08 | 残余风险未逐项书面确认 | 阻塞 |
| B-09 | 构建硬化 / API 14 运行时兼容未决 | 阻塞 |

未授权边界（本任务严格遵守）：

1. **仅本地合并**：未 fetch、未 pull、未 push、未创建 PR/MR、未创建或删除 tag、未签名、未安装、未执行任何应用市场或远端发布写操作。
2. 未切换分支；`task/wp-118-release-consistency` 分支保留，未删除、未移动；未改动任何已评审提交。
3. 合并与验证结果只证明 6 个源提交已以 `--no-ff` 进入 `feat/yaocore-app`，并在合并结果上重跑三项检查；**不构成 release Gate PASS、独立评审、发布授权、部署授权、签名授权、tag 授权或用户验收**。
4. Release 仍为 `NOT_READY`；最终 release revision/tag 未冻结。发布相关裁定归 Orchestrator / 用户。

## 7. 证据更新

- `artifacts/90-integration/integration-report.md` 追加 **§20「Release 文档合并记录（2026-10-18，wp-120）」**：源/目标分支、合并提交与双亲、6 个源提交、7 个合并路径、三项验证矩阵、四份文档存在性/哈希/占位与越界扫描、复评 PASS 范围、B-01..B-09 与发布未授权边界。
- 追加内容不回写 §1–§19 的历史结论；§19 仍是 release 准备计划合并记录，§20 只记录 release 文档进入集成分支。
- 本报告与上述 §20 同属唯一证据提交，路径均在 handoff `deliverables` 内。

## 8. 门禁引用

- 门禁证据：`artifacts/70-review/t26-release-rereview.md`（source blob sha256 `f4ed5a80…` = handoff pin）。
- 关联记录：RELEASE-001 `NOT_READY`；T26-RELEASE-REREVIEW `PASS`（仅限 `3501f5e` 发布准备文档修正）；release Stage Gate **未判定**，发布动作**未授权**。
- 结论：本次合并只表示 release 文档修正已进入集成分支，**不构成 release Gate PASS、独立评审、发布授权、部署授权、签名授权或用户验收**。

## 9. 工作树与分支状态（报告提交后）

| 项 | 值 |
|---|---|
| 当前分支 / HEAD | `feat/yaocore-app` / 本报告提交（父提交 `21c601d`；SHA 由 `git rev-parse HEAD` 读取，无法写入自身） |
| 来源分支 | `task/wp-118-release-consistency` @ `1e955a8`，未删除、未移动 |
| 工作区 | 干净；本任务仅追加 `artifacts/90-integration/integration-report.md` 与新增 `state/reports/wp-120-merge-report.md`（`state/` 受 `.gitignore` 忽略，按 handoff 以 `git add -f` 纳入） |
| 未提交 / 未跟踪 | 无（ignored 构建产物除外） |
| 远端 | 未 push / fetch / pull；未创建 PR/MR；未创建 tag；未签名 |

## 10. 冲突

**无冲突**。`ort` 自动合并；目标 tip 是来源 tip 的直接祖先；7 个路径均来自来源历史，无目标侧独立改动，无删除/重命名冲突。

## 11. 残余与后续建议

1. **release Gate 未判定**：RELEASE-001 为 `NOT_READY`，B-01..B-09 全部未关闭（B-07 部分进展）；不得以“三项检查 PASS”替代发布授权。
2. **B-01/B-06**：用户决定公开旧版本身份/版本/许可证 A/B/C 路径，随后提交 `LICENSE`/`NOTICE` 并冻结 bundleName/version。
3. **B-02**：用户提供证书/Profile/密钥库与口令（不入库），完成签名校验与安装 smoke。
4. **B-03/B-04**：执行 BLK-01..08、U-01..U-12，或用户书面接受残余并限定范围；GAP-AC-01..03 需书面接受或 bounded fix。
5. **B-05**：远端/通道与 push/PR/MR/tag 均需用户显式授权；按 `main_merge_mode: review_request_when_remote` 走托管评审。
6. **B-07**：CHANGELOG/Release Notes 完成评审与发布负责人签核，不得写成已定稿。
7. **B-08/B-09**：在发布 Gate 记录中逐项签核残余风险；完成 API 14 运行时验证或书面风险接受，并记录混淆/裁剪与符号化方案。
8. **非阻塞观察 O-01..O-04**：在后续发布文档维护轮处理；不影响本次合并。
9. **构建 / lint**：本次未重跑，仍引用 TEST-002 @ `e74a181`；产品代码自 `e74a181` 未变。
