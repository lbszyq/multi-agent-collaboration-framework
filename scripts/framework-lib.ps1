<#
.SYNOPSIS
多 Agent 协作框架共享函数库。供 scripts/ 下脚本 dot-source 使用。

.DESCRIPTION
提供 YAML front-matter 的解析与更新函数。
front-matter 是任务卡/回报的结构化元数据（机器可读的唯一权威），
仅支持简单标量（key: value），不支持嵌套结构。
使用方式：. "$PSScriptRoot\framework-lib.ps1"
#>

# =============================================================
# 字段契约常量表（唯一来源）
# 与 task-cards/template.md、reports/template.md 的 front-matter 保持一致；
# validate-framework.ps1 会交叉校验模板与常量表，禁止只改一处。
# =============================================================
$TaskCardFields = @(
    'id', 'title', 'status', 'light', 'created', 'completed', 'assigned_role', 'priority',
    'depends_on', 'blocks', 'parallel_with', 'touched_files', 'workdir', 'workdir_note', 'branch',
    'base_branch', 'base_commit', 'target_branch', 'acceptance_reviewed_by'
)
$TaskCardRequiredFields = @(
    'id', 'status', 'created', 'assigned_role', 'priority', 'depends_on',
    'workdir', 'base_branch', 'base_commit', 'target_branch'
)
$TaskCardStatusValues = @('todo', 'in_progress', 'done', 'accepted', 'merged', 'partial', 'blocked')

$ReportFields = @(
    'task_id', 'role', 'time', 'status', 'light', 'repo_root', 'workdir_type',
    'worktree', 'base_commit', 'branch', 'head_commit', 'workspace_status'
)
$ReportRequiredFields = @(
    'task_id', 'role', 'time', 'status', 'repo_root', 'workdir_type',
    'base_commit', 'branch', 'head_commit', 'workspace_status'
)
$ReportStatusValues = @('done', 'partial', 'blocked')

function Get-FrontMatter {
    <#
    .SYNOPSIS
    解析 markdown 文件头 YAML front-matter，返回 hashtable。

    .DESCRIPTION
    front-matter 格式：文件第一行 `---`，末行 `---`，中间每行 `key: value`。
    - `null` / `~` / 空值 → $null
    - 带引号的值（单/双引号）→ 去引号
    - 其余保持字符串
    无 front-matter 或格式不合法 → 返回 $null
    #>
    param([Parameter(Mandatory = $true)][string]$Content)

    if ($Content -notmatch '(?s)^\uFEFF?---\r?\n(.*?)\r?\n---\s*\r?\n') {
        return $null
    }
    $yaml = $Matches[1]
    $hash = @{}
    foreach ($line in ($yaml -split "`r?`n")) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*?)\s*$') {
            $key = $Matches[1]
            $raw = $Matches[2]
            if ($raw -eq 'null' -or $raw -eq '~' -or $raw -eq '') {
                $hash[$key] = $null
            } elseif ($raw -match '^"(.*)"$' -or $raw -match "^'(.*)'$") {
                $hash[$key] = $Matches[1]
            } else {
                $hash[$key] = $raw
            }
        }
    }
    return $hash
}

function Update-FrontMatterField {
    <#
    .SYNOPSIS
    更新 markdown 文件头 front-matter 中的单个字段，返回更新后的完整内容字符串。

    .DESCRIPTION
    字段已存在 → 原位替换；字段不存在 → 追加到 front-matter 块尾部（--- 之前）。
    不修改正文。
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][string]$Value
    )

    $pattern = "(?m)^" + [regex]::Escape($Key) + "\s*:[^\r\n]*(?=\r?$)"
    if ($Content -match $pattern) {
        $replacement = ("{0}: {1}" -f $Key, $Value)
        return [regex]::Replace($Content, $pattern, { param($m) return $replacement }, 1)
    }
    if ($Content -match '(?s)^\uFEFF?---\r?\n.*?\r?\n---') {
        $block = $Matches[0]
        $nl = if ($block -match '\r\n') { "`r`n" } else { "`n" }
        $replacement = ($nl + '{0}: {1}' + $nl + '---') -f $Key, $Value
        $newBlock = [regex]::Replace($block, '\r?\n---\s*$', { param($m) return $replacement })
        return $Content.Replace($block, $newBlock)
    }
    return $Content
}

function Test-WorktreePath {
    <#
    .SYNOPSIS
    判断值是否为独立 worktree 路径：非空、非"主工作区"、含路径分隔符。
    #>
    param([AllowNull()][string]$Path)
    return $Path -and ($Path -notmatch '主工作区') -and ($Path -match '[\\/]')
}

function Test-F3BoundaryCoverage {
    <#
    .SYNOPSIS
    判断验收标准文本是否命中 F3 边界条件关键词（validate-task-card.ps1 第 5 节启发式）。
    供自测脚本复用；判定规则唯一来源在此。
    #>
    param([AllowNull()][string]$Content)
    if (-not $Content) { return $false }
    $boundaryKw = '边界|为空|空状态|空输入|空白|不存在|重复|超长|超过|超出|上限|非法|未找到|零|无数据|并发|多次|首次'
    return [bool]($Content -match $boundaryKw)
}

function Test-F4ExceptionCoverage {
    <#
    .SYNOPSIS
    判断验收标准文本是否命中 F4 异常处理关键词（validate-task-card.ps1 第 5 节启发式）。
    供自测脚本复用；判定规则唯一来源在此。
    #>
    param([AllowNull()][string]$Content)
    if (-not $Content) { return $false }
    $exceptionKw = '异常|失败|错误|网络|崩溃|降级|不可用|拒绝|中断|超时|断开|兜底'
    return [bool]($Content -match $exceptionKw)
}
function Update-AutoSection {
    <#
    .SYNOPSIS
    更新文档中「指定章节标题下的自动生成区」并返回新文本；未找到章节返回 $null。

    .DESCRIPTION
    在 SectionHeading 之后查找 BeginMarker..EndMarker 块：找到则替换，未找到则在标题后插入。
    标题匹配用 lookahead（(?=\r?$)），避免 \s 吞掉行尾 \r 导致插入块产生孤立 \r（\r\r\n）。
    插入块行尾跟随 $NewLine 参数（调用方按目标文档 CRLF/LF 传入），生成区前后保留标题后 1 空行。
    #>
    param(
        [string]$Text,
        [string]$SectionHeading,
        [string]$Table,
        [string]$BeginMarker = '<!-- BEGIN AUTO-GENERATED -->',
        [string]$EndMarker = '<!-- END AUTO-GENERATED -->',
        [string]$NewLine = "`n"
    )
    $headingPattern = "(?m)^" + [regex]::Escape($SectionHeading) + "[ \t]*(?=\r?$)"
    $m = [regex]::Match($Text, $headingPattern)
    if (-not $m.Success) { return $null }
    $afterHeading = $m.Index + $m.Length
    $rest = $Text.Substring($afterHeading)
    $blockPattern = "(?ms)^\s*" + [regex]::Escape($BeginMarker) + ".*?" + [regex]::Escape($EndMarker)
    $bm = [regex]::Match($rest, $blockPattern)
    if ($bm.Success) {
        return $Text.Substring(0, $afterHeading) + "$NewLine$NewLine$BeginMarker$NewLine$Table$NewLine$EndMarker" + $Text.Substring($afterHeading + $bm.Index + $bm.Length)
    }
    return $Text.Substring(0, $afterHeading) + "$NewLine$NewLine$BeginMarker$NewLine$Table$NewLine$EndMarker" + $Text.Substring($afterHeading)
}
