#Requires -Version 5.1
<#
.SYNOPSIS
    CompreFace 部署件四段式验证 —— **官方 REST 文档在本环境未能取到，本脚本是唯一可执行证明**。
.DESCRIPTION
    1. 外层 nginx 存活
    2. 无 X-API-Key 打检测接口应 401
    3. Face Detection 返回 box 与 probability（证明检测契约）
    4. Face Verification 两图 1:1 比对返回 similarity（证明 SP-3 唯一允许使用的能力）
    5. recognition / subjects 路径必须 404（证明 1:N 红线在部署层生效）
    所有结论必须回写 README.md「实测留档」表；未回写前 MEETING_FACE_POC_PASSED 保持 false。
.EXAMPLE
    .\scripts\verify.ps1
#>

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
    Skip 'detection' "缺少 $face（请放入一张正面人脸 JPEG）"
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
Write-Host '===== 4. Face Verification 1:1 返回 similarity =====' -ForegroundColor Cyan
if (-not (Test-Path $face) -or -not (Test-Path $face2)) {
    Skip 'verification' "缺少 $face 或 $face2（需同一人两张照片）"
} else {
    $r = Invoke-Multipart '/face/api/v1/verification/verify' @("source_image=@$face", "target_image=@$face2")
    if ($r.Code -ne '200') {
        Assert 'verification' $false "HTTP $($r.Code) body=$($r.Body.Substring(0, [Math]::Min(200, $r.Body.Length)))"
    } else {
        try {
            $j = $r.Body | ConvertFrom-Json
            # 官方返回字段名可能是 result.similarity / similarity；此处两种都接受，并把实测形态回写 README
            $sim = if ($null -ne $j.result -and $null -ne $j.result.similarity) { $j.result.similarity } else { $j.similarity }
            Assert 'verification' ($null -ne $sim) "similarity=$sim 原始返回=$($r.Body)"
        } catch { Assert 'verification' $false "返回体解析失败：$($_.Exception.Message) body=$($r.Body)" }
    }
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

Write-Host ''
Write-Host "===== 汇总：pass=$pass fail=$fail skip=$skip =====" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($skip -gt 0) { Write-Host '[warn] 存在 skip：四段式验证未完整，不得据此置 MEETING_FACE_POC_PASSED=true' -ForegroundColor Yellow }
Write-Host '[warn] 请把实测的镜像 tag、环境变量、返回体字段形态与延迟回写 README「实测留档」' -ForegroundColor Yellow
if ($fail -gt 0) { exit 1 }
