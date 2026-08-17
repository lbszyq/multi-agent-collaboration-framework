<#
.SYNOPSIS
生成复盘度量输入：扫描 reports/ 全部完工回报，解析 §9 度量、§5 Bug 分布、§6 契约偏离、§1 状态向量，输出复盘输入表与估算偏差率。

.DESCRIPTION
只读不写（输出到 stdout），供 PM 写 docs/retrospectives/RT-XXX 时使用（docs/retrospectives/README.md 的输入来源，对应 PM-操作指南.md §3.5 复盘与估算校准）。
覆盖范围：主工作区 reports/ + 全部 worktree 内 reports/（同名取最新，与 patrol.ps1 一致）。
解析尽力而为：字段缺失/格式不规范 → 标记「未填」，不 FAIL（正文解析弱于 front-matter，属预期）。

.EXAMPLE
.\scripts\generate-metrics.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir

Write-Host "===== 复盘度量采集：$root ====="

# ---------- 1. 收集回报文件（主工作区 + 全部 Worktree，同名取最新） ----------
$reportFiles = @()
$mainReportDir = Join-Path $root 'reports'
if (Test-Path -LiteralPath $mainReportDir) {
    Get-ChildItem -LiteralPath $mainReportDir -Filter 'TC-*.md' -File -ErrorAction SilentlyContinue |
        ForEach-Object { $reportFiles += [pscustomobject]@{ FullName = $_.FullName; Name = $_.Name; LastWriteTime = $_.LastWriteTime } }
}
try {
    $wtLines = @(git -C $root worktree list --porcelain 2>$null)
    foreach ($line in $wtLines) {
        if ($line -match '^worktree (.+)$') {
            $wtPath = $Matches[1].Trim()
            if ($wtPath -eq $root) { continue }
            $wtReportDir = Join-Path $wtPath 'reports'
            if (Test-Path -LiteralPath $wtReportDir) {
                Get-ChildItem -LiteralPath $wtReportDir -Filter 'TC-*.md' -File -ErrorAction SilentlyContinue |
                    ForEach-Object { $reportFiles += [pscustomobject]@{ FullName = $_.FullName; Name = $_.Name; LastWriteTime = $_.LastWriteTime } }
            }
        }
    }
} catch { }
$reportFiles = @($reportFiles | Group-Object Name | ForEach-Object { $_.Group | Sort-Object LastWriteTime -Descending | Select-Object -First 1 } | Sort-Object Name)

if ($reportFiles.Count -eq 0) {
    Write-Host "  （无回报文件）"
    Write-Host "[结果] PASS"
    exit 0
}

# ---------- 2. 解析单份回报（尽力而为，缺失标「未填」） ----------
function Get-MetricValue {
    param([string]$Content, [string]$Label)
    # 兼容「**标签**：值」与「标签：值」两种写法（[*\s]* 吸收加粗星号与空白）
    if ($Content -match "(?m)$([regex]::Escape($Label))[*\s]*[:：]\s*([^\r\n]+)") {
        return $Matches[1].Trim()
    }
    return $null
}

$rows = [System.Collections.Generic.List[object]]::new()
$sumEst = 0; $sumActual = 0; $estCount = 0; $actCount = 0
$bugCount = @{ P0 = 0; P1 = 0; P2 = 0; P3 = 0 }
$deviationCount = 0
$missingNotes = [System.Collections.Generic.List[string]]::new()

foreach ($r in $reportFiles) {
    $raw = Get-Content -LiteralPath $r.FullName -Raw -Encoding UTF8
    $cardNo = [regex]::Match($r.Name, '^TC-(\d{3})').Groups[1].Value
    if (-not $cardNo) { continue }

    # §9 度量（正文冒号形式）
    $est = Get-MetricValue -Content $raw -Label '任务卡预计'     # 预计轮数（位于「实际轮数：X 轮（任务卡预计：Y 轮）」行内）
    $act = Get-MetricValue -Content $raw -Label '实际轮数'
    $dur = Get-MetricValue -Content $raw -Label '实际耗时'
    $rework = Get-MetricValue -Content $raw -Label '返工次数'
    $bottleneck = Get-MetricValue -Content $raw -Label '主要耗时环节'
    # §1 状态向量（表格形式：| **完成度** | X%（完成 / 部分完成 / 受阻） |）
    $completion = $null
    if ($raw -match '(?m)\|\s*\*\*完成度\*\*\s*\|\s*([^|]+)') { $completion = $Matches[1].Trim() }
    # §6 契约偏离
    $deviated = Get-MetricValue -Content $raw -Label '是否偏离'

    # §5 Bug 分布（每行「严重程度：[Px-...]」取第一个 P 级别计数）
    foreach ($m in [regex]::Matches($raw, '(?m)严重程度\s*[:：]\s*\[?P(\d)')) {
        $lv = 'P' + $m.Groups[1].Value
        if ($bugCount.ContainsKey($lv)) { $bugCount[$lv]++ }
    }
    if ($deviated -and $deviated -match '有偏离') { $deviationCount++ }

    # 轮数数字提取
    $estNum = $null; $actNum = $null
    if ($est -and $est -match '\d+') { $estNum = [int]([regex]::Match($est, '\d+').Value); $sumEst += $estNum; $estCount++ }
    if ($act -and $act -match '\d+') { $actNum = [int]([regex]::Match($act, '\d+').Value); $sumActual += $actNum; $actCount++ }

    # 组装行（先算好全部值，hashtable 内只用简单变量）
    $cardLabel = $r.Name -replace '\.md$', ''
    $estLabel = if ($null -eq $estNum) { '未填' } else { $estNum }
    $actLabel = if ($null -eq $actNum) { '未填' } else { $actNum }
    $deviation = '—'
    if ($null -ne $estNum -and $null -ne $actNum -and $estNum -ne 0) {
        $deviation = ('{0:P0}' -f (($actNum - $estNum) / $estNum))
    }
    $durLabel = if ($dur) { $dur } else { '未填' }
    $reworkLabel = if ($rework) { $rework } else { '未填' }
    $bottleneckLabel = if ($bottleneck) { $bottleneck } else { '未填' }

    $rows.Add([pscustomobject]@{
        任务卡       = $cardLabel
        预计轮数     = $estLabel
        实际轮数     = $actLabel
        偏差         = $deviation
        实际耗时     = $durLabel
        返工次数     = $reworkLabel
        主要耗时环节 = $bottleneckLabel
    })
    if (-not $completion) { $missingNotes.Add("$($r.Name)：§1 完成度未填") }
    if (-not $act) { $missingNotes.Add("$($r.Name)：§9 实际轮数未填") }
    if (-not $est) { $missingNotes.Add("$($r.Name)：§9 预计轮数未填") }
    if (-not $dur) { $missingNotes.Add("$($r.Name)：§9 实际耗时未填") }
    if (-not $rework) { $missingNotes.Add("$($r.Name)：§9 返工次数未填") }
    if (-not $bottleneck) { $missingNotes.Add("$($r.Name)：§9 主要耗时环节未填") }
}

# ---------- 3. 输出 ----------
Write-Host "`n[每卡度量]（共 $($rows.Count) 份回报）："
$rows | Format-Table -AutoSize | Out-String | Write-Host

$deviationRate = '—（无足够数据）'
if ($estCount -gt 0 -and $sumEst -gt 0) {
    $deviationRate = ('{0:P0}' -f (($sumActual - $sumEst) / $sumEst))
}
Write-Host "[汇总]"
Write-Host "  预计轮数合计：$sumEst（$estCount 份填写）/ 实际轮数合计：$sumActual（$actCount 份填写）"
Write-Host "  整体偏差率：$deviationRate"
Write-Host "  Bug 分布：P0 × $($bugCount.P0) / P1 × $($bugCount.P1) / P2 × $($bugCount.P2) / P3 × $($bugCount.P3)"
Write-Host "  契约偏离次数：$deviationCount"
if ($missingNotes.Count -gt 0) {
    Write-Host "`n[未填/解析失败（不阻断，PM 人工补）]："
    $missingNotes | Sort-Object -Unique | ForEach-Object { Write-Host "  - $_" }
}
Write-Host "`n[结果] PASS（只读采集；复盘模板见 docs/retrospectives/template.md）"
exit 0
