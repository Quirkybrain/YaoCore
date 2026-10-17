# T-15 / T-16 收窄修复聚焦复审报告（C-21 / C-22 / C-23）

- **Artifact ID**: REVIEW-T15-T16-C
- **Producer**: agent:quality-reviewer
- **Type**: Independent Code Review / Focused Re-review
- **Status**: **PASS（组件级评审意见；R2-01 / R2-02 已关闭）**
- **Date**: 2026-10-18
- **Task**: `wp-066-review-vm2`（task 分支 `task/wp-060-vm`，父分支 `feat/yaocore-app`，base `3dd0639`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`（CQG-T15 / CQG-T16 前）
- **Reviewed revision**: `3dd06394fbaa84c7fb0227faa0fd3ce0be0ea662`（HEAD；父 `59c27b1`；本修复提交 `3dd0639`）
- **Previous review**: `artifacts/70-review/t15-16-review-b.md`（CHANGES_REQUIRED；revision `e77b192`）
- **Review snapshot**: `refs/swe/snapshots/20261017T162912Z-wp-066-review-vm2-7dd312e3`
- **Independence**: 本报告由未参与 T-15/T-16 实现、测试、实现报告或修复报告编写的 `quality-reviewer` 执行。评审期间未修改任何被审产品代码、测试、证据或实现/修复报告；唯一仓库写入为本报告。独立探针在 `/tmp/opencode/` 的临时脚本中加载真实 `DoorViewModel`、`DeviceViewModel`、`ControlPolicy` 与真实测试 fixture，在内存中执行，未在仓库落盘或提交。复验前后工作区保持 clean，HEAD 为 `3dd0639`。

> 结论先行：R2-01（High，门锁 `CLOSE` 命令值）与 R2-02（Medium，跨设备连续控制隔离）均已按评审建议修复，并通过独立探针复验。`entry/src/test/run-host-tests.sh` 独立复跑 **613/613 PASS**，既有 610 条用例全部保留；`codelinter`、`hvigorw clean assembleHap`、ohosTest（含 C-18 编译探针）与 i18n 检查均通过。未发现新的 High/Medium 代码缺陷。**CQG-T15 / CQG-T16 的组件级评审意见为 PASS（scoped to `3dd0639`）**；F-05、U-02、U-03、真实设备/真实网络等残余项继续跟踪，设备执行仍为 `BLOCKED`，不计入本轮 PASS 证据。本报告不是 Stage Gate，不是用户验收，不授予任何 `STABLE`。

---

## 1. 复审范围、revision 与输入完整性

### 1.1 范围

```text
entry/src/main/ets/viewmodel/                 # DeviceViewModel / DoorViewModel 及 core/**（本轮实际修改 2 个文件）
entry/src/test/                               # host 测试、helper、验证证据日志
artifacts/50-implementation/t15-16-fix2-report.md
```

- 被审修复提交 `3dd0639` 共 **10 个路径**：2 个 ViewModel 产品文件、2 个 host 测试文件、5 个验证证据日志、1 个修复报告。与 `t15-16-fix2-report.md` §6 的变更清单一致。
- 交叉读取但未修改：上轮复审 `t15-16-review-b.md`、DES-B §10.1.3/§10.1.7/§10.3.1/§10.3.2/§10.3.3、`contract-baseline.md`、`test-plan.md`、`GatewayRequestPolicy`/`DeviceCommandRunner`/`LocalGatewayService` 的生产预检路径、`ThrottleGate`/`DoorConfirmationTracker`。
- 明确排除：真实设备/模拟器、真实 BLE/LAN/云、UI 三态视觉与动画、NFR 4.3 p95、T-17/T-18 页面与资源落地、T-19 全量执行、T-20 安全评审、用户验收与完整 Stage Gate。上述项保持 `BLOCKED` / `COMPILED_ONLY` / `UNAVAILABLE`，本报告不将其写成 PASS。

### 1.2 输入 pin 与快照

handoff 的 5 个 `inputs` SHA-256 **5/5 一致**；`config/git-policy.json` 的 SHA-256（`3b8ddffd4494…`）与 handoff 一致。快照 `refs/swe/snapshots/20261017T162912Z-wp-066-review-vm2-7dd312e3` 对 `entry/src/main/ets/viewmodel/`、`entry/src/test/`、`artifacts/` 的覆盖经 `git diff <snapshot> HEAD` 复核为空；复验前后 `git status --short` clean，HEAD = `3dd0639`。

| 输入 | SHA-256 前 12 位 | 结果 |
|---|---|---|
| `artifacts/70-review/t15-16-review-b.md` | `769d4fca9e36` | 一致 |
| `artifacts/50-implementation/t15-16-fix2-report.md` | `5239da7145f9` | 一致 |
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | `42e6912806e3` | 一致 |
| `artifacts/20-architecture/contract-baseline.md` | `883e09bb34ea` | 一致 |
| `artifacts/60-testing/test-plan.md` | `33485cc39abd` | 一致 |
| `config/git-policy.json` | `3b8ddffd4494` | 一致 |

### 1.3 本评审实际复验（cwd = 仓库根，全部只读）

| 命令 | 结果 | 说明 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS：613 tests / 613 pass / 0 fail / 0 cancelled / 0 skipped / 0 todo，exit 0** | 与 `evidence/t15-16-fix2-host-node-tests.tap` 的 613/613 一致；既有 610 条全部保留，新增 3 条真实执行 |
| `codelinter -c code-linter.json5 -p default .` | **PASS：No defects found in your code，exit 0** | 与 `t15-16-fix2-codelinter.log` 一致 |
| `hvigorw clean assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0**（35 tasks） | 与 `t15-16-fix2-clean-assemble.log` 一致 |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0**（35 tasks） | ohosTest 仍 import `GatewayDiscoveryService`（C-18 编译探针），因此这是 **ArkTS 类型/编译证据**，不是设备执行证据 |
| `python3 entry/src/test/i18n/check_i18n.py --root . --strict-ui` | **PASS：blockingFailures=0，warnings=67，missingKeys=0，hardcoded=12，exit 0** | 新增 ViewModel 无硬编码 UI 文案；warnings 为既有 Index/AcAdapter/Mock 等（T-17/T-18 迁移项） |
| `git status --short` | **clean** | 构建仅产生 ignored 目录，未产生跟踪文件变化 |

**独立探针**（真实生产类 + 测试 fixture，非仓库落盘）：

- R2-01 探针 **3/3 PASS**：`CLOSE=false` accepted；`CLOSE=true` → `PROTOCOL_VALUE_OUT_OF_RANGE`；真实 `DoorViewModel.lock()` 经真实 `ControlPolicy` 发出 `CLOSE/false`，到达 `SECURED + COMMITTED`；`unlock()` 的 `OPEN/true` 仍可发出并到达 `OPEN`。
- R2-02 探针 **11/11 PASS**：跨设备 begin 双 `PENDING`；A/B 各自 dispatch 到正确 target/value 并独立 `COMMITTED`；cancel B 不影响 A；A 在途时 B 可同时在途；A 失败 `REVERT` 与 B 成功 `COMMITTED` 隔离；同 key 切换 action 丢弃旧结果；cancel/new-begin 的晚到结果被丢弃；end 后 session 清理且后续 update 为 no-op；dispose 丢弃全部在途结果。
- 额外探针 **4/4 PASS**：同时跨设备在途、跨设备失败隔离、同设备 action 切换、end 清理。另确认既有 `cancel → end` fallback 行为（见 §4 R3-02）。

---

## 2. R2 关闭状态

### 2.1 R2-01（High）：`DoorViewModel.lock()` 的 CLOSE 命令值

| 项 | 复核结果 |
|---|---|
| 修复位置 | `entry/src/main/ets/viewmodel/DoorViewModel.ets:130-134`：`lock()` 调用 `applyLock(DeviceAction.CLOSE, false)`；`unlock()` 保持 `OPEN/true`。 |
| 契约依据 | `GatewayRequestPolicy.ets:158-181`：布尔动作 `expected = action===TURN_ON \|\| action===OPEN \|\| action===BOARD_LED_ON`，即 `CLOSE` 必须为 `false`；`CLOSE=true` 抛 `PROTOCOL_VALUE_OUT_OF_RANGE`。生产 `DeviceCommandRunner.ets:84` 与 `LocalGatewayService.ets:198` 均调用该策略。 |
| 回归断言 | `ViewModelDoorVM.test.mjs:56-69` 增加 `calls[0].command.value === false`；`:72-95` 新增真实 `ControlPolicy` 包装用例：在委托 Fake 前执行生产同款 `ControlPolicy.validate(DeviceType.DOOR, true, command.action, command.value)`，并显式断言 `CLOSE=false` accepted、`CLOSE=true` 抛 `PROTOCOL_VALUE_OUT_OF_RANGE`。修复前该用例会在策略处失败（`calls.length=0`、`REVERT`），因此能真实捕获 R2-01。 |
| 独立探针 | 真实 `ControlPolicy`：`CLOSE=false` accepted、`CLOSE=true` rejected；真实 `DoorViewModel.lock()` 经策略包装后 `seen=[CLOSE/false]`，`door.stage=SECURED`、`lockState=SECURED`、`control.phase=COMMITTED`；`unlock()` 的 `OPEN/true` 同样通过策略并到达 `OPEN`。 |
| 结论 | **CLOSED**。R2-01 的“生产 lock 必然被策略拒绝”缺陷已消除；门锁状态语义（F-02）未被改写。 |

### 2.2 R2-02（Medium）：跨设备连续控制节流隔离

| 项 | 复核结果 |
|---|---|
| 修复位置 | `DeviceViewModel.ets:122-131` 新增 `sessions: Map<string, ContinuousSession>` 与 `gateGeneration`/`continuousActions`；`:216-243` `beginContinuous` 只取消同一 key 的旧会话并创建该 key 的 `ThrottleGate`；`:245-259` `updateContinuous` 读取该 key 的 action/min/max；`:261-296` `endContinuous` 仅在该 key 会话身份仍匹配时发布 `COMMITTED/REVERT`，随后删除会话；`:298-313` `cancelContinuous` 只 dispose/删除该 key；`:335-346` `dispose` 清理全部会话；`:399-443` `dispatchContinuous` 以 `(key, token)`/session 对象身份双重校验丢弃晚到结果。 |
| 契约依据 | DES-B §10.3.2：“不同设备各自独立节流；同设备不同 action 串行（一次只允许一个控制态；切换 action 前等待/取消）”。§10.1.3 连续控制接口按 `DeviceKey` 区分。 |
| 回归断言 | `ViewModelDevice.test.mjs:224-268`：A begin → B begin 后 A/B 均 `PENDING`；B begin 后 A 仍可 update 并 dispatch 到 `dev-a/60`；A `COMMITTED` 后 B 仍 `PENDING`；B 随后独立 `COMMITTED`。`:270-302`：cancel B 后 A 仍 `PENDING` 并可完成 `COMMITTED`，B 为 `IDLE`。两条用例在旧“单一全局 gate”实现下都会因 A 的 update 被 key 不匹配拦截而失败。 |
| 独立探针 | A/B 同时 `PENDING`；A 与 B 各自 dispatch 到正确 target/value；A end 后 B 保持 `PENDING` 并可独立完成；cancel B 不影响 A；**A/B 同时各有一条在途 dispatch**；A 失败 `REVERT` 与 B 成功 `COMMITTED` 互不污染；同 key 从亮度切换到温度时旧在途结果被丢弃、新 action 正常 `COMMITTED`；cancel/new-begin 的晚到结果均被丢弃；end 删除会话后 update 不再 dispatch。 |
| 结论 | **CLOSED**。per-key gate/session 与 DES-B §10.3.2 一致；F-01 的“同一 key/同一会话晚到结果丢弃”语义保留并扩展到跨设备隔离。 |

### 2.3 R2 验收矩阵（摘要）

| 场景 | 期望 | 实测 |
|---|---|---|
| A begin → B begin | A、B 均 `PENDING`，A 会话不被清除 | PASS |
| A/B 分别在途 | 两条命令各自 target/value，互不取代 | PASS |
| A end → B 仍在途/仍 PENDING | B 可继续 update/end 并独立提交 | PASS |
| cancel B → A 继续 | A 仍 `PENDING`，A 可完成 | PASS |
| A 失败、B 成功 | A `REVERT`，B `COMMITTED` | PASS |
| 同 key 新 begin / 切换 action | 旧在途结果丢弃，新会话正常 | PASS |
| cancel 后晚到成功 | 保持 `IDLE`，不写 `confirmedValue` | PASS |
| end 后 update | session 已删除，update no-op | PASS |
| dispose 后在途结果 | 两个 key 的结果均被丢弃 | PASS |
| lock / unlock 命令 | CLOSE/false、OPEN/true，均通过真实策略 | PASS |

---

## 3. 回归与不变量核对

### 3.1 测试数量与既有用例保留

- 父 revision `59c27b1`：`ViewModelDevice.test.mjs` 10 条、`ViewModelDoorVM.test.mjs` 8 条；当前 revision：12 条、9 条，合计 **613** 条（与 TAP 的 613/613 一致）。
- 新增 3 条：Door 真实策略集成 1 条（`ViewModelDoorVM.test.mjs:72-95`）、跨设备连续控制 2 条（`ViewModelDevice.test.mjs:224-268`、`:270-302`）。
- 既有 610 条全部保留；diff 中没有删除测试、没有 `skip`/`todo`/`only`，TAP 为 `fail 0 / cancelled 0 / skipped 0 / todo 0`。
- 新用例断言的是状态、调用次数、target/value、定时器与 `confirmedValue`，不是“仅错误码”或走过场；跨设备用例在旧实现下会因全局 `gateKey`/`gateAction` 行为失败，Door 策略用例在旧 `CLOSE=true` 下会因策略拒绝失败，因此具备真实回归价值。

### 3.2 F-01..F-08 + U-01 未回退

| 项 | 上轮状态 | 本轮复核 |
|---|---|---|
| F-01 连续控制 cancel/supersede 晚到结果 | CLOSED（同 key） | **未回退**：`cancelWhileDispatchInFlightDropsLateSuccess`、`newBeginInvalidatesAnOlderDispatchResult`、`cancelRacingEndCommitNeverPublishesCommitted` 均在 613 全量中通过；独立探针再次验证 cancel/new-begin/dispose 的晚到结果丢弃，且跨设备不再误伤。 |
| F-02 门锁 ACK ≠ 门状态确认 | CLOSED（状态/confirmedValue） | **未回退**：DoorVM 9 条用例全过；CLOSE/false 通过真实策略；`open=false`、`open=true`、无 reported、ACK 拒绝等状态语义未改。 |
| F-03 配网 back 清理 | CLOSED | **未回退**：`ViewModelBle.test.mjs` 相关用例在 613 全量中通过；本轮 diff 未触碰 Ble。 |
| F-04 Settings Token 过期刷新 | CLOSED | **未回退**：`ViewModelSettings.test.mjs` 在 613 全量中通过；本轮 diff 未触碰 Settings。 |
| F-06/F-07 Family 加入完成语义/部分失败重试 | CLOSED（按 `1e7487e`/§0.7） | **未回退**：`ViewModelFamily.test.mjs`、`DomainFamily.test.mjs` 在 613 全量中通过；本轮 diff 未触碰 Family/Invite。 |
| F-08 负例覆盖 | CLOSED（17 条） | **未回退并增强**：17 条既有负例保留，新增 3 条；无 skip/todo。 |
| U-01 C-18 编译阻断 | CLOSED（编译级） | **未回退**：`ViewModelsDevice.test.ets:34-54` 仍 import `GatewayDiscoveryService` 并断言 defined；本轮 ohosTest assemble `BUILD SUCCESSFUL`。 |
| F-05 `GATEWAY_CONFIRMED` 不可观察 | OPEN（跟踪） | **仍 OPEN**：grep 仅在枚举中发现 `DoorStage.GATEWAY_CONFIRMED`，tracker 仍直接从 PENDING 进入 SECURED/WAITING_CONTACT/UNVERIFIED；未在本轮范围。 |
| U-02 `single_gateway_required` 资源键 | DEFERRED（T-18） | **仍缺失**：资源文件中无该键，`SettingsViewModel.ets:40` 以常量引用，静态检查 missingKeys=0 未捕获；保持 T-18。 |
| U-03 `pinMatched`/`rotationRecommended`/`addGatewayToFamily` | DEFERRED（T-17/T-18） | **未由本轮处理**：仍按修复报告余项跟踪。 |

### 3.3 三态/节流主语义与不改变项

- **三态**：`PENDING` 仅 UI 反馈、`COMMITTED` 仅在 `ackAccepted && verification !== MISMATCH` 后、`REVERT` 保持到 `settleRevert`/320ms；`ThrottleGate` 的 55ms 合并、1 在途、latest 不丢、TouchUp 最终值、cancel、dispatch 失败路径均由 613 全量中的 Throttle/Device/Climate 套件覆盖并通过。本轮只把连续会话状态从全局改为 per-key，未改三态判定和 55ms 常量。
- **不改变项**：D-009（密码仅调用期存在）、D-010（接触式收敛）、D-013（TLS/安全路由）、D-022/D-023（邀请容器/回执账本）、R-1（`credentialDraftId`）、F-08 GUEST fail-closed 均未被本 diff 触碰或改写；`git show --name-status 3dd0639` 仅 2 个产品文件。
- **i18n**：新增代码仍只保存 `i18nKey`，`translate*` 才调用 `t()`；CHK-01..09 为 `blockingFailures=0`、`missingKeys=0`。U-02 常量键仍由 T-18 补齐。

---

## 4. 新发现（R3）

### R3-01（Low，测试完整性，非阻断）：跨设备回归目前是串行验证，未固定“同时两条在途/单侧失败隔离”

| 项 | 内容 |
|---|---|
| 位置 | `entry/src/test/host/ViewModelDevice.test.mjs:224-302`（两条新增跨设备用例） |
| 观察 | 两条用例都按“A dispatch 完成 → A end → B dispatch”顺序执行；`FakeControlCoordinator` 立即 resolve，因此没有真正构造“A、B 同时各有一条在途 dispatch”，也没有断言一条设备失败时另一条仍成功。 |
| 独立证据 | 本评审用 `DeferredControl` 探针验证：A/B 同时各有一条在途命令；A reject 后 `REVERT`、B resolve 后 `COMMITTED`，互不污染；同 key action 切换和 dispose 也通过。 |
| 影响 | 产品实现当前正确；但若未来重构把 gate 又合并回全局，现有串行用例未必能捕获并发/失败隔离回归。 |
| 建议 | 在 T-17/T-19 或下一次测试刷新时补两条 host 用例：跨设备同时 in-flight、跨设备单侧失败隔离。地址 `ViewModelDevice.test.mjs`，不需要新设计裁定。 |
| 阻断性 | **不阻断 CQG-T15/T16**；当前实现已由独立探针覆盖，且串行用例已能捕获原全局 gate 缺陷。 |

### R3-02（Info，既有行为，非本轮回归）：`cancel → end` 的 fallback 会发送一条单次命令

| 项 | 内容 |
|---|---|
| 位置 | `entry/src/main/ets/viewmodel/DeviceViewModel.ets:261-268`（无 session 时使用 `continuousActions` 或默认 `SET_TARGET_TEMPERATURE` 调用 `runSingle`） |
| 观察 | 独立探针：`beginContinuous(A)` → `cancelContinuous(A)` → `endContinuous(A,20)` 时，session 已被 cancel 删除，但 end 走 fallback，实际 dispatch 1 条 `SET_BRIGHTNESS/20` 并进入 `COMMITTED`。这是 per-key 改造前就存在的 fallback（旧实现使用全局 `gateAction`），不是 `3dd0639` 引入的回归。 |
| 影响 | 若 T-17 的 UI 在 pointer cancel/页面离开后仍触发 TouchUp，可能发送一条本应被 cancel 丢弃的最终值；命令仍经 C-17 策略校验，不属于安全虚构成功。DES-B §10.1.3 对 `cancelContinuous` 的“不发送”语义未明确覆盖“cancel 后再次 end”的调用顺序。 |
| 建议 | T-17 接线时保证 cancel 后不再调用 end；或在 VM 以 per-key `canceled` 标记把 cancel 后的 end 变为 no-op，并在 DES-B/测试中明确该顺序。作为既有 API 边缘，不要求在本轮 CQG 前修改。 |
| 阻断性 | **不阻断**；记录为后续 UI 接线/契约澄清项。 |

> 本轮未发现新的 High/Medium 代码缺陷。R3-01/R3-02 均为 Low/Info，且不改变 R2-01/R2-02 的关闭结论。

---

## 5. CQG-T15 / CQG-T16 对照

| CQG 项 | 结论 | 依据/限制 |
|---|---|---|
| 构建（clean assembleHap） | **PASS** | 独立复跑 BUILD SUCCESSFUL，exit 0，35 tasks |
| Lint（codelinter） | **PASS** | No defects found，exit 0 |
| Host 测试 | **PASS** | 613/613，0 fail/skip/todo；610 条既有用例全保留，3 条新增真实执行 |
| 契约（C-21/C-22/C-23） | **PASS（组件级）** | R2-01/R2-02 CLOSED；F-01..F-04、F-06..F-08、U-01 未回退；F-05 仍 OPEN（Low，跟踪） |
| 安全（VM 层，非 T-20 全量） | **PASS（VM 层）** | 门锁 CLOSE/false、OPEN/true 均通过真实策略；F-02 不把 UNVERIFIED/矛盾状态写成 OPEN/SECURED；未发现秘密/凭据进入 state 或日志；完整 T-20 安全评审仍待 |
| 分层/架构 | **PASS** | 仅修改 `viewmodel/` 两个文件与 host 测试；VM 不 import 平台 API；无协议/错误码/线格式变更；per-key 为 DES-B §10.3.2 的契约内实现 |
| i18n | **PASS（含 U-02 跟踪）** | CHK-01..09：blockingFailures=0、missingKeys=0、warnings=67；U-02 常量键仍由 T-18 补齐 |
| 独立评审 | **本报告** | 未参与实现/测试/报告；只读复审；不授予 STABLE/Stage Gate |
| 设备执行 | **BLOCKED** | 无设备/模拟器/签名；ohosTest 仅编译（含 C-18 import 探针），`BLOCKED_ON_DEVICE_RUNNER`；不计入本轮 PASS 证据 |
| **CQG-T15/T16 最终意见** | **PASS（组件级，scoped to `3dd0639`）** | R2 阻断项已关闭；构建/lint/host/契约/安全（VM 层）/分层/i18n/独立评审证据齐全；设备、真实网络与 F-05/U-02/U-03 作为残余跟踪 |

---

## 6. 残余风险与跟踪

| 跟踪项 | 风险/内容 | 归属/时机 |
|---|---|---|
| **F-05 `GATEWAY_CONFIRMED`** | 中间态仍不可观察；`DoorStage` 四阶段在可观察状态上只有三段 | T-17/T-18 或后续设计同步；不计入本轮 R2 关闭 |
| **U-02 资源键** | `settings.cloud.single_gateway_required` 在 zh-CN/en-US 仍缺失；常量键未被静态检查捕获 | T-18 资源任务；CQG/Stage Gate 记录 |
| **U-03 端口/字段缺口** | `pinMatched`/`rotationRecommended` 无完整来源；C-08 `addGatewayToFamily` 契约缺口 | C-18/C-27/C-08 owner；T-17/T-18 |
| **真实设备/真实 BLE/LAN/云** | ohosTest 仅编译；真实三态视觉、10s 门磁、BLE 全流程、云影子、p95 均未执行 | T-19 设备矩阵、T-20 安全评审；本报告不授予 PASS |
| **R3-01 跨设备并发测试缺口** | 现有新增用例串行；并发在途/失败隔离仅由独立探针覆盖 | test-engineer/implementation-engineer；T-17/T-19 前补 host 用例 |
| **R3-02 cancel→end fallback** | cancel 后再次 end 会发送单次命令；既有行为，非 `3dd0639` 引入 | T-17 UI 接线/契约澄清；当前不阻断 |
| **BLE back/restart 竞态** | `back()` 未 await `stopScan()`；连续 back→startScan 在真实适配器上可能互相干扰；in-flight back 可能重复 `stopScan` | T-17/T-19 真机复核；低风险观察 |
| **TEST-001 状态** | C-21..C-23、SEC-N09/N11/N12/N14/N20/N23 等仍为 `NOT_RUN` | CQG 后由 test-engineer/Orchestrator 更新；不得把本报告当全量测试 PASS |

---

## 7. Verdict、复验与独立声明

### 7.1 Verdict

**PASS（组件级评审意见，scoped to `3dd06394fbaa84c7fb0227faa0fd3ce0be0ea662`）**。

- R2-01：**CLOSED**。`lock()` 发送 `CLOSE/false`，真实 `ControlPolicy` 接受；`CLOSE/true` 被 `PROTOCOL_VALUE_OUT_OF_RANGE` 拒绝；DoorVM 策略集成用例与独立探针均复验。
- R2-02：**CLOSED**。per-key gate/session 隔离生效；跨设备 begin/update/end/cancel/dispose、并发在途、失败隔离、同 key 切换、F-01 晚到结果丢弃均复验。
- 回归：613/613、610 条既有用例全保留；F-01..F-04/F-06..F-08/U-01 未回退；三态/55ms 主语义未破坏。
- 构建/lint/host/契约/安全（VM 层）/分层/i18n/独立评审：**PASS**；设备执行：**BLOCKED**（不计入 PASS）。
- C-21/C-22/C-23 的组件级评审证据已满足；建议 Orchestrator 在 CQG-T15/T16 记录 `PASS（组件级）`，在正式 Gate 记录前不写 `STABLE`。本报告不是 Stage Gate、不是用户验收。

### 7.2 后续最低动作

1. Orchestrator 依据本报告与 613/613、build/lint/ohosTest 编译证据记录 CQG-T15/T16（组件级 PASS）。
2. T-17/T-19 前补 R3-01 的跨设备并发/失败隔离 host 用例；T-17 接线时明确 R3-02 的 cancel→end 顺序。
3. F-05、U-02、U-03、真实设备/真实网络按既有跟踪项消费；设备矩阵与 T-20 安全评审不得被本报告替代。

### 7.3 独立声明

本报告由未参与 T-15/T-16 实现、测试、实现报告或修复报告编写的 `quality-reviewer` 独立作出。评审期间未修改任何被审产品代码、测试、证据或实现/修复报告；唯一仓库写入为本报告。行为探针通过 `/tmp/opencode/` 临时脚本加载真实 `DoorViewModel`、`DeviceViewModel`、`ControlPolicy` 与仓库测试 fixture 执行，未在仓库落盘；复验前后工作区保持 clean，HEAD 为 `3dd0639`，快照覆盖经 `git diff` 复核为空。本报告的 PASS 结论仅针对 `3dd0639` 这一被审 revision 的组件级评审范围，不延伸到后续 revision、Stage Gate 或用户验收。

---

*聚焦复审结束。*
