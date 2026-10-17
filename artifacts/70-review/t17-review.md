# T-17 应用壳 / 导航 / 组合根 / 权限 / 资源独立评审（CQG-T17 + IG-3 预检）

- **Artifact ID**: REVIEW-T17
- **Producer**: agent:quality-reviewer
- **Type**: Independent Code Review（Code + Architecture/Security/Integration 预检）
- **Status**: **CHANGES_REQUIRED（3 个阻断项）**
- **Date**: 2026-10-18
- **Task**: `wp-069-review-t17`（task 分支 `task/wp-067-ui-shell`，父分支 `feat/yaocore-app`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`（CQG-T17 前；IG-3 预检）
- **Reviewed revision**: `eda508381c96c5412fdf107b5aaae2df5cbeda85`（实现 `9422e37` + 编译修复 `eda5083`；diff `50f0443..eda5083`，59 路径 = 47 + 12）
- **Review snapshot**: `refs/swe/snapshots/20261017T165616Z-wp-069-review-t17-35ad7b47`（commit `2f000128f61d8021ad8ad2984abd6e799359c36b`）
- **Independence**: 本评审由未参与 T-17/T-17 编译修复实现、测试或报告编写的 `quality-reviewer` 执行。评审期间未修改任何被审产品代码、测试、证据或两份实现报告；唯一仓库写入为本报告。构建只在 ignored 的 `entry/build/**`、`.hvigor/**` 等目录产生输出；临时日志与探针位于 `/tmp/opencode`。

> **结论先行**：五项命令独立复验全部通过——`run-host-tests.sh` **639/639**、`codelinter` **0 error / 15 warning**、`hvigorw clean assembleHap` **BUILD SUCCESSFUL**、ohosTest 仅编译 **BUILD SUCCESSFUL**、`check_i18n --strict-ui` **0 blocking**（带 allowlist 10 warnings / 不带 61 warnings）。五文件编译修复经反向 patch 校验与实际构建确认，属于类型层/等价委托修改，无语义变化；生产 HAP 中未出现 `Mock*` 类，权限声明确为 INTERNET + ACCESS_BLUETOOTH，`backup_config` 已关闭，资源键 parity 成立。
>
> 但本评审发现 **3 个阻断项**：**(F-01)** `Index` 的 `@Entry` 没有使用 ability 通过 `loadContent` 传入的 LocalStorage，`@LocalStorageProp('bootstrap')` 取不到组合根，启动必然回退到 `StartupErrorView`；**(F-02)** `NO_PROFILE` 状态没有创建/加入家庭入口，而 `FamilyManagePage` 只在 UNLOCKED 后的 Navigation 内可达，首次安装无法完成 onboarding；**(F-03)** `PermissionGate` 使用 API 20 的 `getSelfPermissionStatus`，在兼容基线 API 14–19 上的回退把“未请求”映射为 DENIED，`ensure()` 因此不会调用 `requestPermissionsFromUser`，BLE 配网权限不会被请求。另有 SessionGate 档案重载、路由参数校验、EntryAbility 全屏/安全区、C-24/C-25 交付范围等 Medium/Low 问题。**本轮不能给出 PASS；CQG-T17 应记为 CHANGES_REQUIRED，IG-3 预检为 NOT READY。**

---

## 1. 范围、revision 与输入完整性

### 1.1 评审范围

```text
entry/src/main/ets/app/                 # 组合根/AppContext/导航/权限/模板
entry/src/main/ets/entryability/        # EntryAbility
entry/src/main/ets/pages/               # Index/MainShell/占位页/ShellViews
entry/src/main/resources/               # string/color/rawfile/backup
entry/src/main/module.json5             # 权限/模块配置
entry/src/main/ets/common/              # Base64Url 编译修复
entry/src/main/ets/service/             # BLE/Cloud 五文件编译修复
entry/src/test/                         # host 测试、i18n 检查器、证据
artifacts/50-implementation/t17-ui-shell.md          # 实现报告（只读）
artifacts/50-implementation/t17-compile-fix-report.md# 修复报告（只读）
```

- 实际被审变更为 `50f0443..eda5083` 的 **59 个路径**：`9422e37` **47 路径**（壳/组合根/权限/资源/host 测试/实现报告与补丁）+ `eda5083` **12 路径**（五文件修复、证据、修复报告）。
- 交叉读取但未修改：DES-B §2.4/§2.8/§8.1.4/§8.3.1/§12/§13/§17、DES-A 端口/错误/时钟、`contract-baseline.md`、`project-constraints.md`（PL-02/CP-01/SC-11/SC-07）、`i18n-resource-design.md`、`test-plan.md`、UIUX §2/§3/§5、`delivery-plan.md`、`input/design/UI_UX_Specification.md`。
- 明确排除：真实设备/模拟器运行、真实 BLE/LAN/云、UI 视觉/动效/时序、T-18 完整页面与 C-24 组件、T-19 全量执行、T-20 安全评审、Stage Gate/User Acceptance。上述保持 `BLOCKED` / `UNAVAILABLE`，本报告不将其写成 PASS。

### 1.2 输入 pin 与快照

handoff 的 9 个 `inputs` SHA-256 **9/9 一致**；`config/git-policy.json` SHA-256（`3b8ddffd4494…`）与 handoff 一致；HEAD = `eda5083`，base commit 与 handoff 一致；snapshot 覆盖 `review_targets` 及占位报告。`begin` 复核输出全部输入 `OK`；任务已处于 active 状态（重复 begin 被正确拒绝），未重新 pin 或改写输入。

| 输入 | SHA-256 前 12 位 | 结果 |
|---|---|---|
| `artifacts/50-implementation/t17-ui-shell.md` | `5ed8035de0d6` | 一致 |
| `artifacts/50-implementation/t17-compile-fix-report.md` | `e37358d84f17` | 一致 |
| `artifacts/40-detailed-design/des-001b-domain-presentation.md` | `42e6912806e3` | 一致 |
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `3a02ecbf266b` | 一致 |
| `artifacts/20-architecture/contract-baseline.md` | `883e09bb34ea` | 一致 |
| `artifacts/20-architecture/project-constraints.md` | `283046210e68` | 一致 |
| `artifacts/20-architecture/i18n-resource-design.md` | `3fa7f3881cda` | 一致 |
| `artifacts/60-testing/test-plan.md` | `33485cc39abd` | 一致 |
| `input/design/UI_UX_Specification.md` | `11bd1399240c` | 一致 |
| `config/git-policy.json` | `3b8ddffd4494` | 一致 |

### 1.3 本评审实际复验（cwd = 仓库根）

| 命令 | 结果 | 说明 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS：639 tests / 639 pass / 0 fail / 0 skipped / 0 todo，exit 0** | 与 `entry/src/test/evidence/t17-host-node-tests.tap` 及修复证据 639/639 一致；T-17 新增 26 条（`AppShell.test.mjs`），基线 613 条无删除 |
| `codelinter -c code-linter.json5 -p default .` | **PASS：Errors 0 / Warns 15 / Suggestions 0，exit 0** | 与两份 codelinter 证据一致；仅覆盖产品源码（测试源码被 `code-linter.json5` 忽略） |
| `hvigorw clean assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL in 11 s 627 ms，exit 0**（35 tasks；34 executed / 1 up-to-date） | 生产 HAP：`entry/build/default/outputs/default/entry-default-unsigned.hap`；含 `@Entry` / `fill` / `getContext` 警告，见 F-01/F-06/F-10 |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL in 9 s 923 ms，exit 0** | 仅编译证据，**不是设备执行**；`onDeviceTest` 仍 BLOCKED（D-019） |
| `check_i18n.py --root . --strict-ui`（带 `--allowlist`） | **PASS：0 blocking / 10 warnings / missingKeys=0 / hardcoded=10，exit 0** | 与 `t17-i18n-checker.log`、修复证据逐项一致 |
| `check_i18n.py --root . --strict-ui`（不带 allowlist） | **PASS：0 blocking / 61 warnings / missingKeys=0，exit 0** | 额外 51 条均为已登记前缀键 unused-key warning；满足 handoff 的 0 blocking 要求 |
| 独立资源 parity 脚本 | **PASS** | rawfile 归一化后 217/217；base/en_US strings 53/53；base/dark colors 20/20；`brand.*` 4 键与 `settings.cloud.single_gateway_required` 均存在 |
| 生产 HAP 内容检查 | **PASS（Mock 排除）** | `entry-default-unsigned.hap` 内 `modules.abc` 对 `MockGatewayService` / `MockBleProvisioningClient` / `MockScenario` 均为 0 命中；仅 `DEV_SIMULATOR_ONLY` 1 处（C-17 拒收常量，SC-11 allowlist 范围） |
| HAP 配置检查 | **PASS** | `module.json` 仅 INTERNET + ACCESS_BLUETOOTH；`backup_config.json` = `allowToBackupRestore:false`；`main_pages.json` 仅 `pages/Index` |
| 补丁等价性 | **PASS** | `git apply --reverse --check artifacts/50-implementation/t17-c28-compile-fix.patch` 成功；5 文件/42+/19− 与 `eda5083` 一致；补丁内容与当前树一致，无 fuzz/reject |
| `git status --short` / `git diff --cached --check` | **PASS** | 复验前后工作树 clean；仅 ignored 构建缓存；报告提交前 staged check 通过 |

### 1.4 测试计数与覆盖边界

- `AppShell.test.mjs` 共 **26 条** `T17_*` 用例，真实执行；覆盖 AppContext 会话门/前后台顺序/重试、NavigationService 路由与 Tab、CompositionPlan/AssemblyTrace、ActiveCloudScope 0/1/多网关 fail-closed、PermissionPolicy 纯决策、ContinuousGestureGuard、资源键、module.json5 权限、组合根 Mock 静态边界。
- 这些 host 用例是有效的**纯逻辑**证据，但不能证明 ArkUI 页面/EntryAbility/LocalStorage 绑定/权限平台调用；没有设备/Previewer UI smoke。设备骨架保持 `BLOCKED`，本报告不把 ohosTest 编译写成设备 PASS。
- 具体覆盖缺口见 F-01（boot LocalStorage）、F-02/F-04（SessionGate UI）、F-03（API 14 权限回退）、F-05（路由校验未接线）、F-12（静态 Mock 扫描范围）。

---

## 2. Findings

严重度定义：**High** = 阻断 CQG-T17 或导致核心启动/安全/兼容语义错误；**Medium** = 契约/状态/交付缺口，需在本轮或书面裁定后关闭；**Low** = 文档、测试、可观测性或已登记残余。`U-*` 为上游/架构项，不计入本轮代码阻断条件，但必须在 IG-3/T-18 前闭环。

| ID | 严重度 | 位置 | 契约/依据 | 问题/影响 | 建议 |
|---|---|---|---|---|---|
| **F-01** | **High（阻断）** | `pages/Index.ets:23-26`；`entryability/EntryAbility.ets:115-118`；构建日志 `t17-clean-assemble.log:271`、`t17-compile-fix/clean-assemble.log:268` | DES-B §17.1.4/§17.1.5；ArkUI `@Entry` EntryOptions（`storage` 未传时框架新建 LocalStorage；`useSharedStorage` 默认 false） | `Index` 用 `@Entry`（无参数）加 `@LocalStorageProp('bootstrap')`；`EntryAbility` 虽把 `ShellBootstrap` 写入 `new LocalStorage()` 并 `loadContent('pages/Index', storage)`，页面默认不会使用该共享实例。`bootstrap` 因此取默认 `new ShellBootstrap()`（无 appContext） → Index 显示 `startupError INTERNAL_ERROR`，重试无效，应用无法进入 Tabs。构建已明确警告 `'@Entry' should have a parameter...`，但报告未按正确性处理。 | 改为 `@Entry({ useSharedStorage: true })`（API 12+，兼容 14）或显式传入页面 storage；保留 `loadContent` 的 storage；在 T-18/T-19 增加启动 smoke（Previewer/真机），断言 `bootstrap.appContext` 非空；修复后重跑构建/评审。 |
| **F-02** | **High（阻断）** | `pages/ShellViews.ets:44-52`；`pages/ShellViews.ets:107-122`；`pages/MainShell.ets:89-148` | DES-B §17.1.5（NO_PROFILE → 创建/加入家庭入口）、§17.3、§17.1.3 | `NO_PROFILE` 分支只显示标题/说明；没有创建家庭/加入家庭按钮或流程。`FamilyManagePage`/`Navigation` 只在 UNLOCKED 后的 MainShell 内渲染，SessionGateView 在 Navigation 之外，因此首次安装无法到达任何创建/加入页面，应用不可用。T-18 写范围也不含 `ShellViews.ets`。 | 在 SessionGateView 提供创建/加入入口（或在 gate 外层提供 onboarding 流程），使其能在 UNLOCKED 前到达 C-22 创建/加入能力；不渲染旧家庭/业务数据；补 UI smoke/人工步骤。若 T-18 承接，需先扩围 `pages/ShellViews.ets`。 |
| **F-03** | **High（阻断，兼容性）** | `app/PermissionGate.ets:69-92`、`:38-54`；`build-profile.json5:10`；SDK `@ohos.abilityAccessCtrl.d.ts:561` | PL-02/CP-01（HarmonyOS NEXT API 14+；compatibleSdk 5.0.2(14)）；DES-B §17.1.6/§17.2 | `getSelfPermissionStatus` 标注 `@since 20`；API 14–19 上调用失败后回退 `checkAccessTokenSync`，该 API 只能返回 granted/denied，无法返回 NOT_DETERMINED。`ensure()` 看到 DENIED 就 `return resultFor(DENIED)`，不会调用 `requestPermissionsFromUser`；BLUETOOTH 运行时授权在兼容基线上实际不会发起，配网流程被阻断或只能依赖用户手动进设置。 | 在 API 14–19 上采用可请求的路径（动作入口调用一次 `requestPermissionsFromUser`，用本地 flag 防止循环；或按 API 能力分支）；/或明确把最低系统提高到 API 20 并更新 CP-01/compatibleSdk。补 API 级别/设备验证。 |
| **F-04** | **Medium** | `pages/ShellViews.ets:32-36`、`:125-136`；`pages/Index.ets:134-140` | DES-B §17.1.5（SessionGate 显示/解锁）；C-28 SEAM | `SessionGateView` 只在 `aboutToAppear` 加载档案；`gate` 从 NO_PROFILE→LOCKED（onboarding 完成/家庭切换）时组件仍处于同一个 `else if` 分支，`@Prop gate` 更新但不会重新执行 `loadProfiles()`。`profiles` 可能为空或残留旧家庭档案，解锁按钮不可用/解锁错误档案；家庭切换后同样。 | 对 `gate`/`activeFamilyId` 加 `@Watch`（或 `onDidBuild`）重新加载并重置 `selectedProfileId`；加载失败显示错误/重试；补 UI 测试。 |
| **F-05** | **Medium** | `app/NavigationService.ets:132-148`、`:170-190`；`pages/MainShell.ets:67-87` | DES-B §17.1.1（路由/参数固定）、§17.2（参数缺失 → ErrorState/返回） | `AppRouteValidation.accepts()` 只在 host 测试中被调用；`push()`/`replace()` 和 `routeBuilder` 均未调用。DeviceControl 缺 `gatewayId`/`deviceId`、Provisioning 非法 `mode` 仍会构造占位页，而不是 ErrorState；T-18 的调用方一旦传参错误不会被拦截。 | 在 `push/replace` 或 routeBuilder 入口调用 `accepts()`；不接受时渲染 `UnknownRouteView`/参数错误态；补缺失/非法参数测试。 |
| **F-06** | **Medium** | `entryability/EntryAbility.ets:75-83` | DES-B §17.1.4/§17.3、UIUX §2.1（428×872、安全区/手势条） | `onWindowStageCreate` 只保存 windowStage 并 loadContent；未调用 `setWindowLayoutFullScreen`、系统栏/避让区或安全区设置，壳层可能显示在系统栏下/达不到设计视口与手势条要求。 | 按当前 SDK 设置全屏、系统栏和 avoid area；在 Previewer/真机上验证安全区；把窗口配置写入 C-28 测试/评审证据。 |
| **F-07** | **Medium（范围/计划）** | `artifacts/30-plan/delivery-plan.md:437-446`、`:453`；`artifacts/50-implementation/t17-ui-shell.md:30-33`、`:168-175`；`pages/HomePage.ets:1-2`、`pages/RoomsPage.ets:1-2`、`pages/DeviceControlPage.ets:1-2` | T-17 DoD（C-24/C-25/C-28）；T-18 写范围；component-graph §3.2 | 交付计划把 C-24 设计系统、Home/Rooms/DeviceControl（C-25）列入 T-17；实现交付的是占位页和仅壳层 `ShellTheme`，并把 C-25 注释为 T-18 替换。T-18 计划写范围只列 Family/RoomManage/Scene/Provisioning/Settings/About/Profile，**不包含 Home/Rooms/DeviceControl**；C-24 组件也未被 T-18 覆盖。若按 CQG-T17 DoD 评判，C-24/C-25 未完成；若 Orchestrator 已把 T-17 重定义为“壳层”，则该重定义未写入决策/计划，T-18 范围也未相应扩围。 | Orchestrator 明确记录重定义：T-17 壳层验收 + T-18 必须扩围承接 C-24/C-25（Home/Rooms/DeviceControl、components、common/theme）；或在本轮补齐 C-24/C-25。CQG 不得把 C-24/C-25 写成已完成。 |
| **F-08** | **Low** | `app/AppCompositionRoot.ets:513-538` | DES-B §17.1.2（`dispose()` 清空会话/草稿） | `dispose()` 停止轮询、取消 BLE、清空草稿、关闭存储，但没有调用 `authService.lockAll()`，没有明确清空会话/会话门；与 API 文字“清空会话”不完全一致。root 是按 Ability 实例，GC 后影响有限，但退出/测试路径语义不完整。 | 在释放前 best-effort `await authService.lockAll()` 并清空/重置会话门；补 dispose 测试或明确记录这是有意例外。 |
| **F-09** | **Low** | `app/AppCompositionRoot.ets:202-208`；`app/CompositionPlan.ets:19-24`；`t17-ui-shell.md` §5 | DES-B §2.4 装配顺序 | `CryptoService` 在 PLATFORM（第 1 步）构造，而 §2.4 把它列在第 5 步（StorageService 之后）；`CompositionPlan` 的“可执行顺序契约”与 §2.4 不完全一致。报告 §5 只记录了 SceneService 的顺序偏差，未记录这一项。功能上 CryptoService 不依赖存储，但作为顺序契约应记录。 | 在 `CompositionPlan`/实现报告记录该依赖驱动的顺序偏差，或按 §2.4 调整构造顺序（并说明 CryptoRandomSource 依赖）。 |
| **F-10** | **Low** | `pages/MainShell.ets:54`；`pages/ShellBackdrop.ets:22,29,36,43` | CP-01 API 14；构建兼容性 warning | `fill` 的 Resource 重载在构建中标注 SDK 26 起支持，当前 compatibleSdk 为 5.0.2(14)；API 14–25 上可能不渲染/忽略或产生兼容性问题。T-17 证据已出现 5 条 warning，修复报告将其列为 Low 残余，未在 T-17 主报告登记。 | 使用 API 14 可用的颜色/fill 写法，或 `apiAvailable`/`canIUse` 分支；若实际只支持 API 26，应更新 CP-01/compatibleSdk 并记录；在设备/Previewer 验证。 |
| **F-11** | **Low（文档/追溯）** | `artifacts/50-implementation/t17-ui-shell.md:7,11,119,151`；`artifacts/50-implementation/t17-compile-fix-report.md:93` | Artifact Validation/证据一致性 | T-17 实现报告仍为 `BLOCKED`，§2/§3 仍写 HAP FAIL；修复报告已 COMPLETE 并给出修复证据。当前 revision 构建成功，但读者/Gate 会看到互相矛盾的最终状态；修复报告只说“可更新”，主报告未更新。 | 在提交 CQG 前更新主报告 Status/§3/§7 指向 `eda5083` 和最终证据，或由 Orchestrator 记录 supersession；不要保留两个最终状态。 |
| **F-12** | **Low（测试/SC-11）** | `entry/src/test/host/AppShell.test.mjs:554-563`；仓库无 `check_production_mock_exclusion.py` | DES-B §17.1.7/§17.4、SC-11 | 静态 Mock/DEV-ONLY 测试只遍历 `entry/src/main/ets/app/`，未覆盖 `entryability/`、`pages/`、`service/` 等生产路径；`check_production_mock_exclusion.py` 在仓库中不存在。实际人工 grep 与生产 HAP 检查未发现 Mock，当前编译产物干净，但自动守卫不足以证明“生产路径永不引入 Mock”。 | 将静态检查扩展到全部生产 import 图（或补齐 C-29 检查器）并检查 HAP 内容；保留本次人工/HAP 证据；在 T-20/C-29 关闭。 |
| **F-13** | **Low（会话一致性）** | `app/AppContext.ets:172-180`、`:134-160` | DES-B §17.1.3；C-22 `needsUnlock` 不变量 | `AppContext.setActiveFamily()` 只写 active family + `refreshSessionGate()`；`refreshSessionGate` 只判断“有档案 + 有会话”，不校验 `session.familyId === activeFamilyId`。如果未来页面直接调用 `setActiveFamily` 切换家庭而旧会话仍在，gate 可能保持 UNLOCKED。当前 C-22 走 `FamilyService.switchFamily`（内部 `auth.lockAll()`），未发现可达路径；但 C-28 公开 API 自身不满足该不变量。 | 让 `setActiveFamily` 先 `lockAll()`（或 refresh 时比较 session.familyId），并补会话/家庭不匹配测试；或明确禁止直接使用该 API。 |
| **U-01** | **Low（上游/架构）** | `app/AppCompositionRoot.ets:69-79`；`app/PermissionGate.ets:22-27`；`pages/Index.ets:16-18` | DES-B §2.3 D-12/D-17；§17.1.2/§17.1.6 | D-17 写“app 可依赖 service/repository/contracts/common”，但 §17.1.2 要求组合根构造 ViewModel 工厂，当前 `AppCompositionRoot` import viewmodel；`PermissionGate` 为适配 C-23 也 import `viewmodel/ViewModelPorts`。D-12 的 pages allowlist 未含 `app/ShellTheme.ets`/`app/ShellBootstrap.ets`，但 Index/MainShell 使用了它们。实现选择可由 §17.1.2/§17.1.6 解释，但与 D-12/D-17 文字冲突；若 IG-3 启用 layering checker 会报错。另：§17.1.5 要求 Index 用 `@Provide('appContext'/'i18n'/'navigation')` 向子树提供实例，当前 Index 仅持有实例并用显式 props 传递；实施报告 §5.2 的“T-18 可在页面内改为 @Consume（Index 已提供实例）”措辞不准确——Index 没有 `@Provide`，T-18 若改用 `@Consume` 必须先补 `@Provide`。 | `solution-architect` 在 T-18/IG-3 前裁定并更新 D-12/D-17（允许 app→viewmodel 工厂、补充 ShellTheme/ShellBootstrap 或迁移到 common/theme/app seam），并明确 `@Provide`/显式 props 的最终 DI 契约；不要在评审中静默放宽分层规则。 |

### 2.1 F-01 阻断展开：`@Entry` 与 ability LocalStorage

```text
Index.ets:23-26
  @Entry
  @Component
  struct Index {
    @LocalStorageProp('bootstrap') bootstrap: ShellBootstrap = new ShellBootstrap();

EntryAbility.ets:115-118
  const storage = new LocalStorage();
  storage.setOrCreate('bootstrap', new ShellBootstrap(this.appContext, this.bootstrapError));
  windowStage.loadContent('pages/Index', storage, callback);
```

- OpenHarmony ArkUI `@Entry` 的 EntryOptions 明确：`storage` 未传入时框架创建新的 LocalStorage 实例作为默认值；`useSharedStorage` 默认 false，true 才使用 `loadContent` 传入的实例。
- 当前 `@Entry` 没有参数，因此页面不会绑定 `EntryAbility` 的 storage；`@LocalStorageProp('bootstrap')` 回退到页面的默认值 `new ShellBootstrap()`，`appContext` 为 undefined。`Index.aboutToAppear` 随即把 `startupError` 置 `INTERNAL_ERROR`（`Index.ets:41-47`），`retry()` 因 appContext 为 undefined 直接返回，用户只能看到启动错误页。
- 构建日志在修复前/后都产生 `'@Entry' should have a parameter, like '@Entry (storage)'`（`t17-clean-assemble.log:271`、`t17-compile-fix/clean-assemble.log:268`）。这不是普通 style warning，而是页面 LocalStorage 未接线的直接信号。
- 契约依据：DES-B §17.1.4 要求“创建 ability 级 LocalStorage，写入 appContext；`windowStage.loadContent('pages/Index', storage)`”；§17.1.5 要求 Index 通过 `@LocalStorageProp('appContext')` 取得实例。当前 key 使用 `bootstrap` 包装对象在语义上可解释（同时携带 startupError），但键名与契约不同，且未在实施报告偏差项中记录；应在修复时统一为 `appContext`（另加 `startupError` 键）或在报告/契约中显式记录该 wrapper 偏差。
- 修复：`@Entry({ useSharedStorage: true })`（API 12+，兼容 API 14）或等价显式 storage 传参。修复后需要 Previewer/真机启动 smoke，断言 `bootstrap.appContext` 非空、Index 能进入 SessionGate/MainShell；host 测试无法覆盖此缺陷。

### 2.2 F-02 / F-04 展开：SessionGate 首次使用与重载

- `SessionGateView` 的 `NO_PROFILE` 分支只有文本（`ShellViews.ets:44-52`），没有“创建家庭/加入家庭”按钮。`MainShell` 的 `Navigation` 包含 `FamilyManagePage`，但 MainShell 只在 `sessionGate === UNLOCKED` 时渲染（`Index.ets:134-148`）；SessionGateView 位于 Navigation 之外。因此 fresh install 无任何路径进入创建/加入流程。DES-B §17.1.5 明确 `NO_PROFILE -> 创建家庭/加入家庭入口`。
- 即使补上入口，`SessionGateView` 只在 `aboutToAppear` 中、且 `gate === LOCKED` 时调用 `loadProfiles()`（`ShellViews.ets:32-36`）。No profile → 创建家庭/档案 → gate 变为 LOCKED 时，组件仍处于同一个 `else if` 分支，`aboutToAppear` 不会再次执行；`profiles` 不会被加载，用户看不到档案/无法解锁。家庭切换后同理。
- 建议：`@Watch('gate')`/`@Watch('familyName')` 或在 `onDidBuild` 中按当前 gate 重新加载，并重置 `selectedProfileId`/密码/错误；加载失败显示可重试错误。T-18 若承接 onboarding，需先扩围 `pages/ShellViews.ets`，并把上述测试写入 UI smoke。

### 2.3 F-03 阻断展开：API 14 权限回退

```text
PermissionGate.check():                                  // :69-92
  try {
    return stateFromSelfStatus(manager.getSelfPermissionStatus(permission));
  } catch {
    const tokenId = bundleManager.getBundleInfoForSelfSync(0).appInfo.accessTokenId;
    const granted = manager.checkAccessTokenSync(tokenId, permission) === GRANTED;
    return granted ? GRANTED : DENIED;
  }

PermissionGate.ensure():                                 // :38-54
  const current = await this.check(kind);
  if (current !== NOT_DETERMINED) {
    return PermissionPolicy.resultFor(kind, current);    // DENIED -> 直接返回，不发请求
  }
  ... requestPermissionsFromUser ...
```

- SDK `@ohos.abilityAccessCtrl.d.ts` 标注 `getSelfPermissionStatus` `@since 20`；`build-profile.json5` 的 `compatibleSdkVersion` 为 `5.0.2(14)`，project-constraints PL-02/CP-01 要求兼容 API 14+。
- 在 API 14–19 上 `getSelfPermissionStatus` 不存在/抛错，进入 `checkAccessTokenSync` 回退；该 API 只返回 granted/denied，无法表达 NOT_DETERMINED。`ensure()` 把 DENIED 当作最终状态，不会调用 `requestPermissionsFromUser`，因此 BLUETOOTH 的运行时授权不会被发起。
- 这违反 DES-B §17.1.6（“运行时申请；拒绝则配网阻断”）以及 T-17 报告 §1.3 对“BLUETOOTH check/request”的声明。用户可能只能手动进设置开启，且 `openSettings()` 的具体 action 也未在设备上验证。
- 建议：按 API 能力分支；在 API < 20 的动作入口调用一次 `requestPermissionsFromUser`（用动作级/一次性 flag 防循环），并在返回 DENIED 后给“去设置”；或在项目层面把最低 API 提升到 20 并同步更新 CP-01、compatibleSdk 和测试矩阵。不要用“targetSdk 26”掩盖 compatibleSdk 14 的 Must 约束。

---

## 3. 契约逐项核对（评审重点 1–7）

| # | 评审重点 | 结论 | 说明 |
|---|---|---|---|
| 1 | 组合根：构造注入、无全局单例/服务定位、CloudActiveScope/Clock 注入与 fail-closed、DomainOperationGate 共享、AuthService/InviteService 接线、Mock 生产排除 | **基本符合（有非阻断项）** | `AppCompositionRoot` 私有构造 + 静态工厂，无全局单例/服务定位；所有依赖构造注入；`ActiveCloudScope` 作为 `CloudActiveScopePort` 注入 `CloudCommandClient`，`ClockPort` 注入 cloud store/client/service/evaluator/credentials；`assertActiveGateway` 在 seq/secret/sign/HTTP 前执行，0/多网关 fail-closed；`DomainOperationGate(2000ms)` 在 C-08..C-11 间共享；`registerMigrations`/`InviteService` 接线存在。生产 HAP 无 `Mock*`；仅 `DEV_SIMULATOR_ONLY` 拒收常量。F-08（dispose 未清会话）、F-09（Crypto 顺序未记录）、F-12（静态检查范围）为剩余项。 |
| 2 | 权限：仅 INTERNET + ACCESS_BLUETOOTH；无猜测权限；backup 合理 | **声明符合；运行时请求部分不符合** | `module.json5` 仅两条；`PermissionPolicy` 未声明 CAMERA/LOCATION；`backup_config` false。F-03 是 API 14–19 的实际请求缺陷；`openSettings` action、BLE 扫描是否需 APPROXIMATELY_LOCATION 仍无设备证据。 |
| 3 | 壳/导航：Tabs+Navigation、SessionGate/PermissionGate、占位页策略、R3-02 | **部分符合** | `Index` 唯一 `@Entry`；Tabs + Navigation/NavDestination 结构、未知路由 ErrorState、`onBackPress` 消费语义成立；`NavigationService` 纯路由；PermissionGate 声明策略正确。F-01 启动绑定、F-02 NO_PROFILE 入口、F-04 SessionGate 重载、F-05 路由校验未接线、F-06 窗口设置、F-07 占位/C-25 范围是缺口。`ContinuousGestureGuard` 逻辑正确且 host 测试覆盖 cancel→TouchUp，但当前没有页面使用它；T-18 滑杆必须显式接线。 |
| 4 | 资源/i18n：`brand.*`/`settings.cloud.single_gateway_required`、parity、checker、动态键 | **符合** | rawfile 归一化 217/217；string 53/53；color 20/20；4 个 `brand.*` 与 single-gateway 键均存在；`check_i18n --strict-ui` 0 blocking；10 warnings 全部来自既有 C-16/C-20 文件；`brand.*` 4 键有 allowlist 理由（F-05 固定映射，不是动态 t() 调用点）；未发现新增硬编码 UI 文案。 |
| 5 | 五文件编译修复：等价性/无语义变化、生产 HAP 可复现、不掩盖真实错误 | **符合** | 补丁反向校验成功；`Base64Url` 仅补 `AppError` 导入；`DelegatingScanListener` 是按原顺序转发三回调的名义类，等价于原对象字面量；`throw error as Error`/reject 参数 `AppError` 仅为类型层收窄，运行时对象不变；未使用忽略/抑制指令；clean assemble 生产图成功，HAP 可复现。 |
| 6 | 测试质量：26 新壳层用例、639/639、设备骨架诚实 | **基本符合（覆盖边界已声明）** | 26 条 `T17_*` 真实执行；覆盖纯逻辑/静态边界；`ohosTest` 仅编译，未写设备 PASS；设备骨架保持 `BLOCKED_ON_DEVICE_RUNNER`。但 LocalStorage 启动、SessionGate UI、API 14 权限回退、路由校验、静态 Mock 全生产路径均无自动测试；F-01/F-02/F-03 的 PASS 不能从 host 测试推出。 |
| 7 | 过程：47+12 路径、两步提交、证据一致、无秘密/构建产物 | **符合** | 47 + 12 路径与 handoff 一致；commit subjects `feat(shell): …`、`fix(build): …` 符合默认 policy（≤72、无句号）；`git diff` 无 HAP/bin/密钥/证书/构建目录；证据日志与本次复验一致（时间/大小差异属正常）；工作树 clean。 |

---

## 4. IG-3 预检意见

**预检结论：NOT READY（不通过）。** 本次评审只覆盖 T-17 壳层与五文件修复，IG-3（G-012，UI+VM 集成）在当前 revision 上不满足预检条件：

1. **T-17 本身未 PASS**：F-01 使启动不可用，F-02/F-04 使首次使用/解锁流程不完整，F-03 使 API 14 配网权限请求失效。IG-3 不能在 CQG-T17 `CHANGES_REQUIRED` 的组件上开始集成验收。
2. **T-18 未交付**：C-26/C-27 页面、配网 6 步、设置/云 UI、Profile 等尚不存在；C-24 完整组件与 C-25 Home/Rooms/DeviceControl 仍为占位，F-07 还暴露 T-18 写范围不覆盖这些页面。
3. **集成证据缺失**：没有设备/Previewer UI smoke（导航、SessionGate、权限拒绝、设置/云、Mock 排除），没有 T-18 页面数据流、i18n 切换、RBAC 可见性与真实/模拟 BLE/LAN/云集成证据；`onDeviceTest` 仍 BLOCKED。
4. **IG-3 前置**：必须在 F-01/F-02/F-03（以及 F-04/F-05/F-06 的修复或书面裁定）完成后，重新运行 host/codelinter/clean assemble/ohosTest/i18n，并在 T-18 完成后执行 IG-3 的 Contract 校验、集成测试与回归。本报告不是 IG-3 的 Gate 决定。

预检中已可确认的部分：组合根构造/依赖注入、CloudActiveScope/ClockPort fail-closed、DomainOperationGate 共享、权限声明/备份、资源 parity、生产 HAP Mock 排除、五文件修复均为正面证据；但不足以让 IG-3 通过。

---

## 5. 残余风险与跟踪

| 跟踪项 | 风险/内容 | 归属/时机 |
|---|---|---|
| **F-01 启动 LocalStorage** | 当前 revision 预期启动进入 StartupError；需 Previewer/真机 smoke 证明修复 | implementation-engineer + T-19 UI smoke；CQG-T17 前 |
| **F-02/F-04 SessionGate onboarding** | NO_PROFILE 入口、档案重载、家庭切换/解锁；需 UI 测试 | T-17 修复或 T-18 扩围 `ShellViews.ets`；CQG-T17 前 |
| **F-03 API 14 权限** | API 14–19 的 BLUETOOTH 请求路径；`openSettings` action；BLE 扫描 location 需求 | implementation-engineer + T-19 设备/API 矩阵；CQG-T17 前 |
| **F-05 路由校验** | DeviceControl/Provisioning 缺参/非法参；T-18 调用方 | T-17/T-18 页面联调；CQG-T17 前 |
| **F-06 窗口全屏/安全区** | 428×872、状态栏/手势条/避让区；设备视觉 | T-18/T-19；CQG-T17 前或书面裁定 |
| **F-07 C-24/C-25 范围** | Home/Rooms/DeviceControl、components、common/theme 未交付；T-18 写范围不覆盖 | Orchestrator/T-18；CQG-T17 与 IG-3 前明确重定义 |
| **F-08 dispose 会话** | 退出/测试路径未清会话；root GC 降低影响 | 维护轮/T-18；不作为本轮阻断 |
| **F-09 装配顺序** | CryptoService 在 PLATFORM 而非 §2.4 第 5 步；报告未记录 | 维护轮/T-18；更新 CompositionPlan/报告 |
| **F-10 fill API 26 vs API 14** | 光影/底座可能降级或运行时不兼容 | T-18/T-19 设备验证；或更新 compatibleSdk/CP-01 |
| **F-11 报告状态** | 主报告 BLOCKED 与修复报告 COMPLETE 并存 | implementation-engineer/Orchestrator；CQG 前 |
| **F-12 静态 Mock 守卫** | 只扫 app/；`check_production_mock_exclusion.py` 不存在；本次人工/HAP 证据 clean | C-29/T-20；IG-3 前补检查器 |
| **F-13 setActiveFamily 会话一致性** | 直接调用可能保留旧家庭会话；当前 C-22 路径会 lockAll | T-18/维护轮；补不变量测试 |
| **U-01 D-12/D-17** | app→viewmodel 与 pages import ShellTheme/ShellBootstrap 的文字冲突 | solution-architect；IG-3 前裁定 |
| **真实设备/UI/BLE/LAN/云** | 无设备/模拟器；ohosTest 仅编译；D-019 | T-19 设备矩阵、T-20 安全评审；本报告不授予设备 PASS |
| **i18n 既有 warning** | 10 条来自 C-16/C-20 既有硬编码；`brand.*` 仍为 C-16 动态映射 + allowlist | C-16/T-18/维护轮；不是 T-17 新增 |
| **HAP 未签名 / 构建警告** | 未配置 signingConfigs；`@Entry`、`fill`、`getContext` 警告；构建仅 SDK 26 | T-18/T-19/发布阶段；`@Entry` 已升级为 F-01 |

---

## 6. Verdict 与后续

**Verdict: `CHANGES_REQUIRED`（不是 PASS）。**

- **CQG-T17**：F-01/F-02/F-03 为阻断项；F-04/F-05 为 onboarding/路由的必需修复；F-06/F-07 需在 CQG 前书面裁定或修复。C-28 壳层不能标记 `STABLE`，C-24/C-25 也不能写成已完成。
- **IG-3 预检**：`NOT READY`；T-18 未交付、T-17 未通过、UI/设备/BLE/LAN/云证据缺失。
- **复验要求**：修复后必须重跑 `run-host-tests.sh`、`codelinter`、`hvigorw clean assembleHap`、ohosTest 编译、`check_i18n --strict-ui`；新增启动/UI smoke（或如实记录 BLOCKED）；由新的独立 `quality-reviewer` 复审受影响范围。修复 F-01 后至少验证 `bootstrap.appContext` 非空与 Index 能进入 SessionGate/MainShell；修复 F-03 后至少验证 API 14–19 请求路径或更新最低 API。
- **不得声明**：CQG-T17 PASS、C-24/C-25 完成、IG-3 PASS、设备/真实 BLE/LAN/云 PASS、用户验收。

本评审的 PASS 条件不是“测试通过”，而是上述阻断项关闭且证据与 revision 重新绑定；当前测试 639/639 和构建成功不能覆盖 F-01..F-03 的运行时/兼容性语义。

---

## 7. 独立性与证据声明

- 本评审由 `quality-reviewer` 独立执行，未参与 T-17/T-17 修复的代码、测试或报告编写。
- 评审期间未修改任何被审产品代码、测试、证据或 `artifacts/50-implementation/t17-ui-shell.md` / `t17-compile-fix-report.md`；未修改 `entry/src/main/**`、`entry/src/test/**`、`entry/src/ohosTest/**` 或资源。唯一仓库写入为本报告。
- 独立复验命令均在 `/home/quirkybrain/code/harmony-projects/YaoCore` 执行；构建输出只落在 ignored 目录；未执行 `pull`/`merge`/`rebase`/`push`，未切换分支。
- 外部平台依据：OpenHarmony ArkUI `@Entry` EntryOptions（`storage`/`useSharedStorage`）文档、SDK `@ohos.abilityAccessCtrl.d.ts`（`getSelfPermissionStatus` `@since 20`）与当前 `build-profile.json5` 的 `compatibleSdkVersion 5.0.2(14)`。这些是平台 API 语义校验，不替代设备测试。
- 本报告只对 `eda5083` 的 `50f0443..eda5083` 差异范围负责；T-18 完整页面、C-24 组件、T-19 全量测试与 T-20 安全评审不在本报告结论内。
