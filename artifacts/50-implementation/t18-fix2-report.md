# T-18 复审 R2 修复报告（R2-01 / R2-02 / R2-04 / R2-05）

- **Artifact ID**: T18-FIX2-REPORT
- **Producer**: agent:implementation-engineer
- **Task**: `wp-077-fix-t18b`（Handoff `state/handoffs/wp-077-fix-t18b.json`）
- **Branch**: `task/wp-073-ui-pages`（base `8f3d969`，parent `feat/yaocore-app`）
- **Inputs**: `artifacts/70-review/t18-review-b.md`、`artifacts/50-implementation/t18-fix-report.md`、`artifacts/40-detailed-design/des-001b-domain-presentation.md`、`artifacts/60-testing/test-plan.md`（SHA-256 与 handoff 冻结值一致）
- **Status**: **COMPLETE（代码/构建/主机测试/i18n 检查完成；待独立复审）**
- **Date**: 2026-10-18
- **Workflow**: STANDARD / GATED_AUTO

> **结论先行**：复审 R2-01、R2-02、R2-04、R2-05 四项在允许写范围内修复；R2-06 的未用 import 已清理，其余 Info 项按记录处理。新增 5 条 host 测试（685→690），既有 685 条全部保留。五项必跑命令全部通过：host 690/690、codelinter 0 error/25 warn、clean assembleHap BUILD SUCCESSFUL、i18n blocking=0/missing=0。设备/视觉/真实 BLE 仍 **BLOCKED**。R2-03（契约登记）属 `solution-architect` 范围，本次未改 DES-A/DES-B，也未改 viewmodel（不在写范围），见 §5 偏离。

---

## 1. 逐条处置

| ID | 严重度 | 处置 | 实现与证据 |
|---|---|---|---|
| **R2-01** Settings P_BLOCKED“重新配网”缺 ADMIN 门 | Medium | **Fixed** | `pages/SettingsPage.ets` 的 `RECONFIGURE` 按钮增加 `.enabled(this.isAdmin())`，与同区 `ROTATE_SECRET` 一致；非 ADMIN 控件禁用，服务层 RBAC 仍为最终判定（`addGatewayToFamily` 残余见 §6）。测试：`T18_R2_settingsReprovisionRequiresAdmin` 断言 SECURITY 区两个网关管理动作均受 `isAdmin()` 门控，且 `isAdmin()` 以 `MemberRole.ADMIN` 为准。 |
| **R2-02** 配网 `busy` 时取消按钮被禁用 | Medium | **Fixed** | `pages/ProvisioningPage.ets` 取消按钮移除 `!this.busy`，恢复 DES-B §16.3(1)“取消随时可用”；`cancel()` 立即清空 PoP/SSID/Wi-Fi 密码、清除错误并复位 `busy`，随后调用 `BleProvisioningViewModel.cancel()`（停扫、递增扫描代际、清 10s 定时器、销毁本会话 draft、`ble.cancel()`）。页面订阅在 `cancelled` 后不再推进步骤，晚到结果不会覆盖取消界面。测试：`T18_R2_provisioningCancelStaysAvailableWhileBusy`（源码守卫）、`T18_R2_cancelDuringPrepareWifiCancelsBleAndClearsTimer`（AP 扫描挂起时取消 → `CANCELLED`、`ble.cancel` 被调用、定时器为 0）。 |
| **R2-04** DoorCard“关联门磁”一次性 skip 后成死按钮 | Low | **Fixed** | `pages/DeviceControlPage.ets` 的显式 `onConfigureLink` 现在重置 `doorGuideDismissed = false` 并打开 `doorGuideVisible = true`。一次性规则只抑制自动弹窗；显式按钮始终有效。按钮仍仅在 `door.link.mode === 'NONE'` 时显示，已关联后不出现。测试：`T18_R2_doorExplicitLinkButtonReopensGuide`。 |
| **R2-05** 配网中途权限/蓝牙失败无“去设置”CTA | Low | **Fixed（页面层）** | 写范围不含 `viewmodel/`，因此在 `ProvisioningPage` 增加 `@State permission` 有效权限镜像：每次发布先同步 `view.permission`，当错误码为 `PROVISIONING_PERMISSION_DENIED`/`PROVISIONING_BLUETOOTH_OFF` 时更新为 `DENIED`/`BLUETOOTH_OFF`。中途失败且 `localStep >= 2` 时保留当前 Step 2/4，不强制跳回 Step0；通用错误区在 `permissionNeedsSettings() && localStep !== 0` 时渲染“去设置”CTA（Step0 仍保留原 CTA）。`openSettings()` 走既有 `PermissionPort.openSettings` seam。测试：`T18_R2_midFlowPermissionFailureKeepsStepAndOffersSettings`。 |
| **R2-06** 未用 import / `width('auto')` 设备证据 | Low/Info | **Fixed（import）/ Recorded（设备）** | `pages/MainShell.ets` 删除未使用的 `AppMotionTokens` import。`PrimaryButton` 的 `.width('auto')` + `minWidth` 布局与 en-US 长标签换行仍无设备证据，记录给 T-19。 |
| **R2-07** 网关/房间/场景服务层残余 | Info | **Recorded（不改）** | `addGatewayToFamily` 无 actor/RBAC、RoomService 缺省 actor 的 v1 local-admin trust、SceneService 无 family/room 上下文均为已声明上游残余，归属 C-22/C-09/C-15/C-12，本次不扩大范围。 |
| **R2-08** 修复报告 §1.2 引用不存在的 §3.1 | Info | **Recorded（不改前序报告）** | `t18-fix-report.md` 是 handoff 冻结输入，未修改以保持证据哈希；已在本报告记录该文档引用失效，待归档/后续文档任务修正。 |
| **R2-03** C-09/C-19/C-23 公共签名未在 DES-A/DES-B 登记 | Medium（契约） | **Out of scope / 未关闭** | 需 `solution-architect` 在 DES-B §4.1.3/§16.1.2/§23 与 DES-A §27.4 登记增量并触发 Change Impact；本次实现未改公共签名，也未改契约文件。 |

---

## 2. 新增测试（685 → 690）

| 文件 | 新增用例 | 覆盖 |
|---|---|---|
| `entry/src/test/host/UiPages.test.mjs` | `T18_R2_settingsReprovisionRequiresAdmin` | R2-01：SECURITY 区 rotate/reprovision 双动作 ADMIN 矩阵 |
| `entry/src/test/host/UiPages.test.mjs` | `T18_R2_provisioningCancelStaysAvailableWhileBusy` | R2-02：取消按钮不受 `busy` 禁用；`cancel()` 清秘密/复位 busy |
| `entry/src/test/host/UiPages.test.mjs` | `T18_R2_doorExplicitLinkButtonReopensGuide` | R2-04：显式入口重置 dismissed 并打开引导 |
| `entry/src/test/host/UiPages.test.mjs` | `T18_R2_midFlowPermissionFailureKeepsStepAndOffersSettings` | R2-05：权限错误码映射、Step2/4 保留、错误区“去设置”CTA |
| `entry/src/test/host/ViewModelBle.test.mjs` | `T18_R2_cancelDuringPrepareWifiCancelsBleAndClearsTimer` | R2-02：`prepareWifi` 挂起时取消→`CANCELLED`、BLE 取消、定时器清零 |

- 既有 685 条用例未删除、未弱化：总数 690，pass 690 / fail 0 / skipped 0。
- 未新增 i18n 键，复用 `profile.settings`（“去设置”）；资源目录未修改。

---

## 3. 验证（实际执行，cwd = 仓库根）

| # | 命令 | 结果 |
|---|---|---|
| 1 | `ohpm install` | exit 0；`install completed in 0s 39ms` |
| 2 | `hvigorw clean assembleHap --no-daemon` | exit 0；**BUILD SUCCESSFUL in 14 s 512 ms**；0 ERROR（既有 ArkTS/SDK 警告不变） |
| 3 | `codelinter -c code-linter.json5 -p default .` | exit 0；**Defects 25 / Errors 0 / Warns 25 / Suggestions 0**（与修复前同量级） |
| 4 | `entry/src/test/run-host-tests.sh` | exit 0；**tests 690 / pass 690 / fail 0 / skipped 0**（新增 5，既有 685 保留） |
| 5 | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | exit 0；**blockingFailures=0 / missingKeys=0**；warnings=139；hardcoded=82（与修复前一致） |

补充静态核对：

- `git diff --stat` 仅 6 个允许路径：4 个 `pages/*.ets`、2 个 `entry/src/test/host/*.test.mjs`；无 `viewmodel/`、`resources/`、`repository/`、`ohosTest/`、`module.json5`、`AppScope/` 改动。
- 未新增用户可见硬编码文案；新增注释/技术错误码字符串不进入 UI。
- `pages/**` 未新增 `@Provide/@Consume`，未 `new` 服务/仓储/VM；DI 约定与 RBAC fail-closed 未变。
- i18n parity 未动：未新增/删除/修改 zh-CN、en-US 资源键。

---

## 4. 变更文件

- `entry/src/main/ets/pages/SettingsPage.ets`（R2-01）
- `entry/src/main/ets/pages/ProvisioningPage.ets`（R2-02、R2-05）
- `entry/src/main/ets/pages/DeviceControlPage.ets`（R2-04）
- `entry/src/main/ets/pages/MainShell.ets`（R2-06 import 清理）
- `entry/src/test/host/UiPages.test.mjs`（4 条 R2 测试）
- `entry/src/test/host/ViewModelBle.test.mjs`（1 条 R2 测试）
- `artifacts/50-implementation/t18-fix2-report.md`（本报告）

---

## 5. 偏离与假设

1. **R2-05 在页面层实现**：handoff 写范围不含 `entry/src/main/ets/viewmodel/`，因此未修改 `BleProvisioningViewModel.handleProvisionFailure` 的 `permission` 发布；页面维护有效权限镜像并在 Step2/4 提供 CTA。语义满足 UI 恢复路径，但 C-23 VM 的 `view.permission` 在中途权限失败后仍保持原值（例如 `GRANTED`）。若后续要求 VM 状态自洽，应在 C-23 增量任务中补 VM 层更新并加 VM 单测。
2. **R2-03 未处理**：契约登记属 `solution-architect`；本任务不改 DES-A/DES-B，也不改契约冻结文件。
3. **R2-08 未修改前序报告**：`t18-fix-report.md` 是 handoff 冻结输入，保持字节不变；失效引用仅在本报告记录。
4. **取消竞态**：C-23 `cancel()` 已停扫/清定时器/取消 BLE；页面以 `cancelled` 状态阻断晚到步骤展示。若 BLE 层在 `cancel()` 前已成功返回 AP 列表，VM 可能短暂发布 `AP_SCANNING`，但页面保持取消界面。彻底消除需在 VM 增加 prepare 代际（不在本次写范围），记录为残余风险。

---

## 6. 残余风险

| 项 | 状态 | 归属 |
|---|---|---|
| R2-03 C-09/C-19/C-23 签名/端口登记 + Change Impact | **未关闭（Medium，契约）** | `solution-architect`；T-20 检查器 |
| `FamilyRepository.addGatewayToFamily` 无 actor/RBAC | Recorded（Info） | C-22/C-09/C-15 |
| R2-05 VM 层 `permission` 不更新（页面镜像已修复 UI） | Recorded | C-23 增量/后续 |
| 取消与 `prepareWifi` 晚到结果的 VM 代际保护 | Recorded（页面已屏蔽） | C-23 增量/后续 |
| `PrimaryButton` `width('auto')` + en-US 长标签/小屏/安全区 | **BLOCKED（设备）** | T-19 |
| 真实 BLE/权限弹窗/AP 扫描/绑定探针/LAN/云/TLS | **BLOCKED（设备）** | T-19 / 用户实机 |
| 设备/视觉/动效/触感/读屏 | **BLOCKED** | T-19 |

---

## 7. 约束核对

- 未修改 `entry/src/main/resources/**`、`entry/src/ohosTest/**`、`repository/**`、`viewmodel/**`、`service/**`、`module.json5`、`AppScope/**`、契约/计划/评审报告。
- 未切换分支、未 pull/merge/rebase/push；提交在 `task/wp-073-ui-pages` 上完成。
- 未改变错误码语义、未新增 i18n 键、未改变 DI 约定与 RBAC fail-closed 行为。
- 既有 685 条 host 用例全部保留并通过（总 690）。
