# 垃圾文件识别规则（A/B/C）

> 机器可读的白名单在 `junk-catalog.json`；本文件说明**为什么**这样分级、边界条件与保留策略。
> 新增清理目标必须同时修改 catalog 与本文件，并遵守最后一节的准入检查表。

## 一、总判定原则

1. **可再生成**：删除后能由系统/软件自动重建（缓存、临时文件、转储）→ 可进入 A/B。
2. **语义明确**：目录名与用途明确（Temp、Cache、Code Cache、DXCache、Download 缓存等）→ 可进入 A/B。
3. **不影响完整性**：删除后不会导致软件无法运行、无法卸载、无法修复、无法更新 → 才可清理。
4. **不确定即保留**：无法确认用途的文件、DLL/EXE/SYS、数据库、项目代码、配置、用户文档 → 一律保留。
5. **不越权**：需要管理员才能删除的系统项，只报告不处理。

## 二、A 级：可以安全清理

| 目标 | 路径 | 判定理由 | 注意 |
|---|---|---|---|
| 用户临时文件 | `%LOCALAPPDATA%\Temp` | 应用临时目录，删除后自动重建 | 占用中文件跳过 |
| Windows 临时文件 | `C:\Windows\Temp` | 系统临时目录 | 需管理员；非管理员不可读 |
| 缩略图/图标缓存 | `%LOCALAPPDATA%\Microsoft\Windows\Explorer\thumbcache_*.db`、`iconcache_*.db` | 资源管理器缓存，重建 | 只删匹配文件 |
| IE/系统 INetCache | `%LOCALAPPDATA%\Microsoft\Windows\INetCache` | 系统级网络缓存 | 小 |

**A 级边界**：只包含"删除后系统/应用自动重建、且不含用户数据"的目录。任何包含用户文件的目录（下载、桌面、文档）即使很大也不属于 A 级。

## 三、B 级：需要用户确认

| 类别 | 典型路径 | 删除影响 | 建议 |
|---|---|---|---|
| GPU 着色器缓存 | `%LOCALAPPDATA%\NVIDIA\DXCache`、`GLCache`、`%LOCALAPPDATA%\AMD\DxcCache`、`%LOCALAPPDATA%\D3DSCache` | 游戏/3D 软件首次运行重新编译，可能短暂卡顿 | 可清，体积通常最大 |
| 浏览器缓存 | Edge/Chrome/Brave `User Data\*\Cache、Code Cache、GPUCache、Service Worker\CacheStorage`；Firefox `cache2` | 网页首次加载变慢；不影响 Cookie/书签/密码 | 只删 Cache 类目录 |
| 包管理器缓存 | npm-cache、pnpm store、Yarn Cache、pip cache、.nuget\packages | 依赖按需重新下载 | 离线环境慎用 |
| 应用缓存 | Steam htmlcache、音乐/视频缓存等 | 应用内资源重新下载 | 需关闭应用或跳过占用 |
| Windows 更新下载缓存 | `C:\Windows\SoftwareDistribution\Download` | 只影响待安装更新的下载，不影响已安装更新 | 需管理员 |
| 错误报告/转储 | WER、CrashDumps、Minidump、MEMORY.DMP | 丢失崩溃诊断信息 | 可清 |
| 回收站 | `C:\$Recycle.Bin` | 清空后不可恢复 | 必须确认 |
| 谨慎项（risk=medium） | DSH 待安装更新包、应用安装缓存 | 可能取消待安装更新或影响升级 | 默认不选，需 `-IncludeMedium` |

**B 级边界**：B 级不是"可以随便删"，而是"删除可恢复代价低但需要用户知情"。展示时必须写明影响。

## 四、C 级：禁止自动删除

| 目标 | 原因 |
|---|---|
| `C:\Windows\WinSxS` | 组件存储；手删会破坏系统，只能 DISM 维护 |
| `C:\Windows\System32\DriverStore` | 驱动仓库；误删导致设备失效 |
| `C:\Windows\Installer` | MSI 缓存，卸载/修复依赖 |
| `C:\ProgramData\Package Cache` | 安装/修复依赖 |
| `C:\Windows\assembly`（NativeImages） | 系统程序集缓存 |
| `C:\ProgramData\Microsoft\Windows\Containers` | 容器/Sandbox 镜像层，需 Docker/沙盒工具管理 |
| `C:\Program Files`、`C:\Program Files (x86)` | 已安装软件 |
| `C:\Users` 根及各用户文档/下载/桌面/图片/视频 | 用户数据 |
| `C:\Windows`、`C:\ProgramData` 根 | 系统与程序数据 |
| `C:\System Volume Information` | 系统还原/卷影副本 |
| `pagefile.sys`、`hiberfil.sys`、`swapfile.sys` | 系统核心文件，只能通过系统设置调整 |
| `C:\Windows\System32\winevt\Logs`、`C:\Windows\Logs` | 排障日志，保留 |
| 任何 DLL/EXE/SYS、数据库、代码仓库、配置文件 | 用途不明，保留 |

**C 级规则**：即使占用很大也只统计、不删除；报告中说明"未清理及原因"。

## 五、异常处理与保留策略

| 情况 | 策略 |
|---|---|
| 文件被占用（IOException/UnauthorizedAccess） | 跳过，记录 failed，不结束进程 |
| 权限不足（系统保护目录） | 跳过，标记 denied，提示需管理员 |
| 路径不存在 | 标记 missing，不计错误 |
| 枚举异常 | 计数后继续，不中断 |
| 未知文件/未知目录 | 不进白名单，保留 |
| 符号链接/联结点（ReparsePoint） | 跳过，不跟随，避免循环与跨区删除 |

## 六、新增清理目标的准入检查表

新增前逐条确认：

- [ ] 目录/文件用途明确，且是缓存或临时数据
- [ ] 删除后可由系统或应用自动重建，或可重新下载
- [ ] 不含用户文档、配置、数据库、代码、凭据
- [ ] 删除不会导致软件无法运行/卸载/修复/更新
- [ ] 已在 `junk-catalog.json` 中登记，含 level、risk、notes
- [ ] 已在本文件对应等级中说明理由与影响
- [ ] 已在测试机验证 DryRun 统计正常、Execute 后系统正常

## 七、实测参考（2026-11-17，Windows 11 build 26200）

一次完整清理的实测基线，用于判断结果是否合理：

| 项目 | 数值 |
|---|---|
| C 盘 | 500 GB，清理前剩余 288.18 GB |
| 发现可清理（A+B） | 24.43 GB / 55,707 文件 |
| 实际清理 | 25.03 GB / 55,574 文件（含谨慎项） |
| 占用中跳过 | 144 个文件（<0.03 GB） |
| 实际释放 | 24.74 GB，剩余 312.92 GB |
| 最大单项 | NVIDIA DXCache 12.26 GB（162 个 .nvph） |
