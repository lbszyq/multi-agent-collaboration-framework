<#
.SYNOPSIS
生成项目状态摘要：扫描 task-cards/ 的 front-matter，更新 docs/project-status.md、docs/thread-routing.md 的自动生成区与 docs/context-brief.md 的「当前活跃任务」。

.DESCRIPTION
状态唯一权威 = task-cards/*.md 文件头 YAML front-matter 的 status 字段（P0-1 状态单一化）。
本脚本将未归档任务卡汇总到 project-status.md「进行中的任务卡」「已完成的任务卡」，
更新 thread-routing.md「当前任务卡索引」，并回填 context-brief.md「当前活跃任务」。
自动生成区用 <!-- BEGIN AUTO-GENERATED --> / <!-- END AUTO-GENERATED --> 标记，勿手改。
PM 只维护 task-cards/ 与 decisions.md；project-status / thread-routing / context-brief 的活跃任务摘要由本脚本生成。

.EXAMPLE
.\scripts\generate-status.ps1
.\scripts\generate-status.ps1 -DryRun   # 预览将生成的表格，不写文件
#>
[CmdletBinding()]
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir
. (Join-Path $scriptDir 'framework-lib.ps1')

# ---------- 1. 扫描任务卡 ----------
$cards = @()
Get-ChildItem -LiteralPath (Join-Path $root 'task-cards') -Filter 'TC-*.md' -File -ErrorAction SilentlyContinue |
    ForEach-Object {
        if ($_.DirectoryName -match 'archive') { return }
        $raw = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
        $fm = Get-FrontMatter -Content $raw
        if (-not $fm -or -not $fm['id']) { return }
        $cards += [pscustomobject]@{
            id        = [string]$fm['id']
            title     = if ($fm['title']) { [string]$fm['title'] } else { '' }
            status    = if ($fm['status']) { [string]$fm['status'] } else { '未知' }
            role      = if ($fm['assigned_role']) { [string]$fm['assigned_role'] } else { '' }
            created   = if ($fm['created']) { [string]$fm['created'] } else { '' }
            completed = if ($fm['completed'] -and $fm['completed'] -ne 'null') { [string]$fm['completed'] } else { '' }
            workdir   = if ($fm['workdir'] -and $fm['workdir'] -ne 'null') { [string]$fm['workdir'] } else { '' }
        }
    }
$cards = @($cards | Sort-Object id)

$active = @($cards | Where-Object { $_.status -in @('todo', 'in_progress', 'partial', 'blocked', 'done', 'accepted') })
$done = @($cards | Where-Object { $_.status -eq 'merged' })

function New-Table {
    param([string[]]$Header, [System.Collections.IEnumerable]$Rows, [string]$NewLine = "`n")
    $lines = @()
    $lines += "| $($Header -join ' | ') |"
    $lines += "| $((1..$Header.Count | ForEach-Object { '---' }) -join ' | ') |"
    $items = @($Rows)
    if ($items.Count -eq 0) {
        $lines += "| $((1..$Header.Count | ForEach-Object { '—' }) -join ' | ') |"
    } else {
        foreach ($row in $items) {
            $cells = foreach ($h in $Header) {
                $v = $row.PSObject.Properties[$h].Value
                if ($null -eq $v -or $v -eq '') { '—' } else { "$v" }
            }
            $lines += "| $($cells -join ' | ') |"
        }
    }
    return $lines -join $NewLine
}

# ---------- 2. 更新自动生成区（按 section 标题独立定位） ----------

function Assert-AutoSectionUpdated {
    param([AllowNull()][string]$Text, [string]$Heading)
    if ($null -eq $Text) { throw "未找到章节「$Heading」，无法插入自动生成区" }
    return $Text
}

$statusFile = Join-Path $root 'docs\project-status.md'
$statusText = Get-Content -LiteralPath $statusFile -Raw -Encoding UTF8
$statusNl = if ($statusText -match '\r\n') { "`r`n" } else { "`n" }
$activeTable = New-Table -Header @('任务卡', '简述', '负责人', '开始时间', '状态') -Rows @($active | ForEach-Object {
    [pscustomobject]@{ 任务卡 = $_.id; 简述 = $_.title; 负责人 = $_.role; 开始时间 = $_.created; 状态 = $_.status }
}) -NewLine $statusNl
$doneTable = New-Table -Header @('任务卡', '简述', '负责人', '完成时间') -Rows @($done | ForEach-Object {
    [pscustomobject]@{ 任务卡 = $_.id; 简述 = $_.title; 负责人 = $_.role; 完成时间 = $_.completed }
}) -NewLine $statusNl
$statusText = Assert-AutoSectionUpdated (Update-AutoSection -Text $statusText -SectionHeading '## 进行中的任务卡' -Table $activeTable -NewLine $statusNl) '## 进行中的任务卡'
$statusText = Assert-AutoSectionUpdated (Update-AutoSection -Text $statusText -SectionHeading '## 已完成的任务卡' -Table $doneTable -NewLine $statusNl) '## 已完成的任务卡'

$routingFile = Join-Path $root 'docs\thread-routing.md'
$routingText = Get-Content -LiteralPath $routingFile -Raw -Encoding UTF8
$routingNl = if ($routingText -match '\r\n') { "`r`n" } else { "`n" }
$routingTable = New-Table -Header @('任务卡', '简述', '角色', '状态', '工作目录') -Rows @($cards | ForEach-Object {
    [pscustomobject]@{ 任务卡 = $_.id; 简述 = $_.title; 角色 = $_.role; 状态 = $_.status; 工作目录 = $_.workdir }
}) -NewLine $routingNl
$routingText = Assert-AutoSectionUpdated (Update-AutoSection -Text $routingText -SectionHeading '## 当前任务卡索引（自动生成）' -Table $routingTable -NewLine $routingNl) '## 当前任务卡索引（自动生成）'

# ---------- 2.5 更新 context-brief.md「当前活跃任务」（落盘三处之一，脚本自动完成） ----------
$briefFile = Join-Path $root 'docs\context-brief.md'
$briefText = Get-Content -LiteralPath $briefFile -Raw -Encoding UTF8
$activeList = if ($active.Count -gt 0) { ($active | ForEach-Object { $_.id }) -join '、' } else { '无' }
if ($briefText -match '\*\*当前活跃任务\*\*') {
    $briefText = [regex]::Replace($briefText, '(?m)^\*\*当前活跃任务\*\*：[^\r\n]*', ('**当前活跃任务**：' + $activeList))
} else {
    Write-Host "[警告] context-brief.md 未找到「当前活跃任务」行，跳过更新"
}

# ---------- 3. 输出 ----------
if ($DryRun) {
    Write-Host "===== [DryRun] 将生成的自动生成区 ====="
    Write-Host "`n--- docs/project-status.md「进行中的任务卡」---`n$activeTable"
    Write-Host "`n--- docs/project-status.md「已完成的任务卡」---`n$doneTable"
    Write-Host "`n--- docs/thread-routing.md「当前任务卡索引」---`n$routingTable"
    Write-Host "`n--- docs/context-brief.md「当前活跃任务」--- 当前活跃任务：$activeList"
    Write-Host "`n共扫描 $($cards.Count) 张任务卡（进行中 $($active.Count)，已合并 $($done.Count)）"
    return
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($statusFile, $statusText, $utf8NoBom)
[System.IO.File]::WriteAllText($routingFile, $routingText, $utf8NoBom)
[System.IO.File]::WriteAllText($briefFile, $briefText, $utf8NoBom)
Write-Host "===== 状态摘要已生成 ====="
Write-Host "  docs/project-status.md：进行中 $($active.Count) 张 / 已完成 $($done.Count) 张"
Write-Host "  docs/thread-routing.md：当前任务卡索引 $($cards.Count) 张"
Write-Host "  docs/context-brief.md：当前活跃任务 = $activeList"
Write-Host "（自动生成区勿手改；状态唯一权威 = task-cards/ 文件头 front-matter）"
