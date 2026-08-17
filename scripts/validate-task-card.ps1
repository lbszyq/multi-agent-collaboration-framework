<#
.SYNOPSIS
校验任务卡：front-matter 必填字段、必填章节、验收标准条数与 F3/F4 边界/异常关键词提示（WARN，不阻断派发）。

.DESCRIPTION
状态/角色/依赖/工作目录/基线等结构化字段以文件头 YAML front-matter 为唯一权威。
worktree 硬约束（docs/git-workflow.md §4）：代码类任务卡一律独立 Worktree；
workdir 填「主工作区」仅限纯文档/纯配置卡且必须填写 workdir_note 理由。

.EXAMPLE
.\scripts\validate-task-card.ps1 -Path task-cards\TC-001-xxx.md
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Path
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'framework-lib.ps1')

$file = Get-Item -LiteralPath $Path
$content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
$results = [System.Collections.Generic.List[string]]::new()

$fm = Get-FrontMatter -Content $content
if (-not $fm) {
    $results.Add("[FAIL] 缺少 YAML front-matter（文件第一行应为 `---`，末行 `---`，见 task-cards/template.md）")
    $fm = @{}
}

# 1. front-matter 必填字段（字段契约唯一来源 = framework-lib.ps1 常量表）
$requiredFields = $TaskCardRequiredFields
foreach ($f in $requiredFields) {
    if (-not $fm.ContainsKey($f)) {
        $results.Add("[FAIL] front-matter 缺少必填字段：$f")
    }
}

# 2. 状态合法性
$status = $fm['status']
if ($status -and $status -notin $TaskCardStatusValues) {
    $results.Add("[FAIL] 状态非法：$status（应为 todo/in_progress/done/accepted/merged/partial/blocked）")
}

# 3. 必填章节
$requiredSections = @('任务目标', '背景信息', '允许修改范围', '禁止修改', '约束与契约', '验收标准')
foreach ($s in $requiredSections) {
    if ($content -notmatch "##\s+$([regex]::Escape($s))") {
        $results.Add("[FAIL] 缺少章节：$s")
    }
}

# 4. 验收标准区域
$acceptance = ''
if ($content -match '(?s)##\s+验收标准.*?(?=\n##\s|\z)') { $acceptance = $Matches[0] }

$itemCount = ([regex]::Matches($acceptance, '(?m)^- \[ \]')).Count
if ($itemCount -eq 0) {
    $results.Add("[FAIL] 验收标准至少需要 1 条")
} else {
    $results.Add("[PASS] 验收标准条数：$itemCount")
}

# 5. F3 边界 / F4 异常启发式（WARN 提示，不阻断派发；语义把关依赖 R03 验收标准评审第二道防线）
#    只扫验收标准区域并剔除 HTML 注释避免模板注释误报
$light = if ($fm.ContainsKey('light')) { [string]$fm['light'] -eq 'true' } else { $false }
$workdir = if ($fm.ContainsKey('workdir')) { [string]$fm['workdir'] } else { '' }
$workdirNote = if ($fm.ContainsKey('workdir_note')) { [string]$fm['workdir_note'] } else { '' }
$isDocCard = ($workdir -match '主工作区') -and ($workdirNote -ne '' -and $workdirNote -ne 'null')
$acceptanceClean = [regex]::Replace($acceptance, '(?s)<!--.*?-->', '')
if ($light) {
    $results.Add("[PASS] light 卡豁免 F3/F4 提示（见 docs/轻量任务通道.md）")
} elseif ($isDocCard) {
    $results.Add("[PASS] 纯文档/配置卡豁免 F3/F4 提示（workdir=主工作区，理由见 workdir_note：$workdirNote）")
} else {
    if (-not (Test-F3BoundaryCoverage -Content $acceptanceClean)) {
        $results.Add("[WARN] 验收标准未命中边界条件关键词（F3）——建议补 1 条边界条件（如空输入/超长/重复/无数据）；大卡派发前应经 R03 评审验收标准（第二道防线），本项不再阻断派发")
    }
    if (-not (Test-F4ExceptionCoverage -Content $acceptanceClean)) {
        $results.Add("[WARN] 验收标准未命中异常处理关键词（F4）——建议补 1 条异常处理（如网络失败/超时/权限不足）；实际把关依赖 R03 验收标准评审")
    }
    if ((Test-F3BoundaryCoverage -Content $acceptanceClean) -and (Test-F4ExceptionCoverage -Content $acceptanceClean)) {
        $results.Add("[PASS] 验收标准命中 F3 边界 + F4 异常关键词")
    }
}
# 6. Worktree 隔离校验（docs/git-workflow.md §4：代码类卡一律 worktree）
$workdir = if ($fm.ContainsKey('workdir')) { [string]$fm['workdir'] } else { '' }
$workdirNote = if ($fm.ContainsKey('workdir_note')) { [string]$fm['workdir_note'] } else { '' }
$parallelWith = if ($fm.ContainsKey('parallel_with')) { [string]$fm['parallel_with'] } else { '' }

if ($workdir -eq '' -or $workdir -eq 'null') {
    if ($status -eq 'todo') {
        $results.Add("[WARN] workdir 未填写——代码类任务卡派发前必须用 .\scripts\new-worktree.ps1 创建独立 Worktree 并回填")
    } else {
        $results.Add("[FAIL] workdir 未填写（状态=$status）——代码类任务卡一律独立 Worktree，纯文档卡填「主工作区」+ workdir_note")
    }
} elseif ($workdir -match '主工作区') {
    if ($workdirNote -eq '') {
        $results.Add("[FAIL] workdir 为「主工作区」但未填写 workdir_note 理由——仅纯文档/纯配置类任务卡可在主工作区执行")
    } else {
        $results.Add("[PASS] 主工作区卡（纯文档/配置），理由：$workdirNote")
    }
} else {
    $isWorktree = Test-WorktreePath -Path $workdir
    if (-not $isWorktree) {
        $results.Add("[FAIL] workdir 不是有效 worktree 路径：$workdir")
    } else {
        $results.Add("[PASS] workdir（独立 Worktree）：$workdir")
    }
}

# 7. 并行组：同组卡必须 worktree（主工作区卡不得进入并行组）
if ($parallelWith -match 'TC-\d{3}' -and $workdir -match '主工作区') {
    $results.Add("[FAIL] 并行组非空（$parallelWith）但 workdir 为主工作区——并行卡必须使用独立 Worktree")
} elseif ($parallelWith -match 'TC-\d{3}') {
    $results.Add("[PASS] 并行卡（并行组：$parallelWith），worktree 隔离由 patrol.ps1 交叉校验同组不共用目录")
}

# 8. base_commit 检查（派发后必填）
$baseCommit = if ($fm.ContainsKey('base_commit')) { [string]$fm['base_commit'] } else { '' }
if (($baseCommit -eq '' -or $baseCommit -eq 'null') -and $status -and $status -ne 'todo') {
    $results.Add("[FAIL] base_commit 未填写（状态=$status）——派发前必须记录基线提交（用 .\scripts\new-worktree.ps1 回填）")
} elseif ($baseCommit -eq '' -or $baseCommit -eq 'null') {
    $results.Add("[WARN] base_commit 未填写（todo 阶段可接受），派发前必须补齐")
}

# 9. branch 检查（派发后必填；merge-card.ps1 依赖该字段，缺失时从 worktree 推导兜底）
$branchVal = if ($fm.ContainsKey('branch')) { [string]$fm['branch'] } else { '' }
if (($branchVal -eq '' -or $branchVal -eq 'null') -and $status -and $status -ne 'todo') {
    $results.Add("[FAIL] branch 未填写（状态=$status）——派发前必须记录分支（用 .\scripts\new-worktree.ps1 回填）")
} elseif ($branchVal -eq '' -or $branchVal -eq 'null') {
    $results.Add("[WARN] branch 未填写（todo 阶段可接受），派发前必须补齐")
} elseif ($branchVal -notmatch '^[A-Za-z0-9/_.-]+$') {
    $results.Add("[FAIL] branch 格式非法：$branchVal")
}

# 10. 验收标准评审记录检查（P2-8 第二道防线：大卡派发前 R03 评审，见 PM-操作指南.md）
#     light 卡豁免；非 todo 状态未填评审记录 → WARN（PM 可写「不适用（理由）」）
$light = if ($fm.ContainsKey('light')) { [string]$fm['light'] -eq 'true' } else { $false }
$reviewedBy = if ($fm.ContainsKey('acceptance_reviewed_by')) { [string]$fm['acceptance_reviewed_by'] } else { '' }
if (-not $light -and $status -and $status -ne 'todo' -and ($reviewedBy -eq '' -or $reviewedBy -eq 'null')) {
    $results.Add("[WARN] acceptance_reviewed_by 未填写——大卡（复杂度=高/涉及契约/schema/冻结产出物/外部证据项/多角色）派发前须经 R03 评审；PM 判定无需评审的写「不适用（理由）」")
}

# 输出
Write-Host "===== 任务卡校验：$($file.Name) ====="
foreach ($r in $results) { Write-Host $r }
$failCount = @($results | Where-Object { $_ -match '^\[FAIL\]' }).Count
if ($failCount -gt 0) {
    Write-Host "-----"
    Write-Host "[结果] FAIL：$failCount 项未通过"
    exit 1
}
Write-Host "-----"
Write-Host "[结果] PASS：结构完整（WARN 项请人工确认）"
exit 0
