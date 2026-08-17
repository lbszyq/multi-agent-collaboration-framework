<#
.SYNOPSIS
框架一致性检查：校验 front-matter 模板与 framework-lib.ps1 常量表一致，并扫描脚本中对 front-matter 字段的引用。

.DESCRIPTION
字段契约唯一来源 = framework-lib.ps1 常量表（$TaskCardFields / $ReportFields / $TaskCardRequiredFields / $ReportRequiredFields / 状态合法值）。
检查项：
  1. task-cards/template.md 的 front-matter 字段集合 == $TaskCardFields（双向）
  2. reports/template.md 的 front-matter 字段集合 == $ReportFields（双向）
  3. Required 字段必须是 Fields 的子集；状态合法值非空
  4. 脚本源码中对 front-matter 字段的引用（$fm['x'] / -Key 'x'）必须属于 TaskCardFields ∪ ReportFields
     ——防止出现 merge-card.ps1 读取 branch 而模板无该字段的断裂

.EXAMPLE
.\scripts\validate-framework.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir
. (Join-Path $scriptDir 'framework-lib.ps1')

$results = [System.Collections.Generic.List[string]]::new()

function Compare-FieldSets {
    param(
        [string]$Label,
        [string[]]$TemplateFields,
        [string[]]$ConstantFields
    )
    $missing = @($ConstantFields | Where-Object { $_ -notin $TemplateFields })
    $extra = @($TemplateFields | Where-Object { $_ -notin $ConstantFields })
    if ($missing.Count -gt 0) { $results.Add("[FAIL] $Label：常量表有但模板缺：$($missing -join ', ')") }
    if ($extra.Count -gt 0) { $results.Add("[FAIL] $Label：模板有但常量表缺：$($extra -join ', ')") }
    if ($missing.Count -eq 0 -and $extra.Count -eq 0) {
        $results.Add("[PASS] $Label：模板与常量表一致（$($TemplateFields.Count) 个字段）")
    }
}

# ---------- 1. 任务卡模板 vs 常量表 ----------
$cardTemplatePath = Join-Path $root 'task-cards\template.md'
if (-not (Test-Path -LiteralPath $cardTemplatePath)) {
    $results.Add("[FAIL] 未找到任务卡模板：$cardTemplatePath")
} else {
    $cardTemplate = Get-Content -LiteralPath $cardTemplatePath -Raw -Encoding UTF8
    $cardTemplateFields = @(Get-FrontMatter -Content $cardTemplate).Keys | Sort-Object
    if ($cardTemplateFields.Count -eq 0) {
        $results.Add("[FAIL] 任务卡模板无 front-matter 或解析失败")
    } else {
        Compare-FieldSets -Label '任务卡模板' -TemplateFields $cardTemplateFields -ConstantFields ($TaskCardFields | Sort-Object)
    }
}

# ---------- 2. 回报模板 vs 常量表 ----------
$reportTemplatePath = Join-Path $root 'reports\template.md'
if (-not (Test-Path -LiteralPath $reportTemplatePath)) {
    $results.Add("[FAIL] 未找到回报模板：$reportTemplatePath")
} else {
    $reportTemplate = Get-Content -LiteralPath $reportTemplatePath -Raw -Encoding UTF8
    $reportTemplateFields = @(Get-FrontMatter -Content $reportTemplate).Keys | Sort-Object
    if ($reportTemplateFields.Count -eq 0) {
        $results.Add("[FAIL] 回报模板无 front-matter 或解析失败")
    } else {
        Compare-FieldSets -Label '回报模板' -TemplateFields $reportTemplateFields -ConstantFields ($ReportFields | Sort-Object)
    }
}

# ---------- 3. Required 子集与状态合法值 ----------
$cardRequiredUnknown = @($TaskCardRequiredFields | Where-Object { $_ -notin $TaskCardFields })
if ($cardRequiredUnknown.Count -gt 0) {
    $results.Add("[FAIL] 任务卡 Required 字段不在 Fields 中：$($cardRequiredUnknown -join ', ')")
} else {
    $results.Add("[PASS] 任务卡 Required 字段均为 Fields 子集")
}
$reportRequiredUnknown = @($ReportRequiredFields | Where-Object { $_ -notin $ReportFields })
if ($reportRequiredUnknown.Count -gt 0) {
    $results.Add("[FAIL] 回报 Required 字段不在 Fields 中：$($reportRequiredUnknown -join ', ')")
} else {
    $results.Add("[PASS] 回报 Required 字段均为 Fields 子集")
}
if ($TaskCardStatusValues.Count -eq 0 -or $ReportStatusValues.Count -eq 0) {
    $results.Add("[FAIL] 状态合法值常量为空")
} else {
    $results.Add("[PASS] 状态合法值常量非空（任务卡 $($TaskCardStatusValues.Count) 个 / 回报 $($ReportStatusValues.Count) 个）")
}

# ---------- 4. 脚本 front-matter 字段引用扫描 ----------
$allFields = @($TaskCardFields) + @($ReportFields)
$excludedScripts = @('framework-lib.ps1', 'validate-framework.ps1')
$scriptFiles = Get-ChildItem -LiteralPath $scriptDir -Filter '*.ps1' -File |
    Where-Object { $_.Name -notin $excludedScripts }
$unknownRefs = [System.Collections.Generic.List[string]]::new()
$refCount = 0
foreach ($sf in $scriptFiles) {
    $text = Get-Content -LiteralPath $sf.FullName -Raw -Encoding UTF8
    $refs = @()
    $refs += [regex]::Matches($text, '\$?fm\[[''"]([A-Za-z_][A-Za-z0-9_]*)[''"]\]') | ForEach-Object { $_.Groups[1].Value }
    $refs += [regex]::Matches($text, '-Key\s+[''"]([A-Za-z_][A-Za-z0-9_]*)[''"]') | ForEach-Object { $_.Groups[1].Value }
    $refs = @($refs | Sort-Object -Unique)
    $refCount += $refs.Count
    foreach ($r in $refs) {
        if ($r -notin $allFields) {
            $unknownRefs.Add("$($sf.Name)：引用未定义字段 '$r'")
        }
    }
}
if ($unknownRefs.Count -gt 0) {
    $unknownRefs | ForEach-Object { $results.Add("[FAIL] $_") }
} else {
    $results.Add("[PASS] 脚本 front-matter 字段引用全部在字段契约内（$refCount 个唯一引用）")
}

# ---------- 5. 文档引用完整性检查（H1：防止 docs/scripts/roles/task-cards/reports 文件改名/移动后引用静默失效） ----------
# 扫描全部 tracked .md/.ps1/.yml 中反引号与单引号内的相对路径引用，逐一判断：
#   - 文件/目录存在 → PASS
#   - 通配符/占位符（* / [ ] / { } / R0X / TC-XXX 示例卡号）→ glob 匹配或按示例跳过
#   - 命中「预期产出物」白名单（项目运行中才产出的文件，如 docs/prd.md、docs/contracts/*-contract.md）→ INFO
#   - 其余不存在 → FAIL（引用失效）
$trackedFiles = @()
$null = git -C $root -c core.quotepath=false ls-files 2>$null
if ($LASTEXITCODE -eq 0) {
    # tracked + untracked：未 git add 的新文件也要纳入引用检查，否则引用新文档会误报「引用失效」
    $trackedFiles = @(git -C $root -c core.quotepath=false ls-files | ForEach-Object { ($_ -replace '\\', '/').ToLowerInvariant() })
    $untrackedFiles = @(git -C $root -c core.quotepath=false ls-files --others --exclude-standard | ForEach-Object { ($_ -replace '\\', '/').ToLowerInvariant() })
    $trackedFiles += $untrackedFiles
} else {
    $trackedFiles = @(Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\.git\\' } |
        ForEach-Object { ($_.FullName.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/').ToLowerInvariant() })
}
$fileSet = @{}
foreach ($t in $trackedFiles) { $fileSet[$t] = $true }
function Test-RepoPathExists {
    param([string]$RelPath)
    $p = ($RelPath -replace '\\', '/').TrimStart('./').ToLowerInvariant()
    if ($fileSet.ContainsKey($p)) { return $true }
    $prefix = $p.TrimEnd('/') + '/'
    foreach ($k in $fileSet.Keys) { if ($k.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $true } }
    return $false
}
function Test-GlobExists {
    param([string]$Pattern)
    $norm = (($Pattern -replace '\\', '/').TrimStart('./')).ToLowerInvariant()
    $rx = '^' + [regex]::Escape($norm).Replace('\*', '.*') + '$'
    foreach ($k in $fileSet.Keys) { if ($k -match $rx) { return $true } }
    return $false
}

$refScanExt = '(?i)\.(md|ps1|yml|yaml|json|css|ts|tsx|py|sh|txt|example|lock)$'
$refPrefix = '(?i)(?<![\w\\/.-])(?:docs|scripts|roles|task-cards|reports)(?:[\\/])'
$futureWhitelist = @(
    '^docs/prd\.md$',
    '^docs/design-system\.md$',
    '^docs/design/',
    '^docs/contracts/[^/]+-contract\.md$',
    '^docs/contracts/design-contract-coverage\.md$',
    '^docs/changes/CR-',
    '^docs/adr/ADR-',
    '^docs/retrospectives/RT-',
    '^docs/requirements/',
    '^docs/design/history/design-v',
    '^docs/(ai-evaluation|ai-observability)\.md$',
    '^task-cards/archive/$',
    '^reports/(screenshots|logs|test-data)/',
    '^prompts/',
    '^ai/',
    '^evaluation/',
    '^knowledge/',
    '^code/',
    '^deploy/',
    '^infra/',
    '\.env\.example$'
)
$scanFiles = @($trackedFiles | Where-Object { $_ -match '\.(md|ps1|yml|yaml)$' })
$refTotal = 0
$refInfo = 0
$refMissing = @()
function Add-Ref {
    param([string]$Candidate, [string]$SourceFile)
    $script:refTotal++
    $c = $Candidate
    if ($c -match '[{}]' -or $c -match 'R0X' -or $c -match '\bXXX\b' -or $c -match '\.\.') { $script:refInfo++; return }
    if ($c -match '\*') {
        if (Test-GlobExists -Pattern $c) { return }
        $script:refInfo++; return
    }
    if ($c -match '\[[^\]]+\]') { $script:refInfo++; return }
    if ($c -match 'TC-\d{3}') {
        if (Test-RepoPathExists -RelPath $c) { return }
        $script:refInfo++; return
    }
    if ($c -match $refScanExt -or $c.EndsWith('/')) {
        if (Test-RepoPathExists -RelPath $c) { return }
        elseif ($c.ToLowerInvariant() -match ($futureWhitelist -join '|')) { $script:refInfo++ }
        else { $script:refMissing += "$SourceFile -> $c" }
    }
}
foreach ($rel in $scanFiles) {
    $full = Join-Path $root ($rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $full)) { continue }
    $text = Get-Content -LiteralPath $full -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $text) { continue }
    # 先剥离代码块（```...```），避免代码块内三反引号被下面的单反引号引用正则错误配对、误提取其中的命令路径
    $text = [regex]::Replace($text, '(?s)```.*?```', '')
    foreach ($m in [regex]::Matches($text, '`([^`]*)`')) {
        $block = $m.Groups[1].Value
        foreach ($p in [regex]::Matches($block, $refPrefix + '[^`\s]+')) {
            $candidate = $p.Value.Trim() -replace '[§#（(：:；;，,。).]*$', ''
            if ($candidate.Length -gt 0) { Add-Ref -Candidate $candidate -SourceFile $rel }
        }
    }
    if ($rel -match '\.ps1$') {
        foreach ($m in [regex]::Matches($text, "'($refPrefix[^']+)'")) {
            $candidate = $m.Groups[1].Value.Trim()
            if ($candidate.Length -gt 0) { Add-Ref -Candidate $candidate -SourceFile $rel }
        }
    }
}
if ($refMissing.Count -gt 0) {
    $refMissing | Sort-Object -Unique | ForEach-Object { $results.Add("[FAIL] 引用失效：$_") }
} else {
    $results.Add("[PASS] 文档/脚本相对路径引用有效（检查 $refTotal 处引用；$refInfo 处为未来产出物/示例/占位）")
}

# ---------- 输出 ----------
Write-Host "===== 框架一致性校验：$root ====="
foreach ($r in $results) { Write-Host $r }
$failCount = @($results | Where-Object { $_ -match '^\[FAIL\]' }).Count
Write-Host "-----"
if ($failCount -gt 0) {
    Write-Host "[结果] FAIL：$failCount 项未通过（模板/常量表/脚本/引用一致性）"
    exit 1
}
Write-Host "[结果] PASS：模板 ↔ 常量表 ↔ 脚本引用 ↔ 文档引用一致"
exit 0
