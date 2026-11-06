<#
.SYNOPSIS
    G2 相似度阈值标定工具（YuNet + SFace / CompreFace 1.2.0）。

.DESCRIPTION
    对本地采集的人脸样本做 1:1 相似度标定，输出 FAR/FRR 曲线与建议阈值。

    样本目录约定（默认 samples/calibration）：
        positive/<person_id>/*.jpg    同一自然人、不同时段/光照/角度/表情的照片（正样本对）
        negative/<person_id>/*.jpg    不同自然人的照片（负样本对，跨人两两配对）

    两个域（必须都看）：
        - 原图域：直接用样本原图比对；
        - 帧域：按前端 grabFrame 口径预处理（长边 640 + JPEG q0.72）后比对。
          生产链路的相似度来自「浏览器抓帧 → 上传」，帧域才是阈值依据；
          原图域会系统性高估相似度（实测同人 0.919 → 帧域 0.663）。

    采集规范（不满足则结果不可用于生产）：
      - 至少 2 名参与者，每人 >= 10 张，覆盖不同日期/时段/光照/朝向/表情/距离；
      - 证件照式正面照与「会中帧」式随意照混合；
      - 全部单人脸（多脸会被 CompreFace 拒绝，脚本跳过并计 SKIP）；
      - 分组必须人工确认——文件名后缀不代表同一人（官方样例 005_A 与 001_A 实测仅 0.21，
        007_B 与 008_B 仅 0.083，均为不同人）；
      - 以东亚面孔为主。

    本脚本只产出报告，不修改 ai-server 的 MEETING_FACE_SIMILARITY_THRESHOLD：
    阈值写入属人工门禁动作（G2），需评审报告后显式设置。
#>
[CmdletBinding()]
param(
    [string]$CalibDir = '',
    [string]$ApiBase = 'http://127.0.0.1:8050/face/api/v1/verification/verify',
    [string]$ApiKey = '',
    [string]$ReportDir = '',
    [double]$TargetFar = 0.001,
    [double]$TargetFrr = 0.05,
    [int]$MaxPairsPerPerson = 60,
    [switch]$SkipFrameDomain
)

$ErrorActionPreference = 'Stop'

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $CalibDir) { $CalibDir = Join-Path $scriptDir '..\samples\calibration' }
$CalibDir = [System.IO.Path]::GetFullPath($CalibDir)

function Write-Section($t) { Write-Host ''; Write-Host "===== $t =====" -ForegroundColor Cyan }

function Resolve-ApiKey {
    param([string]$Explicit)
    if ($Explicit) { return $Explicit }
    $envFile = Join-Path $scriptDir '..\.env'
    if (Test-Path $envFile) {
        $lines = Get-Content -Encoding UTF8 $envFile
        $outer = ($lines | Where-Object { $_ -match '^\s*API_KEY=' } | Select-Object -First 1)
        $svc = ($lines | Where-Object { $_ -match '^\s*COMPREFACE_API_KEY=' } | Select-Object -First 1)
        if ($ApiBase -like '*/face/api/*') {
            if ($outer) { return ($outer -split '=', 2)[1].Trim() }
        } else {
            if ($svc) { return ($svc -split '=', 2)[1].Trim() }
        }
        if ($outer) { return ($outer -split '=', 2)[1].Trim() }
        if ($svc) { return ($svc -split '=', 2)[1].Trim() }
    }
    if ($env:COMPREFACE_API_KEY) { return $env:COMPREFACE_API_KEY }
    return ''
}

function Invoke-Verify {
    param([string]$Source, [string]$Target)
    $tmpOut = [System.IO.Path]::GetTempFileName()
    try {
        $null = & curl.exe -s --max-time 30 -X POST $ApiBase `
            -H "x-api-key: $ApiKey" `
            -F "source_image=@$Source" -F "target_image=@$Target" -o $tmpOut
        $raw = Get-Content -Raw -Encoding UTF8 $tmpOut
        if (-not $raw) { return @{ ok = $false; reason = '空响应' } }
        $j = $raw | ConvertFrom-Json
        if ($j.message) { return @{ ok = $false; reason = "code=$($j.code) $($j.message)" } }
        if ($null -eq $j.result) { return @{ ok = $false; reason = '无 result 字段' } }
        $sim = @($j.result)[0].face_matches[0].similarity
        if ($null -eq $sim) { return @{ ok = $false; reason = '无 similarity' } }
        return @{ ok = $true; similarity = [double]$sim }
    } catch {
        return @{ ok = $false; reason = $_.Exception.Message }
    } finally {
        Remove-Item $tmpOut -ErrorAction SilentlyContinue
    }
}

function Get-Percentile {
    param([double[]]$Values, [double]$P)
    if (-not $Values -or $Values.Count -eq 0) { return $null }
    $s = $Values | Sort-Object
    $idx = [Math]::Min($s.Count - 1, [Math]::Max(0, [Math]::Ceiling($P * $s.Count) - 1))
    return [double]$s[$idx]
}

function Get-Pairs {
    param([string[]]$Files, [int]$Max)
    $pairs = @()
    for ($i = 0; $i -lt $Files.Count - 1; $i++) {
        for ($j = $i + 1; $j -lt $Files.Count; $j++) {
            $pairs += , @($Files[$i], $Files[$j])
            if ($pairs.Count -ge $Max) { return $pairs }
        }
    }
    return $pairs
}

function Get-ImageFiles {
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) { return @() }
    return @(Get-ChildItem $Dir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '^\.(jpg|jpeg|png)$' } | Select-Object -ExpandProperty FullName)
}

Write-Section '参数与环境'
if (-not (Test-Path -LiteralPath $CalibDir)) { Write-Host "[fail] 样本目录不存在：$CalibDir" -ForegroundColor Red; exit 1 }
if (-not $ApiKey) { $ApiKey = Resolve-ApiKey }
Write-Host "样本目录 : $CalibDir"
Write-Host "接口     : $ApiBase"
Write-Host "服务 key : $(if ($ApiKey) { '已获取（长度 ' + $ApiKey.Length + '）' } else { '<未配置>' })"
Write-Host "目标 FAR : $TargetFar   目标 FRR : $TargetFrr"

$posRoot = Join-Path $CalibDir 'positive'
$negRoot = Join-Path $CalibDir 'negative'
if (-not (Test-Path $posRoot)) { Write-Host "[fail] 缺少正样本目录：$posRoot" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $negRoot)) { Write-Host "[fail] 缺少负样本目录：$negRoot" -ForegroundColor Red; exit 1 }

$posGroups = @()
foreach ($d in (Get-ChildItem -Directory $posRoot -ErrorAction SilentlyContinue)) {
    $f = Get-ImageFiles $d.FullName
    if ($f.Count -ge 2) { $posGroups += , @{ Name = $d.Name; Files = $f } }
    else { Write-Host "  [skip] 正样本组 $($d.Name)：照片不足 2 张" -ForegroundColor DarkGray }
}
$negGroups = @()
foreach ($d in (Get-ChildItem -Directory $negRoot -ErrorAction SilentlyContinue)) {
    $f = Get-ImageFiles $d.FullName
    if ($f.Count -ge 1) { $negGroups += , @{ Name = $d.Name; Files = $f } }
}
Write-Host "正样本组：$($posGroups.Count)   负样本组：$($negGroups.Count)"

$frameMap = @{}
if (-not $SkipFrameDomain) {
    Write-Section '帧域预处理（长边 640 + JPEG q0.72，与前端 grabFrame 口径一致）'
    $framesDir = Join-Path $CalibDir '_frames'
    $py = @'
import sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGB')
w, h = im.size
s = 640.0 / max(w, h)
im = im.resize((max(2, int(w * s) // 2 * 2), max(2, int(h * s) // 2 * 2)), Image.LANCZOS)
im.save(dst, 'JPEG', quality=72)
'@
    $all = @()
    foreach ($g in $posGroups) { $all += $g.Files }
    foreach ($g in $negGroups) { $all += $g.Files }
    $ok = 0; $bad = 0
    foreach ($f in ($all | Select-Object -Unique)) {
        $rel = $f.Substring($CalibDir.Length).TrimStart('\')
        $out = Join-Path $framesDir $rel
        New-Item -ItemType Directory -Force (Split-Path -Parent $out) | Out-Null
        try {
            & python -c $py $f $out 2>$null | Out-Null
            if (Test-Path -LiteralPath $out) { $frameMap[$f] = $out; $ok++ } else { $bad++ }
        } catch { $bad++ }
    }
    Write-Host "帧域副本生成：成功 $ok / 失败 $bad（目录 $framesDir）"
    if ($bad -gt 0 -and $ok -eq 0) { Write-Host '[warn] 帧域预处理不可用（缺 python/PIL？），本次只跑原图域' -ForegroundColor Yellow; $frameMap = @{} }
}

function Invoke-Domain {
    param([string]$Label, [hashtable]$Map)
    Write-Host ''
    Write-Host "--- 采集：$Label ---"
    $pos = New-Object System.Collections.Generic.List[double]
    $neg = New-Object System.Collections.Generic.List[double]
    $skip = 0

    foreach ($g in $posGroups) {
        $files = @($g.Files | ForEach-Object { if ($Map.ContainsKey($_)) { $Map[$_] } else { $_ } })
        $pairs = Get-Pairs -Files $files -Max $MaxPairsPerPerson
        $okc = 0
        foreach ($pr in $pairs) {
            $r = Invoke-Verify -Source $pr[0] -Target $pr[1]
            if ($r.ok) { $pos.Add($r.similarity); $okc++ } else { $skip++; Write-Host "  [skip] $($g.Name)：$($r.reason)" -ForegroundColor DarkGray }
        }
        Write-Host "  [$($g.Name)] 配对 $($pairs.Count)，有效 $okc"
    }

    for ($a = 0; $a -lt $negGroups.Count; $a++) {
        for ($b = $a + 1; $b -lt $negGroups.Count; $b++) {
            $fa = @($negGroups[$a].Files | ForEach-Object { if ($Map.ContainsKey($_)) { $Map[$_] } else { $_ } })
            $fb = @($negGroups[$b].Files | ForEach-Object { if ($Map.ContainsKey($_)) { $Map[$_] } else { $_ } })
            $cnt = 0
            foreach ($x in $fa) {
                foreach ($y in $fb) {
                    if ($cnt -ge $MaxPairsPerPerson) { break }
                    $r = Invoke-Verify -Source $x -Target $y
                    if ($r.ok) { $neg.Add($r.similarity); $cnt++ } else { $skip++; Write-Host "  [skip] 跨人对：$($r.reason)" -ForegroundColor DarkGray }
                }
                if ($cnt -ge $MaxPairsPerPerson) { break }
            }
            Write-Host "  [$($negGroups[$a].Name) x $($negGroups[$b].Name)] 有效配对 $cnt"
        }
    }
    return @{ Label = $Label; Pos = $pos.ToArray(); Neg = $neg.ToArray(); Skip = $skip }
}

$domains = @()
$domains += Invoke-Domain -Label '原图域' -Map @{}
if ($frameMap.Count -gt 0) { $domains += Invoke-Domain -Label '帧域(640/q0.72)' -Map $frameMap }

Write-Section '相似度分布与阈值扫描'
$grid = @(0..20) | ForEach-Object { [Math]::Round($_* 0.05, 2) }

$summary = @()
foreach ($d in $domains) {
    $posArr = $d.Pos; $negArr = $d.Neg
    Write-Host ''
    Write-Host "[$($d.Label)] 正样本 n=$($posArr.Count)  负样本 n=$($negArr.Count)  跳过 $($d.Skip)"
    if ($posArr.Count -eq 0 -or $negArr.Count -eq 0) {
        Write-Host '  样本不足，跳过该域的阈值分析' -ForegroundColor Yellow
        $summary += @{ Label = $d.Label; Rows = @(); Best = $null; Youden = $null; Enough = $false }
        continue
    }
    foreach ($pair in @(@('正样本(同人)', $posArr), @('负样本(异人)', $negArr))) {
        $arr = $pair[1]; $m = ($arr | Measure-Object -Average -Minimum -Maximum)
        Write-Host ("  {0,-12} n={1,4} min={2:N4} p05={3:N4} p50={4:N4} p95={5:N4} max={6:N4} mean={7:N4}" -f `
                $pair[0], $arr.Count, $m.Minimum, (Get-Percentile $arr 0.05), (Get-Percentile $arr 0.5), (Get-Percentile $arr 0.95), $m.Maximum, $m.Average)
    }
    $rows = foreach ($t in $grid) {
        $far = (@($negArr | Where-Object { $_ -ge $t }).Count) / $negArr.Count
        $frr = (@($posArr | Where-Object { $_ -lt $t }).Count) / $posArr.Count
        [PSCustomObject]@{ Threshold = $t; FAR = $far; FRR = $frr }
    }
    $feasible = @($rows | Where-Object { $_.FAR -le $TargetFar -and $_.FRR -le $TargetFrr } | Sort-Object -Descending)
    # Youden J = TPR - FPR = (1-FRR) - FAR，取最大者
    $youden = $rows | Sort-Object -Property @{ Expression = { (1 - $_.FRR) - $_.FAR } } -Descending | Select-Object -First 1
    $enough = ($posArr.Count -ge 20) -and ($negArr.Count -ge 20)
    if ($feasible.Count -gt 0) {
        Write-Host ("  满足 FAR<={0} 且 FRR<={1} 的最大阈值：{2}（FAR={3:P3}，FRR={4:P3}）" -f $TargetFar, $TargetFrr, $feasible[0].Threshold, $feasible[0].FAR, $feasible[0].FRR) -ForegroundColor Green
    } else {
        Write-Host ("  无阈值同时满足 FAR<={0} 与 FRR<={1} → 禁止据此设阈值" -f $TargetFar, $TargetFrr) -ForegroundColor Red
    }
    Write-Host ("  Youden J 最优：{0}（FAR={1:P3}，FRR={2:P3}）" -f $youden.Threshold, $youden.FAR, $youden.FRR)
    if (-not $enough) {
        Write-Host "  [warn] 有效配对量不足（门槛各 20 组）：仅供工具自检，不可用于生产阈值" -ForegroundColor Yellow
    }
    $summary += @{ Label = $d.Label; Rows = $rows; Best = $(if ($feasible.Count -gt 0) { $feasible[0] } else { $null }); Youden = $youden; Enough = $enough }
}

$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $ReportDir) { $ReportDir = $CalibDir }
$report = Join-Path $ReportDir "calibration-report-$ts.md"
$L = New-Object System.Collections.Generic.List[string]
$L.Add('# G2 相似度阈值标定报告')
$L.Add('')
$L.Add("- 生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$L.Add("- 接口：$ApiBase")
$L.Add("- 样本目录：$CalibDir")
$L.Add("- 目标：FAR <= $TargetFar，FRR <= $TargetFrr")
$L.Add('')
$L.Add('> 阈值依据以**帧域**为准（原图域会系统性高估相似度）。本报告不自动修改 ai-server 配置。')
$L.Add('')
foreach ($s in $summary) {
    $L.Add("## $($s.Label)")
    $L.Add('')
    if (-not $s.Rows -or $s.Rows.Count -eq 0) { $L.Add('- 样本不足，未做阈值分析'); $L.Add(''); continue }
    $d = $domains | Where-Object { $_.Label -eq $s.Label }
    $L.Add("- 有效配对：正 $($d.Pos.Count) / 负 $($d.Neg.Count)（跳过 $($d.Skip)）")
    $L.Add('')
    $L.Add('| 集合 | n | min | p05 | p50 | p95 | max | mean |')
    $L.Add('|---|---|---|---|---|---|---|---|')
    foreach ($pair in @(@('正样本(同人)', $d.Pos), @('负样本(异人)', $d.Neg))) {
        $arr = $pair[1]; $m = ($arr | Measure-Object -Average -Minimum -Maximum)
        $L.Add(("| {0} | {1} | {2:N4} | {3:N4} | {4:N4} | {5:N4} | {6:N4} | {7:N4} |" -f `
                    $pair[0], $arr.Count, $m.Minimum, (Get-Percentile $arr 0.05), (Get-Percentile $arr 0.5), (Get-Percentile $arr 0.95), $m.Maximum, $m.Average))
    }
    $L.Add('')
    $L.Add('| 阈值 | FAR | FRR |')
    $L.Add('|---|---|---|')
    foreach ($r in $s.Rows) { $L.Add(("| {0} | {1:P3} | {2:P3} |" -f $r.Threshold, $r.FAR, $r.FRR)) }
    $L.Add('')
    if ($s.Best) {
        $L.Add("- 满足目标的最大阈值：**$($s.Best.Threshold)**（FAR=$($s.Best.FAR.ToString('P3'))，FRR=$($s.Best.FRR.ToString('P3'))）")
    } else {
        $L.Add('- 无阈值同时满足目标 FAR/FRR → **不得设置 MEETING_FACE_SIMILARITY_THRESHOLD**')
    }
    $L.Add("- Youden J 最优：$($s.Youden.Threshold)（FAR=$($s.Youden.FAR.ToString('P3'))，FRR=$($s.Youden.FRR.ToString('P3'))）")
    if (-not $s.Enough) { $L.Add('- 有效配对量不足（门槛各 20 组）：**仅用于工具自检**，不构成 G2 通过依据') }
    $L.Add('')
}
$L.Add('## 结论')
$L.Add('')
$frameSummary = $summary | Where-Object { $_.Label -like '帧域*' } | Select-Object -First 1
if ($frameSummary -and $frameSummary.Best -and $frameSummary.Enough) {
    $L.Add("- **建议阈值（帧域）：$($frameSummary.Best.Threshold)**（FAR=$($frameSummary.Best.FAR.ToString('P3'))，FRR=$($frameSummary.Best.FRR.ToString('P3'))）")
    $L.Add('- 写入方式：由管理员显式设置 ai-server 的 `MEETING_FACE_SIMILARITY_THRESHOLD`（或同名环境变量），并复跑 G1/G2 报告')
} else {
    $L.Add('- **当前样本不足以标定生产阈值**：需按采集规范补齐本地真实样本（两人各 >= 10 张，人工确认分组）后重跑本工具')
    $L.Add('- 在此之前 `MEETING_FACE_SIMILARITY_THRESHOLD` 保持不设置，系统恒返回 `FACE_INSUFFICIENT`（只回传相似度、不产身份结论）')
}
$L.Add('')
$L.Add('> 写入 `MEETING_FACE_SIMILARITY_THRESHOLD` 属人工门禁动作，需评审本报告后显式设置。')
[System.IO.File]::WriteAllLines($report, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ''
Write-Host "报告已写出：$report" -ForegroundColor Green
if (-not ($summary | Where-Object { $_.Enough })) { exit 3 }
