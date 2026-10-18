# wp-113 Release 准备计划合并报告（task/wp-112-release-plan → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: `wp-113-merge-release-plan`（`repository_action: merge`）
- **Handoff**: `state/handoffs/wp-113-merge-release-plan.json`（pin + snapshot + begin 已由 Orchestrator 完成；本报告提交后运行 `finish wp-113-merge-release-plan`）
- **日期**: 2026-10-18
- **结果**: **MERGE 成功（`--no-ff`，无冲突）；合并结果上三项验证全部退出 0（host 697/697、crosscheck `hard checks: ALL PASS` 66/66、layering 0 violation）**。RELEASE-001 的 Verdict 保持 **`NOT_READY`**。本报告是集成证据，**不替代任何 Gate 判定、不构成发布授权**。

## 1. 预检（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree；任务期间未建新 worktree） |
| 当前分支 | `feat/yaocore-app`（= handoff `base_branch`、`target_branch`；未切换） |
| 目标 HEAD | `6cd9a88d0fdc1b08cc6ffca233c12c41df737519`（= handoff `base_commit` 与 `feat/yaocore-app` tip；`chore(release): 目标扩展至 release 准备（不发布）`） |
| 来源分支 | `task/wp-112-release-plan` @ `560d08a9e76ac949c0a00b51500fcedee137958b`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `6cd9a88`（目标 tip 是来源 tip 的直接祖先，无分叉） |
| 工作区 | 干净（`git status --porcelain` 无输出）；HEAD 未脱离 |
| 守卫状态 | ACTIVE `wp-113-merge-release-plan`；快照 `refs/swe/snapshots/20261018T105201Z-wp-113-merge-release-plan-876a729d` @ `073e66b9f5fd0771fc749a1f98194492793c838b` |
| 远端 | 按任务“仅本地”要求**未 fetch、未 pull、未 push**，未改写远端跟踪引用 |
| 其他分支 | 全部 `task/*` 与 `main` 均未移动、未切换、未删除；`task/wp-112-release-plan` 保留 |

冻结输入哈希复核（与 handoff pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- `gate_evidence_path` `artifacts/85-release/release-plan.md`：合并后 blob sha256 `3e2cd6158216f58d2a84cad9bc1bb2e87a9c84c29aee3252c58399bc02756411`（= handoff `gate_evidence_path_sha256`）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用 `config/git-policy.default.md` 默认规范，无公司策略覆盖）

来源提交核对（`git log --oneline 6cd9a88..560d08a`，1 个，与任务描述一致）：

```text
560d08a docs(release): 发布就绪评估与检查单
```

来源交付物（`git show --stat 560d08a`）：

```text
artifacts/85-release/release-plan.md | 476 ++++++++++++++++++++++++++++++++++-
docs/release-checklist.md            | 307 ++++++++++++++++++++++
2 files changed, 780 insertions(+), 3 deletions(-)
```

## 2. 合并

- 命令：`git merge --no-ff task/wp-112-release-plan -m "chore(merge): 合并 release 准备计划与检查单"`
- 合并提交：`40fe2a8895aa80fb4ef2191fdd973e3da3d5e1f1`（主题 `chore(merge): 合并 release 准备计划与检查单`）
- 父提交：`6cd9a88`（目标，第一父）+ `560d08a`（来源，第二父）
- 策略：`ort`；**无冲突**（未手工编辑任何文件）
- 树一致性：目标自 base 后无独立提交，`git diff --quiet 40fe2a8 560d08a` 退出 0，合并结果树与来源 tip 完全一致
- 合并范围：**2 个路径，+780 / −3** —— `artifacts/85-release/release-plan.md`（+476 / −3）与 `docs/release-checklist.md`（新建，307 行）；全部落在 handoff `writes` 内（`artifacts/85-release/`、`docs/`）；未触及 `input/`、产品代码、测试断言、工具、契约或构建配置
- `docs/` 受 `.gitignore` 忽略，但来源分支已以 `-f` 提交检查单；合并后 `docs/release-checklist.md` 仍为已跟踪文件

## 3. 合并后验证（在 `40fe2a8` 上实际执行，早于任何证据改动）

| # | 检查 | 命令 | 实测结果 | 退出码 |
|---|---|---|---|---|
| 1 | Host 测试 | `PYTHONDONTWRITEBYTECODE=1 entry/src/test/run-host-tests.sh` | **697/697 PASS**：`1..697`、`# tests 697 / # pass 697 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`；`duration_ms 3604.514874` | 0 |
| 2 | 协议资产交叉校验 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py` | **`hard checks: ALL PASS`**：66 条 `[PASS]` / 0 条 `[FAIL]`；14 条既有 frozen-input `FINDING`（非阻塞） | 0 |
| 3 | 分层检查 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | **PASS**：`files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0` | 0 |

补充：三项检查与 documentation 合并（§18.2）及 TEST-002 的基线一致；命令均在合并提交的干净工作树上运行，统一设置 `PYTHONDONTWRITEBYTECODE=1`；运行后已清理 `__pycache__`；完整日志暂存于 `/tmp/opencode/wp113/`（未提交）。构建 / lint 未在本次合并中重跑，仍引用 TEST-002 @ `e74a181` 的 `BUILD SUCCESSFUL` 与 `codelinter 0 error / 25 warning`。

交付物内容检查：`artifacts/85-release/release-plan.md` 474 行（RELEASE-001 完整评估）、`docs/release-checklist.md` 307 行（发布检查单），均存在且非占位。文中出现的 `TODO` 是对既有 README 许可证占位的事实描述（B-01），不是本次交付物的未完成占位。

## 4. RELEASE-001 裁定与阻塞项

RELEASE-001 的 Release Verdict 为 **`NOT_READY`**（不满足发布授权条件）；以下 8 项阻塞在合并时点全部 **未关闭**，任一项未关闭即不得进入发布授权或市场/远端发布：

| # | 阻塞项 | 摘要 |
|---|---|---|
| B-01 | 项目级许可证未定 | 无 `LICENSE`；README 仍为 TODO；不得假定可再分发 |
| B-02 | 无签名配置，HAP 不可安装 | `signingConfigs: []`；构建跳过签名；产物未签名 |
| B-03 | 设备/用户验收未执行 | ACCEPT-001 U-01..U-12 均 NOT RUN/BLOCKED；无 `hdc` target |
| B-04 | GAP-AC-01..03 未决 | LAN IP 显示、多家庭切换交互、房间图标接线未决 |
| B-05 | 远端/发布通道未授权 | 未 push；无 tag；远端策略与保护分支/CI 未就绪 |
| B-06 | 发布标识/版本/构建模式未冻结 | bundleName/vendor/version 待确认；未签名产物为 `buildMode=debug` |
| B-07 | CHANGELOG/Release Notes 缺失 | 无 `CHANGELOG.md` 与正式 release notes |
| B-08 | 残余风险未逐项书面确认 | PORT-LOC-01、i18n 残余、设备 BLOCKED、ACK p95 `MOCK_ONLY`、NFR partial、lint/覆盖率缺口等 |

权威文本：`artifacts/85-release/release-plan.md` §3（阻塞项）、§8（发布 Gate 条件）、`docs/release-checklist.md`。

## 5. 证据更新

- `artifacts/90-integration/integration-report.md` 追加 **§19「release 准备计划合并记录（2026-10-18，wp-113）」**：源/目标分支、合并提交与双亲、1 个源提交、2 个合并路径、三项验证矩阵、交付物检查、RELEASE-001 Verdict 与 B-01..B-08、未授权边界。
- 追加内容不回写 §1–§18 的历史结论；§18 仍是 documentation 合并记录，§19 只记录 release 准备交付物进入集成分支。
- 本报告与上述 §19 同属唯一证据提交，路径均在 handoff `deliverables` 内。

## 6. 门禁引用

- 门禁证据：`artifacts/85-release/release-plan.md`（sha256 `3e2cd615…` = handoff pin）。
- 关联 Gate：G-018 documentation Stage Gate PASS @ `eb67a94`；release Stage Gate **未判定**，发布动作**未授权**。
- 结论：本次合并只表示 RELEASE-001 发布准备计划与检查单已进入集成分支，**不构成 release Gate PASS、独立评审、发布授权、部署授权、签名授权或用户验收**；Stage Gate 与发布决策归 Orchestrator / 用户。

## 7. 工作树与分支状态（报告提交后）

| 项 | 值 |
|---|---|
| 当前分支 / HEAD | `feat/yaocore-app` / 本报告提交（父提交 `40fe2a8`；SHA 由 `git rev-parse HEAD` 读取，无法写入自身） |
| 来源分支 | `task/wp-112-release-plan` @ `560d08a`，未删除、未移动 |
| 工作区 | 干净；本任务仅新增 `state/reports/wp-113-merge-report.md` 与追加 `artifacts/90-integration/integration-report.md`（`state/` 受 `.gitignore` 忽略，按 handoff 以 `git add -f` 纳入） |
| 未提交 / 未跟踪 | 无（ignored 构建产物除外） |
| 远端 | 未 push / fetch / pull；未创建 PR/MR；未创建 tag；未签名 |

## 8. 冲突

**无冲突**。`ort` 自动合并；目标 tip 是来源 tip 的直接祖先；两个路径均来自来源历史，无目标侧独立改动，无删除/重命名冲突。

## 9. 残余与后续建议

1. **release Gate 未判定**：RELEASE-001 为 `NOT_READY`，B-01..B-08 全部未关闭；不得以“三项检查 PASS”替代发布授权。
2. **B-01 许可证**：项目所有者选择 SPDX 许可证并提交 `LICENSE`/`NOTICE`，完成依赖许可证核对。
3. **B-02 签名**：用户提供证书/Profile/密钥库与口令（不入库），完成签名校验与安装 smoke。
4. **B-03/B-04 验收与偏离**：执行 BLK-01..08，或用户书面接受残余并限定范围；GAP-AC-01..03 需书面接受或 bounded fix。
5. **B-05 远端/通道**：按 `main_merge_mode: review_request_when_remote` 走 PR/MR，需用户显式授权；不得强推或改写共享历史。
6. **B-06/B-07 发布制品**：确认 bundleName/vendor/version，以 `buildMode=release` 重新干净构建；补齐 `CHANGELOG.md` 与 release notes。
7. **B-08 风险签核**：在发布 Gate 记录中逐项接受或派发修复；设备/真实 BLE/LAN/TLS/云/视觉/fps 仍 `BLOCKED`/`UNAVAILABLE`，ACK p95 仅 `MOCK_ONLY`。
8. **构建 / lint**：本次未重跑，仍引用 TEST-002 @ `e74a181`；产品代码自 `e74a181` 未变。
