<#
.SYNOPSIS
框架关键逻辑自测（零依赖：纯 PowerShell 断言，不依赖 Pester 或外部包）。

.DESCRIPTION
覆盖：
  - Get-FrontMatter：null/引号/CRLF/LF/缺失/非法/BOM 开头
  - Update-FrontMatterField：原位替换（CRLF 保留）/追加（行尾跟随原文件）/无 front-matter 原样返回
  - Test-WorktreePath
  - Test-F3BoundaryCoverage / Test-F4ExceptionCoverage（validate-task-card.ps1 第 5 节判定规则）
  - Update-AutoSection：CRLF/LF 插入与替换、无孤立 \r、未找到章节返回 $null
  - 字段契约常量（touched_files 已入列、Required 为 Fields 子集、状态值非空）
  - 集成：validate-framework.ps1 / patrol.ps1 / scan-secrets.ps1 / generate-status.ps1（行尾防回归）
  - H1 负样例：文档引用失效必须被 validate-framework.ps1 检出（临时 git add 一个引用不存在文件的新文档，自动还原）

.EXAMPLE
.\scripts\tests\framework-selftest.ps1
.EXAMPLE
.\scripts\tests\framework-selftest.ps1 -SkipIntegration   # 只测纯函数，不跑校验脚本
#>
[CmdletBinding()]
param(
    [switch]$SkipIntegration,
    [switch]$SkipH1Negative
)
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptsDir = Split-Path -Parent $scriptDir
$root = Split-Path -Parent $scriptsDir
. (Join-Path $scriptsDir 'framework-lib.ps1')

$failCount = 0
$passCount = 0
function Assert-True {
    param([string]$Name, [bool]$Cond)
    if ($Cond) { $script:passCount++; Write-Host "  [PASS] $Name" }
    else { $script:failCount++; Write-Host "  [FAIL] $Name" }
}
function Assert-Eq {
    param([string]$Name, $Actual, $Expected)
    if ([string]::Equals([string]$Actual, [string]$Expected)) {
        $script:passCount++; Write-Host "  [PASS] $Name"
    } else {
        $script:failCount++; Write-Host "  [FAIL] $Name（实际='$Actual'，期望='$Expected'）"
    }
}
function Invoke-PwshFile {
    param([string]$File)
    $out = & (Get-Command pwsh -ErrorAction Stop).Source -NoProfile -File $File 2>&1
    return @{ Code = $LASTEXITCODE; Output = ($out | Out-String) }
}

Write-Host "===== 框架自测：$root ====="
Write-Host "[1] Get-FrontMatter"
$fmCrlf = @(
  '---',
  'id: TC-001',
  'status: todo',
  'completed: null',
  'title: "双引号值"',
  "note: '单引号值'",
  'empty_val:',
  '---',
  ''
) -join "`r`n"
$fm = Get-FrontMatter -Content $fmCrlf
Assert-Eq "CRLF front-matter 解析 id" $fm['id'] 'TC-001'
Assert-True "CRLF front-matter 解析 completed=null" ($null -eq $fm['completed'])
Assert-Eq "双引号值去引号" $fm['title'] '双引号值'
Assert-Eq "单引号值去引号" $fm['note'] '单引号值'
Assert-True "空值解析为 null" ($null -eq $fm['empty_val'])
$fmLf = $fmCrlf -replace "`r`n", "`n"
$fm2 = Get-FrontMatter -Content $fmLf
Assert-Eq "LF front-matter 解析 id" $fm2['id'] 'TC-001'
Assert-True "无 front-matter 返回 null" ($null -eq (Get-FrontMatter -Content '# 只有正文'))
Assert-True "空内容返回 null" ($null -eq (Get-FrontMatter -Content "`n`n"))
Assert-True "只有开始标记返回 null" ($null -eq (Get-FrontMatter -Content "---`nid: x"))
Assert-True "BOM 开头 front-matter 仍可解析" ((Get-FrontMatter -Content ([string][char]0xFEFF + $fmCrlf))['id'] -eq 'TC-001')

Write-Host "[2] Update-FrontMatterField"
$upd = Update-FrontMatterField -Content $fmCrlf -Key 'status' -Value 'done'
Assert-True "原位替换生效" ($upd -match '(?m)^status: done(?=\r?$)')
Assert-True "原位替换保留 CRLF" ($upd.Contains("status: done`r`n"))
$upd2 = Update-FrontMatterField -Content $fmCrlf -Key 'new_field' -Value 'v1'
Assert-True "追加字段生效" ($upd2 -match '(?m)^new_field: v1(?=\r?$)')
Assert-True "追加字段保留 CRLF" ($upd2.Contains("new_field: v1`r`n"))
Assert-True "追加位置在结束标记之前" (($upd2.IndexOf('new_field: v1')) -lt ($upd2.IndexOf("`n---")))
Assert-Eq "无 front-matter 原样返回" (Update-FrontMatterField -Content '# 纯正文' -Key 'a' -Value 'b') '# 纯正文'
$updLf = Update-FrontMatterField -Content $fmLf -Key 'status' -Value 'done'
Assert-True "LF 文件原位替换保留 LF" (-not $updLf.Contains("status: done`r`n") -and $updLf.Contains("status: done`n"))
Assert-True "BOM 开头字段更新生效且保留 BOM" ((Update-FrontMatterField -Content ([string][char]0xFEFF + $fmCrlf) -Key 'status' -Value 'done').StartsWith([string][char]0xFEFF))

Write-Host "[3] Test-WorktreePath"
Assert-True "独立 worktree 路径" (Test-WorktreePath -Path 'D:/wt/tc-001')
Assert-True "相对 worktree 路径" (Test-WorktreePath -Path '..\wt\tc-001')
Assert-True "主工作区返回 false" (-not (Test-WorktreePath -Path '主工作区'))
Assert-True "空字符串返回 false" (-not (Test-WorktreePath -Path ''))
Assert-True "null 返回 false" (-not (Test-WorktreePath -Path $null))

Write-Host "[4] F3/F4 关键词判定"
Assert-True "F3 命中『为空』" (Test-F3BoundaryCoverage -Content '输入为空时返回默认值')
Assert-True "F3 未命中" (-not (Test-F3BoundaryCoverage -Content '正常返回数据'))
Assert-True "F3 空串 false" (-not (Test-F3BoundaryCoverage -Content ''))
Assert-True "F4 命中『异常』" (Test-F4ExceptionCoverage -Content '网络异常时显示重试按钮')
Assert-True "F4 未命中" (-not (Test-F4ExceptionCoverage -Content '正常返回数据'))
Assert-True "F4 空串 false" (-not (Test-F4ExceptionCoverage -Content ''))

Write-Host "[5] 字段契约常量"
Assert-True "touched_files 已在任务卡字段契约" ('touched_files' -in $TaskCardFields)
Assert-True "任务卡 Required 为 Fields 子集" (@($TaskCardRequiredFields | Where-Object { $_ -notin $TaskCardFields }).Count -eq 0)
Assert-True "回报 Required 为 Fields 子集" (@($ReportRequiredFields | Where-Object { $_ -notin $ReportFields }).Count -eq 0)
Assert-True "任务卡状态值非空" ($TaskCardStatusValues.Count -gt 0)
Assert-True "回报状态值非空" ($ReportStatusValues.Count -gt 0)

Write-Host "[6] Update-AutoSection（行尾与孤立 CR 回归）"
$docCrlf = @(
  '# 状态',
  '',
  '## 进行中的任务卡',
  '',
  '（旧内容）',
  ''
) -join "`r`n"
$t1 = Update-AutoSection -Text $docCrlf -SectionHeading '## 进行中的任务卡' -Table '| a |' -NewLine "`r`n"
Assert-True "CRLF 插入生成块" ($t1.Contains("`r`n`r`n<!-- BEGIN AUTO-GENERATED -->`r`n| a |`r`n<!-- END AUTO-GENERATED -->"))
Assert-True "CRLF 插入无孤立 CR" (-not $t1.Contains("`r`r`n"))
$t2 = Update-AutoSection -Text $t1 -SectionHeading '## 进行中的任务卡' -Table '| b |' -NewLine "`r`n"
Assert-True "二次调用替换旧表" ($t2.Contains('| b |') -and -not $t2.Contains('| a |'))
Assert-True "替换后 marker 唯一" (([regex]::Matches($t2, 'BEGIN AUTO-GENERATED')).Count -eq 1)
$docLf = $docCrlf -replace "`r`n", "`n"
$t3 = Update-AutoSection -Text $docLf -SectionHeading '## 进行中的任务卡' -Table '| a |' -NewLine "`n"
Assert-True "LF 文档插入保持 LF" (-not $t3.Contains("`r") -and $t3.Contains("`n| a |`n"))
Assert-True "未找到章节返回 null" ($null -eq (Update-AutoSection -Text $docCrlf -SectionHeading '## 不存在的章节' -Table '| a |' -NewLine "`r`n"))

Write-Host "[7] 集成：validate-framework.ps1"
if ($SkipIntegration) { Write-Host "  [跳过]" }
else {
    $r = Invoke-PwshFile (Join-Path $scriptsDir 'validate-framework.ps1')
    Assert-Eq "validate-framework 退出码为 0" $r.Code 0
    if ($r.Code -ne 0) { Write-Host $r.Output }
}

Write-Host "[8] 集成：patrol.ps1"
if ($SkipIntegration) { Write-Host "  [跳过]" }
else {
    $r = Invoke-PwshFile (Join-Path $scriptsDir 'patrol.ps1')
    Assert-Eq "patrol 退出码为 0（仓库应 PASS）" $r.Code 0
    if ($r.Code -ne 0) { Write-Host $r.Output }
}

Write-Host "[9] H1 负样例：引用失效必须被检出"
if ($SkipIntegration -or $SkipH1Negative) { Write-Host "  [跳过]" }
else {
    $staged = @(git -C $root diff --cached --name-only 2>$null)
    $selfRel = 'scripts/tests/framework-selftest.ps1'
    $otherStaged = @($staged | Where-Object { $_.Replace('\', '/') -ne $selfRel })
    if ($otherStaged.Count -gt 0) {
        Write-Host "  [跳过] git 索引有其他暂存变更（$($otherStaged -join ', ')），避免干扰用户工作区"
    } else {
        $tmpRel = 'docs/__h1_selftest__' + '.md'
        $tmpFile = Join-Path $root ($tmpRel -replace '/', '\')
        $missingRel = 'docs/__h1_selftest_' + 'missing__.md'
        $tmpContent = '引用测试：' + [char]96 + $missingRel + [char]96 + ' 不应存在。' + "`r`n"
        [System.IO.File]::WriteAllText($tmpFile, $tmpContent, (New-Object System.Text.UTF8Encoding($false)))
        try {
            $null = git -C $root add -- $tmpRel
            $r = Invoke-PwshFile (Join-Path $scriptsDir 'validate-framework.ps1')
            Assert-Eq "H1 负样例退出码为 1" $r.Code 1
            Assert-True "H1 负样例输出含失效引用" ($r.Output -match '引用失效.*__h1_selftest_missing__')
            if ($r.Code -ne 1) { Write-Host $r.Output }
        } finally {
            $null = git -C $root rm --cached --quiet -- $tmpRel 2>$null
            if (Test-Path -LiteralPath $tmpFile) { [System.IO.File]::Delete($tmpFile) }
        }
    }
}

Write-Host "[10] 集成：scan-secrets.ps1（中文文件名回归）"
if ($SkipIntegration) { Write-Host "  [跳过]" }
else {
    $scanSrc = Get-Content -LiteralPath (Join-Path $scriptsDir 'scan-secrets.ps1') -Raw -Encoding UTF8
    Assert-True "scan-secrets 使用 quotepath=false（中文文件不漏扫）" $scanSrc.Contains('core.quotepath=false')
    $r = Invoke-PwshFile (Join-Path $scriptsDir 'scan-secrets.ps1')
    Assert-Eq "scan-secrets 退出码为 0" $r.Code 0
    if ($r.Code -ne 0) { Write-Host $r.Output }
}


Write-Host "[11] 集成：generate-status.ps1（行尾防回归）"
if ($SkipIntegration) { Write-Host "  [跳过]" }
else {
    $r = Invoke-PwshFile (Join-Path $scriptsDir 'generate-status.ps1')
    Assert-Eq "generate-status 退出码为 0" $r.Code 0
    if ($r.Code -ne 0) { Write-Host $r.Output }
    foreach ($f in @('docs\project-status.md', 'docs\thread-routing.md')) {
        $raw = [System.IO.File]::ReadAllText((Join-Path $root $f))
        $loneLf = ([regex]::Matches($raw, "(?<!`r)`n")).Count
        $loneCr = ([regex]::Matches($raw, "`r(?!`n)")).Count
        Assert-True "$f 无孤立行尾（孤立LF=$loneLf 孤立CR=$loneCr）" ($loneLf -eq 0 -and $loneCr -eq 0)
    }
}

Write-Host "[12] 集成：generate-metrics.ps1（只读，无回报时退出 0）"
if ($SkipIntegration) { Write-Host "  [跳过]" }
else {
    $r = Invoke-PwshFile (Join-Path $scriptsDir 'generate-metrics.ps1')
    Assert-Eq "generate-metrics 退出码为 0" $r.Code 0
    if ($r.Code -ne 0) { Write-Host $r.Output }
}

Write-Host "-----"
Write-Host "[结果] 自测通过 $passCount 项，失败 $failCount 项"
if ($failCount -gt 0) { exit 1 }
exit 0
