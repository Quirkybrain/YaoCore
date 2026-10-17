# T-06 评审修复报告（R-01..R-13）

- **Artifact ID**: IMP-T06-FIX
- **Producer**: agent:implementation-engineer
- **Type**: Implementation / Verification Evidence（评审修正）
- **Status**: Proposed（修复完成；待独立复审与 CQG-T06 Gate）
- **Date**: 2026-10-17
- **Task**: `wp-014-fix-t06`（task 分支 `task/wp-012-foundation`，父分支 `feat/yaocore-app`；base commit `5eb4d67`）
- **Reviewed revision**: `4d361bdba790da686839b30ce1feffec2215b0f7`；评审报告 `artifacts/70-review/t06-review.md`（REV-T06-001，CHANGES_REQUIRED）
- **Upstream**: DES-A §3.2/§3.3/§4.1.3/§4.2/§5.1.4/§5.1.5/§6.1.3/§6.1.4/§18.5/§18.7/§18.8；DES-B §8.1.5/§8.1.6/§8.3.3；`state-report.schema.json`；CB §2/§6；TEST-001 §5/§10
- **Scope**: `entry/src/main/ets/common/`、`entry/src/main/ets/model/`、`entry/src/main/ets/service/protocol/`、`entry/src/test/`、`artifacts/50-implementation/`
- **Downstream**: 独立复审（非作者）、CQG-T06、T-07（签名/nonce）、C-10/T-19（合并/partial 语义）、T-14（云完成判定/严格 adapter）

---

## 0. 摘要

| 项 | 结果 |
|---|---|
| 评审 finding 处置 | **Fixed 12 / Deferred(Exception) 1**（R-01..R-12 Fixed；R-13 记录例外与迁移计划） |
| 新增/更新 host 用例 | 81 → **88**（+7，全部为评审负例/语义固化） |
| `ohpm install` | **PASS**（exit 0） |
| `hvigorw clean assembleHap --no-daemon` | **PASS**（BUILD SUCCESSFUL，35 tasks：34 executed / 1 up-to-date；unsigned HAP warning） |
| `codelinter -c code-linter.json5 -p default .` | **PASS**（No defects found） |
| `entry/src/test/run-host-tests.sh` | **PASS 88/88**（fail 0，约 641.1 ms） |
| Hypium host 编译（附加检查） | **COMPILED_ONLY**；`UnitTestArkTS` 6.361 s 完成，随后 `> hvigor Linux` 挂起，超时 124（与 T-06 基线一致，不写成 PASS） |
| 组件状态 | 保持 `UNVERIFIED`；本报告不授予 `STABLE`、Stage Gate 或用户验收 |

证据目录：`entry/src/test/evidence/t06-fix-*.log|tap`。

---

## 1. 逐条处置

| ID | 严重度 | 处置 | 变更位置 | 新增/更新测试与证据 |
|---|---|---|---|---|
| **R-01** | Medium | **Fixed**：ACK 根对象、`deviceState`、`gatewayState` 的未知字段统一抛 `ACK_PROTOCOL_VIOLATION`（单一 `rejectUnknownFields` 路径，三处一致） | `entry/src/main/ets/service/protocol/ControlAckMapper.ets`：`rejectUnknownFields` | `ProtocolAck.test.mjs`：更新根对象期望；新增 `C03_ControlAckMapper_unknownFieldsUseAckProtocolViolationInAllShapes`（deviceState/gatewayState 负例） |
| **R-02** | Medium | **Fixed**：`shouldApplyState = ackAccepted && reportedState !== undefined && !(idempotentReplay && alreadyApplied)`；gateway ACK 仅暴露 `gatewayBoardState`，不置 `shouldApplyState`。另在 `ControlOutcome.create` 增加“shouldApplyState ⇒ reportedState 存在”的不变式 | `ControlAckMapper.ets`；`entry/src/main/ets/model/ControlModels.ets` | `ProtocolAck.test.mjs`：gateway 用例改为 `shouldApplyState=false` / `reportedState=undefined`；device golden/replay 仍为 true |
| **R-03** | Medium | **Fixed**：`SET_MODE` 按请求原始值比较；`mode` 缺失 → `UNVERIFIED`，存在且不同 → `MISMATCH`，相同 → `MATCH`；不再因非 7 值词表降级。云路径“非标准值 → UNVERIFIED”保留给 DES-B/T-14 | `ControlAckMapper.ets`：`compareAction` | `ProtocolAck.test.mjs`：`C03_ControlAckMapper_nonStandardModeComparesRawValue`（TURBO≠COOL → MISMATCH；TURBO=TURBO → MATCH；缺失 → UNVERIFIED） |
| **R-04** | Low | **Fixed**：非零 `result_code` 且存在 `reported_state` 时，仍执行 oneOf/字段类型/未知字段严格校验；失败抛 `ACK_PROTOCOL_VIOLATION`。错误路径不把该值放入 `ControlOutcome` | `ControlAckMapper.ets`：`validateReportedState` | `ProtocolAck.test.mjs`：`C03_ControlAckMapper_nonZeroResultStillValidatesReportedStateSchema`（双形态、未知字段、类型错误、合法负例） |
| **R-05** | Low | **Fixed**：`Base64Url.decode('')` 抛 `SECRET_ENCODING_INVALID`；`encode(empty)` 仍返回 `''`；`isValid('')=false` | `entry/src/main/ets/common/utils/Base64Url.ets` | `Foundation.test.mjs`：`C01_Base64Url_isUnpaddedAndStrict` 更新 |
| **R-06** | Low | **Fixed**：新增 `INVITE_VERSION_UNSUPPORTED → errors.app.invite_invalid` 特例（先于通用 `INVITE_*` 分支） | `entry/src/main/ets/common/types/AppError.ets`：`i18nKeyOf` | `Foundation.test.mjs`：`C01_AppError_catalogCarriesCategoryRetryableAndI18nKey` 增加该码与 `INVITE_AEAD_FAILED` 断言 |
| **R-07** | Low | **Fixed**：`ControlRequestSerializer` 按 `DeviceConstants.actionToValueKind(action)` 校验 value 类型；NONE 带值、BOOLEAN/NUMBER/STRING/COLOR 类型不匹配 → `PROTOCOL_INVALID_TYPE`。同时修正 `actionToValueKind` 本身：`OPEN/CLOSE/ON/OFF/BOARD_LED_* → BOOLEAN`（与 DES-A §14.2.3 一致）。7 值 `SET_MODE` 词表仍由 C-11/C-16 强制，不在序列化器强制 | `entry/src/main/ets/service/protocol/ControlRequestSerializer.ets`；`entry/src/main/ets/common/constants/DeviceConstants.ets` | `ProtocolControl.test.mjs`：`C03_ControlRequestSerializer_enforcesActionValueKind`（SET_BRIGHTNESS 字符串、SET_MODE 数字、SET_COLOR 布尔、BOARD_LED_ON 数字、PING 布尔、OPEN 字符串；另确认 `'制冷'` 仍可编码）。V-01 4 向量字段顺序/值/oracle 仍通过 |
| **R-08** | Low | **Fixed（严格门）**：控制与云出站 nonce 均强制 `HEX_LOWER_32`（32 位小写 hex）。若后续认为应在签名入口强制，本序列化器也保留为最后结构门 | `ControlRequestSerializer.ets`；`entry/src/main/ets/service/protocol/CloudCommandSerializer.ets` | `ProtocolControl.test.mjs`：`C03_ControlRequestSerializer_enforcesHexLower32Nonce`（12-hex/大写/含 `-` 负例）；`ProtocolCloud.test.mjs`：`C03_CloudCommandSerializer_rejectsNonCanonicalValueAndFields` 增加 3 个非严格 nonce 负例 |
| **R-09** | Low | **Fixed（选择严格 SERVICES 解析）**：强制 schema 的 7 个 required 固定属性；properties 按 schema 全量 allowlist 拒绝未知属性；顶层仅允许 `services`；required 布尔与 `Gateway_RSSI` 类型/范围严格校验。SHADOW/DEVICES 形态保持 T-06 的 partial 容忍；`DeviceInventoryJson` 内部结构仍由 T-14/PB-02 接管 | `entry/src/main/ets/service/protocol/StateReportMapper.ets` | `ProtocolCloud.test.mjs`：`C03_StateReportMapper_servicesShapeIsStrictPerSchema`（缺 required、未知属性、顶层未知字段、布尔/整数类型负例；并保留 partial SHADOW 正例） |
| **R-10** | Low | **Fixed（Orchestrator 裁定）**：别名回退不再置 `isPartial`；新增独立诊断位 `DiscoverySnapshot.aliasUsed`（默认 false；使用别名的映射设备或跳过设备均置位）。`isPartial` 仍只表示“设备被跳过/字段缺失” | `entry/src/main/ets/model/DiscoveryModels.ets`；`DiscoverMapper.ets`（按设备偏差区间收集 alias 使用，含 catch 路径） | `ProtocolDiscover.test.mjs`：别名用例改为 `isPartial=false` + `aliasUsed=true`；`C03_DiscoverMapper_aliasAndPartialAreIndependentDiagnostics` 覆盖 alias+skip、仅 alias 的跳过设备、clean 三种组合；Hypium `DiscoverMapper.test.ets` 同步 |
| **R-11** | Low | **Fixed**：未知 `deviceType` 的 `ProtocolDeviation.detail` 改为稳定原因码 `unrecognized_type`，不再放入原始值/设备名 | `DiscoverMapper.ets` | `ProtocolDiscover.test.mjs`：`C03_DiscoverMapper_unknownTypeRoomModeColorAndStateSourceAreTolerated` 断言 `detail='unrecognized_type'` 且不含 `'weird'` |
| **R-12** | Low | **Fixed**：README 当前 revision 更新为 **88/88**（证据 `t06-fix-host-node-tests.tap`），并明确 T-05 历史基线 **15/15** 不代表当前 revision | `entry/src/test/README.md` | `entry/src/test/evidence/t06-fix-host-node-tests.tap` |
| **R-13** | Low | **Deferred（记录例外）**：端口暂留 `common/types/Ports.ets`，云映射暂留 `service/protocol/`；**签名不变、无第二套实现**。迁移计划：T-07/C-05 → `contracts/**`；T-14/C-15 → `service/cloud/**`。需在 CQG-T06/Gate 记录该例外 | 无代码移动；本报告 §3.1 | `git status`/diff 证明无重复实现 |

> 计数：**Fixed 12**（R-01..R-12）、**Deferred/Exception 1**（R-13）。无未处置的评审 finding。

---

## 2. 变更文件

### 2.1 产品代码（10）

```text
entry/src/main/ets/common/constants/DeviceConstants.ets       # R-07 布尔动作值类型
entry/src/main/ets/common/types/AppError.ets                   # R-06 i18n key
entry/src/main/ets/common/utils/Base64Url.ets                  # R-05 空串拒绝
entry/src/main/ets/model/ControlModels.ets                     # R-02 shouldApplyState 不变式
entry/src/main/ets/model/DiscoveryModels.ets                   # R-10 aliasUsed
entry/src/main/ets/service/protocol/CloudCommandSerializer.ets # R-08 nonce
entry/src/main/ets/service/protocol/ControlAckMapper.ets       # R-01..R-04
entry/src/main/ets/service/protocol/ControlRequestSerializer.ets # R-07/R-08
entry/src/main/ets/service/protocol/DiscoverMapper.ets         # R-10/R-11
entry/src/main/ets/service/protocol/StateReportMapper.ets      # R-09
```

### 2.2 测试与证据

```text
entry/src/test/host/Foundation.test.mjs
entry/src/test/host/ProtocolAck.test.mjs
entry/src/test/host/ProtocolCloud.test.mjs
entry/src/test/host/ProtocolControl.test.mjs
entry/src/test/host/ProtocolDiscover.test.mjs
entry/src/test/protocol/ControlRequestSerializer.test.ets
entry/src/test/protocol/DiscoverMapper.test.ets
entry/src/test/README.md
entry/src/test/evidence/t06-fix-ohpm-install.log
entry/src/test/evidence/t06-fix-clean-assemble.log
entry/src/test/evidence/t06-fix-codelinter.log
entry/src/test/evidence/t06-fix-host-node-tests.tap
entry/src/test/evidence/t06-fix-hvigor-test-compile.log
artifacts/50-implementation/t06-fix-report.md
```

未修改：`contracts/**`、`repository/**`、`service/cloud/**`、`ohosTest` 契约夹具、构建配置、签名/nonce 生成实现（T-07）。

---

## 3. 对冻结契约的偏离、选择与例外

### 3.1 R-13：目录落点例外（签名不变）

- `common/types/Ports.ets` 暂留 C-01 目录；`CloudCommandSerializer` / `StateReportMapper` 暂留 `service/protocol/`。
- 理由：`wp-014` 写范围不含 `contracts/**` 与 `service/cloud/**`；T-06 的依赖方向正确，无行为偏差。
- 约束：**不复制第二套实现**；迁移时只移动文件并更新 import。
- 迁移计划：
  - T-07/C-05：`Ports.ets` → `contracts/**`（保持 `HmacSignerPort` 等签名）。
  - T-14/C-15：云命令/影子/完成判定映射 → `service/cloud/**`（保持公开方法签名；`StateReportMapper` 可作为过渡名）。
- CQG-T06/Stage Gate 需把该例外写入接受记录，否则复审仍会按 R-13 提出。

### 3.2 R-09：SERVICES 严格解析，SHADOW/DEVICES 仍容忍

选择**严格**而非“partial report 容忍”，依据 `input/api/protocol/state-report.schema.json` 的 `required`/`additionalProperties:false` 与 PR-01：

- 顶层只允许 `services`；service 对象只允许 `service_id/properties/event_time`。
- `properties` 必须包含 7 个 required 固定属性；只允许 schema 列出的属性；6 个 Online 必须为 boolean，`Gateway_RSSI` 必须为 -127..0 的整数。
- `DeviceInventoryJson` 仍作为字符串保留，不在 T-06 解析；T-14/PB-02 接管内部结构与完整完成判定。
- `SHADOW`/`DEVICES` 形态允许 partial（现有测试显式保留该正例），避免把 T-06 的共享映射面误升级为云完成判定。

### 3.3 R-08：V-01 夹具 nonce 与出站生成契约不一致（上游观察）

- DES-A §3.3/§18.5 要求控制/云出站 nonce 为 16B → 32 位小写 hex。
- 公开 V-01 夹具 `hmac-sha256-test-vectors.json` 的 4 条 nonce 是 **12 位 hex**（如 `9f2a7c001122`），按本修复后的严格序列化器会被拒绝。
- 处理：序列化器按冻结契约严格拒绝；V-01 测试仍逐字验证 canonical/HMAC oracle 与 `expectedSign`，仅在“字段顺序/结构”断言中替换为 32-hex 合同 nonce，并新增 `C03_ControlRequestSerializer_fixtureNoncesAreOutsideOutboundContract` 明确记录该差异。
- 跟踪：T-07 实现 `RequestSigner` 时必须以 32-hex 生成 nonce，不得以 V-01 的 12-hex nonce 作为生成器合规证据；T-19 若要求“公开向量可直接序列化”，需上游澄清/更新夹具或放宽 §3.3；本任务不修改 `input/**` 或 `ohosTest` 夹具。

### 3.4 R-10：`aliasUsed` 是新增诊断位

- 冻结的 `DiscoverySnapshot` 没有 `aliasUsed`；Orchestrator 已裁定新增该只读诊断位，以区分“别名回退”与“设备跳过/字段缺失”。
- `isPartial` 定义未改变；C-10/T-19 仍应只在 `isPartial=true` 时禁止“网关已移除”判定；`aliasUsed` 仅用于诊断/迁移提示，不得单独改变合并语义。
- 该新增字段是 add-only；现有构造默认 `false`。

### 3.5 R-07：7 值 `SET_MODE` 词表归属

- 本修复只在序列化器强制 **value kind**（STRING），不强制 7 值词表；V-01 的 `'制冷'` 编码夹具必须继续可序列化。
- 7 值词表由 C-11（命令构造）/C-16（控制策略）与 CB §6.3 强制；越界模式应在命令层被拒绝，而非序列化层。

### 3.6 其他

- 未实现/未修改 HMAC、签名、验签、nonce 生成；仍归 T-07/C-05。
- 未修改云完成判定、`DeviceInventoryJson` 解析；仍归 T-14/PB-02。
- `ControlOutcome.create` 新增的不变式（`shouldApplyState ⇒ reportedState`）是 R-02 定义的直接编码，不改变合法调用路径。

---

## 4. 验证证据

### 4.1 必跑命令（当前修复 revision）

```text
$ ohpm install
install completed in 0s 58ms
exit 0
证据: entry/src/test/evidence/t06-fix-ohpm-install.log

$ hvigorw clean assembleHap --no-daemon
BUILD SUCCESSFUL in 6 s 855 ms
35 tasks in total: 34 executed, 1 up-to-date
WARN: Will skip sign 'hos_hap'. No signingConfigs profile is configured...
exit 0
证据: entry/src/test/evidence/t06-fix-clean-assemble.log

$ codelinter -c code-linter.json5 -p default .
No defects found in your code.
exit 0
证据: entry/src/test/evidence/t06-fix-codelinter.log

$ entry/src/test/run-host-tests.sh
1..88
# tests 88
# pass 88
# fail 0
# duration_ms 641.145518
exit 0
证据: entry/src/test/evidence/t06-fix-host-node-tests.tap
```

### 4.2 新增/更新测试（81 → 88，+7；另替换 1 个固化偏差用例）

1. `C03_ControlAckMapper_unknownFieldsUseAckProtocolViolationInAllShapes`（R-01，新增）
2. `C03_ControlAckMapper_nonZeroResultStillValidatesReportedStateSchema`（R-04，新增）
3. `C03_ControlAckMapper_nonStandardModeComparesRawValue`（R-03，替换原 `..._nonStandardModeIsUnverifiedNotSuccess`）
4. `C03_ControlRequestSerializer_fixtureNoncesAreOutsideOutboundContract`（R-08 夹具差异，新增）
5. `C03_ControlRequestSerializer_enforcesActionValueKind`（R-07，新增）
6. `C03_ControlRequestSerializer_enforcesHexLower32Nonce`（R-08，新增）
7. `C03_StateReportMapper_servicesShapeIsStrictPerSchema`（R-09，新增）
8. `C03_DiscoverMapper_aliasAndPartialAreIndependentDiagnostics`（R-10，新增）

> 新增 = 7（第 1、2、4、5、6、7、8 项）；第 3 项为同计数替换。测试总数 88 与 T-05 基线 15/15 的关系已写入 `entry/src/test/README.md`。

### 4.3 附加检查：Hypium host 编译

```text
$ timeout 90 hvigorw test --no-daemon
> hvigor Finished :entry:default@UnitTestArkTS... after 6 s 340 ms
> hvigor Linux
exit 124 (timeout)
```

结论：测试代码编译通过；运行时仍受 Linux Previewer 限制，保持 **COMPILED_ONLY / BLOCKED**，不写成 PASS。证据 `t06-fix-hvigor-test-compile.log`。

---

## 5. 残余风险与建议跟踪

| ID | 风险/事项 | 影响 | 建议 |
|---|---|---|---|
| FIX-RISK-01 | R-13 目录例外未迁移 | 后续任务可能 import 错位置或复制实现 | T-07/T-14 按 §3.1 迁移；CQG-T06 记录例外 |
| FIX-RISK-02 | V-01 夹具 nonce 12-hex 与 §3.3 冲突 | T-07 可能误用夹具 nonce 作为生成器证据 | T-07 生成 32-hex；上游 T-19 澄清是否更新夹具 |
| FIX-RISK-03 | `aliasUsed` 为新增字段 | C-10 可能误用为 partial/移除判定 | C-10/T-19 只在诊断中使用；`isPartial` 语义不变 |
| FIX-RISK-04 | SERVICES 严格解析可能拒绝真实 partial 云报文 | 若固件只上报变更属性，T-14 会得到 `CLOUD_SHADOW_INVALID` | 以 schema 为准联调；若确认固件 partial，T-14 增加显式 partial adapter，不静默放宽 T-06 |
| FIX-RISK-05 | `SET_MODE` 非标准值现为 MISMATCH | VM 可能触发 REVERT；云路径规则不同 | C-10/C-21 按 DES-A §5.1.4 处理；云路径按 DES-B §8.1.6 由 T-14 实现 |
| FIX-RISK-06 | 非零 ACK 的合法 `reported_state` 被校验但不暴露 | 诊断可能缺少错误 ACK 的状态 | 当前按评审要求执行；若 C-17 需要诊断字段，走 Change Impact |
| FIX-RISK-07 | Hypium/设备运行仍 BLOCKED | 无设备侧运行时 PASS | T-19 在设备/CI 复跑；保持 `COMPILED_ONLY`/`BLOCKED` |
| FIX-RISK-08 | HMAC/签名未实现 | 控制请求仍不能真实发送 | T-07 |

---

## 6. 结论

R-01..R-12 已按评审报告与 Orchestrator 裁定修复并有对应负例/语义测试；R-13 以“签名不变、无重复实现、后续迁移”的明确例外记录。四项必跑命令全部通过（host 88/88）。组件保持 `UNVERIFIED`，等待**作者之外**的独立复审与 CQG-T06 Gate；本报告不构成 STABLE、Stage Gate 或用户验收。
