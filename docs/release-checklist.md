# YaoCore 发布检查单

- **Artifact ID**: RELEASE-CHECKLIST-001
- **Producer**: agent:release-engineer
- **Type**: Release Checklist / Operational Runbook
- **Version**: 1.1（2026-10-18；修订 `wp-116-release-fix`，处理复审 F-01..F-06）
- **Applies to**: 代码证据基线 `e74a181`/TEST-002（产品代码至本修订未变）；文档修订起点 `f1fbe0d`（`task/wp-116-release-fix`；本次修订提交见 Git 记录）；**最终 release revision/tag 未冻结**
- **Related plan**: [`artifacts/85-release/release-plan.md`](../artifacts/85-release/release-plan.md)（RELEASE-001；含 §4.4 公开旧版本对照、§8.1.1 回滚阈值提案）
- **Current verdict**: **`NOT_READY`**（发布准备完成；发布未授权）
- **Scope**: 发布前、发布中、发布后检查；签名、设备、远端、回滚与证据归档。本文不授予任何发布/部署/签名/远端写权限。

> **使用规则**
>
> 1. 每项必须绑定**当前 release revision**（最终 revision/tag 未冻结前为代码证据基线 `e74a181`/TEST-002，构建探针为 `6cd9a88`）的可复现证据；`PASS` 只用于实际执行且断言通过的项目。
> 2. `BLOCKED`、`PENDING`、`NOT_RUN`、`MOCK_ONLY`、`COMPILED_ONLY`、`UNSIGNED` **不得**写成 `PASS`。
> 3. 任何代码/构建配置/版本/签名配置变更都会使受影响证据失效；必须重新构建、重跑受影响检查并更新本检查单。
> 4. 用户书面接受的风险必须记录接受范围、接受人和日期；不得用“已知”代替“已接受”。
> 5. 证据中不得包含证书私钥、密钥库口令、Profile 口令、Wi-Fi 密码、PoP、HMAC 密钥、IAM Token、完整邀请凭据或用户隐私数据。
> 6. 发布/部署授权与就绪评估分离：本检查单通过不代表已授权发布；授权必须单独记录。

---

## 0. 当前状态快照（2026-10-18；代码证据基线 `e74a181`/TEST-002；文档修订起点 `f1fbe0d`）

| 维度 | 当前状态 | 说明 |
|---|---|---|
| 代码证据基线 / 最终 release revision | `PARTIAL` | 代码证据基线 `e74a181`/TEST-002；产品代码/构建配置自 `e74a181` 未变；**最终 release revision/tag 未冻结**（当前无 tag） |
| release 构建 | `DONE（unsigned probe @6cd9a88）` | 默认构建为 `debug`；补充 `buildMode=release` 干净构建通过，未签名 |
| Host/契约/仿真器/分层/i18n | `DONE（code-level @e74a181/TEST-002；6cd9a88 复跑）` | 见 §1.3；当前 revision 复跑全部 exit 0 |
| 设备/真实环境 | `BLOCKED / NOT_RUN` | `hdc` target 为空；BLK-01..08 未执行 |
| 签名/安装 | `BLOCKED` | `signingConfigs: []`；未签名 HAP 不可安装 |
| 许可证 | `BLOCKED` | 当前树无 `LICENSE`；README 标 TODO；公开旧版本为 Apache-2.0 + NOTICE；待 §4.4 A/B/C 决定 |
| GAP-AC-01..03 | `PENDING` | 待用户接受或 bounded fix |
| 发布标识/版本 | `PENDING` | 公开旧版本 `io.github.quirkybrain.yaocore`/1000000；当前 `com.example.yaocore`/1000000；待 §4.4 A/B/C 决定 |
| CHANGELOG/Release Notes | `PARTIAL` | 草案已产出 @ `63d2235`；待评审/签核（B-07） |
| 风险签核 | `PENDING` | B-08：D-030/R4-01/PORT-LOC-01/i18n/NFR/ACK MOCK_ONLY/test lint/unsigned；B-09：构建硬化/API 14 兼容性 |
| 远端/通道 | `UNAUTHORIZED` | `origin/main=7d6f4c9` 为公开 YaoCore 1.0.0；本地 `main` 与其历史不相关；未 push；无 tag；待 §4.4 A/B/C + §7.2 A-E |
| 回滚预案 | `PARTIAL（plan）` | 见 RELEASE-001 §8；§8.1.1 阈值提案待用户批准 |
| **发布 Gate** | **`NOT_READY`** | 任一阻塞未关闭即 No-Go |

---

## 1. 发布前检查

### 1.1 代码、revision 与版本

| # | 检查项 | 责任人 | 证据形式 | 当前状态 |
|---|---|---|---|---|
| 1.1.1 | **代码证据基线**已确认；**最终 release revision/tag** 已冻结并指向该 commit；工作树干净（构建产物除外） | `release-engineer` | `git rev-parse HEAD`、`git status --porcelain`、tag 记录 | `PARTIAL（代码证据基线 e74a181/TEST-002；最终 release revision/tag 未冻结，无 tag；待 B-06）` |
| 1.1.2 | 发布内容与已测试 revision 一致；产品代码/测试/构建配置无未评审差异 | `release-engineer` / `quality-reviewer` | `git diff --quiet <tested>..HEAD -- <paths>` exit 0；评审记录 | `DONE（e74a181..HEAD 产品代码/测试/构建配置无差异）` |
| 1.1.3 | `versionName` / `versionCode` 最终确认；HAP `module.json`/`pack.info` 与 `AppScope/app.json5` 一致 | 用户/项目所有者 + `release-engineer` | `AppScope/app.json5`、HAP `module.json`、`pack.info`、版本签核 | `PENDING（B-06；旧公开 1.0.0 已用 1000000；待 §4.4 A/B/C）` |
| 1.1.4 | `bundleName` / `vendor` 最终确认；与签名证书/Profile/AGC 应用记录一致 | 用户/项目所有者 + 授权签名人 | 包标识确认记录；AGC/Profile 截图（脱敏） | `PENDING（B-06；旧公开 io.github.quirkybrain.yaocore；待 §4.4 A/B/C）` |
| 1.1.5 | 发布构建使用 `buildMode=release`；`buildMode=release`、`debug=false`；无调试 source map/调试开关 | `release-engineer` | 构建命令、`module.json`、HAP 条目清单 | `DONE（probe）；需在 1.1.3/1.1.4 冻结后重建` |
| 1.1.6 | 依赖锁文件与 `ohpm install` 一致；无未登记运行时依赖；无本地路径/代理配置进入产物 | `release-engineer` / `implementation-engineer` | `oh-package.json5`、`oh-package-lock.json5`、`ohpm install` 日志、HAP 扫描 | `DONE（构建级）；许可证审计见 1.6` |
| 1.1.7 | 仓库/产物/日志无秘密、无签名材料、无用户隐私数据 | 全体 | 秘密扫描、提交 diff、日志抽查 | `DONE（本次）；发布前复查` |

### 1.2 构建与产物

| # | 检查项 | 责任人 | 证据形式 | 当前状态 |
|---|---|---|---|---|
| 1.2.1 | `ohpm install` 成功 | `release-engineer` | 命令日志、exit 0 | `DONE` |
| 1.2.2 | 干净 release 构建成功（推荐命令见 §6.1） | `release-engineer` | `BUILD SUCCESSFUL`、任务数、exit 0 | `DONE（unsigned probe）` |
| 1.2.3 | 唯一 HAP 路径、大小、SHA-256 已记录；与构建命令/commit/工具链绑定 | `release-engineer` | `find`、`stat`、`sha256sum`、构建日志 | `DONE（未签名）` |
| 1.2.4 | `module.json`/`pack.info` 的 bundleName、versionName、versionCode、compatible/target API 与预期一致 | `release-engineer` | `unzip -p ... module.json`、`pack.info` | `PARTIAL（结构/值已记录 @6cd9a88；待 1.1.3/1.1.4 冻结后最终确认）` |
| 1.2.5 | HAP 内容检查：无 Mock/ohosTest/DEV-ONLY 生产混入；无意外测试资源 | `quality-reviewer` / `test-engineer` | HAP 条目清单、字符串扫描 0 命中 | `DONE（4 类字符串 0 命中）` |
| 1.2.6 | 构建 warning 已 triage（API 18 `ColumnType/TEXT/BLOB` vs compatible API 14、混淆/裁剪是否启用等） | `implementation-engineer` / `release-engineer` | warning 清单、B-09 决策/验证记录、风险接受或修复记录 | `PENDING（B-09；需签核/修复决定）` |
| 1.2.7 | 产物已保存到受控位置；SHA-256 清单独立于工作树；未提交 HAP 到 Git | `release-engineer` | 产物存储路径、校验和清单、`.gitignore`/提交检查 | `PARTIAL（待发布存储）` |
| 1.2.8 | 构建可复现边界已记录：commit + 工具链 + 命令 + SHA；不承诺字节级可复现 | `release-engineer` | 构建记录、两次构建哈希对比 | `DONE` |

### 1.3 测试与静态检查

| # | 检查项 | 责任人 | 证据形式 | 当前状态 |
|---|---|---|---|---|
| 1.3.1 | Host 纯逻辑测试全绿 | `test-engineer` | `entry/src/test/run-host-tests.sh` TAP、697/697、exit 0 | `DONE（代码证据 e74a181/TEST-002；6cd9a88 复跑）` |
| 1.3.2 | 协议 crosscheck 硬检查全通过；FINDING 已登记 | `test-engineer` / `solution-architect` | `crosscheck_protocol_assets.py` 日志、66/66、14 FINDING | `DONE` |
| 1.3.3 | 仿真器契约（HTTP+TLS）全通过（localhost/DEV-ONLY 边界） | `test-engineer` | `unittest` 日志、20/20、`no_proxy` | `DONE` |
| 1.3.4 | 分层检查 0 violation；例外均版本化登记；`PORT-LOC-01` 状态明确 | `test-engineer` / `solution-architect` | `check_layering.py` 输出、allowlist、fixture 27/27 | `DONE（含 6 D-12 / PORT-LOC-01 OPEN）` |
| 1.3.5 | i18n `--strict-ui` 0 blocking / 0 missing；triage 615 行一致 | `test-engineer` / `technical-writer` | 检查器日志、triage 日志、残余清单 | `DONE` |
| 1.3.6 | 静态检查 `codelinter` 0 error；warning 已 triage | `implementation-engineer` | codelinter 日志、0 error/25 warning | `DONE` |
| 1.3.7 | 安全负例 SEC-N01..N26 有当前证据；无未关闭 High/Critical | `quality-reviewer` / `test-engineer` | 评审记录、测试锚点、安全负例报告 | `DONE（host/sim）；设备子断言 BLOCKED` |
| 1.3.8 | 测试源码 lint/覆盖率缺口已登记并接受（或补齐） | `test-engineer` / 用户 | 维护计划 M-08、风险接受 | `PENDING（接受）` |
| 1.3.9 | 任何代码/测试/配置变更已做 Change Impact，受影响证据已重跑 | `release-engineer` / 各 owner | Change Impact 记录、新测试日志 | `N/A（本任务无代码变更）` |

### 1.4 i18n 与文档

| # | 检查项 | 责任人 | 证据形式 | 当前状态 |
|---|---|---|---|---|
| 1.4.1 | zh-CN/en-US 资源完整；无 blocking 硬编码；key parity 通过 | `implementation-engineer` / `test-engineer` | `check_i18n.py --strict-ui`、资源清单、HAP 内 `resources/rawfile/i18n/*` | `DONE` |
| 1.4.2 | i18n 历史文案残余已 triage（6 PENDING / 11 B / 6 C / 3 D）；544 OBSOLETE 不作为删除清单 | `technical-writer` / `implementation-engineer` | `legacy-migration.csv`、triage 日志、残余签核 | `PENDING（人工收口/接受）` |
| 1.4.3 | README 与实际 revision/命令/数字/已知限制一致 | `technical-writer` | README v1.2、差异检查 | `DONE（v1.2）` |
| 1.4.4 | `CHANGELOG.md` 草案已覆盖本版本；待评审/签核 | `technical-writer` | `CHANGELOG.md`（`Status: DRAFT`）、变更分类、评审记录 | `PARTIAL（草案已产出 @63d2235；待评审/签核）` |
| 1.4.5 | Release notes 草案已覆盖范围、验证边界、已知限制、安装/升级、许可证；待评审/定稿 | `technical-writer` + 用户 | `docs/release-notes-v1.0.0.md`（`DRAFT / NOT_READY`）、评审记录 | `PARTIAL（草案已产出 @63d2235；待评审/签核）` |
| 1.4.6 | 文档链接、命令、产物路径与实际仓库一致 | `technical-writer` / `release-engineer` | 链接检查、命令清单、路径核对 | `PENDING（发布前复核）` |
| 1.4.7 | 若渠道要求：隐私政策、商店描述、截图/素材、支持信息已准备 | 用户/项目所有者 + `technical-writer` | 渠道后台记录/链接 | `PENDING（通道未选）` |

### 1.5 用户验收与风险

| # | 检查项 | 责任人 | 证据形式 | 当前状态 |
|---|---|---|---|---|
| 1.5.1 | ACCEPT-001 的 U-01..U-12 已执行并回填，或按范围书面接受 | 用户 / `system-verifier` | 验收记录、设备矩阵证据、用户签核 | `BLOCKED（未执行）` |
| 1.5.2 | GAP-AC-01..03：LAN IP、首页家庭切换形态、房间图标已接受或修复 | 用户 / `implementation-engineer` | 书面决定；若修复，测试/复审记录 | `PENDING` |
| 1.5.3 | D-030/RA-01 服务层 RBAC 缺口已接受/修复 | 用户 / `solution-architect` | 风险接受记录、复审 | `PENDING` |
| 1.5.4 | R4-01/RA-02 durable 取消边界已接受/修复 | 用户 / `implementation-engineer` | 风险接受记录、边界测试（如修复） | `PENDING` |
| 1.5.5 | PORT-LOC-01 仍 OPEN；不得宣称端口位置 100% 合规 | `solution-architect` | allowlist、DES-A §27.6.4、风险接受 | `PENDING（接受）` |
| 1.5.6 | 设备/真实环境 BLOCKED（BLE/LAN/TLS/云/视觉/fps/硬件）已按范围接受 | 用户 / `system-verifier` | 设备矩阵、风险接受 | `BLOCKED` |
| 1.5.7 | ACK p95 仅 `MOCK_ONLY`，不作为 NFR 4.3 验收；NFR 4.1/4.2/4.3 partial 已登记 | `test-engineer` / 用户 | TEST-002、风险登记、用户签核 | `PENDING（接受）` |
| 1.5.8 | 未签名产物风险已接受，且不把未签名包装成可安装/可发布 | `release-engineer` / 用户 | 风险记录、签名检查单 | `BLOCKED（待签名）` |
| 1.5.9 | B-09 构建硬化/API 14 兼容性决策已签核：API 14 运行时验证或书面风险接受；混淆/裁剪启用与否及符号化方案已记录 | 用户 / `implementation-engineer` / `release-engineer` | B-09 决策/验证记录、回归结果、风险接受 | `PENDING（B-09）` |

### 1.6 许可证与合规

| # | 检查项 | 责任人 | 证据形式 | 当前状态 |
|---|---|---|---|---|
| 1.6.1 | 项目级 `LICENSE` 已选定并提交；SPDX 标识明确；公开旧版本 Apache-2.0/NOTICE 关系已按 §4.4 A/B/C 决定 | 项目所有者 / `technical-writer` | `LICENSE`、`NOTICE`、提交记录、所有者决定、§4.4 记录 | `BLOCKED（待 §4.4 A/B/C）` |
| 1.6.2 | 第三方依赖/模板/字体/图标许可证已核对；必要时补 `NOTICE`；旧公开版本版权/来源声明已处理 | `technical-writer` + 项目所有者 | 依赖清单、许可证文本、审计记录、NOTICE 草案 | `PENDING` |
| 1.6.3 | 源码/产物不含第三方受限代码或未授权素材 | `quality-reviewer` | 源码扫描、素材来源记录 | `PENDING` |
| 1.6.4 | 发布渠道要求的隐私/合规/实名/内容审核材料已准备 | 用户/项目所有者 | 渠道要求清单、提交记录 | `PENDING（通道未选）` |
| 1.6.5 | 无秘密/凭据/个人信息进入 Git、Artifact、日志、商店素材 | 全体 | 秘密扫描、脱敏检查 | `DONE（本次）；发布前复查` |

### 1.7 签名与安装

| # | 检查项 | 责任人 | 证据形式 | 当前状态 |
|---|---|---|---|---|
| 1.7.1 | 签名材料齐备：证书、Profile、密钥库、alias；均在用户控制下 | 用户/授权签名人 | 材料清单（不含秘密）、有效期检查 | `BLOCKED` |
| 1.7.2 | 证书/Profile 的 bundleName、设备/发布类型与最终包标识匹配（最终包标识待 §4.4 A/B/C） | 授权签名人 | Profile/证书校验记录（脱敏）、§4.4 决定 | `BLOCKED` |
| 1.7.3 | 签名配置仅保存在本地/秘密环境；`build-profile.json5` 不含真实口令 | 授权签名人 + `release-engineer` | diff、秘密扫描、配置摘要 | `BLOCKED` |
| 1.7.4 | 干净 release 构建签名成功；无 `Will skip sign` | 授权签名人 | 构建日志、签名成功记录 | `BLOCKED` |
| 1.7.5 | 签名 HAP 校验通过；大小/SHA-256 已记录 | 授权签名人 + `release-engineer` | 签名校验日志、`stat`、`sha256sum` | `BLOCKED` |
| 1.7.6 | 安装 smoke：`hdc install` 成功；启动、版本、权限、4 Tab/核心页面正常 | 用户/`release-engineer` | `hdc` 日志、设备型号/OS/API、截图/录屏 | `BLOCKED` |
| 1.7.7 | 升级安装：若采用 §4.4-A（旧公开身份），从公开 1.0.0 以更高 versionCode 覆盖成功，数据/行为符合预期；若采用 B/C，记录独立应用身份与旧用户无法升级 | 用户 | 升级日志、版本对比、数据检查、§4.4 决定 | `PENDING（旧公开 1.0.0 存在；待 §4.4 A/B/C）` |
| 1.7.8 | 签名后产物与未签名对照产物分开保存；证据链完整 | `release-engineer` | 产物清单、SHA-256、存储路径 | `BLOCKED` |

### 1.8 设备矩阵（用户执行）

> 当前全部 `BLOCKED`/`NOT_RUN`。执行结果回填本表并附证据；不得用 host/mock/编译证据替代。

| ID | 能力 | 责任人 | 证据形式 | 当前状态 |
|---|---|---|---|---|
| BLK-01 | Hypium host 运行（或确认 Node runner 为正式 host 路径） | `test-engineer`/用户 | `hvigorw test` 日志或正式路径说明 | `BLOCKED` |
| BLK-02 | 设备/模拟器 + 签名安装 + UI 启动 | 用户 | `hdc install`、启动截图、4 Tab、设备信息 | `NOT_RUN` |
| BLK-03 | 真实 BLE 配网/Security1/身份 | 用户 + 固件维护者 | BLE §8 的 11 条记录、脱敏日志/截图 | `NOT_RUN` |
| BLK-04 | 真实 LAN / HMAC / TLS pin | 用户 | discover/control/ACK 日志、pin 失败无明文回退、抓包（脱敏） | `NOT_RUN` |
| BLK-05 | 真实华为云 IoTDA | 用户 | 脱敏请求/响应、影子快照、完成判定、Token 过期提示 | `NOT_RUN` |
| BLK-06 | 视觉/无障碍/动效 | 用户 | 截图/录屏、字体缩放、读屏、对比度、动效降级 | `NOT_RUN` |
| BLK-07 | 性能（真实 LAN p95、55ms、60/120fps） | 用户 | 原始测量数据、设备/网络/样本数 | `NOT_RUN` |
| BLK-08 | 真实硬件（门锁/门磁/AC/SHT30/PIR） | 用户 | 设备照片、脱敏日志、状态/阶段/读数 | `NOT_RUN` |

### 1.9 远端与发布通道

| # | 检查项 | 责任人 | 证据形式 | 当前状态 |
|---|---|---|---|---|
| 1.9.1 | 用户书面选择身份/许可证方案（RELEASE-001 §4.4 A/B/C）与远端策略（§7.2 A-E） | 用户/项目所有者 | 决策记录、目标仓库/分支/可见性、§4.4 记录 | `UNAUTHORIZED（待 §4.4 A/B/C + §7.2 A-E）` |
| 1.9.2 | 已确认本地 `main` 与公开 `origin/main` 历史不相关；如需改写已备份并获授权 | `repository-manager` | `git merge-base`、备份记录、授权 | `CONFIRMED（不相关；origin/main=7d6f4c9 为公开 1.0.0）；未授权` |
| 1.9.3 | `main`/发布分支受保护：禁止直接 push/强推；要求 PR/MR、独立评审、必需 CI | `repository-manager` + 平台管理员 | 平台保护设置截图/链接 | `PENDING` |
| 1.9.4 | CI 覆盖构建/测试/静态检查/契约/分层/i18n；当前 revision 通过 | `repository-manager` / CI owner | CI 运行链接、日志 | `PENDING` |
| 1.9.5 | PR/MR 描述包含目标、范围、测试命令/结果、风险、迁移/回滚 | 提交人/评审人 | PR/MR 链接、模板检查 | `PENDING` |
| 1.9.6 | tag 策略确定：不可变、命名规范、只在通过 Gate 后创建 | `release-engineer` / `repository-manager` | tag 记录、发布策略 | `PENDING` |
| 1.9.7 | 发布通道素材/合规材料齐备（如应用市场） | 用户 + `technical-writer` | 渠道后台记录 | `PENDING` |
| 1.9.8 | 任何 push/PR/MR/tag 均有显式授权记录 | 用户 | 授权消息/记录 | `UNAUTHORIZED` |
| 1.9.9 | 公开旧版本（`origin/main` @ `7d6f4c9`）的用户、版本、许可证、来源声明与 Release/tag 保留影响已按 §4.4 A/B/C 分析并记录 | 用户/项目所有者 + `release-engineer` | §4.4 决策记录、旧版本对照、来源/NOTICE 方案 | `PENDING（待用户决定）` |

### 1.10 回滚与保留

| # | 检查项 | 责任人 | 证据形式 | 当前状态 |
|---|---|---|---|---|
| 1.10.1 | 回滚触发条件、动作、责任人已批准；P1/P2 可量化阈值（RELEASE-001 §8.1.1）已签核 | 用户/项目所有者 + `release-engineer` | RELEASE-001 §8；发布负责人签核；阈值批准记录 | `PENDING（计划已起草；§8.1.1 阈值待用户批准）` |
| 1.10.2 | 上一稳定版本/产物已保留（若采用 §4.4-A，旧公开 1.0.0 可作为参考；B/C 需记录无同 bundleName 上一版本） | `release-engineer` | 产物存储清单、SHA-256、§4.4 决定 | `PENDING` |
| 1.10.3 | versionCode 单调递增策略已确认；不得降级；若采用 §4.4-A 必须 >1000000 | `release-engineer` | 版本策略、发布记录、用户确认 | `PENDING（建议已提出；待用户确认）` |
| 1.10.4 | tag/对外发布历史不可改写；回滚用新提交/新版本 | `repository-manager` | 分支保护、tag 记录、回滚演练 | `PENDING` |
| 1.10.5 | 数据备份/迁移/回滚方案（如适用）已批准 | `solution-architect` / 用户 | 迁移/备份方案、演练记录 | `N/A（v1 本地数据；无迁移）` |
| 1.10.6 | 证据保留期限/位置/访问控制已确定 | `release-engineer` + 项目所有者 | 证据目录、保留策略 | `PENDING` |

---

## 2. 发布中检查（授权后执行）

| # | 检查项 | 责任人 | 证据形式 | 状态 |
|---|---|---|---|---|
| 2.1 | 最终 Go/No-Go 会议/记录：R-G01..R-G13 逐项确认 | 用户/项目所有者 + `release-engineer` | Go/No-Go 记录、签字/消息 | `PENDING` |
| 2.2 | 发布授权记录：范围、目标通道、revision、产物 SHA、时间、授权人 | 用户/项目所有者 | 授权记录（可审计） | `PENDING` |
| 2.3 | 发布 tag 创建/推送（如适用）且指向已签产物对应 commit | `repository-manager` | tag 列表、commit、签名/校验和 | `PENDING` |
| 2.4 | 产物上传/发布到目标通道；访问控制/可见性正确 | 授权发布人 | 通道后台记录、下载链接、权限检查 | `PENDING` |
| 2.5 | 上传后重新下载/校验 SHA-256 与签名；与本地记录一致 | `release-engineer` | 校验和对比、签名校验 | `PENDING` |
| 2.6 | 应用市场/渠道提交（如适用）：版本、说明、隐私、素材、审核状态 | 用户/授权发布人 | 提交回执、审核状态 | `PENDING` |
| 2.7 | staged rollout/灰度比例与监控阈值已设置（如渠道支持） | 用户/发布负责人 | 渠道设置截图、监控面板 | `PENDING` |
| 2.8 | 发布通知/支持渠道/事故联系人已就绪 | 用户/项目所有者 | 通知记录、联系人清单 | `PENDING` |

---

## 3. 发布后检查

| # | 检查项 | 责任人 | 证据形式 | 状态 |
|---|---|---|---|---|
| 3.1 | 干净设备安装/启动 smoke 通过；版本/包名正确 | 用户/`release-engineer` | 安装日志、启动截图、版本信息 | `PENDING` |
| 3.2 | 升级安装（若采用 §4.4-A：从公开 1.0.0 升级；B/C：记录独立身份）通过；无数据丢失/启动失败 | 用户 | 升级日志、数据检查、§4.4 决定 | `PENDING` |
| 3.3 | 核心流程 smoke：家庭创建/切换、房间、设备控制、场景、设置 | 用户/`system-verifier` | 截图/录屏、脱敏日志 | `PENDING` |
| 3.4 | BLE/LAN/TLS/云/硬件/视觉/性能按发布范围复验或明确不在范围 | 用户 | 设备矩阵回填 | `PENDING` |
| 3.5 | 崩溃/ANR/性能/网络失败监控已观察并记录 | 用户/发布负责人 | 监控面板、告警记录 | `PENDING` |
| 3.6 | 回滚触发条件复核；如需回滚，执行 RELEASE-001 §8 并保留证据 | 用户/`release-engineer` | 回滚记录、根因、修复版本 | `PENDING` |
| 3.7 | 证据归档：产物、SHA、签名、安装、测试、审批、发布记录 | `release-engineer` | 证据目录/清单/链接 | `PENDING` |
| 3.8 | 复盘：更新 README/维护计划/风险登记/检查单；新增测试或 ADR（如需要） | `technical-writer` + 各 owner | 复盘记录、文档提交 | `PENDING` |

---

## 4. 签核

| 角色 | 签核内容 | 姓名/身份 | 日期 | 结论 |
|---|---|---|---|---|
| 用户/项目所有者 | 公开旧版本身份/版本/许可证（§4.4 A/B/C）、许可证、bundleName/version、GAP-AC-01..03、风险接受（B-08/B-09）、远端/通道、P1/P2 阈值、Go/No-Go |  |  |  |
| 授权签名人 | 证书/Profile/密钥库、签名与签名校验 |  |  |  |
| `release-engineer` | 发布计划、构建产物、检查单、证据完整性 |  |  |  |
| `quality-reviewer` | 发布前独立评审/质量结论 |  |  |  |
| `system-verifier` | 验收/设备矩阵/发布范围声明 |  |  |  |
| `repository-manager` | 分支/tag/远端/保护分支/CI 证据 |  |  |  |
| `technical-writer` | README、CHANGELOG、release notes、许可证文本 |  |  |  |

> 签核不等于授权；授权必须单独记录（见 §2.2）。任何空白项均视为未完成。

---

## 5. 未授权事项（本检查单不授予）

- push / force push / fetch/pull（发布任务内）；创建/删除远端分支；创建/删除 tag。
- PR/MR 创建、合并 `main`/发布分支、rebase 共享历史。
- 使用签名证书/私钥/Profile；生成/安装签名 HAP；安装到设备。
- 应用市场/远端发布、GitHub Release、任何远端写操作。
- 修改代码、版本号、bundleName、签名配置、测试/契约/`input/`。
- 破坏性数据迁移、停机、成本性 rollout。

---

## 6. 命令速查（仓库根执行）

### 6.1 构建与产物

```bash
ohpm install
hvigorw clean --mode module -p module=entry@default -p product=default -p buildMode=release assembleHap --no-daemon
find entry/build -name '*.hap' -type f
HAP="$(find entry/build -name '*.hap' -type f | head -1)"
stat -c '%n %s bytes' "$HAP"
sha256sum "$HAP"
unzip -l "$HAP"
unzip -p "$HAP" module.json
```

> 任务指定的默认 `hvigorw clean assembleHap --no-daemon` 产物为 `buildMode=debug`；发布候选使用上面的 `buildMode=release` 命令并验证 `module.json`。

### 6.2 测试与静态检查

```bash
entry/src/test/run-host-tests.sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/crosscheck_protocol_assets.py
no_proxy=127.0.0.1,localhost NO_PROXY=127.0.0.1,localhost \
  PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tools.simulator.test_gateway_contract -v
PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/check_layering.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/contract/test_check_layering.py
PYTHONDONTWRITEBYTECODE=1 python3 entry/src/test/i18n/check_i18n.py --strict-ui
PYTHONDONTWRITEBYTECODE=1 python3 tools/i18n/triage_legacy.py --check
codelinter -c code-linter.json5 -p default .
```

### 6.3 设备/签名（需授权与环境）

```bash
# 使用 SDK toolchains 中的 hdc（本机不在 PATH）
hdc list targets
hdc install <signed-hap-path>
```

> 签名构建需先完成签名配置；本检查单不提供证书/口令/私钥内容。不得在命令历史/日志中暴露秘密。

### 6.4 证据记录模板

```text
Release: YaoCore v<versionName> (<versionCode>)
Commit: <git rev-parse HEAD>
Build command: <exact command>
Toolchain: ohpm <ver>, hvigorw <ver>, SDK <ver>, Node <ver>, Java <ver>
Artifact: <path>
Size: <bytes>
SHA-256: <hash>
Signed: yes/no; signer: <role>; certificate/profile: <id/expiry, no secrets>
Install device: <model / OS / API>
Test evidence: <paths/links>
Approval: <user/role, date, scope>
Rollback: <plan/owner/previous artifact>
```

---

## 7. 当前 No-Go 摘要

在 2026-10-18、代码证据基线 `e74a181`/TEST-002（文档修订起点 `f1fbe0d`）上，以下任一未关闭即不得发布：

1. **B-01 许可证**：当前树无 `LICENSE`/`NOTICE`；公开旧版本为 Apache-2.0 + NOTICE；待用户在 §4.4 A/B/C 中决定继承/独立/迁移方案。
2. **B-02 签名**：`signingConfigs: []`，无签名/安装 smoke。
3. **B-03 设备/用户验收**：U-01..U-12 未执行。
4. **B-04 GAP-AC-01..03**：未决。
5. **B-05 远端/通道**：未授权；`origin/main=7d6f4c9` 为公开 YaoCore 1.0.0；本地 `main` 与其历史不相关；待 §4.4 A/B/C + §7.2 A-E。
6. **B-06 身份/版本**：bundleName/version/发布构建模式未冻结；旧公开 1.0.0 已用 versionCode 1000000；待 §4.4 A/B/C。
7. **B-07 CHANGELOG/Release Notes**：草案已产出 @ `63d2235`；待评审/签核，不得写成已定稿或对外发布版本。
8. **B-08 残余风险**：D-030/R4-01/PORT-LOC-01/i18n/NFR/ACK MOCK_ONLY/test lint/unsigned 风险未逐项签核。
9. **B-09 构建硬化/兼容性**：API 18 `ColumnType/TEXT/BLOB` 与 compatible API 14 运行时未验证；混淆/裁剪启用与否及符号化/回归方案未决策。

**发布 Gate 结论：`NOT_READY`。** 本检查单在 B-01..B-09 关闭并完成 §2 授权记录前，不得用于发布执行。

> 回滚阈值（RELEASE-001 §8.1.1）仍为提案，须用户批准；批准前不构成回滚授权。`release-notes-v1.0.0.md` §9 的 B 列表当前仍为 B-01..B-08，B-09 与 F-01 相关表述由 `technical-writer` 后续同步；本任务只改发布计划与检查单。

---

*RELEASE-CHECKLIST-001 结束。所有检查项以当前 revision 的可复现证据为准；不得用 host/mock/编译/未签名产物替代设备验收或发布授权。*
