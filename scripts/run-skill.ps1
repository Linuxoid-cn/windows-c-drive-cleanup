<#
.SYNOPSIS
    C 盘清理编排器：一键执行 scan → plan → (确认后) clean → verify。

.DESCRIPTION
    默认 -Phase all 时只做 scan + plan 并停止，等待用户确认；
    只有显式传 -Yes 才会执行删除，然后自动 verify 并生成报告。
    也可以分阶段单独调用。

.PARAMETER Phase
    scan | plan | clean | verify | all（默认 all）

.PARAMETER Levels
    清理等级，默认 A。可传 A,B。C 级永远拒绝。

.PARAMETER IncludeMedium
    包含 B 级中 risk=medium 的谨慎项。

.PARAMETER Yes
    确认执行删除（clean/all 阶段必需）。

.PARAMETER Quick
    扫描使用快速模式。

.PARAMETER Breakdown
    扫描追加目录下钻。

.PARAMETER RunDir
    指定运行目录；不指定则新建时间戳目录。

.PARAMETER OutputDir
    报告输出目录，默认与 RunDir 相同。

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run-skill.ps1 -Phase all -Levels A,B
.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run-skill.ps1 -Phase all -Levels A,B -Yes
#>
[CmdletBinding()]
param(
    [ValidateSet('scan','plan','clean','verify','all')][string]$Phase = 'all',
    [string[]]$Levels = @('A'),
    [switch]$IncludeMedium,
    [switch]$Yes,
    [switch]$Quick,
    [switch]$Breakdown,
    [string]$RunDir,
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Levels = @($Levels | ForEach-Object { $_ -split ',' } | Where-Object { $_ } | ForEach-Object { $_.Trim().ToUpper() })
if ($Levels -contains 'C') { Write-Output 'REFUSED: C 级不允许清理。'; exit 3 }

if (-not $RunDir) {
    $RunDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ('C-Drive-Cleanup\runs\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
if (-not (Test-Path -LiteralPath $RunDir)) { New-Item -ItemType Directory -Path $RunDir -Force | Out-Null }
$RunDir = (Resolve-Path -LiteralPath $RunDir).Path
if (-not $OutputDir) { $OutputDir = $RunDir }

$ScanScript   = Join-Path $PSScriptRoot 'scan-c-drive.ps1'
$CleanScript  = Join-Path $PSScriptRoot 'clean-c-drive.ps1'
$VerifyScript = Join-Path $PSScriptRoot 'verify-cleanup.ps1'

foreach ($s in @($ScanScript, $CleanScript, $VerifyScript)) {
    if (-not (Test-Path -LiteralPath $s)) { Write-Output "ERROR: 缺少脚本 $s"; exit 4 }
}

function Invoke-Child {
    param([string]$Label, [string]$ScriptPath, [hashtable]$Arguments)
    Write-Output ('=== ' + $Label + ' ===')
    $LASTEXITCODE = 0
    & $ScriptPath @Arguments
    $code = $LASTEXITCODE
    if ($null -ne $code -and $code -ne 0) { throw ("$Label 失败，退出码 $code") }
}

$scanArgs = @{ OutputDir = $RunDir }
if ($Quick) { $scanArgs['Quick'] = $true }
if ($Breakdown) { $scanArgs['Breakdown'] = $true }

$planArgs = @{ Mode = 'DryRun'; Levels = $Levels; OutputDir = $RunDir }
if ($IncludeMedium) { $planArgs['IncludeMedium'] = $true }

$cleanArgs = @{ Mode = 'Execute'; Levels = $Levels; OutputDir = $RunDir; Yes = $true }
if ($IncludeMedium) { $cleanArgs['IncludeMedium'] = $true }

$verifyArgs = @{ RunDir = $RunDir }

$didScan = $false
function Ensure-Scan {
    if ($script:didScan) { return }
    if (-not (Test-Path -LiteralPath (Join-Path $RunDir 'scan.json'))) {
        Invoke-Child -Label '阶段1 扫描（只读）' -ScriptPath $ScanScript -Arguments $scanArgs
        $script:didScan = $true
    } else {
        Write-Output '=== 阶段1 扫描：已存在 scan.json，跳过 ==='
        $script:didScan = $true
    }
}

try {
    switch ($Phase) {
        'scan' {
            Invoke-Child -Label '阶段1 扫描（只读）' -ScriptPath $ScanScript -Arguments $scanArgs
            Write-Output ('SCAN DONE. 输出: ' + $RunDir)
        }
        'plan' {
            Ensure-Scan
            Invoke-Child -Label '阶段3 方案（DryRun）' -ScriptPath $CleanScript -Arguments $planArgs
            Write-Output 'PLAN DONE. 等待用户确认后再执行 -Phase clean -Yes（或 -Phase all -Yes）。'
        }
        'clean' {
            if (-not $Yes) { Write-Output 'REFUSED: clean 阶段必须带 -Yes（用户已确认清理清单）。'; exit 2 }
            Ensure-Scan
            Invoke-Child -Label '阶段4 执行清理' -ScriptPath $CleanScript -Arguments $cleanArgs
            Invoke-Child -Label '阶段5 验证与报告' -ScriptPath $VerifyScript -Arguments $verifyArgs
            Write-Output ('CLEAN DONE. 报告: ' + (Join-Path $RunDir 'cleanup-report.md'))
        }
        'verify' {
            Invoke-Child -Label '阶段5 验证与报告' -ScriptPath $VerifyScript -Arguments $verifyArgs
            Write-Output ('VERIFY DONE. 报告: ' + (Join-Path $RunDir 'cleanup-report.md'))
        }
        'all' {
            Ensure-Scan
            Invoke-Child -Label '阶段3 方案（DryRun）' -ScriptPath $CleanScript -Arguments $planArgs
            if (-not $Yes) {
                Write-Output ''
                Write-Output '=== 已停在确认点（默认先扫描、后确认、再删除） ==='
                Write-Output ('运行目录: ' + $RunDir)
                Write-Output ('确认后执行: run-skill.ps1 -Phase all -Levels ' + ($Levels -join ',') + ' -Yes')
                exit 0
            }
            Invoke-Child -Label '阶段4 执行清理' -ScriptPath $CleanScript -Arguments $cleanArgs
            Invoke-Child -Label '阶段5 验证与报告' -ScriptPath $VerifyScript -Arguments $verifyArgs
            Write-Output ('ALL DONE. 报告: ' + (Join-Path $RunDir 'cleanup-report.md'))
        }
    }
} catch {
    Write-Output ('ERROR: ' + $_.Exception.Message)
    exit 1
}
