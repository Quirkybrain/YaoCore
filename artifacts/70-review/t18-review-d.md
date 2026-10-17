# T-18 R3-02 最终聚焦复审报告（取消代际关闭确认 / CQG-T18 最终意见）

- **Artifact ID**: T18-REVIEW-D
- **Producer**: agent:quality-reviewer
- **Task**: `wp-081-review-t18d`（Handoff `state/handoffs/wp-081-review-t18d.json`）
- **Role**: quality-reviewer（未参与 T-18 实现，也未参与 `wp-075-fix-t18` / `wp-077-fix-t18b` / `wp-080-fix-t18c` 修复）
- **Reviewed revision**: `967e266`（`fix(provisioning): 加取消代际防止晚到提交绑定`；父提交 `78eaca9`；R2 复审基线 `4b99e64`）
- **Base branch**: `task/wp-073-ui-pages`（parent `feat/yaocore-app`）
- **Review scope**: `entry/src/main/ets/viewmodel/**`、`entry/src/test/**`、`artifacts/50-implementation/t18-fix3-report.md`；逐项核对 `78eaca9..967e266` 的 3 个变更路径
- **Inputs**: `artifacts/70-review/t18-review-c.md`、`artifacts/50-implementation/t18-fix3-report.md`、`artifacts/40-detailed-design/des-001b-domain-presentation.md`（§12.1.1）、`artifacts/60-testing/test-plan.md`；SHA-256 与 handoff 冻结值逐项一致
- **Workflow**: STANDARD / GATED_AUTO
- **Date**: 2026-10-18
- **Verdict**: **PASS（代码级，仅限 `967e266` 与本次范围）** —— **R3-02 Closed**；未发现新的 Medium/High 缺陷。设备/视觉/真实 BLE 仍 **BLOCKED**；**IG-3 NOT READY**
- **Status**: COMPLETE（代码级独立复审；未把 `BLOCKED` / `COMPILED_ONLY` 写成 PASS）

> **结论先行**：`967e266` 在 C-23 `BleProvisioningViewModel` 中引入取消代际 `cancelGeneration`，`cancel()` / `dispose()` 在第一个 `await` 之前同步递增；`prepareWifi`、`submit`、`commitResult` 及全部 BLE listener 回调按捕获代际丢弃晚到结果。独立探针确认：取消后晚到 AP/BOUND/`onCompleted`/`provision` 成功不会发布、不会进入 `commitBinding`/`addGatewayToFamily`，晚到结果草稿被零化；重复取消保持终态。**R3-02 关闭**。690 条既有用例保留，host **694/694** 复现通过；构建、lint、ohosTest 编译、i18n 门禁均可复现。剩余的是已声明的不可回滚边界（Info，R4-01）、GAP-T18-01（D-030 已风险接受但未关闭）、R3-01/T-20（Low，待检查器落地）以及 T-19 设备矩阵；因此不得宣告 CQG-T18 设备 PASS 或 IG-3 READY。

---

## 1. 范围、revision、输入与独立性

| 项 | 结果 | 证据 |
|---|---|---|
| Review base / HEAD | `78eaca9..967e266`；工作树干净 | `git rev-parse HEAD`、`git status --short --branch`（无文件变更） |
| 变更范围 | 仅 3 个路径：`entry/src/main/ets/viewmodel/BleProvisioningViewModel.ets`、`entry/src/test/host/ViewModelBle.test.mjs`、`artifacts/50-implementation/t18-fix3-report.md` | `git diff --name-status 78eaca9..967e266` |
| 越界修改 | 未发现 `pages/**`、`components/**`、`service/**`、`repository/**`、资源、`ohosTest/**`、`module.json5`、`AppScope/**`、DES/契约/测试计划的改动 | `git diff --stat 78eaca9..967e266` + 路径核对 |
| 输入完整性 | 4 个 handoff 输入的 SHA-256 全部一致 | `sha256sum` 对照 handoff |
| 作者独立性 | 本评审未参与 T-18 实现或三次修复；未编辑被审代码、测试或契约；唯一写入为本报告 | 本文件为唯一变更；`git status` 仅本报告 |
| 评审限制 | 无设备/模拟器/Previewer/签名；无法执行 ArkUI 渲染、视觉、真实 BLE/权限弹窗/AP/LAN/云/TLS | `COMPILED_ONLY` 与 `BLOCKED` 不按 PASS 处理 |

> 本报告只对 `967e266` 的代码级变更作结论；不替代 T-19 设备矩阵、T-20 检查器落地或 Stage Gate。

---

## 2. 独立复验结果（cwd = 仓库根，本次实际执行）

| # | 命令 | 本次结果 | 与修复报告的一致性 |
|---|---|---|---|
| 1 | `entry/src/test/run-host-tests.sh` | **tests 694 / pass 694 / fail 0 / skipped 0**；exit 0（duration ≈ 2938 ms） | 一致 |
| 2 | 聚焦运行 `--test-name-pattern='T18_R3_' entry/src/test/host/ViewModelBle.test.mjs` | **4/4 PASS**（4 条新 R3-02 用例） | 一致 |
| 3 | `codelinter -c code-linter.json5 -p default .` | **Defects 25 / Errors 0 / Warns 25 / Suggestions 0**；exit 0；被审 VM 文件 0 findings | 一致（与修复前同量级） |
| 4 | `hvigorw clean assembleHap --no-daemon` | **BUILD SUCCESSFUL in 14 s 509 ms**；exit 0；0 ERROR | 一致（耗时因缓存不同） |
| 5 | `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **BUILD SUCCESSFUL in 13 s 143 ms**；exit 0；仅编译、未运行 | 一致（COMPILED_ONLY） |
| 6 | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | **blockingFailures=0 / missingKeys=0**；warnings 139；hardcoded 82；exit 0 | 一致；本次未新增键/未改资源 |
| 7 | 既有用例保留核对 | `ViewModelBle.test.mjs` 测试声明 **14 → 18**（新增 4）；全量 host **690 → 694**；diff 无删除测试、无弱化断言（仅 2 行 setup 替换以接入新 fake） | 支持“690 既有用例保留” |
| 8 | 分层/依赖静态核对 | 本次 diff 无新增 import；未改 `pages/**`/`components/**`/`service/**`/`repository/**`；无 `@Provide/@Consume`、无页面 `new` 服务/仓储/VM | 支持 D-12/DI 无回归 |
| 9 | 构建产物/秘密/范围核对 | 无资源、ohosTest、module、AppScope、HAP/秘密入库；工作树干净 | 无范围外提交 |

> 复验通过只证明构建、主机逻辑、源码守卫与 i18n 检查；不证明 ArkUI 页面行为、真实 BLE 或视觉。

---

## 3. 独立探针（评审自建，未入库）

为独立验证代际语义，评审在仓库外编写 7 条临时 host 探针（Node test runner + 同一 `register-ets` 钩子；未修改仓库文件），全部通过：

| # | 探针 | 结果 |
|---|---|---|
| P1 | `ble.cancel()` 挂起时调用 `cancel()`，不等待即触发旧 listener 的 `BOUND` / `onCompleted` | 旧代际事件立即被丢弃；`result` 未发布；晚到 `onCompleted` 的 `draft-result` 立即销毁；`ble.cancel` 恢复后状态为 `CANCELLED`；晚到 `provision` 成功不调用 `commitBinding`/`addGatewayToFamily` |
| P2 | `crypto.randomBytes` 挂起时取消 | 取消后恢复的 `submit` 不创建 request draft、不调用 `provision`，状态保持 `CANCELLED` |
| P3 | `startScan` 的权限 `ensure` 挂起时取消 | 不调用 `ble.startScan`，状态保持 `CANCELLED` |
| P4 | `commitBinding` 挂起时取消，随后 `commitBinding` reject | 状态保持 `CANCELLED`、无 FAILED 覆盖、`addGatewayToFamily` 0 调用、revision 不再变化 |
| P5 | `addGatewayToFamily` 挂起时取消，随后 family add 完成 | 不发布 `BOUND`、`result` 未发布、状态保持 `CANCELLED`；family add 已在取消前发起（边界见 R4-01） |
| P6 | `submit` 进行中 `dispose()`，随后 provision 晚到成功 | 不发布成功、不绑定；`dispose` 代际生效 |
| P7 | 取消后晚到 `onProvisionError`/`FAILED` 进度/旧扫描设备 | 状态/错误/revision 均不被覆盖；旧扫描不追加结果 |

> 探针 P1 直接证明：代际在 `cancel()` 的第一个 `await` 之前已同步生效，而非仅在 `ble.cancel()` 返回后才生效。

---

## 4. R3-02 关闭状态表

> 状态定义：**Closed** = 原 finding 的核心问题已修复且有代码/测试/独立探针证据；**Closed（边界已声明）** = 主缺陷关闭，但存在已记录的不可回滚边界；**Open** = 未关闭。

| R3-02 子项 | 代码/证据 | 状态 |
|---|---|---|
| `cancel()` 在首个 `await` 前同步递增取消代际 | `BleProvisioningViewModel.ets:432-440`；`cancelGeneration++` 位于 `try/await` 之前 | **Closed**（P1） |
| `dispose()` 也递增取消代际 | `:480-488` | **Closed**（P6） |
| `prepareWifi` 每 await 后校验；晚到 AP 列表丢弃 | `:303,313-315,316-322,327-330`；`onAccessPoints(..., generation)` `:563-566`；测试 `T18_R3_cancelDuringPrepareWifiDropsLateAccessPoints`（`ViewModelBle.test.mjs:378`） | **Closed** |
| `submit` 在 crypto await 后、publish 后、provision await 后校验 | `:352,360-362,389-391,392-400,403-411`；测试 `T18_R3_cancelDuringSubmitDropsLateBindingSuccess`（`:410`） | **Closed**（P1/P2） |
| 晚到 `provision` 成功不进入 `commitResult`；晚到结果草稿零化 | `:397-399`；`destroyResultDraft` `:718-726`；测试断言 `draft-result` 被销毁 | **Closed** |
| `commitResult` 入口、`commitBinding` 后、`addGatewayToFamily` 后校验 | `:597-602,607-616,617-624,625-636,637-639`；测试 `T18_R3_cancelDuringCommitBindingSkipsFamilyAddAndBound`（`:444`） | **Closed**（P4/P5） |
| 晚到 `onCompleted` 不发布、草稿立即销毁 | `:586-595` | **Closed**（P1/P6） |
| 晚到 `BOUND`/`onStateChanged`/`onError` 不覆盖 `CANCELLED` | `:532-584`；`WizardProgressListener` 透传 generation `:797-826` | **Closed**（P1/P7） |
| 取消后 `commitBinding`/`addGatewayToFamily` 零调用（晚到 provision 成功路径） | 测试 `:410` 断言 0 调用；P1/P2 复验 | **Closed** |
| 重复取消幂等 | `:432-451`；测试 `T18_R3_repeatedCancelIsIdempotentAndDropsLateSuccess`（`:465`）；终态保持 `CANCELLED`，`canCancel=false`，晚到成功不绑定 | **Closed**（revision 每次递增但终态稳定，无异常） |
| 旧扫描 listener 按 `scanToken` 丢弃 | `:774-794`；`onScanDevice/onScanFinished/onScanError` `:492-530`；P7 | **Closed** |
| `dispose` 后晚到结果不发布/不提交 | `:480-488`；P6 | **Closed** |
| 不可回滚边界（`commitBinding` 已发起 / `addGatewayToFamily` 已发起） | 修复报告 §2.4 记录 `commitBinding`；`addGatewayToFamily` 边界见 R4-01；VM 只抑制后续 `BOUND`/family add，不撤销已发起的 durable 写 | **Closed（边界已声明）** |

**结论：R3-02 关闭（代码级）**。原缺陷“取消后晚到 `submit` 成功仍可进入 `commitResult` → `commitBinding` → `addGatewayToFamily` → `BOUND`”已被代际校验阻断；页面 `cancelled` 遮挡不再是唯一保护。

---

## 5. 回归与约束检查

| 项 | 结果 | 证据 |
|---|---|---|
| 既有 690 条 host 用例 | **保留** | 全量 694/694；`ViewModelBle.test.mjs` 14→18；diff 无删除测试/弱化断言 |
| R2-02 取消随时可用 | **未破坏** | `ProvisioningPage.ets:255-272` 未改；取消按钮 `.enabled(this.view.canCancel \|\| this.localStep < 5)` 未改；`T18_R2_provisioningCancelStaysAvailableWhileBusy`、`T18_R2_cancelDuringPrepareWifiCancelsBleAndClearsTimer` 均通过 |
| R2-02 取消清理 | **未破坏** | `cancel()` 仍执行 `scanGeneration++`、`clearScanTimer()`、`ble.cancel()`、`destroyDrafts()`、发布 `CANCELLED`（`:438-451`） |
| 页面/资源/i18n | **未改动** | `git diff` 仅 3 个路径；无新资源键；`--strict-ui` blocking=0/missing=0 |
| DES-B §12.1.1 语义 | **一致** | “取消……由 `cancelled`/扫描代际保护；晚到结果不得覆盖取消界面”由 `cancelGeneration` + listener 代际实现；未改冻结签名/错误码/状态枚举 |
| 写范围 | **合规** | 修复仅 VM + host 测试 + 报告；本复审仅写本报告 |
| 秘密/构建产物 | **无入库** | 工作树干净；无 HAP/签名/秘密 |

> 注：`cancelGeneration` 只保护“取消前已发起的旧操作”；取消后新发起的操作按新代际正常运行。页面在取消时清空 PoP/SSID/密码，常规 UI 下不会在取消窗口内重新提交；该语义不作为本 finding 的阻塞项。

---

## 6. 新发现（R4-xx）

### R4-01（Info，边界文档/覆盖补充）：`addGatewayToFamily` 已发起后的取消边界未在修复报告中明示

- **位置**：`entry/src/main/ets/viewmodel/BleProvisioningViewModel.ets:625-639`；`artifacts/50-implementation/t18-fix3-report.md` §2.4。
- **证据**：独立探针 P5：当 `commitBinding` 已完成、`addGatewayToFamily` 处于 in-flight 时取消，VM 正确不发布 `BOUND`/`result`，状态保持 `CANCELLED`；但 `addGatewayToFamily` 的 durable 写入已发起并可能完成（探针记录 1 次调用）。
- **影响**：用户看到 `CANCELLED`，但家庭行可能已包含该网关；`addGatewayToFamily` 本身对重复 gatewayId 幂等（`FamilyRepository.ets:284-307`），不会重复追加；route 也已 durable。不会产生“重复绑定”或成功界面，但属于与 `commitBinding` 同类的不可回滚边界，修复报告 §2.4 只明确写了 `commitBinding`。
- **建议/归属**：`implementation-engineer`/`solution-architect` 在下一次文档修订中把该边界补入 §2.4（或在 T-19 设备矩阵记录）；可选补一条 host 边界测试。**不阻断 CQG-T18**，不影响 R3-02 关闭。
- **严重度理由**：无 UI 成功误报、无重复绑定、无秘密泄漏；仅边界披露不完整，故为 Info。

> 未发现新的 Medium/High 代码缺陷；R3-02 的修复未引入新的公开签名、错误码或资源变更。`onProvisionState` 等回调的可选 generation 参数仅用于保持既有 host 测试调用形状，生产路径始终由 `WizardProgressListener` 传入代际（修复报告 §6.3 已披露），不列为新 finding。

---

## 7. CQG-T18 对照与最终意见

| 检查 | 结果 | 证据/说明 |
|---|---|---|
| 构建（生产图） | ✅ **PASS** | `clean assembleHap` BUILD SUCCESSFUL 14 s 509 ms，0 ERROR |
| 静态检查 | ✅ **PASS** | codelinter 0 error / 25 warn / 0 suggestion；被审 VM 0 findings |
| Host 测试 | ✅ **PASS** | **694/694**，fail/skipped 0；690 保留 + 4 新增；R3 聚焦 4/4 |
| i18n / parity | ✅ **PASS** | `--strict-ui` blocking 0 / missing 0；warnings 139 / hardcoded 82；无资源变更 |
| 契约 | ✅ **PASS（登记）** | DES-B §12.1.1 语义与实现一致；`EXT-DES-B-28..32` 未变；无冻结签名/错误码变更；T-20 检查器待落地（R3-01 Low） |
| 安全 | ✅ **PASS（代码级）** | R3-02 关闭：取消后晚到 AP/BOUND/`onCompleted`/`provision` 成功不发布、不绑定、草稿零化；GAP-T18-01 为已接受的上游缺口（见下） |
| RBAC | ✅ **PASS（代码级，含已接受缺口）** | R2-01 UI ADMIN 门、场景/房间服务层 RBAC 未受本次改动影响；GAP-T18-01 未关闭，不得宣称服务层 RBAC 已闭合 |
| 分层/DI | ✅ **PASS（有 R3-01 记录项）** | 本次无新增 import；仅 VM 内部改动；R3-01（D-12 pages 既有 DTO/枚举 allowlist）仍待 T-20 |
| 独立评审 | ✅ **本轮完成** | 本报告为未参与实现/修复的 quality-reviewer 最终聚焦复审；非作者自审 |
| 设备/视觉/真实 BLE | ⚠️ **BLOCKED** | 无设备/模拟器/Previewer/签名；ohosTest 仅 COMPILED_ONLY；真实 BLE/权限弹窗/AP/绑定探针/LAN/云/TLS 未验证 |
| GAP-T18-01 | ⚠️ **ACCEPTED（D-030，未关闭）** | `FamilyRepository.addGatewayToFamily` 仍无 actor/RBAC；D-030 记录 v1 风险接受；Stage Gate 必须记录该限制，不得写成服务层已闭合 |
| R3-01 / T-20 | ⚠️ **Open（Low，T-20）** | D-12 文件/符号级 allowlist 未落地；不阻断 R3-02/CQG-T18 代码级结论 |
| IG-3 | ❌ **NOT READY** | T-19 设备矩阵未执行；T-20 检查器/R3-01 未落地；GAP-T18-01 虽已接受但需 Stage Gate 记录；设备项 BLOCKED |

### CQG-T18 最终意见

**PASS（代码级，仅限 `967e266`）**：`BleProvisioningViewModel` 的取消代际修复成立，R3-02 关闭；构建、lint、host 694/694、ohosTest 编译、i18n 门禁与契约语义均可复现。**无新的阻断性 finding**。以下边界必须保留在结论中：

1. **设备/视觉/真实 BLE 仍 BLOCKED**：不得把 CQG-T18 写成设备 PASS；T-19 设备矩阵（取消按钮可见性、真实 BLE cancel、权限弹窗、AP 扫描、绑定探针、LAN/云/TLS）仍需执行。
2. **GAP-T18-01 未关闭**：D-030 已作 v1 风险接受，但 Stage Gate 必须记录；不得宣称 `addGatewayToFamily` 服务层 RBAC 已闭合。
3. **R3-01/T-20**：D-12 pages 既有 service/repository 只读 DTO/枚举的正式 allowlist 与检查器仍待 T-20；Low，不阻断 T-18 代码级结论。
4. **R4-01（Info）**：`addGatewayToFamily` in-flight 取消边界建议补文档；不阻断。
5. **IG-3 NOT READY**：T-19/T-20 与 Stage Gate 记录未完成前不得宣告集成稳定。

最终 Stage Gate / 用户验收决定由 Orchestrator/Stage Gate 记录；本报告不授予 Stage 或用户验收。

---

## 8. 残余风险与跟踪

| 项 | 状态 | 归属 |
|---|---|---|
| `commitBinding` 已发起后的取消：route 可能 durable，VM 不重启 family add/BOUND | Recorded（修复报告 §2.4） | C-23/T-19；已声明边界 |
| `addGatewayToFamily` 已发起后的取消：family 写入可能完成，VM 只抑制 BOUND | **R4-01 Info** | 文档补充/T-19 |
| `cancel()` 的 `CANCELLED` 发布仍等待 `ble.cancel()`；下层若不返回，页面“已取消”确认会延迟（总线忙状态已立即释放） | Recorded（既有行为，本次未改） | C-19/T-19 设备验证 |
| 可选 generation 回调参数：直接调用 VM 回调（非 listener）不享受取消保护 | Recorded（修复报告 §6.3） | 仅测试兼容；生产 listener 始终传代际 |
| R3-01 pages 既有 service/repository DTO/枚举未正式列入 D-12 | **Open（Low）** | `solution-architect` + T-20 |
| GAP-T18-01 `addGatewayToFamily` 无服务层 RBAC | **Accepted（D-030）/未关闭** | Stage Gate 记录；C-22/C-09/C-15 |
| 真实 BLE/权限弹窗/AP/绑定探针/LAN/云/TLS | **BLOCKED** | T-19 / 用户实机 |
| 设备/视觉/动效/读屏 | **BLOCKED** | T-19 |
| T-20 分层/RBAC/i18n/契约检查器 | **Pending** | T-20 |

**IG-3**：**NOT READY**。R3-02 已不再是 IG-3 的阻塞项；仍缺 T-19 设备矩阵、T-20 检查器/R3-01 收口，以及 Stage Gate 对 D-030 的书面记录。

---

## 9. 独立声明与裁决边界

1. 本复审由 `quality-reviewer` 独立完成；未参与 T-18 实现或 `wp-075`/`wp-077`/`wp-080` 修复；未编辑任何被审代码、测试或契约。本任务唯一写入为 `artifacts/70-review/t18-review-d.md`（覆写 guard 前置占位）。
2. 评审基于 `967e266`（父 `78eaca9`）与 handoff 冻结输入；4 个输入 SHA-256 与 handoff 一致；未修改 `input/`、DES-A/DES-B、contract-baseline、test-plan 或旧评审报告。
3. 复验命令均在本机实际执行：host 694/694、R3 聚焦 4/4、codelinter 0 error、clean assembleHap BUILD SUCCESSFUL、ohosTest 编译 BUILD SUCCESSFUL、i18n blocking 0/missing 0；独立临时探针 7/7（未入库）；未把 `COMPILED_ONLY`/`BLOCKED` 写成 PASS。
4. **Verdict 仅覆盖本报告 §1 的 revision 与范围**：PASS（代码级）；R3-02 关闭；设备项 BLOCKED；IG-3 NOT READY；不授予 Stage Gate 或用户验收。
5. 未发现作者自审替代；未发现越界产品代码改动；未发现秘密/构建产物入库；未发现既有 690 条 host 测试被删除或弱化。

---

## 10. Next action

1. **R3-02**：无需进一步代码修复；保留 `cancelGeneration`/listener 代际与 4 条 host 负例作为回归基线。
2. **R4-01（Info）**：在修复报告 §2.4 或设计注记中补充 `addGatewayToFamily` in-flight 边界；可选补 host 边界测试。
3. **T-19**：执行设备/视觉/真实 BLE cancel/权限弹窗/AP/绑定探针/LAN/云/TLS 矩阵；复跑本报告 §2 命令并记录证据。
4. **T-20/R3-01**：落地 D-12 文件/符号级 allowlist 与检查器；不要把整个 `service/**` 放宽。
5. **GAP-T18-01**：Stage Gate 按 D-030 记录风险接受/限制；不得宣称服务层 RBAC 已闭合。
6. 完成上述后重新评估 IG-3；CQG-T18 的最终 Stage Gate 决定由 Orchestrator 记录。

```text
STATUS: COMPLETE
SUMMARY: 复审 967e266（R3-02 取消代际修复）；R3-02 关闭（代码级），晚到 AP/BOUND/onCompleted/provision 成功均被丢弃，commitBinding/addGatewayToFamily 零调用（晚到 provision 路径），晚到草稿零化，重复取消终态稳定；690 既有用例保留、694/694 复现；新增 R4-01 Info（addGatewayToFamily in-flight 边界文档）
ARTIFACTS_CREATED: artifacts/70-review/t18-review-d.md
ARTIFACTS_UPDATED: artifacts/70-review/t18-review-d.md（覆写 guard 占位）
RISKS: GAP-T18-01 已 D-030 接受但未关闭；R3-01/T-20 Low 待落地；设备/真实 BLE/LAN/云 BLOCKED；R4-01 Info
VALIDATION: host 694/694 exit 0；R3 聚焦 4/4；codelinter 0 error/25 warn；clean assembleHap SUCCESS 14s509；ohosTest 编译 SUCCESS 13s143；i18n blocking=0/missing=0；独立探针 7/7
NEEDS_CLARIFICATION: no
NEXT_ACTION: R4-01 文档补充 + T-19 设备矩阵 + T-20/R3-01 收口 + Stage Gate 记录 D-030 后复评 IG-3
```
