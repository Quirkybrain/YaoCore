# wp-084 合并集成报告（task/wp-084-contract-cleanup → feat/yaocore-app）

- **Producer**: agent:repository-manager
- **Task**: wp-084-merge（repository_action: merge）
- **Handoff**: `state/handoffs/wp-084-merge.json`（pin + snapshot + begin 已完成；本报告提交后运行 `finish wp-084-merge`）
- **日期**: 2026-10-18
- **结果**: **MERGE 成功（`--no-ff`，无冲突）；合并后集成验证 PASS（host 696/696、clean 构建成功）**。本次合并把 T-20 端口物理位置例外与 D-12 文件/符号级 allowlist 的正式化文本带入 `feat/yaocore-app`。本报告是集成证据，**不替代 IG / G-013 / G-014 Stage Gate 判定**，也不表示 `wp-085-tooling` 的检查器改造已完成。

## 1. Baseline（合并前）

| 项 | 值 |
|---|---|
| 仓库根 | `/home/quirkybrain/code/harmony-projects/YaoCore`（唯一 worktree） |
| 目标分支 | `feat/yaocore-app` @ `76d342c84152e57f7b6e661ccce5a41f5881c47c`（= handoff `base_commit`；合并前 HEAD 即此） |
| 来源分支 | `task/wp-084-contract-cleanup` @ `fec06e5e29511753f2074eb358d08b723e57aec8`（= handoff `source_commit`，`git rev-parse` 实查一致） |
| 合并基 | `76d342c`（目标 tip；`git merge-base --is-ancestor 76d342c fec06e5` 通过，来源可直接 `--no-ff` 合并） |
| 工作区 | 干净（`git status --porcelain=v1 -b` 仅输出分支行） |
| 守卫状态 | ACTIVE `wp-084-merge`（begin 已完成）；无其他活动任务 |
| 快照 | `refs/swe/snapshots/20261017T194641Z-wp-084-merge-f4e7024d` @ `35585401c75769b2abda5876e1a6bde75fec7558`（父提交 `76d342c`；捕获 `artifacts/40-detailed-design/` + handoff；原始 DES-A/DES-B 字节 sha256 分别为 `6c0f0a4e…` / `645876f9…`） |
| 远端 | `origin` = `https://github.com/Quirkybrain/YaoCore.git`；已执行 `git fetch origin --prune`（exit 0）；`origin/main` @ `7d6f4c99fa1bf0baf5e40d1948a97f564a647401`；本次**未 push** |
| 本地 `main` | `a6f6558882f7ec53be548c85e15a1a291c5a41fd`（未移动） |

冻结输入哈希复核（与 pin 一致）：

- `config/git-policy.json` sha256 `3b8ddffd44949d4fa41318f4122bc40aa50fb8287d9a9a102d83ffeb9241a014`
- `docs/git-collaboration.md` sha256 `e1884a3333a55903581521fca6ff2ba5b11f7bd9419b3d49972056203367260c`（锚点 `## 分支与交接顺序`）
- `gate_evidence_path` `artifacts/40-detailed-design/des-001b-domain-presentation.md`：来源提交 `fec06e5` 中 sha256 `bdc42f3fcff017244a1e26fb5a0829f3a9bf9954ec00fdcc3bdc82b324649f15`（= handoff `gate_evidence_path_sha256`）；合并前基线 `76d342c` 中为 `645876f9b07f2ab837dd35ba029aaa14290a2a98d86046ab6b5c805f5ffbb521`，已由上述快照保存原始字节
- 策略：`mode: BRANCH_PER_TASK`；`merge_strategy: no-ff`；`main_merge_mode: review_request_when_remote`；`company_policy_path: null`（使用 `config/git-policy.default.md` 默认规范，无公司策略覆盖）

## 2. 来源与预检

来源提交（`git log --oneline 76d342c..fec06e5`，单提交，与任务说明实查一致）：

```text
fec06e5 docs(design): 正式化端口位置与 D-12 例外
```

预检结果：目标工作区干净；来源 tip 精确等于 handoff `source_commit`；目标 tip 是来源的直接祖先（无分叉）；`git diff --check 76d342c..fec06e5` 通过。变更仅 2 个设计文件，全部落在 handoff `writes`（`artifacts/40-detailed-design/`）内。

## 3. 合并

- 命令：`git merge --no-ff task/wp-084-contract-cleanup -m "chore(merge): 合并 T-20 契约例外正式化到 feat/yaocore-app"`
- 合并提交：`0d6e806dfabe3126e5b90d5cce74b546cbdd2050`（主题 `chore(merge): 合并 T-20 契约例外正式化到 feat/yaocore-app`）
- 父提交：`76d342c`（目标，第一父）+ `fec06e5`（来源，第二父）
- 策略：`ort`；**无冲突**（未手工编辑任何文件）
- 树一致性：`git diff --stat fec06e5..0d6e806` 为空，即合并结果树与来源 tip 完全一致（目标自 base 后无独立提交）

## 4. 变更统计（`76d342c..0d6e806`）

| 路径 | 文件数 | + | − |
|---|---:|---:|---:|
| `artifacts/40-detailed-design/des-001a-foundation-transport.md`（§0.8 / §2.1 / §3.7 / §27.6 端口物理位置例外登记） | 1 | 298 | 2 |
| `artifacts/40-detailed-design/des-001b-domain-presentation.md`（§0.10 / §2.3 / §18.1 / §23.7 D-12 例外正式化） | 1 | 256 | 5 |
| **合计** | **2** | **554** | **7** |

说明：`git diff --stat` 显示的行数为每个文件“新增 + 删除”的合计条（DES-A 300、DES-B 261），与交接描述一致；上表为 `--numstat` 的精确增删拆分。

## 5. 合并后验证（在 `0d6e806` 上执行，早于证据提交且不含任何代码改动）

| 检查 | 命令 | 结果 |
|---|---|---|
| Host 测试 | `bash entry/src/test/run-host-tests.sh` | ✅ **696/696 PASS**（`1..696`、`# pass 696 / # fail 0 / # cancelled 0 / # skipped 0 / # todo 0`，exit 0，duration ≈ 2957.0 ms） |
| 构建 | `hvigorw clean assembleHap --no-daemon` | ✅ **BUILD SUCCESSFUL in 14 s 391 ms**（35 tasks：34 executed / 1 up-to-date；仅既有 ArkTS 警告与“未配置 signingConfigs，跳过签名”提示，均为预期；unsigned HAP） |
| 工作区 | `git status --porcelain` | ✅ 干净（构建产物均被忽略） |

说明：本次变更仅设计文档，不涉及产品代码；host 测试与 HAP 构建用于回归确认合并树可构建、可测试。未复跑 codelinter、i18n checker、协议 crosscheck、仿真器套件与设备矩阵——其证据沿用 T-19/T-20 既有报告；本次不新增设备/模拟器/BLE/LAN/TLS/云/性能 PASS 声明。

## 6. 冲突

**无冲突**。`ort` 自动合并；目标 tip 是来源 tip 的直接祖先；两个文件均为既有文件增量修改，无删除、无重叠修改。

## 7. 门禁引用

- 门禁证据：`artifacts/40-detailed-design/des-001b-domain-presentation.md`，来源提交 `fec06e5` 中 sha256 `bdc42f3fcff017244a1e26fb5a0829f3a9bf9954ec00fdcc3bdc82b324649f15`（= handoff pin）。
- 内容要点：T-20 收口正式化 D-12 文件/符号级 13 条例外（`T20-D12-01..13`，`accepted`）；同步登记端口物理位置 17 条例外（DES-A §27.6），并声明 `check_layering` 0 violation ≠ 端口位置合规；不改变任何冻结签名、页面/服务契约与 G-004 语义。DES-A 对应登记见 `artifacts/40-detailed-design/des-001a-foundation-transport.md` §27.6。
- 结论：合并只表示契约例外文本已进入集成分支，**不构成 Gate PASS**；IG-4 / G-013 / G-014 判定归 Stage 流程。`tools/contract/layering_allowlist.json` 的实际 `port_location_exceptions` 读取与硬编码白名单替换属于后续 `wp-085-tooling`。

## 8. 证据提交与分支

- 合并后 `feat/yaocore-app` 新 tip：本证据提交（主题 `chore(repo): 记录 wp-084 合并集成证据`，第一父为合并提交 `0d6e806`；仅包含本报告路径 `state/reports/wp-084-merge-report.md`）。该提交 SHA 无法写入自身，提交后由 `git rev-parse HEAD` / `finish` 记录读取。
- `finish wp-084-merge` 校验通过后，从本证据提交（新 tip）创建 `task/wp-085-tooling`（不切换、不建 worktree），分支 tip 即本证据提交。
- 下一步建议：`wp-085-tooling` 在 `tools/contract/` 实现 `load_port_location_exceptions()` 并用其替换 `_is_storage_port_path` / `_is_viewmodel_service_port`，落地 D-12 13 条 `accepted` 条目；随后按流程独立复审与集成，仍不推送远端。
