# 设备验收证据目录

- **Producer**: agent:test-engineer
- **Related plan**: [`../device-acceptance-plan.md`](../device-acceptance-plan.md)（DEVICE-ACCEPT-001）
- **Related CSV**: [`../device-evidence-template.csv`](../device-evidence-template.csv)
- **Defect template**: [`../defect-report-template.md`](../defect-report-template.md)
- **Validator**: [`../../../tools/acceptance/validate_device_evidence.py`](../../../tools/acceptance/validate_device_evidence.py)

## 目录规则

为每个执行的用例创建子目录，目录名必须等于 `case_id`：

```text
evidence/
├── DA-001/
│   ├── 01-hdc-targets.txt
│   ├── 02-hap-sha256.txt
│   ├── 03-install.log
│   └── 04-launch.png
├── DA-002/
└── ...
```

文件名：`<两位序号>-<内容>.<扩展名>`，例如 `01-permission.png`、`02-p95.csv`、`03-flow.mp4`。
`BLOCKED` 用例至少放 `00-blocked.txt`，写明阻塞原因、已检查的环境项与下一步。

## 必须遵守

- 不得放入 Wi-Fi 口令、PoP 明文、HMAC/会话密钥、IAM Token、私钥、完整邀请凭据或用户隐私数据。
- 截图/日志/录屏先脱敏，再把 CSV 的 `redaction_confirmed` 设为 `true`。
- 首次失败证据不得覆盖；复验使用 `10-retest-<yyyyMMdd>.*` 等新文件。
- 证据路径写入 CSV 的 `evidence_path` 列，例如 `artifacts/75-device-acceptance/evidence/DA-001/`。

## 执行后校验

```bash
python3 tools/acceptance/validate_device_evidence.py \
  artifacts/75-device-acceptance/device-evidence-template.csv
```

详细用例、前置条件、判定标准与缺陷流程见计划正文。
