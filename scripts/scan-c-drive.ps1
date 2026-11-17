<#
.SYNOPSIS
    C 盘只读扫描：磁盘概况、一级目录占用、根目录文件、A/B/C 缓存目标统计。

.DESCRIPTION
    本脚本不做任何写操作（除输出报告到 -OutputDir 外）。
    输出 scan.json 与 scan-report.md，供后续分析与清理使用。

.PARAMETER OutputDir
    输出目录。默认 %LOCALAPPDATA%\C-Drive-Cleanup\runs\<时间戳>。

.PARAMETER CatalogPath
    清理目标白名单 JSON。默认 ..\resources\junk-catalog.json。

.PARAMETER Quick
    快速模式：只扫磁盘 + 缓存目标，跳过一级目录扫描（约 1-2 分钟）。

.PARAMETER Breakdown
    追加主要目录下钻统计（Windows/Users/ProgramData/Program Files 等），耗时较长。

.PARAMETER IncludeProtected
    额外统计 C 级受保护目录（WinSxS、DriverStore 等）的大小，耗时较长。

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scan-c-drive.ps1
.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scan-c-drive.ps1 -Quick -OutputDir D:\scan
#>
[CmdletBinding()]
param(
    [string]$OutputDir,
    [string]$CatalogPath,
    [switch]$Quick,
    [switch]$Breakdown,
    [switch]$IncludeProtected
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$script:StartedAt = Get-Date

$SkillRoot = Split-Path -Parent $PSScriptRoot
if (-not $CatalogPath) { $CatalogPath = Join-Path $SkillRoot 'resources\junk-catalog.json' }
$TemplatePath = Join-Path $SkillRoot 'templates\scan-report-template.md'

if (-not $OutputDir) {
    $OutputDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ('C-Drive-Cleanup\runs\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
if (-not (Test-Path -LiteralPath $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path

function Write-Log([string]$Message) {
    Write-Output $Message
}

function Get-TreeStats {
    param([string]$Root, [string[]]$Filters)
    if (-not (Test-Path -LiteralPath $Root)) {
        return [pscustomobject]@{ exists=$false; bytes=[long]0; files=0; dirs=0; denied=0 }
    }
    if (Test-Path -LiteralPath $Root -PathType Leaf) {
        try {
            $fi = [System.IO.FileInfo]::new($Root)
            return [pscustomobject]@{ exists=$true; bytes=[long]$fi.Length; files=1; dirs=0; denied=0 }
        } catch {
            return [pscustomobject]@{ exists=$true; bytes=[long]0; files=0; dirs=0; denied=1 }
        }
    }
    $size = [long]0; $files = 0; $dirs = 0; $denied = 0
    $stack = New-Object System.Collections.Stack
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $cur = [string]$stack.Pop()
        try {
            foreach ($f in [System.IO.Directory]::EnumerateFiles($cur)) {
                if ($Filters) {
                    $n = [System.IO.Path]::GetFileName($f)
                    $matched = $false
                    foreach ($flt in $Filters) { if ($n -like $flt) { $matched = $true; break } }
                    if (-not $matched) { continue }
                }
                try {
                    $size += ([System.IO.FileInfo]::new($f)).Length
                    $files++
                } catch { $denied++ }
            }
        } catch { $denied++ }
        try {
            foreach ($sub in [System.IO.Directory]::EnumerateDirectories($cur)) {
                try {
                    $at = [System.IO.File]::GetAttributes($sub)
                    if (($at -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                } catch { continue }
                $dirs++
                $stack.Push($sub)
            }
        } catch { $denied++ }
    }
    return [pscustomobject]@{ exists=$true; bytes=$size; files=$files; dirs=$dirs; denied=$denied }
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
                    foreach ($sub in $Target.subtargets) {
                        [void]$paths.Add((Join-Path $p.FullName $sub))
                    }
                }
            }
        }
    }
    return $paths
}

# ---------- 环境信息 ----------
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$os = Get-CimInstance Win32_OperatingSystem
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"

$diskInfo = [pscustomobject]@{
    letter      = 'C:'
    totalBytes  = [long]$disk.Size
    freeBytes   = [long]$disk.FreeSpace
    usedBytes   = [long]($disk.Size - $disk.FreeSpace)
    usedPercent = [math]::Round((1 - $disk.FreeSpace / $disk.Size) * 100, 1)
}

# ---------- 根目录文件 ----------
$rootFiles = @()
try {
    foreach ($f in [System.IO.Directory]::GetFiles('C:\')) {
        try {
            $fi = [System.IO.FileInfo]::new($f)
            $rootFiles += [pscustomobject]@{ name=$fi.Name; bytes=[long]$fi.Length }
        } catch { }
    }
} catch { }

# ---------- 一级目录 ----------
$topDirs = @()
if (-not $Quick) {
    try {
        $dirs = [System.IO.Directory]::GetDirectories('C:\')
    } catch {
        $dirs = @()
    }
    foreach ($d in $dirs) {
        $skip = $false
        try {
            $at = [System.IO.File]::GetAttributes($d)
            if (($at -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { $skip = $true }
        } catch { }
        if ($skip) {
            $topDirs += [pscustomobject]@{ path=$d; bytes=[long]0; files=0; denied=-1; note='reparse-point-skipped' }
            continue
        }
        $st = Get-TreeStats -Root $d
        $topDirs += [pscustomobject]@{ path=$d; bytes=$st.bytes; files=$st.files; denied=$st.denied; note='' }
    }
}

# ---------- 白名单目标统计 ----------
$catalog = $null
try {
    $catalogText = [System.IO.File]::ReadAllText($CatalogPath, [System.Text.Encoding]::UTF8)
    $catalog = $catalogText | ConvertFrom-Json
} catch {
    Write-Log "WARN: 无法读取 catalog: $CatalogPath ($($_.Exception.Message))"
}

$targetResults = @()
if ($catalog -and $catalog.targets) {
    foreach ($t in $catalog.targets) {
        if ($t.level -eq 'C' -and -not $IncludeProtected) { continue }
        $expanded = Expand-CatalogTarget -Target $t
        $bytes = [long]0; $files = 0; $denied = 0; $existsCount = 0
        $paths = @()
        foreach ($p in $expanded) {
            $paths += $p
            $st = Get-TreeStats -Root $p -Filters $t.filters
            if ($st.exists) { $existsCount++ }
            $bytes += $st.bytes; $files += $st.files; $denied += $st.denied
        }
        $targetResults += [pscustomobject]@{
            id           = $t.id
            name         = $t.name
            level        = $t.level
            risk         = $t.risk
            type         = $t.type
            paths        = $paths
            pathsCount   = $paths.Count
            existsCount  = $existsCount
            bytes        = $bytes
            files        = $files
            denied       = $denied
            requiresAdmin= [bool]$t.requiresAdmin
            notes        = [string]$t.notes
        }
    }
}

# ---------- 下钻 ----------
$breakdownData = @()
if ($Breakdown) {
    $roots = @(
        @('C:\Users', 5), @('C:\Windows', 2), @('C:\ProgramData', 2),
        @('C:\Program Files', 2), @('C:\Program Files (x86)', 2)
    )
    foreach ($r in $roots) {
        $rootPath = $r[0]; $depth = [int]$r[1]
        if (-not (Test-Path -LiteralPath $rootPath)) { continue }
        $agg = New-Object 'System.Collections.Generic.Dictionary[string,long]'
        $prefix = $rootPath.TrimEnd('\').Length + 1
        $stack = New-Object System.Collections.Stack
        $stack.Push($rootPath)
        while ($stack.Count -gt 0) {
            $cur = [string]$stack.Pop()
            try {
                foreach ($f in [System.IO.Directory]::EnumerateFiles($cur)) {
                    try { $len = ([System.IO.FileInfo]::new($f)).Length } catch { continue }
                    if ($f.Length -le $prefix) { continue }
                    $rel = $f.Substring($prefix)
                    $parts = $rel.Split('\')
                    $n = [Math]::Min($depth, $parts.Length)
                    $key = ($parts[0..($n-1)] -join '\')
                    if ($agg.ContainsKey($key)) { $agg[$key] = $agg[$key] + $len } else { $agg[$key] = $len }
                }
            } catch { }
            try {
                foreach ($sub in [System.IO.Directory]::EnumerateDirectories($cur)) {
                    try {
                        $at = [System.IO.File]::GetAttributes($sub)
                        if (($at -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                    } catch { }
                    $stack.Push($sub)
                }
            } catch { }
        }
        $rows = @()
        foreach ($kv in $agg.GetEnumerator()) { $rows += [pscustomobject]@{ key=$kv.Key; bytes=$kv.Value } }
        $breakdownData += [pscustomobject]@{ root=$rootPath; depth=$depth; rows=($rows | Sort-Object bytes -Descending) }
    }
}

# ---------- 汇总 ----------
$scan = [pscustomobject]@{
    tool        = 'windows-c-drive-cleanup'
    phase       = 'scan'
    version     = 1
    generatedAt = (Get-Date).ToString('o')
    computer    = $env:COMPUTERNAME
    user        = $identity.Name
    elevated    = $isAdmin
    os          = ($os.Caption + ' build ' + $os.BuildNumber)
    elapsedSec  = [math]::Round(((Get-Date) - $script:StartedAt).TotalSeconds, 1)
    disk        = $diskInfo
    rootFiles   = $rootFiles
    topDirs     = $topDirs
    targets     = $targetResults
    breakdown   = $breakdownData
}

$scanJsonPath = Join-Path $OutputDir 'scan.json'
[System.IO.File]::WriteAllText($scanJsonPath, ($scan | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))

# ---------- Markdown 报告 ----------
function Fmt-GB([long]$bytes) { '{0:N2}' -f ($bytes / 1GB) }
function Fmt-RowsLevel($level) {
    $rows = $targetResults | Where-Object { $_.level -eq $level } | Sort-Object bytes -Descending
    if (-not $rows -or $rows.Count -eq 0) { return '| — | — | — | — |' }
    $out = @()
    foreach ($r in $rows) {
        $first = if ($r.paths.Count -gt 0) { $r.paths[0] } else { '' }
        $out += ('| {0} | {1} GB | {2} | {3} |' -f $r.name, (Fmt-GB $r.bytes), $r.files, $r.risk)
    }
    return ($out -join "`r`n")
}
function Fmt-RowsTop() {
    $rows = $topDirs | Sort-Object bytes -Descending
    if (-not $rows) { return '| — | — | — |' }
    $out = @()
    foreach ($r in $rows) { $out += ('| {0} | {1} GB | {2} |' -f $r.path, (Fmt-GB $r.bytes), $r.files) }
    return ($out -join "`r`n")
}
function Fmt-RowsRootFiles() {
    $rows = $rootFiles | Sort-Object bytes -Descending
    if (-not $rows) { return '| — | — | — |' }
    $out = @()
    foreach ($r in $rows) { $out += ('| {0} | {1} GB |' -f $r.name, (Fmt-GB $r.bytes)) }
    return ($out -join "`r`n")
}

$totalA = ($targetResults | Where-Object { $_.level -eq 'A' } | Measure-Object bytes -Sum).Sum
$totalB = ($targetResults | Where-Object { $_.level -eq 'B' } | Measure-Object bytes -Sum).Sum
$totalC = ($targetResults | Where-Object { $_.level -eq 'C' } | Measure-Object bytes -Sum).Sum
if (-not $totalA) { $totalA = 0 }
if (-not $totalB) { $totalB = 0 }
if (-not $totalC) { $totalC = 0 }

$notes = @()
$notes += ('扫描模式：{0}' -f ($(if ($Quick) { 'Quick' } else { '标准（一级目录）' })))
if ($Breakdown) { $notes += '已执行目录下钻' }
if ($IncludeProtected) { $notes += '已统计 C 级受保护目录' } else { $notes += 'C 级受保护目录未单独统计（需要时加 -IncludeProtected）' }
if (-not $isAdmin) { $notes += '当前非管理员：系统目录（Windows Temp/SoftwareDistribution/WER 等）可能拒绝访问' }
$notesText = ($notes -join "`r`n")

$reportPath = Join-Path $OutputDir 'scan-report.md'
if (Test-Path -LiteralPath $TemplatePath) {
    $md = [System.IO.File]::ReadAllText($TemplatePath, [System.Text.Encoding]::UTF8)
    $md = $md.Replace('{{GENERATED_AT}}', (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
    $md = $md.Replace('{{COMPUTER}}', $env:COMPUTERNAME)
    $md = $md.Replace('{{USER}}', $identity.Name)
    $md = $md.Replace('{{ELEVATED}}', $(if ($isAdmin) { '是' } else { '否' }))
    $md = $md.Replace('{{OS}}', $scan.os)
    $md = $md.Replace('{{DISK_TOTAL_GB}}', (Fmt-GB $diskInfo.totalBytes))
    $md = $md.Replace('{{DISK_USED_GB}}', (Fmt-GB $diskInfo.usedBytes))
    $md = $md.Replace('{{DISK_FREE_GB}}', (Fmt-GB $diskInfo.freeBytes))
    $md = $md.Replace('{{DISK_USED_PCT}}', [string]$diskInfo.usedPercent)
    $md = $md.Replace('{{TOP_DIR_ROWS}}', (Fmt-RowsTop))
    $md = $md.Replace('{{ROOT_FILE_ROWS}}', (Fmt-RowsRootFiles))
    $md = $md.Replace('{{LEVEL_A_ROWS}}', (Fmt-RowsLevel 'A'))
    $md = $md.Replace('{{LEVEL_B_ROWS}}', (Fmt-RowsLevel 'B'))
    $md = $md.Replace('{{LEVEL_C_ROWS}}', (Fmt-RowsLevel 'C'))
    $md = $md.Replace('{{TOTAL_A_GB}}', (Fmt-GB $totalA))
    $md = $md.Replace('{{TOTAL_B_GB}}', (Fmt-GB $totalB))
    $md = $md.Replace('{{TOTAL_C_GB}}', (Fmt-GB $totalC))
    $md = $md.Replace('{{NOTES}}', $notesText)
    [System.IO.File]::WriteAllText($reportPath, $md, [System.Text.UTF8Encoding]::new($false))
}

# ---------- 控制台摘要 ----------
Write-Output ('SCAN OK  output=' + $OutputDir)
Write-Output ('C: total={0} GB used={1} GB free={2} GB ({3}%)  admin={4}' -f (Fmt-GB $diskInfo.totalBytes), (Fmt-GB $diskInfo.usedBytes), (Fmt-GB $diskInfo.freeBytes), $diskInfo.usedPercent, $isAdmin)
foreach ($r in ($targetResults | Sort-Object bytes -Descending)) {
    if ($r.bytes -gt 0 -or $r.level -ne 'C') {
        Write-Output ('[{0}] {1,-42} {2,9} GB  files={3,-7} denied={4}' -f $r.level, $r.name, (Fmt-GB $r.bytes), $r.files, $r.denied)
    }
}
Write-Output ('A total={0} GB  B total={1} GB  C total={2} GB' -f (Fmt-GB $totalA), (Fmt-GB $totalB), (Fmt-GB $totalC))
Write-Output ('elapsed=' + $scan.elapsedSec + 's')
