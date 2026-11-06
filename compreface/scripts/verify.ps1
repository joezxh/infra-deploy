#Requires -Version 5.1
<#
.SYNOPSIS
    CompreFace 部署件验证 —— 自定义 core（YuNet 检测 + SFace 识别）落地后的契约证明。
.DESCRIPTION
    0. 离线权重清单与 SHA256 比对（YuNet 检测 + SFace 识别，缺失记 Skip）
    0b. 自定义 core 镜像存在性
    1. 外层 nginx 存活
    2. 无 X-API-Key 打检测接口应 401
    3. Face Detection 返回 box 与 probability（证明检测契约）
    4. Face Verification 两图 1:1 比对返回 similarity（证明 SP-3 唯一允许使用的能力）
    5. recognition / subjects 路径必须 404（证明 1:N 红线在部署层生效）
    6/7（可选开关）：V5 真实帧延迟 P50/P95、V8 recognition 残留巡检；默认关闭，不影响 9/9 基线。
    所有结论必须回写 README.md「实测留档」表；未回写前不得据此置位门禁。
.EXAMPLE
    .\scripts\verify.ps1
    .\scripts\verify.ps1 -CheckLatency -CheckResidual -FramePath D:\evidence\g1-frames\a\f_0001.jpg
#>
[CmdletBinding()]
param(
    [switch]$CheckLatency,
    [switch]$CheckResidual,
    [string]$FramePath = '',
    [int]$Samples = 20,
    [string]$PgHost = 'host.docker.internal',
    [string]$PgUser = 'postgres',
    [string]$PgDatabase = 'compreface'
)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

$envFile = Get-Content (Join-Path $Root '.env') -ErrorAction SilentlyContinue
if (-not $envFile) { Write-Host '[fail] 缺少 .env，请先运行 deploy.ps1' -ForegroundColor Red; exit 1 }
function Get-EnvValue($name) {
    $v = ($envFile | Where-Object { $_ -match "^$name=" } | Select-Object -First 1)
    if (-not $v) { return '' }
    ($v -replace "^$name=", '').Trim()
}
$apiKey = Get-EnvValue 'API_KEY'
$port = Get-EnvValue 'COMPREFACE_NGINX_PORT'; if (-not $port) { $port = '8050' }
$base = "http://127.0.0.1:$port"
$face = Join-Path $Root 'samples\face.jpg'
$face2 = Join-Path $Root 'samples\face_same_person.jpg'

$pass = 0; $fail = 0; $skip = 0
function Assert($name, $cond, $detail) {
    if ($cond) { Write-Host ("[ pass ] {0}  {1}" -f $name, $detail) -ForegroundColor Green; $script:pass++ }
    else { Write-Host ("[ FAIL ] {0}  {1}" -f $name, $detail) -ForegroundColor Red; $script:fail++ }
}
function Skip($name, $detail) {
    Write-Host ("[ skip ] {0}  {1}" -f $name, $detail) -ForegroundColor Yellow; $script:skip++
}
function Invoke-Multipart($path, $fields) {
    # Windows PowerShell 5.1 不支持 Invoke-RestMethod -Form，必须用 curl.exe
    $args = @('-s', '-w', "`n%{http_code}", '-H', "X-API-Key: $apiKey")
    foreach ($f in $fields) { $args += @('-F', $f) }
    $args += "$base$path"
    $raw = & curl.exe @args 2>$null
    $lines = @($raw -split "`n")
    return @{ Code = $lines[-1].Trim(); Body = (($lines | Select-Object -SkipLast 1) -join "`n") }
}

Write-Host '===== 0. 离线权重清单与 SHA256（缺失记 Skip，不误报服务不可用） =====' -ForegroundColor Cyan
$modelsDir = Join-Path $Root 'models'
$weights = @(
    @{ Name = 'YuNet-det'; File = (Get-EnvValue 'FACE_DET_MODEL'); Expected = (Get-EnvValue 'FACE_DET_SHA256') },
    @{ Name = 'SFace-rec'; File = (Get-EnvValue 'FACE_REC_MODEL'); Expected = (Get-EnvValue 'FACE_REC_SHA256') }
)
foreach ($w in $weights) {
    if (-not $w.File) { Skip "weights-$($w.Name)" '未在 .env 声明模型文件名'; continue }
    $weightPath = Join-Path $modelsDir $w.File
    if (-not (Test-Path $weightPath)) { Skip "weights-$($w.Name)" "权重文件未下载：$($w.File)"; continue }
    if (-not $w.Expected -or $w.Expected -like 'REPLACE*') {
        Skip "weights-$($w.Name)" 'SHA256 期望值未从官方发布页回填'; continue
    }
    $actual = (Get-FileHash -Path $weightPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert "weights-$($w.Name)" ($actual -eq $w.Expected.ToLowerInvariant()) `
        "expected=$($w.Expected) actual=$actual"
}

Write-Host ''
Write-Host '===== 0b. 自定义 core 镜像存在性 =====' -ForegroundColor Cyan
$coreImage = Get-EnvValue 'COMPREFACE_CORE_IMAGE'
if (-not $coreImage) {
    Skip 'core-image' '未在 .env 声明 COMPREFACE_CORE_IMAGE'
} else {
    $ok = $false
    try { & docker image inspect $coreImage 2>$null | Out-Null; $ok = ($LASTEXITCODE -eq 0) } catch { }
    Assert 'core-image' $ok "image=$coreImage"
}

Write-Host ''
Write-Host '===== 1. nginx 存活 =====' -ForegroundColor Cyan
try {
    $h = Invoke-RestMethod -Uri "$base/face-nginx-health" -TimeoutSec 10
    Assert 'nginx-health' ($h.status -eq 'ok') ($h | ConvertTo-Json -Compress)
} catch { Assert 'nginx-health' $false $_.Exception.Message }

Write-Host ''
Write-Host '===== 2. 无 X-API-Key 应 401 =====' -ForegroundColor Cyan
try {
    $r = Invoke-WebRequest -Uri "$base/face/api/v1/detection/detect" -Method POST -TimeoutSec 10
    Assert 'auth-401' $false "期望 401，实际 $($r.StatusCode)"
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Assert 'auth-401' ($code -eq 401) "实际 HTTP $code"
}

Write-Host ''
Write-Host '===== 3. Face Detection 返回 box / probability =====' -ForegroundColor Cyan
if (-not (Test-Path $face)) {
    Skip 'detection' "缺少 $face（请放入一张正面人脸 JPEG 到 samples/）"
} else {
    $r = Invoke-Multipart '/face/api/v1/detection/detect' @("file=@$face", 'det_prob_threshold=0.5')
    if ($r.Code -ne '200') {
        Assert 'detection' $false "HTTP $($r.Code) body=$($r.Body.Substring(0, [Math]::Min(200, $r.Body.Length)))"
    } else {
        try {
            $j = $r.Body | ConvertFrom-Json
            $first = @($j.result)[0]
            Assert 'detection' ($null -ne $first -and $null -ne $first.box -and $null -ne $first.box.probability) `
                ("faces=$(@($j.result).Count) probability=$($first.box.probability)")
        } catch { Assert 'detection' $false "返回体解析失败：$($_.Exception.Message) body=$($r.Body)" }
    }
}

Write-Host ''
Write-Host '===== 4. Face Verification 1:1：同人高分 / 异人低分 =====' -ForegroundColor Cyan
# 实测返回形态（1.2.0 + YuNet/SFace 插件）：
#   { "result": [ { "source_image_face": {...}, "face_matches": [ { "box": {...}, "similarity": 0.x } ] } ] }
$face3 = Join-Path $Root 'samples\face_other_person.jpg'
if (-not (Test-Path $face) -or -not (Test-Path $face2)) {
    Skip 'verification' "缺少 $face 或 $face2（需同一人两张照片）"
} else {
    try {
        $r = Invoke-Multipart '/face/api/v1/verification/verify' @("source_image=@$face", "target_image=@$face2")
        if ($r.Code -ne '200') {
            Assert 'verification-same' $false "HTTP $($r.Code) body=$($r.Body.Substring(0, [Math]::Min(200, $r.Body.Length)))"
        } else {
            $j = $r.Body | ConvertFrom-Json
            $simSame = @($j.result)[0].face_matches[0].similarity
            Assert 'verification-same' ($null -ne $simSame -and $simSame -gt 0.7) "同人 similarity=$simSame（期望 > 0.7）"
        }
        if (Test-Path $face3) {
            $r = Invoke-Multipart '/face/api/v1/verification/verify' @("source_image=@$face", "target_image=@$face3")
            if ($r.Code -ne '200') {
                Assert 'verification-diff' $false "HTTP $($r.Code) body=$($r.Body.Substring(0, [Math]::Min(200, $r.Body.Length)))"
            } else {
                $j = $r.Body | ConvertFrom-Json
                $simDiff = @($j.result)[0].face_matches[0].similarity
                Assert 'verification-diff' ($null -ne $simDiff -and $simDiff -lt 0.5) "异人 similarity=$simDiff（期望 < 0.5；G2 阈值另作本地标定）"
            }
        } else {
            Skip 'verification-diff' "缺少 $face3（异人照片，用于低分对照）"
        }
    } catch { Assert 'verification' $false "请求/解析失败：$($_.Exception.Message)" }
}

Write-Host ''
Write-Host '===== 5. 1:N 红线：recognition / subjects 路径不可达 =====' -ForegroundColor Cyan
try {
    $r = Invoke-WebRequest -Uri "$base/face/api/v1/recognition/recognize" -Method POST -TimeoutSec 10 `
        -Headers @{ 'X-API-Key' = $apiKey }
    Assert 'no-1n' ($r.StatusCode -eq 404) "期望 404，实际 $($r.StatusCode)"
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Assert 'no-1n' ($code -eq 404 -or $code -eq 401) "实际 HTTP $code（401/404 均视为未暴露）"
}

# ---------- 6. V5 真实帧延迟 P50/P95（可选，需 -CheckLatency） ----------
if ($CheckLatency) {
    Write-Host ''
    Write-Host '===== 6. V5 真实帧延迟（P50/P95） =====' -ForegroundColor Cyan
    $frame = if ($FramePath) { $FramePath } else { $face }
    if (-not (Test-Path -LiteralPath $frame)) {
        Skip 'v5-latency' "帧不存在：$frame（用 -FramePath 指定 G1 真实会中帧）"
    } else {
        $ms = @()
        foreach ($i in 1..$Samples) {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $null = & curl.exe -s -o NUL -X POST "$base/face/api/v1/detection/detect" `
                -H "X-API-Key: $apiKey" -F "file=@$frame"
            $sw.Stop()
            $ms += [math]::Round($sw.Elapsed.TotalMilliseconds)
        }
        $sorted = @($ms | Sort-Object)
        $p50 = $sorted[[math]::Floor($sorted.Count * 0.5)]
        $p95 = $sorted[[math]::Min($sorted.Count - 1, [math]::Ceiling($sorted.Count * 0.95) - 1)]
        Assert 'v5-latency' ($p95 -le 3000) "n=$($sorted.Count) P50=${p50}ms P95=${p95}ms（判据 ≤3000ms）"
        New-Item -ItemType Directory -Force (Join-Path $Root 'evidence') | Out-Null
        $v5 = @('# V5 真实帧延迟巡检', '',
            "- 时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", "- 帧：$frame",
            "- 样本：$($sorted.Count) 次 detection", "- P50：$p50 ms", "- P95：$p95 ms",
            '- 判据：P95 ≤ 3000ms', '',
            '> 回写 README §7 V5 行；须用 G1 采集的真实会中帧，官方样例大图不代表生产口径。')
        [System.IO.File]::WriteAllLines((Join-Path $Root 'evidence\v5-latency.md'), $v5,
            (New-Object System.Text.UTF8Encoding($false)))
    }
}

# ---------- 7. V8 recognition 残留巡检（可选，需 -CheckResidual） ----------
if ($CheckResidual) {
    Write-Host ''
    Write-Host '===== 7. V8 recognition 残留巡检 =====' -ForegroundColor Cyan
    $pgPass = Get-EnvValue 'POSTGRES_PASSWORD'
    if (-not $pgPass) {
        Skip 'v8-residual' '.env 无 POSTGRES_PASSWORD，跳过外部 PG 巡检'
    } else {
        $sql = "SELECT format('SELECT ''%I'' AS t, count(*) AS c FROM %I;', table_name, table_name) FROM information_schema.tables WHERE table_schema='public' AND (table_name ILIKE '%subject%' OR table_name ILIKE '%embedding%' OR table_name ILIKE '%face%') \gexec"
        try {
            $out = & docker run --rm -e "PGPASSWORD=$pgPass" postgres:15-alpine psql `
                -h $PgHost -U $PgUser -d $PgDatabase -At -F '|' -c $sql 2>&1
            if ($LASTEXITCODE -ne 0) { throw "psql exit=$LASTEXITCODE" }
            $rows = @($out | Where-Object { $_ -match '^[^|]+\|\d+\s*$' })
            $bad = @($rows | Where-Object { [int](($_ -split '\|')[1].Trim()) -gt 0 })
            Assert 'v8-residual' ($rows.Count -gt 0 -and $bad.Count -eq 0) `
                "相关表 $($rows.Count) 张，含残留 $($bad.Count) 张"
            New-Item -ItemType Directory -Force (Join-Path $Root 'evidence') | Out-Null
            $v8 = @('# V8 recognition 残留巡检', '',
                "- 时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
                "- 库：$PgHost/$PgDatabase", "- 相关表：$($rows.Count) 张，含残留 $($bad.Count) 张",
                '', '| 表 | 行数 |', '|---|---|') + @($rows | ForEach-Object {
                    $p = $_ -split '\|'; "| $($p[0].Trim()) | $($p[1].Trim()) |"
                }) + @('', '> 判据：subject/embedding 相关表行数必须为 0；回写 README §7 V8 行。')
            [System.IO.File]::WriteAllLines((Join-Path $Root 'evidence\v8-residual.md'), $v8,
                (New-Object System.Text.UTF8Encoding($false)))
        } catch {
            Skip 'v8-residual' "外部 PG 巡检不可用：$($_.Exception.Message)（需人工按 README §3 执行）"
        }
    }
}

Write-Host ''
Write-Host "===== 汇总：pass=$pass fail=$fail skip=$skip =====" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($skip -gt 0) { Write-Host '[warn] 存在 skip：含第 0 段权重校验在内的验证未完整，不得据此置 MEETING_FACE_POC_PASSED=true' -ForegroundColor Yellow }
Write-Host '[warn] 请把实测的镜像 tag、权重来源与 SHA256、返回体字段形态与 V5 延迟回写 README「实测留档」' -ForegroundColor Yellow
Write-Host '[warn] 门禁置位由 enable-face-poc.ps1 负责；本脚本通过不代表 G0–G3 留档齐备，投产前须补齐真人报告与法务/运维留档' -ForegroundColor Yellow
if ($fail -gt 0) { exit 1 }
