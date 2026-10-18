# wp-122 设备验收包合并报告（task/wp-121-device-acceptance → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: `wp-122-merge-device-kit`（`repository_action: merge`）
- **Handoff**: `state/handoffs/wp-122-merge-device-kit.json`（pin + snapshot + begin 由 Orchestrator 完成；本报告提交后运行 `finish wp-122-merge-device-kit`）
- **日期**: 2026-10-19
- **结果**: **MERGE 成功（`--no-ff`，无冲突）；合并结果上四项验证全部退出 0（模板 31/31 NOT_RUN + secret clean、self-test 18/18、host 697/697、layering 0 violation）**。设备测试**未执行**，包状态仅为 `READY_FOR_USER_EXECUTION`；本报告是集成证据，**不替代 Gate 判定、不构成设备验收或发布授权**。

## 1. 预检（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree；任务期间未建新 worktree） |
| 当前分支 | `feat/yaocore-app`（= handoff `base_branch` / `target_branch`；未切换） |
| 目标 HEAD | `938867e84a42b860230cdb1ce6a1c3d84a8e246a`（= handoff `base_commit`；`chore(acceptance): 启动设备验收（不使用原仓库）`） |
| 来源分支 | `task/wp-121-device-acceptance` @ `7b0ab0c385fa8a44e24b545378afd81609138aa2`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `938867e`（`git merge-base HEAD task/wp-121-device-acceptance` 实查一致；目标 tip 是来源 tip 的直接祖先，无分叉） |
| 工作区 | 干净（`git status --porcelain` 无输出）；HEAD 未脱离 |
| 守卫状态 | ACTIVE `wp-122-merge-device-kit`；快照 `refs/swe/snapshots/20261018T183809Z-wp-122-merge-device-kit-760ca9e5` @ `c5d8a7f322a2d6ceba8134aca4aae07559db0d01` |
| 远端 | 按任务“仅本地”要求**未 fetch、未 pull、未 push**；未接触 `origin`，未创建 PR/MR |
| 其他分支 | 未切换、未移动、未删除；`task/wp-121-device-acceptance` 合并后保留 |

冻结输入哈希复核（与 handoff pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`，实查存在于第 20 行）
- `gate_evidence_path` `artifacts/75-device-acceptance/device-acceptance-plan.md`：来源 blob sha256 `a108481e3a81d018c4b98ad211b772da4099da46f5d1c02ceca36bc48a7dbc37`（= handoff `gate_evidence_path_sha256`；合并后文件字节一致）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用 `config/git-policy.default.md` 默认规范，无公司策略覆盖）

来源提交与路径核对（`git log --oneline 938867e..7b0ab0c`，1 个，与任务描述一致）：

```text
7b0ab0c test(acceptance): 产出设备验收包与证据校验
```

`git show --stat 7b0ab0c` 核对为 **5 个路径**（与任务描述一致）：

```text
151  0   artifacts/75-device-acceptance/defect-report-template.md
961  3   artifacts/75-device-acceptance/device-acceptance-plan.md
32   0   artifacts/75-device-acceptance/device-evidence-template.csv
41   0   artifacts/75-device-acceptance/evidence/README.md
776  0   tools/acceptance/validate_device_evidence.py
```

## 2. 合并

- 命令：`git merge --no-ff task/wp-121-device-acceptance -m "chore(merge): 合并设备验收包"`
- 合并提交：`51ac14c9e73b1ec98e046d9e3b638c3414adbd4a`（主题 `chore(merge): 合并设备验收包`）
- 父提交：`938867e`（目标，第一父）+ `7b0ab0c`（来源，第二父）
- 策略：`ort`；**无冲突**（未手工编辑任何文件；`grep` 未发现冲突标记）
- 树一致性：目标自 base 后无独立提交，`git diff --quiet 51ac14c 7b0ab0c` 退出 0，合并结果树与来源 tip 完全一致
- 合并范围：**5 个路径，+1961 / −3** —— `device-acceptance-plan.md`（+961/−3）、`device-evidence-template.csv`（+32/−0）、`defect-report-template.md`（+151/−0）、`evidence/README.md`（+41/−0）、`tools/acceptance/validate_device_evidence.py`（+776/−0）；全部落在 handoff `writes`（`artifacts/75-device-acceptance/`、`tools/acceptance/`、`artifacts/90-integration/`）内
- 范围检查：`git diff --stat 938867e..51ac14c -- . ':(exclude)artifacts/75-device-acceptance/' ':(exclude)tools/acceptance/'` 为空；未改产品代码、测试、契约、构建配置、`input/`、Gate 或状态文件

## 3. 合并后验证（在 `51ac14c` 上实际执行，早于任何证据改动）

| # | 检查 | 命令 | 实测结果 | 退出码 |
|---|---|---|---|---|
| 1 | 模板校验 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/acceptance/validate_device_evidence.py --template artifacts/75-device-acceptance/device-evidence-template.csv` | **`validate_device_evidence: OK mode=template`**：`rows: 31`、`results: {'BLOCKED': 0, 'FAIL': 0, 'NOT_RUN': 31, 'PASS': 0}`、`plan_sections: 31`、`secret_scan: clean` | 0 |
| 2 | 校验器自检 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/acceptance/validate_device_evidence.py --self-test` | **`SELF-TEST: 18 checks passed`**：18 条 `[PASS]`，覆盖模板接受、严格 PASS、重复 ID/非法结果/非法哈希/非法日期/未确认脱敏、PASS 缺 actual/证据/非零哈希、秘密赋值/长十六进制、缺列、计划不匹配、CRLF 拒绝、模板跳过路径存在性、BLOCKED 行接受 | 0 |
| 3 | Host 测试 | `PYTHONDONTWRITEBYTECODE=1 entry/src/test/run-host-tests.sh` | **697/697 PASS**：`1..697`、`# tests 697 / # pass 697 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`；`duration_ms 3953.384259` | 0 |
| 4 | 分层检查 | `PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py` | **PASS**：`files=221 violations=0 exceptions_used=6 pending=0 pending_used=0 port_exceptions_used=0 port_pending=0 port_pending_used=0` | 0 |

补充：四项检查均在合并提交的干净工作树上、早于任何证据改动运行；命令统一设置 `PYTHONDONTWRITEBYTECODE=1`；运行后 `git status --porcelain` 无输出；`__pycache__` 已清理；完整日志暂存于 `/tmp/opencode/wp122/`（未提交）。本包为纯文档/工具新增，未重跑构建与 lint；产品代码自 TEST-002 `e74a181` 未变。模板校验的 `secret_scan: clean` 是校验器对 CSV 自由文本字段的**保守模式扫描**，不构成完整安全审计。

## 4. 交付物与覆盖范围

| 文件 | 合并后状态 | sha256（合并后） | 说明 |
|---|---|---|---|
| `artifacts/75-device-acceptance/device-acceptance-plan.md` | 962 行 | `a108481e3a81d018c4b98ad211b772da4099da46f5d1c02ceca36bc48a7dbc37` | DEVICE-ACCEPT-001 v1.0；`READY_FOR_USER_EXECUTION`；31 用例、环境矩阵、证据/脱敏规则、判定/缺陷/复验流程、BLK/U 追溯、非声明 |
| `artifacts/75-device-acceptance/device-evidence-template.csv` | 32 行（31 数据行 + 表头） | `76aaef574bff128fc37da316db36bfd39fc3cb87d4a72c4481aa3f0c4eb66ba2` | 31 条 `NOT_RUN`；S1 20 / S2 11；全零 hash/TBD 哨兵；执行后回填并运行严格校验 |
| `artifacts/75-device-acceptance/defect-report-template.md` | 151 行 | `f1b6b2d13fc677a06750bb548728b1c434b7825a83e70cb12a8b9f789119def5` | DEVICE-DEFECT-TEMPLATE-001；`TEMPLATE`，无真实缺陷 |
| `artifacts/75-device-acceptance/evidence/README.md` | 41 行 | `da9b1c68e724dc7fa5dbc3536b61a64cda95709c5e38cb78419181926c648ff1` | 证据目录/命名/脱敏/复验规则 |
| `tools/acceptance/validate_device_evidence.py` | 776 行 | `6e3150fe42cd509e494f6ba1892f66724da58013975328766c240d2521b3b17a` | 模板/严格校验 + 18 项自检；仅用 Python 标准库 |

覆盖范围（权威文本在计划 §4.1/§7）：

- 用例编号 `DA-001..DA-031`，S1 20 条 / S2 11 条；覆盖安装升级、BLE 配网、LAN HMAC、TLS pinning、华为云 IoTDA、设备类型/硬件、房间/家庭/场景、i18n/视觉/A11y、性能、安全恢复与存储、Hypium/onDeviceTest。
- 追溯覆盖 `BLK-01..BLK-08` 与 `U-01..U-12`，并覆盖 PRD 的 26 个 FR 与 NFR 4.1/4.2/4.3 的用户侧验证点；每个 CSV `case_id` 在计划中有且仅有一个 `### DA-xxx` 章节（校验器 `plan_sections: 31` 佐证）。
- CSV 当前全部为 `NOT_RUN`，`BLOCKED`/`FAIL`/`PASS` 均为 0；模板校验通过只证明包结构、按计划回填的一致性与无模板级秘密，**不证明设备行为**。

## 5. 设备未执行与边界声明

1. **设备测试未执行**：无签名 HAP、无目标 HarmonyOS NEXT 设备、无真实 ESP32-S3 网关/固件、无华为云 IoTDA Token、无真实性能/视觉/A11y 测量环境；31 条用例全部 `NOT_RUN`，无任何设备 PASS。
2. **不构成用户验收或 release 授权**：本包状态仅为 `READY_FOR_USER_EXECUTION`；不关闭 B-03/B-04，不判定 release Stage Gate，不构成发布、部署、签名、tag 或用户验收授权；RELEASE-001 仍为 `NOT_READY`。
3. **执行前提未变**：用户仍需作出身份 A/B/C、GAP-AC-01..03、P-HMAC/TLS 与风险接受等决定（计划 §2.1）；`DA-002` 仅身份 A 可执行，B/C 时记 `BLOCKED`；当前 `com.example.yaocore` 不得宣称覆盖升级成功。
4. **仅本地边界**：未 fetch/pull/push、未创建 PR/MR、未接触 `origin`、未创建或删除 tag、未签名/安装；未切换分支，`task/wp-121-device-acceptance` 保留；未改动任何已评审提交。
5. **校验范围**：host 697/697 与 layering 0 violation 证明合并未引入代码级回归；`secret_scan: clean` 仅为校验器保守扫描；二者均不能替代设备证据、独立评审或用户签核。

## 6. 合并后验证与证据更新

- `artifacts/90-integration/integration-report.md` 追加 **§21「设备验收包合并记录（2026-10-19，wp-122）」**：源/目标分支、合并提交与双亲、1 个源提交、5 个合并路径、四项验证矩阵、5 个交付物哈希与行数、31 用例覆盖范围/严重度分布、设备未执行与不使用原仓库边界。
- 追加内容不回写 §1–§20 的历史结论；§21 只记录设备验收包进入集成分支。
- 本报告与上述 §21 同属唯一证据提交，路径均在 handoff `deliverables` 内。

## 7. 门禁引用

- 门禁证据（handoff pin）：`artifacts/75-device-acceptance/device-acceptance-plan.md`（source/merged blob sha256 `a108481e…`）。
- 关联记录：DEVICE-ACCEPT-001 `READY_FOR_USER_EXECUTION`；RELEASE-001 `NOT_READY`；B-03/B-04 仍未关闭。
- 结论：本次合并只表示设备验收准备包已进入 `feat/yaocore-app`，**不构成设备验收 PASS、用户验收、独立评审、release Gate PASS 或发布授权**。

## 8. 工作树与分支状态（报告提交后）

| 项 | 值 |
|---|---|
| 当前分支 / HEAD | `feat/yaocore-app` / 本报告提交（父提交 `51ac14c`；SHA 由 `git rev-parse HEAD` 读取，无法写入自身） |
| 来源分支 | `task/wp-121-device-acceptance` @ `7b0ab0c`，未删除、未移动 |
| 工作区 | 干净；本任务仅追加 `artifacts/90-integration/integration-report.md` 与新增 `state/reports/wp-122-merge-report.md`（`state/` 受 `.gitignore` 忽略，按 handoff 以 `git add -f` 纳入） |
| 未提交 / 未跟踪 | 无（ignored 构建产物除外） |
| 远端 | 未 push / fetch / pull；未创建 PR/MR；未创建 tag；未签名 |

## 9. 冲突

**无冲突**。`ort` 自动合并；目标 tip 是来源 tip 的直接祖先；5 个路径均来自来源历史，无目标侧独立改动，无删除/重命名冲突。

## 10. 残余与后续建议

1. **设备执行未开始**：用户需按计划 §2/§6 准备签名 HAP、HarmonyOS NEXT 设备、ESP32-S3 网关/固件、IoTDA Token 与测量环境；执行后回填 CSV、脱敏并运行严格校验。
2. **决策前置**：身份 A/B/C、GAP-AC-01..03、P-HMAC/TLS 与风险接受需用户书面决定；未决期间对应用例记 `BLOCKED`，不得猜测产品失败。
3. **Gate 未判定**：本次合并不改变 B-03/B-04 状态，也不改变 RELEASE-001 `NOT_READY`；设备证据回填、独立评审与用户签核后再进入相应 Gate。
4. **远端仍未授权**：任何 push / PR/MR / tag / 签名 / 安装动作均需用户显式授权；本次未执行。
