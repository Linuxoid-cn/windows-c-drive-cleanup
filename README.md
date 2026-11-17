# windows-c-drive-cleanup

一个用于 DeepSeek Harness (DSH) 的 Windows C 盘安全清理技能。

- **只读扫描** → A/B/C 三级分类 → **DryRun 方案** → 用户确认 → **白名单删除** → 前后对比报告
- 脚本：`scripts/`（扫描 / 清理 / 验证 / 编排 / 自检）
- 规则：`resources/junk-catalog.json`（白名单）+ `junk-rules.md`（判定规则）
- 模板：`templates/`（扫描报告 / 清理报告）
- 使用说明：`USAGE.md`

## 快速开始

```powershell
cd scripts
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run-skill.ps1 -Phase scan
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run-skill.ps1 -Phase plan -Levels A,B
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run-skill.ps1 -Phase all -Levels A,B -Yes
```

## 安全

C 级（WinSxS、DriverStore、Program Files、用户文档、pagefile 等）永不删除；
删除必须显式传 `-Yes`；占用中文件自动跳过；白名单外路径一律不动。

## 安装到 DSH

把本目录复制到 `%USERPROFILE%\.dsh\skills\`（或 `%USERPROFILE%\.agents\skills\`），新会话自动发现。