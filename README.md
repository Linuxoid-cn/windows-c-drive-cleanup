# windows-c-drive-cleanup

> 一个面向 **DeepSeek Harness (DSH)** 的 Windows C 盘安全清理技能（AI Skill）。
> 先只读扫描、再分级评估、DryRun 预览、用户确认后才删除，最后自动生成前后对比报告。

[![validate](https://github.com/Linuxoid-cn/windows-c-drive-cleanup/actions/workflows/validate.yml/badge.svg)](https://github.com/Linuxoid-cn/windows-c-drive-cleanup/actions/workflows/validate.yml)
![platform](https://img.shields.io/badge/platform-Windows%2010%2F11-0078D4)
![powershell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)
![license](https://img.shields.io/badge/license-Apache--2.0-blue)

---

## 目录

- [为什么需要它](#为什么需要它)
- [核心特性](#核心特性)
- [安全模型：A / B / C 三级](#安全模型a--b--c-三级)
- [目录结构](#目录结构)
- [快速开始](#快速开始)
- [工作流（五个阶段）](#工作流五个阶段)
- [脚本参考](#脚本参考)
- [清理范围](#清理范围)
- [输出与报告](#输出与报告)
- [安装到 DSH](#安装到-dsh)
- [维护指南](#维护指南)
- [常见问题](#常见问题)
- [已知限制](#已知限制)
- [贡献](#贡献)
- [许可证](#许可证)

---

## 为什么需要它

C 盘被临时文件、浏览器缓存、GPU 着色器缓存、更新残留逐步占满；市面上的"一键清理"工具经常**误删用户数据或系统文件**。
本项目把"哪些能删、删之前要确认什么、删完怎么验证"固化成可复用的脚本与规则，供 AI 助手调用，也供人类手动执行。

设计目标：

1. **零误删**：只删白名单内的缓存/临时目录，白名单外一律保留。
2. **可解释**：每个目标都有等级（A/B/C）、风险（low/medium/high）与说明。
3. **可验证**：删除前后对比磁盘剩余空间，报告实际释放量。
4. **可移植**：纯 PowerShell 5.1 + JSON，无第三方依赖，拷到任意 Windows 10/11 可用。

---

## 核心特性

| 特性 | 说明 |
|---|---|
| 只读扫描 | `scan-c-drive.ps1` 不写任何文件（除报告），统计磁盘、目录、缓存 |
| 分级清理 | A 级可直接清、B 级需确认、C 级永不删除 |
| 干跑（DryRun） | 先统计将删除的文件数/字节数，输出方案 JSON |
| 显式确认 | `Execute` 必须带 `-Yes`，否则拒绝执行 |
| 占用跳过 | 被进程占用的文件自动跳过，**不结束进程、不强制解锁** |
| 链接防护 | 跳过 ReparsePoint（符号链接/联结点），避免跨区误删 |
| 白名单机制 | 目标全部来自 `resources/junk-catalog.json`，未知路径不碰 |
| 前后对比 | `verify-cleanup.ps1` 生成真实释放量与剩余空间 |
| 自检 | `validate-skill.ps1` 校验文件、JSON、语法、模板、安全关键字 |
| CI | GitHub Actions 在每次 push/PR 自动跑自检 |

---

## 安全模型：A / B / C 三级

| 等级 | 定义 | 处理方式 |
|---|---|---|
| **A** | 删除后系统/应用可自动重建，且不含用户数据 | 展示后可批量清理（仍需整批确认） |
| **B** | 删除可恢复代价低，但会影响使用体验或需要重新下载 | 逐项说明影响，用户确认后才删 |
| **C** | 系统/软件完整性资产、用户数据、未知文件 | **禁止删除**，只统计不处理 |

判定原则：**可再生成 + 语义明确 + 不影响完整性** 才能进入 A/B；否则一律保留。

完整规则见 [`resources/junk-rules.md`](resources/junk-rules.md)，机器白名单见 [`resources/junk-catalog.json`](resources/junk-catalog.json)。

---

## 目录结构

```text
windows-c-drive-cleanup/
├── SKILL.md                     # DSH 技能主指令（流程、规则、自检清单）
├── USAGE.md                     # 使用说明（安装、命令、参数、排错）
├── README.md                    # 本文件（项目介绍与维护指南）
├── CONTRIBUTING.md              # 贡献指南
├── CHANGELOG.md                 # 版本记录
├── scripts/
│   ├── scan-c-drive.ps1         # 阶段1：只读扫描
│   ├── clean-c-drive.ps1        # 阶段3/4：DryRun 方案 + Execute 安全删除
│   ├── verify-cleanup.ps1       # 阶段5：复测、对比、生成报告
│   ├── run-skill.ps1            # 编排器：scan → plan → (确认) → clean → verify
│   └── validate-skill.ps1       # 完整性自检
├── resources/
│   ├── junk-catalog.json        # 清理目标白名单（A/B/C）
│   └── junk-rules.md            # 识别规则、判定标准、准入检查表
├── templates/
│   ├── scan-report-template.md  # 扫描报告模板
│   └── cleanup-report-template.md # 清理报告模板
└── .github/workflows/validate.yml # CI 自检
```

---

## 快速开始

> Windows 默认执行策略可能阻止未签名脚本，统一用 `-ExecutionPolicy Bypass`。

```powershell
# 1) 只读扫描
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-skill.ps1 -Phase scan

# 2) 生成清理方案（DryRun，不删除）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-skill.ps1 -Phase plan -Levels A,B

# 3) 确认后执行（必须 -Yes）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-skill.ps1 -Phase all -Levels A,B -Yes

# 4) 完整性自检
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-skill.ps1
```

不带 `-Yes` 时 `-Phase all` 会停在"方案"阶段，等待你确认——这是默认安全行为。

---

## 工作流（五个阶段）

```text
scan（只读） → analyze（模型分级） → plan（DryRun） → 用户确认 → clean（执行） → verify（对比报告）
```

| 阶段 | 命令 | 产物 |
|---|---|---|
| 1 扫描 | `scan-c-drive.ps1` | `scan.json`、`scan-report.md` |
| 2 分析 | 由 AI/人工按 A/B/C 分级 | 分级摘要 |
| 3 方案 | `clean-c-drive.ps1 -Mode DryRun` | `clean-result-dryrun.json` |
| 4 执行 | `clean-c-drive.ps1 -Mode Execute -Yes` | `clean-result-execute.json` |
| 5 验证 | `verify-cleanup.ps1` | `verification.json`、`cleanup-report.md` |

---

## 脚本参考

### scan-c-drive.ps1（只读）

| 参数 | 默认 | 说明 |
|---|---|---|
| `-OutputDir` | `%LOCALAPPDATA%\C-Drive-Cleanup\runs\<时间戳>` | 输出目录 |
| `-CatalogPath` | `..\resources\junk-catalog.json` | 白名单路径 |
| `-Quick` | 关 | 只扫磁盘 + 缓存目标（约 1–2 分钟） |
| `-Breakdown` | 关 | 追加主要目录下钻（较慢） |
| `-IncludeProtected` | 关 | 统计 C 级受保护目录大小（较慢） |

### clean-c-drive.ps1（DryRun / Execute）

| 参数 | 默认 | 说明 |
|---|---|---|
| `-Mode` | `DryRun` | `Execute` 才真正删除 |
| `-Levels` | `A` | 可写 `A,B`；写 `C` 会被拒绝（退出码 3） |
| `-IncludeMedium` | 关 | 包含 B 级 risk=medium 的谨慎项 |
| `-Yes` | 关 | `Execute` 必填，否则退出码 2 |
| `-MaxBytes` | 0 | 删除量上限（超过即停止） |
| `-OutputDir` | 时间戳目录 | 输出目录 |

### verify-cleanup.ps1（验证）

| 参数 | 默认 | 说明 |
|---|---|---|
| `-RunDir` | 最新 runs 目录 | 含 `scan.json` + `clean-result-execute.json` |
| `-OutputDir` | 同 RunDir | 报告目录 |

### run-skill.ps1（编排）

| 参数 | 默认 | 说明 |
|---|---|---|
| `-Phase` | `all` | `scan` / `plan` / `clean` / `verify` / `all` |
| `-Levels` | `A` | 清理等级 |
| `-IncludeMedium` | 关 | 包含谨慎项 |
| `-Yes` | 关 | clean/all 删除必需 |
| `-Quick` / `-Breakdown` | 关 | 传给扫描阶段 |
| `-RunDir` | 新建时间戳目录 | 复用同一运行目录 |

### validate-skill.ps1（自检）

无参数。检查必需文件、frontmatter、catalog 结构、脚本语法、模板占位符、安全关键字；通过输出 `SKILL VALID`，失败退出码 1。

---

## 清理范围

| 等级 | 典型目标 |
|---|---|
| A | `%LOCALAPPDATA%\Temp`、`C:\Windows\Temp`、缩略图/图标缓存、INetCache |
| B | NVIDIA DXCache/GLCache、AMD DxcCache、D3DSCache、Edge/Chrome/Brave/Firefox 缓存、Steam htmlcache、npm/pnpm/Yarn/pip/NuGet 缓存、WER、CrashDumps、Windows 更新下载缓存、回收站 |
| C | WinSxS、DriverStore、Windows Installer、Package Cache、NativeImages、Windows Containers、Program Files、用户文档/下载/桌面、pagefile/hiberfil、事件日志、System Volume Information |

> 完整清单与风险说明见 `resources/junk-rules.md`。

---

## 输出与报告

每次运行生成独立目录：

```text
<RunDir>/
├── scan.json
├── scan-report.md
├── clean-result-dryrun.json
├── clean-result-execute.json
├── verification.json
└── cleanup-report.md
```

清理报告包含：C 盘容量、清理前后剩余空间、实际释放空间、每类清理量、跳过文件数、未清理项及原因。

---

## 安装到 DSH

把整个目录放入任一 DSH 技能根目录（新会话自动发现，无需重启）：

| 作用域 | 路径 |
|---|---|
| 用户（推荐） | `%USERPROFILE%\.dsh\skills\windows-c-drive-cleanup` |
| 用户（共享） | `%USERPROFILE%\.agents\skills\windows-c-drive-cleanup` |
| 项目级 | `<项目>\.dsh\skills\windows-c-drive-cleanup` |

没有安装 DSH 也能用：直接按"快速开始"运行脚本即可。

---

## 维护指南

### 分支与提交

- `main` 始终可运行；功能/修复走 `feat/<name>`、`fix/<name>` 分支后合并。
- 提交信息遵循 [Conventional Commits](https://www.conventionalcommits.org/)：
  `feat:`、`fix:`、`docs:`、`chore:`、`refactor:`、`test:`。
- 每次提交前本地跑一次自检：

  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-skill.ps1
  ```

### 版本与发布

- 版本号记录在 `CHANGELOG.md`，采用语义化版本（`MAJOR.MINOR.PATCH`）。
- 发布步骤：
  1. 更新 `CHANGELOG.md` 的 `Unreleased` → 新版本号与日期；
  2. 跑 `validate-skill.ps1`，确认 `SKILL VALID`；
  3. 提交 `chore(release): vX.Y.Z`；
  4. 打 tag：`git tag vX.Y.Z && git push --tags`；
  5. 在 GitHub Releases 写变更摘要，附可用 ZIP（`git archive` 或目录压缩）。

### 新增/调整清理规则

1. 在 `resources/junk-catalog.json` 增加条目（`id`、`name`、`level`、`risk`、`type`、`path`/`root`、`notes`）。
2. 在 `resources/junk-rules.md` 对应等级补充判定理由与影响说明。
3. 对照准入检查表（见规则文件第六节）自问：是否可再生成？是否含用户数据？是否影响软件完整性？
4. 先 `-Mode DryRun` 验证统计，再在测试机执行。
5. 更新 `CHANGELOG.md`。

### 测试

| 层级 | 内容 |
|---|---|
| 静态 | `validate-skill.ps1`：文件、JSON、语法、模板、安全关键字 |
| 功能 | 扫描 → DryRun → Execute（测试机）→ verify，确认报告数字合理 |
| 回归 | 修改模板后检查占位符全部被替换；修改 catalog 后检查 C 级仍被拦截 |
| CI | GitHub Actions `validate.yml` 在 Windows 上自动执行自检 |

### 兼容性

- Windows 10 / 11 / Server 2016+，Windows PowerShell 5.1 与 PowerShell 7 均可用。
- 不依赖第三方模块、不需要联网、不修改注册表与系统配置。
- 非管理员可用；系统目录会被标记 `denied` 并在报告中说明。

---

## 常见问题

**Q: 会不会误删我的文件？**
A: 不会。脚本只处理 `junk-catalog.json` 白名单内的路径；C 级（用户文档、Program Files、WinSxS 等）永不删除；未知路径直接跳过。

**Q: 为什么有的目录显示 denied？**
A: 非管理员无法访问 `C:\Windows\Temp`、SoftwareDistribution、WER 等系统目录；需要管理员会话才能处理，报告中会标注。

**Q: failed 数量是什么？**
A: 删除失败的文件数（通常是被进程占用或权限不足），已跳过，不会重试或强制删除。

**Q: 实际释放与删除统计为什么略有差异？**
A: 运行中的应用会同时写入新的缓存；以"C 盘剩余空间前后差值"为准。

**Q: 删了 GPU 着色器缓存会怎样？**
A: 游戏/3D 软件首次运行会重新编译，可能短暂卡顿，之后恢复正常。

**Q: 能清理 Windows.old / 旧更新吗？**
A: 本工具默认只处理 `SoftwareDistribution\Download`；`Windows.old` 建议用系统"磁盘清理"或 `DISM` 处理，需管理员并单独确认。

---

## 已知限制

- 非管理员权限下，系统目录无法清理（只报告）。
- 扫描速度受磁盘与文件数影响；百万文件级目录可能耗时数分钟，可用 `-Quick` 跳过。
- 不处理硬链接去重，WinSxS 等目录的统计值可能高于实际占用。
- 不清理系统还原点、休眠文件、虚拟内存、容器镜像——这些需要系统级工具与管理员权限，属于 C 级。
- 不跟随符号链接/联结点（有意为之）。

---

## 贡献

欢迎 Issue 与 PR。提交前请阅读 [`CONTRIBUTING.md`](CONTRIBUTING.md)，并确保：

- `validate-skill.ps1` 通过；
- 安全规则（A/B/C、`-Yes` 确认、白名单、跳过占用）未被削弱；
- 文档与 `CHANGELOG.md` 已同步更新。

---

## 许可证

本项目采用 **Apache License 2.0** 开源，与 [ChatGLM3 开源项目](https://github.com/THUDM/ChatGLM3) 的代码许可证保持一致。

- 许可证全文：[`LICENSE`](LICENSE)
- 版权与说明：[`NOTICE`](NOTICE)

> 说明：ChatGLM3 仓库中的 `MODEL_LICENSE`（ChatGLM3-6B License）仅适用于**模型权重**；
> 本项目不包含任何模型权重，仅包含 PowerShell 脚本、JSON 规则与 Markdown 文档，因此适用 Apache-2.0。
> 你可以自由使用、修改、分发本项目，包括商业用途，但需保留版权声明与许可证文本。

---

## 致谢

- 规则整理自实际 Windows 11 清理实践（500 GB 盘实测：扫描 24.43 GB / 55,707 文件，安全释放 24.74 GB）。
- 感谢 DeepSeek Harness 提供的 Skill 机制与工具链。
