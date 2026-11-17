---
name: windows-c-drive-cleanup
description: "Scan, analyze, and safely clean junk files on a Windows C: drive: Windows and user temp, app and browser caches, GPU shader caches, package-manager caches, Windows Update leftovers, crash dumps, error reports, and the recycle bin. Read-only scan first, A/B/C risk classification, dry-run plan, explicit user confirmation, then deletion that skips in-use files, followed by before/after verification and a report."
whenToUse: "用户要求扫描或清理 C 盘、释放磁盘空间、找出占用异常的目录、清理临时文件/缓存/更新残留/日志/回收站时使用。"
---

# Windows C 盘清理 Skill

基于 2026-11-17 在本机实测通过的清理流程封装：扫描 → 分析 → 方案 → 确认 → 删除 → 验证 → 报告。

## 一、核心安全原则（任何情况下不可违反）

1. **默认只读**：调用本 Skill 时先扫描，绝不直接删除。删除必须经过用户明确确认。
2. **A/B/C 三级制度**：A 级可直接清理；B 级必须逐项确认；C 级禁止删除。
3. **未知即保留**：不在 `resources/junk-catalog.json` 白名单内的路径一律不动，不猜测、不递归删除未知目录。
4. **跳过占用中文件**：删除失败（文件被占用）就跳过并记录，**不结束任何进程**，不使用强制解锁工具。
5. **不使用强删命令处理未知文件**：不使用 `rd /s /q`、`del /f /s /q` 作用于未知路径；脚本只删除目录树内的文件，路径来自白名单。
6. **不修改系统配置**：不改注册表、不改系统设置、不卸载软件、不关闭 Defender/防火墙、不调整虚拟内存和休眠配置（如需系统级清理，单独提示用户并需要管理员权限与明确同意）。
7. **删除前必须展示清单并取得确认**：至少展示类别、路径、大小、风险等级和总计。
8. **可回滚优先**：能用"重新生成"替代删除的缓存（浏览器/着色器/包管理器）才纳入 B 级。

## 二、适用场景

- 用户说"C 盘满了/清理 C 盘/释放空间/清一下缓存/清理临时文件"。
- 需要找出 C 盘占用异常大的目录。
- 清理 Windows 更新残留、错误报告、转储、回收站、浏览器与 GPU 缓存。

不适用：磁盘分区、系统重装、病毒查杀、软件卸载、注册表清理。

## 三、目录结构

```
windows-c-drive-cleanup/
├── SKILL.md                     # 本文件：流程与规则
├── USAGE.md                     # 使用说明（安装、命令、排错）
├── scripts/
│   ├── scan-c-drive.ps1         # 阶段1：只读扫描（磁盘+目录+缓存统计）
│   ├── clean-c-drive.ps1        # 阶段3/4：DryRun 方案 + Execute 安全删除
│   ├── verify-cleanup.ps1       # 阶段5：复测、对比、生成清理报告
│   ├── run-skill.ps1            # 编排器：一键 scan/plan/clean/verify/all
│   └── validate-skill.ps1       # 完整性自检（文件/JSON/语法/模板/安全关键字）
├── resources/
│   ├── junk-catalog.json        # 机器可读的清理目标白名单（A/B/C）
│   └── junk-rules.md            # 垃圾识别规则与判定标准
└── templates/
    ├── scan-report-template.md  # 扫描报告模板
    └── cleanup-report-template.md # 清理报告模板
```

## 四、执行流程

> 所有脚本均为 PowerShell，独立可运行；Windows 默认执行策略可能阻止脚本，统一用：
> `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <脚本路径> <参数>`

### 阶段 1：扫描（只读，不删除）

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\scan-c-drive.ps1 -OutputDir <输出目录>
```

- 输出 `scan.json`（磁盘、根文件、一级目录、缓存目标统计、受保护目录统计）与 `scan-report.md`。
- 加 `-Quick` 只做磁盘+缓存目标（约 1–2 分钟）；默认含一级目录扫描（几分钟）；加 `-Breakdown` 追加主要目录下钻（更慢）。
- 扫描不做任何写操作，只读取文件元数据。

### 阶段 2：分析（模型完成）

读取 `scan.json`，结合 `resources/junk-rules.md` 把结果分为：

| 等级 | 含义 | 处理 |
|---|---|---|
| A | 可安全清理 | 展示后可直接执行（仍需用户确认整批） |
| B | 需要进一步判断 | 逐项说明影响，用户勾选后才删 |
| C | 禁止自动删除 | 只展示大小，永不删除 |

向用户输出：C 盘现状、各类占用、预计可释放空间、风险等级、建议顺序。

### 阶段 3：制定方案（DryRun）

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\clean-c-drive.ps1 -Mode DryRun -Levels A,B -IncludeMedium -OutputDir <输出目录>
```

- 只统计将删除的文件数量与字节数，输出 `clean-result-dryrun.json`。
- 默认只处理 A 级；`-Levels A,B` 才包含 B 级；`-IncludeMedium` 才包含 B 级中 risk=medium 的谨慎项。
- 向用户展示清单并**等待确认**。

### 阶段 4：执行（用户确认后）

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\clean-c-drive.ps1 -Mode Execute -Levels A,B -Yes -OutputDir <输出目录>
```

- 必须带 `-Yes`，否则脚本拒绝执行。
- 只删除白名单目录内的文件；占用中文件跳过；结束时输出 `clean-result-execute.json`。
- 不允许对 C 级路径使用任何删除参数。

### 阶段 5：验证与报告

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\verify-cleanup.ps1 -RunDir <输出目录>
```

- 复测目标目录、重新读取剩余空间、对比前后差异，输出 `verification.json` 与 `cleanup-report.md`。
- 使用 `templates/cleanup-report-template.md` 的格式向用户汇报。

### 一键编排（推荐）

```powershell
# 仅扫描 + 方案，停在确认前
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\run-skill.ps1 -Phase all -Levels A,B -OutputDir <输出目录>

# 用户确认后，带 -Yes 完整执行
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\run-skill.ps1 -Phase all -Levels A,B -Yes -OutputDir <输出目录>
```

## 五、垃圾识别规则（摘要）

完整规则见 `resources/junk-rules.md`，机器清单见 `resources/junk-catalog.json`。

- **A 级**：`%LOCALAPPDATA%\Temp`、`C:\Windows\Temp`、缩略图缓存、INetCache、已知临时日志。
- **B 级**：浏览器缓存、GPU 着色器缓存（NVIDIA DXCache/GLCache、AMD DxcCache、D3DSCache）、包管理器缓存（npm/pnpm/yarn/pip/nuget）、Windows 更新下载缓存、WER 错误报告、CrashDumps、回收站、应用缓存（需逐项说明）。
- **C 级**：WinSxS、DriverStore、Windows Installer、Package Cache、.NET NativeImages、Program Files、用户文档/下载/桌面、pagefile.sys、hiberfil.sys、System Volume Information、Windows Containers/Sandbox 镜像层、开发工具与代码。

判定原则：文件可再生成、目录有明确定义的缓存语义、删除不影响系统/软件完整性 → 才能进入 A/B；否则保留。

## 六、异常处理与保留策略

| 情况 | 处理 |
|---|---|
| 文件被进程占用 | 跳过，计入 `failed`，不结束进程、不重试强制删除 |
| 路径不可访问（权限/系统保护） | 跳过并记录，提示需要管理员权限 |
| 目录不存在 | 标记 `missing`，不算错误 |
| 目标不在白名单 | 拒绝删除，记录 `blocked` |
| 扫描枚举异常 | 计数并继续，不中断整体扫描 |
| 未知文件/未知目录 | 一律保留，只在报告中列出 |
| 删除过程中脚本异常 | 已删文件计入结果，未删文件保持原状，继续下一目标 |

## 七、管理员权限说明

非管理员运行时以下项目无法处理（脚本会报告 `denied`）：

- `C:\Windows\Temp`、`C:\Windows\SoftwareDistribution`、`C:\Windows\Logs`、WER、Prefetch、DeliveryOptimization；
- WinSxS 维护（`DISM /StartComponentCleanup`）、系统还原点、休眠文件、虚拟内存。

这些属于系统级操作，必须由用户明确同意并在管理员会话中执行；本 Skill 默认只报告不执行。

## 八、输出约定

- 所有产物（scan.json、clean-result-*.json、verification.json、报告 md）写入 `-OutputDir` 指定的目录。
- 默认输出目录：`%LOCALAPPDATA%\C-Drive-Cleanup\runs\<时间戳>`。
- 报告格式遵循 `templates/` 下的模板；向用户汇报时至少给出：清理前剩余、发现垃圾总量、实际删除数量、实际释放空间、清理后剩余、未清理项及原因。

## 九、完成标准（自检清单）

- [ ] 扫描阶段零写入，产出 scan.json + scan-report.md
- [ ] 已按 A/B/C 分级并向用户展示
- [ ] 删除前已取得用户明确确认（并记录确认的等级范围）
- [ ] Execute 模式带 `-Yes`，未触碰 C 级与白名单外路径
- [ ] 占用中文件被跳过而非强删
- [ ] verify 产出了前后对比与未清理原因
- [ ] 报告中明确写出实际释放空间与剩余空间
