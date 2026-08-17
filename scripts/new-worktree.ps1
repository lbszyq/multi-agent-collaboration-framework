<#
.SYNOPSIS
为任务卡创建独立 Git Worktree（docs/git-workflow.md §4），并自动回填任务卡 front-matter。

.DESCRIPTION
所有任务卡（含串行）一律使用独立 Worktree——主工作区归 PM 专用（仅检出 develop/main）。
从基线分支创建 feature 分支与独立工作目录，输出分支名、基线提交与 worktree 路径，
并自动写入任务卡 TC-XXX 的 front-matter：workdir / branch / base_branch / base_commit。

.EXAMPLE
.\scripts\new-worktree.ps1 -Number 006 -Summary "user-module"
.\scripts\new-worktree.ps1 -Number 006 -Summary "user-module" -BaseBranch develop -NoUpdateCard
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Number,
    [Parameter(Mandatory = $true, Position = 1)][string]$Summary,
    [string]$BaseBranch = 'develop',
    [switch]$NoUpdateCard
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir
. (Join-Path $scriptDir 'framework-lib.ps1')

if ($Number -notmatch '^\d{3}$') {
    throw "编号必须是 3 位数字（如 001），实际为：$Number"
}
$safeSummary = $Summary -replace '[^A-Za-z0-9_-]', '-'

# 1. Git 仓库检查
$null = git -C $root rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "不是 Git 仓库：$root"
}

# 2. 基线分支检查
$null = git -C $root rev-parse --verify $BaseBranch 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "基线分支不存在：$BaseBranch（可用 git branch -a 查看；默认应为 develop）"
}

# 3. 基线提交
$baseCommit = (git -C $root rev-parse --short $BaseBranch).Trim()
if (-not $baseCommit) {
    throw "无法获取 $BaseBranch 的提交 SHA"
}

# 3.5 任务卡已进基线校验（P0：防止「卡只在主工作区/未提交 → feature Worktree 里没有任务卡」的闭环断裂）
#     主工作区默认检出 develop（docs/git-workflow.md §4.1）；若任务卡未提交到 BaseBranch，Worktree 中找不到任务卡，
#     角色无法开工、merge-card.ps1 在目标分支上找不到任务卡，验收/合并必然失败。
# -c core.quotepath=false：禁用非 ASCII 文件名八进制转义，否则中文任务卡名（TC-001-重写README…）无法被 -match 匹配
$cardInBase = @(git -C $root -c core.quotepath=false ls-tree -r --name-only $BaseBranch -- "task-cards/" 2>$null | Where-Object { $_ -match "^task-cards/TC-$Number-[^/]*\.md$" })
if ($cardInBase.Count -eq 0) {
    throw "任务卡 TC-$Number 未存在于基线分支 $BaseBranch —— 从 $BaseBranch 创建的 feature Worktree 中将找不到任务卡，验收/合并闭环会断裂。请先：1) 确认主工作区检出的分支（应为 develop）；2) 将 task-cards/TC-$Number-*.md 提交到该分支并同步到 $BaseBranch；3) 再运行本脚本。"
}
# 4. 分支与工作目录
$branch = "feature/TC-$Number-$safeSummary"
$worktreePath = "{0}-TC{1}" -f $root.TrimEnd('\', '/'), $Number

if (Test-Path -LiteralPath $worktreePath) {
    throw "worktree 目录已存在：$worktreePath（如需复用请直接使用该目录）"
}

# 5. 创建 worktree
Write-Host "创建 Worktree：$branch ← $BaseBranch ($baseCommit)"
git -C $root worktree add -b $branch $worktreePath $baseCommit
if ($LASTEXITCODE -ne 0) {
    throw "git worktree add 失败（exit=$LASTEXITCODE）"
}

# 6. 自动回填任务卡 front-matter（workdir / branch / base_branch / base_commit）
if (-not $NoUpdateCard) {
    $card = Get-ChildItem -LiteralPath (Join-Path $root 'task-cards') -Filter "TC-$Number-*.md" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($card) {
        $cardContent = Get-Content -LiteralPath $card.FullName -Raw -Encoding UTF8
        $cardContent = Update-FrontMatterField -Content $cardContent -Key 'workdir' -Value $worktreePath
        $cardContent = Update-FrontMatterField -Content $cardContent -Key 'branch' -Value $branch
        $cardContent = Update-FrontMatterField -Content $cardContent -Key 'base_branch' -Value $BaseBranch
        $cardContent = Update-FrontMatterField -Content $cardContent -Key 'base_commit' -Value $baseCommit
        [System.IO.File]::WriteAllText($card.FullName, $cardContent, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "已回填任务卡 front-matter：$($card.Name)（workdir / branch / base_branch / base_commit）"
        Write-Host "[警告] 请立即将 task-cards/TC-$Number-*.md 的 front-matter 回填改动提交到 $BaseBranch（主工作区 = develop）——未提交前，Worktree 内任务卡副本仍是未回填版本（缺 workdir/branch/base_commit），且合并闭环依赖该字段。"
    } else {
        Write-Host "[提示] 未找到 task-cards/TC-$Number-*.md，跳过 front-matter 回填（请手动将以上三项写入任务卡 front-matter）"
    }
} else {
    Write-Host "（-NoUpdateCard：跳过 front-matter 回填）"
}

Write-Host ""
Write-Host "===== Worktree 已创建 ====="
Write-Host "工作目录：$worktreePath"
Write-Host "分支：$branch"
Write-Host "基线提交：$baseCommit"
Write-Host ""
Write-Host "所有任务卡（含串行）一律使用独立 Worktree；主工作区归 PM 专用。"



