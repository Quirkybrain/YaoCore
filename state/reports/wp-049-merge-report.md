# wp-049 合并集成报告（task/wp-049-family → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-049-merge（repository_action: merge）
- **Handoff**: `state/handoffs/wp-049-merge.json`（pin + snapshot + begin 已完成；本报告提交后运行 `finish wp-049-merge`）
- **日期**: 2026-10-17
- **结果**: **MERGE 成功（`--no-ff`，无冲突）；合并后集成验证 PASS（host 479/479、构建成功）**。本次合并将 T-13 邀请认证实现（C-12 AuthService / C-13 InviteService）及 DES-A/DES-B/ADR-003 契约修订带回 `feat/yaocore-app`。本报告是集成证据，**不替代 Stage Gate 判定**。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree） |
| 目标分支 | `feat/yaocore-app` @ `79ef41b50a480de3cce3b368825294685304566d`（= handoff `base_commit`；合并前 HEAD 即此） |
| 来源分支 | `task/wp-049-family` @ `136b6add3c6dfbededd7a86aad97318c5b35994d`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `79ef41b`（目标 tip；来源为基于该 tip 的线性提交链，仍按策略强制 `--no-ff`） |
| 工作区 | 干净（`git status --porcelain=v1` 无输出） |
| 守卫状态 | ACTIVE `wp-049-merge`（begin 已完成）；`status` 未见其他活动任务 |
| 快照 | `refs/swe/snapshots/20261017T144354Z-wp-049-merge-974ca1c8` @ `0f7ef3f522c14fe6e41fd4dd41decd644c4a4a46`，tree `aa7a2296b3a1bc8a55c43fc5cf3df9592e933880`（`SWE snapshot wp-049-merge`） |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；已执行 `git fetch origin`（无错误）；`origin/main` @ `7d6f4c9`；远端无 `feat/yaocore-app`；本次**未 push** |
| 本地 `main` | `a6f6558`（未移动） |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- `gate_evidence_path` `artifacts/70-review/t13-review-b.md` sha256 `78effd4b4918f91eb80fe35ac6ddf4895542e7e75ba79f71189e1618479250f6`（在来源 tip `136b6ad` 上实查一致，= handoff `gate_evidence_path_sha256`）
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用 `config/git-policy.default.md` 默认规范，无公司策略覆盖）

## 2. 来源与预检

来源提交链（`git log --oneline 79ef41b..136b6ad`，9 个提交）：

```text
1e17142 feat(family): 实现本地认证与离线邀请服务
0a5168c fix(family): 修正设备侧骨架编译范围并补充 ohosTest 证据
520bfb3 fix(invite): 将未知容器版本映射为 INVITE_VERSION_UNSUPPORTED
1c832e5 docs(t13): 对齐最终验证证据时间戳
b9aff49 docs(review): T-13 邀请认证独立评审
5b54a1f docs(design): 裁定 YCP1 回执与家庭导入契约
69d5374 fix(family): 修复 T-13 评审发现
d315c02 docs(review): T-13 复审（核心 F 项关闭确认）
136b6ad docs(design): 登记 releaseReceipt 并同步 YCP1 回执形态
```

预检结果：目标工作区干净；来源 tip 精确等于 handoff `source_commit`；`git diff --stat 79ef41b..136b6ad` 为 **34 files changed, 11956 insertions(+), 61 deletions(-)**；其中 3 份设计文档为 Modified，其余为实现/证据/评审文件新增或局部修改。

## 3. 合并

- 命令：`git merge --no-ff task/wp-049-family -m "chore(merge): 合并 T-13 邀请认证实现到 feat/yaocore-app"`
- 合并提交：`63f2e7844ec149047d789e029c51832107288632`
- 父提交：`79ef41b`（目标，第一父）+ `136b6ad`（来源，第二父）
- 策略：`ort`；**无冲突**（未手工编辑任何文件）
- 树一致性：`git diff --stat 136b6ad..63f2e78` 为空，即合并结果树与来源 tip 完全一致（目标自 base 后无独立提交）
- 设计文档合并后与来源 tip 字节一致（见 §5）

## 4. 变更统计（`79ef41b..136b6ad`，按目录）

| 目录 | 文件数 | + | − |
|---|---:|---:|---:|
| `artifacts/20-architecture/` | 1 | 22 | 0 |
| `artifacts/40-detailed-design/` | 2 | 163 | 33 |
| `artifacts/50-implementation/`（含 `evidence/t13-family`、`evidence/t13-fix`） | 12 | 7062 | 0 |
| `artifacts/70-review/` | 2 | 483 | 0 |
| `entry/src/main/ets/repository/` | 1 | 45 | 0 |
| `entry/src/main/ets/service/`（auth/family/invite） | 8 | 2926 | 19 |
| `entry/src/ohosTest/ets/test/` | 2 | 66 | 0 |
| `entry/src/test/`（domain + host） | 6 | 1189 | 9 |
| **合计** | **34** | **11956** | **61** |

三份设计文档修订明细（净 diff）：

| 文档 | 净 +/− | 归属提交 |
|---|---:|---|
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | +66 / −10 | `5b54a1f`（YCP1 回执与家庭导入契约裁定） |
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | +97 / −23 | `5b54a1f`（+80/−23）与 `136b6ad`（+22/−5，其中 5 行改写前次新增内容，故净值为 +97/−23） |
| `artifacts/20-architecture/adr-003-family-credential-distribution.md` | +22 / −0 | `136b6ad`（登记 `releaseReceipt` 与 YCP1 回执形态） |

## 5. 前身保护确认

目标分支中已有的三份设计文档由合并前快照保护；快照内字节与合并前目标字节一致：

| 文档 | 快照/合并前 sha256 | 合并后 sha256（= 来源 tip） |
|---|---|---|
| `adr-003-family-credential-distribution.md` | `14b52fe6cd1b86b16f2d7f643690ceb4c14043b64dcb6a4e39cee2b228e9af96` | `49d99785446a0dbb2a356a51e60d9e5093ca445f34387b6d5dc82f16e281ef3d` |
| `des-001a-foundation-transport.md` | `3932dac62252b040330858d530c1f8988a83ba4185d0ce5e42bc736a05069600` | `3a02ecbf266bfcc293bb648e89fa8d594831c1e07adf38900f6061dd51f12121` |
| `des-001b-domain-presentation.md` | `46e15e3718409d4e096e855b3db9f4662bf43eb635304175a6f5420aceb561fd` | `8d094bb5affa524dc950e56117d9e1c6f10510aea3846f1f588e0d9ca537dbff` |

- 快照 ref 可完整恢复合并前状态；本次未改写历史、未 reset、未 force。
- 合并提交保留双亲，来源修订以独立提交进入历史（`5b54a1f`、`136b6ad`），可追溯。

## 6. 合并后验证（在 `63f2e78` 上执行）

| 检查 | 命令 | 结果 |
|---|---|---|
| Host 测试 | `bash entry/src/test/run-host-tests.sh` | ✅ **479/479 PASS**（`# tests 479 / # pass 479 / # fail 0`） |
| 构建 | `hvigorw clean assembleHap --no-daemon` | ✅ **BUILD SUCCESSFUL**（35 tasks，exit 0） |
| 工作区 | `git status --porcelain` | ✅ 干净（构建产物均被忽略） |

说明：本任务未复跑 codelinter；静态检查证据沿用 CQG-T13 判定的 `t13-fix/codelinter.log`（合并树与来源树一致）。

## 7. 冲突

**无冲突**。`ort` 自动合并；来源与目标在 base 后无分叉内容冲突（目标无独立提交）。

## 8. 门禁引用

- Gate：`state/gates/CQG-T13.md` — **PASS（代码级）**；C-12/C-13 → STABLE（代码级，条件式）@ `69d5374`（契约登记 `136b6ad`）。
- 门禁证据：`artifacts/70-review/t13-review-b.md` sha256 `78effd4b4918f91eb80fe35ac6ddf4895542e7e75ba79f71189e1618479250f6`。
- 残余：R2-03/R2-04/T13-R-15/R2-05、F-09..F-13、F-15 及设备证据（Asset/RDB/PBKDF2/X25519/GCM/多进程）保持 BLOCKED，跟踪至 T-19；详见 CQG-T13。

## 9. 分支与下一步

- 合并后 `feat/yaocore-app` tip：本证据提交（主题 `chore(repo): 记录 wp-049 合并集成证据`）；其第一父为合并提交 `63f2e78`。
- `finish wp-049-merge` 校验通过后，从新 tip 创建 `task/wp-055-cloud`（不切换、不建 worktree）。
- 下一步：派发 **T-14**（C-15 云服务 + C-16 AC 适配）。
- 约束遵守：未 push；未切换/移动其他分支；未创建 worktree；未修改本报告之外文件；未使用 reset/force。

```text
Evidence commit subject: chore(repo): 记录 wp-049 合并集成证据
Merge commit: 63f2e7844ec149047d789e029c51832107288632
Source tip: 136b6add3c6dfbededd7a86aad97318c5b35994d
Target pre-merge: 79ef41b50a480de3cce3b368825294685304566d
```
