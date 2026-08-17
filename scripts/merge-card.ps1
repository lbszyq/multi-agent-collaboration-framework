<#
.SYNOPSIS
PM 验收通过后执行合并：读取任务卡 front-matter，定位 worktree，检查工作区干净，合并到目标分支，标记任务卡 merged。

.DESCRIPTION
合并执行者统一为 PM（P0-3）。前置条件：任务卡状态为 accepted（PM 已完成验收）。
流程：
  1. 校验任务卡状态为 accepted
  2. 定位 feature worktree，检查工作区干净（有未提交修改 → 拒绝）
  3. 定位检出 target_branch（默认 develop）的 worktree
  4. 执行 git merge --no-ff --no-commit（冲突 → 中止合并，交 PM 手动处理）
  5. 更新任务卡 front-matter（status=merged、completed=今天）并随合并结果一次性原子提交
  6. 合并后默认清理已合并的 feature 分支与 worktree（-SkipCleanup 跳过；清理失败会提示手动处理）
本脚本不做 push，不自动解决冲突。

.EXAMPLE
.\scripts\merge-card.ps1 -Card TC-001
.\scripts\merge-card.ps1 -Card TC-001 -TestCommand "npm test"   # 合并后在目标分支运行测试（失败仅提示，不自动回滚）
.\scripts\merge-card.ps1 -Card TC-001 -SkipCleanup              # 合并后保留 feature 分支与 worktree
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Card,
    [string]$TestCommand = '',
    [switch]$SkipCleanup
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir
. (Join-Path $scriptDir 'framework-lib.ps1')

if ($Card -notmatch '^TC-\d{3}$') {
    throw "任务卡编号格式应为 TC-XXX，实际为：$Card"
}

# ---------- 1. 定位任务卡并读取 front-matter ----------
$cardFile = Get-ChildItem -LiteralPath (Join-Path $root 'task-cards') -Filter "$Card-*.md" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $cardFile) {
    throw "未找到任务卡：$Card（应在 task-cards/$Card-*.md）"
}
$cardText = Get-Content -LiteralPath $cardFile.FullName -Raw -Encoding UTF8
$fm = Get-FrontMatter -Content $cardText
if (-not $fm) {
    throw "任务卡缺少 YAML front-matter：$($cardFile.Name)"
}

$status = if ($fm['status']) { [string]$fm['status'] } else { '' }
if ($status -ne 'accepted') {
    throw "任务卡状态为「$status」，仅 accepted（PM 验收通过）可执行合并"
}

$branch = if ($fm['branch'] -and $fm['branch'] -ne 'null') { [string]$fm['branch'] } else { '' }
$workdir = if ($fm['workdir']) { [string]$fm['workdir'] } else { '' }
$targetBranch = if ($fm['target_branch'] -and $fm['target_branch'] -ne 'null') { [string]$fm['target_branch'] } else { 'develop' }

if (-not $workdir -or $workdir -eq 'null' -or -not (Test-Path -LiteralPath $workdir)) {
    throw "workdir 无效或不存在：$workdir（任务卡 front-matter 需填写 feature worktree 路径）"
}
if (-not $branch) {
    # 兼容旧卡：front-matter 未记录 branch 时，从 worktree 当前分支推导
    $branch = (git -C $workdir branch --show-current 2>$null).Trim()
    if ($branch) {
        Write-Host "[提示] 任务卡 front-matter 未记录 branch，已从 worktree 推导：$branch（建议用 new-worktree.ps1 回填后保持一致）"
    }
}
if ($branch -notmatch '^[A-Za-z0-9/_-]+$') {
    throw "分支名非法：$branch（任务卡 front-matter 未记录 branch，且无法从 worktree 推导有效分支）"
}
if ($targetBranch -notmatch '^[A-Za-z0-9/_-]+$') {
    throw "目标分支名非法：$targetBranch"
}

# ---------- 2. 检查 feature worktree 工作区 ----------
Write-Host "==> 检查 worktree 工作区：$workdir"
$dirty = @(git -C $workdir status --short 2>$null)
if ($dirty.Count -gt 0) {
    Write-Host "工作区有未提交修改："
    $dirty | ForEach-Object { Write-Host "  $_" }
    throw "拒绝合并：feature 分支工作区存在未提交修改（docs/git-workflow.md §2.3 要求工作区干净）"
}
Write-Host "    工作区干净"

# ---------- 3. 定位目标分支 worktree ----------
Write-Host "==> 定位检出「$targetBranch」的 worktree"
$targetWorktree = ''
$wtLines = @(git -C $root worktree list --porcelain 2>$null)
$i = 0
while ($i -lt $wtLines.Count) {
    if ($wtLines[$i] -match '^worktree (.+)$') {
        $wtPath = $Matches[1].Trim()
        $wtBranch = ''
        for ($j = $i + 1; $j -lt $wtLines.Count -and $wtLines[$j] -notmatch '^worktree '; $j++) {
            if ($wtLines[$j] -match '^branch refs/heads/(.+)$') { $wtBranch = $Matches[1].Trim() }
        }
        if ($wtBranch -eq $targetBranch) { $targetWorktree = $wtPath; break }
    }
    $i++
}
if (-not $targetWorktree) {
    # 回退：仓库根目录是否检出目标分支
    $rootBranch = (git -C $root branch --show-current 2>$null).Trim()
    if ($rootBranch -eq $targetBranch) {
        $targetWorktree = $root
    }
}
if (-not $targetWorktree) {
    throw "未找到检出「$targetBranch」的 worktree。请先在任一 worktree 检出目标分支（如 git -C <develop-worktree> switch $targetBranch）后重试"
}
Write-Host "    目标 worktree：$targetWorktree"

# ---------- 3.1 检查目标分支 worktree 工作区（双端干净校验：防统计/日志等脏数据误写入目标分支） ----------
Write-Host "==> 检查目标分支工作区：$targetWorktree"
$targetDirty = @(git -C $targetWorktree status --short 2>$null)
if ($targetDirty.Count -gt 0) {
    Write-Host "目标分支工作区有未提交修改："
    $targetDirty | ForEach-Object { Write-Host "  $_" }
    throw "拒绝合并：目标分支「$targetBranch」工作区存在未提交修改（可能含误写入的统计/日志脏数据）——先清理目标分支工作区再合并"
}
Write-Host "    目标分支工作区干净"

# ---------- 4. 执行合并（--no-commit：合并结果与任务卡状态更新合并为一次原子提交） ----------
Write-Host "==> 合并 $branch → $targetBranch（--no-commit，稍后与任务卡状态一起原子提交）"
& git -C $targetWorktree merge --no-ff --no-commit $branch
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] 合并失败（可能冲突）。已中止合并以恢复干净状态；请按 docs/git-workflow.md §五 冲突处理流程处理。"
    & git -C $targetWorktree merge --abort 2>$null
    exit 1
}

# ---------- 5. 更新任务卡 front-matter 并随合并一并提交 ----------
Write-Host "==> 更新任务卡状态：$($cardFile.Name) → merged"
$targetCardPath = Join-Path $targetWorktree (Join-Path 'task-cards' $cardFile.Name)
if (-not (Test-Path -LiteralPath $targetCardPath)) {
    Write-Host "[FAIL] 目标 worktree 中未找到任务卡文件（$targetCardPath）。已中止合并以恢复干净状态。"
    & git -C $targetWorktree merge --abort 2>$null
    exit 1
}
$targetCardText = Get-Content -LiteralPath $targetCardPath -Raw -Encoding UTF8
$today = Get-Date -Format 'yyyy-MM-dd'
$targetCardText = Update-FrontMatterField -Content $targetCardText -Key 'status' -Value 'merged'
$targetCardText = Update-FrontMatterField -Content $targetCardText -Key 'completed' -Value $today
[System.IO.File]::WriteAllText($targetCardPath, $targetCardText, (New-Object System.Text.UTF8Encoding($false)))

& git -C $targetWorktree add (Join-Path 'task-cards' $cardFile.Name)
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] git add 任务卡状态失败。已中止合并以恢复干净状态。"
    & git -C $targetWorktree merge --abort 2>$null
    exit 1
}
# 此 commit 同时包含 merge 结果与任务卡状态更新（原子提交）
& git -C $targetWorktree commit -m "chore($Card): merge and mark merged"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] git commit 失败（合并结果与任务卡状态未提交）。已中止合并以恢复干净状态，请 PM 检查后重试。"
    & git -C $targetWorktree merge --abort 2>$null
    exit 1
}

# ---------- 6. 合并后测试（可选） ----------
if ($TestCommand) {
    Write-Host "==> 目标分支运行测试：$TestCommand"
    Push-Location $targetWorktree
    try {
        $testOut = & ([scriptblock]::Create($TestCommand)) 2>&1
        $testCode = $LASTEXITCODE
        if ($null -eq $testCode) { $testCode = 0 }   # 纯 PowerShell 命令无退出码，视为成功
        if ($testOut) { $testOut | ForEach-Object { Write-Host "    $_" } }
        if ($testCode -ne 0) {
            Write-Host "[警告] 合并后测试未通过（exit=$testCode）。任务已合并，请 PM 评估是否需要修复卡。"
        } else {
            Write-Host "    测试通过"
        }
    } catch {
        Write-Host "[警告] 测试命令执行失败：$($_.Exception.Message)。任务已合并，请 PM 评估是否需要修复卡。"
    } finally {
        Pop-Location
    }
}

Write-Host ""
Write-Host "===== 合并完成 ====="
Write-Host "  $branch → $targetBranch（$targetWorktree）"
Write-Host "  任务卡 $Card 已标记 merged（completed=$today）"
Write-Host "  后续：PM 归档任务卡到 task-cards/archive/，更新 docs/project-status.md（或运行 .\scripts\generate-status.ps1），并运行 .\scripts\patrol.ps1 巡检"

# ---------- 7. 合并后清理（默认执行；-SkipCleanup 保留分支与 worktree） ----------
if (-not $SkipCleanup) {
    Write-Host ""
    Write-Host "==> 清理已合并的 feature 分支与 worktree"
    $postDirty = @(git -C $workdir status --short 2>$null)
    if ($postDirty.Count -gt 0) {
        Write-Host "[警告] feature worktree（$workdir）存在未提交修改，跳过自动移除——请 PM 手动处理后清理：git worktree remove $workdir"
    } else {
        $wtRemoveOutput = & git -C $root worktree remove $workdir 2>&1
        $wtRemoveCode = $LASTEXITCODE
        $wtRemoveOutput | ForEach-Object { Write-Host "    $_" }
        if ($wtRemoveCode -eq 0) {
            Write-Host "    worktree 已移除：$workdir"
            $branchDelOutput = & git -C $root branch -d $branch 2>&1
            $branchDelCode = $LASTEXITCODE
            $branchDelOutput | ForEach-Object { Write-Host "    $_" }
            if ($branchDelCode -eq 0) {
                Write-Host "    分支已删除：$branch"
            } else {
                Write-Host "    [警告] 分支删除失败（$branch）——可能未完全合并或受保护，请手动 git branch -d $branch"
            }
        } else {
            Write-Host "    [警告] worktree 移除失败（$workdir）——可能被进程占用（如本地服务进程），请手动处理：git worktree remove $workdir"
        }
    }
} else {
    Write-Host ""
    Write-Host "==> 已跳过清理（-SkipCleanup）：feature 分支与 worktree 保留，patrol.ps1 会持续提示残留"
}

