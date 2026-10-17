# 旧 615 条内联字典迁移边界（T-10）

- **Producer**: agent:implementation-engineer
- **Task**: T-10 / `wp-031-i18n`
- **上游**: I18N-DESIGN §5；DES-B §7.4.3；CB 术语表；`artifacts/00-project-intake/inventory.md` L170/L259
- **源文件**: `input/existing/original_app/service/I18nService.ets`
  （SHA-256 `dc8e5e4dcbb299d2aa5fdafb270b1d431a20f1b3bc26f18b2b82993fa8fd2c44`，685 行 / 615 case）
- **登记表**: `legacy-migration.csv`（615 行，列：旧中文/旧英文/分类/目标存储/目标键/审查结论/负责人/批次/备注）

## 1. 裁定（不变）

1. **禁止机械迁移中文键**：旧 `case '<中文>'` 只能作为翻译记忆；新键必须是 I18N-DESIGN §3.3 的语义化点分键。
2. **禁止整体导入**旧 `I18nService.ets`；新代码库从零建立键空间。
3. 逐条分类：A 迁移（重键）/ B 重译 / C 废弃 / D 排除；英文必须按 CB 术语表复核（gateway/device/room/family/ACK/影子）。
4. 一个逻辑文案只存在于一个存储（rawfile 或 `string.json`）。
5. 品牌名（Gree/Haier/Midea/Generic）作为数据显示或 `brand.*` 专名表，不进入业务分支。

## 2. T-10 已落地（10 条）

| 旧中文 | 分类 | 目标存储 | 目标键 |
|---|---|---|---|
| 取消 | A | `string.json` | `common_cancel` |
| 删除 | A | `string.json` | `common_delete` |
| 成功 | A | `string.json` | `common_success` |
| 编辑 | A | `string.json` | `common_edit` |
| 查看 | A | `string.json` | `common_view` |
| 失败 | A | `string.json` | `common_failed` |
| 刷新失败，请重试 | A | `string.json` | `common_refresh_failed` |
| 保存失败，请重试 | A | `string.json` | `common_save_failed` |
| 设备离线 | A | `rawfile/i18n` | `errors.gateway.device_offline` |
| Wi-Fi 认证失败，请检查密码 | A | `rawfile/i18n` | `provisioning.error.auth_error` |

## 3. 剩余批次（登记表统计）

| 分类 | 数量 | 处置 |
|---|---|---|
| A 迁移（待 T-17/T-18） | 606 | 按页面/组件抽取语义键；英文先复核再沿用或重译 |
| C 废弃（启发式） | 6 | 版本/关于/旧版本机/模拟器关键词；T-17/T-18 复核后仅存档 |
| D 排除（品牌） | 3 | Gree/格力、Haier/海尔、Midea/美的 |
| **合计** | **615** | |

负责人分布：T-17 = 521，T-18 = 75，T-10 = 10，LEGACY-001（C/D）= 9。

- **T-17**：首页/房间/设备/门锁/空调/场景/家庭/成员/邀请/配网等页面与组件。
- **T-18**：设置/语言/通知/权限/我的/云端/远程连接/安全配置/账号/档案等应用壳与设置。
- `目标存储` 为启发式建议：错误/状态/数据驱动标签 → `rawfile/i18n`；纯静态 UI 字面量 → `string.json`。
- 所有未落地行 `审查结论=PENDING_REVIEW`；不得把本表当成已完成迁移。

## 4. 完成判据

1. v1 全部 UI/代码路径文本经 CHK-01..CHK-09；
2. 零硬编码（CHK-07 UI 阻断项为 0）；
3. key parity 100%（CHK-01/02），无缺失键（CHK-06）；
4. 旧字典不被任何构建产物引用；
5. 英文文案按 CB 术语表审查（翻译审查记录）；
6. 语言切换后 `$r` 与 `t()` 同步、无重启（设备/UI 测试）。

## 5. 说明

- 本表由脚本从源文件逐行提取并按关键词启发式生成；C/D 分类与 owner 需 T-17/T-18 逐条复核。
- 登记表落在 `entry/src/test/i18n/`（DES-B 建议 `tools/i18n/`，但 T-10 写范围不含 `tools/`）。
