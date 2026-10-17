# T-12 聚焦复审报告（R2 项关闭确认 / CQG-T12 最终意见）

- **Artifact ID**: REV-T12-003
- **Producer**: agent:quality-reviewer
- **Type**: Independent Focused Re-Review / Review Handoff
- **Status**: **PASS（代码级，条件式）**
- **Date**: 2026-10-17
- **Task**: `wp-045-review-t12c`（task 分支 `task/wp-040-ble`，父分支 `feat/yaocore-app`）
- **Workflow**: STANDARD / GATED_AUTO
- **Target Stage**: `implementation`（CQG-T12 前）
- **Reviewed revision**: `74255fc111a470a14eb8a6ee231c8482134f594e`（收窄修复提交；父 `1eae08c` 复审报告；原实现 `27dc537`，首轮修复 `a6a3053`）
- **Review snapshot**: `refs/swe/snapshots/20261017T133124Z-wp-045-review-t12c-f4ae1bfc`（commit `e39977e`）
- **Previous reviews**: `artifacts/70-review/t12-review.md`（REV-T12-001）、`artifacts/70-review/t12-review-b.md`（REV-T12-002）
- **Independence**: 本复审由未参与 T-12 实现、`wp-042-fix-t12`、`wp-044-fix-t12b` 修复或任何修复报告编写的 `quality-reviewer` 执行；未修改被审产品代码、测试、证据或修复报告。唯一仓库写入为本报告；占位文件由 Orchestrator 预置以满足快照覆盖，本报告已整体覆写并声明 `Producer: agent:quality-reviewer`。

> 结论先行：**R2-01/R2-03/R2-04 均已关闭**，R2-02/R2-05 按“记录/文档”方式关闭；F-04 由 REV-T12-002 的 PARTIAL 升级为 **CLOSED**。当前 revision 独立复跑 **451/451 host**、`codelinter`、`hvigorw clean assembleHap`、ohosTest 编译均通过；Security1 冻结向量、秘密清零、身份 fail-closed、探针语义与已关闭 F 项无回归；独立探针 24/24 通过。未发现新的阻断项，仅新增 R3-01/R3-02 两条 Low/Info 跟踪项。建议 CQG-T12 以**代码级 PASS（条件式）**记录；`STABLE` 与设备证据仍受 R-1/R-2/D-4 及 T-19 约束。

---

## 1. 复审范围、revision 与输入完整性

### 1.1 范围

```text
entry/src/main/ets/service/                     # C-19 产品代码
entry/src/test/                                 # host fakes、451 条测试、证据日志
artifacts/50-implementation/t12-fix2-report.md  # 收窄修复报告
```

- 修复 diff `1eae08c..74255fc` 共 **15 文件**：4 个产品文件（`BleSupport.ets`、`GattChannel.ets`、`Protobuf.ets`、`adapters/OhosBleTransport.ets`）、3 个 host 测试文件、5 个证据日志、3 个实现报告（`t12-fix2-report.md` 新增，`t12-fix-report.md`/`t12-ble.md` 更新）。
- 全部路径落在 handoff 的 `review_targets`/`writes`/`commit_paths`、或该修复任务声明的 `artifacts/50-implementation/` 范围内；未修改 `entry/src/main/module.json5`、model、DES/ADR、`contract-baseline.md`、`project-constraints.md`、`test-plan.md` 或其他 Stage 产物。
- 未发现构建产物、`.hap`/`.har`、`oh_modules`、证书/私钥或真实秘密入库。
- 范围外/明确排除：真实 BLE 射频、真实 MTU/`0x2901`、平台 X25519/AES-CTR 运行时、真实 ESP-IDF 网关、真实 LAN/HTTPS pin、板载 LED 硬件、API 14/15 设备安装、Hypium/`hvigorw test` 运行时。

### 1.2 输入 pin

本复审核对了 handoff `wp-045-review-t12c` 的全部 **8 个** pin 输入，SHA-256 **8/8 一致**：

| 输入 | SHA-256 前 12 位 | 结果 |
|---|---|---|
| `artifacts/70-review/t12-review-b.md` | `6c75e397a435` | 一致 |
| `artifacts/50-implementation/t12-fix2-report.md` | `609a7b1d032a` | 一致 |
| `artifacts/50-implementation/t12-fix-report.md` | `b9c8c0a89176` | 一致 |
| `artifacts/40-detailed-design/des-001a-foundation-transport.md` | `5599e693fafe` | 一致 |
| `artifacts/20-architecture/adr-002-lan-security-channel.md` | `67943a6e1d8d` | 一致 |
| `artifacts/20-architecture/contract-baseline.md` | `6673a990d502` | 一致 |
| `artifacts/20-architecture/project-constraints.md` | `283046210e68` | 一致 |
| `artifacts/60-testing/test-plan.md` | `33485cc39abd` | 一致 |

`config/git-policy.json` 的 SHA-256 亦与 handoff 一致（`3b8ddffd...`）。复审开始时 `git status` clean，`HEAD = 74255fc`，当前分支 `task/wp-040-ble`，快照 ref 存在。`t12-fix2-report.md` 自述其 wp-044 handoff pin 为 9/9；该 handoff 不在本复审输入中，本报告不把该自述当作独立证据。

### 1.3 复验命令（本复审实际执行，cwd = 仓库根）

| 命令 | 结果 | 备注 |
|---|---|---|
| `entry/src/test/run-host-tests.sh` | **PASS：451 tests / 451 pass / 0 fail / 0 skipped / 0 todo，exit 0** | 与 `entry/src/test/evidence/t12-fix2-host-node-tests.tap` 的 451/451 一致；测试名逐项相同 |
| `codelinter -c code-linter.json5 -p default .` | **PASS：No defects found in your code，exit 0** | 与 `t12-fix2-codelinter.log` 一致 |
| `hvigorw clean assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0**（35 tasks；34 executed / 1 up-to-date） | 与 `t12-fix2-clean-assemble.log` 一致；未配置签名 |
| `hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon` | **PASS：BUILD SUCCESSFUL，exit 0**（35 tasks） | 与 `t12-fix2-ohosTest-assemble.log` 一致；**仅编译，不是设备执行** |
| `git diff --name-status 1eae08c 74255fc` | **15 路径，全部在范围** | 无 `module.json5`、无构建产物、无秘密 |
| `git status --short` / `git diff --check` | **clean / exit 0** | 复验前后均 clean |
| 设备执行 | **BLOCKED（未写成 PASS）** | 无设备/签名；ohosTest 仅编译，符合 CP-03 |

测试数核对：证据 `t12-fix-host-node-tests.tap` 的 449 条用例名全部保留，新增恰好 2 条（`C19_GattChannel_ambiguousWriteFailureIsNotRetried`、`C19_ProtobufReader_rejectsNonCanonicalLengthVarint`），故 449 + 2 = 451；本次独立复跑的 451 个测试名与证据 TAP **逐项一致**。

### 1.4 独立探针（不只依赖新增测试）

使用现有 host fakes 与直接导入执行只读探针，结果 **24/24 通过**，另加 1 个安全信道写失败探针：

- **R2-01 正例**：确认 busy（`retryable=write-busy`）→ `writeAttempts=2`、accepted writes `=1`、两次写入字节完全相同、延迟 50ms。
- **R2-01 负例**：`ble:2900099`、无标记 `GATT_BUSY`、无数字码 raw Error、`ble:2900001`、`ble:2901005` → 均 `writeAttempts=1`、accepted writes `=0`、无 50ms 延迟；错误码分别为 `PROVISIONING_GATT_BUSY` / `PROVISIONING_GATT_INCOMPLETE`。
- **R2-01 安全路径**：真实 Security1 握手后对 `prov-config` 注入 `ble:2900099` 写失败 → `writeAttempts=1`、accepted writes `=0`、`readAttempts=0`、0ms 延迟，未重发密文。
- **R2-01 读 busy**：`writeAttempts=1`、`readAttempts=1`、`PROVISIONING_GATT_BUSY`，读失败不重发。
- **R2-03**：队列 20ms 超时后第二次 `run` 在 **0.21ms** 内失败且为 `GATT_BUSY`；经 `GattChannel` 调用 broken 队列 → 0 次写、0ms 延迟。
- **R2-04**：接受 `0`、`127`、`128`（`80 01`）、`300`（`ac 02`）、`0xFFFFFFFF`；拒绝 `80 00`、`ff 00`、10 字节零、`2^32`、截断续字节；canonical 128 字节正文可完整读取。
- **标记隔离**：`retryable=yes` 的伪标记不被视为确认 busy；仅精确 `write-busy` 通过。

---

## 2. R2 项关闭状态

> 状态：**CLOSED** = 代码/测试/独立探针足以关闭；**CLOSED（记录）** = 按任务决定记录而非改代码；**OPEN** = 未关闭。

| ID | 上轮级别 | 状态 | 当前代码/测试证据 | 复审判断 |
|---|---|---|---|---|
| **R2-01** | Medium / 阻断 | **CLOSED** | `BleSupport.ets:44-80` 标记与判定；`OhosBleTransport.ets:85-99,410-413` 写错误映射；`GattChannel.ets:106-122` 收窄重试；`BleGattFlow.test.mjs:284-325` 四类负例；独立探针正/负/安全路径均符合 | 只有平台确认写未受理的 `2900011`/`2901004` 可重试；`2900099`、`2900001`、`2901005..2901007`、未知/无数字码、无标记 busy 均不重发。F-04 因此转为 **CLOSED** |
| **R2-03** | Low | **CLOSED** | `GattChannel.ets:82-96` 删除队列获取重试并改为 `runSerialized`；`GattRequestQueue.ets:35-58,78-97` 超时即 broken；独立探针 broken 队列立即失败 | 命名/注释/报告口径一致；不再存在“50ms 后必然失败”的无效重试 |
| **R2-04** | Low / Info | **CLOSED** | `Protobuf.ets:219-259`；`BleCodec.test.mjs:236-252`；独立探针 canonical/overlong 双向覆盖 | 非规范 10 字节零与 `80 00` 严格拒绝；合法最小编码不受影响；报告口径已校正 |
| **R2-02** | Low（既有行为） | **CLOSED（记录）** | `t12-fix2-report.md §2.4/§7`；`BleProvisioningService.ets:378-380` 行为未变 | 显式 `request.device` 覆盖 `lastDevice` 为既有语义，已如实记录；未改变已关闭的 F-02 行为 |
| **R2-05** | Info（过程） | **CLOSED（文档）** | `t12-ble.md` 顶部 SUPERSEDED 注记 + `GattChannel.ets` 行内标注；`t12-fix-report.md` 顶部复审更新与 F-04 口径修正 | 旧报告不再误导 CQG；当前行为指向 `t12-fix-report.md` / `t12-fix2-report.md` |
| **F-04** | Medium | **CLOSED** | 上述 R2-01/R2-03 证据 + `C19_GattChannel_writeBusyRetriesOnceWithSameBytes`、`...PreservesCtrStream`、`...readBusyIsTerminalWithoutResend` 全部通过 | 写确认 busy 重试一次并复用同一密文；读 busy 终止；歧义写失败终止；CTR 不二次推进 |

### 2.1 R2-01：写重试仅确认 busy

**适配器侧**（`entry/src/main/ets/service/ble/adapters/OhosBleTransport.ets`）：

- `mapWriteError()`（`:92-99`）仅当 `business.code` 为数字且等于 `2900011`（GATT busy）或 `2901004`（connection congested）时返回 `confirmedWriteBusy()`；该错误为 `PROVISIONING_GATT_BUSY` 且带 `NameValue('retryable','write-busy')`。
- 其他写失败回落到 `mapBleError(error, 'PROVISIONING_GATT_INCOMPLETE')`：`2900099`/未知码带 `field=ble:<code>`，无数字码为无 details 的 `GATT_INCOMPLETE`；`201`/`2900003`/`2901003` 仍保留既有 `PERMISSION_DENIED`/`BLUETOOTH_OFF`/`CONNECT_FAILED` 映射；`2901000` 为 `GATT_INCOMPLETE`。
- `writeCharacteristic` 的 catch 已改为 `throw mapWriteError(...)`（`:410-413`）；读路径仍用 `mapBleError`，显式 busy 读错误为**无标记** `GATT_BUSY`，不会触发写重试。

**通道侧**（`entry/src/main/ets/service/ble/GattChannel.ets`）：

- `writeRead` 的重试条件从 `isCode(..., 'PROVISIONING_GATT_BUSY')` 收窄为 `isConfirmedWriteBusy(typed)`（`:113`）；无标记 `GATT_BUSY`、队列超时、其他端口实现的 busy 均不重试。
- `BleSupport.isConfirmedWriteBusy`（`:65-80`）要求错误为 `AppError`、code 精确为 `PROVISIONING_GATT_BUSY`、details 精确包含 `retryable=write-busy`。
- 安全请求的重试仍发生在 `writeRead` 内，复用 `session.encrypt()` 产生的同一 `encrypted` 帧（`:69-79`），不重新加密、不推进 CTR；`finally` 在成功/失败路径清零密文缓冲。
- 错误向上抛出后由既有 `BleProvisioningService` catch/finally 清理；本次未削弱扫描停止、断连、session/queue 销毁或副本清零路径。

**测试与探针**：

- `C19_GattChannel_writeBusyRetriesOnceWithSameBytes`：2 次写尝试、1 次完成写、两次字节相同、50ms 延迟。
- `C19_GattChannel_writeBusyRetryPreservesCtrStream`：真实 Security1 握手 + 加密请求，重试后仍解密出 `192.168.1.50`，两次写入密文逐字节相同。
- `C19_GattChannel_ambiguousWriteFailureIsNotRetried`：4 个变体均 1 次写尝试、0 次完成写、无延迟；fake 的确认 busy 标记使用固定字面量，避免产品 helper 与测试共享常量而掩盖漂移。
- 独立探针额外覆盖 `ble:2901005` 与安全路径 `prov-config` 的歧义写失败，结果一致。

**关于 `PROVISIONING_GATT_INCOMPLETE` 新映射（低风险确认）**：DES-A §16.10 只列了“端点缺失/重名/不可读写 → `GATT_INCOMPLETE`”，没有单列“写失败”；但 §3.2.3 的错误目录把 `PROVISIONING_GATT_INCOMPLETE` 定义为 **非重试**（`retryable=false`），语义上适合“写未确认受理、不得重发”的终止错误，且复用既有 code/i18n 键，不新增 stable code。该映射合理，建议由 solution-architect 在 DES-A §16.2/§16.10 增补一行或正式确认复用（R3-01，Low/过程，不阻断）。

### 2.2 R2-03：队列超时即 broken，无无效重试

- `GattRequestQueue.execute` 的超时计时器覆盖排队等待与操作本身；超时置 `broken=true`，等待者/后续 `run` 在入口直接 `PROVISIONING_GATT_BUSY`（`GattRequestQueue.ets:35-58,78-97`）。
- `GattChannel.runSerialized`（`:82-96`）只执行一次 `queue.run` + `mapProvisioningError`，不再有 `!started` 的 50ms 重试；注释明确“队列超时永久 broken，第二次运行必然失败；写 busy 处理在 `writeRead` 内”，与实现一致。
- 独立探针：超时后第二次 `run` 在 0.21ms 内失败；通过 `GattChannel` 调用 broken 队列时 0 次写、0ms 延迟。既有 `C19_GattRequestQueue_timeoutNeverStartsConcurrentOperation` 继续通过，F-08 单飞不变量未变。

### 2.3 R2-04：非规范长度 varint 严格拒绝

- `ProtobufReader.readLength()` 在终止字节处增加最小编码检查：`index > 0 && payload === 0` → `fail('length')`（`PROTOCOL_INVALID_JSON`），覆盖 10 字节零与 `80 00`；`2^32`、10 字节非零高位仍按 F-11 拒绝（`Protobuf.ets:219-259`）。
- 合法最小编码（`0`、`127`、`128`、`300`、`0xFFFFFFFF`）不受影响；`readUnsigned` 的 int32 二补码语义未改，冻结向量未受影响。
- `C19_ProtobufReader_rejectsLengthVarintAbove32Bits` 与新增 `C19_ProtobufReader_rejectsNonCanonicalLengthVarint` 均通过；独立探针补充 `ff 00` 与 128 字节正文正例。`t12-fix2-report.md §2.3`、`t12-fix-report.md` F-11 的口径与实现一致。

### 2.4 R2-02 / R2-05

- **R2-02**：`resolveDevice` 在显式 `request.device` 时仍执行 `this.lastDevice = request.device`（`BleProvisioningService.ets:378-380`），本次未改；`t12-fix2-report.md §2.4` 准确记录“一次显式传参后，省略 device 且本次扫描唯一时会使用该显式设备”，并说明可在后续任务增加扫描代次。该行为在 `ba0de0c` 已存在，不构成本次回归。
- **R2-05**：`t12-ble.md` 顶部已加 SUPERSEDED 注记（冻结于 `27dc537`，当前行为以 `t12-fix-report.md`/`t12-fix2-report.md` 为准），§3 的 `GattChannel` 行也已标注过时；`t12-fix-report.md` 顶部注明 R2-01/R2-03/R2-04 更新并更正“队列获取超时重试语义保留”的旧表述。文档口径一致。

---

## 3. 回归检查

| 回归面 | 结论 | 证据 |
|---|---|---|
| Security1 冻结向量 | **PASS** | `C19_ProtocommCodec_step0MatchesFrozenVector`、`C19_Security1_rfc7748Vector`、`C19_Security1_handshakeAndContinuousCtrStream`、`...stateGuardsAndStep0Vector` 全部通过；本次 diff 未修改 `Security1Session.ets`/`ProtocommCodec.ets` |
| 秘密清零（SC-06） | **PASS** | `C01_SecureBytes_zeroizesAndRejectsUseAfterDestroy`、`C19_Security1_wrongPopFailsClosedAndDestroysSession`、`C19_BindingProber_draftIsDestroyedOnFailure`、`C19_BleProvisioningService_postProbeListenerFailureDestroysReissuedDraft` 通过；`GattChannel` 密文 `finally` 清零未改 |
| 身份 fail-closed | **PASS** | `C19_IdentityNegotiator_v20*`/`v21*`/`pinValidationIsFailClosed`/`expectedGatewayIdMismatchIsTerminal` 等全部通过；本次未改身份解析 |
| 探针语义 | **PASS** | gatewayId/snapshot/profile/LED 校验、identity mismatch 终止、有限 5 次、失败不写绑定均通过；本次未改 `BindingProbe` |
| GATT 串行/`0x2901`/MTU | **PASS（host）** | `C19_GattRequestQueue_timeoutNeverStartsConcurrentOperation`、`C19_GattEndpointMap_*`、MTU 用例通过；R2-03 删除无效重试后单飞不变量更强 |
| F-01/F-02/F-03/F-05..F-11 | **PASS** | 451/451 全量通过；本次仅改 F-04 相关重试条件、F-11 严格化与 R2-03 队列重试删除，未触碰其他已关闭行为 |
| 无秘密日志 | **PASS（代码/host）** | BLE 产品代码与本次新增测试无 secret 日志；新增错误 details 仅 `retryable=write-busy` 与 `field=ble:<code>`；证据日志无真实凭据 |
| i18n | **PASS/N/A** | 本次无新增 UI/错误文案；`provisioning.error.gatt_busy`/`gatt_incomplete` 在 zh-CN/en-US 均存在；两 locale 仅既有的复数键差异（`device.count*`），非本次引入 |
| 宿主安全边界 | **PASS** | 平台 `@ohos`/`@kit` import 仍仅在 `adapters/OhosBleTransport.ets`；`BleSupport` 保持纯 ArkTS，adapter → 纯逻辑 helper 的依赖方向可接受；`T11_pureGatewayLogicHasNoPlatformImport` 等通过 |
| 设备边界 | **BLOCKED（诚实）** | ohosTest 仅编译；无设备/签名；真实 BLE/MTU/`0x2901`/平台 X25519/AES-CTR/真实网关/LED 未执行；未把 host/编译写成设备 PASS |

**回归结论**：未发现本次收窄修复破坏 Security1、清零、身份 fail-closed、探针语义、单飞/MTU/`0x2901` 行为；451/451 可复现，449 条基线用例无删除。

---

## 4. 新发现（R3-xx）

### R3-01（Low / 过程，非阻断）：`PROVISIONING_GATT_INCOMPLETE` 复用未在 DES-A §16.10 单列

- **位置**：`OhosBleTransport.ets:92-99`；DES-A §16.10（`des-001a-foundation-transport.md:4204-4214`）与 §3.2.3 错误目录（`:553`）。
- **事实**：写失败（`2900099`、未知/无数字码、`2900001`、`2901005..2901007` 等）现映射为 `PROVISIONING_GATT_INCOMPLETE`；该 code 在错误目录中为非重试，语义匹配“写未确认受理、不得重发”，但 §16.10 只把 `GATT_INCOMPLETE` 用于端点缺失/重名/不可读写，未列写失败场景。
- **影响**：低；不改变协议行为，不新增 stable code，复用既有 i18n 键。属于契约文档的可追溯性缺口，不是代码缺陷。
- **建议**：solution-architect 在 DES-A §16.2/§16.10 增补“歧义写失败 → `PROVISIONING_GATT_INCOMPLETE`（非重试）”一行，或正式确认复用；CQG 记录该确认项。

### R3-02（Low / 证据，非阻断）：适配器 `mapWriteError` 仅编译验证

- **位置**：`OhosBleTransport.ets:85-99,410-413`。
- **事实**：`mapWriteError` 依赖 `@kit` 平台类型，host 不可执行；host 负例用与适配器 fallback 相同的 `field=ble:<code>` 形状验证通道判定，但“哪些平台码被标记为确认 busy”这一映射本身只由代码审查确认。
- **影响**：低；通道侧行为已被 451 条 host 测试与独立探针覆盖，映射错误的最坏后果是“确认 busy 未重试”或“歧义失败被误当 busy”；后者已被适配器代码的第一层 `mapWriteError` 排除，但仍需真实平台错误码语义确认。
- **建议**：T-19 在真实设备验证 `2900011`/`2901004` 的“写调用被拒绝、写未受理”语义，以及 `2900099` 等歧义码的实际行为；在此之前设备项保持 `BLOCKED`，不得写成 PASS。

---

## 5. CQG-T12 最终意见

> 本表是评审意见，不是 Orchestrator 的 Gate 记录。`PASS` 仅指当前 revision `74255fc` 的代码/构建/host 证据；设备项保持 `BLOCKED`。

| CQG 检查项 | 结果 | 证据与边界 |
|---|---|---|
| 构建 | **PASS** | `hvigorw clean assembleHap --no-daemon` exit 0，BUILD SUCCESSFUL（35 tasks）；未签名 |
| 静态检查 | **PASS** | `codelinter -c code-linter.json5 -p default .` exit 0，No defects |
| Host 测试 | **PASS** | 451/451，0 fail/0 skip/0 todo，exit 0；449 条基线保留 + 2 条新增；测试名与证据 TAP 一致 |
| 契约符合 | **PASS（附 architect 跟踪）** | R2-01 收窄符合 DES-A §16.2-3911“GATT busy 重试一次”的安全前提；`GATT_INCOMPLETE` 复用语义合理但 §16.10 未单列（R3-01）；R-1/R-2/D-4 仍为 architect 未关闭项，不构成本次代码阻断 |
| 安全 | **PASS（代码/host）** | 歧义写失败不重发；读 busy 终止；队列超时终止；Security1 派生/连续 CTR/常数时间/失败销毁、身份 fail-closed、探针验签、无 secret 日志均通过；设备侧平台 busy 语义仍 `BLOCKED` |
| 分层/依赖方向 | **PASS** | 平台 API 仅在适配器；`BleSupport` 为纯逻辑；adapter 依赖纯 helper 方向正确；无新增跨层依赖或重复实现 |
| i18n | **PASS/N/A** | 无新增硬编码文案；`gatt_busy`/`gatt_incomplete` 键在 zh-CN/en-US 均存在；无重复代码变体 |
| 独立评审 | **PASS** | 本报告由未参与实现/修复的 reviewer 出具；作者不能自批 |
| 设备/真实平台 | **BLOCKED** | 无设备/签名；ohosTest 仅编译；真实 BLE/MTU/`0x2901`/平台 X25519/AES-CTR/真实网关/LED 未验证；不得写成设备 PASS |
| 可追溯/证据 | **PARTIAL** | 修复与复审报告已更新、`t12-ble.md` 已标注 superseded；TEST-001 的 CQG-T12 状态需由 Orchestrator 更新；R-1/R-2/D-4 仍待裁定 |
| **CQG-T12 总体意见** | **PASS（代码级，条件式）** | 构建/lint/host/契约/安全/分层/独立评审均满足当前 revision 的代码级证据；设备项 `BLOCKED`；`STABLE` 与 R-1/R-2/D-4 由 Orchestrator/architect 记录后决定 |

**建议 CQG 记录**：以 **代码级 PASS（条件式）** 记录 `CQG-T12 @ 74255fc`，条件为：

1. 记录本报告的 revision、451/451 host、codelinter、clean assemble、ohosTest 编译（仅编译）证据。
2. R-1（草稿重签语义）由 solution-architect 裁定；按 REV-T12-001 的建议，**R-1 关闭前不把 C-19 标为 `STABLE`**。R-2/D-4（protocomm 非零 Status 命名）继续由 architect/D-4 owner 统一。
3. R3-01（`GATT_INCOMPLETE` 写失败映射）由 architect 确认或补 DES-A 行。
4. 设备项由 T-19 执行真实 BLE/MTU/`0x2901`/平台 crypto/真实网关/LED 端到端；在此之前 `BLOCKED`，不得用 host/编译替代。
5. TEST-001 的 CQG-T12 状态由 Orchestrator 更新，不得把本报告当成 Gate 记录或设备 PASS。

---

## 6. Verdict

**PASS（代码级，条件式）**

理由：

1. **R2-01 已关闭**：适配器只为 `2900011`/`2901004` 生成带 `retryable=write-busy` 的 `GATT_BUSY`；`GattChannel` 仅为该标记重试一次并复用同一密文。`2900099`、`2900001`、`2901005..2901007`、未知/无数字码、无标记 `GATT_BUSY` 均 1 次写尝试、0 次完成写、无 50ms 延迟；独立探针覆盖普通与安全路径。
2. **R2-03 已关闭**：`runSerialized` 只执行一次队列运行；队列超时即 broken，后续请求立即失败；命名、注释与报告口径一致。
3. **R2-04 已关闭**：`readLength` 采用最小编码，严格拒绝 10 字节零、`80 00`、`2^32` 与截断；合法小长度/边界长度不受影响。
4. **R2-02/R2-05 已按记录/文档关闭**；F-04 转为 CLOSED。
5. 451/451 host、codelinter、clean assemble、ohosTest 编译独立复现；Security1/清零/identity/探针/单飞无回归；未发现新的阻断级缺陷。
6. R3-01/R3-02 为 Low/Info 跟踪项；R-1/R-2/D-4 仍为 architect 未关闭项，设备项保持 `BLOCKED`。

**未授予**：设备/真实平台 PASS、R-1/R-2/D-4 的 architect 裁定、`STABLE`、Integration/Stage Gate 或用户验收。CQG-T12 的最终 Gate 记录与 C-19 `STABLE` 状态由 Orchestrator 依据本意见与证据决定。

---

## 7. 残余风险与跟踪项

| ID | 风险 | 级别 | 下一步/所有者 |
|---|---|---|---|
| R-1 | 草稿重签语义未经 architect 正式裁定；C-23 必须使用 `result.credentialDraftId` | Medium（契约） | solution-architect；按 REV-T12-001 建议，关闭前不标 `STABLE` |
| R-2 / D-4 | protocomm 非零 Status 统一映射 `PROVISIONING_SECURITY_HANDSHAKE_FAILED`；命名待统一 | Medium（契约） | architect / D-4 owner；当前 fail-closed |
| R-3 / R-4 / R-6 | 隐藏 SSID 入口、gatewayId `:`、`ACCESS_BLUETOOTH` 声明 | Low/High（依赖） | T-13/DES-B、C-02 owner、T-17 |
| R-5 / R-12 | 真实 BLE/平台 crypto/设备测试未执行 | High（证据） | T-19；保持 `BLOCKED`，不得写成 PASS |
| R3-01 | `PROVISIONING_GATT_INCOMPLETE` 写失败映射未在 DES-A §16.10 单列 | Low（过程） | solution-architect 确认/补文档 |
| R3-02 | 适配器 `mapWriteError` 仅编译验证，平台码语义待设备确认 | Low（证据） | T-19 设备验证 `2900011`/`2901004`/`2900099` 语义 |
| R2-RISK-05 | F-05 单次 probe 在途可超出 30s 预算 | Low | C-17 已有超时上界；T-19 验证 |
| R2-RISK-06 | F-09 单页在途可超出 15s deadline | Low | 与 F-05 同类；当前在下一页前检查 |
| R-8 | Security1 AES-CTR 无完整性；主动 BLE MITM 理论降级/篡改 | Medium（协议固有） | 记录威胁模型；不得宣称 AEAD/完整 MITM 防护 |

---

## 8. 独立声明与限制

- 本报告由 `agent:quality-reviewer` 独立出具；评审者未编写 T-12 产品代码、host 测试、fakes、修复报告或收窄修复，未修改任何被审代码；唯一仓库写入为本报告。
- 评审基于 `74255fc` 与 §1.2 的 8 个 pin 输入；独立执行 451/451 host、codelinter、clean assemble、ohosTest 编译、`git diff`/pin 校验，并用现有 fakes 做 R2-01/R2-03/R2-04 的只读独立探针（24/24 + 安全路径 1 项）；未修改仓库。构建/测试输出只写入 Git 忽略目录与 `/tmp/opencode`。
- 未覆盖：真实设备/模拟器、真实 BLE 射频、真实平台 X25519/AES-CTR、真实 ESP-IDF 网关、真实 LAN/HTTPS pin、板载 LED 硬件、API 14/15 安装、Hypium/`hvigorw test` 运行时。上述均为 `BLOCKED`/`UNAVAILABLE`，不是 PASS。
- 本报告不替代 CQG-T12、Integration Gate、Stage Gate 或用户验收；最终 Gate 记录由 Orchestrator 依据本意见与证据作出。

---

## 9. Handoff

```text
STATUS: RETURNED_FOR_GATE / PASS_CODE_LEVEL
SUMMARY: R2-01/R2-03/R2-04 全部关闭；R2-02 按记录关闭、R2-05 已标注 superseded；F-04 由 PARTIAL 转为 CLOSED。写重试仅限适配器确认 busy（2900011/2901004，retryable=write-busy），2900099/2900001/未知/无数字码/无标记 busy 均 1 次写尝试、0 次完成写、无重试延迟；安全路径复用同一密文，读 busy/队列超时终止。451/451 host、codelinter、clean assemble、ohosTest 编译独立复现；Security1/清零/identity/探针/单飞无回归；独立探针 24/24 + 安全路径 1 项通过。未发现新阻断项；R3-01/R3-02 为 Low/Info 跟踪。
CLOSURE_TABLE: R2-01 CLOSED; R2-03 CLOSED; R2-04 CLOSED; R2-02 CLOSED(record); R2-05 CLOSED(document); F-04 CLOSED.
VERDICT: PASS（代码级，条件式）；建议 CQG-T12 以代码级 PASS（条件式）记录；C-19 STABLE 受 R-1 architect 裁定约束；设备项 BLOCKED；不授予 Stage Gate/用户验收。
EVIDENCE: reviewed revision 74255fc；host 451/451 pass exit 0；codelinter No defects exit 0；clean assembleHap BUILD SUCCESSFUL exit 0（35 tasks）；ohosTest assembleHap BUILD SUCCESSFUL exit 0（仅编译）；独立探针 24/24 + 安全路径 1 项；8/8 输入 pin 一致；snapshot refs/swe/snapshots/20261017T133124Z-wp-045-review-t12c-f4ae1bfc（e39977e）；本报告提交见 swe_guard finish 记录。
NEW_FINDINGS: R3-01 Low（GATT_INCOMPLETE 写失败映射未在 DES-A §16.10 单列，建议 architect 确认/补文档）；R3-02 Low（适配器 mapWriteError 仅编译验证，平台码语义待 T-19）。均非阻断。
RISKS: R-1 草稿重签（architect，STABLE 前置）；R-2/D-4 非零 Status 命名；R-3/R-4/R-6 依赖项；R-5/R-12 设备项 BLOCKED；R3-01/R3-02 Low；R-8 CTR 无完整性。
NEEDS_CLARIFICATION: R-1 由 solution-architect 裁定；R-2/D-4 由 architect/D-4 owner 统一；R3-01 由 architect 确认 GATT_INCOMPLETE 复用；设备语义由 T-19 验证。
NEXT_ACTION: Orchestrator 以 74255fc + 本报告记录 CQG-T12 代码级 PASS（条件式）；更新 TEST-001；R-1/R-2/D-4 关闭后再议 C-19 STABLE；T-19 设备验收前设备项保持 BLOCKED。
```
