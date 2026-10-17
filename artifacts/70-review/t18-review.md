# T-18 页面与组件独立评审（C-24 / C-25 / C-26 / C-27）

- **Artifact ID**: T18-REVIEW
- **Producer**: agent:quality-reviewer
- **Task**: `wp-074-review-t18`（Handoff `state/handoffs/wp-074-review-t18.json`）
- **Role**: quality-reviewer（独立于实现作者）
- **Reviewed revision**: `155be17`（base `6737303`；实现 `ba9dca6` + 设备编译骨架 `155be17`）
- **Branch**: `task/wp-073-ui-pages`（parent `feat/yaocore-app`）
- **Review scope**: `pages/**`、`components/**`、`common/theme/**`、`app/**`、`resources/**`、`entry/src/test/**`、`entry/src/ohosTest/ets/test/**`、`artifacts/50-implementation/t18-ui-pages.md`
- **Workflow**: STANDARD / GATED_AUTO
- **Date**: 2026-10-18
- **Verdict**: **CHANGES_REQUIRED**
- **Status**: COMPLETE（代码级独立评审；设备/视觉仍 BLOCKED，不作为 PASS）

> **结论先行**：C-24 token、21 个复用组件和 C-25/C-26/C-27 页面主体已具备，构建、主机测试、i18n 门禁和 ohosTest 编译均可复现通过。但本次评审发现 4 个 High 级问题：**LightCard 的电源回调 `onToggle` 从未接线，灯光无法开关**；**GUEST 可执行场景（页面无 RBAC 门，SceneService 也无授权检查）**；**房间/未分配池/网关等管理入口对非 ADMIN 未隐藏且部分服务无 RBAC 检查**；**PENDING 状态下 LightCard 滑杆被 `.enabled(false)` 禁用，破坏 55ms 跟手滑杆/TouchUp 交互**。此外存在 D-12 白名单未同步、配网 AP 列表/真实握手顺序、权限“去设置”、门锁阶段进度条等 Medium 问题。因此不能给出 PASS；修复并重新验证后需再次独立复审。

---

## 1. 范围、revision 与过程核对

| 项 | 结果 | 证据 |
|---|---|---|
| Review base | `6737303`；HEAD `155be17`；工作树干净 | `git status --short` 无输出 |
| 提交 | 2 个：`ba9dca6 feat(ui): 实现设计系统与全量页面`、`155be17 test(ui): 增加 T-18 页面设备编译骨架` | `git log --format='%h %s' 6737303..155be17` |
| 变更路径 | 45 个；与 handoff review_targets 一致 | `git diff --name-only 6737303..155be17 \| wc -l` = 45 |
| 越界修改 | 未发现 `service/**`、`repository/**`、`viewmodel/**`、`entryability/**`、`module.json5`、契约/计划/旧评审报告改动 | `git diff --stat` / 路径核对 |
| ShellTheme 迁移 | `app/ShellTheme.ets` 删除；`common/theme/ShellTheme.ets` 为 facade；无 `app/ShellTheme` 引用 | `git diff --name-status`；`grep -rn "app/ShellTheme"` 仅注释 |
| 秘密/构建产物 | 未发现提交的秘密、HAP/ELF/证书或构建目录；evidence 日志为测试证据 | `git diff` secret 模式扫描；`git status --ignored` |
| 报告范围 | 仅本报告为评审写入；未编辑被审代码 | 本文件是本任务唯一写入 |

**评审限制**：无设备/模拟器/Previewer/签名，无法执行 ArkUI 渲染、视觉、动效、触感、读屏、真实 BLE/LAN/云；`COMPILED_ONLY` 与 `BLOCKED` 均未按 PASS 处理。

---

## 2. 独立复验结果（cwd = 仓库根）

| # | 命令 | 本次结果 | 与实现报告的一致性 |
|---|---|---|---|
| 1 | `entry/src/test/run-host-tests.sh` | **672/672 PASS**，fail 0 / skipped 0；exit 0 | 与 `t18-host-node-tests.tap` 一致 |
| 2 | `codelinter -c code-linter.json5 -p default .` | **Errors 0 / Warns 25 / Suggestions 0**；exit 0 | 与 `t18-codelinter.log` 一致 |
| 3 | `hvigorw clean assembleHap --no-daemon` | **BUILD SUCCESSFUL in 14 s 264 ms**；0 ERROR；68 条既有 ArkTS warning | 与 `t18-clean-assemble.log` 结果一致（耗时因缓存不同） |
| 4 | `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **BUILD SUCCESSFUL in 13 s 75 ms**（仅编译，未运行） | 与 `t18-ohosTest-assemble.log` 的 COMPILED_ONLY 口径一致 |
| 5 | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | **blockingFailures=0 / missingKeys=0**；warnings 134；hardcoded 77（技术枚举/既有模块） | 与 `t18-i18n-checker.log` 一致 |
| 6 | `ohpm install` | exit 0；`install completed` | 与报告一致 |
| 7 | 颜色/字符串 parity | base/dark color **44/44**；base/en_US string **53/53**；rawfile zh/en **543/545**（en 仅多 `device.count_one/_other` 复数变体，基键与 zh 对齐） | 支持报告 §3 的 parity 声明 |
| 8 | DI/分层静态扫描 | 生产 `pages/**`、`components/**` 无 `@Provide`/`@Consume`；无页面 `new` 服务/仓储/VM；`app/ShellTheme.ets` 已删除 | 支持报告 §2 的 DI 声明，但不支持其“D-12 合规”声明（见 F-06） |
| 9 | 提交范围/格式 | 45 路径、两提交、subjects 符合 `<type>[(scope)]: <description>` | 无范围外提交 |

> **注意**：复验通过只能证明构建/主机逻辑/i18n 检查；不能证明 ArkUI 页面行为。以下 Findings 均来自源码/source-level 审查，不把编译或主机测试当作 UI PASS。

---

## 3. Findings（按严重度）

> 级别：**High** = 阻断 CQG-T18 / 需修复后重新评审；**Medium** = 契约/安全/可用性缺口，需修复或由架构师书面裁定；**Low** = 非阻断但应在 CQG-T18 记录；**Info** = 已声明偏离/跟踪项。

| ID | 严重度 | 位置 | 契约/约束 | 证据与影响 | 建议/归属 |
|---|---|---|---|---|---|
| **F-01** | **High** | `entry/src/main/ets/components/DeviceCards.ets:45`（声明），`:55-160`（build 无调用） | DES-B §13.1.3 `LightCard.onToggle`；§14.1.4 LightControl；UIUX §4.3 | `LightCard` 声明了 `onToggle`，但 build 中没有任何 Button/开关调用它；`HomePage` 的 `quickToggle` 与 `DeviceControlPage` 的 `onToggle` 因此永远不会执行。Home 快捷卡片与灯光详情页都无法开关灯，只能看状态/拖亮度/选颜色。 | 在卡片内增加电源开关控件（或复用 `PrimaryButton`/Toggle），并为此补 source-level/设备 smoke；`implementation-engineer`。 |
| **F-02** | **High** | `entry/src/main/ets/pages/ScenePage.ets:284-299`；`entry/src/main/ets/viewmodel/SceneViewModel.ets:110-134`；`entry/src/main/ets/service/scene/SceneService.ets:141-...` | DES-B §11.3.1（T-13 F-08：GUEST 一律不得执行场景，UI 隐藏/禁用，服务层仍拒绝）；§15.3(1) | ScenePage 只按 `scene.isEnabled`/`running` 禁用 Run；未检查 `appContext.session.role`/`FamilyCapabilities.canExecuteScene`。`SceneService.run` 没有 session/actor 参数，`AuthService.canExecuteScene`（`service/auth/AuthService.ets:493-506`）虽存在但未被调用。GUEST 点击后场景会实际下发到设备，且无允许房间校验。 | 页面隐藏/禁用 GUEST 的 Run；同时由 `solution-architect` 决定 C-22/C-11 的 session 授权入口并补服务层拒绝；补 host/source-level 测试。 |
| **F-03** | **High** | `entry/src/main/ets/pages/RoomsPage.ets:258-268`（Add room）、`:234-249`（RoomCard 编辑/删除）、`:309-323`（UnassignedPool assign）；`entry/src/main/ets/pages/RoomManagePage.ets:379-394`；`entry/src/main/ets/service/room/RoomService.ets:203-217` | DES-B §11.3.1（MEMBER 不可房间/网关管理）；§15.3(1)；§14.1.3 | `RoomsPage` 对所有角色显示 Add room/RoomCard 编辑删除/未分配池指派；`RoomManagePage` 虽隐藏创建/改名/删除，但仍显示 `UnassignedPool` 指派。`RoomService.assignDevice`/`createRoom` 等没有角色或 session 校验，故 MEMBER/GUEST 可通过池指派实际修改设备归属。 | 页面按 `appContext.session.role`/`FamilyCapabilities.canManageRooms` 隐藏/禁用入口；服务层由 C-22/C-09 增加授权（跨层，非纯 UI）；补 RBAC 静态/设备测试。 |
| **F-04** | **High** | `entry/src/main/ets/components/DeviceCards.ets:112-113` | DES-B §13.1.4（PENDING 滑杆跟手；禁止重复提交同动作）；§14.3(3)；PF-02；UIUX §4.4 | `LightCard` 滑杆 `.enabled(this.record.isControlAllowed && this.visual() !== CardVisualState.PENDING)`。第一次 `onChange` 触发 `DeviceViewModel.beginContinuous` 后 phase 立即变 PENDING，滑杆随即被禁用，后续拖动不能继续跟手，55ms 节流/TouchUp 的交互前提被破坏。 | 允许 PENDING 时滑杆继续接收输入；仅对会导致重复命令的同类动作做幂等保护（VM 已有 session/gate）；在 PENDING 中保持视觉跟手。`implementation-engineer`，补 UI smoke。 |
| **F-05** | **Medium** | `entry/src/main/ets/components/DeviceCards.ets:112-113`（Light）、`:212/241/260`（Climate）、`:370-371/382-383`（Door）；`entry/src/main/ets/repository/DomainModels.ets:63-64` | DES-B §13.1.4（OFFLINE 可查看、不可控制）；§14.3(3) | `DeviceRecord.isControlAllowed` 只检查 enabled/unassigned/supported/dismissed，**不检查在线**；卡片的 `.enabled` 未使用 `visual()` 的 OFFLINE/READ_ONLY/DISABLED 结果。离线设备仍显示可点击的滑杆/模式/锁按钮，用户会得到 REVERT，而不是“不可控制”的禁用态。 | 控制 `.enabled` 同时要求 `visual()` 不属于 OFFLINE/READ_ONLY/DISABLED；保持状态文字；补 UiMapping/卡片测试。 |
| **F-06** | **Medium** | `entry/src/main/ets/app/PageVmFactory.ets:20-30`；`pages/HomePage.ets:13` 等页面 import；`components/DeviceCards.ets:16-23`；`components/DeviceGrid.ets:11-14`；`components/RoomChipBar.ets:8`；`components/StatusPanels.ets:8-13`；`components/support/UiMapping.ets:15-32`；`pages/FamilyManagePage.ets:30-35`；`pages/ProvisioningPage.ets:22-32`；`pages/SettingsPage.ets:24-25`；`pages/RoomManagePage.ets:25` | DES-B §2.3 D-12（`pages/**` 白名单不含 `app/PageVmFactory`；`components/**` 不得 import `viewmodel/**`、`service/**` 实现或 `repository/DomainModels`；仅允许 C-11/C-15 只读 DTO 的 `import type`）；§17.4；T-17 裁定 U-01（放宽必须 Change Impact） | 实现报告声称 D-12 合规，但实际：① 所有页面 import `app/PageVmFactory`，D-12 未列；② `components/**` 以值 import `viewmodel/core`、`viewmodel/core/DoorConfirmationTracker`、`service/ac/AcModels`，并以 type import `repository/DomainModels`；③ 页面 import `service/{family,cloud,ble,room}` DTO 与 `repository/DomainModels`。这些多为 C-24 props/只读 DTO 的既有契约冲突，不是纯实现疏忽，但当前没有 D-12 修订/Change Impact，C-29 检查器会失败。 | `solution-architect` 做 D-12 增量修订（明确 `PageVmFactoryPort`、C-24 props 所需只读 DTO 的 `import type` 例外）或把 UI 类型抽到 `model/**`；实现按裁定收敛。T-20 前必须落文，不得静默放宽。 |
| **F-07** | **Medium** | `entry/src/main/ets/pages/ProvisioningPage.ets:157-174`（仅 Step4 调用 submit）、`:376-419`（Step3 AP 列表） | DES-B §16.1.2 Step2 Handshake/Step3 AP 列表；§16.3(1) 6 步单向推进 | C-23 的 `submit(pop, ssid, wifiPassword)` 是聚合入口，首次调用才启动 BLE/Security1/AP 扫描。页面在 Step2 只收 PoP、Step3 收 SSID，实际握手/AP 扫描发生在 Step4 的 submit 内；此时 `localStep=4`，Step3 的 `accessPoints` 列表已不可用。用户实际被迫手输 SSID，且 Step2/Step3 的进度与真实状态不一致。 | 由 C-23 提供独立 `startHandshake/scanAccessPoints` seam，或明确把聚合流程改为单页/延时展示并更新契约；当前实现报告已记录偏离，但 CQG-T18 需要架构裁定/跟踪到 C-23 增量。 |
| **F-08** | **Medium** | `entry/src/main/ets/pages/ProvisioningPage.ets:239-248` | DES-B §16.1.2 Step0“去设置”；§16.2 权限拒绝/蓝牙关闭 | 页面只显示 `permission_denied`/`bluetooth_off` 文本，没有“去设置”入口。`PermissionGate.openSettings()` 已存在（`app/PermissionGate.ets:117-126`），但 C-23 VM 未暴露；用户被阻断后无恢复路径。 | C-23/C-28 seam 暴露 `openSettings`，或页面通过允许的 PermissionPort 显式 prop 调用；补 source-level/设备测试。 |
| **F-09** | **Medium** | `entry/src/main/ets/pages/ProvisioningPage.ets:537-540`；`app/NavigationService.ets:35/47`；`SettingsPage.ets:431-445` | DES-B §16.1.2 `RECONFIGURE`/`ROTATE_SECRET` + `expectedGatewayId` 校验；§16.3 | 页面只对 `ROTATE_SECRET` 显示提示；`expectedGatewayId` 从未被读取；`RECONFIGURE` 无行为差异；`submit` 没有 expectedGateway 参数。轮换入口虽可进入向导，但不校验当前网关，存在配错网关/重复绑定的风险。 | 由 C-23 暴露 expectedGateway/rotation 校验入口并接线；在实现前至少禁用未校验的 ROTATE/RECONFIGURE 入口并记录跟踪（不能显示为已实现）。 |
| **F-10** | **Medium** | `entry/src/main/ets/pages/DeviceControlPage.ets:189-210`、`:411-425` | DES-B §13.1.4（UNVERIFIED 使用 `door.link.unverified`，不得显示“已锁好”）；§14.1.4 四阶段；SC-14 | `stageIndex()` 把 `SECURED/OPEN/UNCONFIRMED/UNKNOWN/UNVERIFIED/FAILED` 全部映射到 4；四阶段圆点在 UNVERIFIED/FAILED/UNKNOWN 时全部点亮。文字仍显示 UNVERIFIED，但视觉上呈现“四阶段完成”，与“无证据不得升级 SECURED”及防假成功原则冲突。 | 为 UNVERIFIED/FAILED/UNKNOWN 使用失败/未知视觉（不点亮第 4 阶段或使用琥珀/红状态）；补状态映射测试与设备视觉检查。 |
| **F-11** | Low | `entry/src/main/ets/pages/ShellViews.ets:98` | CQG-T17 R2-02（T-18 替换 onboarding 语义不匹配键）；DES-B §15.1.2 | NO_PROFILE 的“加入家庭”入口仍使用 `family.switch`（“切换家庭”），而不是 T-18 新增的 `onboarding.join.title`/专用 join 键；实现报告 §2.6 声称 R2-02 已处理，实际 OnboardingView 改了、ShellViews 入口未改。 | 换成 `onboarding.join.title` 或新增 `onboarding.join.entry`；补 R2-02 回归断言。 |
| **F-12** | Low | `entry/src/main/ets/pages/ProfilePage.ets:173-200` | DES-B §13.3(7)（每个列表/页面必须有 Loading/Empty/Error，不得用空白代替错误） | Profile 只处理 `LOADING`；`family.phase === 'ERROR'` 时既不显示 `ErrorState`，也不显示 `family.error`；`loadProfileName()` 失败被吞掉。家庭数据读取失败时用户只看到档案卡/入口，无法知道状态。 | 增加 `ErrorState`/重试入口，并显示 `ViewModelError.i18nKey`；补 source-level/设备检查。 |
| **F-13** | Low | `entry/src/main/ets/components/CommonControls.ets:87` | DES-B §13.3(3)（按钮不得固定像素宽度）；I18N-07 | `PrimaryButton` 在 `fullWidth=false` 时固定 `width(168)`；多处英文长标签（如 “Create family and profile”“Assign a room”）可能被截断，违背 20-40% 文本膨胀要求。 | 改为 `constraintSize({ minWidth: 168 })`/自适应宽度并允许换行；抽查 en-US 长文本。 |
| **F-14** | Low | `entry/src/main/ets/components/DeviceCards.ets:156-159`；`entry/src/main/ets/common/theme/AppTheme.ets:137-155`；`pages/MainShell.ets:22` | DES-B §13.1.1（动效 token 必须引用 AppMotionTokens，不得散落 magic number）；§13.3(6) | 只有 LightCard 使用 `.animation`，且 duration 硬编码 `220/0`、`Curve.EaseInOut`；`AppMotionTokens.motionMs()` 未被使用，Climate/Door 无动效接线，`MainShell` 还保留了未使用的 `AppMotionTokens` import。 | 统一使用 `AppMotionTokens.FADE_MS/REDUCED_MOTION_MS`；补 reduced-motion 分支；清理未用 import。 |
| **F-15** | Low | `entry/src/main/ets/components/CommonControls.ets:19`（GlassSurface）、`:186`（SliderControl）、`:104`（IconButton） | DES-B §13.1.3/§13.4（C-24 复用组件） | 三个组件完全未被页面使用；LightCard 直接使用原生 Slider，而不是 C-24 `SliderControl`。降低了“单一设计系统/复用组件”的实际一致性，也让 55ms 滑杆逻辑分散。 | 在卡片/页面接入 GlassSurface/SliderControl，或删除未使用组件并在报告中降级其交付声明。 |
| **F-16** | Low | `entry/src/main/ets/pages/HomePage.ets:229-231`；`entry/src/main/ets/pages/RoomsPage.ets:185-191` | DES-B §14.1.2（点击家庭名打开切换）；§14.1.3 StatusBanner（简化） | Home 点击家庭名只 push `FAMILY`，未传 `section: 'FAMILY'`，默认落到成员页；Rooms 的 StatusBanner 永远传 `gateway: undefined`/`cloud: UNKNOWN`，即使有网关也显示“未绑定网关/云端未配置”。 | 传 `section: 'FAMILY'`；Rooms 复用真实 `HomeViewModel`/网关状态或明确简化为不误导的文案。 |
| **F-17** | Low | `entry/src/main/ets/pages/SettingsPage.ets:152-159`、`:367-372`、`:394-416` | DES-B §16.1.3（testConnection 显示成功/401/403/网络错误；显示 effective profile） | `cloudTested` 只控制错误文本；成功时没有明确的“连接成功”提示，只有状态刷新。安全区只显示 `view.profile`，未显示 `GatewaySecurityView.effectiveProfile`（DTO 已存在），无法区分“持久 profile”和“生效 profile”。 | 成功/失败均给明确结果；显示 effective profile 或说明为何不展示。 |
| **F-18** | Low | `entry/src/test/host/UiPages.test.mjs:312-336`；`entry/src/ohosTest/ets/test/ui/UiPagesDevice.test.ets:52-90` | DES-B §13.4/§14.4/§15.4/§16.4；test-plan CQG-T18 RBAC/UI smoke | 新增 16 条 host 用例有效覆盖纯选择器/路由/onboarding，但 `T18_pagesUseExplicitPropsAndNoProvideConsume` 只检查 `@Provide/@Consume`，未检查页面 `new`、D-12 import、RBAC 门、LightCard toggle/PENDING/offline 控制；设备骨架只做 import 编译。当前 672 PASS 不能防止上述 High/Medium 回归。 | 增加 source-level 断言（无 `new`、D-12 白名单、GUEST/非 ADMIN 入口隐藏、LightCard `onToggle` 被引用）；T-19 设备 smoke 覆盖 toggle/PENDING/离线。 |
| **F-19** | Low | `entry/src/main/ets/pages/DeviceControlPage.ets:170-173`；`entry/src/main/ets/components/DeviceCards.ets:305-319` | DES-B §13.1.4（UNVERIFIED 文案）；§14.1.4 DoorLinkDialog 一次性引导 | `doorNeedsLinkGuide` 在每次 door VM 发布 IDLE + link NONE 时重新置 true；用户“跳过”后若 VM 再发布状态，引导会再次出现，不是一次性。`lockKey()` 对 `UNKNOWN_INITIAL` 回退到 `door.link.unverified`，可能在未关联门磁时显示“门磁联动未验证”而非“未知”。 | 记录一次性 dismissed 状态（页面/VM）；`UNKNOWN_INITIAL` 使用 `door.state.unknown`；补状态测试。 |
| **F-20** | Low | `entry/src/main/ets/pages/ProvisioningPage.ets:176-187` | DES-B §16.1.2（取消显示已取消，清理 PoP/Wi-Fi/草稿）；§16.3(2) | 页面取消后立即 `pop()`，没有显示“已取消”；`pop`/`wifiPassword` 页面 state 未显式清零（依赖组件销毁）。VM 已停止扫描/清 timer/destroy drafts，但 secret 清理的页面层证据不完整。 | 在 pop 前显示取消态/清空页面 secret state；在 aboutToDisappear 也清空；补设备/内存生命周期检查。 |
| **F-21** | Low | `entry/src/main/ets/pages/FamilyManagePage.ets:640-680`、`:460-481` | DES-B §15.1.2 InvitationRow（角色/模式/倒计时/剩余次数/回执状态）；转让 Admin 选择 ACTIVE MEMBER | 邀请行未显示 `usedCount/maxUses` 与回执状态；转让按钮对所有非 owner 成员显示，未过滤 DISABLED/EXPIRED 成员；GUEST 只能“延长”，没有改回 MEMBER 的入口。 | 补齐邀请字段/回执状态；按成员状态过滤转让候选；明确 GUEST→MEMBER 的操作。 |
| **F-22** | Info | `entry/src/main/resources/base/element/color.json`、`dark/element/color.json` | DES-B §13.3(1) 单一设计系统；I18N-08 | 新 `AppColors` 使用 `surface/primary/...`，旧 shell 仍使用同值的 `shell_surface/shell_primary/...`，形成两套等价颜色资源；本次未把旧 shell 全部迁移到 `AppColors`。不造成功能错误，但增加维护/暗黑漂移风险。 | 后续把 shell 颜色别名收敛到 AppColors 或记录为兼容 facade；不要让新页面使用 `shell_*`。 |
| **F-23** | Info | `artifacts/50-implementation/t18-ui-pages.md` §5/§6 | 实现报告已声明 | 设备/视觉/动效/触感/读屏、BLE 配网/权限弹窗/真实扫描、门磁联动、QR/ScanKit、设备删除/改名、SceneEditSheet、通知系统状态、权限去设置、expectedGateway 强校验均为 `BLOCKED`/`DEFERRED`。本评审确认这些不是 PASS 证据，必须由 T-19/T-20 或后续 C-22/C-23 增量承接。 | 保留为跟踪项；不得在 CQG-T18/IG-3 写成已完成。 |

---

## 4. High/Medium 详细说明

### 4.1 F-01 灯光无法开关（High）

`LightCard` 的公开契约包含 `onToggle`，页面在 `HomePage.quickToggle` 和 `DeviceControlPage.lightControl` 都已接线；但 `LightCard.build()` 只渲染状态文字 `common.on/off`、`View` 按钮、亮度 Slider 和颜色按钮，从未调用 `this.onToggle()`。这是“回调存在但无 UI 触发点”的典型死接线：

- `DeviceCards.ets:45` 声明 `onToggle`；
- `DeviceCards.ets:55-160` 无 `onToggle` 调用；
- `DeviceGrid.ets:59-61` 传入 `onToggle: onQuickToggle`；
- `DeviceControlPage.ets:275-280` 传入 `vm.togglePower`。

影响：Home 快捷灯卡、Rooms 房间灯卡、设备详情灯控页都无法执行开/关；用户只能改亮度/颜色。该问题不会被 host 测试发现，因为组件不渲染。修复时建议把电源按钮做成 44vp 的可访问 Button/Toggle，并在 PENDING 时只阻止重复“同动作”提交，而不是禁用整个卡片。

### 4.2 F-02 GUEST 场景执行（High）

`AuthService.canExecuteScene` 已按 T-13 F-08 对 GUEST 返回 `RBAC_DENIED`，但 `SceneViewModel` 没有注入 AuthService/AppContext 授权端口，`SceneService.run` 也没有 session/actor 参数。`ScenePage` 只检查 `scene.isEnabled` 和 `isRunning`，因此 GUEST 可以点击 Run；服务层不会拒绝，场景动作会真实下发。由于 GUEST 的 `allowedRoomIds` 也未在 `SceneService`/`DeviceRepository` 中参与执行，GUEST 可能控制未授权房间的设备。

修复必须双管齐下：页面按 `appContext.session.role` 或 `FamilyCapabilities.canExecuteScene` 隐藏/禁用入口；C-22/C-11 增加服务层授权拒绝。仅隐藏 UI 不满足“服务层仍拒绝”的契约。

### 4.3 F-03 房间/池/网关 RBAC（High）

`FamilyCapabilities.canManageRooms` 已由 `FamilyViewModel` 计算，但 `RoomsPage` 完全未使用；`RoomManagePage` 只用 `session.role === ADMIN` 隐藏了创建/改名/删除，没有隐藏 `UnassignedPool` 的“指派房间”。`RoomService.assignDevice` 也不接收 actor/role，因此 MEMBER/GUEST 可以实际改归属。同类问题：

- Home/Profile 的“添加网关”入口对所有角色显示；`FamilyRepository.addGatewayToFamily` 没有 RBAC 检查；
- Settings 的“高级手动 IP/端口探测”对所有角色可用；`SettingsViewModel.probeManualAddress` 没有角色检查。

建议页面按 `AppContext.session.role`/`FamilyCapabilities` 隐藏入口，并由 `solution-architect` 在 C-22/C-09/C-15 补齐服务层授权。设备级 GUEST allowedRoomIds 是更大的 C-12/C-21 上游问题，建议在 IG-3 前专项评估（本报告作为残余风险跟踪）。

### 4.4 F-04 PENDING 滑杆被禁用（High）

`DeviceViewModel.beginContinuous()` 在第一次滑动时立即发布 `ControlPhase.PENDING`（`DeviceViewModel.ets:237-242`）；`UiMapping.visualState` 把它映射为 `CardVisualState.PENDING`。`LightCard` 的 Slider `.enabled()` 明确排除了 PENDING，导致滑杆在拖动过程中变成禁用态。UIUX §4.4 要求 PENDING 时滑块 100% 跟手、55ms 节流、TouchUp 强同步；实现报告声明“PENDING 跟手”，与代码不符。

`DeviceViewModel` 已有 `ThrottleGate`、`begin/update/end` 与 session 取消保护，足以处理重复动作；卡片不应以禁用滑杆的方式阻断。建议把 `.enabled` 改为只受 `isControlAllowed`/离线/只读控制，保留 PENDING 输入。

### 4.5 F-05 离线控制未禁用（Medium）

`DeviceRecord.isControlAllowed` 计算不含在线状态，而卡片控制按钮只检查 `record.isControlAllowed`。`UiMapping.visualState` 正确返回 OFFLINE，但 `.enabled` 未使用该结果，因此离线灯/空调/门锁仍可操作并进入 REVERT。DES-B §13.1.4 明确 OFFLINE “可查看，不可控制”。建议统一使用 `visual()` 或 `record.state.snapshot.isOnline` 作为控制门，避免用户误以为命令可执行。

### 4.6 F-06 D-12 分层（Medium，需架构裁定）

实现报告 §6.3 已披露 `UiMapping`/components 的风险，但实际范围更大：

- 新 seam `app/PageVmFactory` 被所有页面 import，但 D-12 的 `pages/**` allowlist 未列 `PageVmFactory`；
- `components/**` 以值 import `viewmodel/core`、`DoorConfirmationTracker`、`service/ac/AcModels`；
- 页面 import `service/{family,cloud,ble,room}` DTO 与 `repository/DomainModels`。

其中一部分是 C-24 props 契约（`ControlUiState`/`AcViewState`/`DoorUiState`/`DeviceRecord`）自身的类型归属与 D-12 文字冲突；另一部分是新 seam 未登记。T-17 裁定要求“更严格者优先、任何放宽必须走 Change Impact”，因此不能仅以“C-24 需要”解释。建议 `solution-architect` 在 CQG-T18 前给出 D-12 增量修订：明确允许 `app/PageVmFactory`、C-24 只读 UI DTO 的 `import type` 例外，或把 UI-facing 类型抽到 `model/**`；T-20 的 `check_layering.py` 应按修订后规则实现。

### 4.7 F-07/F-08/F-09 配网向导（Medium）

- **F-07**：C-23 `submit(pop, ssid, wifiPassword)` 聚合入口导致 Step2/Step3 只是表单，真实 Security1/AP 扫描在 Step4 才发生；Step3 的 AP 列表无法在下发前使用。实现报告已记录此偏离，但 UIUX/DES-B 的 6 步状态机并未真正成立。需要 C-23 增量 seam 或正式修订向导契约。
- **F-08**：权限拒绝/蓝牙关闭仅显示文本，没有“去设置”；`PermissionPort.openSettings()` 已存在但未暴露。用户被阻断后无恢复路径。
- **F-09**：`expectedGatewayId` 仅出现在路由参数和 Settings push，ProvisioningPage 从未读取；`RECONFIGURE` 与 `NEW_GATEWAY` 无差异。轮换/重配入口当前可能配错网关，不能视为已实现。

---

## 5. 安全、i18n 与测试评估

### 5.1 安全检查

- **无 `@Provide`/`@Consume`**：生产 `pages/**`、`components/**` 静态扫描无命中；报告声明成立。
- **无页面 `new` 服务/仓储/VM**：静态扫描无命中；VM 均通过 `vmFactory` 创建并 dispose。
- **无原始错误 message/日志秘密**：页面只显示 `i18nKey`；未发现 `console.*`/`logger.*` 或 `error.message` 直出。
- **BUT**：RBAC 服务层缺口（F-02/F-03）是本次最严重的安全类问题；UI 隐藏不能替代服务拒绝。
- **门锁**：`DoorConfirmationTracker` 的四阶段证据逻辑未发现“无证据升级 SECURED”；但 F-10 的进度条视觉与 F-19 的文案回退需要修正。
- **配网秘密**：VM `submit` 对 secret/pop/wifiPassword 做 `zeroize`，取消时 `ble.cancel` + `destroyDrafts`；页面层 secret 清零证据不足（F-20）。

### 5.2 i18n 评估

- `check_i18n --strict-ui` 0 blocking、0 missing；rawfile 543/545（en 仅多 `device.count_one/_other`）；base/en string 53/53；颜色 44/44。
- 页面/组件无 CJK 字面量、无英文句子 UI 文案；`Text('▾')`/`'›'`/`'·'`/单位/协议色值为技术/图标值，可接受。
- **F-11** 的 `family.switch` 是语义不匹配键，R2-02 未完全关闭。
- **F-13** 的固定 168vp 宽度是 I18N-07 的实际风险（en-US 长标签）。
- `onboarding.*` 键、动态 `device.type.*`/`ac.mode.*`/`provisioning.step*`/`provisioning.progress.*` 均存在；未发现缺失。

### 5.3 测试质量

- 672/672 可复现，16 条 T18 用例有效覆盖纯映射/路由/activeFamily/onboarding cleanup/idempotency；`UiPagesDevice.test.ets` 是诚实的 COMPILED_ONLY 骨架，没有把编译写成设备 PASS。
- 但测试**不能捕获** F-01（无 toggle）、F-02/F-03（RBAC）、F-04/F-05（PENDING/离线控制）。`T18_pagesUseExplicitPropsAndNoProvideConsume` 的名称强于其断言（只查 `@Provide/@Consume`）。
- 建议增加 source-level 守卫（页面无 `new`、D-12 import、关键回调被引用、非 ADMIN 入口隐藏）与 T-19 设备 smoke；C-29/T-20 接管正式检查器。

---

## 6. 残余风险与跟踪

| 项 | 状态 | 归属 |
|---|---|---|
| 设备/Previewer/视觉/暗黑/长英文/安全区/动效/触感/读屏 | **BLOCKED / UNAVAILABLE** | T-19（IG-3 设备矩阵） |
| 真实 BLE/权限弹窗/扫描/绑定探针/LAN/云/TLS | **BLOCKED** | T-19；用户实机（CP-03） |
| GUEST 场景/设备 allowedRoomIds、房间/网关服务层 RBAC | **未关闭（F-02/F-03）** | C-22/C-12/C-09/C-15 + `solution-architect` / `debug-specialist` |
| D-12/D-17 与 C-24 props 类型归属、PageVmFactory seam | **未关闭（F-06）** | `solution-architect`；T-20 `check_layering.py` |
| C-23 聚合 seam 导致的 6 步向导/AP 列表/expectedGateway | **未关闭（F-07/F-09）** | C-23 增量 / 设计修订 |
| QR/ScanKit、设备删除/改名、SceneEditSheet、通知系统状态、权限去设置 | **DEFERRED/BLOCKED** | T-19/T-20 或后续任务；不得写成已完成 |
| 通知/动效/读屏/可访问性设备验证 | **BLOCKED** | T-19 |
| 测试只证明纯逻辑/编译，不证明 UI | **已声明** | 本报告 §2；CQG-T18 记录 |

**IG-3**：NOT READY（存在 High findings；设备矩阵未执行）。**T-19**：需要覆盖 F-01/F-04/F-05/F-10 的设备交互与视觉。**T-20**：需要把 D-12 检查器、RBAC 静态检查、i18n 硬编码/parity 纳入正式门禁；本次复审只能用等价静态扫描。

---

## 7. 独立声明与裁决边界

1. 本评审由 `quality-reviewer` 独立完成；未参与 T-18 实现，未编辑任何被审代码；唯一写入为 `artifacts/70-review/t18-review.md`。
2. 评审基于 `155be17` 与 handoff 冻结输入；未对 `input/`、契约、计划或旧评审报告做修改。
3. 复验命令均在本机实际执行：host 672/672、codelinter 0 error、clean assembleHap BUILD SUCCESSFUL、ohosTest 编译 BUILD SUCCESSFUL、i18n 0 blocking；未把 `COMPILED_ONLY`/`BLOCKED` 写成 PASS。
4. **Verdict 仅覆盖本次 review 范围与 revision**：`CHANGES_REQUIRED`。修复后必须以新 revision 重新运行受影响验证并再次独立复审；本报告不授予 Stage Gate 或用户验收。
5. 未发现作者自审替代；未发现提交范围外的产品代码改动；未发现秘密/构建产物入库。

---

## 8. Next action

1. **先修 High**：F-01（LightCard toggle）、F-02（GUEST scene deny）、F-03（房间/池/网关 RBAC）、F-04（PENDING slider）。
2. **再修 Medium**：F-05（离线控制）、F-06（D-12 架构裁定）、F-07/F-08/F-09（配网）、F-10（门锁阶段视觉）。
3. **Low/Info**：F-11..F-23 在 CQG-T18 记录并按风险排期。
4. 修复后执行：`run-host-tests.sh`、`codelinter`、`hvigorw clean assembleHap`、ohosTest 编译、`check_i18n --strict-ui`、D-12/RBAC 静态扫描；提交新 revision 后再次 `quality-reviewer` 复审。
5. 将本报告作为 CQG-T18 的独立评审输入；IG-3/T-19/T-20 继续跟踪设备与检查器项。

```text
STATUS: COMPLETE
SUMMARY: T-18 独立评审完成；构建/主机/i18n/ohosTest 复验通过，但发现 4 High + 10 Medium/Low 阻断项
ARTIFACTS_CREATED: artifacts/70-review/t18-review.md
ARTIFACTS_UPDATED: artifacts/70-review/t18-review.md（占位覆写）
RISKS: GUEST 场景/RBAC 服务层缺口、灯光开关缺失、PENDING 滑杆禁用、D-12 未修订、配网 AP/expectedGateway 缺口、门锁阶段视觉
VALIDATION: host 672/672；codelinter 0 error/25 warn；clean assembleHap SUCCESS；ohosTest 编译 SUCCESS；i18n blocking=0
NEEDS_CLARIFICATION: no（架构裁定项已列明归属）
NEXT_ACTION: 修复 High/Medium 后重新验证并复审
```
