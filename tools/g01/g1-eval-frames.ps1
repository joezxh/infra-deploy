<#
.SYNOPSIS
    G1 真实会中帧召回率/误报率评测（YuNet 检测，经 CompreFace 1:2.0）。

.DESCRIPTION
    输入：collect.html 采集的帧目录 + labels.csv（identity,file,ts,expect,note）
      expect=1  应检出人脸（单人）
      expect=0  不应检出人脸（无人场景，用于误报率）
      expect=2  两人同框（应检出 >=2 张脸）

    指标：
      召回率 = (expect=1 且检出>=1 + expect=2 且检出>=2) / (expect in {1,2})
      误报率 = (expect=0 且检出>=1) / (expect=0)
    判据：帧数 >= MinFrames(20) 且 召回 >= MinRecall(0.85) 且 误报 <= MaxFalsePositive(0.05)

.EXAMPLE
    # 现场采集目录由 collect.html 落盘；仓库内不存在该目录
    .\g1-eval-frames.ps1 -FramesDir D:\evidence\g1-2026-11-xx\g1-frames `
        -LabelsPath D:\evidence\g1-2026-11-xx\g1-frames\labels.csv `
        -OutFile D:\evidence\g1-2026-11-xx\g1-report.md
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$FramesDir,
    [string]$LabelsPath = '',
    [string]$ApiBase = 'http://127.0.0.1:8050/face/api/v1/detection/detect',
    [string]$ApiKey = '',
    [int]$MinFrames = 20,
    [double]$MinRecall = 0.85,
    [double]$MaxFalsePositive = 0.05,
    [string]$OutFile = ''
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $FramesDir)) { Write-Host "[fail] 帧目录不存在：$FramesDir" -ForegroundColor Red; exit 1 }
if (-not $LabelsPath) { $LabelsPath = Join-Path $FramesDir 'labels.csv' }
if (-not (Test-Path -LiteralPath $LabelsPath)) {
    Write-Host "[fail] 缺少标注文件：$LabelsPath（每行 identity,file,ts,expect,note）" -ForegroundColor Red; exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ApiKey) {
    $envFile = Join-Path $scriptDir '..\..\compreface\.env'
    if (Test-Path $envFile) {
        foreach ($line in [System.IO.File]::ReadAllLines($envFile)) {
            if ($line -match '^\s*API_KEY=(.+)$') { $ApiKey = $Matches[1].Trim(); break }
        }
    }
}
if (-not $ApiKey) { Write-Host '[fail] 未取到服务 key：请用 -ApiKey 指定或检查 .env' -ForegroundColor Red; exit 1 }

function Invoke-Detect {
    param([string]$File)
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        $null = & curl.exe -s --max-time 30 -X POST $ApiBase -H "x-api-key: $ApiKey" -F "file=@$File" -o $tmp
        $raw = [System.IO.File]::ReadAllText($tmp)
        if (-not $raw) { return @{ ok = $false; n = 0; reason = '空响应' } }
        $j = $raw | ConvertFrom-Json
        if ($j.message) {
            # code=28：图片中无人脸 —— 这是「检测正常、结果为 0 张脸」，不是调用失败
            # （CompreFace 对无人脸返回错误码而非空 result，误判会导致负样本被跳过、误报率算不出）
            if ([int]$j.code -eq 28) { return @{ ok = $true; n = 0; probs = @() } }
            return @{ ok = $false; n = 0; reason = "code=$($j.code) $($j.message)" }
        }
        $res = @($j.result)
        return @{ ok = $true; n = $res.Count; probs = @($res | ForEach-Object { $_.box.probability }) }
    } catch {
        return @{ ok = $false; n = 0; reason = $_.Exception.Message }
    } finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}

$rows = @()
foreach ($line in [System.IO.File]::ReadAllLines($LabelsPath)) {
    if (-not $line.Trim() -or $line.StartsWith('#')) { continue }
    $p = $line.Split(',')
    if ($p.Count -lt 4) { continue }
    $rows += [PSCustomObject]@{ Identity = $p[0]; File = $p[1]; Ts = $p[2]; Expect = $p[3]; Note = $(if ($p.Count -gt 4) { $p[4] } else { '' }) }
}
Write-Host "标注条目：$($rows.Count)"

$expectPos = 0; $hitPos = 0; $expectNeg = 0; $falsePos = 0; $skip = 0
$details = @()
foreach ($r in $rows) {
    $path = Join-Path $FramesDir (Join-Path $r.Identity $r.File)
    if (-not (Test-Path -LiteralPath $path)) { $path = Join-Path $FramesDir $r.File }
    if (-not (Test-Path -LiteralPath $path)) { $skip++; continue }
    $d = Invoke-Detect -File $path
    if (-not $d.ok) { $skip++; $details += [PSCustomObject]@{ Id = $r.Identity; File = $r.File; Expect = $r.Expect; Detected = -1; Prob = ''; Note = $d.reason }; continue }
    $e = [int]$r.Expect
    $hit = $false
    if ($e -eq 1 -and $d.n -ge 1) { $hit = $true }
    if ($e -eq 2 -and $d.n -ge 2) { $hit = $true }
    if ($e -eq 1 -or $e -eq 2) { $expectPos++; if ($hit) { $hitPos++ } }
    if ($e -eq 0) { $expectNeg++; if ($d.n -ge 1) { $falsePos++ } }
    $details += [PSCustomObject]@{ Id = $r.Identity; File = $r.File; Expect = $e; Detected = $d.n; Prob = $(if ($d.probs.Count) { ($d.probs | ForEach-Object { '{0:N3}' -f $_ }) -join ',' } else { '' }); Note = $r.Note }
}

$total = $expectPos + $expectNeg
$recall = if ($expectPos -gt 0) { $hitPos / $expectPos } else { 0 }
$fp = if ($expectNeg -gt 0) { $falsePos / $expectNeg } else { 0 }

Write-Host ''
Write-Host "有效评测帧：$total（应有人脸 $expectPos / 应无人脸 $expectNeg），跳过 $skip"
Write-Host ("召回率：{0:P2}（{1}/{2}）  误报率：{3:P2}（{4}/{5}）" -f $recall, $hitPos, $expectPos, $fp, $falsePos, $expectNeg)
$enough = ($total -ge $MinFrames)
$pass = $enough -and ($recall -ge $MinRecall) -and ($fp -le $MaxFalsePositive)
Write-Host ''
if (-not $enough) { Write-Host "[warn] 有效帧数 $total < $MinFrames：样本量不足，结论不可用于门禁" -ForegroundColor Yellow }
if ($pass) { Write-Host "[结论] G1 **通过**（召回 >= $MinRecall 且 误报 <= $MaxFalsePositive）" -ForegroundColor Green }
else { Write-Host ("[结论] G1 **未通过**（召回 {0:P2} / 误报 {1:P2}）" -f $recall, $fp) -ForegroundColor Red }

if (-not $OutFile) { $OutFile = Join-Path $FramesDir ("g1-report-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.md') }
$L = New-Object System.Collections.Generic.List[string]
$L.Add('# G1 真实会中帧召回率/误报率报告')
$L.Add('')
$L.Add("- 生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$L.Add("- 帧目录：$FramesDir")
$L.Add("- 检测接口：$ApiBase")
$L.Add("- 有效帧：$total（应有人脸 $expectPos / 应无人脸 $expectNeg），跳过 $skip")
$L.Add('')
$L.Add(("**召回率 = {0:P2}**（{1}/{2}）　**误报率 = {3:P2}**（{4}/{5}）" -f $recall, $hitPos, $expectPos, $fp, $falsePos, $expectNeg))
$L.Add('')
$L.Add("判据：有效帧 >= $MinFrames，召回 >= $MinRecall，误报 <= $MaxFalsePositive")
$L.Add('')
$L.Add('| 身份 | 文件 | 期望 | 检出人脸数 | 置信度 | 备注 |')
$L.Add('|---|---|---|---|---|---|')
foreach ($d in $details) { $L.Add("| $($d.Id) | $($d.File) | $($d.Expect) | $($d.Detected) | $($d.Prob) | $($d.Note) |") }
$L.Add('')
$L.Add('## 结论')
$L.Add('')
if ($pass) { $L.Add('- **G1 通过**：召回与误报均满足判据。') }
else {
    $L.Add('- **G1 未通过**：需补足真实帧数量并排查漏检/误报场景（逆光、弱光、侧脸、口罩）。')
    $L.Add('- 不得以样例图或合成帧替代真机帧来置位门禁。')
}
[System.IO.File]::WriteAllLines($OutFile, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "报告已写出：$OutFile"
if (-not $pass) { exit 3 }