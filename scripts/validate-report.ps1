<#
.SYNOPSIS
校验完工回报：front-matter 必填字段、必填章节、验收标准全勾、状态与工作区一致性。

.DESCRIPTION
任务卡编号、角色、状态、Git 定位信息以回报文件头 YAML front-matter 为唯一权威。
关键一致性规则：状态为 done 时验收标准必须全部勾选、工作区必须干净（workspace_status=clean）。

.EXAMPLE
.\scripts\validate-report.ps1 -Path reports\TC-001-回报.md
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

# 1. 文件名
if ($file.Name -notmatch '^TC-\d{3}-回报\.md$') {
    $results.Add("[FAIL] 文件名不符合规范：应形如 TC-001-回报.md")
} else {
    $results.Add("[PASS] 文件名符合规范：$($file.Name)")
}

$fm = Get-FrontMatter -Content $content
if (-not $fm) {
    $results.Add("[FAIL] 缺少 YAML front-matter（文件第一行应为 `---`，末行 `---`，见 reports/template.md）")
    $fm = @{}
}

# 2. front-matter 必填字段（字段契约唯一来源 = framework-lib.ps1 常量表）
$requiredFields = $ReportRequiredFields
foreach ($f in $requiredFields) {
    if (-not $fm.ContainsKey($f) -or [string]$fm[$f] -eq '' -or [string]$fm[$f] -eq 'null') {
        $results.Add("[FAIL] front-matter 缺少必填字段：$f")
    }
}

# 3. 状态合法性
$status = if ($fm.ContainsKey('status')) { [string]$fm['status'] } else { '' }
if ($status -and $status -notin $ReportStatusValues) {
    $results.Add("[FAIL] 状态非法：$status（应为 done/partial/blocked）")
} else {
    $results.Add("[PASS] 任务卡状态：$status")
}

# 4. workdir_type 与 worktree 字段一致性
$workdirType = if ($fm.ContainsKey('workdir_type')) { [string]$fm['workdir_type'] } else { '' }
$worktree = if ($fm.ContainsKey('worktree')) { [string]$fm['worktree'] } else { '' }
if ($workdirType -eq 'worktree' -and ($worktree -eq '' -or $worktree -eq 'null')) {
    $results.Add("[FAIL] workdir_type=worktree 但 front-matter 缺少 worktree 路径")
} elseif ($workdirType -and $workdirType -notin @('worktree', 'main')) {
    $results.Add("[FAIL] workdir_type 非法：$workdirType（应为 worktree/main）")
} else {
    $results.Add("[PASS] 工作目录类型：$workdirType")
}

# 5. 必填章节（light 回报只要求 §1/§3，其余允许缺失或"不适用"）
$light = if ($fm.ContainsKey('light')) { [string]$fm['light'] -eq 'true' } else { $false }
$requiredSections = if ($light) {
    @('## 1. 总体状态', '## 3. 文件变更清单')
} else {
    @('## 1. 总体状态', '## 2. 提交说明', '## 3. 文件变更清单', '## 4. 验收标准逐条核查', '## 5. Bug 报告', '## 6. 契约偏离', '## 7. 技术债务 / 已知问题', '## 8. 需要 PM 关注的决策', '## 9. 度量信息', '### 4.2 外部证据清单')
}
foreach ($s in $requiredSections) {
    if ($content -notmatch [regex]::Escape($s)) {
        $results.Add("[FAIL] 缺少章节：$s")
    }
}

# 5.1 §1 状态向量内容检查（能观测性：done/partial/blocked 都须自解释；light 卡豁免）
$section1 = ''
if ($content -match '(?s)## 1\. 总体状态.*?(?=\n## 2\.|\z)') { $section1 = $Matches[0] }
if (-not $light -and $section1 -eq '') {
    $results.Add("[FAIL] 缺少 §1 总体状态内容")
} elseif (-not $light -and ($section1 -notmatch '完成度|进度')) {
    $results.Add("[FAIL] §1 总体状态缺少状态向量「完成度/进度」字段（见 reports/template.md）")
} elseif (-not $light -and $section1 -notmatch '阻塞') {
    $results.Add("[FAIL] §1 总体状态缺少状态向量「阻塞项」字段（见 reports/template.md）")
} else {
    $results.Add("[PASS] §1 状态向量完整")
}

# 6. §4 验收标准勾选情况
$section4 = ''
if ($content -match '(?s)## 4\. 验收标准逐条核查.*?(?=\n## 5\.|\z)') { $section4 = $Matches[0] }
$unchecked = ([regex]::Matches($section4, '(?m)^- \[ \]')).Count
$checked = ([regex]::Matches($section4, '(?m)^- \[[xX]\]')).Count
if ($status -eq 'done' -and $unchecked -gt 0) {
    $results.Add("[FAIL] 状态为 done 但验收标准仍有 $unchecked 条未勾选")
} else {
    $results.Add("[PASS] 验收标准：$checked 条已勾选，$unchecked 条未勾选")
}

# 7. 工作区状态与任务状态一致性
$ws = if ($fm.ContainsKey('workspace_status')) { [string]$fm['workspace_status'] } else { '' }
if ($ws -eq 'dirty' -and $status -eq 'done') {
    $results.Add("[FAIL] 工作区有未提交修改（workspace_status=dirty）但状态为 done（应为 partial/blocked）")
} elseif ($ws -and $ws -notin @('clean', 'dirty')) {
    $results.Add("[FAIL] workspace_status 非法：$ws（应为 clean/dirty）")
} else {
    $results.Add("[PASS] 工作区状态与任务状态一致")
}

# 8. 外部证据清单（4.2）内容检查（支持「待外部提供」状态，见 docs/质量验收标准.md §1.2）
$section42 = ''
if ($content -match '(?s)### 4\.2 外部证据清单.*?(?=\n## 5\.|\z)') { $section42 = $Matches[0] }
# 剥离模板自带的指引文本（HTML 注释 + 「不适用时」占位示例行 + 提示引用块），避免把模板示例误判为清单内容
$section42 = [regex]::Replace($section42, '(?s)<!--.*?-->', '')
$section42 = $section42 -replace '(?m)^不适用时：不适用（纯文档/配置任务，理由：xxx）\s*$', ''
$section42 = $section42 -replace '(?ms)^> 状态为「待外部提供」的行必须写明预计提供时机.*$', ''
$dataRows = ([regex]::Matches($section42, '(?m)^\|')).Count
$hasPending = $section42 -match '待外部提供'
$declaredNA = $section42 -match '不适用'
$hasDataRows = $dataRows -ge 3
if ($section42 -eq '') {
    if ($light) {
        $results.Add("[PASS] light 回报：4.2 外部证据清单不适用（见 docs/轻量任务通道.md）")
    } else {
        $results.Add("[FAIL] 缺少 4.2 外部证据清单（纯文档任务须写明'不适用'）")
    }
} elseif ($hasDataRows) {
    $status42 = if ($hasPending) { '含「待外部提供」项' } else { "$($dataRows - 2) 条证据行" }
    $results.Add("[PASS] 外部证据清单：$status42")
} elseif ($declaredNA) {
    $results.Add("[PASS] 外部证据清单：不适用（已声明）")
} elseif ($hasPending) {
    $results.Add("[PASS] 外部证据清单：含「待外部提供」项")
} else {
    $results.Add("[FAIL] 4.2 外部证据清单为空（须逐条填写证据行、声明'待外部提供'，或写明'不适用（理由）'）")
}

# 输出
Write-Host "===== 回报校验：$($file.Name) ====="
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


