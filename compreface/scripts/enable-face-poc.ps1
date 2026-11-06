#Requires -Version 5.1
<#
.SYNOPSIS
    SP-3 门禁置位 / 回滚 / 状态（人工门禁动作的可执行载体）。

.DESCRIPTION
    enable   : 备份两个 .env，置 MEETING_FACE_POC_PASSED=true、MEETING_G3_VIDEO=true、
               MEETING_FACE_ENABLED=true，写入 G2 相似度阈值，并生成 evidence/poc-enablement-record.md
    rollback : 恢复 fail-closed（三个开关 false、阈值留空），保留置位留档并追加回滚记录
    status   : 只读显示四个开关与留档状态

    阈值来源：优先 -Threshold 显式值；否则从 samples/calibration/calibration-report-*.md 最新一份
              解析「帧域满足目标的最大阈值」，并在留档里标注该报告样本量不足、仅供联调。
    纪律：本脚本不生成、不伪造 G0/G1/G2/G3 报告；-G3EvidenceDir 未提供时在留档里逐项标注「未提供」。
          置位后 deploy.ps1 会要求置位留档存在，否则仍拒绝启动。

.EXAMPLE
    .\scripts\enable-face-poc.ps1 -Action status
    .\scripts\enable-face-poc.ps1 -Action enable -Threshold 0.55 -G3EvidenceDir .\evidence\g3
    .\scripts\enable-face-poc.ps1 -Action rollback
#>
[CmdletBinding()]
param(
    [ValidateSet('status', 'enable', 'rollback')][string]$Action = 'status',
    [double]$Threshold = 0,
    [string]$G3EvidenceDir = '',
    [string]$DeployEnvPath = '',
    [string]$AiServerEnvPath = '',
    [switch]$SkipBackup
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Workspace = [System.IO.Path]::GetFullPath((Join-Path $Root '..\..'))
if (-not $DeployEnvPath) { $DeployEnvPath = Join-Path $Root '.env' }
if (-not $AiServerEnvPath) {
    $AiServerEnvPath = Join-Path $Workspace 'mediation-ai\mediation-ai-module\mediation-module-ai-server\.env'
}
$EvidenceDir = Join-Path $Root 'evidence'
$RecordPath = Join-Path $EvidenceDir 'poc-enablement-record.md'
# 备份统一放 mediation-deploy/secrets/（已被仓库 .gitignore 排除），避免在源码目录留下含密钥的 .bak
$BackupDir = [System.IO.Path]::GetFullPath((Join-Path $Root '..\secrets'))
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

function Read-EnvValue([string]$Path, [string]$Name) {
    if (-not (Test-Path -LiteralPath $Path)) { return '<env 不存在>' }
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match "^\s*$Name\s*=\s*(.*)$") {
            return (($Matches[1] -split '#', 2)[0]).Trim()
        }
    }
    return '<未设置>'
}

function Set-EnvValue([string]$Path, [string]$Name, [string]$Value) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "env 文件不存在：$Path" }
    $lines = [System.Collections.Generic.List[string]]::new()
    [System.IO.File]::ReadAllLines($Path) | ForEach-Object { $lines.Add($_) }
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^\s*$Name\s*=") {
            if (-not $found) { $lines[$i] = "$Name=$Value"; $found = $true }
            else { $lines[$i] = "# $($lines[$i])  # 重复项由 enable-face-poc.ps1 注释" }
        }
    }
    if (-not $found) { $lines.Add("$Name=$Value") }
    [System.IO.File]::WriteAllLines($Path, $lines, (New-Object System.Text.UTF8Encoding($false)))
}

function Resolve-Threshold {
    if ($Threshold -gt 0 -and $Threshold -lt 1) {
        return @{ Value = $Threshold; Source = '命令行 -Threshold 显式指定'; Limited = $false }
    }
    $reports = @(Get-ChildItem (Join-Path $Root 'samples\calibration') -Filter 'calibration-report-*.md' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
    if ($reports.Count -eq 0) { throw '未显式给 -Threshold，且找不到标定报告；请先跑 calibrate-threshold.ps1 或直接传阈值' }
    $text = Get-Content -Raw -Encoding UTF8 $reports[0].FullName
    $hits = [regex]::Matches($text, '满足目标的最大阈值：\*\*([0-9.]+)\*\*')
    if ($hits.Count -eq 0) { throw "报告 $($reports[0].Name) 中未解析到帧域建议阈值，请显式传 -Threshold" }
    $v = [double]::Parse($hits[$hits.Count - 1].Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    return @{ Value = $v; Source = $reports[0].FullName; Limited = $true }
}

function Write-Record([hashtable]$t) {
    New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
    $g3 = if ($G3EvidenceDir -and (Test-Path -LiteralPath $G3EvidenceDir)) {
        (Get-ChildItem -LiteralPath $G3EvidenceDir -File | Select-Object -ExpandProperty Name) -join ', '
    } else { '未提供（-G3EvidenceDir 未指向有效目录）' }
    $lines = @(
        '# SP-3 门禁置位留档',
        '',
        "- 时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        '- 动作：enable（由 enable-face-poc.ps1 执行）',
        '- 用户放行声明：2026-11-06「不考虑门禁，当前真人测试的门禁都通过」；2026-11-07「继续」',
        "- 相似度阈值：**$($t.Value)**",
        "- 阈值来源：$($t.Source)",
        $(if ($t.Limited) { '- **阈值局限**：来源报告的样本量低于 G2 门槛（正/负各 ≥20 组），该数值仅供联调，正式生产须以真人 G2 报告数值替换' } else { '- 阈值由管理员显式指定，须确认其来自真人 G2 标定报告' }),
        '',
        '## 开关变更',
        '',
        '| 变量 | 文件 | 置位后 |',
        '|---|---|---|',
        '| MEETING_FACE_POC_PASSED | compreface/.env | true |',
        '| MEETING_G3_VIDEO | ai-server/.env | true |',
        '| MEETING_FACE_ENABLED | ai-server/.env | true |',
        "| MEETING_FACE_SIMILARITY_THRESHOLD | ai-server/.env | $($t.Value) |",
        '',
        '## 留档清点（如实登记，不伪造）',
        '',
        '- G0 双人真机日志报告：本工作区未见（用户声明真人测试已通过）',
        '- G1 20 段真实帧召回报告：本工作区未见（用户声明真人测试已通过）',
        '- 真人 G2 FAR/FRR 报告：本工作区未见；现有报告基于官方样例，样本量不足',
        "- G3 四项留档：$g3",
        '- V5/V8 巡检：见 README §7 与 verify.ps1 的 -CheckLatency / -CheckResidual 段',
        '',
        '## 回滚',
        '',
        '```powershell',
        '.\scripts\enable-face-poc.ps1 -Action rollback',
        '```',
        '',
        '> 置位不解除红线：只做 1:1、禁 1:N、不建底库、帧不落盘、不改实名状态、',
        '> FACE_MISMATCH 措辞固定「疑似不一致，请现场确认」；阈值未标定时仍恒 FACE_INSUFFICIENT。'
    )
    [System.IO.File]::WriteAllLines($RecordPath, $lines, (New-Object System.Text.UTF8Encoding($false)))
}

Write-Host "===== SP-3 门禁 $Action =====" -ForegroundColor Cyan
Write-Host "部署件 env : $DeployEnvPath"
Write-Host "ai-server  : $AiServerEnvPath"

if ($Action -eq 'status') {
    Write-Host ("MEETING_FACE_POC_PASSED           = {0}" -f (Read-EnvValue $DeployEnvPath 'MEETING_FACE_POC_PASSED'))
    Write-Host ("MEETING_G3_VIDEO                  = {0}" -f (Read-EnvValue $AiServerEnvPath 'MEETING_G3_VIDEO'))
    Write-Host ("MEETING_FACE_ENABLED              = {0}" -f (Read-EnvValue $AiServerEnvPath 'MEETING_FACE_ENABLED'))
    Write-Host ("MEETING_FACE_SIMILARITY_THRESHOLD = {0}" -f (Read-EnvValue $AiServerEnvPath 'MEETING_FACE_SIMILARITY_THRESHOLD'))
    Write-Host ("置位留档存在                      = {0}" -f (Test-Path -LiteralPath $RecordPath))
    return
}

if (-not (Test-Path -LiteralPath $DeployEnvPath)) { throw "部署件 .env 不存在：$DeployEnvPath" }
if (-not (Test-Path -LiteralPath $AiServerEnvPath)) { throw "ai-server .env 不存在：$AiServerEnvPath" }

if ($Action -eq 'rollback') {
    if (-not $SkipBackup) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item $DeployEnvPath (Join-Path $BackupDir "compreface.env.bak-$stamp")
        Copy-Item $AiServerEnvPath (Join-Path $BackupDir "ai-server.env.bak-$stamp")
    }
    Set-EnvValue $DeployEnvPath 'MEETING_FACE_POC_PASSED' 'false'
    Set-EnvValue $AiServerEnvPath 'MEETING_G3_VIDEO' 'false'
    Set-EnvValue $AiServerEnvPath 'MEETING_FACE_ENABLED' 'false'
    Set-EnvValue $AiServerEnvPath 'MEETING_FACE_SIMILARITY_THRESHOLD' ''
    if (Test-Path -LiteralPath $RecordPath) {
        Add-Content -Path $RecordPath -Encoding UTF8 -Value "`n- 回滚：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') 已恢复 fail-closed（开关 false、阈值留空）"
    }
    Write-Host '[ ok ] 已回滚到 fail-closed' -ForegroundColor Green
    return
}

$t = Resolve-Threshold
if ($t.Value -le 0 -or $t.Value -ge 1) { throw "阈值必须在 (0,1)：$($t.Value)" }
Write-Host "[info] 阈值 $($t.Value) 来源：$($t.Source)" -ForegroundColor Yellow
if ($t.Limited) { Write-Host '[warn] 该报告样本量不足，仅供联调；正式投产须替换为真人 G2 报告数值' -ForegroundColor Yellow }

if (-not $SkipBackup) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item $DeployEnvPath (Join-Path $BackupDir "compreface.env.bak-$stamp")
    Copy-Item $AiServerEnvPath (Join-Path $BackupDir "ai-server.env.bak-$stamp")
    Write-Host "[ ok ] 已备份两个 .env 到 $BackupDir（后缀 $stamp）" -ForegroundColor Green
}

Set-EnvValue $DeployEnvPath 'MEETING_FACE_POC_PASSED' 'true'
Set-EnvValue $AiServerEnvPath 'MEETING_G3_VIDEO' 'true'
Set-EnvValue $AiServerEnvPath 'MEETING_FACE_ENABLED' 'true'
Set-EnvValue $AiServerEnvPath 'MEETING_FACE_SIMILARITY_THRESHOLD' ([string]$t.Value)
Write-Record $t

Write-Host ''
Write-Host '[ ok ] 门禁已置位，置位留档：' -ForegroundColor Green
Write-Host "       $RecordPath"
Write-Host '[next] 1) 重启 ai-server 使 .env 生效（IDEA 的 AiApplication / 或部署环境注入）'
Write-Host '[next] 2) 跑 .\scripts\verify.ps1 -CheckLatency -CheckResidual 并回写 README §7'
Write-Host '[next] 3) 真人 G2 报告到手后，用 -Action rollback → -Action enable -Threshold <真人值> 替换联调值'
Write-Host '[next] 4) 回滚随时可执行：-Action rollback'
