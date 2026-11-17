<#
.SYNOPSIS
    校验 windows-c-drive-cleanup Skill 的完整性。

.DESCRIPTION
    检查必需文件、SKILL.md frontmatter、catalog JSON 结构、脚本语法、模板占位符。
    全部通过返回 0，否则返回 1 并列出问题。
    只读操作，不修改任何文件。

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\validate-skill.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$SkillRoot = Split-Path -Parent $PSScriptRoot
$problems = New-Object System.Collections.ArrayList
$checks = 0

function Add-Problem([string]$Message) { [void]$problems.Add($Message) }
function Check([string]$Name, [bool]$Condition, [string]$Detail) {
    $script:checks++
    if ($Condition) { Write-Output ("PASS  " + $Name) }
    else { Write-Output ("FAIL  " + $Name + "  " + $Detail); Add-Problem ($Name + ': ' + $Detail) }
}

# 1. 必需文件
$required = @(
    'SKILL.md', 'USAGE.md',
    'scripts\scan-c-drive.ps1', 'scripts\clean-c-drive.ps1',
    'scripts\verify-cleanup.ps1', 'scripts\run-skill.ps1', 'scripts\validate-skill.ps1',
    'resources\junk-catalog.json', 'resources\junk-rules.md',
    'templates\scan-report-template.md', 'templates\cleanup-report-template.md'
)
foreach ($rel in $required) {
    $p = Join-Path $SkillRoot $rel
    Check ("file: " + $rel) (Test-Path -LiteralPath $p) "缺少 $p"
}

# 2. SKILL.md frontmatter
$skillMd = Join-Path $SkillRoot 'SKILL.md'
if (Test-Path $skillMd) {
    $text = [System.IO.File]::ReadAllText($skillMd, [System.Text.Encoding]::UTF8)
    $m = [regex]::Match($text, '(?s)^---\s*\r?\n(.*?)\r?\n---')
    Check 'SKILL.md frontmatter' $m.Success '未找到 --- 包围的 frontmatter'
    if ($m.Success) {
        $fm = $m.Groups[1].Value
        $nameMatch = [regex]::Match($fm, '(?m)^name:\s*["'']?([a-z0-9-]+)["'']?\s*$')
        Check 'frontmatter name (kebab-case)' $nameMatch.Success 'name 缺失或不是 kebab-case'
        $descMatch = [regex]::Match($fm, '(?m)^description:\s*(.+)$')
        Check 'frontmatter description' $descMatch.Success 'description 缺失'
        if ($nameMatch.Success) {
            Check 'SKILL name matches folder' ($nameMatch.Groups[1].Value -eq 'windows-c-drive-cleanup') 'name 与目录名不一致'
        }
    }
}

# 3. catalog JSON
$catalogPath = Join-Path $SkillRoot 'resources\junk-catalog.json'
if (Test-Path $catalogPath) {
    try {
        $catalog = [System.IO.File]::ReadAllText($catalogPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        Check 'catalog parses' $true ''
        Check 'catalog has targets' ($null -ne $catalog.targets -and $catalog.targets.Count -gt 0) 'targets 为空'
        $ids = @{}
        $badLevel = @(); $badType = @(); $dup = @()
        $validTypes = @('path','file','filtered','browser','recycle')
        foreach ($t in $catalog.targets) {
            if ($ids.ContainsKey($t.id)) { $dup += $t.id }
            $ids[$t.id] = $true
            if (@('A','B','C') -notcontains $t.level) { $badLevel += $t.id }
            if ($validTypes -notcontains $t.type) { $badType += $t.id }
            if (-not $t.id -or -not $t.name -or -not $t.risk) { Add-Problem ("target 缺少必填字段: " + $t.id) }
        }
        Check 'catalog ids unique' ($dup.Count -eq 0) ('重复: ' + ($dup -join ','))
        Check 'catalog levels valid' ($badLevel.Count -eq 0) ('非法 level: ' + ($badLevel -join ','))
        Check 'catalog types valid' ($badType.Count -eq 0) ('非法 type: ' + ($badType -join ','))
        $levelC = @($catalog.targets | Where-Object { $_.level -eq 'C' })
        Check 'catalog has C-level guard list' ($levelC.Count -ge 5) 'C 级条目过少'
    } catch {
        Check 'catalog parses' $false $_.Exception.Message
    }
}

# 4. 脚本语法
foreach ($rel in @('scripts\scan-c-drive.ps1','scripts\clean-c-drive.ps1','scripts\verify-cleanup.ps1','scripts\run-skill.ps1','scripts\validate-skill.ps1')) {
    $p = Join-Path $SkillRoot $rel
    if (-not (Test-Path $p)) { continue }
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$tokens, [ref]$errors)
    Check ("syntax: " + $rel) ($errors.Count -eq 0) $(if ($errors.Count -gt 0) { $errors[0].Message } else { '' })
}

# 5. 模板占位符
$expect = @{
    'templates\scan-report-template.md' = @('GENERATED_AT','COMPUTER','USER','ELEVATED','OS','DISK_TOTAL_GB','DISK_USED_GB','DISK_FREE_GB','DISK_USED_PCT','TOP_DIR_ROWS','ROOT_FILE_ROWS','LEVEL_A_ROWS','LEVEL_B_ROWS','LEVEL_C_ROWS','TOTAL_A_GB','TOTAL_B_GB','TOTAL_C_GB','NOTES')
    'templates\cleanup-report-template.md' = @('GENERATED_AT','DISK_TOTAL_GB','BEFORE_FREE_GB','AFTER_FREE_GB','BEFORE_USED_GB','AFTER_USED_GB','FREED_GB','DELETED_GB','DELETED_FILES','FAILED_FILES','ROWS','RISK_NOTES')
}
foreach ($rel in $expect.Keys) {
    $p = Join-Path $SkillRoot $rel
    if (-not (Test-Path $p)) { continue }
    $content = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
    $missing = @()
    foreach ($ph in $expect[$rel]) { if ($content -notmatch ('\{\{' + [regex]::Escape($ph) + '\}\}')) { $missing += $ph } }
    Check ("placeholders: " + $rel) ($missing.Count -eq 0) ('缺少: ' + ($missing -join ','))
}

# 6. 安全关键字（防止误改）
$cleanScript = Join-Path $SkillRoot 'scripts\clean-c-drive.ps1'
if (Test-Path $cleanScript) {
    $cs = [System.IO.File]::ReadAllText($cleanScript, [System.Text.Encoding]::UTF8)
    Check 'cleaner requires -Yes for Execute' ($cs -match '\-not \$Yes') '未发现 -Yes 校验'
    Check 'cleaner rejects C level' ($cs -match "Levels -contains 'C'") '未发现 C 级拦截'
    Check 'cleaner skips reparse points' ($cs -match 'ReparsePoint') '未发现符号链接跳过'
}

Write-Output ''
if ($problems.Count -eq 0) {
    Write-Output ("SKILL VALID - {0} checks passed" -f $checks)
    exit 0
} else {
    Write-Output ("SKILL INVALID - {0} problem(s):" -f $problems.Count)
    $problems | ForEach-Object { Write-Output ('  - ' + $_) }
    exit 1
}
