# T-18 R3-02 修复报告（C-23 取消代际，晚到成功不得提交绑定）

- **Artifact ID**: T18-FIX3-REPORT
- **Producer**: agent:implementation-engineer
- **Task**: `wp-080-fix-t18c`（Handoff `state/handoffs/wp-080-fix-t18c.json`）
- **Branch**: `task/wp-073-ui-pages`（base `78eaca9`，parent `feat/yaocore-app`）
- **Inputs**: `artifacts/70-review/t18-review-c.md`、`artifacts/50-implementation/t18-fix2-report.md`、`artifacts/40-detailed-design/des-001b-domain-presentation.md`、`entry/src/test/run-host-tests.sh`（SHA-256 与 handoff 冻结值一致）
- **Status**: **COMPLETE（代码/构建/主机测试/i18n 检查完成；待独立复审）**
- **Date**: 2026-10-18
- **Workflow**: STANDARD / GATED_AUTO

> **结论先行**：R3-02（Medium，取消与 `submit`/`commitResult` 竞态）已在 C-23 VM 层修复。`BleProvisioningViewModel` 新增取消代际 `cancelGeneration`；`cancel()` 在第一个 await 之前同步递增代际，`prepareWifi`/`submit`/`commitResult` 及全部 BLE listener 回调按代际丢弃晚到结果。取消后晚到的 AP 列表、`BOUND` 进度、`onCompleted` 成功与 `provision` 成功均不再发布、不再进入 `commitBinding`/`addGatewayToFamily`，状态保持 `CANCELLED`，晚到结果草稿被立即零化。新增 4 条 host 负例（690→**694**），既有 690 条全部保留。五项必跑命令全部通过：`ohpm install`、`clean assembleHap` BUILD SUCCESSFUL、codelinter 0 error、host **694/694**、i18n blocking=0/missing=0。未改 DES-B、页面层与资源。设备/真实 BLE 仍 **BLOCKED**。

---

## 1. R3-02 处置

| 项 | 结论 |
|---|---|
| 严重度 | Medium（复审 `t18-review-c.md` §6 R3-02） |
| 状态 | **Fixed（代码级）**；待独立复审关闭 |
| 缺陷 | `cancel()` 只递增 `scanGeneration`，VM 无取消标志/代际；`prepareWifi`/`submit` 仅在 await 后检查 `disposed`。晚到的 `provision` 成功仍会进入 `commitResult` → `commitBinding` → `addGatewayToFamily` → `BOUND`；页面 `cancelled` 只遮挡 UI，不能撤销绑定 |
| 修复 | VM 级 `cancelGeneration`：`cancel()`/`dispose()` 同步递增；每个异步步骤在 await 之后校验捕获代际；listener 携带所属代际，晚到事件被丢弃；晚到结果草稿立即销毁 |
| 语义依据 | DES-B §12.1.1（“取消：`cancel()` 与 `prepareWifi`/`submit` 的竞态由 `cancelled`/扫描代际保护；晚到结果不得覆盖取消界面”）——按现有冻结文本实现，未修改设计 |
| 不改变 | R2-02“取消随时可用”（页面按钮与 `cancel()` 入口未动）；`cancel()` 的既有清理（定时器、扫描、BLE、draft、秘密输入）；错误码与状态枚举；页面层 `cancelled` 遮挡保留并与 VM 保护并存 |

---

## 2. 取消代际设计

### 2.1 单一事实来源

`entry/src/main/ets/viewmodel/BleProvisioningViewModel.ets` 新增：

```ts
private cancelGeneration: number = 0;

private isStale(generation?: number): boolean {
  return this.disposed ||
    (generation !== undefined && generation !== this.cancelGeneration);
}
```

- `cancel()` 与 `dispose()` 在**第一个 `await` 之前**同步执行 `this.cancelGeneration++`。因此只要取消调用已发生，任何从 await 恢复的旧操作都会观察到代际不一致。
- `cancel()` 同时保留 `scanGeneration++`、`clearScanTimer()`、`ble.cancel()`、`destroyDrafts()` 与 `CANCELLED` 发布；重复取消只再次递增代际并重新发布同一终态，不抛错、不恢复成功态。
- `dispose()` 也递增取消代际，保证页面销毁后的晚到结果不会发布或提交。

### 2.2 每个异步步骤的校验点

| 方法 | await 之后/提交前的校验 |
|---|---|
| `prepareWifi` | `crypto`（无）→ `publish(CONNECTING)` 后检查；`await scanWifiAccessPoints` 后检查，晚到 AP 列表直接丢弃，不再发布 `STEP_3/AP_SCANNING`；catch 仅在代际当前时 `handleProvisionFailure` |
| `submit` | `await crypto.randomBytes` 后检查（不在取消后创建 request draft）；`publish(CONNECTING)` 后检查；`await provision` 后检查，晚到成功调用 `destroyResultDraft` 并 **return**，不进入 `commitResult` |
| `commitResult` | 入口检查；`await commitBinding` 后检查（跳过 `addGatewayToFamily` 与 `BOUND`）；`await addGatewayToFamily` 后检查（不发布 `BOUND`） |
| `requestPermission`/`startScan` | 权限 await 后检查取消代际；扫描 listener 携带 `scanToken`，`onScanDevice`/`onScanFinished`/`onScanError` 丢弃过期扫描事件 |

### 2.3 Listener 代际

`WizardProgressListener` 新增 `generation`（`prepareWifi`/`submit` 启动时捕获），`onStateChanged`/`onAccessPoints`/`onError`/`onCompleted` 透传给 VM；VM 在发布前调用 `isStale(generation)`：

- 取消后 BLE 服务残留的 `BOUND`、`WAITING_FOR_WIFI`、AP 列表、`onError` 均被丢弃，不能覆盖 `CANCELLED` 快照。
- 晚到 `onCompleted` 的 `credentialDraftId` 立即 `drafts.destroy()`，不会留下未提交的会话秘密。
- `WizardScanListener` 新增 `scanToken`，`dispose()`/`cancel()`/`stopScan()`/`back()` 递增的扫描代际使旧扫描事件失效。
- 为保持既有 host 测试直接调用 `onProvisionState(progress)` 的形状，公开回调的 `generation` 参数可选；生产路径（Wizard listener）始终传入。直接调用不带代际时沿用原有行为，不作为安全边界。

### 2.4 不可回滚边界（如实记录）

若取消恰好发生在 `await commitBinding` **已经发起之后**，durable route 提交可能已在仓储层完成，VM 无法回滚；修复保证之后**不再**调用 `addGatewayToFamily`、不发布 `BOUND`、不把 `result` 写入视图状态，取消界面保持。取消可阻止的是“晚到成功进入绑定流程”，不是在提交已越过持久化边界后撤销已提交路由。该边界与 DES-B §12.1.1 的“晚到结果不得覆盖取消界面”一致，并已由 `T18_R3_cancelDuringCommitBindingSkipsFamilyAddAndBound` 覆盖。新绑定测试（provision 挂起时取消）证明 `commitBinding`/`addGatewayToFamily` 零调用。

---

## 3. 新增测试（690 → 694）

| 文件 | 新增用例 | 覆盖 |
|---|---|---|
| `entry/src/test/host/ViewModelBle.test.mjs` | `T18_R3_cancelDuringPrepareWifiDropsLateAccessPoints` | AP 扫描挂起时取消 → 晚到 `onAccessPoints`/`AP_SCANNING` 不发布；晚到 AP 列表 resolve 被丢弃；状态 `CANCELLED`、`step=2`、`accessPoints` 为空、`revision` 不变、定时器 0 |
| `entry/src/test/host/ViewModelBle.test.mjs` | `T18_R3_cancelDuringSubmitDropsLateBindingSuccess` | `provision` 挂起时取消 → 晚到 `BOUND`/`onCompleted`/成功 result 被丢弃；`commitBinding` **0 调用**、`addGatewayToFamily` **0 调用**、无 `BOUND` 发布、`result === undefined`、晚到结果草稿被销毁 |
| `entry/src/test/host/ViewModelBle.test.mjs` | `T18_R3_cancelDuringCommitBindingSkipsFamilyAddAndBound` | `commitBinding` 挂起时取消 → await 返回后跳过 `addGatewayToFamily`、不发布 `BOUND`、状态保持 `CANCELLED` |
| `entry/src/test/host/ViewModelBle.test.mjs` | `T18_R3_repeatedCancelIsIdempotentAndDropsLateSuccess` | 并发重复取消 → 状态稳定为 `CANCELLED`、`canCancel=false`；随后晚到成功仍不绑定 |

- 测试 fake：新增 `DeferredBle`/`DeferredWifiBle`（`cancel()` 不 reject 挂起 Promise，模拟“取消后仍晚到成功”）与 `DeferredBindings`（挂起 `commitBinding`）；未修改既有 fake 行为。
- 既有 690 条用例未删除、未弱化：总数 **694**，pass 694 / fail 0 / skipped 0。
- 未新增 i18n 键；未改资源目录。

---

## 4. 验证（实际执行，cwd = 仓库根）

| # | 命令 | 结果 |
|---|---|---|
| 1 | `ohpm install` | exit 0；`install completed in 0s 47ms` |
| 2 | `hvigorw clean assembleHap --no-daemon` | exit 0；**BUILD SUCCESSFUL in 14 s 595 ms**；0 ERROR（既有 ArkTS/SDK 警告不变） |
| 3 | `codelinter -c code-linter.json5 -p default .` | exit 0；**Defects 25 / Errors 0 / Warns 25 / Suggestions 0**（与修复前同量级） |
| 4 | `entry/src/test/run-host-tests.sh` | exit 0；**tests 694 / pass 694 / fail 0 / skipped 0**（新增 4，既有 690 保留） |
| 5 | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | exit 0；**blockingFailures=0 / missingKeys=0**；warnings=139；hardcoded=82（与修复前一致） |

补充核对：

- 变更仅限允许写范围：`entry/src/main/ets/viewmodel/BleProvisioningViewModel.ets`、`entry/src/test/host/ViewModelBle.test.mjs`、本报告。
- 未修改 DES-B/DES-A、页面 `ProvisioningPage.ets`、资源、`ohosTest/`、`module.json5`、`AppScope/`、repository/service 实现。
- 未切换分支、未 pull/merge/rebase/push；无秘密、构建产物或无关文件入库。
- 取消后 VM 清理保持：扫描代际、10s 定时器、BLE cancel、本 session drafts、秘密输入（页面层 `clearSecrets` 未改）；页面 `cancelled` 遮挡仍保留，VM 保护不依赖 UI 遮挡。

---

## 5. 变更文件

- `entry/src/main/ets/viewmodel/BleProvisioningViewModel.ets`（R3-02：取消代际、await 后校验、listener 代际、晚到结果草稿零化）
- `entry/src/test/host/ViewModelBle.test.mjs`（4 条 R3-02 host 负例 + deferred fakes）
- `artifacts/50-implementation/t18-fix3-report.md`（本报告）

---

## 6. 偏离、假设与残余风险

1. **无设计偏离**：DES-B §12.1.1 文本未改；实现的是其已声明的“cancelled/扫描代际保护；晚到结果不得覆盖取消界面”。未改变 R2-02 取消入口、状态枚举、错误码、公开方法签名（`prepareWifi`/`submit`/`cancel` 形状不变）。
2. **commitBinding 已发起后的边界**：见 §2.4。取消发生在 durable commit 已发起之后时无法回滚该路由；修复保证不继续 `addGatewayToFamily`、不发布 `BOUND`、不呈现成功。
3. **公开回调的可选代际参数**：`onProvisionState`/`onAccessPoints`/`onProvisionError`/`onCompleted` 的代际参数可选，以保持既有 host 测试直接调用形状；生产 listener 始终携带代际。VM 外的调用方若直接调用这些回调，不享受取消保护（非页面/生产路径）。
4. **验证边界**：host 测试使用 fake BLE/仓储，证明 VM 逻辑与调用序列；真实 BLE 驱动在取消后是否仍返回成功、设备/权限弹窗/AP 扫描/LAN/绑定探针仍 **BLOCKED**，归 T-19 设备矩阵。
5. **GAP-T18-01**（`addGatewayToFamily` 无服务层 actor/RBAC）与 R3-01/T-20 未在本次范围，未关闭、未弱化。

---

## 7. 约束核对

- 写范围：仅 `entry/src/main/ets/viewmodel/`、`entry/src/test/`、`artifacts/50-implementation/`。
- 未修改 `entry/src/main/ets/pages/**`、`components/**`、`service/**`、`repository/**`、资源、契约/计划/评审报告。
- 既有 690 条 host 用例全部保留并通过（总 694）。
- 未新增用户可见文案，未触发 i18n 门禁变化。
