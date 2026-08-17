<#
.SYNOPSIS
PM 巡检：扫描任务卡状态、回报文件、Git 未合并分支与 Worktree，输出行动清单。

.DESCRIPTION
用于 PM 对话启动时或定期巡检（对应 docs/自动化协作协议.md 第四节）。
状态以 task-cards/ 与 reports/ 文件头 YAML front-matter 为唯一权威。
在无 develop 分支或非 Git 仓库中自动跳过 Git 检查，不报错。

.EXAMPLE
.\scripts\patrol.ps1
#>
$ErrorActionPreference = 'Stop'
$failCount = 0

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir
. (Join-Path $scriptDir 'framework-lib.ps1')

# CI 环境检测（GitHub Actions 等设 $env:CI=true）：CI 是干净 checkout，不含本地 worktree，
# worktree 相关硬约束检查在 CI 中无意义且会误报（如 todo 卡 workdir=null -> 判 FAIL）。
# 本地由 PM 用 new-worktree.ps1 保证隔离，CI 只做静态一致性检查。
$inCI = $env:CI -eq 'true'   # GitHub Actions 等设 CI=true；未设置或 CI=false 均视为本地

Write-Host "===== 框架巡检：$root ====="

# 1. 任务卡状态（front-matter 为唯一权威）
$cardDir = Join-Path $root 'task-cards'
$cards = Get-ChildItem -LiteralPath $cardDir -Filter 'TC-*.md' -File -ErrorAction SilentlyContinue
Write-Host "`n[任务卡] 未归档 $($cards.Count) 张："
$activeCards = @()
foreach ($c in $cards) {
    $raw = Get-Content -LiteralPath $c.FullName -Raw -Encoding UTF8
    $fm = Get-FrontMatter -Content $raw
    $status = if ($fm -and $fm['status']) { $fm['status'] } else { '未知' }
    $role = if ($fm -and $fm['assigned_role']) { $fm['assigned_role'] } else { '' }
    $pg = if ($fm -and $fm['parallel_with'] -and $fm['parallel_with'] -match 'TC-\d{3}') { $fm['parallel_with'] } else { '' }
    $wd = if ($fm -and $fm['workdir']) { [string]$fm['workdir'] } else { '' }
    $light = if ($fm -and $fm['light']) { [string]$fm['light'] -eq 'true' } else { $false }
    $activeCards += [pscustomobject]@{ 文件 = $c.Name; 状态 = $status; 角色 = $role; 并行组 = $pg; 工作目录 = $wd; 轻量 = $light }
}
if ($activeCards.Count -gt 0) {
    $activeCards | Format-Table -AutoSize | Out-String | Write-Host
} else {
    Write-Host "  （无）"
}

# 2. 回报文件（主工作区 + 所有 Worktree）
$reportFiles = @()
$mainReportDir = Join-Path $root 'reports'
if (Test-Path -LiteralPath $mainReportDir) {
    Get-ChildItem -LiteralPath $mainReportDir -Filter 'TC-*.md' -File -ErrorAction SilentlyContinue |
        ForEach-Object { $reportFiles += [pscustomobject]@{ FullName = $_.FullName; Name = $_.Name; LastWriteTime = $_.LastWriteTime; Loc = '主工作区' } }
}
# 枚举所有 Worktree，扫描其 reports/（并行卡回报可能只存在于 Worktree 中）
try {
    $wtLines = @(git -C $root worktree list --porcelain 2>$null)
    foreach ($line in $wtLines) {
        if ($line -match '^worktree (.+)$') {
            $wtPath = $Matches[1].Trim()
            if ($wtPath -eq $root) { continue }
            $wtReportDir = Join-Path $wtPath 'reports'
            if (Test-Path -LiteralPath $wtReportDir) {
                Get-ChildItem -LiteralPath $wtReportDir -Filter 'TC-*.md' -File -ErrorAction SilentlyContinue |
                    ForEach-Object { $reportFiles += [pscustomobject]@{ FullName = $_.FullName; Name = $_.Name; LastWriteTime = $_.LastWriteTime; Loc = "worktree: $wtPath" } }
            }
        }
    }
} catch { }
# 同名回报按修改时间取最新（Worktree 中的新回报优先于基线副本），并标注来源位置
$reportFiles = @($reportFiles | Group-Object Name | ForEach-Object { $_.Group | Sort-Object LastWriteTime -Descending | Select-Object -First 1 } | Sort-Object Name)
Write-Host "[回报] 共 $($reportFiles.Count) 份（含 Worktree）："
foreach ($r in $reportFiles) {
    $raw = Get-Content -LiteralPath $r.FullName -Raw -Encoding UTF8
    $fm = Get-FrontMatter -Content $raw
    $status = if ($fm -and $fm['status']) { $fm['status'] } else { '未知' }
    Write-Host ("  {0}  （状态={1}，位置={2}，修改于 {3}）" -f $r.Name, $status, $r.Loc, $r.LastWriteTime.ToString('MM-dd HH:mm'))
}
if ($reportFiles.Count -eq 0) { Write-Host "  （无）" }

# 3. 交叉检查：有回报但任务卡状态未达 done/accepted/merged
Write-Host "`n[交叉检查] 有回报但任务卡状态未跟进："
$unprocessed = @()
foreach ($r in $reportFiles) {
    $cardNo = [regex]::Match($r.Name, '^TC-(\d{3})').Groups[1].Value
    if (-not $cardNo) { continue }
    # 回报状态为 partial/blocked = 角色如实声明未完成，任务卡状态 partial/blocked 属正常，不判异常
    $rawReport = Get-Content -LiteralPath $r.FullName -Raw -Encoding UTF8
    $rfm = Get-FrontMatter -Content $rawReport
    if ($rfm -and $rfm['status'] -in @('partial', 'blocked')) { continue }
    $matchCards = $activeCards | Where-Object { $_.文件 -match "^TC-$cardNo-" }
    foreach ($mc in $matchCards) {
        if ($mc.状态 -notin @('done', 'accepted', 'merged')) {
            $unprocessed += "TC-$cardNo：有回报（非 partial/blocked），但任务卡状态仍为 $($mc.状态)"
        }
    }
}
if ($unprocessed.Count -gt 0) {
    $unprocessed | ForEach-Object { Write-Host "  [FAIL] $_" }
    $failCount += $unprocessed.Count
} else {
    Write-Host "  无"
}

# 3.1 交叉检查：有回报但 thread-routing.md 未登记
Write-Host "`n[交叉检查] 有回报但路由表未登记："
$routingFile = Join-Path $root 'docs\thread-routing.md'
$routingText = ''
if (Test-Path -LiteralPath $routingFile) {
    $routingText = Get-Content -LiteralPath $routingFile -Raw -Encoding UTF8
}
$archiveDir = Join-Path $root 'task-cards\archive'
$unrouted = @()
$archivedSkipped = 0
foreach ($r in $reportFiles) {
    $cardNo = [regex]::Match($r.Name, '^TC-(\d{3})').Groups[1].Value
    if (-not $cardNo) { continue }
    # 已归档任务卡：验收与合并已完成，路由表「当前任务卡」列已清空，不要求登记
    $archived = @(Get-ChildItem -LiteralPath $archiveDir -Filter "TC-$cardNo-*.md" -File -ErrorAction SilentlyContinue)
    if ($archived.Count -gt 0) { $archivedSkipped++; continue }
    if ($routingText -notmatch "TC-$cardNo") {
        $unrouted += "TC-$cardNo：有回报，但 docs/thread-routing.md 未登记该任务"
    }
}
if ($archivedSkipped -gt 0) {
    Write-Host "  （已归档 $archivedSkipped 份回报，跳过路由表登记检查）"
}
if ($unrouted.Count -gt 0) {
    $unrouted | ForEach-Object { Write-Host "  [FAIL] $_" }
    $failCount += $unrouted.Count
} else {
    Write-Host "  无"
}

# 3.2 认知恢复检查：有活跃任务/回报时 context-brief.md 不得为占位
Write-Host "`n[认知恢复] docs/context-brief.md 非占位检查："
$briefFile = Join-Path $root 'docs\context-brief.md'
$briefText = ''
if (Test-Path -LiteralPath $briefFile) {
    $briefText = Get-Content -LiteralPath $briefFile -Raw -Encoding UTF8
}
$briefPlaceholder = $briefText -match '\[待'
$hasWork = ($activeCards.Count -gt 0) -or ($reportFiles.Count -gt 0)
if ($briefPlaceholder -and $hasWork) {
    Write-Host "  [FAIL] 存在活跃任务/回报，但 docs/context-brief.md 仍为占位——新对话无法可靠恢复认知"
    $failCount++
} elseif ($briefPlaceholder) {
    Write-Host "  [提示] docs/context-brief.md 为占位（当前无活跃任务，可接受）"
} else {
    Write-Host "  PASS"
}

# 3.3 Worktree 隔离交叉检查（docs/git-workflow.md §4：代码类卡一律 worktree；主工作区仅限纯文档卡）
Write-Host "`n[交叉检查] Worktree 隔离："
if ($inCI) {
    # CI 是干净 checkout，不含本地 worktree；workdir 由 PM 本地用 new-worktree.ps1 回填，跳过隔离硬检查避免误报
    Write-Host "  [提示] CI 环境：跳过 Worktree 隔离检查（本地由 new-worktree.ps1 保证隔离）"
} else {
    $parallelIssues = @()
    foreach ($card in $activeCards) {
        if ($card.轻量) { continue }  # light 卡豁免 worktree 硬约束（docs/轻量任务通道.md）
        $wd = $card.工作目录
        $isWorktree = Test-WorktreePath -Path $wd
        if (-not $isWorktree) {
            if ($wd -match '主工作区') {
                # 主工作区卡：需要 workdir_note（纯文档/纯配置豁免），validate-task-card.ps1 已逐卡校验，此处仅提示
                $parallelIssues += "$($card.文件)：workdir 为主工作区（仅限纯文档/纯配置卡，须在 front-matter workdir_note 写明理由）"
            } else {
                $parallelIssues += "$($card.文件)：workdir 缺失或非独立 worktree 路径——代码类任务卡一律使用独立 Worktree（docs/git-workflow.md §4）"
            }
        }
    }
    # 并行组解析：parallel_with 语义为“本卡与对方卡号并行”，A 填 TC-B、B 填 TC-A 互相引用。
    # Group-Object 按字符串分组会把互指的两张卡拆成两个单卡组，导致同组检查（workdir 重复、touched_files 重叠）失效，
    # 因此先按 TC-xxx 引用构建无向连通分量（并查集），再按分量分组。
    $parRoot = @{}
    function Get-ParRoot([string]$x) {
        if (-not $parRoot.ContainsKey($x)) { $parRoot[$x] = $x }
        if ($parRoot[$x] -ne $x) { $parRoot[$x] = Get-ParRoot $parRoot[$x] }
        return $parRoot[$x]
    }
    function Union-Par([string]$x, [string]$y) {
        $rx = Get-ParRoot $x
        $ry = Get-ParRoot $y
        if ($rx -ne $ry) { $parRoot[$ry] = $rx }
    }
    $parCards = @($activeCards | Where-Object { $_.并行组 -match 'TC-\d{3}' })
    foreach ($c in $parCards) {
        $selfNo = [regex]::Match($c.文件, '^TC-(\d{3})').Groups[1].Value
        if ($selfNo) { Get-ParRoot $selfNo | Out-Null }
    }
    foreach ($c in $parCards) {
        $selfNo = [regex]::Match($c.文件, '^TC-(\d{3})').Groups[1].Value
        foreach ($m in [regex]::Matches($c.并行组, 'TC-(\d{3})')) {
            $otherNo = $m.Groups[1].Value
            if ($otherNo -ne $selfNo) { Union-Par $selfNo $otherNo }
        }
    }
    $groupMap = @{}
    foreach ($c in $parCards) {
        $selfNo = [regex]::Match($c.文件, '^TC-(\d{3})').Groups[1].Value
        $root = Get-ParRoot $selfNo
        if (-not $groupMap.ContainsKey($root)) { $groupMap[$root] = @() }
        $groupMap[$root] += $c
    }
    $grouped = @($groupMap.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Name = $_.Key; Group = @($_.Value) } })
    # 并行组文件级重叠检查（H3：touched_files 字段，防止两卡改同一文件）
    foreach ($g in $grouped) {
        $tfMap = @{}
        foreach ($card in $g.Group) {
            $tf = ''
            $rawCard = Get-Content -LiteralPath (Join-Path $cardDir $card.文件) -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($rawCard) {
                $cfm = Get-FrontMatter -Content $rawCard
                if ($cfm -and $cfm['touched_files']) { $tf = [string]$cfm['touched_files'] }
            }
            if (-not $tf -or $tf -eq 'null') {
                $parallelIssues += "并行组 $($g.Name)：$($card.文件) 未填写 front-matter touched_files——并行卡必须声明文件级修改范围（逗号分隔，以 code/ 为根），patrol 才能拦截文件重叠"
                continue
            }
            $tfMap[$card.文件] = @($tf -split ',' | ForEach-Object { $_.Trim().Trim('"', "'").ToLowerInvariant() } | Where-Object { $_ -ne '' })
        }
        $names = @($tfMap.Keys)
        for ($a = 0; $a -lt $names.Count; $a++) {
            for ($b = $a + 1; $b -lt $names.Count; $b++) {
                $overlap = @($tfMap[$names[$a]] | Where-Object { $_ -in $tfMap[$names[$b]] })
                if ($overlap.Count -gt 0) {
                    $parallelIssues += "并行组 $($g.Name)：$($names[$a]) 与 $($names[$b]) 修改范围重叠（touched_files：$($overlap -join ', ')）——禁止并行，需拆分或串行化（docs/自动化协作协议.md §3.6）"
                }
            }
        }
    }
    foreach ($g in $grouped) {
        $withWd = @($g.Group | Where-Object { $_.工作目录 })
        $dup = $withWd | Group-Object 工作目录 | Where-Object { $_.Count -gt 1 }
        foreach ($d in $dup) {
            $parallelIssues += "并行组 $($g.Name)：工作目录「$($d.Name)」被 $($d.Count) 张卡共用——并行卡必须独立 Worktree"
        }
    }
    if ($parallelIssues.Count -gt 0) {
        $parallelIssues | ForEach-Object { Write-Host "  [FAIL] $_" }
        $failCount += $parallelIssues.Count
    } else {
        Write-Host "  无"
    }
}

# 3.7 依赖顺序检查：depends_on 指向的未归档卡未 merged → WARN（受控并行例外允许，须在任务卡记录例外基线）
Write-Host "`n[依赖检查] depends_on 指向的任务卡状态："
$depWarnings = @()
$cardByNo = @{}
foreach ($c in $activeCards) {
    $no = [regex]::Match($c.文件, '^TC-(\d{3})').Groups[1].Value
    if ($no) { $cardByNo[$no] = $c }
}
foreach ($c in $activeCards) {
    $rawCard = Get-Content -LiteralPath (Join-Path $cardDir $c.文件) -Raw -Encoding UTF8
    $cfm = Get-FrontMatter -Content $rawCard
    $dep = if ($cfm -and $cfm['depends_on'] -and $cfm['depends_on'] -ne 'null') { [string]$cfm['depends_on'] } else { '' }
    if (-not $dep) { continue }
    $selfNo = [regex]::Match($c.文件, '^TC-(\d{3})').Groups[1].Value
    foreach ($m in [regex]::Matches($dep, 'TC-(\d{3})')) {
        $depNo = $m.Groups[1].Value
        if ($depNo -eq $selfNo) { continue }
        if ($cardByNo.ContainsKey($depNo)) {
            $depCard = $cardByNo[$depNo]
            if ($depCard.状态 -ne 'merged') {
                $depWarnings += "$($c.文件)：依赖 TC-$depNo（状态=$($depCard.状态)）尚未合并到 develop——本卡可能基于过期基线；受控并行例外须在任务卡记录例外基线与原因（docs/git-workflow.md §2.2）"
            }
        }
        # 依赖卡不在未归档列表中 = 已归档（流程要求 merged 后才归档），视为已处理
    }
}
if ($depWarnings.Count -gt 0) {
    $depWarnings | ForEach-Object { Write-Host "  [WARN] $_" }
    Write-Host "  （WARN 不阻断巡检；依赖例外须在任务卡记录例外基线）"
} else {
    Write-Host "  无"
}
# 4. Git 检查（容错：无 develop / 非 Git 仓库自动跳过）
Write-Host "`n[Git]"
$gitRepo = Test-Path -LiteralPath (Join-Path $root '.git')
if ($gitRepo) {
    try {
        $null = git -C $root rev-parse --verify develop 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [develop] 存在"
            # main 是生产分支，正常方向是 develop -> main（main 未合并到 develop 属正常），从提示中排除
            $unmerged = @(git -C $root branch --no-merged develop 2>$null | Where-Object { $_.Trim().TrimStart('*').Trim() -ne 'main' })
            if ($unmerged.Count -gt 0) {
                Write-Host "  未合并到 develop 的分支："
                $unmerged | ForEach-Object { Write-Host "    $_" }
            } else {
                Write-Host "  无未合并分支"
            }
            # 4.1 已合并但分支/worktree 残留检查（合并闭环收尾：merge-card.ps1 默认自动清理；残留 = 未清理，应处理）
            Write-Host "  [残留] 已合并到 develop 但仍存在的 feature 分支 / worktree："
            $leftover = @()
            $mergedFeat = @(git -C $root branch --merged develop 2>$null | ForEach-Object { $_.Trim().TrimStart('*').Trim() } | Where-Object { $_ -match '^feature/' })
            foreach ($mb in $mergedFeat) {
                $leftover += "分支 $mb 已合并但未删除——应执行：git branch -d $mb"
            }
            try {
                $wtList = @(git -C $root worktree list --porcelain 2>$null)
                $wi = 0
                while ($wi -lt $wtList.Count) {
                    if ($wtList[$wi] -match '^worktree (.+)$') {
                        $wtPath = $Matches[1].Trim()
                        if ($wtPath -ne $root) {
                            for ($wj = $wi + 1; $wj -lt $wtList.Count -and $wtList[$wj] -notmatch '^worktree '; $wj++) {
                                if ($wtList[$wj] -match '^branch refs/heads/feature/(.+)$') {
                                    $wtBranch = 'feature/' + $Matches[1].Trim()
                                    if ($mergedFeat -contains $wtBranch) {
                                        $leftover += "worktree $wtPath 检出已合并分支 $wtBranch——应执行：git worktree remove $wtPath"
                                    }
                                }
                            }
                        }
                    }
                    $wi++
                }
            } catch { }
            if ($leftover.Count -gt 0) {
                $leftover | ForEach-Object { Write-Host "    [WARN] $_" }
                Write-Host "    （WARN 不阻断巡检；清理失败或 -SkipCleanup 保留时出现，PM 手动处理后不再提示）"
            } else {
                Write-Host "    无残留"
            }
        } else {
            Write-Host "  [提示] 未检测到 develop 分支，跳过未合并分支检查"
        }
    } catch {
        Write-Host "  [提示] Git 检查失败：$($_.Exception.Message)"
    }
    try {
        $wt = @(git -C $root worktree list --porcelain 2>$null)
        $wtLines = $wt | Where-Object { $_ -match '^worktree ' }
        Write-Host "  [Worktree] 数量：$($wtLines.Count)"
        $wtLines | ForEach-Object { Write-Host "    $_" }
    } catch {
        Write-Host "  [提示] Worktree 检查失败：$($_.Exception.Message)"
    }
} else {
    Write-Host "  [提示] 非 Git 仓库，跳过"
}

# 4.5 安全：密钥扫描（P2-9；scan-secrets.ps1 存在则执行）
Write-Host "`n[安全] 密钥扫描："
$scanScript = Join-Path $scriptDir 'scan-secrets.ps1'
if (Test-Path -LiteralPath $scanScript) {
    & $scanScript
    if ($LASTEXITCODE -ne 0) {
        $failCount += 1
        Write-Host "  （存在疑似真实密钥的 FAIL 项——安全红线，见 AGENTS.md 通用安全红线）"
    }
} else {
    Write-Host "  （未找到 scan-secrets.ps1，跳过）"
}
# 5. 行动清单
Write-Host "`n[行动清单]"
Write-Host "  1. 状态为 done 的回报 → PM 读回报验收 → 通过后执行 .\scripts\merge-card.ps1 合并 → 归档任务卡"
Write-Host "  2. 状态为 todo/in_progress 但超期 → 询问对应角色状态"
Write-Host "  3. 有未合并分支 → 验收通过后由 PM 合并到 develop"
Write-Host "  4. 存在 [FAIL] 项 → PM 先处理后再派发新任务（自动化模式下落盘与认知恢复是生死线）"
Write-Host "  5. 任务卡/回报状态有变化 → 运行 .\scripts\generate-status.ps1 同步 project-status.md 与 thread-routing.md 的自动生成区"
Write-Host "  6. 代码类卡缺独立 Worktree → 用 .\scripts\new-worktree.ps1 创建后自动回填 front-matter"
Write-Host "  7. 存在已合并残留告警 → 清理 feature 分支与 worktree（git worktree remove + git branch -d，或由 merge-card.ps1 自动执行）"
Write-Host "  8. 存在安全 FAIL 项 → 立即 STOP 相关任务，按 AGENTS.md 安全红线处理（轮换密钥后重扫）"

# 复盘触发提醒（P2-7：累计归档任务卡达到 10 的倍数 → 建议复盘）
$archiveDir = Join-Path $cardDir 'archive'
$archivedCount = 0
if (Test-Path -LiteralPath $archiveDir) {
    $archivedCount = @(Get-ChildItem -LiteralPath $archiveDir -Filter 'TC-*.md' -File -ErrorAction SilentlyContinue).Count
}
$reviewIndex = Join-Path $root 'docs\retrospectives\README.md'
$lastReviewBase = 0
if (Test-Path -LiteralPath $reviewIndex) {
    $idxText = Get-Content -LiteralPath $reviewIndex -Raw -Encoding UTF8
    $reviewRows = [regex]::Matches($idxText, '(?m)^\|\s*RT-\d{3}.*\|\s*(\d+)\s*\|')
    if ($reviewRows.Count -gt 0) {
        $lastReviewBase = [int]$reviewRows[$reviewRows.Count - 1].Groups[1].Value
    }
}
$newSinceReview = $archivedCount - $lastReviewBase
if ($archivedCount -gt 0 -and $newSinceReview -ge 10) {
    Write-Host "  9. 已累计归档 $archivedCount 张任务卡，自上次复盘（基线 $lastReviewBase 张）以来新增 $newSinceReview 张（≥10）→ 按 PM-操作指南.md §3.5 执行复盘，并在 docs/retrospectives/README.md 索引登记该次复盘时的已归档数"
}
Write-Host "`n===== 巡检结束 ====="
if ($failCount -gt 0) {
    Write-Host "[结果] FAIL：$failCount 项需处理（详见上方 [FAIL]）"
    exit 1
}
Write-Host "[结果] PASS"
exit 0
