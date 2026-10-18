# DEFECT REPORT 模板（设备验收）

- **Artifact ID**: DEVICE-DEFECT-TEMPLATE-001
- **Producer**: agent:test-engineer
- **Type**: Defect Report Template
- **Status**: TEMPLATE（无真实缺陷；不得把模板当作已登记缺陷）
- **Date**: 2026-10-19
- **Task**: `wp-121-device-acceptance`
- **Related plan**: [`device-acceptance-plan.md`](device-acceptance-plan.md)（DEVICE-ACCEPT-001）
- **Related evidence**: [`device-evidence-template.csv`](device-evidence-template.csv)
- **Validator**: [`../../tools/acceptance/validate_device_evidence.py`](../../tools/acceptance/validate_device_evidence.py)

> **使用规则**
>
> 1. 仅在设备用例结果为 `FAIL` 时创建缺陷；`BLOCKED` / `NOT_RUN` 不是缺陷，除非阻塞由产品/构建缺陷导致并有证据。
> 2. 复制本文件为 `DEF-<yyyyMMdd>-<NN>.md`，放在 `artifacts/75-device-acceptance/evidence/<case_id>/` 或用户缺陷系统。
> 3. 不得在缺陷中粘贴 Wi-Fi 口令、PoP、HMAC 密钥、IAM Token、私钥、完整邀请凭据或用户隐私数据。
> 4. 未脱敏的证据不得提交/共享；`redaction_confirmed` 必须为 `true` 才可进入复验/关闭。
> 5. 本模板不改变需求、契约、测试预期或 Gate 结论。

---

## 1. 基本信息

| 字段 | 值 |
|---|---|
| Defect ID | `DEF-<yyyyMMdd>-<NN>` |
| Title | `<简短、可检索的缺陷标题>` |
| Severity | `S1` / `S2` / `S3` / `S4`（定义见 §2） |
| Status | `OPEN` / `IN_PROGRESS` / `FIXED` / `RETEST_PENDING` / `CLOSED` / `ACCEPTED_RISK` |
| Case ID | `DA-xxx` |
| Requirement / Contract | `FR-xxx` / `NFR-x.x.x` / 契约或 ADR 条目 |
| First observed | `YYYY-MM-DD HH:MM`（设备本地时间/时区） |
| Reproducibility | `Always` / `Intermittent` / `Once` |
| Reporter / Owner | `<角色/姓名>` / `<责任人>` |
| Redaction confirmed | `true` / `false` |

## 2. 严重度定义

| 级别 | 定义 | 示例 |
|---|---|---|
| **S1** | 安全/数据/核心控制阻断；认证绕过、秘密泄露、错误控制、崩溃/ANR 阻塞主流程 | TLS 失败回退明文；重放被接受；门锁无证据显示已锁好；安装/启动失败 |
| **S2** | 主要功能不可用或有明显错误，但有绕行路径 | 配网取消卡死；云 Token 过期无提示；长英文遮挡关键按钮 |
| **S3** | 次要功能/文案/显示错误，不影响核心任务 | 状态来源标签错误；非关键文案缺失 |
| **S4** | 外观/一致性/建议，不构成验收阻断 | 间距、图标风格、非关键提示措辞 |

> 任何 S1/S2 未关闭或未书面接受，相关用例不得判定为用户验收完成。

## 3. 环境

| 字段 | 值 |
|---|---|
| Device model | `<型号>` |
| OS / API | `<HarmonyOS 版本> / API <level>` |
| Firmware | `<网关固件版本/commit>` |
| App revision | `<git commit>` |
| HAP SHA-256 | `<64 位 hex>` |
| Build mode / signing | `<release/debug；签名方式>` |
| Network | `<2.4GHz/5GHz；SSID 别名；同 LAN/远程>` |
| Cloud | `<IoTDA endpoint 脱敏；project/device 别名>` |
| Matrix ID | `M-01` / `M-02` / ... |
| Account | `<脱敏账号标识/角色>` |

## 4. 复现步骤

1. `<前置状态/数据>`
2. `<操作步骤 1>`
3. `<操作步骤 2>`
4. `<操作步骤 3>`
5. `<观察点>`

> 步骤必须可重复；避免“随便点几下”。如依赖特定设备/固件/网络，明确写出。

## 5. 预期行为

`<引用需求/契约/验收用例的预期；不要用实现现状反推预期>`

## 6. 实际行为

`<实际观察；包含错误码、状态、时间、是否崩溃/ANR>`

## 7. 证据

| 类型 | 路径/说明 | 脱敏确认 |
|---|---|---|
| 截图 | `artifacts/75-device-acceptance/evidence/<case_id>/01-xxx.png` | `true` / `false` |
| 录屏 | `.../02-xxx.mp4` | `true` / `false` |
| App 日志 | `.../03-app.redacted.log` | `true` / `false` |
| 网关日志 | `.../04-gateway.redacted.log` | `true` / `false` |
| 抓包/HAR | `.../05-http.redacted.txt` | `true` / `false` |
| 性能数据 | `.../06-metrics.csv` | `true` / `false` |

脱敏检查：

- [ ] 无 Wi-Fi 口令/预共享密钥
- [ ] 无 PoP 明文/二维码原图
- [ ] 无 HMAC/会话密钥
- [ ] 无 IAM Token/AK/SK
- [ ] 无证书私钥/密钥库/Profile 口令
- [ ] 无完整邀请凭据
- [ ] 无手机号/地址/账号密码等个人信息
- [ ] 截图/录屏中的敏感字段已不可逆遮挡

## 8. 影响与范围

| 项 | 值 |
|---|---|
| 受影响 FR/NFR | `<...>` |
| 受影响设备/固件/网络 | `<...>` |
| 是否阻断发布 | `是` / `否` / `待定` |
| 是否存在绕行 | `<说明>` |
| 是否涉及安全/隐私 | `是` / `否` |
| 是否可回归 | `是` / `否` |

## 9. 分类（不在未诊断时猜测根因）

| 分类 | 选择 |
|---|---|
| 产品行为缺陷 | `[ ]` |
| 测试/证据缺陷 | `[ ]` |
| 环境/设备/固件问题 | `[ ]` |
| 未知/待诊断 | `[ ]` |

> 若根因未知，先保留“未知/待诊断”，交给 `debug-specialist`；不要为了关闭缺陷而修改预期或弱化断言。

## 10. 修复与复验

| 字段 | 值 |
|---|---|
| Fix revision / HAP SHA-256 | `<commit / hash>` |
| Fix description | `<简述>` |
| Retest case | `DA-xxx` |
| Retest date | `YYYY-MM-DD` |
| Retest result | `PASS` / `FAIL` / `BLOCKED` |
| Retest evidence | `artifacts/75-device-acceptance/evidence/<case_id>/10-retest-*.log` |
| Regression run | `<受影响用例/命令/结果>` |
| Closed by / date | `<角色/姓名 / YYYY-MM-DD>` |
| User acceptance (if risk) | `<书面接受范围/日期/人>` |

关闭条件：

- 复验 `PASS`，证据完整且脱敏；或
- 用户书面接受为 `ACCEPTED_RISK`，并记录范围、影响与复审触发条件。

## 11. 备注

`<补充信息；不得包含秘密；可引用需求/契约/计划章节>`

---

*DEVICE-DEFECT-TEMPLATE-001 结束。复制后请替换所有 `<...>` 占位符并删除未使用的证据行。*
