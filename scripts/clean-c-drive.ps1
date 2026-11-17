<#
.SYNOPSIS
    C 盘清理执行器：DryRun 生成方案，Execute 按白名单安全删除。

.DESCRIPTION
    - 只处理 resources\junk-catalog.json 中 level=A/B 的目标；C 级永远拒绝。
    - 默认 DryRun（只统计不删除）。
    - Execute 必须显式带 -Yes，否则拒绝执行。
    - 占用中的文件跳过并计入 failed，不结束进程、不强制解锁。
    - 不跟随符号链接/联结点，避免误删。

.PARAMETER Mode
    DryRun（默认）或 Execute。

.PARAMETER Levels
    要处理的等级，默认 A。可写 A,B；C 会被拒绝。

.PARAMETER IncludeMedium
    包含 B 级中 risk=medium 的谨慎项（如待安装更新包）。

.PARAMETER Yes
    Execute 模式必填，表示已获得用户确认。

.PARAMETER MaxBytes
    安全上限：本次累计删除超过该字节数即停止。0 表示不限制。

.PARAMETER OutputDir
    输出目录，默认 %LOCALAPPDATA%\C-Drive-Cleanup\runs\<时间戳>。

.PARAMETER CatalogPath
    白名单 JSON，默认 ..\resources\junk-catalog.json。

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\clean-c-drive.ps1 -Mode DryRun -Levels A,B
.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\clean-c-drive.ps1 -Mode Execute -Levels A,B -Yes
#>
[CmdletBinding()]
param(
    [ValidateSet('DryRun','Execute')][string]$Mode = 'DryRun',
    [string[]]$Levels = @('A'),
    [switch]$IncludeMedium,
    [switch]$Yes,
    [long]$MaxBytes = 0,
    [string]$OutputDir,
    [string]$CatalogPath
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$StartedAt = Get-Date

# 兼容 -Levels A,B 与 -Levels "A,B" 两种写法
$Levels = @($Levels | ForEach-Object { $_ -split ',' } | Where-Object { $_ } | ForEach-Object { $_.Trim().ToUpper() })

$SkillRoot = Split-Path -Parent $PSScriptRoot
if (-not $CatalogPath) { $CatalogPath = Join-Path $SkillRoot 'resources\junk-catalog.json' }
if (-not $OutputDir) {
    $OutputDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ('C-Drive-Cleanup\runs\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
if (-not (Test-Path -LiteralPath $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path

# ---------- 安全校验 ----------
if ($Levels -contains 'C') {
    Write-Output 'REFUSED: C 级（禁止删除）不允许进入清理流程。'
    exit 3
}
if ($Mode -eq 'Execute' -and -not $Yes) {
    Write-Output 'REFUSED: 执行删除必须带 -Yes（表示已获得用户明确确认）。'
    exit 2
}

$catalog = $null
try {
    $catalogText = [System.IO.File]::ReadAllText($CatalogPath, [System.Text.Encoding]::UTF8)
    $catalog = $catalogText | ConvertFrom-Json
} catch {
    Write-Output ("ERROR: 无法读取 catalog: " + $CatalogPath + " (" + $_.Exception.Message + ")")
    exit 4
}

# 危险路径兜底：即使被误加进 catalog 也绝不删除
$DangerousPaths = @(
    'C:\', 'C:\Windows', 'C:\Windows\System32', 'C:\Windows\SysWOW64',
    'C:\Users', 'C:\Program Files', 'C:\Program Files (x86)', 'C:\ProgramData'
)

function Test-DangerousPath([string]$Path) {
    try { $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\') } catch { return $true }
    foreach ($d in $DangerousPaths) {
        $df = [System.IO.Path]::GetFullPath($d).TrimEnd('\')
        if ($full.Equals($df, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Expand-CatalogTarget {
    param($Target)
    $paths = New-Object System.Collections.ArrayList
    switch ($Target.type) {
        'path'     { [void]$paths.Add([Environment]::ExpandEnvironmentVariables($Target.path)) }
        'file'     { [void]$paths.Add([Environment]::ExpandEnvironmentVariables($Target.path)) }
        'filtered' { [void]$paths.Add([Environment]::ExpandEnvironmentVariables($Target.path)) }
        'recycle'  { [void]$paths.Add('C:\$Recycle.Bin') }
        'browser'  {
            $root = [Environment]::ExpandEnvironmentVariables($Target.root)
            if (Test-Path -LiteralPath $root) {
                $pattern = [string]$Target.profilePattern
                $profiles = Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match $pattern }
                foreach ($p in $profiles) {
                    foreach ($sub in $Target.subtargets) { [void]$paths.Add((Join-Path $p.FullName $sub)) }
                }
            }
        }
    }
    return $paths
}

function Invoke-Target {
    param($Target, [string[]]$Paths)
    $bytes = [long]0; $files = 0; $failed = 0; $removedDirs = 0; $status = 'ok'

    if ($Target.type -eq 'recycle') {
        $st = Get-ChildItem -LiteralPath 'C:\$Recycle.Bin' -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum
        $bytes = [long]$st.Sum; $files = [int]$st.Count
        if ($Mode -eq 'Execute') {
            try { Clear-RecycleBin -DriveLetter C -Force -ErrorAction Stop } catch { $status = 'recycle-clear-failed' }
        }
        return [pscustomobject]@{ bytes=$bytes; files=$files; failed=$failed; dirs=$removedDirs; status=$status }
    }

    if ($Target.type -eq 'file') {
        foreach ($p in $Paths) {
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
            try { $len = ([System.IO.FileInfo]::new($p)).Length } catch { continue }
            if (Test-DangerousPath $p) { continue }
            if ($Mode -eq 'Execute') {
                try { Remove-Item -LiteralPath $p -Force -ErrorAction Stop; $bytes += $len; $files++ }
                catch { $failed++ }
            } else { $bytes += $len; $files++ }
        }
        return [pscustomobject]@{ bytes=$bytes; files=$files; failed=$failed; dirs=$removedDirs; status=$status }
    }

    foreach ($root in $Paths) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        if (Test-DangerousPath $root) { $status = 'blocked-dangerous-path'; continue }
        $stack = New-Object System.Collections.Stack
        $stack.Push($root)
        $dirs = New-Object System.Collections.ArrayList
        while ($stack.Count -gt 0) {
            if ($MaxBytes -gt 0 -and $bytes -ge $MaxBytes) { $status = 'max-bytes-reached'; break }
            $cur = [string]$stack.Pop()
            try {
                foreach ($f in [System.IO.Directory]::EnumerateFiles($cur)) {
                    if ($Target.filters) {
                        $n = [System.IO.Path]::GetFileName($f)
                        $matched = $false
                        foreach ($flt in $Target.filters) { if ($n -like $flt) { $matched = $true; break } }
                        if (-not $matched) { continue }
                    }
                    try { $len = ([System.IO.FileInfo]::new($f)).Length } catch { continue }
                    if ($Mode -eq 'Execute') {
                        try { Remove-Item -LiteralPath $f -Force -ErrorAction Stop; $bytes += $len; $files++ }
                        catch { $failed++ }
                    } else { $bytes += $len; $files++ }
                }
            } catch { $failed++ }
            try {
                foreach ($sub in [System.IO.Directory]::EnumerateDirectories($cur)) {
                    try {
                        $at = [System.IO.File]::GetAttributes($sub)
                        if (($at -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                    } catch { continue }
                    [void]$dirs.Add($sub)
                    $stack.Push($sub)
                }
            } catch { $failed++ }
        }
        if ($Mode -eq 'Execute') {
            $dirs | Sort-Object -Property Length -Descending | ForEach-Object {
                try { Remove-Item -LiteralPath $_ -Force -ErrorAction Stop; $removedDirs++ } catch { }
            }
        }
    }
    return [pscustomobject]@{ bytes=$bytes; files=$files; failed=$failed; dirs=$removedDirs; status=$status }
}

# ---------- 执行 ----------
$selected = @()
foreach ($t in $catalog.targets) {
    if ($Levels -notcontains $t.level) { continue }
    if ($t.level -eq 'C') { continue }
    if ($t.risk -eq 'medium' -and -not $IncludeMedium) { continue }
    $selected += $t
}

$results = @()
foreach ($t in $selected) {
    $paths = @(Expand-CatalogTarget -Target $t)
    $r = Invoke-Target -Target $t -Paths $paths
    $results += [pscustomobject]@{
        id       = $t.id
        name     = $t.name
        level    = $t.level
        risk     = $t.risk
        type     = $t.type
        paths    = $paths
        bytes    = $r.bytes
        files    = $r.files
        failed   = $r.failed
        removedDirs = $r.dirs
        status   = $r.status
        notes    = $t.notes
    }
}

$sumBytes = ($results | Measure-Object bytes -Sum).Sum
$sumFiles = ($results | Measure-Object files -Sum).Sum
$sumFailed = ($results | Measure-Object failed -Sum).Sum
if (-not $sumBytes) { $sumBytes = 0 }
if (-not $sumFiles) { $sumFiles = 0 }
if (-not $sumFailed) { $sumFailed = 0 }

$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$summary = [pscustomobject]@{
    tool       = 'windows-c-drive-cleanup'
    phase      = $(if ($Mode -eq 'DryRun') { 'plan' } else { 'clean' })
    mode       = $Mode
    version    = 1
    generatedAt= (Get-Date).ToString('o')
    elapsedSec = [math]::Round(((Get-Date) - $StartedAt).TotalSeconds, 1)
    levels     = $Levels
    includeMedium = [bool]$IncludeMedium
    diskFreeBytes = [long]$disk.FreeSpace
    totalBytes = [long]$sumBytes
    totalFiles = [int]$sumFiles
    failedFiles= [int]$sumFailed
    items      = $results
}

$outFile = 'clean-result-' + $Mode.ToLower() + '.json'
$outPath = Join-Path $OutputDir $outFile
[System.IO.File]::WriteAllText($outPath, ($summary | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))

function Fmt-GB([long]$bytes) { '{0:N2}' -f ($bytes / 1GB) }
Write-Output ('[{0}] levels={1} includeMedium={2}' -f $Mode, ($Levels -join ','), [bool]$IncludeMedium)
foreach ($r in $results) {
    Write-Output ('  {0,-40} {1,9} GB  files={2,-6} failed={3,-4} {4}' -f $r.name, (Fmt-GB $r.bytes), $r.files, $r.failed, $r.status)
}
Write-Output ('TOTAL {0} GB  files={1}  failed={2}  elapsed={3}s' -f (Fmt-GB $sumBytes), $sumFiles, $sumFailed, $summary.elapsedSec)
if ($Mode -eq 'DryRun') { Write-Output 'DRY RUN - 未删除任何文件。向用户展示清单并取得确认后再用 -Mode Execute -Yes。' }
else { Write-Output ('EXECUTED - 已删除。磁盘剩余=' + (Fmt-GB ([long]$disk.FreeSpace)) + ' GB') }
