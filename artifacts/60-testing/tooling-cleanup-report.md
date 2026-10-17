# TOOLING-CLEANUP-REPORT-001：T-20 工具收口与分层例外正式化

- **Artifact ID**: TOOLING-CLEANUP-REPORT-001
- **Producer**: agent:test-engineer
- **Type**: Tooling Implementation / Verification Report / Exception Registry Evidence
- **Status**: COMPLETE（T-20 工具语义已落地并实测；不授予 Gate PASS）
- **Date**: 2026-10-18
- **Task**: `wp-085-tooling`（T-20；`task/wp-085-tooling`，父分支 `feat/yaocore-app`，base `1cd7998`）
- **Workflow**: STANDARD / GATED_AUTO
- **Inputs**: `artifacts/70-review/final-system-review.md`（F-01..F-06）；`artifacts/60-testing/test-report.md`；DES-A §27.6；DES-B §2.3/§18.1；`tools/contract/{check_layering.py,layering_allowlist.json,test_check_layering.py}`；`entry/src/test/i18n/check_i18n.py`
- **写范围**: `tools/contract/`、`entry/src/test/`、`artifacts/60-testing/`、`entry/src/main/ets/service/`
- **上游裁定**: DES-A §27.6（端口物理位置例外 17 条）；DES-B §2.3/§18.1（`T20-D12-01..13`，13 条 `accepted`）；contract-baseline §4.5（响应验签/相关性错误码唯一命名）

> **结论先行**：F-01/F-02 已由检查器读取版本化登记收口；F-03 报告数字已与证据文件一致；F-04 Mock 退役别名已对齐；F-05 `--strict-ui` 已成为真实门禁开关；F-06 补齐 D-03/D-05 与端口例外 fixture。8 项指定验证命令全部实际执行且通过（host **697/697**、fixture **10/10**、layering **violations=0 / pending=0**、crosscheck **66/66**、i18n **0 blocking**、codelinter **0 error**）。端口迁移仍未执行，属独立任务；`check_layering` 0 violation 不等于端口位置合规。

---

## 1. 逐项处置（F-01..F-06）

| Finding | 级别 | 处置 | 结果 | 证据 |
|---|---|---|---|---|
| **F-01** 端口位置例外硬编码 | Medium | 把 DES-A §27.6.2 的 **17 条** `port_location_exceptions`（16 个端口/契约文件 + 1 个 `pure-seam`）写入 `layering_allowlist.json`；`check_layering.py` 新增 `load_port_location_exceptions()`，按精确 `path` + `symbols ⊆` 匹配；删除 `_is_storage_port_path`/`_is_viewmodel_service_port`；未登记路径、符号越界、非 `accepted-location-exception` 状态均使 D-09/D-11 失败；注册端口文件新增 `@ohos.*`/adapter/未登记 repository 依赖时报 `PORT-LOC`。 | **CLOSED（工具侧）**。17 条全部载入；10 条当前被使用（PORT-LOC-02/03/04/05/06/07/08/09/10/11），7 条保留待迁移（01/12/13/14/15/16/17）。 | `tools/contract/layering_allowlist.json`；`check_layering.py:393-476,530-580,688-718`；`t20-layering.json` |
| **F-02** 13 条 D-12 例外仍 pending | Low | 按 DES-B §18.1 定稿写入 **13 条** `T20-D12-01..13`，`status: accepted`；`status` 强制：已使用但状态不是 `accepted` 的条目为 gate 违规（exit 1），未使用 `pending-*` 保留可见告警与计数；缺失 `status` 默认 `pending-unregistered`，fail-closed。 | **CLOSED**。13/13 全部命中且仅命中一次；`pending=0`、`unused_exceptions=[]`。 | `tools/contract/layering_allowlist.json`；`check_layering.py:439-476,786-880`；`t20-layering.json` |
| **F-03** ACK p95 报告数字与证据不一致 | Low | 以证据文件 `entry/src/test/evidence/t19-ack-p95-mock.json` 为准修正 `test-report.md` 与 `test-plan.md`：p50 **0.536 ms** / p95 **0.598 ms** / max **0.684 ms**（原 0.526/0.601/0.647）。 | **CLOSED**。报告、计划与证据 JSON 逐字一致；仍标注 `MOCK_ONLY`。 | `artifacts/60-testing/test-report.md:71,176,185`；`artifacts/60-testing/test-plan.md:618`；`entry/src/test/evidence/t19-ack-p95-mock.json` |
| **F-04** C-20 Mock 退役错误码别名 | Low | 删除 `MockGatewayService` 的 try/catch 别名转换；header 验签失败原样传播 `RESPONSE_AUTH_FAILED`，header correlation 失败传播 `RESPONSE_CORRELATION_MISMATCH`；ACK body 的 `request_id`/`seq` 仍由 C-03 `ControlAckMapper` 产出 `ACK_CORRELATION_MISMATCH`。同步 `GatewayMock.test.mjs` 断言。 | **CLOSED**。MOCK 与生产 `LocalGatewayService` 语义一致；`CONTROL_RESPONSE_AUTH_FAILED` 不再有新产生点。 | `entry/src/main/ets/service/mock/MockGatewayService.ets:300-307`；`entry/src/test/host/GatewayMock.test.mjs:175-184`；`t20-host-node-tests.tap` |
| **F-05** `--strict-ui` 为 no-op | Low | `--strict-ui` 现在把短英文 UI 文案从 `warning` 提升为 `blocking`；默认仍为 advisory。短 UI 规则排除 `LOADING`/`RECONFIGURE` 等 SCREAMING_SNAKE 技术常量与 CamelCase 标识符；报告新增 `strictUi` 字段；README/CLI help 已文档化。 | **CLOSED**。新增 `fixtures/short-ui/` 与 host 测试：默认 exit 0（warning），strict exit 1（blocking）。生产树 strict 重跑 **0 blocking**。 | `entry/src/test/i18n/check_i18n.py:19-22,248-250,485-516,556-566,584`；`entry/src/test/host/I18n.test.mjs:556-579`；`entry/src/test/i18n/README.md`；`t20-i18n-checker.log` |
| **F-06** fixture 缺 D-03/D-05 负例 | Low | `bad` fixture 新增 `contracts/BadContract.ets`（导入 service/repository）与 `repository/BadRepoPlatform.ets`（`@ohos.net.http`）；新增端口例外 4 类 fixture：合法（含 pure-seam）、未登记路径、符号越界、`pending-*`；另加 `pending-d12` 验证 D-12 状态强制。 | **CLOSED**。自测从 4 条扩为 **10 条**，覆盖 D-01/02/03/05/06/08/09/11/12/13/17 与端口例外全部失败语义。 | `tools/contract/test_check_layering.py`；`tools/contract/fixtures/layering/**`；`t20-layering-fixture-tests.log` |

## 2. 检查器语义变更（before → after）

| 语义 | T-19 | T-20 |
|---|---|---|
| 端口放行 | `_is_storage_port_path()` / `_is_viewmodel_service_port()` 代码内硬编码路径集合 | 只读取 `port_location_exceptions`；精确路径 + 非空符号子集；未登记路径 fail-closed |
| D-11 范围 | `service/{gateway,ble,crypto}`（storage 实际未受限） | `service/{gateway,ble,crypto,storage}`，按 DES-A §27.6.1 与端口登记匹配 |
| 端口状态 | 无状态概念 | 仅 `accepted-location-exception`；`pending-*` 使用时失败，未使用时可见告警 |
| D-12 状态 | 读取但不强制 | `used && status != accepted` → 违规；缺失状态按 `pending-unregistered` fail-closed |
| 端口文件漂移 | 无检查 | 注册文件新增 `@ohos.*`/adapter/未登记 repository 依赖 → `PORT-LOC` 违规 |
| 报告计数 | `exceptions_used` + 仅 used pending | `exceptions_used`、`pending`、`pending_used`、`port_exceptions_used`、`port_pending`、`port_pending_used`；保留 `unused_exceptions` 与完整端口登记明细 |
| D-12 与端口例外关系 | 端口硬编码与 D-12 allowlist 分离但不显式 | 两者独立匹配、取更严格者；端口例外**不得**放宽 D-12（fixture `port-exceptions/bad` 验证） |

## 3. 验证命令与实际结果

环境：Linux x86_64；分支 `task/wp-085-tooling`；base `1cd7998`；Python 3.12.3；Node v24.15.0；hvigorw 6.26.8；ohpm 26.0.0.630；codelinter 6.0.240；HarmonyOS SDK 26.0.0.105；无设备/模拟器/签名。

| # | 命令 | 实际结果 | 分类 | 证据 |
|---|---|---|---|---|
| 1 | `ohpm install` | `install completed in 0s 45ms`；exit 0 | **PASS** | `entry/src/test/evidence/t20-ohpm-install.log` |
| 2 | `hvigorw clean assembleHap --no-daemon` | `BUILD SUCCESSFUL in 14 s 460 ms`；35 tasks；unsigned HAP（无 signingConfigs） | **PASS** | `t20-clean-assemble.log` |
| 3 | `codelinter -c code-linter.json5 -p default .` | `Defects: 25; Errors: 0; Warns: 25`；exit 0 | **PASS（0 error）** | `t20-codelinter.log` |
| 4 | `entry/src/test/run-host-tests.sh` | `tests 697 / pass 697 / fail 0 / skipped 0`；exit 0 | **PASS** | `t20-host-node-tests.tap` |
| 5 | `python3 tools/contract/check_layering.py` | `files=209 violations=0 exceptions_used=13 pending=0 pending_used=0 port_exceptions_used=10 port_pending=0 port_pending_used=0`；exit 0 | **PASS（含已登记例外）** | `t20-layering.log`、`t20-layering.json` |
| 6 | `python3 tools/contract/test_check_layering.py` | `Ran 10 tests ... OK`；exit 0 | **PASS 10/10** | `t20-layering-fixture-tests.log` |
| 7 | `python3 entry/src/test/i18n/check_i18n.py --strict-ui` | `blockingFailures=0 warnings=73 missingKeys=0 hardcoded=16`；exit 0 | **PASS（strict 生效）** | `t20-i18n-strict-noallow.log` |
| 8 | `python3 tools/contract/crosscheck_protocol_assets.py` | `hard checks: ALL PASS`（66 PASS）；14 项冻结输入 `FINDING`；exit 0 | **PASS 66/66** | `t20-crosscheck.log` |

补充证据（带 allowlist 的 i18n 重跑）：

```text
$ python3 entry/src/test/i18n/check_i18n.py --strict-ui \
    --allowlist entry/src/test/i18n/allowlist.json \
    --report entry/src/test/evidence/t20-i18n-report.json
summary: blockingFailures=0 warnings=55 missingKeys=0 hardcoded=16
```

- T-19 的 121 warnings / 82 hardcoded 含 66 条状态常量误报；T-20 排除后 hardcoded=16，全部是非 UI 技术字符串（`AppTheme` 颜色注释、AC 适配器 CJK 名称、mock 错误消息），**0 blocking**。
- 其余 39 条 CHK-05 为未使用键告警（non-blocking）；带 allowlist 时与不带 allowlist 的差异仅来自 keyPrefixes。

## 4. 追溯

| 项 | 映射 |
|---|---|
| F-01 / PORT-LOC-01..17 | DES-A §27.6；`layering_allowlist.json:port_location_exceptions`；`check_layering.py` |
| F-02 / T20-D12-01..13 | DES-B §2.3/§18.1；`layering_allowlist.json:entries`；`check_layering.py` |
| F-03 | contract-baseline/测试证据 `t19-ack-p95-mock.json`；test-report/test-plan |
| F-04 | contract-baseline §4.2/§4.5；DES-A §17/§19；`MockGatewayService`、`GatewayMock.test.mjs` |
| F-05 | DES-B §7.4.4 / CHK-07；`check_i18n.py`、`I18n.test.mjs`、i18n README |
| F-06 | DES-B §18.1 item 5；fixture 自测 |

## 5. 残余与限制

1. **端口迁移未执行（独立任务）**：`contracts/**` 仍不存在；17 条例外只是受控接受。建议按 DES-A §27.6.3 的 P1..P4 执行迁移，之后 `port_exceptions_used` 逐条归零并删除条目。任务 ID 由 Orchestrator 分配，不占用 T-21/T-22。
2. **0 violation ≠ 端口位置合规**：G-013/G-014 必须记录“例外已登记、迁移未完成”，不得把本报告写成 Gate PASS。
3. **7 条未使用端口登记**：PORT-LOC-01/12/13/14/15/16/17 当前不被 D-09/D-11 触发（或仅作为同层依赖），保留用于架构登记完整性；迁移后删除，不得复用 ID。
4. **i18n 路径偏差 T10-EX-01 未变**：检查器仍在 `entry/src/test/i18n/`，未迁移到 `tools/i18n/`。
5. **i18n 剩余 16 条 hardcoded warning** 均为非 UI 技术字符串；`--strict-ui` 只提升短英文 UI 文案，不追溯这些历史告警。
6. **设备/真实环境仍 BLOCKED/UNAVAILABLE**：本报告不覆盖真实 BLE/LAN/TLS/云/视觉/fps；ACK p95 仍为 `MOCK_ONLY`。
7. **未提交的 commit ID**：本报告在提交前生成；最终 commit 以 `swe_guard.py finish` 的校验与 handoff 返回值为准。
