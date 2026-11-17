# 贡献指南

感谢你愿意改进 `windows-c-drive-cleanup`。本项目最看重两件事：**安全**与**可解释**。

## 开始之前

- 读一遍 [`README.md`](README.md) 的"安全模型"与"维护指南"。
- 任何删除行为的改动都必须保持：白名单、A/B/C 分级、`-Yes` 确认、跳过占用文件。
- 不引入第三方依赖（脚本必须能在干净的 Windows 10/11 + PowerShell 5.1 上运行）。

## 开发环境

| 项目 | 要求 |
|---|---|
| 系统 | Windows 10/11（或在 CI 上运行） |
| PowerShell | 5.1 或 7.x |
| Git | 任意较新版本 |

```powershell
git clone https://github.com/Linuxoid-cn/windows-c-drive-cleanup.git
cd windows-c-drive-cleanup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-skill.ps1
```

看到 `SKILL VALID - N checks passed` 即可开始。

## 提交规范

使用 [Conventional Commits](https://www.conventionalcommits.org/)：

| 前缀 | 用途 |
|---|---|
| `feat:` | 新功能（新清理目标、新参数） |
| `fix:` | 修复缺陷 |
| `docs:` | 文档 |
| `chore:` | 构建、CI、依赖 |
| `refactor:` | 不改变行为的重构 |
| `test:` | 测试相关 |

示例：

```text
feat(catalog): add Intel shader cache target (B, low-medium)
fix(clean): skip files locked by running processes
docs(readme): describe maintenance workflow
```

## 修改清理规则

新增或调整清理目标时：

1. 在 `resources/junk-catalog.json` 增加/修改条目，必填：`id`、`name`、`level`、`risk`、`type`、`path` 或 `root`、`notes`。
2. 在 `resources/junk-rules.md` 对应等级章节写清判定理由、删除影响与恢复方式。
3. 通过准入检查表（`junk-rules.md` 第六节）逐条自检。
4. 在测试机执行：`scan → DryRun → Execute → verify`，确认报告数字合理。
5. 更新 `CHANGELOG.md` 的 `Unreleased`。

> 不允许把 C 级内容改成 A/B；不允许为了让测试通过而放宽安全校验。

## 代码风格

- 脚本保持 ASCII 变量名，面向用户的字符串可用中文。
- 新增函数写简短注释；复杂逻辑拆分为小函数。
- 保持 `Set-StrictMode` 之外的行为兼容 PowerShell 5.1。
- 修改模板时，确保脚本替换的占位符与模板一致（`validate-skill.ps1` 会检查）。

## 测试清单

提交 PR 前请确认：

- [ ] `scripts/validate-skill.ps1` 通过
- [ ] 扫描脚本在干净环境可运行（`-Quick` 与默认模式各一次）
- [ ] DryRun 输出与实际删除统计逻辑一致
- [ ] `Execute` 仍要求 `-Yes`；`-Levels C` 仍被拒绝
- [ ] 占用中文件仍被跳过，未新增强制删除
- [ ] README / USAGE / CHANGELOG 已同步

## 提交 PR

1. Fork 仓库并从 `main` 建分支：`feat/xxx` 或 `fix/xxx`。
2. 提交前跑一次自检。
3. PR 描述中写明：改了什么、为什么、如何在真实机器上验证、风险点。
4. CI（`.github/workflows/validate.yml`）必须通过。

## 安全问题

如果你发现可能导致误删的缺陷，请先开 Issue 描述复现路径，避免在公开 PR 中附上危险命令。
