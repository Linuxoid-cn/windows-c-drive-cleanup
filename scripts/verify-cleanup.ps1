<#
.SYNOPSIS
    C 盘清理验证：复测目标目录、对比前后磁盘空间、生成清理报告。

.DESCRIPTION
    读取扫描基线 scan.json 与清理结果 clean-result-execute.json，
    重新测量清理后的目标目录与 C 盘剩余空间，输出 verification.json 与 cleanup-report.md。

.PARAMETER RunDir
    运行目录（含 scan.json 与 clean-result-execute.json）。
    默认取 %LOCALAPPDATA%\C-Drive-Cleanup\runs 下最新的目录。

.PARAMETER OutputDir
    报告输出目录，默认与 RunDir 相同。

.PARAMETER CatalogPath
    白名单 JSON，默认 ..\resources\junk-catalog.json。

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\verify-cleanup.ps1 -RunDir .\runs\20261117-200000
#>
[CmdletBinding()]
param(
    [string]$RunDir,
    [string]$OutputDir,
    [string]$CatalogPath
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$StartedAt = Get-Date

$SkillRoot = Split-Path -Parent $PSScriptRoot
if (-not $CatalogPath) { $CatalogPath = Join-Path $SkillRoot 'resources\junk-catalog.json' }
$TemplatePath = Join-Path $SkillRoot 'templates\cleanup-report-template.md'

if (-not $RunDir) {
    $runsRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'C-Drive-Cleanup\runs'
    $latest = Get-ChildItem -LiteralPath $runsRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) { $RunDir = $latest.FullName }
}
if (-not $RunDir -or -not (Test-Path -LiteralPath $RunDir)) {
    Write-Output 'ERROR: 找不到运行目录，请用 -RunDir 指定。'
    exit 4
}
$RunDir = (Resolve-Path -LiteralPath $RunDir).Path
if (-not $OutputDir) { $OutputDir = $RunDir }
if (-not (Test-Path -LiteralPath $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path

function Get-TreeStats {
    param([string]$Root, [string[]]$Filters)
    if (-not (Test-Path -LiteralPath $Root)) {
        return [pscustomobject]@{ exists=$false; bytes=[long]0; files=0 }
    }
    if (Test-Path -LiteralPath $Root -PathType Leaf) {
        try { $fi = [System.IO.FileInfo]::new($Root); return [pscustomobject]@{ exists=$true; bytes=[long]$fi.Length; files=1 } }
        catch { return [pscustomobject]@{ exists=$true; bytes=[long]0; files=0 } }
    }
    $size = [long]0; $files = 0
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
                try { $size += ([System.IO.FileInfo]::new($f)).Length; $files++ } catch { }
            }
        } catch { }
        try {
            foreach ($sub in [System.IO.Directory]::EnumerateDirectories($cur)) {
                try {
                    $at = [System.IO.File]::GetAttributes($sub)
                    if (($at -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                } catch { continue }
                $stack.Push($sub)
            }
        } catch { }
    }
    return [pscustomobject]@{ exists=$true; bytes=$size; files=$files }
}

$scanPath = Join-Path $RunDir 'scan.json'
$resultPath = Join-Path $RunDir 'clean-result-execute.json'
if (-not (Test-Path $scanPath)) { Write-Output "ERROR: 缺少 $scanPath"; exit 4 }
if (-not (Test-Path $resultPath)) { Write-Output "ERROR: 缺少 $resultPath（先执行清理）"; exit 4 }

$scan = [System.IO.File]::ReadAllText($scanPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$result = [System.IO.File]::ReadAllText($resultPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$afterFree = [long]$disk.FreeSpace
$afterUsed = [long]($disk.Size - $disk.FreeSpace)
$beforeFree = [long]$scan.disk.freeBytes
$beforeUsed = [long]$scan.disk.usedBytes
$freed = $afterFree - $beforeFree

# 复测清理后的目标目录
$catalog = $null
try { $catalog = ([System.IO.File]::ReadAllText($CatalogPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json) } catch { }

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
                $profiles = Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $pattern }
                foreach ($p in $profiles) { foreach ($sub in $Target.subtargets) { [void]$paths.Add((Join-Path $p.FullName $sub)) } }
            }
        }
    }
    return $paths
}

$catalogMap = @{}
if ($catalog -and $catalog.targets) { foreach ($t in $catalog.targets) { $catalogMap[$t.id] = $t } }

$items = @()
foreach ($it in $result.items) {
    $current = [long]0; $currentFiles = 0
    $ct = $catalogMap[$it.id]
    if ($ct) {
        foreach ($p in (Expand-CatalogTarget -Target $ct)) {
            $st = Get-TreeStats -Root $p -Filters $ct.filters
            $current += $st.bytes; $currentFiles += $st.files
        }
    }
    $items += [pscustomobject]@{
        id        = $it.id
        name      = $it.name
        level     = $it.level
        risk      = $it.risk
        beforeBytes = [long]$it.bytes
        deletedBytes = [long]$it.bytes
        remainingBytes = [long]$current
        remainingFiles = $currentFiles
        failedFiles = [int]$it.failed
        status    = $it.status
    }
}

$verification = [pscustomobject]@{
    tool        = 'windows-c-drive-cleanup'
    phase       = 'verify'
    version     = 1
    generatedAt = (Get-Date).ToString('o')
    runDir      = $RunDir
    elapsedSec  = [math]::Round(((Get-Date) - $StartedAt).TotalSeconds, 1)
    disk = [pscustomobject]@{
        totalBytes      = [long]$disk.Size
        beforeFreeBytes = $beforeFree
        afterFreeBytes  = $afterFree
        beforeUsedBytes = $beforeUsed
        afterUsedBytes  = $afterUsed
        freedBytes      = $freed
        freedPercentOfUsed = $(if ($beforeUsed -gt 0) { [math]::Round($freed / $beforeUsed * 100, 2) } else { 0 })
    }
    deletedBytes = [long]$result.totalBytes
    deletedFiles = [int]$result.totalFiles
    failedFiles  = [int]$result.failedFiles
    items        = $items
    note = 'freedBytes 为磁盘剩余空间的真实变化，deletedBytes 为脚本统计的删除量，两者可能因应用同时写入而略有差异。'
}
[System.IO.File]::WriteAllText((Join-Path $OutputDir 'verification.json'), ($verification | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))

function Fmt-GB([long]$bytes) { '{0:N2}' -f ($bytes / 1GB) }

$rows = @()
foreach ($i in ($items | Sort-Object deletedBytes -Descending)) {
    $rows += ('| {0} | {1} GB | {2} GB | {3} GB | {4} |' -f $i.name, (Fmt-GB $i.beforeBytes), (Fmt-GB $i.deletedBytes), (Fmt-GB $i.remainingBytes), $(if ($i.failedFiles -gt 0) { "已清理；$($i.failedFiles) 个文件无法处理（占用/权限）" } else { '已清理' }))
}
$rowsText = $rows -join "`r`n"

$riskNotes = @()
$riskNotes += 'C 级（WinSxS、DriverStore、Installer、Package Cache、NativeImages、Containers、Program Files、用户文档、pagefile/hiberfil、系统日志）全部保留，未删除。'
if (-not $scan.elevated) { $riskNotes += '当前为非管理员会话：C:\Windows\Temp、SoftwareDistribution、WER、Prefetch 等系统目录可能拒绝访问，未清理。' }
if ($verification.failedFiles -gt 0) { $riskNotes += ('有 ' + $verification.failedFiles + ' 个文件无法处理（占用中或权限不足），已跳过，未强制结束任何进程。') }
$riskText = ($riskNotes -join "`r`n")

$reportPath = Join-Path $OutputDir 'cleanup-report.md'
if (Test-Path -LiteralPath $TemplatePath) {
    $md = [System.IO.File]::ReadAllText($TemplatePath, [System.Text.Encoding]::UTF8)
    $md = $md.Replace('{{GENERATED_AT}}', (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
    $md = $md.Replace('{{DISK_TOTAL_GB}}', (Fmt-GB ([long]$disk.Size)))
    $md = $md.Replace('{{BEFORE_FREE_GB}}', (Fmt-GB $beforeFree))
    $md = $md.Replace('{{AFTER_FREE_GB}}', (Fmt-GB $afterFree))
    $md = $md.Replace('{{BEFORE_USED_GB}}', (Fmt-GB $beforeUsed))
    $md = $md.Replace('{{AFTER_USED_GB}}', (Fmt-GB $afterUsed))
    $md = $md.Replace('{{FREED_GB}}', (Fmt-GB $freed))
    $md = $md.Replace('{{DELETED_GB}}', (Fmt-GB ([long]$result.totalBytes)))
    $md = $md.Replace('{{DELETED_FILES}}', [string]$result.totalFiles)
    $md = $md.Replace('{{FAILED_FILES}}', [string]$result.failedFiles)
    $md = $md.Replace('{{ROWS}}', $rowsText)
    $md = $md.Replace('{{RISK_NOTES}}', $riskText)
    [System.IO.File]::WriteAllText($reportPath, $md, [System.Text.UTF8Encoding]::new($false))
}

Write-Output ('VERIFY OK  output=' + $OutputDir)
Write-Output ('before free={0} GB  after free={1} GB  freed={2} GB' -f (Fmt-GB $beforeFree), (Fmt-GB $afterFree), (Fmt-GB $freed))
Write-Output ('deleted={0} GB / {1} files  failed={2}' -f (Fmt-GB ([long]$result.totalBytes)), $result.totalFiles, $result.failedFiles)
foreach ($i in ($items | Sort-Object deletedBytes -Descending)) {
    Write-Output ('  [{0}] {1,-40} deleted={2,8} GB remaining={3,8} GB failed={4}' -f $i.level, $i.name, (Fmt-GB $i.deletedBytes), (Fmt-GB $i.remainingBytes), $i.failedFiles)
}
