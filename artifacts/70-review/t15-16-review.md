# T-15 / T-16 独立评审报告（C-21 / C-22 / C-23 ViewModel 层）

- **Artifact ID**: REVIEW-T15-T16
- **Producer**: agent:quality-reviewer
- **Type**: Independent Code Review
- **Status**: **CHANGES_REQUIRED（代码级；不是 PASS）**
- **Date**: 2026-10-17
- **Task**: `wp-061-review-t15-16`（task 分支 `task/wp-060-vm`，父分支 `feat/yaocore-app`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`（CQG-T15 / CQG-T16 前）
- **Reviewed revision**: `ffadebf01ec5050808ea937b1e52b06422af78af`（实现 diff `2a37a6a..ffadebf`，38 路径）
- **Review snapshot**: `refs/swe/snapshots/20261017T155049Z-wp-061-review-t15-16-708da53e`（commit `24ec3f7ae172c1e54187a6069bda61f7230798a7`）
- **Independence**: 本评审由未参与 T-15/T-16 实现、测试或实现报告编写的 `quality-reviewer` 执行。评审期间未修改任何被审产品代码、测试、证据或 `artifacts/50-implementation/t15-16-vm.md`；唯一仓库写入为本报告。所有行为探针与上游编译探针均在 `/tmp/opencode` 的只读副本/临时脚本中执行，未在仓库落盘，原工作区保持 clean。

> 结论先行：88 条新增 host 用例真实执行，593/593 通过；`codelinter`、clean `assembleHap`、ohosTest 仅编译均通过；三态主路径、55ms 合并/TouchUp、LAN→云有限回退、GUEST fail-closed（F-08）、房间删除保护、场景局部失败、配网 6 步与 R-1 草稿重签的主体实现与契约一致。但独立探针复现了 **2 个 High 阻断项**：连续控制取消后在途结果仍写回 `PENDING`（F-01），以及门锁把“控制 ACK 成功”当作“门状态已确认”（F-02：解锁 `UNVERIFIED` 也显示 `OPEN`；关锁回报 `open=true` 时门状态 `FAILED/OPEN` 而控制仍显示 `COMMITTED`）。另有 2 个 Medium（配网 `back()` 未停止扫描/定时器；Settings `testConnection` 的 Token 过期未刷新 `state.cloud`）和若干 Low/跟踪项。**本轮不能给出 PASS；CQG-T15/CQG-T16 应记为 CHANGES_REQUIRED，C-21..C-23 保持 `UNVERIFIED`。**

---

## 1. 范围、revision 与输入完整性

### 1.1 评审范围

```text
entry/src/main/ets/viewmodel/               # 14 个产品文件（VM + core/** + ViewModelPorts）
entry/src/test/                             # host 测试、helper、证据日志、README
entry/src/ohosTest/ets/test/                # 设备编译骨架、List.test.ets、README
artifacts/50-implementation/t15-16-vm.md    # 实现报告（只读）
```

- 实际被审变更为 `2a37a6a..ffadebf` 的 **38 个路径**：14 个产品文件、12 个 host `.test.mjs` + 2 个 helper、1 个 ohosTest 骨架 + `List.test.ets` 注册、2 个 README、5 个证据日志、1 个实现报告。
- 交叉读取但未修改：DES-B §10/§11/§12（及 §3.1.3/§3.3.2 的 C-08 加入语义）、DES-A §3.7/§16.9、`contract-baseline.md`、`project-constraints.md`、`i18n-resource-design.md`、TEST-001、`state/decisions/wp-004-resolutions.md`、C-08/C-10/C-12/C-15/C-18/C-19 的现有实现与端口。
- 明确排除：真实设备/模拟器、真实 LAN/云/BLE、UI 三态视觉与动画、NFR 4.3 p95、C-28 组合根、T-17/T-18 页面与资源落地、T-19 全量执行、T-20 安全评审、用户验收、完整 Stage Gate。这些保持 `BLOCKED` / `COMPILED_ONLY` / `UNAVAILABLE`，本报告不将其写成 PASS。

### 1.2 输入 pin 与快照

handoff 的 8 个 `inputs` SHA-256 **8/8 一致**；`config/git-policy.json` 的 SHA-256（`3b8ddffd4494…`）与 handoff 一致。复验前后 `git status --short` clean，HEAD = `ffadebf`，38 路径与 commit 一致。

| 输入 | SHA-256 前 12 位 | 结果 |
|---|---|---|
| `artifacts/50-implementation/t15-16-vm.md` | `75638e1c9990` | 一致 |
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | `e8d3869b0990` | 一致 |
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `3a02ecbf266b` | 一致 |
| `artifacts/20-architecture/contract-baseline.md` | `883e09bb34ea` | 一致 |
| `artifacts/20-architecture/project-constraints.md` | `283046210e68` | 一致 |
| `artifacts/20-architecture/i18n-resource-design.md` | `3fa7f3881cda` | 一致 |
| `artifacts/60-testing/test-plan.md` | `33485cc39abd` | 一致 |
| `state/decisions/wp-004-resolutions.md` | `2a485fcef8df` | 一致 |
| `config/git-policy.json` | `3b8ddffd4494` | 一致 |

### 1.3 本评审实际复验（cwd = 仓库根）

| 命令 | 结果 | 说明 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS：593 tests / 593 pass / 0 fail / 0 skipped / 0 todo，exit 0** | 与 `evidence/t15-16-host-node-tests.tap` 的 593/593 一致；T-15/T-16 新增 88 条（C-21 43 + C-22/C-23 45），基线 505 条无删除 |
| `codelinter -c code-linter.json5 -p default .` | **PASS：No defects found in your code，exit 0** | 与 `t15-16-codelinter.log` 一致；仅覆盖产品源码 |
| `hvigorw clean assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0**（35 tasks；34 executed / 1 up-to-date） | 与 `t15-16-clean-assemble.log` 一致 |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0**（35 tasks） | 与 `t15-16-ohosTest-assemble.log` 一致；骨架 import 了全部 C-21..C-23 VM，因此这是 **ArkTS 类型/编译证据**，不是设备执行证据 |
| `python3 entry/src/test/i18n/check_i18n.py --root . --strict-ui` | **PASS：CHK-01..09 全部 PASS，0 blocking，67 warnings，missingKeys=0，exit 0** | 新增 ViewModel 没有硬编码 UI 文案；warnings 为既有 Index/T-14 协议别名等 |
| `git status --short` / `git diff --stat` | **PASS：clean / 空** | 构建仅产生 ignored 的 build 目录，未产生跟踪文件变化 |

测试计数核对：`ViewModel*.test.mjs` 共 12 个文件、88 条 `test()`（Throttle 5、Device 7、Coordinator 7、Door 9、DoorVM 4、Home 7、Climate 4、Family 10、Room 7、Scene 7、Ble 11、Settings 10），与实现报告 §4 的 88 条一致；无跳过/待办。设备骨架保持 `BLOCKED_ON_DEVICE_RUNNER`，未把编译成功写成设备 PASS。

### 1.4 独立只读探针（不写入仓库）

除现有测试外，本评审直接用真实产品类 + 共享 fake 复现了以下行为（脚本位于 `/tmp/opencode/probe-*.mjs`，原仓库未修改）：

1. **连续控制取消后晚到结果污染状态**（F-01）：`PENDING → cancelContinuous() = IDLE`；随后在途 dispatch 成功返回 → 控制态重新变为 `PENDING`，`optimisticValue=80`、`confirmedValue=undefined`，且没有 gate 能再完成它。
2. **门锁解锁把 `UNVERIFIED` 当作 `OPEN`**（F-02）：ACK accepted、`stateVerification=UNVERIFIED`、无 reported `open` → `DoorStage.OPEN / DoorLockState.OPEN / ControlPhase.COMMITTED`。
3. **门锁关锁回报 `open=true` 时控制仍 COMMITTED**（F-02）：ACK accepted、verification `MATCH`、reported `open=true` → `DoorStage.FAILED / DoorLockState.OPEN / ControlPhase.COMMITTED`（契约要求 FAILED + REVERT）。
4. **配网 `back()` 未清理扫描**（F-03）：`STEP_1_SCAN → back() = STEP_0`，但 BLE `stopScan` 调用数为 0、10s 定时器仍 pending；10s 后状态跳回 `STEP_1` 并报 `PROVISIONING_DEVICE_NOT_FOUND`。
5. **Settings Token 过期状态不刷新**（F-04）：`testConnection()` 返回 `CLOUD_TOKEN_EXPIRED` 且底层 `CloudService` 视图已为 `TOKEN_EXPIRED`，但 `SettingsViewState.cloud.state` 仍为 `CONFIGURED`（仅 `error` 有值）。
6. **上游 C-18 编译阻塞独立复现**（U-01）：在 `/tmp/opencode/yaocore-c18-probe` 的副本中给 ohosTest 骨架临时加入 `GatewayDiscoveryService` import，构建 exit 255，报 `arkts-no-structural-typing` 于 `GatewayDiscoveryService.ets:331:18` 与 `:344:18`；原仓库因未 import 该文件而构建通过——与实现报告 §5 的描述一致。

这些探针仅使用内存 fake/公开测试数据，不构成设备、真实网络或真实云证据。

---

## 2. Findings

严重度定义：**High** = 会导致核心契约/安全语义错误、用户可见错误状态或阻断 CQG；**Medium** = 契约/状态/清理缺口，需在本修复轮或书面裁定后关闭；**Low/Info** = 文档、可观测状态完整性、测试补强与已登记残余。上游项用 `U-*` 区分，不计入 T-15/T-16 代码通过条件，但必须在 T-17 前闭环。

| ID | 严重度 | 位置 | 契约/依据 | 问题/影响 | 建议 |
|---|---|---|---|---|---|
| **F-01** | **High（阻断）** | `DeviceViewModel.ets:371-404`（`dispatchContinuous` 收到 `token` 但从未校验）、`:271-285`（`cancelContinuous`）、`:236-269`（`endContinuous`）、`:215-216`（gate 闭包） | DES-B §10.1.3（`cancelContinuous`：取消 timer、丢弃 pending、不发送、回弹 confirmed）、§10.1.4（cancel 后底层请求结果不得写 state，VM 用 operation token 丢弃）、§10.3.2（页面离开/dispose 在途结果不得写 state）；D-019 | 连续控制在途时取消：`cancelContinuous()` 已发布 `IDLE`，但晚到的 dispatch 成功仍把控制态写回 `PENDING`（探针已复现）。该 `PENDING` 没有存活的 `ThrottleGate` 来完成/回弹，UI 会永久显示“发送中”并显示用户已取消的乐观值；`endContinuous` 与 `cancelContinuous` 并发时也没有会话 token，可能把取消后的状态覆盖为 COMMITTED。`ClimateViewModel.ets:292-312` 的 `dispatchTemperature` 同样没有 generation/token 校验（未复现为可见错误，但同一根因） | 在 `beginContinuous` 为每个 gate 生成会话 token/generation，并在 `dispatchContinuous` 入口与 `await` 之后校验；`cancelContinuous`/`dispose`/`endContinuous` 递增该 token，丢弃旧结果；`endContinuous` 完成后仅在 token 仍匹配时发布 COMMITTED/REVERT。补回归测试：dispatch 延迟 → cancel → resolve（不得出现 PENDING）；dispatch 延迟 → 新 begin → 旧结果不得覆盖；cancel 与 endContinuous 并发。Climate 同步修复并补测 |
| **F-02** | **High（阻断）** | `DoorViewModel.ets:240-250`（`succeeded()` 后无条件 COMMITTED/markUnlocked）、`:133-135`（unlock）、`:202-273`；`core/DoorConfirmationTracker.ets:263-270`（`markUnlocked`）、`:166-177`（open==true 的 FAILED 分支） | DES-B §10.1.7：`lock()` 仅 `ackAccepted && reported open==false` 才进入 GATEWAY_CONFIRMED，否则 `FAILED + REVERT`；`unlock()` 单次 ACK **`open==true`** 才 `OPEN`；§10.3.3/SC-14（禁止虚构成功） | 门锁把“控制层 ACK 成功”当作“门状态已确认”：(a) unlock 在 ACK accepted + `UNVERIFIED`/无 reported `open` 时直接 `markUnlocked()` → `OPEN/OPEN/COMMITTED`（探针已复现），没有“已执行、状态未回传”的如实提示；(b) CLOSE 在 reported `open=true` 时 tracker 已判 `FAILED/OPEN`，但 `succeeded()` 仍为 true，VM 随后发布 `COMMITTED`（探针已复现），与“FAILED + REVERT”冲突，用户会看到控制成功而门实际未锁 | 由 tracker 的门结果驱动 ControlUiState：CLOSE 仅在 tracker 进入 GATEWAY_CONFIRMED/SECURED/WAITING_CONTACT/UNVERIFIED（即 reported open==false 或明确无回传）时 COMMITTED；reported open==true 或 FAILED → REVERT。unlock 要求 `reportedOpen(execution)===true`，否则保持上一确认状态并给 `UNVERIFIED/UNCONFIRMED` + “已执行，状态未回传”；补 unlock 无 reported/`open=false`、CLOSE reported `open=true` 两条回归测试 |
| **F-03** | **Medium** | `BleProvisioningViewModel.ets:334-344`（`back`）、`:194-220`（`startScan` 定时器）、`:222-230`（`stopScan`） | DES-B §12.1.1：只有 STEP_0/1 可自由后退；任何 cancel/fail/back（step≥2）必须清理；§12.3.1：任一步取消含 `ble.cancel()` 清理；PR-13（扫描 10s） | 从 STEP_1 后退只发布 STEP_0，不调用 `stopScan()`、不清 `scanTimerId`（探针已复现：ble stop 调用 0、定时器仍 pending）。10s 后无结果定时器把状态强行拉回 STEP_1 并报 `PROVISIONING_DEVICE_NOT_FOUND`；扫描 radio 也可能继续工作，违反“自由后退”和清理语义 | `back()` 在 STEP_1 时先 `clearScanTimer()` + `await this.ble.stopScan()`（失败仅日志），再发布 STEP_0/IDLE；测试断言 stopScan 被调用、定时器为 0、推进 10s 不产生错误；STEP_2+ 保持现有确认取消路径 |
| **F-04** | **Medium** | `SettingsViewModel.ets:251-278`（`testCloudConnection` 失败分支只 `fail`）、`:412-414`（`loadCloud`） | DES-B §12.1.2：`testCloudConnection` 的 401/403 → `TOKEN_EXPIRED`，不自动刷新；§12.3.2 Token 状态机；F-03（testConnection 只更新瞬时层） | 探针复现：底层 `CloudService` 已把状态置为 `TOKEN_EXPIRED`，但 Settings 的 `state.cloud.state` 仍是旧的 `CONFIGURED`（只有 `error` 是 token 过期）。用户在“测试连接”失败后仍看到云为已配置，不会得到“更新 IAM Token”的持久提示；`loadCloud` 只在成功/清 token 时调用 | 在 `testConnection` 返回 invalid 后重新 `loadCloud()` 并发布（或订阅 `CloudService` 状态事件）；测试除 `error.code` 外必须断言 `state.cloud.state==='TOKEN_EXPIRED'`（以及网络失败不把状态改成 UNAVAILABLE 的 F-03 负例） |
| **F-05** | Low（状态机完整性） | `core/DoorConfirmationTracker.ets:147-191`、`:61-72`（`DoorStage`） | DES-B §10.1.7 状态图：`PENDING → GATEWAY_CONFIRMED → SECURED/WAITING_CONTACT/UNVERIFIED`；四阶段门锁 | `DoorStage.GATEWAY_CONFIRMED` 从未被发布：`onResult` 直接进入 SECURED/WAITING_CONTACT/UNVERIFIED。最终三结果语义正确，但 UI 无法显示“网关已确认、等待门磁”的中间态，公开枚举值实际不可达；“四阶段”在可观察状态上只有三段 | 若中间态需要 UI/动画：在 link 分支前先发布/回调 GATEWAY_CONFIRMED（tracker 需要额外通知或 VM 读取后分两跳发布）；若有意合并，更新 DES-B/实现报告并移除或标注不可达枚举。加一条状态序列测试 |
| **F-06** | Low（契约冲突，需上游裁定） | `FamilyViewModel.ets:343-376`（`submitJoinInvitation`/`completeJoinWithProfile`）；`FamilyJoinSession.ets:110-134` | DES-B §11.3.2：`APPLYING → COMPLETED: createProfile + setActiveFamily`；而 §3.1.3/§3.3.2：C-08 在 `acceptInvitation` + 成员 upsert 后即 `COMPLETED`，不创建 LocalProfile | 当前 VM 原样透传 C-08 状态：`submitJoinInvitation` 成功即 `COMPLETED`，`completeJoinWithProfile` 之后 join 状态不再变化。`T16_Family_joinStateMachineAndProfileCompletion` 用 FakeJoinSession 把该时序固化为期望。C-08 与 C-22 对 COMPLETED 的定义不一致；UI 可能在本地档案创建前把加入流程当作完成 | 由 `solution-architect` 裁定二选一：C-08 增加 profile 完成后的状态迁移，或 C-22 暴露 `profileRequired`/独立 phase 并在 `completeJoinWithProfile` 成功后置 COMPLETED；更新 §3.1.3/§11.3.2 与测试，不得保留两套定义 |
| **F-07** | Low（部分失败/重试） | `FamilyViewModel.ets:357-376` | DES-B §11.1.1：失败保留 `AcceptedInvitation` 并允许重试（不重复接受容器）；join 后切换家庭需 `refreshSessionGate`/`needsUnlock` | `completeJoinWithProfile` 若 `createProfile` 成功但 `switchFamily` 失败，重试会再次 `createProfile` 并因 C-12 非幂等抛 `AUTH_PROFILE_EXISTS`，流程卡死；同时 `switchFamily` 返回的 `requiresUnlock` 被丢弃，`FamilyViewState.needsUnlock` 可能保持 false | 将 `AUTH_PROFILE_EXISTS` 视为档案已存在并继续 `switchFamily`；把 `switchFamily` 的 `requiresUnlock` 写入 state；补“profile 成功 + switch 失败 → 重试成功/解锁提示”测试 |
| **F-08** | Low（测试有效性） | `ViewModelDevice.test.mjs:131-144`（取消前未启动 dispatch）、`ViewModelDoorVM.test.mjs:84-92`（只测 unlock 正例）、`ViewModelBle.test.mjs`（无 back 用例）、`ViewModelSettings.test.mjs:185-197`（只断言 error）、`ViewModelThrottle.test.mjs`（无 onCommit-before-55/cancel-in-flight） | DES-B §10.4/§11.4/§12.4 host 测试清单；TEST-001 CQG-T15/T16 | 88 条用例真实执行且主体有效，但恰好缺少能暴露 F-01..F-04 的负例/并发路径；测试 PASS 不能作为这些语义成立的证据。`T16_Family_join...` 还用 fake 固化了 F-06 的冲突时序 | 随 F-01..F-04 修复补齐回归：cancel-in-flight、end/cancel 并发、unlock UNVERIFIED/open=false、CLOSE open=true、back 扫描清理、token 过期 `state.cloud`、onCommit-before-55、Throttle cancel with waiter；测试应断言状态与调用次数，而不仅是错误码 |
| **U-01** | **High（上游；T-17 前置阻断）** | `entry/src/main/ets/service/gateway/GatewayDiscoveryService.ets:331:18`、`:344:18`（`withProbeTimeout` 的 `Promise.then/catch` 回调） | DES-B §2.4 C-28 装配；PL-01（ArkTS 构造函数）、PL-03；C-18 交付 | 实现报告 §5 已如实记录：该 C-18 文件一旦进入生产编译图即报 `arkts-no-structural-typing`。本评审在 `/tmp` 副本中给 ohosTest 骨架临时 import 该类，独立复现两个错误（exit 255）；当前 T-15/T-16 通过 `ManualDiscoveryPort` 隔离，未把该类拉入编译图，因此当前构建通过是**隔离**而不是该类可用。T-17 若直接 import `GatewayDiscoveryService` 会立即爆雷 | 在 T-17 前由 C-18 owner 修复（改为显式 `new Promise`/`async` 包装或 ArkTS 允许的 typed 回调），并在 ohosTest 骨架中保留一条 import 该类的编译接线（或单独 compile probe），确保后续不会再次被未引用裁掉；本项不得作为 T-15/T-16 的放宽理由 |
| **U-02** | Low（资源；T-18） | `SettingsViewModel.ets:40`（`settings.cloud.single_gateway_required`）；`entry/src/main/resources/rawfile/i18n/{zh-CN,en-US}.json` | I18N-05（key parity/fallback）；DES-B §12.3.2 F-06 提示；i18n 设计 §6 | 该键在 zh-CN/en-US 均不存在，`t()` 会回退显示原始 key；实现报告 §5 已登记 `DEFERRED（T-18）`。直接扁平化检查确认它是 VM 引用键中唯一缺失项（`brand.*` 属 T-14 F-05 上游遗留）。CHK-06 因常量/动态调用未报 missing | T-18 补齐 zh-CN/en-US 两键并纳入 parity；为 `SettingsViewModel` 的常量键增加静态检查（或 allowlist/编译期常量）避免再次漏检。`brand.*` 由 T-14/C-24/C-27 资源任务一并补齐 |
| **U-03** | Info（上游/已登记） | `ViewModelPorts.ets:29-33`；`SettingsViewModel.ets:416-443`（`pinMatched` 留空/`rotationRecommended=false`）；`BleProvisioningViewModel.ets:456`（`FamilyRepository.addGatewayToFamily`） | DES-B §12.1.2（`pinMatched` 来自 probe）；C-08 `addGatewayToFamily` 契约缺口；C-18/C-27 | `DiscoveryCandidate` 不携带 matched pin，VM 诚实留空；C-08 未暴露 `addGatewayToFamily`，VM 使用 `FamilyRepository`（报告 §5 已记录）；`rotationRecommended` 无来源，恒 false。均非 T-15/16 代码缺陷，但 T-17/T-18 必须决定是否补端口/字段，不能把“留空/false”当作已实现 | 由 C-18/C-27/C-08 owner 在装配任务中提供 matched pin 与 rotation 来源；T-17 确认 `FamilyRepository.addGatewayToFamily` 的事务/权限语义与 C-08 用例一致，否则补 C-08 用例方法。保持登记，不计入本轮阻断 |

### 2.1 F-01 阻断项展开：连续控制取消后的晚到结果

```text
探针（真实 DeviceViewModel + FakeTimer/FakeControlCoordinator）:
  beginContinuous(key, SET_BRIGHTNESS, 0, 100)
  updateContinuous(key, 80)
  timer.advance(55)                 -> dispatch 发出，控制为 PENDING（在途中）
  cancelContinuous(key)             -> IDLE, optimisticValue=undefined
  release in-flight dispatch (成功) -> 控制变回 PENDING, optimisticValue=80, confirmedValue=undefined
```

- 根因：`beginContinuous` 把闭包 `(value) => this.dispatchContinuous(value, token)` 传给 gate，但 `dispatchContinuous(value, token)` 从头到尾没有读取 `token`；`cancelContinuous` 只 `gate.dispose()` + 把控制态置 IDLE，没有使旧 dispatch 的副作用失效。`endContinuous` 在 `await gate.onCommit` 之后也没有校验会话是否已被取消/替换，且会重新 `nextToken`，可能把并发的其他 action 结果判为 stale。
- 契约：`cancelContinuous` 必须“取消 timer、丢弃 pending、不发送、UI 回弹到 confirmed”；`cancel`/dispose 只允许底层请求继续，**结果不得写 state**（VM 用 operation token/revision 丢弃）。当前把“取消 UI”与“忽略结果”混在一起，只做了前者。
- 影响：用户拖动后取消/松手前取消，UI 可能永久停在 PENDING 并显示已取消的值；下一次操作会以该污染状态为起点；对 `COMMITTED` 的判断没有直接伪造成功，但三态状态机已被破坏，属于阻断级。
- 修复要点：为每次 `beginContinuous` 建立 gate 会话 id/generation；`dispatchContinuous` 在入口和 `await control.execute` 返回后都检查 `this.gate===gate && token===this.gateToken`；`cancelContinuous`/`endContinuous` 递增 token；`endContinuous` 仅在 token 仍当前时发布 COMMITTED/REVERT。`ClimateViewModel.dispatchTemperature` 同样加 generation 检查。回归测试在 resolve 前 cancel、在 cancel 后 resolve、cancel 与 end 并发三种时序。

### 2.2 F-02 阻断项展开：门锁“控制成功 ≠ 门状态确认”

```text
探针 A（unlock）:
  execution = {ackAccepted:true, stateVerification:'UNVERIFIED', apply.record.openStatus:undefined}
  unlock() -> DoorStage.OPEN / DoorLockState.OPEN / ControlPhase.COMMITTED
  期望：不得显示“已打开”；应为“已执行，状态未回传”并保留上一确认锁态

探针 B（lock + reported open=true）:
  execution = {ackAccepted:true, stateVerification:'MATCH', apply.record.openStatus:true}
  lock() -> tracker: DoorStage.FAILED / DoorLockState.OPEN
            VM:     ControlPhase.COMMITTED
  期望：FAILED + REVERT（DES-B §10.1.7），不得显示控制成功
```

- 根因：`DoorViewModel.applyLock` 用 `DeviceControlCoordinator.succeeded(execution)`（控制层 ACK 语义）判断成功，然后在 CLOSE 分支调用 `tracker.onResult`、在 OPEN 分支无条件 `tracker.markUnlocked()`；它没有读取 tracker 的门状态结论，也没有把 `unlock` 的 reported `open==true` 作为确认条件。`markUnlocked()` 本身也不校验任何 reported state。
- 契约：CLOSE 必须 `ackAccepted && reported open==false` 才进入 GATEWAY_CONFIRMED，否则 FAILED + REVERT；unlock 必须 `open==true` 才 OPEN；未见门磁确认只能“已执行/未确认到位”，`door.state.secured` 只在 SECURED 使用。当前 (a) 把 UNVERIFIED 的 unlock 写成 OPEN，(b) 把 open==true 的 CLOSE 控制写成 COMMITTED，均违反 SC-14 的“不得虚构成功”。
- 影响：门锁是安全相关 UI。虽然 (a) 不是伪造 SECURED，但它伪造了“已打开”的确认状态；(b) 在门实际未锁时给用户控制成功反馈。两者都会误导用户对门状态的判断，且现有 4 条 DoorVM 测试只覆盖了正例和 ACK 拒绝，未覆盖这两个输入。
- 修复要点：`applyLock` 先执行命令，再根据 `tracker` 的门结果决定 ControlUiState：CLOSE 的 tracker stage 为 FAILED 或 reported open==true → REVERT；unlock 仅在 `reportedOpen(execution)===true` 时 markUnlocked，否则保持上一确认锁态并发布 UNVERIFIED/UNCONFIRMED（不进入 OPEN）。补探针 A/B 的回归测试；必要时把 `DoorConfirmationTracker.onResult` 的返回结果暴露给 VM，而不是只读内部状态。

### 2.3 F-03 / F-04 展开

- **F-03**：`back()` 的 STEP_1 分支只 `publish(...STEP_0...)`；`startScan()` 在 `await ble.startScan` 之后设置的 10s 定时器仍在。探针输出 `after back step=0, bleStopCalls=0, timerPending=1`，10s 后 `step=1, error=PROVISIONING_DEVICE_NOT_FOUND`。这与“STEP_0/1 可自由后退”和“任何 cancel/back 清理”直接冲突；修复只需在后退路径 `clearScanTimer()` + `stopScan()` 并保留 STEP_0/IDLE，无需改 C-19。
- **F-04**：`testCloudConnection` 在 invalid 时只把错误写入 `error`；`CloudService.testConnection` 已按 T-14 F-03 的裁定把 401/403 记录为瞬时 token 状态并 `notify()`，但 Settings VM 没有订阅、也没有在失败分支重新 `loadCloud()`，所以 `state.cloud.state` 仍是旧值。修复可二选一：失败后 `await this.loadCloud()` 并发布，或订阅 `CloudService.subscribe` 把状态同步到 state（注意 dispose 取消订阅）。

### 2.4 U-01 上游编译阻塞展开

- 记录准确性：实现报告 §5 明确写出 `GatewayDiscoveryService.ets:331/344`、`arkts-no-structural-typing`、`Promise.then/catch` 回调参数、T-17 前必须由 C-18 owner 修复；本评审确认行号与代码内容一致（`withProbeTimeout` 的 `promise.then(...).catch(...)`）。
- 隔离有效性：Home/Settings 使用 `ViewModelPorts.ManualDiscoveryPort`，C-18 未进入 `assembleHap`/ohosTest 编译图；ohosTest 骨架只 import VM，因此当前构建通过不能证明 C-18 可用。
- 独立复现：在 `/tmp/opencode/yaocore-c18-probe` 副本的 `ViewModelsDevice.test.ets` 中临时加入 `import { GatewayDiscoveryService } ...` 与一个 `expect(...)`，执行同一条 ohosTest assemble 命令，exit 255，两个 ArkTS 错误分别位于 `:331:18` 和 `:344:18`；原仓库未改动。
- 结论：U-01 是 **T-17 的装配前置阻断**，不是 T-15/T-16 本轮可修的代码缺陷；但 CQG-T15/T16 与 T-17 的任务单必须携带该跟踪项，且 T-17 不得把“当前构建通过”当作 C-18 可 import。修复后必须重新执行带 import 的 ohosTest 编译证据。

---

## 3. 契约逐项核对（评审重点 1–10）

| # | 评审重点 | 结论 | 说明 |
|---|---|---|---|
| 1 | 三态控制：COMMITTED 仅 `ackAccepted + verification!=MISMATCH`；PENDING/REVERT 3s 回弹；禁止乐观成功；replay 不重复应用 | **部分符合** | Device/Climate 的成功/失败/MISMATCH/3s 超时路径与测试正确；`ControlExecution` 的 `stateVerification` 与 `lastExecution` 暴露给 UI；replay 由 C-10/C-17 现有层处理，VM 不重复应用。**F-01** 破坏 cancel/在途结果丢弃；门锁的 F-02 是安全相关例外 |
| 2 | 55ms 节流/TouchUp：合并、1 在途、latest 不丢、最终值强同步；单测有效 | **部分符合** | `ThrottleGate` 的核心状态机、55ms、1 在途、TouchUp、cancel、dispatch 失败 5 条测试均有效；但 VM 层 cancel 的晚到结果未被忽略（F-01），且缺 onCommit-before-55/cancel-with-waiter 测试（F-08） |
| 3 | 门锁四阶段：10s/门磁到位/在线离线；无门磁如实“未验证到位” | **部分符合** | GATEWAY_MERGED、CONTACT_SENSOR 到位/10s 在线 UNCONFIRMED/离线 UNKNOWN/NONE→UNVERIFIED、open 报警、dismiss 均与 §10.1.7 一致；**F-02** 的 unlock/CLOSE 控制态与门态耦合错误；**F-05** GATEWAY_CONFIRMED 不可观察 |
| 4 | LAN→云回退边界：仅网络类错误；安全/设备错误不回退；单网关 v1 | **符合** | `DeviceControlCoordinator` 仅对 `GATEWAY_UNREACHABLE/GATEWAY_TIMEOUT/LOCAL_REQUEST_FAILED` 且云 `CONFIGURED` 回退；`DEVICE_OFFLINE/TLS_*/TOKEN_*` 不回退；云 `UNSUPPORTED` 不 apply/不成功；7 条测试覆盖。F-06 单网关联云限制在 Settings 侧实现并有测试 |
| 5 | RBAC/F-08：GUEST 控制矩阵/`RBAC_DENIED`；房间删除保护/未分配池 | **符合（VM 层）** | `FamilyCapabilities` 由 C-12 派生，GUEST `canExecuteScene=false`、`allowedRoomIds` 暴露；F-08 由 C-12 fail-closed；房间删除走 C-09 预览+计数确认，设备进未分配/禁用池；VM 不绕过服务校验。F-06 的 join COMPLETED 冲突是独立的上游语义问题 |
| 6 | 配网 VM：6 步状态机/取消清理/`result.credentialDraftId`（R-1） | **部分符合** | 6 步映射、权限 DENIED/BLUETOOTH_OFF、扫描去重/10s、取消 `ble.cancel`+销毁草稿+清空 Wi-Fi/PoP、C-19 失败双草稿清理、R-1 `commitBinding(result, result.credentialDraftId, familyId)` 与测试均正确；**F-03** back 未清理扫描/定时器 |
| 7 | 错误→i18n：经 `ErrorI18nMapper`，无硬编码；键存在性 | **部分符合** | 所有 ViewModel 只保存 `i18nKey`，`translate*` 才调用 `t()`；没有新增 UI 硬编码；CHK-01..09 通过。**U-02** `settings.cloud.single_gateway_required` 尚未落地（报告已登记 T-18）；`brand.*` 为 T-14 F-05 上游；其余 VM 引用键（door/errors/provisioning/invite/gateway.security/scene）均存在 |
| 8 | 上游编译阻塞：如实记录/隔离；不得在 T-17 爆雷 | **记录与隔离符合；T-17 仍阻断** | U-01 描述准确且当前构建通过是隔离结果；独立探针复现两个 ArkTS 错误。T-17 前必须修复 C-18，不得直接 import 该类 |
| 9 | 测试质量：88 新用例有效/负例；设备骨架诚实（BLOCKED） | **部分符合** | 88 条真实执行，主路径/错误映射/门锁时序/回退矩阵/房间池/R-1 均有价值；但缺 F-01..F-04 的负例/并发用例，PASS 不能覆盖这些语义。设备骨架 `BLOCKED_ON_DEVICE_RUNNER` 诚实，未写 PASS |
| 10 | 过程：38 路径、证据一致、无秘密/构建产物 | **符合** | 38 路径与 commit 一致；5 个证据日志与独立复跑一致；`git status` clean；未发现 `.hap/build/oh_modules/密钥` 进入本次提交；实现报告 §5 的偏离/延期项（端口最小化、C-08 方法缺口、pinMatched、资源键、C-18）均有记录 |

---

## 4. 残余风险与跟踪

| 跟踪项 | 风险/内容 | 归属/时机 |
|---|---|---|
| **U-01 C-18 编译阻塞** | `GatewayDiscoveryService.ets:331/344` 的 `arkts-no-structural-typing`；T-17 直接 import 会构建失败 | C-18 owner 修复；T-17 前置；修复后补“import 该类的 ohosTest 编译”证据 |
| **F-01/F-02 修复后的回归** | 连续控制 cancel/end 并发、门锁 unlock/CLOSE 的 reported state 分支 | implementation-engineer 修复 + test-engineer/implementer 补测；重新 host/assemble + quality-reviewer 复审 |
| **F-03/F-04 修复** | BLE back 清理、Settings token 状态刷新 | 同一修复轮；T-18 页面联调时复核 |
| **U-02 资源键** | `settings.cloud.single_gateway_required` 缺失；`brand.*` 缺失（T-14 F-05） | T-18 资源任务；CQG/Stage Gate 记录 |
| **F-06 join 状态定义冲突** | C-08 COMPLETED（无 profile） vs C-22 COMPLETED（profile+active family） | `solution-architect` 裁定；T-17/T-18 前更新 DES-B 与测试 |
| **C-08 `addGatewayToFamily` 缺口** | VM 使用 `FamilyRepository.addGatewayToFamily` 而非 `FamilyService`；事务/权限语义需确认 | T-17/C-08 owner；保留 `U-03` 跟踪 |
| **pinMatched/rotationRecommended** | discovery 候选无 matched pin；rotation 无来源；VM 诚实留空/false | C-18/C-27/C-08；不要写成已实现 |
| **真实设备/真实 BLE/LAN/云** | 设备骨架仅编译；真实三态视觉、10s 门磁、BLE 全流程、云影子、p95 均 `UNAVAILABLE`/`BLOCKED` | T-19 设备矩阵、T-20 安全评审；本报告不授予 PASS |
| **TEST-001 状态** | C-21..C-23、SEC-N09/N11/N12/N14/N20/N23 等仍为 `NOT_RUN` | CQG 后由 test-engineer/Orchestrator 更新；不得把本报告当全量测试 PASS |
| **家庭/成员/场景服务层** | C-08/C-09/C-11 的 RBAC、删除保护、场景单飞是上游证据；本评审只验证 VM 透传/组合，未重审服务层 | 上游 STABLE 证据引用；T-17 集成时复验契约 |

---

## 5. Verdict 与后续

### 5.1 Verdict

**CHANGES_REQUIRED（代码级）**。

- C-21/C-22/C-23 保持 `UNVERIFIED`，不得进入 `STABLE`；CQG-T15/CQG-T16 不得记为 PASS。
- **必须先修复 F-01、F-02**；F-03、F-04 应在同一修复轮关闭，或由 Orchestrator 书面接受为 CQG 前跟踪项（不建议延后，二者都是用户可见契约缺口）。
- F-05/F-06/F-07/F-08 与 U-02/U-03 进入 CQG/Stage Gate 跟踪；F-06 需 architect 裁定。
- U-01 是 T-17 的装配前置阻断；T-15/T-16 的隔离不能作为 C-18 可用的证据。
- 本报告不是 Stage Gate、不是用户验收、不授予任何 `STABLE`。

### 5.2 修复后的最低复验

1. F-01/F-02/F-03/F-04 的回归测试（含探针中给出的时序/输入）必须新增并通过；同时补 F-08 列出的负例。
2. `entry/src/test/run-host-tests.sh`（预期 ≥ 593/593，新增用例全过）；`codelinter`；`hvigorw clean assembleHap`；ohosTest assemble。
3. U-01 修复后，在 ohosTest 骨架中保留/新增 `GatewayDiscoveryService` import，重新执行 ohosTest assemble；不得只跑未引用构建。
4. 重新执行 `quality-reviewer` 评审（至少复审 F-01/F-02 的修复与新增测试），再进入 CQG-T15/T16。

### 5.3 独立声明

本报告由未参与 T-15/T-16 实现、测试或实现报告编写的 `quality-reviewer` 独立作出。评审期间未修改任何被审产品代码、测试、证据或实现报告；唯一仓库写入为本报告。行为探针和 C-18 编译探针在 `/tmp/opencode` 的临时脚本/只读副本中执行；原仓库 `git status` 保持 clean，HEAD 仍为 `ffadebf`。本报告的 PASS/FAIL 权限仅针对 `ffadebf` 这一被审 revision，不延伸到修复后的 revision 或任何后续 Stage。

---

*评审结束。*
