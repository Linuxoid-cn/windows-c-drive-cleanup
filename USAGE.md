# 使用说明（USAGE）

**Skill 名称**：`windows-c-drive-cleanup`
**安装位置**：`%USERPROFILE%\.dsh\skills\windows-c-drive-cleanup`（本机为 `C:\Users\Kernix\.dsh\skills\windows-c-drive-cleanup`）
**发现方式**：DSH 用户 Skill 根目录（`$DSH_HOME/skills` 或 `~/.agents/skills`），新会话自动进入 Skill 目录，无需重启。

---

## 1. 依赖与前置条件

| 项目 | 要求 |
|---|---|
| 系统 | Windows 10/11（PowerShell 5.1 即可） |
| 权限 | 普通用户即可；管理员可处理系统目录（可选） |
| 执行策略 | 用 `-ExecutionPolicy Bypass` 运行脚本（见下） |
| 网络 | 不需要 |

> 默认执行策略可能禁止运行未签名脚本；本 Skill 不修改系统策略，统一用：
> `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <脚本> <参数>`

### 1.1 在其他电脑上使用（可移植性）

**可以，整个文件夹直接拷走即可。** 目录内没有写死本机用户名或绝对路径：脚本用 `$PSScriptRoot` 定位资源、用 `%LOCALAPPDATA%`/`%USERPROFILE%` 展开目标，所有路径都在 `resources/junk-catalog.json` 中用环境变量描述。

| 场景 | 做法 |
|---|---|
| 目标机已装 DSH | 把 `windows-c-drive-cleanup` 文件夹放到 `%USERPROFILE%\.dsh\skills\`（或 `%USERPROFILE%\.agents\skills\`），新会话自动发现；也可放项目级 `<项目>\.dsh\skills\` |
| 目标机没装 DSH | 仍可手动使用：解压后进入 `scripts` 目录，按第 2 节命令运行 |
| 从 ZIP 安装 | 解压到上述目录，保证顶层是 `windows-c-drive-cleanup\` |

**每次在新机器上建议先跑自检**：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\validate-skill.ps1
```

机器差异说明：

- 管理员权限：半受限；非管理员会跳过 `C:\Windows\Temp`、SoftwareDistribution、WER 等系统项（报告中标注）。
- 应用专属条目（如 `app_shell_cache_6383`、DSH 更新待安装包）：其他电脑上不存在时会显示 `missing`，属正常，不影响清理。
- 控制台中文乱码：先执行 `chcp 65001`，或直接用 Windows Terminal / PowerShell 7。
- 脚本为 UTF-8（带 BOM），Windows PowerShell 5.1 可直接读取中文参数与提示。

---

## 2. 快速开始

```powershell
cd "$env:USERPROFILE\.dsh\skills\windows-c-drive-cleanup\scripts"

# ① 只读扫描（生成 scan.json + scan-report.md）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run-skill.ps1 -Phase scan

# ② 生成清理方案（DryRun，不删除）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run-skill.ps1 -Phase plan -Levels A,B

# ③ 用户确认后执行（会删除，必须带 -Yes）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run-skill.ps1 -Phase all -Levels A,B -Yes
```

或者一步到位：`-Phase all` 默认只做到"方案"就停下等确认；加 `-Yes` 才会继续删除并验证。

---

## 3. 脚本参考

### 3.1 scan-c-drive.ps1（只读）

| 参数 | 默认 | 说明 |
|---|---|---|
| `-OutputDir` | `%LOCALAPPDATA%\C-Drive-Cleanup\runs\<时间戳>` | 输出目录 |
| `-CatalogPath` | `..\resources\junk-catalog.json` | 白名单 |
| `-Quick` | 关 | 只扫磁盘 + 缓存目标，跳过一级目录（约 1–2 分钟） |
| `-Breakdown` | 关 | 追加主要目录下钻（较慢） |
| `-IncludeProtected` | 关 | 统计 C 级受保护目录大小（较慢） |

输出：`scan.json`、`scan-report.md`

### 3.2 clean-c-drive.ps1（DryRun / Execute）

| 参数 | 默认 | 说明 |
|---|---|---|
| `-Mode` | `DryRun` | `DryRun` 只统计；`Execute` 真删除 |
| `-Levels` | `A` | 可 `A,B`；`C` 会被拒绝并退出码 3 |
| `-IncludeMedium` | 关 | 包含 B 级 risk=medium 的谨慎项 |
| `-Yes` | 关 | Execute 必填，否则退出码 2 |
| `-MaxBytes` | 0 | 删除量上限，超过即停止 |
| `-OutputDir` | 时间戳目录 | 输出目录 |

输出：`clean-result-dryrun.json` 或 `clean-result-execute.json`

### 3.3 verify-cleanup.ps1（验证）

| 参数 | 默认 | 说明 |
|---|---|---|
| `-RunDir` | 最新 runs 目录 | 含 scan.json + clean-result-execute.json |
| `-OutputDir` | 同 RunDir | 报告目录 |

输出：`verification.json`、`cleanup-report.md`

### 3.4 run-skill.ps1（编排）

| 参数 | 默认 | 说明 |
|---|---|---|
| `-Phase` | `all` | `scan`/`plan`/`clean`/`verify`/`all` |
| `-Levels` | `A` | 清理等级 |
| `-IncludeMedium` | 关 | 包含谨慎项 |
| `-Yes` | 关 | clean/all 删除必需 |
| `-Quick` / `-Breakdown` | 关 | 传给扫描阶段 |
| `-RunDir` | 新建时间戳目录 | 复用同一运行目录 |

### 3.5 validate-skill.ps1（完整性自检）

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\validate-skill.ps1
```

检查必需文件、SKILL.md frontmatter、catalog JSON、脚本语法、模板占位符和安全关键字；全部通过输出 `SKILL VALID`（退出码 0），否则列出问题（退出码 1）。

---

## 4. 典型会话流程（模型侧）

1. 用户提出"清理 C 盘"。
2. 模型加载本 Skill，执行 `run-skill.ps1 -Phase scan`（只读）。
3. 读取 `scan.json`/`scan-report.md`，按 A/B/C 汇总并展示。
4. 执行 `run-skill.ps1 -Phase plan -Levels A,B`（DryRun），展示精确清单。
5. **等待用户确认**。
6. 用户确认后执行 `run-skill.ps1 -Phase all -Levels ... -Yes`。
7. 读取 `cleanup-report.md`，按模板向用户汇报清理前后对比。

---

## 5. 输出文件

```
<RunDir>/
├── scan.json                  # 扫描数据（机器可读）
├── scan-report.md             # 扫描报告
├── clean-result-dryrun.json   # 方案（DryRun）
├── clean-result-execute.json  # 实际删除记录
├── verification.json          # 前后对比数据
└── cleanup-report.md          # 最终清理报告
```

---

## 6. 安全边界（重要）

- **只删白名单**：`resources/junk-catalog.json` 中 level=A/B 的路径；其他一律不动。
- **C 级永不删除**：即使传入 `-Levels C` 也会被拒绝（退出码 3）。
- **Execute 需 `-Yes`**：防止误调用。
- **占用中文件跳过**：不结束进程、不强制解锁。
- **不跟随符号链接/联结点**：避免跨区误删。
- **不改系统配置**：不碰注册表、休眠、虚拟内存、系统还原、Defender。
- **危险路径兜底**：`C:\`、`C:\Windows`、`C:\Users`、`Program Files`、`ProgramData` 等即使误入白名单也会被拒绝。

---

## 7. 常见问题

| 现象 | 原因/处理 |
|---|---|
| `cannot be loaded ... not digitally signed` | 用 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...` |
| 某些目录显示 denied | 非管理员无法访问系统目录；属预期，报告中说明 |
| `failed=NN` | 文件被占用，已跳过；关闭相关应用后重跑可清理 |
| 实际释放与删除统计不一致 | 运行中应用同时写入缓存，属正常；以磁盘剩余变化为准 |
| 扫描很慢 | 用 `-Quick`；或跳过 `-Breakdown`/`-IncludeProtected` |
| 想清理系统级空间 | 需管理员 + 单独确认：DISM 组件清理、休眠文件、虚拟内存、系统还原、容器镜像 |

---

## 8. 扩展白名单

1. 编辑 `resources/junk-catalog.json`，新增 target（`level`、`risk`、`type`、`path`/`root`）。
2. 在 `resources/junk-rules.md` 对应等级补充理由与影响。
3. 先跑 `clean-c-drive.ps1 -Mode DryRun` 验证统计，再执行。

> 新增前请对照 `junk-rules.md` 第六节的"准入检查表"。

---

## 9. 实测记录

2026-11-17 在 Windows 11 Pro build 26200 实测通过：

| 项目 | 结果 |
|---|---|
| 扫描 | 500 GB 盘，识别 A+B 24.43 GB / 55,707 文件 |
| 清理 | 删除 25.03 GB / 55,574 文件，144 个占用中文件跳过 |
| 释放 | 剩余 288.18 GB → 312.92 GB（+24.74 GB） |
| 安全 | 未结束进程、未触碰 C 级与用户数据，全部应用正常运行 |
