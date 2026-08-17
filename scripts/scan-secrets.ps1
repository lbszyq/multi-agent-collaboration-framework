<#
.SYNOPSIS
扫描 git tracked 文件中的疑似密钥/凭据，防止明文密钥入库（AGENTS.md 安全红线）。

.DESCRIPTION
扫描范围：git ls-files 列出的文本文件（排除 .git、二进制扩展名、示例文件）。
判定分级：
  FAIL  = 高置信密钥模式（AWS AKIA / 私钥块 / GitHub PAT / OpenAI sk- / 腾讯云 SecretKey），行内无示例关键词
  WARN  = 低置信模式（password/secret/token = 值），值疑似占位或上下文模糊，需人工确认
白名单：*.example / *.sample 整文件跳过；行内含 example/示例/占位/your-/xxx/****/<...>/demo/sample 降级为跳过或 WARN。
无 FAIL 时退出码 0；有 FAIL 退出码 1（供 patrol.ps1 引用）。

.EXAMPLE
.\scripts\scan-secrets.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir

Write-Host "===== 密钥扫描：$root ====="

# ---------- 高置信模式（命中 → FAIL，除非行内含示例关键词） ----------
$highConfidence = @(
    'AKIA[0-9A-Z]{16}',                                          # AWS Access Key
    '-----BEGIN (?:RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----', # 私钥块
    'ghp_[A-Za-z0-9]{30,}',                                      # GitHub Personal Access Token
    'sk-[A-Za-z0-9_-]{24,}',                                     # OpenAI 等 sk- 密钥
    'AKID[0-9A-Za-z]{13,}',                                      # 腾讯云 SecretId 常见前缀
    'SecretAccessKey[=:]\s*["'']?[A-Za-z0-9/+]{20,}'             # AWS Secret
)

# ---------- 低置信模式（命中 → WARN） ----------
$lowConfidence = @(
    '(?i)(password|passwd|pwd|secret|api[_-]?key|client[_-]?secret|access[_-]?token|private[_-]?key|auth[_-]?token)\s*[:=]\s*["'']([^"'']{6,})["'']'
)

# ---------- 行级白名单关键词（含这些词的命中行视为示例，跳过） ----------
$whitelistPattern = 'example|示例|占位|placeholder|your-|your_|xxx|<[^>]+>|\*\*\*\*|demo|sample|dummy|fake|changeme|change-me|qa-secret|password\s*[:=]\s*["'']?(password|passwd)["'']?'

# ---------- 二进制/跳过扩展名 ----------
$skipExtensions = @('.png','.jpg','.jpeg','.gif','.ico','.pdf','.zip','.gz','.tar','.woff','.woff2','.ttf','.eot','.exe','.dll','.class','.pyc','.lock')
# 整文件跳过（示例/依赖文件）
$skipFiles = @('.env.example', '.env.sample')

# ---------- 收集 tracked 文件 ----------
$files = @(git -C $root -c core.quotepath=false ls-files 2>$null)
if ($files.Count -eq 0) {
    Write-Host "  （无 tracked 文件或非 Git 仓库）"
    Write-Host "[结果] PASS"
    exit 0
}

$failCount = 0
$warnCount = 0
$scanned = 0

foreach ($rel in $files) {
    $full = Join-Path $root $rel
    if (-not (Test-Path -LiteralPath $full)) { continue }
    $name = Split-Path -Leaf $rel
    $ext = [System.IO.Path]::GetExtension($rel).ToLowerInvariant()
    if ($skipExtensions -contains $ext) { continue }
    if ($skipFiles -contains $name.ToLowerInvariant()) { continue }
    if ($rel -match '\.example(\.|$)') { continue }
    if ((Get-Item -LiteralPath $full).Length -gt 2MB) { continue }  # 跳过大文件（依赖/生成物）
    $scanned++

    $lines = Get-Content -LiteralPath $full -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $lines) { continue }
    $lineNo = 0
    foreach ($line in $lines) {
        $lineNo++
        if ($line.Length -gt 500) { continue }  # 超长行（压缩 JSON 等）跳过，避免误报
        if ($line -match $whitelistPattern) { continue }
        $hit = $null
        foreach ($p in $highConfidence) {
            if ($line -match $p) { $hit = [pscustomobject]@{ Pattern = $p; Level = 'FAIL' }; break }
        }
        if (-not $hit) {
            foreach ($p in $lowConfidence) {
                if ($line -match $p) {
                    $val = $Matches[2]
                    # 值本身像占位（短/纯数字/常见占位词）→ WARN，否则 FAIL
                    $level = if ($val.Length -le 8 -or $val -match '^(123456|password|passwd|secret|changeme|change-me|qa-secret|000000|admin)$') { 'WARN' } else { 'FAIL' }
                    $hit = [pscustomobject]@{ Pattern = $p; Level = $level }
                    break
                }
            }
        }
        if ($hit) {
            $displayLine = $line.Trim()
            if ($displayLine.Length -gt 120) { $displayLine = $displayLine.Substring(0, 120) + '…' }
            if ($hit.Level -eq 'FAIL') {
                Write-Host "  [FAIL] $rel`:$lineNo  $displayLine"
                $failCount++
            } else {
                Write-Host "  [WARN] $rel`:$lineNo  $displayLine"
                $warnCount++
            }
        }
    }
}

Write-Host "  扫描 $scanned 个文本文件"
if ($failCount -gt 0) {
    Write-Host "[结果] FAIL：$failCount 处疑似真实密钥（安全红线，立即处理并轮换，见 AGENTS.md 通用安全红线）"
    exit 1
}
Write-Host "[结果] PASS（WARN $warnCount 项请人工确认）"
exit 0
