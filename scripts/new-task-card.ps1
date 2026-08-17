<#
.SYNOPSIS
从 task-cards/template.md 生成新任务卡（含 YAML front-matter），生成后自动调用 validate-task-card.ps1 校验。

.DESCRIPTION
生成 front-matter：id/title/status=todo/light/created（当天）/assigned_role（-Role，未传填「待填写」）。
workdir/branch/base_commit 留空，由 scripts/new-worktree.ps1 创建 worktree 后自动回填（或 PM 手工补填）。
-Light：生成 light 卡（docs/轻量任务通道.md）——light: true，跳过 F3/F4 关键词提示与完整回报，默认主工作区执行。

.EXAMPLE
.\scripts\new-task-card.ps1 -Number 006 -Summary "示例模块" -Role "R02-后端工程师"
.\scripts\new-task-card.ps1 -Number 007 -Summary "修正文案" -Light
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Number,
    [Parameter(Mandatory = $true, Position = 1)][string]$Summary,
    [string]$Role = '待填写',
    [switch]$Light
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir

if ($Number -notmatch '^\d{3}$') {
    throw "编号必须是 3 位数字（如 001），实际为：$Number"
}
$safeSummary = $Summary -replace '[/\\:*?"<>|\s\[\]$]', '-'
$branchSummary = $Summary -replace '[^A-Za-z0-9_-]', '-'   # 分支名仅允许 ASCII（与 new-worktree.ps1 一致，中文摘要会变为 -）
$today = Get-Date -Format 'yyyy-MM-dd'

$templatePath = Join-Path $root 'task-cards\template.md'
if (-not (Test-Path -LiteralPath $templatePath)) {
    throw "未找到模板：$templatePath"
}
$template = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8

$content = $template
$content = $content -replace 'feature/TC-\{序号\}-\{英文简述\}', "feature/TC-$Number-$branchSummary"
$content = $content -replace 'TC-\{序号\}：\{一行简述任务内容\}', "TC-$Number：$Summary"
$content = $content -replace '\{序号\}', $Number
$content = $content -replace '\{英文简述\}', $branchSummary
$content = $content -replace '\{一行简述任务内容\}', $Summary
$content = $content -replace '\{YYYY-MM-DD\}', $today
$content = $content -replace '\{R0X-岗位名\}', $Role
$content = $content -replace '{P2-中}', 'P2-中'
if ($Light) {
    $content = $content -replace 'light: false', 'light: true'
    $content = $content -replace 'workdir: null', 'workdir: 主工作区'
    $content = $content -replace 'workdir_note: null', 'workdir_note: 轻量通道（light 卡）'
}

$outputPath = Join-Path $root "task-cards\TC-$Number-$safeSummary.md"
if (Test-Path -LiteralPath $outputPath) {
    throw "目标文件已存在，未覆盖：$outputPath"
}
[System.IO.File]::WriteAllText($outputPath, $content, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "已生成任务卡：$outputPath"
if ($Light) {
    Write-Host "提示：light 卡（docs/轻量任务通道.md）——跳过 F3/F4 关键词提示与完整回报，默认主工作区执行（workdir=主工作区 + workdir_note=轻量通道（light 卡）），无需 worktree。"
} else {
    Write-Host "提示：代码类任务卡请运行 .\scripts\new-worktree.ps1 -Number $Number -Summary `"$branchSummary`" 创建独立 Worktree，脚本会自动回填 front-matter 的 workdir/branch/base_branch/base_commit。"
}
Write-Host ""

# 生成后自动校验
& (Join-Path $scriptDir 'validate-task-card.ps1') -Path $outputPath
if (-not $Light) {
    Write-Host "（提示：新卡验收标准为模板占位，通常有 F3/F4 [WARN]——填写真实任务内容与验收标准后重新运行 validate-task-card.ps1；派发前必须通过校验）"
}
exit $LASTEXITCODE

